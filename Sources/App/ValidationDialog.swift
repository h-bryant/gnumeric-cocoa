import AppKit
import GnmCocoa

/// The GTK Format Cells dialog's Validation and Input Message pages
/// (dialog-cell-format.c) as one alert sheet: the criteria (kind,
/// operator, the one or two values), empty cells, the in-cell list, the
/// action with its title and message, and the input message shown while
/// the cell is selected.  Prefilled from the edit position.
@MainActor
final class ValidationDialog: NSObject {
    /// For the headless checks: fill the fields and return true to apply.
    nonisolated(unsafe) static var headlessDriver: ((ValidationDialog) -> Bool)?

    static let kinds: [Validation.Kind] = [.any, .wholeNumber, .number, .inList, .date, .time, .textLength, .custom]
    static let operators: [Validation.Operator] = [.between, .notBetween, .equal, .notEqual, .greaterThan, .lessThan, .greaterOrEqual, .lessOrEqual]
    static let actions: [Validation.Action] = [.none, .stop, .warning, .information]

    let alert = NSAlert()
    let kind = NSPopUpButton(frame: .zero, pullsDown: false)
    let op = NSPopUpButton(frame: .zero, pullsDown: false)
    let firstLabel = NSTextField(labelWithString: "Min:")
    let secondLabel = NSTextField(labelWithString: "Max:")
    let firstField = NSTextField(string: "")
    let secondField = NSTextField(string: "")
    let allowBlank = NSButton(checkboxWithTitle: "Ignore empty cells", target: nil, action: nil)
    let dropdown = NSButton(checkboxWithTitle: "In-cell dropdown", target: nil, action: nil)
    let action = NSPopUpButton(frame: .zero, pullsDown: false)
    let errorTitle = NSTextField(string: "")
    let errorMessage = NSTextField(string: "")
    let messageTitle = NSTextField(string: "")
    let messageText = NSTextField(string: "")

    init(sheet: Sheet) {
        super.init()
        alert.messageText = "Data Validation"
        alert.informativeText = "What the selected cells accept, and the message shown while one is selected."
        alert.addButton(withTitle: Localization.title("OK"))
        alert.addButton(withTitle: Localization.title("Cancel"))
        kind.addItems(withTitles: Self.kinds.map { Validation.label(for: $0) })
        op.addItems(withTitles: Self.operators.map { Validation.label(for: $0) })
        action.addItems(withTitles: Self.actions.map { Validation.label(for: $0) })
        allowBlank.state = .on
        dropdown.state = .on
        action.selectItem(at: 1)
        let cell = sheet.editPosition
        if let current = sheet.validation(atColumn: cell.column, row: cell.row) {
            kind.selectItem(at: Self.kinds.firstIndex(of: current.kind) ?? 0)
            op.selectItem(at: Self.operators.firstIndex(of: current.op) ?? 0)
            firstField.stringValue = current.firstExpression
            secondField.stringValue = current.secondExpression
            allowBlank.state = current.allowsBlank ? .on : .off
            dropdown.state = current.usesDropdown ? .on : .off
            action.selectItem(at: Self.actions.firstIndex(of: current.action) ?? 1)
            errorTitle.stringValue = current.errorTitle
            errorMessage.stringValue = current.errorMessage
        }
        if let message = sheet.inputMessage(atColumn: cell.column, row: cell.row) {
            messageTitle.stringValue = message.title
            messageText.stringValue = message.message
        }
        for field in [firstField, secondField, errorTitle, errorMessage, messageTitle, messageText] {
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        }
        errorMessage.placeholderString = "The engine's own words when empty"
        kind.target = self
        kind.action = #selector(criteriaChanged(_:))
        op.target = self
        op.action = #selector(criteriaChanged(_:))
        alert.accessoryView = makeGrid()
        criteriaChanged(nil)
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
        firstLabel.alignment = .right
        secondLabel.alignment = .right
        let rows: [[NSView]] = [
            [heading("Criteria"), NSGridCell.emptyContentView],
            [label("Allow:"), kind], [label("Condition:"), op],
            [firstLabel, firstField], [secondLabel, secondField],
            [NSGridCell.emptyContentView, allowBlank], [NSGridCell.emptyContentView, dropdown],
            [heading("Error alert"), NSGridCell.emptyContentView],
            [label("Action:"), action], [label("Title:"), errorTitle], [label("Message:"), errorMessage],
            [heading("Input message"), NSGridCell.emptyContentView],
            [label("Title:"), messageTitle], [label("Message:"), messageText],
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
        grid.frame = NSRect(x: 0, y: 0, width: max(size.width, 380), height: size.height)
        return grid
    }

    var selectedKind: Validation.Kind { Self.kinds[max(0, kind.indexOfSelectedItem)] }
    var selectedOperator: Validation.Operator { Self.operators[max(0, op.indexOfSelectedItem)] }

    /// The value rows follow the kind and operator (cb_validation_sensitivity).
    @objc func criteriaChanged(_ sender: Any?) {
        let count = Validation.operandCount(for: selectedKind, operator: selectedOperator)
        let takesOperator = ![.any, .inList, .custom].contains(selectedKind)
        op.isEnabled = takesOperator
        firstLabel.stringValue = Validation.firstOperandLabel(for: selectedKind, operator: selectedOperator) ?? "Value:"
        firstField.isEnabled = count >= 1
        secondLabel.stringValue = "Max:"
        secondField.isEnabled = count >= 2
        dropdown.isEnabled = selectedKind == .inList
        let validates = selectedKind != .any
        allowBlank.isEnabled = validates
        action.isEnabled = validates
        errorTitle.isEnabled = validates
        errorMessage.isEnabled = validates
    }

    /// The validation as the fields describe it; nil for Any Value.
    func makeValidation() -> Validation? {
        guard selectedKind != .any else { return nil }
        let validation = Validation()
        validation.kind = selectedKind
        validation.op = selectedOperator
        validation.firstExpression = firstField.stringValue
        validation.secondExpression = secondField.stringValue
        validation.allowsBlank = allowBlank.state == .on
        validation.usesDropdown = dropdown.state == .on
        validation.action = Self.actions[max(0, action.indexOfSelectedItem)]
        validation.errorTitle = errorTitle.stringValue
        validation.errorMessage = errorMessage.stringValue
        return validation
    }

    /// The input message, or nil when both fields are empty.
    func makeInputMessage() -> InputMessage? {
        guard !messageTitle.stringValue.isEmpty || !messageText.stringValue.isEmpty else { return nil }
        return InputMessage(title: messageTitle.stringValue, message: messageText.stringValue)
    }

    /// Present as a sheet; `apply` gets the choices on OK and returns
    /// whether they were accepted (a refusal re-presents).
    func present(in window: NSWindow, apply: @escaping (Validation?, InputMessage?) -> Bool) {
        if let driver = Self.headlessDriver {
            if driver(self) { _ = apply(makeValidation(), makeInputMessage()) }
            return
        }
        alert.window.initialFirstResponder = firstField
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn else { return }
            if !apply(makeValidation(), makeInputMessage()) {
                DispatchQueue.main.async { [self] in present(in: window, apply: apply) }
            }
        }
    }
}
