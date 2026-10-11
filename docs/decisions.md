# Decisions

ADR format: context, decision, consequences. Decisions inherited from
`HANDOFF.md` §2 are not repeated here.

## ADR-001 (2026-10-10): Build the engine from a copy of the submodule

Context: `HANDOFF.md` §6 forbids editing inside the submodule, but
`autogen.sh` writes generated files into the source tree and patches must be
applied somewhere.

Decision: `scripts/build-gnumeric.sh` rsyncs `upstream/gnumeric` to
`build/src/gnumeric`, applies `patches/*.patch` there, runs `autogen.sh` there,
and configures out of tree in `build/obj/gnumeric` with `--prefix` set to
`build/prefix`.

Consequences: the submodule always stays clean; rebuilding from scratch is
`rm -rf build`. The copy costs about 140 MB of disk.

## ADR-002 (2026-10-10): Prototype the bridge against Homebrew's libspreadsheet

Context: Homebrew's `gnumeric` keg installs the engine headers,
`libspreadsheet-1.12.60.dylib`, and `libspreadsheet-1.12.pc`. The submodule
build is blocked until the autotools formulae are installed.

Decision: until `build/prefix` exists, bridge code and the smoke programs are
compiled with `pkg-config libspreadsheet-1.12` resolving to the Homebrew keg;
`scripts/env.sh` orders `PKG_CONFIG_PATH` so that `build/prefix` wins once it
exists.

Consequences: no work is blocked on the build tools; the switch to the
submodule build is a `PKG_CONFIG_PATH` change. Patches to the engine (§5 of
`docs/architecture.md`) cannot be exercised until the submodule build exists.

## ADR-003 (2026-10-10): Submodule pinned to Homebrew's current goffice pairing

Context: Homebrew's formulae had moved to goffice 0.10.62 / gnumeric 1.12.62
while this machine had 0.10.60 / 1.12.60 installed. Staying would have meant
carrying a patch for 1.12.60 and later absorbing the 1.12.61 GObject refactor
of the analysis tools in the middle of Phase 5.

Decision (Henry, 2026-10-10): upgrade Homebrew's goffice and gnumeric and pin
the submodule to `GNUMERIC_1_12_62`. The pairing rule stays: the submodule tag
tracks the goffice version Homebrew installs.

Consequences: `patches/` is empty; all line references in
`docs/architecture.md` and `docs/upstream-issue.md` are for 1.12.62. When
Homebrew moves goffice again, re-pin, re-run `scripts/smoke-test.sh`, and
re-check the cited lines.

## ADR-004 (2026-10-10): clang and swiftc builds until Xcode.app exists

Context: `HANDOFF.md` chooses Xcode with an XcodeGen project, but Xcode.app
was not installed during the session that wrote the bridge and the viewer,
and the Command Line Tools have no XCTest.

Decision: `project.yml` stays the intended build. In parallel,
`scripts/build-bridge.sh` and `scripts/build-app.sh` build the same sources
with clang and swiftc from pkg-config flags, and `Tests/BridgeTests` are plain
Objective-C programs run by `Tests/BridgeTests/run.sh`, each written so its
body can move into an XCTestCase method unchanged.

Consequences: no work waited on Xcode; the scripts remain useful as a
CI-without-Xcode path. `scripts/gen-xcconfig.sh` keeps the Xcode project on
the same pkg-config results. Once Xcode is present, the XCTest targets wrap
the existing tests and `xcodebuild` becomes the gate.

## ADR-005 (2026-10-10): GLib main context driven from the CFRunLoop

Context: the engine schedules idles and timeouts and GIO completes file
operations on worker threads that wake the default `GMainContext`; AppKit
owns the main loop, so `g_main_loop_run` is not an option.

