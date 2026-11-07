-- The zone's name across the screen as we arrive (the zone name add-ons): in, held, out over 4 s.

local IN, HOLD, OUT = 0.6, 2.4, 1.0
local shown_at, name

local function draw()
  if not shown_at then return end
  local t = os.clock() - shown_at
  if t > IN + HOLD + OUT then
    shown_at = nil
    hud.clear()
    return
  end
  local a = t < IN and t / IN or (t < IN + HOLD and 1 or 1 - (t - IN - HOLD) / OUT)
  local scr = hud.screen()
  local u = scr.ui_scale
  hud.text("zone", { x = scr.width / 2, y = scr.height * 0.14, text = name, size = 2.0, align = "center",
    font = "bold", colour = { 245, 235, 205, math.floor(255 * a) }, outline = { 0, 0, 0, math.floor(200 * a) },
    outline_width = 2 * u })
  local w = 360 * u
  hud.rect("line", { x = scr.width / 2 - w / 2, y = scr.height * 0.14 + 46 * u, w = w, h = 1.5 * u,
    colour = { 210, 180, 110, math.floor(220 * a) } })
end

events.on("zone_change", function(zone)
  if not settings.get("on") then return end
  name = res.zone(zone)
  if name and name ~= "" then shown_at = os.clock() end
end)
events.on("frame", draw)
