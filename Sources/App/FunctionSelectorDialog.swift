import AppKit
import GnmCocoa

/// The GTK function selector (dialog-function-select.c) as an alert
/// sheet: a group pop-up and a search field over the catalog, the
/// functions with their summaries, the chosen one's arguments and
/// description; Insert puts the name into the formula being edited, or
/// starts one.
@MainActor
final class FunctionSelectorDialog: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    /// For the headless checks: choose and return true to insert.
    nonisolated(unsafe) static var headlessDriver: ((FunctionSelectorDialog) -> Bool)?

    let alert = NSAlert()
    let groups: [FunctionGroup]
    let groupPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    let search = NSSearchField()
    let table = NSTableView()
    let details = NSTextField(wrappingLabelWithString: "")
    private(set) var shown: [FunctionInfo] = []

    /// Help → Functions (dialog_function_select_help): the same catalog
    /// to read, with nothing to insert.
    let helpOnly: Bool

    init(engine: Engine, helpOnly: Bool = false) {
        groups = engine.functionGroups
        self.helpOnly = helpOnly
        super.init()
        alert.messageText = helpOnly ? "Functions" : "Insert Function"
        alert.addButton(withTitle: helpOnly ? "Close" : "Insert")
        if !helpOnly { alert.addButton(withTitle: Localization.title("Cancel")) }
        groupPopUp.addItems(withTitles: ["All functions"] + groups.map(\.name))
        groupPopUp.target = self
        groupPopUp.action = #selector(filterChanged(_:))
        search.delegate = self
        search.placeholderString = "Name or description"
        let name = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        name.title = "Function"
        name.width = 130
        let summary = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("summary"))
        summary.title = "Description"
        summary.width = 330
        table.addTableColumn(name)
        table.addTableColumn(summary)
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(rowDoubleClicked(_:))
        details.preferredMaxLayoutWidth = 470
        details.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        alert.accessoryView = makeGrid()
        filterChanged(nil)
    }

    private func makeGrid() -> NSView {
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: 180).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 480).isActive = true
        search.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let top = NSStackView(views: [groupPopUp, search])
        top.orientation = .horizontal
        top.spacing = 8
        let detailsScroll = NSScrollView()
        details.isSelectable = true
        details.widthAnchor.constraint(equalToConstant: 470).isActive = true
        detailsScroll.documentView = details
        detailsScroll.hasVerticalScroller = true
        detailsScroll.borderType = .noBorder
        detailsScroll.heightAnchor.constraint(equalToConstant: 110).isActive = true
        detailsScroll.widthAnchor.constraint(equalToConstant: 480).isActive = true
        let stack = NSStackView(views: [top, scroll, detailsScroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        let size = stack.fittingSize
        stack.frame = NSRect(x: 0, y: 0, width: max(size.width, 480), height: size.height)
        return stack
    }

    /// The group and the search narrow the list (the GTK filters by name
    /// and description).
    @objc func filterChanged(_ sender: Any?) {
        let index = groupPopUp.indexOfSelectedItem
        let pool = index <= 0 ? groups.flatMap(\.functions) : groups[index - 1].functions
        let needle = search.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        shown = needle.isEmpty ? pool : pool.filter { $0.name.lowercased().contains(needle) || $0.summary.lowercased().contains(needle) }
        if index <= 0 { shown.sort { $0.name < $1.name } }
        table.reloadData()
        if !shown.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        showDetails()
    }

    func controlTextDidChange(_ obj: Notification) { filterChanged(nil) }

    var selectedFunction: FunctionInfo? {
        let row = table.selectedRow
        return row >= 0 && row < shown.count ? shown[row] : nil
    }

    /// Select a function by name (the headless checks).
    func select(named name: String) {
        if let row = shown.firstIndex(where: { $0.name == name }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            showDetails()
        }
    }

    private func showDetails() {
        guard let function = selectedFunction else {
            details.stringValue = ""
            return
        }
        var lines = ["\(function.name)(\(function.argumentNames.joined(separator: ", ")))"]
        for (name, description) in zip(function.argumentNames, function.argumentDescriptions) where !description.isEmpty {
            lines.append("\(name): \(description)")
        }
        if !function.descriptionText.isEmpty { lines.append(""); lines.append(function.descriptionText) }
        details.stringValue = lines.joined(separator: "\n")
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row < shown.count else { return nil }
        return tableColumn?.identifier.rawValue == "name" ? shown[row].name : shown[row].summary
    }

    func tableViewSelectionDidChange(_ notification: Notification) { showDetails() }

    @objc func rowDoubleClicked(_ sender: Any?) {
        guard selectedFunction != nil else { return }
        alert.buttons.first?.performClick(nil)
    }

    /// Present as a sheet; `insert` gets the chosen function.
    func present(in window: NSWindow, insert: @escaping (FunctionInfo) -> Void) {
        if let driver = Self.headlessDriver {
            if driver(self), let function = selectedFunction { insert(function) }
            return
        }
        alert.window.initialFirstResponder = search
        alert.beginSheetModal(for: window) { [self] response in
            guard !helpOnly, response == .alertFirstButtonReturn, let function = selectedFunction else { return }
            insert(function)
        }
    }

    /// Present as an application-modal window (Help → Functions with no
    /// workbook window open).
    func runModal() {
        alert.window.initialFirstResponder = search
        _ = alert.runModal()
    }
}
