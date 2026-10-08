local mainMod = "SUPER"
local noctCall = "noctalia msg "
local h1nCall = "quickshell -c h1n054ur ipc call " -- h1n054ur lock screen and session menu
local launchPrefix = "uwsm app -- " -- if you are not using UWSM, make this empty (e.g. "")

-- AZERTY fix: the number-row keys emit symbols (& é " ' ...) without Shift, so
-- binding to the digit characters fails. Bind by physical keycode instead.
-- Digit d -> evdev keycode: 1..9 => 10..18, 0 => 19
local function digitCode(d)
    return "code:" .. (d == 0 and 19 or (9 + d))
end

---------------------------
---- WINDOW MANAGEMENT ----
---------------------------

-- Window manipulation
hl.bind(mainMod .. " + Escape",      hl.dsp.exec_cmd("hyprctl kill"))
hl.bind(mainMod .. " + Q",           hl.dsp.window.close())
hl.bind(mainMod .. " + ALT + Space", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + Return",      hl.dsp.window.fullscreen({ mode = 1 })) -- maximise
hl.bind(mainMod .. " + F11",         hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + J",           hl.dsp.layout("togglesplit"))

-- Change focus
hl.bind(mainMod .. " + Left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + Right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + Up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + Down",  hl.dsp.focus({ direction = "down" }))
hl.bind("ALT + Tab",           hl.dsp.window.cycle_next())
hl.bind(mainMod .. " + Tab",   hl.dsp.exec_cmd(noctCall .. "window-switcher"))

-- Move active window around workspaces & monitors
hl.bind(mainMod .. " + SHIFT + Up",                   hl.dsp.window.move({ direction = "u" }))
hl.bind(mainMod .. " + SHIFT + Right",                hl.dsp.window.move({ direction = "r" }))
hl.bind(mainMod .. " + SHIFT + Left",                 hl.dsp.window.move({ direction = "l" }))
hl.bind(mainMod .. " + SHIFT + Down",                 hl.dsp.window.move({ direction = "d" }))
hl.bind(mainMod .. " + SHIFT + mouse_up",             hl.dsp.window.move({ monitor   = "-1" }))
hl.bind(mainMod .. " + SHIFT + mouse_down",           hl.dsp.window.move({ monitor   = "+1" }))
hl.bind(mainMod .. " + CONTROL + SHIFT + Right",      hl.dsp.window.move({ workspace = "m+1" }))
hl.bind(mainMod .. " + CONTROL + SHIFT + Left",       hl.dsp.window.move({ workspace = "m-1" }))
hl.bind(mainMod .. " + CONTROL + SHIFT + mouse_up",   hl.dsp.window.move({ workspace = "m-1" }))
hl.bind(mainMod .. " + CONTROL + SHIFT + mouse_down", hl.dsp.window.move({ workspace = "m+1" }))
for i = 1, NUM_WPM do
    local key = i % 10
    hl.bind(mainMod .. " + SHIFT + CONTROL + " .. digitCode(key), hl.dsp.window.move({ workspace = "m~" .. i }))
end
for i = 1, NUM_WPM do
    local key = i % 10
    hl.bind(mainMod .. " + SHIFT + ALT + " .. digitCode(key), hl.dsp.window.move({ workspace = "m~" .. i, follow = false }))
end

-- Move & Resize with mouse
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag())
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize())

-- Zoom
local function zoomfunction(value)
    local zoomvalue = hl.get_config("cursor:zoom_factor")
    if (zoomvalue + value) > 3.0 then
        hl.config({ cursor = { zoom_factor = 3.0 } })
    elseif (zoomvalue + value) < 1.0 then
        hl.config({ cursor = { zoom_factor = 1.0 } })
    else
        hl.config({ cursor = { zoom_factor = zoomvalue + value } })
    end
end
hl.bind(mainMod .. " + Minus", function() zoomfunction(-0.3) end, { repeating = true})
hl.bind(mainMod .. " + Plus", function() zoomfunction(0.3) end, { repeating = true })

--# Zoom with keypad
hl.bind(mainMod .. " + code:82", function() zoomfunction(-0.3) end, { repeating = true })
hl.bind(mainMod .. " + code:86", function() zoomfunction(0.3) end, { repeating = true })


------------------
---- LAUNCHER ----
------------------

hl.bind(mainMod .. " + T",          hl.dsp.exec_cmd(launchPrefix .. TERMINAL))
-- Ferdium: jump to it when it is open, start it otherwise
hl.bind(mainMod .. " + F", function()
    if hl.get_window("class:ferdium") then
        hl.dispatch(hl.dsp.focus({ window = "class:ferdium" }))
    else
        hl.dispatch(hl.dsp.exec_cmd(launchPrefix .. "ferdium"))
    end
end)
-- Helium: jump to the normal (signed-in) window when open, start it otherwise; Shift opens an incognito window
hl.bind(mainMod .. " + C", function()
    for _, w in ipairs(hl.get_windows({ class = "helium" })) do
        -- the first title says "New Incognito Tab" for the whole life of an incognito window
        if not (w.initial_title .. w.title):find("Incognito", 1, true) then
            hl.dispatch(hl.dsp.focus({ window = "address:" .. w.address }))
            return
        end
    end
    hl.dispatch(hl.dsp.exec_cmd(launchPrefix .. "helium-browser"))
end)
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd(launchPrefix .. "helium-browser --incognito"))
-- Call apps that can share the screen (Ferdium can't for these): jump to the window when open, start it otherwise
local function focusOrLaunch(class, cmd)
    return function()
        local w = hl.get_windows({ class = class })[1]
        if w then
            hl.dispatch(hl.dsp.focus({ window = "address:" .. w.address }))
        else
            hl.dispatch(hl.dsp.exec_cmd(launchPrefix .. cmd))
        end
    end
end
-- Vesktop: jump to it when open, otherwise start it on the next empty workspace of the right screen
-- (switch first, as for YouTube Music below: a new window lands on the workspace active when its process started)
hl.bind(mainMod .. " + D", function()
    local w = hl.get_windows({ class = "vesktop" })[1]
    if w then
        hl.dispatch(hl.dsp.focus({ window = "address:" .. w.address }))
    else
        hl.dispatch(hl.dsp.focus({ monitor = SIDE_SCREEN }))
        hl.dispatch(hl.dsp.focus({ workspace = "emptym" }))
        hl.dispatch(hl.dsp.exec_cmd(launchPrefix .. "vesktop"))
    end
end)
hl.bind(mainMod .. " + SHIFT + T", focusOrLaunch("chrome-teams.microsoft.com__-Default", "helium-browser --app=https://teams.microsoft.com/"))
hl.bind(mainMod .. " + SHIFT + Z", focusOrLaunch("chrome-app.zoom.us__wc_home-Default", "helium-browser --app=https://app.zoom.us/wc/home"))
-- Windows desktop (WinApps, see h1n054ur-setup): focus it, or open it on the next empty workspace
hl.bind(mainMod .. " + W",          hl.dsp.exec_cmd(launchPrefix .. os.getenv("HOME") .. "/.local/bin/winapps-open windows"))
-- Obsidian (notes, ~/Notes vault): jump to it when open, start it otherwise
hl.bind(mainMod .. " + O", focusOrLaunch("md.obsidian.Obsidian", "obsidian"))
hl.bind(mainMod .. " + V",         focusOrLaunch("codium", "codium"))
hl.bind(mainMod .. " + B",         focusOrLaunch("calibre-gui", "calibre"))
hl.bind(mainMod .. " + SHIFT + B", focusOrLaunch("com.github.johnfactotum.Foliate", "foliate")) -- ebook reader
-- yazi and rmpc as their own kitty windows (Ctrl+Shift+Y / Ctrl+Shift+M still work inside kitty)
hl.bind(mainMod .. " + Y",         focusOrLaunch("yazi", TERMINAL .. " --class yazi -e yazi"))
-- YouTube Music as a Chrome app window: jump to it when open, otherwise start it on the next empty
-- workspace of this monitor (switch first: a new window lands on the workspace active when its process started)
hl.bind(mainMod .. " + M", function()
    local w = hl.get_windows({ class = "chrome-music.youtube.com__-Default" })[1]
    if w then
        hl.dispatch(hl.dsp.focus({ window = "address:" .. w.address }))
    else
        hl.dispatch(hl.dsp.focus({ workspace = "emptym" }))
        hl.dispatch(hl.dsp.exec_cmd(launchPrefix .. "helium-browser --app=https://music.youtube.com/"))
    end
end)
hl.bind(mainMod .. " + SHIFT + M", focusOrLaunch("rmpc", TERMINAL .. " --class rmpc -e rmpc"))
-- Bitwarden pop-up: pick a login and it is typed into the focused field (rbw + rofi-rbw + wtype)
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("rofi-rbw"))
-- Bitwarden desktop app: jump to it when open, start it otherwise
hl.bind(mainMod .. " + P",         focusOrLaunch("Bitwarden", "bitwarden-desktop"))
hl.bind(mainMod .. " + E",          hl.dsp.exec_cmd(launchPrefix .. FILE_MANAGER))
hl.bind(mainMod .. " + equal",      hl.dsp.exec_cmd(launchPrefix .. CALCULATOR))
hl.bind("XF86Calculator",           hl.dsp.exec_cmd(launchPrefix .. CALCULATOR))
hl.bind("CONTROL + SHIFT + Escape", focusOrLaunch("io.missioncenter.MissionCenter", "missioncenter")) -- Mission Center task manager (jumps)
hl.bind(mainMod .. " + SHIFT + Escape", hl.dsp.exec_cmd(launchPrefix .. TERMINAL .. " -e btop")) -- btop (was Ctrl+Shift+Esc until 2026-10-07)
hl.bind(mainMod .. " + Z",          hl.dsp.exec_cmd(noctCall .. "settings-toggle"))
hl.bind(mainMod .. " + X",          hl.dsp.exec_cmd(noctCall .. "panel-toggle control-center"))
hl.bind(mainMod .. " + grave",      hl.dsp.exec_cmd("pkill -x fuzzel || fuzzel")) -- app launcher (fuzzel, h1n054ur look); toggles
-- Dictation (Handy, offline): hold Ctrl+Space and talk, let go and the text is typed. handy-ptt starts/stops only
-- when Handy's real state needs it (its mic stream), and Ctrl's own release also stops it, so key order never matters
hl.bind("CONTROL + Space",          hl.dsp.exec_cmd("handy-ptt down"))
hl.bind("CONTROL + Space",          hl.dsp.exec_cmd("handy-ptt up"), { release = true })
hl.bind("CONTROL + Control_L",      hl.dsp.exec_cmd("handy-ptt up"), { release = true, non_consuming = true })
hl.bind("CONTROL + Control_R",      hl.dsp.exec_cmd("handy-ptt up"), { release = true, non_consuming = true })
hl.bind(mainMod .. " + L",          hl.dsp.exec_cmd(h1nCall .. "lock lock"))
hl.bind(mainMod .. " + ALT + C",    hl.dsp.exec_cmd(h1nCall .. "session toggle"))
hl.bind(mainMod .. " + slash",      hl.dsp.exec_cmd(noctCall .. "panel-toggle kenn/keybind-cheatsheet:cheatsheet")) -- searchable keybind cheat sheet

