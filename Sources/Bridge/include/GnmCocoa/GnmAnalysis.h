// The analysis tools behind the GTK Statistics menu (`tools/analysis-tools.h`,
// `analysis-regression.h`): descriptive statistics, correlation,
// covariance, and regression, each a tool object the engine's
// `cmd_analysis_tool` runs against an output description (`dao.h`), a
// new sheet or a range, as the dialogs in dialog-analysis-tools.c do.
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmGeometry.h>
#import <GnmCocoa/GnmSheet.h>

NS_ASSUME_NONNULL_BEGIN

/// How the input ranges split into variables (`gnm_tool_group_by_t`).
typedef NS_ENUM(NSInteger, GnmAnalysisGrouping) {
    GnmAnalysisGroupingRows = 0,
    GnmAnalysisGroupingColumns = 1,
    /// Each range is one variable.
    GnmAnalysisGroupingAreas = 2,
} NS_SWIFT_NAME(Analysis.Grouping);

/// Where a tool writes: the dialogs' Output page.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(AnalysisOutput)
@interface GnmAnalysisOutput : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// "Filter in-place": the rows that match stay, the others are hidden
/// (only the advanced filter takes it).
+ (instancetype)inPlace;
/// A new sheet after the others, named after the tool ("Descriptive
/// Statistics (1)"), and focused.
+ (instancetype)onNewSheet NS_SWIFT_NAME(newSheet());
/// From a cell ("F1": as much room as the tool needs) or within a range
/// ("F1:H10": cut to it), written as the dialogs take it, in the sheet
/// the tool runs on unless qualified ("Sheet2!A1").
+ (instancetype)inRangeNamed:(NSString *)text NS_SWIFT_NAME(init(rangeNamed:));
@property (nonatomic, readonly) BOOL isNewSheet;
/// Empty for a new sheet.
@property (nonatomic, readonly, copy) NSString *rangeName;
/// Fit the columns to what was written (on).
@property (nonatomic) BOOL autofitsColumns;
/// Clear the range first (on).
@property (nonatomic) BOOL clearsOutputRange;
/// Keep the range's formatting (off).
@property (nonatomic) BOOL retainsFormatting;
/// Keep the range's comments (off).
@property (nonatomic) BOOL retainsComments;
/// Enter formulas rather than their values (off).
@property (nonatomic) BOOL entersFormulas;
@end

/// A tool with its settings; `-[GnmSheet runAnalysis:output:error:]` runs it.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(Analysis)
@interface GnmAnalysis : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// The tool's name, as the undo label and a new sheet carry it.
@property (nonatomic, readonly, copy) NSString *title;
@end

/// Tools over a list of ranges split into variables.
NS_SWIFT_NAME(GroupedAnalysis)
@interface GnmGroupedAnalysis : GnmAnalysis
- (instancetype)init NS_UNAVAILABLE;
/// The input as the dialogs take it: a range ("A1:C20") or several
/// ("A1:A9, C1:C9"), in the sheet the tool runs on unless qualified.
@property (nonatomic, copy) NSString *inputRanges;
/// Columns at first.
@property (nonatomic) GnmAnalysisGrouping grouping;
/// The first cell of each variable is its label.
@property (nonatomic) BOOL hasLabels;
@end

/// Mean, standard error, median, mode, standard deviation, variance,
/// kurtosis, skewness, range, minimum, maximum, sum, and count per
/// variable, with a confidence interval for the mean and the kth
/// largest and smallest values when asked.
NS_SWIFT_NAME(DescriptiveStatistics)
@interface GnmDescriptiveStatistics : GnmGroupedAnalysis
- (instancetype)init;
/// The summary table (on).
@property (nonatomic) BOOL summaryStatistics;
/// SSMEDIAN (the median of grouped data, interval width 1) in place of MEDIAN (off).
@property (nonatomic) BOOL usesSSMedian;
/// A confidence interval for the mean at this level (0.95), or nil for none.
@property (nonatomic, copy, nullable) NSNumber *confidenceLevel;
/// The kth largest value, or nil for none.
@property (nonatomic, copy, nullable) NSNumber *kthLargest;
/// The kth smallest value, or nil for none.
@property (nonatomic, copy, nullable) NSNumber *kthSmallest;
@end

