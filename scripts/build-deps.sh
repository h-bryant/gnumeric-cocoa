#!/bin/bash
# Install the Homebrew dependencies listed in Brewfile and report what is
# present.  This installs software system-wide, so Henry runs it himself
# (HANDOFF.md §1).  Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."
brew bundle --file=Brewfile
# shellcheck source=env.sh
source scripts/env.sh

echo "== build tools"
for t in autoreconf aclocal glibtoolize intltoolize itstool gtkdocize yelp-build glib-gettextize pkg-config bison flex make clang swiftc xcodegen; do
	printf '%-16s %s\n' "$t" "$(command -v "$t" || echo MISSING)"
done
echo "== pkg-config modules"
for p in libgoffice-0.10 libgsf-1 gtk+-3.0 gdk-quartz-3.0 cairo cairo-quartz pangocairo glib-2.0 gmodule-2.0 libxml-2.0 librsvg-2.0; do
	printf '%-18s %s\n' "$p" "$(pkg-config --modversion "$p" 2>/dev/null || echo MISSING)"
done
echo "== Homebrew versions"
brew list --versions gnumeric goffice glib gtk+3 cairo pango libgsf libxml2 librsvg gettext harfbuzz \
	autoconf automake libtool pkgconf intltool itstool gtk-doc yelp-tools xcodegen 2>/dev/null || true
echo "== Pango backend"
if nm -gU "$HOMEBREW_PREFIX/lib/libpangocairo-1.0.dylib" | grep -q pango_cairo_core_text_font_map_get_type; then
	echo "pangocairo has the CoreText backend"
else
	echo "WARNING: pangocairo lacks the CoreText backend"
fi
