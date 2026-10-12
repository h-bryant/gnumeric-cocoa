// Find and Replace over the engine's search: GnmSearchReplace objects
// built the way dialog-search.c and dialog-search-replace.c build them,
// matches collected as the Search dialog lists them, and the replace
// command with its query function answered by a block.
#import "GnmPrivate.h"
#include <search.h>

/* The engine answers its own questions with GTK's response codes (search.c,
 * commands.c), which reach it through goffice's headers. */
#ifndef GTK_RESPONSE_YES
#define GTK_RESPONSE_YES (-8)
#define GTK_RESPONSE_NO (-9)
#define GTK_RESPONSE_CANCEL (-6)
#endif

@implementation GnmSearchOptions

- (instancetype)init
{
    if (!(self = [super init]))
        return nil;
    /* gnumeric-conf.c defaults: the GTK dialogs start from these. */
    _searchText = @"";
    _replaceText = @"";
    _scope = GnmSearchScopeWorkbook;
    _rangeText = @"";
    _textKind = GnmSearchTextPlain;
    _ignoresCase = YES;
    _matchesWholeWords = NO;
    _preservesCase = NO;
    _searchesStrings = YES;
    _searchesOtherValues = YES;
    _searchesExpressions = YES;
    _searchesExpressionResults = YES;
    _searchesComments = NO;
    _byRow = NO;   /* "columnmajor" defaults to true */
    _asksBeforeEachChange = NO;
    _keepsStrings = YES;
    _errorBehavior = GnmSearchErrorFail;
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    GnmSearchOptions *copy = [[GnmSearchOptions allocWithZone:zone] init];
    copy.searchText = _searchText;
    copy.replaceText = _replaceText;
    copy.scope = _scope;
    copy.rangeText = _rangeText;
    copy.textKind = _textKind;
    copy.ignoresCase = _ignoresCase;
    copy.matchesWholeWords = _matchesWholeWords;
    copy.preservesCase = _preservesCase;
    copy.searchesStrings = _searchesStrings;
    copy.searchesOtherValues = _searchesOtherValues;
    copy.searchesExpressions = _searchesExpressions;
    copy.searchesExpressionResults = _searchesExpressionResults;
    copy.searchesComments = _searchesComments;
    copy.byRow = _byRow;
    copy.asksBeforeEachChange = _asksBeforeEachChange;
    copy.keepsStrings = _keepsStrings;
    copy.errorBehavior = _errorBehavior;
    return copy;
}

@end

@interface GnmSearchMatch ()
- (instancetype)initWithSheet:(GnmSheet *)sheet column:(NSInteger)column row:(NSInteger)row locus:(GnmSearchMatchLocus)locus
                     cellName:(NSString *)cellName reference:(NSString *)reference kind:(NSString *)kind contents:(NSString *)contents;
@end

@implementation GnmSearchMatch

- (instancetype)initWithSheet:(GnmSheet *)sheet column:(NSInteger)column row:(NSInteger)row locus:(GnmSearchMatchLocus)locus
                     cellName:(NSString *)cellName reference:(NSString *)reference kind:(NSString *)kind contents:(NSString *)contents
{
    if (!(self = [super init]))
        return nil;
    _sheet = sheet;
    _column = column;
    _row = row;
    _locus = locus;
    _cellName = [cellName copy];
    _reference = [reference copy];
    _kindDescription = [kind copy];
    _contents = [contents copy];
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@ %@ '%@'>", self.class, _reference, _kindDescription, _contents];
}

@end

@interface GnmSearchQuery ()
- (instancetype)initWithSheet:(GnmSheet *)sheet column:(NSInteger)column row:(NSInteger)row comment:(BOOL)comment
                     location:(NSString *)location oldText:(NSString *)oldText newText:(NSString *)newText;
@end

@implementation GnmSearchQuery

