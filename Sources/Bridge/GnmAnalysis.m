// The analysis tools as dialog-analysis-tools.c runs them: a tool object
// with the dialog's settings, the input parsed as a range list, the
// output description from the Output page, and cmd_analysis_tool.
#import "GnmPrivate.h"
#include <tools/analysis-ttest.h>
#include <tools/analysis-ztest.h>
#include <tools/analysis-ftest.h>
#include <tools/analysis-exp-smoothing.h>
#include <tools/analysis-frequency.h>
#include <tools/analysis-histogram.h>
#include <tools/analysis-normality.h>
#include <tools/analysis-one-mean-test.h>
#include <tools/analysis-sign-test.h>
#include <tools/analysis-signed-rank-test.h>
#include <tools/analysis-wilcoxon-mann-whitney.h>
#include <tools/analysis-principal-components.h>
#include <tools/analysis-kaplan-meier.h>
#include <tools/analysis-chi-squared.h>
#include <tools/analysis-anova.h>

static NSError *
analysis_error (GnmEngine *engine, NSString *message)
{
    return [engine _errorWithCode:GnmErrorCommandFailed description:message collected:@[]];
}

/* One range from text, as gnm_expr_entry_parse_as_value gives it for the
 * dialogs' entries (GNM_EE_FORCE_ABS_REF: the references absolute, so the
 * output's evaluation elsewhere does not shift them), or NULL. */
