# OxiCloud Files mount

This mounts OxiCloud at `~/Files` with rclone and a systemd user service. The mount root is OxiCloud's drive listing, so the personal drive and every shared drive the user can read appear as top-level directories.

## OxiCloud v0.10.1 behaviour

OxiCloud exposes WebDAV at `/webdav/`. The default `/webdav/` path opens the personal drive, while `/webdav/@drive/` lists every readable drive and accepts a drive UUID or display name below it. This mount uses `https://files.bts.ad/webdav/@drive/` so personal and shared drives are both visible. See the pinned [WebDAV guide, lines 3 to 46](https://github.com/AtalayaLabs/OxiCloud/blob/v0.10.1/docs/guide/webdav.md#L3-L46) and [drives guide, lines 3 to 38](https://github.com/AtalayaLabs/OxiCloud/blob/v0.10.1/docs/guide/drives.md#L3-L38).

DAV uses HTTP Basic authentication with the OxiCloud username and an app password. The normal account password is refused, including for users who sign in through OIDC. OxiCloud documents the same app-password flow for password, magic-link and OIDC accounts in the [WebDAV guide, lines 54 to 75](https://github.com/AtalayaLabs/OxiCloud/blob/v0.10.1/docs/guide/webdav.md#L54-L75) and [DAV client setup, lines 5 to 25](https://github.com/AtalayaLabs/OxiCloud/blob/v0.10.1/docs/guide/dav-client-setup.md#L5-L25).

## Create the app password

1. Sign in to [files.bts.ad](https://files.bts.ad) through OIDC.
2. Open **Profile**, then **App Passwords**.
3. Select **Create**, give the password a machine-specific name such as `desktop files` or `laptop files`, and copy the token when OxiCloud shows it. The token is shown once.
4. Store the username and token in the vault. The lead handles this after the code is merged.
5. On the machine being set up, create the credential file without putting the token on a command line:

```bash
install -d -m 700 ~/.config/oxicloud
umask 077
read -r -p "OxiCloud username: " oxicloud_user
read -r -s -p "OxiCloud app password: " oxicloud_app_password
printf '\n'
printf '%s\n%s\n' "$oxicloud_user" "$oxicloud_app_password" > ~/.config/oxicloud/credentials
unset oxicloud_user oxicloud_app_password
chmod 600 ~/.config/oxicloud/credentials
```

The file must contain exactly two non-empty lines. The username is on line 1 and the app password is on line 2. The existing `files` CLI and this mount read the same file. No secret is stored in the repository or the rclone config.

## One-time setup

The `network` package group in `setup/` installs rclone. FUSE and the systemd user manager also need to be available.

```bash
cd ~/desktop/filesmount
./install.sh --dry-run
./install.sh
```

The real run installs the remote definition, mount helper and user unit. It adds `/Files` to `~/.stignore` before starting the mount, then enables and starts `oxicloud-files.service`.

`~/Files` is inside the home directory because that is the requested desktop path. The current Syncthing folder named `home` is rooted at `~`, so `/Files` is a root-relative ignore pattern in `~/.stignore`. After issue #423 removes whole-home sync, only `~/Notes` remains in Syncthing and it does not overlap the mount. The mount helper refuses to start if the `/Files` guard is missing.

The rclone VFS cache lives at `~/.cache/rclone/oxicloud`. It uses full mode, keeps at most 10 GiB, removes entries that have not been used for 24 hours, and tries to leave 5 GiB free on the cache filesystem.

## Check it

```bash
systemctl --user status --no-pager oxicloud-files.service
findmnt --mountpoint "$HOME/Files"
ls -la ~/Files
journalctl --user -u oxicloud-files.service -n 50 --no-pager
```

`ls` should show the personal drive and each shared drive the account can read.

## Unmount it

Stop the service to unmount until the next login:

```bash
systemctl --user stop oxicloud-files.service
```

Start it again with `systemctl --user start oxicloud-files.service`. To keep it off across logins, run:

```bash
systemctl --user disable --now oxicloud-files.service
```
