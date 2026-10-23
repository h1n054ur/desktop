"""Tests for bin/recorder. Capture is faked with an ffmpeg sine generator, nothing real is recorded."""

import array
import importlib.machinery
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(HERE, "..", "bin", "recorder")
FAKE = "-readrate_initial_burst 0 -re -f lavfi -i sine=frequency={freq}:sample_rate=48000"


def load_module():
    loader = importlib.machinery.SourceFileLoader("recorder_mod", BIN)
    spec = importlib.util.spec_from_loader("recorder_mod", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


class Env(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="recorder-test-")
        self.env = dict(os.environ)
        for k in ("RECORDER_DIR", "RECORDER_NOTES_DIR"):
            self.env.pop(k, None)
        self.env.update({
            "HOME": self.tmp,
            "XDG_DATA_HOME": os.path.join(self.tmp, "data"),
            "XDG_STATE_HOME": os.path.join(self.tmp, "state"),
            "RECORDER_NO_NOTIFY": "1",
            "RECORDER_NO_WORKER": "1",
            "RECORDER_CAPTURE_CMD": FAKE.format(freq=440),
        })
        self._saved = {k: os.environ.get(k) for k in self.env}
        os.environ.update(self.env)
        self.mod = load_module()

    def tearDown(self):
        # Make sure no daemon is left behind.
        st = self.state()
        if st.get("state") in ("recording", "paused"):
            self.run_cli("stop", check=False)
        for k, v in self._saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_cli(self, *args, check=True):
        r = subprocess.run([sys.executable, BIN, *args], env=self.env, capture_output=True, text=True, timeout=60)
        if check and r.returncode != 0:
            self.fail(f"recorder {' '.join(args)} failed {r.returncode}: {r.stderr}")
        return r

    def json_cli(self, *args):
        return json.loads(self.run_cli(*args).stdout)

    def state(self):
        try:
            with open(os.path.join(self.tmp, "state", "recorder", "state.json")) as f:
                return json.load(f)
        except OSError:
            return {}

    def wait_for(self, pred, timeout=5.0):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if pred():
                return True
            time.sleep(0.05)
        return False

    def add_row(self, title="Recording", tags=(), transcript=None, started="2026-10-23T14:05:12+05:00"):
        con = self.mod.connect()
        with con:
            cur = con.execute(
                "INSERT INTO recordings(started_at, ended_at, duration_s, source, format, files, size_bytes, title,"
                " tags, transcript_status, transcript, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (started, started, 12.0, "system", "flac", "[]", 0, title, json.dumps(list(tags)),
                 "done" if transcript else "none", transcript, started, started))
        con.close()
        return cur.lastrowid


