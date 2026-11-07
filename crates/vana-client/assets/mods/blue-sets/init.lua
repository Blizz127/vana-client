-- Named blue magic sets (the blue magic set add-ons): //blu save | <name> | list | delete. Slots 1..20 as
-- actions.blue_set numbers them; the server refuses spells over the job's points or level. //blu codex: every blue
-- spell, learned or not, and the monster moves that teach it; a line and a call when a monster readies a move that
-- teaches one we lack (BLUAlert), and a call when one is learned.

local LEARN = require("src.learn")
local BLU = 16
local CODEX = "blucodex"

-- The blue spells each monster move teaches.
local TAUGHT = {}
for sp, e in pairs(LEARN) do
  for _, m in ipairs(e[2]) do
    TAUGHT[m] = TAUGHT[m] or {}
    table.insert(TAUGHT[m], sp)
  end
end

local function known()
  local t = {}
  for _, id in ipairs(game.spells() or {}) do t[id] = true end
  return t
end

local function blu_level(r) return r.levels and r.levels[BLU] end

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

-- ---- The codex ----

local FILTERS = { "Missing", "Learned", "All" }
local view = 1

local function codex_rows()
  local k = known()
  local list, have = {}, 0
  for sp, e in pairs(LEARN) do
    local r = res.spell(sp)
    if r and r.name then
      local learned = k[sp] == true
      if learned then have = have + 1 end
      if view == 3 or (view == 1 and not learned) or (view == 2 and learned) then
        local moves = {}
        for _, m in ipairs(e[2]) do moves[#moves + 1] = res.mob_skill(m) or ("move " .. m) end
        list[#list + 1] = { id = sp, level = blu_level(r) or 999, name = r.name, learned = learned, points = e[1],
          moves = table.concat(moves, ", ") }
      end
    end
  end
  table.sort(list, function(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return a.name < b.name
  end)
  local rows = {}
  for _, x in ipairs(list) do
    rows[#rows + 1] = { x.name, x.level == 999 and "" or tostring(x.level), tostring(x.points), x.moves,
      icon = { kind = "spell", id = x.id }, colour = x.learned and nil or { 200, 200, 200 } }
  end
  return rows, have
end

local function codex()
  local rows, have = codex_rows()
  local total = 0
  for _ in pairs(LEARN) do total = total + 1 end
  ui.window(CODEX, {
    title = "Blue Magic Codex", width = 640,
    elements = {
      { type = "text", id = "count", text = ("%d of %d learned"):format(have, total) },
      { type = "tabs", id = "filter", items = FILTERS, at = view },
      { type = "list", id = "spells", rows = rows, height = 14,
        columns = { { title = "Spell", width = 200 }, { title = "Lvl", width = 40, align = "right" },
          { title = "Pts", width = 40, align = "right" }, { title = "Learned from", width = 320 } } },
    },
  })
end

ui.on(CODEX, function(_, e)
  if e.kind == "set" and e.id == "filter" then
    view = e.index
    local rows = codex_rows()
    ui.update(CODEX, "spells", { rows = rows, at = 1 })
  end
end)

-- ---- Learnable moves and new spells ----

local function call() if settings.get("alert_sound") then audio.play_ui(18) end end

events.on("action", function(a)
  if not settings.get("on") or not settings.get("alert") or a.category ~= 7 or a.param == 28787 then return end
  local p = game.player()
  if not p or p.main_job ~= BLU then return end
  local mob = game.entity(a.actor)
  local t = a.targets and a.targets[1]
  local r = t and t.results and t.results[1]
  local teaches = r and TAUGHT[r.value]
  if not mob or mob.kind ~= "mob" or not teaches then return end
  local k, out = known(), {}
  for _, id in ipairs(teaches) do
    local s = res.spell(id)
    if s and not k[id] then
      local lvl = blu_level(s)
      out[#out + 1] = s.name .. ((lvl and lvl > (p.main_level or 0)) and (" at level " .. lvl) or "")
    end
  end
  if #out == 0 then return end
  chat.add(("Blue Magic: %s readies %s, which teaches %s."):format(mob.name, res.mob_skill(r.value) or "a move", table.concat(out, ", ")))
  call()
end)

-- A spell learned since the last look: a call (the game prints the line).
local had
timer.every(2, function()
  if not settings.get("on") then return end
  local k = known()
  local now = {}
  for sp in pairs(LEARN) do now[sp] = k[sp] end
  if had then
    for sp in pairs(LEARN) do
      if now[sp] and not had[sp] then
        call()
        if ui.is_open(CODEX) then codex() end
        break
      end
    end
  end
  had = now
end)

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
  elseif cmd == "codex" then
    if ui.is_open(CODEX) then ui.close(CODEX) return end
    codex()
    ui.open(CODEX)
  elseif s[name] then
    put_on(name, s[name])
  else
    chat.add("Blue Magic Sets: //blu save <name>, //blu <name>, //blu list, //blu delete <name>, //blu codex")
  end
end)
