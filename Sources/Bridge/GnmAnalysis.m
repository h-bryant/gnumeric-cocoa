// The analysis tools as dialog-analysis-tools.c runs them: a tool object
// with the dialog's settings, the input parsed as a range list, the
// output description from the Output page, and cmd_analysis_tool.
#import "GnmPrivate.h"

static NSError *
analysis_error (GnmEngine *engine, NSString *message)
{
    return [engine _errorWithCode:GnmErrorCommandFailed description:message collected:@[]];
}

/* One range from text, as gnm_expr_entry_parse_as_value gives it, or NULL. */
static GnmValue *
single_range (Sheet *sheet, NSString *text)
{
    if (text.length == 0)
        return NULL;
    GSList *ranges = global_range_list_parse (sheet, text.UTF8String);
    GnmValue *result = NULL;
    if (ranges && !ranges->next && VALUE_IS_CELLRANGE ((GnmValue *) ranges->data)) {
        result = ranges->data;
        g_slist_free (ranges);
    } else
        range_list_destroy (ranges);
    return result;
}

#pragma mark - Output

@implementation GnmAnalysisOutput

- (instancetype)initPrivate
{
    if (!(self = [super init]))
        return nil;
    _rangeName = @"";
    _autofitsColumns = YES;
    _clearsOutputRange = YES;
    return self;
}

+ (instancetype)onNewSheet
{
    GnmAnalysisOutput *output = [[self alloc] initPrivate];
    output->_isNewSheet = YES;
    return output;
}

+ (instancetype)inRangeNamed:(NSString *)text
{
    GnmAnalysisOutput *output = [[self alloc] initPrivate];
    output->_rangeName = [text copy];
    return output;
}

- (data_analysis_output_t *)_outputForSheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    data_analysis_output_t *dao;
    if (_isNewSheet)
        dao = dao_init_new_sheet (sheet);
    else {
        GnmValue *range = single_range (sheet, _rangeName);
        if (!range) {
            if (error)
                *error = analysis_error (engine, @"The output range is invalid.");
            return NULL;
        }
        dao = dao_init (GNM_DAO_OUTPUT_RANGE);
        dao_load_from_value (dao, range);
        value_release (range);
        if (!dao->dst_sheet)
            dao->dst_sheet = sheet;
    }
    dao->autofit_flag = _autofitsColumns;
    dao->clear_outputrange = _clearsOutputRange;
    dao->retain_format = _retainsFormatting;
    dao->retain_comments = _retainsComments;
    dao->put_formulas = _entersFormulas;
    return dao;
}

@end

#pragma mark - Tools

@implementation GnmAnalysis

- (instancetype)initWithTitle:(NSString *)title
{
    if (!(self = [super init]))
        return nil;
    _title = [title copy];
    return self;
}

- (GnmAnalysisTool *)_engineToolForSheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    return NULL;
}

- (NSString *)_failureDescriptionForEngineTool:(GnmAnalysisTool *)tool
{
    return nil;
}

@end

@implementation GnmGroupedAnalysis

- (instancetype)initWithTitle:(NSString *)title
{
    if (!(self = [super initWithTitle:title]))
        return nil;
    _inputRanges = @"";
    _grouping = GnmAnalysisGroupingColumns;
    return self;
}

- (GnmAnalysisTool *)_newEngineTool
{
    return NULL;
}

- (BOOL)_configureEngineTool:(GnmAnalysisTool *)tool engine:(GnmEngine *)engine error:(NSError **)error
{
    return YES;
}

- (GnmAnalysisTool *)_engineToolForSheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    GnmAnalysisTool *tool = [self _newEngineTool];
    GnmGenericAnalysisTool *gtool = GNM_GENERIC_ANALYSIS_TOOL (tool);
    gtool->base.input = _inputRanges.length ? global_range_list_parse (sheet, _inputRanges.UTF8String) : NULL;
    if (!gtool->base.input) {
        if (error)
            *error = analysis_error (engine, @"The input range is invalid.");
        g_object_unref (tool);
        return NULL;
    }
    gtool->base.group_by = (gnm_tool_group_by_t) _grouping;
    gtool->base.labels = _hasLabels;
    if (![self _configureEngineTool:tool engine:engine error:error]) {
        g_object_unref (tool);
        return NULL;
    }
    return tool;
}

