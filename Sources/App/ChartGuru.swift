import AppKit
import GnmCocoa

/// The chart guru as a sheet: goffice's plot families on the left, the
/// family's types with their sample images on the right, the description
/// of the chosen type, and the GTK guru's two options (series as rows or
/// columns, a shared abscissa).  The chart's series come from the
/// selection when the sheet inserts it.
@MainActor
final class ChartGuru: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    struct Choice {
        let type: PlotType
        let layout: ChartSeriesLayout
        let sharedAbscissa: Bool
    }

    let window: NSWindow
    private let families: [String]
    private let typesByFamily: [String: [PlotType]]
    private let familyTable = NSTableView()
    private let typeTable = NSTableView()
    private let summary = NSTextField(wrappingLabelWithString: "")
    private let layout = NSPopUpButton(frame: .zero, pullsDown: false)
    private let shared = NSButton(checkboxWithTitle: Localization.title("Use the first series as the shared abscissa"), target: nil, action: nil)
    private let insertButton = NSButton(title: Localization.title("Insert"), target: nil, action: nil)
    private var images: [String: NSImage] = [:]
    private var completion: ((Choice?) -> Void)?

    /// Only the type: the chart editor's "Change Type…" (no series options).
    private let typeOnly: Bool
    private let preselectedEngine: String?

    override convenience init() {
        self.init(typeOnly: false, preselecting: nil)
    }

    init(typeOnly: Bool, preselecting engine: String?) {
        self.typeOnly = typeOnly
        self.preselectedEngine = engine
        var families: [String] = []
        var byFamily: [String: [PlotType]] = [:]
        for type in PlotType.allTypes {
            if byFamily[type.family] == nil {
                families.append(type.family)
                byFamily[type.family] = []
            }
            byFamily[type.family]?.append(type)
        }
        self.families = families
        self.typesByFamily = byFamily
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 460),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = typeOnly ? "Change Plot Type" : "Insert Chart"
        window.isReleasedWhenClosed = false   // closed below, released with this object
        super.init()
        build()
        if let engine = preselectedEngine, let family = families.first(where: { byFamily[$0]?.contains { $0.engine == engine } == true }),
           let familyRow = families.firstIndex(of: family) {
            familyTable.selectRowIndexes([familyRow], byExtendingSelection: false)
            reloadTypes()
            if let typeRow = byFamily[family]?.firstIndex(where: { $0.engine == engine }) {
                typeTable.selectRowIndexes([typeRow], byExtendingSelection: false)
                updateSummary()
            }
        }
    }

    private var selectedFamily: String? {
        familyTable.selectedRow >= 0 && familyTable.selectedRow < families.count ? families[familyTable.selectedRow] : nil
    }

    private var selectedType: PlotType? {
        guard let family = selectedFamily, let types = typesByFamily[family],
              typeTable.selectedRow >= 0, typeTable.selectedRow < types.count else { return nil }
        return types[typeTable.selectedRow]
    }

    private func build() {
        func scrolled(_ table: NSTableView, columnTitle: String, width: CGFloat) -> NSScrollView {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(columnTitle))
            column.title = columnTitle
            column.width = width - 20
            table.addTableColumn(column)
            table.headerView = nil
            table.dataSource = self
            table.delegate = self
            table.allowsEmptySelection = false
            table.style = .inset
            let scroll = NSScrollView()
            scroll.documentView = table
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            scroll.translatesAutoresizingMaskIntoConstraints = false
            scroll.widthAnchor.constraint(equalToConstant: width).isActive = true
            return scroll
        }
        familyTable.rowHeight = 22
        typeTable.rowHeight = 60
        typeTable.target = self
        typeTable.doubleAction = #selector(insertPressed(_:))
        let familyScroll = scrolled(familyTable, columnTitle: "Family", width: 180)
        let typeScroll = scrolled(typeTable, columnTitle: "Type", width: 440)
        let tables = NSStackView(views: [familyScroll, typeScroll])
        tables.orientation = .horizontal
        tables.spacing = 8
        tables.heightAnchor.constraint(equalToConstant: 300).isActive = true

        summary.preferredMaxLayoutWidth = 620
        summary.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        layout.addItem(withTitle: Localization.title("Auto"))
        layout.addItem(withTitle: Localization.title("Columns"))
        layout.addItem(withTitle: Localization.title("Rows"))
        let options = NSStackView(views: [NSTextField(labelWithString: Localization.title("Series as:")), layout, shared])
        options.orientation = .horizontal
        options.spacing = 8
        options.isHidden = typeOnly

        let cancel = NSButton(title: Localization.title("Cancel"), target: self, action: #selector(cancelPressed(_:)))
        cancel.keyEquivalent = "\u{1b}"
        insertButton.title = typeOnly ? "Change" : "Insert"
        insertButton.target = self
        insertButton.action = #selector(insertPressed(_:))
        insertButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), cancel, insertButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.distribution = .gravityAreas

        let column = NSStackView(views: [tables, summary, options, buttons])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 12
        column.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        column.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            column.topAnchor.constraint(equalTo: content.topAnchor),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            buttons.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -20),
            summary.widthAnchor.constraint(equalTo: tables.widthAnchor),
        ])
        window.contentView = content
        familyTable.reloadData()
        if !families.isEmpty {
            familyTable.selectRowIndexes([0], byExtendingSelection: false)
        }
        reloadTypes()
    }

    private func reloadTypes() {
        typeTable.reloadData()
        if typeTable.numberOfRows > 0 {
            typeTable.selectRowIndexes([0], byExtendingSelection: false)
        }
        updateSummary()
    }

    private func updateSummary() {
        summary.stringValue = selectedType?.summary ?? ""
        insertButton.isEnabled = selectedType != nil
    }

    private func image(for type: PlotType) -> NSImage? {
        let key = type.engine + "/" + type.name
        if let cached = images[key] { return cached }
        guard let data = type.sampleImageData, let image = NSImage(data: data) else { return nil }
        images[key] = image
        return image
    }

    // MARK: Tables

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === familyTable ? families.count : (selectedFamily.flatMap { typesByFamily[$0]?.count } ?? 0)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === familyTable {
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: families[row])
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }
        guard let family = selectedFamily, let type = typesByFamily[family]?[row] else { return nil }
        let cell = NSTableCellView()
        let imageView = NSImageView()
        imageView.image = image(for: type)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: type.name)
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(imageView)
        cell.addSubview(label)
        cell.imageView = imageView
        cell.textField = label
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 52),
            imageView.heightAnchor.constraint(equalToConstant: 52),
            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if (notification.object as? NSTableView) === familyTable {
            reloadTypes()
        } else {
            updateSummary()
        }
    }

    // MARK: Running

    func run(in parent: NSWindow, completion: @escaping @MainActor (Choice?) -> Void) {
        self.completion = completion
        parent.beginSheet(window) { _ in }
    }

    private func finish(_ choice: Choice?) {
        guard let parent = window.sheetParent else { return }
        parent.endSheet(window)
        window.close()   // out of the app's window list
        let completion = self.completion
        self.completion = nil
        completion?(choice)
    }

    @objc private func cancelPressed(_ sender: Any?) {
        finish(nil)
    }

    /// Close without a choice (the headless checks).
    func cancel() {
        finish(nil)
    }

    @objc private func insertPressed(_ sender: Any?) {
        guard let type = selectedType else { return }
        let layouts: [ChartSeriesLayout] = [.auto, .columns, .rows]
        finish(Choice(type: type, layout: layouts[max(layout.indexOfSelectedItem, 0)], sharedAbscissa: shared.state == .on))
    }
}
