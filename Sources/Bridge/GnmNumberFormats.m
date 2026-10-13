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
#include <workbook-cmd-format.h>
#include <style-border.h>
#include <style-color.h>
#include <sheet-style.h>
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

- (NSInteger)indentOfSelection
{
    WorkbookView *wbv = self.workbook.workbookView;
    return wbv && wbv->current_style ? gnm_style_get_indent (wbv->current_style) : 0;
}

- (GnmFontScript)fontScriptOfSelection
{
    WorkbookView *wbv = self.workbook.workbookView;
    return wbv && wbv->current_style ? (GnmFontScript) gnm_style_get_font_script (wbv->current_style) : GnmFontScriptStandard;
}

- (BOOL)changeIndentUp:(BOOL)up error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GnmWorkbook *workbook = self.workbook;
    if (!workbook)
        return NO;
    [workbook selectSheet:self];
    return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        if (up)
            workbook_cmd_inc_indent (wbc);
        else
            workbook_cmd_dec_indent (wbc);
        return FALSE;
    } description:@"Could not change the indent." error:error];
}

- (BOOL)increaseIndentOfSelectionWithError:(NSError **)error { return [self changeIndentUp:YES error:error]; }
- (BOOL)decreaseIndentOfSelectionWithError:(NSError **)error { return [self changeIndentUp:NO error:error]; }

- (BOOL)toggleFontScriptOfSelection:(GnmFontScript)script error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GnmWorkbook *workbook = self.workbook;
    if (!workbook)
        return NO;
    [workbook selectSheet:self];
    GOFontScript value = self.fontScriptOfSelection == script ? GO_FONT_SCRIPT_STANDARD : (GOFontScript) script;
    GnmStyle *style = gnm_style_new ();
    gnm_style_set_font_script (style, value);
    return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_selection_format_toggle_font_style (wbc, style, MSTYLE_FONT_SCRIPT);
    } description:@"Could not change the script." error:error];
}

+ (NSArray<NSNumber *> *)allBorderPresets
{
    return @[@(GnmBorderPresetNone), @(GnmBorderPresetOutside), @(GnmBorderPresetAll), @(GnmBorderPresetThickOutside),
             @(GnmBorderPresetLeft), @(GnmBorderPresetRight), @(GnmBorderPresetBottom), @(GnmBorderPresetDoubleBottom),
             @(GnmBorderPresetThickBottom), @(GnmBorderPresetTopAndBottom), @(GnmBorderPresetTopAndDoubleBottom),
             @(GnmBorderPresetTopAndThickBottom)];
}

+ (NSString *)nameOfBorderPreset:(GnmBorderPreset)preset
{
    switch (preset) {
    case GnmBorderPresetLeft: return @"Left";
    case GnmBorderPresetNone: return @"None";
    case GnmBorderPresetRight: return @"Right";
    case GnmBorderPresetAll: return @"All";
    case GnmBorderPresetOutside: return @"Outside";
    case GnmBorderPresetThickOutside: return @"Thick Outside";
    case GnmBorderPresetBottom: return @"Bottom";
    case GnmBorderPresetDoubleBottom: return @"Double Bottom";
    case GnmBorderPresetThickBottom: return @"Thick Bottom";
    case GnmBorderPresetTopAndBottom: return @"Top and Bottom";
    case GnmBorderPresetTopAndDoubleBottom: return @"Top and Double Bottom";
    case GnmBorderPresetTopAndThickBottom: return @"Top and Thick Bottom";
    }
    return @"";
}

- (BOOL)setBordersOfSelection:(GnmBorderPreset)preset error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GnmWorkbook *workbook = self.workbook;
    Sheet *sheet = self.engineSheet;
    if (!workbook || !sheet)
        return NO;
    [workbook selectSheet:self];
    /* cb_border_activated */
    GnmBorder *borders[GNM_STYLE_BORDER_EDGE_MAX];
    for (int i = GNM_STYLE_BORDER_TOP; i < GNM_STYLE_BORDER_EDGE_MAX; i++)
        borders[i] = NULL;
    /* each fetch takes over one reference to the automatic color, so one is fetched per border as the GTK does */
#define AUTO_COLOR sheet_style_get_auto_pattern_color (sheet)
    switch (preset) {
    case GnmBorderPresetLeft:
        borders[GNM_STYLE_BORDER_LEFT] = gnm_style_border_fetch (GNM_STYLE_BORDER_THIN, AUTO_COLOR, gnm_style_border_get_orientation (GNM_STYLE_BORDER_LEFT));
        break;
    case GnmBorderPresetNone:
        for (int i = GNM_STYLE_BORDER_TOP; i < GNM_STYLE_BORDER_EDGE_MAX; i++)
            borders[i] = gnm_style_border_ref (gnm_style_border_none ());
        break;
    case GnmBorderPresetRight:
        borders[GNM_STYLE_BORDER_RIGHT] = gnm_style_border_fetch (GNM_STYLE_BORDER_THIN, AUTO_COLOR, gnm_style_border_get_orientation (GNM_STYLE_BORDER_RIGHT));
        break;
    case GnmBorderPresetAll:
        for (int i = GNM_STYLE_BORDER_HORIZ; i <= GNM_STYLE_BORDER_VERT; ++i)
            borders[i] = gnm_style_border_fetch (GNM_STYLE_BORDER_THIN, AUTO_COLOR, gnm_style_border_get_orientation (i));
        /* fall through */
    case GnmBorderPresetOutside:
        for (int i = GNM_STYLE_BORDER_TOP; i <= GNM_STYLE_BORDER_RIGHT; ++i)
            borders[i] = gnm_style_border_fetch (GNM_STYLE_BORDER_THIN, AUTO_COLOR, gnm_style_border_get_orientation (i));
        break;
    case GnmBorderPresetThickOutside:
        for (int i = GNM_STYLE_BORDER_TOP; i <= GNM_STYLE_BORDER_RIGHT; ++i)
            borders[i] = gnm_style_border_fetch (GNM_STYLE_BORDER_THICK, AUTO_COLOR, gnm_style_border_get_orientation (i));
        break;
    case GnmBorderPresetTopAndBottom:
    case GnmBorderPresetTopAndDoubleBottom:
    case GnmBorderPresetTopAndThickBottom:
        borders[GNM_STYLE_BORDER_TOP] = gnm_style_border_fetch (GNM_STYLE_BORDER_THIN, AUTO_COLOR, gnm_style_border_get_orientation (GNM_STYLE_BORDER_TOP));
        /* fall through */
    case GnmBorderPresetBottom:
    case GnmBorderPresetDoubleBottom:
    case GnmBorderPresetThickBottom: {
        int tmp = (int) preset % 10;
        GnmStyleBorderType t = tmp == 1 ? GNM_STYLE_BORDER_THIN : tmp == 2 ? GNM_STYLE_BORDER_DOUBLE : GNM_STYLE_BORDER_THICK;
        borders[GNM_STYLE_BORDER_BOTTOM] = gnm_style_border_fetch (t, AUTO_COLOR, gnm_style_border_get_orientation (GNM_STYLE_BORDER_BOTTOM));
        break;
    }
    default:
        return NO;
    }
#undef AUTO_COLOR
    GnmBorder **list = borders;   /* an array cannot be captured by the block */
    return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_selection_format (wbc, NULL, list, "Set Borders");
    } description:@"Could not set the borders." error:error];
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
