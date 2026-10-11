// A Sheet, its SheetView, and the Cocoa SheetControl attached to that view.
// Geometry is in sheet pixels at the sheet's zoom factor, origin at the
// top-left of cell A1, y increasing downward (the engine's own convention).
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <GnmCocoa/GnmGeometry.h>
#import <GnmCocoa/GnmCellFormat.h>

NS_ASSUME_NONNULL_BEGIN

@class GnmWorkbook, GnmSheet;

/// What `clearSelection:` removes; mirrors the engine's CLEAR_* flags.
typedef NS_OPTIONS(NSUInteger, GnmClearOptions) {
    GnmClearValues = 1 << 0,
    GnmClearFormats = 1 << 1,
    GnmClearComments = 1 << 2,
    GnmClearMerges = 1 << 6,
    GnmClearObjects = 1 << 7,
} NS_SWIFT_NAME(ClearOptions);

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
@end

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
/// The sheet's zoom (1.0 = 100%).  Setting it re-lays out the engine's
/// column and row sizes and rendered values; the control reports back
/// through `sheetGeometryDidChange:`.
@property (nonatomic) double zoomFactor;

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
- (BOOL)insertColumns:(NSInteger)count atColumn:(NSInteger)column error:(NSError **)error NS_SWIFT_NAME(insertColumns(_:at:));
- (BOOL)insertRows:(NSInteger)count atRow:(NSInteger)row error:(NSError **)error NS_SWIFT_NAME(insertRows(_:at:));
- (BOOL)deleteColumns:(NSRange)columns error:(NSError **)error NS_SWIFT_NAME(deleteColumns(_:));
- (BOOL)deleteRows:(NSRange)rows error:(NSError **)error NS_SWIFT_NAME(deleteRows(_:));
/// Copy or cut the selection into the engine's clipboard, which also puts a
/// tab-separated text version on the system pasteboard; a cut becomes a move
/// when pasted.  Paste takes the engine's clipboard when it is current,
/// otherwise text from the system pasteboard (one value is matched like typed
/// input; several cells go through the engine's text importer).
- (void)copySelection;
- (void)cutSelection;
- (void)paste;
/// Frames (sheet pixels) of the ranges carrying marching ants: the source
/// of the last copy or cut, until it is pasted or cleared.
@property (nonatomic, readonly) NSArray<NSValue *> *marchingAntsFrames;
/// The style shared by the selected cells; properties that differ across
/// the selection are nil (`sheet_style_find_conflicts`).
@property (nonatomic, readonly) GnmCellFormat *formatOfSelection;
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

@end

NS_ASSUME_NONNULL_END
