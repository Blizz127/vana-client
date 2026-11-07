-- A window for the content we are in (Dynamis, Abyssea, Salvage, Nyzul Isle helpers), read from its messages;
-- the time left counts down between them. Filters cannot read the game, so lines are kept for the next tick.

local pending = {}
local st = {}

local function reset()
  st = { lights = {}, risen = {}, removed = {}, tokens = 0 }
end
reset()

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
  if not st.ends then return end
  local left = math.floor(math.max(0, st.ends - os.clock()))
  out[#out + 1] = { type = "gauge", style = "row", label = "Time left",
    text = ("%d:%02d"):format(left // 60, left % 60), value = math.min(1, left / 3600) }
end

local function rows(kind)
  local out = {}
  left_row(out)
  if kind == "Dynamis" then
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

local here
timer.every(1, function()
  local lines = pending
  pending = {}
  if not settings.get("on") then
    ui.close("content")
    return
  end
  local p = game.player()
  local kind = content_of(p and res.zone(p.zone))
  if kind ~= here then
    -- a new content (or none): its own state, before its first messages are read
    reset()
    here = kind
  end
  for _, l in ipairs(lines) do read(l) end
  if not kind then
    ui.close("content")
    return
  end
  ui.window("content", { edge = true, width = 280, title = kind, heading = kind, elements = rows(kind) })
  ui.open("content")
end)
