import AppKit

/// The in-cell editor: a borderless text field the grid places over the
/// cell being edited.  Return, Tab, and Escape go to the grid through
/// `onCommit` and `onCancel`; the field itself handles text editing.
@MainActor
final class CellEditorField: NSTextField, NSTextFieldDelegate {
    enum Movement { case none, down, up, right, left }
    var onCommit: ((String, Movement) -> Void)?
    var onCancel: (() -> Void)?
    var onTextChange: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        isBezeled = false
        drawsBackground = true
        backgroundColor = .white
        textColor = .black
        focusRingType = .none
        lineBreakMode = .byClipping
        cell?.usesSingleLineMode = true
        cell?.isScrollable = true
        delegate = self
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func controlTextDidChange(_ obj: Notification) {
        onTextChange?(stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            onCommit?(stringValue, .down)
        case #selector(NSResponder.insertTab(_:)):
            onCommit?(stringValue, .right)
        case #selector(NSResponder.insertBacktab(_:)):
            onCommit?(stringValue, .left)
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
        case #selector(NSResponder.moveUp(_:)):
            onCommit?(stringValue, .up)
        case #selector(NSResponder.moveDown(_:)):
            onCommit?(stringValue, .down)
        default:
            return false
        }
        return true
    }

    /// Clicking elsewhere ends editing: commit without moving.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard !isHidden else { return }
        let movement = (obj.userInfo?["NSTextMovement"] as? Int) ?? NSTextMovement.other.rawValue
        if movement == NSTextMovement.other.rawValue {
            onCommit?(stringValue, .none)
        }
    }
}