class SchemaTests(Env):
    def test_schema_version_and_fts(self):
        con = self.mod.connect()
        self.assertEqual(con.execute("PRAGMA user_version").fetchone()[0], self.mod.SCHEMA_VERSION)
        self.assertEqual(con.execute("PRAGMA journal_mode").fetchone()[0], "wal")
        names = {r[0] for r in con.execute("SELECT name FROM sqlite_master")}
        for n in ("recordings", "settings", "recordings_fts", "recordings_ai", "recordings_ad", "recordings_au"):
            self.assertIn(n, names)
        con.close()
        # Running the migrations again changes nothing.
        con = self.mod.connect()
        self.assertEqual(con.execute("PRAGMA user_version").fetchone()[0], self.mod.SCHEMA_VERSION)
        con.close()

    def test_search_prefix_title_tags_transcript(self):
        a = self.add_row(title="Standup call", transcript="We talked about the quarterly budget.")
        b = self.add_row(title="Music sketch", tags=["guitar"])
        c = self.add_row(title="Interview", transcript="Questions about history and archives.")

        def ids(q):
            return [r["id"] for r in self.json_cli("list", "--json", "--search", q)]

        self.assertEqual(ids("budg"), [a])
        self.assertEqual(ids("guit"), [b])
        self.assertEqual(ids("stand"), [a])
        self.assertEqual(sorted(ids("about")), sorted([a, c]))
        self.assertEqual(ids("about hist"), [c])
        self.assertEqual(ids('"; DROP'), [])

    def test_triggers_follow_rename_tag_and_delete(self):
        a = self.add_row(title="Old name")
        self.run_cli("rename", str(a), "Planning session")
        self.assertEqual(len(self.json_cli("list", "--json", "--search", "plan")), 1)
        self.assertEqual(len(self.json_cli("list", "--json", "--search", "old")), 0)
        self.json_cli("tag", str(a), "work", "q4", "work")
        self.assertEqual(self.json_cli("show", "--json", str(a))["tags"], ["work", "q4"])
        self.assertEqual(len(self.json_cli("list", "--json", "--search", "q4")), 1)
        self.json_cli("untag", str(a), "q4")
        self.assertEqual(len(self.json_cli("list", "--json", "--search", "q4")), 0)
        self.json_cli("delete", str(a))
        self.assertEqual(self.json_cli("list", "--json", "--search", "plan"), [])

    def test_list_day_and_limit(self):
        self.add_row(started="2026-10-22T09:00:00+05:00")
        self.add_row(started="2026-10-23T09:00:00+05:00")
        self.add_row(started="2026-10-23T10:00:00+05:00")
        rows = self.json_cli("list", "--json", "--day", "2026-10-23")
        self.assertEqual([r["started_at"][11:13] for r in rows], ["10", "09"])
        self.assertEqual(len(self.json_cli("list", "--json", "--limit", "1")), 1)
        self.assertNotIn("transcript", rows[0])

    def test_snippet(self):
        words = "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen"
        a = self.add_row(title="Weekly sync", transcript=words + " budget review " + words)
        b = self.add_row(title="Budget planning", transcript="Nothing related in here at all.")
        rows = {r["id"]: r for r in self.json_cli("list", "--json", "--search", "budg")}
        self.assertEqual(set(rows), {a, b})
        snip = rows[a]["snippet"]
        self.assertIn("**budget**", snip)
        self.assertLessEqual(len(snip.replace("...", "").split()), 12)
        self.assertEqual(rows[b]["snippet"], "")
        self.assertNotIn("snippet", self.json_cli("list", "--json")[0])

    def test_stats(self):
        self.assertEqual(self.json_cli("stats", "--json"),
                         {"count": 0, "size_bytes": 0, "total_duration_s": 0, "days": []})
        self.add_row(started="2026-10-22T09:00:00+05:00")
        self.add_row(started="2026-10-23T09:00:00+05:00")
        gone = self.add_row(started="2026-10-23T10:00:00+05:00")
        self.add_row(started="2026-10-23T11:00:00+05:00")
        con = self.mod.connect()
        with con:
            con.execute("UPDATE recordings SET size_bytes=100")
        con.close()
        self.json_cli("delete", str(gone))
        self.assertEqual(self.json_cli("stats", "--json"), {
            "count": 3, "size_bytes": 300, "total_duration_s": 36.0,
            "days": [{"day": "2026-10-23", "count": 2, "duration_s": 24.0},
                     {"day": "2026-10-22", "count": 1, "duration_s": 12.0}]})

    def test_settings(self):
        self.assertEqual(self.json_cli("settings", "--json"),
                         {"default_source": "system", "auto_transcribe_mic": False, "long": False})
        self.run_cli("set", "default_source", "both")
        self.run_cli("set", "auto_transcribe_mic", "true")
        self.run_cli("set", "long", "true")
        self.assertEqual(self.json_cli("settings", "--json"),
                         {"default_source": "both", "auto_transcribe_mic": True, "long": True})
        self.assertNotEqual(self.run_cli("set", "long", "maybe", check=False).returncode, 0)
        self.assertNotEqual(self.run_cli("set", "default_source", "radio", check=False).returncode, 0)
        self.assertNotEqual(self.run_cli("set", "nope", "x", check=False).returncode, 0)


