import AppKit
import GnmCocoa

/// The cell grid: a flipped view whose coordinates are the sheet's pixel
/// coordinates, drawn by the engine through the bridge, with the selection
/// painted natively on top.
@MainActor
final class GridView: NSView, SheetDelegate, NSUserInterfaceValidations {
    var sheet: Sheet? {
        didSet {
            guard oldValue !== sheet else { return }
            if isEditing { cancelEditing() }
            selectedObjects = []
            objectDrag = nil
            if let old = oldValue, old.delegate === self {
                old.delegate = nil
            }
            sheet?.delegate = self
            updateFrameSize()
            updateCommentToolTips()
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
        drawFilterButtons(of: sheet, dirtyRect: dirtyRect)
        drawCommentMarkers(of: sheet, dirtyRect: dirtyRect)
        drawMarchingAnts(of: sheet, dirtyRect: dirtyRect)
        drawSelection(of: sheet, dirtyRect: dirtyRect)
        drawObjectSelection(dirtyRect: dirtyRect)
    }

    private func drawSelection(of sheet: Sheet, dirtyRect: NSRect) {
        let selection = rect(of: sheet.selectedRange, in: sheet)
        lastSelectionRect = selection
        // The cell cursor hides while objects are selected (the GTK object mode).
        guard selectedObjects.isEmpty, selection.intersects(dirtyRect) else { return }
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
        if selectedObjects.isEmpty {
            addCursorRect(viewRect(forSheetRect: fillHandleRect(for: rect(of: sheet.selectedRange, in: sheet))).insetBy(dx: -2, dy: -2),
                          cursor: .crosshair)
            return
        }
        for object in selectedObjects {
            addCursorRect(viewRect(forSheetRect: object.frame), cursor: .openHand)
            guard object.canResize else { continue }
            for (index, handle) in handleRects(for: object.frame).enumerated() {
                let cursor: NSCursor = [1, 6].contains(index) ? .resizeUpDown : [3, 4].contains(index) ? .resizeLeftRight : .crosshair
                addCursorRect(viewRect(forSheetRect: handle).insetBy(dx: -2, dy: -2), cursor: cursor)
            }
        }
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
        // The session ends before the command runs: a first-responder
        // change while the engine works would otherwise end the editor's
        // editing and commit a second time.
        endEditingSession()
        do {
            try sheet.setText(text, atColumn: cell.column, row: cell.row, autocorrect: true)
        } catch {
            presentError?(error)
            sheet.selectCell(atColumn: cell.column, row: cell.row)
            beginEditing(initialText: text)
            return
        }
        switch movement {
        case .enter: moveAfterReturn()
        case .down: move(columns: 0, rows: 1, extend: false)
        case .up: move(columns: 0, rows: -1, extend: false)
        case .right: move(columns: 1, rows: 0, extend: false)
        case .left: move(columns: -1, rows: 0, extend: false)
        case .none: break
        }
    }

    /// Where Return moves: the preference (`core/gui/editing/enter_moves_dir`),
    /// down unless changed in Settings.
    private func moveAfterReturn() {
        switch Engine.shared?.preferences.enterMovesDirection ?? .down {
        case .up: move(columns: 0, rows: -1, extend: false)
        case .left: move(columns: -1, rows: 0, extend: false)
        case .right: move(columns: 1, rows: 0, extend: false)
        default: move(columns: 0, rows: 1, extend: false)
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
        if !selectedObjects.isEmpty {
            deleteSelectedObjects()
            return
        }
        do {
            try sheet.clearSelection(.values)
        } catch {
            presentError?(error)
        }
    }

    // MARK: Sheet objects (Phase 4)

    /// The selected objects; the cell cursor hides while any is selected.
    private(set) var selectedObjects: [SheetObject] = []
    /// A drag of the selected objects.  `handle` 0 to 7 resizes by the
    /// GTK control point indexes (top-left, top, top-right, left, right,
    /// bottom-left, bottom, bottom-right); 8 moves.
    private struct ObjectDrag {
        let handle: Int
        let start: NSPoint
        let originalFrames: [NSRect]
        var frames: [NSRect]
        var moved: Bool { frames != originalFrames }
    }
    private var objectDrag: ObjectDrag?
    static let objectHandleSize: CGFloat = 7
    /// Which edges a handle drags (sheet-control-gui.c drag_object):
    /// coordinate 0 or 2 for x, 1 or 3 for y, -1 for neither.
    private static let handleEdges: [(x: Int, y: Int)] = [(0, 1), (-1, 1), (2, 1), (0, -1), (2, -1), (0, 3), (-1, 3), (2, 3)]

    func select(objects: [SheetObject]) {
        let attached = objects.filter { $0.isAttached }
        guard attached != selectedObjects else { return }
        selectedObjects = attached
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func deselectObjects() {
        select(objects: [])
    }

    func handleRects(for frame: NSRect) -> [NSRect] {
        let s = Self.objectHandleSize
        let xs = [frame.minX, frame.midX, frame.maxX], ys = [frame.minY, frame.midY, frame.maxY]
        let corners = [(0, 0), (1, 0), (2, 0), (0, 1), (2, 1), (0, 2), (1, 2), (2, 2)]
        return corners.map { NSRect(x: xs[$0.0] - s / 2, y: ys[$0.1] - s / 2, width: s, height: s) }
    }

    /// The handle of a selected, resizable object under a sheet point.
    private func handleHit(at point: NSPoint) -> Int? {
        for object in selectedObjects where object.canResize {
            if let index = handleRects(for: object.frame).firstIndex(where: { $0.insetBy(dx: -2, dy: -2).contains(point) }) {
                return index
            }
        }
        return nil
    }

    private func drawObjectSelection(dirtyRect: NSRect) {
        for (i, object) in selectedObjects.enumerated() {
            let frame = objectDrag.map { $0.frames[i] } ?? object.frame
            guard frame.insetBy(dx: -8, dy: -8).intersects(dirtyRect) else { continue }
            let outline = NSBezierPath(rect: frame.insetBy(dx: -0.5, dy: -0.5))
            outline.lineWidth = 1
            if objectDrag?.moved == true {
                outline.setLineDash([4, 3], count: 2, phase: 0)
            }
            NSColor.controlAccentColor.setStroke()
            outline.stroke()
            guard object.canResize else { continue }
            for handle in handleRects(for: frame) {
                NSColor.white.setFill()
                handle.fill()
                let border = NSBezierPath(rect: handle.insetBy(dx: 0.5, dy: 0.5))
                NSColor.controlAccentColor.setStroke()
                border.stroke()
            }
        }
    }

    /// The frames after a drag by (dx, dy): a move shifts every frame;
    /// a handle drags its edges, both opposite edges with Option
    /// (symmetric), and Shift snaps the dragged edges to the grid.
    private func draggedFrames(_ drag: ObjectDrag, dx: CGFloat, dy: CGFloat, symmetric: Bool, snap: Bool) -> [NSRect] {
        guard let sheet else { return drag.originalFrames }
        func snapped(_ value: CGFloat, column: Bool) -> CGFloat {
            let index = column ? sheet.column(atX: value) : sheet.row(atY: value)
            let low = column ? sheet.leftEdge(ofColumn: index) : sheet.topEdge(ofRow: index)
            let high = column ? sheet.leftEdge(ofColumn: index + 1) : sheet.topEdge(ofRow: index + 1)
            return abs(value - low) < abs(value - high) ? low : high
        }
        return drag.originalFrames.map { original in
            var c = [original.minX, original.minY, original.maxX, original.maxY]
            if drag.handle == 8 {
                var x = c[0] + dx, y = c[1] + dy
                if snap { x = snapped(x, column: true); y = snapped(y, column: false) }
                c[2] += x - c[0]; c[3] += y - c[1]
                c[0] = x; c[1] = y
            } else {
                let edges = Self.handleEdges[drag.handle]
                if edges.x >= 0 {
                    var x = c[edges.x] + dx
                    if snap { x = snapped(x, column: true) }
                    if symmetric { c[edges.x == 0 ? 2 : 0] -= x - c[edges.x] }
                    c[edges.x] = x
                }
                if edges.y >= 0 {
                    var y = c[edges.y] + dy
                    if snap { y = snapped(y, column: false) }
                    if symmetric { c[edges.y == 1 ? 3 : 1] -= y - c[edges.y] }
                    c[edges.y] = y
                }
            }
            return NSRect(x: min(c[0], c[2]), y: min(c[1], c[3]), width: abs(c[2] - c[0]), height: abs(c[3] - c[1]))
        }
    }

    private func commitObjectDrag(_ drag: ObjectDrag) {
        guard let sheet, drag.moved else { return }
        do {
            try sheet.setFrames(drag.frames.map { NSValue(rect: $0) }, of: selectedObjects, resizing: drag.handle != 8)
        } catch {
            presentError?(error)
        }
    }

    /// Nudge the selected objects (arrow keys), one pixel, ten with Shift.
    private func nudgeObjects(dx: CGFloat, dy: CGFloat) {
        guard let sheet, !selectedObjects.isEmpty else { return }
        let frames = selectedObjects.map { $0.frame.offsetBy(dx: dx, dy: dy) }
        do {
            try sheet.setFrames(frames.map { NSValue(rect: $0) }, of: selectedObjects, resizing: false)
        } catch {
            presentError?(error)
        }
    }

    func deleteSelectedObjects() {
        guard let sheet, !selectedObjects.isEmpty else { return }
        let doomed = selectedObjects
        deselectObjects()
        do {
            try sheet.deleteSheetObjects(doomed)
        } catch {
            presentError?(error)
        }
    }

    /// Tab cycles through the sheet's selectable objects (scg_object_select_next).
    private func selectNextObject(reverse: Bool) {
        guard let sheet else { return }
        let candidates = sheet.sheetObjects.filter { $0.isSelectable && $0.isVisible }
        guard !candidates.isEmpty else { return }
        guard let current = selectedObjects.first, let index = candidates.firstIndex(of: current) else {
            select(objects: [candidates[0]])
            return
        }
        let next = reverse ? (index + 1) % candidates.count : (index + candidates.count - 1) % candidates.count
        select(objects: [candidates[next]])
    }

    /// Where a new object of `size` goes: beside the selection when that
    /// fits in view, else near the top-left of the visible area.
    func suggestedFrameForNewObject(size: NSSize) -> NSRect {
        guard let sheet else { return NSRect(origin: .zero, size: size) }
        let visible = scrollingVisibleRect
        let selection = rect(of: sheet.selectedRange, in: sheet)
        let beside = NSRect(x: selection.maxX + 16, y: selection.minY, width: size.width, height: size.height)
        if visible.contains(beside) {
            return beside
        }
        return NSRect(x: visible.minX + 24, y: visible.minY + 24, width: size.width, height: size.height)
    }

    @objc func deleteObjects(_ sender: Any?) { deleteSelectedObjects() }
    @objc func pullObjectToFront(_ sender: Any?) { restackSelectedObject(.pullToFront) }
    @objc func pullObjectForward(_ sender: Any?) { restackSelectedObject(.pullForward) }
    @objc func pushObjectBackward(_ sender: Any?) { restackSelectedObject(.pushBackward) }
    @objc func pushObjectToBack(_ sender: Any?) { restackSelectedObject(.pushToBack) }

    private func restackSelectedObject(_ direction: SheetObject.Stacking) {
        guard let sheet, let object = selectedObjects.first else { return }
        do {
            try sheet.restack(object, direction)
        } catch {
            presentError?(error)
        }
    }

    /// Right-click on an object: the GTK object menu's delete and order items.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let sheet else { return nil }
        let point = sheetPoint(forViewPoint: convert(event.locationInWindow, from: nil))
        guard let object = sheet.sheetObject(at: point) else {
            // A cell: its comment.
            if isEditing { commitEditing(text: editor.stringValue, movement: .none) }
            let cell = CellCoordinate(column: sheet.column(atX: point.x), row: sheet.row(atY: point.y))
            let selection = sheet.selectedRange
            let inside = cell.column >= selection.start.column && cell.column <= selection.end.column
                && cell.row >= selection.start.row && cell.row <= selection.end.row
            if !inside || sheet.editPosition.column != cell.column || sheet.editPosition.row != cell.row {
                sheet.selectCell(atColumn: cell.column, row: cell.row)
            }
            let menu = NSMenu(title: "Cell")
            if sheet.comment(atColumn: cell.column, row: cell.row) != nil {
                menu.addItem(withTitle: "Edit Comment…", action: #selector(insertComment(_:)), keyEquivalent: "")
                menu.addItem(withTitle: "Delete Comment", action: #selector(deleteComment(_:)), keyEquivalent: "")
            } else {
                menu.addItem(withTitle: "Insert Comment…", action: #selector(insertComment(_:)), keyEquivalent: "")
            }
            return menu
        }
        if !selectedObjects.contains(object) {
            select(objects: [object])
        }
        let menu = NSMenu(title: "Object")
        if object.typeName == "SheetObjectGraph" {
            menu.addItem(withTitle: "Properties…", action: #selector(editObjectProperties(_:)), keyEquivalent: "")
        }
        if !sheet.imageFormats(for: object).isEmpty {
            menu.addItem(withTitle: "Save as Image…", action: #selector(saveObjectAsImage(_:)), keyEquivalent: "")
        }
        if menu.items.count > 0 {
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Delete", action: #selector(deleteObjects(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Pull to Front", action: #selector(pullObjectToFront(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Pull Forward", action: #selector(pullObjectForward(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Push Backward", action: #selector(pushObjectBackward(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Push to Back", action: #selector(pushObjectToBack(_:)), keyEquivalent: "")
        return menu
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
        if !selectedObjects.isEmpty {
            sheet?.copySheetObjects(selectedObjects, cut: false)
            return
        }
        sheet?.copySelection()
    }

    @objc func cut(_ sender: Any?) {
        if isEditing { commitEditing(text: editor.stringValue, movement: .none) }
        if !selectedObjects.isEmpty {
            let doomed = selectedObjects
            deselectObjects()
            sheet?.copySheetObjects(doomed, cut: true)   // the engine deletes them now
            return
        }
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

    /// Insert → Current Date, Time, Date and Time: typed into the editor
    /// when one is open, else into the current cell (the GTK actions put
    /// the text on the edit line).
    private func insertDateTime(date: Bool, time: Bool) {
        guard let sheet else { return }
        let text = sheet.currentDateTimeText(date: date, time: time)
        if isEditing, let fieldEditor = editor.currentEditor() as? NSTextView {
            fieldEditor.insertText(text, replacementRange: fieldEditor.selectedRange())
            editingTextDidChange?(editor.stringValue)
            return
        }
        run { sheet in
            let cell = sheet.editPosition
            try sheet.setText(text, atColumn: cell.column, row: cell.row, autocorrect: false)
        }
    }

    @objc func insertCurrentDate(_ sender: Any?) { insertDateTime(date: true, time: false) }
    @objc func insertCurrentTime(_ sender: Any?) { insertDateTime(date: false, time: true) }
    @objc func insertCurrentDateTime(_ sender: Any?) { insertDateTime(date: true, time: true) }

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

    @objc func sortAscending(_ sender: Any?) { run { try $0.sortSelection(descending: false) } }
    @objc func sortDescending(_ sender: Any?) { run { try $0.sortSelection(descending: true) } }

    // MARK: Autofilter (Data → Filter)

    /// Set by the window controller: the "(Custom…)" and "(Top 10…)"
    /// choices need a dialog (`custom` says which).
    var requestFilterDialog: ((_ button: FilterButton, _ choices: FilterChoices, _ custom: Bool) -> Void)?
    /// Set by the window controller: a double-click on an object, or
    /// Properties… for it, opens its editor (charts have one).
    var requestObjectEditor: ((SheetObject) -> Void)?

    /// Format → Object Properties… and the context menu's Properties…
    @objc func editObjectProperties(_ sender: Any?) {
        guard let object = selectedObjects.first else { return }
        requestObjectEditor?(object)
    }

    /// Set by the window controller: the context menu's Save as Image…
    /// needs a save panel.
    var requestObjectImageSave: ((SheetObject) -> Void)?

    @objc func saveObjectAsImage(_ sender: Any?) {
        guard let object = selectedObjects.first else { return }
        requestObjectImageSave?(object)
    }
    private var filterMenuButton: FilterButton?
    private var filterMenuChoices: FilterChoices?

    @objc func toggleAutofilter(_ sender: Any?) { run { try $0.toggleAutofilter() } }
    @objc func showAllFilteredRows(_ sender: Any?) {
        guard let sheet else { return }
        if isEditing { commitEditing(text: editor.stringValue, movement: .none) }
        sheet.showAllFilteredRows()
    }
    @objc func clearAllFiltered(_ sender: Any?) {
        run { try $0.clearSelection([.values, .formats, .comments, .objects, .filteredRowsOnly]) }
    }
    @objc func clearFormatsFiltered(_ sender: Any?) { run { try $0.clearSelection([.formats, .filteredRowsOnly]) } }
    @objc func clearCommentsFiltered(_ sender: Any?) { run { try $0.clearSelection([.comments, .filteredRowsOnly]) } }
    @objc func clearContentsFiltered(_ sender: Any?) { run { try $0.clearSelection([.values, .filteredRowsOnly]) } }

    /// The drop-down buttons of the sheet's autofilters: a small rounded
    /// square with a triangle in each heading cell, filled with the accent
    /// color while the field has a condition (the GTK arrow's checked state).
    // MARK: Comments

    /// The GTK comment indicator: a small red triangle in the cell's
    /// top-right corner (`comment_view_set_bounds`).
    private static let commentMarkerSize: CGFloat = 6

    private func drawCommentMarkers(of sheet: Sheet, dirtyRect: NSRect) {
        let range = CellRange(start: CellCoordinate(column: sheet.column(atX: dirtyRect.minX), row: sheet.row(atY: dirtyRect.minY)),
                              end: CellCoordinate(column: sheet.column(atX: dirtyRect.maxX), row: sheet.row(atY: dirtyRect.maxY)))
        let comments = sheet.comments(in: range)
        guard !comments.isEmpty else { return }
        NSColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1).setFill()
        for comment in comments {
            let frame = sheet.frameOfCell(atColumn: comment.column, row: comment.row)
            guard !frame.isEmpty, frame.intersects(dirtyRect) else { continue }
            let size = min(Self.commentMarkerSize, frame.width, frame.height)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: frame.maxX - size, y: frame.minY + 1))
            path.line(to: NSPoint(x: frame.maxX, y: frame.minY + 1))
            path.line(to: NSPoint(x: frame.maxX, y: frame.minY + 1 + size))
            path.close()
            path.fill()
        }
    }

    /// One tool tip rect per commented cell, so hovering shows the
    /// comment (the GTK pane shows it when the pointer enters the marker).
    private func updateCommentToolTips() {
        removeAllToolTips()
        guard let sheet else { return }
        let whole = CellRange(start: CellCoordinate(column: 0, row: 0),
                              end: CellCoordinate(column: sheet.columnCount - 1, row: sheet.rowCount - 1))
        for comment in sheet.comments(in: whole) {
            let frame = viewRect(forSheetRect: sheet.frameOfCell(atColumn: comment.column, row: comment.row))
            if !frame.isEmpty {
                addToolTip(frame, owner: self, userData: nil)
            }
        }
    }

    /// What the tool tip over a cell says: the author, then the text.
    func commentToolTip(atColumn column: Int, row: Int) -> String? {
        guard let comment = sheet?.comment(atColumn: column, row: row) else { return nil }
        return comment.author.isEmpty ? comment.text : "\(comment.author):\n\(comment.text)"
    }

    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData: UnsafeMutableRawPointer?) -> String {
        guard let sheet else { return "" }
        let p = sheetPoint(forViewPoint: point)
        return commentToolTip(atColumn: sheet.column(atX: p.x), row: sheet.row(atY: p.y)) ?? ""
    }

    /// Insert → Comment… and the cell's context menu: the editor for the
    /// edit position's comment, provided by the window controller.
    var requestCommentEditor: ((CellCoordinate) -> Void)?

    @objc func insertComment(_ sender: Any?) {
        guard let sheet else { return }
        if isEditing { commitEditing(text: editor.stringValue, movement: .none) }
        requestCommentEditor?(sheet.editPosition)
    }

    @objc func deleteComment(_ sender: Any?) {
        guard let sheet else { return }
        let cell = sheet.editPosition
        run { try $0.setComment("", author: "", atColumn: cell.column, row: cell.row) }
    }

    private func drawFilterButtons(of sheet: Sheet, dirtyRect: NSRect) {
        for button in sheet.filterButtons {
            let frame = button.frame
            guard !frame.isEmpty, frame.intersects(dirtyRect) else { continue }
            // Fixed colors: the grid is drawn white whatever the appearance.
            let box = frame.insetBy(dx: 1.5, dy: 1.5)
            let path = NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2)
            (button.isActive ? NSColor.controlAccentColor : NSColor.white).setFill()
            path.fill()
            (button.isActive ? NSColor.controlAccentColor : NSColor(white: 0.55, alpha: 1)).setStroke()
            path.lineWidth = 1
            path.stroke()
            let w = box.width * 0.5, h = box.height * 0.3   // the triangle points down (flipped view)
            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: box.midX - w / 2, y: box.midY - h / 2))
            triangle.line(to: NSPoint(x: box.midX + w / 2, y: box.midY - h / 2))
            triangle.line(to: NSPoint(x: box.midX, y: box.midY + h / 2))
            triangle.close()
            (button.isActive ? NSColor.white : NSColor(white: 0.2, alpha: 1)).setFill()
            triangle.fill()
        }
    }

    /// The button's list (fcombo_create_list): All, Top 10…, Custom…, the
    /// column's values, and Blanks / Non Blanks when the column has blanks.
    private func showFilterMenu(for button: FilterButton, event: NSEvent) {
        guard let sheet else { return }
        let choices = sheet.choices(for: button)
        let current = choices.current
        let menu = NSMenu(title: "Filter")
        @discardableResult
        func add(_ title: String, _ condition: FilterCondition?, checked: Bool, tag: Int = 0) -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: #selector(filterChoiceSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = condition
            item.state = checked ? .on : .off
            item.tag = tag
            return item
        }
        add("(All)", .showAll(), checked: current.kind == .showAll)
        add("(Top 10…)", nil, checked: current.kind == .bucket, tag: 1)
        add("(Custom…)", nil, checked: current.kind == .custom, tag: 2)
        if !choices.values.isEmpty {
            menu.addItem(.separator())
        }
        for (i, value) in choices.values.enumerated() {
            add(value, choices.condition(forValueAt: i), checked: current.kind == .value && current.valueIndex == i)
        }
        if choices.hasBlanks {
            menu.addItem(.separator())
            add("(Blanks)", .blanks(true), checked: current.kind == .blanks)
            add("(Non Blanks)", .blanks(false), checked: current.kind == .nonBlanks)
        }
        filterMenuButton = button
        filterMenuChoices = choices
        let frame = viewRect(forSheetRect: button.frame)
        menu.popUp(positioning: nil, at: NSPoint(x: frame.minX, y: frame.maxY), in: self)
    }

    @objc private func filterChoiceSelected(_ item: NSMenuItem) {
        guard let button = filterMenuButton, let choices = filterMenuChoices else { return }
        filterMenuButton = nil
        filterMenuChoices = nil
        switch item.tag {
        case 1: requestFilterDialog?(button, choices, false)
        case 2: requestFilterDialog?(button, choices, true)
        default:
            guard let condition = item.representedObject as? FilterCondition else { return }
            applyFilterCondition(condition, to: button)
        }
    }

    func applyFilterCondition(_ condition: FilterCondition, to button: FilterButton) {
        guard let sheet else { return }
        do {
            try sheet.setFilterCondition(condition, for: button)
        } catch {
            presentError?(error)
        }
    }

    /// Paste Special, with the options the window controller collected.
    func paste(options: PasteOptions) {
        if isEditing { commitEditing(text: editor.stringValue, movement: .none) }
        sheet?.paste(options: options)
    }

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
            return sheet.workbook?.canPaste ?? false
        case #selector(mergeCells(_:)), #selector(mergeAndCenter(_:)):
            return selectionIsMultiCell
        case #selector(unmergeCells(_:)):
            return sheet.selectionHasMergedCells
        case #selector(freezePanes(_:)):
            if let menuItem = item as? NSMenuItem {
                menuItem.title = sheet.isFrozen ? "Unfreeze Panes" : "Freeze Panes"
            }
            return true
        case #selector(toggleAutofilter(_:)):
            if let menuItem = item as? NSMenuItem {
                menuItem.title = sheet.editPositionIsInFilter ? "Remove Auto Filter" : "Add Auto Filter"
            }
            return true
        case #selector(showAllFilteredRows(_:)), #selector(clearAllFiltered(_:)), #selector(clearFormatsFiltered(_:)),
             #selector(clearCommentsFiltered(_:)), #selector(clearContentsFiltered(_:)):
            return sheet.hasFilteredRows
        case #selector(insertComment(_:)):
            if let menuItem = item as? NSMenuItem, menuItem.menu?.title != "Cell" {
                let cell = sheet.editPosition
                menuItem.title = sheet.comment(atColumn: cell.column, row: cell.row) == nil ? "Comment…" : "Edit Comment…"
            }
            return window?.attachedSheet == nil
        case #selector(deleteComment(_:)):
            let cell = sheet.editPosition
            return sheet.comment(atColumn: cell.column, row: cell.row) != nil
        case #selector(editObjectProperties(_:)):
            return selectedObjects.count == 1 && selectedObjects[0].typeName == "SheetObjectGraph" && window?.attachedSheet == nil
        case #selector(saveObjectAsImage(_:)):
            return selectedObjects.count == 1 && !sheet.imageFormats(for: selectedObjects[0]).isEmpty && window?.attachedSheet == nil
        default:
            return true
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        guard let sheet else { return }
        let point = sheetPoint(forViewPoint: convert(event.locationInWindow, from: nil))
        if event.clickCount == 1, let button = sheet.filterButtons.first(where: { $0.frame.contains(point) }) {
            if isEditing { commitEditing(text: editor.stringValue, movement: .none) }
            window?.makeFirstResponder(self)
            showFilterMenu(for: button, event: event)
            return
        }
        if !isEditing, event.clickCount == 1, let handle = handleHit(at: point) {
            let frames = selectedObjects.map(\.frame)
            objectDrag = ObjectDrag(handle: handle, start: point, originalFrames: frames, frames: frames)
            return
        }
        if let object = sheet.sheetObject(at: point) {
            if isEditing { commitEditing(text: editor.stringValue, movement: .none) }
            window?.makeFirstResponder(self)
            let additive = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
            if selectedObjects.contains(object) {
                if additive {
                    select(objects: selectedObjects.filter { $0 != object })
                    return
                }
            } else {
                select(objects: additive ? selectedObjects + [object] : [object])
            }
            if event.clickCount == 1 {
                let frames = selectedObjects.map(\.frame)
                objectDrag = ObjectDrag(handle: 8, start: point, originalFrames: frames, frames: frames)
            } else if event.clickCount == 2 {
                requestObjectEditor?(object)
            }
            return
        }
        if !selectedObjects.isEmpty {
            deselectObjects()   // a click on the cells leaves the object mode
        }
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
        if var drag = objectDrag {
            autoscroll(with: event)
            let point = sheetPoint(forViewPoint: convert(event.locationInWindow, from: nil))
            drag.frames = draggedFrames(drag, dx: point.x - drag.start.x, dy: point.y - drag.start.y,
                                        symmetric: event.modifierFlags.contains(.option), snap: event.modifierFlags.contains(.shift))
            objectDrag = drag
            needsDisplay = true
            return
        }
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
        if let drag = objectDrag {
            objectDrag = nil
            commitObjectDrag(drag)
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            return
        }
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
            deselectObjects()
            beginEditing(initialText: chars)
            return
        }
        if !selectedObjects.isEmpty, event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
           let key = event.charactersIgnoringModifiers?.unicodeScalars.first?.value {
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            switch Int(key) {
            case NSLeftArrowFunctionKey: nudgeObjects(dx: -step, dy: 0); return
            case NSRightArrowFunctionKey: nudgeObjects(dx: step, dy: 0); return
            case NSUpArrowFunctionKey: nudgeObjects(dx: 0, dy: -step); return
            case NSDownArrowFunctionKey: nudgeObjects(dx: 0, dy: step); return
            default: break
            }
        }
        interpretKeyEvents([event])
    }

    override func cancelOperation(_ sender: Any?) {
        deselectObjects()
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
    override func insertTab(_ sender: Any?) {
        if selectedObjects.isEmpty { move(columns: 1, rows: 0, extend: false) } else { selectNextObject(reverse: false) }
    }
    override func insertBacktab(_ sender: Any?) {
        if selectedObjects.isEmpty { move(columns: -1, rows: 0, extend: false) } else { selectNextObject(reverse: true) }
    }
    override func insertNewline(_ sender: Any?) { moveAfterReturn() }

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
        updateCommentToolTips()
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

    func sheetObjectsDidChange(_ sheet: Sheet) {
        updateCommentToolTips()
        let survivors = selectedObjects.filter { $0.isAttached }
        if survivors.count != selectedObjects.count {
            selectedObjects = survivors
            window?.invalidateCursorRects(for: self)
        }
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
