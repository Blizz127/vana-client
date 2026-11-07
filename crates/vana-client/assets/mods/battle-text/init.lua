-- Battle messages through filters.battle: others' start lines dropped (Ready Lines), names coloured by who they are
-- (Battle Names), a message read back into one short line (Battle Text): "Lnxcsfix uses Fast Blade. / The Wild Rabbit
-- takes 123 points of damage." reads "Lnxcsfix [Fast Blade] → Wild Rabbit: 123". A message whose lines match none of
-- the forms below stays as the game prints it.

-- Start categories: weapon skill, spell, item, ranged.
local START = { [7] = true, [8] = true, [9] = true, [12] = true }

-- The log's in-line colour codes a name takes.
local ME, PARTY, ALLIANCE, OUR_CLAIM, OTHER_CLAIM = 7, 6, 3, 8, 5

-- Our party's and the alliance's members by id; our party's indexes.
local function roster()
  local mine, all, indexes = {}, {}, {}
  for _, m in ipairs(game.party()) do
    all[m.id] = true
    if m.party == 0 then
      mine[m.id] = true
      indexes[m.index] = true
    end
  end
  return mine, all, indexes
end

local function colour_of(id, me, pet, mine, all)
  local e = game.entity(id)
  if id == me or (pet and e and e.index == pet) then return ME end
  if mine[id] then return PARTY end
  if all[id] then return ALLIANCE end
  if e and e.kind == "mob" and e.claim ~= 0 then
    return (e.claim == me or mine[e.claim]) and OUR_CLAIM or OTHER_CLAIM
  end
  return 0
end

-- Us, our party, or a pet of one of us.
local function ours(id, me, my_index, mine, indexes)
  if id == me or mine[id] then return true end
  local e = game.entity(id)
  local master = e and e.master or 0
  return master ~= 0 and (master == my_index or indexes[master] == true)
end

