// Conditional formatting (`style-conditions.h`): the conditions the GTK
// Format → Conditional Formatting dialog (dialog-cell-format-cond.c)
// lists and edits, each an operator, its one or two expressions, and the
// style overlaid when it holds.
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmCellFormat.h>
#import <GnmCocoa/GnmSheet.h>

NS_ASSUME_NONNULL_BEGIN

/// `GnmStyleCondOp`; the values are what `.gnumeric` files store.
typedef NS_ENUM(NSInteger, GnmConditionOperator) {
    GnmConditionBetween = 0,
    GnmConditionNotBetween,
    GnmConditionEqual,
    GnmConditionNotEqual,
    GnmConditionGreaterThan,
    GnmConditionLessThan,
    GnmConditionGreaterOrEqual,
    GnmConditionLessOrEqual,
    /// The first expression evaluates to TRUE.
    GnmConditionCustom,
    GnmConditionContainsString = 0x10,
    GnmConditionNotContainsString,
    GnmConditionBeginsWithString,
    GnmConditionNotBeginsWithString,
    GnmConditionEndsWithString,
    GnmConditionNotEndsWithString,
    GnmConditionContainsError,
    GnmConditionNotContainsError,
    GnmConditionContainsBlanks,
    GnmConditionNotContainsBlanks,
} NS_SWIFT_NAME(ConditionalFormat.Operator);

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(ConditionalFormat)
@interface GnmConditionalFormat : NSObject <NSCopying>
@property (nonatomic) GnmConditionOperator op;
/// "x": a value, a cell, or an expression in the sheet's syntax, relative
/// to the edit position; empty when the operator takes none.
@property (nonatomic, copy) NSString *firstExpression;
/// "y", for Between and Not Between.
@property (nonatomic, copy) NSString *secondExpression;
/// What to overlay when the condition holds: only the set parts count.
@property (nonatomic, copy) GnmCellFormat *format;
/// The operators in the GTK dialog's order.
@property (class, nonatomic, readonly) NSArray<NSNumber *> *allOperators;
/// How many expressions an operator takes (0, 1, or 2).
+ (NSInteger)operandCountForOperator:(GnmConditionOperator)op NS_SWIFT_NAME(operandCount(for:));
/// The GTK dialog's wording ("Cell value is > x.").
+ (NSString *)labelForOperator:(GnmConditionOperator)op NS_SWIFT_NAME(label(for:));
@end

@interface GnmSheet (ConditionalFormats)
/// The conditions on a cell, in order, expressions written relative to
/// the sheet's edit position; empty without any.
- (NSArray<GnmConditionalFormat *> *)conditionalFormatsAtColumn:(NSInteger)column row:(NSInteger)row NS_SWIFT_NAME(conditionalFormats(atColumn:row:));
/// Give the selection these conditions (replacing any), or none for an
/// empty array ("Set conditional formatting", undoable).  Expressions
/// parse relative to the edit position with unknown names as strings, as
/// the GTK dialog parses them; NO with the parser's message otherwise.
- (BOOL)setConditionalFormats:(NSArray<GnmConditionalFormat *> *)formats error:(NSError **)error NS_SWIFT_NAME(setConditionalFormats(_:));
@end

NS_ASSUME_NONNULL_END
