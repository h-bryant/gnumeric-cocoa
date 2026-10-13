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

    let alert = NSAlert()
    private(set) var fields: [(name: String, field: NSTextField)] = []

    init(workbook: Workbook) {
        alert.messageText = "Document Properties"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
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
        let size = grid.fittingSize
        grid.frame = NSRect(x: 0, y: 0, width: max(size.width, 400), height: size.height)
        alert.accessoryView = grid
        alert.window.initialFirstResponder = fields.first?.field
    }

    func setValue(_ value: String, for name: String) {
        fields.first { $0.name == name }?.field.stringValue = value
    }

    var values: [String: String] {
        Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.field.stringValue) })
    }

    func present(in window: NSWindow, apply: @escaping ([String: String]) -> Bool) {
        if let driver = Self.headlessDriver {
            if driver(self) { _ = apply(values) }
            return
        }
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn else { return }
            if !apply(values) {
                DispatchQueue.main.async { [self] in present(in: window, apply: apply) }
            }
        }
    }
}
