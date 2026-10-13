import SwiftUI
import GnmCocoa

/// The Format Cells sheet: the first SwiftUI form hosted in AppKit
/// (HANDOFF.md Phase 2b), establishing the pattern for the later dialogs.
struct FormatCellsView: View {
    @Bindable var model: FormatCellsModel
    let onDone: (Bool) -> Void

    var body: some View {
        VStack(spacing: 12) {
            TabView {
                numberTab.tabItem { Text(Localization.title("Number")) }
                alignmentTab.tabItem { Text(Localization.title("Alignment")) }
                fontTab.tabItem { Text(Localization.title("Font")) }
                borderTab.tabItem { Text(Localization.title("Border")) }
                fillTab.tabItem { Text(Localization.title("Fill")) }
                protectionTab.tabItem { Text(Localization.title("Protection")) }
            }
            .frame(minHeight: 320)
            HStack {
                Spacer()
                Button(Localization.title("Cancel")) { onDone(false) }.keyboardShortcut(.cancelAction)
                Button(Localization.title("OK")) { onDone(true) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 520)
    }

    private func mixedNote(_ key: FormatCellsModel.Key) -> some View {
        Group {
            if model.mixed.contains(key) && !model.touched.contains(key) {
                Text(Localization.title("(mixed)")).foregroundStyle(.secondary).font(.caption)
            }
        }
    }

    // MARK: Number

    private var numberTab: some View {
        Form {
            HStack {
                Picker(Localization.title("Category"), selection: $model.category) {
                    ForEach(FormatCellsModel.Category.allCases) { Text($0.rawValue).tag($0) }
                }
                mixedNote(.numberFormat)
            }
            if model.category.usesDecimals {
                Stepper("Decimal places: \(model.decimals)", value: $model.decimals, in: 0...30)
            }
            if model.category.usesThousands {
                Toggle(Localization.title("Use thousands separator"), isOn: $model.thousandsSeparator)
            }
            if !model.category.presets.isEmpty {
                Picker(Localization.title("Format"), selection: $model.preset) {
                    ForEach(model.category.presets, id: \.self) { Text($0).tag($0) }
                }
            }
            if model.category == .custom {
                TextField(Localization.title("Format code"), text: $model.customFormat)
                    .font(.system(.body, design: .monospaced))
            }
            LabeledContent("Code") {
                Text(model.numberFormatCode).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: Alignment

    private var alignmentTab: some View {
        Form {
            HStack {
                Picker(Localization.title("Horizontal"), selection: $model.horizontalAlignment) {
                    Text(Localization.title("General")).tag(HorizontalAlignment.general)
                    Text(Localization.title("Left")).tag(HorizontalAlignment.left)
                    Text(Localization.title("Center")).tag(HorizontalAlignment.center)
                    Text(Localization.title("Right")).tag(HorizontalAlignment.right)
                    Text(Localization.title("Fill")).tag(HorizontalAlignment.fill)
                    Text(Localization.title("Justify")).tag(HorizontalAlignment.justify)
                    Text(Localization.title("Center across selection")).tag(HorizontalAlignment.centerAcrossSelection)
                    Text(Localization.title("Distributed")).tag(HorizontalAlignment.distributed)
                }
                mixedNote(.horizontalAlignment)
            }
            HStack {
                Picker(Localization.title("Vertical"), selection: $model.verticalAlignment) {
                    Text(Localization.title("Top")).tag(VerticalAlignment.top)
                    Text(Localization.title("Center")).tag(VerticalAlignment.center)
                    Text(Localization.title("Bottom")).tag(VerticalAlignment.bottom)
                    Text(Localization.title("Justify")).tag(VerticalAlignment.justify)
                    Text(Localization.title("Distributed")).tag(VerticalAlignment.distributed)
                }
                mixedNote(.verticalAlignment)
            }
            HStack {
                Toggle(Localization.title("Wrap text"), isOn: $model.wrapsText)
                mixedNote(.wrapsText)
            }
        }
        .padding()
    }

    // MARK: Font

    private var fontTab: some View {
        Form {
            HStack {
                Picker(Localization.title("Family"), selection: $model.fontName) {
                    ForEach(FormatCellsModel.fontFamilies, id: \.self) { Text($0).tag($0) }
                }
                mixedNote(.fontName)
            }
            HStack {
                TextField(Localization.title("Size"), value: $model.fontSize, format: .number.precision(.fractionLength(0...1)))
                    .frame(width: 60)
                Stepper("", value: $model.fontSize, in: 1...400, step: 1).labelsHidden()
                Text(Localization.title("points")).foregroundStyle(.secondary)
                mixedNote(.fontSize)
            }
            HStack(spacing: 16) {
                Toggle(Localization.title("Bold"), isOn: $model.bold)
                Toggle(Localization.title("Italic"), isOn: $model.italic)
                Toggle(Localization.title("Strikethrough"), isOn: $model.strikethrough)
                mixedNote(.bold)
            }
            Picker(Localization.title("Underline"), selection: $model.underline) {
                Text(Localization.title("None")).tag(UnderlineStyle.none)
                Text(Localization.title("Single")).tag(UnderlineStyle.single)
                Text(Localization.title("Double")).tag(UnderlineStyle.double)
                Text(Localization.title("Single low")).tag(UnderlineStyle.singleLow)
                Text(Localization.title("Double low")).tag(UnderlineStyle.doubleLow)
            }
            HStack {
                ColorPicker("Color", selection: Binding(
                    get: { Color(nsColor: model.textColor) },
                    set: { model.textColor = NSColor($0) }), supportsOpacity: false)
                mixedNote(.textColor)
            }
        }
        .padding()
    }

    // MARK: Border

    private static let lineStyles: [(String, BorderLineStyle)] = [
        ("None", .none), ("Hair", .hair), ("Thin", .thin), ("Medium", .medium), ("Thick", .thick),
        ("Dashed", .dashed), ("Dotted", .dotted), ("Double", .double),
        ("Medium dash", .mediumDash), ("Dash dot", .dashDot), ("Dash dot dot", .dashDotDot),
    ]

    private func borderRow(_ title: String, edge: BorderEdge) -> some View {
        HStack {
            Picker(title, selection: Binding(
                get: { model.borders[edge] ?? .none },
                set: { model.setBorder($0, edge: edge) })) {
                ForEach(Self.lineStyles, id: \.1) { Text($0.0).tag($0.1) }
            }
            mixedNote(.border(edge))
        }
    }

    private var borderTab: some View {
        Form {
            borderRow("Top", edge: .top)
            borderRow("Bottom", edge: .bottom)
            borderRow("Left", edge: .left)
            borderRow("Right", edge: .right)
            if model.isMultiCell {
                borderRow("Inside horizontal", edge: .insideHorizontal)
                borderRow("Inside vertical", edge: .insideVertical)
            }
            ColorPicker("Line color", selection: Binding(
                get: { Color(nsColor: model.borderColor) },
                set: { model.borderColor = NSColor($0) }), supportsOpacity: false)
            Text(Localization.title("Changing a line style applies the line color to that edge."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: Fill

    /// The GTK Protection page: Lock, Hide, the note, Protect worksheet.
    private var protectionTab: some View {
        Form {
            HStack {
                Toggle(Localization.title("Lock"), isOn: $model.contentsLocked)
                mixedNote(.contentsLocked)
            }
            HStack {
                Toggle(Localization.title("Hide"), isOn: $model.contentsHidden)
                mixedNote(.contentsHidden)
            }
            Text(Localization.title("Locking cells or hiding formulæ only affects protected worksheets."))
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle(Localization.title("Protect worksheet"), isOn: $model.sheetProtected)
        }
        .padding()
    }

    private var fillTab: some View {
        Form {
            HStack {
                Toggle(Localization.title("Fill the cells with a solid color"), isOn: $model.fillsBackground)
                mixedNote(.fill)
            }
            ColorPicker("Color", selection: Binding(
                get: { Color(nsColor: model.backgroundColor) },
                set: { model.backgroundColor = NSColor($0) }), supportsOpacity: false)
                .disabled(!model.fillsBackground)
        }
        .padding()
    }
}
