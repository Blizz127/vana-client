-- Bag space, gil and chosen items and key items (the inventory and gil tracker add-ons), in an edge window.

local BAGS = { { 0, "Inventory" }, { 5, "Satchel" }, { 6, "Sack" }, { 7, "Case" }, { 8, "Wardrobe" },
  { 10, "Wardrobe 2" }, { 11, "Wardrobe 3" }, { 12, "Wardrobe 4" }, { 13, "Wardrobe 5" }, { 14, "Wardrobe 6" },
  { 15, "Wardrobe 7" }, { 16, "Wardrobe 8" } }

local function watched()
  local s = storage.character
  s.watch = s.watch or {}
  return s.watch
end

local function commas(n)
  local out = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

-- How many of an item we hold in every bag, and its stack size.
local function held(name)
  local n, id = 0, nil
  for _, it in ipairs(game.find_items(name)) do
    n, id = n + it.count, it.id
  end
  local r = id and res.item(id)
  return n, r and r.stack or 1
end

local function key_item(name)
  local want = name:lower()
  for _, id in ipairs(game.key_items()) do
    local k = res.key_item(id)
    if k and k.name:lower() == want then return true end
  end
  return false
end

local function rows()
  local out = {}
  for i, b in ipairs(BAGS) do
    if i > 1 and not settings.get("all_bags") then break end
    local size = game.bag_size(b[1]) or 0
    if size > 0 then
      local used = #game.items(b[1])
      out[#out + 1] = { type = "gauge", style = "row", label = b[2], text = used .. "/" .. size, value = used / size }
    end
  end
  for _, w in ipairs(watched()) do
    if w.key then
      local have = key_item(w.name)
      out[#out + 1] = { type = "gauge", style = "row", label = w.name, text = have and "Held" or "Not held",
        value = have and 1 or 0, dim = not have }
    else
      local n, stack = held(w.name)
      out[#out + 1] = { type = "gauge", style = "row", label = w.name, text = tostring(n),
        value = math.min(1, n / math.max(1, stack)), dim = n == 0 }
    end
  end
  return out
end

local function tick()
  if not settings.get("on") then
    ui.close("bags")
    return
  end
  ui.window("bags", {
    edge = true, width = 280, title = "Bags", heading = "Gil " .. commas(game.gil()), elements = rows(),
  })
  ui.open("bags")
end

timer.every(1, tick)
events.on("settings_changed", tick)

local USAGE = "//bags add <item>, //bags addkey <key item>, //bags remove <name>, //bags list"

commands.register("bags", function(cmd, ...)
  cmd = (cmd or ""):lower()
  local name = table.concat({ ... }, " "):match("^%s*(.-)%s*$")
  local w = watched()
  if cmd == "list" then
    local names = {}
    for _, x in ipairs(w) do names[#names + 1] = x.name end
    chat.add("Inventory HUD: " .. (#names > 0 and table.concat(names, ", ") or "nothing watched"))
  elseif (cmd == "add" or cmd == "addkey") and name ~= "" then
    w[#w + 1] = { name = name, key = cmd == "addkey" or nil }
    storage.save()
    tick()
  elseif cmd == "remove" and name ~= "" then
    for i, x in ipairs(w) do
      if x.name:lower() == name:lower() then
        table.remove(w, i)
        storage.save()
        tick()
        return
      end
    end
    chat.add("Inventory HUD: " .. name .. " is not watched.")
  else
    chat.add("Inventory HUD: " .. USAGE)
  end
end)
