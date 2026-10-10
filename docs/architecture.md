# Architecture notes (Phase 0 reconnaissance)

Date: 2026-10-10. Source examined: upstream Gnumeric tag `GNUMERIC_1_12_60`
(submodule `upstream/gnumeric`), goffice 0.10.60 headers from Homebrew. All
`file:line` references below are relative to `upstream/gnumeric/src/` unless
stated otherwise.

Everything in this file was checked against source or by running code. Where a
claim in `HANDOFF.md` turned out to be wrong, the correction is here and the
handoff was updated.

## 1. Summary

- The engine runs headless with GTK linked but never initialized. `gnm_init()`
  never calls `gtk_init()`; it only consults `gdk_screen_get_default()` to skip
  icon-theme setup when there is no display (`libgnumeric.c:326`).
- `WorkbookControl` and `SheetControl` are real GObject base classes with
  vtables (`workbook-control-priv.h`, `sheet-control-priv.h`). Every virtual is
  NULL-checked in the base class, so a Cocoa subclass can be built up method by
  method. The GTK implementations (`WBCGtk`, `SheetControlGUI`) implement all of
  them.
- The command layer (`commands.c`, `cmd-edit.c`) takes `WorkbookControl *`. Seven
  call sites inside it reach into `WBCGtk` for message boxes or confirmations;
  three further files cast an unknown `SheetControl` to `SheetControlGUI` without
  a type check. These are the only decoupling patches the port needs for the MVP
  (see §5 and `docs/upstream-issue.md`).
- Cell drawing (`cell_draw`), border drawing, and sheet-object drawing
  (`sheet_object_draw_cairo_sized`, which covers charts) all take a plain
  `cairo_t *` and work on a cairo-quartz surface with Pango's CoreText backend.
  Verified by `Tests/EngineSmoke/render.c` (§6).
- A GTK-free `libspreadsheet` is explicitly unsupported upstream:
  `configure.ac:200` aborts on `--without-gtk`. GTK stays linked; see §9 for the
  bundle cost.

## 2. Engine lifecycle (from `ssconvert.c`)

`ssconvert.c` is Latin-1 encoded; grep it with `LC_ALL=C`.

Startup, in order (`ssconvert.c:1433-1495`):

1. `gnm_pre_parse_init (argc, argv)` (`libgnumeric.c:232`): raises the stack
   limit to 64 MiB, sets `G_ENABLE_DIAGNOSTIC=0`, records `argv[0]`, sets the
   program name, calls `gutils_init()` (resolves lib/data/locale directories),
   binds the gettext domains, and runs `setlocale (LC_ALL, "")`. Nothing may run
   before it.
2. `gnm_conf_set_persistence (FALSE)` so the run does not write preferences
   back. The Cocoa app will want persistence on.
