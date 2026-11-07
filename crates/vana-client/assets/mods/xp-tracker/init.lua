-- Experience, limit and capacity points with their rates per hour (the point-watch add-ons), in an edge window.
-- Gains come from game.stats and game.job_points once a second: a level, merit or job point taken in counts the
-- points that rolled over; losses (a death, merits or job points spent) count nothing.

local LIMIT_PER_MERIT, CAPACITY_PER_JP = 10000, 30000

local last       -- the last reading
local gained     -- kind -> {total, since}

local function reset()
  gained = { exp = { total = 0 }, limit = { total = 0 }, capacity = { total = 0 } }
end
reset()

local function commas(n)
  local s = tostring(math.floor(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

local function rate(kind)
  local g = gained[kind]
  if not g.since then return nil end
  local hours = (os.time() - g.since) / 3600
  if hours < 1 / 60 then return nil end
  local r = g.total / hours
  if r >= 10000 then return ("%.1fk/h"):format(r / 1000) end
  return commas(r) .. "/h"
end

local function reading()
  local s, p = game.stats(), game.player()
  if not s or not p or not p.main_job then return nil end
  local jp = (game.job_points() or {})[p.main_job]
  return {
    job = p.main_job, level = p.main_level, exp = s.exp, exp_next = s.exp_next,
    limit = s.limit_points, merits = s.merit_points, merit_max = s.merit_max,
    capacity = jp and jp.capacity, jp = jp and jp.points, jp_spent = jp and jp.spent,
  }
end

local function add(kind, n)
  if n <= 0 then return end
  local g = gained[kind]
  g.since = g.since or os.time()
  g.total = g.total + n
end

-- What came in since the last reading, by kind.
local function count(a, b)
  if a.job ~= b.job then return end
  if b.level == a.level then
    add("exp", b.exp - a.exp)
  elseif b.level == a.level + 1 then
    add("exp", (a.exp_next - a.exp) + b.exp)
  end
  if a.limit and b.limit then
    add("limit", (b.merits - a.merits) * LIMIT_PER_MERIT + b.limit - a.limit)
  end
  if a.capacity and b.capacity then
    add("capacity", ((b.jp + b.jp_spent) - (a.jp + a.jp_spent)) * CAPACITY_PER_JP + b.capacity - a.capacity)
  end
end

local function rows(r)
  local out = {}
  local function row(label, value, of, kind)
    local per = rate(kind)
    out[#out + 1] = {
      type = "gauge", style = "row", label = per and (label .. "  " .. per) or label,
      text = commas(value) .. "/" .. commas(of), value = of > 0 and value / of or 0,
    }
  end
  if r.exp_next and r.exp_next > 0 then
    row("Experience", r.exp, r.exp_next, "exp")
  end
  if r.limit and r.level >= 75 then
    row(("Merits %d/%d"):format(r.merits, r.merit_max or 0), r.limit, LIMIT_PER_MERIT, "limit")
  end
  if r.capacity and r.level >= 99 then
    row(("Job Points %d"):format(r.jp), r.capacity, CAPACITY_PER_JP, "capacity")
  end
  return out
end

local function tick()
  local r = reading()
  if not r then return end
  if last then count(last, r) end
  last = r
  if not settings.get("on") then
    ui.close("xp")
    return
  end
  local els = rows(r)
  if #els == 0 then
    ui.close("xp")
    return
  end
  ui.window("xp", {
    edge = true, resize = true, width = 300, title = "XP",
    heading = ("%s %d"):format(res.job(r.job) or "", r.level or 0), elements = els,
  })
  ui.open("xp")
end

timer.every(1, tick)
events.on("job_change", function() last = nil end)
events.on("settings_changed", tick)

commands.register("xp", function(cmd)
  if (cmd or ""):lower() == "reset" then
    reset()
    chat.add("XP Tracker: the rates start again.")
  else
    chat.add("XP Tracker: //xp reset starts the rates again.")
  end
end)
