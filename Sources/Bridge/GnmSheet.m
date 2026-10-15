// GnmSheet: the Cocoa SheetControl, sheet geometry, and grid drawing.
//
// draw_region() is a port of item_grid_draw_region (item-grid.c:444-880 in
// 1.12.62) with the GTK canvas, style context, selection painting, and
// in-place editor removed.  Selection and the edit cell are drawn by the app.
#import "GnmPrivate.h"
#include <math.h>

/* ------------------------------------------------------------------------
 * SheetControl subclass.
 */
typedef struct {
    SheetControlClass base;
} GnmCocoaSheetControlClass;

static GObjectClass *csc_parent_class;

static GnmSheet *
sc_owner (SheetControl *sc)
{
    GnmCocoaSheetControl *c = (GnmCocoaSheetControl *) sc;
    return c->owner ? (__bridge GnmSheet *) c->owner : nil;
}

static void csc_resize (SheetControl *sc, G_GNUC_UNUSED gboolean force_scroll)
{
    [sc_owner (sc) _controlGeometryDidChange];
}
static void csc_redraw_all (SheetControl *sc, gboolean headers)
{
    [sc_owner (sc) _controlNeedsDisplayIncludingHeaders:headers];
}
static void csc_redraw_range (SheetControl *sc, GnmRange const *r)
{
    [sc_owner (sc) _controlNeedsDisplayInRange:r];
}
static void csc_redraw_headers (SheetControl *sc, gboolean const col, gboolean const row,
                                G_GNUC_UNUSED GnmRange const *r)
{
    [sc_owner (sc) _controlNeedsHeaderDisplayForColumns:col rows:row];
}
static void csc_ant (SheetControl *sc)
{
    [sc_owner (sc) _controlMarchingAntsDidChange];
}
static void csc_unant (SheetControl *sc)
{
    [sc_owner (sc) _controlMarchingAntsDidChange];
}
static void csc_scrollbar_config (SheetControl *sc)
{
    [sc_owner (sc) _controlGeometryDidChange];
}
static void csc_mode_edit (G_GNUC_UNUSED SheetControl *sc)
{
    /* No range-selection or object modes yet. */
}
static void csc_set_top_left (SheetControl *sc, int col, int row)
{
    [sc_owner (sc) _controlScrollToColumn:col row:row];
}
static void csc_recompute_visible_region (SheetControl *sc, G_GNUC_UNUSED gboolean full)
{
    [sc_owner (sc) _controlGeometryDidChange];
}
static void csc_make_cell_visible (SheetControl *sc, int col, int row, G_GNUC_UNUSED gboolean couple_panes)
{
    [sc_owner (sc) _controlMakeVisibleColumn:col row:row];
}
static void csc_cursor_bound (SheetControl *sc, GnmRange const *r)
{
    [sc_owner (sc) _controlCursorDidMoveToRange:r];
}
static void csc_set_panes (SheetControl *sc)
{
    [sc_owner (sc) _controlFrozenPanesDidChange];
}
static void csc_object_create_view (SheetControl *sc, G_GNUC_UNUSED SheetObject *so)
{
    /* Objects are drawn directly from the model (drawSheetObjectsInRect:);
     * the engine calls this from an idle after an object joins a sheet. */
    [sc_owner (sc) _objectsDidChange];
    [sc_owner (sc) _controlNeedsDisplayIncludingHeaders:NO];
}
static void csc_scale_changed (SheetControl *sc)
{
    [sc_owner (sc) _controlGeometryDidChange];
}
static void csc_show_im_tooltip (G_GNUC_UNUSED SheetControl *sc, G_GNUC_UNUSED GnmInputMsg *im,
                                 G_GNUC_UNUSED GnmCellPos *pos)
{
}
static void csc_freeze_object_view (G_GNUC_UNUSED SheetControl *sc, G_GNUC_UNUSED gboolean freeze)
{
}

static void
csc_finalize (GObject *object)
{
    [sc_owner ((SheetControl *) object) _controlWasFinalized];
    csc_parent_class->finalize (object);
}

static void
csc_class_init (GObjectClass *object_class)
{
    SheetControlClass *sc_class = (SheetControlClass *) object_class;
    csc_parent_class = g_type_class_peek_parent (object_class);
    object_class->finalize = csc_finalize;
    sc_class->resize = csc_resize;
    sc_class->redraw_all = csc_redraw_all;
    sc_class->redraw_range = csc_redraw_range;
    sc_class->redraw_headers = csc_redraw_headers;
    sc_class->ant = csc_ant;
    sc_class->unant = csc_unant;
    sc_class->scrollbar_config = csc_scrollbar_config;
    sc_class->mode_edit = csc_mode_edit;
    sc_class->set_top_left = csc_set_top_left;
    sc_class->recompute_visible_region = csc_recompute_visible_region;
    sc_class->make_cell_visible = csc_make_cell_visible;
    sc_class->cursor_bound = csc_cursor_bound;
    sc_class->set_panes = csc_set_panes;
    sc_class->object_create_view = csc_object_create_view;
    sc_class->scale_changed = csc_scale_changed;
    sc_class->show_im_tooltip = csc_show_im_tooltip;
    sc_class->freeze_object_view = csc_freeze_object_view;
}

GSF_CLASS (GnmCocoaSheetControl, gnm_cocoa_sheet_control,
           csc_class_init, NULL, GNM_SHEET_CONTROL_TYPE)

/* ------------------------------------------------------------------------
 * Geometry helpers.  Positions are sums of visible column widths or row
 * heights from the sheet origin, which is what sheet_colrow_get_distance_pixels
 * returns (it caches per 128-row segment, so a binary search is cheap).
 */

static inline gint64
colrow_distance (Sheet const *sheet, gboolean is_cols, int from, int to)
{
    return from < to ? sheet_colrow_get_distance_pixels (sheet, is_cols, from, to) : 0;
}

/* The largest index whose left/top edge is at or before `pos`; the edge
 * position goes to *origin.  Replaces gnm_pane_find_col/row for a pane that
 * starts at the sheet origin. */
static int
colrow_at (Sheet const *sheet, gboolean is_cols, gint64 pos, gint64 *origin)
{
    int lo = 0, hi = is_cols ? gnm_sheet_get_last_col (sheet) : gnm_sheet_get_last_row (sheet);
    if (pos <= 0) {
        if (origin) *origin = 0;
        return 0;
    }
    while (lo < hi) {
        int mid = lo + (hi - lo + 1) / 2;
        if (colrow_distance (sheet, is_cols, 0, mid) <= pos)
            lo = mid;
        else
            hi = mid - 1;
    }
    if (origin)
        *origin = colrow_distance (sheet, is_cols, 0, lo);
    return lo;
}

/* ------------------------------------------------------------------------
 * Grid drawing (port of item-grid.c).  Colors and sizes are the defaults of
 * upstream's src/gnumeric.css.
 */

typedef struct {
    Sheet const *sheet;
    WorkbookView const *wbv;
    GnmCellDrawStyle cell_draw_style;
    GdkRGBA function_marker_color;
    GdkRGBA function_marker_border_color;
    int function_marker_size;
} DrawContext;

static void
draw_context_init (DrawContext *dc, Sheet const *sheet, WorkbookView const *wbv)
{
    dc->sheet = sheet;
    dc->wbv = wbv;
    dc->cell_draw_style.extension_marker_color = (GdkRGBA) { 1.0, 0.0, 0.0, 0.7 };
    dc->cell_draw_style.extension_marker_size = 12;
    dc->function_marker_color = (GdkRGBA) { 0.5, 1.0, 0.5, 1.0 };
    dc->function_marker_border_color = (GdkRGBA) { 0.33, 0.33, 0.33, 1.0 };
    dc->function_marker_size = 10;
}

static void
draw_function_marker (DrawContext const *dc, GnmCell const *cell, cairo_t *cr,
                      double x, double y, double w, double h, int const dir)
{
    int size = dc->function_marker_size;
    if (cell == NULL || !gnm_cell_has_expr (cell))
        return;
    cairo_save (cr);
    cairo_new_path (cr);
    cairo_rectangle (cr, x, y, w + 1, h + 1);
    cairo_clip (cr);
    cairo_new_path (cr);
    if (dir > 0) {
        cairo_move_to (cr, x, y);
        cairo_line_to (cr, x + size, y);
        cairo_arc (cr, x, y, size, 0., M_PI / 2.);
    } else {
        cairo_move_to (cr, x + w, y);
        cairo_line_to (cr, x + w, y + size);
        cairo_arc (cr, x + w, y, size, M_PI / 2., M_PI);
    }
    cairo_close_path (cr);
    gdk_cairo_set_source_rgba (cr, &dc->function_marker_color);
    cairo_fill_preserve (cr);
    gdk_cairo_set_source_rgba (cr, &dc->function_marker_border_color);
    cairo_set_line_width (cr, 0.5);
    cairo_stroke (cr);
    cairo_restore (cr);
}

static void
draw_merged_range (DrawContext const *dc, cairo_t *cr, int start_x, int start_y,
                   GnmRange const *view, GnmRange const *range)
{
    Sheet const *sheet = dc->sheet;
    int l, r, t, b, last;
    gboolean show_function_cell_markers = dc->wbv->show_function_cell_markers;
    gboolean show_extension_markers = dc->wbv->show_extension_markers;
    GnmCell const *cell = sheet_cell_get (sheet, range->start.col, range->start.row);
    int const dir = sheet->text_is_rtl ? -1 : 1;
    GnmStyleConditions *conds;
    GnmStyle const *style = sheet_style_get (sheet, range->start.col, range->start.row);

    l = r = start_x;
    if (view->start.col < range->start.col)
        l += dir * colrow_distance (sheet, TRUE, view->start.col, range->start.col);
    if (range->end.col <= (last = view->end.col))
        last = range->end.col;
    r += dir * colrow_distance (sheet, TRUE, view->start.col, last + 1);

    t = b = start_y;
    if (view->start.row < range->start.row)
        t += colrow_distance (sheet, FALSE, view->start.row, range->start.row);
    if (range->end.row <= (last = view->end.row))
        last = range->end.row;
    b += colrow_distance (sheet, FALSE, view->start.row, last + 1);

    if (l == r || t == b)
        return;

    conds = gnm_style_get_conditions (style);
    if (conds) {
        GnmEvalPos ep;
        int res;
        eval_pos_init (&ep, (Sheet *) sheet, range->start.col, range->start.row);
        if ((res = gnm_style_conditions_eval (conds, &ep)) >= 0)
            style = gnm_style_get_cond_style (style, res);
    }

    if (gnm_pattern_background_set (style, cr, FALSE, NULL)) {
        if (dir > 0)
            cairo_rectangle (cr, l, t, r - l + 1, b - t + 1);
        else
            cairo_rectangle (cr, r, t, l - r + 1, b - t + 1);
        cairo_fill (cr);
    }

    if (range->start.col < view->start.col)
        l -= dir * colrow_distance (sheet, TRUE, range->start.col, view->start.col);
    if (view->end.col < range->end.col)
        r += dir * colrow_distance (sheet, TRUE, view->end.col + 1, range->end.col + 1);
    if (range->start.row < view->start.row)
        t -= colrow_distance (sheet, FALSE, range->start.row, view->start.row);
    if (view->end.row < range->end.row)
        b += colrow_distance (sheet, FALSE, view->end.row + 1, range->end.row + 1);

    if (cell != NULL) {
        ColRowInfo *ri = sheet_row_get (sheet, range->start.row);
        if (ri->needs_respan)
            row_calc_spans (ri, cell->pos.row, sheet);
        if (dir > 0) {
            if (show_function_cell_markers)
                draw_function_marker (dc, cell, cr, l, t, r - l, b - t, dir);
            cell_draw (cell, cr, l, t, r - l, b - t, -1,
                       show_extension_markers, &dc->cell_draw_style);
        } else {
            if (show_function_cell_markers)
                draw_function_marker (dc, cell, cr, r, t, l - r, b - t, dir);
            cell_draw (cell, cr, r, t, l - r, b - t, -1,
                       show_extension_markers, &dc->cell_draw_style);
        }
    }
    if (dir > 0)
        gnm_style_border_draw_diag (style, cr, l, t, r, b);
    else
        gnm_style_border_draw_diag (style, cr, r, t, l, b);
}

static void
draw_background (cairo_t *cr, GnmStyle const *style, int x, int y, int w, int h)
{
    if (gnm_pattern_background_set (style, cr, FALSE, NULL)) {
        cairo_rectangle (cr, x, y, w + 1, h + 1);
        cairo_fill (cr);
    }
    gnm_style_border_draw_diag (style, cr, x, y, x + w, y + h);
}

static gint
merged_col_cmp (GnmRange const *a, GnmRange const *b)
{
    return a->start.col - b->start.col;
}

/* Draw the cells intersecting the sheet-pixel rectangle [x0,x1) x [y0,y1),
 * restricted to `bound`, onto `cr`, whose user space is sheet pixels. */
/* `mirror` > 0 draws a right-to-left sheet: the columns run leftward from
 * the cairo x `mirror` of the sheet's left edge (dir = -1 below, as
 * item-grid.c under a right-to-left canvas); x0..x1 stay sheet pixels. */
