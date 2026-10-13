import AppKit
import GnmCocoa

/// Editable state behind the Format Cells sheet.  Values start from the
/// selection's common format (mixed properties get a neutral default and are
/// flagged), and only the properties the user touched are applied, so an
/// untouched mixed property stays mixed.
@MainActor
@Observable
final class FormatCellsModel {
    enum Key: Hashable {
        case numberFormat, horizontalAlignment, verticalAlignment, wrapsText
        case fontName, fontSize, bold, italic, underline, strikethrough, textColor
        case fill, backgroundColor, border(BorderEdge)
        case contentsLocked, contentsHidden
    }

    /// Number format categories offered by the Number tab.
    enum Category: String, CaseIterable, Identifiable {
        case general = "General", number = "Number", currency = "Currency", accounting = "Accounting"
        case date = "Date", time = "Time", percentage = "Percentage", fraction = "Fraction"
        case scientific = "Scientific", text = "Text", custom = "Custom"
        var id: String { rawValue }

        init(family: NumberFormatFamily) {
            switch family {
            case .general: self = .general
            case .number: self = .number
            case .currency: self = .currency
            case .accounting: self = .accounting
            case .date: self = .date
            case .time: self = .time
            case .percentage: self = .percentage
            case .fraction: self = .fraction
            case .scientific: self = .scientific
            case .text: self = .text
            default: self = .custom
            }
        }

        var family: NumberFormatFamily? {
            switch self {
            case .general: return .general
            case .number: return .number
            case .currency: return .currency
            case .accounting: return .accounting
            case .date: return .date
            case .time: return .time
            case .percentage: return .percentage
            case .fraction: return .fraction
            case .scientific: return .scientific
            case .text: return .text
            case .custom: return nil
            }
        }

        var usesDecimals: Bool { [.number, .currency, .accounting, .percentage, .scientific].contains(self) }
        var usesThousands: Bool { [.number, .currency, .accounting].contains(self) }
        /// Preset codes for the families goffice does not generate.
        var presets: [String] {
            switch self {
            case .date: return ["yyyy-mm-dd", "d-mmm-yyyy", "mm/dd/yyyy", "dd/mm/yyyy", "dddd, d mmmm yyyy", "mmm yyyy"]
            case .time: return ["h:mm:ss", "hh:mm", "h:mm AM/PM", "h:mm:ss AM/PM", "[h]:mm:ss"]
            case .fraction: return ["# ?/?", "# ??/??", "# ???/???", "# ?/2", "# ?/4", "# ?/8", "# ?/16"]
            case .text: return ["@"]
            default: return []
            }
        }
    }

    let isMultiCell: Bool
    private(set) var touched: Set<Key> = []
    /// Properties that differ across the selection; shown as such until touched.
    private(set) var mixed: Set<Key> = []

    var category: Category { didSet { noteNumberFormatChange() } }
    var decimals: Int { didSet { noteNumberFormatChange() } }
    var thousandsSeparator: Bool { didSet { noteNumberFormatChange() } }
    var preset: String { didSet { noteNumberFormatChange() } }
    var customFormat: String { didSet { if category == .custom { touched.insert(.numberFormat) } } }

    var horizontalAlignment: HorizontalAlignment { didSet { touched.insert(.horizontalAlignment) } }
    var verticalAlignment: VerticalAlignment { didSet { touched.insert(.verticalAlignment) } }
    var wrapsText: Bool { didSet { touched.insert(.wrapsText) } }

    var fontName: String { didSet { touched.insert(.fontName) } }
    var fontSize: Double { didSet { touched.insert(.fontSize) } }
    var bold: Bool { didSet { touched.insert(.bold) } }
    var italic: Bool { didSet { touched.insert(.italic) } }
    var underline: UnderlineStyle { didSet { touched.insert(.underline) } }
    var strikethrough: Bool { didSet { touched.insert(.strikethrough) } }
    var textColor: NSColor { didSet { touched.insert(.textColor) } }

    var fillsBackground: Bool { didSet { touched.insert(.fill) } }
    var backgroundColor: NSColor { didSet { touched.insert(.backgroundColor); touched.insert(.fill) } }

    /// Border line per edge; `.none` with the edge touched removes it.
    var borders: [BorderEdge: BorderLineStyle] = [:]
    var borderColor: NSColor = .black

    // The Protection page (fmt_dialog_init_protection_page).
    var contentsLocked: Bool { didSet { touched.insert(.contentsLocked) } }
    var contentsHidden: Bool { didSet { touched.insert(.contentsHidden) } }
    /// The sheet's protection, applied apart from the style when changed.
    var sheetProtected: Bool { didSet { sheetProtectedChanged = true } }
    private(set) var sheetProtectedChanged = false
    func setBorder(_ style: BorderLineStyle, edge: BorderEdge) {
        borders[edge] = style
        touched.insert(.border(edge))
    }

    static let fontFamilies: [String] = {
        let generic = ["Sans", "Serif", "Monospace"]
        let installed = NSFontManager.shared.availableFontFamilies.sorted()
        return generic + installed.filter { !generic.contains($0) }
    }()

