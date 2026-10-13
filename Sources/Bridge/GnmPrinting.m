// print.c's pagination (compute_sheet_pages, paginate, compute_group,
// compute_scale_fit_to) and page drawing (print_page and its helpers),
// with the GtkPrintContext's width, height, and Pango replaced by the
// paper's printable area and pango-cairo on a cairo-quartz surface.
#import "GnmPrivate.h"
#include <print-info.h>
#include <print-cell.h>
#include <expr-name.h>
#include <expr.h>
#include <gtk/gtk.h>
#include <pango/pangocairo.h>
#include <style-font.h>

#pragma mark - Settings

@implementation GnmPrintSettings

- (instancetype)init
{
    GnmPrintInformation *pi = gnm_print_information_new (TRUE);
    self = [self initWithPrintInformation:pi];
    gnm_print_info_free (pi);
    return self;
}

- (instancetype)initWithPrintInformation:(GnmPrintInformation *)pi
{
    if (!(self = [super init]))
        return nil;
    gnm_print_info_load_defaults (pi);
    char *paper = print_info_get_paper (pi);
    _paperName = GnmString (paper);
    g_free (paper);
    _orientation = (GnmPageOrientation) print_info_get_paper_orientation (pi);
    double top, bottom, left, right, below_header, above_footer;
    print_info_get_margins (pi, &top, &bottom, &left, &right, &below_header, &above_footer);
    _headerMargin = top;
    _footerMargin = bottom;
    _leftMargin = left;
    _rightMargin = right;
    _topMargin = below_header;
    _bottomMargin = above_footer;
    _scaling = pi->scaling.type == PRINT_SCALE_FIT_PAGES ? GnmPrintScalingFitPages : GnmPrintScalingPercentage;
    _scalePercentage = pi->scaling.percentage.x;
    _fitColumns = pi->scaling.dim.cols;
    _fitRows = pi->scaling.dim.rows;
    _centersHorizontally = pi->center_horizontally;
    _centersVertically = pi->center_vertically;
    _printsGridLines = pi->print_grid_lines;
    _printsTitles = pi->print_titles;
    _printsBlackAndWhite = pi->print_black_and_white;
    _printsAcrossThenDown = pi->print_across_then_down;
    _repeatTop = GnmString (pi->repeat_top);
    _repeatLeft = GnmString (pi->repeat_left);
    _headerLeft = GnmString (pi->header ? pi->header->left_format : NULL);
    _headerMiddle = GnmString (pi->header ? pi->header->middle_format : NULL);
    _headerRight = GnmString (pi->header ? pi->header->right_format : NULL);
    _footerLeft = GnmString (pi->footer ? pi->footer->left_format : NULL);
    _footerMiddle = GnmString (pi->footer ? pi->footer->middle_format : NULL);
    _footerRight = GnmString (pi->footer ? pi->footer->right_format : NULL);
    return self;
}

- (void)_applyToPrintInformation:(GnmPrintInformation *)pi
{
    gnm_print_info_load_defaults (pi);
    if (_paperName.length)
        print_info_set_paper (pi, _paperName.UTF8String);
    print_info_set_paper_orientation (pi, (GtkPageOrientation) _orientation);
    print_info_set_margins (pi, _headerMargin, _footerMargin, _leftMargin, _rightMargin);
    print_info_set_edge_to_below_header (pi, _topMargin);
    print_info_set_edge_to_above_footer (pi, _bottomMargin);
    pi->scaling.type = _scaling == GnmPrintScalingFitPages ? PRINT_SCALE_FIT_PAGES : PRINT_SCALE_PERCENTAGE;
    pi->scaling.percentage.x = pi->scaling.percentage.y = _scalePercentage > 0 ? _scalePercentage : 100;
    pi->scaling.dim.cols = (int) MAX (_fitColumns, 0);
    pi->scaling.dim.rows = (int) MAX (_fitRows, 0);
    pi->center_horizontally = _centersHorizontally;
    pi->center_vertically = _centersVertically;
    pi->print_grid_lines = _printsGridLines;
    pi->print_titles = _printsTitles;
    pi->print_black_and_white = _printsBlackAndWhite;
    pi->print_across_then_down = _printsAcrossThenDown;
    g_free (pi->repeat_top);
    pi->repeat_top = g_strdup (_repeatTop.UTF8String);
    g_free (pi->repeat_left);
    pi->repeat_left = g_strdup (_repeatLeft.UTF8String);
    gnm_print_hf_free (pi->header);
    pi->header = gnm_print_hf_new (_headerLeft.UTF8String, _headerMiddle.UTF8String, _headerRight.UTF8String);
    gnm_print_hf_free (pi->footer);
    pi->footer = gnm_print_hf_new (_footerLeft.UTF8String, _footerMiddle.UTF8String, _footerRight.UTF8String);
}

