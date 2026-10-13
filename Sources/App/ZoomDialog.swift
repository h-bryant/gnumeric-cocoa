import AppKit
import GnmCocoa

/// The GTK Zoom dialog (dialog-zoom.c) as an alert sheet: a percentage
/// from the presets or typed, applied to the sheet or to all sheets as
/// one undoable `cmd_zoom`.
@MainActor
final class ZoomDialog {
    /// For the headless checks: fill the fields and return true to apply.
    nonisolated(unsafe) static var headlessDriver: ((ZoomDialog) -> Bool)?

    static let presets = [400, 200, 150, 100, 75, 50, 25]
    let alert = NSAlert()
    let percentField = NSComboBox(frame: .zero)
    let allSheets = NSButton(checkboxWithTitle: Localization.title("All sheets"), target: nil, action: nil)

    init(sheet: Sheet) {
        alert.messageText = Localization.title("Zoom")
        alert.addButton(withTitle: Localization.title("OK"))
        alert.addButton(withTitle: Localization.title("Cancel"))
        percentField.addItems(withObjectValues: Self.presets.map { "\($0)%" })
        percentField.stringValue = "\(Int((sheet.zoomFactor * 100).rounded()))%"
        percentField.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let label = NSTextField(labelWithString: Localization.title("Zoom:"))
        label.alignment = .right
        let grid = NSGridView(views: [[label, percentField], [NSGridCell.emptyContentView, allSheets]])
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        let size = grid.fittingSize
        grid.frame = NSRect(x: 0, y: 0, width: max(size.width, 220), height: size.height)
        alert.accessoryView = grid
        alert.window.initialFirstResponder = percentField
    }

    /// The percentage typed, 10 to 500 as the GTK spin button allows.
    var percentage: Int? {
        let text = percentField.stringValue.trimmingCharacters(in: CharacterSet(charactersIn: "% ")).trimmingCharacters(in: .whitespaces)
        guard let value = Double(text), value >= 10, value <= 500 else { return nil }
        return Int(value.rounded())
    }

    /// Present as a sheet; `apply` gets the factor and whether all
    /// sheets take it, and returns whether it was accepted.
    func present(in window: NSWindow, apply: @escaping (Double, Bool) -> Bool) {
        if let driver = Self.headlessDriver {
            if driver(self), let percentage { _ = apply(Double(percentage) / 100, allSheets.state == .on) }
            return
        }
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn else { return }
            guard let percentage, apply(Double(percentage) / 100, allSheets.state == .on) else {
                DispatchQueue.main.async { [self] in present(in: window, apply: apply) }
                return
            }
        }
    }
}
