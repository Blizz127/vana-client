-- Pop lists: an Empyrean (or other) NM's pops as a tree, each held or needed and how many lie in the treasure pool
-- (//pops), and the Zeni NMs by path with the seals, pop items, trophies and salts held (//znm).

local EMPY = require("src.empy")
local ZNM = require("src.znm")

local M = {}

local GREEN = { 130, 220, 130 }
local RED = { 235, 120, 105 }
local GOLD = { 232, 200, 120 }

-- What we hold: key items, items in every bag and in the inventory, items in the treasure pool.
local function holdings()
  local h = { ki = {}, all = {}, inv = {}, pool = {} }
  for _, id in ipairs(game.key_items()) do h.ki[id] = true end
  for bag = 0, 17 do
    for _, it in ipairs(game.items(bag) or {}) do
      h.all[it.id] = (h.all[it.id] or 0) + (it.count or 1)
      if bag == 0 then h.inv[it.id] = (h.inv[it.id] or 0) + (it.count or 1) end
    end
  end
  for _, t in ipairs(game.treasure() or {}) do h.pool[t.item] = (h.pool[t.item] or 0) + (t.count or 1) end
  return h
end

local function item_name(id)
  local r = res.item(id)
  return r and r.name or ("item " .. id)
end

local function ki_name(id)
  local r = res.key_item(id)
  return r and r.name or ("key item " .. id)
end

local function held(n, h)
  if n.ki then return h.ki[n.ki] == true end
  return (h.all[n.item] or 0) > 0
end

-- The tree's rows, depth first, indented by depth: the pop and who drops it, green when held, red when needed.
local function tree_rows(nodes, depth, h, rows)
  for _, n in ipairs(nodes) do
    local name = n.ki and ki_name(n.ki) or item_name(n.item)
    local note = ""
    if n.item then
      if held(n, h) and (h.inv[n.item] or 0) == 0 then note = " (not in inventory)" end
      if h.pool[n.item] then note = note .. (" [%d in the pool]"):format(h.pool[n.item]) end
    end
    rows[#rows + 1] = { cells = { string.rep("    ", depth) .. name .. note, n.from .. (n.how ~= "" and ("  " .. n.how) or "") },
      colour = held(n, h) and GREEN or RED }
    if n.pops then tree_rows(n.pops, depth + 1, h, rows) end
  end
  return rows
end

-- An NM by name: exact, else the first whose name starts so, else a * wildcard pattern; any case.
function M.find(q)
  q = q:lower()
  for _, nm in ipairs(EMPY) do
    if nm.name:lower() == q then return nm end
  end
  for _, nm in ipairs(EMPY) do
    if nm.name:lower():sub(1, #q) == q then return nm end
  end
  local pat = "^" .. q:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
  for _, nm in ipairs(EMPY) do
    if nm.name:lower():find(pat) then return nm end
  end
end

M.view = nil

local function nm_texts(nm, h)
  local all = true
  for _, n in ipairs(nm.pops) do all = all and held(n, h) end
  local c = nm.collect
  local collect = c and ("%s: %d / %d"):format(item_name(c[1]), h.all[c[1]] or 0, c[2])
  return all, collect, c and (h.all[c[1]] or 0) >= c[2]
end

function M.show(nm)
  M.view = nm
  local h = holdings()
  local rows = tree_rows(nm.pops, 0, h, {})
  local all, collect, enough = nm_texts(nm, h)
  local els = {
    { type = "text", text = nm.zone .. (nm.note and (" (" .. nm.note .. ")") or ""), dim = true },
    { type = "list", id = "tree", columns = { { title = "Pop" }, { title = "Dropped by" } }, rows = rows,
      height = math.max(3, math.min(16, #rows)) },
    { type = "text", id = "all", text = all and "Every pop held" or "Pops still needed", colour = all and GREEN or nil, dim = not all },
  }
  if collect then els[#els + 1] = { type = "text", id = "collect", text = collect, colour = enough and GREEN or nil } end
  els[#els + 1] = { type = "buttons", id = "more", items = { "Other NMs" } }
  ui.window("pops", { title = nm.name, width = 560, elements = els,
    help = "Green: held; red: still needed. Items count in every bag; a trade needs them in the inventory." })
  ui.open("pops")
end

function M.pick()
  M.view = nil
  local rows = {}
  for _, nm in ipairs(EMPY) do rows[#rows + 1] = { nm.name, nm.zone } end
  ui.window("pops", { title = "Pop lists", width = 460, elements = {
    { type = "list", id = "nms", columns = { { title = "NM" }, { title = "Zone" } }, rows = rows, height = 14 },
  }, help = "Enter on an NM shows its pops." })
  ui.open("pops")
end

-- The Zeni NM window: a page per path, each tier's seals (gold when held), its ZNMs (green: trophy held; gold: pop
-- item held) and the path's salt.
local function znm_rows(list, h)
  local rows = {}
  for _, z in ipairs(list) do
    local have_trophy = z.trophy and (h.all[z.trophy] or 0) > 0
    local have_pop = (h.all[z.pop] or 0) > 0
    rows[#rows + 1] = { cells = { z.name, item_name(z.pop), z.trophy and item_name(z.trophy) or "" },
      colour = have_trophy and GREEN or have_pop and GOLD or nil }
  end
  return rows
end

local function tiers(path)
  local out = {}
  for _, z in ipairs(path.znms) do
    out[z.tier] = out[z.tier] or {}
    table.insert(out[z.tier], z)
  end
  return out
end

local function seal_text(list, h)
  local need, have = {}, true
  for _, s in ipairs(list[1].seals) do
    need[#need + 1] = ki_name(s)
    have = have and h.ki[s] == true
  end
  if #need == 0 then return "No seal needed", nil end
  return "Seals: " .. table.concat(need, ", "), have
end

local function znm_elements(h)
  local names = {}
  for _, p in ipairs(ZNM) do names[#names + 1] = p.path end
  local els = { { type = "tabs", id = "path", items = names } }
  for k, p in ipairs(ZNM) do
    for tier, list in pairs(tiers(p)) do
      local text, have = seal_text(list, h)
      els[#els + 1] = { type = "text", id = ("s%d_%d"):format(k, tier), page = k, text = ("Tier %d  \u{00b7}  %s"):format(tier, text),
        colour = have and GOLD or nil, dim = have == false }
      els[#els + 1] = { type = "list", id = ("t%d_%d"):format(k, tier), page = k, height = #list,
        columns = { { title = "ZNM" }, { title = "Pop item" }, { title = "Trophy" } }, rows = znm_rows(list, h) }
    end
    if p.salt then
      local have = h.ki[p.salt] == true
      els[#els + 1] = { type = "text", id = ("salt%d"):format(k), page = k, text = "Salt: " .. ki_name(p.salt) .. (have and " (held)" or ""),
        colour = have and GREEN or nil, dim = not have }
    end
  end
  return els
end

function M.znm()
  ui.window("znm", { title = "Zeni NMs", width = 620, elements = znm_elements(holdings()),
    help = "Green: its trophy held; gold: its pop item held. Enter on a ZNM: where its ??? is." })
  ui.open("znm")
end

-- Where a ZNM's ??? is, to the log.
function M.where(path, tier, index)
  local list = tiers(ZNM[path])[tier]
  local z = list and list[index]
  if not (z and z.at) then return end
  chat.add(("%s: its ??? is at (%d, %d, %d) in %s."):format(z.name, z.at[1], z.at[2], z.at[3], res.zone(z.at[4]) or ("zone " .. z.at[4])))
end

-- Brings the open windows up to date with what we hold.
function M.refresh()
  local pops, znm = ui.is_open("pops"), ui.is_open("znm")
  if not (pops and M.view) and not znm then return end
  local h = holdings()
  if pops and M.view then
    local nm = M.view
    ui.update("pops", "tree", { rows = tree_rows(nm.pops, 0, h, {}) })
    local all, collect, enough = nm_texts(nm, h)
    ui.update("pops", "all", { text = all and "Every pop held" or "Pops still needed", colour = all and GREEN or false, dim = not all })
    if collect then ui.update("pops", "collect", { text = collect, colour = enough and GREEN or false }) end
  end
  if znm then
    for k, p in ipairs(ZNM) do
      for tier, list in pairs(tiers(p)) do
        local text, have = seal_text(list, h)
        ui.update("znm", ("s%d_%d"):format(k, tier), { text = ("Tier %d  \u{00b7}  %s"):format(tier, text), colour = have and GOLD or false, dim = have == false })
        ui.update("znm", ("t%d_%d"):format(k, tier), { rows = znm_rows(list, h) })
      end
      if p.salt then
        local have = h.ki[p.salt] == true
        ui.update("znm", ("salt%d"):format(k), { text = "Salt: " .. ki_name(p.salt) .. (have and " (held)" or ""), colour = have and GREEN or false, dim = not have })
      end
    end
  end
end

M.EMPY, M.ZNM = EMPY, ZNM
return M