/// The correlation matrix of the variables.
NS_SWIFT_NAME(CorrelationAnalysis)
@interface GnmCorrelationAnalysis : GnmGroupedAnalysis
- (instancetype)init;
@end

/// The covariance matrix of the variables.
NS_SWIFT_NAME(CovarianceAnalysis)
@interface GnmCovarianceAnalysis : GnmGroupedAnalysis
- (instancetype)init;
@end

/// Least squares with the regression statistics, the ANOVA table, and
/// the coefficients with their standard errors, t statistics, p-values,
/// and confidence bounds.
NS_SWIFT_NAME(RegressionAnalysis)
@interface GnmRegressionAnalysis : GnmAnalysis
- (instancetype)init;
/// The x variables, one per column (or per row when the y is a row).
@property (nonatomic, copy) NSString *xRange;
/// The y variable: a vector (n by 1 or 1 by n) the length of the x
/// variables; with `hasMultipleY` the roles swap, the y range holding
/// several variables and the x range one.
@property (nonatomic, copy) NSString *yRange;
/// The first cell of each variable is its label.
@property (nonatomic) BOOL hasLabels;
/// 0.95 at first.
@property (nonatomic) double confidenceLevel;
@property (nonatomic) BOOL forcesZeroIntercept;
@property (nonatomic) BOOL calculatesResiduals;
/// One multiple linear regression (on), or a 2-variable regression for
/// each variable in the range of several.
@property (nonatomic) BOOL isMultipleLinear;
/// Several y variables regressed on one x: the GTK dialog's "Multiple
/// dependent (y) variables".
@property (nonatomic) BOOL hasMultipleY;
@end

/// Tools over two ranges (variable 1 and variable 2) with a
/// significance level.
NS_SWIFT_NAME(TwoSampleAnalysis)
@interface GnmTwoSampleAnalysis : GnmAnalysis
- (instancetype)init NS_UNAVAILABLE;
@property (nonatomic, copy) NSString *firstRange;
@property (nonatomic, copy) NSString *secondRange;
/// The first cell of each variable is its label.
@property (nonatomic) BOOL hasLabels;
/// 0.05 at first.
@property (nonatomic) double alpha;
@end

/// mean-tests.ui: paired, unpaired with known population variances (a
/// z-test), unpaired with equal or with unequal unknown variances.
typedef NS_ENUM(NSInteger, GnmMeanTestKind) {
    GnmMeanTestPaired = 0,
    GnmMeanTestKnownVariances,
    GnmMeanTestEqualVariances,
    GnmMeanTestUnequalVariances,
} NS_SWIFT_NAME(MeanTestAnalysis.Kind);

/// Claims About Two Means: the t-tests and the z-test.
NS_SWIFT_NAME(MeanTestAnalysis)
@interface GnmMeanTestAnalysis : GnmTwoSampleAnalysis
- (instancetype)init;
/// Unequal variances at first.
@property (nonatomic) GnmMeanTestKind kind;
/// 0 at first.
@property (nonatomic) double hypothesizedMeanDifference;
/// The population variances for the known-variances kind; both positive.
@property (nonatomic) double firstVariance;
@property (nonatomic) double secondVariance;
@end

/// Claims About Two Variances: the F-test.
NS_SWIFT_NAME(VarianceTestAnalysis)
@interface GnmVarianceTestAnalysis : GnmTwoSampleAnalysis
- (instancetype)init;
@end

/// ANOVA: Single Factor.
NS_SWIFT_NAME(AnovaSingleFactorAnalysis)
@interface GnmAnovaSingleFactorAnalysis : GnmGroupedAnalysis
- (instancetype)init;
/// 0.05 at first.
@property (nonatomic) double alpha;
@end

/// Rank and Percentile.
NS_SWIFT_NAME(RankingAnalysis)
@interface GnmRankingAnalysis : GnmGroupedAnalysis
- (instancetype)init;
/// Tied values share the average rank rather than the top one (off).
@property (nonatomic) BOOL averagesTies;
@end

