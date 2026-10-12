// A text import session over GnmStfParseOptions: what dialog-stf.c and
// its pages keep in StfDialogData (the decoded text, the chosen lines,
// the parse options, the per-column formats and choices), and the parse
// into a workbook from stf.c's stf_read_workbook.
#import "GnmPrivate.h"
#include <stf-parse.h>
#include <stf.h>
#include <expr.h>

@implementation GnmTextImportSession {
    GString *_text;                 /* UTF-8, NUL-free */
    GnmStfParseOptions *_po;
    NSInteger _lineCount;
    NSInteger _startLine, _stopLine;
    NSArray<NSNumber *> *_importedColumns;
}

#pragma mark - Making one

static GString *
decode (NSData *data, NSString *encoding, NSString **encodingOut, NSString **problem)
{
    GString *utf8 = NULL;
    const char *enc = go_guess_encoding (data.bytes, data.length, encoding.UTF8String, &utf8, NULL);
    if (!enc || !utf8) {
        if (utf8)
            g_string_free (utf8, TRUE);
        *problem = @"That file is not in the given encoding.";
        return NULL;
    }
    /* stf.c clear_stray_NULs */
    for (gsize i = 0; i < utf8->len; i++)
        if (utf8->str[i] == '\0')
            utf8->str[i] = ' ';
    *encodingOut = [NSString stringWithUTF8String:enc];
    return utf8;
}

- (instancetype)initWithText:(GString *)text name:(NSString *)name encoding:(NSString *)encoding url:(NSURL *)url
{
    if (!(self = [super init]))
        return nil;
    _text = text;
    _name = [name copy];
    _encoding = [encoding copy];
    _url = [url copy];
    BOOL csv = [name.pathExtension caseInsensitiveCompare:@"csv"] == NSOrderedSame;
    _po = csv ? stf_parse_options_guess_csv (_text->str) : stf_parse_options_guess (_text->str);
    _importedColumns = @[];
    [self _countLines];
    _startLine = 1;
    _stopLine = MAX (_lineCount, 1);
    return self;
}

+ (instancetype)sessionWithContentsOfURL:(NSURL *)url encoding:(NSString *)encoding error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&readError];
    if (!data) {
        if (error)
            *error = readError;
        return nil;
    }
    NSString *found = nil, *problem = nil;
    GString *text = decode (data, encoding, &found, &problem);
    if (!text) {
        if (error)
            *error = [GnmEngine.shared _errorWithCode:GnmErrorOpenFailed description:problem collected:@[]];
        return nil;
    }
    return [[self alloc] initWithText:text name:url.lastPathComponent encoding:found url:url];
}

+ (instancetype)sessionWithText:(NSString *)text name:(NSString *)name
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GString *copy = g_string_new (text.UTF8String ?: "");
    return [[self alloc] initWithText:copy name:name encoding:@"UTF-8" url:nil];
}

- (void)dealloc
{
    if (_po)
        g_object_unref (_po);
    if (_text)
        g_string_free (_text, TRUE);
}

#pragma mark - Lines

- (void)_countLines
{
    GnmStfParsedLines *pl = stf_parse_lines (_po, _text->str, G_MAXINT, FALSE);
    _lineCount = pl ? (NSInteger) pl->lines->len : 0;
    if (pl)
        g_object_unref (pl);
}

- (NSInteger)lineCount { return _lineCount; }

- (NSInteger)startLine { return _startLine; }
- (NSInteger)stopLine { return _stopLine; }

- (void)setStartLine:(NSInteger)line
{
    /* dialog-stf-main-page.c main_page_import_range_changed */
    _startLine = MIN (_stopLine, MAX (1, line));
}

- (void)setStopLine:(NSInteger)line
{
    NSInteger limit = MIN (_lineCount, _startLine + (GNM_MAX_ROWS - 1));
    _stopLine = MIN (MAX (1, line), MAX (limit, 1));
    if (_startLine > _stopLine)
        _startLine = _stopLine;
}

/// The chosen range of the text: [start, end).
- (void)_rangeStart:(const char **)start end:(const char **)end
{
    *start = stf_parse_find_line (_po, _text->str, (int) _startLine - 1);
    *end = stf_parse_find_line (_po, _text->str, (int) _stopLine);
    if (!*start)
        *start = _text->str;
    if (!*end || *end < *start)
        *end = _text->str + _text->len;
}

#pragma mark - The main page

- (GnmTextImportKind)kind
{
    return _po->parsetype == PARSE_TYPE_FIXED ? GnmTextImportFixedWidth : GnmTextImportSeparated;
}

