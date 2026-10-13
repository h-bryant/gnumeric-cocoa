// The what-if tools: a data table over a two-input model, tabulations of
// a formula over one and two dependencies, the random generators, and
// the dialogs' refusals.
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
        /* the model: A1 = x, A2 = y, A3 = x·y; the table C1:E3 has the
         * corner formula, 10 and 20 for x across, 1 and 2 for y down */
        NSDictionary *texts = @{ @"0,0": @"2", @"0,1": @"3", @"0,2": @"=A1*A2", @"2,0": @"=A3", @"3,0": @"10", @"4,0": @"20", @"2,1": @"1", @"2,2": @"2" };
        for (NSString *key in texts) {
            NSArray *parts = [key componentsSeparatedByString:@","];
            GNM_ASSERT ([s setText:texts[key] atColumn:[parts[0] intValue] row:[parts[1] intValue] autocorrect:NO error:&error], @"model: %@", error);
        }
        [s selectRange:GnmCellRangeMake (2, 0, 4, 2) editPosition:GnmCellCoordinateMake (2, 0)];
        GNM_ASSERT ([s createDataTableWithRowInput:@"A1" columnInput:@"A2" error:&error], @"table: %@", error);
        NSLog (@"table: D2=%@ E2=%@ D3=%@ E3=%@ entered D2 '%@' undo '%@'", cell (s, 3, 1), cell (s, 4, 1), cell (s, 3, 2), cell (s, 4, 2),
               [s enteredTextOfCellAtColumn:3 row:1], wb.undoLabel);
        GNM_ASSERT (number (s, 3, 1) == 10 && number (s, 4, 1) == 20 && number (s, 3, 2) == 20 && number (s, 4, 2) == 40, @"x·y over the headers");
        GNM_ASSERT_EQ_STR (wb.undoLabel, @"Creating a Data Table in D2:E3");
        [wb undo];
        GNM_ASSERT ([s isCellEmptyAtColumn:3 row:1], @"undone");
        [wb redo];
        GNM_ASSERT (number (s, 3, 1) == 10, @"redone");
        /* refusals */
        [s selectRange:GnmCellRangeMake (2, 0, 2, 2) editPosition:GnmCellCoordinateMake (2, 0)];
        error = nil;
        GNM_ASSERT (![s createDataTableWithRowInput:@"A1" columnInput:@"A2" error:&error]
                    && [error.localizedDescription containsString:@"more than 1 column"], @"one column: %@", error);
        [s selectRange:GnmCellRangeMake (2, 0, 4, 2) editPosition:GnmCellCoordinateMake (2, 0)];
        error = nil;
        GNM_ASSERT (![s createDataTableWithRowInput:@"junk" columnInput:@"A2" error:&error]
                    && [error.localizedDescription containsString:@"one cell"], @"bad input: %@", error);

        /* a tabulation of A3 over A1 from 1 to 3 */
        NSUInteger before = wb.sheets.count;
        GnmTabulationDimension *dx = [[GnmTabulationDimension alloc] initWithCell:@"A1" minimum:1 maximum:3 step:1];
        GNM_ASSERT ([s tabulateCell:@"A3" dimensions:@[dx] withCoordinates:NO error:&error], @"tabulate: %@", error);
        GnmSheet *tabulation = wb.sheets.lastObject;
        NSMutableString *dump = [NSMutableString string];
        for (int r = 0; r < 5; r++)
            [dump appendFormat:@"%@ | %@ | %@ / ", cell (tabulation, 0, r), cell (tabulation, 1, r), cell (tabulation, 2, r)];
        NSLog (@"tabulate: %lu sheets, '%@': %@ undo '%@'", (unsigned long) wb.sheets.count, tabulation.name, dump, wb.undoLabel);
        GNM_ASSERT (wb.sheets.count == before + 1, @"one new sheet");
        GNM_ASSERT (number (tabulation, 1, 1) == 3 && number (tabulation, 1, 3) == 9, @"x·3 for x = 1 and 3: %@ %@", cell (tabulation, 1, 1), cell (tabulation, 1, 3));
        [wb undo];
        GNM_ASSERT (wb.sheets.count == before, @"the sheet went with the undo");
        /* two dimensions, one row per combination */
        GnmTabulationDimension *dy = [[GnmTabulationDimension alloc] initWithCell:@"A2" minimum:1 maximum:2 step:1];
        NSArray *both = @[dx, dy];
        GNM_ASSERT ([s tabulateCell:@"A3" dimensions:both withCoordinates:YES error:&error], @"tabulate 2: %@", error);
        tabulation = wb.sheets.lastObject;
        [dump setString:@""];
        for (int r = 0; r < 8; r++)
            [dump appendFormat:@"%@ | %@ | %@ / ", cell (tabulation, 0, r), cell (tabulation, 1, r), cell (tabulation, 2, r)];
        NSLog (@"tabulate 2: '%@': %@", tabulation.name, dump);
        GNM_ASSERT (number (tabulation, 2, 5) == 6, @"x = 3, y = 2 last: %@", cell (tabulation, 2, 5));
        [wb undo];
        /* refusals */
        error = nil;
        GNM_ASSERT (![s tabulateCell:@"A1" dimensions:@[dx] withCoordinates:NO error:&error]
                    && [error.localizedDescription containsString:@"target cell should contain"], @"no formula: %@", error);
        error = nil;
        GNM_ASSERT (![s tabulateCell:@"A3" dimensions:@[] withCoordinates:NO error:&error]
                    && [error.localizedDescription containsString:@"one or more"], @"no dimensions: %@", error);
        error = nil;
        GnmTabulationDimension *bad = [[GnmTabulationDimension alloc] initWithCell:@"A1" minimum:1 maximum:3 step:0];
        GNM_ASSERT (![s tabulateCell:@"A3" dimensions:@[bad] withCoordinates:NO error:&error]
                    && [error.localizedDescription containsString:@"positive"], @"zero step: %@", error);
        error = nil;
        GnmTabulationDimension *formula = [[GnmTabulationDimension alloc] initWithCell:@"A3" minimum:1 maximum:3 step:1];
        GNM_ASSERT (![s tabulateCell:@"A3" dimensions:@[formula] withCoordinates:NO error:&error]
                    && [error.localizedDescription containsString:@"should not contain an expression"], @"formula dependency: %@", error);
        error = nil;

        /* random numbers: uniform on [0, 1), two variables of five, into H1 */
        GNM_ASSERT (GnmRandomNumbersAnalysis.allDistributions.count == 30, @"the dialog's distributions");
        GNM_ASSERT_EQ_STR ([GnmRandomNumbersAnalysis labelForDistribution:GnmRandomDistributionNormal], @"Normal");
        GNM_ASSERT_EQ_STR ([GnmRandomNumbersAnalysis secondParameterLabelForDistribution:GnmRandomDistributionNormal], @"Standard deviation:");
        GNM_ASSERT ([GnmRandomNumbersAnalysis secondParameterLabelForDistribution:GnmRandomDistributionPoisson] == nil, @"one parameter");
        GnmRandomNumbersAnalysis *rnd = [[GnmRandomNumbersAnalysis alloc] init];
        rnd.variableCount = 2;
        rnd.count = 5;
        GNM_ASSERT ([s runAnalysis:rnd output:[GnmAnalysisOutput inRangeNamed:@"H1"] error:&error] == s, @"random: %@", error);
        NSLog (@"random uniform: H1=%@ I1=%@ H5=%@ I5=%@ undo '%@'", cell (s, 7, 0), cell (s, 8, 0), cell (s, 7, 4), cell (s, 8, 4), wb.undoLabel);
        for (int r = 0; r < 5; r++)
            for (int c = 7; c < 9; c++) {
                double v = number (s, c, r);
                GNM_ASSERT (v >= 0 && v < 1, @"uniform at %d,%d: %@", c, r, cell (s, c, r));
            }
        GNM_ASSERT ([s isCellEmptyAtColumn:7 row:5] && [s isCellEmptyAtColumn:9 row:0], @"nothing beyond");
        rnd.distribution = GnmRandomDistributionNormal;
        rnd.firstParameter = 100;
        rnd.secondParameter = 0;
        rnd.variableCount = 1;
        GNM_ASSERT ([s runAnalysis:rnd output:[GnmAnalysisOutput inRangeNamed:@"H7"] error:&error] == s, @"normal: %@", error);
        NSLog (@"random normal: H7=%@ H11=%@", cell (s, 7, 6), cell (s, 7, 10));
        GNM_ASSERT (fabs (number (s, 7, 6) - 100) < 1e-9 && fabs (number (s, 7, 10) - 100) < 1e-9, @"a zero deviation");
        GNM_ASSERT ([s setText:@"7" atColumn:10 row:0 autocorrect:NO error:&error] && [s setText:@"0.5" atColumn:11 row:0 autocorrect:NO error:&error]
                    && [s setText:@"9" atColumn:10 row:1 autocorrect:NO error:&error] && [s setText:@"0.5" atColumn:11 row:1 autocorrect:NO error:&error], @"values: %@", error);
        rnd.distribution = GnmRandomDistributionDiscrete;
        rnd.valueRange = @"K1:L2";
        rnd.count = 8;
        GNM_ASSERT ([s runAnalysis:rnd output:[GnmAnalysisOutput inRangeNamed:@"H13"] error:&error] == s, @"discrete: %@", error);
        NSMutableString *drawn = [NSMutableString string];
        for (int r = 12; r < 20; r++) {
            [drawn appendFormat:@"%@ ", cell (s, 7, r)];
            double v = number (s, 7, r);
            GNM_ASSERT (v == 7 || v == 9, @"a listed value: %@", cell (s, 7, r));
        }
        NSLog (@"random discrete: %@", drawn);
        error = nil;
        rnd.valueRange = @"nowhere";
        GNM_ASSERT ([s runAnalysis:rnd output:[GnmAnalysisOutput inRangeNamed:@"H13"] error:&error] == nil
                    && [error.localizedDescription containsString:@"probability input range"], @"bad values: %@", error);
        error = nil;
        rnd.distribution = GnmRandomDistributionUniform;
        rnd.count = 0;
        GNM_ASSERT ([s runAnalysis:rnd output:[GnmAnalysisOutput inRangeNamed:@"H13"] error:&error] == nil
                    && [error.localizedDescription containsString:@"random numbers requested"], @"no count: %@", error);
        error = nil;

        /* correlated: the identity in M1:N2, three rows into P1 */
        GNM_ASSERT ([s setText:@"1" atColumn:12 row:0 autocorrect:NO error:&error] && [s setText:@"0" atColumn:13 row:0 autocorrect:NO error:&error]
                    && [s setText:@"0" atColumn:12 row:1 autocorrect:NO error:&error] && [s setText:@"1" atColumn:13 row:1 autocorrect:NO error:&error], @"matrix: %@", error);
        GnmCorrelatedRandomNumbersAnalysis *cor = [[GnmCorrelatedRandomNumbersAnalysis alloc] init];
        cor.matrixRange = @"M1:N2";
        cor.count = 3;
        GNM_ASSERT ([s runAnalysis:cor output:[GnmAnalysisOutput inRangeNamed:@"P1"] error:&error] == s, @"correlated: %@", error);
        NSMutableString *layout = [NSMutableString string];
        int numeric = 0;
        for (int r = 0; r < 8; r++) {
            for (int c = 15; c < 20; c++) {
                [layout appendFormat:@"%@%@", c > 15 ? @" | " : @"", cell (s, c, r)];
                if (!isnan (number (s, c, r)))
                    numeric++;
            }
            [layout appendString:@" / "];
        }
        NSLog (@"random correlated: %@ undo '%@'", layout, wb.undoLabel);
        NSLog (@"random correlated entered: P2 '%@' Q2 '%@' Q3 '%@' S6 '%@'", [s enteredTextOfCellAtColumn:15 row:1], [s enteredTextOfCellAtColumn:16 row:1],
               [s enteredTextOfCellAtColumn:16 row:2], [s enteredTextOfCellAtColumn:18 row:5]);
        [s selectRange:GnmCellRangeMake (21, 0, 22, 1) editPosition:GnmCellCoordinateMake (21, 0)];
        GNM_ASSERT ([s enterArrayFormula:@"=CHOLESKY(M1:N2)" error:&error], @"cholesky: %@", error);
        NSLog (@"cholesky of the identity: %@ %@ / %@ %@", cell (s, 21, 0), cell (s, 22, 0), cell (s, 21, 1), cell (s, 22, 1));
        GNM_ASSERT (numeric >= 6, @"three rows of two numbers somewhere in the output: %d numbers", numeric);
        /* patch 0006: the correlated cells are numbers, not #VALUE!; with
         * values entered, each row's product is one array value in its
         * first cell (the engine shows its first element), with formulas
         * the array spans the variables */
        GNM_ASSERT (!isnan (number (s, 18, 5)) && !isnan (number (s, 18, 7)), @"correlated values: %@ %@", cell (s, 18, 5), cell (s, 18, 7));
        GnmAnalysisOutput *corOut = [GnmAnalysisOutput inRangeNamed:@"V1"];
        corOut.entersFormulas = YES;
        GNM_ASSERT ([s runAnalysis:cor output:corOut error:&error] == s, @"correlated formulas: %@", error);
        NSLog (@"random correlated formulas: %@ %@ / %@ %@ (%@)", cell (s, 24, 5), cell (s, 25, 5), cell (s, 24, 7), cell (s, 25, 7),
               [s enteredTextOfCellAtColumn:24 row:5]);
        GNM_ASSERT (!isnan (number (s, 24, 5)) && !isnan (number (s, 25, 5)) && !isnan (number (s, 25, 7)), @"both correlated columns: %@ %@", cell (s, 24, 5), cell (s, 25, 5));
        error = nil;
        cor.matrixRange = @"M1:N1";
        GNM_ASSERT ([s runAnalysis:cor output:[GnmAnalysisOutput inRangeNamed:@"P1"] error:&error] == nil
                    && [error.localizedDescription containsString:@"matrix range"], @"not square: %@", error);

        /* consolidation: AA1:AB2 and AA4:AB5 summed into AD1 */
        NSArray *first = @[@"1", @"2", @"3", @"4"], *secondArea = @[@"10", @"20", @"30", @"40"];
        for (int i = 0; i < 4; i++) {
            GNM_ASSERT ([s setText:first[i] atColumn:26 + i % 2 row:i / 2 autocorrect:NO error:&error], @"area 1: %@", error);
            GNM_ASSERT ([s setText:secondArea[i] atColumn:26 + i % 2 row:3 + i / 2 autocorrect:NO error:&error], @"area 2: %@", error);
        }
        GnmConsolidateAnalysis *con = [[GnmConsolidateAnalysis alloc] init];
        con.sourceRanges = @[@"AA1:AB2", @"AA4:AB5"];
        GNM_ASSERT ([s runAnalysis:con output:[GnmAnalysisOutput inRangeNamed:@"AD1"] error:&error] == s, @"consolidate: %@", error);
        NSLog (@"consolidate: %@ %@ / %@ %@ entered '%@' undo '%@'", cell (s, 29, 0), cell (s, 30, 0), cell (s, 29, 1), cell (s, 30, 1),
               [s enteredTextOfCellAtColumn:29 row:0], wb.undoLabel);
        GNM_ASSERT (number (s, 29, 0) == 11 && number (s, 30, 1) == 44, @"sums by position");
        [wb undo];
        con.function = GnmConsolidateFunctionMax;
        GnmAnalysisOutput *formulas = [GnmAnalysisOutput inRangeNamed:@"AD1"];
        formulas.entersFormulas = YES;
        GNM_ASSERT ([s runAnalysis:con output:formulas error:&error] == s, @"consolidate max: %@", error);
        NSLog (@"consolidate max: %@ entered '%@'", cell (s, 29, 0), [s enteredTextOfCellAtColumn:29 row:0]);
        GNM_ASSERT (number (s, 29, 0) == 10 && [[s enteredTextOfCellAtColumn:29 row:0] hasPrefix:@"="], @"a formula for the max");
        [wb undo];
        error = nil;
        con.sourceRanges = @[@"AA1:AB2", @"junk"];
        GNM_ASSERT ([s runAnalysis:con output:[GnmAnalysisOutput inRangeNamed:@"AD1"] error:&error] == nil
                    && [error.localizedDescription containsString:@"does not define a region"], @"bad source: %@", error);
        error = nil;
        con.sourceRanges = @[@"AA1:AB2", @"AA4:AB5"];
        GNM_ASSERT ([s runAnalysis:con output:[GnmAnalysisOutput inRangeNamed:@"AA1"] error:&error] == nil
                    && [error.localizedDescription containsString:@"overlaps"], @"overlapping output: %@", error);
        error = nil;
        /* shuffling AA1:AB2 keeps the values */
        GNM_ASSERT ([s shuffleRange:@"AA1:AB2" by:GnmShuffleArea error:&error], @"shuffle: %@", error);
        NSMutableArray *values = [NSMutableArray array];
        for (int i = 0; i < 4; i++)
            [values addObject:@(number (s, 26 + i % 2, i / 2))];
        [values sortUsingSelector:@selector(compare:)];
        NSLog (@"shuffle: %@ undo '%@'", values, wb.undoLabel);
        NSArray *expected = @[@1, @2, @3, @4];
        GNM_ASSERT ([values isEqualToArray:expected], @"the same values: %@", values);
        [wb undo];
        GNM_ASSERT (number (s, 26, 0) == 1 && number (s, 27, 1) == 4, @"undone");
        error = nil;
        GNM_ASSERT (![s shuffleRange:@"nowhere" by:GnmShuffleRows error:&error] && [error.localizedDescription containsString:@"input range"], @"bad range: %@", error);
        error = nil;

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("whatif");
    }
}
