import AppKit

/// The GTK Auto Save dialog (dialog-autosave.c) as an alert sheet: whether
/// to save automatically, every how many minutes, and whether to ask
/// first.  OK is refused (the dialog returns) while saving is on and the
/// minutes are not a positive number, as the GTK keeps its OK insensitive.
@MainActor
final class AutoSaveDialog {
    /// For the headless checks: fill the fields and return true to apply.
    nonisolated(unsafe) static var headlessDriver: ((AutoSaveDialog) -> Bool)?

    let alert = NSAlert()
    let enabled = NSButton(checkboxWithTitle: "Automatically save every", target: nil, action: nil)
    let minutesField = NSTextField(string: "")
    let prompt = NSButton(checkboxWithTitle: "Prompt before saving", target: nil, action: nil)

    init(seconds: Int, prompt promptFirst: Bool) {
        alert.messageText = "Auto Save"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        enabled.state = seconds > 0 ? .on : .off
        enabled.target = self
        enabled.action = #selector(enabledChanged(_:))
        minutesField.stringValue = seconds > 0 ? "\(seconds / 60)" : "10"
        minutesField.alignment = .right
        minutesField.widthAnchor.constraint(equalToConstant: 50).isActive = true
        prompt.state = promptFirst ? .on : .off
        let row = NSStackView(views: [enabled, minutesField, NSTextField(labelWithString: "minutes")])
        row.orientation = .horizontal
        row.spacing = 6
        let grid = NSGridView(views: [[row], [prompt]])
        grid.rowSpacing = 8
        let size = grid.fittingSize
        grid.frame = NSRect(x: 0, y: 0, width: max(size.width, 280), height: size.height)
        alert.accessoryView = grid
        alert.window.initialFirstResponder = minutesField
        enabledChanged(nil)
    }

    @objc private func enabledChanged(_ sender: Any?) {
        let on = enabled.state == .on
        minutesField.isEnabled = on
        prompt.isEnabled = on
    }

    /// The seconds the fields describe: 0 when saving is off, nil when
    /// the minutes are not a positive whole number.
    var seconds: Int? {
        guard enabled.state == .on else { return 0 }
        let text = minutesField.stringValue.trimmingCharacters(in: .whitespaces)
        guard let minutes = Int(text), minutes > 0 else { return nil }
        return 60 * min(minutes, Int.max / 60)
    }

    /// Present as a sheet; `apply` gets the seconds (0 for off) and
    /// whether to prompt.
    func present(in window: NSWindow, apply: @escaping (Int, Bool) -> Void) {
        if let driver = Self.headlessDriver {
            if driver(self), let seconds { apply(seconds, prompt.state == .on) }
            return
        }
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn else { return }
            guard let seconds else {
                DispatchQueue.main.async { [self] in present(in: window, apply: apply) }
                return
            }
            apply(seconds, prompt.state == .on)
        }
    }
}
