import AppKit
import SwiftUI
import GnmCocoa

/// The "Export as Text" options (the GTK dialog's two pages, sheets and
/// formatting) as a model the sheet edits and turns back into options.
@MainActor
final class TextExportModel: ObservableObject {
    struct SheetChoice: Identifiable {
        let id: Int
        let sheet: Sheet
        let name: String
    }

    static let separatorPresets: [(label: String, value: String?)] = [
        ("Comma (,)", ","), ("Semicolon (;)", ";"), ("Tab", "\t"), ("Space", " "), ("Pipe (|)", "|"),
        ("Colon (:)", ":"), ("Hyphen (-)", "-"), ("Slash (/)", "/"), ("Bang (!)", "!"), ("Custom", nil),
    ]
    static let encodings: [(label: String, value: String)] = [
        ("Unicode (UTF-8)", ""), ("Unicode (UTF-16)", "UTF-16"), ("Western (ISO Latin 1)", "ISO-8859-1"),
        ("Western (ISO Latin 9)", "ISO-8859-15"), ("Western (Windows 1252)", "WINDOWS-1252"), ("Western (Mac OS Roman)", "MACINTOSH"),
    ]
    static let quoteCharacters = ["\"", "'", "`"]

    let sheets: [SheetChoice]
    @Published var selected: Set<Int>
    @Published var lineEnding: TextExportOptions.LineEnding
    @Published var separatorPreset: Int
    @Published var customSeparator: String
    @Published var quoting: TextExportOptions.Quoting
    @Published var quoteCharacter: String
    /// "" is UTF-8.
    @Published var encoding: String
    /// "" is the current locale.
    @Published var locale: String
    @Published var unknownCharacters: TextExportOptions.UnknownCharacters
    @Published var format: TextExportOptions.FormatMode
    @Published var exportsFormulas: Bool
    @Published var saveAsDefault = false

    init(options: TextExportOptions, workbook: Workbook) {
        sheets = workbook.sheets.enumerated().map { SheetChoice(id: $0.offset, sheet: $0.element, name: $0.element.name) }
        // The GTK dialog checks every sheet until a list exists.
        let listed = options.sheets
        selected = listed.isEmpty ? Set(sheets.map(\.id)) : Set(sheets.filter { choice in listed.contains { $0 === choice.sheet } }.map(\.id))
        lineEnding = options.lineEnding
        if let preset = Self.separatorPresets.firstIndex(where: { $0.value == options.separator }) {
            separatorPreset = preset
            customSeparator = ""
        } else {
            separatorPreset = Self.separatorPresets.count - 1
            customSeparator = options.separator
        }
        quoting = options.quoting
        quoteCharacter = options.quoteCharacter
        encoding = options.characterEncoding ?? ""
        locale = options.locale ?? ""
        unknownCharacters = options.unknownCharacters
        format = options.format
        exportsFormulas = options.exportsFormulas
    }

    var separator: String {
        Self.separatorPresets[max(0, min(separatorPreset, Self.separatorPresets.count - 1))].value ?? customSeparator
    }

    var isCustomSeparator: Bool { Self.separatorPresets[max(0, min(separatorPreset, Self.separatorPresets.count - 1))].value == nil }

    var canExport: Bool { !selected.isEmpty && !separator.isEmpty }

    func options() -> TextExportOptions {
        let options = TextExportOptions()
        // Every sheet in order is the saver's default; the list otherwise.
        options.sheets = selected.count == sheets.count ? [] : sheets.filter { selected.contains($0.id) }.map(\.sheet)
        options.lineEnding = lineEnding
        options.separator = separator
        options.quoting = quoting
        options.quoteCharacter = quoteCharacter.isEmpty ? "\"" : quoteCharacter
        options.characterEncoding = encoding.isEmpty ? nil : encoding
        options.locale = locale.isEmpty ? nil : locale
        options.unknownCharacters = unknownCharacters
        options.format = format
        options.exportsFormulas = exportsFormulas
        return options
    }
}

