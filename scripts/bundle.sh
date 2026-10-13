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
# The translations: the engine's catalogs (gnumeric-<version>.mo and the
# functions' per language) and goffice's beside them, which the engine
# rebinds to this directory.  GNM_BUNDLE_LANGUAGES="de fr" keeps only those
# languages; all of them otherwise.
if [ -d "$GNM_PREFIX/share/locale" ]; then
	cp -R "$GNM_PREFIX/share/locale" "$RES/gnumeric/locale"
	goffice_locale="$(pkg-config --variable=prefix libgoffice-0.10)/share/locale"
	for mo in "$goffice_locale"/*/LC_MESSAGES/goffice-*.mo; do
		[ -f "$mo" ] || continue
		lang="$(basename "$(dirname "$(dirname "$mo")")")"
		[ -d "$RES/gnumeric/locale/$lang/LC_MESSAGES" ] || continue   # only the engine's languages
		cp "$mo" "$RES/gnumeric/locale/$lang/LC_MESSAGES/"
	done
	if [ -n "${GNM_BUNDLE_LANGUAGES:-}" ]; then
		for dir in "$RES"/gnumeric/locale/*/; do
			lang="$(basename "$dir")"
			case " $GNM_BUNDLE_LANGUAGES " in *" $lang "*) ;; *) rm -rf "$dir" ;; esac
		done
	fi
fi
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
import json
with open(os.path.join(os.path.dirname(dist), "closure.json"), "w") as f:
    json.dump(copied, f, indent=1, sort_keys=True)
PY

# The licenses: every bundled library's texts and an index (HANDOFF.md
# Phase 6: the libraries are not system libraries, so their licenses
# travel with them; the engine is GPL, so its patches do too).
source_url=$(git remote get-url origin 2>/dev/null | sed -E 's#^git@github.com:#https://github.com/#; s#\.git$##' || true)
python3 - "$DIST" "$(brew --prefix 2>/dev/null || echo /opt/homebrew)" "$GNM_PREFIX" "$goffice_plugins" "$loaders" "$PWD" "$version" "${source_url:-}" <<'PY'
import os, re, sys, glob, json, shutil
dist, brew, prefix, goffice_plugins, loaders, repo, engine_version, source_url = sys.argv[1:9]
res = os.path.join(dist, "Contents/Resources")
out = os.path.join(res, "licenses")
os.makedirs(out)
cellar = re.compile(re.escape(os.path.realpath(os.path.join(brew, "Cellar"))) + r"/([^/]+)/([^/]+)/")
prefix = os.path.realpath(prefix)
with open(os.path.join(os.path.dirname(dist), "closure.json")) as f:
    closure = json.load(f)

# 1. what came from where: formula -> {version, files}
entries = {}
def note(real, shown):
    real = os.path.realpath(real)
    if real.startswith(prefix + "/"):
        key, version = "gnumeric", engine_version
    else:
        m = cellar.match(real)
        if not m:
            print("no formula for", real)
            sys.exit(1)
        key, version = m.group(1), m.group(2)
    entries.setdefault(key, {"version": version, "files": []})["files"].append(shown)
for name, real in closure.items():
    note(real, "Frameworks/" + name)
for so in sorted(glob.glob(os.path.join(prefix, "lib/gnumeric", engine_version, "plugins/*/*.so"))):
    note(so, "Resources/gnumeric/lib/plugins/" + os.path.relpath(so, os.path.join(prefix, "lib/gnumeric", engine_version, "plugins")))
for so in sorted(glob.glob(os.path.join(goffice_plugins, "*/*.so"))):
    note(so, "Resources/goffice/plugins/" + os.path.relpath(so, goffice_plugins))
for so in sorted(glob.glob(os.path.join(loaders, "*.so"))):
    note(so, "Resources/gdk-pixbuf/loaders/" + os.path.basename(so))

