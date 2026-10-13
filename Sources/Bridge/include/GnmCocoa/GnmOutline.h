// Outlines, grouped columns and rows: the levels the headers draw as
// bars (item-bar.c), Data → Outline's commands (wbc-gtk-actions.c
// group_ungroup_colrow and hide_show_detail), and the toggle a click on
// a header's bar runs (outline_button_press).
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmSheet.h>

NS_ASSUME_NONNULL_BEGIN

@interface GnmSheet (Outline)
/// A column's or row's nesting depth, 0 outside any group.
- (NSInteger)outlineLevelOfColumn:(NSInteger)column NS_SWIFT_NAME(outlineLevel(ofColumn:));
- (NSInteger)outlineLevelOfRow:(NSInteger)row NS_SWIFT_NAME(outlineLevel(ofRow:));
/// The column or row that ends a group whose members are hidden (the
/// engine's `is_collapsed`): the headers draw its "+" there.
- (BOOL)isColumnCollapsed:(NSInteger)column NS_SWIFT_NAME(isColumnCollapsed(_:));
- (BOOL)isRowCollapsed:(NSInteger)row NS_SWIFT_NAME(isRowCollapsed(_:));
/// The deepest level on each axis; 0 without groups.
@property (nonatomic, readonly) NSInteger maximumColumnOutlineLevel;
@property (nonatomic, readonly) NSInteger maximumRowOutlineLevel;
/// The sheet's Display Outlines, Outline Symbols Below, Outline Symbols
/// Right (toggled through `toggleDisplayOption:`).
@property (nonatomic, readonly) BOOL displaysOutlines;
@property (nonatomic, readonly) BOOL outlineSymbolsBelow;
@property (nonatomic, readonly) BOOL outlineSymbolsRight;
/// Whether the selection's first range covers every column (whole rows
/// selected) or every row (whole columns): the GTK groups along the
/// other axis without asking, and asks when both or neither hold.
@property (nonatomic, readonly) BOOL selectionSpansAllColumns;
@property (nonatomic, readonly) BOOL selectionSpansAllRows;
/// Data → Outline → Group / Ungroup on the selection's columns or rows
/// (`cmd_selection_group`, undoable); NO with the engine's message when
/// they are already grouped, or not grouped.
- (BOOL)groupSelection:(BOOL)group columns:(BOOL)columns error:(NSError **)error NS_SWIFT_NAME(groupSelection(_:columns:));
/// Data → Outline → Hide Detail / Show Detail: hide or show the
/// selection's columns or rows, which must form an existing group
/// (`cmd_selection_colrow_hide`, undoable).
- (BOOL)setDetailShown:(BOOL)shown columns:(BOOL)columns error:(NSError **)error NS_SWIFT_NAME(setDetailShown(_:columns:));
/// A click on a header's outline bar at a column or row and a level
/// (`cmd_selection_outline_change`): collapse or expand the group there.
- (BOOL)changeOutlineAtIndex:(NSInteger)index columns:(BOOL)columns depth:(NSInteger)depth error:(NSError **)error
    NS_SWIFT_NAME(changeOutline(atIndex:columns:depth:));
/// Show every group down to `depth` levels and hide the rest
/// (`cmd_global_outline_change`, the level buttons of other spreadsheets).
- (BOOL)changeGlobalOutlineForColumns:(BOOL)columns depth:(NSInteger)depth error:(NSError **)error
    NS_SWIFT_NAME(changeGlobalOutline(columns:depth:));
@end

NS_ASSUME_NONNULL_END