- (NSString *)paperDisplayName
{
    GtkPaperSize *size = gtk_paper_size_new (_paperName.length ? _paperName.UTF8String : NULL);
    NSString *name = GnmString (gtk_paper_size_get_display_name (size));
    gtk_paper_size_free (size);
    return name;
}

- (double)paperWidth
{
    GtkPaperSize *size = gtk_paper_size_new (_paperName.length ? _paperName.UTF8String : NULL);
    double w = gtk_paper_size_get_width (size, GTK_UNIT_POINTS), h = gtk_paper_size_get_height (size, GTK_UNIT_POINTS);
    gtk_paper_size_free (size);
    BOOL landscape = _orientation == GnmPageOrientationLandscape || _orientation == GnmPageOrientationReverseLandscape;
    return landscape ? h : w;
}

- (double)paperHeight
{
    GtkPaperSize *size = gtk_paper_size_new (_paperName.length ? _paperName.UTF8String : NULL);
    double w = gtk_paper_size_get_width (size, GTK_UNIT_POINTS), h = gtk_paper_size_get_height (size, GTK_UNIT_POINTS);
    gtk_paper_size_free (size);
    BOOL landscape = _orientation == GnmPageOrientationLandscape || _orientation == GnmPageOrientationReverseLandscape;
    return landscape ? w : h;
}

+ (NSDictionary<NSString *, NSString *> *)paperDisplayNames
{
    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    GList *sizes = gtk_paper_size_get_paper_sizes (FALSE);
    for (GList *l = sizes; l; l = l->next) {
        GtkPaperSize *size = l->data;
        names[GnmString (gtk_paper_size_get_name (size))] = GnmString (gtk_paper_size_get_display_name (size));
    }
    g_list_free_full (sizes, (GDestroyNotify) gtk_paper_size_free);
    return names;
}

- (id)copyWithZone:(NSZone *)zone
{
    GnmPrintSettings *copy = [[GnmPrintSettings allocWithZone:zone] init];
    copy.paperName = _paperName;
    copy.orientation = _orientation;
    copy.topMargin = _topMargin;
    copy.bottomMargin = _bottomMargin;
    copy.headerMargin = _headerMargin;
    copy.footerMargin = _footerMargin;
    copy.leftMargin = _leftMargin;
    copy.rightMargin = _rightMargin;
    copy.scaling = _scaling;
    copy.scalePercentage = _scalePercentage;
    copy.fitColumns = _fitColumns;
    copy.fitRows = _fitRows;
    copy.centersHorizontally = _centersHorizontally;
    copy.centersVertically = _centersVertically;
    copy.printsGridLines = _printsGridLines;
    copy.printsTitles = _printsTitles;
    copy.printsBlackAndWhite = _printsBlackAndWhite;
    copy.printsAcrossThenDown = _printsAcrossThenDown;
    copy.repeatTop = _repeatTop;
    copy.repeatLeft = _repeatLeft;
    copy.headerLeft = _headerLeft;
    copy.headerMiddle = _headerMiddle;
    copy.headerRight = _headerRight;
    copy.footerLeft = _footerLeft;
    copy.footerMiddle = _footerMiddle;
    copy.footerRight = _footerRight;
    return copy;
}

@end

#pragma mark - Pagination (print.c)

typedef struct {
    int rc, count, first_rep, n_rep;
} PaginationInfo;

typedef struct {
    GnmRange range;
    int first_rep_rows, n_rep_rows, first_rep_cols, n_rep_cols;
} SheetPageRange;

static int
compute_group (Sheet const *sheet, int start, int end, double usable,
               ColRowInfo const *(get_info) (Sheet const *sheet, int const p))
{
    double size_pts = 1.;   /* the initial grid line */
    int idx, count = 0;
    for (idx = start; idx <= end; idx++, count++) {
        ColRowInfo const *info = (*get_info) (sheet, idx);
        if (info->visible) {
            size_pts += info->size_pts;
            if (size_pts > usable)
                break;
        }
    }
    return count == 0 ? 1 : count;   /* one at least, or we would loop forever */
}

static void
adjust_repetition (Sheet const *sheet, gint i, gint first_rep, gint n_rep, gdouble repeating,
                   gint *first_rep_used, gint *n_rep_used, gdouble *repeating_used,
                   double (sheet_get_distance_pts) (Sheet const *sheet, int from, int to))
{
    if (i > first_rep) {
        *first_rep_used = first_rep;
        if (i - first_rep < n_rep) {
            *n_rep_used = i - first_rep;
            *repeating_used = sheet_get_distance_pts (sheet, first_rep, first_rep + *n_rep_used);
        } else {
            *repeating_used = repeating;
            *n_rep_used = n_rep;
        }
    }
}

