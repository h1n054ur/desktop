hl.config({
    dwindle = {
        preserve_split = true,
    },
    ecosystem = {
        no_update_news = true,
        no_donation_nag = true,
    },
    misc = {
        col = {
            splash = CACHYLGREEN,
        },
        middle_click_paste = false,
        enable_swallow = true,
        swallow_regex = "(kitty|ghostty|[Kk]onsole|Alacritty|gnome-terminal|xfce[0-9]?-terminal)",
        vrr = 3,
        -- If a lock screen crashes, a new one can take over (and unlock) instead of leaving the session stuck
        allow_session_lock_restore = true,
        -- Any key or mouse movement switches screens back on, also behind the lock screen (it holds the input,
        -- so Noctalia's idle resume never sees it and the screens stayed black)
        key_press_enables_dpms = true,
        mouse_move_enables_dpms = true,
    },
    render = {
        direct_scanout = 2,
        -- Use the option below if you find games constantly black screening for a couple seconds whenever direct scanout enables/disables
        -- non_shader_cm = 0,
    },
    xwayland = {
        force_zero_scaling = true
    },
})
