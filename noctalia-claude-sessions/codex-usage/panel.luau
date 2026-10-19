--!nonstrict
local shared = require("./shared.luau")

local limits = noctalia.state.get("limits") or {}

local function iconLine(glyph, text, color, size)
  return ui.row({ gap = 6, align = "center" }, {
    ui.glyph({ name = glyph, size = (size or 11) + 1, color = color or "on_surface_variant" }),
    ui.label({ text = text, fontSize = size or 11, color = color or "on_surface_variant", maxLines = 2, flexGrow = 1 }),
  })
end

local function action(glyph, tooltip, fn, variant)
  return ui.button({ glyph = glyph, tooltip = tooltip, variant = variant or "ghost", controlSize = "sm", onClick = fn })
end

-- Plan usage windows (5h / 7d), one meter each, laid out like the Claude panel's limits strip.
local function limitsStrip()
  local windows = limits.windows or {}
  if #windows == 0 then return nil end
  local meters = {}
  for _, w in ipairs(windows) do
    local p = math.max(0, math.min(100, w.percent)) / 100
    local color = shared.severity(w.percent)
    local left = shared.resetsIn(w.resetsAt)
    meters[#meters + 1] = ui.column({ gap = 3, flexGrow = 1 }, {
      ui.row({ gap = 4, align = "center" }, {
        ui.label({ text = w.label, fontSize = 11, fontWeight = "bold", color = "on_surface" }),
        ui.spacer({ flexGrow = 1 }),
        ui.label({ text = `{math.floor(w.percent + 0.5)}%`, fontSize = 11, fontWeight = "bold", color = color }),
      }),
      ui.progress({ progress = p, height = 5, fill = color }),
      ui.label({ text = left and `resets in {left}` or "", fontSize = 10, color = "on_surface_variant" }),
    })
  end
  return ui.column({ gap = 6, padding = 10, radius = 10, fill = "on_surface/0.04" }, {
    ui.row({ gap = 14, align = "start" }, meters),
  })
end

function render()
  local header = {
    ui.row({ width = 28, height = 28, radius = 8, fill = "primary/0.15", align = "center", justify = "center" }, {
      ui.glyph({ name = shared.ICON, size = 16, color = "primary" }),
    }),
    ui.column({ gap = 0 }, {
      ui.label({ text = "Codex Usage", fontSize = 15, fontWeight = "bold", color = "on_surface" }),
      ui.label({ text = limits.plan and `ChatGPT {limits.plan}` or "", fontSize = 10, color = "on_surface_variant",
        visible = limits.plan ~= nil }),
    }),
    ui.spacer({ flexGrow = 1 }),
    action(limits.pending and "loader-2" or "refresh", "Refresh now", function()
      noctalia.state.set("command", { action = "force", at = noctalia.nowMs() })
    end),
    action("x", "Close", function() panel.close() end),
  }

  local content = {}
  local strip = limitsStrip()
  if strip then
    content[#content + 1] = strip
  elseif not limits.error then
    content[#content + 1] = ui.column({ gap = 8, align = "center", justify = "center", paddingV = 30 }, {
      ui.glyph({ name = "loader-2", size = 30, color = "on_surface_variant" }),
      ui.label({ text = "Loading Codex limits", color = "on_surface_variant" }),
    })
  end
  if limits.error then
    content[#content + 1] = ui.column({ gap = 4, padding = 10, radius = 10, fill = "error/0.08", border = "error/0.4", borderWidth = 1 }, {
      iconLine("alert-circle", shared.errorText(limits.error), "error", 12),
      iconLine("clock", strip and "Showing the last numbers we got" or `tried {shared.ago(limits.error.at)} ago`),
    })
  end

  local updated = limits.updated and `Last updated {shared.ago(limits.updated)} ago` or "Not updated yet"
  panel.render(ui.column({ gap = 10, flexGrow = 1 }, {
    ui.row({ gap = 8, align = "center" }, header),
    ui.scroll({ flexGrow = 1, gap = 8 }, content),
    ui.row({ gap = 12, align = "center" }, {
      iconLine("clock", updated),
      iconLine("pointer", "Right-click the bar to refresh"),
    }),
  }))
end

noctalia.state.watch("limits", function(v) limits = v or {}; render() end)
function onOpen(_ctx)
  limits = noctalia.state.get("limits") or {}
  noctalia.state.set("command", { action = "refresh", at = noctalia.nowMs() })
  panel.setWantsSecondTicks(true)
  render()
end
function onClose() panel.setWantsSecondTicks(false) end
function update() render() end
render()