static GnmValue *
single_range (Sheet *sheet, NSString *text)
{
    if (text.length == 0)
        return NULL;
    GnmParsePos pp;
    parse_pos_init_sheet (&pp, sheet);
    GnmValue *v = value_new_cellrange_parsepos_str (&pp, text.UTF8String,
                                                    GNM_EXPR_PARSE_UNKNOWN_NAMES_ARE_STRINGS | GNM_EXPR_PARSE_FORCE_ABSOLUTE_REFERENCES
                                                    | GNM_EXPR_PARSE_FORCE_EXPLICIT_SHEET_REFERENCES);
    if (v && !VALUE_IS_CELLRANGE (v)) {
        value_release (v);
        return NULL;
    }
    return v;
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

- (NSArray<NSString *> *)_requiredPluginIdentifiers
{
    return @[];
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

- (BOOL)_configureEngineTool:(GnmAnalysisTool *)tool sheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
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
    if (![self _configureEngineTool:tool sheet:sheet engine:engine error:error]) {
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

- (BOOL)_configureEngineTool:(GnmAnalysisTool *)tool sheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
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

#pragma mark - Two samples

@implementation GnmTwoSampleAnalysis

- (instancetype)initWithTitle:(NSString *)title
{
    if (!(self = [super initWithTitle:title]))
        return nil;
    _firstRange = @"";
    _secondRange = @"";
    _alpha = 0.05;
    return self;
}

- (GnmAnalysisTool *)_newEngineTool { return NULL; }

- (BOOL)_configureEngineTool:(GnmAnalysisTool *)tool sheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error { return YES; }

- (GnmAnalysisTool *)_engineToolForSheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    /* ttest_update_sensitivity_cb and ttest_tool_ok_clicked_cb */
    GnmValue *first = single_range (sheet, _firstRange);
    if (!first) {
        if (error)
            *error = analysis_error (engine, @"The variable 1 range is invalid.");
        return NULL;
    }
    GnmValue *second = single_range (sheet, _secondRange);
    if (!second) {
        if (error)
            *error = analysis_error (engine, @"The variable 2 range is invalid.");
        value_release (first);
        return NULL;
    }
    if (!(_alpha > 0 && _alpha < 1)) {
        if (error)
            *error = analysis_error (engine, @"The alpha value should be between 0 and 1.");
        value_release (first);
        value_release (second);
        return NULL;
    }
    GnmAnalysisTool *tool = [self _newEngineTool];
    GnmGenericBAnalysisTool *btool = GNM_GENERIC_B_ANALYSIS_TOOL (tool);
    btool->base.range_1 = first;
    btool->base.range_2 = second;
    btool->base.labels = _hasLabels;
    btool->base.alpha = _alpha;
    if (![self _configureEngineTool:tool sheet:sheet engine:engine error:error]) {
        g_object_unref (tool);
        return NULL;
    }
    return tool;
}

- (NSString *)_failureDescriptionForEngineTool:(GnmAnalysisTool *)tool
{
    GnmGenericBAnalysisTool *btool = GNM_GENERIC_B_ANALYSIS_TOOL (tool);
    return btool->base.err ? [NSString stringWithFormat:@"An unexpected error has occurred: %d.", btool->base.err] : nil;
}

@end

@implementation GnmMeanTestAnalysis

- (instancetype)init
{
    if (!(self = [super initWithTitle:@"Claims About Two Means"]))
        return nil;
    _kind = GnmMeanTestUnequalVariances;
    return self;
}

- (GnmAnalysisTool *)_newEngineTool
{
    switch (_kind) {
    case GnmMeanTestPaired: return gnm_ttest_paired_tool_new ();
    case GnmMeanTestKnownVariances: return gnm_ztest_tool_new ();
    case GnmMeanTestEqualVariances: return gnm_ttest_eqvar_tool_new ();
    case GnmMeanTestUnequalVariances: return gnm_ttest_neqvar_tool_new ();
    }
    return gnm_ttest_neqvar_tool_new ();
}

- (BOOL)_configureEngineTool:(GnmAnalysisTool *)tool sheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    switch (_kind) {
    case GnmMeanTestPaired: GNM_TTEST_PAIRED_TOOL (tool)->mean_diff = _hypothesizedMeanDifference; break;
    case GnmMeanTestEqualVariances: GNM_TTEST_EQVAR_TOOL (tool)->mean_diff = _hypothesizedMeanDifference; break;
    case GnmMeanTestUnequalVariances: GNM_TTEST_NEQVAR_TOOL (tool)->mean_diff = _hypothesizedMeanDifference; break;
    case GnmMeanTestKnownVariances: {
        GnmZTestTool *ztool = GNM_ZTEST_TOOL (tool);
        if (!(_firstVariance > 0)) {
            if (error)
                *error = analysis_error (engine, @"Please enter a valid population variance for variable 1.");
            return NO;
        }
        if (!(_secondVariance > 0)) {
            if (error)
                *error = analysis_error (engine, @"Please enter a valid population variance for variable 2.");
            return NO;
        }
        ztool->mean_diff = _hypothesizedMeanDifference;
        ztool->var1 = _firstVariance;
        ztool->var2 = _secondVariance;
        break;
    }
    }
    return YES;
}

@end

@implementation GnmVarianceTestAnalysis
- (instancetype)init { return [super initWithTitle:@"Claims About Two Variances"]; }
- (GnmAnalysisTool *)_newEngineTool { return gnm_ftest_tool_new (); }
@end

#pragma mark - More grouped tools

@implementation GnmAnovaSingleFactorAnalysis

- (instancetype)init
{
    if (!(self = [super initWithTitle:@"ANOVA: Single Factor"]))
        return nil;
    _alpha = 0.05;
    return self;
}

- (GnmAnalysisTool *)_newEngineTool { return gnm_anova_single_tool_new (); }

- (BOOL)_configureEngineTool:(GnmAnalysisTool *)tool sheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    if (!(_alpha > 0 && _alpha < 1)) {
        if (error)
            *error = analysis_error (engine, @"The alpha value should be between 0 and 1.");
        return NO;
    }
    GNM_ANOVA_SINGLE_TOOL (tool)->alpha = _alpha;
    return YES;
}

@end

@implementation GnmRankingAnalysis
- (instancetype)init { return [super initWithTitle:@"Rank and Percentile"]; }
- (GnmAnalysisTool *)_newEngineTool { return gnm_ranking_tool_new (); }
- (BOOL)_configureEngineTool:(GnmAnalysisTool *)tool sheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    GNM_RANKING_TOOL (tool)->av_ties = _averagesTies;
    return YES;
}
@end

@implementation GnmSamplingAnalysis

- (instancetype)init
{
    if (!(self = [super initWithTitle:@"Sampling"]))
        return nil;
    _period = 1;
    _sampleSize = 1;
    _sampleCount = 1;
    return self;
}

- (GnmAnalysisTool *)_newEngineTool { return gnm_sampling_tool_new (); }