3. Optional: `g_option_context_add_group (ctx, gnm_get_option_group ())`.
4. `gnm_init ()` (`libgnumeric.c:314`): `libgoffice_init()`, resource
   registration, plugin-service registration, creation of the `GnmApp`
   singleton, then the `*_init()` functions for math, styles, config
   (`gnm_conf_init`, which reads GSettings through goffice's `go_conf`), fonts,
   values, expressions, cells, clipboard, dependents, rendered values,
   functions, printing, autofill, sheet objects, hyperlinks, and the built-in
   `.gnumeric` and text file formats. It finally sets goffice's default image
   DPI from the config keys `core/gui/screen/{horizontal,vertical}dpi`.
5. `cc = gnm_cmd_context_stderr_new ()`: a `GOCmdContext` that prints errors to
   stderr. The Cocoa bridge replaces this with its own `GOCmdContext`
   implementation (interface in goffice `app/go-cmd-context-impl.h`: `error`,
   `error_info`, `error_info_list`, `progress_set`, `progress_message_set`,
   `get_password`, `set_sensitive`).
6. `gnm_plugins_init (cc)` (`gnm-plugin.c`): builds the plugin search list from
   `<libdir>/gnumeric/<version>/plugins`, the extern plugin dir, the per-user
   dir, the config key `plugins/extra-dirs`, and the `GNUMERIC_PLUGIN_PATH`
   environment variable (path-separated), then calls `go_plugins_init()` with
   the config's plugin file states and active list. Plugins are GModules; with
   Homebrew's install 50 are available and all activate headless.
7. `go_component_set_default_command_context (cc)`.

Opening and saving (`ssconvert.c:1205-1344`): `ioc = go_io_context_new (cc)`;
`wbv = workbook_view_new_from_uri (uri, optional_opener, ioc, optional_encoding)`;
`wb = wb_view_get_workbook (wbv)`; `workbook_recalc_all (wb)`;
`workbook_view_save_as (wbv, saver, uri, cc)` or `workbook_view_save_to_uri`.
File arguments must be URIs; use `go_shell_arg_to_uri()` on paths. Savers are
looked up with `go_file_saver_for_id ("Gnumeric_XmlIO:sax")` or
`go_file_saver_for_file_name (name)`.

Shutdown (`ssconvert.c:1530-1533`): `go_component_set_default_command_context
(NULL)`, `g_object_unref (cc)`, `gnm_shutdown ()`, `gnm_pre_parse_shutdown ()`.
`gnm_shutdown()` shuts plugins down first and stores their states in config.

The GTK front end (`main-application.c`, also Latin-1) differs only in calling
`gtk_init()` at line 133 before `gnm_init()` at 240, creating a `GOIOContext`
subclass with a splash screen, and running `gtk_main()`.

Path resolution (`gutils.c:48-135`): lib, data, locale, and extern-plugin
directories are compile-time constants (`GNUMERIC_LIBDIR` etc. from
`configure --prefix`), overridden only when running inside the build tree
(`running_in_tree()` and `GNM_TEST_TOP_BUILDDIR`). There is no general
environment override, so the app bundle must either be built with a prefix that
matches its final layout or carry a patch that lets the bridge set these
directories at startup. This is a Phase 6 decision; for Phases 1 to 5 the
`build/prefix` install is used in place.

Configuration: `gnumeric-conf.c` goes through goffice's `go_conf_*` API, and
Homebrew's goffice is built with the GSettings backend (`libgoffice` imports
`g_settings_new` and `g_settings_list_schemas`). The schemas
`org.gnome.gnumeric*.gschema.xml` must be compiled and findable (the
`gschemas.compiled` next to them, or `GSETTINGS_SCHEMA_DIR`). `gnm_init()`
succeeds on this machine because Homebrew compiled them into
`/opt/homebrew/share/glib-2.0/schemas`. The bundle must ship a compiled schema
directory and set `GSETTINGS_SCHEMA_DIR` before `gnm_init()`.

On macOS, GIO's default settings backend is `GNextstepSettingsBackend`, which
stores values through `NSUserDefaults`. The storage domain is the bundle
identifier, or for a bare executable the process name, so values land in
`~/Library/Preferences/<name>.plist` (Henry's Homebrew Gnumeric has
`gnumeric.plist` there). Two consequences, both observed on 2026-10-10:

- `gnm_shutdown()` stores the plugin *file states* (`plugins/file-states`)
  but not the *active* list; the GTK app stores that separately through
  `gnm_conf_set_plugins_active()` (`main-application.c:146`,
  `store_plugin_state`). A program that shuts down with persistence on and
  never stores the active list leaves a domain in which every plugin is
  "known" and none is active, so the next launch loads no plugins at all
  (charts then fail with "unknown type 'GogXYPlot'"). The Cocoa app must
  store the active list the way the GTK app does, and tests must run with
  `gnm_conf_set_persistence (FALSE)` as ssconvert does.
- The app's preferences domain is its bundle identifier; choose it once and
  keep it.

## 3. Control classes the bridge must implement

### `WorkbookControl` (`workbook-control-priv.h`)

