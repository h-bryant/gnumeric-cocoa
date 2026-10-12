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

        var title: String {
            switch self {
            case .descriptiveStatistics: return "Descriptive Statistics"
            case .correlation: return "Correlation"
            case .covariance: return "Covariance"
            case .regression: return "Regression"
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
        for field in [inputField, xField, yField, outputField] {
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        }
        for field in [confidenceField, intervalField, largestField, smallestField] {
            field.widthAnchor.constraint(equalToConstant: 70).isActive = true
        }
        alert.accessoryView = makeGrid()
        alert.window.initialFirstResponder = tool == .regression ? xField : inputField
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
        case .descriptiveStatistics, .correlation, .covariance:
            rows += [[label("Input range:"), inputField], [label("Grouped by:"), grouping], [NSGridCell.emptyContentView, labels]]
            if tool == .descriptiveStatistics {
                rows += [[heading("Statistics"), NSGridCell.emptyContentView],
                         [NSGridCell.emptyContentView, summary], [NSGridCell.emptyContentView, ssmedian],
                         [NSGridCell.emptyContentView, pair(confidenceInterval, intervalField)],
                         [NSGridCell.emptyContentView, pair(kthLargest, largestField)],
                         [NSGridCell.emptyContentView, pair(kthSmallest, smallestField)]]
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
        }
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
