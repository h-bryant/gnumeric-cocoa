import AppKit
import SwiftUI
import GnmCocoa

/// The text import assistant's model: the session's options as published
/// values, each change pushed to the session and the preview parsed
/// again (the GTK assistant's pages over `StfDialogData`).
@MainActor
final class TextImportModel: ObservableObject {
    struct PreviewRow: Identifiable {
        let id: Int
        let cells: [String]
    }
    struct PreviewColumn: Identifiable {
        let id: Int
        var title: String { "Column \(id + 1)" }
    }
    struct ColumnChoice: Identifiable {
        let id: Int
        let guessed: String
    }

    static let encodings: [(label: String, value: String)] = [
        ("Unicode (UTF-8)", "UTF-8"), ("ASCII", "ASCII"), ("Unicode (UTF-16)", "UTF-16"), ("Western (ISO Latin 1)", "ISO-8859-1"),
        ("Western (ISO Latin 9)", "ISO-8859-15"), ("Western (Windows 1252)", "WINDOWS-1252"), ("Western (Mac OS Roman)", "MACINTOSH"),
    ]
    static let separatorChoices: [(label: String, character: String)] = [
        ("Tab", "\t"), ("Colon (:)", ":"), ("Comma (,)", ","), ("Space", " "), ("Semicolon (;)", ";"), ("Hyphen (-)", "-"),
    ]
    static let previewLineLimit = 60
    static let previewColumnLimit = 40

    private(set) var session: TextImportSession
    let name: String
    @Published var page = 0
    @Published var encoding: String
    @Published var kind: TextImportSession.Kind { didSet { if !loading { session.kind = kind; refresh() } } }
    @Published var lineBreaks: TextImportSession.LineBreaks { didSet { if !loading { session.lineBreaks = lineBreaks; refresh() } } }
    @Published var startLine: Int { didSet { if !loading { session.startLine = startLine; reload(range: true) } } }
    @Published var stopLine: Int { didSet { if !loading { session.stopLine = stopLine; reload(range: true) } } }
    @Published var separators: Set<String> { didSet { if !loading { pushSeparators() } } }
    @Published var customSeparator: String { didSet { if !loading { pushSeparators() } } }
    @Published var mergesAdjacentSeparators: Bool { didSet { if !loading { session.mergesAdjacentSeparators = mergesAdjacentSeparators; refresh() } } }
    @Published var ignoresLeadingSeparators: Bool { didSet { if !loading { session.ignoresLeadingSeparators = ignoresLeadingSeparators; refresh() } } }
    @Published var quoteCharacter: String { didSet { if !loading { session.quoteCharacter = quoteCharacter; refresh() } } }
    @Published var doubledQuoteIsLiteral: Bool { didSet { if !loading { session.doubledQuoteIsLiteral = doubledQuoteIsLiteral; refresh() } } }
    @Published var splitPositionsText: String { didSet { if !loading { pushSplitPositions() } } }
    @Published var trimming: TextImportSession.Trimming { didSet { if !loading { session.trimming = trimming } } }
    @Published var locale: String { didSet { if !loading { session.locale = locale.isEmpty ? nil : locale } } }
    /// The chosen format per column, in the engine's syntax.
    @Published var columnFormats: [String] { didSet { if !loading { session.columnFormats = columnFormats } } }
    @Published var importedColumns: [Bool] { didSet { if !loading { session.importedColumns = importedColumns.map { NSNumber(value: $0) } } } }
    @Published private(set) var preview: [PreviewRow] = []
    @Published private(set) var previewColumns: [PreviewColumn] = []
    @Published private(set) var columnChoices: [ColumnChoice] = []
    @Published private(set) var lineCount = 0
    private var loading = true

