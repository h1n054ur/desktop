-- Per-machine values, loaded by hyprland.lua from host/<hostname>.lua. Copy this to host/<your hostname>.lua.
--
-- Two screens, two roles:
--   MAIN_SCREEN = the left screen, the main one in practice: workspaces 1-5, the full Noctalia bar, the login panel
--   SIDE_SCREEN = the right screen: workspaces 6-10, a slimmer bar, the clock on the login screen
-- Match screens by description (make, model, serial: `hyprctl monitors`) so swapping cables never swaps roles.

MAIN_SCREEN = "desc:Dell Inc. DELL P2417H LEFTSERIAL"    -- left screen (main)
SIDE_SCREEN = "desc:Dell Inc. DELL P2417H RIGHTSERIAL"   -- right screen

-- Fixed positions keep the physical layout: left screen at 0x0, right screen next to it
hl.monitor({ output = MAIN_SCREEN, mode = "1920x1080@60", position = "0x0", scale = "1" })
hl.monitor({ output = SIDE_SCREEN, mode = "1920x1080@60", position = "1920x0", scale = "1" })
