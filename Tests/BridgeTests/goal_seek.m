// Goal Seek through the engine's solver: a root found and committed as
// one undoable command, bounds, a seek that fails and leaves the cell
// alone, the input checks, and the cell reference parser.
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
        GNM_ASSERT ([s setText:@"2" atColumn:0 row:0 autocorrect:NO error:&error], @"A1: %@", error);
        GNM_ASSERT ([s setText:@"=A1*A1-9" atColumn:1 row:0 autocorrect:NO error:&error], @"B1: %@", error);
        NSString *before = wb.undoLabel;

        /* references */
        NSInteger c = -1, r = -1;
        GNM_ASSERT ([s parseCellReference:@"B3" column:&c row:&r] && c == 1 && r == 2, @"B3 parses to %ld,%ld", (long) c, (long) r);
        GNM_ASSERT ([s parseCellReference:@"$AA$10" column:&c row:&r] && c == 26 && r == 9, @"$AA$10 parses");
        GNM_ASSERT (![s parseCellReference:@"nonsense" column:&c row:&r], @"a word does not parse");
        GNM_ASSERT (![s parseCellReference:@"" column:&c row:&r], @"empty does not parse");

        /* a root: x^2 - 9 = 0 from 2 reaches 3 */
        GnmGoalSeekResult *result = [s goalSeekCellAtColumn:1 row:0 toValue:0 byChangingCellAtColumn:0 row:0 minimum:nil maximum:nil error:&error];
        GNM_ASSERT (result != nil, @"seek: %@", error);
        GNM_ASSERT (result.found, @"found");
        GNM_ASSERT (fabs (result.solution - 3) < 1e-6, @"solution %g", result.solution);
        GNM_ASSERT (fabs (result.currentValue) < 1e-6 && result.targetValue == 0, @"current %g target %g", result.currentValue, result.targetValue);
        GNM_ASSERT (fabs ([s numberFromText:[s displayTextOfCellAtColumn:0 row:0]].doubleValue - 3) < 1e-6, @"A1 is %@", [s displayTextOfCellAtColumn:0 row:0]);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Goal Seek (A1)");
        [wb undo];
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:0 row:0], @"2");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:1 row:0], @"\u22125");   /* the engine renders a true minus */
        [wb redo];
        GNM_ASSERT (fabs ([s numberFromText:[s displayTextOfCellAtColumn:0 row:0]].doubleValue - 3) < 1e-6, @"redone");
        [wb undo];

        /* bounds: the negative root */
        result = [s goalSeekCellAtColumn:1 row:0 toValue:0 byChangingCellAtColumn:0 row:0 minimum:@(-10) maximum:@0 error:&error];
        GNM_ASSERT (result != nil && result.found, @"bounded seek: %@", error);
        GNM_ASSERT (fabs (result.solution + 3) < 1e-6, @"negative root %g", result.solution);
        [wb undo];
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:0 row:0], @"2");

        /* no solution: x^2 + 1 never reaches 0 */
        GNM_ASSERT ([s setText:@"=A1*A1+1" atColumn:1 row:0 autocorrect:NO error:&error], @"B1 again: %@", error);
        NSString *label = wb.undoLabel;
        result = [s goalSeekCellAtColumn:1 row:0 toValue:0 byChangingCellAtColumn:0 row:0 minimum:nil maximum:nil error:&error];
        GNM_ASSERT (result != nil && !result.found, @"no solution: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:0 row:0], @"2");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:1 row:0], @"5");
        GNM_ASSERT ([wb.undoLabel ?: @"" isEqualToString:label ?: @""], @"nothing recorded: %@", wb.undoLabel);

        /* the checks */
        error = nil;
        GNM_ASSERT ([s goalSeekCellAtColumn:0 row:0 toValue:0 byChangingCellAtColumn:2 row:0 minimum:nil maximum:nil error:&error] == nil && error,
                    @"a set cell without a formula is refused");
        error = nil;
        GNM_ASSERT ([s goalSeekCellAtColumn:1 row:0 toValue:0 byChangingCellAtColumn:1 row:0 minimum:nil maximum:nil error:&error] == nil && error,
                    @"a changing cell with a formula is refused");
        NSLog (@"refusal: %@", error.localizedDescription);

        /* an empty changing cell gets a value */
        GNM_ASSERT ([s setText:@"=D1*2-8" atColumn:4 row:0 autocorrect:NO error:&error], @"E1: %@", error);
        result = [s goalSeekCellAtColumn:4 row:0 toValue:0 byChangingCellAtColumn:3 row:0 minimum:nil maximum:nil error:&error];
        GNM_ASSERT (result != nil && result.found && fabs (result.solution - 4) < 1e-6, @"from empty: %g (%@)", result.solution, error);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Goal Seek (D1)");
        [wb undo];
        GNM_ASSERT ([s isCellEmptyAtColumn:3 row:0] || [[s displayTextOfCellAtColumn:3 row:0] isEqualToString:@""], @"empty again: %@", [s displayTextOfCellAtColumn:3 row:0]);
        (void) before;

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("goal_seek");
    }
}
