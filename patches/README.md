# Patches

Patches to upstream Gnumeric, applied by `scripts/apply-patches.sh` to a copy of
`upstream/gnumeric` (never to the submodule). Name them `NNNN-description.patch`
and start each with a comment header saying why it exists and where it came from.
Keep every patch minimal and in the form upstream could accept: engagement is
deferred, not ruled out (`docs/decisions.md` ADR-011).

| Patch | Why |
|---|---|
| `0001-decouple-command-dialogs-from-wbcgtk.patch` | The seven command-layer sites that cast to `WBCGtk` (`docs/architecture.md` §5) go through the control's command context and a new `query_yes_no` vtable slot, so a Cocoa control survives Phase 2 editing. GTK behavior unchanged. |
| `0002-merge-center-style-ref.patch` | `cmd_merge_cells_redo` unreffed the align-center style once too often (`sheet_apply_style` absorbs a reference), a use after free in Merge and Center that the GTK front end shares. One `gnm_style_ref` per range. |
| `0003-analysis-tool-undo-colrow-state.patch` | `cmd_analysis_tool_undo` destroyed its saved column and row state lists without clearing the pointers, so a redo after an undo freed them again (an abort on macOS for Fill Series and every range-output analysis tool). Two `= NULL`. |
| `0004-solver-constant-bound.patch` | `gnm_solver_update_derived` lost a constraint's constant right-hand side (`cell_is_constant` zeroed it for the missing cell), so "A1 ≤ 3" bounded A1 by 0 and, with Assume Non-Negative, Gnumeric's own solver refused the problem as an equality; the program report asked `cell_name` for the same missing cell (a CRITICAL). Leave the value alone when there is no cell, and write the constant through `gnm_solver_constraint_side_as_str`. |
| `0005-frequency-histogram-bin-double-free.patch` | The frequency and histogram tools put their bin range into `gnm_expr_new_constant`, which takes the value over, and then released it again in `finalize`, a double free once the run is undone and the command leaves the redo list. Hand the expression a `value_dup`. |
| `0006-correlated-random-width.patch` | The correlated random generator referenced the uncorrelated row as three columns wide whatever the number of variables, so every correlated cell was `#VALUE!` unless the matrix was 3×3. Width from `rtool->variables`. |

Re-check each patch at every submodule re-pin (ADR-003).
