"""Re-vendor ElegantFin and Cascadia Code for the Jellyfin theme. Called by update.sh.

    python3 -I update.py <vendor-dir> <elegantfin-commit> <cascadia-version>

Downloads with curl into a temp folder, verifies every file, inlines the fonts as data URIs,
writes vendor/elegantfin/, vendor/fonts/ and vendor/VERSIONS. Uses only the Python stdlib.
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

REPO = "lscambo13/ElegantFin"
MINIFIED = "Theme/ElegantFin-jellyfin-theme-build-latest-minified.css"

# Files that do not depend on the ElegantFin commit: pinned by URL and sha256.
INTER_URL = "https://fonts.gstatic.com/s/inter/v20/UcCo3FwrK3iLTcviYwY.woff2"
INTER_SHA = "2c295d99e26dcf357d4d01bcf270fd6924b600c9a13dd8c363ef114f4c6976fa"
INTER_ITALIC_BYTES = 79716  # only quoted in VERSIONS, never downloaded
INTER_IMPORT = ('@import url("https://fonts.googleapis.com/css2?family=Inter:ital,opsz,wght@'
                '0,14..32,100..900;1,14..32,100..900&display=swap");')
INTER_LICENSE_URL = "https://raw.githubusercontent.com/rsms/inter/v4.1/LICENSE.txt"
INTER_LICENSE_SHA = "262481e844521b326f5ecd053e59b98c8b2da78c8ee1bdbb6e8174305e54935a"
MS_LICENSE_REF = "49d4db35df873165d6bd6ba09b063c7dafbac2f4"
MS_LICENSE_URL = f"https://raw.githubusercontent.com/google/material-design-icons/{MS_LICENSE_REF}/LICENSE"
MS_LICENSE_SHA = "58d1e17ffe5109a7ae296caafcadfdbe6a7d176f0bc4ab01e12a689b0499d8bd"

LATIN = ("U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,"
         "U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD")


def die(msg):
    sys.exit(f"update: {msg}")


def say(msg):
    print(f"update: {msg}", flush=True)


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
    vendor, commit, cc_ver = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
    with tempfile.TemporaryDirectory(prefix="jf-vendor-") as d:
        run(vendor, commit, cc_ver, pathlib.Path(d))


def run(vendor, commit, cc_ver, tmp):
    raw = f"https://raw.githubusercontent.com/{REPO}/{commit}"

    # ElegantFin at the commit
    css = fetch(f"{raw}/{MINIFIED}", tmp / "min.css")
    lic = fetch(f"{raw}/LICENSE", tmp / "LICENSE")
    readme = fetch(f"{raw}/README.md", tmp / "README.md").decode()
    info = json.loads(fetch(f"https://api.github.com/repos/{REPO}/commits/{commit}", tmp / "commit.json"))
    latest = json.loads(fetch(f"https://api.github.com/repos/{REPO}/releases/latest", tmp / "rel.json"))["tag_name"]
    if info.get("sha") != commit:
        die(f"GitHub resolved the commit to {info.get('sha')}, pass the full 40 character sha")
    c_date = info["commit"]["committer"]["date"][:10]
    c_subject = info["commit"]["message"].splitlines()[0]

    text = css.decode()
    m = re.match(r"/\*! ElegantFin Theme (v[0-9.]+) for Jellyfin by lscambo13 \*/", text)
    if not m:
        die("unexpected banner at the top of the minified build")
    banner, version = m.group(0), m.group(1)
    tested = re.search(r"Tested on\s*\n+\s*- Jellyfin Server v?([0-9.]+)", readme)

    # Fonts referenced by the build
    if text.count(INTER_IMPORT) != 1:
        die("the Inter @import changed upstream, check the font and update INTER_* in update.py")
    inter = fetch(INTER_URL, tmp / "inter.woff2")
    pinned("Inter latin woff2", inter, INTER_SHA)
    mmin = re.search(r"(@font-face\{font-family:Material Symbols Rounded Minimal;[^}]*?src:url\()"
                     r"(https://fonts\.gstatic\.com/l/font\?kit=[^)]*)(\))", text)
    if not mmin:
        die("Material Symbols Rounded Minimal @font-face not found")
    ms_min_url = mmin.group(2)
    ms_min = fetch(ms_min_url, tmp / "ms-min.woff2")
    full = re.search(r"@font-face\{font-family:Material Symbols Rounded;[^}]*?src:url\("
                     r"(https://fonts\.gstatic\.com/s/materialsymbolsrounded/v[0-9]+/[^)]*)\)[^}]*\}", text)
    if not full:
        die("full Material Symbols Rounded @font-face not found")
    ms_full = fetch(full.group(1), tmp / "ms-full.woff2")
    inter_lic = fetch(INTER_LICENSE_URL, tmp / "inter-LICENSE")
    pinned("Inter LICENSE", inter_lic, INTER_LICENSE_SHA)
    ms_lic = fetch(MS_LICENSE_URL, tmp / "ms-LICENSE")
    pinned("Material Symbols LICENSE", ms_lic, MS_LICENSE_SHA)

    # Patch the build (the only changes made to upstream)
    out = text.replace(INTER_IMPORT,
                       "@font-face{font-family:Inter;font-style:normal;font-weight:100 900;font-display:swap;"
                       f'src:url(data:font/woff2;base64,{b64(inter)}) format("woff2");unicode-range:{LATIN}}}')
    mmin = re.search(re.escape(ms_min_url), out)
    out = out[:mmin.start()] + "data:font/woff2;base64," + b64(ms_min) + out[mmin.end():]
    full = re.search(r"@font-face\{font-family:Material Symbols Rounded;[^}]*\}", out)
    out = out[:full.start()] + out[full.end():]
    old_pack, new_pack = '--iconPack:"Material Symbols Rounded"', '--iconPack:"Material Symbols Rounded Minimal"'
    if out.count(old_pack) != 1:
        die("--iconPack setting not found exactly once")
    out = out.replace(old_pack, new_pack)
    note = ("/* Vendored for offline use, see VERSIONS. Patches: Inter (latin, normal) and the Material Symbols "
            "Rounded Minimal icon subset inlined as data URIs, the 5.3 MB full Material Symbols face removed, "
            "--iconPack set to the Minimal subset. */")
    out = out.replace(banner, banner + note, 1)
    if re.search(r"https?://", out.replace("http://www.w3.org/2000/svg", "")):
        die("an external URL is left in the patched ElegantFin CSS")
    ef_css = out.encode()

    # Cascadia Code from the npm tarball, checked against the registry's sha512 integrity
    npm = json.loads(fetch(f"https://registry.npmjs.org/@fontsource/cascadia-code/{cc_ver}", tmp / "npm.json"))
    tgz_url, integrity = npm["dist"]["tarball"], npm["dist"]["integrity"]
    tgz = fetch(tgz_url, tmp / "cc.tgz")
    algo, _, want = integrity.partition("-")
    if algo != "sha512" or base64.b64encode(hashlib.sha512(tgz).digest()).decode() != want:
        die(f"Cascadia tarball does not match the registry integrity {integrity}")
    say("ok Cascadia tarball matches the npm integrity")
    with tarfile.open(fileobj=io.BytesIO(tgz), mode="r:gz") as tf:
        def member(name):
            f = tf.extractfile(f"package/{name}")
            if f is None:
                die(f"package/{name} missing from the tarball")
            return f.read()
        meta = json.loads(member("metadata.json"))
        cc_files = {w: member(f"files/cascadia-code-latin-{w}-normal.woff2") for w in (400, 700)}
    cc_tag = json.loads(fetch("https://api.github.com/repos/microsoft/cascadia-code/releases/latest",
                              tmp / "cc-rel.json"))["tag_name"]
    cc_lic = fetch(f"https://raw.githubusercontent.com/microsoft/cascadia-code/{cc_tag}/LICENSE", tmp / "cc-LICENSE")
    rules = []
    for w, data in cc_files.items():
        rules.append(f"/* cascadia-code-latin-{w}-normal */\n@font-face{{font-family:\"Cascadia Code\";font-style:normal;"
                     f"font-display:swap;font-weight:{w};src:url(data:font/woff2;base64,{b64(data)}) "
                     f"format(\"woff2\");unicode-range:{LATIN}}}")
    cc_css = (f"/* Cascadia Code, latin subset, weights 400 and 700, from @fontsource/cascadia-code {cc_ver}. "
              "See VERSIONS. */\n" + "\n".join(rules) + "\n").encode()

    # VERSIONS
    rel = ["latest release"] if latest == version else []
    if tested:
        rel.append(f"tested upstream on Jellyfin Server {tested.group(1)}")
    rel_s = f" ({', '.join(rel)})" if rel else ""
    total = len(ef_css) + len(cc_css)
    full_url_s = re.search(r"https://(\S+?)\)", text[text.find("font-family:Material Symbols Rounded;"):]).group(1)
    v = f"""Vendored third-party files for the Jellyfin theme. Nothing here loads from the internet at runtime.
