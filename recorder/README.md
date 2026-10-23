# recorder

Records system sound, the mic, or both on the desktop, and keeps a library of what was recorded. Files are named by start time, a SQLite database indexes them, and titles, tags and transcripts can be searched. The bar button and library panel live in `noctalia-glow-plugins/glow-record`.

It needs Python 3 (standard library only), `ffmpeg`, `ffprobe` and `pactl` (PipeWire with its Pulse layer), and `notify-send` for the saved card. The library panel plays recordings with `mpv`.

## Install

```sh
./install.sh
```

`install.sh` links `recorder`, `recorder-worker` and `recorder-player` into `~/.local/bin`, links the worker's user unit into `~/.config/systemd/user` and reloads systemd, and creates `~/Recordings`, its `.trash` folder and the data and state folders. It never enables or starts anything. Run it again any time.

## Use

```sh
recorder start                  # system sound, FLAC
recorder start --source mic     # the mic only
recorder start --source both    # system and mic as two separate files
recorder start --long           # Opus instead of FLAC, for long recordings
recorder start --no-long        # FLAC even when the long setting is on
recorder pause | resume | stop
recorder toggle                 # start or stop, for the keybind
recorder status --json
```

`start` returns at once and the recording runs in its own process. Only one recording runs at a time, a second `start` exits with code 2. `stop` waits until the files are written and prints the new recording's id. A card then says the recording is saved and how long it is, with Transcribe and Open buttons.

Without `--source`, `start` uses the `default_source` setting. Without `--long` or `--no-long` it uses the `long` setting. `toggle` takes the same options.

```sh
recorder list --json [--search WORDS] [--day 2026-10-23] [--limit 20]
recorder show --json ID
recorder stats --json           # totals and a count per day
recorder rename ID "Call with the team"
recorder tag ID work q4
recorder untag ID q4
recorder delete ID              # moves the files to ~/Recordings/.trash
recorder transcribe ID          # queues it for the transcription worker
recorder to-notes ID            # writes the transcript as a note
recorder library                # opens the library panel
recorder settings --json
recorder set default_source both
recorder set auto_transcribe_mic true
recorder set long true
recorder set transcribe_model small   # tiny, base, small, medium, large-v3, large-v3-turbo
recorder devices --json         # mic inputs: name, description, is_default
recorder devices --json --sinks # outputs, for sink_device
recorder set mic_device alsa_input.usb-ABC_MIC_TEST-00.analog-stereo
recorder set mic_device default
recorder set sink_device default
```

`mic_device` picks the mic by its PipeWire node name, as `devices` shows it. `default` follows the system's default input, which is also what happens when the setting is unset. `sink_device` does the same for system sound, which is then taken from that output's monitor. A device can be chosen while it is unplugged. If the chosen device is not there when a recording starts, the recorder uses the system default and says so in the recording's `error` field, for example `mic device ... not found, used the system default`. `devices --json` leaves out monitor sources. The library panel's Mic select uses it.

Each row has `peaks`, 30 values from 0 to 1 for the library's waveform. They are the loudest sample in each of 30 equal slices of the saved audio, taken from the louder track of a two track recording.

`--search` matches the start of each word you type, in titles, tags and transcripts. Every word has to match. `list --json` leaves the transcript text out and says `has_transcript` instead, `show` has the full row. With `--search`, each row also has `snippet`: about 12 words of the transcript around the match, with the match in `**bold**`. It is empty when only the title or tags matched.

`stats --json` gives `count`, `size_bytes`, `total_duration_s` and `days` (each with `day`, `count` and `duration_s`) for recordings that are not deleted.

`to-notes` writes `~/Notes/Recordings/<start>-<title>.md` with the title, date, length, source, tags, audio paths and model at the top, then the transcript. It exits with code 3 when the recording has no transcript yet.

`show`, `rename`, `tag`, `untag`, `delete`, `transcribe` and `to-notes` exit with code 1 when there is no such recording and code 4 when it was deleted, and then change nothing. So a saved card whose recording was deleted since does nothing when you press Transcribe.

With `auto_transcribe_mic` on, recordings that include the mic are queued for transcription as soon as they stop.

## Files

- Recordings: `~/Recordings/2026-10-23_14-05-12.flac`, or `.opus` with `--long`. Two tracks get `-system` and `-mic` at the end of the name.
- Database: `~/.local/share/recorder/recordings.db` (SQLite in WAL mode). One row per recording, an FTS5 index over title, tags and transcript, and a `settings` table. The schema version is kept in `PRAGMA user_version`.
- State for the bar: `~/.local/state/recorder/state.json`, replaced in one step each time:

