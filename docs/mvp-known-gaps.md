# MVP known gaps (v0.1.0, 2026-10-11)

Every GTK Gnumeric feature not yet in the Cocoa app, per `HANDOFF.md` Phase 2b.
The list is the GTK front end's menu structure (`src/GNOME_Gnumeric-gtk.xml`,
202 items in 43 menus, extracted 2026-10-11) with a status each, plus the
features that are not menu items. `docs/parity.md` (Phase 7) grows from this
file; keep the two in step.

Status: **ported** (native equivalent exists), **partial** (works with
limits noted), **bridge** (the engine call is wrapped in `Sources/Bridge`
but there is no UI yet), **no** (not started). The "Phase" column is where
`HANDOFF.md` §4 schedules it.

## File

| Action | Status | Notes / Phase |
|---|---|---|
| FileNew | no | the app opens no untitled document yet (`newWorkbook` exists in the bridge) |
| FileOpen | ported | every engine opener; CSV with default options |
| FileSave, FileSaveAs | ported | `.gnumeric`, uncompressed `.xml`, `.xlsx`; other savers need Save As types |
| FilePageSetup, FilePrintPreview, FilePrint, FilePrintArea* (6) | no | printing, Phase 3+ (`docs/architecture.md` §7) |
| FileSend | no | Phase 5 |
| FileMetaData (Properties) | no | Phase 5 |
| FileHistoryFull | ported | `NSDocumentController` recents |
| FileClose, FileQuit | ported | |

## Edit

| Action | Status | Notes / Phase |
|---|---|---|
| Undo, Redo | ported | engine command stack, labels in the menu |
| EditCut, EditCopy, EditPaste | ported | engine clipboard; text to and from other apps; selected objects, with a PNG out and images in |
| EditPasteSpecial | ported | Edit → Paste Special… (⌘⇧V): what, operation, region transform, the four switches, Paste Link |
| EditFind, EditReplace | no | Phase 5 |
| EditRecalc | ported | Data → Recalculate (F9), `workbook_recalc_all` |
| EditPreferences | no | Phase 5 |
| EditClearContent | ported | Delete key and Edit → Delete |
| EditClearAll, EditClearFormats, EditClearComments | ported | Edit → Clear submenu |
| EditClear*Filtered (4) | ported | Edit → Clear → "… Filtered Rows" (2026-10-12); as in GTK they skip the rows a filter hides |
| EditDeleteColumns, EditDeleteRows | ported | Edit menu; the selection's columns or rows |
| EditDeleteCells | no | Phase 3 |
| EditClearHyperlinks, EditComment, EditHyperlink, EditNames | no | Phase 5 |
| InsertSheet, InsertSheetAtEnd, EditDuplicateSheet, SheetRemove, SheetChangeName | ported | Edit → Sheet and the tab context menu; rename through a prompt |
| SheetReorder | partial | Move Left / Move Right; no Manage Sheets dialog or drag |
| SheetResize | ported | Edit → Sheet → Resize… (2026-10-12): powers of two, optionally every sheet |
| EditSelectAll | ported | ⌘A and the header corner |
| EditSelectColumn, EditSelectRow | ported | header clicks and Edit → Select |
| EditSelectArray, EditSelectDepends, EditSelectInputs, EditSelectObject | no | Phase 3/4 |
| EditGotoTop/Bottom/First/Last, EditGoto | partial | Home and ⌘↑ work; no name-box navigation or Goto dialog |

## View

| Action | Status | Notes / Phase |
|---|---|---|
| ViewNew | no | second window on one workbook (`control_new` slot), Phase 3 |
| ViewFreezeThawPanes | ported | View → Freeze/Unfreeze Panes with the GTK placement rules; files with frozen panes open frozen |
| ViewStatusbar | partial | the auto-expression (Sum/Min/Max/Average/Count of the selection) sits at the right of the tab bar; no hide toggle, no other status fields |
| ViewFullScreen | no | enable the window's full-screen behavior, Phase 3 |
| FormatWorkbook (workbook properties) | no | Phase 5 |
| ViewZoom | partial | fixed steps via View menu; no zoom dialog or percentage entry |

## Insert

