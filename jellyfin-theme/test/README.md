# Test Jellyfin

A throwaway Jellyfin for looking at the theme before it goes near a real server. It runs on your own machine, listens on `127.0.0.1:8097` only, and is never deployed anywhere.

It uses the same Jellyfin release as the real server (10.11.11, pinned by digest), so the web client the theme styles is the same one. The container is capped at 1 GB of memory.

## Up and seed

```sh
./seed.sh
```

`seed.sh` does everything and is safe to run again:

1. downloads four free films and two episodes of a short series (Big Buck Bunny, Sintel, Tears of Steel, Charlie Chaplin's The Count, Caminandes) into `~/.cache/jellyfin-theme-test/media`, about 270 MB, outside the repo
2. starts the container with `compose.yaml`
3. finishes the setup wizard with an admin user `test` and a random password in `~/.cache/jellyfin-theme-test/admin.txt` (mode 600)
4. names the server `h1n054ur`, adds the Movies and Shows libraries, scans them (posters come from the files' folders or from Jellyfin's usual metadata sources)
5. creates an API key in `~/.cache/jellyfin-theme-test/apikey` (mode 600)
6. marks one film half watched, so the home page shows "Continue watching"

Then open <http://127.0.0.1:8097>. The password is throwaway and stays out of the vault.

To put the theme on it:

```sh
JELLYFIN_URL=http://127.0.0.1:8097 JELLYFIN_API_KEY=$(cat ~/.cache/jellyfin-theme-test/apikey) ../apply.sh
```

## Down

```sh
docker compose -f compose.yaml down        # stop, keep the seeded server
docker compose -f compose.yaml down -v     # also drop its config and cache
rm -rf ~/.cache/jellyfin-theme-test        # and the media, password and key
```

After `down -v`, `seed.sh` sets the fresh server up again with the same password and makes a new key.

Override the paths with `JF_TEST_STATE`, `JF_TEST_MEDIA` and `JF_TEST_URL` if needed.
