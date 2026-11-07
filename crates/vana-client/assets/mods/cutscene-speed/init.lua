-- Events play faster, through the client's cutscene_speed switch (back to the game's speed when off or unloaded).
local function update()
  client.set_option("cutscene_speed", settings.get("on") and settings.get("speed") or 1.0)
end

update()
events.on("settings_changed", update)
