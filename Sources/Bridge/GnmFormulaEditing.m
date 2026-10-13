// gnm_expr_entry_find_range without the entry: the engine's lexer over
// the text, the tokens around the cursor, and the GTK's rules for which
// of them a reference replaces.  Operands are told from operators by
// their first character, since the parser's token numbers are not
// public.
#import "GnmPrivate.h"
#include <complete-sheet.h>
#include <expr.h>
#include <func.h>
#include <gnumeric-conf.h>
#include <goffice/goffice.h>

/* parser.y's token numbers, in declaration order from 258 (parser.h is
 * not installed): STRING 258, QUOTED_STRING 259, CONSTANT 260, RANGEREF
 * 261, the comparison and logic tokens, INTERSECT 268, then ARG_SEP and
 * INVALID_TOKEN (the GTK entry's unmatched apostrophe). */
enum { LEX_STRING = 258, LEX_CONSTANT = 260, LEX_ARG_SEP = 269, LEX_INVALID = 273 };

#define UNICODE_LEFT_TRIANGLE "\xe2\x97\x80"
#define UNICODE_RIGHT_TRIANGLE "\xe2\x96\xb6"
#define UNICODE_CROSS_AND_SKULLBONES "\xe2\x98\xa0"
#define UNICODE_ELLIPSIS "\xe2\x80\xa6"

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

- (NSString *)formulaText:(NSString *)text cursorAt:(NSInteger)cursor cycleReferenceIn:(NSRange *)range
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    NSRange replace = NSMakeRange (0, 0);
    if (!sheet || ![self formulaText:text cursorAt:cursor canTakeRange:&replace] || replace.length == 0)
        return nil;
    GnmParsePos pp;
    GnmCellCoordinate edit = self.editPosition;
    parse_pos_init (&pp, sheet->workbook, sheet, (int) edit.column, (int) edit.row);
    GnmConventions const *convs = sheet_get_conventions (sheet);
    const char *operand = [text substringWithRange:replace].UTF8String;
    GnmRangeRef ref;
    const char *after = rangeref_parse (&ref, operand, &pp, convs);
    if (!after || after == operand || *after != '\0')
        return nil;
    gboolean c = ref.a.col_relative, r = ref.a.row_relative;
    gnm_cellref_set_col_ar (&ref.a, &pp, !c);
    gnm_cellref_set_col_ar (&ref.b, &pp, !c);
    gnm_cellref_set_row_ar (&ref.a, &pp, c ^ r);
    gnm_cellref_set_row_ar (&ref.b, &pp, c ^ r);
    GnmConventionsOut out;
    out.accum = g_string_new (NULL);
    out.pp = &pp;
    out.convs = convs;
    rangeref_as_string (&out, &ref);
    NSString *result = [NSString stringWithUTF8String:out.accum->str] ?: @"";
    g_string_free (out.accum, TRUE);
    if (range)
        *range = replace;
    return result;
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
    /* the preferences (the GTK Tools page): off, or too few characters */
    if (!gnm_conf_get_core_gui_editing_autocomplete ()
        || (NSInteger) text.length < gnm_conf_get_core_gui_editing_autocomplete_min_chars ())
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

#pragma mark - Function tooltips

@implementation GnmFunctionTooltip

- (instancetype)initWithText:(NSString *)text functionName:(NSString *)name argumentIndex:(NSInteger)index
                 completions:(NSArray<NSString *> *)completions completion:(NSString *)completion range:(NSRange)range
{
    if (!(self = [super init]))
        return nil;
    _text = [text copy];
    _functionName = [name copy];
    _argumentIndex = index;
    _completions = [completions copy];
    _completion = [completion copy];
    _completionRange = range;
    return self;
}

@end

/* A help text without its argument markup ("@{criteria}" → "criteria"). */
static NSString *
plain_help (const char *text)
{
    NSString *s = text ? [NSString stringWithUTF8String:text] : nil;
    if (!s)
        return @"";
    NSMutableString *m = [s mutableCopy];
    [m replaceOccurrencesOfString:@"@{" withString:@"" options:0 range:NSMakeRange (0, m.length)];
    [m replaceOccurrencesOfString:@"}" withString:@"" options:0 range:NSMakeRange (0, m.length)];
    return m;
}

