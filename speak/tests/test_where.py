"""Tests for bin/speak-where and hooks/claude-stop.sh. Run: python3 speak/tests/test_where.py

kitten and hyprctl are stub scripts on PATH that print fixture JSON, and `speak` is a stub that
records its arguments, so nothing touches the live kitty, Hyprland or the speakers.
"""

import json
import os
import subprocess
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
WHERE = os.path.join(HERE, "..", "bin", "speak-where")
SPEAK = os.path.realpath(os.path.join(HERE, "..", "bin", "speak"))
HOOK = os.path.join(HERE, "..", "hooks", "claude-stop.sh")

KPID = 6595


def kitty_ls(focused_window=None, second_os_window=False):
    """kitten @ ls output: OS window 1 holds kitty windows 1 and 2 in one tab, window 2 active.

    focused_window names the kitty window that has focus, None means kitty has no focus.
    With second_os_window, a second OS window holds window 3.
    """
    def win(wid, active):
        return {"id": wid, "is_active": active, "is_focused": focused_window == wid, "title": f"title {wid}"}

    data = [{
        "id": 1, "is_focused": focused_window in (1, 2),
        "tabs": [{"id": 1, "is_active": True, "title": "tab", "windows": [win(1, False), win(2, True)]}],
    }]
    if second_os_window:
        data.append({
            "id": 2, "is_focused": focused_window == 3,
            "tabs": [{"id": 2, "is_active": True, "title": "tab", "windows": [win(3, True)]}],
        })
    return data


