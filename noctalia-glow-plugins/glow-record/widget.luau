--!nonstrict
-- Bar button for the `recorder` CLI. Idle and paused it only stats the state file once a second and parses it
-- when the mtime moves. While recording it reads the small state file ten times a second for the level meter,
-- blinks the red dot every 500 ms and ticks the time. When idle it asks `recorder list` every 3 s whether a
-- transcript is running, to show its progress. Without `recorder` on the PATH it shows the dim dot and stays quiet.
local shared = require("./shared.luau")

local STATE_FILE = shared.statePath()
local FAST_MS, SLOW_MS = 100, 1000
local LIST_EVERY_MS = 3000
local SETTINGS_EVERY_MS = 30000
local CHECK_EVERY_MS = 30000

-- Meter geometry at ui_scale 1 (the bar scales it): 5 bars, 3 px wide, 2 px apart, 15 px tall.
local BAR_W, BAR_GAP, BAR_H = 3, 2, 15
local BAR_RAMP = { 0.45, 0.6, 0.75, 0.88, 1.0 }

local st = { state = "idle" }
local readAtMs = 0          -- when `st` was read, to tick the time between state writes
local lastMtime = nil
local available = noctalia.commandExists("recorder")
local checkedAtMs = 0
local transcript = nil      -- { title, progress (0..1 or nil) } while a transcript runs
local listPending, listAtMs = false, 0
local settings = nil
local settingsPending, settingsAtMs = false, 0
local busy = false          -- a click's command is still running

local function now() return noctalia.nowMs() end

local function readState()
  local raw = noctalia.readFile(STATE_FILE)
  local data = raw and noctalia.json.decode(raw) or nil
  if type(data) == "table" and type(data.state) == "string" then
    st = data
  else
    st = { state = "idle" }
  end
  readAtMs = now()
end

-- Elapsed seconds: the stored value plus the time since it was read, while recording (capped so a
-- stalled writer cannot run the clock away).
local function elapsed()
  local e = tonumber(st.elapsed_s) or 0
  if st.state == "recording" then e = e + math.min(2, (now() - readAtMs) / 1000) end
  return e
end

-- Per-track levels when the state file carries them ({ system = x, mic = y } or { x, y }), else nil.
local function trackLevels()
  local lv = st.levels
  if type(lv) ~= "table" then return nil end
  local sys, mic = lv.system or lv[1], lv.mic or lv[2]
  if sys == nil or mic == nil then return nil end
  return shared.clamp01(sys), shared.clamp01(mic)
end

local function meter(level)
  local lit = level > 0.02 and math.ceil(level * 5) or 0
  local bars = {}
  for i = 1, 5 do
    local color = i <= 3 and "primary" or "secondary"
    local on = i <= lit
    bars[i] = ui.column({ height = BAR_H, justify = "end" }, {
      ui.box({
        width = BAR_W,
        height = on and math.max(2, BAR_H * BAR_RAMP[i]) or math.max(2, BAR_H * 0.14),
        radius = 1,
        fill = on and color or color .. "/0.35",
      }),
    })
  end
  return ui.row({ gap = BAR_GAP, align = "end" }, bars)
end

local function dot(name)
  return ui.image({ path = "icons/" .. name .. ".png", width = 20, height = 20 })
end

local function timeLabel(color)
  return ui.label({ text = shared.fmtTime(elapsed()), fontSize = 13, fontWeight = "semibold", color = color })
end

