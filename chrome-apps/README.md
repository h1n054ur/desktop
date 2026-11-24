# Helium app windows

`apps.tsv` is the launcher list for Helium app windows. Each row sets the name, URL, icon, launcher group and optional Helium profile. The `UNE` profile keeps UNE Microsoft 365 signed in separately from the default profile.

The builder writes desktop launchers under `~/.local/share/applications/` with the window class Helium uses for each URL. It also removes old launchers for WhatsApp, Telegram, Slack, Teams and Discord because those services now live as pinned tabs in the main Helium window.

## Install

```sh
install -Dm644 apps.tsv ~/.local/share/chrome-apps/apps.tsv
install -Dm755 build.py ~/.local/share/chrome-apps/build.py
~/.local/share/chrome-apps/build.py
```

The desktop installer runs the same steps through its `appwindows` component. Custom `@name.png` icons are used when they already exist under `~/.local/share/icons/webapps/`. On a new machine the builder tries the site's own icon instead.
