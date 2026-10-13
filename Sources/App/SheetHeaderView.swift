import AppKit
import GnmCocoa

/// Column and row headers: plain views the window controller lays out around
/// the grid's scroll view (above and to the left of it) and that redraw when
/// the clip view scrolls.  Drawn natively; the engine only supplies sizes and
/// names.  Clicking selects whole columns or rows, dragging or shift-clicking
/// extends, and the corner above the row header selects everything.
///
/// They used to be NSRulerView subclasses.  On macOS 26 NSScrollView no longer
/// tiles rulers beside the clip view but overlays them in scroll pockets, and
/// with rulers installed nothing drawn in the document view reached the
/// window at all (docs/progress.md, 2026-10-11).
@MainActor
class SheetHeaderView: NSView {
    static let thickness: CGFloat = 20
    static let rowHeaderWidth: CGFloat = 44

    private(set) weak var gridView: GridView?
    var sheet: Sheet? { gridView?.sheet }
    /// Index (column or row) where the current header drag started.
    var dragAnchor: Int?
    /// A boundary drag in progress: the column (row) being resized, its
    /// size when the drag started, and the mouse position then.
    var resizing: (index: Int, startSize: CGFloat, startPoint: NSPoint)?
    /// Half the width of the strip around a boundary that resizes.
    static let boundaryGrip: CGFloat = 4

