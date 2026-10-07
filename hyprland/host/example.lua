-- Per-machine values, loaded by hyprland.lua from host/<hostname>.lua. Copy this to host/<your hostname>.lua.
--
-- Two screens, two roles:
--   MONITOR2 = the left screen, the main one in practice: workspaces 1-5, the full Noctalia bar, the login panel
--   MONITOR1 = the right screen: workspaces 6-10, a slimmer bar, the clock on the login screen
-- Match screens by description (make, model, serial: `hyprctl monitors`) so swapping cables never swaps roles.

MONITOR1 = "desc:Dell Inc. DELL P2417H RIGHTSERIAL"   -- right screen
MONITOR2 = "desc:Dell Inc. DELL P2417H LEFTSERIAL"    -- left screen (main)
MONITOR3 = ""
PRIMARY_MONITOR = MONITOR1

-- Fixed positions keep the physical layout: left screen at 0x0, right screen next to it
hl.monitor({ output = MONITOR2, mode = "1920x1080@60", position = "0x0", scale = "1" })
hl.monitor({ output = MONITOR1, mode = "1920x1080@60", position = "1920x0", scale = "1" })
