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
        gridView.requestFilterDialog = { [weak self] button, choices, custom in
            self?.promptFilterCondition(for: button, choices: choices, custom: custom)
        }
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
            // The tab color as a swatch before the name: a segmented control
            // has no per-segment background (the text color is not shown).
            if let color = sheet.tabColor().flatMap(NSColor.init(cgColor:)) {
                tabs.setImage(Self.swatch(color), forSegment: i)
                tabs.setImageScaling(.scaleNone, forSegment: i)
            } else {
                tabs.setImage(nil, forSegment: i)
            }
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

    private static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2).fill()
            return true
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
        // The engine focuses the command's sheet after every command
        // (commands.c update_after_action); only a real change resets the grid.
        if gridView.sheet !== sheet {
            gridView.sheet = sheet
        }
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
             #selector(setDefaultColumnWidth(_:)), #selector(setDefaultRowHeight(_:)), #selector(renameSheet(_:)),
             #selector(resizeSheet(_:)), #selector(setTabColor(_:)), #selector(sortCells(_:)):
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

    /// The GTK Resize Sheet dialog: sizes are powers of two between the
    /// engine's limits; the change can apply to every sheet.
    @objc func resizeSheet(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet else { return }
        let alert = NSAlert()
        alert.messageText = "Resize Sheet"
        alert.informativeText = "Sizes are powers of two. A sheet cannot shrink below its data."
        alert.addButton(withTitle: "Resize")
        alert.addButton(withTitle: "Cancel")
        func sizes(from minimum: Int, to maximum: Int, current: Int) -> NSPopUpButton {
            let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
            var n = minimum
            while n <= maximum {
                popUp.addItem(withTitle: n >= 1 << 20 ? "\(n >> 20)M" : "\(n)")
                popUp.lastItem?.tag = n
                n *= 2
            }
            _ = popUp.selectItem(withTag: current)
            return popUp
        }
        let columns = sizes(from: Workbook.minimumSheetColumns, to: Workbook.maximumSheetColumns, current: sheet.columnCount)
        let rows = sizes(from: Workbook.minimumSheetRows, to: Workbook.maximumSheetRows, current: sheet.rowCount)
        let all = NSButton(checkboxWithTitle: "Apply to all sheets", target: nil, action: nil)
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Columns:"), columns],
            [NSTextField(labelWithString: "Rows:"), rows],
            [NSView(), all],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 6
        grid.frame = NSRect(x: 0, y: 0, width: 260, height: grid.fittingSize.height)
        alert.accessoryView = grid
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let cols = columns.selectedTag(), rws = rows.selectedTag()
            var targets = [sheet]   // first, so the focus stays here on undo
            if all.state == .on {
                targets += workbook.sheets.filter { $0 != sheet && ($0.columnCount != cols || $0.rowCount != rws) }
            }
            if targets.count == 1 && sheet.columnCount == cols && sheet.rowCount == rws { return }
            runSheetCommand { try $0.resize(targets, toColumns: cols, rows: rws) }
        }
    }

    /// Tab colors (the GTK Manage Sheets dialog's color pickers).
    @objc func setTabColor(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet else { return }
        let alert = NSAlert()
        alert.messageText = "Tab Color"
        alert.informativeText = "Colors of the tab for the sheet \"\(sheet.name)\"."
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        func well(_ color: CGColor?, none: NSButton) -> NSColorWell {
            let well = NSColorWell(frame: NSRect(x: 0, y: 0, width: 60, height: 24))
            well.widthAnchor.constraint(equalToConstant: 60).isActive = true
            well.heightAnchor.constraint(equalToConstant: 24).isActive = true
            if let color, let nsColor = NSColor(cgColor: color) {
                well.color = nsColor
            } else {
                none.state = .on
            }
            return well
        }
        let noBackground = NSButton(checkboxWithTitle: "None", target: nil, action: nil)
        let noText = NSButton(checkboxWithTitle: "None", target: nil, action: nil)
        let background = well(sheet.tabColor(), none: noBackground)
        let text = well(sheet.tabTextColor(), none: noText)
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Background:"), background, noBackground],
            [NSTextField(labelWithString: "Text:"), text, noText],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 6
        grid.frame = NSRect(x: 0, y: 0, width: 260, height: grid.fittingSize.height)
        alert.accessoryView = grid
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            NSColorPanel.shared.orderOut(nil)
            let bg = noBackground.state == .on ? nil : background.color.cgColor
            let fg = noText.state == .on ? nil : text.color.cgColor
            runSheetCommand { try $0.setTabColor(bg, textColor: fg, of: sheet) }
        }
    }

    // MARK: Sort dialog (Data → Sort…)

    private var sortDialog: SortDialog?

    @objc func sortCells(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, sortDialog == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let dialog = SortDialog(sheet: sheet, range: sheet.sortableRange)
        sortDialog = dialog
        dialog.run(in: window) { [weak self] request in
            guard let self else { return }
            sortDialog = nil
            guard let request else { return }
            runSizeCommand { sheet in
                try sheet.sort(request.range, byRows: request.byRows, hasHeader: request.hasHeader, keys: request.keys,
                               retainFormats: request.retainFormats)
            }
        }
    }

    // MARK: Autofilter dialogs ("(Custom…)" and "(Top 10…)")

    private static let filterOperators: [(label: String, op: FilterOperator)] = [
        ("(none)", .none), ("equals", .equals), ("does not equal", .doesNotEqual),
        ("is greater than", .greaterThan), ("is greater than or equal to", .greaterThanOrEqual),
        ("is less than", .lessThan), ("is less than or equal to", .lessThanOrEqual),
        ("begins with", .beginsWith), ("does not begin with", .doesNotBeginWith),
        ("ends with", .endsWith), ("does not end with", .doesNotEndWith),
        ("contains", .contains), ("does not contain", .doesNotContain),
    ]

    func promptFilterCondition(for button: FilterButton, choices: FilterChoices, custom: Bool) {
        guard let window else { return }
        let current = choices.current
        let alert = NSAlert()
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let condition: () -> FilterCondition
        if custom {
            alert.messageText = "Custom Filter"
            alert.informativeText = "Show the rows where the column:"
            func operators(_ selected: FilterOperator) -> NSPopUpButton {
                let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
                Self.filterOperators.forEach { popUp.addItem(withTitle: $0.label) }
                popUp.selectItem(at: Self.filterOperators.firstIndex { $0.op == selected } ?? 0)
                return popUp
            }
            let isCustom = current.kind == .custom
            let op0 = operators(isCustom ? current.firstOperator : .equals)
            let op1 = operators(isCustom ? current.secondOperator : .none)
            let text0 = NSTextField(string: isCustom ? current.firstText : "")
            let text1 = NSTextField(string: isCustom ? current.secondText : "")
            let join = NSSegmentedControl(labels: ["And", "Or"], trackingMode: .selectOne, target: nil, action: nil)
            join.selectedSegment = isCustom && !current.joinedWithAnd ? 1 : 0
            for field in [text0, text1] {
                field.widthAnchor.constraint(equalToConstant: 160).isActive = true
            }
            let grid = NSGridView(views: [[op0, text0], [join, NSView()], [op1, text1]])
            grid.rowSpacing = 6
            grid.frame = NSRect(x: 0, y: 0, width: 400, height: grid.fittingSize.height)
            alert.accessoryView = grid
            alert.window.initialFirstResponder = text0
            condition = {
                let first = Self.filterOperators[op0.indexOfSelectedItem].op
                let second = Self.filterOperators[op1.indexOfSelectedItem].op
                if first == .none { return .showAll() }
                if second == .none { return .custom(first, text0.stringValue) }
                return .custom(first, text0.stringValue, joinedWithAnd: join.selectedSegment == 0, second, text1.stringValue)
            }
        } else {
            alert.messageText = "Top 10 AutoFilter"
            alert.informativeText = "Show the rows with the largest or smallest values of the column."
            let isBucket = current.kind == .bucket
            let direction = NSPopUpButton(frame: .zero, pullsDown: false)
            direction.addItem(withTitle: "Top")
            direction.addItem(withTitle: "Bottom")
            direction.selectItem(at: isBucket && !current.isTop ? 1 : 0)
            let count = NSTextField(frame: NSRect(x: 0, y: 0, width: 60, height: 24))
            let formatter = NumberFormatter()
            formatter.minimum = 1
            formatter.maximumFractionDigits = 0
            count.formatter = formatter
            count.doubleValue = isBucket ? current.count : 10
            count.widthAnchor.constraint(equalToConstant: 60).isActive = true
            let unit = NSPopUpButton(frame: .zero, pullsDown: false)
            unit.addItem(withTitle: "Items")
            unit.addItem(withTitle: "Percent")
            unit.selectItem(at: isBucket && current.isPercent ? 1 : 0)
            let grid = NSGridView(views: [[direction, count, unit]])
            grid.columnSpacing = 8
            grid.frame = NSRect(x: 0, y: 0, width: 300, height: grid.fittingSize.height)
            alert.accessoryView = grid
            alert.window.initialFirstResponder = count
            condition = {
                .bucket(top: direction.indexOfSelectedItem == 0, count: max(count.doubleValue, 1), percent: unit.indexOfSelectedItem == 1)
            }
        }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            gridView.applyFilterCondition(condition(), to: button)
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
