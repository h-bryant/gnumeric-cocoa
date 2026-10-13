import AppKit
import GnmCocoa

/// Format → Workbook… (dialog-workbook-attr.c) as an alert sheet: the
/// view's attributes as checkboxes, applied at once on OK.
@MainActor
final class WorkbookAttributesDialog {
    nonisolated(unsafe) static var headlessDriver: ((WorkbookAttributesDialog) -> Bool)?

    let alert = NSAlert()
    let horizontalScrollbar = NSButton(checkboxWithTitle: Localization.title("Horizontal scrollbar"), target: nil, action: nil)
    let verticalScrollbar = NSButton(checkboxWithTitle: Localization.title("Vertical scrollbar"), target: nil, action: nil)
    let sheetTabs = NSButton(checkboxWithTitle: Localization.title("Sheet tabs"), target: nil, action: nil)
    let autoCompletion = NSButton(checkboxWithTitle: Localization.title("Autocomplete text in cells"), target: nil, action: nil)
    let functionMarkers = NSButton(checkboxWithTitle: Localization.title("Cell markers for formulas"), target: nil, action: nil)
    let extensionMarkers = NSButton(checkboxWithTitle: Localization.title("Cell markers for text that spills over"), target: nil, action: nil)
    let protected = NSButton(checkboxWithTitle: Localization.title("Protected workbook"), target: nil, action: nil)

    struct Settings {
        var horizontalScrollbar, verticalScrollbar, sheetTabs, autoCompletion, functionMarkers, extensionMarkers, protected: Bool
    }

    init(workbook: Workbook) {
        alert.messageText = Localization.title("Workbook Properties")
        alert.informativeText = "What this workbook's windows show; saved with the file."
        alert.addButton(withTitle: Localization.title("OK"))
        alert.addButton(withTitle: Localization.title("Cancel"))
        horizontalScrollbar.state = workbook.showsHorizontalScrollbar ? .on : .off
        verticalScrollbar.state = workbook.showsVerticalScrollbar ? .on : .off
        sheetTabs.state = workbook.showsSheetTabs ? .on : .off
        autoCompletion.state = workbook.autoCompletes ? .on : .off
        functionMarkers.state = workbook.showsFunctionCellMarkers ? .on : .off
        extensionMarkers.state = workbook.showsExtensionMarkers ? .on : .off
        protected.state = workbook.isProtected ? .on : .off
        let stack = NSStackView(views: [horizontalScrollbar, verticalScrollbar, sheetTabs, autoCompletion, functionMarkers, extensionMarkers, protected])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        let size = stack.fittingSize
        stack.frame = NSRect(x: 0, y: 0, width: max(size.width, 320), height: size.height)
        alert.accessoryView = stack
    }

    var settings: Settings {
        Settings(horizontalScrollbar: horizontalScrollbar.state == .on, verticalScrollbar: verticalScrollbar.state == .on,
                 sheetTabs: sheetTabs.state == .on, autoCompletion: autoCompletion.state == .on,
                 functionMarkers: functionMarkers.state == .on, extensionMarkers: extensionMarkers.state == .on,
                 protected: protected.state == .on)
    }

    func present(in window: NSWindow, apply: @escaping (Settings) -> Void) {
        if let driver = Self.headlessDriver {
            if driver(self) { apply(settings) }
            return
        }
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn else { return }
            apply(settings)
        }
    }
}

/// File → Properties… (dialog-doc-metadata.c's Description page) as an
/// alert sheet: the standard string properties, set as one undoable
/// command on OK.
@MainActor
final class DocumentPropertiesDialog: NSObject {
    nonisolated(unsafe) static var headlessDriver: ((DocumentPropertiesDialog) -> Bool)?

    /// The Calculation page's settings (the GTK's, set on the workbook).
    struct Calculation: Equatable {
        var automatic: Bool
        var iterates: Bool
        var maximum: Int
        var tolerance: Double
    }

    let alert = NSAlert()
    private(set) var fields: [(name: String, field: NSTextField)] = []
    let automaticButton = NSButton(radioButtonWithTitle: Localization.title("Automatic"), target: nil, action: nil)
    let manualButton = NSButton(radioButtonWithTitle: Localization.title("Manual"), target: nil, action: nil)
    let iterationButton = NSButton(checkboxWithTitle: Localization.title("Iterative calculation"), target: nil, action: nil)
    let maximumField = NSTextField(string: "")
    let toleranceField = NSTextField(string: "")
    /// The Statistics page's lines (the headless checks).
    private(set) var statistics: [(String, String)] = []

    init(workbook: Workbook, fileURL: URL?) {
        super.init()
        alert.messageText = Localization.title("Document Properties")
        alert.addButton(withTitle: Localization.title("OK"))
        alert.addButton(withTitle: Localization.title("Cancel"))
        let tabs = NSTabView(frame: NSRect(x: 0, y: 0, width: 460, height: 360))
        tabs.addTabViewItem(Self.tab("Description", view: descriptionGrid(workbook)))
        tabs.addTabViewItem(Self.tab("Statistics", view: statisticsGrid(workbook, fileURL: fileURL)))
        tabs.addTabViewItem(Self.tab("Calculation", view: calculationGrid(workbook)))
        tabs.addTabViewItem(Self.tab("Properties", view: propertiesView(workbook)))
        alert.accessoryView = tabs
        alert.window.initialFirstResponder = fields.first?.field
    }

