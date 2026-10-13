// Hyperlinks as dialog-hyperlink.c sets them (a link on a partial style
// with the underline and the blue, cmd_selection_hyperlink) and hlink.c
// follows the internal ones.
#import "GnmPrivate.h"
#include <hlink.h>
#include <expr-name.h>
#include <expr.h>

@implementation GnmHyperlink

- (instancetype)initWithKind:(GnmHyperlinkKind)kind target:(NSString *)target tip:(NSString *)tip
{
    if (!(self = [super init]))
        return nil;
    _kind = kind;
    _target = [target copy];
    _tip = [tip copy];
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[GnmHyperlink allocWithZone:zone] initWithKind:_kind target:_target tip:_tip];
}

+ (NSString *)emailTargetForAddress:(NSString *)address subject:(NSString *)subject
{
    if (address.length == 0)
        return @"";
    char *enc_addr = go_url_encode (address.UTF8String, 0);
    NSString *result;
    if (subject.length == 0)
        result = [NSString stringWithFormat:@"mailto:%s", enc_addr];
    else {
        char *enc_subj = go_url_encode (subject.UTF8String, 0);
        result = [NSString stringWithFormat:@"mailto:%s?subject=%s", enc_addr, enc_subj];
        g_free (enc_subj);
    }
    g_free (enc_addr);
    return result;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %ld '%@' tip '%@'>", self.class, (long) _kind, _target, _tip];
}

@end

static GType
hlink_type_for_kind (GnmHyperlinkKind kind)
{
    switch (kind) {
    case GnmHyperlinkInternal: return gnm_hlink_cur_wb_get_type ();
    case GnmHyperlinkExternalFile: return gnm_hlink_external_get_type ();
    case GnmHyperlinkEmail: return gnm_hlink_email_get_type ();
    case GnmHyperlinkWeb: return gnm_hlink_url_get_type ();
    }
    return gnm_hlink_url_get_type ();
}

static GnmHyperlinkKind
kind_for_hlink (GnmHLink *lnk)
{
    if (G_TYPE_CHECK_INSTANCE_TYPE (lnk, gnm_hlink_cur_wb_get_type ()))
        return GnmHyperlinkInternal;
    if (GNM_IS_HLINK_EXTERNAL (lnk))
        return GnmHyperlinkExternalFile;
    if (G_TYPE_CHECK_INSTANCE_TYPE (lnk, gnm_hlink_email_get_type ()))
        return GnmHyperlinkEmail;
    return GnmHyperlinkWeb;
}

@implementation GnmSheet (Hyperlinks)

- (GnmHyperlink *)hyperlinkAtColumn:(NSInteger)column row:(NSInteger)row
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    if (!sheet)
        return nil;
    GnmCellPos pos = { (int) column, (int) row };
    GnmHLink *lnk = gnm_sheet_hlink_find (sheet, &pos);
    if (!lnk)
        return nil;
    const char *tip = gnm_hlink_get_tip (lnk);
    return [[GnmHyperlink alloc] initWithKind:kind_for_hlink (lnk) target:GnmString (gnm_hlink_get_target (lnk))
                                          tip:tip ? GnmString (tip) : nil];
}

- (BOOL)setHyperlink:(GnmHyperlink *)link error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    if (!sheet || !workbook)
        return NO;
    /* dhl_cb_ok: new when the edit position has no link yet */
    GnmCellCoordinate edit = self.editPosition;
    GnmCellPos pos = { (int) edit.column, (int) edit.row };
    BOOL isNew = gnm_sheet_hlink_find (sheet, &pos) == NULL;
    GnmStyle *style = gnm_style_new ();
    const char *name;
    char *content = NULL;
    if (link) {
        GnmHLink *lnk = gnm_hlink_new (hlink_type_for_kind (link.kind), sheet);
        gnm_hlink_set_target (lnk, link.target.UTF8String);
        gnm_hlink_set_tip (lnk, link.tip ? link.tip.UTF8String : NULL);
        gnm_style_set_hlink (style, lnk);
        gnm_style_set_font_uline (style, UNDERLINE_SINGLE);
        gnm_style_set_font_color (style, gnm_color_new_go (GO_COLOR_BLUE));
        name = isNew ? "Add Hyperlink" : "Edit Hyperlink";
        if (isNew)
            content = g_strdup (link.target.UTF8String);
    } else {
        if (isNew) {
            gnm_style_unref (style);
            return YES;
        }
        gnm_style_set_hlink (style, NULL);
        name = "Remove Hyperlink";
    }
    return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_selection_hyperlink (wbc, style, name, content);
    } description:@"Could not change the hyperlink." error:error];
}

