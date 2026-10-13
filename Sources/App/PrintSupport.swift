import AppKit
import GnmCocoa

/// A sheet's printed pages for `NSPrintOperation`: one page rect per
/// page, each drawn by the engine's page drawing (print.c) through the
/// bridge's job.  Flipped, in points, the pages stacked top to bottom.
@MainActor
final class PrintView: NSView {
    let job: PrintJob

    init(job: PrintJob) {
        self.job = job
        let size = job.pageSize
        super.init(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height * CGFloat(max(job.pageCount, 1))))
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: max(job.pageCount, 1))
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        let size = job.pageSize
        return NSRect(x: 0, y: size.height * CGFloat(page - 1), width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let size = job.pageSize
        let first = max(0, Int(floor(dirtyRect.minY / size.height)))
        let last = min(job.pageCount - 1, Int(floor((dirtyRect.maxY - 0.5) / size.height)))
        guard first <= last else { return }
        for page in first...last {
            context.saveGState()
            context.translateBy(x: 0, y: size.height * CGFloat(page))
            context.clip(to: CGRect(origin: .zero, size: size))
            job.drawPage(page, in: context)
            context.restoreGState()
        }
    }

    /// The print info matching the job's paper: our pages carry their own
    /// margins, headers, and footers.
    static func printInfo(for job: PrintJob, settings: PrintSettings) -> NSPrintInfo {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = job.pageSize
        info.orientation = job.pageSize.width > job.pageSize.height ? .landscape : .portrait
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.horizontalPagination = .clip
        info.verticalPagination = .clip
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        return info
    }
}

/// The GTK Page Setup dialog (dialog-printer-setup.c) as an alert sheet:
/// the paper and orientation, the margins in inches, the scaling, the
/// header and footer, what to print, and the repeated rows and columns.
@MainActor
final class PageSetupDialog: NSObject {
    /// For the headless checks: fill the fields and return true to apply.
    nonisolated(unsafe) static var headlessDriver: ((PageSetupDialog) -> Bool)?

    static let orientations: [PrintSettings.Orientation] = [.portrait, .landscape]

    let alert = NSAlert()
    let papers: [(name: String, display: String)]
    let paper = NSPopUpButton(frame: .zero, pullsDown: false)
    let orientation = NSPopUpButton(frame: .zero, pullsDown: false)
    let topField = NSTextField(string: "")
    let bottomField = NSTextField(string: "")
    let leftField = NSTextField(string: "")
    let rightField = NSTextField(string: "")
    let headerField = NSTextField(string: "")
    let footerField = NSTextField(string: "")
    let scaling = NSPopUpButton(frame: .zero, pullsDown: false)
    let percentField = NSTextField(string: "100")
    let fitColumnsField = NSTextField(string: "1")
    let fitRowsField = NSTextField(string: "1")
    let headerLeft = NSTextField(string: "")
    let headerMiddle = NSTextField(string: "")
    let headerRight = NSTextField(string: "")
    let footerLeft = NSTextField(string: "")
    let footerMiddle = NSTextField(string: "")
    let footerRight = NSTextField(string: "")
    let gridLines = NSButton(checkboxWithTitle: "Grid lines", target: nil, action: nil)
    let titles = NSButton(checkboxWithTitle: "Row and column headers", target: nil, action: nil)
    let blackAndWhite = NSButton(checkboxWithTitle: "Black and white", target: nil, action: nil)
    let centerH = NSButton(checkboxWithTitle: "Center horizontally", target: nil, action: nil)
    let centerV = NSButton(checkboxWithTitle: "Center vertically", target: nil, action: nil)
    let acrossThenDown = NSPopUpButton(frame: .zero, pullsDown: false)
    let repeatTopField = NSTextField(string: "")
    let repeatLeftField = NSTextField(string: "")
    let allSheets = NSButton(checkboxWithTitle: "Apply to all sheets", target: nil, action: nil)

    private static let pointsPerInch = 72.0