- (instancetype)initWithSheet:(GnmSheet *)sheet column:(NSInteger)column row:(NSInteger)row comment:(BOOL)comment
                     location:(NSString *)location oldText:(NSString *)oldText newText:(NSString *)newText
{
    if (!(self = [super init]))
        return nil;
    _sheet = sheet;
    _column = column;
    _row = row;
    _isComment = comment;
    _location = [location copy];
    _currentText = [oldText copy];
    _replacementText = [newText copy];
    _asksAgain = YES;
    return self;
}

@end

#pragma mark - Building the engine's object

static NSString *
string_or_empty (const char *s)
{
    return s ? [NSString stringWithUTF8String:s] : @"";
}

/* As dialog-search.c search_clicked and dialog-search-replace.c
 * apply_clicked build theirs. */
static GnmSearchReplace *
make_search_replace (GnmSearchOptions *options, Sheet *sheet, BOOL replacing)
{
    char *search = gnm_search_normalize (options.searchText.UTF8String ?: "");
    char *replace = gnm_search_normalize (options.replaceText.UTF8String ?: "");
    GnmSearchReplace *sr = g_object_new (GNM_SEARCH_REPLACE_TYPE,
                                         "sheet", sheet,
                                         "scope", (int) options.scope,
                                         "range-text", options.rangeText.UTF8String ?: "",
                                         "search-text", search,
                                         "replace-text", replace,
                                         "is-regexp", options.textKind == GnmSearchTextRegularExpression,
                                         "is-number", !replacing && options.textKind == GnmSearchTextNumber,
                                         "ignore-case", (gboolean) options.ignoresCase,
                                         "match-words", (gboolean) options.matchesWholeWords,
                                         "preserve-case", (gboolean) options.preservesCase,
                                         "query", (gboolean) options.asksBeforeEachChange,
                                         "replace-keep-strings", (gboolean) options.keepsStrings,
                                         "search-strings", (gboolean) options.searchesStrings,
                                         "search-other-values", (gboolean) options.searchesOtherValues,
                                         "search-expressions", (gboolean) options.searchesExpressions,
                                         "search-expression-results", replacing ? FALSE : (gboolean) options.searchesExpressionResults,
                                         "search-comments", (gboolean) options.searchesComments,
                                         "by-row", (gboolean) options.byRow,
                                         NULL);
    sr->error_behaviour = (GnmSearchReplaceError) options.errorBehavior;
    g_free (search);
    g_free (replace);
    return sr;
}

/* The two checks both dialogs make before searching (the verify covers
 * bad patterns and ranges); nil when fine. */
static NSString *
check_search_replace (GnmSearchReplace *sr, BOOL replacing)
{
    char *err = gnm_search_replace_verify (sr, replacing);
    if (err) {
        NSString *message = string_or_empty (err);
        g_free (err);
        return message;
    }
    if (!sr->search_strings && !sr->search_other_values && !sr->search_expressions
        && !sr->search_expression_results && !sr->search_comments)
        return @"You must select some cell types to search.";
    return nil;
}

static NSString *
cell_kind_description (GnmCell *cell)
{
    if (!cell)
        return @"Deleted";
    if (gnm_cell_has_expr (cell))
        return @"Expression";
    GnmValue *v = cell->value;
    BOOL is_value = !gnm_cell_is_empty (cell) && v;
    if (is_value && VALUE_IS_STRING (v))
        return @"String";
    if (is_value && VALUE_IS_FLOAT (v))
        return @"Number";
    return @"Other value";
}

static NSString *
quoted_reference (Sheet *sheet, GnmCellPos const *pos)
{
    return [NSString stringWithFormat:@"%s!%s", sheet->name_quoted, cellpos_as_string (pos)];
}

#pragma mark - The query function

typedef struct {
    __unsafe_unretained GnmWorkbook *workbook;
    __unsafe_unretained GnmSearchQueryHandler handler;
    /* The test run's refusal (GNM_SRQ_FAIL), for the error. */
    __unsafe_unretained NSString *failure;
    __strong NSString *failureStorage;
} QueryContext;

