-- The camera's distance (in and out of battle) and pan speed (the camera add-ons); the game's back when off.
local function apply()
  if settings.get("on") then
    local d = settings.get("distance")
    local b = settings.get("battle")
    render.set_camera({ max_distance = math.max(3, d, b), distance = d, speed = settings.get("speed"),
      battle_distance = b > 0 and b or false })
  else
    render.set_camera({ distance = 1, speed = 1, battle_distance = false })
  end
end

apply()
events.on("settings_changed", apply)
events.on("unload", function() render.set_camera({ distance = 1, speed = 1, battle_distance = false }) end)