- (BOOL)_configureEngineTool:(GnmAnalysisTool *)tool sheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    /* sampling_tool_update_sensitivity_cb */
    NSString *why = nil;
    if (_sampleCount < 1)
        why = @"The requested number of samples is invalid.";
    else if (_isPeriodic && _period < 1)
        why = @"The requested period is invalid.";
    else if (_isPeriodic && _offset < 0)
        why = @"The requested offset is invalid.";
    else if (!_isPeriodic && _sampleSize < 1)
        why = @"The requested sample size is invalid.";
    if (why) {
        if (error)
            *error = analysis_error (engine, why);
        return NO;
    }
    GnmSamplingTool *stool = GNM_SAMPLING_TOOL (tool);
    stool->periodic = _isPeriodic;
    if (_isPeriodic) {
        stool->period = (guint) _period;
        stool->offset = (guint) _offset;
        stool->row_major = _isRowMajor;
    }
    stool->size = (guint) _sampleSize;
    stool->number = (guint) _sampleCount;
    return YES;
}

@end

@implementation GnmMovingAverageAnalysis

- (instancetype)init
{
    if (!(self = [super initWithTitle:@"Moving Average"]))
        return nil;
    _interval = 3;
    return self;
}

- (GnmAnalysisTool *)_newEngineTool { return gnm_moving_average_tool_new (); }

- (BOOL)_configureEngineTool:(GnmAnalysisTool *)tool sheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    /* average_tool_update_sensitivity_cb, then average_tool_ok_clicked_cb */
    GnmMovingAverageTool *mtool = GNM_MOVING_AVERAGE_TOOL (tool);
    NSInteger interval = _interval;
    NSInteger offset = _isCentral ? interval / 2 : _offset;
    moving_average_type_t type = (moving_average_type_t) _kind;
    if ((type == moving_average_type_sma || type == moving_average_type_wma) && interval <= 0) {
        if (error)
            *error = analysis_error (engine, @"The given interval is invalid.");
        return NO;
    }
    if (type == moving_average_type_sma && (offset < 0 || offset > interval)) {
        if (error)
            *error = analysis_error (engine, @"The given offset is invalid.");
        return NO;
    }
    switch (type) {
    case moving_average_type_sma:
        if (_isCentral && interval % 2 == 0)
            type = moving_average_type_central_sma;
        break;
    case moving_average_type_cma:
        interval = 0;
        offset = 0;
        break;
    case moving_average_type_spencer_ma:
        interval = 15;
        offset = 7;
        break;
    case moving_average_type_wma:
        offset = 0;
        break;
    default:
        break;
    }
    mtool->interval = (int) interval;
    mtool->offset = (int) offset;
    mtool->std_error_flag = _includesStandardErrors;
    mtool->show_graph = _includesChart;
    mtool->df = (int) _denominatorOffset;
    mtool->ma_type = type;
    return YES;
}

@end

@implementation GnmExponentialSmoothingAnalysis

- (instancetype)init
{
    if (!(self = [super initWithTitle:@"Exponential Smoothing"]))
        return nil;
    _dampingFactor = 0.2;
    _growthDampingFactor = 0.2;
    _seasonalDampingFactor = 0.2;
    _seasonalPeriod = 12;
    return self;
}

- (GnmAnalysisTool *)_newEngineTool { return gnm_exp_smoothing_tool_new (); }

- (BOOL)_configureEngineTool:(GnmAnalysisTool *)tool sheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    /* exp_smoothing_tool_update_sensitivity_cb */
    NSString *why = nil;
    BOOL seasonal = _kind == GnmExponentialSmoothingAdditiveHoltWinters || _kind == GnmExponentialSmoothingMultiplicativeHoltWinters;
    BOOL trend = seasonal || _kind == GnmExponentialSmoothingHoltTrend;
    if (seasonal && !(_seasonalDampingFactor >= 0 && _seasonalDampingFactor <= 1))
        why = @"The given seasonal damping factor is invalid.";
    else if (seasonal && _seasonalPeriod < 2)
        why = @"The given seasonal period is invalid.";
    else if (trend && !(_growthDampingFactor >= 0 && _growthDampingFactor <= 1))
        why = @"The given growth damping factor is invalid.";
    else if (!(_dampingFactor >= 0 && _dampingFactor <= 1))
        why = @"The given damping factor is invalid.";
    if (why) {
        if (error)
            *error = analysis_error (engine, why);
        return NO;
    }
    GnmExpSmoothingTool *etool = GNM_EXP_SMOOTHING_TOOL (tool);
    etool->damp_fact = _dampingFactor;
    etool->g_damp_fact = _growthDampingFactor;
    etool->s_damp_fact = _seasonalDampingFactor;
    etool->s_period = (int) _seasonalPeriod;
    etool->std_error_flag = _includesStandardErrors;
    etool->show_graph = _includesChart;
    etool->df = (int) _denominatorOffset;
    etool->es_type = (exponential_smoothing_type_t) _kind;
    return YES;
}

