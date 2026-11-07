-- Named blue magic sets (the blue magic set add-ons): //blu save | <name> | list | delete. Slots 1..20 as
-- actions.blue_set numbers them; the server refuses spells over the job's points or level.

local BLU = 16

local function setup()
  local d = game.job_data()
  for _, k in ipairs({ "main", "sub" }) do
    local j = d and d[k]
    if j and j.job == BLU then return j end
  end
  return nil
end

local function sets()
  local s = storage.account
  s.blue = s.blue or {}
  return s.blue
end

local function spell_name(id)
  local r = res.spell(id)
  return r and r.name or tostring(id)
end

-- One change a second (the game's rate): only the slots that differ, emptied first, then filled.
local GAP = 1.1

local function put_on(name, spells)
  local j = setup()
  if not j then
    chat.add("Blue Magic Sets: you are not a Blue Mage now.")
    return
  end
  local want = {}
  for i = 1, 20 do want[i] = spells[i] or 0 end
  local have = j.blue_slots or {}
  local changes = 0
  for i = 20, 1, -1 do
    if (have[i] or 0) ~= 0 and have[i] ~= want[i] then
      actions.blue_remove(i)
      changes = changes + 1
      sleep(GAP)
    end
  end
  for i = 1, 20 do
    if want[i] ~= 0 and (have[i] or 0) ~= want[i] then
      actions.blue_set(i, want[i])
      changes = changes + 1
      sleep(GAP)
    end
  end
  sleep(1)
  local now = {}
  for _, id in ipairs(setup().blue_spells or {}) do now[id] = true end
  local missing = {}
  for _, id in ipairs(spells) do
    if id ~= 0 and not now[id] then missing[#missing + 1] = spell_name(id) end
  end
  chat.add(#missing == 0 and ("Blue Magic Sets: %s is set (%d changes)."):format(name, changes)
    or ("Blue Magic Sets: %s is set, but not: %s (the server refused them)."):format(name, table.concat(missing, ", ")))
end

commands.register("blu", function(cmd, ...)
  if not settings.get("on") then return end
  local name = table.concat({ cmd or "", ... }, " "):match("^%s*(.-)%s*$"):lower()
  local rest = table.concat({ ... }, " "):match("^%s*(.-)%s*$"):lower()
  cmd = (cmd or ""):lower()
  local s = sets()
  if cmd == "save" and rest ~= "" then
    local j = setup()
    if not j then
      chat.add("Blue Magic Sets: you are not a Blue Mage now.")
      return
    end
    s[rest] = j.blue_slots or j.blue_spells or {}
    storage.save()
    chat.add(("Blue Magic Sets: %s saved (%d spells)."):format(rest, #(j.blue_spells or {})))
  elseif cmd == "delete" and rest ~= "" then
    s[rest] = nil
    storage.save()
  elseif cmd == "list" then
    local out = {}
    for k, v in pairs(s) do
      local n = 0
      for _, id in ipairs(v) do if id ~= 0 then n = n + 1 end end
      out[#out + 1] = ("%s (%d)"):format(k, n)
    end
    table.sort(out)
    chat.add("Blue Magic Sets: " .. (#out > 0 and table.concat(out, ", ") or "none saved"))
  elseif s[name] then
    put_on(name, s[name])
  else
    chat.add("Blue Magic Sets: //blu save <name>, //blu <name>, //blu list, //blu delete <name>")
  end
end)
