--!nonstrict
-- The voice used by speak is also the session persona. Keep its label beside the speak control without
-- starting another process: state.json already carries the current or most recent voice.

local HOME = noctalia.getenv("HOME") or ""
local stateHome = noctalia.getenv("XDG_STATE_HOME")
if not stateHome or stateHome == "" then stateHome = HOME .. "/.local/state" end
local STATE_FILE = stateHome .. "/speak/state.json"

local lastMtime = nil
local persona = "Persona"
local source = "No spoken reply yet"

local function displayName(value)
  if not value or value == "" or value == "default" then return "Persona" end
  return value:sub(1, 1):upper() .. value:sub(2)
end

local function render()
  barWidget.render(ui.label({ text = persona, fontSize = 11, fontWeight = "bold", color = "primary" }))
  barWidget.setTooltip({
    { "Persona", persona },
    { "Last reply", source },
  })
end

local function refresh()
  local raw = noctalia.readFile(STATE_FILE)
  local data = raw and noctalia.json.decode(raw) or nil
  if type(data) == "table" then
    persona = displayName(data.voice)
    source = (data.source and data.source ~= "") and data.source or "No spoken reply yet"
  else
    persona = "Persona"
    source = "Speak is not ready"
  end
  render()
end

function update()
  noctalia.setUpdateInterval(1000)
  local info = noctalia.fileInfo(STATE_FILE)
  local mtime = info and info.mtime or 0
  if mtime ~= lastMtime then
    lastMtime = mtime
    refresh()
  end
end

refresh()
