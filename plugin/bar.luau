--!nonstrict
-- Bar icon for the dictation history: click to open the list of
-- transcriptions, right-click for the plugin settings.

local function render()
  barWidget.setGlyph("bubble-text")
  barWidget.setTooltip(noctalia.tr("bar.tooltip"))
end

function update()
  -- Static icon: no need to tick often
  noctalia.setUpdateInterval(60000)
  render()
end

function onClick()
  noctalia.togglePanel("luiz/dictation:history")
end

function onRightClick()
  noctalia.openSettings()
end
