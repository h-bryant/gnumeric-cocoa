#!/bin/bash
# Engine smoke suite (HANDOFF.md §5): open, recalc, and convert a fixed set of
# upstream sample workbooks headless with ssconvert, then build and run the two
# C programs in Tests/EngineSmoke.  Run after every dependency change.
#
# Uses build/prefix/bin/ssconvert when the submodule build exists, otherwise
# Homebrew's.  Override with SSCONVERT=/path/to/ssconvert.
set -uo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=env.sh
source scripts/env.sh
SSCONVERT="${SSCONVERT:-$GNM_PREFIX/bin/ssconvert}"
[ -x "$SSCONVERT" ] || SSCONVERT="$HOMEBREW_PREFIX/bin/ssconvert"
OUT="$PWD/build/smoke"
rm -rf "$OUT"; mkdir -p "$OUT"
SAMPLES="$PWD/upstream/gnumeric/samples"
fail=0

echo "== ssconvert: $SSCONVERT ($("$SSCONVERT" --version 2>&1 | head -1))"
for f in chart-tests.gnumeric format-tests.gnumeric formula-tests.gnumeric cond-format-tests.gnumeric excel12/cellstyle.xlsx; do
	base="$(basename "${f%.*}")"
	for ext in gnumeric xlsx csv; do
		if "$SSCONVERT" --recalc "$SAMPLES/$f" "$OUT/$base.$ext" >"$OUT/$base.$ext.log" 2>&1; then
			printf 'ok   %-28s -> %s\n' "$f" "$ext"
		else
			printf 'FAIL %-28s -> %s  (see %s)\n' "$f" "$ext" "$OUT/$base.$ext.log"; fail=1
		fi
	done
done

echo "== engine smoke programs"
Tests/EngineSmoke/run.sh "$OUT" || fail=1

[ $fail -eq 0 ] && echo "SMOKE OK" || echo "SMOKE FAILED"
exit $fail
