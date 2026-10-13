// What-if tools: Data → Table… (dialog-data-table.c, cmd_create_data_table)
// and Data → Fill → Tabulate Dependency… (dialog-tabulate.c, cmd_tabulate).
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmSheet.h>

NS_ASSUME_NONNULL_BEGIN

/// One dependency of a tabulation: a cell stepped from `minimum` to
/// `maximum`.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(TabulationDimension)
@interface GnmTabulationDimension : NSObject
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCell:(NSString *)cell minimum:(double)minimum maximum:(double)maximum step:(double)step
    NS_SWIFT_NAME(init(cell:minimum:maximum:step:));
@property (nonatomic, readonly, copy) NSString *cell;
@property (nonatomic, readonly) double minimum;
@property (nonatomic, readonly) double maximum;
@property (nonatomic, readonly) double step;
@end

@interface GnmSheet (WhatIf)
/// Data → Table…: the selection less its first row and column becomes
/// one TABLE(row input, column input) array, each cell the corner's
/// formula evaluated with the row input cell set to its column's header
/// value and the column input cell to its row's ("Creating a Data Table
/// in D2:E3", undoable).  NO with the dialog's message when the
/// selection is one row or column, would split an array or a merge, is
/// locked, or an input does not parse.
- (BOOL)createDataTableWithRowInput:(NSString *)rowInput columnInput:(NSString *)columnInput error:(NSError **)error
    NS_SWIFT_NAME(createDataTable(rowInput:columnInput:));
/// Data → Fill → Tabulate Dependency…: the result cell's formula
/// evaluated over every combination of the dimensions' values, into new
/// sheets ("Tabulating Dependencies", undoable); `withCoordinates`
/// writes one row per combination (the dialog's coordinate mode) rather
/// than a table.  NO with the dialog's messages: each dependency a
/// single cell without a formula, numbers in order, a positive step, at
/// least one dimension, and a result cell holding a formula.
- (BOOL)tabulateCell:(NSString *)target dimensions:(NSArray<GnmTabulationDimension *> *)dimensions withCoordinates:(BOOL)withCoordinates
               error:(NSError **)error NS_SWIFT_NAME(tabulate(target:dimensions:withCoordinates:));
@end

NS_ASSUME_NONNULL_END