Instance: `GODocControl base; WorkbookView *wb_view; gulong
clipboard_changed_signal`. `GODocControl` (goffice `app/go-doc-control-impl.h`)
is a trivial GObject holding a `GODoc *`.

Class vtable, with the GTK implementation for reference (`wbc-gtk.c:5000-5030`):

| Slot | Purpose | GTK impl |
|---|---|---|
| `control_new (wbc, wbv, wb, extra)` | create another control of the same kind (new window) | `wbc_gtk_control_new` |
| `init_state (wbc)` | called once after the view is attached | `wbc_gtk_init_state` |
| `style_feedback (wbc, changes)` | update toolbar/inspector state from the edit cell's style | `wbc_gtk_style_feedback` |
| `edit_line_set (wbc, text)` | set the formula bar text | `wbcg_edit_line_set` |
| `edit_finish (wbc, accept)` | end an in-progress cell edit | not set by WBCGtk; handled via `wbcg_edit_finish` |
| `selection_descr_set (wbc, text)` | the "A1:B2" / name box text | `wbcg_edit_selection_descr_set` |
| `update_action_sensitivity (wbc)` | enable/disable menu actions | `wbcg_update_action_sensitivity` |
| `sheet.add (wbc, sv)` | a `SheetView` was created; create the `SheetControl` and a tab | `wbcg_sheet_add` |
| `sheet.remove (wbc, sheet)` | | `wbcg_sheet_remove` |
| `sheet.focus (wbc, sheet)` | | `wbcg_sheet_focus` |
| `sheet.remove_all (wbc)` | | `wbcg_sheet_remove_all` |
| `undo_redo.truncate (wbc, n, is_undo)` | trim the undo/redo menu list | `wbc_gtk_undo_redo_truncate` |
| `undo_redo.pop (wbc, is_undo)` | | `wbc_gtk_undo_redo_pop` |
| `undo_redo.push (wbc, is_undo, text, key)` | | `wbc_gtk_undo_redo_push` |
| `undo_redo.labels (wbc, undo, redo)` | menu item titles | `wbcg_undo_redo_labels` |
| `menu_state.update (wbc, flags)` | `MS_*` flags in `workbook-control.h` | `wbcg_menu_state_update` |
| `claim_selection (wbc)` | take ownership of the system clipboard | `wbcg_claim_selection` |
| `paste_from_selection (wbc, pt)` | paste from the system clipboard | `wbcg_paste_from_selection` |
| `validation_msg (wbc, style, title, msg)` | validation alert; returns a button id | `wbcg_validation_msg` |

Every slot is optional: `workbook-control.c:49-60` wraps each call in a NULL
check (`WBC_VIRTUAL`). Creation sequence (`wbc_gtk_new`, `wbc-gtk.c`):
`g_object_new (TYPE)`, `wb_control_set_view (wbc, optional_view,
optional_wb)` (creates a `WorkbookView` and `Workbook` if NULL), then
`wb_control_menu_state_update (wbc, MS_ALL)`,
`wb_control_update_action_sensitivity`, `wb_control_style_feedback (wbc,
NULL)`, and finally `wb_control_init_state (wbc)`, which calls `sheet.add` for
each existing sheet view. The undo/redo stack itself lives in the `Workbook`;
the app calls `command_undo (wbc)` / `command_redo (wbc)` (`commands.h:9-10`)
and receives the vtable notifications above. Do not mirror the stack in
`NSUndoManager`.

`WorkbookView` is the model-side link: `wb_view_attach_control`,
`wb_view_detach_control`, `wb_view_sheet_focus`, `wb_view_cur_sheet`,
`wb_view_edit_line_set`, `wb_view_selection_desc`, `wb_view_style_feedback`,
`wb_view_auto_expr_recalc`, `wb_view_menus_update`, `wb_view_is_protected`
(`workbook-view.h`).

### `SheetControl` (`sheet-control-priv.h`)