---------------------------
---- HARDWARE CONTROLS ----
---------------------------

-- Audio
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(noctCall .. "volume-up"),   { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(noctCall .. "volume-down"), { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd(noctCall .. "volume-mute"), { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd(noctCall .. "mic-mute"),    { locked = true })

-- Media
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd(noctCall .. "media toggle"),   { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(noctCall .. "media toggle"),   { locked = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd(noctCall .. "media next"),     { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd(noctCall .. "media previous"), { locked = true })

-- Brightness
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd(noctCall .. "brightness-up"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(noctCall .. "brightness-down"), { locked = true, repeating = true })

-------------------
---- UTILITIES ----
-------------------

-- Screen Capture
hl.bind(mainMod .. " + ALT + P", hl.dsp.exec_cmd("hyprpicker -a -n"))   -- colour picker (was Super+P until 2026-10-07)
hl.bind("Print",               hl.dsp.exec_cmd(noctCall .. "screenshot-region"))
hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd(noctCall .. "screenshot-fullscreen"))

-- Theming and Wallpaper
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd(noctCall .. "panel-toggle wallpaper"))

-- Clipboard
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd(noctCall .. "panel-toggle clipboard"))

-- Notifications
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd(noctCall .. "panel-toggle control-center notifications"))
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.exec_cmd(noctCall .. "notification-dnd-toggle")) -- do not disturb on/off

