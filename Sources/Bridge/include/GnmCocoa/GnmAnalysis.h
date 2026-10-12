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