static gint
paginate (GArray *paginationInfo, Sheet const *sheet, gint start, gint end, gdouble usable,
          gboolean repeat, gint repeat_start, gint repeat_end,
          double (sheet_get_distance_pts) (Sheet const *sheet, int from, int to),
          ColRowInfo const *(get_info) (Sheet const *sheet, int const p),
          GnmPageBreaks *pb, gboolean store_breaks)
{
    int rc = start;
    gint n_rep = 0, first_rep = 0;
    gdouble repeating = 0.;
    gint page_count = 0;
    if (repeat) {
        first_rep = repeat_start;
        n_rep = repeat_end - first_rep + 1;
        repeating = sheet_get_distance_pts (sheet, first_rep, first_rep + n_rep);
    }
    while (rc <= end) {
        gint n_end = pb ? gnm_page_breaks_get_next_manual_break (pb, rc) - 1 : -1;
        if (n_end < rc)
            n_end = end;
        while (rc <= n_end) {
            int count;
            gdouble repeating_used = 0.;
            gint n_rep_used = 0, first_rep_used = 0;
            adjust_repetition (sheet, rc, first_rep, n_rep, repeating, &first_rep_used, &n_rep_used, &repeating_used,
                               sheet_get_distance_pts);
            count = compute_group (sheet, rc, n_end, usable - repeating_used, get_info);
            if (paginationInfo) {
                PaginationInfo item = { rc, count, first_rep_used, n_rep_used };
                g_array_append_val (paginationInfo, item);
            }
            page_count++;
            rc += count;
            if (store_breaks && pb && rc < n_end)
                gnm_page_breaks_set_break (pb, rc, GNM_PAGE_BREAK_AUTO);
        }
    }
    return page_count;
}

static double
compute_scale_fit_to (Sheet const *sheet, int start, int end, double usable,
                      ColRowInfo const *(get_info) (Sheet const *sheet, int const p),
                      double (get_distance_pts) (Sheet const *sheet, int from, int to),
                      gint pages, double max_percent, double header,
                      gboolean repeat, gint repeat_start, gint repeat_end, GnmPageBreaks *pb)
{
    double max_p, min_p;
    gint max_pages;
    double extent = get_distance_pts (sheet, start, end + 1);
    if (repeat && repeat_start < start)
        extent += get_distance_pts (sheet, repeat_start, repeat_end < start ? repeat_end + 1 : start);
    if (pages <= 0)
        return max_percent;
    if (pages == 1) {
        max_p = usable / (header + extent + 2.);
        return max_p > max_percent ? max_percent : max_p;
    }
    max_p = (pages * usable) / (extent + pages * header);
    max_p = CLAMP (max_p, 0.01, max_percent);
    max_pages = paginate (NULL, sheet, start, end, usable / max_p - header, repeat, repeat_start, repeat_end,
                          get_distance_pts, get_info, pb, FALSE);
    if (max_pages == pages)
        return max_p;
    min_p = usable / (extent + header);
    min_p = CLAMP (min_p, 0.01, max_percent);
    paginate (NULL, sheet, start, end, usable / min_p - header, repeat, repeat_start, repeat_end, get_distance_pts, get_info, pb, FALSE);
    while (max_p - min_p > 0.001) {
        double cur_p = (max_p + min_p) / 2.;
        int cur_pages = paginate (NULL, sheet, start, end, usable / cur_p - header, repeat, repeat_start, repeat_end,
                                  get_distance_pts, get_info, pb, FALSE);
        if (cur_pages > pages)
            max_p = cur_p;
        else
            min_p = cur_p;
    }
    return min_p;
}

#pragma mark - Page drawing (print.c)

static void
print_header_box (cairo_t *cr, double x, double y, double w, double h, char const *name, PangoFontDescription *desc)
{
    cairo_rectangle (cr, x, y, w, h);
    cairo_set_source_rgb (cr, 0.8, 0.8, 0.8);
    cairo_fill (cr);
    cairo_set_source_rgb (cr, 0., 0., 0.);
    PangoLayout *layout = pango_cairo_create_layout (cr);
    pango_layout_set_font_description (layout, desc);
    pango_layout_set_text (layout, name, -1);
    pango_layout_set_width (layout, (int) (w * PANGO_SCALE));
    pango_layout_set_alignment (layout, PANGO_ALIGN_CENTER);
    int layout_height;
    pango_layout_get_size (layout, NULL, &layout_height);
    double text_height = (double) layout_height / PANGO_SCALE;
    cairo_move_to (cr, x, y + (h - text_height) / 2);
    pango_cairo_show_layout (cr, layout);
    g_object_unref (layout);
}

