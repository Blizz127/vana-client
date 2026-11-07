-- Key binds and aliases kept per character (the bind and alias add-ons): //bind <key> <line>, //alias <name> <line>.
-- An alias's line may use $1, $2... for the words typed after it, and $* for all of them.

local function saved()
  local s = storage.character
  s.binds = s.binds or {}
  s.aliases = s.aliases or {}
  return s
end

local function bind(key, line)
  local ok, err = pcall(binds.set, key, function() commands.run(line) end)
  if not ok then chat.add("Key Commands: " .. tostring(err)) end
  return ok
end

local function load_binds()
  for key, line in pairs(saved().binds) do bind(key, line) end
end

commands.register("bind", function(key, ...)
  local line = table.concat({ ... }, " ")
  if not key or line == "" then
    chat.add("Key Commands: //bind <key> <line>")
    return
  end
  key = key:lower()
  if bind(key, line) then
    saved().binds[key] = line
    storage.save()
    chat.add(("Key Commands: %s runs %s"):format(key, line))
  end
end)

commands.register("unbind", function(key)
  if not key then return end
  key = key:lower()
  pcall(binds.unset, key)
  saved().binds[key] = nil
  storage.save()
end)

commands.register("binds", function()
  local out = {}
  for k, v in pairs(saved().binds) do out[#out + 1] = k .. ": " .. v end
  table.sort(out)
  chat.add("Key Commands: " .. (#out > 0 and table.concat(out, "; ") or "no binds"))
end)

commands.register("alias", function(name, ...)
  local line = table.concat({ ... }, " ")
  if not name or line == "" then
    chat.add("Key Commands: //alias <name> <line>")
    return
  end
  name = name:lower():gsub("^/+", "")
  if commands.is_game(name) then
    chat.add("Key Commands: /" .. name .. " is a game command.")
    return
  end
  saved().aliases[name] = line
  storage.save()
end)

commands.register("unalias", function(name)
  if not name then return end
  saved().aliases[name:lower():gsub("^/+", "")] = nil
  storage.save()
end)

commands.register("aliases", function()
  local out = {}
  for k, v in pairs(saved().aliases) do out[#out + 1] = "/" .. k .. ": " .. v end
  table.sort(out)
  chat.add("Key Commands: " .. (#out > 0 and table.concat(out, "; ") or "no aliases"))
end)

-- An alias typed (/name or //name) becomes its line.
filters.typed(function(line)
  if not settings.get("on") then return nil end
  local name, rest = line:match("^/+(%S+)%s*(.*)$")
  local a = name and saved().aliases[name:lower()]
  if not a then return nil end
  local words = {}
  for w in rest:gmatch("%S+") do words[#words + 1] = w end
  local all = rest:gsub("%%", "%%%%")
  return (a:gsub("%$(%d)", function(n) return words[tonumber(n)] or "" end):gsub("%$%*", all))
end)

local started
started = events.on("frame", function()
  if game.player() and game.player().name ~= "" then
    events.off(started)
    if settings.get("on") then load_binds() end
  end
end)