/// Sampling: random samples, or every period-th value from an offset.
NS_SWIFT_NAME(SamplingAnalysis)
@interface GnmSamplingAnalysis : GnmGroupedAnalysis
- (instancetype)init;
@property (nonatomic) BOOL isPeriodic;
/// Periodic: the period (1) and the offset (0), taken row-major or column-major.
@property (nonatomic) NSInteger period;
@property (nonatomic) NSInteger offset;
@property (nonatomic) BOOL isRowMajor;
/// The size of each sample (1): random draws, or values a period apart.
@property (nonatomic) NSInteger sampleSize;
/// How many samples (1).
@property (nonatomic) NSInteger sampleCount;
@end

typedef NS_ENUM(NSInteger, GnmMovingAverageKind) {
    GnmMovingAverageSimple = 0,
    GnmMovingAverageCumulative,
    GnmMovingAverageWeighted,
    /// Spencer's 15-point moving average.
    GnmMovingAverageSpencer,
} NS_SWIFT_NAME(MovingAverageAnalysis.Kind);

/// Moving Average.
NS_SWIFT_NAME(MovingAverageAnalysis)
@interface GnmMovingAverageAnalysis : GnmGroupedAnalysis
- (instancetype)init;
@property (nonatomic) GnmMovingAverageKind kind;
/// Simple and weighted: the interval (3).
@property (nonatomic) NSInteger interval;
/// Simple: a central average (the offset half the interval) rather than
/// the prior one or the offset given.
@property (nonatomic) BOOL isCentral;
@property (nonatomic) NSInteger offset;
/// Standard errors with the denominator n (0), n−1 (1), or n−2 (2).
@property (nonatomic) BOOL includesStandardErrors;
@property (nonatomic) NSInteger denominatorOffset;
/// A chart of the data and the averages on the output sheet.
@property (nonatomic) BOOL includesChart;
@end

typedef NS_ENUM(NSInteger, GnmExponentialSmoothingKind) {
    /// Simple exponential smoothing (Hunter, 1986).
    GnmExponentialSmoothingSimpleHunter = 0,
    /// Simple exponential smoothing (Roberts, 1959).
    GnmExponentialSmoothingSimpleRoberts,
    /// Holt's trend corrected exponential smoothing.
    GnmExponentialSmoothingHoltTrend,
    GnmExponentialSmoothingAdditiveHoltWinters,
    GnmExponentialSmoothingMultiplicativeHoltWinters,
} NS_SWIFT_NAME(ExponentialSmoothingAnalysis.Kind);

/// Exponential Smoothing.
NS_SWIFT_NAME(ExponentialSmoothingAnalysis)
@interface GnmExponentialSmoothingAnalysis : GnmGroupedAnalysis
- (instancetype)init;
@property (nonatomic) GnmExponentialSmoothingKind kind;
/// α (0.2), γ for the trend kinds (0.2), δ and the period for the
/// seasonal kinds (0.2, 12); the factors between 0 and 1.
@property (nonatomic) double dampingFactor;
@property (nonatomic) double growthDampingFactor;
@property (nonatomic) double seasonalDampingFactor;
@property (nonatomic) NSInteger seasonalPeriod;
/// Standard errors with the denominator n (0), n−1 (1), n−2 (2), or n−3 (3).
@property (nonatomic) BOOL includesStandardErrors;
@property (nonatomic) NSInteger denominatorOffset;
@property (nonatomic) BOOL includesChart;
@end

/// frequency.ui's chart choices.
typedef NS_ENUM(NSInteger, GnmFrequencyChart) {
    GnmFrequencyChartNone = 0,
    GnmFrequencyChartBar,
    GnmFrequencyChartColumn,
} NS_SWIFT_NAME(FrequencyAnalysis.Chart);