def clients(*entries):
    return [{"pid": pid, "title": title, "workspace": {"id": 0, "name": ws}} for pid, title, ws in entries]


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.bin = os.path.join(self.tmp.name, "bin")
        os.makedirs(self.bin)
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}", HYPRLAND_INSTANCE_SIGNATURE="test")
        self.fixture(kitty=kitty_ls(), clients=clients((KPID, "title 2", "3")), active={"pid": 1})

    def tearDown(self):
        self.tmp.cleanup()

    def stub(self, name, body):
        path = os.path.join(self.bin, name)
        with open(path, "w") as fh:
            fh.write("#!/bin/sh\n" + body)
        os.chmod(path, 0o755)

    def fixture(self, kitty, clients, active):
        for name, data in (("kitty.json", kitty), ("clients.json", clients), ("active.json", active)):
            with open(os.path.join(self.tmp.name, name), "w") as fh:
                json.dump(data, fh)
        d = self.tmp.name
        self.stub("kitten", f'cat "{d}/kitty.json"\n')
        self.stub("hyprctl", f'case $1 in clients) cat "{d}/clients.json" ;; activewindow) cat "{d}/active.json" ;; esac\n')

    def where(self, *extra, window=2):
        args = [WHERE, "--kitty-pid", str(KPID), "--kitty-window", str(window), "--project", "/home/u/desktop", *extra]
        out = subprocess.run(args, env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(out.returncode, 0)
        return out.stdout.strip()


class WhereTests(Base):
    def test_focused_prints_nothing(self):
        self.fixture(kitty_ls(focused_window=2), clients((KPID, "title 2", "3")), {"pid": KPID})
        self.assertEqual(self.where("--agent", "claude"), "")

    def test_kitty_focused_but_another_app_active(self):
        self.fixture(kitty_ls(focused_window=2), clients((KPID, "title 2", "3")), {"pid": 1})
        self.assertEqual(self.where("--agent", "claude"), "Workspace 3, Claude in desktop.")

    def test_unfocused_on_workspace_3(self):
        self.assertEqual(self.where("--agent", "claude"), "Workspace 3, Claude in desktop.")

    def test_other_split_in_same_tab_is_focused(self):
        self.fixture(kitty_ls(focused_window=1), clients((KPID, "title 1", "3")), {"pid": KPID})
        self.assertEqual(self.where("--agent", "claude", window=2), "Workspace 3, Claude in desktop.")

    def test_named_workspace(self):
        self.fixture(kitty_ls(), clients((KPID, "title 2", "music")), {"pid": 1})
        self.assertEqual(self.where("--agent", "claude"), "Workspace music, Claude in desktop.")

    def test_second_os_window_matched_by_title(self):
        self.fixture(
            kitty_ls(second_os_window=True),
            clients((KPID, "title 2", "3"), (KPID, "title 3", "5"), (99, "title 3", "7")),
            {"pid": 1},
        )
        self.assertEqual(self.where("--agent", "claude", window=3), "Workspace 5, Claude in desktop.")

    def test_unknown_workspace_when_titles_clash(self):
        self.fixture(
            kitty_ls(second_os_window=True),
            clients((KPID, "same", "3"), (KPID, "same", "5")),
            {"pid": 1},
        )
        self.assertEqual(self.where("--agent", "claude", window=3), "Claude in desktop.")

    def test_unknown_workspace_without_kitty_ids(self):
        out = subprocess.run(
            [WHERE, "--kitty-pid", "", "--kitty-window", "", "--agent", "claude", "--project", "/x/desktop"],
            env=self.env, capture_output=True, text=True, timeout=10,
        )
        self.assertEqual((out.returncode, out.stdout.strip()), (0, "Claude in desktop."))

    def test_unknown_workspace_when_kitty_is_unreachable(self):
        self.stub("kitten", "exit 1\n")
        self.assertEqual(self.where("--agent", "claude"), "Claude in desktop.")

    def test_unknown_window_id(self):
        self.assertEqual(self.where("--agent", "claude", window=42), "Claude in desktop.")

    def test_opencode_labels(self):
        self.assertEqual(self.where("--agent", "opencode", "--voice", "codex"), "Workspace 3, Codex in desktop.")
        self.assertEqual(
            self.where("--agent", "opencode", "--voice", "default", "--model", "meta/llama-4-maverick-20250405"),
            "Workspace 3, llama 4 maverick in desktop.",
        )
        self.assertEqual(self.where("--agent", "opencode"), "Workspace 3, OpenCode in desktop.")

    def test_persona_name_wins(self):
        self.assertEqual(self.where("--agent", "claude", "--name", "Ada"), "Workspace 3, Ada in desktop.")
        self.assertEqual(self.where("--agent", "opencode", "--voice", "codex", "--name", "Ada"),
                         "Workspace 3, Ada in desktop.")
        self.assertEqual(self.where("--agent", "claude", "--name", ""), "Workspace 3, Claude in desktop.")


class HookTests(Base):
    def setUp(self):
        super().setUp()
        self.calls = os.path.join(self.tmp.name, "speak-calls")
        # voice-from-reply goes to the real speak, say is recorded.
        self.stub("speak", f'[ "$1" = voice-from-reply ] && exec python3 "{SPEAK}" "$@"\n'
                           f'for a in "$@"; do printf "%s\\n" "$a"; done > "{self.calls}.args"\n'
                           f'cat > "{self.calls}.stdin"\nmv "{self.calls}.args" "{self.calls}"\n')
        self.transcript = os.path.join(self.tmp.name, "t.jsonl")
        self.sessions = os.path.join(self.tmp.name, "sessions")
        os.makedirs(self.sessions)
        conf = os.path.join(self.tmp.name, "config", "speak")
        os.makedirs(conf)
        with open(os.path.join(conf, "config.toml"), "w") as fh:
            fh.write(f'[voices]\nada = "alba"\n\n[labels]\nstate_dir = "{self.sessions}"\n')
        self.env.update(
            XDG_CONFIG_HOME=os.path.join(self.tmp.name, "config"),
            XDG_STATE_HOME=os.path.join(self.tmp.name, "state"),
            CLAUDE_CODE_ENTRYPOINT="cli",
        )
        self.env.pop("SPEAK_OFF", None)

    def run_hook(self, prompt, origin=None, kitty=(KPID, 2), wait=5, reply="All tests pass.",
                 entrypoint=None, env=None):
        entry = {"type": "user", "message": {"role": "user", "content": prompt}}
        if origin:
            entry["origin"] = {"kind": origin}
        if entrypoint:
            entry["entrypoint"] = entrypoint
        with open(self.transcript, "w") as fh:
            fh.write(json.dumps(entry) + "\n")
            fh.write(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "Done."}]}}) + "\n")
        hook = {
            "session_id": "s1", "transcript_path": self.transcript, "cwd": "/home/u/desktop",
            "stop_hook_active": False, "last_assistant_message": reply,
        }
        env = dict(self.env, KITTY_PID=str(kitty[0]), KITTY_WINDOW_ID=str(kitty[1]), **(env or {}))
        env["PATH"] = f"{self.bin}:{os.path.dirname(WHERE)}:{os.environ['PATH']}"
        out = subprocess.run([HOOK], input=json.dumps(hook), env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual((out.returncode, out.stdout), (0, ""))
        end = time.time() + wait
        while time.time() < end and not os.path.exists(self.calls):
            time.sleep(0.02)
        if not os.path.exists(self.calls):
            return None
        with open(self.calls) as fh:
            args = fh.read().splitlines()
        with open(self.calls + ".stdin") as fh:
            return args, fh.read()

    def intro(self, args):
        return args[args.index("--intro") + 1]

    def test_focused_has_no_intro(self):
        self.fixture(kitty_ls(focused_window=2), clients((KPID, "title 2", "3")), {"pid": KPID})
        args, text = self.run_hook("how are you")
        self.assertEqual(self.intro(args), "")
        self.assertEqual(text, "All tests pass.")
        self.assertEqual(args[:5], ["say", "--voice", "claude", "--source", "claude-code: desktop"])

    def test_unfocused_has_workspace_intro(self):
        args, _ = self.run_hook("how are you")
        self.assertEqual(self.intro(args), "Workspace 3, Claude in desktop.")

    def test_unknown_workspace_intro(self):
        args, _ = self.run_hook("how are you", kitty=(KPID, 42))
        self.assertEqual(self.intro(args), "Claude in desktop.")

    def test_update_prompt_is_skipped(self):
        self.assertIsNone(self.run_hook("update", wait=1))

    def test_plugin_prompt_is_skipped(self):
        self.assertIsNone(self.run_hook("check things", origin="plugin", wait=1))

    def voice(self, args):
        return args[args.index("--voice") + 1]

    def test_label_picks_voice_and_names_the_intro(self):
        args, text = self.run_hook("how are you", reply="**Ada:** All tests pass.")
        self.assertEqual(self.voice(args), "ada")
        self.assertEqual(self.intro(args), "Workspace 3, Ada in desktop.")
        self.assertIn("--strip-label", args)
        self.assertEqual(text, "**Ada:** All tests pass.")

    def test_saved_persona_without_label(self):
        with open(os.path.join(self.sessions, "claude-s1.json"), "w") as fh:
            json.dump({"persona": "ada", "updated": 1}, fh)
        args, _ = self.run_hook("how are you")
        self.assertEqual(self.voice(args), "ada")
        self.assertEqual(self.intro(args), "Workspace 3, Ada in desktop.")

    def test_unknown_label_keeps_claude(self):
        args, _ = self.run_hook("how are you", reply="**Zed:** All tests pass.")
        self.assertEqual(self.voice(args), "claude")
        self.assertEqual(self.intro(args), "Workspace 3, Claude in desktop.")

    def test_print_mode_transcript_is_skipped(self):
        self.assertIsNone(self.run_hook("summarise this", entrypoint="sdk-cli", wait=1))

    def test_print_mode_env_is_skipped(self):
        self.assertIsNone(self.run_hook("summarise this", env={"CLAUDE_CODE_ENTRYPOINT": "sdk-cli"}, wait=1))

    def test_interactive_transcript_is_spoken(self):
        args, _ = self.run_hook("how are you", entrypoint="cli")
        self.assertEqual(self.voice(args), "claude")

    def test_speak_off(self):
        self.assertIsNone(self.run_hook("how are you", env={"SPEAK_OFF": "1"}, wait=1))


if __name__ == "__main__":
    unittest.main()
