-- A window for the content we are in, read from its messages: Dynamis, Abyssea, Salvage, Nyzul Isle, Omen, Delve,
-- Odyssey, Sortie and reives (the content tracker add-ons). The time left follows the content's countdown, else counts
-- down from its lines. Pop lists for the Empyrean and other NMs (//pops) and the Zeni NMs (//znm). Filters cannot
-- read the game, so lines are kept for the next tick.

local Omen = require("src.omen")
local Delve = require("src.delve")
local Odyssey = require("src.odyssey")
local Sortie = require("src.sortie")
local Reive = require("src.reive")
local Pops = require("src.pops")

local pending = {}
local st = {}

local function reset()
  st = { lights = {}, risen = {}, removed = {}, tokens = 0 }
end
reset()

-- Contents known by their zone; the field zones where Delve's plasm lines open its window.
local BY_ZONE = { [292] = "Omen", [264] = "Delve", [271] = "Delve", [275] = "Sortie", [133] = "Sortie", [189] = "Sortie" }
local DELVE_FIELD = { [261] = true, [262] = true, [263] = true, [265] = true, [266] = true, [267] = true, [274] = true, [276] = true }
local MODULES = { Omen = Omen, Delve = Delve, Odyssey = Odyssey, Sortie = Sortie }

-- The content of a zone, by its name.
local function content_of(name)
  if not name then return nil end
  if name:find("^Dynamis") then return "Dynamis" end
  if name:find("^Abyssea") then return "Abyssea" end
  if name:find("Remnants$") then return "Salvage" end
  if name == "Nyzul Isle" then return "Nyzul Isle" end
end

local function set_left(n, unit)
  st.ends = os.clock() + tonumber(n) * ((unit or ""):find("^second") and 1 or 60)
end

-- What the content modules read lines with: who we are, and the time left.
local ctx = {
  set_left = set_left,
  extend = function(secs)
    if st.ends then st.ends = st.ends + secs end
  end,
}

local LIGHTS = { "Pearlescent", "Ebon", "Golden", "Silvery", "Azure", "Ruby", "Amber" }

-- Salvage's restrictions in the order of their messages; the cell that lifts each is 5365 + its place - 1.
local PATHOS = { "Main Weapon/Sub-Weapon", "Head/Neck", "Body", "Hands", "Legs/Feet", "Back/Waist", "Ranged Weapon/Ammo",
  "Earrings/Rings", "Support Job", "Job Abilities", "Spellcasting", "STR Down", "DEX Down", "VIT Down", "AGI Down",
  "INT Down", "MND Down", "CHR Down", "Max HP Down", "Max MP Down" }
local CELL = 5365

local DYNAMIS_CURRENCY = {
  { "Bronzepiece", 1452, 1 }, { "Silverpiece", 1453, 100 }, { "Goldpiece", 1454, 10000 },
  { "One Byne Bill", 1455, 1 }, { "Hundred Byne Bill", 1456, 100 }, { "Ten Thousand Byne Bill", 1457, 10000 },
  { "Whiteshell", 1449, 1 }, { "Jadeshell", 1450, 100 }, { "Stripeshell", 1451, 10000 },
}
local GRANULES = { [1545] = "Crimson", [1546] = "Azure", [1547] = "Amber", [1548] = "Alabaster", [1549] = "Obsidian" }

-- One message line: what it tells about the content.
local function read(line)
  local n, unit = line:match("You have (%d+) minutes? %(Earth time%) remaining in Dynamis")
  if n then set_left(n) return end
  n = line:match("Your stay in Dynamis has been extended by (%d+) minute")
  if n and st.ends then st.ends = st.ends + tonumber(n) * 60 return end
  n, unit = line:match("You will be expelled from Dynamis in (%d+) (%a+)")
  if n then set_left(n, unit) return end
  if line:find("The sands of the hourglass have emptied") then st.ends = os.clock() return end
  n = line:match("You have (%d+) minutes? %(Earth time%) to complete this mission")
  if n then set_left(n) return end
  n, unit = line:match("Time remaining: (%d+) (%a+)")
  if n then set_left(n, unit) return end
  n = line:match("Time limit has been reduced by (%d+) minute")
  if n and st.ends then st.ends = st.ends - tonumber(n) * 60 return end
  n, unit = line:match("Your visitant status will wear off in (%d+) (%a+)")
  if n then set_left(n, unit) return end
  -- without visitant status: the countdown to being sent out
  n, unit = line:match("^Exiting in (%d+) (%a+)")
  if n then set_left(n, unit) return end
  -- Abyssea: the light readout's pairs (it spans lines), then the rises between readouts
  local got = false
  for _, pat in ipairs({ { "Pearlescent", "Ebon" }, { "Golden", "Silvery" }, { "Azure", "Ruby", "Amber" } }) do
    local vals = { line:match(table.concat(pat, ": (%d+) / ") .. ": (%d+)") }
    if #vals == #pat then
      for i, k in ipairs(pat) do
        st.lights[k], st.risen[k] = tonumber(vals[i]), nil
      end
      got = true
    end
  end
  if got then return end
  local colour = line:match("body emits an? %a+ (%a+) light")
  if colour then
    colour = colour:sub(1, 1):upper() .. colour:sub(2)
    st.risen[colour] = true
    return
  end
  n = line:match("Obtained %d+ cruor%. %(Total: (%d+)%)")
  if n then st.cruor = tonumber(n) return end
  -- Salvage
  if line:find("You feel an incredible pressure bearing down on you") then
    st.removed = {}
    return
  end
  local what = line:match("^(.-) restriction removed%.") or line:match("^(.- Down) removed%.")
  if what then st.removed[what] = true return end
  -- Nyzul Isle
  n = line:match("Welcome to Floor (%d+)")
  if n then st.floor, st.objective, st.done = tonumber(n), nil, false return end
  local obj = line:match("^Objective: (.-)%.$")
  if obj and not obj:find("^Complete on%-site") then st.objective = obj return end
  if line:find("Floor %d+ objective complete") then st.done = true return end
  n = line:match("You obtain (%d+) tokens?!")
  if n then st.tokens = st.tokens + tonumber(n) end
end

filters.chat(function(t)
  if settings.get("on") then pending[#pending + 1] = text.strip(t) end
end)

-- The content's countdown when the game shows one, else the time its lines gave.
local function time_left()
  local c = game.countdown and game.countdown()
  if c then return c.left, c.length end
  if st.ends then return math.floor(math.max(0, st.ends - os.clock())), 3600 end
end

local function held(id)
  local n = 0
  for _, bag in ipairs({ 0, 3 }) do
    for _, it in ipairs(game.items(bag)) do
      if it.id == id then n = n + it.count end
    end
  end
  return n
end

local function left_row(out)
  local left, len = time_left()
  if not left then return end
  out[#out + 1] = { type = "gauge", style = "row", label = "Time left",
    text = ("%d:%02d"):format(left // 60, left % 60), value = math.min(1, left / math.max(1, len)) }
end

local reive = Reive.new()

local function rows(kind)
  local out = {}
  left_row(out)
  if MODULES[kind] then
    MODULES[kind].rows(st.mod, out)
  elseif kind == "Reive" then
    Reive.rows(reive, out)
  elseif kind == "Dynamis" then
    local total = 0
    for _, c in ipairs(DYNAMIS_CURRENCY) do
      local n = held(c[2])
      if n > 0 then
        out[#out + 1] = { type = "text", text = ("%s: %d"):format(c[1], n) }
        total = total + n * c[3]
      end
    end
    out[#out + 1] = { type = "text", text = ("Currency worth %d singles"):format(total), dim = true }
    local have = {}
    for _, id in ipairs(game.key_items()) do
      if GRANULES[id] then have[#have + 1] = GRANULES[id] end
    end
    out[#out + 1] = { type = "text", text = "Granules: " .. (#have > 0 and table.concat(have, ", ") or "none"), dim = #have == 0 }
  elseif kind == "Abyssea" then
    for _, k in ipairs(LIGHTS) do
      local v = st.lights[k]
      out[#out + 1] = { type = "text", text = ("%s: %s%s"):format(k, v and tostring(v) or "?", st.risen[k] and " +" or ""),
        dim = v == nil }
    end
    if st.cruor then out[#out + 1] = { type = "text", text = ("Cruor: %d"):format(st.cruor) } end
  elseif kind == "Salvage" then
    for i, name in ipairs(PATHOS) do
      if not st.removed[name] then
        local cells = held(CELL + i - 1)
        out[#out + 1] = { type = "text", text = name .. (cells > 0 and (" \u{2014} %d cell%s"):format(cells, cells > 1 and "s" or "") or ""),
          dim = cells == 0 }
      end
    end
    if #out <= 1 then out[#out + 1] = { type = "text", text = "Every restriction removed." } end
  elseif kind == "Nyzul Isle" then
    out[#out + 1] = { type = "text", text = st.floor and ("Floor %d%s"):format(st.floor, st.done and " \u{2014} cleared" or "") or "Floor ?" }
    if st.objective then out[#out + 1] = { type = "text", text = st.objective } end
    out[#out + 1] = { type = "text", text = ("Tokens this run: %d"):format(st.tokens), dim = st.tokens == 0 }
  end
  return out
end

-- Where we are, the content there, and Odyssey's run between Rabao and the Walk of Echoes.
local here_zone, here_kind
local armed, last_run

local function store()
  return (storage and storage.character) or {}
end

timer.every(1, function()
  local lines = pending
  pending = {}
  Pops.refresh()
  if not settings.get("on") then
    ui.close("content")
    return
  end
  local p = game.player()
  local zone = p and p.zone
  ctx.me = p and p.name
  if zone ~= here_zone then
    -- a new zone: its content (or none) afresh, before its first messages are read
    if here_kind == "Odyssey" and st.mod then last_run = Odyssey.finish(st.mod) end
    local entered = armed
    armed = nil
    reset()
    reive = Reive.new()
    here_zone = zone
    here_kind = BY_ZONE[zone] or content_of(zone and res.zone(zone))
    if Odyssey.ZONES[zone] and entered then here_kind = "Odyssey" end
    if MODULES[here_kind] then st.mod = MODULES[here_kind].new(entered) end
  end
  for _, l in ipairs(lines) do
    if zone == Odyssey.RABAO then armed = Odyssey.entering(l) or armed end
    if MODULES[here_kind] then
      MODULES[here_kind].read(st.mod, l, ctx)
    elseif here_kind then
      read(l)
    else
      if DELVE_FIELD[zone] then
        st.mod = st.mod or Delve.new()
        Delve.read(st.mod, l, ctx)
      end
      Reive.read(reive, l, ctx)
    end
  end
  local kind = here_kind
  if not kind and st.mod and st.mod.seen then kind = "Delve" end
  if not kind and Reive.active(reive, game.buffs()) then kind = "Reive" end
  local phone = Odyssey.watch_phone(game.key_items(), store())
  local out
  if kind then
    out = rows(kind)
  elseif zone == Odyssey.RABAO then
    out = {}
    Odyssey.rabao_rows(last_run, store(), phone, out)
    if #out > 0 then kind = "Odyssey" else out = nil end
  end
  if not out then
    ui.close("content")
    return
  end
  ui.window("content", { edge = true, width = 280, title = kind, heading = kind, elements = out })
  ui.open("content")
end)

-- //pops [NM]: an NM's pops (any case, a start of its name, or * wildcards); none: the list of NMs. //znm: the Zeni NMs.
commands.register("pops", function(...)
  if not settings.get("on") then return chat.add("Content Trackers is off (Config > Extras).") end
  local q = table.concat({ ... }, " ")
  if q == "" then return Pops.pick() end
  local nm = Pops.find(q)
  if nm then Pops.show(nm) else chat.add(("No pop list for \"%s\". //pops lists them."):format(q)) end
end)

commands.register("znm", function()
  if not settings.get("on") then return chat.add("Content Trackers is off (Config > Extras).") end
  Pops.znm()
end)

ui.on("pops", function(_, e)
  if e.kind == "select" and e.id == "nms" then
    Pops.show(Pops.EMPY[e.index])
  elseif e.kind == "press" and e.id == "more" then
    Pops.pick()
  end
end)

ui.on("znm", function(_, e)
  if e.kind == "select" then
    local path, tier = e.id:match("^t(%d+)_(%d+)$")
    if path then Pops.where(tonumber(path), tonumber(tier), e.index) end
  end
end)