- (void)setKind:(GnmTextImportKind)kind
{
    stf_parse_options_set_type (_po, kind == GnmTextImportFixedWidth ? PARSE_TYPE_FIXED : PARSE_TYPE_CSV);
}

- (GnmTextLineBreaks)lineBreaks
{
    GnmTextLineBreaks breaks = 0;
    for (GSList *l = _po->terminator; l; l = l->next) {
        const char *t = l->data;
        if (strcmp (t, "\n") == 0)
            breaks |= GnmTextLineBreaksUnix;
        else if (strcmp (t, "\r\n") == 0)
            breaks |= GnmTextLineBreaksWindows;
        else if (strcmp (t, "\r") == 0)
            breaks |= GnmTextLineBreaksMacintosh;
    }
    return breaks;
}

- (void)setLineBreaks:(GnmTextLineBreaks)breaks
{
    /* dialog-stf-main-page.c cb_line_breaks: the range follows the end
     * when it reached it */
    BOOL toEnd = _stopLine >= _lineCount;
    stf_parse_options_clear_line_terminator (_po);
    if (breaks & GnmTextLineBreaksUnix)
        stf_parse_options_add_line_terminator (_po, "\n");
    if (breaks & GnmTextLineBreaksWindows)
        stf_parse_options_add_line_terminator (_po, "\r\n");
    if (breaks & GnmTextLineBreaksMacintosh)
        stf_parse_options_add_line_terminator (_po, "\r");
    [self _countLines];
    if (toEnd)
        _stopLine = MAX (_lineCount, 1);
    [self setStopLine:_stopLine];
}

#pragma mark - The separators page

- (NSString *)separatorCharacters
{
    return _po->sep.chr ? [NSString stringWithUTF8String:_po->sep.chr] : @"";
}

- (NSArray<NSString *> *)customSeparators
{
    NSMutableArray *custom = [NSMutableArray array];
    for (GSList *l = _po->sep.str; l; l = l->next)
        [custom addObject:[NSString stringWithUTF8String:l->data]];
    return custom;
}

- (void)_setSeparatorCharacters:(NSString *)characters custom:(NSArray<NSString *> *)custom
{
    GSList *list = NULL;
    for (NSString *s in custom)
        if (s.length)
            list = g_slist_append (list, g_strdup (s.UTF8String));
    stf_parse_options_csv_set_separators (_po, characters.length ? characters.UTF8String : NULL, list);
    g_slist_free_full (list, g_free);
}

- (void)setSeparatorCharacters:(NSString *)characters
{
    [self _setSeparatorCharacters:characters custom:self.customSeparators];
}

- (void)setCustomSeparators:(NSArray<NSString *> *)custom
{
    [self _setSeparatorCharacters:self.separatorCharacters custom:custom];
}

- (BOOL)mergesAdjacentSeparators { return _po->sep.duplicates; }
- (void)setMergesAdjacentSeparators:(BOOL)merges { stf_parse_options_csv_set_duplicates (_po, merges); }
- (BOOL)ignoresLeadingSeparators { return _po->trim_seps; }
- (void)setIgnoresLeadingSeparators:(BOOL)ignores { stf_parse_options_csv_set_trim_seps (_po, ignores); }

- (NSString *)quoteCharacter
{
    if (!_po->stringindicator)
        return @"";
    char buffer[8];
    int len = g_unichar_to_utf8 (_po->stringindicator, buffer);
    return [[NSString alloc] initWithBytes:buffer length:len encoding:NSUTF8StringEncoding] ?: @"";
}

- (void)setQuoteCharacter:(NSString *)quote
{
    stf_parse_options_csv_set_stringindicator (_po, quote.length ? g_utf8_get_char (quote.UTF8String) : 0);
}

- (BOOL)doubledQuoteIsLiteral { return _po->indicator_2x_is_single; }
- (void)setDoubledQuoteIsLiteral:(BOOL)literal { stf_parse_options_csv_set_indicator_2x_is_single (_po, literal); }

#pragma mark - The fixed-width page

- (NSArray<NSNumber *> *)splitPositions
{
    NSMutableArray *positions = [NSMutableArray array];
    int count = stf_parse_options_fixed_splitpositions_count (_po);
    for (int i = 0; i < count; i++) {
        int position = stf_parse_options_fixed_splitpositions_nth (_po, i);
        if (position >= 0)
            [positions addObject:@(position)];
    }
    return positions;
}

