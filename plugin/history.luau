--!nonstrict
-- Dictation history, opened from the bar icon (bar.luau). Lists what the
-- dictate script saved to $XDG_STATE_HOME/dictate/history.jsonl (one
-- {"time","text"} object per line, newest last), newest first. Click an entry
-- to copy it to the clipboard; the trash button clears the history after a
-- confirming second click.

local shared = require("./shared.luau")

local entries = {} -- { id, time, text }, newest first
local loadedSignature = nil -- mtime:size of the file we last read
local hoveredKey = nil
local confirmClear = false

local render

local function tr(key, subst)
  return noctalia.tr(key, subst)
end

-- Cheap change check for the second ticks: the script replaces the file on
-- every save, so mtime or size moves
local function signature()
  local info = noctalia.fileInfo(shared.historyFile())
  return if info then `{info.mtime}:{info.size}` else "none"
end

local function load()
  loadedSignature = signature()
  local list = {}
  local contents = noctalia.readFile(shared.historyFile())
  local id = 0
  for line in string.gmatch(contents or "", "[^\n]+") do
    id += 1
    local entry = noctalia.json.decode(line)
    -- Skip lines that are not ours (a hand edit, a cut-off write)
    if type(entry) == "table" and type(entry.text) == "string" and entry.text ~= "" then
      table.insert(list, { id = id, time = tonumber(entry.time) or 0, text = entry.text })
    end
  end
  -- Newest first, capped at the setting: the script only trims the file when
  -- it saves the next dictation
  entries = {}
  for i = #list, math.max(1, #list - shared.historySize() + 1), -1 do
    table.insert(entries, list[i])
  end
end

local function timeLabel(time)
  local now = os.time()
  local day = noctalia.formatTime("%Y-%m-%d", time)
  local clock = noctalia.formatTime("%H:%M", time)
  if day == noctalia.formatTime("%Y-%m-%d", now) then
    return clock
  elseif day == noctalia.formatTime("%Y-%m-%d", now - 86400) then
    return tr("history.yesterday", { time = clock })
  elseif noctalia.formatTime("%Y", time) == noctalia.formatTime("%Y", now) then
    return noctalia.formatTime("%b %d, %H:%M", time)
  end
  return noctalia.formatTime("%b %d %Y, %H:%M", time)
end

local function copy(entry)
  if noctalia.copyToClipboard(entry.text, "text/plain;charset=utf-8") then
    panel.close()
  else
    noctalia.notifyError(tr("title"), tr("history.copy_failed"))
  end
end

local function askClear()
  confirmClear = true
  render()
end

local function cancelClear()
  confirmClear = false
  render()
end

local function clearHistory()
  confirmClear = false
  if noctalia.fileExists(shared.historyFile()) then
    local ok, err = noctalia.removeFile(shared.historyFile())
    if not ok then
      noctalia.notifyError(tr("title"), tostring(err))
    end
  end
  load()
  render()
end

function onRowHover(state, key)
  hoveredKey = if state == "true" then key else nil
  render()
end

local function header()
  local children = {
    ui.glyph({ name = "microphone", size = 18, color = "primary" }),
    ui.label({
      text = tr("history.title"),
      fontSize = 15,
      fontWeight = "semibold",
      color = "on_surface",
      flexGrow = 1,
    }),
  }
  -- Distinct keys per button: a retained button can keep its old glyph
  if confirmClear then
    table.insert(children, ui.label({ text = tr("history.clear_confirm"), fontSize = 13, color = "error" }))
    table.insert(children, ui.button({
      key = "clear-yes",
      glyph = "check",
      variant = "destructive",
      controlSize = "sm",
      onClick = clearHistory,
    }))
    table.insert(children, ui.button({
      key = "clear-no",
      glyph = "close",
      variant = "ghost",
      controlSize = "sm",
      onClick = cancelClear,
    }))
  else
    if #entries > 0 then
      table.insert(children, ui.button({
        key = "clear",
        glyph = "trash",
        variant = "ghost",
        controlSize = "sm",
        tooltip = tr("history.clear"),
        onClick = askClear,
      }))
    end
    table.insert(children, ui.button({
      key = "settings",
      glyph = "settings",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("history.settings"),
      onClick = function()
        noctalia.openSettings()
      end,
    }))
  end
  return ui.row({ gap = 6, align = "center" }, children)
end

local function row(entry)
  local key = `entry-{entry.id}`
  local hot = hoveredKey == key
  return ui.column({
    key = key,
    gap = 4,
    paddingV = 8,
    paddingH = 12,
    radius = 8,
    fill = if hot then "surface_variant" else "surface_variant/0.35",
    onHover = "onRowHover",
    onClick = function()
      copy(entry)
    end,
  }, {
    ui.label({ text = entry.text, fontSize = 13, color = "on_surface", maxLines = 4 }),
    ui.row({ gap = 6, align = "center" }, {
      ui.label({
        text = timeLabel(entry.time),
        fontSize = 11,
        color = "on_surface_variant",
        flexGrow = 1,
      }),
      -- Shown on hover (opacity keeps the row height steady): click copies
      ui.glyph({ name = "copy", size = 13, color = "primary", opacity = if hot then 1 else 0 }),
    }),
  })
end

local function emptyState()
  return ui.column({ flexGrow = 1, gap = 6, align = "center", justify = "center" }, {
    ui.glyph({ name = "microphone", size = 32, color = "on_surface_variant" }),
    ui.label({ text = tr("history.empty"), fontSize = 14, color = "on_surface" }),
    ui.label({ text = tr("history.empty_hint"), fontSize = 12, color = "on_surface_variant" }),
  })
end

render = function()
  local body
  if #entries == 0 then
    body = emptyState()
  else
    local rows = {}
    for i, entry in ipairs(entries) do
      rows[i] = row(entry)
    end
    body = ui.scroll({ flexGrow = 1, gap = 6 }, rows)
  end
  panel.render(ui.column({ flexGrow = 1, gap = 10 }, { header(), body }))
end

function onOpen()
  hoveredKey = nil
  confirmClear = false
  load()
  panel.setWantsSecondTicks(true)
  render()
end

function onClose()
  panel.setWantsSecondTicks(false)
end

-- Second ticks while open: show a dictation saved meanwhile
function update()
  if signature() ~= loadedSignature then
    load()
    render()
  end
end
