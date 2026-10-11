# gnumeric-cocoa

Read `HANDOFF.md` first: it holds the goals, decisions, phase plan, conventions,
and the open questions that need Henry's answer. `docs/progress.md` says where
the last session stopped; `docs/architecture.md` has the verified engine facts.

Rules that matter most (from `HANDOFF.md` §1 and §6):

- Ask Henry before any `brew` install or upgrade, any `sudo`, any change
  outside this repository, code signing with real credentials, or `git push`.
- Never edit `upstream/gnumeric`; put changes in `patches/`.
- All engine access is main-thread only; Swift never sees a GObject pointer.

Commands:

```sh
source scripts/env.sh            # build environment (Homebrew paths); bash, not zsh
scripts/build-deps.sh            # Henry runs: brew bundle + report
scripts/build-gnumeric.sh        # engine from the submodule into build/prefix
scripts/smoke-test.sh            # ssconvert + engine smoke programs + bridge tests
Tests/EngineSmoke/run.sh         # just the C smoke programs
scripts/build-bridge.sh          # Objective-C bridge with clang (no Xcode needed)
Tests/BridgeTests/run.sh         # just the bridge tests
scripts/build-app.sh             # Swift app with swiftc into build/app/GnumericCocoa.app
scripts/run-app.sh [file]        # launch it; GNM_SNAPSHOT=out.png renders grid + window and quits
scripts/gen-xcconfig.sh && xcodegen generate   # regenerate the Xcode project
xcodebuild -scheme GnumericCocoa -derivedDataPath build/DerivedData build
scripts/test-xcode.sh            # XCTest bundle via xcrun xctest (xcodebuild test needs developer mode)
```

Bridge rules: public headers under `Sources/Bridge/include/GnmCocoa/` never
include engine headers; `NS_SWIFT_NAME` on every method; every workbook must be
released before `GnmEngine.shutdown`. The scripts source `scripts/env.sh` with
bash; sourcing it from zsh computes the wrong repository root.

Grep `upstream/gnumeric/src/ssconvert.c`, `main-application.c`, and `style.c`
with `LC_ALL=C`; they are Latin-1 encoded.
