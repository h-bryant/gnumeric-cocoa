#!/bin/bash
# Make a relocatable application bundle from the development build:
# build/dist/GnumericCocoa.app carries the engine, every dylib it needs,
# the Gnumeric and goffice plugins, the autoformat templates, the GSettings
# schemas, and the gdk-pixbuf loaders, with every load command rewritten to
# @rpath and everything ad-hoc signed.  No Homebrew tool beyond those the
# engine build needs; install_name_tool and codesign are Apple's.
#   scripts/bundle.sh
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=env.sh
source scripts/env.sh
APP="$PWD/build/app/GnumericCocoa.app"
[ -x "$APP/Contents/MacOS/GnumericCocoa" ] || scripts/build-app.sh
DIST="$PWD/build/dist/GnumericCocoa.app"
rm -rf "$DIST"
mkdir -p "$PWD/build/dist"
cp -R "$APP" "$DIST"
RES="$DIST/Contents/Resources"
FW="$DIST/Contents/Frameworks"
mkdir -p "$FW"
/usr/libexec/PlistBuddy -c "Delete :GnmEnginePrefix" "$DIST/Contents/Info.plist" 2>/dev/null || true

# The engine's directories (patch 0010 lets the app name them).
version=$(pkg-config --modversion libspreadsheet-1.12)
mkdir -p "$RES/gnumeric/lib" "$RES/gnumeric/share" "$RES/glib-2.0"
cp -RL "$GNM_PREFIX/lib/gnumeric/$version/plugins" "$RES/gnumeric/lib/plugins"
cp -R "$GNM_PREFIX/share/gnumeric/$version/." "$RES/gnumeric/share/"
cp -R "$GNM_PREFIX/share/glib-2.0/schemas" "$RES/glib-2.0/schemas"
[ -d "$GNM_PREFIX/share/locale" ] && cp -R "$GNM_PREFIX/share/locale" "$RES/gnumeric/locale"
goffice_plugins="$(pkg-config --variable=libdir libgoffice-0.10)/goffice/$(pkg-config --modversion libgoffice-0.10)/plugins"
mkdir -p "$RES/goffice"
cp -RL "$goffice_plugins" "$RES/goffice/plugins"   # Homebrew links into the Cellar
# gdk-pixbuf loaders, their cache naming them relative to the module dir
loaders="$(pkg-config --variable=gdk_pixbuf_moduledir gdk-pixbuf-2.0)"
mkdir -p "$RES/gdk-pixbuf"
cp -RL "$loaders" "$RES/gdk-pixbuf/loaders"
rm -f "$RES"/gdk-pixbuf/loaders/*.dylib
(cd "$RES/gdk-pixbuf/loaders" && gdk-pixbuf-query-loaders ./*.so 2>/dev/null | sed 's#"\./#"#') > "$RES/gdk-pixbuf/loaders.cache"
# libtool leftovers are of no use in a bundle
find "$RES" -name "*.la" -delete

# The dylib closure, copied and rewritten to @rpath.
python3 - "$DIST" "$(brew --prefix 2>/dev/null || echo /opt/homebrew)" <<'PY'
import os, subprocess, sys, glob, shutil
dist, brew = sys.argv[1], sys.argv[2]
fw = os.path.join(dist, "Contents/Frameworks")
binary = os.path.join(dist, "Contents/MacOS/GnumericCocoa")
plugins = glob.glob(os.path.join(dist, "Contents/Resources/**/*.so"), recursive=True)

def load_commands(path):
    out = subprocess.run(["otool", "-L", path], capture_output=True, text=True).stdout.splitlines()[1:]
    return [l.split()[0] for l in out if l.strip()]

def is_system(dep):
    return dep.startswith(("/usr/lib/", "/System/"))

def resolve(dep, referrer):
    """The file a load command names, for an absolute path or an @rpath,
    @loader_path, or @executable_path name (Homebrew's brotli and friends
    refer to their siblings so): beside the referrer, in its ../lib, or in
    Homebrew's lib."""
    if dep.startswith("/"):
        return dep if os.path.exists(dep) else None
    name = dep.split("/", 1)[1] if "/" in dep else dep
    here = os.path.dirname(os.path.realpath(referrer))
    for candidate in (os.path.join(here, name), os.path.join(here, "..", "lib", name), os.path.join(brew, "lib", name)):
        if os.path.exists(candidate):
            return candidate
    return None

# 1. collect the closure: realpath basename -> source, and each image's rewrites
copied = {}
changes = {}   # source image path -> [(dep, new name)]
stack = [binary] + plugins
seen_images = set()
while stack:
    item = stack.pop()
    if item in seen_images:
        continue
    seen_images.add(item)
    rewrites = []
    for dep in load_commands(item):
        if is_system(dep) or os.path.basename(dep) == os.path.basename(item):
            continue   # a system library, or the image's own install name
        found = resolve(dep, item)
        if not found:
            print("unresolved reference:", item, "->", dep)
            sys.exit(1)
        real = os.path.realpath(found)
        name = os.path.basename(real)
        if name not in copied:
            copied[name] = real
            stack.append(real)
        if dep != "@rpath/" + name:
            rewrites.append((dep, "@rpath/" + name))
    changes[item] = rewrites
for name, src in copied.items():
    dst = os.path.join(fw, name)
    shutil.copy2(src, dst)
    os.chmod(dst, 0o755)

# 2. rewrite every Mach-O in the bundle: ids, references, run paths
def rewrite(path, source, rpaths, is_dylib):
    args = ["install_name_tool"]
    if is_dylib:
        args += ["-id", "@rpath/" + os.path.basename(path)]
    for dep, new in changes.get(source, []):
        args += ["-change", dep, new]
    for rp in rpaths:
        args += ["-add_rpath", rp]
    args.append(path)
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0 and "would duplicate path" not in result.stderr:
        print("install_name_tool failed:", path, result.stderr.strip())
        sys.exit(1)

rewrite(binary, binary, ["@executable_path/../Frameworks"], False)
for name, src in copied.items():
    rewrite(os.path.join(fw, name), src, ["@loader_path"], True)
for so in plugins:
    rel = os.path.relpath(fw, os.path.dirname(so))
    rewrite(so, so, ["@loader_path/" + rel], True)

# 3. nothing may point outside the bundle any more
bad = []
for path in [binary] + [os.path.join(fw, n) for n in copied] + plugins:
    for dep in load_commands(path):
        if is_system(dep) or os.path.basename(dep) == os.path.basename(path):
            continue
        if not dep.startswith("@rpath/") or not os.path.exists(os.path.join(fw, dep[len("@rpath/"):])):
            bad.append((path, dep))
if bad:
    for path, dep in bad[:10]:
        print("outside reference:", path, "->", dep)
    sys.exit(1)
total = sum(os.path.getsize(os.path.join(fw, n)) for n in copied)
print(f"{len(copied)} dylibs in Frameworks ({total // 1_000_000} MB), {len(plugins)} plugins")
PY

# Ad-hoc signatures, inner items first.
find "$FW" "$RES" -type f \( -name "*.dylib" -o -name "*.so" \) -exec codesign --force --sign - {} \; 2>/dev/null
codesign --force --sign - "$DIST" >/dev/null 2>&1
du -sh "$DIST" | awk '{print "bundle size " $1}'
echo "bundled $DIST"
