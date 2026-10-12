// Conditional formatting through the engine's style conditions: set on a
// selection, read back with the overlay, undone and redone, two-operand
// and custom conditions written relative to the edit position, the
// errors, cleared, and kept through a save and reopen.
#import "GnmTest.h"

static GnmConditionalFormat *
condition (GnmConditionOperator op, NSString *x, NSString *y, GnmCellFormat *format)
{
    GnmConditionalFormat *c = [[GnmConditionalFormat alloc] init];
    c.op = op;
    c.firstExpression = x;
    c.secondExpression = y;
    c.format = format;
    return c;
}

int main (void)
{
    @autoreleasepool {
        GnmEngineConfiguration *cfg = gnm_test_configuration (NO);
        cfg.xmlCompressionLevel = @0;
        GnmEngine *engine = gnm_test_start_engine_with (cfg);
        NSMutableArray<NSError *> *stray = [NSMutableArray array];
        engine.messageHandler = ^(NSError *e) { [stray addObject:e]; };
      @autoreleasepool {
        NSError *error = nil;
        GnmWorkbook *wb = [engine newWorkbookWithSheetCount:1];
        GnmSheet *s = wb.sheets.firstObject;
        for (int r = 0; r < 3; r++) {
            NSString *text = [NSString stringWithFormat:@"%d", 3 + 2 * r * r];
            BOOL ok = [s setText:text atColumn:0 row:r autocorrect:NO error:&error];
            GNM_ASSERT (ok, @"A%d: %@", r + 1, error);
        }
        GNM_ASSERT ([s conditionalFormatsAtColumn:0 row:1].count == 0, @"none yet");
        GNM_ASSERT ([GnmConditionalFormat operandCountForOperator:GnmConditionBetween] == 2
                    && [GnmConditionalFormat operandCountForOperator:GnmConditionContainsError] == 0
                    && [GnmConditionalFormat operandCountForOperator:GnmConditionGreaterThan] == 1, @"operand counts");
        GNM_ASSERT (GnmConditionalFormat.allOperators.count == 19, @"%lu operators", (unsigned long) GnmConditionalFormat.allOperators.count);
        GNM_ASSERT_EQ_STR ([GnmConditionalFormat labelForOperator:GnmConditionGreaterThan], @"Cell value is > x.");

        /* > 5 in red and bold on A1:A3 */
        GnmCellFormat *red = [[GnmCellFormat alloc] init];
        CGColorRef redColor = CGColorCreateSRGB (1, 0, 0, 1);
        red.backgroundColor = redColor;
        red.bold = @YES;
        [s selectRange:GnmCellRangeMake (0, 0, 0, 2) editPosition:GnmCellCoordinateMake (0, 0)];
        GNM_ASSERT ([s setConditionalFormats:@[condition (GnmConditionGreaterThan, @"5", @"", red)] error:&error], @"set: %@", error);
        GNM_ASSERT ([wb.undoLabel ?: @"" containsString:@"onditional"], @"label: %@", wb.undoLabel);
        NSArray<GnmConditionalFormat *> *read = [s conditionalFormatsAtColumn:0 row:1];
        GNM_ASSERT (read.count == 1, @"one condition on A2: %@", read);
        GNM_ASSERT (read.firstObject.op == GnmConditionGreaterThan, @"op %ld", (long) read.firstObject.op);
        GNM_ASSERT_EQ_STR (read.firstObject.firstExpression, @"5");
        GNM_ASSERT_EQ_STR (read.firstObject.secondExpression, @"");
        GNM_ASSERT (read.firstObject.format.bold.boolValue, @"bold overlay");
        GNM_ASSERT (read.firstObject.format.backgroundColor != NULL, @"fill overlay");
        GNM_ASSERT (read.firstObject.format.italic == nil && read.firstObject.format.numberFormat == nil, @"only the set parts");
        GNM_ASSERT ([s conditionalFormatsAtColumn:0 row:2].count == 1 && [s conditionalFormatsAtColumn:1 row:1].count == 0, @"the selection only");
        [wb undo];
        GNM_ASSERT ([s conditionalFormatsAtColumn:0 row:1].count == 0, @"undone");
        [wb redo];
        GNM_ASSERT ([s conditionalFormatsAtColumn:0 row:1].count == 1, @"redone");

        /* two conditions, one with two operands, one custom and relative */
        GnmCellFormat *italic = [[GnmCellFormat alloc] init];
        italic.italic = @YES;
        [s selectRange:GnmCellRangeMake (0, 0, 0, 2) editPosition:GnmCellCoordinateMake (0, 0)];
        NSArray *pair = @[condition (GnmConditionBetween, @"4", @"8", italic), condition (GnmConditionCustom, @"A1>B1", @"", red)];
        GNM_ASSERT ([s setConditionalFormats:pair error:&error], @"two: %@", error);
        read = [s conditionalFormatsAtColumn:0 row:0];
        GNM_ASSERT (read.count == 2, @"two on A1: %@", read);
        GNM_ASSERT (read[0].op == GnmConditionBetween && [read[0].firstExpression isEqualToString:@"4"]
                    && [read[0].secondExpression isEqualToString:@"8"], @"between 4 and 8: %@", read[0]);
        GNM_ASSERT_EQ_STR (read[1].firstExpression, @"A1>B1");
        [s selectCellAtColumn:0 row:1];
        GNM_ASSERT_EQ_STR ([s conditionalFormatsAtColumn:0 row:1][1].firstExpression, @"A2>B2");   /* relative, shown from the edit position */
        [s selectCellAtColumn:0 row:0];

        /* errors: a missing operand, an unreadable expression */
        error = nil;
        GNM_ASSERT (![s setConditionalFormats:@[condition (GnmConditionBetween, @"4", @"", italic)] error:&error] && error, @"missing y refused");
        NSLog (@"missing: %@", error.localizedDescription);
        error = nil;
        GNM_ASSERT (![s setConditionalFormats:@[condition (GnmConditionCustom, @"=1+", @"", italic)] error:&error] && error, @"unreadable refused");
        NSLog (@"unreadable: %@", error.localizedDescription);
        GNM_ASSERT ([s conditionalFormatsAtColumn:0 row:0].count == 2, @"nothing changed by the failures");

        /* kept through a save and reopen */
        NSURL *url = [NSURL fileURLWithPath:[gnm_test_env ("GNM_TEST_OUT") stringByAppendingPathComponent:@"conditional.gnumeric"]];
        GNM_ASSERT ([wb writeToURL:url adoptingURL:NO error:&error], @"save: %@", error);
        GnmWorkbook *again = [engine openWorkbookAtURL:url error:&error];
        GNM_ASSERT (again != nil, @"reopen: %@", error);
        NSArray<GnmConditionalFormat *> *kept = [again.sheets.firstObject conditionalFormatsAtColumn:0 row:2];
        GNM_ASSERT (kept.count == 2 && kept[0].op == GnmConditionBetween && kept[1].op == GnmConditionCustom, @"kept: %@", kept);
        GNM_ASSERT (kept[0].format.italic.boolValue && kept[1].format.bold.boolValue, @"overlays kept");
        again = nil;

        /* cleared */
        [s selectRange:GnmCellRangeMake (0, 0, 0, 2) editPosition:GnmCellCoordinateMake (0, 0)];
        GNM_ASSERT ([s setConditionalFormats:@[] error:&error], @"clear: %@", error);
        GNM_ASSERT ([s conditionalFormatsAtColumn:0 row:0].count == 0, @"cleared");
        [wb undo];
        GNM_ASSERT ([s conditionalFormatsAtColumn:0 row:0].count == 2, @"clear undone");
        CGColorRelease (redColor);

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("conditional");
    }
}
