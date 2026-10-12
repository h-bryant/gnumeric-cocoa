// Conditional formats as dialog-cell-format-cond.c builds and applies
// them: a GnmStyleCond per condition with its overlay and expressions, a
// GnmStyleConditions on a partial style, applied to the selection with
// cmd_selection_format.
#import "GnmPrivate.h"
#include <style-conditions.h>
#include <expr.h>

@implementation GnmConditionalFormat

- (instancetype)init
{
    if (!(self = [super init]))
        return nil;
    _op = GnmConditionGreaterThan;
    _firstExpression = @"";
    _secondExpression = @"";
    _format = [[GnmCellFormat alloc] init];
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    GnmConditionalFormat *copy = [[GnmConditionalFormat allocWithZone:zone] init];
    copy.op = _op;
    copy.firstExpression = _firstExpression;
    copy.secondExpression = _secondExpression;
    copy.format = _format;
    return copy;
}

+ (NSArray<NSNumber *> *)allOperators
{
    /* dialog-cell-format-cond.c's type store order */
    return @[@(GnmConditionContainsError), @(GnmConditionNotContainsError), @(GnmConditionContainsBlanks), @(GnmConditionNotContainsBlanks),
             @(GnmConditionEqual), @(GnmConditionNotEqual), @(GnmConditionGreaterThan), @(GnmConditionLessThan),
             @(GnmConditionGreaterOrEqual), @(GnmConditionLessOrEqual), @(GnmConditionCustom),
             @(GnmConditionContainsString), @(GnmConditionNotContainsString), @(GnmConditionBeginsWithString),
             @(GnmConditionNotBeginsWithString), @(GnmConditionEndsWithString), @(GnmConditionNotEndsWithString),
             @(GnmConditionBetween), @(GnmConditionNotBetween)];
}

+ (NSInteger)operandCountForOperator:(GnmConditionOperator)op
{
    switch (op) {
    case GnmConditionBetween:
    case GnmConditionNotBetween:
        return 2;
    case GnmConditionContainsError:
    case GnmConditionNotContainsError:
    case GnmConditionContainsBlanks:
    case GnmConditionNotContainsBlanks:
        return 0;
    default:
        return 1;
    }
}

+ (NSString *)labelForOperator:(GnmConditionOperator)op
{
    switch (op) {
    case GnmConditionContainsError: return @"Cell contains an error value.";
    case GnmConditionNotContainsError: return @"Cell does not contain an error value.";
    case GnmConditionContainsBlanks: return @"Cell contains whitespace.";
    case GnmConditionNotContainsBlanks: return @"Cell does not contain whitespace.";
    case GnmConditionEqual: return @"Cell value is = x.";
    case GnmConditionNotEqual: return @"Cell value is ≠ x.";
    case GnmConditionGreaterThan: return @"Cell value is > x.";
    case GnmConditionLessThan: return @"Cell value is < x.";
    case GnmConditionGreaterOrEqual: return @"Cell value is ≧ x.";
    case GnmConditionLessOrEqual: return @"Cell value is ≦ x.";
    case GnmConditionCustom: return @"Expression x evaluates to TRUE.";
    case GnmConditionContainsString: return @"Cell contains the string x.";
    case GnmConditionNotContainsString: return @"Cell does not contain the string x.";
    case GnmConditionBeginsWithString: return @"Cell value begins with the string x.";
    case GnmConditionNotBeginsWithString: return @"Cell value does not begin with the string x.";
    case GnmConditionEndsWithString: return @"Cell value ends with the string x.";
    case GnmConditionNotEndsWithString: return @"Cell value does not end with the string x.";
    case GnmConditionBetween: return @"Cell value is between x and y (incl.).";
    case GnmConditionNotBetween: return @"Cell value is not between x and y (incl.).";
    }
    return @"";
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %ld '%@' '%@'>", self.class, (long) _op, _firstExpression, _secondExpression];
}

@end

@implementation GnmSheet (ConditionalFormats)

