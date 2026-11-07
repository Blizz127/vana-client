-- What is left (the checklist and spell book add-ons): a job's unlearned spells by level, every area's quests and
-- where we stand in them. One window, two tabs; //left prints summaries too.

local WIN = "completion"
local AREAS = { "San d'Oria", "Bastok", "Windurst", "Jeuno", "Other Areas", "Outlands", "Aht Urhgan", "Crystal War",
  "Abyssea", "Adoulin", "Coalition" }
local DIM = { 150, 150, 150, 255 }
local GOLD = { 232, 200, 120, 255 }

local view = { tab = 1, job = nil, area = 1 }

local function say(t) chat.add("Completion Log: " .. t) end

local function job_names()
  local out = {}
  for id = 1, 22 do out[id] = res.job(id) or tostring(id) end
  return out
end

-- The spells a job learns that we have not, by level: {id, name, level}.
local function unlearned(job)
  local known = {}
  for _, id in ipairs(game.spells()) do known[id] = true end
  local out = {}
  for id = 1, 1023 do
    local r = res.spell(id)
    local lv = r and r.levels and r.levels[job]
    if lv and lv > 0 and lv <= 99 and not known[id] and r.kind ~= 8 then
      out[#out + 1] = { id = id, name = r.name, level = lv }
    end
  end
  table.sort(out, function(a, b) return a.level == b.level and a.name < b.name or a.level < b.level end)
  return out
end

local function spell_rows(job)
  local have = (game.jobs().levels or {})[job] or 0
  local rows = {}
  for _, s in ipairs(unlearned(job)) do
    rows[#rows + 1] = { s.name, tostring(s.level), icon = { kind = "spell", id = s.id }, colour = s.level > have and DIM or nil }
  end
  return rows
end

local function state(q)
  if q.completed and not q.current then return "done" end
  if q.current then return "under way" end
  return ""
end

local function quest_rows(area)
  local list = game.quests()[area - 1] or {}
  local rows = {}
  for _, q in ipairs(list) do
    local s = state(q)
    rows[#rows + 1] = { q.name .. (q.repeatable and " (repeatable)" or ""), s, colour = s == "done" and DIM or (s == "under way" and GOLD or nil) }
  end
  return rows
end

local function main_job()
  local p = game.player()
  return p and p.main_job or 1
end

local function open()
  view.job = view.job or main_job()
  ui.window(WIN, {
    title = "Completion Log", width = 460,
    elements = {
      { type = "tabs", id = "tabs", items = { "Spells", "Quests" }, at = view.tab },
      { type = "choice", id = "job", label = "Job", items = job_names(), at = view.job, page = 1 },
      { type = "list", id = "spells", rows = spell_rows(view.job), height = 12, page = 1,
        columns = { { title = "Spell", width = 330 }, { title = "Level", width = 80, align = "right" } } },
      { type = "choice", id = "area", label = "Area", items = AREAS, at = view.area, page = 2 },
      { type = "list", id = "quests", rows = quest_rows(view.area), height = 12, page = 2,
        columns = { { title = "Quest", width = 320 }, { title = "", width = 90, align = "right" } } },
    },
  })
  ui.open(WIN)
end

ui.on(WIN, function(_, e)
  if e.kind ~= "set" then return end
  if e.id == "tabs" then
    view.tab = e.index
  elseif e.id == "job" then
    view.job = e.index
    ui.update(WIN, "spells", { rows = spell_rows(view.job), at = 1 })
  elseif e.id == "area" then
    view.area = e.index
    ui.update(WIN, "quests", { rows = quest_rows(view.area), at = 1 })
  end
end)

local function job_id(s)
  s = (s or ""):upper()
  for id = 1, 22 do
    if res.job(id) == s then return id end
  end
end

commands.register("left", function(what, arg)
  if not settings.get("on") then return end
  what = (what or ""):lower()
  if what == "" then
    if ui.is_open(WIN) then ui.close(WIN) else open() end
  elseif what == "spells" then
    local job = arg and job_id(arg) or main_job()
    if not job then say("no job " .. arg .. ".") return end
    local have = (game.jobs().levels or {})[job] or 0
    local list, now = unlearned(job), {}
    for _, s in ipairs(list) do
      if s.level <= have then now[#now + 1] = s.name end
    end
    say(("%s: %d spells not learned, %d of them at level %d or under%s"):format(res.job(job), #list, #now, have,
      #now > 0 and (": " .. table.concat(now, ", ", 1, math.min(#now, 12)) .. (#now > 12 and ", ..." or "")) or "."))
  elseif what == "quests" then
    local all = game.quests()
    for i, name in ipairs(AREAS) do
      local done, going, total = 0, 0, 0
      for _, q in ipairs(all[i - 1] or {}) do
        total = total + 1
        if q.current then going = going + 1 elseif q.completed then done = done + 1 end
      end
      if total > 0 then say(("%s: %d of %d done, %d under way."):format(name, done, total, going)) end
    end
  else
    say("//left, //left spells [job], //left quests")
  end
end)
