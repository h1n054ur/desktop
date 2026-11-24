#!/usr/bin/env python3
"""Build Helium app-window launchers from apps.tsv.

The launcher filename and StartupWMClass match Chromium's app-window class:
chrome-<host>_<path>-<profile>. Column 6 selects a second Helium profile.
"""
import glob
import os
import ssl
import subprocess
import urllib.parse
import urllib.request

HOME = os.path.expanduser("~")
BASE = f"{HOME}/.local/share/chrome-apps"
ICONS = f"{HOME}/.local/share/icons/webapps"
APPS = f"{HOME}/.local/share/applications"
MANIFEST = f"{BASE}/generated-launchers.txt"
CDN = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/{}.png"
DROP_HOSTS = {
    "app.slack.com",
    "discord.com",
    "slack.com",
    "teams.microsoft.com",
    "web.telegram.org",
    "web.whatsapp.com",
}
DROP_HOST_SUFFIXES = (".discord.com", ".slack.com")

os.makedirs(ICONS, exist_ok=True)
os.makedirs(APPS, exist_ok=True)
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE


def wm_class(url, profile="Default"):
    parsed = urllib.parse.urlsplit(url)
    return f"chrome-{parsed.hostname}_{(parsed.path or '/').replace('/', '_')}-{profile}"


def fetch(url, dest):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=15, context=ctx) as response:
            data = response.read()
        valid = (
            len(data) > 200
            and (
                data[:4] in (b"\x89PNG", b"\x00\x00\x01\x00")
                or data[:5] == b"<?xml"
                or b"<svg" in data[:300]
            )
        )
        if valid:
            with open(dest, "wb") as output:
                output.write(data)
            return True
    except Exception:
        pass
    return False


def icon_for(slug, url, name):
    dest = f"{ICONS}/{slug}-app.png"
    if name.startswith("@"):
        custom = f"{ICONS}/{name[1:]}"
        if os.path.exists(custom):
            return custom
    if name != "-" and not name.startswith("@") and fetch(CDN.format(name), dest):
        return dest
    parsed = urllib.parse.urlsplit(url)
    root = f"{parsed.scheme}://{parsed.netloc}"
    for path in ("/apple-touch-icon.png", "/favicon.png", "/favicon.ico"):
        if fetch(root + path, dest):
            return dest
    return "helium-browser"


def launcher_url(path):
    try:
        with open(path) as launcher:
            for line in launcher:
                if line.startswith("Comment="):
                    return line.removeprefix("Comment=").strip()
    except OSError:
        pass
    return ""


def remove_dropped_launchers():
    for path in glob.glob(f"{APPS}/chrome-*.desktop"):
        host = urllib.parse.urlsplit(launcher_url(path)).hostname
        if host in DROP_HOSTS or (host and host.endswith(DROP_HOST_SUFFIXES)):
            os.unlink(path)
            print(f"removed     {os.path.basename(path)}")


with open(f"{BASE}/apps.tsv") as source:
    rows = [line.rstrip("\n").split("\t") for line in source if line.strip() and not line.startswith("#")]

launchers = set()
remove_dropped_launchers()
for slug, name, url, icon, group, *rest in rows:
    profile = rest[0] if rest and rest[0] else "Default"
    keywords = rest[1] if len(rest) > 1 else ""
    if slug == "mylearn":
        cls = wm_class("https://mylearn.une.edu.au/admin/tool/mobile/autologin.php", profile)
    else:
        cls = wm_class(url, profile)
    launcher = f"{cls}.desktop"
    launchers.add(launcher)
    launcher_icon = icon_for(slug, url, icon)
    if slug == "jellyfin":
        command = f"{HOME}/.local/bin/jellyfin-app"
    elif slug == "mylearn":
        command = f"{HOME}/.local/bin/mylearn-app"
    elif profile == "Default":
        command = f"helium-browser --app={url}"
    else:
        command = f"helium-browser --profile-directory={profile} --app={url}"
    with open(f"{APPS}/{launcher}", "w") as output:
        output.write(
            "[Desktop Entry]\n"
            "Type=Application\n"
            f"Name={name}\n"
            f"Comment={url}\n"
            + (f"Keywords={keywords}\n" if keywords else "")
            + f"Exec={command}\n"
            f"Icon={launcher_icon}\n"
            "Terminal=false\n"
            f"StartupWMClass={cls}\n"
            "Categories=Network;\n"
            f"X-ChromeApp-Group={group}\n"
            "X-ChromeApp-Managed=true\n"
        )
    status = "ok " if launcher_icon != "helium-browser" else "NOICON"
    print(f"{status:6} {slug:18} {cls}")

try:
    with open(MANIFEST) as previous:
        old_launchers = {os.path.basename(line.strip()) for line in previous if line.strip()}
except FileNotFoundError:
    old_launchers = set()
for launcher in old_launchers - launchers:
    path = f"{APPS}/{launcher}"
    if os.path.exists(path):
        os.unlink(path)
        print(f"removed     {launcher}")

with open(f"{MANIFEST}.new", "w") as output:
    output.writelines(f"{launcher}\n" for launcher in sorted(launchers))
os.replace(f"{MANIFEST}.new", MANIFEST)
subprocess.run(["update-desktop-database", APPS], check=False)
