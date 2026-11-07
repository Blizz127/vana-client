-- Named sets of Records of Eminence objectives (the roe add-ons): //roeset save | <name> | list | delete. The server
-- takes one change a second.

local GAP = 1.1

local function say(t) chat.add("Objective Sets: " .. t) end

local function sets()
  local s = storage.character
  s.sets = s.sets or {}
  return s.sets
end

local function name_of(n)
  local r = res.item(0xE000 + n)
  return r and r.name or ("objective " .. n)
end

local function put_on(name, ids)
  local want, have = {}, {}
  for _, n in ipairs(ids) do want[n] = true end
  local changes = 0
  for _, o in ipairs(game.roe().active) do
    have[o.id] = true
    if not want[o.id] then
      actions.roe_remove(o.id)
      changes = changes + 1
      sleep(GAP)
    end
  end
  for _, n in ipairs(ids) do
    if not have[n] then
      actions.roe_set(n)
      changes = changes + 1
      sleep(GAP)
    end
  end
  say(("%s is set (%d change%s)."):format(name, changes, changes == 1 and "" or "s"))
end

commands.register("roeset", function(cmd, ...)
  if not settings.get("on") then return end
  local c = (cmd or ""):lower()
  local rest = table.concat({ ... }, " "):lower()
  local s = sets()
  if c == "" then
    say("//roeset save <name> | <name> | list | delete <name>")
  elseif c == "save" then
    if rest == "" then say("//roeset save <name>") return end
    local ids = {}
    for _, o in ipairs(game.roe().active) do ids[#ids + 1] = o.id end
    if #ids == 0 then say("no objectives are set.") return end
    s[rest] = ids
    say(("%s saved (%d objective%s)."):format(rest, #ids, #ids == 1 and "" or "s"))
  elseif c == "list" then
    local names = {}
    for k, v in pairs(s) do names[#names + 1] = ("%s (%d)"):format(k, #v) end
    table.sort(names)
    say(#names > 0 and table.concat(names, ", ") or "none saved.")
  elseif c == "delete" then
    s[rest] = nil
    say(rest .. " deleted.")
  elseif s[c] then
    put_on(c, s[c])
  else
    say("no set " .. c .. ".")
  end
end)

commands.register("roeshow", function()
  if not settings.get("on") then return end
  local active = game.roe().active
  if #active == 0 then say("no objectives are set.") return end
  for _, o in ipairs(active) do say(("%d. %s (%d)"):format(o.slot, name_of(o.id), o.progress)) end
end)
