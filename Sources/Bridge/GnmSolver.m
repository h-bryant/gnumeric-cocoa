// The Solver as dialog-solver.c drives it: extract_settings into the
// sheet's parameters with the parameter-swap undo, run_solver's start,
// wait, store, report, and command.
#import "GnmPrivate.h"
#include <tools/gnm-solver.h>

static NSError *
solver_error (GnmEngine *engine, NSString *message)
{
    return [engine _errorWithCode:GnmErrorCommandFailed description:message collected:@[]];
}

/* The dialog's entries (GNM_EE_FORCE_ABS_REF | GNM_EE_SHEET_OPTIONAL):
 * absolute references, the sheet left implicit. */
static GnmValue *
parse_range (Sheet *sheet, NSString *text)
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

/* A constraint side: a range, or for the right side a number too. */
static GnmValue *
parse_side (Sheet *sheet, NSString *text)
{
    GnmValue *v = parse_range (sheet, text);
    if (!v && text.length) {
        v = format_match_number (text.UTF8String, NULL, sheet_date_conv (sheet));
        if (v && !VALUE_IS_FLOAT (v)) {
            value_release (v);
            v = NULL;
        }
    }
    return v;
}

static NSString *
range_text (Sheet *sheet, GnmValue const *v)
{
    GnmRange r;
    if (!v || !range_init_value (&r, v))
        return @"";
    Sheet *where = v->v_range.cell.a.sheet;
    if (where && where != sheet) {
        char *name = global_range_name (where, &r);
        NSString *s = GnmString (name);
        g_free (name);
        return s;
    }
    return GnmString (range_as_string (&r));
}

static GnmSolverFactory *
factory_with_id (NSString *identifier)
{
    if (!identifier.length)
        return NULL;
    for (GSList *l = gnm_solver_db_get (); l; l = l->next) {
        GnmSolverFactory *f = l->data;
        if (f->id && strcmp (f->id, identifier.UTF8String) == 0)
            return f;
    }
    return NULL;
}

@implementation GnmSolverAlgorithm

- (instancetype)initWithFactory:(GnmSolverFactory *)factory
{
    if (!(self = [super init]))
        return nil;
    _identifier = GnmString (factory->id);
    _name = GnmString (factory->name);
    _model = (GnmSolverModel) factory->type;
    _isFunctional = gnm_solver_factory_functional (factory, NULL);
    return self;
}

@end

@implementation GnmSolverRule

- (instancetype)initWithKind:(GnmSolverRuleKind)kind leftSide:(NSString *)leftSide rightSide:(NSString *)rightSide
{
    if (!(self = [super init]))
        return nil;
    _kind = kind;
    _leftSide = [leftSide copy];
    _rightSide = [rightSide copy];
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[GnmSolverRule allocWithZone:zone] initWithKind:_kind leftSide:_leftSide rightSide:_rightSide];
}

- (BOOL)takesRightSide
{
    return _kind != GnmSolverRuleInteger && _kind != GnmSolverRuleBoolean;
}

+ (NSString *)symbolForKind:(GnmSolverRuleKind)kind
{
    switch (kind) {
    case GnmSolverRuleLessOrEqual: return @"≤";
    case GnmSolverRuleGreaterOrEqual: return @"≥";
    case GnmSolverRuleEqual: return @"=";
    case GnmSolverRuleInteger: return @"Int";
    case GnmSolverRuleBoolean: return @"Bool";
    }
    return @"";
}

- (BOOL)isEqual:(id)object
{
    if (![object isKindOfClass:GnmSolverRule.class])
        return NO;
    GnmSolverRule *other = object;
    return other.kind == _kind && [other.leftSide isEqualToString:_leftSide] && [other.rightSide isEqualToString:_rightSide];
}

- (NSUInteger)hash { return _leftSide.hash ^ _rightSide.hash ^ (NSUInteger) _kind; }

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@ %@ %@>", self.class, _leftSide, [GnmSolverRule symbolForKind:_kind], _rightSide];
}

@end

@implementation GnmSolverSettings

- (instancetype)init
{
    GnmSolverParameters *fresh = gnm_solver_param_new (NULL);
    self = [self initWithParameters:fresh sheet:NULL];
    g_object_unref (fresh);
    return self;
}

