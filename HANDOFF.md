# gnumeric-cocoa — Handoff for Claude Code

Status: Phase 0 complete (2026-10-10): Gnumeric 1.12.62 builds from the submodule
and passes the smoke suite. No app code yet. Phase 1 waits on Xcode.app (§8,
question 3). `docs/progress.md` has the session log.
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
worked on Henry's plan on 2026-10-10. Xcode.app is required for `xcodebuild` and
XcodeGen projects; as of 2026-10-10 only the Command Line Tools are installed and the
Xcode install is pending Henry's `sudo` (§8, question 3). Anthropic still recommends auto mode in isolated
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
| Upstream engagement | Open a GNOME GitLab issue after Phase 0, with concrete findings and a specific request; no general announcement before working code exists. Henry posts it; Claude Code drafts it. | Maintainers can confirm or correct architecture assumptions and may accept small decoupling patches, keeping the patch series short. Contacting them before Phase 0 would mean announcing a project with no code. |
| Minimum macOS | 14 (Sonoma) | Sets the AppKit and SwiftUI feature level for dialogs. Set `MACOSX_DEPLOYMENT_TARGET = 14.0` in `project.yml`. |
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
5. **Done (draft).** Draft `docs/upstream-issue.md`: the text of a GNOME GitLab issue for `GNOME/gnumeric`. It should briefly describe the port, list the concrete Phase 0 findings, and make a specific request, typically: which engine entry points take `WBCGtk*` and could reasonably be moved to `WorkbookControl*`, and whether such patches would be accepted. Keep it short, factual, and free of promises about delivery. Henry reviews and posts it himself.
6. **Done** for the VERIFY items. Phase estimates: Phase 1 and 2 are unchanged in scope; Phase 2 additionally needs the seven decoupling patches (small). Phase 5 is the largest: 83 dialog entry points over 69 files, all GTK forms.

### Phase 1 — Skeleton, read-only viewer

- Generate the Xcode project from a text spec using **XcodeGen** (`project.yml`): a static-library target for the Objective-C bridge, a Swift app target, and test targets. Do not commit hand-edited `.pbxproj` churn; prefer plain-text, diffable build config. Requires Xcode.app, which is not installed (open question 3).
- Integrate the GLib main loop with the run loop. GTK's own `gdk/quartz/gdkeventloop-quartz.c` is a proven reference implementation. Keep all engine calls on the main thread; the engine is not thread-safe.
- `NSDocument` subclass that opens files through Gnumeric's file openers, so all supported formats work for free.
- Grid view: custom layer-backed, flipped `NSView` inside `NSScrollView`.
  - Draw only visible cells, using the existing cell-drawing code through cairo-quartz and Pango's CoreText backend. This gives rendering fidelity on day one.
  - Native Core Text rendering is a later optimization, not an MVP task.
- Row and column headers; sheet tabs (a simple segmented control or custom tab bar is fine for now).

### Phase 2 — Editing

- Cell editor: an `NSTextView` overlay positioned over the active cell. Commit through `cmd_set_text` (**verified**: `src/wbc-gtk-edit.c:413-424` uses `cmd_set_text`, `cmd_area_set_text`, and `cmd_area_set_array_expr`).
- Formula bar synchronized with the active cell.
- Undo/redo: keep Gnumeric's command stack as the source of truth. Wire the Edit menu and Cmd-Z to it rather than duplicating state in `NSUndoManager`.
- Keyboard navigation, range selection, copy/paste. Pasteboard: plain text, TSV, and Gnumeric's own clipboard format.
- Save, including uncompressed `.gnumeric` XML (Henry's preferred version-control-friendly format).

### Phase 2b — MVP completion

The MVP is Phases 1, 2, and this one. It must be usable for daily spreadsheet work on real files.

- **Read-only chart rendering:** draw existing `GogGraph` objects in their sheet positions via cairo-quartz. No chart creation or editing yet; files containing charts must round-trip through save unchanged.
- **Basic Format Cells dialog:** number format, alignment, font, borders, and fill, as the first SwiftUI form hosted in `NSHostingController`. This establishes the dialog pattern for Phase 5.
- Tag the release `v0.1.0` and write `docs/mvp-known-gaps.md` listing every GTK feature not yet ported.

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
- **Rendering:** golden-image tests that render a fixed set of fixture sheets to PNG and compare against committed references, with a tolerance. Store fixtures as uncompressed `.gnumeric` or CSV so diffs stay readable.
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
   **Blocked on Henry's machine**: the Xcode currently on the App Store requires macOS
   26.6, and the MacBook Air is on 26.5 (`mas install 497799835` reported this on
   2026-10-10). Henry picks one of:
   - (a) update macOS to 26.6 (System Settings → General → Software Update), then
     install Xcode from the App Store (no `sudo` needed), or
   - (b) stay on 26.5 and install an earlier Xcode 26.x build from
     https://developer.apple.com/download/all/?q=xcode (free Apple ID sign-in; the
     `.xip` expands into `/Applications/Xcode.app`).
   Either way, afterwards run in Terminal.app (the `!` prefix in Claude Code cannot
   prompt for a `sudo` password): `sudo xcode-select -s /Applications/Xcode.app` and
   `sudo xcodebuild -license accept`. Phase 1 starts once `xcodebuild -version` works.
   Recommendation: (a); it is a point update and keeps the SDK current.

## 9. First actions for the next session

1. Read `docs/progress.md` and §8. Check Xcode: `xcode-select -p` should be
   `/Applications/Xcode.app/Contents/Developer` and `xcodebuild -version` should work.
   If not, ask Henry whether §8 question 3 is done and meanwhile do only work that
   needs no `xcodebuild` (bridge C/Objective-C code can be compiled with `clang`
   against `pkg-config libspreadsheet-1.12`, as `Tests/EngineSmoke/run.sh` does).
   Then run `scripts/smoke-test.sh` once to confirm the engine build still works
   (a `brew upgrade` in between can change library versions; if goffice moved,
   re-pin per `docs/decisions.md` ADR-003).
2. If Henry has reviewed `docs/upstream-issue.md`, incorporate his edits; he posts it.
3. With Xcode available, start Phase 1: `project.yml`, the Objective-C bridge target
   with `module.modulemap`, engine init/shutdown in an XCTest, then the GLib main loop
   integration. The rendering path is already proven by `Tests/EngineSmoke/render.c`.
