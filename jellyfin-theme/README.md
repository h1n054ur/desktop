# jellyfin-theme

The h1n054ur look for [Jellyfin](https://jellyfin.org) 10.11: a dark green-to-cyan theme with a glowing wordmark, built on top of one of two base themes: [ElegantFin](https://github.com/lscambo13/ElegantFin) or Abyss (the floating side pill look). Both bases share the palette, the wordmark, the login button and the splash. Each base ships as one CSS file that goes into Jellyfin's custom CSS setting. The base themes and the fonts are vendored at a pinned version, so the theme never loads anything from the internet when a page opens.

## Layout

| Path | What it is |
|---|---|
| `src/common/` | shared by both bases: `00-palette.css` (the `--h1-*` colour tokens), `10-logo.css` (wordmark and mark), `login-disclaimer.html` (the "Sign in with Authentik" button) |
| `src/elegantfin/` | ElegantFin only: `05-elegantfin-vars.css` (tokens written onto ElegantFin's variables), `15-login-wordmark.css`, `20-login.css`, `30-home.css`, `90-overrides.css` (small fixes, last so they win) |
| `src/abyss/` | Abyss only, same roles plus `40-side-pill.css`, `50-detail.css` (detail pages and the search page), `60-menus.css` (action sheets, multi-select bar, header title and the fade above the header), `70-browse.css` (card titles, home rows, pill and drawer active state, sort and filter dialogs, empty states, A to Z picker) and `80-player-forms.css` (pill and header hidden while a video loads, player title and time fixes, user settings forms, login header). The admin dashboard is out of reach: Jellyfin 10.11 does not load the server's custom CSS there. Placeholders for now (#299) |
| `vendor/elegantfin/` | ElegantFin's CSS at a pinned commit |
| `vendor/abyss/` | Abyss's CSS at a pinned commit |
| `vendor/fonts/` | font CSS (Cascadia Code, used for accents only) and its font files |
| `vendor/VERSIONS` | where each vendored piece came from and at which commit or release |
| `vendor/update.sh` | fetches ElegantFin and the fonts again at a given commit and rebuilds (see below) |
| `assets/` | the wordmark and splash images |
| `dist/theme-elegantfin.css`, `dist/theme-abyss.css` | the built themes, committed: `apply.sh` sends one of them to Jellyfin |
| `backup/` | the custom CSS that was on the server before an apply, for `rollback.sh` |
| `build.sh` | builds `dist/theme-<base>.css` and checks it |
| `apply.sh`, `rollback.sh` | put the theme on a Jellyfin server, or take it off again |

## Build

```sh
./build.sh                      # writes dist/theme-elegantfin.css (elegantfin is the default base)
./build.sh --base abyss         # writes dist/theme-abyss.css
./build.sh --check              # fails if either dist file is out of date, then lints both
./build.sh --base abyss --check # checks one base only
```

`build.sh` joins the files for a base in a fixed order: `vendor/<base>/*.css`, then `vendor/fonts/*.css`, then `src/common/*.css` and `src/<base>/*.css` merged by file name, so the number prefix decides the order across both folders (common first on a tie, and the same name in both folders is an error). The header of each dist file names its base and lists the pins from `vendor/VERSIONS`. It runs from any directory. While `vendor/abyss/` is still empty, the Abyss build warns and goes ahead with `src/` only.

`--check` rebuilds into a temporary file and compares it with the committed dist file, so a change to `src/` or `vendor/` without a rebuild fails. It then runs a small lint written in awk: braces have to balance, comments and strings have to close, and no `@import` or `url()` may point at an outside address. The lint needs nothing installed. Stylelint would catch more, but it means pulling a Node toolchain into every check for a file that is mostly vendored CSS, and the faults that matter here (a broken brace that hides the rest of the file, a font loaded from a CDN) are covered by the small check.

Edit `src/`, never `dist/`. After every change run `./build.sh` for each base it touches (a change in `src/common/` touches both) and commit the source and the dist files together.

## Updating the vendored theme

```sh
vendor/update.sh <elegantfin-commit> [cascadia-version]
# for example, the current pin:
vendor/update.sh 5efc1105e9a56424d2252d73c04cafe484fb9e92 5.3.0
```

The first argument is a full commit sha from [lscambo13/ElegantFin](https://github.com/lscambo13/ElegantFin) (pick the commit of a release). The second is the [`@fontsource/cascadia-code`](https://www.npmjs.com/package/@fontsource/cascadia-code) version and defaults to 5.3.0. The script needs bash, curl and python3 with nothing extra installed. `update.py` next to it does the work.

What it does:

1. Downloads ElegantFin's minified build, LICENSE and README at that commit.
2. Swaps the Google Fonts `@import` for Inter (latin, normal style) as an inline data URI, inlines the "Material Symbols Rounded Minimal" icon subset the same way, drops the 5.3 MB full Material Symbols face and points `--iconPack` at the Minimal subset. It stops if any of these no longer match upstream exactly once.
3. Builds `vendor/fonts/cascadia-code.css` from the npm tarball: Cascadia Code latin 400 and 700 as data URIs.
4. Checks every download: Inter and the two font licenses against sha256 values pinned in `update.py`, the Cascadia tarball against the npm registry's sha512 integrity. If the commit and Cascadia version are the ones already in `VERSIONS`, every size and hash has to match the committed ones or nothing is written.
5. Writes `vendor/elegantfin/`, `vendor/fonts/` and a new `vendor/VERSIONS`, then runs `build.sh`.

Review the diff (`VERSIONS` shows what moved), look at the theme on a test server, and commit `vendor/` and `dist/` together. The script rebuilds both bases, since `VERSIONS` goes into every header. If upstream changed how it loads fonts, the script stops with a message naming the step, and `update.py` needs a matching change.

## Apply and roll back

Both scripts talk to the Jellyfin 10.11 API and need `curl` and `jq`. They read the server and an admin API key from the environment. The key is written to a header file only the current user can read, so it never shows up in a process list.

```sh
export JELLYFIN_URL=https://jellyfin.example.com   # the server itself, see below
export JELLYFIN_API_KEY=...                         # Dashboard > API Keys
export JELLYFIN_THEME_BACKUP_DIR=~/jellyfin-branding-backups
export SERVER_NAME=h1n054ur                         # optional, this is the default
export BASE=elegantfin                              # optional, elegantfin (default) or abyss

./apply.sh --dry-run   # print the plan and sizes, contact nothing
./apply.sh             # back up, apply, read back
./rollback.sh          # put the backup back, read back
```

`apply.sh` does, in order:

1. Runs `build.sh --base $BASE --check` and stops if `dist/theme-$BASE.css` is stale or fails the lint. It also needs `src/common/login-disclaimer.html` and `assets/splash.png`.
2. Saves the current branding (custom CSS, login disclaimer, splash switch), the server name and any custom splash image to `$JELLYFIN_THEME_BACKUP_DIR/pre-apply-<UTC time>.json` (and `-splash.png`). Without that folder it refuses, unless you pass `--no-backup`.
3. Posts the branding: `CustomCss` from `dist/theme-$BASE.css`, `LoginDisclaimer` from `src/common/login-disclaimer.html` (this keeps the "Sign in with Authentik" button), splash screen on.
4. Uploads `assets/splash.png` to `/Branding/Splashscreen`. Jellyfin wants the image base64 encoded with `Content-Type: image/png`.
5. Sets the server name: reads the whole server configuration, changes `ServerName` only and writes it back.
6. Reads everything back and compares sha256 hashes with what it sent. A mismatch exits non-zero. The splash is reported but not failed on a different hash, since the server may re-encode it on the way out.

To switch from one base to the other, run `apply.sh` again with the other `BASE`. Going back to ElegantFin is `BASE=elegantfin ./apply.sh`, and going back to the branding from before the theme is `rollback.sh`.

The branding body is about 440 KB, so `JELLYFIN_URL` should point at Jellyfin directly (or at a proxy that allows a body that size), not through one with a small upload limit.

`rollback.sh [--dry-run] [SOURCE]` restores from either layout:

- a `pre-apply-<time>.json` written by `apply.sh` (the newest one in `$JELLYFIN_THEME_BACKUP_DIR` when no SOURCE is given)
- a snapshot folder holding `branding.json` (`LoginDisclaimer`, `CustomCss`, `SplashscreenEnabled`), `server-name.txt`, and optionally `custom.css`, `login-disclaimer.html` and `splash.png`. When `$JELLYFIN_THEME_BACKUP_DIR` itself holds a `branding.json`, it is used as such a folder. Loose copies have to match `branding.json` or the script stops.

It posts the branding back, re-uploads the backed-up splash or deletes the custom one when the backup had none, restores the server name and reads it all back the same way.

Backups can hold the login disclaimer, which may name private addresses, so keep `$JELLYFIN_THEME_BACKUP_DIR` outside this repo (see `backup/README.md`). After an apply or a rollback, a browser reload shows the change.
