// Edit → Select, Format → Workbook…, and File → Properties… over the
// engine.
#import "GnmPrivate.h"
#include <cmd-edit.h>
#include <commands.h>
#include <sheet-view.h>
#include <selection.h>
#include <workbook-view.h>
#include <workbook-priv.h>
#include <number-match.h>
#include <value.h>
#include <gsf/gsf-timestamp.h>
#include <gsf/gsf-docprop-vector.h>

static void cb_collect_property (gpointer key, gpointer value, gpointer user);
#include <workbook.h>
#include <gsf/gsf-doc-meta-data.h>
#include <gsf/gsf-meta-names.h>
#include <goffice/goffice.h>

@implementation GnmSheet (SelectionTools)

static NSString *
selection_signature (SheetView *sv)
{
    NSMutableString *s = [NSMutableString string];
    for (GSList *l = sv ? sv->selections : NULL; l; l = l->next) {
        GnmRange const *r = l->data;
        [s appendFormat:@"%d,%d,%d,%d;", r->start.col, r->start.row, r->end.col, r->end.row];
    }
    return s;
}

- (BOOL)selectWith:(void (NS_NOESCAPE ^)(SheetView *sv))select
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    SheetView *sv = self.sheetView;
    if (!sv)
        return NO;
    [self.workbook selectSheet:self];
    NSString *before = selection_signature (sv);
    select (sv);
    return ![selection_signature (sv) isEqualToString:before];
}

- (BOOL)selectCurrentArray { return [self selectWith:^(SheetView *sv) { sv_select_cur_array (sv); }]; }
- (BOOL)selectDependents { return [self selectWith:^(SheetView *sv) { sv_select_cur_depends (sv); }]; }
- (BOOL)selectInputs { return [self selectWith:^(SheetView *sv) { sv_select_cur_inputs (sv); }]; }

@end

@implementation GnmWorkbook (ViewAttributes)

- (BOOL)viewFlag:(const char *)name
{
    gboolean value = FALSE;
    g_object_get (G_OBJECT (self.workbookView), name, &value, NULL);
    return value != FALSE;
}

- (void)setViewFlag:(const char *)name to:(BOOL)value
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    if ([self viewFlag:name] == value)
        return;
    g_object_set (G_OBJECT (self.workbookView), name, value ? TRUE : FALSE, NULL);
    go_doc_set_dirty (GO_DOC (self.engineWorkbook), TRUE);   /* the attributes save with the file */
}

#define VIEW_FLAG(getter, setter, name) \
    - (BOOL)getter { return [self viewFlag:name]; } \
    - (void)setter:(BOOL)value { [self setViewFlag:name to:value]; }

VIEW_FLAG (showsHorizontalScrollbar, setShowsHorizontalScrollbar, "show-horizontal-scrollbar")
VIEW_FLAG (showsVerticalScrollbar, setShowsVerticalScrollbar, "show-vertical-scrollbar")
VIEW_FLAG (showsSheetTabs, setShowsSheetTabs, "show-notebook-tabs")
VIEW_FLAG (autoCompletes, setAutoCompletes, "do-auto-completion")
VIEW_FLAG (showsFunctionCellMarkers, setShowsFunctionCellMarkers, "show-function-cell-markers")
VIEW_FLAG (showsExtensionMarkers, setShowsExtensionMarkers, "show-extension-markers")
VIEW_FLAG (isProtected, setProtected, "protected")

#undef VIEW_FLAG

@end

@implementation GnmWorkbook (DocumentProperties)

+ (NSArray<NSString *> *)standardDocumentPropertyNames
{
    return @[@GSF_META_NAME_TITLE, @GSF_META_NAME_SUBJECT, @GSF_META_NAME_DESCRIPTION, @GSF_META_NAME_KEYWORDS,
             @GSF_META_NAME_CREATOR, @GSF_META_NAME_INITIAL_CREATOR, @GSF_META_NAME_MANAGER, @GSF_META_NAME_COMPANY,
             @GSF_META_NAME_CATEGORY];
}

+ (NSString *)labelForDocumentProperty:(NSString *)name
{
    static NSDictionary *labels;
    static dispatch_once_t once;
    dispatch_once (&once, ^{
        labels = @{@GSF_META_NAME_TITLE: @"Title", @GSF_META_NAME_SUBJECT: @"Subject", @GSF_META_NAME_DESCRIPTION: @"Description",
                   @GSF_META_NAME_KEYWORDS: @"Keywords", @GSF_META_NAME_CREATOR: @"Author", @GSF_META_NAME_INITIAL_CREATOR: @"Initial author",
                   @GSF_META_NAME_MANAGER: @"Manager", @GSF_META_NAME_COMPANY: @"Company", @GSF_META_NAME_CATEGORY: @"Category"};
    });
    return labels[name] ?: name;
}

static void
cb_collect_string (gpointer key, gpointer value, gpointer user)
{
    GsfDocProp *prop = value;
    GValue const *v = gsf_doc_prop_get_val (prop);
    if (v && G_VALUE_HOLDS_STRING (v) && g_value_get_string (v))
        ((__bridge NSMutableDictionary *) user)[GnmString (key)] = GnmString (g_value_get_string (v));
}

