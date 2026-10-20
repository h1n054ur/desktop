"""Tests that `speak say` never repeats a reply. Run: python3 speak/tests/test_dedupe.py

A stub TTS server on 127.0.0.1:8778 counts requests, the player writes to a file, and the
state dir is a temp folder, so nothing reaches the speakers or the live state.
"""

import fcntl
import http.server
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SPEAK = os.path.join(HERE, "..", "bin", "speak")
PORT = 8778


class StubTTS(http.server.BaseHTTPRequestHandler):
    requests = []

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        StubTTS.requests.append(body)
        self.send_response(200)
        self.send_header("Content-Type", "audio/wav")
        self.send_header("Content-Length", "4")
        self.end_headers()
        self.wfile.write(b"RIFF")

    def log_message(self, *args):
        pass


class SayBase(unittest.TestCase):
    """A stub server, a temp state dir and helpers to call `speak say`."""

    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), StubTTS)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        StubTTS.requests = []
        self.tmp = tempfile.TemporaryDirectory()
        self.out = os.path.join(self.tmp.name, "played")
        self.env = dict(
            os.environ,
            XDG_STATE_HOME=os.path.join(self.tmp.name, "state"),
            XDG_CONFIG_HOME=os.path.join(self.tmp.name, "config"),
            SPEAK_SERVER=f"http://127.0.0.1:{PORT}",
            SPEAK_PLAYER=f"cat >> {self.out}",
        )
        self.state = os.path.join(self.tmp.name, "state", "speak")

    def tearDown(self):
        self.wait_idle()
        self.tmp.cleanup()

    def say(self, text, source="opencode: test", reply_id=None, intro=None, voice="codex", strip=False):
        args = [sys.executable, SPEAK, "say", "--voice", voice, "--source", source]
        if strip:
            args.append("--strip-label")
        if reply_id:
            args += ["--id", reply_id]
        if intro is not None:
            args += ["--intro", intro]
        return subprocess.Popen(args, stdin=subprocess.PIPE, env=self.env, text=True)

    def run_all(self, procs, texts):
        for proc, text in zip(procs, texts):
            proc.stdin.write(text)
            proc.stdin.close()
        for proc in procs:
            self.assertEqual(proc.wait(timeout=10), 0)

    def wait_idle(self, timeout=10):
        """Wait until the detached worker has drained the queue and let go of its lock."""
        lock = os.path.join(self.state, "worker.lock")
        queue = os.path.join(self.state, "queue")
        end = time.time() + timeout
        while time.time() < end:
            busy = os.path.isdir(queue) and any(n.endswith(".json") for n in os.listdir(queue))
            if not busy and os.path.exists(lock):
                with open(lock, "a") as fh:
                    try:
                        fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        fcntl.flock(fh, fcntl.LOCK_UN)
                        return
                    except BlockingIOError:
                        pass
            elif not busy:
                return
            time.sleep(0.05)
        self.fail("worker did not finish")

class DedupeTests(SayBase):
    def test_parallel_same_id_plays_once(self):
        procs = [self.say("Doing well, thanks.", reply_id="opencode:msg_1") for _ in range(8)]
        self.run_all(procs, ["Doing well, thanks."] * 8)
        self.wait_idle()
        self.assertEqual(len(StubTTS.requests), 1)
        self.assertEqual(len(os.listdir(os.path.join(self.state, "ids"))), 1)
        with open(self.out, "rb") as fh:
            self.assertEqual(fh.read(), b"RIFF")

    def test_same_id_later_is_dropped(self):
        self.run_all([self.say("First.", reply_id="x")], ["First."])
        self.wait_idle()
        self.run_all([self.say("Other text.", reply_id="x")], ["Other text."])
        self.wait_idle()
        self.assertEqual(len(StubTTS.requests), 1)

    def test_same_text_same_source_within_window_is_dropped(self):
        self.run_all([self.say("Same words.", reply_id="a")], ["Same words."])
        self.run_all([self.say("Same words.", reply_id="b")], ["Same words."])
        self.run_all([self.say("Same words.")], ["Same words."])
        self.wait_idle()
        self.assertEqual(len(StubTTS.requests), 1)

    def test_same_text_other_source_plays(self):
        self.run_all([self.say("Same words.", source="opencode: a")], ["Same words."])
        self.wait_idle()
        self.run_all([self.say("Same words.", source="claude-code: b")], ["Same words."])
        self.wait_idle()
        self.assertEqual(len(StubTTS.requests), 2)

    def test_old_ids_are_pruned(self):
        self.run_all([self.say("Old one.", reply_id="old")], ["Old one."])
        self.wait_idle()
        ids = os.path.join(self.state, "ids")
        (name,) = os.listdir(ids)
        two_days = time.time() - 2 * 24 * 3600
        os.utime(os.path.join(ids, name), (two_days, two_days))
        self.run_all([self.say("New one.", reply_id="new")], ["New one."])
        self.wait_idle()
        self.assertEqual(len(os.listdir(ids)), 1)
        self.assertNotEqual(os.listdir(ids)[0], name)

    def test_intro_is_spoken_but_not_kept(self):
        intro = "Workspace 3, Codex in desktop."
        self.run_all([self.say("All tests pass.", intro=intro)], ["All tests pass."])
        self.wait_idle()
        self.assertEqual(len(StubTTS.requests), 1)
        self.assertIn(b"Workspace 3, Codex in desktop. All tests pass.", StubTTS.requests[0])
        with open(os.path.join(self.state, "last.json")) as fh:
            self.assertEqual(json.load(fh)["text"], "All tests pass.")

    def test_empty_intro_says_only_the_reply(self):
        self.run_all([self.say("All tests pass.", intro="")], ["All tests pass."])
        self.wait_idle()
        self.assertIn(b"\r\nAll tests pass.\r\n", StubTTS.requests[0])


