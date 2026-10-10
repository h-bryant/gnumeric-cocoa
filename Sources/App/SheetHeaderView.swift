import AppKit
import GnmCocoa

/// Column and row headers as ruler views, so NSScrollView keeps them in step
/// with the grid.  Drawn natively; the engine only supplies sizes and names.
@MainActor
class SheetHeaderView: NSRulerView {
    static let thickness: CGFloat = 20
    static let rowHeaderWidth: CGFloat = 44

    var gridView: GridView? { clientView as? GridView }
    var sheet: Sheet? { gridView?.sheet }

    override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
        super.init(scrollView: scrollView, orientation: orientation)
        ruleThickness = orientation == .horizontalRuler ? Self.thickness : Self.rowHeaderWidth
        reservedThicknessForMarkers = 0
        reservedThicknessForAccessoryView = 0
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    static let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

    func attributes(selected: Bool) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byClipping
        return [.font: Self.font,
                .foregroundColor: selected ? NSColor.labelColor : NSColor.secondaryLabelColor,
                .paragraphStyle: style]
    }

    func fillBackground(_ rect: NSRect, selected: Bool) {
        (selected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25) : NSColor.windowBackgroundColor).setFill()
        rect.fill()
    }
}

@MainActor
final class ColumnHeaderView: SheetHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
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

@MainActor
final class RowHeaderView: SheetHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
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
        NSRect(x: width - 1, y: 0, width: 1, height: bounds.height).fill()
    }
}