static void
draw_region (DrawContext const *dc, cairo_t *cr,
             gint64 x0, gint64 y0, gint64 x1, gint64 y1,
             GnmRange const *bound, GdkRGBA const *background, double mirror)
{
    Sheet const *sheet = dc->sheet;
    ColRowInfo const *ri = NULL, *next_ri = NULL;
    int const dir = sheet->text_is_rtl ? -1 : 1;
    gboolean show_function_cell_markers = dc->wbv->show_function_cell_markers;
    gboolean show_extension_markers = dc->wbv->show_extension_markers;
    int x;
    gint64 y, start_x, start_y, offset;
    int col, row, n, start_col, end_col, start_row, end_row;
    GnmStyleRow sr, next_sr;
    GnmStyle const **styles;
    GnmBorder const **borders, **prev_vert;
    GnmBorder const *none = sheet->hide_grid ? NULL : gnm_style_border_none ();
    gpointer *sr_array_data;
    GnmRange view;
    GSList *merged_active, *merged_active_seen, *merged_used, *merged_unused, *ptr, **lag;
    int *colwidths;

    start_row = colrow_at (sheet, FALSE, y0 - 2, &start_y);
    end_row = colrow_at (sheet, FALSE, y1 + 2, NULL);
    start_col = colrow_at (sheet, TRUE, x0 - 2, &start_x);
    end_col = colrow_at (sheet, TRUE, x1 + 2, NULL);

    /* clip to bounds */
    if (start_col < bound->start.col) {
        start_col = bound->start.col;
        start_x = colrow_distance (sheet, TRUE, 0, start_col);
    }
    if (start_row < bound->start.row) {
        start_row = bound->start.row;
        start_y = colrow_distance (sheet, FALSE, 0, start_row);
    }
    if (end_col > bound->end.col)
        end_col = bound->end.col;
    if (end_row > bound->end.row)
        end_row = bound->end.row;
    if (start_col > end_col || start_row > end_row)
        return;

    /* Skip any hidden cols/rows at the start */
    for (; start_col <= end_col; ++start_col) {
        ri = sheet_col_get_info (sheet, start_col);
        if (ri->visible)
            break;
    }
    for (; start_row <= end_row; ++start_row) {
        ri = sheet_row_get_info (sheet, start_row);
        if (ri->visible)
            break;
    }
    if (end_col < bound->start.col || start_col > bound->end.col ||
        end_row < bound->start.row || start_row > bound->end.row)
        return;

    /* Respan all rows that need it. */
    for (row = start_row; row <= end_row; row++) {
        ColRowInfo const *rri = sheet_row_get_info (sheet, row);
        if (rri->visible && rri->needs_respan)
            row_calc_spans ((ColRowInfo *) rri, row, sheet);
    }

    sheet_style_update_grid_color (sheet, NULL);

    /* A right-to-left sheet: the first column's right edge, in cairo x. */
    if (mirror > 0)
        start_x = (gint64) llround (mirror) - start_x;

    /* Fill entire region with the background (even past the far edge) */
    cairo_save (cr);
    gdk_cairo_set_source_rgba (cr, background);
    cairo_rectangle (cr, mirror > 0 ? (double) ((gint64) llround (mirror) - x1) : (double) x0, y0, x1 - x0, y1 - y0);
    cairo_fill (cr);
    cairo_restore (cr);

    merged_active = merged_active_seen = merged_used = NULL;
    merged_unused = gnm_sheet_merge_get_overlap (sheet,
        range_init (&view, start_col, start_row, end_col, end_row));

    n = end_col - start_col + 3;
    sr_array_data = g_new (gpointer, n * 8);
    style_row_init (&prev_vert, &sr, &next_sr, start_col, end_col, sr_array_data, sheet->hide_grid);

    next_sr.row = sr.row = row = start_row;
    sheet_style_get_row (sheet, &sr);

    colwidths = g_new (int, n);
    colwidths -= start_col;
    for (col = start_col; col <= end_col; col++) {
        ColRowInfo const *ci = sheet_col_get_info (sheet, col);
        colwidths[col] = ci->visible ? ci->size_pixels : -1;
    }

    x = (int) start_x;
    for (y = start_y; row <= end_row; row = sr.row = next_sr.row, ri = next_ri) {
        g_return_if_fail (merged_active == NULL);

        while (merged_active_seen != NULL) {
            GSList *tmp = merged_active_seen->next;
            merged_active_seen->next = merged_active;
            merged_active = merged_active_seen;
            merged_active_seen = tmp;
        }

        /* find the next visible row */
        while (1) {
            ++next_sr.row;
            if (next_sr.row <= end_row) {
                next_ri = sheet_row_get_info (sheet, next_sr.row);
                if (next_ri->visible) {
                    sheet_style_get_row (sheet, &next_sr);
                    break;
                }
            } else {
                GnmBorder const *vert =
                    next_sr.row == gnm_sheet_get_max_rows (sheet) ? NULL : none;
                for (col = start_col; col <= end_col; ++col) {
                    next_sr.vertical[col] = vert;
                    next_sr.bottom[col] = none;
                }
                break;
            }
        }

        /* merges that start on this row (or above, on the first row) */
        view.start.row = row;
        lag = &merged_unused;
        for (ptr = merged_unused; ptr != NULL;) {
            GnmRange *const r = ptr->data;
            if (r->start.row <= row) {
                GSList *tmp = ptr;
                ptr = *lag = tmp->next;
                if (r->end.row < row) {
                    tmp->next = merged_used;
                    merged_used = tmp;
                } else {
                    ColRowInfo const *ci = sheet_col_get_info (sheet, r->start.col);
                    g_slist_free_1 (tmp);
                    merged_active = g_slist_insert_sorted (merged_active, r,
                                                           (GCompareFunc) merged_col_cmp);
                    if (ci->visible)
                        draw_merged_range (dc, cr, (int) start_x, (int) y, &view, r);
                }
            } else {
                lag = &(ptr->next);
                ptr = ptr->next;
            }
        }

        for (col = start_col, x = (int) start_x; col <= end_col; col++) {
            GnmStyle const *style;
            CellSpanInfo const *span;
            ColRowInfo const *ci = sheet_col_get_info (sheet, col);

            if (!ci->visible) {
                if (merged_active != NULL) {
                    GnmRange const *r = merged_active->data;
                    if (r->end.col == col) {
                        ptr = merged_active;
                        merged_active = merged_active->next;
                        if (r->end.row <= row) {
                            ptr->next = merged_used;
                            merged_used = ptr;
                        } else {
                            ptr->next = merged_active_seen;
                            merged_active_seen = ptr;
                        }
                    }
                }
                continue;
            }

            /* Skip any merged regions */
            if (merged_active != NULL) {
                GnmRange const *r = merged_active->data;
                if (r->start.col <= col) {
                    gboolean clear_top, clear_bottom = FALSE;
                    int i, first = r->start.col;
                    int last = r->end.col;

                    ptr = merged_active;
                    merged_active = merged_active->next;
                    if (r->end.row <= row) {
                        ptr->next = merged_used;
                        merged_used = ptr;
                        if (r->end.row < row)
                            goto plain_draw;
                    } else {
                        ptr->next = merged_active_seen;
                        merged_active_seen = ptr;
                        if (next_sr.row <= r->end.row)
                            clear_bottom = TRUE;
                    }

                    x += dir * colrow_distance (sheet, TRUE, col, last + 1);
                    col = last;

                    if (first < start_col) {
                        first = start_col;
                        sr.vertical[first] = NULL;
                    }
                    if (last > end_col) {
                        last = end_col;
                        sr.vertical[last + 1] = NULL;
                    }
                    clear_top = (r->start.row != row);

                    for (i = first; i <= last; i++) {
                        if (clear_top)
                            sr.top[i] = NULL;
                        if (clear_bottom)
                            sr.bottom[i] = NULL;
                        if (i > first)
                            sr.vertical[i] = NULL;
                    }
                    continue;
                }
            }

plain_draw:
            if (dir < 0)
                x -= ci->size_pixels;
            style = sr.styles[col];
            {
                /* item-grid.c item_grid_draw_background: the conditional
                 * style that holds for this cell, if any */
                GnmStyleConditions *conds = gnm_style_get_conditions (style);
                if (conds) {
                    GnmEvalPos ep;
                    int res;
                    eval_pos_init (&ep, (Sheet *) sheet, col, row);
                    if ((res = gnm_style_conditions_eval (conds, &ep)) >= 0)
                        style = gnm_style_get_cond_style (style, res);
                }
            }
            draw_background (cr, style, x, (int) y, ci->size_pixels, ri->size_pixels);

            if (NULL == ri->spans || NULL == (span = row_span_get (ri, col))) {
                GnmCell const *cell = sheet_cell_get (sheet, col, row);
                if (!gnm_cell_is_empty (cell)) {
                    if (show_function_cell_markers)
                        draw_function_marker (dc, cell, cr, x, y, ci->size_pixels,
                                              ri->size_pixels, dir);
                    cell_draw (cell, cr, x, (int) y, ci->size_pixels, ri->size_pixels, -1,
                               show_extension_markers, &dc->cell_draw_style);
                }
            } else if (col == span->right || col == end_col) {
                GnmCell const *cell = span->cell;
                int const start_span_col = span->left;
                int const end_span_col = span->right;
                int real_x = x;
                ColRowInfo const *cell_col = sheet_col_get_info (sheet, cell->pos.col);
                int center_offset = cell_col->size_pixels / 2;
                int tmp_width = ci->size_pixels;

                if (col != cell->pos.col)
                    style = sheet_style_get (sheet, cell->pos.col, row);

                if (dir > 0 && start_span_col != cell->pos.col)
                    center_offset += colrow_distance (sheet, TRUE, start_span_col, cell->pos.col);
                else if (dir < 0 && end_span_col != cell->pos.col)
                    center_offset += colrow_distance (sheet, TRUE, cell->pos.col, end_span_col);

                if (start_span_col != col) {
                    offset = colrow_distance (sheet, TRUE, start_span_col, col);
                    tmp_width += offset;
                    if (dir > 0)
                        real_x -= offset;
                    sr.vertical[col] = NULL;
                }
                if (end_span_col != col) {
                    offset = colrow_distance (sheet, TRUE, col + 1, end_span_col + 1);
                    tmp_width += offset;
                    if (dir < 0)
                        real_x -= offset;
                }

                if (show_function_cell_markers)
                    draw_function_marker (dc, cell, cr, real_x, y, tmp_width, ri->size_pixels, dir);
                cell_draw (cell, cr, real_x, (int) y, tmp_width, ri->size_pixels, center_offset,
                           show_extension_markers, &dc->cell_draw_style);
            } else if (col != span->left)
                sr.vertical[col] = NULL;

            if (dir > 0)
                x += ci->size_pixels;
        }
        gnm_style_borders_row_draw (prev_vert, &sr, cr, (int) start_x, (int) y,
                                    (int) (y + ri->size_pixels), colwidths, TRUE, dir);

        while (merged_active != NULL) {
            GnmRange const *r = merged_active->data;
            ptr = merged_active;
            merged_active = merged_active->next;
            if (r->end.row <= row) {
                ptr->next = merged_used;
                merged_used = ptr;
            } else {
                ptr->next = merged_active_seen;
                merged_active_seen = ptr;
            }
        }

        /* roll the pointers */
        borders = prev_vert; prev_vert = sr.vertical;
        sr.vertical = next_sr.vertical; next_sr.vertical = borders;
        borders = sr.top; sr.top = sr.bottom;
        sr.bottom = next_sr.top = next_sr.bottom; next_sr.bottom = borders;
        styles = sr.styles; sr.styles = next_sr.styles; next_sr.styles = styles;

        y += ri->size_pixels;
    }

    if (row == gnm_sheet_get_max_rows (sheet) && ri)
        gnm_style_borders_row_draw (prev_vert, &sr, cr, (int) start_x, (int) y,
                                    (int) (y + ri->size_pixels), colwidths, TRUE, dir);

    g_slist_free (merged_used);
    g_slist_free (merged_active_seen);
    g_slist_free (merged_unused);
    g_free (sr_array_data);
    g_free (colwidths + start_col);
}

/* Pixel rectangle of a sheet object: port of scg_object_anchor_to_coords
 * (sheet-control-gui.c) for a pane at the sheet origin. */
static void
object_pixel_frame (Sheet const *sheet, SheetObject const *so, double *coords)
{
    SheetObjectAnchor const *anchor = sheet_object_get_anchor (so);
    GODrawingAnchorDir direction;
    gint64 pixels[4];
    GnmRange const *r = &anchor->cell_bound;

    if (anchor->mode != GNM_SO_ANCHOR_ABSOLUTE) {
        pixels[0] = colrow_distance (sheet, TRUE, 0, r->start.col);
        pixels[1] = colrow_distance (sheet, FALSE, 0, r->start.row);
        if (anchor->mode == GNM_SO_ANCHOR_TWO_CELLS) {
            pixels[2] = pixels[0] + colrow_distance (sheet, TRUE, r->start.col, r->end.col);
            pixels[3] = pixels[1] + colrow_distance (sheet, FALSE, r->start.row, r->end.row);
            pixels[0] += anchor->offset[0] * sheet_col_get_info (sheet, r->start.col)->size_pixels + .5;
            pixels[1] += anchor->offset[1] * sheet_row_get_info (sheet, r->start.row)->size_pixels + .5;
            pixels[2] += anchor->offset[2] * sheet_col_get_info (sheet, r->end.col)->size_pixels + .5;
            pixels[3] += anchor->offset[3] * sheet_row_get_info (sheet, r->end.row)->size_pixels + .5;
        } else {
            pixels[0] += anchor->offset[0] * sheet_col_get_info (sheet, r->start.col)->size_pixels + .5;
            pixels[1] += anchor->offset[1] * sheet_row_get_info (sheet, r->start.row)->size_pixels + .5;
            pixels[2] = pixels[0] + go_fake_floor (anchor->offset[2] * colrow_compute_pixel_scale (sheet, TRUE) + .5);
            pixels[3] = pixels[1] + go_fake_floor (anchor->offset[3] * colrow_compute_pixel_scale (sheet, TRUE) + .5);
        }
    } else {
        double h = colrow_compute_pixel_scale (sheet, TRUE);
        double v = colrow_compute_pixel_scale (sheet, FALSE);
        pixels[0] = go_fake_floor (anchor->offset[0] * h);
        pixels[1] = go_fake_floor (anchor->offset[1] * v);
        pixels[2] = go_fake_floor ((anchor->offset[0] + anchor->offset[2]) * h);
        pixels[3] = go_fake_floor ((anchor->offset[1] + anchor->offset[3]) * v);
    }

    direction = anchor->base.direction;
    if (direction == GOD_ANCHOR_DIR_UNKNOWN)
        direction = GOD_ANCHOR_DIR_DOWN_RIGHT;
    coords[0] = pixels[direction & GOD_ANCHOR_DIR_H_MASK ? 0 : 2];
    coords[1] = pixels[direction & GOD_ANCHOR_DIR_V_MASK ? 1 : 3];
    coords[2] = pixels[direction & GOD_ANCHOR_DIR_H_MASK ? 2 : 0];
    coords[3] = pixels[direction & GOD_ANCHOR_DIR_V_MASK ? 3 : 1];
}