Instance: `GObject object; SheetView *view; WorkbookControl *wbc`. The
`SheetView` (`sheet-view.h`) owns the selection, edit position, frozen panes,
and the list of controls (`gnm_sheet_view_attach_control`,
`gnm_sheet_view_detach_control`); `SHEET_FOREACH_CONTROL` fans model changes out
to every control.

Class vtable; `SheetControlGUI` implements all 17 (`sheet-control-gui.c:3923-3939`):

| Slot | What the Cocoa grid must do |
|---|---|
| `resize (sc, force_scroll)` | relayout after zoom or column/row size change |
| `redraw_all (sc, headers)` | `setNeedsDisplay` on grid (and headers) |
| `redraw_range (sc, range)` | invalidate the rect of a cell range |
| `redraw_headers (sc, col, row, range)` | invalidate header strips |
| `ant (sc)` / `unant (sc)` | start/stop marching ants for the cut/copy range |
| `scrollbar_config (sc)` | update scroll extents from `sheet->rows.max_used` etc. |
| `mode_edit (sc)` | leave any range-selection or object mode |
| `set_top_left (sc, col, row)` | scroll so the cell is at the top left |
| `recompute_visible_region (sc, full)` | recompute first/last visible col/row in `SheetView` |
| `make_cell_visible (sc, col, row, couple_panes)` | scroll to reveal a cell |
| `cursor_bound (sc, range)` | move the selection rectangle |
| `set_panes (sc)` | create or remove frozen-pane sub-views |
| `object_create_view (sc, so)` | create a view for a sheet object (chart, image, widget) |
| `scale_changed (sc)` | zoom changed |
| `show_im_tooltip (sc, msg, pos)` | show an input-message popover |
| `freeze_object_view (sc, freeze)` | suspend object-view updates during bulk changes |

`sc_view`, `sc_sheet`, `sc_wbc` are the accessors; `sheet-control.c:29-40`
NULL-checks every virtual.

### `GnmApp` signals the app should observe

`application.c:846-895`: `workbook_added`, `workbook_removed`,
`window-list-changed`, `custom-ui-added`, `custom-ui-removed`,
`clipboard_modified`, `recalc_finished`, `recalc_clear_caches`. The GTK recent
file manager is only created when `gdk_display_get_default()` is non-NULL
(`application.c:914`); the Cocoa app uses `NSDocumentController` recents.

## 4. GTK dependency map of `src/`

Method: per file, count `#include <gtk/|gdk/`, `gtk_*`, `gdk_*`, `wbcg_*`,
`WBCGtk`, `scg_*`, and `goc_*` references. Full table reproduced from the
survey (zero rows omitted).

**Engine files with no GTK, GDK, WBCGtk, SCG, or canvas references** (reusable
unchanged): `auto-format cell cellspan clipboard collect colrow
command-context command-context-stderr complete complete-sheet complex
consolidate criteria dependent expr expr-deriv expr-name file-autoft
format-template func func-builtin gnm-cell-combo gnm-commands-slicer
gnm-data-cache-source gnm-datetime gnm-format gnm-random gnm-sheet-slicer
gnm-sheet-slicer-combo go-data-cache go-data-cache-field go-data-cache-source
go-data-slicer go-data-slicer-field go-val graph history input-msg mathfunc
mstyle number-match outoflinedocs parse-util position print-cell
rangefunc rangefunc-strings ranges rendered-value search selection session
sf-bessel sf-dpq sf-gamma sf-trig sheet-autofill sheet-conditions
sheet-control sheet-diff sheet-filter sheet-merge sheet-style sheet-utils
sheet-view sort ssconvert ssdiff ssgrep ssindex sstest stf-export stf-parse
style-conditions validation value value-sheet workbook workbook-cmd-format
workbook-control workbook-view xml-sax-read xml-sax-write`, plus `parser.y`.
`src/tools/`: 24 of 26 files are GTK-free and take `WorkbookControl *` or
`GOCmdContext *` (`random-generator.c` and `gnm-solver.c` reference `WBCGtk`).

