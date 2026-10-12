import AppKit
import GnmCocoa

/// Find and Replace as a floating panel beside a document window: the
/// GTK Search dialog's options and Matches page and the Search & Replace
/// dialog's replace options, over the engine's search.  Choosing a match
/// selects its cell (switching sheets); Replace changes the chosen match,
/// Replace All runs the engine's "Search and Replace" command, asking
/// before each change when told to.
@MainActor
final class FindPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    let panel: NSPanel
    private weak var controller: WorkbookWindowController?
    private var workbook: Workbook? { controller?.workbook }
    private var currentSheet: Sheet? { controller?.gridView.sheet }

    private let findField = NSTextField()
    private let replaceField = NSTextField()
    private let scopeButtons: [NSButton]
    private let rangeField = NSTextField()
    private let kindButtons: [NSButton]   // strings, other values, expressions, results, comments
    private let textKind = NSPopUpButton(frame: .zero, pullsDown: false)
    private let order = NSPopUpButton(frame: .zero, pullsDown: false)
    private let ignoreCase = NSButton(checkboxWithTitle: "Ignore case", target: nil, action: nil)
    private let wholeWords = NSButton(checkboxWithTitle: "Whole words only", target: nil, action: nil)
    private let preserveCase = NSButton(checkboxWithTitle: "Preserve case", target: nil, action: nil)
    private let keepStrings = NSButton(checkboxWithTitle: "Keep strings as strings", target: nil, action: nil)
    private let askEach = NSButton(checkboxWithTitle: "Ask before each change", target: nil, action: nil)
    private let errorBehavior = NSPopUpButton(frame: .zero, pullsDown: false)
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private let previousButton = NSButton(title: "Previous", target: nil, action: nil)
    private let nextButton = NSButton(title: "Next", target: nil, action: nil)
    private let replaceButton = NSButton(title: "Replace", target: nil, action: nil)
    private let replaceAllButton = NSButton(title: "Replace All", target: nil, action: nil)

    private(set) var matches: [SearchMatch] = []
    private var revealing = false

    private static let errorChoices: [(String, SearchOptions.ErrorBehavior)] = [
        ("Stop with an error", .fail), ("Leave the cell unchanged", .skip),
        ("Store an error expression", .makeError), ("Store it as a string", .makeString),
    ]

    init(controller: WorkbookWindowController) {
        self.controller = controller
        panel = FindPanelWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 540),
                                styleMask: [.titled, .closable, .resizable, .utilityWindow],
                                backing: .buffered, defer: false)
        scopeButtons = ["Entire workbook", "Current sheet", "Range:"].map {
            NSButton(radioButtonWithTitle: $0, target: nil, action: nil)
        }
        kindButtons = ["Strings", "Other values", "Expressions", "Results", "Comments"].map {
            NSButton(checkboxWithTitle: $0, target: nil, action: nil)
        }
        super.init()
        (panel as? FindPanelWindow)?.owner = self
        panel.title = "Find and Replace"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 480, height: 420)
        panel.setFrameAutosaveName("FindPanel")
        build()
        load()
        if let window = controller.window {
            // Selector observers go away with the observer (no deinit needed).
            NotificationCenter.default.addObserver(self, selector: #selector(documentWindowWillClose(_:)),
                                                   name: NSWindow.willCloseNotification, object: window)
        }
    }

    @objc private func documentWindowWillClose(_ notification: Notification) {
        panel.close()
    }

    // MARK: Layout

    private func build() {
        for field in [findField, replaceField, rangeField] {
            field.delegate = self
            field.lineBreakMode = .byTruncatingTail
            field.cell?.isScrollable = true
        }
        findField.placeholderString = "Text, regular expression, or number"
        findField.target = self
        findField.action = #selector(findAll(_:))
        replaceField.target = self
        replaceField.action = #selector(findAll(_:))
        rangeField.placeholderString = "A1:B4 or Sheet2!C1:C9"
        rangeField.target = self
        rangeField.action = #selector(findAll(_:))
        for button in scopeButtons {
            button.target = self
            button.action = #selector(scopeChosen(_:))   // one action: one radio group
        }
        textKind.addItems(withTitles: ["Plain text", "Regular expression", "Number"])
        order.addItems(withTitles: ["By columns", "By rows"])
        errorBehavior.addItems(withTitles: Self.errorChoices.map(\.0))
        previousButton.target = self
        previousButton.action = #selector(findPrevious(_:))
        nextButton.target = self
        nextButton.action = #selector(findNext(_:))
        replaceButton.target = self
        replaceButton.action = #selector(replaceCurrent(_:))
        replaceAllButton.target = self
        replaceAllButton.action = #selector(replaceAll(_:))
        let findAllButton = NSButton(title: "Find All", target: self, action: #selector(findAll(_:)))
        findAllButton.keyEquivalent = "\r"

        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.alignment = .right
            return field
        }
        func row(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
            let stack = NSStackView(views: views)
            stack.orientation = .horizontal
            stack.alignment = .firstBaseline
            stack.spacing = spacing
            return stack
        }
        let scopeRow = row([scopeButtons[0], scopeButtons[1], scopeButtons[2], rangeField])
        rangeField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rangeField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        let grid = NSGridView(views: [
            [label("Find:"), findField],
            [label("Replace:"), replaceField],
            [label("Scope:"), scopeRow],
            [label("Look in:"), row(kindButtons)],
            [label("Text is:"), row([textKind, order, ignoreCase, wholeWords])],
            [label("Replacing:"), row([preserveCase, keepStrings, askEach])],
            [label("If invalid:"), errorBehavior],
        ])
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        for index in 0..<grid.numberOfRows { grid.row(at: index).yPlacement = .center }

        let buttons = row([findAllButton, previousButton, nextButton, NSView(), replaceButton, replaceAllButton])
        buttons.distribution = .fill
        buttons.alignment = .centerY
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        for (identifier, title, width) in [("sheet", "Sheet", 90.0), ("cell", "Cell", 60.0), ("kind", "Type", 90.0), ("contents", "Content", 220.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            column.minWidth = 40
            table.addTableColumn(column)
        }
        table.tableColumns.last?.resizingMask = .autoresizingMask
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = true
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(activateDocument(_:))
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        let stack = NSStackView(views: [grid, buttons, status, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
        panel.contentView = content
        panel.initialFirstResponder = findField
        updateButtons()
    }

    // MARK: Options

    /// The toggles, the scope, the text kind, the order, and the error
    /// behavior persist (the GTK "Save settings as default").
    private static let defaultsKey = "FindPanel.options"

    private func load() {
        let options = SearchOptions()
        let stored = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) ?? [:]
        func flag(_ key: String, _ fallback: Bool) -> Bool { stored[key] as? Bool ?? fallback }
        func number(_ key: String, _ fallback: Int) -> Int { stored[key] as? Int ?? fallback }
        let scope = number("scope", options.scope.rawValue)
        scopeButtons.enumerated().forEach { $0.element.state = $0.offset == scope ? .on : .off }
        let kinds = [options.searchesStrings, options.searchesOtherValues, options.searchesExpressions,
                     options.searchesExpressionResults, options.searchesComments]
        let kindKeys = ["strings", "otherValues", "expressions", "results", "comments"]
        for (index, button) in kindButtons.enumerated() { button.state = flag(kindKeys[index], kinds[index]) ? .on : .off }
        textKind.selectItem(at: number("textKind", options.textKind.rawValue))
        order.selectItem(at: flag("byRow", options.byRow) ? 1 : 0)
        ignoreCase.state = flag("ignoreCase", options.ignoresCase) ? .on : .off
        wholeWords.state = flag("wholeWords", options.matchesWholeWords) ? .on : .off
        preserveCase.state = flag("preserveCase", options.preservesCase) ? .on : .off
        keepStrings.state = flag("keepStrings", options.keepsStrings) ? .on : .off
        askEach.state = flag("askEach", options.asksBeforeEachChange) ? .on : .off
        let behavior = SearchOptions.ErrorBehavior(rawValue: number("errorBehavior", options.errorBehavior.rawValue)) ?? .fail
        errorBehavior.selectItem(at: Self.errorChoices.firstIndex { $0.1 == behavior } ?? 0)
    }

    private func save(_ options: SearchOptions) {
        let stored: [String: Any] = [
            "scope": options.scope.rawValue, "strings": options.searchesStrings, "otherValues": options.searchesOtherValues,
            "expressions": options.searchesExpressions, "results": options.searchesExpressionResults,
            "comments": options.searchesComments, "textKind": options.textKind.rawValue, "byRow": options.byRow,
            "ignoreCase": options.ignoresCase, "wholeWords": options.matchesWholeWords, "preserveCase": options.preservesCase,
            "keepStrings": options.keepsStrings, "askEach": options.asksBeforeEachChange,
            "errorBehavior": options.errorBehavior.rawValue,
        ]
        UserDefaults.standard.set(stored, forKey: Self.defaultsKey)
    }

    /// What the panel says now.
    var options: SearchOptions {
        let options = SearchOptions()
        options.searchText = findField.stringValue
        options.replaceText = replaceField.stringValue
        options.scope = SearchOptions.Scope(rawValue: scopeButtons.firstIndex { $0.state == .on } ?? 1) ?? .sheet
        options.rangeText = rangeField.stringValue
        options.textKind = SearchOptions.TextKind(rawValue: textKind.indexOfSelectedItem) ?? .plain
        options.byRow = order.indexOfSelectedItem == 1
        options.ignoresCase = ignoreCase.state == .on
        options.matchesWholeWords = wholeWords.state == .on
        options.preservesCase = preserveCase.state == .on
        options.keepsStrings = keepStrings.state == .on
        options.asksBeforeEachChange = askEach.state == .on
        options.searchesStrings = kindButtons[0].state == .on
        options.searchesOtherValues = kindButtons[1].state == .on
        options.searchesExpressions = kindButtons[2].state == .on
        options.searchesExpressionResults = kindButtons[3].state == .on
        options.searchesComments = kindButtons[4].state == .on
        options.errorBehavior = Self.errorChoices[max(0, errorBehavior.indexOfSelectedItem)].1
        return options
    }

    /// For the headless hooks: the two texts.
    func setTexts(find: String, replace: String) {
        findField.stringValue = find
        replaceField.stringValue = replace
    }

    // MARK: Showing

    /// Open beside the document window, the Range field holding the
    /// selection as the GTK dialogs start, the focus in one of the texts.
    func show(focusReplace: Bool) {
        if let sheet = currentSheet, scopeButtons[2].state != .on || rangeField.stringValue.isEmpty {
            rangeField.stringValue = sheet.selectionText
        }
        if !panel.isVisible, let window = controller?.window, !panel.setFrameUsingName("FindPanel") {
            let frame = window.frame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: min(frame.maxX - size.width - 24, (NSScreen.main?.visibleFrame.maxX ?? frame.maxX) - size.width),
                                         y: frame.maxY - size.height - 60))
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(focusReplace ? replaceField : findField)
    }

    @objc private func scopeChosen(_ sender: NSButton) {
        for button in scopeButtons where button !== sender { button.state = .off }
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        if notification.object as? NSTextField === rangeField {
            scopeButtons.enumerated().forEach { $0.element.state = $0.offset == 2 ? .on : .off }
        }
    }

    // MARK: Finding

    private var selectedMatch: SearchMatch? {
        let row = table.selectedRow
        return row >= 0 && row < matches.count ? matches[row] : nil
    }

    @discardableResult
    private func search(selecting row: Int?) -> Bool {
        guard let workbook, let sheet = currentSheet else { return false }
        if controller?.gridView.isEditing == true { controller?.gridView.cancelEditing() }
        let options = options
        if options.searchText.isEmpty {
            NSSound.beep()
            panel.makeFirstResponder(findField)
            return false
        }
        save(options)
        do {
            matches = try workbook.findMatches(options, in: sheet)
        } catch {
            matches = []
            table.reloadData()
            updateButtons()
            present(error)
            return false
        }
        table.reloadData()
        status.stringValue = matches.isEmpty ? "No matches" : matches.count == 1 ? "1 match" : "\(matches.count) matches"
        if let row, !matches.isEmpty {
            select(row: min(max(row, 0), matches.count - 1))
        } else {
            updateButtons()
        }
        return true
    }

    private func select(row: Int) {
        guard row >= 0, row < matches.count else { return }
        revealing = true
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
        revealing = false
        reveal(matches[row])
        updateButtons()
    }

    private func reveal(_ match: SearchMatch) {
        guard match.sheet.workbook === workbook, match.sheet.isVisible else { return }
        match.sheet.revealCell(atColumn: match.column, row: match.row)
        workbook?.resendDelegateState()
    }

    private func updateButtons() {
        let row = table.selectedRow
        previousButton.isEnabled = row > 0
        nextButton.isEnabled = !matches.isEmpty && row < matches.count - 1
        // A computed value cannot be replaced; a comment on an empty cell is
        // out of a range's reach (the engine visits cells with content).
        let replaceable: Bool
        if let match = selectedMatch {
            replaceable = match.locus == .contents
                || (match.locus == .comment && !match.sheet.isCellEmpty(atColumn: match.column, row: match.row))
        } else {
            replaceable = false
        }
        replaceButton.isEnabled = replaceable
    }

    @objc func findAll(_ sender: Any?) {
        search(selecting: 0)
    }

    @objc func findNext(_ sender: Any?) {
        if matches.isEmpty { search(selecting: 0); return }
        let row = table.selectedRow
        select(row: row < 0 ? 0 : min(row + 1, matches.count - 1))
    }

    @objc func findPrevious(_ sender: Any?) {
        if matches.isEmpty { search(selecting: nil); if !matches.isEmpty { select(row: matches.count - 1) }; return }
        let row = table.selectedRow
        select(row: row < 0 ? matches.count - 1 : max(row - 1, 0))
    }

    // MARK: Replacing

    /// Replace the chosen match only: the replace command over that one
    /// cell as its range.
    @objc func replaceCurrent(_ sender: Any?) {
        guard let workbook, let sheet = currentSheet, let match = selectedMatch, replaceButton.isEnabled else { return }
        let row = table.selectedRow
        let options = options
        options.scope = .range
        options.rangeText = match.reference
        options.asksBeforeEachChange = false
        options.searchesComments = match.locus == .comment
        if match.locus == .comment {
            options.searchesStrings = false
            options.searchesOtherValues = false
            options.searchesExpressions = false
        }
        do {
            try workbook.replaceMatches(options, in: sheet, queryHandler: nil)
        } catch {
            present(error)
            return
        }
        workbook.resendDelegateState()
        controller?.gridView.needsDisplay = true
        // The list again, the choice staying on the match that now holds
        // this one's place.
        search(selecting: row)
    }

    @objc func replaceAll(_ sender: Any?) {
        guard let workbook, let sheet = currentSheet else { return }
        if controller?.gridView.isEditing == true { controller?.gridView.cancelEditing() }
        let options = options
        if options.searchText.isEmpty {
            NSSound.beep()
            panel.makeFirstResponder(findField)
            return
        }
        save(options)
        let row = max(table.selectedRow, 0)
        do {
            try workbook.replaceMatches(options, in: sheet) { [weak self] query in
                self?.ask(query) ?? .cancel
            }
        } catch {
            present(error)
            return
        }
        workbook.resendDelegateState()
        controller?.gridView.needsDisplay = true
        if search(selecting: row) {
            status.stringValue = matches.isEmpty ? "Replaced; no matches remain"
                               : "Replaced; \(matches.count) " + (matches.count == 1 ? "match remains" : "matches remain")
        }
    }

    /// The GTK query dialog: the cell shown, then Replace, Skip, or
    /// Cancel, with the choice of not being asked again.  Synchronous,
    /// because the engine's command waits for the answer.
    private func ask(_ query: SearchQuery) -> SearchQuery.Answer {
        if query.sheet.workbook === workbook, query.sheet.isVisible {
            query.sheet.revealCell(atColumn: query.column, row: query.row)
            workbook?.resendDelegateState()
            controller?.gridView.displayIfNeeded()
        }
        let alert = NSAlert()
        alert.messageText = query.isComment ? "Replace in this comment?" : "Replace in this cell?"
        alert.informativeText = "\(query.location)\n\nReplacing:  \(query.currentText)\nBy:  \(query.replacementText)"
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Do not ask again"
        let response = alert.runModal()
        query.asksAgain = alert.suppressionButton?.state != .on
        switch response {
        case .alertFirstButtonReturn: return .replace
        case .alertSecondButtonReturn: return .skip
        default: return .cancel
        }
    }

    private func present(_ error: Error) {
        NSLog("Gnumeric error: %@ %@", error.localizedDescription, (error as NSError).localizedRecoverySuggestion ?? "")
        let alert = NSAlert(error: error)
        if let suggestion = (error as NSError).localizedRecoverySuggestion {
            alert.informativeText = suggestion
        }
        alert.beginSheetModal(for: panel)
    }

    /// A double-click: the match's cell, in the document window.
    @objc private func activateDocument(_ sender: Any?) {
        guard let match = selectedMatch else { return }
        reveal(match)
        controller?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { matches.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, row < matches.count else { return nil }
        let match = matches[row]
        let identifier = tableColumn.identifier
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? {
            let view = NSTableCellView()
            view.identifier = identifier
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
        let text: String
        switch identifier.rawValue {
        case "sheet": text = match.sheet.name
        case "cell": text = match.cellName
        case "kind": text = match.kindDescription
        default: text = match.contents.replacingOccurrences(of: "\n", with: " ")
        }
        cell.textField?.stringValue = text
        cell.textField?.font = identifier.rawValue == "contents" ? .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
                                                                 : .systemFont(ofSize: NSFont.smallSystemFontSize)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !revealing else { return }
        if let match = selectedMatch { reveal(match) }
        updateButtons()
    }
}

/// The panel: menu actions the panel's owner handles (Find Next and the
/// rest while the panel is key), Escape closing it.
@MainActor
private final class FindPanelWindow: NSPanel {
    weak var owner: FindPanel?

    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        if let owner, owner.responds(to: action) { return owner }
        return super.supplementalTarget(forAction: action, sender: sender)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
