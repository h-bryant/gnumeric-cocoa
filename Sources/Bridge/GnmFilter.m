// Autofilter buttons, conditions, and drop-down choices (GnmFilter.h).
// The conversions mirror the GTK combo (widgets/gnm-filter-combo-view.c)
// and its dialog (dialogs/dialog-autofilter.c).
#import "GnmPrivate.h"

@implementation GnmFilterButton {
    Sheet *_sheet;
}

- (instancetype)initWithFilter:(GnmFilter *)filter field:(unsigned)field sheet:(Sheet *)sheet
{
    if (!(self = [super init]))
        return nil;
    _filter = gnm_filter_ref (filter);
    _field = field;
    _sheet = sheet;
    GnmRange const *r = &filter->r;
    _cell = GnmCellCoordinateMake (r->start.col + field, r->start.row);
    _filterRange = GnmCellRangeMake (r->start.col, r->start.row, r->end.col, r->end.row);
    /* filter_view_set_bounds: a square of the cell's height, at most 20
     * pixels, inside the cell's bottom-right corner. */
    ColRowInfo const *ci = sheet_col_get_info (sheet, (int) _cell.column);
    ColRowInfo const *ri = sheet_row_get_info (sheet, (int) _cell.row);
    double right = sheet_colrow_get_distance_pixels (sheet, TRUE, 0, (int) _cell.column + 1);
    double bottom = sheet_colrow_get_distance_pixels (sheet, FALSE, 0, (int) _cell.row + 1);
    double h = MIN (ri->visible ? ri->size_pixels : 0, 20);
    double w = MIN (h, ci->visible ? ci->size_pixels : 0);
    _frame = CGRectMake (right - w, bottom - h, w, h);
    return self;
}

- (void)dealloc
{
    gnm_filter_unref (_filter);
}

- (BOOL)isAttached
{
    return _filter->sheet == _sheet && _field < _filter->fields->len;
}

- (BOOL)isActive
{
    if (!self.isAttached)
        return NO;
    GnmFilterCombo *fcombo = g_ptr_array_index (_filter->fields, _field);
    return fcombo->cond != NULL;
}

- (BOOL)isEqual:(id)object
{
    if (![object isKindOfClass:GnmFilterButton.class])
        return NO;
    GnmFilterButton *other = object;
    return other->_filter == _filter && other->_field == _field;
}

- (NSUInteger)hash
{
    return (NSUInteger) _filter ^ _field;
}

@end

/* ------------------------------------------------------------------------ */

@implementation GnmFilterCriterion {
    GnmValue *_value;
}

- (instancetype)initWithKind:(GnmFilterConditionKind)kind
{
    if (!(self = [super init]))
        return nil;
    _kind = kind;
    _valueIndex = -1;
    _valueText = @"";
    _firstText = @"";
    _secondText = @"";
    return self;
}

- (instancetype)initWithValue:(GnmValue *)value index:(NSInteger)index text:(NSString *)text
{
    if (!(self = [self initWithKind:GnmFilterConditionValue]))
        return nil;
    _value = value;
    _valueIndex = index;
    _valueText = [text copy];
    return self;
}

- (void)dealloc
{
    value_release (_value);
}

- (GnmValue const *)value { return _value; }

+ (instancetype)showAll
{
    return [[self alloc] initWithKind:GnmFilterConditionShowAll];
}

+ (instancetype)blanks:(BOOL)blanks
{
    return [[self alloc] initWithKind:blanks ? GnmFilterConditionBlanks : GnmFilterConditionNonBlanks];
}

+ (instancetype)customWithOperator:(GnmFilterOperator)op text:(NSString *)text
{
    return [self customWithOperator:op text:text joinedWithAnd:YES operator:GnmFilterOperatorNone text:@""];
}

+ (instancetype)customWithOperator:(GnmFilterOperator)op0 text:(NSString *)text0 joinedWithAnd:(BOOL)and
                          operator:(GnmFilterOperator)op1 text:(NSString *)text1
{
    GnmFilterCriterion *c = [[self alloc] initWithKind:GnmFilterConditionCustom];
    c->_firstOperator = op0;
    c->_firstText = [text0 copy] ?: @"";
    c->_secondOperator = op1;
    c->_secondText = [text1 copy] ?: @"";
    c->_joinedWithAnd = and;
    return c;
}

+ (instancetype)bucketTop:(BOOL)top count:(double)count percent:(BOOL)percent
{
    GnmFilterCriterion *c = [[self alloc] initWithKind:GnmFilterConditionBucket];
    c->_top = top;
    c->_count = count;
    c->_percent = percent;
    return c;
}

