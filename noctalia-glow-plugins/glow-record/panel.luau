--!nonstrict
-- Library panel for the recorder CLI: recordings grouped by day, search over titles, tags and
-- transcripts, play in place, transcript chip per row, one open row with transcript, tags and
-- actions, and the settings strip. All data comes from `recorder ... --json`; playback goes
-- through `recorder-player` (mpv over IPC).
local lib = require("./lib/library.luau")
local C = lib.COLORS

local PAGE = 40
local RELOAD_EVERY_MS = 10000
local SEARCH_DEBOUNCE_MS = 250

local HOME = noctalia.getenv("HOME") or ""
local STATE_DIR = (noctalia.getenv("XDG_STATE_HOME") or (HOME .. "/.local/state")) .. "/recorder"
local DATA_DIR = (noctalia.getenv("XDG_DATA_HOME") or (HOME .. "/.local/share")) .. "/recorder"
local STATE_FILE = STATE_DIR .. "/state.json"
local WORKER_FILE = STATE_DIR .. "/worker.json"
local DB_FILE = DATA_DIR .. "/recordings.db"

local isOpen = false
local rows = {} -- current page, newest first
local loaded = false
local cliError = nil
local limit = PAGE
local hasMore = false
local totals = { count = 0, size = 0, days = {} }
local query, pendingQuery, queryAt, searchRev = "", nil, 0, 0
local openId, detail = nil, nil -- the open row and its `recorder show` JSON
local renaming, tagging, confirmDelete = nil, nil, nil
local settings = { default_source = "system", auto_transcribe_mic = false, transcribe_model = "small" }
local recState = { state = "idle" }
local worker = nil
local play = nil -- { id, token, pos, dur, paused }
local playToken = 0
local flash, flashAt = nil, 0
local lastKey, lastReload = nil, 0
local busy = { page = false, totals = false, detail = false }
local again = { page = false, totals = false, detail = false }

-- ── Commands ────────────────────────────────────────────────────────────────

local function decode(s)
  if not s or s == "" then return nil end
  local v = noctalia.json.decode(s)
  return v
end

local function readJson(path)
  local raw = noctalia.readFile(path)
  if not raw then return nil end
  return decode(raw)
end

local function mtime(path)
  local info = noctalia.fileInfo(path)
  return info and info.mtime or 0
end

local function say(text)
  flash, flashAt = text, noctalia.nowMs()
end

