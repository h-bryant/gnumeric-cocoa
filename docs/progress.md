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
- Sheet management: Edit → Sheet (Insert, Insert at End, Duplicate,
  Rename…, Move Left, Move Right, Remove), the same menu on a right-click
  of a tab (`SheetTabControl` selects the tab under the mouse first). The
  bridge runs each change the GTK way: `workbook_sheet_state_new`, the
  change (`workbook_sheet_add`, `sheet_dup` plus
  `workbook_sheet_attach_at_pos`, `workbook_sheet_delete`,
  `workbook_sheet_move`), then `cmd_reorganize_sheets`, which owns the
  snapshot and refocuses the given sheet on undo; `cmd_rename_sheet` for
  names. The last sheet cannot be removed. Each sheet's `notify::name`
  and `notify::visibility` reach the delegate as `workbook:sheetDidChange:`
  (the GTK tab listens to the same), so the tab strip follows renames.
  `GNM_SNAPSHOT_SHEETS=1` drives append, insert, move, duplicate, remove,
  and rename. Found on the way: the engine's undo stack keeps a limited
  number of commands (`core/undo/maxnum`), so a test that removes twenty
  sheets cannot undo them all.
- Paste Special (Edit → Paste Special…, ⌘⇧V): an `NSAlert` sheet with the
  GTK dialog's choices (what to paste, arithmetic operation, region
  transform, skip blanks, keep formula references, column widths, row
  heights) and a Paste Link button; the bridge's `pasteWithOptions:`
  mirrors the engine's PASTE_* flags. Sort: Data → Sort Ascending and
  Sort Descending run the GTK quick sort (`sort_by_rows`: by every column
  of the one selected range, heading detected; a single cell sorts the
  sheet below it by that column; `cmd_sort` owns the `GnmSortData`). The
  engine's clause flag reads inverted (`asc = descending`), kept as GTK
  has it. Both covered in `Tests/BridgeTests/editing.m` and driven by
  `GNM_SNAPSHOT_PHASE3=1`.
- `docs/mvp-known-gaps.md` updated. Next in Phase 3: the filtered Clear
  variants (with autofilter), sheet resize, tab colors, the Sort dialog.

## 2026-10-12: Phase 3, the rest: autofilter, sheet resize, tab colors, the Sort dialog

- Autofilter (Data → Filter → Add/Remove Auto Filter, Show All). The
  bridge wraps `cmd_autofilter_add_remove` (`toggleAutofilter`) and
  `cmd_autofilter_set_condition` (`setFilterCondition:forButton:`), and
  describes each filter field as a `GnmFilterButton` (heading cell, the
  square at the cell's bottom-right as `filter_view_set_bounds` places it,
  active flag). `choicesForFilterButton:` ports `fcombo_create_list`
  (`widgets/gnm-filter-combo-view.c`): the column's distinct values,
  formatted and sorted, rows hidden by the other fields left out through
  the same temporary-sheet trick, plus the current condition read back.
  `GnmFilterCriterion` (Swift `FilterCondition`; the engine's typedef owns
  the name `GnmFilterCondition`) covers All, one value, Blanks, Non
  Blanks, the custom one- or two-comparison form with the twelve
  operators of `dialog-autofilter.c` (the text ones travel as `*`
  wildcards and come back as such), and the Top/Bottom N items or percent
  bucket. The grid draws the buttons (accent-filled while active) and
  pops up an `NSMenu` with the GTK list on a click; "(Custom…)" and
  "(Top 10…)" open `NSAlert` sheets on the window controller. Edit →
  Clear gained the four "… Filtered Rows" items (`CLEAR_FILTERED_ONLY`).
- Three engine facts the tests settled, all shared with the GTK front end:
  `has_filtered_rows` is kept only by the advanced filter, so
  `hasFilteredRows` looks at the rows of the active autofilters; the
  "filtered rows" clear variants skip the rows a filter hides (they act
  on the rows it shows: `cmd_selection_clear_row_handler`); and undoing a
  filter removal re-attaches the filter without its conditions
  (`gnm_filter_attach` recreates the fields). `filter_show_all` serves
  only the advanced filter, so `showAllFilteredRows` also drops every
  autofilter condition (one undoable command each) before calling it.
- `sheet_object_draw_cairo_sized` calls the class's `draw_cairo` without a
  NULL check, and the filter combo objects have none: `drawSheetObjectsInRect:`
  now skips objects without a renderer (and invisible ones). Any file
  with an autofilter would have crashed the grid before.
- Sheet resize (Edit → Sheet → Resize…): `resizeSheets:toColumns:rows:`
  over `cmd_resize_sheets` (the list's first sheet keeps the focus on
  undo), `isValidSheetSizeWithColumns:rows:` and the four limits; the
  sheet offers the powers of two between them in two pop-ups and an
  "Apply to all sheets" switch, as the GTK sliders do.
- Tab colors (Edit → Sheet → Tab Color…, the tab context menu):
  `setTabColor:textColor:ofSheet:` sets the sheet's `tab-background`
  and `tab-foreground` between a sheet-state snapshot and
  `cmd_reorganize_sheets`, as `dialog-sheet-order.c` does, and the two
  `notify::` signals reach `sheetDidChange:`. The tab strip shows the
  background as a swatch before the name (`NSSegmentedControl` has no
  per-segment background; the text color is kept in the file but not
  shown). The sheet has two color wells with "None" switches.
- Sort dialog (Data → Sort…, `SortDialog.swift`): direction (rows or
  columns, defaulting to rows for a range taller than wide as GTK does),
  a header switch preset by `sheet_range_has_heading`, three keys named
  like the GTK dialog ("Price (Column B)"), each with order and case
  sensitivity, and "keep formats". `sortRange:byRows:hasHeader:keys:retainFormats:`
  builds the `GnmSortData` as `cb_dialog_ok_clicked` does; `sortableRange`
  grows a single cell to its data block (`gnm_sheet_guess_data_range`).
  Left out: more than three keys, the locale selector, the per-key "by
  value" switch (always on), the saved sort setups.
- `GNM_SNAPSHOT_FILTER=1` drives a table at A20:B25 through add filter,
  a value choice, the Sort command, a resize, and a tab color; the
  capture shows the active and inactive buttons and the hidden rows.
  Covered in `Tests/BridgeTests/editing.m`. The window captures still do
  not render the tab labels (a capture limitation seen before the
  swatches too).

