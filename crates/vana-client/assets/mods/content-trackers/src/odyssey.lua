-- Odyssey (Sheol A / B / C and Sheol: Gaol, from Rabao): the area and difficulty from Rabao's "Entering" line, segments
-- this run and their total, izzat, Moogle Mastery, Gaol's RP, the translocators unlocked; the last run's segments
-- back in Rabao, and when another moglophone may be ready.

local M = {}

local GREEN = { 130, 220, 130 }

M.RABAO = 247
-- The Walk of Echoes zones hold Selbina's fights too: only a run entered from Rabao is Odyssey.
M.ZONES = { [298] = true, [279] = true }

-- The moglophone key item, and how long until another is ready (the moglophone helpers' figure, not the game's).
local PHONE, RECHARGE = 3212, 20 * 3600

-- Rabao's "Entering Sheol A: Normal." and the like: area and difficulty.
function M.entering(line)
  local s = line:match("^Entering (Sheol[^%.]*)%.")
  if not s then return nil end
  if s:find("^Sheol: Gaol") then return { area = "Sheol: Gaol", diff = s:match("^Sheol: Gaol: (.+)$") } end
  return { area = s:match("^(Sheol %u)") or s, diff = s:match("^Sheol %u: (.+)$") }
end

function M.new(armed)
  return { area = armed and armed.area, diff = armed and armed.diff, segments = 0, izzat = 0, unlocked = {} }
end

function M.read(st, line, ctx)
  local n, total = line:match("You receive (%d+) moogle segments? for a total of (%d+)%.")
  if n then st.segments, st.seg_total = st.segments + tonumber(n), tonumber(total) return true end
  n, total = line:match("You receive (%d+) izzat, for a total of (%d+)%.")
  if n then st.izzat, st.izzat_total = st.izzat + tonumber(n), tonumber(total) return true end
  if line:find("izzat total is at its maximum") then st.izzat_max = true return true end
  local lv = line:match("Moogle Mastery is now level (%u+)") or line:match("effects of Moogle Mastery level (%u+)")
  if lv then st.mastery = lv return true end
  local f = line:match("translocator in Perdition (%u%-%d)")
  if f then st.unlocked[#st.unlocked + 1] = f return true end
  local from
  n, from, total = line:match("You receive (%d+) RP from (.-) for a total of (%d+)%.")
  if n then st.rp, st.rp_from = tonumber(total), from return true end
  n = line:match("Your stay has been extended by (%d+) minutes?%.")
  if n then ctx.extend(tonumber(n) * 60) return true end
  n = line:match("Leaving the instance in (%d+) minutes?")
  if n then ctx.set_left(n, "minutes") return true end
end

local function title(a, d)
  return (a or "Odyssey") .. (d and (" (" .. d .. ")") or "")
end

function M.rows(st, out)
  out[#out + 1] = { type = "text", text = title(st.area, st.diff) }
  out[#out + 1] = { type = "text", text = ("Segments: %d%s"):format(st.segments, st.seg_total and (" (total %d)"):format(st.seg_total) or ""),
    dim = st.segments == 0 }
  if st.izzat > 0 or st.izzat_max then
    out[#out + 1] = { type = "text", text = st.izzat_max and "Izzat: at its maximum" or ("Izzat: %d (total %d)"):format(st.izzat, st.izzat_total or 0) }
  end
  if st.mastery then out[#out + 1] = { type = "text", text = "Moogle Mastery: " .. st.mastery } end
  if st.rp then out[#out + 1] = { type = "text", text = ("RP: %d%s"):format(st.rp, st.rp_from and (" (last from " .. st.rp_from .. ")") or "") } end
  if #st.unlocked > 0 then out[#out + 1] = { type = "text", text = "Translocators: " .. table.concat(st.unlocked, ", "), colour = GREEN } end
end

-- The run ending: what Rabao shows after it.
function M.finish(st)
  return { area = st.area, diff = st.diff, segments = st.segments, total = st.seg_total }
end

-- Notes the moglophone going (it is used up on entering): from then the wait for another counts.
function M.watch_phone(keys, store)
  local held = false
  for _, id in ipairs(keys) do
    if id == PHONE then held = true break end
  end
  if store.phone_held and not held then
    store.phone_used = os.time()
    if storage.save then storage.save() end
  end
  store.phone_held = held
  return held
end

-- Rabao's rows: the last run, and the moglophone.
function M.rabao_rows(last, store, held, out)
  if last then
    out[#out + 1] = { type = "text", text = "Last run: " .. title(last.area, last.diff) }
    out[#out + 1] = { type = "text", text = ("Segments: %d%s"):format(last.segments, last.total and (" (total %d)"):format(last.total) or "") }
  end
  if held then
    out[#out + 1] = { type = "text", text = "Moglophone: in hand", colour = GREEN }
  elseif store.phone_used then
    local left = store.phone_used + RECHARGE - os.time()
    if left > 0 then
      out[#out + 1] = { type = "text", text = ("Another moglophone in about %d:%02d"):format(left // 3600, left % 3600 // 60), dim = true,
        tip = "Twenty hours from the last one going, as the moglophone helpers count; the game does not say." }
    else
      out[#out + 1] = { type = "text", text = "Another moglophone should be ready", colour = GREEN }
    end
  end
end

return M