/* The operator and text of one engine comparison: the wildcard forms
 * the GTK dialog writes ("abc*", "*abc", "*abc*") come back as the
 * text operators. */
static GnmFilterOperator
operator_from_engine (GnmFilterOp op, GnmValue const *v, NSString **text)
{
    char *str = v ? value_get_as_string (v) : g_strdup ("");
    size_t len = strlen (str);
    GnmFilterOperator result = GnmFilterOperatorNone;
    switch (op) {
    case GNM_FILTER_OP_GT: result = GnmFilterOperatorGreaterThan; break;
    case GNM_FILTER_OP_GTE: result = GnmFilterOperatorGreaterThanOrEqual; break;
    case GNM_FILTER_OP_LT: result = GnmFilterOperatorLessThan; break;
    case GNM_FILTER_OP_LTE: result = GnmFilterOperatorLessThanOrEqual; break;
    case GNM_FILTER_OP_EQUAL:
    case GNM_FILTER_OP_NOT_EQUAL: {
        BOOL negated = op == GNM_FILTER_OP_NOT_EQUAL;
        BOOL is_string = v != NULL && VALUE_IS_STRING (v);
        BOOL leading = is_string && len >= 2 && str[0] == '*';
        BOOL trailing = is_string && len >= 2 && str[len - 1] == '*';
        if (leading && trailing && len >= 3) {
            result = negated ? GnmFilterOperatorDoesNotContain : GnmFilterOperatorContains;
            str[len - 1] = '\0';
            memmove (str, str + 1, len - 1);
        } else if (trailing) {
            result = negated ? GnmFilterOperatorDoesNotBeginWith : GnmFilterOperatorBeginsWith;
            str[len - 1] = '\0';
        } else if (leading) {
            result = negated ? GnmFilterOperatorDoesNotEndWith : GnmFilterOperatorEndsWith;
            memmove (str, str + 1, len);
        } else {
            result = negated ? GnmFilterOperatorDoesNotEqual : GnmFilterOperatorEquals;
        }
        break;
    }
    default:
        break;
    }
    *text = GnmString (str);
    g_free (str);
    return result;
}

+ (instancetype)conditionFromEngine:(GnmFilterCondition const *)cond values:(GPtrArray *)values labels:(NSArray<NSString *> *)labels
{
    if (cond == NULL || cond->op[0] == GNM_FILTER_UNUSED)
        return [self showAll];
    GnmFilterOp op0 = cond->op[0];
    switch (op0 & GNM_FILTER_OP_TYPE_MASK) {
    case GNM_FILTER_OP_TYPE_BLANKS:
        return [self blanks:op0 == GNM_FILTER_OP_BLANKS];
    case GNM_FILTER_OP_TYPE_BUCKETS:
        return [self bucketTop:!(op0 & GNM_FILTER_OP_BOTTOM_MASK) count:cond->count
                       percent:(op0 & GNM_FILTER_OP_PERCENT_MASK) != 0];
    case GNM_FILTER_OP_TYPE_OP: {
        if (op0 == GNM_FILTER_OP_EQUAL && cond->op[1] == GNM_FILTER_UNUSED && cond->value[0] != NULL && values != NULL) {
            for (unsigned i = 0; i < values->len; i++)
                if (value_equal (cond->value[0], g_ptr_array_index (values, i)))
                    return [[self alloc] initWithValue:value_dup (cond->value[0]) index:i text:labels[i]];
        }
        NSString *text0 = @"", *text1 = @"";
        GnmFilterOperator o0 = operator_from_engine (op0, cond->value[0], &text0);
        if (cond->op[1] == GNM_FILTER_UNUSED)
            return [self customWithOperator:o0 text:text0];
        GnmFilterOperator o1 = operator_from_engine (cond->op[1], cond->value[1], &text1);
        return [self customWithOperator:o0 text:text0 joinedWithAnd:cond->is_and operator:o1 text:text1];
    }
    default:
        /* averages, standard deviations, regular expressions: files can
         * carry them, the dialog cannot show them */
        return [self customWithOperator:GnmFilterOperatorNone text:@""];
    }
}

/* dialog-autofilter.c map_op: the engine operator and value of one
 * comparison; NO when the comparison is unused. */