- (instancetype)initWithParameters:(GnmSolverParameters *)param sheet:(Sheet *)sheet
{
    if (!(self = [super init]))
        return nil;
    GnmCellRef const *target = gnm_solver_param_get_target (param);
    if (target) {
        NSString *name = GnmString (cell_coord_name (target->col, target->row));
        _targetCell = target->sheet && sheet && target->sheet != sheet
            ? [NSString stringWithFormat:@"%s!%@", target->sheet->name_quoted, name] : name;
    } else
        _targetCell = @"";
    _goal = (GnmSolverGoal) param->problem_type;
    _inputCells = sheet ? range_text (sheet, gnm_solver_param_get_input (param)) : @"";
    NSMutableArray *rules = [NSMutableArray array];
    for (GSList *l = param->constraints; l; l = l->next) {
        GnmSolverConstraint *c = l->data;
        GString *lhs = g_string_new (NULL), *rhs = g_string_new (NULL);
        gnm_solver_constraint_side_as_str (c, sheet, lhs, TRUE);
        if (gnm_solver_constraint_has_rhs (c))
            gnm_solver_constraint_side_as_str (c, sheet, rhs, FALSE);
        [rules addObject:[[GnmSolverRule alloc] initWithKind:(GnmSolverRuleKind) c->type leftSide:GnmString (lhs->str) rightSide:GnmString (rhs->str)]];
        g_string_free (lhs, TRUE);
        g_string_free (rhs, TRUE);
    }
    _rules = rules;
    _algorithmIdentifier = param->options.algorithm ? GnmString (param->options.algorithm->id) : nil;
    _model = (GnmSolverModel) param->options.model_type;
    _maxIterations = param->options.max_iter;
    _maxTimeSeconds = param->options.max_time_sec;
    _assumesNonNegative = param->options.assume_non_negative;
    _assumesDiscrete = param->options.assume_discrete;
    _automaticScaling = param->options.automatic_scaling;
    _gradientOrder = param->options.gradient_order;
    _programReport = param->options.program_report;
    _sensitivityReport = param->options.sensitivity_report;
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    GnmSolverSettings *copy = [[GnmSolverSettings allocWithZone:zone] init];
    copy.targetCell = _targetCell;
    copy.goal = _goal;
    copy.inputCells = _inputCells;
    copy.rules = _rules;
    copy.algorithmIdentifier = _algorithmIdentifier;
    copy.model = _model;
    copy.maxIterations = _maxIterations;
    copy.maxTimeSeconds = _maxTimeSeconds;
    copy.assumesNonNegative = _assumesNonNegative;
    copy.assumesDiscrete = _assumesDiscrete;
    copy.automaticScaling = _automaticScaling;
    copy.gradientOrder = _gradientOrder;
    copy.programReport = _programReport;
    copy.sensitivityReport = _sensitivityReport;
    return copy;
}

/* extract_settings */
- (void)_fillParameters:(GnmSolverParameters *)param sheet:(Sheet *)sheet
{
    GnmValue *target = parse_range (sheet, _targetCell);
    gnm_solver_param_set_target (param, target ? &target->v_range.cell.a : NULL);
    if (target)
        value_release (target);
    gnm_solver_param_set_input (param, parse_range (sheet, _inputCells));   /* takes it */
    param->problem_type = (GnmSolverProblemType) _goal;
    param->options.model_type = (GnmSolverModelType) _model;
    gnm_solver_param_set_algorithm (param, factory_with_id (_algorithmIdentifier));
    param->options.max_iter = (unsigned) MAX (_maxIterations, 0);
    param->options.max_time_sec = (int) _maxTimeSeconds;
    param->options.gradient_order = (unsigned) MAX (_gradientOrder, 0);
    param->options.automatic_scaling = _automaticScaling;
    param->options.assume_non_negative = _assumesNonNegative;
    param->options.assume_discrete = _assumesDiscrete;
    param->options.program_report = _programReport;
    param->options.sensitivity_report = _sensitivityReport;
    g_slist_free_full (param->constraints, (GDestroyNotify) gnm_solver_constraint_free);
    param->constraints = NULL;
    for (GnmSolverRule *rule in _rules) {
        /* constraint_fill */
        GnmSolverConstraint *c = gnm_solver_constraint_new (sheet);
        c->type = (GnmSolverConstraintType) rule.kind;
        gnm_solver_constraint_set_lhs (c, parse_range (sheet, rule.leftSide));
        gnm_solver_constraint_set_rhs (c, gnm_solver_constraint_has_rhs (c) ? parse_side (sheet, rule.rightSide) : NULL);
        param->constraints = g_slist_append (param->constraints, c);
    }
}

@end

/* cb_notify_status's words */
static NSString *
status_text (GnmSolver *sol)
{
    switch (sol->status) {
    case GNM_SOLVER_STATUS_READY: return @"Ready";
    case GNM_SOLVER_STATUS_PREPARING: return @"Preparing";
    case GNM_SOLVER_STATUS_PREPARED: return @"Prepared";
    case GNM_SOLVER_STATUS_RUNNING: return @"Running";
    case GNM_SOLVER_STATUS_DONE: return @"Done";
    case GNM_SOLVER_STATUS_CANCELLED: return @"Cancelled";
    case GNM_SOLVER_STATUS_ERROR:
    default: return @"Error";
    }
}

