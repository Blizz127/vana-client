-- Effects on the target from anyone (the debuff tracker add-ons): from action results naming a status (landed),
-- removed, worn off or the bearer defeated (the client's Timers read the same messages).

local LANDED = { [127] = true, [186] = true, [230] = true, [236] = true, [237] = true, [242] = true, [243] = true,
  [266] = true, [267] = true, [268] = true, [271] = true, [277] = true, [278] = true, [319] = true, [320] = true }
local REMOVED = { [83] = true, [123] = true, [159] = true, [321] = true, [341] = true, [343] = true, [378] = true,
  [453] = true }
local WORN = { [204] = true, [206] = true }
local DEFEATED = { [6] = true, [20] = true, [97] = true }

local on = {}   -- target id -> {status id -> landed at}
local last_sig

local function put(target, status, at)
  on[target] = on[target] or {}
  on[target][status] = at
end

local function take(target, status)
  if on[target] then on[target][status] = nil end
end

events.on("action", function(a)
  for _, t in ipairs(a.targets or {}) do
    for _, r in ipairs(t.results or {}) do
      if LANDED[r.message] and r.value > 0 then
        put(t.id, r.value, os.clock())
      elseif REMOVED[r.message] then
        take(t.id, r.value)
      end
    end
  end
end)

events.on("battle_message", function(_, target, message, param1)
  if WORN[message] then
    take(target, param1)
  elseif DEFEATED[message] then
    on[target] = nil
  end
end)

events.on("zone_change", function() on = {} end)

local function clear()
  if last_sig then hud.clear() end
  last_sig = nil
end

events.on("frame", function()
  if not settings.get("on") then return clear() end
  local t = game.target()
  local list = t and on[t.id]
  if not list or not next(list) then return clear() end
  local ids = {}
  for id in pairs(list) do ids[#ids + 1] = id end
  table.sort(ids)
  local scr = hud.screen()
  local u = scr.ui_scale
  local panel = ui.native.rect("target")
  local sig = table.concat(ids, ",") .. "|" .. t.id .. "|" .. (panel and (panel.x .. "," .. panel.y .. "," .. panel.h) or "")
    .. "|" .. scr.width .. "|" .. u .. "|" .. math.floor(os.clock() / 5)
  if sig == last_sig then return end
  last_sig = sig
  hud.clear()
  local size, gap = 22 * u, 3 * u
  local x0, y0
  if panel and panel.shown then
    x0, y0 = panel.x, panel.y - size - gap
  else
    x0, y0 = math.floor(scr.width / 2 - #ids * (size + gap) / 2), math.floor(48 * u)
  end
  for i, id in ipairs(ids) do
    local key = "d" .. id
    local ago = math.floor(os.clock() - list[id])
    hud.icon(key, { kind = "status", id = id, x = x0 + (i - 1) * (size + gap), y = y0, size = size,
      tip = { title = res.status(id) or ("Effect " .. id), text = ("Landed %d:%02d ago"):format(ago // 60, ago % 60) } })
  end
end)
