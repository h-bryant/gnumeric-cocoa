import AppKit
import GnmCocoa

/// The Manage Sheets dialog (dialog-sheet-order.c) as a sheet: every
/// workbook sheet in a table with its lock, visibility, name, and text
/// direction, the tab colors of the chosen one below, and buttons to
/// insert, append, duplicate, remove, move, and sort.  As in the GTK,
/// each change is applied at once as an undoable engine command, and
/// Undo takes the last one back.
@MainActor
final class ManageSheetsDialog: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let window: NSWindow
    private let workbook: Workbook
    private let table = NSTableView()
    private let backgroundWell = NSColorWell()
    private let textWell = NSColorWell()
    private let clearBackgroundButton = NSButton(title: "Clear", target: nil, action: nil)
    private let clearTextButton = NSButton(title: "Clear", target: nil, action: nil)
    private let insertButton = NSButton(title: "Insert", target: nil, action: nil)
    private let appendButton = NSButton(title: "Append", target: nil, action: nil)
    private let duplicateButton = NSButton(title: "Duplicate", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove", target: nil, action: nil)
    private let upButton = NSButton(title: "Up", target: nil, action: nil)
    private let downButton = NSButton(title: "Down", target: nil, action: nil)
    private let sortAscendingButton = NSButton(title: "Sort A → Z", target: nil, action: nil)
    private let sortDescendingButton = NSButton(title: "Sort Z → A", target: nil, action: nil)
    private let undoButton = NSButton(title: "Undo", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private(set) var sheets: [Sheet] = []
    private var completion: (@MainActor () -> Void)?
    private var updatingWells = false

    init(workbook: Workbook) {
        self.workbook = workbook
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Manage Sheets"
        window.isReleasedWhenClosed = false
        super.init()
        build()
        reload(selecting: workbook.currentSheet)
    }

    // MARK: Layout

    private func build() {
        for (identifier, title, width) in [("lock", "Locked", 56.0), ("visible", "Shown", 56.0), ("name", "Name", 220.0), ("rtl", "Right to Left", 90.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            column.minWidth = 40
            table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.usesAlternatingRowBackgroundColors = true
        table.allowsEmptySelection = true
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        for (button, action) in [(insertButton, #selector(insert(_:))), (appendButton, #selector(append(_:))),
                                 (duplicateButton, #selector(duplicate(_:))), (removeButton, #selector(remove(_:))),
                                 (upButton, #selector(moveUp(_:))), (downButton, #selector(moveDown(_:))),
                                 (sortAscendingButton, #selector(sortAscending(_:))), (sortDescendingButton, #selector(sortDescending(_:))),
                                 (undoButton, #selector(undo(_:))), (clearBackgroundButton, #selector(clearBackground(_:))),
                                 (clearTextButton, #selector(clearText(_:)))] {
            button.target = self
            button.action = action
        }
        let side = NSStackView(views: [insertButton, appendButton, duplicateButton, removeButton, NSBox.separatorLine(),
                                       upButton, downButton, NSBox.separatorLine(), sortAscendingButton, sortDescendingButton])
        side.orientation = .vertical
        side.alignment = .width
        side.spacing = 6
        side.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let listRow = NSStackView(views: [scroll, side])
        listRow.orientation = .horizontal
        listRow.alignment = .top
        listRow.spacing = 12

        backgroundWell.target = self
        backgroundWell.action = #selector(backgroundChanged(_:))
        textWell.target = self
        textWell.action = #selector(textChanged(_:))
        for well in [backgroundWell, textWell] {
            well.widthAnchor.constraint(equalToConstant: 44).isActive = true
            well.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        let colors = NSStackView(views: [NSTextField(labelWithString: "Tab color:"), backgroundWell, clearBackgroundButton,
                                         NSTextField(labelWithString: "Text color:"), textWell, clearTextButton, NSView()])
        colors.orientation = .horizontal
        colors.spacing = 8
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.lineBreakMode = .byTruncatingTail
        let closeButton = NSButton(title: "Close", target: self, action: #selector(close(_:)))
        closeButton.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [undoButton, status, NSView(), closeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let stack = NSStackView(views: [listRow, colors, buttons])
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
            content.widthAnchor.constraint(equalToConstant: 620),
        ])
        window.contentView = content
        window.initialFirstResponder = table
    }

    // MARK: Running

    func run(in parent: NSWindow, completion: @escaping @MainActor () -> Void) {
        self.completion = completion
        parent.beginSheet(window) { _ in }
    }

    @objc func close(_ sender: Any?) {
        window.makeFirstResponder(nil)   // commits a name being typed
        if let parent = window.sheetParent { parent.endSheet(window) }
        window.close()
        let completion = self.completion
        self.completion = nil
        completion?()
    }

    // MARK: The list

    /// The row chosen in the table.
    var selectedRow: Int { table.selectedRow }
    var selectedSheet: Sheet? {
        let row = table.selectedRow
        return row >= 0 && row < sheets.count ? sheets[row] : nil
    }

    func select(row: Int) {
        guard row >= 0, row < sheets.count else { return }
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
        updateButtons()
    }

    private func reload(selecting sheet: Sheet?) {
        sheets = workbook.sheets
        table.reloadData()
        if let sheet, let row = sheets.firstIndex(where: { $0 === sheet }) {
            table.selectRowIndexes([row], byExtendingSelection: false)
            table.scrollRowToVisible(row)
        } else {
            table.deselectAll(nil)
        }
        updateButtons()
    }

    private func updateButtons() {
        let row = table.selectedRow
        let chosen = selectedSheet
        insertButton.isEnabled = chosen != nil
        duplicateButton.isEnabled = chosen != nil
        removeButton.isEnabled = chosen != nil && workbook.canRemoveSheets
        upButton.isEnabled = row > 0
        downButton.isEnabled = row >= 0 && row < sheets.count - 1
        sortAscendingButton.isEnabled = sheets.count > 1
        sortDescendingButton.isEnabled = sheets.count > 1
        undoButton.isEnabled = workbook.undoLabel != nil
        undoButton.title = workbook.undoLabel.map { "Undo \($0)" } ?? "Undo"
        updatingWells = true
        if let chosen {
            backgroundWell.isEnabled = true
            textWell.isEnabled = true
            backgroundWell.color = chosen.tabColor().flatMap { NSColor(cgColor: $0) } ?? .clear
            textWell.color = chosen.tabTextColor().flatMap { NSColor(cgColor: $0) } ?? .clear
            clearBackgroundButton.isEnabled = chosen.tabColor() != nil
            clearTextButton.isEnabled = chosen.tabTextColor() != nil
        } else {
            backgroundWell.isEnabled = false
            textWell.isEnabled = false
            clearBackgroundButton.isEnabled = false
            clearTextButton.isEnabled = false
        }
        updatingWells = false
    }

    func numberOfRows(in tableView: NSTableView) -> Int { sheets.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, row < sheets.count else { return nil }
        let sheet = sheets[row]
        let identifier = tableColumn.identifier
        if identifier.rawValue == "name" {
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? {
                let view = NSTableCellView()
                view.identifier = identifier
                let field = NSTextField(string: "")
                field.isBordered = false
                field.drawsBackground = false
                field.isEditable = true
                field.lineBreakMode = .byTruncatingTail
                field.translatesAutoresizingMaskIntoConstraints = false
                field.target = self
                field.action = #selector(nameEdited(_:))
                (field.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
                view.addSubview(field)
                view.textField = field
                NSLayoutConstraint.activate([
                    field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
                    field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2),
                    field.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                ])
                return view
            }()
            cell.textField?.stringValue = sheet.name
            cell.textField?.tag = row
            cell.textField?.textColor = sheet.isVisible ? .labelColor : .secondaryLabelColor
            return cell
        }
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? {
            let view = NSTableCellView()
            view.identifier = identifier
            let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(boxToggled(_:)))
            box.identifier = identifier
            box.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(box)
            NSLayoutConstraint.activate([
                box.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                box.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
            return view
        }()
        if let box = cell.subviews.first as? NSButton {
            box.tag = row
            switch identifier.rawValue {
            case "lock": box.state = sheet.isProtected ? .on : .off
            case "visible": box.state = sheet.isVisible ? .on : .off
            default: box.state = sheet.isRightToLeft ? .on : .off
            }
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
    }

    // MARK: Changes, each an engine command

    private func apply(_ change: () throws -> Void, thenSelecting sheet: Sheet? = nil) {
        do {
            try change()
            status.stringValue = ""
        } catch {
            status.stringValue = error.localizedDescription
            NSLog("Gnumeric error: %@", error.localizedDescription)
        }
        reload(selecting: sheet ?? selectedSheet)
    }

    @objc private func boxToggled(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue, sender.tag >= 0, sender.tag < sheets.count else { return }
        let sheet = sheets[sender.tag]
        switch identifier {
        case "lock": toggleLock(row: sender.tag)
        case "visible": toggleVisible(row: sender.tag)
        default: _ = sheet; toggleDirection(row: sender.tag)
        }
    }

    func toggleLock(row: Int) {
        guard row >= 0, row < sheets.count else { return }
        let sheet = sheets[row]
        apply({ try workbook.setSheet(sheet, protected: !sheet.isProtected) }, thenSelecting: sheet)
    }

    func toggleVisible(row: Int) {
        guard row >= 0, row < sheets.count else { return }
        let sheet = sheets[row]
        apply({ try workbook.setSheet(sheet, visible: !sheet.isVisible) }, thenSelecting: sheet)
    }

    func toggleDirection(row: Int) {
        guard row >= 0, row < sheets.count else { return }
        let sheet = sheets[row]
        apply({ try sheet.toggleDisplayOption(.rightToLeft) }, thenSelecting: sheet)
    }

    @objc private func nameEdited(_ sender: NSTextField) {
        setName(sender.stringValue, forRow: sender.tag)
    }

    func setName(_ name: String, forRow row: Int) {
        guard row >= 0, row < sheets.count else { return }
        let sheet = sheets[row]
        guard name != sheet.name else { return }
        apply({ try workbook.rename(sheet, to: name) }, thenSelecting: sheet)
    }

    @objc func insert(_ sender: Any?) {
        guard let sheet = selectedSheet else { return }
        var added: Sheet?
        apply({ added = try workbook.insertSheet(before: sheet) })
        if let added { reload(selecting: added) }
    }

    @objc func append(_ sender: Any?) {
        var added: Sheet?
        apply({ added = try workbook.insertSheet(before: nil) })
        if let added { reload(selecting: added) }
    }

    @objc func duplicate(_ sender: Any?) {
        guard let sheet = selectedSheet else { return }
        var copy: Sheet?
        apply({ copy = try workbook.duplicate(sheet) })
        if let copy { reload(selecting: copy) }
    }

    @objc func remove(_ sender: Any?) {
        guard let sheet = selectedSheet, workbook.canRemoveSheets else { return }
        let row = table.selectedRow
        apply({ try workbook.remove(sheet) }, thenSelecting: nil)
        select(row: min(row, sheets.count - 1))
    }

    @objc func moveUp(_ sender: Any?) {
        guard let sheet = selectedSheet, table.selectedRow > 0 else { return }
        apply({ try workbook.move(sheet, toIndex: table.selectedRow - 1) }, thenSelecting: sheet)
    }

    @objc func moveDown(_ sender: Any?) {
        guard let sheet = selectedSheet, table.selectedRow < sheets.count - 1 else { return }
        apply({ try workbook.move(sheet, toIndex: table.selectedRow + 1) }, thenSelecting: sheet)
    }

    @objc func sortAscending(_ sender: Any?) {
        apply({ try workbook.sortSheets(ascending: true) })
    }

    @objc func sortDescending(_ sender: Any?) {
        apply({ try workbook.sortSheets(ascending: false) })
    }

    @objc func undo(_ sender: Any?) {
        guard workbook.undoLabel != nil else { return }
        workbook.undo()
        status.stringValue = ""
        reload(selecting: selectedSheet)
    }

    @objc private func backgroundChanged(_ sender: NSColorWell) {
        guard !updatingWells, let sheet = selectedSheet else { return }
        setTabColors(background: sender.color.cgColor, text: sheet.tabTextColor(), of: sheet)
    }

    @objc private func textChanged(_ sender: NSColorWell) {
        guard !updatingWells, let sheet = selectedSheet else { return }
        setTabColors(background: sheet.tabColor(), text: sender.color.cgColor, of: sheet)
    }

    @objc func clearBackground(_ sender: Any?) {
        guard let sheet = selectedSheet else { return }
        setTabColors(background: nil, text: sheet.tabTextColor(), of: sheet)
    }

    @objc func clearText(_ sender: Any?) {
        guard let sheet = selectedSheet else { return }
        setTabColors(background: sheet.tabColor(), text: nil, of: sheet)
    }

    func setTabColors(background: CGColor?, text: CGColor?, of sheet: Sheet) {
        apply({ try workbook.setTabColor(background, textColor: text, of: sheet) }, thenSelecting: sheet)
    }
}

private extension NSBox {
    static func separatorLine() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}
