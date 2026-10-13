// A Sheet, its SheetView, and the Cocoa SheetControl attached to that view.
// Geometry is in sheet pixels at the sheet's zoom factor, origin at the
// top-left of cell A1, y increasing downward (the engine's own convention).
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <GnmCocoa/GnmGeometry.h>
#import <GnmCocoa/GnmCellFormat.h>
#import <GnmCocoa/GnmFilter.h>
#import <GnmCocoa/GnmSheetObject.h>
#import <GnmCocoa/GnmPlotType.h>

NS_ASSUME_NONNULL_BEGIN

@class GnmWorkbook, GnmSheet;

/// What `clearSelection:` removes; mirrors the engine's CLEAR_* flags.
typedef NS_OPTIONS(NSUInteger, GnmClearOptions) {
    GnmClearValues = 1 << 0,
    GnmClearFormats = 1 << 1,
    GnmClearComments = 1 << 2,
    GnmClearMerges = 1 << 6,
    GnmClearObjects = 1 << 7,
    /// Skip the rows an autofilter hides, so only the rows the filter shows
    /// are cleared (the GTK "... in Filtered Rows" items).
    GnmClearFilteredRowsOnly = 1 << 8,
} NS_SWIFT_NAME(ClearOptions);

/// One key of the Sort dialog: a column (sorting by rows) or a row (sorting
/// by columns), absolute index.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(SortKey)
@interface GnmSortKey : NSObject
- (instancetype)initWithIndex:(NSInteger)index descending:(BOOL)descending caseSensitive:(BOOL)caseSensitive
                      byValue:(BOOL)byValue NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init(index:descending:caseSensitive:byValue:));
- (instancetype)init NS_UNAVAILABLE;
@property (nonatomic, readonly) NSInteger index;
@property (nonatomic, readonly, getter=isDescending) BOOL descending;
@property (nonatomic, readonly, getter=isCaseSensitive) BOOL caseSensitive;
/// Compare values (the usual) rather than the formatted text.
@property (nonatomic, readonly) BOOL byValue;
@end

/// What and how `pasteWithOptions:` pastes; mirrors the engine's PASTE_*
/// flags.  `GnmPasteDefault` is the plain paste (everything, with column
/// widths and row heights adjusted).
typedef NS_OPTIONS(NSUInteger, GnmPasteOptions) {
    GnmPasteContents = 1 << 0,
    GnmPasteAsValues = 1 << 1,       /* instead of contents */
    GnmPasteFormats = 1 << 2,
    GnmPasteComments = 1 << 3,
    GnmPasteObjects = 1 << 4,
    GnmPasteAdd = 1 << 5,
    GnmPasteSubtract = 1 << 6,
    GnmPasteMultiply = 1 << 7,
    GnmPasteDivide = 1 << 8,
    GnmPasteTranspose = 1 << 9,
    GnmPasteLink = 1 << 10,
    GnmPasteSkipBlanks = 1 << 11,
    GnmPasteColumnWidths = 1 << 14,
    GnmPasteRowHeights = 1 << 16,
    GnmPasteKeepFormulaReferences = 1 << 18,   /* PASTE_EXPR_LOCAL_RELOCATE */
    GnmPasteFlipHorizontally = 1 << 20,
    GnmPasteFlipVertically = 1 << 21,
    GnmPasteAllCells = GnmPasteContents | GnmPasteFormats | GnmPasteComments | GnmPasteObjects,
    GnmPasteDefault = GnmPasteAllCells | (1 << 15) | (1 << 17),   /* auto widths and heights */
} NS_SWIFT_NAME(PasteOptions);

