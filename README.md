# gnumeric-cocoa

Gnumeric with a native macOS (AppKit) front end: the upstream C engine
(`libspreadsheet`, goffice, libgsf) unchanged, the GTK user interface replaced.

Status (2026-10-12): MVP `v0.1.0` plus Phase 3. The app opens every
format the engine reads, edits with the engine's undo and clipboard, formats
cells, resizes, fills, sorts, filters, freezes panes, manages sheets, and
saves `.gnumeric`, `.xml`, and `.xlsx`. See `HANDOFF.md` for goals, decisions, the
phase plan, and where to pick up; `docs/mvp-known-gaps.md` for what is
missing; `docs/build.md` for how to build.