**Engine files with incidental GTK use** (each assessed; none needs a display):

| File | Use | Assessment |
|---|---|---|
| `application.c:545-737, 914` | `GtkFileFilter`, `GtkRecentManager` | recent-file history only; skipped without a display |
| `cell-draw.c:22, 345-373` | `GdkRGBA` in `GnmCellDrawStyle`, `gdk_cairo_set_source_rgba` | plain struct and a cairo helper; no display |
| `commands.c:7689-7702` | `GtkAdjustment` for widget sheet objects | GObject only |
| `gnumeric-conf.c` | 14 `gtk_*` refs | `GtkPrintSettings`/`GtkPageSetup` serialization for print config |
| `gutils.c:1012` | `gtk_check_version` | benign |
| `libgnumeric.c:326-329` | icon theme | guarded by `gdk_screen_get_default()` |
| `pattern.c:79, 94` | `gtk_style_context_get_background_color` | only when `is_selected`; pass `FALSE` and NULL |
| `preview-grid.c:251` | `gtk_render_background` | the GTK format-preview canvas; not used |
| `print-info.c`, `print.c` | `GtkPrintOperation`, `GtkPageSetup` | GTK printing; Cocoa printing is a later phase (§7) |
| `sheet.c:816` | `gtk_widget_get_default_direction` | static global; under `#ifdef GNM_WITH_GTK` |
| `style.c:403-413` | `gdk_screen_get_default`, `gtk_get_default_language` | **windowless fallback exists**: creates a `pango_cairo_font_map_new()` context at 96 dpi when there is no screen |
| `style-border.c:29` | `#include <gdk/gdk.h>` | header only |
| `style-color.c:120-125` | `style_color_grid (GtkStyleContext *)` | returns `#c7c7c7` when passed NULL |
| `sheet-style.c` | `sheet_style_update_grid_color (sheet, ctxt)` | passes `ctxt` to `style_color_grid`; NULL is fine |
| `undo.c:217-222` | see §5 | unguarded SCG cast |
| `stf.c:191, 296`, `stf-export.c:663` | text import/export dialogs | guarded by `GNM_IS_WBC_GTK`; non-GTK controls get an error string ("This importer can only be used with a GUI.") or no dialog |

**GTK front end** (replaced by Cocoa code): `wbc-gtk.c` (5478 lines),
`wbc-gtk-actions.c` (4531), `wbc-gtk-edit.c` (1296), `sheet-control-gui.c`
(4535), `gnm-pane.c` (3195), `item-grid.c` (1317), `item-bar.c` (1262),
`item-cursor.c` (1549), `item-edit.c` (753), `gnm-graph-window.c`,
`gnumeric-simple-canvas.c`, `gui-clipboard.c`, `gui-file.c`, `gui-util.c`,
`io-context-gtk.c`, `sheet-object-widget.c` (GTK widgets on the canvas),
`src/dialogs/` (69 `.c`, 85 GtkBuilder `.ui`, 83 entry points, every one
taking `WBCGtk *`), `src/widgets/` (18 files).

**Sheet objects** (`sheet-object*.c`, `gnm-so-*.c`): model code is clean; each
has a `new_view` that creates a `GocItem` on the GTK canvas, and a
`draw_cairo` used for printing and image export. The Cocoa grid draws objects
through `draw_cairo` (§6) and provides its own selection handles. The
`GNM_WITH_GTK` ifdefs in `gnm-so-filled.c`, `gnm-so-line.c`, `gnm-so-path.c`,
`gnm-so-polygon.c`, and `sheet.c` are the only ones in `src/`.

## 5. Engine entry points that require `WBCGtk`

These are the places where code reachable from a generic `WorkbookControl`
assumes the GTK subclass. "Unguarded" means a `WBC_GTK()` cast or
`(SheetControlGUI *)` cast with no type check: with a Cocoa control the cast
yields garbage and the call crashes. "Guarded" means a `GNM_IS_WBC_GTK` /
`GNM_IS_SCG` check that skips the GTK-only behavior.

