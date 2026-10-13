import AppKit
import GnmCocoa

/// The GTK standard and format toolbars (GNOME_Gnumeric-gtk.xml) as one
/// NSToolbar: file, clipboard, undo and redo, hyperlink, AutoSum, the
/// function selector, sorting, a chart, zoom; then the font, bold,
/// italic, underline, the alignments, merging, and the number formats.
/// Items act through the responder chain and validate as the menus do;
/// the toggles and pop-ups show the cursor cell's format.
extension WorkbookWindowController: NSToolbarDelegate {
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

    static let defaultToolbarItems: [NSToolbarItem.Identifier] = {
        let names = ["new", "open", "save", "print", "printPreview", "|", "cut", "copy", "paste", "|", "undo", "redo", "|",
                     "autosum", "function", "sortAscending", "sortDescending", "chart", "objects", "zoom", "~",
                     "fontFamily", "fontSize", "bold", "italic", "underline", "|", "alignLeft", "alignCenter", "alignRight", "merge", "|",
                     "accounting", "percent", "thousands", "morePrecision", "lessPrecision", "|",
                     "indentLess", "indentMore", "superscript", "subscript", "borders", "textColor", "fillColor"]
        return names.map { $0 == "|" ? .space : $0 == "~" ? .flexibleSpace : NSToolbarItem.Identifier($0) }
    }()

