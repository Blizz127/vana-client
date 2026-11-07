-- GearSwap files, run as GearSwap runs them: a sandbox env per file (_G is the env), get_sets at load, then
-- pretarget / precast / midcast around each action the player's command line starts, aftercast when it ends,
-- status_change, buff_change, sub_job_change and self_command; equip() collects an event's gear, sent when the event
-- returns. Its data (player, world, buffactive, pet, spell) is rebuilt before every event, with Windower's names.

local core = require("src.core")
local compat = require("src.compat")
local names = require("src.names")
local GS = names.GS

local M = {}

local env            -- the loaded file's env
M.file = nil         -- its path
local event = nil    -- the running event
local equips = {}    -- slot -> item value, this event
local disabled, held = {}, {}
local cancelled, new_target = false, nil
local show_swaps, debug_mode = false, false
local registry = {}  -- actions sent: {spell, at, timeout}
local user_events = {}
local unhandled = {}

local SLOT_ID, ALIAS = {}, { ranged = "range", ear1 = "left_ear", learring = "left_ear", lear = "left_ear",
  ear2 = "right_ear", rearring = "right_ear", rear = "right_ear", ring1 = "left_ring", lring = "left_ring",
  ring2 = "right_ring", rring = "right_ring" }
for i, n in ipairs(core.SLOTS) do SLOT_ID[n] = i - 1 end

local function slot_of(k)
  if type(k) ~= "string" then return nil end
  k = k:lower()
  return SLOT_ID[ALIAS[k] or k]
end

local function say(text) chat.add("Gearshift: " .. text) end

