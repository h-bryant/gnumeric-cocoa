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
  the whole-window `cacheDisplay` came out blank (read at the time as a
  capture artifact; it was the real `NSRulerView` bug, see 2026-10-11);
  Homebrew bottles target the running macOS, so a 14.0 deployment target
  only yields linker warnings for now.
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

## 2026-10-11: upstream engagement deferred

- Henry decided to proceed without depending on upstream Gnumeric changes
  (`docs/decisions.md` ADR-011). `docs/upstream-issue.md` stays an unposted
  draft; unavoidable engine changes go to `patches/`, kept upstreamable. The
  annotated tag `upstream-baseline-2026-10-11` marks this point for a later
  return to upstream work.

## 2026-10-11: XCTest integration

- `project.yml` gains four `tool` targets (one per program in
  `Tests/BridgeTests`, via a target template) and a `BridgeTests` XCTest
  bundle that launches them as subprocesses and fails on exit status or
  engine warnings; the scheme's test action runs it. All four pass under
  `xcrun xctest` (`scripts/test-xcode.sh`). `xcodebuild test` times out
  "while preparing to run tests" because developer mode is disabled on the
  machine (`DevToolsSecurity -status`); enabling it is Henry's `sudo`.

## 2026-10-11: Phase 1 gaps closed, except panes and right-to-left

- Clicking a column or row header selects the whole column or row (drag or
  shift-click extends; the corner above the row header selects all), the
  View menu zooms (Zoom In/Out/Actual Size; the bridge sets the engine's
  `zoom-factor` property and the control's `scale_changed` drives the
  re-layout; the window subtitle shows the percentage), and the sheet tabs
  live in a horizontally scrolling strip (verified with a 60-sheet workbook).
- Draw timing (`GNM_DEBUG_LAYOUT=1`): the first draw of a sheet takes 55 to
  85 ms (one-time text layout), full-window redraws 3 to 10 ms, so the grid
  stays a plain `drawRect` view (ADR-007).
- Still open from Phase 1: frozen panes (Phase 3 in `HANDOFF.md` anyway)
  and right-to-left sheets (drawn left-to-right; Phase 7).

## 2026-10-11: Phase 2 editing, first cut

- Engine side: `patches/0001-decouple-command-dialogs-from-wbcgtk.patch`
  (the seven sites of `docs/architecture.md` §5; GTK behavior unchanged;
  rebuilt with `scripts/build-gnumeric.sh`). Bridge: `GnmWorkbook` gains
  undo/redo with the engine's labels, `notify::dirty` forwarding, and the
  `query_yes_no` slot answered by the delegate; `GnmSheet` gains
  `setText`, `fillSelection`, `clearSelection`, insert/delete rows and
  columns, hide/unhide, and `editingTextOfCell`. Every command returns the
  engine's own message as an `NSError` (`GnmErrorCommandFailed`).
  `Tests/BridgeTests/editing.m` covers them, including both patched paths.
- App side: in-cell editor (`CellEditorField`: typing starts a fresh edit,
  double-click or F2 edits the content, Return/Tab/arrows commit and move,
  Escape cancels, clicking elsewhere commits), the formula bar is editable
  (Return commits, Escape reverts), Edit menu Undo/Redo carry the engine's
  labels, Cut/Copy/Paste use tab-separated text (paste fills a block cell
  by cell for now; a single region paste waits for the engine clipboard
  format), Delete/Backspace clear values, and `WorkbookDocument` saves
  `.gnumeric` and `.xlsx` through the engine (`writeSafely` hands the final
  URL to libgsf's own atomic write) with the engine's dirty flag driving the
  change count. Engine messages outside a command show as alert sheets;
  yes/no questions as modal alerts.
- Verified headlessly (`GNM_SNAPSHOT_TYPE="=2*21"`): C3 shows 42 after
  typing, undo, redo; a pasted block appears at E5; the NSDocument save
  writes a file ssconvert reads back with the edits and clears the edited
  state.
- Clipboard, second pass: Copy and Cut go through `gnm_app_clipboard_cut_copy`
  (the engine keeps the cell region with formulas and formats and marks the
  source with marching ants, drawn as a static dashed outline), the
  control's `claim_selection` slot mirrors the region as tab-separated text
  on `NSPasteboard`, and Paste runs `cmd_paste_to_selection`: one undoable
  command ("Pasting into E5"), relative references adjust, a cut moves. Text
  from other applications comes in through `paste_from_selection`: one
  value is matched like typed input (dates included), several cells go
  through the engine's text importer with guessed options (formulas stay
  text, as in the GTK front end). A pasteboard change by another app
  retires the engine's clipboard. `Tests/BridgeTests/editing.m` covers it.
