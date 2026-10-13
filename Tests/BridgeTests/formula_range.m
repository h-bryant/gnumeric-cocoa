// Range selection while typing a formula: where a click may put a
// reference (after an operator or a parenthesis, in place of the operand
// under or before the cursor, never after a closing parenthesis or in
// plain text), range names, where arrow keys move, autocompletion, and
// array formulas over the selection.
#import "GnmTest.h"

static NSString *
probe (GnmSheet *s, NSString *text, NSInteger cursor)
{
    NSRange r;
    if (![s formulaText:text cursorAt:cursor canTakeRange:&r])
        return @"no";
    return [NSString stringWithFormat:@"%lu+%lu", (unsigned long) r.location, (unsigned long) r.length];
}

int main (void)
{
    @autoreleasepool {
        GnmEngine *engine = gnm_test_start_engine (NO);
        NSMutableArray<NSError *> *stray = [NSMutableArray array];
        engine.messageHandler = ^(NSError *e) { [stray addObject:e]; };
      @autoreleasepool {
        GnmWorkbook *wb = [engine newWorkbookWithSheetCount:1];
        GnmSheet *s = wb.sheets.firstObject;
        GNM_ASSERT_EQ_STR (probe (s, @"hello", 5), @"no");
        GNM_ASSERT_EQ_STR (probe (s, @"", 0), @"no");
        GNM_ASSERT_EQ_STR (probe (s, @"=", 1), @"1+0");
        GNM_ASSERT_EQ_STR (probe (s, @"=SUM(", 5), @"5+0");
        GNM_ASSERT_EQ_STR (probe (s, @"=A1+", 4), @"4+0");
        GNM_ASSERT_EQ_STR (probe (s, @"=A1+B2", 6), @"4+2");
        GNM_ASSERT_EQ_STR (probe (s, @"=A1+B2", 2), @"1+2");
        GNM_ASSERT_EQ_STR (probe (s, @"=A1+B2", 3), @"1+2");
        GNM_ASSERT_EQ_STR (probe (s, @"=SUM(A1:B2)", 11), @"no");
        GNM_ASSERT_EQ_STR (probe (s, @"=SUM(A1:B2,", 11), @"11+0");
        GNM_ASSERT_EQ_STR (probe (s, @"=SUM(A1:B2)+", 12), @"12+0");
        GNM_ASSERT_EQ_STR (probe (s, @"=1+2*", 5), @"5+0");
        GNM_ASSERT_EQ_STR (probe (s, @"=SUM(", 4), @"no");   /* before the parenthesis of a call */
        GNM_ASSERT_EQ_STR (probe (s, @"=\"été\"&", 7), @"7+0");
        GNM_ASSERT_EQ_STR ([s nameOfRange:GnmCellRangeMake (0, 0, 0, 0)], @"A1");
        GNM_ASSERT_EQ_STR ([s nameOfRange:GnmCellRangeMake (0, 0, 2, 3)], @"A1:C4");

        /* autocompletion from the column above */
        NSError *error = nil;
        GNM_ASSERT ([s setText:@"apple" atColumn:0 row:0 autocorrect:NO error:&error], @"apple: %@", error);
        GNM_ASSERT ([s setText:@"apricot" atColumn:0 row:1 autocorrect:NO error:&error], @"apricot: %@", error);
        GNM_ASSERT ([s setText:@"banana" atColumn:0 row:2 autocorrect:NO error:&error], @"banana: %@", error);
        NSString *ap = [s completionForText:@"ap" atColumn:0 row:3];
        NSLog (@"autocomplete: 'ap' -> '%@', 'app' -> '%@', 'b' -> '%@'", ap, [s completionForText:@"app" atColumn:0 row:3], [s completionForText:@"b" atColumn:0 row:3]);
        GNM_ASSERT ([[s completionForText:@"app" atColumn:0 row:3] isEqualToString:@"apple"], @"the nearest above that matches");
        GNM_ASSERT ([ap isEqualToString:@"apricot"] || ap == nil, @"'ap' is the nearest, or too short for the preference: %@", ap);
        GNM_ASSERT ([s completionForText:@"zzz" atColumn:0 row:3] == nil, @"nothing matches");
        GNM_ASSERT ([s completionForText:@"=ap" atColumn:0 row:3] == nil, @"formulas are not completed");
        GNM_ASSERT ([s completionForText:@"app" atColumn:1 row:3] == nil, @"another column");
        GNM_ASSERT ([s setText:@"" atColumn:0 row:2 autocorrect:NO error:&error], @"blank: %@", error);
        GNM_ASSERT ([s completionForText:@"app" atColumn:0 row:4] == nil, @"the search stops at a blank");

        /* arrow moves: D1:D3 filled, the rest empty */
        for (NSInteger r = 0; r < 3; r++) {
            NSString *number = [NSString stringWithFormat:@"%ld", (long) r + 1];
            GNM_ASSERT ([s setText:number atColumn:3 row:r autocorrect:NO error:&error], @"D: %@", error);
        }
        GnmCellCoordinate d1 = GnmCellCoordinateMake (3, 0), c;
        c = [s cell:d1 movedByColumns:0 rows:1 base:d1 jumpingToBoundary:NO];
        GNM_ASSERT (c.column == 3 && c.row == 1, @"a step down: %ld,%ld", (long) c.column, (long) c.row);
        c = [s cell:d1 movedByColumns:0 rows:1 base:d1 jumpingToBoundary:YES];
        GNM_ASSERT (c.column == 3 && c.row == 2, @"a jump down to the end of the data: %ld,%ld", (long) c.column, (long) c.row);
        GnmCellCoordinate d6 = GnmCellCoordinateMake (3, 5);
        c = [s cell:d6 movedByColumns:0 rows:-1 base:d6 jumpingToBoundary:YES];
        GNM_ASSERT (c.column == 3 && c.row == 2, @"a jump up from an empty cell to the data: %ld,%ld", (long) c.column, (long) c.row);
        c = [s cell:d1 movedByColumns:-1 rows:0 base:d1 jumpingToBoundary:NO];
        GNM_ASSERT (c.column == 2 && c.row == 0, @"a step left: %ld,%ld", (long) c.column, (long) c.row);
        GnmCellCoordinate a1 = GnmCellCoordinateMake (0, 0);
        c = [s cell:a1 movedByColumns:-1 rows:0 base:a1 jumpingToBoundary:NO];
        GNM_ASSERT (c.column == 0 && c.row == 0, @"the edge holds: %ld,%ld", (long) c.column, (long) c.row);
        GnmCellCoordinate d3 = GnmCellCoordinateMake (3, 2);
        c = [s cell:d3 movedByColumns:0 rows:1 base:d3 jumpingToBoundary:YES];
        NSLog (@"arrows: a jump down from the end of the data goes to %ld,%ld; a jump right from D1 to %ld,%ld",
               (long) c.column, (long) c.row,
               (long) [s cell:d1 movedByColumns:1 rows:0 base:d1 jumpingToBoundary:YES].column,
               (long) [s cell:d1 movedByColumns:1 rows:0 base:d1 jumpingToBoundary:YES].row);
        GNM_ASSERT (c.column == 3 && c.row > 2, @"a jump down from the end of the data moves on: %ld,%ld", (long) c.column, (long) c.row);

        /* an array formula over E1:E3 */
        [s selectRange:GnmCellRangeMake (4, 0, 4, 2) editPosition:GnmCellCoordinateMake (4, 0)];
        GNM_ASSERT ([s enterArrayFormula:@"=D1:D3*2" error:&error], @"array: %@", error);
        NSLog (@"array: E1..E3 = '%@' '%@' '%@', entered '%@', undo '%@'",
               [s displayTextOfCellAtColumn:4 row:0], [s displayTextOfCellAtColumn:4 row:1], [s displayTextOfCellAtColumn:4 row:2],
               [s enteredTextOfCellAtColumn:4 row:1], wb.undoLabel);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:4 row:0], @"2");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:4 row:1], @"4");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:4 row:2], @"6");
        GNM_ASSERT_EQ_STR (wb.undoLabel, @"Inserting array expression in E1:E3");
        /* one cell of it cannot be changed alone */
        error = nil;
        GNM_ASSERT (![s setText:@"x" atColumn:4 row:1 autocorrect:NO error:&error], @"a cell of an array changed alone");
        NSLog (@"array: changing one cell: %@", error.localizedDescription);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:4 row:1], @"4");
        [s selectRange:GnmCellRangeMake (4, 1, 4, 1) editPosition:GnmCellCoordinateMake (4, 1)];
        error = nil;
        GNM_ASSERT (![s enterArrayFormula:@"=1" error:&error], @"an array over part of an array");
        NSLog (@"array: over part of one: %@", error.localizedDescription);
        [wb undo];
        GNM_ASSERT ([s displayTextOfCellAtColumn:4 row:2] == nil || [[s displayTextOfCellAtColumn:4 row:2] isEqualToString:@""], @"undone: '%@'", [s displayTextOfCellAtColumn:4 row:2]);
        /* not a formula: the selection takes the text */
        [s selectRange:GnmCellRangeMake (5, 0, 5, 1) editPosition:GnmCellCoordinateMake (5, 0)];
        GNM_ASSERT ([s enterArrayFormula:@"hello" error:&error], @"text: %@", error);
        NSLog (@"array: text fill undo '%@'", wb.undoLabel);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:5 row:0], @"hello");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:5 row:1], @"hello");
        GNM_ASSERT ([s enterArrayFormula:@"-" error:&error], @"a lone minus: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:5 row:0], @"-");
        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("formula_range");
    }
}