/// Requests the engine makes through the SheetControl vtable
/// (docs/architecture.md §3).  All optional; all on the main thread.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(SheetDelegate)
@protocol GnmSheetDelegate <NSObject>
@optional
- (void)sheetNeedsDisplay:(GnmSheet *)sheet includingHeaders:(BOOL)includingHeaders NS_SWIFT_NAME(sheetNeedsDisplay(_:includingHeaders:));
- (void)sheet:(GnmSheet *)sheet needsDisplayInRange:(GnmCellRange)range NS_SWIFT_NAME(sheet(_:needsDisplayIn:));
- (void)sheet:(GnmSheet *)sheet needsHeaderDisplayForColumns:(BOOL)columns rows:(BOOL)rows NS_SWIFT_NAME(sheet(_:needsHeaderDisplayForColumns:rows:));
/// Column or row sizes, zoom, or the scrollable extent changed.
- (void)sheetGeometryDidChange:(GnmSheet *)sheet NS_SWIFT_NAME(sheetGeometryDidChange(_:));
- (void)sheet:(GnmSheet *)sheet cursorDidMoveToRange:(GnmCellRange)range NS_SWIFT_NAME(sheet(_:cursorDidMoveTo:));
- (void)sheet:(GnmSheet *)sheet scrollToColumn:(NSInteger)column row:(NSInteger)row NS_SWIFT_NAME(sheet(_:scrollToColumn:row:));
- (void)sheet:(GnmSheet *)sheet makeVisibleColumn:(NSInteger)column row:(NSInteger)row NS_SWIFT_NAME(sheet(_:makeVisibleColumn:row:));
- (void)sheetMarchingAntsDidChange:(GnmSheet *)sheet NS_SWIFT_NAME(sheetMarchingAntsDidChange(_:));
- (void)sheetFrozenPanesDidChange:(GnmSheet *)sheet NS_SWIFT_NAME(sheetFrozenPanesDidChange(_:));
/// A sheet object moved, was resized, left the sheet, or joined it.
- (void)sheetObjectsDidChange:(GnmSheet *)sheet NS_SWIFT_NAME(sheetObjectsDidChange(_:));
@end

typedef NS_ENUM(NSInteger, GnmFillSeriesKind) {
    GnmFillSeriesLinear = 0,
    GnmFillSeriesGrowth,
    GnmFillSeriesDate,
} NS_SWIFT_NAME(Sheet.FillSeriesKind);

typedef NS_ENUM(NSInteger, GnmFillSeriesDateUnit) {
    GnmFillSeriesDateUnitDay = 0,
    GnmFillSeriesDateUnitWeekday,
    GnmFillSeriesDateUnitMonth,
    GnmFillSeriesDateUnitYear,
} NS_SWIFT_NAME(Sheet.FillSeriesDateUnit);

/// What a goal seek ended with.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(GoalSeekResult)
@interface GnmGoalSeekResult : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly) BOOL found;
/// The changing cell's value at the end.
@property (nonatomic, readonly) double solution;
/// The set cell's value at the end.
@property (nonatomic, readonly) double currentValue;
@property (nonatomic, readonly) double targetValue;
@end

/// A cell's comment (`GnmComment`): its position, author, and text.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(CellComment)
@interface GnmCellComment : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly) NSInteger column;
@property (nonatomic, readonly) NSInteger row;
@property (nonatomic, readonly, copy) NSString *author;
@property (nonatomic, readonly, copy) NSString *text;
@end

/// Format → Sheet's toggles (`cmd_toggle_sheet_property`).
typedef NS_ENUM(NSInteger, GnmSheetDisplayOption) {
    GnmSheetDisplayOptionFormulas = 0,
    GnmSheetDisplayOptionHideZeros,
    GnmSheetDisplayOptionHideGridLines,
    GnmSheetDisplayOptionHideColumnHeader,
    GnmSheetDisplayOptionHideRowHeader,
    GnmSheetDisplayOptionR1C1 NS_SWIFT_NAME(r1c1),
    GnmSheetDisplayOptionRightToLeft,
} NS_SWIFT_NAME(Sheet.DisplayOption);

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(Sheet)
@interface GnmSheet : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, readonly, weak) GnmWorkbook *workbook;
@property (nonatomic, weak, nullable) id<GnmSheetDelegate> delegate;

@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) NSInteger index;
@property (nonatomic, readonly, getter=isVisible) BOOL visible;
@property (nonatomic, readonly, getter=isRightToLeft) BOOL rightToLeft;
@property (nonatomic, readonly) BOOL hidesGridLines;
@property (nonatomic, readonly) BOOL hidesColumnHeader;
@property (nonatomic, readonly) BOOL hidesRowHeader;
@property (nonatomic, readonly) BOOL displaysFormulas;
@property (nonatomic, readonly) BOOL hidesZeros;
@property (nonatomic, readonly) BOOL usesR1C1;
/// One of the toggles as it stands.
- (BOOL)displayOption:(GnmSheetDisplayOption)option NS_SWIFT_NAME(displayOption(_:));
/// Flip one, undoable ("Toggle displaying formulæ" and so on); the
/// delegate then hears `sheetGeometryDidChange:`.
- (BOOL)toggleDisplayOption:(GnmSheetDisplayOption)option error:(NSError **)error NS_SWIFT_NAME(toggleDisplayOption(_:));
/// The sheet's zoom (1.0 = 100%).  Setting it is `cmd_zoom` on this
/// sheet ("Zoom Sheet1 to 150%", undoable); the engine re-lays out its
/// column and row sizes and rendered values, and the control reports
/// back through `sheetGeometryDidChange:`.
@property (nonatomic) double zoomFactor;
/// `cmd_zoom` on this sheet or on all the workbook's (the Zoom dialog).
- (BOOL)setZoomFactor:(double)zoomFactor forAllSheets:(BOOL)all error:(NSError **)error NS_SWIFT_NAME(setZoomFactor(_:forAllSheets:));