- Save As offers Gnumeric, Gnumeric XML uncompressed (`.xml`, the engine's
  `Gnumeric_XmlIO:sax:0` saver, declared as an exported UTI), and Excel.
- Still to do in Phase 2: range selection with the keyboard while editing
  a formula, autocomplete, and the editor using the cell's own font.

## 2026-10-11: Format Cells, the first SwiftUI dialog (Phase 2b)

- Bridge: `GnmCellFormat` (NS_SWIFT_NAME `CellFormat`), an all-optional
  value object: number format (Excel syntax), alignment, wrap, font name,
  size, bold, italic, underline, strikethrough, text color, fill, and a
  border per edge. `GnmSheet.formatOfSelection` reads the selection's
  common style with `sheet_style_find_conflicts` (nil where cells differ);
  `applyFormat:` runs `cmd_selection_format` with a partial style and the
  border set. Format helpers wrap goffice's family classification and
  format generator. `Tests/BridgeTests/format.m` covers read, mixed
  detection, apply, undo, fill removal, and the helpers.
- App: `FormatCellsView` (SwiftUI `TabView`: Number, Alignment, Font,
  Border, Fill) over an `@Observable` `FormatCellsModel` that tracks which
  properties the user touched, so only those apply and untouched mixed
  properties stay mixed. Hosted in an `NSHostingController` inside a window
  sheet from Format → Cells… (⌘1). Verified headlessly
  (`GNM_SNAPSHOT_FORMAT=1`): the model builds from a selection, the view
  lays out, and applying produces "Changing format of B5:B7" with the
  expected render.

## 2026-10-11: v0.1.0, the MVP

- `docs/mvp-known-gaps.md` lists every GTK menu item (202, extracted from
  `src/GNOME_Gnumeric-gtk.xml`) and the non-menu features with a status and
  phase. Tagged `v0.1.0` locally (not pushed). Phase 3 starts next.

## 2026-10-11: first interactive run, blank grid fixed

- Henry ran the app: the window showed only the column header and the
  sheet tabs; the grid, row header, and formula bar were blank, and typing
  showed nothing. The whole-window `GNM_SNAPSHOT` capture (`-window.png`)
  showed the same, which the previous session had dismissed as a capture
  artifact (ADR-007 consequences, now corrected). Three causes, in order:
  1. `NSRulerView` headers. On macOS 26 `NSScrollView` no longer tiles
     rulers beside the clip view: the clip view keeps the full size, the
     rulers sit in scroll pockets with backdrop views, and with them
     installed nothing drawn in the document view reached the window
     (verified: a plain red fill in `GridView.draw` never appeared; removing
     the rulers made the grid appear). `SheetHeaderView` is now a plain
     flipped `NSView`; `WorkbookWindowController` lays the two headers and
     the scroll view out in a pane (row header full height on the left with
     the select-all corner on top, column header above the scroll view) and
     `GridView` redraws them on the clip view's bounds-changed notification.
  2. `NSView.clipsToBounds` defaults to false since macOS 14: `draw(_:)`
     received a dirty rect covering the whole window with no clip, so each
     header's background fill painted over the formula bar and the other
     header in any pass where views share a context (window captures, layer
     rendering). The custom views set `clipsToBounds = true` and fill only
     `dirtyRect ∩ bounds`.
  3. The CGContext text matrix is not part of the graphics state, and
     cairo-quartz draws glyphs with whatever it finds; AppKit's string
     drawing leaves a flipped, translated one behind, so the engine's text
     vanished whenever a header had drawn before the grid in the same
     context. `GnmSheet` now resets the text matrix around its drawing and
     restores it after.
- Also: the formula bar's SwiftUI-backed text fields report a taller
  intrinsic height once drawn, which re-laid out the window during the
  first capture; the bar and its fields have fixed heights now. `Snapshot`
  flushes layout before capturing and writes a third file, `-layers.png`,
  from `CALayer.render(in:)`. Both whole-window captures now match the grid
  capture at 1x and at 150 % zoom (headers, selection highlights, corner,
  name box, cell text).
- Henry confirmed on screen the same day: grid, headers, and typing work.
- Tests unchanged and passing: `scripts/smoke-test.sh`, `scripts/test-xcode.sh`,
  `xcodebuild -scheme GnumericCocoa build`.

## 2026-10-11: Phase 3, first step: the commands the bridge already wrapped

- Menus: Edit → Clear (All, Formats, Contents, Comments), Fill (Down ⌘D,
  Right ⌘R), Delete Columns, Delete Rows, Select (All, Column, Row); a new
  Insert menu (Columns, Rows: as many as the selection spans, before it);
  Format → Column and Row submenus (Width/Height… in points, Autofit,
  Standard…, Hide, Unhide), Merge Cells, Merge and Center, Unmerge Cells;
  Data → Recalculate (F9). Actions live on `GridView` (responder chain);
  the four size prompts, `NSAlert` sheets with a number field, on the
  window controller.
