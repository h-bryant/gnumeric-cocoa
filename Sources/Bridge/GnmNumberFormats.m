// The toolbar's format changes, as wbc-gtk-actions.c runs them over the
// view's current style and cmd_selection_format.
#import "GnmPrivate.h"
#include <commands.h>
#include <mstyle.h>
#include <sheet-view.h>
#include <selection.h>
#include <cell.h>
#include <value.h>
#include <workbook-view.h>
#include <goffice/goffice.h>

/* cb_calc_decs: the most decimals a selected number shows */
static GnmValue *
cb_calc_decs (GnmCellIter const *iter, gpointer user)
{
    int *pdecs = user;
    int decs = 0;
    GnmCell *cell = iter->cell;
    if (!cell || !cell->value || !VALUE_IS_NUMBER (cell->value))
        return NULL;
    if (gnm_cell_has_expr (cell) && cell->base.sheet->display_formulas)
        return NULL;
    char *text = gnm_cell_get_rendered_text (cell);
    GString const *dec = go_locale_get_decimal ();
    const char *p = strstr (text, dec->str);
    if (p) {
        p += dec->len;
        while (g_ascii_isdigit (*p))
            decs++, p++;
    }
    *pdecs = MAX (*pdecs, decs);
    g_free (text);
    return NULL;
}

@implementation GnmSheet (ToolbarFormats)

- (BOOL)changeNumberFormatOfSelection:(GnmNumberFormatChange)change error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GnmWorkbook *workbook = self.workbook;
    WorkbookView *wbv = workbook.workbookView;
    SheetView *sv = self.sheetView;
    if (!workbook || !wbv || !wbv->current_style || !sv)
        return NO;
    [workbook selectSheet:self];
    GOFormat const *current = gnm_style_get_format (wbv->current_style);
    GOFormat *format = NULL;
    const char *label = "Format cells";
    switch (change) {
    case GnmNumberFormatGeneral:
        format = go_format_ref (go_format_general ());
        label = "Format as General";
        break;
    case GnmNumberFormatAccounting:
        format = go_format_ref (go_format_default_accounting ());
        label = "Format as Accounting";
        break;
    case GnmNumberFormatPercentage:
        format = go_format_new_from_XL ("0%");
        label = "Format as Percentage";
        break;
    case GnmNumberFormatScientific:
        format = go_format_new_from_XL ("0.00E+00");
        label = "Format as Scientific";
        break;
    case GnmNumberFormatToggleThousands:
        format = go_format_toggle_1000sep (current);
        label = "Toggle thousands separator";
        break;
    case GnmNumberFormatIncreasePrecision:
    case GnmNumberFormatDecreasePrecision: {
        int dir = change == GnmNumberFormatIncreasePrecision ? 1 : -1;
        label = dir > 0 ? "Increase precision" : "Decrease precision";
        if (!go_format_is_general (current)) {
            format = dir > 0 ? go_format_inc_precision (current) : go_format_dec_precision (current);
        } else {
            /* inc_dec: a fixed format from what the numbers show */
            int decs = -2;
            for (GSList *l = sv->selections; l; l = l->next)
                sheet_foreach_cell_in_range (sv_sheet (sv), CELL_ITER_IGNORE_BLANK | CELL_ITER_IGNORE_HIDDEN, l->data, cb_calc_decs, &decs);
            GString *str = g_string_new ("0");
            if (decs + dir > 0) {
                g_string_append_c (str, '.');
                for (int i = 0; i < decs + dir; i++)
                    g_string_append_c (str, '0');
            }
            format = go_format_new_from_XL (str->str);
            g_string_free (str, TRUE);
        }
        break;
    }
    }
    if (!format)
        return YES;   /* nothing to change (the precision is at its end) */
    GnmStyle *style = gnm_style_new ();
    gnm_style_set_format (style, format);
    go_format_unref (format);
    return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_selection_format (wbc, style, NULL, label);
    } description:@"Could not change the number format." error:error];
}

- (BOOL)toggleHorizontalAlignmentOfSelection:(NSInteger)alignment error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GnmWorkbook *workbook = self.workbook;
    WorkbookView *wbv = workbook.workbookView;
    if (!workbook || !wbv || !wbv->current_style)
        return NO;
    [workbook selectSheet:self];
    GnmHAlign halign = (GnmHAlign) alignment;
    if (gnm_style_get_align_h (wbv->current_style) == halign)
        halign = GNM_HALIGN_GENERAL;
    GnmStyle *style = gnm_style_new ();
    gnm_style_set_align_h (style, halign);
    return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_selection_format (wbc, style, NULL, "Set Horizontal Alignment");
    } description:@"Could not set the alignment." error:error];
}

@end
