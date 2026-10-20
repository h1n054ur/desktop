--!nonstrict
-- Bar button for the `speak` CLI, which reads coding-agent replies aloud. Every second it only stats the
-- state file and the mute flag. `speak status --json` runs when one of them changed, every second while a
-- reply is playing (the icon pulses), and every 30 s as a safety net. A missing or failing `speak` shows the
-- dim idle icon and nothing else.

local HOME = noctalia.getenv("HOME") or ""
local stateHome = noctalia.getenv("XDG_STATE_HOME")
if not stateHome or stateHome == "" then stateHome = HOME .. "/.local/state" end
local STATE_FILE = stateHome .. "/speak/state.json"
local MUTED_FILE = stateHome .. "/speak/muted"
local RECHECK_TICKS = 30

local status = { state = "idle" }
local available = true
local pending = false
local lastKey = nil
local ticks = 0
local pulse = false

local LABEL = { idle = "Idle", speaking = "Speaking", muted = "Muted" }

local function render()
  local state = status.state
  local icon = "vol-idle"
  if state == "muted" then
    icon = "vol-mute"
  elseif state == "speaking" then
    icon = pulse and "vol-medium" or "vol-high"
  end
  barWidget.render(ui.row({ gap = 5, align = "center" }, {
    ui.image({ path = "icons/" .. icon .. ".png", width = 20, height = 20 }),
  }))

  local rows = {}
  if available then
    rows[#rows + 1] = { "Speak", LABEL[state] or state }
    rows[#rows + 1] = { "Voice", (status.voice and status.voice ~= "") and status.voice or "none" }
    rows[#rows + 1] = { "Last reply", (status.source and status.source ~= "") and status.source or "none yet" }
  else
    rows[#rows + 1] = { "Speak", "not available" }
  end
  rows[#rows + 1] = { "Left click", state == "muted" and "unmute" or "mute" }
  rows[#rows + 1] = { "Right click", "stop" }
  rows[#rows + 1] = { "Middle click", "replay last reply" }
  barWidget.setTooltip(rows)
end

local function refresh()
  if pending then return end
  pending = true
  local started = noctalia.runAsync({ "speak", "status", "--json" }, function(res)
    pending = false
    local data = res.exitCode == 0 and noctalia.json.decode(res.stdout or "") or nil
    if type(data) == "table" and type(data.state) == "string" then
      available = true
      status = data
    else
      available = false
      status = { state = "idle" }
    end
    render()
  end, 5000)
  if not started then
    pending = false
    available = false
    status = { state = "idle" }
    render()
  end
end

-- A cheap change key: the state file's mtime plus whether the mute flag exists.
local function changeKey()
  local info = noctalia.fileInfo(STATE_FILE)
  local mtime = info and info.mtime or 0
  return tostring(mtime) .. (noctalia.fileExists(MUTED_FILE) and ":m" or "")
end

local function run(action)
  noctalia.runAsync({ "speak", action }, function(_res)
    lastKey = nil
    refresh()
  end, 5000)
end

function onClick() run("toggle") end
function onRightClick() run("stop") end
function onMiddleClick() run("replay") end

function update()
  noctalia.setUpdateInterval(1000)
  ticks += 1
  local key = changeKey()
  if status.state == "speaking" then
    pulse = not pulse
    render()
  end
  if key ~= lastKey or status.state == "speaking" or ticks >= RECHECK_TICKS then
    lastKey = key
    ticks = 0
    refresh()
  end
end

render()
