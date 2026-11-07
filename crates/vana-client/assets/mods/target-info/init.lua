-- The target window's distance and HP percent slots, every frame (the window draws them on its gauge row).
events.on("frame", function()
  local t = game.target()
  ui.native.slot("target_distance", t and settings.get("distance") and t.distance or nil)
  ui.native.slot("target_hpp", t and settings.get("hpp") and t.hpp or nil)
end)