    init(settings: PrintSettings) {
        papers = PrintSettings.paperDisplayNames.map { (name: $0.key, display: $0.value) }.sorted { $0.display < $1.display }
        super.init()
        alert.messageText = "Page Setup"
        alert.addButton(withTitle: Localization.title("OK"))
        alert.addButton(withTitle: Localization.title("Cancel"))
        paper.addItems(withTitles: papers.map(\.display))
        if let index = papers.firstIndex(where: { $0.name == settings.paperName }) { paper.selectItem(at: index) }
        orientation.addItems(withTitles: ["Portrait", "Landscape"])
        orientation.selectItem(at: settings.orientation == .landscape || settings.orientation == .reverseLandscape ? 1 : 0)
        func inches(_ points: Double) -> String { String(format: "%.2f", points / Self.pointsPerInch) }
        topField.stringValue = inches(settings.topMargin)
        bottomField.stringValue = inches(settings.bottomMargin)
        leftField.stringValue = inches(settings.leftMargin)
        rightField.stringValue = inches(settings.rightMargin)
        headerField.stringValue = inches(settings.headerMargin)
        footerField.stringValue = inches(settings.footerMargin)
        scaling.addItems(withTitles: ["Percentage of normal size:", "Fit to pages across and down:"])
        scaling.selectItem(at: settings.scaling == .fitPages ? 1 : 0)
        percentField.stringValue = String(format: "%g", settings.scalePercentage)
        fitColumnsField.stringValue = String(settings.fitColumns)
        fitRowsField.stringValue = String(settings.fitRows)
        headerLeft.stringValue = settings.headerLeft
        headerMiddle.stringValue = settings.headerMiddle
        headerRight.stringValue = settings.headerRight
        footerLeft.stringValue = settings.footerLeft
        footerMiddle.stringValue = settings.footerMiddle
        footerRight.stringValue = settings.footerRight
        gridLines.state = settings.printsGridLines ? .on : .off
        titles.state = settings.printsTitles ? .on : .off
        blackAndWhite.state = settings.printsBlackAndWhite ? .on : .off
        centerH.state = settings.centersHorizontally ? .on : .off
        centerV.state = settings.centersVertically ? .on : .off
        acrossThenDown.addItems(withTitles: ["Down, then across", "Across, then down"])
        acrossThenDown.selectItem(at: settings.printsAcrossThenDown ? 1 : 0)
        repeatTopField.stringValue = settings.repeatTop
        repeatLeftField.stringValue = settings.repeatLeft
        for field in [topField, bottomField, leftField, rightField, headerField, footerField, percentField, fitColumnsField, fitRowsField] {
            field.widthAnchor.constraint(equalToConstant: 60).isActive = true
        }
        for field in [headerLeft, headerMiddle, headerRight, footerLeft, footerMiddle, footerRight] {
            field.widthAnchor.constraint(equalToConstant: 130).isActive = true
        }
        for field in [repeatTopField, repeatLeftField] {
            field.widthAnchor.constraint(equalToConstant: 100).isActive = true
        }
        alert.accessoryView = makeGrid()
    }

