# recorder

Records system sound, the mic, or both on the desktop, and keeps a library of what was recorded. Files are named by start time, a SQLite database indexes them, and titles, tags and transcripts can be searched. The bar button and library panel live in `noctalia-glow-plugins/glow-record`.

It needs Python 3 (standard library only), `ffmpeg`, `ffprobe` and `pactl` (PipeWire with its Pulse layer), and `notify-send` for the saved card.

## Install

```sh
./install.sh
```

`install.sh` links `recorder` into `~/.local/bin` and creates `~/Recordings`, its `.trash` folder and the data and state folders. It starts nothing. Run it again any time.

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
```

Each row has `peaks`, 30 values from 0 to 1 for the library's waveform. They are the loudest sample in each of 30 equal slices of the saved audio, taken from the louder track of a two track recording.

`--search` matches the start of each word you type, in titles, tags and transcripts. Every word has to match. `list --json` leaves the transcript text out and says `has_transcript` instead, `show` has the full row. With `--search`, each row also has `snippet`: about 12 words of the transcript around the match, with the match in `**bold**`. It is empty when only the title or tags matched.

`stats --json` gives `count`, `size_bytes`, `total_duration_s` and `days` (each with `day`, `count` and `duration_s`) for recordings that are not deleted.

`to-notes` writes `~/Notes/Recordings/<start>-<title>.md` with the date, length, source and tags at the top. It exits with code 3 when the recording has no transcript yet.

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

## How capture works

Each track is one `ffmpeg -f pulse` process. System sound comes from the default output's monitor and the mic from the default input, both looked up with `pactl` when the recording starts. The same ffmpeg also writes a small 8 kHz mono copy to a pipe, which the recorder reads to work out the level, so there is no second capture.

The captures keep running through a pause, so the devices are never closed and opened again. The recorder notes where each pause starts and ends in every track, counted in samples from the level copy, which runs on the same clock as the file. On stop it cuts those spans out of each track with ffmpeg. FLAC is decoded and encoded again for the cut, which stays lossless, and Opus is encoded once more. A recording without pauses is only moved into place. A device that started later than the other gets that much silence at its start, so both tracks of a two track recording share one timeline. ffmpeg finishes each file on SIGINT, so a stopped file is always complete. If a capture dies, what it wrote is still saved.

`stop` sends SIGTERM to the recording process, `pause` SIGUSR1 and `resume` SIGUSR2. Its pid is in the state file and it holds `~/.local/state/recorder/recording.lock` for as long as it runs.

## Tests

```sh
python3 -m unittest discover -s tests
```

The tests use a temporary home folder and replace the capture with a sine tone from ffmpeg (`RECORDER_CAPTURE_CMD` holds the ffmpeg input arguments, and `{track}` in it becomes `system` or `mic`). `RECORDER_NO_NOTIFY=1` skips the card and `RECORDER_NO_WORKER=1` skips waking the transcription worker.
