-- Colonization Reives: which reive we joined, bayld and experience or limit points while in it, the last momentum
-- scores, the momentum bonuses by kind, and the lockout after a removal. Shown while the Reive Mark is on us, or for a
-- while after our reive lines.

local M = {}

local GREEN = { 130, 220, 130 }
local RED = { 235, 110, 100 }

function M.new()
  return { bayld = 0, xp = 0, lp = 0, scores = {}, bonuses = {}, order = {} }
end

function M.read(st, line, ctx)
  local function mark() st.last = os.clock() end
  local who, kind = line:match("^(.-) has joined the (%a+) Reive!")
  if who then
    if who == ctx.me then st.kind, st.joined, st.won, st.removed = kind, true, false, false mark() end
    return true
  end
  who, kind = line:match("^(.-) is victorious in the (%a+) Reive!")
  if who then
    if st.joined then st.won = true mark() end
    return true
  end
  local n
  who, n = line:match("^(.-) obtained (%d+) bayld!")
  if who then
    -- "You have obtained N bayld!" is a quest reward, not the reive's
    if who == ctx.me then st.bayld = st.bayld + tonumber(n) mark() end
    return true
  end
  if not st.joined then return end
  who, n = line:match("^(.-) gains (%d+) experience points%.")
  if who == ctx.me then st.xp = st.xp + tonumber(n) mark() return true end
  who, n = line:match("^(.-) gains (%d+) limit points%.")
  if who == ctx.me then st.lp = st.lp + tonumber(n) mark() return true end
  local s = line:match("^Reive momentum score: (.-)%.$")
  if s then
    table.insert(st.scores, 1, s)
    st.scores[6] = nil
    mark()
    return true
  end
  local b = line:match("^Momentum [Bb]onus: (.-)!$")
  if b then
    if not st.bonuses[b] then st.order[#st.order + 1] = b end
    st.bonuses[b] = (st.bonuses[b] or 0) + 1
    mark()
    return true
  end
  n = line:match("participate in a reive for the next (%d+) minutes?")
  if n then st.lockout = os.clock() + tonumber(n) * 60 mark() return true end
  n = line:match("discharged in (%d+) seconds?")
  if n then st.discharge = os.clock() + tonumber(n) mark() return true end
  if line:find("You have been removed from the") then st.removed = true mark() return true end
  if line:find("You have returned to the") then st.removed, st.discharge = false, nil mark() return true end
end

function M.rows(st, out)
  out[#out + 1] = { type = "text", text = (st.kind and (st.kind .. " Reive") or "Reive") .. (st.won and " \u{2014} victorious" or ""),
    colour = st.won and GREEN or nil }
  if st.discharge and st.discharge > os.clock() then
    out[#out + 1] = { type = "text", text = ("Too far: discharged in %d s"):format(math.ceil(st.discharge - os.clock())), colour = RED }
  end
  if st.removed then out[#out + 1] = { type = "text", text = "Removed from the reive", colour = RED } end
  out[#out + 1] = { type = "text", text = ("Bayld: %d"):format(st.bayld), dim = st.bayld == 0 }
  if st.xp > 0 then out[#out + 1] = { type = "text", text = ("Experience: %d"):format(st.xp) } end
  if st.lp > 0 then out[#out + 1] = { type = "text", text = ("Limit points: %d"):format(st.lp) } end
  if #st.scores > 0 then
    out[#out + 1] = { type = "separator" }
    out[#out + 1] = { type = "text", text = "Momentum scores", dim = true }
    for i, s in ipairs(st.scores) do out[#out + 1] = { type = "text", text = ("%d  %s"):format(i, s) } end
  end
  if #st.order > 0 then
    out[#out + 1] = { type = "separator" }
    out[#out + 1] = { type = "text", text = "Momentum bonuses", dim = true }
    for _, b in ipairs(st.order) do out[#out + 1] = { type = "text", text = ("%s \u{00d7}%d"):format(b, st.bonuses[b]) } end
  end
  if st.lockout and st.lockout > os.clock() then
    local m = math.ceil((st.lockout - os.clock()) / 60)
    out[#out + 1] = { type = "text", text = ("No reive for %d more minute%s"):format(m, m == 1 and "" or "s"), dim = true }
  end
end

-- Shown while the Reive Mark (status 511) is on us, or for two minutes after our last reive line.
function M.active(st, buffs)
  for _, b in ipairs(buffs) do
    if b.id == 511 then return true end
  end
  return st.joined and st.last and os.clock() - st.last < 120
end

return M