static void
print_page_col_headers (cairo_t *cr, Sheet const *sheet, GnmRange *range, double row_header_width, double col_header_height)
{
    double hscale = sheet->display_formulas ? 2 : 1;
    PangoFontDescription *desc = pango_font_description_from_string ("sans 12");
    double x = (row_header_width + GNM_COL_MARGIN) * (sheet->text_is_rtl ? -1. : 1.);
    for (int col = range->start.col; col <= range->end.col; col++) {
        ColRowInfo const *ci = sheet_col_get_info (sheet, col);
        if (ci->visible) {
            if (sheet->text_is_rtl)
                x -= ci->size_pts * hscale;
            print_header_box (cr, x + 0.5, 0, ci->size_pts * hscale - 1, col_header_height - 0.5, col_name (col), desc);
            if (!sheet->text_is_rtl)
                x += ci->size_pts * hscale;
        }
    }
    pango_font_description_free (desc);
}

static void
print_page_row_headers (cairo_t *cr, Sheet const *sheet, GnmRange *range, double row_header_width, double col_header_height)
{
    PangoFontDescription *desc = pango_font_description_from_string ("sans 12");
    double x = sheet->text_is_rtl ? -(row_header_width - 0.5) : 0, y = col_header_height;
    for (int row = range->start.row; row <= range->end.row; row++) {
        ColRowInfo const *ri = sheet_row_get_info (sheet, row);
        if (ri->visible) {
            print_header_box (cr, x, y + 0.5, row_header_width - 0.5, ri->size_pts - 1, row_name (row), desc);
            y += ri->size_pts;
        }
    }
    pango_font_description_free (desc);
}

static void
print_hf_element (cairo_t *cr, char const *format, PangoAlignment side, double width, gboolean align_bottom, GnmPrintHFRenderInfo *hfi)
{
    if (!format)
        return;
    char *text = gnm_print_hf_format_render (format, hfi, HF_RENDER_PRINT);
    if (!text)
        return;
    PangoLayout *layout = pango_cairo_create_layout (cr);
    GnmStyle *style = gnm_conf_get_printer_decoration_font ();
    GnmFont *font = gnm_style_get_font (style, pango_layout_get_context (layout));
    pango_layout_set_font_description (layout, font->go.font->desc);
    gnm_style_unref (style);
    pango_layout_set_text (layout, text, -1);
    pango_layout_set_width (layout, (int) (width * PANGO_SCALE));
    pango_layout_set_alignment (layout, side);
    double text_height = 0.;
    if (align_bottom) {
        int layout_height = 0;
        pango_layout_get_size (layout, NULL, &layout_height);
        text_height = (double) layout_height / PANGO_SCALE;
    }
    cairo_set_source_rgb (cr, 0., 0., 0.);
    cairo_move_to (cr, 0., -text_height);
    pango_cairo_show_layout (cr, layout);
    g_object_unref (layout);
    g_free (text);
}

static void
print_hf_line (cairo_t *cr, GnmPrintHF const *hf, gboolean align_bottom, double width, GnmPrintHFRenderInfo *hfi)
{
    if (!hf)
        return;
    print_hf_element (cr, hf->left_format, PANGO_ALIGN_LEFT, width, align_bottom, hfi);
    print_hf_element (cr, hf->middle_format, PANGO_ALIGN_CENTER, width, align_bottom, hfi);
    print_hf_element (cr, hf->right_format, PANGO_ALIGN_RIGHT, width, align_bottom, hfi);
}

/* gnm_print_sheet_objects, left-to-right */
static void
print_sheet_objects (cairo_t *cr, Sheet const *sheet, GnmRange *range, double base_x, double base_y)
{
    cairo_save (cr);
    double height = sheet_row_get_distance_pts (sheet, range->start.row, range->end.row + 1);
    double width = sheet_col_get_distance_pts (sheet, range->start.col, range->end.col + 1);
    cairo_rectangle (cr, base_x, base_y, width, height);
    cairo_clip (cr);
    GSList *objects = g_slist_reverse (g_slist_copy (sheet->sheet_objects));
    for (GSList *ptr = objects; ptr; ptr = ptr->next) {
        SheetObject *so = GNM_SO (ptr->data);
        GnmRange const *r = &so->anchor.cell_bound;
        if (!sheet_object_can_print (so) || !range_overlap (range, &so->anchor.cell_bound))
            continue;
        cairo_save (cr);
        if (so->anchor.mode == GNM_SO_ANCHOR_ABSOLUTE)
            cairo_translate (cr, base_x + 0.5, base_y + 0.5);
        else
            cairo_translate (cr, base_x + 0.5 + sheet_col_get_distance_pts (sheet, 0, r->start.col)
                             - sheet_col_get_distance_pts (sheet, 0, range->start.col),
                             base_y + 0.5 + sheet_row_get_distance_pts (sheet, 0, r->start.row)
                             - sheet_row_get_distance_pts (sheet, 0, range->start.row));
        sheet_object_draw_cairo (so, (gpointer) cr, FALSE);
        cairo_restore (cr);
    }
    g_slist_free (objects);
    cairo_restore (cr);
}