/// Sheet dimensions in cells.
@property (nonatomic, readonly) NSInteger columnCount;
@property (nonatomic, readonly) NSInteger rowCount;

/// Smallest range holding every non-empty cell (`sheet_get_extent`).
@property (nonatomic, readonly) GnmCellRange usedRange;

/// Last column and row the user should be able to scroll to: the used extent
/// or the sheet objects' extent, whichever is larger (what the GTK scrollbars
/// use).
@property (nonatomic, readonly) GnmCellCoordinate scrollableExtent;

// Geometry.  Hidden columns and rows have size 0.
- (CGFloat)widthOfColumn:(NSInteger)column NS_SWIFT_NAME(width(ofColumn:));
- (CGFloat)heightOfRow:(NSInteger)row NS_SWIFT_NAME(height(ofRow:));
- (BOOL)isColumnVisible:(NSInteger)column NS_SWIFT_NAME(isColumnVisible(_:));
- (BOOL)isRowVisible:(NSInteger)row NS_SWIFT_NAME(isRowVisible(_:));
/// Pixel distance from the sheet origin to the left edge of `column` (the sum
/// of all visible columns before it); `column` may equal `columnCount`.
- (CGFloat)leftEdgeOfColumn:(NSInteger)column NS_SWIFT_NAME(leftEdge(ofColumn:));
- (CGFloat)topEdgeOfRow:(NSInteger)row NS_SWIFT_NAME(topEdge(ofRow:));
/// The visible column containing x, clamped to the sheet.
- (NSInteger)columnAtX:(CGFloat)x NS_SWIFT_NAME(column(atX:));
- (NSInteger)rowAtY:(CGFloat)y NS_SWIFT_NAME(row(atY:));
- (CGRect)frameOfCellAtColumn:(NSInteger)column row:(NSInteger)row NS_SWIFT_NAME(frameOfCell(atColumn:row:));

- (NSString *)nameOfColumn:(NSInteger)column NS_SWIFT_NAME(name(ofColumn:));
- (NSString *)nameOfRow:(NSInteger)row NS_SWIFT_NAME(name(ofRow:));

// Cell contents.
- (BOOL)isCellEmptyAtColumn:(NSInteger)column row:(NSInteger)row NS_SWIFT_NAME(isCellEmpty(atColumn:row:));
- (BOOL)cellHasFormulaAtColumn:(NSInteger)column row:(NSInteger)row NS_SWIFT_NAME(cellHasFormula(atColumn:row:));
/// The formatted text the cell displays, or nil when the cell is empty.
- (nullable NSString *)displayTextOfCellAtColumn:(NSInteger)column row:(NSInteger)row NS_SWIFT_NAME(displayTextOfCell(atColumn:row:));
/// What the user typed (formula or literal), as the formula bar shows it.
- (nullable NSString *)enteredTextOfCellAtColumn:(NSInteger)column row:(NSInteger)row NS_SWIFT_NAME(enteredTextOfCell(atColumn:row:));

// Selection, kept in the engine's SheetView.
@property (nonatomic, readonly) GnmCellCoordinate editPosition;
@property (nonatomic, readonly) GnmCellRange selectedRange;
- (void)selectCellAtColumn:(NSInteger)column row:(NSInteger)row NS_SWIFT_NAME(selectCell(atColumn:row:));
- (void)selectRange:(GnmCellRange)range editPosition:(GnmCellCoordinate)editPosition NS_SWIFT_NAME(selectRange(_:editPosition:));
/// The selection as the engine writes it, sheet-qualified and absolute
/// (`selection_to_string`: "Sheet1!$A$1:$B$4", several ranges joined by
/// commas): what the search dialogs' Range field starts with.
@property (nonatomic, readonly, copy) NSString *selectionText;
/// Make the cell the selection and the edit position and bring it into
/// view, focusing this sheet in the workbook first (what the GTK Search
/// dialog does when a match is chosen).
- (void)revealCellAtColumn:(NSInteger)column row:(NSInteger)row NS_SWIFT_NAME(revealCell(atColumn:row:));

