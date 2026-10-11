import AppKit
import GnmCocoa

/// The cell grid: a flipped view whose coordinates are the sheet's pixel
/// coordinates, drawn by the engine through the bridge, with the selection
/// painted natively on top.
@MainActor
final class GridView: NSView, SheetDelegate, NSUserInterfaceValidations {
    var sheet: Sheet? {
        didSet {
            if isEditing { cancelEditing() }
            if let old = oldValue, old.delegate === self {
                old.delegate = nil
            }
            sheet?.delegate = self
            updateFrameSize()
            scroll(.zero)
            needsDisplay = true
            headerViews.forEach { $0.needsDisplay = true }
        }
    }
    var headerViews: [SheetHeaderView] = []
    /// Called after the engine reports a geometry change (zoom, sizes).
    var geometryDidChange: (() -> Void)?
    /// Called with the editor's text as it changes, and nil when editing ends.
    var editingTextDidChange: ((String?) -> Void)?
    /// Shows an error to the user (the window controller attaches an alert).
    var presentError: ((Error) -> Void)?
    private var dragAnchor: CellCoordinate?
    private var lastSelectionRect: NSRect = .zero
    private let editor = CellEditorField()
    private var editingCell: CellCoordinate?
    var isEditing: Bool { editingCell != nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Not layer-backed: cacheDisplay(in:to:) (snapshots, golden images)
        // skips layer content, and plain drawRect scrolling is fast enough
        // for now.  Revisit with responsive-scrolling measurements.
        NotificationCenter.default.addObserver(self, selector: #selector(clipFrameChanged(_:)),
                                               name: NSView.frameDidChangeNotification, object: nil)
        addSubview(editor)
        editor.onCommit = { [weak self] text, movement in self?.commitEditing(text: text, movement: movement) }
        editor.onCancel = { [weak self] in self?.cancelEditing() }
        editor.onTextChange = { [weak self] text in self?.editingTextDidChange?(text) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: Geometry

    /// The document size: the scrollable extent plus one page so the user
    /// can scroll a little past the data, as the GTK scrollbars allow.
    private func updateFrameSize() {
        guard let sheet else {
            setFrameSize(NSSize(width: 100, height: 100))
            return
        }
        let visible = enclosingScrollView?.contentView.bounds.size ?? NSSize(width: 800, height: 600)
        let extent = sheet.scrollableExtent
        let width = sheet.leftEdge(ofColumn: min(extent.column + 1, sheet.columnCount)) + visible.width
        let height = sheet.topEdge(ofRow: min(extent.row + 1, sheet.rowCount)) + visible.height
        let size = NSSize(width: ceil(width), height: ceil(height))
        if size != frame.size {
            setFrameSize(size)
        }
    }

    @objc private func clipFrameChanged(_ note: Notification) {
        guard let clip = enclosingScrollView?.contentView, note.object as? NSView === clip else { return }
        updateFrameSize()
    }

    func rect(of range: CellRange, in sheet: Sheet) -> NSRect {
        let x = sheet.leftEdge(ofColumn: range.start.column)
        let y = sheet.topEdge(ofRow: range.start.row)
        let right = sheet.leftEdge(ofColumn: min(range.end.column + 1, sheet.columnCount))
        let bottom = sheet.topEdge(ofRow: min(range.end.row + 1, sheet.rowCount))
        return NSRect(x: x, y: y, width: right - x, height: bottom - y)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let debug = ProcessInfo.processInfo.environment["GNM_DEBUG_LAYOUT"] != nil
        let started = debug ? CFAbsoluteTimeGetCurrent() : 0
        defer {
            if debug {
                NSLog("GridView.draw %@ sheet=%@ took %.1f ms", NSStringFromRect(dirtyRect), sheet?.name ?? "nil",
                      (CFAbsoluteTimeGetCurrent() - started) * 1000)
            }
        }
        guard let sheet, let context = NSGraphicsContext.current?.cgContext else {
            NSColor.white.setFill()
            dirtyRect.fill()
            return
        }
        sheet.drawCells(in: dirtyRect, context: context, backgroundColor: NSColor.white.cgColor)
        sheet.drawSheetObjects(in: dirtyRect, context: context)
        drawMarchingAnts(of: sheet, dirtyRect: dirtyRect)
        drawSelection(of: sheet, dirtyRect: dirtyRect)
    }

    private func drawSelection(of sheet: Sheet, dirtyRect: NSRect) {
        let selection = rect(of: sheet.selectedRange, in: sheet)
        lastSelectionRect = selection
        guard selection.intersects(dirtyRect) else { return }
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.12).setFill()
        selection.fill(using: .sourceOver)
        let edit = sheet.editPosition
        let editRect = sheet.frameOfCell(atColumn: edit.column, row: edit.row)
        if selection != editRect {
            NSColor.white.withAlphaComponent(0.7).setFill()
            editRect.fill(using: .sourceOver)
        }
        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(rect: selection.insetBy(dx: -0.5, dy: -0.5))
        outline.lineWidth = 2
        outline.stroke()
    }

    /// The source of the last copy or cut, outlined with dashes (static for
    /// now; the GTK front end animates them).
    private func drawMarchingAnts(of sheet: Sheet, dirtyRect: NSRect) {
        for value in sheet.marchingAntsFrames {
            let frame = value.rectValue
            guard frame.intersects(dirtyRect) else { continue }
            let path = NSBezierPath(rect: frame.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.setLineDash([4, 3], count: 2, phase: 0)
            NSColor.labelColor.setStroke()
            path.stroke()
        }
    }

    private func invalidateSelection(_ sheet: Sheet) {
        let newRect = rect(of: sheet.selectedRange, in: sheet)
        setNeedsDisplay(lastSelectionRect.insetBy(dx: -3, dy: -3))
        setNeedsDisplay(newRect.insetBy(dx: -3, dy: -3))
        headerViews.forEach { $0.needsDisplay = true }
    }

    // MARK: Editing

    /// Open the editor over the edit cell.  `initialText` nil means the
    /// cell's current content (double-click, F2); a string replaces it
    /// (typing starts fresh).
    func beginEditing(initialText: String?) {
        guard let sheet else { return }
        let cell = sheet.editPosition
        let frame = sheet.frameOfCell(atColumn: cell.column, row: cell.row)
        let zoom = sheet.zoomFactor
        editor.font = NSFont.systemFont(ofSize: max(8, 13.3 * zoom))   // the engine's 10 pt default at 96 dpi
        editor.frame = NSRect(x: frame.minX, y: frame.minY,
                              width: max(frame.width, 80 * zoom), height: max(frame.height, 16 * zoom))
        editor.stringValue = initialText ?? (sheet.editingTextOfCell(atColumn: cell.column, row: cell.row) ?? "")
        editingCell = cell
        editor.isHidden = false
        window?.makeFirstResponder(editor)
        if let fieldEditor = editor.currentEditor() {
            let end = editor.stringValue.utf16.count
            fieldEditor.selectedRange = NSRange(location: initialText == nil ? end : end, length: 0)
        }
        editingTextDidChange?(editor.stringValue)
    }

    private func endEditingSession() {
        editingCell = nil
        editor.isHidden = true
        editor.stringValue = ""
        editingTextDidChange?(nil)
        window?.makeFirstResponder(self)
    }

    func cancelEditing() {
        guard isEditing else { return }
        endEditingSession()
    }

    /// Commit the editor's text through the engine; on failure the editor
    /// stays open with the error shown.
    func commitEditing(text: String, movement: CellEditorField.Movement) {
        guard let sheet, let cell = editingCell else { return }
        do {
            try sheet.setText(text, atColumn: cell.column, row: cell.row, autocorrect: true)
        } catch {
            presentError?(error)
            window?.makeFirstResponder(editor)
            return
        }
        endEditingSession()
        switch movement {
        case .down: move(columns: 0, rows: 1, extend: false)
        case .up: move(columns: 0, rows: -1, extend: false)
        case .right: move(columns: 1, rows: 0, extend: false)
        case .left: move(columns: -1, rows: 0, extend: false)
        case .none: break
        }
    }

    /// Commit from the formula bar: same command, no movement.
    func setEditCellText(_ text: String) {
        guard let sheet else { return }
        let cell = sheet.editPosition
        do {
            try sheet.setText(text, atColumn: cell.column, row: cell.row, autocorrect: true)
        } catch {
            presentError?(error)
        }
    }

    private func clearSelectionValues() {
        guard let sheet else { return }
        do {
            try sheet.clearSelection(.values)
        } catch {
            presentError?(error)
        }
    }

    // MARK: Undo, redo, clipboard (Edit menu, through the responder chain)

    @objc func undo(_ sender: Any?) {
        if isEditing { cancelEditing() }
        sheet?.workbook?.undo()
    }

    @objc func redo(_ sender: Any?) {
        if isEditing { cancelEditing() }
        sheet?.workbook?.redo()
    }

    @objc func copy(_ sender: Any?) {
        if isEditing { commitEditing(text: editor.stringValue, movement: .none) }
        sheet?.copySelection()
    }

    @objc func cut(_ sender: Any?) {
        if isEditing { commitEditing(text: editor.stringValue, movement: .none) }
        sheet?.cutSelection()
    }

    /// The engine's clipboard when it is current, else text from the system
    /// pasteboard through the engine's text importer; one undoable command.
    @objc func paste(_ sender: Any?) {
        if isEditing { commitEditing(text: editor.stringValue, movement: .none) }
        sheet?.paste()
    }

    @objc func delete(_ sender: Any?) {
        clearSelectionValues()
    }

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        guard let sheet else { return false }
        switch item.action {
        case #selector(undo(_:)):
            if let menuItem = item as? NSMenuItem {
                menuItem.title = sheet.workbook?.undoLabel.map { "Undo " + $0 } ?? "Undo"
            }
            return sheet.workbook?.canUndo ?? false
        case #selector(redo(_:)):
            if let menuItem = item as? NSMenuItem {
                menuItem.title = sheet.workbook?.redoLabel.map { "Redo " + $0 } ?? "Redo"
            }
            return sheet.workbook?.canRedo ?? false
        case #selector(paste(_:)):
            return NSPasteboard.general.string(forType: .string) != nil
        default:
            return true
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        guard let sheet else { return }
        if isEditing { commitEditing(text: editor.stringValue, movement: .none) }
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let cell = CellCoordinate(column: sheet.column(atX: point.x), row: sheet.row(atY: point.y))
        if event.clickCount == 2 {
            sheet.selectCell(atColumn: cell.column, row: cell.row)
            beginEditing(initialText: nil)
            return
        }
        if event.modifierFlags.contains(.shift), let anchor = dragAnchor {
            sheet.selectRange(Self.range(from: anchor, to: cell), editPosition: anchor)
        } else {
            dragAnchor = cell
            sheet.selectCell(atColumn: cell.column, row: cell.row)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let sheet, let anchor = dragAnchor else { return }
        autoscroll(with: event)
        let point = convert(event.locationInWindow, from: nil)
        let cell = CellCoordinate(column: sheet.column(atX: point.x), row: sheet.row(atY: point.y))
        let range = Self.range(from: anchor, to: cell)
        let current = sheet.selectedRange
        if range.start.column != current.start.column || range.start.row != current.start.row ||
            range.end.column != current.end.column || range.end.row != current.end.row {
            sheet.selectRange(range, editPosition: anchor)
        }
    }

    private static func range(from a: CellCoordinate, to b: CellCoordinate) -> CellRange {
        CellRange(start: CellCoordinate(column: min(a.column, b.column), row: min(a.row, b.row)),
                  end: CellCoordinate(column: max(a.column, b.column), row: max(a.row, b.row)))
    }

    // MARK: Whole columns, rows, and the sheet

    /// The first visible row, where the edit cursor lands for a column
    /// selection (what the GTK pane does).
    private var topVisibleRow: Int {
        guard let sheet else { return 0 }
        return sheet.row(atY: visibleRect.minY)
    }

    private var leftVisibleColumn: Int {
        guard let sheet else { return 0 }
        return sheet.column(atX: visibleRect.minX)
    }

    func selectColumns(from first: Int, to last: Int, anchor: Int) {
        guard let sheet else { return }
        let edit = CellCoordinate(column: anchor, row: topVisibleRow)
        dragAnchor = edit
        sheet.selectRange(CellRange(start: CellCoordinate(column: first, row: 0),
                                    end: CellCoordinate(column: last, row: sheet.rowCount - 1)),
                          editPosition: edit)
    }

    func selectRows(from first: Int, to last: Int, anchor: Int) {
        guard let sheet else { return }
        let edit = CellCoordinate(column: leftVisibleColumn, row: anchor)
        dragAnchor = edit
        sheet.selectRange(CellRange(start: CellCoordinate(column: 0, row: first),
                                    end: CellCoordinate(column: sheet.columnCount - 1, row: last)),
                          editPosition: edit)
    }

    override func selectAll(_ sender: Any?) {
        guard let sheet else { return }
        let edit = CellCoordinate(column: leftVisibleColumn, row: topVisibleRow)
        dragAnchor = edit
        sheet.selectRange(CellRange(start: CellCoordinate(column: 0, row: 0),
                                    end: CellCoordinate(column: sheet.columnCount - 1, row: sheet.rowCount - 1)),
                          editPosition: edit)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        // F2 edits the current content; a printable key starts a fresh edit.
        if event.keyCode == 120 {
            beginEditing(initialText: nil)
            return
        }
        if let chars = event.characters, !chars.isEmpty,
           !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control),
           chars.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7f && !($0.value >= 0xF700 && $0.value <= 0xF8FF) }) {
            beginEditing(initialText: chars)
            return
        }
        interpretKeyEvents([event])
    }