class FileTests(Env):
    def test_file_names(self):
        rd = os.path.join(self.tmp, "Recordings")
        self.assertEqual(self.mod.file_names("2026-10-23_14-05-12", "system", False),
                         {"system": os.path.join(rd, "2026-10-23_14-05-12.flac")})
        self.assertEqual(self.mod.file_names("2026-10-23_14-05-12", "mic", True),
                         {"mic": os.path.join(rd, "2026-10-23_14-05-12.opus")})
        self.assertEqual(self.mod.file_names("2026-10-23_14-05-12", "both", False),
                         {"system": os.path.join(rd, "2026-10-23_14-05-12-system.flac"),
                          "mic": os.path.join(rd, "2026-10-23_14-05-12-mic.flac")})
        os.makedirs(rd)
        open(os.path.join(rd, "2026-10-23_14-05-12.flac"), "w").close()
        self.assertEqual(self.mod.file_names("2026-10-23_14-05-12", "system", False),
                         {"system": os.path.join(rd, "2026-10-23_14-05-12_2.flac")})

    def test_delete_moves_to_trash(self):
        rd = os.path.join(self.tmp, "Recordings")
        os.makedirs(rd)
        f = os.path.join(rd, "2026-10-23_14-05-12.flac")
        with open(f, "wb") as fh:
            fh.write(b"x")
        rid = self.add_row()
        con = self.mod.connect()
        with con:
            con.execute("UPDATE recordings SET files=? WHERE id=?", (json.dumps([f]), rid))
        out = self.json_cli("delete", str(rid))
        trashed = os.path.join(rd, ".trash", "2026-10-23_14-05-12.flac")
        self.assertEqual(out["files"], [trashed])
        self.assertFalse(os.path.exists(f))
        self.assertTrue(os.path.exists(trashed))
        shown = self.json_cli("show", "--json", str(rid))
        self.assertTrue(shown["deleted"])
        self.assertEqual(self.json_cli("list", "--json"), [])
        self.assertNotEqual(self.run_cli("rename", str(rid), "x", check=False).returncode, 0)

    def test_to_notes_refuses_without_transcript(self):
        rid = self.add_row(title="No words yet")
        r = self.run_cli("to-notes", str(rid), check=False)
        self.assertEqual(r.returncode, 3)
        self.assertIn("no transcript", r.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "Notes", "Recordings")))

    def test_to_notes_writes_note(self):
        rid = self.add_row(title="Call with team", tags=["work"], transcript="Hello there.\n")
        out = self.json_cli("to-notes", str(rid))
        self.assertEqual(out["path"], os.path.join(self.tmp, "Notes", "Recordings",
                                                   "2026-10-23_14-05-12-call-with-team.md"))
        with open(out["path"]) as fh:
            text = fh.read()
        self.assertIn("# Call with team", text)
        self.assertIn("Hello there.", text)
        self.assertIn('tags: ["work"]', text)

    def test_transcribe_queues(self):
        rid = self.add_row()
        self.assertEqual(self.json_cli("transcribe", str(rid))["transcript_status"], "queued")
        self.assertEqual(self.json_cli("show", "--json", str(rid))["transcript_status"], "queued")

    def test_keep_ranges(self):
        kr = self.mod.keep_ranges
        self.assertEqual(kr([]), [(0.0, None)])
        self.assertEqual(kr([[1.0, 2.0]]), [(0.0, 1.0), (2.0, None)])
        self.assertEqual(kr([[1.0, 2.0], [3.0, None]]), [(0.0, 1.0), (2.0, 3.0)])
        self.assertEqual(kr([[0.0, 1.0]], duration=1.0), [])
        self.assertEqual(kr([[1.0, 2.0]], duration=2.0), [(0.0, 1.0)])

    def test_finish_track_cuts_and_pads(self):
        os.makedirs(os.path.join(self.tmp, "state", "recorder"))
        src = os.path.join(self.tmp, "src.flac")
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
                        "sine=frequency=440:sample_rate=48000:duration=3", "-c:a", "flac", src], check=True)
        out = os.path.join(self.tmp, "out.flac")
        self.assertIsNone(self.mod.finish_track(src, out, [[1.0, 2.0]], 0.25, False))
        self.assertFalse(os.path.exists(src))
        self.assertAlmostEqual(self.mod.probe_duration(out), 2.25, delta=0.01)

    def test_peaks_slices(self):
        os.makedirs(os.path.join(self.tmp, "state", "recorder"))
        src = os.path.join(self.tmp, "src.flac")
        # 1 s of silence, then 1 s of tone.
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
                        "aevalsrc='if(lt(t,1),0,0.5*sin(2*PI*440*t))':s=48000:d=2", "-c:a", "flac", src],
                       check=True)
        peaks = self.mod.compute_peaks(src)
        self.assertEqual(len(peaks), 30)
        self.assertTrue(all(p < 0.01 for p in peaks[:14]), peaks)
        self.assertTrue(all(abs(p - 0.5) < 0.02 for p in peaks[16:]), peaks)
        self.assertEqual(self.mod.compute_peaks(os.path.join(self.tmp, "missing.flac")), [])

    def test_migration_from_v1(self):
        os.makedirs(os.path.join(self.tmp, "data", "recorder"))
        import sqlite3
        con = sqlite3.connect(os.path.join(self.tmp, "data", "recorder", "recordings.db"))
        con.executescript("BEGIN;" + self.mod.MIGRATIONS[1] + "PRAGMA user_version=1;COMMIT;")
        con.execute("INSERT INTO recordings(started_at, source, format, created_at, updated_at)"
                    " VALUES ('2026-10-23T14:05:12+05:00', 'system', 'flac', 'x', 'x')")
        con.commit()
        con.close()
        row = self.json_cli("show", "--json", "1")
        self.assertEqual(row["peaks"], [])
        con = self.mod.connect()
        self.assertEqual(con.execute("PRAGMA user_version").fetchone()[0], 2)
        con.close()

    def test_level(self):
        self.assertEqual(self.mod.compute_level(b""), 0.0)
        self.assertEqual(self.mod.compute_level(bytes(1600)), 0.0)
        loud = array.array("h", [20000, -20000] * 400).tobytes()
        self.assertGreater(self.mod.compute_level(loud), 0.9)
        quiet = array.array("h", [30, -30] * 400).tobytes()
        self.assertLess(self.mod.compute_level(quiet), 0.2)


