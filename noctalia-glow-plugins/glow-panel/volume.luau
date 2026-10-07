--!nonstrict
-- Volume with level icons (mute/low/medium/high). `pactl subscribe` pushes sink changes so the icon
-- follows scrolls and mutes immediately; update() is only a slow fallback.

local volume, muted = nil, false
local pending = false

local function render()
  if volume == nil then
    barWidget.setText("–")
    return
  end
  local pct = math.floor(volume * 100 + 0.5)
  local icon = "vol-high"
  if muted or pct == 0 then
    icon = "vol-mute"
  elseif pct < 34 then
    icon = "vol-low"
  elseif pct < 67 then
    icon = "vol-medium"
  end
  local children = { ui.image({ path = "icons/" .. icon .. ".png", width = 20, height = 20 }) }
  if noctalia.getConfig("show_value") then
    table.insert(children, ui.label({ text = muted and "Muted" or (pct .. "%") }))
  end
  barWidget.render(ui.row({ gap = 5, align = "center" }, children))
  barWidget.setTooltip(muted and string.format("Volume %d%% (muted)", pct) or string.format("Volume %d%%", pct))
end

local function refresh()
  if pending then return end
  pending = true
  noctalia.runAsync({ "wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@" }, function(res)
    pending = false
    local v = res.exitCode == 0 and string.match(res.stdout or "", "Volume:%s*([%d%.]+)") or nil
    if v then
      volume = tonumber(v)
      muted = string.find(res.stdout, "MUTED", 1, true) ~= nil
    end
    render()
  end)
end

-- Noctalia hands its own open pipes to stream children; a long-lived child that keeps them open makes Noctalia
-- wait forever on an unrelated command (it froze at login on 2026-10-08). Close every inherited fd above 2 first.
local SUBSCRIBE = [[python3 -c "import os; os.closerange(3, 65536); os.execvp('pactl', ['pactl', 'subscribe'])"]]

noctalia.runStream(SUBSCRIBE, function(line)
  if string.find(line, "sink", 1, true) or string.find(line, "server", 1, true) then
    refresh()
  end
end)

function update()
  noctalia.setUpdateInterval(15000)
  refresh()
end
