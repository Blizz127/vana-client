-- The client's behaviour switches as settings (the game's behaviour back when one is off or the mod unloads).
local SWITCHES = {
  { "instant_palette", "macro_palette_delay", true },
  { "instant_auction", "ah_result_delay", true },
  { "instant_equipsets", "equipset_delay", true },
  { "instant_log", "log_slide", true },
  { "dead_commands", "dead_commands", false },
  { "ttf_text", "ttf_text", false },
}

local function update()
  for _, s in ipairs(SWITCHES) do
    local on = settings.get(s[1]) == true
    -- An inverted switch is the game's wait: on means the wait is gone.
    if s[3] then client.set_option(s[2], not on) else client.set_option(s[2], on) end
  end
  client.set_option("animation_rate", settings.get("animation"))
end

update()
events.on("settings_changed", update)
