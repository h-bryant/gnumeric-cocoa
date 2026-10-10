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