// Editing.  Every method runs an undoable engine command through the
// workbook's control; a NO return carries the engine's message in `error`.

/// What the user typed, prepared for editing (`gnm_cell_get_text_for_editing`:
/// formulas keep their leading "=", quoted text keeps its quote).
- (nullable NSString *)editingTextOfCellAtColumn:(NSInteger)column row:(NSInteger)row NS_SWIFT_NAME(editingTextOfCell(atColumn:row:));
/// Set a cell's content from text, as the in-cell editor commits it
/// (`cmd_set_text`).  `autocorrect` applies the engine's autocorrections.
- (BOOL)setText:(NSString *)text atColumn:(NSInteger)column row:(NSInteger)row autocorrect:(BOOL)autocorrect error:(NSError **)error NS_SWIFT_NAME(setText(_:atColumn:row:autocorrect:));
/// Fill the whole selection with the text (`cmd_area_set_text`).
- (BOOL)fillSelectionWithText:(NSString *)text error:(NSError **)error NS_SWIFT_NAME(fillSelection(with:));
/// Clear parts of the selected cells (`cmd_selection_clear`).
- (BOOL)clearSelection:(GnmClearOptions)options error:(NSError **)error NS_SWIFT_NAME(clearSelection(_:));

// Fill Series (`tools/fill-series.h`, the GTK dialog-fill-series.c).
/// A number from text the way the dialogs read their entries: a plain
/// number, or a date or time in the sheet's conventions, as its serial;
/// nil when the text is neither.
- (nullable NSNumber *)numberFromText:(NSString *)text NS_SWIFT_NAME(number(from:));
/// Fill `range` with a series from `start`: linear (adding `step`),
/// growth (multiplying by it), or dates (stepping by `step` of
/// `unit`).  Without a step, it is found from `stop` over the range;
/// with both, the series ends at `stop` or the range's end, whichever
/// comes first.  Undoable as "Fill Series".
- (BOOL)fillSeriesInRange:(GnmCellRange)range byRows:(BOOL)byRows kind:(GnmFillSeriesKind)kind dateUnit:(GnmFillSeriesDateUnit)unit
                    start:(double)start step:(nullable NSNumber *)step stop:(nullable NSNumber *)stop
                    error:(NSError **)error NS_SWIFT_NAME(fillSeries(in:byRows:kind:dateUnit:start:step:stop:));

// Goal Seek (`tools/goal-seek.h`, the GTK dialog-goal-seek.c).
/// A cell reference in the sheet's syntax ("B3", "$B$3") to its position;
/// NO for anything else.
- (BOOL)parseCellReference:(NSString *)text column:(NSInteger *)column row:(NSInteger *)row NS_SWIFT_NAME(parseCellReference(_:column:row:));
/// Change the value of one cell until the formula in another reaches
/// `target` (`gnm_goal_seek_cell`), within `minimum` and `maximum` when
/// given.  A solution is committed as "Goal Seek (A1)", undoable; without
/// one the changing cell keeps its value and `found` is NO.  Nil with an
/// error when the set cell holds no formula or the changing cell holds
/// one.
- (nullable GnmGoalSeekResult *)goalSeekCellAtColumn:(NSInteger)column row:(NSInteger)row toValue:(double)target
                              byChangingCellAtColumn:(NSInteger)changeColumn row:(NSInteger)changeRow
                                             minimum:(nullable NSNumber *)minimum maximum:(nullable NSNumber *)maximum
                                               error:(NSError **)error
    NS_SWIFT_NAME(goalSeek(cellAtColumn:row:toValue:byChangingCellAtColumn:row:minimum:maximum:));

// Comments.
/// The cell's comment, nil without one (`sheet_get_comment`).
- (nullable GnmCellComment *)commentAtColumn:(NSInteger)column row:(NSInteger)row NS_SWIFT_NAME(comment(atColumn:row:));
/// The comments anchored in `range`, for the markers.
- (NSArray<GnmCellComment *> *)commentsInRange:(GnmCellRange)range NS_SWIFT_NAME(comments(in:));
/// Set, change, or with nil or empty text remove the cell's comment
/// (`cmd_set_comment`, undoable as "Setting comment of C3").
- (BOOL)setCommentText:(nullable NSString *)text author:(nullable NSString *)author atColumn:(NSInteger)column row:(NSInteger)row
                 error:(NSError **)error NS_SWIFT_NAME(setComment(_:author:atColumn:row:));
