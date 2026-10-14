"""Re-vendor the Abyss Jellyfin theme for offline use. Called by vendor/abyss/update.sh.

    python3 -I update.py <abyss-dir> <abyss-commit>

Downloads with curl into a temp folder, verifies every file, inlines the fonts as data URIs,
writes vendor/abyss/abyss.css, abyss-lite.css, the licenses and vendor/abyss/VERSIONS.
Uses only the Python stdlib. Re-running the committed pin must reproduce the files exactly.
"""
import base64
import datetime
import hashlib
import io
import json
import pathlib
import re
import subprocess
import sys
import tarfile
import tempfile

REPO = "AumGupta/abyss-jellyfin"
UPSTREAM_FILES = ["abyss.css", "styles/abyss-lite.css", "LICENSE", "README.md"]

# The Google Fonts @import at the top of abyss.css, replaced by one inline @font-face.
GS_IMPORT = ("@import url('https://fonts.googleapis.com/css2?family=Google+Sans:ital,opsz,wght@"
             "0,17..18,400..700;1,17..18,400..700&display=swap');")
# The latin, normal style face that the css2 URL above serves to a current Chrome. Pinned by sha256.
GS_URL = "https://fonts.gstatic.com/s/googlesans/v71/4UaRrENHsxJlGDuGo1OIlJfC6l_24rlCK1Yo_Iq2vgCI.woff2"
GS_SHA = "76522cb09c91d6f8fcb3b4163ca574cbf2bba901965fa02351fd5bdff17b4fce"
GS_ITALIC_URL = "https://fonts.gstatic.com/s/googlesans/v71/4UaXrENHsxJlGDuGo1OIlL3L2JB874GPhFI9_IqmuTCKjsg.woff2"
GS_LICENSE_REF = "a0e3dbcdc3a3ecfafff3f071159ae0221628922d"
GS_LICENSE_URL = f"https://raw.githubusercontent.com/google/fonts/{GS_LICENSE_REF}/ofl/googlesans/OFL.txt"
GS_LICENSE_SHA = "2b75ef20f13d83a7514aee452c4782c20cdc9ff2dee17600f44d37a06d4fb958"

# The Material Icons Round @font-face src, served by jsDelivr from the npm package.
MI_PKG, MI_VER = "material-icons", "1.13.12"
MI_SRC = f"https://cdn.jsdelivr.net/npm/{MI_PKG}@{MI_VER}/iconfont/material-icons-round.woff2"
MI_FILE = "iconfont/material-icons-round.woff2"

LATIN = ("U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,"
         "U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD")


def die(msg):
    sys.exit(f"update-abyss: {msg}")


def say(msg):
    print(f"update-abyss: {msg}", flush=True)


def fetch(url, dest):
    say(f"fetch {url}")
    r = subprocess.run(["curl", "-fsSL", "--retry", "3", "--proto", "=https", "-A", "curl",
                        "-o", str(dest), url])
    if r.returncode != 0:
        die(f"download failed ({r.returncode}): {url}")
    return dest.read_bytes()


def sha(b):
    return hashlib.sha256(b).hexdigest()


def pinned(name, data, want):
    got = sha(data)
    if got != want:
        die(f"{name}: sha256 {got} does not match the pinned {want}")
    say(f"ok {name} sha256 matches the pin")


def b64(b):
    return base64.b64encode(b).decode()


def main():
    out_dir, commit = pathlib.Path(sys.argv[1]), sys.argv[2]
    with tempfile.TemporaryDirectory(prefix="jf-abyss-") as d:
        run(out_dir, commit, pathlib.Path(d))


