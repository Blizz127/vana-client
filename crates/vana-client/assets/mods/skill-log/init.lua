-- Skill-ups (the skill-up tracker add-ons): message 38 "<name>'s <skill> skill rises 0.x points" gets the session's
-- total for that skill; //skills lists levels, caps and gains.

local RISES = 38
local gained = {}   -- skill id -> tenths this session
local by_name

local function skill_id(name)
  if not by_name then
    by_name = {}
    for id = 1, 63 do
      local n = res.skill(id)
      if n then by_name[n:lower()] = id end
    end
  end
  return by_name[name:lower()]
end

filters.battle(function(m)
  if m.id ~= RISES or not settings.get("on") or not m.lines or not m.lines[1] then return nil end
  local me = game.player()
  if not me or not m.actor or m.actor.id ~= me.id then return nil end
  local plain = text.strip(m.lines[1])
  local name = plain:match("'s (.-) skill rises")
  local id = name and skill_id(name)
  if not id then return nil end
  gained[id] = (gained[id] or 0) + (m.value or 0)
  local out = {}
  for i, l in ipairs(m.lines) do out[i] = l end
  out[#out] = out[#out] .. (" (+%.1f this session)"):format(gained[id] / 10)
  return out
end)

commands.register("skills", function()
  local s = game.skills()
  local rows = {}
  for _, group in ipairs({ s.combat or {}, s.magic or {} }) do
    for id, v in pairs(group) do
      if (v.level or 0) > 0 then
        rows[#rows + 1] = { id = id, text = ("%s %d%s%s"):format(res.skill(id) or ("skill " .. id), v.level,
          v.capped and " (capped)" or "", gained[id] and ("  +%.1f"):format(gained[id] / 10) or "") }
      end
    end
  end
  table.sort(rows, function(a, b) return a.id < b.id end)
  if #rows == 0 then
    chat.add("Skill-up Log: no skills known yet.")
    return
  end
  for _, r in ipairs(rows) do chat.add(r.text) end
end)
