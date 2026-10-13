// Scenarios and the simulation tool, as dialog-scenarios.c and
// dialog-simulation.c drive the engine.
#import "GnmPrivate.h"
#include <tools/scenarios.h>
#include <tools/simulation.h>
#include <tools/dao.h>
#include <commands.h>
#include <cell.h>
#include <value.h>
#include <expr.h>
#include <ranges.h>
#include <parse-util.h>
#include <workbook.h>
#include <workbook-control.h>
#include <workbook-view.h>
#include <goffice/goffice.h>

#define LIGHT_GRAY GO_COLOR_GREY(0xdd)
#define DARK_GRAY  GO_COLOR_GREY(0x33)

@interface GnmSheetScenario ()
- (instancetype)initWithScenario:(struct GnmScenario_ *)scenario NS_DESIGNATED_INITIALIZER;
@property (nonatomic, readonly) struct GnmScenario_ *engineScenario;
@end

@interface GnmScenarioManager ()
- (instancetype)initWithSheet:(GnmSheet *)sheet NS_DESIGNATED_INITIALIZER;
@end

@implementation GnmSheetScenario {
    struct GnmScenario_ *_scenario;
}

/* The sheet owns its scenarios and they go with it (their items are
 * dependents of the sheet), so the wrapper only watches its scenario. */
- (instancetype)initWithScenario:(struct GnmScenario_ *)scenario
{
    if (!(self = [super init]))
        return nil;
    _scenario = scenario;
    g_object_add_weak_pointer (G_OBJECT (scenario), (gpointer *) &_scenario);
    return self;
}

- (void)dealloc
{
    if (_scenario)
        g_object_remove_weak_pointer (G_OBJECT (_scenario), (gpointer *) &_scenario);
}

- (struct GnmScenario_ *)engineScenario { return _scenario; }
- (NSString *)name { return _scenario ? GnmString (_scenario->name) : @""; }
- (NSString *)comment { return _scenario ? GnmString (_scenario->comment) : @""; }

- (NSString *)changingCellsText
{
    if (!_scenario)
        return @"";
    char *text = gnm_scenario_get_range_str (_scenario);
    NSString *result = GnmString (text);
    g_free (text);
    return result;
}

- (NSArray<NSString *> *)valueDescriptions
{
    NSMutableArray *result = [NSMutableArray array];
    for (GSList *l = _scenario ? _scenario->items : NULL; l; l = l->next) {
        GnmScenarioItem *item = l->data;
        GnmSheetRange sr;
        if (!item->value || !gnm_scenario_item_valid (item, &sr))
            continue;
        char *text = value_get_as_string (item->value);
        [result addObject:[NSString stringWithFormat:@"%s = %s", cell_coord_name (sr.range.start.col, sr.range.start.row), text]];
        g_free (text);
    }
    return result;
}

- (BOOL)isEqual:(id)other
{
    return [other isKindOfClass:GnmSheetScenario.class] && _scenario && ((GnmSheetScenario *) other)->_scenario == _scenario;
}

- (NSUInteger)hash { return (NSUInteger) _scenario; }

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@ [%@]>", self.class, self.name, self.changingCellsText];
}

@end

/* One range from a dialog entry (gnm_expr_entry_parse_as_value). */
static GnmValue *
scenario_range (Sheet *sheet, NSString *text)
{
    if (text.length == 0)
        return NULL;
    GnmParsePos pp;
    parse_pos_init_sheet (&pp, sheet);
    GnmValue *v = value_new_cellrange_parsepos_str (&pp, text.UTF8String,
                                                    GNM_EXPR_PARSE_UNKNOWN_NAMES_ARE_STRINGS | GNM_EXPR_PARSE_FORCE_ABSOLUTE_REFERENCES);
    if (v && !VALUE_IS_CELLRANGE (v)) {
        value_release (v);
        return NULL;
    }
    return v;
}

static NSError *
scenario_error (GnmEngine *engine, NSString *message)
{
    return [engine _errorWithCode:GnmErrorCommandFailed description:message collected:@[]];
}

