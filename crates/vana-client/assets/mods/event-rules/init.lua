-- Command lines run on events (the auto-exec add-ons), from rules.txt in the data folder, one rule a line:
--   event | match | line        (# starts a comment)
-- Events and their match: login (empty), zone (zone name), job (main job, e.g. WAR), gain and lose (an effect's name),
-- hp_below and mp_below (a percent), chat (words in a chat line), day (e.g. Firesday), weather (e.g. Rain).

local FILE = "rules.txt"
local EXAMPLE = [[
# event | match | command line
# zone | Bastok Markets | /echo Back in Bastok
# gain | Sleep | /p I am asleep!
# hp_below | 30 | /p HP low
]]
local rules = {}

local function trim(s)
  return (s:match("^%s*(.-)%s*$"))
end

local function load_rules()
  rules = {}
  local text_ = fs.read(FILE)
  if not text_ then
    fs.write(FILE, EXAMPLE)
    return
  end
  for line in text_:gmatch("[^\r\n]+") do
    if not line:match("^%s*#") and line:find("|", 1, true) then
      local ev, match, cmd = line:match("^([^|]*)|([^|]*)|(.*)$")
      if ev and trim(cmd) ~= "" then
        rules[#rules + 1] = { event = trim(ev):lower(), match = trim(match):lower(), line = trim(cmd) }
      end
    end
  end
end
load_rules()

local function fire(event, test)
  if not settings.get("on") then return end
  for _, r in ipairs(rules) do
    if r.event == event and test(r.match) then commands.run(r.line) end
  end
end

local function named(name)
  name = (name or ""):lower()
  return function(m) return m == "" or m == name end
end

local started
started = events.on("frame", function()
  local me = game.player()
  if me and me.name ~= "" then
    events.off(started)
    fire("login", function() return true end)
  end
end)

events.on("zone_change", function(zone) fire("zone", named(res.zone(zone))) end)
events.on("job_change", function(main) fire("job", named(res.job(main))) end)
events.on("buff_gain", function(id) fire("gain", named(res.status(id))) end)
events.on("buff_lose", function(id) fire("lose", named(res.status(id))) end)
events.on("hpp_change", function(now, before)
  fire("hp_below", function(m) local p = tonumber(m) return p and now < p and before >= p end)
end)
events.on("mpp_change", function(now, before)
  fire("mp_below", function(m) local p = tonumber(m) return p and now < p and before >= p end)
end)
events.on("day_change", function(day) fire("day", named(res.day(day))) end)
events.on("weather_change", function(w) fire("weather", named(res.weather(w))) end)
events.on("chat_message", function(line, sender)
  local me = game.player()
  if me and sender == me.name then return end
  local low = text.plain(line):lower()
  fire("chat", function(m) return m ~= "" and low:find(m, 1, true) ~= nil end)
end)

commands.register("rules", function(cmd)
  if (cmd or ""):lower() == "reload" then
    load_rules()
    chat.add(("Event Rules: %d rules read."):format(#rules))
    return
  end
  if #rules == 0 then
    chat.add("Event Rules: no rules; add them to " .. FILE .. " in this mod's data folder, then //rules reload.")
    return
  end
  for _, r in ipairs(rules) do chat.add(("Event Rules: %s | %s | %s"):format(r.event, r.match, r.line)) end
end)
