// gnm_expr_entry_find_range without the entry: the engine's lexer over
// the text, the tokens around the cursor, and the GTK's rules for which
// of them a reference replaces.  Operands are told from operators by
// their first character, since the parser's token numbers are not
// public.
#import "GnmPrivate.h"
#include <complete-sheet.h>
#include <expr.h>

static gboolean
is_operand (char const *text, GnmLexerItem const *gli)
{
    if (gli->token < 256)
        return FALSE;   /* a single-character token */
    unsigned char c = (unsigned char) text[gli->start];
    return g_ascii_isalnum (c) || c == '"' || c == '\'' || c == '$' || c == '#' || c == '.' || c == '_' || c >= 0x80;
}

static gboolean
is_open (GnmLexerItem const *gli) { return gli->token == '(' || gli->token == '{'; }

static gboolean
is_close (GnmLexerItem const *gli) { return gli->token == ')' || gli->token == '}'; }

/* gee_find_lexer_token */
static void
find_lexer_token (GnmLexerItem const *gli, gsize token_pos, GnmLexerItem const **before, GnmLexerItem const **after)
{
    *before = *after = NULL;
    if (gli->token == 0)
        return;
    if (gli->start == token_pos) {
        *after = gli;
        return;
    }
    while (gli->token != 0) {
        if (gli->start < token_pos && token_pos < gli->end) {
            *before = *after = gli;
            return;
        }
        if (gli->start == token_pos) {
            *before = gli - 1;
            *after = gli;
            return;
        }
        if (gli->end == token_pos) {
            *before = gli;
            *after = (gli + 1)->token != 0 ? gli + 1 : NULL;
            return;
        }
        gli++;
    }
    *before = gli - 1;
}

@implementation GnmSheet (FormulaEditing)

- (BOOL)formulaText:(NSString *)text cursorAt:(NSInteger)cursor canTakeRange:(NSRange *)replace
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    if (!sheet || text.length == 0)
        return NO;
    const char *utf8 = text.UTF8String;
    const char *ptr = gnm_expr_char_start_p (utf8);
    if (!ptr)
        return NO;   /* not a formula */
    /* the cursor as a byte offset */
    NSInteger clamped = MIN (MAX (cursor, 0), (NSInteger) text.length);
    gsize cursor_bytes = strlen ([text substringToIndex:(NSUInteger) clamped].UTF8String);
    gsize start = 0, end = 0;   /* bytes */
    if (ptr[0] == '\0') {
        start = end = (gsize) (ptr - utf8);
    } else {
        GnmParsePos pp;
        GnmCellCoordinate edit = self.editPosition;
        parse_pos_init (&pp, sheet->workbook, sheet, (int) edit.column, (int) edit.row);
        /* the GTK entry lexes the whole text and skips the tokens before
         * the expression's start */
        GnmLexerItem *items = gnm_expr_lex_all (utf8, &pp, GNM_EXPR_PARSE_UNKNOWN_NAMES_ARE_STRINGS, NULL);
        if (!items)
            return NO;
        gsize base = 0;
        gsize token_pos = cursor_bytes;
        GnmLexerItem const *gli = items, *before, *after;
        while (gli->token != 0 && gli->start < (gsize) (ptr - utf8))
            gli++;
        BOOL ok = YES;
        if (gli->token == 0) {
            start = (gsize) (ptr - utf8);
            end = strlen (utf8);
        } else {
            find_lexer_token (gli, token_pos, &before, &after);
            if (!before && !after)
                ok = NO;
            else if (before == after) {
                if (is_open (after + 1) || (gli < before && is_close (before - 1)))
                    ok = NO;
                else {
                    start = base + before->start;
                    end = base + before->end;
                }
            } else if (before && after) {
                if (is_operand (utf8, before)) {
                    if (is_open (after))
                        ok = NO;
                    else {
                        start = base + before->start;
                        end = base + before->end;
                    }
                } else if (is_operand (utf8, after)) {
                    start = base + after->start;
                    end = base + after->end;
                } else {
                    start = base + before->end;
                    end = base + after->start;
                }
            } else if (!before) {
                if (is_operand (utf8, after)) {
                    if (is_open (after + 1))
                        ok = NO;
                    else {
                        start = base + after->start;
                        end = base + after->end;
                    }
                } else
                    start = end = base + after->start;
            } else {
                if (is_operand (utf8, before)) {
                    if (gli < before && is_close (before - 1))
                        ok = NO;
                    else {
                        start = base + before->start;
                        end = base + before->end;
                    }
                } else if (is_close (before))
                    ok = NO;
                else
                    start = end = base + before->start;
            }
        }
        g_free (items);
        if (!ok)
            return NO;
    }
    /* an insertion goes at the cursor (gee_rangesel_update_text); a
     * replacement covers the token, bytes back to UTF-16 */
    if (start == end) {
        if (replace)
            *replace = NSMakeRange ((NSUInteger) clamped, 0);
        return YES;
    }
    NSString *head = [[NSString alloc] initWithBytes:utf8 length:start encoding:NSUTF8StringEncoding];
    NSString *middle = [[NSString alloc] initWithBytes:utf8 + start length:end - start encoding:NSUTF8StringEncoding];
    if (replace)
        *replace = NSMakeRange (head.length, middle.length);
    return YES;
}

