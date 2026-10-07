--!nonstrict
-- Fetches Open-Meteo forecast + air quality, derives icons/colours/labels and publishes one plain
-- table on the plugin state channel ("wx") for the bar widget and panel.

local FORECAST = "https://api.open-meteo.com/v1/forecast"
local AIR = "https://air-quality-api.open-meteo.com/v1/air-quality"
local LOCATION_CACHE = "~/.cache/noctalia/location.json"

local raw = nil -- last good forecast
local air = nil -- last good air quality
local place = ""
local lastFetchMs = 0
local fetching = false
local lastError = nil

-- WMO weather code -> label and day/night icon names (icons/<name>.png)
local CODES = {
  [0] = { "Clear", "sunny", "clear-night" },
  [1] = { "Mostly clear", "mostly-sunny", "partly-cloudy-night" },
  [2] = { "Partly cloudy", "partly-cloudy", "partly-cloudy-night" },
  [3] = { "Overcast", "overcast", "overcast" },
  [45] = { "Fog", "fog", "fog" },
  [48] = { "Freezing fog", "fog", "fog" },
  [51] = { "Light drizzle", "rain", "rain" },
  [53] = { "Drizzle", "rain", "rain" },
  [55] = { "Heavy drizzle", "rain", "rain" },
  [56] = { "Freezing drizzle", "sleet", "sleet" },
  [57] = { "Freezing drizzle", "sleet", "sleet" },
  [61] = { "Light rain", "rain", "rain" },
  [63] = { "Rain", "rain", "rain" },
  [65] = { "Heavy rain", "heavy-rain", "heavy-rain" },
  [66] = { "Freezing rain", "sleet", "sleet" },
  [67] = { "Freezing rain", "sleet", "sleet" },
  [71] = { "Light snow", "snow", "snow" },
  [73] = { "Snow", "snow", "snow" },
  [75] = { "Heavy snow", "snow", "snow" },
  [77] = { "Snow grains", "snow", "snow" },
  [80] = { "Showers", "rain", "rain" },
  [81] = { "Showers", "rain", "rain" },
  [82] = { "Violent showers", "heavy-rain", "heavy-rain" },
  [85] = { "Snow showers", "snow", "snow" },
  [86] = { "Snow showers", "snow", "snow" },
  [95] = { "Thunderstorm", "thunderstorm", "thunderstorm" },
  [96] = { "Thunderstorm, hail", "thunderstorm", "thunderstorm" },
  [99] = { "Thunderstorm, hail", "thunderstorm", "thunderstorm" },
}

local function condition(code, isDay, wind, pm25)
  local c = CODES[code] or { "Unknown", "cloudy", "cloudy" }
  local label, icon = c[1], (isDay and c[2] or c[3])
  -- Open-Meteo has no haze/wind codes: derive them for otherwise dry skies
  if code <= 3 and pm25 and pm25 >= 75 then
    return "Haze", "haze"
  end
  if code <= 3 and wind and wind >= 35 then
    return label .. ", windy", "windy"
  end
  return label, icon
end

local function tempStyle(t)
  if t == nil then return "on_surface", "mild" end
  if t <= 0 then return "#9cc4ff", "freezing" end
  if t < 15 then return "#7fb0ff", "cold" end
  if t < 26 then return "on_surface", "mild" end
  if t < 33 then return "#ffb35c", "warm" end
  return "#ff6b5b", "hot"
end

local function aqiStyle(us)
  if us == nil then return nil, nil end
  if us <= 50 then return "Good", "#5fd38d" end
  if us <= 100 then return "Moderate", "#f2c94c" end
  if us <= 150 then return "Unhealthy for sensitive groups", "#ff9f43" end
  if us <= 200 then return "Unhealthy", "#ff5c5c" end
  if us <= 300 then return "Very unhealthy", "#b06cff" end
  return "Hazardous", "#a0204a"
end

local function round(x)
  if x == nil then return nil end
  return math.floor(x + 0.5)
end

