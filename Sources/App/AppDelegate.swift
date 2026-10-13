import AppKit
import SwiftUI
import GnmCocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: Engine?
    private(set) var settings: PreferencesWindowController?

    /// File → Import Text… (⇧⌘O): any text file through the import
    /// assistant, whatever its extension (Open… takes `.csv` and `.tsv`
    /// with the engine's guessed options).
    @objc func importText(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Import Text"
        panel.allowedContentTypes = [.plainText, .commaSeparatedText, .tabSeparatedText, .delimitedText, .text, .data]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Self.importText(at: url)
        }
    }

    /// Open `url` as the plain-text document type: the assistant, then a
    /// new document window.
    static func importText(at url: URL) {
        let controller = NSDocumentController.shared
        do {
            let document = try controller.makeDocument(withContentsOf: url, ofType: WorkbookDocument.textType)
            controller.addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
            controller.noteNewRecentDocumentURL(url)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError { return }
            NSLog("import %@ failed: %@", url.path, error.localizedDescription)
            NSApp.presentError(error)
        }
    }

    /// Gnumeric → Settings… (⌘,): the engine's preferences the app honors.
    @objc func showSettings(_ sender: Any?) {
        guard let engine else { return }
        if settings == nil {
            settings = PreferencesWindowController(preferences: engine.preferences)
        }
        settings?.show()
    }

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

    /// An untitled workbook at launch when no file was named (File → New
    /// otherwise), as any document app.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        !CommandLine.arguments.dropFirst().contains { !$0.hasPrefix("-") }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Workbooks must be released before the engine shuts down
        // (GnmEngine.shutdown refuses otherwise).
        autoreleasepool {
            for document in NSDocumentController.shared.documents {
                document.close()
            }
        }
        if ProcessInfo.processInfo.environment["GNM_SNAPSHOT"] != nil {
            NSLog("terminate: documents=%ld windows=%@", NSDocumentController.shared.documents.count,
                  NSApp.windows.map { "\(type(of: $0)) visible=\($0.isVisible) sheet=\($0.attachedSheet != nil)" }.joined(separator: ", "))
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
        // The compression level of `.gnumeric` files is a preference
        // (Settings → General; Henry's choice of 0, plain XML, is in the
        // app's defaults since 2026-10-12), so nothing is set here.
        return configuration
    }
}

/// The texts of a view tree (what an alert sheet says, in logs).
@MainActor
private func textFields(in view: NSView) -> [String] {
    var texts: [String] = []
    if let field = view as? NSTextField, !field.stringValue.isEmpty {
        texts.append(field.stringValue)
    }
    if let button = view as? NSButton, !button.title.isEmpty {
        texts.append("[\(button.title)]")
    }
    for sub in view.subviews {
        texts += textFields(in: sub)
    }
    return texts
}