- (NSArray<GnmConditionalFormat *> *)conditionalFormatsAtColumn:(NSInteger)column row:(NSInteger)row
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    NSMutableArray *result = [NSMutableArray array];
    Sheet *sheet = self.engineSheet;
    if (!sheet)
        return result;
    GnmStyle const *style = sheet_style_get (sheet, (int) column, (int) row);
    if (!gnm_style_is_element_set (style, MSTYLE_CONDITIONS))
        return result;
    GnmStyleConditions *sc = gnm_style_get_conditions (style);
    GPtrArray const *conds = sc ? gnm_style_conditions_details (sc) : NULL;
    if (!conds)
        return result;
    GnmParsePos pp;
    GnmCellCoordinate edit = self.editPosition;
    parse_pos_init (&pp, sheet->workbook, sheet, (int) edit.column, (int) edit.row);
    GnmConventions const *convs = sheet_get_conventions (sheet);
    for (unsigned i = 0; i < conds->len; i++) {
        GnmStyleCond const *cond = g_ptr_array_index (conds, i);
        GnmConditionalFormat *f = [[GnmConditionalFormat alloc] init];
        f.op = (GnmConditionOperator) cond->op;
        for (unsigned k = 0; k < 2; k++) {
            GnmExprTop const *texpr = gnm_style_cond_get_expr (cond, k);
            if (!texpr)
                continue;
            char *text = gnm_expr_top_as_string (texpr, &pp, convs);
            NSString *s = text ? [NSString stringWithUTF8String:text] : @"";
            g_free (text);
            if (k == 0)
                f.firstExpression = s;
            else
                f.secondExpression = s;
        }
        f.format = cond->overlay ? gnm_cocoa_format_from_style (cond->overlay) : [[GnmCellFormat alloc] init];
        [result addObject:f];
    }
    return result;
}

- (BOOL)setConditionalFormats:(NSArray<GnmConditionalFormat *> *)formats error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    if (!sheet || !workbook)
        return NO;
    GnmParsePos pp;
    GnmCellCoordinate edit = self.editPosition;
    parse_pos_init (&pp, sheet->workbook, sheet, (int) edit.column, (int) edit.row);

    GnmStyleConditions *sc = formats.count ? gnm_style_conditions_new (sheet) : NULL;
    for (GnmConditionalFormat *f in formats) {
        GnmStyleCond *cond = gnm_style_cond_new ((GnmStyleCondOp) f.op, sheet);
        GnmStyle *overlay = NULL;
        GnmBorder *borders[GNM_STYLE_BORDER_EDGE_MAX];
        gnm_cocoa_format_to_engine (f.format, &overlay, borders);
        for (int i = 0; i < GNM_STYLE_BORDER_EDGE_MAX; i++)
            if (borders[i])
                gnm_style_border_unref (borders[i]);   /* overlays carry no borders here */
        gnm_style_cond_set_overlay (cond, overlay);
        gnm_style_unref (overlay);
        NSInteger operands = [GnmConditionalFormat operandCountForOperator:f.op];
        for (NSInteger k = 0; k < operands; k++) {
            NSString *text = k == 0 ? f.firstExpression : f.secondExpression;
            GnmParseError perr;
            GnmExprTop const *texpr = text.length
                ? gnm_expr_parse_str (text.UTF8String, &pp, GNM_EXPR_PARSE_UNKNOWN_NAMES_ARE_STRINGS, NULL, parse_error_init (&perr))
                : NULL;
            if (!texpr) {
                NSString *message = text.length == 0
                    ? [NSString stringWithFormat:@"The condition “%@” needs %@.", [GnmConditionalFormat labelForOperator:f.op],
                       k == 0 ? @"a value for x" : @"a value for y"]
                    : (perr.err ? [NSString stringWithUTF8String:perr.err->message] : @"The expression could not be read.");
                if (text.length)
                    parse_error_free (&perr);
                gnm_style_cond_free (cond);
                if (sc)
                    g_object_unref (sc);
                if (error)
                    *error = [workbook.engine _errorWithCode:GnmErrorCommandFailed description:message collected:@[]];
                return NO;
            }
            parse_error_free (&perr);
            gnm_style_cond_set_expr (cond, texpr, (unsigned) k);
            gnm_expr_top_unref (texpr);
        }
        gnm_style_conditions_insert (sc, cond, -1);   /* copies it */
        gnm_style_cond_free (cond);
    }
    GnmStyle *style = gnm_style_new ();
    gnm_style_set_conditions (style, sc);   /* takes the reference, or none */
    return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_selection_format (wbc, style, NULL, "Set conditional formatting");
    } description:@"Could not set the conditional formatting." error:error];
}

@end
