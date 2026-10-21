--!nonstrict
-- Helpers shared by the bar widget and the panel.
local M = {}
local PLUGIN = noctalia.pluginDir()
local HOME = noctalia.getenv("HOME") or ""

-- One place for the icon (also `icon` in plugin.toml).
M.ICON = "brand-meta"

function M.dur(s)
  s = math.max(0, math.floor(s))
  if s < 60 then return `{s}s` elseif s < 3600 then return `{s // 60}m` elseif s < 86400 then return `{s // 3600}h` end
  return `{s // 86400}d`
end

function M.ago(ms) return M.dur((noctalia.nowMs() - ms) / 1000) end

-- Epoch ms -> "2h 14m" / "3d 5h" until then, or nil when unknown or past.
function M.resetsIn(ms)
  local left = ms and ms > noctalia.nowMs() and math.floor((ms - noctalia.nowMs()) / 60000) or nil
  if not left then return nil end
  return left >= 1440 and `{left // 1440}d {left % 1440 // 60}h` or `{left // 60}h {left % 60}m`
end

-- The widget's accent: the accent_color setting (Facebook blue by default), or the theme primary when empty.
local accentSetting = noctalia.string.trim(tostring(noctalia.getConfig("accent_color") or ""))
local ACCENT = accentSetting ~= "" and accentSetting or "primary"

-- A colour at some alpha: "role/0.15" for palette roles, an alpha byte on "#rrggbb" or "#rrggbbaa" hex.
-- Hex in other lengths is returned as is.
function M.tint(color, alpha)
  if alpha == nil then return color end
  if string.sub(color, 1, 1) ~= "#" then return `{color}/{alpha}` end
  if #color ~= 7 and #color ~= 9 then return color end
  return string.sub(color, 1, 7) .. string.format("%02x", math.floor(alpha * 255 + 0.5))
end

function M.accent(alpha) return M.tint(ACCENT, alpha) end

-- Limit colours: warn_color from 70% (yellow by default) and critical_color from 90% (red by default).
-- Noctalia has no yellow palette role (tertiary is often green or teal) and some themes' error is pink,
-- so both are hex settings. An empty critical_color uses the theme's error colour.
local function colorSetting(key, fallback)
  local v = noctalia.string.trim(tostring(noctalia.getConfig(key) or ""))
  return v ~= "" and v or fallback
end
local WARN = colorSetting("warn_color", "#FFC53D")
local CRITICAL = colorSetting("critical_color", "error")

function M.severity(pct) return pct >= 90 and CRITICAL or pct >= 70 and WARN or M.accent() end

-- limits.sh exit codes (see service.luau) -> what to tell the user.
M.ERRORS = {
  not_signed_in = "Not signed in to Muse (run `muse login`)",
  expired = "Muse sign-in expired (run `muse login`)",
  failed = "Could not fetch Muse limits",
}

function M.errorText(err)
  if not err then return nil end
  local text = M.ERRORS[err.kind] or M.ERRORS.failed
  if err.kind == "failed" and err.detail and err.detail ~= "" then text = `{text}: {err.detail}` end
  return text
end

-- Usage arrives with the first Muse request in OpenCode (open-muse's usage file), so a fetch can
-- succeed with no windows before that.
M.NO_USAGE = "No usage yet: it shows after your first Muse request in OpenCode"
function M.noUsage(limits)
  return limits.updated ~= nil and limits.error == nil and #(limits.windows or {}) == 0
end

-- Paths under the home folder show as ~/...
function M.projectPath(p)
  if HOME ~= "" and (p == HOME or string.sub(p, 1, #HOME + 1) == HOME .. "/") then return "~" .. string.sub(p, #HOME + 1) end
  return p
end

local function quote(s) return "'" .. string.gsub(s, "'", "'\\''") .. "'" end

-- Brings the terminal of the OpenCode TUI with this pid to the front (focus.sh, copied from claude-sessions).
function M.focus(pid) noctalia.runAsync({ PLUGIN .. "/focus.sh", tostring(pid) }) end

function M.resumeCommand(cwd, id) return `cd {quote(cwd)} && opencode -s {id}` end

return M
