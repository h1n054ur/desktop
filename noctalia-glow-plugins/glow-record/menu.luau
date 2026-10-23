--!nonstrict
-- Right-click menu of the record button, drawn as a small floating panel because bar widgets have no
-- context menu: where to record from (`recorder set default_source`), the long recording toggle
-- (`recorder set long`) and a way into the library panel.
local shared = require("./shared.luau")

local settings = nil
local loaded = false
local pending = false

local render

local function publish(s)
  settings = s
  loaded = true
  noctalia.state.set("settings", s)
  render()
end

local function reload()
  shared.loadSettings(function(s) publish(s) end)
end

local function set(key, value)
  if pending then return end
  pending = true
  noctalia.runAsync({ "recorder", "set", key, value }, function(res)
    pending = false
    if res.exitCode ~= 0 then noctalia.log("recorder set " .. key .. " failed: " .. tostring(res.stderr)) end
    reload()
  end, 5000)
end

local function isLong()
  return settings ~= nil and (settings.long == true or settings.long == "true")
end

local function sourceRow(source)
  local selected = settings ~= nil and settings.default_source == source
  return ui.row({
    gap = 10, align = "center", paddingH = 10, height = 32, radius = 8,
    fill = selected and "primary/0.08" or "#00000000",
    onClick = function() if not selected then set("default_source", source) end end,
  }, {
    ui.glyph({ name = selected and "circle-dot" or "circle", size = 15, color = selected and "primary" or "on_surface_variant" }),
    ui.glyph({ name = source == "mic" and "microphone" or "volume", size = 14, color = "on_surface_variant" }),
    ui.label({ text = shared.SOURCE_LABEL[source], fontSize = 13, color = "on_surface" }),
  })
end

render = function()
  local kids = {}
  if not noctalia.commandExists("recorder") then
    kids[#kids + 1] = ui.label({ text = "recorder not installed", fontSize = 13, color = "on_surface_variant" })
    panel.render(ui.column({ gap = 8, padding = 12 }, kids))
    return
  end

  kids[#kids + 1] = ui.row({ paddingH = 10 }, {
    ui.label({ text = "Record from", fontSize = 12, color = "on_surface_variant/0.7" }),
  })
  for _, s in ipairs(shared.SOURCES) do kids[#kids + 1] = sourceRow(s) end
  kids[#kids + 1] = ui.separator({ orientation = "horizontal", color = "outline", spacing = 4 })

  local known = settings ~= nil and settings.long ~= nil
  kids[#kids + 1] = ui.row({ gap = 10, align = "start", paddingH = 10 }, {
    ui.toggle({
      checked = isLong(),
      enabled = known and not pending,
      onChange = function(v) set("long", v and "true" or "false") end,
    }),
    ui.column({ gap = 2, flexGrow = 1 }, {
      ui.label({ text = "Long recording (Opus)", fontSize = 13, color = "on_surface" }),
      ui.label({
        text = known and "Smaller files for hours of audio" or (loaded and "Needs a newer recorder" or "Loading"),
        fontSize = 12, color = "on_surface_variant", maxLines = 2,
      }),
    }),
  })
  kids[#kids + 1] = ui.separator({ orientation = "horizontal", color = "outline", spacing = 4 })

  kids[#kids + 1] = ui.row({
    gap = 10, align = "center", paddingH = 10, height = 32, radius = 8,
    onClick = function()
      panel.close()
      noctalia.togglePanel("hani/glow-record:panel")
    end,
  }, {
    ui.glyph({ name = "list-details", size = 14, color = "on_surface_variant" }),
    ui.label({ text = "Open library", fontSize = 13, color = "on_surface" }),
    ui.spacer({ flexGrow = 1 }),
    ui.label({ text = "Super+Alt+L", fontSize = 12, color = "on_surface_variant/0.7" }),
  })

  panel.render(ui.column({ gap = 4, padding = 10 }, kids))
end

function onOpen(_ctx)
  render()
  reload()
end

render()
