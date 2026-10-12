// The analysis tools: descriptive statistics to a new sheet (named,
// focused, undone and redone), correlation and covariance into a range
// with labels, regression with its coefficients, the range list reader,
// and the dialogs' refusals.
#import "GnmTest.h"

static NSString *
cell (GnmSheet *s, int col, int row)
{
    return [s displayTextOfCellAtColumn:col row:row] ?: @"-";
}

static double
number (GnmSheet *s, int col, int row)
{
    NSNumber *n = [s numberFromText:cell (s, col, row)];
    return n ? n.doubleValue : NAN;
}

/* The cell to the right of the first cell showing @text within the area. */
static double
beside (GnmSheet *s, NSString *text, int cols, int rows)
{
    for (int r = 0; r < rows; r++)
        for (int c = 0; c < cols; c++)
            if ([cell (s, c, r) isEqualToString:text])
                return number (s, c + 1, r);
    return NAN;
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
        NSArray *xs = @[@"x", @"1", @"2", @"3", @"4", @"5"];
        NSArray *ys = @[@"y", @"3", @"5", @"7", @"9", @"12"];
        for (int r = 0; r < 6; r++) {
            GNM_ASSERT ([s setText:xs[r] atColumn:0 row:r autocorrect:NO error:&error], @"x: %@", error);
            GNM_ASSERT ([s setText:ys[r] atColumn:1 row:r autocorrect:NO error:&error], @"y: %@", error);
        }

        /* the range list reader */
        NSArray *names = [s rangeNamesInList:@"A1:B6, D1:D3"];
        GNM_ASSERT_EQ_STR ([names componentsJoinedByString:@"|"], @"A1:B6|D1:D3");
        GNM_ASSERT ([s rangeNamesInList:@"foo"] == nil, @"a name is not a range");
        GNM_ASSERT ([s rangeNamesInList:@""] == nil, @"empty");

        /* descriptive statistics to a new sheet */
        GnmDescriptiveStatistics *desc = [[GnmDescriptiveStatistics alloc] init];
        desc.inputRanges = @"A1:B6";
        desc.hasLabels = YES;
        desc.confidenceLevel = @0.95;
        desc.kthLargest = @2;
        GnmSheet *out = [s runAnalysis:desc output:[GnmAnalysisOutput onNewSheet] error:&error];
        GNM_ASSERT (out != nil, @"descriptive: %@", error);
        GNM_ASSERT_EQ_STR (out.name, @"Descriptive Statistics (1)");
        GNM_ASSERT (wb.sheets.count == 2 && wb.currentSheet == out, @"a new sheet, focused: %lu %@", (unsigned long) wb.sheets.count, wb.currentSheet.name);
        GNM_ASSERT_EQ_STR (cell (out, 1, 0), @"x");
        GNM_ASSERT_EQ_STR (cell (out, 2, 0), @"y");
        GNM_ASSERT_EQ_STR (cell (out, 0, 1), @"Mean");
        GNM_ASSERT (number (out, 1, 1) == 3 && number (out, 2, 1) == 7.2, @"means %@ %@", cell (out, 1, 1), cell (out, 2, 1));
        GNM_ASSERT_EQ_STR (cell (out, 0, 13), @"Count");
        GNM_ASSERT (number (out, 1, 13) == 5, @"count %@", cell (out, 1, 13));
        GNM_ASSERT (beside (out, @"Largest (2)", 3, 30) == 4, @"2nd largest x");
        NSLog (@"descriptive: undo label '%@'; CI rows: %@ %@", wb.undoLabel, cell (out, 0, 15), cell (out, 0, 16));
        GNM_ASSERT ([wb.undoLabel ?: @"" hasPrefix:@"Descriptive Statistics"], @"label: %@", wb.undoLabel);
        [wb undo];
        GNM_ASSERT (wb.sheets.count == 1, @"undo removes the sheet: %lu", (unsigned long) wb.sheets.count);
        [wb redo];
        GNM_ASSERT (wb.sheets.count == 2, @"redo restores it");
        GNM_ASSERT_EQ_STR (cell (wb.sheets.lastObject, 0, 1), @"Mean");
        [wb undo];

        /* correlation into a range, grouped by columns with labels */
        GnmCorrelationAnalysis *corr = [[GnmCorrelationAnalysis alloc] init];
        corr.inputRanges = @"A1:B6";
        corr.hasLabels = YES;
        out = [s runAnalysis:corr output:[GnmAnalysisOutput inRangeNamed:@"D1"] error:&error];
        GNM_ASSERT (out == s, @"correlation into this sheet: %@", error);
        NSLog (@"correlation: D1..F3 = %@ %@ %@ / %@ %@ %@ / %@ %@ %@", cell (s, 3, 0), cell (s, 4, 0), cell (s, 5, 0),
               cell (s, 3, 1), cell (s, 4, 1), cell (s, 5, 1), cell (s, 3, 2), cell (s, 4, 2), cell (s, 5, 2));
        GNM_ASSERT_EQ_STR (cell (s, 4, 0), @"x");
        GNM_ASSERT_EQ_STR (cell (s, 3, 2), @"y");
        double rxy = number (s, 4, 2);
        GNM_ASSERT (fabs (rxy - 0.99589) < 0.0001, @"r(x,y) = %g", rxy);
        GNM_ASSERT ([wb.undoLabel ?: @"" hasPrefix:@"Correlation"], @"label: %@", wb.undoLabel);

        /* covariance, by areas, formulas entered */
        GnmCovarianceAnalysis *cov = [[GnmCovarianceAnalysis alloc] init];
        cov.inputRanges = @"A2:A6, B2:B6";
        cov.grouping = GnmAnalysisGroupingAreas;
        GnmAnalysisOutput *into = [GnmAnalysisOutput inRangeNamed:@"D6"];
        into.entersFormulas = YES;
        GNM_ASSERT ([s runAnalysis:cov output:into error:&error] == s, @"covariance: %@", error);
        NSLog (@"covariance: D6..F8 = %@ %@ %@ / %@ %@ %@ / %@ %@ %@", cell (s, 3, 5), cell (s, 4, 5), cell (s, 5, 5),
               cell (s, 3, 6), cell (s, 4, 6), cell (s, 5, 6), cell (s, 3, 7), cell (s, 4, 7), cell (s, 5, 7));
        GNM_ASSERT (number (s, 4, 7) == 4.4, @"cov(x,y) = %@", cell (s, 4, 7));
        GNM_ASSERT ([[s enteredTextOfCellAtColumn:4 row:7] hasPrefix:@"="], @"a formula: %@", [s enteredTextOfCellAtColumn:4 row:7]);

        /* regression: y on x */
        GnmRegressionAnalysis *reg = [[GnmRegressionAnalysis alloc] init];
        reg.xRange = @"A1:A6";
        reg.yRange = @"B1:B6";
        reg.hasLabels = YES;
        out = [s runAnalysis:reg output:[GnmAnalysisOutput onNewSheet] error:&error];
        GNM_ASSERT (out != nil, @"regression: %@", error);
        GNM_ASSERT_EQ_STR (out.name, @"Regression (1)");
        double intercept = beside (out, @"Intercept", 8, 40), slope = beside (out, @"x", 8, 40);
        NSLog (@"regression: intercept %g slope %g; A1..A6 = %@ %@ %@ %@ %@ %@", intercept, slope,
               cell (out, 0, 0), cell (out, 0, 1), cell (out, 0, 2), cell (out, 0, 3), cell (out, 0, 4), cell (out, 0, 5));
        GNM_ASSERT (fabs (intercept - 0.6) < 1e-9 && fabs (slope - 2.2) < 1e-9, @"fit");
        GNM_ASSERT ([wb.undoLabel ?: @"" hasPrefix:@"Regression"], @"label: %@", wb.undoLabel);
        [wb undo];
        GNM_ASSERT (wb.sheets.count == 1, @"regression sheet undone");

        /* refusals, with the dialogs' words */
        error = nil;
        desc.inputRanges = @"nonsense";
        GNM_ASSERT ([s runAnalysis:desc output:[GnmAnalysisOutput onNewSheet] error:&error] == nil
                    && [error.localizedDescription containsString:@"input range is invalid"], @"bad input: %@", error);
        error = nil;
        desc.inputRanges = @"A2:A6, B2:B4";
        desc.grouping = GnmAnalysisGroupingAreas;
        GNM_ASSERT ([s runAnalysis:desc output:[GnmAnalysisOutput onNewSheet] error:&error] == nil
                    && [error.localizedDescription containsString:@"areas must have equal size"], @"unequal: %@", error);
        GNM_ASSERT (wb.sheets.count == 1, @"nothing added: %lu", (unsigned long) wb.sheets.count);
        error = nil;
        desc.inputRanges = @"A2:A6";
        desc.summaryStatistics = NO;
        desc.confidenceLevel = nil;
        desc.kthLargest = nil;
        GNM_ASSERT ([s runAnalysis:desc output:[GnmAnalysisOutput onNewSheet] error:&error] == nil
                    && [error.localizedDescription containsString:@"No statistics"], @"none: %@", error);
        error = nil;
        desc.kthLargest = @0;
        GNM_ASSERT ([s runAnalysis:desc output:[GnmAnalysisOutput onNewSheet] error:&error] == nil
                    && [error.localizedDescription containsString:@"positive integer"], @"k: %@", error);
        error = nil;
        desc.kthLargest = @1;
        GNM_ASSERT ([s runAnalysis:desc output:[GnmAnalysisOutput inRangeNamed:@"nowhere"] error:&error] == nil
                    && [error.localizedDescription containsString:@"output range is invalid"], @"bad output: %@", error);
        error = nil;
        reg.yRange = @"A1:B6";
        GNM_ASSERT ([s runAnalysis:reg output:[GnmAnalysisOutput onNewSheet] error:&error] == nil
                    && [error.localizedDescription containsString:@"must be a vector"], @"y matrix: %@", error);
        error = nil;
        reg.yRange = @"B1:B4";
        GNM_ASSERT ([s runAnalysis:reg output:[GnmAnalysisOutput onNewSheet] error:&error] == nil
                    && [error.localizedDescription containsString:@"do not match"], @"sizes: %@", error);
        error = nil;
        reg.yRange = @"B1:B6";
        reg.confidenceLevel = 1.5;
        GNM_ASSERT ([s runAnalysis:reg output:[GnmAnalysisOutput onNewSheet] error:&error] == nil
                    && [error.localizedDescription containsString:@"confidence level is invalid"], @"confidence: %@", error);

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("analysis");
    }
}
