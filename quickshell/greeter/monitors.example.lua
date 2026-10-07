-- Copy to monitors.lua (same folder) and fill in your screens from `hyprctl monitors` (make, model, serial).
-- The login panel goes on the left-most screen; every other screen shows the clock.
-- Matching by description keeps the roles when cables are swapped.
hl.monitor({ output = "desc:Dell Inc. DELL P2417H LEFTSERIAL",  mode = "1920x1080@60", position = "0x0",    scale = "1" })
hl.monitor({ output = "desc:Dell Inc. DELL P2417H RIGHTSERIAL", mode = "1920x1080@60", position = "1920x0", scale = "1" })
