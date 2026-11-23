-- Auto-start config
-- if you dont use UWSM add your auto start programs here, otherwise use XDG autostart https://wiki.archlinux.org/title/XDG_Autostart

hl.on("hyprland.start", function ()
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")
    hl.exec_cmd("noctalia")
    -- h1n054ur lock screen + session menu (~/.config/quickshell/h1n054ur), and hypridle to lock before sleep
    hl.exec_cmd("quickshell -c h1n054ur")
    hl.exec_cmd("hypridle")
    -- Handy: offline dictation in the tray, held on Right Alt through handy-ptt (Handy's own shortcut does not fire on Wayland)
    hl.exec_cmd("handy --start-hidden")
    hl.exec_cmd("xhost +SI:localuser:root")
    -- first kitty: workspace per machine (KITTY_WORKSPACE, set in variables.lua / host files); started directly
    -- (not through uwsm) so the workspace rule matches its pid
    hl.exec_cmd(TERMINAL, { workspace = (KITTY_WORKSPACE or "6") .. " silent" })
    -- workspaces 2 to 4 on the left screen: Helium on 2 first (it becomes the browser process), then the BTS
    -- Mail and Tasks app windows, which Helium opens in that same process. Their window rules (windowrules.lua)
    -- put them on 3 and 4. MailCraft (the desktop mail client) opens on 5.
    hl.exec_cmd("helium-browser", { workspace = "2 silent" })
    hl.exec_cmd("sh -c 'sleep 5; helium-browser --app=https://mail.bts.ad/; sleep 2; helium-browser --app=https://tasks.bts.ad/'")
    hl.exec_cmd("gtk-launch io.github.billsecond.mailcraft")
end)
