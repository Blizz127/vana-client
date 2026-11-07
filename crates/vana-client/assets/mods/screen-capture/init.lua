-- //shot: a screenshot filed as <character>/<zone>/<date time>; //record [stop]: a video of the window.

local function where()
  local me = game.player()
  local who = me and me.name ~= "" and me.name or "unknown"
  local zone = (res.zone(game.zone() or 0) or "zone"):gsub("[^%w%s%-]", ""):gsub("%s+", " ")
  return who, zone
end

commands.register("shot", function()
  if not settings.get("on") then return end
  local who, zone = where()
  local name = client.screenshot(("%s/%s/%s"):format(who, zone, os.date("%Y-%m-%d %H.%M.%S")))
  chat.add("Screen Capture: " .. name)
end)

commands.register("record", function(arg)
  if not settings.get("on") then return end
  if (arg or ""):lower() == "stop" then
    client.stop_recording()
    chat.add("Screen Capture: recording stopped.")
    return
  end
  local who, zone = where()
  client.record(("%s %s %s"):format(who, zone, os.date("%Y-%m-%d %H.%M.%S")))
  chat.add("Screen Capture: recording; //record stop ends it.")
end)
