-- What we wear as the equipment menu's 4 x 4 grid of item icons, with the ammo count, in an edge window.

-- Equipment slots (0 main .. 15 back) in the menu's order, row by row.
local GRID = { { 0, 1, 2, 3 }, { 4, 9, 11, 12 }, { 5, 6, 13, 14 }, { 15, 10, 7, 8 } }
local CELL, GAP = 36, 4
local SIZE = 4 * CELL + 3 * GAP

local last

local function count(e)
  for _, it in ipairs(game.items(e.bag) or {}) do
    if it.slot == e.slot then return it.count end
  end
  return nil
end

local function draw(eq)
  local out = {}
  for r, row in ipairs(GRID) do
    for c, s in ipairs(row) do
      local x, y = (c - 1) * (CELL + GAP), (r - 1) * (CELL + GAP)
      out[#out + 1] = { type = "rect", x = x, y = y, w = CELL, h = CELL, colour = { 0, 0, 0, 90 } }
      out[#out + 1] = { type = "rect", x = x, y = y, w = CELL, h = CELL, line = 1, colour = { 160, 150, 120, 110 } }
      local e = eq[s]
      if e and e.id then
        out[#out + 1] = { type = "icon", kind = "item", id = e.id, x = x + 2, y = y + 2, size = CELL - 4 }
        local n = s == 3 and count(e)
        if n and n > 1 then
          out[#out + 1] = { type = "text", x = x + CELL - 14, y = y + CELL - 14, text = tostring(n), colour = { 255, 255, 255 } }
        end
      end
    end
  end
  return out
end

local function signature(eq)
  local t = {}
  for s = 0, 15 do
    local e = eq[s]
    t[#t + 1] = e and e.id and (e.id .. "/" .. tostring(s == 3 and count(e))) or "-"
  end
  return table.concat(t, ",")
end

local function tick()
  if not settings.get("on") then
    if last then ui.close("grid") end
    last = nil
    return
  end
  local eq = game.equipment() or {}
  local sig = signature(eq)
  if sig == last then return end
  last = sig
  ui.window("grid", {
    edge = true, width = SIZE + 24, title = "Equipment", heading = "Equipment",
    elements = { { type = "canvas", id = "cells", w = SIZE, h = SIZE, draw = draw(eq) } },
  })
  ui.open("grid")
end

timer.every(0.5, tick)
events.on("settings_changed", tick)
