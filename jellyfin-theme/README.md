# jellyfin-theme

The h1n054ur look for [Jellyfin](https://jellyfin.org) 10.11: a dark green-to-cyan theme with a glowing wordmark, built on top of [ElegantFin](https://github.com/lscambo13/ElegantFin). Everything ships in one CSS file that goes into Jellyfin's custom CSS setting. ElegantFin and the fonts are vendored at a pinned version, so the theme never loads anything from the internet when a page opens.

## Layout

| Path | What it is |
|---|---|
| `src/` | our own CSS, loaded after ElegantFin in file name order: `00-palette.css` (colours), `10-logo.css` (wordmark), `20-login.css` (login page), `90-overrides.css` (small fixes, last so they win) |
| `vendor/elegantfin/` | ElegantFin's CSS at a pinned commit |
| `vendor/fonts/` | font CSS (Cascadia Code, used for accents only) and its font files |
| `vendor/VERSIONS` | where each vendored piece came from and at which commit or release |
| `assets/` | the wordmark and splash images |
| `dist/theme.css` | the built theme, committed: this is what `apply.sh` sends to Jellyfin |
| `backup/` | the custom CSS that was on the server before an apply, for `rollback.sh` |
| `build.sh` | builds `dist/theme.css` and checks it |
| `apply.sh`, `rollback.sh` | put the theme on a Jellyfin server, or take it off again |

## Build

```sh
./build.sh           # writes dist/theme.css
./build.sh --check   # fails if dist/theme.css is out of date, then lints it
```

`build.sh` joins the files in a fixed order: `vendor/elegantfin/*.css`, then `vendor/fonts/*.css`, then `src/*.css`. The header of `dist/theme.css` lists the pins from `vendor/VERSIONS`. It runs from any directory.

`--check` rebuilds into a temporary file and compares it with the committed `dist/theme.css`, so a change to `src/` or `vendor/` without a rebuild fails. It then runs a small lint written in awk: braces have to balance, comments and strings have to close, and no `@import` or `url()` may point at an outside address. The lint needs nothing installed. Stylelint would catch more, but it means pulling a Node toolchain into every check for a file that is mostly vendored CSS, and the faults that matter here (a broken brace that hides the rest of the file, a font loaded from a CDN) are covered by the small check.

Edit `src/`, never `dist/theme.css`. After every change run `./build.sh` and commit both.

## Apply and roll back

Both scripts talk to the Jellyfin 10.11 API and need `curl` and `jq`. They read the server and an admin API key from the environment. The key is written to a header file only the current user can read, so it never shows up in a process list.

```sh
export JELLYFIN_URL=https://jellyfin.example.com   # the server itself, see below
export JELLYFIN_API_KEY=...                         # Dashboard > API Keys
export JELLYFIN_THEME_BACKUP_DIR=~/jellyfin-branding-backups
export SERVER_NAME=h1n054ur                         # optional, this is the default

./apply.sh --dry-run   # print the plan and sizes, contact nothing
./apply.sh             # back up, apply, read back
./rollback.sh          # put the backup back, read back
```

`apply.sh` does, in order:

1. Runs `build.sh --check` and stops if `dist/theme.css` is stale or fails the lint. It also needs `src/login-disclaimer.html` and `assets/splash.png`.
2. Saves the current branding (custom CSS, login disclaimer, splash switch), the server name and any custom splash image to `$JELLYFIN_THEME_BACKUP_DIR/pre-apply-<UTC time>.json` (and `-splash.png`). Without that folder it refuses, unless you pass `--no-backup`.
3. Posts the branding: `CustomCss` from `dist/theme.css`, `LoginDisclaimer` from `src/login-disclaimer.html` (this keeps the "Sign in with Authentik" button), splash screen on.
4. Uploads `assets/splash.png` to `/Branding/Splashscreen`. Jellyfin wants the image base64 encoded with `Content-Type: image/png`.
5. Sets the server name: reads the whole server configuration, changes `ServerName` only and writes it back.
6. Reads everything back and compares sha256 hashes with what it sent. A mismatch exits non-zero. The splash is reported but not failed on a different hash, since the server may re-encode it on the way out.

The branding body is about 440 KB, so `JELLYFIN_URL` should point at Jellyfin directly (or at a proxy that allows a body that size), not through one with a small upload limit.

`rollback.sh [--dry-run] [SOURCE]` restores from either layout:

- a `pre-apply-<time>.json` written by `apply.sh` (the newest one in `$JELLYFIN_THEME_BACKUP_DIR` when no SOURCE is given)
- a snapshot folder holding `branding.json` (`LoginDisclaimer`, `CustomCss`, `SplashscreenEnabled`), `server-name.txt`, and optionally `custom.css`, `login-disclaimer.html` and `splash.png`. When `$JELLYFIN_THEME_BACKUP_DIR` itself holds a `branding.json`, it is used as such a folder. Loose copies have to match `branding.json` or the script stops.

It posts the branding back, re-uploads the backed-up splash or deletes the custom one when the backup had none, restores the server name and reads it all back the same way.

Backups can hold the login disclaimer, which may name private addresses, so keep `$JELLYFIN_THEME_BACKUP_DIR` outside this repo (see `backup/README.md`). After an apply or a rollback, a browser reload shows the change.
