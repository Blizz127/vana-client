-- Delve: mweya plasm this run (and the total when a line gives it), kills estimated from the gains, the fracture's
-- stage from the "Your ears" lines, the dreadful energy while it lasts, airlixirs found, and the time lines.

local M = {}

local RED = { 235, 110, 100 }

-- The six "Your ears ..." lines, quietest first (inferred: the fracture's progress toward its boss).
local EARS = { "pick up a subtle mumbling sound", "pick up a guttural growl", "pick up a discordant howl",
  "are assaulted by a harsh, grating outcry", "are assaulted by a cacophonous bellow", "are assaulted by a deafening roar" }

function M.new()
  return { plasm = 0, kills = 0, air = { 0, 0, 0 } }
end

-- A gain that is a multiple of 50 (but not of 500, 750 or 10000) is that many kills' worth; anything else one kill.
local function kills_of(n)
  if n % 50 == 0 and n % 500 ~= 0 and n % 750 ~= 0 and n % 10000 ~= 0 then return n // 50 end
  return 1
end

function M.read(st, line, ctx)
  local n, total = line:match("You receive (%d+) corpuscles?, making for a total of (%d+)%.")
  n = n or line:match("You receive (%d+) corpuscles? of mweya plasm%.")
  if n then
    n = tonumber(n)
    st.plasm, st.kills, st.seen = st.plasm + n, st.kills + kills_of(n), true
    st.total = tonumber(total) or (st.total and st.total + n)
    return true
  end
  for i, p in ipairs(EARS) do
    if line:find("Your ears " .. p, 1, true) then st.stage = i return true end
  end
  if line:find("A dreadful energy emanates from deep within the") then st.energy = true return true end
  if line:find("The oppressive energy passes") then st.energy = false return true end
  local plus = line:match("You find an airlixir %+(%d)")
  if plus and st.air[tonumber(plus) + 1] then
    st.air[tonumber(plus) + 1] = st.air[tonumber(plus) + 1] + 1
    return true
  end
  if line:find("You find an airlixir") then st.air[1] = st.air[1] + 1 return true end
  n = line:match("You have (%d+) minutes? %(Earth time%) to complete the battle")
  if n then ctx.set_left(n, "minutes") return true end
  n = line:match("You have only (%d+) seconds? %(Earth time%) remaining")
  if n then ctx.set_left(n, "seconds") return true end
  n = line:match("time in the battle has been reset to (%d+) minute")
  if n then ctx.set_left(n, "minutes") return true end
  if line:find("Your time has expired for this battle") then ctx.set_left(0, "seconds") return true end
end

function M.rows(st, out)
  out[#out + 1] = { type = "text", text = ("Plasm: %d%s"):format(st.plasm, st.total and (" (total %d)"):format(st.total) or "") }
  out[#out + 1] = { type = "text", text = ("Kills (estimate): %d"):format(st.kills), dim = st.kills == 0 }
  if st.stage then
    out[#out + 1] = { type = "gauge", style = "row", label = "Fracture", text = ("%d of 6"):format(st.stage), value = st.stage / 6 }
  end
  if st.energy then out[#out + 1] = { type = "text", text = "A dreadful energy emanates!", colour = RED } end
  local a = st.air
  if a[1] + a[2] + a[3] > 0 then
    out[#out + 1] = { type = "text", text = ("Airlixirs: %d  \u{00b7}  +1: %d  \u{00b7}  +2: %d"):format(a[1], a[2], a[3]) }
  end
end

return M
