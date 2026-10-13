import AppKit
import GnmCocoa

/// The GTK Advanced Filter dialog (dialog-advanced-filter.c) as an alert
/// sheet: the list and criteria ranges, unique records only, and the
/// output (in place, a range, or a new sheet).
@MainActor
final class AdvancedFilterDialog {
    /// For the headless checks: fill the fields and return true to run.
    nonisolated(unsafe) static var headlessDriver: ((AdvancedFilterDialog) -> Bool)?

    let alert = NSAlert()
    let listField = NSTextField(string: "")
    let criteriaField = NSTextField(string: "")
    let unique = NSButton(checkboxWithTitle: Localization.title("Unique records only"), target: nil, action: nil)
    let destination = NSPopUpButton(frame: .zero, pullsDown: false)
    let outputField = NSTextField(string: "")

    init(sheet: Sheet) {
        alert.messageText = Localization.title("Advanced Filter")
        alert.addButton(withTitle: Localization.title("OK"))
        alert.addButton(withTitle: Localization.title("Cancel"))
        listField.stringValue = sheet.rangeNames(inList: sheet.selectionText)?.joined(separator: ", ") ?? ""
        destination.addItems(withTitles: ["Filter in-place", "Copy to range:", "New sheet"])
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
        for field in [listField, criteriaField, outputField] { field.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true }
        let grid = NSGridView(views: [[heading("Input"), NSGridCell.emptyContentView],
                                      [label("List range:"), listField], [label("Criteria range:"), criteriaField],
                                      [NSGridCell.emptyContentView, unique],
                                      [heading("Output"), NSGridCell.emptyContentView],
                                      [label("Place in:"), destination], [NSGridCell.emptyContentView, outputField]])
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        for index in [0, 4] {
            grid.cell(atColumnIndex: 0, rowIndex: index).xPlacement = .leading
            grid.row(at: index).topPadding = index == 0 ? 0 : 8
        }
        let size = grid.fittingSize
        grid.frame = NSRect(x: 0, y: 0, width: max(size.width, 360), height: size.height)
        alert.accessoryView = grid
        alert.window.initialFirstResponder = listField
    }

    func makeFilter() -> AdvancedFilter {
        let filter = AdvancedFilter()
        filter.listRange = listField.stringValue
        filter.criteriaRange = criteriaField.stringValue
        filter.uniqueOnly = unique.state == .on
        return filter
    }

    func makeOutput() -> AnalysisOutput {
        switch destination.indexOfSelectedItem {
        case 1: return AnalysisOutput(rangeNamed: outputField.stringValue)
        case 2: return AnalysisOutput.newSheet()
        default: return AnalysisOutput.inPlace()
        }
    }

    /// Present as a sheet; `run` returns whether the choices were accepted
    /// (a refusal re-presents).
    func present(in window: NSWindow, run: @escaping (AdvancedFilter, AnalysisOutput) -> Bool) {
        if let driver = Self.headlessDriver {
            if driver(self) { _ = run(makeFilter(), makeOutput()) }
            return
        }
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn else { return }
            if !run(makeFilter(), makeOutput()) {
                DispatchQueue.main.async { [self] in present(in: window, run: run) }
            }
        }
    }
}
