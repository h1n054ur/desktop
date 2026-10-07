"""Ctrl+V for kitty (mapped in kitty.conf: map ctrl+v kitten smart_paste.py).

- image on the clipboard (screenshot, copied image): send a real Ctrl+V to the program, so apps that read images
  themselves (Claude Code uses wl-paste) can attach it
- files copied in Dolphin or another file manager (text/uri-list): paste their paths, quoted if needed
- anything else: normal paste
"""
import shlex
import subprocess
from typing import List
from urllib.parse import unquote, urlparse

from kittens.tui.handler import result_handler


def main(args: List[str]) -> str:
    return ""


def wl_paste(*args: str) -> str:
    try:
        return subprocess.run(["wl-paste", "--no-newline", *args], capture_output=True, text=True, timeout=2).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def copied_file_paths(types: List[str]) -> str:
    """Quoted paths for files on the clipboard, else ''."""
    if "text/uri-list" not in types:
        return ""
    paths = []
    for line in wl_paste("--type", "text/uri-list").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        url = urlparse(line)
        if url.scheme != "file":
            return ""
        paths.append(shlex.quote(unquote(url.path)))
    return " ".join(paths)


@result_handler(no_ui=True)
def handle_result(args: List[str], answer: str, target_window_id: int, boss) -> None:
    w = boss.window_id_map.get(target_window_id)
    if w is None:
        return
    types = wl_paste("--list-types").split()
    files = copied_file_paths(types)
    if files:
        w.paste_with_actions(files)
        return
    if any(t.startswith("image/") for t in types):
        w.send_key("ctrl+v")
        return
    from kitty.clipboard import get_clipboard_string
    text = get_clipboard_string()
    if not text:
        w.send_key("ctrl+v")
        return
    w.paste_with_actions(text)
