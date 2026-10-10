#!/bin/bash
# Build the Swift app with swiftc (no Xcode) into build/app/GnumericCocoa.app,
# linked against the clang-built bridge and the pkg-config engine.  The Xcode
# project (project.yml) is the intended build; this script exists so the app
# runs while Xcode.app is still not installed.
#   scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=env.sh
source scripts/env.sh
scripts/build-bridge.sh >/dev/null

APP="$PWD/build/app/GnumericCocoa.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# swiftc does not take -Wl, flags; rewrite pkg-config's framework syntax.
# shellcheck disable=SC2046
libs=($(pkg-config --libs libspreadsheet-1.12 cairo-quartz | sed 's/-Wl,-framework,/-framework /g'))
swiftc -swift-version 6 -module-name GnumericCocoa -g \
	-I "$PWD/Sources/Bridge/include" \
	Sources/App/*.swift \
	"$PWD/build/bridge/libGnmCocoa.a" "${libs[@]}" -framework Cocoa \
	-o "$APP/Contents/MacOS/GnumericCocoa"

cp Sources/App/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :GnmEnginePrefix string $GNM_PREFIX" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "built $APP"