- (BOOL)insertColumns:(NSInteger)count atColumn:(NSInteger)column error:(NSError **)error NS_SWIFT_NAME(insertColumns(_:at:));
- (BOOL)insertRows:(NSInteger)count atRow:(NSInteger)row error:(NSError **)error NS_SWIFT_NAME(insertRows(_:at:));
- (BOOL)deleteColumns:(NSRange)columns error:(NSError **)error NS_SWIFT_NAME(deleteColumns(_:));
- (BOOL)deleteRows:(NSRange)rows error:(NSError **)error NS_SWIFT_NAME(deleteRows(_:));
/// Insert empty cells the size of `range`, shifting what is there right
/// or down (`cmd_shift_rows` / `cmd_shift_cols`, the GTK Insert Cells
/// dialog's first two choices); undoable.
- (BOOL)insertCellsInRange:(GnmCellRange)range shiftingDown:(BOOL)down error:(NSError **)error NS_SWIFT_NAME(insertCells(in:shiftingDown:));
/// Delete the cells of `range`, shifting what follows left or up (the
/// GTK Delete Cells dialog's first two choices); undoable.
- (BOOL)deleteCellsInRange:(GnmCellRange)range shiftingUp:(BOOL)up error:(NSError **)error NS_SWIFT_NAME(deleteCells(in:shiftingUp:));
/// Today's date and/or the time of day as text for the edit position's
/// cell, the way the GTK Insert → Current Date/Time put it on the edit
/// line (the cell's date format when it has one, else the default
/// date and time formats, in the sheet's date conventions); the app
/// types it into the cell or the editor.
- (NSString *)currentDateTimeTextWithDate:(BOOL)date time:(BOOL)time NS_SWIFT_NAME(currentDateTimeText(date:time:));
/// Copy or cut the selection into the engine's clipboard, which also puts a
/// tab-separated text version on the system pasteboard; a cut becomes a move
/// when pasted.  Paste takes the engine's clipboard when it is current,
/// otherwise text from the system pasteboard (one value is matched like typed
/// input; several cells go through the engine's text importer).
- (void)copySelection;
- (void)cutSelection;
- (void)paste;
/// Paste Special: the same sources with explicit options.
- (void)pasteWithOptions:(GnmPasteOptions)options NS_SWIFT_NAME(paste(options:));
/// Sort the selection's rows by its columns left to right (`cmd_sort`, the
/// GTK quick sort): a single selected cell sorts the whole sheet below it
/// by that column; a heading row is detected and kept.  Several ranges
/// are refused.
- (BOOL)sortSelectionDescending:(BOOL)descending error:(NSError **)error NS_SWIFT_NAME(sortSelection(descending:));

// The Sort dialog (dialogs/dialog-cell-sort.c).
/// The range the dialog starts from: the selection, or the data region
/// around a single selected cell.
@property (nonatomic, readonly) GnmCellRange sortableRange;
/// Whether the first row (sorting by rows) or column of `range` looks like
/// a heading (`sheet_range_has_heading`).
- (BOOL)range:(GnmCellRange)range hasHeadingByRows:(BOOL)byRows NS_SWIFT_NAME(range(_:hasHeadingByRows:));
/// What the dialog calls a key: "Column B", or "Price (Column B)" when
/// the heading cell has text.
- (NSString *)sortKeyNameForIndex:(NSInteger)index inRange:(GnmCellRange)range byRows:(BOOL)byRows
                        hasHeader:(BOOL)hasHeader NS_SWIFT_NAME(sortKeyName(forIndex:in:byRows:hasHeader:));
/// Sort `range` by `keys` in order (`cmd_sort`); with `hasHeader` the
/// heading row (or column) stays.
- (BOOL)sortRange:(GnmCellRange)range byRows:(BOOL)byRows hasHeader:(BOOL)hasHeader keys:(NSArray<GnmSortKey *> *)keys
    retainFormats:(BOOL)retainFormats error:(NSError **)error NS_SWIFT_NAME(sort(_:byRows:hasHeader:keys:retainFormats:));
