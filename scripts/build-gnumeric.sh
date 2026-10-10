#!/bin/bash
# Build Gnumeric from upstream/gnumeric against the Homebrew libraries and
# install it under build/prefix.  The submodule is never touched: it is copied
# to build/src/gnumeric, patched there, and built out of tree in
# build/obj/gnumeric.  Extra arguments are passed to configure.
#
# Requires the build tools from Brewfile (see docs/build.md).
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=env.sh
source scripts/env.sh
ROOT="$PWD"
SRC="$ROOT/build/src/gnumeric"
OBJ="$ROOT/build/obj/gnumeric"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"

for t in autoreconf aclocal glibtoolize intltoolize gtkdocize glib-gettextize itstool bison pkg-config; do
	command -v "$t" >/dev/null || { echo "missing build tool: $t (run scripts/build-deps.sh)"; exit 1; }
done

mkdir -p "$SRC" "$OBJ"
rsync -a --delete --exclude .git "$ROOT/upstream/gnumeric/" "$SRC/"
scripts/apply-patches.sh "$SRC"

( cd "$SRC" && NOCONFIGURE=1 ./autogen.sh )

# Flags mirror Homebrew's gnumeric formula (--disable-schemas-compile,
# --disable-silent-rules, --disable-dependency-tracking) plus what the app
# does not need: the goffice embedding component, GObject introspection,
# API docs, and the Perl and Python plugin loaders.
( cd "$OBJ" && "$SRC/configure" \
	--prefix="$GNM_PREFIX" \
	--disable-dependency-tracking \
	--disable-silent-rules \
	--disable-schemas-compile \
	--disable-component \
	--disable-introspection \
	--disable-gtk-doc \
	--without-python \
	--without-perl \
	"$@" )

make -C "$OBJ" -j"$JOBS"
make -C "$OBJ" install
glib-compile-schemas "$GNM_PREFIX/share/glib-2.0/schemas"

echo "installed to $GNM_PREFIX"
"$GNM_PREFIX/bin/ssconvert" --version