class CaptureTests(Env):
    def test_start_pause_resume_stop(self):
        t0 = time.monotonic()
        out = self.json_cli("start")
        self.assertLess(time.monotonic() - t0, 0.5)
        self.assertEqual(out["source"], "system")
        self.assertEqual(self.state()["state"], "recording")
        # Second start is refused while one runs.
        self.assertEqual(self.run_cli("start", check=False).returncode, 2)
        self.assertTrue(self.wait_for(lambda: self.state().get("level", 0) > 0.3), "level never moved")
        updated = self.state()["updated"]
        self.assertTrue(self.wait_for(lambda: self.state()["updated"] > updated, 1.0), "state not refreshed")

        time.sleep(0.6)
        self.assertEqual(self.json_cli("pause")["state"], "paused")
        st = self.state()
        self.assertEqual(st["level"], 0.0)
        frozen = st["elapsed_s"]
        time.sleep(0.4)
        self.assertEqual(self.json_cli("status", "--json")["elapsed_s"], frozen)
        self.assertEqual(self.json_cli("resume")["state"], "recording")
        time.sleep(0.8)
        stopped = self.json_cli("stop")
        st = self.state()
        self.assertEqual(st["state"], "idle")
        self.assertEqual(st["id"], stopped["id"])

        row = self.json_cli("show", "--json", str(stopped["id"]))
        self.assertEqual(row["format"], "flac")
        self.assertEqual(len(row["files"]), 1)
        f = row["files"][0]
        self.assertRegex(os.path.basename(f), r"^\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d\.flac$")
        self.assertTrue(os.path.getsize(f) > 0)
        self.assertEqual(row["size_bytes"], os.path.getsize(f))
        self.assertGreater(row["duration_s"], 1.0)
        self.assertTrue(re.match(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d$", row["started_at"]))
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "Recordings", ".parts")))
        self.assertEqual(self.run_cli("stop", check=False).returncode, 2)

    def test_two_tracks_opus(self):
        self.json_cli("start", "--source", "both", "--long")
        self.assertTrue(self.wait_for(lambda: self.state().get("level", 0) > 0.3))
        time.sleep(0.5)
        row = self.json_cli("show", "--json", str(self.json_cli("stop")["id"]))
        names = sorted(os.path.basename(f) for f in row["files"])
        self.assertEqual(len(names), 2)
        self.assertTrue(names[0].endswith("-mic.opus") and names[1].endswith("-system.opus"))
        self.assertEqual(names[0][:19], names[1][:19])
        self.assertEqual(row["source"], "both")
        self.assertEqual(row["format"], "opus")

    def probe(self, f):
        r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                            "-of", "default=nw=1:nk=1", f], capture_output=True, text=True)
        return float(r.stdout)

    def pause_cycle_both(self, *extra):
        t0 = time.monotonic()
        self.json_cli("start", "--source", "both", *extra)
        self.assertTrue(self.wait_for(lambda: self.state().get("level", 0) > 0.3))
        time.sleep(0.6)
        for _ in range(3):
            self.assertEqual(self.json_cli("pause")["state"], "paused")
            time.sleep(0.4)
            self.assertEqual(self.json_cli("resume")["state"], "recording")
            time.sleep(0.4)
        row = self.json_cli("show", "--json", str(self.json_cli("stop")["id"]))
        wall = time.monotonic() - t0
        self.assertIsNone(row["error"])
        lengths = [self.probe(f) for f in row["files"]]
        self.assertEqual(len(lengths), 2)
        self.assertLess(abs(lengths[0] - lengths[1]), 0.05, lengths)
        # 1.2 s of the run was paused and has to be gone, at least 1.8 s was recorded.
        self.assertGreater(min(lengths), 1.7, lengths)
        self.assertLess(max(lengths), wall - 1.0, (lengths, wall))
        return row

    def test_pause_keeps_tracks_aligned_flac(self):
        row = self.pause_cycle_both()
        for f in row["files"]:
            r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_name",
                                "-of", "default=nw=1:nk=1", f], capture_output=True, text=True)
            self.assertEqual(r.stdout.strip(), "flac")

    def test_pause_keeps_tracks_aligned_opus(self):
        self.pause_cycle_both("--long")

    def test_stop_while_paused(self):
        t0 = time.monotonic()
        self.json_cli("start")
        time.sleep(0.8)
        self.json_cli("pause")
        before_pause = time.monotonic() - t0
        time.sleep(1.0)
        row = self.json_cli("show", "--json", str(self.json_cli("stop")["id"]))
        self.assertIsNone(row["error"])
        # The fake source runs a little ahead of the clock, the paused second must be gone.
        self.assertLess(self.probe(row["files"][0]), before_pause + 0.5)

    def test_capture_that_dies_is_still_saved(self):
        self.env["RECORDER_CAPTURE_CMD"] = FAKE.format(freq=440) + ":duration=0.6"
        self.json_cli("start")
        self.assertTrue(self.wait_for(lambda: self.state().get("state") == "idle" and self.state().get("id"), 10))
        rows = self.json_cli("list", "--json")
        self.assertEqual(len(rows), 1)
        self.assertGreater(rows[0]["duration_s"], 0.4)

    def test_peaks(self):
        self.json_cli("start")
        self.assertTrue(self.wait_for(lambda: self.state().get("level", 0) > 0.3))
        time.sleep(0.6)
        rid = self.json_cli("stop")["id"]
        peaks = self.json_cli("show", "--json", str(rid))["peaks"]
        self.assertEqual(len(peaks), 30)
        # ffmpeg's sine tone peaks at 1/8 of full scale.
        for p in peaks:
            self.assertAlmostEqual(p, 0.125, delta=0.01)
        self.assertEqual(self.json_cli("list", "--json")[0]["peaks"], peaks)

    def test_long_setting_and_override(self):
        self.run_cli("set", "long", "true")
        out = self.json_cli("start")
        self.assertTrue(out["long"])
        self.assertTrue(self.state()["long"])
        time.sleep(0.5)
        row = self.json_cli("show", "--json", str(self.json_cli("stop")["id"]))
        self.assertEqual(row["format"], "opus")
        self.assertTrue(row["files"][0].endswith(".opus"))
        self.assertFalse(self.json_cli("toggle", "--no-long")["long"])
        time.sleep(0.5)
        row = self.json_cli("show", "--json", str(self.json_cli("toggle")["id"]))
        self.assertEqual(row["format"], "flac")
        self.run_cli("set", "long", "false")
        self.assertTrue(self.json_cli("start", "--long")["long"])
        time.sleep(0.5)
        row = self.json_cli("show", "--json", str(self.json_cli("stop")["id"]))
        self.assertEqual(row["format"], "opus")

    def test_levels_per_track(self):
        self.json_cli("start", "--source", "both")
        self.assertTrue(self.wait_for(lambda: min(self.state().get("levels", {"x": 0}).values()) > 0.3))
        st = self.state()
        self.assertEqual(set(st["levels"]), {"system", "mic"})
        self.assertEqual(st["level"], max(st["levels"].values()))
        self.json_cli("pause")
        self.assertEqual(self.state()["levels"], {"system": 0.0, "mic": 0.0})
        self.json_cli("stop")
        self.assertEqual(self.state()["levels"], {})

    def test_toggle_and_default_source(self):
        self.run_cli("set", "default_source", "mic")
        self.assertEqual(self.json_cli("toggle")["source"], "mic")
        self.assertEqual(self.json_cli("status", "--json")["state"], "recording")
        time.sleep(0.6)
        rid = self.json_cli("toggle")["id"]
        self.assertEqual(self.json_cli("show", "--json", str(rid))["source"], "mic")

    def test_auto_transcribe_mic(self):
        self.run_cli("set", "auto_transcribe_mic", "true")
        self.json_cli("start", "--source", "mic")
        time.sleep(0.6)
        rid = self.json_cli("stop")["id"]
        self.assertEqual(self.json_cli("show", "--json", str(rid))["transcript_status"], "queued")

    def test_stale_state_reads_idle(self):
        os.makedirs(os.path.join(self.tmp, "state", "recorder"))
        with open(os.path.join(self.tmp, "state", "recorder", "state.json"), "w") as f:
            json.dump({"state": "recording", "pid": 999999, "id": None}, f)
        self.assertEqual(self.json_cli("status", "--json")["state"], "idle")


if __name__ == "__main__":
    unittest.main()