@implementation GnmSheet (Scenarios)

- (NSArray<GnmSheetScenario *> *)scenarios
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    NSMutableArray *result = [NSMutableArray array];
    Sheet *sheet = self.engineSheet;
    for (GList *l = sheet ? sheet->scenarios : NULL; l; l = l->next)
        [result addObject:[[GnmSheetScenario alloc] initWithScenario:l->data]];
    return result;
}

- (BOOL)addScenarioNamed:(NSString *)name comment:(NSString *)comment changingCells:(NSString *)cells error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    if (!sheet || !workbook)
        return NO;
    /* scenario_add_ok_clicked_cb */
    GnmValue *range = scenario_range (sheet, cells);
    GnmSheetRange sr;
    if (!range || !gnm_sheet_range_from_value (&sr, range)) {
        if (range)
            value_release (range);
        if (error)
            *error = scenario_error (workbook.engine, @"Invalid changing cells");
        return NO;
    }
    value_release (range);
    if (sr.sheet && sr.sheet != sheet) {
        if (error)
            *error = scenario_error (workbook.engine, @"Changing cells should be on the current sheet only.");
        return NO;
    }
    if (gnm_sheet_scenario_find (sheet, name.UTF8String)) {
        if (error)
            *error = scenario_error (workbook.engine, @"Scenario name already used");
        return NO;
    }
    if ([name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) {
        if (error)
            *error = scenario_error (workbook.engine, @"Invalid scenario name");
        return NO;
    }
    return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        GnmScenario *sc = gnm_sheet_scenario_new (sheet, name.UTF8String);
        if (comment.length)
            gnm_scenario_set_comment (sc, comment.UTF8String);
        gnm_scenario_add_area (sc, &sr);
        return cmd_scenario_add (wbc, sc, sheet);
    } description:@"Could not add the scenario." error:error];
}

- (GnmScenarioManager *)scenarioManager
{
    return [[GnmScenarioManager alloc] initWithSheet:self];
}

@end

#pragma mark - The manager's session

@implementation GnmScenarioManager {
    GnmSheet *_sheet;
    GnmSheetScenario *_current;
    GOUndo *_undo;
    NSMutableArray<GnmSheetScenario *> *_marked;
    NSMutableArray<GnmSheet *> *_reportSheets;
}

- (instancetype)initWithSheet:(GnmSheet *)sheet
{
    if (!(self = [super init]))
        return nil;
    _sheet = sheet;
    _marked = [NSMutableArray array];
    _reportSheets = [NSMutableArray array];
    return self;
}

- (void)dealloc
{
    if (_undo)
        g_object_unref (_undo);
}

- (GnmSheet *)sheet { return _sheet; }
- (GnmSheetScenario *)shownScenario { return _current; }

- (NSArray<GnmSheetScenario *> *)scenarios
{
    NSMutableArray *result = [NSMutableArray array];
    for (GnmSheetScenario *sc in _sheet.scenarios)
        if (![_marked containsObject:sc])
            [result addObject:sc];
    return result;
}

/* restore_old_values */
- (void)restore
{
    if (!_undo)
        return;
    WorkbookControl *wbc = _sheet.workbook.control;
    go_undo_undo_with_data (_undo, wbc ? GO_CMD_CONTEXT (wbc) : NULL);
    g_object_unref (_undo);
    _undo = NULL;
    _current = nil;
    if (_sheet.engineSheet)
        workbook_recalc (_sheet.engineSheet->workbook);
}

- (BOOL)showScenario:(GnmSheetScenario *)scenario error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    if (![_sheet.scenarios containsObject:scenario] || [_marked containsObject:scenario]) {
        if (error)
            *error = scenario_error (_sheet.workbook.engine, @"The scenario is gone.");
        return NO;
    }
    [self restore];
    if (!scenario.engineScenario)
        return NO;
    _current = scenario;
    _undo = gnm_scenario_apply (scenario.engineScenario);
    workbook_recalc (_sheet.engineSheet->workbook);   /* the GTK's idle recalc */
    return YES;
}

