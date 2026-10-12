// Defined names as dialog-define-names.c handles them: listed from the
// workbook's and the sheet's collections, parsed relative to the edit
// position, and changed through the engine's commands.
#import "GnmPrivate.h"
#include <expr-name.h>
#include <expr.h>

@interface GnmDefinedName ()
- (instancetype)initWithExpression:(GnmNamedExpr *)nexpr scope:(nullable GnmSheet *)scope text:(NSString *)text;
@property (nonatomic, readonly) GnmNamedExpr *expression;
@end

@implementation GnmDefinedName {
    GnmNamedExpr *_nexpr;
}

- (instancetype)initWithExpression:(GnmNamedExpr *)nexpr scope:(GnmSheet *)scope text:(NSString *)text
{
    if (!(self = [super init]))
        return nil;
    _nexpr = expr_name_ref (nexpr);
    _name = [NSString stringWithUTF8String:expr_name_name (nexpr)];
    _scope = scope;
    _expressionText = [text copy];
    _editable = !nexpr->is_permanent;
    return self;
}

- (void)dealloc
{
    if (_nexpr)
        expr_name_unref (_nexpr);
}

- (GnmNamedExpr *)expression { return _nexpr; }
- (BOOL)isInUse { return expr_name_in_use (_nexpr); }

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@ [%@] = %@>", self.class, _name, _scope ? _scope.name : @"workbook", _expressionText];
}

@end

/* The parse position of the GTK dialog: the sheet's edit position, on
 * the sheet or on none for the workbook scope. */
static void
parse_position (GnmParsePos *pp, GnmWorkbook *workbook, GnmSheet *sheet, GnmSheet *scope)
{
    GnmCellCoordinate edit = sheet.editPosition;
    parse_pos_init (pp, workbook.engineWorkbook, scope ? scope.engineSheet : NULL, (int) edit.column, (int) edit.row);
}

static void
cb_collect_name (G_GNUC_UNUSED gconstpointer key, gpointer value, gpointer accum)
{
    GnmNamedExpr *nexpr = value;
    if (nexpr->is_hidden || expr_name_is_placeholder (nexpr))
        return;
    *(GList **) accum = g_list_prepend (*(GList **) accum, nexpr);
}

@implementation GnmWorkbook (Names)

- (NSArray<GnmDefinedName *> *)definedNamesForSheet:(GnmSheet *)sheet
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    NSMutableArray *names = [NSMutableArray array];
    Sheet *engineSheet = sheet.engineSheet;
    if (!engineSheet || sheet.workbook != self)
        return names;
    GnmParsePos pp;
    parse_position (&pp, self, sheet, sheet);
    GnmConventions const *convs = sheet_get_conventions (engineSheet);

    GList *list = NULL;
    workbook_foreach_name (self.engineWorkbook, TRUE, (GHFunc) cb_collect_name, &list);
    gnm_sheet_foreach_name (engineSheet, (GHFunc) cb_collect_name, &list);
    list = g_list_sort (list, (GCompareFunc) expr_name_cmp_by_name);
    for (GList *l = list; l; l = l->next) {
        GnmNamedExpr *nexpr = l->data;
        char *text = expr_name_as_string (nexpr, &pp, convs);
        GnmSheet *scope = nexpr->pos.sheet ? [self wrapperForEngineSheet:nexpr->pos.sheet] : nil;
        [names addObject:[[GnmDefinedName alloc] initWithExpression:nexpr scope:scope
                                                               text:text ? [NSString stringWithUTF8String:text] : @""]];
        g_free (text);
    }
    g_list_free (list);
    return names;
}

- (BOOL)defineName:(NSString *)name expression:(NSString *)text scope:(GnmSheet *)scope inSheet:(GnmSheet *)sheet error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!expr_name_validate (trimmed.UTF8String ?: "")) {
        if (error)
            *error = [self.engine _errorWithCode:GnmErrorCommandFailed
                                     description:[NSString stringWithFormat:@"“%@” is not a valid name.", trimmed] collected:@[]];
        return NO;
    }
    if (text.length == 0) {
        if (error)
            *error = [self.engine _errorWithCode:GnmErrorCommandFailed
                                     description:@"Why would you want to define a name for the empty string?" collected:@[]];
        return NO;
    }
    GnmParsePos pp;
    parse_position (&pp, self, sheet, scope);
    GnmParseError perr;
    GnmExprTop const *texpr = gnm_expr_parse_str (text.UTF8String, &pp,
                                                  GNM_EXPR_PARSE_DEFAULT | GNM_EXPR_PARSE_UNKNOWN_NAMES_ARE_INVALID
                                                  | GNM_EXPR_PARSE_PERMIT_MULTIPLE_EXPRESSIONS,
                                                  NULL, parse_error_init (&perr));
    if (texpr == NULL) {
        NSString *message = perr.err ? [NSString stringWithUTF8String:perr.err->message] : @"The expression could not be read.";
        parse_error_free (&perr);
        if (error)
            *error = [self.engine _errorWithCode:GnmErrorCommandFailed description:message collected:@[]];
        return NO;
    }
    parse_error_free (&perr);
    /* cmd_define_name takes the expression reference. */
    BOOL ok = [self _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_define_name (wbc, trimmed.UTF8String, &pp, texpr, NULL);
    } description:[NSString stringWithFormat:@"Could not define the name “%@”.", trimmed] error:error];
    return ok;
}

- (BOOL)removeName:(GnmDefinedName *)name error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GnmNamedExpr *nexpr = name.expression;
    return [self _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_remove_name (wbc, nexpr);
    } description:[NSString stringWithFormat:@"Could not remove the name “%@”.", name.name] error:error];
}

- (BOOL)changeScopeOfName:(GnmDefinedName *)name toSheet:(GnmSheet *)scope error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GnmNamedExpr *nexpr = name.expression;
    Sheet *target = scope.engineSheet;
    return [self _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_rescope_name (wbc, nexpr, target);
    } description:[NSString stringWithFormat:@"Could not change the scope of “%@”.", name.name] error:error];
}

@end