static void
print_page_cells (PangoContext *pcontext, cairo_t *cr, Sheet const *sheet, GnmRange *range, double base_x, double base_y)
{
    gnm_gtk_print_cell_range (pcontext, cr, sheet, range, base_x, base_y, (GnmPrintInformation const *) sheet->print_info);
    print_sheet_objects (cr, sheet, range, base_x, base_y);
}

#pragma mark - Job

@implementation GnmPrintJob {
    GnmSheet *_owner;
    Sheet *_sheet;
    GArray *_columns, *_rows;
    double _paperWidth, _paperHeight;
    GnmPrintHFRenderInfo *_hfi;
}

- (nullable instancetype)initWithSheet:(GnmSheet *)owner selectionOnly:(BOOL)selectionOnly ignoringPrintArea:(BOOL)ignore
{
    if (!(self = [super init]))
        return nil;
    _owner = owner;
    _sheet = owner.engineSheet;
    Sheet *sheet = _sheet;
    GnmPrintInformation *pinfo = sheet->print_info;
    gnm_print_info_load_defaults (pinfo);
    /* compute_sheet_pages */
    double col_header_height = 0., row_header_width = 0.;
    if (pinfo->print_titles) {
        col_header_height = sheet->rows.default_style.size_pts;
        row_header_width = sheet->cols.default_style.size_pts;
    }
    GnmRange print_area = sheet_get_printarea (sheet, pinfo->print_even_if_only_styles, ignore);
    if (selectionOnly) {
        SheetView *sv = owner.sheetView;
        GnmRange const *selection = sv ? selection_first_range (sv, NULL, "Print Selection") : NULL;
        if (!selection)
            return nil;
        GnmRange r;
        if (ignore)
            print_area = *selection;
        else if (range_intersection (&r, selection, &print_area))
            print_area = r;
        else
            return nil;
    }
    double top, bottom, left, right, below_header, above_footer;
    print_info_get_margins (pinfo, &top, &bottom, &left, &right, &below_header, &above_footer);
    _paperWidth = print_info_get_paper_width (pinfo, GTK_UNIT_POINTS);
    _paperHeight = print_info_get_paper_height (pinfo, GTK_UNIT_POINTS);
    double page_width = _paperWidth - left - right;
    double page_height = _paperHeight - top - bottom;
    page_height -= (below_header - top) + (above_footer - bottom);
    GnmRange r;
    gboolean repeat_top_use = print_load_repeat_range (pinfo->repeat_top, &r, sheet);
    int repeat_top_start = repeat_top_use ? r.start.row : 0, repeat_top_end = repeat_top_use ? r.end.row : 0;
    gboolean repeat_left_use = print_load_repeat_range (pinfo->repeat_left, &r, sheet);
    int repeat_left_start = repeat_left_use ? r.start.col : 0, repeat_left_end = repeat_left_use ? r.end.col : 0;
    if (pinfo->page_breaks.h == NULL)
        print_info_set_breaks (pinfo, gnm_page_breaks_new (FALSE));
    else
        gnm_page_breaks_clean (pinfo->page_breaks.h);
    if (pinfo->page_breaks.v == NULL)
        print_info_set_breaks (pinfo, gnm_page_breaks_new (TRUE));
    else
        gnm_page_breaks_clean (pinfo->page_breaks.v);
    if (pinfo->scaling.type == PRINT_SCALE_FIT_PAGES) {
        double pxy = compute_scale_fit_to (sheet, print_area.start.row, print_area.end.row, page_height, sheet_row_get_info,
                                           sheet_row_get_distance_pts, pinfo->scaling.dim.rows, 1., col_header_height,
                                           repeat_top_use, repeat_top_start, repeat_top_end, pinfo->page_breaks.h);
        pxy = compute_scale_fit_to (sheet, print_area.start.col, print_area.end.col, page_width, sheet_col_get_info,
                                    sheet_col_get_distance_pts, pinfo->scaling.dim.cols, pxy, row_header_width,
                                    repeat_left_use, repeat_left_start, repeat_left_end, pinfo->page_breaks.v);
        pinfo->scaling.percentage.x = pinfo->scaling.percentage.y = pxy * 100.;
    }
    double px = pinfo->scaling.percentage.x / 100., py = pinfo->scaling.percentage.y / 100.;
    if (px <= 0.) px = 1.;
    if (py <= 0.) py = 1.;
    double usable_x = page_width / px, usable_y = page_height / py;
    double hscale = sheet->display_formulas ? 2 : 1;
    _columns = g_array_new (FALSE, TRUE, sizeof (PaginationInfo));
    _rows = g_array_new (FALSE, TRUE, sizeof (PaginationInfo));
    paginate (_columns, sheet, print_area.start.col, print_area.end.col, (usable_x - row_header_width) / hscale,
              repeat_left_use, repeat_left_start, repeat_left_end, sheet_col_get_distance_pts, sheet_col_get_info,
              pinfo->page_breaks.v, TRUE);
    paginate (_rows, sheet, print_area.start.row, print_area.end.row, usable_y - col_header_height,
              repeat_top_use, repeat_top_start, repeat_top_end, sheet_row_get_distance_pts, sheet_row_get_info,
              pinfo->page_breaks.h, TRUE);
    _hfi = gnm_print_hf_render_info_new ();
    _hfi->sheet = sheet;
    _hfi->pages = (int) self.pageCount;
    return self;
}

