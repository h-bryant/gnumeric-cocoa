# gnumeric-cocoa — Handoff for Claude Code

Status: MVP tagged `v0.1.0` on 2026-10-11 (Phases 0, 1, 2, 2b), and the
Phase 3 list done on 2026-10-11 and 2026-10-12 (menu commands, fill handle,
header resizing, merge, status bar, freeze panes, sheet management, Paste
Special, sorting with its dialog, autofilter, sheet resize, tab colors);
Phase 4 on 2026-10-12 has sheet objects (select, move, resize, delete,
restack, cut, copy, paste), the chart guru, images, and the chart editor.
The app opens, edits, formats, and saves real files with undo and
clipboard, built with Xcode 27 or the clang/swiftc scripts. `docs/mvp-known-gaps.md` lists what is missing. §8
questions 1 to 5 are resolved; upstream engagement is deferred (ADR-011).
`docs/progress.md` has the session log; §9 says where to pick up.
Owner: Henry.
Goal: a native macOS (AppKit) front end for Gnumeric that reuses Gnumeric's existing
C engine (`libspreadsheet`), `goffice`, and `libgsf`, replacing only the GTK user interface.
The **eventual goal is a full, feature-complete, working port**: everything the GTK
Gnumeric can do, done natively on macOS. The MVP defined below is a milestone on that
path, not the destination; no feature is out of scope, only deferred.

> **Read this whole file before acting.** Items originally marked **VERIFY** were checked
> against the 1.12.60 source and by running code on 2026-10-10. Each is now marked
> **VERIFIED** with corrections inline; the evidence is in `docs/architecture.md`.

---

## 1. Environment constraint (important)

