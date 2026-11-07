-- Rows left out of the game's lists (trimspells, HideActions): spells, abilities and mounts named by //trim, kept per
-- character. Only the lists change; commands and macros use them as before.

local LISTS = { "magic", "abilities", "mounts" }

local function say(t) chat.add("List Trimmer: " .. t) end

local function kept()
  local s = storage.character
  s.trimmed = s.trimmed or { magic = {}, abilities = {}, mounts = {} }
  return s.trimmed
end

local function apply()
  local on = settings.get("on")
  for _, l in ipairs(LISTS) do
    local ids = {}
    if on then
      for id in pairs(kept()[l]) do ids[#ids + 1] = tonumber(id) end
    end
    ui.native.trim(l, ids)
  end
end

-- The list and id a name stands for: spells first, then abilities, then mounts.
local function find(name)
  local want = name:lower()
  for id = 1, 1023 do
    local r = res.spell(id)
    if r and r.name and r.name:lower() == want then return "magic", id, r.name end
  end
  for id = 0, 0x7ff do
    local r = res.ability(id)
    if r and r.name and r.name:lower() == want then return "abilities", id, r.name end
  end
  for id = 0, 63 do
    local n = res.mount(id)
    if n and n:lower() == want then return "mounts", id, n end
  end
end

local function name_of(list, id)
  if list == "magic" then return (res.spell(id) or {}).name end
  if list == "abilities" then return (res.ability(id) or {}).name end
  return res.mount(id)
end

commands.register("trim", function(...)
  local arg = table.concat({ ... }, " ")
  local k = kept()
  if arg == "" then
    say("//trim <spell, ability or mount> | list | clear")
  elseif arg:lower() == "list" then
    local out = {}
    for _, l in ipairs(LISTS) do
      for id in pairs(k[l]) do out[#out + 1] = name_of(l, tonumber(id)) or tostring(id) end
    end
    table.sort(out)
    say(#out > 0 and ("left out: " .. table.concat(out, ", ")) or "nothing left out.")
  elseif arg:lower() == "clear" then
    for _, l in ipairs(LISTS) do k[l] = {} end
    apply()
    say("every list is whole again.")
  else
    local list, id, name = find(arg)
    if not list then say("no spell, ability or mount named " .. arg .. ".") return end
    local key = tostring(id)
    if k[list][key] then
      k[list][key] = nil
      say(name .. " is back in its list.")
    else
      k[list][key] = true
      say(name .. " is left out of its list.")
    end
    apply()
  end
end)

events.on("load", apply)
events.on("login", apply)
events.on("settings_changed", apply)