static int
answer_query (QueryContext *ctx, GnmSearchReplace *sr, GnmSearchQuery *query)
{
    if (!ctx->handler)
        return GTK_RESPONSE_YES;
    GnmSearchQueryAnswer answer = ctx->handler (query);
    switch (answer) {
    case GnmSearchQueryReplace:
        sr->query = query.asksAgain;
        return GTK_RESPONSE_YES;
    case GnmSearchQuerySkip:
        sr->query = query.asksAgain;
        return GTK_RESPONSE_NO;
    case GnmSearchQueryCancel:
    default:
        return GTK_RESPONSE_CANCEL;
    }
}

static int
cb_search_query (GnmSearchReplaceQuery q, GnmSearchReplace *sr, ...)
{
    QueryContext *ctx = sr->user_data;
    va_list ap;
    va_start (ap, sr);
    int res = GTK_RESPONSE_CANCEL;
    switch (q) {
    case GNM_SRQ_FAIL: {
        GnmCell *cell = va_arg (ap, GnmCell *);
        char const *old_text = va_arg (ap, char const *);
        char const *new_text = va_arg (ap, char const *);
        /* wbc-gtk-actions.c's wording */
        ctx->failureStorage = [NSString stringWithFormat:
            @"In cell %s, the current contents\n        %s\nwould have been replaced by\n        %s\nwhich is invalid.\n\n"
             "The replace has been aborted and nothing has been changed.",
            cell_name (cell), old_text ?: "", new_text ?: ""];
        ctx->failure = ctx->failureStorage;
        res = GTK_RESPONSE_NO;
        break;
    }
    case GNM_SRQ_QUERY: {
        GnmCell *cell = va_arg (ap, GnmCell *);
        char const *old_text = va_arg (ap, char const *);
        char const *new_text = va_arg (ap, char const *);
        Sheet *sheet = cell->base.sheet;
        GnmSheet *wrapper = [ctx->workbook wrapperForEngineSheet:sheet];
        NSString *location = [NSString stringWithFormat:@"%s!%s", sheet->name_unquoted, cell_name (cell)];
        GnmSearchQuery *query = [[GnmSearchQuery alloc] initWithSheet:wrapper column:cell->pos.col row:cell->pos.row comment:NO
                                                             location:location oldText:string_or_empty (old_text)
                                                              newText:string_or_empty (new_text)];
        res = wrapper ? answer_query (ctx, sr, query) : GTK_RESPONSE_YES;
        break;
    }
    case GNM_SRQ_QUERY_COMMENT: {
        Sheet *sheet = va_arg (ap, Sheet *);
        GnmCellPos *cp = va_arg (ap, GnmCellPos *);
        char const *old_text = va_arg (ap, char const *);
        char const *new_text = va_arg (ap, char const *);
        GnmSheet *wrapper = [ctx->workbook wrapperForEngineSheet:sheet];
        NSString *location = [NSString stringWithFormat:@"Comment in cell %s!%s", sheet->name_unquoted, cellpos_as_string (cp)];
        GnmSearchQuery *query = [[GnmSearchQuery alloc] initWithSheet:wrapper column:cp->col row:cp->row comment:YES
                                                             location:location oldText:string_or_empty (old_text)
                                                              newText:string_or_empty (new_text)];
        res = wrapper ? answer_query (ctx, sr, query) : GTK_RESPONSE_YES;
        break;
    }
    default:
        break;
    }
    va_end (ap);
    return res;
}

#pragma mark - The workbook's side

@implementation GnmWorkbook (Search)

