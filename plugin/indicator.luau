--!nonstrict
-- Mic pill shown while ~/.local/bin/dictate runs. The script writes
--   $XDG_RUNTIME_DIR/dictate/state   "listening" or "transcribing"
--   $XDG_RUNTIME_DIR/dictate/level   mic level 0..100, every 100 ms
--   $XDG_RUNTIME_DIR/dictate/live    the text so far, rewritten as the live
--                                    transcription corrects itself
-- and opens/closes this panel; here we poll those files and draw: the text
-- on top, the mic, meter and buttons under it.
-- Buttons talk back through files the script polls, like the CLI does:
--   mic       -> stop    (finish and paste now)
--   keyboard  -> type    (exists = paste the text; else only save it to history)
--   lock      -> lock    (exists = keep listening through pauses)
--   X         -> cancel  (throw the recording away)
-- The script creates type/lock at the start from the plugin settings.

local shared = require("./shared.luau")

local BARS = 32
local POLL_MS = 50

local dir = shared.runtimeDir()

local state = "listening"
local transcript = ""
local locked = false
local typing = true
local hovered = { mic = false, type = false, lock = false, cancel = false }
local history = {} -- recent levels (0..1), newest last
local clock = 0 -- ms since open, drives the pulse animation
local sincePoll = 0

local function resetHistory()
  history = {}
  for i = 1, BARS do
    history[i] = 0
  end
end

local function push(level)
  table.remove(history, 1)
  table.insert(history, level)
end

local function readToggles()
  locked = noctalia.fileExists(dir .. "/lock")
  typing = noctalia.fileExists(dir .. "/type")
end

local function poll()
  readToggles()
  noctalia.readFileAsync(dir .. "/state", function(contents)
    if contents ~= nil then
      state = string.gsub(contents, "%s+", "")
    end
  end)
  noctalia.readFileAsync(dir .. "/level", function(contents)
    local level = contents and tonumber((string.gsub(contents, "%s+", "")))
    if level ~= nil and state == "listening" then
      push(math.clamp(level / 100, 0, 1))
    end
  end)
  -- Missing until the first live pass (and with no whisper server at all)
  noctalia.readFileAsync(dir .. "/live", function(contents)
    transcript = if contents then noctalia.string.trim(contents) else ""
  end)
end

-- The live text, pinned to its newest line; a muted hint until it starts
local function transcriptView()
  local empty = transcript == ""
  return ui.scroll({ flexGrow = 1, stickToBottom = true }, {
    ui.label({
      text = if not empty then transcript elseif state == "listening" then "Listening…" else "",
      fontSize = 14,
      color = if empty then "on_surface_variant" else "on_surface",
    }),
  })
end

local function meter()
  -- Thin dense bars read as a waveform; locked switches them to the lock's
  -- tertiary accent. The row takes the leftover width, the bars stay centered.
  local color = if locked then "tertiary" else "primary"
  local bars = {}
  for i, level in ipairs(history) do
    -- Older bars fade out a little so the meter reads left -> right
    local alpha = 0.35 + 0.65 * (i / BARS)
    bars[i] = ui.box({
      width = 3,
      height = math.max(4, math.floor(4 + level * 20)),
      radius = 2,
      fill = `{color}/{string.format("%.2f", alpha)}`,
    })
  end
  return ui.row({ gap = 2, align = "center", justify = "center", flexGrow = 1 }, bars)
end

local function transcribing()
  -- Three dots that light up in turn
  local dots = {}
  local active = math.floor(clock / 250) % 3
  for i = 0, 2 do
    dots[i + 1] = ui.box({
      width = 6,
      height = 6,
      radius = 3,
      fill = if i == active then "primary" else "primary/0.3",
    })
  end
  return ui.row({ gap = 8, align = "center", justify = "center", flexGrow = 1 }, {
    ui.label({ text = "Transcribing", fontSize = 13, color = "on_surface" }),
    ui.row({ gap = 4, align = "center" }, dots),
  })
end

-- Same files `dictate stop` / `dictate cancel` create; the script polls them
local function stopDictation()
  if state ~= "transcribing" then
    noctalia.writeFile(dir .. "/stop", "")
  end
