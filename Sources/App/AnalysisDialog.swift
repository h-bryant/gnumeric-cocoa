import AppKit
import GnmCocoa

/// The GTK analysis tool dialogs (dialog-analysis-tools.c) as alert sheets:
/// the Input page (the ranges, their grouping, labels), the tool's own
/// page, and the Output page (a new sheet or a range, with its
/// formatting choices).  A refused run re-presents the sheet with its
/// values kept, as the GTK dialogs stay open.
@MainActor
final class AnalysisDialog {
    enum Tool {
        case descriptiveStatistics, correlation, covariance, regression
        case meanTest, varianceTest, anovaSingleFactor, ranking, sampling, movingAverage, exponentialSmoothing
        case frequency, histogram, fourier, principalComponents, kaplanMeier
        case normality, oneMeanTest, oneMedianSignTest, oneMedianSignedRank
        case twoMedianSignTest, twoMedianSignedRank, mannWhitney
        case anovaTwoFactor, homogeneity, independence

        var title: String {
            switch self {
            case .descriptiveStatistics: return "Descriptive Statistics"
            case .correlation: return "Correlation"
            case .covariance: return "Covariance"
            case .regression: return "Regression"
            case .meanTest: return "Claims About Two Means"
            case .varianceTest: return "Claims About Two Variances"
            case .anovaSingleFactor: return "ANOVA: Single Factor"
            case .ranking: return "Rank and Percentile"
            case .sampling: return "Sampling"
            case .movingAverage: return "Moving Average"
            case .exponentialSmoothing: return "Exponential Smoothing"
            case .frequency: return "Frequency Tables"
            case .histogram: return "Histogram"
            case .fourier: return "Fourier Analysis"
            case .principalComponents: return "Principal Components Analysis"
            case .kaplanMeier: return "Kaplan-Meier Estimates"
            case .normality: return "Normality Tests"
            case .oneMeanTest: return "Claims About a Mean"
            case .oneMedianSignTest, .oneMedianSignedRank: return "Claims About a Median"
            case .twoMedianSignTest, .twoMedianSignedRank: return "Claims About Two Medians"
            case .mannWhitney: return "Wilcoxon-Mann-Whitney Test"
            case .anovaTwoFactor: return "ANOVA: Two Factor"
            case .homogeneity: return "Test of Homogeneity"
            case .independence: return "Test of Independence"
            }
        }

        /// Tools over a list of ranges split into variables.
        var isGrouped: Bool {
            switch self {
            case .descriptiveStatistics, .correlation, .covariance, .anovaSingleFactor, .ranking, .sampling, .movingAverage, .exponentialSmoothing,
                 .frequency, .histogram, .fourier, .principalComponents, .normality, .oneMeanTest, .oneMedianSignTest, .oneMedianSignedRank:
                return true
            default:
                return false
            }
        }

        /// Tools over two variables (the ttest.ui layout).
        var isTwoSample: Bool {
            switch self {
            case .meanTest, .varianceTest, .twoMedianSignTest, .twoMedianSignedRank, .mannWhitney: return true
            default: return false
            }
        }
    }

    /// For the headless checks: fill the fields and return true to run.
    nonisolated(unsafe) static var headlessDriver: ((AnalysisDialog) -> Bool)?

    let tool: Tool
    let alert = NSAlert()

