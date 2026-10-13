import AppKit
import SwiftUI
import GnmCocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var engine: Engine?
    private(set) var settings: PreferencesWindowController?

    /// File → Import Text… (⇧⌘O): any text file through the import
    /// assistant, whatever its extension (Open… takes `.csv` and `.tsv`
    /// with the engine's guessed options).
    @objc func importText(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = Localization.title("Import Text")
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
    @objc func showSettings(_ sender: Any?) { showSettings(tab: nil) }

    /// Tools → Auto Correct… (cb_tools_autocorrect): the Settings window
    /// on the tab with the Auto Correct section.
    @objc func autoCorrectSettings(_ sender: Any?) { showSettings(tab: "Editing") }

    func showSettings(tab: String?) {
        guard let engine else { return }
        if settings == nil {
            settings = PreferencesWindowController(preferences: engine.preferences)
        }
        settings?.show(tab: tab)
    }

    // MARK: Help

    /// The GTK Help items (cb_help_docs, cb_help_web, cb_help_irc,
    /// cb_help_bug): the manual, the website, the IRC channel, and the
    /// issue tracker open in the browser (or the IRC client, when one
    /// handles irc: links).
    static let helpURLs: [String: String] = [
        "docs": "https://help.gnome.org/users/gnumeric/stable/",
        "web": "https://www.gnumeric.org/",
        "irc": "irc://irc.gnome.org/gnumeric",
        "bug": "https://gitlab.gnome.org/GNOME/gnumeric/issues",
    ]

    private func openHelp(_ key: String) {
        guard let string = Self.helpURLs[key], let url = URL(string: string) else { return }
        if ProcessInfo.processInfo.environment["GNM_SNAPSHOT"] != nil {
            NSLog("help: would open %@", url.absoluteString)
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc func helpDocs(_ sender: Any?) { openHelp("docs") }
    @objc func helpWeb(_ sender: Any?) { openHelp("web") }
    @objc func helpIRC(_ sender: Any?) { openHelp("irc") }
    @objc func helpBug(_ sender: Any?) { openHelp("bug") }

    /// The index of the bundled libraries' licenses that scripts/bundle.sh
    /// writes (Resources/licenses/THIRD-PARTY.txt); nil in a development
    /// build, which links Homebrew's libraries in place.
    static var licensesIndexURL: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("licenses/THIRD-PARTY.txt"),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Help → Third-Party Licenses: the index opens in the text editor
    /// (the license texts sit in the directories beside it).
    @objc func helpLicenses(_ sender: Any?) {
        guard let url = Self.licensesIndexURL else { return }
        if ProcessInfo.processInfo.environment["GNM_SNAPSHOT"] != nil {
            NSLog("help: would open %@", url.path)
            return
        }
        NSWorkspace.shared.open(url)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == Selector(("helpLicenses:")) {
            return Self.licensesIndexURL != nil
        }
        return true
    }

    /// Help → Functions (dialog_function_select_help): the catalog to read.
    @objc func helpFunctions(_ sender: Any?) {
        guard let engine else { return }
        let dialog = FunctionSelectorDialog(engine: engine, helpOnly: true)
        if let window = NSApp.keyWindow, window.windowController is WorkbookWindowController, window.attachedSheet == nil {
            dialog.present(in: window) { _ in }
        } else {
            dialog.runModal()
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        do {
            let engine = try Engine.start(configuration: EngineLocator.configuration())
            // The menu after the engine: its titles come through the
            // engine's catalogs (Localization).
            self.engine = engine
            NSApp.mainMenu = MainMenu.build()
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

    /// The engine carried inside the bundle (scripts/bundle.sh): nil for
    /// a development build, which runs against the prefix.
    static var bundledEngineDirectory: URL? {
        guard ProcessInfo.processInfo.environment["GNM_PREFIX"] == nil,
              let resources = Bundle.main.resourceURL else { return nil }
        let engine = resources.appendingPathComponent("gnumeric", isDirectory: true)
        return FileManager.default.fileExists(atPath: engine.appendingPathComponent("lib/plugins").path) ? engine : nil
    }

    static var isBundled: Bool { bundledEngineDirectory != nil }

    /// The engine's messages (and its number parsing) follow the process
    /// locale, which a Finder launch leaves at "C": take macOS's preferred
    /// languages, unless the environment names a locale already (a
    /// Terminal launch, the headless runs).  LANGUAGE lists the languages
    /// for the catalogs (gettext's fallback chain); LANG must name a
    /// locale macOS has.
    static func exportLocale() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LC_ALL"] == nil, environment["LANG"] == nil, environment["LC_MESSAGES"] == nil else { return }
        let languages = Locale.preferredLanguages.map { Locale(identifier: $0) }
        let codes: [String] = languages.compactMap { $0.language.languageCode?.identifier }
        guard let first = languages.first, let code = codes.first else { return }
        let region = first.region?.identifier ?? Locale.current.region?.identifier ?? ""
        let candidates = ["\(code)_\(region).UTF-8", "\(code).UTF-8"]
        guard let name = candidates.first(where: { FileManager.default.fileExists(atPath: "/usr/share/locale/\($0)") }) else { return }
        setenv("LANG", name, 1)
        setenv("LANGUAGE", codes.joined(separator: ":"), 1)
    }

    static func configuration() -> EngineConfiguration {
        exportLocale()
        let configuration = EngineConfiguration()
        configuration.programName = "gnumeric-cocoa"
        // GSettings persists through NSUserDefaults under the bundle
        // identifier (docs/decisions.md ADR-010); GNM_PERSIST_PREFS=0 keeps a
        // run from touching ~/Library/Preferences.
        configuration.persistsPreferences = ProcessInfo.processInfo.environment["GNM_PERSIST_PREFS"] != "0"
        if let engine = bundledEngineDirectory, let resources = Bundle.main.resourceURL {
            // Contents/Resources: gnumeric/lib (plugins), gnumeric/share
            // (templates), goffice/plugins, glib-2.0/schemas, gdk-pixbuf
            // (loaders and their cache with names relative to the module dir).
            configuration.libraryDirectory = engine.appendingPathComponent("lib").path
            configuration.dataDirectory = engine.appendingPathComponent("share").path
            let locale = engine.appendingPathComponent("locale")
            if FileManager.default.fileExists(atPath: locale.path) { configuration.localeDirectory = locale.path }
            configuration.settingsSchemaDirectory = resources.appendingPathComponent("glib-2.0/schemas").path
            configuration.extraPluginDirectories = [resources.appendingPathComponent("goffice/plugins").path]
            let loaders = resources.appendingPathComponent("gdk-pixbuf/loaders")
            if FileManager.default.fileExists(atPath: loaders.path) {
                setenv("GDK_PIXBUF_MODULEDIR", loaders.path, 1)
                setenv("GDK_PIXBUF_MODULE_FILE", resources.appendingPathComponent("gdk-pixbuf/loaders.cache").path, 1)
            }
        } else if let prefix {
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
                    // a text color on the last sheet: its tab carries the name as an image
                    dialog.setTabColors(background: NSColor.systemYellow.cgColor, text: NSColor.systemRed.cgColor, of: dialog.sheets[dialog.sheets.count - 1])
                    let tabTexts: String = (0..<controller.tabCount).map { controller.tabDescriptionForTesting($0) }.joined(separator: "; ")
                    NSLog("manage: tabs %@", tabTexts)
                    controller.toggleStatusBar(nil)
                    let hidden: Bool = !controller.statusBarIsShown
                    controller.toggleStatusBar(nil)
                    NSLog("manage: status bar hidden=%d shown again=%d", hidden ? 1 : 0, controller.statusBarIsShown ? 1 : 0)
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
                // the format extras: indent, superscript, an outside border, red text, a yellow fill
                sheet.selectCell(atColumn: 2, row: 2)
                for identifier in ["indentMore", "superscript"] { controller.performToolbarItemForTesting(identifier) }
                if let popUp = window.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "borders" })?.view as? NSPopUpButton,
                   let outside = popUp.menu?.items.first(where: { $0.title == "Outside" }) {
                    controller.borderPresetChosen(outside)
                }
                if let well = window.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "textColor" })?.view as? NSColorWell {
                    well.color = .systemRed
                    controller.textColorChosen(well)
                }
                if let well = window.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "fillColor" })?.view as? NSColorWell {
                    well.color = .systemYellow
                    controller.fillColorChosen(well)
                }
                let extras = sheet.formatOfSelection
                NSLog("toolbar: C3 indent=%ld script=%ld top border=%@ text color=%@ fill=%@ state %@", sheet.indentOfSelection, sheet.fontScriptOfSelection.rawValue,
                      extras.borderStyle(edge: .top) ?? -1, extras.textColor == nil ? "nil" : "set", extras.fillsBackground ?? -1, controller.toolbarStateForTesting)
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
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_MULTILINE"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Multi-line editing: "first", Option+Return, "second" typed in
                // A1 through the field editor; the editor grows, the entry
                // keeps the line break, the formula bar shows two lines.
                func key(_ code: UInt16, _ character: String, _ flags: NSEvent.ModifierFlags) {
                    if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: window.windowNumber, context: nil, characters: character,
                                                   charactersIgnoringModifiers: character, isARepeat: false, keyCode: code) {
                        window.sendEvent(event)
                    }
                }
                sheet.selectCell(atColumn: 0, row: 0)
                controller.gridView.beginEditing(initialText: "first")
                let before = controller.gridView.editorFrameForTesting.height
                key(36, "\r", [.option])
                for ch in "second" { key(0, String(ch), []) }
                let text = controller.gridView.editorTextForTesting
                NSLog("multiline: editor text %@ lines=%ld height %.0f -> %.0f", text.replacingOccurrences(of: "\n", with: "⏎"),
                      text.components(separatedBy: "\n").count, before, controller.gridView.editorFrameForTesting.height)
                key(36, "\r", [])   // Return commits
                NSLog("multiline: A1 entered '%@' display lines=%ld editing=%d", (sheet.enteredTextOfCell(atColumn: 0, row: 0) ?? "nil").replacingOccurrences(of: "\n", with: "⏎"),
                      (sheet.displayTextOfCell(atColumn: 0, row: 0) ?? "").components(separatedBy: "\n").count, controller.gridView.isEditing ? 1 : 0)
                sheet.selectCell(atColumn: 0, row: 0)
                NSLog("multiline: formula bar height %.0f for A1, %.0f for B1", controller.formulaBarHeightForTesting, { sheet.selectCell(atColumn: 1, row: 0); return controller.formulaBarHeightForTesting }())
                sheet.selectCell(atColumn: 0, row: 0)
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_PROPS"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Select → Depends and Inputs on a small chain; Format →
                // Workbook… hides the sheet tabs (left hidden in the window
                // capture); File → Properties… sets a title and author.
                do {
                    try sheet.setText("10", atColumn: 0, row: 0, autocorrect: false)
                    try sheet.setText("=A1*2", atColumn: 1, row: 0, autocorrect: false)
                    try sheet.setText("=B1+1", atColumn: 2, row: 0, autocorrect: false)
                } catch { NSLog("props: data failed: %@", error.localizedDescription) }
                sheet.selectCell(atColumn: 0, row: 0)
                controller.selectDependents(nil)
                let depends = sheet.selectedRange
                sheet.selectCell(atColumn: 2, row: 0)
                controller.selectInputs(nil)
                let inputs = sheet.selectedRange
                NSLog("props: depends of A1 -> %ld,%ld; inputs of C1 -> %ld,%ld", depends.start.column, depends.start.row, inputs.start.column, inputs.start.row)
                WorkbookAttributesDialog.headlessDriver = { dialog in
                    dialog.sheetTabs.state = .off
                    dialog.protected.state = .on
                    return true
                }
                controller.formatWorkbook(nil)
                WorkbookAttributesDialog.headlessDriver = nil
                NSLog("props: tabs shown %d protected %d modified %d", controller.workbook.showsSheetTabs ? 1 : 0,
                      controller.workbook.isProtected ? 1 : 0, controller.workbook.isModified ? 1 : 0)
                DocumentPropertiesDialog.headlessDriver = { dialog in
                    dialog.setValue("Quarterly figures", for: "dc:title")
                    dialog.setValue("Henry", for: "dc:creator")
                    let statistics: String = dialog.statistics.map { "\($0.0)=\($0.1)" }.joined(separator: "; ")
                    NSLog("props: statistics %@", statistics)
                    dialog.setCalculation(DocumentPropertiesDialog.Calculation(automatic: false, iterates: true, maximum: 50, tolerance: 0.01))
                    dialog.stageProperty(name: "project", type: .string, value: "alpha")
                    dialog.stageProperty(name: "runs", type: .integer, value: "12")
                    let staged: String = dialog.propertyRowsForTesting.joined(separator: "; ")
                    NSLog("props: staged rows %@", staged)
                    return true
                }
                controller.documentProperties(nil)
                DocumentPropertiesDialog.headlessDriver = nil
                NSLog("props: title '%@' author '%@' undo=%@", controller.workbook.documentProperties["dc:title"] ?? "nil",
                      controller.workbook.documentProperties["dc:creator"] ?? "nil", controller.workbook.undoLabel ?? "nil")
                let calc: String = "automatic=\(controller.workbook.recalculatesAutomatically) iterates=\(controller.workbook.iterationEnabled) max=\(controller.workbook.iterationMaximum) tol=\(controller.workbook.iterationTolerance)"
                NSLog("props: calculation %@", calc)
                let custom: String = controller.workbook.allDocumentProperties.filter { ["project", "runs"].contains($0.name) }.map { "\($0.name)=\($0.value)/\($0.type.rawValue)" }.joined(separator: " ")
                NSLog("props: custom %@ undo=%@", custom, controller.workbook.undoLabel ?? "nil")
                controller.workbook.recalculatesAutomatically = true
                controller.workbook.iterationEnabled = false
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_WIDGETACT"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Widgets that act: a checkbox linked to C1 clicked, a
                // horizontal scrollbar over 0…50 linked to C2 clicked at
                // four fifths, a list over A1:A3 with its choice in C3
                // clicked on its second row; all left in the window capture.
                for (row, color) in ["red", "green", "blue"].enumerated() { try? sheet.setText(color, atColumn: 0, row: row, autocorrect: false) }
                @MainActor func make(_ kind: WidgetSettings.Kind, _ frame: CGRect, _ configure: (WidgetSettings) -> Void) -> SheetObject? {
                    guard let object = try? sheet.insertWidget(ofKind: kind, frame: frame), let settings = sheet.widgetSettings(of: object) else { return nil }
                    configure(settings)
                    try? sheet.applyWidgetSettings(settings, to: object)
                    return object
                }
                let d2 = sheet.frameOfCell(atColumn: 3, row: 1)
                if let box = make(.checkbox, CGRect(x: d2.minX, y: d2.minY, width: 90, height: 20), { $0.linkText = "C1"; $0.label = "Agree" }) {
                    controller.gridView.actOnWidget(box, at: CGPoint(x: box.frame.midX, y: box.frame.midY))
                    NSLog("widgetact: checkbox -> C1='%@' active=%d undo=%@", sheet.displayTextOfCell(atColumn: 2, row: 0) ?? "nil",
                          sheet.widgetIsActive(box) ? 1 : 0, sheet.workbook?.undoLabel ?? "nil")
                }
                let d4 = sheet.frameOfCell(atColumn: 3, row: 3)
                if let bar = make(.scrollbar, CGRect(x: d4.minX, y: d4.minY, width: 160, height: 18), { $0.linkText = "C2"; $0.minimum = 0; $0.maximum = 50; $0.horizontal = true }) {
                    let frame = bar.frame
                    controller.gridView.actOnWidget(bar, at: CGPoint(x: frame.minX + 15 + (frame.width - 30) * 0.8, y: frame.midY))
                    NSLog("widgetact: scrollbar -> C2='%@' value=%g", sheet.displayTextOfCell(atColumn: 2, row: 1) ?? "nil", sheet.widgetValue(bar))
                }
                let d6 = sheet.frameOfCell(atColumn: 3, row: 5)
                if let list = make(.list, CGRect(x: d6.minX, y: d6.minY, width: 100, height: 60), { $0.contentText = "A1:A3"; $0.linkText = "C3"; $0.outputsIndex = false }) {
                    controller.gridView.actOnWidget(list, at: CGPoint(x: list.frame.minX + 10, y: list.frame.minY + 15 * sheet.zoomFactor + 3))
                    NSLog("widgetact: list %@ -> C3='%@' selection=%ld", sheet.widgetEntries(list).joined(separator: ","),
                          sheet.displayTextOfCell(atColumn: 2, row: 2) ?? "nil", sheet.widgetSelection(list))
                }
                controller.gridView.select(objects: [])
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_FONTMENU"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Format → Font on A1 (strikethrough), B1 (double
                // underline), C1 (superscript); Edit → Clear → Hyperlinks on
                // a linked D1; Edit → Select → Next Object with one widget.
                let texts = ["struck", "double", "x2", "linked"]
                for (column, text) in texts.enumerated() { try? sheet.setText(text, atColumn: column, row: 0, autocorrect: false) }
                sheet.selectCell(atColumn: 0, row: 0)
                controller.toggleStrikethrough(nil)
                sheet.selectCell(atColumn: 1, row: 0)
                controller.toggleDoubleUnderline(nil)
                sheet.selectCell(atColumn: 2, row: 0)
                controller.toggleSuperscript(nil)
                sheet.selectCell(atColumn: 3, row: 0)
                try? sheet.setHyperlink(Hyperlink(kind: .web, target: "https://www.gnumeric.org/", tip: nil))
                let before = sheet.hyperlink(atColumn: 3, row: 0) != nil
                controller.gridView.clearHyperlinks(nil)
                let strike = sheet.formatOfCell(atColumn: 0, row: 0).strikethrough?.boolValue ?? false
                let underline = sheet.formatOfCell(atColumn: 1, row: 0).underline?.intValue ?? -1
                sheet.selectCell(atColumn: 2, row: 0)
                let script = sheet.fontScriptOfSelection.rawValue
                NSLog("fontmenu: strike=%d underline=%ld script=%ld linked=%d->%d undo=%@", strike ? 1 : 0, underline, script,
                      before ? 1 : 0, sheet.hyperlink(atColumn: 3, row: 0) != nil ? 1 : 0, sheet.workbook?.undoLabel ?? "nil")
                let d3 = sheet.frameOfCell(atColumn: 3, row: 2)
                _ = try? sheet.insertWidget(ofKind: .checkbox, frame: CGRect(x: d3.minX, y: d3.minY, width: 90, height: 20))
                controller.gridView.select(objects: [])
                controller.gridView.selectNextObjectItem(nil)
                NSLog("fontmenu: next object selected=%ld bold-on=%d strike-on=%d", controller.gridView.selectedObjects.count,
                      controller.fontMenuItemIsOn(#selector(WorkbookWindowController.toggleBold(_:))) ? 1 : 0,
                      controller.fontMenuItemIsOn(#selector(WorkbookWindowController.toggleStrikethrough(_:))) ? 1 : 0)
                controller.gridView.select(objects: [])
                sheet.selectCell(atColumn: 0, row: 0)
                NSLog("fontmenu: A1 strike-on=%d", controller.fontMenuItemIsOn(#selector(WorkbookWindowController.toggleStrikethrough(_:))) ? 1 : 0)
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_PAGEBREAK"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Print Area: A1:D10 set, a column break before C and a row
                // break above row 5 (dashed lines in the capture), Show
                // Print Area selecting it; the Help items log their URLs.
                for row in 0..<12 {
                    for column in 0..<6 { try? sheet.setText("\(row + 1)", atColumn: column, row: row, autocorrect: false) }
                }
                try? sheet.setPrintArea("A1:D10")
                sheet.selectCell(atColumn: 2, row: 0)
                controller.toggleColumnPageBreak(nil)
                sheet.selectCell(atColumn: 0, row: 4)
                controller.toggleRowPageBreak(nil)
                let menuItem = NSMenuItem(title: "", action: #selector(WorkbookWindowController.toggleRowPageBreak(_:)), keyEquivalent: "")
                let enabled = controller.validateUserInterfaceItem(menuItem)
                controller.showPrintArea(nil)
                let selected = sheet.selectedRange
                let breaks = "columns=\(sheet.columnPageBreaks) rows=\(sheet.rowPageBreaks) has=\(sheet.hasManualPageBreaks)"
                let item = "item='\(menuItem.title)' enabled=\(enabled)"
                let selection = "selection=\(selected.start.column),\(selected.start.row)-\(selected.end.column),\(selected.end.row)"
                let undo = "undo=" + (sheet.workbook?.undoLabel ?? "nil")
                NSLog("pagebreak: %@ %@ %@ %@", breaks, item, selection, undo)
                let delegate = NSApp.delegate as? AppDelegate
                delegate?.helpDocs(nil)
                delegate?.helpBug(nil)
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_SENDTO"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet, let document = controller.document as? WorkbookDocument {
                // Send To…: an edit, then the copy written for the mailer;
                // the document stays edited and where it was.
                try? sheet.setText("sent", atColumn: 0, row: 0, autocorrect: false)
                controller.sendTo(nil)
                let copy = controller.lastSentCopyURL
                let size = copy.flatMap { (try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int) } ?? -1
                let state = "edited=\(document.isDocumentEdited) modified=\(sheet.workbook?.isModified ?? false)"
                let location = "fileURL=" + (document.fileURL?.lastPathComponent ?? "nil") + " engine=" + (sheet.workbook?.fileURL?.lastPathComponent ?? "nil")
                NSLog("sendto: copy=%@ size=%ld %@ %@", copy?.lastPathComponent ?? "nil", size, state, location)
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_AUTOSAVE"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet, let document = controller.document as? WorkbookDocument {
                // Tools → Auto Save…: two minutes without a prompt through
                // the dialog, the workbook saved beside the capture, an
                // edit, then the timer's work run at once; with the prompt
                // on, the headless run logs instead of asking.  Tools →
                // Auto Correct… opens Settings on the Editing tab.
                AutoSaveDialog.headlessDriver = { dialog in
                    dialog.enabled.state = .on
                    dialog.minutesField.stringValue = "2"
                    dialog.prompt.state = .off
                    return true
                }
                controller.autoSave(nil)
                AutoSaveDialog.headlessDriver = nil
                NSLog("autosave: time=%ld prompt=%d scheduled=%d", controller.autosaveTime, controller.autosavePrompt ? 1 : 0,
                      controller.autosaveTimerIsScheduledForTesting ? 1 : 0)
                let saveURL = URL(fileURLWithPath: (path as NSString).deletingPathExtension + "-autosaved.gnumeric")
                try? FileManager.default.removeItem(at: saveURL)
                do {
                    try document.write(to: saveURL, ofType: WorkbookDocument.gnumericType)
                    document.fileURL = saveURL
                    document.fileType = WorkbookDocument.gnumericType
                    sheet.workbook?.adoptFileURL(saveURL)
                } catch {
                    NSLog("autosave: first write failed: %@", error.localizedDescription)
                }
                let before = (try? FileManager.default.attributesOfItem(atPath: saveURL.path)[.size] as? Int) ?? -1
                try? sheet.setText("autosaved text", atColumn: 0, row: 0, autocorrect: false)
                let edited = document.isDocumentEdited
                controller.autosaveNow { error in
                    let after = (try? FileManager.default.attributesOfItem(atPath: saveURL.path)[.size] as? Int) ?? -1
                    let holds = (try? String(contentsOf: saveURL, encoding: .utf8))?.contains("autosaved text") ?? false
                    NSLog("autosave: save error=%@ before=%ld edited=%d after=%ld holds=%d editedNow=%d",
                          error?.localizedDescription ?? "none", before, edited ? 1 : 0, after, holds ? 1 : 0, document.isDocumentEdited ? 1 : 0)
                }
                controller.autosavePrompt = true
                try? sheet.setText("second edit", atColumn: 0, row: 1, autocorrect: false)
                controller.autosaveNow()
                NSLog("autosave: with prompt editedNow=%d", document.isDocumentEdited ? 1 : 0)
                (NSApp.delegate as? AppDelegate)?.autoCorrectSettings(nil)
                NSLog("autosave: settings tab=%@ visible=%d", (NSApp.delegate as? AppDelegate)?.settings?.model.selectedTab ?? "nil",
                      (NSApp.delegate as? AppDelegate)?.settings?.window.isVisible ?? false ? 1 : 0)
                (NSApp.delegate as? AppDelegate)?.settings?.window.orderOut(nil)
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_MERGE"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet, let workbook = sheet.workbook {
                // Data → Merge…: a letter in A1:B3 with the name in B1 and
                // the city in B2, names in D1:D3 and cities in E1:E3; three
                // sheets result, the first of them shown in the capture.
                let texts: [(Int, Int, String)] = [(0, 0, "Dear"), (0, 1, "City"), (0, 2, "=B1&\" of \"&B2"),
                                                   (3, 0, "Ann"), (3, 1, "Bob"), (3, 2, "Cy"), (4, 0, "Austin"), (4, 1, "Bryan"), (4, 2, "Conroe")]
                for (column, row, text) in texts { try? sheet.setText(text, atColumn: column, row: row, autocorrect: false) }
                MergeDialog.headlessDriver = { dialog in
                    dialog.zoneField.stringValue = "A1:B3"
                    dialog.addRow(data: "D1:D3", field: "B1")
                    dialog.addRow(data: "E1:E3", field: "B2")
                    return true
                }
                controller.mergeData(nil)
                MergeDialog.headlessDriver = nil
                let sheets = workbook.sheets
                let second: Sheet? = sheets.count > 1 ? sheets[1] : nil
                let a3: String = second?.displayTextOfCell(atColumn: 0, row: 2) ?? "nil"
                let b1: String = second?.displayTextOfCell(atColumn: 1, row: 0) ?? "nil"
                let undo: String = workbook.undoLabel ?? "nil"
                NSLog("merge: sheets=%ld second A3='%@' B1='%@' undo=%@", sheets.count, a3, b1, undo)
                second?.revealCell(atColumn: 0, row: 0)
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_COMPARE"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet, let workbook = sheet.workbook {
                // Compare Sheets: a second sheet with a changed B1, an added
                // B2, a removed C3, a bold D1, and a wider column E; the panel
                // compares the first against it, is captured to -compare.png,
                // and its "Changed" row brings B1 of the second sheet into view.
                do {
                    _ = try workbook.insertSheet(before: nil)
                } catch {
                    NSLog("compare: add sheet failed: %@", error.localizedDescription)
                }
                let sheets = workbook.sheets
                if sheets.count >= 2 {
                    let later = sheets[1]
                    for s in [sheet, later] {
                        try? s.setText("same", atColumn: 0, row: 0, autocorrect: false)
                        try? s.setText("10", atColumn: 1, row: 0, autocorrect: false)
                        try? s.setText("gone", atColumn: 2, row: 2, autocorrect: false)
                    }
                    try? later.setText("=B1*2", atColumn: 1, row: 0, autocorrect: false)
                    try? later.setText("extra", atColumn: 1, row: 1, autocorrect: false)
                    later.revealCell(atColumn: 2, row: 2)
                    try? later.clearSelection(.values)
                    later.revealCell(atColumn: 3, row: 0)
                    let bold = CellFormat()
                    bold.bold = true
                    try? later.apply(bold)
                    later.revealCell(atColumn: 4, row: 0)
                    try? later.setSelected(columns: true, sizeInPoints: 120)
                    sheet.revealCell(atColumn: 0, row: 0)
                    controller.compareSheets(nil)
                    if let dialog = controller.sheetCompareDialog {
                        dialog.selectSheets(a: 0, b: 1)
                        dialog.compare(nil)
                        let heads = dialog.results.map { "\($0.text)(\($0.children.count))" }.joined(separator: " ")
                        NSLog("compare: %@", heads)
                        for head in dialog.results {
                            for d in head.children {
                                let line: String = "\(d.text) \(d.location) '\(d.beforeText)' -> '\(d.afterText)' children=\(d.children.count)"
                                NSLog("compare:   %@", line)
                            }
                        }
                        if let content = dialog.panel.contentView {
                            content.layoutSubtreeIfNeeded()
                            if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                                content.cacheDisplay(in: content.bounds, to: rep)
                                let comparePath = (path as NSString).deletingPathExtension + "-compare.png"
                                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: comparePath))
                                NSLog("compare: captured %@ (%@)", comparePath, NSStringFromRect(content.bounds))
                            }
                        }
                        // the Cells section's "Changed" row: B1 on both sheets
                        if let cells = dialog.results.first(where: { $0.section == .cells }),
                           let changed = cells.children.first(where: { $0.direction == .changed }) {
                            dialog.reveal(changed)
                            let current: Sheet = controller.gridView.sheet ?? sheet
                            let edit = current.editPosition
                            let where_: String = "sheet=\(current.name) edit=\(edit.column),\(edit.row)"
                            NSLog("compare: after reveal %@", where_)
                        }
                        dialog.panel.orderOut(nil)
                    }
                }
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_PROTECT"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // The Protection page: B2 unlocked through the model, the
                // sheet protected; an edit of B2 goes through, one of A1 is
                // refused (the error logged, not shown); then unprotected.
                try? sheet.setText("locked", atColumn: 0, row: 0, autocorrect: false)
                sheet.selectCell(atColumn: 1, row: 1)
                let model = FormatCellsModel(format: sheet.formatOfSelection, isMultiCell: false, sheetProtected: sheet.isProtected)
                let before: String = "locked=\(model.contentsLocked) hidden=\(model.contentsHidden) protected=\(model.sheetProtected)"
                model.contentsLocked = false
                model.sheetProtected = true
                controller.applyFormatCells(model, to: sheet)
                let b2 = sheet.formatOfCell(atColumn: 1, row: 1)
                let after: String = "B2 locked=\(b2.contentsLockedValue ?? true) protected=\(sheet.isProtected) undo=\(sheet.workbook?.undoLabel ?? "nil")"
                NSLog("protect: %@ -> %@", before, after)
                // Typing into B2 commits; typing into A1 is refused with the
                // message, the editor staying open (the alert is logged).
                let grid = controller.gridView
                let presenter = grid.presentError
                var refused = "none"
                grid.presentError = { error in refused = (error as NSError).localizedRecoverySuggestion ?? error.localizedDescription }
                sheet.selectCell(atColumn: 1, row: 1)
                grid.beginEditing(initialText: "free")
                grid.commitEditing(text: "free", movement: .none)
                let b2Text: String = sheet.displayTextOfCell(atColumn: 1, row: 1) ?? "nil"
                sheet.selectCell(atColumn: 0, row: 0)
                grid.beginEditing(initialText: "no")
                grid.commitEditing(text: "no", movement: .none)
                let stillEditing = grid.isEditing
                let a1Text: String = sheet.displayTextOfCell(atColumn: 0, row: 0) ?? "nil"
                grid.cancelEditing()
                grid.presentError = presenter
                NSLog("protect: B2='%@' refusal='%@' editing=%d A1='%@'", b2Text, refused, stillEditing ? 1 : 0, a1Text)
                try? sheet.workbook?.setSheet(sheet, protected: false)
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_SHAPES"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // The object toolbar's shapes at four cells, Go to Bottom
                // and Last around a block, and the marching ants' timer
                // after a copy; all left in the capture.
                for (column, row, kind) in [(1, 1, "rectangle"), (4, 1, "ellipse"), (1, 8, "line"), (4, 8, "arrow")] {
                    sheet.selectCell(atColumn: column, row: row)
                    switch kind {
                    case "rectangle": controller.insertRectangle(nil)
                    case "ellipse": controller.insertEllipse(nil)
                    case "line": controller.insertLine(nil)
                    default: controller.insertArrow(nil)
                    }
                }
                let kinds: String = sheet.sheetObjects.map { "\($0.shapeKind.rawValue)" }.joined(separator: ",")
                NSLog("shapes: objects=%ld kinds=%@ undo=%@", sheet.sheetObjects.count, kinds, sheet.workbook?.undoLabel ?? "nil")
                controller.gridView.select(objects: [])
                for row in 12..<16 {
                    for column in 7..<10 { try? sheet.setText("\(row)", atColumn: column, row: row, autocorrect: false) }
                }
                sheet.selectCell(atColumn: 8, row: 13)
                controller.goToBottom(nil)
                let bottom = sheet.selectedRange
                controller.goToLast(nil)
                let last = sheet.selectedRange
                let goes: String = "bottom=\(bottom.start.column),\(bottom.start.row) last=\(last.start.column),\(last.start.row)"
                NSLog("shapes: %@", goes)
                sheet.selectRange(CellRange(start: CellCoordinate(column: 7, row: 12), end: CellCoordinate(column: 9, row: 15)),
                                  editPosition: CellCoordinate(column: 7, row: 12))
                controller.gridView.copy(nil)
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
                NSLog("shapes: ants frames=%ld marching=%d", sheet.marchingAntsFrames.count, controller.gridView.antsAreMarchingForTesting ? 1 : 0)
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_PREVIEW"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Print Preview: a block of 70 rows (two pages), the window
                // opened and captured to -preview.png at Fit Width, then
                // the second page at 100%.
                for row in 0..<70 {
                    for column in 0..<4 { try? sheet.setText("\(column + 1)×\(row + 1)", atColumn: column, row: row, autocorrect: false) }
                }
                controller.printPreview(nil)
                if let preview = controller.printPreview {
                    preview.window.setContentSize(NSSize(width: 700, height: 800))
                    preview.window.layoutIfNeeded()
                    preview.reload()
                    let pages: Int = preview.job?.pageCount ?? -1
                    let scale: Double = Double(preview.scale)
                    NSLog("preview: pages=%ld scale=%.3f page=%ld title='%@'", pages, scale, preview.currentPage + 1, preview.window.title)
                    if let content = preview.window.contentView {
                        content.layoutSubtreeIfNeeded()
                        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: rep)
                            let previewPath = (path as NSString).deletingPathExtension + "-preview.png"
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: previewPath))
                            NSLog("preview: captured %@ (%@)", previewPath, NSStringFromRect(content.bounds))
                        }
                    }
                    preview.selectZoom(at: 3)
                    preview.go(to: 1)
                    let after: String = "scale=\(preview.scale) page=\(preview.currentPage + 1)"
                    NSLog("preview: %@", after)
                    preview.window.orderOut(nil)
                }
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_SORTSETUP"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Remembered sort setups: a table sorted once by its second
                // column descending with the C locale through the dialog's
                // command, then the dialog built again on the range comes
                // back filled; captured to -sortsetup.png.
                let rows: [(String, String)] = [("Name", "Score"), ("Ann", "7"), ("Bob", "9"), ("Cy", "3"), ("Dee", "5")]
                for (row, pair) in rows.enumerated() {
                    try? sheet.setText(pair.0, atColumn: 0, row: row, autocorrect: false)
                    try? sheet.setText(pair.1, atColumn: 1, row: row, autocorrect: false)
                }
                let range = CellRange(start: CellCoordinate(column: 0, row: 0), end: CellCoordinate(column: 1, row: 4))
                let key = SortKey(index: 1, descending: true, caseSensitive: true, byValue: true)
                do {
                    try sheet.sort(range, byRows: true, hasHeader: true, keys: [key], retainFormats: false, locale: "C")
                } catch {
                    NSLog("sortsetup: sort failed %@", error.localizedDescription)
                }
                let dialog = SortDialog(sheet: sheet, range: range)
                let keys: String = dialog.chosenKeysForTesting.map { "\($0.0)/\($0.1 ? "desc" : "asc")/\($0.2 ? "cs" : "ci")" }.joined(separator: " ")
                let a2: String = sheet.displayTextOfCell(atColumn: 0, row: 1) ?? "nil"
                NSLog("sortsetup: loaded=%d keys=%@ A2='%@' setup=%@", dialog.loadedSetup ? 1 : 0, keys, a2,
                      sheet.sortSetup(for: range).map { "\($0)" } ?? "nil")
                if let content = dialog.alert.accessoryView {
                    content.layoutSubtreeIfNeeded()
                    if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                        content.cacheDisplay(in: content.bounds, to: rep)
                        let sortPath = (path as NSString).deletingPathExtension + "-sortsetup.png"
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: sortPath))
                        NSLog("sortsetup: captured %@ (%@)", sortPath, NSStringFromRect(content.bounds))
                    }
                }
                let other = SortDialog(sheet: sheet, range: CellRange(start: CellCoordinate(column: 4, row: 0), end: CellCoordinate(column: 5, row: 3)))
                NSLog("sortsetup: another range loaded=%d", other.loadedSetup ? 1 : 0)
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_REPEAT"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet, let document = controller.document as? WorkbookDocument {
                // Repeat Export: nothing to repeat at first; the sheet
                // written as CSV beside the capture through the document's
                // write, an edit, then File → Repeat Export rewrites it.
                let before: Bool = controller.workbook.lastExportURL == nil
                try? sheet.setText("first", atColumn: 0, row: 0, autocorrect: false)
                let csvURL = URL(fileURLWithPath: (path as NSString).deletingPathExtension + "-repeat.csv")
                try? FileManager.default.removeItem(at: csvURL)
                do {
                    try document.write(to: csvURL, ofType: WorkbookDocument.csvType)
                } catch {
                    NSLog("repeat: csv write failed: %@", error.localizedDescription)
                }
                let remembered: String = controller.workbook.lastExportURL?.lastPathComponent ?? "nil"
                try? sheet.setText("second", atColumn: 0, row: 0, autocorrect: false)
                controller.repeatExport(nil)
                let contents: String = (try? String(contentsOf: csvURL, encoding: .utf8)) ?? "nil"
                let single: Bool = controller.workbook.lastExporterWritesSingleSheet
                NSLog("repeat: none at first=%d remembered=%@ exporter='%@' single=%d after='%@'", before ? 1 : 0, remembered,
                      controller.workbook.lastExporterDescription ?? "nil", single ? 1 : 0, contents.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_XMLOPEN"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet, let workbook = sheet.workbook {
                // A workbook saved as uncompressed XML opens again through
                // the document controller (Henry: it did not, 2026-10-13),
                // and the typed-edit arrow keys commit and move.
                try? sheet.setText("xml round trip", atColumn: 0, row: 0, autocorrect: false)
                let xmlURL = URL(fileURLWithPath: (path as NSString).deletingPathExtension + "-roundtrip.xml")
                try? FileManager.default.removeItem(at: xmlURL)
                do {
                    try workbook.writeCopy(to: xmlURL, saverIdentifier: "Gnumeric_XmlIO:sax:0")
                } catch {
                    NSLog("xmlopen: write failed %@", error.localizedDescription)
                }
                let guessed: String = (try? NSDocumentController.shared.typeForContents(of: xmlURL)) ?? "none"
                NSLog("xmlopen: type for contents %@", guessed)
                NSDocumentController.shared.openDocument(withContentsOf: xmlURL, display: false) { document, _, error in
                    let opened = document as? WorkbookDocument
                    let a1: String = opened?.workbook?.sheets.first?.displayTextOfCell(atColumn: 0, row: 0) ?? "nil"
                    NSLog("xmlopen: opened=%d fileType=%@ A1='%@' error=%@", opened != nil ? 1 : 0, opened?.fileType ?? "nil", a1,
                          error?.localizedDescription ?? "none")
                    opened?.close()
                }
                // arrows end a typed entry and move; an F2 edit keeps them
                let grid = controller.gridView
                sheet.selectCell(atColumn: 2, row: 2)
                grid.beginEditing(initialText: "typed")
                let typedKeyEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                     context: nil, characters: "\u{F703}", charactersIgnoringModifiers: "\u{F703}", isARepeat: false, keyCode: 124)
                if let typedKeyEvent { window.sendEvent(typedKeyEvent) }
                let afterTyped: String = "editing=\(grid.isEditing) C3='\(sheet.displayTextOfCell(atColumn: 2, row: 2) ?? "nil")' edit=\(sheet.editPosition.column),\(sheet.editPosition.row)"
                sheet.selectCell(atColumn: 2, row: 2)
                grid.beginEditing(initialText: nil)
                if let typedKeyEvent { window.sendEvent(typedKeyEvent) }
                let afterF2: String = "editing=\(grid.isEditing) edit=\(sheet.editPosition.column),\(sheet.editPosition.row)"
                grid.cancelEditing()
                NSLog("xmlopen: typed arrow: %@; F2 arrow: %@", afterTyped, afterF2)
                // the Tab Color dialog's wells: a chosen color clears None
                let none = NSButton(checkboxWithTitle: Localization.title("None"), target: nil, action: nil)
                none.state = .on
                let well = TabColorWell(frame: .zero)
                well.noneBox = none
                well.color = .systemRed
                NSLog("xmlopen: tab color well none=%d", none.state == .on ? 1 : 0)
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_BUNDLE"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet, let engine = Engine.shared {
                // The bundled app (scripts/verify-bundle.sh runs this with
                // build/prefix hidden): where the engine looks, the plugins
                // it found, a chart (a goffice plugin), the autoformat
                // templates (the data directory), a PNG and a GIF (gdk-pixbuf).
                let dirs: String = "bundled=\(EngineLocator.isBundled) lib=\(engine.libraryDirectory) data=\(engine.dataDirectory)"
                NSLog("bundle: %@", dirs)
                let counts: String = "plugins available=\(engine.availablePluginCount) active=\(engine.activePluginCount) autoformat categories=\(engine.autoFormatCategories.count)"
                NSLog("bundle: %@", counts)
                for row in 0..<4 { try? sheet.setText("\(row + 1)", atColumn: 0, row: row, autocorrect: false) }
                sheet.selectRange(CellRange(start: CellCoordinate(column: 0, row: 0), end: CellCoordinate(column: 0, row: 3)), editPosition: CellCoordinate(column: 0, row: 0))
                let types = PlotType.allTypes
                let column = types.first { $0.family == "Column" && $0.engine == "GogBarColPlot" }
                var chart = "none"
                if let column, let object = try? sheet.insertChart(column, seriesLayout: .auto, sharedAbscissa: false, frame: CGRect(x: 200, y: 20, width: 240, height: 160)) {
                    chart = object.typeName
                }
                NSLog("bundle: plot types=%ld chart=%@", types.count, chart)
                let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
                    NSColor.systemGreen.setFill(); rect.fill(); return true
                }
                var pngResult = "none", gifResult = "none"
                if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                    if let png = rep.representation(using: .png, properties: [:]) {
                        do { pngResult = try sheet.insertImage(png, frame: CGRect(x: 200, y: 200, width: 40, height: 40)).typeName } catch { pngResult = error.localizedDescription }
                    }
                    if let gif = rep.representation(using: .gif, properties: [:]) {
                        do { gifResult = try sheet.insertImage(gif, frame: CGRect(x: 260, y: 200, width: 40, height: 40)).typeName } catch { gifResult = error.localizedDescription }
                    }
                }
                NSLog("bundle: png=%@ gif=%@ app=%@", pngResult, gifResult, Bundle.main.bundlePath)
                // The licenses: a directory per library beside the index
                // that Help → Third-Party Licenses opens.
                let licensesPath: String = Bundle.main.resourceURL?.appendingPathComponent("licenses").path ?? ""
                let licenseEntries: [String] = (try? FileManager.default.contentsOfDirectory(atPath: licensesPath)) ?? []
                let licenseFolders: Int = licenseEntries.filter { !$0.hasSuffix(".txt") }.count
                let indexState: String = AppDelegate.licensesIndexURL != nil ? "yes" : "no"
                NSLog("bundle: licenses=%ld index=%@", licenseFolders, indexState)
                // The translations: the catalogs per language beside the
                // engine, and the engine's messages following LANG (the
                // verify script runs under German: "Blatt1").
                let localeEntries: [String] = (try? FileManager.default.contentsOfDirectory(atPath: engine.localeDirectory)) ?? []
                let localeState: String = "locale=\(engine.localeDirectory) catalogs=\(localeEntries.count) messages=\(engine.messagesLocale) sheet=\(sheet.name) translated=\(engine.localizedString("Sheet%d"))"
                NSLog("bundle: %@", localeState)
                (NSApp.delegate as? AppDelegate)?.helpLicenses(nil)
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_RTL"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet {
                // Format → Sheet → Right to Left: column A at the right edge
                // of the view, the row header on the right, Left moving to
                // B; a round trip back puts A1 at the left again.
                for (column, text) in ["Alpha", "Beta", "Gamma"].enumerated() {
                    try? sheet.setText(text, atColumn: column, row: 0, autocorrect: false)
                }
                try? sheet.setText("12.5", atColumn: 0, row: 1, autocorrect: false)
                sheet.selectRange(CellRange(start: CellCoordinate(column: 0, row: 0), end: CellCoordinate(column: 0, row: 0)), editPosition: CellCoordinate(column: 0, row: 0))
                let grid = controller.gridView
                controller.toggleDirection(nil)
                view.layoutSubtreeIfNeeded()
                let clip: NSRect = grid.enclosingScrollView?.contentView.bounds ?? .zero
                let a1: NSRect = grid.viewRect(forSheetRect: sheet.frameOfCell(atColumn: 0, row: 0))
                let undo: String = sheet.workbook?.undoLabel ?? "nil"
                let state: String = "rtl=\(sheet.isRightToLeft) a1=\(NSStringFromRect(a1)) clip=\(NSStringFromRect(clip)) undo=\(undo)"
                NSLog("rtl: %@", state)
                let rightPoint = grid.sheetPoint(forViewPoint: NSPoint(x: clip.maxX - 2, y: clip.minY + 5))
                let leftPoint = grid.sheetPoint(forViewPoint: NSPoint(x: clip.minX + 2, y: clip.minY + 5))
                let columnAtRight: Int = sheet.column(atX: rightPoint.x)
                let columnAtLeft: Int = sheet.column(atX: leftPoint.x)
                grid.moveLeft(nil)
                let afterLeft = sheet.editPosition
                let headerXs: [CGFloat] = grid.headerViews.map { $0.frame.minX }
                let hits: String = "columnAtRight=\(columnAtRight) columnAtLeft=\(columnAtLeft) afterLeft=\(afterLeft.column),\(afterLeft.row) headerXs=\(headerXs)"
                NSLog("rtl: %@", hits)
                let menuItem = NSMenuItem(title: "", action: #selector(WorkbookWindowController.toggleDirection(_:)), keyEquivalent: "")
                _ = controller.validateUserInterfaceItem(menuItem)
                NSLog("rtl: item state=%ld", menuItem.state.rawValue)
                controller.toggleDirection(nil)
                view.layoutSubtreeIfNeeded()
                let back: NSRect = grid.viewRect(forSheetRect: sheet.frameOfCell(atColumn: 0, row: 0))
                let backHeaderXs: [CGFloat] = grid.headerViews.map { $0.frame.minX }
                let backState: String = "rtl=\(sheet.isRightToLeft) a1=\(NSStringFromRect(back)) headerXs=\(backHeaderXs)"
                NSLog("rtl: back %@", backState)
                controller.toggleDirection(nil)
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_LOCALE"] != nil,
               let controller = window.windowController as? WorkbookWindowController,
               let sheet = controller.gridView.sheet, let engine = Engine.shared {
                // Run under LANG=de_DE.UTF-8 LANGUAGE=de: the engine's
                // messages are German (the sheet "Blatt1", the undo label,
                // a catalog lookup) and its number parsing takes the comma.
                try? sheet.setText("1,5", atColumn: 0, row: 0, autocorrect: false)
                try? sheet.setText("=A1*2", atColumn: 1, row: 0, autocorrect: false)
                let undo: String = sheet.workbook?.undoLabel ?? "nil"
                let b1: String = sheet.displayTextOfCell(atColumn: 1, row: 0) ?? "nil"
                let state: String = "messages=\(engine.messagesLocale) dir=\(engine.localeDirectory) sheet=\(sheet.name) translated=\(engine.localizedString("Sheet%d")) undo=\(undo) b1=\(b1)"
                NSLog("locale: %@", state)
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            if ProcessInfo.processInfo.environment["GNM_SNAPSHOT_MENUS"] != nil,
               let controller = window.windowController as? WorkbookWindowController {
                // The menu titles in the engine's language (run under
                // LANG=de_DE.UTF-8 LANGUAGE=de): the menu bar, the sheet
                // tab menu, a dynamic title, and how many titles changed.
                let top: [String] = NSApp.mainMenu?.items.map { $0.title } ?? []
                NSLog("menus: top=%@", top.joined(separator: " | "))
                let pairs = Localization.titlesForTesting
                let changed = pairs.filter { $0.english != $0.shown }
                let sample: String = changed.prefix(8).map { "\($0.english)→\($0.shown)" }.joined(separator: ", ")
                NSLog("menus: localized=%ld of %ld: %@", changed.count, pairs.count, sample)
                let formatMenu = NSApp.mainMenu?.items.first { $0.title == Localization.title("Format") }?.submenu
                let sheetMenuTitles: [String] = formatMenu?.items.first { $0.submenu != nil && $0.title == Localization.title("Sheet") }?.submenu?.items.map { $0.title } ?? []
                NSLog("menus: format→sheet=%@", sheetMenuTitles.joined(separator: " | "))
                let tabMenu: [String] = MainMenu.sheetMenu().items.map { $0.title }
                NSLog("menus: tab=%@", tabMenu.joined(separator: " | "))
                let breakItem = NSMenuItem(title: "", action: #selector(WorkbookWindowController.toggleColumnPageBreak(_:)), keyEquivalent: "")
                _ = controller.validateUserInterfaceItem(breakItem)
                NSLog("menus: pagebreak='%@'", breakItem.title)
                let toolbarLabels: [String] = controller.window?.toolbar?.items.map { $0.label } ?? []
                NSLog("menus: toolbar=%@", toolbarLabels.joined(separator: " | "))
                let buttons: [String] = ["Cancel", "OK", "Yes", "Paste Link", "Delete Comment", "Save as Image…", "Fewer Decimals"].map { Localization.title($0) }
                NSLog("menus: buttons=%@", buttons.joined(separator: " | "))
                let chrome: [String] = ["Open…", "Save As…", "Angle:", "Case sensitive", "Goal Seek", "Number", "Alignment"].map { Localization.title($0) }
                NSLog("menus: chrome=%@", chrome.joined(separator: " | "))
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
                // Keyboard moves never leave the cursor under the frozen
                // strips (Henry saw that, 2026-10-13): from row 31 up to the
                // frozen rows, every scrolling row must clear the strip.
                var hidden = 0
                sheet.selectCell(atColumn: 5, row: 30)
                grid.sheet(sheet, makeVisibleColumn: 5, row: 30)
                for _ in 0..<32 {
                    grid.moveUp(nil)
                    let edit = sheet.editPosition
                    let frame = sheet.frameOfCell(atColumn: edit.column, row: edit.row)
                    if grid.panes != nil, edit.row >= sheet.unfrozenTopLeft.row, frame.minY < grid.scrollingVisibleRect.minY - 0.5 { hidden += 1 }
                }
                let origin = grid.enclosingScrollView?.contentView.bounds.origin ?? .zero
                let where_: String = "row=\(sheet.editPosition.row) hidden=\(hidden) origin=\(NSStringFromPoint(origin)) minimum=\(NSStringFromPoint(grid.minimumScrollOrigin))"
                NSLog("freeze: after moving up %@", where_)
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
