-- The client's timers in three edge windows, one per section, so /uimodes shows and hides each: our recasts, the
-- effects on us and our party (buffs), and the ones we put on monsters (debuffs). The classic UI draws them as the one
-- Timers window with three sections. Other mods' timers.add rows show in them whether the setting is on or not; the
-- client's own rows only while it is on.
local WINDOWS = {
  { id = "recasts", title = "Recasts" },
  { id = "buffs", title = "Buffs" },
  { id = "debuffs", title = "Debuffs" },
}

local function show()
  local builtin = settings.get("on") == true
  for _, w in ipairs(WINDOWS) do
    ui.window(w.id, {
      edge = true, panel = "timers_" .. w.id, resize = true, title = w.title,
      elements = { { type = "timers", section = w.id, builtin = builtin } },
    })
    ui.open(w.id)
  end
end

show()
events.on("settings_changed", show)
