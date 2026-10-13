import AppKit
import GnmCocoa

/// The GTK Insert → Hyperlink dialog (dialog-hyperlink.c) as an alert
/// sheet: the link type, its target (a range or name, a file, an address
/// and subject, a web address), and the tip; prefilled from the edit
/// position's link, with Remove when there is one.
@MainActor
final class HyperlinkDialog: NSObject {
    /// For the headless checks: fill the fields and return true to apply.
    nonisolated(unsafe) static var headlessDriver: ((HyperlinkDialog) -> Bool)?

    static let kinds: [Hyperlink.Kind] = [.internal, .externalFile, .email, .web]

    let alert = NSAlert()
    let kind = NSPopUpButton(frame: .zero, pullsDown: false)
    let rangeField = NSTextField(string: "")
    let fileField = NSTextField(string: "")
    let addressField = NSTextField(string: "")
    let subjectField = NSTextField(string: "")
    let webField = NSTextField(string: "")
    let defaultTip = NSButton(checkboxWithTitle: Localization.title("Use the target as the tip"), target: nil, action: nil)
    let tipField = NSTextField(string: "")
    let hasLink: Bool

    init(sheet: Sheet) {
        let cell = sheet.editPosition
        let current = sheet.hyperlink(atColumn: cell.column, row: cell.row)
        hasLink = current != nil
        super.init()
        alert.messageText = Localization.title("Hyperlink")
        alert.informativeText = "A link on the selected cells; a click follows it."
        alert.addButton(withTitle: Localization.title("OK"))
        alert.addButton(withTitle: Localization.title("Cancel"))
        if hasLink { alert.addButton(withTitle: Localization.title("Remove")) }
        kind.addItems(withTitles: ["Internal Link", "External Link", "Email Link", "Web Link"].map(Localization.title))
        kind.selectItem(at: 3)
        defaultTip.state = .on
        if let current {
            kind.selectItem(at: Self.kinds.firstIndex(of: current.kind) ?? 3)
            switch current.kind {
            case .internal: rangeField.stringValue = current.target
            case .externalFile: fileField.stringValue = current.target
            case .email:
                let (address, subject) = Self.parseMailto(current.target)
                addressField.stringValue = address
                subjectField.stringValue = subject
            default: webField.stringValue = current.target
            }
            if let tip = current.tip {
                defaultTip.state = .off
                tipField.stringValue = tip
            }
        }
        for field in [rangeField, fileField, addressField, subjectField, webField, tipField] {
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        }
        kind.target = self
        kind.action = #selector(kindChanged(_:))
        defaultTip.target = self
        defaultTip.action = #selector(kindChanged(_:))
        alert.accessoryView = makeGrid()
        kindChanged(nil)
    }

    private func makeGrid() -> NSGridView {
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: Localization.title(text))
            field.alignment = .right
            return field
        }
        let rows: [[NSView]] = [
            [label("Type:"), kind],
            [label("Target range:"), rangeField], [label("File:"), fileField],
            [label("Email address:"), addressField], [label("Subject:"), subjectField],
            [label("Web address:"), webField],
            [NSGridCell.emptyContentView, defaultTip], [label("Tip:"), tipField],
        ]
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        for index in 0..<grid.numberOfRows { grid.row(at: index).yPlacement = .center }
        let size = grid.fittingSize
        grid.frame = NSRect(x: 0, y: 0, width: max(size.width, 400), height: size.height)
        return grid
    }

    var selectedKind: Hyperlink.Kind { Self.kinds[max(0, kind.indexOfSelectedItem)] }

    /// Only the chosen type's fields take input.
    @objc func kindChanged(_ sender: Any?) {
        rangeField.isEnabled = selectedKind == .internal
        fileField.isEnabled = selectedKind == .externalFile
        addressField.isEnabled = selectedKind == .email
        subjectField.isEnabled = selectedKind == .email
        webField.isEnabled = selectedKind == .web
        tipField.isEnabled = defaultTip.state == .off
    }

    /// The dialog's reading of a mailto target back into its fields.
    static func parseMailto(_ target: String) -> (address: String, subject: String) {
        guard target.hasPrefix("mailto:") else { return (target, "") }
        let rest = target.dropFirst("mailto:".count)
        let parts = rest.split(separator: "?", maxSplits: 1)
        let address = String(parts.first ?? "").removingPercentEncoding ?? String(parts.first ?? "")
        var subject = ""
        if parts.count > 1 {
            for pair in parts[1].split(separator: "&") where pair.hasPrefix("subject=") {
                let value = String(pair.dropFirst("subject=".count))
                subject = value.removingPercentEncoding ?? value
            }
        }
        return (address, subject)
    }

    /// The target as the fields give it, or nil when the chosen type's
    /// field is empty.
    func makeTarget() -> String? {
        let text: String
        switch selectedKind {
        case .internal: text = rangeField.stringValue
        case .externalFile: text = fileField.stringValue
        case .email: text = Hyperlink.emailTarget(address: addressField.stringValue, subject: subjectField.stringValue)
        default: text = webField.stringValue
        }
        return text.isEmpty ? nil : text
    }

    /// The link to apply, or nil to remove.
    func makeHyperlink() -> Hyperlink? {
        guard let target = makeTarget() else { return nil }
        return Hyperlink(kind: selectedKind, target: target, tip: defaultTip.state == .on ? nil : tipField.stringValue)
    }

    /// Present as a sheet; `apply` gets the link (nil to remove) on OK or
    /// Remove and returns whether it was accepted (a refusal re-presents).
    func present(in window: NSWindow, apply: @escaping (Hyperlink?) -> Bool) {
        if let driver = Self.headlessDriver {
            if driver(self) { _ = apply(makeHyperlink()) }
            return
        }
        alert.window.initialFirstResponder = webField
        alert.beginSheetModal(for: window) { [self] response in
            let accepted: Bool
            switch response {
            case .alertFirstButtonReturn: accepted = apply(makeHyperlink())
            case .alertThirdButtonReturn: accepted = apply(nil)
            default: return
            }
            if !accepted {
                DispatchQueue.main.async { [self] in present(in: window, apply: apply) }
            }
        }
    }
}