void
gnm_cocoa_object_pixel_frame (Sheet const *sheet, SheetObject const *so, double *coords)
{
    object_pixel_frame (sheet, so, coords);
}

int
gnm_cocoa_colrow_at (Sheet const *sheet, gboolean is_cols, gint64 pos, gint64 *origin)
{
    return colrow_at (sheet, is_cols, pos, origin);
}

/* RGB and gray colors pass through untouched; anything else is matched to
 * sRGB.  (Matching an RGB color to another RGB space would shift its
 * components, which a caller passing a background color does not expect.) */
GdkRGBA
gnm_cocoa_rgba_from_cgcolor (CGColorRef color)
{
    GdkRGBA rgba = { 1, 1, 1, 1 };
    CGColorSpaceModel model = CGColorSpaceGetModel (CGColorGetColorSpace (color));
    const CGFloat *c = CGColorGetComponents (color);
    size_t n = CGColorGetNumberOfComponents (color);
    if (model == kCGColorSpaceModelRGB && n >= 3) {
        rgba = (GdkRGBA) { c[0], c[1], c[2], n > 3 ? c[3] : 1 };
    } else if (model == kCGColorSpaceModelMonochrome && n >= 1) {
        rgba = (GdkRGBA) { c[0], c[0], c[0], n > 1 ? c[1] : 1 };
    } else {
        CGColorSpaceRef srgb = CGColorSpaceCreateWithName (kCGColorSpaceSRGB);
        CGColorRef m = CGColorCreateCopyByMatchingToColorSpace (srgb, kCGRenderingIntentDefault, color, NULL);
        if (m && CGColorGetNumberOfComponents (m) == 4) {
            const CGFloat *mc = CGColorGetComponents (m);
            rgba = (GdkRGBA) { mc[0], mc[1], mc[2], mc[3] };
        }
        if (m)
            CGColorRelease (m);
        CGColorSpaceRelease (srgb);
    }
    return rgba;
}

/* A cairo context on top of a CGContext whose CTM already maps sheet pixels
 * to the destination with y downward (a flipped NSView or a flipped bitmap
 * context).  The surface size only bounds cairo's extents.
 *
 * The text matrix is not part of the graphics state, and cairo-quartz draws
 * glyphs with whatever it finds; AppKit's string drawing leaves a flipped,
 * translated one behind, which put every glyph off-screen when a header
 * view had drawn into the same context before the grid (whole-window
 * captures, 2026-10-11).  Reset it here; callers restore it. */
cairo_t *
gnm_cocoa_cairo_for_context (CGContextRef context, CGRect rect, cairo_surface_t **surface_out)
{
    unsigned w = (unsigned) MAX (ceil (CGRectGetMaxX (rect)), 1.0);
    unsigned h = (unsigned) MAX (ceil (CGRectGetMaxY (rect)), 1.0);
    CGContextSetTextMatrix (context, CGAffineTransformIdentity);
    cairo_surface_t *surface = cairo_quartz_surface_create_for_cg_context (context, w, h);
    cairo_t *cr = cairo_create (surface);
    cairo_rectangle (cr, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
    cairo_clip (cr);
    *surface_out = surface;
    return cr;
}

/* ------------------------------------------------------------------------ */

@implementation GnmSortKey

- (instancetype)initWithIndex:(NSInteger)index descending:(BOOL)descending caseSensitive:(BOOL)caseSensitive byValue:(BOOL)byValue
{
    if (!(self = [super init]))
        return nil;
    _index = index;
    _descending = descending;
    _caseSensitive = caseSensitive;
    _byValue = byValue;
    return self;
}

@end

/* ------------------------------------------------------------------------ */

@implementation GnmGoalSeekResult

- (instancetype)initWithFound:(BOOL)found solution:(double)solution current:(double)current target:(double)target
{
    if (!(self = [super init]))
        return nil;
    _found = found;
    _solution = solution;
    _currentValue = current;
    _targetValue = target;
    return self;
}

@end

@implementation GnmCellComment

- (instancetype)initWithComment:(GnmComment *)comment
{
    if (!(self = [super init]))
        return nil;
    GnmRange const *r = sheet_object_get_range (GNM_SO (comment));
    _column = r ? r->start.col : 0;
    _row = r ? r->start.row : 0;
    const char *author = cell_comment_author_get (comment);
    const char *text = cell_comment_text_get (comment);
    _author = author ? [NSString stringWithUTF8String:author] : @"";
    _text = text ? [NSString stringWithUTF8String:text] : @"";
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %ld,%ld %@: %@>", self.class, (long) _column, (long) _row, _author, _text];
}

@end

@implementation GnmSheet {
    Sheet *_sheet;
    SheetView *_sv;
    GnmCocoaSheetControl *_sc;
    NSMutableDictionary<NSValue *, GnmSheetObject *> *_objectWrappers;   /* keyed by engine pointer */
}

- (instancetype)initWithSheetView:(SheetView *)sheetView workbook:(GnmWorkbook *)workbook
{
    if (!(self = [super init]))
        return nil;
    _workbook = workbook;
    _sv = sheetView;
    _sheet = sv_sheet (sheetView);
    _sc = g_object_new (gnm_cocoa_sheet_control_get_type (), NULL);
    _sc->owner = (__bridge void *) self;
    _sc->base.wbc = workbook.control;
    /* The view owns the control's reference from here on (sheet-view.c
     * sv_real_dispose releases whatever is still attached). */
    gnm_sheet_view_attach_control (_sv, (SheetControl *) _sc);
    return self;
}

- (void)dealloc
{
    [self _detachFromEngine];
}

- (void)_detachFromEngine
{
    for (GnmSheetObject *wrapper in _objectWrappers.allValues)
        [wrapper _detachFromEngine];
    _objectWrappers = nil;
    if (_sc) {
        _sc->owner = NULL;
        if (_sv)
            gnm_sheet_view_detach_control (_sv, (SheetControl *) _sc);
        g_object_unref (_sc);
        _sc = NULL;
    }
    _sv = NULL;
}

- (void)_controlWasFinalized
{
    _sc = NULL;   /* the view released it before we detached */
}

- (Sheet *)engineSheet { return _sheet; }
- (SheetView *)sheetView { return _sv; }

#pragma mark - Facts

- (NSString *)name { return GnmString (_sheet->name_unquoted); }
- (NSInteger)index { return _sheet->index_in_wb; }
- (BOOL)isVisible { return sheet_is_visible (_sheet); }
- (BOOL)isRightToLeft { return _sheet->text_is_rtl; }
- (BOOL)isProtected { return _sheet->is_protected; }
- (BOOL)hidesGridLines { return _sheet->hide_grid; }
- (BOOL)hidesColumnHeader { return _sheet->hide_col_header; }
- (BOOL)hidesRowHeader { return _sheet->hide_row_header; }
- (BOOL)displaysFormulas { return _sheet->display_formulas; }
- (BOOL)hidesZeros { return _sheet->hide_zero; }
- (BOOL)usesR1C1 { return sheet_get_conventions (_sheet)->r1c1_addresses; }

- (BOOL)displayOption:(GnmSheetDisplayOption)option
{
    switch (option) {
    case GnmSheetDisplayOptionFormulas: return _sheet->display_formulas;
    case GnmSheetDisplayOptionHideZeros: return _sheet->hide_zero;
    case GnmSheetDisplayOptionHideGridLines: return _sheet->hide_grid;
    case GnmSheetDisplayOptionHideColumnHeader: return _sheet->hide_col_header;
    case GnmSheetDisplayOptionHideRowHeader: return _sheet->hide_row_header;
    case GnmSheetDisplayOptionR1C1: return sheet_get_conventions (_sheet)->r1c1_addresses;
    case GnmSheetDisplayOptionRightToLeft: return _sheet->text_is_rtl;
    case GnmSheetDisplayOptionOutlines: return _sheet->display_outlines;
    case GnmSheetDisplayOptionOutlineSymbolsBelow: return _sheet->outline_symbols_below;
    case GnmSheetDisplayOptionOutlineSymbolsRight: return _sheet->outline_symbols_right;
    }
    return NO;
}

- (BOOL)toggleDisplayOption:(GnmSheetDisplayOption)option error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    /* wbc-gtk-actions.c TOGGLE_HANDLER */
    const char *property, *desc;
    switch (option) {
    case GnmSheetDisplayOptionFormulas: property = "display-formulas"; desc = "Toggle displaying formul\303\246"; break;
    case GnmSheetDisplayOptionHideZeros: property = "display-zeros"; desc = "Toggle showing zeros"; break;
    case GnmSheetDisplayOptionHideGridLines: property = "display-grid"; desc = "Toggle showing gridlines"; break;
    case GnmSheetDisplayOptionHideColumnHeader: property = "display-column-header"; desc = "Toggle showing column headers"; break;
    case GnmSheetDisplayOptionHideRowHeader: property = "display-row-header"; desc = "Toggle showing row headers"; break;
    case GnmSheetDisplayOptionR1C1: property = "use-r1c1"; desc = "Toggle whether to show r1c1-style references"; break;
    case GnmSheetDisplayOptionRightToLeft: property = "text-is-rtl"; desc = "Toggle sheet text direction"; break;
    case GnmSheetDisplayOptionOutlines: property = "display-outlines"; desc = "Toggle showing outlines"; break;
    case GnmSheetDisplayOptionOutlineSymbolsBelow: property = "display-outlines-below"; desc = "Toggle where to show outlines vertically"; break;
    case GnmSheetDisplayOptionOutlineSymbolsRight: property = "display-outlines-right"; desc = "Toggle where to show outlines horizontally"; break;
    default: return NO;
    }
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_toggle_sheet_property (wbc, _sheet, property, desc);
    } description:@"Could not change the sheet's display." error:error];
}

- (double)zoomFactor { return _sheet->last_zoom_factor_used; }

- (void)setZoomFactor:(double)zoomFactor
{
    [self setZoomFactor:zoomFactor forAllSheets:NO error:NULL];
}

- (BOOL)setZoomFactor:(double)zoomFactor forAllSheets:(BOOL)all error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    /* dialog-zoom.c cb_zoom_ok_clicked; cmd_zoom takes the list */
    double factor = MIN (MAX (zoomFactor, 0.1), 5.0);
    GSList *sheets = NULL;
    if (all) {
        Workbook *wb = _sheet->workbook;
        for (int i = workbook_sheet_count (wb) - 1; i >= 0; i--)
            sheets = g_slist_prepend (sheets, workbook_sheet_by_index (wb, i));
    } else
        sheets = g_slist_append (NULL, _sheet);
    BOOL ok = [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_zoom (wbc, sheets, factor);
    } description:@"Could not change the zoom." error:error];
    sheet_update (_sheet);
    return ok;
}
- (NSInteger)columnCount { return gnm_sheet_get_max_cols (_sheet); }
- (NSInteger)rowCount { return gnm_sheet_get_max_rows (_sheet); }

static GnmCellRange
cell_range_from (GnmRange const *r)
{
    return GnmCellRangeMake (r->start.col, r->start.row, r->end.col, r->end.row);
}

- (GnmCellRange)usedRange
{
    GnmRange r = sheet_get_extent (_sheet, FALSE, TRUE);
    return cell_range_from (&r);
}

- (GnmCellCoordinate)scrollableExtent
{
    int col = MAX (_sheet->cols.max_used, _sheet->max_object_extent.col);
    int row = MAX (_sheet->rows.max_used, _sheet->max_object_extent.row);
    return GnmCellCoordinateMake (MAX (col, 0), MAX (row, 0));
}

- (GnmCellCoordinate)initialTopLeft
{
    if (_sv == NULL)
        return GnmCellCoordinateMake (0, 0);
    return GnmCellCoordinateMake (_sv->initial_top_left.col, _sv->initial_top_left.row);
}

- (void)setInitialTopLeft:(GnmCellCoordinate)cell
{
    if (_sv == NULL || _sheet == NULL)
        return;
    int col = (int) cell.column, row = (int) cell.row;
    /* the engine's own checks, which it answers with a critical warning */
    if (col < 0 || col >= gnm_sheet_get_max_cols (_sheet) || row < 0 || row >= gnm_sheet_get_max_rows (_sheet))
        return;
    if (gnm_sheet_view_is_frozen (_sv) && (_sv->unfrozen_top_left.col > col || _sv->unfrozen_top_left.row > row))
        return;
    if (_sv->initial_top_left.col == col && _sv->initial_top_left.row == row)
        return;
    gnm_sheet_view_set_initial_top_left (_sv, col, row);
}

#pragma mark - Geometry

- (CGFloat)widthOfColumn:(NSInteger)column
{
    ColRowInfo const *ci = sheet_col_get_info (_sheet, (int) column);
    return ci->visible ? ci->size_pixels : 0;
}

- (CGFloat)heightOfRow:(NSInteger)row
{
    ColRowInfo const *ri = sheet_row_get_info (_sheet, (int) row);
    return ri->visible ? ri->size_pixels : 0;
}

- (BOOL)isColumnVisible:(NSInteger)column { return sheet_col_get_info (_sheet, (int) column)->visible; }
- (BOOL)isRowVisible:(NSInteger)row { return sheet_row_get_info (_sheet, (int) row)->visible; }

- (CGFloat)leftEdgeOfColumn:(NSInteger)column
{
    return colrow_distance (_sheet, TRUE, 0, (int) MIN (column, gnm_sheet_get_max_cols (_sheet)));
}

- (CGFloat)topEdgeOfRow:(NSInteger)row
{
    return colrow_distance (_sheet, FALSE, 0, (int) MIN (row, gnm_sheet_get_max_rows (_sheet)));
}

