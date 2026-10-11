import AppKit
import SwiftUI
import GnmCocoa

/// The document window: name box and formula line on top, the grid in a
/// scroll view with header rulers, and sheet tabs at the bottom.
@MainActor
final class WorkbookWindowController: NSWindowController, WorkbookDelegate, NSWindowDelegate, NSUserInterfaceValidations, NSTextFieldDelegate {
    let workbook: Workbook
    private weak var workbookDocument: WorkbookDocument?
    let gridView = GridView()
    private let scrollView = NSScrollView()
    private let nameBox = NSTextField(labelWithString: "")
    private let formulaField = NSTextField(labelWithString: "")
    private let tabs = NSSegmentedControl()
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

        scrollView.documentView = gridView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.usesPredominantAxisScrolling = false
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .white
        scrollView.drawsBackground = true
        scrollView.hasHorizontalRuler = true
        scrollView.hasVerticalRuler = true
        scrollView.horizontalRulerView = ColumnHeaderView(scrollView: scrollView, orientation: .horizontalRuler)
        scrollView.verticalRulerView = RowHeaderView(scrollView: scrollView, orientation: .verticalRuler)
        scrollView.rulersVisible = true
        scrollView.horizontalRulerView?.clientView = gridView
        scrollView.verticalRulerView?.clientView = gridView
        gridView.headerViews = [scrollView.horizontalRulerView, scrollView.verticalRulerView].compactMap { $0 as? SheetHeaderView }

        tabs.segmentStyle = .texturedRounded
        tabs.trackingMode = .selectOne
        tabs.target = self
        tabs.action = #selector(tabChanged(_:))
        // Many sheets overflow the window: the tabs sit in a horizontally
        // scrolling strip (trackpad scroll, no visible scroller).
        tabScroller.documentView = tabs
        tabScroller.hasHorizontalScroller = false
        tabScroller.hasVerticalScroller = false
        tabScroller.verticalScrollElasticity = .none
        tabScroller.drawsBackground = false
        tabScroller.borderType = .noBorder
        tabScroller.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let tabBar = NSStackView(views: [tabScroller])
        tabBar.orientation = .horizontal
        tabBar.distribution = .fill
        tabBar.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        tabScroller.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let column = NSStackView(views: [formulaBar, scrollView, tabBar])
        column.orientation = .vertical
        column.distribution = .fill   /* the default, gravity areas, would not stretch the scroll view */
        column.spacing = 0
        column.alignment = .width
        column.translatesAutoresizingMaskIntoConstraints = false
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

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
        scrollView.horizontalRulerView?.needsDisplay = true
        scrollView.verticalRulerView?.needsDisplay = true
        window?.makeFirstResponder(gridView)
        updateSubtitle()
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
        default:
            return true
        }
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
