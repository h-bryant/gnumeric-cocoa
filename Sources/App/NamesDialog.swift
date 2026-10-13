import AppKit
import GnmCocoa

/// The Define Names dialog (dialog-define-names.c) as a sheet: the
/// workbook's names and the current sheet's in a table, fields below for
/// the chosen or a new one (name, scope, expression), Add or Update,
/// Remove, and Close.  Every change is an engine command, undoable.
@MainActor
final class NamesDialog: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let window: NSWindow
    private let workbook: Workbook
    private let sheet: Sheet
    private let table = NSTableView()
    private let nameField = NSTextField()
    private let scopePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let expressionField = NSTextField()
    private let addButton = NSButton(title: Localization.title("Add"), target: nil, action: nil)
    private let removeButton = NSButton(title: Localization.title("Remove"), target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private(set) var names: [DefinedName] = []
    private var completion: (@MainActor () -> Void)?

    init(workbook: Workbook, sheet: Sheet) {
        self.workbook = workbook
        self.sheet = sheet
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = Localization.title("Define Names")
        window.isReleasedWhenClosed = false
        super.init()
        build()
        reload(selecting: nil)
    }

    // MARK: Layout

    private func build() {
        for (identifier, title, width) in [("name", "Name", 140.0), ("scope", "Scope", 100.0), ("expression", "Refers to", 260.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            column.minWidth = 50
            table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = true
        table.allowsEmptySelection = true
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true

        nameField.placeholderString = "Name"
        expressionField.placeholderString = "A range, a value, or a formula, such as Sheet1!$A$1:$A$9"
        expressionField.target = self
        expressionField.action = #selector(add(_:))
        scopePopUp.addItem(withTitle: "Workbook")
        scopePopUp.addItem(withTitle: "Sheet “\(sheet.name)”")
        addButton.target = self
        addButton.action = #selector(add(_:))
        removeButton.target = self
        removeButton.action = #selector(remove(_:))
        let closeButton = NSButton(title: Localization.title("Close"), target: self, action: #selector(close(_:)))
        closeButton.keyEquivalent = "\u{1b}"
        let newButton = NSButton(title: Localization.title("New"), target: self, action: #selector(clearFields(_:)))

        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.alignment = .right
            return field
        }
        let grid = NSGridView(views: [
            [label("Name:"), nameField],
            [label("Scope:"), scopePopUp],
            [label("Refers to:"), expressionField],
        ])
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        for index in 0..<grid.numberOfRows { grid.row(at: index).yPlacement = .center }
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.lineBreakMode = .byTruncatingTail

        let buttons = NSStackView(views: [newButton, addButton, removeButton, NSView(), status, closeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let stack = NSStackView(views: [scroll, grid, buttons])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            content.widthAnchor.constraint(equalToConstant: 560),
        ])
        window.contentView = content
        window.initialFirstResponder = nameField
    }

    // MARK: Running

    func run(in parent: NSWindow, completion: @escaping @MainActor () -> Void) {
        self.completion = completion
        parent.beginSheet(window) { _ in }
    }

    @objc private func close(_ sender: Any?) {
        guard let parent = window.sheetParent else { return }
        parent.endSheet(window)
        window.close()
        let completion = self.completion
        self.completion = nil
        completion?()
    }

    // MARK: The list

    private func reload(selecting name: String?) {
        names = workbook.definedNames(for: sheet)
        table.reloadData()
        if let name, let row = names.firstIndex(where: { $0.name == name }) {
            table.selectRowIndexes([row], byExtendingSelection: false)
            table.scrollRowToVisible(row)
        } else {
            table.deselectAll(nil)
        }
        updateButtons()
    }

    private var selectedName: DefinedName? {
        let row = table.selectedRow
        return row >= 0 && row < names.count ? names[row] : nil
    }

    private func updateButtons() {
        let chosen = selectedName
        removeButton.isEnabled = chosen?.isEditable == true
        let existing = names.first { $0.name == nameField.stringValue && ($0.scope == nil) == (scopePopUp.indexOfSelectedItem == 0) }
        addButton.title = existing == nil ? "Add" : "Update"
        addButton.isEnabled = existing?.isEditable != false
    }

    func numberOfRows(in tableView: NSTableView) -> Int { names.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, row < names.count else { return nil }
        let name = names[row]
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
        switch tableColumn.identifier.rawValue {
        case "name": cell.textField?.stringValue = name.name
        case "scope": cell.textField?.stringValue = name.scope?.name ?? "Workbook"
        default: cell.textField?.stringValue = name.expressionText
        }
        cell.textField?.textColor = name.isEditable ? .labelColor : .secondaryLabelColor
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if let name = selectedName {
            nameField.stringValue = name.name
            scopePopUp.selectItem(at: name.scope == nil ? 0 : 1)
            expressionField.stringValue = name.expressionText
        }
        updateButtons()
    }

    func controlTextDidChange(_ notification: Notification) {
        updateButtons()
    }

    // MARK: Actions

    @objc private func clearFields(_ sender: Any?) {
        table.deselectAll(nil)
        nameField.stringValue = ""
        expressionField.stringValue = ""
        status.stringValue = ""
        updateButtons()
        window.makeFirstResponder(nameField)
    }

    /// Add a new name or update the chosen one (Enter in the expression
    /// field does the same); the scope pop-up chooses between the
    /// workbook and the current sheet.
    @objc func add(_ sender: Any?) {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        let scope: Sheet? = scopePopUp.indexOfSelectedItem == 0 ? nil : sheet
        guard !name.isEmpty else {
            status.stringValue = "A name is needed."
            window.makeFirstResponder(nameField)
            return
        }
        do {
            try workbook.defineName(name, expression: expressionField.stringValue, scope: scope, in: sheet)
            status.stringValue = ""
            reload(selecting: name)
        } catch {
            status.stringValue = error.localizedDescription
            NSLog("Gnumeric error: %@", error.localizedDescription)
        }
    }

    @objc private func remove(_ sender: Any?) {
        guard let name = selectedName, name.isEditable else { return }
        if name.isInUse {
            let alert = NSAlert()
            alert.messageText = "The defined name “\(name.name)” is in use."
            alert.informativeText = "Cells or other names refer to it; they will show an error without it. Remove it anyway?"
            alert.addButton(withTitle: Localization.title("Remove"))
            alert.addButton(withTitle: Localization.title("Cancel"))
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn else { return }
                self?.performRemove(name)
            }
        } else {
            performRemove(name)
        }
    }

    private func performRemove(_ name: DefinedName) {
        do {
            try workbook.remove(name)
            status.stringValue = ""
            clearFields(nil)
            reload(selecting: nil)
        } catch {
            status.stringValue = error.localizedDescription
        }
    }

    /// For the headless hook: the fields as typed.
    func setFields(name: String, expression: String, workbookScope: Bool) {
        nameField.stringValue = name
        expressionField.stringValue = expression
        scopePopUp.selectItem(at: workbookScope ? 0 : 1)
        updateButtons()
    }
}