| Site | Function | Behavior | Status |
|---|---|---|---|
| `commands.c:1457` | `cmd_insert_cols` | error dialog when data would be pushed off the sheet | unguarded |
| `commands.c:1486` | `cmd_insert_rows` | same | unguarded |
| `commands.c:2347` | `cmd_selection_colrow_hide` | yes/no confirmation when hiding all rows or columns | unguarded |
| `commands.c:3208` | `cmd_paste_copy` | yes/no confirmation for pastes of more than 10000 copies | unguarded |
| `commands.c:3051` | `cmd_paste_copy_impl` | select the pasted objects through `wbcg_get_nth_scg` | guarded |
| `cmd-edit.c:418` | `cmd_shift_rows` | error dialog | unguarded |
| `cmd-edit.c:467` | `cmd_shift_cols` | error dialog | unguarded |
| `undo.c:217-222` | `cb_filter_set_condition_undo_set_pb` via `SHEET_FOREACH_CONTROL` (line 266) | writes "%d rows match" into `wbcg->progress_bar` | unguarded `(SheetControlGUI *)` cast |
| `sheet-object.c:131-140, 203-214` | `cb_so_size_position` | detach the object guru | guarded (`g_return_if_fail (GNM_IS_SCG)`) |
| `sheet-object-graph.c:320-372, 491, 718-818` | image save, "open in new window", chart guru | take `WBCGtk *` explicitly (`sheet_object_graph_guru` is public) |
| `sheet-object-image.c:294-317`, `sheet-object-component.c:189-384` | image save dialogs, component editing | `scg_wbcg (GNM_SCG (sc))` |
| `hlink.c:66, 309, 510, 563` | `gnm_hlink_activate (GnmHLink *, WBCGtk *)` | hyperlink activation | public API takes `WBCGtk *` |
| `print.c:1244-2022` | print progress, page setup | guarded by `GNM_IS_WBC_GTK` |
| `stf.c:68, 191, 208, 296, 316`; `stf-export.c:663` | text import/export dialogs | guarded |
| `gnm-plugin.c:592` | `cb_load_and_functional (GnmSolverFactory *, WBCGtk *, ...)` | solver factory callback signature | signature only |

The four error dialogs and two confirmations in `commands.c`/`cmd-edit.c` can
be routed through existing generic mechanisms: `go_cmd_context_error_invalid`
/ `go_cmd_context_error` on the control (every `WorkbookControl` is a
`GOCmdContext`), and the existing `validation_msg` vtable slot or a new
`WorkbookControlClass` slot for yes/no questions. The `undo.c` cast can become
a `wb_control_*` progress-message call. These form the patch series proposed
in `docs/upstream-issue.md`. Until they land, `patches/` will carry them.

For Phase 1 (read-only viewer) none of these sites is reachable. For Phase 2,
`cmd_insert_cols`/`cmd_insert_rows` and `cmd_paste_copy` are, so the patches
are needed before the MVP.

## 6. Rendering

Verified with `Tests/EngineSmoke/render.c` on 2026-10-10 against Homebrew's
`libspreadsheet-1.12.60.dylib`, with no display:

- Pango's default cairo font map on this machine is
  `PangoCairoCoreTextFontMap`; `gnm_pango_context_get()` (`style.c:399`)
  creates a windowless context from it at 96 dpi.
- Cells: `cell_draw (cell, cr, x, y, height, width, h_center,
  show_extension_markers, &style)` (`cell-draw.h`) rendered text, alignment,
  and colors from `chart-tests.gnumeric` and `excel12/cellstyle.xlsx` onto a
  `cairo_image_surface` and onto `cairo_quartz_surface_create()` identically.