- (void)deleteScenario:(GnmSheetScenario *)scenario
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    [self restore];
    if (![_marked containsObject:scenario])
        [_marked addObject:scenario];
}

/* The report scenario_summary lays out, with the per-cell parts the GTK
 * left as stubs filled in: each changing cell's current value and its
 * value in every scenario, then the result cells' values under every
 * scenario (applied, recalculated, read, restored). */
- (GnmSheet *)createSummaryWithResultCells:(NSString *)results error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    [self restore];
    Sheet *sheet = _sheet.engineSheet;
    GnmWorkbook *workbook = _sheet.workbook;
    WorkbookControl *wbc = workbook.control;
    if (!sheet || !wbc)
        return nil;
    NSMutableArray<NSValue *> *resultCells = [NSMutableArray array];   /* GnmCellPos */
    NSString *trimmed = [results stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    for (NSString *part in trimmed.length ? [trimmed componentsSeparatedByString:@","] : @[]) {
        GnmValue *v = scenario_range (sheet, [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]);
        GnmSheetRange sr;
        if (!v || !gnm_sheet_range_from_value (&sr, v) || (sr.sheet && sr.sheet != sheet)) {
            if (v)
                value_release (v);
            if (error)
                *error = scenario_error (workbook.engine, @"Results entry did not contain valid cell names.");
            return nil;
        }
        value_release (v);
        for (int col = sr.range.start.col; col <= sr.range.end.col; col++)
            for (int row = sr.range.start.row; row <= sr.range.end.row; row++) {
                GnmCellPos pos = { col, row };
                [resultCells addObject:[NSValue valueWithBytes:&pos objCType:@encode (GnmCellPos)]];
            }
    }
    NSArray<GnmSheetScenario *> *scenarios = self.scenarios;
    data_analysis_output_t *dao = dao_init_new_sheet (sheet);
    dao_prepare_output (wbc, dao, "Scenario Summary");
    dao_set_cell (dao, 1, 1, "Current Values");
    dao_set_cell (dao, 0, 2, "Changing Cells:");
    NSMutableDictionary<NSString *, NSNumber *> *rows = [NSMutableDictionary dictionary];
    int row = 0, col = 0;
    for (GnmSheetScenario *sc in scenarios) {
        dao_set_cell (dao, 2 + col, 1, sc.name.UTF8String);
        for (GSList *l = sc.engineScenario ? sc.engineScenario->items : NULL; l; l = l->next) {
            GnmScenarioItem *item = l->data;
            GnmSheetRange sr;
            if (!item->value || !gnm_scenario_item_valid (item, &sr))
                continue;
            char *name = dao_find_name (sheet, sr.range.start.col, sr.range.start.row);
            NSString *key = GnmString (name);
            NSNumber *known = rows[key];
            int r;
            if (known) {
                r = known.intValue;
            } else {
                r = row++;
                rows[key] = @(r);
                dao_set_cell (dao, 0, 3 + r, name);
                GnmCell *cell = sheet_cell_get (sheet, sr.range.start.col, sr.range.start.row);
                if (cell && cell->value)
                    dao_set_cell_value (dao, 1, 3 + r, value_dup (cell->value));
            }
            g_free (name);
            dao_set_cell_value (dao, 2 + col, 3 + r, value_dup (item->value));
            dao_set_colors (dao, 2 + col, 3 + r, 2 + col, 3 + r, gnm_color_new_go (GO_COLOR_BLACK), gnm_color_new_go (LIGHT_GRAY));
        }
        col++;
    }
    dao_set_align (dao, 0, 3, 0, 2 + row, GNM_HALIGN_RIGHT, GNM_VALIGN_BOTTOM);
    int resultsRow = 3 + row;
    if (resultCells.count) {
        dao_set_cell (dao, 0, resultsRow, "Result Cells:");
        int r = resultsRow + 1;
        for (NSValue *boxed in resultCells) {
            GnmCellPos pos;
            [boxed getValue:&pos];
            char *name = dao_find_name (sheet, pos.col, pos.row);
            dao_set_cell (dao, 0, r, name);
            g_free (name);
            GnmCell *cell = sheet_cell_get (sheet, pos.col, pos.row);
            if (cell && cell->value)
                dao_set_cell_value (dao, 1, r, value_dup (cell->value));
            r++;
        }
        col = 0;
        for (GnmSheetScenario *sc in scenarios) {
            GOUndo *undo = sc.engineScenario ? gnm_scenario_apply (sc.engineScenario) : NULL;
            workbook_recalc (sheet->workbook);
            r = resultsRow + 1;
            for (NSValue *boxed in resultCells) {
                GnmCellPos pos;
                [boxed getValue:&pos];
                GnmCell *cell = sheet_cell_get (sheet, pos.col, pos.row);
                if (cell && cell->value)
                    dao_set_cell_value (dao, 2 + col, r, value_dup (cell->value));
                r++;
            }
            if (undo) {
                go_undo_undo_with_data (undo, GO_CMD_CONTEXT (wbc));
                g_object_unref (undo);
            }
            col++;
        }
        workbook_recalc (sheet->workbook);
        dao_set_align (dao, 0, resultsRow + 1, 0, resultsRow + (int) resultCells.count, GNM_HALIGN_RIGHT, GNM_VALIGN_BOTTOM);
        dao_set_colors (dao, 0, resultsRow, 0, resultsRow + (int) resultCells.count, gnm_color_new_go (GO_COLOR_BLACK), gnm_color_new_go (LIGHT_GRAY));
    }
    int lastRow = resultCells.count ? resultsRow + (int) resultCells.count : 2 + row;
    dao_set_bold (dao, 0, 0, 0, lastRow);
    dao_autofit_columns (dao);
    dao_set_cell (dao, 0, 0, "Scenario Summary");
    dao_set_colors (dao, 0, 0, (int) scenarios.count + 1, 1, gnm_color_new_go (GO_COLOR_WHITE), gnm_color_new_go (DARK_GRAY));
    dao_set_colors (dao, 0, 2, 0, 2 + row, gnm_color_new_go (GO_COLOR_BLACK), gnm_color_new_go (LIGHT_GRAY));
    dao_set_align (dao, 1, 1, (int) scenarios.count + 1, 1, GNM_HALIGN_RIGHT, GNM_VALIGN_BOTTOM);
    Sheet *report = dao->dst_sheet;
    dao_free (dao);
    GnmSheet *wrapper = report ? [workbook wrapperForEngineSheet:report] : nil;
    if (wrapper)
        [_reportSheets addObject:wrapper];
    return wrapper;
}

