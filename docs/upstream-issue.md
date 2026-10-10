# Draft GNOME GitLab issue for GNOME/gnumeric

Status: draft for Henry's review. Henry posts it; nothing has been sent.
Target: https://gitlab.gnome.org/GNOME/gnumeric/-/issues

---

**Title:** Decoupling a few WorkbookControl call sites from WBCGtk for a non-GTK front end

I am working on a native macOS (AppKit) front end for Gnumeric that reuses
libspreadsheet, goffice, and libgsf unchanged, and replaces only the GTK user
interface by subclassing `WorkbookControl` and `SheetControl`. It is at the
reconnaissance stage: the engine runs headless on macOS with GTK linked but
never initialized, and `cell_draw()` and `sheet_object_draw_cairo_sized()`
render correctly to cairo-quartz surfaces with Pango's CoreText backend. There
is no releasable code yet, so this is not an announcement, only a question
about a small set of patches.

Findings from reading 1.12.60 (`src/`):

The `WorkbookControlClass` and `SheetControlClass` vtables are complete enough
to build another front end on, and `commands.c` takes `WorkbookControl *`
throughout. However, a handful of places reachable from a generic
`WorkbookControl` cast it to `WBCGtk` without a type check, so a non-GTK
control crashes there:

| Site | Function | What it does |
|---|---|---|
| `commands.c:1457` | `cmd_insert_cols` | `go_gtk_notice_dialog (wbcg_toplevel (WBC_GTK (wbc)), ...)` when data would be pushed off the sheet |
| `commands.c:1486` | `cmd_insert_rows` | same |
| `commands.c:2347` | `cmd_selection_colrow_hide` | `go_gtk_query_yes_no` before hiding all rows/columns |
| `commands.c:3208` | `cmd_paste_copy` | `go_gtk_query_yes_no` for more than 10000 copies |
| `cmd-edit.c:418` | `cmd_shift_rows` | `go_gtk_notice_dialog` |
| `cmd-edit.c:467` | `cmd_shift_cols` | `go_gtk_notice_dialog` |
| `undo.c:217-222` | `cb_filter_set_condition_undo_set_pb` (via `SHEET_FOREACH_CONTROL` at line 266) | casts `SheetControl *` to `SheetControlGUI *` to set the progress-bar text |

Other sites (`commands.c:3051`, `sheet-object.c:131`, `print.c`, `stf.c`,
`stf-export.c`) already guard with `GNM_IS_WBC_GTK` / `GNM_IS_SCG`, and
`hlink.c`, `sheet-object-graph.c`, and the dialogs take `WBCGtk *` explicitly,
which is fine for a front end that supplies its own.

Proposal, if acceptable:

1. Route the four error dialogs through the control's `GOCmdContext`
   (`go_cmd_context_error_invalid` or a `GOErrorInfo`), which `WBCGtk` already
   turns into a dialog.
2. Replace the two `go_gtk_query_yes_no` calls with a new
   `WorkbookControlClass` virtual (for example `query_yes_no (wbc, title,
   msg)`), or with the existing `validation_msg` slot, defaulting to "yes" when
   the slot is NULL so ssconvert behavior is unchanged.
3. Guard the `undo.c` cast with `GNM_IS_SCG`, or add a `wb_control_*` progress
   message hook.

Each is a few lines and leaves the GTK build's behavior unchanged. Would you
accept merge requests of this shape? If you would rather keep these sites as
they are, I will carry the patches downstream; either answer is useful.

Two smaller questions, no action needed:

- `configure.ac` rejects `--without-gtk`. I am not asking for that to work; I
  only want to confirm that linking GTK without ever calling `gtk_init()` (as
  ssconvert does) is the supported way to run the engine without a display.
- `gutils.c` resolves lib/data/locale directories from compile-time constants.
  For an app bundle, would a patch adding an environment or API override for
  these directories be acceptable, or is building with the bundle layout as
  `--prefix` the intended approach?

Thanks for Gnumeric.
