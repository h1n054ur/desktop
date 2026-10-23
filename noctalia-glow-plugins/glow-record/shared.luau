--!nonstrict
-- Helpers shared by the record button and its menu.
local M = {}

M.SOURCES = { "system", "mic", "both" }
M.SOURCE_LABEL = { system = "System sound", mic = "Mic", both = "Both, as separate tracks" }
M.SOURCE_SHORT = { system = "System sound", mic = "Mic", both = "Both tracks" }
M.SOURCE_GLYPH = { system = "volume", mic = "microphone", both = "volume" }

-- Palette from the design note: red live, amber paused, cyan model busy, green done.
M.AMBER = "#f5d76e"

function M.statePath()
  local home = noctalia.getenv("HOME") or ""
  local stateHome = noctalia.getenv("XDG_STATE_HOME")
  if not stateHome or stateHome == "" then stateHome = home .. "/.local/state" end
  return stateHome .. "/recorder/state.json"
end

-- 75 s -> "01:15", 3725 s -> "1:02:05".
function M.fmtTime(s)
  s = math.max(0, math.floor(tonumber(s) or 0))
  local h, m, sec = math.floor(s / 3600), math.floor(s / 60) % 60, s % 60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, sec) end
  return string.format("%02d:%02d", m, sec)
end

-- "2026-10-23T14:05:12+05:00" -> "2026-10-23_14-05-12", the recording's file stem.
function M.fileStem(startedAt)
  if type(startedAt) ~= "string" then return nil end
  local d, h, mi, s = string.match(startedAt, "^(%d%d%d%d%-%d%d%-%d%d)T(%d%d):(%d%d):(%d%d)")
  if not d then return nil end
  return d .. "_" .. h .. "-" .. mi .. "-" .. s
end

function M.clamp01(v)
  v = tonumber(v) or 0
  if v ~= v then return 0 end
  return math.max(0, math.min(1, v))
end

-- Runs `recorder settings --json` and hands the decoded table (or nil) to cb.
function M.loadSettings(cb)
  local started = noctalia.runAsync({ "recorder", "settings", "--json" }, function(res)
    local data = res.exitCode == 0 and noctalia.json.decode(res.stdout or "") or nil
    cb(type(data) == "table" and data or nil)
  end, 5000)
  if not started then cb(nil) end
end

return M
