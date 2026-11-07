-- Notes on the map (boussole and kin): pins at places in a zone (kept for every character), party members in sight
-- and tracked names, drawn over the Map Overlay's box while it is open.

local NOTE = { 236, 196, 92, 255 }
local PARTY = { 110, 190, 255, 255 }
local TRACK = { 240, 100, 90, 255 }
local drawn = {}

local function say(t) chat.add("Map Notes: " .. t) end

local function store()
  local s = storage.account
  s.notes = s.notes or {}
  s.track = s.track or {}
  return s
end

local function zone_notes(zone)
  local s = store()
  local k = tostring(zone)
  s.notes[k] = s.notes[k] or {}
  return s.notes[k]
end

-- One mark: a dot and its label, inside the box.
local function mark(now, v, id, wx, wz, colour, label)
  local px, py = game.map_pos(wx, wz)
  if not px then return end
  local sx = v.x + (v.ox + px - (v.cx - v.span / 2)) * v.side / v.span
  local sy = v.y + (v.oy + py - (v.cy - v.span / 2)) * v.side / v.span
  if sx < v.x or sy < v.y or sx > v.x + v.side or sy > v.y + v.side then return end
  local u = hud.screen().ui_scale
  local r = 4 * u
  hud.rect(id, { x = sx - r, y = sy - r, w = 2 * r, h = 2 * r, round = r, colour = colour, layer = 2 })
  now[id] = true
  if label and label ~= "" then
    hud.text(id .. ":t", { x = sx + 7 * u, y = sy - 9 * u, text = label, size = 0.85, colour = colour,
      outline = { 0, 0, 0, 230 }, layer = 2 })
    now[id .. ":t"] = true
  end
end

events.on("frame", function()
  local now = {}
  local ok, v = pcall(mods.call, "map-overlay", "view")
  if settings.get("on") and ok and v then
    for i, n in ipairs(zone_notes(v.zone)) do
      if (n.map or v.number) == v.number then mark(now, v, "note" .. i, n.x, n.z, NOTE, i .. ". " .. n.text) end
    end
    if settings.get("party") then
      local me = (game.player() or {}).id
      for _, m in ipairs(game.party()) do
        local e = m.id ~= me and m.in_zone and game.entity(m.id)
        if e and e.pos then mark(now, v, "party" .. m.id, e.pos.x, e.pos.z, PARTY, m.name) end
      end
    end
    local track = store().track
    if next(track) then
      for _, e in ipairs(game.entities({ kinds = { "mob", "npc" } })) do
        if track[e.name:lower()] and e.pos and not e.hidden then mark(now, v, "track" .. e.id, e.pos.x, e.pos.z, TRACK, e.name) end
      end
    end
  end
  for id in pairs(drawn) do
    if not now[id] then hud.remove(id) end
  end
  drawn = now
end)

commands.register("mapnote", function(cmd, ...)
  if not settings.get("on") then return end
  local c = (cmd or ""):lower()
  local rest = table.concat({ ... }, " ")
  local p = game.player()
  if not p then return end
  local list = zone_notes(p.zone)
  if c == "add" then
    if rest == "" then say("//mapnote add <text>") return end
    local m = game.map()
    list[#list + 1] = { x = p.pos.x, z = p.pos.z, map = m and m.number, text = rest }
    say(("note %d added here."):format(#list))
  elseif c == "del" then
    local n = tonumber(rest)
    if not n or not list[n] then say("//mapnote del <number> (//mapnote list shows them)") return end
    table.remove(list, n)
    say("note " .. n .. " removed.")
  elseif c == "list" then
    if #list == 0 then say("no notes in " .. (res.zone(p.zone) or "this zone") .. ".") return end
    for i, n in ipairs(list) do say(("%d. %s"):format(i, n.text)) end
  elseif c == "track" then
    if rest == "" then say("//mapnote track <name>") return end
    store().track[rest:lower()] = true
    say("tracking " .. rest .. " on the map.")
  elseif c == "untrack" then
    store().track[rest:lower()] = nil
    say("no longer tracking " .. rest .. ".")
  else
    say("//mapnote add <text> | del <n> | list | track <name> | untrack <name>")
  end
end)
