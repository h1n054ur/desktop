"""Tests that `speak say` never repeats a reply. Run: python3 speak/tests/test_dedupe.py

A stub TTS server on 127.0.0.1:8778 counts requests, the player writes to a file, and the
state dir is a temp folder, so nothing reaches the speakers or the live state.
"""

import fcntl
import http.server
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


class DedupeTests(unittest.TestCase):
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

    def say(self, text, source="opencode: test", reply_id=None):
        args = [sys.executable, SPEAK, "say", "--voice", "codex", "--source", source]
        if reply_id:
            args += ["--id", reply_id]
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


if __name__ == "__main__":
    unittest.main()
