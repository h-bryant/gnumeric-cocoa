import AppKit
import GnmCocoa

/// The GTK standard and format toolbars (GNOME_Gnumeric-gtk.xml) as one
/// ribbon of buttons above the formula bar: file, clipboard, undo and
/// redo, hyperlink, AutoSum, the function selector, sorting, a chart,
/// zoom; then the font, bold, italic, underline, the alignments, merging,
/// and the number formats.  The ribbon wraps into as many rows as the
/// window's width needs (Henry's choice, 2026-11-09; an NSToolbar puts
/// what does not fit into an overflow menu instead, and its user
/// customization went with it).  Items act through the responder chain
/// and validate as the menus do; the toggles and pop-ups show the cursor
/// cell's format.
extension WorkbookWindowController {
    private static let fontSizes = ["6", "7", "8", "9", "10", "11", "12", "14", "16", "18", "20", "24", "28", "32", "36", "48", "72"]
    private static let zoomLevels: [(String, Double)] = [("50%", 0.5), ("75%", 0.75), ("100%", 1), ("125%", 1.25), ("150%", 1.5), ("200%", 2)]

    struct ToolbarSpec {
        let identifier: String
        let label: String
        let symbol: String
        let action: Selector
        let toggles: Bool
    }

    static let toolbarSpecs: [ToolbarSpec] = [
        ToolbarSpec(identifier: "new", label: "New", symbol: "doc", action: #selector(NSDocumentController.newDocument(_:)), toggles: false),
        ToolbarSpec(identifier: "open", label: "Open", symbol: "folder", action: #selector(NSDocumentController.openDocument(_:)), toggles: false),
        ToolbarSpec(identifier: "save", label: "Save", symbol: "square.and.arrow.down", action: #selector(NSDocument.save(_:)), toggles: false),
        ToolbarSpec(identifier: "print", label: "Print", symbol: "printer", action: Selector(("printSheet:")), toggles: false),
        ToolbarSpec(identifier: "printPreview", label: "Print Preview", symbol: "doc.text.magnifyingglass", action: Selector(("printPreview:")), toggles: false),
        ToolbarSpec(identifier: "cut", label: "Cut", symbol: "scissors", action: Selector(("cut:")), toggles: false),
        ToolbarSpec(identifier: "copy", label: "Copy", symbol: "doc.on.doc", action: Selector(("copy:")), toggles: false),
        ToolbarSpec(identifier: "paste", label: "Paste", symbol: "doc.on.clipboard", action: Selector(("paste:")), toggles: false),
        ToolbarSpec(identifier: "undo", label: "Undo", symbol: "arrow.uturn.backward", action: Selector(("undo:")), toggles: false),
        ToolbarSpec(identifier: "redo", label: "Redo", symbol: "arrow.uturn.forward", action: Selector(("redo:")), toggles: false),
        ToolbarSpec(identifier: "hyperlink", label: "Hyperlink", symbol: "link", action: Selector(("insertHyperlink:")), toggles: false),
        ToolbarSpec(identifier: "autosum", label: "Sum", symbol: "sum", action: Selector(("autoSum:")), toggles: false),
        ToolbarSpec(identifier: "function", label: "Function", symbol: "function", action: Selector(("insertFunction:")), toggles: false),
        ToolbarSpec(identifier: "sortAscending", label: "Sort A→Z", symbol: "arrow.up", action: Selector(("sortAscending:")), toggles: false),
        ToolbarSpec(identifier: "sortDescending", label: "Sort Z→A", symbol: "arrow.down", action: Selector(("sortDescending:")), toggles: false),
        ToolbarSpec(identifier: "chart", label: "Chart", symbol: "chart.bar", action: Selector(("insertChart:")), toggles: false),
        ToolbarSpec(identifier: "bold", label: "Bold", symbol: "bold", action: Selector(("toggleBold:")), toggles: true),
        ToolbarSpec(identifier: "italic", label: "Italic", symbol: "italic", action: Selector(("toggleItalic:")), toggles: true),
        ToolbarSpec(identifier: "underline", label: "Underline", symbol: "underline", action: Selector(("toggleUnderline:")), toggles: true),
        ToolbarSpec(identifier: "alignLeft", label: "Left", symbol: "text.alignleft", action: Selector(("alignLeft:")), toggles: true),
        ToolbarSpec(identifier: "alignCenter", label: "Center", symbol: "text.aligncenter", action: Selector(("alignCenter:")), toggles: true),
        ToolbarSpec(identifier: "alignRight", label: "Right", symbol: "text.alignright", action: Selector(("alignRight:")), toggles: true),
        ToolbarSpec(identifier: "centerAcross", label: "Across", symbol: "text.justify", action: Selector(("centerAcrossSelection:")), toggles: true),
        ToolbarSpec(identifier: "merge", label: "Merge", symbol: "rectangle.and.arrow.up.right.and.arrow.down.left", action: Selector(("mergeCells:")), toggles: false),
        ToolbarSpec(identifier: "unmerge", label: "Unmerge", symbol: "rectangle.split.2x1", action: Selector(("unmergeCells:")), toggles: false),
        ToolbarSpec(identifier: "accounting", label: "Accounting", symbol: "dollarsign.circle", action: Selector(("formatAsAccounting:")), toggles: false),
        ToolbarSpec(identifier: "percent", label: "Percent", symbol: "percent", action: Selector(("formatAsPercentage:")), toggles: false),
        ToolbarSpec(identifier: "thousands", label: "Thousands", symbol: "textformat.123", action: Selector(("formatWithThousands:")), toggles: false),
        ToolbarSpec(identifier: "morePrecision", label: "More Decimals", symbol: "plus.circle", action: Selector(("increasePrecision:")), toggles: false),
        ToolbarSpec(identifier: "lessPrecision", label: "Fewer Decimals", symbol: "minus.circle", action: Selector(("decreasePrecision:")), toggles: false),
        ToolbarSpec(identifier: "indentLess", label: "Less Indent", symbol: "decrease.indent", action: Selector(("decreaseIndent:")), toggles: false),
        ToolbarSpec(identifier: "indentMore", label: "More Indent", symbol: "increase.indent", action: Selector(("increaseIndent:")), toggles: false),
        ToolbarSpec(identifier: "superscript", label: "Superscript", symbol: "textformat.superscript", action: Selector(("toggleSuperscript:")), toggles: true),
        ToolbarSpec(identifier: "subscript", label: "Subscript", symbol: "textformat.subscript", action: Selector(("toggleSubscript:")), toggles: true),
        ToolbarSpec(identifier: "clearFill", label: "No Fill", symbol: "paintbrush", action: Selector(("clearFill:")), toggles: false),
    ]

    /// The ribbon's order: "|" is a separator, "~" the wider gap where the
    /// GTK's standard toolbar ends and its format toolbar begins.
    static let defaultToolbarItems: [String] = [
        "new", "open", "save", "print", "printPreview", "|", "cut", "copy", "paste", "|", "undo", "redo", "|",
        "autosum", "function", "sortAscending", "sortDescending", "chart", "objects", "zoom", "~",
        "fontFamily", "fontSize", "bold", "italic", "underline", "|", "alignLeft", "alignCenter", "alignRight", "merge", "|",
        "accounting", "percent", "thousands", "morePrecision", "lessPrecision", "|",
        "indentLess", "indentMore", "superscript", "subscript", "borders", "textColor", "fillColor",
    ]

    /// The ribbon with every item in the default order.
    func makeToolbarRibbon() -> ToolbarRibbon {
        let ribbon = ToolbarRibbon()
        for identifier in Self.defaultToolbarItems {
            switch identifier {
            case "|": ribbon.addSeparator()
            case "~": ribbon.addGap()
            default:
                if let (view, label) = makeToolbarView(for: identifier) {
                    ribbon.add(view, identifier: identifier, label: label)
                }
            }
        }
        return ribbon
    }

    /// For the headless checks and the hooks: an item's view, the labels,
    /// and the count.
    func toolbarItemView(_ identifier: String) -> NSView? { toolbarRibbon?.view(for: identifier) }
    var toolbarLabelsForTesting: [String] { toolbarRibbon?.entries.map(\.label) ?? [] }
    var toolbarItemCountForTesting: Int { toolbarRibbon?.entries.count ?? 0 }

    /// One item's view and label; nil for an unknown identifier.
    private func makeToolbarView(for identifier: String) -> (NSView, String)? {
        switch identifier {
        case "zoom":
            let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 84, height: 24), pullsDown: false)
            popUp.addItems(withTitles: Self.zoomLevels.map(\.0))
            popUp.selectItem(at: 2)
            popUp.target = self
            popUp.action = #selector(zoomChosen(_:))
            popUp.toolTip = Localization.title("Zoom")
            return (popUp, Localization.title("Zoom"))
        case "fontFamily":
            let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 150, height: 24), pullsDown: false)
            popUp.addItems(withTitles: FormatCellsModel.fontFamilies)
            popUp.target = self
            popUp.action = #selector(fontFamilyChosen(_:))
            popUp.toolTip = Localization.title("Font")
            return (popUp, Localization.title("Font"))
        case "objects":
            // The GTK object toolbar as one pull-down.
            let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 120, height: 24), pullsDown: true)
            popUp.addItem(withTitle: Localization.title("Objects"))
            for (tag, title) in Self.objectToolbarEntries {
                let menuItem = NSMenuItem(title: title, action: #selector(objectKindChosen(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.tag = tag
                popUp.menu?.addItem(menuItem)
            }
            popUp.toolTip = Localization.title("Insert a shape or a widget")
            return (popUp, Localization.title("Objects"))
        case "borders":
            let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 150, height: 24), pullsDown: true)
            popUp.addItem(withTitle: Localization.title("Borders"))
            for preset in Sheet.allBorderPresets {
                let menuItem = NSMenuItem(title: Sheet.nameOfBorderPreset(Sheet.BorderPreset(rawValue: preset.intValue) ?? .none), action: #selector(borderPresetChosen(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.tag = preset.intValue
                popUp.menu?.addItem(menuItem)
            }
            popUp.toolTip = Localization.title("Borders")
            return (popUp, Localization.title("Borders"))
        case "textColor", "fillColor":
            let well = ToolbarColorWell(frame: NSRect(x: 0, y: 0, width: 40, height: 24))
            let isText = identifier == "textColor"
            well.show(isText ? .black : .white)
            well.onPick = { [weak self, weak well] in
                guard let self, let well else { return }
                if isText { textColorChosen(well) } else { fillColorChosen(well) }
            }
            let label = Localization.title(isText ? "Text Color" : "Fill Color")
            well.toolTip = label
            return (well, label)
        case "fontSize":
            let combo = NSComboBox(frame: NSRect(x: 0, y: 0, width: 60, height: 24))
            combo.addItems(withObjectValues: Self.fontSizes)
            combo.target = self
            combo.action = #selector(fontSizeChosen(_:))
            combo.delegate = self
            combo.toolTip = Localization.title("Font size")
            return (combo, Localization.title("Size"))
        default:
            guard let spec = Self.toolbarSpecs.first(where: { $0.identifier == identifier }) else { return nil }
            let label = Localization.title(spec.label)
            let image = NSImage(systemSymbolName: spec.symbol, accessibilityDescription: spec.label)
                ?? NSImage(systemSymbolName: "questionmark", accessibilityDescription: spec.label)
            let button = RibbonButton(image: image ?? NSImage(), target: nil, action: spec.action)
            button.bezelStyle = .texturedRounded
            button.setButtonType(spec.toggles ? .pushOnPushOff : .momentaryPushIn)
            button.frame = NSRect(x: 0, y: 0, width: 36, height: 24)
            button.toolTip = label
            return (button, label)
        }
    }

    // MARK: State

    /// The toggles and pop-ups follow the cursor cell's format
    /// (wbcg_update_ui's toolbar updates).
    func updateToolbarState() {
        guard let ribbon = toolbarRibbon, let sheet = gridView.sheet else { return }
        let format = sheet.formatOfSelection
        let alignment = format.horizontalAlignment?.intValue ?? 0x01
        for entry in ribbon.entries {
            let view = entry.view
            switch entry.identifier {
            case "bold": (view as? NSButton)?.state = format.bold?.boolValue == true ? .on : .off
            case "italic": (view as? NSButton)?.state = format.italic?.boolValue == true ? .on : .off
            case "underline": (view as? NSButton)?.state = (format.underline?.intValue ?? 0) != UnderlineStyle.none.rawValue ? .on : .off
            case "alignLeft": (view as? NSButton)?.state = alignment == 0x02 ? .on : .off
            case "alignCenter": (view as? NSButton)?.state = alignment == 0x08 ? .on : .off
            case "alignRight": (view as? NSButton)?.state = alignment == 0x04 ? .on : .off
            case "centerAcross": (view as? NSButton)?.state = alignment == 0x40 ? .on : .off
            case "superscript": (view as? NSButton)?.state = sheet.fontScriptOfSelection == .superscript ? .on : .off
            case "subscript": (view as? NSButton)?.state = sheet.fontScriptOfSelection == .subscript ? .on : .off
            case "textColor":
                if let well = view as? ToolbarColorWell, let color = format.textColor, let ns = NSColor(cgColor: color) { well.show(ns) }
            case "fillColor":
                if let well = view as? ToolbarColorWell {
                    well.show(format.fillsBackground?.boolValue == true ? (format.backgroundColor.flatMap(NSColor.init(cgColor:)) ?? .white) : .white)
                }
            case "fontFamily":
                if let popUp = view as? NSPopUpButton, let name = format.fontName, popUp.titleOfSelectedItem != name {
                    popUp.selectItem(withTitle: name)
                }
            case "fontSize":
                if let combo = view as? NSComboBox, let size = format.fontSize?.doubleValue, combo.currentEditor() == nil {
                    combo.stringValue = size == size.rounded() ? String(Int(size)) : String(size)
                }
            case "zoom":
                if let popUp = view as? NSPopUpButton {
                    let percent = "\(Int((sheet.zoomFactor * 100).rounded()))%"
                    if popUp.titleOfSelectedItem != percent {
                        if popUp.indexOfItem(withTitle: percent) < 0 { popUp.addItem(withTitle: percent) }
                        popUp.selectItem(withTitle: percent)
                    }
                }
            default: break
            }
        }
    }

    /// The toolbar's state for the checks: "bold=1 italic=0 … align=8".
    var toolbarStateForTesting: String {
        guard let ribbon = toolbarRibbon else { return "no toolbar" }
        var parts: [String] = []
        for entry in ribbon.entries {
            if let button = entry.view as? NSButton, Self.toolbarSpecs.first(where: { $0.identifier == entry.identifier })?.toggles == true {
                parts.append("\(entry.identifier)=\(button.state == .on ? 1 : 0)")
            } else if let popUp = entry.view as? NSPopUpButton {
                parts.append("\(entry.identifier)=\(popUp.titleOfSelectedItem ?? "")")
            } else if let combo = entry.view as? NSComboBox {
                parts.append("\(entry.identifier)=\(combo.stringValue)")
            }
        }
        return parts.joined(separator: " ")
    }

    /// Press a toolbar button for the checks: its action to the target a
    /// click would reach (through the ribbon's own search, since the
    /// headless window is never key).
    func performToolbarItemForTesting(_ identifier: String) {
        guard let ribbon = toolbarRibbon, let button = ribbon.view(for: identifier) as? NSButton, let action = button.action,
              let target = button.target ?? ribbon.target(for: action) else { return }
        _ = target.perform(action, with: button)
    }

    // MARK: Actions

    @objc func zoomChosen(_ sender: NSPopUpButton) {
        guard let level = Self.zoomLevels.first(where: { $0.0 == sender.titleOfSelectedItem }) else { return }
        runSizeCommand { sheet in try sheet.setZoomFactor(level.1, forAllSheets: false) }
    }

    @objc func fontFamilyChosen(_ sender: NSPopUpButton) {
        guard let name = sender.titleOfSelectedItem else { return }
        runSizeCommand { sheet in
            let format = CellFormat()
            format.fontName = name
            try sheet.apply(format)
        }
    }

    @objc func fontSizeChosen(_ sender: NSComboBox) {
        guard let size = Double(sender.stringValue.trimmingCharacters(in: .whitespaces)), size >= 1, size <= 400 else { return }
        runSizeCommand { sheet in
            let format = CellFormat()
            format.fontSize = NSNumber(value: size)
            try sheet.apply(format)
        }
        window?.makeFirstResponder(gridView)
    }

    @objc func alignLeft(_ sender: Any?) { runSizeCommand { try $0.toggleHorizontalAlignmentOfSelection(0x02) } }
    @objc func alignCenter(_ sender: Any?) { runSizeCommand { try $0.toggleHorizontalAlignmentOfSelection(0x08) } }
    @objc func alignRight(_ sender: Any?) { runSizeCommand { try $0.toggleHorizontalAlignmentOfSelection(0x04) } }
    @objc func centerAcrossSelection(_ sender: Any?) { runSizeCommand { try $0.toggleHorizontalAlignmentOfSelection(0x40) } }
    @objc func formatAsAccounting(_ sender: Any?) { runSizeCommand { try $0.changeNumberFormatOfSelection(.accounting) } }
    @objc func formatAsPercentage(_ sender: Any?) { runSizeCommand { try $0.changeNumberFormatOfSelection(.percentage) } }
    @objc func formatWithThousands(_ sender: Any?) { runSizeCommand { try $0.changeNumberFormatOfSelection(.toggleThousands) } }
    @objc func increasePrecision(_ sender: Any?) { runSizeCommand { try $0.changeNumberFormatOfSelection(.increasePrecision) } }
    @objc func decreasePrecision(_ sender: Any?) { runSizeCommand { try $0.changeNumberFormatOfSelection(.decreasePrecision) } }

    @objc func increaseIndent(_ sender: Any?) { runSizeCommand { try $0.increaseIndentOfSelection() } }
    @objc func decreaseIndent(_ sender: Any?) { runSizeCommand { try $0.decreaseIndentOfSelection() } }
    @objc func toggleSuperscript(_ sender: Any?) { runSizeCommand { try $0.toggleFontScriptOfSelection(.superscript) } }
    @objc func toggleSubscript(_ sender: Any?) { runSizeCommand { try $0.toggleFontScriptOfSelection(.subscript) } }

    @objc func borderPresetChosen(_ sender: NSMenuItem) {
        guard let preset = Sheet.BorderPreset(rawValue: sender.tag) else { return }
        runSizeCommand { try $0.setBordersOfSelection(preset) }
    }

    @objc func textColorChosen(_ sender: NSColorWell) {
        runSizeCommand { sheet in
            let format = CellFormat()
            format.textColor = sender.color.cgColor
            try sheet.apply(format)
        }
    }

    @objc func fillColorChosen(_ sender: NSColorWell) {
        runSizeCommand { sheet in
            let format = CellFormat()
            format.fillsBackground = true
            format.backgroundColor = sender.color.cgColor
            try sheet.apply(format)
        }
    }

    /// The color combo's "Automatic": no fill.
    @objc func clearFill(_ sender: Any?) {
        runSizeCommand { sheet in
            let format = CellFormat()
            format.fillsBackground = false
            try sheet.apply(format)
        }
    }

    /// cb_autosum: start "=SUM()" with the cursor inside, or put the
    /// cursor before the closing parenthesis of a sum being typed.
    @objc func autoSum(_ sender: Any?) {
        gridView.autoSum()
    }
}

