// Data → Merge (dialog-merge.c, `cmd_merge_data`): a merge zone of this
// sheet copied to one new sheet per data row, with each field cell in the
// zone taking that row's value from its data column (a form letter from a
// list).
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmSheet.h>

NS_ASSUME_NONNULL_BEGIN

@interface GnmSheet (Merge)
/// Whether text names a range of this sheet (a single cell when
/// `singleCell`), as the dialog enables its buttons
/// (`gnm_expr_entry_is_cell_ref`).
- (BOOL)isRangeText:(NSString *)text singleCell:(BOOL)singleCell NS_SWIFT_NAME(isRangeText(_:singleCell:));
/// The rows of the shortest and the longest data column; NO when a
/// text is not a range.  When they differ the dialog asks whether to
/// trim the columns to the shortest.
- (BOOL)mergeDataLengths:(NSArray<NSString *> *)data shortest:(NSInteger *)shortest longest:(NSInteger *)longest
    NS_SWIFT_NAME(mergeDataLengths(_:shortest:longest:));
/// The dialog's Merge: `zone` a range of this sheet, `fields` cells
/// within it, and `data` the column ranges in step with them ("Merging
/// data into Sheet1!A1:B3", undoable; one new sheet per data row, the zone
/// copied with its column and row sizes and objects).  NO with the
/// dialog's messages when a field lies outside the zone ("One field is
/// not part of the merge zone!") or, unless `trim` cuts the data columns
/// to the shortest, when their lengths differ.
- (BOOL)mergeDataIntoZone:(NSString *)zone fields:(NSArray<NSString *> *)fields data:(NSArray<NSString *> *)data
       trimmingToShortest:(BOOL)trim error:(NSError **)error
    NS_SWIFT_NAME(mergeData(intoZone:fields:data:trimmingToShortest:));
@end

NS_ASSUME_NONNULL_END