-- Bar on/off (presentations, screen shares)
hl.bind(mainMod .. " + SHIFT + H", hl.dsp.exec_cmd(noctCall .. "bar-toggle"))

-- Resize mode: Super+R, then arrows resize the focused window (Shift = bigger steps), Esc or Enter leaves
hl.bind(mainMod .. " + R", hl.dsp.submap("resize"))
hl.define_submap("resize", function()
    hl.bind("Right",         hl.dsp.window.resize({ x = 40,   y = 0,    relative = true }), { repeating = true })
    hl.bind("Left",          hl.dsp.window.resize({ x = -40,  y = 0,    relative = true }), { repeating = true })
    hl.bind("Up",            hl.dsp.window.resize({ x = 0,    y = -40,  relative = true }), { repeating = true })
    hl.bind("Down",          hl.dsp.window.resize({ x = 0,    y = 40,   relative = true }), { repeating = true })
    hl.bind("SHIFT + Right", hl.dsp.window.resize({ x = 160,  y = 0,    relative = true }), { repeating = true })
    hl.bind("SHIFT + Left",  hl.dsp.window.resize({ x = -160, y = 0,    relative = true }), { repeating = true })
    hl.bind("SHIFT + Up",    hl.dsp.window.resize({ x = 0,    y = -160, relative = true }), { repeating = true })
    hl.bind("SHIFT + Down",  hl.dsp.window.resize({ x = 0,    y = 160,  relative = true }), { repeating = true })
    hl.bind("Escape",        hl.dsp.submap("reset"))
    hl.bind("Return",        hl.dsp.submap("reset"))
end)

