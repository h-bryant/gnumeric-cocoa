#!/bin/bash
# Launch the development build directly (not via `open`) so stderr stays in
# the terminal and file arguments are opened by AppDelegate.
#   scripts/run-app.sh [file ...]
#   GNM_SNAPSHOT=/path/out.png scripts/run-app.sh file   # render and quit
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=env.sh
source scripts/env.sh
APP="$PWD/build/app/GnumericCocoa.app"
[ -x "$APP/Contents/MacOS/GnumericCocoa" ] || scripts/build-app.sh
exec "$APP/Contents/MacOS/GnumericCocoa" "$@"