This project needs macOS, Xcode, and the AppKit SDK. It **cannot** be built or run
on the usual isolated Debian VM. Run the session on the MacBook Air (M4, macOS Tahoe,
arm64). Run Claude Code in **auto mode** (`claude --enable-auto-mode`, then cycle to it
with Shift+Tab; or `permissionMode` in the repo's `.claude/settings.json`). Auto mode
worked on Henry's plan on 2026-10-10. Xcode.app 27 is installed (2026-10-10). Anthropic still recommends auto mode in isolated
environments, and there is no VM sandbox here, so do **not** use bypass-permissions mode,
and even in auto mode stop and ask Henry before doing any of the following:

- system-wide installs (Homebrew/MacPorts/Nix package installs, `sudo`),
- changes outside the repository directory,
- code signing or notarization with real credentials,
- any `git push`.

## 2. Decisions already made

| Topic | Decision | Rationale |
|---|---|---|
| UI toolkit | AppKit | SwiftUI cannot host a large virtualized, editable grid well; GTK/Quartz, Qt, wx are not truly native. |
| Language at the C boundary | Objective-C | Calls C and GObject directly; Swift interop with GObject macros and refcounting is awkward. |
| Language for app/UI layer | Swift, from Phase 1 | Dialogs can be SwiftUI hosted in AppKit via `NSHostingView`, shrinking Phase 5; value types and `let` bindings fit Henry's functional style; current AppKit docs and new APIs are Swift-first. Starting in Objective-C and switching later would discard the MVP UI code. |
| Scope | Full feature parity with GTK Gnumeric, eventually. MVP = viewer/editor + read-only chart rendering + basic Format Cells dialog (see Phase 2b). | Ships something usable early, tests the SwiftUI-dialog pattern before Phase 5, and keeps the fallback to the GTK build for everything else until parity is reached. |
| Upstream engagement | **Deferred (Henry, 2026-10-11):** the port proceeds without depending on any change to upstream Gnumeric. Engine changes the port cannot avoid are carried as small patches in `patches/`, written to stay upstreamable. `docs/upstream-issue.md` stays a draft, not posted. The git tag `upstream-baseline-2026-10-11` marks the point to return to if engagement resumes (`docs/decisions.md` ADR-011). | Keeps the project self-contained and unblocked; the option to engage later is preserved by the draft, the site list in `docs/architecture.md` §5, and the tag. |
| Minimum macOS | Homebrew's oldest supported release at release time; 15 (Sequoia) as of 2026-10-10 | Dependencies come from Homebrew, whose bottles target the OS they are built on; 14 is no longer supported there. `MACOSX_DEPLOYMENT_TARGET = 15.0` in `project.yml` and `LSMinimumSystemVersion` in `Info.plist` (`docs/decisions.md` ADR-009). |
| Repo name | `gnumeric-cocoa` | Matches convention (Qt, SDL, wxWidgets name Mac backends "cocoa"). |
| License | Same as Gnumeric: GPL-2.0-only OR GPL-3.0-only (confirmed: upstream ships `COPYING`, `COPYING-gpl2`, `COPYING-gpl3`) | Combined work links the GPL engine. AppKit linking is allowed under the GPL system-library exceptions. |
| Distribution | Direct download / Homebrew / MacPorts. **Not** the Mac App Store. | App Store terms are generally considered incompatible with the GPL. |
| Upstream relationship | Keep upstream Gnumeric unmodified as a git submodule; carry any needed changes as a patch series in `patches/` | Keeps changes small, reviewable, and upstreamable. |
| Dependency source | Homebrew (`/opt/homebrew`, arm64) for all third-party libraries and build tools, **including goffice**. Only Gnumeric itself is built from the pinned submodule. | Henry's choice. Homebrew has current `goffice` and `gnumeric` formulae with Tahoe arm64 bottles; `brew install --only-dependencies gnumeric` pulls the exact dependency set upstream needs. goffice moves to a submodule only if a patch to it becomes necessary. |

## 3. Architecture

```
┌──────────────────────────────────────────────────────────┐
│ App layer (Swift: AppKit + SwiftUI-hosted dialogs)       │
│  NSDocument subclass, window controllers, grid NSView,   │
│  formula bar, sheet tabs, dialogs, menus                 │
├──────────────────────────────────────────────────────────┤
│ Bridge layer (Objective-C, "GnmCocoa")                   │
│  - Cocoa implementations of WorkbookControl / SheetControl│
│  - GLib main loop ↔ NSRunLoop integration                │
│  - GOCmdContext impl (errors → NSAlert, progress)        │
│  - ObjC wrappers holding GObject refs (retain/release)   │
├──────────────────────────────────────────────────────────┤
│ Engine (upstream, C): libspreadsheet, goffice, libgsf,   │
│  GLib/GObject, cairo (Quartz backend), Pango (CoreText)  │
└──────────────────────────────────────────────────────────┘
```

### Key upstream concepts (all **VERIFIED** in Phase 0; details in `docs/architecture.md`)

- Gnumeric uses a model/view/control split:
  - `Workbook` (model) → `WorkbookView` → `WorkbookControl` (abstract), implemented for GTK by `WBCGtk` in `src/wbc-gtk.c`.
  - `Sheet` → `SheetView` → `SheetControl` (abstract), implemented by `SheetControlGUI` in `src/sheet-control-gui.c`.
  - **Central idea of the port:** write Cocoa subclasses of `WorkbookControl` and `SheetControl`. Most editing logic in `src/commands.c` (`cmd_*` functions, which also own undo/redo) takes a `WorkbookControl*`, so it should be reusable as-is.
    **Verified**, with exceptions: seven sites in `commands.c`, `cmd-edit.c`, and `undo.c` cast to `WBCGtk`/`SheetControlGUI` without a type check (`docs/architecture.md` §5). They are unreachable in Phase 1 but needed for Phase 2; `docs/upstream-issue.md` proposes the fixes. Both vtables are NULL-safe, so a Cocoa control can be built incrementally.
- `ssconvert` (`src/ssconvert.c`) is the reference for headless engine startup and shutdown (`gnm_init`, plugin loading, `gnm_shutdown`, a stderr command context). Copy its initialization sequence. **Verified**: no `gtk_init` anywhere in the path; the exact sequence is in `docs/architecture.md` §2 and reproduced in `Tests/EngineSmoke/headless.c`. The file is Latin-1 encoded: grep it with `LC_ALL=C`.
- Function libraries (`fn-stat`, `fn-math`, …) are plugins loaded at runtime as GModules. The app bundle must ship them and point the plugin search path at them. **Verified**: `GNUMERIC_PLUGIN_PATH` adds search directories; 50 plugins (41 Gnumeric, 9 goffice) load headless. Lib/data/locale directories themselves are compile-time constants with no environment override (`src/gutils.c`), which is a Phase 6 item.
- Cell text layout uses Pango (`GnmRenderedValue`). Cell drawing to a `cairo_t` lives roughly in `src/cell-draw.c`. Grid painting for GTK is `src/item-grid.c` on goffice's `GocCanvas`. **Verified**: `cell_draw()` in `src/cell-draw.c`, borders in `src/style-border.c`; `src/style.c` has a windowless Pango context fallback (cairo font map, 96 dpi) used whenever there is no GDK screen, and Pango's default font map on this machine is CoreText.
- Charts are `GogGraph` objects in goffice. They render to cairo, so they can draw into a `CGContext` via `cairo_quartz_surface_create_for_cg_context`. **Verified** by `Tests/EngineSmoke/render.c`: `sheet_object_draw_cairo_sized()` drew a chart from `samples/chart-tests.gnumeric` on a cairo-quartz surface with no display.

### Structural constraint: GTK stays linked

A GTK-free build is **not** a realistic goal. goffice itself depends on GTK (its
Homebrew formula requires `gtk+3`), and `libspreadsheet` is built as one library
containing both engine and GTK front end. `ssconvert` nonetheless runs headless
(it is widely used on servers without a display), which proves the engine works
with GTK linked but never initialized for display.

So the working model is: GTK 3 (Quartz backend, from Homebrew) is linked and
bundled, but no GTK window, widget, or `GocCanvas` is ever created. Phase 0 must
establish:

- exactly how `ssconvert` initializes the engine without a display, and whether
  any `gtk_init` call is involved,
- which engine entry points unavoidably pull in GTK widgets (e.g., anything taking
  `WBCGtk*` rather than `WorkbookControl*`), so the bridge avoids them,
- the bundle-size cost of shipping GTK and its dependencies.

The second item determines how much of `commands.c` and the dialog logic is
reusable, and therefore the size of the project.

Phase 0 result (2026-10-10): all three are established in `docs/architecture.md`.
`configure.ac` has a `--without-gtk` option that deliberately errors out, so the
"linked but never initialized" model is the only supported one. The dylib closure of
libspreadsheet plus all plugins is about 45 MB, plus up to 23 MB of locale data.

## 4. Phased plan

Each phase ends with a commit-ready state and a short entry in `docs/progress.md`.

### Phase 0 — Reconnaissance (no app code)

1. **Done.** Added upstream Gnumeric as a submodule (GNOME GitLab: `GNOME/gnumeric`), pinned to `GNUMERIC_1_12_62`, matching Homebrew's goffice 0.10.62 (Henry chose to upgrade from the 0.10.60 / 1.12.60 that was installed). The pairing rule stands: the tag tracks the goffice version Homebrew installs.
2. Install dependencies with Homebrew:
   - `brew install --only-dependencies gnumeric` gives the runtime and build dependencies upstream's formula needs (glib, cairo, pango, gtk+3, libgsf, libxml2, librsvg, gettext, goffice, …). Read the formula (`brew cat gnumeric`) for the configure flags Homebrew uses on macOS and reuse them.
   - Add build tools: `autoconf`, `automake`, `libtool`, `pkgconf`, `intltool`, `itstool`, `bison`, `xcodegen`. **Verified** names with `brew info`; two more are required by `autogen.sh`: `gtk-doc` (for `gtkdocize`) and `yelp-tools` (for `yelp.m4`). macOS's bison 2.3 is what Homebrew's own formula uses, so Homebrew `bison` is optional. Installed on 2026-10-10 by running `scripts/build-deps.sh` with Henry's approval.
   - Record the final list in a `Brewfile` at the repo root and install with `brew bundle`. Record Homebrew and formula versions in `docs/build.md`. **Done** (`Brewfile`, `docs/build.md`).
   - Set `PKG_CONFIG_PATH` and `ACLOCAL_PATH` for keg-only formulae (e.g., `libxml2`, `gettext`) in `scripts/build-deps.sh`, not in the shell profile. **Done** as `scripts/env.sh` (sourced by every script); `scripts/build-deps.sh` runs `brew bundle` and reports. `libxml2` and `zlib` are keg-only; `gettext` is linked normally now.
   - Confirm Homebrew's `cairo` has the Quartz backend and `pango` has the CoreText font map (`pkg-config --exists cairo-quartz pangocairo`; inspect the pango build). Phase 1 rendering depends on both. **Done**: both present, and GTK is built with the Quartz backend only.
   - Per §1, ask Henry before running `brew` installs.
3. **Done.** Build Gnumeric from the submodule with autotools against the Homebrew libraries. Run the built `ssconvert` on a sample `.gnumeric` and `.xlsx` with no display to prove the engine works headless. `scripts/build-gnumeric.sh` built 1.12.62 unpatched on the first run; `scripts/smoke-test.sh` passes against `build/prefix` (15 ssconvert conversions plus the C smoke programs, which render cells and a chart to cairo-quartz and save both formats).
4. **Done.** Produce `docs/architecture.md` covering:
   - the real `WorkbookControl`/`SheetControl` vtables and which methods a new front end must implement,
   - a GTK-dependency map of `src/` (e.g., `grep -l gtk` plus link analysis),
   - the init/shutdown sequence from `ssconvert.c`.
5. **Done (draft, not posted).** Draft `docs/upstream-issue.md`: the text of a GNOME GitLab issue for `GNOME/gnumeric`. It should briefly describe the port, list the concrete Phase 0 findings, and make a specific request, typically: which engine entry points take `WBCGtk*` and could reasonably be moved to `WorkbookControl*`, and whether such patches would be accepted. Keep it short, factual, and free of promises about delivery. Henry decided on 2026-10-11 not to engage upstream for now (§2); the draft is kept for later.
6. **Done** for the VERIFY items. Phase estimates: Phase 1 and 2 are unchanged in scope; Phase 2 additionally needs the seven decoupling patches (small). Phase 5 is the largest: 83 dialog entry points over 69 files, all GTK forms.

### Phase 1 — Skeleton, read-only viewer

- Generate the Xcode project from a text spec using **XcodeGen** (`project.yml`): a static-library target for the Objective-C bridge, a Swift app target, and test targets. Do not commit hand-edited `.pbxproj` churn; prefer plain-text, diffable build config. Requires Xcode.app, which is not installed (open question 3).
- Integrate the GLib main loop with the run loop. GTK's own `gdk/quartz/gdkeventloop-quartz.c` is a proven reference implementation. Keep all engine calls on the main thread; the engine is not thread-safe.
- `NSDocument` subclass that opens files through Gnumeric's file openers, so all supported formats work for free.
- Grid view: custom layer-backed, flipped `NSView` inside `NSScrollView`.
  - Draw only visible cells, using the existing cell-drawing code through cairo-quartz and Pango's CoreText backend. This gives rendering fidelity on day one.
  - Native Core Text rendering is a later optimization, not an MVP task.
- Row and column headers; sheet tabs (a simple segmented control or custom tab bar is fine for now).

Status 2026-10-10: everything above exists and runs from the swiftc build
(`scripts/run-app.sh`), verified on `chart-tests.gnumeric` and
`format-tests.gnumeric`: the bridge (`Sources/Bridge`), the run loop
integration, `WorkbookDocument` opening through the engine's openers, the
flipped grid view drawing through cairo-quartz with a native selection, mouse
and keyboard selection, column and row headers (plain views beside the scroll
view since 2026-10-11; `NSRulerView` left the grid invisible on macOS 26) with
click-to-select and a select-all corner, zoom (View menu), and scrolling sheet
tabs; Xcode builds it and runs the XCTest bundle. Not yet: frozen panes
(Phase 3) and right-to-left sheets (Phase 7). Details in `docs/progress.md`.

### Phase 2 — Editing

- Cell editor: an `NSTextView` overlay positioned over the active cell. Commit through `cmd_set_text` (**verified**: `src/wbc-gtk-edit.c:413-424` uses `cmd_set_text`, `cmd_area_set_text`, and `cmd_area_set_array_expr`).
- Formula bar synchronized with the active cell.
- Undo/redo: keep Gnumeric's command stack as the source of truth. Wire the Edit menu and Cmd-Z to it rather than duplicating state in `NSUndoManager`.
- Keyboard navigation, range selection, copy/paste. Pasteboard: plain text, TSV, and Gnumeric's own clipboard format.
- Save, including uncompressed `.gnumeric` XML (Henry's preferred version-control-friendly format).

Status 2026-10-11: cell editor, formula bar editing, undo/redo on the engine's
stack, Delete, the engine's clipboard (region copy/cut/paste with marching
ants, text import from other applications), and saving `.gnumeric`,
uncompressed `.xml`, and `.xlsx` through `NSDocument` exist
(`docs/progress.md`); the editor takes the cell's own font and alignment.

### Phase 2b — MVP completion

The MVP is Phases 1, 2, and this one. It must be usable for daily spreadsheet work on real files.

- **Read-only chart rendering:** draw existing `GogGraph` objects in their sheet positions via cairo-quartz. No chart creation or editing yet; files containing charts must round-trip through save unchanged. **Done** (Phase 1 drew them from the start; round trips are in the smoke tests).
- **Basic Format Cells dialog:** number format, alignment, font, borders, and fill, as the first SwiftUI form hosted in `NSHostingController`. This establishes the dialog pattern for Phase 5. **Done 2026-10-11** (`FormatCellsView`, `FormatCellsModel`, `GnmCellFormat`).
- Tag the release `v0.1.0` and write `docs/mvp-known-gaps.md` listing every GTK feature not yet ported. **Done 2026-10-11**: tag `v0.1.0` (local), `docs/mvp-known-gaps.md` from the GTK menu structure (202 items) plus non-menu features.

### Phase 3 — Spreadsheet features

- Fill and autofill, insert/delete rows and columns, freeze panes, column and row resizing.
- Number-format and Format Cells dialog (native `NSWindow` sheets).
- Function autocomplete in the editor.

### Phase 4 — Charts and objects

- Selection and move/resize handles for charts, images, and other sheet objects.
- Chart creation (the chart guru) and full chart editing.

### Phase 5 — Dialogs and tools

- Port the remaining dialogs by usage frequency. The statistical analysis tools come last; they are many and mostly forms.

### Phase 7 — Feature parity

- Work through `docs/mvp-known-gaps.md` until it is empty: every menu item, dialog, tool, plugin, and file format of the GTK build has a native equivalent.
- Maintain `docs/parity.md`, a checklist of GTK Gnumeric features with status (ported / partial / not started). Generate the initial list from the GTK build's menus and `src/dialogs/`.
- Parity, not polish, is the exit criterion; polish continues afterwards.

### Phase 6 — Packaging

- Bundle dylibs and plugins inside the `.app` with rewritten install names (`dylibbundler` 1.0.5 is in Homebrew; `gtk-mac-bundler` is not a Homebrew formula, so plan on `dylibbundler` plus a script; **verified**). Also ship compiled GSettings schemas and set `GSETTINGS_SCHEMA_DIR`, and settle how lib/data/locale paths are found (`docs/architecture.md` §10).
- Ad-hoc signing for development; Developer ID signing and notarization for releases.
- Include the sources/licenses of all bundled third-party libraries (GLib, cairo, Pango, libxml2, …). These are not covered by the system-library exception.

## 5. Testing

- **Engine:** upstream's `make check` expects an active X session and has known failures even on Linux, so do not treat it as a gate on macOS. Instead, keep a small `ssconvert`-based smoke suite (open, recalc, convert a fixed set of fixtures) and run it after every dependency change.
- **Bridge:** XCTest unit tests for init/shutdown, document open/save round-trips, and command execution through the Cocoa `WorkbookControl`.
- **Rendering:** golden-image tests that render a fixed set of fixture sheets to PNG and compare against committed references, with a tolerance. Store fixtures as uncompressed `.gnumeric` or CSV so diffs stay readable. Until they exist, `GNM_SNAPSHOT` (`docs/build.md`) is the headless check: compare the grid capture with the whole-window one, which reflected the screen when the grid went blank on 2026-10-11.
- **CI:** later, GitHub Actions macOS arm64 runners.

## 6. Conventions for this repo

- **Commits:** small, one logical change each; imperative subject lines.
- **Upstream changes:** never edit inside the submodules. Write patches into `patches/NNNN-description.patch` and apply them in the build script, with an explanatory header in each patch.
- **Style:**
  - Prefer a functional style where it fits: pure helper functions, immutable value objects in the bridge, minimal shared mutable state.
  - Object-oriented structure is expected where AppKit and GObject demand it (subclassing `NSView`, `NSDocument`, GObject classes).
- **Language boundary:**
  - The bridge (`Sources/Bridge/`) is Objective-C and is the only code that includes GLib, goffice, or Gnumeric headers. Swift never sees a GObject pointer.
  - Bridge headers are written for Swift consumption: `NS_ASSUME_NONNULL_BEGIN`/`END` with explicit `nullable` where needed, `NS_SWIFT_NAME` on every class and method, lightweight generics on collections, `NS_ENUM`/`NS_OPTIONS` for enums, and `NSError **` out-parameters for failures so Swift gets `throws`.
  - Expose the bridge to Swift as a Clang module (`module.modulemap`), not a bridging header, so it also works from test targets.
  - All engine access is main-thread only. Mark every bridge class `@MainActor` from the Swift side (via `NS_SWIFT_UI_ACTOR` on the ObjC declarations) and build the Swift target in Swift 6 language mode with strict concurrency checking from the start; retrofitting it later is painful.
  - Dialogs: prefer SwiftUI views hosted in `NSHostingController` for forms (Format Cells, preferences, analysis tools). Keep the grid, headers, formula bar, and cell editor as custom AppKit views.
- **Ownership:** every ObjC wrapper that holds a GObject must `g_object_ref` on init and `g_object_unref` in `dealloc`. Document ownership in the header comment.
- **File formats:** text and diffable formats wherever possible (`project.yml`, Markdown docs, CSV/XML fixtures).
- **Documentation:** keep `docs/progress.md` (dated entries) and `docs/decisions.md` (ADR-style: context, decision, consequences) up to date.

## 7. Proposed initial layout

```
gnumeric-cocoa/
├── HANDOFF.md            # this file
├── CLAUDE.md             # short pointer to HANDOFF.md + build/test commands once known
├── COPYING               # GPL texts matching upstream
├── project.yml           # XcodeGen spec
├── Brewfile              # Homebrew dependency list
├── upstream/
│   └── gnumeric/         # submodule, pinned tag (goffice comes from Homebrew)
├── patches/
├── scripts/              # build-deps.sh, apply-patches.sh, bundle.sh
├── Sources/
│   ├── Bridge/           # Objective-C: WBC/SC subclasses, runloop glue, cmd context, module.modulemap
│   └── App/              # Swift: AppDelegate, Document, GridView, editors, SwiftUI dialogs
├── Tests/
│   ├── BridgeTests/
│   └── RenderingTests/   # fixtures + golden PNGs
└── docs/
    ├── architecture.md
    ├── build.md
    ├── upstream-issue.md # Phase 0 deliverable; Henry posts it
    ├── mvp-known-gaps.md # written at v0.1.0
    ├── parity.md         # feature-parity checklist, Phase 7
    ├── decisions.md
    └── progress.md
```

## 8. Open questions (ask Henry before deciding)

Add new ones here as they arise, and do not resolve them unilaterally.

1. **Homebrew installs.** Resolved 2026-10-10: Henry approved, and
   `scripts/build-deps.sh` was run (`brew bundle` of the `Brewfile`). `mas` was also
   installed, outside the `Brewfile`, to fetch Xcode.
2. **Version pairing.** Resolved 2026-10-10: Henry chose to upgrade. Homebrew goffice
   0.10.62 / gnumeric 1.12.62 are installed, the submodule is pinned to
   `GNUMERIC_1_12_62`, and `patches/` is empty.
3. **Xcode.** Decided 2026-10-10: install Xcode.app and keep the XcodeGen decision.
   Henry took option (a): the machine is on macOS 26.7.1, so the App Store's
   Xcode 27.0 installs now (App Store, or `mas install 497799835`). Still to do,
   in Terminal.app (the `!` prefix in Claude Code cannot prompt for a `sudo`
   password): `sudo xcode-select -s /Applications/Xcode.app` and
   `sudo xcodebuild -license accept`. Then `xcodebuild -version` works and
   `scripts/gen-xcconfig.sh && xcodegen generate && xcodebuild -scheme
   GnumericCocoa build` is the first thing to try. Until then the clang/swiftc
   scripts (`docs/build.md`) build and run everything.
4. **Deployment target versus Homebrew bottles.** Resolved 2026-10-10: the minimum
   macOS follows Homebrew's oldest supported release (15 today); `project.yml` and
   `Info.plist` say 15.0. See `docs/decisions.md` ADR-009.
5. **Bundle identifier and preferences domain.** Resolved 2026-10-10:
   `io.github.h-bryant.gnumeric-cocoa`; preferences persist by default in
   `~/Library/Preferences/io.github.h-bryant.gnumeric-cocoa.plist`
   (`GNM_PERSIST_PREFS=0` for a run without). See ADR-010.

## 9. First actions for the next session

1. Read `docs/progress.md` (latest entry) and §8. Run `scripts/smoke-test.sh`
   (ssconvert, engine programs, bridge tests). If goffice moved under a `brew
   upgrade`, re-pin per `docs/decisions.md` ADR-003 and re-run
   `scripts/gen-xcconfig.sh`.
2. Build with Xcode: `scripts/gen-xcconfig.sh && xcodegen generate && xcodebuild
   -scheme GnumericCocoa build` (works since 2026-10-10; `docs/build.md`), and
   run the XCTest bundle with `scripts/test-xcode.sh` (`xcodebuild test` itself
   waits on Henry enabling developer mode: `sudo DevToolsSecurity -enable`).
3. Upstream engagement is deferred (§2, ADR-011): do not post or extend
   `docs/upstream-issue.md`; keep any engine patch minimal and upstreamable.
4. Henry has used the app once (2026-10-11, confirming the blank-grid fix).
   Everything Phase 3 added after that (fill handle, header resizing, the
   status pull-down, freeze panes, tab context menu, the Paste Special,
   size, resize, tab color, sort, and filter sheets, the filter buttons
   and their pop-up, the object handles and drags, the chart guru, the
   image open panel, the chart editor) is verified only
   headlessly: ask what he sees before
   changing UI behavior, and take his report over the captures. First
   thing to ask: edit, ⌘S, ⌘Q, and Save As to a new name and to `.xml`
   (`docs/progress.md`, "Quit did nothing after a save (fixed)").
5. Phase 3 (`docs/mvp-known-gaps.md` says what the MVP lacks). Done on
   2026-10-11 and 2026-10-12: insert/delete rows and columns, hide and
   unhide, clear variants (filtered ones too), fill and autofill (fill
   handle), column and row sizes with header drag-resizing, merge, recalc,
   the auto-expression in the tab bar, freeze panes, sheet management,
   Paste Special, quick sort and the Sort dialog, autofilter, sheet resize,
   tab colors. Phase 4 started the same day: objects are selected,
   moved, resized, deleted, and restacked (`GnmSheetObject`,
   `Tests/BridgeTests/objects.m`), and Insert → Chart… builds a chart
   from the selection with every goffice plot type (`GnmPlotType`,
   `ChartGuru.swift`); objects cut, copy, and paste, and images come
   from files or the pasteboard; the chart editor (`GnmChartEditor`,
   `ChartEditorWindow.swift`, `Tests/BridgeTests/chart.m`) edits a copy
   of the graph and commits it as "Reconfigure Graph", changes a plot's
   type in place, and objects save as image files. Phase 5 began the
   same day with the everyday items (File → New, Go To and the name box,
   Insert and Delete Cells, the current date and time, Save As CSV) and
   Find and Replace (`GnmSearch`, `FindPanel.swift`, `search.m`), and
   the Settings window (`GnmPreferences`, `PreferencesWindow.swift`,
   `preferences.m`; the compression level is a preference now, Henry's
   0 in the app's defaults), and Export as Text with the GTK dialog's
   options (`GnmTextExport`, `TextExportSheet.swift`, `text_export.m`).
   The text import assistant followed (`GnmTextImport`,
   `TextImportAssistant.swift`, `text_import.m`), then cell comments
   (markers, tool tips, the editor; `comments.m`) and defined names
   (`GnmNames`, `NamesDialog.swift`, `names.m`; the static link needs
   `-ObjC` for the bridge's categories), Fill Series (the engine's
   analysis tool command; patch 0003 fixes its undo-then-redo double
   free), and Text to Columns (the import assistant over the selection).
   Goal Seek (Tools menu) and conditional formatting (Format menu;
   `GnmConditionalFormat`, `ConditionalFormatDialog.swift`,
   `conditional.m`), twelve analysis tools (Tools → Statistics:
   descriptive statistics, correlation, covariance, ranks, regression,
   two means, two variances, single-factor ANOVA, sampling, moving
   average, exponential smoothing; `GnmAnalysis`, `AnalysisDialog.swift`,
   `analysis.m`) and data validation (Data → Validation…;
   `GnmValidation.h`, `ValidationDialog.swift`, the grid's entry check,
   `validation.m`) and hyperlinks (Insert → Hyperlink…; `GnmHyperlink.h`,
   `HyperlinkDialog.swift`, the grid's click and tool tip, `hyperlink.m`)
   the Solver (Tools → Solver…; `GnmSolver.h`, `SolverDialog.swift`,
   `solver.m`, engine patch 0004), and printing (File → Page Setup…,
   Print…, Print Area; `GnmPrinting.h`, `PrintSupport.swift`,
   `printing.m`), range selection by mouse while typing a formula
   (`GnmFormulaEditing.h`, `GridView.takeFormulaRange`,
   `formula_range.m`), the font shortcuts, autocompletion, and the
   function selector (Insert → Function…; `GnmFunctions.h`,
   `FunctionSelectorDialog.swift`, `functions.m`) followed, then
   keyboard range selection in the editor (arrows, Shift, ⌘ for the
   data's edge), array formulas (⇧⌘Return or ⌃⇧Return;
   `GnmSheet.enterArrayFormula`), and ⌘-arrow jumps on the grid
   (`sheet_find_boundary_*`), then the fifteen remaining statistics
   tools on the analysis pattern with the GTK's Statistics menu groups
   (patch 0005 for the frequency and histogram tools' double free).
   The Solver then got the GTK dialog's run page: a progress sheet with
   the status, the objective so far, the elapsed time, and a Stop button
   over `GnmSolverRun` (start, poll, stop, finish), and the in-cell editor
   took the cell's font, colors, and alignment (`formatOfCellAtColumn:`,
   `resolvedFontFamilyForName:`); Format → Sheet's display toggles and
   the Zoom dialog followed (`toggleDisplayOption:`, `cmd_zoom`), then
   Data → Table…, Fill → Tabulate Dependency…, and the random
   generators (`GnmWhatIf.h`, `GnmRandomNumbersAnalysis`, `whatif.m`).
   Outlines followed (`GnmOutline.h`, the header strips in
   `SheetHeaderView.swift`, `outline.m`), then the advanced filter,
   sheet Hide / Unhide, and full screen (`GnmAdvancedFilter`,
   `setSheet:visible:`, `filter_visibility.m`), and the Sort dialog's
   six key rows and locale, and Data → Consolidate… and Shuffle…
   (`GnmConsolidateAnalysis`, `shuffleRange:by:`), and the function
   tooltips under the in-cell editor with F4's completion and reference
   cycling (`functionTooltipForText:cursorAt:`,
   `formulaText:cursorAt:cycleReferenceIn:`), and Edit → Sheet → Manage
   Sheets… (`ManageSheetsDialog.swift`, `setSheet:protected:`,
   `sortSheetsAscending:`), and Tools → Plug-ins… (`GnmPlugins.h`,
   `PluginManagerDialog.swift`, `plugins.m`), and on 2026-10-13 Tools →
   Scenarios and Simulation… (`GnmScenarios.h`, `ScenariosDialog.swift`,
   `SimulationDialog.swift`, `scenarios.m`), and Format → AutoFormat…
   (`GnmAutoFormat.h`, `AutoFormatDialog.swift`, `autoformat.m`; engine
   patch 0008), and the widget editors with Insert → Object
   (`GnmWidgets.h`, `WidgetDialog.swift`, `widgets.m`), and the toolbar
   (`WorkbookToolbar.swift`, `GnmNumberFormats.h`), and drag and drop
   of cells, files, and sheet tabs (`GnmDragging.h`), and multi-line
   editing (Option+Return; the editor and the formula bar grow), and
   Edit → Select → Array/Depends/Inputs, Format → Workbook…, File →
   Properties… (`GnmWorkbookProperties.h`, `properties.m`), and the
   toolbar's indent, script, border, and color items, and widgets that
   act (`GnmSheet (WidgetActions)`, `GridView.actOnWidget`), and Edit →
   Clear → Hyperlinks, Select → Next Object, the Format → Font submenu,
   page breaks with Show Print Area, the Help menu, File → Send To…, and
   Tools → Auto Correct… and Auto Save…, Data → Merge… (engine patch
   0009), Tools → Compare Sheets… (`GnmCompare.h`,
   `SheetCompareDialog.swift`), the Format Cells Protection page, the
   shapes with the object toolbar's pull-down, Go to Top/Bottom/First/
   Last, the marching ants' animation, and File → Print Preview
   (`PrintPreviewWindow.swift`), the Sort dialog's remembered setups,
   the Settings' Tools, markers, and Screen entries, View → Status Bar,
   tab text colors, and the Properties dialog's Statistics and
   Calculation pages, and File → Repeat Export.  Next, by usage: the
   remaining "partial" rows of `docs/mvp-known-gaps.md` (custom
   document properties, the sheet direction) and the "no" rows (ViewNew,
   data slicers, goffice components).
6. Headless checks for all of it: `GNM_SNAPSHOT=out.png scripts/run-app.sh
   file` plus `GNM_SNAPSHOT_TYPE`, `_FORMAT`, `_PHASE3`, `_FREEZE`,
   `_SHEETS`, `_FILTER`, `_OBJECTS`, `_CHART`, `_EDITOR`, `_EVERYDAY`, `_FIND`, `_PREFS`, `_TEXT`, `_IMPORT`, `_COMMENT`, `_NAMES`, `_FILL`, `_GOAL`, `_COND`, `_STATS`, `_VALID`, `_LINK`, `_SOLVE`, `_PRINT`, `_FORMULA`, `_FUNC`, `_ZOOM` (`docs/build.md`); compare `out.png` with
   `out-window.png`. Engine fixes go to `patches/` (0001 decouplings, 0002
   Merge and Center, 0003 analysis tool undo, 0004 solver constant bounds);
   `scripts/build-gnumeric.sh` re-applies them and takes a few minutes
   (about half a minute when only one source file changed).
