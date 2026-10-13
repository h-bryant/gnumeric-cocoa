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
                numberTab.tabItem { Text("Number") }
                alignmentTab.tabItem { Text("Alignment") }
                fontTab.tabItem { Text("Font") }
                borderTab.tabItem { Text("Border") }
                fillTab.tabItem { Text("Fill") }
                protectionTab.tabItem { Text("Protection") }
            }
            .frame(minHeight: 320)
            HStack {
                Spacer()
                Button("Cancel") { onDone(false) }.keyboardShortcut(.cancelAction)
                Button("OK") { onDone(true) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 520)
    }

    private func mixedNote(_ key: FormatCellsModel.Key) -> some View {
        Group {
            if model.mixed.contains(key) && !model.touched.contains(key) {
                Text("(mixed)").foregroundStyle(.secondary).font(.caption)
            }
        }
    }

    // MARK: Number

    private var numberTab: some View {
        Form {
            HStack {
                Picker("Category", selection: $model.category) {
                    ForEach(FormatCellsModel.Category.allCases) { Text($0.rawValue).tag($0) }
                }
                mixedNote(.numberFormat)
            }
            if model.category.usesDecimals {
                Stepper("Decimal places: \(model.decimals)", value: $model.decimals, in: 0...30)
            }
            if model.category.usesThousands {
                Toggle("Use thousands separator", isOn: $model.thousandsSeparator)
            }
            if !model.category.presets.isEmpty {
                Picker("Format", selection: $model.preset) {
                    ForEach(model.category.presets, id: \.self) { Text($0).tag($0) }
                }
            }
            if model.category == .custom {
                TextField("Format code", text: $model.customFormat)
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
                Picker("Horizontal", selection: $model.horizontalAlignment) {
                    Text("General").tag(HorizontalAlignment.general)
                    Text("Left").tag(HorizontalAlignment.left)
                    Text("Center").tag(HorizontalAlignment.center)
                    Text("Right").tag(HorizontalAlignment.right)
                    Text("Fill").tag(HorizontalAlignment.fill)
                    Text("Justify").tag(HorizontalAlignment.justify)
                    Text("Center across selection").tag(HorizontalAlignment.centerAcrossSelection)
                    Text("Distributed").tag(HorizontalAlignment.distributed)
                }
                mixedNote(.horizontalAlignment)
            }
            HStack {
                Picker("Vertical", selection: $model.verticalAlignment) {
                    Text("Top").tag(VerticalAlignment.top)
                    Text("Center").tag(VerticalAlignment.center)
                    Text("Bottom").tag(VerticalAlignment.bottom)
                    Text("Justify").tag(VerticalAlignment.justify)
                    Text("Distributed").tag(VerticalAlignment.distributed)
                }
                mixedNote(.verticalAlignment)
            }
            HStack {
                Toggle("Wrap text", isOn: $model.wrapsText)
                mixedNote(.wrapsText)
            }
        }
        .padding()
    }

    // MARK: Font

    private var fontTab: some View {
        Form {
            HStack {
                Picker("Family", selection: $model.fontName) {
                    ForEach(FormatCellsModel.fontFamilies, id: \.self) { Text($0).tag($0) }
                }
                mixedNote(.fontName)
            }
            HStack {
                TextField("Size", value: $model.fontSize, format: .number.precision(.fractionLength(0...1)))
                    .frame(width: 60)
                Stepper("", value: $model.fontSize, in: 1...400, step: 1).labelsHidden()
                Text("points").foregroundStyle(.secondary)
                mixedNote(.fontSize)
            }
            HStack(spacing: 16) {
                Toggle("Bold", isOn: $model.bold)
                Toggle("Italic", isOn: $model.italic)
                Toggle("Strikethrough", isOn: $model.strikethrough)
                mixedNote(.bold)
            }
            Picker("Underline", selection: $model.underline) {
                Text("None").tag(UnderlineStyle.none)
                Text("Single").tag(UnderlineStyle.single)
                Text("Double").tag(UnderlineStyle.double)
                Text("Single low").tag(UnderlineStyle.singleLow)
                Text("Double low").tag(UnderlineStyle.doubleLow)
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
            Text("Changing a line style applies the line color to that edge.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: Fill

    /// The GTK Protection page: Lock, Hide, the note, Protect worksheet.
    private var protectionTab: some View {
        Form {
            HStack {
                Toggle("Lock", isOn: $model.contentsLocked)
                mixedNote(.contentsLocked)
            }
            HStack {
                Toggle("Hide", isOn: $model.contentsHidden)
                mixedNote(.contentsHidden)
            }
            Text("Locking cells or hiding formulæ only affects protected worksheets.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle("Protect worksheet", isOn: $model.sheetProtected)
        }
        .padding()
    }

    private var fillTab: some View {
        Form {
            HStack {
                Toggle("Fill the cells with a solid color", isOn: $model.fillsBackground)
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