## 2026-10-12: Phase 4, first step: sheet objects selected, moved, resized, deleted

- `GnmSheetObject` (Swift `SheetObject`): one wrapper per engine object
  for the life of the sheet (cached by pointer, holding a reference and
  listening to the object's `bounds-changed` and `unrealized` signals,
  which reach the delegate as `sheetObjectsDidChange:`). It reports the
  type name, frame in sheet pixels, attached and visible flags, and
  whether the user may select it (not cell comments, not filter combos,
  not objects without a cairo renderer). The sheet lists them front to
  back (`sheet->sheet_objects` is prepended on insertion), finds the one
  under a point, and runs the commands: `setFrames:ofSheetObjects:resizing:`
  over `cmd_objects_move` with anchors recomputed from the frames (a port
  of `scg_object_coords_to_anchor`, keeping each anchor's mode), `deleteSheetObjects:`
  over `cmd_objects_delete`, `restackSheetObject:direction:` over
  `cmd_object_raise`. Objects are now drawn back to front, as print.c
  does; they were drawn front first before, so overlaps came out wrong.
- Grid: a click on an object selects it (Shift or Command adds), the
  cell cursor hides meanwhile (the GTK object mode), eight handles on
  resizable objects, dragging the body moves and a handle resizes (Option
  for a symmetric resize, Shift to snap to the grid, both as GTK's
  `drag_object` does), with a dashed preview until the mouse goes up and
  the engine command runs. Delete and Backspace delete the selection,
  arrows nudge by a pixel (ten with Shift), Tab cycles through the
  objects, Escape leaves the object mode, a right-click offers Delete and
  the four stacking items. No live preview of the object itself while
  dragging, no cut, copy, or paste of objects, no double-click editor yet.
- Found on the way: the engine focuses the command's sheet on every
  control after each command (`update_after_action`), and the window
  controller passed that to the grid as a sheet change, which reset the
  scroll position, the editor, and now the object selection after every
  command. Both the controller and the grid now ignore a refocus of the
  current sheet.
- `Tests/BridgeTests/objects.m` (also an XCTest target) covers the
  wrappers, hit testing, move and resize with undo, two objects in one
  command, delete with undo, restacking, and drawing with a filter combo
  present. `GNM_SNAPSHOT_OBJECTS=1` moves and widens the front object
  and shows the handles in the capture.

## 2026-10-12: Phase 4, second step: the chart guru

- `GnmPlotType` (Swift `PlotType`): goffice's plot registry
  (`gog_plot_families`), 64 types in 18 families from the six plot
  plugins, ordered as the GTK guru shows them (families by priority, XY
  first, then Column, Bar, ...; types by row and column), each with its
  name, description, engine class, and the sample PNG the guru shows
  (`go_rsm_lookup` on the `res:go:...` resource names).
- `insertChartOfType:seriesLayout:sharedAbscissa:frame:` on the sheet
  builds what the guru's closure would hand back: a `GogGraph` with a
  chart and the plot (`gog_plot_new_by_type` applies the type's
  properties), the series read from the selection by the engine's own
  `sv_selection_to_plot` through the `GnmGraphDataClosure` it expects
  (series as columns or rows, the shared abscissa; a heading row names
  the series), the "guru-hints" backplane and major grid, a legend when
  there is more than one series, and a one-cell anchor (graphs do not
  resize with cells, as the GTK closure sets). The object is attached and
  committed with `cmd_objects_move` as a created object, so "Insert 1
  Object" undoes to nothing, as `scg_objects_drag_commit` does.
- `ChartGuru.swift` (Insert → Chart…): a sheet with the families in one
  table, the family's types with their sample images in another, the
  type's description, "Series as" (Auto, Columns, Rows), and the shared
  abscissa switch. Insert places the chart beside the selection when that
  fits in view, else near the visible area's top-left, at the engine's
  default 12 by 8 cm, and selects it. Not in it: the guru's later pages
  (every chart, plot, and series property), which are the object editor's
  job.
- `GNM_SNAPSHOT_CHART=1` inserts a clustered column chart from A1:D6 of
  `chart-tests.gnumeric` and writes the guru sheet to `-guru.png` (the
  two tables and their images render there; the description, pop-up,
  and buttons below come out blank in captures, the known limitation,
  and `GNM_DEBUG_LAYOUT=1` logs their frames instead).
  `Tests/BridgeTests/objects.m` covers the catalogue, the sample PNGs, a
  column chart from a three-series block (drawn into a bitmap and checked
  for ink), undo and redo of the insertion, and a pie from one series
  with the options set.

## 2026-10-12: Phase 4, third step: object clipboard and images

- Objects copy and cut: `copySheetObjects:cut:` over
  `gnm_app_clipboard_cut_copy_obj` (a cut deletes now, "Cut Object",
  undoable), and the existing `paste` puts copies at the selection
  through the engine's clipboard. The engine places a pasted copy's
  anchor cell at the target and keeps the original's offset within its
  cell, so a copy can land up to a cell away from the clicked cell (the
  GTK front end does the same). Copy and Cut on the grid act on the
  selected objects when there are any; the pasteboard gets a PNG of the
  first copied object (`sheet_object_write_image`), so other
  applications can take it.
- Images: Insert → Image… (an open panel) and a paste of PNG or TIFF data
  from the pasteboard (converted to PNG through `NSBitmapImageRep`) make
  a `SheetObjectImage` at its own size (one image pixel per point, as the
  engine sizes new images), as "Insert 1 Object". goffice guesses image
  types through the shared MIME database, which Homebrew does not
  install, so the bridge sniffs PNG, JPEG, GIF, BMP, and SVG itself and
  passes the type. `GnmWorkbook.canPaste` replaces the pasteboard-string
  check for the Paste items: the engine's clipboard when current, else
  text or an image on the pasteboard.
- The paste of an image runs an engine command inside the paste command,
  which the bridge's message collection used to refuse (an assertion);
  collections now nest, the inner command reporting into the outer.
- `GNM_SNAPSHOT_OBJECTS=1` also copies the front object, pastes it at
  A40, and inserts a green image; `Tests/BridgeTests/objects.m` covers
  copy, paste, undo, cut and paste, the PNG on the pasteboard, an image
  from data, a refused non-image, and an image pasted from the pasteboard.

## 2026-10-12: Phase 4, fourth step: the chart editor

- `GnmChartEditor` (bridge): the guru's later pages over a working copy of
  a chart's graph. The editor duplicates the graph (`gog_graph_dup`; the
  data objects come along bound to their sheet, so the copy evaluates live
  cells), the app edits the copy, and `apply` commits it with the engine's
  own "Reconfigure Graph" command (`cmd_so_graph_config (wbc, so, copy,
  old)`), undoable; cancel is releasing the editor. The copy's objects are
  `GnmChartNode`s (stable per object): name, role, type, children,
  deletable, reorderable (`gog_object_can_reorder`), the roles a child can
  take (`gog_object_possible_additions`), the generic GObject properties
  of the class (booleans, integers, doubles, texts, and the string
  properties the GTK editor shows as combos, with their choices: position
  compass and alignment, axis position and scale, interpolation, the
  bar/column/line/area "type", label justification, theme, regression
  drawing bounds; identity, layout, and cross-reference properties stay
  hidden), the data dimensions (`gog_dataset_get_dim`: series name and
  values, axis bounds, label texts) as expressions in the sheet's syntax
  read and written the way the GTK data allocator does (`go_data_serialize`
  with the sheet's conventions; `gnm_expr_parse_str` with unknown names as
  strings and lists for vectors, a scalar that does not parse is the text
  itself, `gnm_go_data_*_new_expr`), and the style as a value
  (`GnmChartStyle`: line, fill, marker, font, text angle, each with its
  automatic flag, applied through `go_style_dup` and
  `go_styled_object_set_style`). The preview renders the copy with
  `gog_graph_render_to_cairo`.