- (NSInteger)columnAtX:(CGFloat)x
{
    int col = colrow_at (_sheet, TRUE, (gint64) floor (x), NULL);
    while (col < gnm_sheet_get_last_col (_sheet) && !sheet_col_get_info (_sheet, col)->visible)
        col++;
    return col;
}

- (NSInteger)rowAtY:(CGFloat)y
{
    int row = colrow_at (_sheet, FALSE, (gint64) floor (y), NULL);
    while (row < gnm_sheet_get_last_row (_sheet) && !sheet_row_get_info (_sheet, row)->visible)
        row++;
    return row;
}

- (CGRect)frameOfCellAtColumn:(NSInteger)column row:(NSInteger)row
{
    return CGRectMake ([self leftEdgeOfColumn:column], [self topEdgeOfRow:row],
                       [self widthOfColumn:column], [self heightOfRow:row]);
}

- (NSString *)nameOfColumn:(NSInteger)column
{
    /* item-bar.c: numbers under R1C1 */
    if (sheet_get_conventions (_sheet)->r1c1_addresses)
        return [NSString stringWithFormat:@"%ld", (long) column + 1];
    return GnmString (col_name ((int) column));
}
- (NSString *)nameOfRow:(NSInteger)row { return GnmString (row_name ((int) row)); }

#pragma mark - Cells

- (BOOL)isCellEmptyAtColumn:(NSInteger)column row:(NSInteger)row
{
    return gnm_cell_is_empty (sheet_cell_get (_sheet, (int) column, (int) row));
}

- (BOOL)cellHasFormulaAtColumn:(NSInteger)column row:(NSInteger)row
{
    GnmCell *cell = sheet_cell_get (_sheet, (int) column, (int) row);
    return cell != NULL && gnm_cell_has_expr (cell);
}

- (NSString *)displayTextOfCellAtColumn:(NSInteger)column row:(NSInteger)row
{
    GnmCell *cell = sheet_cell_get (_sheet, (int) column, (int) row);
    if (cell == NULL || gnm_cell_is_empty (cell))
        return nil;
    char *text = gnm_cell_get_rendered_text (cell);
    NSString *s = GnmString (text);
    g_free (text);
    return s;
}

- (NSString *)enteredTextOfCellAtColumn:(NSInteger)column row:(NSInteger)row
{
    GnmCell *cell = sheet_cell_get (_sheet, (int) column, (int) row);
    if (cell == NULL || gnm_cell_is_empty (cell))
        return nil;
    char *text = gnm_cell_get_entered_text (cell);
    NSString *s = GnmString (text);
    g_free (text);
    return s;
}

#pragma mark - Editing

- (NSString *)editingTextOfCellAtColumn:(NSInteger)column row:(NSInteger)row
{
    GnmCell *cell = sheet_cell_get (_sheet, (int) column, (int) row);
    if (cell == NULL || gnm_cell_is_empty (cell))
        return nil;
    gboolean quoted = FALSE;
    int cursor = 0;
    char *text = gnm_cell_get_text_for_editing (cell, &quoted, &cursor);
    NSString *s = GnmString (text);
    g_free (text);
    return s;
}

/* The engine's own "is there anything to do" test (commands.c
 * cmd_set_text_full and cmd_set_text_full_check_text), for a command
 * that returns TRUE, as a failure would, when the text is unchanged. */
static gboolean
cell_already_has_text (Sheet *sheet, GnmCellPos pos, char const *new_text, gboolean autocorrect)
{
    GnmCell *cell = sheet_cell_get (sheet, pos.col, pos.row);
    char *corrected = autocorrect ? autocorrect_tool (new_text) : g_strdup (new_text);
    if (corrected && corrected[0] == '\'' && corrected[1] == '\0') {
        g_free (corrected);
        corrected = g_strdup ("");
    }
    gboolean same;
    if (cell == NULL || gnm_cell_is_blank (cell))
        same = corrected == NULL || corrected[0] == '\0';
    else if (corrected == NULL || corrected[0] == '\0')
        same = FALSE;
    else {
        gboolean quoted = FALSE;
        char *old_text = gnm_cell_get_text_for_editing (cell, &quoted, NULL);
        same = g_strcmp0 (old_text, corrected) == 0;
        if (!same && !quoted && cell->value && VALUE_IS_STRING (cell->value) && corrected[0] == '\'')
            same = g_strcmp0 (old_text, corrected + 1) == 0;
        g_free (old_text);
    }
    g_free (corrected);
    return same;
}

- (BOOL)setText:(NSString *)text atColumn:(NSInteger)column row:(NSInteger)row
    autocorrect:(BOOL)autocorrect error:(NSError **)error
{
    GnmCellPos pos = { (int) column, (int) row };
    const char *utf8 = text.UTF8String;
    BOOL reported = NO;
    NSError *commandError = nil;
    BOOL ok = [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_set_text (wbc, _sheet, &pos, utf8, NULL, autocorrect);
    } description:[NSString stringWithFormat:@"Could not set the text of %@.",
                   GnmString (cell_coord_name ((int) column, (int) row))] reported:&reported error:&commandError];
    if (!ok && !reported && cell_already_has_text (_sheet, pos, utf8, autocorrect))
        return YES;   /* the engine's "nothing to do", not a failure */
    if (!ok && error)
        *error = commandError;
    return ok;
}

- (BOOL)fillSelectionWithText:(NSString *)text error:(NSError **)error
{
    if (_sv == NULL)
        return NO;
    const char *utf8 = text.UTF8String;
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_area_set_text (wbc, _sv, utf8, NULL);
    } description:@"Could not fill the selection." error:error];
}

- (BOOL)clearSelection:(GnmClearOptions)options error:(NSError **)error
{
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_selection_clear (wbc, (int) options);
    } description:@"Could not clear the selection." error:error];
}

- (BOOL)insertCellsInRange:(GnmCellRange)range shiftingDown:(BOOL)down error:(NSError **)error
{
    int cols = (int) (range.end.column - range.start.column + 1);
    int rows = (int) (range.end.row - range.start.row + 1);
    /* dialog-insert-cells.c cb_insert_cell_ok_clicked */
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        if (down)
            cmd_shift_cols (wbc, _sheet, (int) range.start.column, (int) range.end.column, (int) range.start.row, rows);
        else
            cmd_shift_rows (wbc, _sheet, (int) range.start.column, (int) range.start.row, (int) range.end.row, cols);
        return FALSE;   /* the shift commands report through the context and return nothing */
    } description:@"Could not insert cells." error:error];
}

- (BOOL)deleteCellsInRange:(GnmCellRange)range shiftingUp:(BOOL)up error:(NSError **)error
{
    int cols = (int) (range.end.column - range.start.column + 1);
    int rows = (int) (range.end.row - range.start.row + 1);
    /* dialog-delete-cells.c cb_delete_cell_ok_clicked */
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        if (up)
            cmd_shift_cols (wbc, _sheet, (int) range.start.column, (int) range.end.column, (int) range.end.row + 1, -rows);
        else
            cmd_shift_rows (wbc, _sheet, (int) range.end.column + 1, (int) range.start.row, (int) range.end.row, -cols);
        return FALSE;
    } description:@"Could not delete cells." error:error];
}

- (NSString *)currentDateTimeTextWithDate:(BOOL)date time:(BOOL)wantsTime
{
    /* wbc-gtk-actions.c insert_date_time_common */
    if (_sv == NULL || (!date && !wantsTime))
        return @"";
    GnmCell const *cell = sheet_cell_fetch (_sheet, _sv->edit_pos.col, _sv->edit_pos.row);
    GODateConventions const *date_conv = sheet_date_conv (_sheet);
    GnmValue *v = value_new_float (go_date_timet_to_serial_raw (time (NULL), date_conv));
    char *dtxt = NULL, *ttxt = NULL;
    if (date) {
        GOFormat *fmt = gnm_format_for_date_editing (cell);
        dtxt = format_value (fmt, v, -1, date_conv);
        go_format_unref (fmt);
    }
    if (wantsTime)
        ttxt = format_value (go_format_default_time (), v, -1, date_conv);
    value_release (v);
    NSString *result;
    if (date && wantsTime)
        result = [NSString stringWithFormat:@"%@ %@", GnmString (dtxt), GnmString (ttxt)];
    else
        result = GnmString (date ? dtxt : ttxt);
    g_free (dtxt);
    g_free (ttxt);
    return result;
}

- (BOOL)insertColumns:(NSInteger)count atColumn:(NSInteger)column error:(NSError **)error
{
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_insert_cols (wbc, _sheet, (int) column, (int) count);
    } description:@"Could not insert columns." error:error];
}

- (BOOL)insertRows:(NSInteger)count atRow:(NSInteger)row error:(NSError **)error
{
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_insert_rows (wbc, _sheet, (int) row, (int) count);
    } description:@"Could not insert rows." error:error];
}

- (BOOL)deleteColumns:(NSRange)columns error:(NSError **)error
{
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_delete_cols (wbc, _sheet, (int) columns.location, (int) columns.length);
    } description:@"Could not delete columns." error:error];
}

- (BOOL)deleteRows:(NSRange)rows error:(NSError **)error
{
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_delete_rows (wbc, _sheet, (int) rows.location, (int) rows.length);
    } description:@"Could not delete rows." error:error];
}

- (void)copySelection
{
    GnmRange const *r = _sv ? selection_first_range (_sv, NULL, NULL) : NULL;
    if (r)
        gnm_app_clipboard_cut_copy (self.workbook.control, FALSE, _sv, r, TRUE);
}

- (void)cutSelection
{
    GnmRange const *r = _sv ? selection_first_range (_sv, NULL, NULL) : NULL;
    if (r)
        gnm_app_clipboard_cut_copy (self.workbook.control, TRUE, _sv, r, TRUE);
}

- (void)paste
{
    [self pasteWithOptions:GnmPasteDefault];
}

- (void)pasteWithOptions:(GnmPasteOptions)options
{
    if (_sv == NULL)
        return;
    [self.workbook _dropStaleEngineClipboard];
    /* void: problems are reported through the command context */
    [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        cmd_paste_to_selection (wbc, _sv, (int) options);
        return FALSE;
    } description:@"Could not paste." error:NULL];
}

- (BOOL)sortSelectionDescending:(BOOL)descending error:(NSError **)error
{
    if (_sv == NULL || _sv->selections == NULL || _sv->selections->next != NULL) {
        if (error)
            *error = [self.workbook.engine _errorWithCode:GnmErrorCommandFailed
                                             description:@"Sort does not support multiple ranges." collected:@[]];
        return NO;
    }
    /* wbc-gtk-actions.c, sort_by_rows: one range sorts its rows by every
     * column left to right; one cell sorts the sheet below by that column. */
    GnmRange const *r = _sv->selections->data;
    GnmRange sel;
    int numclause;
    GnmSortClause *clause;
    if (range_is_singleton (r)) {
        range_init_full_sheet (&sel, _sheet);
        sel.start.row = r->start.row;
        range_clip_to_finite (&sel, _sheet);
        numclause = 1;
        clause = g_new0 (GnmSortClause, 1);
        clause[0].offset = r->start.col - sel.start.col;
    } else {
        sel = *r;
        range_clip_to_finite (&sel, _sheet);
        numclause = range_width (&sel);
        clause = g_new0 (GnmSortClause, numclause);
        for (int i = 0; i < numclause; i++)
            clause[i].offset = i;
    }
    for (int i = 0; i < numclause; i++) {
        clause[i].asc = descending;   /* sic: the engine's flag reads this way (GTK does the same) */
        clause[i].cs = gnm_conf_get_core_sort_default_by_case ();
        clause[i].val = TRUE;
    }
    GnmSortData *data = gnm_sort_data_new ();
    data->sheet = _sheet;
    data->range = sel;
    data->num_clause = numclause;
    data->clauses = clause;
    data->locale = NULL;
    data->retain_formats = gnm_conf_get_core_sort_default_retain_formats ();
    data->top = TRUE;
    if (sheet_range_has_heading (data->sheet, &data->range, data->top, FALSE))
        data->range.start.row += 1;
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_sort (wbc, data);   /* takes ownership of data */
    } description:@"Could not sort." error:error];
}

#pragma mark - Sort dialog

- (GnmCellRange)sortableRange
{
    GnmRange const *r = _sv ? selection_first_range (_sv, NULL, NULL) : NULL;
    GnmRange region;
    if (r == NULL) {
        GnmCellCoordinate p = self.editPosition;
        range_init (&region, (int) p.column, (int) p.row, (int) p.column, (int) p.row);
    } else {
        region = *r;
    }
    if (range_is_singleton (&region))
        gnm_sheet_guess_data_range (_sheet, &region);   /* the block around the cell, in every direction */
    range_clip_to_finite (&region, _sheet);
    return cell_range_from (&region);
}

static GnmRange
range_from (GnmCellRange r)
{
    GnmRange out;
    range_init (&out, (int) r.start.column, (int) r.start.row, (int) r.end.column, (int) r.end.row);
    return out;
}

- (BOOL)range:(GnmCellRange)range hasHeadingByRows:(BOOL)byRows
{
    GnmRange r = range_from (range);
    return sheet_range_has_heading (_sheet, &r, byRows, FALSE);
}

- (NSString *)sortKeyNameForIndex:(NSInteger)index inRange:(GnmCellRange)range byRows:(BOOL)byRows hasHeader:(BOOL)hasHeader
{
    /* dialog-cell-sort.c col_row_name */
    NSString *generic = byRows ? [NSString stringWithFormat:@"Column %@", GnmString (col_name ((int) index))]
                               : [NSString stringWithFormat:@"Row %@", GnmString (row_name ((int) index))];
    if (!hasHeader)
        return generic;
    GnmCell *cell = byRows ? sheet_cell_get (_sheet, (int) index, (int) range.start.row)
                           : sheet_cell_get (_sheet, (int) range.start.column, (int) index);
    if (cell == NULL || gnm_cell_is_blank (cell))
        return generic;
    char *text = value_get_as_string (cell->value);
    NSString *name = [NSString stringWithFormat:@"%@ (%@)", GnmString (text), generic];
    g_free (text);
    return name;
}

