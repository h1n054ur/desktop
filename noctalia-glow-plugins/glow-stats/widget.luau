--!nonstrict
-- One stat per widget instance; the icon steps through heat levels (icons/<stat>-<level>.png).

-- upper bounds per level; the last level catches everything above
local LEVELS = {
  cpu = { 30, 70 },          -- 3 levels (percent busy)
  cpu_temp = { 55, 70, 85 }, -- 4 levels (degrees C)
  gpu_temp = { 50, 65, 80 },
  ram = { 40, 65, 85 },      -- percent of total
}

local function level(stat, v)
  local bounds = LEVELS[stat]
  for i, b in ipairs(bounds) do
    if v < b then return i end
  end
  return #bounds + 1
end

local function read(stat, s)
  if stat == "cpu" then
    local v = s.cpu and s.cpu.usagePercent
    return v, v and string.format("%d%%", math.floor(v + 0.5))
  elseif stat == "cpu_temp" then
    local v = s.cpu and s.cpu.tempC
    return v, v and string.format("%d°C", math.floor(v + 0.5))
  elseif stat == "gpu_temp" then
    local v = s.gpu and s.gpu.tempC
    return v, v and string.format("%d°C", math.floor(v + 0.5))
  else
    local r = s.ram
    if not r or not r.totalMb or r.totalMb == 0 then return nil, nil end
    return r.usagePercent or (100 * r.usedMb / r.totalMb), string.format("%.1f GiB", r.usedMb / 1024)
  end
end

local function fmt(v, unit)
  return v and string.format("%d%s", math.floor(v + 0.5), unit) or "–"
end

function update()
  noctalia.setUpdateInterval(2000)
  local stat = noctalia.getConfig("stat") or "cpu"
  local s = noctalia.systemStats()
  if not s then
    barWidget.setText("–")
    return
  end
  local v, text = read(stat, s)
  local lvl = v and level(stat, v) or 1
  local children = { ui.image({ path = "icons/" .. stat .. "-" .. lvl .. ".png", width = 20, height = 20 }) }
  if noctalia.getConfig("show_value") and text then
    local hot = lvl == #LEVELS[stat] + 1
    table.insert(children, ui.label({ text = text, color = hot and "error" or nil }))
  end
  barWidget.render(ui.row({ gap = 5, align = "center" }, children))

  local ram = s.ram and s.ram.usedMb and string.format("%.1f / %.1f GiB", s.ram.usedMb / 1024, (s.ram.totalMb or 0) / 1024) or "–"
  barWidget.setTooltip({
    { key = "CPU", value = fmt(s.cpu and s.cpu.usagePercent, "%") .. ((s.cpu and s.cpu.freqMhz) and string.format(" · %.2f GHz", s.cpu.freqMhz / 1000) or "") },
    { key = "CPU temp", value = fmt(s.cpu and s.cpu.tempC, "°C") },
    { key = "GPU", value = fmt(s.gpu and s.gpu.usagePercent, "%") .. " · " .. fmt(s.gpu and s.gpu.tempC, "°C") },
    { key = "RAM", value = ram },
    { key = "Load", value = s.loadAvg and string.format("%.2f %.2f %.2f", s.loadAvg[1], s.loadAvg[2], s.loadAvg[3]) or "–" },
  })
end