    init(gridView: GridView) {
        self.gridView = gridView
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layerContentsRedrawPolicy = .duringViewResize
        // Since macOS 14 views are not clipped by default: draw(_:) then gets
        // a dirty rect covering the whole window and an unclipped context,
        // and the background fill below would paint over the neighbours in
        // any pass where views share a context (window captures).
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    /// item-bar.c ib_compute_pixels_from_indent: the strip for the outline
    /// bars, (levels + 1) × 14 px at the zoom; none without groups or with
    /// Display Outlines off.
    static func outlineIndent(for sheet: Sheet?, columns: Bool) -> CGFloat {
        guard let sheet, sheet.displaysOutlines else { return 0 }
        let levels = columns ? sheet.maximumColumnOutlineLevel : sheet.maximumRowOutlineLevel
        return levels > 0 ? (CGFloat(levels + 1) * 14 * sheet.zoomFactor).rounded() : 0
    }

    var outlineIndent: CGFloat { Self.outlineIndent(for: sheet, columns: isColumnHeader) }

    /// gnm_item_bar_group_size: one level's share of the strip.
    var outlineStep: CGFloat {
        guard let sheet else { return 0 }
        let levels = isColumnHeader ? sheet.maximumColumnOutlineLevel : sheet.maximumRowOutlineLevel
        return levels > 0 ? (outlineIndent - 2) / CGFloat(levels + 1) : 0
    }

    /// A click in the outline strip: the column (row) and the level step
    /// there (outline_button_press), or nil elsewhere.
    func outlineHit(at point: NSPoint) -> (index: Int, step: Int)? { nil }

    /// The strip's bars and toggles for one column or row at its span
    /// along the header: a line per level, a corner where a group begins,
    /// and a box with − (or + when its group is hidden) on the column or
    /// row that ends one (item-bar.c, symbols on the right or below).
    func drawOutline(index: Int, start: CGFloat, size: CGFloat, level: Int, previousLevel: Int, collapsed: Bool, dirtyRect: NSRect) {
        let indent = outlineIndent, inc = outlineStep
        guard indent > 0, inc > 0 else { return }
        let base = 0.2 * inc, len = min(4, inc)
        let strip = isColumnHeader ? NSRect(x: start, y: 0, width: size, height: indent) : NSRect(x: 0, y: start, width: indent, height: size)
        guard strip.intersects(dirtyRect) else { return }
        NSColor.secondaryLabelColor.setStroke()
        NSColor.secondaryLabelColor.setFill()
        let mid = start + size / 2
        func point(_ along: CGFloat, _ across: CGFloat) -> NSPoint { isColumnHeader ? NSPoint(x: along, y: across) : NSPoint(x: across, y: along) }
        let path = NSBezierPath()
        path.lineWidth = 2
        var depth = 1
        while depth <= level {
            let pos = base + CGFloat(depth - 1) * inc
            if depth > previousLevel {
                // the group begins here: from the middle to the far edge, with a tick
                path.move(to: point(mid, pos + len))
                path.line(to: point(mid, pos))
                path.line(to: point(start + size, pos))
            } else {
                path.move(to: point(start, pos))
                path.line(to: point(start + size, pos))
            }
            depth += 1
        }
        path.stroke()
        // the box that ends a group: for each level the previous column (row) had beyond this one
        var ended = previousLevel
        if collapsed { ended = max(ended, level + 1) }
        if ended > level {
            for boxLevel in (level + 1)...ended {
                let pos = base + CGFloat(boxLevel - 1) * inc
                let boxSize = max(6, min(inc - 2, 9))
                let box = isColumnHeader ? NSRect(x: start + 2, y: pos - boxSize / 2, width: boxSize, height: boxSize)
                                         : NSRect(x: pos - boxSize / 2, y: start + 2, width: boxSize, height: boxSize)
                let outline = NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5))
                outline.lineWidth = 1
                NSColor.windowBackgroundColor.setFill()
                box.fill()
                outline.stroke()
                let sign = NSBezierPath()
                sign.lineWidth = 1
                sign.move(to: NSPoint(x: box.minX + 2, y: box.midY))
                sign.line(to: NSPoint(x: box.maxX - 2, y: box.midY))
                if collapsed {
                    sign.move(to: NSPoint(x: box.midX, y: box.minY + 2))
                    sign.line(to: NSPoint(x: box.midX, y: box.maxY - 2))
                }
                sign.stroke()
            }
        }
    }

    /// Header text follows the sheet zoom like the GTK item bar does.
    var font: NSFont {
        let zoom = sheet?.zoomFactor ?? 1
        return NSFont.systemFont(ofSize: max(7, min(NSFont.smallSystemFontSize * zoom, 40)))
    }

    func attributes(selected: Bool) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byClipping
        return [.font: font,
                .foregroundColor: selected ? NSColor.labelColor : NSColor.secondaryLabelColor,
                .paragraphStyle: style]
    }

    func fillBackground(_ rect: NSRect, selected: Bool) {
        NSColor.windowBackgroundColor.setFill()
        rect.fill()
        if selected {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).setFill()
            rect.fill(using: .sourceOver)
        }
    }

    /// The column or row under a point in this view's coordinates.
    func index(at point: NSPoint) -> Int? { nil }

    /// Select from the anchor to `index` (whole columns or rows).
    func select(from anchor: Int, to index: Int) {}

    /// The column (row) whose far edge lies within the grip strip around
    /// `point`, for resizing; nil elsewhere.
    func boundary(at point: NSPoint) -> Int? { nil }

    /// Whether this header resizes columns (true) or rows.
    var isColumnHeader: Bool { true }

    /// The mouse coordinate that matters for this header.
    func along(_ point: NSPoint) -> CGFloat { isColumnHeader ? point.x : point.y }

    func size(of index: Int) -> CGFloat {
        guard let sheet else { return 0 }
        return isColumnHeader ? sheet.width(ofColumn: index) : sheet.height(ofRow: index)
    }

    override func mouseDown(with event: NSEvent) {
        guard let gridView else { return }
        window?.makeFirstResponder(gridView)
        let point = convert(event.locationInWindow, from: nil)
        if let hit = outlineHit(at: point) {
            toggleOutline(at: hit.index, step: hit.step)
            return
        }
        if let index = boundary(at: point) {
            if event.clickCount == 2 {
                // Double-click on a boundary fits the column (row) to its content.
                apply(size: -1, to: index)
                return
            }
            resizing = (index, size(of: index), point)
            return
        }
        guard let index = index(at: point) else {
            cornerClicked()
            return
        }
        if event.modifierFlags.contains(.shift), let anchor = dragAnchor {
            select(from: anchor, to: index)
        } else {
            dragAnchor = index
            select(from: index, to: index)
        }
    }

    /// outline_button_press: collapse or expand the group at a column (row)
    /// and level.
    func toggleOutline(at index: Int, step: Int) {
        guard let gridView, let sheet else { return }
        do {
            try sheet.changeOutline(atIndex: index, columns: isColumnHeader, depth: step)
        } catch {
            gridView.presentError?(error)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let resizing, let gridView {
            // A right-to-left column grows leftward (item-bar.c's rtl case).
            let mirrored = isColumnHeader && gridView.isRightToLeft
            let delta = along(point) - along(resizing.startPoint)
            let size = max(1, resizing.startSize + (mirrored ? -delta : delta))
            let edgeInGrid = (isColumnHeader ? gridView.sheet?.leftEdge(ofColumn: resizing.index)
                                             : gridView.sheet?.topEdge(ofRow: resizing.index)) ?? 0
            gridView.resizeGuide = (isColumnHeader, isColumnHeader ? gridView.viewX(forSheetX: edgeInGrid) + (mirrored ? -size : size)
                                                                    : gridView.viewY(forSheetY: edgeInGrid) + size)
            needsDisplay = true
            return
        }
        guard let anchor = dragAnchor else { return }
        if let index = index(at: point) {
            select(from: anchor, to: index)
        }
        gridView?.autoscroll(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard let resizing else { return }
        self.resizing = nil
        gridView?.resizeGuide = nil
        let point = convert(event.locationInWindow, from: nil)
        let size = max(1, resizing.startSize + along(point) - along(resizing.startPoint))
        if abs(size - resizing.startSize) >= 1 {
            apply(size: Int(size.rounded()), to: resizing.index)
        }
    }

    /// Resize the column (row) at `index`, or every selected one when the
    /// whole-column selection includes it (what the GTK header does).
    /// -1 fits the content.
    func apply(size: Int, to index: Int) {
        guard let sheet, let gridView else { return }
        var range = NSRange(location: index, length: 1)
        let selection = sheet.selectedRange
        let wholeSelection = isColumnHeader
            ? (selection.start.row == 0 && selection.end.row == sheet.rowCount - 1
               && index >= selection.start.column && index <= selection.end.column)
            : (selection.start.column == 0 && selection.end.column == sheet.columnCount - 1
               && index >= selection.start.row && index <= selection.end.row)
        if wholeSelection {
            range = isColumnHeader
                ? NSRange(location: selection.start.column, length: selection.end.column - selection.start.column + 1)
                : NSRange(location: selection.start.row, length: selection.end.row - selection.start.row + 1)
        }
        do {
            try sheet.set(columns: isColumnHeader, in: range, sizeInPixels: size)
        } catch {
            gridView.presentError?(error)
        }
    }

    override func resetCursorRects() {
        guard let gridView, let sheet else { return }
        let cursor: NSCursor = isColumnHeader ? .resizeLeftRight : .resizeUpDown
        let grip = Self.boundaryGrip
        let visible = gridView.visibleRect
        if isColumnHeader {
            let range = gridView.visibleSheetXRange
            var column = sheet.column(atX: range.minX)
            while column < sheet.columnCount {
                let left = sheet.leftEdge(ofColumn: column)
                if left > range.maxX { break }
                let width = sheet.width(ofColumn: column)
                if width > 0 {
                    let edge = convert(NSPoint(x: gridView.viewX(forSheetRightEdge: left + width), y: 0), from: gridView).x
                    addCursorRect(NSRect(x: edge - grip, y: 0, width: 2 * grip, height: bounds.height), cursor: cursor)
                }
                column += 1
            }
        } else {
            var row = sheet.row(atY: visible.minY)
            while row < sheet.rowCount {
                let top = sheet.topEdge(ofRow: row)
                if top > visible.maxY { break }
                let height = sheet.height(ofRow: row)
                if height > 0 {
                    let edge = convert(NSPoint(x: 0, y: gridView.viewY(forSheetY: top + height - 0.5) + 0.5), from: gridView).y
                    addCursorRect(NSRect(x: 0, y: edge - grip, width: bounds.width, height: 2 * grip), cursor: cursor)
                }
                row += 1
            }
        }
    }

    func cornerClicked() {}

    /// The boundary being dragged, in this header.
    func drawResizeGuide() {
        guard let gridView, let guide = gridView.resizeGuide, guide.isColumn == isColumnHeader else { return }
        NSColor.controlAccentColor.setFill()
        if isColumnHeader {
            let x = convert(NSPoint(x: guide.position, y: 0), from: gridView).x
            NSRect(x: x - 1, y: 0, width: 2, height: bounds.height).fill()
        } else {
            let y = convert(NSPoint(x: 0, y: guide.position), from: gridView).y
            NSRect(x: 0, y: y - 1, width: bounds.width, height: 2).fill()
        }
    }

    /// Development aid (GNM_DEBUG_LAYOUT): where a draw lands.
    func logDraw(_ dirtyRect: NSRect) {
        guard ProcessInfo.processInfo.environment["GNM_DEBUG_LAYOUT"] != nil,
              let context = NSGraphicsContext.current?.cgContext else { return }
        let m = context.ctm
        NSLog("%@.draw %@ frame=%@ bounds=%@ ctm=[%g %g %g %g %g %g] clip=%@", String(describing: type(of: self)),
              NSStringFromRect(dirtyRect), NSStringFromRect(frame), NSStringFromRect(bounds), m.a, m.b, m.c, m.d, m.tx, m.ty,
              NSStringFromRect(context.boundingBoxOfClipPath))
    }
}

@MainActor
final class ColumnHeaderView: SheetHeaderView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Self.thickness + outlineIndent) }
    override var isColumnHeader: Bool { true }

    override func outlineHit(at point: NSPoint) -> (index: Int, step: Int)? {
        let indent = outlineIndent, inc = outlineStep
        guard indent > 0, inc > 0, point.y < indent, let index = index(at: point) else { return nil }
        return (index, Int(point.y / inc))
    }

    override func index(at point: NSPoint) -> Int? {
        guard let gridView, let sheet else { return nil }
        let x = gridView.sheetX(forViewX: convert(point, to: gridView).x)
        return x >= 0 ? sheet.column(atX: x) : 0
    }

    override func boundary(at point: NSPoint) -> Int? {
        guard let gridView, let sheet else { return nil }
        let x = gridView.sheetX(forViewX: convert(point, to: gridView).x)
        guard x >= 0 else { return nil }
        // The edge just before or just after the point, within the grip.
        let column = sheet.column(atX: x)
        let left = sheet.leftEdge(ofColumn: column)
        let right = left + sheet.width(ofColumn: column)
        if abs(x - right) <= Self.boundaryGrip { return column }
        if column > 0, abs(x - left) <= Self.boundaryGrip { return column - 1 }
        return nil
    }

    override func select(from anchor: Int, to index: Int) {
        gridView?.selectColumns(from: min(anchor, index), to: max(anchor, index), anchor: anchor)
    }

    override func draw(_ dirtyRect: NSRect) {
        logDraw(dirtyRect)
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.intersection(bounds).fill()
        guard let gridView, let sheet else { return }
        let selection = sheet.selectedRange
        let visible = gridView.visibleRect
        let indent = outlineIndent
        let height = bounds.height - indent
        func drawColumns(from first: Int, to end: Int, maxX: CGFloat) {
            var column = first
            var previousLevel = column > 0 ? sheet.outlineLevel(ofColumn: column - 1) : 0
            while column < end {
                let left = sheet.leftEdge(ofColumn: column)
                if left > maxX { break }
                let width = sheet.width(ofColumn: column)
                if width > 0 {
                    // The column's view edges, in either order on a
                    // right-to-left sheet.
                    let a = convert(NSPoint(x: gridView.viewX(forSheetX: left), y: 0), from: gridView).x
                    let b = convert(NSPoint(x: gridView.viewX(forSheetRightEdge: left + width), y: 0), from: gridView).x
                    let x0 = min(a, b)
                    let cell = NSRect(x: x0, y: indent, width: width, height: height)
                    if cell.intersects(dirtyRect) {
                        let selected = column >= selection.start.column && column <= selection.end.column
                        fillBackground(cell, selected: selected)
                        let name = sheet.name(ofColumn: column) as NSString
                        let attrs = attributes(selected: selected)
                        let size = name.size(withAttributes: attrs)
                        name.draw(in: NSRect(x: cell.minX, y: indent + (height - size.height) / 2, width: cell.width, height: size.height),
                                  withAttributes: attrs)
                        NSColor.separatorColor.setFill()
                        NSRect(x: cell.maxX - 1, y: indent, width: 1, height: height).fill()
                    }
                    let level = sheet.outlineLevel(ofColumn: column)
                    if indent > 0 {
                        drawOutline(index: column, start: x0, size: width, level: level, previousLevel: previousLevel,
                                    collapsed: sheet.isColumnCollapsed(column), dirtyRect: dirtyRect)
                    }
                    previousLevel = level
                }
                column += 1
            }
        }
        let range = gridView.visibleSheetXRange
        drawColumns(from: sheet.column(atX: range.minX), to: sheet.columnCount, maxX: range.maxX)
        if let panes = gridView.panes, panes.hasColumns {
            // The frozen columns, painted over whatever scrolled under them
            // (at the right of a right-to-left sheet).
            let frozen = sheet.frozenTopLeft, unfrozen = sheet.unfrozenTopLeft
            drawColumns(from: frozen.column, to: unfrozen.column, maxX: .greatestFiniteMagnitude)
            NSColor.tertiaryLabelColor.setFill()
            let edge = gridView.isRightToLeft
                ? convert(NSPoint(x: visible.maxX - panes.width, y: 0), from: gridView).x
                : convert(NSPoint(x: visible.minX + panes.width, y: 0), from: gridView).x - 1
            NSRect(x: edge, y: 0, width: 1, height: height).fill()
        }
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        drawResizeGuide()
        window?.invalidateCursorRects(for: self)
    }
}

