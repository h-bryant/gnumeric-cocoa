# Build notes

Last verified: 2026-10-10 on the MacBook Air (M4, macOS 26.5 "Tahoe", arm64).

## Toolchain

| Tool | Version | Notes |
|---|---|---|
| Xcode Command Line Tools | clang 17.0.0 (clang-1700.6.3.2), Swift 6.2.3 | `/Library/Developer/CommandLineTools`; the SDK has AppKit, SwiftUI, CoreText |
| Xcode.app | **not installed yet** | Needed for `xcodebuild` and XcodeGen projects. `mas` 7.0.0 is installed; the install needs an administrator password, so Henry runs `sudo mas install 497799835` (or uses the App Store), then `sudo xcode-select -s /Applications/Xcode.app` and `sudo xcodebuild -license accept` |
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
| `scripts/smoke-test.sh` | ssconvert conversions of fixed samples plus `Tests/EngineSmoke/run.sh`; fails on engine warnings |
| `Tests/EngineSmoke/run.sh` | compile and run `headless.c` and `render.c` against `pkg-config libspreadsheet-1.12` |

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

## Using the engine from other code

```sh
source scripts/env.sh
pkg-config --cflags --libs libspreadsheet-1.12 cairo-quartz   # resolves to build/prefix
Tests/EngineSmoke/run.sh
```

Before `build/prefix` exists, the same commands resolve to Homebrew's gnumeric
keg, whose API matches the pinned tag.
