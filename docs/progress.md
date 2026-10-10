# Progress

## 2026-10-10: Phase 0 reconnaissance

- Environment confirmed: macOS 26.5 arm64, Homebrew 7.0.9, Command Line Tools
  only (no Xcode.app). Auto mode worked for the session.
- Added `upstream/gnumeric` submodule pinned to `GNUMERIC_1_12_60`; copied the
  three `COPYING*` files; added `.gitignore`, `Brewfile`, `scripts/`,
  `patches/0001-*` (Homebrew's `sstest.c` fix for 1.12.60).
- Verified every **VERIFY** item in `HANDOFF.md` against source; findings in
  `docs/architecture.md`: control vtables, GTK dependency map, the init
  sequence, the WBCGtk-requiring sites, bundle size.
- Proved the engine headless on this machine with Homebrew's
  `libspreadsheet`: `Tests/EngineSmoke/headless.c` and `render.c` open
  `.gnumeric` and `.xlsx`, recalc, draw cells and a chart on cairo image and
  cairo-quartz surfaces (Pango CoreText backend), and save both formats.
  `scripts/smoke-test.sh` passes.
- Found and fixed a trap: GSettings on macOS is `NSUserDefaults`, keyed by
  process name; a scratch run with config persistence on left
  `~/Library/Preferences/headless.plist` with plugin file states and no active
  list, after which no plugins loaded under that name. Removed that plist
  (`defaults delete headless`); the smoke programs now disable persistence and
  fail on engine warnings. Details in `docs/architecture.md` §2.
- Drafted `docs/upstream-issue.md` for Henry to review and post.
- Open questions put to Henry (`HANDOFF.md` §8): Homebrew installs, version
  pairing, Xcode.

## 2026-10-10, later: decisions applied, engine built

- Henry's answers: run `build-deps.sh`; upgrade to 1.12.62; use Xcode.
- `brew upgrade goffice gnumeric` (0.10.62 / 1.12.62, with gtk+3 3.24.52_1,
  libgsf 1.14.60, librsvg 2.63.2, libxml2 2.15.4, pango 1.58.2 moving up), then
  `scripts/build-deps.sh` installed autoconf, automake, libtool, intltool,
  itstool, gtk-doc, yelp-tools, xcodegen.
- Submodule re-pinned to `GNUMERIC_1_12_62`; `patches/0001` dropped (the fix is
  upstream). Every line reference in `docs/architecture.md` and
  `docs/upstream-issue.md` re-located for 1.12.62; the GTK dependency survey
  re-run (82 of 128 `src/*.c` files are GTK-free; same seven unguarded
  `WBCGtk` sites). New in 1.12.62: ssconvert adds `gtk_get_option_group
  (FALSE)` but still never calls `gtk_init`.
- `scripts/build-gnumeric.sh` built the engine unpatched on the first run;
  `scripts/smoke-test.sh` passes against `build/prefix`. Details in
  `docs/build.md`.
- Xcode: installed `mas`; `mas install 497799835` needs `sudo`, and Henry's
  attempt showed the App Store's Xcode requires macOS 26.6 while the machine
  is on 26.5. Options and the follow-up commands are in `HANDOFF.md` §8,
  question 3. Phase 1 starts after that.
- Session ended here. Working tree clean; all work committed on `main`,
  nothing pushed. `build/` (ignored) holds the built engine; `rm -rf build &&
  scripts/build-gnumeric.sh` recreates it in a few minutes.

## 2026-10-10, third session: Phase 1 bridge and read-only viewer

- Environment: macOS is now 26.7.1 (Henry took option (a) of `HANDOFF.md`
  §8 question 3), so the App Store's Xcode 27.0 is installable, but Xcode.app
  is still absent; only the Command Line Tools (Swift 6.3.3) exist.
  `scripts/smoke-test.sh` passed against `build/prefix` before any new work.
- Per `HANDOFF.md` §9, did the Phase 1 work that needs no `xcodebuild`:
  - `Sources/Bridge`: the Objective-C bridge (`GnmEngine`, `GnmWorkbook`,
    `GnmSheet`, `GnmRunLoopBridge`, `module.modulemap`), compiled with clang
    by `scripts/build-bridge.sh`. Cocoa subclasses of `WorkbookControl` and
    `SheetControl` forward every vtable slot to delegates; `GnmSheet` draws
    cells through a port of `item_grid_draw_region` and sheet objects through
    `sheet_object_draw_cairo_sized`, both onto a cairo-quartz surface over the
    caller's `CGContext`. The run loop bridge is the "CFRunLoop in control"
    half of GTK's `gdkeventloop-quartz.c` (observer plus poll thread).
  - `Tests/BridgeTests`: four headless programs (XCTest needs Xcode.app):
    lifecycle and vtable notifications, open/save round trips with error
    reporting, rendering into flipped `CGBitmapContext`s at 1x and 2x, and
    the run loop (idles, timeouts on time, GIO completions, cross-thread
    wake-ups, nested loops). All pass; `scripts/smoke-test.sh` runs them.
  - `project.yml` (XcodeGen) with `scripts/gen-xcconfig.sh` feeding
    pkg-config paths into `build/engine.xcconfig`; `xcodegen generate` works
    without Xcode, `xcodebuild` has not been tried.
  - `Sources/App`: the Swift 6 viewer (`WorkbookDocument`, window controller,
    `GridView`, header rulers, sheet tabs, menu). `scripts/build-app.sh`
    builds it with swiftc into `build/app/GnumericCocoa.app`;
    `scripts/run-app.sh file` launches it. Verified by `GNM_SNAPSHOT` renders
    of `chart-tests.gnumeric` (cells, selection, six charts in place) and
    `format-tests.gnumeric` (number formats, colors, fills, dates).
- Traps found and recorded (`docs/decisions.md` ADR-004 to ADR-008):
  engine messages become one `NSError` per operation; every workbook must be
  released (autorelease pools drained) before `shutdown`; a color-matched
  `CGColor` shifts its components, so RGB colors pass straight through;
  `NSStackView`'s default gravity distribution collapses the scroll view;
  macOS 26's `NSScrollView` blanks its interior in `cacheDisplay`, so
  snapshots capture the grid view itself; Homebrew bottles target the running
  macOS, so a 14.0 deployment target only yields linker warnings for now.
- Not done in Phase 1 yet: frozen panes (single pane only), right-to-left
  sheets (drawn left-to-right), header clicks to select columns and rows,
  zoom UI, sheet-tab overflow for many sheets, layer-backed scrolling
  performance, the Xcode build itself and XCTest wrappers.
- Working tree clean after this entry; everything committed on `main`,
  nothing pushed. `build/` (ignored) holds the engine, bridge, tests, and app.

## 2026-10-10, fourth session: Xcode works, questions 4 and 5 decided

- Henry installed Xcode 27.0 and ran `xcodebuild -runFirstLaunch` (needed:
  without it `xcodebuild` cannot load its plug-ins).
- Decisions (`docs/decisions.md` ADR-009, ADR-010): minimum macOS follows
  Homebrew's oldest supported release (15 today; every Homebrew dylib here
  has a 26.0 minimum, and Homebrew no longer supports 14); bundle identifier
  `io.github.h-bryant.gnumeric-cocoa`; preferences persist by default.
  Verified: the app writes
  `~/Library/Preferences/io.github.h-bryant.gnumeric-cocoa.plist` with the
  plugin file states and active list, and a second launch still loads the
  plot plugins (identical chart render).
- First `xcodebuild` of the XcodeGen project: two fixes were needed. The
  bridge target now builds without Clang modules (Homebrew include paths
  broke the SDK's Darwin and CoreFoundation module builds), and
  `scripts/gen-xcconfig.sh` rewrites the libffi include path, which pkg-config
  reports inside the Command Line Tools SDK, to `$(SDKROOT)`. After that:
  `** BUILD SUCCEEDED **`, no diagnostics in our sources, and the Xcode-built
  app (identifier and 15.0 minimum confirmed) renders `chart-tests.gnumeric`
  byte-identically to the swiftc build. `scripts/smoke-test.sh` passes.
- Working tree clean; committed on `main`, nothing pushed.

## How to resume

1. Henry (optional): review and post `docs/upstream-issue.md`.
2. Claude Code: `claude --enable-auto-mode` here, then "read HANDOFF.md and
   docs/progress.md and continue with Phase 1". `scripts/smoke-test.sh` first,
   then `scripts/gen-xcconfig.sh && xcodegen generate && xcodebuild -scheme
   GnumericCocoa build`. Next work: XCTest targets around `Tests/BridgeTests`,
   the Phase 1 gaps listed above, then Phase 2.
