-- The engine both front ends share: the game through a small adapter (tests swap it), held items resolved for the
-- wanted slots, equip packets built and sent in order, the equipment just sent remembered until the server agrees,
-- and the actions we hold and send again with the gear around them.

local M = {}

-- ---- The game, through one table (tests replace it) ----

M.H = {
  player = function() return game.player() end,
  equipment = function() return game.equipment() end,
  items = function(bag) return game.items(bag) end,
  item = function(id) return res.item(id) end,
  inject = function(data) packets.inject_out(data) end,
  now = function() return clock() end,
}

-- Equipment slots 0..15 by name.
M.SLOTS = { "main", "sub", "range", "ammo", "head", "body", "hands", "legs", "feet", "neck", "waist", "left_ear",
  "right_ear", "left_ring", "right_ring", "back" }

-- Bags by id and by name.
M.BAG_NAMES = { [0] = "inventory", "safe", "storage", "temporary", "locker", "satchel", "sack", "case", "wardrobe",
  "safe2", "wardrobe2", "wardrobe3", "wardrobe4", "wardrobe5", "wardrobe6", "wardrobe7", "wardrobe8", "recycle" }
M.BAG_IDS = {}
for id, name in pairs(M.BAG_NAMES) do M.BAG_IDS[name] = id end

-- The bags gear is worn from.
M.EQUIP_BAGS = { 0, 8, 10, 11, 12, 13, 14, 15, 16 }

-- ---- Item records and augments ----

local records = {}
function M.record(id)
  local r = records[id]
  if r == nil then
    r = M.H.item(id) or false
    records[id] = r
  end
  return r or nil
end

-- Augment lines by extdata (res.augments works only in the mod phase: the frame handler fills this).
M.augments = {}
local pending_augs = {}

function M.want_augments(extdata, id)
  if extdata and M.augments[extdata] == nil then pending_augs[extdata] = id or 0 end
end

-- In the mod phase: decodes what the hooks asked for, a few each frame.
function M.decode_augments()
  local n = 0
  for ext, id in pairs(pending_augs) do
    pending_augs[ext] = nil
    local ok, a = pcall(res.augments, id, ext)
    M.augments[ext] = (ok and a and a.lines) or {}
    n = n + 1
    if n >= 32 then return end
  end
end

-- Letters, digits, '-' and ',' alone, lowercased: the loose form augments are compared in.
local function loose(s)
  return (tostring(s):lower():gsub("[^%w%-,]", ""))
end

-- Every wanted augment matches a different one of the item's.
function M.augments_match(extdata, wanted, id)
  if not wanted or #wanted == 0 then return true end
  if not extdata then return false end
  local have = M.augments[extdata]
  if not have then
    M.want_augments(extdata, id)
    return false
  end
  local free = {}
  for i, a in ipairs(have) do free[i] = loose(a) end
  for _, w in ipairs(wanted) do
    local lw, found = loose(w), false
    for i, a in ipairs(free) do
      if a == lw then
        table.remove(free, i)
        found = true
        break
      end
    end
    if not found then return false end
  end
  return true
end

-- ---- What is worn: the server's, with what we sent over it ----

-- slot -> {bag, index, id, at}: sent, not yet seen worn.
M.sent = {}
M.SENT_HOLD = 2

function M.worn()
  local now, eq = M.H.now(), M.H.equipment() or {}
  local out = {}
  for s = 0, 15 do
    local cur = eq[s] or {}
    local p = M.sent[s]
    if p and (now - p.at > M.SENT_HOLD or (cur.bag == p.bag and cur.slot == p.index)) then
      M.sent[s], p = nil, nil
    end
    if p then
      out[s] = p.index ~= 0 and { bag = p.bag, index = p.index, id = p.id } or nil
    elseif cur.id then
      out[s] = { bag = cur.bag, index = cur.slot, id = cur.id }
    end
  end
  return out
end

-- ---- Resolving a want list ----

local function bit(n) return 1 << n end

-- Can we wear it now: our main job's bit, its level, the slot (races are not checked: the game refuses).
local function wearable(r, slot, p)
  if not r or not r.slots or r.slots & bit(slot) == 0 then return false end
  if p.main_job and r.jobs and r.jobs ~= 0 and r.jobs & bit(p.main_job) == 0 then return false end
  if r.level and p.main_level and r.level > p.main_level then return false end
  return true
end

local function named(r, name, log_names)
  if not r then return false end
  local n = name:lower()
  return (r.name and r.name:lower() == n) or (log_names and r.log_name and r.log_name:lower() == n) or false
end

