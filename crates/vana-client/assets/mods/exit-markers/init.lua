-- Zone lines outlined on the ground (ZoneLines): each box that zones us when touched, its footprint at our feet' height
-- (its floor when we stand above or below it) and a short post at each corner, for the ones within range.

local POST = 2.0
local drawn = {}

local function colour()
  local c = settings.get("colour") or {}
  return { c.r or c[1] or 110, c.g or c[2] or 220, c.b or c[3] or 255, c.a or c[4] or 220 }
end

local function refresh()
  local now = {}
  local p = game.player()
  if settings.get("on") and p and p.pos then
    local range, col = settings.get("range"), colour()
    for i, z in ipairs(game.zone_lines()) do
      local dx, dz = z.centre.x - p.pos.x, z.centre.z - p.pos.z
      if dx * dx + dz * dz <= range * range then
        -- The box reaches below the ground: the outline at our feet' height while that is within it (y down).
        local top, bottom = z.centre.y - z.size.y / 2, z.centre.y + z.size.y / 2
        local y = math.max(top, math.min(bottom, p.pos.y))
        local c = {}
        for k, q in ipairs(z.corners) do c[k] = { x = q.x, y = y, z = q.z } end
        for k = 1, 4 do
          local a, b = c[k], c[k % 4 + 1]
          local id = ("zl%d:%d"):format(i, k)
          draw.line(id, { from = a, to = b, colour = col })
          now[id] = true
          -- y is down: the post rises to a smaller y
          draw.line(id .. "p", { from = a, to = { x = a.x, y = a.y - POST, z = a.z }, colour = col })
          now[id .. "p"] = true
        end
      end
    end
  end
  for id in pairs(drawn) do
    if not now[id] then draw.remove(id) end
  end
  drawn = now
end

timer.every(1, refresh)
events.on("zone_change", refresh)
events.on("settings_changed", refresh)
