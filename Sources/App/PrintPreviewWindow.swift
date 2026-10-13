import AppKit
import GnmCocoa

/// File → Print Preview (the GTK hands the sheet to GTK's own preview
/// through gnm_print_sheet): the paginated pages drawn by the engine's
/// page drawing, stacked in a scrolling window, with paging, a zoom,
/// Page Setup…, and Print….
@MainActor
final class PrintPreviewController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private weak var controller: WorkbookWindowController?
    private let pageView = PrintPreviewView()
    private let scroll = NSScrollView()
    private let pageLabel = NSTextField(labelWithString: "")
    private let zoomPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let previousButton = NSButton(title: Localization.title("Previous"), target: nil, action: nil)
    private let nextButton = NSButton(title: Localization.title("Next"), target: nil, action: nil)
    /// The zoom choices: nil fits the page width.
    static let zoomChoices: [(String, CGFloat?)] = [("Fit Width", nil), ("50%", 0.5), ("75%", 0.75), ("100%", 1), ("150%", 1.5), ("200%", 2)]
    private(set) var job: PrintJob?
    private(set) var currentPage = 0

    init(controller: WorkbookWindowController) {
        self.controller = controller
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 820),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Print Preview"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 360)
        window.setFrameAutosaveName("PrintPreview")
        window.delegate = self
        build()
        if let parent = controller.window {
            NotificationCenter.default.addObserver(self, selector: #selector(documentWindowWillClose(_:)),
                                                   name: NSWindow.willCloseNotification, object: parent)
        }
    }

    @objc private func documentWindowWillClose(_ notification: Notification) { window.close() }

    private func build() {
        previousButton.target = self
        previousButton.action = #selector(previousPage(_:))
        nextButton.target = self
        nextButton.action = #selector(nextPage(_:))
        zoomPopUp.addItems(withTitles: Self.zoomChoices.map(\.0))
        zoomPopUp.target = self
        zoomPopUp.action = #selector(zoomChosen(_:))
        let setupButton = NSButton(title: Localization.title("Page Setup…"), target: self, action: #selector(pageSetup(_:)))
        let printButton = NSButton(title: Localization.title("Print…"), target: self, action: #selector(print(_:)))
        printButton.keyEquivalent = "\r"
        let bar = NSStackView(views: [previousButton, nextButton, pageLabel, NSView(), zoomPopUp, setupButton, printButton])
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 6, right: 12)
        scroll.documentView = pageView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .noBorder
        scroll.backgroundColor = .windowBackgroundColor
        scroll.drawsBackground = true
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        let stack = NSStackView(views: [bar, scroll])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        window.contentView = content
    }

    // MARK: Showing

    /// Paginate the sheet again and show the window.
    func show() {
        reload()
        if !window.isVisible, !window.setFrameUsingName("PrintPreview") { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    /// The pages from the sheet's current print area and page setup.
    func reload() {
        guard let controller, let sheet = controller.gridView.sheet else { return }
        job = sheet.printJob(selectionOnly: false, ignoringPrintArea: false)
        window.title = "Print Preview – \(sheet.name)"
        pageView.job = job
        applyZoom()
        currentPage = min(currentPage, max((job?.pageCount ?? 1) - 1, 0))
        updateBar()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // The sheet may have changed meanwhile.
        reload()
    }

    // MARK: Paging and zoom

    private func updateBar() {
        let count = job?.pageCount ?? 0
        pageLabel.stringValue = count == 0 ? "Nothing to print" : "Page \(currentPage + 1) of \(count)"
        previousButton.isEnabled = currentPage > 0
        nextButton.isEnabled = currentPage + 1 < count
    }

    @objc private func previousPage(_ sender: Any?) { go(to: currentPage - 1) }
    @objc private func nextPage(_ sender: Any?) { go(to: currentPage + 1) }

    func go(to page: Int) {
        guard let job, page >= 0, page < job.pageCount else { return }
        currentPage = page
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.origin.x, y: pageView.top(ofPage: page)))
        scroll.reflectScrolledClipView(scroll.contentView)
        updateBar()
    }

    @objc private func scrolled(_ notification: Notification) {
        guard let job, job.pageCount > 0 else { return }
        let page = pageView.page(atY: scroll.contentView.bounds.midY)
        if page != currentPage {
            currentPage = page
            updateBar()
        }
    }

    @objc private func zoomChosen(_ sender: Any?) { applyZoom() }

    /// Set the zoom by its index in `zoomChoices` (the headless checks).
    func selectZoom(at index: Int) {
        zoomPopUp.selectItem(at: index)
        applyZoom()
    }

    var scale: CGFloat { pageView.scale }

    private func applyZoom() {
        let index = max(zoomPopUp.indexOfSelectedItem, 0)
        if let fixed = Self.zoomChoices[index].1 {
            pageView.scale = fixed
        } else if let job {
            let available = max(scroll.contentView.bounds.width - 2 * PrintPreviewView.gap, 100)
            pageView.scale = available / max(job.pageSize.width, 1)
        }
        pageView.layoutPages()
    }

    func windowDidResize(_ notification: Notification) {
        if Self.zoomChoices[max(zoomPopUp.indexOfSelectedItem, 0)].1 == nil { applyZoom() }
    }

    // MARK: Page Setup and Print

    @objc private func pageSetup(_ sender: Any?) {
        controller?.pageSetup(nil)
    }

    @objc private func print(_ sender: Any?) {
        controller?.printSheet(nil)
    }
}

/// The pages stacked top to bottom at a scale, each on white with a
/// shadow, drawn by the job (flipped, like `PrintView`).
@MainActor
final class PrintPreviewView: NSView {
    static let gap: CGFloat = 20
    var job: PrintJob? { didSet { layoutPages() } }
    var scale: CGFloat = 1

    override var isFlipped: Bool { true }

    private var pageSize: NSSize {
        guard let job else { return NSSize(width: 612, height: 792) }
        return NSSize(width: job.pageSize.width * scale, height: job.pageSize.height * scale)
    }

    func top(ofPage page: Int) -> CGFloat {
        Self.gap + CGFloat(page) * (pageSize.height + Self.gap)
    }

    func page(atY y: CGFloat) -> Int {
        let count = job?.pageCount ?? 0
        guard count > 0 else { return 0 }
        return min(max(Int((y - Self.gap) / (pageSize.height + Self.gap)), 0), count - 1)
    }

    func layoutPages() {
        let count = max(job?.pageCount ?? 0, 1)
        let size = pageSize
        let width = size.width + 2 * Self.gap
        let height = CGFloat(count) * (size.height + Self.gap) + Self.gap
        let visible = enclosingScrollView?.contentView.bounds.size ?? .zero
        frame = NSRect(x: 0, y: 0, width: max(width, visible.width), height: max(height, visible.height))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        guard let job, job.pageCount > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        let size = pageSize
        let x = max((bounds.width - size.width) / 2, Self.gap)
        for page in 0..<job.pageCount {
            let rect = NSRect(x: x, y: top(ofPage: page), width: size.width, height: size.height)
            guard rect.insetBy(dx: -8, dy: -8).intersects(dirtyRect) else { continue }
            NSColor.black.withAlphaComponent(0.18).setFill()
            rect.offsetBy(dx: 2, dy: 3).fill()
            NSColor.white.setFill()
            rect.fill()
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: scale, y: scale)
            context.clip(to: CGRect(origin: .zero, size: job.pageSize))
            job.drawPage(page, in: context)
            context.restoreGState()
            NSColor.separatorColor.setStroke()
            NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
    }
}
