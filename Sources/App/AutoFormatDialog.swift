import AppKit
import GnmCocoa

/// The AutoFormat dialog (dialog-autoformat.c) as a sheet window: a
/// category pop-up, the category's templates in a list, the chosen one
/// drawn over the GTK's demo table, its name, author, and description,
/// and the Settings menu's parts and edges as checkboxes.
@MainActor
final class AutoFormatDialog: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let window: NSWindow
    private let engine: Engine
    private let categoryPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let table = NSTableView()
    private let preview = AutoFormatPreview()
    private let info = NSTextField(wrappingLabelWithString: "")
    private var partBoxes: [(NSButton, WritableKeyPath<AutoFormatTemplate, Bool>)] = []
    private let status = NSTextField(labelWithString: "")
    private(set) var categories: [AutoFormatCategory] = []
    private(set) var templates: [AutoFormatTemplate] = []
    private var completion: (@MainActor (AutoFormatTemplate?) -> Void)?

    init(engine: Engine) {
        self.engine = engine
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = Localization.title("AutoFormat")
        window.isReleasedWhenClosed = false
        super.init()
        build()
        categories = engine.autoFormatCategories
        categoryPopUp.removeAllItems()
        categoryPopUp.addItems(withTitles: categories.map(\.name))
        if categories.isEmpty { status.stringValue = "An error occurred while reading the category list" }
        loadTemplates()
    }

    private func build() {
        categoryPopUp.target = self
        categoryPopUp.action = #selector(categoryChanged(_:))
        let categoryRow = NSStackView(views: [NSTextField(labelWithString: Localization.title("Category:")), categoryPopUp, NSView()])
        categoryRow.orientation = .horizontal
        categoryRow.spacing = 8

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = "Template"
        column.width = 200
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = true
        table.allowsEmptySelection = false
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.widthAnchor.constraint(equalToConstant: 220).isActive = true

        preview.widthAnchor.constraint(equalToConstant: AutoFormatPreview.cellWidth * CGFloat(AutoFormatTemplate.previewColumns) + 2).isActive = true
        preview.heightAnchor.constraint(equalToConstant: AutoFormatPreview.cellHeight * CGFloat(AutoFormatTemplate.previewRows) + 2).isActive = true
        info.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        info.textColor = .secondaryLabelColor
        info.maximumNumberOfLines = 6
        let parts: [(String, WritableKeyPath<AutoFormatTemplate, Bool>)] = [
            ("Number", \.appliesNumberFormat), ("Border", \.appliesBorders), ("Font", \.appliesFont),
            ("Patterns", \.appliesPatterns), ("Alignment", \.appliesAlignment),
        ]
        let edges: [(String, WritableKeyPath<AutoFormatTemplate, Bool>)] = [
            ("Left", \.bordersLeftEdge), ("Right", \.bordersRightEdge), ("Top", \.bordersTopEdge), ("Bottom", \.bordersBottomEdge),
        ]
        func row(_ title: String, _ items: [(String, WritableKeyPath<AutoFormatTemplate, Bool>)]) -> NSStackView {
            var views: [NSView] = [NSTextField(labelWithString: title)]
            for (name, keyPath) in items {
                let box = NSButton(checkboxWithTitle: name, target: self, action: #selector(partToggled(_:)))
                box.state = .on
                partBoxes.append((box, keyPath))
                views.append(box)
            }
            views.append(NSView())
            let stack = NSStackView(views: views)
            stack.orientation = .horizontal
            stack.spacing = 8
            return stack
        }
        let previewColumn = NSStackView(views: [preview, info, row("Apply:", parts), row("Edges:", edges)])
        previewColumn.orientation = .vertical
        previewColumn.alignment = .leading
        previewColumn.spacing = 8
        let middle = NSStackView(views: [scroll, previewColumn])
        middle.orientation = .horizontal
        middle.alignment = .top
        middle.spacing = 12

        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.lineBreakMode = .byTruncatingTail
        let okButton = NSButton(title: Localization.title("OK"), target: self, action: #selector(apply(_:)))
        okButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: Localization.title("Cancel"), target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [status, NSView(), cancelButton, okButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let stack = NSStackView(views: [categoryRow, middle, buttons])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            content.widthAnchor.constraint(equalToConstant: 640),
        ])
        window.contentView = content
        window.initialFirstResponder = table
    }

    // MARK: Running

    /// `completion` gets the template chosen by OK, nil for Cancel.
    func run(in parent: NSWindow, completion: @escaping @MainActor (AutoFormatTemplate?) -> Void) {
        self.completion = completion
        parent.beginSheet(window) { _ in }
    }

    private func end(with template: AutoFormatTemplate?) {
        if let parent = window.sheetParent { parent.endSheet(window) }
        window.close()
        let completion = self.completion
        self.completion = nil
        completion?(template)
    }

    @objc func apply(_ sender: Any?) { end(with: selectedTemplate) }
    @objc func cancel(_ sender: Any?) { end(with: nil) }

    // MARK: The lists

    var selectedTemplate: AutoFormatTemplate? {
        let row = table.selectedRow
        return row >= 0 && row < templates.count ? templates[row] : nil
    }

    func selectCategory(named name: String) {
        guard let index = categories.firstIndex(where: { $0.name == name }) else { return }
        categoryPopUp.selectItem(at: index)
        loadTemplates()
    }

    func select(row: Int) {
        guard row >= 0, row < templates.count else { return }
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
        updatePreview()
    }

    func setPart(_ keyPath: WritableKeyPath<AutoFormatTemplate, Bool>, on: Bool) {
        guard let (box, _) = partBoxes.first(where: { $0.1 == keyPath }) else { return }
        box.state = on ? .on : .off
        partToggled(box)
    }

    @objc private func categoryChanged(_ sender: Any?) { loadTemplates() }

    private func loadTemplates() {
        let index = categoryPopUp.indexOfSelectedItem
        templates = index >= 0 && index < categories.count ? categories[index].templates : []
        table.reloadData()
        if !templates.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
        updatePreview()
    }

    private func updatePreview() {
        preview.template = selectedTemplate
        if let template = selectedTemplate {
            info.stringValue = "\(template.name) — \(template.author)\n\(template.summary)"
            for (box, keyPath) in partBoxes { box.state = template[keyPath: keyPath] ? .on : .off }
        } else {
            info.stringValue = templates.isEmpty ? "No templates in this category." : ""
        }
    }

    @objc private func partToggled(_ sender: NSButton) {
        // cb_check_item_toggled: the setting applies to every template listed
        guard let (_, keyPath) = partBoxes.first(where: { $0.0 === sender }) else { return }
        for var template in templates { template[keyPath: keyPath] = sender.state == .on }
        preview.needsDisplay = true
    }

    func numberOfRows(in tableView: NSTableView) -> Int { templates.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, row < templates.count else { return nil }
        let cell = (tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NSTableCellView) ?? {
            let view = NSTableCellView()
            view.identifier = tableColumn.identifier
            let field = NSTextField(labelWithString: "")
            field.lineBreakMode = .byTruncatingTail
            field.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(field)
            view.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
                field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2),
                field.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
            return view
        }()
        cell.textField?.stringValue = templates[row].name
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updatePreview()
    }
}

