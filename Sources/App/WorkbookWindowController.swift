import AppKit
import SwiftUI
import GnmCocoa

/// The document window: name box and formula line on top, the grid in a
/// scroll view with column and row headers beside it, and sheet tabs at the
/// bottom.
@MainActor
final class WorkbookWindowController: NSWindowController, WorkbookDelegate, NSWindowDelegate, NSUserInterfaceValidations, NSTextFieldDelegate {
    let workbook: Workbook
    private weak var workbookDocument: WorkbookDocument?
    let gridView = GridView()
    private let scrollView = NSScrollView()
    private let nameBox = NSTextField(labelWithString: "")
    private let formulaField = NSTextField(labelWithString: "")
    private let tabs = SheetTabControl()
    /// The status bar's auto-expression: a pull-down showing "Sum = 42"
    /// whose items choose the function, as the GTK status bar does.
    private let autoExpression = NSPopUpButton(frame: .zero, pullsDown: true)
    private static let autoExpressionChoices: [(label: String, function: String)] = [
        ("Sum", "sum"), ("Min", "min"), ("Max", "max"), ("Average", "average"), ("Count", "count"),
    ]
    private let tabScroller = NSScrollView()
    private var tabSheets: [Sheet] = []
    /// Zoom steps for the View menu, as percentages.
    private static let zoomSteps: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4]

    init(workbook: Workbook, document: WorkbookDocument) {
        self.workbook = workbook
        self.workbookDocument = document
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 400, height: 300)
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
        workbook.delegate = self
        workbook.resendDelegateState()
        rebuildTabs()
        show(sheet: workbook.currentSheet ?? workbook.sheets.first)
        window.center()
        window.setFrameAutosaveName("WorkbookWindow")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Layout

    private func buildContent(in window: NSWindow) {
        nameBox.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        nameBox.alignment = .center
        nameBox.isBezeled = true
        nameBox.bezelStyle = .roundedBezel
        nameBox.widthAnchor.constraint(equalToConstant: 96).isActive = true
        formulaField.isBezeled = true
        formulaField.bezelStyle = .roundedBezel
        formulaField.lineBreakMode = .byTruncatingTail
        formulaField.isSelectable = true
        formulaField.isEditable = true
        formulaField.delegate = self
        formulaField.cell?.usesSingleLineMode = true
        formulaField.cell?.isScrollable = true
        formulaField.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let formulaBar = NSStackView(views: [nameBox, formulaField])
        formulaBar.orientation = .horizontal
        formulaBar.distribution = .fill
        formulaBar.spacing = 6
        formulaBar.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 2, right: 8)
        formulaBar.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        // Fixed heights: the SwiftUI-backed text fields of macOS 26 report a
        // taller intrinsic size once drawn, which re-laid out the window
        // under the first capture (2026-10-11).
        NSLayoutConstraint.activate([
            nameBox.heightAnchor.constraint(equalToConstant: 24),
            formulaField.heightAnchor.constraint(equalToConstant: 24),
            formulaBar.heightAnchor.constraint(equalToConstant: 32),
        ])

        scrollView.contentView = GridClipView()   // clamps scrolling under frozen panes
        scrollView.documentView = gridView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.usesPredominantAxisScrolling = false
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .white
        scrollView.drawsBackground = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        // Headers beside the scroll view, not NSRulerViews: see SheetHeaderView.
        let columnHeader = ColumnHeaderView(gridView: gridView)
        let rowHeader = RowHeaderView(gridView: gridView)
        gridView.headerViews = [columnHeader, rowHeader]
        let pane = NSView()
        pane.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(rowHeader)
        pane.addSubview(columnHeader)
        pane.addSubview(scrollView)
        NSLayoutConstraint.activate([
            rowHeader.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            rowHeader.topAnchor.constraint(equalTo: pane.topAnchor),
            rowHeader.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
            columnHeader.leadingAnchor.constraint(equalTo: rowHeader.trailingAnchor),
            columnHeader.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            columnHeader.topAnchor.constraint(equalTo: pane.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: rowHeader.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: columnHeader.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
        ])

        tabs.segmentStyle = .texturedRounded
        tabs.trackingMode = .selectOne
        tabs.target = self
        tabs.action = #selector(tabChanged(_:))
        tabs.menu = MainMenu.sheetMenu()   // right-click on a tab
        // Many sheets overflow the window: the tabs sit in a horizontally
        // scrolling strip (trackpad scroll, no visible scroller).
        tabScroller.documentView = tabs
        tabScroller.hasHorizontalScroller = false
        tabScroller.hasVerticalScroller = false
        tabScroller.verticalScrollElasticity = .none
        tabScroller.drawsBackground = false
        tabScroller.borderType = .noBorder
        tabScroller.heightAnchor.constraint(equalToConstant: 30).isActive = true
        autoExpression.bezelStyle = .texturedRounded
        autoExpression.controlSize = .small
        autoExpression.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        autoExpression.addItem(withTitle: "")   // the pull-down's title item
        for choice in Self.autoExpressionChoices {
            autoExpression.addItem(withTitle: choice.label)
            autoExpression.lastItem?.representedObject = choice.function
            autoExpression.lastItem?.target = self
            autoExpression.lastItem?.action = #selector(autoExpressionChosen(_:))
        }
        autoExpression.setContentHuggingPriority(.required, for: .horizontal)
        autoExpression.setContentCompressionResistancePriority(.required, for: .horizontal)
        let tabBar = NSStackView(views: [tabScroller, autoExpression])
        tabBar.orientation = .horizontal
        tabBar.distribution = .fill
        tabBar.spacing = 8
        tabBar.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        tabScroller.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let column = NSStackView(views: [formulaBar, pane, tabBar])
        column.orientation = .vertical
        column.distribution = .fill   /* the default, gravity areas, would not stretch the pane */
        column.spacing = 0
        column.alignment = .width
        column.translatesAutoresizingMaskIntoConstraints = false
        pane.setContentHuggingPriority(.defaultLow, for: .vertical)
        pane.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let content = NSView()
        content.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            column.topAnchor.constraint(equalTo: content.topAnchor),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
        window.initialFirstResponder = gridView
        gridView.geometryDidChange = { [weak self] in self?.updateSubtitle() }
        gridView.editingTextDidChange = { [weak self] text in
            guard let self else { return }
            if let text {
                self.formulaField.stringValue = text
            } else {
                self.workbook.resendDelegateState()   // back to the cell's real content
            }
        }
        gridView.presentError = { [weak self] error in self?.present(error) }
    }

    private func present(_ error: Error) {
        guard let window else { return }
        let alert = NSAlert(error: error)
        if let suggestion = (error as NSError).localizedRecoverySuggestion {
            alert.informativeText = suggestion
        }
        alert.beginSheetModal(for: window)
    }

    // MARK: Formula bar editing

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === formulaField else { return false }
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            gridView.setEditCellText(formulaField.stringValue)
            window?.makeFirstResponder(gridView)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            workbook.resendDelegateState()
            window?.makeFirstResponder(gridView)
            return true
        default:
            return false
        }
    }

    private func updateSubtitle() {
        guard let sheet = gridView.sheet else { return }
        let percent = Int((sheet.zoomFactor * 100).rounded())
        window?.subtitle = percent == 100 ? "" : "\(percent)%"
    }

    // MARK: Sheets

    /// For the headless checks.
    var tabCount: Int { tabs.segmentCount }

    private func rebuildTabs() {
        tabSheets = workbook.sheets.filter { $0.isVisible }
        tabs.segmentCount = tabSheets.count
        for (i, sheet) in tabSheets.enumerated() {
            tabs.setLabel(sheet.name, forSegment: i)
            tabs.setWidth(0, forSegment: i)
        }
        if let current = gridView.sheet, let index = tabSheets.firstIndex(of: current) {
            tabs.selectedSegment = index
        }
        // As a scroll view's document the control keeps its natural width,
        // so a long sheet list scrolls instead of being squeezed.
        tabs.translatesAutoresizingMaskIntoConstraints = true
        tabs.autoresizingMask = []
        tabs.sizeToFit()
        tabs.frame = NSRect(x: 0, y: 3, width: max(tabs.fittingSize.width, tabs.intrinsicContentSize.width), height: 24)
        if ProcessInfo.processInfo.environment["GNM_DEBUG_LAYOUT"] != nil {
            NSLog("tabs: %d segments, natural width %.1f", tabs.segmentCount, tabs.frame.width)
        }
    }

    private func revealSelectedTab() {
        guard tabs.selectedSegment >= 0 else { return }
        var x: CGFloat = 0
        for i in 0..<tabs.selectedSegment { x += tabs.width(forSegment: i) }
        // width(forSegment:) is 0 for auto-sized segments; fall back to a
        // proportional estimate.
        if x == 0 && tabs.selectedSegment > 0 {
            x = tabs.frame.width * CGFloat(tabs.selectedSegment) / CGFloat(max(tabs.segmentCount, 1))
        }
        tabs.scrollToVisible(NSRect(x: x, y: 0, width: tabs.frame.width / CGFloat(max(tabs.segmentCount, 1)), height: 24))
    }

    private func show(sheet: Sheet?) {
        gridView.sheet = sheet
        if let sheet, let index = tabSheets.firstIndex(of: sheet) {
            tabs.selectedSegment = index
            revealSelectedTab()
        }
        window?.makeFirstResponder(gridView)
        updateSubtitle()
    }

    // MARK: Column width and row height (Format menu)

    /// A sheet with one numeric field, in points; `completion` gets the
    /// value when the user confirms.
    private func promptSize(title: String, message: String, value: Double,
                            completion: @escaping @MainActor (Double) -> Void) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        let formatter = NumberFormatter()
        formatter.minimum = 0
        formatter.maximumFractionDigits = 2
        field.formatter = formatter
        field.doubleValue = value
        field.alignment = .right
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            completion(field.doubleValue)
        }
    }

    private func runSizeCommand(_ command: (Sheet) throws -> Void) {
        guard let sheet = gridView.sheet else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        do {
            try command(sheet)
        } catch {
            present(error)
        }
    }

    @objc func setColumnWidth(_ sender: Any?) {
        guard let sheet = gridView.sheet else { return }
        promptSize(title: "Column Width", message: "Width of the selected columns, in points. 0 restores the standard width.",
                   value: sheet.widthInPoints(ofColumn: sheet.selectedRange.start.column)) { [weak self] points in
            self?.runSizeCommand { try $0.setSelected(columns: true, sizeInPoints: points) }
        }
    }

    @objc func setRowHeight(_ sender: Any?) {
        guard let sheet = gridView.sheet else { return }
        promptSize(title: "Row Height", message: "Height of the selected rows, in points. 0 restores the standard height.",
                   value: sheet.heightInPoints(ofRow: sheet.selectedRange.start.row)) { [weak self] points in
            self?.runSizeCommand { try $0.setSelected(columns: false, sizeInPoints: points) }
        }
    }

    @objc func setDefaultColumnWidth(_ sender: Any?) {
        guard let sheet = gridView.sheet else { return }
        promptSize(title: "Standard Column Width", message: "Width of the columns without their own width, in points.",
                   value: sheet.defaultColumnWidthInPoints) { [weak self] points in
            guard points > 0 else { return }
            self?.runSizeCommand { try $0.setDefaultSizeInPoints(points, forColumns: true) }
        }
    }

    @objc func setDefaultRowHeight(_ sender: Any?) {
        guard let sheet = gridView.sheet else { return }
        promptSize(title: "Standard Row Height", message: "Height of the rows without their own height, in points.",
                   value: sheet.defaultRowHeightInPoints) { [weak self] points in
            guard points > 0 else { return }
            self?.runSizeCommand { try $0.setDefaultSizeInPoints(points, forColumns: false) }
        }
    }

    // MARK: Format Cells (Format menu)

    private var formatSheetWindow: NSWindow?

    @objc func formatCells(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, formatSheetWindow == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let range = sheet.selectedRange
        let multi = range.start.column != range.end.column || range.start.row != range.end.row
        let model = FormatCellsModel(format: sheet.formatOfSelection, isMultiCell: multi)
        let hosting = NSHostingController(rootView: FormatCellsView(model: model) { [weak self] accepted in
            self?.finishFormatCells(accepted: accepted, model: model)
        })
        let sheetWindow = NSWindow(contentViewController: hosting)
        sheetWindow.styleMask = [.titled]
        sheetWindow.title = "Format Cells"
        formatSheetWindow = sheetWindow
        window.beginSheet(sheetWindow) { [weak self] _ in self?.formatSheetWindow = nil }
    }

    private func finishFormatCells(accepted: Bool, model: FormatCellsModel) {
        if let sheetWindow = formatSheetWindow {
            window?.endSheet(sheetWindow)
        }
        guard accepted, let sheet = gridView.sheet else { return }
        do {
            try sheet.apply(model.changes())
        } catch {
            present(error)
        }
    }

    // MARK: Zoom (View menu, through the responder chain)

    private func setZoom(_ factor: Double) {
        guard let sheet = gridView.sheet else { return }
        sheet.zoomFactor = factor
    }

    @objc func zoomIn(_ sender: Any?) {
        guard let sheet = gridView.sheet else { return }
        if let next = Self.zoomSteps.first(where: { $0 > sheet.zoomFactor + 1e-6 }) { setZoom(next) }
    }

    @objc func zoomOut(_ sender: Any?) {
        guard let sheet = gridView.sheet else { return }
        if let prev = Self.zoomSteps.last(where: { $0 < sheet.zoomFactor - 1e-6 }) { setZoom(prev) }
    }

    @objc func zoomActualSize(_ sender: Any?) {
        setZoom(1)
    }

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        let zoom = gridView.sheet?.zoomFactor
        switch item.action {
        case #selector(zoomIn(_:)):
            guard let zoom else { return false }
            return zoom < Self.zoomSteps.last! - 1e-6
        case #selector(zoomOut(_:)):
            guard let zoom else { return false }
            return zoom > Self.zoomSteps.first! + 1e-6
        case #selector(zoomActualSize(_:)):
            guard let zoom else { return false }
            return abs(zoom - 1) > 1e-6
        case #selector(formatCells(_:)):
            return gridView.sheet != nil && formatSheetWindow == nil
        case #selector(setColumnWidth(_:)), #selector(setRowHeight(_:)),
             #selector(setDefaultColumnWidth(_:)), #selector(setDefaultRowHeight(_:)), #selector(renameSheet(_:)):
            return gridView.sheet != nil && window?.attachedSheet == nil
        case #selector(removeSheet(_:)):
            return gridView.sheet != nil && workbook.canRemoveSheets
        case #selector(pasteSpecial(_:)):
            return gridView.sheet != nil && window?.attachedSheet == nil && NSPasteboard.general.string(forType: .string) != nil
        case #selector(moveSheetLeft(_:)):
            return (gridView.sheet?.index ?? 0) > 0
        case #selector(moveSheetRight(_:)):
            guard let sheet = gridView.sheet else { return false }
            return sheet.index < workbook.sheets.count - 1
        default:
            return true
        }
    }

    // MARK: Paste Special (Edit menu)

    /// The GTK Paste Special dialog as a sheet: what to paste, an
    /// arithmetic operation, a region transform, and the four switches,
    /// plus Paste Link.
    @objc func pasteSpecial(_ sender: Any?) {
        guard let window, gridView.sheet != nil else { return }
        let alert = NSAlert()
        alert.messageText = "Paste Special"
        alert.addButton(withTitle: "Paste")
        alert.addButton(withTitle: "Paste Link")
        alert.addButton(withTitle: "Cancel")
        let what = NSPopUpButton(frame: .zero, pullsDown: false)
        let whatChoices: [(String, PasteOptions)] = [
            ("All", .allCells), ("Contents", .contents), ("As Values", .asValues), ("Formats", .formats), ("Comments", .comments)]
        whatChoices.forEach { what.addItem(withTitle: $0.0) }
        let operation = NSPopUpButton(frame: .zero, pullsDown: false)
        let operationChoices: [(String, PasteOptions)] = [
            ("None", []), ("Add", .add), ("Subtract", .subtract), ("Multiply", .multiply), ("Divide", .divide)]
        operationChoices.forEach { operation.addItem(withTitle: $0.0) }
        let region = NSPopUpButton(frame: .zero, pullsDown: false)
        let regionChoices: [(String, PasteOptions)] = [
            ("None", []), ("Transpose", .transpose), ("Flip Horizontally", .flipHorizontally), ("Flip Vertically", .flipVertically)]
        regionChoices.forEach { region.addItem(withTitle: $0.0) }
        let skipBlanks = NSButton(checkboxWithTitle: "Skip blanks", target: nil, action: nil)
        let keepReferences = NSButton(checkboxWithTitle: "Don't change formulae", target: nil, action: nil)
        let widths = NSButton(checkboxWithTitle: "Column widths", target: nil, action: nil)
        let heights = NSButton(checkboxWithTitle: "Row heights", target: nil, action: nil)
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Paste:"), what],
            [NSTextField(labelWithString: "Operation:"), operation],
            [NSTextField(labelWithString: "Region:"), region],
            [NSView(), skipBlanks],
            [NSView(), keepReferences],
            [NSView(), widths],
            [NSView(), heights],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 6
        grid.frame = NSRect(x: 0, y: 0, width: 300, height: grid.fittingSize.height)
        alert.accessoryView = grid
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                var options = whatChoices[max(what.indexOfSelectedItem, 0)].1
                if options == .allCells || options == .contents || options == .asValues {
                    options.formUnion(operationChoices[max(operation.indexOfSelectedItem, 0)].1)
                }
                options.formUnion(regionChoices[max(region.indexOfSelectedItem, 0)].1)
                if skipBlanks.state == .on { options.insert(.skipBlanks) }
                if keepReferences.state == .on { options.insert(.keepFormulaReferences) }
                if widths.state == .on { options.insert(.columnWidths) }
                if heights.state == .on { options.insert(.rowHeights) }
                self.gridView.paste(options: options)
            case .alertSecondButtonReturn:
                self.gridView.paste(options: .link)
            default:
                break
            }
        }
    }

    // MARK: Sheet management (Edit → Sheet, tab context menu)

    private func runSheetCommand(_ command: (Workbook) throws -> Void) {
        if gridView.isEditing { gridView.cancelEditing() }
        do {
            try command(workbook)
        } catch {
            present(error)
        }
    }

    @objc func insertSheet(_ sender: Any?) {
        runSheetCommand { workbook in
            workbook.select(try workbook.insertSheet(before: gridView.sheet))
        }
    }

    @objc func appendSheet(_ sender: Any?) {
        runSheetCommand { workbook in
            workbook.select(try workbook.insertSheet(before: nil))
        }
    }

    @objc func duplicateSheet(_ sender: Any?) {
        guard let current = gridView.sheet else { return }
        runSheetCommand { workbook in
            workbook.select(try workbook.duplicate(current))
        }
    }

    @objc func removeSheet(_ sender: Any?) {
        guard let current = gridView.sheet else { return }
        runSheetCommand { try $0.remove(current) }
    }

    @objc func moveSheetLeft(_ sender: Any?) {
        guard let current = gridView.sheet else { return }
        runSheetCommand { try $0.move(current, toIndex: current.index - 1) }
    }

    @objc func moveSheetRight(_ sender: Any?) {
        guard let current = gridView.sheet else { return }
        runSheetCommand { try $0.move(current, toIndex: current.index + 1) }
    }

    @objc func renameSheet(_ sender: Any?) {
        guard let window, let current = gridView.sheet else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Sheet"
        alert.informativeText = "A name for the sheet \"\(current.name)\"."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = current.name
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name != current.name else { return }
            self?.runSheetCommand { try $0.rename(current, to: name) }
        }
    }

    @objc private func autoExpressionChosen(_ sender: NSMenuItem) {
        guard let function = sender.representedObject as? String else { return }
        workbook.setAutoExpression(function: function, label: sender.title)
    }

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        guard sender.selectedSegment >= 0, sender.selectedSegment < tabSheets.count else { return }
        workbook.select(tabSheets[sender.selectedSegment])
    }

    // MARK: WorkbookDelegate

    func workbook(_ workbook: Workbook, didFocus sheet: Sheet?) {
        show(sheet: sheet)
    }

    func workbook(_ workbook: Workbook, didAdd sheet: Sheet) {
        rebuildTabs()
    }

    func workbook(_ workbook: Workbook, sheetDidChange sheet: Sheet) {
        rebuildTabs()
    }

    func workbook(_ workbook: Workbook, willRemove sheet: Sheet) {
        if gridView.sheet == sheet {
            gridView.sheet = nil
        }
        DispatchQueue.main.async { [weak self] in self?.rebuildTabs() }
    }

    func workbookWillRemoveAllSheets(_ workbook: Workbook) {
        gridView.sheet = nil
    }

    func workbook(_ workbook: Workbook, editLineDidChange text: String) {
        formulaField.stringValue = text
    }

    func workbook(_ workbook: Workbook, autoExpressionDidChange text: String) {
        autoExpression.setTitle(text)
        autoExpression.isHidden = text.isEmpty
        for item in autoExpression.itemArray {
            item.state = (item.representedObject as? String) == workbook.autoExpressionFunction ? .on : .off
        }
    }

    func workbook(_ workbook: Workbook, selectionDescriptionDidChange text: String) {
        nameBox.stringValue = text
    }

    func workbookModifiedStateDidChange(_ workbook: Workbook) {
        workbookDocument?.modifiedStateDidChange()
    }

    /// Engine commands that need confirmation (hide every row, paste
    /// thousands of copies) ask through a modal alert.
    func workbook(_ workbook: Workbook, askYesNo question: String, defaultAnswer: Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = question
        alert.alertStyle = .warning
        alert.addButton(withTitle: defaultAnswer ? "Yes" : "No")
        alert.addButton(withTitle: defaultAnswer ? "No" : "Yes")
        let first = alert.runModal() == .alertFirstButtonReturn
        return defaultAnswer ? first : !first
    }
}

/// The sheet tabs: a right-click selects the tab under the mouse before
/// its context menu opens, so the menu's commands apply to that sheet.
@MainActor
final class SheetTabControl: NSSegmentedControl {
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        var x: CGFloat = 0
        for segment in 0..<segmentCount {
            let width = self.width(forSegment: segment) > 0 ? self.width(forSegment: segment)
                : bounds.width / CGFloat(max(segmentCount, 1))
            if point.x >= x && point.x < x + width {
                if selectedSegment != segment {
                    selectedSegment = segment
                    sendAction(action, to: target)
                }
                break
            }
            x += width
        }
        return super.menu(for: event)
    }
}