- (void)setSplitPositions:(NSArray<NSNumber *> *)positions
{
    stf_parse_options_fixed_splitpositions_clear (_po);
    for (NSNumber *position in [positions sortedArrayUsingSelector:@selector(compare:)])
        if (position.intValue > 0)
            stf_parse_options_fixed_splitpositions_add (_po, position.intValue);
}

- (void)discoverSplitPositions
{
    const char *start, *end;
    [self _rangeStart:&start end:&end];
    stf_parse_options_fixed_autodiscover (_po, start, end);
}

#pragma mark - The format page

- (GnmTextTrimming)trimming
{
    switch ((int) _po->trim_spaces) {
    case TRIM_TYPE_LEFT: return GnmTextTrimmingLeft;
    case TRIM_TYPE_RIGHT: return GnmTextTrimmingRight;
    case TRIM_TYPE_LEFT | TRIM_TYPE_RIGHT: return GnmTextTrimmingBoth;
    default: return GnmTextTrimmingNone;
    }
}

- (void)setTrimming:(GnmTextTrimming)trimming
{
    GnmStfTrimType trim;
    switch (trimming) {
    case GnmTextTrimmingLeft: trim = TRIM_TYPE_LEFT; break;
    case GnmTextTrimmingRight: trim = TRIM_TYPE_RIGHT; break;
    case GnmTextTrimmingBoth: trim = TRIM_TYPE_LEFT | TRIM_TYPE_RIGHT; break;
    default: trim = TRIM_TYPE_NEVER; break;
    }
    stf_parse_options_set_trim_spaces (_po, trim);
}

- (NSString *)locale
{
    return _po->locale && *_po->locale ? [NSString stringWithUTF8String:_po->locale] : nil;
}

- (void)setLocale:(NSString *)locale
{
    g_free (_po->locale);
    _po->locale = locale.length ? g_strdup (locale.UTF8String) : NULL;
}

- (GnmStfParsedLines *)_parseRange
{
    const char *start, *end;
    [self _rangeStart:&start end:&end];
    return stf_parse_general (_po, start, end);
}

- (NSInteger)columnCount
{
    GnmStfParsedLines *pl = [self _parseRange];
    unsigned columns = 0;
    if (pl) {
        for (unsigned i = 0; i < pl->lines->len; i++) {
            GPtrArray *line = g_ptr_array_index (pl->lines, i);
            columns = MAX (columns, line->len);
        }
        g_object_unref (pl);
    }
    return columns;
}

- (NSArray<NSString *> *)columnFormats
{
    /* One per column the current options produce: the guessed or set
     * ones, then general (the GTK format page's prepare). */
    NSInteger columns = self.columnCount;
    NSMutableArray *formats = [NSMutableArray arrayWithCapacity:MAX (columns, 0)];
    for (unsigned i = 0; i < _po->formats->len && (NSInteger) i < columns; i++) {
        GOFormat *format = g_ptr_array_index (_po->formats, i);
        [formats addObject:format ? [NSString stringWithUTF8String:go_format_as_XL (format)] : @"General"];
    }
    while ((NSInteger) formats.count < columns)
        [formats addObject:@"General"];
    return formats;
}

- (void)setColumnFormats:(NSArray<NSString *> *)formats
{
    /* The arrays free their elements themselves (stf-parse.c). */
    g_ptr_array_set_size (_po->formats, 0);
    for (NSString *text in formats) {
        GOFormat *format = text.length && ![text isEqualToString:@"General"]
            ? go_format_new_from_XL (text.UTF8String) : go_format_ref (go_format_general ());
        g_ptr_array_add (_po->formats, format);
    }
    /* The matching decimal, thousands, and currency guesses are for the
     * guessed formats only. */
    g_ptr_array_set_size (_po->formats_decimal, 0);
    g_ptr_array_set_size (_po->formats_thousand, 0);
    g_ptr_array_set_size (_po->formats_curr, 0);
}

- (void)guessColumnFormats
{
    const char *start, *end;
    [self _rangeStart:&start end:&end];
    /* The guess reads to the end of its string: a copy of the range. */
    char *range = g_strndup (start, end - start);
    stf_parse_options_guess_formats (_po, range);
    g_free (range);
}

- (NSArray<NSNumber *> *)importedColumns { return _importedColumns; }