@end

#pragma mark - Frequency tables and histograms

@implementation GnmFrequencyAnalysis

- (instancetype)init
{
    if (!(self = [super initWithTitle:@"Frequency Tables"]))
        return nil;
    _categoryCount = 10;
    return self;
}

- (GnmAnalysisTool *)_newEngineTool { return gnm_frequency_tool_new (); }

- (BOOL)_configureEngineTool:(GnmAnalysisTool *)tool sheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    /* frequency_tool_update_sensitivity_cb and frequency_tool_ok_clicked_cb */
    GnmFrequencyTool *ftool = GNM_FREQUENCY_TOOL (tool);
    if (_categoryRange.length) {
        ftool->bin = single_range (sheet, _categoryRange);
        if (!ftool->bin) {
            if (error)
                *error = analysis_error (engine, @"The categories range is not valid.");
            return NO;
        }
        ftool->predetermined = TRUE;
    } else {
        if (_categoryCount < 1) {
            if (error)
                *error = analysis_error (engine, @"The number of categories is invalid.");
            return NO;
        }
        ftool->predetermined = FALSE;
        ftool->bin = NULL;
        ftool->n = (gint) _categoryCount;
    }
    ftool->percentage = _asPercentages;
    ftool->exact = _exactMatches;
    ftool->chart = (gnm_freq_tool_chart_t) _chart;
    return YES;
}

@end

@implementation GnmHistogramAnalysis

- (instancetype)init
{
    if (!(self = [super initWithTitle:@"Histogram"]))
        return nil;
    _cutoffCount = 10;
    return self;
}

- (GnmAnalysisTool *)_newEngineTool { return gnm_histogram_tool_new (); }

- (BOOL)_configureEngineTool:(GnmAnalysisTool *)tool sheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    /* histogram_tool_update_sensitivity_cb and histogram_tool_ok_clicked_cb */
    GnmHistogramTool *htool = GNM_HISTOGRAM_TOOL (tool);
    if (_cutoffRange.length) {
        htool->bin = single_range (sheet, _cutoffRange);
        if (!htool->bin) {
            if (error)
                *error = analysis_error (engine, @"The cutoff range is not valid.");
            return NO;
        }
        htool->predetermined = TRUE;
    } else {
        if (_cutoffCount < 1) {
            if (error)
                *error = analysis_error (engine, @"The number of to be calculated cutoffs is invalid.");
            return NO;
        }
        htool->predetermined = FALSE;
        htool->bin = NULL;
        htool->n = (gint) _cutoffCount;
        htool->max_given = _maximum != nil;
        htool->min_given = _minimum != nil;
        htool->max = _maximum.doubleValue;
        htool->min = _minimum.doubleValue;
    }
    htool->bin_type = (analysis_histogram_bin_type_t) ((_binsIncludeUpperCutoff ? bintype_no_inf_upper : 0)
                                                        | (_lastBinToPlusInfinity ? bintype_p_inf_lower : 0)
                                                        | (_firstBinFromMinusInfinity ? bintype_m_inf_lower : 0));
    htool->percentage = _asPercentages;
    htool->cumulative = _cumulative;
    htool->only_numbers = _onlyNumbers;
    htool->chart = (gnm_hist_tool_chart_t) _chart;
    return YES;
}

@end

#pragma mark - One-sample tests

static BOOL
check_alpha (double alpha, GnmEngine *engine, NSError **error)
{
    if (alpha > 0 && alpha < 1)
        return YES;
    if (error)
        *error = analysis_error (engine, @"The alpha value should be between 0 and 1.");
    return NO;
}

@implementation GnmNormalityAnalysis

- (instancetype)init
{
    if (!(self = [super initWithTitle:@"Normality Tests"]))
        return nil;
    _alpha = 0.05;
    return self;
}

- (GnmAnalysisTool *)_newEngineTool { return gnm_normality_tool_new (); }