- (BOOL)sortRange:(GnmCellRange)range byRows:(BOOL)byRows hasHeader:(BOOL)hasHeader keys:(NSArray<GnmSortKey *> *)keys
    retainFormats:(BOOL)retainFormats error:(NSError **)error
{
    return [self sortRange:range byRows:byRows hasHeader:hasHeader keys:keys retainFormats:retainFormats locale:nil error:error];
}

- (BOOL)sortRange:(GnmCellRange)range byRows:(BOOL)byRows hasHeader:(BOOL)hasHeader keys:(NSArray<GnmSortKey *> *)keys
    retainFormats:(BOOL)retainFormats locale:(NSString *)locale error:(NSError **)error
{
    if (keys.count == 0) {
        if (error)
            *error = [self.workbook.engine _errorWithCode:GnmErrorCommandFailed
                                             description:@"Sort needs at least one key." collected:@[]];
        return NO;
    }
    /* dialog-cell-sort.c cb_dialog_ok_clicked */
    GnmSortClause *clauses = g_new0 (GnmSortClause, keys.count);
    NSInteger base = byRows ? range.start.column : range.start.row;
    NSUInteger i = 0;
    for (GnmSortKey *key in keys) {
        clauses[i].offset = (int) (key.index - base);
        clauses[i].asc = key.isDescending;   /* sic, as the quick sort */
        clauses[i].cs = key.isCaseSensitive;
        clauses[i].val = key.byValue;
        i++;
    }
    GnmSortData *data = gnm_sort_data_new ();
    data->sheet = _sheet;
    range_init (&data->range,
                (int) range.start.column + ((hasHeader && !byRows) ? 1 : 0),
                (int) range.start.row + ((hasHeader && byRows) ? 1 : 0),
                (int) range.end.column, (int) range.end.row);
    range_clip_to_finite (&data->range, _sheet);
    data->num_clause = (int) keys.count;
    data->clauses = clauses;
    data->top = byRows;
    data->retain_formats = retainFormats;
    data->locale = locale.length ? g_strdup (locale.UTF8String) : NULL;
    /* the dialog remembers the setup under the range's name before it
     * sorts (cb_dialog_ok_clicked); the sheet owns key and copy */
    GnmRange full;
    range_init (&full, (int) range.start.column, (int) range.start.row, (int) range.end.column, (int) range.end.row);
    gnm_sheet_add_sort_setup (_sheet, g_strdup (range_as_string (&full)), gnm_sort_data_copy (data));
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_sort (wbc, data);   /* takes ownership of data */
    } description:@"Could not sort." error:error];
}

- (GnmSortSetup *)sortSetupForRange:(GnmCellRange)range
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    if (!_sheet)
        return nil;
    GnmRange full;
    range_init (&full, (int) range.start.column, (int) range.start.row, (int) range.end.column, (int) range.end.row);
    GnmSortData const *data = gnm_sheet_find_sort_setup (_sheet, range_as_string (&full));
    if (!data)
        return nil;
    /* dialog_cell_sort_load_sort_setup: the clauses' offsets are from
     * the sorted range's first column (row) */
    NSMutableArray<GnmSortKey *> *keys = [NSMutableArray array];
    int base = data->top ? data->range.start.col : data->range.start.row;
    for (int i = 0; i < data->num_clause; i++) {
        GnmSortClause const *clause = &data->clauses[i];
        [keys addObject:[[GnmSortKey alloc] initWithIndex:base + clause->offset descending:clause->asc
                                            caseSensitive:clause->cs byValue:clause->val]];
    }
    return [[GnmSortSetup alloc] initPrivateWithByRows:data->top keys:keys retainsFormats:data->retain_formats
                                                locale:data->locale ? [NSString stringWithUTF8String:data->locale] : nil];
}

+ (BOOL)sortDefaultsToCaseSensitive { return gnm_conf_get_core_sort_default_by_case (); }
+ (BOOL)sortDefaultsToRetainingFormats { return gnm_conf_get_core_sort_default_retain_formats (); }
+ (BOOL)sortDefaultsToAscending { return gnm_conf_get_core_sort_default_ascending (); }

#pragma mark - Autofilter

- (BOOL)editPositionIsInFilter
{
    return _sv != NULL && gnm_sheet_view_editpos_in_filter (_sv) != NULL;
}

- (BOOL)hasFilteredRows
{
    /* The engine's flag is only kept by the advanced filter (tools/filter.c);
     * for autofilters, look at the rows of the active ones. */
    if (_sheet->has_filtered_rows)
        return YES;
    for (GSList *l = _sheet->filters; l; l = l->next) {
        GnmFilter const *filter = l->data;
        if (!filter->is_active)
            continue;
        for (int row = filter->r.start.row + 1; row <= filter->r.end.row; row++) {
            ColRowInfo const *ri = sheet_row_get (_sheet, row);
            if (ri != NULL && !ri->visible)
                return YES;
        }
    }
    return NO;
}

- (BOOL)toggleAutofilter:(NSError **)error
{
    if (_sv == NULL)
        return NO;
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_autofilter_add_remove (wbc);
    } description:@"Could not add or remove the autofilter." error:error];
}

- (void)showAllFilteredRows
{
    if (wb_view_cur_sheet (self.workbook.workbookView) != _sheet)
        wb_view_sheet_focus (self.workbook.workbookView, _sheet);
    /* The GTK item only serves the advanced filter (tools/filter.c
     * cb_show_all looks at in_advanced_filter); here every autofilter
     * condition goes too, each one an undoable command. */
    for (GSList *l = _sheet->filters; l; l = l->next) {
        GnmFilter *filter = l->data;
        for (unsigned i = 0; i < filter->fields->len; i++) {
            GnmFilterCombo *fcombo = g_ptr_array_index (filter->fields, i);
            if (fcombo->cond == NULL)
                continue;
            [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
                return cmd_autofilter_set_condition (wbc, filter, i, NULL);
            } description:@"Could not show the filtered rows." error:NULL];
        }
    }
    [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        filter_show_all (wbc);
        return FALSE;
    } description:@"Could not show the filtered rows." error:NULL];
    sheet_update (_sheet);
}

- (NSArray<GnmFilterButton *> *)filterButtons
{
    NSMutableArray *buttons = [NSMutableArray array];
    for (GSList *l = _sheet->filters; l; l = l->next) {
        GnmFilter *filter = l->data;
        for (unsigned i = 0; i < filter->fields->len; i++)
            [buttons addObject:[[GnmFilterButton alloc] initWithFilter:filter field:i sheet:_sheet]];
    }
    return buttons;
}

/* Port of fcombo_create_list (widgets/gnm-filter-combo-view.c): the
 * column's distinct values, leaving out rows the other fields hide. */
typedef struct {
    gboolean has_blank;
    GHashTable *hash;
    GODateConventions const *date_conv;
    Sheet *src_sheet;
} UniqueCollection;

static GnmValue *
cb_collect_content (GnmCellIter const *iter, UniqueCollection *uc)
{
    GnmCell const *cell = (iter->pp.sheet == uc->src_sheet) ? iter->cell
        : sheet_cell_get (uc->src_sheet, iter->pp.eval.col, iter->pp.eval.row);
    if (gnm_cell_is_blank (cell))
        uc->has_blank = TRUE;
    else {
        GOFormat const *fmt = gnm_cell_get_format (cell);
        GnmValue const *v = cell->value;
        g_hash_table_replace (uc->hash, value_dup (v), format_value (fmt, v, -1, uc->date_conv));
    }
    return NULL;
}

static void
cb_hash_domain (GnmValue *key, G_GNUC_UNUSED gpointer value, gpointer accum)
{
    g_ptr_array_add (accum, key);
}

static gboolean
formatted_value_equal (GnmValue const *a, GnmValue const *b)
{
    return value_equal (a, b) && (VALUE_FMT (a) == VALUE_FMT (b));
}

- (GnmFilterChoices *)choicesForFilterButton:(GnmFilterButton *)button
{
    if (!button.isAttached)
        return [[GnmFilterChoices alloc] initWithValues:g_ptr_array_new () labels:@[] hasBlanks:NO
                                                current:[GnmFilterCriterion showAll]];
    GnmFilter const *filter = button.filter;
    unsigned field_num = button.field;
    GnmFilterCombo *fcombo = g_ptr_array_index (filter->fields, field_num);
    GnmRange r = filter->r;
    UniqueCollection uc;

    r.start.row++;
    r.end.col = r.start.col += field_num;
    uc.has_blank = FALSE;
    uc.hash = g_hash_table_new_full ((GHashFunc) value_hash, (GEqualFunc) formatted_value_equal,
                                     (GDestroyNotify) value_release, (GDestroyNotify) g_free);
    uc.src_sheet = filter->sheet;
    uc.date_conv = sheet_date_conv (uc.src_sheet);

    if (filter->fields->len > 1) {
        /* A temporary sheet carries the other fields' visibility. */
        Workbook *wb = uc.src_sheet->workbook;
        char *name = workbook_sheet_get_free_name (wb, "DummyFilterPopulate", FALSE, FALSE);
        Sheet *filtered_sheet = sheet_new (wb, name, gnm_sheet_get_max_cols (uc.src_sheet),
                                           gnm_sheet_get_max_rows (uc.src_sheet));
        g_free (name);
        for (unsigned i = 0; i < filter->fields->len; i++)
            if (i != field_num)
                gnm_filter_combo_apply (g_ptr_array_index (filter->fields, i), filtered_sheet);
        sheet_foreach_cell_in_range (filtered_sheet, CELL_ITER_IGNORE_HIDDEN, &r,
                                     (CellIterFunc) cb_collect_content, &uc);
        g_object_unref (filtered_sheet);
    } else {
        sheet_foreach_cell_in_range (filter->sheet, CELL_ITER_ALL, &r,
                                     (CellIterFunc) cb_collect_content, &uc);
    }

    GPtrArray *sorted = g_ptr_array_new ();
    g_hash_table_foreach (uc.hash, (GHFunc) cb_hash_domain, sorted);
    g_ptr_array_sort (sorted, value_cmp);

    GPtrArray *values = g_ptr_array_new ();
    NSMutableArray<NSString *> *labels = [NSMutableArray arrayWithCapacity:sorted->len];
    for (unsigned i = 0; i < sorted->len; i++) {
        GnmValue const *v = g_ptr_array_index (sorted, i);
        char const *str = g_hash_table_lookup (uc.hash, v);
        unsigned const max = 50;
        NSString *label = GnmString (str);
        if (g_utf8_strlen (str, -1) > max + 3) {
            char *cut = g_strdup (str);
            strcpy (g_utf8_offset_to_pointer (cut, max), "...");
            label = GnmString (cut);
            g_free (cut);
        }
        [labels addObject:label];
        g_ptr_array_add (values, value_dup (v));
    }
    g_hash_table_destroy (uc.hash);
    g_ptr_array_free (sorted, TRUE);

    GnmFilterCriterion *current = [GnmFilterCriterion conditionFromEngine:fcombo->cond values:values labels:labels];
    return [[GnmFilterChoices alloc] initWithValues:values labels:labels hasBlanks:uc.has_blank current:current];
}

- (BOOL)setFilterCondition:(GnmFilterCriterion *)condition forButton:(GnmFilterButton *)button error:(NSError **)error
{
    if (!button.isAttached) {
        if (error)
            *error = [self.workbook.engine _errorWithCode:GnmErrorCommandFailed
                                             description:@"The filter is gone." collected:@[]];
        return NO;
    }
    GnmFilter *filter = button.filter;
    unsigned field = button.field;
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        GnmFilterCondition *cond = [condition newEngineConditionWithWorkbook:_sheet->workbook];
        return cmd_autofilter_set_condition (wbc, filter, field, cond);   /* takes cond */
    } description:@"Could not change the filter condition." error:error];
}

#pragma mark - Tab colors

- (CGColorRef)copyTabColor
{
    return _sheet->tab_color ? gnm_cocoa_cgcolor_from_go (_sheet->tab_color->go_color) : NULL;
}

- (CGColorRef)copyTabTextColor
{
    return _sheet->tab_text_color ? gnm_cocoa_cgcolor_from_go (_sheet->tab_text_color->go_color) : NULL;
}

- (NSArray<NSValue *> *)marchingAntsFrames
{
    NSMutableArray *frames = [NSMutableArray array];
    if (_sv == NULL)
        return frames;
    for (GList *l = _sv->ants; l; l = l->next) {
        GnmRange const *r = l->data;
        CGFloat x = colrow_distance (_sheet, TRUE, 0, r->start.col);
        CGFloat y = colrow_distance (_sheet, FALSE, 0, r->start.row);
        CGFloat w = colrow_distance (_sheet, TRUE, r->start.col, r->end.col + 1);
        CGFloat h = colrow_distance (_sheet, FALSE, r->start.row, r->end.row + 1);
        [frames addObject:[NSValue valueWithRect:NSMakeRect (x, y, w, h)]];
    }
    return frames;
}

- (GnmCellFormat *)formatOfSelection
{
    GnmRange const *r = _sv ? selection_first_range (_sv, NULL, NULL) : NULL;
    GnmRange single;
    if (r == NULL) {
        GnmCellCoordinate p = self.editPosition;
        range_init (&single, (int) p.column, (int) p.row, (int) p.column, (int) p.row);
        r = &single;
    }
    return gnm_cocoa_format_from_selection (_sheet, r);
}

- (GnmCellFormat *)formatOfCellAtColumn:(NSInteger)column row:(NSInteger)row
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    return gnm_cocoa_format_from_style (sheet_style_get (_sheet, (int) column, (int) row));
}

- (BOOL)applyFormat:(GnmCellFormat *)format error:(NSError **)error
{
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        GnmStyle *style;
        GnmBorder *borders[GNM_STYLE_BORDER_EDGE_MAX];
        gnm_cocoa_format_to_engine (format, &style, borders);
        return cmd_selection_format (wbc, style, borders, NULL);   /* takes both */
    } description:@"Could not format the selection." error:error];
}

