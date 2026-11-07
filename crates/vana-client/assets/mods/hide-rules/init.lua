-- Interface parts hidden by rule (the hide-the-HUD add-ons): in the Mog House, in named zones, while engaged, in
-- events. Each part named is one of ui.native.hide's HUD pieces.

local PARTS = { party = true, alliance = true, target = true, buffs = true, compass = true, minimap = true, cast = true,
  plates = true, log = true, timers = true, regime = true }
local hidden = {}  -- part -> true while we hide it

local function parts(key)
  local out = {}
  for p in (settings.get(key) or ""):gmatch("[^,]+") do
    p = p:match("^%s*(.-)%s*$"):lower()
    if PARTS[p] then out[p] = true end
  end
  return out
end

local function zones()
  local out = {}
  for z in (settings.get("zones") or ""):gmatch("[^,]+") do out[z:match("^%s*(.-)%s*$"):lower()] = true end
  return out
end

local function wanted()
  local want = {}
  if not settings.get("on") then return want end
  local info, me = game.info(), game.player()
  local function add(key)
    for p in pairs(parts(key)) do want[p] = true end
  end
  if info.mog_house then add("moghouse") end
  if info.zone and zones()[(res.zone(info.zone) or ""):lower()] then add("in_zones") end
  if me and me.status == 1 then add("fighting") end
  if info.event then add("events") end
  return want
end

timer.every(0.25, function()
  local want = wanted()
  for p in pairs(want) do
    if not hidden[p] then
      ui.native.hide(p, true)
      hidden[p] = true
    end
  end
  for p in pairs(hidden) do
    if not want[p] then
      ui.native.hide(p, false)
      hidden[p] = nil
    end
  end
end)