/// The engine's sort preferences (`core/sort/default/*`).
@property (class, nonatomic, readonly) BOOL sortDefaultsToCaseSensitive;
@property (class, nonatomic, readonly) BOOL sortDefaultsToRetainingFormats;
@property (class, nonatomic, readonly) BOOL sortDefaultsToAscending;

// Autofilter (Data → Filter).  A filter covers a range whose first row
// holds headings; each heading gets a button (`GnmFilterButton`) that
// drops down the column's values and the special choices.
/// Whether the edit position lies in a filter (the menu item then reads
/// Remove instead of Add).
@property (nonatomic, readonly) BOOL editPositionIsInFilter;
/// Whether any row is hidden by a filter.
@property (nonatomic, readonly) BOOL hasFilteredRows;
/// Add a filter over the selection, or over the region around a
/// single-row selection, or remove the filter at the edit position
/// (`cmd_autofilter_add_remove`); one undoable command.
- (BOOL)toggleAutofilter:(NSError **)error NS_SWIFT_NAME(toggleAutofilter());
/// Show every row the filters hide: drops each autofilter condition (an
/// undoable command each; the GTK item only serves the advanced filter)
/// and runs `filter_show_all` for rows an advanced filter hid.
- (void)showAllFilteredRows;
/// The buttons of every filter on the sheet, for drawing and hit testing.
@property (nonatomic, readonly) NSArray<GnmFilterButton *> *filterButtons;
/// The drop-down list of a button: the column's values and the current
/// condition.
- (GnmFilterChoices *)choicesForFilterButton:(GnmFilterButton *)button NS_SWIFT_NAME(choices(for:));
/// Apply a condition to the button's field (`cmd_autofilter_set_condition`).
- (BOOL)setFilterCondition:(GnmFilterCriterion *)condition forButton:(GnmFilterButton *)button
                     error:(NSError **)error NS_SWIFT_NAME(setFilterCondition(_:for:));

// Tab colors, as the file stores them; nil when unset.  Set through the
// workbook (`setTabColor:textColor:ofSheet:`), which makes the change
// undoable.
- (nullable CGColorRef)copyTabColor CF_RETURNS_RETAINED NS_SWIFT_NAME(tabColor());
- (nullable CGColorRef)copyTabTextColor CF_RETURNS_RETAINED NS_SWIFT_NAME(tabTextColor());
/// Frames (sheet pixels) of the ranges carrying marching ants: the source
/// of the last copy or cut, until it is pasted or cleared.
@property (nonatomic, readonly) NSArray<NSValue *> *marchingAntsFrames;
/// The style shared by the selected cells; properties that differ across
/// the selection are nil (`sheet_style_find_conflicts`).
@property (nonatomic, readonly) GnmCellFormat *formatOfSelection;
/// One cell's whole style (`sheet_style_get`), nothing nil: what the
/// in-cell editor takes its font, colors, and alignment from.
- (GnmCellFormat *)formatOfCellAtColumn:(NSInteger)column row:(NSInteger)row NS_SWIFT_NAME(formatOfCell(atColumn:row:));
/// Apply the set properties of `format` to the selection as one undoable
/// command (`cmd_selection_format`).
- (BOOL)applyFormat:(GnmCellFormat *)format error:(NSError **)error NS_SWIFT_NAME(apply(_:));
/// Hide or show the selected columns or rows (`cmd_selection_colrow_hide`).
- (BOOL)setSelectedColumns:(BOOL)columns hidden:(BOOL)hidden error:(NSError **)error NS_SWIFT_NAME(setSelected(columns:hidden:));