struct TextExportView: View {
    @ObservedObject var model: TextExportModel
    let onDone: (Bool) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Form {
                Section("Sheets to export, in order") {
                    ForEach(model.sheets) { choice in
                        Toggle(choice.name, isOn: Binding(
                            get: { model.selected.contains(choice.id) },
                            set: { on in if on { model.selected.insert(choice.id) } else { model.selected.remove(choice.id) } }))
                    }
                    HStack {
                        Button("Select All") { model.selected = Set(model.sheets.map(\.id)) }
                        Button("Select None") { model.selected = [] }
                    }
                }
                Section("Formatting") {
                    Picker("Line termination:", selection: $model.lineEnding) {
                        Text("Unix (linefeed)").tag(TextExportOptions.LineEnding.unix)
                        Text("Macintosh before OS X (carriage return)").tag(TextExportOptions.LineEnding.macintosh)
                        Text("Windows (carriage return + linefeed)").tag(TextExportOptions.LineEnding.windows)
                    }
                    Picker("Separator:", selection: $model.separatorPreset) {
                        ForEach(Array(TextExportModel.separatorPresets.enumerated()), id: \.offset) { index, preset in
                            Text(preset.label).tag(index)
                        }
                    }
                    if model.isCustomSeparator {
                        TextField("Custom separator:", text: $model.customSeparator)
                    }
                    Picker("Quoting:", selection: $model.quoting) {
                        Text("Automatic (quotes where needed)").tag(TextExportOptions.Quoting.automatic)
                        Text("Always").tag(TextExportOptions.Quoting.always)
                        Text("Never").tag(TextExportOptions.Quoting.never)
                    }
                    Picker("Quote character:", selection: $model.quoteCharacter) {
                        if !TextExportModel.quoteCharacters.contains(model.quoteCharacter) {
                            Text(model.quoteCharacter).tag(model.quoteCharacter)
                        }
                        ForEach(TextExportModel.quoteCharacters, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Character encoding:", selection: $model.encoding) {
                        if !TextExportModel.encodings.contains(where: { $0.value == model.encoding }) {
                            Text(model.encoding).tag(model.encoding)
                        }
                        ForEach(TextExportModel.encodings, id: \.value) { Text($0.label).tag($0.value) }
                    }
                    Picker("Locale:", selection: $model.locale) {
                        if !["", "C"].contains(model.locale) {
                            Text(model.locale).tag(model.locale)
                        }
                        Text("Current").tag("")
                        Text("C (period decimal point)").tag("C")
                    }
                    Picker("Unknown characters:", selection: $model.unknownCharacters) {
                        if TextExportOptions.canTransliterate {
                            Text("Transliterate").tag(TextExportOptions.UnknownCharacters.transliterate)
                        }
                        Text("Escape").tag(TextExportOptions.UnknownCharacters.escape)
                    }
                    Picker("Format:", selection: $model.format) {
                        Text("Automatic").tag(TextExportOptions.FormatMode.automatic)
                        Text("Raw values").tag(TextExportOptions.FormatMode.raw)
                        Text("Preserve as displayed").tag(TextExportOptions.FormatMode.preserve)
                    }
                    Toggle("Export formulas rather than values", isOn: $model.exportsFormulas)
                    Toggle("Save as default formatting", isOn: $model.saveAsDefault)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { onDone(false) }.keyboardShortcut(.cancelAction)
                Button("Export") { onDone(true) }.keyboardShortcut(.defaultAction).disabled(!model.canExport)
            }
            .padding([.horizontal, .bottom], 16)
        }
        .frame(width: 520, height: 560)
    }
}

/// The options as a sheet on the document window, before a Save As to
/// "Text (configurable)".
@MainActor
final class TextExportSheet {
    let window: NSWindow
    let model: TextExportModel
    private var completion: ((TextExportOptions?, Bool) -> Void)?
    private weak var parent: NSWindow?

    init(options: TextExportOptions, workbook: Workbook) {
        model = TextExportModel(options: options, workbook: workbook)
        let hosting = NSHostingController(rootView: TextExportView(model: model) { _ in })
        window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled]
        window.title = "Export as Text"
        window.isReleasedWhenClosed = false
        hosting.rootView = TextExportView(model: model) { [weak self] accepted in self?.finish(accepted) }
    }

    func run(in parent: NSWindow, completion: @escaping (TextExportOptions?, Bool) -> Void) {
        self.parent = parent
        self.completion = completion
        parent.beginSheet(window) { _ in }
    }

    /// Export or Cancel: the options (or nil) and whether to remember them.
    func finish(_ accepted: Bool) {
        guard let completion else { return }
        self.completion = nil
        parent?.endSheet(window)
        window.close()
        completion(accepted ? model.options() : nil, accepted && model.saveAsDefault)
    }
}
