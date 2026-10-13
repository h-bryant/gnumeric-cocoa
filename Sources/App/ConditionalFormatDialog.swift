import AppKit
import GnmCocoa

/// Format → Conditional Formatting… (dialog-cell-format-cond.c): the
/// conditions on the selection's cell in a table, an editor below for the
/// chosen or a new one (the condition, its x and y, and the parts of the
/// style it overlays: fill, text color, bold, italic, number format), Add,
/// Replace, Remove, Clear, and OK applying the list as one command.
@MainActor
final class ConditionalFormatDialog: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let window: NSWindow
    private let sheet: Sheet
    private let table = NSTableView()
    private let operatorPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let xField = NSTextField()
    private let yField = NSTextField()
    private let fillCheck = NSButton(checkboxWithTitle: "Fill:", target: nil, action: nil)
    private let fillWell = NSColorWell()
    private let textCheck = NSButton(checkboxWithTitle: "Text color:", target: nil, action: nil)
    private let textWell = NSColorWell()
    private let boldCheck = NSButton(checkboxWithTitle: "Bold", target: nil, action: nil)
    private let italicCheck = NSButton(checkboxWithTitle: "Italic", target: nil, action: nil)
    private let formatCheck = NSButton(checkboxWithTitle: "Number format:", target: nil, action: nil)
    private let formatField = NSTextField()
    private let replaceButton = NSButton(title: Localization.title("Replace"), target: nil, action: nil)
    private let removeButton = NSButton(title: Localization.title("Remove"), target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private(set) var conditions: [ConditionalFormat]
    private var completion: (@MainActor ([ConditionalFormat]?) -> Void)?

    init(sheet: Sheet) {
        self.sheet = sheet
        let edit = sheet.editPosition
        conditions = sheet.conditionalFormats(atColumn: edit.column, row: edit.row)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 520),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Conditional Formatting"
        window.isReleasedWhenClosed = false
        super.init()
        build()
        table.reloadData()
        updateButtons()
    }

    // MARK: Layout

    private func build() {
        for (identifier, title, width) in [("condition", "Condition", 300.0), ("style", "Style", 220.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = true
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true

        for op in ConditionalFormat.allOperators {
            let item = NSMenuItem(title: ConditionalFormat.label(for: ConditionalFormat.Operator(rawValue: op.intValue) ?? .greaterThan),
                                  action: nil, keyEquivalent: "")
            item.tag = op.intValue
            operatorPopUp.menu?.addItem(item)
        }
        operatorPopUp.selectItem(withTag: ConditionalFormat.Operator.greaterThan.rawValue)
        operatorPopUp.target = self
        operatorPopUp.action = #selector(operatorChanged(_:))
        xField.placeholderString = "x: a value, a cell, or an expression"
        yField.placeholderString = "y"
        fillWell.color = .systemYellow
        textWell.color = .systemRed
        formatField.placeholderString = "0.00"
        for well in [fillWell, textWell] { well.widthAnchor.constraint(equalToConstant: 44).isActive = true }

        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.alignment = .right
            return field
        }
        func row(_ views: [NSView]) -> NSStackView {
            let stack = NSStackView(views: views)
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8
            return stack
        }
        let grid = NSGridView(views: [
            [label("Condition:"), operatorPopUp],
            [label("x:"), xField],
            [label("y:"), yField],
            [label("Style:"), row([fillCheck, fillWell, textCheck, textWell, boldCheck, italicCheck])],
            [label(""), row([formatCheck, formatField])],
        ])
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        for index in 0..<grid.numberOfRows { grid.row(at: index).yPlacement = .center }

        let addButton = NSButton(title: Localization.title("Add"), target: self, action: #selector(add(_:)))
        replaceButton.target = self
        replaceButton.action = #selector(replace(_:))
        removeButton.target = self
        removeButton.action = #selector(remove(_:))
        let clearButton = NSButton(title: Localization.title("Clear All"), target: self, action: #selector(clearAll(_:)))
        let cancelButton = NSButton(title: Localization.title("Cancel"), target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        let okButton = NSButton(title: Localization.title("OK"), target: self, action: #selector(accept(_:)))
        okButton.keyEquivalent = "\r"
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.lineBreakMode = .byTruncatingTail
        let editButtons = row([addButton, replaceButton, removeButton, clearButton, NSView(), status])
        let buttons = row([NSView(), cancelButton, okButton])
        let stack = NSStackView(views: [scroll, grid, editButtons, buttons])
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
            content.widthAnchor.constraint(equalToConstant: 580),
        ])
        window.contentView = content
        window.initialFirstResponder = xField
        operatorChanged(nil)
    }

    // MARK: Running

    func run(in parent: NSWindow, completion: @escaping @MainActor ([ConditionalFormat]?) -> Void) {
        self.completion = completion
        parent.beginSheet(window) { _ in }
    }

    private func finish(_ result: [ConditionalFormat]?) {
        guard let parent = window.sheetParent else { return }
        parent.endSheet(window)
        window.close()
        let completion = self.completion
        self.completion = nil
        completion?(result)
    }

    @objc private func accept(_ sender: Any?) { finish(conditions) }
    @objc private func cancel(_ sender: Any?) { finish(nil) }

    // MARK: The editor

    private var selectedOperator: ConditionalFormat.Operator {
        ConditionalFormat.Operator(rawValue: operatorPopUp.selectedTag()) ?? .greaterThan
    }

    @objc private func operatorChanged(_ sender: Any?) {
        let operands = ConditionalFormat.operandCount(for: selectedOperator)
        xField.isEnabled = operands >= 1
        yField.isEnabled = operands >= 2
    }

    /// What the editor describes.
    func condition() -> ConditionalFormat {
        let c = ConditionalFormat()
        c.op = selectedOperator
        c.firstExpression = xField.stringValue
        c.secondExpression = yField.stringValue
        let format = CellFormat()
        if fillCheck.state == .on {
            format.fillsBackground = true
            format.backgroundColor = fillWell.color.cgColor
        }
        if textCheck.state == .on { format.textColor = textWell.color.cgColor }
        if boldCheck.state == .on { format.bold = true }
        if italicCheck.state == .on { format.italic = true }
        if formatCheck.state == .on, !formatField.stringValue.isEmpty { format.numberFormat = formatField.stringValue }
        c.format = format
        return c
    }

    /// For the headless hook and tests of the dialog: the editor's fields.
    func setEditor(op: ConditionalFormat.Operator, x: String, y: String = "", fill: NSColor? = nil, bold: Bool = false) {
        operatorPopUp.selectItem(withTag: op.rawValue)
        operatorChanged(nil)
        xField.stringValue = x
        yField.stringValue = y
        fillCheck.state = fill == nil ? .off : .on
        if let fill { fillWell.color = fill }
        boldCheck.state = bold ? .on : .off
    }

    private func load(_ c: ConditionalFormat) {
        operatorPopUp.selectItem(withTag: c.op.rawValue)
        operatorChanged(nil)
        xField.stringValue = c.firstExpression
        yField.stringValue = c.secondExpression
        let format = c.format
        fillCheck.state = format.backgroundColor != nil ? .on : .off
        if let color = format.backgroundColor { fillWell.color = NSColor(cgColor: color) ?? fillWell.color }
        textCheck.state = format.textColor != nil ? .on : .off
        if let color = format.textColor { textWell.color = NSColor(cgColor: color) ?? textWell.color }
        boldCheck.state = format.bold?.boolValue == true ? .on : .off
        italicCheck.state = format.italic?.boolValue == true ? .on : .off
        formatCheck.state = format.numberFormat != nil ? .on : .off
        formatField.stringValue = format.numberFormat ?? ""
    }

    private func check(_ c: ConditionalFormat) -> Bool {
        let operands = ConditionalFormat.operandCount(for: c.op)
        if operands >= 1 && c.firstExpression.isEmpty { status.stringValue = "A value for x is needed."; return false }
        if operands >= 2 && c.secondExpression.isEmpty { status.stringValue = "A value for y is needed."; return false }
        status.stringValue = ""
        return true
    }

    @objc func add(_ sender: Any?) {
        let c = condition()
        guard check(c) else { return }
        conditions.append(c)
        table.reloadData()
        table.selectRowIndexes([conditions.count - 1], byExtendingSelection: false)
        updateButtons()
    }

    @objc private func replace(_ sender: Any?) {
        let row = table.selectedRow
        guard row >= 0, row < conditions.count else { return }
        let c = condition()
        guard check(c) else { return }
        conditions[row] = c
        table.reloadData()
        table.selectRowIndexes([row], byExtendingSelection: false)
    }

    @objc private func remove(_ sender: Any?) {
        let row = table.selectedRow
        guard row >= 0, row < conditions.count else { return }
        conditions.remove(at: row)
        table.reloadData()
        updateButtons()
    }

    @objc private func clearAll(_ sender: Any?) {
        conditions = []
        table.reloadData()
        updateButtons()
    }

    private func updateButtons() {
        let chosen = table.selectedRow >= 0 && table.selectedRow < conditions.count
        replaceButton.isEnabled = chosen
        removeButton.isEnabled = chosen
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { conditions.count }

    static func describe(_ c: ConditionalFormat) -> String {
        var text = ConditionalFormat.label(for: c.op)
        let operands = ConditionalFormat.operandCount(for: c.op)
        if operands >= 1 { text = text.replacingOccurrences(of: " x", with: " " + c.firstExpression) }
        if operands >= 2 { text = text.replacingOccurrences(of: " y", with: " " + c.secondExpression) }
        return text
    }

    static func describeStyle(_ format: CellFormat) -> String {
        var parts: [String] = []
        if format.backgroundColor != nil { parts.append("fill") }
        if format.textColor != nil { parts.append("text color") }
        if format.bold?.boolValue == true { parts.append("bold") }
        if format.italic?.boolValue == true { parts.append("italic") }
        if let number = format.numberFormat { parts.append("format " + number) }
        if format.fontName != nil || format.fontSize != nil { parts.append("font") }
        return parts.isEmpty ? "(no change)" : parts.joined(separator: ", ")
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, row < conditions.count else { return nil }
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
        let c = conditions[row]
        cell.textField?.stringValue = tableColumn.identifier.rawValue == "condition" ? Self.describe(c) : Self.describeStyle(c.format)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        if row >= 0, row < conditions.count { load(conditions[row]) }
        updateButtons()
    }
}