@implementation GnmSolverOutcome

- (instancetype)initWithSolver:(GnmSolver *)sol
{
    if (!(self = [super init]))
        return nil;
    _status = status_text (sol);
    _reason = sol->reason ? GnmString (sol->reason) : nil;
    _quality = sol->result ? (GnmSolverQuality) sol->result->quality : GnmSolverQualityNone;
    _hasSolution = gnm_solver_has_solution (sol);
    _objectiveValue = sol->result ? sol->result->value : NAN;
    _elapsedSeconds = gnm_solver_elapsed (sol);
    return self;
}

@end

@implementation GnmEngine (Solver)

- (NSArray<GnmSolverAlgorithm *> *)solverAlgorithms
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    NSMutableArray *result = [NSMutableArray array];
    for (GSList *l = gnm_solver_db_get (); l; l = l->next)
        [result addObject:[[GnmSolverAlgorithm alloc] initWithFactory:l->data]];
    return result;
}

@end

static GOUndo *
set_params_undo (Sheet *sheet, GnmSolverParameters *params)
{
    /* dialog-solver.c set_params */
    return go_undo_binary_new (sheet, g_object_ref (params), (GOUndoBinaryFunc) gnm_sheet_set_solver_params, NULL, g_object_unref);
}

static gboolean
cb_keep_waiting (gpointer data)
{
    return G_SOURCE_CONTINUE;
}

@implementation GnmSheet (Solver)

- (GnmSolverSettings *)solverSettings
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    if (!sheet)
        return [[GnmSolverSettings alloc] init];
    return [[GnmSolverSettings alloc] initWithParameters:sheet->solver_parameters sheet:sheet];
}

- (BOOL)setSolverSettings:(GnmSolverSettings *)settings error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    if (!sheet || !workbook)
        return NO;
    GnmSolverParameters *orig = gnm_solver_param_dup (sheet->solver_parameters, sheet);
    GnmSolverParameters *param = sheet->solver_parameters;
    [settings _fillParameters:param sheet:sheet];
    GError *err = NULL;
    if (!gnm_solver_param_valid (param, &err)) {
        if (error)
            *error = solver_error (workbook.engine, err ? GnmString (err->message) : @"The solver parameters are invalid.");
        g_clear_error (&err);
        gnm_sheet_set_solver_params (sheet, orig);
        g_object_unref (orig);
        return NO;
    }
    /* check_for_changed_options */
    BOOL ok = YES;
    if (!gnm_solver_param_equal (sheet->solver_parameters, orig)) {
        GOUndo *undo = set_params_undo (sheet, orig);
        GOUndo *redo = set_params_undo (sheet, sheet->solver_parameters);
        ok = [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
            return cmd_generic (wbc, "Changing solver parameters", undo, redo);
        } description:@"Could not change the solver parameters." error:error];
    }
    g_object_unref (orig);
    return ok;
}

- (GnmSolverRun *)startSolverWithError:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    if (!sheet || !workbook)
        return nil;
    GnmEngine *engine = workbook.engine;
    GnmSolverParameters *param = sheet->solver_parameters;
    GError *err = NULL;
    if (!gnm_solver_param_valid (param, &err)) {
        if (error)
            *error = solver_error (engine, err ? GnmString (err->message) : @"The solver parameters are invalid.");
        g_clear_error (&err);
        return nil;
    }
    /* run_solver */
    GnmSolverFactory *factory = param->options.algorithm;
    GnmSolver *sol = gnm_solver_factory_functional (factory, NULL) ? gnm_solver_factory_create (factory, param) : NULL;
    if (!sol) {
        if (error)
            *error = solver_error (engine, factory ? @"The chosen solver is not functional." : @"No solver algorithm is chosen.");
        return nil;
    }
    GnmSheetRange sr;
    gnm_sheet_range_from_value (&sr, gnm_solver_param_get_input (param));
    if (!sr.sheet)
        sr.sheet = param->sheet;
    GOUndo *undo = clipboard_copy_range_undo (sr.sheet, &sr.range);
    if (!gnm_solver_start (sol, workbook.control, &err)) {
        /* finished at once, with the words of the failure */
        if (err)
            gnm_solver_set_reason (sol, err->message);
        if (!gnm_solver_finished (sol))
            gnm_solver_set_status (sol, GNM_SOLVER_STATUS_ERROR);
    }
    g_clear_error (&err);
    GnmSolverRun *run = [[GnmSolverRun alloc] initWithSolver:sol sheet:self range:sr undo:undo];
    g_object_unref (sol);
    return run;
}