/// Frequency Tables: how often each category occurs in each variable.
NS_SWIFT_NAME(FrequencyAnalysis)
@interface GnmFrequencyAnalysis : GnmGroupedAnalysis
- (instancetype)init;
/// The categories as a range; nil (the default) takes `categoryCount`
/// of them from the data.
@property (nonatomic, copy, nullable) NSString *categoryRange;
/// 10 at first.
@property (nonatomic) NSInteger categoryCount;
@property (nonatomic) BOOL asPercentages;
/// "Use exact comparisons": a value counts only when it equals a
/// category.
@property (nonatomic) BOOL exactMatches;
@property (nonatomic) GnmFrequencyChart chart;
@end

/// histogram.ui's chart choices.
typedef NS_ENUM(NSInteger, GnmHistogramChart) {
    GnmHistogramChartNone = 0,
    GnmHistogramChartHistogram,
    GnmHistogramChartBar,
    GnmHistogramChartColumn,
} NS_SWIFT_NAME(HistogramAnalysis.Chart);

/// Histogram: counts of each variable's values between cutoffs.
NS_SWIFT_NAME(HistogramAnalysis)
@interface GnmHistogramAnalysis : GnmGroupedAnalysis
- (instancetype)init;
/// The cutoffs as a range; nil (the default) calculates `cutoffCount`
/// of them between `minimum` and `maximum`, each the data's when nil.
@property (nonatomic, copy, nullable) NSString *cutoffRange;
/// 10 at first.
@property (nonatomic) NSInteger cutoffCount;
@property (nonatomic, copy, nullable) NSNumber *minimum;
@property (nonatomic, copy, nullable) NSNumber *maximum;
/// histogram.ui's bin types: each bin takes its upper cutoff, (∙,∙],
/// rather than its lower, [∙,∙); the first bin reaches down to −∞; the
/// last reaches up to +∞.  All off at first.
@property (nonatomic) BOOL binsIncludeUpperCutoff;
@property (nonatomic) BOOL firstBinFromMinusInfinity;
@property (nonatomic) BOOL lastBinToPlusInfinity;
@property (nonatomic) BOOL asPercentages;
@property (nonatomic) BOOL cumulative;
/// Count only numbers (not dates and so on).
@property (nonatomic) BOOL onlyNumbers;
@property (nonatomic) GnmHistogramChart chart;
@end

/// normality-tests.ui's tests.
typedef NS_ENUM(NSInteger, GnmNormalityTestKind) {
    GnmNormalityTestAndersonDarling = 0,
    GnmNormalityTestCramerVonMises,
    GnmNormalityTestLilliefors,
    GnmNormalityTestShapiroFrancia,
} NS_SWIFT_NAME(NormalityAnalysis.Kind);

/// Normality Tests.
NS_SWIFT_NAME(NormalityAnalysis)
@interface GnmNormalityAnalysis : GnmGroupedAnalysis
- (instancetype)init;
/// Anderson-Darling at first.
@property (nonatomic) GnmNormalityTestKind kind;
/// 0.05 at first.
@property (nonatomic) double alpha;
/// "Create Normal Probability Plot".
@property (nonatomic) BOOL includesProbabilityPlot;
@end

/// Claims About a Mean: the one-sample t-test of each variable.
NS_SWIFT_NAME(OneMeanTestAnalysis)
@interface GnmOneMeanTestAnalysis : GnmGroupedAnalysis
- (instancetype)init;
/// 0 at first.
@property (nonatomic) double hypothesizedMean;
/// 0.05 at first.
@property (nonatomic) double alpha;
@end

/// sign-test.ui's tests.
typedef NS_ENUM(NSInteger, GnmMedianTestKind) {
    GnmMedianTestSign = 0,
    GnmMedianTestWilcoxonSignedRank,
} NS_SWIFT_NAME(MedianTestAnalysis.Kind);

/// Claims About a Median: the sign test or the Wilcoxon signed rank test
/// of each variable.
NS_SWIFT_NAME(MedianTestAnalysis)
@interface GnmMedianTestAnalysis : GnmGroupedAnalysis
- (instancetype)init;
/// The sign test at first.
@property (nonatomic) GnmMedianTestKind kind;
/// 0 at first.
@property (nonatomic) double hypothesizedMedian;
/// 0.05 at first.
@property (nonatomic) double alpha;
@end

