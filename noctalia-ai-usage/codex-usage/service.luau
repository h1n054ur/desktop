--!nonstrict
-- ChatGPT plan limits for Codex, read through limits.sh (OpenCode's own ChatGPT sign-in, read-only).
-- limits.sh fetch prints [{label, percent, resets_at}] like the Claude widget's limits.sh; on failure it
-- exits 2 (not signed in), 3 (token expired) or anything else (request failed), message on stderr.
-- Published as state "limits" = { windows, updated, plan, error, pending }.
local PLUGIN = noctalia.pluginDir()
local FRESH_MS = 5 * 60000 -- min gap between API calls (failures included, so a broken sign-in backs off too)
local MANUAL_MS = 30000 -- min gap for a manual refresh (right-click on the bar)
local KINDS = { [2] = "not_signed_in", [3] = "expired" }

local api = { windows = nil, at = 0, lastTry = -math.huge, pending = false, plan = nil, error = nil }

-- "2026-10-01T20:29:59.766+00:00" -> epoch ms (UTC; honours the offset).
local function isoToMs(iso)
  local y, mo, d, h, mi, sec, sign, oh, om = string.match(iso or "",
    "^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)[%.%d]*([%+%-]?)(%d*):?(%d*)")
  if not y then return nil end
  y, mo, d = tonumber(y), tonumber(mo), tonumber(d)
  -- days since epoch (Howard Hinnant's days_from_civil)
  if mo <= 2 then y -= 1 end
  local era = (y >= 0 and y or y - 399) // 400
  local yoe = y - era * 400
  local doy = (153 * ((mo + 9) % 12) + 2) // 5 + d - 1
  local days = era * 146097 + yoe * 365 + yoe // 4 - yoe // 100 + doy - 719468
  local secs = days * 86400 + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(sec)
  if sign ~= "" and oh ~= "" then
    local off = tonumber(oh) * 3600 + (tonumber(om) or 0) * 60
    secs = sign == "+" and secs - off or secs + off
  end
  return secs * 1000
end

local function publish()
  local windows = {}
  for _, w in ipairs(api.windows or {}) do
    if type(w) == "table" and tonumber(w.percent) then
      windows[#windows + 1] = { label = w.label or "?", percent = tonumber(w.percent), resetsAt = isoToMs(w.resets_at) }
    end
  end
  noctalia.state.set("limits", {
    windows = windows,
    updated = api.at > 0 and api.at or nil,
    plan = api.plan,
    error = api.error,
    pending = api.pending,
  })
end

-- Plan name ("Plus", "Pro") is optional: limits.sh may not support it, so any failure is ignored.
local function fetchPlan()
  noctalia.runAsync({ PLUGIN .. "/limits.sh", "plan" }, function(r)
    local plan = r.exitCode == 0 and noctalia.string.trim(r.stdout or "") or ""
    if plan ~= "" and plan ~= api.plan then api.plan = plan; publish() end
  end, 20000)
end

local function fetchLimits()
  if api.pending then return end
  api.pending, api.lastTry = true, noctalia.nowMs()
  local started = noctalia.runAsync({ PLUGIN .. "/limits.sh", "fetch" }, function(r)
    api.pending = false
    local list = r.exitCode == 0 and noctalia.json.decode(r.stdout or "") or nil
    if type(list) == "table" then
      api.windows, api.at, api.error = list, noctalia.nowMs(), nil
      if not api.plan then fetchPlan() end
    else
      -- Keep the last good windows so the bar still shows them; the panel says they are stale.
      local detail = noctalia.string.trim(r.stderr or "")
      api.error = { kind = KINDS[r.exitCode] or "failed", detail = detail, at = noctalia.nowMs() }
      if detail ~= "" then noctalia.log(`codex-usage: limits ({r.exitCode}): {detail}`) end
    end
    publish()
  end, 20000)
  if not started then
    api.pending = false
    api.error = { kind = "failed", detail = "could not start limits.sh", at = noctalia.nowMs() }
  end
  publish()
end

local function poll(force)
  local gap = force and MANUAL_MS or FRESH_MS
  if noctalia.nowMs() - api.lastTry >= gap then fetchLimits() end
end

-- Panel open asks for "refresh" (normal 5-minute gap); right-click on the bar asks for "force".
noctalia.state.watch("command", function(v)
  if type(v) == "table" then
    if v.action == "force" then poll(true) elseif v.action == "refresh" then poll(false) end
  end
end)
function update() poll(false) end
function onIpc(event) if event == "refresh" then poll(true) end end
function onConfigChanged() publish() end
noctalia.setUpdateInterval(30000)
poll(false)
