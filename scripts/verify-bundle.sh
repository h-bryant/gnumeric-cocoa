#!/bin/bash
# Make the bundle and run it headlessly with build/prefix hidden, so the
# engine, the plugins, the templates, and the image loaders must all come
# from inside the .app (GNM_SNAPSHOT_BUNDLE=1 logs what it found).
#   scripts/verify-bundle.sh
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/bundle.sh
DIST="$PWD/build/dist/GnumericCocoa.app"
out="$PWD/build/dist/bundle-check"
mkdir -p "$out"
hidden="$PWD/build/prefix.hidden"
mv "$PWD/build/prefix" "$hidden"
trap 'mv "$hidden" "$PWD/build/prefix"' EXIT
env -u GNM_PREFIX GNM_PERSIST_PREFS=0 GNM_SNAPSHOT="$out/bundle.png" GNM_SNAPSHOT_BUNDLE=1 \
	"$DIST/Contents/MacOS/GnumericCocoa" > "$out/bundle.log" 2>&1 &
pid=$!
for _ in $(seq 1 60); do sleep 1; kill -0 "$pid" 2>/dev/null || break; done
if kill -0 "$pid" 2>/dev/null; then echo "STILL RUNNING"; kill "$pid"; fi
grep -o "bundle: .*\|help: .*\|Gnumeric error.*\|CRITICAL.*" "$out/bundle.log" | cut -c1-240
ls -la "$out/bundle.png" 2>/dev/null | awk '{print $5, $9}'