- (BOOL)finishWithError:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GnmWorkbook *workbook = _sheet.workbook;
    Sheet *sheet = _sheet.engineSheet;
    if (!workbook || !sheet)
        return NO;
    BOOL ok = YES;
    if (_current && _undo && _current.engineScenario) {
        GnmSheetScenario *shown = _current;
        GOUndo *undo = _undo;
        ok = [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
            return cmd_scenario_mngr (wbc, shown.engineScenario, undo);
        } description:@"Could not show the scenario." error:error];
        g_object_unref (_undo);   /* the command took its own reference */
        _undo = NULL;
        _current = nil;
    }
    /* scenario_manager_ok */
    for (GnmSheetScenario *sc in _marked)
        if (sc.engineScenario && g_list_find (sheet->scenarios, sc.engineScenario))
            gnm_sheet_scenario_remove (sheet, sc.engineScenario);
    [_marked removeAllObjects];
    [_reportSheets removeAllObjects];
    sheet_redraw_all (sheet, TRUE);
    return ok;
}

- (void)cancel
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    [self restore];
    /* scenarios_cancel_clicked_cb: the report sheets of this session go */
    GnmWorkbook *workbook = _sheet.workbook;
    for (GnmSheet *report in _reportSheets) {
        Sheet *engineReport = report.engineSheet;
        if (!engineReport || !workbook)
            continue;
        if (workbook.currentSheet == report)
            [workbook selectSheet:_sheet];
        workbook_sheet_delete (engineReport);
    }
    [_reportSheets removeAllObjects];
    [_marked removeAllObjects];
}

