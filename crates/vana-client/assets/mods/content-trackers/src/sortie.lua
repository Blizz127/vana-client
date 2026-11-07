-- Sortie (Outer Ra'Kaznar [U1..U3]): our gallimaufry this run and its total, the treasure coffer reports of sectors
-- #A..#H, the temporary items held, the plate's seconds, and the time lines.

local M = {}

local GREEN = { 130, 220, 130 }

function M.new()
  return { gall = 0, coffers = {}, temp = {} }
end

function M.read(st, line, ctx)
  local who, n, total = line:match("^(.-) received (%d+) gallimaufry for a total of (%d+)%.")
  if who then
    if who == ctx.me then st.gall, st.total = st.gall + tonumber(n), tonumber(total) end
    return true
  end
  local l, a, b, c, d = line:match("#(%u) treasure coffer status report: (%d+)/(%d+) #%?: (%d+)/(%d+)%.")
  if l then
    st.coffers[l] = { tonumber(a), tonumber(b), tonumber(c), tonumber(d) }
    return true
  end
  local item = line:match("You obtain the temporary item: (.-)!")
  if item then st.temp[item] = true return true end
  item = line:match("You lose the temporary item: (.-)%.")
  if item then st.temp[item] = nil return true end
  n = line:match("worth of potency%. It currently has (%d+) seconds? remaining")
  if n then st.plate = tonumber(n) return true end
  n = line:match("Your stay within %a+ has been extended by (%d+) minute")
  if n then ctx.extend(tonumber(n) * 60) return true end
  n = line:match("Exiting in (%d+) minutes?")
  if n then ctx.set_left(n, "minutes") return true end
end

function M.rows(st, out)
  out[#out + 1] = { type = "text", text = ("Gallimaufry: %d%s"):format(st.gall, st.total and (" (total %d)"):format(st.total) or ""),
    dim = st.gall == 0 }
  for _, l in ipairs({ "A", "B", "C", "D", "E", "F", "G", "H" }) do
    local c = st.coffers[l]
    if c then
      local done = c[1] >= c[2] and c[3] >= c[4]
      out[#out + 1] = { type = "text", text = ("#%s  %d/%d   #?: %d/%d"):format(l, c[1], c[2], c[3], c[4]), colour = done and GREEN or nil }
    else
      out[#out + 1] = { type = "text", text = ("#%s  no report yet"):format(l), dim = true }
    end
  end
  local names = {}
  for k in pairs(st.temp) do names[#names + 1] = k end
  table.sort(names)
  if #names > 0 then out[#out + 1] = { type = "text", text = "Temporary items: " .. table.concat(names, ", ") } end
  if st.plate then out[#out + 1] = { type = "text", text = ("Plate: %d:%02d of potency"):format(st.plate // 60, st.plate % 60) } end
end

return M
