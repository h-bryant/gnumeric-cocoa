import AppKit
import GnmCocoa

/// The GTK Compare Sheets dialog (dialog-sheet-compare.c) as a floating
/// panel: two sheets of any open workbook, Compare, and the differences
/// as a tree (Cells, Formatting, Columns/Rows) whose rows, when chosen,
/// bring the places into view on their sheets.
@MainActor
final class SheetCompareDialog: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let panel: NSPanel
    private weak var controller: WorkbookWindowController?
    private let workbookPopUps = [NSPopUpButton(frame: .zero, pullsDown: false), NSPopUpButton(frame: .zero, pullsDown: false)]
    private let sheetPopUps = [NSPopUpButton(frame: .zero, pullsDown: false), NSPopUpButton(frame: .zero, pullsDown: false)]
    private let outline = NSOutlineView()
    private let status = NSTextField(labelWithString: "")
    /// The open workbooks, as the dialog's selectors list them.
    private(set) var documents: [WorkbookDocument] = []
    /// The last comparison's tree: section heads with their entries.
    private(set) var results: [SheetDifference] = []

    init(controller: WorkbookWindowController) {
        self.controller = controller
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow],
                        backing: .buffered, defer: false)
        super.init()
        panel.title = Localization.title("Compare Sheets")
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 520, height: 360)
        panel.setFrameAutosaveName("SheetComparePanel")
        build()
        reloadSelectors()
        if let window = controller.window {
            NotificationCenter.default.addObserver(self, selector: #selector(documentWindowWillClose(_:)),
                                                   name: NSWindow.willCloseNotification, object: window)
        }
    }

    @objc private func documentWindowWillClose(_ notification: Notification) { panel.close() }

    private func build() {
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: Localization.title("Sheet A:")), workbookPopUps[0], sheetPopUps[0]],
            [NSTextField(labelWithString: Localization.title("Sheet B:")), workbookPopUps[1], sheetPopUps[1]],
        ])
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        for (index, popUp) in workbookPopUps.enumerated() {
            popUp.target = self
            popUp.action = #selector(workbookChosen(_:))
            popUp.tag = index
            popUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
            sheetPopUps[index].widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        }
        let compareButton = NSButton(title: Localization.title("Compare"), target: self, action: #selector(compare(_:)))
        compareButton.keyEquivalent = "\r"
        let top = NSStackView(views: [grid, NSView(), compareButton])
        top.orientation = .horizontal
        top.alignment = .bottom
        top.spacing = 12

        for (identifier, title, width) in [("description", "Description", 150.0), ("location", "Location", 100.0), ("old", "Old", 160.0), ("new", "New", 160.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            outline.addTableColumn(column)
        }
        outline.outlineTableColumn = outline.tableColumns[0]
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.usesAlternatingRowBackgroundColors = true
        outline.allowsEmptySelection = true
        outline.dataSource = self
        outline.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.lineBreakMode = .byTruncatingTail
        let closeButton = NSButton(title: Localization.title("Close"), target: self, action: #selector(close(_:)))
        closeButton.keyEquivalent = "\u{1b}"
        let bottom = NSStackView(views: [status, NSView(), closeButton])
        bottom.orientation = .horizontal
        bottom.spacing = 8
        let stack = NSStackView(views: [top, scroll, bottom])
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
        ])
        panel.contentView = content
    }

    // MARK: The selectors

    /// The open workbooks and their sheets; the defaults as
    /// select_default_sheets picks them: this workbook against the other
    /// one when two are open, else this sheet against the next.
    func reloadSelectors() {
        documents = NSDocumentController.shared.documents.compactMap { $0 as? WorkbookDocument }.filter { $0.workbook != nil }
        let names: [String] = documents.map { $0.displayName ?? "Untitled" }
        for popUp in workbookPopUps {
            popUp.removeAllItems()
            popUp.addItems(withTitles: names)
        }
        guard let own = controller?.document as? WorkbookDocument, let index = documents.firstIndex(where: { $0 === own }) else {
            for index in 0..<2 { reloadSheets(of: index) }
            return
        }
        workbookPopUps[0].selectItem(at: index)
        workbookPopUps[1].selectItem(at: documents.count > 1 ? (index == 0 ? 1 : 0) : index)
        for index in 0..<2 { reloadSheets(of: index) }
        if documents.count == 1, let workbook = own.workbook, workbook.sheets.count > 1 {
            sheetPopUps[0].selectItem(at: 0)
            sheetPopUps[1].selectItem(at: 1)
        }
    }

    private func reloadSheets(of index: Int) {
        let popUp = sheetPopUps[index]
        popUp.removeAllItems()
        let chosen = workbookPopUps[index].indexOfSelectedItem
        guard chosen >= 0, chosen < documents.count, let workbook = documents[chosen].workbook else { return }
        popUp.addItems(withTitles: workbook.sheets.map(\.name))
        if let current = workbook.currentSheet, let row = workbook.sheets.firstIndex(where: { $0 == current }) {
            popUp.selectItem(at: row)
        }
    }

    @objc private func workbookChosen(_ sender: NSPopUpButton) { reloadSheets(of: sender.tag) }

    /// The sheet a selector pair names.
    func sheet(at index: Int) -> Sheet? {
        let chosen = workbookPopUps[index].indexOfSelectedItem
        guard chosen >= 0, chosen < documents.count, let workbook = documents[chosen].workbook else { return nil }
        let row = sheetPopUps[index].indexOfSelectedItem
        return row >= 0 && row < workbook.sheets.count ? workbook.sheets[row] : nil
    }

    /// Choose the sheets by index in the current workbook (the headless checks).
    func selectSheets(a: Int, b: Int) {
        sheetPopUps[0].selectItem(at: a)
        sheetPopUps[1].selectItem(at: b)
    }

    // MARK: Comparing

    @objc func compare(_ sender: Any?) {
        guard let a = sheet(at: 0), let b = sheet(at: 1) else {
            status.stringValue = "Choose two sheets."
            return
        }
        results = b.differences(from: a)
        outline.reloadData()
        for head in results { outline.expandItem(head, expandChildren: true) }
        let count = results.reduce(0) { $0 + $1.children.count }
        status.stringValue = results.isEmpty ? "The sheets are the same." : "\(count) difference\(count == 1 ? "" : "s") in \(results.count) section\(results.count == 1 ? "" : "s")."
    }

    func show() {
        reloadSelectors()
        if !panel.isVisible, !panel.setFrameUsingName("SheetComparePanel") { panel.center() }
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func close(_ sender: Any?) { panel.close() }

    // MARK: The tree

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let difference = item as? SheetDifference else { return results.count }
        return difference.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let difference = item as? SheetDifference else { return results[index] }
        return difference.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? SheetDifference)?.children.isEmpty == false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let difference = item as? SheetDifference, let identifier = tableColumn?.identifier else { return nil }
        let text: String
        switch identifier.rawValue {
        case "location": text = difference.location
        case "old": text = difference.beforeText
        case "new": text = difference.afterText
        default: text = difference.text
        }
        if let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cell.textField?.stringValue = text
            return cell
        }
        let cell = NSTableCellView()
        cell.identifier = identifier
        let label = NSTextField(labelWithString: Localization.title(text))
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    /// cb_cursor_changed: the chosen row's places brought into view on
    /// their sheets (the old one first, the new one in a different view
    /// when there is one).
    func outlineViewSelectionDidChange(_ notification: Notification) {
        reveal(outline.item(atRow: outline.selectedRow) as? SheetDifference)
    }

    func reveal(_ difference: SheetDifference?) {
        guard let difference, difference.direction != .none else { return }
        if let sheet = difference.beforeSheet {
            sheet.revealCell(atColumn: difference.beforeRange.start.column, row: difference.beforeRange.start.row)
        }
        if let sheet = difference.afterSheet, sheet.workbook != difference.beforeSheet?.workbook || difference.beforeSheet == nil {
            sheet.revealCell(atColumn: difference.afterRange.start.column, row: difference.afterRange.start.row)
        }
    }

    /// Select a row of the flattened, expanded tree (the headless checks).
    func select(row: Int) {
        guard row >= 0, row < outline.numberOfRows else { return }
        outline.selectRowIndexes([row], byExtendingSelection: false)
    }

    var selectedDifference: SheetDifference? { outline.item(atRow: outline.selectedRow) as? SheetDifference }
}
