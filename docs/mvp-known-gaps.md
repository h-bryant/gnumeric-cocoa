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
| FileNew | ported | File → New (⌘N) and an untitled workbook at launch without a file (2026-10-12) |
| FileOpen | ported | every engine opener; CSV with default options |
| FileSave, FileSaveAs | ported | `.gnumeric`, uncompressed `.xml`, `.xlsx`; other savers need Save As types |
| FilePageSetup, FilePrint, FilePrintArea set and clear | ported | File → Page Setup… (⇧⌘P), Print… (⌘P) through the system print panel, Print Area → Set and Clear (2026-10-12); the engine's pagination and page drawing in the bridge |
| FilePrintPreview, FilePrintArea show, page break actions | partial | the system print panel previews (no separate preview window); 2026-10-13: File → Print Area → Show Print Area selects the area, Add/Remove Column (Row) Page Break at the edit position and Clear All Page Breaks run the engine's commands (`cmd_page_break_toggle`, whose undo label names the reverse action, as in the GTK), the pagination honors them, and the grid draws manual breaks as dashed blue lines (the GTK grid shows none) |
| FileSend | no | Phase 5 |
| FileMetaData (Properties) | partial | 2026-10-13: File → Properties… edits the nine standard string properties (title, subject, description, keywords, author, initial author, manager, company, category) as one undoable command (`GnmWorkbook.setDocumentProperties`, `DocumentPropertiesDialog`); no statistics page, no custom properties |
| FileHistoryFull | ported | `NSDocumentController` recents |
| FileClose, FileQuit | ported | |

## Edit