- (void)dealloc
{
    if (_columns)
        g_array_free (_columns, TRUE);
    if (_rows)
        g_array_free (_rows, TRUE);
    if (_hfi)
        gnm_print_hf_render_info_free (_hfi);
}

- (NSInteger)pageCount { return (NSInteger) _columns->len * (NSInteger) _rows->len; }
- (CGSize)pageSize { return CGSizeMake (_paperWidth, _paperHeight); }

/* print_get_sheet_page_range */
- (BOOL)_rangeOfPage:(NSInteger)page into:(SheetPageRange *)gsr
{
    if (page < 0 || page >= self.pageCount)
        return NO;
    unsigned col, row;
    if (_sheet->print_info->print_across_then_down) {
        col = (unsigned) page % _columns->len;
        row = (unsigned) page / _columns->len;
    } else {
        col = (unsigned) page / _rows->len;
        row = (unsigned) page % _rows->len;
    }
    PaginationInfo *c = &g_array_index (_columns, PaginationInfo, col);
    PaginationInfo *rr = &g_array_index (_rows, PaginationInfo, row);
    int last_col = gnm_sheet_get_last_col (_sheet), last_row = gnm_sheet_get_last_row (_sheet);
    range_init (&gsr->range, MIN (c->rc, last_col), MIN (rr->rc, last_row),
                MIN (c->rc + c->count - 1, last_col), MIN (rr->rc + rr->count - 1, last_row));
    gsr->n_rep_cols = c->n_rep;
    gsr->first_rep_cols = c->first_rep;
    gsr->n_rep_rows = rr->n_rep;
    gsr->first_rep_rows = rr->first_rep;
    return YES;
}

- (NSString *)rangeNameOfPage:(NSInteger)page
{
    SheetPageRange gsr;
    return [self _rangeOfPage:page into:&gsr] ? GnmString (range_as_string (&gsr.range)) : @"";
}