    // Input
    let inputField = NSTextField(string: "")
    let grouping = NSPopUpButton(frame: .zero, pullsDown: false)
    let labels = NSButton(checkboxWithTitle: "Labels in the first row or column", target: nil, action: nil)
    // Regression
    let xField = NSTextField(string: "")
    let yField = NSTextField(string: "")
    let regressionKind = NSPopUpButton(frame: .zero, pullsDown: false)
    let multipleY = NSButton(checkboxWithTitle: "Multiple dependent (y) variables", target: nil, action: nil)
    let confidenceField = NSTextField(string: "0.95")
    let zeroIntercept = NSButton(checkboxWithTitle: "Force intercept to be zero", target: nil, action: nil)
    let residuals = NSButton(checkboxWithTitle: "Calculate residuals", target: nil, action: nil)
    // Two samples
    let alphaField = NSTextField(string: "0.05")
    let meanTestKind = NSPopUpButton(frame: .zero, pullsDown: false)
    let meanDifferenceField = NSTextField(string: "0")
    let firstVarianceField = NSTextField(string: "")
    let secondVarianceField = NSTextField(string: "")
    // Ranking
    let averageTies = NSButton(checkboxWithTitle: "Average rank for ties", target: nil, action: nil)
    // Sampling
    let samplingMethod = NSPopUpButton(frame: .zero, pullsDown: false)
    let sampleSizeField = NSTextField(string: "1")
    let sampleCountField = NSTextField(string: "1")
    let periodField = NSTextField(string: "1")
    let offsetField = NSTextField(string: "0")
    let samplingDirection = NSPopUpButton(frame: .zero, pullsDown: false)
    // Moving average and exponential smoothing
    let movingAverageKind = NSPopUpButton(frame: .zero, pullsDown: false)
    let maIntervalField = NSTextField(string: "3")
    let placement = NSPopUpButton(frame: .zero, pullsDown: false)
    let averageOffsetField = NSTextField(string: "0")
    let smoothingKind = NSPopUpButton(frame: .zero, pullsDown: false)
    let dampingField = NSTextField(string: "0.2")
    let growthField = NSTextField(string: "0.2")
    let seasonalField = NSTextField(string: "0.2")
    let seasonalPeriodField = NSTextField(string: "12")
    let standardErrors = NSButton(checkboxWithTitle: "Standard errors", target: nil, action: nil)
    let denominator = NSPopUpButton(frame: .zero, pullsDown: false)
    let chart = NSButton(checkboxWithTitle: "Include chart", target: nil, action: nil)
    // Frequency tables and histograms
    let cutoffSource = NSPopUpButton(frame: .zero, pullsDown: false)
    let cutoffRangeField = NSTextField(string: "")
    let cutoffCountField = NSTextField(string: "10")
    let minField = NSTextField(string: "")
    let maxField = NSTextField(string: "")
    let upperCutoff = NSButton(checkboxWithTitle: "Bins take their upper cutoff: (∙,∙] rather than [∙,∙)", target: nil, action: nil)
    let minusInfinity = NSButton(checkboxWithTitle: "First bin reaches down to −∞", target: nil, action: nil)
    let plusInfinity = NSButton(checkboxWithTitle: "Last bin reaches up to +∞", target: nil, action: nil)
    let percentage = NSButton(checkboxWithTitle: "Percentages", target: nil, action: nil)
    let cumulative = NSButton(checkboxWithTitle: "Cumulative answers", target: nil, action: nil)
    let onlyNumbers = NSButton(checkboxWithTitle: "Count numbers only", target: nil, action: nil)
    let exact = NSButton(checkboxWithTitle: "Use exact comparisons", target: nil, action: nil)
    let chartKind = NSPopUpButton(frame: .zero, pullsDown: false)
    // One-sample and two-sample tests
    let normalityKind = NSPopUpButton(frame: .zero, pullsDown: false)
    let probabilityPlot = NSButton(checkboxWithTitle: "Create normal probability plot", target: nil, action: nil)
    let meanField = NSTextField(string: "0")
    let medianField = NSTextField(string: "0")
    let medianKind = NSPopUpButton(frame: .zero, pullsDown: false)
    // Fourier, Kaplan-Meier
    let inverse = NSButton(checkboxWithTitle: "Inverse transform", target: nil, action: nil)
    let timeField = NSTextField(string: "")
    let censorField = NSTextField(string: "")
    let censorFromField = NSTextField(string: "0")
    let censorToField = NSTextField(string: "0")
    let groupsRangeField = NSTextField(string: "")
    let groupsField = NSTextField(string: "")
    let kmChart = NSButton(checkboxWithTitle: "Chart", target: nil, action: nil)
    let kmTicks = NSButton(checkboxWithTitle: "Censorship ticks on the chart", target: nil, action: nil)
    let kmStandardErrors = NSButton(checkboxWithTitle: "Standard errors", target: nil, action: nil)
    let kmMedian = NSButton(checkboxWithTitle: "Median", target: nil, action: nil)
    let logRank = NSButton(checkboxWithTitle: "Log-rank test between the groups", target: nil, action: nil)
    // Tables
    let chiKind = NSPopUpButton(frame: .zero, pullsDown: false)
    let replicationField = NSTextField(string: "1")
    // Descriptive statistics
    let summary = NSButton(checkboxWithTitle: "Summary statistics", target: nil, action: nil)
    let ssmedian = NSButton(checkboxWithTitle: "Use SSMEDIAN for the median", target: nil, action: nil)
    let confidenceInterval = NSButton(checkboxWithTitle: "Confidence interval for the mean, 1 − α:", target: nil, action: nil)
    let intervalField = NSTextField(string: "0.95")
    let kthLargest = NSButton(checkboxWithTitle: "Kth largest, K:", target: nil, action: nil)
    let largestField = NSTextField(string: "1")
    let kthSmallest = NSButton(checkboxWithTitle: "Kth smallest, K:", target: nil, action: nil)
    let smallestField = NSTextField(string: "1")
    // Output
    let destination = NSPopUpButton(frame: .zero, pullsDown: false)
    let outputField = NSTextField(string: "")
    let autofit = NSButton(checkboxWithTitle: "Autofit columns", target: nil, action: nil)
    let clear = NSButton(checkboxWithTitle: "Clear output range", target: nil, action: nil)
    let retainFormatting = NSButton(checkboxWithTitle: "Retain output range formatting", target: nil, action: nil)
    let retainComments = NSButton(checkboxWithTitle: "Retain output range comments", target: nil, action: nil)
    let entered = NSPopUpButton(frame: .zero, pullsDown: false)

