// Plain value types shared by the bridge and the app.  Columns and rows are
// zero-based, as in the engine; ranges are inclusive at both ends.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    NSInteger column;
    NSInteger row;
} GnmCellCoordinate NS_SWIFT_NAME(CellCoordinate);

typedef struct {
    GnmCellCoordinate start;
    GnmCellCoordinate end;
} GnmCellRange NS_SWIFT_NAME(CellRange);

NS_INLINE GnmCellCoordinate GnmCellCoordinateMake(NSInteger column, NSInteger row) {
    GnmCellCoordinate c = { column, row };
    return c;
}

NS_INLINE GnmCellRange GnmCellRangeMake(NSInteger startColumn, NSInteger startRow,
                                        NSInteger endColumn, NSInteger endRow) {
    GnmCellRange r = { { startColumn, startRow }, { endColumn, endRow } };
    return r;
}

NS_INLINE BOOL GnmCellRangeContains(GnmCellRange r, GnmCellCoordinate c) {
    return c.column >= r.start.column && c.column <= r.end.column &&
           c.row >= r.start.row && c.row <= r.end.row;
}

NS_ASSUME_NONNULL_END
