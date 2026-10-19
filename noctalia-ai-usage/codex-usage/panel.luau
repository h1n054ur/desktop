--!nonstrict
local shared = require("./shared.luau")

local limits = noctalia.state.get("limits") or {}
local sessions = noctalia.state.get("sessions") or {}

-- Same groups and colours as the Claude panel, with Working in the accent.
local GROUPS = {
  { status = "waiting", title = "Needs you", glyph = "bell-ringing", color = "error" },
  { status = "busy", title = "Working", glyph = "loader-2", color = shared.accent() },
  { status = "idle", title = "Idle", glyph = "circle-check", color = "on_surface_variant" },
}
local LOOK = {}
for _, g in ipairs(GROUPS) do LOOK[g.status] = g end

-- OpenCode tool names (sessions.sh gives "name: detail").
local TOOL_GLYPH = {
  shell = "terminal-2", bash = "terminal-2", edit = "pencil", patch = "pencil", write = "file-plus", read = "file-text",
  grep = "search", glob = "folder-search", list = "folder", task = "robot", webfetch = "world", websearch = "world-search",
  todowrite = "list-check", skill = "sparkles", question = "help-circle",
}

local function iconLine(glyph, text, color, size)
  return ui.row({ gap = 6, align = "center" }, {
    ui.glyph({ name = glyph, size = (size or 11) + 1, color = color or "on_surface_variant" }),
    ui.label({ text = text, fontSize = size or 11, color = color or "on_surface_variant", maxLines = 2, flexGrow = 1 }),
  })
end

local function action(glyph, tooltip, fn, variant)
  return ui.button({ glyph = glyph, tooltip = tooltip, variant = variant or "ghost", controlSize = "sm", onClick = fn })
end

local function chip(glyph, text)
  return ui.row({ gap = 4, align = "center", paddingH = 6, paddingV = 2, radius = 6, fill = "on_surface/0.06" }, {
    ui.glyph({ name = glyph, size = 11, color = "on_surface_variant" }),
    ui.label({ text = text, fontSize = 10, color = "on_surface_variant" }),
  })
end

local function badge(glyph, color)
  return ui.column({ width = 34, height = 34, radius = 9, fill = shared.tint(color, 0.15), align = "center", justify = "center" }, {
    ui.glyph({ name = glyph, size = 18, color = color }),
  })
end

local function sectionHeader(text, count, color)
  return ui.row({ gap = 6, align = "center", paddingH = 2 }, {
    ui.label({ text = string.upper(text), fontSize = 10, fontWeight = "bold", color = color }),
    ui.label({ text = tostring(count), fontSize = 10, color = "on_surface_variant" }),
    ui.separator({ orientation = "horizontal", color = "outline", opacity = 0.2, flexGrow = 1 }),
  })
end

