--!nonstrict
-- Pure helpers for the library panel: formatting, day grouping, totals, waveform resampling,
-- transcript chip state and search highlighting. No Noctalia calls here, so tests can load it as is.
local M = {}

M.COLORS = {
  surface = "#06090a",
  outline = "#1d2a26",
  group = "#0b1311",
  variant = "#101816",
  hover = "#13221d",
  text = "#e6f1ee",
  text2 = "#9fb2ac",
  faint = "#71857f",
  wave = "#24332f",
  green = "#39ff14",
  cyan = "#00e5ff",
  tag = "#2bf5a0",
  red = "#ff5c7a",
  amber = "#f5d76e",
}

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local WEEKDAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local WEEKDAYS_LONG = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }

-- "#rrggbb" at an alpha, as "#rrggbbaa".
function M.tint(hex, alpha)
  return string.sub(hex, 1, 7) .. string.format("%02x", math.floor(alpha * 255 + 0.5))
end

-- 48 -> "0:48", 751 -> "12:31", 3725 -> "1:02:05".
function M.dur(s)
  s = math.max(0, math.floor((tonumber(s) or 0) + 0.5))
  local h, m, sec = s // 3600, (s % 3600) // 60, s % 60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, sec) end
  return string.format("%d:%02d", m, sec)
end

