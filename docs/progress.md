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

## How to resume (updated 2026-10-12)

1. Start Claude Code here and say "read HANDOFF.md and docs/progress.md and
   continue with Phase 4". `HANDOFF.md` §9 is the checklist: smoke tests,
   the Xcode build, the ADR-011 rule on upstream, what Henry has and has
   not seen on screen, and the rest of Phase 4 (object selection, move,
   resize, delete, stacking, the chart guru, the object clipboard, and
   images are done; next the chart and object editors, then Phase 5) from
   `docs/mvp-known-gaps.md`, which also
   lists the smaller Phase 3 items still open (Insert/Delete Cells, Goto,
   the name box, the formula bar, autocomplete, drag and drop, outlines).
2. Working pattern that held up: wrap the engine call in the bridge with a
   test in `Tests/BridgeTests/editing.m` (mirror the GTK callback in
   `wbc-gtk-actions.c` or `wbc-gtk.c`), add the menu item (string selector
   on `MainMenu`, action on `GridView` or the window controller), drive it
   from a `GNM_SNAPSHOT_*` hook in `AppDelegate.swift`, look at the
   `-window.png` capture, update `docs/mvp-known-gaps.md`, commit.
3. The state at the end of 2026-10-12: `main` at the object clipboard
   and images commit (after the chart guru, sheet objects, and autofilter
   ones), clean tree, nothing pushed,
   `v0.1.0` and `upstream-baseline-2026-10-11` tagged. The engine in
   `build/prefix` has both patches applied.
