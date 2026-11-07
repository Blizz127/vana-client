-- Trust lineups (the trust set add-ons): //trusts save <name> [trust, trust...] keeps the party's trusts (or those
-- named), //trusts <name> calls those not already in the party one after another.

local busy = false

-- Names compared without case, spaces or marks: the party shows "NanaaMihgo" for the spell "Nanaa Mihgo".
local function key(name)
  return (name:lower():gsub("[^%w]", ""))
end

local function sets()
  local s = storage.character
  s.lineups = s.lineups or {}
  return s.lineups
end

-- Our learned trust spells by lower-case name: {id, name, cast_time}.
local function known_trusts()
  local out = {}
  for _, id in ipairs(game.spells()) do
    local s = res.spell(id)
    if s and id >= 896 and id < 1024 and s.name and s.name ~= "" then
      out[key(s.name)] = { id = id, name = s.name, cast = s.cast_time or 5 }
    end
  end
  return out
end

local function in_party()
  local out = {}
  for i, m in ipairs(game.party()) do
    if i <= 6 and m.name then out[key(m.name)] = true end
  end
  return out
end

local function call(names)
  if busy then
    chat.add("Trust Lineups: still calling the last lineup.")
    return
  end
  busy = true
  local known, here = known_trusts(), in_party()
  local ok, err = pcall(function()
    for _, n in ipairs(names) do
      local t = known[key(n)]
      if not t then
        chat.add("Trust Lineups: you have not learned " .. n .. ".")
      elseif not here[key(n)] then
        commands.run(('/ma "%s" <me>'):format(t.name))
        -- The next once this one stands in the party (or we gave up) and the game takes a spell again, a few seconds
        -- after a cast ends.
        local waited = 0
        repeat
          sleep(0.5)
          waited = waited + 0.5
        until in_party()[key(n)] or waited >= t.cast + 12
        sleep(4)
      end
    end
  end)
  busy = false
  if not ok then error(err, 0) end
end

local USAGE = "//trusts <lineup>, //trusts save <lineup> [trust, trust...], //trusts list, //trusts delete <lineup>"

commands.register("trusts", function(cmd, name, ...)
  if not settings.get("on") then return end
  cmd = (cmd or ""):lower()
  local s = sets()
  if cmd == "" then
    chat.add("Trust Lineups: " .. USAGE)
  elseif cmd == "list" then
    local out = {}
    for k, v in pairs(s) do out[#out + 1] = k .. ": " .. table.concat(v, ", ") end
    table.sort(out)
    chat.add("Trust Lineups: " .. (#out > 0 and table.concat(out, "; ") or "none saved"))
  elseif cmd == "save" and name then
    local names = {}
    local rest = table.concat({ ... }, " ")
    if rest:match("%S") then
      for n in rest:gmatch("[^,]+") do names[#names + 1] = n:match("^%s*(.-)%s*$") end
    else
      local known = known_trusts()
      for i, m in ipairs(game.party()) do
        if i > 1 and i <= 6 and m.name and known[key(m.name)] then names[#names + 1] = known[key(m.name)].name end
      end
    end
    if #names == 0 then
      chat.add("Trust Lineups: no trusts in your party to save; name them: //trusts save <lineup> <trust>, <trust>")
      return
    end
    s[name:lower()] = names
    storage.save()
    chat.add(("Trust Lineups: %s is %s."):format(name, table.concat(names, ", ")))
  elseif cmd == "delete" and name then
    s[name:lower()] = nil
    storage.save()
    chat.add("Trust Lineups: " .. name .. " deleted.")
  elseif s[cmd] then
    call(s[cmd])
  else
    chat.add("Trust Lineups: no lineup " .. cmd .. ". " .. USAGE)
  end
end)