- (void)setImportedColumns:(NSArray<NSNumber *> *)columns
{
    _importedColumns = [columns copy];
    g_free (_po->col_import_array);
    g_free (_po->col_autofit_array);
    _po->col_import_array = NULL;
    _po->col_autofit_array = NULL;
    _po->col_import_array_len = 0;
    if (columns.count == 0)
        return;
    _po->col_import_array_len = (unsigned) columns.count;
    _po->col_import_array = g_new (gboolean, columns.count);
    _po->col_autofit_array = g_new (gboolean, columns.count);
    for (unsigned i = 0; i < columns.count; i++) {
        _po->col_import_array[i] = columns[i].boolValue;
        _po->col_autofit_array[i] = TRUE;
    }
}

#pragma mark - Preview

- (NSArray<NSArray<NSString *> *> *)previewLines:(NSInteger)maxLines
{
    const char *start, *end;
    [self _rangeStart:&start end:&end];
    /* dialog-stf-csv-page.c parses its preview untrimmed */
    GnmStfTrimType trim = _po->trim_spaces;
    stf_parse_options_set_trim_spaces (_po, TRIM_TYPE_NEVER);
    const char *previewEnd = stf_parse_find_line (_po, start, (int) MAX (maxLines, 1));
    if (!previewEnd || previewEnd > end)
        previewEnd = end;
    GnmStfParsedLines *pl = stf_parse_general (_po, start, previewEnd);
    stf_parse_options_set_trim_spaces (_po, trim);
    NSMutableArray *lines = [NSMutableArray array];
    if (pl) {
        for (unsigned i = 0; i < pl->lines->len && (NSInteger) i < maxLines; i++) {
            GPtrArray *line = g_ptr_array_index (pl->lines, i);
            NSMutableArray *fields = [NSMutableArray arrayWithCapacity:line->len];
            for (unsigned j = 0; j < line->len; j++) {
                const char *field = g_ptr_array_index (line, j);
                [fields addObject:field ? [NSString stringWithUTF8String:field] : @""];
            }
            [lines addObject:fields];
        }
        g_object_unref (pl);
    }
    return lines;
}

#pragma mark - The import

- (GnmStfParseOptions *)_parseOptions { return _po; }

- (NSInteger)_importedColumnCountOf:(NSInteger)columns
{
    if (_importedColumns.count == 0)
        return columns;
    NSInteger count = 0;
    for (NSInteger i = 0; i < columns; i++)
        if (i >= (NSInteger) _importedColumns.count || _importedColumns[i].boolValue)
            count++;
    return count;
}

- (char *)_copyOfRange
{
    const char *start, *end;
    [self _rangeStart:&start end:&end];
    return g_strndup (start, end - start);
}

@end

/* stf.c cb_get_content: a cell's text for Text to Columns. */
static GnmValue *
cb_cell_text (GnmCellIter const *iter, GString *buffer)
{
    GnmCell *cell = iter->cell;
    if (cell) {
        char *tmp;
        if (gnm_cell_has_expr (cell))
            tmp = gnm_expr_top_as_string (cell->base.texpr, &iter->pp, iter->pp.sheet->convs);
        else if (VALUE_FMT (cell->value) != NULL)
            tmp = format_value (NULL, cell->value, -1, workbook_date_conv (iter->pp.wb));
        else
            tmp = value_get_as_string (cell->value);
        g_string_append (buffer, tmp);
        g_free (tmp);
    }
    g_string_append_c (buffer, '\n');
    return NULL;
}

@implementation GnmSheet (TextToColumns)

- (GnmTextImportSession *)textToColumnsSessionWithError:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmEngine *engine = self.workbook.engine;
    if (!sheet || !engine)
        return nil;
    GnmCellRange selection = self.selectedRange;
    if (selection.start.column != selection.end.column) {
        if (error)
            *error = [engine _errorWithCode:GnmErrorCommandFailed
                                description:@"Only one column of input data can be parsed at a time" collected:@[]];
        return nil;
    }
    GnmRange src;
    range_init (&src, (int) selection.start.column, (int) selection.start.row, (int) selection.end.column, (int) selection.end.row);
    GString *buffer = g_string_new (NULL);
    sheet_foreach_cell_in_range (sheet, CELL_ITER_ALL, &src, (CellIterFunc) cb_cell_text, buffer);
    /* As the engine does: no cells at all is no data (a column of empty
     * lines still counts as lines). */
    BOOL empty = YES;
    for (gsize i = 0; i < buffer->len && empty; i++)
        if (buffer->str[i] != '\n')
            empty = NO;
    if (empty) {
        g_string_free (buffer, TRUE);
        if (error)
            *error = [engine _errorWithCode:GnmErrorCommandFailed description:@"There is no data to convert" collected:@[]];
        return nil;
    }
    GnmTextImportSession *session = [[GnmTextImportSession alloc] initWithText:buffer name:@"Text to Columns" encoding:@"UTF-8" url:nil];
    return session;
}