    private static func tab(_ label: String, view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: label)
        item.label = label
        let content = NSView()
        content.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            view.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
        ])
        item.view = content
        return item
    }

    private func descriptionGrid(_ workbook: Workbook) -> NSGridView {
        let current = workbook.documentProperties
        var rows: [[NSView]] = []
        for name in Workbook.standardDocumentPropertyNames {
            let label = NSTextField(labelWithString: Workbook.label(forDocumentProperty: name) + ":")
            label.alignment = .right
            let field = NSTextField(string: current[name] ?? "")
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
            fields.append((name, field))
            rows.append([label, field])
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        return grid
    }

    /// The GTK Statistics page: the file, its dates, the sheets; the
    /// cells counted here (the GTK shows "Unknown").
    private func statisticsGrid(_ workbook: Workbook, fileURL: URL?) -> NSGridView {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        var lines: [(String, String)] = []
        if let fileURL {
            lines.append(("File", fileURL.lastPathComponent))
            lines.append(("Location", fileURL.deletingLastPathComponent().path))
            let attributes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)) ?? [:]
            if let created = attributes[.creationDate] as? Date { lines.append(("Created", formatter.string(from: created))) }
            if let modified = attributes[.modificationDate] as? Date { lines.append(("Modified", formatter.string(from: modified))) }
            if let size = attributes[.size] as? Int { lines.append(("Size", ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))) }
        } else {
            lines.append(("File", "Not saved yet"))
        }
        lines.append(("Sheets", "\(workbook.sheets.count)"))
        lines.append(("Cells", "\(workbook.cellCount)"))
        statistics = lines
        let rows: [[NSView]] = lines.map { line in
            let label = NSTextField(labelWithString: line.0 + ":")
            label.alignment = .right
            let value = NSTextField(labelWithString: line.1)
            value.lineBreakMode = .byTruncatingMiddle
            value.widthAnchor.constraint(lessThanOrEqualToConstant: 320).isActive = true
            return [label, value]
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        return grid
    }

    // MARK: The Properties page (custom properties)

    /// A change staged on the Properties page, applied on OK.
    enum PropertyChange: Equatable {
        case set(name: String, type: DocumentProperty.Kind, value: String)
        case remove(name: String)
    }

    private let propertiesTable = NSTableView()
    private var rows: [(name: String, value: String, type: DocumentProperty.Kind)] = []
    let propertyNameField = NSTextField(string: "")
    let propertyValueField = NSTextField(string: "")
    let propertyTypePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private(set) var propertyChanges: [PropertyChange] = []
    static let propertyTypes: [(String, DocumentProperty.Kind)] = [("Text", .string), ("Integer", .integer), ("Number", .number), ("Yes/No", .boolean), ("Date and time", .timestamp)]

    private func propertiesView(_ workbook: Workbook) -> NSView {
        rows = workbook.allDocumentProperties.map { ($0.name, $0.value, $0.type) }
        for (identifier, title, width) in [("name", "Name", 140.0), ("value", "Value", 170.0), ("type", "Type", 90.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            propertiesTable.addTableColumn(column)
        }
        propertiesTable.usesAlternatingRowBackgroundColors = true
        propertiesTable.allowsEmptySelection = true
        propertiesTable.dataSource = self
        propertiesTable.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = propertiesTable
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 420).isActive = true
        propertyNameField.placeholderString = "Name"
        propertyNameField.widthAnchor.constraint(equalToConstant: 130).isActive = true
        propertyValueField.placeholderString = "Value"
        propertyValueField.widthAnchor.constraint(equalToConstant: 160).isActive = true
        propertyTypePopUp.addItems(withTitles: Self.propertyTypes.map(\.0))
        let entry = NSStackView(views: [propertyNameField, propertyValueField, propertyTypePopUp])
        entry.orientation = .horizontal
        entry.spacing = 6
        let addButton = NSButton(title: Localization.title("Add"), target: self, action: #selector(addProperty(_:)))
        let removeButton = NSButton(title: Localization.title("Remove"), target: self, action: #selector(removeProperty(_:)))
        let buttons = NSStackView(views: [addButton, removeButton, NSView()])
        buttons.orientation = .horizontal
        buttons.spacing = 6
        let stack = NSStackView(views: [scroll, entry, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    /// Stage a set (the Add button): the table shows it at once, the
    /// workbook takes it on OK.
    func stageProperty(name: String, type: DocumentProperty.Kind, value: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        propertyChanges.removeAll { if case .set(let n, _, _) = $0 { return n == trimmed }; if case .remove(let n) = $0 { return n == trimmed }; return false }
        propertyChanges.append(.set(name: trimmed, type: type, value: value))
        if let index = rows.firstIndex(where: { $0.name == trimmed }) {
            rows[index] = (trimmed, value, type)
        } else {
            rows.append((trimmed, value, type))
            rows.sort { $0.name < $1.name }
        }
        propertiesTable.reloadData()
    }

    /// Stage a removal (the Remove button) of a listed property.
    func stageRemoval(name: String) {
        guard let index = rows.firstIndex(where: { $0.name == name }) else { return }
        propertyChanges.removeAll { if case .set(let n, _, _) = $0 { return n == name }; return false }
        propertyChanges.append(.remove(name: name))
        rows.remove(at: index)
        propertiesTable.reloadData()
    }

    @objc private func addProperty(_ sender: Any?) {
        let index = max(propertyTypePopUp.indexOfSelectedItem, 0)
        stageProperty(name: propertyNameField.stringValue, type: Self.propertyTypes[index].1, value: propertyValueField.stringValue)
    }

    @objc private func removeProperty(_ sender: Any?) {
        let row = propertiesTable.selectedRow
        guard row >= 0, row < rows.count else { return }
        stageRemoval(name: rows[row].name)
    }

    /// The table's rows as "name=value" (the headless checks).
    var propertyRowsForTesting: [String] { rows.map { "\($0.name)=\($0.value)" } }

    private func calculationGrid(_ workbook: Workbook) -> NSGridView {
        automaticButton.state = workbook.recalculatesAutomatically ? .on : .off
        manualButton.state = workbook.recalculatesAutomatically ? .off : .on
        for button in [automaticButton, manualButton] {
            button.target = self
            button.action = #selector(recalcModeChosen(_:))
        }
        iterationButton.state = workbook.iterationEnabled ? .on : .off
        iterationButton.target = self
        iterationButton.action = #selector(iterationToggled(_:))
        maximumField.stringValue = "\(workbook.iterationMaximum)"
        maximumField.alignment = .right
        maximumField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        toleranceField.stringValue = "\(workbook.iterationTolerance)"
        toleranceField.alignment = .right
        toleranceField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: Localization.title("Recalculation:")), automaticButton],
            [NSView(), manualButton],
            [NSView(), iterationButton],
            [NSTextField(labelWithString: Localization.title("Maximum iterations:")), maximumField],
            [NSTextField(labelWithString: Localization.title("Tolerance:")), toleranceField],
        ])
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        iterationToggled(nil)
        return grid
    }

    @objc private func recalcModeChosen(_ sender: NSButton) {
        automaticButton.state = sender === automaticButton ? .on : .off
        manualButton.state = sender === manualButton ? .on : .off
    }

    @objc private func iterationToggled(_ sender: Any?) {
        let on = iterationButton.state == .on
        maximumField.isEnabled = on
        toleranceField.isEnabled = on
    }

    func setValue(_ value: String, for name: String) {
        fields.first { $0.name == name }?.field.stringValue = value
    }

    /// Fill the Calculation page (the headless checks).
    func setCalculation(_ calculation: Calculation) {
        automaticButton.state = calculation.automatic ? .on : .off
        manualButton.state = calculation.automatic ? .off : .on
        iterationButton.state = calculation.iterates ? .on : .off
        maximumField.stringValue = "\(calculation.maximum)"
        toleranceField.stringValue = "\(calculation.tolerance)"
        iterationToggled(nil)
    }

    var values: [String: String] {
        Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.field.stringValue) })
    }

    /// The Calculation page as filled; nil when the maximum or the
    /// tolerance is not a number.
    var calculation: Calculation? {
        guard let maximum = Int(maximumField.stringValue.trimmingCharacters(in: .whitespaces)), maximum >= 1,
              let tolerance = Double(toleranceField.stringValue.trimmingCharacters(in: .whitespaces)), tolerance > 0 else { return nil }
        return Calculation(automatic: automaticButton.state == .on, iterates: iterationButton.state == .on, maximum: maximum, tolerance: tolerance)
    }

    func present(in window: NSWindow, apply: @escaping ([String: String], Calculation, [PropertyChange]) -> Bool) {
        if let driver = Self.headlessDriver {
            if driver(self), let calculation { _ = apply(values, calculation, propertyChanges) }
            return
        }
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn else { return }
            guard let calculation, apply(values, calculation, propertyChanges) else {
                DispatchQueue.main.async { [self] in present(in: window, apply: apply) }
                return
            }
        }
    }
}

extension DocumentPropertiesDialog: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier else { return nil }
        let entry = rows[row]
        let text: String
        switch identifier.rawValue {
        case "value": text = entry.value
        case "type": text = Self.propertyTypes.first { $0.1 == entry.type }?.0 ?? "Other"
        default: text = entry.name
        }
        if let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cell.textField?.stringValue = text
            return cell
        }
        let cell = NSTableCellView()
        cell.identifier = identifier
        let label = NSTextField(labelWithString: text)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
