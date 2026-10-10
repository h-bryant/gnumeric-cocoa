# Build notes

Last verified: 2026-10-10 on the MacBook Air (M4, macOS 26.5 "Tahoe", arm64).

## Toolchain present

| Tool | Version | Source |
|---|---|---|
| Xcode Command Line Tools | clang 17.0.0 (clang-1700.6.3.2), Swift 6.2.3 | `/Library/Developer/CommandLineTools` |
| Xcode.app | **not installed** | `xcodebuild` unavailable; see HANDOFF.md §8 |
| Homebrew | 7.0.9 | `/opt/homebrew` |
| macOS SDK | MacOSX.sdk in the CLT (AppKit, SwiftUI, CoreText present) | |

## Homebrew formulae

Installed before this project (versions on 2026-10-10):

| Formula | Installed | Formula stable |
|---|---|---|
| gnumeric | 1.12.60 | 1.12.62 |
| goffice | 0.10.60 | 0.10.62 |
| glib | 2.90.1 (2.88.0 also present) | |
| gtk+3 | 3.24.51, Quartz backend (`-Dquartz_backend=true -Dx11_backend=false`) | |
| cairo | 1.18.6 (`cairo-quartz`, `cairo-quartz-font` present) | |
| pango | 1.57.0_2 (CoreText and fontconfig backends; CoreText is the default font map) | |
| libgsf | 1.14.55 | |
| libxml2 | 2.15.2 (keg-only) | |
| librsvg | 2.62.0 | |
| gettext | 1.0 | |
| pkgconf | 2.5.1 | 3.0.7 |

Not installed yet (listed in `Brewfile`; Henry installs): `autoconf`,
`automake`, `libtool`, `intltool`, `itstool`, `gtk-doc`, `yelp-tools`,
`xcodegen`. `bison` 2.3 and `flex` 2.6.4 come from macOS.

Formula names were verified with `brew info`: `gtk-mac-bundler` is not a
Homebrew formula; `dylibbundler` 1.0.5 is.

## Layout

- `upstream/gnumeric`: submodule, pinned to `GNUMERIC_1_12_60`
  (commit `39152134`, 2026-02-10) to match the installed goffice 0.10.60.
- `patches/`: applied to a copy of the submodule, never to the submodule.
- `build/` (ignored): `src/gnumeric` (patched copy), `obj/gnumeric`
  (out-of-tree objects), `prefix` (install), `smoke` (test outputs).

## Scripts

| Script | Purpose |
|---|---|
| `scripts/env.sh` | source it: `PKG_CONFIG_PATH`, `ACLOCAL_PATH`, `PATH`, `GNM_PREFIX`; unsets `DISPLAY` |
| `scripts/build-deps.sh` | `brew bundle` plus a tool and pkg-config report (Henry runs this) |
| `scripts/build-gnumeric.sh [configure args]` | copy, patch, `autogen.sh`, configure, make, install to `build/prefix`, compile schemas |
| `scripts/apply-patches.sh <dir>` | apply `patches/*.patch` with `patch -p1` |
| `scripts/smoke-test.sh` | ssconvert conversions of fixed samples plus `Tests/EngineSmoke/run.sh` |
| `Tests/EngineSmoke/run.sh` | compile and run `headless.c` and `render.c` against `pkg-config libspreadsheet-1.12` |

Configure flags used by `build-gnumeric.sh`: Homebrew's
(`--disable-schemas-compile --disable-silent-rules
--disable-dependency-tracking`) plus `--disable-component` (the goffice
embedding component would otherwise install into Homebrew's goffice plugin
directory), `--disable-introspection`, `--disable-gtk-doc`,
`--without-python`, `--without-perl`.

## Status

- The submodule build has **not** been run: `autogen.sh` needs the build
  tools above. Everything else in Phase 0 was done against Homebrew's
  `libspreadsheet-1.12.60`, whose headers and pkg-config file Homebrew
  installs, and whose API is identical to the pinned tag.
- `scripts/smoke-test.sh` passes with Homebrew's engine (2026-10-10): 15
  ssconvert conversions, and both smoke programs.

## Running with the Homebrew engine

```sh
source scripts/env.sh
pkg-config --cflags --libs libspreadsheet-1.12 cairo-quartz
Tests/EngineSmoke/run.sh
```