/* gee_set_tooltip's text */
static NSString *
argument_tooltip_text (GnmFunc *fd, int args, gboolean had_stuff)
{
    gnm_func_load_if_stub (fd);
    int min, max;
    gnm_func_count_args (fd, &min, &max);
    /* the registered names are lower case; formulas show them upper */
    NSString *fdname = [[NSString stringWithUTF8String:gnm_func_get_name (fd, FALSE)] uppercaseString];
    GString *str = g_string_new (fdname.UTF8String);
    char sep = go_locale_get_arg_sep ();
    gboolean first = TRUE;
    char *extra = NULL;
    g_string_append_c (str, '(');
    int i;
    for (i = 0; i < max; i++) {
        const char *arg_name = gnm_func_get_arg_name (fd, i);
        if (arg_name == NULL)
            break;
        if (first)
            first = FALSE;
        else
            g_string_append_c (str, sep);
        if (i == args) {
            extra = g_strdup_printf ("%s: %s", arg_name, plain_help (gnm_func_get_arg_description (fd, i)).UTF8String);
            g_string_append (str, UNICODE_RIGHT_TRIANGLE);
        }
        if (i >= min)
            g_string_append_c (str, '[');
        g_string_append (str, arg_name);
        if (i >= min)
            g_string_append_c (str, ']');
        if (i == args)
            g_string_append (str, UNICODE_LEFT_TRIANGLE);
    }
    if (i < max) {
        if (!first)
            g_string_append_c (str, sep);
        g_string_append (str, (args >= i && args < max) ? UNICODE_RIGHT_TRIANGLE UNICODE_ELLIPSIS UNICODE_LEFT_TRIANGLE : UNICODE_ELLIPSIS);
    }
    if (max == 0 && args == 0 && !had_stuff) {
        extra = g_strdup_printf ("%s takes no arguments", fdname.UTF8String);
    } else if (args >= max) {
        g_string_append (str, UNICODE_RIGHT_TRIANGLE UNICODE_CROSS_AND_SKULLBONES UNICODE_LEFT_TRIANGLE);
        extra = g_strdup_printf ("Too many arguments for %s", fdname.UTF8String);
    }
    g_string_append_c (str, ')');
    if (extra) {
        g_string_append_c (str, '\n');
        g_string_append (str, extra);
        g_free (extra);
    }
    NSString *result = [NSString stringWithUTF8String:str->str] ?: @"";
    g_string_free (str, TRUE);
    return result;
}

static gint
func_name_cmp (gconstpointer a, gconstpointer b)
{
    return g_ascii_strcasecmp (gnm_func_get_name ((GnmFunc *) a, FALSE), gnm_func_get_name ((GnmFunc *) b, FALSE));
}

@implementation GnmSheet (FunctionTooltips)

