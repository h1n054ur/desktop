-- Minimal Hyprland session for the h1n054ur greeter: shows the greeter, then exits once you sign in.
-- Started by launch.sh; Hyprland 0.55+ reads Lua configs (the old .conf format is deprecated).

-- Screen layout: monitors.lua next to this file (copy monitors.example.lua). It is kept out of git because it
-- holds your screens' serial numbers. Without it every screen uses its preferred mode, placed automatically.
local layout = loadfile("/etc/greetd/h1n054ur/monitors.lua")
if layout then layout() end
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "1" })

hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("XCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")

hl.config({
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
    },
    animations = {
        enabled = false,
    },
    ecosystem = {
        no_update_news = true,
        no_donation_nag = true,
    },
    input = {
        kb_layout = "us",
        numlock_by_default = true,
    },
})

hl.on("hyprland.start", function()
    hl.exec_cmd("/etc/greetd/h1n054ur/run-greeter.sh")
end)