-- One OpenCode session, laid out like the Claude panel's live card. Click jumps to its TUI's terminal
-- when sessions.sh found one (pid); the copy button gives the command that reopens it.
local function sessionCard(s)
  local look = LOOK[s.status] or LOOK.idle
  local tool = s.tool ~= "" and string.match(s.tool, "^([^:]+)") or nil
  local toolArg = s.tool ~= "" and string.match(s.tool, "^[^:]+: (.*)$") or nil
  local body = {
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = s.title, fontSize = 13, fontWeight = "bold", color = "on_surface", maxLines = 1, flexGrow = 1 }),
      ui.label({ text = (s.since or 0) > 0 and shared.ago(s.since) or "", fontSize = 11, color = look.color }),
    }),
    ui.row({ gap = 5, align = "center" }, {
      ui.glyph({ name = "folder", size = 12, color = "on_surface_variant" }),
      ui.label({ text = shared.projectPath(s.cwd or ""), fontSize = 11, color = "on_surface_variant", maxLines = 1, flexGrow = 1 }),
      ui.button({ glyph = "copy", tooltip = "Copy resume command", variant = "ghost", controlSize = "sm", height = 24, width = 26,
        glyphSize = 13, onClick = function()
          noctalia.copyToClipboard(shared.resumeCommand(s.cwd, s.id), "text/plain")
          noctalia.notify("Copied", shared.resumeCommand(s.cwd, s.id))
        end }),
    }),
  }
  if s.status == "waiting" then
    body[#body + 1] = iconLine("alert-circle", s.waitingFor ~= "" and s.waitingFor or "Needs your input", "error", 12)
  elseif s.status == "busy" and tool then
    body[#body + 1] = iconLine(TOOL_GLYPH[string.lower(tool)] or "tool", tool .. (toolArg and ("  " .. toolArg) or ""), shared.accent(), 12)
  end
  body[#body + 1] = ui.row({ gap = 4, align = "center" }, {
    chip("terminal", s.terminal or "no terminal open"),
  })
  return ui.column({
    key = "session:" .. s.id, gap = 4, padding = 10, radius = 10,
    opacity = s.status == "idle" and 0.7 or 1,
    fill = "on_surface/0.04",
    border = s.status == "waiting" and "error/0.5" or nil,
    borderWidth = s.status == "waiting" and 1 or nil,
    onClick = s.pid and function() shared.focus(s.pid); panel.close() end or nil,
  }, {
    ui.row({ gap = 12, align = "start" }, { badge(look.glyph, look.color), ui.column({ gap = 5, flexGrow = 1 }, body) }),
  })
end

local function sessionList(content)
  for _, g in ipairs(GROUPS) do
    local list = {}
    for _, s in ipairs(sessions) do if (LOOK[s.status] and s.status or "idle") == g.status then list[#list + 1] = s end end
    if #list > 0 then
      content[#content + 1] = sectionHeader(g.title, #list, g.color)
      for _, s in ipairs(list) do content[#content + 1] = sessionCard(s) end
    end
  end
end

-- Plan usage windows (5h / 7d), one meter each, laid out like the Claude panel's limits strip.
local function limitsStrip()
  local windows = limits.windows or {}
  if #windows == 0 then return nil end
  local meters = {}
  for _, w in ipairs(windows) do
    local p = math.max(0, math.min(100, w.percent)) / 100
    local color = shared.severity(w.percent)
    local left = shared.resetsIn(w.resetsAt)
    meters[#meters + 1] = ui.column({ gap = 3, flexGrow = 1 }, {
      ui.row({ gap = 4, align = "center" }, {
        ui.label({ text = w.label, fontSize = 11, fontWeight = "bold", color = "on_surface" }),
        ui.spacer({ flexGrow = 1 }),
        ui.label({ text = `{math.floor(w.percent + 0.5)}%`, fontSize = 11, fontWeight = "bold", color = color }),
      }),
      ui.progress({ progress = p, height = 5, fill = color }),
      ui.label({ text = left and `resets in {left}` or "", fontSize = 10, color = "on_surface_variant" }),
    })
  end
  return ui.column({ gap = 6, padding = 10, radius = 10, fill = "on_surface/0.04" }, {
    ui.row({ gap = 14, align = "start" }, meters),
  })
end

function render()
  local header = {
    ui.row({ width = 28, height = 28, radius = 8, fill = shared.accent(0.15), align = "center", justify = "center" }, {
      ui.glyph({ name = shared.ICON, size = 16, color = shared.accent() }),
    }),
    ui.column({ gap = 0 }, {
      ui.label({ text = "Codex Usage", fontSize = 15, fontWeight = "bold", color = "on_surface" }),
      ui.label({ text = limits.plan and `ChatGPT {limits.plan}` or "", fontSize = 10, color = "on_surface_variant",
        visible = limits.plan ~= nil }),
    }),
    ui.spacer({ flexGrow = 1 }),
    action(limits.pending and "loader-2" or "refresh", "Refresh now", function()
      noctalia.state.set("command", { action = "force", at = noctalia.nowMs() })
    end),
    action("x", "Close", function() panel.close() end),
  }

  local content = {}
  local strip = limitsStrip()
  if strip then
    content[#content + 1] = strip
  elseif not limits.error then
    content[#content + 1] = ui.column({ gap = 8, align = "center", justify = "center", paddingV = 30 }, {
      ui.glyph({ name = "loader-2", size = 30, color = "on_surface_variant" }),
      ui.label({ text = "Loading Codex limits", color = "on_surface_variant" }),
    })
  end
  if limits.error then
    content[#content + 1] = ui.column({ gap = 4, padding = 10, radius = 10, fill = "error/0.08", border = "error/0.4", borderWidth = 1 }, {
      iconLine("alert-circle", shared.errorText(limits.error), "error", 12),
      iconLine("clock", strip and "Showing the last numbers we got" or `tried {shared.ago(limits.error.at)} ago`),
    })
  end

  if #sessions > 0 then
    sessionList(content)
  else
    content[#content + 1] = iconLine("moon", "No OpenCode sessions open")
  end

  local updated = limits.updated and `Last updated {shared.ago(limits.updated)} ago` or "Not updated yet"
  panel.render(ui.column({ gap = 10, flexGrow = 1 }, {
    ui.row({ gap = 8, align = "center" }, header),
    ui.scroll({ flexGrow = 1, gap = 8 }, content),
    ui.row({ gap = 12, align = "center" }, {
      iconLine("clock", updated),
      iconLine("pointer", "Click a session to jump to it"),
      iconLine("refresh", "Right-click the bar to refresh"),
    }),
  }))
end

noctalia.state.watch("limits", function(v) limits = v or {}; render() end)
noctalia.state.watch("sessions", function(v) sessions = v or {}; render() end)
function onOpen(_ctx)
  limits = noctalia.state.get("limits") or {}
  sessions = noctalia.state.get("sessions") or {}
  noctalia.state.set("command", { action = "refresh", at = noctalia.nowMs() })
  panel.setWantsSecondTicks(true)
  render()
end
function onClose() panel.setWantsSecondTicks(false) end
function update() render() end
render()
