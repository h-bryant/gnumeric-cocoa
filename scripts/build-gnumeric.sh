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
# autogen.sh derives po-functions/Makefile.in.in from po/Makefile.in.in.own
# with a sed script whose alternation `\(GETTEXT_PACKAGE\|subdir\)` is a GNU
# extension: BSD sed matches nothing, the functions' domain stays plain
# @GETTEXT_PACKAGE@, and their catalogs install over the engine's (same
# file name).  Name the domain the engine binds, GETTEXT_PACKAGE
# "-functions" (libgnumeric.c), and the subdir, as upstream's sed meant to.
sed -i '' -e 's/^GETTEXT_PACKAGE = @GETTEXT_PACKAGE@$/GETTEXT_PACKAGE = @GETTEXT_PACKAGE@-functions/' \
	-e 's/^subdir = po$/subdir = po-functions/' "$SRC/po-functions/Makefile.in.in"

# Flags mirror Homebrew's gnumeric formula (--disable-schemas-compile,
# --disable-silent-rules, --disable-dependency-tracking) plus what the app
# does not need: the goffice embedding component, GObject introspection,
# API docs, and the Perl and Python plugin loaders.
#
# The translations: the gettext test program in upstream's m4/ declares
# `_nl_expand_alias ()` K&R style and calls it with an argument, which the
# C23 mode autoconf 2.72 picks rejects, so configure concludes "no GNU
# gettext in libintl" and leaves USE_NLS=no (no catalogs built or
# installed).  The engine links Homebrew's libintl anyway, through glib;
# the cache variable states the fact and the prefix names the library.
( cd "$OBJ" && gt_cv_func_gnugettext1_libintl=yes "$SRC/configure" \
	--prefix="$GNM_PREFIX" \
	--with-libintl-prefix="$HOMEBREW_PREFIX/opt/gettext" \
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
