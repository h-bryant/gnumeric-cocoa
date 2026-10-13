import AppKit
import GnmCocoa

/// The GTK Tabulate Dependency dialog (dialog-tabulate.c) as an alert
/// sheet: up to three dependency cells with their ranges and steps, the
/// result cell, and the visual or coordinate layout.
@MainActor
final class TabulateDialog {
    /// For the headless checks: fill the fields and return true to apply.
    nonisolated(unsafe) static var headlessDriver: ((TabulateDialog) -> Bool)?

    @MainActor
    struct Row {
        let cell = NSTextField(string: "")
        let minimum = NSTextField(string: "")
        let maximum = NSTextField(string: "")
        let step = NSTextField(string: "")
    }

    let alert = NSAlert()
    let rows = [Row(), Row(), Row()]
    let resultField = NSTextField(string: "")
    let mode = NSPopUpButton(frame: .zero, pullsDown: false)

    init(sheet: Sheet) {
        alert.messageText = Localization.title("Tabulate Dependency")
        alert.addButton(withTitle: Localization.title("Tabulate"))
        alert.addButton(withTitle: Localization.title("Cancel"))
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
        mode.addItems(withTitles: ["Visual: a table", "Coordinate: one row per combination"])
        let edit = sheet.editPosition
        resultField.stringValue = sheet.name(of: CellRange(start: edit, end: edit))
        var views: [[NSView]] = [[heading("Dependency cell"), heading("Minimum"), heading("Maximum"), heading("Step")]]
        for row in rows {
            row.cell.widthAnchor.constraint(equalToConstant: 90).isActive = true
            for field in [row.minimum, row.maximum, row.step] { field.widthAnchor.constraint(equalToConstant: 70).isActive = true }
            views.append([row.cell, row.minimum, row.maximum, row.step])
        }
        resultField.widthAnchor.constraint(equalToConstant: 90).isActive = true
        views.append([label("Result cell:"), resultField, NSGridCell.emptyContentView, NSGridCell.emptyContentView])
        views.append([label("Tabulation style:"), mode, NSGridCell.emptyContentView, NSGridCell.emptyContentView])
        let grid = NSGridView(views: views)
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.cell(for: mode)?.row?.mergeCells(in: NSRange(location: 1, length: 3))
        let size = grid.fittingSize
        grid.frame = NSRect(x: 0, y: 0, width: max(size.width, 380), height: size.height)
        alert.accessoryView = grid
        alert.window.initialFirstResponder = rows[0].cell
    }

    /// The rows with a cell, as dimensions (numbers that do not parse come
    /// through as NaN for the bridge's messages).
    var dimensions: [TabulationDimension] {
        rows.filter { !$0.cell.stringValue.isEmpty }.map { row in
            TabulationDimension(cell: row.cell.stringValue, minimum: Double(row.minimum.stringValue) ?? .nan,
                                maximum: Double(row.maximum.stringValue) ?? .nan,
                                step: row.step.stringValue.isEmpty ? 1 : (Double(row.step.stringValue) ?? .nan))
        }
    }

    var withCoordinates: Bool { mode.indexOfSelectedItem == 1 }

    /// Present as a sheet; `apply` returns whether the choices were
    /// accepted (a refusal re-presents).
    func present(in window: NSWindow, apply: @escaping (TabulateDialog) -> Bool) {
        if let driver = Self.headlessDriver {
            if driver(self) { _ = apply(self) }
            return
        }
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn else { return }
            if !apply(self) {
                DispatchQueue.main.async { [self] in present(in: window, apply: apply) }
            }
        }
    }
}