local function clock(t, offset)
  local s = (t + offset) % 86400
  return string.format("%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60))
end

local WEEKDAYS = { "Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed" } -- 1970-01-01 was a Thursday
local function weekday(t, offset)
  return WEEKDAYS[(math.floor((t + offset) / 86400) % 7) + 1]
end

local function duration(sec)
  local m = math.max(0, math.floor(sec / 60))
  if m >= 60 then
    return string.format("%dh %02dm", math.floor(m / 60), m % 60)
  end
  return string.format("%dm", m)
end

local function compass(deg)
  if deg == nil then return "" end
  local dirs = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
  return dirs[(math.floor((deg + 22.5) / 45) % 8) + 1]
end

local function coords()
  local lat, lon = noctalia.getConfig("latitude") or 0, noctalia.getConfig("longitude") or 0
  if lat ~= 0 or lon ~= 0 then
    return lat, lon, ""
  end
  local body = noctalia.readFile(LOCATION_CACHE)
  if body then
    local loc = noctalia.json.decode(body)
    if loc and loc.latitude and loc.longitude then
      return loc.latitude, loc.longitude, tostring(loc.name or "")
    end
  end
  return nil, nil, ""
end

local function publish()
  if not raw then
    noctalia.state.set("wx", { ok = false, error = lastError or "Loading weather…" })
    return
  end
  local nowS = math.floor(noctalia.nowMs() / 1000)
  local off = raw.utc_offset_seconds or 0
  local c = raw.current
  local pm25 = air and air.current and air.current.pm2_5 or nil
  local label, icon = condition(c.weather_code, c.is_day == 1, c.wind_speed_10m, pm25)
  local tColor, tKind = tempStyle(c.temperature_2m)
  local fColor, fKind = tempStyle(c.apparent_temperature)

  local hours = {}
  local h = raw.hourly
  for i = 1, math.min(#h.time, 24) do
    local hl, hi = condition(h.weather_code[i], h.is_day[i] == 1, nil, nil)
    table.insert(hours, {
      t = h.time[i],
      hh = clock(h.time[i], off),
      temp = round(h.temperature_2m[i]),
      feels = round(h.apparent_temperature[i]),
      rain = h.precipitation_probability[i] or 0,
      icon = hi,
      label = hl,
    })
  end

  local days = {}
  local d = raw.daily
  local wmin, wmax = 1e9, -1e9
  for i = 1, #d.time do
    local dl, di = condition(d.weather_code[i], true, nil, nil)
    local lo, hi = round(d.temperature_2m_min[i]), round(d.temperature_2m_max[i])
    wmin, wmax = math.min(wmin, lo), math.max(wmax, hi)
    table.insert(days, {
      name = (i == 1) and "Today" or weekday(d.time[i] + 43200, off),
      icon = di,
      label = dl,
      min = lo,
      max = hi,
      rain = d.precipitation_probability_max[i] or 0,
      uv = d.uv_index_max[i],
    })
  end

  -- next sun event: today's sunrise/sunset, else tomorrow's sunrise
  local rise, set = d.sunrise[1], d.sunset[1]
  local nextKind, nextAt
  if nowS < rise then
    nextKind, nextAt = "sunrise", rise
  elseif nowS < set then
    nextKind, nextAt = "sunset", set
  else
    nextKind, nextAt = "sunrise", d.sunrise[2] or rise + 86400
  end

  local aqi = nil
  if air and air.current and air.current.us_aqi then
    local al, ac = aqiStyle(air.current.us_aqi)
    aqi = {
      us = round(air.current.us_aqi),
      pm25 = round(air.current.pm2_5),
      pm10 = round(air.current.pm10),
      label = al,
      color = ac,
    }
  end

  noctalia.state.set("wx", {
    ok = true,
    stale = lastError,
    place = place,
    updated = clock(raw.current.time, off),
    now = {
      temp = round(c.temperature_2m),
      feels = round(c.apparent_temperature),
      humidity = round(c.relative_humidity_2m),
      wind = round(c.wind_speed_10m),
      gusts = round(c.wind_gusts_10m),
      windDir = compass(c.wind_direction_10m),
      uv = c.uv_index and (math.floor(c.uv_index * 10 + 0.5) / 10) or nil,
      label = label,
      icon = icon,
      tempColor = tColor,
      feelsColor = fColor,
      thermo = fKind,
      isDay = c.is_day == 1,
    },
    aqi = aqi,
    hours = hours,
    days = days,
    weekMin = wmin,
    weekMax = wmax,
    sun = {
      rise = clock(rise, off),
      set = clock(set, off),
      nextKind = nextKind,
      nextIn = duration(nextAt - nowS),
    },
  })
end

local function fetch()
  if fetching then return end
  local lat, lon, name = coords()
  if not lat then
    lastError = "No location yet"
    publish()
    return
  end
  fetching = true
  place = name
  lastFetchMs = noctalia.nowMs()
  local q = string.format("?latitude=%.4f&longitude=%.4f&timezone=auto&timeformat=unixtime", lat, lon)
  local url = FORECAST .. q
    .. "&current=temperature_2m,apparent_temperature,relative_humidity_2m,is_day,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index"
    .. "&hourly=temperature_2m,apparent_temperature,precipitation_probability,weather_code,is_day"
    .. "&forecast_hours=24"
    .. "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,uv_index_max"
    .. "&forecast_days=7"
  noctalia.http({ url = url }, function(res)
    fetching = false
    local data = res.ok and noctalia.json.decode(res.body) or nil
    if data and data.current and data.hourly and data.daily then
      raw = data
      lastError = nil
    else
      lastError = "Weather fetch failed (" .. tostring(res.status) .. ")"
      noctalia.log(lastError)
    end
    publish()
  end)
  noctalia.http({ url = AIR .. q .. "&current=us_aqi,pm2_5,pm10" }, function(res)
    local data = res.ok and noctalia.json.decode(res.body) or nil
    if data and data.current then
      air = data
      publish()
    end
  end)
end

function update()
  noctalia.setUpdateInterval(60 * 1000)
  local every = (noctalia.getConfig("refresh_minutes") or 15) * 60 * 1000
  if lastFetchMs == 0 or noctalia.nowMs() - lastFetchMs >= every then
    fetch()
  else
    publish() -- keep the sun countdown fresh
  end
end

function onConfigChanged()
  lastFetchMs = 0
  fetch()
end

function onIpc(event)
  if event == "refresh" then
    lastFetchMs = 0
    fetch()
  end
end
