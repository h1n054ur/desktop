-- Auto-start config
-- if you dont use UWSM add your auto start programs here, otherwise use XDG autostart https://wiki.archlinux.org/title/XDG_Autostart

hl.on("hyprland.start", function ()
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")
    hl.exec_cmd("noctalia")
    -- h1n054ur lock screen + session menu (~/.config/quickshell/h1n054ur), and hypridle to lock before sleep
    hl.exec_cmd("quickshell -c h1n054ur")
    hl.exec_cmd("hypridle")
    -- Handy: offline dictation in the tray; its own shortcut is Ctrl+Space (not a Hyprland bind: a Super bind
    -- let the typed text arrive while Super was still held, so every letter fired a Super shortcut)
    hl.exec_cmd("handy --start-hidden")
    hl.exec_cmd("xhost +SI:localuser:root")
    -- first kitty: workspace per machine (KITTY_WORKSPACE, set in variables.lua / host files); started directly
    -- (not through uwsm) so the workspace rule matches its pid
    hl.exec_cmd(TERMINAL, { workspace = (KITTY_WORKSPACE or "6") .. " silent" })
end)