-- Day totals: 900 s -> "15 min", 5400 -> "1 h 30 min", 20 -> "20 s".
function M.durWords(s)
  s = math.max(0, math.floor((tonumber(s) or 0) + 0.5))
  if s < 60 then return s .. " s" end
  local m = (s + 30) // 60
  if m < 60 then return m .. " min" end
  if m % 60 == 0 then return (m // 60) .. " h" end
  return (m // 60) .. " h " .. (m % 60) .. " min"
end

function M.size(bytes)
  bytes = tonumber(bytes) or 0
  if bytes >= 1e9 then return string.format("%.1f GB", bytes / 1e9) end
  if bytes >= 1e6 then return string.format("%.1f MB", bytes / 1e6) end
  if bytes >= 1e3 then return string.format("%d kB", math.floor(bytes / 1e3 + 0.5)) end
  return bytes .. " B"
end

function M.plural(n, word)
  if n == 1 then return n .. " " .. word end
  local tail = string.sub(word, -2)
  return n .. " " .. word .. ((tail == "ch" or tail == "sh" or string.sub(word, -1) == "s") and "es" or "s")
end

-- "2026-10-23T14:05:12+05:00" -> { y, mo, d, h, mi, day = "2026-10-23" }
function M.parseTime(iso)
  local y, mo, d, h, mi = string.match(iso or "", "^(%d+)-(%d+)-(%d+)[T ](%d+):(%d+)")
  if not y then return nil end
  return { y = tonumber(y), mo = tonumber(mo), d = tonumber(d), h = tonumber(h), mi = tonumber(mi),
    day = string.sub(iso, 1, 10) }
end

local function weekday(y, mo, d)
  -- Sakamoto's method, 1 = Sunday.
  local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
  if mo < 3 then y = y - 1 end
  return (y + y // 4 - y // 100 + y // 400 + t[mo] + d) % 7 + 1
end

-- "Fri 23 Oct"
function M.shortDate(p)
  return WEEKDAYS[weekday(p.y, p.mo, p.d)] .. " " .. p.d .. " " .. MONTHS[p.mo]
end

function M.clock(p) return string.format("%02d:%02d", p.h, p.mi) end

-- Day header name: Today, Yesterday, a weekday within the last week, else the short date.
-- today and yesterday are "YYYY-MM-DD" strings, daysAgo is how many days back the day is (or nil).
function M.dayName(p, today, yesterday, daysAgo)
  if p.day == today then return "Today" end
  if p.day == yesterday then return "Yesterday" end
  if daysAgo and daysAgo < 7 then return WEEKDAYS_LONG[weekday(p.y, p.mo, p.d)] end
  return MONTHS[p.mo] .. " " .. p.d
end

-- Untitled rows show their date and time instead, marked so the panel draws them dimmer.
function M.title(row)
  local t = row.title
  if t and t ~= "" then return t, false end
  local p = M.parseTime(row.started_at)
  if not p then return "Recording " .. tostring(row.id), true end
  return M.shortDate(p) .. ", " .. M.clock(p), true
end

-- Rows (already sorted newest first) into { { day, rows = {...} }, ... } keeping order.
function M.groupByDay(rows)
  local groups, byDay = {}, {}
  for _, r in ipairs(rows) do
    local day = string.sub(r.started_at or "", 1, 10)
    local g = byDay[day]
    if not g then
      g = { day = day, rows = {} }
      byDay[day] = g
      groups[#groups + 1] = g
    end
    g.rows[#g.rows + 1] = r
  end
  return groups
end

-- Totals over every recording: count, size, and per day count and duration.
function M.totals(rows)
  local out = { count = 0, size = 0, days = {} }
  for _, r in ipairs(rows) do
    out.count += 1
    out.size += tonumber(r.size_bytes) or 0
    local day = string.sub(r.started_at or "", 1, 10)
    local d = out.days[day] or { count = 0, dur = 0 }
    d.count += 1
    d.dur += tonumber(r.duration_s) or 0
    out.days[day] = d
  end
  return out
end

-- Peaks (any length, values 0-1) to exactly n bars, taking the max over each bucket.
function M.resample(peaks, n)
  local out = {}
  local len = type(peaks) == "table" and #peaks or 0
  for i = 1, n do
    if len == 0 then
      out[i] = 0
    else
      local a = math.floor((i - 1) * len / n) + 1
      local b = math.max(a, math.floor(i * len / n))
      local m = 0
      for j = a, math.min(b, len) do
        local v = tonumber(peaks[j]) or 0
        if v > m then m = v end
      end
      out[i] = math.max(0, math.min(1, m))
    end
  end
  return out
end

-- The chip on every row. worker is the progress file ({ id, progress 0-100 }) or nil.
-- Returns one of: none, queued, running (with pct), done, nospeech, failed.
function M.chip(row, worker)
  local st = row.transcript_status or "none"
  if st == "running" then
    local pct = nil
    if worker and tonumber(worker.id) == tonumber(row.id) then pct = tonumber(worker.progress) end
    return "running", math.max(0, math.min(100, math.floor((pct or 0) + 0.5)))
  end
  if st == "done" then
    if row.has_transcript == false or (row.has_transcript == nil and (row.transcript or "") == "") then
      return "nospeech"
    end
    return "done"
  end
  if st == "queued" or st == "failed" then return st end
  return "none"
end

-- Words of a search query, lowercased, as the CLI matches them.
function M.words(q)
  local out = {}
  for w in string.gmatch(string.lower(q or ""), "[%w_\128-\255]+") do out[#out + 1] = w end
  return out
end

-- How many times any search word starts a word in the text (FTS prefix match, case-insensitive).
function M.countMatches(text, words)
  if #words == 0 or not text then return 0 end
  local low, n = string.lower(text), 0
  for _, w in ipairs(words) do
    local i = 1
    while true do
      local s, e = string.find(low, w, i, true)
      if not s then break end
      local before = s > 1 and string.sub(low, s - 1, s - 1) or ""
      if before == "" or not string.match(before, "[%w_\128-\255]") then
        n += 1
      end
      i = e + 1
    end
  end
  return n
end

-- Escape markdown so a transcript renders as plain text.
function M.mdEscape(s)
  return (string.gsub(s, "([\\`*_%[%]#<>|~])", "\\%1"))
end

-- Transcript as markdown: escaped text, each line its own paragraph, the whole word that a
-- search word starts shown in bold. Lines like "[02:14] Mic: text" keep their stamp dim via code.
function M.transcriptMarkdown(text, words)
  local out = {}
  for line in string.gmatch((text or "") .. "\n", "([^\n]*)\n") do
    if line ~= "" then
      local stamp, rest = string.match(line, "^(%[%d+:%d+[:%d]*%])%s*(.*)$")
      local body = rest or line
      local md = {}
      local pos = 1
      local low = string.lower(body)
      while pos <= #body do
        local s, e = string.find(body, "[%w_\128-\255]+", pos)
        if not s then
          md[#md + 1] = M.mdEscape(string.sub(body, pos))
          break
        end
        md[#md + 1] = M.mdEscape(string.sub(body, pos, s - 1))
        local word = string.sub(body, s, e)
        local lw = string.sub(low, s, e)
        local hit = false
        for _, w in ipairs(words) do
          if string.sub(lw, 1, #w) == w then hit = true break end
        end
        md[#md + 1] = hit and ("**" .. M.mdEscape(word) .. "**") or M.mdEscape(word)
        pos = e + 1
      end
      local para = table.concat(md)
      if stamp then para = "`" .. string.sub(stamp, 2, -2) .. "` " .. para end
      out[#out + 1] = para
    end
  end
  return table.concat(out, "\n\n")
end

M.SOURCE_GLYPH = { system = "volume", mic = "microphone", both = "speakerphone" }
M.SOURCE_LABEL = { system = "System", mic = "Mic", both = "Both" }
M.MODELS = { "tiny", "base", "small", "medium", "large-v3", "large-v3-turbo" }

return M
