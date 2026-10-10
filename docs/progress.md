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
- Xcode: installed `mas` and tried `mas install 497799835`; it needs `sudo`,
  so Henry runs it (`HANDOFF.md` §8, question 3). Phase 1 starts after that.