```json
{"state": "recording", "id": null, "started_at": "2026-10-23T14:05:12+05:00", "elapsed_s": 12.3,
 "source": "both", "level": 0.42, "levels": {"system": 0.42, "mic": 0.18}, "long": false,
 "updated": 1792738030.6}
```

While recording it is written about ten times a second. `levels` has one value from 0 to 1 per track and `level` is the larger one. When idle, `id` is the last saved recording. A state file left behind by a crashed recording reads as idle.

- Log of the recording process: `~/.local/state/recorder/daemon.log`.

## Transcription

`recorder transcribe ID` marks the row `queued` and starts `recorder-worker.service` if the unit is installed. The worker takes queued rows in id order, one at a time, and exits when none are left. Only one worker runs at a time (it holds `~/.local/state/recorder/worker.lock`), and a row left `running` by a worker that died is queued again on the next start. Before it exits, the worker looks at the queue one last time under `queue.lock` and lets go of `worker.lock` while it still holds `queue.lock`. `transcribe` queues under the same lock, so a row queued at the last moment is either seen by that worker or finds no worker in its loop, and then `transcribe` runs `systemctl --user restart --no-block` (a plain `start` does nothing while the old run is still exiting).

It runs with the WhisperX venv's python (`~/.local/share/uv/tools/whisperx/bin/python`, or `RECORDER_WORKER_PYTHON`) and re-executes itself there. Each file is decoded with ffmpeg to 16 kHz mono and transcribed with faster-whisper, the model from the `transcribe_model` setting (default `small`), on the GPU in int8 with the CPU as fallback. The language is detected and silence is skipped. A recording with no speech ends `done` with an empty transcript. Two-track recordings are transcribed track by track and merged by time, each line labelled `System` or `Mic`.

The transcript is one line per segment, `[mm:ss] text` (or `[h:mm:ss]` past an hour). The row then gets `transcript_status` `done` and `transcript_model`, or `failed` with the reason in `error`. A card says "Transcript ready" with an Open button that opens the library.

While a row runs, `~/.local/state/recorder/worker.json` holds `{"id": 3, "progress": 42, "eta_s": 18.5, "updated": ...}`, progress 0 to 100, replaced in one step. The file is gone when the worker is idle.

The unit runs at low CPU and IO priority, with `MemoryMax=6G`, and never restarts on its own.

## Playback

The library panel plays a recording in place through `recorder-player`, a small wrapper around `mpv --no-video` with an IPC socket.

```sh
recorder-player play FILE [FILE2]   # prints {"pos": 12.3, "dur": 48.0, "paused": false} per change, then {"end": true}
recorder-player pause               # pause or resume
recorder-player seek SECONDS
recorder-player stop
```

Two files, the system and mic tracks, play mixed together. Only one player runs at a time, `play` stops any earlier one first.

## How capture works

Each track is one `ffmpeg -f pulse` process. System sound comes from the default output's monitor (or the `sink_device` output's) and the mic from the default input (or `mic_device`), both looked up with `pactl` when the recording starts. The same ffmpeg also writes a small 8 kHz mono copy to a pipe, which the recorder reads to work out the level, so there is no second capture.

The captures keep running through a pause, so the devices are never closed and opened again. The recorder notes where each pause starts and ends in every track, counted in samples from the level copy, which runs on the same clock as the file. On stop it cuts those spans out of each track with ffmpeg. FLAC is decoded and encoded again for the cut, which stays lossless, and Opus is encoded once more. A recording without pauses is only moved into place. A device that started later than the other gets that much silence at its start, so both tracks of a two track recording share one timeline. ffmpeg finishes each file on SIGINT, so a stopped file is always complete. If a capture dies, what it wrote is still saved.

`stop` sends SIGTERM to the recording process, `pause` SIGUSR1 and `resume` SIGUSR2. Its pid is in the state file and it holds `~/.local/state/recorder/recording.lock` for as long as it runs.

## Tests

```sh
python3 -m unittest discover -s tests
```

The tests use a temporary home folder and replace the capture with a sine tone from ffmpeg (`RECORDER_CAPTURE_CMD` holds the ffmpeg input arguments, and `{track}` in it becomes `system` or `mic`). `RECORDER_PACTL` replaces the `pactl` command, which the device tests point at a small script with canned output. `RECORDER_NO_NOTIFY=1` skips the cards and `RECORDER_NO_WORKER=1` skips waking the transcription worker. The worker tests set `RECORDER_FAKE_TRANSCRIBE=1`, which swaps the model for canned segments, so they need no GPU or venv. `RECORDER_FAKE_DELAY` slows each segment down to watch the progress file, `RECORDER_FAKE_FINAL_PAUSE=before:S` or `inside:S` holds the worker in its final check, and `RECORDER_WORKER_START_CMD` replaces the systemctl call.