- (NSDictionary<NSString *, NSString *> *)documentProperties
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    GsfDocMetaData *meta = go_doc_get_meta_data (GO_DOC (self.engineWorkbook));
    if (meta)
        gsf_doc_meta_data_foreach (meta, cb_collect_string, (__bridge void *) result);
    return result;
}

- (BOOL)setDocumentProperties:(NSDictionary<NSString *, NSString *> *)changes error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    NSDictionary *current = self.documentProperties;
    GSList *changed = NULL, *removed = NULL;
    for (NSString *name in changes) {
        NSString *value = changes[name];
        NSString *existing = current[name];
        if (value.length == 0) {
            if (existing)
                removed = g_slist_prepend (removed, g_strdup (name.UTF8String));
            continue;
        }
        if ([existing isEqualToString:value])
            continue;
        /* dialog_doc_metadata_set_prop: a string property */
        GsfDocProp *prop = gsf_doc_prop_new (g_strdup (name.UTF8String));
        GValue *v = g_new0 (GValue, 1);
        g_value_init (v, G_TYPE_STRING);
        g_value_set_string (v, value.UTF8String);
        gsf_doc_prop_set_val (prop, v);
        changed = g_slist_prepend (changed, prop);
    }
    if (!changed && !removed)
        return YES;
    return [self _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_change_meta_data (wbc, changed, removed);   /* takes both lists */
    } description:@"Could not change the document's properties." error:error];
}

- (NSArray<GnmDocumentProperty *> *)allDocumentProperties
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    NSMutableArray *result = [NSMutableArray array];
    GsfDocMetaData *meta = go_doc_get_meta_data (GO_DOC (self.engineWorkbook));
    if (meta)
        gsf_doc_meta_data_foreach (meta, cb_collect_property, (__bridge void *) result);
    [result sortUsingComparator:^NSComparisonResult (GnmDocumentProperty *a, GnmDocumentProperty *b) {
        return [a.name compare:b.name];
    }];
    return result;
}

- (BOOL)setDocumentProperty:(NSString *)name type:(GnmDocumentPropertyType)type value:(NSString *)value error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (trimmed.length == 0) {
        if (error)
            *error = [self.engine _errorWithCode:GnmErrorCommandFailed description:@"A property needs a name." collected:@[]];
        return NO;
    }
    /* dialog_doc_metadata_set_gsf_prop: a new GsfDocProp with a typed value */
    GsfDocProp *prop = gsf_doc_prop_new (g_strdup (trimmed.UTF8String));
    GValue *v = g_new0 (GValue, 1);
    const char *text = value.UTF8String ?: "";
    GODateConventions const *conv = workbook_date_conv (self.engineWorkbook);
    switch (type) {
    case GnmDocumentPropertyTypeInteger:
        g_value_init (v, G_TYPE_INT);
        g_value_set_int (v, (int) strtol (text, NULL, 10));
        break;
    case GnmDocumentPropertyTypeNumber: {
        g_value_init (v, G_TYPE_DOUBLE);
        GnmValue *val = format_match_number (text, NULL, conv);
        if (val) {
            g_value_set_double (v, value_get_as_float (val));
            value_release (val);
        }
        break;
    }
    case GnmDocumentPropertyTypeBoolean: {
        g_value_init (v, G_TYPE_BOOLEAN);
        GnmValue *val = format_match_number (text, NULL, conv);
        gboolean b = FALSE;
        if (val) {
            gboolean err;
            b = value_get_as_bool (val, &err);
            value_release (val);
        }
        g_value_set_boolean (v, b);
        break;
    }
    case GnmDocumentPropertyTypeTimestamp: {
        /* dialog_doc_metadata_transform_str_to_timestamp */
        g_value_init (v, GSF_TIMESTAMP_TYPE);
        GOFormat *fmt = go_format_new_from_XL ("yyyy-mm-dd hh:mm:ss");
        GnmValue *conversion = format_match_number (text, fmt, conv);
        go_format_unref (fmt);
        time_t s = time (NULL);
        if (conversion) {
            double serial = value_get_as_float (conversion);
            value_release (conversion);
            int int_serial = (int) serial;
            time_t base = go_date_serial_to_timet (int_serial, NULL);
            if (fabs (serial - int_serial) < 1 && base != (time_t) -1)
                s = base + (time_t) gnm_fake_round (3600 * 24 * (serial - int_serial));
        }
        GsfTimestamp *gt = gsf_timestamp_new ();
        gsf_timestamp_set_time (gt, s);
        gsf_timestamp_to_value (gt, v);
        gsf_timestamp_free (gt);
        break;
    }
    default:
        g_value_init (v, G_TYPE_STRING);
        g_value_set_string (v, text);
        break;
    }
    gsf_doc_prop_set_val (prop, v);
    return [self _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_change_meta_data (wbc, g_slist_prepend (NULL, prop), NULL);
    } description:@"Could not set the property." error:error];
}

