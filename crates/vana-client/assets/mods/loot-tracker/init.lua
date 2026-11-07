-- Loot (the loot tracker add-ons): Treasure Hunter per monster from its rises (an additional effect, message 603, its
-- value the new level), kills by name (defeat messages), drops by name (new treasure pool items, by their dropper),
-- and the pool's items with the 5 minutes they stay.

local TH_PROC, DEFEATS = 603, { [6] = true, [20] = true, [97] = true }
local POOL_SECS = 300

local th = {}        -- monster id -> TH level
local kills = {}     -- name -> count
local drops = {}     -- name -> {item id -> count}
local order = {}     -- names, the latest last
local pool = {}      -- "slot:item:dropper" -> first seen (os.clock)

local function touch(name)
  for i, n in ipairs(order) do
    if n == name then table.remove(order, i) break end
  end
  order[#order + 1] = name
end

events.on("action", function(a)
  for _, t in ipairs(a.targets or {}) do
    for _, r in ipairs(t.results or {}) do
      if r.proc and r.proc.message == TH_PROC then th[t.id] = r.proc.value end
    end
  end
end)

events.on("battle_message", function(_, target, message)
  if not DEFEATS[message] then return end
  local e = game.entity(target)
  if e and e.kind == "mob" then
    kills[e.name] = (kills[e.name] or 0) + 1
    touch(e.name)
  end
end)

local function item_name(id)
  local r = res.item(id)
  return r and r.name or ("item " .. id)
end

local function rows()
  local out = {}
  local t = game.target()
  if t and t.kind == "mob" then
    out[#out + 1] = { type = "gauge", style = "row", label = "Treasure Hunter: " .. t.name, text = tostring(th[t.id] or 0),
      value = math.min(1, (th[t.id] or 0) / 8) }
  end
  local now = os.clock()
  local seen = {}
  for _, p in ipairs(game.treasure()) do
    local key = ("%d:%d:%s"):format(p.slot, p.item, tostring(p.dropper))
    seen[key] = true
    if not pool[key] then
      pool[key] = now
      local d = p.dropper and game.entity(p.dropper)
      local who = d and d.name or "?"
      drops[who] = drops[who] or {}
      drops[who][p.item] = (drops[who][p.item] or 0) + (p.count or 1)
      touch(who)
    end
    local left = math.max(0, POOL_SECS - (now - pool[key]))
    out[#out + 1] = { type = "gauge", style = "row", label = item_name(p.item), text = ("%d:%02d"):format(left // 60, left % 60),
      value = left / POOL_SECS, dim = p.lotted or p.passed }
  end
  for k in pairs(pool) do
    if not seen[k] then pool[k] = nil end
  end
  for i = #order, math.max(1, #order - 4), -1 do
    local name = order[i]
    local parts = {}
    for id, n in pairs(drops[name] or {}) do parts[#parts + 1] = ("%s x%d"):format(item_name(id), n) end
    table.sort(parts)
    out[#out + 1] = { type = "text", text = ("%s: %d killed%s"):format(name, kills[name] or 0,
      #parts > 0 and (" \u{2014} " .. table.concat(parts, ", ")) or ""), dim = true }
  end
  return out
end

timer.every(1, function()
  local els = settings.get("on") and rows() or {}
  if #els == 0 then
    ui.close("loot")
    return
  end
  ui.window("loot", { edge = true, width = 300, title = "Loot", heading = "Loot", elements = els })
  ui.open("loot")
end)

events.on("zone_change", function() th = {} end)

commands.register("lootlog", function(cmd)
  if (cmd or ""):lower() == "reset" then
    th, kills, drops, order = {}, {}, {}, {}
    chat.add("Loot Tracker: started over.")
  else
    chat.add("Loot Tracker: //lootlog reset starts over.")
  end
end)
