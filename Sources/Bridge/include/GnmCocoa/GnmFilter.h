// Autofilters: the drop-down buttons the engine attaches to the heading
// row of a filtered range, the choices each one offers (the GTK combo's
// list), and the conditions a choice sets.  The sheet creates and applies
// them (GnmSheet.h, "Autofilter").
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <GnmCocoa/GnmGeometry.h>

NS_ASSUME_NONNULL_BEGIN

/// One field of an autofilter: the button drawn at the bottom-right of a
/// heading cell.  Buttons are snapshots; ask the sheet for them again after
/// any command.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(FilterButton)
@interface GnmFilterButton : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// The heading cell the button belongs to.
@property (nonatomic, readonly) GnmCellCoordinate cell;
/// The range the filter covers, heading row included.
@property (nonatomic, readonly) GnmCellRange filterRange;
/// Where the button is drawn, in sheet pixels (a square inside the cell's
/// bottom-right corner, at most 20 pixels, as the GTK canvas places it).
@property (nonatomic, readonly) CGRect frame;
/// Whether this field has a condition.
@property (nonatomic, readonly, getter=isActive) BOOL active;
@end

/// Comparisons of the custom condition (the GTK "Custom..." dialog).  The
/// text ones match with wildcards; the others compare a value matched like
/// typed input (a number, a date) or as text.
typedef NS_ENUM(NSInteger, GnmFilterOperator) {
    GnmFilterOperatorNone = 0,
    GnmFilterOperatorEquals,
    GnmFilterOperatorDoesNotEqual,
    GnmFilterOperatorGreaterThan,
    GnmFilterOperatorGreaterThanOrEqual,
    GnmFilterOperatorLessThan,
    GnmFilterOperatorLessThanOrEqual,
    GnmFilterOperatorBeginsWith,
    GnmFilterOperatorDoesNotBeginWith,
    GnmFilterOperatorEndsWith,
    GnmFilterOperatorDoesNotEndWith,
    GnmFilterOperatorContains,
    GnmFilterOperatorDoesNotContain,
} NS_SWIFT_NAME(FilterOperator);

typedef NS_ENUM(NSInteger, GnmFilterConditionKind) {
    /// No condition: every row shows ("(All)").
    GnmFilterConditionShowAll = 0,
    /// Rows whose cell equals one of the column's values.
    GnmFilterConditionValue,
    GnmFilterConditionBlanks,
    GnmFilterConditionNonBlanks,
    /// One or two comparisons ("Custom...").
    GnmFilterConditionCustom,
    /// The top or bottom N items, or N percent of them ("Top 10...").
    GnmFilterConditionBucket,
} NS_SWIFT_NAME(FilterCondition.Kind);

/// What a field filters on.  Value conditions come from `GnmFilterChoices`
/// (they carry the engine value); the others are built here.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(FilterCondition)
@interface GnmFilterCriterion : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
+ (instancetype)showAll;
+ (instancetype)blanks:(BOOL)blanks NS_SWIFT_NAME(blanks(_:));
+ (instancetype)customWithOperator:(GnmFilterOperator)op text:(NSString *)text NS_SWIFT_NAME(custom(_:_:));
+ (instancetype)customWithOperator:(GnmFilterOperator)op0 text:(NSString *)text0 joinedWithAnd:(BOOL)and
                          operator:(GnmFilterOperator)op1 text:(NSString *)text1 NS_SWIFT_NAME(custom(_:_:joinedWithAnd:_:_:));
+ (instancetype)bucketTop:(BOOL)top count:(double)count percent:(BOOL)percent NS_SWIFT_NAME(bucket(top:count:percent:));

@property (nonatomic, readonly) GnmFilterConditionKind kind;
/// Value conditions: the index into the choices' `values`; -1 for a value
/// not in the list.
@property (nonatomic, readonly) NSInteger valueIndex;
/// The value's text, for value conditions read back from the engine.
@property (nonatomic, readonly, copy) NSString *valueText;
// Custom conditions.  `secondOperator` is None for a single comparison.
@property (nonatomic, readonly) GnmFilterOperator firstOperator;
@property (nonatomic, readonly, copy) NSString *firstText;
@property (nonatomic, readonly) GnmFilterOperator secondOperator;
@property (nonatomic, readonly, copy) NSString *secondText;
@property (nonatomic, readonly) BOOL joinedWithAnd;
// Bucket conditions.
@property (nonatomic, readonly, getter=isTop) BOOL top;
@property (nonatomic, readonly, getter=isPercent) BOOL percent;
@property (nonatomic, readonly) double count;
@end

/// The list a filter button drops down: the column's distinct values below
/// the heading (formatted, sorted, rows hidden by the other fields left
/// out), whether blanks exist, and the field's current condition.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(FilterChoices)
@interface GnmFilterChoices : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// Formatted values; a label longer than 50 characters is cut with "...".
@property (nonatomic, readonly, copy) NSArray<NSString *> *values;
@property (nonatomic, readonly) BOOL hasBlanks;
@property (nonatomic, readonly) GnmFilterCriterion *current;
/// A condition selecting rows equal to `values[index]`.
- (GnmFilterCriterion *)conditionForValueAtIndex:(NSInteger)index NS_SWIFT_NAME(condition(forValueAt:));
@end

NS_ASSUME_NONNULL_END