- (BOOL)removeDocumentProperty:(NSString *)name error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GsfDocMetaData *meta = go_doc_get_meta_data (GO_DOC (self.engineWorkbook));
    if (!meta || !gsf_doc_meta_data_lookup (meta, name.UTF8String)) {
        if (error)
            *error = [self.engine _errorWithCode:GnmErrorCommandFailed
                                     description:[NSString stringWithFormat:@"There is no property named “%@”.", name] collected:@[]];
        return NO;
    }
    return [self _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_change_meta_data (wbc, NULL, g_slist_prepend (NULL, g_strdup (name.UTF8String)));
    } description:@"Could not remove the property." error:error];
}

@end

@interface GnmDocumentProperty ()
- (instancetype)initPrivateWithName:(NSString *)name value:(NSString *)value type:(GnmDocumentPropertyType)type;
@end

@implementation GnmDocumentProperty

- (instancetype)initPrivateWithName:(NSString *)name value:(NSString *)value type:(GnmDocumentPropertyType)type
{
    if (!(self = [super init]))
        return nil;
    _name = [name copy];
    _value = [value copy];
    _type = type;
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@=%@ (%ld)>", self.class, _name, _value, (long) _type];
}

@end

/* The GTK page's OTHER TO G_TYPE_STRING transforms */
static void
cb_collect_property (gpointer key, gpointer value, gpointer user)
{
    GsfDocProp *prop = value;
    GValue const *v = gsf_doc_prop_get_val (prop);
    NSString *text = @"";
    GnmDocumentPropertyType type = GnmDocumentPropertyTypeOther;
    if (v) {
        GType t = G_VALUE_TYPE (v);
        if (t == G_TYPE_STRING) {
            type = GnmDocumentPropertyTypeString;
            text = GnmString (g_strdup (g_value_get_string (v) ?: ""));
        } else if (t == G_TYPE_INT) {
            type = GnmDocumentPropertyTypeInteger;
            text = [NSString stringWithFormat:@"%d", g_value_get_int (v)];
        } else if (t == G_TYPE_UINT) {
            type = GnmDocumentPropertyTypeInteger;
            text = [NSString stringWithFormat:@"%u", g_value_get_uint (v)];
        } else if (t == G_TYPE_DOUBLE || t == G_TYPE_FLOAT) {
            type = GnmDocumentPropertyTypeNumber;
            text = [NSString stringWithFormat:@"%g", t == G_TYPE_DOUBLE ? g_value_get_double (v) : g_value_get_float (v)];
        } else if (t == G_TYPE_BOOLEAN) {
            type = GnmDocumentPropertyTypeBoolean;
            text = g_value_get_boolean (v) ? @"TRUE" : @"FALSE";
        } else if (t == GSF_TIMESTAMP_TYPE) {
            type = GnmDocumentPropertyTypeTimestamp;
            GsfTimestamp const *ts = g_value_get_boxed (v);
            text = ts ? GnmString (gsf_timestamp_as_string (ts)) : @"";
        } else {
            char *contents = g_strdup_value_contents (v);
            text = GnmString (contents);
        }
    }
    [(__bridge NSMutableArray *) user addObject:[[GnmDocumentProperty alloc] initPrivateWithName:GnmString (g_strdup (key)) value:text type:type]];
}

@implementation GnmWorkbook (Calculation)

- (BOOL)recalculatesAutomatically
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    return workbook_get_recalcmode (self.engineWorkbook);
}

- (void)setRecalculatesAutomatically:(BOOL)automatic
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    if (workbook_get_recalcmode (self.engineWorkbook) == (automatic != NO))
        return;
    workbook_set_recalcmode (self.engineWorkbook, automatic);
    go_doc_set_dirty (GO_DOC (self.engineWorkbook), TRUE);
}

- (BOOL)iterationEnabled
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    return self.engineWorkbook->iteration.enabled;
}

- (void)setIterationEnabled:(BOOL)enabled
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    if (self.engineWorkbook->iteration.enabled == (enabled != NO))
        return;
    workbook_iteration_enabled (self.engineWorkbook, enabled);
    go_doc_set_dirty (GO_DOC (self.engineWorkbook), TRUE);
}

- (NSInteger)iterationMaximum
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    return self.engineWorkbook->iteration.max_number;
}

- (void)setIterationMaximum:(NSInteger)maximum
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    if (self.engineWorkbook->iteration.max_number == (int) maximum)
        return;
    workbook_iteration_max_number (self.engineWorkbook, (int) MAX (maximum, 1));
    go_doc_set_dirty (GO_DOC (self.engineWorkbook), TRUE);
}

- (double)iterationTolerance
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    return self.engineWorkbook->iteration.tolerance;
}

- (void)setIterationTolerance:(double)tolerance
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    if (self.engineWorkbook->iteration.tolerance == tolerance)
        return;
    workbook_iteration_tolerance (self.engineWorkbook, tolerance);
    go_doc_set_dirty (GO_DOC (self.engineWorkbook), TRUE);
}

- (NSInteger)cellCount
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    NSInteger count = 0;
    Workbook *wb = self.engineWorkbook;
    for (int i = 0; i < workbook_sheet_count (wb); i++)
        count += sheet_cells_count (workbook_sheet_by_index (wb, i));
    return count;
}

@end