- A trap found by the test: a duplicated graph's data register as sheet
  dependents (`gnm_go_data_dup` calls `dependent_set_sheet`), and nothing
  unlinks them when an object leaves the copy or the copy goes, so a node
  outliving the workbook crashed in `dependent_unlink`. The editor now
  binds the copy's data the way a sheet object does (the graph's
  `add_data` and `remove_data` signals) and unlinks everything before
  releasing the copy.
- `ChartEditorWindow.swift` (double-click on a chart, its context menu's
  Properties…, Format → Object Properties…): a resizable sheet with the
  object tree, Add (the selected object's roles), Remove, and reorder
  buttons on the left, the live preview on the right, and below it the
  selected object's data fields, properties (checkboxes, number and text
  fields, pop-ups by kind), and style controls (color wells, dash and
  marker pop-ups, font family, size, bold, italic, angle). Every edit goes
  to the copy at once; Apply commits. A nested function in the style
  section held `self` through the handler closures (a cycle that kept the
  copy alive until quit); closures with weak captures now. The guru and
  editor sheets close their windows when done, so they leave the app's
  window list.
- Undo and redo of "Reconfigure Graph" give the grid no signal (the GTK
  canvas item listens to the renderer), so the bridge now tells the
  current sheet its objects may have changed after every undo and redo.
- `GNM_SNAPSHOT_EDITOR=1` opens the editor on the sheet's first chart,
  adds a title, inverts the X axis, colors the first series red, writes
  the editor to `-editor.png`, and applies before the grid capture.
  `Tests/BridgeTests/chart.m` (a new program, in the Xcode project and
  the XCTest bundle) covers the tree, property kinds and clamping, the
  hidden set, titles with literal and cell text, series names and
  values with a refused bad range, styles read back, legend position,
  adding, reordering, and removing, the preview, apply with undo and
  redo, and an editor whose chart was deleted.
- Not in it: changing a plot's type in place (insert a new chart), error
  bars, gradient and image fills, the guru's manual object positions,
  "Save as Image…", editors for images and widgets (`cmd_so_set_*`).

## 2026-10-12: plain-XML `.gnumeric` saves (an interim preference)

- Henry's request, pending the Preferences window: save `.gnumeric` files
  uncompressed, the GTK preference "Default compression level for
  Gnumeric files" at 0, so they diff under version control.
  `GnmEngineConfiguration.xmlCompressionLevel` (nil keeps the stored
  preference) is applied after `gnm_init()` through
  `gnm_conf_set_core_xml_compression_level`, which with persistence on
  stores it like any preference change, in the app's own defaults domain
  (ADR-010), not the GTK Gnumeric's. `AppDelegate.configuration()` sets 0
  at every launch; remove that line when the Preferences window arrives.
  `Tests/BridgeTests/workbook_io.m` starts its engine at level 0 and
  checks the `.gnumeric` output starts with `<?xml`.

## 2026-10-12: Quit did nothing after a save (fixed)

- Found while checking the compression change, then chased to the end:
  after an NSDocument save (the typing hook's Save As, and the user's
  ⌘S in place, checked with a new `GNM_SNAPSHOT_SAVE_INPLACE=1` variant
  of the hook) the app's Quit did nothing, headlessly and, by the same
  mechanism, on screen. `NSApp.terminate` never reached the delegate
  because an alert sheet was attached to the document window, and
  AppKit's review of documents at quit waits for sheets. The alert was
  "Could not set the text of C3": three defects stacked.
  1. `WorkbookWindowController.show(sheet:)` made the grid the first
     responder on every engine command (the engine focuses the command's
     sheet after each one), which ended the cell editor's editing in the
     middle of its own commit, so the editor committed the same text a
     second time. Now only a real sheet change takes the first responder,
     and `GridView.commitEditing` ends the session before it runs the
     command (and reopens the editor with the text if the command fails).
  2. The engine's `cmd_set_text` returns TRUE, as a failure would, when
     the text is unchanged ("nothing to do"), and the bridge turned that
     into an error. `GnmSheet.setText` now recognizes the case the way
     `cmd_set_text_full_check_text` does (a message-less TRUE with the
     cell already holding the text, after autocorrection) and reports
     success; `editing.m` covers it. Typing the same text into a cell
     again, or F2 then Return, used to show the alert too.
  3. Along the way the document's save moved to NSDocument's own staged
     write: the earlier `writeSafely` override handed the final URL to
     libgsf, which replaced the file under AppKit's coordinated write
     and left NSDocument's own bookkeeping (modification date, file
     presenter) behind. `write(to:ofType:)` now saves to the staged URL
     without adopting it (`GnmWorkbook.write(to:saverIdentifier:
     adoptingURL:)`, which records the saver and clears the dirty flag
     but leaves the location), and `save(to:...)` adopts the final URL
     when the save completes (`adoptFileURL`). The staged name is not
     the final one (`name.gnumeric.sb-…` for a save in place), so the
     saver comes from the document type (`Gnumeric_XmlIO:sax` for
     `.gnumeric`, `Gnumeric_XmlIO:sax:0` for `.xml`, goffice's choice by
     extension for `.xlsx`), not from the file name; `workbook_io.m`
     covers the staged save, the adoption, and the `.xml` saver under a
     staged name.
