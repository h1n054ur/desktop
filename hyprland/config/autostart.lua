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
    -- The desktop keeps its first kitty on the right screen. The laptop leaves workspace 5 empty at login.
    -- Start it directly, rather than through uwsm, so the workspace rule matches its pid.
    if not LAPTOP_PROFILE then
        hl.exec_cmd(TERMINAL, { workspace = (KITTY_WORKSPACE or "6") .. " silent" })
    end
    -- Login apps are data shared by both profiles: Helium, Chat, Vicu and Mail on workspaces 1 to 4.
    local profile = LAPTOP_PROFILE and "laptop" or "desktop"
    local elapsed = 0
    local apps = os.getenv("HOME") .. "/.config/hypr/config/apps.tsv"
    local file = io.open(apps, "r")
    if file then
        for line in file:lines() do
            if line ~= "" and not line:match("^%s*#") then
                local rowProfile, delay, workspace, command = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t(.+)$")
                if rowProfile and (rowProfile == "all" or rowProfile == profile) then
                    elapsed = elapsed + (tonumber(delay) or 0)
                    local launch = command
                    if elapsed > 0 then
                        launch = "sh -c " .. string.format("%q", "sleep " .. elapsed .. "; exec " .. command)
                    end
                    hl.exec_cmd(launch, { workspace = workspace .. " silent" })
                end
            end
        end
        file:close()
    end
end)