- Charts: `sheet_object_draw_cairo_sized (so, cr, width, height)`
  (`sheet-object.h:149`) rendered a `SheetObjectGraph` (XY plot with log axis
  and legend) on both surfaces. `sheet_object_position_pts_get (so, coords)`
  gives the object's rectangle in points. The same call covers images, lines,
  filled shapes, paths, polygons, and (44 `draw_cairo` references in
  `sheet-object-widget.c`) form widgets, so Phase 2b read-only charts need no
  GTK canvas.
- Round trips: `.gnumeric` via `Gnumeric_XmlIO:sax` and `.xlsx` via
  `Gnumeric_Excel:xlsx2` saved without error.

What the Cocoa grid view replicates from `item_grid_draw_region`
(`item-grid.c:444-880`), in order:

1. Find the visible column and row range for the dirty rect (hidden
   columns/rows skipped; `sheet_col_get_info`/`sheet_row_get_info` give
   `size_pixels`, `sheet_col_get_distance_pixels` sums them).
2. Respan rows (`row_calc_spans`) so cells can overflow into empty neighbors.
3. Fill the background, then iterate rows: `sheet_style_get_row` loads a
   `GnmStyleRow` of styles and borders for `start_col-1 .. end_col+1`;
   `gnm_sheet_merge_get_overlap` supplies merged ranges, drawn by
   `item_grid_draw_merged_range`.
4. Per cell: `gnm_pattern_background_set (style, cr, FALSE, NULL)` for the
   fill, then `cell_draw` for non-empty cells that are not the edit cell,
   honoring spans (`row_span_get`) and offsets for right/center alignment.
5. Per row: `gnm_style_borders_row_draw (prev_vert, &sr, cr, x, y, y_next,
   colwidths, TRUE, ...)` draws all borders of the row, including grid lines
   when `sheet->hide_grid` is false (`gnm_style_border_none()` is the grid
   line, colored by `sheet_style_update_grid_color (sheet, NULL)`).
6. Diagonal borders via `gnm_style_border_draw_diag`.

Scaling: `GnmRenderedValue`s are computed at the sheet zoom; HiDPI is handled
by applying the backing scale to the cairo context rather than to the engine.
`gnm_app_display_dpi_get()` reads `core/gui/screen/{horizontal,vertical}dpi`
from config (default 96) and feeds `go_image_set_default_dpi`.

## 7. Editing, undo, printing

- Edit commit path (`wbc-gtk-edit.c:380-424`): `wbcg_edit_finish` calls
  `sheet_cell_set_text` for the in-place case and otherwise
  `cmd_area_set_array_expr (wbc, sv, texpr)`, `cmd_set_text (wbc, sheet,
  &sv->edit_pos, text, markup, autocorrect)`, or `cmd_area_set_text (wbc, sv,
  text, markup)`. `commands.h:33-40` declares them. The handoff's
  `cmd_set_text` name is correct.
- `WBCEditResult` (`wbc-gtk.h:49-56`): `REJECT`, `ACCEPT`, `ACCEPT_WO_AC`,
  `ACCEPT_RANGE`, `ACCEPT_ARRAY`; the Cocoa editor reproduces the same
  decision (Enter, Ctrl-Enter, Ctrl-Shift-Enter).
- Undo/redo: `command_undo`, `command_redo`, `command_repeat` on the control;
  notifications through the `undo_redo.*` vtable slots (§3).
- Printing: `print.c` is built on `GtkPrintOperation` and
  `gnm_gtk_print_cell_range` takes a `GtkPrintContext`; the Cocoa app will
  drive `NSPrintOperation` and reuse the `print-cell.c` drawing with a cairo
  context obtained from the `NSGraphicsContext`. Deferred beyond the MVP.
- Text import (`stf.c`) requires the GTK dialog; CSV import for non-GTK
  controls reports an error. The Cocoa app needs its own import sheet calling
  `stf_parse_*` (`stf-parse.h`, GTK-free).

## 8. Build facts

