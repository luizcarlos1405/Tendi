--!nonstrict
-- Headless service: mirrors the plugin settings into
-- $XDG_STATE_HOME/dictate/settings as key=value lines, since the dictate
-- script cannot read Noctalia's config. Rewritten when Noctalia starts and
-- whenever the settings change; the script reads it when a dictation starts.
--
-- History trimming stays with the script (it trims on every save), so lowering
-- the size and raising it back before the next dictation loses nothing.

local shared = require("./shared.luau")

local function writeSettings()
  local dir = shared.dataDir()
  local ok, err = noctalia.mkdirAll(dir)
  if ok then
    local contents = table.concat({
      "# Written by the luiz/dictation Noctalia plugin from its settings; read by dictate.",
      `history_size={shared.historySize()}`,
      `type_by_default={noctalia.getConfig("type_by_default") ~= false}`,
      `lock_by_default={noctalia.getConfig("lock_by_default") == true}`,
    }, "\n") .. "\n"
    -- Write then rename, so the script never reads half a file
    ok, err = noctalia.writeFile(dir .. "/settings.tmp", contents)
    if ok then
      ok, err = noctalia.renameFile(dir .. "/settings.tmp", dir .. "/settings")
    end
  end
  if not ok then
    noctalia.log(`dictation: could not write {dir}/settings: {err}`)
  end
end

function onConfigChanged()
  writeSettings()
end

writeSettings()
