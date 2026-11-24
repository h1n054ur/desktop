--!nonstrict
-- Headphone button: one click puts the default output back to full volume. It unmutes the default sink,
-- sets it to 100% and, when that sink is an ALSA card with a hardware PCM control, sets the card's PCM
-- to 100% as well (some USB headsets lower it on their own). The icon lights up for two seconds after a
-- click. A failing command still leaves the button usable.

local MAX_CMD = table.concat({
  "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0",
  "wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0",
  "c=$(wpctl inspect @DEFAULT_AUDIO_SINK@ | sed -n 's/.*api.alsa.pcm.card = \"\\([0-9]*\\)\".*/\\1/p' | head -1)",
  "if [ -n \"$c\" ]; then amixer -q -c \"$c\" sset PCM 100% unmute 2>/dev/null; fi",
  "exit 0",
}, "; ")

local FLASH_TICKS = 2
local flash = 0
local busy = false

local function render()
  local icon = flash > 0 and "boost-active" or "boost-idle"
  barWidget.render(ui.row({ gap = 5, align = "center" }, {
    ui.image({ path = "icons/" .. icon .. ".png", width = 20, height = 20 }),
  }))
  barWidget.setTooltip({
    { "Headphones", "full volume" },
    { "Left click", "set output to 100%" },
  })
end

function onClick()
  if busy then return end
  busy = true
  flash = FLASH_TICKS
  render()
  local started = noctalia.runAsync({ "sh", "-c", MAX_CMD }, function(_res)
    busy = false
  end, 5000)
  if not started then busy = false end
end

function update()
  noctalia.setUpdateInterval(1000)
  if flash > 0 then
    flash -= 1
    if flash == 0 then render() end
  end
end

render()
