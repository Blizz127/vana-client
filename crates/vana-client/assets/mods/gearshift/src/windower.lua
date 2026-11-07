-- The part of Windower's API that job files and their libraries call, over the game's state: windower.ffxi getters,
-- send_command, add_to_chat, register_event, file checks; and gearswap.res, Windower's resources tables built as they
-- are read.

local M = {}

local function job(id) return id and id ~= 0 and res.job(id) or nil end

local function mob(e)
  if not e then return nil end
  return { name = e.name, id = e.id, index = e.index, hpp = e.hpp, x = e.pos and e.pos.x, y = e.pos and e.pos.y,
    z = e.pos and e.pos.z, distance = (e.distance or 0) ^ 2, is_npc = e.kind ~= "player", claim_id = e.claim,
    status = e.status, spawn_type = e.kind == "player" and 1 or (e.kind == "npc" and 2 or 16),
    in_party = e.in_party, in_alliance = e.in_alliance, valid_target = e.targetable, target_index = e.target_index,
    tp = e.tp, mpp = e.mpp, heading = e.heading, facing = e.heading, model_size = e.hitbox }
end

local function items_of(bag)
  local t = { max = game.bag_size and game.bag_size(bag) or 80, count = 0, enabled = true }
  for _, it in ipairs(game.items(bag) or {}) do
    t[it.slot] = { id = it.id, count = it.count, status = it.locked, slot = it.slot, extdata = it.extdata or "", bazaar = 0 }
    t.count = t.count + 1
  end
  return t
end

function M.make(env, register, console)
  local ffxi = {}
  function ffxi.get_player()
    local p = game.player()
    local buffs = {}
    for _, b in ipairs(game.buffs() or {}) do buffs[#buffs + 1] = b.id end
    return { name = p.name, id = p.id, index = p.index, main_job = job(p.main_job), main_job_id = p.main_job,
      main_job_level = p.main_level, sub_job = job(p.sub_job), sub_job_id = p.sub_job, sub_job_level = p.sub_level,
      status = p.status, buffs = buffs, in_combat = p.status == 1,
      vitals = { hp = p.hp, mp = p.mp, tp = p.tp, hpp = p.hpp, mpp = p.mpp, max_hp = p.hp_max, max_mp = p.mp_max } }
  end
  function ffxi.get_items(bag, index)
    if bag == nil then
      local all = {}
      for id, name in pairs(require("src.core").BAG_NAMES) do all[name] = items_of(id) end
      return all
    end
    if type(bag) == "string" then bag = require("src.core").BAG_IDS[bag:lower()] end
    local t = items_of(bag)
    if index then return t[index] end
    return t
  end
  function ffxi.get_mob_by_target(tag) return mob(game.entity_by_tag(tag or "t")) end
  function ffxi.get_mob_by_id(id) return mob(game.entity(id)) end
  function ffxi.get_mob_by_index(index)
    for _, e in ipairs(game.entities() or {}) do if e.index == index then return mob(e) end end
  end
  function ffxi.get_mob_array()
    local t = {}
    for _, e in ipairs(game.entities() or {}) do t[e.index] = mob(e) end
    return t
  end
  function ffxi.get_info()
    local i, t = game.info(), game.time()
    return { zone = i.zone, mog_house = i.mog_house, chat_open = i.chat_open, menu_open = i.menu_open, logged_in = true,
      day = t.weekday, moon = t.moon_phase, moon_pct = t.moon, time = t.hour * 60 + t.minute, weather = game.weather(),
      language = "English", server = i.server }
  end
  -- Every recast id has its entry, 0 when ready, as Windower's tables have them (files compare them unchecked).
  function ffxi.get_ability_recasts()
    local r = game.recasts() or {}
    local t = {}
    for id = 0, 1023 do t[id] = 0 end
    for id, left in pairs(r.abilities or {}) do t[id] = left end
    return t
  end
  function ffxi.get_spell_recasts()
    local r = game.recasts() or {}
    local t = {}
    for id = 0, 1023 do t[id] = 0 end
    for id, left in pairs(r.spells or {}) do t[id] = math.floor(left * 60) end
    return t
  end
  function ffxi.get_spells()
    local t = {}
    for _, id in ipairs(game.spells() or {}) do t[id] = true end
    return t
  end
  function ffxi.get_abilities()
    local ja, ws = {}, {}
    for _, id in ipairs(game.abilities() or {}) do
      if id < 0x200 then ws[#ws + 1] = id else ja[#ja + 1] = id - 0x200 end
    end
    return { job_abilities = ja, weapon_skills = ws }
  end
  function ffxi.get_party() return {} end
  function ffxi.get_key_items() return game.key_items() or {} end
  function ffxi.cancel_buff(id) pcall(actions.cancel, id) end
  local w = setmetatable({
    ffxi = ffxi,
    send_command = console,
    add_to_chat = function(c, text) chat.add(tostring(text == nil and c or text)) end,
    register_event = function(name, f) return register(name, f) end,
    raw_register_event = function(name, f) return register(name, f) end,
    unregister_event = function() end,
    addon_path = "gearswap/",
    windower_path = "",
    file_exists = function(p) return fs.exists(p) end,
    dir_exists = function(p) return fs.exists(p) end,
    to_shift_jis = function(s) return text.to_shift_jis(s) end,
    from_shift_jis = function(s) return text.from_shift_jis(s) end,
    convert_auto_trans = function(s) return text.plain(s) end,
    text = setmetatable({}, { __index = function() return function() end end }),
    prim = setmetatable({}, { __index = function() return function() end end }),
  }, { __index = function() return nil end })
  return w
end

-- Windower's resources, as files read them: res.spells[id].en and so on, each line made when first read.
function M.res()
  local function lazy(make)
    return setmetatable({}, { __index = function(t, id)
      if type(id) ~= "number" then return nil end
      local v = make(id)
      if v then rawset(t, id, v) end
      return v
    end })
  end
  local function named(n, extra)
    if not n then return nil end
    local t = { en = n, english = n, ja = n, name = n }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
  end
  return {
    spells = lazy(function(id) local s = res.spell(id) return s and named(s.name, { id = id, recast_id = id, mp_cost = s.mp, cast_time = s.cast_time, recast = s.recast, skill = s.skill, element = s.element, type = s.kind }) end),
    job_abilities = lazy(function(id) local a = res.ability(id + 0x200) return a and named(a.name, { id = id, recast_id = a.recast_id }) end),
    weapon_skills = lazy(function(id) local a = res.ability(id) return a and named(a.name, { id = id }) end),
    items = lazy(function(id) local i = res.item(id) return i and named(i.name, { id = id, enl = i.log_name, english_log = i.log_name }) end),
    buffs = lazy(function(id) local n = res.status(id) return n and named(n, { id = id }) end),
    zones = lazy(function(id) local n = res.zone(id) return n and named(n, { id = id }) end),
    jobs = lazy(function(id) local n = res.job(id) return n and named(n, { id = id, ens = n }) end),
    elements = lazy(function(id) local n = res.element(id) return n and named(n, { id = id }) end),
    weather = lazy(function(id) local n = res.weather(id) return n and named(n, { id = id, element = res.weather_element(id) }) end),
    days = lazy(function(id) local n = res.day(id) return n and named(n, { id = id }) end),
    skills = lazy(function(id) local n = res.skill(id) return n and named(n, { id = id }) end),
  }
end

return M
