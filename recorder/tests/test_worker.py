"""Tests for bin/recorder-worker with the fake model (RECORDER_FAKE_TRANSCRIBE=1), no GPU needed."""

import json
import os
import subprocess
import sys
import time
import unittest

from test_recorder import Env

HERE = os.path.dirname(os.path.abspath(__file__))
WORKER = os.path.join(HERE, "..", "bin", "recorder-worker")


class WorkerTests(Env):
    def setUp(self):
        super().setUp()
        self.env["RECORDER_FAKE_TRANSCRIBE"] = "1"
        self.rec = os.path.join(self.tmp, "Recordings")
        os.makedirs(self.rec, exist_ok=True)

    def audio(self, name):
        path = os.path.join(self.rec, name)
        with open(path, "wb") as f:
            f.write(b"fake")
        return path

    def queued_row(self, files, source="system", started="2026-10-23T14:05:12+05:00", title="Recording"):
        rid = self.add_row(title=title, started=started)
        con = self.mod.connect()
        with con:
            con.execute("UPDATE recordings SET files=?, source=?, duration_s=70, transcript_status='queued'"
                        " WHERE id=?", (json.dumps(files), source, rid))
        con.close()
        return rid

    def run_worker(self, **extra):
        env = dict(self.env, **extra)
        return subprocess.run([sys.executable, WORKER], env=env, capture_output=True, text=True, timeout=60)

    def row(self, rid):
        return self.json_cli("show", "--json", str(rid))

    def progress_file(self):
        return os.path.join(self.tmp, "state", "recorder", "worker.json")

    def test_single_track_done(self):
        rid = self.queued_row([self.audio("a.flac")])
        r = self.run_worker()
        self.assertEqual(r.returncode, 0, r.stderr)
        row = self.row(rid)
        self.assertEqual(row["transcript_status"], "done")
        self.assertEqual(row["transcript_model"], "fake")
        self.assertEqual(row["transcript"],
                         "[00:00] Hello from the system track.\n[00:05] Second system line.\n")
        self.assertIsNone(row["error"])
        self.assertFalse(os.path.exists(self.progress_file()))
        # The transcript is searchable.
        self.assertEqual([x["id"] for x in self.json_cli("list", "--json", "--search", "second system")], [rid])

    def test_two_track_merge(self):
        rid = self.queued_row([self.audio("b-system.flac"), self.audio("b-mic.flac")], source="both")
        self.assertEqual(self.run_worker().returncode, 0)
        self.assertEqual(self.row(rid)["transcript"].splitlines(), [
            "[00:00] System: Hello from the system track.",
            "[00:01] Mic: Reply on the mic.",
            "[00:05] System: Second system line.",
            "[01:05] Mic: Mic after a minute.",
        ])

    def test_mic_only_uses_mic_track(self):
        rid = self.queued_row([self.audio("c.flac")], source="mic")
        self.run_worker()
        self.assertTrue(self.row(rid)["transcript"].startswith("[00:01] Reply on the mic."))

    def test_failed_then_queue_goes_on(self):
        bad = self.queued_row([os.path.join(self.rec, "gone.flac")])
        good = self.queued_row([self.audio("d.flac")])
        r = self.run_worker()
        self.assertEqual(r.returncode, 0)
        b = self.row(bad)
        self.assertEqual(b["transcript_status"], "failed")
        self.assertIn("missing audio file gone.flac", b["error"])
        self.assertEqual(self.row(good)["transcript_status"], "done")

    def test_queue_order_and_skips(self):
        first = self.queued_row([self.audio("e1.flac")])
        second = self.queued_row([self.audio("e2.flac")])
        untouched = self.add_row(title="Not queued")
        gone = self.queued_row([self.audio("e3.flac")])
        con = self.mod.connect()
        with con:
            con.execute("UPDATE recordings SET deleted=1 WHERE id=?", (gone,))
        con.close()
        out = self.run_worker().stdout.splitlines()
        self.assertEqual([int(l.split()[1]) for l in out], [first, second])
        self.assertEqual(self.row(untouched)["transcript_status"], "none")

    def test_running_and_progress_file(self):
        rid = self.queued_row([self.audio("f.flac")])
        p = subprocess.Popen([sys.executable, WORKER], env=dict(self.env, RECORDER_FAKE_DELAY="0.4"),
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            seen = []

            def progressed():
                try:
                    with open(self.progress_file()) as f:
                        d = json.load(f)
                except (OSError, ValueError):
                    return False
                seen.append(d)
                return d["progress"] > 0
            self.assertTrue(self.wait_for(progressed, timeout=5))
            self.assertEqual(self.row(rid)["transcript_status"], "running")
            d = seen[-1]
            self.assertEqual(d["id"], rid)
            self.assertTrue(0 < d["progress"] < 100)
            self.assertIn("eta_s", d)
        finally:
            p.communicate(timeout=30)
        self.assertEqual(self.row(rid)["transcript_status"], "done")
        self.assertFalse(os.path.exists(self.progress_file()))

    def test_stale_running_row_is_picked_up(self):
        rid = self.queued_row([self.audio("g.flac")])
        con = self.mod.connect()
        with con:
            con.execute("UPDATE recordings SET transcript_status='running' WHERE id=?", (rid,))
        con.close()
        self.run_worker()
        self.assertEqual(self.row(rid)["transcript_status"], "done")

    def test_second_worker_steps_aside(self):
        import fcntl
        os.makedirs(os.path.join(self.tmp, "state", "recorder"), exist_ok=True)
        rid = self.queued_row([self.audio("h.flac")])
        with open(os.path.join(self.tmp, "state", "recorder", "worker.lock"), "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            r = self.run_worker()
        self.assertEqual(r.returncode, 0)
        self.assertIn("another worker", r.stderr)
        self.assertEqual(self.row(rid)["transcript_status"], "queued")

    def race(self, where):
        """Queue a second row while the worker sits in its final check, `before` or `inside` queue.lock."""
        first = self.queued_row([self.audio("r1.flac")])
        second = self.add_row(title="Late")
        con = self.mod.connect()
        with con:
            con.execute("UPDATE recordings SET files=? WHERE id=?", (json.dumps([self.audio("r2.flac")]), second))
        con.close()
        env = dict(self.env, RECORDER_FAKE_FINAL_PAUSE=f"{where}:1.0")
        env["RECORDER_WORKER_START_CMD"] = f"{sys.executable} {WORKER}"
        env.pop("RECORDER_NO_WORKER")
        self.env = env  # run_cli uses it, so `transcribe` may start a second worker
        p = subprocess.Popen([sys.executable, WORKER], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             text=True)
        try:
            self.assertTrue(self.wait_for(lambda: self.row(first)["transcript_status"] == "done", timeout=10))
            time.sleep(0.3)  # now in the final check pause
            self.run_cli("transcribe", str(second))
            self.assertTrue(self.wait_for(lambda: self.row(second)["transcript_status"] == "done", timeout=10))
        finally:
            out, _ = p.communicate(timeout=30)
        self.assertTrue(self.wait_for(lambda: not self.mod.worker_in_loop(), timeout=10))
        return [int(l.split()[1]) for l in out.splitlines()], first, second

    def test_queued_before_final_check_is_taken_by_same_worker(self):
        ids, first, second = self.race("before")
        self.assertEqual(ids, [first, second])

    def test_queued_during_final_check_starts_new_worker(self):
        ids, first, second = self.race("inside")
        self.assertEqual(ids, [first])  # the second row went to the worker that transcribe started
        self.assertFalse(os.path.exists(self.progress_file()))

    def test_empty_queue_exits(self):
        t0 = time.monotonic()
        self.assertEqual(self.run_worker().returncode, 0)
        self.assertLess(time.monotonic() - t0, 10)

    def test_to_notes_after_transcribe(self):
        rid = self.queued_row([self.audio("2026-10-23_14-05-12-system.flac"),
                               self.audio("2026-10-23_14-05-12-mic.flac")], source="both", title="Team call")
        self.run_cli("tag", str(rid), "work")
        self.run_worker()
        out = self.json_cli("to-notes", str(rid))
        with open(out["path"]) as f:
            text = f.read()
        self.assertEqual(text, "\n".join([
            "---",
            'title: "Team call"',
            "recorded: 2026-10-23T14:05:12+05:00",
            "duration: 1:10",
            "source: both",
            'tags: ["work"]',
            'audio: ["~/Recordings/2026-10-23_14-05-12-system.flac", "~/Recordings/2026-10-23_14-05-12-mic.flac"]',
            'model: "fake"',
            "---",
            "",
            "# Team call",
            "",
            "Audio: `~/Recordings/2026-10-23_14-05-12-system.flac`",
            "Audio: `~/Recordings/2026-10-23_14-05-12-mic.flac`",
            "",
            "## Transcript",
            "",
            "[00:00] System: Hello from the system track.",
            "[00:01] Mic: Reply on the mic.",
            "[00:05] System: Second system line.",
            "[01:05] Mic: Mic after a minute.",
            "",
        ]))


class FormatTests(unittest.TestCase):
    def test_stamp_over_an_hour(self):
        import importlib.machinery
        import importlib.util
        loader = importlib.machinery.SourceFileLoader("worker_mod", WORKER)
        spec = importlib.util.spec_from_loader("worker_mod", loader)
        mod = importlib.util.module_from_spec(spec)
        loader.exec_module(mod)
        self.assertEqual(mod.stamp(59.9), "00:59")
        self.assertEqual(mod.stamp(3725), "1:02:05")
        self.assertEqual(mod.format_transcript([]), "")


if __name__ == "__main__":
    unittest.main()
