-- //sell and //trade by item name (the sell and trade add-ons). Names: any case, the short or the log name, * for
-- any run of letters.

local INVENTORY = 0

local function pattern(name)
  local p = name:lower():match("^%s*(.-)%s*$")
  if p:find("*", 1, true) then
    return "^" .. p:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
  end
end

-- Inventory stacks of an item, unlocked, not worn.
local function stacks(name)
  local pat = pattern(name)
  local out = {}
  if not pat then
    for _, it in ipairs(game.find_items(name, { INVENTORY })) do
      if it.locked == 0 then out[#out + 1] = it end
    end
    return out
  end
  for _, it in ipairs(game.items(INVENTORY)) do
    local r = res.item(it.id)
    if r and it.locked == 0 and (((r.name or ""):lower():find(pat)) or ((r.log_name or ""):lower():find(pat))) then
      out[#out + 1] = it
    end
  end
  return out
end

commands.register("sell", function(...)
  if not settings.get("on") then return end
  local args = { ... }
  local all = args[#args] and args[#args]:lower() == "all"
  if all then table.remove(args) end
  local name = table.concat(args, " ")
  if name == "" then
    chat.add("Sell and Hand In: //sell <item> [all]")
    return
  end
  if not game.shop() then
    chat.add("Sell and Hand In: open a shop first.")
    return
  end
  local found = stacks(name)
  if #found == 0 then
    chat.add("Sell and Hand In: you have no " .. name .. " to sell.")
    return
  end
  for i, it in ipairs(found) do
    if i > 1 and not all then break end
    if i > 1 then sleep(1.5) end
    actions.sell(it.slot, it.count)
  end
end)

-- "<name> [count]" pieces separated by commas.
local function wanted(line)
  local out = {}
  for piece in line:gmatch("[^,]+") do
    local name, n = piece:match("^%s*(.-)%s+(%d+)%s*$")
    name = name or piece:match("^%s*(.-)%s*$")
    if name ~= "" then out[#out + 1] = { name = name, count = tonumber(n) or 1 } end
  end
  return out
end

commands.register("trade", function(...)
  if not settings.get("on") then return end
  local me = game.player()
  local npc = me and me.target
  local t = npc and game.entity(npc)
  if not t or t.kind ~= "npc" then
    chat.add("Sell and Hand In: target the NPC first.")
    return
  end
  local items = {}
  for _, w in ipairs(wanted(table.concat({ ... }, " "))) do
    local left = w.count
    for _, it in ipairs(stacks(w.name)) do
      if left <= 0 then break end
      local n = math.min(left, it.count)
      items[#items + 1] = { slot = it.slot, count = n }
      left = left - n
    end
    if left > 0 then
      chat.add(("Sell and Hand In: you have only %d %s."):format(w.count - left, w.name))
      return
    end
  end
  if #items == 0 then
    chat.add("Sell and Hand In: //trade <item> [count], <item> [count]...")
  elseif #items > 8 then
    chat.add("Sell and Hand In: a trade holds 8 stacks at most.")
  else
    actions.trade(npc, items)
  end
end)
