/*
 * Engine smoke test 1: start the Gnumeric engine with no display, load the
 * plugins, open a workbook, recalculate, read a cell, save a copy, shut down.
 * The call sequence is the one ssconvert uses (upstream src/ssconvert.c main).
 *
 *   headless <workbook> [<output.gnumeric>]
 */
#include <gnumeric.h>
#include <libgnumeric.h>
#include <gnm-plugin.h>
#include <gnumeric-conf.h>
#include <command-context-stderr.h>
#include <workbook-view.h>
#include <workbook.h>
#include <sheet.h>
#include <cell.h>
#include <goffice/goffice.h>
#include <pango/pangocairo.h>
#include <gdk/gdk.h>
#include <stdio.h>

int
main (int argc, char const **argv)
{
	GOCmdContext *cc;
	GOIOContext *ioc;
	WorkbookView *wbv;
	Workbook *wb;
	Sheet *sheet;
	GnmCell *cell;
	char *uri, *txt;

	if (argc < 2) {
		fprintf (stderr, "usage: headless <workbook> [<output.gnumeric>]\n");
		return 2;
	}

	argv = gnm_pre_parse_init (argc, argv);
	gnm_conf_set_persistence (FALSE);	/* do not write config back, as ssconvert */
	gnm_init ();
	cc = gnm_cmd_context_stderr_new ();
	gnm_plugins_init (cc);
	go_component_set_default_command_context (cc);

	printf ("gdk display open: %s\n", gdk_display_get_default () ? "yes (unexpected)" : "no");
	printf ("pango font map: %s\n", G_OBJECT_TYPE_NAME (pango_cairo_font_map_get_default ()));
	printf ("plugins available: %u, active: %u\n",
		g_slist_length (go_plugins_get_available_plugins ()),
		g_slist_length (go_plugins_get_active_plugins ()));
	if (go_plugins_get_active_plugins () == NULL) {
		/* Happens when a previous run with config persistence on stored
		 * plugin file states but no active list; see docs/architecture.md §2. */
		fprintf (stderr, "no plugins active: stale plugin state in the preferences domain '%s'\n",
			 g_get_prgname ());
		return 1;
	}

	ioc = go_io_context_new (cc);
	uri = go_shell_arg_to_uri (argv[1]);
	wbv = workbook_view_new_from_uri (uri, NULL, ioc, NULL);
	g_free (uri);
	if (wbv == NULL) {
		fprintf (stderr, "open failed: %s\n", argv[1]);
		return 1;
	}
	wb = wb_view_get_workbook (wbv);
	workbook_recalc_all (wb);
	sheet = workbook_sheet_by_index (wb, 0);
	cell = sheet_cell_get (sheet, 0, 0);
	txt = cell ? gnm_cell_get_rendered_text (cell) : g_strdup ("<empty>");
	printf ("sheets: %d; first sheet '%s'; A1 = %s\n",
		workbook_sheet_count (wb), sheet->name_unquoted, txt);
	g_free (txt);

	if (argc > 2) {
		GOFileSaver *fs = go_file_saver_for_id ("Gnumeric_XmlIO:sax");
		char *out = go_shell_arg_to_uri (argv[2]);
		workbook_view_save_to_uri (wbv, fs, out, ioc);
		printf ("saved %s: %s\n", argv[2], go_io_error_occurred (ioc) ? "FAILED" : "ok");
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
