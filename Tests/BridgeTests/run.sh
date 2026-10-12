#!/bin/bash
# Build the bridge, then compile and run each test program in this directory
# against it.  Needs no Xcode: clang, Foundation, and pkg-config suffice.
#   Tests/BridgeTests/run.sh [output-dir]
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/../.."
# shellcheck source=../../scripts/env.sh
source scripts/env.sh
OUT="${1:-$PWD/build/bridge-tests}"
mkdir -p "$OUT"

scripts/build-bridge.sh >/dev/null || { echo "bridge build failed"; exit 1; }
cflags=()
while IFS= read -r line; do cflags+=("$line"); done < <(scripts/build-bridge.sh --flags)
# shellcheck disable=SC2046
# -ObjC: the bridge's categories (GnmWorkbook (Names) and the like) live in
# their own object files, which a static link drops unless told otherwise.
libs=($(pkg-config --libs libspreadsheet-1.12 cairo-quartz) -ObjC -framework Foundation -framework AppKit -framework CoreGraphics -framework ImageIO -framework CoreServices)

export GNM_TEST_SCHEMA_DIR="$(pkg-config --variable=prefix libspreadsheet-1.12)/share/glib-2.0/schemas"
[ -f "$GNM_TEST_SCHEMA_DIR/gschemas.compiled" ] || export GNM_TEST_SCHEMA_DIR="$HOMEBREW_PREFIX/share/glib-2.0/schemas"
export GNM_TEST_SAMPLES="$PWD/upstream/gnumeric/samples"
export GNM_TEST_OUT="$OUT"

fail=0
for src in "$HERE"/*.m; do
	name="$(basename "${src%.m}")"
	if ! clang "${cflags[@]}" "$src" "$PWD/build/bridge/libGnmCocoa.a" "${libs[@]}" -o "$OUT/$name" 2>"$OUT/$name.build.log"; then
		echo "FAIL $name (compile; see $OUT/$name.build.log)"; fail=1; continue
	fi
	if (cd "$OUT" && "./$name" >"$OUT/$name.log" 2>&1); then
		echo "ok   $name"
	else
		echo "FAIL $name (see $OUT/$name.log)"; tail -20 "$OUT/$name.log"; fail=1
	fi
	# Engine warnings mean a plugin or schema did not load.
	if grep -qE "unknown type|CRITICAL|Unable to|failed to" "$OUT/$name.log"; then
		echo "FAIL $name (engine warnings in $OUT/$name.log)"; grep -E "unknown type|CRITICAL|Unable to|failed to" "$OUT/$name.log" | head -5; fail=1
	fi
done
[ $fail -eq 0 ] && echo "bridge tests OK (outputs in $OUT)"
exit $fail
