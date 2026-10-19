--!nonstrict
local shared = require("./shared.luau")
local limits = noctalia.state.get("limits") or {}
local sessions = noctalia.state.get("sessions") or {}
local style = noctalia.getConfig("bar_style") or "dots" -- "dots" | "counts"
local limitsMode = noctalia.getConfig("bar_limits") or "5h" -- "5h" | "7d" | "5h_7d" | "all" | "none"
local gaugeStyle = noctalia.getConfig("bar_limits_style") or "bar" -- "bar" | "ring"
local SHOWN = { ["5h"] = { ["5h"] = true }, ["7d"] = { ["7d"] = true }, ["5h_7d"] = { ["5h"] = true, ["7d"] = true } }
-- Same session colours as the Claude widget, with working sessions in the accent.
local COLOR = { waiting = "error", busy = shared.accent(), idle = "on_surface_variant/0.45" }
local MAX_DOTS = 8

-- Noctalia has no circular progress control and images can't follow the theme palette, so the ring
-- is a 9x9 grid of tiny boxes: cells on the circle are filled clockwise from 12 o'clock up to `progress`.
local RING_N, RING_CELL = 9, 2
local function ring(progress, color)
  local c = (RING_N - 1) / 2
  local radius = c - 0.3
  local rows = {}
  for i = 0, RING_N - 1 do
    local cells = {}
    for j = 0, RING_N - 1 do
      local dx, dy = j - c, i - c
      local fill = "#00000000"
      if math.abs(math.sqrt(dx * dx + dy * dy) - radius) < 0.55 then
        local angle = (math.atan2(dx, -dy) / (2 * math.pi)) % 1
        fill = angle < progress and color or "on_surface/0.18"
      end
      cells[#cells + 1] = ui.box({ width = RING_CELL, height = RING_CELL, radius = RING_CELL / 2, fill = fill })
    end
    rows[#rows + 1] = ui.row({ gap = 0 }, cells)
  end
  return ui.column({ gap = 0 }, rows)
end

-- Compact limit readouts: "5h ▬▬▭ 45%" per window picked by the bar_limits setting.
local function limitNodes(vertical)
  local nodes = {}
  if limitsMode == "none" then return nodes end
  for _, w in ipairs(limits.windows or {}) do
    if limitsMode == "all" or (SHOWN[limitsMode] and SHOWN[limitsMode][w.label]) then
      local pct = math.floor(w.percent + 0.5)
      local color = shared.severity(pct)
      local progress = math.max(0, math.min(100, pct)) / 100
      local gauge = gaugeStyle == "ring" and ring(progress, color)
        or ui.progress({ progress = progress, width = vertical and 16 or 28, height = 4, fill = color, track = "on_surface/0.18" })
      local kids = {
        ui.label({ text = w.label, fontSize = 9, color = "on_surface_variant" }),
        gauge,
        ui.label({ text = `{pct}%`, fontSize = 10, fontWeight = "bold", color = color }),
      }
      nodes[#nodes + 1] = vertical and ui.column({ gap = 2, align = "center" }, kids) or ui.row({ gap = 3, align = "center" }, kids)
    end
  end
  return nodes
end

local function render()
  local vertical = barWidget.isVertical()
  local nodes = limitNodes(vertical)
  local busy, waiting, rows = 0, 0, {}
  for _, s in ipairs(sessions) do
    if s.status == "busy" then busy += 1 elseif s.status == "waiting" then waiting += 1 end
    local what = s.status == "waiting" and (s.waitingFor ~= "" and s.waitingFor or "needs input")
      or s.status == "busy" and (s.tool ~= "" and s.tool or "working") or "idle"
    rows[#rows + 1] = { s.title, what }
  end
  -- The icon turns red only when there is an error and nothing to show; stale numbers keep it neutral.
  -- A session waiting for you swaps it for a bell, like the Claude widget.
  local failing = limits.error ~= nil and #(limits.windows or {}) == 0
  local children = {
    waiting > 0 and ui.glyph({ name = "bell-ringing", size = 15, color = "error" })
      or ui.glyph({ name = shared.ICON, size = 15, color = failing and "error" or busy > 0 and shared.accent() or "on_surface_variant" }),
  }
  -- Sessions first (one dot each, sorted waiting > busy > idle, or counts), then the limits.
  local marks = {}
  if style == "counts" or #sessions > MAX_DOTS then
    if waiting > 0 then marks[#marks + 1] = ui.label({ text = tostring(waiting), fontSize = 11, fontWeight = "bold", color = "error" }) end
    if #sessions > 0 then
      marks[#marks + 1] = ui.label({ text = `{busy}/{#sessions}`, fontSize = 11, color = busy > 0 and shared.accent() or "on_surface_variant" })
    end
  else
    for _, s in ipairs(sessions) do
      marks[#marks + 1] = ui.box({ width = 7, height = 7, radius = 4, fill = COLOR[s.status] or COLOR.idle })
    end
  end
  for _, m in ipairs(marks) do children[#children + 1] = m end
  if #marks > 0 and #nodes > 0 then
    children[#children + 1] = ui.box({ width = vertical and 10 or 1, height = vertical and 1 or 10, fill = "outline/0.6" })
  end
  for _, n in ipairs(nodes) do children[#children + 1] = n end
  local props = { gap = 4, align = "center" }
  barWidget.render(vertical and ui.column(props, children) or ui.row(props, children))

  for _, w in ipairs(limits.windows or {}) do
    local resets = shared.resetsIn(w.resetsAt)
    rows[#rows + 1] = { `{w.label} limit`, `{math.floor(w.percent + 0.5)}%` .. (resets and ` · resets in {resets}` or "") }
  end
  if limits.error then rows[#rows + 1] = { "Codex", shared.errorText(limits.error) }
  elseif #(limits.windows or {}) == 0 then rows[#rows + 1] = { "Codex", "loading limits" } end
  if limits.updated then rows[#rows + 1] = { "Updated", `{shared.ago(limits.updated)} ago` } end
  barWidget.setTooltip(rows)
end

noctalia.state.watch("limits", function(v) limits = v or {}; render() end)
noctalia.state.watch("sessions", function(v) sessions = v or {}; render() end)
function onClick() noctalia.togglePanel("hani/codex-usage:panel") end
-- Right-click fetches fresh limits now (at most every 30 s, see service.luau).
function onRightClick() noctalia.state.set("command", { action = "force", at = noctalia.nowMs() }) end
-- `noctalia msg plugin hani/codex-usage:bar focused click` toggles the panel (e.g. from a keybind)
function onIpc(ev) if ev == "click" then onClick() end end
render()
