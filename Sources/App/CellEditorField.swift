import AppKit

/// The in-cell editor: a borderless text field the grid places over the
/// cell being edited.  Return, Tab, and Escape go to the grid through
/// `onCommit` and `onCancel`; arrow keys are offered to `onArrow` first
/// (range selection while a formula is typed); the field itself handles
/// text editing.
@MainActor
final class CellEditorField: NSTextField, NSTextFieldDelegate {
    /// `enter` is Return: where it goes is a preference (down by default).
    enum Movement { case none, enter, down, up, right, left }
    var onCommit: ((String, Movement) -> Void)?
    var onCancel: (() -> Void)?
    var onTextChange: ((String) -> Void)?
    /// An arrow key as (columns, rows, Shift extends, ⌘ jumps to the edge
    /// of the data): true when it moved a range, else the key keeps its
    /// meaning in the text (Up and Down commit).
    var onArrow: ((Int, Int, Bool, Bool) -> Bool)?
    /// Return with Shift and Control or Command: the text as an array
    /// formula over the selection.
    var onArrayCommit: ((String) -> Void)?

    override class var cellClass: AnyClass? {
        get { CellEditorCell.self }
        set {}
    }

    /// The field's own field editor (lent through `CellEditorCell`), so
    /// Return with modifiers is seen before the text system takes it.
    lazy var ownFieldEditor: NSTextView = {
        let view = CellFieldEditor()
        view.isFieldEditor = true
        view.owner = self
        return view
    }()

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

    /// A key the field editor got, before the text system interprets it:
    /// Return with Shift and Control or Command enters an array formula.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.keyCode == 36 || event.keyCode == 76,   // Return, Enter
              flags.contains(.shift), !flags.isDisjoint(with: [.control, .command]),
              let onArrayCommit else { return false }
        onArrayCommit(stringValue)
        return true
    }

    private func arrow(_ columns: Int, _ rows: Int, extend: Bool = false, jump: Bool = false) -> Bool {
        onArrow?(columns, rows, extend, jump) ?? false
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            onCommit?(stringValue, .enter)
        case #selector(NSResponder.insertTab(_:)):
            onCommit?(stringValue, .right)
        case #selector(NSResponder.insertBacktab(_:)):
            onCommit?(stringValue, .left)
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
        case #selector(NSResponder.moveUp(_:)):
            if !arrow(0, -1) { onCommit?(stringValue, .up) }
        case #selector(NSResponder.moveDown(_:)):
            if !arrow(0, 1) { onCommit?(stringValue, .down) }
        case #selector(NSResponder.moveLeft(_:)):
            return arrow(-1, 0)
        case #selector(NSResponder.moveRight(_:)):
            return arrow(1, 0)
        case #selector(NSResponder.moveUpAndModifySelection(_:)):
            return arrow(0, -1, extend: true)
        case #selector(NSResponder.moveDownAndModifySelection(_:)):
            return arrow(0, 1, extend: true)
        case #selector(NSResponder.moveLeftAndModifySelection(_:)):
            return arrow(-1, 0, extend: true)
        case #selector(NSResponder.moveRightAndModifySelection(_:)):
            return arrow(1, 0, extend: true)
        // ⌘-arrows in a text view
        case #selector(NSResponder.moveToBeginningOfDocument(_:)):
            return arrow(0, -1, jump: true)
        case #selector(NSResponder.moveToEndOfDocument(_:)):
            return arrow(0, 1, jump: true)
        case #selector(NSResponder.moveToLeftEndOfLine(_:)), #selector(NSResponder.moveToBeginningOfLine(_:)):
            return arrow(-1, 0, jump: true)
        case #selector(NSResponder.moveToRightEndOfLine(_:)), #selector(NSResponder.moveToEndOfLine(_:)):
            return arrow(1, 0, jump: true)
        case #selector(NSResponder.moveToBeginningOfDocumentAndModifySelection(_:)):
            return arrow(0, -1, extend: true, jump: true)
        case #selector(NSResponder.moveToEndOfDocumentAndModifySelection(_:)):
            return arrow(0, 1, extend: true, jump: true)
        case #selector(NSResponder.moveToLeftEndOfLineAndModifySelection(_:)), #selector(NSResponder.moveToBeginningOfLineAndModifySelection(_:)):
            return arrow(-1, 0, extend: true, jump: true)
        case #selector(NSResponder.moveToRightEndOfLineAndModifySelection(_:)), #selector(NSResponder.moveToEndOfLineAndModifySelection(_:)):
            return arrow(1, 0, extend: true, jump: true)
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

/// The editor's cell: lends the field its own field editor.
final class CellEditorCell: NSTextFieldCell {
    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        MainActor.assumeIsolated { (controlView as? CellEditorField)?.ownFieldEditor }
    }
}

/// The field editor that lets the field see keys first.
@MainActor
final class CellFieldEditor: NSTextView {
    weak var owner: CellEditorField?
    override func keyDown(with event: NSEvent) {
        if let owner, owner.handleKeyDown(event) { return }
        super.keyDown(with: event)
    }
}
