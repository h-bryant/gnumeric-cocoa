import AppKit
import GnmCocoa

/// A widget's configuration dialog (sheet-object-widget.c's per-kind
/// dialogs and dialog-so-list.c) as an alert sheet: the fields the kind
/// takes (label, linked cell, value, range and direction, content and
/// output), applied as the engine's command on OK.
@MainActor
final class WidgetDialog {
    /// For the headless checks: fill the fields and return true to apply.
    nonisolated(unsafe) static var headlessDriver: ((WidgetDialog) -> Bool)?

    let alert = NSAlert()
    let settings: WidgetSettings
    let labelField = NSTextField(string: "")
    let linkField = NSTextField(string: "")
    let valueField = NSTextField(string: "")
    let minimumField = NSTextField(string: "")
    let maximumField = NSTextField(string: "")
    let incrementField = NSTextField(string: "")
    let pageField = NSTextField(string: "")
    let horizontalBox = NSButton(checkboxWithTitle: Localization.title("Horizontal"), target: nil, action: nil)
    let contentField = NSTextField(string: "")
    let outputPopUp = NSPopUpButton(frame: .zero, pullsDown: false)

    init(settings: WidgetSettings) {
        self.settings = settings
        alert.messageText = settings.title
        alert.addButton(withTitle: Localization.title("OK"))
        alert.addButton(withTitle: Localization.title("Cancel"))
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: Localization.title(text))
            field.alignment = .right
            return field
        }
        var rows: [[NSView]] = []
        let kind = settings.kind
        if [.frame, .button, .checkbox, .radioButton].contains(kind) {
            labelField.stringValue = settings.label
            rows.append([label("Label:"), labelField])
        }
        if kind != .frame {
            linkField.stringValue = settings.linkText
            linkField.placeholderString = "A cell, such as C3"
            rows.append([label(kind == .list || kind == .combo ? "Output cell:" : "Link to:"), linkField])
        }
        if kind == .radioButton {
            valueField.stringValue = settings.valueText
            rows.append([label("Value:"), valueField])
        }
        if [.scrollbar, .spinButton, .slider].contains(kind) {
            minimumField.stringValue = "\(settings.minimum)"
            maximumField.stringValue = "\(settings.maximum)"
            incrementField.stringValue = "\(settings.increment)"
            pageField.stringValue = "\(settings.pageIncrement)"
            for field in [minimumField, maximumField, incrementField, pageField] {
                field.alignment = .right
                field.widthAnchor.constraint(equalToConstant: 80).isActive = true
            }
            rows.append([label("Min:"), minimumField])
            rows.append([label("Max:"), maximumField])
            rows.append([label("Increment:"), incrementField])
            rows.append([label("Page:"), pageField])
            horizontalBox.state = settings.horizontal ? .on : .off
            rows.append([NSView(), horizontalBox])
        }
        if kind == .list || kind == .combo {
            contentField.stringValue = settings.contentText
            contentField.placeholderString = "The entries, such as A1:A7"
            rows.insert([label("Content:"), contentField], at: 0)
            outputPopUp.addItems(withTitles: ["As value", "As index"].map(Localization.title))
            outputPopUp.selectItem(at: settings.outputsIndex ? 1 : 0)
            rows.append([label("Output:"), outputPopUp])
        }
        for field in [labelField, linkField, valueField, contentField] { field.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        let size = grid.fittingSize
        grid.frame = NSRect(x: 0, y: 0, width: max(size.width, 340), height: size.height)
        alert.accessoryView = grid
        alert.window.initialFirstResponder = rows.first?.last
    }

    /// The settings as edited.
    var result: WidgetSettings {
        let edited = settings.copy() as! WidgetSettings
        edited.label = labelField.stringValue
        edited.linkText = linkField.stringValue
        edited.valueText = valueField.stringValue
        edited.minimum = Int(minimumField.stringValue) ?? edited.minimum
        edited.maximum = Int(maximumField.stringValue) ?? edited.maximum
        edited.increment = Int(incrementField.stringValue) ?? edited.increment
        edited.pageIncrement = Int(pageField.stringValue) ?? edited.pageIncrement
        edited.horizontal = horizontalBox.state == .on
        edited.contentText = contentField.stringValue
        edited.outputsIndex = outputPopUp.indexOfSelectedItem == 1
        return edited
    }

    func present(in window: NSWindow, run: @escaping (WidgetSettings) -> Bool) {
        if let driver = Self.headlessDriver {
            if driver(self) { _ = run(result) }
            return
        }
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn else { return }
            if !run(result) {
                DispatchQueue.main.async { [self] in present(in: window, run: run) }
            }
        }
    }
}
