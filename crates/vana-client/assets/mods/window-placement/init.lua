-- The window's place and size per character, always-on-top and the client's priority (the window position add-ons).
-- Places are only known where the system tells them (not on Wayland).

local PRIORITY = { ["Low"] = "low", ["Below Normal"] = "below_normal", ["Normal"] = "normal" }

local function apply_flags()
  if not settings.get("on") then return end
  client.set_window({ top = settings.get("top") })
  client.set_priority(PRIORITY[settings.get("priority")] or "normal")
end

local function restore()
  local p = storage.character.window
  if settings.get("on") and p then
    client.set_window({ x = p.x, y = p.y, w = p.w, h = p.h })
  end
  apply_flags()
end

local started
started = events.on("frame", function()
  if game.player() and game.player().name ~= "" then
    events.off(started)
    restore()
  end
end)
events.on("settings_changed", apply_flags)

commands.register("winpos", function(cmd)
  cmd = (cmd or ""):lower()
  if cmd == "save" then
    local w = client.window()
    storage.character.window = { x = w.x, y = w.y, w = w.w, h = w.h }
    storage.save()
    chat.add(("Window Placement: %dx%d%s kept for this character."):format(w.w, w.h,
      w.x and (" at " .. w.x .. "," .. w.y) or ""))
  elseif cmd == "forget" then
    storage.character.window = nil
    storage.save()
    chat.add("Window Placement: forgotten.")
  else
    chat.add("Window Placement: //winpos save, //winpos forget")
  end
end)
