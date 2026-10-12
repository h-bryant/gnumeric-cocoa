// Range selection while typing a formula: where a click may put a
// reference (after an operator or a parenthesis, in place of the operand
// under or before the cursor, never after a closing parenthesis or in
// plain text), and range names.
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
        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("formula_range");
    }
}