    override func deleteBackward(_ sender: Any?) { clearSelectionValues() }
    override func deleteForward(_ sender: Any?) { clearSelectionValues() }

    private func move(columns dc: Int, rows dr: Int, extend: Bool) {
        guard let sheet else { return }
        let edit = sheet.editPosition
        let anchor = extend ? (dragAnchor ?? edit) : edit
        var target = extend ? farCorner(of: sheet.selectedRange, from: anchor) : edit
        target = step(target, columns: dc, rows: dr, in: sheet)
        if extend {
            dragAnchor = anchor
            sheet.selectRange(Self.range(from: anchor, to: target), editPosition: anchor)
        } else {
            dragAnchor = target
            sheet.selectCell(atColumn: target.column, row: target.row)
        }
        scrollToVisible(sheet.frameOfCell(atColumn: target.column, row: target.row).insetBy(dx: -2, dy: -2))
    }

    private func farCorner(of range: CellRange, from anchor: CellCoordinate) -> CellCoordinate {
        CellCoordinate(column: range.start.column == anchor.column ? range.end.column : range.start.column,
                       row: range.start.row == anchor.row ? range.end.row : range.start.row)
    }

    /// Step over hidden columns and rows; stop at the sheet edges.
    private func step(_ from: CellCoordinate, columns dc: Int, rows dr: Int, in sheet: Sheet) -> CellCoordinate {
        var column = from.column, row = from.row
        if dc != 0 {
            var c = column + dc
            while c >= 0 && c < sheet.columnCount && !sheet.isColumnVisible(c) { c += dc }
            if c >= 0 && c < sheet.columnCount { column = c }
        }
        if dr != 0 {
            var r = row + dr
            while r >= 0 && r < sheet.rowCount && !sheet.isRowVisible(r) { r += dr }
            if r >= 0 && r < sheet.rowCount { row = r }
        }
        return CellCoordinate(column: column, row: row)
    }

