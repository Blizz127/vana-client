-- The weather we wait for (the weather add-ons): a line and a call when a watched weather starts or ends in the zone.

local function watched(name)
  name = (name or ""):lower()
  for w in (settings.get("weathers") or ""):gmatch("[^,]+") do
    if w:match("^%s*(.-)%s*$"):lower() == name then return true end
  end
  return false
end

local function say(line)
  chat.add("Weather Watch: " .. line)
  audio.play_ui(17)
  if settings.get("party") then commands.run("/p " .. line) end
end

events.on("weather_change", function(now, before)
  if not settings.get("on") then return end
  local zone = res.zone(game.zone() or 0) or "here"
  local a, b = res.weather(now), res.weather(before)
  if watched(a) then
    say(("%s in %s."):format(a, zone))
  elseif watched(b) then
    say(("%s is over in %s."):format(b, zone))
  end
end)

commands.register("weather", function()
  local t = game.time()
  chat.add(("Weather Watch: %s in %s, %s."):format(res.weather(game.weather()) or "?", res.zone(game.zone() or 0) or "?",
    res.day(t.weekday) or "?"))
end)
