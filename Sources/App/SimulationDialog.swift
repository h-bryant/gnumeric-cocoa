import AppKit
import GnmCocoa

/// The Risk Simulation dialog (dialog-simulation.c) as an alert sheet:
/// the input and output ranges, the iterations, the rounds, the time
/// limit, and where the report goes; the results pane follows as a
/// second alert with each round's table and the run's log.
@MainActor
final class SimulationDialog {
    /// For the headless checks: fill the fields and return true to run.
    nonisolated(unsafe) static var headlessDriver: ((SimulationDialog) -> Bool)?
    /// The last run's results text, for the checks.
    nonisolated(unsafe) static var lastResultsText: String?

    let alert = NSAlert()
    let inputsField = NSTextField(string: "")
    let outputsField = NSTextField(string: "")
    let iterationsField = NSTextField(string: "1000")
    let firstRoundField = NSTextField(string: "1")
    let lastRoundField = NSTextField(string: "1")
    let maxTimeField = NSTextField(string: "60")
    let outputPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    let outputRangeField = NSTextField(string: "")

    struct Request {
        var inputs: String
        var outputs: String
        var iterations: Int
        var firstRound: Int
        var lastRound: Int
        var maximumSeconds: Int
        var output: AnalysisOutput
    }

    init(sheet: Sheet) {
        alert.messageText = "Risk Simulation"
        alert.informativeText = "The inputs are recomputed each iteration; the outputs' statistics make the report."
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        inputsField.stringValue = sheet.rangeNames(inList: sheet.selectionText)?.first ?? ""
        for field in [inputsField, outputsField, outputRangeField] { field.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true }
        for field in [iterationsField, firstRoundField, lastRoundField, maxTimeField] {
            field.widthAnchor.constraint(equalToConstant: 80).isActive = true
            field.alignment = .right
        }
        outputPopUp.addItems(withTitles: ["New sheet", "Range:"])
        outputPopUp.target = self
        outputPopUp.action = #selector(outputChanged(_:))
        outputRangeField.isEnabled = false
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.alignment = .right
            return field
        }
        let outputRow = NSStackView(views: [outputPopUp, outputRangeField])
        outputRow.orientation = .horizontal
        outputRow.spacing = 8
        let grid = NSGridView(views: [
            [label("Input variables:"), inputsField],
            [label("Output variables:"), outputsField],
            [label("Iterations:"), iterationsField],
            [label("First round:"), firstRoundField],
            [label("Last round:"), lastRoundField],
            [label("Max time (seconds):"), maxTimeField],
            [label("Output:"), outputRow],
        ])
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        let size = grid.fittingSize
        grid.frame = NSRect(x: 0, y: 0, width: max(size.width, 400), height: size.height)
        alert.accessoryView = grid
        alert.window.initialFirstResponder = inputsField
    }

    @objc private func outputChanged(_ sender: Any?) {
        outputRangeField.isEnabled = outputPopUp.indexOfSelectedItem == 1
    }

    var request: Request {
        Request(inputs: inputsField.stringValue, outputs: outputsField.stringValue,
                iterations: Int(iterationsField.stringValue) ?? 0, firstRound: Int(firstRoundField.stringValue) ?? 0,
                lastRound: Int(lastRoundField.stringValue) ?? 0, maximumSeconds: Int(maxTimeField.stringValue) ?? 0,
                output: outputPopUp.indexOfSelectedItem == 1 ? AnalysisOutput(rangeNamed: outputRangeField.stringValue) : AnalysisOutput.newSheet())
    }

    func present(in window: NSWindow, run: @escaping (Request) -> Bool) {
        if let driver = Self.headlessDriver {
            if driver(self) { _ = run(request) }
            return
        }
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn else { return }
            if !run(request) {
                DispatchQueue.main.async { [self] in present(in: window, run: run) }
            }
        }
    }

    /// The results pane: every round's table (the GTK shows one at a time
    /// with Prev and Next) and the log.
    static func resultsText(for result: SimulationResult) -> String {
        var text = ""
        for round in result.firstRound...max(result.firstRound, result.lastRound) {
            text += result.text(forRound: round) + "\n"
        }
        text += result.logLines.joined(separator: "\n")
        return text
    }

    static func presentResults(_ result: SimulationResult, in window: NSWindow) {
        let text = resultsText(for: result)
        lastResultsText = text
        guard headlessDriver == nil else { return }
        let alert = NSAlert()
        alert.messageText = "Simulation Results"
        alert.informativeText = "The report is on its sheet; this is the summary of each round."
        alert.addButton(withTitle: "OK")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 260))
        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = text
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        alert.accessoryView = scroll
        alert.beginSheetModal(for: window)
    }
}
