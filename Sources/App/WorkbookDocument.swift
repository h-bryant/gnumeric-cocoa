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

    override init() {
        super.init()
        hasUndoManager = false
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
            workbook = try engine.openWorkbook(at: url)
        }
    }

    override nonisolated class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

    override func makeWindowControllers() {
        guard let workbook else { return }
        addWindowController(WorkbookWindowController(workbook: workbook, document: self))
    }

    // MARK: Saving

    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        [Self.gnumericType, Self.xmlType, Self.xlsxType]
    }

    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        switch typeName {
        case Self.gnumericType: return "gnumeric"
        case Self.xmlType: return "xml"
        case Self.xlsxType: return "xlsx"
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
            try workbook.write(to: url, saverIdentifier: Self.saverIdentifier(for: typeName), adoptingURL: false)
        }
    }

    /// The engine saver for a document type: Gnumeric's XML (compressed as
    /// the preference says), its always-uncompressed twin for `.xml`, and
    /// goffice's choice for the type's extension otherwise.
    nonisolated static func saverIdentifier(for typeName: String) -> String {
        switch typeName {
        case gnumericType: return "Gnumeric_XmlIO:sax"
        case xmlType: return "Gnumeric_XmlIO:sax:0"
        default:
            let ext = typeName == xlsxType ? "xlsx" : "gnumeric"
            return MainActor.assumeIsolated { Engine.shared?.saverIdentifier(forFileName: "x." + ext) } ?? "Gnumeric_XmlIO:sax"
        }
    }

    /// The funnel of every save (Save, Save As, the headless hook): once
    /// the file is in place, the engine learns where the document lives.
    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping ((any Error)?) -> Void) {
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            if error == nil, let self, let fileURL = self.fileURL {
                self.workbook?.adoptFileURL(fileURL)
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
