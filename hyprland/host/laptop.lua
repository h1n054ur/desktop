-- laptop: HP ZBook Firefly 14 G7, 14" 1920x1080 built-in screen (eDP-1).
-- Alone, the built-in screen holds every workspace (1-10). Plugged-in screens get roles in Phase 7 (screens.lua).

MAIN_SCREEN = "eDP-1"
SIDE_SCREEN = "eDP-1"   -- one screen holds both roles
KITTY_WORKSPACE = "2"   -- one screen: Ferdium on 1, kitty next to it on 2

hl.monitor({
    output    = "eDP-1",
    mode      = "1920x1080@60",
    position  = "0x0",
    scale     = "1",
})
