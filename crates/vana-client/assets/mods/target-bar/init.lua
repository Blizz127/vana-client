-- A large HP bar for the target (the enemy bar add-ons): name, HP %, distance, and the line the game prints when it
-- readies a move or starts a spell (s2c 0x028 categories 7 and 8), until it finishes or 5 s pass. Dragged, it stays.

local STARTS = { [7] = true, [8] = true }
local DONE = { [3] = true, [4] = true, [11] = true }
local SHOW_SECS = 5

local doing = {}   -- actor id -> {text, at}
local last_sig
local drag_from

local function place()
  local p = storage.account.place or {}
  return p.x or 0, p.y or 0
end

events.on("action", function(a)
  if STARTS[a.category] then
    local t = a.targets and a.targets[1]
    local r = t and t.results and t.results[1]
    if r and r.message and r.message > 0 and a.param ~= 28787 then
      local m = res.message(r.message, { actor = a.actor, target = t.id, values = { r.value } })
      if m then doing[a.actor] = { text = text.strip(m.text), at = os.clock() } end
    else
      doing[a.actor] = nil
    end
  elseif DONE[a.category] then
    doing[a.actor] = nil
  end
end)

local function clear()
  if last_sig then hud.clear() end
  last_sig = nil
end

events.on("frame", function()
  if not settings.get("on") then return clear() end
  local t = game.target()
  if not t or not t.hpp then return clear() end
  local d = doing[t.id]
  if d and os.clock() - d.at > SHOW_SECS then
    doing[t.id], d = nil, nil
  end
  local scr = hud.screen()
  local u = scr.ui_scale
  local dx, dy = place()
  local sig = table.concat({ t.id, t.hpp, ("%.1f"):format(t.distance or 0), d and d.text or "", scr.width, scr.height,
    u, dx, dy, settings.get("width") }, "|")
  if sig == last_sig then return end
  last_sig = sig
  local w, h = settings.get("width") * u, 10 * u
  local x = math.floor((scr.width - w) / 2 + dx)
  local y = math.floor(scr.height * 0.12 + dy)
  hud.bar("bar", { x = x, y = y, w = w, h = h, value = t.hpp / 100, kind = "hp" })
  hud.rect("grip", { x = x, y = y - 22 * u, w = w, h = 22 * u + h, colour = { 0, 0, 0, 1 } })
  hud.text("name", { x = x, y = y - 20 * u, text = t.name or "", size = 1.0, colour = { 240, 235, 220 },
    outline = { 0, 0, 0, 220 } })
  hud.text("hpp", { x = x + w, y = y - 20 * u, text = t.hpp .. "%", size = 1.0, align = "right",
    colour = { 255, 255, 255 }, outline = { 0, 0, 0, 220 } })
  hud.text("dist", { x = x + w, y = y + h + 3 * u, text = ("%.1f"):format(t.distance or 0), size = 0.8,
    align = "right", colour = { 210, 210, 215 }, outline = { 0, 0, 0, 220 } })
  if d then
    hud.text("doing", { x = x, y = y + h + 3 * u, text = d.text, size = 0.9, colour = { 255, 220, 140 },
      outline = { 0, 0, 0, 220 } })
  else
    hud.remove("doing")
  end
  hud.on("grip", function(_, e)
    if e.kind == "drag_start" then
      drag_from = { place() }
    elseif (e.kind == "drag" or e.kind == "drag_end") and drag_from then
      storage.account.place = { x = drag_from[1] + e.dx, y = drag_from[2] + e.dy }
      last_sig = nil
      if e.kind == "drag_end" then
        drag_from = nil
        storage.save()
      end
    end
  end)
end)