/// The GTK preview grid: the demo table drawn with the template's
/// styles, fills, fonts, alignment, and borders.
@MainActor
final class AutoFormatPreview: NSView {
    static let cellWidth: CGFloat = 60
    static let cellHeight: CGFloat = 20
    static let demoTable = [
        [" ", "Jan", "Feb", "Mar", "Total"],
        ["North", "6", "13", "20", "39"],
        ["South", "12", "4", "17", "33"],
        ["West", "8", "2", "0", "10"],
        ["Total", "26", "19", "37", "81"],
    ]
    var template: AutoFormatTemplate? { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let rows = AutoFormatTemplate.previewRows, columns = AutoFormatTemplate.previewColumns
        let w = Self.cellWidth, h = Self.cellHeight
        for row in 0..<rows {
            for column in 0..<columns {
                let rect = NSRect(x: 1 + CGFloat(column) * w, y: 1 + CGFloat(row) * h, width: w, height: h)
                let text = Self.demoTable[row][column]
                let isNumber = Double(text) != nil
                var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.black]
                var alignment: NSTextAlignment = isNumber ? .right : .left
                if let template {
                    let format = template.previewFormat(atRow: row, column: column)
                    if format.fillsBackground?.boolValue == true, let color = format.backgroundColor, let fill = NSColor(cgColor: color) {
                        fill.setFill()
                        rect.fill()
                    }
                    var font = NSFont.systemFont(ofSize: CGFloat(format.fontSize?.doubleValue ?? 11).clamped(to: 7...14))
                    var traits: NSFontTraitMask = []
                    if format.bold?.boolValue == true { traits.insert(.boldFontMask) }
                    if format.italic?.boolValue == true { traits.insert(.italicFontMask) }
                    if !traits.isEmpty { font = NSFontManager.shared.convert(font, toHaveTrait: traits) }
                    attributes[.font] = font
                    if let color = format.textColor, let text = NSColor(cgColor: color) { attributes[.foregroundColor] = text }
                    switch format.horizontalAlignment?.intValue {
                    case 0x02: alignment = .left
                    case 0x04: alignment = .right
                    case 0x08: alignment = .center
                    default: break
                    }
                }
                let size = (text as NSString).size(withAttributes: attributes)
                var x = rect.minX + 3
                if alignment == .right { x = rect.maxX - 3 - size.width } else if alignment == .center { x = rect.midX - size.width / 2 }
                (text as NSString).draw(at: NSPoint(x: x, y: rect.midY - size.height / 2), withAttributes: attributes)
                NSColor(white: 0.85, alpha: 1).setStroke()
                NSBezierPath(rect: rect).stroke()
            }
        }
        guard let template else { return }
        for row in 0..<rows {
            for column in 0..<columns {
                let rect = NSRect(x: 1 + CGFloat(column) * w, y: 1 + CGFloat(row) * h, width: w, height: h)
                let edges: [(AutoFormatTemplate.Edge, NSPoint, NSPoint)] = [
                    (.top, NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY)),
                    (.bottom, NSPoint(x: rect.minX, y: rect.maxY), NSPoint(x: rect.maxX, y: rect.maxY)),
                    (.left, NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.minX, y: rect.maxY)),
                    (.right, NSPoint(x: rect.maxX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.maxY)),
                ]
                for (edge, from, to) in edges {
                    let type = template.previewBorder(atRow: row, column: column, edge: edge)
                    guard type != 0 else { continue }
                    let color = template.previewBorderColor(atRow: row, column: column, edge: edge).flatMap { NSColor(cgColor: $0) } ?? .black
                    color.setStroke()
                    let path = NSBezierPath()
                    path.move(to: from)
                    path.line(to: to)
                    path.lineWidth = type == 5 || type == 2 ? 2 : 1   // thick and medium
                    if type == 3 || type == 4 { path.setLineDash([3, 2], count: 2, phase: 0) }   // dashed, dotted
                    path.stroke()
                }
            }
        }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}
