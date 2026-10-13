// Data → Merge as dialog-merge.c's cb_merge_merge_clicked runs it.
#import "GnmPrivate.h"
#include <ranges.h>
#include <value.h>

@implementation GnmSheet (Merge)

- (BOOL)isRangeText:(NSString *)text singleCell:(BOOL)singleCell
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    if (!sheet || !text.length)
        return NO;
    GnmValue *v = value_new_cellrange_str (sheet, text.UTF8String);
    if (!v)
        return NO;
    GnmRangeRef const *ref = &v->v_range.cell;
    BOOL ok = !singleCell || (ref->a.col == ref->b.col && ref->a.row == ref->b.row);
    value_release (v);
    return ok;
}

static GSList *
ranges_from_texts (Sheet *sheet, NSArray<NSString *> *texts, NSString **bad)
{
    GSList *list = NULL;
    for (NSString *text in texts) {
        GnmValue *v = text.length ? value_new_cellrange_str (sheet, text.UTF8String) : NULL;
        if (!v) {
            range_list_destroy (list);
            if (bad)
                *bad = text;
            return NULL;
        }
        list = g_slist_append (list, v);
    }
    return list;
}

static int
range_rows (GnmValue const *v)
{
    GnmRangeRef const *ref = &v->v_range.cell;
    return ref->b.row - ref->a.row + 1;
}

- (BOOL)mergeDataLengths:(NSArray<NSString *> *)data shortest:(NSInteger *)shortest longest:(NSInteger *)longest
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    if (!sheet || !data.count)
        return NO;
    GSList *list = ranges_from_texts (sheet, data, NULL);
    if (!list)
        return NO;
    int min = gnm_sheet_get_max_rows (sheet), max = 0;
    for (GSList *l = list; l; l = l->next) {
        int rows = range_rows (l->data);
        min = MIN (min, rows);
        max = MAX (max, rows);
    }
    range_list_destroy (list);
    if (shortest)
        *shortest = min;
    if (longest)
        *longest = max;
    return YES;
}

- (BOOL)mergeDataIntoZone:(NSString *)zone fields:(NSArray<NSString *> *)fields data:(NSArray<NSString *> *)data
       trimmingToShortest:(BOOL)trim error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    if (!sheet || !workbook)
        return NO;
    GnmEngine *engine = workbook.engine;
    if (fields.count == 0 || fields.count != data.count) {
        if (error)
            *error = [engine _errorWithCode:GnmErrorCommandFailed description:@"The merge needs at least one field with its data column." collected:@[]];
        return NO;
    }
    GnmValue *v_zone = zone.length ? value_new_cellrange_str (sheet, zone.UTF8String) : NULL;
    if (!v_zone) {
        if (error)
            *error = [engine _errorWithCode:GnmErrorCommandFailed description:@"The merge zone is not a range." collected:@[]];
        return NO;
    }
    NSString *bad = nil;
    GSList *field_list = ranges_from_texts (sheet, fields, &bad);
    GSList *data_list = field_list ? ranges_from_texts (sheet, data, &bad) : NULL;
    if (!field_list || !data_list) {
        value_release (v_zone);
        range_list_destroy (field_list);
        if (error)
            *error = [engine _errorWithCode:GnmErrorCommandFailed
                                description:[NSString stringWithFormat:@"“%@” is not a range.", bad] collected:@[]];
        return NO;
    }
    int field_problems = 0;
    for (GSList *l = field_list; l; l = l->next)
        if (!global_range_contained (sheet, l->data, v_zone))
            field_problems++;
    if (field_problems > 0) {
        NSString *text = field_problems == 1 ? @"One field is not part of the merge zone!"
            : [NSString stringWithFormat:@"%d fields are not part of the merge zone!", field_problems];
        value_release (v_zone);
        range_list_destroy (field_list);
        range_list_destroy (data_list);
        if (error)
            *error = [engine _errorWithCode:GnmErrorCommandFailed description:text collected:@[]];
        return NO;
    }
    int min_length = gnm_sheet_get_max_rows (sheet), max_length = 0;
    for (GSList *l = data_list; l; l = l->next) {
        int rows = range_rows (l->data);
        min_length = MIN (min_length, rows);
        max_length = MAX (max_length, rows);
    }
    if (min_length < max_length) {
        if (!trim) {
            value_release (v_zone);
            range_list_destroy (field_list);
            range_list_destroy (data_list);
            if (error)
                *error = [engine _errorWithCode:GnmErrorCommandFailed
                                    description:[NSString stringWithFormat:@"The data columns range in length from %d to %d. Shall we trim the lengths to %d and proceed?",
                                                 min_length, max_length, min_length]
                                      collected:@[]];
            return NO;
        }
        for (GSList *l = data_list; l; l = l->next) {   /* cb_merge_trim_data */
            GnmValue *v = l->data;
            v->v_range.cell.b.row = v->v_range.cell.a.row + min_length - 1;
        }
    }
    /* cmd_merge_data takes the zone and both lists */
    return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_merge_data (wbc, sheet, v_zone, field_list, data_list);
    } description:@"Could not merge the data." error:error];
}

@end
