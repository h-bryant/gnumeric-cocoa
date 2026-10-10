#!/bin/bash
# Compile the Objective-C bridge (Sources/Bridge) into build/bridge/libGnmCocoa.a
# with clang and pkg-config, without Xcode.  Flags mirror what project.yml
# gives the Xcode target; scripts/gen-xcconfig.sh writes the same pkg-config
# results into build/engine.xcconfig for XcodeGen.
#   scripts/build-bridge.sh            # build
#   scripts/build-bridge.sh --flags    # print the compile flags only
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=env.sh
source scripts/env.sh
OUT="$PWD/build/bridge"
PKGS="libspreadsheet-1.12 cairo-quartz"

# shellcheck disable=SC2046
cflags=(-I "$PWD/Sources/Bridge/include" $(pkg-config --cflags $PKGS) \
	-fobjc-arc -fobjc-weak -Wall -Wno-deprecated-declarations -Wno-unused-function -g)
# No -mmacosx-version-min: Homebrew bottles are built for the running macOS,
# and a lower target only produces linker warnings (HANDOFF.md §8, question 4).
if [ "${1:-}" = "--flags" ]; then
	printf '%s\n' "${cflags[@]}"
	exit 0
fi

mkdir -p "$OUT/obj"
objs=()
for src in Sources/Bridge/*.m; do
	obj="$OUT/obj/$(basename "${src%.m}").o"
	clang "${cflags[@]}" -c "$src" -o "$obj"
	objs+=("$obj")
done
rm -f "$OUT/libGnmCocoa.a"
libtool -static -o "$OUT/libGnmCocoa.a" "${objs[@]}" 2>&1 | grep -v "has no symbols" || true
echo "built $OUT/libGnmCocoa.a"