- Diagnostics kept: `WorkbookWindowController.present` and
  `WorkbookDocument.willPresentError` log every error they show, and the
  snapshot's fallback (three seconds after a terminate that went
  nowhere) logs the attached sheets' texts before exiting through the
  delegate's shutdown; it no longer fires.
- Still for Henry on screen: open a file, edit a cell, ⌘S, ⌘Q, and the
  same with Save As to a new name and to `.xml`; the captures say all
  three work, his screen decides.

## 2026-10-12: Save as Image…, the plot type change, and weak chart nodes

- Save as Image… (the object context menu, charts and images):
  `GnmSheet.imageFormatsForSheetObject:` lists a chart's formats
  (`gog_graph_get_supported_image_formats`: svg, png, jpeg, pdf, ps, eps)
  or an image's own format first and the raster ones goffice can convert
  to, as `GnmImageFormat` (name, summary, extension, whether a resolution
  applies); `writeImageOfSheetObject:format:resolution:toURL:` writes
  through `sheet_object_write_image` into a `GsfOutput` on the file. The
  controller's save panel has a format pop-up that switches the allowed
  type and the name's extension, and a resolution field (150 dpi, the GTK
  dialog's) for a chart's raster formats. `objects.m` writes a chart as
  PNG and SVG and an image back as PNG, and refuses an unwritable path.
- The plot type change in place (`GnmChartEditor.changeType:ofPlot:`,
  the editor's "Change Type…" button over the guru's type page with the
  current type preselected and the series options hidden): a new plot of
  the type, the series in the tree's order with their names and the
  dimensions both types share matched by Excel's roles
  (`gog_series_map_XL_dim`; a dimension the new type shares across its
  series, such as a column plot's categories, comes from the first
  series), the old plot out with its hold on the axes released
  (`gog_plot_axis_clear`), the chart's axis set reassigned
  (`gog_chart_axis_set_assign` adds what is missing; the axes outside the
  set are removed here, since it leaves them), the new plot in, the
  series' styles copied once the theme has had its say (copied earlier
  they were reset), and the type's guru hints. XY to Column keeps axes
  and their settings; to Pie and back makes new axes. `chart.m` covers
  XY to Column to Pie and back, the carried names, values, categories,
  and styles.
- Chart nodes no longer keep their objects alive. goffice frees a tree
  parent first and the children through it, and a series freed after its
  plot reads the plot's description from freed memory, so nodes that
  outlived the tree (the old plot's series after a type change) leaked
  data on some runs and would have crashed on others. A node now watches
  its object with `g_object_weak_ref`; the editor's graph keeps attached
  objects alive, a removed object goes at once in tree order, and its
  node becomes a tombstone (`isAttached` NO, the last name, nothing
  else), forgotten by the editor's cache so a reused address gets a
  fresh node. The style copy during a type change happens before the old
  plot's last reference goes, for the same reason.
- `GNM_SNAPSHOT_EDITOR=1` also changes the chart to columns before the
  capture.

## 2026-10-12: Phase 5 opens with the everyday items

- File → New (⌘N) and an untitled workbook at launch when no file is
  named: `WorkbookDocument.init(type:)` takes a one-sheet workbook from
  the engine (`makeWorkbook(sheetCount:)`).
- The name box takes a reference or a name and Return
  (`GnmWorkbook.jumpToReference:` over `wb_control_parse_and_jump`, the
  GTK name box and Go To): a cell, a range, a sheet-qualified reference
  (switching sheets), A1 or R1C1, or a defined name; a plain word
  defines a name for the selection, as in GTK; a reference to a missing
  sheet is an error. Edit → Go To… (⌃G) asks the same in a sheet.
- Insert → Cells… and Edit → Delete Cells…: the GTK dialogs' four
  choices as radio buttons (shift cells right or down, left or up;
  entire rows or columns), over `cmd_shift_rows` and `cmd_shift_cols`
  with the dialogs' exact arguments (`insertCellsInRange:shiftingDown:`,
  `deleteCellsInRange:shiftingUp:`), undoable as "Shift …".
