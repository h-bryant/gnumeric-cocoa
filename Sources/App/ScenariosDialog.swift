import AppKit
import GnmCocoa

/// The Add Scenario dialog (dialog_scenario_add) as an alert sheet: the
/// name, the changing cells, and a comment.
@MainActor
final class ScenarioAddDialog {
    /// For the headless checks: fill the fields and return true to add.
    nonisolated(unsafe) static var headlessDriver: ((ScenarioAddDialog) -> Bool)?

    let alert = NSAlert()
    let nameField = NSTextField(string: "")
    let cellsField = NSTextField(string: "")
    let commentField = NSTextField(string: "")

    init(sheet: Sheet) {
        alert.messageText = Localization.title("Add Scenario")
        alert.informativeText = "The changing cells keep their current values under this name."
        alert.addButton(withTitle: Localization.title("Add"))
        alert.addButton(withTitle: Localization.title("Cancel"))
        cellsField.stringValue = sheet.rangeNames(inList: sheet.selectionText)?.first ?? ""
        for field in [nameField, cellsField, commentField] { field.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true }
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.alignment = .right
            return field
        }
        let grid = NSGridView(views: [[label("Name:"), nameField], [label("Changing cells:"), cellsField], [label("Comment:"), commentField]])
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        let size = grid.fittingSize
        grid.frame = NSRect(x: 0, y: 0, width: max(size.width, 360), height: size.height)
        alert.accessoryView = grid
        alert.window.initialFirstResponder = nameField
    }

    func present(in window: NSWindow, run: @escaping (String, String, String) -> Bool) {
        if let driver = Self.headlessDriver {
            if driver(self) { _ = run(nameField.stringValue, cellsField.stringValue, commentField.stringValue) }
            return
        }
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn else { return }
            if !run(nameField.stringValue, cellsField.stringValue, commentField.stringValue) {
                DispatchQueue.main.async { [self] in present(in: window, run: run) }
            }
        }
    }
}