- `libspreadsheet.la` is one library containing engine, GTK front end,
  dialogs, and tools (`src/Makefile.am:347-493`). The binaries `gnumeric`,
  `ssconvert`, `ssindex`, `ssgrep`, `ssdiff`, `sstest` link it.
- `configure.ac:196-215`: `--without-gtk` exists but errors out
  ("configuration without gtk+ currently does not work"); `GNM_WITH_GTK` is
  always defined.
- `autogen.sh` requires `aclocal`, `glib-gettextize`, `gtkdocize`,
  `intltoolize`, `autoreconf` and expects `yelp.m4` for `YELP_HELP_INIT`
  (`configure.ac:1005`). `AC_PROG_YACC` requires bison; the git tree has only
  `parser.y`. Homebrew's formula builds the release tarball with macOS bison
  2.3.
- Homebrew's formula applies upstream commit `0de4c0a4` (`sstest.c` `bool` to
  `gboolean`) to 1.12.60; it is in `patches/0001-*.patch` here and is part of
  1.12.62.
- Homebrew's gnumeric keg ships `include/libspreadsheet-1.12/`,
  `lib/libspreadsheet-1.12.60.dylib`, and `lib/pkgconfig/libspreadsheet-1.12.pc`
  (`Requires: glib-2.0 gobject-2.0 libgsf-1 libxml-2.0 gtk+-3.0
  libgoffice-0.10`). The bridge can be compiled against it with plain
  `pkg-config --cflags --libs libspreadsheet-1.12`, which is how the smoke
  programs are built today.

## 9. Bundle-size cost of shipping GTK

Transitive `otool -L` closure of `libspreadsheet`, the 41 Gnumeric plugins,
the 9 goffice plugins, and the gdk-pixbuf loaders, restricted to
`/opt/homebrew` (system frameworks excluded):

| Component | Size |
|---|---|
| 45 dylibs | 37.1 MB |
| Gnumeric plugins (`.so`) | 4.7 MB |
| goffice plugins | 1.2 MB |
| gdk-pixbuf loaders | 0.8 MB |
| Gnumeric + goffice data (`share/`) | 0.6 MB |
| Gnumeric + goffice locale | 22.6 MB (trim to a language subset) |
| Adwaita icons | 15 MB (not needed; GTK never draws) |
| GLib schemas | 56 KB |

Largest dylib contributors: gtk+3 7.9 MB, librsvg 6.1 MB, libspreadsheet 4.8
MB, glib 3.9 MB, goffice 1.5 MB. The closure also drags in libx11, libxcb,
libepoxy, and freetype/fontconfig through gtk+3 and pango (about 3.5 MB); none
is used at runtime. Roughly 45 MB of binaries before locale data, which is
acceptable.

## 10. Risks carried into Phase 1

1. **GSettings schemas** (§2): a missing schema is a hard abort inside
   `gnm_conf_init`. The bridge test target must set `GSETTINGS_SCHEMA_DIR`.
2. **Compile-time data paths** (§2): no environment override; decide in Phase 6
   between a relocatable-prefix patch and building with the final bundle
   layout as prefix.
3. **GLib main loop**: the engine uses idles and timeouts (recalc, autosave,
   clipboard). Integrate `GMainContext` with `NSRunLoop` on the main thread
   following `gdk/quartz/gdkeventloop-quartz.c` (not shipped by Homebrew;
   fetch from the GTK repository when needed).
4. **The seven unguarded `WBCGtk` sites** (§5) must be patched before Phase 2.
5. **Form widgets** (`sheet-object-widget.c`) are GTK widgets in the GTK build;
   the Cocoa build draws them via `draw_cairo` and must implement interaction
   itself (Phase 4).
6. **Hyperlinks** take `WBCGtk *`; the Cocoa app opens URLs through
   `NSWorkspace` and only needs the sheet-jump case from the engine.
7. **Plugin state persistence** (§2): store the active plugin list at
   shutdown, or every later launch runs with no plugins.
