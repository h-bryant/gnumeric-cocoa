import AppKit
import GnmCocoa

/// The document window: name box and formula line on top, the grid in a
/// scroll view with header rulers, and sheet tabs at the bottom.
@MainActor
final class WorkbookWindowController: NSWindowController, WorkbookDelegate, NSWindowDelegate {
    let workbook: Workbook
    private let gridView = GridView()
    private let scrollView = NSScrollView()
    private let nameBox = NSTextField(labelWithString: "")
    private let formulaField = NSTextField(labelWithString: "")
    private let tabs = NSSegmentedControl()
    private var tabSheets: [Sheet] = []

    init(workbook: Workbook) {
        self.workbook = workbook
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
        let tabBar = NSStackView(views: [tabs])
        tabBar.orientation = .horizontal
        tabBar.alignment = .centerY
        tabBar.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)

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
    }

    private func show(sheet: Sheet?) {
        gridView.sheet = sheet
        if let sheet, let index = tabSheets.firstIndex(of: sheet) {
            tabs.selectedSegment = index
        }
        scrollView.horizontalRulerView?.needsDisplay = true
        scrollView.verticalRulerView?.needsDisplay = true
        window?.makeFirstResponder(gridView)
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
}