class LabelTests(SayBase):
    """Name labels: `speak voice-from-reply` picks the voice, `say --strip-label` drops the label."""

    def setUp(self):
        super().setUp()
        self.sessions = os.path.join(self.tmp.name, "sessions")
        os.makedirs(self.sessions)
        conf = os.path.join(self.tmp.name, "config", "speak")
        os.makedirs(conf)
        with open(os.path.join(conf, "config.toml"), "w") as fh:
            fh.write(f'[voices]\nada = "alba"\nBo = "jean"\n\n[labels]\nenabled = true\nstate_dir = "{self.sessions}"\n')

    def pick(self, text, tool="claude", session="s1"):
        out = subprocess.run(
            [sys.executable, SPEAK, "voice-from-reply", "--tool", tool, "--session", session],
            input=text, env=self.env, capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(out.returncode, 0)
        return json.loads(out.stdout)

    def save_state(self, persona, tool="claude", session="s1"):
        with open(os.path.join(self.sessions, f"{tool}-{session}.json"), "w") as fh:
            json.dump({"persona": persona, "updated": 1}, fh)

    def test_bold_label(self):
        self.assertEqual(self.pick("**Ada:** All tests pass."), {"voice": "ada", "name": "Ada", "from": "label"})
        self.assertEqual(self.pick("**ada**: All tests pass.")["voice"], "ada")

    def test_label_without_bold_any_case(self):
        self.assertEqual(self.pick("ADA: All tests pass.")["voice"], "ada")
        self.assertEqual(self.pick("bo: done.")["voice"], "Bo")

    def test_unknown_or_late_label_is_ignored(self):
        self.assertEqual(self.pick("Note: this is fine."), {})
        self.assertEqual(self.pick("Default: no."), {})
        self.assertEqual(self.pick("I think **Ada:** said so."), {})

    def test_state_fallback(self):
        self.save_state("ada")
        self.assertEqual(self.pick("All tests pass."), {"voice": "ada", "name": "Ada", "from": "state"})
        self.assertEqual(self.pick("**Bo:** Done.")["voice"], "Bo")
        self.assertEqual(self.pick("All tests pass.", tool="opencode"), {})

    def test_state_naming_an_unknown_voice_is_ignored(self):
        self.save_state("nobody")
        self.assertEqual(self.pick("All tests pass."), {})

    def test_no_state(self):
        self.assertEqual(self.pick("All tests pass.", session="none"), {})
        self.assertEqual(self.pick("All tests pass.", session="../x"), {})

    def test_labels_off(self):
        with open(os.path.join(self.tmp.name, "config", "speak", "config.toml"), "w") as fh:
            fh.write('[voices]\nada = "alba"\n[labels]\nenabled = false\n')
        self.assertEqual(self.pick("**Ada:** All tests pass."), {})

    def test_label_is_not_spoken_but_kept(self):
        intro = "Workspace 3, Ada in desktop."
        reply = "**Ada:** All tests pass."
        self.run_all([self.say(reply, intro=intro, voice="ada", strip=True)], [reply])
        self.wait_idle()
        self.assertEqual(len(StubTTS.requests), 1)
        self.assertIn(b"\r\nWorkspace 3, Ada in desktop. All tests pass.\r\n", StubTTS.requests[0])
        with open(os.path.join(self.state, "last.json")) as fh:
            last = json.load(fh)
        self.assertEqual(last["speech"], "All tests pass.")
        self.assertTrue(last["text"].endswith("All tests pass."))
        self.assertIn("Ada", last["text"])
        self.assertNotIn("Workspace", last["text"])

    def test_unknown_label_is_spoken_as_is(self):
        reply = "Note: all tests pass."
        self.run_all([self.say(reply, strip=True)], [reply])
        self.wait_idle()
        self.assertIn(b"Note: all tests pass.", StubTTS.requests[0])


if __name__ == "__main__":
    unittest.main()
