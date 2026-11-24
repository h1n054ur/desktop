-- laptop: HP ZBook Firefly 14 G7, 14" 1920x1080 built-in screen (eDP-1).
-- The built-in screen holds workspaces 1 to 5. The desktop host files still use the two-screen defaults.

LAPTOP_PROFILE = true
WORKSPACE_COUNT = 5
FERDIUM_ENABLED = false
WINAPPS_ENABLED = false
MAIN_SCREEN = "eDP-1"
SIDE_SCREEN = "eDP-1"
KITTY_WORKSPACE = "2"

hl.monitor({
    output    = "eDP-1",
    mode      = "1920x1080@60",
    position  = "0x0",
    scale     = "1",
})