extension WorkbookWindowController: NSComboBoxDelegate {
    func comboBoxSelectionDidChange(_ notification: Notification) {
        guard let combo = notification.object as? NSComboBox, let value = combo.objectValueOfSelectedItem as? String else { return }
        combo.stringValue = value
        fontSizeChosen(combo)
    }
}

/// A toolbar color well that applies every color the panel gives it.  A
/// well's action is not the way to learn of a choice: the panel pushes
/// colors into its well with `_takeColorFromAndSendActionIfContinuous:`,
/// so a non-continuous well only changes color, and a continuous one
/// would run a command for every step of a drag across the picker.  The
/// color is watched instead, while the well is active (the panel's; AppKit
/// sets the color on its own while the well is being set up, which must
/// apply nothing), changes within a short interval coalescing into one
/// command and the last one applied at once when the well deactivates.
/// A color dropped on the well arrives through the action, applied at
/// once.  `show(_:)` is the toolbar's own refresh from the cell's format.
@MainActor
final class ToolbarColorWell: NSColorWell {
    var onPick: (() -> Void)?
    private var showing = false
    private var applied: NSColor?
    private var pending: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isContinuous = false
        target = self
        action = #selector(pickNow(_:))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ color: NSColor) {
        showing = true
        self.color = color
        showing = false
        applied = color
    }

    override var color: NSColor {
        didSet {
            guard !showing, isActive, color != oldValue else { return }
            pending?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.pickNow(nil) }
            pending = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
        }
    }

    /// Apply the color now, unless it is the one applied (or shown) last.
    @objc func pickNow(_ sender: Any?) {
        pending?.cancel()
        pending = nil
        guard color != applied else { return }
        applied = color
        onPick?()
    }

    override func deactivate() {
        super.deactivate()
        if pending != nil { pickNow(nil) }
    }
}