/// Claims About Two Medians, paired: the sign test or the Wilcoxon
/// signed rank test of the differences between two variables of the
/// same shape.
NS_SWIFT_NAME(TwoMedianTestAnalysis)
@interface GnmTwoMedianTestAnalysis : GnmTwoSampleAnalysis
- (instancetype)init;
/// The sign test at first.
@property (nonatomic) GnmMedianTestKind kind;
/// The hypothesized median of the differences; 0 at first.
@property (nonatomic) double hypothesizedMedian;
@end

/// The Wilcoxon-Mann-Whitney test of two independent variables.
NS_SWIFT_NAME(MannWhitneyAnalysis)
@interface GnmMannWhitneyAnalysis : GnmTwoSampleAnalysis
- (instancetype)init;
@end

/// Principal Components Analysis of the variables.
NS_SWIFT_NAME(PrincipalComponentsAnalysis)
@interface GnmPrincipalComponentsAnalysis : GnmGroupedAnalysis
- (instancetype)init;
@end

/// Fourier Analysis of each variable.
NS_SWIFT_NAME(FourierAnalysis)
@interface GnmFourierAnalysis : GnmGroupedAnalysis
- (instancetype)init;
/// The inverse transform.
@property (nonatomic) BOOL isInverse;
@end

/// One group of the Kaplan-Meier tool: the records whose group value
/// lies between `from` and `to`.
NS_SWIFT_NAME(KaplanMeierGroup)
@interface GnmKaplanMeierGroup : NSObject
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithName:(NSString *)name from:(NSInteger)from to:(NSInteger)to NS_SWIFT_NAME(init(name:from:to:));
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) NSInteger from;
@property (nonatomic, readonly) NSInteger to;
@end

/// Kaplan-Meier Estimates of a survival function.
NS_SWIFT_NAME(KaplanMeierAnalysis)
@interface GnmKaplanMeierAnalysis : GnmAnalysis
- (instancetype)init;
/// One column of times.
@property (nonatomic, copy) NSString *timeRange;
/// One column of the same height marking censored records with a value
/// from `censorMark` to `censorMarkTo`; nil (the default) for no
/// censoring.
@property (nonatomic, copy, nullable) NSString *censorRange;
@property (nonatomic) NSInteger censorMark;
@property (nonatomic) NSInteger censorMarkTo;
/// One column of the same height with each record's group, and the
/// groups to estimate; nil and empty (the defaults) for one estimate.
@property (nonatomic, copy, nullable) NSString *groupRange;
@property (nonatomic, copy) NSArray<GnmKaplanMeierGroup *> *groups;
/// With groups, the log-rank test between them.
@property (nonatomic) BOOL logRankTest;
@property (nonatomic) BOOL includesChart;
/// Censorship ticks on the chart.
@property (nonatomic) BOOL includesTicks;
@property (nonatomic) BOOL includesStandardErrors;
@property (nonatomic) BOOL includesMedian;
@end

/// Contingency Table: the chi-squared Test of Homogeneity or Test of
/// Independence over a table of counts.
NS_SWIFT_NAME(ContingencyTableAnalysis)
@interface GnmContingencyTableAnalysis : GnmAnalysis
- (instancetype)init;
/// The table, at least two rows and two columns (plus the labels).
@property (nonatomic, copy) NSString *inputRange;
/// The first row and column are labels.
@property (nonatomic) BOOL hasLabels;
/// Independence rather than homogeneity; NO at first.
@property (nonatomic) BOOL testsIndependence;
/// 0.05 at first.
@property (nonatomic) double alpha;
@end

/// ANOVA: Two Factor, with or without replication.
NS_SWIFT_NAME(AnovaTwoFactorAnalysis)
@interface GnmAnovaTwoFactorAnalysis : GnmAnalysis
- (instancetype)init;
/// The table: one factor's levels across the columns, the other's down
/// the rows, `rowsPerSample` rows for each.
@property (nonatomic, copy) NSString *inputRange;
/// The first row and column are labels.
@property (nonatomic) BOOL hasLabels;
/// 0.05 at first.
@property (nonatomic) double alpha;
/// 1 at first (no replication).
@property (nonatomic) NSInteger rowsPerSample;
@end

