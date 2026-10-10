import AppKit
import GnmCocoa

/// One open file.  Reading goes through the engine's file openers, so every
/// format Gnumeric can load works (HANDOFF.md §4, Phase 1).
@MainActor
final class WorkbookDocument: NSDocument {
    private(set) var workbook: Workbook?

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
        addWindowController(WorkbookWindowController(workbook: workbook))
    }

    /// Phase 1 is read-only: no writable types, so Save and Save As stay
    /// disabled and closing never asks about unsaved changes.
    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] { [] }

    override func close() {
        super.close()
        workbook = nil
    }
}
