# Patches

Patches to upstream Gnumeric, applied by `scripts/apply-patches.sh` to a copy of
`upstream/gnumeric` (never to the submodule). Name them `NNNN-description.patch`
and start each with a comment header saying why it exists and where it came from.
Keep every patch minimal and in the form upstream could accept: engagement is
deferred, not ruled out (`docs/decisions.md` ADR-011).

| Patch | Why |
|---|---|
| `0001-decouple-command-dialogs-from-wbcgtk.patch` | The seven command-layer sites that cast to `WBCGtk` (`docs/architecture.md` §5) go through the control's command context and a new `query_yes_no` vtable slot, so a Cocoa control survives Phase 2 editing. GTK behavior unchanged. |

Re-check each patch at every submodule re-pin (ADR-003).