    init(format: CellFormat, isMultiCell: Bool, sheetProtected: Bool = false) {
        // Observed properties cannot be touched before every stored property
        // is set, so the mixed set is built locally first.
        var mixedKeys = Set<Key>()
        self.isMultiCell = isMultiCell
        self.sheetProtected = sheetProtected
        // The GTK shows an unchecked box for a mixed selection.
        contentsLocked = format.contentsLockedValue ?? false
        contentsHidden = format.contentsHiddenValue ?? false
        if format.contentsLocked == nil { mixedKeys.insert(.contentsLocked) }
        if format.contentsHidden == nil { mixedKeys.insert(.contentsHidden) }

        let code = format.numberFormat ?? "General"
        var cat = Category(family: CellFormat.family(ofNumberFormat: code))
        if cat != .custom, !cat.presets.isEmpty, !cat.presets.contains(code) { cat = .custom }
        category = cat
        decimals = Self.decimals(in: code)
        thousandsSeparator = code.contains(",")
        preset = cat.presets.contains(code) ? code : (cat.presets.first ?? code)
        customFormat = code
        if format.numberFormat == nil { mixedKeys.insert(.numberFormat) }

        horizontalAlignment = format.horizontalAlignmentValue ?? .general
        verticalAlignment = format.verticalAlignmentValue ?? .bottom
        wrapsText = format.wrapsTextValue ?? false
        if format.horizontalAlignment == nil { mixedKeys.insert(.horizontalAlignment) }
        if format.verticalAlignment == nil { mixedKeys.insert(.verticalAlignment) }
        if format.wrapsText == nil { mixedKeys.insert(.wrapsText) }

        fontName = format.fontName ?? "Sans"
        fontSize = format.fontSizeValue ?? 10
        bold = format.boldValue ?? false
        italic = format.italicValue ?? false
        underline = format.underlineValue ?? .none
        strikethrough = format.strikethroughValue ?? false
        textColor = format.textColor.map { NSColor(cgColor: $0) ?? .black } ?? .black
        for (key, isNil) in [(Key.fontName, format.fontName == nil), (.fontSize, format.fontSize == nil),
                             (.bold, format.bold == nil), (.italic, format.italic == nil),
                             (.underline, format.underline == nil), (.strikethrough, format.strikethrough == nil),
                             (.textColor, format.textColor == nil)] where isNil {
            mixedKeys.insert(key)
        }

        fillsBackground = format.fillsBackgroundValue ?? false
        backgroundColor = format.backgroundColor.map { NSColor(cgColor: $0) ?? .white } ?? .white
        if format.fillsBackground == nil { mixedKeys.insert(.fill) }

        var initialBorders: [BorderEdge: BorderLineStyle] = [:]
        for edge in [BorderEdge.top, .bottom, .left, .right, .insideHorizontal, .insideVertical] {
            if let style = format.borderLineStyle(edge: edge) {
                initialBorders[edge] = style
            } else {
                mixedKeys.insert(.border(edge))
            }
        }
        borders = initialBorders
        borderColor = format.borderColor(edge: .top).flatMap { NSColor(cgColor: $0) } ?? .black
        mixed = mixedKeys
        touched = []
    }

    private func noteNumberFormatChange() {
        touched.insert(.numberFormat)
    }

    private static func decimals(in code: String) -> Int {
        guard let dot = code.firstIndex(of: ".") else { return 0 }
        return code[code.index(after: dot)...].prefix { $0 == "0" }.count
    }

    /// The format code the Number tab currently describes.
    var numberFormatCode: String {
        switch category {
        case .custom: return customFormat
        case .general: return "General"
        case .date, .time, .fraction, .text: return preset
        default:
            guard let family = category.family else { return customFormat }
            return CellFormat.numberFormat(family: family, decimals: decimals, thousandsSeparator: thousandsSeparator)
        }
    }

    /// Only what the user touched, as the bridge applies it.
    func changes() -> CellFormat {
        let f = CellFormat()
        if touched.contains(.numberFormat) { f.numberFormat = numberFormatCode }
        if touched.contains(.horizontalAlignment) { f.horizontalAlignmentValue = horizontalAlignment }
        if touched.contains(.verticalAlignment) { f.verticalAlignmentValue = verticalAlignment }
        if touched.contains(.wrapsText) { f.wrapsTextValue = wrapsText }
        if touched.contains(.fontName) { f.fontName = fontName }
        if touched.contains(.fontSize) { f.fontSizeValue = max(fontSize, 1) }
        if touched.contains(.bold) { f.boldValue = bold }
        if touched.contains(.italic) { f.italicValue = italic }
        if touched.contains(.underline) { f.underlineValue = underline }
        if touched.contains(.strikethrough) { f.strikethroughValue = strikethrough }
        if touched.contains(.contentsLocked) { f.contentsLockedValue = contentsLocked }
        if touched.contains(.contentsHidden) { f.contentsHiddenValue = contentsHidden }
        if touched.contains(.textColor) { f.textColor = textColor.cgColor }
        if touched.contains(.fill) {
            f.fillsBackgroundValue = fillsBackground
            if fillsBackground { f.backgroundColor = backgroundColor.cgColor }
        }
        for (edge, style) in borders where touched.contains(.border(edge)) {
            f.setBorder(style, color: borderColor.cgColor, edge: edge)
        }
        return f
    }
}
