// The format toolbar's one-click changes (wbc-gtk-actions.c): number
// formats and the toggling alignment buttons, each one undoable.
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmSheet.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, GnmNumberFormatChange) {
    /// `go_format_general` ("Format as General").
    GnmNumberFormatGeneral = 0,
    /// `go_format_default_accounting` ("Format as Accounting").
    GnmNumberFormatAccounting,
    /// "0%" ("Format as Percentage").
    GnmNumberFormatPercentage,
    /// "0.00E+00".
    GnmNumberFormatScientific,
    /// `go_format_toggle_1000sep` on the current format.
    GnmNumberFormatToggleThousands,
    /// One more decimal: `go_format_inc_precision`, or for a General
    /// format a fixed format with one more decimal than the selection's
    /// numbers show (the GTK `inc_dec`).
    GnmNumberFormatIncreasePrecision,
    GnmNumberFormatDecreasePrecision,
} NS_SWIFT_NAME(Sheet.NumberFormatChange);

/// The format toolbar's border presets (`cb_border_activated`'s
/// indexes).
typedef NS_ENUM(NSInteger, GnmBorderPreset) {
    GnmBorderPresetLeft = 11,
    GnmBorderPresetNone = 12,
    GnmBorderPresetRight = 13,
    GnmBorderPresetAll = 21,
    GnmBorderPresetOutside = 22,
    GnmBorderPresetThickOutside = 23,
    GnmBorderPresetBottom = 31,
    GnmBorderPresetDoubleBottom = 32,
    GnmBorderPresetThickBottom = 33,
    GnmBorderPresetTopAndBottom = 41,
    GnmBorderPresetTopAndDoubleBottom = 42,
    GnmBorderPresetTopAndThickBottom = 43,
} NS_SWIFT_NAME(Sheet.BorderPreset);

/// `GOFontScript`.
typedef NS_ENUM(NSInteger, GnmFontScript) {
    GnmFontScriptSubscript = -1,
    GnmFontScriptStandard = 0,
    GnmFontScriptSuperscript = 1,
} NS_SWIFT_NAME(Sheet.FontScript);

@interface GnmSheet (ToolbarFormats)
/// The cursor cell's indent and script, for the toolbar's state.
@property (nonatomic, readonly) NSInteger indentOfSelection;
@property (nonatomic, readonly) GnmFontScript fontScriptOfSelection;
/// `workbook_cmd_inc_indent` / `_dec_indent`: one step, up to 20, left
/// alignment set on the way up ("Increase Indent", undoable).
- (BOOL)increaseIndentOfSelectionWithError:(NSError **)error NS_SWIFT_NAME(increaseIndentOfSelection());
- (BOOL)decreaseIndentOfSelectionWithError:(NSError **)error NS_SWIFT_NAME(decreaseIndentOfSelection());
/// The toolbar's superscript and subscript toggles (`toggle_font_attr`
/// over `cmd_selection_format_toggle_font_style`): `script` when the
/// cursor cell does not have it, standard when it does.
- (BOOL)toggleFontScriptOfSelection:(GnmFontScript)script error:(NSError **)error NS_SWIFT_NAME(toggleFontScriptOfSelection(_:));
/// The border selector's presets ("Set Borders", undoable), in the
/// sheet's automatic pattern color.
- (BOOL)setBordersOfSelection:(GnmBorderPreset)preset error:(NSError **)error NS_SWIFT_NAME(setBordersOfSelection(_:));
/// The presets in the GTK selector's order, with their names.
@property (class, nonatomic, readonly) NSArray<NSNumber *> *allBorderPresets;
+ (NSString *)nameOfBorderPreset:(GnmBorderPreset)preset NS_SWIFT_NAME(nameOfBorderPreset(_:));
/// Apply one of the toolbar's number format changes to the selection,
/// from the cursor cell's format (`wb_view->current_style`).
- (BOOL)changeNumberFormatOfSelection:(GnmNumberFormatChange)change error:(NSError **)error NS_SWIFT_NAME(changeNumberFormatOfSelection(_:));
/// The toolbar's alignment buttons (`wbcg_set_selection_halign`): set
/// `alignment` (the `GnmHAlign` value: 2 left, 4 right, 8 center, 64
/// center across selection), or back to General when the cursor cell
/// already has it ("Set Horizontal Alignment").
- (BOOL)toggleHorizontalAlignmentOfSelection:(NSInteger)alignment error:(NSError **)error NS_SWIFT_NAME(toggleHorizontalAlignmentOfSelection(_:));
@end

NS_ASSUME_NONNULL_END
