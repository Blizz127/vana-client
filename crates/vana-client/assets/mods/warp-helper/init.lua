-- //warp (the warp add-ons): answers a Home Point's, Survival Guide's or Waypoint's menus by name, as the player
-- would pick each row; //warp home and //warp dim use the Warp spell or a warp item.

local places = require("src.places")

local function say(t) chat.add("Warp Helper: " .. t) end

-- Lower case, no punctuation but # and [ ], single spaces: "Ru'Lude Gardens." and "rulude gardens" match.
local function norm(s)
  return (s:lower():gsub("[^%w#%[%] ]", ""):gsub("%s+", " "):match("^%s*(.-)%s*$"))
end

local ALIAS = { sandy = "san doria", windy = "windurst", whitegate = "aht urhgan whitegate" }

-- region by zone, per menu
local region_of = {}
for kind, rows in pairs(places) do
  region_of[kind] = {}
  for _, row in ipairs(rows) do
    for _, z in ipairs(row[2]) do region_of[kind][norm(z)] = row[1] end
  end
end

-- The names that hold every word, an exact name first; nil and the candidates when several do.
local function pick_name(names, words)
  local want = norm(ALIAS[norm(words)] or words)
  local hits = {}
  for _, n in ipairs(names) do
    local k = norm(n)
    if k == want then return n end
    local all = true
    for w in want:gmatch("%S+") do
      -- a bare number is a "#n": "bivouac 2" is Frontier Bivouac #2
      local found = w:find("^%d+$") and (k .. " "):find("#" .. w .. "%D") or k:find(w, 1, true)
      if not found then all = false break end
    end
    if all then hits[#hits + 1] = n end
  end
  if #hits == 1 then return hits[1] end
  return nil, hits
end

local function zone_names(kind)
  local out = {}
  for _, row in ipairs(places[kind]) do
    for _, z in ipairs(row[2]) do out[#out + 1] = z end
  end
  return out
end

-- Menus ----------------------------------------------------------------------------------------------------------

local function sig(m) return m.question .. "\n" .. table.concat(m.options, "\n") end

-- The next menu whose question passes `test` and that is not the one just answered (10 s at most).
local function next_menu(test, last)
  local started = false
  for _ = 1, 100 do
    sleep(0.1)
    local e = game.event()
    if e then
      started = true
      if e.menu and test(e.menu.question) and sig(e.menu) ~= last then return e.menu end
    elseif started then
      return nil, "the menu closed."
    end
  end
  return nil, "the menu did not answer."
end

local function is(q) return function(s) return s == q end end
local function starts(q) return function(s) return s:sub(1, #q) == q end end

-- The option whose words start with `want` (normalised), or nil.
local function option(m, want)
  for i, o in ipairs(m.options) do
    local k = norm(o)
    if k == want or k:sub(1, #want + 1) == want .. " " then return i end
  end
end

-- Picks an option and waits for the next menu; the menu is left to the player when the walk cannot go on.
local Walk = {}
Walk.__index = Walk

local function walk() return setmetatable({ last = "" }, Walk) end

function Walk:wait(test)
  local m, err = next_menu(test, self.last)
  if not m then say(err) end
  self.m = m
  return m
end

function Walk:choose(i)
  self.last = sig(self.m)
  actions.choose(i)
end

-- Through a region list's pages to `region`; false when it is on none.
function Walk:region(question, region)
  for _ = 1, 4 do
    if not self:wait(is(question)) then return false end
    local i = option(self.m, norm(region))
    if i then self:choose(i) return true end
    local nxt = option(self.m, "next page")
    if not nxt then return false end
    self:choose(nxt)
  end
  return false
end

-- NPCs -----------------------------------------------------------------------------------------------------------

local REACH = 5.5

local function nearest(prefix)
  local best
  for _, e in ipairs(game.entities({ kinds = { "npc" } })) do
    if e.name:sub(1, #prefix) == prefix and not e.hidden and (not best or e.distance < best.distance) then best = e end
  end
  return best
end

local NPC = { hp = "Home Point", sg = "Survival Guide", wp = "Waypoint" }

-- Runs up to the NPC when it is a short way off, then talks to it.
local function reach_and_talk(e)
  if e.distance > REACH then
    if e.distance > 30 then
      say("the nearest " .. e.name .. " is too far away.")
      return false
    end
    actions.run_to(e.pos.x, e.pos.z, REACH - 1.5)
    for _ = 1, 100 do
      sleep(0.1)
      local n = game.entity(e.id)
      if n and n.distance <= REACH then break end
    end
  end
  actions.talk(e.id)
  return true
end

-- The three menus -------------------------------------------------------------------------------------------------

local function home_point(e, words)
  local num = words:match("%s(%d+)$")
  if num then words = words:sub(1, -#num - 2) end
  local zone, hits = pick_name(zone_names("home_point"), words)
  if not zone then
    say(#hits > 1 and ("which one: " .. table.concat(hits, ", ") .. "?") or ("no Home Point in " .. words .. "."))
    return
  end
  if not reach_and_talk(e) then return end
  local w = walk()
  if not w:wait(is("What will you do?")) then return end
  w:choose(option(w.m, "travel to another home point") or 1)
  if not w:region("Teleport to which region?", region_of.home_point[norm(zone)]) then
    if w.m then say("no Home Point registered in " .. zone .. ".") end
    return
  end
  if not w:wait(is("Teleport where?")) then return end
  local zi = option(w.m, norm(zone))
  if not zi then say("no Home Point registered in " .. zone .. ".") return end
  w:choose(zi)
  if not w:wait(starts("Teleport where?(")) then return end
  local at = num and option(w.m, "home point #" .. num)
  if not num then
    for i, o in ipairs(w.m.options) do
      if norm(o):find("^home point") then at = i break end
    end
  end
  if not at then say((num and ("Home Point #" .. num) or "no Home Point") .. " in " .. zone .. " is not registered.") return end
  w:choose(at)
  if not w:wait(starts("Teleport?")) then return end
  w:choose(option(w.m, "yes please") or 2)
end

local function survival_guide(e, words)
  local zone, hits = pick_name(zone_names("survival_guide"), words)
  if not zone then
    say(#hits > 1 and ("which one: " .. table.concat(hits, ", ") .. "?") or ("no Survival Guide in " .. words .. "."))
    return
  end
  if not reach_and_talk(e) then return end
  local w = walk()
  if not w:wait(is("What chapter will you read?")) then return end
  w:choose(option(w.m, "teleportation assistance") or 2)
  if not w:region("Travel to which region?", region_of.survival_guide[norm(zone)]) then
    if w.m then say("no Survival Guide registered in " .. zone .. ".") end
    return
  end
  if not w:wait(is("Where will you travel?")) then return end
  local zi = option(w.m, norm(zone))
  if not zi then say("no Survival Guide registered in " .. zone .. ".") return end
  w:choose(zi)
  if not w:wait(starts("Travel to ")) then return end
  local unit = settings.get("fare") == "Tabs" and "tabs" or "gil"
  local pay = option(w.m, "up and away")
  for i, o in ipairs(w.m.options) do
    if not pay and norm(o):find("^travel using %d+ " .. unit) then pay = i end
  end
  if not pay then say("the guide does not take " .. unit .. " for this trip.") return end
  w:choose(pay)
end

local function waypoint(e, words)
  if not reach_and_talk(e) then return end
  local w = walk()
  if not w:wait(starts("What will you do?")) then return end
  local names = {}
  for _, o in ipairs(w.m.options) do
    local z = o:match("^Go to (.-)%.")
    if z then names[#names + 1] = z end
  end
  -- "<zone> <place>": the longest zone name the words start with, then the place.
  local zone, place
  for _, z in ipairs(names) do
    local k = norm(z)
    local nw = norm(words)
    if (nw == k or nw:sub(1, #k + 1) == k .. " ") and (not zone or #k > #norm(zone)) then
      zone, place = z, nw:sub(#k + 2)
    end
  end
  if not zone then
    local z, hits = pick_name(names, words)
    if not z then
      say(#hits > 1 and ("which one: " .. table.concat(hits, ", ") .. "?") or ("this Waypoint does not go to " .. words .. "."))
      return
    end
    zone, place = z, ""
  end
  w:choose(option(w.m, "go to " .. norm(zone)))
  if not w:wait(function(q) return q:find("^Choose a destination") or q == "Warp to your destination?" end) then return end
  if w.m.question:find("^Choose a destination") then
    local spots = {}
    for i = 2, #w.m.options do spots[#spots + 1] = w.m.options[i] end
    local spot, hits = spots[1], nil
    if place ~= "" then spot, hits = pick_name(spots, place) end
    if not spot then
      say(#hits > 1 and ("which one: " .. table.concat(hits, ", ") .. "?") or ("no " .. place .. " in " .. zone .. "."))
      return
    end
    for i, o in ipairs(w.m.options) do
      if o == spot then w:choose(i) break end
    end
    local m = next_menu(function(q) return q == "Warp to your destination?" end, w.last)
    if not m then return end
    w.m = m
  end
  w:choose(option(w.m, "yes") or 1)
end

local FLOWS = { hp = home_point, sg = survival_guide, wp = waypoint }

-- Warp items -----------------------------------------------------------------------------------------------------

local WARP = 261
local SLOT = { left_ring = 13, main = 0 }
local HOME = {
  { name = "Warp Ring", slot = "left_ring" },
  { name = "Warp Cudgel", slot = "main" },
  { name = "Instant Warp" },
}
local DIM = {
  holla = { name = "Dim. Ring (Holla)", slot = "left_ring" },
  dem = { name = "Dim. Ring (Dem)", slot = "left_ring" },
  mea = { name = "Dim. Ring (Mea)", slot = "left_ring" },
}

local function u32(s, at)
  local a, b, c, d = s:byte(at, at + 3)
  return a + b * 256 + c * 65536 + d * 16777216
end

-- Charges left and when it can be used (Vana'diel seconds; 0 now), from a charged item's extdata.
local function charge_state(it)
  local x = it.extdata
  if not x or #x < 12 or x:byte(1) ~= 1 then return 1, 0 end
  local ready = x:byte(4) & 0x40 ~= 0
  return x:byte(2), ready and 0 or math.max(u32(x, 5), u32(x, 9))
end

-- The inventory and the wardrobes: where gear is worn and items used from.
local BAGS = { 0, 8, 10, 11, 12, 13, 14, 15, 16 }

local function find_item(name)
  return (game.find_items(name, BAGS) or {})[1]
end

local function wait_text(secs)
  secs = math.floor(secs)
  if secs >= 3600 then return string.format("%d:%02d:%02d", secs // 3600, secs % 3600 // 60, secs % 60) end
  return string.format("%d:%02d", secs // 60, secs % 60)
end

local function can_cast(id)
  local r, p = res.spell(id), game.player()
  if not r or not p then return false end
  local known = false
  for _, s in ipairs(game.spells()) do
    if s == id then known = true break end
  end
  local function job_ok(job, lv) return job and r.levels[job] and r.levels[job] <= (lv or 0) end
  return known and (job_ok(p.main_job, p.main_level) or job_ok(p.sub_job, p.sub_level))
    and (p.mp or 0) >= r.mp and (game.recasts().spells[id] or 0) == 0
end

-- Gone: another zone, or a jump (a warp into the zone we are in loads no new zone).
local function moved_from(zone, pos)
  local p = game.player()
  if not p or not p.pos then return false end
  local dx, dz = p.pos.x - pos.x, p.pos.z - pos.z
  return p.zone ~= zone or dx * dx + dz * dz > 100
end

-- Wears the item if it is gear, waits out its equip delay, uses it, and puts the old piece back after the warp.
-- true once used; false and seconds to wait (no charges: nil; true third when it cannot be worn); nil when not held.
local function use_warp_item(spec)
  local it = find_item(spec.name)
  if not it then return nil end
  if spec.slot and not game.can_wear(it.id) then return false, nil, true end
  local charges, at = charge_state(it)
  if charges == 0 then return false end
  local now = game.time().earth
  local delay = (res.item(it.id) or {}).use_delay or 0
  local worn = spec.slot and game.equipment()[SLOT[spec.slot]]
  local wearing = worn and worn.id == it.id
  -- worn and only its equip delay left: wait it out
  if at > now and not (wearing and at - now <= delay + 2) then return false, at - now end
  local old
  if spec.slot and not wearing then
    old = worn and worn.id and { bag = worn.bag, index = worn.slot }
    actions.equip(spec.slot, { bag = it.bag, index = it.slot })
    sleep(1)
    if (game.equipment()[SLOT[spec.slot]] or {}).id ~= it.id then return false, nil, true end
    say("wearing " .. spec.name .. "; using it in " .. math.floor(delay) .. " seconds.")
    -- The server's item update after the swap carries the equip delay's end (no time: ready).
    local start = os.clock()
    sleep(1)
    while os.clock() - start < delay + 15 do
      local cur = find_item(spec.name)
      local t = cur and select(2, charge_state(cur)) or 0
      if t == 0 or game.time().earth > t then break end
      sleep(0.5)
    end
  elseif at > now then
    sleep(at - now + 1)
  end
  local me = game.player()
  local zone, pos = me.zone, { x = me.pos.x, z = me.pos.z }
  actions.use_item(it.id, "<me>")
  -- after the warp, or 30 s if it never came
  if old and settings.get("gear_back") then
    for _ = 1, 300 do
      sleep(0.1)
      if moved_from(zone, pos) then
        sleep(3)
        break
      end
    end
    actions.equip(spec.slot, old)
  end
  return true
end

-- The first of the items that can be used now; else why not.
local function use_first(specs, none)
  local soonest, wait_for, spent, unworn
  for _, spec in ipairs(specs) do
    local ok, wait, cannot = use_warp_item(spec)
    if ok then return end
    if ok == false and wait and (not soonest or wait < soonest) then soonest, wait_for = wait, spec.name end
    if ok == false and cannot then unworn = unworn or spec.name end
    if ok == false and not wait and not cannot then spent = spent or spec.name end
  end
  if soonest then
    say(wait_for .. " is ready in " .. wait_text(soonest) .. ".")
  elseif spent then
    say(spent .. " has no charges left.")
  elseif unworn then
    say("you cannot wear " .. unworn .. " now.")
  else
    say(none)
  end
end

local function home()
  if can_cast(WARP) then
    actions.cast(WARP, "<me>")
    return
  end
  use_first(HOME, "no Warp spell ready and no Warp Ring, Warp Cudgel or Instant Warp.")
end

-- The command ------------------------------------------------------------------------------------------------------

local USAGE = "//warp [hp | sg | wp] <zone> [number or place], //warp home, //warp dim <holla | dem | mea>"

commands.register("warp", function(...)
  if not settings.get("on") then return end
  local args = { ... }
  local first = (args[1] or ""):lower()
  if first == "" then say(USAGE) return end
  if game.event() then say("finish the conversation first.") return end
  if first == "home" then home() return end
  if first == "dim" then
    local spec = DIM[(args[2] or ""):lower()]
    if not spec then say("//warp dim <holla | dem | mea>") return end
    use_first({ spec }, "no " .. spec.name .. ".")
    return
  end
  local kind
  if FLOWS[first] then
    kind = first
    table.remove(args, 1)
  end
  local words = table.concat(args, " ")
  if words == "" then say(USAGE) return end
  local best, best_kind
  for key, name in pairs(NPC) do
    if not kind or kind == key then
      local e = nearest(name)
      if e and (not best or e.distance < best.distance) then best, best_kind = e, key end
    end
  end
  if not best then
    say("no " .. (kind and NPC[kind] or "Home Point, Survival Guide or Waypoint") .. " here.")
    return
  end
  FLOWS[best_kind](best, words)
end)
