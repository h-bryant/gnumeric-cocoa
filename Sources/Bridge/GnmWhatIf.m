// dialog_data_table and tabulate_ok_clicked without their dialogs: the
// same checks in the same order, then the engine's command.
#import "GnmPrivate.h"
#include <tools/tabulate.h>

static NSError *
what_if_error (GnmEngine *engine, NSString *message)
{
    return [engine _errorWithCode:GnmErrorCommandFailed description:message collected:@[]];
}

/* single_cell: the text as one cell, or NO */
static BOOL
parse_single_cell (Sheet *sheet, NSString *text, int *col, int *row)
{
    if (text.length == 0)
        return NO;
    GnmParsePos pp;
    parse_pos_init_sheet (&pp, sheet);
    GnmValue *v = value_new_cellrange_parsepos_str (&pp, text.UTF8String, GNM_EXPR_PARSE_UNKNOWN_NAMES_ARE_STRINGS);
    if (!v)
        return NO;
    BOOL single = VALUE_IS_CELLRANGE (v) && v->v_range.cell.a.col == v->v_range.cell.b.col && v->v_range.cell.a.row == v->v_range.cell.b.row
        && (v->v_range.cell.a.sheet == NULL || v->v_range.cell.a.sheet == sheet);
    if (single) {
        *col = v->v_range.cell.a.col;
        *row = v->v_range.cell.a.row;
    }
    value_release (v);
    return single;
}

@implementation GnmTabulationDimension

- (instancetype)initWithCell:(NSString *)cell minimum:(double)minimum maximum:(double)maximum step:(double)step
{
    if (!(self = [super init]))
        return nil;
    _cell = [cell copy];
    _minimum = minimum;
    _maximum = maximum;
    _step = step;
    return self;
}

@end

@implementation GnmSheet (WhatIf)

- (BOOL)createDataTableWithRowInput:(NSString *)rowInput columnInput:(NSString *)columnInput error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    SheetView *sv = self.sheetView;
    if (!sheet || !workbook || !sv)
        return NO;
    GnmEngine *engine = workbook.engine;
    /* dialog_data_table */
    int col, row;
    if (!parse_single_cell (sheet, rowInput, &col, &row) || !parse_single_cell (sheet, columnInput, &col, &row)) {
        if (error)
            *error = what_if_error (engine, @"The row and column input cells must each be one cell.");
        return NO;
    }
    __block GnmRange input;
    BOOL ok = [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        GnmRange const *r = selection_first_range (sv, GO_CMD_CONTEXT (wbc), "Create Data Table");
        if (r == NULL || range_width (r) <= 1 || range_height (r) <= 1)
            return TRUE;
        input = *r;
        input.start.col++;
        input.start.row++;
        if (sheet_range_splits_region (sheet, &input, NULL, GO_CMD_CONTEXT (wbc), "Data Table")
            || cmd_cell_range_is_locked_effective (sheet, &input, wbc, "Data Table"))
            return TRUE;
        return cmd_create_data_table (wbc, sheet, &input, columnInput.UTF8String, rowInput.UTF8String);
    } description:@"The selection must have more than 1 column and row to create a Data Table." error:error];
    return ok;
}

- (BOOL)tabulateCell:(NSString *)target dimensions:(NSArray<GnmTabulationDimension *> *)dimensions withCoordinates:(BOOL)withCoordinates
               error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    if (!sheet || !workbook)
        return NO;
    GnmEngine *engine = workbook.engine;
    /* tabulate_ok_clicked */
    NSString *message = nil;
    GnmTabulate *tab = gnm_tabulate_new ((int) MAX (dimensions.count, 1));
    int dims = 0;
    for (GnmTabulationDimension *d in dimensions) {
        int col, row;
        if (!parse_single_cell (sheet, d.cell, &col, &row)) {
            message = @"You should introduce a single valid cell as dependency cell";
            break;
        }
        GnmCell *cell = sheet_cell_fetch (sheet, col, row);
        if (gnm_cell_has_expr (cell)) {
            message = @"The dependency cells should not contain an expression";
            break;
        }
        if (!isfinite (d.minimum)) {
            message = @"You should introduce a valid number as minimum";
            break;
        }
        if (!isfinite (d.maximum)) {
            message = @"You should introduce a valid number as maximum";
            break;
        }
        if (d.maximum < d.minimum) {
            message = @"The maximum value should be greater than the minimum";
            break;
        }
        if (!isfinite (d.step)) {
            message = @"You should introduce a valid number as step size";
            break;
        }
        if (d.step <= 0) {
            message = @"The step size should be positive";
            break;
        }
        tab->cells[dims] = cell;
        tab->minima[dims] = d.minimum;
        tab->maxima[dims] = d.maximum;
        tab->steps[dims] = d.step;
        dims++;
    }
    if (!message && dims == 0)
        message = @"You should introduce one or more dependency cells";
    if (!message) {
        int col, row;
        if (!parse_single_cell (sheet, target, &col, &row))
            message = @"You should introduce a single valid cell as result cell";
        else {
            GnmCell *result = sheet_cell_fetch (sheet, col, row);
            if (!gnm_cell_has_expr (result))
                message = @"The target cell should contain an expression";
            else
                tab->target = result;
        }
    }
    if (message) {
        g_object_unref (tab);
        if (error)
            *error = what_if_error (engine, message);
        return NO;
    }
    tab->dims = dims;
    tab->with_coordinates = withCoordinates;
    return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_tabulate (wbc, tab);   /* takes the tabulation */
    } description:@"Could not tabulate." error:error];
}

@end
