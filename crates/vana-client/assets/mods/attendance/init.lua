-- //attend [note] (the linkshell attendance add-ons): the party, the alliance and players nearby, written with the time
-- and zone to attendance/<date>.txt in the data folder.

commands.register("attend", function(...)
  if not settings.get("on") then return end
  local note = table.concat({ ... }, " ")
  local names, seen = {}, {}
  local function add(n)
    if n and n ~= "" and not seen[n] then
      seen[n] = true
      names[#names + 1] = n
    end
  end
  for _, m in ipairs(game.party()) do add(m.name) end
  if settings.get("nearby") then
    for _, e in ipairs(game.entities({ distance = 50, kinds = { "player" } })) do add(e.name) end
  end
  table.sort(names)
  local zone = res.zone(game.zone() or 0) or ""
  local head = os.date("%H:%M") .. "  " .. zone .. (note ~= "" and ("  " .. note) or "")
  fs.append("attendance/" .. os.date("%Y-%m-%d") .. ".txt", head .. "\n  " .. table.concat(names, ", ") .. "\n")
  chat.add(("Attendance: %d names written."):format(#names))
end)
