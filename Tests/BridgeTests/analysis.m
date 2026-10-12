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

        /* two means: paired, then known variances (z), then unequal variances */
        GnmMeanTestAnalysis *mean = [[GnmMeanTestAnalysis alloc] init];
        mean.kind = GnmMeanTestPaired;
        mean.firstRange = @"A1:A6";
        mean.secondRange = @"B1:B6";
        mean.hasLabels = YES;
        out = [s runAnalysis:mean output:[GnmAnalysisOutput onNewSheet] error:&error];
        GNM_ASSERT (out != nil, @"paired: %@", error);
        GNM_ASSERT_EQ_STR (out.name, @"t-Test (1)");
        double t = beside (out, @"t Stat", 4, 30);
        NSLog (@"paired t: %g; rows: %@ / %@ / %@", t, cell (out, 0, 0), cell (out, 0, 1), cell (out, 0, 2));
        GNM_ASSERT (fabs (fabs (t) - 4.8826) < 0.001, @"paired t = %g", t);
        [wb undo];
        mean.kind = GnmMeanTestKnownVariances;
        mean.firstVariance = 2.5;
        mean.secondVariance = 12.2;
        out = [s runAnalysis:mean output:[GnmAnalysisOutput onNewSheet] error:&error];
        GNM_ASSERT (out != nil, @"z: %@", error);
        GNM_ASSERT_EQ_STR (out.name, @"z-Test (1)");
        double z = beside (out, @"z", 4, 30);
        NSLog (@"z: %g; rows: %@|%@|%@ / %@|%@|%@ / %@|%@|%@ / %@|%@|%@", z, cell (out, 0, 5), cell (out, 1, 5), cell (out, 2, 5),
               cell (out, 0, 6), cell (out, 1, 6), cell (out, 2, 6), cell (out, 0, 7), cell (out, 1, 7), cell (out, 2, 7),
               cell (out, 0, 1), cell (out, 1, 1), cell (out, 2, 1));
        GNM_ASSERT (fabs (fabs (z) - 2.4495) < 0.001, @"z = %g", z);
        GNM_ASSERT (number (out, 1, 1) == 3 && number (out, 2, 1) == 7.2, @"the ranges stay put: %@ %@", cell (out, 1, 1), cell (out, 2, 1));
        [wb undo];
        mean.kind = GnmMeanTestUnequalVariances;
        out = [s runAnalysis:mean output:[GnmAnalysisOutput onNewSheet] error:&error];
        GNM_ASSERT (out != nil, @"unequal: %@", error);
        double welch = beside (out, @"t Stat", 4, 30);
        NSLog (@"welch t: %g", welch);
        GNM_ASSERT (fabs (fabs (welch) - 2.4495) < 0.001, @"welch t = %g", welch);
        [wb undo];

        /* two variances */
        GnmVarianceTestAnalysis *ftest = [[GnmVarianceTestAnalysis alloc] init];
        ftest.firstRange = @"A1:A6";
        ftest.secondRange = @"B1:B6";
        ftest.hasLabels = YES;
        out = [s runAnalysis:ftest output:[GnmAnalysisOutput onNewSheet] error:&error];
        GNM_ASSERT (out != nil, @"F: %@", error);
        GNM_ASSERT_EQ_STR (out.name, @"F-Test (1)");
        double f = beside (out, @"F", 4, 30);
        NSLog (@"F: %g", f);
        GNM_ASSERT (fabs (f - 2.5 / 12.2) < 0.001, @"F = %g", f);
        [wb undo];

        /* single factor ANOVA */
        GnmAnovaSingleFactorAnalysis *anova = [[GnmAnovaSingleFactorAnalysis alloc] init];
        anova.inputRanges = @"A1:B6";
        anova.hasLabels = YES;
        out = [s runAnalysis:anova output:[GnmAnalysisOutput onNewSheet] error:&error];
        GNM_ASSERT (out != nil, @"anova: %@", error);
        GNM_ASSERT_EQ_STR (out.name, @"Single Factor ANOVA (1)");
        double ssb = beside (out, @"Between Groups", 8, 30);
        NSLog (@"anova SS between: %g", ssb);
        GNM_ASSERT (fabs (ssb - 44.1) < 1e-9, @"SS between = %g", ssb);
        [wb undo];

        /* ranks into a range */
        GnmRankingAnalysis *rank = [[GnmRankingAnalysis alloc] init];
        rank.inputRanges = @"A1:A6";
        rank.hasLabels = YES;
        GNM_ASSERT ([s runAnalysis:rank output:[GnmAnalysisOutput inRangeNamed:@"H1"] error:&error] == s, @"rank: %@", error);
        NSLog (@"ranks: %@ %@ %@ %@ / %@ %@ %@ %@", cell (s, 7, 0), cell (s, 8, 0), cell (s, 9, 0), cell (s, 10, 0),
               cell (s, 7, 1), cell (s, 8, 1), cell (s, 9, 1), cell (s, 10, 1));
        GNM_ASSERT_EQ_STR (cell (s, 9, 1), @"Rank");
        GNM_ASSERT (number (s, 9, 2) == 1 && number (s, 8, 2) == 5, @"the top value ranks first: %@ %@", cell (s, 8, 2), cell (s, 9, 2));

        /* periodic sampling into a range */
        GnmSamplingAnalysis *sampling = [[GnmSamplingAnalysis alloc] init];
        sampling.inputRanges = @"A2:A6";
        sampling.isPeriodic = YES;
        sampling.period = 2;
        sampling.sampleSize = 2;
        GNM_ASSERT ([s runAnalysis:sampling output:[GnmAnalysisOutput inRangeNamed:@"H10"] error:&error] == s, @"sampling: %@", error);
        NSLog (@"sampling: %@ %@ %@ %@ %@", cell (s, 7, 9), cell (s, 7, 10), cell (s, 7, 11), cell (s, 7, 12), cell (s, 7, 13));
        GNM_ASSERT (number (s, 7, 10) == 2 && number (s, 7, 11) == 4 && [s isCellEmptyAtColumn:7 row:12], @"every second value");

        /* a prior moving average of two */
        GnmMovingAverageAnalysis *average = [[GnmMovingAverageAnalysis alloc] init];
        average.inputRanges = @"A1:A6";
        average.hasLabels = YES;
        average.interval = 2;
        GNM_ASSERT ([s runAnalysis:average output:[GnmAnalysisOutput inRangeNamed:@"J10"] error:&error] == s, @"average: %@", error);
        NSLog (@"moving average: %@ %@ %@ %@ %@ %@", cell (s, 9, 9), cell (s, 9, 10), cell (s, 9, 11), cell (s, 9, 12), cell (s, 9, 13), cell (s, 9, 14));
        /* the engine's own quirk: with labels the last average is not written */
        GNM_ASSERT (number (s, 9, 11) == 1.5 && number (s, 9, 13) == 3.5, @"averages of pairs");

        /* exponential smoothing with its chart on a new sheet */
        GnmExponentialSmoothingAnalysis *smoothing = [[GnmExponentialSmoothingAnalysis alloc] init];
        smoothing.inputRanges = @"B1:B6";
        smoothing.hasLabels = YES;
        smoothing.includesChart = YES;
        out = [s runAnalysis:smoothing output:[GnmAnalysisOutput onNewSheet] error:&error];
        GNM_ASSERT (out != nil, @"smoothing: %@", error);
        GNM_ASSERT_EQ_STR (out.name, @"Exponential Smoothing (1)");
        NSLog (@"smoothing: %@ %@ %@ %@; objects %lu", cell (out, 0, 0), cell (out, 0, 1), cell (out, 0, 2), cell (out, 0, 3), (unsigned long) out.sheetObjects.count);
        GNM_ASSERT (out.sheetObjects.count == 1, @"a chart was added: %lu", (unsigned long) out.sheetObjects.count);
        [wb undo];
        GNM_ASSERT (wb.sheets.count == 1, @"smoothing sheet undone");

        /* their refusals */
        error = nil;
        mean.firstRange = @"nothing";
        GNM_ASSERT ([s runAnalysis:mean output:[GnmAnalysisOutput onNewSheet] error:&error] == nil
                    && [error.localizedDescription containsString:@"variable 1 range"], @"bad first: %@", error);
        error = nil;
        mean.firstRange = @"A1:A6";
        mean.kind = GnmMeanTestKnownVariances;
        mean.firstVariance = 0;
        GNM_ASSERT ([s runAnalysis:mean output:[GnmAnalysisOutput onNewSheet] error:&error] == nil
                    && [error.localizedDescription containsString:@"variance for variable 1"], @"bad variance: %@", error);
        error = nil;
        sampling.sampleCount = 0;
        GNM_ASSERT ([s runAnalysis:sampling output:[GnmAnalysisOutput onNewSheet] error:&error] == nil
                    && [error.localizedDescription containsString:@"number of samples"], @"bad count: %@", error);
        error = nil;
        average.interval = 0;
        GNM_ASSERT ([s runAnalysis:average output:[GnmAnalysisOutput onNewSheet] error:&error] == nil
                    && [error.localizedDescription containsString:@"interval is invalid"], @"bad interval: %@", error);
        error = nil;
        smoothing.dampingFactor = 1.5;
        GNM_ASSERT ([s runAnalysis:smoothing output:[GnmAnalysisOutput onNewSheet] error:&error] == nil
                    && [error.localizedDescription containsString:@"damping factor is invalid"], @"bad damping: %@", error);
        GNM_ASSERT (wb.sheets.count == 1, @"nothing added by refusals: %lu", (unsigned long) wb.sheets.count);

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
