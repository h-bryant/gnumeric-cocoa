# Build notes

Last verified: 2026-10-10 on the MacBook Air (M4, macOS 26.7.1 "Tahoe", arm64).

## Toolchain

| Tool | Version | Notes |
|---|---|---|
| Xcode Command Line Tools | clang 17 (clang-2100.1.1.101), Swift 6.3.3, SDK macOS 26.5 | `/Library/Developer/CommandLineTools`; the SDK has AppKit, SwiftUI, CoreText; `swiftc` builds the app, but XCTest is not included |
| Xcode.app | 27.0 (27A266a), SDK macOS 27.0 | Installed 2026-10-10; `xcodebuild -runFirstLaunch` was required once. `xcodebuild -scheme GnumericCocoa build` works on the XcodeGen project |
| Homebrew | 7.0.9 | `/opt/homebrew` |

## Homebrew formulae

As installed on 2026-10-10 after `brew upgrade goffice gnumeric` and
`scripts/build-deps.sh` (`brew bundle`):

| Formula | Version | Notes |
|---|---|---|
| gnumeric | 1.12.62 | reference `ssconvert`; ships `libspreadsheet-1.12.pc` and headers |
| goffice | 0.10.62 | the goffice the app links; its 9 plot plugins live in `/opt/homebrew/opt/goffice/lib/goffice/0.10.62/plugins` |
| glib | 2.90.1 | GSettings uses the NSUserDefaults backend on macOS |
| gtk+3 | 3.24.52_1 | built with `-Dquartz_backend=true -Dx11_backend=false` |
| cairo | 1.18.6 | `cairo-quartz` and `cairo-quartz-font` present |
| pango | 1.58.2 | CoreText and fontconfig backends; CoreText is the default font map |
| libgsf | 1.14.60 | |
| libxml2 | 2.15.4 | keg-only (handled in `scripts/env.sh`) |
| librsvg | 2.63.2 | |
| gettext | 1.0 | |
| harfbuzz | 14.6.0 | |
| pkgconf | 3.0.7 | |
| autoconf / automake / libtool | 2.73 / 1.19 / 2.6.2 | `autogen.sh` |
| intltool / itstool | 0.51.0_2 / 2.0.7_2 | `autogen.sh`, translations |
| gtk-doc | 1.37.0 | `gtkdocize`, required by `autogen.sh` |
| yelp-tools | 42.1_3 | `yelp.m4` for `YELP_HELP_INIT` |
| xcodegen | 2.46.0 | Phase 1 |
| mas | 7.0.0 | not in `Brewfile`; installed only to fetch Xcode |

`bison` 2.3 and `flex` 2.6.4 come from macOS and suffice. `gtk-mac-bundler` is
not a Homebrew formula; `dylibbundler` 1.0.5 is (Phase 6).

## Layout

- `upstream/gnumeric`: submodule pinned to `GNUMERIC_1_12_62` (commit
  `221aa930`, 2026-09-20), matching Homebrew's goffice 0.10.62.
- `patches/`: empty; 1.12.62 builds unpatched. Patches are applied to a copy of
  the submodule, never to the submodule.
