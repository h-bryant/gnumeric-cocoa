// Validation as dialog-cell-format.c builds it (gnm_validation_new on a
// partial style, applied to the selection), as wbc-gtk-edit.c checks an
// entry (a temporary assignment, gnm_validation_eval, the undo), and as
// gnm-validation-combo-view.c lists a source's values.
#import "GnmPrivate.h"
#include <validation.h>
#include <input-msg.h>
#include <expr.h>

@implementation GnmCellValidation

- (instancetype)init
{
    if (!(self = [super init]))
        return nil;
    _kind = GnmValidationKindAny;
    _op = GnmValidationOperatorBetween;
    _firstExpression = @"";
    _secondExpression = @"";
    _allowsBlank = YES;
    _usesDropdown = YES;
    _action = GnmValidationActionStop;
    _errorTitle = @"";
    _errorMessage = @"";
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    GnmCellValidation *copy = [[GnmCellValidation allocWithZone:zone] init];
    copy.kind = _kind;
    copy.op = _op;
    copy.firstExpression = _firstExpression;
    copy.secondExpression = _secondExpression;
    copy.allowsBlank = _allowsBlank;
    copy.usesDropdown = _usesDropdown;
    copy.action = _action;
    copy.errorTitle = _errorTitle;
    copy.errorMessage = _errorMessage;
    return copy;
}

+ (NSInteger)operandCountForKind:(GnmValidationKind)kind operator:(GnmValidationOperator)op
{
    switch (kind) {
    case GnmValidationKindAny: return 0;
    case GnmValidationKindInList:
    case GnmValidationKindCustom: return 1;
    default: return op == GnmValidationOperatorBetween || op == GnmValidationOperatorNotBetween ? 2 : 1;
    }
}

+ (NSString *)firstOperandLabelForKind:(GnmValidationKind)kind operator:(GnmValidationOperator)op
{
    /* cb_validation_sensitivity's labels */
    switch (kind) {
    case GnmValidationKindAny: return nil;
    case GnmValidationKindInList: return @"Source";
    case GnmValidationKindCustom: return @"Criteria";
    default:
        switch (op) {
        case GnmValidationOperatorBetween:
        case GnmValidationOperatorNotBetween:
        case GnmValidationOperatorGreaterThan:
        case GnmValidationOperatorGreaterOrEqual: return @"Min:";
        case GnmValidationOperatorEqual:
        case GnmValidationOperatorNotEqual: return @"Value:";
        case GnmValidationOperatorLessThan:
        case GnmValidationOperatorLessOrEqual: return @"Max:";
        }
    }
    return nil;
}

+ (NSString *)labelForKind:(GnmValidationKind)kind
{
    switch (kind) {
    case GnmValidationKindAny: return @"Any Value     (no validation)";
    case GnmValidationKindWholeNumber: return @"Whole numbers";
    case GnmValidationKindNumber: return @"Numbers";
    case GnmValidationKindInList: return @"In a list";
    case GnmValidationKindDate: return @"Date";
    case GnmValidationKindTime: return @"Time";
    case GnmValidationKindTextLength: return @"Text length";
    case GnmValidationKindCustom: return @"Custom";
    }
    return @"";
}

+ (NSString *)labelForOperator:(GnmValidationOperator)op
{
    switch (op) {
    case GnmValidationOperatorBetween: return @"between";
    case GnmValidationOperatorNotBetween: return @"not between";
    case GnmValidationOperatorEqual: return @"equal to";
    case GnmValidationOperatorNotEqual: return @"not equal to";
    case GnmValidationOperatorGreaterThan: return @"greater than";
    case GnmValidationOperatorLessThan: return @"less than";
    case GnmValidationOperatorGreaterOrEqual: return @"greater than or equal to";
    case GnmValidationOperatorLessOrEqual: return @"less than or equal to";
    }
    return @"";
}

+ (NSString *)labelForAction:(GnmValidationAction)action
{
    /* validation_error_actions */
    switch (action) {
    case GnmValidationActionNone: return @"None (silently accept invalid input)";
    case GnmValidationActionStop: return @"Stop (never allow invalid input)";
    case GnmValidationActionWarning: return @"Warning (accept/discard invalid input)";
    case GnmValidationActionInformation: return @"Information (allow invalid input)";
    case GnmValidationActionParseError: return @"Parse error";
    }
    return @"";
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ kind %ld op %ld '%@' '%@' action %ld>", self.class, (long) _kind, (long) _op,
            _firstExpression, _secondExpression, (long) _action];
}