- (BOOL)_configureEngineTool:(GnmAnalysisTool *)tool sheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    if (!check_alpha (_alpha, engine, error))
        return NO;
    GnmNormalityTool *ntool = GNM_NORMALITY_TOOL (tool);
    ntool->alpha = _alpha;
    ntool->type = (gnm_normality_test_type_t) _kind;
    ntool->graph = _includesProbabilityPlot;
    return YES;
}

@end

@implementation GnmOneMeanTestAnalysis

- (instancetype)init
{
    if (!(self = [super initWithTitle:@"Claims About a Mean"]))
        return nil;
    _alpha = 0.05;
    return self;
}

- (GnmAnalysisTool *)_newEngineTool { return gnm_one_mean_test_tool_new (); }

- (BOOL)_configureEngineTool:(GnmAnalysisTool *)tool sheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    if (!check_alpha (_alpha, engine, error))
        return NO;
    GnmOneMeanTestTool *otool = GNM_ONE_MEAN_TEST_TOOL (tool);
    otool->mean = _hypothesizedMean;
    otool->alpha = _alpha;
    return YES;
}

@end

@implementation GnmMedianTestAnalysis

- (instancetype)init
{
    if (!(self = [super initWithTitle:@"Claims About a Median"]))
        return nil;
    _alpha = 0.05;
    return self;
}

- (GnmAnalysisTool *)_newEngineTool
{
    return _kind == GnmMedianTestSign ? gnm_sign_test_tool_new () : gnm_signed_rank_test_tool_new ();
}

- (BOOL)_configureEngineTool:(GnmAnalysisTool *)tool sheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    if (!check_alpha (_alpha, engine, error))
        return NO;
    if (GNM_IS_SIGN_TEST_TOOL (tool)) {
        GNM_SIGN_TEST_TOOL (tool)->median = _hypothesizedMedian;
        GNM_SIGN_TEST_TOOL (tool)->alpha = _alpha;
    } else {
        GNM_SIGNED_RANK_TEST_TOOL (tool)->median = _hypothesizedMedian;
        GNM_SIGNED_RANK_TEST_TOOL (tool)->alpha = _alpha;
    }
    return YES;
}

@end

#pragma mark - Two-sample tests

@implementation GnmTwoMedianTestAnalysis

- (instancetype)init
{
    return [super initWithTitle:@"Claims About Two Medians"];
}

- (GnmAnalysisTool *)_newEngineTool
{
    return _kind == GnmMedianTestSign ? gnm_sign_test_two_tool_new () : gnm_signed_rank_test_two_tool_new ();
}

- (BOOL)_configureEngineTool:(GnmAnalysisTool *)tool sheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    /* sign_test_two_tool_update_sensitivity_cb: the same shape */
    GnmGenericBAnalysisTool *btool = GNM_GENERIC_B_ANALYSIS_TOOL (tool);
    GnmRangeRef const *a = &btool->base.range_1->v_range.cell, *b = &btool->base.range_2->v_range.cell;
    if (a->b.col - a->a.col != b->b.col - b->a.col || a->b.row - a->a.row != b->b.row - b->a.row) {
        if (error)
            *error = analysis_error (engine, @"The input ranges do not have the same shape.");
        return NO;
    }
    if (GNM_IS_SIGN_TEST_TWO_TOOL (tool))
        GNM_SIGN_TEST_TWO_TOOL (tool)->median = _hypothesizedMedian;
    else
        GNM_SIGNED_RANK_TEST_TWO_TOOL (tool)->median = _hypothesizedMedian;
    return YES;
}

@end

@implementation GnmMannWhitneyAnalysis

- (instancetype)init
{
    return [super initWithTitle:@"Wilcoxon-Mann-Whitney Test"];
}

- (GnmAnalysisTool *)_newEngineTool { return gnm_wilcoxon_mann_whitney_tool_new (); }

@end

#pragma mark - Dependent observations

@implementation GnmPrincipalComponentsAnalysis

- (instancetype)init
{
    return [super initWithTitle:@"Principal Components Analysis"];
}

- (GnmAnalysisTool *)_newEngineTool { return gnm_principal_components_tool_new (); }

@end

@implementation GnmFourierAnalysis

- (instancetype)init
{
    return [super initWithTitle:@"Fourier Analysis"];
}

- (GnmAnalysisTool *)_newEngineTool { return gnm_fourier_tool_new (); }

/* dialog_fourier_tool's plugins: the time series analysis one is not in
 * the default active list */
