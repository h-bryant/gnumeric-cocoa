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
| EditCut, EditCopy, EditPaste | ported | engine clipboard; text to and from other apps |
| EditPasteSpecial | no | Phase 3 (`cmd_paste_to_selection` takes flags already) |
| EditFind, EditReplace | no | Phase 5 |
| EditRecalc | ported | Data → Recalculate (F9), `workbook_recalc_all` |
| EditPreferences | no | Phase 5 |
| EditClearContent | ported | Delete key and Edit → Delete |
| EditClearAll, EditClearFormats, EditClearComments | ported | Edit → Clear submenu |
| EditClear*Filtered (4) | bridge | `clearSelection:` takes the flags; filtered-only variants wait for autofilter (Phase 3) |
| EditDeleteColumns, EditDeleteRows | ported | Edit menu; the selection's columns or rows |
| EditDeleteCells | no | Phase 3 |
| EditClearHyperlinks, EditComment, EditHyperlink, EditNames | no | Phase 5 |
| SheetReorder, InsertSheet, InsertSheetAtEnd, EditDuplicateSheet, SheetRemove, SheetChangeName, SheetResize | no | Phase 3 (sheet management) |
| EditSelectAll | ported | ⌘A and the header corner |
| EditSelectColumn, EditSelectRow | ported | header clicks and Edit → Select |
| EditSelectArray, EditSelectDepends, EditSelectInputs, EditSelectObject | no | Phase 3/4 |
| EditGotoTop/Bottom/First/Last, EditGoto | partial | Home and ⌘↑ work; no name-box navigation or Goto dialog |

## View

| Action | Status | Notes / Phase |
|---|---|---|
| ViewNew | no | second window on one workbook (`control_new` slot), Phase 3 |
| ViewFreezeThawPanes | no | Phase 3; frozen panes in files draw as one pane |
| ViewStatusbar | no | no status bar or auto-expression yet, Phase 3 |
| ViewFullScreen | no | enable the window's full-screen behavior, Phase 3 |
| FormatWorkbook (workbook properties) | no | Phase 5 |
| ViewZoom | partial | fixed steps via View menu; no zoom dialog or percentage entry |

## Insert

| Action | Status | Notes / Phase |
|---|---|---|
| InsertCells | no | Phase 3 |
| InsertColumns, InsertRows | ported | Insert menu; as many as the selection spans, before it |
| SheetInsert | no | Phase 3 |
| ChartGuru, InsertComponent, InsertShapedComponent, NewGOComponent, GOComponentFromFile, InsertImage | no | Phase 4; existing charts and images draw read-only |
| InsertFormula (function selector), InsertNames | no | Phase 5 |
| InsertComment, InsertHyperlink | no | Phase 5 |
| InsertSortDecreasing, InsertSortIncreasing | no | Phase 3 |
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
| DataSort, DataShuffle, DataValidate, DataConsolidate, DataTable, DataTextToColumns | no | Phase 3/5 |
| CopyDown, CopyRight | ported | Edit → Fill → Down ⌘D, Right ⌘R |
| EditFillAutofill | ported | the fill handle on the selection; Option makes a single number count up (the GTK Ctrl) |
| EditFillSeries, ToolsMerge, ToolsTabulate, RandomGenerator* | no | Phase 3/5 |
| DataAutoFilter, DataFilterShowAll, DataFilterAdvancedfilter | no | Phase 3; filtered rows in files draw hidden |
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
| Status bar, auto-expression (sum/average of selection) | no | Phase 3 |
| Name box navigation (type a reference) | no | Phase 3 |
| Formula bar: multi-line editing, function tooltips | no | Phase 3 |
| In-cell editor: cell's own font and alignment, autocomplete, range selection by mouse or keyboard while typing a formula, array formulas (Ctrl-Shift-Enter) | no | Phase 3 (`cmd_area_set_array_expr` is not wrapped yet) |
| Cell comments (display, tooltips) | no | Phase 5 |
| Hyperlinks (activation) | no | Phase 5 (`gnm_hlink_activate` takes `WBCGtk`) |
| Sheet objects: selection handles, move, resize, context menus, editing, form widgets | no | Phase 4; objects draw read-only |
| Frozen panes | no | Phase 3 |
| Right-to-left sheets | no | Phase 7; drawn left-to-right |
| Marching ants animation | partial | static dashed outline |
| Drag and drop (cells, files, sheet tabs) | no | Phase 3 |
| Column and row header drag resizing, double-click autosize | ported | 2026-10-11; resizes every selected column (row) when the dragged one is selected |
| Sheet tab context menu, tab colors | no | Phase 3 |
| Printing and page setup | no | Phase 3+ (`NSPrintOperation` with the engine's `print-cell.c`) |
| Preferences window | no | Phase 5 |
| Plugin manager | no | Phase 5 |
| Localization of the UI (the engine's messages follow the process locale) | no | Phase 7 |
| Bundled distribution (dylibs, plugins, schemas inside the `.app`) | no | Phase 6 |
