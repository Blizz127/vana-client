-- /<spell or ability> [target] for what we can use (the shortcut add-ons): the name with any case, no spaces or marks,
-- and 2..6 for II..VI, becomes the full command: /cure3 me -> /ma "Cure III" <me>. The game's commands are left alone.

local ROMAN = { ii = "2", iii = "3", iv = "4", v = "5", vi = "6" }
local TARGETS = { t = "<t>", me = "<me>", st = "<st>", bt = "<bt>", lastst = "<lastst>", pet = "<pet>" }

local index, built = {}, -100

local function keys(name)
  local low = name:lower()
  local plain = low:gsub("[^%w]", "")
  local out = { plain }
  local base, roman = low:match("^(.-)%s+([iv]+)$")
  if base and ROMAN[roman] then out[#out + 1] = base:gsub("[^%w]", "") .. ROMAN[roman] end
  return out
end

local function rebuild()
  index = {}
  for _, id in ipairs(game.spells()) do
    local s = res.spell(id)
    if s and s.name and s.name ~= "" then
      for _, k in ipairs(keys(s.name)) do index[k] = index[k] or { cmd = "/ma", name = s.name, self = s.targets == 1 } end
    end
  end
  for _, id in ipairs(game.abilities()) do
    local a = res.ability(id)
    if a and a.name and a.name ~= "" then
      local cmd = id < 0x200 and "/ws" or id < 0x400 and "/ja" or "/pet"
      for _, k in ipairs(keys(a.name)) do index[k] = index[k] or { cmd = cmd, name = a.name, self = a.targets == 1 } end
    end
  end
  built = os.clock()
end

local function target(arg, self)
  arg = arg:match("^%s*(.-)%s*$")
  if arg == "" then return self and "<me>" or "<t>" end
  local low = arg:lower()
  if TARGETS[low] then return TARGETS[low] end
  if low:match("^p[0-5]$") or low:match("^a[12][0-5]$") then return "<" .. low .. ">" end
  if arg:match("^<.*>$") then return arg end
  for _, m in ipairs(game.party()) do
    if m.name and m.name:lower():sub(1, #low) == low then return m.name end
  end
  return arg
end

filters.typed(function(line)
  if not settings.get("on") then return nil end
  local word, rest = line:match("^/([^/%s]+)%s*(.*)$")
  if not word or commands.is_game(word) then return nil end
  if os.clock() - built > 10 then rebuild() end
  local hit = index[word:lower():gsub("[^%w]", "")]
  if not hit then return nil end
  return ('%s "%s" %s'):format(hit.cmd, hit.name, target(rest, hit.self))
end)

events.on("job_change", function() built = -100 end)
