// Tools → Compare Sheets (dialog-sheet-compare.c over `sheet-diff.h`):
// the differences between two sheets, of this workbook or of two, as the
// GTK dialog's tree lists them: a Cells section (added, removed, changed
// cells with their entered texts), a Formatting section (each range whose
// style differs, with the elements that differ and both values), and a
// Columns/Rows section (sizes).
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmGeometry.h>
#import <GnmCocoa/GnmSheet.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, GnmDifferenceSection) {
    GnmDifferenceSectionCells = 0,
    GnmDifferenceSectionFormatting,
    GnmDifferenceSectionColumnsRows,
} NS_SWIFT_NAME(SheetDifference.Section);

typedef NS_ENUM(NSInteger, GnmDifferenceDirection) {
    /// A section head.
    GnmDifferenceDirectionNone = 0,
    GnmDifferenceDirectionAdded,
    GnmDifferenceDirectionRemoved,
    GnmDifferenceDirectionChanged,
    /// A formatting or size entry (the GTK's DIR_QUIET).
    GnmDifferenceDirectionQuiet,
} NS_SWIFT_NAME(SheetDifference.Direction);

/// One row of the dialog's tree.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(SheetDifference)
@interface GnmSheetDifference : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly) GnmDifferenceSection section;
@property (nonatomic, readonly) GnmDifferenceDirection direction;
/// The Description column: "Cells", "Added", "Bold", "Various", "Size".
@property (nonatomic, readonly, copy) NSString *text;
/// The Location column: "B3", "Row 4", "Column C"; empty for a head.
@property (nonatomic, readonly, copy) NSString *location;
/// The Old and New columns: a cell's entered text, a style element's
/// value, a size in points; empty when there is none.
@property (nonatomic, readonly, copy) NSString *beforeText;
@property (nonatomic, readonly, copy) NSString *afterText;
/// Where the difference lies in each sheet (nil without one: an added
/// cell has no old place, a head none).
@property (nonatomic, readonly, nullable, weak) GnmSheet *beforeSheet;
@property (nonatomic, readonly, nullable, weak) GnmSheet *afterSheet;
@property (nonatomic, readonly) GnmCellRange beforeRange;
@property (nonatomic, readonly) GnmCellRange afterRange;
/// A section's entries, or a "Various" formatting entry's elements.
@property (nonatomic, readonly, copy) NSArray<GnmSheetDifference *> *children;
@end

@interface GnmSheet (Compare)
/// The differences from `beforeSheet` to this sheet (`gnm_diff_sheets`),
/// as section heads with their entries; empty when the sheets agree.
- (NSArray<GnmSheetDifference *> *)differencesFromSheet:(GnmSheet *)beforeSheet NS_SWIFT_NAME(differences(from:));
@end

NS_ASSUME_NONNULL_END
