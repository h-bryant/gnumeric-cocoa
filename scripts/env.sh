#!/bin/bash
# Source this file; do not execute it.  It sets the environment for building
# Gnumeric and the bridge against Homebrew libraries.  Nothing here belongs in
# a shell profile (HANDOFF.md §4, Phase 0 step 2).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT
export HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
# Where scripts/build-gnumeric.sh installs the submodule build.
export GNM_PREFIX="${GNM_PREFIX:-$REPO_ROOT/build/prefix}"

# pkg-config: our own prefix first, then Homebrew, then keg-only formulae whose
# .pc files are not linked into $HOMEBREW_PREFIX/lib/pkgconfig (libxml2, zlib),
# then Homebrew's gnumeric keg so libspreadsheet-1.12.pc resolves before the
# submodule build exists.
export PKG_CONFIG_PATH="$GNM_PREFIX/lib/pkgconfig:$HOMEBREW_PREFIX/lib/pkgconfig:$HOMEBREW_PREFIX/opt/libxml2/lib/pkgconfig:$HOMEBREW_PREFIX/opt/zlib/lib/pkgconfig:$HOMEBREW_PREFIX/opt/gnumeric/lib/pkgconfig"

# autotools macro directories (glib-2.0.m4, gsettings.m4, nls.m4, pkg.m4, ...).
export ACLOCAL_PATH="$HOMEBREW_PREFIX/share/aclocal:$HOMEBREW_PREFIX/opt/gettext/share/aclocal"

# Prefer Homebrew tools; Homebrew bison is keg-only so it only wins if installed.
export PATH="$HOMEBREW_PREFIX/opt/bison/bin:$HOMEBREW_PREFIX/opt/gettext/bin:$HOMEBREW_PREFIX/bin:$PATH"

export CPPFLAGS="-I$HOMEBREW_PREFIX/include ${CPPFLAGS:-}"
export LDFLAGS="-L$HOMEBREW_PREFIX/lib ${LDFLAGS:-}"

# The engine must never see a display during builds and tests.
unset DISPLAY