@end

@implementation GnmInputMessage

- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message
{
    if (!(self = [super init]))
        return nil;
    _title = [title copy];
    _message = [message copy];
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[GnmInputMessage allocWithZone:zone] initWithTitle:_title message:_message];
}

@end

@implementation GnmSheet (Validation)

- (GnmCellValidation *)validationAtColumn:(NSInteger)column row:(NSInteger)row
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    if (!sheet)
        return nil;
    GnmStyle const *style = sheet_style_get (sheet, (int) column, (int) row);
    GnmValidation const *v = gnm_style_get_validation (style);
    if (!v)
        return nil;
    GnmCellValidation *result = [[GnmCellValidation alloc] init];
    result.kind = (GnmValidationKind) v->type;
    result.op = v->op == GNM_VALIDATION_OP_NONE ? GnmValidationOperatorBetween : (GnmValidationOperator) v->op;
    result.allowsBlank = v->allow_blank;
    result.usesDropdown = v->use_dropdown;
    result.action = (GnmValidationAction) v->style;
    result.errorTitle = v->title ? [NSString stringWithUTF8String:v->title->str] : @"";
    result.errorMessage = v->msg ? [NSString stringWithUTF8String:v->msg->str] : @"";
    /* fmt_dialog_init_validation_page loads them at the edit position */
    GnmParsePos pp;
    GnmCellCoordinate edit = self.editPosition;
    parse_pos_init (&pp, sheet->workbook, sheet, (int) edit.column, (int) edit.row);
    GnmConventions const *convs = sheet_get_conventions (sheet);
    for (unsigned i = 0; i < 2; i++) {
        GnmExprTop const *texpr = dependent_managed_get_expr (&v->deps[i]);
        if (!texpr)
            continue;
        char *text = gnm_expr_top_as_string (texpr, &pp, convs);
        NSString *s = text ? [NSString stringWithUTF8String:text] : @"";
        g_free (text);
        if (i == 0)
            result.firstExpression = s;
        else
            result.secondExpression = s;
    }
    return result;
}

- (GnmInputMessage *)inputMessageAtColumn:(NSInteger)column row:(NSInteger)row
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    if (!sheet)
        return nil;
    GnmInputMsg *msg = gnm_style_get_input_msg (sheet_style_get (sheet, (int) column, (int) row));
    if (!msg)
        return nil;
    return [[GnmInputMessage alloc] initWithTitle:GnmString (gnm_input_msg_get_title (msg))
                                          message:GnmString (gnm_input_msg_get_msg (msg))];
}

- (BOOL)setValidation:(GnmCellValidation *)validation inputMessage:(GnmInputMessage *)message error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    if (!sheet || !workbook)
        return NO;
    GnmStyle *style = gnm_style_new ();
    /* validation_rebuild_validation: Any Value means none */
    if (validation && validation.kind != GnmValidationKindAny) {
        GnmParsePos pp;
        GnmCellCoordinate edit = self.editPosition;
        parse_pos_init (&pp, sheet->workbook, sheet, (int) edit.column, (int) edit.row);
        GnmExprTop const *texpr[2] = { NULL, NULL };
        NSInteger operands = [GnmCellValidation operandCountForKind:validation.kind operator:validation.op];
        for (NSInteger k = 0; k < operands; k++) {
            NSString *text = k == 0 ? validation.firstExpression : validation.secondExpression;
            GnmParseError perr;
            texpr[k] = text.length ? gnm_expr_parse_str (text.UTF8String, &pp, GNM_EXPR_PARSE_DEFAULT, NULL, parse_error_init (&perr)) : NULL;
            if (!texpr[k]) {
                NSString *why = text.length == 0
                    ? [NSString stringWithFormat:@"The validation needs %@.", k == 0 ? @"a first value" : @"a second value"]
                    : (perr.err ? [NSString stringWithUTF8String:perr.err->message] : @"The expression could not be read.");
                if (text.length)
                    parse_error_free (&perr);
                if (texpr[0])
                    gnm_expr_top_unref (texpr[0]);
                gnm_style_unref (style);
                if (error)
                    *error = [workbook.engine _errorWithCode:GnmErrorCommandFailed description:why collected:@[]];
                return NO;
            }
            parse_error_free (&perr);
        }
        BOOL opless = validation.kind == GnmValidationKindInList || validation.kind == GnmValidationKindCustom;
        gnm_style_set_validation (style, gnm_validation_new ((ValidationStyle) validation.action, (ValidationType) validation.kind,
                                                             opless ? GNM_VALIDATION_OP_NONE : (ValidationOp) validation.op, sheet,
                                                             validation.errorTitle.UTF8String, validation.errorMessage.UTF8String,
                                                             texpr[0], texpr[1], validation.allowsBlank, validation.usesDropdown));
        /* gnm_validation_new took the expressions */
    } else
        gnm_style_set_validation (style, NULL);
    gnm_style_set_input_msg (style, message ? gnm_input_msg_new (message.message.UTF8String, message.title.UTF8String) : NULL);
    return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_selection_format (wbc, style, NULL, "Set validation");
    } description:@"Could not set the validation." error:error];
}

