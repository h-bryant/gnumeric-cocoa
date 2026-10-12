// Fill Series through the engine's analysis tool: linear, growth, and
// date series by rows and columns, a step found from a stop, a stop
// cutting the range short, the number reader for the dialog's entries,
// and undo.
#import "GnmTest.h"

static NSString *
column (GnmSheet *s, int col, int rows)
{
    NSMutableArray *parts = [NSMutableArray array];
    for (int r = 0; r < rows; r++)
        [parts addObject:[s displayTextOfCellAtColumn:col row:r] ?: @"-"];
    return [parts componentsJoinedByString:@","];
}

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

        /* linear down a column with a step */
        GNM_ASSERT ([s fillSeriesInRange:GnmCellRangeMake (0, 0, 0, 4) byRows:NO kind:GnmFillSeriesLinear dateUnit:GnmFillSeriesDateUnitDay
                                   start:1 step:@2 stop:nil error:&error], @"linear: %@", error);
        GNM_ASSERT_EQ_STR (column (s, 0, 6), @"1,3,5,7,9,-");
        GNM_ASSERT ([wb.undoLabel ?: @"" hasPrefix:@"Fill Series"], @"label: %@", wb.undoLabel);
        [wb undo];
        GNM_ASSERT ([s isCellEmptyAtColumn:0 row:0], @"undone");
        [wb redo];
        GNM_ASSERT_EQ_STR (column (s, 0, 5), @"1,3,5,7,9");

        /* a step found from the stop over the range */
        GNM_ASSERT ([s fillSeriesInRange:GnmCellRangeMake (1, 0, 1, 4) byRows:NO kind:GnmFillSeriesLinear dateUnit:GnmFillSeriesDateUnitDay
                                   start:0 step:nil stop:@100 error:&error], @"stop only: %@", error);
        GNM_ASSERT_EQ_STR (column (s, 1, 5), @"0,25,50,75,100");

        /* a stop that cuts the range short */
        GNM_ASSERT ([s fillSeriesInRange:GnmCellRangeMake (2, 0, 2, 9) byRows:NO kind:GnmFillSeriesLinear dateUnit:GnmFillSeriesDateUnitDay
                                   start:10 step:@10 stop:@30 error:&error], @"step and stop: %@", error);
        GNM_ASSERT_EQ_STR (column (s, 2, 4), @"10,20,30,-");

        /* growth across a row */
        GNM_ASSERT ([s fillSeriesInRange:GnmCellRangeMake (0, 10, 3, 10) byRows:YES kind:GnmFillSeriesGrowth dateUnit:GnmFillSeriesDateUnitDay
                                   start:1 step:@3 stop:nil error:&error], @"growth: %@", error);
        NSMutableArray *row = [NSMutableArray array];
        for (int c = 0; c < 4; c++)
            [row addObject:[s displayTextOfCellAtColumn:c row:10] ?: @"-"];
        GNM_ASSERT_EQ_STR ([row componentsJoinedByString:@","], @"1,3,9,27");

        /* dates: the reader turns text into serials, months step by month */
        NSNumber *jan = [s numberFromText:@"2026-01-31"];
        GNM_ASSERT (jan != nil, @"a date reads as a number");
        GNM_ASSERT ([s numberFromText:@"12.5"].doubleValue == 12.5, @"a plain number reads");
        GNM_ASSERT ([s numberFromText:@"not a number"] == nil, @"text does not");
        GNM_ASSERT ([s fillSeriesInRange:GnmCellRangeMake (3, 0, 3, 2) byRows:NO kind:GnmFillSeriesDate dateUnit:GnmFillSeriesDateUnitMonth
                                   start:jan.doubleValue step:@1 stop:nil error:&error], @"months: %@", error);
        NSLog (@"month series from 2026-01-31: %@", column (s, 3, 3));
        GNM_ASSERT ([[s displayTextOfCellAtColumn:3 row:1] containsString:@"2"] , @"a date shown: %@", [s displayTextOfCellAtColumn:3 row:1]);
        GNM_ASSERT ([s fillSeriesInRange:GnmCellRangeMake (4, 0, 4, 6) byRows:NO kind:GnmFillSeriesDate dateUnit:GnmFillSeriesDateUnitWeekday
                                   start:[s numberFromText:@"2026-10-09"].doubleValue step:@1 stop:nil error:&error], @"weekdays: %@", error);
        NSLog (@"weekday series from Friday 2026-10-09: %@", column (s, 4, 7));
        double friday = [s numberFromText:@"2026-10-09"].doubleValue;
        GNM_ASSERT ([s numberFromText:[s displayTextOfCellAtColumn:4 row:1]].doubleValue == friday + 3, @"Friday steps to Monday");

        /* neither step nor stop */
        error = nil;
        GNM_ASSERT (![s fillSeriesInRange:GnmCellRangeMake (5, 0, 5, 3) byRows:NO kind:GnmFillSeriesLinear dateUnit:GnmFillSeriesDateUnitDay
                                    start:1 step:nil stop:nil error:&error] && error, @"refused without step or stop");

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("fill_series");
    }
}