Fetched {datetime.date.today().isoformat()} by vendor/update.sh. All sha256 values are of the upstream file as downloaded.

ElegantFin (vendor/elegantfin/)
  repo:     https://github.com/{REPO}
  release:  {version}{rel_s}
  commit:   {commit} ({c_date}, "{c_subject}")
  license:  GPL-2.0 (LICENSE)
  source files:
    {MINIFIED}  {len(css)} bytes
      {sha(css)}
    LICENSE  {len(lic)} bytes
      {sha(lic)}
  output: elegantfin.css ({len(ef_css)} bytes)
      {sha(ef_css)}
  patches applied to the minified build (the only changes):
    1. @import of Google Fonts Inter replaced by one inline @font-face: Inter latin subset,
       normal style, variable weight 100 to 900, as a woff2 data URI.
       {INTER_URL}  {len(inter)} bytes
         {sha(inter)}
       Dropped: Inter italic (latin {INTER_ITALIC_BYTES} bytes) and the non-latin subsets. Browsers synthesise
       italic from the normal face.
       License: OFL-1.1 (LICENSE-inter.txt, rsms/inter v4.1 LICENSE.txt,
         {sha(inter_lic)})
    2. "Material Symbols Rounded Minimal" @font-face: Google Fonts kit URL replaced by the same
       file as a woff2 data URI (the icon subset listed in upstream's source CSS).
       {ms_min_url[:79]}... (full URL
       in upstream Theme/ElegantFin-theme-{version}.css)  {len(ms_min)} bytes
         {sha(ms_min)}
    3. "Material Symbols Rounded" (full) @font-face removed. Its file is {len(ms_full)} bytes
       ({full_url_s},
       {sha(ms_full)}), too large to inline.
    4. --iconPack changed from "Material Symbols Rounded" to "Material Symbols Rounded Minimal",
       the option upstream documents to save bandwidth. Upstream warns it may miss icons that
       plugins add. Fallback in every icon rule is Jellyfin's bundled "Material Icons".
       License: Apache-2.0 (LICENSE-material-symbols.txt, google/material-design-icons
         {MS_LICENSE_REF} LICENSE,
         {sha(ms_lic)})
  not vendored: upstream add-ons (media bar, custom media covers), commented out upstream.

Cascadia Code (vendor/fonts/)
  package:  @fontsource/cascadia-code {cc_ver} (npm), font version {meta['version']}, lastModified {meta['lastModified']}
            {tgz_url}
            integrity {integrity} (verified)
            tarball sha256 {sha(tgz)}
  upstream: https://github.com/microsoft/cascadia-code (latest release {cc_tag})
  license:  OFL-1.1 (LICENSE-cascadia-code.txt, microsoft/cascadia-code {cc_tag} LICENSE,
            {sha(cc_lic)})
  source files (latin subset, normal style):
"""
    for w, data in cc_files.items():
        v += f"    files/cascadia-code-latin-{w}-normal.woff2  {len(data)} bytes\n      {sha(data)}\n"
    v += f"""  output: cascadia-code.css ({len(cc_css)} bytes), two @font-face rules with woff2 data URIs
      {sha(cc_css)}

Total vendored CSS: {total} bytes (about {round(total / 1024, -1):.0f} KiB).
"""

    # Re-running the pinned commit must reproduce the pinned files exactly (only the date may move).
    vf = vendor / "VERSIONS"
    if vf.exists():
        old = vf.read_text()
        same_pin = f"commit:   {commit} " in old and f"@fontsource/cascadia-code {cc_ver} " in old
        strip = lambda s: re.sub(r"^Fetched .*\n", "", s, count=1, flags=re.M)
        if same_pin and strip(old) != strip(v):
            import difflib
            sys.stderr.writelines(difflib.unified_diff(strip(old).splitlines(True), strip(v).splitlines(True),
                                                       "VERSIONS (committed)", "VERSIONS (fetched now)"))
            die("same pin as committed but the downloads differ, nothing written")
        if same_pin:
            say("same pin as committed: every hash and size matches VERSIONS")

    (vendor / "elegantfin" / "elegantfin.css").write_bytes(ef_css)
    (vendor / "elegantfin" / "LICENSE").write_bytes(lic)
    (vendor / "elegantfin" / "LICENSE-inter.txt").write_bytes(inter_lic)
    (vendor / "elegantfin" / "LICENSE-material-symbols.txt").write_bytes(ms_lic)
    (vendor / "fonts" / "cascadia-code.css").write_bytes(cc_css)
    (vendor / "fonts" / "LICENSE-cascadia-code.txt").write_bytes(cc_lic)
    vf.write_text(v)
    say(f"wrote vendor/ for ElegantFin {version} at {commit[:12]} and Cascadia Code {cc_ver}")


if __name__ == "__main__":
    main()