static void
cb_complete_match (GnmComplete *complete, char const *text, gpointer closure)
{
    char **found = closure;
    g_free (*found);
    *found = g_strdup (text);
}

- (NSString *)completionForText:(NSString *)text atColumn:(NSInteger)column row:(NSInteger)row
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    WorkbookView *wbv = self.workbook.workbookView;
    if (!sheet || !wbv || !wbv->do_auto_completion || text.length == 0)
        return nil;
    /* wbcg_edit_start: not for formulas */
    if (gnm_expr_char_start_p (text.UTF8String))
        return nil;
    GnmComplete *complete = gnm_complete_sheet_new (sheet, (int) column, (int) row);
    char *found = NULL;
    g_signal_connect (complete, "notify-match", G_CALLBACK (cb_complete_match), &found);
    gnm_complete_start (complete, text.UTF8String);
    /* the GTK searches in idle steps; here all at once */
    if (complete->idle_tag) {
        g_source_remove (complete->idle_tag);
        complete->idle_tag = 0;
    }
    GnmCompleteClass *klass = GNM_COMPLETE_CLASS (G_OBJECT_GET_CLASS (complete));
    while (klass->search_iteration (complete))
        ;
    g_object_unref (complete);
    NSString *result = found ? GnmString (found) : nil;
    g_free (found);
    return result;
}

- (NSString *)nameOfRange:(GnmCellRange)range
{
    GnmRange r;
    range_init (&r, (int) range.start.column, (int) range.start.row, (int) range.end.column, (int) range.end.row);
    return GnmString (range_as_string (&r));
}

- (GnmCellCoordinate)cell:(GnmCellCoordinate)from movedByColumns:(NSInteger)columns rows:(NSInteger)rows
                     base:(GnmCellCoordinate)base jumpingToBoundary:(BOOL)jump
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    if (!sheet)
        return from;
    GnmCellCoordinate to = from;
    /* scg_rangesel_move / scg_cursor_move: a jump steps one cell at a time */
    if (columns != 0)
        to.column = sheet_find_boundary_horizontal (sheet, (int) from.column, (int) from.row, (int) base.row,
                                                    (int) columns, jump && (columns == 1 || columns == -1));
    if (rows != 0)
        to.row = sheet_find_boundary_vertical (sheet, (int) to.column, (int) from.row, (int) base.column,
                                               (int) rows, jump && (rows == 1 || rows == -1));
    return to;
}

- (BOOL)enterArrayFormula:(NSString *)text error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    SheetView *sv = self.sheetView;
    if (!sheet || !workbook || sv == NULL)
        return NO;
    const char *txt = text.UTF8String;
    return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        GSList *selection = selection_get_ranges (sv, FALSE);
        /* wbcg_edit_finish: an array needs a single range; the checks it
         * makes before any command */
        gboolean array = selection != NULL && selection->next == NULL;
        if (sheet_ranges_split_region (sheet, selection, GO_CMD_CONTEXT (wbc), "Set Text")
            || (array && sheet_range_contains_merges_or_arrays (sheet, selection->data, GO_CMD_CONTEXT (wbc), "Set Text", TRUE, FALSE))
            || cmd_selection_is_locked_effective (sheet, selection, wbc, "Set Text")) {
            range_fragment_free (selection);
            return TRUE;
        }
        /* a formula only when the text is not a value in the cell's format,
         * and not a lone "-" */
        char const *expr_txt = NULL;
        GnmCellPos const *pos = &sv->edit_pos;
        GOFormat const *fmt = gnm_style_get_format (sheet_style_get (sheet, pos->col, pos->row));
        GnmValue *value = format_match (txt, fmt, sheet_date_conv (sheet));
        if (value == NULL)
            expr_txt = gnm_expr_char_start_p (txt);
        else
            value_release (value);
        if (expr_txt != NULL && (*expr_txt == '\0' || strcmp (expr_txt, "-") == 0))
            expr_txt = NULL;
        GnmExprTop const *texpr = NULL;
        if (array && expr_txt) {
            GnmParsePos pp;
            GnmRange const *r = selection->data;
            parse_pos_init (&pp, sheet->workbook, sheet, r->start.col, r->start.row);
            texpr = gnm_expr_parse_str (expr_txt, &pp, GNM_EXPR_PARSE_DEFAULT, sheet_get_conventions (sheet), NULL);
        }
        range_fragment_free (selection);
        gboolean failed;
        if (texpr) {
            failed = cmd_area_set_array_expr (wbc, sv, texpr);
            gnm_expr_top_unref (texpr);
        } else
            failed = cmd_area_set_text (wbc, sv, txt, NULL);
        return failed;
    } description:@"Could not enter the array formula." error:error];
}

@end
