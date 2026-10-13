import AppKit
import GnmCocoa

/// The Plugin Manager (dialog-plugin-manager.c) as a sheet: every plugin
/// goffice found with a checkbox for its activation, details of the
/// chosen one below (description, identifier, directory, dependencies,
/// services, and a mark for deactivation at the next start when it
/// cannot go now), Activate All, the preference for new plugins, the
/// directories searched with Add and Remove, and Rescan.
@MainActor
final class PluginManagerDialog: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let window: NSWindow
    private let engine: Engine
    private let table = NSTableView()
    private let directoriesTable = NSTableView()
    private let details = NSTextField(wrappingLabelWithString: "")
    private let markBox = NSButton(checkboxWithTitle: "Deactivate at the next start", target: nil, action: nil)
    private let newPluginsBox = NSButton(checkboxWithTitle: "Activate new plugins found at a start", target: nil, action: nil)
    private let activateAllButton = NSButton(title: "Activate All", target: nil, action: nil)
    private let addDirectoryButton = NSButton(title: "Add…", target: nil, action: nil)
    private let removeDirectoryButton = NSButton(title: "Remove", target: nil, action: nil)
    private let rescanButton = NSButton(title: "Rescan", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private(set) var plugins: [Plugin] = []
    /// The directories listed: the system ones first, then the extra ones.
    private(set) var directories: [(path: String, isSystem: Bool)] = []
    private var completion: (@MainActor () -> Void)?
    /// Headless runs answer the dependency question with this.
    static var activatesDependenciesForTesting: Bool?

    init(engine: Engine) {
        self.engine = engine
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Plugin Manager"
        window.isReleasedWhenClosed = false
        super.init()
        build()
        reload(selecting: nil)
    }

    // MARK: Layout

    private func build() {
        for (identifier, title, width) in [("active", "Active", 56.0), ("name", "Plugin name", 520.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            column.minWidth = 40
            table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = true
        table.allowsEmptySelection = true
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        details.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        details.textColor = .secondaryLabelColor
        details.maximumNumberOfLines = 8
        details.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        markBox.target = self
        markBox.action = #selector(markToggled(_:))
        newPluginsBox.target = self
        newPluginsBox.action = #selector(newPluginsToggled(_:))
        newPluginsBox.state = engine.activatesNewPlugins ? .on : .off
        activateAllButton.target = self
        activateAllButton.action = #selector(activateAll(_:))
        let pluginButtons = NSStackView(views: [activateAllButton, newPluginsBox, NSView()])
        pluginButtons.orientation = .horizontal
        pluginButtons.spacing = 12

        let directoryColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("directory"))
        directoryColumn.title = "Directories searched"
        directoryColumn.width = 560
        directoriesTable.addTableColumn(directoryColumn)
        directoriesTable.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        directoriesTable.allowsEmptySelection = true
        directoriesTable.dataSource = self
        directoriesTable.delegate = self
        let directoriesScroll = NSScrollView()
        directoriesScroll.documentView = directoriesTable
        directoriesScroll.hasVerticalScroller = true
        directoriesScroll.borderType = .bezelBorder
        directoriesScroll.heightAnchor.constraint(equalToConstant: 96).isActive = true
        for (button, action) in [(addDirectoryButton, #selector(chooseDirectory(_:))), (removeDirectoryButton, #selector(removeDirectory(_:))),
                                 (rescanButton, #selector(rescan(_:)))] {
            button.target = self
            button.action = action
        }
        let directoryButtons = NSStackView(views: [addDirectoryButton, removeDirectoryButton, rescanButton, NSView()])
        directoryButtons.orientation = .horizontal
        directoryButtons.spacing = 8

        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.lineBreakMode = .byTruncatingTail
        let closeButton = NSButton(title: "Close", target: self, action: #selector(close(_:)))
        closeButton.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [status, NSView(), closeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let stack = NSStackView(views: [scroll, details, markBox, pluginButtons, directoriesScroll, directoryButtons, buttons])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            content.widthAnchor.constraint(equalToConstant: 640),
        ])
        window.contentView = content
        window.initialFirstResponder = table
    }

    // MARK: Running

    func run(in parent: NSWindow, completion: @escaping @MainActor () -> Void) {
        self.completion = completion
        parent.beginSheet(window) { _ in }
    }

    @objc func close(_ sender: Any?) {
        if let parent = window.sheetParent { parent.endSheet(window) }
        window.close()
        let completion = self.completion
        self.completion = nil
        completion?()
    }

    // MARK: The lists

    var selectedPlugin: Plugin? {
        let row = table.selectedRow
        return row >= 0 && row < plugins.count ? plugins[row] : nil
    }

    func select(row: Int) {
        guard row >= 0, row < plugins.count else { return }
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
        updateDetails()
    }

    func select(pluginWithIdentifier identifier: String) {
        if let row = plugins.firstIndex(where: { $0.identifier == identifier }) { select(row: row) }
    }

    private func reload(selecting plugin: Plugin?) {
        plugins = engine.availablePlugins
        table.reloadData()
        if let plugin, let row = plugins.firstIndex(where: { $0.identifier == plugin.identifier }) {
            table.selectRowIndexes([row], byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
        directories = engine.systemPluginDirectories.map { ($0, true) } + engine.extraPluginDirectories.map { ($0, false) }
        directoriesTable.reloadData()
        updateDetails()
    }

    private func updateDetails() {
        if let plugin = selectedPlugin {
            var lines = [plugin.summary]
            lines.append("Identifier: \(plugin.identifier)")
            lines.append("Directory: \(plugin.directory)")
            if !plugin.dependencyIdentifiers.isEmpty {
                lines.append("Depends on: " + plugin.dependencyIdentifiers.joined(separator: ", "))
            }
            if !plugin.serviceDescriptions.isEmpty {
                lines.append("Services: " + plugin.serviceDescriptions.joined(separator: "; "))
            }
            details.stringValue = lines.joined(separator: "\n")
            let stuck = plugin.isActive && !plugin.canDeactivate
            markBox.isEnabled = stuck
            markBox.state = plugin.isMarkedForDeactivation ? .on : .off
        } else {
            details.stringValue = "Choose a plugin for its details."
            markBox.isEnabled = false
            markBox.state = .off
        }
        activateAllButton.isEnabled = plugins.contains { !$0.isActive }
        let row = directoriesTable.selectedRow
        removeDirectoryButton.isEnabled = row >= 0 && row < directories.count && !directories[row].isSystem
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === directoriesTable ? directories.count : plugins.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else { return nil }
        let identifier = tableColumn.identifier
        if identifier.rawValue == "active" {
            guard row < plugins.count else { return nil }
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? {
                let view = NSTableCellView()
                view.identifier = identifier
                let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(activeToggled(_:)))
                box.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(box)
                NSLayoutConstraint.activate([
                    box.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                    box.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                ])
                return view
            }()
            if let box = cell.subviews.first as? NSButton {
                let plugin = plugins[row]
                box.tag = row
                box.state = plugin.isActive ? .on : .off
                // the GTK's "switchable": active plugins in use stay on
                box.isEnabled = !plugin.isActive || plugin.canDeactivate
            }
            return cell
        }
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? {
            let view = NSTableCellView()
            view.identifier = identifier
            let field = NSTextField(labelWithString: "")
            field.lineBreakMode = .byTruncatingTail
            field.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(field)
            view.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
                field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2),
                field.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
            return view
        }()
        if tableView === directoriesTable {
            guard row < directories.count else { return nil }
            cell.textField?.stringValue = directories[row].path
            cell.textField?.textColor = directories[row].isSystem ? .secondaryLabelColor : .labelColor
        } else {
            guard row < plugins.count else { return nil }
            cell.textField?.stringValue = plugins[row].name
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateDetails()
    }

    // MARK: Changes

    private func report(_ error: Error) {
        let nsError = error as NSError
        status.stringValue = [nsError.localizedDescription, nsError.localizedRecoverySuggestion].compactMap { $0 }.joined(separator: " ")
        NSLog("Gnumeric error: %@ %@", nsError.localizedDescription, nsError.localizedRecoverySuggestion ?? "")
    }

    @objc private func activeToggled(_ sender: NSButton) {
        toggleActive(row: sender.tag)
    }

    /// cb_active_toggled: deactivate an active plugin; activate an
    /// inactive one, asking first when inactive dependencies come along.
    func toggleActive(row: Int) {
        guard row >= 0, row < plugins.count else { return }
        let plugin = plugins[row]
        status.stringValue = ""
        if plugin.isActive {
            do { try engine.deactivate(plugin) } catch { report(error) }
            reload(selecting: plugin)
            return
        }
        let dependencies = engine.inactiveDependencyNames(of: plugin)
        let activate = { [weak self] in
            guard let self else { return }
            do { try engine.activate(plugin) } catch { report(error) }
            reload(selecting: plugin)
        }
        guard !dependencies.isEmpty else { return activate() }
        if let answer = Self.activatesDependenciesForTesting {
            if answer { activate() } else { reload(selecting: plugin) }
            return
        }
        let alert = NSAlert()
        alert.messageText = "The following extra plugins must be activated in order to activate this one:"
        alert.informativeText = dependencies.joined(separator: "\n") + "\n\nDo you want to activate this plugin together with its dependencies?"
        alert.addButton(withTitle: "Activate")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { activate() } else { self?.reload(selecting: plugin) }
        }
    }

    @objc private func markToggled(_ sender: NSButton) {
        guard let plugin = selectedPlugin else { return }
        engine.setPlugin(plugin, markedForDeactivation: sender.state == .on)
        updateDetails()
    }

    @objc private func newPluginsToggled(_ sender: NSButton) {
        engine.activatesNewPlugins = sender.state == .on
    }

    @objc func activateAll(_ sender: Any?) {
        status.stringValue = ""
        do { try engine.activateAllPlugins() } catch { report(error) }
        reload(selecting: selectedPlugin)
    }

    @objc func chooseDirectory(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let path = panel.url?.path else { return }
            self?.addDirectory(path)
        }
    }

    func addDirectory(_ path: String) {
        var extra = engine.extraPluginDirectories
        guard !extra.contains(path), !engine.systemPluginDirectories.contains(path) else { return }
        extra.append(path)
        engine.extraPluginDirectories = extra
        status.stringValue = "New directories are searched at the next start, or by Rescan."
        reload(selecting: selectedPlugin)
    }

    @objc func removeDirectory(_ sender: Any?) {
        let row = directoriesTable.selectedRow
        guard row >= 0, row < directories.count, !directories[row].isSystem else { return }
        engine.extraPluginDirectories = engine.extraPluginDirectories.filter { $0 != directories[row].path }
        reload(selecting: selectedPlugin)
    }

    @objc func rescan(_ sender: Any?) {
        status.stringValue = ""
        do {
            let found = try engine.rescanPlugins()
            status.stringValue = found.isEmpty ? "No new plugins." : "New: " + found.map(\.name).joined(separator: ", ")
        } catch {
            report(error)
        }
        reload(selecting: selectedPlugin)
    }
}
