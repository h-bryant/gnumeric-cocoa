import AppKit
import UniformTypeIdentifiers
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
            let wasRightToLeft = layoutIsRightToLeft
            layoutIsRightToLeft = isRightToLeft
            updateFrameSize()
            updateCommentToolTips()
            scrollToInitialTopLeft()
            needsDisplay = true
            headerViews.forEach { $0.needsDisplay = true }
            if wasRightToLeft != layoutIsRightToLeft { directionDidChange?() }
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
    /// Dragging the selection by its border (item-cursor.c): the range
    /// picked up, where the grab was inside it, and where it would drop.
    private struct MoveDrag {
        var source: CellRange
        var grabColumn: Int
        var grabRow: Int
        var target: CellRange?
        var moved = false
    }
    private var moveDrag: MoveDrag?
    /// A scrollbar or slider being dragged: its value follows the pointer.
    private var widgetDrag: SheetObject?

    // MARK: Widgets that act

    /// What a click (or drag) at `point` does to a widget: a checkbox,
    /// radio button, or button is clicked; a scrollbar or slider takes
    /// the value under the pointer along its length; a spin button steps
    /// up in its upper half and down in its lower; a list takes the row
    /// under the pointer; a combo pops up its entries.
    func actOnWidget(_ object: SheetObject, at point: NSPoint) {
        guard let sheet else { return }
        let frame = object.frame
        do {
            switch object.widgetKind {
            case .checkbox, .radioButton, .button:
                try sheet.clickWidget(object)
            case .scrollbar, .slider:
                guard let settings = sheet.widgetSettings(of: object) else { return }
                let arrows: CGFloat = object.widgetKind == .scrollbar ? 15 * sheet.zoomFactor : 0
                let fraction: CGFloat
                if settings.horizontal {
                    fraction = (point.x - frame.minX - arrows) / max(frame.width - 2 * arrows, 1)
                } else {
                    fraction = (point.y - frame.minY - arrows) / max(frame.height - 2 * arrows, 1)
                }
                let clamped = min(max(fraction, 0), 1)
                let value = Double(settings.minimum) + Double(settings.maximum - settings.minimum) * Double(clamped)
                try sheet.setWidgetValue(value, for: object)
            case .spinButton:
                guard let settings = sheet.widgetSettings(of: object) else { return }
                let step = point.y < frame.midY ? settings.increment : -settings.increment
                try sheet.setWidgetValue(sheet.widgetValue(object) + Double(step), for: object)
            case .list:
                let rowHeight = 15 * sheet.zoomFactor
                let row = Int((point.y - frame.minY) / rowHeight) + 1
                let entries = sheet.widgetEntries(object)
                if row >= 1, row <= entries.count { try sheet.chooseWidgetEntry(row, for: object) }
            case .combo:
                presentComboEntries(for: object, at: point)
            default:
                return
            }
        } catch {
            presentError?(error)
        }
        needsDisplay = true
    }

    private func presentComboEntries(for object: SheetObject, at point: NSPoint) {
        guard let sheet else { return }
        let entries = sheet.widgetEntries(object)
        guard !entries.isEmpty else { return }
        let menu = NSMenu(title: "Entries")
        let chosen = sheet.widgetSelection(object)
        for (index, entry) in entries.enumerated() {
            let item = NSMenuItem(title: entry.isEmpty ? " " : entry, action: #selector(comboEntryChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index + 1
            item.representedObject = object
            item.state = chosen == index + 1 ? .on : .off
            menu.addItem(item)
        }
        if let event = window?.currentEvent, event.type == .leftMouseDown {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            menu.popUp(positioning: nil, at: viewRect(forSheetRect: NSRect(origin: point, size: .zero)).origin, in: self)
        }
    }

    @objc private func comboEntryChosen(_ sender: NSMenuItem) {
        guard let sheet, let object = sender.representedObject as? SheetObject else { return }
        do {
            try sheet.chooseWidgetEntry(sender.tag, for: object)
        } catch {
            presentError?(error)
        }
        needsDisplay = true
    }
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
    /// unfrozen cell sits right under the frozen strips (at the top and
    /// left; for a right-to-left sheet the columns strip is at the right,
    /// and `maximumScrollOriginX` bounds the origin instead).
    var minimumScrollOrigin: NSPoint {
        guard let panes else { return .zero }
        return NSPoint(x: isRightToLeft ? 0 : panes.origin.x, y: panes.origin.y)
    }

    var maximumScrollOriginX: CGFloat? {
        guard isRightToLeft, let panes, panes.hasColumns, let clip = enclosingScrollView?.contentView else { return nil }
        return mirrorWidth - panes.origin.x - clip.bounds.width
    }

    // MARK: Right to left

    /// A right-to-left sheet (`text_is_rtl`, Format → Sheet → Right to
    /// Left): column A sits at the right edge of the document view and the
    /// columns run leftward, as the GTK's canvas direction mirrors them.
    /// Sheet pixels keep counting from column A; the mirror lives in the
    /// sheet-to-view mapping below and in the drawing passes.
    var isRightToLeft: Bool { sheet?.isRightToLeft ?? false }

    /// The view x of sheet x 0 for a right-to-left sheet: the document's
    /// right edge (`updateFrameSize` keeps the scroll position on the same
    /// cells as the frame grows).
    var mirrorWidth: CGFloat { bounds.width }

    /// The direction the view was last laid out for.  A change flips the
    /// scroll position so the same columns stay in view, and tells the
    /// window controller, which moves the row header to the other side.
    private var layoutIsRightToLeft = false
    var directionDidChange: (() -> Void)?

    func syncDirection() {
        let rtl = isRightToLeft
        guard rtl != layoutIsRightToLeft else { return }
        layoutIsRightToLeft = rtl
        if let clip = enclosingScrollView?.contentView {
            var origin = clip.bounds.origin
            origin.x = max(0, bounds.width - clip.bounds.width - origin.x)
            clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
            enclosingScrollView?.reflectScrolledClipView(clip)
        }
        needsDisplay = true
        headerViews.forEach { $0.needsDisplay = true }
        directionDidChange?()
    }

    /// Where the sheet was last shown: the first scrolling cell its view
    /// keeps (restored from the file, or recorded as the grid scrolled),
    /// at the top left, or at the top right of a right-to-left sheet.
    private func scrollToInitialTopLeft() {
        guard let sheet, let clip = enclosingScrollView?.contentView else { scroll(.zero); return }
        // Before the first layout the clip view has no size and the grid
        // no page beyond the data: the scroll waits for the frame.
        guard !clip.bounds.isEmpty else { needsInitialScroll = true; return }
        needsInitialScroll = false
        scroll(toFirstScrollingCell: sheet.initialTopLeft)
    }
    private var needsInitialScroll = false

    /// Scroll so `cell` is the first cell past the frozen strips (what the
    /// GTK's pane 0 shows at its top left; sc_set_top_left), at the top
    /// right of a right-to-left sheet.
    func scroll(toFirstScrollingCell cell: CellCoordinate) {
        guard let sheet else { return }
        let clipWidth = enclosingScrollView?.contentView.bounds.width ?? 0
        let strip = (width: panes?.width ?? 0, height: panes?.height ?? 0)
        let x = sheet.leftEdge(ofColumn: cell.column)
        scroll(NSPoint(x: isRightToLeft ? max(0, mirrorWidth - x + strip.width - clipWidth) : max(0, x - strip.width),
                       y: max(0, sheet.topEdge(ofRow: cell.row) - strip.height)))
    }

    /// The first scrolling cell, kept in the sheet's view as the grid
    /// scrolls (gnm_pane_update_inital_top_left): the file saves it and
    /// the sheet shows it again when it comes back.
    private func recordTopLeft() {
        guard let sheet, !needsInitialScroll else { return }
        let r = scrollingVisibleRect
        let x = isRightToLeft ? max(0, sheetX(forViewX: r.maxX) - 0.5) : sheetX(forViewX: r.minX)
        let cell = CellCoordinate(column: sheet.column(atX: x), row: sheet.row(atY: sheetY(forViewY: r.minY)))
        if cell != sheet.initialTopLeft { sheet.initialTopLeft = cell }
    }

    /// The sheet x range the visible rect covers, apart from the strips.
    var visibleSheetXRange: (minX: CGFloat, maxX: CGFloat) {
        let visible = visibleRect
        return isRightToLeft ? (mirrorWidth - visible.maxX, mirrorWidth - visible.minX) : (visible.minX, visible.maxX)
    }

    // Sheet pixels and view points coincide, except where a frozen strip
    // covers the visible rect (there the view shows the frozen cells) and
    // on a right-to-left sheet (mirrored).
    func viewX(forSheetX x: CGFloat) -> CGFloat {
        if let panes, panes.hasColumns, x >= panes.origin.x, x < panes.origin.x + panes.width {
            return isRightToLeft ? visibleRect.maxX - (x - panes.origin.x) : visibleRect.minX + (x - panes.origin.x)
        }
        return isRightToLeft ? mirrorWidth - x : x
    }

    /// The view x of a column's right edge in sheet pixels (exclusive): on
    /// a right-to-left sheet the column's left edge in the view.
    func viewX(forSheetRightEdge x: CGFloat) -> CGFloat {
        isRightToLeft ? viewX(forSheetX: x - 0.5) - 0.5 : viewX(forSheetX: x - 0.5) + 0.5
    }

    func viewY(forSheetY y: CGFloat) -> CGFloat {
        guard let panes, panes.hasRows, y >= panes.origin.y, y < panes.origin.y + panes.height else { return y }
        return visibleRect.minY + (y - panes.origin.y)
    }

    func sheetX(forViewX x: CGFloat) -> CGFloat {
        if let panes, panes.hasColumns {
            if isRightToLeft {
                if x > visibleRect.maxX - panes.width, x <= visibleRect.maxX {
                    return panes.origin.x + (visibleRect.maxX - x)
                }
            } else if x >= visibleRect.minX, x < visibleRect.minX + panes.width {
                return panes.origin.x + (x - visibleRect.minX)
            }
        }
        return isRightToLeft ? mirrorWidth - x : x
    }

    func sheetY(forViewY y: CGFloat) -> CGFloat {
        guard let panes, panes.hasRows, y >= visibleRect.minY, y < visibleRect.minY + panes.height else { return y }
        return panes.origin.y + (y - visibleRect.minY)
    }

    func sheetPoint(forViewPoint p: NSPoint) -> NSPoint {
        NSPoint(x: sheetX(forViewX: p.x), y: sheetY(forViewY: p.y))
    }

    /// Where a sheet rect appears; one that straddles a frozen boundary
    /// keeps its size and follows its origin (its right edge, right to left).
    func viewRect(forSheetRect r: NSRect) -> NSRect {
        let x = isRightToLeft ? viewX(forSheetRightEdge: r.maxX) : viewX(forSheetX: r.minX)
        return NSRect(x: x, y: viewY(forSheetY: r.minY), width: r.width, height: r.height)
    }

    /// The part of the visible rect that scrolls: the visible rect minus
    /// the frozen strips.
    var scrollingVisibleRect: NSRect {
        var r = visibleRect
        if let panes {
            if !isRightToLeft { r.origin.x += panes.width }
            r.size.width -= panes.width
            r.origin.y += panes.height; r.size.height -= panes.height
        }
        return r
    }
    private let editor = CellEditorField()
    private var editingCell: CellCoordinate?
    var isEditing: Bool { editingCell != nil }
    /// Whether the edit began with typing (an arrow key then ends it)
    /// rather than F2 or a double-click (the arrows move in the text).
    private(set) var editingStartedByTyping = false

    // MARK: Dropped files

    /// A file dropped on the grid: images are placed where they land,
    /// anything else opens as a document (the GTK's drop of a URI).
    var openDroppedDocument: ((URL) -> Void)?

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return false }
        let point = sheetPoint(forViewPoint: convert(sender.draggingLocation, from: nil))
        handleDroppedFiles(urls, at: point)
        return true
    }

    func handleDroppedFiles(_ urls: [URL], at point: NSPoint) {
        var origin = point
        for url in urls {
            let type = UTType(filenameExtension: url.pathExtension) ?? .data
            if type.conforms(to: .image), let sheet, let data = try? Data(contentsOf: url) {
                let natural = sheet.naturalSize(ofImageData: data)
                let size = natural == .zero ? CGSize(width: 200, height: 150) : natural
                do {
                    let object = try sheet.insertImage(data, frame: CGRect(origin: origin, size: size))
                    select(objects: [object])
                    origin.x += 20
                    origin.y += 20
                } catch {
                    presentError?(error)
                }
            } else {
                openDroppedDocument?(url)
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
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
        editor.onArrow = { [weak self] columns, rows, extend, jump in
            guard let self else { return false }
            // The arrows follow the screen: Left is the next column of a
            // right-to-left sheet (gnm-pane.c).
            let columns = isRightToLeft ? -columns : columns
            if moveFormulaRange(columns: columns, rows: rows, extend: extend, jump: jump) { return true }
            // An entry started by typing ends on an arrow key, which then
            // moves the cursor (the GTK's wbcg_edit_start without the
            // cursor keys in the entry); an F2 or double-click edit keeps
            // the arrows for the text.
            guard editingStartedByTyping, !extend else { return false }
            let movement: CellEditorField.Movement = rows < 0 ? .up : rows > 0 ? .down : columns < 0 ? .left : .right
            commitEditing(text: editor.stringValue, movement: movement)
            return true
        }
        editor.onArrayCommit = { [weak self] text in self?.commitArrayFormula(text: text) }
        editor.onSelectionChange = { [weak self] in self?.updateFunctionTooltip() }
        editor.onCompleteFunction = { [weak self] in self?.completeFunctionName() }
        editor.onTextChange = { [weak self] text in
            guard let self else { return }
            handleAutocomplete(text)
            // gee_update_env: typing stops the range selection when the text
            // can no longer take a range at the cursor (after ")", in plain
            // text); otherwise the next range goes where the cursor now is.
            if formulaRangeAnchor == nil, formulaRange != nil {
                if let replace = formulaReplacement() {
                    formulaRangeText = replace
                } else {
                    formulaRange = nil
                    formulaRangeText = nil
                    formulaRangeBase = nil
                    needsDisplay = true
                }
            }
            editingTextDidChange?(text)
            fitEditorToText()
            updateFunctionTooltip()
        }
    }

    /// item-edit.c: the in-cell editor grows down (and right) to show every
    /// line of a multi-line text, never shrinking below the cell.
    private func fitEditorToText() {
        guard isEditing, let sheet, let cell = editingCell else { return }
        let frame = sheet.frameOfCell(atColumn: cell.column, row: cell.row)
        let zoom = sheet.zoomFactor
        let font = editor.font ?? NSFont.systemFont(ofSize: 13)
        let lines = editor.stringValue.components(separatedBy: "\n")
        let lineHeight = ceil(font.ascender - font.descender + font.leading) + 1
        let widest = lines.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let minimum = NSRect(x: frame.minX, y: frame.minY, width: max(frame.width, 80 * zoom), height: max(frame.height, 16 * zoom))
        let height = lines.count > 1 ? max(minimum.height, lineHeight * CGFloat(lines.count) + 4) : minimum.height
        let width = max(minimum.width, widest + 8)
        let fitted = viewRect(forSheetRect: NSRect(x: minimum.minX, y: minimum.minY, width: width, height: height))
        if fitted != editor.frame {
            editor.frame = fitted
            needsDisplay = true
        }
    }

    /// The editor's frame, for the checks.
    var editorFrameForTesting: NSRect { editor.frame }

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
            let previousWidth = frame.width
            setFrameSize(size)
            if isRightToLeft, let clip = enclosingScrollView?.contentView {
                // Column A stays at the right edge: the scroll origin moves
                // with the growth.
                var origin = clip.bounds.origin
                origin.x += size.width - previousWidth
                clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
                enclosingScrollView?.reflectScrolledClipView(clip)
            }
        }
    }

    @objc private func clipFrameChanged(_ note: Notification) {
        guard let clip = enclosingScrollView?.contentView, note.object as? NSView === clip else { return }
        updateFrameSize()
        if needsInitialScroll { scrollToInitialTopLeft() }
        headerViews.forEach { $0.needsDisplay = true }
    }

    /// Scrolling: the headers follow the clip view's bounds origin, and
    /// frozen strips are repainted at the new visible rect.
    @objc private func clipBoundsChanged(_ note: Notification) {
        guard let clip = enclosingScrollView?.contentView, note.object as? NSView === clip else { return }
        headerViews.forEach { $0.needsDisplay = true }
        if panes != nil { needsDisplay = true }
        recordTopLeft()
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
        // Each pass maps sheet pixels to the view: the main one as they
        // are; a frozen strip shifted so its cells land at the top or left
        // of the visible rect; a right-to-left sheet mirrored, about the
        // document's right edge or, under the frozen columns strip (then at
        // the right), about the visible rect's.  Shapes drawn in sheet
        // coordinates come out mirrored by the transform; the engine places
        // the cells and objects itself, and text is set upright locally.
        let rtl = isRightToLeft
        var passes = [DrawPass(clip: dirtyRect, shift: .zero, mirror: rtl ? mirrorWidth : nil)]
        let visible = visibleRect
        if let panes {
            let stripX = rtl ? visible.maxX - panes.width : visible.minX
            let stripMirror: CGFloat? = rtl ? visible.maxX + panes.origin.x : nil
            let stripShift = rtl ? 0 : visible.minX - panes.origin.x
            if panes.hasRows {
                passes.append(DrawPass(clip: NSRect(x: rtl ? visible.minX : visible.minX + panes.width, y: visible.minY,
                                                    width: visible.width - panes.width, height: panes.height),
                                       shift: NSPoint(x: 0, y: visible.minY - panes.origin.y), mirror: rtl ? mirrorWidth : nil))
            }
            if panes.hasColumns {
                passes.append(DrawPass(clip: NSRect(x: stripX, y: visible.minY + panes.height,
                                                    width: panes.width, height: visible.height - panes.height),
                                       shift: NSPoint(x: stripShift, y: 0), mirror: stripMirror))
            }
            if panes.hasRows && panes.hasColumns {
                passes.append(DrawPass(clip: NSRect(x: stripX, y: visible.minY, width: panes.width, height: panes.height),
                                       shift: NSPoint(x: stripShift, y: visible.minY - panes.origin.y), mirror: stripMirror))
            }
        }
        for (index, pass) in passes.enumerated() {
            let clip = index == 0 ? dirtyRect : pass.clip.intersection(dirtyRect)
            guard !clip.isEmpty else { continue }
            NSGraphicsContext.saveGraphicsState()
            if index > 0 { clip.clip() }
            context.concatenate(pass.transform)
            currentPass = pass
            drawPass(sheet, context: context, dirtyRect: clip.applying(pass.transform.inverted()))
            currentPass = nil
            NSGraphicsContext.restoreGraphicsState()
        }
        guard let panes else { return }
        // The pane boundaries.
        NSColor.tertiaryLabelColor.setFill()
        if panes.hasRows {
            NSRect(x: visible.minX, y: visible.minY + panes.height - 1, width: visible.width, height: 1).fill()
        }
        if panes.hasColumns {
            NSRect(x: rtl ? visible.maxX - panes.width : visible.minX + panes.width - 1, y: visible.minY, width: 1, height: visible.height).fill()
        }
    }

    /// One drawing pass: how a region's sheet pixels reach the view.
    struct DrawPass {
        let clip: NSRect
        let shift: NSPoint
        /// The view x of sheet x 0, for a right-to-left sheet.
        let mirror: CGFloat?
        var mirrorTransform: CGAffineTransform? {
            mirror.map { CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: $0, ty: 0) }
        }
        var transform: CGAffineTransform {
            (mirrorTransform ?? .identity).concatenating(CGAffineTransform(translationX: shift.x, y: shift.y))
        }
    }
    private var currentPass: DrawPass?

    /// The cells and the objects come from the engine, which places a
    /// right-to-left sheet's columns itself (item-grid's direction of -1)
    /// and never mirrors their text: under a mirrored pass the context goes
    /// back to view x and the engine is given the mirror.
    private func drawCells(of sheet: Sheet, context: CGContext, dirtyRect: NSRect) {
        guard let pass = currentPass, let mirror = pass.mirror, let flip = pass.mirrorTransform else {
            sheet.drawCells(in: dirtyRect, context: context, backgroundColor: NSColor.white.cgColor)
            return
        }
        context.saveGState()
        context.concatenate(flip)   // its own inverse
        sheet.drawCells(in: dirtyRect.applying(flip), context: context, backgroundColor: NSColor.white.cgColor, rightToLeftWidth: mirror)
        context.restoreGState()
    }

    private func drawSheetObjects(of sheet: Sheet, context: CGContext, dirtyRect: NSRect) {
        guard let pass = currentPass, let mirror = pass.mirror, let flip = pass.mirrorTransform else {
            sheet.drawSheetObjects(in: dirtyRect, context: context)
            return
        }
        context.saveGState()
        context.concatenate(flip)
        sheet.drawSheetObjects(in: dirtyRect.applying(flip), context: context, rightToLeftWidth: mirror)
        context.restoreGState()
    }

    /// Text drawn in sheet coordinates under a mirrored pass: mirrored
    /// again about its box's centre, it reads upright where the box lands.
    private func withUprightText(around box: NSRect, _ body: () -> Void) {
        guard let pass = currentPass, pass.mirror != nil, let context = NSGraphicsContext.current?.cgContext else {
            body()
            return
        }
        context.saveGState()
        context.concatenate(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 2 * box.midX, ty: 0))
        body()
        context.restoreGState()
    }

    /// Everything the sheet shows in `dirtyRect` (sheet coordinates).
    private func drawPass(_ sheet: Sheet, context: CGContext, dirtyRect: NSRect) {
        drawCells(of: sheet, context: context, dirtyRect: dirtyRect)
        drawPageBreaks(of: sheet, dirtyRect: dirtyRect)
        drawSheetObjects(of: sheet, context: context, dirtyRect: dirtyRect)
        drawFilterButtons(of: sheet, dirtyRect: dirtyRect)
        drawCommentMarkers(of: sheet, dirtyRect: dirtyRect)
        drawMarchingAnts(of: sheet, dirtyRect: dirtyRect)
        drawSelection(of: sheet, dirtyRect: dirtyRect)
        drawValidationDropdown(of: sheet, dirtyRect: dirtyRect)
        drawInputMessage(of: sheet, dirtyRect: dirtyRect)
        drawFunctionTooltip(of: sheet, dirtyRect: dirtyRect)
        drawFormulaRange(of: sheet, dirtyRect: dirtyRect)
        drawObjectSelection(dirtyRect: dirtyRect)
    }

    /// The manual page breaks as dashed blue lines along the left of a
    /// column and the top of a row (the GTK grid shows none; the print
    /// preview is the system panel's).
    private func drawPageBreaks(of sheet: Sheet, dirtyRect: NSRect) {
        let columns = sheet.columnPageBreaks, rows = sheet.rowPageBreaks
        guard !columns.isEmpty || !rows.isEmpty else { return }
        let path = NSBezierPath()
        path.lineWidth = 1
        path.setLineDash([6, 3], count: 2, phase: 0)
        for column in columns {
            let x = sheet.frameOfCell(atColumn: column.intValue, row: 0).minX - 0.5
            guard x >= dirtyRect.minX - 1, x <= dirtyRect.maxX + 1 else { continue }
            path.move(to: NSPoint(x: x, y: dirtyRect.minY))
            path.line(to: NSPoint(x: x, y: dirtyRect.maxY))
        }
        for row in rows {
            let y = sheet.frameOfCell(atColumn: 0, row: row.intValue).minY - 0.5
            guard y >= dirtyRect.minY - 1, y <= dirtyRect.maxY + 1 else { continue }
            path.move(to: NSPoint(x: dirtyRect.minX, y: y))
            path.line(to: NSPoint(x: dirtyRect.maxX, y: y))
        }
        NSColor.systemBlue.withAlphaComponent(0.7).setStroke()
        path.stroke()
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
        if let target = moveDrag?.target {
            let path = NSBezierPath(rect: rect(of: target, in: sheet).insetBy(dx: -1, dy: -1))
            path.lineWidth = 2
            NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
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
            let whole = CellRange(start: CellCoordinate(column: 0, row: 0),
                                  end: CellCoordinate(column: sheet.columnCount - 1, row: sheet.rowCount - 1))
            for value in sheet.hyperlinkRanges(in: whole) {
                var range = CellRange()
                value.getValue(&range)
                let frame = viewRect(forSheetRect: rect(of: range, in: sheet))
                if !frame.isEmpty { addCursorRect(frame, cursor: .pointingHand) }
            }
            let selection = viewRect(forSheetRect: rect(of: sheet.selectedRange, in: sheet))
            for edge in Self.borderBands(of: selection) { addCursorRect(edge, cursor: .openHand) }
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
    /// The ants march while the clipboard holds a cut or copied range:
    /// item-cursor.c steps its dash every 75 ms.
    private var antsTimer: Timer?
    private var antsPhase: CGFloat = 0
    var antsAreMarchingForTesting: Bool { antsTimer != nil }

    private func drawMarchingAnts(of sheet: Sheet, dirtyRect: NSRect) {
        let frames = sheet.marchingAntsFrames
        updateAntsTimer(marching: !frames.isEmpty)
        for value in frames {
            let frame = value.rectValue
            guard frame.intersects(dirtyRect) else { continue }
            let path = NSBezierPath(rect: frame.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.setLineDash([4, 3], count: 2, phase: antsPhase)
            NSColor.labelColor.setStroke()
            path.stroke()
        }
    }

    private func updateAntsTimer(marching: Bool) {
        if !marching {
            antsTimer?.invalidate()
            antsTimer = nil
            return
        }
        guard antsTimer == nil else { return }
        let timer = Timer(timeInterval: 0.075, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated { stepAnts() }
        }
        RunLoop.main.add(timer, forMode: .common)
        antsTimer = timer
    }

    private func stepAnts() {
        guard let sheet, window?.isVisible == true else {
            updateAntsTimer(marching: false)
            return
        }
        let frames = sheet.marchingAntsFrames
        guard !frames.isEmpty else {
            updateAntsTimer(marching: false)
            return
        }
        antsPhase = (antsPhase + 1).truncatingRemainder(dividingBy: 7)
        for value in frames { setNeedsDisplay(value.rectValue.insetBy(dx: -2, dy: -2)) }
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
        editingStartedByTyping = initialText != nil
        let cell = sheet.editPosition
        let frame = sheet.frameOfCell(atColumn: cell.column, row: cell.row)
        let zoom = sheet.zoomFactor
        // item-edit.c: the cell's own font at the zoom, its colors, and
        // its alignment (General edits left-aligned).
        let format = sheet.formatOfCell(atColumn: cell.column, row: cell.row)
        editor.font = Self.editorFont(for: format, zoom: zoom)
        editor.textColor = format.textColor.flatMap { NSColor(cgColor: $0) } ?? .black
        editor.backgroundColor = (format.fillsBackground?.boolValue ?? false)
            ? (format.backgroundColor.flatMap { NSColor(cgColor: $0) } ?? .white) : .white
        switch format.horizontalAlignment?.intValue ?? 0x01 {
        case 0x04: editor.alignment = .right
        case 0x08: editor.alignment = .center
        default: editor.alignment = .left
        }
        editor.frame = viewRect(forSheetRect: NSRect(x: frame.minX, y: frame.minY,
                                                     width: max(frame.width, 80 * zoom), height: max(frame.height, 16 * zoom)))
        editor.stringValue = initialText ?? (sheet.editingTextOfCell(atColumn: cell.column, row: cell.row) ?? "")
        editingCell = cell
        // wbcg_edit_start: completion only when typing starts with a letter
        autocompleting = initialText == nil || (initialText?.first?.isLetter ?? false)
        autocompletePrefix = ""
        editor.isHidden = false
        window?.makeFirstResponder(editor)
        if let fieldEditor = editor.currentEditor() {
            let end = editor.stringValue.utf16.count
            fieldEditor.selectedRange = NSRange(location: initialText == nil ? end : end, length: 0)
        }
        editingTextDidChange?(editor.stringValue)
    }

    /// The cell's font as the engine draws it: its family resolved the way
    /// pango does, its points at 96 dpi and the zoom, bold and italic.
    static func editorFont(for format: CellFormat, zoom: CGFloat) -> NSFont {
        let points = CGFloat(format.fontSize?.doubleValue ?? 10)
        let size = max(8, points * 96 / 72 * zoom)
        let family = Engine.shared?.resolvedFontFamily(forName: format.fontName ?? "Sans") ?? "Helvetica"
        let bold = format.bold?.boolValue ?? false
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if format.italic?.boolValue ?? false { traits.insert(.italicFontMask) }
        return NSFontManager.shared.font(withFamily: family, traits: traits, weight: bold ? 9 : 5, size: size)
            ?? NSFont.systemFont(ofSize: size)
    }

    /// For the headless checks: the editor's font, size, and alignment.
    var editorStyleForTesting: String {
        "\(editor.font?.fontName ?? "nil") \(editor.font?.pointSize ?? 0) align=\(editor.alignment.rawValue)"
    }

    private func endEditingSession() {
        editingCell = nil
        functionTooltip = nil
        autocompleting = false
        formulaRangeAnchor = nil
        formulaRangeText = nil
        formulaRangeBase = nil
        if formulaRange != nil {
            formulaRange = nil
            needsDisplay = true
        }
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
        // The cell's validation first (wbcg_edit_finish): a Stop re-edits
        // or discards, a Warning accepts or discards, Information accepts.
        switch sheet.validateText(text, atColumn: cell.column, row: cell.row) {
        case .edit:
            sheet.selectCell(atColumn: cell.column, row: cell.row)
            beginEditing(initialText: text)
            return
        case .discard:
            return
        default:
            break
        }
        // The lock check of wbcg_edit_finish: a locked cell of a
        // protected sheet keeps the editor open with the message.
        let target = CellRange(start: cell, end: cell)
        if let message = sheet.lockMessage(forCellsIn: target) {
            presentError?(NSError(domain: GnmErrorDomain, code: GnmError.Code.commandFailed.rawValue,
                                  userInfo: [NSLocalizedDescriptionKey: "Set Text", NSLocalizedRecoverySuggestionErrorKey: message]))
            sheet.selectCell(atColumn: cell.column, row: cell.row)
            beginEditing(initialText: text)
            return
        }
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

    /// Return with Shift and Control or Command (the GTK's Ctrl+Shift+Return):
    /// the text as an array formula over the selection, through the cell's
    /// validation as a plain commit; a refusal reopens the editor.
    func commitArrayFormula(text: String) {
        guard let sheet, let cell = editingCell else { return }
        endEditingSession()
        switch sheet.validateText(text, atColumn: cell.column, row: cell.row) {
        case .edit:
            beginEditing(initialText: text)
            return
        case .discard:
            return
        default:
            break
        }
        do {
            try sheet.enterArrayFormula(text)
        } catch {
            presentError?(error)
            beginEditing(initialText: text)
        }
    }

    /// Commit from the formula bar: same command, no movement.
    func setEditCellText(_ text: String) {
        guard let sheet else { return }
        let cell = sheet.editPosition
        guard sheet.validateText(text, atColumn: cell.column, row: cell.row) == .valid else { return }
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

    /// The GTK's cell menu (scg_context_menu), for the selection: the
    /// clipboard, then Insert and Delete Cells…, or Insert and Delete
    /// Columns or Rows when whole columns or rows are selected (neither
    /// when the whole sheet is), Clear Contents, the edit position's
    /// comment and hyperlink with the selection's removals, Format All
    /// Cells…, Conditional Formatting…, and the Cell, Column, and Row
    /// submenus.  The actions go through the responder chain, validated
    /// as the menu bar's are.
    func contextMenu() -> NSMenu {
        let menu = NSMenu(title: "Cell")
        guard let sheet else { return menu }
        let selection = sheet.selectedRange
        let wholeRows = selection.start.column == 0 && selection.end.column == sheet.columnCount - 1
        let wholeColumns = selection.start.row == 0 && selection.end.row == sheet.rowCount - 1
        let columns = selection.end.column - selection.start.column + 1
        let rows = selection.end.row - selection.start.row + 1
        let forCells = !wholeRows && !wholeColumns
        @discardableResult
        func add(_ title: String, _ action: Selector?, to target: NSMenu = menu) -> NSMenuItem {
            target.addItem(withTitle: title, action: action, keyEquivalent: "")
        }
        /// The GTK's ngettext pair, the count put in.
        func counted(_ title: String, _ n: Int) -> String {
            title.replacingOccurrences(of: "%d", with: String(n))
        }
        func submenu(_ title: String) -> NSMenu {
            let sub = NSMenu(title: title)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = sub
            menu.addItem(item)
            return sub
        }
        add(Localization.title("Cut"), #selector(NSText.cut(_:)))
        add(Localization.title("Copy"), #selector(NSText.copy(_:)))
        add(Localization.title("Paste"), #selector(NSText.paste(_:)))
        add(Localization.title("Paste Special…"), Selector(("pasteSpecial:")))
        menu.addItem(.separator())
        if forCells {
            let cells = columns * rows
            add(counted(cells == 1 ? Localization.title("Insert %d Cell…") : Localization.title("Insert %d Cells…"), cells), Selector(("insertCells:")))
            add(counted(cells == 1 ? Localization.title("Delete %d Cell…") : Localization.title("Delete %d Cells…"), cells), Selector(("deleteCells:")))
        } else if wholeColumns && !wholeRows {
            add(counted(columns == 1 ? Localization.title("Insert %d Column") : Localization.title("Insert %d Columns"), columns), #selector(insertColumns(_:)))
            add(counted(columns == 1 ? Localization.title("Delete %d Column") : Localization.title("Delete %d Columns"), columns), #selector(deleteColumns(_:)))
        } else if wholeRows && !wholeColumns {
            add(counted(rows == 1 ? Localization.title("Insert %d Row") : Localization.title("Insert %d Rows"), rows), #selector(insertRows(_:)))
            add(counted(rows == 1 ? Localization.title("Delete %d Row") : Localization.title("Delete %d Rows"), rows), #selector(deleteRows(_:)))
        }
        add(Localization.title("Clear Contents"), #selector(NSText.delete(_:)))
        if forCells {
            menu.addItem(.separator())
            let edit = sheet.editPosition
            add(sheet.comment(atColumn: edit.column, row: edit.row) == nil ? Localization.title("Add Comment…") : Localization.title("Edit Comment…"),
                #selector(insertComment(_:)))
            let comments = sheet.comments(in: selection).count
            if comments > 0 {
                add(counted(comments == 1 ? Localization.title("Remove %d Comment") : Localization.title("Remove %d Comments"), comments),
                    #selector(clearComments(_:)))
            }
            add(sheet.hyperlink(atColumn: edit.column, row: edit.row) == nil ? Localization.title("Add Hyperlink…") : Localization.title("Edit Hyperlink…"),
                Selector(("insertHyperlink:")))
            let links = sheet.hyperlinkRanges(in: selection).count
            if links > 0 {
                add(counted(links == 1 ? Localization.title("Remove %d Link") : Localization.title("Remove %d Links"), links), #selector(clearHyperlinks(_:)))
            }
        }
        menu.addItem(.separator())
        add(Localization.title("Format All Cells…"), Selector(("formatCells:")))
        add(Localization.title("Conditional Formatting…"), Selector(("conditionalFormatting:")))
        let cellMenu = submenu(Localization.title("Cell"))
        add(Localization.title("Merge"), #selector(mergeCells(_:)), to: cellMenu)
        add(Localization.title("Unmerge"), #selector(unmergeCells(_:)), to: cellMenu)
        add(Localization.title("Auto Fit Width"), #selector(autofitColumns(_:)), to: cellMenu)
        add(Localization.title("Auto Fit Height"), #selector(autofitRows(_:)), to: cellMenu)
        let columnMenu = submenu(Localization.title("Column"))
        add(Localization.title("Width…"), Selector(("setColumnWidth:")), to: columnMenu)
        add(Localization.title("Auto Fit Width"), #selector(autofitColumns(_:)), to: columnMenu)
        // Hiding every column (row) is refused, as the GTK greys it.
        add(Localization.title("Hide"), wholeRows ? nil : #selector(hideColumns(_:)), to: columnMenu)
        add(Localization.title("Unhide"), #selector(unhideColumns(_:)), to: columnMenu)
        let rowMenu = submenu(Localization.title("Row"))
        add(Localization.title("Height…"), Selector(("setRowHeight:")), to: rowMenu)
        add(Localization.title("Auto Fit Height"), #selector(autofitRows(_:)), to: rowMenu)
        add(Localization.title("Hide"), wholeColumns ? nil : #selector(hideRows(_:)), to: rowMenu)
        add(Localization.title("Unhide"), #selector(unhideRows(_:)), to: rowMenu)
        return menu
    }

    /// Right-click on an object: the GTK object menu's delete and order items.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let sheet else { return nil }
        let point = sheetPoint(forViewPoint: convert(event.locationInWindow, from: nil))
        guard let object = sheet.sheetObject(at: point) else {
            // A cell: the selection's menu; a click outside the selection
            // moves the selection there first (gnm_pane_button_press).
            if isEditing { commitEditing(text: editor.stringValue, movement: .none) }
            let cell = CellCoordinate(column: sheet.column(atX: point.x), row: sheet.row(atY: point.y))
            let selection = sheet.selectedRange
            let inside = cell.column >= selection.start.column && cell.column <= selection.end.column
                && cell.row >= selection.start.row && cell.row <= selection.end.row
            if !inside {
                sheet.selectCell(atColumn: cell.column, row: cell.row)
            }
            return contextMenu()
        }
        if !selectedObjects.contains(object) {
            select(objects: [object])
        }
        let menu = NSMenu(title: "Object")
        if object.typeName == "SheetObjectGraph" {
            menu.addItem(withTitle: Localization.title("Properties…"), action: #selector(editObjectProperties(_:)), keyEquivalent: "")
        }
        if !sheet.imageFormats(for: object).isEmpty {
            menu.addItem(withTitle: Localization.title("Save as Image…"), action: #selector(saveObjectAsImage(_:)), keyEquivalent: "")
        }
        if menu.items.count > 0 {
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: Localization.title("Delete"), action: #selector(deleteObjects(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: Localization.title("Pull to Front"), action: #selector(pullObjectToFront(_:)), keyEquivalent: "")
        menu.addItem(withTitle: Localization.title("Pull Forward"), action: #selector(pullObjectForward(_:)), keyEquivalent: "")
        menu.addItem(withTitle: Localization.title("Push Backward"), action: #selector(pushObjectBackward(_:)), keyEquivalent: "")
        menu.addItem(withTitle: Localization.title("Push to Back"), action: #selector(pushObjectToBack(_:)), keyEquivalent: "")
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
        // The ants start marching at once (the GTK's cursor animates
        // from the copy), not at the next redraw.
        updateAntsTimer(marching: true)
        needsDisplay = true
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
        updateAntsTimer(marching: true)
        needsDisplay = true
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

    /// Insert → Name…: the name into the cell being edited, or a formula
    /// "=name" into the cell (dialog-define-names.c name_guru_paste).
    func insertName(_ name: String) {
        guard sheet != nil else { return }
        if !isEditing {
            beginEditing(initialText: "=" + name)
            return
        }
        if let fieldEditor = editor.currentEditor() as? NSTextView {
            let text = editor.stringValue.isEmpty ? "=" + name : name
            fieldEditor.insertText(text, replacementRange: fieldEditor.selectedRange())
            editingTextDidChange?(editor.stringValue)
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
    /// Edit → Clear → Hyperlinks (cb_edit_delete_links).
    @objc func clearHyperlinks(_ sender: Any?) { run { try $0.removeHyperlinksOfSelection() } }
    /// Edit → Select → Next Object (⌃Tab; cb_edit_select_object).
    @objc func selectNextObjectItem(_ sender: Any?) { selectNextObject(reverse: false) }

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
    // MARK: Autocompletion

    /// The GTK autocompletion: while plain text is typed at the end of the
    /// editor, the column's nearest matching text above fills in with the
    /// added part selected; deleting, a non-letter, or typing elsewhere
    /// stops it for the session.
    private var autocompleting = false
    private var autocompletePrefix = ""

    /// For the headless checks: the editor's text, and a text change as
    /// typing would report it.
    var editorTextForTesting: String { editor.stringValue }
    func editorTextDidChangeForTesting(_ text: String) {
        editor.stringValue = text
        editor.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        editor.onTextChange?(text)
    }

    /// For the headless checks: the selected tail after a completion.
    var autocompleteTail: NSRange? {
        guard autocompleting, let fieldEditor = editor.currentEditor(), fieldEditor.selectedRange.length > 0 else { return nil }
        return fieldEditor.selectedRange
    }

    private func handleAutocomplete(_ text: String) {
        guard autocompleting, let sheet, let cell = editingCell else { return }
        let length = (text as NSString).length
        if length < (autocompletePrefix as NSString).length || text.isEmpty {
            autocompleting = false   // deleting
            return
        }
        guard let fieldEditor = editor.currentEditor(), fieldEditor.selectedRange.location == length,
              let last = text.last, last.isLetter else {
            autocompleting = false
            return
        }
        autocompletePrefix = text
        guard let completion = sheet.completion(for: text, atColumn: cell.column, row: cell.row),
              completion != text, completion.hasPrefix(text) else { return }
        editor.stringValue = completion
        editor.currentEditor()?.selectedRange = NSRange(location: length, length: (completion as NSString).length - length)
    }

    /// Insert → Function…: the name and its parenthesis into the formula
    /// being edited at the cursor, or a fresh formula.
    func insertFunction(_ name: String) {
        guard let sheet else { return }
        if isEditing, let fieldEditor = editor.currentEditor() {
            let text = editor.stringValue as NSString
            let cursor = min(fieldEditor.selectedRange.location, text.length)
            let prefix = text.length == 0 ? "=" : ""
            editor.stringValue = text.replacingCharacters(in: NSRange(location: cursor, length: 0), with: prefix + name + "(")
            editor.currentEditor()?.selectedRange = NSRange(location: cursor + (prefix + name + "(").utf16.count, length: 0)
            editingTextDidChange?(editor.stringValue)
        } else {
            _ = sheet
            beginEditing(initialText: "=" + name + "(")
        }
    }

    // MARK: Formula range selection

    /// While a formula is typed, a click or drag on the grid, or an arrow
    /// key, puts a range into the text (scg_rangesel_* and the GTK entry's
    /// find_range); the range stays outlined until the text can no longer
    /// take one at the cursor.
    private var formulaRangeAnchor: CellCoordinate?
    private var formulaRangeText: NSRange?
    private var formulaRange: CellRange?
    /// The range's base corner (scg->rangesel.base_corner): where the
    /// keyboard moves from, the other corner extending.
    private var formulaRangeBase: CellCoordinate?

    /// For the headless checks: the outlined range.
    var formulaRangeShown: CellRange? { formulaRange }

    /// Whether a click now would put a reference into the editor.
    private func formulaReplacement() -> NSRange? {
        guard isEditing, let sheet, let fieldEditor = editor.currentEditor() else { return nil }
        var replace = NSRange(location: 0, length: 0)
        let cursor = fieldEditor.selectedRange.location
        return sheet.formulaText(editor.stringValue, cursorAt: cursor, canTakeRange: &replace) ? replace : nil
    }

    /// Put a range's reference into the editor at the replacement, and
    /// keep the editor the first responder with the cursor after it.
    func takeFormulaRange(_ range: CellRange, replacing replace: NSRange) {
        guard let sheet else { return }
        let name = sheet.name(of: range)
        let text = editor.stringValue as NSString
        guard replace.location <= text.length, replace.location + replace.length <= text.length else { return }
        editor.stringValue = text.replacingCharacters(in: replace, with: name)
        formulaRangeText = NSRange(location: replace.location, length: name.utf16.count)
        formulaRange = range
        // Making the editor first responder while its field editor already
        // is would end editing (and commit) on the way; only take focus
        // back when it was lost.
        if let fieldEditor = editor.currentEditor() {
            if window?.firstResponder !== fieldEditor { window?.makeFirstResponder(editor) }
        } else {
            window?.makeFirstResponder(editor)
        }
        editor.currentEditor()?.selectedRange = NSRange(location: replace.location + name.utf16.count, length: 0)
        editingTextDidChange?(editor.stringValue)
        needsDisplay = true
    }

    /// An arrow key while a formula can take a range (scg_rangesel_move and
    /// scg_rangesel_extend): the first step goes from the cell being
    /// edited, later ones from the range's base corner; Shift moves the
    /// far corner, ⌘ jumps to the edge of the data.  False when the text
    /// cannot take a range, so the key keeps its meaning in the text.
    func moveFormulaRange(columns: Int, rows: Int, extend: Bool, jump: Bool) -> Bool {
        guard let sheet, let cell = editingCell else { return false }
        let active = formulaRange != nil && formulaRangeText != nil
        guard let replace = active ? formulaRangeText : formulaReplacement() else { return false }
        let base = (active ? formulaRangeBase : nil) ?? cell
        let range: CellRange
        let target: CellCoordinate
        if extend, active, let shown = formulaRange {
            target = sheet.cell(farCorner(of: shown, from: base), movedByColumns: columns, rows: rows, base: base, jumpingToBoundary: jump)
            range = Self.range(from: base, to: target)
        } else {
            target = sheet.cell(base, movedByColumns: columns, rows: rows, base: base, jumpingToBoundary: jump)
            range = CellRange(start: target, end: target)
        }
        formulaRangeBase = range.start == target && range.end == target ? target : base
        takeFormulaRange(range, replacing: replace)
        self.sheet(sheet, makeVisibleColumn: target.column, row: target.row)
        return true
    }

    // MARK: Function tooltips

    /// The GTK entry's tooltip under the editor: the call around the
    /// cursor with its argument marked, or the names a typed prefix could
    /// complete to (gee_check_tooltip); nil when there is none.
    private(set) var functionTooltip: FunctionTooltip? {
        didSet {
            if oldValue?.text != functionTooltip?.text { needsDisplay = true }
        }
    }

    private func updateFunctionTooltip() {
        guard isEditing, let sheet, let fieldEditor = editor.currentEditor() else {
            functionTooltip = nil
            return
        }
        functionTooltip = sheet.functionTooltip(for: editor.stringValue, cursorAt: fieldEditor.selectedRange.location)
    }

    /// F4 (cb_gee_key_press_event): a single completion replaces the
    /// prefix, else the reference at the cursor cycles between relative
    /// and absolute; the cursor ends after the new text.
    func completeFunctionName() {
        guard let sheet, let fieldEditor = editor.currentEditor() else { return }
        let text = editor.stringValue as NSString
        var range = NSRange(location: 0, length: 0)
        let replacement: String
        if let tooltip = functionTooltip, let completion = tooltip.completion {
            range = tooltip.completionRange
            replacement = completion
        } else if let cycled = sheet.formulaText(editor.stringValue, cursorAt: fieldEditor.selectedRange.location, cycleReferenceIn: &range) {
            replacement = cycled
        } else {
            return
        }
        guard range.location + range.length <= text.length else { return }
        editor.stringValue = text.replacingCharacters(in: range, with: replacement)
        if let shown = formulaRangeText, shown == range {
            formulaRangeText = NSRange(location: range.location, length: replacement.utf16.count)
        }
        editor.currentEditor()?.selectedRange = NSRange(location: range.location + replacement.utf16.count, length: 0)
        editingTextDidChange?(editor.stringValue)
        updateFunctionTooltip()
    }

    private func drawFunctionTooltip(of sheet: Sheet, dirtyRect: NSRect) {
        guard let tooltip = functionTooltip, let cell = editingCell else { return }
        let frame = sheet.frameOfCell(atColumn: cell.column, row: cell.row)
        guard !frame.isEmpty else { return }
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .left, location: 110)]
        style.defaultTabInterval = 110
        let text = NSAttributedString(string: tooltip.text.replacingOccurrences(of: " \t", with: "\t"),
                                      attributes: [.font: NSFont.systemFont(ofSize: 11), .paragraphStyle: style])
        let size = text.boundingRect(with: NSSize(width: 420, height: 300), options: [.usesLineFragmentOrigin]).size
        let box = NSRect(x: frame.minX, y: editor.frame.maxY + 2, width: ceil(size.width) + 12, height: ceil(size.height) + 8)
        guard box.intersects(dirtyRect) else { return }
        withUprightText(around: box) {
            let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
            NSColor(red: 1, green: 1, blue: 0.86, alpha: 1).setFill()
            path.fill()
            NSColor.gray.setStroke()
            path.lineWidth = 0.5
            path.stroke()
            text.draw(with: box.insetBy(dx: 6, dy: 4), options: [.usesLineFragmentOrigin])
        }
    }

    /// The outline of the range being put into the formula.
    private func drawFormulaRange(of sheet: Sheet, dirtyRect: NSRect) {
        guard let range = formulaRange else { return }
        let frame = rect(of: range, in: sheet)
        guard frame.intersects(dirtyRect) else { return }
        let path = NSBezierPath(rect: frame.insetBy(dx: 1, dy: 1))
        path.lineWidth = 2
        path.setLineDash([4, 3], count: 2, phase: 0)
        NSColor.systemBlue.setStroke()
        path.stroke()
    }

    // MARK: Validation

    /// The edit position's in-cell list (the GTK validation combo) and
    /// input message, refreshed when the cursor moves.
    private var validationCell: CellCoordinate?
    private var validationChoices: [String]?
    private var inputMessage: InputMessage?
    private static let dropdownWidth: CGFloat = 14

    func updateValidationState(_ sheet: Sheet) {
        let cell = sheet.editPosition
        let had = validationChoices != nil || inputMessage != nil
        validationCell = cell
        validationChoices = sheet.validationChoices(atColumn: cell.column, row: cell.row)
        inputMessage = sheet.inputMessage(atColumn: cell.column, row: cell.row)
        if had || validationChoices != nil || inputMessage != nil { needsDisplay = true }
    }

    /// For the headless checks.
    var validationChoicesShown: [String]? { validationChoices }
    var inputMessageShown: InputMessage? { inputMessage }

    /// The arrow just right of the edit cell (where the GTK combo puts
    /// it, clear of the cell's content), in sheet coordinates.
    private func validationDropdownRect(in sheet: Sheet) -> NSRect? {
        guard validationChoices != nil, let cell = validationCell else { return nil }
        let frame = sheet.frameOfCell(atColumn: cell.column, row: cell.row)
        guard !frame.isEmpty else { return nil }
        return NSRect(x: frame.maxX + 1, y: frame.minY, width: Self.dropdownWidth, height: frame.height)
    }

    private func drawValidationDropdown(of sheet: Sheet, dirtyRect: NSRect) {
        guard let arrow = validationDropdownRect(in: sheet), arrow.intersects(dirtyRect) else { return }
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(rect: arrow).fill()
        NSColor.gray.setStroke()
        let box = NSBezierPath(rect: arrow.insetBy(dx: 0.5, dy: 0.5))
        box.lineWidth = 1
        box.stroke()
        let triangle = NSBezierPath()
        let mid = arrow.midX, top = arrow.midY - 2
        triangle.move(to: NSPoint(x: mid - 3.5, y: top))
        triangle.line(to: NSPoint(x: mid + 3.5, y: top))
        triangle.line(to: NSPoint(x: mid, y: top + 4))
        triangle.close()
        NSColor.labelColor.setFill()
        triangle.fill()
    }

    /// The validation list as a menu; choosing enters the value.
    private func showValidationMenu(from arrow: NSRect) {
        guard let choices = validationChoices else { return }
        let menu = NSMenu()
        for choice in choices {
            let item = menu.addItem(withTitle: choice, action: #selector(chooseValidationItem(_:)), keyEquivalent: "")
            item.target = self
        }
        let anchor = viewRect(forSheetRect: arrow)
        menu.popUp(positioning: nil, at: NSPoint(x: anchor.minX, y: anchor.maxY), in: self)
    }

    @objc private func chooseValidationItem(_ sender: NSMenuItem) {
        guard let sheet, let cell = validationCell else { return }
        if isEditing { cancelEditing() }
        do {
            try sheet.setText(sender.title, atColumn: cell.column, row: cell.row, autocorrect: false)
        } catch {
            presentError?(error)
        }
    }

    /// The input message under the edit cell while it is selected (the
    /// GTK pane shows it as a tool tip there).
    private func drawInputMessage(of sheet: Sheet, dirtyRect: NSRect) {
        guard let message = inputMessage, let cell = validationCell else { return }
        let frame = sheet.frameOfCell(atColumn: cell.column, row: cell.row)
        guard !frame.isEmpty else { return }
        let text = NSMutableAttributedString()
        if !message.title.isEmpty {
            text.append(NSAttributedString(string: message.title, attributes: [.font: NSFont.boldSystemFont(ofSize: 11)]))
            if !message.message.isEmpty { text.append(NSAttributedString(string: "\n")) }
        }
        text.append(NSAttributedString(string: message.message, attributes: [.font: NSFont.systemFont(ofSize: 11)]))
        let size = text.boundingRect(with: NSSize(width: 260, height: 200), options: [.usesLineFragmentOrigin]).size
        let box = NSRect(x: frame.minX, y: frame.maxY + 2, width: ceil(size.width) + 12, height: ceil(size.height) + 8)
        guard box.intersects(dirtyRect) else { return }
        withUprightText(around: box) {
            let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
            NSColor(red: 1, green: 1, blue: 0.86, alpha: 1).setFill()
            path.fill()
            NSColor.gray.setStroke()
            path.lineWidth = 0.5
            path.stroke()
            text.draw(with: box.insetBy(dx: 6, dy: 4), options: [.usesLineFragmentOrigin])
        }
    }

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

    /// One tool tip rect per commented cell and per linked range, so
    /// hovering shows the comment or the link's tip (the GTK pane shows
    /// them when the pointer enters the marker or the cell).
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
        for value in sheet.hyperlinkRanges(in: whole) {
            var range = CellRange()
            value.getValue(&range)
            let frame = viewRect(forSheetRect: rect(of: range, in: sheet))
            if !frame.isEmpty {
                addToolTip(frame, owner: self, userData: nil)
            }
        }
        window?.invalidateCursorRects(for: self)
    }

    /// What the tool tip over a cell says: the comment's author, then its
    /// text; else the link's tip, or its target.
    func commentToolTip(atColumn column: Int, row: Int) -> String? {
        guard let sheet else { return nil }
        if let comment = sheet.comment(atColumn: column, row: row) {
            return comment.author.isEmpty ? comment.text : "\(comment.author):\n\(comment.text)"
        }
        if let link = sheet.hyperlink(atColumn: column, row: row) {
            return link.tip ?? link.target
        }
        return nil
    }

    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData: UnsafeMutableRawPointer?) -> String {
        guard let sheet else { return "" }
        let p = sheetPoint(forViewPoint: point)
        return commentToolTip(atColumn: sheet.column(atX: p.x), row: sheet.row(atY: p.y)) ?? ""
    }

    // MARK: Hyperlinks

    /// The cell a single unmodified click landed on when it carried a
    /// link; the link is followed on release when the click selected just
    /// that cell (item_grid_button_released).
    private var linkClickCell: CellCoordinate?

    /// Follow a cell's link: an internal one selects its range through the
    /// engine; a file, mailto, or web target opens with the system.
    func followHyperlink(atColumn column: Int, row: Int) {
        guard let sheet, let link = sheet.hyperlink(atColumn: column, row: row) else { return }
        switch link.kind {
        case .internal:
            do {
                try sheet.followInternalHyperlink(atColumn: column, row: row)
            } catch {
                presentError?(error)
            }
        case .externalFile:
            let path = (link.target as NSString).expandingTildeInPath
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        default:
            if let url = URL(string: link.target) {
                NSWorkspace.shared.open(url)
            }
        }
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

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        validateUserInterfaceItem(item)
    }

    /// The toolbar's AutoSum (cb_autosum): "=SUM()" with the cursor
    /// inside the parentheses, or, while a sum is being typed, the cursor
    /// before its closing parenthesis.
    func autoSum() {
        guard sheet != nil else { return }
        if isEditing {
            let text = editor.stringValue
            guard text.lowercased().hasPrefix("=sum(") else { return }
            editor.currentEditor()?.selectedRange = NSRange(location: max(0, text.utf16.count - 1), length: 0)
            return
        }
        beginEditing(initialText: "=SUM()")
        editor.currentEditor()?.selectedRange = NSRange(location: 5, length: 0)
        editingTextDidChange?(editor.stringValue)
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
        case #selector(selectNextObjectItem(_:)):
            return sheet.sheetObjects.contains { $0.isSelectable && $0.isVisible }
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
        if event.clickCount == 1, let replace = formulaReplacement() {
            let cell = CellCoordinate(column: sheet.column(atX: point.x), row: sheet.row(atY: point.y))
            formulaRangeAnchor = cell
            formulaRangeBase = cell
            takeFormulaRange(CellRange(start: cell, end: cell), replacing: replace)
            return
        }
        if event.clickCount == 1, let arrow = validationDropdownRect(in: sheet), arrow.contains(point) {
            if isEditing { commitEditing(text: editor.stringValue, movement: .none) }
            window?.makeFirstResponder(self)
            showValidationMenu(from: arrow)
            return
        }
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
            // A plain click on a widget works it; Command, Shift, or Option
            // selects it instead (the GTK's object mode).
            if object.widgetKind != .none, selectedObjects.isEmpty,
               event.modifierFlags.isDisjoint(with: [.shift, .command, .option]) {
                actOnWidget(object, at: point)
                if [.scrollbar, .slider].contains(object.widgetKind) { widgetDrag = object }
                return
            }
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
        if selectedObjects.isEmpty, !event.modifierFlags.contains(.shift), isOnSelectionBorder(point, of: sheet) {
            let cell = CellCoordinate(column: sheet.column(atX: point.x), row: sheet.row(atY: point.y))
            let source = sheet.selectedRange
            moveDrag = MoveDrag(source: source, grabColumn: cell.column - source.start.column, grabRow: cell.row - source.start.row)
            return
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
            linkClickCell = event.modifierFlags.isDisjoint(with: [.command, .option, .control])
                && sheet.hyperlink(atColumn: cell.column, row: cell.row) != nil ? cell : nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let sheet else { return }
        if let anchor = formulaRangeAnchor, let textRange = formulaRangeText {
            autoscroll(with: event)
            let point = sheetPoint(forViewPoint: convert(event.locationInWindow, from: nil))
            let cell = CellCoordinate(column: sheet.column(atX: point.x), row: sheet.row(atY: point.y))
            let range = Self.range(from: anchor, to: cell)
            if formulaRange.map({ $0 != range }) ?? true {
                takeFormulaRange(range, replacing: textRange)
            }
            return
        }
        if var drag = objectDrag {
            autoscroll(with: event)
            let point = sheetPoint(forViewPoint: convert(event.locationInWindow, from: nil))
            drag.frames = draggedFrames(drag, dx: point.x - drag.start.x, dy: point.y - drag.start.y,
                                        symmetric: event.modifierFlags.contains(.option), snap: event.modifierFlags.contains(.shift))
            objectDrag = drag
            needsDisplay = true
            return
        }
        if let widget = widgetDrag {
            let point = sheetPoint(forViewPoint: convert(event.locationInWindow, from: nil))
            actOnWidget(widget, at: point)
            return
        }
        if var drag = moveDrag {
            autoscroll(with: event)
            let point = sheetPoint(forViewPoint: convert(event.locationInWindow, from: nil))
            let cell = CellCoordinate(column: sheet.column(atX: point.x), row: sheet.row(atY: point.y))
            let target = moveTarget(for: drag, pointerAt: cell, in: sheet)
            drag.moved = true
            if drag.target.map({ $0 != target }) ?? true {
                drag.target = target
                needsDisplay = true
            }
            moveDrag = drag
            NSCursor.closedHand.set()
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
        if formulaRangeAnchor != nil {
            formulaRangeAnchor = nil
            return
        }
        if let cell = linkClickCell, let sheet {
            linkClickCell = nil
            let selection = sheet.selectedRange
            if selection.start == cell && selection.end == cell {
                followHyperlink(atColumn: cell.column, row: cell.row)
                return
            }
        }
        if let drag = objectDrag {
            objectDrag = nil
            commitObjectDrag(drag)
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            return
        }
        if widgetDrag != nil {
            widgetDrag = nil
            return
        }
        if let drag = moveDrag {
            moveDrag = nil
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            if drag.moved {
                dropMovedCells(drag, copying: event.modifierFlags.contains(.option))
            } else if let sheet {
                // a click on the border without a drag selects the cell under it
                let point = sheetPoint(forViewPoint: convert(event.locationInWindow, from: nil))
                sheet.selectCell(atColumn: sheet.column(atX: point.x), row: sheet.row(atY: point.y))
            }
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

    /// The four bands along a selection's border a drag of the cells
    /// starts from (the GTK's cursor edge, 3 pixels either side).
    static func borderBands(of rect: NSRect) -> [NSRect] {
        let w: CGFloat = 3
        return [
            NSRect(x: rect.minX - w, y: rect.minY - w, width: rect.width + 2 * w, height: 2 * w),
            NSRect(x: rect.minX - w, y: rect.maxY - w, width: rect.width + 2 * w, height: 2 * w),
            NSRect(x: rect.minX - w, y: rect.minY - w, width: 2 * w, height: rect.height + 2 * w),
            NSRect(x: rect.maxX - w, y: rect.minY - w, width: 2 * w, height: rect.height + 2 * w),
        ]
    }

    private func isOnSelectionBorder(_ sheetPoint: NSPoint, of sheet: Sheet) -> Bool {
        let selection = rect(of: sheet.selectedRange, in: sheet)
        guard !selection.isEmpty else { return false }
        if fillHandleRect(for: selection).insetBy(dx: -2, dy: -2).contains(sheetPoint) { return false }
        return Self.borderBands(of: selection).contains { $0.contains(sheetPoint) }
    }

    /// Where the dragged range would land for the pointer at `cell`.
    private func moveTarget(for drag: MoveDrag, pointerAt cell: CellCoordinate, in sheet: Sheet) -> CellRange {
        let width = drag.source.end.column - drag.source.start.column
        let height = drag.source.end.row - drag.source.start.row
        let column = min(max(cell.column - drag.grabColumn, 0), sheet.columnCount - 1 - width)
        let row = min(max(cell.row - drag.grabRow, 0), sheet.rowCount - 1 - height)
        return CellRange(start: CellCoordinate(column: column, row: row), end: CellCoordinate(column: column + width, row: row + height))
    }

    /// Finish a drag of the cells: Option drops a copy (the GTK's Ctrl).
    private func dropMovedCells(_ drag: MoveDrag, copying: Bool) {
        guard let sheet, let target = drag.target, target != drag.source else { return }
        do {
            try sheet.dropSelection(atColumn: target.start.column, row: target.start.row, copying: copying)
            sheet.selectRange(target, editPosition: target.start)
        } catch {
            presentError?(error)
        }
    }

    /// The checks' drag: the selection dropped with its top left at `cell`.
    func dropSelectionForTesting(at cell: CellCoordinate, copying: Bool) {
        guard let sheet else { return }
        let source = sheet.selectedRange
        var drag = MoveDrag(source: source, grabColumn: 0, grabRow: 0)
        drag.target = moveTarget(for: drag, pointerAt: cell, in: sheet)
        dropMovedCells(drag, copying: copying)
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
        // Option-Down opens the cell's validation list.
        if event.modifierFlags.contains(.option), !isEditing, let sheet,
           event.charactersIgnoringModifiers?.unicodeScalars.first?.value == UInt32(NSDownArrowFunctionKey),
           let arrow = validationDropdownRect(in: sheet) {
            showValidationMenu(from: arrow)
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

    /// scg_cursor_move / scg_cursor_extend; `jump` is the GTK's Ctrl+arrow,
    /// to the edge of the run of filled or of empty cells.
    private func move(columns dc: Int, rows dr: Int, extend: Bool, jump: Bool = false) {
        guard let sheet else { return }
        let edit = sheet.editPosition
        let anchor = extend ? (dragAnchor ?? edit) : edit
        var target = extend ? farCorner(of: sheet.selectedRange, from: anchor) : edit
        target = jump ? sheet.cell(target, movedByColumns: dc, rows: dr, base: anchor, jumpingToBoundary: true)
                      : step(target, columns: dc, rows: dr, in: sheet)
        if extend {
            dragAnchor = anchor
            sheet.selectRange(Self.range(from: anchor, to: target), editPosition: anchor)
        } else {
            dragAnchor = target
            sheet.selectCell(atColumn: target.column, row: target.row)
        }
        self.sheet(sheet, makeVisibleColumn: target.column, row: target.row)
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
    /// The arrows follow the screen (gnm-pane.c): Left is the next column
    /// of a right-to-left sheet.
    private var leftward: Int { isRightToLeft ? 1 : -1 }
    override func moveLeft(_ sender: Any?) { move(columns: leftward, rows: 0, extend: false) }
    override func moveRight(_ sender: Any?) { move(columns: -leftward, rows: 0, extend: false) }
    override func moveUpAndModifySelection(_ sender: Any?) { move(columns: 0, rows: -1, extend: true) }
    override func moveDownAndModifySelection(_ sender: Any?) { move(columns: 0, rows: 1, extend: true) }
    override func moveLeftAndModifySelection(_ sender: Any?) { move(columns: leftward, rows: 0, extend: true) }
    override func moveRightAndModifySelection(_ sender: Any?) { move(columns: -leftward, rows: 0, extend: true) }
    override func pageDown(_ sender: Any?) { move(columns: 0, rows: pageRows, extend: false) }
    override func pageUp(_ sender: Any?) { move(columns: 0, rows: -pageRows, extend: false) }
    // ⌘-arrows jump to the edge of the data (the GTK's Ctrl+arrow), Shift
    // extending; Home goes to the row's first column.
    override func moveToBeginningOfLine(_ sender: Any?) { move(columns: -1, rows: 0, extend: false, jump: true) }
    override func moveToLeftEndOfLine(_ sender: Any?) { move(columns: leftward, rows: 0, extend: false, jump: true) }
    override func moveToEndOfLine(_ sender: Any?) { move(columns: 1, rows: 0, extend: false, jump: true) }
    override func moveToRightEndOfLine(_ sender: Any?) { move(columns: -leftward, rows: 0, extend: false, jump: true) }
    override func moveToBeginningOfDocument(_ sender: Any?) { move(columns: 0, rows: -1, extend: false, jump: true) }
    override func moveToEndOfDocument(_ sender: Any?) { move(columns: 0, rows: 1, extend: false, jump: true) }
    override func moveToBeginningOfLineAndModifySelection(_ sender: Any?) { move(columns: -1, rows: 0, extend: true, jump: true) }
    override func moveToLeftEndOfLineAndModifySelection(_ sender: Any?) { move(columns: leftward, rows: 0, extend: true, jump: true) }
    override func moveToEndOfLineAndModifySelection(_ sender: Any?) { move(columns: 1, rows: 0, extend: true, jump: true) }
    override func moveToRightEndOfLineAndModifySelection(_ sender: Any?) { move(columns: -leftward, rows: 0, extend: true, jump: true) }
    override func moveToBeginningOfDocumentAndModifySelection(_ sender: Any?) { move(columns: 0, rows: -1, extend: true, jump: true) }
    override func moveToEndOfDocumentAndModifySelection(_ sender: Any?) { move(columns: 0, rows: 1, extend: true, jump: true) }
    override func scrollToBeginningOfDocument(_ sender: Any?) {
        guard let sheet else { return }
        sheet.selectCell(atColumn: 0, row: sheet.editPosition.row)
        self.sheet(sheet, makeVisibleColumn: 0, row: sheet.editPosition.row)
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
        syncDirection()
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
        syncDirection()
        updateFrameSize()
        headerViews.forEach { $0.invalidateIntrinsicContentSize() }
        updateCommentToolTips()
        needsDisplay = true
        headerViews.forEach { $0.needsDisplay = true }
        geometryDidChange?()
    }

    func sheet(_ sheet: Sheet, cursorDidMoveTo range: CellRange) {
        invalidateSelection(sheet)
        updateValidationState(sheet)
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
        scroll(toFirstScrollingCell: CellCoordinate(column: column, row: row))
    }

    /// Scroll so the cell shows; a scrolling cell must clear the frozen
    /// strips, a frozen one is always in view.
    func sheet(_ sheet: Sheet, makeVisibleColumn column: Int, row: Int) {
        // In view coordinates: a frozen cell is in view already; an
        // unfrozen one must clear the strips, at the top and at the left
        // (the right, for a right-to-left sheet) of the visible rect.
        var frame = viewRect(forSheetRect: sheet.frameOfCell(atColumn: column, row: row))
        if let panes {
            let unfrozen = sheet.unfrozenTopLeft
            if panes.hasColumns, column >= unfrozen.column {
                if !isRightToLeft { frame.origin.x -= panes.width }
                frame.size.width += panes.width
            }
            if panes.hasRows, row >= unfrozen.row {
                frame.origin.y -= panes.height; frame.size.height += panes.height
            }
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
            if let maximumX = grid.maximumScrollOriginX {
                bounds.origin.x = min(bounds.origin.x, max(minimum.x, maximumX))
            }
        }
        return bounds
    }
}