- (GnmFunctionTooltip *)functionTooltipForText:(NSString *)text cursorAt:(NSInteger)cursor
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    if (!sheet || text.length == 0 || cursor <= 0)
        return nil;
    const char *utf8 = text.UTF8String;
    if (!gnm_expr_char_start_p (utf8))
        return nil;
    NSInteger clamped = MIN (cursor, (NSInteger) text.length);
    gsize end_t = strlen ([text substringToIndex:(NSUInteger) clamped].UTF8String);
    GnmParsePos pp;
    GnmCellCoordinate edit = self.editPosition;
    parse_pos_init (&pp, sheet->workbook, sheet, (int) edit.column, (int) edit.row);
    GnmLexerItem *items = gnm_expr_lex_all (utf8, &pp, GNM_EXPR_PARSE_UNKNOWN_NAMES_ARE_STRINGS, NULL);
    if (!items)
        return nil;
    /* gee_check_tooltip */
    GnmLexerItem *gli = items;
    gboolean stuff = FALSE;
    int args = 0, last_token = 0;
    GnmFunctionTooltip *result = nil;
    for (; gli->token != 0; gli++) {
        if (gli->start >= end_t) {
            gli->token = 0;
            break;
        }
        if (gli->token != LEX_INVALID)
            continue;
        if (gli->start == 0)
            goto not_found;
        gli->token = 0;
        stuff = TRUE;
        break;
    }
    if (gli > items)
        gli--;
    if (gli > items)
        last_token = (gli - 1)->token;
    /* a function name being typed: the names it could complete to */
    if (!stuff && gli->token == LEX_STRING && last_token != LEX_CONSTANT && last_token != '$') {
        gsize start_t = gli->start, stop_t = gli->end;
        /* the lookup is case-sensitive against the lower-case names, so
         * unlike the GTK a name typed in capitals completes too */
        char *prefix = g_ascii_strdown (utf8 + start_t, (gssize) (stop_t - start_t));
        GSList *list = gnm_func_lookup_prefix (prefix, sheet->workbook, FALSE);
        if (list) {
            list = g_slist_sort (list, func_name_cmp);
            /* gee_set_tooltip_completion: up to nine names longer than the
             * prefix, a name no longer than it ticked and not counted; one
             * counted name is what F4 completes to (the last listed) */
            NSMutableString *lines = [NSMutableString string];
            NSMutableArray *names = [NSMutableArray array];
            NSString *last = nil;
            int i = 0;
            glong typed = g_utf8_strlen (prefix, -1);
            for (GSList *l = list; l && ++i < 10; l = l->next) {
                GnmFunc *fd = l->data;
                gnm_func_load_if_stub (fd);
                const char *raw = gnm_func_get_name (fd, FALSE);
                NSString *name = [[NSString stringWithUTF8String:raw] uppercaseString];
                BOOL exact = typed >= g_utf8_strlen (raw, -1);
                [lines appendFormat:@"%@%@ \t%@\n", exact ? @"\u2713 " : @"", name, plain_help (gnm_func_get_description (fd))];
                [names addObject:name];
                last = name;
                if (exact)
                    i--;
            }
            if (i == 10)
                [lines appendString:@"\u22ee\n"];
            if (i == 1)
                [lines appendString:@"F4 to complete"];
            else if (lines.length)
                [lines deleteCharactersInRange:NSMakeRange (lines.length - 1, 1)];
            NSString *head = [[NSString alloc] initWithBytes:utf8 length:start_t encoding:NSUTF8StringEncoding];
            NSString *word = [[NSString alloc] initWithBytes:utf8 + start_t length:stop_t - start_t encoding:NSUTF8StringEncoding];
            NSRange range = NSMakeRange (head.length, word.length);
            g_slist_free_full (list, (GDestroyNotify) gnm_func_dec_usage);
            g_free (prefix);
            if (!gnm_conf_get_core_gui_editing_function_name_tooltips ())
                goto not_found;
            result = [[GnmFunctionTooltip alloc] initWithText:lines functionName:nil argumentIndex:-1 completions:names
                                                   completion:i == 1 ? last : nil range:range];
            g_free (items);
            return result;
        }
        g_free (prefix);
    }
    if (!gnm_conf_get_core_gui_editing_function_argument_tooltips ())
        goto not_found;
    while (gli->start > 1) {
        switch (gli->token) {
        case '(':
            if ((gli - 1)->token == LEX_STRING) {
                gsize start_t = (gli - 1)->start, stop_t = (gli - 1)->end;
                char *name = g_strndup (utf8 + start_t, stop_t - start_t);
                GnmFunc *fd = gnm_func_lookup (name, NULL);
                g_free (name);
                if (fd != NULL) {
                    result = [[GnmFunctionTooltip alloc] initWithText:argument_tooltip_text (fd, args, stuff)
                                                          functionName:[[NSString stringWithUTF8String:gnm_func_get_name (fd, FALSE)] uppercaseString]
                                                         argumentIndex:args completions:@[] completion:nil range:NSMakeRange (0, 0)];
                    g_free (items);
                    return result;
                }
            }
            stuff = TRUE;
            args = 0;
            break;
        case '{':
            stuff = (args == 0);
            args = 0;
            break;
        case ')': {
            int para = 1;
            gli--;
            while (gli->start > 1 && para > 0) {
                if (gli->token == ')')
                    para++;
                else if (gli->token == '(')
                    para--;
                gli--;
            }
            gli++;
            stuff = (args == 0);
            break;
        }
        case '}': {
            int para = 1;
            gli--;
            while (gli->start > 1 && para > 0) {
                if (gli->token == '}')
                    para++;
                else if (gli->token == '{')
                    para--;
                gli--;
            }
            gli++;
            stuff = (args == 0);
            break;
        }
        case LEX_ARG_SEP:
            args++;
            break;
        default:
            stuff = (args == 0);
            break;
        }
        if (gli->start > 1)
            gli--;
    }
not_found:
    g_free (items);
    return nil;
}

@end