    init(tool: Tool, sheet: Sheet) {
        self.tool = tool
        alert.messageText = tool.title
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        let selection = sheet.rangeNames(inList: sheet.selectionText)?.joined(separator: ", ") ?? ""
        inputField.stringValue = selection
        xField.stringValue = selection
        grouping.addItems(withTitles: ["Columns", "Rows", "Areas"])
        regressionKind.addItems(withTitles: ["Multiple linear regression", "Multiple 2-variable regressions"])
        summary.state = .on
        destination.addItems(withTitles: ["New sheet", "Output range:"])
        autofit.state = .on
        clear.state = .on
        entered.addItems(withTitles: ["Values", "Formulas"])
        meanTestKind.addItems(withTitles: ["Paired", "Unpaired, known population variances", "Unpaired, equal variances", "Unpaired, unequal variances"])
        meanTestKind.selectItem(at: 3)
        samplingMethod.addItems(withTitles: ["Random", "Periodic"])
        samplingDirection.addItems(withTitles: ["Column major", "Row major"])
        movingAverageKind.addItems(withTitles: ["Simple moving average", "Cumulative moving average", "Weighted moving average", "Spencer's 15-point moving average"])
        placement.addItems(withTitles: ["Prior moving average", "Central moving average", "Other offset"])
        smoothingKind.addItems(withTitles: ["Simple exponential smoothing (Hunter, 1986)", "Simple exponential smoothing (Roberts, 1959)",
                                            "Holt's trend corrected exponential smoothing", "Additive Holt-Winters exponential smoothing",
                                            "Multiplicative Holt-Winters exponential smoothing"])
        denominator.addItems(withTitles: ["n", "n − 1", "n − 2", "n − 3"])
        cutoffSource.addItems(withTitles: tool == .frequency ? ["Counted from the data", "From a range:"] : ["Calculated", "From a range:"])
        chartKind.addItems(withTitles: tool == .frequency ? ["No chart", "Bar chart", "Column chart"]
                                                          : ["No chart", "Histogram chart", "Bar chart", "Column chart"])
        normalityKind.addItems(withTitles: ["Anderson-Darling test", "Cramér-von Mises test", "Lilliefors (Kolmogorov-Smirnov) test", "Shapiro-Francia test"])
        medianKind.addItems(withTitles: ["Sign test", "Wilcoxon signed rank test"])
        medianKind.selectItem(at: tool == .oneMedianSignedRank || tool == .twoMedianSignedRank ? 1 : 0)
        chiKind.addItems(withTitles: ["Test of homogeneity", "Test of independence"])
        chiKind.selectItem(at: tool == .independence ? 1 : 0)
        timeField.stringValue = selection
        for field in [inputField, xField, yField, outputField, cutoffRangeField, timeField, censorField, groupsRangeField, groupsField] {
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        }
        for field in [confidenceField, intervalField, largestField, smallestField, alphaField, meanDifferenceField, firstVarianceField,
                      secondVarianceField, sampleSizeField, sampleCountField, periodField, offsetField, maIntervalField, averageOffsetField,
                      dampingField, growthField, seasonalField, seasonalPeriodField, cutoffCountField, minField, maxField, meanField,
                      medianField, censorFromField, censorToField, replicationField] {
            field.widthAnchor.constraint(equalToConstant: 70).isActive = true
        }
        alert.accessoryView = makeGrid()
        alert.window.initialFirstResponder = tool.isGrouped ? inputField : (tool == .kaplanMeier ? timeField : xField)
    }

