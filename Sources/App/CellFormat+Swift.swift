import Foundation
import GnmCocoa

/// Typed views of the bridge's NSNumber-based optional properties.
extension CellFormat {
    var horizontalAlignmentValue: HorizontalAlignment? {
        get { horizontalAlignment.flatMap { HorizontalAlignment(rawValue: $0.intValue) } }
        set { horizontalAlignment = newValue.map { NSNumber(value: $0.rawValue) } }
    }
    var verticalAlignmentValue: VerticalAlignment? {
        get { verticalAlignment.flatMap { VerticalAlignment(rawValue: $0.intValue) } }
        set { verticalAlignment = newValue.map { NSNumber(value: $0.rawValue) } }
    }
    var underlineValue: UnderlineStyle? {
        get { underline.flatMap { UnderlineStyle(rawValue: $0.intValue) } }
        set { underline = newValue.map { NSNumber(value: $0.rawValue) } }
    }
    var wrapsTextValue: Bool? {
        get { wrapsText?.boolValue }
        set { wrapsText = newValue.map { NSNumber(value: $0) } }
    }
    var boldValue: Bool? {
        get { bold?.boolValue }
        set { bold = newValue.map { NSNumber(value: $0) } }
    }
    var italicValue: Bool? {
        get { italic?.boolValue }
        set { italic = newValue.map { NSNumber(value: $0) } }
    }
    var strikethroughValue: Bool? {
        get { strikethrough?.boolValue }
        set { strikethrough = newValue.map { NSNumber(value: $0) } }
    }
    var fontSizeValue: Double? {
        get { fontSize?.doubleValue }
        set { fontSize = newValue.map { NSNumber(value: $0) } }
    }
    var fillsBackgroundValue: Bool? {
        get { fillsBackground?.boolValue }
        set { fillsBackground = newValue.map { NSNumber(value: $0) } }
    }
    func borderLineStyle(edge: BorderEdge) -> BorderLineStyle? {
        borderStyle(edge: edge).flatMap { BorderLineStyle(rawValue: $0.intValue) }
    }
}