    func installToolbar(in window: NSWindow) {
        let toolbar = NSToolbar(identifier: "WorkbookToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .expanded
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Self.defaultToolbarItems }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.toolbarSpecs.map { NSToolbarItem.Identifier($0.identifier) }
            + ["zoom", "fontFamily", "fontSize", "borders", "textColor", "fillColor", "objects"].map { NSToolbarItem.Identifier($0) }
            + [.space, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier.rawValue {
        case "zoom":
            let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 84, height: 24), pullsDown: false)
            popUp.addItems(withTitles: Self.zoomLevels.map(\.0))
            popUp.selectItem(at: 2)
            popUp.target = self
            popUp.action = #selector(zoomChosen(_:))
            item.view = popUp
            item.label = Localization.title("Zoom")
            item.toolTip = Localization.title("Zoom")
        case "fontFamily":
            let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 150, height: 24), pullsDown: false)
            popUp.addItems(withTitles: FormatCellsModel.fontFamilies)
            popUp.target = self
            popUp.action = #selector(fontFamilyChosen(_:))
            item.view = popUp
            item.label = Localization.title("Font")
            item.toolTip = Localization.title("Font")
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
            item.view = popUp
            item.label = Localization.title("Objects")
            item.toolTip = Localization.title("Insert a shape or a widget")
        case "borders":
            let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 150, height: 24), pullsDown: true)
            popUp.addItem(withTitle: Localization.title("Borders"))
            for preset in Sheet.allBorderPresets {
                let menuItem = NSMenuItem(title: Sheet.nameOfBorderPreset(Sheet.BorderPreset(rawValue: preset.intValue) ?? .none), action: #selector(borderPresetChosen(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.tag = preset.intValue
                popUp.menu?.addItem(menuItem)
            }
            item.view = popUp
            item.label = Localization.title("Borders")
            item.toolTip = Localization.title("Borders")
        case "textColor", "fillColor":
            let well = NSColorWell(frame: NSRect(x: 0, y: 0, width: 40, height: 24))
            well.isContinuous = false
            well.color = itemIdentifier.rawValue == "textColor" ? .black : .white
            well.target = self
            well.action = itemIdentifier.rawValue == "textColor" ? #selector(textColorChosen(_:)) : #selector(fillColorChosen(_:))
            item.view = well
            item.label = Localization.title(itemIdentifier.rawValue == "textColor" ? "Text Color" : "Fill Color")
            item.toolTip = item.label
        case "fontSize":
            let combo = NSComboBox(frame: NSRect(x: 0, y: 0, width: 60, height: 24))
            combo.addItems(withObjectValues: Self.fontSizes)
            combo.target = self
            combo.action = #selector(fontSizeChosen(_:))
            combo.delegate = self
            item.view = combo
            item.label = Localization.title("Size")
            item.toolTip = Localization.title("Font size")
        default:
            guard let spec = Self.toolbarSpecs.first(where: { $0.identifier == itemIdentifier.rawValue }) else { return nil }
            item.label = Localization.title(spec.label)
            item.toolTip = Localization.title(spec.label)
            let image = NSImage(systemSymbolName: spec.symbol, accessibilityDescription: spec.label)
                ?? NSImage(systemSymbolName: "questionmark", accessibilityDescription: spec.label)
            if spec.toggles {
                let button = NSButton(image: image ?? NSImage(), target: nil, action: spec.action)
                button.bezelStyle = .texturedRounded
                button.setButtonType(.pushOnPushOff)
                button.frame = NSRect(x: 0, y: 0, width: 36, height: 24)
                item.view = button
                // the item's own action is what validation looks up
                item.action = spec.action
                item.target = nil
            } else {
                item.image = image
                item.action = spec.action
                item.target = nil
                item.isBordered = true
            }
        }
        return item
    }

    // MARK: State

    /// The toggles and pop-ups follow the cursor cell's format
    /// (wbcg_update_ui's toolbar updates).
    func updateToolbarState() {
        guard let toolbar = window?.toolbar, let sheet = gridView.sheet else { return }
        let format = sheet.formatOfSelection
        let alignment = format.horizontalAlignment?.intValue ?? 0x01
        for item in toolbar.items {
            switch item.itemIdentifier.rawValue {
            case "bold": (item.view as? NSButton)?.state = format.bold?.boolValue == true ? .on : .off
            case "italic": (item.view as? NSButton)?.state = format.italic?.boolValue == true ? .on : .off
            case "underline": (item.view as? NSButton)?.state = (format.underline?.intValue ?? 0) != UnderlineStyle.none.rawValue ? .on : .off
            case "alignLeft": (item.view as? NSButton)?.state = alignment == 0x02 ? .on : .off
            case "alignCenter": (item.view as? NSButton)?.state = alignment == 0x08 ? .on : .off
            case "alignRight": (item.view as? NSButton)?.state = alignment == 0x04 ? .on : .off
            case "centerAcross": (item.view as? NSButton)?.state = alignment == 0x40 ? .on : .off
            case "superscript": (item.view as? NSButton)?.state = sheet.fontScriptOfSelection == .superscript ? .on : .off
            case "subscript": (item.view as? NSButton)?.state = sheet.fontScriptOfSelection == .subscript ? .on : .off
            case "textColor":
                if let well = item.view as? NSColorWell, let color = format.textColor, let ns = NSColor(cgColor: color) { well.color = ns }
            case "fillColor":
                if let well = item.view as? NSColorWell {
                    well.color = format.fillsBackground?.boolValue == true ? (format.backgroundColor.flatMap(NSColor.init(cgColor:)) ?? .white) : .white
                }
            case "fontFamily":
                if let popUp = item.view as? NSPopUpButton, let name = format.fontName, popUp.titleOfSelectedItem != name {
                    popUp.selectItem(withTitle: name)
                }
            case "fontSize":
                if let combo = item.view as? NSComboBox, let size = format.fontSize?.doubleValue, combo.currentEditor() == nil {
                    combo.stringValue = size == size.rounded() ? String(Int(size)) : String(size)
                }
            case "zoom":
                if let popUp = item.view as? NSPopUpButton {
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
        guard let toolbar = window?.toolbar else { return "no toolbar" }
        var parts: [String] = []
        for item in toolbar.items {
            if let button = item.view as? NSButton, button.allowsMixedState == false, Self.toolbarSpecs.first(where: { $0.identifier == item.itemIdentifier.rawValue })?.toggles == true {
                parts.append("\(item.itemIdentifier.rawValue)=\(button.state == .on ? 1 : 0)")
            } else if let popUp = item.view as? NSPopUpButton {
                parts.append("\(item.itemIdentifier.rawValue)=\(popUp.titleOfSelectedItem ?? "")")
            } else if let combo = item.view as? NSComboBox {
                parts.append("\(item.itemIdentifier.rawValue)=\(combo.stringValue)")
            }
        }
        return parts.joined(separator: " ")
    }

    /// Press a toolbar item for the checks.
    func performToolbarItemForTesting(_ identifier: String) {
        guard let item = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == identifier }), let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
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
