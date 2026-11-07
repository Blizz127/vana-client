-- A ground ring under the target (the target marker add-ons), redrawn each frame as the target moves.
-- Lines are a pixel wide: a few rings close together make a band that reads.
local BAND = { 0, 0.03, 0.06, 0.09 }
local shown = false

events.on("frame", function()
  local t = settings.get("on") and game.target()
  if not t or not t.pos then
    if shown then draw.clear() end
    shown = false
    return
  end
  local c = settings.get("colour")
  local colour = { c[1], c[2], c[3], c[4] or 200 }
  -- y points down: lifted a little off the floor, or the ground hides it.
  local feet = { x = t.pos.x, y = t.pos.y - 0.1, z = t.pos.z }
  for i, d in ipairs(BAND) do
    draw.ring("ring" .. i, { at = feet, radius = settings.get("size") + d, colour = colour, segments = 64 })
  end
  shown = true
end)