local function render()
  local state = available and st.state or "idle"
  local kids = {}
  if state == "recording" then
    local live = math.floor(now() / 500) % 2 == 0
    kids[#kids + 1] = dot(live and "rec-live" or "rec-live-dim")
    kids[#kids + 1] = timeLabel("on_surface")
    local sys, mic = trackLevels()
    if sys ~= nil then
      kids[#kids + 1] = ui.glyph({ name = "volume", size = 12, color = "on_surface_variant" })
      kids[#kids + 1] = meter(sys)
      kids[#kids + 1] = ui.glyph({ name = "microphone", size = 12, color = "on_surface_variant" })
      kids[#kids + 1] = meter(mic)
    else
      kids[#kids + 1] = meter(shared.clamp01(st.level))
    end
  elseif state == "paused" then
    kids[#kids + 1] = dot("rec-paused")
    kids[#kids + 1] = timeLabel("on_surface_variant")
    kids[#kids + 1] = ui.glyph({ name = "player-pause", size = 13, color = shared.AMBER })
  else
    kids[#kids + 1] = dot("rec-idle")
    if transcript then
      local p = transcript.progress
      kids[#kids + 1] = ui.glyph({ name = "file-text", size = 14, color = "secondary" })
      kids[#kids + 1] = ui.progress({ progress = p or 0, width = 30, height = 4, fill = "secondary", track = "on_surface/0.18" })
      kids[#kids + 1] = ui.label({
        text = p and (tostring(math.floor(p * 100 + 0.5)) .. "%") or "...",
        fontSize = 11, fontWeight = "bold", color = "secondary",
      })
    end
  end
  local props = { gap = 7, align = "center" }
  barWidget.render(barWidget.isVertical() and ui.column(props, kids) or ui.row(props, kids))

  local rows = {}
  if not available then
    rows[#rows + 1] = { "Recorder", "not installed" }
    barWidget.setTooltip(rows)
    return
  end
  if state == "recording" or state == "paused" then
    rows[#rows + 1] = { state == "paused" and "Paused" or "Recording", shared.fmtTime(elapsed()) }
    rows[#rows + 1] = { "Source", shared.SOURCE_SHORT[st.source] or tostring(st.source or "unknown") }
    rows[#rows + 1] = { "Format", st.long and "Opus" or "FLAC" }
    local stem = shared.fileStem(st.started_at)
    if stem then rows[#rows + 1] = { "File", stem } end
    rows[#rows + 1] = { "Left click", "stop and save" }
    rows[#rows + 1] = { "Middle click", state == "paused" and "resume" or "pause" }
  else
    rows[#rows + 1] = { "Recorder", transcript and "transcribing" or "idle" }
    if transcript then
      rows[#rows + 1] = { "Transcript", transcript.title }
      if transcript.progress then rows[#rows + 1] = { "Progress", tostring(math.floor(transcript.progress * 100 + 0.5)) .. "%" } end
    end
    if settings then
      rows[#rows + 1] = { "Source", shared.SOURCE_SHORT[settings.default_source] or tostring(settings.default_source) }
      if settings.long ~= nil then
        rows[#rows + 1] = { "Format", (settings.long == true or settings.long == "true") and "Opus" or "FLAC" }
      end
    end
    rows[#rows + 1] = { "Left click", "start recording" }
  end
  rows[#rows + 1] = { "Right click", "source and options" }
  barWidget.setTooltip(rows)
end

-- Progress of a running transcript: `transcript_progress` (0..1, or 0..100) when the CLI reports it.
local function progressOf(row)
  local p = tonumber(row.transcript_progress or row.progress)
  if not p then return nil end
  if p > 1 then p = p / 100 end
  return shared.clamp01(p)
end

local function refreshList()
  if listPending then return end
  listPending = true
  local started = noctalia.runAsync({ "recorder", "list", "--json", "--limit", "5" }, function(res)
    listPending = false
    local rows = res.exitCode == 0 and noctalia.json.decode(res.stdout or "") or nil
    local found = nil
    if type(rows) == "table" then
      for _, r in ipairs(rows) do
        if type(r) == "table" and r.transcript_status == "running" then
          local title = (type(r.title) == "string" and r.title ~= "") and r.title or (shared.fileStem(r.started_at) or "recording")
          found = { title = title, progress = progressOf(r) }
          break
        end
      end
    end
    transcript = found
    render()
  end, 5000)
  if not started then listPending = false end
end

local function refreshSettings()
  if settingsPending then return end
  settingsPending = true
  shared.loadSettings(function(s)
    settingsPending = false
    settings = s
    render()
  end)
end

local function run(argv)
  if not available or busy then return end
  busy = true
  local started = noctalia.runAsync(argv, function(_res)
    busy = false
    lastMtime = nil
    readState()
    render()
  end, 10000)
  if not started then busy = false end
end

function onClick() run({ "recorder", "toggle" }) end

function onMiddleClick()
  if st.state == "recording" then
    run({ "recorder", "pause" })
  elseif st.state == "paused" then
    run({ "recorder", "resume" })
  end
end

function onRightClick() noctalia.togglePanel("hani/glow-record:menu") end

-- The menu publishes the settings it just changed, so the tooltip follows at once.
noctalia.state.watch("settings", function(v)
  if type(v) == "table" then settings = v; render() end
end)

function update()
  local t = now()
  if t - checkedAtMs >= CHECK_EVERY_MS then
    checkedAtMs = t
    available = noctalia.commandExists("recorder")
  end
  if not available then
    st, transcript, settings = { state = "idle" }, nil, nil
    noctalia.setUpdateInterval(SLOW_MS)
    render()
    return
  end

  if st.state == "recording" then
    readState()                       -- level changes ~10 times a second, faster than mtime's 1 s grain
  else
    local info = noctalia.fileInfo(STATE_FILE)
    local mtime = info and info.mtime or 0
    if mtime ~= lastMtime then
      lastMtime = mtime
      readState()
    end
  end

  if st.state == "idle" then
    if t - listAtMs >= LIST_EVERY_MS then
      listAtMs = t
      refreshList()
    end
  else
    transcript = nil
  end
  if st.state == "idle" and t - settingsAtMs >= SETTINGS_EVERY_MS then
    settingsAtMs = t
    refreshSettings()
  end

  noctalia.setUpdateInterval(st.state == "recording" and FAST_MS or SLOW_MS)
  render()
end

render()
