--!nonstrict
-- Bar widget: glow icon, temperature coloured by heat, 12-hour sparkline and an air-quality dot.

local wx = noctalia.state.get("wx")
local expanded = false -- collapsed to icon + temperature until hovered

local function series(kind)
  if type(wx) ~= "table" or not wx.hours then return nil end
  local vals, lo, hi = {}, 1e9, -1e9
  for i = 1, math.min(#wx.hours, 12) do
    local v = (kind == "rain") and wx.hours[i].rain or wx.hours[i].temp
    table.insert(vals, v)
    lo, hi = math.min(lo, v), math.max(hi, v)
  end
  if #vals < 2 then return nil end
  for i, v in ipairs(vals) do
    if kind == "rain" then
      vals[i] = v / 100
    else
      vals[i] = (hi > lo) and (0.15 + 0.7 * (v - lo) / (hi - lo)) or 0.5
    end
  end
  return vals
end

local function render()
  local vertical = barWidget.isVertical()
  local container = vertical and ui.column or ui.row
  if type(wx) ~= "table" or not wx.ok then
    barWidget.render(container({ gap = 6, align = "center" }, {
      ui.image({ path = "icons/cloudy.png", width = 20, height = 20 }),
      ui.label({ text = "…" }),
    }))
    barWidget.setTooltip(type(wx) == "table" and wx.error or "Loading weather…")
    return
  end

  local n = wx.now
  local useFeels = noctalia.getConfig("temperature") ~= "actual"
  local t = useFeels and n.feels or n.temp
  local children = {
    ui.image({ path = "icons/" .. n.icon .. ".png", width = 20, height = 20 }),
    ui.label({ text = tostring(t) .. "°" }),
  }
  local reveal = expanded and not vertical
  if reveal and noctalia.getConfig("show_condition") then
    table.insert(children, ui.label({ text = n.label }))
  end
  local kind = noctalia.getConfig("sparkline") or "temp"
  local vals = (kind ~= "off" and reveal) and series(kind) or nil
  if vals then
    table.insert(children, ui.graph({
      values = vals,
      color = (kind == "rain") and "#6fb6ff" or "primary",
      lineWidth = 1.5,
      fillOpacity = 0.25,
      width = 34,
      height = 14,
    }))
  end
  if reveal and noctalia.getConfig("show_aqi") and wx.aqi then
    table.insert(children, ui.box({ width = 7, height = 7, radius = 4, fill = wx.aqi.color }))
  end
  barWidget.render(container({ gap = 6, align = "center", onHover = "onHover" }, children))

  local rows = {
    { key = wx.place ~= "" and wx.place or "Weather", value = n.label },
    { key = "Temperature", value = string.format("%d° (feels %d°)", n.temp, n.feels) },
    { key = "Humidity", value = tostring(n.humidity) .. "%" },
    { key = "Wind", value = string.format("%d km/h %s", n.wind, n.windDir) },
  }
  if wx.aqi then
    table.insert(rows, { key = "Air quality", value = string.format("%d · %s", wx.aqi.us, wx.aqi.label) })
  end
  table.insert(rows, { key = (wx.sun.nextKind == "sunset") and "Sunset in" or "Sunrise in", value = wx.sun.nextIn })
  barWidget.setTooltip(rows)
end

noctalia.state.watch("wx", function(v)
  wx = v
  render()
end)

function update()
  noctalia.setUpdateInterval(5 * 60 * 1000)
  render()
end

function onClick()
  noctalia.togglePanel("hani/glow-weather:panel")
end

function onRightClick()
  noctalia.togglePanel("hani/glow-weather:panel")
end

function onHover(state)
  local want = state == "true"
  if want ~= expanded then
    expanded = want
    render()
  end
end
