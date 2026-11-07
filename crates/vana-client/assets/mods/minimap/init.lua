-- The client's minimap (its map, the radar's dots, the wheel's zoom; Wide Scan under it in the modern UI) in the
-- minimap's edge window: panel "minimap" draws it, in its corner in the classic UI.
local function show()
  if settings.get("on") then
    ui.window("minimap", { edge = true, panel = "minimap", title = "Map" })
    ui.open("minimap")
  else
    ui.close("minimap")
  end
end

show()
events.on("settings_changed", show)
