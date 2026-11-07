-- Omen (Reisenjima Henge): the floor, its objective and whether it is cleared, the omens, the bonus objectives' timer
-- and the numbered bonus objectives with their progress.

local M = {}

local GREEN = { 130, 220, 130 }
local RED = { 235, 110, 100 }

-- Bonus objectives by a phrase of theirs, most particular first: label, a damage threshold rather than a count, and
-- where the count is when it is not the first number.
local KINDS = {
  { "single magic burst", "Magic burst damage", true },
  { "without performing a magic burst", "Nuke damage (no burst)", true },
  { "single weapon skill", "Weapon skill damage", true },
  { "single auto%-attack", "Melee round damage", true },
  { "HP %d+ times?", "Cures", false, "HP (%d+) times?" },
  { "skillchain", "Skillchains" },
  { "critical hit", "Critical hits" },
  { "magic burst", "Magic bursts" },
  { "physical weapon skill", "Physical weapon skills" },
  { "elemental weapon skill", "Elemental weapon skills" },
  { "weapon skill", "Weapon skills" },
  { "spell", "Spells" },
  { "abilit", "Abilities" },
  { "foe", "Kills" },
}

local function kind_of(rest)
  for _, k in ipairs(KINDS) do
    if rest:find(k[1]) then return k end
  end
end

-- Boss and treasure floors have no bonus objectives.
local function quiet(obj)
  return obj and (obj:find("^Vanquish the Glassy") or obj:find("^Vanquish %a+$") or obj:find("treasure portent"))
end

function M.new()
  return { floor = 1, bonus = {} }
end

local function bonus(st, slot, rest)
  local k = kind_of(rest)
  if not k then return end
  local b = st.bonus[slot] or {}
  st.bonus[slot] = b
  b.label, b.damage = k[2], k[3]
  local n = tonumber(rest:match(k[4] or "(%d+)"))
  if rest:find("^You have failed to") then
    b.state = "failed"
  elseif rest:find("^You have ") then
    -- progress, or done; a damage objective's only progress line is its success
    if b.damage then
      b.state = "done"
    else
      b.cur = n
      if b.target and n and n >= b.target then b.state = "done" end
    end
  else
    b.state, b.cur = nil, 0
    b.target = n
  end
end

function M.read(st, line, ctx)
  if line:find("^Vanquish") or line:find("^Open %d+ treasure portents?%.") then
    if st.cleared then st.bonus, st.bonus_ends = {}, nil end
    st.objective, st.cleared = line:gsub("%.$", ""), false
    return true
  end
  if line:find("The light shall come even if you fail to obey") then
    if st.cleared then st.bonus, st.bonus_ends = {}, nil end
    st.objective, st.cleared = "No objective: the light comes regardless", false
    return true
  end
  if line:find("A spectral light flares up") then st.cleared = true return true end
  local n = line:match("(%d+) omens from your foes")
  if n then st.omens = tonumber(n) return true end
  n = line:match("You have (%d+) seconds? remaining%.")
  if n then st.bonus_ends, st.bonus_len = os.clock() + tonumber(n), tonumber(n) return true end
  n = line:match("Your stay has been extended by (%d+) minutes?%.")
  if n then
    -- each floor after the first brings more time
    st.floor = st.floor + 1
    ctx.extend(tonumber(n) * 60)
    return true
  end
  n = line:match("Mission failure in (%d+) minutes?")
  if n then ctx.set_left(n, "minutes") return true end
  local slot, rest = line:match("^(%d+): (.+)$")
  if slot and tonumber(slot) <= 10 then
    bonus(st, tonumber(slot), rest)
    return true
  end
end

function M.rows(st, out)
  out[#out + 1] = { type = "text", text = ("Floor %d%s"):format(st.floor, st.omens and ("  \u{00b7}  Omens: %d"):format(st.omens) or "") }
  out[#out + 1] = { type = "text", text = (st.objective or "Objective: not seen yet") .. (st.cleared and " \u{2014} cleared" or ""),
    colour = st.cleared and GREEN or nil, dim = not st.objective }
  if quiet(st.objective) then return end
  local timed_out = false
  if st.bonus_ends then
    local left = math.max(0, math.floor(st.bonus_ends - os.clock()))
    timed_out = left == 0
    out[#out + 1] = { type = "gauge", style = "row", label = "Bonus objectives", text = ("%d:%02d"):format(left // 60, left % 60),
      value = st.bonus_len and st.bonus_len > 0 and left / st.bonus_len or 0 }
  end
  for slot = 1, 10 do
    local b = st.bonus[slot]
    if b then
      local done = b.state == "done"
      local failed = b.state == "failed" or (timed_out and not done)
      local progress
      if b.damage then
        progress = b.target and ("at least %d"):format(b.target) or ""
      else
        progress = ("%s/%s"):format(b.cur or "?", b.target or "?")
      end
      out[#out + 1] = { type = "text", text = ("%d  %s  %s"):format(slot, b.label, progress),
        colour = done and GREEN or failed and RED or nil }
    end
  end
end

return M
