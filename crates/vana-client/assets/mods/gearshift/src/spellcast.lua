-- Spellcast's XML files (Windower's gear-swap add-on before GearSwap), run as Spellcast ran them: an action's command
-- line is read against the rules once, building the precast, midcast and aftercast sets; the precast set goes on, the
-- line goes to the game, the midcast set 0.6 s later and the aftercast set when the cast should be over (its base time
-- + 1.5 s). A status change reads the rules again as the "autoset" spell for the idle, engaged or resting set.

local core = require("src.core")
local compat = require("src.compat")
local names = require("src.names")
local xml = require("src.xml")
local regex = require("src.regex")
local LAC = names.LAC

local M = {}
M.file = nil

local doc          -- {root, rules, sets, groups, cfg, dir}
local group        -- the current group's node
local uvars = {}   -- lower name -> {name = as written, value}
local disabled = {}
local gen = 0      -- the newest cast: older timers do nothing
local pass = {}    -- lines we send ourselves, let through once
local debug, show = false, false
local warned = {}

local function say(text) chat.add("Spellcast: " .. text) end
local function warn(text)
  if not warned[text] then
    warned[text] = true
    say(text)
  end
end

-- An element's name without a namespace prefix, lowered.
local function lname(n) return (n.name:lower():gsub("^.-:", "")) end
local function attr(n, k) return n.attr[k] end

-- Spellcast's yes: t*, y*, on, 1.
local function truthy(v)
  if v == nil then return false end
  local l = tostring(v):lower()
  return l:sub(1, 1) == "t" or l:sub(1, 1) == "y" or l == "on" or l == "1"
end

local function trim(s) return (tostring(s or ""):match("^%s*(.-)%s*$")) end

-- ---- Slots ----

local SLOT = { main = 0, sub = 1, range = 2, ammo = 3, head = 4, body = 5, hands = 6, legs = 7, feet = 8, neck = 9,
  waist = 10, lear = 11, rear = 12, lring = 13, rring = 14, back = 15 }
local SLOT_NAME = {}
for k, v in pairs(SLOT) do SLOT_NAME[v] = k end
-- The names `sc disable` / `enable` and those actions take, as Spellcast's table has them.
local SLOT_ALIASES = { { 1, "sub|off*|shield|grip" }, { 2, "range*|bow|gun" }, { 3, "ammo|throw*" }, { 9, "neck*" },
  { 11, "l*ear*|ear*1" }, { 12, "r*ear*|ear*2" }, { 13, "lring|l.ring|ring*1" }, { 14, "rring|r.ring|ring*2" },
  { 15, "back|cape" }, { 10, "waist|belt" }, { 7, "legs|pants" }, { 8, "feet|boot*|foot" }, { 4, "head|hat" },
  { 6, "hands|gloves" }, { 0, "main" }, { 5, "body" } }

-- ---- Matching: wildcards (* and ?), | alternatives, (regex)...(/regex) ----

local function wild(t, p, i, j)
  while j <= #p do
    local c = p:sub(j, j)
    if c == "*" then
      for k = #t + 1, i, -1 do
        if wild(t, p, k, j + 1) then return true end
      end
      return false
    end
    if i > #t then return false end
    if c ~= "?" and c ~= t:sub(i, i) then return false end
    i, j = i + 1, j + 1
  end
  return i > #t
end