    private var pageRows: Int {
        guard let sheet else { return 1 }
        let visibleHeight = enclosingScrollView?.contentView.bounds.height ?? 400
        return max(1, Int(visibleHeight / max(sheet.height(ofRow: sheet.editPosition.row), 1)) - 1)
    }

    override func moveUp(_ sender: Any?) { move(columns: 0, rows: -1, extend: false) }
    override func moveDown(_ sender: Any?) { move(columns: 0, rows: 1, extend: false) }
    override func moveLeft(_ sender: Any?) { move(columns: -1, rows: 0, extend: false) }
    override func moveRight(_ sender: Any?) { move(columns: 1, rows: 0, extend: false) }
    override func moveUpAndModifySelection(_ sender: Any?) { move(columns: 0, rows: -1, extend: true) }
    override func moveDownAndModifySelection(_ sender: Any?) { move(columns: 0, rows: 1, extend: true) }
    override func moveLeftAndModifySelection(_ sender: Any?) { move(columns: -1, rows: 0, extend: true) }
    override func moveRightAndModifySelection(_ sender: Any?) { move(columns: 1, rows: 0, extend: true) }
    override func pageDown(_ sender: Any?) { move(columns: 0, rows: pageRows, extend: false) }
    override func pageUp(_ sender: Any?) { move(columns: 0, rows: -pageRows, extend: false) }
    override func moveToBeginningOfLine(_ sender: Any?) {
        guard let sheet else { return }
        sheet.selectCell(atColumn: 0, row: sheet.editPosition.row)
        scrollToVisible(sheet.frameOfCell(atColumn: 0, row: sheet.editPosition.row))
    }
    override func moveToBeginningOfDocument(_ sender: Any?) {
        sheet?.selectCell(atColumn: 0, row: 0)
        scroll(.zero)
    }
    override func insertTab(_ sender: Any?) { move(columns: 1, rows: 0, extend: false) }
    override func insertBacktab(_ sender: Any?) { move(columns: -1, rows: 0, extend: false) }
    override func insertNewline(_ sender: Any?) { move(columns: 0, rows: 1, extend: false) }

