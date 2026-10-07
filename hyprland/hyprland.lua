-- CachyOS Hyprland Configuration

require("config.animations")
require("config.autostart")
require("config.colors")
require("config.decorations")
require("config.variables")
-- Per-machine values (monitors...): host/<hostname>.lua, shared between machines like everything else
do
    local f = io.open("/etc/hostname")
    local host = f and f:read("*l") or ""
    if f then f:close() end
    local hf = host ~= "" and io.open(os.getenv("HOME") .. "/.config/hypr/host/" .. host .. ".lua")
    if hf then
        hf:close()
        require("host." .. host)
    end
end
require("config.environment")
require("config.inputs")
require("config.binds")
require("config.misc")
require("config.monitors")
require("config.windowrules")
require("config.workspaces")