-- ---- Case-insensitive tables (GearSwap's "user tables") ----

local function utable(t)
  local u = setmetatable({}, {
    __index = function(_, k) if type(k) == "string" then return rawget(_, k:lower()) end end,
    __newindex = function(u, k, v) rawset(u, type(k) == "string" and k:lower() or k, v) end,
  })
  for k, v in pairs(t or {}) do u[k] = v end
  return u
end

-- ---- The data ----

local empty = { name = "empty" }

local function target_table(e, raw)
  if not e then return { type = "NONE" } end
  local me = game.player()
  local kind = e.me and "SELF" or (e.kind == "player" and "PLAYER") or (e.kind == "npc" and "NPC") or "MONSTER"
  local t = utable({
    name = e.name, id = e.id, index = e.index, hpp = e.hpp, distance = e.distance, x = e.pos and e.pos.x,
    y = e.pos and e.pos.y, z = e.pos and e.pos.z, is_npc = e.kind ~= "player", claim_id = e.claim,
    status = GS.STATUS[e.status] or tostring(e.status), status_id = e.status, type = kind,
    in_party = e.in_party, in_alliance = e.in_alliance, isallymember = e.in_alliance, valid_target = e.targetable,
    target_index = e.target_index, tp = e.tp, mpp = e.mpp, model_size = e.hitbox, raw = raw,
  })
  if e.id == me.id then t.type = "SELF" end
  return t
end

local function bag_table(bag)
  local t = utable({})
  for _, it in ipairs(game.items(bag) or {}) do
    local r = core.record(it.id)
    if r then
      local e = t[r.name]
      if e then
        e.count = e.count + it.count
      else
        e = { id = it.id, count = it.count, status = it.locked, slot = it.slot, extdata = it.extdata,
          shortname = r.name:lower(), longname = r.log_name ~= r.name and r.log_name:lower() or nil }
        t[r.name] = e
        if r.log_name and r.log_name ~= r.name then t[r.log_name] = e end
      end
    end
  end
  return t
end

local function job(id) return id and id ~= 0 and res.job(id) or nil end

local function refresh()
  local p = game.player()
  local player = utable({
    name = p.name, id = p.id, index = p.index, main_job = job(p.main_job), main_job_id = p.main_job,
    main_job_level = p.main_level, main_job_full = names.JOBS_FULL[p.main_job or 0], sub_job = job(p.sub_job),
    sub_job_id = p.sub_job, sub_job_level = p.sub_level, sub_job_full = names.JOBS_FULL[p.sub_job or 0],
    hp = p.hp, mp = p.mp, tp = p.tp, hpp = p.hpp, mpp = p.mpp, max_hp = p.hp_max, max_mp = p.mp_max,
    status = GS.STATUS[p.status] or tostring(p.status), status_id = p.status, target_index = nil,
    in_combat = p.status == 1,
  })
  player.vitals = { hp = p.hp, mp = p.mp, tp = p.tp, hpp = p.hpp, mpp = p.mpp, max_hp = p.hp_max, max_mp = p.mp_max }
  player.job = (player.main_job or "") .. "/" .. (player.sub_job or "")
  local eq = utable({})
  local worn = core.worn()
  for s = 0, 15 do
    local w = worn[s]
    local r = w and core.record(w.id)
    eq[core.SLOTS[s + 1]] = r and r.name or "empty"
  end
  for alias, real in pairs(ALIAS) do eq[alias] = eq[real] end
  player.equipment = eq
  local buffs, active = {}, utable({})
  for _, b in ipairs(game.buffs() or {}) do
    buffs[#buffs + 1] = b.id
    local n = res.status(b.id)
    active[b.id] = (active[b.id] or 0) + 1
    if n then active[n] = (active[n] or 0) + 1 end
  end
  player.buffs = buffs
  player.target = target_table(game.target())
  -- The bags as tables of items by name, made when asked for.
  setmetatable(player, {
    __index = function(t, k)
      if type(k) ~= "string" then return nil end
      k = k:lower()
      local v = rawget(t, k)
      if v ~= nil then return v end
      local bag = core.BAG_IDS[k]
      if bag then
        v = bag_table(bag)
        rawset(t, k, v)
      end
      return v
    end,
    __newindex = function(t, k, v) rawset(t, type(k) == "string" and k:lower() or k, v) end,
  })
  env.player, env.buffactive = player, active
  local t = game.time()
  local weather = game.weather()
  local storm
  for _, b in ipairs(buffs) do storm = storm or names.STORMS[b] end
  local w = storm or weather
  env.world = utable({
    zone = res.zone(p.zone or 0), area = res.zone(p.zone or 0), zone_id = p.zone, day = res.day(t.weekday),
    day_element = GS.ELEMENTS[({ [0] = 0, 3, 5, 2, 1, 4, 6, 7 })[t.weekday]], moon = res.moon(t.moon_phase),
    moon_pct = t.moon, time = t.hour * 60 + t.minute, weather_id = w, weather = res.weather(w),
    weather_element = GS.WEATHER_ELEMENT[w], real_weather_id = weather, real_weather = res.weather(weather),
    real_weather_element = GS.WEATHER_ELEMENT[weather], mog_house = game.info().mog_house,
    in_mog_house = game.info().mog_house,
  })
  local pet = game.entity_by_tag("pet")
  if pet then
    env.pet = target_table(pet)
    env.pet.isvalid = true
  else
    env.pet = utable({ isvalid = false })
  end
  local party = { count = 0 }
  for _, m in ipairs(game.party() or {}) do
    if m.party == 0 then
      party.count = party.count + 1
      party[party.count] = utable({ name = m.name, hp = m.hp, hpp = m.hpp, mp = m.mp, mpp = m.mpp, tp = m.tp, zone = m.zone })
    end
  end
  env.party = party
  env.alliance = { party, count = party.count }
end

-- ---- Spells ----

local spell_ids, ability_ids
local function index_names()
  if spell_ids then return end
  spell_ids, ability_ids = {}, {}
  for id = 1, 1023 do
    local s = res.spell(id)
    if s and s.name and s.name ~= "" then spell_ids[s.name:lower()] = spell_ids[s.name:lower()] or id end
  end
  for id = 0, 0x7ff do
    local a = res.ability(id)
    if a and a.name and a.name ~= "" then ability_ids[a.name:lower()] = ability_ids[a.name:lower()] or id end
  end
end

local function targets_set(bits)
  local t = {}
  for bit, n in pairs(GS.TARGETS) do
    if (bits or 0) & bit ~= 0 then t[n] = true end
  end
  return t
end

-- The spell table for an action: from its resource, with GearSwap's fields.
local function spell_of(act, raw)
  local p = game.player()
  local s
  if act.kind == "item" then
    local it
    for _, x in ipairs(game.items(act.bag) or {}) do if x.slot == act.index then it = x break end end
    local r = it and core.record(it.id) or {}
    s = { id = it and it.id or 0, en = r.name, enl = r.log_name, name = r.name, english = r.name, english_log = r.log_name,
      prefix = "/item", type = "Item", action_type = "Item", cast_time = r.cast_time }
  elseif act.category == 3 then
    local r = res.spell(act.param) or {}
    s = { id = act.param, en = r.name, name = r.name, english = r.name, prefix = "/magic",
      type = GS.SPELL_TYPES[r.kind or 0] or "Unknown", skill = GS.SKILLS[r.skill or 0], skill_id = r.skill,
      element = GS.ELEMENTS[r.element or 15], element_id = r.element, mp_cost = r.mp or 0, cast_time = r.cast_time,
      recast = r.recast, recast_id = act.param, range = r.range, targets = targets_set(r.targets), action_type = "Magic",
      tp_cost = 0 }
  elseif act.category == 16 then
    s = { id = 0, en = "Ranged", name = "Ranged", english = "Ranged", prefix = "/range", type = "Misc",
      element = "None", range = 25, targets = { Enemy = true }, action_type = "Ranged Attack" }
  else
    local id = core.res_id(act)
    local r = res.ability(id) or {}
    local ws = act.category == 7
    s = { id = act.param, en = r.name, name = r.name, english = r.name, prefix = ws and "/weaponskill" or "/jobability",
      type = ws and "WeaponSkill" or "JobAbility", recast_id = r.recast_id, recast = r.recast,
      targets = targets_set(r.targets), action_type = "Ability", tp_cost = ws and p.tp or (r.tp or 0),
      mp_cost = r.cost or 0, element = "None" }
  end
  s.tpaftercast = (p.tp or 0) - (s.tp_cost or 0)
  s.mpaftercast = (p.mp or 0) - (s.mp_cost or 0)
  s.mppaftercast = p.mp_max and p.mp_max > 0 and (s.mp_cost or 0) > 0 and s.mpaftercast / p.mp_max or p.mpp
  s.target = target_table(game.entity(act.target), raw or "<t>")
  s.interrupted = false
  return utable(s)
end

-- ---- Equip processing ----

local BAG_KEYS = {}
for id, n in pairs(core.BAG_NAMES) do BAG_KEYS[n] = id end

local function want(v)
  if v == empty then return { remove = true } end
  if type(v) == "string" then return { name = v } end
  if type(v) == "table" and type(v.name) == "string" then
    local augs = v.augments or (v.augment and { v.augment })
    local bag = type(v.bag) == "string" and BAG_KEYS[(v.bag:gsub("%s", ""):lower())] or nil
    return { name = v.name, augments = augs, bag = bag, priority = tonumber(v.priority) or 0 }
  end
end

-- This event's gear as packets (sent at once unless `keep`).
local function process(keep)
  local wants = {}
  for s, v in pairs(equips) do wants[s] = want(v) end
  equips = {}
  if next(wants) == nil then return {} end
  local list = core.resolve(wants, { log_names = true })
  if show_swaps and #list > 0 then
    local t = {}
    for _, c in ipairs(list) do
      local r = c.id and core.record(c.id)
      t[#t + 1] = core.SLOTS[c.slot + 1] .. ": " .. (r and r.name or "empty")
    end
    say(event .. ": " .. table.concat(t, ", "))
  end
  local pkts = core.packets(list, "auto", 2)
  if not keep then core.send(pkts) end
  return pkts
end

-- Runs a hook as an event: data refreshed, equip() collected.
local function run(name, ...)
  local f = env and rawget(env, name)
  if type(f) ~= "function" then return false end
  event, equips = name, {}
  env._global.current_event = name
  refresh()
  local ok, err = pcall(f, ...)
  if not ok then say(name .. ": " .. tostring(err)) end
  return true
end

-- ---- The env ----

local function equip(...)
  for i = 1, select("#", ...) do
    local set = select(i, ...)
    if type(set) ~= "table" then error("Trying to combine non-gear sets.", 2) end
    for k, v in pairs(set) do
      local s = slot_of(k)
      if s then
        if disabled[s] then held[s] = v else equips[s] = v end
      end
    end
  end
end

local function set_combine(...)
  local out = {}
  for i = 1, select("#", ...) do
    local set = select(i, ...)
    if type(set) ~= "table" then error("Trying to combine non-gear sets.", 2) end
    for k, v in pairs(set) do
      local s = slot_of(k)
      if s then out[core.SLOTS[s + 1]] = v end
    end
  end
  return out
end

local function slots_of(...)
  local list = {}
  local args = { ... }
  if type(args[1]) == "table" then args = args[1] end
  for _, k in ipairs(args) do
    local s = slot_of(k)
    if not s then error("Unknown slot: " .. tostring(k), 3) end
    list[#list + 1] = s
  end
  return list
end

local console

-- The data files' folder, case-insensitively: "a/b.lua" as it is on disk.
local function find_file(dir, name)
  local lname = name:lower()
  for _, n in ipairs(fs.list(dir) or {}) do
    if n:lower() == lname then return dir .. n end
  end
end

local function search(name)
  local p = game.player()
  for _, dir in ipairs({ "gearswap/" .. (p.name or "") .. "/", "gearswap/common/", "gearswap/" }) do
    local f = find_file(dir, name)
    if f then return f end
  end
end

local function run_file(path, into)
  local text = fs.read(path)
  if not text then error("file not found: " .. path, 3) end
  local fenv = env
  if into then fenv = setmetatable(into, { __index = env }) end
  local chunk, err = load(text, "@" .. path, "t", fenv)
  if not chunk then error(err, 3) end
  if into then
    pcall(chunk)
    return into
  end
  return chunk()
end

local LIBS = { tables = true, strings = true, sets = true, lists = true, logger = true, functions = true, maths = true }

local function include(name, into)
  name = tostring(name)
  local lname = name:lower()
  if lname == "resources" then return env.gearswap.res end
  if LIBS[lname] or lname == "texts" or lname == "packets" or lname == "extdata" or lname == "pack" then
    return lname == "texts" and env.texts or nil
  end
  if not lname:match("%.lua$") then lname = lname .. ".lua" end
  local path = search(lname)
  -- GearSwap's libraries where the player has no copy: modes (ours), the Organizer hook (nothing to do here).
  if not path and lname == "modes.lua" then
    env.M = env.M or require("src.modes")
    return
  end
  if not path and lname == "organizer-lib.lua" then return end
  if not path then error("Cannot find the include file (" .. name .. ").", 2) end
  return run_file(path, into)
end

local function make_env()
  local e = {}
  for _, k in ipairs({ "type", "tonumber", "pairs", "ipairs", "next", "select", "assert", "error", "pcall", "xpcall",
    "setmetatable", "getmetatable", "rawset", "rawget", "rawequal", "rawlen", "os", "coroutine", "utf8" }) do
    e[k] = _G[k]
  end
  compat.install(e)
  e.print = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    log.info(table.concat(t, " "))
  end
  e._G = e
  e.sets = { naked = {} }
  for _, n in ipairs(core.SLOTS) do e.sets.naked[n] = empty end
  e.empty = empty
  e.equip, e.set_combine = equip, set_combine
  e.cancel_spell = function(v)
    if event ~= "pretarget" and event ~= "precast" and event ~= "filtered_action" then
      error("cancel_spell() is only valid in pretarget, precast and filtered_action", 2)
    end
    cancelled = v ~= false
  end
  e.change_target = function(t)
    if event ~= "pretarget" then error("change_target() is only valid in pretarget", 2) end
    new_target = t
  end
  e.cast_delay = function() end
  e.move_spell_target = function() end
  e.disable = function(...) for _, s in ipairs(slots_of(...)) do disabled[s] = true end end
  e.enable = function(...)
    local out = {}
    for _, s in ipairs(slots_of(...)) do
      disabled[s] = nil
      if held[s] ~= nil then
        out[core.SLOTS[s + 1]] = held[s]
        equips[s] = held[s]
        held[s] = nil
      end
    end
    return out
  end
  e.midaction = function(clear)
    if clear == false then registry = {} return false end
    local now = clock()
    for _, r in ipairs(registry) do
      if now < r.ends then return true, r.spell end
    end
    return false
  end
  e.pet_midaction = function() return false end
  e.print_set = function(set, title)
    if type(set) ~= "table" then error("print_set: not a set", 2) end
    say(tostring(title or "set"))
    for k, v in pairs(set) do chat.add(("  %s: %s"):format(tostring(k), type(v) == "table" and tostring(v.name) .. " (Adv.)" or tostring(v))) end
  end
  e.show_swaps = function(v) show_swaps = v ~= false end
  e.debug_mode = function(v) debug_mode = v ~= false end
  e.set_language = function() end
  e.include, e.require = include, include
  e.include_path = function() end
  e.register_unhandled_command = function(f) unhandled[#unhandled + 1] = f end
  e.send_command = function(cmd) console(cmd) end
  e.add_to_chat = function(c, text)
    if text == nil then text = c end
    chat.add(tostring(text))
  end
  e._global = { current_event = "None" }
  e._settings = { debug_mode = false, show_swaps = false, demo_mode = false }
  e._addon = { name = "GearSwap", version = "0.940", commands = { "gs", "gearswap" } }
  e.language = "english"
  e.windower = require("src.windower").make(e, function(name, f) user_events[#user_events + 1] = { name = name, f = f } return #user_events end, function(cmd) console(cmd) end)
  e.gearswap = { res = require("src.windower").res(), default_slot_map = core.SLOTS, encumbrance_table = {},
    gearswap_disabled = false, pathsearch = function(list) for _, n in ipairs(list) do local f = search(n:lower()) if f then return f end end end }
  e.texts = require("src.texts")
  e.coroutine = setmetatable({
    schedule = function(f, delay) timer.after(delay or 0, f) end,
    sleep = function(s) sleep(s) end,
  }, { __index = coroutine })
  return e
end

-- ---- Loading ----

local CANDIDATES = { "%s_%s.lua", "%s-%s.lua", "%s_%s.lua", "%s-%s.lua", "%s.lua", "%s.lua", "%s.lua", "default.lua" }

-- The file for this character and job, as GearSwap looks for it.
function M.find()
  local p = game.player()
  local short, full = job(p.main_job), names.JOBS_FULL[p.main_job or 0]
  if not short then return nil end
  local list = {
    p.name .. "_" .. short .. ".lua", p.name .. "-" .. short .. ".lua", p.name .. "_" .. full .. ".lua",
    p.name .. "-" .. full .. ".lua", p.name .. ".lua", short .. ".lua", full .. ".lua", "default.lua",
  }
  for _, dir in ipairs({ "gearswap/" .. p.name .. "/", "gearswap/common/", "gearswap/" }) do
    for _, n in ipairs(list) do
      local f = find_file(dir, n)
      if f then return f end
    end
  end
end

function M.unload()
  if env and M.file then run("file_unload", M.file) end
  require("src.texts").clear_all()
  env, M.file, registry, user_events, unhandled, equips = nil, nil, {}, {}, {}, {}
end

function M.load(path)
  M.unload()
  env = make_env()
  M.file = path
  -- player, world, buffactive are there while the file's body runs, as GearSwap has them.
  refresh()
  local ok, err = pcall(run_file, path)
  if not ok then
    say("could not load " .. path .. ": " .. tostring(err))
    env, M.file = nil, nil
    return false
  end
  say("loaded " .. path)
  run("get_sets")
  process()
  return true
end

function M.loaded() return env ~= nil end

-- The item names the loaded file's sets hold.
function M.gear_names() return env and core.set_names(rawget(env, "sets"), slot_of) or {} end

-- ---- The command path: lines that start actions ----

local PREFIX = { ["/ma"] = "magic", ["/magic"] = "magic", ["/so"] = "magic", ["/song"] = "magic", ["/nin"] = "magic",
  ["/ninjutsu"] = "magic", ["/ja"] = "ability", ["/jobability"] = "ability", ["/pet"] = "ability",
  ["/bstpet"] = "ability", ["/ws"] = "ability", ["/weaponskill"] = "ability", ["/ra"] = "ranged", ["/range"] = "ranged",
  ["/rangedattack"] = "ranged", ["/throw"] = "ranged", ["/shoot"] = "ranged", ["/item"] = "item" }

local lines = {}  -- {group, name, raw, at}: command lines seen, waiting for their action packets

function M.typed(line)
  if not env then return end
  local t = compat.tokens((line:gsub("<wait%s+[%d%.]+>", "")))
  local group = t[1] and PREFIX[t[1]:lower()]
  if not group then return end
  local name, raw = (t[2] or ""):lower(), t[3]
  if group == "ranged" then name, raw = "ranged", t[2] end
  lines[#lines + 1] = { group = group, name = name, raw = raw, at = clock() }
  while #lines > 8 do table.remove(lines, 1) end
end

local function line_for(act)
  index_names()
  local now = clock()
  for i = #lines, 1, -1 do
    local l = lines[i]
    if now - l.at > 3 then
      table.remove(lines, i)
    else
      local ok
      if act.kind == "item" then
        local s = spell_of(act)
        ok = l.group == "item" and s.name and (s.name:lower() == l.name or (s.enl or ""):lower() == l.name)
      elseif act.category == 3 then
        ok = l.group == "magic" and spell_ids[l.name] == act.param
      elseif act.category == 16 then
        ok = l.group == "ranged"
      else
        ok = l.group == "ability" and ability_ids[l.name] == core.res_id(act)
      end
      if ok then
        table.remove(lines, i)
        return l
      end
    end
  end
end

-- The action packet: pretarget, precast, the action, midcast, in that order in one batch; false drops the client's.
function M.action(act)
  if not env then return end
  local l = line_for(act)
  if not l then return end
  local spell = spell_of(act, l.raw)
  cancelled, new_target = false, nil
  local out = {}
  if run("pretarget", spell) then
    for _, d in ipairs(process(true)) do out[#out + 1] = d end
    if new_target then
      local e = game.entity_by_tag(new_target)
      if e then
        core.retarget(act, e.id, e.index)
        spell.target = target_table(e, new_target)
      end
    end
  end
  if not cancelled and run("precast", spell) then
    if cancelled then equips = {} else
      for _, d in ipairs(process(true)) do out[#out + 1] = d end
    end
  end
  core.send(out)
  if cancelled then return false end
  local mid = {}
  if run("midcast", spell) then mid = process(true) end
  core.H.inject(act.packet)
  core.send(mid)
  local timeout = spell.cast_time and spell.cast_time * 1.1 + 2 or ({ Ability = 3, Magic = 20, ["Ranged Attack"] = 10, Item = 10 })[spell.action_type] or 3
  registry[#registry + 1] = { spell = spell, ends = clock() + timeout }
  return false
end

-- ---- The result path ----

local FINISH = { [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [11] = true, [13] = true, [14] = true, [15] = true }

function M.on_action(a)
  if not env or a.actor ~= game.player().id then return end
  local interrupted = a.param == 28787 and (a.category == 7 or a.category == 8 or a.category == 9 or a.category == 12)
  if not FINISH[a.category] and not interrupted then return end
  -- The oldest entry of that kind ends.
  local now = clock()
  for i = #registry, 1, -1 do
    if now > registry[i].ends then table.remove(registry, i) end
  end
  local entry = table.remove(registry, 1)
  if not entry then return end
  local spell = entry.spell
  spell.interrupted = interrupted
  if interrupted then spell.action_type = "Interruption" end
  local first = a.targets and a.targets[1]
  spell.value = first and first.results and first.results[1] and first.results[1].value
  if run("aftercast", spell) then process() end
end

-- 0x029: an "unable to act" message about us ends our newest action, interrupted; a death ends those aimed at the dead.
local UNABLE = {}
for _, id in ipairs({ 17, 18, 48, 71, 72, 78, 84, 87, 88, 89, 90, 154, 191, 313, 328, 410, 428, 429, 516, 517, 523,
  524, 525, 547, 568, 569, 575 }) do UNABLE[id] = true end
local DEATHS = { [6] = true, [20] = true, [113] = true, [406] = true, [605] = true, [646] = true }

function M.battle_message(actor, target, message)
  if not env then return end
  local me = game.player().id
  local msg = message & 0x7fff
  if actor == me and UNABLE[msg] then
    local entry = table.remove(registry)
    if not entry then return end
    entry.spell.interrupted, entry.spell.action_type = true, "Interruption"
    if run("aftercast", entry.spell) then process() end
  elseif DEATHS[msg] then
    for i = #registry, 1, -1 do
      local e = registry[i]
      if e.spell.target and e.spell.target.id == target then
        table.remove(registry, i)
        if run("aftercast", e.spell) then process() end
      end
    end
  end
end

function M.status_change(new, old)
  if not env then return end
  local bad = { [2] = true, [3] = true, [4] = true }
  if bad[new] or bad[old] then return end
  if run("status_change", GS.STATUS[new] or tostring(new), GS.STATUS[old] or tostring(old)) then process() end
end

function M.buff_change(id, gained)
  if not env then return end
  local n = res.status(id)
  if not n then return end
  if run("buff_change", n, gained, { id = id, name = n }) then process() end
end

function M.sub_job_change(new, old)
  if not env then return end
  if run("sub_job_change", job(new), job(old)) then process() end
end

-- User Windower events registered with windower.register_event, by our event names.
function M.user_event(name, ...)
  if not env then return end
  for _, u in ipairs(user_events) do
    if u.f and u.name == name then
      event, equips = "user", {}
      refresh()
      local ok, err = pcall(u.f, ...)
      if not ok then say(name .. ": " .. tostring(err)) end
      process()
    end
  end
end

-- ---- Commands (//gs ...) ----

local function path_set(text)
  local t = env
  local first = true
  for key in text:gmatch("[^%.%[%]]+") do
    key = key:gsub("^[\"']", ""):gsub("[\"']$", "")
    if first and key ~= "sets" then t = env.sets end
    first = false
    if type(t) ~= "table" then return nil end
    t = t[tonumber(key) or key]
  end
  return t
end

function M.command(args)
  local cmd = (args[1] or ""):lower()
  if cmd == "c" then
    if not env then return end
    local text = table.concat(args, " ", 2)
    if text == "" then say("gs c needs a command") return end
    if run("self_command", text) then process() end
  elseif cmd == "equip" then
    if not env then return end
    local set = path_set(table.concat(args, " ", 2))
    if type(set) ~= "table" then say("That set does not exist") return end
    event, equips = "equip_command", {}
    refresh()
    equip(set)
    process()
  elseif cmd == "reload" or cmd == "r" then
    local f = M.find()
    if f then M.load(f) else say("no file for this job") end
  elseif cmd == "load" or cmd == "l" then
    local n = args[2] or ""
    if not n:lower():match("%.lua$") then n = n .. ".lua" end
    local f = search(n)
    if f then M.load(f) else say("no file " .. n) end
  elseif cmd == "enable" or cmd == "disable" then
    local on = cmd == "enable"
    local list = {}
    if args[2] == nil or args[2]:lower() == "all" then for s = 0, 15 do list[#list + 1] = s end
    else for i = 2, #args do local s = slot_of(args[i]) if s then list[#list + 1] = s end end end
    event, equips = "equip_command", {}
    for _, s in ipairs(list) do
      if on then
        disabled[s] = nil
        if held[s] ~= nil then equips[s] = held[s] held[s] = nil end
      else
        disabled[s] = true
      end
    end
    if env then refresh() process() end
  elseif cmd == "showswaps" then
    show_swaps = not show_swaps
    say("show swaps " .. (show_swaps and "on" or "off"))
  elseif cmd == "debugmode" then
    debug_mode = not debug_mode
    say("debug mode " .. (debug_mode and "on" or "off"))
  else
    for _, f in ipairs(unhandled) do
      if f(cmd, table.unpack(args, 2)) then return end
    end
    say("command not found: " .. cmd)
  end
end

-- Windower console commands from files: input, wait, gs, bind / unbind, cancel; ';' chains them.
console = function(text)
  local parts = {}
  for part in tostring(text):gmatch("[^;]+") do parts[#parts + 1] = part end
  local function go(i)
    for k = i, #parts do
      local c = parts[k]:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^@", "")
      local t = compat.tokens(c)
      local w = (t[1] or ""):lower()
      if w == "wait" then
        timer.after(tonumber(t[2]) or 0, function() go(k + 1) end)
        return
      elseif w == "input" then
        commands.run((c:gsub("^%S+%s*", "")))
      elseif w == "gs" or w == "gearswap" then
        M.command({ table.unpack(t, 2) })
      elseif w == "bind" and t[2] then
        local rest = c:gsub("^%S+%s+%S+%s*", "")
        pcall(binds.set, t[2], function() console(rest) end)
      elseif w == "unbind" and t[2] then
        pcall(binds.unset, t[2])
      elseif w:sub(1, 1) == "/" then
        commands.run(c)
      elseif w ~= "" then
        log.debug("gearswap console: " .. c)
      end
    end
  end
  go(1)
end

return M
