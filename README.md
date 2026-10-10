# gnumeric-cocoa

Gnumeric with a native macOS (AppKit) front end: the upstream C engine
(`libspreadsheet`, goffice, libgsf) unchanged, the GTK user interface replaced.

Status (2026-10-10): Phase 1 in progress. The Objective-C bridge and a Swift
read-only viewer build and open `.gnumeric`, `.xlsx`, and the other formats
the engine reads. See `HANDOFF.md` for goals, decisions, and the phase plan,
and `docs/build.md` for how to build.