/// random-generator.h's distributions, the engine's values.
typedef NS_ENUM(NSInteger, GnmRandomDistribution) {
    GnmRandomDistributionDiscrete = 0,
    GnmRandomDistributionUniform,
    GnmRandomDistributionNormal,
    GnmRandomDistributionBernoulli,
    GnmRandomDistributionBeta,
    GnmRandomDistributionBinomial,
    GnmRandomDistributionPoisson,
    GnmRandomDistributionCauchy,
    GnmRandomDistributionChiSquared,
    GnmRandomDistributionGamma,
    GnmRandomDistributionWeibull,
    GnmRandomDistributionF,
    GnmRandomDistributionGeometric,
    GnmRandomDistributionGumbel1,
    GnmRandomDistributionGumbel2,
    GnmRandomDistributionLaplace,
    GnmRandomDistributionStudentT,
    GnmRandomDistributionLogarithmic,
    GnmRandomDistributionLogistic,
    GnmRandomDistributionPareto,
    GnmRandomDistributionLognormal,
    GnmRandomDistributionRayleigh,
    GnmRandomDistributionLevy,
    GnmRandomDistributionExponentialPower,
    GnmRandomDistributionRayleighTail,
    GnmRandomDistributionLandau,
    GnmRandomDistributionGaussianTail,
    GnmRandomDistributionUniformInteger,
    GnmRandomDistributionNegativeBinomial,
    GnmRandomDistributionExponential,
} NS_SWIFT_NAME(RandomNumbersAnalysis.Distribution);

/// Data → Fill → Random Generator → Uncorrelated…: `variableCount`
/// columns of `count` numbers from one distribution, its one or two
/// parameters in the dialog's order (random-generation.ui).
NS_SWIFT_NAME(RandomNumbersAnalysis)
@interface GnmRandomNumbersAnalysis : GnmAnalysis
- (instancetype)init;
/// Uniform at first.
@property (nonatomic) GnmRandomDistribution distribution;
/// 1 at first.
@property (nonatomic) NSInteger variableCount;
/// 10 at first.
@property (nonatomic) NSInteger count;
/// The dialog's first and second entries (lower and upper bound, mean
/// and standard deviation, a and b, p and the number of trials, …).
@property (nonatomic) double firstParameter;
@property (nonatomic) double secondParameter;
/// Discrete: the two-column range of values and their probabilities.
@property (nonatomic, copy, nullable) NSString *valueRange;
/// The dialog's order: the common ones first, then alphabetical.
@property (class, nonatomic, readonly) NSArray<NSNumber *> *allDistributions;
+ (NSString *)labelForDistribution:(GnmRandomDistribution)distribution NS_SWIFT_NAME(label(for:));
/// The entries' labels, nil for one the distribution lacks.
+ (nullable NSString *)firstParameterLabelForDistribution:(GnmRandomDistribution)distribution NS_SWIFT_NAME(firstParameterLabel(for:));
+ (nullable NSString *)secondParameterLabelForDistribution:(GnmRandomDistribution)distribution NS_SWIFT_NAME(secondParameterLabel(for:));
@end

/// Data → Fill → Random Generator → Correlated…: `count` rows of
/// normal numbers with a covariance matrix, given as the matrix itself
/// or its Cholesky factor (random-generation-cor.ui).
NS_SWIFT_NAME(CorrelatedRandomNumbersAnalysis)
@interface GnmCorrelatedRandomNumbersAnalysis : GnmAnalysis
- (instancetype)init;
/// A square range.
@property (nonatomic, copy) NSString *matrixRange;
/// The range holds the Cholesky decomposition rather than the covariance matrix; NO at first.
@property (nonatomic) BOOL isCholesky;
/// 2 at first.
@property (nonatomic) NSInteger count;
@end

