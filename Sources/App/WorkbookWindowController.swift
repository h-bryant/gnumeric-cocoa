import AppKit
import SwiftUI
import GnmCocoa
import UniformTypeIdentifiers

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
        nameBox.isSelectable = true
        nameBox.isEditable = true   // type a reference or a name and press Return
        nameBox.delegate = self
        nameBox.cell?.usesSingleLineMode = true
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
        gridView.requestObjectEditor = { [weak self] object in self?.editObject(object) }
        gridView.requestCommentEditor = { [weak self] cell in self?.editComment(at: cell) }
        gridView.requestObjectImageSave = { [weak self] object in self?.saveObjectAsImage(object) }
    }

    private func present(_ error: Error) {
        guard let window else { return }
        NSLog("Gnumeric error: %@ %@", error.localizedDescription, (error as NSError).localizedRecoverySuggestion ?? "")
        let alert = NSAlert(error: error)
        if let suggestion = (error as NSError).localizedRecoverySuggestion {
            alert.informativeText = suggestion
        }
        alert.beginSheetModal(for: window)
    }

    // MARK: Formula bar editing

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control === nameBox {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                jump(to: nameBox.stringValue)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                workbook.resendDelegateState()
                window?.makeFirstResponder(gridView)
                return true
            default:
                return false
            }
        }
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
            // Only then: taking the first responder during a command kicked
            // the cell editor out, whose end of editing committed the same
            // text again, which the engine reported as a failure (an alert
            // the Quit then waited on, 2026-10-12).
            window?.makeFirstResponder(gridView)
        }
        if let sheet, let index = tabSheets.firstIndex(of: sheet) {
            tabs.selectedSegment = index
            revealSelectedTab()
        }
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
             #selector(resizeSheet(_:)), #selector(setTabColor(_:)), #selector(sortCells(_:)), #selector(insertChart(_:)),
             #selector(insertImage(_:)), #selector(goTo(_:)), #selector(insertCells(_:)), #selector(deleteCells(_:)):
            return gridView.sheet != nil && window?.attachedSheet == nil
        case #selector(showFindPanel(_:)), #selector(showReplacePanel(_:)), #selector(findNext(_:)), #selector(findPrevious(_:)):
            return gridView.sheet != nil
        case #selector(defineNames(_:)), #selector(insertName(_:)), #selector(fillSeries(_:)), #selector(textToColumns(_:)),
             #selector(goalSeek(_:)):
            return gridView.sheet != nil && window?.attachedSheet == nil
        case #selector(removeSheet(_:)):
            return gridView.sheet != nil && workbook.canRemoveSheets
        case #selector(pasteSpecial(_:)):
            return gridView.sheet != nil && window?.attachedSheet == nil && workbook.canPaste
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

    // MARK: Insert Chart (the chart guru)

    private var chartGuru: ChartGuru?

    @objc func insertChart(_ sender: Any?) {
        guard let window, gridView.sheet != nil, chartGuru == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let guru = ChartGuru()
        chartGuru = guru
        guru.run(in: window) { [weak self] choice in
            guard let self else { return }
            chartGuru = nil
            guard let choice, let sheet = gridView.sheet else { return }
            let frame = gridView.suggestedFrameForNewObject(size: sheet.defaultChartSize)
            do {
                let object = try sheet.insertChart(choice.type, seriesLayout: choice.layout, sharedAbscissa: choice.sharedAbscissa, frame: frame)
                gridView.select(objects: [object])
                gridView.scrollToVisible(frame.insetBy(dx: -8, dy: -8))
            } catch {
                present(error)
            }
        }
    }

    // MARK: Go To and the name box

    /// The engine's jump: a cell, a range, a sheet-qualified reference, or
    /// a name; a new word names the selection instead.
    func jump(to text: String) {
        if gridView.isEditing { gridView.cancelEditing() }
        do {
            try workbook.jump(to: text.trimmingCharacters(in: .whitespaces))
        } catch {
            present(error)
        }
        workbook.resendDelegateState()
        window?.makeFirstResponder(gridView)
    }

    @objc func goTo(_ sender: Any?) {
        guard let window, gridView.sheet != nil else { return }
        let alert = NSAlert()
        alert.messageText = "Go To"
        alert.informativeText = "A cell such as C10, a range such as B2:D4, a sheet-qualified reference such as Sheet2!A1, or a defined name."
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Reference or name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { jump(to: text) }
        }
    }

    // MARK: Insert Cells… and Delete Cells… (shifting)

    /// The GTK dialogs' four choices as radio buttons.
    private func promptCellShift(insert: Bool) {
        guard let window, let sheet = gridView.sheet else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let range = sheet.selectedRange
        let alert = NSAlert()
        alert.messageText = insert ? "Insert Cells" : "Delete Cells"
        alert.informativeText = insert ? "Insert empty cells the size of the selection, or whole rows or columns."
                                       : "Delete the selected cells, or their whole rows or columns."
        alert.addButton(withTitle: insert ? "Insert" : "Delete")
        alert.addButton(withTitle: "Cancel")
        let titles = insert ? ["Shift cells right", "Shift cells down", "Entire rows", "Entire columns"]
                            : ["Shift cells left", "Shift cells up", "Entire rows", "Entire columns"]
        let radios = titles.map { NSButton(radioButtonWithTitle: $0, target: nil, action: nil) }
        let group = RadioGroup(radios)
        radios[0].state = .on
        let stack = NSStackView(views: radios)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.frame = NSRect(x: 0, y: 0, width: 240, height: 100)
        alert.accessoryView = stack
        alert.beginSheetModal(for: window) { [weak self] response in
            withExtendedLifetime(group) {}
            guard let self, response == .alertFirstButtonReturn else { return }
            let choice = radios.firstIndex { $0.state == .on } ?? 0
            runSizeCommand { sheet in
                switch (insert, choice) {
                case (true, 0): try sheet.insertCells(in: range, shiftingDown: false)
                case (true, 1): try sheet.insertCells(in: range, shiftingDown: true)
                case (true, 2): try sheet.insertRows(range.end.row - range.start.row + 1, at: range.start.row)
                case (true, _): try sheet.insertColumns(range.end.column - range.start.column + 1, at: range.start.column)
                case (false, 0): try sheet.deleteCells(in: range, shiftingUp: false)
                case (false, 1): try sheet.deleteCells(in: range, shiftingUp: true)
                case (false, 2): try sheet.deleteRows(NSRange(location: range.start.row, length: range.end.row - range.start.row + 1))
                case (false, _): try sheet.deleteColumns(NSRange(location: range.start.column, length: range.end.column - range.start.column + 1))
                }
            }
        }
    }

    /// Keeps a set of radio buttons exclusive (they share this target).
    private final class RadioGroup: NSObject {
        private let buttons: [NSButton]
        init(_ buttons: [NSButton]) {
            self.buttons = buttons
            super.init()
            for button in buttons {
                button.target = self
                button.action = #selector(chosen(_:))
            }
        }
        @objc func chosen(_ sender: NSButton) {
            for button in buttons where button !== sender { button.state = .off }
        }
    }

    @objc func insertCells(_ sender: Any?) { promptCellShift(insert: true) }
    @objc func deleteCells(_ sender: Any?) { promptCellShift(insert: false) }

    // MARK: Fill Series (Edit → Fill → Series…)

    /// The GTK Fill Series dialog as an alert sheet: the series in rows or
    /// columns, linear, growth, or date with its unit, and the start, step,
    /// and stop values (start from the selection's first cell, stop from
    /// its last, as the GTK dialog fills them).
    @objc func fillSeries(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let range = sheet.selectedRange
        let preferRows = range.end.column - range.start.column >= range.end.row - range.start.row
        let alert = NSAlert()
        alert.messageText = "Fill Series"
        alert.informativeText = "Fill the selection with a series from the start value. Leave the step empty to spread the series to the stop value over the selection."
        alert.addButton(withTitle: "Fill")
        alert.addButton(withTitle: "Cancel")
        let direction = NSPopUpButton(frame: .zero, pullsDown: false)
        direction.addItems(withTitles: ["In columns (down)", "In rows (across)"])
        direction.selectItem(at: preferRows ? 1 : 0)
        let kind = NSPopUpButton(frame: .zero, pullsDown: false)
        kind.addItems(withTitles: ["Linear", "Growth", "Date"])
        let unit = NSPopUpButton(frame: .zero, pullsDown: false)
        unit.addItems(withTitles: ["Day", "Weekday", "Month", "Year"])
        let start = NSTextField(string: sheet.displayTextOfCell(atColumn: range.start.column, row: range.start.row) ?? "")
        let lastColumn = preferRows ? range.end.column : range.start.column
        let lastRow = preferRows ? range.start.row : range.end.row
        let stop = NSTextField(string: (lastColumn != range.start.column || lastRow != range.start.row)
                               ? (sheet.displayTextOfCell(atColumn: lastColumn, row: lastRow) ?? "") : "")
        let step = NSTextField(string: "1")
        for field in [start, step, stop] { field.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true }
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.alignment = .right
            return field
        }
        let grid = NSGridView(views: [
            [label("Series in:"), direction], [label("Type:"), kind], [label("Date unit:"), unit],
            [label("Start value:"), start], [label("Step value:"), step], [label("Stop value:"), stop],
        ])
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        for index in 0..<grid.numberOfRows { grid.row(at: index).yPlacement = .center }
        grid.frame = NSRect(x: 0, y: 0, width: 300, height: 190)
        alert.accessoryView = grid
        alert.window.initialFirstResponder = start
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            guard let startValue = sheet.number(from: start.stringValue) else {
                presentMessage("The start value “\(start.stringValue)” is not a number or a date.")
                return
            }
            let stepValue = step.stringValue.isEmpty ? nil : sheet.number(from: step.stringValue)
            let stopValue = stop.stringValue.isEmpty ? nil : sheet.number(from: stop.stringValue)
            if !step.stringValue.isEmpty && stepValue == nil {
                presentMessage("The step value “\(step.stringValue)” is not a number.")
                return
            }
            if !stop.stringValue.isEmpty && stopValue == nil {
                presentMessage("The stop value “\(stop.stringValue)” is not a number or a date.")
                return
            }
            runSizeCommand { sheet in
                try sheet.fillSeries(in: range, byRows: direction.indexOfSelectedItem == 1,
                                     kind: Sheet.FillSeriesKind(rawValue: kind.indexOfSelectedItem) ?? .linear,
                                     dateUnit: Sheet.FillSeriesDateUnit(rawValue: unit.indexOfSelectedItem) ?? .day,
                                     start: startValue.doubleValue, step: stepValue, stop: stopValue)
            }
        }
    }

    private func presentMessage(_ text: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = text
        alert.beginSheetModal(for: window)
    }

    // MARK: Goal Seek (Tools menu)

    /// The GTK Goal Seek dialog as an alert sheet: the cell to set (the
    /// selection's cell at first), the value to reach, the cell to change,
    /// and the optional bounds; the result in a second alert.
    @objc func goalSeek(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let edit = sheet.editPosition
        let alert = NSAlert()
        alert.messageText = "Goal Seek"
        alert.informativeText = "Change one cell until the formula in another reaches a value."
        alert.addButton(withTitle: "Seek")
        alert.addButton(withTitle: "Cancel")
        let setCell = NSTextField(string: sheet.name(ofColumn: edit.column) + sheet.name(ofRow: edit.row))
        let toValue = NSTextField(string: "0")
        let changeCell = NSTextField(string: "")
        let atLeast = NSTextField(string: "")
        let atMost = NSTextField(string: "")
        for field in [setCell, toValue, changeCell, atLeast, atMost] { field.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true }
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.alignment = .right
            return field
        }
        let grid = NSGridView(views: [
            [label("Set cell:"), setCell], [label("To value:"), toValue], [label("By changing cell:"), changeCell],
            [label("At least:"), atLeast], [label("At most:"), atMost],
        ])
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        for index in 0..<grid.numberOfRows { grid.row(at: index).yPlacement = .center }
        grid.frame = NSRect(x: 0, y: 0, width: 300, height: 160)
        alert.accessoryView = grid
        alert.window.initialFirstResponder = changeCell
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            var setColumn = 0, setRow = 0, changeColumn = 0, changeRow = 0
            guard sheet.parseCellReference(setCell.stringValue, column: &setColumn, row: &setRow) else {
                presentMessage("You should introduce a valid cell name in 'Set Cell:'!")
                return
            }
            guard sheet.parseCellReference(changeCell.stringValue, column: &changeColumn, row: &changeRow) else {
                presentMessage("You should introduce a valid cell name in 'By Changing Cell:'!")
                return
            }
            guard let target = sheet.number(from: toValue.stringValue) else {
                presentMessage("The value given in 'To Value:' is not valid.")
                return
            }
            let minimum = atLeast.stringValue.isEmpty ? nil : sheet.number(from: atLeast.stringValue)
            let maximum = atMost.stringValue.isEmpty ? nil : sheet.number(from: atMost.stringValue)
            do {
                let result = try sheet.goalSeek(cellAtColumn: setColumn, row: setRow, toValue: target.doubleValue,
                                                byChangingCellAtColumn: changeColumn, row: changeRow, minimum: minimum, maximum: maximum)
                workbook.resendDelegateState()
                gridView.needsDisplay = true
                let setName = sheet.name(ofColumn: setColumn) + sheet.name(ofRow: setRow)
                let changeName = sheet.name(ofColumn: changeColumn) + sheet.name(ofRow: changeRow)
                let report = NSAlert()
                if result.found {
                    report.messageText = "Goal seeking with cell \(setName) found a solution."
                    report.informativeText = "\(changeName) = \(result.solution.formatted(.number.precision(.significantDigits(1...10))))\n"
                        + "\(setName) = \(result.currentValue.formatted(.number.precision(.significantDigits(1...10)))), "
                        + "\(abs(result.targetValue - result.currentValue).formatted(.number.precision(.significantDigits(1...3)))) from the target."
                } else {
                    report.messageText = "Goal seeking with cell \(setName) did not find a solution."
                    report.informativeText = "\(changeName) keeps its value. Bounds under At least and At most can help."
                }
                report.beginSheetModal(for: window)
            } catch {
                present(error)
            }
        }
    }

    // MARK: Text to Columns (Data menu)

    /// Data → Text to Columns…: the selection's column through the import
    /// assistant, parsed into the columns to its right.
    @objc func textToColumns(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        do {
            let session = try sheet.textToColumnsSession()
            let assistant = TextImportAssistant(session: session, title: "Text to Columns")
            guard assistant.run() else { return }
            try sheet.textToColumns(assistant.model.session)
            workbook.resendDelegateState()
            gridView.needsDisplay = true
        } catch {
            present(error)
        }
    }

    // MARK: Names (Edit → Define Names…, Insert → Name…)

    var namesDialog: NamesDialog?

    @objc func defineNames(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, namesDialog == nil, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let dialog = NamesDialog(workbook: workbook, sheet: sheet)
        namesDialog = dialog
        dialog.run(in: window) { [weak self] in
            guard let self else { return }
            namesDialog = nil
            workbook.resendDelegateState()
            gridView.needsDisplay = true
            window.makeFirstResponder(gridView)
        }
    }

    /// The GTK Paste Names dialog as an alert: a pop-up of the names the
    /// cell can use, inserted into the cell editor.
    @objc func insertName(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, window.attachedSheet == nil else { return }
        let names = workbook.definedNames(for: sheet).filter(\.isEditable)
        let alert = NSAlert()
        alert.messageText = "Insert Name"
        guard !names.isEmpty else {
            alert.informativeText = "No names are defined. Edit → Define Names… defines one."
            alert.beginSheetModal(for: window)
            return
        }
        alert.informativeText = "The name goes into the cell as a formula, or into the formula being edited."
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")
        let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
        for name in names {
            popUp.addItem(withTitle: name.scope == nil ? name.name : "\(name.name)  (\(name.scope!.name))")
        }
        alert.accessoryView = popUp
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn, popUp.indexOfSelectedItem < names.count else { return }
            gridView.insertName(names[popUp.indexOfSelectedItem].name)
        }
    }

    // MARK: Comments (Insert → Comment…, the cell's context menu)

    /// The GTK cell comment dialog as a sheet: the author (the user's name
    /// for a new one) and the text; OK sets it, Remove clears it.
    func editComment(at cell: CellCoordinate) {
        guard let window, let sheet = gridView.sheet, window.attachedSheet == nil else { return }
        let existing = sheet.comment(atColumn: cell.column, row: cell.row)
        let alert = NSAlert()
        alert.messageText = (existing == nil ? "Comment for " : "Edit the comment for ") + sheet.name(ofColumn: cell.column) + sheet.name(ofRow: cell.row)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if existing != nil {
            alert.addButton(withTitle: "Remove")
        }
        let author = NSTextField(string: existing?.author ?? NSFullUserName())
        author.placeholderString = "Author"
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 110))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let text = NSTextView(frame: scroll.bounds)
        text.isRichText = false
        text.font = .systemFont(ofSize: NSFont.systemFontSize)
        text.string = existing?.text ?? ""
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.isVerticallyResizable = true
        scroll.documentView = text
        scroll.heightAnchor.constraint(equalToConstant: 110).isActive = true
        let stack = NSStackView(views: [author, scroll])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 320, height: 150)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = text
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            let newText: String
            switch response {
            case .alertFirstButtonReturn: newText = text.string
            case .alertThirdButtonReturn: newText = ""
            default: return
            }
            do {
                try sheet.setComment(newText, author: author.stringValue, atColumn: cell.column, row: cell.row)
            } catch {
                present(error)
            }
            window.makeFirstResponder(gridView)
        }
    }

    // MARK: Export as Text (the options before a text save)

    private(set) var textExportSheet: TextExportSheet?

    /// The "Export as Text" sheet; the completion gets the options (nil
    /// when cancelled) and whether to remember them as the defaults.
    func promptTextExport(options: TextExportOptions, completion: @escaping (TextExportOptions?, Bool) -> Void) {
        guard let window, textExportSheet == nil, window.attachedSheet == nil else {
            completion(nil, false)
            return
        }
        if gridView.isEditing { gridView.cancelEditing() }
        let sheet = TextExportSheet(options: options, workbook: workbook)
        textExportSheet = sheet
        sheet.run(in: window) { [weak self] options, remember in
            self?.textExportSheet = nil
            completion(options, remember)
        }
    }

    // MARK: Find and Replace (Edit menu)

    private(set) var findPanel: FindPanel?

    private func ensureFindPanel() -> FindPanel {
        if let findPanel { return findPanel }
        let panel = FindPanel(controller: self)
        findPanel = panel
        return panel
    }

    @objc func showFindPanel(_ sender: Any?) {
        guard gridView.sheet != nil else { return }
        ensureFindPanel().show(focusReplace: false)
    }

    @objc func showReplacePanel(_ sender: Any?) {
        guard gridView.sheet != nil else { return }
        ensureFindPanel().show(focusReplace: true)
    }

    /// Find Next and Find Previous from the document window: the panel's
    /// steps when it has matches (or a text to find), else the panel.
    @objc func findNext(_ sender: Any?) {
        guard gridView.sheet != nil else { return }
        if let findPanel, !findPanel.options.searchText.isEmpty { findPanel.findNext(sender) } else { showFindPanel(sender) }
    }

    @objc func findPrevious(_ sender: Any?) {
        guard gridView.sheet != nil else { return }
        if let findPanel, !findPanel.options.searchText.isEmpty { findPanel.findPrevious(sender) } else { showFindPanel(sender) }
    }

    // MARK: Chart Properties (the chart editor)

    private(set) var chartEditor: ChartEditorWindow?

    /// Open the editor of an object that has one: charts, through the
    /// guru's later pages on a working copy.
    func editObject(_ object: SheetObject) {
        guard let window, chartEditor == nil, window.attachedSheet == nil else { return }
        guard let editor = ChartEditor(editing: object) else { return }   // images have no editor yet
        if gridView.isEditing { gridView.cancelEditing() }
        let sheet = ChartEditorWindow(editor: editor)
        chartEditor = sheet
        sheet.run(in: window) { [weak self] applied in
            guard let self else { return }
            chartEditor = nil
            if applied {
                gridView.needsDisplay = true
            }
        }
    }

    // MARK: Save as Image (the object context menu)

    /// A save panel with the object's formats in a pop-up and, for a
    /// chart's raster formats, the resolution (the GTK dialog's 150 dpi).
    func saveObjectAsImage(_ object: SheetObject) {
        guard let window, let sheet = gridView.sheet, window.attachedSheet == nil else { return }
        let formats = sheet.imageFormats(for: object)
        guard !formats.isEmpty else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let panel = NSSavePanel()
        panel.message = "Save the \(object.typeName == "SheetObjectGraph" ? "chart" : "image") as a file."
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = (object.name.isEmpty ? "Object" : object.name) + "." + formats[0].fileExtension
        let formatPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        for format in formats {
            formatPopUp.addItem(withTitle: format.summary)
        }
        let resolution = NSTextField(string: "150")
        resolution.translatesAutoresizingMaskIntoConstraints = false
        resolution.widthAnchor.constraint(equalToConstant: 56).isActive = true
        let dpiLabel = NSTextField(labelWithString: "Resolution (dpi):")
        func applyFormat() {
            let format = formats[max(0, formatPopUp.indexOfSelectedItem)]
            if let type = UTType(filenameExtension: format.fileExtension) {
                panel.allowedContentTypes = [type]
            }
            let name = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = name + "." + format.fileExtension
            resolution.isEnabled = format.usesResolution
            dpiLabel.textColor = format.usesResolution ? .labelColor : .disabledControlTextColor
        }
        let handler = FormatChangeHandler(applyFormat)
        formatPopUp.target = handler
        formatPopUp.action = #selector(FormatChangeHandler.changed(_:))
        let row = NSStackView(views: [NSTextField(labelWithString: "Format:"), formatPopUp, dpiLabel, resolution])
        row.orientation = .horizontal
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        let accessory = NSView()
        accessory.addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: accessory.centerXAnchor),
            row.topAnchor.constraint(equalTo: accessory.topAnchor),
            row.bottomAnchor.constraint(equalTo: accessory.bottomAnchor),
            accessory.widthAnchor.constraint(greaterThanOrEqualTo: row.widthAnchor),
        ])
        panel.accessoryView = accessory
        applyFormat()
        panel.beginSheetModal(for: window) { [weak self] response in
            withExtendedLifetime(handler) {}
            guard let self, response == .OK, let url = panel.url else { return }
            let format = formats[max(0, formatPopUp.indexOfSelectedItem)]
            let dpi = Double(resolution.stringValue) ?? 150
            do {
                try sheet.writeImage(of: object, format: format, resolution: format.usesResolution ? max(dpi, 1) : -1, to: url)
            } catch {
                present(error)
            }
        }
    }

    /// A target for the save panel's format pop-up (closures cannot be
    /// targets).
    private final class FormatChangeHandler: NSObject {
        private let handler: () -> Void
        init(_ handler: @escaping () -> Void) { self.handler = handler }
        @objc func changed(_ sender: Any?) { handler() }
    }

    // MARK: Insert Image

    @objc func insertImage(_ sender: Any?) {
        guard let window, gridView.sheet != nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an image to place on the sheet."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            insertImage(at: url)
        }
    }

    func insertImage(at url: URL) {
        guard let sheet = gridView.sheet else { return }
        do {
            let data = try Data(contentsOf: url)
            let size = sheet.naturalSize(ofImageData: data)
            guard size != .zero else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError,
                              userInfo: [NSLocalizedDescriptionKey: "“\(url.lastPathComponent)” is not an image the engine can read."])
            }
            let frame = gridView.suggestedFrameForNewObject(size: size)
            let object = try sheet.insertImage(data, frame: frame)
            gridView.select(objects: [object])
            gridView.scrollToVisible(frame.insetBy(dx: -8, dy: -8))
        } catch {
            present(error)
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
