-- Nested Hyprland for testing the lock screen in a window: two outputs, the shell started with test hooks.
hl.monitor({ output = "", mode = "1280x720", position = "auto", scale = "1" })
hl.config({
    misc = { disable_hyprland_logo = true, disable_splash_rendering = true, allow_session_lock_restore = true, disable_watchdog_warning = true },
    animations = { enabled = false },
    ecosystem = { no_update_news = true, no_donation_nag = true },
})
hl.on("hyprland.start", function()
    hl.exec_cmd("hyprctl output create wayland")
    hl.exec_cmd(os.getenv("H1N_NESTED_CMD"))
end)
