--!nonstrict
-- Shows the window selected on this bar's own screen; hidden when that screen's workspace is empty.

local windows = noctalia.state.get("windows")
local icons = {}

local function iconFor(class)
  if class == nil or class == "" then return nil end
  if icons[class] == nil then
    icons[class] = noctalia.appIconPath(class, 18) or false
  end
  return icons[class] or nil
end

local function render()
  local out = barWidget.outputName()
  if out == nil then
    -- the bar is not attached to an output yet: retry soon instead of hiding for good
    noctalia.setUpdateInterval(500)
    return
  end
  noctalia.setUpdateInterval(60000)
  local w = type(windows) == "table" and windows[out] or nil
  if not w then
    barWidget.setVisible(false)
    return
  end
  barWidget.setVisible(true)
  local children = {}
  local icon = iconFor(w.class)
  if icon then
    table.insert(children, ui.image({ path = icon, width = 16, height = 16 }))
  end
  table.insert(children, ui.label({ text = w.title, maxWidth = noctalia.getConfig("max_width") or 420, maxLines = 1 }))
  barWidget.render(ui.row({ gap = 6, align = "center" }, children))
  barWidget.setTooltip(w.title)
end

noctalia.state.watch("windows", function(v)
  windows = v
  render()
end)

function update()
  render()
end
