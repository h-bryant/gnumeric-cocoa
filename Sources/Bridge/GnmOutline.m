// The outline state from the engine's column and row records, and the
// GTK's callbacks without their dialogs.
#import "GnmPrivate.h"

static NSError *
outline_error (GnmEngine *engine, NSString *message)
{
    return [engine _errorWithCode:GnmErrorCommandFailed description:message collected:@[]];
}

@implementation GnmSheet (Outline)

- (NSInteger)outlineLevelOfColumn:(NSInteger)column
{
    ColRowInfo const *cri = sheet_col_get_info (self.engineSheet, (int) column);
    return cri ? cri->outline_level : 0;
}

- (NSInteger)outlineLevelOfRow:(NSInteger)row
{
    ColRowInfo const *cri = sheet_row_get_info (self.engineSheet, (int) row);
    return cri ? cri->outline_level : 0;
}

- (BOOL)isColumnCollapsed:(NSInteger)column
{
    ColRowInfo const *cri = sheet_col_get_info (self.engineSheet, (int) column);
    return cri ? cri->is_collapsed : NO;
}

- (BOOL)isRowCollapsed:(NSInteger)row
{
    ColRowInfo const *cri = sheet_row_get_info (self.engineSheet, (int) row);
    return cri ? cri->is_collapsed : NO;
}

- (NSInteger)maximumColumnOutlineLevel { return self.engineSheet->cols.max_outline_level; }
- (NSInteger)maximumRowOutlineLevel { return self.engineSheet->rows.max_outline_level; }
- (BOOL)displaysOutlines { return self.engineSheet->display_outlines; }
- (BOOL)outlineSymbolsBelow { return self.engineSheet->outline_symbols_below; }
- (BOOL)outlineSymbolsRight { return self.engineSheet->outline_symbols_right; }

- (BOOL)selectionSpansAllColumns
{
    SheetView *sv = self.sheetView;
    GnmRange const *r = sv ? selection_first_range (sv, NULL, NULL) : NULL;
    return r && range_is_full (r, self.engineSheet, TRUE);
}

- (BOOL)selectionSpansAllRows
{
    SheetView *sv = self.sheetView;
    GnmRange const *r = sv ? selection_first_range (sv, NULL, NULL) : NULL;
    return r && range_is_full (r, self.engineSheet, FALSE);
}

- (BOOL)groupSelection:(BOOL)group columns:(BOOL)columns error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_selection_group (wbc, columns, group);
    } description:group ? @"Could not group." : @"Could not ungroup." error:error];
}

- (BOOL)setDetailShown:(BOOL)shown columns:(BOOL)columns error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    SheetView *sv = self.sheetView;
    if (!sheet || !workbook || !sv)
        return NO;
    /* hide_show_detail_real */
    GnmRange const *r = selection_first_range (sv, NULL, NULL);
    if (!r || sheet_colrow_can_group (sheet, r, columns)) {
        if (error)
            *error = outline_error (workbook.engine, [NSString stringWithFormat:@"%@ can only be performed on an existing group.",
                                                      shown ? @"Show Detail" : @"Hide Detail"]);
        return NO;
    }
    return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_selection_colrow_hide (wbc, columns, shown);
    } description:shown ? @"Could not show the detail." : @"Could not hide the detail." error:error];
}

- (BOOL)changeOutlineAtIndex:(NSInteger)index columns:(BOOL)columns depth:(NSInteger)depth error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_selection_outline_change (wbc, columns, (int) index, (int) depth);
    } description:@"Could not change the outline." error:error];
}

- (BOOL)changeGlobalOutlineForColumns:(BOOL)columns depth:(NSInteger)depth error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_global_outline_change (wbc, columns, (int) depth);
    } description:@"Could not change the outline." error:error];
}

@end