/// Development aid: log a view's subtree with frames and layer state
/// (GNM_DEBUG_LAYOUT).  `contents=1` means the layer holds drawn pixels.
@MainActor
private func dump(view: NSView, depth: Int) {
    let indent = String(repeating: "  ", count: depth)
    let layer = view.layer.map {
        String(format: "layer(opacity=%.2f masks=%d contents=%d)", $0.opacity, $0.masksToBounds ? 1 : 0,
               $0.contents != nil ? 1 : 0)
    } ?? "nolayer"
    NSLog("%@%@ frame=%@ hidden=%d alpha=%.2f opaque=%d %@", indent, String(describing: type(of: view)),
          NSStringFromRect(view.frame), view.isHidden ? 1 : 0, view.alphaValue, view.isOpaque ? 1 : 0, layer)
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
            // Terminate from a later turn, with every document marked clean:
            // the review of unsaved documents would otherwise block headless
            // (or leave its alert holding the document past the engine's
            // shutdown), and this closure's own window reference must be
            // gone before applicationWillTerminate releases the workbooks.
            defer {
                for document in NSDocumentController.shared.documents {
                    document.updateChangeCount(.changeCleared)
                }
                DispatchQueue.main.async { NSApp.terminate(nil) }
                // After a save through NSDocument (the typing hook), AppKit
                // swallows the terminate on most runs, and every later one
                // too (2026-10-12, docs/progress.md): fall back to the
                // delegate's own shutdown and a plain exit, said out loud.
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    for window in NSApp.windows {
                        if let sheet = window.attachedSheet, let content = sheet.contentView {
                            NSLog("snapshot: sheet on '%@' says: %@", window.title, textFields(in: content).joined(separator: " | "))
                        }
                    }
                    NSLog("snapshot: terminate was swallowed; shutting the engine down and exiting (modal=%@ documents=%@ windows=%@)",
                          NSApp.modalWindow.map { String(describing: type(of: $0)) } ?? "none",
                          NSDocumentController.shared.documents.map { "\($0.fileURL?.lastPathComponent ?? "untitled") edited=\($0.isDocumentEdited) type=\($0.fileType ?? "nil")" }.joined(separator: "; "),
                          NSApp.windows.map { "\(type(of: $0)) '\($0.title)' visible=\($0.isVisible) sheet=\($0.attachedSheet.map { String(describing: type(of: $0)) } ?? "none")" }.joined(separator: "; "))
                    (NSApp.delegate as? AppDelegate)?.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
                    exit(0)
                }
            }
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
                sheet.selectCell(atColumn: 0, row: 2)
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
                if let document = controller.document as? WorkbookDocument,
                   ProcessInfo.processInfo.environment["GNM_SNAPSHOT_SAVE_INPLACE"] != nil {
                    // File → Save on the opened file itself (give the hook a
                    // copy), the user's ⌘S.
                    NSLog("document edited before save in place: %d type=%@", document.isDocumentEdited ? 1 : 0, document.fileType ?? "nil")
                    document.save(nil)   // asynchronous: the file is written a turn later
                    NSLog("save in place requested: fileURL=%@", document.fileURL?.lastPathComponent ?? "nil")
                } else if let document = controller.document as? WorkbookDocument {
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
            // Each hook runs in its own pool: references the bridge
            // autoreleases must be gone before terminate shuts the engine down.
            autoreleasepool {
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_PHASE3"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // The Phase 3 menu commands, driven through the grid view's
                // actions: insert and delete rows, fill, autofill, hide,
                // autofit, merge, with the undo stack checked along the way.
                let grid = controller.gridView
                sheet.selectRange(CellRange(start: CellCoordinate(column: 0, row: 4), end: CellCoordinate(column: 0, row: 5)),
                                  editPosition: CellCoordinate(column: 0, row: 4))
                grid.insertRows(nil)
                NSLog("phase3: after insert rows A7=%@ undo=%@", sheet.displayTextOfCell(atColumn: 0, row: 6) ?? "nil",
                      sheet.workbook?.undoLabel ?? "nil")
                grid.deleteRows(nil)
                NSLog("phase3: after delete rows A5=%@ undo=%@", sheet.displayTextOfCell(atColumn: 0, row: 4) ?? "nil",
                      sheet.workbook?.undoLabel ?? "nil")
                sheet.selectRange(CellRange(start: CellCoordinate(column: 4, row: 4), end: CellCoordinate(column: 4, row: 8)),
                                  editPosition: CellCoordinate(column: 4, row: 4))
                try? sheet.setText("fill", atColumn: 4, row: 4, autocorrect: false)
                grid.fillDown(nil)
                NSLog("phase3: fill down E9=%@", sheet.displayTextOfCell(atColumn: 4, row: 8) ?? "nil")
                try? sheet.setText("10", atColumn: 6, row: 4, autocorrect: false)
                try? sheet.setText("20", atColumn: 6, row: 5, autocorrect: false)
                let source = CellRange(start: CellCoordinate(column: 6, row: 4), end: CellCoordinate(column: 6, row: 5))
                let target = GridView.fillTarget(from: source, toward: CellCoordinate(column: 6, row: 9))
                try? sheet.autofill(from: source, to: target, defaultIncrement: false)
                NSLog("phase3: autofill target rows %ld-%ld G10=%@", target.start.row, target.end.row,
                      sheet.displayTextOfCell(atColumn: 6, row: 9) ?? "nil")
                sheet.selectRange(CellRange(start: CellCoordinate(column: 8, row: 4), end: CellCoordinate(column: 9, row: 5)),
                                  editPosition: CellCoordinate(column: 8, row: 4))
                grid.mergeAndCenter(nil)
                NSLog("phase3: merged=%d undo=%@", sheet.selectionHasMergedCells ? 1 : 0, sheet.workbook?.undoLabel ?? "nil")
                grid.selectColumn(nil)
                grid.hideColumns(nil)
                NSLog("phase3: column I visible=%d", sheet.isColumnVisible(8) ? 1 : 0)
                grid.unhideColumns(nil)
                sheet.selectCell(atColumn: 0, row: 6)
                grid.selectColumn(nil)
                grid.autofitColumns(nil)
                NSLog("phase3: column A width %g undo=%@", sheet.width(ofColumn: 0), sheet.workbook?.undoLabel ?? "nil")
                // Paste Special (values, transposed) of the series into K5, then sort it descending.
                sheet.selectRange(CellRange(start: CellCoordinate(column: 6, row: 4), end: CellCoordinate(column: 6, row: 9)),
                                  editPosition: CellCoordinate(column: 6, row: 4))
                grid.copy(nil)
                sheet.selectCell(atColumn: 10, row: 4)
                grid.paste(options: [.asValues, .transpose])
                NSLog("phase3: transposed K5=%@ P5=%@", sheet.displayTextOfCell(atColumn: 10, row: 4) ?? "nil",
                      sheet.displayTextOfCell(atColumn: 15, row: 4) ?? "nil")
                sheet.selectRange(CellRange(start: CellCoordinate(column: 6, row: 4), end: CellCoordinate(column: 6, row: 9)),
                                  editPosition: CellCoordinate(column: 6, row: 4))
                grid.sortDescending(nil)
                NSLog("phase3: sorted G5=%@ G10=%@ undo=%@", sheet.displayTextOfCell(atColumn: 6, row: 4) ?? "nil",
                      sheet.displayTextOfCell(atColumn: 6, row: 9) ?? "nil", sheet.workbook?.undoLabel ?? "nil")
                sheet.workbook?.recomputeAutoExpression()   // the engine's own trigger is a lag timer
                NSLog("phase3: auto-expression '%@'", sheet.workbook?.autoExpressionText ?? "nil")
                sheet.workbook?.setAutoExpression(function: "average", label: "Average")
                NSLog("phase3: auto-expression '%@'", sheet.workbook?.autoExpressionText ?? "nil")
                sheet.selectCell(atColumn: 0, row: 2)
                grid.recalculate(nil)
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            }
            autoreleasepool {
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_FILTER"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // A small table at A20:B25, an autofilter over it, one value
                // chosen from the first button's choices, the Sort dialog's
                // command, a sheet resize, and a tab color.
                let grid = controller.gridView
                let table: [(String, String)] = [("Name", "Qty"), ("apple", "3"), ("pear", "5"), ("apple", "7"), ("", "1"), ("kiwi", "9")]
                for (i, row) in table.enumerated() {
                    if !row.0.isEmpty { try? sheet.setText(row.0, atColumn: 0, row: 19 + i, autocorrect: false) }
                    try? sheet.setText(row.1, atColumn: 1, row: 19 + i, autocorrect: false)
                }
                let range = CellRange(start: CellCoordinate(column: 0, row: 19), end: CellCoordinate(column: 1, row: 24))
                sheet.selectRange(range, editPosition: range.start)
                grid.toggleAutofilter(nil)
                let buttons = sheet.filterButtons
                NSLog("filter: buttons=%ld inFilter=%d undo=%@", buttons.count, sheet.editPositionIsInFilter ? 1 : 0,
                      sheet.workbook?.undoLabel ?? "nil")
                if let first = buttons.first {
                    let choices = sheet.choices(for: first)
                    NSLog("filter: choices=%@ blanks=%d frame=%@", choices.values.joined(separator: ","), choices.hasBlanks ? 1 : 0,
                          NSStringFromRect(first.frame))
                    grid.applyFilterCondition(choices.condition(forValueAt: 0), to: first)
                    NSLog("filter: row 21 visible=%d row 22 visible=%d filtered=%d active=%d undo=%@",
                          sheet.isRowVisible(20) ? 1 : 0, sheet.isRowVisible(21) ? 1 : 0, sheet.hasFilteredRows ? 1 : 0,
                          sheet.filterButtons.first?.isActive ?? false ? 1 : 0, sheet.workbook?.undoLabel ?? "nil")
                }
                let key = SortKey(index: 1, descending: true, caseSensitive: false, byValue: true)
                do {
                    try sheet.sort(range, byRows: true, hasHeader: true, keys: [key], retainFormats: true)
                } catch {
                    NSLog("filter: sort failed: %@", error.localizedDescription)
                }
                NSLog("filter: sorted B21=%@ B25=%@ undo=%@", sheet.displayTextOfCell(atColumn: 1, row: 20) ?? "nil",
                      sheet.displayTextOfCell(atColumn: 1, row: 24) ?? "nil", sheet.workbook?.undoLabel ?? "nil")
                do {
                    try sheet.workbook?.resize([sheet], toColumns: sheet.columnCount * 2, rows: sheet.rowCount)
                } catch {
                    NSLog("filter: resize failed: %@", error.localizedDescription)
                }
                NSLog("filter: columns=%ld rows=%ld undo=%@", sheet.columnCount, sheet.rowCount, sheet.workbook?.undoLabel ?? "nil")
                do {
                    try sheet.workbook?.setTabColor(NSColor.systemOrange.cgColor, textColor: nil, of: sheet)
                } catch {
                    NSLog("filter: tab color failed: %@", error.localizedDescription)
                }
                NSLog("filter: tab color=%d tabs=%ld undo=%@", sheet.tabColor() != nil ? 1 : 0, controller.tabCount,
                      sheet.workbook?.undoLabel ?? "nil")
                sheet.selectCell(atColumn: 0, row: 19)
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            }
            autoreleasepool {
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_OBJECTS"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Sheet objects: select the front chart, move and resize it
                // through the same command the drag commits, delete the
                // second one and undo; the capture shows the handles.
                let grid = controller.gridView
                let objects = sheet.sheetObjects
                NSLog("objects: count=%ld first=%@", objects.count, objects.first.map { "\($0.typeName) \(NSStringFromRect($0.frame))" } ?? "nil")
                if let first = objects.first {
                    grid.select(objects: [first])
                    do {
                        try sheet.setFrames([NSValue(rect: first.frame.offsetBy(dx: 60, dy: 40))], of: [first], resizing: false)
                        var grown = first.frame
                        grown.size.width += 80
                        try sheet.setFrames([NSValue(rect: grown)], of: [first], resizing: true)
                    } catch {
                        NSLog("objects: move or resize failed: %@", error.localizedDescription)
                    }
                    NSLog("objects: now %@ undo=%@ hit=%d", NSStringFromRect(first.frame), sheet.workbook?.undoLabel ?? "nil",
                          sheet.sheetObject(at: NSPoint(x: first.frame.midX, y: first.frame.midY)) == first ? 1 : 0)
                    if objects.count > 1 {
                        try? sheet.deleteSheetObjects([objects[1]])
                        NSLog("objects: deleted second count=%ld undo=%@", sheet.sheetObjects.count, sheet.workbook?.undoLabel ?? "nil")
                        grid.undo(nil)
                        NSLog("objects: after undo count=%ld attached=%d selected=%ld", sheet.sheetObjects.count,
                              objects[1].isAttached ? 1 : 0, grid.selectedObjects.count)
                    }
                    // Copy the selected object and paste it at A40; then an
                    // image made here, placed where the controller would put it.
                    grid.copy(nil)
                    sheet.selectCell(atColumn: 0, row: 39)
                    grid.paste(nil)
                    NSLog("objects: pasted copy count=%ld png=%ld bytes undo=%@", sheet.sheetObjects.count,
                          NSPasteboard.general.data(forType: .png)?.count ?? 0, sheet.workbook?.undoLabel ?? "nil")
                    let image = NSImage(size: NSSize(width: 60, height: 40), flipped: false) { rect in
                        NSColor.systemGreen.setFill()
                        rect.fill()
                        return true
                    }
                    if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        let size = sheet.naturalSize(ofImageData: png)
                        sheet.selectCell(atColumn: 6, row: 39)
                        let frame = grid.suggestedFrameForNewObject(size: size)
                        if let picture = try? sheet.insertImage(png, frame: frame) {
                            grid.select(objects: [picture])
                            NSLog("objects: image %@ at %@ undo=%@", picture.typeName, NSStringFromRect(picture.frame), sheet.workbook?.undoLabel ?? "nil")
                        }
                    }
                }
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            }
            autoreleasepool {
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_EVERYDAY"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // The everyday items: the name box's jump, the current date
                // typed into a cell, cells inserted with a shift, a Save As
                // to CSV, and File → New.
                let grid = controller.gridView
                controller.jump(to: "C10")
                NSLog("everyday: after jump to C10 edit position=%ld,%ld", sheet.editPosition.column, sheet.editPosition.row)
                controller.jump(to: "Nowhere!A1")   // an error, shown as a sheet and logged
                grid.insertCurrentDate(nil)
                NSLog("everyday: date typed into C10 shows '%@' undo=%@", sheet.displayTextOfCell(atColumn: 2, row: 9) ?? "nil",
                      sheet.workbook?.undoLabel ?? "nil")
                let before = sheet.displayTextOfCell(atColumn: 0, row: 0) ?? ""
                do {
                    try sheet.insertCells(in: CellRange(start: CellCoordinate(column: 0, row: 0), end: CellCoordinate(column: 0, row: 0)), shiftingDown: false)
                } catch {
                    NSLog("everyday: insert cells failed: %@", error.localizedDescription)
                }
                NSLog("everyday: A1 '%@' moved to B1 '%@' undo=%@", before, sheet.displayTextOfCell(atColumn: 1, row: 0) ?? "nil",
                      sheet.workbook?.undoLabel ?? "nil")
                grid.undo(nil)
                if let document = controller.document as? WorkbookDocument {
                    let csvURL = URL(fileURLWithPath: (path as NSString).deletingPathExtension + "-saved.csv")
                    document.save(to: csvURL, ofType: WorkbookDocument.csvType, for: .saveToOperation) { error in
                        let head = (try? String(contentsOf: csvURL, encoding: .utf8))?.prefix(60) ?? ""
                        NSLog("everyday: csv error=%@ head='%@'", error?.localizedDescription ?? "none", String(head).replacingOccurrences(of: "\n", with: "|"))
                    }
                }
                NSDocumentController.shared.newDocument(nil)
                let untitled = NSDocumentController.shared.documents.first { $0.fileURL == nil } as? WorkbookDocument
                NSLog("everyday: documents=%ld untitled=%@ sheets=%ld windows=%ld", NSDocumentController.shared.documents.count,
                      untitled?.displayName ?? "none", untitled?.workbook?.sheets.count ?? 0, untitled?.windowControllers.count ?? 0)
                untitled?.close()
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_FUNC"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Autocompletion: "app" typed under "apple" fills in with the
                // tail selected; then Insert → Function… puts SUM( into a
                // fresh formula (captured to `-func.png`).
                do {
                    try sheet.setText("apple", atColumn: 3, row: 0, autocorrect: false)
                    try sheet.setText("apricot", atColumn: 3, row: 1, autocorrect: false)
                } catch {
                    NSLog("func: data failed: %@", error.localizedDescription)
                }
                sheet.selectCell(atColumn: 3, row: 2)
                controller.gridView.beginEditing(initialText: "a")
                controller.gridView.editorTextDidChangeForTesting("ap")
                controller.gridView.editorTextDidChangeForTesting("app")
                NSLog("func: editor '%@' tail %@", controller.gridView.editorTextForTesting,
                      controller.gridView.autocompleteTail.map(NSStringFromRange) ?? "nil")
                controller.gridView.commitEditing(text: controller.gridView.editorTextForTesting, movement: .none)
                NSLog("func: D3='%@'", sheet.displayTextOfCell(atColumn: 3, row: 2) ?? "nil")
                sheet.selectCell(atColumn: 5, row: 0)
                FunctionSelectorDialog.headlessDriver = { dialog in
                    dialog.search.stringValue = "sum"
                    dialog.filterChanged(nil)
                    dialog.select(named: "SUM")
                    if let content = dialog.alert.accessoryView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let funcPath = (path as NSString).deletingPathExtension + "-func.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: funcPath))
                            NSLog("func: captured %@ (%@)", funcPath, NSStringFromRect(content.bounds))
                        }
                    }
                    NSLog("func: %ld shown, selected %@ (%@)", dialog.shown.count, dialog.selectedFunction?.name ?? "nil", dialog.selectedFunction?.summary ?? "")
                    return true
                }
                controller.insertFunction(nil)
                FunctionSelectorDialog.headlessDriver = nil
                NSLog("func: editor now '%@'", controller.gridView.editorTextForTesting)
                controller.gridView.cancelEditing()
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_FORMULA"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // A formula typed in A5 takes B1:B3 from the grid, then Bold
                // through its shortcut; the grid capture shows the bold sum.
                do {
                    for r in 0..<3 { try sheet.setText("\(r + 1)", atColumn: 1, row: r, autocorrect: false) }
                } catch {
                    NSLog("formula: data failed: %@", error.localizedDescription)
                }
                sheet.selectCell(atColumn: 0, row: 4)
                controller.gridView.beginEditing(initialText: "=SUM(")
                var replace = NSRange(location: 0, length: 0)
                let takes = sheet.formulaText("=SUM(", cursorAt: 5, canTakeRange: &replace)
                controller.gridView.takeFormulaRange(CellRange(start: CellCoordinate(column: 1, row: 0), end: CellCoordinate(column: 1, row: 2)),
                                                     replacing: replace)
                NSLog("formula: takes=%d replace=%@ outlined=%@", takes ? 1 : 0, NSStringFromRange(replace),
                      controller.gridView.formulaRangeShown.map { "\($0.start.column),\($0.start.row)-\($0.end.column),\($0.end.row)" } ?? "nil")
                controller.gridView.commitEditing(text: "=SUM(B1:B3)", movement: .none)
                NSLog("formula: A5='%@' entered '%@'", sheet.displayTextOfCell(atColumn: 0, row: 4) ?? "nil",
                      sheet.enteredTextOfCell(atColumn: 0, row: 4) ?? "nil")
                controller.toggleBold(nil)
                NSLog("formula: bold=%@ undo=%@", sheet.formatOfSelection.bold ?? -1, sheet.workbook?.undoLabel ?? "nil")
                // Keyboard range selection as key events through the field
                // editor: "=MAX(" in A6, Right (B6), ⌘Up (the data's edge,
                // B3), Shift+⌘Up (B1:B3), ")" and Return; then an array
                // formula over A7:A9 by Shift+⌘Return.
                func key(_ code: UInt16, _ character: String, _ flags: NSEvent.ModifierFlags) {
                    if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: window.windowNumber, context: nil, characters: character,
                                                   charactersIgnoringModifiers: character, isARepeat: false, keyCode: code) {
                        window.sendEvent(event)
                    }
                }
                let up = String(UnicodeScalar(NSUpArrowFunctionKey)!), right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
                sheet.selectCell(atColumn: 0, row: 5)
                // A6 in bold Georgia 14, right-aligned, red: the editor takes
                // the cell's style.
                let style = CellFormat()
                style.fontName = "Georgia"
                style.fontSize = 14
                style.bold = true
                style.horizontalAlignment = 0x04
                style.textColor = NSColor.systemRed.cgColor
                do { try sheet.apply(style) } catch { NSLog("formula: style failed: %@", error.localizedDescription) }
                controller.gridView.beginEditing(initialText: "=MAX(")
                NSLog("formula: editor style %@ (Sans is %@)", controller.gridView.editorStyleForTesting,
                      Engine.shared?.resolvedFontFamily(forName: "Sans") ?? "nil")
                NSLog("formula: tooltip for '=MAX(' is '%@'", controller.gridView.functionTooltip?.text ?? "nil")
                key(124, right, [])
                NSLog("formula: Right -> '%@'", controller.gridView.editorTextForTesting)
                key(126, up, [.command])
                NSLog("formula: ⌘Up -> '%@'", controller.gridView.editorTextForTesting)
                key(126, up, [.command, .shift])
                NSLog("formula: ⇧⌘Up -> '%@' outlined=%@", controller.gridView.editorTextForTesting,
                      controller.gridView.formulaRangeShown.map { "\($0.start.column),\($0.start.row)-\($0.end.column),\($0.end.row)" } ?? "nil")
                key(118, "", [])   // F4 on the taken range: absolute
                NSLog("formula: F4 -> '%@'", controller.gridView.editorTextForTesting)
                key(118, "", [])   // F4 again: absolute row
                NSLog("formula: F4 F4 -> '%@' outlined=%@", controller.gridView.editorTextForTesting,
                      controller.gridView.formulaRangeShown.map { "\($0.start.column),\($0.start.row)-\($0.end.column),\($0.end.row)" } ?? "nil")
                key(118, "", [])   // absolute column
                key(118, "", [])   // back to relative
                NSLog("formula: F4 x4 -> '%@'", controller.gridView.editorTextForTesting)
                key(29, ")", [])
                NSLog("formula: ) -> '%@' outlined=%@ fieldEditor=%@", controller.gridView.editorTextForTesting,
                      controller.gridView.formulaRangeShown.map { "\($0.start.column),\($0.start.row)-\($0.end.column),\($0.end.row)" } ?? "nil",
                      String(describing: type(of: window.firstResponder as AnyObject)))
                key(126, up, [])   // no range to take after ")": Up commits upward
                NSLog("formula: Up -> '%@' A6='%@' entered '%@' editing=%d edit=%ld,%ld", controller.gridView.editorTextForTesting,
                      sheet.displayTextOfCell(atColumn: 0, row: 5) ?? "nil",
                      sheet.enteredTextOfCell(atColumn: 0, row: 5) ?? "nil", controller.gridView.isEditing ? 1 : 0,
                      sheet.editPosition.column, sheet.editPosition.row)
                // "=avera" typed in A10 lists AVERAGE and friends under the
                // editor (captured); "=averageif" is itself a name, so F4
                // completes to the one longer name, AVERAGEIFS, as in the GTK.
                sheet.selectCell(atColumn: 0, row: 9)
                controller.gridView.beginEditing(initialText: "=avera")
                NSLog("formula: completions for '=avera': %@ single=%@", controller.gridView.functionTooltip?.completions.joined(separator: ",") ?? "nil",
                      controller.gridView.functionTooltip?.completion ?? "nil")
                let grid = controller.gridView
                grid.layoutSubtreeIfNeeded()
                grid.displayIfNeeded()
                if let rep = grid.bitmapImageRepForCachingDisplay(in: grid.bounds) {
                    grid.cacheDisplay(in: grid.bounds, to: rep)
                    let tipPath = (path as NSString).deletingPathExtension + "-tooltip.png"
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: tipPath))
                    NSLog("formula: captured %@", tipPath)
                }
                controller.gridView.cancelEditing()
                controller.gridView.beginEditing(initialText: "=averageif")
                key(118, "", [])   // F4
                NSLog("formula: F4 on '=averageif' -> '%@' tooltip '%@'", controller.gridView.editorTextForTesting,
                      controller.gridView.functionTooltip?.text ?? "nil")
                controller.gridView.cancelEditing()
                sheet.selectRange(CellRange(start: CellCoordinate(column: 0, row: 6), end: CellCoordinate(column: 0, row: 8)),
                                  editPosition: CellCoordinate(column: 0, row: 6))
                controller.gridView.beginEditing(initialText: "=B1:B3*2")
                key(36, "\r", [.command, .shift])
                NSLog("formula: array A7..A9 = '%@' '%@' '%@' entered '%@' undo=%@ editing=%d",
                      sheet.displayTextOfCell(atColumn: 0, row: 6) ?? "nil", sheet.displayTextOfCell(atColumn: 0, row: 7) ?? "nil",
                      sheet.displayTextOfCell(atColumn: 0, row: 8) ?? "nil", sheet.enteredTextOfCell(atColumn: 0, row: 7) ?? "nil",
                      sheet.workbook?.undoLabel ?? "nil", controller.gridView.isEditing ? 1 : 0)
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_PRINT"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Printing: landscape with grid lines and a header through the
                // Page Setup dialog (captured to `-print.png`), then the first
                // printed page drawn to `-page1.png`.
                PageSetupDialog.headlessDriver = { dialog in
                    dialog.orientation.selectItem(at: 1)
                    dialog.gridLines.state = .on
                    dialog.titles.state = .on
                    dialog.headerMiddle.stringValue = "&[TAB] — page &[PAGE] of &[PAGES]"
                    if let content = dialog.alert.accessoryView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let printPath = (path as NSString).deletingPathExtension + "-print.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: printPath))
                            NSLog("print: captured %@ (%@)", printPath, NSStringFromRect(content.bounds))
                        }
                    }
                    return true
                }
                controller.pageSetup(nil)
                PageSetupDialog.headlessDriver = nil
                let settings = sheet.printSettings
                NSLog("print: paper %@ orientation %ld grid %d titles %d header '%@' undo=%@", settings.paperDisplayName, settings.orientation.rawValue,
                      settings.printsGridLines ? 1 : 0, settings.printsTitles ? 1 : 0, settings.headerMiddle, sheet.workbook?.undoLabel ?? "nil")
                controller.printSheet(nil)
                if let job = WorkbookWindowController.lastPrintJob {
                    let size = job.pageSize
                    if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                       let graphics = NSGraphicsContext(bitmapImageRep: rep) {
                        NSGraphicsContext.saveGraphicsState()
                        NSGraphicsContext.current = graphics
                        let cg = graphics.cgContext
                        cg.setFillColor(CGColor.white)
                        cg.fill(CGRect(origin: .zero, size: size))
                        cg.translateBy(x: 0, y: size.height)
                        cg.scaleBy(x: 1, y: -1)
                        job.drawPage(0, in: cg)
                        NSGraphicsContext.restoreGraphicsState()
                        let pagePath = (path as NSString).deletingPathExtension + "-page1.png"
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: pagePath))
                        NSLog("print: %ld pages of %gx%g, first %@, drawn to %@", job.pageCount, size.width, size.height, job.rangeName(ofPage: 0), pagePath)
                    }
                }
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_SOLVE"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // The Solver: maximize B1 = 3*A1 + 2*A2 with A1 + A2 <= 4 and
                // A1 <= 3, non-negative, through the dialog (captured to
                // `-solve.png`); the grid capture shows A1 = 3, A2 = 1, B1 = 11.
                do {
                    try sheet.setText("1", atColumn: 0, row: 0, autocorrect: false)
                    try sheet.setText("1", atColumn: 0, row: 1, autocorrect: false)
                    try sheet.setText("=3*A1+2*A2", atColumn: 1, row: 0, autocorrect: false)
                    try sheet.setText("=A1+A2", atColumn: 2, row: 0, autocorrect: false)
                } catch {
                    NSLog("solve: data failed: %@", error.localizedDescription)
                }
                SolverDialog.headlessDriver = { dialog in
                    dialog.targetField.stringValue = "B1"
                    dialog.goal.selectItem(at: 0)
                    dialog.inputField.stringValue = "A1:A2"
                    dialog.model.selectItem(at: 2)
                    dialog.nonNegative.state = .on
                    dialog.lhsField.stringValue = "C1"
                    dialog.kind.selectItem(at: 0)
                    dialog.rhsField.stringValue = "4"
                    dialog.addRule(nil)
                    dialog.lhsField.stringValue = "A1"
                    dialog.rhsField.stringValue = "3"
                    dialog.addRule(nil)
                    NSLog("solve: dialog algorithms %@; rules %ld", dialog.algorithms.map(\.identifier), dialog.rules.count)
                    if let content = dialog.alert.accessoryView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let solvePath = (path as NSString).deletingPathExtension + "-solve.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: solvePath))
                            NSLog("solve: captured %@ (%@)", solvePath, NSStringFromRect(content.bounds))
                        }
                    }
                    return true
                }
                controller.solver(nil)
                SolverDialog.headlessDriver = nil
                // The run goes through the progress sheet's timer: pump the
                // run loop until the outcome arrives.
                let deadline = Date(timeIntervalSinceNow: 15)
                while WorkbookWindowController.lastSolverOutcome == nil && Date() < deadline {
                    RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
                }
                let outcome = WorkbookWindowController.lastSolverOutcome
                NSLog("solve: status=%@ quality=%ld objective=%g A1=%@ A2=%@ B1=%@ undo=%@", outcome?.status ?? "nil", outcome?.quality.rawValue ?? -1,
                      outcome?.objectiveValue ?? .nan, sheet.displayTextOfCell(atColumn: 0, row: 0) ?? "nil",
                      sheet.displayTextOfCell(atColumn: 0, row: 1) ?? "nil", sheet.displayTextOfCell(atColumn: 1, row: 0) ?? "nil",
                      sheet.workbook?.undoLabel ?? "nil")
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_ADVFILTER"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // The advanced filter: a list in A1:B6 and criteria in D1:D2
                // (Qty > 4) filtered in place through the dialog (captured
                // to `-advfilter.png`), then the matches copied to G1; then
                // a second sheet hidden and shown again.
                let table: [(String, String)] = [("Name", "Qty"), ("apple", "3"), ("pear", "5"), ("apple", "7"), ("fig", "1"), ("kiwi", "9")]
                do {
                    for (i, row) in table.enumerated() {
                        try sheet.setText(row.0, atColumn: 0, row: i, autocorrect: false)
                        try sheet.setText(row.1, atColumn: 1, row: i, autocorrect: false)
                    }
                    try sheet.setText("Qty", atColumn: 3, row: 0, autocorrect: false)
                    try sheet.setText(">4", atColumn: 3, row: 1, autocorrect: false)
                } catch {
                    NSLog("advfilter: data failed: %@", error.localizedDescription)
                }
                sheet.selectRange(CellRange(start: CellCoordinate(column: 0, row: 0), end: CellCoordinate(column: 1, row: 5)),
                                  editPosition: CellCoordinate(column: 0, row: 0))
                AdvancedFilterDialog.headlessDriver = { dialog in
                    dialog.criteriaField.stringValue = "D1:D2"
                    if let content = dialog.alert.accessoryView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let filterPath = (path as NSString).deletingPathExtension + "-advfilter.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: filterPath))
                            NSLog("advfilter: captured %@ (%@)", filterPath, NSStringFromRect(content.bounds))
                        }
                    }
                    return true
                }
                controller.advancedFilter(nil)
                NSLog("advfilter: in place: rows visible %d %d %d %d %d", sheet.isRowVisible(1) ? 1 : 0, sheet.isRowVisible(2) ? 1 : 0,
                      sheet.isRowVisible(3) ? 1 : 0, sheet.isRowVisible(4) ? 1 : 0, sheet.isRowVisible(5) ? 1 : 0)
                AdvancedFilterDialog.headlessDriver = { dialog in
                    dialog.listField.stringValue = "A1:B6"
                    dialog.criteriaField.stringValue = "D1:D2"
                    dialog.destination.selectItem(at: 1)
                    dialog.outputField.stringValue = "G1"
                    return true
                }
                controller.advancedFilter(nil)
                AdvancedFilterDialog.headlessDriver = nil
                NSLog("advfilter: copied: G1=%@ G2=%@ H2=%@ G4=%@ undo=%@", sheet.displayTextOfCell(atColumn: 6, row: 0) ?? "nil",
                      sheet.displayTextOfCell(atColumn: 6, row: 1) ?? "nil", sheet.displayTextOfCell(atColumn: 7, row: 1) ?? "nil",
                      sheet.displayTextOfCell(atColumn: 6, row: 3) ?? "nil", sheet.workbook?.undoLabel ?? "nil")
                controller.appendSheet(nil)
                let added = controller.gridView.sheet
                controller.hideSheet(nil)
                NSLog("advfilter: '%@' hidden=%d tabs=%ld now on '%@' undo=%@", added?.name ?? "nil", added?.isVisible == false ? 1 : 0, controller.tabCount,
                      controller.gridView.sheet?.name ?? "nil", sheet.workbook?.undoLabel ?? "nil")
                WorkbookWindowController.unhideChoiceForTesting = added?.name
                controller.unhideSheet(nil)
                WorkbookWindowController.unhideChoiceForTesting = nil
                NSLog("advfilter: shown again=%d tabs=%ld on '%@'", added?.isVisible == true ? 1 : 0, controller.tabCount, controller.gridView.sheet?.name ?? "nil")
                controller.workbook.select(sheet)
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_OUTLINE"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Outlines: rows 2–4 grouped (whole rows: no question), rows
                // 2–3 grouped inside, columns B–C grouped, then the inner
                // rows' detail hidden; the window capture shows the header
                // strips with their bars and the + box; the row header's
                // toggle then shows them again.
                do {
                    for r in 0..<6 { for c in 0..<3 { try sheet.setText("\(r * 3 + c + 1)", atColumn: c, row: r, autocorrect: false) } }
                } catch {
                    NSLog("outline: data failed: %@", error.localizedDescription)
                }
                controller.gridView.selectRows(from: 1, to: 3, anchor: 1)
                controller.groupOutline(nil)
                controller.gridView.selectRows(from: 1, to: 2, anchor: 1)
                controller.groupOutline(nil)
                controller.gridView.selectColumns(from: 1, to: 2, anchor: 1)
                controller.groupOutline(nil)
                controller.gridView.selectRows(from: 1, to: 2, anchor: 1)
                controller.hideDetail(nil)
                let headers = controller.gridView.headerViews
                NSLog("outline: row levels %ld %ld %ld %ld column levels %ld %ld max %ld/%ld hidden rows %d %d collapsed row 4 %d undo=%@ headers %@ / %@",
                      sheet.outlineLevel(ofRow: 0), sheet.outlineLevel(ofRow: 1), sheet.outlineLevel(ofRow: 3), sheet.outlineLevel(ofRow: 4),
                      sheet.outlineLevel(ofColumn: 1), sheet.outlineLevel(ofColumn: 3), sheet.maximumRowOutlineLevel, sheet.maximumColumnOutlineLevel,
                      sheet.isRowVisible(1) ? 0 : 1, sheet.isRowVisible(2) ? 0 : 1, sheet.isRowCollapsed(3) ? 1 : 0, sheet.workbook?.undoLabel ?? "nil",
                      headers.count == 2 ? NSStringFromSize(headers[0].intrinsicContentSize) : "-",
                      headers.count == 2 ? NSStringFromSize(headers[1].intrinsicContentSize) : "-")
                // The row header's toggle at row 4 (which ends the hidden
                // group), level 2: the rows show again; hidden once more for
                // the capture.
                if headers.count == 2 { headers[1].toggleOutline(at: 3, step: 2) }
                NSLog("outline: after the toggle: rows visible %d %d undo=%@", sheet.isRowVisible(1) ? 1 : 0, sheet.isRowVisible(2) ? 1 : 0,
                      sheet.workbook?.undoLabel ?? "nil")
                controller.gridView.selectRows(from: 1, to: 2, anchor: 1)
                controller.hideDetail(nil)
                sheet.selectCell(atColumn: 0, row: 0)
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_WHATIF"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // What-if: A3 = A1·A2; a data table over C1:E3 through its
                // dialog (captured to `-table.png`), uniform random numbers
                // into H1 through the generator's dialog, then a tabulation
                // of A3 over A1 through its dialog, which lands on a new
                // sheet the grid capture shows.
                let texts = [(0, 0, "2"), (0, 1, "3"), (0, 2, "=A1*A2"), (2, 0, "=A3"), (3, 0, "10"), (4, 0, "20"), (2, 1, "1"), (2, 2, "2")]
                do {
                    for (c, r, text) in texts { try sheet.setText(text, atColumn: c, row: r, autocorrect: false) }
                } catch {
                    NSLog("whatif: model failed: %@", error.localizedDescription)
                }
                sheet.selectRange(CellRange(start: CellCoordinate(column: 2, row: 0), end: CellCoordinate(column: 4, row: 2)),
                                  editPosition: CellCoordinate(column: 2, row: 0))
                DataTableDialog.headlessDriver = { dialog in
                    dialog.rowField.stringValue = "A1"
                    dialog.columnField.stringValue = "A2"
                    if let content = dialog.alert.accessoryView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let tablePath = (path as NSString).deletingPathExtension + "-table.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: tablePath))
                            NSLog("whatif: captured %@ (%@)", tablePath, NSStringFromRect(content.bounds))
                        }
                    }
                    return true
                }
                controller.dataTable(nil)
                DataTableDialog.headlessDriver = nil
                NSLog("whatif: table D2=%@ E3=%@ undo=%@", sheet.displayTextOfCell(atColumn: 3, row: 1) ?? "nil",
                      sheet.displayTextOfCell(atColumn: 4, row: 2) ?? "nil", sheet.workbook?.undoLabel ?? "nil")
                AnalysisDialog.headlessDriver = { dialog in
                    dialog.distribution.selectItem(at: 2)   // Normal
                    dialog.firstParameterField.stringValue = "50"
                    dialog.secondParameterField.stringValue = "0"
                    dialog.countField.stringValue = "3"
                    dialog.destination.selectItem(at: 1)
                    dialog.outputField.stringValue = "H1"
                    NSLog("whatif: random dialog labels '%@' / '%@' chosen %ld", dialog.firstParameterLabel.stringValue,
                          dialog.secondParameterLabel.stringValue, dialog.chosenDistribution.rawValue)
                    return true
                }
                controller.randomNumbers(nil)
                AnalysisDialog.headlessDriver = nil
                NSLog("whatif: random H1=%@ H3=%@ H4=%@ undo=%@", sheet.displayTextOfCell(atColumn: 7, row: 0) ?? "nil",
                      sheet.displayTextOfCell(atColumn: 7, row: 2) ?? "nil", sheet.displayTextOfCell(atColumn: 7, row: 3) ?? "nil",
                      sheet.workbook?.undoLabel ?? "nil")
                TabulateDialog.headlessDriver = { dialog in
                    dialog.rows[0].cell.stringValue = "A1"
                    dialog.rows[0].minimum.stringValue = "1"
                    dialog.rows[0].maximum.stringValue = "4"
                    dialog.rows[0].step.stringValue = "1"
                    dialog.resultField.stringValue = "A3"
                    return true
                }
                controller.tabulate(nil)
                TabulateDialog.headlessDriver = nil
                let shown = controller.gridView.sheet
                NSLog("whatif: tabulation on '%@' of %ld sheets: B2=%@ B5=%@ undo=%@", shown?.name ?? "nil", sheet.workbook?.sheets.count ?? 0,
                      shown?.displayTextOfCell(atColumn: 1, row: 1) ?? "nil", shown?.displayTextOfCell(atColumn: 1, row: 4) ?? "nil",
                      sheet.workbook?.undoLabel ?? "nil")
                // Back on the first sheet: K1:L2 and K4:L5 consolidated by SUM
                // into N1 through the dialog, then K1:L2 shuffled in place.
                controller.workbook.select(sheet)
                do {
                    for (i, text) in ["1", "2", "3", "4"].enumerated() { try sheet.setText(text, atColumn: 10 + i % 2, row: i / 2, autocorrect: false) }
                    for (i, text) in ["10", "20", "30", "40"].enumerated() { try sheet.setText(text, atColumn: 10 + i % 2, row: 3 + i / 2, autocorrect: false) }
                } catch {
                    NSLog("whatif: consolidate data failed: %@", error.localizedDescription)
                }
                AnalysisDialog.headlessDriver = { dialog in
                    dialog.sourceFields[0].stringValue = "K1:L2"
                    dialog.sourceFields[1].stringValue = "K4:L5"
                    dialog.destination.selectItem(at: 1)
                    dialog.outputField.stringValue = "N1"
                    return true
                }
                controller.consolidate(nil)
                AnalysisDialog.headlessDriver = nil
                NSLog("whatif: consolidated N1=%@ O2=%@ undo=%@", sheet.displayTextOfCell(atColumn: 13, row: 0) ?? "nil",
                      sheet.displayTextOfCell(atColumn: 14, row: 1) ?? "nil", sheet.workbook?.undoLabel ?? "nil")
                ShuffleDialog.headlessDriver = { dialog in
                    dialog.rangeField.stringValue = "K1:L2"
                    dialog.method.selectItem(at: 2)
                    return true
                }
                controller.shuffle(nil)
                ShuffleDialog.headlessDriver = nil
                NSLog("whatif: shuffled K1:L2 = %@ %@ %@ %@ undo=%@", sheet.displayTextOfCell(atColumn: 10, row: 0) ?? "nil",
                      sheet.displayTextOfCell(atColumn: 11, row: 0) ?? "nil", sheet.displayTextOfCell(atColumn: 10, row: 1) ?? "nil",
                      sheet.displayTextOfCell(atColumn: 11, row: 1) ?? "nil", sheet.workbook?.undoLabel ?? "nil")
                if let tabulation = controller.workbook.sheets.last, tabulation != sheet { controller.workbook.select(tabulation) }
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_SHEET"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Format → Sheet: A1 a formula and B1 a zero, then Display
                // Formulæ, Hide Zeros, Hide Gridlines, and Hide Row Headers
                // toggled; the window capture shows the formula text, the
                // blank zero, no grid lines, and no row header.  Then Zoom…
                // to 150% through its dialog (captured to `-zoom.png`).
                do {
                    try sheet.setText("=1+1", atColumn: 0, row: 0, autocorrect: false)
                    try sheet.setText("0", atColumn: 1, row: 0, autocorrect: false)
                } catch {
                    NSLog("sheet: data failed: %@", error.localizedDescription)
                }
                controller.toggleDisplayFormulas(nil)
                controller.toggleHideZeros(nil)
                controller.toggleHideGridLines(nil)
                controller.toggleHideRowHeaders(nil)
                NSLog("sheet: formulas=%d zeros=%d grid=%d rowHeader=%d colHeader=%d A1='%@' B1='%@' undo=%@ rowHeaderHidden=%d",
                      sheet.displaysFormulas ? 1 : 0, sheet.hidesZeros ? 1 : 0, sheet.hidesGridLines ? 1 : 0, sheet.hidesRowHeader ? 1 : 0,
                      sheet.hidesColumnHeader ? 1 : 0, sheet.displayTextOfCell(atColumn: 0, row: 0) ?? "nil",
                      sheet.displayTextOfCell(atColumn: 1, row: 0) ?? "nil", sheet.workbook?.undoLabel ?? "nil",
                      controller.gridView.headerViews.count == 2 && controller.gridView.headerViews[1].isHidden ? 1 : 0)
                controller.toggleR1C1(nil)
                NSLog("sheet: r1c1=%d column 2 is '%@'", sheet.usesR1C1 ? 1 : 0, sheet.name(ofColumn: 2))
                controller.toggleR1C1(nil)
                ZoomDialog.headlessDriver = { dialog in
                    dialog.percentField.stringValue = "150"
                    if let content = dialog.alert.accessoryView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let zoomPath = (path as NSString).deletingPathExtension + "-zoom.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: zoomPath))
                            NSLog("sheet: captured %@ (%@)", zoomPath, NSStringFromRect(content.bounds))
                        }
                    }
                    return true
                }
                controller.zoomDialog(nil)
                ZoomDialog.headlessDriver = nil
                NSLog("sheet: zoom=%g undo=%@", sheet.zoomFactor, sheet.workbook?.undoLabel ?? "nil")
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_LINK"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Hyperlinks: a web link on A1 through the dialog (captured to
                // `-link.png`), an internal link on A3 to C5 followed, the
                // tool tip over A1; the grid capture shows the blue
                // underlined cells.
                sheet.selectCell(atColumn: 0, row: 0)
                HyperlinkDialog.headlessDriver = { dialog in
                    dialog.kind.selectItem(at: 3)
                    dialog.kindChanged(nil)
                    dialog.webField.stringValue = "https://www.gnumeric.org/"
                    dialog.defaultTip.state = .off
                    dialog.kindChanged(nil)
                    dialog.tipField.stringValue = "The Gnumeric project"
                    if let content = dialog.alert.accessoryView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let linkPath = (path as NSString).deletingPathExtension + "-link.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: linkPath))
                            NSLog("link: captured %@ (%@)", linkPath, NSStringFromRect(content.bounds))
                        }
                    }
                    return true
                }
                controller.insertHyperlink(nil)
                sheet.selectCell(atColumn: 0, row: 2)
                HyperlinkDialog.headlessDriver = { dialog in
                    dialog.kind.selectItem(at: 0)
                    dialog.kindChanged(nil)
                    dialog.rangeField.stringValue = "C5"
                    return true
                }
                controller.insertHyperlink(nil)
                HyperlinkDialog.headlessDriver = nil
                let a1 = sheet.hyperlink(atColumn: 0, row: 0), a3 = sheet.hyperlink(atColumn: 0, row: 2)
                NSLog("link: A1='%@' kind=%ld target='%@' tip='%@'; A3 kind=%ld target='%@'; undo=%@",
                      sheet.displayTextOfCell(atColumn: 0, row: 0) ?? "nil", a1?.kind.rawValue ?? -1, a1?.target ?? "nil", a1?.tip ?? "nil",
                      a3?.kind.rawValue ?? -1, a3?.target ?? "nil", sheet.workbook?.undoLabel ?? "nil")
                controller.gridView.followHyperlink(atColumn: 0, row: 2)
                let selection = sheet.selectedRange
                NSLog("link: followed A3 -> selection %ld,%ld; tool tip over A1 '%@'; ranges %ld", selection.start.column, selection.start.row,
                      controller.gridView.commentToolTip(atColumn: 0, row: 0) ?? "nil",
                      sheet.hyperlinkRanges(in: CellRange(start: CellCoordinate(column: 0, row: 0), end: CellCoordinate(column: 5, row: 10))).count)
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_VALID"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Data validation: C1 takes a value from B1:B5 through the
                // dialog (captured to `-valid.png`) with an input message; an
                // entry outside the list is refused, one from the list taken;
                // the grid capture shows the list arrow and the message.
                do {
                    for r in 0..<5 { try sheet.setText("\(r + 1)", atColumn: 1, row: r, autocorrect: false) }
                } catch {
                    NSLog("valid: data failed: %@", error.localizedDescription)
                }
                sheet.selectCell(atColumn: 2, row: 0)
                ValidationDialog.headlessDriver = { dialog in
                    dialog.kind.selectItem(at: ValidationDialog.kinds.firstIndex(of: .inList) ?? 0)
                    dialog.criteriaChanged(nil)
                    dialog.firstField.stringValue = "$B$1:$B$5"
                    dialog.errorTitle.stringValue = "Pick from the list"
                    dialog.messageTitle.stringValue = "Choose"
                    dialog.messageText.stringValue = "A value from B1:B5"
                    if let content = dialog.alert.accessoryView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let validPath = (path as NSString).deletingPathExtension + "-valid.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: validPath))
                            NSLog("valid: captured %@ (%@)", validPath, NSStringFromRect(content.bounds))
                        }
                    }
                    NSLog("valid: dialog first label '%@' dropdown enabled %d", dialog.firstLabel.stringValue, dialog.dropdown.isEnabled ? 1 : 0)
                    return true
                }
                controller.dataValidation(nil)
                ValidationDialog.headlessDriver = nil
                let read = sheet.validation(atColumn: 2, row: 0)
                NSLog("valid: C1 kind=%ld source='%@' title='%@' choices=%@ message='%@' undo=%@", read?.kind.rawValue ?? -1,
                      read?.firstExpression ?? "nil", read?.errorTitle ?? "nil", controller.gridView.validationChoicesShown ?? [],
                      controller.gridView.inputMessageShown?.message ?? "nil", sheet.workbook?.undoLabel ?? "nil")
                WorkbookWindowController.validationAnswerForTesting = .discard
                let refused = sheet.validateText("7", atColumn: 2, row: 0)
                let taken = sheet.validateText("3", atColumn: 2, row: 0)
                WorkbookWindowController.validationAnswerForTesting = nil
                NSLog("valid: '7' -> %ld (%@); '3' -> %ld", refused.rawValue, WorkbookWindowController.lastValidationMessage ?? "nil", taken.rawValue)
                do {
                    try sheet.setText("3", atColumn: 2, row: 0, autocorrect: false)
                } catch {
                    NSLog("valid: entry failed: %@", error.localizedDescription)
                }
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_STATS"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // The analysis tools: x and y in A1:B6, a correlation matrix
                // into D1 through its dialog (captured to `-stats.png`), then
                // descriptive statistics with a confidence interval to a new
                // sheet, which the grid capture shows.
                do {
                    let xs = ["x", "1", "2", "3", "4", "5"], ys = ["y", "3", "5", "7", "9", "12"]
                    for r in 0..<6 {
                        try sheet.setText(xs[r], atColumn: 0, row: r, autocorrect: false)
                        try sheet.setText(ys[r], atColumn: 1, row: r, autocorrect: false)
                    }
                } catch {
                    NSLog("stats: data failed: %@", error.localizedDescription)
                }
                sheet.selectRange(CellRange(start: CellCoordinate(column: 0, row: 0), end: CellCoordinate(column: 1, row: 5)),
                                  editPosition: CellCoordinate(column: 0, row: 0))
                AnalysisDialog.headlessDriver = { dialog in
                    dialog.labels.state = .on
                    dialog.destination.selectItem(at: 1)
                    dialog.outputField.stringValue = "D1"
                    if let content = dialog.alert.accessoryView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let statsPath = (path as NSString).deletingPathExtension + "-stats.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: statsPath))
                            NSLog("stats: captured %@ (%@)", statsPath, NSStringFromRect(content.bounds))
                        }
                    }
                    NSLog("stats: dialog '%@' input '%@'", dialog.alert.messageText, dialog.inputField.stringValue)
                    return true
                }
                controller.correlation(nil)
                NSLog("stats: D1='%@' E3='%@' undo=%@", sheet.displayTextOfCell(atColumn: 3, row: 0) ?? "nil",
                      sheet.displayTextOfCell(atColumn: 4, row: 2) ?? "nil", sheet.workbook?.undoLabel ?? "nil")
                AnalysisDialog.headlessDriver = { dialog in
                    dialog.xField.stringValue = "A1:A6"
                    dialog.yField.stringValue = "B1:B6"
                    dialog.labels.state = .on
                    dialog.meanTestKind.selectItem(at: 0)
                    dialog.destination.selectItem(at: 1)
                    dialog.outputField.stringValue = "D6"
                    return true
                }
                controller.meanTest(nil)
                var tStat = "none"
                for r in 5..<30 where sheet.displayTextOfCell(atColumn: 3, row: r) == "t Stat" {
                    tStat = sheet.displayTextOfCell(atColumn: 4, row: r) ?? "nil"
                }
                NSLog("stats: paired t-test into D6: t Stat=%@ undo=%@", tStat, sheet.workbook?.undoLabel ?? "nil")
                // A histogram with three calculated cutoffs into D20 through
                // its dialog (captured to `-hist.png`), then a test of
                // independence on a 2×2 table into D30.
                sheet.selectRange(CellRange(start: CellCoordinate(column: 0, row: 0), end: CellCoordinate(column: 1, row: 5)),
                                  editPosition: CellCoordinate(column: 0, row: 0))
                AnalysisDialog.headlessDriver = { dialog in
                    dialog.labels.state = .on
                    dialog.cutoffCountField.stringValue = "3"
                    dialog.plusInfinity.state = .on
                    dialog.destination.selectItem(at: 1)
                    dialog.outputField.stringValue = "D20"
                    if let content = dialog.alert.accessoryView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let histPath = (path as NSString).deletingPathExtension + "-hist.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: histPath))
                            NSLog("stats: captured %@ (%@)", histPath, NSStringFromRect(content.bounds))
                        }
                    }
                    return true
                }
                controller.histogram(nil)
                NSLog("stats: histogram into D20: %@ | %@ / %@ | %@ / %@ | %@ undo=%@",
                      sheet.displayTextOfCell(atColumn: 3, row: 21) ?? "nil", sheet.displayTextOfCell(atColumn: 4, row: 21) ?? "nil",
                      sheet.displayTextOfCell(atColumn: 3, row: 22) ?? "nil", sheet.displayTextOfCell(atColumn: 4, row: 22) ?? "nil",
                      sheet.displayTextOfCell(atColumn: 3, row: 24) ?? "nil", sheet.displayTextOfCell(atColumn: 4, row: 24) ?? "nil",
                      sheet.workbook?.undoLabel ?? "nil")
                do {
                    for (i, text) in ["10", "20", "30", "40"].enumerated() { try sheet.setText(text, atColumn: 7 + i % 2, row: 30 + i / 2, autocorrect: false) }
                } catch {
                    NSLog("stats: table failed: %@", error.localizedDescription)
                }
                AnalysisDialog.headlessDriver = { dialog in
                    dialog.inputField.stringValue = "H31:I32"
                    dialog.destination.selectItem(at: 1)
                    dialog.outputField.stringValue = "D30"
                    return true
                }
                controller.independence(nil)
                NSLog("stats: independence into D30: %@ %@ / %@ %@ undo=%@",
                      sheet.displayTextOfCell(atColumn: 3, row: 30) ?? "nil", sheet.displayTextOfCell(atColumn: 4, row: 30) ?? "nil",
                      sheet.displayTextOfCell(atColumn: 3, row: 32) ?? "nil", sheet.displayTextOfCell(atColumn: 4, row: 32) ?? "nil",
                      sheet.workbook?.undoLabel ?? "nil")
                sheet.selectRange(CellRange(start: CellCoordinate(column: 0, row: 0), end: CellCoordinate(column: 1, row: 5)),
                                  editPosition: CellCoordinate(column: 0, row: 0))
                AnalysisDialog.headlessDriver = { dialog in
                    dialog.labels.state = .on
                    dialog.confidenceInterval.state = .on
                    return true
                }
                controller.descriptiveStatistics(nil)
                AnalysisDialog.headlessDriver = nil
                let shown = controller.gridView.sheet
                NSLog("stats: now on '%@' of %ld sheets, tabs=%ld; A2='%@' B2='%@' undo=%@", shown?.name ?? "nil",
                      sheet.workbook?.sheets.count ?? 0, controller.tabCount, shown?.displayTextOfCell(atColumn: 0, row: 1) ?? "nil",
                      shown?.displayTextOfCell(atColumn: 1, row: 1) ?? "nil", sheet.workbook?.undoLabel ?? "nil")
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_COND"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Conditional formatting: B5:B12 gets "value > 100 → yellow
                // fill, bold" through the dialog (captured to `-cond.png`),
                // which the grid capture then shows.
                sheet.selectRange(CellRange(start: CellCoordinate(column: 1, row: 4), end: CellCoordinate(column: 1, row: 11)),
                                  editPosition: CellCoordinate(column: 1, row: 4))
                controller.conditionalFormatting(nil)
                if let dialog = controller.conditionalDialog {
                    dialog.setEditor(op: .greaterThan, x: "100", fill: .yellow, bold: true)
                    dialog.add(nil)
                    NSLog("cond: dialog holds %ld condition(s): %@", dialog.conditions.count,
                          dialog.conditions.map { ConditionalFormatDialog.describe($0) })
                    if let content = dialog.window.contentView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let condPath = (path as NSString).deletingPathExtension + "-cond.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: condPath))
                            NSLog("cond: captured %@ (%@)", condPath, NSStringFromRect(content.bounds))
                        }
                    }
                    window.endSheet(dialog.window)
                    dialog.window.close()
                    controller.conditionalDialog = nil
                    do {
                        try sheet.setConditionalFormats(dialog.conditions)
                    } catch {
                        NSLog("cond: apply failed: %@", error.localizedDescription)
                    }
                }
                let read = sheet.conditionalFormats(atColumn: 1, row: 6)
                NSLog("cond: B7 has %ld condition(s) %@ undo=%@", read.count, read.map { "\($0.op.rawValue) \($0.firstExpression)" },
                      sheet.workbook?.undoLabel ?? "nil")
                controller.gridView.needsDisplay = true
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_GOAL"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Goal Seek: B30 = A30^2 - 9 driven to 0 by changing A30.
                do {
                    try sheet.setText("2", atColumn: 0, row: 29, autocorrect: false)
                    try sheet.setText("=A30*A30-9", atColumn: 1, row: 29, autocorrect: false)
                    let result = try sheet.goalSeek(cellAtColumn: 1, row: 29, toValue: 0, byChangingCellAtColumn: 0, row: 29, minimum: nil, maximum: nil)
                    NSLog("goal: found=%d solution=%g current=%g A30='%@' undo=%@", result.found ? 1 : 0, result.solution, result.currentValue,
                          sheet.displayTextOfCell(atColumn: 0, row: 29) ?? "nil", sheet.workbook?.undoLabel ?? "nil")
                    controller.gridView.undo(nil)
                    NSLog("goal: after undo A30='%@'", sheet.displayTextOfCell(atColumn: 0, row: 29) ?? "nil")
                } catch {
                    NSLog("goal: failed: %@", error.localizedDescription)
                }
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_FILL"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Fill Series down F1:F6 from 1 by 2, then Text to Columns on
                // "a;b" and "c;d" in G1:G2 through the assistant.
                do {
                    try sheet.fillSeries(in: CellRange(start: CellCoordinate(column: 5, row: 0), end: CellCoordinate(column: 5, row: 5)),
                                         byRows: false, kind: .linear, dateUnit: .day, start: 1, step: 2, stop: nil)
                    NSLog("fill: F1..F6 = %@ undo=%@", (0..<6).map { sheet.displayTextOfCell(atColumn: 5, row: $0) ?? "-" },
                          sheet.workbook?.undoLabel ?? "nil")
                    try sheet.setText("a;b", atColumn: 6, row: 0, autocorrect: false)
                    try sheet.setText("c;d", atColumn: 6, row: 1, autocorrect: false)
                    sheet.selectRange(CellRange(start: CellCoordinate(column: 6, row: 0), end: CellCoordinate(column: 6, row: 1)),
                                      editPosition: CellCoordinate(column: 6, row: 0))
                    TextImportAssistant.headlessDriver = { assistant in
                        assistant.model.separators = [";"]
                        NSLog("fill: text to columns assistant '%@' %ld columns", assistant.window.title, assistant.model.columnChoices.count)
                        return true
                    }
                    controller.textToColumns(nil)
                    TextImportAssistant.headlessDriver = nil
                    NSLog("fill: H1='%@' I1='%@' I2='%@' undo=%@", sheet.displayTextOfCell(atColumn: 7, row: 0) ?? "nil",
                          sheet.displayTextOfCell(atColumn: 8, row: 0) ?? "nil", sheet.displayTextOfCell(atColumn: 8, row: 1) ?? "nil",
                          sheet.workbook?.undoLabel ?? "nil")
                } catch {
                    NSLog("fill: failed: %@", error.localizedDescription)
                }
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_NAMES"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Define Names: a workbook name added through the dialog
                // (captured to `-names.png`), then inserted into a cell as
                // a formula.
                controller.defineNames(nil)
                if let dialog = controller.namesDialog {
                    NSLog("names: %ld listed before", dialog.names.count)
                    dialog.setFields(name: "first_column", expression: "Sheet1!$A$1:$A$10", workbookScope: true)
                    dialog.add(nil)
                    NSLog("names: after add %@ undo=%@", dialog.names.filter(\.isEditable).map { "\($0.name)=\($0.expressionText)" },
                          sheet.workbook?.undoLabel ?? "nil")
                    if let content = dialog.window.contentView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let namesPath = (path as NSString).deletingPathExtension + "-names.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: namesPath))
                            NSLog("names: captured %@ (%@)", namesPath, NSStringFromRect(content.bounds))
                        }
                    }
                    window.endSheet(dialog.window)
                    dialog.window.close()
                    controller.namesDialog = nil
                }
                sheet.selectCell(atColumn: 4, row: 0)
                controller.gridView.insertName("first_column")
                controller.gridView.commitEditing(text: "=COUNT(first_column)", movement: .none)
                NSLog("names: E1 shows '%@' from '%@'", sheet.displayTextOfCell(atColumn: 4, row: 0) ?? "nil",
                      sheet.enteredTextOfCell(atColumn: 4, row: 0) ?? "nil")
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_COMMENT"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // A comment on C3: the marker in the capture, the tool tip
                // text, the context menu's items, and the removal undone.
                do {
                    try sheet.setComment("Checked in Cocoa", author: "Hook", atColumn: 0, row: 2)
                } catch {
                    NSLog("comment: set failed: %@", error.localizedDescription)
                }
                NSLog("comment: A3 tool tip '%@' undo=%@ markers=%ld",
                      controller.gridView.commentToolTip(atColumn: 0, row: 2)?.replacingOccurrences(of: "\n", with: "|") ?? "nil",
                      sheet.workbook?.undoLabel ?? "nil",
                      sheet.comments(in: CellRange(start: CellCoordinate(column: 0, row: 0), end: CellCoordinate(column: 20, row: 20))).count)
                sheet.selectCell(atColumn: 0, row: 2)
                let point = controller.gridView.viewRect(forSheetRect: sheet.frameOfCell(atColumn: 0, row: 2))
                let fake = NSEvent.mouseEvent(with: .rightMouseDown, location: controller.gridView.convert(NSPoint(x: point.midX, y: point.midY), to: nil),
                                              modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                              eventNumber: 0, clickCount: 1, pressure: 1)
                if let fake, let menu = controller.gridView.menu(for: fake) {
                    NSLog("comment: context menu %@", menu.items.map(\.title))
                }
                controller.gridView.deleteComment(nil)
                NSLog("comment: after delete, comment=%@ undo=%@", sheet.comment(atColumn: 0, row: 2)?.text ?? "nil", sheet.workbook?.undoLabel ?? "nil")
                controller.gridView.undo(nil)
                NSLog("comment: after undo, comment=%@", sheet.comment(atColumn: 0, row: 2)?.text ?? "nil")
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_IMPORT"] != nil {
                // Import Text: a semicolon file beside the capture goes
                // through the assistant, driven headlessly (captured to
                // `-import.png`, the semicolon chosen, the first column as
                // text), into a new document.
                let importURL = URL(fileURLWithPath: (path as NSString).deletingPathExtension + "-import.txt")
                try? "id;name;amount\n007;Smith, J.;1.5\n008;\"Jones; A.\";2\n".write(to: importURL, atomically: true, encoding: .utf8)
                TextImportAssistant.headlessDriver = { assistant in
                    let model = assistant.model
                    NSLog("import: assistant for %@: %ld lines, kind %ld, separators '%@', %ld columns",
                          model.name, model.lineCount, model.kind.rawValue, model.session.separatorCharacters, model.columnChoices.count)
                    model.separators = [";"]
                    model.page = 2
                    if !model.columnFormats.isEmpty { model.columnFormats[0] = "@" }
                    NSLog("import: with semicolons %ld columns, formats %@", model.columnChoices.count, model.columnFormats)
                    if let content = assistant.window.contentView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let importPath = (path as NSString).deletingPathExtension + "-import.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: importPath))
                            NSLog("import: captured %@ (%@)", importPath, NSStringFromRect(content.bounds))
                        }
                    }
                    return true
                }
                AppDelegate.importText(at: importURL)
                TextImportAssistant.headlessDriver = nil
                if let imported = NSDocumentController.shared.documents.first(where: { $0.fileURL == importURL }) as? WorkbookDocument,
                   let sheet = imported.workbook?.sheets.first {
                    NSLog("import: document '%@' sheet '%@' A1='%@' B1='%@' C1='%@' A2='%@' windows=%ld", imported.displayName, sheet.name,
                          sheet.displayTextOfCell(atColumn: 0, row: 0) ?? "nil", sheet.displayTextOfCell(atColumn: 1, row: 0) ?? "nil",
                          sheet.displayTextOfCell(atColumn: 2, row: 0) ?? "nil", sheet.displayTextOfCell(atColumn: 0, row: 1) ?? "nil",
                          imported.windowControllers.count)
                    imported.close()
                } else {
                    NSLog("import: no document appeared")
                }
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_TEXT"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let document = controller.document as? WorkbookDocument {
                // Export as Text: a Save As to the text type opens the
                // options sheet, which is captured to `-export.png`, set to
                // semicolons and quotes always, and confirmed.
                let textURL = URL(fileURLWithPath: (path as NSString).deletingPathExtension + "-saved.txt")
                document.save(to: textURL, ofType: WorkbookDocument.textType, for: .saveToOperation) { error in
                    let head = (try? String(contentsOf: textURL, encoding: .utf8))?.prefix(80) ?? ""
                    NSLog("text: saved error=%@ head='%@'", error?.localizedDescription ?? "none",
                          String(head).replacingOccurrences(of: "\n", with: "|"))
                }
                if let sheet = controller.textExportSheet {
                    NSLog("text: sheet open with %ld sheets, %ld selected, separator preset %ld", sheet.model.sheets.count,
                          sheet.model.selected.count, sheet.model.separatorPreset)
                    if let content = sheet.window.contentView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let exportPath = (path as NSString).deletingPathExtension + "-export.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: exportPath))
                            NSLog("text: captured %@ (%@)", exportPath, NSStringFromRect(content.bounds))
                        }
                    }
                    sheet.model.separatorPreset = 1   // semicolon
                    sheet.model.quoting = .always
                    sheet.finish(true)
                } else {
                    NSLog("text: no sheet appeared")
                }
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_PREFS"] != nil,
               let delegate = NSApp.delegate as? AppDelegate, let engine = Engine.shared {
                // Settings: the window captured to `-settings.png`, a change
                // in the model reaching the engine, then put back.
                delegate.showSettings(nil)
                if let settings = delegate.settings {
                    let level = engine.preferences.xmlCompressionLevel
                    settings.model.xmlCompressionLevel = level == 5 ? 4 : 5
                    NSLog("settings: compression %ld -> engine says %ld; sheets %ld, enter %ld, font %@ %g",
                          level, engine.preferences.xmlCompressionLevel, engine.preferences.newWorkbookSheetCount,
                          engine.preferences.enterMovesDirection.rawValue, engine.preferences.defaultFontName,
                          engine.preferences.defaultFontSize)
                    settings.model.xmlCompressionLevel = level
                    settings.window.layoutIfNeeded()
                    NSLog("settings: window frame %@ visible=%d content %@", NSStringFromRect(settings.window.frame),
                          settings.window.isVisible ? 1 : 0, NSStringFromRect(settings.window.contentView?.bounds ?? .zero))
                    if let content = settings.window.contentView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let settingsPath = (path as NSString).deletingPathExtension + "-settings.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: settingsPath))
                            NSLog("settings: captured %@ (%@)", settingsPath, NSStringFromRect(content.bounds))
                        }
                    }
                    settings.window.close()
                }
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_FIND"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Find and Replace: the panel over the whole workbook finds
                // "1", steps to the second match, is captured to `-find.png`,
                // replaces one match and then all of them, then undoes.
                controller.showFindPanel(nil)
                if let panel = controller.findPanel {
                    panel.setTexts(find: "1", replace: "one")
                    panel.findAll(nil)
                    NSLog("find: %ld matches, first=%@ (%@ '%@')", panel.matches.count, panel.matches.first?.reference ?? "none",
                          panel.matches.first?.kindDescription ?? "", panel.matches.first?.contents ?? "")
                    panel.findNext(nil)
                    let current = controller.gridView.sheet ?? sheet
                    NSLog("find: after next, edit position %@!%ld,%ld", current.name, current.editPosition.column, current.editPosition.row)
                    if let content = panel.panel.contentView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let findPath = (path as NSString).deletingPathExtension + "-find.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: findPath))
                            NSLog("find: captured %@ (%@)", findPath, NSStringFromRect(content.bounds))
                        }
                        if ProcessInfo.processInfo.environment["GNM_DEBUG_LAYOUT"] != nil {
                            dump(view: content, depth: 0)
                        }
                    }
                    let before = panel.matches.count
                    panel.replaceCurrent(nil)
                    NSLog("find: after replacing one, %ld matches (was %ld) undo=%@", panel.matches.count, before,
                          sheet.workbook?.undoLabel ?? "nil")
                    panel.replaceAll(nil)
                    NSLog("find: after replacing all, %ld matches undo=%@", panel.matches.count, sheet.workbook?.undoLabel ?? "nil")
                    controller.gridView.undo(nil)
                    controller.gridView.undo(nil)
                    panel.panel.close()
                }
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_EDITOR"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet,
               let chart = sheet.sheetObjects.first(where: { $0.typeName == "SheetObjectGraph" }) {
                // The chart editor over the sheet's first chart: a title,
                // an inverted X axis, a red series line, the editor window
                // captured to `-editor.png`, then applied so the grid
                // capture shows the reconfigured chart.
                let grid = controller.gridView
                grid.select(objects: [chart])
                controller.editObject(chart)
                if let sheetWindow = controller.chartEditor {
                    let editor = sheetWindow.editor
                    let root = editor.root
                    NSLog("editor: root=%@ children=%@", root.name, root.children.map(\.name))
                    if let chartNode = root.children.first {
                        sheetWindow.select(node: chartNode)
                        NSLog("editor: chart addable=%@ properties=%ld", chartNode.addableRoles, chartNode.properties.count)
                        if let title = sheetWindow.addChild(role: "Title") {
                            sheetWindow.select(node: title)
                            sheetWindow.setText("Edited in Cocoa", forDimensionLabeled: "Text")
                            NSLog("editor: title %@ dims=%@", title.name, title.dimensions)
                        }
                        if let axis = chartNode.children.first(where: { $0.role == "X-Axis" }) {
                            sheetWindow.select(node: axis)
                            sheetWindow.setProperty(named: "invert-axis", to: NSNumber(value: true))
                            NSLog("editor: axis properties=%@", axis.properties.map { "\($0.name)=\($0.value ?? "nil")" })
                        }
                        if let plot = chartNode.children.first(where: { $0.role == "Plot" }),
                           let series = plot.children.first, let style = series.style {
                            style.lineAutomatic = false
                            style.lineColor = NSColor.systemRed.cgColor
                            style.lineWidth = 2.5
                            _ = editor.apply(style, to: series)
                            sheetWindow.select(node: series)
                            NSLog("editor: series %@ dims=%@ style line auto=%d", series.name, series.dimensions.map(\.text),
                                  series.style?.lineAutomatic == true ? 1 : 0)
                            // and the plot as columns (the Change Type… button's outcome)
                            if let column = PlotType.allTypes.first(where: { $0.family == "Column" && $0.engine == "GogBarColPlot" }) {
                                sheetWindow.select(node: plot)
                                let changed = sheetWindow.changePlotType(to: column)
                                NSLog("editor: plot now %@ with %ld series, old attached=%d", changed?.typeName ?? "nil",
                                      changed?.children.count ?? 0, plot.isAttached ? 1 : 0)
                            }
                        }
                    }
                    if let content = sheetWindow.window.contentView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let editorPath = (path as NSString).deletingPathExtension + "-editor.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: editorPath))
                            NSLog("editor: captured %@ (%@) changes=%ld", editorPath, NSStringFromRect(content.bounds), editor.changeCount)
                        }
                        if ProcessInfo.processInfo.environment["GNM_DEBUG_LAYOUT"] != nil {
                            dump(view: content, depth: 0)
                        }
                    }
                    sheetWindow.apply()
                    NSLog("editor: applied undo=%@ open=%d", sheet.workbook?.undoLabel ?? "nil", controller.chartEditor == nil ? 0 : 1)
                }
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_CHART"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // A clustered column chart from A1:D6 through the guru's
                // outcome, placed where the guru would put it, selected.
                let grid = controller.gridView
                let types = PlotType.allTypes
                let column = types.first { $0.family == "Column" && $0.engine == "GogBarColPlot" }
                NSLog("chart: %ld plot types, first family %@, column type %@ image=%ld bytes", types.count,
                      types.first?.family ?? "nil", column?.name ?? "nil", column?.sampleImageData?.count ?? 0)
                if let column {
                    sheet.selectRange(CellRange(start: CellCoordinate(column: 0, row: 0), end: CellCoordinate(column: 3, row: 5)),
                                      editPosition: CellCoordinate(column: 0, row: 0))
                    let frame = grid.suggestedFrameForNewObject(size: sheet.defaultChartSize)
                    do {
                        let object = try sheet.insertChart(column, seriesLayout: .auto, sharedAbscissa: false, frame: frame)
                        grid.select(objects: [object])
                        NSLog("chart: inserted %@ at %@ undo=%@", object.typeName, NSStringFromRect(object.frame), sheet.workbook?.undoLabel ?? "nil")
                    } catch {
                        NSLog("chart: insert failed: %@", error.localizedDescription)
                    }
                }
                // The guru sheet itself, captured to `-guru.png`, then dismissed.
                let guru = ChartGuru()
                guru.run(in: window) { _ in }
                if let content = guru.window.contentView {
                    content.layoutSubtreeIfNeeded()
                    if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                        content.cacheDisplay(in: content.bounds, to: rep)
                        let guruPath = (path as NSString).deletingPathExtension + "-guru.png"
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: guruPath))
                        NSLog("chart: guru captured %@ (%@)", guruPath, NSStringFromRect(content.bounds))
                    }
                    if ProcessInfo.processInfo.environment["GNM_DEBUG_LAYOUT"] != nil {
                        dump(view: content, depth: 0)
                    }
                }
                guru.cancel()
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_SHEETS"] != nil,
               let controller = window.windowController as? WorkbookWindowController {
                // Sheet management through the controller's actions.
                let workbook = controller.workbook
                let names = { workbook.sheets.map(\.name).joined(separator: ",") }
                controller.appendSheet(nil)
                controller.insertSheet(nil)
                NSLog("sheets: after append+insert %@ current=%@ undo=%@", names(), workbook.currentSheet?.name ?? "nil",
                      workbook.undoLabel ?? "nil")
                controller.moveSheetRight(nil)
                controller.duplicateSheet(nil)
                NSLog("sheets: after move+duplicate %@ current=%@", names(), workbook.currentSheet?.name ?? "nil")
                controller.removeSheet(nil)
                try? workbook.rename(workbook.currentSheet!, to: "Renamed")
                NSLog("sheets: after remove+rename %@ current=%@", names(), workbook.currentSheet?.name ?? "nil")
                DispatchQueue.main.async {   // the tab strip rebuilds after a removal on the next turn
                    NSLog("sheets: tabs=%ld", controller.tabCount)
                }
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_MANAGE"] != nil,
               let controller = window.windowController as? WorkbookWindowController {
                // Manage Sheets: a sheet appended and renamed through the
                // table, the first locked and hidden, the list sorted, one
                // step undone, the window captured to `-manage.png`.
                let workbook = controller.workbook
                let names = { workbook.sheets.map { "\($0.name)\($0.isProtected ? "🔒" : "")\($0.isVisible ? "" : "(hidden)")" }.joined(separator: ",") }
                controller.manageSheets(nil)
                if let dialog = controller.manageSheetsDialog {
                    NSLog("manage: %ld rows, row %ld chosen", dialog.sheets.count, dialog.selectedRow)
                    dialog.append(nil)
                    dialog.setName("Zulu", forRow: dialog.selectedRow)
                    dialog.toggleLock(row: 0)
                    dialog.toggleVisible(row: 0)
                    dialog.setTabColors(background: NSColor.systemTeal.cgColor, text: nil, of: dialog.sheets[0])
                    NSLog("manage: after append, rename, lock, hide, color: %@ undo=%@", names(), workbook.undoLabel ?? "nil")
                    dialog.sortDescending(nil)
                    NSLog("manage: sorted descending: %@", names())
                    dialog.undo(nil)
                    NSLog("manage: undone: %@ undo=%@", names(), workbook.undoLabel ?? "nil")
                    dialog.setName("", forRow: dialog.sheets.count - 1)
                    NSLog("manage: empty name refused: %@", workbook.sheets.last?.name ?? "nil")
                    if let content = dialog.window.contentView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let managePath = (path as NSString).deletingPathExtension + "-manage.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: managePath))
                            NSLog("manage: captured %@ (%@)", managePath, NSStringFromRect(content.bounds))
                        }
                    }
                    dialog.close(nil)
                    NSLog("manage: closed, dialog=%@ tabs=%ld", controller.manageSheetsDialog == nil ? "nil" : "open", controller.tabCount)
                }
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_PLUGINS"] != nil,
               let controller = window.windowController as? WorkbookWindowController {
                // Plugin Manager: the time series plugin activated through
                // its checkbox and deactivated again, a directory added and
                // removed, a rescan, the window captured to `-plugins.png`.
                controller.pluginManager(nil)
                if let dialog = controller.pluginManagerDialog {
                    let identifier = "Gnumeric_fnTimeSeriesAnalysis"
                    NSLog("plugins: %ld listed, %ld active", dialog.plugins.count, dialog.plugins.filter(\.isActive).count)
                    dialog.select(pluginWithIdentifier: identifier)
                    if let row = dialog.plugins.firstIndex(where: { $0.identifier == identifier }) {
                        let before = dialog.plugins[row].isActive
                        dialog.toggleActive(row: row)
                        let after = dialog.plugins[row].isActive
                        dialog.toggleActive(row: row)
                        NSLog("plugins: TSA %@ -> %@ -> %@", before ? "active" : "inactive", after ? "active" : "inactive",
                              dialog.plugins[row].isActive ? "active" : "inactive")
                        dialog.toggleActive(row: row)
                    }
                    dialog.addDirectory("/tmp/no-plugins-here")   // what the Add… panel would hand over
                    NSLog("plugins: %ld directories after add, extra=%@", dialog.directories.count,
                          Engine.shared?.extraPluginDirectories.joined(separator: ",") ?? "nil")
                    dialog.rescan(nil)
                    if let content = dialog.window.contentView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let pluginsPath = (path as NSString).deletingPathExtension + "-plugins.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: pluginsPath))
                            NSLog("plugins: captured %@ (%@)", pluginsPath, NSStringFromRect(content.bounds))
                        }
                    }
                    Engine.shared?.extraPluginDirectories = Engine.shared?.extraPluginDirectories.filter { $0 != "/tmp/no-plugins-here" } ?? []
                    NSLog("plugins: extra after remove=%@", Engine.shared?.extraPluginDirectories.joined(separator: ",") ?? "nil")
                    dialog.close(nil)
                    NSLog("plugins: closed, dialog=%@", controller.pluginManagerDialog == nil ? "nil" : "open")
                }
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_SCENARIO"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Scenarios: A1*A2 in B1; "Base" and "High" added through the
                // dialog, "High" shown in the manager, a summary with B1 as
                // the result cell, the manager captured to `-scenarios.png`,
                // OK; then a simulation of D1+D2 with random inputs.
                do {
                    try sheet.setText("10", atColumn: 0, row: 0, autocorrect: false)
                    try sheet.setText("5", atColumn: 0, row: 1, autocorrect: false)
                    try sheet.setText("=A1*A2", atColumn: 1, row: 0, autocorrect: false)
                } catch {
                    NSLog("scenario: data failed: %@", error.localizedDescription)
                }
                ScenarioAddDialog.headlessDriver = { dialog in
                    dialog.nameField.stringValue = "Base"
                    dialog.cellsField.stringValue = "A1:A2"
                    dialog.commentField.stringValue = "as now"
                    return true
                }
                controller.scenarioAdd(nil)
                try? sheet.setText("12", atColumn: 0, row: 0, autocorrect: false)
                try? sheet.setText("8", atColumn: 0, row: 1, autocorrect: false)
                ScenarioAddDialog.headlessDriver = { dialog in
                    dialog.nameField.stringValue = "High"
                    dialog.cellsField.stringValue = "A1:A2"
                    return true
                }
                controller.scenarioAdd(nil)
                ScenarioAddDialog.headlessDriver = nil
                try? sheet.setText("10", atColumn: 0, row: 0, autocorrect: false)
                try? sheet.setText("5", atColumn: 0, row: 1, autocorrect: false)
                NSLog("scenario: %@ added, undo=%@", sheet.scenarios.map(\.name).joined(separator: ","), sheet.workbook?.undoLabel ?? "nil")
                controller.scenarioView(nil)
                if let dialog = controller.scenarioManagerDialog {
                    // the summary first: as in the GTK it restores the sheet
                    // and forgets the shown scenario
                    dialog.setResultCellsForTesting("B1")
                    dialog.summary(nil)
                    if let report = dialog.lastSummarySheet {
                        NSLog("scenario: summary '%@' row 6: %@ %@ %@ %@", report.name,
                              report.displayTextOfCell(atColumn: 0, row: 6) ?? "nil", report.displayTextOfCell(atColumn: 1, row: 6) ?? "nil",
                              report.displayTextOfCell(atColumn: 2, row: 6) ?? "nil", report.displayTextOfCell(atColumn: 3, row: 6) ?? "nil")
                    }
                    dialog.select(row: 1)
                    dialog.show(nil)
                    NSLog("scenario: shown %@ B1='%@'", dialog.manager.shownScenario?.name ?? "nil", sheet.displayTextOfCell(atColumn: 1, row: 0) ?? "nil")
                    if let content = dialog.window.contentView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let scenariosPath = (path as NSString).deletingPathExtension + "-scenarios.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: scenariosPath))
                            NSLog("scenario: captured %@ (%@)", scenariosPath, NSStringFromRect(content.bounds))
                        }
                    }
                    dialog.finish(nil)
                    NSLog("scenario: after OK B1='%@' undo=%@ sheets=%ld dialog=%@", sheet.displayTextOfCell(atColumn: 1, row: 0) ?? "nil",
                          sheet.workbook?.undoLabel ?? "nil", sheet.workbook?.sheets.count ?? 0, controller.scenarioManagerDialog == nil ? "nil" : "open")
                    sheet.workbook?.select(sheet)
                }
                do {
                    try sheet.setText("=RAND()", atColumn: 3, row: 0, autocorrect: false)
                    try sheet.setText("=10*RAND()", atColumn: 3, row: 1, autocorrect: false)
                    try sheet.setText("=D1+D2", atColumn: 4, row: 0, autocorrect: false)
                } catch {
                    NSLog("scenario: simulation data failed: %@", error.localizedDescription)
                }
                SimulationDialog.headlessDriver = { dialog in
                    dialog.inputsField.stringValue = "D1:D2"
                    dialog.outputsField.stringValue = "E1"
                    dialog.iterationsField.stringValue = "100"
                    dialog.lastRoundField.stringValue = "2"
                    return true
                }
                controller.simulation(nil)
                SimulationDialog.headlessDriver = nil
                NSLog("scenario: simulation results:\n%@", SimulationDialog.lastResultsText ?? "nil")
                NSLog("scenario: sheets after simulation %@", sheet.workbook?.sheets.map(\.name).joined(separator: ",") ?? "nil")
                sheet.workbook?.select(sheet)
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_AUTOFORMAT"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // AutoFormat: a 5x5 block of numbers, the dialog's second
                // General template with its top edge off, captured to
                // `-autoformat.png`, applied by OK, and left in the capture.
                for r in 0..<5 {
                    for c in 0..<5 { try? sheet.setText("\(r * 5 + c)", atColumn: c, row: r, autocorrect: false) }
                }
                sheet.selectRange(CellRange(start: CellCoordinate(column: 0, row: 0), end: CellCoordinate(column: 4, row: 4)),
                                  editPosition: CellCoordinate(column: 0, row: 0))
                controller.autoFormat(nil)
                if let dialog = controller.autoFormatDialog {
                    NSLog("autoformat: %ld categories (%@), %ld templates in the first", dialog.categories.count,
                          dialog.categories.map(\.name).joined(separator: ","), dialog.templates.count)
                    dialog.selectCategory(named: "General")
                    dialog.select(row: min(1, dialog.templates.count - 1))
                    dialog.setPart(\.bordersTopEdge, on: false)
                    NSLog("autoformat: chosen '%@' by %@, top edge %d", dialog.selectedTemplate?.name ?? "nil", dialog.selectedTemplate?.author ?? "nil",
                          dialog.selectedTemplate?.bordersTopEdge == true ? 1 : 0)
                    if let content = dialog.window.contentView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let autoformatPath = (path as NSString).deletingPathExtension + "-autoformat.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: autoformatPath))
                            NSLog("autoformat: captured %@ (%@)", autoformatPath, NSStringFromRect(content.bounds))
                        }
                    }
                    dialog.apply(nil)
                    NSLog("autoformat: applied, undo=%@ B1 bold=%@ fill=%@ dialog=%@", sheet.workbook?.undoLabel ?? "nil",
                          sheet.formatOfCell(atColumn: 1, row: 0).bold ?? -1, sheet.formatOfCell(atColumn: 1, row: 0).fillsBackground ?? -1,
                          controller.autoFormatDialog == nil ? "nil" : "open")
                }
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_WIDGET"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Widgets: a button inserted at B2 and configured through
                // its dialog (label, link), a scrollbar at D2 configured
                // (range, horizontal), both left in the window capture.
                sheet.selectCell(atColumn: 1, row: 1)
                controller.insertButton(nil)
                if let button = controller.gridView.selectedObjects.first {
                    NSLog("widget: inserted %@ kind %ld undo=%@", button.typeName, button.widgetKind.rawValue, sheet.workbook?.undoLabel ?? "nil")
                    WidgetDialog.headlessDriver = { dialog in
                        dialog.labelField.stringValue = "Go"
                        dialog.linkField.stringValue = "C1"
                        return true
                    }
                    controller.editObject(button)
                    WidgetDialog.headlessDriver = nil
                    let settings = sheet.widgetSettings(of: button)
                    NSLog("widget: button label '%@' link '%@' undo=%@", settings?.label ?? "nil", settings?.linkText ?? "nil", sheet.workbook?.undoLabel ?? "nil")
                }
                sheet.selectCell(atColumn: 3, row: 1)
                controller.insertScrollbar(nil)
                if let scrollbar = controller.gridView.selectedObjects.first {
                    WidgetDialog.headlessDriver = { dialog in
                        dialog.minimumField.stringValue = "0"
                        dialog.maximumField.stringValue = "50"
                        dialog.horizontalBox.state = .on
                        dialog.linkField.stringValue = "C2"
                        return true
                    }
                    controller.editObject(scrollbar)
                    WidgetDialog.headlessDriver = nil
                    let settings = sheet.widgetSettings(of: scrollbar)
                    let minimum: Int = settings?.minimum ?? -1
                    let maximum: Int = settings?.maximum ?? -1
                    let horizontal: Int = settings?.horizontal == true ? 1 : 0
                    let link: String = settings?.linkText ?? "nil"
                    let undo: String = sheet.workbook?.undoLabel ?? "nil"
                    NSLog("widget: scrollbar %ld..%ld horizontal %d link '%@' undo=%@", minimum, maximum, horizontal, link, undo)
                }
                NSLog("widget: %ld objects on the sheet", sheet.sheetObjects.count)
                controller.gridView.select(objects: [])
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_TOOLBAR"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // The toolbar: 1234.5678 in C3 made bold, centered, a
                // percentage with one more decimal through the buttons, the
                // font size 14 through the combo, AutoSum in C5, zoom 150%.
                try? sheet.setText("1234.5678", atColumn: 2, row: 2, autocorrect: false)
                sheet.selectCell(atColumn: 2, row: 2)
                NSLog("toolbar: %ld items; state %@", window.toolbar?.items.count ?? 0, controller.toolbarStateForTesting)
                for identifier in ["bold", "alignCenter", "percent", "morePrecision"] { controller.performToolbarItemForTesting(identifier) }
                let format = sheet.formatOfCell(atColumn: 2, row: 2)
                NSLog("toolbar: C3 bold=%@ align=%@ format='%@' shows '%@' undo=%@", format.bold ?? -1, format.horizontalAlignment ?? -1,
                      format.numberFormat ?? "nil", sheet.displayTextOfCell(atColumn: 2, row: 2) ?? "nil", sheet.workbook?.undoLabel ?? "nil")
                NSLog("toolbar: state %@", controller.toolbarStateForTesting)
                if let combo = window.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "fontSize" })?.view as? NSComboBox {
                    combo.stringValue = "14"
                    controller.fontSizeChosen(combo)
                    NSLog("toolbar: font size %@", sheet.formatOfCell(atColumn: 2, row: 2).fontSize ?? -1)
                }
                sheet.selectCell(atColumn: 2, row: 4)
                controller.performToolbarItemForTesting("autosum")
                NSLog("toolbar: autosum editing=%d text='%@'", controller.gridView.isEditing ? 1 : 0, controller.gridView.editorTextForTesting)
                controller.gridView.cancelEditing()
                if let zoom = window.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "zoom" })?.view as? NSPopUpButton {
                    zoom.selectItem(withTitle: "150%")
                    controller.zoomChosen(zoom)
                    NSLog("toolbar: zoom %g state %@", sheet.zoomFactor, controller.toolbarStateForTesting)
                    zoom.selectItem(withTitle: "100%")
                    controller.zoomChosen(zoom)
                }
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_DRAG"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Drag and drop: A1:B1 dragged to A4 (moved, the formula
                // follows), then Option-dragged to A7 (copied); a PNG file
                // dropped at D2; the second tab dragged before the first.
                do {
                    try sheet.setText("5", atColumn: 0, row: 0, autocorrect: false)
                    try sheet.setText("=A1*3", atColumn: 1, row: 0, autocorrect: false)
                } catch { NSLog("drag: data failed: %@", error.localizedDescription) }
                sheet.selectRange(CellRange(start: CellCoordinate(column: 0, row: 0), end: CellCoordinate(column: 1, row: 0)),
                                  editPosition: CellCoordinate(column: 0, row: 0))
                controller.gridView.dropSelectionForTesting(at: CellCoordinate(column: 0, row: 3), copying: false)
                NSLog("drag: moved A4='%@' B4='%@' A1='%@' selection=%ld,%ld undo=%@", sheet.displayTextOfCell(atColumn: 0, row: 3) ?? "nil",
                      sheet.enteredTextOfCell(atColumn: 1, row: 3) ?? "nil", sheet.displayTextOfCell(atColumn: 0, row: 0) ?? "",
                      sheet.selectedRange.start.column, sheet.selectedRange.start.row, sheet.workbook?.undoLabel ?? "nil")
                controller.gridView.dropSelectionForTesting(at: CellCoordinate(column: 0, row: 6), copying: true)
                NSLog("drag: copied A7='%@' B7='%@' A4='%@'", sheet.displayTextOfCell(atColumn: 0, row: 6) ?? "nil",
                      sheet.enteredTextOfCell(atColumn: 1, row: 6) ?? "nil", sheet.displayTextOfCell(atColumn: 0, row: 3) ?? "nil")
                let pngPath = (path as NSString).deletingPathExtension + "-drop.png"
                let image = NSImage(size: NSSize(width: 40, height: 30), flipped: false) { rect in
                    NSColor.systemPurple.setFill()
                    rect.fill()
                    return true
                }
                if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: pngPath))
                    let frame = sheet.frameOfCell(atColumn: 3, row: 1)
                    controller.gridView.handleDroppedFiles([URL(fileURLWithPath: pngPath)], at: frame.origin)
                    NSLog("drag: dropped image -> %ld objects, first %@", sheet.sheetObjects.count, sheet.sheetObjects.first?.typeName ?? "nil")
                }
                controller.appendSheet(nil)
                sheet.workbook?.select(sheet)
                let before = sheet.workbook?.sheets.map(\.name).joined(separator: ",") ?? ""
                controller.reorderTab(from: 1, to: 0)
                NSLog("drag: tabs %@ -> %@ undo=%@", before, sheet.workbook?.sheets.map(\.name).joined(separator: ",") ?? "", sheet.workbook?.undoLabel ?? "nil")
                sheet.workbook?.select(sheet)
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_FREEZE"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Freeze at C4 through the View menu action, then scroll
                // well into the sheet: rows 1-3 and columns A-B must stay.
                let grid = controller.gridView
                sheet.selectCell(atColumn: 2, row: 3)
                grid.freezePanes(nil)
                NSLog("freeze: frozen=%d unfrozen=%ld,%ld panes=%@", sheet.isFrozen ? 1 : 0,
                      sheet.unfrozenTopLeft.column, sheet.unfrozenTopLeft.row,
                      grid.panes.map { NSStringFromRect(NSRect(origin: $0.origin, size: NSSize(width: $0.width, height: $0.height))) } ?? "nil")
                grid.scroll(NSPoint(x: 300, y: 400))
                grid.enclosingScrollView?.reflectScrolledClipView(grid.enclosingScrollView!.contentView)
                sheet.selectCell(atColumn: 4, row: 30)
                NSLog("freeze: visible=%@ scrolling=%@", NSStringFromRect(grid.visibleRect), NSStringFromRect(grid.scrollingVisibleRect))
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_FORMAT"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // The dialog's model and view, driven without clicks: format
                // B5:B7 bold, centered, two decimals, yellow fill, thick bottom border.
                sheet.selectRange(CellRange(start: CellCoordinate(column: 1, row: 4), end: CellCoordinate(column: 1, row: 6)),
                                  editPosition: CellCoordinate(column: 1, row: 4))
                let model = FormatCellsModel(format: sheet.formatOfSelection, isMultiCell: true)
                let hosting = NSHostingController(rootView: FormatCellsView(model: model) { _ in })
                hosting.view.frame = NSRect(x: 0, y: 0, width: 520, height: 420)
                hosting.view.layoutSubtreeIfNeeded()
                NSLog("format model: category=%@ code=%@ mixed=%d touched=%d",
                      model.category.rawValue, model.numberFormatCode, model.mixed.count, model.touched.count)
                model.category = .number
                model.decimals = 2
                model.thousandsSeparator = true
                model.bold = true
                model.horizontalAlignment = .center
                model.fillsBackground = true
                model.backgroundColor = .yellow
                model.setBorder(.thick, edge: .bottom)
                do {
                    try sheet.apply(model.changes())
                } catch {
                    NSLog("format apply failed: %@", error.localizedDescription)
                }
                NSLog("format applied: B5=%@ touched=%d undo=%@", sheet.displayTextOfCell(atColumn: 1, row: 4) ?? "nil",
                      model.touched.count, sheet.workbook?.undoLabel ?? "nil")
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
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            if ProcessInfo.processInfo.environment["GNM_DEBUG_LAYOUT"] != nil {
                dump(view: view, depth: 0)
            }
            // The PNG at `path` is the grid view's visible area: the part the
            // engine draws, and what golden-image tests compare.  A capture
            // of the whole content view goes next to it (`-window.png`); it
            // matched the screen when the NSRulerView headers blanked the
            // scroll view on macOS 26 (2026-10-11), so it is the check that
            // the grid actually reaches the window.  SwiftUI-hosted controls
            // (text fields, the tab control) may come out incomplete in it.
            if let grid = findView(of: "GridView", in: view),
               let gridRep = grid.bitmapImageRepForCachingDisplay(in: grid.visibleRect) {
                grid.cacheDisplay(in: grid.visibleRect, to: gridRep)
                try? gridRep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                NSLog("snapshot written to %@", path)
            }
            if ProcessInfo.processInfo.environment["GNM_DEBUG_LAYOUT"] != nil {
                for name in ["RowHeaderView", "ColumnHeaderView"] {
                    if let header = findView(of: name, in: view),
                       let rep = header.bitmapImageRepForCachingDisplay(in: header.bounds) {
                        header.cacheDisplay(in: header.bounds, to: rep)
                        let headerPath = (path as NSString).deletingPathExtension + "-\(name).png"
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: headerPath))
                    }
                }
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
            // The layer tree as Core Animation composites it (`-layers.png`):
            // the closest thing to the screen without a screen capture.
            if let layer = view.layer, let layerRep = view.bitmapImageRepForCachingDisplay(in: view.bounds),
               let context = NSGraphicsContext(bitmapImageRep: layerRep) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                layer.render(in: context.cgContext)
                NSGraphicsContext.restoreGraphicsState()
                let layersPath = (path as NSString).deletingPathExtension + "-layers.png"
                try? layerRep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: layersPath))
            }
        }
    }
}
