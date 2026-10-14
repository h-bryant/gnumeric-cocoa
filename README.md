# Gnumeric Cocoa

A native macOS front end for the [Gnumeric](https://www.gnumeric.org/)
spreadsheet engine. The engine (`libspreadsheet` 1.12.62 with goffice and
libgsf) does the calculating, file reading and writing, formatting, undo,
and cell rendering; the GTK user interface is replaced by an AppKit one
written in Swift, with an Objective-C bridge between the two. Nothing of
GTK's windowing is used: no X11, no XQuartz.

Gnumeric is the GNOME project's spreadsheet. This is an independent port
of its engine to a Cocoa interface, not a GNOME project, and it is not
affiliated with or endorsed by the Gnumeric maintainers.

## Status

Version 0.2.0, 2026-10-13. The app opens every format the engine reads
(Gnumeric, Excel `.xlsx` and `.xls`, OpenDocument, CSV, delimited and
fixed-width text, and the rest of the engine's importers) and saves the
engine's own format, Excel, CSV, and configurable text. Of the GTK
interface's menu items, dialogs, and tools, 97 are ported, 9 partly, and
3 left out by decision (a second view of one workbook, the unfinished
data slicers, and goffice components, which Homebrew's goffice does not
ship). `docs/mvp-known-gaps.md` has the table, item by item.

Ported, among other things: the formula bar and in-cell editor with
autocompletion and function tooltips, frozen panes, merged cells, sheet
management, Paste Special, sorting and filtering, conditional formatting
and data validation, defined names, comments and hyperlinks, charts with
goffice's chart editor, images and shapes, form widgets, all 27 analysis
tools, Goal Seek and the Solver, scenarios and simulation, printing with
page setup and a print preview, Find and Replace, autoformat, right-to-left
sheets, and the Settings window. Menus, dialogs, and the engine's messages
follow the macOS language through Gnumeric's own translations (62
languages).

Requirements: macOS 15 or later on Apple silicon.

## Running the release

Each release on the repository's GitHub
[Releases page](https://github.com/h-bryant/gnumeric-cocoa/releases)
carries a download named `GnumericCocoa-<version>.zip` (for example
`GnumericCocoa-0.2.0.zip`). Unzipping it gives `GnumericCocoa.app`, with
the engine, its plugins, the libraries, templates, and translations
inside; move it to `/Applications` or anywhere else you like.
It is not signed with an Apple Developer ID, so macOS blocks the first
launch. Either of these lets it run:

- Double-click the app once, dismiss the message, then open System
  Settings → Privacy & Security, scroll to the note about the app, and
  choose **Open Anyway**. macOS asks for your password once.
- Or remove the quarantine flag in Terminal before the first launch:

  ```sh
  xattr -dr com.apple.quarantine /path/to/GnumericCocoa.app
  ```

The bundle has been run with its own engine on the machine it was built
on, but not yet on a Mac without Homebrew installed. If you run it on a
clean machine, please open an issue saying whether fonts render, whether
charts work, and what Console.app logs if anything fails.

## Building from source

You need the Xcode Command Line Tools (Xcode itself only for the XCTest
run), [Homebrew](https://brew.sh/), and the formulae in `Brewfile`.

```sh
git clone --recurse-submodules https://github.com/h-bryant/gnumeric-cocoa.git
cd gnumeric-cocoa
brew bundle                      # the engine's libraries and the autotools
bash                             # the scripts are bash; zsh computes the wrong root
source scripts/env.sh
scripts/build-gnumeric.sh        # the engine from the submodule into build/prefix
scripts/build-app.sh             # the app into build/app/GnumericCocoa.app
scripts/run-app.sh [file]        # run it
scripts/bundle.sh                # the relocatable build/dist/GnumericCocoa.app
```

The engine builds from the upstream source in the `upstream/gnumeric`
submodule with the patches in `patches/` applied to a copy; the submodule
itself is never modified. `docs/build.md` has the details, the headless
checks, and the bundling notes.

Tests:

```sh
scripts/smoke-test.sh            # ssconvert on sample files, engine smoke programs, bridge tests
Tests/BridgeTests/run.sh         # the 35 bridge test programs
scripts/test-xcode.sh            # the same through XCTest (needs Xcode)
```

## Layout

- `Sources/Bridge` — the Objective-C bridge: the engine's lifecycle, a
  `WorkbookControl` and `SheetControl` for Cocoa, workbook and sheet
  wrappers, drawing through cairo-quartz, and every engine feature the app
  uses behind headers that expose no engine types.
- `Sources/App` — the AppKit application: the grid view, headers, menus,
  toolbar, dialogs, printing, and localization.
- `patches/` — the engine changes, each with its reason in `patches/README.md`.
- `scripts/` — build, test, and bundling scripts.
- `docs/` — `architecture.md` (how the engine is driven), `decisions.md`,
  `mvp-known-gaps.md`, `build.md`, and `progress.md`, the working journal.
  `HANDOFF.md` is the plan the work follows.

## License

GPL-2.0-only OR GPL-3.0-only, the same as Gnumeric (`COPYING`,
`COPYING-gpl2`, `COPYING-gpl3`). The release bundle carries the license
texts and source locations of every bundled library under Help →
Third-Party Licenses.
