--!nonstrict
-- Listens to Hyprland's event socket and publishes, per monitor, the last focused window of the
-- workspace visible on that monitor: state "windows" = { ["DP-1"] = { title, class } | false }.

local LISTEN = [[python3 -u -c "
import socket, os, glob
os.closerange(3, 65536)  # drop pipes inherited from Noctalia, or they never reach EOF (froze Noctalia at login, 2026-10-08)
sig = os.environ.get('HYPRLAND_INSTANCE_SIGNATURE')
base = os.environ.get('XDG_RUNTIME_DIR', '/run/user/%d' % os.getuid()) + '/hypr/'
path = base + sig + '/.socket2.sock' if sig else (glob.glob(base + '*/.socket2.sock') or [''])[0]
s = socket.socket(socket.AF_UNIX); s.connect(path)
for line in s.makefile(): print(line, end='', flush=True)
"]]


local busy, dirty = false, false

local WATCHED = { activewindow = true, workspace = true, focusedmon = true, openwindow = true, closewindow = true,
  movewindow = true, windowtitle = true, windowtitlev2 = true, moveworkspace = true, monitoradded = true, monitorremoved = true }

local function refresh()
  if busy then
    dirty = true
    return
  end
  busy = true
  noctalia.runAsync({ "sh", "-c", "hyprctl -j monitors; printf '\\036'; hyprctl -j workspaces; printf '\\036'; hyprctl -j clients" }, function(res)
    busy = false
    local parts = {}
    for chunk in string.gmatch((res.stdout or "") .. "\30", "([^\30]*)\30") do
      table.insert(parts, chunk)
    end
    local monitors = parts[1] and noctalia.json.decode(parts[1])
    local workspaces = parts[2] and noctalia.json.decode(parts[2])
    local clients = parts[3] and noctalia.json.decode(parts[3])
    if type(monitors) == "table" and type(workspaces) == "table" then
      local byWs, byAddr = {}, {}
      for _, w in ipairs(workspaces) do byWs[w.id] = w end
      for _, c in ipairs(clients or {}) do byAddr[c.address] = c end
      local out = {}
      for _, m in ipairs(monitors) do
        local ws = m.activeWorkspace and byWs[m.activeWorkspace.id]
        local entry = false
        if ws and (ws.windows or 0) > 0 and ws.lastwindowtitle and ws.lastwindowtitle ~= "" then
          local c = byAddr[ws.lastwindow]
          entry = { title = ws.lastwindowtitle, class = c and c.class or "" }
        end
        out[m.name] = entry
      end
      noctalia.state.set("windows", out)
    end
    if dirty then
      dirty = false
      refresh()
    end
  end)
end

noctalia.runStream(LISTEN, function(line)
  local ev = string.match(line, "^([%w]+)>>")
  if ev and WATCHED[ev] then refresh() end
end)

function update()
  noctalia.setUpdateInterval(30000) -- safety net if the event stream drops
  refresh()
end