- `build/` (ignored): `src/gnumeric` (patched copy, 152 MB), `obj/gnumeric`
  (out-of-tree objects, 72 MB), `prefix` (install, 29 MB), `smoke` (test
  outputs), `build.log`.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/env.sh` | source it: `PKG_CONFIG_PATH` (`build/prefix` first), `ACLOCAL_PATH`, `PATH`, `GNM_PREFIX`; unsets `DISPLAY` |
| `scripts/build-deps.sh` | `brew bundle` plus a tool and pkg-config report (installs software; Henry's call) |
| `scripts/build-gnumeric.sh [configure args]` | copy, patch, `autogen.sh`, configure, `make -j`, install to `build/prefix`, compile schemas |
| `scripts/apply-patches.sh <dir>` | apply `patches/*.patch` with `patch -p1` |
| `scripts/smoke-test.sh` | ssconvert conversions of fixed samples, `Tests/EngineSmoke/run.sh`, then `Tests/BridgeTests/run.sh`; fails on engine warnings |
| `Tests/EngineSmoke/run.sh` | compile and run `headless.c` and `render.c` against `pkg-config libspreadsheet-1.12` |
| `scripts/build-bridge.sh` | clang build of `Sources/Bridge` into `build/bridge/libGnmCocoa.a`; `--flags` prints the compile flags |
| `Tests/BridgeTests/run.sh` | build the bridge, then compile and run each test program against it (no Xcode needed) |
| `scripts/gen-xcconfig.sh` | write `build/engine.xcconfig` from pkg-config for `project.yml`; then `xcodegen generate` |
| `scripts/build-app.sh` | swiftc build of `Sources/App` plus the bridge into `build/app/GnumericCocoa.app` (ad-hoc signed) |
| `scripts/test-xcode.sh` | build the Xcode test bundle and run it with `xcrun xctest`; `--xcodebuild` uses `xcodebuild test` (needs developer mode) |
| `scripts/run-app.sh [file ...]` | launch that app directly; `GNM_SNAPSHOT=out.png` writes the grid (`out.png`), the whole window through `cacheDisplay` (`out-window.png`) and through `CALayer.render` (`out-layers.png`), then quits; `GNM_DEBUG_LAYOUT=1` logs view frames, layer state, and every grid and header draw with its transform |

Configure flags used by `build-gnumeric.sh`: Homebrew's
(`--disable-schemas-compile --disable-silent-rules
--disable-dependency-tracking`) plus `--disable-component` (the goffice
embedding component would otherwise install into Homebrew's goffice plugin
directory), `--disable-introspection`, `--disable-gtk-doc`,
`--without-python`, `--without-perl`.

## Engine build result (2026-10-10)

`scripts/build-gnumeric.sh` built 1.12.62 on the first run, in a few minutes
with `make -j10`. Configure summary: compiler `gcc -std=gnu23` (Apple clang),
UI Gtk, Perl and Python plugin loaders disabled by request, no GDA, psiconv,
or PDF docs. 38 Gnumeric plugins were built and installed (the Perl ones are
excluded); goffice's 9 plot plugins still come from Homebrew.

`scripts/smoke-test.sh` then passed against `build/prefix`: 15 ssconvert
conversions (`.gnumeric`, `.xlsx`, `.csv` from five samples), and the two
smoke programs linked against `build/prefix/lib/libspreadsheet-1.12.62.dylib`
(47 plugins available, 44 active; cells and a chart rendered to cairo image
and cairo-quartz surfaces; `.gnumeric` and `.xlsx` saved).

Rebuild from scratch with `rm -rf build && scripts/build-gnumeric.sh`.

## Bridge and app builds (no Xcode)

```sh
scripts/build-bridge.sh          # build/bridge/libGnmCocoa.a
Tests/BridgeTests/run.sh         # the headless test programs; outputs in build/bridge-tests
scripts/build-app.sh             # build/app/GnumericCocoa.app
scripts/run-app.sh upstream/gnumeric/samples/chart-tests.gnumeric
GNM_SNAPSHOT=/tmp/grid.png scripts/run-app.sh upstream/gnumeric/samples/format-tests.gnumeric
```

`GNM_SNAPSHOT_ZOOM=1.5`, `GNM_SNAPSHOT_TYPE=text`, `GNM_SNAPSHOT_FORMAT=1`,
`GNM_SNAPSHOT_PHASE3=1`, `GNM_SNAPSHOT_FREEZE=1`, `GNM_SNAPSHOT_SHEETS=1`,
`GNM_SNAPSHOT_FILTER=1`, `GNM_SNAPSHOT_OBJECTS=1`, `GNM_SNAPSHOT_CHART=1`,
`GNM_SNAPSHOT_EDITOR=1`, `GNM_SNAPSHOT_EVERYDAY=1`, `GNM_SNAPSHOT_FIND=1`,
`GNM_SNAPSHOT_PREFS=1`, `GNM_SNAPSHOT_TEXT=1`, `GNM_SNAPSHOT_IMPORT=1`,
`GNM_SNAPSHOT_COMMENT=1`, `GNM_SNAPSHOT_NAMES=1`, `GNM_SNAPSHOT_FILL=1`,
`GNM_SNAPSHOT_GOAL=1`, `GNM_SNAPSHOT_COND=1`, `GNM_SNAPSHOT_STATS=1`,
`GNM_SNAPSHOT_VALID=1`, `GNM_SNAPSHOT_LINK=1`, `GNM_SNAPSHOT_SOLVE=1`,
`GNM_SNAPSHOT_PRINT=1`, `GNM_SNAPSHOT_FORMULA=1`, `GNM_SNAPSHOT_FUNC=1`,
`GNM_SNAPSHOT_SHEET=1`, `GNM_SNAPSHOT_WHATIF=1`, `GNM_SNAPSHOT_OUTLINE=1`,
`GNM_SNAPSHOT_ADVFILTER=1`, `GNM_SNAPSHOT_MANAGE=1`, `GNM_SNAPSHOT_PLUGINS=1`,
`GNM_SNAPSHOT_SCENARIO=1`, `GNM_SNAPSHOT_AUTOFORMAT=1`, `GNM_SNAPSHOT_WIDGET=1`,
`GNM_SNAPSHOT_TOOLBAR=1`, and `GNM_SNAPSHOT_DRAG=1`
exercise zoom, editing and saving, the Format Cells model, the Phase 3
commands, frozen panes, sheet management, the autofilter with the Sort
command, a sheet resize, and a tab color, the sheet objects (select, move,
resize, delete, undo, copy and paste, an inserted image), chart
insertion (which also writes the guru sheet to `-guru.png`), and the chart
editor on the sheet's first chart (a title, an inverted axis, a red series,
the plot changed to columns, the editor written to `-editor.png`, then
applied), the everyday items (the name box's jump, the current date,
a shifted cell, a CSV saved beside the capture, File → New), and Find and
Replace (the panel finds "1", steps, is written to `-find.png`, replaces
one match and then all, undone), the Settings window (a compression
level change read back from the engine, the window written to
`-settings.png`), Export as Text (the options sheet written to
`-export.png`, then the sample saved beside the capture with semicolons),
and Import Text (a semicolon file written beside the capture, the
assistant driven headlessly and written to `-import.png`, the new
document's cells logged), and a cell comment (set on A3, its tool tip,
the cell's context menu, the removal undone, the marker left in the
capture), and defined names (one added through the dialog, captured to
`-names.png`, then inserted into E1 as a formula), and Fill Series with
Text to Columns (F1:F6 filled from 1 by 2, "a;b" and "c;d" in G1:G2 split
through the assistant), and Goal Seek (B30 driven to 0 by changing A30,
undone), and conditional formatting ("value > 100 → yellow, bold" put on
B5:B12 through the dialog, captured to `-cond.png`), and the analysis
tools (a correlation into D1 through its dialog, captured to
`-stats.png`, a paired t-test into D6, a histogram into D20 through its
dialog, captured to `-hist.png`, a test of independence into D30, then
descriptive statistics to a new sheet), and data
validation (C1 takes a value from B1:B5 through the dialog, captured to
`-valid.png`; an entry outside the list refused, one from it taken), and
hyperlinks (a web link on A1 through the dialog, captured to
`-link.png`, an internal link on A3 followed to C5), and the Solver (a
small linear program through the dialog, captured to `-solve.png`, run
through the progress sheet's timer with the run loop pumped until the
outcome, the solution in the cells), and printing (landscape with grid lines and a
header through the Page Setup dialog, captured to `-print.png`, the
first page drawn to `-page1.png`), formula range selection ("=SUM(" in
A5 takes B1:B3 from the grid, then Bold; A6 styled bold Georgia 14
right-aligned so the editor shows the cell's style; "=MAX(" in A6 takes B1:B3 by
Right, ⌘Up, and ⇧⌘Up sent as key events, F4 four times cycles the
reference's absolute forms, ")" ends the selection, Up commits; "=avera"
in A10 shows the completion list under the editor, written to
`-tooltip.png`, and F4 on "=averageif" completes it; "=B1:B3*2" over
A7:A9 by ⇧⌘Return), and autocompletion with the
function selector ("app" under "apple" completes; SUM inserted through
the dialog, captured to `-func.png`), and the sheet display toggles
(A1 a formula and B1 a zero, then Display Formulæ, Hide Zeros, Hide
Gridlines, Hide Row Headers, R1C1 column names, and Zoom… to 150%
through its dialog, captured to `-zoom.png`), and the what-if tools
(a data table over C1:E3 through its dialog, captured to `-table.png`,
normal random numbers into H1, a tabulation of A3 over A1 onto a new
sheet, K1:L2 and K4:L5 consolidated into N1, K1:L2 shuffled), and outlines (rows 2–4 and 2–3 and columns B–C grouped, the
inner rows hidden, the row header's toggle, hidden again for the
window capture's header strips), and the advanced filter (A1:B6 with
Qty > 4 in place through its dialog, captured to `-advfilter.png`, then
copied to G1; a second sheet hidden and shown again), and Manage Sheets
(a sheet appended and renamed through the table, the first locked, hidden,
and colored, the list sorted and the sort undone, an empty name refused,
the window captured to `-manage.png`), and the Plugin Manager (the time
series plugin activated and deactivated through its checkbox, a directory
added and removed, a rescan, the window captured to `-plugins.png`), and
scenarios ("Base" and "High" for A1:A2 added through the dialog, the
manager's summary with B1 as the result cell, "High" shown and committed
by OK, the manager captured to `-scenarios.png`, then a simulation of
D1+D2 over two rounds, its results text logged), and AutoFormat (a 5 × 5
block, the dialog on General's second template with the top edge off,
captured to `-autoformat.png`, applied by OK), and widgets (a button
inserted at B2 and configured through its dialog, a scrollbar at D2 made
horizontal over 0…50, both in the window capture), and the toolbar
(1234.5678 in C3 made bold, centered, a percentage with one more decimal
through the toolbar's items, the font size 14 through its combo, AutoSum
in C5, zoom 150% through its pop-up; the toggles' state logged), and drag
and drop (A1:B1 dropped at A4 as a move and at A7 as a copy, a PNG
written beside the capture and dropped at D2, the second tab dragged
before the first) before the capture (`AppDelegate.swift`, `Snapshot`). The typing hook saves as a
Save As next to the snapshot; with `GNM_SNAPSHOT_SAVE_INPLACE=1` it saves
the opened file in place instead (give it a copy). Should a quit ever go
nowhere again (an alert sheet on the window did that once,
`docs/progress.md` 2026-10-12), the snapshot logs the sheets' texts and
"terminate was swallowed" and exits through the delegate's shutdown. The three snapshot files should agree. The grid capture draws the grid view
alone; the window captures draw the whole hierarchy and are what caught the
blank grid of 2026-10-11 (`docs/progress.md`). SwiftUI-hosted controls (the
text fields, the tab control) may come out incomplete in the window
captures; that is a capture limitation, not a bug. The screen itself cannot
be captured without a Screen Recording permission prompt.

The app finds the engine's compiled GSettings schemas through `GNM_PREFIX`
(exported by `scripts/env.sh`) or the `GnmEnginePrefix` key that
`build-app.sh` writes into the bundle's `Info.plist`; lib, data, and plugin
directories are compile-time constants in the engine and point at
`build/prefix` already. Preferences persist through NSUserDefaults in
`~/Library/Preferences/io.github.h-bryant.gnumeric-cocoa.plist` (ADR-010);
`GNM_PERSIST_PREFS=0` keeps a run from writing there.

Linking shows "building for macOS-15.0, but linking with dylib ... built for
newer version 26.0" warnings whenever a deployment target below the running
macOS is requested, because Homebrew bottles target the OS they were built
on. `build-bridge.sh` therefore passes no `-mmacosx-version-min`;
`project.yml` and `Info.plist` carry the product minimum, macOS 15.0, which
follows Homebrew's oldest supported release (ADR-009).

## Xcode build

```sh
scripts/gen-xcconfig.sh && xcodegen generate
xcodebuild -scheme GnumericCocoa -configuration Debug -derivedDataPath build/DerivedData build
GNM_PREFIX=$PWD/build/prefix build/DerivedData/Build/Products/Debug/GnumericCocoa.app/Contents/MacOS/GnumericCocoa file.gnumeric
```

Tests: `scripts/test-xcode.sh` builds the `BridgeTests` bundle
(`xcodebuild build-for-testing`) and runs it with `xcrun xctest`. The bundle
launches the four test programs, built as tool targets next to it, as
subprocesses, because the engine starts once per process. `xcodebuild test`
(or `scripts/test-xcode.sh --xcodebuild`) is the official route but its test
runner times out while preparing until macOS developer mode is enabled
(`DevToolsSecurity -status`; enabling needs `sudo DevToolsSecurity -enable`).

Two settings matter: the bridge target has `CLANG_ENABLE_MODULES = NO`
(with modules on, Homebrew's include paths break the SDK's own module
builds), and `gen-xcconfig.sh` maps any include path pkg-config reports
inside the Command Line Tools SDK (libffi's) to `$(SDKROOT)`. The scheme's
run action exports `GNM_PREFIX` so the app finds the compiled schemas.

## Using the engine from other code

```sh
source scripts/env.sh
pkg-config --cflags --libs libspreadsheet-1.12 cairo-quartz   # resolves to build/prefix
Tests/EngineSmoke/run.sh
```

Before `build/prefix` exists, the same commands resolve to Homebrew's gnumeric
keg, whose API matches the pinned tag.
