-- /find <words>: one line per item whose name has them, with the bags holding it and the count in each.
local BAGS = { [0] = "Inventory", "Mog Safe", "Storage", "Temporary", "Mog Locker", "Mog Satchel", "Mog Sack", "Mog Case", "Mog Wardrobe", "Mog Safe 2" }

local function bag_name(b)
  if b >= 10 and b <= 16 then
    return "Mog Wardrobe " .. (b - 8)
  end
  return BAGS[b] or ("Bag " .. b)
end

commands.register("find", function(...)
  local what = table.concat({ ... }, " ")
  local want = what:lower()
  if want == "" then return end
  local found, names = {}, {}
  for bag = 0, 17 do
    for _, it in ipairs(game.items(bag)) do
      local name = res.item(it.id)
      name = type(name) == "table" and name.name or name
      if name and name:lower():find(want, 1, true) then
        if not found[name] then
          found[name] = {}
          names[#names + 1] = name
        end
        found[name][bag] = (found[name][bag] or 0) + math.max(it.count, 1)
      end
    end
  end
  -- The system message mode's colour, as the client's own lines.
  if #names == 0 then
    chat.add("/find " .. what .. ": (none)", { colour = 0x8b })
    return
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local at = {}
    for bag = 0, 17 do
      if found[name][bag] then
        at[#at + 1] = bag_name(bag) .. " " .. found[name][bag]
      end
    end
    chat.add(name .. ": " .. table.concat(at, ", "), { colour = 0x8b })
  end
end)