/// The scenario manager (dialog-scenarios.c) as a sheet window over the
/// engine's session: the sheet's scenarios in a list, the chosen one's
/// comment and cells below, Show, Delete, and Summary (with the result
/// cells), then OK commits what was shown and deleted, Cancel restores.
@MainActor
final class ScenarioManagerDialog: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let window: NSWindow
    let manager: ScenarioManager
    private let table = NSTableView()
    private let details = NSTextField(wrappingLabelWithString: "")
    private let resultsField = NSTextField(string: "")
    private let showButton = NSButton(title: Localization.title("Show"), target: nil, action: nil)
    private let deleteButton = NSButton(title: Localization.title("Delete"), target: nil, action: nil)
    private let summaryButton = NSButton(title: Localization.title("Summary"), target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private(set) var scenarios: [Scenario] = []
    private var completion: (@MainActor (Bool) -> Void)?

    init(sheet: Sheet) {
        manager = sheet.scenarioManager()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = Localization.title("Scenarios")
        window.isReleasedWhenClosed = false
        super.init()
        build()
        reload(selecting: nil)
    }

    private func build() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = "Scenario"
        column.width = 460
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = true
        table.allowsEmptySelection = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(show(_:))
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true

        details.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        details.textColor = .secondaryLabelColor
        details.maximumNumberOfLines = 6
        for (button, action) in [(showButton, #selector(show(_:))), (deleteButton, #selector(delete(_:))), (summaryButton, #selector(summary(_:)))] {
            button.target = self
            button.action = action
        }
        resultsField.placeholderString = "Result cells for the summary, such as B1:B3"
        let resultsRow = NSStackView(views: [NSTextField(labelWithString: Localization.title("Result cells:")), resultsField])
        resultsRow.orientation = .horizontal
        resultsRow.spacing = 8
        let actions = NSStackView(views: [showButton, deleteButton, summaryButton, NSView()])
        actions.orientation = .horizontal
        actions.spacing = 8
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.lineBreakMode = .byTruncatingTail
        let okButton = NSButton(title: Localization.title("OK"), target: self, action: #selector(finish(_:)))
        okButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: Localization.title("Cancel"), target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [status, NSView(), cancelButton, okButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let stack = NSStackView(views: [scroll, details, actions, resultsRow, buttons])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            content.widthAnchor.constraint(equalToConstant: 520),
        ])
        window.contentView = content
        window.initialFirstResponder = table
    }

    // MARK: Running

    /// `completion` gets true when OK committed the session.
    func run(in parent: NSWindow, completion: @escaping @MainActor (Bool) -> Void) {
        self.completion = completion
        parent.beginSheet(window) { _ in }
    }

    private func end(committed: Bool) {
        if let parent = window.sheetParent { parent.endSheet(window) }
        window.close()
        let completion = self.completion
        self.completion = nil
        completion?(committed)
    }

    @objc func finish(_ sender: Any?) {
        do {
            try manager.finish()
        } catch {
            status.stringValue = error.localizedDescription
            NSLog("Gnumeric error: %@", error.localizedDescription)
        }
        end(committed: true)
    }

    @objc func cancel(_ sender: Any?) {
        manager.cancel()
        end(committed: false)
    }

    // MARK: The list

    var selectedScenario: Scenario? {
        let row = table.selectedRow
        return row >= 0 && row < scenarios.count ? scenarios[row] : nil
    }

    func select(row: Int) {
        guard row >= 0, row < scenarios.count else { return }
        table.selectRowIndexes([row], byExtendingSelection: false)
        updateDetails()
    }

    private func reload(selecting scenario: Scenario?) {
        scenarios = manager.scenarios
        table.reloadData()
        if let scenario, let row = scenarios.firstIndex(where: { $0 == scenario }) {
            table.selectRowIndexes([row], byExtendingSelection: false)
        }
        updateDetails()
    }

    private func updateDetails() {
        if let scenario = selectedScenario {
            var lines = ["Changing cells: " + scenario.changingCellsText]
            if !scenario.valueDescriptions.isEmpty { lines.append(scenario.valueDescriptions.joined(separator: ", ")) }
            if !scenario.comment.isEmpty { lines.append(scenario.comment) }
            if manager.shownScenario == scenario { lines.append("Shown on the sheet.") }
            details.stringValue = lines.joined(separator: "\n")
        } else {
            details.stringValue = scenarios.isEmpty ? "The sheet has no scenarios; Tools → Scenarios → Add… makes one." : "Choose a scenario."
        }
        showButton.isEnabled = selectedScenario != nil
        deleteButton.isEnabled = selectedScenario != nil
        summaryButton.isEnabled = !scenarios.isEmpty
    }

    func numberOfRows(in tableView: NSTableView) -> Int { scenarios.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, row < scenarios.count else { return nil }
        let cell = (tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NSTableCellView) ?? {
            let view = NSTableCellView()
            view.identifier = tableColumn.identifier
            let field = NSTextField(labelWithString: "")
            field.lineBreakMode = .byTruncatingTail
            field.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(field)
            view.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
                field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2),
                field.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
            return view
        }()
        cell.textField?.stringValue = scenarios[row].name
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateDetails()
    }

    // MARK: Actions

    @objc func show(_ sender: Any?) {
        guard let scenario = selectedScenario else { return }
        do {
            try manager.show(scenario)
            status.stringValue = ""
        } catch {
            status.stringValue = error.localizedDescription
        }
        reload(selecting: scenario)
    }

    @objc func delete(_ sender: Any?) {
        guard let scenario = selectedScenario else { return }
        manager.delete(scenario)
        reload(selecting: nil)
    }

    /// The report sheet made last, for the checks.
    private(set) var lastSummarySheet: Sheet?

    func setResultCellsForTesting(_ text: String) {
        resultsField.stringValue = text
    }

    @objc func summary(_ sender: Any?) {
        do {
            lastSummarySheet = try manager.createSummary(resultCells: resultsField.stringValue)
            status.stringValue = "Summary written to “\(lastSummarySheet?.name ?? "")”."
        } catch {
            status.stringValue = error.localizedDescription
        }
        reload(selecting: selectedScenario)
    }
}