def run(out_dir, commit, tmp):
    raw = f"https://raw.githubusercontent.com/{REPO}/{commit}"
    up = {f: fetch(f"{raw}/{f}", tmp / f.replace("/", "_")) for f in UPSTREAM_FILES}
    info = json.loads(fetch(f"https://api.github.com/repos/{REPO}/commits/{commit}", tmp / "commit.json"))
    if info.get("sha") != commit:
        die(f"GitHub resolved the commit to {info.get('sha')}, pass the full 40 character sha")
    c_date = info["commit"]["committer"]["date"][:10]
    c_subject = info["commit"]["message"].splitlines()[0]
    tags = json.loads(fetch(f"https://api.github.com/repos/{REPO}/tags?per_page=100", tmp / "tags.json"))
    tag = next((t["name"] for t in tags if t["commit"]["sha"] == commit), None)
    latest = json.loads(fetch(f"https://api.github.com/repos/{REPO}/releases/latest", tmp / "rel.json"))["tag_name"]
    readme = up["README.md"].decode()
    compat = re.findall(r"^\| (1[0-9.x]+) \| ([^|]+?) \|$", readme, flags=re.M)

    text = up["abyss.css"].decode()
    lite = up["styles/abyss-lite.css"]
    if re.search(rb"https?://", lite):
        die("abyss-lite.css now references an external URL, check it")

    # Google Sans: the import must be exactly the one pinned above.
    if text.count(GS_IMPORT) != 1:
        die("the Google Sans @import changed upstream, check the font and update GS_* in update.py")
    gs = fetch(GS_URL, tmp / "gs.woff2")
    pinned("Google Sans latin woff2", gs, GS_SHA)
    gs_lic = fetch(GS_LICENSE_URL, tmp / "gs-OFL.txt")
    pinned("Google Sans OFL.txt", gs_lic, GS_LICENSE_SHA)

    # Material Icons Round: take it from the npm tarball, checked against the registry integrity,
    # and make sure it is byte-identical to what jsDelivr serves for the URL in abyss.css.
    if text.count(MI_SRC) != 1:
        die("the Material Icons Round src URL changed upstream, update MI_* in update.py")
    npm = json.loads(fetch(f"https://registry.npmjs.org/{MI_PKG}/{MI_VER}", tmp / "npm.json"))
    tgz_url, integrity = npm["dist"]["tarball"], npm["dist"]["integrity"]
    tgz = fetch(tgz_url, tmp / "mi.tgz")
    algo, _, want = integrity.partition("-")
    if algo != "sha512" or base64.b64encode(hashlib.sha512(tgz).digest()).decode() != want:
        die(f"{MI_PKG} tarball does not match the registry integrity {integrity}")
    say(f"ok {MI_PKG} tarball matches the npm integrity")
    with tarfile.open(fileobj=io.BytesIO(tgz), mode="r:gz") as tf:
        def member(name):
            f = tf.extractfile(f"package/{name}")
            if f is None:
                die(f"package/{name} missing from the tarball")
            return f.read()
        mi = member(MI_FILE)
        mi_lic = member("LICENSE")
    cdn = fetch(MI_SRC, tmp / "mi-cdn.woff2")
    if sha(cdn) != sha(mi):
        die("jsDelivr serves a different Material Icons Round file than the npm tarball holds")
    say("ok Material Icons Round from jsDelivr matches the npm tarball")

    # Patch abyss.css (the only changes made to upstream)
    out = text.replace(GS_IMPORT,
                       "@font-face{font-family:'Google Sans';font-style:normal;font-weight:400 700;font-display:swap;"
                       f"src:url(data:font/woff2;base64,{b64(gs)}) format('woff2');unicode-range:{LATIN}}}")
    out = out.replace(MI_SRC, "data:font/woff2;base64," + b64(mi))
    note = ("/* Vendored for offline use, see vendor/abyss/VERSIONS. Patches: the Google Fonts @import replaced by "
            "Google Sans (latin, normal) inlined as a data URI, the Material Icons Round woff2 inlined as a data "
            "URI. */\n")
    out = note + out
    if re.search(r"https?://", out.replace("http://www.w3.org/2000/svg", "")):
        die("an external URL is left in the patched abyss.css")
    abyss_css = out.encode()

    # VERSIONS
    rel = [f"tag {tag}"] if tag else ["no tag at this commit"]
    if tag and tag == latest:
        rel.append("latest release")
    rel_s = ", ".join(rel)
    compat_s = "\n".join(f"            {v}: {s}" for v, s in compat) or "            (table not found)"
    total = len(abyss_css) + len(lite)
    v = f"""Abyss theme for Jellyfin, vendored for offline use. Nothing here loads from the internet at runtime.
Fetched {datetime.date.today().isoformat()} by vendor/abyss/update.sh. All sha256 values are of the upstream file as downloaded.

Abyss (vendor/abyss/)
  repo:     https://github.com/{REPO}
  release:  {rel_s}
  commit:   {commit} ({c_date}, "{c_subject}")
  license:  MIT (LICENSE)
  upstream compatibility table (README.md at this commit):
{compat_s}
  source files:
"""
    for f in UPSTREAM_FILES:
        v += f"    {f}  {len(up[f])} bytes\n      {sha(up[f])}\n"
    v += f"""  output:
    abyss.css  {len(abyss_css)} bytes
      {sha(abyss_css)}
    abyss-lite.css  {len(lite)} bytes (upstream styles/abyss-lite.css, unchanged, optional low-power override)
      {sha(lite)}
  patches applied to abyss.css (the only changes):
    1. @import of Google Fonts "Google Sans" replaced by one inline @font-face: Google Sans
       latin subset, normal style, variable weight 400 to 700, as a woff2 data URI.
       {GS_URL}  {len(gs)} bytes
         {sha(gs)}
       Dropped: the italic face ({GS_ITALIC_URL.rsplit('/', 1)[1]}) and the
       non-latin subsets. Browsers synthesise italic from the normal face.
       License: OFL-1.1 (LICENSE-google-sans.txt, google/fonts {GS_LICENSE_REF[:12]} ofl/googlesans/OFL.txt,
         {sha(gs_lic)})
    2. "Material Icons Round" @font-face src: the jsDelivr URL replaced by the same file as a
       woff2 data URI. Kept whole: abyss.css forces this family with !important on every icon
       element and upstream documents no smaller subset.
       {MI_SRC}  {len(mi)} bytes
         {sha(mi)}
       taken from the npm tarball {tgz_url}
         integrity {integrity} (verified, and byte-identical to the jsDelivr file)
       License: Apache-2.0 (LICENSE-material-icons.txt, {MI_PKG} {MI_VER} package LICENSE,
         {sha(mi_lic)})
    3. A one-line comment at the top naming these patches.
  not vendored: Spotlight (scripts/spotlight/, needs a script tag added to jellyfin-web index.html
    on the server), the installers, the plugin add-ons styles/abyss-je.css and styles/abyss-mbe.css.

Total vendored CSS: {total} bytes (about {round(total / 1024, -1):.0f} KiB).
"""

    vf = out_dir / "VERSIONS"
    if vf.exists():
        old = vf.read_text()
        same_pin = f"commit:   {commit} " in old
        strip = lambda s: re.sub(r"^Fetched .*\n", "", s, count=1, flags=re.M)
        if same_pin and strip(old) != strip(v):
            import difflib
            sys.stderr.writelines(difflib.unified_diff(strip(old).splitlines(True), strip(v).splitlines(True),
                                                       "VERSIONS (committed)", "VERSIONS (fetched now)"))
            die("same pin as committed but the downloads differ, nothing written")
        if same_pin:
            say("same pin as committed: every hash and size matches VERSIONS")

    (out_dir / "abyss.css").write_bytes(abyss_css)
    (out_dir / "abyss-lite.css").write_bytes(lite)
    (out_dir / "LICENSE").write_bytes(up["LICENSE"])
    (out_dir / "LICENSE-google-sans.txt").write_bytes(gs_lic)
    (out_dir / "LICENSE-material-icons.txt").write_bytes(mi_lic)
    vf.write_text(v)
    say(f"wrote vendor/abyss/ for Abyss {tag or commit[:12]}")


if __name__ == "__main__":
    main()
