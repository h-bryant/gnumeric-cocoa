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
static void csc_object_create_view (G_GNUC_UNUSED SheetControl *sc, G_GNUC_UNUSED SheetObject *so)
{
    /* Objects are drawn directly from the model (drawSheetObjectsInRect:). */
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
static void
draw_region (DrawContext const *dc, cairo_t *cr,
             gint64 x0, gint64 y0, gint64 x1, gint64 y1,
             GnmRange const *bound, GdkRGBA const *background)
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

    /* Fill entire region with the background (even past the far edge) */
    cairo_save (cr);
    gdk_cairo_set_source_rgba (cr, background);
    cairo_rectangle (cr, x0, y0, x1 - x0, y1 - y0);
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

/* RGB and gray colors pass through untouched; anything else is matched to
 * sRGB.  (Matching an RGB color to another RGB space would shift its
 * components, which a caller passing a background color does not expect.) */
static GdkRGBA
rgba_from_cgcolor (CGColorRef color)
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
 * context).  The surface size only bounds cairo's extents. */
static cairo_t *
cairo_for_context (CGContextRef context, CGRect rect, cairo_surface_t **surface_out)
{
    unsigned w = (unsigned) MAX (ceil (CGRectGetMaxX (rect)), 1.0);
    unsigned h = (unsigned) MAX (ceil (CGRectGetMaxY (rect)), 1.0);
    cairo_surface_t *surface = cairo_quartz_surface_create_for_cg_context (context, w, h);
    cairo_t *cr = cairo_create (surface);
    cairo_rectangle (cr, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
    cairo_clip (cr);
    *surface_out = surface;
    return cr;
}

/* ------------------------------------------------------------------------ */

@implementation GnmSheet {
    Sheet *_sheet;
    SheetView *_sv;
    GnmCocoaSheetControl *_sc;
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
- (BOOL)hidesGridLines { return _sheet->hide_grid; }
- (BOOL)hidesColumnHeader { return _sheet->hide_col_header; }
- (BOOL)hidesRowHeader { return _sheet->hide_row_header; }
- (double)zoomFactor { return _sheet->last_zoom_factor_used; }
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

- (NSString *)nameOfColumn:(NSInteger)column { return GnmString (col_name ((int) column)); }
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

#pragma mark - Drawing

- (void)drawCellsInRect:(CGRect)rect context:(CGContextRef)context backgroundColor:(CGColorRef)backgroundColor
{
    if (_sv == NULL || CGRectIsEmpty (rect))
        return;
    GdkRGBA bg = { 1, 1, 1, 1 };
    if (backgroundColor)
        bg = rgba_from_cgcolor (backgroundColor);
    GnmRange bound;
    range_init_full_sheet (&bound, _sheet);

    DrawContext dc;
    draw_context_init (&dc, _sheet, sv_wbv (_sv));

    CGContextSaveGState (context);
    CGContextClipToRect (context, rect);
    cairo_surface_t *surface;
    cairo_t *cr = cairo_for_context (context, rect, &surface);
    draw_region (&dc, cr,
                 (gint64) floor (CGRectGetMinX (rect)), (gint64) floor (CGRectGetMinY (rect)),
                 (gint64) ceil (CGRectGetMaxX (rect)), (gint64) ceil (CGRectGetMaxY (rect)),
                 &bound, &bg);
    cairo_destroy (cr);
    cairo_surface_flush (surface);
    cairo_surface_destroy (surface);
    CGContextRestoreGState (context);
}

- (void)drawSheetObjectsInRect:(CGRect)rect context:(CGContextRef)context
{
    if (_sheet->sheet_objects == NULL || CGRectIsEmpty (rect))
        return;
    CGContextSaveGState (context);
    CGContextClipToRect (context, rect);
    cairo_surface_t *surface;
    cairo_t *cr = cairo_for_context (context, rect, &surface);
    for (GSList *l = _sheet->sheet_objects; l; l = l->next) {
        SheetObject *so = l->data;
        double c[4];
        object_pixel_frame (_sheet, so, c);
        CGRect frame = CGRectMake (c[0], c[1], c[2] - c[0], c[3] - c[1]);
        if (!CGRectIntersectsRect (frame, rect) || frame.size.width <= 0 || frame.size.height <= 0)
            continue;
        cairo_save (cr);
        cairo_translate (cr, frame.origin.x, frame.origin.y);
        sheet_object_draw_cairo_sized (so, cr, frame.size.width, frame.size.height);
        cairo_restore (cr);
    }
    cairo_destroy (cr);
    cairo_surface_flush (surface);
    cairo_surface_destroy (surface);
    CGContextRestoreGState (context);
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