- (BOOL)setSelectedColumns:(BOOL)columns hidden:(BOOL)hidden error:(NSError **)error
{
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_selection_colrow_hide (wbc, columns, !hidden);
    } description:hidden ? @"Could not hide." : @"Could not unhide." error:error];
}

#pragma mark - Column widths and row heights

/* Points to pixels at the sheet's own scale (zoom times its pixels per
 * point), through the engine's conversion so the two agree exactly. */
static int
pixels_from_points (Sheet const *sheet, gboolean horizontal, double points)
{
    ColRowInfo info = { 0 };
    info.size_pts = points;
    colrow_compute_pixels_from_pts (&info, sheet, horizontal, -1);
    return info.size_pixels;
}

- (CGFloat)widthInPointsOfColumn:(NSInteger)column
{
    ColRowInfo const *info = sheet_col_get_info (_sheet, (int) column);
    return info ? info->size_pts : 0;
}

- (CGFloat)heightInPointsOfRow:(NSInteger)row
{
    ColRowInfo const *info = sheet_row_get_info (_sheet, (int) row);
    return info ? info->size_pts : 0;
}

- (CGFloat)defaultColumnWidthInPoints { return sheet_col_get_default_size_pts (_sheet); }
- (CGFloat)defaultRowHeightInPoints { return sheet_row_get_default_size_pts (_sheet); }

- (BOOL)setSelectedColumns:(BOOL)columns sizeInPoints:(CGFloat)points error:(NSError **)error
{
    int pixels = points > 0 ? MAX (pixels_from_points (_sheet, columns, points), 1) : 0;
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        /* The GTK Column Width dialog: the engine collects the selection's
         * columns and runs cmd_resize_colrow (returns TRUE on failure
         * through cmd_generic_with_size). */
        workbook_cmd_resize_selected_colrow (wbc, _sheet, columns, pixels);
        return FALSE;
    } description:columns ? @"Could not set the column width." : @"Could not set the row height." error:error];
}

- (BOOL)setColumns:(BOOL)columns inRange:(NSRange)range sizeInPixels:(NSInteger)pixels error:(NSError **)error
{
    if (range.length == 0)
        return YES;
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        /* The command's undo object takes the list (cmd_resize_colrow). */
        ColRowIndexList *list = colrow_get_index_list ((int) range.location,
                                                       (int) (range.location + range.length - 1), NULL);
        return cmd_resize_colrow (wbc, _sheet, columns, list, (int) pixels);
    } description:columns ? @"Could not set the column width." : @"Could not set the row height." error:error];
}

- (BOOL)autofitSelectedColumns:(BOOL)columns error:(NSError **)error
{
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        workbook_cmd_resize_selected_colrow (wbc, _sheet, columns, -1);
        return FALSE;
    } description:@"Could not fit the size to the content." error:error];
}

- (BOOL)autofitSelectedCellsWidth:(BOOL)width error:(NSError **)error
{
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        workbook_cmd_autofit_selection (wbc, _sheet, width);
        return FALSE;
    } description:@"Could not fit the size to the content." error:error];
}

- (BOOL)setDefaultSizeInPoints:(CGFloat)points forColumns:(BOOL)columns error:(NSError **)error
{
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_colrow_std_size (wbc, _sheet, columns, points);
    } description:columns ? @"Could not set the default column width." : @"Could not set the default row height." error:error];
}

#pragma mark - Fill

- (BOOL)fillDown:(NSError **)error
{
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_copyrel (wbc, 0, -1, "Copy down");
    } description:@"Could not fill down." error:error];
}

- (BOOL)fillRight:(NSError **)error
{
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_copyrel (wbc, -1, 0, "Copy right");
    } description:@"Could not fill right." error:error];
}

- (BOOL)autofillFromRange:(GnmCellRange)source toRange:(GnmCellRange)target defaultIncrement:(BOOL)defaultIncrement error:(NSError **)error
{
    /* As the GTK fill handle calls it (item-cursor.c): the base is the
     * target's top-left, the size is the source's, the end is the target's
     * bottom-right, and the fill runs backwards when the target starts
     * before the source. */
    BOOL inverse = target.start.column < source.start.column || target.start.row < source.start.row;
    int w = (int) (source.end.column - source.start.column + 1);
    int h = (int) (source.end.row - source.start.row + 1);
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_autofill (wbc, _sheet, defaultIncrement,
                             (int) target.start.column, (int) target.start.row, w, h,
                             (int) target.end.column, (int) target.end.row, inverse);
    } description:@"Could not autofill." error:error];
}

#pragma mark - Frozen panes

- (BOOL)isFrozen
{
    return _sv != NULL && gnm_sheet_view_is_frozen (_sv);
}

- (GnmCellCoordinate)frozenTopLeft
{
    if (!self.isFrozen)
        return GnmCellCoordinateMake (-1, -1);
    return GnmCellCoordinateMake (_sv->frozen_top_left.col, _sv->frozen_top_left.row);
}

- (GnmCellCoordinate)unfrozenTopLeft
{
    if (!self.isFrozen)
        return GnmCellCoordinateMake (-1, -1);
    return GnmCellCoordinateMake (_sv->unfrozen_top_left.col, _sv->unfrozen_top_left.row);
}

- (void)freezePanesWithUnfrozenTopLeft:(GnmCellCoordinate)unfrozen frozenTopLeft:(GnmCellCoordinate)frozen
{
    if (_sv == NULL)
        return;
    GnmCellPos f = { (int) frozen.column, (int) frozen.row };
    GnmCellPos u = { (int) unfrozen.column, (int) unfrozen.row };
    if (u.col < f.col || u.row < f.row)
        return;   /* the engine would only complain */
    gnm_sheet_view_freeze_panes (_sv, &f, &u);
}

- (void)unfreezePanes
{
    if (_sv != NULL)
        gnm_sheet_view_freeze_panes (_sv, NULL, NULL);
}

#pragma mark - Merged cells

- (BOOL)selectionHasMergedCells
{
    if (_sv == NULL)
        return NO;
    GSList *ranges = selection_get_ranges (_sv, FALSE);
    BOOL found = NO;
    for (GSList *l = ranges; l != NULL && !found; l = l->next) {
        GSList *overlap = gnm_sheet_merge_get_overlap (_sheet, l->data);
        found = overlap != NULL;
        g_slist_free (overlap);
    }
    range_fragment_free (ranges);
    return found;
}

- (BOOL)mergeSelectionCentered:(BOOL)center error:(NSError **)error
{
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        GSList *ranges = selection_get_ranges (_sv, FALSE);
        gboolean failed = cmd_merge_cells (wbc, _sheet, ranges, center);
        range_fragment_free (ranges);
        return failed;
    } description:@"Could not merge the cells." error:error];
}

- (BOOL)unmergeSelection:(NSError **)error
{
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        GSList *ranges = selection_get_ranges (_sv, FALSE);
        gboolean failed = cmd_unmerge_cells (wbc, _sheet, ranges);
        range_fragment_free (ranges);
        return failed;
    } description:@"Could not unmerge the cells." error:error];
}

#pragma mark - Selection

- (GnmCellCoordinate)editPosition
{
    if (_sv == NULL)
        return GnmCellCoordinateMake (0, 0);
    return GnmCellCoordinateMake (_sv->edit_pos.col, _sv->edit_pos.row);
}

- (GnmCellRange)selectedRange
{
    GnmRange const *r = _sv ? selection_first_range (_sv, NULL, NULL) : NULL;
    if (r == NULL) {
        GnmCellCoordinate p = self.editPosition;
        return GnmCellRangeMake (p.column, p.row, p.column, p.row);
    }
    return cell_range_from (r);
}

- (void)selectCellAtColumn:(NSInteger)column row:(NSInteger)row
{
    [self selectRange:GnmCellRangeMake (column, row, column, row)
         editPosition:GnmCellCoordinateMake (column, row)];
}

- (void)selectRange:(GnmCellRange)range editPosition:(GnmCellCoordinate)editPosition
{
    if (_sv == NULL)
        return;
    GnmCellPos pos = { (int) editPosition.column, (int) editPosition.row };
    sv_selection_set (_sv, &pos, (int) range.start.column, (int) range.start.row,
                      (int) range.end.column, (int) range.end.row);
    sheet_update (_sheet);   /* flush the status and redraw requests */
}

- (NSString *)selectionText
{
    if (_sv == NULL)
        return @"";
    char *text = selection_to_string (_sv, TRUE);
    NSString *result = text ? [NSString stringWithUTF8String:text] : @"";
    g_free (text);
    return result;
}

- (void)navigateTo:(GnmNavigationTarget)target
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    Sheet *sheet = self.engineSheet;
    WorkbookControl *wbc = self.workbook.control;
    if (!sheet || !wbc)
        return;
    wb_control_sheet_focus (wbc, sheet);
    wb_control_navigate_to_cell (wbc, (wb_control_navigator_t) target);
}

- (void)revealCellAtColumn:(NSInteger)column row:(NSInteger)row
{
    if (_sv == NULL || _sheet == NULL)
        return;
    /* dialog-search.c cursor_change */
    WorkbookView *wbv = sv_wbv (_sv);
    if (wbv && wb_view_cur_sheet (wbv) != _sheet)
        wb_view_sheet_focus (wbv, _sheet);
    GnmCellPos pos = { (int) column, (int) row };
    gnm_sheet_view_set_edit_pos (_sv, &pos);
    sv_selection_set (_sv, &pos, (int) column, (int) row, (int) column, (int) row);
    gnm_sheet_view_make_cell_visible (_sv, (int) column, (int) row, FALSE);
    gnm_sheet_view_update (_sv);
}

#pragma mark - Fill Series

- (NSNumber *)numberFromText:(NSString *)text
{
    if (_sheet == NULL || text.length == 0)
        return nil;
    GnmValue *v = format_match_number (text.UTF8String, NULL, sheet_date_conv (_sheet));
    if (!v)
        return nil;
    NSNumber *result = VALUE_IS_NUMBER (v) ? @(value_get_as_float (v)) : nil;
    value_release (v);
    return result;
}

- (BOOL)fillSeriesInRange:(GnmCellRange)range byRows:(BOOL)byRows kind:(GnmFillSeriesKind)kind dateUnit:(GnmFillSeriesDateUnit)unit
                    start:(double)start step:(NSNumber *)step stop:(NSNumber *)stop error:(NSError **)error
{
    if (_sheet == NULL || _workbook == nil)
        return NO;
    if (step == nil && stop == nil) {
        if (error)
            *error = [_workbook.engine _errorWithCode:GnmErrorCommandFailed
                                          description:@"A step or a stop value is needed for a series." collected:@[]];
        return NO;
    }
    /* dialog-fill-series.c cb_fill_series_ok_clicked */
    GnmAnalysisTool *tool = gnm_fill_series_tool_new ();
    GnmFillSeriesTool *ftool = GNM_FILL_SERIES_TOOL (tool);
    ftool->series_in_rows = byRows;
    ftool->type = (gnm_fill_series_type_t) kind;
    ftool->date_unit = (gnm_fill_series_date_unit_t) unit;
    ftool->start_value = start;
    ftool->is_step_set = step != nil;
    ftool->step_value = step.doubleValue;
    ftool->is_stop_set = stop != nil;
    ftool->stop_value = stop.doubleValue;
    data_analysis_output_t *dao = dao_init (GNM_DAO_OUTPUT_RANGE);
    dao->start_col = (int) range.start.column;
    dao->start_row = (int) range.start.row;
    dao->cols = (int) (range.end.column - range.start.column + 1);
    dao->rows = (int) (range.end.row - range.start.row + 1);
    dao->dst_sheet = _sheet;
    Sheet *sheet = _sheet;
    /* The command owns the output description and keeps the tool. */
    BOOL ok = [_workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_analysis_tool (wbc, sheet, dao, tool);
    } description:@"Could not fill the series." error:error];
    g_object_unref (tool);
    return ok;
}

#pragma mark - Goal Seek

- (BOOL)parseCellReference:(NSString *)text column:(NSInteger *)column row:(NSInteger *)row
{
    if (_sheet == NULL || text.length == 0)
        return NO;
    GnmCellPos pos;
    const char *end = cellpos_parse (text.UTF8String, gnm_sheet_get_size (_sheet), &pos, TRUE);
    if (!end)
        return NO;
    if (column)
        *column = pos.col;
    if (row)
        *row = pos.row;
    return YES;
}

- (GnmGoalSeekResult *)goalSeekCellAtColumn:(NSInteger)column row:(NSInteger)row toValue:(double)target
                     byChangingCellAtColumn:(NSInteger)changeColumn row:(NSInteger)changeRow
                                    minimum:(NSNumber *)minimum maximum:(NSNumber *)maximum error:(NSError **)error
{
    if (_sheet == NULL || _workbook == nil)
        return nil;
    GnmEngine *engine = _workbook.engine;
    /* dialog-goal-seek.c cb_dialog_apply_clicked */
    GnmCell *setCell = sheet_cell_get (_sheet, (int) column, (int) row);
    if (setCell == NULL || !gnm_cell_has_expr (setCell)) {
        if (error)
            *error = [engine _errorWithCode:GnmErrorCommandFailed
                                description:@"The cell named in 'Set Cell:' must contain a formula!" collected:@[]];
        return nil;
    }
    GnmCell *changeCell = sheet_cell_fetch (_sheet, (int) changeColumn, (int) changeRow);
    if (gnm_cell_has_expr (changeCell)) {
        if (error)
            *error = [engine _errorWithCode:GnmErrorCommandFailed
                                description:@"The cell named in 'By changing cell' must not contain a formula." collected:@[]];
        return nil;
    }
    static const double max_range_val = 1e24;
    GnmGoalSeekData seekdata;
    GnmGoalSeekCellData celldata;
    goal_seek_initialize (&seekdata);
    seekdata.xmin = minimum ? minimum.doubleValue : -max_range_val;
    seekdata.xmax = maximum ? maximum.doubleValue : +max_range_val;
    celldata.xcell = changeCell;
    celldata.ycell = setCell;
    celldata.ytarget = target;

    GnmValue *oldValue = value_dup (changeCell->value);
    GnmGoalSeekStatus status = gnm_goal_seek_cell (&seekdata, &celldata);
    gnm_app_recalc ();
    if (status != GOAL_SEEK_OK) {
        /* back as it was */
        sheet_cell_set_value (changeCell, oldValue);   /* absorbs the value */
        gnm_app_recalc ();
        sheet_update (_sheet);
        return [[GnmGoalSeekResult alloc] initWithFound:NO solution:0 current:0 target:target];
    }
    double solution = changeCell->value ? value_get_as_float (changeCell->value) : 0;
    double current = setCell->value ? value_get_as_float (setCell->value) : 0;
    /* The command takes the old value and copies the cell's new one. */
    GnmValue *handed = oldValue;
    BOOL ok = [_workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_goal_seek (wbc, changeCell, handed, NULL);
    } description:@"Could not record the goal seek." error:error];
    if (!ok)
        return nil;
    return [[GnmGoalSeekResult alloc] initWithFound:YES solution:solution current:current target:target];
}

