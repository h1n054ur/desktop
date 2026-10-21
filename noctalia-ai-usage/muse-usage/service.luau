--!nonstrict
-- Muse Code plan limits, read through limits.sh (a short-lived `muse serve` host, read-only, no model
-- request). limits.sh fetch prints [{label, percent, resets_at}] like the other widgets' limits.sh; on
-- failure it exits 2 (not signed in), 3 (expired) or anything else (request failed), message on stderr.
-- Muse only knows usage after it has talked to the model, so a successful fetch is often [] for now:
-- the bar and panel show that as "no usage yet", not as an error.
-- Published as state "limits" = { windows, updated, plan, error, pending }.
--
-- OpenCode sessions come from sessions.sh (the OpenCode background service's own API, read-only), every
-- few seconds; with no service running it prints [] at once. Published as state "sessions" =
-- [{ id, title, cwd, status = busy|waiting|idle, since, waitingFor, tool, pid, terminal, provider, model }],
-- sorted waiting > busy > idle, newest first. Notifications use the same settings as the Claude widget.
-- Only sessions whose model provider matches the "providers" setting (a regex, default ^muse$, the
-- provider id of the open-muse OpenCode plugin) show here. Sessions whose provider cannot be told stay
-- on the Codex widget, so this one runs sessions.sh without --keep-unknown.
local PLUGIN = noctalia.pluginDir()
local FRESH_MS = 5 * 60000 -- min gap between API calls (failures included, so a broken sign-in backs off too)
local MANUAL_MS = 30000 -- min gap for a manual refresh (right-click on the bar)
local KINDS = { [2] = "not_signed_in", [3] = "expired" }
local SESSIONS_MS = 3000 -- sessions.sh poll interval
local RANK = { waiting = 0, busy = 1, idle = 2 }
local PROVIDERS = "^muse$" -- default of the "providers" setting

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

-- Plan tier ("Everyday" and so on) is optional: limits.sh may not support it, so any failure is ignored.
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
      -- The tier comes with the usage, so asking for it before any usage would start a host for nothing.
      if not api.plan and #list > 0 then fetchPlan() end
    else
      -- Keep the last good windows so the bar still shows them; the panel says they are stale.
      local detail = noctalia.string.trim(r.stderr or "")
      api.error = { kind = KINDS[r.exitCode] or "failed", detail = detail, at = noctalia.nowMs() }
      if detail ~= "" then noctalia.log(`muse-usage: limits ({r.exitCode}): {detail}`) end
    end
    publish()
  end, 20000)
  if not started then
    api.pending = false
    api.error = { kind = "failed", detail = "could not start limits.sh", at = noctalia.nowMs() }
  end
  publish()
end

-- ── Sessions ────────────────────────────────────────────────────────────────

local sess = { pending = false, tracked = {} } -- tracked: id -> { status, busySince }

local function cfg(key, fallback)
  local v = noctalia.getConfig(key)
  if v == nil then return fallback end
  return v
end

local function dur(ms)
  local m = math.floor(ms / 60000)
  if m < 60 then return `{m}m` end
  return `{m // 60}h {m % 60}m`
end

-- Notifications on waiting / finished, like the Claude widget (same setting names).
local function track(list)
  local alive = {}
  for _, s in ipairs(list) do
    alive[s.id] = true
    local t = sess.tracked[s.id]
    if t then
      if t.status ~= "waiting" and s.status == "waiting" and cfg("notify_waiting", true) then
        noctalia.notify("Muse needs you", s.title .. (s.waitingFor ~= "" and (": " .. s.waitingFor) or ""))
      elseif t.status == "busy" and s.status == "idle" and cfg("notify_finished", true) and t.busySince then
        local took = s.since - t.busySince
        if took >= (tonumber(cfg("finished_min_minutes", 2)) or 2) * 60000 then
          noctalia.notify("Muse finished", `{s.title} · {dur(took)}`)
        end
      end
    else
      t = {}
      sess.tracked[s.id] = t
    end
    if s.status == "busy" and t.status ~= "busy" and t.status ~= "waiting" then t.busySince = s.since end
    t.status = s.status
  end
  for id in pairs(sess.tracked) do if not alive[id] then sess.tracked[id] = nil end end
end

local function pollSessions()
  if sess.pending then return end
  sess.pending = true
  local providers = noctalia.string.trim(tostring(cfg("providers", PROVIDERS)))
  local started = noctalia.runAsync({ PLUGIN .. "/sessions.sh", providers }, function(r)
    sess.pending = false
    local list = r.exitCode == 0 and noctalia.json.decode(r.stdout or "") or nil
    if type(list) ~= "table" then
      local detail = noctalia.string.trim(r.stderr or "")
      if detail ~= "" then noctalia.log(`muse-usage: sessions ({r.exitCode}): {detail}`) end
      return
    end
    track(list)
    local hideMs = (tonumber(cfg("hide_idle_hours", 0)) or 0) * 3600000
    local now, shown = noctalia.nowMs(), {}
    for _, s in ipairs(list) do
      if not (hideMs > 0 and s.status == "idle" and now - (s.since or 0) > hideMs) then shown[#shown + 1] = s end
    end
    table.sort(shown, function(a, b)
      local ra, rb = RANK[a.status] or 3, RANK[b.status] or 3
      if ra ~= rb then return ra < rb end
      return (a.since or 0) > (b.since or 0)
    end)
    noctalia.state.set("sessions", shown)
  end, 10000)
  if not started then sess.pending = false end
end

local function poll(force)
  local gap = force and MANUAL_MS or FRESH_MS
  if noctalia.nowMs() - api.lastTry >= gap then fetchLimits() end
end

-- Panel open asks for "refresh" (normal 5-minute gap); right-click on the bar asks for "force".
noctalia.state.watch("command", function(v)
  if type(v) == "table" then
    pollSessions()
    if v.action == "force" then poll(true) elseif v.action == "refresh" then poll(false) end
  end
end)
-- Limits keep their own 5-minute gap inside poll(); the timer runs at the sessions pace.
function update() pollSessions(); poll(false) end
function onIpc(event) if event == "refresh" then pollSessions(); poll(true) end end
function onConfigChanged() publish(); pollSessions() end
noctalia.setUpdateInterval(SESSIONS_MS)
pollSessions()
poll(false)
