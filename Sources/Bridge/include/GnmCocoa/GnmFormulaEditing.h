// Range selection while a formula is typed: where a click on the grid
// may put a reference into the text being edited, as the GTK entry
// decides it (gnm_expr_entry_find_range in gnm-expr-entry.c).
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmGeometry.h>
#import <GnmCocoa/GnmSheet.h>

NS_ASSUME_NONNULL_BEGIN

@interface GnmSheet (FormulaEditing)
/// Whether text being edited, with the insertion point at `cursor`
/// (UTF-16 offset), can take a cell reference from a click: it must be
/// a formula, and the cursor must sit where an operand may go.  On YES,
/// `replace` is the UTF-16 range the reference replaces: empty to
/// insert, or the operand under or before the cursor.
- (BOOL)formulaText:(NSString *)text cursorAt:(NSInteger)cursor canTakeRange:(NSRange *)replace NS_SWIFT_NAME(formulaText(_:cursorAt:canTakeRange:));
/// A range as a reference in this sheet's syntax ("A1", "A1:C4").
- (NSString *)nameOfRange:(GnmCellRange)range NS_SWIFT_NAME(name(of:));
/// The GTK autocompletion (`GnmCompleteSheet`): the nearest text above
/// in the column, up to the first blank, that starts with what was
/// typed; nil when there is none, when autocompletion is off in the
/// preferences, or when fewer characters than their minimum were typed.
- (nullable NSString *)completionForText:(NSString *)text atColumn:(NSInteger)column row:(NSInteger)row NS_SWIFT_NAME(completion(for:atColumn:row:));
@end

NS_ASSUME_NONNULL_END
