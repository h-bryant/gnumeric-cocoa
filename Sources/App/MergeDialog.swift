import AppKit
import GnmCocoa

/// The GTK Data → Merge dialog (dialog-merge.c) as a sheet window: the
/// merge zone, a list of data ranges with the field cell each one fills,
/// and Merge, which makes one sheet per data row.
@MainActor
final class MergeDialog: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    /// For the headless checks: fill the dialog and return true to merge.
    nonisolated(unsafe) static var headlessDriver: ((MergeDialog) -> Bool)?

    let window: NSWindow
    let sheet: Sheet
    let zoneField = NSTextField(string: "")
    let dataField = NSTextField(string: "")
    let fieldField = NSTextField(string: "")
    private let table = NSTableView()
    private let addButton = NSButton(title: Localization.title("Add"), target: nil, action: nil)
    private let changeButton = NSButton(title: Localization.title("Change"), target: nil, action: nil)
    private let deleteButton = NSButton(title: Localization.title("Delete"), target: nil, action: nil)
    private let mergeButton = NSButton(title: Localization.title("Merge"), target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    /// The list's rows: a data range and the field cell it fills.
    private(set) var rows: [(data: String, field: String)] = []
    private var completion: (@MainActor (Bool) -> Void)?

    init(sheet: Sheet) {
        self.sheet = sheet
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = Localization.title("Merge")
        window.isReleasedWhenClosed = false
        super.init()
        zoneField.stringValue = sheet.selectionText
        build()
        updateButtons()
    }

    private func build() {
        for (column, title) in [("data", "Data Range"), ("field", "Field")] {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column))
            tableColumn.title = title
            tableColumn.width = 230
            table.addTableColumn(tableColumn)
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
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true

        for field in [zoneField, dataField, fieldField] {
            field.delegate = self
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        }
        zoneField.placeholderString = "The range copied to each new sheet"
        dataField.placeholderString = "A column of values, such as D1:D20"
        fieldField.placeholderString = "A cell of the zone, such as B1"
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: Localization.title("Merge zone:")), zoneField],
            [NSTextField(labelWithString: Localization.title("Data range:")), dataField],
            [NSTextField(labelWithString: Localization.title("Field:")), fieldField],
        ])
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        for (button, action) in [(addButton, #selector(add(_:))), (changeButton, #selector(change(_:))), (deleteButton, #selector(delete(_:)))] {
            button.target = self
            button.action = action
        }
        let actions = NSStackView(views: [addButton, changeButton, deleteButton, NSView()])
        actions.orientation = .horizontal
        actions.spacing = 8
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 3
        mergeButton.target = self
        mergeButton.action = #selector(merge(_:))
        mergeButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: Localization.title("Cancel"), target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [NSView(), cancelButton, mergeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let stack = NSStackView(views: [grid, actions, scroll, status, buttons])
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
        window.initialFirstResponder = zoneField
    }

    // MARK: Running

    /// `completion` gets true when the merge ran.
    func run(in parent: NSWindow, completion: @escaping @MainActor (Bool) -> Void) {
        self.completion = completion
        if let driver = Self.headlessDriver {
            if driver(self) { merge(nil) } else { cancel(nil) }
            return
        }
        parent.beginSheet(window) { _ in }
    }

    private func end(merged: Bool) {
        if let parent = window.sheetParent { parent.endSheet(window) }
        window.close()
        let completion = self.completion
        self.completion = nil
        completion?(merged)
    }

    @objc func cancel(_ sender: Any?) { end(merged: false) }

    /// cb_merge_merge_clicked: the fields checked, the question about
    /// unequal columns asked (answered yes headlessly), the command run.
    @objc func merge(_ sender: Any?) {
        let fields = rows.map(\.field), data = rows.map(\.data)
        var shortest = 0, longest = 0
        if sheet.mergeDataLengths(data, shortest: &shortest, longest: &longest), shortest < longest, Self.headlessDriver == nil {
            let alert = NSAlert()
            alert.messageText = "The data columns range in length from \(shortest) to \(longest). Shall we trim the lengths to \(shortest) and proceed?"
            alert.addButton(withTitle: Localization.title("Yes"))
            alert.addButton(withTitle: Localization.title("No"))
            alert.beginSheetModal(for: window) { [self] response in
                guard response == .alertFirstButtonReturn else { return }
                runMerge(fields: fields, data: data, trim: true)
            }
            return
        }
        runMerge(fields: fields, data: data, trim: shortest < longest)
    }

    private func runMerge(fields: [String], data: [String], trim: Bool) {
        do {
            try sheet.mergeData(intoZone: zoneField.stringValue, fields: fields, data: data, trimmingToShortest: trim)
            end(merged: true)
        } catch {
            status.stringValue = error.localizedDescription
            NSLog("Gnumeric error: %@", error.localizedDescription)
            if Self.headlessDriver != nil { end(merged: false) }
        }
    }

    // MARK: The list

    private var selectedRow: Int? {
        let row = table.selectedRow
        return row >= 0 && row < rows.count ? row : nil
    }

    private var entriesAreRanges: Bool {
        sheet.isRangeText(dataField.stringValue, singleCell: false) && sheet.isRangeText(fieldField.stringValue, singleCell: true)
    }

    /// cb_merge_update_buttons.
    private func updateButtons() {
        addButton.isEnabled = entriesAreRanges
        changeButton.isEnabled = entriesAreRanges && selectedRow != nil
        deleteButton.isEnabled = selectedRow != nil
        mergeButton.isEnabled = !rows.isEmpty && sheet.isRangeText(zoneField.stringValue, singleCell: false)
    }

    func controlTextDidChange(_ notification: Notification) { updateButtons() }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if let row = selectedRow {
            dataField.stringValue = rows[row].data
            fieldField.stringValue = rows[row].field
        }
        updateButtons()
    }

    /// Add a data range and its field (the Add button; the texts as the
    /// GTK stores them, by `gnm_expr_entry_global_range_name`).
    func addRow(data: String, field: String) {
        rows.append((data, field))
        table.reloadData()
        table.selectRowIndexes([rows.count - 1], byExtendingSelection: false)
        updateButtons()
    }

    @objc func add(_ sender: Any?) {
        guard entriesAreRanges else { return }
        addRow(data: dataField.stringValue, field: fieldField.stringValue)
    }

    @objc func change(_ sender: Any?) {
        guard entriesAreRanges, let row = selectedRow else { return }
        rows[row] = (dataField.stringValue, fieldField.stringValue)
        table.reloadData()
        table.selectRowIndexes([row], byExtendingSelection: false)
        updateButtons()
    }

    @objc func delete(_ sender: Any?) {
        guard let row = selectedRow else { return }
        rows.remove(at: row)
        table.reloadData()
        updateButtons()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("data")
        let text = identifier.rawValue == "field" ? rows[row].field : rows[row].data
        if let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cell.textField?.stringValue = text
            return cell
        }
        let cell = NSTableCellView()
        cell.identifier = identifier
        let label = NSTextField(labelWithString: Localization.title(text))
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
