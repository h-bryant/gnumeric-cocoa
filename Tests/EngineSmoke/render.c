/*
 * Engine smoke test 2: with no display, draw the first 8x20 cells of the first
 * sheet with the engine's own cell_draw(), and the first chart object with
 * sheet_object_draw_cairo_sized(), each onto a cairo image surface and onto a
 * cairo-quartz surface.  This is the rendering path the Cocoa grid view will
 * use (HANDOFF.md §4, Phase 1 and Phase 2b).
 *
 *   render <workbook> [<output file; format chosen by extension>]
 *
 * Writes cells-image.png, cells-quartz.png, chart-image.png, chart-quartz.png
 * into the current directory.
 */
#include <gnumeric.h>
#include <libgnumeric.h>
#include <gnm-plugin.h>
#include <gnumeric-conf.h>
#include <command-context-stderr.h>
#include <workbook-view.h>
#include <workbook.h>
#include <sheet.h>
#include <sheet-object.h>
#include <sheet-object-graph.h>
#include <cell.h>
#include <cell-draw.h>
#include <colrow.h>
#include <goffice/goffice.h>
#include <pango/pangocairo.h>
#include <gdk/gdk.h>
#include <cairo.h>
#include <cairo-quartz.h>
#include <stdio.h>

static void render_cells (Sheet *sheet, cairo_surface_t *surf, int ncols, int nrows)
{
	int W = (int) sheet_col_get_distance_pixels (sheet, 0, ncols);
	int H = (int) sheet_row_get_distance_pixels (sheet, 0, nrows);
	cairo_t *cr = cairo_create (surf);
	GnmCellDrawStyle style = { { 0.5, 0.5, 0.5, 1.0 }, 4 };
	int x, y, c, r;
	cairo_set_source_rgb (cr, 1, 1, 1); cairo_paint (cr);
	cairo_set_source_rgb (cr, 0.78, 0.78, 0.78); cairo_set_line_width (cr, 1);
	for (r = 0, y = 0; r <= nrows; y += sheet_row_get_info (sheet, r++)->size_pixels) {
		cairo_move_to (cr, 0, y + .5); cairo_line_to (cr, W, y + .5);
	}
	for (c = 0, x = 0; c <= ncols; x += sheet_col_get_info (sheet, c++)->size_pixels) {
		cairo_move_to (cr, x + .5, 0); cairo_line_to (cr, x + .5, H);
	}
	cairo_stroke (cr);
	for (r = 0, y = 0; r < nrows; r++) {
		ColRowInfo const *ri = sheet_row_get_info (sheet, r);
		for (c = 0, x = 0; c < ncols; c++) {
			ColRowInfo const *ci = sheet_col_get_info (sheet, c);
			GnmCell *cell = sheet_cell_get (sheet, c, r);
			if (cell && !gnm_cell_is_empty (cell))
				cell_draw (cell, cr, x, y, ri->size_pixels, ci->size_pixels, -1, FALSE, &style);
			x += ci->size_pixels;
		}
		y += ri->size_pixels;
	}
	cairo_destroy (cr);
}

static SheetObject *first_graph (Workbook *wb, Sheet **where)
{
	int i;
	for (i = 0; i < workbook_sheet_count (wb); i++) {
		Sheet *sheet = workbook_sheet_by_index (wb, i);
		GSList *l;
		for (l = sheet->sheet_objects; l; l = l->next)
			if (GNM_IS_SO_GRAPH (l->data)) { *where = sheet; return l->data; }
	}
	return NULL;
}