- (NSString *)_failureDescriptionForEngineTool:(GnmAnalysisTool *)tool
{
    /* corr_tool_ok_clicked_cb's reading of the error code */
    GnmGenericAnalysisTool *gtool = GNM_GENERIC_ANALYSIS_TOOL (tool);
    switch ((int) gtool->base.err - 1) {
    case -1: return nil;
    case GNM_TOOL_GROUPED_BY_ROW: return @"The selected input rows must have equal size!";
    case GNM_TOOL_GROUPED_BY_COL: return @"The selected input columns must have equal size!";
    case GNM_TOOL_GROUPED_BY_AREA: return @"The selected input areas must have equal size!";
    default: return [NSString stringWithFormat:@"An unexpected error has occurred: %d.", gtool->base.err];
    }
}

@end

@implementation GnmDescriptiveStatistics

- (instancetype)init
{
    if (!(self = [super initWithTitle:@"Descriptive Statistics"]))
        return nil;
    /* descriptive-stats.ui: only the summary is on */
    _summaryStatistics = YES;
    return self;
}

- (GnmAnalysisTool *)_newEngineTool { return gnm_descriptive_tool_new (); }

- (BOOL)_configureEngineTool:(GnmAnalysisTool *)tool engine:(GnmEngine *)engine error:(NSError **)error
{
    /* desc_stat_tool_update_sensitivity_cb's checks */
    if (!_summaryStatistics && !_confidenceLevel && !_kthLargest && !_kthSmallest) {
        if (error)
            *error = analysis_error (engine, @"No statistics are selected.");
        return NO;
    }
    if (_confidenceLevel && !(_confidenceLevel.doubleValue > 0 && _confidenceLevel.doubleValue < 1)) {
        if (error)
            *error = analysis_error (engine, @"The confidence level should be between 0 and 1.");
        return NO;
    }
    for (NSNumber *k in @[_kthLargest ?: @1, _kthSmallest ?: @1])
        if (k.doubleValue != (double) k.integerValue || k.integerValue <= 0) {
            if (error)
                *error = analysis_error (engine, @"K must be a positive integer.");
            return NO;
        }
    GnmDescriptiveTool *dtool = GNM_DESCRIPTIVE_TOOL (tool);
    dtool->summary_statistics = _summaryStatistics;
    dtool->use_ssmedian = _usesSSMedian;
    dtool->confidence_level = _confidenceLevel != nil;
    dtool->c_level = _confidenceLevel ? _confidenceLevel.doubleValue : 0.95;
    dtool->kth_largest = _kthLargest != nil;
    dtool->k_largest = _kthLargest ? _kthLargest.intValue : 1;
    dtool->kth_smallest = _kthSmallest != nil;
    dtool->k_smallest = _kthSmallest ? _kthSmallest.intValue : 1;
    return YES;
}

@end

@implementation GnmCorrelationAnalysis
- (instancetype)init { return [super initWithTitle:@"Correlation"]; }
- (GnmAnalysisTool *)_newEngineTool { return gnm_correlation_tool_new (); }
@end

@implementation GnmCovarianceAnalysis
- (instancetype)init { return [super initWithTitle:@"Covariance"]; }
- (GnmAnalysisTool *)_newEngineTool { return gnm_covariance_tool_new (); }
@end

@implementation GnmRegressionAnalysis

- (instancetype)init
{
    if (!(self = [super initWithTitle:@"Regression"]))
        return nil;
    _xRange = @"";
    _yRange = @"";
    _confidenceLevel = 0.95;
    _isMultipleLinear = YES;
    return self;
}