-- `wants`: {[slot] = {name=, augments=, bag=, priority=, test=, remove=true}} (`test(extdata)`: a further check on the
-- item); `opt`: {log_names, bags (search order)}.
-- Returns the changes, in send order: {slot, bag, index, id, priority} (index 0 takes the slot off).
function M.resolve(wants, opt)
  local p = M.H.player() or {}
  local worn = M.worn()
  local out, used, left = {}, {}, {}
  local function key(bag, index) return bag * 256 + index end
  for slot, w in pairs(wants) do
    local cur = worn[slot]
    if w.remove then
      if cur then out[#out + 1] = { slot = slot, bag = 0, index = 0, priority = w.priority or 0 } end
    else
      local r = cur and M.record(cur.id)
      local ext
      if cur then
        for _, it in ipairs(M.H.items(cur.bag) or {}) do
          if it.slot == cur.index then ext = it.extdata break end
        end
      end
      if cur and named(r, w.name, opt.log_names) and (not w.bag or w.bag == cur.bag) and M.augments_match(ext, w.augments, cur.id)
        and (not w.test or w.test(ext)) then
        used[key(cur.bag, cur.index)] = true
      else
        left[slot] = w
      end
    end
  end
  -- Worn items another wanted slot keeps are not taken.
  for s, c in pairs(worn) do
    if not left[s] and not wants[s] then used[key(c.bag, c.index)] = true end
  end
  if next(left) then
    for _, bag in ipairs(opt.bags or M.EQUIP_BAGS) do
      for _, it in ipairs(M.H.items(bag) or {}) do
        local lock = it.locked or 0
        if (lock == 0 or lock == 5) and not used[key(bag, it.slot)] then
          local r = M.record(it.id)
          for slot, w in pairs(left) do
            if named(r, w.name, opt.log_names) and (not w.bag or w.bag == bag) and wearable(r, slot, p)
              and M.augments_match(it.extdata, w.augments, it.id) and (not w.test or w.test(it.extdata)) then
              out[#out + 1] = { slot = slot, bag = bag, index = it.slot, id = it.id, priority = w.priority or 0 }
              used[key(bag, it.slot)] = true
              left[slot] = nil
              break
            end
          end
        end
        if not next(left) then break end
      end
      if not next(left) then break end
    end
  end
  table.sort(out, function(a, b)
    if a.priority ~= b.priority then return a.priority > b.priority end
    return a.slot < b.slot
  end)
  return out, left
end

-- ---- Packets ----

function M.equip_packet(c)
  return packets.build(0x050, string.pack("BBBB", c.index, c.slot, c.bag, 0))
end

function M.equipset_packet(list)
  local body = { string.pack("BBBB", #list, 0, 0, 0) }
  for i = 1, 16 do
    local c = list[i]
    body[#body + 1] = c and string.pack("BBBB", c.index, c.slot, c.bag, 0) or string.pack("BBBB", 0, 0, 0, 0)
  end
  return packets.build(0x051, table.concat(body))
end

-- The changes as packets: one equipset (`style` "set"), single equips ("single"), or single ones up to `max`
-- pieces and an equipset above ("auto"). Each sent piece is remembered as worn.
function M.packets(list, style, max)
  local out = {}
  if #list == 0 then return out end
  if style == "set" or (style == "auto" and #list > (max or 2)) then
    out[1] = M.equipset_packet(list)
  else
    for _, c in ipairs(list) do out[#out + 1] = M.equip_packet(c) end
  end
  local now = M.H.now()
  for _, c in ipairs(list) do
    M.sent[c.slot] = { bag = c.bag, index = c.index, id = c.id, at = now }
  end
  return out
end

function M.send(pkts)
  for _, d in ipairs(pkts) do M.H.inject(d) end
end

-- ---- Actions on the wire ----

-- c2s 0x01A: target @4, its index @8, category @0x0a, param @0x0c; c2s 0x037: target @4, its index @0x0c, the item's
-- index @0x0e and bag @0x10.
function M.parse_action(p)
  local d = p.data
  if p.id == 0x01A and #d >= 0x10 then
    local target, tindex, cat, param = string.unpack("<I4I2I2I4", d, 5)
    if cat == 3 or cat == 7 or cat == 9 or cat == 16 then
      return { packet = d, kind = "action", category = cat, param = param, target = target, tindex = tindex }
    end
  elseif p.id == 0x037 and #d >= 0x14 then
    local target = string.unpack("<I4", d, 5)
    local tindex = string.unpack("<I2", d, 0x0c + 1)
    local index = string.unpack("B", d, 0x0e + 1)
    local bag = string.unpack("<I4", d, 0x10 + 1)
    return { packet = d, kind = "item", category = 0, bag = bag, index = index, target = target, tindex = tindex }
  end
end

-- The action's packet aimed at another target (id, index).
function M.retarget(act, id, index)
  local d = act.packet
  if act.kind == "item" then
    act.packet = d:sub(1, 4) .. string.pack("<I4", id) .. d:sub(9, 12) .. string.pack("<I2", index) .. d:sub(15)
  else
    act.packet = d:sub(1, 4) .. string.pack("<I4I2", id, index) .. d:sub(11)
  end
  act.target, act.tindex = id, index
end

-- The action's name-table id for res: spells as sent, weapon skills as sent, abilities 0x200 on.
function M.res_id(act)
  if act.category == 9 then return act.param + 0x200 end
  return act.param
end

-- Every item name a profile's sets hold: tables walked for slot keys (`slot_of`), each value a name or a table with
-- `name` / `Name`; nested sets followed once each.
function M.set_names(root, slot_of)
  local out, seen, found = {}, {}, {}
  local function walk(t)
    if type(t) ~= "table" or seen[t] then return end
    seen[t] = true
    for k, v in pairs(t) do
      if slot_of(k) then
        local n = type(v) == "string" and v or (type(v) == "table" and (rawget(v, "name") or rawget(v, "Name")))
        local l = type(n) == "string" and n:lower() or ""
        if l ~= "" and l ~= "empty" and l ~= "remove" and l ~= "ignore" and l ~= "displaced" and not found[l] then
          found[l] = true
          out[#out + 1] = n
        end
      elseif type(v) == "table" then
        walk(v)
      end
    end
  end
  walk(root)
  table.sort(out)
  return out
end

return M