| Action | Status | Notes / Phase |
|---|---|---|
| InsertCells | no | Phase 3 |
| InsertColumns, InsertRows | ported | Insert menu; as many as the selection spans, before it |
| SheetInsert | ported | Edit → Sheet → Insert |
| ChartGuru | ported | Insert → Chart… (2026-10-12): every goffice plot type with its sample image, series from the selection, the two guru options; the later pages are the chart editor (double-click, Properties…, Format → Object Properties…): object tree with add, remove, reorder, live preview, every object's data expressions, properties, and style; not in it: changing a plot's type in place, error bars, gradient and image fills, manual positions |
| InsertImage | ported | Insert → Image… (2026-10-12), and PNG or TIFF pasted from other applications |
| InsertComponent, InsertShapedComponent, NewGOComponent, GOComponentFromFile | no | Phase 4; goffice components (equations, embedded documents) |
| InsertFormula (function selector), InsertNames | no | Phase 5 |
| InsertComment, InsertHyperlink | no | Phase 5 |
| InsertSortDecreasing, InsertSortIncreasing | ported | Data → Sort Ascending / Descending (the GTK quick sort: by the selection's columns, heading kept) |
| InsertCurrentDate, InsertCurrentTime, InsertCurrentDateTime | no | Phase 3 |

## Format

| Action | Status | Notes / Phase |
|---|---|---|
| FormatCells | partial | number, alignment, font, border, fill; no protection, validation, input message, or conditional pages; no format preview |
| FormatCellsCond | no | Phase 5 |
| FormatMergeCells, FormatUnmergeCells | ported | Format menu, with Merge and Center (`patches/0002` fixes an engine double-unref there) |
| FormatCellsFitHeight, FormatCellsFitWidth | bridge | `autofitSelectedCells(width:)`; the menu has the whole-column/row Autofit |
| FormatAuto | no | Phase 5 |
| FontBold, FontItalic, FontStrikeThrough, FontUnderline*, FontSuperscript, FontSubscript | partial | through the dialog only; no shortcuts, toolbar, or script |
| ColumnSize, RowSize, ColumnAutoSize, RowAutoSize, ColumnDefaultSize, RowDefaultSize | ported | Format → Column / Row (points); headers drag-resize and autofit on a boundary double-click |
| ColumnHide, RowHide, ColumnUnhide, RowUnhide | ported | Format → Column / Row |
| SheetDisplayFormulas, SheetUseR1C1, SheetHideZeros, SheetHideGridlines, SheetHideColHeader, SheetHideRowHeader, SheetDirection | partial | the grid honors the file's settings (except direction, drawn left-to-right); no menu items, Phase 3/7 |

## Tools and Statistics

| Action | Status | Notes / Phase |
|---|---|---|
| ToolsAutoCorrect, ToolsAutoSave, ToolsGoalSeek, ToolsSolver, ToolsSimulation, ToolsCompare, ToolsPlugins, ToolsScenarios, ToolsScenarioAdd | no | Phase 5 |
| All 28 Statistics items (descriptive, frequencies, sampling, time series, one- and two-sample tests, ANOVA, contingency) | no | Phase 5, last; the engine's `src/tools/` is GTK-free |

## Data

| Action | Status | Notes / Phase |
|---|---|---|
| DataSort | partial | Data → Sort… (2026-10-12): rows or columns, header, three keys with order and case, keep formats; no locale, no more than three keys, no saved setups |
| DataShuffle, DataValidate, DataConsolidate, DataTable, DataTextToColumns | no | Phase 3/5 |
| CopyDown, CopyRight | ported | Edit → Fill → Down ⌘D, Right ⌘R |
| EditFillAutofill | ported | the fill handle on the selection; Option makes a single number count up (the GTK Ctrl) |
| EditFillSeries, ToolsMerge, ToolsTabulate, RandomGenerator* | no | Phase 3/5 |
| DataAutoFilter, DataFilterShowAll | ported | Data → Filter (2026-10-12): buttons in the heading cells with the GTK list, Custom… and Top 10… sheets; Show All also drops every autofilter condition (GTK's only serves the advanced filter) |
| DataFilterAdvancedfilter | no | Phase 5 |
| DataOutline* (7) | no | Phase 3 |
| DataSlicer* (3) | no | Phase 5 |
| DataImportText, DataImportOther, DataExportText, DataExportCSV, DataExport, DataExportRepeat | no | Phase 5; the text import dialog is also needed for CSV options |

## Help

| Action | Status | Notes / Phase |
|---|---|---|
| HelpAbout | ported | standard About panel, no version details |
| HelpDocs, HelpFunctions, HelpWeb, HelpIRC, HelpBug | no | Phase 5 |

## Not menu items

| Feature | Status | Notes / Phase |
|---|---|---|
| Toolbars (standard, format, object) | no | Phase 3 |
| Status bar, auto-expression (sum/average of selection) | partial | auto-expression pull-down 2026-10-11; no progress or zoom fields |
| Name box navigation (type a reference) | no | Phase 3 |
| Formula bar: multi-line editing, function tooltips | no | Phase 3 |
| In-cell editor: cell's own font and alignment, autocomplete, range selection by mouse or keyboard while typing a formula, array formulas (Ctrl-Shift-Enter) | no | Phase 3 (`cmd_area_set_array_expr` is not wrapped yet) |
| Cell comments (display, tooltips) | no | Phase 5 |
| Hyperlinks (activation) | no | Phase 5 (`gnm_hlink_activate` takes `WBCGtk`) |
| Sheet objects: selection handles, move, resize, context menus, editing, form widgets | partial | 2026-10-12: click to select, handles, drag to move and resize (Option symmetric, Shift snaps), Delete, arrows nudge, Tab cycles, context menu with Properties… (charts), Delete, and the stacking order, cut, copy, and paste (a PNG goes to other applications), the chart editor; no Save as Image…, no editors for images and widgets, no live preview while dragging, widgets draw but do not act |
| Frozen panes | ported | 2026-10-11: frozen strips painted as overlays on one document view, scrolling clamped to the first unfrozen cell |
| Right-to-left sheets | no | Phase 7; drawn left-to-right |
| Marching ants animation | partial | static dashed outline |
| Drag and drop (cells, files, sheet tabs) | no | Phase 3; sheets move through the menu for now |
| Column and row header drag resizing, double-click autosize | ported | 2026-10-11; resizes every selected column (row) when the dragged one is selected |
| Sheet tab context menu, tab colors | partial | context menu 2026-10-11; Tab Color… 2026-10-12 shows the background as a swatch before the name (the text color is kept in the file, not shown) |
| Printing and page setup | no | Phase 3+ (`NSPrintOperation` with the engine's `print-cell.c`) |
| Preferences window | no | Phase 5 |
| Plugin manager | no | Phase 5 |
| Localization of the UI (the engine's messages follow the process locale) | no | Phase 7 |
| Bundled distribution (dylibs, plugins, schemas inside the `.app`) | no | Phase 6 |
