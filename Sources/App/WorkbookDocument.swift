import AppKit
import GnmCocoa

/// One open file.  Reading and writing go through the engine's file openers
/// and savers, so every format Gnumeric handles works; the engine's command
/// stack is the undo source of truth, so the document keeps no undo manager
/// and mirrors the engine's dirty flag into its change count.
@MainActor
final class WorkbookDocument: NSDocument {
    private(set) var workbook: Workbook?

    nonisolated static let gnumericType = "org.gnome.gnumeric.spreadsheet"
    nonisolated static let xlsxType = "org.openxmlformats.spreadsheetml.sheet"
    /// Gnumeric's uncompressed XML (the engine's `Gnumeric_XmlIO:sax:0`
    /// saver, chosen by the `.xml` extension): diffable, Henry's preferred
    /// form for version control.
    nonisolated static let xmlType = "io.github.h-bryant.gnumeric-cocoa.gnumeric-xml"
    /// Delimited text: opened through the engine's text importer with its
    /// guessed options, saved as CSV of the current sheet
    /// (`Gnumeric_stf:stf_csv`), the diffable form of a plain table.
    nonisolated static let csvType = "public.comma-separated-values-text"
    /// "Text (configurable)": the engine's text saver with the options
    /// sheet before it (`Gnumeric_stf:stf_assistant`).
    nonisolated static let textType = "public.plain-text"
    /// The options the next text write uses, chosen in the sheet.
    private var pendingTextExport: (options: TextExportOptions, remember: Bool)?

    override init() {
        super.init()
        hasUndoManager = false
    }

    /// File → New: an empty workbook with the preferred number of sheets
    /// (Settings → General), the engine's defaults otherwise.
    convenience init(type typeName: String) throws {
        self.init()
        guard let engine = Engine.shared else {
            throw NSError(domain: GnmErrorDomain, code: GnmError.Code.engineNotRunning.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "The Gnumeric engine is not running."])
        }
        workbook = engine.makeWorkbook(sheetCount: UInt(max(1, engine.preferences.newWorkbookSheetCount)))
        fileType = typeName
    }

    override class var autosavesInPlace: Bool { false }

    /// NSDocument declares reading nonisolated (it may read concurrently when
    /// asked to); this document never asks, so the read happens on the main
    /// thread and the engine call is safe.
    override nonisolated func read(from url: URL, ofType typeName: String) throws {
        try MainActor.assumeIsolated {
            guard let engine = Engine.shared else {
                throw NSError(domain: GnmErrorDomain, code: GnmError.Code.engineNotRunning.rawValue,
                              userInfo: [NSLocalizedDescriptionKey: "The Gnumeric engine is not running."])
            }
            if typeName == Self.textType {
                // Plain text goes through the import assistant (the GTK
                // opener's dialog), modal because the read is synchronous;
                // delimited text takes the engine's guessed options.
                let session = try TextImportSession(contentsOf: url, encoding: nil)
                let assistant = TextImportAssistant(session: session)
                guard assistant.run() else {
                    throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
                }
                workbook = try engine.importText(assistant.model.session)
            } else {
                workbook = try engine.openWorkbook(at: url)
            }
        }
    }

    override nonisolated class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

    override func makeWindowControllers() {
        guard let workbook else { return }
        addWindowController(WorkbookWindowController(workbook: workbook, document: self))
    }

    // MARK: Saving

    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        [Self.gnumericType, Self.xmlType, Self.xlsxType, Self.csvType, Self.textType]
    }

    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        switch typeName {
        case Self.gnumericType: return "gnumeric"
        case Self.xmlType: return "xml"
        case Self.xlsxType: return "xlsx"
        case Self.csvType: return "csv"
        case Self.textType: return "txt"
        default: return super.fileNameExtension(forType: typeName, saveOperation: saveOperation)
        }
    }

    /// NSDocument stages the file and moves it into place itself, with its
    /// file coordination (an earlier `writeSafely` override handed the
    /// final URL straight to the engine, because libgsf also writes
    /// atomically; the staged path is the one AppKit expects, 2026-10-12).
    /// The staged name is not the final one (`name.gnumeric.sb-…` for a
    /// save in place), so the saver comes from the document type, not the
    /// file name, and the engine writes without adopting the URL;
    /// `save(to:...)` adopts it when the save completes.
    override nonisolated func write(to url: URL, ofType typeName: String) throws {
        // Saves run on the main thread (canAsynchronouslyWrite stays false).
        try MainActor.assumeIsolated {
            guard let workbook else { return }
            if typeName == Self.textType, let pending = pendingTextExport {
                try workbook.write(to: url, textExportOptions: pending.options, rememberAsDefault: pending.remember, adoptingURL: false)
            } else {
                try workbook.write(to: url, saverIdentifier: Self.saverIdentifier(for: typeName), adoptingURL: false)
            }
        }
    }

    /// The engine saver for a document type: Gnumeric's XML (compressed as
    /// the preference says), its always-uncompressed twin for `.xml`, and
    /// goffice's choice for the type's extension otherwise.
    nonisolated static func saverIdentifier(for typeName: String) -> String {
        switch typeName {
        case gnumericType: return "Gnumeric_XmlIO:sax"
        case xmlType: return "Gnumeric_XmlIO:sax:0"
        case csvType: return "Gnumeric_stf:stf_csv"
        case textType: return "Gnumeric_stf:stf_assistant"
        default:
            let ext = typeName == xlsxType ? "xlsx" : "gnumeric"
            return MainActor.assumeIsolated { Engine.shared?.saverIdentifier(forFileName: "x." + ext) } ?? "Gnumeric_XmlIO:sax"
        }
    }

    /// The funnel of every save (Save, Save As, the headless hook): once
    /// the file is in place, the engine learns where the document lives.
    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping ((any Error)?) -> Void) {
        // A text save asks for its options first (the GTK saver's dialog),
        // then comes back through here with them pending.
        if typeName == Self.textType, pendingTextExport == nil {
            guard let workbook, let controller = windowControllers.first as? WorkbookWindowController else {
                completionHandler(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
                return
            }
            controller.promptTextExport(options: workbook.textExportOptions) { [weak self] options, remember in
                guard let self else { return }
                guard let options else {
                    completionHandler(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
                    return
                }
                pendingTextExport = (options, remember)
                save(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
            }
            return
        }
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            if let self {
                pendingTextExport = nil
                if error == nil, let fileURL = self.fileURL {
                    workbook?.adoptFileURL(fileURL)
                }
            }
            completionHandler(error)
        }
    }

    /// The engine's dirty flag drives the change count.
    func modifiedStateDidChange() {
        guard let workbook else { return }
        updateChangeCount(workbook.isModified ? .changeDone : .changeCleared)
    }

    override func close() {
        super.close()
        workbook = nil
    }

    /// Saving and reading errors go to the log with their causes before the
    /// alert shows them; the alert's text alone said "could not be saved".
    override func willPresentError(_ error: any Error) -> any Error {
        let nsError = error as NSError
        NSLog("Document error: %@ (%@ %ld) underlying=%@ info=%@", nsError.localizedDescription, nsError.domain, nsError.code,
              (nsError.userInfo[NSUnderlyingErrorKey] as? NSError).map { "\($0.domain) \($0.code) \($0.localizedDescription)" } ?? "none",
              nsError.userInfo.keys.sorted().joined(separator: ","))
        return super.willPresentError(error)
    }
}
