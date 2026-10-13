import AppKit
import GnmCocoa

/// The Sort dialog (the GTK dialog-cell-sort.c, with a fixed six key rows
/// in place of its list): sort the rows by columns or the columns by
/// rows, keep a heading, choose the keys with their order and case
/// sensitivity, the locale whose collation orders text, and keep the
/// formats with the data.
@MainActor
final class SortDialog: NSObject {
    struct Request {
        let range: CellRange
        let byRows: Bool
        let hasHeader: Bool
        let keys: [SortKey]
        let retainFormats: Bool
        /// The collation's locale; nil for the current one.
        let locale: String?
    }

    /// The key rows offered.
    static let keyRows = 6
    /// The locales the pop-up offers; the current one first (empty).
    static let locales = ["", "C", "en_US.UTF-8", "en_GB.UTF-8", "de_DE.UTF-8", "fr_FR.UTF-8", "es_ES.UTF-8", "it_IT.UTF-8",
                          "pt_BR.UTF-8", "nl_NL.UTF-8", "sv_SE.UTF-8", "ja_JP.UTF-8", "zh_CN.UTF-8"]

    private let sheet: Sheet
    private let range: CellRange
    private let direction = NSPopUpButton(frame: .zero, pullsDown: false)
    private let header = NSButton(checkboxWithTitle: "Range contains a header", target: nil, action: nil)
    private let retainFormats = NSButton(checkboxWithTitle: "Keep formats with the data", target: nil, action: nil)
    private let keyPopUps = (0..<SortDialog.keyRows).map { _ in NSPopUpButton(frame: .zero, pullsDown: false) }
    private let orderPopUps = (0..<SortDialog.keyRows).map { _ in NSPopUpButton(frame: .zero, pullsDown: false) }
    private let caseChecks = (0..<SortDialog.keyRows).map { _ in NSButton(checkboxWithTitle: "Case sensitive", target: nil, action: nil) }
    let locale = NSComboBox(frame: .zero)
    private let alert = NSAlert()
    /// The most entries a key pop-up lists (a whole-sheet selection would
    /// otherwise list every column).
    private static let maximumKeys = 1024

    init(sheet: Sheet, range: CellRange) {
        self.sheet = sheet
        self.range = range
        super.init()
        direction.addItem(withTitle: "Top to bottom (sort the rows)")
        direction.addItem(withTitle: "Left to right (sort the columns)")
        // The GTK dialog sorts the rows of a range taller than wide.
        direction.selectItem(at: range.end.row - range.start.row >= range.end.column - range.start.column ? 0 : 1)
        direction.target = self
        direction.action = #selector(layoutChanged(_:))
        header.state = sheet.range(range, hasHeadingByRows: byRows) ? .on : .off
        header.target = self
        header.action = #selector(layoutChanged(_:))
        retainFormats.state = Sheet.sortDefaultsToRetainingFormats ? .on : .off
        for (i, popUp) in orderPopUps.enumerated() {
            popUp.addItem(withTitle: "Ascending")
            popUp.addItem(withTitle: "Descending")
            popUp.selectItem(at: Sheet.sortDefaultsToAscending ? 0 : 1)
            caseChecks[i].state = Sheet.sortDefaultsToCaseSensitive ? .on : .off
        }
        rebuildKeys()
        alert.messageText = "Sort"
        alert.informativeText = "Sort \(rangeDescription) by the keys, in order."
        locale.addItems(withObjectValues: Self.locales.map { $0.isEmpty ? "(current)" : $0 })
        locale.stringValue = "(current)"
        locale.widthAnchor.constraint(equalToConstant: 160).isActive = true
        alert.addButton(withTitle: "Sort")
        alert.addButton(withTitle: "Cancel")
        var cells: [[NSView]] = [
            [NSTextField(labelWithString: "Direction:"), direction, NSView()],
            [NSView(), header, NSView()],
        ]
        for i in 0..<Self.keyRows {
            cells.append([NSTextField(labelWithString: i == 0 ? "Sort by:" : "Then by:"), keyPopUps[i], orderPopUps[i]])
            cells.append([NSView(), caseChecks[i], NSView()])
        }
        cells.append([NSTextField(labelWithString: "Locale:"), locale, NSView()])
        cells.append([NSView(), retainFormats, NSView()])
        let grid = NSGridView(views: cells)
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        for popUp in keyPopUps {
            popUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        }
        grid.frame = NSRect(x: 0, y: 0, width: 440, height: grid.fittingSize.height)
        alert.accessoryView = grid
    }

    private var rangeDescription: String {
        "\(sheet.name(ofColumn: range.start.column))\(sheet.name(ofRow: range.start.row)):"
            + "\(sheet.name(ofColumn: range.end.column))\(sheet.name(ofRow: range.end.row))"
    }

    private var byRows: Bool { direction.indexOfSelectedItem == 0 }

    /// The key pop-ups list the range's columns (or rows) by name; the
    /// second and third also offer "(none)".  Selections survive a
    /// relabeling when the direction or the header toggle changes.
    private func rebuildKeys() {
        let hasHeader = header.state == .on
        let first = byRows ? range.start.column : range.start.row
        let last = byRows ? range.end.column : range.end.row
        let count = min(last - first + 1, Self.maximumKeys)
        for (i, popUp) in keyPopUps.enumerated() {
            let previous = popUp.selectedTag()
            popUp.removeAllItems()
            if i > 0 {
                popUp.addItem(withTitle: "(none)")
                popUp.lastItem?.tag = -1
            }
            for index in first..<(first + count) {
                popUp.addItem(withTitle: sheet.sortKeyName(forIndex: index, in: range, byRows: byRows, hasHeader: hasHeader))
                popUp.lastItem?.tag = index
            }
            if popUp.menu?.item(withTag: previous) != nil {
                _ = popUp.selectItem(withTag: previous)
            } else {
                popUp.selectItem(at: 0)
            }
        }
    }

    @objc private func layoutChanged(_ sender: Any?) {
        rebuildKeys()
    }

    /// Run as a sheet on `window`; `completion` gets nil on Cancel.
    func run(in window: NSWindow, completion: @escaping @MainActor (Request?) -> Void) {
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn else {
                completion(nil)
                return
            }
            let keys: [SortKey] = (0..<Self.keyRows).compactMap { i in
                let index = keyPopUps[i].selectedTag()
                guard index >= 0 else { return nil }
                return SortKey(index: index, descending: orderPopUps[i].indexOfSelectedItem == 1,
                               caseSensitive: caseChecks[i].state == .on, byValue: true)
            }
            let chosen = locale.stringValue.trimmingCharacters(in: .whitespaces)
            completion(Request(range: range, byRows: byRows, hasHeader: header.state == .on, keys: keys,
                               retainFormats: retainFormats.state == .on,
                               locale: chosen.isEmpty || chosen == "(current)" ? nil : chosen))
        }
    }
}
