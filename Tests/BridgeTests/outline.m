// Outlines: rows and columns grouped and ungrouped, levels and the
// deepest level, detail hidden and shown, a header toggle, the global
// change, the display options, and the refusals.
#import "GnmTest.h"

int main (void)
{
    @autoreleasepool {
        GnmEngine *engine = gnm_test_start_engine (NO);
        NSMutableArray<NSError *> *stray = [NSMutableArray array];
        engine.messageHandler = ^(NSError *e) { [stray addObject:e]; };
      @autoreleasepool {
        NSError *error = nil;
        GnmWorkbook *wb = [engine newWorkbookWithSheetCount:1];
        GnmSheet *s = wb.sheets.firstObject;
        NSInteger lastColumn = s.columnCount - 1, lastRow = s.rowCount - 1;
        GNM_ASSERT (s.maximumRowOutlineLevel == 0 && s.maximumColumnOutlineLevel == 0 && s.displaysOutlines, @"no groups at first");

        /* rows 2 to 4 grouped (whole rows selected: no need to ask) */
        [s selectRange:GnmCellRangeMake (0, 1, lastColumn, 3) editPosition:GnmCellCoordinateMake (0, 1)];
        GNM_ASSERT (s.selectionSpansAllColumns && !s.selectionSpansAllRows, @"whole rows");
        GNM_ASSERT ([s groupSelection:YES columns:NO error:&error], @"group rows: %@", error);
        NSLog (@"outline: rows grouped, undo '%@', levels %ld %ld %ld %ld max %ld", wb.undoLabel, (long) [s outlineLevelOfRow:0], (long) [s outlineLevelOfRow:1],
               (long) [s outlineLevelOfRow:3], (long) [s outlineLevelOfRow:4], (long) s.maximumRowOutlineLevel);
        GNM_ASSERT ([s outlineLevelOfRow:0] == 0 && [s outlineLevelOfRow:1] == 1 && [s outlineLevelOfRow:3] == 1 && [s outlineLevelOfRow:4] == 0, @"levels");
        GNM_ASSERT (s.maximumRowOutlineLevel == 1, @"max level 1");
        /* rows 2 and 3 again: a second level */
        [s selectRange:GnmCellRangeMake (0, 1, lastColumn, 2) editPosition:GnmCellCoordinateMake (0, 1)];
        GNM_ASSERT ([s groupSelection:YES columns:NO error:&error], @"group again: %@", error);
        GNM_ASSERT ([s outlineLevelOfRow:1] == 2 && [s outlineLevelOfRow:3] == 1 && s.maximumRowOutlineLevel == 2, @"nested: %ld %ld",
                    (long) [s outlineLevelOfRow:1], (long) s.maximumRowOutlineLevel);
        /* hide the detail of rows 2 to 4 */
        [s selectRange:GnmCellRangeMake (0, 1, lastColumn, 3) editPosition:GnmCellCoordinateMake (0, 1)];
        GNM_ASSERT ([s setDetailShown:NO columns:NO error:&error], @"hide detail: %@", error);
        NSLog (@"outline: detail hidden, undo '%@', visible %d %d %d, collapsed row 5 %d", wb.undoLabel, [s isRowVisible:1], [s isRowVisible:3], [s isRowVisible:4],
               [s isRowCollapsed:4]);
        GNM_ASSERT (![s isRowVisible:1] && ![s isRowVisible:3] && [s isRowVisible:4], @"rows hidden");
        GNM_ASSERT ([s isRowCollapsed:4], @"row 5 ends the hidden group");
        GNM_ASSERT ([s setDetailShown:YES columns:NO error:&error] && [s isRowVisible:1], @"show detail: %@", error);
        /* the header's toggle at row 5, level 1: collapses; again: expands */
        GNM_ASSERT ([s changeOutlineAtIndex:4 columns:NO depth:1 error:&error], @"toggle: %@", error);
        NSLog (@"outline: toggled at row 5, undo '%@', visible %d %d", wb.undoLabel, [s isRowVisible:1], [s isRowVisible:3]);
        GNM_ASSERT (![s isRowVisible:3], @"collapsed by the toggle");
        GNM_ASSERT ([s changeOutlineAtIndex:4 columns:NO depth:1 error:&error] && [s isRowVisible:3], @"expanded by the toggle: %@", error);
        /* the global level counts the levels shown: 1 is the top only, 2
         * shows the outer group and hides the inner one */
        GNM_ASSERT ([s changeGlobalOutlineForColumns:NO depth:1 error:&error] && ![s isRowVisible:3], @"global 1: %@", error);
        GNM_ASSERT ([s changeGlobalOutlineForColumns:NO depth:2 error:&error], @"global 2: %@", error);
        NSLog (@"outline: global depth 2, undo '%@', visible %d %d %d", wb.undoLabel, [s isRowVisible:1], [s isRowVisible:2], [s isRowVisible:3]);
        GNM_ASSERT (![s isRowVisible:1] && [s isRowVisible:3], @"the inner group hidden");
        GNM_ASSERT ([s changeGlobalOutlineForColumns:NO depth:3 error:&error] && [s isRowVisible:1], @"all shown: %@", error);
        /* ungroup the inner group */
        [s selectRange:GnmCellRangeMake (0, 1, lastColumn, 2) editPosition:GnmCellCoordinateMake (0, 1)];
        GNM_ASSERT ([s groupSelection:NO columns:NO error:&error] && [s outlineLevelOfRow:1] == 1, @"ungroup: %@", error);
        /* refusals */
        error = nil;
        GNM_ASSERT (![s groupSelection:NO columns:NO error:&error], @"ungrouped twice");
        NSLog (@"outline: ungrouping again: %@", error.localizedDescription);
        [s selectRange:GnmCellRangeMake (0, 9, lastColumn, 10) editPosition:GnmCellCoordinateMake (0, 9)];
        error = nil;
        GNM_ASSERT (![s setDetailShown:NO columns:NO error:&error] && [error.localizedDescription containsString:@"existing group"], @"no group: %@", error);

        /* columns B and C */
        [s selectRange:GnmCellRangeMake (1, 0, 2, lastRow) editPosition:GnmCellCoordinateMake (1, 0)];
        GNM_ASSERT (!s.selectionSpansAllColumns && s.selectionSpansAllRows, @"whole columns");
        GNM_ASSERT ([s groupSelection:YES columns:YES error:&error] && [s outlineLevelOfColumn:1] == 1 && [s outlineLevelOfColumn:3] == 0
                    && s.maximumColumnOutlineLevel == 1, @"group columns: %@", error);
        GNM_ASSERT ([s setDetailShown:NO columns:YES error:&error] && ![s isColumnVisible:2] && [s isColumnCollapsed:3], @"columns hidden: %@", error);
        [wb undo];
        GNM_ASSERT ([s isColumnVisible:2], @"undone");
        /* a plain range: neither axis is whole */
        [s selectRange:GnmCellRangeMake (1, 1, 2, 2) editPosition:GnmCellCoordinateMake (1, 1)];
        GNM_ASSERT (!s.selectionSpansAllColumns && !s.selectionSpansAllRows, @"ambiguous: the app asks");

        /* the display options */
        GNM_ASSERT ([s toggleDisplayOption:GnmSheetDisplayOptionOutlines error:&error] && !s.displaysOutlines, @"outlines off: %@", error);
        GNM_ASSERT_EQ_STR (wb.undoLabel, @"Toggle showing outlines");
        [wb undo];
        GNM_ASSERT (s.displaysOutlines, @"outlines back");
        GNM_ASSERT ([s toggleDisplayOption:GnmSheetDisplayOptionOutlineSymbolsRight error:&error] && !s.outlineSymbolsRight, @"symbols right off: %@", error);
        [wb undo];

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("outline");
    }
}
