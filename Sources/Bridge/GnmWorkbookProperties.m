// Edit → Select, Format → Workbook…, and File → Properties… over the
// engine.
#import "GnmPrivate.h"
#include <cmd-edit.h>
#include <commands.h>
#include <sheet-view.h>
#include <selection.h>
#include <workbook-view.h>
#include <workbook-priv.h>
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

@end

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