    init(session: TextImportSession) {
        self.session = session
        name = session.name
        encoding = session.encoding
        kind = session.kind
        lineBreaks = session.lineBreaks
        startLine = session.startLine
        stopLine = session.stopLine
        let characters = session.separatorCharacters.map { String($0) }
        separators = Set(characters)
        customSeparator = session.customSeparators.first ?? ""
        mergesAdjacentSeparators = session.mergesAdjacentSeparators
        ignoresLeadingSeparators = session.ignoresLeadingSeparators
        quoteCharacter = session.quoteCharacter
        doubledQuoteIsLiteral = session.doubledQuoteIsLiteral
        splitPositionsText = session.splitPositions.map { String($0.intValue) }.joined(separator: ", ")
        trimming = session.trimming
        locale = session.locale ?? ""
        columnFormats = session.columnFormats
        importedColumns = []
        loading = false
        refresh()
    }

    /// The file read again in another encoding: a fresh session, the
    /// options guessed again (the GTK main page's charmap change).
    func reread(encoding newEncoding: String) {
        guard let url = session.url, let fresh = try? TextImportSession(contentsOf: url, encoding: newEncoding) else { return }
        loading = true
        session = fresh
        encoding = fresh.encoding
        kind = fresh.kind
        lineBreaks = fresh.lineBreaks
        startLine = fresh.startLine
        stopLine = fresh.stopLine
        separators = Set(fresh.separatorCharacters.map { String($0) })
        customSeparator = fresh.customSeparators.first ?? ""
        quoteCharacter = fresh.quoteCharacter
        columnFormats = fresh.columnFormats
        importedColumns = []
        loading = false
        refresh()
    }

    private func pushSeparators() {
        session.separatorCharacters = Self.separatorChoices.map(\.character).filter { separators.contains($0) }.joined()
        session.customSeparators = customSeparator.isEmpty ? [] : [customSeparator]
        refresh()
    }

    private func pushSplitPositions() {
        let positions = splitPositionsText.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Int($0) }
        session.splitPositions = positions.map { NSNumber(value: $0) }
        refresh()
    }

    func discoverSplitPositions() {
        session.discoverSplitPositions()
        loading = true
        splitPositionsText = session.splitPositions.map { String($0.intValue) }.joined(separator: ", ")
        loading = false
        refresh()
    }

    /// The columns changed: formats guessed again, every column imported.
    private func refresh() {
        session.guessColumnFormats()
        loading = true
        columnFormats = session.columnFormats
        importedColumns = Array(repeating: true, count: columnFormats.count)
        session.importedColumns = []
        loading = false
        reload(range: true)
    }

    /// The range or the options changed: the preview and the counts.
    private func reload(range: Bool) {
        lineCount = session.lineCount
        if range {
            loading = true
            startLine = session.startLine
            stopLine = session.stopLine
            loading = false
        }
        let lines = session.previewLines(Self.previewLineLimit)
        let width = min(lines.map(\.count).max() ?? 0, Self.previewColumnLimit)
        preview = lines.enumerated().map { PreviewRow(id: $0.offset, cells: Array($0.element.prefix(width))) }
        previewColumns = (0..<width).map { PreviewColumn(id: $0) }
        let guessed = session.columnFormats
        columnChoices = (0..<max(columnFormats.count, width)).map { ColumnChoice(id: $0, guessed: $0 < guessed.count ? guessed[$0] : "General") }
        if columnFormats.count < columnChoices.count {
            loading = true
            columnFormats += Array(repeating: "General", count: columnChoices.count - columnFormats.count)
            importedColumns += Array(repeating: true, count: columnChoices.count - importedColumns.count)
            loading = false
        }
    }

    var importedColumnCount: Int { importedColumns.filter { $0 }.count }
    var lastPage: Int { 2 }
}