- (BOOL)textToColumnsWithSession:(GnmTextImportSession *)session error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    if (!sheet || !workbook)
        return NO;
    GnmCellRange selection = self.selectedRange;
    GnmRange src, target;
    range_init (&src, (int) selection.start.column, (int) selection.start.row, (int) selection.end.column, (int) selection.end.row);
    target = src;
    range_translate (&target, sheet, 1, 0);   /* the columns to the right, as stf_text_to_columns does */

    GnmStfParseOptions *po = [session _parseOptions];
    char *text = [session _copyOfRange];
    GnmCellRegion *cr = stf_parse_region (po, text, NULL, sheet->workbook);
    g_free (text);
    if (cr == NULL) {
        if (error)
            *error = [workbook.engine _errorWithCode:GnmErrorCommandFailed
                                         description:@"Error while trying to parse data into sheet" collected:@[]];
        return NO;
    }
    /* dialog-stf.c stf_dialog_result_attach_formats_to_cr */
    unsigned targetcol = 0;
    for (unsigned col = 0; col < po->formats->len; col++) {
        if (po->col_import_array == NULL || po->col_import_array_len <= col || po->col_import_array[col]) {
            GOFormat *sf = g_ptr_array_index (po->formats, col);
            GnmRange r;
            range_init (&r, (int) targetcol, 0, (int) targetcol, cr->rows - 1);
            GnmStyle *style = gnm_style_new_default ();
            gnm_style_set_format (style, sf);
            cr->styles = g_slist_prepend (cr->styles, gnm_style_region_new (&r, style));
            gnm_style_unref (style);
            targetcol++;
        }
    }
    target.end.col = target.start.col + cr->cols - 1;
    target.end.row = target.start.row + cr->rows - 1;
    BOOL ok = [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_text_to_columns (wbc, &src, sheet, &target, sheet, cr);
    } description:@"Error while trying to parse data into sheet" error:error];
    return ok;
}

@end

@implementation GnmEngine (TextImport)

- (GnmWorkbook *)importTextSession:(GnmTextImportSession *)session error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GnmStfParseOptions *po = [session _parseOptions];
    char *text = [session _copyOfRange];

    /* stf.c stf_read_workbook after its dialog */
    int cols = (int) [session _importedColumnCountOf:session.columnCount];
    int rows = (int) (session.stopLine - session.startLine + 1);
    gnm_sheet_suggest_size (&cols, &rows);
    Workbook *book = workbook_new ();
    Sheet *sheet = sheet_new (book, session.name.UTF8String ?: "Sheet1", cols, rows);
    workbook_sheet_attach (book, sheet);
    if (!stf_parse_sheet (po, text, NULL, sheet, 0, 0)) {
        g_free (text);
        g_object_unref (book);
        if (error)
            *error = [self _errorWithCode:GnmErrorOpenFailed
                             description:@"Parse error while trying to parse data into sheet" collected:@[]];
        return nil;
    }
    g_free (text);
    workbook_recalc_all (book);
    {
        /* stf.c resize_columns */
        GnmRange r;
        range_init_full_sheet (&r, sheet);
        r.end.row = MIN (r.end.row, 1000);
        colrow_autofit (sheet, &r, TRUE, TRUE, TRUE, TRUE, NULL, NULL, TRUE);
        sheet_queue_respan (sheet, 0, gnm_sheet_get_last_row (sheet));
    }
    if (po->cols_exceeded || po->rows_exceeded)
        [self _reportMessage:@"Some data did not fit on the sheet and was dropped." details:nil];
    workbook_set_saveinfo (book, GO_FILE_FL_WRITE_ONLY, go_file_saver_for_id ("Gnumeric_stf:stf_assistant"));
    if (session.url) {
        char *uri = session.url.isFileURL ? go_shell_arg_to_uri (session.url.path.fileSystemRepresentation)
                                          : g_strdup (session.url.absoluteString.UTF8String);
        go_doc_set_uri (GO_DOC (book), uri);
        g_free (uri);
    }
    go_doc_set_dirty (GO_DOC (book), FALSE);

    WorkbookView *wbv = workbook_view_new (book);   /* consumes the workbook reference */
    return [[GnmWorkbook alloc] initWithWorkbookView:wbv engine:self];
}

@end
