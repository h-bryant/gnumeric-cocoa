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
source scripts/env.sh            # build environment (Homebrew paths)
scripts/build-deps.sh            # Henry runs: brew bundle + report
scripts/build-gnumeric.sh        # engine from the submodule into build/prefix
scripts/smoke-test.sh            # ssconvert + engine smoke programs
Tests/EngineSmoke/run.sh         # just the C smoke programs
```

Grep `upstream/gnumeric/src/ssconvert.c`, `main-application.c`, and `style.c`
with `LC_ALL=C`; they are Latin-1 encoded.
