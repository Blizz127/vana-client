-- //ride: a random mount of ours, or the first whose name holds the words given (the mount roulette add-ons). The
-- mounts we have are the key items 3072 + the mount list's index.

local FIRST = 3072

local function owned()
  local out = {}
  for _, id in ipairs(game.key_items()) do
    if id >= FIRST and id < FIRST + 64 then
      local name = res.mount(id - FIRST)
      if name and name ~= "" then out[#out + 1] = name end
    end
  end
  table.sort(out)
  return out
end

commands.register("ride", function(...)
  if not settings.get("on") then return end
  local want = table.concat({ ... }, " "):lower():match("^%s*(.-)%s*$")
  local mounts = owned()
  if #mounts == 0 then
    chat.add("Mount Picker: you have no mounts yet.")
    return
  end
  if want == "list" then
    chat.add("Mount Picker: " .. table.concat(mounts, ", "))
    return
  end
  local pick
  if want == "" then
    pick = mounts[math.random(#mounts)]
  else
    for _, m in ipairs(mounts) do
      if m:lower():find(want, 1, true) then
        pick = m
        break
      end
    end
  end
  if pick then
    actions.mount(pick)
  else
    chat.add("Mount Picker: no mount of yours is called " .. want .. ".")
  end
end)