    private func makeGrid() -> NSGridView {
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.alignment = .right
            return field
        }
        func heading(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            return field
        }
        func row(_ views: [NSView]) -> NSStackView {
            let stack = NSStackView(views: views)
            stack.orientation = .horizontal
            stack.spacing = 6
            return stack
        }
        let rows: [[NSView]] = [
            [heading("Paper"), NSGridCell.emptyContentView],
            [label("Paper:"), paper], [label("Orientation:"), orientation],
            [heading("Margins (inches)"), NSGridCell.emptyContentView],
            [label("Top:"), row([topField, label("Bottom:"), bottomField])],
            [label("Left:"), row([leftField, label("Right:"), rightField])],
            [label("Header:"), row([headerField, label("Footer:"), footerField])],
            [heading("Scale"), NSGridCell.emptyContentView],
            [label("Scale:"), row([scaling, percentField, label("%")])],
            [label("Fit to:"), row([fitColumnsField, label("across by"), fitRowsField, label("down")])],
            [heading("Header and footer"), NSGridCell.emptyContentView],
            [label("Header:"), row([headerLeft, headerMiddle, headerRight])],
            [label("Footer:"), row([footerLeft, footerMiddle, footerRight])],
            [NSGridCell.emptyContentView, label("Codes: &[PAGE] &[PAGES] &[TAB] &[DATE] &[TIME] &[FILE] &[PATH]")],
            [heading("Sheet"), NSGridCell.emptyContentView],
            [NSGridCell.emptyContentView, row([gridLines, titles, blackAndWhite])],
            [NSGridCell.emptyContentView, row([centerH, centerV])],
            [label("Page order:"), acrossThenDown],
            [label("Repeat rows:"), row([repeatTopField, label("Repeat columns:"), repeatLeftField])],
            [NSGridCell.emptyContentView, allSheets],
        ]
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        for index in 0..<grid.numberOfRows { grid.row(at: index).yPlacement = .center }
        for (index, row) in rows.enumerated() where row[1] === NSGridCell.emptyContentView && row[0] is NSTextField {
            grid.cell(atColumnIndex: 0, rowIndex: index).xPlacement = .leading
            grid.row(at: index).topPadding = index == 0 ? 0 : 8
        }
        let size = grid.fittingSize
        grid.frame = NSRect(x: 0, y: 0, width: max(size.width, 480), height: size.height)
        return grid
    }

    /// The settings as the fields describe them.
    func makeSettings(from base: PrintSettings) -> PrintSettings {
        let settings = base.copy() as! PrintSettings
        if paper.indexOfSelectedItem >= 0, paper.indexOfSelectedItem < papers.count {
            settings.paperName = papers[paper.indexOfSelectedItem].name
        }
        settings.orientation = Self.orientations[max(0, orientation.indexOfSelectedItem)]
        func points(_ field: NSTextField, _ fallback: Double) -> Double {
            (Double(field.stringValue).map { $0 * Self.pointsPerInch }) ?? fallback
        }
        settings.topMargin = points(topField, base.topMargin)
        settings.bottomMargin = points(bottomField, base.bottomMargin)
        settings.leftMargin = points(leftField, base.leftMargin)
        settings.rightMargin = points(rightField, base.rightMargin)
        settings.headerMargin = points(headerField, base.headerMargin)
        settings.footerMargin = points(footerField, base.footerMargin)
        settings.scaling = scaling.indexOfSelectedItem == 1 ? .fitPages : .percentage
        settings.scalePercentage = Double(percentField.stringValue) ?? 100
        settings.fitColumns = Int(fitColumnsField.stringValue) ?? 0
        settings.fitRows = Int(fitRowsField.stringValue) ?? 0
        settings.headerLeft = headerLeft.stringValue
        settings.headerMiddle = headerMiddle.stringValue
        settings.headerRight = headerRight.stringValue
        settings.footerLeft = footerLeft.stringValue
        settings.footerMiddle = footerMiddle.stringValue
        settings.footerRight = footerRight.stringValue
        settings.printsGridLines = gridLines.state == .on
        settings.printsTitles = titles.state == .on
        settings.printsBlackAndWhite = blackAndWhite.state == .on
        settings.centersHorizontally = centerH.state == .on
        settings.centersVertically = centerV.state == .on
        settings.printsAcrossThenDown = acrossThenDown.indexOfSelectedItem == 1
        settings.repeatTop = repeatTopField.stringValue
        settings.repeatLeft = repeatLeftField.stringValue
        return settings
    }

    /// Present as a sheet; `apply` gets the settings and whether every
    /// sheet takes them, and returns whether they were accepted.
    func present(in window: NSWindow, base: PrintSettings, apply: @escaping (PrintSettings, Bool) -> Bool) {
        if let driver = Self.headlessDriver {
            if driver(self) { _ = apply(makeSettings(from: base), allSheets.state == .on) }
            return
        }
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn else { return }
            if !apply(makeSettings(from: base), allSheets.state == .on) {
                DispatchQueue.main.async { [self] in present(in: window, base: base, apply: apply) }
            }
        }
    }
}
