// Dragging the selection by its border (item-cursor.c's ACTION_MOVE_CELLS
// and ACTION_COPY_CELLS): the cells go to where they are dropped, with
// references adjusted as a cut and paste adjusts them, or a copy of them.
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmSheet.h>

NS_ASSUME_NONNULL_BEGIN

@interface GnmSheet (Dragging)
/// Drop the selection's first range with its top left at `column`,
/// `row` (`gnm_sheet_view_selection_cut` or `_copy`, then `cmd_paste`
/// with PASTE_ALL_CELL; the engine's clipboard holds the cells after,
/// as in the GTK).  NO with the engine's message when the range splits
/// an array or a merged region, or the target would run off the sheet.
- (BOOL)dropSelectionAtColumn:(NSInteger)column row:(NSInteger)row copying:(BOOL)copying error:(NSError **)error
    NS_SWIFT_NAME(dropSelection(atColumn:row:copying:));
@end

NS_ASSUME_NONNULL_END