/// A toolbar button: it validates like a menu item (NSValidatedUserInterfaceItem
/// wants an action and a tag, which every control has).
final class RibbonButton: NSButton, NSValidatedUserInterfaceItem {}

/// The toolbar as a strip of views that wraps: the items go left to right,
/// each row taking what fits in the width, and the strip is as tall as its
/// rows (a separator or gap that would start a row is left out of it).
/// The buttons validate through the responder chain whenever the window
/// updates, as NSToolbar's items do.
@MainActor
final class ToolbarRibbon: NSView {
    struct Entry {
        let identifier: String
        let view: NSView
        let label: String
    }
    private(set) var entries: [Entry] = []
    /// The entries' views with the separators and gaps, in order.
    private var pieces: [NSView] = []
    private var spacers: Set<NSView> = []
    private static let inset: CGFloat = 8
    private static let spacing: CGFloat = 4
    private static let rowHeight: CGFloat = 28
    private static let padding: CGFloat = 4
    private var heightConstraint: NSLayoutConstraint!
    /// The rows the last layout needed.
    private(set) var rowCount = 1
    private var updateObserver: (any NSObjectProtocol)?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightConstraint = heightAnchor.constraint(equalToConstant: Self.rowHeight + 2 * Self.padding)
        heightConstraint.isActive = true
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func add(_ view: NSView, identifier: String, label: String) {
        entries.append(Entry(identifier: identifier, view: view, label: label))
        pieces.append(view)
        addSubview(view)
    }