@end

#pragma mark - Simulation

@interface GnmSimulationStatistics ()
- (instancetype)initWithName:(NSString *)name stats:(simstats_t *)stats index:(int)i NS_DESIGNATED_INITIALIZER;
@end

@implementation GnmSimulationStatistics

- (instancetype)initWithName:(NSString *)name stats:(simstats_t *)stats index:(int)i
{
    if (!(self = [super init]))
        return nil;
    _variableName = [name copy];
    _minimum = stats->min[i];
    _mean = stats->mean[i];
    _maximum = stats->max[i];
    _median = stats->median[i];
    _mode = stats->mode[i];
    _standardDeviation = stats->stddev[i];
    _variance = stats->var[i];
    _skewness = stats->skew[i];
    _kurtosis = stats->kurtosis[i];
    _range = stats->range[i];
    _confidence = stats->confidence[i];
    _lowerLimit = stats->lower[i];
    _upperLimit = stats->upper[i];
    return self;
}

@end

@interface GnmSimulationResult ()
- (instancetype)initWithSimulation:(simulation_t *)sim NS_DESIGNATED_INITIALIZER;
@end

@implementation GnmSimulationResult {
    NSArray<NSArray<GnmSimulationStatistics *> *> *_rounds;   /* index round - firstRound */
}

- (instancetype)initWithSimulation:(simulation_t *)sim
{
    if (!(self = [super init]))
        return nil;
    _firstRound = sim->first_round + 1;
    _lastRound = sim->last_round + 1;
    _iterations = sim->n_iterations;
    _inputCount = sim->n_input_vars;
    _outputCount = sim->n_output_vars;
    _runtime = (sim->end - sim->start) / 1e6;
    NSMutableArray *rounds = [NSMutableArray array];
    for (int round = sim->first_round; round <= sim->last_round; round++) {
        NSMutableArray *stats = [NSMutableArray array];
        for (int i = 0; i < sim->n_vars; i++)
            [stats addObject:[[GnmSimulationStatistics alloc] initWithName:GnmString (sim->cellnames[i]) stats:sim->stats[round] index:i]];
        [rounds addObject:stats];
    }
    _rounds = rounds;
    GString *date = g_string_new (NULL);
    dao_append_date (date);
    _logLines = @[[NSString stringWithFormat:@"Simulations: %ld", (long) (_lastRound - _firstRound + 1)],
                  [NSString stringWithFormat:@"Iterations: %ld", (long) _iterations],
                  [NSString stringWithFormat:@"# Input variables: %ld", (long) _inputCount],
                  [NSString stringWithFormat:@"# Output variables: %ld", (long) _outputCount],
                  [NSString stringWithFormat:@"Runtime: %.2f", _runtime],
                  [NSString stringWithFormat:@"Run on: %@", GnmString (date->str)]];
    g_string_free (date, TRUE);
    return self;
}

- (NSArray<GnmSimulationStatistics *> *)statisticsForRound:(NSInteger)round
{
    NSInteger index = round - _firstRound;
    return index >= 0 && index < (NSInteger) _rounds.count ? _rounds[(NSUInteger) index] : @[];
}

- (NSString *)textForRound:(NSInteger)round
{
    /* update_results_view */
    NSMutableString *text = [NSMutableString stringWithFormat:@"Simulation #%ld\n\n", (long) round];
    [text appendFormat:@"%-20s %10s %10s %10s\n", "Variable", "Min", "Average", "Max"];
    for (GnmSimulationStatistics *stats in [self statisticsForRound:round])
        [text appendFormat:@"%-20s %10g %10G %10g\n", stats.variableName.UTF8String, stats.minimum, stats.mean, stats.maximum];
    return text;
}