- (GnmAnalysisTool *)_engineToolForSheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    /* regression_tool_update_sensitivity_cb's checks, then
     * regression_tool_ok_clicked_cb: range_1 holds the several variables,
     * range_2 the one (y, or x with several y). */
    BOOL swapped = _hasMultipleY;
    GnmValue *vector = single_range (sheet, swapped ? _xRange : _yRange);
    GnmRange r;
    if (!vector || !range_init_value (&r, vector)) {
        if (error)
            *error = analysis_error (engine, swapped ? @"The x variable range is invalid." : @"The y variable range is invalid.");
        if (vector)
            value_release (vector);
        return NULL;
    }
    int y_h = range_height (&r), y_w = range_width (&r);
    NSString *message = nil;
    if (y_h != 1 && y_w != 1)
        message = swapped ? @"The x variable range must be a vector (n by 1 or 1 by n)."
                          : @"The y variable range must be a vector (n by 1 or 1 by n).";
    else if (y_h <= 2 && y_w <= 2)
        message = swapped ? @"The x variable range is too small" : @"The y variable range is too small";
    if (message) {
        if (error)
            *error = analysis_error (engine, message);
        value_release (vector);
        return NULL;
    }
    GnmValue *several = single_range (sheet, swapped ? _yRange : _xRange);
    if (!several || !range_init_value (&r, several)) {
        if (error)
            *error = analysis_error (engine, swapped ? @"The y variables range is invalid." : @"The x variables range is invalid.");
        value_release (vector);
        if (several)
            value_release (several);
        return NULL;
    }
    int x_h = range_height (&r), x_w = range_width (&r);
    if ((y_h == 1 && y_w != x_w) || (y_w == 1 && y_h != x_h))
        message = swapped ? @"The sizes of the x variable and y variables ranges do not match."
                          : @"The sizes of the y variable and x variables ranges do not match.";
    else if (!(_confidenceLevel >= 0 && _confidenceLevel <= 1))
        message = @"The confidence level is invalid.";
    if (message) {
        if (error)
            *error = analysis_error (engine, message);
        value_release (vector);
        value_release (several);
        return NULL;
    }
    GnmAnalysisTool *tool = gnm_regression_tool_new ();
    GnmRegressionTool *rtool = GNM_REGRESSION_TOOL (tool);
    rtool->parent.base.range_1 = several;
    rtool->parent.base.range_2 = vector;
    rtool->group_by = y_h == 1 ? GNM_TOOL_GROUPED_BY_ROW : GNM_TOOL_GROUPED_BY_COL;
    rtool->parent.base.labels = _hasLabels;
    rtool->parent.base.alpha = 1 - _confidenceLevel;
    rtool->intercept = !_forcesZeroIntercept;
    rtool->residual = _calculatesResiduals;
    rtool->multiple_regression = _isMultipleLinear;
    rtool->multiple_y = _hasMultipleY;
    return tool;
}

- (NSString *)_failureDescriptionForEngineTool:(GnmAnalysisTool *)tool
{
    GnmGenericBAnalysisTool *btool = GNM_GENERIC_B_ANALYSIS_TOOL (tool);
    return btool->base.err ? [NSString stringWithFormat:@"An unexpected error has occurred: %d.", btool->base.err] : nil;
}

@end

#pragma mark - Running

@implementation GnmSheet (Analysis)

- (GnmSheet *)runAnalysis:(GnmAnalysis *)analysis output:(GnmAnalysisOutput *)output error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    if (!sheet || !workbook)
        return nil;
    GnmEngine *engine = workbook.engine;
    GnmAnalysisTool *tool = [analysis _engineToolForSheet:sheet engine:engine error:error];
    if (!tool)
        return nil;
    data_analysis_output_t *dao = [output _outputForSheet:sheet engine:engine error:error];
    if (!dao) {
        g_object_unref (tool);
        return nil;
    }
    /* The command owns the output description from here, freeing it on
     * failure as well, and keeps its own reference to the tool. */
    __block Sheet *written = NULL;
    NSError *failure = nil;
    BOOL ok = [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        gboolean trouble = cmd_analysis_tool (wbc, sheet, dao, tool);
        if (!trouble)
            written = dao->dst_sheet;
        return trouble;
    } description:[NSString stringWithFormat:@"Could not run %@.", analysis.title] error:&failure];
    if (!ok) {
        NSString *why = [analysis _failureDescriptionForEngineTool:tool];
        if (error)
            *error = why ? analysis_error (engine, why) : failure;
    }
    g_object_unref (tool);
    return ok && written ? [workbook wrapperForEngineSheet:written] : nil;
}

- (NSArray<NSString *> *)rangeNamesInList:(NSString *)text
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    if (!sheet || text.length == 0)
        return nil;
    GSList *ranges = global_range_list_parse (sheet, text.UTF8String);
    if (!ranges)
        return nil;
    NSMutableArray *names = [NSMutableArray array];
    for (GSList *l = ranges; l; l = l->next) {
        GnmValue const *v = l->data;
        GnmRange r;
        if (!VALUE_IS_CELLRANGE (v) || !range_init_value (&r, v)) {
            range_list_destroy (ranges);
            return nil;
        }
        Sheet *where = v->v_range.cell.a.sheet;
        char *name = where && where != sheet ? global_range_name (where, &r) : g_strdup (range_as_string (&r));
        [names addObject:[NSString stringWithUTF8String:name]];
        g_free (name);
    }
    range_list_destroy (ranges);
    return names;
}

@end
