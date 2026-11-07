-- The chat log to plain text files, one a day per character (the logger add-ons): logs/<character>/<date>.log in the
-- mod's data folder. Lines are gathered as they come and written once a second, as plain words.

local pending = {}

filters.chat(function(line, _, battle)
  if settings.get("on") and (settings.get("battle") or not battle) then
    -- Kept raw: the auto-translate words need the game's dictionary, which only the mod phase reaches.
    pending[#pending + 1] = { os.date("%H:%M:%S "), line }
  end
  return nil
end)

timer.every(1, function()
  if #pending == 0 then return end
  local me = game.player()
  if not me or not me.name or me.name == "" then return end
  local out = {}
  for _, p in ipairs(pending) do out[#out + 1] = p[1] .. text.strip(text.plain(p[2])) end
  pending = {}
  local lines = table.concat(out, "\n") .. "\n"
  fs.append(("logs/%s/%s.log"):format(me.name, os.date("%Y-%m-%d")), lines)
end)
