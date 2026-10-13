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

@interface GnmSheet (ToolbarFormats)
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