/// Data → Filter → Advanced Filter… (dialog-advanced-filter.c): the
/// rows of a list whose values meet the criteria, as a database
/// function reads them (a header row, then conditions), left in place
/// with the rest hidden, or copied to a range or a new sheet.
NS_SWIFT_NAME(AdvancedFilter)
@interface GnmAdvancedFilter : GnmAnalysis
- (instancetype)init;
/// The list with its header row.
@property (nonatomic, copy) NSString *listRange;
/// The criteria: field names over conditions.
@property (nonatomic, copy) NSString *criteriaRange;
/// "Unique records only".
@property (nonatomic) BOOL uniqueOnly;
@end

@interface GnmSheet (Filtering)
/// Run the filter: in place (`advanced_filter`, not undoable; Data →
/// Filter → Show All brings the rows back) or as an analysis tool to the
/// output.  NO with the dialog's messages: an invalid range, criteria
/// that do not parse, no matching records.
- (BOOL)applyAdvancedFilter:(GnmAdvancedFilter *)filter output:(GnmAnalysisOutput *)output error:(NSError **)error
    NS_SWIFT_NAME(applyAdvancedFilter(_:output:));
@end

/// consolidate.ui's functions, in its order.
typedef NS_ENUM(NSInteger, GnmConsolidateFunction) {
    GnmConsolidateFunctionSum = 0,
    GnmConsolidateFunctionMin,
    GnmConsolidateFunctionMax,
    GnmConsolidateFunctionAverage,
    GnmConsolidateFunctionCount,
    GnmConsolidateFunctionProduct,
    GnmConsolidateFunctionStandardDeviation,
    GnmConsolidateFunctionPopulationStandardDeviation,
    GnmConsolidateFunctionVariance,
    GnmConsolidateFunctionPopulationVariance,
} NS_SWIFT_NAME(ConsolidateAnalysis.Function);

/// Data → Consolidate… (dialog-consolidate.c): one function over the
/// matching cells of several source areas, by position or by the labels
/// in their top row or left column.  The output's values-or-formulas
/// choice decides whether the results are written as values.
NS_SWIFT_NAME(ConsolidateAnalysis)
@interface GnmConsolidateAnalysis : GnmAnalysis
- (instancetype)init;
/// SUM at first.
@property (nonatomic) GnmConsolidateFunction function;
/// The source areas, each a range in the sheet's syntax.
@property (nonatomic, copy) NSArray<NSString *> *sourceRanges;
/// "Labels in top row": the top row holds keys, not data.
@property (nonatomic) BOOL hasTopRowLabels;
/// "Labels in left column".
@property (nonatomic) BOOL hasLeftColumnLabels;
/// "Copy labels" into the output.
@property (nonatomic) BOOL copiesLabels;
@end

/// Data → Shuffle… (dialog-shuffle.c): how a range's cells are mixed.
typedef NS_ENUM(NSInteger, GnmShuffleKind) {
    /// Each column's cells among themselves.
    GnmShuffleColumns = 0,
    /// Each row's cells among themselves.
    GnmShuffleRows,
    /// All the cells.
    GnmShuffleArea,
} NS_SWIFT_NAME(Sheet.ShuffleKind);

@interface GnmSheet (Shuffling)
/// Shuffle a range in place (`cmd_data_shuffle`, "Shuffled", undoable).
- (BOOL)shuffleRange:(NSString *)rangeText by:(GnmShuffleKind)kind error:(NSError **)error NS_SWIFT_NAME(shuffle(_:by:));
@end

@interface GnmSheet (Analysis)
/// Run a tool with its ranges read relative to this sheet, writing as the
/// output says, as one undoable command named for the tool.  The sheet
/// written to (a new one is attached after the others and focused), or
/// nil with the dialogs' message when the input, the output, or the
/// tool refuses.
- (nullable GnmSheet *)runAnalysis:(GnmAnalysis *)analysis output:(GnmAnalysisOutput *)output
                             error:(NSError **)error NS_SWIFT_NAME(run(_:output:));
/// The ranges in a list as the dialogs read it ("A1:B5, D1:D5"), each
/// named in full ("A1:B5", "Sheet2!D1:D5"); nil when the text is not a
/// list of ranges.
- (nullable NSArray<NSString *> *)rangeNamesInList:(NSString *)text NS_SWIFT_NAME(rangeNames(inList:));
@end

NS_ASSUME_NONNULL_END
