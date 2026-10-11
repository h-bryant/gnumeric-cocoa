import AppKit
import GnmCocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: Engine?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        do {
            let engine = try Engine.start(configuration: EngineLocator.configuration())
            engine.messageHandler = { (error: any Error) in
                let nsError = error as NSError
                NSLog("Gnumeric: %@ %@", nsError.localizedDescription, nsError.localizedRecoverySuggestion ?? "")
                let alert = NSAlert(error: nsError)
                if let suggestion = nsError.localizedRecoverySuggestion {
                    alert.informativeText = suggestion
                }
                if let window = NSApp.keyWindow {
                    alert.beginSheetModal(for: window)
                } else if ProcessInfo.processInfo.environment["GNM_SNAPSHOT"] == nil {
                    alert.runModal()
                }
            }
            self.engine = engine
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Paths on the command line: scripts/run-app.sh launches the binary
        // directly, so no open-file Apple event arrives.
        for path in CommandLine.arguments.dropFirst() where !path.hasPrefix("-") {
            let url = URL(fileURLWithPath: path)
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error {
                    NSLog("open %@ failed: %@", path, error.localizedDescription)
                }
            }
        }
        if let path = ProcessInfo.processInfo.environment["GNM_SNAPSHOT"] {
            Snapshot.schedule(path: path, after: 1.5)
        }
    }

    /// Phase 1 is a viewer; new documents arrive with editing (Phase 2).
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        // Workbooks must be released before the engine shuts down
        // (GnmEngine.shutdown refuses otherwise).
        autoreleasepool {
            for document in NSDocumentController.shared.documents {
                document.close()
            }
        }
        engine?.shutdown()
    }
}

/// Where the engine's data lives.  Development builds run against
/// build/prefix (passed as GNM_PREFIX by scripts/run-app.sh or baked into
/// Info.plist by scripts/build-app.sh); Phase 6 moves it into the bundle.
@MainActor
enum EngineLocator {
    static var prefix: String? {
        if let env = ProcessInfo.processInfo.environment["GNM_PREFIX"], !env.isEmpty {
            return env
        }
        return Bundle.main.infoDictionary?["GnmEnginePrefix"] as? String
    }

    static func configuration() -> EngineConfiguration {
        let configuration = EngineConfiguration()
        configuration.programName = "gnumeric-cocoa"
        // GSettings persists through NSUserDefaults under the bundle
        // identifier (docs/decisions.md ADR-010); GNM_PERSIST_PREFS=0 keeps a
        // run from touching ~/Library/Preferences.
        configuration.persistsPreferences = ProcessInfo.processInfo.environment["GNM_PERSIST_PREFS"] != "0"
        if let prefix {
            configuration.settingsSchemaDirectory = prefix + "/share/glib-2.0/schemas"
        }
        return configuration
    }
}

/// Development aid: log a view's subtree with frames (GNM_DEBUG_LAYOUT).
@MainActor
private func dump(view: NSView, depth: Int) {
    let indent = String(repeating: "  ", count: depth)
    NSLog("%@%@ frame=%@ hidden=%d layer=%d", indent, String(describing: type(of: view)),
          NSStringFromRect(view.frame), view.isHidden ? 1 : 0, view.wantsLayer ? 1 : 0)
    for sub in view.subviews {
        dump(view: sub, depth: depth + 1)
    }
}

@MainActor
private func findView(of className: String, in view: NSView) -> NSView? {
    if String(describing: type(of: view)) == className { return view }
    for sub in view.subviews {
        if let found = findView(of: className, in: sub) { return found }
    }
    return nil
}

/// Development aid: write a PNG of the front window's content and quit.
/// Rendering goes through the same draw(_:) path as the screen, so this also
/// serves the golden-image tests of HANDOFF.md §5.
enum Snapshot {
    @MainActor
    static func schedule(path: String, after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            defer { NSApp.terminate(nil) }
            guard let window = NSApp.windows.first(where: { $0.isVisible }),
                  let view = window.contentView else {
                NSLog("snapshot: no visible window")
                return
            }
            if let text = ProcessInfo.processInfo.environment["GNM_SNAPSHOT_TYPE"],
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Exercise the editing path headlessly: type into C3, commit
                // with Return, undo, redo, then paste a block at E5.
                sheet.selectCell(atColumn: 2, row: 2)
                controller.gridView.beginEditing(initialText: text)
                controller.gridView.commitEditing(text: text, movement: .down)
                controller.gridView.undo(nil)
                controller.gridView.redo(nil)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("p1\tp2\np3\tp4", forType: .string)
                sheet.selectCell(atColumn: 4, row: 4)
                controller.gridView.paste(nil)
                NSLog("typed: C3=%@ E5=%@ F6=%@ modified=%d undo=%@",
                      sheet.displayTextOfCell(atColumn: 2, row: 2) ?? "nil",
                      sheet.displayTextOfCell(atColumn: 4, row: 4) ?? "nil",
                      sheet.displayTextOfCell(atColumn: 5, row: 5) ?? "nil",
                      sheet.workbook?.isModified ?? false ? 1 : 0,
                      sheet.workbook?.undoLabel ?? "nil")
                // and the NSDocument save path, next to the snapshot
                if let document = controller.document as? WorkbookDocument {
                    let saveURL = URL(fileURLWithPath: (path as NSString).deletingPathExtension + "-saved.gnumeric")
                    NSLog("document edited before save: %d", document.isDocumentEdited ? 1 : 0)
                    document.save(to: saveURL, ofType: WorkbookDocument.gnumericType, for: .saveAsOperation) { error in
                        let size = (try? FileManager.default.attributesOfItem(atPath: saveURL.path)[.size] as? Int) ?? -1
                        NSLog("saved: error=%@ size=%d edited=%d fileURL=%@", error?.localizedDescription ?? "none",
                              size, document.isDocumentEdited ? 1 : 0, document.fileURL?.lastPathComponent ?? "nil")
                    }
                }
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if let zoom = ProcessInfo.processInfo.environment["GNM_SNAPSHOT_ZOOM"].flatMap(Double.init),
               let controller = window.windowController as? WorkbookWindowController {
                controller.gridView.sheet?.zoomFactor = zoom
                controller.gridView.selectColumns(from: 1, to: 2, anchor: 1)
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_DEBUG_LAYOUT"] != nil {
                dump(view: view, depth: 0)
            }
            // The PNG at `path` is the grid view's visible area: the part the
            // engine draws, and what golden-image tests compare.  A capture
            // of the whole content view goes next to it, but on macOS 26
            // NSScrollView's backdrop views blank its interior in
            // cacheDisplay(in:to:), so treat that one as a layout check only.
            if let grid = findView(of: "GridView", in: view),
               let gridRep = grid.bitmapImageRepForCachingDisplay(in: grid.visibleRect) {
                grid.cacheDisplay(in: grid.visibleRect, to: gridRep)
                try? gridRep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                NSLog("snapshot written to %@", path)
            }
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            let windowPath = (path as NSString).deletingPathExtension + "-window.png"
            guard let png = rep.representation(using: .png, properties: [:]) else { return }
            do {
                try png.write(to: URL(fileURLWithPath: windowPath))
            } catch {
                NSLog("snapshot failed: %@", error.localizedDescription)
            }
        }
    }
}
