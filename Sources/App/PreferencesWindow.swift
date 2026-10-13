import AppKit
import SwiftUI
import GnmCocoa

/// The Settings window's model: the engine's preferences the app honors,
/// each write going through at once (as in the GTK Preferences dialog;
/// GSettings persists them under the bundle identifier).
@MainActor
final class PreferencesModel: ObservableObject {
    private let preferences: Preferences

    @Published var xmlCompressionLevel: Int { didSet { preferences.xmlCompressionLevel = xmlCompressionLevel } }
    @Published var newWorkbookSheetCount: Int { didSet { preferences.newWorkbookSheetCount = newWorkbookSheetCount } }
    @Published var newWorkbookRowCount: Int { didSet { preferences.newWorkbookRowCount = newWorkbookRowCount } }
    @Published var newWorkbookColumnCount: Int { didSet { preferences.newWorkbookColumnCount = newWorkbookColumnCount } }
    /// Percent.
    @Published var defaultZoom: Int { didSet { preferences.defaultZoom = Double(defaultZoom) / 100 } }
    @Published var defaultFontName: String { didSet { preferences.defaultFontName = defaultFontName } }
    @Published var defaultFontSize: Double { didSet { preferences.defaultFontSize = defaultFontSize } }
    @Published var defaultFontBold: Bool { didSet { preferences.defaultFontBold = defaultFontBold } }
    @Published var defaultFontItalic: Bool { didSet { preferences.defaultFontItalic = defaultFontItalic } }
    @Published var enterMovesDirection: Preferences.Direction { didSet { preferences.enterMovesDirection = enterMovesDirection } }
    @Published var autocorrectsInitialCapitals: Bool { didSet { preferences.autocorrectsInitialCapitals = autocorrectsInitialCapitals } }
    @Published var autocorrectsFirstLetter: Bool { didSet { preferences.autocorrectsFirstLetter = autocorrectsFirstLetter } }
    @Published var autocorrectsNamesOfDays: Bool { didSet { preferences.autocorrectsNamesOfDays = autocorrectsNamesOfDays } }
    @Published var autocorrectsReplacements: Bool { didSet { preferences.autocorrectsReplacements = autocorrectsReplacements } }
    @Published var undoMaximumSteps: Int { didSet { preferences.undoMaximumSteps = undoMaximumSteps } }
    @Published var undoMaximumSize: Int { didSet { preferences.undoMaximumSize = undoMaximumSize } }
    @Published var undoShowsSheetName: Bool { didSet { preferences.undoShowsSheetName = undoShowsSheetName } }
    @Published var undoMaximumDescriptorWidth: Int { didSet { preferences.undoMaximumDescriptorWidth = undoMaximumDescriptorWidth } }
    @Published var sortRetainsFormats: Bool { didSet { preferences.sortRetainsFormats = sortRetainsFormats } }
    @Published var sortIsCaseSensitive: Bool { didSet { preferences.sortIsCaseSensitive = sortIsCaseSensitive } }
    @Published var sortAscending: Bool { didSet { preferences.sortAscending = sortAscending } }
    @Published var sortInitialClauseCount: Int { didSet { preferences.sortInitialClauseCount = sortInitialClauseCount } }
    /// The tab shown: General, Editing, Undo, Sorting, or Font.
    @Published var selectedTab = "General"

    init(preferences: Preferences) {
        self.preferences = preferences
        xmlCompressionLevel = preferences.xmlCompressionLevel
        newWorkbookSheetCount = preferences.newWorkbookSheetCount
        newWorkbookRowCount = preferences.newWorkbookRowCount
        newWorkbookColumnCount = preferences.newWorkbookColumnCount
        defaultZoom = Int((preferences.defaultZoom * 100).rounded())
        defaultFontName = preferences.defaultFontName
        defaultFontSize = preferences.defaultFontSize
        defaultFontBold = preferences.defaultFontBold
        defaultFontItalic = preferences.defaultFontItalic
        enterMovesDirection = preferences.enterMovesDirection
        autocorrectsInitialCapitals = preferences.autocorrectsInitialCapitals
        autocorrectsFirstLetter = preferences.autocorrectsFirstLetter
        autocorrectsNamesOfDays = preferences.autocorrectsNamesOfDays
        autocorrectsReplacements = preferences.autocorrectsReplacements
        undoMaximumSteps = preferences.undoMaximumSteps
        undoMaximumSize = preferences.undoMaximumSize
        undoShowsSheetName = preferences.undoShowsSheetName
        undoMaximumDescriptorWidth = preferences.undoMaximumDescriptorWidth
        sortRetainsFormats = preferences.sortRetainsFormats
        sortIsCaseSensitive = preferences.sortIsCaseSensitive
        sortAscending = preferences.sortAscending
        sortInitialClauseCount = preferences.sortInitialClauseCount
    }

    /// Valid sheet sizes: the powers of two between the engine's limits.
    static func sizes(from minimum: Int, to maximum: Int) -> [Int] {
        var sizes: [Int] = []
        var size = max(minimum, 1)
        while size <= maximum {
            sizes.append(size)
            size *= 2
        }
        return sizes
    }
}

/// The Settings window's content: the GTK Preferences dialog's pages
/// that have an effect here, as tabs.
struct PreferencesView: View {
    @ObservedObject var model: PreferencesModel

    private static let fontFamilies: [String] = NSFontManager.shared.availableFontFamilies.sorted {
        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }

    var body: some View {
        TabView(selection: $model.selectedTab) {
            general.tabItem { Text("General") }.tag("General")
            editing.tabItem { Text("Editing") }.tag("Editing")
            undo.tabItem { Text("Undo") }.tag("Undo")
            sorting.tabItem { Text("Sorting") }.tag("Sorting")
            font.tabItem { Text("Font") }.tag("Font")
        }
        .padding(16)
        .frame(width: 520, height: 400)
    }

