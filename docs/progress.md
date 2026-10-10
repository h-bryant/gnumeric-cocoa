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
- Not done: the submodule build (`scripts/build-gnumeric.sh`) is waiting on
  Henry installing the autotools formulae in `Brewfile`. Open questions in
  `HANDOFF.md` §8: Homebrew installs, version pairing, Xcode.