    func addSeparator() {
        let box = NSBox(frame: NSRect(x: 0, y: 0, width: 1, height: 18))
        box.boxType = .separator
        spacers.insert(box)
        pieces.append(box)
        addSubview(box)
    }

    func addGap() {
        let gap = NSView(frame: NSRect(x: 0, y: 0, width: 12, height: 1))
        spacers.insert(gap)
        pieces.append(gap)
        addSubview(gap)
    }

    func view(for identifier: String) -> NSView? { entries.first { $0.identifier == identifier }?.view }

    /// Each piece's frame for a width (empty for a spacer left out), and
    /// the rows used.
    private func arrange(width: CGFloat) -> (frames: [NSRect], rows: Int) {
        var frames: [NSRect] = []
        var x = Self.inset
        var row = 0
        let limit = max(width - Self.inset, Self.inset + 1)
        for piece in pieces {
            let size = piece.frame.size
            if x > Self.inset, x + size.width > limit {
                row += 1
                x = Self.inset
            }
            if spacers.contains(piece), x == Self.inset {
                frames.append(.zero)
                continue
            }
            let y = Self.padding + CGFloat(row) * Self.rowHeight + (Self.rowHeight - size.height) / 2
            frames.append(NSRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + Self.spacing
        }
        return (frames, row + 1)
    }

    override func layout() {
        super.layout()
        let (frames, rows) = arrange(width: bounds.width)
        for (piece, frame) in zip(pieces, frames) {
            piece.isHidden = frame.isEmpty
            if !frame.isEmpty { piece.frame = frame }
        }
        rowCount = rows
        let height = CGFloat(rows) * Self.rowHeight + 2 * Self.padding
        if heightConstraint.constant != height { heightConstraint.constant = height }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer = updateObserver { NotificationCenter.default.removeObserver(observer) }
        updateObserver = nil
        guard let window else { return }
        updateObserver = NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.validateButtons() }
        }
    }

    /// The object a nil-targeted action reaches from this window: along
    /// the responder chain from the first responder, then the window's
    /// delegate, controller, and document, the application, its delegate,
    /// and the document controller (NSApplication's own search, which
    /// starts at the key window and so finds nothing headless).
    func target(for action: Selector) -> AnyObject? {
        var responder: NSResponder? = window?.firstResponder ?? window
        while let current = responder {
            if current.responds(to: action) { return current }
            responder = current.nextResponder
        }
        let rest: [AnyObject?] = [window?.delegate, window?.windowController, window?.windowController?.document as AnyObject?,
                                  NSApp, NSApp.delegate, NSDocumentController.shared]
        return rest.compactMap { $0 }.first { $0.responds(to: action) }
    }

    /// What NSToolbar does for its items: the target the action would
    /// reach says whether a button is enabled.
    func validateButtons() {
        for entry in entries {
            guard let button = entry.view as? RibbonButton, let action = button.action else { continue }
            let target = button.target ?? target(for: action)
            let enabled = (target as? any NSUserInterfaceValidations)?.validateUserInterfaceItem(button) ?? (target != nil)
            if button.isEnabled != enabled { button.isEnabled = enabled }
        }
    }
}