- (NSArray<NSString *> *)_requiredPluginIdentifiers
{
    return @[@"Gnumeric_fnTimeSeriesAnalysis", @"Gnumeric_fncomplex"];
}

- (BOOL)_configureEngineTool:(GnmAnalysisTool *)tool sheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    GNM_FOURIER_TOOL (tool)->inverse = _isInverse;
    return YES;
}

@end

@implementation GnmKaplanMeierGroup

- (instancetype)initWithName:(NSString *)name from:(NSInteger)from to:(NSInteger)to
{
    if (!(self = [super init]))
        return nil;
    _name = [name copy];
    _from = from;
    _to = to;
    return self;
}

@end

@implementation GnmKaplanMeierAnalysis

- (instancetype)init
{
    if (!(self = [super initWithTitle:@"Kaplan-Meier Estimates"]))
        return nil;
    _timeRange = @"";
    _groups = @[];
    return self;
}

/* kaplan_meier_tool_update_sensitivity_cb's reading of a column entry */
static GnmValue *
kaplan_meier_column (Sheet *sheet, NSString *text, GnmValue const *time, NSString *what, GnmEngine *engine, NSError **error)
{
    GnmValue *v = single_range (sheet, text);
    NSString *message = nil;
    if (!v)
        message = [NSString stringWithFormat:@"The %@ column is not valid.", what];
    else if (v->v_range.cell.a.col != v->v_range.cell.b.col)
        message = [NSString stringWithFormat:@"The %@ column should be part of a single column.", what];
    else if (time && v->v_range.cell.b.row - v->v_range.cell.a.row != time->v_range.cell.b.row - time->v_range.cell.a.row)
        message = [NSString stringWithFormat:@"The %@ and time columns should have the same height.", what];
    if (!message)
        return v;
    if (v)
        value_release (v);
    if (error)
        *error = analysis_error (engine, message);
    return NULL;
}

- (GnmAnalysisTool *)_engineToolForSheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    GnmValue *time = kaplan_meier_column (sheet, _timeRange, NULL, @"time", engine, error);
    if (!time)
        return NULL;
    GnmValue *censor = NULL, *group = NULL;
    if (_censorRange.length && !(censor = kaplan_meier_column (sheet, _censorRange, time, @"censorship", engine, error))) {
        value_release (time);
        return NULL;
    }
    if (_groups.count && !(group = kaplan_meier_column (sheet, _groupRange ?: @"", time, @"groups", engine, error))) {
        value_release (time);
        if (censor)
            value_release (censor);
        return NULL;
    }
    GnmAnalysisTool *tool = gnm_kaplan_meier_tool_new ();
    GnmKaplanMeierTool *ktool = GNM_KAPLAN_MEIER_TOOL (tool);
    ktool->parent.base.range_1 = time;
    ktool->parent.base.range_2 = censor;
    ktool->censored = censor != NULL;
    ktool->censor_mark = (int) _censorMark;
    ktool->censor_mark_to = (int) _censorMarkTo;
    ktool->range_3 = group;
    GSList *list = NULL;
    for (GnmKaplanMeierGroup *g in _groups) {
        analysis_tools_kaplan_meier_group_t *entry = g_new0 (analysis_tools_kaplan_meier_group_t, 1);
        entry->name = g_strdup (g.name.UTF8String);
        entry->group_from = (guint) MAX (g.from, 0);
        entry->group_to = (guint) MAX (g.to, 0);
        list = g_slist_append (list, entry);
    }
    ktool->group_list = list;
    ktool->logrank_test = list != NULL && _logRankTest;
    ktool->median = _includesMedian;
    ktool->chart = _includesChart;
    ktool->ticks = _includesTicks;
    ktool->std_err = _includesStandardErrors;
    return tool;
}

@end

#pragma mark - Tables

@implementation GnmContingencyTableAnalysis

- (instancetype)init
{
    if (!(self = [super initWithTitle:@"Contingency Table"]))
        return nil;
    _inputRange = @"";
    _alpha = 0.05;
    return self;
}

