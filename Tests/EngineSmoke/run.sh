#!/bin/bash
# Build and run the engine smoke programs against whichever libspreadsheet
# pkg-config resolves first (build/prefix, then Homebrew's gnumeric keg).
#   Tests/EngineSmoke/run.sh [output-dir]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/../.."
# shellcheck source=../../scripts/env.sh
source scripts/env.sh
OUT="${1:-$PWD/build/smoke}"
mkdir -p "$OUT"
SAMPLES="$PWD/upstream/gnumeric/samples"

echo "libspreadsheet: $(pkg-config --modversion libspreadsheet-1.12) from $(pkg-config --variable=prefix libspreadsheet-1.12)"
# shellcheck disable=SC2046
for prog in headless render; do
	clang -Wall -Wno-deprecated-declarations -o "$OUT/$prog" "$HERE/$prog.c" \
		$(pkg-config --cflags --libs libspreadsheet-1.12 cairo-quartz)
done

cd "$OUT"
: > smoke-stderr.log
./headless "$SAMPLES/chart-tests.gnumeric" headless-out.gnumeric 2>>smoke-stderr.log
./render "$SAMPLES/chart-tests.gnumeric" render-out.gnumeric 2>>smoke-stderr.log
./render "$SAMPLES/excel12/cellstyle.xlsx" render-out.xlsx 2>>smoke-stderr.log
# Engine warnings mean something did not load (for example plot plugins).
if grep -qE "unknown type|CRITICAL|Unable to|failed to" smoke-stderr.log; then
	echo "engine warnings during smoke run (see $OUT/smoke-stderr.log):"
	grep -E "unknown type|CRITICAL|Unable to|failed to" smoke-stderr.log | sort | uniq -c | head
	exit 1
fi
for f in cells-image.png cells-quartz.png chart-image.png chart-quartz.png headless-out.gnumeric render-out.gnumeric render-out.xlsx; do
	[ -s "$f" ] || { echo "missing output: $f"; exit 1; }
done
echo "engine smoke programs OK (outputs in $OUT)"
