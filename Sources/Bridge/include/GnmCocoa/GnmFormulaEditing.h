// Editing with the keyboard: where a click or an arrow key may put a
// reference into a formula being typed, as the GTK entry decides it
// (gnm_expr_entry_find_range in gnm-expr-entry.c), where an arrow moves
// (sheet_find_boundary_*), and the array formula Ctrl+Shift+Return
// enters over the selection (wbcg_edit_finish, WBC_EDIT_ACCEPT_ARRAY).
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmGeometry.h>
#import <GnmCocoa/GnmSheet.h>

NS_ASSUME_NONNULL_BEGIN

/// What the GTK entry's tooltip shows while a formula is typed
/// (gee_check_tooltip): the call around the cursor with its argument
/// marked ("SUM(▶number1◀,number2,…)" and the argument's description),
/// or, for a function name being typed, the names it could complete to.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(FunctionTooltip)
@interface GnmFunctionTooltip : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// The lines to show.
@property (nonatomic, readonly, copy) NSString *text;
/// The function's name for an argument tooltip, nil for completions.
@property (nonatomic, readonly, copy, nullable) NSString *functionName;
/// The argument the cursor is in, for an argument tooltip.
@property (nonatomic, readonly) NSInteger argumentIndex;
/// The names a typed prefix could complete to (the first ten), empty
/// for an argument tooltip.
@property (nonatomic, readonly, copy) NSArray<NSString *> *completions;
/// With one completion, the name F4 puts in place of the prefix, whose
/// UTF-16 range is `completionRange`.
@property (nonatomic, readonly, copy, nullable) NSString *completion;
@property (nonatomic, readonly) NSRange completionRange;
@end

@interface GnmSheet (FormulaEditing)
/// The tooltip for text being edited with the insertion point at
/// `cursor`, or nil when there is none: not a formula, the cursor at
/// the start, no call around it, or the preferences (`function-
/// argument-tooltips`, `function-name-tooltips`) off.
- (nullable GnmFunctionTooltip *)functionTooltipForText:(NSString *)text cursorAt:(NSInteger)cursor NS_SWIFT_NAME(functionTooltip(for:cursorAt:));
/// Whether text being edited, with the insertion point at `cursor`
/// (UTF-16 offset), can take a cell reference from a click: it must be
/// a formula, and the cursor must sit where an operand may go.  On YES,
/// `replace` is the UTF-16 range the reference replaces: empty to
/// insert, or the operand under or before the cursor.
- (BOOL)formulaText:(NSString *)text cursorAt:(NSInteger)cursor canTakeRange:(NSRange *)replace NS_SWIFT_NAME(formulaText(_:cursorAt:canTakeRange:));
/// The GTK's F4 (cb_gee_key_press_event): the reference the cursor is
/// in or just after, with its corners cycled relative → absolute →
/// absolute column → absolute row → relative ("A1", "$A$1", "A$1",
/// "$A1"); nil when no reference is there.  On a result, `range` is the
/// UTF-16 range of the text it replaces.
- (nullable NSString *)formulaText:(NSString *)text cursorAt:(NSInteger)cursor cycleReferenceIn:(NSRange *)range NS_SWIFT_NAME(formulaText(_:cursorAt:cycleReferenceIn:));
/// A range as a reference in this sheet's syntax ("A1", "A1:C4").
- (NSString *)nameOfRange:(GnmCellRange)range NS_SWIFT_NAME(name(of:));
/// Where an arrow key moves `from`: `columns` or `rows` steps (one of
/// them zero; the columns first), skipping hidden columns and rows and
/// whole merged cells, stopping at the sheet's edges
/// (`sheet_find_boundary_horizontal` / `_vertical`).  With `jump`
/// (Ctrl+arrow in the GTK) a single step goes to the edge of the run of
/// filled or of empty cells; `base` is the range's other corner when one
/// is extended (merges are stepped over as a whole), else `from`.
- (GnmCellCoordinate)cell:(GnmCellCoordinate)from movedByColumns:(NSInteger)columns rows:(NSInteger)rows
                     base:(GnmCellCoordinate)base jumpingToBoundary:(BOOL)jump
    NS_SWIFT_NAME(cell(_:movedByColumns:rows:base:jumpingToBoundary:));
/// The GTK's Ctrl+Shift+Return: the text as one array formula over the
/// selection ("Inserting array expression in A1:A3", undoable), parsed
/// at the selection's top left.  As there, when the text is not a
/// formula, or more than one range is selected, the selection is filled
/// with the text instead (Ctrl+Return).  NO with the engine's message
/// when the selection would split an array or a merged region, holds
/// one, or is locked.
- (BOOL)enterArrayFormula:(NSString *)text error:(NSError **)error NS_SWIFT_NAME(enterArrayFormula(_:));
/// The GTK autocompletion (`GnmCompleteSheet`): the nearest text above
/// in the column, up to the first blank, that starts with what was
/// typed; nil when there is none, when autocompletion is off in the
/// preferences, or when fewer characters than their minimum were typed.
- (nullable NSString *)completionForText:(NSString *)text atColumn:(NSInteger)column row:(NSInteger)row NS_SWIFT_NAME(completion(for:atColumn:row:));
@end

NS_ASSUME_NONNULL_END