-- Run `recorder ...` and hand the decoded JSON (or nil and the error text) to cb.
local function recorder(args, cb)
  local argv = { "recorder" }
  for _, a in ipairs(args) do argv[#argv + 1] = a end
  local ok = noctalia.runAsync(argv, function(res)
    if res.exitCode ~= 0 then
      local err = noctalia.string.trim(res.stderr or "")
      if cb then cb(nil, err ~= "" and err or ("recorder exited with " .. tostring(res.exitCode))) end
      return
    end
    if cb then cb(decode(res.stdout), nil) end
  end, 15000)
  if not ok and cb then cb(nil, "could not run recorder") end
end

local loadPage, loadTotals, loadDetail, loadSettings

-- Change a recording, then refresh what shows it.
local function act(args, after)
  recorder(args, function(data, err)
    if err then say(err) end
    if after then after(data, err) end
    loadPage()
    loadTotals()
    loadDetail()
  end)
end

function loadPage()
  if busy.page then again.page = true return end
  busy.page = true
  local args = { "list", "--json", "--limit", tostring(limit) }
  if query ~= "" then
    args[#args + 1] = "--search"
    args[#args + 1] = query
  end
  local asked = query
  recorder(args, function(data, err)
    busy.page = false
    lastReload = noctalia.nowMs()
    if asked == query then
      if err then
        cliError = err
      elseif type(data) == "table" then
        cliError = nil
        rows = data
        hasMore = #data >= limit
        loaded = true
      end
    end
    if again.page then again.page = false loadPage() end
    render()
  end)
end

-- Header and day totals cover every recording, so they come from `recorder stats`, not the page.
function loadTotals()
  if busy.totals then again.totals = true return end
  busy.totals = true
  recorder({ "stats", "--json" }, function(data)
    busy.totals = false
    if type(data) == "table" then totals = lib.fromStats(data) end
    if again.totals then again.totals = false loadTotals() end
    render()
  end)
end

function loadDetail()
  if not openId then detail = nil return end
  if busy.detail then again.detail = true return end
  busy.detail = true
  local id = openId
  recorder({ "show", "--json", tostring(id) }, function(data)
    busy.detail = false
    if id == openId then detail = type(data) == "table" and data or nil end
    if again.detail then again.detail = false loadDetail() end
    render()
  end)
end

function loadSettings()
  recorder({ "settings", "--json" }, function(data)
    if type(data) == "table" then
      for k, v in pairs(data) do settings[k] = v end
      render()
    end
  end)
end

local function setSetting(key, value)
  settings[key] = value
  render()
  recorder({ "set", key, tostring(value) }, function(_data, err)
    if err then say(err) end
    loadSettings()
  end)
end

-- ── Playback ────────────────────────────────────────────────────────────────

local function shq(s) return "'" .. string.gsub(s, "'", "'\\''") .. "'" end

local function stopPlayback()
  if play then noctalia.runAsync({ "recorder-player", "stop" }) end
  play = nil
end

local function togglePlay(row)
  if play and play.id == row.id then
    noctalia.runAsync({ "recorder-player", "pause" })
    play.paused = not play.paused
    render()
    return
  end
  local files = row.files or {}
  if #files == 0 then say("This recording has no files") render() return end
  playToken += 1
  local token = playToken
  play = { id = row.id, token = token, pos = 0, dur = tonumber(row.duration_s) or 0, paused = false }
  local cmd = "exec recorder-player play " .. shq(files[1]) .. (files[2] and (" " .. shq(files[2])) or "")
  local ok = noctalia.runStream(cmd, function(line)
    if not play or play.token ~= token then return end
    local msg = decode(line)
    if type(msg) ~= "table" then return end
    if msg["end"] then
      play = nil
      if msg.error then say(msg.error) end
    elseif msg.pos then
      play.pos, play.dur, play.paused = tonumber(msg.pos) or 0, tonumber(msg.dur) or play.dur, msg.paused == true
    end
    render()
  end)
  if not ok then play = nil say("Could not start the player") end
  render()
end

local function seek(row, frac)
  if not play or play.id ~= row.id or play.dur <= 0 then return end
  local t = math.max(0, math.min(play.dur, frac * play.dur))
  play.pos = t
  noctalia.runAsync({ "recorder-player", "seek", string.format("%.1f", t) })
  render()
end

-- ── Small pieces ────────────────────────────────────────────────────────────

local function label(text, size, color, weight, extra)
  local p = { text = text, fontSize = size, color = color or C.text, fontWeight = weight, maxLines = 1 }
  if extra then for k, v in pairs(extra) do p[k] = v end end
  return ui.label(p)
end

local function dot(color, size)
  size = size or 10
  return ui.box({ width = size, height = size, radius = size / 2, fill = color, softness = 1 })
end

local function iconButton(glyph, tooltip, fn, color)
  return ui.row({ width = 27, height = 27, radius = 8, align = "center", justify = "center", tooltip = tooltip,
    onClick = fn }, { ui.glyph({ name = glyph, size = 15, color = color or C.text2 }) })
end

local function textButton(glyph, text, fn, color, filled)
  return ui.row({ gap = 6, height = 30, paddingH = 10, radius = 8, align = "center",
    fill = filled and lib.tint(color or C.green, 0.12) or C.variant,
    border = filled and lib.tint(color or C.green, 0.5) or C.outline, borderWidth = 1, onClick = fn }, {
    ui.glyph({ name = glyph, size = 14, color = color or C.text }),
    label(text, 13, color or C.text),
  })
end

-- The transcript chip: 96 x 24, doubles as the action for its state.
local function chip(row)
  local state, pct = lib.chip(row, worker)
  local id = row.id
  local function base(color, fillA, kids, fn, tooltip, borderColor)
    return ui.row({ width = 96, height = 24, radius = 12, gap = 5, paddingH = 8, align = "center", justify = "center",
      fill = fillA and lib.tint(color, fillA) or nil, border = borderColor or lib.tint(color, 0.55), borderWidth = 1,
      onClick = fn, tooltip = tooltip }, kids)
  end
  if state == "queued" then
    return base(C.cyan, 0.08, { ui.glyph({ name = "clock", size = 13, color = C.cyan }), label("Queued", 12, C.cyan) })
  elseif state == "running" then
    return base(C.cyan, 0.1, {
      label(pct .. "%", 12, C.cyan, "bold"),
      ui.progress({ progress = pct / 100, width = 34, height = 4, radius = 2, fill = C.cyan, track = lib.tint(C.cyan, 0.2) }),
    })
  elseif state == "done" then
    return base(C.green, 0.08, { ui.glyph({ name = "check", size = 13, color = C.green }), label("Transcript", 12, C.green) },
      function() openRow(id) end)
  elseif state == "nospeech" then
    return base(C.faint, nil, { ui.glyph({ name = "volume-off", size = 13, color = C.faint }), label("No speech", 12, C.faint) },
      nil, "The transcript found no speech in this recording")
  elseif state == "failed" then
    return base(C.red, 0.08, { ui.glyph({ name = "alert-triangle", size = 13, color = C.red }), label("Failed", 12, C.red) },
      function() act({ "transcribe", tostring(id) }) end, "Click to retry. " .. tostring(row.error or "Transcription failed"))
  end
  return base(C.text2, nil, { ui.glyph({ name = "file-text", size = 13, color = C.text2 }), label("Transcribe", 12, C.text2) },
    function() act({ "transcribe", tostring(id) }) end, "Queue a transcript", C.faint)
end

local function waveform(row, playing)
  local bars = lib.resample(row.peaks, 29)
  local played = 0
  if playing and play.dur > 0 then played = play.pos / play.dur end
  local kids = {}
  for i, v in ipairs(bars) do
    local on = playing and (i - 0.5) / 29 <= played
    local box = { width = 2, height = math.max(2, math.floor(v * 22 + 0.5)), radius = 1, fill = on and C.green or C.wave }
    if playing then
      local frac = (i - 1) / 29
      box.onClick = function() seek(row, frac) end
    end
    kids[i] = ui.box(box)
  end
  return ui.row({ width = 88, height = 24, gap = 1, align = "center", justify = "center" }, kids)
end

local function metaLine(row, p)
  local kids = {
    label(p and lib.clock(p) or "", 12, C.faint),
    ui.glyph({ name = lib.SOURCE_GLYPH[row.source] or "volume", size = 12, color = C.faint }),
    label(lib.SOURCE_LABEL[row.source] or tostring(row.source or ""), 12, C.faint),
  }
  for _, t in ipairs(row.tags or {}) do kids[#kids + 1] = label(t, 12, C.tag) end
  if row.format == "opus" then
    kids[#kids + 1] = ui.row({ paddingH = 4, radius = 4, border = C.outline, borderWidth = 1 }, { label("Opus", 11, C.text2) })
  end
  return ui.row({ gap = 5, align = "center" }, kids)
end

-- ── Rows ────────────────────────────────────────────────────────────────────

function openRow(id)
  if openId == id then
    openId, detail = nil, nil
  else
    openId, detail = id, nil
    loadDetail()
  end
  renaming, tagging = nil, nil
  render()
end

local function deleteRow(row)
  local title = lib.title(row)
  return ui.row({ key = "row:" .. row.id, gap = 10, paddingH = 12, paddingV = 10, align = "center", minHeight = 54,
    fill = lib.tint(C.red, 0.07) }, {
    ui.glyph({ name = "trash", size = 16, color = C.red }),
    ui.column({ gap = 2, flexGrow = 1 }, {
      label('Delete "' .. title .. '"?', 13, C.text, "semibold"),
      label("The files move to ~/Recordings/.trash", 12, C.text2),
    }),
    ui.button({ text = "Cancel", variant = "ghost", controlSize = "sm", onClick = function() confirmDelete = nil render() end }),
    ui.button({ text = "Delete", variant = "destructive", controlSize = "sm", onClick = function()
      confirmDelete = nil
      if play and play.id == row.id then stopPlayback() end
      if openId == row.id then openId, detail = nil, nil end
      act({ "delete", tostring(row.id) })
    end }),
  })
end

local function titleCell(row, p)
  local title, untitled = lib.title(row)
  local top
  if renaming == row.id then
    top = ui.row({ gap = 4, align = "center" }, {
      ui.input({ key = "rename:" .. row.id, value = row.title or "", placeholder = "Title", focus = true,
        controlSize = "sm", fontSize = 13, flexGrow = 1,
        onSubmit = function(text)
          renaming = nil
          text = noctalia.string.trim(text or "")
          if text ~= "" and text ~= row.title then act({ "rename", tostring(row.id), text }) else render() end
        end }),
      iconButton("x", "Cancel", function() renaming = nil render() end),
    })
  else
    top = label(title, 14, untitled and C.text2 or C.text, "semibold")
  end
  local kids = { top }
  if query ~= "" and (row.snippet or "") ~= "" then
    kids[#kids + 1] = ui.markdown({ text = lib.snippetMarkdown(row.snippet) })
  end
  kids[#kids + 1] = metaLine(row, p)
  return ui.column({ gap = 3, flexGrow = 1 }, kids)
end

local function lengthCell(row, playing)
  if playing then
    return ui.column({ width = 46, gap = 0, align = "end" }, {
      label(lib.dur(play.pos), 13, C.green, "semibold"),
      label(lib.dur(play.dur), 12, C.faint),
    })
  end
  return ui.column({ width = 46, align = "end" }, { label(lib.dur(row.duration_s), 13, C.text) })
end

local function transcriptBlock(row)
  local state = lib.chip(row, worker)
  local d = detail and detail.id == row.id and detail or nil
  local words = lib.words(query)
  if state == "done" then
    if not d then return { label("Loading transcript", 12, C.faint) } end
    local text = d.transcript or ""
    local n = lib.countMatches(text, words)
    local model = d.transcript_model and d.transcript_model ~= "" and d.transcript_model or "local model"
    return {
      ui.row({ gap = 6, align = "center" }, {
        label("Transcript, " .. model .. (n > 0 and (", " .. lib.plural(n, "match")) or ""), 12, C.faint, nil, { flexGrow = 1 }),
      }),
      ui.column({ padding = 12, radius = 8, fill = C.surface, border = C.outline, borderWidth = 1 }, {
        ui.markdown({ text = lib.transcriptMarkdown(text, words) }),
      }),
    }
  elseif state == "nospeech" then
    return { label("No speech found in this recording.", 12, C.faint) }
  elseif state == "failed" then
    return { label("Transcript failed: " .. tostring(row.error or "unknown error"), 12, C.red, nil, { maxLines = 3 }) }
  elseif state == "queued" or state == "running" then
    return { label("The transcript is on its way.", 12, C.cyan) }
  end
  return { label("No transcript yet.", 12, C.faint) }
end

local function tagsRow(row)
  local kids = {}
  for _, t in ipairs(row.tags or {}) do
    kids[#kids + 1] = ui.row({ key = "tag:" .. row.id .. ":" .. t, gap = 4, height = 24, paddingH = 9, radius = 12,
      align = "center", fill = lib.tint(C.tag, 0.08), border = lib.tint(C.tag, 0.45), borderWidth = 1 }, {
      label(t, 12, C.tag),
      ui.row({ tooltip = "Remove tag", onClick = function() act({ "untag", tostring(row.id), t }) end }, {
        ui.glyph({ name = "x", size = 11, color = C.tag }),
      }),
    })
  end
  if tagging == row.id then
    kids[#kids + 1] = ui.input({ key = "tagin:" .. row.id, placeholder = "tag, Enter adds", focus = true,
      controlSize = "sm", fontSize = 12, width = 150,
      onSubmit = function(text)
        tagging = nil
        local args = { "tag", tostring(row.id) }
        for w in string.gmatch(text or "", "[^%s,]+") do args[#args + 1] = w end
        if #args > 2 then act(args) else render() end
      end })
    kids[#kids + 1] = iconButton("x", "Cancel", function() tagging = nil render() end)
  else
    kids[#kids + 1] = ui.row({ gap = 4, height = 24, paddingH = 9, radius = 12, align = "center",
      border = C.outline, borderWidth = 1, onClick = function() tagging = row.id render() end }, {
      ui.glyph({ name = "tag", size = 12, color = C.text2 }),
      label("Add tag", 12, C.text2),
    })
  end
  return ui.row({ gap = 6, align = "center" }, kids)
end

local function actionsRow(row)
  local state = lib.chip(row, worker)
  local id = tostring(row.id)
  local kids = {
    iconButton("pencil", "Rename", function() renaming = row.id tagging = nil render() end),
    iconButton("tag", "Add a tag", function() tagging = row.id renaming = nil render() end),
    iconButton("copy", "Copy the file path", function()
      noctalia.copyToClipboard(table.concat(row.files or {}, "\n"), "text/plain")
      say("Path copied")
      render()
    end),
    iconButton("trash", "Delete", function() confirmDelete = row.id render() end, C.red),
    ui.spacer({ flexGrow = 1 }),
  }
  if state ~= "queued" and state ~= "running" then
    local redo = state == "done" or state == "nospeech" or state == "failed"
    kids[#kids + 1] = textButton("refresh", redo and "Transcribe again" or "Transcribe",
      function() act({ "transcribe", id }) end)
  end
  if state == "done" then
    kids[#kids + 1] = textButton("notebook", "Send to Notes", function()
      act({ "to-notes", id }, function(data)
        if data and data.path then say("Saved to " .. string.gsub(data.path, "^" .. HOME, "~")) end
      end)
    end, C.green, true)
  end
  return ui.row({ gap = 6, align = "center" }, kids)
end

local function recordingRow(row)
  if confirmDelete == row.id then return deleteRow(row) end
  local p = lib.parseTime(row.started_at)
  local playing = play ~= nil and play.id == row.id
  local isOpenRow = openId == row.id
  local playBtn = ui.row({ width = 30, height = 30, radius = 15, align = "center", justify = "center",
    fill = playing and C.green or C.variant, border = playing and C.green or C.outline, borderWidth = 1,
    tooltip = playing and (play.paused and "Resume" or "Pause") or "Play",
    onClick = function() togglePlay(row) end }, {
    ui.glyph({ name = (playing and not play.paused) and "player-pause-filled" or "player-play-filled", size = 13,
      color = playing and C.surface or C.text }),
  })
  local line = ui.row({ gap = 10, align = "center", minHeight = 54, paddingH = 12, paddingV = 8,
    onClick = function() openRow(row.id) end }, {
    playBtn,
    titleCell(row, p),
    waveform(row, playing),
    lengthCell(row, playing),
    chip(row),
    ui.glyph({ name = isOpenRow and "chevron-up" or "chevron-down", size = 16, color = C.faint }),
  })
  local kids = { line }
  if isOpenRow then
    local body = {}
    for _, n in ipairs(transcriptBlock(row)) do body[#body + 1] = n end
    body[#body + 1] = tagsRow(row)
    body[#body + 1] = actionsRow(row)
    kids[#kids + 1] = ui.column({ gap = 10, paddingH = 12, paddingV = 10 }, body)
  end
  return ui.column({ key = "row:" .. row.id, gap = 0,
    fill = (playing or isOpenRow) and C.hover or nil }, kids)
end

-- ── Sections ────────────────────────────────────────────────────────────────

local function todayStrings()
  local now = os.time()
  return os.date("%Y-%m-%d", now), os.date("%Y-%m-%d", now - 86400), now
end

local function daysAgo(p, now)
  local t = os.time({ year = p.y, month = p.mo, day = p.d, hour = 12 })
  return math.floor((now - t) / 86400 + 0.5)
end

local function dayGroup(g, today, yesterday, now)
  local p = lib.parseTime(g.rows[1].started_at)
  local right = ""
  local t = totals.days[g.day]
  if query == "" and t then right = lib.plural(t.count, "recording") .. ", " .. lib.durWords(t.dur) end
  local kids = {}
  for i, r in ipairs(g.rows) do
    if i > 1 then kids[#kids + 1] = ui.separator({ orientation = "horizontal", color = C.outline, thickness = 1 }) end
    kids[#kids + 1] = recordingRow(r)
  end
  return ui.column({ key = "day:" .. g.day, gap = 8 }, {
    ui.row({ gap = 8, align = "center", paddingH = 2 }, {
      label(p and lib.dayName(p, today, yesterday, daysAgo(p, now)) or g.day, 13.5, C.text, "bold"),
      label(p and lib.shortDate(p) or "", 12.5, C.faint, nil, { flexGrow = 1 }),
      label(right, 12, C.faint),
    }),
    ui.column({ gap = 0, radius = 10, fill = C.group, border = C.outline, borderWidth = 1 }, kids),
  })
end

local function header()
  local sub = totals.count > 0 and (lib.plural(totals.count, "recording") .. ", " .. lib.size(totals.size)) or ""
  local st = recState.state or "idle"
  local btnText, dotColor = "Record", C.red
  if st == "recording" then
    btnText = "Stop " .. lib.dur(recState.elapsed_s)
  elseif st == "paused" then
    btnText, dotColor = "Stop " .. lib.dur(recState.elapsed_s), C.amber
  end
  return ui.row({ gap = 10, align = "center", height = 32 }, {
    dot(lib.tint(C.green, st == "idle" and 0.35 or 0.8), 20),
    label("Recordings", 17, C.text, "bold"),
    label(sub, 12, C.faint, nil, { flexGrow = 1 }),
    ui.row({ gap = 7, height = 27, paddingH = 10, radius = 8, align = "center",
      fill = lib.tint(C.green, 0.08), border = lib.tint(C.green, 0.5), borderWidth = 1,
      tooltip = st == "idle" and "Start recording" or "Stop and save",
      onClick = function()
        noctalia.runAsync({ "recorder", "toggle" }, function() lastKey = nil end, 15000)
      end }, {
      dot(dotColor, 10),
      label(btnText, 13, C.green),
    }),
  })
end

local function searchBox()
  local active = query ~= "" or (pendingQuery or "") ~= ""
  local kids = {
    ui.glyph({ name = "search", size = 15, color = active and C.text or C.text2 }),
    ui.input({ key = "search:" .. searchRev, placeholder = "Search titles and transcripts", frameVisible = false,
      fontSize = 13, controlSize = "sm", flexGrow = 1,
      onChange = function(text)
        pendingQuery, queryAt = text or "", noctalia.nowMs()
        panel.setNeedsFrameTick(true)
      end,
      onSubmit = function(text) pendingQuery, queryAt = text or "", 0 end }),
  }
  if active then
    kids[#kids + 1] = iconButton("x", "Clear the search", function()
      searchRev += 1
      pendingQuery, query, limit = nil, "", PAGE
      loadPage()
      render()
    end)
  end
  return ui.row({ gap = 8, height = 38, paddingH = 12, radius = 8, align = "center", fill = C.variant,
    border = active and C.green or C.outline, borderWidth = 1 }, kids)
end

local function emptyState()
  local src = lib.SOURCE_LABEL[settings.default_source] or "System"
  local what = settings.default_source == "mic" and "your mic" or settings.default_source == "both"
    and "system sound and mic as two tracks" or "system sound"
  return ui.column({ gap = 12, align = "center", justify = "center", paddingV = 60, paddingH = 30, flexGrow = 1 }, {
    dot(lib.tint(C.green, 0.3), 46),
    label("No recordings yet", 14, C.text, "bold"),
    label("Press Super+Alt+R or click the dot on the bar. It records " .. what ..
      " (default: " .. src .. ").", 13, C.text2, nil, { maxLines = 3, textAlign = "center", maxWidth = 380 }),
    ui.row({ gap = 7, height = 30, paddingH = 12, radius = 8, align = "center",
      fill = lib.tint(C.green, 0.08), border = lib.tint(C.green, 0.5), borderWidth = 1,
      onClick = function() noctalia.runAsync({ "recorder", "toggle" }, function() lastKey = nil end, 15000) end }, {
      dot(C.red, 10),
      label("Start recording", 13, C.green),
    }),
  })
end

local function segment()
  local kids = {}
  for _, s in ipairs({ "system", "mic", "both" }) do
    local on = settings.default_source == s
    kids[#kids + 1] = ui.row({ key = "src:" .. s, height = 27, paddingH = 12, radius = 6, align = "center",
      fill = on and C.green or nil, onClick = function() setSetting("default_source", s) end }, {
      label(lib.SOURCE_LABEL[s], 12.5, on and C.surface or C.text2, on and "bold" or nil),
    })
  end
  return ui.row({ gap = 0, radius = 8, fill = C.variant, border = C.outline, borderWidth = 1, padding = 1 }, kids)
end

local function settingsStrip()
  local model = settings.transcribe_model or "small"
  local idx = 2
  for i, m in ipairs(lib.MODELS) do if m == model then idx = i - 1 end end
  return ui.column({ gap = 10 }, {
    ui.separator({ orientation = "horizontal", color = C.outline, thickness = 1 }),
    ui.row({ gap = 8, align = "center" }, {
      label("Default source", 13, C.text, nil, { flexGrow = 1 }),
      segment(),
    }),
    ui.row({ gap = 8, align = "center" }, {
      ui.column({ gap = 1, flexGrow = 1 }, {
        label("Auto-transcribe mic recordings", 13, C.text),
        label("Queues a transcript when a mic recording stops", 12, C.faint),
      }),
      ui.toggle({ checked = settings.auto_transcribe_mic == true,
        onChange = function(v) setSetting("auto_transcribe_mic", v == "true") end }),
    }),
    ui.row({ gap = 6, align = "center" }, {
      ui.glyph({ name = "folder", size = 13, color = C.faint }),
      label("~/Recordings", 12, C.faint, nil, { flexGrow = 1 }),
      label("Model", 12, C.faint),
      ui.select({ options = lib.MODELS, selectedIndex = idx, controlSize = "sm", width = 150,
        onChange = function(i)
          local m = lib.MODELS[(tonumber(i) or 0) + 1]
          if m and m ~= settings.transcribe_model then setSetting("transcribe_model", m) end
        end }),
    }),
  })
end

function render()
  if not isOpen then return end
  local content = {}
  if cliError and not loaded then
    content[#content + 1] = ui.column({ gap = 8, align = "center", paddingV = 60 }, {
      ui.glyph({ name = "alert-triangle", size = 28, color = C.red }),
      label("The recorder CLI did not answer", 13, C.text, "bold"),
      label(cliError, 12, C.text2, nil, { maxLines = 4, textAlign = "center", maxWidth = 420 }),
    })
  elseif loaded and query == "" and #rows == 0 then
    content[#content + 1] = emptyState()
  else
    if query ~= "" then
      local n = #rows
      local count = hasMore and (n .. "+") or tostring(n)
      content[#content + 1] = label((n == 1 and not hasMore) and ('1 recording matches "' .. query .. '"')
        or (count .. ' recordings match "' .. query .. '"'), 12, C.faint)
    end
    local today, yesterday, now = todayStrings()
    for _, g in ipairs(lib.groupByDay(rows)) do content[#content + 1] = dayGroup(g, today, yesterday, now) end
    if hasMore then
      content[#content + 1] = ui.row({ gap = 6, align = "center", justify = "center", paddingV = 8 }, {
        label("Loading older days", 12, C.faint),
      })
    elseif query ~= "" then
      content[#content + 1] = ui.row({ gap = 6, align = "center", paddingV = 4 }, {
        ui.glyph({ name = "search", size = 12, color = C.faint }),
        label("Matches titles, tags and transcripts. The x clears the search.", 12, C.faint),
      })
    end
  end

  local tree = { header(), searchBox() }
  tree[#tree + 1] = ui.scroll({ flexGrow = 1, gap = 14, onScroll = "onListScroll" }, content)
  if flash and noctalia.nowMs() - flashAt < 4000 then
    tree[#tree + 1] = label(flash, 12, C.text2)
  end
  tree[#tree + 1] = settingsStrip()
  panel.render(ui.column({ gap = 12, padding = 16, flexGrow = 1 }, tree))
end

-- ── Polling and events ──────────────────────────────────────────────────────

-- Cheap change check once a second: the recorder state, the worker's progress file, and the
-- database files' mtimes. The list reloads only on a change, or every 10 s as a safety net.
local function poll()
  local st = readJson(STATE_FILE)
  recState = type(st) == "table" and st or { state = "idle" }
  local wk = noctalia.fileExists(WORKER_FILE) and readJson(WORKER_FILE) or nil
  worker = type(wk) == "table" and wk or nil
  local key = table.concat({ mtime(DB_FILE), mtime(DB_FILE .. "-wal"), tostring(recState.state), tostring(recState.id),
    tostring(worker and worker.id or "") }, ":")
  if key ~= lastKey then
    lastKey = key
    loadPage()
    loadTotals()
    loadDetail()
  elseif noctalia.nowMs() - lastReload > RELOAD_EVERY_MS then
    loadPage()
  end
end

function onListScroll(offset, maxOffset)
  local off, max = tonumber(offset) or 0, tonumber(maxOffset) or 0
  if hasMore and not busy.page and max - off < 160 then
    limit += PAGE
    loadPage()
  end
end

function onFrameTick(_deltaMs)
  if pendingQuery ~= nil and noctalia.nowMs() - queryAt >= SEARCH_DEBOUNCE_MS then
    local q = noctalia.string.trim(pendingQuery)
    pendingQuery = nil
    panel.setNeedsFrameTick(false)
    if q ~= query then
      query, limit = q, PAGE
      loadPage()
    end
    render()
  end
end

function update()
  if not isOpen then return end
  poll()
  render()
end

function onOpen(context)
  isOpen = true
  renaming, tagging, confirmDelete = nil, nil, nil
  local id = tonumber(context or "")
  if id then
    openId, detail = id, nil
  end
  lastKey = nil
  panel.setWantsSecondTicks(true)
  loadSettings()
  poll()
  render()
end

function onClose()
  isOpen = false
  stopPlayback()
  renaming, tagging, confirmDelete, pendingQuery = nil, nil, nil, nil
  panel.setWantsSecondTicks(false)
  panel.setNeedsFrameTick(false)
end
