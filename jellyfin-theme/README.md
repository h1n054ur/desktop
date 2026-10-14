# jellyfin-theme

The h1n054ur look for [Jellyfin](https://jellyfin.org) 10.11: a dark green-to-cyan theme with a glowing wordmark, built on top of [ElegantFin](https://github.com/lscambo13/ElegantFin). Everything ships in one CSS file that goes into Jellyfin's custom CSS setting. ElegantFin and the fonts are vendored at a pinned version, so the theme never loads anything from the internet when a page opens.

## Layout

| Path | What it is |
|---|---|
| `src/` | our own CSS, loaded after ElegantFin in file name order: `00-palette.css` (colours), `10-logo.css` (wordmark), `20-login.css` (login page), `90-overrides.css` (small fixes, last so they win) |
| `vendor/elegantfin/` | ElegantFin's CSS at a pinned commit |
| `vendor/fonts/` | font CSS (Cascadia Code, used for accents only) and its font files |
| `vendor/VERSIONS` | where each vendored piece came from and at which commit or release |
| `vendor/update.sh` | fetches ElegantFin and the fonts again at a given commit and rebuilds (see below) |
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

Review the diff (`VERSIONS` shows what moved), look at the theme on a test server, and commit `vendor/` and `dist/theme.css` together. If upstream changed how it loads fonts, the script stops with a message naming the step, and `update.py` needs a matching change.

## Apply and roll back

Both scripts read the server and an admin API key from the environment:

```sh
export JELLYFIN_URL=https://jellyfin.example.com
export JELLYFIN_API_KEY=...        # Dashboard > API Keys

./apply.sh      # saves the current custom CSS to backup/, then sets it to dist/theme.css
./rollback.sh   # puts the CSS from backup/ back
```

The theme goes into the Custom CSS setting on the dashboard's Branding page. A browser reload shows it.