#pragma mark - Comments

- (GnmCellComment *)commentAtColumn:(NSInteger)column row:(NSInteger)row
{
    if (_sheet == NULL)
        return nil;
    GnmCellPos pos = { (int) column, (int) row };
    GnmComment *comment = sheet_get_comment (_sheet, &pos);
    return comment ? [[GnmCellComment alloc] initWithComment:comment] : nil;
}

- (NSArray<GnmCellComment *> *)commentsInRange:(GnmCellRange)range
{
    NSMutableArray *comments = [NSMutableArray array];
    if (_sheet == NULL)
        return comments;
    GnmRange r;
    range_init (&r, (int) range.start.column, (int) range.start.row, (int) range.end.column, (int) range.end.row);
    GSList *objects = sheet_objects_get (_sheet, &r, GNM_CELL_COMMENT_TYPE);
    for (GSList *l = objects; l; l = l->next)
        [comments addObject:[[GnmCellComment alloc] initWithComment:GNM_CELL_COMMENT (l->data)]];
    g_slist_free (objects);
    return comments;
}

- (BOOL)setCommentText:(NSString *)text author:(NSString *)author atColumn:(NSInteger)column row:(NSInteger)row error:(NSError **)error
{
    if (_sheet == NULL || _workbook == nil)
        return NO;
    GnmCellPos pos = { (int) column, (int) row };
    /* The command wants both strings; an empty text clears the comment. */
    const char *newText = text.UTF8String ?: "";
    const char *newAuthor = author.UTF8String ?: "";
    Sheet *sheet = _sheet;
    BOOL ok = [_workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_set_comment (wbc, sheet, &pos, newText, NULL, newAuthor);
    } description:[NSString stringWithFormat:@"Could not set the comment of %s.", cellpos_as_string (&pos)] error:error];
    if (ok)
        [self _objectsDidChange];
    return ok;
}

#pragma mark - Drawing

- (void)drawCellsInRect:(CGRect)rect context:(CGContextRef)context backgroundColor:(CGColorRef)backgroundColor
{
    [self drawCellsInRect:rect context:context backgroundColor:backgroundColor rightToLeftWidth:0];
}

- (void)drawCellsInRect:(CGRect)rect context:(CGContextRef)context backgroundColor:(CGColorRef)backgroundColor rightToLeftWidth:(CGFloat)width
{
    if (_sv == NULL || CGRectIsEmpty (rect))
        return;
    double mirror = 0;
    gint64 x0 = (gint64) floor (CGRectGetMinX (rect)), x1 = (gint64) ceil (CGRectGetMaxX (rect));
    if (_sheet->text_is_rtl) {
        mirror = width > 0 ? width : CGRectGetMaxX (rect);
        gint64 m = (gint64) llround (mirror);
        x0 = m - (gint64) ceil (CGRectGetMaxX (rect));
        x1 = m - (gint64) floor (CGRectGetMinX (rect));
    }
    GdkRGBA bg = { 1, 1, 1, 1 };
    if (backgroundColor)
        bg = gnm_cocoa_rgba_from_cgcolor (backgroundColor);
    GnmRange bound;
    range_init_full_sheet (&bound, _sheet);

    DrawContext dc;
    draw_context_init (&dc, _sheet, sv_wbv (_sv));

    CGAffineTransform text_matrix = CGContextGetTextMatrix (context);
    CGContextSaveGState (context);
    CGContextClipToRect (context, rect);
    cairo_surface_t *surface;
    cairo_t *cr = gnm_cocoa_cairo_for_context (context, rect, &surface);
    draw_region (&dc, cr,
                 x0, (gint64) floor (CGRectGetMinY (rect)),
                 x1, (gint64) ceil (CGRectGetMaxY (rect)),
                 &bound, &bg, mirror);
    cairo_destroy (cr);
    cairo_surface_flush (surface);
    cairo_surface_destroy (surface);
    CGContextRestoreGState (context);
    CGContextSetTextMatrix (context, text_matrix);
}

- (void)drawSheetObjectsInRect:(CGRect)rect context:(CGContextRef)context
{
    [self drawSheetObjectsInRect:rect context:context rightToLeftWidth:0];
}

- (void)drawSheetObjectsInRect:(CGRect)rect context:(CGContextRef)context rightToLeftWidth:(CGFloat)width
{
    if (_sheet->sheet_objects == NULL || CGRectIsEmpty (rect))
        return;
    double mirror = _sheet->text_is_rtl ? (width > 0 ? width : CGRectGetMaxX (rect)) : 0;
    CGAffineTransform text_matrix = CGContextGetTextMatrix (context);
    CGContextSaveGState (context);
    CGContextClipToRect (context, rect);
    cairo_surface_t *surface;
    cairo_t *cr = gnm_cocoa_cairo_for_context (context, rect, &surface);
    /* The list is front to back; draw back to front (print.c does the same). */
    GSList *back_to_front = g_slist_reverse (g_slist_copy (_sheet->sheet_objects));
    for (GSList *l = back_to_front; l; l = l->next) {
        SheetObject *so = l->data;
        double c[4];
        /* Autofilter combos and other widget-like objects have no cairo
         * renderer (sheet_object_draw_cairo_sized would call NULL); the
         * app draws the filter buttons itself. */
        if (GNM_SO_CLASS (G_OBJECT_GET_CLASS (so))->draw_cairo == NULL || !(so->flags & SHEET_OBJECT_IS_VISIBLE))
            continue;
        object_pixel_frame (_sheet, so, c);
        CGRect frame = CGRectMake (c[0], c[1], c[2] - c[0], c[3] - c[1]);
        if (mirror > 0)
            frame.origin.x = mirror - c[2];
        if (!CGRectIntersectsRect (frame, rect) || frame.size.width <= 0 || frame.size.height <= 0)
            continue;
        cairo_save (cr);
        cairo_translate (cr, frame.origin.x, frame.origin.y);
        sheet_object_draw_cairo_sized (so, cr, frame.size.width, frame.size.height);
        cairo_restore (cr);
    }
    g_slist_free (back_to_front);
    cairo_destroy (cr);
    cairo_surface_flush (surface);
    cairo_surface_destroy (surface);
    CGContextRestoreGState (context);
    CGContextSetTextMatrix (context, text_matrix);
}

- (NSArray<NSValue *> *)sheetObjectFrames
{
    NSMutableArray *frames = [NSMutableArray array];
    for (GSList *l = _sheet->sheet_objects; l; l = l->next) {
        double c[4];
        object_pixel_frame (_sheet, l->data, c);
        [frames addObject:[NSValue valueWithRect:NSMakeRect (c[0], c[1], c[2] - c[0], c[3] - c[1])]];
    }
    return frames;
}

#pragma mark - Sheet objects

- (GnmSheetObject *)_wrapperForObject:(SheetObject *)object
{
    if (_objectWrappers == nil)
        _objectWrappers = [NSMutableDictionary dictionary];
    NSValue *key = [NSValue valueWithPointer:object];
    GnmSheetObject *wrapper = _objectWrappers[key];
    if (wrapper == nil) {
        wrapper = [[GnmSheetObject alloc] initWithObject:object sheet:self];
        _objectWrappers[key] = wrapper;
    }
    return wrapper;
}

- (void)_objectsDidChange
{
    if ([self.delegate respondsToSelector:@selector(sheetObjectsDidChange:)])
        [self.delegate sheetObjectsDidChange:self];
}

- (NSArray<GnmSheetObject *> *)sheetObjects
{
    NSMutableArray *objects = [NSMutableArray array];
    for (GSList *l = _sheet->sheet_objects; l; l = l->next)
        [objects addObject:[self _wrapperForObject:l->data]];
    return objects;
}

- (GnmSheetObject *)sheetObjectAtPoint:(CGPoint)point
{
    for (GSList *l = _sheet->sheet_objects; l; l = l->next) {
        GnmSheetObject *wrapper = [self _wrapperForObject:l->data];
        if (!wrapper.isSelectable || !wrapper.isVisible)
            continue;
        CGRect frame = wrapper.frame;
        if (frame.size.width < 6 || frame.size.height < 6)
            frame = CGRectInset (frame, -3, -3);   /* thin lines */
        if (CGRectContainsPoint (frame, point))
            return wrapper;
    }
    return nil;
}

/* calc_obj_place (sheet-control-gui.c): the column or row under a sheet
 * pixel and the fraction of it before the pixel. */
static int
obj_place (Sheet const *sheet, gboolean is_col, double pos, double *offset)
{
    int i = colrow_at (sheet, is_col, (gint64) floor (pos), NULL);
    int last = is_col ? gnm_sheet_get_last_col (sheet) : gnm_sheet_get_last_row (sheet);
    ColRowInfo const *cri = sheet_colrow_get_info (sheet, i, is_col);
    while (i < last && !cri->visible)
        cri = sheet_colrow_get_info (sheet, ++i, is_col);
    gint64 origin = colrow_distance (sheet, is_col, 0, i);
    *offset = cri->visible && cri->size_pixels > 0 ? (pos - origin) / (double) cri->size_pixels : 0;
    if (*offset < 0)
        *offset = 0;
    return i;
}

/* scg_object_coords_to_anchor for a normalized frame: the anchor keeps
 * its mode and gets the cells and offsets under the frame. */
static void
anchor_from_frame (Sheet const *sheet, CGRect frame, SheetObjectAnchor *in_out)
{
    double tmp[4] = { CGRectGetMinX (frame), CGRectGetMinY (frame), CGRectGetMaxX (frame), CGRectGetMaxY (frame) };
    in_out->base.direction = GOD_ANCHOR_DIR_DOWN_RIGHT;
    switch (in_out->mode) {
    case GNM_SO_ANCHOR_TWO_CELLS:
        in_out->cell_bound.start.col = obj_place (sheet, TRUE, tmp[0], in_out->offset + 0);
        in_out->cell_bound.start.row = obj_place (sheet, FALSE, tmp[1], in_out->offset + 1);
        in_out->cell_bound.end.col = obj_place (sheet, TRUE, tmp[2], in_out->offset + 2);
        in_out->cell_bound.end.row = obj_place (sheet, FALSE, tmp[3], in_out->offset + 3);
        break;
    case GNM_SO_ANCHOR_ONE_CELL:
        in_out->cell_bound.start.col = obj_place (sheet, TRUE, tmp[0], in_out->offset + 0);
        in_out->cell_bound.start.row = obj_place (sheet, FALSE, tmp[1], in_out->offset + 1);
        in_out->cell_bound.end = in_out->cell_bound.start;
        in_out->offset[2] = (tmp[2] - tmp[0]) / colrow_compute_pixel_scale (sheet, TRUE);
        in_out->offset[3] = (tmp[3] - tmp[1]) / colrow_compute_pixel_scale (sheet, FALSE);
        break;
    case GNM_SO_ANCHOR_ABSOLUTE: {
        double h = colrow_compute_pixel_scale (sheet, TRUE);
        double v = colrow_compute_pixel_scale (sheet, FALSE);
        range_init (&in_out->cell_bound, 0, 0, 0, 0);
        in_out->offset[0] = tmp[0] / h;
        in_out->offset[1] = tmp[1] / v;
        in_out->offset[2] = (tmp[2] - tmp[0]) / h;
        in_out->offset[3] = (tmp[3] - tmp[1]) / v;
        break;
    }
    }
}

- (BOOL)setFrames:(NSArray<NSValue *> *)frames ofSheetObjects:(NSArray<GnmSheetObject *> *)objects resizing:(BOOL)resizing error:(NSError **)error
{
    if (frames.count != objects.count) {
        if (error)
            *error = [self.workbook.engine _errorWithCode:GnmErrorCommandFailed
                                             description:@"One frame per object is needed." collected:@[]];
        return NO;
    }
    GSList *list = NULL, *anchors = NULL;
    for (NSUInteger i = objects.count; i-- > 0;) {
        GnmSheetObject *wrapper = objects[i];
        if (!wrapper.isAttached)
            continue;
        SheetObjectAnchor *anchor = sheet_object_anchor_dup (sheet_object_get_anchor (wrapper.engineObject));
        anchor_from_frame (_sheet, frames[i].rectValue, anchor);
        list = g_slist_prepend (list, wrapper.engineObject);
        anchors = g_slist_prepend (anchors, anchor);
    }
    if (list == NULL)
        return YES;
    unsigned n = g_slist_length (list);
    NSString *label = [NSString stringWithFormat:resizing ? (n == 1 ? @"Resize %u Object" : @"Resize %u Objects")
                                                          : (n == 1 ? @"Move %u Object" : @"Move %u Objects"), n];
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_objects_move (wbc, list, anchors, FALSE, label.UTF8String);   /* takes both lists */
    } description:resizing ? @"Could not resize the objects." : @"Could not move the objects." error:error];
}

- (BOOL)deleteSheetObjects:(NSArray<GnmSheetObject *> *)objects error:(NSError **)error
{
    GSList *list = NULL;
    for (GnmSheetObject *wrapper in objects.reverseObjectEnumerator)
        if (wrapper.isAttached)
            list = g_slist_prepend (list, wrapper.engineObject);
    if (list == NULL)
        return YES;
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_objects_delete (wbc, list, NULL);   /* takes the list */
    } description:@"Could not delete the objects." error:error];
}