# 2. each formula's texts and metadata
texts = re.compile(r"^(COPYING|LICEN[CS]E|Copyright|NOTICE|AUTHORS|[\w.+-]*(GPL|MIT|BSD|MPL|Apache|Zlib|license)[\w.+-]*\.txt)", re.I)
def keg_metadata(formula, version):
    keg = os.path.join(brew, "Cellar", formula, version)
    rb = open(os.path.join(keg, ".brew", formula + ".rb")).read()
    url = re.search(r'^\s*url "([^"]+)"', rb, re.M)
    homepage = re.search(r'^\s*homepage "([^"]+)"', rb, re.M)
    license = None
    sbom = os.path.join(keg, "sbom.spdx.json")
    if os.path.exists(sbom):
        with open(sbom) as f:
            for package in json.load(f).get("packages", []):
                if package.get("name") == formula and package.get("licenseConcluded") not in (None, "NOASSERTION"):
                    license = package["licenseConcluded"]
    if not license:
        m = re.search(r"^\s*license (.+?)$", rb, re.M)
        license = m.group(1).strip() if m else "(not stated)"
    files = sorted(n for n in os.listdir(keg) if texts.match(n))
    if os.path.isdir(os.path.join(keg, "LICENSES")):
        files.append("LICENSES")
    return keg, license, homepage.group(1) if homepage else "", url.group(1) if url else "", files

index = []
for formula in sorted(entries):
    entry = entries[formula]
    version = entry["version"]
    folder = f"{formula}-{version}"
    target = os.path.join(out, folder)
    os.makedirs(target)
    if formula == "gnumeric":
        keg = os.path.join(repo, "upstream/gnumeric")
        license = "GPL-2.0-only OR GPL-3.0-only"
        homepage = "https://www.gnumeric.org/"
        major = ".".join(version.split(".")[:2])
        url = f"https://download.gnome.org/sources/gnumeric/{major}/gnumeric-{version}.tar.xz"
        files = sorted(n for n in os.listdir(keg) if texts.match(n))
        shutil.copytree(os.path.join(repo, "patches"), os.path.join(target, "patches"))
        entry["note"] = "the engine, built from this release with the patches in patches/ (patches/README.md says what each changes)"
    else:
        keg, license, homepage, url, files = keg_metadata(formula, version)
    if not files:
        print("no license text in", keg)
        sys.exit(1)
    for name in files:
        src = os.path.join(keg, name)
        if os.path.isdir(src):
            shutil.copytree(src, os.path.join(target, name))
        else:
            shutil.copy2(src, os.path.join(target, name))
    shown = [n for n in files if not n.upper().startswith("AUTHORS")]
    lines = [f"{formula} {version}",
             f"  license:  {license}",
             f"  homepage: {homepage}",
             f"  source:   {url}",
             f"  texts:    {folder}/{', '.join(shown)}"]
    if "note" in entry:
        lines.append(f"  note:     {entry['note']}")
    files_shown = entry["files"]
    lines.append(f"  bundled:  {len(files_shown)} file{'s' if len(files_shown) != 1 else ''}: " + ", ".join(files_shown[:4]) + (", …" if len(files_shown) > 4 else ""))
    index.append("\n".join(lines))

# 3. the application's own license beside them
own = os.path.join(out, "GnumericCocoa")
os.makedirs(own)
for name in ("COPYING", "COPYING-gpl2", "COPYING-gpl3"):
    shutil.copy2(os.path.join(repo, name), os.path.join(own, name))

header = f"""Third-party software in GnumericCocoa.app
=========================================

GnumericCocoa is free software under the GNU General Public License,
version 2 or version 3 (GnumericCocoa/COPYING beside this file); its
source is at {source_url or "the repository it was built from"}.
It is a Cocoa front end for the Gnumeric spreadsheet engine, and it
carries the engine and the libraries below inside the application
bundle, each as its own file under Contents/Frameworks or
Contents/Resources that a user may replace with another build of the
same library (the GNU Lesser General Public License's relinking
condition, version 2.1 section 6b).  Each library's license texts are
in the directory named under "texts", and the source of each release is
at the URL under "source".  Versions are those of the Homebrew formulae
the bundle was made from.

"""
with open(os.path.join(out, "THIRD-PARTY.txt"), "w") as f:
    f.write(header + "\n\n".join(index) + "\n")
print(f"{len(entries)} libraries' licenses in Resources/licenses (THIRD-PARTY.txt)")
PY

# Ad-hoc signatures, inner items first.
find "$FW" "$RES" -type f \( -name "*.dylib" -o -name "*.so" \) -exec codesign --force --sign - {} \; 2>/dev/null
codesign --force --sign - "$DIST" >/dev/null 2>&1
du -sh "$DIST" | awk '{print "bundle size " $1}'
echo "bundled $DIST"
