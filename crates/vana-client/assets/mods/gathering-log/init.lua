-- Gathering (the gathering add-ons). A try at a point starts its event with what was found, whether the tool broke
-- and whether the bag was full (LandSandBoat's HELM: event params 0, 1, 2; 0 found nothing): s2c 0x032 / 0x034, the
-- point by its name.

local KINDS = { ["Harvesting Point"] = "Harvesting", ["Logging Point"] = "Logging", ["Mining Point"] = "Mining",
  ["Excavation Point"] = "Excavation" }
local stats = {}   -- kind -> {tries, found, broke, items = {id -> n}}

local function on_event(p)
  local d = p.data
  if #d < 0x14 then return end
  local npc = string.unpack("<I4", d, 5)
  local e = game.entity(npc)
  local kind = e and KINDS[e.name]
  if not kind then return end
  local item, broke = string.unpack("<I4I4", d, 9)
  local s = stats[kind] or { tries = 0, found = 0, broke = 0, items = {} }
  stats[kind] = s
  s.tries = s.tries + 1
  if broke == 1 then s.broke = s.broke + 1 end
  if item ~= 0 then
    s.found = s.found + 1
    s.items[item] = (s.items[item] or 0) + 1
  end
end

for _, id in ipairs({ 0x032, 0x034 }) do packets.on_in(id, on_event) end

local function item_name(id)
  local r = res.item(id)
  return r and r.name or ("item " .. id)
end

timer.every(1, function()
  if not settings.get("on") or not next(stats) then
    ui.close("gather")
    return
  end
  local els = {}
  local kinds = {}
  for k in pairs(stats) do kinds[#kinds + 1] = k end
  table.sort(kinds)
  for _, k in ipairs(kinds) do
    local s = stats[k]
    els[#els + 1] = { type = "gauge", style = "row", label = ("%s  %d tries%s"):format(k, s.tries,
      s.broke > 0 and (", %d broke"):format(s.broke) or ""), text = ("%d%%"):format(math.floor(s.found * 100 / s.tries + 0.5)),
      value = s.found / s.tries }
    local parts = {}
    for id, n in pairs(s.items) do parts[#parts + 1] = ("%s x%d"):format(item_name(id), n) end
    table.sort(parts)
    if #parts > 0 then els[#els + 1] = { type = "text", text = table.concat(parts, ", "), dim = true } end
  end
  ui.window("gather", { edge = true, width = 300, title = "Gathering", heading = "Gathering", elements = els })
  ui.open("gather")
end)

commands.register("gather", function(cmd)
  if (cmd or ""):lower() == "reset" then
    stats = {}
    chat.add("Gathering Log: started over.")
  else
    chat.add("Gathering Log: //gather reset starts over.")
  end
end)
