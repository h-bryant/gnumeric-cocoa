import AppKit
import GnmCocoa

/// The GTK Data Table dialog (dialog-data-table.c) as an alert sheet: the
/// row and column input cells for a two-input table over the selection.
@MainActor
final class DataTableDialog {
    /// For the headless checks: fill the fields and return true to apply.
    nonisolated(unsafe) static var headlessDriver: ((DataTableDialog) -> Bool)?

    let alert = NSAlert()
    let rowField = NSTextField(string: "")
    let columnField = NSTextField(string: "")

    init() {
        alert.messageText = "Data Table"
        alert.informativeText = "The selection's first row and column hold the values; its top-left cell holds the formula."
        alert.addButton(withTitle: Localization.title("OK"))
        alert.addButton(withTitle: Localization.title("Cancel"))
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.alignment = .right
            return field
        }
        for field in [rowField, columnField] { field.widthAnchor.constraint(equalToConstant: 160).isActive = true }
        let grid = NSGridView(views: [[label("Row input cell:"), rowField], [label("Column input cell:"), columnField]])
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        let size = grid.fittingSize
        grid.frame = NSRect(x: 0, y: 0, width: max(size.width, 300), height: size.height)
        alert.accessoryView = grid
        alert.window.initialFirstResponder = rowField
    }

    /// Present as a sheet; `apply` gets the two cells and returns whether
    /// they were accepted (a refusal re-presents).
    func present(in window: NSWindow, apply: @escaping (String, String) -> Bool) {
        if let driver = Self.headlessDriver {
            if driver(self) { _ = apply(rowField.stringValue, columnField.stringValue) }
            return
        }
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn else { return }
            if !apply(rowField.stringValue, columnField.stringValue) {
                DispatchQueue.main.async { [self] in present(in: window, apply: apply) }
            }
        }
    }
}