end

-- lock and type are on while their file exists, as with `dictate lock|type`
local function setFlag(name, on)
  if on then
    noctalia.writeFile(dir .. "/" .. name, "")
  else
    noctalia.removeFile(dir .. "/" .. name)
  end
end

local function toggleLock()
  locked = not locked
  setFlag("lock", locked)
end

-- Checked by the script right before typing, so it works while transcribing too
local function toggleTyping()
  typing = not typing
  setFlag("type", typing)
end

local function cancelDictation()
  noctalia.writeFile(dir .. "/cancel", "")
  -- Close now: while whisper runs, the script only sees the file afterwards
  panel.close()
end

local function hoverHandler(key)
  return function(value)
    hovered[key] = value == "true"
  end
end

local function micBadge(listening, pulse)
  local hot = listening and hovered.mic
  return ui.row({
    width = 32,
    height = 32,
    radius = 16,
    fill = if listening then "error" else "primary",
    -- Hover: a soft ring and no pulse, so it reads as a button
    border = if hot then "error/0.35" else nil,
    borderWidth = if hot then 3 else 0,
    align = "center",
    justify = "center",
    opacity = if hot then 1 else pulse,
    onClick = stopDictation, -- click the mic to stop and type
    onHover = hoverHandler("mic"),
  }, {
    ui.glyph({
      -- Hover turns the mic into a check: clicking accepts the dictation
      name = if not listening then "wand" elseif hot then "check" else "microphone",
      size = 18,
      color = if listening then "on_error" else "on_primary",
    }),
  })
end

-- 28 px square icon tile: muted grey until hovered; an `accent` color role
-- tints it while its toggle is on (primary for typing, tertiary for the lock)
local function iconButton(key, glyph, accent, onClick)
  local hot = hovered[key]
  return ui.row({
    width = 28,
    height = 28,
    radius = 8,
    fill = if accent then `{accent}/0.22` elseif hot then "surface_variant" else "#00000000",
    align = "center",
    justify = "center",
    onClick = onClick,
    onHover = hoverHandler(key),
  }, {
    ui.glyph({
      name = glyph,
      size = 16,
      color = if accent then accent elseif hot then "on_surface" else "on_surface_variant",
    }),
  })
end

local function divider()
  return ui.box({ width = 1, height = 22, fill = "outline/0.55" })
end

local function render()
  local listening = state ~= "transcribing"
  -- Slow breathing pulse on the mic badge while listening
  local pulse = if listening then 0.6 + 0.4 * (0.5 + 0.5 * math.sin(clock / 1000 * math.pi * 1.5)) else 1

  -- Three zones: mic | meter or "Transcribing" (flexible) | divider + buttons
  local buttons = {
    iconButton("type", if typing then "keyboard" else "keyboard-off", if typing then "primary" else nil, toggleTyping),
  }
  if listening then
    table.insert(buttons, iconButton("lock", if locked then "lock" else "lock-open", if locked then "tertiary" else nil, toggleLock))
  end
  table.insert(buttons, iconButton("cancel", "close", nil, cancelDictation))

  -- The live text takes the height the row leaves (plugin.toml sizes the
  -- panel for about three lines over the 32 px badge)
  panel.render(ui.column({ flexGrow = 1, gap = 8 }, {
    transcriptView(),
    ui.row({ gap = 10, align = "center" }, {
      micBadge(listening, pulse),
      if listening then meter() else transcribing(),
      divider(),
      ui.row({ gap = 4, align = "center" }, buttons),
    }),
  }))
end

function onOpen()
  state = "listening"
  transcript = ""
  -- The script set these up before opening us: show them from the first frame
  readToggles()
  hovered = { mic = false, type = false, lock = false, cancel = false }
  clock = 0
  sincePoll = POLL_MS
  resetHistory()
  panel.setNeedsFrameTick(true)
  render()
end

function onClose()
  panel.setNeedsFrameTick(false)
end

function onFrameTick(deltaMs)
  local dt = tonumber(deltaMs) or 16
  clock += dt
  sincePoll += dt
  if sincePoll >= POLL_MS then
    sincePoll = 0
    poll()
  end
  render()
end

resetHistory()
