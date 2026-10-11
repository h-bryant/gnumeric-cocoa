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

    /// The engine's savers write through libgsf, which already writes to a
    /// temporary file in the target directory and renames it on success, so
    /// the document hands the final URL straight to the engine rather than
    /// letting NSDocument stage a temporary copy (which would leave the
    /// engine believing the document lives in the staging directory).
    override nonisolated func writeSafely(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) throws {
        // Saves run on the main thread (canAsynchronouslyWrite stays false).
        try MainActor.assumeIsolated {
            guard let workbook else { return }
            try workbook.write(to: url)
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
}
