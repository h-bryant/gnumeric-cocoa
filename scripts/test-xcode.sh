#!/bin/bash
# Build the Xcode test bundle and run it.  `xcodebuild test` needs macOS
# developer mode (`sudo DevToolsSecurity -enable`, Henry's call) or its test
# runner times out while preparing; running the built bundle with xctest
# directly needs nothing (docs/build.md).
#   scripts/test-xcode.sh            # build-for-testing, then xctest
#   scripts/test-xcode.sh --xcodebuild   # the official way, once developer mode is on
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=env.sh
source scripts/env.sh
scripts/gen-xcconfig.sh >/dev/null
xcodegen generate >/dev/null
DD="$PWD/build/DerivedData"
if [ "${1:-}" = "--xcodebuild" ]; then
	exec xcodebuild test -scheme GnumericCocoa -derivedDataPath "$DD"
fi
xcodebuild build-for-testing -scheme GnumericCocoa -derivedDataPath "$DD" -quiet 2>&1 | grep -v "ld: warning" || true
BUNDLE="$DD/Build/Products/Debug/BridgeTests.xctest"
[ -d "$BUNDLE" ] || { echo "test bundle not built: $BUNDLE"; exit 1; }
GNM_REPO_ROOT="$PWD" GNM_PREFIX="$GNM_PREFIX" xcrun xctest "$BUNDLE" 2>&1 | grep -vE "^ld: warning|^Leaking string"
