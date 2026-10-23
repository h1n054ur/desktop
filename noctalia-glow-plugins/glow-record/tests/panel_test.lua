-- Harness for panel.luau: a fake Noctalia API (ui.*, panel.*, noctalia.*), canned `recorder`
-- JSON for every row state, and scenarios that click through the rendered tree.
local dir = arg[1]

-- ── tiny JSON ───────────────────────────────────────────────────────────────
local json = {}
function json.decode(s)
  local i = 1
  local function ws() i = s:find("[^ \t\r\n]", i) or #s + 1 end
  local val
  local function str()
    i = i + 1
    local buf = {}
    while true do
      local c = s:sub(i, i)
      if c == '"' then i = i + 1 break end
      if c == "\\" then
        local n = s:sub(i + 1, i + 1)
        local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" }
        if n == "u" then buf[#buf + 1] = utf8.char(tonumber(s:sub(i + 2, i + 5), 16)) i = i + 6
        else buf[#buf + 1] = map[n] or n i = i + 2 end
      else buf[#buf + 1] = c i = i + 1 end
    end
    return table.concat(buf)
  end
  function val()
    ws()
    local c = s:sub(i, i)
    if c == "{" then
      i = i + 1 local t = {} ws()
      if s:sub(i, i) == "}" then i = i + 1 return t end
      while true do
        ws() local k = str() ws() i = i + 1 t[k] = val() ws()
        local d = s:sub(i, i) i = i + 1
        if d == "}" then return t end
      end
    elseif c == "[" then
      i = i + 1 local t = {} ws()
      if s:sub(i, i) == "]" then i = i + 1 return t end
      while true do
        t[#t + 1] = val() ws()
        local d = s:sub(i, i) i = i + 1
        if d == "]" then return t end
      end
    elseif c == '"' then return str()
    elseif s:sub(i, i + 3) == "true" then i = i + 4 return true
    elseif s:sub(i, i + 4) == "false" then i = i + 5 return false
    elseif s:sub(i, i + 3) == "null" then i = i + 4 return nil
    else
      local num = s:match("^-?[%d.eE+-]+", i) i = i + #num return tonumber(num)
    end
  end
  local ok, v = pcall(val)
  if ok then return v end
  return nil, "bad json"
end

local function enc(v)
  local t = type(v)
  if t == "table" then
    if #v > 0 or next(v) == nil then
      local p = {} for _, x in ipairs(v) do p[#p + 1] = enc(x) end
      return "[" .. table.concat(p, ",") .. "]"
    end
    local p = {} for k, x in pairs(v) do p[#p + 1] = enc(tostring(k)) .. ":" .. enc(x) end
    return "{" .. table.concat(p, ",") .. "}"
  elseif t == "string" then
    return '"' .. v:gsub('[\\"]', "\\%0"):gsub("\n", "\\n") .. '"'
  elseif t == "boolean" or t == "number" then return tostring(v) end
  return "null"
end

-- ── fake world ──────────────────────────────────────────────────────────────
local HOME = "/home/test"
local clock = 1000000
local files = {} -- path -> { content, mtime }
local calls = {} -- every runAsync argv
local streams = {} -- { cmd, onLine }
local clipboard = nil
local lastTree = nil
local frameTick, secondTicks = false, false

local today = os.date("%Y-%m-%d")
local yesterday = os.date("%Y-%m-%d", os.time() - 86400)
local older = os.date("%Y-%m-%d", os.time() - 2 * 86400)
local PEAKS = {}
for k = 1, 30 do PEAKS[k] = (k % 7) / 7 end

local function rec(id, day, hm, extra)
  local r = { id = id, started_at = day .. "T" .. hm .. ":00+05:00", duration_s = 120 + id, source = "system",
    format = "flac", files = { HOME .. "/Recordings/" .. day .. "_" .. id .. ".flac" }, size_bytes = 300000000,
    title = "Rec " .. id, tags = {}, transcript_status = "none", has_transcript = false, peaks = PEAKS,
    error = nil, deleted = false }
  for k, v in pairs(extra or {}) do r[k] = v end
  return r
end

local ALL = {
  rec(1, today, "14:05", { title = "Persona clip", tags = { "voice" }, transcript_status = "done", has_transcript = true, duration_s = 48 }),
  rec(2, today, "10:02", { title = "Standup notes", source = "mic", tags = { "work" }, transcript_status = "running" }),
  rec(3, today, "09:41", { title = "", source = "both", transcript_status = "queued",
    files = { HOME .. "/Recordings/a-system.flac", HOME .. "/Recordings/a-mic.flac" } }),
  rec(4, yesterday, "16:30", { title = "Call with client", source = "both", format = "opus", transcript_status = "done", has_transcript = true }),
  rec(5, older, "20:15", { title = "Intro, take 2", transcript_status = "done", has_transcript = false }),
  rec(6, older, "11:12", { title = "Mic check", source = "mic", transcript_status = "failed", error = "CUDA out of memory" }),
  rec(7, older, "08:00", { title = "Recording " .. older .. " 08:00" }),
}
local TRANSCRIPT = "[02:14] Mic: The build is green on main, so push it to staging this afternoon.\n[02:31] Mic: If staging holds until Monday we tag the release."

local listData = ALL
local listOverride = nil -- function(args) -> rows
local failCli = false
local settingsData = { default_source = "system", auto_transcribe_mic = false, transcribe_model = "small" }

local function has(argv, flag)
  for k, a in ipairs(argv) do if a == flag then return argv[k + 1] or true end end
  return nil
end

local function recorderReply(argv)
  local sub = argv[2]
  if sub == "list" then
    local rows = listOverride and listOverride(argv) or listData
    local q = has(argv, "--search")
    if q and not listOverride then
      local out = {}
      for _, r in ipairs(rows) do
        if r.id == 2 or r.id == 4 then
          local c = {} for k, v in pairs(r) do c[k] = v end
          c.snippet = r.id == 4 and "...so push it to **staging** this afternoon_ [ok]..." or ""
          out[#out + 1] = c
        end
      end
      rows = out
    end
    local lim = tonumber(has(argv, "--limit"))
    if lim and #rows > lim then
      local out = {} for k = 1, lim do out[k] = rows[k] end rows = out
    end
    return enc(rows)
  elseif sub == "stats" then
    -- What the CLI computes: totals over every row, days newest first.
    local out, byDay = { count = 0, size_bytes = 0, total_duration_s = 0, days = {} }, {}
    for _, r in ipairs(listData) do
      out.count = out.count + 1
      out.size_bytes = out.size_bytes + r.size_bytes
      out.total_duration_s = out.total_duration_s + r.duration_s
      local day = r.started_at:sub(1, 10)
      local d = byDay[day]
      if not d then d = { day = day, count = 0, duration_s = 0 } byDay[day] = d out.days[#out.days + 1] = d end
      d.count = d.count + 1
      d.duration_s = d.duration_s + r.duration_s
    end
    if #out.days == 0 then return '{"count":0,"size_bytes":0,"total_duration_s":0,"days":[]}' end
    return enc(out)
  elseif sub == "show" then
    local id = tonumber(argv[4])
    for _, r in ipairs(ALL) do
      if r.id == id then
        local d = {} for k, v in pairs(r) do d[k] = v end
        d.transcript = r.has_transcript and TRANSCRIPT or ""
        d.transcript_model = "small"
        return enc(d)
      end
    end
    return "{}"
  elseif sub == "settings" then return enc(settingsData)
  elseif sub == "set" then settingsData[argv[3]] = argv[4] == "true" and true or argv[4] == "false" and false or argv[4]
  elseif sub == "to-notes" then return enc({ ok = true, path = HOME .. "/Notes/Recordings/x.md" }) end
  return enc({ ok = true })
end

noctalia = {
  getenv = function(k) if k == "HOME" then return HOME end return nil end,
  nowMs = function() return clock end,
  json = { decode = json.decode },
  string = { trim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end },
  readFile = function(p) return files[p] and files[p].content or nil end,
  fileInfo = function(p) return files[p] and { size = #files[p].content, mtime = files[p].mtime, isDir = false } or nil end,
  fileExists = function(p) return files[p] ~= nil end,
  copyToClipboard = function(t) clipboard = t return true end,
  runAsync = function(argv, cb)
    calls[#calls + 1] = argv
    if cb then
      if argv[1] == "recorder" and failCli then
        cb({ exitCode = 127, stdout = "", stderr = "recorder: command not found" })
      elseif argv[1] == "recorder" then
        cb({ exitCode = 0, stdout = recorderReply(argv), stderr = "" })
      else
        cb({ exitCode = 0, stdout = "", stderr = "" })
      end
    end
    return true
  end,
  runStream = function(cmd, onLine) streams[#streams + 1] = { cmd = cmd, onLine = onLine } return true end,
}
panel = {
  render = function(t) lastTree = t end,
  close = function() end,
  setWantsSecondTicks = function(v) secondTicks = v end,
  setNeedsFrameTick = function(v) frameTick = v end,
}
ui = setmetatable({}, { __index = function(_, name)
  return function(props, children) return { type = name, props = props or {}, children = children or {} } end
end })

local STATE = HOME .. "/.local/state/recorder/state.json"
local WORKER = HOME .. "/.local/state/recorder/worker.json"
local DB = HOME .. "/.local/share/recorder/recordings.db"
files[STATE] = { content = '{"state":"idle","updated":1}', mtime = 1 }
files[DB] = { content = "x", mtime = 1 }
files[WORKER] = { content = '{"id":2,"progress":38,"eta_s":12,"updated":1}', mtime = 1 }

-- Load the panel with a require that resolves ./lib/library.luau to the converted file.
require = function(p)
  assert(p == "./lib/library.luau", "unexpected require " .. p)
  return dofile(dir .. "/lib/library.lua")
end
dofile(dir .. "/panel.lua")

-- ── tree helpers ────────────────────────────────────────────────────────────
local function walk(node, fn)
  if type(node) ~= "table" then return end
  fn(node)
  for _, c in ipairs(node.children or {}) do walk(c, fn) end
end

local function texts()
  local out = {}
  walk(lastTree, function(n)
    if n.type == "label" or n.type == "markdown" then out[#out + 1] = n.props.text
    elseif n.type == "button" and n.props.text then out[#out + 1] = n.props.text end
  end)
  return table.concat(out, "\n")
end

local function find(pred)
  local hit
  walk(lastTree, function(n) if not hit and pred(n) then hit = n end end)
  return hit
end

-- The clickable node that holds a label with this text (or a button with this text/tooltip).
local function clickable(text)
  local hit
  local function visit(n, owner)
    if hit then return end
    if (n.props.onClick or n.props.onSubmit) then owner = n end
    if (n.type == "label" and n.props.text == text) or n.props.tooltip == text or (n.type == "button" and n.props.text == text) then
      hit = owner
      return
    end
    for _, c in ipairs(n.children or {}) do visit(c, owner) end
  end
  visit(lastTree, nil)
  assert(hit, "no clickable for " .. text)
  return hit
end

local function click(text) clickable(text).props.onClick() end

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1 else failed = failed + 1 print("FAIL " .. name .. (detail and (": " .. detail) or "")) end
end
local function contains(s, sub) return s:find(sub, 1, true) ~= nil end
local function lastCall() return table.concat(calls[#calls], " ") end
local function anyCall(sub)
  for _, c in ipairs(calls) do if contains(table.concat(c, " "), sub) then return true end end
  return false
end

-- ── scenarios ───────────────────────────────────────────────────────────────
onOpen("")
local t = texts()
check("header count and size", contains(t, "7 recordings, 2.1 GB"), t:sub(1, 200))
check("today header", contains(t, "Today"))
check("yesterday header", contains(t, "Yesterday"))
check("today totals", contains(t, "3 recordings, 5 min"))
check("totals from stats", anyCall("recorder stats --json"))
local unlimited = false
for _, c in ipairs(calls) do
  if c[1] == "recorder" and c[2] == "list" and not has(c, "--limit") then unlimited = true end
end
check("no unlimited list", not unlimited)
check("chip none", contains(t, "Transcribe"))
check("chip queued", contains(t, "Queued"))
check("chip running percent from worker.json", contains(t, "38%"))
check("chip done", contains(t, "Transcript"))
check("chip no speech", contains(t, "No speech"))
check("chip failed", contains(t, "Failed"))
check("auto title shows the time only", contains(t, "Recording 08:00") and not contains(t, "Recording " .. older))
check("named title kept", contains(t, "Call with client"))
check("untitled shows date and time", t:find(", 09:41", 1, true) ~= nil)
check("opus marker", contains(t, "Opus"))
check("tag in meta", contains(t, "voice"))
check("second ticks on", secondTicks)
check("settings strip", contains(t, "Default source") and contains(t, "Auto-transcribe mic recordings"))
check("model select", find(function(n) return n.type == "select" and n.props.selectedIndex == 2 end) ~= nil)
local bars = 0
walk(lastTree, function(n) if n.type == "box" and n.props.width == 2 then bars = bars + 1 end end)
check("waveform 29 bars per row", bars == 29 * 7, tostring(bars))

-- Polling: no change, no reload. DB mtime change, reload.
local n0 = #calls
update()
check("idle tick does not reload", #calls == n0, tostring(#calls - n0))
files[DB].mtime = 2
update()
check("db change reloads", #calls > n0)

-- Failed chip retries, none chip transcribes.
click("Failed")
check("failed chip retries", anyCall("recorder transcribe 6"))
calls = {}
click("Queue a transcript")
check("none chip queues", anyCall("recorder transcribe 7"), lastCall())

-- Play in place.
clickable("Play").props.onClick()
check("player started", #streams == 1 and contains(streams[1].cmd, "recorder-player play '"), streams[1] and streams[1].cmd)
streams[1].onLine('{"pos": 24.0, "dur": 48.0, "paused": false}')
local green = 0
walk(lastTree, function(n) if n.type == "box" and n.props.width == 2 and n.props.fill == "#39ff14" then green = green + 1 end end)
check("played half is green", green >= 13 and green <= 16, tostring(green))
check("current time shown", contains(texts(), "0:24"))
clickable("Pause").props.onClick()
check("pause sent", lastCall() == "recorder-player pause")
-- seek by clicking a bar of the playing row
local seekBox = find(function(n) return n.type == "box" and n.props.width == 2 and n.props.onClick end)
seekBox.props.onClick()
check("seek sent", contains(lastCall(), "recorder-player seek"))
streams[1].onLine('{"end": true}')
check("end clears playback", find(function(n) return n.props.tooltip == "Resume" or n.props.tooltip == "Pause" end) == nil)

-- Two-track playback passes both files.
local both = find(function(n) return n.props.key == "row:3" end)
walk(both, function(n) if n.props.tooltip == "Play" then n.props.onClick() end end)
check("both tracks played mixed", contains(streams[#streams].cmd, "a-system.flac") and contains(streams[#streams].cmd, "a-mic.flac"))
onClose()
check("close stops player", anyCall("recorder-player stop"))
onOpen("")

-- Open a done row: transcript, tags, actions.
click("Persona clip")
t = texts()
check("transcript shown", contains(t, "push it to staging"))
check("stamp kept", contains(t, "`02:14`"))
check("send to notes offered", contains(t, "Send to Notes"))
check("transcribe again offered", contains(t, "Transcribe again"))
check("add tag offered", contains(t, "Add tag"))
click("Send to Notes")
check("to-notes called", anyCall("recorder to-notes 1"))
check("saved path flashed", contains(texts(), "Saved to ~/Notes/Recordings/x.md"))
click("Copy the file path")
check("path copied", clipboard and contains(clipboard, "Recordings/"))

-- Rename in place.
click("Rename")
local input = find(function(n) return n.type == "input" and n.props.key == "rename:1" end)
check("rename input focused", input and input.props.focus == true and input.props.value == "Persona clip")
input.props.onSubmit("Persona clip Faz")
check("rename called", anyCall("recorder rename 1 Persona clip Faz"))

-- Tags: add and remove.
click("Add tag")
input = find(function(n) return n.type == "input" and n.props.key == "tagin:1" end)
input.props.onSubmit("faz, demo")
check("tag called with words", anyCall("recorder tag 1 faz demo"))
click("Remove tag")
check("untag called", anyCall("recorder untag 1 voice"))

-- No speech row: no Send to Notes.
click("Persona clip") -- close
click("Intro, take 2")
t = texts()
check("no speech row explains", contains(t, "No speech found"))
check("no send to notes on empty transcript", not contains(t, "Send to Notes"))

-- Delete with inline confirm.
click("Delete")
t = texts()
check("confirm shown", contains(t, 'Delete "Intro, take 2"?') and contains(t, "~/Recordings/.trash"))
clickable("Cancel").props.onClick()
check("cancel restores row", not contains(texts(), 'Delete "Intro'))
click("Delete")
local deleteBtn = find(function(n) return n.type == "button" and n.props.text == "Delete" end)
deleteBtn.props.onClick()
check("delete called", anyCall("recorder delete 5"))

-- Search with debounce.
local sinput = find(function(n) return n.type == "input" and n.props.key and n.props.key:sub(1, 7) == "search:" end)
calls = {}
sinput.props.onChange("staging")
check("frame tick armed", frameTick)
onFrameTick("16")
check("debounced: no search yet", not anyCall("--search"))
clock = clock + 300
onFrameTick("16")
check("search runs after debounce", anyCall("recorder list --json --limit 40 --search staging"))
check("frame tick off", not frameTick)
t = texts()
check("match count line", contains(t, '2 recordings match "staging"'), t:sub(1, 300))
check("only matches listed", contains(t, "Standup notes") and not contains(t, "Mic check"))
check("snippet under the title", contains(t, "...so push it to **staging** this afternoon\\_ \\[ok\\]..."), t:sub(1, 400))
local snippets = 0
walk(lastTree, function(n) if n.type == "markdown" and contains(n.props.text, "afternoon") then snippets = snippets + 1 end end)
check("empty snippet not drawn", snippets == 1, tostring(snippets))
check("header totals unchanged by search", contains(t, "7 recordings, 2.1 GB"))
click("Call with client")
t = texts()
check("search word bold in transcript", contains(t, "**staging**"))
check("match count in transcript", contains(t, "2 matches"))
clickable("Clear the search").props.onClick()
check("clear resets", contains(texts(), "Mic check"))

-- Pagination: 100 rows, page of 40, scroll near the bottom loads 80.
local many = {}
for k = 1, 100 do many[k] = rec(100 + k, today, "08:00") end
listData = many
files[DB].mtime = 3
update()
check("first page", contains(texts(), "Loading older days"))
calls = {}
onListScroll("900", "1000")
check("scroll loads more", anyCall("--limit 80"))
onListScroll("10", "1000")

-- Open row without a transcript: the chip is the only Transcribe action.
listData = ALL
files[DB].mtime = 4
update()
local function rowTexts(id)
  local out = {}
  walk(find(function(n) return n.props.key == "row:" .. id end), function(n)
    if n.type == "label" then out[#out + 1] = n.props.text end
  end)
  return out
end
local function countText(list, s) local k = 0 for _, x in ipairs(list) do if x == s then k = k + 1 end end return k end
click("Recording 08:00")
local r7 = rowTexts(7)
check("single Transcribe action when no transcript", countText(r7, "Transcribe") == 1 and countText(r7, "Transcribe again") == 0,
  table.concat(r7, "|"))
check("no transcript yet shown", countText(r7, "No transcript yet.") == 1)
click("Mic check")
local r6 = rowTexts(6)
check("failed row: chip retries, no big button", countText(r6, "Transcribe again") == 0 and countText(r6, "Transcribe") == 0,
  table.concat(r6, "|"))
click("Call with client")
check("done row keeps Transcribe again", countText(rowTexts(4), "Transcribe again") == 1)
click("Call with client")

-- Chip width fits its longest label: glyph 13 + gap 5 + 10 chars of 12 px mono (7.2 px) + padding 14.
local chipNode = find(function(n) return n.type == "row" and n.props.height == 24 and n.props.radius == 12 and n.props.width end)
check("chip wide enough for Transcribe", chipNode and chipNode.props.width >= 13 + 5 + 72 + 14, chipNode and tostring(chipNode.props.width))

-- Settings.
listData = ALL
local function segments()
  local out = {}
  walk(lastTree, function(n)
    if n.props.key and n.props.key:sub(1, 4) == "src:" then
      out[n.props.key:sub(5)] = { fill = n.props.fill, color = n.children[1].props.color, weight = n.children[1].props.fontWeight }
    end
  end)
  return out
end
for _, pick in ipairs({ "System", "Mic", "Both", "Mic" }) do
  find(function(n) return n.props.key == "src:" .. string.lower(pick) end).props.onClick()
  local seg, greens = segments(), 0
  for s, v in pairs(seg) do
    if v.fill == "#39ff14" then greens = greens + 1 end
    -- Every off segment sets its fill and weight explicitly, so an in-place re-render clears the old green.
    if s ~= string.lower(pick) then
      check("segment " .. s .. " off after " .. pick, v.fill == "#00000000" and v.weight == "regular" and v.color ~= "#06090a",
        tostring(v.fill) .. " " .. tostring(v.weight))
    end
  end
  check("only " .. pick .. " green", greens == 1 and seg[string.lower(pick)].fill == "#39ff14", tostring(greens))
end
check("default source set", anyCall("recorder set default_source mic"))
find(function(n) return n.type == "toggle" end).props.onChange("true")
check("auto transcribe set", anyCall("recorder set auto_transcribe_mic true"))
find(function(n) return n.type == "select" end).props.onChange("4")
check("model set", anyCall("recorder set transcribe_model large-v3"))

-- Record button and recording state.
files[STATE] = { content = '{"state":"recording","id":9,"elapsed_s":252.4,"updated":5}', mtime = 5 }
update()
check("record button shows elapsed", contains(texts(), "Stop 4:12"))
click("Stop 4:12")
check("toggle called", anyCall("recorder toggle"))

-- Open from the saved card: context is the recording id.
onClose()
onOpen("4")
check("context opens that row", contains(texts(), "Transcribe again"))

-- Empty state.
onClose()
listData = {}
files[DB].mtime = 9
onOpen("")
t = texts()
check("empty state", contains(t, "No recordings yet") and contains(t, "Start recording") and contains(t, "Super+Alt+R"))

-- CLI missing.
onClose()
failCli = true
files[DB].mtime = 10
dofile(dir .. "/panel.lua")
onOpen("")
check("cli error shown", contains(texts(), "recorder: command not found"))

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
