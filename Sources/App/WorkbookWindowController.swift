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
    private let scrollView = GridScrollView()
    /// The headers stop where the scrollers begin (the column header's
    /// trailing edge, the row header's bottom), by the scrollers' width.
    private var columnHeaderTrailing: NSLayoutConstraint?
    private var rowHeaderBottom: NSLayoutConstraint?
    private let nameBox = NSTextField(labelWithString: "")
    private let formulaField = NSTextField(labelWithString: "")
    private var formulaFieldHeight: NSLayoutConstraint?
    private var formulaBarHeight: NSLayoutConstraint?

    /// The edit line shows up to five lines of a multi-line text (the
    /// GTK entry scrolls them; here the bar grows).
    private func fitFormulaBar(to text: String) {
        let lines = min(max(text.components(separatedBy: "\n").count, 1), 5)
        let height = 24 + CGFloat(lines - 1) * 17
        if formulaFieldHeight?.constant != height {
            formulaFieldHeight?.constant = height
            formulaBarHeight?.constant = height + 8
        }
    }

    /// The formula bar's height, for the checks.
    var formulaBarHeightForTesting: CGFloat { formulaBarHeight?.constant ?? 0 }
    private let tabs = SheetTabControl()
    /// The status bar's auto-expression: a pull-down showing "Sum = 42"
    /// whose items choose the function, as the GTK status bar does.
    private let autoExpression = NSPopUpButton(frame: .zero, pullsDown: true)
    private static let autoExpressionChoices: [(label: String, function: String)] = [
        ("Sum", "sum"), ("Min", "min"), ("Max", "max"), ("Average", "average"), ("Count", "count"),
    ]
    private let tabScroller = NSScrollView()
    private var tabBar: NSStackView?

    /// The workbook view's attributes on the window: scrollers and the
    /// tab bar shown or not (wbcg's show_* handling).
    func applyWorkbookView() {
        scrollView.hasHorizontalScroller = workbook.showsHorizontalScrollbar
        scrollView.hasVerticalScroller = workbook.showsVerticalScrollbar
        tabBar?.isHidden = !workbook.showsSheetTabs
        updateHeaderInsets()
    }

    /// The headers end at the scrollers, which sit inside the scroll
    /// view's frame (the legacy style; the column header would otherwise
    /// run on above the vertical scroller).
    private func updateHeaderInsets() {
        let width = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        columnHeaderTrailing?.constant = scrollView.hasVerticalScroller ? -width : 0
        rowHeaderBottom?.constant = scrollView.hasHorizontalScroller ? -width : 0
    }

    /// For the headless checks: the scrollers and the headers' frames.
    var scrollerInfoForTesting: String {
        func describe(_ scroller: NSScroller?) -> String {
            guard let scroller else { return "none" }
            return "\(NSStringFromRect(scroller.frame)) style=\(scroller.scrollerStyle == .legacy ? "legacy" : "overlay") "
                + "knob=\(String(format: "%.2f", scroller.knobProportion)) hidden=\(scroller.isHidden) alpha=\(scroller.alphaValue)"
        }
        let v = describe(scrollView.verticalScroller)
        let h = describe(scrollView.horizontalScroller)
        return "style=\(scrollView.scrollerStyle == .legacy ? "legacy" : "overlay") vertical=\(v) horizontal=\(h) "
            + "clip=\(NSStringFromRect(scrollView.contentView.frame)) columnHeader=\(columnHeaderView.map { NSStringFromRect($0.frame) } ?? "none") "
            + "rowHeader=\(rowHeaderView.map { NSStringFromRect($0.frame) } ?? "none")"
    }

    /// Format → Workbook… (dialog_workbook_attr).
    @objc func formatWorkbook(_ sender: Any?) {
        guard let window, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let dialog = WorkbookAttributesDialog(workbook: workbook)
        dialog.present(in: window) { [weak self] settings in
            guard let self else { return }
            workbook.showsHorizontalScrollbar = settings.horizontalScrollbar
            workbook.showsVerticalScrollbar = settings.verticalScrollbar
            workbook.showsSheetTabs = settings.sheetTabs
            workbook.autoCompletes = settings.autoCompletion
            workbook.showsFunctionCellMarkers = settings.functionMarkers
            workbook.showsExtensionMarkers = settings.extensionMarkers
            workbook.isProtected = settings.protected
            applyWorkbookView()
        }
    }

    /// File → Properties… (dialog_doc_metadata).
    @objc func documentProperties(_ sender: Any?) {
        guard let window, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let dialog = DocumentPropertiesDialog(workbook: workbook, fileURL: workbookDocument?.fileURL)
        dialog.present(in: window) { [weak self] values, calculation, changes in
            guard let self else { return true }
            do {
                try workbook.setDocumentProperties(values)
                // The Properties page's staged sets and removals, each a
                // command as the GTK page runs them.
                for change in changes {
                    switch change {
                    case .set(let name, let type, let value): try workbook.setDocumentProperty(name, type: type, value: value)
                    case .remove(let name): try workbook.removeDocumentProperty(name)
                    }
                }
            } catch {
                present(error)
                return false
            }
            // The Calculation page sets the workbook at once, as the GTK does.
            workbook.recalculatesAutomatically = calculation.automatic
            workbook.iterationEnabled = calculation.iterates
            workbook.iterationMaximum = calculation.maximum
            workbook.iterationTolerance = calculation.tolerance
            if calculation.automatic { workbook.recalculate() }
            return true
        }
    }

    /// Edit → Select → Array, Depends, Inputs (cmd-edit.c).
    @objc func selectArray(_ sender: Any?) { selectWith { $0.selectCurrentArray() } }
    @objc func selectDependents(_ sender: Any?) { selectWith { $0.selectDependents() } }
    @objc func selectInputs(_ sender: Any?) { selectWith { $0.selectInputs() } }

    private func selectWith(_ select: (Sheet) -> Bool) {
        guard let sheet = gridView.sheet else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        if !select(sheet) { NSSound.beep() }
        gridView.needsDisplay = true
    }
    private var tabSheets: [Sheet] = []
    /// Zoom steps for the View menu, as percentages.
    private static let zoomSteps: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4]

    init(workbook: Workbook, document: WorkbookDocument) {
        self.workbook = workbook
        self.workbookDocument = document
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.collectionBehavior.insert(.fullScreenPrimary)   // View → Enter Full Screen
        window.minSize = NSSize(width: 400, height: 300)
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
        installToolbar(in: window)
        workbook.delegate = self
        workbook.resendDelegateState()
        rebuildTabs()
        show(sheet: workbook.currentSheet ?? workbook.sheets.first)
        window.center()
        window.setFrameAutosaveName("WorkbookWindow")
        autosaveTime = Engine.shared?.preferences.autosaveTime ?? 0
        scheduleAutosave()
        UserDefaults.standard.register(defaults: [Self.statusBarDefaultsKey: true])
        autoExpression.isHidden = !UserDefaults.standard.bool(forKey: Self.statusBarDefaultsKey)
    }

    // MARK: View → Status Bar

    /// The GTK View → View Statusbar (wbcg_toggle_visibility): the status
    /// area, here the auto-expression at the right of the tab bar, shown
    /// or hidden for every window, remembered in the defaults.
    static let statusBarDefaultsKey = "ShowStatusBar"
    var statusBarIsShown: Bool { !autoExpression.isHidden }

    @objc func toggleStatusBar(_ sender: Any?) {
        let show = autoExpression.isHidden
        UserDefaults.standard.set(show, forKey: Self.statusBarDefaultsKey)
        for window in NSApp.windows {
            (window.windowController as? WorkbookWindowController)?.autoExpression.isHidden = !show
        }
    }

    // MARK: Auto Save

    /// The GTK's per-window autosave (wbc-gtk.c cb_autosave): every
    /// `autosaveTime` seconds (0 for never; the preference
    /// `core/workbook/autosave_time` to start with) an edited workbook is
    /// saved, after a question first when `autosavePrompt` is on.
    var autosaveTime = 0 { didSet { scheduleAutosave() } }
    var autosavePrompt = false
    private var autosaveTimer: Timer?
    var autosaveTimerIsScheduledForTesting: Bool { autosaveTimer != nil }

    private func scheduleAutosave() {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
        guard autosaveTime > 0 else { return }
        let timer = Timer(timeInterval: TimeInterval(autosaveTime), repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated { autosaveNow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        autosaveTimer = timer
    }

    /// What the timer does (cb_autosave): nothing unless the workbook is
    /// edited; the question when it is asked for; then File → Save (a
    /// Save panel for an untitled workbook, as the GTK's gui_file_save).
    func autosaveNow(completion: (((any Error)?) -> Void)? = nil) {
        guard autosaveTime > 0, let document = workbookDocument, document.isDocumentEdited, let window else { return }
        let save = {
            if let url = document.fileURL, let type = document.fileType {
                document.save(to: url, ofType: type, for: .saveOperation) { error in completion?(error) }
            } else {
                document.save(nil)   // the Save panel, as gui_file_save
            }
        }
        guard autosavePrompt else {
            save()
            return
        }
        if ProcessInfo.processInfo.environment["GNM_SNAPSHOT"] != nil {
            NSLog("autosave: would ask to save %@", document.displayName)
            return
        }
        guard window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the workbook \(document.displayName)?"
        alert.addButton(withTitle: Localization.title("Yes"))
        alert.addButton(withTitle: Localization.title("No"))
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            save()
        }
    }

    /// Tools → Auto Save… (dialog_autosave).
    @objc func autoSave(_ sender: Any?) {
        guard let window, window.attachedSheet == nil else { return }
        let dialog = AutoSaveDialog(seconds: autosaveTime, prompt: autosavePrompt)
        dialog.present(in: window) { [weak self] seconds, prompt in
            guard let self else { return }
            autosavePrompt = prompt
            autosaveTime = seconds
        }
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
        formulaField.lineBreakMode = .byClipping
        formulaField.isSelectable = true
        formulaField.isEditable = true
        formulaField.delegate = self
        formulaField.cell?.usesSingleLineMode = false   // multi-line texts show every line
        formulaField.cell?.wraps = false
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
        formulaFieldHeight = formulaField.heightAnchor.constraint(equalToConstant: 24)
        formulaBarHeight = formulaBar.heightAnchor.constraint(equalToConstant: 32)
        NSLayoutConstraint.activate([
            nameBox.heightAnchor.constraint(equalToConstant: 24),
            formulaFieldHeight!,
            formulaBarHeight!,
        ])

        scrollView.contentView = GridClipView()   // clamps scrolling under frozen panes
        scrollView.documentView = gridView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy   // always visible, as the GTK's scrollbars
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
        columnHeaderView = columnHeader
        rowHeaderView = rowHeader
        gridView.headerViews = [columnHeader, rowHeader]
        hiddenColumnHeaderConstraint = columnHeader.heightAnchor.constraint(equalToConstant: 0)
        hiddenRowHeaderConstraint = rowHeader.widthAnchor.constraint(equalToConstant: 0)
        let pane = NSView()
        pane.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(rowHeader)
        pane.addSubview(columnHeader)
        pane.addSubview(scrollView)
        sheetPane = pane
        rowHeaderBottom = rowHeader.bottomAnchor.constraint(equalTo: pane.bottomAnchor)
        NSLayoutConstraint.activate([
            rowHeader.topAnchor.constraint(equalTo: pane.topAnchor),
            rowHeaderBottom!,
            columnHeader.topAnchor.constraint(equalTo: pane.topAnchor),
            scrollView.topAnchor.constraint(equalTo: columnHeader.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
        ])
        layoutHeaders(rightToLeft: false)
        gridView.directionDidChange = { [weak self] in
            guard let self else { return }
            self.layoutHeaders(rightToLeft: self.gridView.sheet?.isRightToLeft ?? false)
        }

        tabs.segmentStyle = .texturedRounded
        tabs.trackingMode = .selectOne
        tabs.target = self
        tabs.action = #selector(tabChanged(_:))
        tabs.onReorder = { [weak self] from, to in self?.reorderTab(from: from, to: to) }
        gridView.openDroppedDocument = { url in
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSLog("open %@ failed: %@", url.path, error.localizedDescription) }
            }
        }
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
        self.tabBar = tabBar
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
        gridView.geometryDidChange = { [weak self] in
            self?.updateSubtitle()
            self?.applySheetDisplay()
        }
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
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            textView.insertText("\n", replacementRange: textView.selectedRange())
            fitFormulaBar(to: formulaField.stringValue)
            return true
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
            tabs.setWidth(0, forSegment: i)
            // The tab color as a swatch before the name: a segmented control
            // has no per-segment background.  A text color cannot color a
            // segment's label either, so such a tab carries its name drawn
            // in that color as its image (over the background, when set).
            let background = sheet.tabColor().flatMap(NSColor.init(cgColor:))
            if let text = sheet.tabTextColor().flatMap(NSColor.init(cgColor:)) {
                tabs.setLabel("", forSegment: i)
                tabs.setImage(Self.coloredName(sheet.name, text: text, background: background, font: tabs.font), forSegment: i)
                tabs.setImageScaling(.scaleNone, forSegment: i)
            } else {
                tabs.setLabel(sheet.name, forSegment: i)
                if let background {
                    tabs.setImage(Self.swatch(background), forSegment: i)
                    tabs.setImageScaling(.scaleNone, forSegment: i)
                } else {
                    tabs.setImage(nil, forSegment: i)
                }
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

    /// A tab's name in its text color, on its background color when it
    /// has one (the GTK draws the label so over the tab).
    private static func coloredName(_ name: String, text: NSColor, background: NSColor?, font: NSFont?) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize), .foregroundColor: text]
        let size = (name as NSString).size(withAttributes: attributes)
        let padding: CGFloat = background == nil ? 0 : 4
        let image = NSImage(size: NSSize(width: ceil(size.width) + 2 * padding, height: ceil(size.height) + 2), flipped: false) { rect in
            if let background {
                background.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            }
            (name as NSString).draw(at: NSPoint(x: padding, y: 1), withAttributes: attributes)
            return true
        }
        return image
    }

    /// A tab as shown: its label and image size (the headless checks).
    func tabDescriptionForTesting(_ segment: Int) -> String {
        guard segment >= 0, segment < tabs.segmentCount else { return "none" }
        let image = tabs.image(forSegment: segment)
        return "label='\(tabs.label(forSegment: segment) ?? "")' image=\(image.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "none")"
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
            applySheetDisplay()
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
        alert.addButton(withTitle: Localization.title("OK"))
        alert.addButton(withTitle: Localization.title("Cancel"))
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

    func runSizeCommand(_ command: (Sheet) throws -> Void) {
        guard let sheet = gridView.sheet else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        do {
            try command(sheet)
        } catch {
            present(error)
        }
        updateToolbarState()
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
        let model = FormatCellsModel(format: sheet.formatOfSelection, isMultiCell: multi, sheetProtected: sheet.isProtected)
        let hosting = NSHostingController(rootView: FormatCellsView(model: model) { [weak self] accepted in
            self?.finishFormatCells(accepted: accepted, model: model)
        })
        let sheetWindow = NSWindow(contentViewController: hosting)
        sheetWindow.styleMask = [.titled]
        sheetWindow.title = Localization.title("Format Cells")
        formatSheetWindow = sheetWindow
        window.beginSheet(sheetWindow) { [weak self] _ in self?.formatSheetWindow = nil }
    }

    private func finishFormatCells(accepted: Bool, model: FormatCellsModel) {
        if let sheetWindow = formatSheetWindow {
            window?.endSheet(sheetWindow)
        }
        guard accepted, let sheet = gridView.sheet else { return }
        applyFormatCells(model, to: sheet)
    }

    /// The dialog's OK (cb_fmt_dialog_dialog_apply): the style changes,
    /// then the sheet's protection when its box was toggled.
    func applyFormatCells(_ model: FormatCellsModel, to sheet: Sheet) {
        do {
            if !model.touched.isEmpty { try sheet.apply(model.changes()) }
            if model.sheetProtectedChanged, model.sheetProtected != sheet.isProtected {
                try workbook.setSheet(sheet, protected: model.sheetProtected)
            }
        } catch {
            present(error)
        }
    }

    // MARK: Sheet display (Format → Sheet)

    /// Collapse the header views to nothing when the sheet hides them.
    private var hiddenColumnHeaderConstraint: NSLayoutConstraint?
    private var hiddenRowHeaderConstraint: NSLayoutConstraint?
    /// The header views and their pane, laid out again when a sheet's
    /// direction changes: the row header moves to the right side.
    private var columnHeaderView: ColumnHeaderView?
    private var rowHeaderView: RowHeaderView?
    private var sheetPane: NSView?
    private var headerConstraints: [NSLayoutConstraint] = []
    private var headersAreRightToLeft = false

    /// The row header at the left of the grid, or at the right of a
    /// right-to-left sheet (the GTK mirrors its whole table).
    private func layoutHeaders(rightToLeft: Bool) {
        guard let pane = sheetPane, let rowHeader = rowHeaderView, let columnHeader = columnHeaderView,
              headerConstraints.isEmpty || rightToLeft != headersAreRightToLeft else { return }
        NSLayoutConstraint.deactivate(headerConstraints)
        headersAreRightToLeft = rightToLeft
        // The vertical scroller keeps the scroll view's right edge either
        // way, so the column header's trailing edge stops short of it.
        columnHeaderTrailing = rightToLeft
            ? columnHeader.trailingAnchor.constraint(equalTo: rowHeader.leadingAnchor)
            : columnHeader.trailingAnchor.constraint(equalTo: pane.trailingAnchor)
        headerConstraints = rightToLeft ? [
            rowHeader.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            columnHeader.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            columnHeaderTrailing!,
            scrollView.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rowHeader.leadingAnchor),
        ] : [
            rowHeader.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            columnHeader.leadingAnchor.constraint(equalTo: rowHeader.trailingAnchor),
            columnHeaderTrailing!,
            scrollView.leadingAnchor.constraint(equalTo: rowHeader.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
        ]
        NSLayoutConstraint.activate(headerConstraints)
        updateHeaderInsets()
    }

    /// The sheet's Hide Column Headers and Hide Row Headers, on the
    /// header views beside the grid.
    func applySheetDisplay() {
        let hideColumns = gridView.sheet?.hidesColumnHeader ?? false
        let hideRows = gridView.sheet?.hidesRowHeader ?? false
        hiddenColumnHeaderConstraint?.isActive = hideColumns
        hiddenRowHeaderConstraint?.isActive = hideRows
        if gridView.headerViews.count == 2 {
            gridView.headerViews[0].isHidden = hideColumns
            gridView.headerViews[1].isHidden = hideRows
        }
        layoutHeaders(rightToLeft: gridView.sheet?.isRightToLeft ?? false)
    }

    private func toggleDisplayOption(_ option: Sheet.DisplayOption) {
        guard let sheet = gridView.sheet else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        do {
            try sheet.toggleDisplayOption(option)
        } catch {
            present(error)
        }
    }

    @objc func toggleDisplayFormulas(_ sender: Any?) { toggleDisplayOption(.formulas) }
    @objc func toggleR1C1(_ sender: Any?) { toggleDisplayOption(.r1c1) }
    @objc func toggleHideZeros(_ sender: Any?) { toggleDisplayOption(.hideZeros) }
    /// Format → Sheet → Right to Left (the GTK's SheetDirection toggle).
    @objc func toggleDirection(_ sender: Any?) {
        toggleDisplayOption(.rightToLeft)
        gridView.syncDirection()
    }
    @objc func toggleHideGridLines(_ sender: Any?) { toggleDisplayOption(.hideGridLines) }
    @objc func toggleHideColumnHeaders(_ sender: Any?) { toggleDisplayOption(.hideColumnHeader) }
    @objc func toggleHideRowHeaders(_ sender: Any?) { toggleDisplayOption(.hideRowHeader) }

    /// View → Zoom… and Format → Sheet → Zoom…: the GTK dialog.
    @objc func zoomDialog(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        ZoomDialog(sheet: sheet).present(in: window) { [weak self] factor, all in
            guard let self else { return true }
            do {
                try sheet.setZoomFactor(factor, forAllSheets: all)
                return true
            } catch {
                presentMessage(error.localizedDescription)
                return false
            }
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

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        validateUserInterfaceItem(item)
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
        case #selector(zoomDialog(_:)):
            return gridView.sheet != nil && window?.attachedSheet == nil
        case #selector(toggleDisplayFormulas(_:)), #selector(toggleR1C1(_:)), #selector(toggleHideZeros(_:)),
             #selector(toggleHideGridLines(_:)), #selector(toggleHideColumnHeaders(_:)), #selector(toggleHideRowHeaders(_:)),
             #selector(toggleDisplayOutlines(_:)), #selector(toggleOutlineSymbolsBelow(_:)), #selector(toggleOutlineSymbolsRight(_:)),
             #selector(toggleDirection(_:)):
            guard let sheet = gridView.sheet else { return false }
            let option: Sheet.DisplayOption
            switch item.action {
            case #selector(toggleDisplayFormulas(_:)): option = .formulas
            case #selector(toggleR1C1(_:)): option = .r1c1
            case #selector(toggleHideZeros(_:)): option = .hideZeros
            case #selector(toggleHideGridLines(_:)): option = .hideGridLines
            case #selector(toggleHideColumnHeaders(_:)): option = .hideColumnHeader
            case #selector(toggleDisplayOutlines(_:)): option = .outlines
            case #selector(toggleOutlineSymbolsBelow(_:)): option = .outlineSymbolsBelow
            case #selector(toggleOutlineSymbolsRight(_:)): option = .outlineSymbolsRight
            case #selector(toggleDirection(_:)): option = .rightToLeft
            default: option = .hideRowHeader
            }
            (item as? NSMenuItem)?.state = sheet.displayOption(option) ? .on : .off
            return true
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
             #selector(goalSeek(_:)), #selector(conditionalFormatting(_:)), #selector(descriptiveStatistics(_:)),
             #selector(correlation(_:)), #selector(covariance(_:)), #selector(regression(_:)), #selector(dataValidation(_:)),
             #selector(meanTest(_:)), #selector(varianceTest(_:)), #selector(anovaSingleFactor(_:)), #selector(ranking(_:)),
             #selector(sampling(_:)), #selector(movingAverage(_:)), #selector(exponentialSmoothing(_:)), #selector(insertHyperlink(_:)),
             #selector(solver(_:)), #selector(pageSetup(_:)), #selector(printSheet(_:)), #selector(setPrintArea(_:)), #selector(clearPrintArea(_:)),
             #selector(toggleBold(_:)), #selector(toggleItalic(_:)), #selector(toggleUnderline(_:)), #selector(insertFunction(_:)),
             #selector(dataTable(_:)), #selector(tabulate(_:)), #selector(randomNumbers(_:)), #selector(correlatedRandomNumbers(_:)),
             #selector(groupOutline(_:)), #selector(ungroupOutline(_:)), #selector(hideDetail(_:)), #selector(showDetail(_:)),
             #selector(consolidate(_:)), #selector(shuffle(_:)):
            return gridView.sheet != nil && window?.attachedSheet == nil
        case #selector(removeSheet(_:)):
            return gridView.sheet != nil && workbook.canRemoveSheets
        case #selector(hideSheet(_:)):
            return gridView.sheet != nil && workbook.sheets.filter({ $0.isVisible }).count > 1
        case #selector(unhideSheet(_:)):
            return workbook.sheets.contains { !$0.isVisible } && window?.attachedSheet == nil
        case #selector(manageSheets(_:)), #selector(pluginManager(_:)), #selector(formatWorkbook(_:)), #selector(documentProperties(_:)):
            return window?.attachedSheet == nil
        case #selector(selectArray(_:)), #selector(selectDependents(_:)), #selector(selectInputs(_:)):
            return gridView.sheet != nil
        case #selector(scenarioAdd(_:)), #selector(scenarioView(_:)), #selector(simulation(_:)), #selector(autoFormat(_:)):
            return gridView.sheet != nil && window?.attachedSheet == nil
        case #selector(insertFrame(_:)), #selector(insertButton(_:)), #selector(insertCheckbox(_:)), #selector(insertRadioButton(_:)),
             #selector(insertScrollbar(_:)), #selector(insertSpinButton(_:)), #selector(insertSlider(_:)), #selector(insertList(_:)),
             #selector(insertCombo(_:)), #selector(alignLeft(_:)), #selector(alignCenter(_:)), #selector(alignRight(_:)),
             #selector(centerAcrossSelection(_:)), #selector(formatAsAccounting(_:)), #selector(formatAsPercentage(_:)),
             #selector(formatWithThousands(_:)), #selector(increasePrecision(_:)), #selector(decreasePrecision(_:)), #selector(autoSum(_:)),
             #selector(increaseIndent(_:)), #selector(decreaseIndent(_:)), #selector(toggleSuperscript(_:)), #selector(toggleSubscript(_:)),
             #selector(clearFill(_:)):
            return gridView.sheet != nil
        case #selector(advancedFilter(_:)):
            return gridView.sheet != nil && window?.attachedSheet == nil
        case #selector(pasteSpecial(_:)):
            return gridView.sheet != nil && window?.attachedSheet == nil && workbook.canPaste
        case #selector(moveSheetLeft(_:)):
            return (gridView.sheet?.index ?? 0) > 0
        case #selector(moveSheetRight(_:)):
            guard let sheet = gridView.sheet else { return false }
            return sheet.index < workbook.sheets.count - 1
        case #selector(repeatExport(_:)):
            return workbook.lastExportURL != nil
        case #selector(toggleStatusBar(_:)):
            if let menuItem = item as? NSMenuItem { menuItem.state = statusBarIsShown ? .on : .off }
            return true
        case #selector(showPrintArea(_:)):
            var area = CellRange()
            return gridView.sheet?.getPrintArea(&area) ?? false
        case #selector(toggleColumnPageBreak(_:)), #selector(toggleRowPageBreak(_:)):
            // wb_control_menu_state_update's MS_PAGE_BREAKS: the label says
            // what the item does; the first column (row) takes no break.
            guard let sheet = gridView.sheet else { return false }
            let edit = sheet.editPosition
            let columns = item.action == #selector(toggleColumnPageBreak(_:))
            let has = columns ? sheet.columnPageBreaks.contains(NSNumber(value: edit.column))
                              : sheet.rowPageBreaks.contains(NSNumber(value: edit.row))
            if let menuItem = item as? NSMenuItem {
                menuItem.title = Localization.title((has ? "Remove " : "Add ") + (columns ? "Column" : "Row") + " Page Break")
            }
            return columns ? edit.column != 0 : edit.row != 0
        case #selector(clearPageBreaks(_:)):
            return gridView.sheet?.hasManualPageBreaks ?? false
        case #selector(toggleBold(_:)), #selector(toggleItalic(_:)), #selector(toggleUnderline(_:)),
             #selector(toggleDoubleUnderline(_:)), #selector(toggleSingleLowUnderline(_:)), #selector(toggleDoubleLowUnderline(_:)),
             #selector(toggleStrikethrough(_:)), #selector(toggleSuperscript(_:)), #selector(toggleSubscript(_:)):
            guard gridView.sheet != nil else { return false }
            if let menuItem = item as? NSMenuItem { menuItem.state = fontMenuItemIsOn(item.action) ? .on : .off }
            return true
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
        alert.messageText = Localization.title("Paste Special")
        alert.addButton(withTitle: Localization.title("Paste"))
        alert.addButton(withTitle: Localization.title("Paste Link"))
        alert.addButton(withTitle: Localization.title("Cancel"))
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
        let skipBlanks = NSButton(checkboxWithTitle: Localization.title("Skip blanks"), target: nil, action: nil)
        let keepReferences = NSButton(checkboxWithTitle: Localization.title("Don't change formulae"), target: nil, action: nil)
        let widths = NSButton(checkboxWithTitle: Localization.title("Column widths"), target: nil, action: nil)
        let heights = NSButton(checkboxWithTitle: Localization.title("Row heights"), target: nil, action: nil)
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: Localization.title("Paste:")), what],
            [NSTextField(labelWithString: Localization.title("Operation:")), operation],
            [NSTextField(labelWithString: Localization.title("Region:")), region],
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
        alert.messageText = Localization.title("Rename Sheet")
        alert.informativeText = "A name for the sheet \"\(current.name)\"."
        alert.addButton(withTitle: Localization.title("Rename"))
        alert.addButton(withTitle: Localization.title("Cancel"))
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
        alert.messageText = Localization.title("Resize Sheet")
        alert.informativeText = "Sizes are powers of two. A sheet cannot shrink below its data."
        alert.addButton(withTitle: Localization.title("Resize"))
        alert.addButton(withTitle: Localization.title("Cancel"))
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
        let all = NSButton(checkboxWithTitle: Localization.title("Apply to all sheets"), target: nil, action: nil)
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: Localization.title("Columns:")), columns],
            [NSTextField(labelWithString: Localization.title("Rows:")), rows],
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
        alert.messageText = Localization.title("Tab Color")
        alert.informativeText = "Colors of the tab for the sheet \"\(sheet.name)\"."
        alert.addButton(withTitle: Localization.title("Set"))
        alert.addButton(withTitle: Localization.title("Cancel"))
        func well(_ color: CGColor?, none: NSButton) -> NSColorWell {
            let well = TabColorWell(frame: NSRect(x: 0, y: 0, width: 60, height: 24))
            well.widthAnchor.constraint(equalToConstant: 60).isActive = true
            well.heightAnchor.constraint(equalToConstant: 24).isActive = true
            if let color, let nsColor = NSColor(cgColor: color) {
                well.color = nsColor
            } else {
                none.state = .on
            }
            // Picking a color means a color: the None box clears itself
            // (it stayed checked before, so Set changed nothing).
            well.noneBox = none
            return well
        }
        let noBackground = NSButton(checkboxWithTitle: Localization.title("None"), target: nil, action: nil)
        let noText = NSButton(checkboxWithTitle: Localization.title("None"), target: nil, action: nil)
        let background = well(sheet.tabColor(), none: noBackground)
        let text = well(sheet.tabTextColor(), none: noText)
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: Localization.title("Background:")), background, noBackground],
            [NSTextField(labelWithString: Localization.title("Text:")), text, noText],
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
                               retainFormats: request.retainFormats, locale: request.locale)
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
        alert.messageText = Localization.title("Go To")
        alert.informativeText = "A cell such as C10, a range such as B2:D4, a sheet-qualified reference such as Sheet2!A1, or a defined name."
        alert.addButton(withTitle: Localization.title("Go"))
        alert.addButton(withTitle: Localization.title("Cancel"))
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
        alert.addButton(withTitle: Localization.title("Cancel"))
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
        alert.messageText = Localization.title("Fill Series")
        alert.informativeText = "Fill the selection with a series from the start value. Leave the step empty to spread the series to the stop value over the selection."
        alert.addButton(withTitle: Localization.title("Fill"))
        alert.addButton(withTitle: Localization.title("Cancel"))
        let direction = NSPopUpButton(frame: .zero, pullsDown: false)
        direction.addItems(withTitles: ["In columns (down)", "In rows (across)"].map(Localization.title))
        direction.selectItem(at: preferRows ? 1 : 0)
        let kind = NSPopUpButton(frame: .zero, pullsDown: false)
        kind.addItems(withTitles: ["Linear", "Growth", "Date"].map(Localization.title))
        let unit = NSPopUpButton(frame: .zero, pullsDown: false)
        unit.addItems(withTitles: ["Day", "Weekday", "Month", "Year"].map(Localization.title))
        let start = NSTextField(string: sheet.displayTextOfCell(atColumn: range.start.column, row: range.start.row) ?? "")
        let lastColumn = preferRows ? range.end.column : range.start.column
        let lastRow = preferRows ? range.start.row : range.end.row
        let stop = NSTextField(string: (lastColumn != range.start.column || lastRow != range.start.row)
                               ? (sheet.displayTextOfCell(atColumn: lastColumn, row: lastRow) ?? "") : "")
        let step = NSTextField(string: "1")
        for field in [start, step, stop] { field.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true }
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: Localization.title(text))
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

    // MARK: Conditional Formatting (Format menu)

    var conditionalDialog: ConditionalFormatDialog?

    @objc func conditionalFormatting(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, conditionalDialog == nil, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let dialog = ConditionalFormatDialog(sheet: sheet)
        conditionalDialog = dialog
        dialog.run(in: window) { [weak self] conditions in
            guard let self else { return }
            conditionalDialog = nil
            guard let conditions else { return }
            runSizeCommand { sheet in try sheet.setConditionalFormats(conditions) }
        }
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
        alert.messageText = Localization.title("Goal Seek")
        alert.informativeText = "Change one cell until the formula in another reaches a value."
        alert.addButton(withTitle: Localization.title("Seek"))
        alert.addButton(withTitle: Localization.title("Cancel"))
        let setCell = NSTextField(string: sheet.name(ofColumn: edit.column) + sheet.name(ofRow: edit.row))
        let toValue = NSTextField(string: "0")
        let changeCell = NSTextField(string: "")
        let atLeast = NSTextField(string: "")
        let atMost = NSTextField(string: "")
        for field in [setCell, toValue, changeCell, atLeast, atMost] { field.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true }
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: Localization.title(text))
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

    // MARK: Functions

    /// Insert → Function…: the selector; the chosen name goes into the
    /// formula being edited, or starts one.
    @objc func insertFunction(_ sender: Any?) {
        guard let window, gridView.sheet != nil, window.attachedSheet == nil, let engine = Engine.shared else { return }
        let dialog = FunctionSelectorDialog(engine: engine)
        dialog.present(in: window) { [weak self] function in
            self?.gridView.insertFunction(function.name)
        }
    }

    // MARK: Font shortcuts

    /// The GTK toggle actions (toggle_font_attr): the selection takes the
    /// opposite of the edit position's attribute, as one command.
    private func toggleFont(_ change: (CellFormat, CellFormat) -> Void) {
        runSizeCommand { sheet in
            let current = sheet.formatOfSelection
            let format = CellFormat()
            change(format, current)
            try sheet.apply(format)
        }
    }

    @objc func toggleBold(_ sender: Any?) {
        toggleFont { format, current in format.bold = NSNumber(value: !(current.bold?.boolValue ?? false)) }
    }

    @objc func toggleItalic(_ sender: Any?) {
        toggleFont { format, current in format.italic = NSNumber(value: !(current.italic?.boolValue ?? false)) }
    }

    @objc func toggleUnderline(_ sender: Any?) { toggleUnderlineStyle(.single) }
    @objc func toggleDoubleUnderline(_ sender: Any?) { toggleUnderlineStyle(.double) }
    @objc func toggleSingleLowUnderline(_ sender: Any?) { toggleUnderlineStyle(.singleLow) }
    @objc func toggleDoubleLowUnderline(_ sender: Any?) { toggleUnderlineStyle(.doubleLow) }

    /// The GTK underline toggles: the style when it is not there, none
    /// when it is (toggle_font_attr with UNDERLINE_* and UNDERLINE_NONE).
    private func toggleUnderlineStyle(_ style: UnderlineStyle) {
        toggleFont { format, current in
            let on = (current.underline?.intValue ?? 0) == style.rawValue
            format.underline = NSNumber(value: on ? UnderlineStyle.none.rawValue : style.rawValue)
        }
    }

    @objc func toggleStrikethrough(_ sender: Any?) {
        toggleFont { format, current in format.strikethrough = NSNumber(value: !(current.strikethrough?.boolValue ?? false)) }
    }

    /// The check marks of the Format → Font items: the edit position's
    /// attributes, as the GTK toggle actions show them.
    func fontMenuItemIsOn(_ action: Selector?) -> Bool {
        guard let sheet = gridView.sheet, let action else { return false }
        let current = sheet.formatOfSelection
        switch action {
        case #selector(toggleBold(_:)): return current.bold?.boolValue ?? false
        case #selector(toggleItalic(_:)): return current.italic?.boolValue ?? false
        case #selector(toggleUnderline(_:)): return current.underline?.intValue == UnderlineStyle.single.rawValue
        case #selector(toggleDoubleUnderline(_:)): return current.underline?.intValue == UnderlineStyle.double.rawValue
        case #selector(toggleSingleLowUnderline(_:)): return current.underline?.intValue == UnderlineStyle.singleLow.rawValue
        case #selector(toggleDoubleLowUnderline(_:)): return current.underline?.intValue == UnderlineStyle.doubleLow.rawValue
        case #selector(toggleStrikethrough(_:)): return current.strikethrough?.boolValue ?? false
        case #selector(toggleSuperscript(_:)): return sheet.fontScriptOfSelection == .superscript
        case #selector(toggleSubscript(_:)): return sheet.fontScriptOfSelection == .subscript
        default: return false
        }
    }

    // MARK: Printing

    /// For the headless checks: the last job built for printing.
    nonisolated(unsafe) static var lastPrintJob: PrintJob?

    /// File → Page Setup…: the GTK dialog as an alert sheet, recorded as
    /// one command for the sheet or every sheet.
    @objc func pageSetup(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let base = sheet.printSettings
        let dialog = PageSetupDialog(settings: base)
        dialog.present(in: window, base: base) { [weak self] settings, all in
            guard let self else { return true }
            do {
                try sheet.setPrintSettings(settings, forAllSheets: all)
                if let preview = printPreview, preview.window.isVisible { preview.reload() }
                return true
            } catch {
                presentMessage(error.localizedDescription)
                return false
            }
        }
    }

    // MARK: Print Preview

    private(set) var printPreview: PrintPreviewController?

    /// File → Print Preview (cb_file_print_preview): the pages in a
    /// window of their own, one per workbook window, kept between uses.
    @objc func printPreview(_ sender: Any?) {
        guard gridView.sheet != nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        if printPreview == nil { printPreview = PrintPreviewController(controller: self) }
        printPreview?.show()
    }

    /// File → Print…: the sheet's print area (or the whole used range)
    /// paginated by the engine, through the system print panel.
    @objc func printSheet(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        guard let job = sheet.printJob(selectionOnly: false, ignoringPrintArea: false) else {
            presentMessage("There is nothing to print.")
            return
        }
        Self.lastPrintJob = job
        let view = PrintView(job: job)
        let info = PrintView.printInfo(for: job, settings: sheet.printSettings)
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = "\(document?.displayName ?? "Workbook") – \(sheet.name)"
        operation.showsPrintPanel = ProcessInfo.processInfo.environment["GNM_SNAPSHOT"] == nil
        operation.showsProgressPanel = operation.showsPrintPanel
        if operation.showsPrintPanel {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }
    }

    // MARK: Compare Sheets

    private(set) var sheetCompareDialog: SheetCompareDialog?

    /// Tools → Compare Sheets… (dialog_sheet_compare): the floating
    /// panel, one per window, kept between uses.
    @objc func compareSheets(_ sender: Any?) {
        guard gridView.sheet != nil else { return }
        if sheetCompareDialog == nil { sheetCompareDialog = SheetCompareDialog(controller: self) }
        sheetCompareDialog?.show()
    }

    // MARK: Merge

    /// Data → Merge… (dialog_merge).
    @objc func mergeData(_ sender: Any?) {
        guard let sheet = gridView.sheet, let window, window.attachedSheet == nil else { return }
        let dialog = MergeDialog(sheet: sheet)
        dialog.run(in: window) { [weak self] merged in
            guard merged, let self else { return }
            gridView.needsDisplay = true
            updateToolbarState()
        }
    }

    // MARK: Repeat Export

    /// The GTK Data → Repeat Export (gui_file_export_repeat): the
    /// question naming the place and the exporter, then the export to the
    /// same place again.  Headlessly the question is skipped.
    @objc func repeatExport(_ sender: Any?) {
        guard let window, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        guard let url = workbook.lastExportURL else {
            presentMessage("Unable to repeat export since no previous export information has been saved in this session.")
            return
        }
        let run = { [weak self] in
            guard let self else { return }
            do {
                try workbook.repeatExport()
            } catch {
                present(error)
            }
        }
        if ProcessInfo.processInfo.environment["GNM_SNAPSHOT"] != nil {
            run()
            return
        }
        let alert = NSAlert()
        let what = workbook.lastExporterWritesSingleSheet ? "the current sheet of this workbook" : "this workbook"
        alert.messageText = "Do you want to export \(what) to the location “\(url.path)” using the “\(workbook.lastExporterDescription ?? "")” exporter?"
        alert.addButton(withTitle: Localization.title("Yes"))
        alert.addButton(withTitle: Localization.title("No"))
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            run()
        }
    }

    // MARK: Send To

    /// The copy the last Send To… wrote (for the headless check).
    private(set) var lastSentCopyURL: URL?

    /// File → Send To… (cb_file_sendto): a copy written with the
    /// document's saver to a temporary folder and handed to Mail as an
    /// attachment (the GTK opens a mailto: with it attached); when no mail
    /// service can take it, the sharing picker offers the others.  The
    /// copy goes away after a while, as the GTK's does.
    @objc func sendTo(_ sender: Any?) {
        guard let document = workbookDocument, let workbook = document.workbook else { return }
        var type = document.fileType ?? WorkbookDocument.gnumericType
        var name = document.fileURL?.lastPathComponent ?? (document.displayName + ".gnumeric")
        if type == WorkbookDocument.textType {
            // The import assistant's text has no saver of its own: send
            // Gnumeric's format, as the GTK's default saver would.
            type = WorkbookDocument.gnumericType
            name = ((name as NSString).deletingPathExtension) + ".gnumeric"
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gnm-sendto-" + UUID().uuidString, isDirectory: true)
        let copy = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try workbook.writeCopy(to: copy, saverIdentifier: WorkbookDocument.saverIdentifier(for: type))
        } catch {
            try? FileManager.default.removeItem(at: folder)
            presentError(error)
            return
        }
        lastSentCopyURL = copy
        let headless = ProcessInfo.processInfo.environment["GNM_SNAPSHOT"] != nil
        if !headless {
            if let mail = NSSharingService(named: .composeEmail), mail.canPerform(withItems: [copy]) {
                mail.perform(withItems: [copy])
            } else {
                let picker = NSSharingServicePicker(items: [copy])
                let visible = gridView.visibleRect
                picker.show(relativeTo: NSRect(x: visible.minX, y: visible.minY, width: 1, height: 1), of: gridView, preferredEdge: .minY)
            }
        }
        // The mailer has long read the attachment by then (the GTK waits
        // ten seconds).
        DispatchQueue.main.asyncAfter(deadline: .now() + (headless ? 0.5 : 60)) {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// File → Print Area → Set Print Area: the selection.
    @objc func setPrintArea(_ sender: Any?) {
        guard let sheet = gridView.sheet else { return }
        runSizeCommand { sheet in
            try sheet.setPrintArea(sheet.rangeNames(inList: sheet.selectionText)?.first ?? "")
        }
        _ = sheet
    }

    @objc func clearPrintArea(_ sender: Any?) {
        runSizeCommand { try $0.setPrintArea(nil) }
    }

    /// File → Print Area → Show Print Area (cb_file_print_area_show):
    /// select the area and bring its first cell into view.
    @objc func showPrintArea(_ sender: Any?) {
        guard let sheet = gridView.sheet else { return }
        var area = CellRange()
        guard sheet.getPrintArea(&area) else { return }
        sheet.selectRange(area, editPosition: area.start)
        gridView.scrollToVisible(sheet.frameOfCell(atColumn: area.start.column, row: area.start.row).insetBy(dx: -2, dy: -2))
        gridView.needsDisplay = true
    }

    /// File → Print Area → Add/Remove Column (Row) Page Break and Clear
    /// All Page Breaks (cb_file_print_area_toggle_col/_row,
    /// cb_file_print_area_clear_pagebreaks).
    @objc func toggleColumnPageBreak(_ sender: Any?) { runSizeCommand { try $0.togglePageBreakAtEditPosition(forColumns: true) } }
    @objc func toggleRowPageBreak(_ sender: Any?) { runSizeCommand { try $0.togglePageBreakAtEditPosition(forColumns: false) } }
    @objc func clearPageBreaks(_ sender: Any?) { runSizeCommand { try $0.clearPageBreaks() } }

    // MARK: Solver

    /// For the headless checks: the last run's outcome.
    nonisolated(unsafe) static var lastSolverOutcome: SolverOutcome?

    /// Tools → Solver…: the GTK dialog as an alert sheet; Solve records
    /// the settings and starts the run, which the progress sheet follows
    /// (with its Stop button) until the outcome is shown.
    @objc func solver(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let dialog = SolverDialog(sheet: sheet)
        dialog.present(in: window) { [weak self] settings, solve in
            guard let self else { return true }
            do {
                try sheet.setSolverSettings(settings)
            } catch {
                presentMessage(error.localizedDescription)
                return false
            }
            guard solve else { return true }
            do {
                let run = try sheet.startSolver()
                let follow = { [weak self] in
                    guard let self, let window = self.window else { return }
                    solverProgress = SolverProgress(run: run, in: window) { [weak self] outcome in
                        guard let self else { return }
                        solverProgress = nil
                        Self.lastSolverOutcome = outcome
                        presentSolverOutcome(outcome)
                    }
                    solverProgress?.begin()
                }
                // The dialog's sheet is still closing; the progress sheet
                // waits a turn of the run loop (not headlessly).
                if SolverDialog.headlessDriver != nil { follow() } else { DispatchQueue.main.async(execute: follow) }
            } catch {
                presentMessage(error.localizedDescription)
            }
            return true
        }
    }

    /// The run in progress, while there is one.
    private var solverProgress: SolverProgress?

    /// The dialog's Results page: the solver and problem status, the
    /// objective value, the elapsed time.
    private func presentSolverOutcome(_ outcome: SolverOutcome) {
        guard let window else { return }
        let quality: String
        switch outcome.quality {
        case .feasible: quality = "Feasible"
        case .optimal: quality = "Optimal"
        case .infeasible: quality = "Infeasible"
        case .unbounded: quality = "Unbounded"
        default: quality = "None"
        }
        var lines = ["Solver status: \(outcome.status)" + (outcome.reason.map { " (\($0))" } ?? ""), "Problem status: \(quality)"]
        if outcome.hasSolution { lines.append("Objective value: \(outcome.objectiveValue)") }
        lines.append(String(format: "Elapsed time: %.2f s", outcome.elapsedSeconds))
        let alert = NSAlert()
        alert.messageText = outcome.hasSolution ? "The solver found a solution." : "The solver found no solution."
        alert.informativeText = lines.joined(separator: "\n")
        alert.alertStyle = outcome.hasSolution ? .informational : .warning
        if ProcessInfo.processInfo.environment["GNM_SNAPSHOT"] == nil { alert.beginSheetModal(for: window) }
    }

    // MARK: Hyperlinks

    /// Insert → Hyperlink…: the GTK dialog as an alert sheet, applied to
    /// the selection as one command; Remove takes the link away.
    @objc func insertHyperlink(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let dialog = HyperlinkDialog(sheet: sheet)
        dialog.present(in: window) { [weak self] link in
            guard let self else { return true }
            if let link, link.kind == .internal, !sheet.isValidInternalTarget(link.target) {
                presentMessage("Not a range or name")
                return false
            }
            do {
                try sheet.setHyperlink(link)
                return true
            } catch {
                presentMessage(error.localizedDescription)
                return false
            }
        }
    }

    // MARK: Validation

    /// Data → Validation…: the GTK Validation and Input Message pages as
    /// one alert sheet, applied to the selection as one command.
    @objc func dataValidation(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let dialog = ValidationDialog(sheet: sheet)
        dialog.present(in: window) { [weak self] validation, message in
            guard let self else { return true }
            do {
                try sheet.setValidation(validation, inputMessage: message)
                gridView.updateValidationState(sheet)
                return true
            } catch {
                presentMessage(error.localizedDescription)
                return false
            }
        }
    }

    /// For the headless checks: answer validation messages without the alert.
    nonisolated(unsafe) static var validationAnswerForTesting: Validation.Status?
    nonisolated(unsafe) static var lastValidationMessage: String?

    // MARK: Statistics

    @objc func descriptiveStatistics(_ sender: Any?) { runAnalysisDialog(.descriptiveStatistics) }
    @objc func correlation(_ sender: Any?) { runAnalysisDialog(.correlation) }
    @objc func covariance(_ sender: Any?) { runAnalysisDialog(.covariance) }
    @objc func regression(_ sender: Any?) { runAnalysisDialog(.regression) }
    @objc func meanTest(_ sender: Any?) { runAnalysisDialog(.meanTest) }
    @objc func varianceTest(_ sender: Any?) { runAnalysisDialog(.varianceTest) }
    @objc func anovaSingleFactor(_ sender: Any?) { runAnalysisDialog(.anovaSingleFactor) }
    @objc func ranking(_ sender: Any?) { runAnalysisDialog(.ranking) }
    @objc func sampling(_ sender: Any?) { runAnalysisDialog(.sampling) }
    @objc func movingAverage(_ sender: Any?) { runAnalysisDialog(.movingAverage) }
    @objc func exponentialSmoothing(_ sender: Any?) { runAnalysisDialog(.exponentialSmoothing) }
    @objc func frequency(_ sender: Any?) { runAnalysisDialog(.frequency) }
    @objc func histogram(_ sender: Any?) { runAnalysisDialog(.histogram) }
    @objc func fourier(_ sender: Any?) { runAnalysisDialog(.fourier) }
    @objc func principalComponents(_ sender: Any?) { runAnalysisDialog(.principalComponents) }
    @objc func kaplanMeier(_ sender: Any?) { runAnalysisDialog(.kaplanMeier) }
    @objc func normality(_ sender: Any?) { runAnalysisDialog(.normality) }
    @objc func oneMeanTest(_ sender: Any?) { runAnalysisDialog(.oneMeanTest) }
    @objc func oneMedianSignTest(_ sender: Any?) { runAnalysisDialog(.oneMedianSignTest) }
    @objc func oneMedianSignedRank(_ sender: Any?) { runAnalysisDialog(.oneMedianSignedRank) }
    @objc func twoMedianSignTest(_ sender: Any?) { runAnalysisDialog(.twoMedianSignTest) }
    @objc func twoMedianSignedRank(_ sender: Any?) { runAnalysisDialog(.twoMedianSignedRank) }
    @objc func mannWhitney(_ sender: Any?) { runAnalysisDialog(.mannWhitney) }
    @objc func anovaTwoFactor(_ sender: Any?) { runAnalysisDialog(.anovaTwoFactor) }
    @objc func homogeneity(_ sender: Any?) { runAnalysisDialog(.homogeneity) }
    @objc func independence(_ sender: Any?) { runAnalysisDialog(.independence) }
    @objc func randomNumbers(_ sender: Any?) { runAnalysisDialog(.randomNumbers) }
    @objc func consolidate(_ sender: Any?) { runAnalysisDialog(.consolidate) }

    /// Data → Shuffle…: the GTK dialog, in place.
    @objc func shuffle(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        ShuffleDialog(sheet: sheet).present(in: window) { [weak self] range, kind in
            guard let self else { return true }
            do {
                try sheet.shuffle(range, by: kind)
                return true
            } catch {
                presentMessage(error.localizedDescription)
                return false
            }
        }
    }
    @objc func correlatedRandomNumbers(_ sender: Any?) { runAnalysisDialog(.correlatedRandomNumbers) }
    // The GTK's four Claims About Two Means items preselect the kind.
    @objc func meanTestPaired(_ sender: Any?) { runAnalysisDialog(.meanTest) { $0.meanTestKind.selectItem(at: 0) } }
    @objc func meanTestKnownVariances(_ sender: Any?) { runAnalysisDialog(.meanTest) { $0.meanTestKind.selectItem(at: 1) } }
    @objc func meanTestEqualVariances(_ sender: Any?) { runAnalysisDialog(.meanTest) { $0.meanTestKind.selectItem(at: 2) } }
    @objc func meanTestUnequalVariances(_ sender: Any?) { runAnalysisDialog(.meanTest) { $0.meanTestKind.selectItem(at: 3) } }

    /// One of the GTK analysis tool dialogs as an alert sheet; the tool
    /// runs as one undoable command and the sheet written to is shown.  A
    /// refusal (the dialogs' message) re-presents the sheet with its
    /// values kept.
    private func runAnalysisDialog(_ tool: AnalysisDialog.Tool, configure: ((AnalysisDialog) -> Void)? = nil) {
        guard let window, let sheet = gridView.sheet, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let dialog = AnalysisDialog(tool: tool, sheet: sheet)
        configure?(dialog)
        dialog.present(in: window) { [weak self] analysis, output in
            guard let self else { return true }
            do {
                let written = try sheet.run(analysis, output: output)
                if written != gridView.sheet { workbook.select(written) }
                return true
            } catch {
                presentMessage(error.localizedDescription)
                return false
            }
        }
    }

    // MARK: Advanced filter (Data → Filter)

    /// Data → Filter → Advanced Filter…: the GTK dialog; in place the rows
    /// that do not match are hidden, otherwise the matches are copied.
    @objc func advancedFilter(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        AdvancedFilterDialog(sheet: sheet).present(in: window) { [weak self] filter, output in
            guard let self else { return true }
            do {
                try sheet.applyAdvancedFilter(filter, output: output)
                if output.isNewSheet, let last = workbook.sheets.last, last != gridView.sheet { workbook.select(last) }
                gridView.needsDisplay = true
                return true
            } catch {
                presentMessage(error.localizedDescription)
                return false
            }
        }
    }

    // MARK: Sheet visibility (Edit → Sheet)

    /// For the headless checks: which hidden sheet Unhide… picks.
    nonisolated(unsafe) static var unhideChoiceForTesting: String?

    @objc func hideSheet(_ sender: Any?) {
        guard let current = gridView.sheet else { return }
        runSheetCommand { workbook in
            try workbook.setSheet(current, visible: false)
            if let next = workbook.sheets.first(where: { $0.isVisible }) { workbook.select(next) }
        }
    }

    /// The Manage Sheets dialog's visibility toggle, as a choice among the
    /// hidden sheets.
    @objc func unhideSheet(_ sender: Any?) {
        guard let window, window.attachedSheet == nil else { return }
        let hidden = workbook.sheets.filter { !$0.isVisible }
        guard !hidden.isEmpty else { return }
        let show = { [weak self] (sheet: Sheet) in
            self?.runSheetCommand { workbook in
                try workbook.setSheet(sheet, visible: true)
                workbook.select(sheet)
            }
        }
        if let choice = Self.unhideChoiceForTesting {
            if let sheet = hidden.first(where: { $0.name == choice }) { show(sheet) }
            return
        }
        let alert = NSAlert()
        alert.messageText = Localization.title("Unhide Sheet")
        alert.informativeText = "Choose the sheet to show again."
        alert.addButton(withTitle: Localization.title("Unhide"))
        alert.addButton(withTitle: Localization.title("Cancel"))
        let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 26), pullsDown: false)
        popUp.addItems(withTitles: hidden.map(\.name))
        alert.accessoryView = popUp
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn, popUp.indexOfSelectedItem >= 0, popUp.indexOfSelectedItem < hidden.count else { return }
            show(hidden[popUp.indexOfSelectedItem])
        }
    }

    // MARK: Outline (Data → Outline)

    /// For the headless checks: the answer to "rows or columns?".
    nonisolated(unsafe) static var outlineAxisForTesting: Bool?

    /// group_ungroup_colrow and hide_show_detail: whole rows or whole
    /// columns selected settle the axis; otherwise the GTK asks
    /// (dialog_col_row).  `run` gets true for columns.
    private func outlineAxis(_ operation: String, then run: @escaping (Bool) -> Void) {
        guard let window, let sheet = gridView.sheet, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let wholeRows = sheet.selectionSpansAllColumns, wholeColumns = sheet.selectionSpansAllRows
        if wholeRows != wholeColumns {
            run(wholeColumns)
            return
        }
        if let answer = Self.outlineAxisForTesting {
            run(answer)
            return
        }
        let alert = NSAlert()
        alert.messageText = "\(operation) rows or columns?"
        alert.addButton(withTitle: Localization.title("Columns"))
        alert.addButton(withTitle: Localization.title("Rows"))
        alert.addButton(withTitle: Localization.title("Cancel"))
        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn: run(true)
            case .alertSecondButtonReturn: run(false)
            default: break
            }
        }
    }

    private func runOutline(_ body: (Sheet) throws -> Void) {
        guard let sheet = gridView.sheet else { return }
        do {
            try body(sheet)
        } catch {
            present(error)
        }
    }

    @objc func groupOutline(_ sender: Any?) {
        outlineAxis("Group") { [weak self] columns in self?.runOutline { try $0.groupSelection(true, columns: columns) } }
    }
    @objc func ungroupOutline(_ sender: Any?) {
        outlineAxis("Ungroup") { [weak self] columns in self?.runOutline { try $0.groupSelection(false, columns: columns) } }
    }
    @objc func hideDetail(_ sender: Any?) {
        outlineAxis("Hide Detail") { [weak self] columns in self?.runOutline { try $0.setDetailShown(false, columns: columns) } }
    }
    @objc func showDetail(_ sender: Any?) {
        outlineAxis("Show Detail") { [weak self] columns in self?.runOutline { try $0.setDetailShown(true, columns: columns) } }
    }
    @objc func toggleDisplayOutlines(_ sender: Any?) { toggleDisplayOption(.outlines) }
    @objc func toggleOutlineSymbolsBelow(_ sender: Any?) { toggleDisplayOption(.outlineSymbolsBelow) }
    @objc func toggleOutlineSymbolsRight(_ sender: Any?) { toggleDisplayOption(.outlineSymbolsRight) }

    // MARK: What-if (Data → Table, Edit → Fill → Tabulate Dependency)

    /// Data → Table…: the GTK dialog over the selection.
    @objc func dataTable(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        DataTableDialog().present(in: window) { [weak self] rowInput, columnInput in
            guard let self else { return true }
            do {
                try sheet.createDataTable(rowInput: rowInput, columnInput: columnInput)
                return true
            } catch {
                presentMessage(error.localizedDescription)
                return false
            }
        }
    }

    /// Edit → Fill → Tabulate Dependency…: the GTK dialog; the tabulation
    /// lands on new sheets.
    @objc func tabulate(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        TabulateDialog(sheet: sheet).present(in: window) { [weak self] dialog in
            guard let self else { return true }
            do {
                try sheet.tabulate(target: dialog.resultField.stringValue, dimensions: dialog.dimensions, withCoordinates: dialog.withCoordinates)
                if let last = workbook.sheets.last, last != gridView.sheet { workbook.select(last) }
                return true
            } catch {
                presentMessage(error.localizedDescription)
                return false
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
    var manageSheetsDialog: ManageSheetsDialog?
    var pluginManagerDialog: PluginManagerDialog?
    var scenarioManagerDialog: ScenarioManagerDialog?
    var autoFormatDialog: AutoFormatDialog?

    /// Format → AutoFormat… (dialog_autoformat): a template applied to the
    /// selection on OK.
    @objc func autoFormat(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, let engine = Engine.shared, autoFormatDialog == nil, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let dialog = AutoFormatDialog(engine: engine)
        autoFormatDialog = dialog
        dialog.run(in: window) { [weak self] template in
            guard let self else { return }
            autoFormatDialog = nil
            if let template {
                do {
                    try sheet.applyAutoFormat(template)
                } catch {
                    present(error)
                }
            }
            gridView.needsDisplay = true
            window.makeFirstResponder(gridView)
        }
    }

    /// Tools → Scenarios → Add… (dialog_scenario_add).
    @objc func scenarioAdd(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let dialog = ScenarioAddDialog(sheet: sheet)
        dialog.present(in: window) { [weak self] name, cells, comment in
            guard let self else { return true }
            do {
                try sheet.addScenario(named: name, comment: comment, changingCells: cells)
                return true
            } catch {
                present(error)
                return false
            }
        }
    }

    /// Tools → Scenarios → View… (the GTK scenario manager).
    @objc func scenarioView(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, scenarioManagerDialog == nil, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let dialog = ScenarioManagerDialog(sheet: sheet)
        scenarioManagerDialog = dialog
        dialog.run(in: window) { [weak self] _ in
            guard let self else { return }
            scenarioManagerDialog = nil
            workbook.resendDelegateState()
            gridView.needsDisplay = true
            window.makeFirstResponder(gridView)
        }
    }

    /// Tools → Simulation… (dialog_simulation): the run, then the results.
    @objc func simulation(_ sender: Any?) {
        guard let window, let sheet = gridView.sheet, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let dialog = SimulationDialog(sheet: sheet)
        dialog.present(in: window) { [weak self] request in
            guard let self else { return true }
            do {
                let result = try sheet.runSimulation(inputs: request.inputs, outputs: request.outputs, iterations: request.iterations,
                                                     firstRound: request.firstRound, lastRound: request.lastRound,
                                                     maximumSeconds: request.maximumSeconds, output: request.output)
                workbook.resendDelegateState()
                gridView.needsDisplay = true
                if SimulationDialog.headlessDriver != nil {
                    SimulationDialog.presentResults(result, in: window)
                } else {
                    DispatchQueue.main.async { SimulationDialog.presentResults(result, in: window) }   // after this sheet is gone
                }
                return true
            } catch {
                present(error)
                return false
            }
        }
    }

    /// The GTK Plugin Manager as a sheet (Tools → Plug-ins…).
    @objc func pluginManager(_ sender: Any?) {
        guard let window, let engine = Engine.shared, pluginManagerDialog == nil, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let dialog = PluginManagerDialog(engine: engine)
        pluginManagerDialog = dialog
        dialog.run(in: window) { [weak self] in
            guard let self else { return }
            pluginManagerDialog = nil
            window.makeFirstResponder(gridView)
        }
    }

    /// The GTK Manage Sheets dialog as a sheet; its changes are engine
    /// commands applied at once.
    @objc func manageSheets(_ sender: Any?) {
        guard let window, manageSheetsDialog == nil, window.attachedSheet == nil else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let dialog = ManageSheetsDialog(workbook: workbook)
        manageSheetsDialog = dialog
        dialog.run(in: window) { [weak self] in
            guard let self else { return }
            manageSheetsDialog = nil
            workbook.resendDelegateState()
            gridView.needsDisplay = true
            window.makeFirstResponder(gridView)
        }
    }

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
        alert.messageText = Localization.title("Insert Name")
        guard !names.isEmpty else {
            alert.informativeText = "No names are defined. Edit → Define Names… defines one."
            alert.beginSheetModal(for: window)
            return
        }
        alert.informativeText = "The name goes into the cell as a formula, or into the formula being edited."
        alert.addButton(withTitle: Localization.title("Insert"))
        alert.addButton(withTitle: Localization.title("Cancel"))
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
        alert.addButton(withTitle: Localization.title("OK"))
        alert.addButton(withTitle: Localization.title("Cancel"))
        if existing != nil {
            alert.addButton(withTitle: Localization.title("Remove"))
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
        if object.widgetKind != .none {
            editWidget(object)
            return
        }
        guard let editor = ChartEditor(editing: object) else { return }   // images have no editor (nor in the GTK)
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

    /// A widget's Properties…: its configuration dialog, the engine's
    /// command on OK.
    func editWidget(_ object: SheetObject) {
        guard let window, let sheet = object.sheet, let settings = sheet.widgetSettings(of: object) else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let dialog = WidgetDialog(settings: settings)
        dialog.present(in: window) { [weak self] edited in
            guard let self else { return true }
            do {
                try sheet.applyWidgetSettings(edited, to: object)
                gridView.needsDisplay = true
                return true
            } catch {
                present(error)
                return false
            }
        }
    }

    /// Insert → Object: a widget placed at the edit position, sized as the
    /// GTK's default creation drag would leave it.
    func insertWidget(ofKind kind: WidgetSettings.Kind) {
        guard let sheet = gridView.sheet else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let edit = sheet.editPosition
        let cell = sheet.frameOfCell(atColumn: edit.column, row: edit.row)
        let size: CGSize
        switch kind {
        case .frame: size = CGSize(width: 160, height: 100)
        case .scrollbar, .slider: size = CGSize(width: 20, height: 120)
        case .spinButton: size = CGSize(width: 80, height: 24)
        case .list: size = CGSize(width: 120, height: 90)
        case .combo: size = CGSize(width: 120, height: 24)
        default: size = CGSize(width: 100, height: 24)
        }
        do {
            let object = try sheet.insertWidget(ofKind: kind, frame: CGRect(origin: cell.origin, size: size))
            gridView.select(objects: [object])
        } catch {
            present(error)
        }
    }

    /// The object toolbar's shapes (cmd_create_line/_arrow/_rectangle/
    /// _ellipse), placed at the edit cell as the widgets are.
    func insertShape(ofKind kind: ShapeKind) {
        guard let sheet = gridView.sheet else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        let edit = sheet.editPosition
        let cell = sheet.frameOfCell(atColumn: edit.column, row: edit.row)
        let size = kind == .line || kind == .arrow ? CGSize(width: 120, height: 60) : CGSize(width: 120, height: 80)
        do {
            let object = try sheet.insertShape(ofKind: kind, frame: CGRect(origin: cell.origin, size: size))
            gridView.select(objects: [object])
        } catch {
            present(error)
        }
    }

    @objc func insertLine(_ sender: Any?) { insertShape(ofKind: .line) }
    @objc func insertArrow(_ sender: Any?) { insertShape(ofKind: .arrow) }
    @objc func insertRectangle(_ sender: Any?) { insertShape(ofKind: .rectangle) }
    @objc func insertEllipse(_ sender: Any?) { insertShape(ofKind: .ellipse) }

    /// The toolbar's Objects pull-down: the tag names the creation.
    @objc func objectKindChosen(_ sender: NSMenuItem) {
        switch sender.tag {
        case 1: insertShape(ofKind: .rectangle)
        case 2: insertShape(ofKind: .ellipse)
        case 3: insertWidget(ofKind: .frame)
        case 4: insertShape(ofKind: .line)
        case 5: insertShape(ofKind: .arrow)
        case 6: insertWidget(ofKind: .checkbox)
        case 7: insertWidget(ofKind: .radioButton)
        case 8: insertWidget(ofKind: .button)
        case 9: insertWidget(ofKind: .scrollbar)
        case 10: insertWidget(ofKind: .spinButton)
        case 11: insertWidget(ofKind: .slider)
        case 12: insertWidget(ofKind: .list)
        case 13: insertWidget(ofKind: .combo)
        default: break
        }
    }

    /// The GTK object toolbar's items in its order, with their tags.
    static let objectToolbarEntries: [(Int, String)] = [
        (1, "Rectangle"), (2, "Ellipse"), (3, "Frame"), (4, "Line"), (5, "Arrow"), (6, "Checkbox"), (7, "Radio Button"),
        (8, "Button"), (9, "Scrollbar"), (10, "Spin Button"), (11, "Slider"), (12, "List"), (13, "Combo Box"),
    ]

    // MARK: Go to Top/Bottom/First/Last

    private func navigate(to target: Sheet.NavigationTarget) {
        guard let sheet = gridView.sheet else { return }
        if gridView.isEditing { gridView.cancelEditing() }
        sheet.navigate(to: target)
        let edit = sheet.editPosition
        gridView.scrollToVisible(sheet.frameOfCell(atColumn: edit.column, row: edit.row).insetBy(dx: -2, dy: -2))
        gridView.needsDisplay = true
    }

    @objc func goToTop(_ sender: Any?) { navigate(to: .top) }
    @objc func goToBottom(_ sender: Any?) { navigate(to: .bottom) }
    @objc func goToFirst(_ sender: Any?) { navigate(to: .first) }
    @objc func goToLast(_ sender: Any?) { navigate(to: .last) }

    /// Edit → Go to Current Cell Indicator (⇧⌃G,
    /// wbcg_focus_current_cell_indicator): the name box takes the focus
    /// with its text selected.
    @objc func goToCellIndicator(_ sender: Any?) {
        guard let window else { return }
        window.makeFirstResponder(nameBox)
        nameBox.currentEditor()?.selectAll(nil)
    }

    @objc func insertFrame(_ sender: Any?) { insertWidget(ofKind: .frame) }
    @objc func insertButton(_ sender: Any?) { insertWidget(ofKind: .button) }
    @objc func insertCheckbox(_ sender: Any?) { insertWidget(ofKind: .checkbox) }
    @objc func insertRadioButton(_ sender: Any?) { insertWidget(ofKind: .radioButton) }
    @objc func insertScrollbar(_ sender: Any?) { insertWidget(ofKind: .scrollbar) }
    @objc func insertSpinButton(_ sender: Any?) { insertWidget(ofKind: .spinButton) }
    @objc func insertSlider(_ sender: Any?) { insertWidget(ofKind: .slider) }
    @objc func insertList(_ sender: Any?) { insertWidget(ofKind: .list) }
    @objc func insertCombo(_ sender: Any?) { insertWidget(ofKind: .combo) }

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
        let dpiLabel = NSTextField(labelWithString: Localization.title("Resolution (dpi):"))
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
        let row = NSStackView(views: [NSTextField(labelWithString: Localization.title("Format:")), formatPopUp, dpiLabel, resolution])
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
        alert.addButton(withTitle: Localization.title("OK"))
        alert.addButton(withTitle: Localization.title("Cancel"))
        let condition: () -> FilterCondition
        if custom {
            alert.messageText = Localization.title("Custom Filter")
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
            alert.messageText = Localization.title("Top 10 AutoFilter")
            alert.informativeText = "Show the rows with the largest or smallest values of the column."
            let isBucket = current.kind == .bucket
            let direction = NSPopUpButton(frame: .zero, pullsDown: false)
            direction.addItem(withTitle: Localization.title("Top"))
            direction.addItem(withTitle: Localization.title("Bottom"))
            direction.selectItem(at: isBucket && !current.isTop ? 1 : 0)
            let count = NSTextField(frame: NSRect(x: 0, y: 0, width: 60, height: 24))
            let formatter = NumberFormatter()
            formatter.minimum = 1
            formatter.maximumFractionDigits = 0
            count.formatter = formatter
            count.doubleValue = isBucket ? current.count : 10
            count.widthAnchor.constraint(equalToConstant: 60).isActive = true
            let unit = NSPopUpButton(frame: .zero, pullsDown: false)
            unit.addItem(withTitle: Localization.title("Items"))
            unit.addItem(withTitle: Localization.title("Percent"))
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

    /// A tab dropped at another tab's place moves the sheet there.
    func reorderTab(from: Int, to: Int) {
        guard from >= 0, from < tabSheets.count, to >= 0, to < tabSheets.count, from != to else { return }
        runSheetCommand { workbook in
            try workbook.move(tabSheets[from], toIndex: tabSheets[to].index)
        }
    }

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        guard sender.selectedSegment >= 0, sender.selectedSegment < tabSheets.count else { return }
        workbook.select(tabSheets[sender.selectedSegment])
    }

    // MARK: WorkbookDelegate

    func workbook(_ workbook: Workbook, didFocus sheet: Sheet?) {
        show(sheet: sheet)
        applyWorkbookView()
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
        fitFormulaBar(to: text)
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
        updateToolbarState()
    }

    func workbookModifiedStateDidChange(_ workbook: Workbook) {
        workbookDocument?.modifiedStateDidChange()
    }

    /// Engine commands that need confirmation (hide every row, paste
    /// thousands of copies) ask through a modal alert.
    /// `wbcg_validation_msg`: the message with the action's choices, the
    /// GTK default choice first.
    func workbook(_ workbook: Workbook, presentValidationMessage message: String, title: String?, action: Validation.Action) -> Validation.Status {
        if let canned = Self.validationAnswerForTesting {
            Self.lastValidationMessage = message
            return canned
        }
        let alert = NSAlert()
        alert.messageText = title ?? "Validation"
        alert.informativeText = message
        switch action {
        case .stop:
            alert.alertStyle = .critical
            alert.addButton(withTitle: Localization.title("Discard"))
            alert.addButton(withTitle: Localization.title("Re-Edit"))
            return alert.runModal() == .alertFirstButtonReturn ? .discard : .edit
        case .warning:
            alert.alertStyle = .warning
            alert.addButton(withTitle: Localization.title("Discard"))
            alert.addButton(withTitle: Localization.title("Accept"))
            return alert.runModal() == .alertFirstButtonReturn ? .discard : .valid
        case .parseError:
            alert.alertStyle = .critical
            alert.addButton(withTitle: Localization.title("Accept"))
            alert.addButton(withTitle: Localization.title("Re-Edit"))
            return alert.runModal() == .alertFirstButtonReturn ? .valid : .edit
        default:
            alert.alertStyle = .informational
            alert.addButton(withTitle: Localization.title("OK"))
            alert.runModal()
            return .valid
        }
    }

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
/// A color well of the Tab Color dialog: choosing a color unchecks its
/// "None" box.
final class TabColorWell: NSColorWell {
    weak var noneBox: NSButton?

    override var color: NSColor {
        didSet { noneBox?.state = .off }
    }
}

final class SheetTabControl: NSSegmentedControl {
    /// A tab dragged onto another's place: (from, to) segment indexes.
    var onReorder: ((Int, Int) -> Void)?

    private func segment(at point: NSPoint) -> Int? {
        var x: CGFloat = 0
        for segment in 0..<segmentCount {
            let width = self.width(forSegment: segment) > 0 ? self.width(forSegment: segment)
                : bounds.width / CGFloat(max(segmentCount, 1))
            if point.x >= x && point.x < x + width { return segment }
            x += width
        }
        return nil
    }

    /// A press selects the tab; a drag of more than a few points moves it
    /// to where it is let go (the GTK notebook's tab reordering).
    override func mouseDown(with event: NSEvent) {
        guard let from = segment(at: convert(event.locationInWindow, from: nil)), let window else {
            super.mouseDown(with: event)
            return
        }
        var dragged = false
        var last = event
        while true {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            last = next
            if next.type == .leftMouseUp { break }
            if abs(next.locationInWindow.x - event.locationInWindow.x) > 4 { dragged = true }
        }
        if dragged, let to = segment(at: convert(last.locationInWindow, from: nil)), to != from {
            onReorder?(from, to)
        } else if selectedSegment != from {
            selectedSegment = from
            sendAction(action, to: target)
        }
    }

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

/// The grid's scroll view: its scrollers stay visible, as the GTK's
/// scrollbars do, whatever the system's scroller setting (AppKit sets the
/// preferred style on every scroll view when that setting changes).
final class GridScrollView: NSScrollView {
    override var scrollerStyle: NSScroller.Style {
        get { .legacy }
        set { super.scrollerStyle = .legacy }
    }
}