- Bridge (`GnmSheet`): sizes in points (`widthInPointsOfColumn:`,
  defaults), `setSelectedColumns:sizeInPoints:` and
  `setColumns:inRange:sizeInPixels:` (`cmd_resize_colrow` through the
  engine's own point-to-pixel scale, `colrow_compute_pixels_from_pts`),
  `autofitSelectedColumns:`, `autofitSelectedCellsWidth:`,
  `setDefaultSizeInPoints:forColumns:` (`cmd_colrow_std_size`), `fillDown`
  / `fillRight` (`cmd_copyrel`), `autofillFromRange:toRange:defaultIncrement:`
  (`cmd_autofill`; the flag means a lone number counts up by one, the GTK
  Ctrl), `mergeSelectionCentered:`, `unmergeSelection`,
  `selectionHasMergedCells`; `GnmWorkbook.recalculateAll`. Covered in
  `Tests/BridgeTests/editing.m` (the engine prints negatives with U+2212).
- Grid: a fill handle on the selection's corner; dragging it extends the
  source in one direction by whole multiples of its size
  (`item-cursor.c`, `cb_autofill_scroll`) with a dashed outline, Option
  for the increment. Headers: a resize cursor over column and row
  boundaries, drag to resize (a guide line across the grid, applied on
  release to every selected column or row when the dragged one is
  selected), double-click to fit the content.
- `patches/0002-merge-center-style-ref.patch`: Merge and Center tripped
  `gnm_style_unref: assertion 'style->ref_count > 0'` because
  `cmd_merge_cells_redo` unrefs the align-center style once more than it
  owns (`sheet_apply_style` absorbs a reference); an upstream bug the GTK
  front end shares. One `gnm_style_ref` per range. Re-check at the next
  re-pin (ADR-003); it belongs in any future upstream request (ADR-011).
- `GNM_SNAPSHOT_PHASE3=1` drives insert, delete, fill, autofill, merge,
  hide, unhide, autofit, and recalc through the grid's actions before the
  capture. Snapshot runs now mark documents clean before terminating: the
  unsaved-documents review blocked headless and its alert kept the
  document (so a workbook) alive past the engine's shutdown.
- Status bar: the engine's auto-expression (`WorkbookView` properties
  `auto-expr-func`, `auto-expr-descr`, `auto-expr-value`) as a pull-down at
  the right of the tab bar showing "Sum = 42" over the selection, with
  Sum, Min, Max, Average, and Count to choose from (GTK's list). The bridge
  formats the value with `format_value` and the workbook's date
  convention, forwards `notify::auto-expr-value` to the delegate, and
  offers `recomputeAutoExpression` because the engine's own trigger after a
  selection change is a GLib timeout (the recalc lag) that test programs
  never pump.
- Freeze panes (View → Freeze Panes / Unfreeze Panes). The bridge exposes
  `isFrozen`, `frozenTopLeft`, `unfrozenTopLeft`, `freezePanes…`, and
  `unfreezePanes` over `gnm_sheet_view_freeze_panes`; the action follows
  the GTK placement rules (`cb_view_freeze_panes`). The grid keeps one
  document view: the frozen rows, columns, and corner are painted again as
  overlays at the visible rect's top and left (the sheet drawn with a
  translation and a clip, so the selection and ants come along), with
  mapping helpers (`viewX(forSheetX:)` and friends) for hit testing, the
  fill handle, and the headers, which paint the frozen columns or rows
  over the scrolled ones. `GridClipView.constrainBoundsRect` clamps
  scrolling to the first unfrozen cell, and "make cell visible" clears
  the strips. While frozen, any change repaints the visible rect
  (3 to 10 ms). `GNM_SNAPSHOT_FREEZE=1` freezes at C4 and scrolls; the
  capture shows rows 1 to 3 and columns A and B in place beside row 28 and
  column H.
- `docs/mvp-known-gaps.md` updated. Next in Phase 3: sheet management
  (insert, rename, remove, reorder), Paste Special, sort, and the filtered
  Clear variants.

## How to resume

1. Upstream engagement is deferred; see ADR-011 before touching
   `docs/upstream-issue.md`.
2. Claude Code: `claude --enable-auto-mode` here, then "read HANDOFF.md and
   docs/progress.md and continue with Phase 1". `scripts/smoke-test.sh` first,
   then `scripts/gen-xcconfig.sh && xcodegen generate && xcodebuild -scheme
   GnumericCocoa build`. Next work: XCTest targets around `Tests/BridgeTests`,
   the Phase 1 gaps listed above, then Phase 2.
