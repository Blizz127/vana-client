-- What a macro does first, for its slot's icon and recast: the first line naming a spell (/ma, /magic, /so, /song,
-- /nin), a job ability or pet command (/ja, /pet), a weapon skill (/ws) or an item (/item).

local M = {}

local spells, abilities, weaponskills

local function index()
  if spells then return end
  spells, abilities, weaponskills = {}, {}, {}
  for id = 1, 1023 do
    local s = res.spell(id)
    if s and s.name and s.name ~= "" then spells[s.name:lower()] = spells[s.name:lower()] or id end
  end
  for id = 0, 0x7ff do
    local a = res.ability(id)
    if a and a.name and a.name ~= "" then
      local t = id < 0x200 and weaponskills or abilities
      t[a.name:lower()] = t[a.name:lower()] or id
    end
  end
end

local KIND = { ["/ma"] = "spell", ["/magic"] = "spell", ["/so"] = "spell", ["/song"] = "spell", ["/nin"] = "spell",
  ["/ninjutsu"] = "spell", ["/ja"] = "ability", ["/jobability"] = "ability", ["/pet"] = "ability",
  ["/ws"] = "weaponskill", ["/weaponskill"] = "weaponskill", ["/item"] = "item" }

local cache = {}

-- {kind = 'spell' | 'ability' | 'item', id, recast_id} for the macro's first action, or false.
function M.of(macro)
  local key = table.concat(macro.lines or {}, "\n")
  local hit = cache[key]
  if hit ~= nil then return hit end
  hit = false
  for _, line in ipairs(macro.lines or {}) do
    local cmd, name = line:match('^(/%a+)%s+"([^"]+)"')
    if not cmd then cmd, name = line:match("^(/%a+)%s+(%S+)") end
    local kind = cmd and KIND[cmd:lower()]
    if kind then
      index()
      name = name:lower()
      if kind == "spell" and spells[name] then
        hit = { kind = "spell", id = spells[name] }
      elseif kind == "ability" and abilities[name] then
        local r = res.ability(abilities[name])
        hit = { kind = "ability", id = abilities[name], recast_id = r and r.recast_id }
      elseif kind == "weaponskill" and weaponskills[name] then
        hit = { kind = "ability", id = weaponskills[name] }
      elseif kind == "item" then
        local held = game.find_items(name)
        if held[1] then hit = { kind = "item", id = held[1].id } end
      end
      break
    end
  end
  cache[key] = hit
  return hit
end

-- Seconds left on its recast and the fraction of the whole still to go (0 when ready).
function M.recast(a, recasts)
  if not a then return 0, 0 end
  local left, total = 0, 0
  if a.kind == "spell" then
    left, total = recasts.spells[a.id] or 0, recasts.totals.spells[a.id] or 0
  elseif a.recast_id then
    left, total = recasts.abilities[a.recast_id] or 0, recasts.totals.abilities[a.recast_id] or 0
  end
  if left <= 0 then return 0, 0 end
  return left, total > 0 and math.min(1, left / total) or 1
end

return M
