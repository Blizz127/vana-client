-- The hold: an action packet sent while we move waits, with everything sent after it (a gear mod's midcast set),
-- until we have stood still a moment; then all of it goes, in order.

local M = {}

local STILL = 0.15  -- seconds without moving before the hold lets go
local MAX = 3       -- a hold never lasts longer

local queue = {}    -- packets held, in order: {id, data}
local held_at
local released = {} -- packets we send again: they pass once
local last_pos, moved_at = nil, -math.huge

-- Which actions wait: spells always, items and shots by setting.
M.holds = { items = true, shots = true }

local function is_action(id, data)
  if id == 0x037 then return M.holds.items end
  if id ~= 0x01A or #data < 0x10 then return false end
  local cat = string.unpack("<I2", data, 0x0a + 1)
  return cat == 3 or (cat == 16 and M.holds.shots)
end

-- An outgoing packet (on_out): false to hold it.
function M.out(id, data, now)
  if released[data] then
    released[data] = released[data] > 1 and released[data] - 1 or nil
    return nil
  end
  if #queue > 0 then
    -- Behind a held action everything waits, so it goes out in the order it was sent.
    queue[#queue + 1] = data
    return false
  end
  if is_action(id, data) and now - moved_at < STILL then
    queue[1] = data
    held_at = now
    return false
  end
  return nil
end

-- Each frame: where we stand; the held packets go once we have stood still (or waited too long).
function M.frame(pos, now, send)
  if pos then
    local p = pos.x .. "," .. pos.z
    if last_pos and p ~= last_pos then moved_at = now end
    last_pos = p
  end
  if #queue == 0 then return end
  if now - moved_at >= STILL or now - held_at >= MAX then
    local list = queue
    queue = {}
    for _, d in ipairs(list) do
      released[d] = (released[d] or 0) + 1
      send(d)
    end
  end
end

function M.held() return #queue end

return M
