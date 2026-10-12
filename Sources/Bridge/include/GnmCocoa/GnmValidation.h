// Data validation (`validation.h`, `input-msg.h`): what a cell accepts,
// what to do when an entry fails, and the message shown while the cell
// is selected, as the GTK Format Cells dialog's Validation and Input
// Message pages set them (dialog-cell-format.c) and the editor checks
// them (wbc-gtk-edit.c).
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmSheet.h>

NS_ASSUME_NONNULL_BEGIN

/// `ValidationStyle`: what happens to an entry that fails.
typedef NS_ENUM(NSInteger, GnmValidationAction) {
    /// Silently accept invalid input.
    GnmValidationActionNone = 0,
    /// Never allow invalid input (re-edit or discard).
    GnmValidationActionStop,
    /// Accept or discard invalid input.
    GnmValidationActionWarning,
    /// Allow invalid input after a message.
    GnmValidationActionInformation,
    /// The editor's own: a formula that does not parse (re-edit or accept).
    GnmValidationActionParseError,
} NS_SWIFT_NAME(Validation.Action);

/// `ValidationType`, in the dialog's order.
typedef NS_ENUM(NSInteger, GnmValidationKind) {
    GnmValidationKindAny = 0,
    GnmValidationKindWholeNumber,
    GnmValidationKindNumber,
    GnmValidationKindInList,
    GnmValidationKindDate,
    GnmValidationKindTime,
    GnmValidationKindTextLength,
    /// The first expression must evaluate to TRUE.
    GnmValidationKindCustom,
} NS_SWIFT_NAME(Validation.Kind);

/// `ValidationOp`, in the dialog's order.
typedef NS_ENUM(NSInteger, GnmValidationOperator) {
    GnmValidationOperatorBetween = 0,
    GnmValidationOperatorNotBetween,
    GnmValidationOperatorEqual,
    GnmValidationOperatorNotEqual,
    GnmValidationOperatorGreaterThan,
    GnmValidationOperatorLessThan,
    GnmValidationOperatorGreaterOrEqual,
    GnmValidationOperatorLessOrEqual,
} NS_SWIFT_NAME(Validation.Operator);

/// `ValidationStatus`: what the editor does with an entry.
typedef NS_ENUM(NSInteger, GnmValidationStatus) {
    GnmValidationStatusValid = 0,
    /// Drop the entry and leave the editor.
    GnmValidationStatusDiscard,
    /// Keep editing.
    GnmValidationStatusEdit,
} NS_SWIFT_NAME(Validation.Status);

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(Validation)
@interface GnmCellValidation : NSObject <NSCopying>
@property (nonatomic) GnmValidationKind kind;
/// For the number, date, time, and text length kinds.
@property (nonatomic) GnmValidationOperator op;
/// The minimum, value, maximum, source list, or criteria (by kind and
/// operator), in the sheet's syntax relative to the edit position.
@property (nonatomic, copy) NSString *firstExpression;
/// The maximum for Between and Not Between.
@property (nonatomic, copy) NSString *secondExpression;
/// An empty cell passes (on).
@property (nonatomic) BOOL allowsBlank;
/// An in-cell list for the In List kind (on).
@property (nonatomic) BOOL usesDropdown;
/// Stop at first.
@property (nonatomic) GnmValidationAction action;
/// The message's title and text; empty for the engine's own words.
@property (nonatomic, copy) NSString *errorTitle;
@property (nonatomic, copy) NSString *errorMessage;
/// How many expressions a kind and operator take (0, 1, or 2).
+ (NSInteger)operandCountForKind:(GnmValidationKind)kind operator:(GnmValidationOperator)op NS_SWIFT_NAME(operandCount(for:operator:));
/// The dialog's label for the first expression ("Min:", "Value:", "Max:",
/// "Source", "Criteria"), or nil when the kind takes none.
+ (nullable NSString *)firstOperandLabelForKind:(GnmValidationKind)kind operator:(GnmValidationOperator)op NS_SWIFT_NAME(firstOperandLabel(for:operator:));
/// The dialog's wording for a kind and an operator.
+ (NSString *)labelForKind:(GnmValidationKind)kind NS_SWIFT_NAME(label(for:));
+ (NSString *)labelForOperator:(GnmValidationOperator)op NS_SWIFT_NAME(label(for:));
+ (NSString *)labelForAction:(GnmValidationAction)action NS_SWIFT_NAME(label(for:));
@end

/// The Input Message page: shown while the cell is selected.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(InputMessage)
@interface GnmInputMessage : NSObject <NSCopying>
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message NS_DESIGNATED_INITIALIZER;
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *message;
@end

@interface GnmSheet (Validation)
/// A cell's validation (expressions written relative to the edit
/// position), or nil without one.
- (nullable GnmCellValidation *)validationAtColumn:(NSInteger)column row:(NSInteger)row NS_SWIFT_NAME(validation(atColumn:row:));
/// A cell's input message, or nil without one.
- (nullable GnmInputMessage *)inputMessageAtColumn:(NSInteger)column row:(NSInteger)row NS_SWIFT_NAME(inputMessage(atColumn:row:));
/// Give the selection a validation and an input message (nil clears
/// each), as the Format Cells dialog applies its pages ("Set
/// validation", undoable).  Expressions parse relative to the edit
/// position; NO with the parser's message otherwise.
- (BOOL)setValidation:(nullable GnmCellValidation *)validation inputMessage:(nullable GnmInputMessage *)message
                error:(NSError **)error NS_SWIFT_NAME(setValidation(_:inputMessage:));
/// The editor's check before an entry is committed (`wbcg_edit_finish`):
/// the text is set in the cell for the moment, the cell's validation
/// evaluated, the cell restored.  A failure asks the workbook delegate
/// what to do with the action's choices; Valid when there is nothing to
/// check.
- (GnmValidationStatus)validateText:(NSString *)text atColumn:(NSInteger)column row:(NSInteger)row NS_SWIFT_NAME(validateText(_:atColumn:row:));
/// The in-cell list of an In List validation at a cell: the source's
/// distinct values as displayed, sorted (the GTK combo's rows); nil
/// without such a validation or when the list is off.
- (nullable NSArray<NSString *> *)validationChoicesAtColumn:(NSInteger)column row:(NSInteger)row NS_SWIFT_NAME(validationChoices(atColumn:row:));
@end

NS_ASSUME_NONNULL_END
