--!nonstrict
-- Helpers shared by the bar widget and the panel.
local M = {}

-- One place for the icon (also `icon` in plugin.toml).
M.ICON = "brand-openai"

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

-- Same thresholds as the Claude widget: 90% and up is red, 70% and up amber.
function M.severity(pct) return pct >= 90 and "error" or pct >= 70 and "secondary" or "primary" end

-- limits.sh exit codes (see service.luau) -> what to tell the user.
M.ERRORS = {
  not_signed_in = "Not signed in to ChatGPT in OpenCode (run `opencode auth login`)",
  expired = "ChatGPT sign-in expired (open OpenCode to refresh it)",
  failed = "Could not fetch Codex limits",
}

function M.errorText(err)
  if not err then return nil end
  local text = M.ERRORS[err.kind] or M.ERRORS.failed
  if err.kind == "failed" and err.detail and err.detail ~= "" then text = `{text}: {err.detail}` end
  return text
end

return M
