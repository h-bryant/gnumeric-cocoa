// A Sheet, its SheetView, and the Cocoa SheetControl attached to that view.
// Geometry is in sheet pixels at the sheet's zoom factor, origin at the
// top-left of cell A1, y increasing downward (the engine's own convention).
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <GnmCocoa/GnmGeometry.h>

NS_ASSUME_NONNULL_BEGIN

@class GnmWorkbook, GnmSheet;

/// Requests the engine makes through the SheetControl vtable
/// (docs/architecture.md §3).  All optional; all on the main thread.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(SheetDelegate)
@protocol GnmSheetDelegate <NSObject>
@optional
- (void)sheetNeedsDisplay:(GnmSheet *)sheet includingHeaders:(BOOL)includingHeaders;
- (void)sheet:(GnmSheet *)sheet needsDisplayInRange:(GnmCellRange)range;
- (void)sheet:(GnmSheet *)sheet needsHeaderDisplayForColumns:(BOOL)columns rows:(BOOL)rows;
/// Column or row sizes, zoom, or the scrollable extent changed.
- (void)sheetGeometryDidChange:(GnmSheet *)sheet;
- (void)sheet:(GnmSheet *)sheet cursorDidMoveToRange:(GnmCellRange)range;
- (void)sheet:(GnmSheet *)sheet scrollToColumn:(NSInteger)column row:(NSInteger)row;
- (void)sheet:(GnmSheet *)sheet makeVisibleColumn:(NSInteger)column row:(NSInteger)row;
- (void)sheetMarchingAntsDidChange:(GnmSheet *)sheet;
- (void)sheetFrozenPanesDidChange:(GnmSheet *)sheet;
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
@property (nonatomic, readonly) double zoomFactor;

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
- (CGFloat)widthOfColumn:(NSInteger)column;
- (CGFloat)heightOfRow:(NSInteger)row;
- (BOOL)isColumnVisible:(NSInteger)column;
- (BOOL)isRowVisible:(NSInteger)row;
/// Pixel distance from the sheet origin to the left edge of `column` (the sum
/// of all visible columns before it); `column` may equal `columnCount`.
- (CGFloat)leftEdgeOfColumn:(NSInteger)column;
- (CGFloat)topEdgeOfRow:(NSInteger)row;
/// The visible column containing x, clamped to the sheet.
- (NSInteger)columnAtX:(CGFloat)x;
- (NSInteger)rowAtY:(CGFloat)y;
- (CGRect)frameOfCellAtColumn:(NSInteger)column row:(NSInteger)row;

- (NSString *)nameOfColumn:(NSInteger)column;
- (NSString *)nameOfRow:(NSInteger)row;

// Cell contents.
- (BOOL)isCellEmptyAtColumn:(NSInteger)column row:(NSInteger)row;
- (BOOL)cellHasFormulaAtColumn:(NSInteger)column row:(NSInteger)row;
/// The formatted text the cell displays, or nil when the cell is empty.
- (nullable NSString *)displayTextOfCellAtColumn:(NSInteger)column row:(NSInteger)row;
/// What the user typed (formula or literal), as the formula bar shows it.
- (nullable NSString *)enteredTextOfCellAtColumn:(NSInteger)column row:(NSInteger)row;

// Selection, kept in the engine's SheetView.
@property (nonatomic, readonly) GnmCellCoordinate editPosition;
@property (nonatomic, readonly) GnmCellRange selectedRange;
- (void)selectCellAtColumn:(NSInteger)column row:(NSInteger)row;
- (void)selectRange:(GnmCellRange)range editPosition:(GnmCellCoordinate)editPosition;

// Drawing, using the engine's own cell, border, and object renderers through
// cairo-quartz (docs/architecture.md §6).  `rect` is in sheet pixels and the
// context's CTM must map sheet pixels to the destination with y downward, as
// a flipped NSView's context does; the backing scale stays in the CTM.
- (void)drawCellsInRect:(CGRect)rect context:(CGContextRef)context backgroundColor:(nullable CGColorRef)backgroundColor;
/// Charts, images, and other sheet objects whose frames intersect `rect`.
- (void)drawSheetObjectsInRect:(CGRect)rect context:(CGContextRef)context;
/// Frames of the sheet objects, for hit testing and invalidation.
@property (nonatomic, readonly) NSArray<NSValue *> *sheetObjectFrames;

@end

NS_ASSUME_NONNULL_END