// Column widths and row heights.  Points are the engine's zoom-independent
// unit (what files store); `widthOfColumn:` and friends give pixels at the
// current zoom.
- (CGFloat)widthInPointsOfColumn:(NSInteger)column NS_SWIFT_NAME(widthInPoints(ofColumn:));
- (CGFloat)heightInPointsOfRow:(NSInteger)row NS_SWIFT_NAME(heightInPoints(ofRow:));
@property (nonatomic, readonly) CGFloat defaultColumnWidthInPoints;
@property (nonatomic, readonly) CGFloat defaultRowHeightInPoints;
/// Resize the selected columns or rows (`cmd_resize_colrow`); 0 points
/// restores the default size.
- (BOOL)setSelectedColumns:(BOOL)columns sizeInPoints:(CGFloat)points error:(NSError **)error NS_SWIFT_NAME(setSelected(columns:sizeInPoints:));
/// Resize a run of columns or rows to a pixel size at the current zoom
/// (header dragging); 0 restores the default, -1 fits the content.
- (BOOL)setColumns:(BOOL)columns inRange:(NSRange)range sizeInPixels:(NSInteger)pixels error:(NSError **)error NS_SWIFT_NAME(set(columns:in:sizeInPixels:));
/// Fit the selected columns or rows to all of their content.
- (BOOL)autofitSelectedColumns:(BOOL)columns error:(NSError **)error NS_SWIFT_NAME(autofitSelected(columns:));
/// Fit the columns (or rows) of the selection to the selected cells only
/// (`cmd_autofit_selection`).
- (BOOL)autofitSelectedCellsWidth:(BOOL)width error:(NSError **)error NS_SWIFT_NAME(autofitSelectedCells(width:));
/// Change the sheet's default column width or row height
/// (`cmd_colrow_std_size`); columns and rows without an explicit size follow.
- (BOOL)setDefaultSizeInPoints:(CGFloat)points forColumns:(BOOL)columns error:(NSError **)error NS_SWIFT_NAME(setDefaultSizeInPoints(_:forColumns:));

// Fill.
/// Copy the top row of the selection down over the rest of it, or the row
/// above into a single-row selection (`cmd_copyrel`, the GTK Copy Down).
- (BOOL)fillDown:(NSError **)error NS_SWIFT_NAME(fillDown());
/// The same from the left (Copy Right).
- (BOOL)fillRight:(NSError **)error NS_SWIFT_NAME(fillRight());
/// Autofill: extend `source` over `target`, which must contain `source` and
/// grow it in one direction only (what the fill handle does;
/// `cmd_autofill`).  `defaultIncrement` (the GTK Ctrl modifier) makes a
/// single-cell number source count up by one instead of repeating.
- (BOOL)autofillFromRange:(GnmCellRange)source toRange:(GnmCellRange)target defaultIncrement:(BOOL)defaultIncrement error:(NSError **)error NS_SWIFT_NAME(autofill(from:to:defaultIncrement:));

// Frozen panes (View → Freeze Panes).  `frozenTopLeft` is the first cell
// of the frozen area (the window's top-left when it was frozen) and
// `unfrozenTopLeft` the first cell that scrolls; a frozen pane has no
// frozen columns when the two columns are equal (both 0, the engine's
// rule), likewise rows.  Both are (-1, -1) when nothing is frozen.
@property (nonatomic, readonly, getter=isFrozen) BOOL frozen;
@property (nonatomic, readonly) GnmCellCoordinate frozenTopLeft;
@property (nonatomic, readonly) GnmCellCoordinate unfrozenTopLeft;
/// Freeze with `unfrozen` as the first scrolling cell and `frozen` as the
/// top-left of the frozen area (`gnm_sheet_view_freeze_panes`); the engine
/// ignores a request that freezes nothing.  The control hears back through
/// `sheetFrozenPanesDidChange:`.
- (void)freezePanesWithUnfrozenTopLeft:(GnmCellCoordinate)unfrozen frozenTopLeft:(GnmCellCoordinate)frozen NS_SWIFT_NAME(freezePanes(unfrozenTopLeft:frozenTopLeft:));
- (void)unfreezePanes;

// Merged cells.
/// Whether any selected range overlaps a merged region.
@property (nonatomic, readonly) BOOL selectionHasMergedCells;
- (BOOL)mergeSelectionCentered:(BOOL)center error:(NSError **)error NS_SWIFT_NAME(mergeSelection(centered:));
- (BOOL)unmergeSelection:(NSError **)error NS_SWIFT_NAME(unmergeSelection());

// Drawing, using the engine's own cell, border, and object renderers through
// cairo-quartz (docs/architecture.md §6).  `rect` is in sheet pixels and the
// context's CTM must map sheet pixels to the destination with y downward, as
// a flipped NSView's context does; the backing scale stays in the CTM.
- (void)drawCellsInRect:(CGRect)rect context:(CGContextRef)context backgroundColor:(nullable CGColorRef)backgroundColor NS_SWIFT_NAME(drawCells(in:context:backgroundColor:));
/// Charts, images, and other sheet objects whose frames intersect `rect`.
- (void)drawSheetObjectsInRect:(CGRect)rect context:(CGContextRef)context NS_SWIFT_NAME(drawSheetObjects(in:context:));
/// Frames of the sheet objects, for hit testing and invalidation.
@property (nonatomic, readonly) NSArray<NSValue *> *sheetObjectFrames;

