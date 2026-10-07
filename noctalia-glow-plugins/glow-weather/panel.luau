--!nonstrict
-- Panel: current conditions, detail tiles, 24-hour graph with hover readout, 7-day forecast.

local wx = noctalia.state.get("wx")
local hovered = nil -- hovered hour index on the graph
local isOpen = false

local function icon(name, size)
  return ui.image({ path = "icons/" .. name .. ".png", width = size, height = size })
end

local function tile(iconName, value, caption)
  return ui.column({ gap = 4, align = "center", padding = 10, radius = 14, fill = "surface_variant/0.55", flexGrow = 1 }, {
    icon(iconName, 30),
    ui.label({ text = value, fontSize = 15, fontWeight = "bold", textAlign = "center" }),
    ui.label({ text = caption, fontSize = 11, color = "on_surface_variant", textAlign = "center" }),
  })
end

local function header()
  local n = wx.now
  local right = {}
  if wx.aqi then
    right = {
      ui.row({ gap = 6, align = "center", paddingH = 10, paddingV = 6, radius = 12, fill = "surface_variant/0.55" }, {
        icon("air-quality", 22),
        ui.column({ gap = 0 }, {
          ui.label({ text = "AQI " .. wx.aqi.us, fontSize = 14, fontWeight = "bold", color = wx.aqi.color }),
          ui.label({ text = wx.aqi.label, fontSize = 10, color = "on_surface_variant", maxWidth = 120, maxLines = 2 }),
        }),
      }),
    }
  end
  return ui.row({ gap = 14, align = "center" }, {
    icon(n.icon, 84),
    ui.column({ gap = 2, flexGrow = 1 }, {
      ui.label({ text = n.temp .. "°", fontSize = 44, fontWeight = "bold", color = n.tempColor }),
      ui.row({ gap = 6, align = "center" }, {
        icon(n.thermo, 16),
        ui.label({ text = "Feels " .. n.feels .. "° · " .. n.label, fontSize = 14, color = n.feelsColor }),
      }),
      ui.label({
        text = (wx.place ~= "" and (wx.place .. " · ") or "") .. "Updated " .. wx.updated .. (wx.stale and " · offline" or ""),
        fontSize = 11,
        color = "on_surface_variant",
      }),
    }),
    ui.column({ gap = 0, align = "end" }, right),
  })
end

local function tiles()
  local n, s = wx.now, wx.sun
  local nextIcon = (s.nextKind == "sunset") and "sunset" or "sunrise"
  return ui.row({ gap = 8 }, {
    tile("humidity", n.humidity .. "%", "Humidity"),
    tile("wind", n.wind .. " km/h", n.windDir .. (n.gusts and (" · gusts " .. n.gusts) or "")),
    tile("uv-index", n.uv and tostring(n.uv) or "–", "UV index"),
    tile(nextIcon, s.nextIn, (s.nextKind == "sunset" and "Sunset " .. s.set) or ("Sunrise " .. s.rise)),
  })
end

function onGraphMove(normX)
  local count = #wx.hours
  local i = math.floor(tonumber(normX) * count) + 1
  i = math.max(1, math.min(count, i))
  if i ~= hovered then
    hovered = i
    render()
  end
end

function onGraphLeave()
  hovered = nil
  render()
end

local function hourly()
  local temps, rains, lo, hi = {}, {}, 1e9, -1e9
  for _, h in ipairs(wx.hours) do
    lo, hi = math.min(lo, h.temp), math.max(hi, h.temp)
  end
  for _, h in ipairs(wx.hours) do
    table.insert(temps, (hi > lo) and (0.12 + 0.76 * (h.temp - lo) / (hi - lo)) or 0.5)
    table.insert(rains, h.rain / 100)
  end
  local h = wx.hours[hovered or 1]
  local readout = string.format("%s · %d° (feels %d°) · %s · %d%% rain", hovered and h.hh or "Now", h.temp, h.feels, h.label, h.rain)

  local strip = {}
  for i = 1, #wx.hours, 3 do
    local x = wx.hours[i]
    table.insert(strip, ui.column({ gap = 2, align = "center", flexGrow = 1 }, {
      ui.label({ text = (i == 1) and "Now" or x.hh, fontSize = 10, color = "on_surface_variant" }),
      icon(x.icon, 26),
      ui.label({ text = x.temp .. "°", fontSize = 12, fontWeight = "bold" }),
      ui.label({ text = x.rain > 0 and (x.rain .. "%") or " ", fontSize = 9, color = "#6fb6ff" }),
    }))
  end

  return ui.column({ gap = 6, padding = 12, radius = 14, fill = "surface_variant/0.35" }, {
    ui.row({ align = "center" }, {
      ui.label({ text = "Next 24 hours", fontSize = 13, fontWeight = "bold", flexGrow = 1 }),
      ui.label({ text = string.format("%d° – %d°", lo, hi), fontSize = 11, color = "on_surface_variant" }),
    }),
    ui.label({ text = readout, fontSize = 12, color = hovered and "primary" or "on_surface_variant" }),
    ui.graph({
      values = temps,
      values2 = rains,
      color = "primary",
      color2 = "#6fb6ff",
      lineWidth = 2,
      fillOpacity = 0.18,
      height = 70,
      onPointerMove = "onGraphMove",
      onPointerLeave = "onGraphLeave",
    }),
    ui.row({ gap = 0 }, strip),
  })
end

local function daily()
  local rows = {}
  local span = math.max(1, wx.weekMax - wx.weekMin)
  for _, d in ipairs(wx.days) do
    table.insert(rows, ui.row({ gap = 10, align = "center", paddingV = 2 }, {
      ui.label({ text = d.name, fontSize = 13, fontWeight = (d.name == "Today") and "bold" or "normal", width = 52 }),
      icon(d.icon, 26),
      ui.row({ gap = 2, align = "center", width = 48 }, {
        icon("humidity", 12),
        ui.label({ text = d.rain .. "%", fontSize = 11, color = d.rain >= 30 and "#6fb6ff" or "on_surface_variant" }),
      }),
      ui.label({ text = d.min .. "°", fontSize = 12, color = "on_surface_variant", width = 32, textAlign = "end" }),
      ui.progress({ progress = (d.max - wx.weekMin) / span, fill = "primary", track = "surface_variant", height = 6, radius = 3, flexGrow = 1 }),
      ui.label({ text = d.max .. "°", fontSize = 12, fontWeight = "bold", width = 32 }),
    }))
  end
  return ui.column({ gap = 4, padding = 12, radius = 14, fill = "surface_variant/0.35" }, rows)
end

function render()
  if not isOpen then return end
  if type(wx) ~= "table" or not wx.ok then
    panel.render(ui.column({ gap = 12, align = "center", justify = "center", padding = 24 }, {
      icon("cloudy", 72),
      ui.label({ text = (type(wx) == "table" and wx.error) or "Loading weather…", fontSize = 14 }),
    }))
    return
  end
  panel.render(ui.column({ gap = 12, padding = 16 }, {
    header(),
    tiles(),
    hourly(),
    daily(),
  }))
end

noctalia.state.watch("wx", function(v)
  wx = v
  render()
end)

function onOpen()
  isOpen = true
  hovered = nil
  wx = noctalia.state.get("wx")
  render()
end

function onClose()
  isOpen = false
end
