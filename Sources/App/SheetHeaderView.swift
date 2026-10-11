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

    override func mouseDown(with event: NSEvent) {
        guard let gridView else { return }
        window?.makeFirstResponder(gridView)
        let point = convert(event.locationInWindow, from: nil)
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

    override func mouseDragged(with event: NSEvent) {
        guard let anchor = dragAnchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let index = index(at: point) {
            select(from: anchor, to: index)
        }
        gridView?.autoscroll(with: event)
    }

    func cornerClicked() {}

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
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Self.thickness) }

    override func index(at point: NSPoint) -> Int? {
        guard let gridView, let sheet else { return nil }
        let x = convert(point, to: gridView).x
        return x >= 0 ? sheet.column(atX: x) : 0
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
        var column = sheet.column(atX: visible.minX)
        let height = bounds.height
        NSColor.separatorColor.setFill()
        while column < sheet.columnCount {
            let left = sheet.leftEdge(ofColumn: column)
            if left > visible.maxX { break }
            let width = sheet.width(ofColumn: column)
            if width > 0 {
                let x0 = convert(NSPoint(x: left, y: 0), from: gridView).x
                let cell = NSRect(x: x0, y: 0, width: width, height: height)
                if cell.intersects(dirtyRect) {
                    let selected = column >= selection.start.column && column <= selection.end.column
                    fillBackground(cell, selected: selected)
                    let name = sheet.name(ofColumn: column) as NSString
                    let attrs = attributes(selected: selected)
                    let size = name.size(withAttributes: attrs)
                    name.draw(in: NSRect(x: cell.minX, y: (height - size.height) / 2, width: cell.width, height: size.height),
                              withAttributes: attrs)
                    NSColor.separatorColor.setFill()
                    NSRect(x: cell.maxX - 1, y: 0, width: 1, height: height).fill()
                }
            }
            column += 1
        }
        NSRect(x: 0, y: height - 1, width: bounds.width, height: 1).fill()
    }
}

/// The row header spans the full height of the sheet pane: its top strip,
/// beside the column header, is the select-all corner.
@MainActor
final class RowHeaderView: SheetHeaderView {
    private var cornerHeight: CGFloat { Self.thickness }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.rowHeaderWidth, height: NSView.noIntrinsicMetric) }

    override func index(at point: NSPoint) -> Int? {
        guard let gridView, let sheet, point.y >= cornerHeight else { return nil }
        let y = convert(point, to: gridView).y
        return y >= 0 ? sheet.row(atY: y) : 0
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
        var row = sheet.row(atY: visible.minY)
        let width = bounds.width
        while row < sheet.rowCount {
            let top = sheet.topEdge(ofRow: row)
            if top > visible.maxY { break }
            let height = sheet.height(ofRow: row)
            if height > 0 {
                let y0 = convert(NSPoint(x: 0, y: top), from: gridView).y
                let cell = NSRect(x: 0, y: y0, width: width, height: height)
                if cell.intersects(dirtyRect) {
                    let selected = row >= selection.start.row && row <= selection.end.row
                    fillBackground(cell, selected: selected)
                    let name = sheet.name(ofRow: row) as NSString
                    let attrs = attributes(selected: selected)
                    let size = name.size(withAttributes: attrs)
                    name.draw(in: NSRect(x: 0, y: cell.minY + (height - size.height) / 2, width: width - 4, height: size.height),
                              withAttributes: attrs)
                    NSColor.separatorColor.setFill()
                    NSRect(x: 0, y: cell.maxY - 1, width: width, height: 1).fill()
                }
            }
            row += 1
        }
        // The select-all corner: a small triangle pointing at A1.
        let corner = NSRect(x: 0, y: 0, width: width, height: cornerHeight)
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
    }
}