- (GnmAnalysisTool *)_engineToolForSheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    /* chi_squared_tool_update_sensitivity_cb and chi_squared_tool_ok_clicked_cb */
    GnmValue *input = single_range (sheet, _inputRange);
    if (!input) {
        if (error)
            *error = analysis_error (engine, @"The input range is invalid.");
        return NULL;
    }
    int rows = input->v_range.cell.b.row - input->v_range.cell.a.row + 1;
    int cols = input->v_range.cell.b.col - input->v_range.cell.a.col + 1;
    if (MIN (rows, cols) < (_hasLabels ? 3 : 2)) {
        if (error)
            *error = analysis_error (engine, @"The input range is too small.");
        value_release (input);
        return NULL;
    }
    if (!check_alpha (_alpha, engine, error)) {
        value_release (input);
        return NULL;
    }
    GnmAnalysisTool *tool = gnm_chi_squared_tool_new ();
    GnmChiSquaredTool *ctool = GNM_CHI_SQUARED_TOOL (tool);
    ctool->input = input;
    ctool->labels = _hasLabels;
    ctool->alpha = _alpha;
    ctool->independence = _testsIndependence;
    return tool;
}

@end

@implementation GnmAnovaTwoFactorAnalysis

- (instancetype)init
{
    if (!(self = [super initWithTitle:@"ANOVA: Two Factor"]))
        return nil;
    _inputRange = @"";
    _alpha = 0.05;
    _rowsPerSample = 1;
    return self;
}

- (GnmAnalysisTool *)_engineToolForSheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error
{
    /* anova_two_factor_tool_update_sensitivity_cb and anova_two_factor_tool_ok_clicked_cb */
    GnmValue *input = single_range (sheet, _inputRange);
    if (!input) {
        if (error)
            *error = analysis_error (engine, @"The input range is invalid.");
        return NULL;
    }
    if (!check_alpha (_alpha, engine, error)) {
        value_release (input);
        return NULL;
    }
    if (_rowsPerSample < 1) {
        if (error)
            *error = analysis_error (engine, @"The number of rows per sample should be a positive integer.");
        value_release (input);
        return NULL;
    }
    GnmAnalysisTool *tool = gnm_anova_two_factor_tool_new ();
    GnmAnovaTwoFactorTool *atool = GNM_ANOVA_TWO_FACTOR_TOOL (tool);
    atool->input = input;
    atool->err = analysis_tools_noerr;
    atool->labels = _hasLabels;
    atool->alpha = _alpha;
    atool->replication = (gint) _rowsPerSample;
    return tool;
}

- (NSString *)_failureDescriptionForEngineTool:(GnmAnalysisTool *)tool
{
    GnmAnovaTwoFactorTool *atool = GNM_ANOVA_TWO_FACTOR_TOOL (tool);
    switch (atool->err) {
    case analysis_tools_noerr:
        return nil;
    case analysis_tools_missing_data:
        return _hasLabels ? @"The given input range should contain at least two columns and two rows of data and the labels."
                          : @"The given input range should contain at least two columns and two rows of data.";
    case analysis_tools_too_few_cols:
        return _hasLabels ? @"The given input range should contain at least two columns of data and the labels."
                          : @"The given input range should contain at least two columns of data.";
    case analysis_tools_too_few_rows:
        return _hasLabels ? @"The given input range should contain at least two rows of data and the labels."
                          : @"The given input range should contain at least two rows of data.";
    case analysis_tools_replication_invalid:
        return @"The number of data rows must be a multiple of the replication number.";
    default:
        return [NSString stringWithFormat:@"An unexpected error has occurred: %d.", atool->err];
    }
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
    /* gnm_check_for_plugins_missing, except that a plugin that is merely
     * inactive is activated here (the GTK sends the user to its plugin
     * manager) */
    for (NSString *identifier in [analysis _requiredPluginIdentifiers]) {
        GOPlugin *plugin = go_plugins_get_plugin_by_id (identifier.UTF8String);
        if (!plugin) {
            if (error)
                *error = analysis_error (engine, [NSString stringWithFormat:@"The plugin with id %@ is required but cannot be found.", identifier]);
            return nil;
        }
        if (!go_plugin_is_active (plugin)) {
            GOErrorInfo *info = NULL;
            go_plugin_activate (plugin, &info);
            if (info) {
                if (error)
                    *error = analysis_error (engine, [NSString stringWithFormat:@"The %s plugin is required but could not be loaded: %s",
                                                      go_plugin_get_name (plugin), go_error_info_peek_message (info) ?: ""]);
                go_error_info_free (info);
                return nil;
            }
        }
    }
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
