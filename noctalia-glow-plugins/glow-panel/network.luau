--!nonstrict
-- Network icon: Ethernet when a cable link is up, otherwise Wi-Fi with a glow icon per signal strength
-- (wifi-1 .. wifi-4), connecting / no signal / off states. Same widget on the desktop and the laptop.

local ip = nil
local ssid = nil
local lastInfoCheck = 0
local lastInfoIface = nil

local function isWireless(n)
  return noctalia.fileExists("/sys/class/net/" .. n .. "/wireless")
end

local function operstate(n)
  return noctalia.string.trim(noctalia.readFile("/sys/class/net/" .. n .. "/operstate") or "")
end

-- Physical interfaces only (virtual ones like docker0, tailscale0, br-* have no device link)
local function interfaces()
  local wired, wifi = {}, {}
  local names = noctalia.listDir("/sys/class/net") or {}
  table.sort(names)
  for _, n in ipairs(names) do
    if n ~= "lo" and noctalia.fileExists("/sys/class/net/" .. n .. "/device") then
      if isWireless(n) then table.insert(wifi, n) else table.insert(wired, n) end
    end
  end
  return wired, wifi
end

-- Link quality from /proc/net/wireless, as a percentage of the driver's maximum (70 on iwlwifi)
local function wifiQuality(n)
  for line in string.gmatch(noctalia.readFile("/proc/net/wireless") or "", "[^\n]+") do
    local name, q = string.match(line, "^%s*([%w%-_]+):%s+%x+%s+([%d%.]+)")
    if name == n and q then return math.min(100, math.floor(tonumber(q) / 70 * 100 + 0.5)) end
  end
  return nil
end

local function level(pct)
  if not pct or pct <= 0 then return nil end
  if pct >= 75 then return 4 elseif pct >= 50 then return 3 elseif pct >= 25 then return 2 end
  return 1
end

local function refreshInfo(iface, wifi)
  local now = noctalia.nowMs()
  if iface == lastInfoIface and now - lastInfoCheck < 30000 then return end
  lastInfoCheck, lastInfoIface = now, iface
  noctalia.runAsync({ "ip", "-4", "-br", "addr", "show", "dev", iface }, function(res)
    ip = string.match(res.stdout or "", "(%d+%.%d+%.%d+%.%d+/%d+)")
  end)
  if wifi then
    noctalia.runAsync({ "nmcli", "-t", "-g", "GENERAL.CONNECTION", "device", "show", iface }, function(res)
      ssid = noctalia.string.trim(res.stdout or "")
      if ssid == "" then ssid = nil end
    end)
  else
    ssid = nil
  end
end

function update()
  noctalia.setUpdateInterval(3000)
  local wired, wifi = interfaces()

  local up = nil
  for _, n in ipairs(wired) do if operstate(n) == "up" then up = n break end end

  local icon, rows = nil, {}
  if up then
    icon = "wired-active"
    rows = { { key = "Ethernet", value = "Connected" }, { key = "Interface", value = up } }
    refreshInfo(up, false)
    if ip then table.insert(rows, { key = "Address", value = ip }) end
  elseif #wifi > 0 then
    local w = wifi[1]
    for _, n in ipairs(wifi) do if operstate(n) == "up" then w = n break end end
    local state = operstate(w)
    if state == "up" then
      local pct = wifiQuality(w)
      local lvl = level(pct)
      icon = lvl and ("wifi-" .. lvl) or "wifi-no-signal"
      refreshInfo(w, true)
      rows = { { key = "Wi-Fi", value = ssid or "Connected" } }
      if pct then table.insert(rows, { key = "Signal", value = pct .. "%" }) end
      table.insert(rows, { key = "Interface", value = w })
      if ip then table.insert(rows, { key = "Address", value = ip }) end
    elseif state == "dormant" then
      icon = "wifi-connecting"
      rows = { { key = "Wi-Fi", value = "Connecting" }, { key = "Interface", value = w } }
    else
      icon = "wifi-disconnected"
      rows = { { key = "Wi-Fi", value = "Not connected" }, { key = "Interface", value = w } }
    end
  elseif #wired > 0 then
    icon = "wired-error"
    rows = { { key = "Ethernet", value = "Cable unplugged" }, { key = "Interface", value = wired[1] } }
  else
    icon = "wired-disconnected"
    rows = { { key = "Network", value = "No network interface" } }
  end

  barWidget.render(ui.row({ align = "center" }, {
    ui.image({ path = "icons/" .. icon .. ".png", width = 20, height = 20 }),
  }))
  barWidget.setTooltip(rows)
end