- (GnmValidationStatus)validateText:(NSString *)text atColumn:(NSInteger)column row:(NSInteger)row
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    if (!sheet || !workbook)
        return GnmValidationStatusValid;
    GnmStyle const *style = sheet_style_get (sheet, (int) column, (int) row);
    GnmValidation const *v = gnm_style_get_validation (style);
    if (!v || v->type == GNM_VALIDATION_TYPE_ANY)
        return GnmValidationStatusValid;
    /* wbcg_edit_finish's WBC_EDIT_ACCEPT case */
    GnmCellPos pos = { (int) column, (int) row };
    GnmRange r;
    range_init_cellpos (&r, &pos);
    GOUndo *u = clipboard_copy_range_undo (sheet, &r);
    GnmCell *cell = sheet_cell_fetch (sheet, pos.col, pos.row);
    sheet_cell_set_text (cell, text.UTF8String, NULL);
    gboolean showed = FALSE;
    ValidationStatus status = gnm_validation_eval (workbook.control, style, sheet, &pos, &showed);
    go_undo_undo (u);
    g_object_unref (u);
    return (GnmValidationStatus) status;
}

typedef struct {
    GHashTable *hash;
    GODateConventions const *date_conv;
} UniqueCollection;

static GnmValue *
cb_collect_unique (GnmValueIter const *iter, UniqueCollection *uc)
{
    GOFormat const *fmt = iter->cell_iter ? gnm_cell_get_format (iter->cell_iter->cell) : NULL;
    g_hash_table_replace (uc->hash, value_dup (iter->v), format_value (fmt, iter->v, -1, uc->date_conv));
    return NULL;
}

static void
cb_hash_domain (GnmValue *key, gpointer value, gpointer accum)
{
    g_ptr_array_add (accum, key);
}

- (NSArray<NSString *> *)validationChoicesAtColumn:(NSInteger)column row:(NSInteger)row
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    if (!sheet)
        return nil;
    GnmValidation const *val = gnm_style_get_validation (sheet_style_get (sheet, (int) column, (int) row));
    if (!val || val->type != GNM_VALIDATION_TYPE_IN_LIST || !val->use_dropdown)
        return nil;
    GnmExprTop const *texpr = dependent_managed_get_expr (&val->deps[0]);
    if (!texpr)
        return nil;
    /* vcombo_create_list */
    GnmEvalPos ep;
    eval_pos_init (&ep, sheet, (int) column, (int) row);
    GnmValue *v = gnm_expr_top_eval_fake_array (texpr, &ep, GNM_EXPR_EVAL_PERMIT_NON_SCALAR | GNM_EXPR_EVAL_PERMIT_EMPTY);
    if (!v)
        return nil;
    UniqueCollection uc;
    uc.date_conv = sheet_date_conv (sheet);
    uc.hash = g_hash_table_new_full ((GHashFunc) value_hash, (GEqualFunc) value_equal,
                                     (GDestroyNotify) value_release, (GDestroyNotify) g_free);
    value_area_foreach (v, &ep, CELL_ITER_IGNORE_BLANK, (GnmValueIterFunc) cb_collect_unique, &uc);
    value_release (v);
    GPtrArray *sorted = g_ptr_array_new ();
    g_hash_table_foreach (uc.hash, (GHFunc) cb_hash_domain, sorted);
    g_ptr_array_sort (sorted, value_cmp);
    NSMutableArray *choices = [NSMutableArray arrayWithCapacity:sorted->len];
    for (unsigned i = 0; i < sorted->len; i++) {
        char const *label = g_hash_table_lookup (uc.hash, g_ptr_array_index (sorted, i));
        [choices addObject:GnmString (label)];
    }
    g_ptr_array_free (sorted, TRUE);
    g_hash_table_destroy (uc.hash);
    return choices;
}

@end