static BOOL
operator_to_engine (GnmFilterOperator op, NSString *text, Workbook *wb, GnmFilterOp *eop, GnmValue **v)
{
    const char *txt = text.UTF8String;
    *eop = GNM_FILTER_UNUSED;
    *v = NULL;
    if (op == GnmFilterOperatorNone || txt == NULL || *txt == '\0')
        return NO;
    switch (op) {
    case GnmFilterOperatorEquals: *eop = GNM_FILTER_OP_EQUAL; break;
    case GnmFilterOperatorDoesNotEqual: *eop = GNM_FILTER_OP_NOT_EQUAL; break;
    case GnmFilterOperatorGreaterThan: *eop = GNM_FILTER_OP_GT; break;
    case GnmFilterOperatorGreaterThanOrEqual: *eop = GNM_FILTER_OP_GTE; break;
    case GnmFilterOperatorLessThan: *eop = GNM_FILTER_OP_LT; break;
    case GnmFilterOperatorLessThanOrEqual: *eop = GNM_FILTER_OP_LTE; break;
    case GnmFilterOperatorBeginsWith:
    case GnmFilterOperatorDoesNotBeginWith:
        *eop = op == GnmFilterOperatorDoesNotBeginWith ? GNM_FILTER_OP_NOT_EQUAL : GNM_FILTER_OP_EQUAL;
        *v = value_new_string_nocopy (g_strconcat (txt, "*", NULL));
        break;
    case GnmFilterOperatorEndsWith:
    case GnmFilterOperatorDoesNotEndWith:
        *eop = op == GnmFilterOperatorDoesNotEndWith ? GNM_FILTER_OP_NOT_EQUAL : GNM_FILTER_OP_EQUAL;
        *v = value_new_string_nocopy (g_strconcat ("*", txt, NULL));
        break;
    case GnmFilterOperatorContains:
    case GnmFilterOperatorDoesNotContain:
        *eop = op == GnmFilterOperatorDoesNotContain ? GNM_FILTER_OP_NOT_EQUAL : GNM_FILTER_OP_EQUAL;
        *v = value_new_string_nocopy (g_strconcat ("*", txt, "*", NULL));
        break;
    default:
        return NO;
    }
    if (*v == NULL)
        *v = format_match (txt, NULL, workbook_date_conv (wb));
    if (*v == NULL)
        *v = value_new_string (txt);
    return YES;
}

- (GnmFilterCondition *)newEngineConditionWithWorkbook:(Workbook *)wb
{
    switch (_kind) {
    case GnmFilterConditionShowAll:
        return NULL;
    case GnmFilterConditionValue:
        return _value ? gnm_filter_condition_new_single (GNM_FILTER_OP_EQUAL, value_dup (_value)) : NULL;
    case GnmFilterConditionBlanks:
        return gnm_filter_condition_new_single (GNM_FILTER_OP_BLANKS, NULL);
    case GnmFilterConditionNonBlanks:
        return gnm_filter_condition_new_single (GNM_FILTER_OP_NON_BLANKS, NULL);
    case GnmFilterConditionBucket:
        return gnm_filter_condition_new_bucket (_top, !_percent, TRUE, _count);
    case GnmFilterConditionCustom: {
        GnmFilterOp op0, op1;
        GnmValue *v0, *v1;
        if (!operator_to_engine (_firstOperator, _firstText, wb, &op0, &v0))
            return NULL;
        if (operator_to_engine (_secondOperator, _secondText, wb, &op1, &v1))
            return gnm_filter_condition_new_double (op0, v0, _joinedWithAnd, op1, v1);
        return gnm_filter_condition_new_single (op0, v0);
    }
    }
    return NULL;
}

@end

/* ------------------------------------------------------------------------ */

@implementation GnmFilterChoices {
    GPtrArray *_values;   /* GnmValue *, owned */
    NSArray<NSString *> *_labels;
}

- (instancetype)initWithValues:(GPtrArray *)values labels:(NSArray<NSString *> *)labels
                     hasBlanks:(BOOL)hasBlanks current:(GnmFilterCriterion *)current
{
    if (!(self = [super init]))
        return nil;
    _values = values;
    _labels = [labels copy];
    _hasBlanks = hasBlanks;
    _current = current;
    return self;
}

- (void)dealloc
{
    for (unsigned i = 0; i < _values->len; i++)
        value_release (g_ptr_array_index (_values, i));
    g_ptr_array_free (_values, TRUE);
}

- (NSArray<NSString *> *)values { return _labels; }

- (GnmFilterCriterion *)conditionForValueAtIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger) _values->len)
        return [GnmFilterCriterion showAll];
    return [[GnmFilterCriterion alloc] initWithValue:value_dup (g_ptr_array_index (_values, (unsigned) index))
                                               index:index text:_labels[(NSUInteger) index]];
}

@end
