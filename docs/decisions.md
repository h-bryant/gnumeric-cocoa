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

## ADR-003 (2026-10-10): Submodule pinned to the installed goffice pairing

Context: Homebrew's formulae moved to goffice 0.10.62 / gnumeric 1.12.62, but
this machine has 0.10.60 / 1.12.60 installed. Upgrading is a system-wide
change that Henry decides (HANDOFF.md §1).

Decision: pin to `GNUMERIC_1_12_60` now. Re-pin to `GNUMERIC_1_12_62` and drop
`patches/0001-*.patch` if Henry upgrades (HANDOFF.md §8, question 2).

Consequences: the API the bridge targets is 1.12.60; the 1.12.61 refactor of
the analysis tools to GObject (upstream NEWS) will affect Phase 5 if the pin
moves, so it should move before Phase 5 at the latest.
