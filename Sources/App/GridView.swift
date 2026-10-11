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
    /// Dragging the fill handle: the source range and the pending target.
    private var fillSource: CellRange?
    private var fillTarget: CellRange?
    /// A column or row boundary being dragged in a header, as a guide line
    /// across the grid (sheet pixels).
    var resizeGuide: (isColumn: Bool, position: CGFloat)? {
        didSet { needsDisplay = true }
    }
    static let fillHandleSize: CGFloat = 7

    /// Frozen panes: the frozen rows and columns are painted as overlays at
    /// the top and left of the visible rect (the GTK front end uses up to
    /// four canvases instead).  `origin` is the sheet position of the frozen
    /// area's top-left cell, `width` and `height` the frozen extents in
    /// sheet pixels (0 when no columns or no rows are frozen).
    struct Panes {
        let origin: NSPoint
        let width: CGFloat
        let height: CGFloat
        var hasColumns: Bool { width > 0 }
        var hasRows: Bool { height > 0 }
    }

    var panes: Panes? {
        guard let sheet, sheet.isFrozen else { return nil }
        let frozen = sheet.frozenTopLeft, unfrozen = sheet.unfrozenTopLeft
        let origin = NSPoint(x: sheet.leftEdge(ofColumn: frozen.column), y: sheet.topEdge(ofRow: frozen.row))
        return Panes(origin: origin,
                     width: unfrozen.column > frozen.column ? sheet.leftEdge(ofColumn: unfrozen.column) - origin.x : 0,
                     height: unfrozen.row > frozen.row ? sheet.topEdge(ofRow: unfrozen.row) - origin.y : 0)
    }

    /// The scroll origin the clip view must not go above: the first
    /// unfrozen cell sits right under the frozen strips.
    var minimumScrollOrigin: NSPoint {
        guard let panes else { return .zero }
        return panes.origin
    }

    // Sheet pixels and view points coincide, except where a frozen strip
    // covers the visible rect: there the view shows the frozen cells.
    func viewX(forSheetX x: CGFloat) -> CGFloat {
        guard let panes, panes.hasColumns, x >= panes.origin.x, x < panes.origin.x + panes.width else { return x }
        return visibleRect.minX + (x - panes.origin.x)
    }

    func viewY(forSheetY y: CGFloat) -> CGFloat {
        guard let panes, panes.hasRows, y >= panes.origin.y, y < panes.origin.y + panes.height else { return y }
        return visibleRect.minY + (y - panes.origin.y)
    }

    func sheetX(forViewX x: CGFloat) -> CGFloat {
        guard let panes, panes.hasColumns, x >= visibleRect.minX, x < visibleRect.minX + panes.width else { return x }
        return panes.origin.x + (x - visibleRect.minX)
    }

    func sheetY(forViewY y: CGFloat) -> CGFloat {
        guard let panes, panes.hasRows, y >= visibleRect.minY, y < visibleRect.minY + panes.height else { return y }
        return panes.origin.y + (y - visibleRect.minY)
    }

    func sheetPoint(forViewPoint p: NSPoint) -> NSPoint {
        NSPoint(x: sheetX(forViewX: p.x), y: sheetY(forViewY: p.y))
    }

    /// Where a sheet rect appears; one that straddles a frozen boundary
    /// keeps its size and follows its origin.
    func viewRect(forSheetRect r: NSRect) -> NSRect {
        NSRect(x: viewX(forSheetX: r.minX), y: viewY(forSheetY: r.minY), width: r.width, height: r.height)
    }

    /// The part of the visible rect that scrolls: the visible rect minus
    /// the frozen strips.
    var scrollingVisibleRect: NSRect {
        var r = visibleRect
        if let panes {
            r.origin.x += panes.width; r.size.width -= panes.width
            r.origin.y += panes.height; r.size.height -= panes.height
        }
        return r
    }
    private let editor = CellEditorField()
    private var editingCell: CellCoordinate?
    var isEditing: Bool { editingCell != nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Layer-backed like the rest of the window (AppKit gives it a layer
        // because its ancestors have one); everything is drawn in draw(_:),
        // so cacheDisplay(in:to:) snapshots stay faithful.  Full-window
        // redraws take 3 to 10 ms, so scrolling needs nothing special yet.
        clipsToBounds = true   // macOS 14+ default is false; see SheetHeaderView
        NotificationCenter.default.addObserver(self, selector: #selector(clipFrameChanged(_:)),
                                               name: NSView.frameDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(clipBoundsChanged(_:)),
                                               name: NSView.boundsDidChangeNotification, object: nil)
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
        headerViews.forEach { $0.needsDisplay = true }
    }

    /// Scrolling: the headers follow the clip view's bounds origin, and
    /// frozen strips are repainted at the new visible rect.
    @objc private func clipBoundsChanged(_ note: Notification) {
        guard let clip = enclosingScrollView?.contentView, note.object as? NSView === clip else { return }
        headerViews.forEach { $0.needsDisplay = true }
        if panes != nil { needsDisplay = true }
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
        if debug, let context = NSGraphicsContext.current?.cgContext {
            let t = context.textMatrix, m = context.ctm
            NSLog("GridView.draw textMatrix=[%g %g %g %g %g %g] ctm=[%g %g %g %g %g %g] clip=%@",
                  t.a, t.b, t.c, t.d, t.tx, t.ty, m.a, m.b, m.c, m.d, m.tx, m.ty,
                  NSStringFromRect(context.boundingBoxOfClipPath))
        }
        guard let sheet, let context = NSGraphicsContext.current?.cgContext else {
            NSColor.white.setFill()
            dirtyRect.fill()
            return
        }
        drawPass(sheet, context: context, dirtyRect: dirtyRect)
        guard let panes else { return }
        // Frozen strips: the sheet drawn again, shifted so the frozen cells
        // land at the top and left of the visible rect, clipped to each strip.
        let visible = visibleRect
        var strips: [(clip: NSRect, shift: NSPoint)] = []
        if panes.hasRows {
            strips.append((NSRect(x: visible.minX + panes.width, y: visible.minY,
                                  width: visible.width - panes.width, height: panes.height),
                           NSPoint(x: 0, y: visible.minY - panes.origin.y)))
        }
        if panes.hasColumns {
            strips.append((NSRect(x: visible.minX, y: visible.minY + panes.height,
                                  width: panes.width, height: visible.height - panes.height),
                           NSPoint(x: visible.minX - panes.origin.x, y: 0)))
        }
        if panes.hasRows && panes.hasColumns {
            strips.append((NSRect(x: visible.minX, y: visible.minY, width: panes.width, height: panes.height),
                           NSPoint(x: visible.minX - panes.origin.x, y: visible.minY - panes.origin.y)))
        }
        for strip in strips {
            let clip = strip.clip.intersection(dirtyRect)
            guard !clip.isEmpty else { continue }
            NSGraphicsContext.saveGraphicsState()
            clip.clip()
            let transform = NSAffineTransform()
            transform.translateX(by: strip.shift.x, yBy: strip.shift.y)
            transform.concat()
            drawPass(sheet, context: context, dirtyRect: clip.offsetBy(dx: -strip.shift.x, dy: -strip.shift.y))
            NSGraphicsContext.restoreGraphicsState()
        }
        // The pane boundaries.
        NSColor.tertiaryLabelColor.setFill()
        if panes.hasRows {
            NSRect(x: visible.minX, y: visible.minY + panes.height - 1, width: visible.width, height: 1).fill()
        }
        if panes.hasColumns {
            NSRect(x: visible.minX + panes.width - 1, y: visible.minY, width: 1, height: visible.height).fill()
        }
    }

    /// Everything the sheet shows in `dirtyRect` (sheet coordinates).
    private func drawPass(_ sheet: Sheet, context: CGContext, dirtyRect: NSRect) {
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
        if !isEditing {
            // The fill handle: a small square on the bottom-right corner.
            let handle = fillHandleRect(for: selection)
            NSColor.white.setFill()
            handle.insetBy(dx: -1, dy: -1).fill()
            NSColor.controlAccentColor.setFill()
            handle.fill()
        }
        if let fillTarget {
            let target = rect(of: fillTarget, in: sheet)
            let path = NSBezierPath(rect: target.insetBy(dx: -0.5, dy: -0.5))
            path.lineWidth = 1
            path.setLineDash([4, 2], count: 2, phase: 0)
            NSColor.controlAccentColor.setStroke()
            path.stroke()
        }
        if let resizeGuide {
            NSColor.controlAccentColor.withAlphaComponent(0.6).setFill()
            let visible = visibleRect
            if resizeGuide.isColumn {
                NSRect(x: resizeGuide.position - 1, y: visible.minY, width: 1, height: visible.height).fill()
            } else {
                NSRect(x: visible.minX, y: resizeGuide.position - 1, width: visible.width, height: 1).fill()
            }
        }
    }

    private func fillHandleRect(for selection: NSRect) -> NSRect {
        let size = Self.fillHandleSize
        return NSRect(x: selection.maxX - size / 2, y: selection.maxY - size / 2, width: size, height: size)
    }

    override func resetCursorRects() {
        guard let sheet, !isEditing else { return }
        addCursorRect(viewRect(forSheetRect: fillHandleRect(for: rect(of: sheet.selectedRange, in: sheet))).insetBy(dx: -2, dy: -2),
                      cursor: .crosshair)
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
        if panes != nil {
            needsDisplay = true   // the overlays show these cells elsewhere
        } else {
            setNeedsDisplay(lastSelectionRect.insetBy(dx: -6, dy: -6))
            setNeedsDisplay(newRect.insetBy(dx: -6, dy: -6))
        }
        headerViews.forEach { $0.needsDisplay = true }
        window?.invalidateCursorRects(for: self)
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

    // MARK: Edit, Insert, Format, and Data menu commands on the selection

    /// Finish any edit, run an engine command, and show its error.
    private func run(_ command: (Sheet) throws -> Void) {
        guard let sheet else { return }
        if isEditing { commitEditing(text: editor.stringValue, movement: .none) }
        do {
            try command(sheet)
        } catch {
            presentError?(error)
        }
    }

    @objc func clearAll(_ sender: Any?) {
        run { try $0.clearSelection([.values, .formats, .comments, .objects]) }
    }
    @objc func clearFormats(_ sender: Any?) { run { try $0.clearSelection(.formats) } }
    @objc func clearComments(_ sender: Any?) { run { try $0.clearSelection(.comments) } }

    /// Insert as many columns (rows) as the selection spans, before it, as
    /// the GTK front end does.
    @objc func insertColumns(_ sender: Any?) {
        run { sheet in
            let range = sheet.selectedRange
            try sheet.insertColumns(range.end.column - range.start.column + 1, at: range.start.column)
        }
    }
    @objc func insertRows(_ sender: Any?) {
        run { sheet in
            let range = sheet.selectedRange
            try sheet.insertRows(range.end.row - range.start.row + 1, at: range.start.row)
        }
    }
    @objc func deleteColumns(_ sender: Any?) {
        run { sheet in
            let range = sheet.selectedRange
            try sheet.deleteColumns(NSRange(location: range.start.column, length: range.end.column - range.start.column + 1))
        }
    }
    @objc func deleteRows(_ sender: Any?) {
        run { sheet in
            let range = sheet.selectedRange
            try sheet.deleteRows(NSRange(location: range.start.row, length: range.end.row - range.start.row + 1))
        }
    }

    @objc func fillDown(_ sender: Any?) { run { try $0.fillDown() } }
    @objc func fillRight(_ sender: Any?) { run { try $0.fillRight() } }

    @objc func selectColumn(_ sender: Any?) {
        guard let sheet else { return }
        let range = sheet.selectedRange
        selectColumns(from: range.start.column, to: range.end.column, anchor: sheet.editPosition.column)
    }
    @objc func selectRow(_ sender: Any?) {
        guard let sheet else { return }
        let range = sheet.selectedRange
        selectRows(from: range.start.row, to: range.end.row, anchor: sheet.editPosition.row)
    }

    @objc func hideColumns(_ sender: Any?) { run { try $0.setSelected(columns: true, hidden: true) } }
    @objc func unhideColumns(_ sender: Any?) { run { try $0.setSelected(columns: true, hidden: false) } }
    @objc func hideRows(_ sender: Any?) { run { try $0.setSelected(columns: false, hidden: true) } }
    @objc func unhideRows(_ sender: Any?) { run { try $0.setSelected(columns: false, hidden: false) } }
    @objc func autofitColumns(_ sender: Any?) { run { try $0.autofitSelected(columns: true) } }
    @objc func autofitRows(_ sender: Any?) { run { try $0.autofitSelected(columns: false) } }

    @objc func mergeCells(_ sender: Any?) { run { try $0.mergeSelection(centered: false) } }
    @objc func mergeAndCenter(_ sender: Any?) { run { try $0.mergeSelection(centered: true) } }
    @objc func unmergeCells(_ sender: Any?) { run { try $0.unmergeSelection() } }

    @objc func recalculate(_ sender: Any?) {
        if isEditing { commitEditing(text: editor.stringValue, movement: .none) }
        sheet?.workbook?.recalculateAll()
    }

    private var selectionIsMultiCell: Bool {
        guard let sheet else { return false }
        let range = sheet.selectedRange
        return range.start.column != range.end.column || range.start.row != range.end.row
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
        case #selector(mergeCells(_:)), #selector(mergeAndCenter(_:)):
            return selectionIsMultiCell
        case #selector(unmergeCells(_:)):
            return sheet.selectionHasMergedCells
        case #selector(freezePanes(_:)):
            if let menuItem = item as? NSMenuItem {
                menuItem.title = sheet.isFrozen ? "Unfreeze Panes" : "Freeze Panes"
            }
            return true
        default:
            return true
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        guard let sheet else { return }
        let point = sheetPoint(forViewPoint: convert(event.locationInWindow, from: nil))
        if !isEditing, event.clickCount == 1,
           fillHandleRect(for: rect(of: sheet.selectedRange, in: sheet)).insetBy(dx: -2, dy: -2).contains(point) {
            fillSource = sheet.selectedRange
            fillTarget = nil
            return
        }
        if isEditing { commitEditing(text: editor.stringValue, movement: .none) }
        window?.makeFirstResponder(self)
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
        guard let sheet else { return }
        if let fillSource {
            autoscroll(with: event)
            let point = sheetPoint(forViewPoint: convert(event.locationInWindow, from: nil))
            let cell = CellCoordinate(column: sheet.column(atX: point.x), row: sheet.row(atY: point.y))
            let target = Self.fillTarget(from: fillSource, toward: cell)
            if fillTarget.map({ $0 != target }) ?? true {
                fillTarget = target
                needsDisplay = true
            }
            return
        }
        guard let anchor = dragAnchor else { return }
        autoscroll(with: event)
        let point = sheetPoint(forViewPoint: convert(event.locationInWindow, from: nil))
        let cell = CellCoordinate(column: sheet.column(atX: point.x), row: sheet.row(atY: point.y))
        let range = Self.range(from: anchor, to: cell)
        let current = sheet.selectedRange
        if range.start.column != current.start.column || range.start.row != current.start.row ||
            range.end.column != current.end.column || range.end.row != current.end.row {
            sheet.selectRange(range, editPosition: anchor)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let sheet, let source = fillSource else { return }
        let target = fillTarget
        fillSource = nil
        fillTarget = nil
        needsDisplay = true
        guard let target, target != source else { return }
        // Option: a single number counts up by one instead of repeating
        // (the GTK Ctrl modifier).
        let increment = event.modifierFlags.contains(.option)
        do {
            try sheet.autofill(from: source, to: target, defaultIncrement: increment)
            sheet.selectRange(target, editPosition: sheet.editPosition)
        } catch {
            presentError?(error)
        }
    }

    /// The fill handle extends the source in one direction only, by whole
    /// multiples of its size (item-cursor.c, cb_autofill_scroll).
    static func fillTarget(from source: CellRange, toward cell: CellCoordinate) -> CellRange {
        var r = source
        let width = source.end.column - source.start.column + 1
        let height = source.end.row - source.start.row + 1
        let north = source.start.row - cell.row, south = cell.row - source.end.row
        let west = source.start.column - cell.column, east = cell.column - source.end.column
        if max(north, south) > max(west, east) {
            if cell.row < source.start.row {
                r.start.row -= height * (north / height)
            } else if cell.row > source.end.row {
                r.end.row += height * (south / height)
            }
        } else {
            if cell.column < source.start.column {
                r.start.column -= width * (west / width)
            } else if cell.column > source.end.column {
                r.end.column += width * (east / width)
            }
        }
        return r
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
        return sheet.row(atY: scrollingVisibleRect.minY)
    }

    private var leftVisibleColumn: Int {
        guard let sheet else { return 0 }
        return sheet.column(atX: scrollingVisibleRect.minX)
    }

    // MARK: Freeze panes (View menu)

    /// Toggle frozen panes.  Freezing follows the GTK rules
    /// (wbc-gtk-actions.c, cb_view_freeze_panes): the edit position is the
    /// first scrolling cell; at A1 a whole-row or whole-column selection
    /// freezes the rows above or the columns before it; a cell on the
    /// window's top edge freezes rows only, one on its left edge columns
    /// only; an edit position out of view, or at the window's top-left,
    /// freezes at the middle of the window.
    @objc func freezePanes(_ sender: Any?) {
        guard let sheet else { return }
        if isEditing { commitEditing(text: editor.stringValue, movement: .none) }
        if sheet.isFrozen {
            sheet.unfreezePanes()
            return
        }
        let visible = visibleRect
        var frozen = CellCoordinate(column: sheet.column(atX: visible.minX), row: sheet.row(atY: visible.minY))
        let last = CellCoordinate(column: sheet.column(atX: visible.maxX - 1), row: sheet.row(atY: visible.maxY - 1))
        var unfrozen = sheet.editPosition
        if unfrozen.column == 0 && unfrozen.row == 0 {
            let first = sheet.selectedRange
            let fullRows = first.start.column == 0 && first.end.column == sheet.columnCount - 1
            let fullColumns = first.start.row == 0 && first.end.row == sheet.rowCount - 1
            if !fullRows && !fullColumns {
                unfrozen = CellCoordinate(column: first.end.column + 1, row: first.end.row + 1)
            } else if fullRows && !fullColumns {
                unfrozen = CellCoordinate(column: 0, row: first.end.row + 1)
            } else if fullColumns && !fullRows {
                unfrozen = CellCoordinate(column: first.end.column + 1, row: 0)
            }
        }
        var center = unfrozen.column < frozen.column || unfrozen.column > last.column
            || unfrozen.row < frozen.row || unfrozen.row > last.row
        if unfrozen.column == frozen.column {
            if unfrozen.row == frozen.row {
                center = true
            } else {
                unfrozen.column = 0; frozen.column = 0
            }
        } else if unfrozen.row == frozen.row {
            unfrozen.row = 0; frozen.row = 0
        }
        if center {
            unfrozen = CellCoordinate(column: (frozen.column + last.column) / 2, row: (frozen.row + last.row) / 2)
        }
        guard unfrozen.column > frozen.column || unfrozen.row > frozen.row else { return }
        sheet.freezePanes(unfrozenTopLeft: unfrozen, frozenTopLeft: frozen)
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

    /// Scroll so the cell shows; a scrolling cell must clear the frozen
    /// strips, a frozen one is always in view.
    func sheet(_ sheet: Sheet, makeVisibleColumn column: Int, row: Int) {
        var frame = sheet.frameOfCell(atColumn: column, row: row)
        if let panes {
            let unfrozen = sheet.unfrozenTopLeft
            if panes.hasColumns {
                if column < unfrozen.column { frame.size.width = 0 } else {
                    frame.origin.x -= panes.width; frame.size.width += panes.width
                }
            }
            if panes.hasRows {
                if row < unfrozen.row { frame.size.height = 0 } else {
                    frame.origin.y -= panes.height; frame.size.height += panes.height
                }
            }
            if frame.width == 0 && frame.height == 0 { return }
            if frame.width == 0 { frame.origin.x = visibleRect.minX; frame.size.width = 1 }
            if frame.height == 0 { frame.origin.y = visibleRect.minY; frame.size.height = 1 }
        }
        scrollToVisible(frame)
    }

    func sheetFrozenPanesDidChange(_ sheet: Sheet) {
        // The clip view's minimum origin changed: re-clamp, then repaint.
        if let clip = enclosingScrollView?.contentView {
            clip.scroll(to: clip.constrainBoundsRect(clip.bounds).origin)
            enclosingScrollView?.reflectScrolledClipView(clip)
        }
        needsDisplay = true
        headerViews.forEach { $0.needsDisplay = true }
        window?.invalidateCursorRects(for: self)
    }
}

/// The grid's clip view: scrolling never goes above the first unfrozen cell.
@MainActor
final class GridClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        if let grid = documentView as? GridView {
            let minimum = grid.minimumScrollOrigin
            bounds.origin.x = max(bounds.origin.x, minimum.x)
            bounds.origin.y = max(bounds.origin.y, minimum.y)
        }
        return bounds
    }
}
