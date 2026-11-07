-- Automaton sets (the automaton set add-ons): //automaton save | <name> | list | delete. Slots as actions.attach
-- numbers them: 1 head, 2 frame, 3..14 attachments.

local PUP = 18

local function setup()
  local d = game.job_data()
  for _, k in ipairs({ "main", "sub" }) do
    local j = d and d[k]
    if j and j.job == PUP then return j end
  end
  return nil
end

local function sets()
  local s = storage.account
  s.sets = s.sets or {}
  return s.sets
end

local function item_name(id)
  local r = id and res.item(id)
  return r and r.name or tostring(id)
end

local function put_on(name, set)
  local now = setup()
  if not now then
    chat.add("Automaton Sets: you are not a Puppetmaster now.")
    return
  end
  if game.entity_by_tag("pet") then
    chat.add("Automaton Sets: deactivate your automaton first.")
    return
  end
  -- Attachments off first: a new head or frame may refuse them.
  for slot = 3, 14 do
    actions.detach(slot)
  end
  sleep(0.5)
  if set.head then actions.attach(1, set.head) end
  if set.frame then actions.attach(2, set.frame) end
  sleep(0.5)
  for i, id in ipairs(set.attachments or {}) do
    actions.attach(2 + i, id)
    sleep(0.2)
  end
  sleep(1)
  local after = setup()
  local missing = {}
  local have = {}
  for _, id in ipairs(after and after.attachments or {}) do have[id] = (have[id] or 0) + 1 end
  for _, id in ipairs(set.attachments or {}) do
    if (have[id] or 0) > 0 then have[id] = have[id] - 1 else missing[#missing + 1] = item_name(id) end
  end
  chat.add(#missing == 0 and ("Automaton Sets: %s is on."):format(name)
    or ("Automaton Sets: %s is on, but not: %s (the server refused them)."):format(name, table.concat(missing, ", ")))
end

commands.register("automaton", function(cmd, ...)
  if not settings.get("on") then return end
  cmd = (cmd or ""):lower()
  local name = table.concat({ ... }, " "):match("^%s*(.-)%s*$"):lower()
  local s = sets()
  if cmd == "save" and name ~= "" then
    local j = setup()
    if not j then
      chat.add("Automaton Sets: you are not a Puppetmaster now.")
      return
    end
    s[name] = { head = j.head, frame = j.frame, attachments = j.attachments or {} }
    storage.save()
    chat.add(("Automaton Sets: %s saved (%d attachments)."):format(name, #(j.attachments or {})))
  elseif cmd == "delete" and name ~= "" then
    s[name] = nil
    storage.save()
  elseif cmd == "list" then
    local out = {}
    for k, v in pairs(s) do out[#out + 1] = ("%s (%s, %s, %d)"):format(k, item_name(v.head), item_name(v.frame), #(v.attachments or {})) end
    table.sort(out)
    chat.add("Automaton Sets: " .. (#out > 0 and table.concat(out, "; ") or "none saved"))
  elseif cmd ~= "" and s[cmd .. (name ~= "" and (" " .. name) or "")] then
    local key = cmd .. (name ~= "" and (" " .. name) or "")
    put_on(key, s[key])
  else
    chat.add("Automaton Sets: //automaton save <name>, //automaton <name>, //automaton list, //automaton delete <name>")
  end
end)