Decision: `GnmRunLoopBridge` ports the "CFRunLoop is in control" half of
GTK's `gdk/quartz/gdkeventloop-quartz.c`: a run-loop observer runs
prepare/query/check/dispatch per cycle (high-priority sources before
AppKit's sources, the rest before and after waiting), a `CFRunLoopTimer`
carries GLib's timeout, and a poll thread blocks on GLib's descriptors and
signals a `CFRunLoopSource`. It is attached once per process by
`GnmEngine.start` (configurable).

Consequences: GLib work runs on the main thread only, interleaved with
events, also during tracking loops and modal panels (common modes). The
reverse direction (GLib driving Cocoa) is not implemented and not needed.
Verified by `Tests/BridgeTests/runloop.m`.

## ADR-006 (2026-10-10): Engine object ownership in the bridge

Context: upstream's ownership is circular on purpose: a `WorkbookView` holds
a reference to its `Workbook`, the workbook's dispose releases its views,
views release their attached controls, and a `SheetView`'s dispose releases
attached `SheetControl`s (`workbook.c`, `workbook-view.c`, `sheet-view.c`).

Decision: `GnmWorkbook` keeps the view reference the opener returns and
ends everything with one `g_object_unref` of the `Workbook`, exactly as
ssconvert and `wbcg_close_if_user_permits` do. `GnmSheet` creates its
`SheetControl`, attaches it, and detaches and releases it on `sheet.remove`,
`sheet.remove_all`, or its own deallocation; the control's finalizer clears
the wrapper's pointer if the view got there first. Every GObject carries an
unretained back-pointer to its wrapper, cleared before the wrapper goes away.
`GnmEngine.shutdown` refuses while any wrapper is alive.

Consequences: no leaks or double frees in the tests; callers must release
workbooks (and drain autorelease pools) before shutting the engine down,
which the app does by closing documents in `applicationWillTerminate`.

## ADR-007 (2026-10-10): Drawing contract between the bridge and the grid view

Context: cell drawing must come from the engine (`cell_draw`, border and
pattern code, `sheet_object_draw_cairo_sized`) for fidelity, while selection
and headers should look native.

Decision: `GnmSheet` draws into the caller's `CGContext` through a
cairo-quartz surface created per call; the context's CTM maps sheet pixels
(the engine's own coordinates at the sheet zoom) to the destination with y
downward, and the backing scale stays in the CTM, as a flipped `NSView`'s
context already provides. The grid view is a plain flipped `NSView` whose
coordinates are sheet pixels; it paints the selection and the edit cursor
with AppKit colors after the engine has drawn; headers are `NSRulerView`
subclasses that only ask the bridge for sizes and names.

Consequences: HiDPI needs nothing from the engine (verified at 2x);
rendering tests can use flipped `CGBitmapContext`s; selection highlighting
through the engine's `is_selected` path (which needs a `GtkStyleContext`) is
bypassed. The grid view is not layer-backed for now because
`cacheDisplay(in:to:)`, used for snapshots and future golden images, skips
layer content; revisit if scrolling performance needs it.

## ADR-008 (2026-10-10): Development builds do not persist preferences

Superseded by ADR-010 the same day, once Henry confirmed the identifier.

Context: GSettings on macOS writes to `NSUserDefaults` under the bundle
identifier, and the identifier (`org.gnumeric.cocoa` in `Info.plist`) has
not been confirmed by Henry (`HANDOFF.md` §8 question 5). Writing outside
the repository needs his approval (`HANDOFF.md` §1).

Decision: `AppDelegate` starts the engine with persistence off unless
`GNM_PERSIST_PREFS=1` is set; `GnmEngine.shutdown` stores the active plugin
list when persistence is on, so turning it on later is safe.

Consequences: preferences changes are lost between launches in development;
no `~/Library/Preferences/org.gnumeric.cocoa.plist` is created yet.

## ADR-009 (2026-10-10): Minimum macOS follows Homebrew's oldest supported release

Context: `HANDOFF.md` §2 chose macOS 14. Every Homebrew dylib on the build
machine carries a minimum OS of 26.0 (bottles target the OS they were built
on), Homebrew's oldest supported release is now 15, and no macOS 14 machine
exists for testing. A direct-download bundle needs libraries built for the
product's minimum either way.

Decision (Henry, 2026-10-10): the minimum macOS is Homebrew's oldest
supported release at the time of each release; 15.0 today, set in
`project.yml` (`MACOSX_DEPLOYMENT_TARGET`) and `Info.plist`
(`LSMinimumSystemVersion`). The clang/swiftc development scripts pass no
deployment flag because they link the host's bottles.

Consequences: APIs newer than the floor need `#available` guards. Phase 6 can
assemble the bundle from Homebrew's own bottles for the floor release (for
example the `arm64_sequoia` bottle tag) instead of rebuilding the stack from
source, though the Intel and universal question stays open there. When
Homebrew drops a release, the next version of this app may drop it too.

## ADR-010 (2026-10-10): Bundle identifier and preferences domain

Context: the identifier names the app to Launch Services and code signing and
is the NSUserDefaults domain GSettings writes to (GNextstepSettingsBackend),
so it should be chosen once. `org.gnumeric.cocoa` was a placeholder in
upstream's namespace (upstream uses `org.gnumeric.gnumeric` for its desktop
and appdata ids, `org.gnome.gnumeric` for its schemas), and the project is not
presented as official.

Decision (Henry, 2026-10-10): `io.github.h-bryant.gnumeric-cocoa`, the
reverse-DNS form of the GitHub repository. Preference persistence is on by
default; `GNM_PERSIST_PREFS=0` turns it off for a run, and the bridge tests
always run without it.

Consequences: preferences live in
`~/Library/Preferences/io.github.h-bryant.gnumeric-cocoa.plist`, separate from
the GTK build's `gnumeric.plist`. `GnmEngine.shutdown` stores the active
plugin list so later launches keep their plugins (docs/architecture.md §2).
Renaming later would orphan that file and any "Open With" defaults; if
upstream adopts the port, that rename happens with the adopting release.

## ADR-011 (2026-10-11): Upstream engagement deferred; the port stays self-contained

Context: `HANDOFF.md` §2 planned a GNOME GitLab issue after Phase 0 asking
whether decoupling patches (the seven `WBCGtk` sites in
`docs/architecture.md` §5) would be accepted. The draft exists
(`docs/upstream-issue.md`). Waiting on, or shaping work around, upstream
review would slow the port down.

Decision (Henry, 2026-10-11): proceed without depending on any upstream
change. The draft is not posted. Engine changes the port cannot avoid are
carried in `patches/` (applied by `scripts/build-gnumeric.sh` to the build
copy, never to the submodule), kept minimal, each with a header explaining
why, and written in the form upstream would accept, so that nothing has to
be redone if engagement resumes. The annotated git tag
`upstream-baseline-2026-10-11` marks the repository at this decision.

Consequences: Phase 2 needs those patches before `cmd_insert_cols`,
`cmd_insert_rows`, `cmd_paste_copy`, `cmd_selection_colrow_hide`,
`cmd_shift_rows`, `cmd_shift_cols`, and the `undo.c` filter case can be
reached from a Cocoa control; the patch series must be re-applied and
re-checked at every submodule re-pin (ADR-003). To resume upstream work
later: `git show upstream-baseline-2026-10-11`, re-check the line numbers
in `docs/upstream-issue.md` and `docs/architecture.md` §5 against the pinned
tag, fold the accumulated `patches/` into the request, and post.
