-- Wide Scan by name (the wide scan add-ons): //track <name>, //track stop, //seek <name>. The zone's NPC list gives
-- the names; an entity's index is the low 12 bits of its server id.

local function matches(want)
  local low = want:lower()
  local out = {}
  for id, name in pairs(game.npc_names()) do
    if name:lower():find(low, 1, true) then out[#out + 1] = { id = id, name = name } end
  end
  return out
end

-- The nearest of the matches in range (else the first).
local function nearest(list)
  local best, dist
  for _, m in ipairs(list) do
    local e = game.entity(m.id)
    if e and e.distance and (not dist or e.distance < dist) then best, dist = m, e.distance end
  end
  return best or list[1], dist
end

commands.register("track", function(...)
  if not settings.get("on") then return end
  local want = table.concat({ ... }, " "):match("^%s*(.-)%s*$")
  if want:lower() == "stop" then
    actions.untrack()
    return
  end
  if want == "" then
    chat.add("Tracking Tools: //track <name>, //track stop, //seek <name>")
    return
  end
  local m = nearest(matches(want))
  if not m then
    chat.add("Tracking Tools: no " .. want .. " in this zone.")
    return
  end
  actions.track(m.id & 0xfff)
  chat.add("Tracking Tools: tracking " .. m.name .. ".")
end)

commands.register("seek", function(...)
  local want = table.concat({ ... }, " "):match("^%s*(.-)%s*$")
  if want == "" then return end
  local list = matches(want)
  local m, dist = nearest(list)
  if not m then
    chat.add("Tracking Tools: no " .. want .. " in this zone.")
  else
    chat.add(("Tracking Tools: %d %s in this zone%s."):format(#list, want,
      dist and (", the nearest %.1f yalms away"):format(dist) or ""))
  end
end)
