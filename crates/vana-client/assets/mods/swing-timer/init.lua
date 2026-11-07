-- Time to the next auto-attack (the swing timer add-ons): from our last melee round (s2c 0x028 category 1) and the
-- main weapon's delay (1/60 s; hand-to-hand adds the unarmed 480). Haste and dual wield are not counted.

local MELEE, ENGAGED, MAIN = 1, 1, 0
local last_round
local shown = false

local function delay()
  local eq = game.equipment() or {}
  local main = eq[MAIN]
  local r = main and main.id and res.item(main.id)
  local d = r and r.delay or 0
  if not r or r.skill == 1 then d = d + 480 end
  return math.max(d, 60) / 60
end

events.on("action", function(a)
  local me = game.player()
  if me and a.actor == me.id and a.category == MELEE then last_round = os.clock() end
end)

events.on("frame", function()
  local me = game.player()
  if not settings.get("on") or not me or me.status ~= ENGAGED or not last_round then
    if shown then hud.clear() end
    shown = false
    if me and me.status ~= ENGAGED then last_round = nil end
    return
  end
  local scr = hud.screen()
  local u = scr.ui_scale
  local d = delay()
  local f = math.min(1, (os.clock() - last_round) / d)
  local w, h = 120 * u, 5 * u
  local x, y = math.floor(scr.width / 2 - w / 2), math.floor(scr.height * 0.575)
  hud.bar("swing", { x = x, y = y, w = w, h = h, value = f, kind = "tp" })
  shown = true
end)