int main (int argc, char const **argv)
{
	argv = gnm_pre_parse_init (argc, argv);
	gnm_conf_set_persistence (FALSE);
	gnm_init ();
	GOCmdContext *cc = gnm_cmd_context_stderr_new ();
	gnm_plugins_init (cc);
	go_component_set_default_command_context (cc);

	GOIOContext *ioc = go_io_context_new (cc);
	char *uri = go_shell_arg_to_uri (argv[1]);
	WorkbookView *wbv = workbook_view_new_from_uri (uri, NULL, ioc, NULL);
	g_free (uri);
	if (!wbv) { fprintf (stderr, "open failed\n"); return 1; }
	Workbook *wb = wb_view_get_workbook (wbv);
	workbook_recalc_all (wb);
	Sheet *s0 = workbook_sheet_by_index (wb, 0);
	printf ("opened: %d sheets, first '%s', pango font map %s\n",
		workbook_sheet_count (wb), s0->name_unquoted,
		G_OBJECT_TYPE_NAME (pango_cairo_font_map_get_default ()));

	/* cells, image surface */
	int ncols = 8, nrows = 20;
	int W = (int) sheet_col_get_distance_pixels (s0, 0, ncols) + 1;
	int H = (int) sheet_row_get_distance_pixels (s0, 0, nrows) + 1;
	cairo_surface_t *img = cairo_image_surface_create (CAIRO_FORMAT_RGB24, W, H);
	render_cells (s0, img, ncols, nrows);
	cairo_surface_write_to_png (img, "cells-image.png");
	cairo_surface_destroy (img);
	printf ("cells (%dx%d px) -> cells-image.png\n", W, H);

	/* cells, quartz surface */
	cairo_surface_t *qz = cairo_quartz_surface_create (CAIRO_FORMAT_ARGB32, W, H);
	render_cells (s0, qz, ncols, nrows);
	cairo_surface_flush (qz);
	printf ("cells on cairo-quartz surface: status %s -> cells-quartz.png\n",
		cairo_status_to_string (cairo_surface_status (qz)));
	cairo_surface_write_to_png (qz, "cells-quartz.png");
	cairo_surface_destroy (qz);

	/* first chart, both surfaces */
	Sheet *where = NULL;
	SheetObject *so = first_graph (wb, &where);
	if (so) {
		double coords[4];
		sheet_object_position_pts_get (so, coords);
		double w = coords[2] - coords[0], h = coords[3] - coords[1];
		cairo_surface_t *cs = cairo_image_surface_create (CAIRO_FORMAT_ARGB32, (int) w, (int) h);
		cairo_t *cr = cairo_create (cs);
		cairo_set_source_rgb (cr, 1, 1, 1); cairo_paint (cr);
		sheet_object_draw_cairo_sized (so, cr, w, h);
		cairo_destroy (cr);
		cairo_surface_write_to_png (cs, "chart-image.png");
		cairo_surface_destroy (cs);
		cs = cairo_quartz_surface_create (CAIRO_FORMAT_ARGB32, (int) w, (int) h);
		cr = cairo_create (cs);
		cairo_set_source_rgb (cr, 1, 1, 1); cairo_paint (cr);
		sheet_object_draw_cairo_sized (so, cr, w, h);
		cairo_destroy (cr);
		cairo_surface_write_to_png (cs, "chart-quartz.png");
		printf ("chart on sheet '%s' (%.0fx%.0f pt) -> chart-image.png, chart-quartz.png (quartz status %s)\n",
			where->name_unquoted, w, h, cairo_status_to_string (cairo_surface_status (cs)));
		cairo_surface_destroy (cs);
	} else
		printf ("no chart objects in workbook\n");

	if (argc > 2) {
		char *out = go_shell_arg_to_uri (argv[2]);
		GOFileSaver *fs = go_file_saver_for_file_name (argv[2]);
		workbook_view_save_to_uri (wbv, fs, out, ioc);
		printf ("saved %s via %s: %s\n", argv[2], go_file_saver_get_id (fs),
			go_io_error_occurred (ioc) ? "FAILED" : "ok");
		g_free (out);
	}
	g_object_unref (wb);
	g_object_unref (ioc);
	go_component_set_default_command_context (NULL);
	g_object_unref (cc);
	gnm_shutdown ();
	gnm_pre_parse_shutdown ();
	return 0;
}