/// The row header spans the full height of the sheet pane: its top strip,
/// beside the column header, is the select-all corner.
@MainActor
final class RowHeaderView: SheetHeaderView {
    /// The strip beside the column header, as tall as it.
    private var cornerHeight: CGFloat { Self.thickness + Self.outlineIndent(for: sheet, columns: true) }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.rowHeaderWidth + outlineIndent, height: NSView.noIntrinsicMetric) }
    override var isColumnHeader: Bool { false }

    override func outlineHit(at point: NSPoint) -> (index: Int, step: Int)? {
        let indent = outlineIndent, inc = outlineStep
        guard indent > 0, inc > 0, point.x < indent, point.y >= cornerHeight, let index = index(at: point) else { return nil }
        return (index, Int(point.x / inc))
    }

    override func index(at point: NSPoint) -> Int? {
        guard let gridView, let sheet, point.y >= cornerHeight else { return nil }
        let y = gridView.sheetY(forViewY: convert(point, to: gridView).y)
        return y >= 0 ? sheet.row(atY: y) : 0
    }

    override func boundary(at point: NSPoint) -> Int? {
        guard let gridView, let sheet, point.y >= cornerHeight else { return nil }
        let y = gridView.sheetY(forViewY: convert(point, to: gridView).y)
        guard y >= 0 else { return nil }
        let row = sheet.row(atY: y)
        let top = sheet.topEdge(ofRow: row)
        let bottom = top + sheet.height(ofRow: row)
        if abs(y - bottom) <= Self.boundaryGrip { return row }
        if row > 0, abs(y - top) <= Self.boundaryGrip { return row - 1 }
        return nil
    }

    override func select(from anchor: Int, to index: Int) {
        gridView?.selectRows(from: min(anchor, index), to: max(anchor, index), anchor: anchor)
    }

    override func cornerClicked() {
        gridView?.selectAll(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        logDraw(dirtyRect)
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.intersection(bounds).fill()
        guard let gridView, let sheet else { return }
        let selection = sheet.selectedRange
        let visible = gridView.visibleRect
        let indent = outlineIndent
        let width = bounds.width - indent
        func drawRows(from first: Int, to end: Int, maxY: CGFloat) {
            var row = first
            var previousLevel = row > 0 ? sheet.outlineLevel(ofRow: row - 1) : 0
            while row < end {
                let top = sheet.topEdge(ofRow: row)
                if top > maxY { break }
                let height = sheet.height(ofRow: row)
                if height > 0 {
                    let y0 = convert(NSPoint(x: 0, y: gridView.viewY(forSheetY: top)), from: gridView).y
                    let cell = NSRect(x: indent, y: y0, width: width, height: height)
                    if cell.intersects(dirtyRect) {
                        let selected = row >= selection.start.row && row <= selection.end.row
                        fillBackground(cell, selected: selected)
                        let name = sheet.name(ofRow: row) as NSString
                        let attrs = attributes(selected: selected)
                        let size = name.size(withAttributes: attrs)
                        name.draw(in: NSRect(x: indent, y: cell.minY + (height - size.height) / 2, width: width - 4, height: size.height),
                                  withAttributes: attrs)
                        NSColor.separatorColor.setFill()
                        NSRect(x: indent, y: cell.maxY - 1, width: width, height: 1).fill()
                    }
                    let level = sheet.outlineLevel(ofRow: row)
                    if indent > 0 {
                        drawOutline(index: row, start: y0, size: height, level: level, previousLevel: previousLevel,
                                    collapsed: sheet.isRowCollapsed(row), dirtyRect: dirtyRect)
                    }
                    previousLevel = level
                }
                row += 1
            }
        }
        drawRows(from: sheet.row(atY: visible.minY), to: sheet.rowCount, maxY: visible.maxY)
        if let panes = gridView.panes, panes.hasRows {
            let frozen = sheet.frozenTopLeft, unfrozen = sheet.unfrozenTopLeft
            drawRows(from: frozen.row, to: unfrozen.row, maxY: .greatestFiniteMagnitude)
            NSColor.tertiaryLabelColor.setFill()
            let edge = convert(NSPoint(x: 0, y: visible.minY + panes.height), from: gridView).y
            NSRect(x: 0, y: edge - 1, width: width, height: 1).fill()
        }
        // The select-all corner: a small triangle pointing at A1.
        let corner = NSRect(x: 0, y: 0, width: bounds.width, height: cornerHeight)
        if corner.intersects(dirtyRect) {
            NSColor.windowBackgroundColor.setFill()
            corner.fill()
            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: width - 4, y: cornerHeight - 4))
            triangle.line(to: NSPoint(x: width - 14, y: cornerHeight - 4))
            triangle.line(to: NSPoint(x: width - 4, y: cornerHeight - 14))
            triangle.close()
            NSColor.tertiaryLabelColor.setFill()
            triangle.fill()
            NSColor.separatorColor.setFill()
            NSRect(x: 0, y: cornerHeight - 1, width: width, height: 1).fill()
        }
        NSRect(x: width - 1, y: 0, width: 1, height: bounds.height).fill()
        drawResizeGuide()
        window?.invalidateCursorRects(for: self)
    }
}