- Insert → Current Date (⌘;), Current Time (⇧⌘;), Current Date and
  Time: the bridge formats today the way `insert_date_time_common` does
  (the cell's date format when it has one, else the default date and
  time formats, in the sheet's date conventions); the grid types the
  text into an open editor at the insertion point or into the cell.
- Save As to CSV: a fourth writable type (`Gnumeric_stf:stf_csv`, the
  current sheet with the exporter's defaults; the options dialog is
  still a gap) and the delimited-text document type promoted to Editor;
  opening a `.csv` already went through the engine's text importer with
  its guessed options (`workbook_io.m` now checks both ways).
- `GNM_SNAPSHOT_EVERYDAY=1` jumps through the name box, types the date,
  shifts a cell, saves a CSV beside the capture, and makes a new
  document; `editing.m` covers the shifts with undo, the date and time
  texts, and the jumps.

## 2026-10-12: Find and Replace

- The bridge (`GnmSearch.h`, `GnmSearch.m`): `GnmSearchOptions` holds
  what the GTK Search and Search & Replace dialogs collect, with the
  `gnumeric-conf` defaults; `findMatches:inSheet:` builds the engine's
  `GnmSearchReplace` the way `dialog-search.c` does, runs
  `gnm_search_collect_cells` and `gnm_search_filter_matching`, and
  returns `GnmSearchMatch` values (sheet, cell, locus, the Matches
  page's Type and Content columns, and a quoted reference);
  `replaceMatches:inSheet:queryHandler:` runs `cmd_search_replace` with
  the engine's query function answered by a block (Replace, Skip,
  Cancel, and "do not ask again"), the Fail behavior's refusal turned
  into the error `wbc-gtk-actions.c` shows.  `GnmSheet` gained
  `selectionText` (`selection_to_string`, absolute and sheet-qualified,
  for the Range field) and `revealCellAtColumn:row:` (the dialog's
  cursor change: focus the sheet, select, scroll).
- The panel (`FindPanel.swift`): a floating utility panel per document
  window with the two texts, the scope (workbook, sheet, a range that
  starts as the selection), the cell kinds, the text kind (plain,
  regular expression, number), the order, case and whole-word options,
  the replace options (preserve case, keep strings, ask before each
  change), the invalid-replacement behavior, Find All / Previous / Next
  / Replace / Replace All, and the matches table; choosing a match
  selects its cell (switching sheets), Replace runs the command over the
  chosen cell as a range, and the ask-before-each-change question is a
  modal alert with "Do not ask again".  Options persist in the app's
  own defaults.  Edit → Find… (⌘F), Find and Replace… (⌥⌘F), Find Next
  (⌘G), Find Previous (⇧⌘G); Find Next from the document window steps
  the panel's matches.  Escape closes the panel; it closes with its
  window.
- Engine facts settled by `Tests/BridgeTests/search.m`: a regular
  expression ignores case when told to (so `^a.*e$` finds "Apple pie");
  a kept string's replacement is shown with its leading quote (`'pear`);
  a kept string never fails to parse, so the error behaviors only act
  with "Keep strings" off; a range scope visits cells with content only,
  so a comment on an empty cell is reached by the sheet and workbook
  scopes alone; a cancelled replace keeps the changes made so far as one
  command.  `GNM_SNAPSHOT_FIND=1` drives the panel headlessly and
  captures it to `-find.png` (the capture omits buttons, as it does tab
  labels).

## 2026-10-12: The Settings window

- `GnmPreferences` (`GnmEngine.preferences`): the engine's configuration
  keys the app or the engine honors, as properties over `gnm_conf_get_*`
  and `gnm_conf_set_*`, each write taking effect at once and persisting
  through GSettings' NSUserDefaults backend under the bundle identifier
  (ADR-010): the `.gnumeric` compression level, the new-workbook sheet
  count, rows, columns, and zoom, the default font, where Return moves,
  the four Auto Correct switches, the undo limits and sheet naming, and
  the Sort dialog's defaults.  `Tests/BridgeTests/preferences.m` checks
  the schema's defaults (sheet count 1, undo size 100000, sheet names
  off in 1.12.62), the round trips and clamping, the Sort defaults
  following, and the saver writing plain XML at 0 and gzip at 9.
- Gnumeric → Settings… (⌘,): `PreferencesWindow.swift`, a SwiftUI form
  in five tabs (General: files and new workbooks; Editing: Return's
  direction and Auto Correct; Undo; Sorting; Font) over an
  `ObservableObject` whose `didSet`s write to the bridge.  A standalone
  hosting window starts at no size, so it is sized from the view's
  fitting size.  `GNM_SNAPSHOT_PREFS=1` opens it, changes the
  compression level through the model and reads it back from the
  engine, captures `-settings.png`, and closes it.
- What follows the preferences now: File → New makes the preferred
  number of sheets; Return in the grid and the cell editor moves in the
  preferred direction (`CellEditorField.Movement.enter`,
  `GridView.moveAfterReturn`); the Sort dialog already read its
  defaults.  The launch-time compression override in `AppDelegate` is
  gone: Henry's 0 is in the app's defaults
  (`/org/gnome/gnumeric/core/xml/compression-level`), and a fresh
  install gets the GTK default 9 until changed in Settings.  Reads come
  from the defaults even with `GNM_PERSIST_PREFS=0`, which only stops
  writes.

## 2026-10-12: Export as Text with options

- `GnmTextExportOptions` (`GnmTextExport.h`): what the GTK "Export as
  Text" dialog collects (the sheets in order, line ending, separator,
  quoting and quote character, encoding, locale, unknown characters,
  format mode, formulas).  `GnmWorkbook.textExportOptions` reads the
  workbook's `GnmStfExport` (`gnm_stf_get_stfe`: the preferences'
  defaults, or the last export's choices); `writeToURL:textExportOptions:
  rememberAsDefault:adoptingURL:` sets it the way
  `stf_export_dialog_finish` does (quoting triggers included), fills the
  sheet list, and saves through `Gnumeric_stf:stf_assistant`, which
  without a GTK control runs no dialog; `remember` stores the choices in
  `gnm_conf`'s `stf_export` keys.
- `TextExportSheet.swift`: a SwiftUI sheet (sheet toggles with Select
  All and None, then the formatting pickers) over an `ObservableObject`;
  `WorkbookDocument` gained the "Text (configurable)" writable type
  (`public.plain-text`, `.txt`, an Info.plist type with role None so
  the app does not claim to open plain text yet), and its `save(to:…)`
  asks for the options first, then saves with them pending.
- Engine facts settled by `Tests/BridgeTests/text_export.m`: the
  automatic format mode writes raw values except dates (a 50.00% cell
  exports as 0.5; Preserve keeps the display text); an empty sheet list
  makes the saver take every sheet and clear the list again; the
  workbook keeps the options of its last export; the C locale and an
  ISO-8859-1 encoding reach the file.  `GNM_SNAPSHOT_TEXT=1` saves the
  sample as text headlessly (the sheet captured to `-export.png`, then
  semicolons and quotes always).

## 2026-10-12: The text import assistant

- `GnmTextImportSession` (`GnmTextImport.h`): a session over the
  engine's `GnmStfParseOptions` holding the decoded text
  (`go_guess_encoding`, NULs blanked as `stf.c` does), the options the
  GTK assistant's pages set (kind, line breaks, the lines to import,
  separators and quotes, split positions with the engine's discovery,
  trimming, locale, per-column formats and choices), previews
  (`stf_parse_general` over the chosen range, untrimmed as the GTK
  preview is), and `GnmEngine.importTextSession:`: the parse into a new
  one-sheet workbook as `stf_read_workbook` does after its dialog
  (`stf_parse_sheet`, columns fitted, the text saver recorded at the
  write-only level, the file as the location).
- `TextImportAssistant.swift`: the three pages (main; separators or
  fixed width; format with a per-column format and import toggle) over
  a shared preview `Table`, as a modal window, since the GTK dialog runs
  inside the opener and NSDocument reads synchronously.  Plain text
  (`public.plain-text`, now an Editor type) reads through it; `.csv` and
  `.tsv` keep the engine's guessed options; File → Import Text… (⇧⌘O)
  sends any text file through it.  A headless run drives it through
  `TextImportAssistant.headlessDriver`.
- Engine facts settled by `Tests/BridgeTests/text_import.m`:
  `go_guess_encoding` says "ASCII" for pure ASCII and falls back from an
  encoding the bytes are not in rather than failing; the `.txt` guesser
  can pick a comma where a semicolon file has commas in its fields (the
  CSV rules apply to `.csv` names only); the parse options' format
  arrays free their elements themselves (a manual unref crashed);
  formats are guessed once, so new columns after a separator change are
  general until guessed again.  `GNM_SNAPSHOT_IMPORT=1` imports a
  semicolon file headlessly (the assistant captured to `-import.png`).

## 2026-10-12: Cell comments

- `GnmSheet` gained comments: `commentAtColumn:row:` and
  `commentsInRange:` (`sheet_get_comment`, `sheet_objects_get` with
  the comment type) return `GnmCellComment` values (position, author,
  text); `setCommentText:author:atColumn:row:` runs `cmd_set_comment`
  ("Setting comment of C3", or "Clearing comment of C3" for an empty
  text, which is how the engine removes one; it wants both strings
  non-NULL).  `Tests/BridgeTests/comments.m` covers set, read, range
  listing, change, undo and redo, removal, the search finding comments,
  and Edit → Clear → Comments.
- The grid draws the GTK indicator (a small red triangle in the cell's
  top-right corner, `comment_view_set_bounds`) and keeps a tool tip
  rect per commented cell, so hovering shows "Author:\ntext".  A cell's
  context menu (new: right-clicking a cell selects it) offers Insert
  Comment…, or Edit Comment… and Delete Comment; Insert → Comment… (the
  title says Edit Comment… over one) opens the GTK dialog's equivalent
  as an alert sheet: the author (the user's full name for a new one)
  and the text, with Remove for an existing one.
- `GNM_SNAPSHOT_COMMENT=1` sets a comment on A3, logs the tool tip, the
  context menu, the removal and its undo, and leaves the marker in the
  capture.

## 2026-10-12: Defined names

- `GnmNames.h`: `GnmDefinedName` (name, scope sheet or nil for the
  workbook, the expression text relative to the sheet's edit position
  as the GTK dialog shows it, editable unless permanent, in use) and a
  `GnmWorkbook (Names)` category: `definedNamesForSheet:` (the
  workbook's names and the sheet's, sorted, hidden and placeholder ones
  left out), `defineName:expression:scope:inSheet:` (validated with
  `expr_name_validate`, parsed with unknown names invalid and multiple
  expressions permitted, then `cmd_define_name`, which also redefines),
  `removeName:` (`cmd_remove_name`), `changeScopeOfName:toSheet:`
  (`cmd_rescope_name`).
- Link flag: the bridge's categories live in their own object files,
  which a static link drops unless `-ObjC` is given; `run.sh`,
  `build-app.sh`, and both Xcode targets now link with it (the earlier
  categories survived only because their files also define classes the
  app allocates).
- `NamesDialog.swift` (Edit → Define Names…): the table of names with
  their scope and expression, fields for the chosen or a new one, Add
  or Update, Remove (asking first when the name is in use), Close.
  Insert → Name… lists the names in a pop-up and puts the chosen one
  into the cell editor (`GridView.insertName`: "=name" into an empty
  cell, the name at the caret otherwise, as the GTK paste does).
- Engine facts settled by `Tests/BridgeTests/names.m`: every sheet
  carries the permanent `Print_Area` and `Sheet_Title` names; the
  command labels carry the name ("Define Name total"); a sheet name's
  expression is written without its own sheet's prefix, and relative
  references move with the edit position; the name box's jump defines
  names that the dialog then lists.  `GNM_SNAPSHOT_NAMES=1` adds a
  name through the dialog (captured to `-names.png`) and inserts it.

## 2026-10-12: Fill Series and Text to Columns

- Fill Series (`GnmSheet.fillSeriesInRange:byRows:kind:dateUnit:start:
  step:stop:`): the engine's `GnmFillSeriesTool` through
  `cmd_analysis_tool` with a range output description (`dao_init` with
  the selection as `GNM_DAO_OUTPUT_RANGE`, as the GTK dialog's
  `dao_parse_output` fills it), the command owning the description and
  keeping the tool; `numberFromText:` reads the dialog's entries as the
  GTK `entry_to_float` does (`format_match_number`, so dates and times
  read as serials).  Edit → Fill → Series… is an alert sheet (series in
  rows or columns, linear, growth, or date with its unit, start, step,
  stop; start and stop from the selection's first and last cells).
- Text to Columns (`GnmSheet (TextToColumns)` in `GnmTextImport.h`):
  `textToColumnsSessionWithError:` builds an import session from the
  selection's column (formulas as written, values as displayed, as
  `stf_text_to_columns` does; one column only, and not empty);
  `textToColumnsWithSession:` parses it into a cell region
  (`stf_parse_region`), attaches the column formats as
  `stf_dialog_result_attach_formats_to_cr` does, and pastes it into the
  columns to the right with `cmd_text_to_columns`.  Data → Text to
  Columns… runs the import assistant on it (titled accordingly).
- Engine bug, patched: `cmd_analysis_tool_undo` destroyed its saved
  column and row state lists without clearing the pointers, and the
  redo destroyed them again, an abort on macOS for every range-output
  analysis tool on undo then redo.  `patches/0003-analysis-tool-undo-
  colrow-state.patch` sets the pointers to NULL; the GTK front end runs
  the same code.
- `Tests/BridgeTests/fill_series.m` (linear by step and by stop, a stop
  cutting the range, growth across a row, month and weekday dates, the
  number reader, undo and redo, the refusal without step or stop) and
  the Text to Columns block of `text_import.m` (two columns refused,
  the formula as written, the parse, undo, no data refused).
  `GNM_SNAPSHOT_FILL=1` fills F1:F6 and splits G1:G2 headlessly.

## 2026-10-12: Goal Seek

- `GnmSheet.goalSeekCellAtColumn:row:toValue:byChangingCellAtColumn:row:
  minimum:maximum:` runs `gnm_goal_seek_cell` as the GTK dialog's
  apply does (the set cell must hold a formula, the changing cell must
  not; the bounds default to ±1e24), recalculates, and on success
  commits `cmd_goal_seek` with the changing cell's old value, undoable
  as "Goal Seek (A1)"; without a solution the old value goes back and
  `GnmGoalSeekResult.found` is NO.  `parseCellReference:column:row:`
  (`cellpos_parse`) reads the dialog's cell fields.  A new Tools menu
  holds Goal Seek…, an alert sheet with the five fields and a result
  alert after.  `Tests/BridgeTests/goal_seek.m`: a root found and
  undone, the negative root under bounds, a seek with no solution
  leaving the cell alone, the two refusals, an empty changing cell.
  The engine renders negative numbers with a true minus (U+2212).
  `GNM_SNAPSHOT_GOAL=1` seeks A30 headlessly.

## 2026-10-12: Conditional formatting

- `GnmConditionalFormat` (`GnmConditionalFormat.h`): an operator (the
  engine's `GnmStyleCondOp`, whose values `.gnumeric` files store), its
  one or two expressions, and the overlay as a `GnmCellFormat` of set
  parts.  `GnmSheet.conditionalFormatsAtColumn:row:` reads a cell's
  conditions (expressions written relative to the edit position, as the
  GTK dialog shows them; `gnm_cocoa_format_from_style` turns the
  overlay into a format); `setConditionalFormats:` builds a
  `GnmStyleCond` per condition (`gnm_cocoa_format_to_engine` for the
  overlay, expressions parsed with unknown names as strings) into a
  `GnmStyleConditions` on a partial style, applied to the selection with
  `cmd_selection_format` as "Set conditional formatting"; an empty array
  clears them.
- The grid now evaluates conditions when it draws a plain cell's
  background (`item_grid_draw_background` did; the merged-cell path
  already did), so conditional fills show.  Text styles come through
  the cell's rendered value, which the engine computes from the
  effective style.
- `ConditionalFormatDialog.swift` (Format → Conditional Formatting…):
  the conditions on the selection's cell in a table (described in the
  dialog's words, with the overlay's parts), an editor for the chosen or
  a new one (the operator pop-up in the GTK order, x and y, fill, text
  color, bold, italic, number format), Add, Replace, Remove, Clear All,
  and OK applying the list as one command.
- `Tests/BridgeTests/conditional.m`: set, read back with the overlay,
  the selection only, undo and redo, two operands, a custom condition
  shown relative to the edit position, the errors, a save and reopen
  keeping them, clearing.  `GNM_SNAPSHOT_COND=1` puts "value > 100 →
  yellow, bold" on B5:B12 through the dialog (captured to `-cond.png`)
  and the grid capture shows the fills.

## 2026-10-12: The analysis tools

- `GnmAnalysis.h`: `GnmAnalysisOutput` (the dialogs' Output page: a new
  sheet named after the tool, or a range named as the dialogs take it,
  with autofit, clear, retain formatting and comments, and formulas or
  values), `GnmAnalysis` and its tools: `GnmDescriptiveStatistics`
  (summary, SSMEDIAN, a confidence interval for the mean, kth largest and
  smallest), `GnmCorrelationAnalysis`, `GnmCovarianceAnalysis` (all three
  over a range list grouped by columns, rows, or areas, with labels), and
  `GnmRegressionAnalysis` (x and y ranges, labels, confidence level, zero
  intercept, residuals, one multiple regression or 2-variable ones,
  several y).  `GnmSheet.runAnalysis:output:` builds the engine's tool
  object as the dialogs' OK handlers do (`global_range_list_parse` for
  the input), the output description, and runs `cmd_analysis_tool`,
  returning the sheet written to; the dialogs' validations and their
  words come first (vector y, matching sizes, the confidence level, "No
  statistics are selected.", the equal-size refusal from the tool's
  error code).  `rangeNamesInList:` names the ranges in a list, which
  the dialog uses to turn the selection into "A1:B6".
- Engine facts: `cmd_analysis_tool` takes the output description over
  and frees it on failure too (its finalize), so the caller never frees
  it; a new-sheet run attaches and focuses the sheet inside the command
  (the delegate's didAdd and didFocus follow), and undo removes it;
  the correlation tool writes the lower triangle; the covariance tool
  uses COVAR (population); with labels the variable names head the
  rows and columns.
- `AnalysisDialog.swift` (Tools → Statistics → Descriptive Statistics…,
  Correlation…, Covariance…, Regression…): one alert sheet per tool with
  the Input rows (the selection as the input, grouping, labels), the
  tool's rows, and the Output rows; a refusal shows the message and
  re-presents the sheet with its values kept.  The sheet written to is
  shown.
- `Tests/BridgeTests/analysis.m` (18 XCTest programs now): descriptive
  statistics to a new sheet with undo and redo, correlation and
  covariance (by areas, formulas entered) into ranges, regression
  coefficients, the range list reader, and the refusals.
  `GNM_SNAPSHOT_STATS=1` fills A1:B6, runs a correlation into D1 through
  the dialog (captured to `-stats.png`), then descriptive statistics to
  a new sheet, which the grid capture shows.

## 2026-10-12: Data validation

- `GnmValidation.h`: `GnmCellValidation` (the engine's `GnmValidation`
  name is taken): kind, operator, the one or two expressions relative to
  the edit position, empty cells allowed, the in-cell list, the action
  (None, Stop, Warning, Information) with its title and message;
  `GnmInputMessage`.  `GnmSheet` reads a cell's validation and input
  message, sets the selection's as the Format Cells dialog applies its
  pages (`gnm_validation_new` and `gnm_input_msg_new` on a partial style,
  `cmd_selection_format` "Set validation"; Any Value and nil clear),
  checks an entry as `wbcg_edit_finish` does (`clipboard_copy_range_undo`,
  `sheet_cell_set_text`, `gnm_validation_eval`, `go_undo_undo`), and
  lists an In List source's distinct displayed values sorted as the GTK
  validation combo does.  The control's `validation_msg` vfunc asks the
  workbook delegate (`workbook:presentValidationMessage:title:action:`)
  and returns its status; without a delegate Stop and Warning discard,
  as the GTK dialog's default response does.
- Engine facts: an empty title gives "Gnumeric: Validation"; the
  engine's own messages are "'x' is not an integer", "x is out of
  permitted range", "<source> does not contain the new value.",
  "<criteria> is not true.", and "Cell X is not permitted to contain
  strings"; a None action accepts silently without asking.
- `ValidationDialog.swift` (Data → Validation…): the Criteria rows
  (Allow, Condition, the value fields relabeled as the GTK page does:
  Min, Max, Value, Source, Criteria), Ignore empty cells, In-cell
  dropdown, the Error alert rows, and the Input message rows, prefilled
  from the edit position.  `GridView` validates an entry before the
  command (Stop re-edits or discards, Warning accepts or discards,
  Information accepts, through the controller's alerts with the GTK
  default first), draws the list arrow just right of the edit cell
  (click or Option-Down opens the choices as a menu, choosing enters the
  value), and draws the input message under the cell while it is
  selected.
- `Tests/BridgeTests/validation.m` (19 XCTest programs now) and
  `GNM_SNAPSHOT_VALID=1` (C1 takes a value from B1:B5 through the dialog,
  captured to `-valid.png`; "7" refused with the engine's words, "3"
  taken; the grid capture shows the arrow and the message).

## 2026-10-12: More analysis tools

- `GnmAnalysis.h` grew `GnmTwoSampleAnalysis` (variable 1 and 2 ranges,
  labels, alpha) with `GnmMeanTestAnalysis` (paired, known variances as
  the z-test, equal and unequal variances; the hypothesized mean
  difference and the population variances) and `GnmVarianceTestAnalysis`
  (the F-test), and the grouped `GnmAnovaSingleFactorAnalysis`,
  `GnmRankingAnalysis`, `GnmSamplingAnalysis` (random or periodic),
  `GnmMovingAverageAnalysis` (simple, cumulative, weighted, Spencer;
  prior, central, or an offset; standard errors; a chart), and
  `GnmExponentialSmoothingAnalysis` (the five kinds with their factors
  and the seasonal period; standard errors; a chart), each with the GTK
  dialog's validations and words and the OK handler's mapping
  (`average_tool_ok_clicked_cb`'s interval and offset rewriting).
- Engine fact that cost an hour: the dialogs' range entries carry
  `GNM_EE_FORCE_ABS_REF`, so `gnm_expr_entry_parse_as_value` forces
  absolute references; a relative range embedded as a constant in the
  tool's expressions is shifted when the output evaluates it elsewhere
  (the z-test showed the mean of the wrong column).  `single_range` now
  parses with `value_new_cellrange_parsepos_str` and
  `GNM_EXPR_PARSE_FORCE_ABSOLUTE_REFERENCES`; range lists keep
  `global_range_list_parse` as the GTK list entries do.  Other facts:
  periodic sampling takes `size` values a period apart (an offset of 0
  means the period); with labels the moving average does not write the
  last value; the new sheets are "t-Test (1)", "z-Test (1)", "F-Test
  (1)", "Single Factor ANOVA (1)", "Ranks (1)", "Sampling (1)", "Moving
  Average (1)", "Exponential Smoothing (1)"; a chart lands on the output
  sheet as a sheet object the command owns (undo removes it).
- `AnalysisDialog.swift` has a tool case for each, under Tools →
  Statistics (grouped as the GTK menu groups them: descriptive,
  dependent, tests, time series); `GNM_SNAPSHOT_STATS=1` also runs a
  paired t-test into D6 through the dialog.
- `analysis.m` covers them all (the paired, z, and Welch statistics,
  the F, the ANOVA sum of squares, ranks, every second value, averages
  of pairs, the smoothing chart) and their refusals.

## How to resume (updated 2026-10-12)

1. Start Claude Code here and say "read HANDOFF.md and docs/progress.md and
   continue with Phase 4". `HANDOFF.md` §9 is the checklist: smoke tests,
   the Xcode build, the ADR-011 rule on upstream, what Henry has and has
   not seen on screen, and the rest of Phase 4 (object selection, move,
   resize, delete, stacking, the chart guru, the object clipboard, images,
   the chart editor with its plot type change, and Save as Image… are
   done; Phase 5 has begun with File → New, Go To and the name box,
   Insert and Delete Cells, the current date and time, Save As CSV,
   Find and Replace, the Settings window, and Export as Text with
   options, the text import assistant, cell comments, defined names,
   Fill Series, Text to Columns, Goal Seek, conditional formatting, and
   twelve analysis tools, and data validation; next the rest of Phase 5
   by usage frequency: Solver, hyperlinks, the remaining statistics
   (frequencies, histograms, the non-parametric tests, two-factor
   ANOVA, Fourier, Kaplan-Meier, principal components)) from
   `docs/mvp-known-gaps.md`, which also
   lists the smaller Phase 3 items still open (Insert/Delete Cells, Goto,
   the name box, the formula bar, autocomplete, drag and drop, outlines).
2. Working pattern that held up: wrap the engine call in the bridge with a
   test in `Tests/BridgeTests/editing.m` (mirror the GTK callback in
   `wbc-gtk-actions.c` or `wbc-gtk.c`), add the menu item (string selector
   on `MainMenu`, action on `GridView` or the window controller), drive it
   from a `GNM_SNAPSHOT_*` hook in `AppDelegate.swift`, look at the
   `-window.png` capture, update `docs/mvp-known-gaps.md`, commit.
   For goffice questions (the chart editor needed many): write a probe
   program that imports `Sources/Bridge/GnmPrivate.h` and
   `Tests/BridgeTests/GnmTest.h`, compile it with
   `scripts/build-bridge.sh --flags` plus `-I Sources/Bridge -I
   Tests/BridgeTests` against `build/bridge/libGnmCocoa.a`, open a
   sample, and print what the engine does (reference counts, property
   lists, serialized data); goffice ships no source, but its reference
   manual is at
   `/opt/homebrew/Cellar/goffice/0.10.62/share/gtk-doc/html/goffice-0.10/`.
   Facts the probes settled: `gog_object_clear_parent` hands the parent's
   reference to the caller (unref it); `gog_graph_dup` duplicates the
   data objects and `gnm_go_data_dup` links them as sheet dependents; a
   command's `update_after_action` does not redraw objects.
3. The state at the end of 2026-10-12: `main` at the second analysis
   tools commit (after data validation, the first analysis tools, conditional formatting, Goal Seek, Fill Series and Text to Columns, defined names, cell comments, the text import assistant, Export as Text, the Settings window, Find and Replace, the everyday items, Save as Image, the Quit fix, the plain-XML saves, the
   chart editor, the object clipboard, chart guru, sheet objects, and
   autofilter ones), clean tree, nothing pushed,
   `v0.1.0` and `upstream-baseline-2026-10-11` tagged. The engine in
   `build/prefix` has both patches applied.
