// item_cursor_do_action for the cell drag.
#import "GnmPrivate.h"
#include <commands.h>
#include <clipboard.h>
#include <sheet-view.h>
#include <selection.h>
#include <ranges.h>

@implementation GnmSheet (Dragging)

- (BOOL)dropSelectionAtColumn:(NSInteger)column row:(NSInteger)row copying:(BOOL)copying error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GnmWorkbook *workbook = self.workbook;
    SheetView *sv = self.sheetView;
    Sheet *sheet = self.engineSheet;
    if (!workbook || !sv || !sheet)
        return NO;
    [workbook selectSheet:self];
    GnmRange const *r = selection_first_range (sv, NULL, NULL);
    if (!r)
        return NO;
    int width = r->end.col - r->start.col, height = r->end.row - r->start.row;
    if (column < 0 || row < 0 || column + width >= gnm_sheet_get_max_cols (sheet) || row + height >= gnm_sheet_get_max_rows (sheet)) {
        if (error)
            *error = [workbook.engine _errorWithCode:GnmErrorCommandFailed description:@"The cells would be moved off the sheet." collected:@[]];
        return NO;
    }
    if (column == r->start.col && row == r->start.row)
        return YES;
    GnmRange target;
    range_init (&target, (int) column, (int) row, (int) column + width, (int) row + height);
    /* cmd_paste reports its refusals through the context and returns
     * nothing, so a message during the run is the failure */
    NSString *description = copying ? @"Could not copy the cells." : @"Could not move the cells.";
    BOOL reported = NO;
    NSError *first = nil;
    BOOL ok = [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        BOOL ready = copying ? gnm_sheet_view_selection_copy (sv, wbc) : gnm_sheet_view_selection_cut (sv, wbc);
        if (!ready)
            return TRUE;
        GnmPasteTarget pt;
        cmd_paste (wbc, paste_target_init (&pt, sheet, &target, PASTE_ALL_CELL));
        return FALSE;
    } description:description reported:&reported error:&first];
    if (!ok) {
        if (error)
            *error = first;
        return NO;
    }
    if (reported) {
        if (error)
            *error = [workbook.engine _errorWithCode:GnmErrorCommandFailed description:description collected:@[]];
        return NO;
    }
    return YES;
}

@end