// Sheet objects (Phase 4).  Wrappers are stable for the life of the sheet.
/// Every object on the sheet, front to back (the engine's stacking order).
@property (nonatomic, readonly) NSArray<GnmSheetObject *> *sheetObjects;
/// The frontmost selectable, visible object under a sheet pixel.
- (nullable GnmSheetObject *)sheetObjectAtPoint:(CGPoint)point NS_SWIFT_NAME(sheetObject(at:));
/// Move or resize objects to new frames (sheet pixels, one per object),
/// as one undoable command (`cmd_objects_move`, the GTK drag commit);
/// `resizing` only picks the undo label.  Anchors keep their mode: an
/// object tied to cells stays tied to the cells now under it.
- (BOOL)setFrames:(NSArray<NSValue *> *)frames ofSheetObjects:(NSArray<GnmSheetObject *> *)objects resizing:(BOOL)resizing
            error:(NSError **)error NS_SWIFT_NAME(setFrames(_:of:resizing:));
/// Delete objects (`cmd_objects_delete`); undo brings them back.
- (BOOL)deleteSheetObjects:(NSArray<GnmSheetObject *> *)objects error:(NSError **)error NS_SWIFT_NAME(deleteSheetObjects(_:));
/// Change an object's place in the stacking order (`cmd_object_raise`).
- (BOOL)restackSheetObject:(GnmSheetObject *)object direction:(GnmSheetObjectStacking)direction
                     error:(NSError **)error NS_SWIFT_NAME(restack(_:_:));

/// Copy objects into the engine's clipboard (`gnm_app_clipboard_cut_copy_obj`),
/// with a PNG of the first on the system pasteboard; a cut deletes them
/// now ("Cut Object", undoable) and `paste` puts copies at the selection.
- (void)copySheetObjects:(NSArray<GnmSheetObject *> *)objects cut:(BOOL)cut NS_SWIFT_NAME(copySheetObjects(_:cut:));

// Images (Insert → Image…).
/// The image's own size in sheet pixels at the current zoom (one image
/// pixel per point, as the engine sizes a new image), or zero when the
/// data is not an image the engine can decode.
- (CGSize)naturalSizeOfImageData:(NSData *)data NS_SWIFT_NAME(naturalSize(ofImageData:));
/// Insert an image (PNG, JPEG, and the other formats the engine decodes)
/// at `frame`, as one undoable command ("Insert 1 Object").
- (nullable GnmSheetObject *)insertImageData:(NSData *)data frame:(CGRect)frame
                                       error:(NSError **)error NS_SWIFT_NAME(insertImage(_:frame:));

// Charts (Insert → Chart…, the GTK chart guru's outcome).
/// The engine's default chart size (12 by 8 cm) in sheet pixels.
@property (nonatomic, readonly) CGSize defaultChartSize;
/// Insert a chart of `type` whose series come from the selection, the
/// way the guru fills a new plot (`sv_selection_to_plot`: a heading row
/// or column names the series, `layout` picks rows or columns, `shared`
/// makes the first series the abscissa of the others), at `frame`, as one
/// undoable command ("Insert 1 Object").  A legend is added when there is
/// more than one series.  Returns the new object, selected by nobody.
- (nullable GnmSheetObject *)insertChartOfType:(GnmPlotType *)type seriesLayout:(GnmChartSeriesLayout)layout
                                sharedAbscissa:(BOOL)shared frame:(CGRect)frame
                                         error:(NSError **)error NS_SWIFT_NAME(insertChart(_:seriesLayout:sharedAbscissa:frame:));

// Objects as image files (the GTK object menu's Save as Image…).
/// The formats an object can be written as: a chart's vector and raster
/// formats (`gog_graph_get_supported_image_formats`), an image's own
/// format first and then the raster ones goffice can convert to; empty
/// for objects that cannot be written.
- (NSArray<GnmImageFormat *> *)imageFormatsForSheetObject:(GnmSheetObject *)object NS_SWIFT_NAME(imageFormats(for:));
/// Write an object to a file in one of its formats
/// (`sheet_object_write_image`); `resolution` in dots per inch matters
/// for a chart's raster formats (the GTK dialog offers 150).
- (BOOL)writeImageOfSheetObject:(GnmSheetObject *)object format:(GnmImageFormat *)format resolution:(double)resolution
                          toURL:(NSURL *)url error:(NSError **)error NS_SWIFT_NAME(writeImage(of:format:resolution:to:));

@end

NS_ASSUME_NONNULL_END
