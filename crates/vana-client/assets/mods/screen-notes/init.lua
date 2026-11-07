-- Notes on the screen (the text add-ons): //note <name> <text>; dragged, a note keeps its place. Kept per character.

local drag

local function notes()
  local s = storage.character
  s.notes = s.notes or {}
  return s.notes
end

local function draw()
  hud.clear()
  if not settings.get("on") then return end
  local scr = hud.screen()
  local i = 0
  for name, n in pairs(notes()) do
    i = i + 1
    n.x = n.x or math.floor(scr.width * 0.4)
    n.y = n.y or math.floor(scr.height * 0.3 + i * 30 * scr.ui_scale)
    hud.text(name, { x = n.x, y = n.y, text = n.text, size = 1.0, colour = { 245, 240, 225 }, bg = { 0, 0, 0, 150 },
      pad = 4 * scr.ui_scale, outline = { 0, 0, 0, 200 } })
    hud.on(name, function(id, e)
      local note = notes()[id]
      if not note then return end
      if e.kind == "drag_start" then
        drag = { note.x, note.y }
      elseif (e.kind == "drag" or e.kind == "drag_end") and drag then
        note.x, note.y = drag[1] + e.dx, drag[2] + e.dy
        hud.set(id, { x = note.x, y = note.y })
        if e.kind == "drag_end" then
          drag = nil
          storage.save()
        end
      end
    end)
  end
end

commands.register("note", function(name, ...)
  if not name then
    chat.add("Screen Notes: //note <name> <text>, //note <name> (removes it), //notes")
    return
  end
  local t = table.concat({ ... }, " ")
  local n = notes()
  if t == "" then
    n[name] = nil
  else
    n[name] = n[name] or {}
    n[name].text = t
  end
  storage.save()
  draw()
end)

commands.register("notes", function()
  local out = {}
  for name, n in pairs(notes()) do out[#out + 1] = name .. ": " .. n.text end
  table.sort(out)
  chat.add("Screen Notes: " .. (#out > 0 and table.concat(out, "; ") or "none"))
end)

local started
started = events.on("frame", function()
  if game.player() and game.player().name ~= "" then
    events.off(started)
    draw()
  end
end)
events.on("settings_changed", draw)