    private var general: some View {
        Form {
            Section("Files") {
                Stepper("Compression of .gnumeric files: \(model.xmlCompressionLevel)", value: $model.xmlCompressionLevel, in: 0...9)
                Text("0 writes plain XML, which diffs under version control; 9 makes the smallest file.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("New Workbooks") {
                Stepper("Sheets: \(model.newWorkbookSheetCount)", value: $model.newWorkbookSheetCount, in: 1...64)
                Picker("Rows:", selection: $model.newWorkbookRowCount) {
                    ForEach(PreferencesModel.sizes(from: Workbook.minimumSheetRows, to: Workbook.maximumSheetRows), id: \.self) { size in
                        Text(size.formatted()).tag(size)
                    }
                }
                Picker("Columns:", selection: $model.newWorkbookColumnCount) {
                    ForEach(PreferencesModel.sizes(from: Workbook.minimumSheetColumns, to: Workbook.maximumSheetColumns), id: \.self) { size in
                        Text(size.formatted()).tag(size)
                    }
                }
                Stepper("Zoom: \(model.defaultZoom)%", value: $model.defaultZoom, in: 10...500, step: 5)
            }
        }
        .formStyle(.grouped)
    }

    private var editing: some View {
        Form {
            Section("Cells") {
                Picker("Return moves the selection:", selection: $model.enterMovesDirection) {
                    Text("Down").tag(Preferences.Direction.down)
                    Text("Up").tag(Preferences.Direction.up)
                    Text("Right").tag(Preferences.Direction.right)
                    Text("Left").tag(Preferences.Direction.left)
                }
            }
            Section("Auto Correct") {
                Toggle("Correct TWo INitial CApitals", isOn: $model.autocorrectsInitialCapitals)
                Toggle("Capitalize the first letter of a sentence", isOn: $model.autocorrectsFirstLetter)
                Toggle("Capitalize names of days", isOn: $model.autocorrectsNamesOfDays)
                Toggle("Replace text as you type", isOn: $model.autocorrectsReplacements)
            }
        }
        .formStyle(.grouped)
    }

    private var undo: some View {
        Form {
            Section("Undo") {
                HStack {
                    Text("Undoable commands:")
                    TextField("", value: $model.undoMaximumSteps, format: .number).frame(width: 80)
                    Stepper("", value: $model.undoMaximumSteps, in: 0...10000).labelsHidden()
                }
                HStack {
                    Text("Maximum size of the undo list:")
                    TextField("", value: $model.undoMaximumSize, format: .number).frame(width: 80)
                    Stepper("", value: $model.undoMaximumSize, in: 1...1_000_000, step: 1000).labelsHidden()
                }
                Text("A one-cell edit counts 1; the list is cut when its total passes this.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Name the sheet in command descriptions", isOn: $model.undoShowsSheetName)
                Stepper("Longest description: \(model.undoMaximumDescriptorWidth) characters",
                        value: $model.undoMaximumDescriptorWidth, in: 5...256)
            }
        }
        .formStyle(.grouped)
    }

    private var sorting: some View {
        Form {
            Section("What the Sort dialog starts with") {
                Toggle("Keep formats with the data", isOn: $model.sortRetainsFormats)
                Toggle("Case sensitive", isOn: $model.sortIsCaseSensitive)
                Toggle("Ascending", isOn: $model.sortAscending)
                Stepper("Clauses shown: \(model.sortInitialClauseCount)", value: $model.sortInitialClauseCount, in: 1...50)
            }
        }
        .formStyle(.grouped)
    }

    private var font: some View {
        Form {
            Section("Default font of new workbooks") {
                Picker("Family:", selection: $model.defaultFontName) {
                    if !Self.fontFamilies.contains(model.defaultFontName) {
                        Text(model.defaultFontName).tag(model.defaultFontName)
                    }
                    ForEach(Self.fontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                HStack {
                    Text("Size:")
                    TextField("", value: $model.defaultFontSize, format: .number.precision(.fractionLength(0...1))).frame(width: 60)
                    Stepper("", value: $model.defaultFontSize, in: 4...100, step: 1).labelsHidden()
                    Text("points")
                }
                Toggle("Bold", isOn: $model.defaultFontBold)
                Toggle("Italic", isOn: $model.defaultFontItalic)
            }
        }
        .formStyle(.grouped)
    }
}

/// The Settings window (Gnumeric → Settings…, ⌘,): one per app, kept
/// across closings.
@MainActor
final class PreferencesWindowController {
    let window: NSWindow
    let model: PreferencesModel

    init(preferences: Preferences) {
        model = PreferencesModel(preferences: preferences)
        let hosting = NSHostingController(rootView: PreferencesView(model: model))
        window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        // A standalone hosting window starts at no size until SwiftUI lays
        // out; size it from the view's fitting size (the fixed frame plus
        // padding) now.
        hosting.view.layoutSubtreeIfNeeded()
        let fitting = hosting.view.fittingSize
        window.setContentSize(fitting.width > 10 && fitting.height > 10 ? fitting : NSSize(width: 552, height: 432))
        window.setFrameAutosaveName("Settings")
    }

    /// Show the window, on a tab when one is named (the GTK
    /// `dialog_preferences (wbcg, "Auto Correct")` from Tools → Auto
    /// Correct…; that page is the Editing tab's section here).
    func show(tab: String? = nil) {
        if let tab { model.selectedTab = tab }
        if !window.isVisible, !window.setFrameUsingName("Settings") {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }
}
