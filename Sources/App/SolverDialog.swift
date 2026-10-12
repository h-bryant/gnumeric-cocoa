import AppKit
import GnmCocoa

/// The GTK Solver dialog (dialog-solver.c) as an alert sheet: the target
/// and the cells to change, the model and algorithm, the constraints
/// with their editor, the options and reports; Solve records the
/// settings on the sheet and runs, Save only records.
@MainActor
final class SolverDialog: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    /// For the headless checks: fill the fields and return true to solve.
    nonisolated(unsafe) static var headlessDriver: ((SolverDialog) -> Bool)?

    static let kinds: [SolverRule.Kind] = [.lessOrEqual, .greaterOrEqual, .equal, .integer, .boolean]

    let alert = NSAlert()
    let sheet: Sheet
    let targetField = NSTextField(string: "")
    let goal = NSPopUpButton(frame: .zero, pullsDown: false)
    let inputField = NSTextField(string: "")
    let model = NSPopUpButton(frame: .zero, pullsDown: false)
    let algorithm = NSPopUpButton(frame: .zero, pullsDown: false)
    let algorithms: [SolverAlgorithm]
    let nonNegative = NSButton(checkboxWithTitle: "Assume non-negative", target: nil, action: nil)
    let discrete = NSButton(checkboxWithTitle: "Assume integer (discrete)", target: nil, action: nil)
    let maxIterationsField = NSTextField(string: "1000")
    let maxTimeField = NSTextField(string: "60")
    let autoscale = NSButton(checkboxWithTitle: "Automatic scaling", target: nil, action: nil)
    let programReport = NSButton(checkboxWithTitle: "Program report", target: nil, action: nil)
    let sensitivityReport = NSButton(checkboxWithTitle: "Sensitivity report", target: nil, action: nil)
    let table = NSTableView()
    let lhsField = NSTextField(string: "")
    let kind = NSPopUpButton(frame: .zero, pullsDown: false)
    let rhsField = NSTextField(string: "")
    private(set) var rules: [SolverRule] = []

    init(sheet: Sheet) {
        self.sheet = sheet
        algorithms = (Engine.shared?.solverAlgorithms ?? []).filter(\.isFunctional)
        super.init()
        alert.messageText = "Solver"
        alert.informativeText = "Change the input cells so the target cell is as large or as small as the constraints allow."
        alert.addButton(withTitle: "Solve")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Save")
        goal.addItems(withTitles: ["Max", "Min"])
        model.addItems(withTitles: ["Linear (LP/MILP)", "Quadratic (QP/MIQP)", "Non-linear"])
        algorithm.addItems(withTitles: algorithms.map(\.name))
        kind.addItems(withTitles: Self.kinds.map { SolverRule.symbol(for: $0) })
        let settings = sheet.solverSettings
        targetField.stringValue = settings.targetCell
        goal.selectItem(at: settings.goal == .maximize ? 0 : 1)
        inputField.stringValue = settings.inputCells
        model.selectItem(at: settings.model.rawValue)
        if let identifier = settings.algorithmIdentifier, let index = algorithms.firstIndex(where: { $0.identifier == identifier }) {
            algorithm.selectItem(at: index)
        } else if let index = algorithms.firstIndex(where: { $0.identifier == "nlsolve" }) {
            algorithm.selectItem(at: index)
        }
        nonNegative.state = settings.assumesNonNegative ? .on : .off
        discrete.state = settings.assumesDiscrete ? .on : .off
        maxIterationsField.stringValue = String(settings.maxIterations)
        maxTimeField.stringValue = String(settings.maxTimeSeconds)
        autoscale.state = settings.automaticScaling ? .on : .off
        programReport.state = settings.programReport ? .on : .off
        sensitivityReport.state = settings.sensitivityReport ? .on : .off
        rules = settings.rules
        if targetField.stringValue.isEmpty {
            let cell = sheet.editPosition
            targetField.stringValue = sheet.rangeNames(inList: sheet.selectionText)?.first ?? ""
            _ = cell
        }
        for field in [targetField, inputField, lhsField, rhsField] {
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        }
        for field in [maxIterationsField, maxTimeField] {
            field.widthAnchor.constraint(equalToConstant: 70).isActive = true
        }
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("rule"))
        column.title = "Constraints"
        column.width = 300
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(ruleSelected(_:))
        alert.accessoryView = makeGrid()
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
        func row(_ views: [NSView]) -> NSStackView {
            let stack = NSStackView(views: views)
            stack.orientation = .horizontal
            stack.spacing = 6
            return stack
        }
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: 90).isActive = true
        scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        let add = NSButton(title: "Add", target: self, action: #selector(addRule(_:)))
        let change = NSButton(title: "Change", target: self, action: #selector(changeRule(_:)))
        let delete = NSButton(title: "Delete", target: self, action: #selector(deleteRule(_:)))
        let rows: [[NSView]] = [
            [heading("Parameters"), NSGridCell.emptyContentView],
            [label("Set target cell:"), row([targetField, label("Equal to:"), goal])],
            [label("By changing cells:"), inputField],
            [heading("Model"), NSGridCell.emptyContentView],
            [label("Model:"), model], [label("Algorithm:"), algorithm],
            [NSGridCell.emptyContentView, nonNegative], [NSGridCell.emptyContentView, discrete],
            [heading("Constraints"), NSGridCell.emptyContentView],
            [NSGridCell.emptyContentView, scroll],
            [label("Left hand side:"), row([lhsField, kind, rhsField])],
            [NSGridCell.emptyContentView, row([add, change, delete])],
            [heading("Options"), NSGridCell.emptyContentView],
            [label("Max iterations:"), row([maxIterationsField, label("Max time (sec.):"), maxTimeField])],
            [NSGridCell.emptyContentView, autoscale],
            [NSGridCell.emptyContentView, row([programReport, sensitivityReport])],
        ]
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
        grid.frame = NSRect(x: 0, y: 0, width: max(size.width, 440), height: size.height)
        return grid
    }

    // MARK: Constraints

    func numberOfRows(in tableView: NSTableView) -> Int { rules.count }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row < rules.count else { return nil }
        let rule = rules[row]
        return sheet.description(of: rule) ?? "\(rule.leftSide) \(SolverRule.symbol(for: rule.kind)) \(rule.rightSide)"
    }

    /// The editor as the fields describe it.
    var editedRule: SolverRule {
        SolverRule(kind: Self.kinds[max(0, kind.indexOfSelectedItem)], leftSide: lhsField.stringValue, rightSide: rhsField.stringValue)
    }

    /// Only a rule the engine accepts is added (dialog_set_sec_button_sensitivity).
    @discardableResult
    func add(_ rule: SolverRule) -> Bool {
        guard sheet.description(of: rule) != nil else { return false }
        rules.append(rule)
        table.reloadData()
        return true
    }

    @objc func addRule(_ sender: Any?) { add(editedRule) }

    @objc func changeRule(_ sender: Any?) {
        let row = table.selectedRow
        guard row >= 0, row < rules.count, sheet.description(of: editedRule) != nil else { return }
        rules[row] = editedRule
        table.reloadData()
    }

    @objc func deleteRule(_ sender: Any?) {
        let row = table.selectedRow
        guard row >= 0, row < rules.count else { return }
        rules.remove(at: row)
        table.reloadData()
    }

    @objc func ruleSelected(_ sender: Any?) {
        let row = table.selectedRow
        guard row >= 0, row < rules.count else { return }
        let rule = rules[row]
        lhsField.stringValue = rule.leftSide
        kind.selectItem(at: Self.kinds.firstIndex(of: rule.kind) ?? 0)
        rhsField.stringValue = rule.rightSide
    }

    /// The settings as the fields describe them.
    func makeSettings() -> SolverSettings {
        let settings = SolverSettings()
        settings.targetCell = targetField.stringValue
        settings.goal = goal.indexOfSelectedItem == 0 ? .maximize : .minimize
        settings.inputCells = inputField.stringValue
        settings.model = SolverSettings.Model(rawValue: model.indexOfSelectedItem) ?? .linear
        settings.algorithmIdentifier = algorithm.indexOfSelectedItem >= 0 && algorithm.indexOfSelectedItem < algorithms.count
            ? algorithms[algorithm.indexOfSelectedItem].identifier : nil
        settings.assumesNonNegative = nonNegative.state == .on
        settings.assumesDiscrete = discrete.state == .on
        settings.maxIterations = Int(maxIterationsField.stringValue) ?? 0
        settings.maxTimeSeconds = Int(maxTimeField.stringValue) ?? 0
        settings.automaticScaling = autoscale.state == .on
        settings.programReport = programReport.state == .on
        settings.sensitivityReport = sensitivityReport.state == .on
        settings.rules = rules
        return settings
    }

    /// Present as a sheet; `apply` gets the settings and whether to solve
    /// (Solve) or only record (Save), and returns whether they were
    /// accepted (a refusal re-presents).
    func present(in window: NSWindow, apply: @escaping (SolverSettings, Bool) -> Bool) {
        if let driver = Self.headlessDriver {
            if driver(self) { _ = apply(makeSettings(), true) }
            return
        }
        alert.window.initialFirstResponder = targetField
        alert.beginSheetModal(for: window) { [self] response in
            let accepted: Bool
            switch response {
            case .alertFirstButtonReturn: accepted = apply(makeSettings(), true)
            case .alertThirdButtonReturn: accepted = apply(makeSettings(), false)
            default: return
            }
            if !accepted {
                DispatchQueue.main.async { [self] in present(in: window, apply: apply) }
            }
        }
    }
}