- (void)drawPage:(NSInteger)page inContext:(CGContextRef)context
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    SheetPageRange gsr;
    if (![self _rangeOfPage:page into:&gsr])
        return;
    Sheet *sheet = _sheet;
    GnmPrintInformation *pinfo = sheet->print_info;
    cairo_surface_t *surface = NULL;
    cairo_t *cr = gnm_cocoa_cairo_for_context (context, CGRectMake (0, 0, _paperWidth, _paperHeight), &surface);
    PangoContext *pcontext = pango_cairo_create_context (cr);
    pango_cairo_context_set_resolution (pcontext, 72.);
    _hfi->page = (int) page + 1;
    _hfi->pages = (int) self.pageCount;
    _hfi->page_area = gsr.range;
    _hfi->top_repeating.col = gsr.first_rep_cols;
    _hfi->top_repeating.row = gsr.first_rep_rows;

    /* print_page */
    double px = pinfo->scaling.percentage.x / 100., py = pinfo->scaling.percentage.y / 100.;
    if (px <= 0.) px = 1.;
    if (py <= 0.) py = 1.;
    double header, footer, left, right, below_header, above_footer;
    print_info_get_margins (pinfo, &header, &footer, &left, &right, &below_header, &above_footer);
    double col_header_height = 0., row_header_width = 0., rep_row_height = 0., rep_col_width = 0.;
    if (pinfo->print_titles) {
        col_header_height = sheet->rows.default_style.size_pts;
        row_header_width = sheet->cols.default_style.size_pts;
    }
    double width = _paperWidth - left - right;
    double height = _paperHeight - below_header - above_footer;
    double main_height = sheet_row_get_distance_pts (sheet, gsr.range.start.row, gsr.range.end.row + 1);
    double main_width = sheet_col_get_distance_pts (sheet, gsr.range.start.col, gsr.range.end.col + 1);
    if (gsr.n_rep_rows > 0)
        rep_row_height = sheet_row_get_distance_pts (sheet, gsr.first_rep_rows, gsr.first_rep_rows + gsr.n_rep_rows);
    if (gsr.n_rep_cols > 0)
        rep_col_width = sheet_col_get_distance_pts (sheet, gsr.first_rep_cols, gsr.first_rep_cols + gsr.n_rep_cols);
    GnmRange r_repeating_intersect;
    if (gsr.n_rep_rows > 0 || gsr.n_rep_cols > 0)
        range_init (&r_repeating_intersect, gsr.first_rep_cols, gsr.first_rep_rows,
                    gsr.first_rep_cols + gsr.n_rep_cols - 1, gsr.first_rep_rows + gsr.n_rep_rows - 1);
    double print_height = main_height + col_header_height + rep_row_height;
    double print_width = main_width + row_header_width + rep_col_width;

    /* the GTK print context's origin: the printable area's top-left */
    cairo_translate (cr, left, header);
    if (below_header > header) {
        cairo_save (cr);
        print_hf_line (cr, pinfo->header, FALSE, width, _hfi);
        cairo_restore (cr);
    }
    if (above_footer > footer) {
        cairo_save (cr);
        cairo_translate (cr, 0, height + (below_header - header) + (above_footer - footer));
        print_hf_line (cr, pinfo->footer, TRUE, width, _hfi);
        cairo_restore (cr);
    }
    cairo_save (cr);
    cairo_translate (cr, 0, below_header - header);
    if (pinfo->center_horizontally || pinfo->center_vertically) {
        double shift_x = pinfo->center_horizontally ? (width - print_width * px) / 2 : 0;
        double shift_y = pinfo->center_vertically ? (height - print_height * py) / 2 : 0;
        cairo_translate (cr, shift_x, shift_y);
    }
    cairo_scale (cr, px, py);
    if (pinfo->print_titles) {
        cairo_save (cr);
        if (gsr.n_rep_cols > 0) {
            print_page_col_headers (cr, sheet, &r_repeating_intersect, row_header_width, col_header_height);
            cairo_translate (cr, rep_col_width, 0);
        }
        print_page_col_headers (cr, sheet, &gsr.range, row_header_width, col_header_height);
        cairo_restore (cr);
        cairo_save (cr);
        if (gsr.n_rep_rows > 0) {
            print_page_row_headers (cr, sheet, &r_repeating_intersect, row_header_width, col_header_height);
            cairo_translate (cr, 0, rep_row_height);
        }
        print_page_row_headers (cr, sheet, &gsr.range, row_header_width, col_header_height);
        cairo_restore (cr);
        cairo_translate (cr, row_header_width, col_header_height);
    }
    if (gsr.n_rep_rows > 0 && gsr.n_rep_cols > 0)
        print_page_cells (pcontext, cr, sheet, &r_repeating_intersect, GNM_COL_MARGIN, -GNM_ROW_MARGIN);
    if (gsr.n_rep_rows > 0) {
        GnmRange r;
        range_init (&r, gsr.range.start.col, gsr.first_rep_rows, gsr.range.end.col, gsr.first_rep_rows + gsr.n_rep_rows - 1);
        cairo_save (cr);
        if (gsr.n_rep_cols > 0)
            cairo_translate (cr, rep_col_width, 0);
        print_page_cells (pcontext, cr, sheet, &r, GNM_COL_MARGIN, -GNM_ROW_MARGIN);
        cairo_restore (cr);
        cairo_translate (cr, 0, rep_row_height);
    }
    if (gsr.n_rep_cols > 0) {
        GnmRange r;
        range_init (&r, gsr.first_rep_cols, gsr.range.start.row, gsr.first_rep_cols + gsr.n_rep_cols - 1, gsr.range.end.row);
        print_page_cells (pcontext, cr, sheet, &r, GNM_COL_MARGIN, -GNM_ROW_MARGIN);
        cairo_translate (cr, rep_col_width, 0);
    }
    print_page_cells (pcontext, cr, sheet, &gsr.range, GNM_COL_MARGIN, -GNM_ROW_MARGIN);
    cairo_restore (cr);
    g_object_unref (pcontext);
    cairo_destroy (cr);
    cairo_surface_flush (surface);
    cairo_surface_destroy (surface);
}

@end

