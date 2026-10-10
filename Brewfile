# Homebrew dependencies for gnumeric-cocoa.  Install with:  brew bundle
# Henry installs these himself (see HANDOFF.md §1); scripts never run brew.

# Runtime and build libraries: installing the gnumeric formula pulls the exact
# dependency set upstream needs (goffice, gtk+3, glib, cairo, pango, libgsf,
# libxml2, librsvg, gettext, harfbuzz, ...), and leaves a reference ssconvert
# and libspreadsheet-1.12.pc for prototyping against the Homebrew engine.
brew "gnumeric"

# Build tools needed to run upstream/gnumeric/autogen.sh and configure.
brew "autoconf"
brew "automake"
brew "libtool"
brew "pkgconf"
brew "intltool"
brew "itstool"
brew "gtk-doc"      # provides gtkdocize, which autogen.sh requires
brew "yelp-tools"   # provides yelp.m4 for YELP_HELP_INIT in configure.ac
# bison: macOS ships bison 2.3, which upstream's Homebrew formula uses as-is.

# App build (Phase 1).
brew "xcodegen"

# Packaging (Phase 6), not needed yet:
# brew "dylibbundler"