    // MARK: SheetDelegate

    func sheetNeedsDisplay(_ sheet: Sheet, includingHeaders: Bool) {
        needsDisplay = true
        if includingHeaders {
            headerViews.forEach { $0.needsDisplay = true }
        }
    }

    func sheet(_ sheet: Sheet, needsDisplayIn range: CellRange) {
        setNeedsDisplay(rect(of: range, in: sheet).insetBy(dx: -2, dy: -2))
    }

    func sheet(_ sheet: Sheet, needsHeaderDisplayForColumns columns: Bool, rows: Bool) {
        headerViews.forEach { $0.needsDisplay = true }
    }

    func sheetGeometryDidChange(_ sheet: Sheet) {
        updateFrameSize()
        needsDisplay = true
        headerViews.forEach { $0.needsDisplay = true }
        geometryDidChange?()
    }

    func sheet(_ sheet: Sheet, cursorDidMoveTo range: CellRange) {
        invalidateSelection(sheet)
    }

    func sheetMarchingAntsDidChange(_ sheet: Sheet) {
        needsDisplay = true
    }

    func sheet(_ sheet: Sheet, scrollToColumn column: Int, row: Int) {
        scroll(NSPoint(x: sheet.leftEdge(ofColumn: column), y: sheet.topEdge(ofRow: row)))
    }

    func sheet(_ sheet: Sheet, makeVisibleColumn column: Int, row: Int) {
        scrollToVisible(sheet.frameOfCell(atColumn: column, row: row))
    }
}