| Action | Status | Notes / Phase |
|---|---|---|
| Undo, Redo | ported | engine command stack, labels in the menu |
| EditCut, EditCopy, EditPaste | ported | engine clipboard; text to and from other apps; selected objects, with a PNG out and images in |
| EditPasteSpecial | ported | Edit → Paste Special… (⌘⇧V): what, operation, region transform, the four switches, Paste Link |
| EditFind, EditReplace | ported | Edit → Find… (⌘F) and Find and Replace… (⌥⌘F), one floating panel with the GTK dialogs' options and the matches list (2026-10-12) |
| EditRecalc | ported | Data → Recalculate (F9), `workbook_recalc_all` |
| EditPreferences | partial | Gnumeric → Settings… (⌘,) with the GTK pages that have an effect here: files (compression), new workbooks, Return's direction, Auto Correct, undo, sorting, default font (2026-10-12); no header/footer font, screen DPI, autosave, or copy-and-paste pages |
| EditClearContent | ported | Delete key and Edit → Delete |
| EditClearAll, EditClearFormats, EditClearComments | ported | Edit → Clear submenu |
| EditClear*Filtered (4) | ported | Edit → Clear → "… Filtered Rows" (2026-10-12); as in GTK they skip the rows a filter hides |
| EditDeleteColumns, EditDeleteRows | ported | Edit menu; the selection's columns or rows |
| EditDeleteCells | ported | Edit → Delete Cells… (2026-10-12): shift left or up, entire rows or columns |
| EditHyperlink | ported | Insert → Hyperlink… edits or removes the edit position's link (2026-10-12) |
| EditClearHyperlinks | ported | 2026-10-13: Edit → Clear → Hyperlinks takes the links off every selected range as one command named after the count ("Remove 2 Links"), the underline and color staying as in the GTK (`removeHyperlinksOfSelection`) |
| EditNames | ported | Edit → Define Names… (2026-10-12): list, add or update, remove, workbook or sheet scope |
| EditComment | ported | Insert → Comment… (Edit Comment… over one) and the cell's context menu (2026-10-12) |
| InsertSheet, InsertSheetAtEnd, EditDuplicateSheet, SheetRemove, SheetChangeName | ported | Edit → Sheet and the tab context menu; rename through a prompt |
| SheetReorder | ported | Move Left / Move Right, Edit → Sheet → Hide / Unhide…, and Edit → Sheet → Manage Sheets… (2026-10-12: the GTK dialog's table of lock, visibility, name, and direction, tab colors, insert, append, duplicate, remove, up, down, sort by name, Undo; `ManageSheetsDialog.swift`); no tab drag |
| SheetResize | ported | Edit → Sheet → Resize… (2026-10-12): powers of two, optionally every sheet |
| EditSelectAll | ported | ⌘A and the header corner |
| EditSelectColumn, EditSelectRow | ported | header clicks and Edit → Select |
| EditSelectArray, EditSelectDepends, EditSelectInputs | ported | 2026-10-13: Edit → Select → Array, Depends, Inputs (`sv_select_cur_*`); a beep when there is nothing to select |
| EditSelectObject | ported | Tab cycles the objects on the grid; Edit → Select → Next Object (⌃Tab) since 2026-10-13 |
| EditGotoTop/Bottom/First/Last, EditGoto | partial | ⌘-arrows jump to the edge of the data (the GTK's Ctrl+arrow, Shift extending) and Home goes to the row's first column (2026-10-12); Edit → Go To… (⌃G) and the name box take a reference or a name; no Top/Bottom/First/Last items, no key for A1 |

## View

| Action | Status | Notes / Phase |
|---|---|---|
| ViewNew | no | second window on one workbook (`control_new` slot), Phase 3 |
| ViewFreezeThawPanes | ported | View → Freeze/Unfreeze Panes with the GTK placement rules; files with frozen panes open frozen |
| ViewStatusbar | partial | the auto-expression (Sum/Min/Max/Average/Count of the selection) sits at the right of the tab bar; no hide toggle, no other status fields |
| ViewFullScreen | ported | View → Enter Full Screen (⌃⌘F), the window's full-screen behavior (2026-10-12) |
| FormatWorkbook (workbook properties) | ported | 2026-10-13: Format → Workbook… sets the view's attributes (scrollbars, sheet tabs, autocompletion, the two cell markers, protection; `GnmWorkbook (ViewAttributes)`); the window hides its scrollers and tab bar accordingly, the markers are kept for the file |
| ViewZoom | ported | View → Zoom In/Out/Actual Size, and View → Zoom… (also Format → Sheet → Zoom…) with the presets or a typed percentage and "All sheets", over `cmd_zoom` (undoable, "Zoom Sheet1 to 150%") (2026-10-12) |

## Insert

| Action | Status | Notes / Phase |
|---|---|---|
| InsertCells | ported | Insert → Cells… (2026-10-12): shift right or down, entire rows or columns |
| InsertColumns, InsertRows | ported | Insert menu; as many as the selection spans, before it |
| SheetInsert | ported | Edit → Sheet → Insert |
| ChartGuru | ported | Insert → Chart… (2026-10-12): every goffice plot type with its sample image, series from the selection, the two guru options; the later pages are the chart editor (double-click, Properties…, Format → Object Properties…): object tree with add, remove, reorder, live preview, every object's data expressions, properties, and style, Change Type… for a plot; not in it: error bars, gradient and image fills, manual positions |
| InsertImage | ported | Insert → Image… (2026-10-12), and PNG or TIFF pasted from other applications |
| InsertComponent, InsertShapedComponent, NewGOComponent, GOComponentFromFile | no | Phase 4; goffice components (equations, embedded documents) |
| InsertFormula (function selector) | ported | Insert → Function… (2026-10-12): groups, search, summaries, arguments; no formula guru |
| InsertNames | ported | Insert → Name… puts a name into the cell editor (2026-10-12) |
| InsertComment | ported | Insert → Comment…, an alert sheet with author and text (2026-10-12) |
| InsertHyperlink | ported | Insert → Hyperlink… (⌘K), 2026-10-12: internal, file, email, and web links with a tip |
| InsertSortDecreasing, InsertSortIncreasing | ported | Data → Sort Ascending / Descending (the GTK quick sort: by the selection's columns, heading kept) |
| InsertCurrentDate, InsertCurrentTime, InsertCurrentDateTime | ported | Insert menu, ⌘; and ⇧⌘; (2026-10-12) |

## Format

| Action | Status | Notes / Phase |
|---|---|---|
| FormatCells | partial | number, alignment, font, border, fill; the validation and input message pages are Data → Validation… and the conditional page Format → Conditional Formatting… (2026-10-12); no protection page; no format preview |
| FormatCellsCond | ported | Format → Conditional Formatting… (2026-10-12): the GTK operators, x and y, an overlay of fill, text color, bold, italic, number format |
| FormatMergeCells, FormatUnmergeCells | ported | Format menu, with Merge and Center (`patches/0002` fixes an engine double-unref there) |
| FormatCellsFitHeight, FormatCellsFitWidth | bridge | `autofitSelectedCells(width:)`; the menu has the whole-column/row Autofit |
| FormatAuto | ported | 2026-10-13, see Format → AutoFormat… below |
| FontBold, FontItalic, FontUnderline | ported | Format → Bold ⌘B, Italic ⌘I, Underline ⌘U (2026-10-12) |
| FontStrikeThrough, FontDoubleUnderline, FontSuperscript, FontSubscript | ported | 2026-10-13: Format → Font ▸ Bold ⌘B, Italic ⌘I, Underline ⌘U, Double Underline ⇧⌘D, Single Low Underline ⇧⌘L, Double Low Underline, Strikethrough ⌘5, Superscript ⌃⌘+, Subscript ⌃⌘- (the GTK toggles: the opposite of the edit position's attribute, check marks following it); Superscript and Subscript are on the toolbar too |
| ColumnSize, RowSize, ColumnAutoSize, RowAutoSize, ColumnDefaultSize, RowDefaultSize | ported | Format → Column / Row (points); headers drag-resize and autofit on a boundary double-click |
| ColumnHide, RowHide, ColumnUnhide, RowUnhide | ported | Format → Column / Row |
| SheetDisplayFormulas, SheetUseR1C1, SheetHideZeros, SheetHideGridlines, SheetHideColHeader, SheetHideRowHeader, SheetDirection | partial | Format → Sheet (2026-10-12): Display Formulæ, Use R1C1 Notation, Hide Zeros, Hide Gridlines, Hide Column Headers, Hide Row Headers as checked items over `cmd_toggle_sheet_property` (undoable; the header views collapse); no Direction item, the sheet is drawn left-to-right |

## Tools and Statistics

| Action | Status | Notes / Phase |
|---|---|---|
| ToolsSolver | ported | Tools → Solver… (2026-10-12): parameters, model and algorithm, constraints, options, reports; Gnumeric's own solver, GLPK and lp_solve when installed; the run page as a progress sheet with the status, objective, elapsed time, and a Stop button (`GnmSolverRun`); no scenarios |
| ToolsAutoCorrect, ToolsAutoSave, ToolsCompare | no | Phase 5 |
| ToolsScenarios, ToolsScenarioAdd | ported | Tools → Scenarios → View… / Add… (2026-10-13): the Add dialog's checks, the manager's session (Show, Delete, Summary, OK commits "Scenario Show" and the deletions, Cancel restores and drops the report sheets); the summary report fills in the per-cell rows the GTK left as stubs and adds result cells (`GnmScenarios.h`, `ScenariosDialog.swift`, `scenarios.m`) |
| Format → AutoFormat… | ported | 2026-10-13: the shipped template categories, a preview over the GTK demo table, the Settings menu's parts and edges as checkboxes, applied to the selection with `cmd_selection_autoformat` (`GnmAutoFormat.h`, `AutoFormatDialog.swift`, `autoformat.m`); engine patch 0008 for the edge filter's use after free |
| ToolsSimulation | ported | Tools → Simulation… (2026-10-13): the dialog's fields, `simulation_tool`'s report to a new sheet or a range, the results of every round and the log in a second alert (`GnmSheet.runSimulation…`, `SimulationDialog.swift`) |
| ToolsPlugins | ported | Tools → Plug-ins… (2026-10-12): the GTK dialog's list with activation checkboxes, details, the mark for deactivation, Activate All, the new-plugins preference, the directories with Add and Remove, Rescan (`GnmPlugins.h`, `PluginManagerDialog.swift`, `plugins.m`) |
| ToolsGoalSeek | ported | Tools → Goal Seek… (2026-10-12) |
| Statistics: Descriptive Statistics, Correlation, Covariance, Rank and Percentile, Regression, Two Means (t and z), Two Variances (F), ANOVA single factor, Sampling, Moving Average, Exponential Smoothing | ported | Tools → Statistics (2026-10-12): the GTK dialogs' Input, tool, and Output pages as alert sheets over `cmd_analysis_tool` |
| The other Statistics items: Frequency Tables, Histogram, Fourier, Principal Components, Kaplan-Meier, Normality Tests, Claims About a Mean, the one- and two-sample sign and Wilcoxon signed rank tests, Wilcoxon-Mann-Whitney, two-factor ANOVA, the contingency table tests | ported | 2026-10-12 on the same pattern; the Statistics menu now has the GTK's groups and submenus; a tool's required function plugins are activated on demand (Fourier's time series plugin is inactive by default); Kaplan-Meier groups are typed as "name from to; …" rather than a table; engine patch 0005 for the frequency and histogram tools' double free |

## Data

| Action | Status | Notes / Phase |
|---|---|---|
| DataSort | partial | Data → Sort… (2026-10-12): rows or columns, header, six key rows with order and case, the collation's locale (a pop-up of common ones or typed), keep formats; no saved setups, the GTK's open-ended key list is six rows |
| DataValidate | ported | Data → Validation… (2026-10-12): the criteria, the action's alerts on entry, the in-cell list, the input message |
| DataTable | ported | Data → Table… (2026-10-12): the GTK dialog's row and column input cells over the selection, `cmd_create_data_table` |
| DataShuffle, DataConsolidate | ported | Data → Shuffle… (columns, rows, or area in place, `cmd_data_shuffle`) and Data → Consolidate… (the ten functions, four source areas, top-row and left-column labels, copy labels, the Output page's values or formulas; `gnm_consolidate_tool_new`) (2026-10-12) |
| DataTextToColumns | ported | Data → Text to Columns… through the import assistant (2026-10-12) |
| CopyDown, CopyRight | ported | Edit → Fill → Down ⌘D, Right ⌘R |
| EditFillAutofill | ported | the fill handle on the selection; Option makes a single number count up (the GTK Ctrl) |
| ToolsTabulate, RandomGenerator* | ported | Edit → Fill (2026-10-12): Tabulate Dependency… (three dependencies, visual or coordinate layout, `cmd_tabulate` onto new sheets), Random Generator → Uncorrelated… (the 30 distributions with the dialog's parameter labels) and Correlated… (a covariance matrix or its Cholesky factor; engine patch 0006 for matrices other than 3×3), both analysis tools with the Output page |
| ToolsMerge | no | Phase 5 |
| EditFillSeries | ported | Edit → Fill → Series… (2026-10-12): linear, growth, date series in rows or columns |
| DataAutoFilter, DataFilterShowAll | ported | Data → Filter (2026-10-12): buttons in the heading cells with the GTK list, Custom… and Top 10… sheets; Show All also drops every autofilter condition (GTK's only serves the advanced filter) |
| DataFilterAdvancedfilter | ported | Data → Filter → Advanced Filter… (2026-10-12): list and criteria ranges, unique records, in place (`advanced_filter`, Show All brings the rows back) or copied to a range or a new sheet (the engine's tool with its three-line heading) |
| DataOutline* (7) | ported | Data → Outline (2026-10-12): Hide Detail, Show Detail, Group…, Ungroup… (whole rows or columns settle the axis, otherwise a Rows/Columns question), Display Outlines, Outlines Below, Outlines Right; the headers grow an outline strip ((levels + 1) × 14 px as item-bar.c) with a bar per level, a corner where a group starts, and a − or + box on the column or row that ends it, clicked to collapse or expand (`cmd_selection_outline_change`); no global level buttons |
| DataSlicer* (3) | no | Phase 5 |
| DataImportText, DataImportOther, DataExportText, DataExportCSV, DataExport, DataExportRepeat | partial | Save As to CSV writes the current sheet with the exporter's defaults; Save As to "Text (configurable)" asks the GTK export dialog's options first; plain text opens through the import assistant and File → Import Text… (⇧⌘O) sends any file through it, `.csv` and `.tsv` take the guessed options (2026-10-12); no DataImportOther, DataExportRepeat |

## Help

| Action | Status | Notes / Phase |
|---|---|---|
| HelpAbout | ported | standard About panel, no version details |
| HelpDocs, HelpFunctions, HelpWeb, HelpIRC, HelpBug | ported | 2026-10-13: Help → Gnumeric Help (the GNOME manual online, instead of yelp), Functions… (the function catalog to read), Gnumeric on the Web, Live Assistance (irc:, needs a client), Report a Problem (the GNOME GitLab tracker) |

## Not menu items

| Feature | Status | Notes / Phase |
|---|---|---|
| Toolbars (standard, format, object) | partial | 2026-10-13: one customizable NSToolbar with the GTK standard items (New, Open, Save, Print, Cut, Copy, Paste, Undo, Redo, Hyperlink, AutoSum, Function, the sorts, Chart, a zoom pop-up) and the format items (font family and size, Bold, Italic, Underline, the alignments, Merge, Unmerge, Accounting, Percent, thousands, more and fewer decimals, less and more indent, superscript, subscript, a border preset pull-down, text and fill color wells, No Fill; `WorkbookToolbar.swift`, `GnmNumberFormats.h`); the toggles and wells follow the cursor cell; no object toolbar (Insert → Object covers it) or print preview |
| Status bar, auto-expression (sum/average of selection) | partial | auto-expression pull-down 2026-10-11; no progress or zoom fields |
| Name box navigation (type a reference) | ported | 2026-10-12: a reference, a sheet-qualified reference, or a name; a new word names the selection |
| Formula bar: multi-line editing | ported | 2026-10-13: Option+Return adds a line break (the GTK's Alt+Return) in the cell editor and the formula bar; the in-cell editor grows to show every line (item-edit.c) and the formula bar shows up to five |
| In-cell editor: function tooltips and F4 | ported | 2026-10-12: the call around the cursor with its argument marked, or the names a prefix completes to, drawn under the editor (`gee_check_tooltip`; `GnmSheet.functionTooltip`); F4 completes a single name or cycles the reference at the cursor relative → absolute → row → column (`formulaText:cursorAt:cycleReferenceIn:`) |
| In-cell editor: range selection by mouse while typing a formula | ported | 2026-10-12: a click or drag puts the reference where the GTK entry would (`GnmFormulaEditing`) |
| In-cell editor: autocomplete | ported | 2026-10-12: the column's nearest text above fills in with the tail selected |
| In-cell editor: range selection by keyboard while typing a formula | ported | 2026-10-12: arrows move the reference from the edited cell, Shift extends it, ⌘ jumps to the data's edge (`scg_rangesel_move/extend`); typing that leaves no place for a range ends it (`gee_update_env`) |
| In-cell editor: array formulas (Ctrl-Shift-Enter) | ported | 2026-10-12: ⇧⌘Return or ⌃⇧Return enters the text as an array over the selection (`GnmSheet.enterArrayFormula`, `cmd_area_set_array_expr`); a non-formula or several ranges fill as text, as the GTK does |
| In-cell editor: cell's own font and alignment | ported | 2026-10-12: the editor takes the cell's family (resolved as pango does: Sans is Helvetica), size at the zoom, bold and italic, text and fill colors, and alignment (General edits left, as item-edit.c); underline and strikethrough are not shown while editing |
| Cell comments (display, tooltips) | ported | the red corner marker and a tool tip with author and text (2026-10-12) |
| Hyperlinks (activation) | ported | a click follows the link (2026-10-12): internal ones through the engine's selection, the others through NSWorkspace; the tip is the tool tip |
| Sheet objects: selection handles, move, resize, context menus, editing, form widgets | partial | 2026-10-12: click to select, handles, drag to move and resize (Option symmetric, Shift snaps), Delete, arrows nudge, Tab cycles, context menu with Properties… (charts), Save as Image… (charts and images, with the format and resolution), Delete, and the stacking order, cut, copy, and paste (a PNG goes to other applications), the chart editor; 2026-10-13: Insert → Object inserts the nine widget kinds and Properties… on a widget opens its configuration dialog (label, linked cell, value, range and direction, content and output; `GnmWidgets.h`, `WidgetDialog.swift`, `widgets.m`); images have no editor in the GTK either; widgets act on 2026-10-13: a plain click clicks a checkbox, radio button, or button, sets a scrollbar or slider from the pointer (dragging follows), steps a spin button, picks a list row, or pops up a combo's entries, each driving the linked cell through the GTK's undoable commands ("Clicking checkbox", "Change widget", "Clicking in list"); Command, Shift, or Option click selects a widget instead; no live preview while dragging |
| Frozen panes | ported | 2026-10-11: frozen strips painted as overlays on one document view, scrolling clamped to the first unfrozen cell |
| Right-to-left sheets | no | Phase 7; drawn left-to-right |
| Marching ants animation | partial | static dashed outline |
| Drag and drop (cells, files, sheet tabs) | ported | 2026-10-13: the selection dragged by its border moves the cells (Option drops a copy; `GnmSheet.dropSelection`, the GTK item cursor's cut or copy and paste), image files dropped on the grid are placed where they land and other files open as documents, and a sheet tab dragged onto another's place moves the sheet (`SheetTabControl`) |
| Column and row header drag resizing, double-click autosize | ported | 2026-10-11; resizes every selected column (row) when the dragged one is selected |
| Sheet tab context menu, tab colors | partial | context menu 2026-10-11; Tab Color… 2026-10-12 shows the background as a swatch before the name (the text color is kept in the file, not shown) |
| Printing and page setup | ported | 2026-10-12: `NSPrintOperation` over `PrintView`, the engine's `print-cell.c` and a port of print.c's pagination and page drawing in `GnmPrinting.m` |
| Preferences window | partial | see EditPreferences (2026-10-12) |
| Plugin manager | ported | 2026-10-12, see ToolsPlugins above |
| Localization of the UI (the engine's messages follow the process locale) | no | Phase 7 |
| Bundled distribution (dylibs, plugins, schemas inside the `.app`) | no | Phase 6 |