- (BOOL)isValidInternalTarget:(NSString *)text
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    if (!sheet || text.length == 0)
        return NO;
    /* dhl_get_target_cur_wb */
    GnmParsePos pp;
    parse_pos_init_sheet (&pp, sheet);
    GnmValue *val = value_new_cellrange_parsepos_str (&pp, text.UTF8String,
                                                      GNM_EXPR_PARSE_UNKNOWN_NAMES_ARE_STRINGS | GNM_EXPR_PARSE_FORCE_EXPLICIT_SHEET_REFERENCES);
    if (!val) {
        GnmNamedExpr *nexpr = expr_name_lookup (&pp, text.UTF8String);
        if (nexpr)
            val = gnm_expr_top_get_range (nexpr->texpr);
    }
    if (!val)
        return NO;
    value_release (val);
    return YES;
}

- (BOOL)followInternalHyperlinkAtColumn:(NSInteger)column row:(NSInteger)row error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    if (!sheet || !workbook)
        return NO;
    GnmCellPos pos = { (int) column, (int) row };
    GnmHLink *lnk = gnm_sheet_hlink_find (sheet, &pos);
    GnmSheetRange sr;
    if (!lnk || !gnm_hlink_get_range_target (lnk, &sr)) {
        /* gnm_hlink_cur_wb_activate's refusal */
        if (error) {
            const char *target = lnk ? gnm_hlink_get_target (lnk) : NULL;
            *error = [workbook.engine _errorWithCode:GnmErrorCommandFailed
                                         description:[NSString stringWithFormat:@"Link target: %s", target ? target : "-"] collected:@[]];
        }
        return NO;
    }
    WorkbookView *wbv = workbook.workbookView;
    SheetView *sv = sheet_get_view (sr.sheet, wbv);
    sv_selection_set (sv, &sr.range.start, sr.range.start.col, sr.range.start.row, sr.range.end.col, sr.range.end.row);
    gnm_sheet_view_make_cell_visible (sv, sr.range.start.col, sr.range.start.row, FALSE);
    if (wb_view_cur_sheet (wbv) != sr.sheet)
        wb_view_sheet_focus (wbv, sr.sheet);
    gnm_sheet_view_update (sv);
    return YES;
}

- (NSArray<NSValue *> *)hyperlinkRangesInRange:(GnmCellRange)range
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    NSMutableArray *result = [NSMutableArray array];
    if (!sheet)
        return result;
    GnmRange r;
    range_init (&r, (int) range.start.column, (int) range.start.row, (int) range.end.column, (int) range.end.row);
    GnmStyleList *regions = sheet_style_collect_hlinks (sheet, &r);
    for (GSList *l = regions; l; l = l->next) {
        GnmStyleRegion const *region = l->data;
        if (!gnm_style_get_hlink (region->style))
            continue;
        GnmCellRange found = GnmCellRangeMake (region->range.start.col, region->range.start.row,
                                               region->range.end.col, region->range.end.row);
        [result addObject:[NSValue valueWithBytes:&found objCType:@encode (GnmCellRange)]];
    }
    sheet_style_list_free (regions);
    return result;
}

- (BOOL)removeHyperlinksOfSelectionWithError:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    SheetView *sv = self.sheetView;
    GnmWorkbook *workbook = self.workbook;
    if (!sheet || !sv || !workbook)
        return NO;
    int n_links = 0;
    for (GSList *l = sv->selections; l; l = l->next) {
        GnmStyleList *styles = sheet_style_collect_hlinks (sheet, l->data);
        n_links += (int) g_slist_length (styles);
        sheet_style_list_free (styles);
    }
    char *name = g_strdup_printf (n_links == 1 ? "Remove %d Link" : "Remove %d Links", n_links);
    GnmStyle *style = gnm_style_new ();
    gnm_style_set_hlink (style, NULL);
    BOOL ok = [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_selection_format (wbc, style, NULL, name);
    } description:@"Could not remove the hyperlinks." error:error];
    g_free (name);
    return ok;
}

@end