local function after(s, prefix)
  if s:sub(1, #prefix) == prefix then return s:sub(#prefix + 1) end
end

local function before(s, suffix)
  if #s >= #suffix and s:sub(#s - #suffix + 1) == suffix then return s:sub(1, #s - #suffix) end
end

local function between(s, prefix, suffix)
  local m = after(s, prefix)
  return m and before(m, suffix)
end

local function trim(s)
  return (s:match("^%s*(.-)%s*$"))
end

-- How a name prints in the game's text, longest first ("The Wild Rabbit", "the Wild Rabbit", "Wild Rabbit").
local function forms(w)
  if w.pc or w.named then return { w.name } end
  return { "The " .. w.name, "the " .. w.name, w.name }
end

-- `line` with the first printed form of `w` as `token`.
local function mark(line, w, token)
  if not w then return line end
  for _, f in ipairs(forms(w)) do
    local i, j = line:find(f, 1, true)
    if i then return line:sub(1, i - 1) .. token .. line:sub(j + 1) end
  end
  return line
end

local function cap(s)
  return s:sub(1, 1):upper() .. s:sub(2)
end

-- Lines about the target: prefix, suffix, the short form of what is between, and whether to capitalise it.
local RESULTS = {
  { "{T} takes ", " points of damage.", "%s" },
  { "{T} takes ", " point of damage.", "%s" },
  { "{T} recovers ", " HP.", "+%s HP" },
  { "{T} recovers ", " MP.", "+%s MP" },
  { "{T} gains the effect of ", ".", "+%s", true },
  { "{T} receives the effect of ", ".", "+%s", true },
  { "{T}'s ", " effect wears off.", "-%s", true },
  { "", " HP drained from {T}.", "%s HP drained" },
  { "", " MP drained from {T}.", "%s MP drained" },
}
local WHOLE = {
  ["{T} resists the spell."] = "resisted",
  ["{T} resists the effects of the spell!"] = "resisted",
  ["No effect on {T}."] = "no effect",
  ["{T} evades."] = "evaded",
}

-- What a line about the target says, short ("123", "+45 HP", "+Protect", "resisted").
local function result(line)
  local rest = after(line, "Magic Burst! ")
  local burst = rest ~= nil
  line = rest or line
  local r = WHOLE[line]
  if not r then
    for _, f in ipairs(RESULTS) do
      local x = between(line, f[1], f[2])
      if x then
        r = f[3]:format(f[4] and cap(x) or x)
        break
      end
    end
  end
  if r and burst then r = r .. " (Magic Burst)" end
  return r
end

-- The message's lines (codes kept) as one short line, or nil to print them as they are.
local function shorten(lines, actor, target)
  local plain = {}
  for _, l in ipairs(lines) do
    local p = trim(text.strip(l))
    if p ~= "" then plain[#plain + 1] = p end
  end
  if #plain == 0 then return nil end
  local a = actor and text.colour(actor.name, actor.colour)
  local t = target and text.colour(target.name, target.colour)
  -- The actor is named first in the opening line, the target after it.
  local first = mark(mark(plain[1], actor, "{A}"), target, "{T}")
  local rest = {}
  for i = 2, #plain do rest[#rest + 1] = mark(mark(plain[i], target, "{T}"), actor, "{A}") end
  local function short(act, r)
    if not (a and t) then return nil end
    if act then return ("%s [%s] → %s: %s"):format(a, act, t, r) end
    return ("%s → %s: %s"):format(a, t, r)
  end
  if #rest == 0 then
    local n = between(first, "{A} hits {T} for ", " points of damage.") or between(first, "{A} hits {T} for ", " point of damage.")
    if n then return short(nil, n) end
    if first == "{A} misses {T}." then return short(nil, "miss") end
    local x = between(first, "{A} uses ", ", but misses {T}.")
    if x then return short(x, "miss") end
    -- "Lnxtest uses Provoke on the Snipper." -> "Lnxtest [Provoke] → Snipper".
    x = between(first, "{A} uses ", " on {T}.")
    if x and not x:find("{", 1, true) then
      return a and t and ("%s [%s] → %s"):format(a, x, t)
    end
    -- A line about the target alone (an area action's later targets, a wear-off).
    local r = result(first)
    return r and t and ("%s: %s"):format(t, r)
  elseif #rest == 1 then
    local r = result(rest[1])
    if not r then return nil end
    if first == "{A} scores a critical hit!" then return short(nil, r .. "!") end
    local sc = between(first, "Skillchain: ", ".")
    if sc then return t and ("[Skillchain: %s] → %s: %s"):format(sc, t, r) end
    local act = between(first, "{A} uses ", ".") or between(first, "{A} casts ", ".")
    if not act then return nil end
    act = before(act, " on {T}") or act
    if act:find("{", 1, true) then return nil end
    return short(act, r)
  end
  return nil
end

local function on_message(m)
  local ready, short, names = settings.get("ready"), settings.get("short"), settings.get("names")
  local me = game.player()
  local mine, all, indexes = roster()
  if ready and START[m.category] and m.actor and m.actor.id ~= me.id then
    local e = game.entity(m.actor.id)
    if ours(m.actor.id, me.id, me.index, mine, indexes) or not (e and e.kind == "mob") then return false end
  end
  if names then
    local pet = game.info().pet_index
    for _, w in pairs({ m.actor or false, m.target or false }) do
      if w and w.name then w.colour = colour_of(w.id, me.id, pet, mine, all) end
    end
  end
  if short then
    return shorten(m.lines, m.actor and m.actor.name and m.actor, m.target and m.target.name and m.target)
  end
end

-- Filtering only while a setting asks for it.
local filter
local function update()
  local on = settings.get("ready") or settings.get("short") or settings.get("names")
  if on and not filter then
    filter = filters.battle(on_message)
  elseif not on and filter then
    filters.off(filter)
    filter = nil
  end
end

update()
events.on("settings_changed", update)

-- For the client's tests.
return { shorten = shorten }
