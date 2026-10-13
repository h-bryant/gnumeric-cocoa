import AppKit
import GnmCocoa

/// Format → Workbook… (dialog-workbook-attr.c) as an alert sheet: the
/// view's attributes as checkboxes, applied at once on OK.
@MainActor
final class WorkbookAttributesDialog {
    nonisolated(unsafe) static var headlessDriver: ((WorkbookAttributesDialog) -> Bool)?

    let alert = NSAlert()
    let horizontalScrollbar = NSButton(checkboxWithTitle: "Horizontal scrollbar", target: nil, action: nil)
    let verticalScrollbar = NSButton(checkboxWithTitle: "Vertical scrollbar", target: nil, action: nil)
    let sheetTabs = NSButton(checkboxWithTitle: "Sheet tabs", target: nil, action: nil)
    let autoCompletion = NSButton(checkboxWithTitle: "Autocomplete text in cells", target: nil, action: nil)
    let functionMarkers = NSButton(checkboxWithTitle: "Cell markers for formulas", target: nil, action: nil)
    let extensionMarkers = NSButton(checkboxWithTitle: "Cell markers for text that spills over", target: nil, action: nil)
    let protected = NSButton(checkboxWithTitle: "Protected workbook", target: nil, action: nil)

    struct Settings {
        var horizontalScrollbar, verticalScrollbar, sheetTabs, autoCompletion, functionMarkers, extensionMarkers, protected: Bool
    }

    init(workbook: Workbook) {
        alert.messageText = "Workbook Properties"
        alert.informativeText = "What this workbook's windows show; saved with the file."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
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
final class DocumentPropertiesDialog {
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
    let automaticButton = NSButton(radioButtonWithTitle: "Automatic", target: nil, action: nil)
    let manualButton = NSButton(radioButtonWithTitle: "Manual", target: nil, action: nil)
    let iterationButton = NSButton(checkboxWithTitle: "Iterative calculation", target: nil, action: nil)
    let maximumField = NSTextField(string: "")
    let toleranceField = NSTextField(string: "")
    /// The Statistics page's lines (the headless checks).
    private(set) var statistics: [(String, String)] = []

    init(workbook: Workbook, fileURL: URL?) {
        alert.messageText = "Document Properties"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let tabs = NSTabView(frame: NSRect(x: 0, y: 0, width: 460, height: 360))
        tabs.addTabViewItem(Self.tab("Description", view: descriptionGrid(workbook)))
        tabs.addTabViewItem(Self.tab("Statistics", view: statisticsGrid(workbook, fileURL: fileURL)))
        tabs.addTabViewItem(Self.tab("Calculation", view: calculationGrid(workbook)))
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
            [NSTextField(labelWithString: "Recalculation:"), automaticButton],
            [NSView(), manualButton],
            [NSView(), iterationButton],
            [NSTextField(labelWithString: "Maximum iterations:"), maximumField],
            [NSTextField(labelWithString: "Tolerance:"), toleranceField],
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

    func present(in window: NSWindow, apply: @escaping ([String: String], Calculation) -> Bool) {
        if let driver = Self.headlessDriver {
            if driver(self), let calculation { _ = apply(values, calculation) }
            return
        }
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn else { return }
            guard let calculation, apply(values, calculation) else {
                DispatchQueue.main.async { [self] in present(in: window, apply: apply) }
                return
            }
        }
    }
}