#pragma mark - Sheet

@implementation GnmSheet (Printing)

- (GnmPrintSettings *)printSettings
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    return sheet ? [[GnmPrintSettings alloc] initWithPrintInformation:sheet->print_info] : [[GnmPrintSettings alloc] init];
}

- (BOOL)setPrintSettings:(GnmPrintSettings *)settings forAllSheets:(BOOL)allSheets error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    if (!sheet || !workbook)
        return NO;
    GnmPrintInformation *pi = gnm_print_info_dup (sheet->print_info);
    [settings _applyToPrintInformation:pi];
    BOOL ok = [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_print_setup (wbc, allSheets ? NULL : sheet, pi);
    } description:@"Could not change the page setup." error:error];
    gnm_print_info_free (pi);
    return ok;
}

- (GnmPrintJob *)printJobForSelectionOnly:(BOOL)selectionOnly ignoringPrintArea:(BOOL)ignoringPrintArea
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    if (!self.engineSheet)
        return nil;
    return [[GnmPrintJob alloc] initWithSheet:self selectionOnly:selectionOnly ignoringPrintArea:ignoringPrintArea];
}

- (NSString *)printAreaName
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    if (!sheet)
        return @"";
    GnmRange *r = sheet_get_nominal_printarea (sheet);
    if (!r)
        return @"";
    NSString *name = GnmString (range_as_string (r));
    g_free (r);
    return name;
}

- (BOOL)getPrintArea:(GnmCellRange *)range
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    if (!sheet)
        return NO;
    GnmRange *r = sheet_get_nominal_printarea (sheet);
    if (!r)
        return NO;
    if (range)
        *range = GnmCellRangeMake (r->start.col, r->start.row, r->end.col, r->end.row);
    g_free (r);
    return YES;
}

static NSArray<NSNumber *> *manual_breaks (GnmPageBreaks const *breaks)
{
    NSMutableArray *result = [NSMutableArray array];
    if (!breaks || !breaks->details)
        return result;
    for (guint i = 0; i < breaks->details->len; i++) {
        GnmPageBreak const *pb = &g_array_index (breaks->details, GnmPageBreak, i);
        if (pb->type == GNM_PAGE_BREAK_MANUAL)
            [result addObject:@(pb->pos)];
    }
    return result;
}

- (NSArray<NSNumber *> *)columnPageBreaks
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    return sheet && sheet->print_info ? manual_breaks (sheet->print_info->page_breaks.v) : @[];
}

- (NSArray<NSNumber *> *)rowPageBreaks
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    return sheet && sheet->print_info ? manual_breaks (sheet->print_info->page_breaks.h) : @[];
}

- (BOOL)hasManualPageBreaks
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    return sheet && sheet->print_info && print_info_has_manual_breaks (sheet->print_info);
}

- (BOOL)togglePageBreakAtEditPositionForColumns:(BOOL)columns error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    if (!sheet || !workbook)
        return NO;
    return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_page_break_toggle (wbc, sheet, columns);
    } description:@"Could not change the page break." error:error];
}

- (BOOL)clearPageBreaksWithError:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    if (!sheet || !workbook)
        return NO;
    return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_page_breaks_clear (wbc, sheet);
    } description:@"Could not clear the page breaks." error:error];
}

- (BOOL)setPrintArea:(NSString *)rangeName error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    if (!sheet || !workbook)
        return NO;
    /* cb_file_print_area_set and cb_file_print_area_clear */
    GnmParsePos pp;
    parse_pos_init_sheet (&pp, sheet);
    GnmExprTop const *texpr;
    char *label;
    if (rangeName.length) {
        GnmValue *v = value_new_cellrange_parsepos_str (&pp, rangeName.UTF8String,
                                                        GNM_EXPR_PARSE_UNKNOWN_NAMES_ARE_STRINGS | GNM_EXPR_PARSE_FORCE_ABSOLUTE_REFERENCES);
        if (!v || !VALUE_IS_CELLRANGE (v)) {
            if (v)
                value_release (v);
            if (error)
                *error = [workbook.engine _errorWithCode:GnmErrorCommandFailed description:@"The print area is not a range." collected:@[]];
            return NO;
        }
        GnmRange r;
        range_init_value (&r, v);
        texpr = gnm_expr_top_new_constant (v);
        label = g_strdup_printf ("Set Print Area to %s", range_as_string (&r));
    } else {
        texpr = gnm_expr_top_new_constant (value_new_error_REF (NULL));
        label = g_strdup ("Clear Print Area");
    }
    BOOL ok = [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_define_name (wbc, "Print_Area", &pp, texpr, label);
    } description:@"Could not change the print area." error:error];
    g_free (label);
    return ok;
}

@end