-- The alternatives of a value: split on | outside (regex)...(/regex).
local function alternatives(v)
  local out, i, cur = {}, 1, ""
  while i <= #v do
    local open = v:sub(i):lower():match("^%(regex[%w%-]*%)")
    if open then
      local close = v:lower():find("(/regex)", i, true)
      local e = close and close + 7 or #v
      cur = cur .. v:sub(i, e)
      i = e + 1
    elseif v:sub(i, i) == "|" then
      out[#out + 1] = cur
      cur = ""
      i = i + 1
    else
      cur = cur .. v:sub(i, i)
      i = i + 1
    end
  end
  out[#out + 1] = cur
  return out
end

local function match(pattern, subject)
  subject = tostring(subject or "")
  local ls = subject:lower()
  for _, a in ipairs(alternatives(pattern)) do
    local la = a:lower()
    local opts = la:match("^%((regex[%w%-]*)%)")
    if opts then
      local close = la:find("(/regex)", #opts + 3, true)
      local body = a:sub(#opts + 3, (close or #a + 1) - 1)
      local ok, hit = pcall(regex.test, body, subject, opts:find("case", 1, true) ~= nil)
      if not ok then warn("regex " .. body .. ": " .. tostring(hit)) elseif hit then return true end
    elseif wild(ls, a:lower(), 1, 1) then
      return true
    end
  end
  return false
end

local function slots_of(list)
  if not list or trim(list) == "" then
    local all = {}
    for s = 0, 15 do all[#all + 1] = s end
    return all
  end
  local out = {}
  for _, w in ipairs(alternatives(list)) do
    for _, a in ipairs(SLOT_ALIASES) do
      if match(a[2], trim(w)) then out[#out + 1] = a[1] break end
    end
  end
  return out
end

-- ---- Game data in Spellcast's words ----

local ELEMENT = { [0] = "Fire", "Ice", "Wind", "Earth", "Thunder", "Water", "Light", "Dark", [15] = "None" }
local SKILL = { [32] = "DivineMagic", [33] = "HealingMagic", [34] = "EnhancingMagic", [35] = "EnfeeblingMagic",
  [36] = "ElementalMagic", [37] = "DarkMagic", [38] = "SummoningMagic", [39] = "Ninjutsu", [40] = "Singing",
  [43] = "BlueMagic", [44] = "Geomancy" }
local SPELL_TYPE = { "WhiteMagic", "BlackMagic", "SummonerPact", "Ninjutsu", "BardSong", "BlueMagic", "Geomancy", "Trust" }
local ABILITY_TYPE = { [173] = "BloodPactRage", [174] = "BloodPactWard", [193] = "CorsairRoll", [195] = "CorsairShot" }
local TARGET_WORDS = { "Self", "Player", "Party", "Ally", "NPC", "Enemy" }
local TRIGGER_WORDS = { me = true, t = true, st = true, stnpc = true, stpc = true, stpt = true, stal = true, lastst = true,
  r = true, pet = true, bt = true, ht = true, ft = true, scan = true }

local function me() return game.player() or {} end
local function job(id) return res.job(id or 0) or "NON" end
local function pet()
  local e = game.entity_by_tag("pet")
  if e and (e.hpp or 0) > 0 then return e end
end

local function valid_targets(bits)
  local t = {}
  for i, w in ipairs(TARGET_WORDS) do
    if (bits or 0) & (1 << (i - 1)) ~= 0 then t[#t + 1] = w end
  end
  return table.concat(t, ", ")
end

local function etype(e)
  if not e then return "NONE" end
  if e.me then return "SELF" end
  if e.kind == "mob" then return "MONSTER" end
  if e.kind == "npc" then return "NPC" end
  return "PLAYER"
end

local function weather_id()
  local w = game.weather() or 0
  for _, b in ipairs(game.buffs() or {}) do
    local s = names.STORMS[b.id]
    if s then
      -- A storm over the same single weather is its double.
      if s % 2 == 0 and w == s then return s + 1 end
      return s
    end
  end
  return w
end

local function worn_name(slot)
  local w = core.worn()[slot]
  if not w then return "empty" end
  local r = core.record(w.id)
  return r and r.name or "empty"
end

local function num(v) return tostring(math.tointeger(v) or v) end

-- Predefined variables (and the conditions of the same names), by lowered name; `c` is the pass's context.
local PRE = {
  group = function(c) return group and alternatives(attr(group, "name") or "")[1] or "" end,
  spell = function(c) return c.spell and c.spell.name or "" end,
  spellelement = function(c) return c.spell and c.spell.element or "None" end,
  type = function(c) return c.spell and c.spell.type or "" end,
  skill = function(c) return c.spell and c.spell.skill or "" end,
  validtarget = function(c) return c.spell and c.spell.valid or "" end,
  mpcost = function(c) return num(c.spell and c.spell.mp or 0) end,
  tpcost = function(c) return num(c.spell and c.spell.tp or 0) end,
  recast = function(c) return num(c.spell and c.spell.recast or 0) end,
  casttime = function(c) return num(c.spell and c.spell.cast or 0) end,
  commandprefix = function(c) return c.prefix or (c.spell and c.spell.prefix) or "" end,
  mpaftercast = function(c) return num((me().mp or 0) - (c.spell and c.spell.mp or 0)) end,
  mppaftercast = function(c)
    local max = me().mp_max or 0
    return num(max > 0 and ((me().mp or 0) - (c.spell and c.spell.mp or 0)) * 100 // max or 0)
  end,
  tpaftercast = function(c) return num((me().tp or 0) - (c.spell and c.spell.tp or 0)) end,
  mp = function() return num(me().mp or 0) end,
  hp = function() return num(me().hp or 0) end,
  tp = function() return num(me().tp or 0) end,
  mpp = function() return num(me().mpp or 0) end,
  hpp = function() return num(me().hpp or 0) end,
  mpmax = function() return num(me().mp_max or 0) end,
  hpmax = function() return num(me().hp_max or 0) end,
  status = function()
    local s = me().status or 0
    return ({ [0] = "Idle", "Engaged", "Dead", "Dead", "Zoning", [33] = "Resting" })[s] or "Other"
  end,
  job = function() return job(me().main_job) .. "/" .. job(me().sub_job) end,
  mainjob = function() return job(me().main_job) end,
  subjob = function() return job(me().sub_job) end,
  fulljob = function() return names.JOBS_FULL[me().main_job or 0] or "" end,
  lvl = function() return (me().main_level or 0) .. "/" .. (me().sub_level or 0) end,
  mainjoblvl = function() return num(me().main_level or 0) end,
  subjoblvl = function() return num(me().sub_level or 0) end,
  playername = function() return me().name or "" end,
  isincombat = function() return me().status == 1 and "1" or "0" end,
  isinally = function()
    for _, m in ipairs(game.party() or {}) do if m.slot >= 6 then return "1" end end
    return "0"
  end,
  partycount = function() return num(math.max(#(game.party() or {}), 1)) end,
  area = function() return res.zone(me().zone or 0) or "" end,
  time = function() local t = game.time() return string.format("%02d.%02d", t.hour, t.minute) end,
  moon = function() return res.moon(game.time().moon_phase) or "" end,
  moonpct = function() return num(game.time().moon or 0) end,
  day = function() return LAC.DAYS[game.time().weekday] or "" end,
  dayelement = function() return LAC.DAY_ELEMENTS[game.time().weekday] or "" end,
  weather = function() return LAC.WEATHER[weather_id()] or "Clear" end,
  weatherelement = function() return LAC.WEATHER_ELEMENT[weather_id()] or "None" end,
  spelltargetname = function(c) return c.target and c.target.name or "" end,
  spelltargetraw = function(c) return c.raw or "" end,
  spelltargethpp = function(c) return num(c.target and c.target.hpp or 0) end,
  spelltargettype = function(c) return etype(c.target) end,
  spelltargetdistance = function(c) return num(c.target and c.target.distance or 0) end,
  spelltargetisallymember = function(c)
    local e = c.target
    return (e and (e.me or e.in_party or e.in_alliance)) and "1" or "0"
  end,
  spelltargetid = function(c) return num(c.target and c.target.id or 0) end,
  target = function() local t = game.target() return t and t.name or "" end,
  targethpp = function() local t = game.target() return num(t and t.hpp or 0) end,
  targettype = function() return etype(game.target()) end,
  targetdistance = function() local t = game.target() return num(t and t.distance or 0) end,
  targetisallymember = function()
    local e = game.target()
    return (e and (e.me or e.in_party or e.in_alliance)) and "1" or "0"
  end,
  targetid = function() local t = game.target() return num(t and t.id or 0) end,
  petisvalid = function() return pet() and "TRUE" or "FALSE" end,
  petname = function() local p = pet() return p and p.name or "" end,
  petelement = function() return "" end,
  pettp = function() local p = pet() return num(p and p.tp or 0) end,
  pethpp = function() local p = pet() return num(p and p.hpp or 0) end,
  petmpp = function() local p = pet() return num(p and p.mpp or 0) end,
  fellowisvalid = function() return "FALSE" end,
  fellowid = function() return "0" end,
  fellowname = function() return "" end,
  fellowhpp = function() return "0" end,
  geardelay = function(c) return num(c.delay and c.delay.gear or 0) end,
  precastdelay = function(c) return num(c.delay and c.delay.cast or 0) end,
  midcastdelay = function(c) return num(c.delay and c.delay.mid or 0.6) end,
  aftercastdelay = function(c) return num(c.delay and c.delay.after or 0) end,
}
-- Other spellings the files and the plugin itself use.
local SAME = { espell = "spell", fspell = "spell", gspell = "spell", jspell = "spell", element = "spellelement",
  castime = "casttime", maxmp = "mpmax", maxhp = "hpmax", mlvl = "mainjoblvl", slvl = "subjoblvl", zone = "area",
  spelltarget = "spelltargetname", pettpreal = "pettp" }
for k, v in pairs(SAME) do PRE[k] = PRE[v] end
for s = 0, 15 do
  PRE["equip" .. SLOT_NAME[s]] = function() return worn_name(s) end
end
local PRE_NAMES = {}
for k in pairs(PRE) do PRE_NAMES[#PRE_NAMES + 1] = k end
-- Longest first: %MoonPCT is not %Moon + PCT.
table.sort(PRE_NAMES, function(a, b) return #a > #b end)

-- ---- Variables ----

-- The user variable named by the start of `rest`: the shortest defined name that prefixes it, as Spellcast reads them.
local function uvar_at(rest)
  local lr, best = rest:lower(), nil
  for k in pairs(uvars) do
    if lr:sub(1, #k) == k and (not best or #k < #best or (#k == #best and k < best)) then best = k end
  end
  return best
end

local function last_before(s, ch, limit)
  for i = math.min(limit, #s), 1, -1 do
    if s:sub(i, i) == ch then return i end
  end
end

-- % then $, each right to left; \% and \$ stay literal.
local function expand(s, c)
  s = tostring(s or "")
  if not s:find("[%%%$]") then return s end
  c = c or {}
  s = s:gsub("\\%%", "\1"):gsub("\\%$", "\2")
  local limit = #s
  for _ = 1, 256 do
    local p = last_before(s, "%", limit)
    if not p then break end
    local rest, name = s:sub(p + 1):lower(), nil
    for _, n in ipairs(PRE_NAMES) do
      if rest:sub(1, #n) == n then name = n break end
    end
    if name then
      local v = tostring(PRE[name](c))
      s = s:sub(1, p - 1) .. v .. s:sub(p + 1 + #name)
    end
    limit = p - 1
  end
  limit = #s
  for _ = 1, 256 do
    local p = last_before(s, "$", limit)
    if not p then break end
    local name = uvar_at(s:sub(p + 1))
    if name then
      local v = uvars[name].value
      s = s:sub(1, p - 1) .. v .. s:sub(p + 1 + #name)
      limit = p - 1 + #v
    else
      limit = p - 1
    end
  end
  return (s:gsub("\1", "%%"):gsub("\2", "$"))
end

-- ---- Advanced expressions ----

local function truth(v)
  if v.k == "b" then return v.v end
  if v.k == "n" then return v.v ~= 0 end
  local l = tostring(v.v):lower()
  return l ~= "" and l ~= "false" and l ~= "0"
end
local function tonum(v)
  if v.k == "n" then return v.v end
  if v.k == "b" then return v.v and 1 or 0 end
  return tonumber((tostring(v.v):match("^%s*([%+%-]?%d*%.?%d+)"))) or 0
end
local function tostr(v)
  if v.k == "b" then return v.v and "true" or "false" end
  if v.k == "n" then return num(v.v) end
  return v.v
end

local function buff_active(list)
  for _, b in ipairs(game.buffs() or {}) do
    local n = res.status(b.id)
    if n and match(list, n) then return true end
  end
  return false
end

local FUNCS = {
  regex = function(a) local ok, r = pcall(regex.test, tostr(a[2] or { k = "s", v = "" }), tostr(a[1] or { k = "s", v = "" })) return ok and r end,
  strmatch = function(a) return match(tostr(a[1] or { k = "s", v = "" }), tostr(a[2] or { k = "s", v = "" })) end,
  isarea = function(a) return match(tostr(a[1] or { k = "s", v = "" }), PRE.area()) end,
  buffactive = function(a) return buff_active(tostr(a[1] or { k = "s", v = "" })) end,
}

local function tokens(s)
  local out, i = {}, 1
  while i <= #s do
    local c = s:sub(i, i)
    local low = s:sub(i):lower()
    if c:match("%s") then
      i = i + 1
    elseif low:match("^%(regex[%w%-]*%)") then
      local open = low:match("^%(regex[%w%-]*%)")
      local close = s:lower():find("(/regex)", i + #open, true)
      local body = s:sub(i + #open, (close or #s + 1) - 1)
      local subj, pat = body:match("^(.-)=(.*)$")
      local ok, r = pcall(regex.test, pat or "", subj or body, open:find("case", 1, true) ~= nil)
      if not pat then warn("Missing = of a (regex)") end
      out[#out + 1] = { t = "v", v = { k = "b", v = pat ~= nil and ok and r } }
      i = (close or #s) + 8
    elseif low:match("^%(buffactive%)") then
      local close = s:lower():find("(/buffactive)", i, true)
      local body = s:sub(i + 12, (close or #s + 1) - 1)
      out[#out + 1] = { t = "v", v = { k = "b", v = buff_active(body) } }
      i = (close or #s) + 13
    elseif low:match("^%((bool)%)") or low:match("^%((int)%)") or low:match("^%((float)%)") or low:match("^%((string)%)") then
      local w = low:match("^%((%a+)%)")
      out[#out + 1] = { t = "cast", v = w }
      i = i + #w + 2
    elseif c == '"' then
      local j = s:find('"', i + 1, true) or #s + 1
      out[#out + 1] = { t = "v", v = { k = "s", v = s:sub(i + 1, j - 1) } }
      i = j + 1
    elseif c:match("%d") or (c == "." and s:sub(i + 1, i + 1):match("%d")) then
      local n = s:match("^%d*%.?%d+", i)
      out[#out + 1] = { t = "v", v = { k = "n", v = tonumber(n), float = n:find(".", 1, true) ~= nil } }
      i = i + #n
    else
      local op = s:sub(i, i + 1)
      if op == "&&" or op == "||" or op == "==" or op == "!=" or op == "<=" or op == ">=" then
        out[#out + 1] = { t = "op", v = op }
        i = i + 2
      elseif ("<>=!+-*/(),"):find(c, 1, true) then
        out[#out + 1] = { t = "op", v = c }
        i = i + 1
      else
        local w = s:match("^[^%s<>=!%+%-%*/%(%),\"]+", i)
        local lw = w:lower()
        if lw == "and" then
          out[#out + 1] = { t = "op", v = "&&" }
        elseif lw == "or" then
          out[#out + 1] = { t = "op", v = "||" }
        elseif FUNCS[lw] and s:sub(i + #w):match("^%s*%(") then
          out[#out + 1] = { t = "fn", v = lw }
        else
          out[#out + 1] = { t = "v", v = { k = "s", v = w } }
        end
        i = i + #w
      end
    end
  end
  return out
end

local function evaluate(s)
  local tk, pos = tokens(s), 1
  local function peek() return tk[pos] end
  local function isop(v) local t = tk[pos] return t and t.t == "op" and t.v == v end
  local orx

  local function primary()
    local t = tk[pos]
    if not t then error("expression ends early", 0) end
    pos = pos + 1
    if t.t == "v" then return t.v end
    if t.t == "fn" then
      if not isop("(") then error("( expected after " .. t.v, 0) end
      pos = pos + 1
      local a = {}
      if not isop(")") then
        a[1] = orx()
        while isop(",") do
          pos = pos + 1
          a[#a + 1] = orx()
        end
      end
      if not isop(")") then error(") expected", 0) end
      pos = pos + 1
      return { k = "b", v = FUNCS[t.v](a) and true or false }
    end
    if t.t == "op" and t.v == "(" then
      local v = orx()
      if not isop(")") then error(") expected", 0) end
      pos = pos + 1
      return v
    end
    error("unexpected " .. tostring(t.v), 0)
  end

  local function unary()
    local t = peek()
    if t and t.t == "op" and t.v == "!" then
      pos = pos + 1
      return { k = "b", v = not truth(unary()) }
    end
    if t and t.t == "op" and t.v == "-" then
      pos = pos + 1
      local v = unary()
      return { k = "n", v = -tonum(v), float = v.float }
    end
    if t and t.t == "cast" then
      pos = pos + 1
      local v = unary()
      if t.v == "bool" then return { k = "b", v = truth(v) } end
      if t.v == "int" then
        local n = tonum(v)
        return { k = "n", v = n < 0 and math.ceil(n) or math.floor(n) }
      end
      if t.v == "float" then return { k = "n", v = tonum(v), float = true } end
      return { k = "s", v = tostr(v) }
    end
    return primary()
  end

  local function mul()
    local a = unary()
    while isop("*") or isop("/") do
      local op = tk[pos].v
      pos = pos + 1
      local b = unary()
      local float = a.float or b.float
      local x, y = tonum(a), tonum(b)
      local r
      if op == "*" then
        r = x * y
      elseif y == 0 then
        r = 0
      elseif float then
        r = x / y
      else
        r = x / y
        r = r < 0 and math.ceil(r) or math.floor(r)
      end
      a = { k = "n", v = r, float = float }
    end
    return a
  end

  local function add()
    local a = mul()
    while isop("+") or isop("-") do
      local op = tk[pos].v
      pos = pos + 1
      local b = mul()
      a = { k = "n", v = op == "+" and tonum(a) + tonum(b) or tonum(a) - tonum(b), float = a.float or b.float }
    end
    return a
  end

  local function cmp()
    local a = add()
    local t = peek()
    while t and t.t == "op" and (t.v == "<" or t.v == ">" or t.v == "<=" or t.v == ">=" or t.v == "=" or t.v == "==" or t.v == "!=") do
      pos = pos + 1
      local b = add()
      local r
      if a.k == "n" and b.k == "n" then
        local x, y = a.v, b.v
        r = ({ ["<"] = x < y, [">"] = x > y, ["<="] = x <= y, [">="] = x >= y, ["="] = x == y, ["=="] = x == y, ["!="] = x ~= y })[t.v]
      else
        local x, y = tostr(a):lower(), tostr(b):lower()
        r = ({ ["<"] = x < y, [">"] = x > y, ["<="] = x <= y, [">="] = x >= y, ["="] = x == y, ["=="] = x == y, ["!="] = x ~= y })[t.v]
      end
      a = { k = "b", v = r }
      t = peek()
    end
    return a
  end

  local function andx()
    local a = cmp()
    while isop("&&") do
      pos = pos + 1
      local b = cmp()
      a = { k = "b", v = truth(a) and truth(b) }
    end
    return a
  end

  orx = function()
    local a = andx()
    while isop("||") do
      pos = pos + 1
      local b = andx()
      a = { k = "b", v = truth(a) or truth(b) }
    end
    return a
  end

  local v = orx()
  if pos <= #tk then error("unexpected " .. tostring(tk[pos].v), 0) end
  return v
end

local function advanced(expr, c)
  local ok, v = pcall(evaluate, expand(expr, c))
  if not ok then
    warn("Error in Advanced: " .. expr .. " (" .. tostring(v) .. ")")
    return false
  end
  return truth(v)
end

-- A GT / LT value: a number, or an expression of one.
local function number_of(s)
  local n = tonumber(s)
  if n then return n end
  local ok, v = pcall(evaluate, s)
  return ok and tonum(v) or 0
end

-- ---- Conditions ----

local function known(name)
  if name == "advanced" or name == "buffactive" or name == "mode" then return true end
  if PRE[name] then return true end
  local b = name:match("^(.-)[gl]t$")
  return b ~= nil and PRE[b] ~= nil
end

local function condition(c, name, value)
  if name == "advanced" then return advanced(value, c) end
  if name == "buffactive" then return buff_active(expand(value, c)) end
  local want = expand(value, c)
  -- Group: any of the current group's names.
  if name == "group" then
    for _, a in ipairs(alternatives(group and attr(group, "name") or "")) do
      if match(want, a) then return true end
    end
    return false
  end
  local get = PRE[name]
  if get then return match(want, get(c)) end
  local b, op = name:match("^(.-)([gl]t)$")
  local v, w = tonumber(PRE[b](c)) or 0, number_of(want)
  if op == "gt" then return v > w end
  return v < w
end

local function test(c, n)
  local m = attr(n, "mode")
  local any = m and m:lower() == "or"
  local seen = false
  for _, a in ipairs(n.attrs) do
    local ln = a.name:lower()
    if ln ~= "mode" and not ln:find(":", 1, true) and ln ~= "xmlns" then
      local base, neg = ln, false
      if not known(ln) and ln:sub(1, 3) == "not" and known(ln:sub(4)) then base, neg = ln:sub(4), true end
      if known(base) then
        seen = true
        local r = condition(c, base, a.value)
        if neg then r = not r end
        if any and r then return true end
        if not any and not r then return false end
      else
        warn("unknown condition " .. a.name)
      end
    end
  end
  if not seen then return true end
  return not any
end

-- ---- Groups and sets ----

local function groups() return doc and doc.groups or {} end

local function find_group(name)
  for _, g in ipairs(groups()) do
    if match(attr(g, "name") or "", name) then return g end
  end
end

local function find_set(g, name, seen)
  seen = seen or {}
  if not g or seen[g] then return nil end
  seen[g] = true
  for _, s in ipairs(g.children) do
    if lname(s) == "set" and match(attr(s, "name") or "", name) then return s end
  end
  local inherit = attr(g, "inherit")
  if inherit then return find_set(find_group(inherit), name, seen) end
end

local function put_slot(target, el, c)
  local nm = lname(el)
  if nm == "" then return end
  local s = SLOT[nm]
  if not s then
    warn("<" .. el.name .. "> is not one of Spellcast's slots; ignored")
    return
  end
  local lock = attr(el, "lock") ~= nil and truthy(attr(el, "lock"))
  local cur = target[s]
  if cur and cur.lock then return end
  local text = trim(el.text)
  if text == "" then
    -- An empty slot drops a pending change; locked, it keeps what is worn.
    target[s] = lock and { lock = true } or nil
    return
  end
  target[s] = { text = expand(text, c), lock = lock }
end

local function put_set(target, name, grp, c, seen)
  local g = grp and find_group(grp) or group
  local set = find_set(g, name)
  if not set then
    warn("Did not find Set " .. name .. " in Group " .. (g and (attr(g, "name") or "?") or "?"))
    return
  end
  seen = seen or {}
  if seen[set] then return end
  seen[set] = true
  local base = attr(set, "baseset")
  if base then
    local bg = attr(set, "basegroup")
    for _, b in ipairs(alternatives(expand(base, c))) do put_set(target, trim(b), bg and expand(bg, c), c, seen) end
  end
  for _, el in ipairs(set.children) do put_slot(target, el, c) end
end

-- ---- Actions ----

local function starts(l, list)
  for _, p in ipairs(list) do
    if l:sub(1, #p) == p then return true end
  end
  return false
end

-- The pass's sets an action's `when` names.
local function phases(c, n)
  local w = attr(n, "when")
  w = w and expand(w, c) or "precast"
  local on, all = {}, false
  for item in w:gmatch("[^|]+") do
    local l = item:lower():gsub("%s", "")
    if l == "all" then
      all = true
    elseif starts(l, { "before", "pre", "start" }) then
      on.precast = true
    elseif starts(l, { "mid", "during" }) then
      on.midcast = true
    elseif starts(l, { "after", "done", "post" }) then
      on.aftercast = true
    elseif starts(l, { "auto", "as" }) then
      on.auto = true
    elseif starts(l, { "rest", "heal" }) then
      on.resting = true
    elseif starts(l, { "eng", "att" }) then
      on.engaged = true
    elseif starts(l, { "stand", "idle", "norm" }) then
      on.idle = true
    end
  end
  local out = {}
  if c.auto then
    if all or on.auto or on[c.auto] then out[1] = "auto" end
  else
    for _, ph in ipairs({ "precast", "midcast", "aftercast" }) do
      if all or on[ph] then out[#out + 1] = ph end
    end
  end
  return out
end

local console

local function queue(c, n, f)
  for _, ph in ipairs(phases(c, n)) do table.insert(c.run[ph], f) end
end

-- ---- Command lines: actions and their names ----

local ROMAN = { i = "1", ii = "2", iii = "3", iv = "4", v = "5", vi = "6", vii = "7", viii = "8", ix = "9", x = "10" }

-- A name as Spellcast compares typed names: lower case, roman numerals as digits, nothing but letters and digits.
local function key(name)
  local s = " " .. tostring(name):lower() .. " "
  s = s:gsub("(%W)([ivx]+)(%f[%W])", function(a, r) return ROMAN[r] and (a .. ROMAN[r]) or nil end)
  return (s:gsub("[^%w]", ""))
end

local TRIGGERS = {}
do
  local function add(n, skill, element) TRIGGERS[key(n)] = { name = n, skill = skill, element = element } end
  for i = 0, 99 do add("Trigger" .. i, "ControlTrigger", "trigger") end
  add("Update", "ControlTrigger", "trigger")
  add("Reset", "ControlTrigger", "trigger")
  add("Trigger", "GenericTrigger", "trigger")
  add("ClassTrigger", "GenericTrigger", "trigger")
  for _, e in ipairs({ "Fire", "Ice", "Wind", "Earth", "Thunder", "Water", "Light", "Dark" }) do add(e .. "Trigger", "ElementalTrigger", e) end
  add("AnyElementTrigger", "ElementalTrigger", "Any")
  add("AllElementTrigger", "ElementalTrigger", "All")
  add("NoneElementTrigger", "ElementalTrigger", "None")
  for _, w in ipairs({ "IdleMode", "CycleIdleMode", "RestingMode", "CycleRestingMode", "CombatMode", "CycleCombatMode",
    "CastingMode", "CycleCastingMode", "PhysicalDefense", "MagicalDefense" }) do add(w, "CombatTrigger", "trigger") end
end

local index
local function build_index()
  if index then return end
  index = {}
  local function add(k, e)
    index[k] = index[k] or {}
    table.insert(index[k], e)
  end
  for id = 1, 1023 do
    local s = res.spell(id)
    if s and s.name and s.name ~= "" then add(key(s.name), { kind = "magic", id = id }) end
  end
  for id = 0, 0x7ff do
    local a = res.ability(id)
    if a and a.name and a.name ~= "" then
      add(key(a.name), { kind = id < 0x200 and "ws" or (id < 0x400 and "ja" or "pet"), id = id })
    end
  end
end

-- The action a typed name names (`family`: the typed prefix's, preferred among same-named ones).
local function lookup(name, family)
  local k = key(name)
  if TRIGGERS[k] then return { kind = "trigger", t = TRIGGERS[k] } end
  build_index()
  local list = index[k] or (k:sub(-1) == "1" and index[k:sub(1, -2)]) or nil
  if not list then return nil end
  for _, e in ipairs(list) do
    if e.kind == family or (family == "ja" and e.kind == "pet") or (family == "pet" and e.kind == "ja") then return e end
  end
  return list[1]
end

-- The action's fields as Spellcast names them.
local function spell_of(e)
  if e.kind == "trigger" then
    return { name = e.t.name, kind = "trigger", type = "trigger", skill = e.t.skill, element = e.t.element, valid = "Self",
      mp = 0, tp = 0, recast = 0, cast = 0, prefix = "/trigger", self = true }
  elseif e.kind == "ranged" then
    return { name = "Ranged", kind = "ranged", type = "Misc", skill = "Ability", element = "None", valid = "Enemy", mp = 0,
      tp = 0, recast = 0, cast = 0, prefix = "/range" }
  elseif e.kind == "magic" then
    local r = res.spell(e.id) or {}
    local t = SPELL_TYPE[r.kind or 0] or ""
    return { name = r.name, kind = "magic", id = e.id, type = t, skill = SKILL[r.skill or 0] or "", element = ELEMENT[r.element or 15] or "None",
      valid = valid_targets(r.targets), mp = r.mp or 0, tp = 0, recast = r.recast or 0, cast = r.cast_time or 0,
      prefix = t == "Ninjutsu" and "/ninjutsu" or (t == "BardSong" and "/song" or "/magic"), self = (r.targets or 0) == 1 }
  end
  local r = res.ability(e.id) or {}
  local ws = e.kind == "ws"
  local t = ws and "WeaponSkill" or (ABILITY_TYPE[r.recast_id or -1] or (e.kind == "pet" and "PetCommand" or "JobAbility"))
  local prefix = ws and "/weaponskill" or ((e.kind == "pet" or t:find("BloodPact", 1, true)) and "/pet" or "/jobability")
  return { name = r.name, kind = e.kind, id = e.id, type = t, skill = "Ability", element = "None", valid = valid_targets(r.targets),
    mp = 0, tp = r.tp or 0, recast = r.recast or 0, cast = 0, prefix = prefix, self = (r.targets or 0) == 1 }
end

local FAMILY = { ["/ma"] = "magic", ["/magic"] = "magic", ["/so"] = "magic", ["/song"] = "magic", ["/nin"] = "magic",
  ["/ninjutsu"] = "magic", ["/ja"] = "ja", ["/jobability"] = "ja", ["/pet"] = "pet", ["/ws"] = "ws",
  ["/weaponskill"] = "ws", ["/ra"] = "ranged", ["/range"] = "ranged", ["/throw"] = "ranged", ["/shoot"] = "ranged",
  ["/trigger"] = "trigger" }
local DISABLE = { ["/ma"] = "disablema", ["/magic"] = "disablema", ["/so"] = "disableso", ["/song"] = "disableso",
  ["/nin"] = "disablenin", ["/ninjutsu"] = "disablenin", ["/ja"] = "disableja", ["/jobability"] = "disableja",
  ["/pet"] = "disablepet", ["/ws"] = "disablews", ["/weaponskill"] = "disablews", ["/ra"] = "disablera",
  ["/range"] = "disablera", ["/throw"] = "disablera", ["/shoot"] = "disablera" }
-- What the game takes for each long prefix.
local SEND = { ["/magic"] = "/ma", ["/song"] = "/ma", ["/ninjutsu"] = "/ma", ["/jobability"] = "/ja", ["/pet"] = "/pet",
  ["/weaponskill"] = "/ws", ["/range"] = "/ra" }
local LONG = { ["/ma"] = "/magic", ["/so"] = "/song", ["/nin"] = "/ninjutsu", ["/ja"] = "/jobability", ["/ws"] = "/weaponskill",
  ["/ra"] = "/range" }

local function target_word(t)
  t = trim(t)
  if t == "" then return nil end
  local l = t:lower()
  if TRIGGER_WORDS[l] or l:match("^p[0-5]$") or l:match("^a[12][0-5]$") then return "<" .. l .. ">" end
  return t
end

local function entity_named(name)
  local l = name:lower()
  for _, e in ipairs(game.entities() or {}) do
    if e.name and e.name:lower() == l then return e end
  end
end

local function target_of(raw)
  local r = (raw or ""):lower()
  if r == "<me>" then return game.entity(me().id) end
  if r == "<t>" or r:match("^<st") or r == "<lastst>" or r == "<bt>" then return game.target() end
  if r == "<pet>" then return pet() end
  local p = r:match("^<p(%d)>$")
  if p then
    for _, m in ipairs(game.party() or {}) do
      if m.slot == tonumber(p) then return game.entity(m.id) end
    end
    return nil
  end
  if r:sub(1, 1) ~= "<" and r ~= "" then return entity_named(raw) end
end

-- ---- Sending gear ----

local function send_set(set, label)
  local wants = {}
  for s, w in pairs(set) do
    if w.text and not disabled[s] then
      wants[s] = w.text:lower() == "remove" and { remove = true } or { name = w.text }
    end
  end
  if not next(wants) then return end
  local list = core.resolve(wants, { log_names = true })
  if show and #list > 0 then
    local t = {}
    for _, x in ipairs(list) do
      local r = x.id and core.record(x.id)
      t[#t + 1] = SLOT_NAME[x.slot] .. ": " .. (r and r.name or "remove")
    end
    say(label .. ": " .. table.concat(t, ", "))
  end
  core.send(core.packets(list, "auto", 8))
end

local function run_phase(c, ph)
  send_set(c.sets[ph], ph)
  for _, f in ipairs(c.run[ph]) do f() end
end

-- ---- Reading the rules ----

local walk
local var_command

local ACTIONS = {
  equip = function(c, n)
    for _, ph in ipairs(phases(c, n)) do
      local target = c.sets[ph]
      local set = attr(n, "set")
      if set then put_set(target, expand(set, c), attr(n, "setgroup") and expand(attr(n, "setgroup"), c), c) end
      for _, el in ipairs(n.children) do put_slot(target, el, c) end
    end
  end,
  command = function(c, n)
    local text = expand(trim(n.text), c)
    queue(c, n, function() console(text) end)
  end,
  addtochat = function(c, n)
    local text = expand(n.text, c)
    local colour = tonumber(attr(n, "color") or "") or 32
    queue(c, n, function() chat.add(text, math.max(0, math.min(255, colour))) end)
  end,
  castdelay = function(c, n) c.delay.cast = tonumber(expand(attr(n, "delay") or "0", c)) or 0 end,
  geardelay = function(c, n) c.delay.gear = tonumber(expand(attr(n, "delay") or "0", c)) or 0 end,
  midcastdelay = function(c, n) c.delay.mid = tonumber(expand(attr(n, "delay") or "0", c)) or 0.6 end,
  aftercastdelay = function(c, n) c.delay.after = tonumber(expand(attr(n, "delay") or "0", c)) or 0 end,
  cancelspell = function(c) c.cancel = true end,
  ["return"] = function() return true end,
  changespell = function(c, n)
    local name = expand(attr(n, "spell") or trim(n.text), c)
    local e = lookup(name, c.spell and c.spell.kind)
    if e then c.spell = spell_of(e) else warn("ChangeSpell: no spell or ability " .. name) end
  end,
  changeprefix = function(c, n)
    local p = expand(attr(n, "prefix") or attr(n, "pfx") or trim(n.text), c):lower()
    c.prefix = LONG[p] or p
  end,
  changetarget = function(c, n)
    c.raw = target_word(expand(attr(n, "target") or trim(n.text), c)) or c.raw
    c.target = target_of(c.raw)
  end,
  defaulttarget = function(c, n)
    if not c.given then
      c.raw = target_word(expand(attr(n, "target") or trim(n.text), c)) or c.raw
      c.target = target_of(c.raw)
    end
  end,
  changelock = function(c, n)
    local lock = truthy(attr(n, "lock"))
    for _, ph in ipairs(phases(c, n)) do
      for _, s in ipairs(slots_of(attr(n, "slot") and expand(attr(n, "slot"), c))) do
        local t = c.sets[ph]
        if t[s] then t[s].lock = lock elseif lock then t[s] = { lock = true } end
      end
    end
  end,
  disable = function(c, n)
    for _, s in ipairs(slots_of(attr(n, "slot") and expand(attr(n, "slot"), c))) do disabled[s] = true end
  end,
  enable = function(c, n)
    for _, s in ipairs(slots_of(attr(n, "slot") and expand(attr(n, "slot"), c))) do disabled[s] = nil end
  end,
  var = function(c, n) var_command(compat.tokens(expand(attr(n, "cmd") or trim(n.text), c)), expand(attr(n, "cmd") or trim(n.text), c)) end,
  showspellinfo = function(c)
    local s = c.spell or {}
    say(("%s: %s, %s, %s, MP %s, cast %s s, recast %s s"):format(s.name or "?", s.type or "", s.skill or "", s.element or "",
      num(s.mp or 0), num(s.cast or 0), num(s.recast or 0)))
  end,
}
ACTIONS.cmd = ACTIONS.command
ACTIONS.precastdelay = ACTIONS.castdelay

-- An action element (either spelling); true when it stops the pass.
local function act(c, n)
  local nm = lname(n)
  if nm == "action" then nm = (attr(n, "type") or ""):lower() end
  local f = ACTIONS[nm]
  if not f then
    warn("unknown action <" .. n.name .. ">")
    return false
  end
  return f(c, n) == true
end

walk = function(c, parent)
  local chain, open = false, false
  for _, n in ipairs(parent.children) do
    local nm = lname(n)
    if nm == "if" or nm == "rule" then
      open = true
      if test(c, n) then
        chain = false
        if walk(c, n) then return true end
      else
        chain = true
      end
    elseif nm == "elseif" then
      if open and chain and test(c, n) then
        chain = false
        if walk(c, n) then return true end
      end
    elseif nm == "else" then
      if open and chain then
        chain = false
        if walk(c, n) then return true end
      end
      open = false
    elseif nm ~= "" then
      open = false
      if act(c, n) then return true end
    end
  end
end

local function new_pass(spell, raw, given, auto)
  return { spell = spell, raw = raw, given = given, target = target_of(raw), auto = auto,
    sets = { precast = {}, midcast = {}, aftercast = {}, auto = {} },
    run = { precast = {}, midcast = {}, aftercast = {}, auto = {} },
    delay = { gear = (raw or ""):lower():match("^<st") and 0.1 or 0, cast = 0, mid = 0.6 } }
end

local function read_rules(c)
  local rules = doc and doc.rules
  if rules and test(c, rules) then walk(c, rules) end
end

-- ---- Console commands (command actions, /sc) ----

local function after(secs, f)
  if secs <= 0 then f() else timer.after(secs, f) end
end

-- A line we send ourselves: the typed filter lets it through once.
local function send_line(line)
  pass[line] = (pass[line] or 0) + 1
  commands.run(line)
end

-- Windower's console: `;` between commands, `wait N`, `input <line>`, and Spellcast's `sc ...`.
console = function(text)
  local delay = 0
  for part in (text .. ";"):gmatch("(.-);") do
    local p = trim(part):gsub("^@", "")
    local w, rest = p:match("^(%S+)%s*(.*)$")
    local lw = w and w:lower()
    if not lw then
      -- nothing
    elseif lw == "wait" then
      delay = delay + (tonumber(rest) or 0)
    else
      local line
      if lw == "input" then
        line = rest
      elseif lw == "sc" or lw == "spellcast" then
        line = { rest }
      else
        line = "//" .. p
      end
      after(delay, function()
        if type(line) == "table" then M.command(compat.tokens(line[1])) else commands.run(line) end
      end)
    end
  end
end

-- ---- Loading ----

local function find_file(dir, name)
  local lname_ = name:lower()
  for _, n in ipairs(fs.list(dir) or {}) do
    if n:lower() == lname_ then return dir .. n end
  end
end

function M.find()
  local p = me()
  local main, sub = res.job(p.main_job or 0), res.job(p.sub_job or 0)
  if not main then return nil end
  local list = {}
  local function add(dir, n) list[#list + 1] = { dir, n } end
  if sub then add("spellcast/" .. p.name .. "/", main .. "_" .. sub .. ".xml") end
  add("spellcast/" .. p.name .. "/", main .. ".xml")
  if sub then add("spellcast/", p.name .. "_" .. main .. "_" .. sub .. ".xml") end
  add("spellcast/", p.name .. "_" .. main .. ".xml")
  if sub then add("spellcast/", main .. "_" .. sub .. ".xml") end
  add("spellcast/", main .. ".xml")
  -- default.xml decides: without AutoLoadXML it is the file.
  local default = find_file("spellcast/", "default.xml")
  if default then
    local text = fs.read(default) or ""
    local auto = text:lower():match("autoloadxml%s*=%s*[\"']([^\"']*)")
    if not truthy(auto) then return default end
  end
  for _, x in ipairs(list) do
    local f = find_file(x[1], x[2])
    if f then return f end
  end
  return default
end

-- The nodes an XInclude xpointer names: //a[@n='v']/*, /a/b[@n='v']/* and the like.
local function select(docnode, path)
  local nodes, i = { docnode }, 1
  local function desc(n, out)
    for _, ch in ipairs(n.children) do
      if ch.name ~= "" then
        out[#out + 1] = ch
        desc(ch, out)
      end
    end
    return out
  end
  while i <= #path do
    local deep = false
    if path:sub(i, i + 1) == "//" then
      deep, i = true, i + 2
    elseif path:sub(i, i) == "/" then
      i = i + 1
    end
    local step = path:match("^[^/]+", i)
    if not step then break end
    i = i + #step
    local name, an, av = step:match("^([^%[]+)%[@([^=%s]+)%s*=%s*['\"](.-)['\"]%]$")
    name = (name or step):lower():gsub("^.-:", "")
    local out = {}
    for _, n in ipairs(nodes) do
      for _, ch in ipairs(deep and desc(n, {}) or n.children) do
        if ch.name ~= "" and (name == "*" or lname(ch) == name)
          and (not an or (ch.attr[an:lower()] or ""):lower() == av:lower()) then out[#out + 1] = ch end
      end
    end
    nodes = out
  end
  return nodes
end

local function expand_includes(n, dir, depth)
  local i = 1
  while i <= #n.children do
    local ch = n.children[i]
    if ch.name:lower():match("^[%w_]+:include$") and depth < 8 then
      local href = attr(ch, "href") or ""
      local path = href:sub(1, 1) == "/" and ("spellcast" .. href) or (dir .. href)
      local d, b = path:match("^(.-)([^/]+)$")
      local f = find_file(d, b)
      local nodes = {}
      if f then
        local ok, inc = pcall(xml.parse, fs.read(f) or "")
        if ok then
          nodes = select(inc, attr(ch, "xpointer") or "/*")
          for _, x in ipairs(nodes) do expand_includes(x, d, depth + 1) end
        else
          warn("include " .. href .. ": " .. tostring(inc))
        end
      else
        warn("include not found: " .. href)
      end
      table.remove(n.children, i)
      for k = #nodes, 1, -1 do table.insert(n.children, i, nodes[k]) end
      i = i + #nodes
    else
      if ch.name ~= "" then expand_includes(ch, dir, depth) end
      i = i + 1
    end
  end
end

local function child(n, name)
  for _, ch in ipairs(n.children) do
    if lname(ch) == name then return ch end
  end
end

local function pick_group()
  local p = me()
  for _, g in ipairs(groups()) do
    if truthy(attr(g, "default")) then return g end
  end
  local main, sub = res.job(p.main_job or 0) or "", res.job(p.sub_job or 0) or ""
  return find_group(main .. "_" .. sub) or find_group(main) or groups()[1]
end

function M.unload()
  gen = gen + 1
  doc, group, M.file = nil, nil, nil
end

function M.load(path)
  M.unload()
  warned = {}
  local ok, err = pcall(function()
    local dir = path:match("^(.-)[^/]*$")
    local d = xml.parse(fs.read(path) or "")
    local root
    for _, ch in ipairs(d.children) do
      if lname(ch) == "spellcast" then root = ch end
    end
    if not root then error("No <spellcast>?", 0) end
    expand_includes(root, dir, 0)
    local cfg = {}
    local c = child(root, "config")
    if c then
      for _, a in ipairs(c.attrs) do cfg[a.name:lower()] = a.value end
    end
    local sets = child(root, "sets")
    local gs_ = {}
    if sets then
      for _, g in ipairs(sets.children) do
        if lname(g) == "group" then gs_[#gs_ + 1] = g end
      end
      -- Sets straight under <sets>: one group of them.
      if #gs_ == 0 then gs_[1] = sets end
    end
    doc = { root = root, rules = child(root, "rules"), groups = gs_, cfg = cfg, dir = dir }
    local vars = child(root, "variables")
    if vars then
      if truthy(attr(vars, "clear")) then uvars = {} end
      for _, v in ipairs(vars.children) do
        local name = attr(v, "name")
        if lname(v) == "var" and name then
          local k = name:lower()
          if not (truthy(attr(v, "nooverwrite")) and uvars[k]) then uvars[k] = { name = name, value = v.text } end
        end
      end
    end
  end)
  if not ok then
    say("could not load " .. path .. ": " .. tostring(err))
    doc = nil
    return false
  end
  M.file = path
  group = pick_group()
  debug, show = truthy(doc.cfg.debug), truthy(doc.cfg.showgearswaps)
  say("loaded " .. path .. (group and attr(group, "name") and (", group " .. attr(group, "name")) or ""))
  return true
end

function M.loaded() return doc ~= nil end

-- The item names the file's sets hold.
function M.gear_names()
  local out, seen = {}, {}
  for _, g in ipairs(groups()) do
    for _, s in ipairs(g.children) do
      if lname(s) == "set" then
        for _, el in ipairs(s.children) do
          local t = trim(el.text)
          local l = t:lower()
          if SLOT[lname(el)] and t ~= "" and not t:find("[%%%$]") and l ~= "remove" and not seen[l] then
            seen[l] = true
            out[#out + 1] = t
          end
        end
      end
    end
  end
  table.sort(out)
  return out
end

-- ---- Casting ----

-- Reads the rules for an action line and runs its stages; returns what the typed filter returns.
local function cast(spell, raw, given)
  local c = new_pass(spell, raw, given, nil)
  read_rules(c)
  gen = gen + 1
  local my = gen
  local function later(secs, f)
    if secs <= 0 then f() return end
    timer.after(secs, function() if gen == my then f() end end)
  end
  local d = c.delay
  local final = c.spell
  -- Triggers never reach the game; a cancelled action keeps its precast stage only.
  if c.cancel or final.kind == "trigger" then
    later(d.gear, function() run_phase(c, "precast") end)
    return false
  end
  local send = SEND[c.prefix or final.prefix] or SEND[final.prefix] or "/ma"
  local line = ("%s \"%s\" %s"):format(send, final.name, c.raw or "<t>")
  if final.kind == "ranged" then line = "/ra " .. (c.raw or "<t>") end
  local send_at = d.gear + d.cast
  local base = final.cast + 1.5
  local extra = d.after or ((final.kind == "ws" or final.kind == "ja" or final.kind == "pet") and 1.5 or 0)
  later(send_at + d.mid, function() run_phase(c, "midcast") end)
  later(send_at + base + extra, function() run_phase(c, "aftercast") end)
  if send_at <= 0 then
    run_phase(c, "precast")
    return line
  end
  later(d.gear, function() run_phase(c, "precast") end)
  later(send_at, function() send_line(line) end)
  return false
end

-- A status change: the rules read as the "autoset" spell, for the idle, engaged or resting set.
local AUTO = { [0] = "idle", [1] = "engaged", [33] = "resting" }

function M.status_change(new)
  if not doc then return end
  local which = AUTO[new]
  if not which then return end
  local function go()
    local c = new_pass({ name = "autoset", kind = "autoset", type = "", skill = "", element = "None", valid = "", mp = 0, tp = 0,
      recast = 0, cast = 0, prefix = "" }, "<me>", false, which)
    read_rules(c)
    run_phase(c, "auto")
  end
  -- Engaged waits a moment, so the target is known.
  if which == "engaged" then timer.after(0.5, function() if doc then go() end end) else go() end
end

-- ---- The typed filter ----

-- A typed line: an action line read against the rules (false: we send it, or not at all; a string: the line as the
-- game should have it), /sc taken, any other line with % or $ expanded.
function M.typed(line)
  if not doc then return nil end
  if pass[line] then
    pass[line] = pass[line] > 1 and pass[line] - 1 or nil
    return nil
  end
  local t = compat.tokens(line)
  local w = (t[1] or ""):lower()
  if w == "/sc" or w == "/spellcast" then
    M.command({ table.unpack(t, 2) })
    return false
  end
  if w == "/fish" and doc.cfg.fishingset then
    local c = new_pass(nil, "<me>", false, nil)
    put_set(c.sets.precast, doc.cfg.fishingset, nil, c)
    send_set(c.sets.precast, "fishing")
    return nil
  end
  local l = line:lower()
  if w == "/item" and doc.cfg.helmset and (l:find("hatchet", 1, true) or l:find("sickle", 1, true) or l:find("pickaxe", 1, true)) then
    local c = new_pass(nil, "<me>", false, nil)
    put_set(c.sets.precast, doc.cfg.helmset, nil, c)
    send_set(c.sets.precast, "HELM")
    return nil
  end
  local family = FAMILY[w]
  if family and not (DISABLE[w] and truthy(doc.cfg[DISABLE[w]])) then
    local words = { table.unpack(t, 2) }
    local found, rest
    if family == "ranged" then
      found, rest = { kind = "ranged" }, words
    else
      for n = #words, 1, -1 do
        local e = lookup(table.concat(words, " ", 1, n), family)
        if e then
          found, rest = e, { table.unpack(words, n + 1) }
          break
        end
      end
    end
    if found then
      local spell = spell_of(found)
      local given = target_word(table.concat(rest, " "))
      local raw = given or (spell.self and "<me>" or "<t>")
      if spell.kind == "trigger" then raw = table.concat(rest, " ") end
      return cast(spell, raw, given ~= nil)
    end
  end
  if line:find("[%%%$]") then
    local e = expand(line, {})
    if e ~= line then return e end
  end
  return nil
end

-- ---- /sc ----

var_command = function(t, text)
  local sub = (t[1] or ""):lower()
  local name = t[2]
  local k = name and name:lower()
  if sub == "set" or sub == "s" then
    if not name then return end
    local rest = (text or ""):match("^%s*%S+%s+%S+%s?(.*)$") or ""
    if rest:match('^".*"$') then rest = rest:sub(2, -2) end
    uvars[k] = { name = name, value = (rest:gsub("\\%$", "$"):gsub("\\%%", "%%")) }
  elseif sub == "rem" or sub == "r" then
    if k then uvars[k] = nil end
  elseif sub == "inc" or sub == "i" or sub == "dec" or sub == "d" then
    local v = k and uvars[k]
    local n = v and math.tointeger(tonumber(v.value))
    if not n then
      say("Trying to " .. ((sub == "inc" or sub == "i") and "increment" or "decrement") .. " non-integer variable " .. tostring(name))
      return
    end
    v.value = tostring(n + ((sub == "inc" or sub == "i") and 1 or -1))
  elseif sub == "clear" or sub == "c" then
    uvars = {}
  elseif sub == "list" then
    local keys = {}
    for kk in pairs(uvars) do keys[#keys + 1] = kk end
    table.sort(keys)
    for _, kk in ipairs(keys) do say("$" .. uvars[kk].name .. ": " .. uvars[kk].value) end
  else
    say("var: set NAME VALUE, rem NAME, inc NAME, dec NAME, list, clear")
  end
end

function M.command(t)
  local cmd = (t[1] or ""):lower()
  local rest = table.concat(t, " ", 2)
  if cmd == "file" or cmd == "load" or cmd == "f" then
    local n = rest:lower():sub(-4) == ".xml" and rest or rest .. ".xml"
    local p = me()
    local f = find_file("spellcast/" .. (p.name or "") .. "/", n) or find_file("spellcast/", n)
    if f then M.load(f) else say("file not found: " .. n) end
  elseif cmd == "reload" or cmd == "rehash" or cmd == "r" then
    if M.file then M.load(M.file) end
  elseif not doc then
    say("no Spellcast file loaded")
  elseif cmd == "info" or cmd == "stats" or cmd == "i" then
    local sets = 0
    for _, g in ipairs(groups()) do
      for _, s in ipairs(g.children) do if lname(s) == "set" then sets = sets + 1 end end
    end
    local nv = 0
    for _ in pairs(uvars) do nv = nv + 1 end
    say(("%s, group %s; %d groups, %d sets, %d variables"):format(M.file, group and attr(group, "name") or "-", #groups(), sets, nv))
  elseif cmd == "group" or cmd == "setgroup" or cmd == "g" then
    local g = find_group(rest)
    if g then
      group = g
      say("group " .. (attr(g, "name") or rest))
    else
      say("Could not find group " .. rest)
    end
  elseif cmd == "set" or cmd == "equipset" or cmd == "useset" or cmd == "s" then
    local c = new_pass(nil, "<me>", false, nil)
    put_set(c.sets.precast, rest, nil, c)
    send_set(c.sets.precast, "set " .. rest)
  elseif cmd == "naked" or cmd == "getnaked" or cmd == "n" then
    local set = {}
    for s = 0, 15 do set[s] = { text = "remove" } end
    send_set(set, "naked")
  elseif cmd == "disable" or cmd == "d" or cmd == "enable" or cmd == "e" then
    for _, s in ipairs(slots_of(rest ~= "" and rest or nil)) do
      disabled[s] = (cmd == "disable" or cmd == "d") or nil
    end
  elseif cmd == "debug" then
    debug = rest == "" and not debug or truthy(rest)
    say("debug " .. (debug and "on" or "off"))
  elseif cmd == "var" or cmd == "v" then
    var_command({ table.unpack(t, 2) }, rest)
  else
    say("commands: file, reload, info, group, set, naked, disable, enable, debug, var")
  end
end

-- For tests.
M._expand, M._advanced, M._match, M._key = expand, advanced, match, key
M._uvars = function(t) if t then uvars = t end return uvars end

return M