- (GnmSolverOutcome *)runSolverWithError:(NSError **)error
{
    GnmSolverRun *run = [self startSolverWithError:error];
    if (!run)
        return nil;
    /* the dialog's nested main loop: the solver's sources run until it
     * is done, with the time limit checked as its timer does */
    guint ticker = g_timeout_add (100, cb_keep_waiting, NULL);
    while (!run.isFinished) {
        g_main_context_iteration (NULL, TRUE);
        [run checkTimeout];
    }
    g_source_remove (ticker);
    return [run finish];
}

@end

@implementation GnmSolverRun {
    GnmSolver *_sol;
    GnmSheet *_sheet;
    /* kept alive past the solver: its parameters are the sheet's, and
     * their dependents unlink from the sheet when the solver goes */
    GnmWorkbook *_workbook;
    GnmSheetRange _range;
    GOUndo *_undo;
    BOOL _finished;
}

- (instancetype)initWithSolver:(GnmSolver *)solver sheet:(GnmSheet *)sheet range:(GnmSheetRange)range undo:(GOUndo *)undo
{
    if (!(self = [super init]))
        return nil;
    _sol = g_object_ref (solver);
    _sheet = sheet;
    _workbook = sheet.workbook;
    _range = range;
    _undo = undo;
    return self;
}

- (void)dealloc
{
    /* before ARC lets the workbook go */
    if (_undo)
        g_object_unref (_undo);
    g_object_unref (_sol);
}

- (NSString *)status
{
    NSString *text = status_text (_sol);
    return _sol->reason ? [NSString stringWithFormat:@"%@ (%s)", text, _sol->reason] : text;
}

- (BOOL)isFinished { return gnm_solver_finished (_sol); }

- (NSNumber *)objectiveValue
{
    /* update_obj_value: the result's value, once there is one */
    return _sol->result ? @(_sol->result->value) : nil;
}

- (double)elapsedSeconds { return gnm_solver_elapsed (_sol); }

- (BOOL)checkTimeout
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    return gnm_solver_check_timeout (_sol);
}

- (BOOL)stop
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    if (gnm_solver_finished (_sol))
        return YES;
    return gnm_solver_stop (_sol, NULL);
}

- (GnmSolverOutcome *)finish
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    if (_finished || !gnm_solver_finished (_sol))
        return nil;
    _finished = YES;
    Sheet *sheet = _sheet.engineSheet;
    GnmWorkbook *workbook = _sheet.workbook;
    GnmSolverParameters *param = _sol->params;
    if (sheet && workbook && gnm_solver_has_solution (_sol)) {
        gnm_solver_store_result (_sol);
        GOUndo *undo = _undo;
        _undo = NULL;
        GOUndo *redo = clipboard_copy_range_undo (_range.sheet, &_range.range);
        if (param->options.program_report || param->options.sensitivity_report) {
            Workbook *wb = param->sheet->workbook;
            GOUndo *undo_report = go_undo_binary_new (wb, workbook_sheet_state_new (wb), (GOUndoBinaryFunc) workbook_sheet_state_restore,
                                                      NULL, (GFreeFunc) workbook_sheet_state_unref);
            undo = go_undo_combine (undo, undo_report);
            char *base = g_strdup_printf ("%s %%s Report", sheet->name_unquoted);
            gnm_solver_create_report (_sol, workbook.control, base);
            g_free (base);
            GOUndo *redo_report = go_undo_binary_new (wb, workbook_sheet_state_new (wb), (GOUndoBinaryFunc) workbook_sheet_state_restore,
                                                      NULL, (GFreeFunc) workbook_sheet_state_unref);
            redo = go_undo_combine (redo, redo_report);
        }
        [workbook _runCommand:^gboolean (WorkbookControl *control) {
            return cmd_generic (control, "Running solver", undo, redo);
        } description:@"Could not record the solver's result." error:NULL];
    }
    gnm_app_recalc ();
    return [[GnmSolverOutcome alloc] initWithSolver:_sol];
}

@end

@implementation GnmSheet (SolverRules)

- (NSString *)descriptionOfSolverRule:(GnmSolverRule *)rule
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    if (!sheet)
        return nil;
    GnmSolverConstraint *c = gnm_solver_constraint_new (sheet);
    c->type = (GnmSolverConstraintType) rule.kind;
    gnm_solver_constraint_set_lhs (c, parse_range (sheet, rule.leftSide));
    gnm_solver_constraint_set_rhs (c, gnm_solver_constraint_has_rhs (c) ? parse_side (sheet, rule.rightSide) : NULL);
    NSString *text = nil;
    if (gnm_solver_constraint_valid (c, sheet->solver_parameters)) {
        char *s = gnm_solver_constraint_as_str (c, sheet);
        text = GnmString (s);
        g_free (s);
    }
    gnm_solver_constraint_free (c);
    return text;
}

@end