@end

@implementation GnmSheet (Simulation)

- (GnmSimulationResult *)runSimulationWithInputs:(NSString *)inputs outputs:(NSString *)outputs iterations:(NSInteger)iterations
                                      firstRound:(NSInteger)firstRound lastRound:(NSInteger)lastRound maximumSeconds:(NSInteger)seconds
                                          output:(GnmAnalysisOutput *)output error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    WorkbookControl *wbc = workbook.control;
    if (!sheet || !workbook || !wbc)
        return nil;
    /* simulation_ok_clicked_cb and prepare_ranges */
    simulation_t sim;
    memset (&sim, 0, sizeof sim);
    sim.inputs = scenario_range (sheet, inputs);
    sim.outputs = scenario_range (sheet, outputs);
    GnmSimulationResult *result = nil;
    NSString *failure = nil;
    if (!sim.inputs || !sim.outputs) {
        failure = @"Invalid variable range was given";
        goto out;
    }
    if (firstRound > lastRound) {
        failure = @"First round number should be less than or equal to the number of the last round.";
        goto out;
    }
    if (firstRound < 1 || iterations < 1) {
        failure = @"Invalid variable range was given";
        goto out;
    }
    sim.ref_inputs = gnm_rangeref_dup (value_get_rangeref (sim.inputs));
    sim.ref_outputs = gnm_rangeref_dup (value_get_rangeref (sim.outputs));
    sim.n_input_vars = (abs (sim.ref_inputs->a.col - sim.ref_inputs->b.col) + 1) * (abs (sim.ref_inputs->a.row - sim.ref_inputs->b.row) + 1);
    sim.n_output_vars = (abs (sim.ref_outputs->a.col - sim.ref_outputs->b.col) + 1) * (abs (sim.ref_outputs->a.row - sim.ref_outputs->b.row) + 1);
    sim.n_vars = sim.n_input_vars + sim.n_output_vars;
    {
        GnmRangeRef *refs[2] = { sim.ref_inputs, sim.ref_outputs };
        GSList *lists[2] = { NULL, NULL };
        for (int k = 0; k < 2; k++) {
            GnmRangeRef *ref = refs[k];
            Sheet *target = ref->a.sheet ? ref->a.sheet : sheet;
            for (int c = MIN (ref->a.col, ref->b.col); c <= MAX (ref->a.col, ref->b.col); c++)
                for (int r = MIN (ref->a.row, ref->b.row); r <= MAX (ref->a.row, ref->b.row); r++)
                    lists[k] = g_slist_append (lists[k], sheet_cell_fetch (target, c, r));
        }
        sim.list_inputs = lists[0];
        sim.list_outputs = lists[1];
    }
    sim.n_iterations = (int) iterations;
    sim.first_round = (int) firstRound - 1;
    sim.last_round = (int) lastRound - 1;
    sim.max_time = (int) seconds;
    {
        data_analysis_output_t *dao = [output _outputForSheet:sheet engine:workbook.engine error:error];
        if (!dao) {
            failure = nil;
            goto cleanup;
        }
        wb_view_sheet_focus (workbook.workbookView, sheet);   /* the tool reads the view's current sheet */
        sim.start = g_get_monotonic_time ();
        const char *err = simulation_tool (wbc, dao, &sim);
        sim.end = g_get_monotonic_time ();
        dao_free (dao);
        if (err)
            failure = GnmString (err);
        else
            result = [[GnmSimulationResult alloc] initWithSimulation:&sim];
        simulation_tool_destroy (&sim);
        sim.ref_inputs = NULL;
        sim.ref_outputs = NULL;
    }
cleanup:
    if (sim.ref_inputs)
        g_free (sim.ref_inputs);
    if (sim.ref_outputs)
        g_free (sim.ref_outputs);
out:
    if (sim.inputs)
        value_release (sim.inputs);
    if (sim.outputs)
        value_release (sim.outputs);
    if (failure && error)
        *error = scenario_error (workbook.engine, failure);
    return result;
}

@end
