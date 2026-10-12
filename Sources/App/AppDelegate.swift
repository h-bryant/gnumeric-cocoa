import AppKit
import SwiftUI
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
        return configuration
    }
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
                sheet.selectCell(atColumn: 2, row: 2)
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
