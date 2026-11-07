-- Bags by command (organizer, itemizer, porter and kin): items fetched to the inventory and stowed by name, the
-- gear the loaded Gearshift file names gathered into the wardrobes, the rest of the gear tidied away. One move at a
-- time, a moment apart; the server has the last word on each.

local INV, GAP = 0, 0.35
local NAMES = { inventory = 0, safe = 1, storage = 2, locker = 4, satchel = 5, sack = 6, case = 7, wardrobe = 8,
  safe2 = 9, wardrobe2 = 10, wardrobe3 = 11, wardrobe4 = 12, wardrobe5 = 13, wardrobe6 = 14, wardrobe7 = 15,
  wardrobe8 = 16 }
local LABEL = {}
for k, v in pairs(NAMES) do LABEL[v] = k end
local MOG = { [1] = true, [2] = true, [4] = true, [9] = true }
local WARDROBES = { 8, 10, 11, 12, 13, 14, 15, 16 }
local CARRIED = { 7, 6, 5 }   -- where tidied things go first: case, sack, satchel
local FROM = { 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 1, 9, 2, 4 }

local function say(t) chat.add("Bag Manager: " .. t) end

local function reachable(bag)
  local n = game.bag_size(bag)
  if not n or n == 0 then return false end
  return not MOG[bag] or game.info().mog_house
end

local function free(bag)
  return reachable(bag) and (game.bag_size(bag) - #game.items(bag)) or 0
end

local function named(it, want)
  local r = res.item(it.id)
  return r and ((r.name or ""):lower() == want or (r.log_name or ""):lower() == want), r
end

local function worn()
  local out = {}
  for _, e in pairs(game.equipment()) do
    if e.id then out[e.bag .. ":" .. e.slot] = true end
  end
  return out
end

-- Moves one stack and waits a moment; false when the target has no room.
local function move(it, to, count)
  if free(to) <= 0 then return false end
  actions.move(it.bag, it.slot, to, count)
  sleep(GAP)
  return true
end

local function get(name, how)
  local want = name:lower()
  local n = tonumber(how) or (how == "all" and math.huge) or 1
  local moved = 0
  for _, bag in ipairs(FROM) do
    if reachable(bag) then
      for _, it in ipairs(game.items(bag)) do
        if moved >= n then break end
        if it.locked == 0 and named(it, want) then
          local take = math.min(it.count, n - moved)
          if not move(it, INV, take < it.count and take or nil) then say("the inventory is full.") return end
          moved = moved + take
        end
      end
    end
  end
  say(moved > 0 and ("%d %s fetched."):format(moved, name) or ("no %s within reach."):format(name))
end

local function put(name, to, all)
  local want = name:lower()
  local targets = to and { to } or CARRIED
  local moved, w = 0, worn()
  for _, it in ipairs(game.items(INV)) do
    if (all or moved == 0) and it.locked == 0 and not w["0:" .. it.slot] and named(it, want) then
      local done = false
      for _, b in ipairs(targets) do
        if move(it, b) then done = true break end
      end
      if not done then say("no room to stow " .. name .. ".") break end
      moved = moved + 1
    end
  end
  if moved == 0 then say("no " .. name .. " in the inventory to stow.") else say(("%d stowed."):format(moved)) end
end

local function gear_list()
  local ok, g = pcall(mods.call, "gearshift", "gear_names")
  if not ok or not g then say("no Gearshift file loaded for this job.") return nil end
  return g
end

-- Each item the sets name, from wherever it is into a wardrobe (else the inventory).
local function gather()
  local g = gear_list()
  if not g then return end
  local want, missing, moved = {}, {}, 0
  for _, n in ipairs(g.names) do want[n:lower()] = n end
  local have = {}
  for _, b in ipairs({ INV, 8, 10, 11, 12, 13, 14, 15, 16 }) do
    for _, it in ipairs(game.items(b)) do
      local _, r = named(it, "")
      if r then have[(r.name or ""):lower()] = true have[(r.log_name or ""):lower()] = true end
    end
  end
  for key, n in pairs(want) do
    if not have[key] then
      local found = false
      for _, bag in ipairs({ 5, 6, 7, 1, 9, 2, 4 }) do
        if reachable(bag) and not found then
          for _, it in ipairs(game.items(bag)) do
            if it.locked == 0 and named(it, key) then
              local placed = false
              for _, wb in ipairs(WARDROBES) do
                if move(it, wb) then placed = true break end
              end
              if not placed and not move(it, INV) then say("no room left: stopping.") return end
              moved, found = moved + 1, true
              break
            end
          end
        end
      end
      if not found then missing[#missing + 1] = n end
    end
  end
  table.sort(missing)
  say(("%d gathered for %s%s"):format(moved, g.file or "this job",
    #missing > 0 and ("; not within reach: " .. table.concat(missing, ", ") .. ".") or "."))
end

-- Gear in the inventory that the sets don't name and that is not worn goes to the case, sack or satchel.
local function tidy()
  local g = gear_list()
  local keep = {}
  for _, n in ipairs(g and g.names or {}) do keep[n:lower()] = true end
  local moved, w = 0, worn()
  for _, it in ipairs(game.items(INV)) do
    local r = res.item(it.id)
    local gear = r and (r.kind == "armor" or r.kind == "weapon")
    if gear and it.locked == 0 and not w["0:" .. it.slot] and not keep[(r.name or ""):lower()] and not keep[(r.log_name or ""):lower()] then
      local done = false
      for _, b in ipairs(CARRIED) do
        if move(it, b) then done = true break end
      end
      if not done then say("no room left in the case, sack or satchel.") break end
      moved = moved + 1
    end
  end
  say(("%d piece%s tidied away."):format(moved, moved == 1 and "" or "s"))
end

commands.register("stow", function(cmd, ...)
  if not settings.get("on") then return end
  local args = { ... }
  local c = (cmd or ""):lower()
  if c == "get" then
    local how = args[#args] and (tonumber(args[#args]) or args[#args]:lower() == "all") and table.remove(args):lower()
    local name = table.concat(args, " ")
    if name == "" then say("//stow get <item> [count | all]") return end
    get(name, how)
  elseif c == "put" then
    local all = args[#args] and args[#args]:lower() == "all"
    if all then table.remove(args) end
    local to
    if #args >= 2 and args[#args - 1]:lower() == "to" then
      to = NAMES[args[#args]:lower()]
      if not to then say("no bag " .. args[#args] .. ".") return end
      table.remove(args) table.remove(args)
    end
    local name = table.concat(args, " ")
    if name == "" then say("//stow put <item> [to <bag>] [all]") return end
    put(name, to, all)
  elseif c == "gear" then
    gather()
  elseif c == "tidy" then
    tidy()
  else
    say("//stow get <item> [count | all] | put <item> [to <bag>] [all] | gear | tidy")
  end
end)