-------------------------------
---- WORKSPACES & MONITORS ----
-------------------------------

-- Fixed workspaces: 1-5 live on the left monitor, 6-10 on the right (main) one (see workspaces.lua)
-- Super+N goes to workspace N (Super+0 is workspace 10), Super+Shift+N sends the focused window there
for i = 1, 10 do
    hl.bind(mainMod .. " + " .. digitCode(i % 10), hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. digitCode(i % 10), hl.dsp.window.move({ workspace = tostring(i) }))
end

-- Focus on workspace number
-- Absolute
for i = 1, NUM_WPM do
    local key = i % 10
    hl.bind(mainMod .. " + ALT + " .. digitCode(key), hl.dsp.focus({ workspace = i }))
end
-- Relative
for i = 1, NUM_WPM do
    local key = i % 10
    hl.bind(mainMod .. " + CONTROL + " .. digitCode(key), hl.dsp.focus({ workspace = "m~" .. i }))
end

-- Move to adjacent workspaces and next empty on a given monitor
hl.bind(mainMod .. " + CONTROL + Right",       hl.dsp.focus({ workspace = "m+1" }))
hl.bind(mainMod .. " + CONTROL + Left",        hl.dsp.focus({ workspace = "m-1" }))
hl.bind(mainMod .. " + CONTROL + Down",        hl.dsp.focus({ workspace = "emptym" }))

-- Scroll through existing workspaces & monitors
hl.bind(mainMod .. " + mouse_down",           hl.dsp.focus({ workspace = "m-1" }))
hl.bind(mainMod .. " + mouse_up",             hl.dsp.focus({ workspace = "m+1" }))
hl.bind(mainMod .. " + CONTROL + mouse_up",   hl.dsp.focus({ workspace = "m-1" }))
hl.bind(mainMod .. " + CONTROL + mouse_down", hl.dsp.focus({ workspace = "m+1" }))

-- Special workspace (scratchpad)
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special" }))
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special())