- (NSArray<GnmSearchMatch *> *)findMatches:(GnmSearchOptions *)options inSheet:(GnmSheet *)sheet error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *engineSheet = sheet.engineSheet;
    if (!engineSheet || sheet.workbook != self) {
        if (error)
            *error = [self.engine _errorWithCode:GnmErrorCommandFailed description:@"The sheet is gone." collected:@[]];
        return nil;
    }
    GnmSearchReplace *sr = make_search_replace (options, engineSheet, NO);
    NSString *problem = check_search_replace (sr, NO);
    if (problem) {
        g_object_unref (sr);
        if (error)
            *error = [self.engine _errorWithCode:GnmErrorCommandFailed description:problem collected:@[]];
        return nil;
    }

    GPtrArray *cells = gnm_search_collect_cells (sr);
    GPtrArray *matches = gnm_search_filter_matching (sr, cells);
    gnm_search_collect_cells_free (cells);

    NSMutableArray<GnmSearchMatch *> *result = [NSMutableArray arrayWithCapacity:matches->len];
    for (unsigned i = 0; i < matches->len; i++) {
        GnmSearchFilterResult *m = g_ptr_array_index (matches, i);
        GnmSheet *wrapper = [self wrapperForEngineSheet:m->ep.sheet];
        if (!wrapper)
            continue;
        GnmCell *cell = m->locus == GNM_SRL_COMMENT ? NULL
                      : sheet_cell_get (m->ep.sheet, m->ep.eval.col, m->ep.eval.row);
        GnmComment *comment = m->locus == GNM_SRL_COMMENT ? sheet_get_comment (m->ep.sheet, &m->ep.eval) : NULL;
        NSString *kind, *contents;
        GnmSearchMatchLocus locus;
        switch (m->locus) {
        case GNM_SRL_COMMENT:
            locus = GnmSearchMatchComment;
            kind = @"Comment";
            contents = comment ? string_or_empty (cell_comment_text_get (comment)) : @"Deleted";
            break;
        case GNM_SRL_VALUE:
            locus = GnmSearchMatchResult;
            kind = @"Result";
            contents = cell && cell->value ? string_or_empty (value_peek_string (cell->value)) : @"Deleted";
            break;
        case GNM_SRL_CONTENTS:
        default:
            locus = GnmSearchMatchContents;
            kind = cell_kind_description (cell);
            if (cell) {
                char *entered = gnm_cell_get_entered_text (cell);
                contents = string_or_empty (entered);
                g_free (entered);
            } else
                contents = @"Deleted";
            break;
        }
        [result addObject:[[GnmSearchMatch alloc] initWithSheet:wrapper column:m->ep.eval.col row:m->ep.eval.row locus:locus
                                                       cellName:string_or_empty (cellpos_as_string (&m->ep.eval))
                                                      reference:quoted_reference (m->ep.sheet, &m->ep.eval)
                                                           kind:kind contents:contents]];
    }
    gnm_search_filter_matching_free (matches);
    g_object_unref (sr);
    return result;
}

- (BOOL)replaceMatches:(GnmSearchOptions *)options inSheet:(GnmSheet *)sheet
          queryHandler:(GnmSearchQueryHandler)handler error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *engineSheet = sheet.engineSheet;
    if (!engineSheet || sheet.workbook != self) {
        if (error)
            *error = [self.engine _errorWithCode:GnmErrorCommandFailed description:@"The sheet is gone." collected:@[]];
        return NO;
    }
    GnmSearchReplace *sr = make_search_replace (options, engineSheet, YES);
    NSString *problem = check_search_replace (sr, YES);
    if (problem) {
        g_object_unref (sr);
        if (error)
            *error = [self.engine _errorWithCode:GnmErrorCommandFailed description:problem collected:@[]];
        return NO;
    }

    QueryContext ctx = { self, handler, nil, nil };
    sr->query_func = cb_search_query;
    sr->user_data = &ctx;
    NSError *commandError = nil;
    BOOL reported = NO;
    BOOL ok = [self _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_search_replace (wbc, sr);
    } description:@"Search and Replace" reported:&reported error:&commandError];
    sr->query_func = NULL;
    sr->user_data = NULL;
    g_object_unref (sr);
    if (ok)
        return YES;
    if (error) {
        if (ctx.failure && !reported)
            *error = [self.engine _errorWithCode:GnmErrorCommandFailed description:ctx.failure collected:@[]];
        else
            *error = commandError;
    }
    return NO;
}

@end
