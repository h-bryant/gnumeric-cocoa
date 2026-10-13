import AppKit
import GnmCocoa

/// The GTK Data Shuffling dialog (dialog-shuffle.c) as an alert sheet: the
/// range and whether its columns, rows, or all its cells are shuffled.
@MainActor
final class ShuffleDialog {
    /// For the headless checks: fill the fields and return true to run.
    nonisolated(unsafe) static var headlessDriver: ((ShuffleDialog) -> Bool)?

    let alert = NSAlert()
    let rangeField = NSTextField(string: "")
    let method = NSPopUpButton(frame: .zero, pullsDown: false)

    init(sheet: Sheet) {
        alert.messageText = "Data Shuffling"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        rangeField.stringValue = sheet.rangeNames(inList: sheet.selectionText)?.first ?? ""
        rangeField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        method.addItems(withTitles: ["Columns", "Rows", "Area"])
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.alignment = .right
            return field
        }
        let grid = NSGridView(views: [[label("Input range:"), rangeField], [label("Shuffle method:"), method]])
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        let size = grid.fittingSize
        grid.frame = NSRect(x: 0, y: 0, width: max(size.width, 320), height: size.height)
        alert.accessoryView = grid
        alert.window.initialFirstResponder = rangeField
    }

    var kind: Sheet.ShuffleKind { Sheet.ShuffleKind(rawValue: method.indexOfSelectedItem) ?? .columns }

    func present(in window: NSWindow, run: @escaping (String, Sheet.ShuffleKind) -> Bool) {
        if let driver = Self.headlessDriver {
            if driver(self) { _ = run(rangeField.stringValue, kind) }
            return
        }
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn else { return }
            if !run(rangeField.stringValue, kind) {
                DispatchQueue.main.async { [self] in present(in: window, run: run) }
            }
        }
    }
}