/// The assistant's pages: the main page (encoding, line breaks, kind,
/// the lines), the separators or fixed-width page, and the format page,
/// each over the same preview.
struct TextImportView: View {
    @ObservedObject var model: TextImportModel
    let onDone: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Import “\(model.name)”").font(.headline)
            Group {
                switch model.page {
                case 0: mainPage
                case 1: model.kind == .fixedWidth ? AnyView(fixedPage) : AnyView(separatorsPage)
                default: formatPage
                }
            }
            .frame(height: 230)
            previewTable
            HStack {
                Text(model.page == 0 ? "\(model.stopLine - model.startLine + 1) of \(model.lineCount) lines to import"
                                     : "\(model.importedColumnCount) of \(model.columnChoices.count) columns to import")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { onDone(false) }.keyboardShortcut(.cancelAction)
                Button("Back") { model.page -= 1 }.disabled(model.page == 0)
                if model.page < model.lastPage {
                    Button("Next") { model.page += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Finish") { onDone(true) }.keyboardShortcut(.defaultAction).disabled(model.importedColumnCount == 0)
                }
            }
        }
        .padding(16)
        .frame(width: 760, height: 600)
    }

    private var mainPage: some View {
        Form {
            Picker("Encoding:", selection: Binding(get: { model.encoding }, set: { model.reread(encoding: $0) })) {
                if !TextImportModel.encodings.contains(where: { $0.value == model.encoding }) {
                    Text(model.encoding).tag(model.encoding)
                }
                ForEach(TextImportModel.encodings, id: \.value) { Text($0.label).tag($0.value) }
            }
            .disabled(model.session.url == nil)
            HStack {
                Text("Line breaks:")
                toggle("Unix (linefeed)", .unix)
                toggle("Windows (carriage return + linefeed)", .windows)
                toggle("Macintosh (carriage return)", .macintosh)
            }
            Picker("Original data type:", selection: $model.kind) {
                Text("Separated").tag(TextImportSession.Kind.separated)
                Text("Fixed width").tag(TextImportSession.Kind.fixedWidth)
            }
            .pickerStyle(.radioGroup)
            HStack {
                Text("Lines:")
                Text("from")
                TextField("", value: $model.startLine, format: .number).frame(width: 70)
                Stepper("", value: $model.startLine, in: 1...max(model.lineCount, 1)).labelsHidden()
                Text("to")
                TextField("", value: $model.stopLine, format: .number).frame(width: 70)
                Stepper("", value: $model.stopLine, in: 1...max(model.lineCount, 1)).labelsHidden()
            }
        }
        .formStyle(.grouped)
    }

    private func toggle(_ title: String, _ flag: TextImportSession.LineBreaks) -> some View {
        Toggle(title, isOn: Binding(
            get: { model.lineBreaks.contains(flag) },
            set: { on in if on { model.lineBreaks.insert(flag) } else { model.lineBreaks.remove(flag) } }))
    }

    private var separatorsPage: some View {
        Form {
            Section("Separators") {
                HStack {
                    ForEach(TextImportModel.separatorChoices, id: \.character) { choice in
                        Toggle(choice.label, isOn: Binding(
                            get: { model.separators.contains(choice.character) },
                            set: { on in if on { model.separators.insert(choice.character) } else { model.separators.remove(choice.character) } }))
                    }
                }
                TextField("Custom:", text: $model.customSeparator)
                Toggle("See two separators as one", isOn: $model.mergesAdjacentSeparators)
                Toggle("Ignore separators at the start of a line", isOn: $model.ignoresLeadingSeparators)
            }
            Section("Text indicator") {
                Picker("Quote character:", selection: $model.quoteCharacter) {
                    if !["\"", "'", "`", ""].contains(model.quoteCharacter) {
                        Text(model.quoteCharacter).tag(model.quoteCharacter)
                    }
                    Text("\"").tag("\"")
                    Text("'").tag("'")
                    Text("`").tag("`")
                    Text("None").tag("")
                }
                Toggle("Two quotes inside a field are one quote", isOn: $model.doubledQuoteIsLiteral)
            }
        }
        .formStyle(.grouped)
    }

    private var fixedPage: some View {
        Form {
            Section("Column breaks") {
                TextField("Split after characters:", text: $model.splitPositionsText)
                Text("Character positions, comma-separated, counted from the start of the line.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Auto") { model.discoverSplitPositions() }
                    Button("Clear") { model.splitPositionsText = "" }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var formatPage: some View {
        Form {
            Picker("Trim spaces:", selection: $model.trimming) {
                Text("Neither side").tag(TextImportSession.Trimming.none)
                Text("Both sides").tag(TextImportSession.Trimming.both)
                Text("On the left").tag(TextImportSession.Trimming.left)
                Text("On the right").tag(TextImportSession.Trimming.right)
            }
            Picker("Locale for numbers and dates:", selection: $model.locale) {
                if !["", "C"].contains(model.locale) {
                    Text(model.locale).tag(model.locale)
                }
                Text("Current").tag("")
                Text("C (period decimal point)").tag("C")
            }
            Section("Columns") {
                ForEach(model.columnChoices) { column in
                    HStack {
                        Toggle("Column \(column.id + 1)", isOn: Binding(
                            get: { column.id < model.importedColumns.count ? model.importedColumns[column.id] : true },
                            set: { on in if column.id < model.importedColumns.count { model.importedColumns[column.id] = on } }))
                            .frame(width: 120, alignment: .leading)
                        Picker("", selection: Binding(
                            get: { column.id < model.columnFormats.count ? model.columnFormats[column.id] : "General" },
                            set: { format in if column.id < model.columnFormats.count { model.columnFormats[column.id] = format } })) {
                            Text("Guessed (\(column.guessed))").tag(column.guessed)
                            ForEach(Self.formatChoices.filter { $0.1 != column.guessed }, id: \.1) { Text($0.0).tag($0.1) }
                        }
                        .labelsHidden()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private static let formatChoices: [(String, String)] = [
        ("General", "General"), ("Text", "@"), ("Number", "0.00"), ("Percent", "0.00%"), ("Date", "yyyy-mm-dd"),
    ]

    private var previewTable: some View {
        Table(model.preview) {
            TableColumnForEach(model.previewColumns) { column in
                TableColumn(column.title) { row in
                    Text(column.id < row.cells.count ? row.cells[column.id] : "")
                        .font(.system(size: NSFont.smallSystemFontSize, design: .monospaced))
                        .lineLimit(1)
                }
                .width(min: 60, ideal: 110)
            }
        }
        .frame(minHeight: 160)
    }
}

/// The assistant as a modal window: the GTK dialog runs inside the
/// engine's opener, and NSDocument reads synchronously, so the choices
/// are made before the document exists.
@MainActor
final class TextImportAssistant {
    /// Headless runs: drive the window instead of the modal loop; the
    /// result stands for Finish (true) or Cancel.
    nonisolated(unsafe) static var headlessDriver: (@MainActor (TextImportAssistant) -> Bool)?

    let window: NSWindow
    let model: TextImportModel
    private var accepted = false

    init(session: TextImportSession, title: String = "Import Text") {
        model = TextImportModel(session: session)
        let hosting = NSHostingController(rootView: TextImportView(model: model) { _ in })
        window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled]
        window.isReleasedWhenClosed = false
        hosting.rootView = TextImportView(model: model) { [weak self] accepted in self?.finish(accepted) }
        hosting.view.layoutSubtreeIfNeeded()
        let fitting = hosting.view.fittingSize
        window.setContentSize(fitting.width > 10 && fitting.height > 10 ? fitting : NSSize(width: 760, height: 600))
        window.center()
    }

    /// Run until Finish or Cancel; true when the import should go ahead
    /// with the model's session.
    func run() -> Bool {
        if let driver = Self.headlessDriver {
            return driver(self)
        }
        NSApp.runModal(for: window)
        window.close()
        return accepted
    }

    private func finish(_ accepted: Bool) {
        self.accepted = accepted
        NSApp.stopModal()
    }
}
