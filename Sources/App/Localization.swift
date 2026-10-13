import AppKit
import GnmCocoa

/// The app's titles that are the GTK's, in the language the engine's
/// messages follow: `GTKLabels.messages` (generated from
/// wbc-gtk-actions.c) gives the GTK's message id for a plain title, and
/// `Engine.localizedString` looks it up in the gnumeric catalog under the
/// engine's locale directory.  Titles worded differently here map through
/// `aliases`; a title in neither table is tried as a message id itself,
/// plain and with a mnemonic on its first letter (the command names the
/// engine translates, "Add Column Page Break"; the buttons, "_Cancel");
/// the rest (the standard macOS items, titles with no GTK counterpart)
/// stay as written.  Without a translation a title stays as written too,
/// so an English run is unchanged.  The toolbar labels, the context
/// menus, and the dialogs' buttons come through here as well.
@MainActor
enum Localization {
    /// The app's wording → the GTK's message id, where the two differ.
    static let aliases: [String: String] = [
        "AutoFormat…": "_Autoformat...",
        "Autofit Height": "Auto Fit _Height",
        "Autofit Width": "Auto Fit _Width",
        "Claims About Two Variances…": "Claims About Two _Variances",
        "Define Names…": "_Names...",
        "Delete Cells…": "C_ells...",
        "Delete Columns": "_Columns",
        "Delete Rows": "_Rows",
        "Find…": "S_earch...",
        "Find and Replace…": "Search _& Replace...",
        "Formats": "_Formats",
        "Formats in Filtered Rows": "F_ormats & Hyperlinks in Filtered Rows",
        "Functions…": "_Functions",
        "Gnumeric Help": "_Contents",
        "Go To…": "_Go to Cell...",
        "Import Text…": "Import _Text File...",
        "Insert at End": "_Append",
        "Merge Cells": "Merge",
        "Outline": "_Group and Outline",
        "Print Area": "Print Area & Breaks",
        "Properties…": "Document Proper_ties...",
        "Radio Button": "RadioButton",
        "Random Generator": "_Random Generators",
        "Ranks and Percentiles…": "Ranks And _Percentiles...",
        "Right to Left": "Direction",
        "Settings…": "Preferences...",
        "Spin Button": "SpinButton",
        "Standard Height…": "_Standard Height",
        "Standard Width…": "_Standard Width",
        "Status Bar": "View _Statusbar",
        "Unhide…": "_Unhide",
        "Unmerge Cells": "_Unmerge",
        "Validation…": "_Validate...",
        "Workbook…": "Workbook",
        // The toolbar
        "Across": "_Center Across Selection",
        "Chart": "C_hart...",
        "Fewer Decimals": "Decrease Precision",
        "More Decimals": "Increase Precision",
        "Function": "_Function...",
        "Less Indent": "Decrease Indent",
        "More Indent": "Increase Indent",
        "No Fill": "Clear Background",
        "Percent": "Percentage",
        "Sort A→Z": "Sort Ascending",
        "Sort Z→A": "Sort Descending",
        "Thousands": "Thousands Separator",
        "Zoom": "_Zoom...",
        "Objects": "_Object",
        "Open": "_Open",
        // The context menus and the dialogs' buttons
        "Delete Comment": "_Remove Comments",
        "Insert Comment…": "Add _Comment...",
        "Edit Comment…": "Edit Co_mment...",
        "Save as Image…": "_Save As Image",
        "Paste Link": "Paste _Link",
    ]

    /// Every title asked for and what it became, for the headless checks.
    static var titlesForTesting: [(english: String, shown: String)] = []

    /// The title to show for one the app writes in English.
    static func title(_ english: String) -> String {
        let shown = translated(english) ?? english
        titlesForTesting.append((english, shown))
        return shown
    }

    private static func translated(_ english: String) -> String? {
        guard let engine = Engine.shared else { return nil }
        let dotted = english.replacingOccurrences(of: "…", with: "...")
        let candidates = [GTKLabels.messages[english], aliases[english], dotted, "_" + dotted].compactMap { $0 }
        guard let translation = candidates.lazy.map({ engine.localizedString($0) }).enumerated()
                .first(where: { $0.element != candidates[$0.offset] })?.element else { return nil }
        var result = plain(translation)
        // The app's ellipsis where the GTK's label had none, and none where
        // the app's title has none (a toolbar label from a menu item).
        if english.hasSuffix("…"), !result.hasSuffix("…") { result += "…" }
        if !english.hasSuffix("…"), result.hasSuffix("…") {
            result = String(result.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    /// A label without its mnemonic underscore ("__" is a literal one) and
    /// with "..." as an ellipsis.
    static func plain(_ label: String) -> String {
        label.replacingOccurrences(of: "__", with: "\u{0}")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "\u{0}", with: "_")
            .replacingOccurrences(of: "...", with: "…")
            .trimmingCharacters(in: .whitespaces)
    }
}