    private func makeGrid() -> NSGridView {
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.alignment = .right
            return field
        }
        func heading(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            return field
        }
        func pair(_ check: NSButton, _ field: NSTextField) -> NSStackView {
            let stack = NSStackView(views: [check, field])
            stack.orientation = .horizontal
            stack.spacing = 6
            return stack
        }
        var rows: [[NSView]] = [[heading("Input"), NSGridCell.emptyContentView]]
        switch tool {
        case .regression:
            rows += [[label("X variables:"), xField], [label("Y variable:"), yField],
                     [NSGridCell.emptyContentView, labels], [NSGridCell.emptyContentView, multipleY],
                     [heading("Options"), NSGridCell.emptyContentView],
                     [label("Model:"), regressionKind], [label("Confidence level:"), confidenceField],
                     [NSGridCell.emptyContentView, zeroIntercept], [NSGridCell.emptyContentView, residuals]]
        case .meanTest:
            rows += [[label("Variable 1 range:"), xField], [label("Variable 2 range:"), yField], [NSGridCell.emptyContentView, labels],
                     [heading("Test"), NSGridCell.emptyContentView],
                     [label("Variables are:"), meanTestKind],
                     [label("Variable 1 population variance:"), firstVarianceField], [label("Variable 2 population variance:"), secondVarianceField],
                     [label("Hypothesized mean difference:"), meanDifferenceField], [label("Alpha:"), alphaField]]
        case .varianceTest:
            rows += [[label("Variable 1 range:"), xField], [label("Variable 2 range:"), yField], [NSGridCell.emptyContentView, labels],
                     [heading("Test"), NSGridCell.emptyContentView], [label("Alpha:"), alphaField]]
        case .twoMedianSignTest, .twoMedianSignedRank:
            rows += [[label("Variable 1 range:"), xField], [label("Variable 2 range:"), yField], [NSGridCell.emptyContentView, labels],
                     [heading("Test"), NSGridCell.emptyContentView], [label("Test:"), medianKind],
                     [label("Predicted difference:"), medianField], [label("Alpha:"), alphaField]]
        case .mannWhitney:
            rows += [[label("Variable 1 range:"), xField], [label("Variable 2 range:"), yField], [NSGridCell.emptyContentView, labels]]
        case .kaplanMeier:
            rows += [[label("Time column:"), timeField], [label("Censorship column:"), censorField],
                     [label("Censor marks from:"), censorFromField], [label("to:"), censorToField],
                     [label("Groups column:"), groupsRangeField], [label("Groups (name from to; …):"), groupsField],
                     [heading("Options"), NSGridCell.emptyContentView],
                     [NSGridCell.emptyContentView, kmChart], [NSGridCell.emptyContentView, kmTicks],
                     [NSGridCell.emptyContentView, kmStandardErrors], [NSGridCell.emptyContentView, kmMedian],
                     [NSGridCell.emptyContentView, logRank]]
        case .anovaTwoFactor:
            rows += [[label("Input range:"), inputField], [NSGridCell.emptyContentView, labels],
                     [heading("Options"), NSGridCell.emptyContentView],
                     [label("Rows per sample:"), replicationField], [label("Alpha:"), alphaField]]
        case .homogeneity, .independence:
            rows += [[label("Input range:"), inputField], [NSGridCell.emptyContentView, labels],
                     [heading("Test"), NSGridCell.emptyContentView], [label("Test:"), chiKind], [label("Alpha:"), alphaField]]
        default:
            rows += [[label("Input range:"), inputField], [label("Grouped by:"), grouping], [NSGridCell.emptyContentView, labels]]
            switch tool {
            case .descriptiveStatistics:
                rows += [[heading("Statistics"), NSGridCell.emptyContentView],
                         [NSGridCell.emptyContentView, summary], [NSGridCell.emptyContentView, ssmedian],
                         [NSGridCell.emptyContentView, pair(confidenceInterval, intervalField)],
                         [NSGridCell.emptyContentView, pair(kthLargest, largestField)],
                         [NSGridCell.emptyContentView, pair(kthSmallest, smallestField)]]
            case .anovaSingleFactor:
                rows += [[heading("Options"), NSGridCell.emptyContentView], [label("Alpha:"), alphaField]]
            case .ranking:
                rows += [[heading("Options"), NSGridCell.emptyContentView], [NSGridCell.emptyContentView, averageTies]]
            case .sampling:
                rows += [[heading("Options"), NSGridCell.emptyContentView],
                         [label("Sampling method:"), samplingMethod], [label("Size of sample:"), sampleSizeField],
                         [label("Number of samples:"), sampleCountField], [label("Period:"), periodField],
                         [label("Offset:"), offsetField], [label("Primary direction:"), samplingDirection]]
            case .movingAverage:
                rows += [[heading("Options"), NSGridCell.emptyContentView],
                         [label("Average:"), movingAverageKind], [label("Interval:"), maIntervalField],
                         [label("Placement:"), placement], [label("Offset:"), averageOffsetField],
                         [NSGridCell.emptyContentView, standardErrors], [label("Denominator:"), denominator],
                         [NSGridCell.emptyContentView, chart]]
            case .exponentialSmoothing:
                rows += [[heading("Options"), NSGridCell.emptyContentView],
                         [label("Smoothing:"), smoothingKind], [label("Damping factor (α):"), dampingField],
                         [label("Growth damping factor (γ):"), growthField], [label("Seasonal damping factor (δ):"), seasonalField],
                         [label("Seasonal period:"), seasonalPeriodField],
                         [NSGridCell.emptyContentView, standardErrors], [label("Denominator:"), denominator],
                         [NSGridCell.emptyContentView, chart]]
            case .frequency:
                rows += [[heading("Categories"), NSGridCell.emptyContentView],
                         [label("Categories:"), cutoffSource], [NSGridCell.emptyContentView, cutoffRangeField],
                         [label("Number of categories:"), cutoffCountField],
                         [heading("Options"), NSGridCell.emptyContentView],
                         [NSGridCell.emptyContentView, exact], [NSGridCell.emptyContentView, percentage],
                         [label("Chart:"), chartKind]]
            case .histogram:
                rows += [[heading("Cutoffs"), NSGridCell.emptyContentView],
                         [label("Cutoffs:"), cutoffSource], [NSGridCell.emptyContentView, cutoffRangeField],
                         [label("Number of cutoffs:"), cutoffCountField], [label("Minimum:"), minField], [label("Maximum:"), maxField],
                         [heading("Bins"), NSGridCell.emptyContentView],
                         [NSGridCell.emptyContentView, upperCutoff], [NSGridCell.emptyContentView, minusInfinity],
                         [NSGridCell.emptyContentView, plusInfinity],
                         [heading("Options"), NSGridCell.emptyContentView],
                         [NSGridCell.emptyContentView, percentage], [NSGridCell.emptyContentView, cumulative],
                         [NSGridCell.emptyContentView, onlyNumbers], [label("Chart:"), chartKind]]
            case .fourier:
                rows += [[heading("Options"), NSGridCell.emptyContentView], [NSGridCell.emptyContentView, inverse]]
            case .normality:
                rows += [[heading("Test"), NSGridCell.emptyContentView],
                         [label("Test:"), normalityKind], [label("Alpha:"), alphaField], [NSGridCell.emptyContentView, probabilityPlot]]
            case .oneMeanTest:
                rows += [[heading("Test"), NSGridCell.emptyContentView],
                         [label("Predicted mean:"), meanField], [label("Alpha:"), alphaField]]
            case .oneMedianSignTest, .oneMedianSignedRank:
                rows += [[heading("Test"), NSGridCell.emptyContentView],
                         [label("Test:"), medianKind], [label("Predicted median:"), medianField], [label("Alpha:"), alphaField]]
            default:
                break
            }
        }
        rows += [[heading("Output"), NSGridCell.emptyContentView],
                 [label("Place in:"), destination], [NSGridCell.emptyContentView, outputField],
                 [NSGridCell.emptyContentView, autofit], [NSGridCell.emptyContentView, clear],
                 [NSGridCell.emptyContentView, retainFormatting], [NSGridCell.emptyContentView, retainComments],
                 [label("Enter into cells:"), entered]]
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        for index in 0..<grid.numberOfRows { grid.row(at: index).yPlacement = .center }
        for (index, row) in rows.enumerated() where row[1] === NSGridCell.emptyContentView && row[0] is NSTextField {
            grid.cell(atColumnIndex: 0, rowIndex: index).xPlacement = .leading
            grid.row(at: index).topPadding = index == 0 ? 0 : 8
        }
        let size = grid.fittingSize
        grid.frame = NSRect(x: 0, y: 0, width: max(size.width, 360), height: size.height)
        return grid
    }

    /// The tool as the fields describe it.
    func makeAnalysis() -> Analysis {
        switch tool {
        case .regression:
            let regression = RegressionAnalysis()
            regression.xRange = xField.stringValue
            regression.yRange = yField.stringValue
            regression.hasLabels = labels.state == .on
            regression.confidenceLevel = Double(confidenceField.stringValue) ?? -1
            regression.forcesZeroIntercept = zeroIntercept.state == .on
            regression.calculatesResiduals = residuals.state == .on
            regression.isMultipleLinear = regressionKind.indexOfSelectedItem == 0
            regression.hasMultipleY = multipleY.state == .on
            return regression
        case .descriptiveStatistics:
            let statistics = DescriptiveStatistics()
            statistics.summaryStatistics = summary.state == .on
            statistics.usesSSMedian = ssmedian.state == .on
            statistics.confidenceLevel = confidenceInterval.state == .on ? NSNumber(value: Double(intervalField.stringValue) ?? -1) : nil
            statistics.kthLargest = kthLargest.state == .on ? NSNumber(value: Double(largestField.stringValue) ?? 0) : nil
            statistics.kthSmallest = kthSmallest.state == .on ? NSNumber(value: Double(smallestField.stringValue) ?? 0) : nil
            fill(statistics)
            return statistics
        case .correlation:
            let correlation = CorrelationAnalysis()
            fill(correlation)
            return correlation
        case .covariance:
            let covariance = CovarianceAnalysis()
            fill(covariance)
            return covariance
        case .meanTest:
            let test = MeanTestAnalysis()
            fillTwoSample(test)
            test.kind = MeanTestAnalysis.Kind(rawValue: meanTestKind.indexOfSelectedItem) ?? .unequalVariances
            test.hypothesizedMeanDifference = Double(meanDifferenceField.stringValue) ?? 0
            test.firstVariance = Double(firstVarianceField.stringValue) ?? 0
            test.secondVariance = Double(secondVarianceField.stringValue) ?? 0
            return test
        case .varianceTest:
            let test = VarianceTestAnalysis()
            fillTwoSample(test)
            return test
        case .anovaSingleFactor:
            let anova = AnovaSingleFactorAnalysis()
            fill(anova)
            anova.alpha = Double(alphaField.stringValue) ?? -1
            return anova
        case .ranking:
            let ranking = RankingAnalysis()
            fill(ranking)
            ranking.averagesTies = averageTies.state == .on
            return ranking
        case .sampling:
            let sampling = SamplingAnalysis()
            fill(sampling)
            sampling.isPeriodic = samplingMethod.indexOfSelectedItem == 1
            sampling.sampleSize = Int(sampleSizeField.stringValue) ?? 0
            sampling.sampleCount = Int(sampleCountField.stringValue) ?? 0
            sampling.period = Int(periodField.stringValue) ?? 0
            sampling.offset = Int(offsetField.stringValue) ?? -1
            sampling.isRowMajor = samplingDirection.indexOfSelectedItem == 1
            return sampling
        case .movingAverage:
            let average = MovingAverageAnalysis()
            fill(average)
            average.kind = MovingAverageAnalysis.Kind(rawValue: movingAverageKind.indexOfSelectedItem) ?? .simple
            average.interval = Int(maIntervalField.stringValue) ?? 0
            average.isCentral = placement.indexOfSelectedItem == 1
            average.offset = placement.indexOfSelectedItem == 2 ? (Int(averageOffsetField.stringValue) ?? -1) : 0
            average.includesStandardErrors = standardErrors.state == .on
            average.denominatorOffset = min(denominator.indexOfSelectedItem, 2)
            average.includesChart = chart.state == .on
            return average
        case .exponentialSmoothing:
            let smoothing = ExponentialSmoothingAnalysis()
            fill(smoothing)
            smoothing.kind = ExponentialSmoothingAnalysis.Kind(rawValue: smoothingKind.indexOfSelectedItem) ?? .simpleHunter
            smoothing.dampingFactor = Double(dampingField.stringValue) ?? -1
            smoothing.growthDampingFactor = Double(growthField.stringValue) ?? -1
            smoothing.seasonalDampingFactor = Double(seasonalField.stringValue) ?? -1
            smoothing.seasonalPeriod = Int(seasonalPeriodField.stringValue) ?? 0
            smoothing.includesStandardErrors = standardErrors.state == .on
            smoothing.denominatorOffset = denominator.indexOfSelectedItem
            smoothing.includesChart = chart.state == .on
            return smoothing
        case .frequency:
            let frequency = FrequencyAnalysis()
            fill(frequency)
            frequency.categoryRange = cutoffSource.indexOfSelectedItem == 1 ? cutoffRangeField.stringValue : nil
            frequency.categoryCount = Int(cutoffCountField.stringValue) ?? 0
            frequency.exactMatches = exact.state == .on
            frequency.asPercentages = percentage.state == .on
            frequency.chart = FrequencyAnalysis.Chart(rawValue: chartKind.indexOfSelectedItem) ?? .none
            return frequency
        case .histogram:
            let histogram = HistogramAnalysis()
            fill(histogram)
            histogram.cutoffRange = cutoffSource.indexOfSelectedItem == 1 ? cutoffRangeField.stringValue : nil
            histogram.cutoffCount = Int(cutoffCountField.stringValue) ?? 0
            histogram.minimum = Double(minField.stringValue).map { NSNumber(value: $0) }
            histogram.maximum = Double(maxField.stringValue).map { NSNumber(value: $0) }
            histogram.binsIncludeUpperCutoff = upperCutoff.state == .on
            histogram.firstBinFromMinusInfinity = minusInfinity.state == .on
            histogram.lastBinToPlusInfinity = plusInfinity.state == .on
            histogram.asPercentages = percentage.state == .on
            histogram.cumulative = cumulative.state == .on
            histogram.onlyNumbers = onlyNumbers.state == .on
            histogram.chart = HistogramAnalysis.Chart(rawValue: chartKind.indexOfSelectedItem) ?? .none
            return histogram
        case .fourier:
            let fourier = FourierAnalysis()
            fill(fourier)
            fourier.isInverse = inverse.state == .on
            return fourier
        case .principalComponents:
            let components = PrincipalComponentsAnalysis()
            fill(components)
            return components
        case .kaplanMeier:
            let estimates = KaplanMeierAnalysis()
            estimates.timeRange = timeField.stringValue
            estimates.censorRange = censorField.stringValue.isEmpty ? nil : censorField.stringValue
            estimates.censorMark = Int(censorFromField.stringValue) ?? 0
            estimates.censorMarkTo = Int(censorToField.stringValue) ?? 0
            estimates.groupRange = groupsRangeField.stringValue.isEmpty ? nil : groupsRangeField.stringValue
            estimates.groups = Self.parseGroups(groupsField.stringValue)
            estimates.includesChart = kmChart.state == .on
            estimates.includesTicks = kmTicks.state == .on
            estimates.includesStandardErrors = kmStandardErrors.state == .on
            estimates.includesMedian = kmMedian.state == .on
            estimates.logRankTest = logRank.state == .on
            return estimates
        case .normality:
            let test = NormalityAnalysis()
            fill(test)
            test.kind = NormalityAnalysis.Kind(rawValue: normalityKind.indexOfSelectedItem) ?? .andersonDarling
            test.alpha = Double(alphaField.stringValue) ?? -1
            test.includesProbabilityPlot = probabilityPlot.state == .on
            return test
        case .oneMeanTest:
            let test = OneMeanTestAnalysis()
            fill(test)
            test.hypothesizedMean = Double(meanField.stringValue) ?? 0
            test.alpha = Double(alphaField.stringValue) ?? -1
            return test
        case .oneMedianSignTest, .oneMedianSignedRank:
            let test = MedianTestAnalysis()
            fill(test)
            test.kind = medianKind.indexOfSelectedItem == 1 ? .wilcoxonSignedRank : .sign
            test.hypothesizedMedian = Double(medianField.stringValue) ?? 0
            test.alpha = Double(alphaField.stringValue) ?? -1
            return test
        case .twoMedianSignTest, .twoMedianSignedRank:
            let test = TwoMedianTestAnalysis()
            fillTwoSample(test)
            test.kind = medianKind.indexOfSelectedItem == 1 ? .wilcoxonSignedRank : .sign
            test.hypothesizedMedian = Double(medianField.stringValue) ?? 0
            return test
        case .mannWhitney:
            let test = MannWhitneyAnalysis()
            fillTwoSample(test)
            test.alpha = 0.05   // the dialog has no alpha
            return test
        case .anovaTwoFactor:
            let anova = AnovaTwoFactorAnalysis()
            anova.inputRange = inputField.stringValue
            anova.hasLabels = labels.state == .on
            anova.alpha = Double(alphaField.stringValue) ?? -1
            anova.rowsPerSample = Int(replicationField.stringValue) ?? 0
            return anova
        case .homogeneity, .independence:
            let test = ContingencyTableAnalysis()
            test.inputRange = inputField.stringValue
            test.hasLabels = labels.state == .on
            test.testsIndependence = chiKind.indexOfSelectedItem == 1
            test.alpha = Double(alphaField.stringValue) ?? -1
            return test
        }
    }

    /// "low 0 7; high 8 20": the Kaplan-Meier groups, each a name and its
    /// first and last group values.
    static func parseGroups(_ text: String) -> [KaplanMeierGroup] {
        text.split(separator: ";").compactMap { part -> KaplanMeierGroup? in
            let words = part.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard words.count >= 3, let from = Int(words[words.count - 2]), let to = Int(words[words.count - 1]) else { return nil }
            return KaplanMeierGroup(name: words.dropLast(2).joined(separator: " "), from: from, to: to)
        }
    }

    private func fillTwoSample(_ analysis: TwoSampleAnalysis) {
        analysis.firstRange = xField.stringValue
        analysis.secondRange = yField.stringValue
        analysis.hasLabels = labels.state == .on
        analysis.alpha = Double(alphaField.stringValue) ?? -1
    }

    private func fill(_ analysis: GroupedAnalysis) {
        analysis.inputRanges = inputField.stringValue
        analysis.grouping = Analysis.Grouping(rawValue: [1, 0, 2][grouping.indexOfSelectedItem]) ?? .columns
        analysis.hasLabels = labels.state == .on
    }

    /// Where to write, as the Output rows say.
    func makeOutput() -> AnalysisOutput {
        let output = destination.indexOfSelectedItem == 0 ? AnalysisOutput.newSheet() : AnalysisOutput(rangeNamed: outputField.stringValue)
        output.autofitsColumns = autofit.state == .on
        output.clearsOutputRange = clear.state == .on
        output.retainsFormatting = retainFormatting.state == .on
        output.retainsComments = retainComments.state == .on
        output.entersFormulas = entered.indexOfSelectedItem == 1
        return output
    }

    /// Present as a sheet; `run` is called with the choices on Run and
    /// returns whether they were accepted (a refusal re-presents).
    func present(in window: NSWindow, run: @escaping (Analysis, AnalysisOutput) -> Bool) {
        if let driver = Self.headlessDriver {
            if driver(self) { _ = run(makeAnalysis(), makeOutput()) }
            return
        }
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn else { return }
            if !run(makeAnalysis(), makeOutput()) {
                DispatchQueue.main.async { [self] in present(in: window, run: run) }
            }
        }
    }
}
