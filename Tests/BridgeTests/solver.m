// The Solver: the algorithms the plugins register, settings on a sheet
// (defaults, round trip, the parameter command and its undo, the
// engine's refusals), a small linear program solved by Gnumeric's own
// solver with its program report, undo and redo, and an infeasible one.
#import "GnmTest.h"
#include <glib.h>

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
        NSArray<GnmSolverAlgorithm *> *algorithms = engine.solverAlgorithms;
        NSMutableArray *names = [NSMutableArray array];
        GnmSolverAlgorithm *nlsolve = nil;
        for (GnmSolverAlgorithm *a in algorithms) {
            [names addObject:[NSString stringWithFormat:@"%@ (%@, model %ld, %@)", a.identifier, a.name, (long) a.model, a.isFunctional ? @"functional" : @"missing"]];
            if ([a.identifier isEqualToString:@"nlsolve"])
                nlsolve = a;
        }
        NSLog (@"solver: algorithms %@", [names componentsJoinedByString:@"; "]);
        GNM_ASSERT (nlsolve && nlsolve.isFunctional && nlsolve.model == GnmSolverModelNonlinear, @"Gnumeric's own solver is there");

        GnmWorkbook *wb = [engine newWorkbookWithSheetCount:1];
        GnmSheet *s = wb.sheets.firstObject;
        /* maximize 3x + 2y with x + y <= 4, x <= 3, x, y >= 0: x = 3, y = 1, 11 */
        GNM_ASSERT ([s setText:@"1" atColumn:0 row:0 autocorrect:NO error:&error], @"x: %@", error);
        GNM_ASSERT ([s setText:@"1" atColumn:0 row:1 autocorrect:NO error:&error], @"y: %@", error);
        GNM_ASSERT ([s setText:@"=3*A1+2*A2" atColumn:1 row:0 autocorrect:NO error:&error], @"objective: %@", error);
        GNM_ASSERT ([s setText:@"=A1+A2" atColumn:2 row:0 autocorrect:NO error:&error], @"sum: %@", error);

        /* the defaults */
        GnmSolverSettings *defaults = s.solverSettings;
        NSLog (@"solver: defaults target '%@' input '%@' goal %ld model %ld iter %ld time %ld nonneg %d algorithm %@", defaults.targetCell, defaults.inputCells,
               (long) defaults.goal, (long) defaults.model, (long) defaults.maxIterations, (long) defaults.maxTimeSeconds, defaults.assumesNonNegative,
               defaults.algorithmIdentifier);
        GNM_ASSERT (defaults.rules.count == 0 && defaults.maxTimeSeconds > 0, @"fresh defaults");
        GNM_ASSERT ([[[GnmSolverSettings alloc] init].inputCells isEqualToString:@""], @"a fresh settings object");

        /* the refusals before anything is recorded */
        GnmSolverSettings *settings = [[GnmSolverSettings alloc] init];
        settings.targetCell = @"nowhere";
        settings.inputCells = @"A1:A2";
        error = nil;
        NSString *before = wb.undoLabel;
        GNM_ASSERT (![s setSolverSettings:settings error:&error] && [error.localizedDescription containsString:@"target"], @"bad target: %@", error);
        GNM_ASSERT ([wb.undoLabel isEqualToString:before], @"nothing recorded: %@", wb.undoLabel);
        settings.targetCell = @"A1";
        error = nil;
        GNM_ASSERT (![s setSolverSettings:settings error:&error] && [error.localizedDescription containsString:@"formula"], @"a constant target: %@", error);
        settings.targetCell = @"B1";
        settings.inputCells = @"";
        error = nil;
        GNM_ASSERT (![s setSolverSettings:settings error:&error] && [error.localizedDescription containsString:@"input"], @"no input: %@", error);

        /* the settings recorded, read back, undone */
        settings.inputCells = @"A1:A2";
        settings.goal = GnmSolverGoalMaximize;
        settings.model = GnmSolverModelNonlinear;
        settings.algorithmIdentifier = @"nlsolve";
        settings.assumesNonNegative = YES;
        settings.maxTimeSeconds = 30;
        settings.rules = @[[[GnmSolverRule alloc] initWithKind:GnmSolverRuleLessOrEqual leftSide:@"C1" rightSide:@"4"],
                           [[GnmSolverRule alloc] initWithKind:GnmSolverRuleLessOrEqual leftSide:@"A1" rightSide:@"3"]];
        GNM_ASSERT_EQ_STR ([s descriptionOfSolverRule:settings.rules[0]] ?: @"nil", @"$C$1 ≤ 4");
        GNM_ASSERT ([s descriptionOfSolverRule:[[GnmSolverRule alloc] initWithKind:GnmSolverRuleEqual leftSide:@"junk" rightSide:@"1"]] == nil, @"an unparsable rule");
        GNM_ASSERT ([s setSolverSettings:settings error:&error], @"set: %@", error);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Changing solver parameters");
        GnmSolverSettings *read = s.solverSettings;
        GNM_ASSERT_EQ_STR (read.targetCell, @"B1");
        GNM_ASSERT_EQ_STR (read.inputCells, @"A1:A2");
        GNM_ASSERT (read.goal == GnmSolverGoalMaximize && read.model == GnmSolverModelNonlinear && read.assumesNonNegative && read.maxTimeSeconds == 30, @"read back: %@ %ld", read.algorithmIdentifier, (long) read.maxTimeSeconds);
        GNM_ASSERT_EQ_STR (read.algorithmIdentifier ?: @"nil", @"nlsolve");
        GNM_ASSERT (read.rules.count == 2 && read.rules[1].kind == GnmSolverRuleLessOrEqual && [read.rules[1].rightSide isEqualToString:@"3"],
                    @"rules back: %@", read.rules);
        GNM_ASSERT_EQ_STR (read.rules[0].leftSide, @"$C$1");
        GNM_ASSERT_EQ_STR (read.rules[0].rightSide, @"4");
        [wb undo];
        GNM_ASSERT (s.solverSettings.rules.count == 0, @"undone");
        [wb redo];
        GNM_ASSERT (s.solverSettings.rules.count == 2, @"redone");
        GNM_ASSERT ([s setSolverSettings:settings error:&error] && [wb.undoLabel isEqualToString:@"Changing solver parameters"], @"the same again records nothing new");

        /* solved, with the program report */
        settings.programReport = YES;
        GNM_ASSERT ([s setSolverSettings:settings error:&error], @"report on: %@", error);
        GnmSolverSettings *live = s.solverSettings;
        NSLog (@"solver: before the run: target '%@' input '%@' rules %@ / %@", live.targetCell, live.inputCells,
               [s descriptionOfSolverRule:live.rules[0]], [s descriptionOfSolverRule:live.rules[1]]);
        GnmSolverOutcome *outcome = [s runSolverWithError:&error];
        GNM_ASSERT (outcome != nil, @"run: %@", error);
        NSLog (@"solver: status %@ quality %ld solution %d objective %g elapsed %.2fs reason %@; A1=%@ A2=%@ B1=%@; sheets %lu", outcome.status, (long) outcome.quality,
               outcome.hasSolution, outcome.objectiveValue, outcome.elapsedSeconds, outcome.reason, cell (s, 0, 0), cell (s, 0, 1), cell (s, 1, 0),
               (unsigned long) wb.sheets.count);
        GNM_ASSERT (outcome.hasSolution && (outcome.quality == GnmSolverQualityOptimal || outcome.quality == GnmSolverQualityFeasible), @"solved: %@", outcome.status);
        /* Gnumeric's own solver is a local non-linear method: it reaches a
         * feasible point that beats the start, not always the LP corner */
        double x = number (s, 0, 0), y = number (s, 0, 1);
        GNM_ASSERT (x >= -1e-6 && y >= -1e-6 && x <= 3 + 1e-6 && x + y <= 4 + 1e-6, @"within the constraints: %g %g", x, y);
        GNM_ASSERT (number (s, 1, 0) > 5 + 1e-6 && fabs (outcome.objectiveValue - number (s, 1, 0)) < 1e-9, @"an improvement: %@ vs %g", cell (s, 1, 0), outcome.objectiveValue);
        double solvedX = x;
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Running solver");
        GNM_ASSERT (wb.sheets.count == 2 && [wb.sheets[1].name containsString:@"Program Report"], @"the report sheet: %@", wb.sheets.lastObject.name);
        [wb undo];
        GNM_ASSERT (number (s, 0, 0) == 1 && number (s, 0, 1) == 1 && wb.sheets.count == 1, @"undo restores the cells and removes the report");
        [wb redo];
        GNM_ASSERT (fabs (number (s, 0, 0) - solvedX) < 1e-9 && wb.sheets.count == 2, @"redo");
        [wb undo];

        /* an infeasible one is reported, not stored */
        settings.programReport = NO;
        settings.rules = @[[[GnmSolverRule alloc] initWithKind:GnmSolverRuleGreaterOrEqual leftSide:@"C1" rightSide:@"10"],
                           [[GnmSolverRule alloc] initWithKind:GnmSolverRuleLessOrEqual leftSide:@"A1" rightSide:@"3"],
                           [[GnmSolverRule alloc] initWithKind:GnmSolverRuleLessOrEqual leftSide:@"A2" rightSide:@"3"]];
        GNM_ASSERT ([s setSolverSettings:settings error:&error], @"infeasible settings: %@", error);
        live = s.solverSettings;
        NSLog (@"solver: before the infeasible run: target '%@' input '%@' rules %lu", live.targetCell, live.inputCells, (unsigned long) live.rules.count);
        error = nil;
        outcome = [s runSolverWithError:&error];
        NSLog (@"solver: infeasible run: %@ status %@ quality %ld solution %d reason %@", error, outcome.status, (long) outcome.quality, outcome.hasSolution, outcome.reason);
        GNM_ASSERT (outcome == nil || !outcome.hasSolution, @"no solution stored");
        GNM_ASSERT (number (s, 0, 0) == 1, @"x untouched: %@", cell (s, 0, 0));

        /* a run started, stopped at once, and finished (the dialog's Stop) */
        [wb undo];
        GNM_ASSERT ([s setText:@"1" atColumn:0 row:0 autocorrect:NO error:&error] && [s setText:@"1" atColumn:0 row:1 autocorrect:NO error:&error], @"reset: %@", error);
        settings = [s solverSettings];
        settings.rules = @[[[GnmSolverRule alloc] initWithKind:GnmSolverRuleLessOrEqual leftSide:@"A1" rightSide:@"3"],
                           [[GnmSolverRule alloc] initWithKind:GnmSolverRuleLessOrEqual leftSide:@"A1:A2" rightSide:@"4"]];
        GNM_ASSERT ([s setSolverSettings:settings error:&error], @"stop settings: %@", error);
        error = nil;
        GnmSolverRun *run = [s startSolverWithError:&error];
        GNM_ASSERT (run != nil, @"start: %@", error);
        NSLog (@"solver: started: status '%@' finished %d objective %@", run.status, run.isFinished, run.objectiveValue);
        GNM_ASSERT ([run finish] == nil, @"nothing to finish before the end");
        GNM_ASSERT ([run stop], @"stop");
        for (int i = 0; i < 200 && !run.isFinished; i++) {
            g_main_context_iteration (NULL, FALSE);
            [run checkTimeout];
        }
        NSLog (@"solver: stopped: status '%@' finished %d elapsed %.3f", run.status, run.isFinished, run.elapsedSeconds);
        GNM_ASSERT (run.isFinished, @"the solver stopped");
        outcome = [run finish];
        GNM_ASSERT (outcome != nil && [run finish] == nil, @"finished once: %@", outcome);
        NSLog (@"solver: stopped outcome: status %@ quality %ld solution %d; A1=%@", outcome.status, (long) outcome.quality, outcome.hasSolution, cell (s, 0, 0));
        GNM_ASSERT ([outcome.status hasPrefix:@"Cancelled"] || !outcome.hasSolution || number (s, 0, 0) >= 1, @"a stop keeps the cells or stores a solution");

        /* no algorithm */
        settings.algorithmIdentifier = nil;
        GNM_ASSERT ([s setSolverSettings:settings error:&error], @"no algorithm settings: %@", error);
        error = nil;
        GNM_ASSERT ([s runSolverWithError:&error] == nil && error, @"refused without an algorithm: %@", error);

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("solver");
    }
}
