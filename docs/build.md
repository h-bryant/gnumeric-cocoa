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
and `GNM_SNAPSHOT_EDITOR=1`
exercise zoom, editing and saving, the Format Cells model, the Phase 3
commands, frozen panes, sheet management, the autofilter with the Sort
command, a sheet resize, and a tab color, the sheet objects (select, move,
resize, delete, undo, copy and paste, an inserted image), chart
insertion (which also writes the guru sheet to `-guru.png`), and the chart
editor on the sheet's first chart (a title, an inverted axis, a red series,
the editor written to `-editor.png`, then applied) before the
capture (`AppDelegate.swift`, `Snapshot`). After the typing hook's save
the normal quit is swallowed (`docs/progress.md`, 2026-10-12); the
snapshot then logs "terminate was swallowed" and exits through the
delegate's shutdown itself. The three snapshot files should agree. The grid capture draws the grid view
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
