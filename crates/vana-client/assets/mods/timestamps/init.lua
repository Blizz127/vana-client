-- The game's chat timestamps on every log line, through the client's stamp_all_lines switch (back off when unloaded).
local function update()
  client.set_option("stamp_all_lines", settings.get("on") == true)
end

update()
events.on("settings_changed", update)
