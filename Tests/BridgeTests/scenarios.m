// Scenarios: added, listed, shown and restored through the manager's
// session, deleted, summarized; and the risk simulation tool.
#import "GnmTest.h"

static NSString *
cell (GnmSheet *s, int col, int row)
{
    return [s displayTextOfCellAtColumn:col row:row] ?: @"-";
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
        /* A1 price, A2 units, B1 revenue */
        GNM_ASSERT ([s setText:@"10" atColumn:0 row:0 autocorrect:NO error:&error], @"A1: %@", error);
        GNM_ASSERT ([s setText:@"5" atColumn:0 row:1 autocorrect:NO error:&error], @"A2: %@", error);
        GNM_ASSERT ([s setText:@"=A1*A2" atColumn:1 row:0 autocorrect:NO error:&error], @"B1: %@", error);
        GNM_ASSERT (s.scenarios.count == 0, @"none to start");

        /* the Add dialog's refusals */
        GNM_ASSERT (![s addScenarioNamed:@"x" comment:@"" changingCells:@"nonsense!" error:&error] && [error.localizedDescription containsString:@"Invalid changing cells"], @"bad cells: %@", error);
        GNM_ASSERT (![s addScenarioNamed:@"  " comment:@"" changingCells:@"A1:A2" error:&error] && [error.localizedDescription containsString:@"Invalid scenario name"], @"blank name: %@", error);
        GNM_ASSERT ([s addScenarioNamed:@"Base" comment:@"as now" changingCells:@"A1:A2" error:&error], @"add: %@", error);
        GNM_ASSERT (![s addScenarioNamed:@"Base" comment:@"" changingCells:@"A1" error:&error] && [error.localizedDescription containsString:@"already used"], @"duplicate: %@", error);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Add scenario");
        GNM_ASSERT (s.scenarios.count == 1 && [s.scenarios.firstObject.name isEqualToString:@"Base"], @"listed: %@", s.scenarios);
        GnmSheetScenario *base = s.scenarios.firstObject;
        NSLog (@"scenarios: base cells '%@' values %@ comment '%@'", base.changingCellsText, base.valueDescriptions, base.comment);
        GNM_ASSERT ([base.changingCellsText containsString:@"A1:A2"] || [base.changingCellsText containsString:@"$A$1:$A$2"], @"cells text: %@", base.changingCellsText);
        BOOL valuesSaved = base.valueDescriptions.count == 2 && [base.valueDescriptions.firstObject isEqualToString:@"A1 = 10"];
        GNM_ASSERT (valuesSaved, @"values saved: %@", base.valueDescriptions);
        GNM_ASSERT_EQ_STR (base.comment, @"as now");
        [wb undo];
        GNM_ASSERT (s.scenarios.count == 0, @"add undone");
        [wb redo];
        GNM_ASSERT (s.scenarios.count == 1, @"add redone");
        /* a second scenario with other values */
        GNM_ASSERT ([s setText:@"12" atColumn:0 row:0 autocorrect:NO error:&error] && [s setText:@"8" atColumn:0 row:1 autocorrect:NO error:&error], @"new values: %@", error);
        GNM_ASSERT ([s addScenarioNamed:@"High" comment:@"" changingCells:@"A1:A2" error:&error], @"add high: %@", error);
        GNM_ASSERT ([s setText:@"10" atColumn:0 row:0 autocorrect:NO error:&error] && [s setText:@"5" atColumn:0 row:1 autocorrect:NO error:&error], @"back: %@", error);
        GNM_ASSERT_EQ_STR (cell (s, 1, 0), @"50");

        /* the manager: show applies, cancel restores */
        GnmScenarioManager *manager = [s scenarioManager];
        GNM_ASSERT (manager.scenarios.count == 2 && manager.shownScenario == nil, @"two listed");
        GnmSheetScenario *high = manager.scenarios[1];
        GNM_ASSERT ([manager showScenario:high error:&error] && manager.shownScenario == high, @"show: %@", error);
        GNM_ASSERT_EQ_STR (cell (s, 0, 0), @"12");
        GNM_ASSERT_EQ_STR (cell (s, 1, 0), @"96");
        GNM_ASSERT ([manager showScenario:manager.scenarios[0] error:&error], @"show base: %@", error);
        GNM_ASSERT_EQ_STR (cell (s, 1, 0), @"50");
        GNM_ASSERT ([manager showScenario:high error:&error], @"show high again: %@", error);
        [manager cancel];
        GNM_ASSERT_EQ_STR (cell (s, 0, 0), @"10");
        GNM_ASSERT_EQ_STR (cell (s, 1, 0), @"50");
        GNM_ASSERT (manager.shownScenario == nil, @"nothing shown after cancel");
        /* finish: the shown scenario becomes the undoable command */
        manager = [s scenarioManager];
        GNM_ASSERT ([manager showScenario:manager.scenarios[1] error:&error], @"show: %@", error);
        GNM_ASSERT ([manager finishWithError:&error], @"finish: %@", error);
        GNM_ASSERT_EQ_STR (cell (s, 1, 0), @"96");
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Scenario Show");
        [wb undo];
        GNM_ASSERT_EQ_STR (cell (s, 1, 0), @"50");
        [wb redo];
        GNM_ASSERT_EQ_STR (cell (s, 1, 0), @"96");
        [wb undo];
        GNM_ASSERT_EQ_STR (cell (s, 0, 0), @"10");

        /* the summary report on a new sheet, with a result cell */
        manager = [s scenarioManager];
        NSUInteger sheetsBefore = wb.sheets.count;
        GNM_ASSERT ([manager createSummaryWithResultCells:@"B9999999" error:&error] == nil && [error.localizedDescription containsString:@"valid cell names"], @"bad results: %@", error);
        GnmSheet *report = [manager createSummaryWithResultCells:@"B1" error:&error];
        GNM_ASSERT (report != nil && wb.sheets.count == sheetsBefore + 1, @"summary sheet: %@", error);
        NSLog (@"scenarios: summary sheet '%@': %@ | %@ | %@ | %@ / %@ | %@ | %@ | %@ / %@ | %@ | %@ | %@ / %@ | %@ | %@ | %@", report.name,
               cell (report, 0, 0), cell (report, 1, 1), cell (report, 2, 1), cell (report, 3, 1),
               cell (report, 0, 3), cell (report, 1, 3), cell (report, 2, 3), cell (report, 3, 3),
               cell (report, 0, 4), cell (report, 1, 4), cell (report, 2, 4), cell (report, 3, 4),
               cell (report, 0, 6), cell (report, 1, 6), cell (report, 2, 6), cell (report, 3, 6));
        GNM_ASSERT_EQ_STR (cell (report, 0, 0), @"Scenario Summary");
        GNM_ASSERT_EQ_STR (cell (report, 2, 1), @"Base");
        GNM_ASSERT_EQ_STR (cell (report, 3, 1), @"High");
        GNM_ASSERT_EQ_STR (cell (report, 0, 3), @"A1");
        GNM_ASSERT_EQ_STR (cell (report, 1, 3), @"10");
        GNM_ASSERT_EQ_STR (cell (report, 2, 3), @"10");
        GNM_ASSERT_EQ_STR (cell (report, 3, 3), @"12");
        GNM_ASSERT_EQ_STR (cell (report, 0, 5), @"Result Cells:");
        GNM_ASSERT_EQ_STR (cell (report, 0, 6), @"B1");
        GNM_ASSERT_EQ_STR (cell (report, 1, 6), @"50");
        GNM_ASSERT_EQ_STR (cell (report, 2, 6), @"50");
        GNM_ASSERT_EQ_STR (cell (report, 3, 6), @"96");
        GNM_ASSERT_EQ_STR (cell (s, 1, 0), @"50");
        [manager cancel];
        GNM_ASSERT (wb.sheets.count == sheetsBefore, @"cancel removed the report sheet");
        /* delete marks, finish removes */
        manager = [s scenarioManager];
        [manager deleteScenario:manager.scenarios[0]];
        GNM_ASSERT (manager.scenarios.count == 1 && s.scenarios.count == 2, @"marked, not yet gone");
        [manager cancel];
        GNM_ASSERT (s.scenarios.count == 2, @"cancel unmarked");
        manager = [s scenarioManager];
        [manager deleteScenario:manager.scenarios[0]];
        GNM_ASSERT ([manager finishWithError:&error] && s.scenarios.count == 1 && [s.scenarios.firstObject.name isEqualToString:@"High"], @"deleted: %@", s.scenarios);

        /* the simulation tool: a random input, an output, two rounds */
        GNM_ASSERT ([s setText:@"=RAND()" atColumn:3 row:0 autocorrect:NO error:&error], @"D1: %@", error);
        GNM_ASSERT ([s setText:@"=10*RAND()" atColumn:3 row:1 autocorrect:NO error:&error], @"D2: %@", error);
        GNM_ASSERT ([s setText:@"=D1+D2" atColumn:4 row:0 autocorrect:NO error:&error], @"E1: %@", error);
        sheetsBefore = wb.sheets.count;
        GNM_ASSERT ([s runSimulationWithInputs:@"D1:D2" outputs:@"E1" iterations:10 firstRound:2 lastRound:1 maximumSeconds:60 output:[GnmAnalysisOutput onNewSheet] error:&error] == nil
                    && [error.localizedDescription containsString:@"First round"], @"rounds out of order: %@", error);
        GNM_ASSERT ([s runSimulationWithInputs:@"" outputs:@"E1" iterations:10 firstRound:1 lastRound:1 maximumSeconds:60 output:[GnmAnalysisOutput onNewSheet] error:&error] == nil
                    && [error.localizedDescription containsString:@"Invalid variable range"], @"no inputs: %@", error);
        GnmSimulationResult *result = [s runSimulationWithInputs:@"D1:D2" outputs:@"E1" iterations:200 firstRound:1 lastRound:2 maximumSeconds:60
                                                          output:[GnmAnalysisOutput onNewSheet] error:&error];
        GNM_ASSERT (result != nil, @"simulation: %@", error);
        NSLog (@"scenarios: simulation log %@\n%@", result.logLines, [result textForRound:1]);
        GNM_ASSERT (result.firstRound == 1 && result.lastRound == 2 && result.iterations == 200 && result.inputCount == 2 && result.outputCount == 1, @"the run's shape");
        NSArray<GnmSimulationStatistics *> *stats = [result statisticsForRound:2];
        GNM_ASSERT (stats.count == 3 && [stats[0].variableName isEqualToString:@"E1"] && [stats[1].variableName hasPrefix:@"(Input)"], @"outputs first: %@", [stats valueForKey:@"variableName"]);
        GNM_ASSERT (stats[0].minimum >= 0 && stats[0].maximum <= 11 && stats[0].mean > 2 && stats[0].mean < 9 && stats[0].minimum < stats[0].mean, @"E1 stats %g %g %g", stats[0].minimum, stats[0].mean, stats[0].maximum);
        GNM_ASSERT (stats[1].maximum <= 1 && stats[2].maximum <= 10, @"input stats %g %g", stats[1].maximum, stats[2].maximum);
        GNM_ASSERT ([result statisticsForRound:3].count == 0, @"no round 3");
        GNM_ASSERT (result.logLines.count == 6 && [result.logLines[0] isEqualToString:@"Simulations: 2"], @"log: %@", result.logLines);
        GNM_ASSERT (wb.sheets.count == sheetsBefore + 1, @"the report sheet");
        GnmSheet *simReport = wb.sheets.lastObject;
        NSLog (@"scenarios: report '%@' A1='%@' A6='%@' B8='%@' C7='%@'", simReport.name, cell (simReport, 0, 0), cell (simReport, 0, 5), cell (simReport, 1, 7), cell (simReport, 2, 6));
        GNM_ASSERT ([cell (simReport, 0, 5) isEqualToString:@"SUMMARY"] || [cell (simReport, 0, 5) containsString:@"SUMMARY"], @"the report's summary heading: '%@'", cell (simReport, 0, 5));
        GNM_ASSERT_EQ_STR (cell (simReport, 2, 6), @"Min");
        [wb selectSheet:s];

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("scenarios");
    }
}
