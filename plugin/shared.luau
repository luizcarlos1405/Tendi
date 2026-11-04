--!nonstrict
-- Paths and settings shared by the entries, which each load their own copy
-- (entries share no Lua memory). The paths must match ~/.local/bin/dictate.

local M = {}

local function envOr(name, fallback)
  local value = noctalia.getenv(name)
  if value == nil or value == "" then
    return fallback
  end
  return value
end

-- The running dictation's state files; the script removes the dir when done
function M.runtimeDir()
  return envOr("XDG_RUNTIME_DIR", "/tmp") .. "/dictate"
end

-- What outlives a dictation: history.jsonl and the settings file
function M.dataDir()
  return envOr("XDG_STATE_HOME", noctalia.expandPath("~/.local/state")) .. "/dictate"
end

function M.historyFile()
  return M.dataDir() .. "/history.jsonl"
end

-- Same bounds as the manifest, in case the config holds something odd
function M.historySize()
  local size = tonumber(noctalia.getConfig("history_size")) or 100
  return math.clamp(math.floor(size), 1, 1000)
end

return M
