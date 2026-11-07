-- The battle menu's suggestions (modern UI): the client's rules pick what is worth using now (the suggestions event,
-- which runs them only while a mod listens); this mod puts the picks at the top of the battle menu.

local listening

local function show(rows)
  ui.native.slot("battle_rows", #rows > 0 and rows or nil)
end

local function apply()
  if settings.get("on") and not listening then
    listening = events.on("suggestions", show)
  elseif not settings.get("on") and listening then
    events.off(listening)
    listening = nil
    ui.native.slot("battle_rows", nil)
  end
end

apply()
events.on("settings_changed", apply)
