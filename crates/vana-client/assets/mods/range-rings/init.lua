-- Ground rings at chosen distances around us, and optionally the target (the range display add-ons).

local shown = false

local function radii()
  local out = {}
  for d in (settings.get("distances") or ""):gmatch("[^,]+") do
    local n = tonumber(d:match("^%s*(.-)%s*$"))
    if n and n > 0 and n <= 50 then out[#out + 1] = n end
  end
  return out
end

local function at(pos)
  -- y points down: a little off the floor, or the ground hides it.
  return { x = pos.x, y = pos.y - 0.1, z = pos.z }
end

events.on("frame", function()
  local me = game.player()
  if not settings.get("on") or not me or not me.pos then
    if shown then draw.clear() end
    shown = false
    return
  end
  local c = settings.get("colour")
  local colour = { c[1], c[2], c[3], c[4] or 220 }
  local list = radii()
  -- Lines are a pixel wide: three rings close together make a band that reads.
  local function band(key, pos, r)
    for k, d in ipairs({ 0, 0.04, 0.08 }) do
      draw.ring(key .. "_" .. k, { at = at(pos), radius = r + d, colour = colour, segments = 96 })
    end
  end
  local function unband(key)
    for k = 1, 3 do draw.remove(key .. "_" .. k) end
  end
  for i, r in ipairs(list) do band("me" .. i, me.pos, r) end
  for i = #list + 1, 8 do unband("me" .. i) end
  local t = settings.get("target") and game.target()
  if t and t.pos and list[1] then band("target", t.pos, list[1]) else unband("target") end
  shown = true
end)