- (BOOL)restackSheetObject:(GnmSheetObject *)object direction:(GnmSheetObjectStacking)direction error:(NSError **)error
{
    if (!object.isAttached)
        return NO;
    SheetObject *so = object.engineObject;
    return [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_object_raise (wbc, so, (CmdObjectRaiseSelector) direction);
    } description:@"Could not restack the object." error:error];
}

#pragma mark - Object clipboard and images

- (void)copySheetObjects:(NSArray<GnmSheetObject *> *)objects cut:(BOOL)cut
{
    if (_sv == NULL)
        return;
    GSList *list = NULL;
    for (GnmSheetObject *wrapper in objects.reverseObjectEnumerator)
        if (wrapper.isAttached)
            list = g_slist_prepend (list, wrapper.engineObject);
    if (list == NULL)
        return;
    [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        gnm_app_clipboard_cut_copy_obj (wbc, cut, _sv, list);   /* takes the list */
        return FALSE;
    } description:@"Could not copy the objects." error:NULL];
}

/* goffice guesses an image's type through the shared MIME database, which
 * Homebrew does not install; sniff the common formats here instead. */
static char const *
image_type_for_data (NSData *data)
{
    unsigned char const *b = data.bytes;
    NSUInteger n = data.length;
    if (n >= 8 && memcmp (b, "\x89PNG\r\n\x1a\n", 8) == 0)
        return "png";
    if (n >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF)
        return "jpeg";
    if (n >= 6 && memcmp (b, "GIF8", 4) == 0)
        return "gif";
    if (n >= 2 && b[0] == 'B' && b[1] == 'M')
        return "bmp";
    if (n >= 5 && (memcmp (b, "<?xml", 5) == 0 || memcmp (b, "<svg", 4) == 0)) {
        NSString *head = [[NSString alloc] initWithBytes:b length:MIN (n, 512) encoding:NSUTF8StringEncoding];
        if ([head containsString:@"<svg"])
            return "svg";
    }
    return NULL;
}

- (CGSize)naturalSizeOfImageData:(NSData *)data
{
    char const *type = image_type_for_data (data);
    if (type == NULL)
        return CGSizeZero;
    GOImage *image = go_image_new_from_data (type, data.bytes, data.length, NULL, NULL);
    if (image == NULL)
        return CGSizeZero;
    /* gnm_soi_default_size: the pixel size as points */
    CGSize size = CGSizeMake (go_image_get_width (image) * colrow_compute_pixel_scale (_sheet, TRUE),
                              go_image_get_height (image) * colrow_compute_pixel_scale (_sheet, FALSE));
    g_object_unref (image);
    return size;
}

/* Attach a new object at `frame` and commit it as a created object, as
 * scg_objects_drag_commit does after a creation drag ("Insert 1 Object"). */
- (GnmSheetObject *)_insertCreatedObject:(SheetObject *)so frame:(CGRect)frame anchorMode:(GnmSOAnchorMode)mode
                             description:(NSString *)description error:(NSError **)error
{
    SheetObjectAnchor anchor;
    sheet_object_anchor_init (&anchor, NULL, NULL, GOD_ANCHOR_DIR_DOWN_RIGHT, mode);
    anchor_from_frame (_sheet, frame, &anchor);
    sheet_object_set_anchor (so, &anchor);
    sheet_object_set_sheet (so, _sheet);
    GSList *objects = g_slist_prepend (NULL, so);
    GSList *anchors = g_slist_prepend (NULL, sheet_object_anchor_dup (&anchor));
    BOOL ok = [self.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_objects_move (wbc, objects, anchors, TRUE, "Insert 1 Object");   /* takes both lists */
    } description:description error:error];
    return ok ? [self _wrapperForObject:so] : nil;
}

- (GnmSheetObject *)insertImageData:(NSData *)data frame:(CGRect)frame error:(NSError **)error
{
    if (CGSizeEqualToSize ([self naturalSizeOfImageData:data], CGSizeZero)) {
        if (error)
            *error = [self.workbook.engine _errorWithCode:GnmErrorCommandFailed
                                             description:@"The data is not an image the engine can read." collected:@[]];
        return nil;
    }
    /* scg_image_create */
    SheetObjectImage *soi = g_object_new (GNM_SO_IMAGE_TYPE, NULL);
    sheet_object_image_set_image (soi, image_type_for_data (data), data.bytes, (unsigned) data.length);
    SheetObject *so = GNM_SO (soi);
    GnmSheetObject *wrapper = [self _insertCreatedObject:so frame:frame anchorMode:GNM_SO_ANCHOR_TWO_CELLS
                                             description:@"Could not insert the image." error:error];
    g_object_unref (so);
    return wrapper;
}

#pragma mark - Charts

- (CGSize)defaultChartSize
{
    /* gnm_sog_default_size: 12 by 8 cm in points, at the sheet's scale */
    return CGSizeMake (GO_CM_TO_PT (12.0) * colrow_compute_pixel_scale (_sheet, TRUE),
                       GO_CM_TO_PT (8.0) * colrow_compute_pixel_scale (_sheet, FALSE));
}

#pragma mark - Objects as images

- (NSArray<GnmImageFormat *> *)imageFormatsForSheetObject:(GnmSheetObject *)object
{
    NSMutableArray *result = [NSMutableArray array];
    SheetObject *so = object.engineObject;
    if (so == NULL)
        return result;
    GSList *formats = NULL;
    if (GNM_IS_SO_GRAPH (so)) {
        formats = gog_graph_get_supported_image_formats ();
    } else if (GNM_IS_SO_IMAGE (so)) {
        /* sheet-object-image.c soi_cb_save_as: the raster formats with a
         * saver, the image's own format first */
        formats = go_image_get_formats_with_pixbuf_saver ();
        char *type = NULL;
        g_object_get (so, "image-type", &type, NULL);
        GOImageFormat own = type ? go_image_get_format_from_name (type) : GO_IMAGE_FORMAT_UNKNOWN;
        g_free (type);
        if (own != GO_IMAGE_FORMAT_UNKNOWN) {
            formats = g_slist_remove (formats, GUINT_TO_POINTER (own));
            formats = g_slist_prepend (formats, GUINT_TO_POINTER (own));
        }
    }
    for (GSList *l = formats; l; l = l->next) {
        GnmImageFormat *format = [[GnmImageFormat alloc] initWithFormat:(GOImageFormat) GPOINTER_TO_UINT (l->data)];
        if (format)
            [result addObject:format];
    }
    g_slist_free (formats);
    return result;
}

- (BOOL)writeImageOfSheetObject:(GnmSheetObject *)object format:(GnmImageFormat *)format resolution:(double)resolution
                          toURL:(NSURL *)url error:(NSError **)error
{
    SheetObject *so = object.engineObject;
    NSString *failure = [NSString stringWithFormat:@"Could not write “%@”.", url.lastPathComponent];
    if (so == NULL || !GNM_IS_SO_IMAGEABLE (so)) {
        if (error)
            *error = [self.workbook.engine _errorWithCode:GnmErrorSaveFailed description:failure
                                              collected:@[[NSError errorWithDomain:GnmErrorDomain code:GnmErrorSaveFailed userInfo:@{
                                                  NSLocalizedDescriptionKey: @"This object cannot be written as an image." }]]];
        return NO;
    }
    GError *gerr = NULL;
    GsfOutput *output = gsf_output_stdio_new (url.path.fileSystemRepresentation, &gerr);
    if (output == NULL) {
        if (error)
            *error = [self.workbook.engine _errorWithCode:GnmErrorSaveFailed description:failure
                                              collected:@[[NSError errorWithDomain:GnmErrorDomain code:GnmErrorSaveFailed userInfo:@{
                                                  NSLocalizedDescriptionKey: GnmString (gerr ? gerr->message : "") }]]];
        g_clear_error (&gerr);
        return NO;
    }
    sheet_object_write_image (so, format.name.UTF8String, resolution, output, &gerr);
    if (!gsf_output_is_closed (output))
        gsf_output_close (output);
    g_object_unref (output);
    if (gerr) {
        if (error)
            *error = [self.workbook.engine _errorWithCode:GnmErrorSaveFailed description:failure
                                              collected:@[[NSError errorWithDomain:GnmErrorDomain code:GnmErrorSaveFailed userInfo:@{
                                                  NSLocalizedDescriptionKey: GnmString (gerr->message) }]]];
        g_error_free (gerr);
        return NO;
    }
    return YES;
}

- (GnmSheetObject *)insertChartOfType:(GnmPlotType *)type seriesLayout:(GnmChartSeriesLayout)layout
                       sharedAbscissa:(BOOL)shared frame:(CGRect)frame error:(NSError **)error
{
    if (_sv == NULL || type.engineType == NULL)
        return nil;
    GogPlot *plot = gog_plot_new_by_type (type.engineType);
    if (plot == NULL) {
        if (error)
            *error = [self.workbook.engine _errorWithCode:GnmErrorCommandFailed
                                             description:[NSString stringWithFormat:@"The plot type %@ is not available.", type.engine]
                                               collected:@[]];
        return nil;
    }
    /* The guru's new graph: a chart holding the plot, the series read from
     * the selection through the data closure sv_selection_to_plot expects. */
    GogGraph *graph = g_object_new (GOG_TYPE_GRAPH, NULL);
    GogObject *chart = gog_object_add_by_name (GOG_OBJECT (graph), "Chart", NULL);
    gog_object_add_by_name (chart, "Plot", GOG_OBJECT (plot));
    GnmGraphDataClosure closure = { 0 };
    closure.colrowmode = (int) layout;
    closure.share_x = shared;
    closure.anchor_mode = GNM_SO_ANCHOR_ONE_CELL;   /* graphs do not resize with cells */
    g_object_set_data (G_OBJECT (graph), "data-closure", &closure);
    sv_selection_to_plot (_sv, plot);
    g_object_set_data (G_OBJECT (graph), "data-closure", NULL);
    NSString *hints = [type propertyNamed:@"guru-hints"];
    if ([hints containsString:@"backplane"])
        gog_object_add_by_name (chart, "Backplane", NULL);
    if ([hints containsString:@"major-grid"]) {
        GSList *axes = gog_chart_get_axes (GOG_CHART (chart), GOG_AXIS_Y);
        if (axes)
            gog_object_add_by_name (GOG_OBJECT (axes->data), "MajorGrid", NULL);
        g_slist_free (axes);
    }
    if (g_slist_length ((GSList *) gog_plot_get_series (plot)) > 1)
        gog_object_add_by_name (chart, "Legend", NULL);

    SheetObject *so = sheet_object_graph_new (graph);   /* takes its own reference */
    g_object_unref (graph);
    /* Graphs do not resize with cells (the GTK closure's anchor mode). */
    GnmSheetObject *wrapper = [self _insertCreatedObject:so frame:frame anchorMode:GNM_SO_ANCHOR_ONE_CELL
                                             description:@"Could not insert the chart." error:error];
    g_object_unref (so);   /* the sheet and the command hold theirs */
    return wrapper;
}

#pragma mark - Control callbacks

- (void)_controlNeedsDisplayIncludingHeaders:(BOOL)headers
{
    if ([self.delegate respondsToSelector:@selector(sheetNeedsDisplay:includingHeaders:)])
        [self.delegate sheetNeedsDisplay:self includingHeaders:headers];
}

- (void)_controlNeedsDisplayInRange:(GnmRange const *)range
{
    if ([self.delegate respondsToSelector:@selector(sheet:needsDisplayInRange:)])
        [self.delegate sheet:self needsDisplayInRange:cell_range_from (range)];
}

- (void)_controlNeedsHeaderDisplayForColumns:(BOOL)columns rows:(BOOL)rows
{
    if ([self.delegate respondsToSelector:@selector(sheet:needsHeaderDisplayForColumns:rows:)])
        [self.delegate sheet:self needsHeaderDisplayForColumns:columns rows:rows];
}

- (void)_controlGeometryDidChange
{
    if ([self.delegate respondsToSelector:@selector(sheetGeometryDidChange:)])
        [self.delegate sheetGeometryDidChange:self];
}

- (void)_controlCursorDidMoveToRange:(GnmRange const *)range
{
    if (range && [self.delegate respondsToSelector:@selector(sheet:cursorDidMoveToRange:)])
        [self.delegate sheet:self cursorDidMoveToRange:cell_range_from (range)];
}

- (void)_controlScrollToColumn:(int)column row:(int)row
{
    if ([self.delegate respondsToSelector:@selector(sheet:scrollToColumn:row:)])
        [self.delegate sheet:self scrollToColumn:column row:row];
}

- (void)_controlMakeVisibleColumn:(int)column row:(int)row
{
    if ([self.delegate respondsToSelector:@selector(sheet:makeVisibleColumn:row:)])
        [self.delegate sheet:self makeVisibleColumn:column row:row];
}

- (void)_controlMarchingAntsDidChange
{
    if ([self.delegate respondsToSelector:@selector(sheetMarchingAntsDidChange:)])
        [self.delegate sheetMarchingAntsDidChange:self];
}

- (void)_controlFrozenPanesDidChange
{
    if ([self.delegate respondsToSelector:@selector(sheetFrozenPanesDidChange:)])
        [self.delegate sheetFrozenPanesDidChange:self];
}

@end

@implementation GnmSortSetup

- (instancetype)initPrivateWithByRows:(BOOL)byRows keys:(NSArray<GnmSortKey *> *)keys retainsFormats:(BOOL)retainsFormats
                               locale:(NSString *)locale
{
    if (!(self = [super init]))
        return nil;
    _byRows = byRows;
    _keys = [keys copy];
    _retainsFormats = retainsFormats;
    _locale = [locale copy];
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@ %lu keys formats=%d locale=%@>", self.class, _byRows ? @"rows" : @"columns",
            (unsigned long) _keys.count, _retainsFormats, _locale ?: @"(current)"];
}

@end
