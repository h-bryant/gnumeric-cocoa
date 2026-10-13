import AppKit
import GnmCocoa

/// The chart editor as a sheet (the GTK guru's later pages): the graph's
/// object tree on the left with Add, Remove, and reorder buttons, a live
/// preview of the working copy on the right, and below it the selected
/// object's data, properties, and style.  Every edit goes to the copy at
/// once and shows in the preview; Apply commits it as "Reconfigure Graph".
@MainActor
final class ChartEditorWindow: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate {
    let window: NSWindow
    let editor: ChartEditor
    private let outline = NSOutlineView()
    private let preview: PreviewView
    private let addButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let removeButton = NSButton(title: Localization.title("Remove"), target: nil, action: nil)
    private let upButton = NSButton(title: Localization.title("↑"), target: nil, action: nil)
    private let downButton = NSButton(title: Localization.title("↓"), target: nil, action: nil)
    private let formScroll = NSScrollView()
    private let form = NSStackView()
    private var handlers: [NSControl: () -> Void] = [:]
    private var endEditingHandlers: [NSTextField: (String) -> Void] = [:]
    private var style: ChartStyle?
    private var completion: ((Bool) -> Void)?
    private var typePicker: ChartGuru?

    init(editor: ChartEditor) {
        self.editor = editor
        preview = PreviewView(editor: editor)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 640),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.title = "Chart Properties"
        window.minSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false   // closed below, released with this object
        super.init()
        build()
    }

    // MARK: Building

    private func build() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("object"))
        column.title = "Object"
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.dataSource = self
        outline.delegate = self
        outline.rowHeight = 22
        outline.allowsEmptySelection = false
        outline.style = .inset
        let outlineScroll = NSScrollView()
        outlineScroll.documentView = outline
        outlineScroll.hasVerticalScroller = true
        outlineScroll.borderType = .bezelBorder
        outlineScroll.translatesAutoresizingMaskIntoConstraints = false

        addButton.addItem(withTitle: "Add")
        addButton.menu?.delegate = self
        removeButton.target = self
        removeButton.action = #selector(removePressed(_:))
        upButton.target = self
        upButton.action = #selector(upPressed(_:))
        downButton.target = self
        downButton.action = #selector(downPressed(_:))
        upButton.toolTip = "Move up"
        downButton.toolTip = "Move down"
        let treeButtons = NSStackView(views: [addButton, removeButton, upButton, downButton])
        treeButtons.orientation = .horizontal
        treeButtons.spacing = 6
        let left = NSStackView(views: [outlineScroll, treeButtons])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 8
        left.translatesAutoresizingMaskIntoConstraints = false
        left.widthAnchor.constraint(equalToConstant: 260).isActive = true

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.heightAnchor.constraint(equalToConstant: 250).isActive = true
        preview.wantsLayer = true
        preview.layer?.borderWidth = 1
        preview.layer?.borderColor = NSColor.separatorColor.cgColor

        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 10
        form.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        form.translatesAutoresizingMaskIntoConstraints = false
        let formHost = FlippedView()
        formHost.translatesAutoresizingMaskIntoConstraints = false
        formHost.addSubview(form)
        formScroll.documentView = formHost
        formScroll.hasVerticalScroller = true
        formScroll.borderType = .bezelBorder
        formScroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: formHost.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: formHost.trailingAnchor),
            form.topAnchor.constraint(equalTo: formHost.topAnchor),
            form.bottomAnchor.constraint(equalTo: formHost.bottomAnchor),
            formHost.widthAnchor.constraint(equalTo: formScroll.contentView.widthAnchor),
        ])
        let right = NSStackView(views: [preview, formScroll])
        right.orientation = .vertical
        right.spacing = 8
        right.translatesAutoresizingMaskIntoConstraints = false

        let panes = NSStackView(views: [left, right])
        panes.orientation = .horizontal
        panes.spacing = 12
        panes.distribution = .fill
        panes.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            outlineScroll.widthAnchor.constraint(equalTo: left.widthAnchor),
            preview.widthAnchor.constraint(equalTo: right.widthAnchor),
            formScroll.widthAnchor.constraint(equalTo: right.widthAnchor),
            left.heightAnchor.constraint(equalTo: panes.heightAnchor),
            right.heightAnchor.constraint(equalTo: panes.heightAnchor),
            outlineScroll.heightAnchor.constraint(equalTo: left.heightAnchor, constant: -40),
        ])

        let cancel = NSButton(title: Localization.title("Cancel"), target: self, action: #selector(cancelPressed(_:)))
        cancel.keyEquivalent = "\u{1b}"
        let apply = NSButton(title: Localization.title("Apply"), target: self, action: #selector(applyPressed(_:)))
        apply.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), cancel, apply])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(panes)
        content.addSubview(buttons)
        NSLayoutConstraint.activate([
            panes.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            panes.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            panes.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            panes.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
        window.contentView = content
        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
        if let chart = editor.root.children.first {
            select(node: chart)
        } else {
            select(node: editor.root)
        }
    }

    // MARK: The tree

    var selectedNode: ChartNode? {
        outline.item(atRow: outline.selectedRow) as? ChartNode
    }

    func select(node: ChartNode) {
        var ancestors: [ChartNode] = []
        var parent = node.parent
        while let p = parent {
            ancestors.append(p)
            parent = p.parent
        }
        for ancestor in ancestors.reversed() {
            outline.expandItem(ancestor)
        }
        let row = outline.row(forItem: node)
        if row >= 0 {
            outline.selectRowIndexes([row], byExtendingSelection: false)
            outline.scrollRowToVisible(row)
        }
        rebuildForm()
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? ChartNode else { return 1 }
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? ChartNode else { return editor.root }
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? ChartNode)?.children.isEmpty == false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? ChartNode else { return nil }
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: node.name)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        rebuildForm()
    }

    private func reloadTree(selecting node: ChartNode?) {
        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
        if let node, node.isAttached {
            select(node: node)
        } else if outline.selectedRow < 0, outline.numberOfRows > 0 {
            outline.selectRowIndexes([0], byExtendingSelection: false)
            rebuildForm()
        } else {
            rebuildForm()
        }
    }

    private func changed() {
        preview.needsDisplay = true
    }

    @objc private func addRole(_ sender: NSMenuItem) {
        guard let node = selectedNode, let role = sender.representedObject as? String else { return }
        if let child = editor.addChild(role: role, to: node) {
            changed()
            reloadTree(selecting: child)
        }
    }

    @objc private func removePressed(_ sender: Any?) {
        guard let node = selectedNode, let parent = node.parent else { return }
        if editor.remove(node) {
            changed()
            reloadTree(selecting: parent)
        }
    }

    @objc private func upPressed(_ sender: Any?) { move(forward: true) }
    @objc private func downPressed(_ sender: Any?) { move(forward: false) }

    private func move(forward: Bool) {
        guard let node = selectedNode else { return }
        if editor.move(node, forward: forward) {
            changed()
            reloadTree(selecting: node)
        }
    }

    // MARK: The form

    private func rebuildForm() {
        handlers.removeAll()
        endEditingHandlers.removeAll()
        style = nil
        for view in form.arrangedSubviews {
            form.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        guard let node = selectedNode else {
            removeButton.isEnabled = false
            upButton.isEnabled = false
            downButton.isEnabled = false
            addButton.isEnabled = false
            return
        }
        removeButton.isEnabled = node.canDelete
        upButton.isEnabled = node.canMoveForward
        downButton.isEnabled = node.canMoveBackward
        addButton.isEnabled = !node.addableRoles.isEmpty

        let title = NSTextField(labelWithString: node.name)
        title.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        let subtitle = NSTextField(labelWithString: node.role.isEmpty ? node.typeName : "\(node.role) · \(node.typeName)")
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        form.addArrangedSubview(title)
        form.addArrangedSubview(subtitle)
        if node.role == "Plot" {
            let change = NSButton(title: Localization.title("Change Type…"), target: self, action: #selector(changeTypePressed(_:)))
            form.addArrangedSubview(change)
        }

        let dimensions = node.dimensions
        if !dimensions.isEmpty {
            form.addArrangedSubview(sectionLabel("Data"))
            var rows: [[NSView]] = []
            for dimension in dimensions {
                let field = NSTextField(string: dimension.text)
                field.placeholderString = dimension.kind == .scalar ? "Text or a cell" : "A range or a list"
                field.delegate = self
                field.translatesAutoresizingMaskIntoConstraints = false
                field.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
                endEditingHandlers[field] = { [weak self, weak field] text in
                    guard let self, let field else { return }
                    do {
                        try editor.setText(text, for: dimension, of: node)
                        field.stringValue = node.dimensions.first { $0.index == dimension.index }?.text ?? text
                        changed()
                        if dimension.index == -1 { outline.reloadItem(node) }
                    } catch {
                        field.stringValue = dimension.text
                        let alert = NSAlert(error: error)
                        alert.runModal()
                    }
                }
                rows.append([NSTextField(labelWithString: dimension.label + ":"), field])
            }
            form.addArrangedSubview(grid(rows))
        }

        let properties = node.properties
        if !properties.isEmpty {
            form.addArrangedSubview(sectionLabel("Properties"))
            var rows: [[NSView]] = []
            for property in properties {
                rows.append([NSTextField(labelWithString: property.label + ":"), control(for: property, of: node)])
            }
            form.addArrangedSubview(grid(rows))
        }

        if let nodeStyle = node.style {
            style = nodeStyle
            buildStyleSection(nodeStyle, node: node)
        }
        form.layoutSubtreeIfNeeded()
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        return label
    }

    private func grid(_ rows: [[NSView]]) -> NSGridView {
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false
        return grid
    }

    private func control(for property: ChartProperty, of node: ChartNode) -> NSView {
        switch property.kind {
        case .boolean:
            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(controlChanged(_:)))
            check.state = (property.value as? NSNumber)?.boolValue == true ? .on : .off
            handlers[check] = { [weak self, weak check] in
                guard let self, let check else { return }
                if editor.setValue(NSNumber(value: check.state == .on), for: property, of: node) { changed() }
            }
            return check
        case .integer, .number:
            let field = NSTextField(string: "")
            let formatter = NumberFormatter()
            formatter.minimum = NSNumber(value: property.minimum)
            formatter.maximum = NSNumber(value: property.maximum)
            formatter.allowsFloats = property.kind == .number
            formatter.maximumFractionDigits = 4
            field.formatter = formatter
            if let number = property.value as? NSNumber {
                field.stringValue = formatter.string(from: number) ?? number.stringValue
            }
            field.delegate = self
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 90).isActive = true
            endEditingHandlers[field] = { [weak self] text in
                guard let self, let number = formatter.number(from: text) ?? Double(text).map({ NSNumber(value: $0) }) else { return }
                if editor.setValue(number, for: property, of: node) { changed() }
            }
            return field
        case .text:
            let field = NSTextField(string: (property.value as? String) ?? "")
            field.delegate = self
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
            endEditingHandlers[field] = { [weak self] text in
                guard let self else { return }
                if editor.setValue(text as NSString, for: property, of: node) { changed() }
            }
            return field
        case .choice:
            let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
            for (choice, label) in zip(property.choices, property.choiceLabels) {
                popUp.addItem(withTitle: label)
                popUp.lastItem?.representedObject = choice
            }
            if let current = property.value as? String, let index = property.choices.firstIndex(of: current) {
                popUp.selectItem(at: index)
            }
            popUp.target = self
            popUp.action = #selector(controlChanged(_:))
            handlers[popUp] = { [weak self, weak popUp] in
                guard let self, let choice = popUp?.selectedItem?.representedObject as? String else { return }
                if editor.setValue(choice as NSString, for: property, of: node) { changed() }
            }
            return popUp
        @unknown default:
            return NSTextField(labelWithString: String(describing: property.value ?? ""))
        }
    }

    private func buildStyleSection(_ style: ChartStyle, node: ChartNode) {
        // A closure, not a nested function: the handlers below keep it, and
        // a nested function would hold `self` strongly (a cycle through
        // `handlers`).
        let apply: () -> Void = { [weak self] in
            guard let self, let current = self.style else { return }
            if editor.apply(current, to: node) { changed() }
        }
        func automatic(_ title: String, _ get: @escaping (ChartStyle) -> Bool, _ set: @escaping (ChartStyle, Bool) -> Void) -> NSButton {
            let check = NSButton(checkboxWithTitle: title, target: self, action: #selector(controlChanged(_:)))
            check.state = get(style) ? .on : .off
            handlers[check] = { [weak self, weak check] in
                guard let self, let check, let current = self.style else { return }
                set(current, check.state == .on)
                apply()
            }
            return check
        }
        func well(_ color: CGColor?, _ set: @escaping (ChartStyle, CGColor?) -> Void) -> NSColorWell {
            let well = NSColorWell(frame: NSRect(x: 0, y: 0, width: 44, height: 22))
            well.translatesAutoresizingMaskIntoConstraints = false
            well.widthAnchor.constraint(equalToConstant: 44).isActive = true
            well.heightAnchor.constraint(equalToConstant: 22).isActive = true
            if let color, let ns = NSColor(cgColor: color) { well.color = ns }
            well.target = self
            well.action = #selector(controlChanged(_:))
            handlers[well] = { [weak self, weak well] in
                guard let self, let well, let current = self.style else { return }
                set(current, well.color.cgColor)
                apply()
            }
            return well
        }
        func number(_ value: Double, width: CGFloat = 60, _ set: @escaping (ChartStyle, Double) -> Void) -> NSTextField {
            let field = NSTextField(string: String(format: value == value.rounded() ? "%.0f" : "%.2f", value))
            field.delegate = self
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: width).isActive = true
            endEditingHandlers[field] = { [weak self] text in
                guard let self, let current = self.style, let v = Double(text) else { return }
                set(current, v)
                apply()
            }
            return field
        }
        func popUp(_ names: [String], selected: Int, _ set: @escaping (ChartStyle, Int) -> Void) -> NSPopUpButton {
            let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
            popUp.addItems(withTitles: names)
            popUp.selectItem(at: max(0, min(selected, names.count - 1)))
            popUp.target = self
            popUp.action = #selector(controlChanged(_:))
            handlers[popUp] = { [weak self, weak popUp] in
                guard let self, let popUp, let current = self.style else { return }
                set(current, popUp.indexOfSelectedItem)
                apply()
            }
            return popUp
        }
        func row(_ views: [NSView]) -> NSStackView {
            let stack = NSStackView(views: views)
            stack.orientation = .horizontal
            stack.spacing = 8
            return stack
        }

        form.addArrangedSubview(sectionLabel("Style"))
        var rows: [[NSView]] = []
        if style.hasLine || style.hasOutline {
            let visible = NSButton(checkboxWithTitle: "Visible", target: self, action: #selector(controlChanged(_:)))
            visible.state = style.lineColor != nil ? .on : .off
            let color = well(style.lineColor ?? NSColor.black.cgColor) { $0.lineColor = $1 }
            handlers[visible] = { [weak self, weak visible, weak color] in
                guard let self, let visible, let current = self.style else { return }
                current.lineAutomatic = false
                current.lineColor = visible.state == .on ? color?.color.cgColor : nil
                apply()
            }
            rows.append([NSTextField(labelWithString: (style.hasLine ? "Line" : "Outline") + ":"),
                         row([automatic("Automatic", { $0.lineAutomatic }, { $0.lineAutomatic = $1 }), visible, color,
                              NSTextField(labelWithString: "Width:"), number(style.lineWidth) { $0.lineAutomatic = false; $0.lineWidth = $1 },
                              popUp(ChartStyle.lineDashNames, selected: style.lineDash) { $0.lineAutomatic = false; $0.lineDash = $1 }])])
        }
        if style.hasFill {
            let filled = automatic("Filled", { $0.fillSolid }, { $0.fillAutomatic = false; $0.fillSolid = $1 })
            rows.append([NSTextField(labelWithString: "Fill:"),
                         row([automatic("Automatic", { $0.fillAutomatic }, { $0.fillAutomatic = $1 }), filled,
                              well(style.fillColor) { $0.fillAutomatic = false; $0.fillSolid = true; $0.fillColor = $1 }])])
        }
        if style.hasMarker {
            rows.append([NSTextField(labelWithString: "Marker:"),
                         row([automatic("Automatic", { $0.markerAutomatic }, { $0.markerAutomatic = $1 }),
                              popUp(ChartStyle.markerShapeNames, selected: style.markerShape) { $0.markerAutomatic = false; $0.markerShape = $1 },
                              NSTextField(labelWithString: "Size:"), number(Double(style.markerSize), width: 44) { $0.markerAutomatic = false; $0.markerSize = Int($1) },
                              NSTextField(labelWithString: "Fill:"), well(style.markerFillColor) { $0.markerAutomatic = false; $0.markerFillColor = $1 },
                              NSTextField(labelWithString: "Outline:"), well(style.markerOutlineColor) { $0.markerAutomatic = false; $0.markerOutlineColor = $1 }])])
        }
        if style.hasFont {
            let families = NSFontManager.shared.availableFontFamilies.sorted()
            var familyList = families
            if !style.fontFamily.isEmpty, !families.contains(style.fontFamily) {
                familyList.insert(style.fontFamily, at: 0)
            }
            let selected = familyList.firstIndex(of: style.fontFamily) ?? 0
            rows.append([NSTextField(labelWithString: "Font:"),
                         row([automatic("Automatic", { $0.fontAutomatic }, { $0.fontAutomatic = $1 }),
                              popUp(familyList, selected: selected) { $0.fontAutomatic = false; $0.fontFamily = familyList[$1] },
                              number(style.fontSize, width: 44) { $0.fontAutomatic = false; $0.fontSize = $1 },
                              automatic("Bold", { $0.fontBold }, { $0.fontAutomatic = false; $0.fontBold = $1 }),
                              automatic("Italic", { $0.fontItalic }, { $0.fontAutomatic = false; $0.fontItalic = $1 })])])
            rows.append([NSTextField(labelWithString: "Text color:"),
                         row([automatic("Automatic", { $0.fontColorAutomatic }, { $0.fontColorAutomatic = $1 }),
                              well(style.fontColor) { $0.fontColorAutomatic = false; $0.fontColor = $1 }])])
        }
        if style.hasTextLayout {
            rows.append([NSTextField(labelWithString: "Angle:"),
                         row([automatic("Automatic", { $0.textAngleAutomatic }, { $0.textAngleAutomatic = $1 }),
                              number(style.textAngle, width: 50) { $0.textAngleAutomatic = false; $0.textAngle = $1 },
                              NSTextField(labelWithString: "degrees")])])
        }
        form.addArrangedSubview(grid(rows))
    }

    @objc private func controlChanged(_ sender: NSControl) {
        handlers[sender]?()
    }

    /// The guru's type page over the selected plot: the series come along.
    @objc private func changeTypePressed(_ sender: Any?) {
        guard let node = selectedNode, node.role == "Plot", typePicker == nil else { return }
        let picker = ChartGuru(typeOnly: true, preselecting: node.typeName)
        typePicker = picker
        picker.run(in: window) { [weak self] choice in
            guard let self else { return }
            typePicker = nil
            if let choice {
                changePlotType(to: choice.type)
            }
        }
    }

    /// Replace the selected plot with one of `type` (also the headless checks).
    @discardableResult
    func changePlotType(to type: PlotType) -> ChartNode? {
        guard let node = selectedNode, node.role == "Plot", let plot = editor.changeType(type, ofPlot: node) else { return nil }
        changed()
        reloadTree(selecting: plot)
        return plot
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        endEditingHandlers[field]?(field.stringValue)
    }

    // MARK: Scripted edits (the headless checks)

    /// Commit text into a field the way Enter would.
    func setText(_ text: String, forDimensionLabeled label: String) {
        guard let node = selectedNode, let dimension = node.dimensions.first(where: { $0.label == label }) else { return }
        try? editor.setText(text, for: dimension, of: node)
        changed()
        rebuildForm()
    }

    func setProperty(named name: String, to value: Any) {
        guard let node = selectedNode, let property = node.properties.first(where: { $0.name == name }) else { return }
        if editor.setValue(value, for: property, of: node) {
            changed()
            rebuildForm()
        }
    }

    func addChild(role: String) -> ChartNode? {
        guard let node = selectedNode, let child = editor.addChild(role: role, to: node) else { return nil }
        changed()
        reloadTree(selecting: child)
        return child
    }

    // MARK: Running

    func run(in parent: NSWindow, completion: @escaping @MainActor (Bool) -> Void) {
        self.completion = completion
        parent.beginSheet(window) { _ in }
    }

    private func finish(_ applied: Bool) {
        guard let parent = window.sheetParent else { return }
        NSColorPanel.shared.orderOut(nil)
        parent.endSheet(window)
        window.close()   // out of the app's window list, so the copy goes with this object
        let completion = self.completion
        self.completion = nil
        completion?(applied)
    }

    @objc private func cancelPressed(_ sender: Any?) {
        finish(false)
    }

    /// Close without applying (the headless checks).
    func cancel() {
        finish(false)
    }

    /// Apply and close, as the button does (the headless checks).
    func apply() {
        applyPressed(nil)
    }

    @objc private func applyPressed(_ sender: Any?) {
        window.makeFirstResponder(nil)   // commit a field still being edited
        do {
            try editor.apply()
            finish(true)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// The working copy, drawn by the engine.
    final class PreviewView: NSView {
        private let editor: ChartEditor
        init(editor: ChartEditor) {
            self.editor = editor
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            NSColor.white.setFill()
            bounds.fill()
            editor.drawPreview(in: context, size: bounds.size)
        }
    }

    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }
}

extension ChartEditorWindow: NSMenuDelegate {
    /// The Add pull-down lists the selected object's addable roles.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === addButton.menu else { return }
        while menu.items.count > 1 {
            menu.removeItem(at: 1)
        }
        for role in selectedNode?.addableRoles ?? [] {
            let item = NSMenuItem(title: role, action: #selector(addRole(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = role
            menu.addItem(item)
        }
    }
}
