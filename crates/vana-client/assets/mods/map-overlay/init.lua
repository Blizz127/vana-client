-- The zone map over the game (the map add-ons). Ctrl or Alt + O opens and closes it: the map we stand on (one we have
-- and own) in a box in the middle of the screen at the set opacity, our marker on it. A left drag pans it, the wheel
-- zooms at the pointer (the whole map up to 8x), Escape closes it. It follows us across zones and map pages.

local BOX, MAX_ZOOM = 0.7, 8
local open = false
-- What the box shows: the map pixel at its centre (the map's own coordinates) and how many map pixels it spans; the
-- map and screen it was set for.
local view, seen
local drag

local function box()
  local s = hud.screen()
  local side = math.floor(math.min(s.width, s.height) * BOX + 0.5)
  return math.floor((s.width - side) / 2 + 0.5), math.floor((s.height - side) / 2 + 0.5), side
end

-- The image stays over the whole box.
local function clamp(m)
  view.span = math.max(512 / MAX_ZOOM, math.min(512, view.span))
  local half = view.span / 2
  view.cx = math.max(m.origin.x + half, math.min(m.origin.x + 512 - half, view.cx))
  view.cy = math.max(m.origin.y + half, math.min(m.origin.y + 512 - half, view.cy))
end

local function close()
  open, view, drag = false, nil, nil
  hud.remove("overlay")
  hud.remove("overlay_edge")
end

local function show()
  local m = game.map()
  if not open or not m then
    hud.remove("overlay")
    hud.remove("overlay_edge")
    return
  end
  local x, y, side = box()
  -- A new zone, map page or window size: the whole map again.
  local key = table.concat({ m.zone, m.number, side }, ":")
  if not view or seen ~= key then
    view, seen = { cx = m.origin.x + 256, cy = m.origin.y + 256, span = 512 }, key
  end
  clamp(m)
  local centre = { x = view.cx / m.px_per_unit, z = -view.cy / m.px_per_unit }
  hud.map("overlay", { x = x, y = y, w = side, h = side, centre = centre, span = view.span, alpha = settings.get("opacity"), me = true })
  hud.on("overlay", function(_, e)
    if e.button ~= "left" or not view then return end
    if e.kind == "drag_start" then
      drag = { cx = view.cx, cy = view.cy }
    elseif drag and (e.kind == "drag" or e.kind == "drag_end") then
      local k = view.span / side
      view.cx, view.cy = drag.cx - e.dx * k, drag.cy - e.dy * k
      if e.kind == "drag_end" then drag = nil end
      show()
    end
  end)
  -- The modern UI's bronze edge.
  if game.info().modern_ui then
    hud.rect("overlay_edge", { x = x - 2, y = y - 2, w = side + 4, h = side + 4, line = 2, colour = { 184, 139, 73, 204 } })
  else
    hud.remove("overlay_edge")
  end
end

local function toggle()
  if open then
    close()
  elseif not game.map() then
    audio.play_ui(4)
  else
    open = true
    show()
  end
end

-- The keys while the overlay is switched on in Extras.
local function apply()
  if settings.get("on") then
    binds.set("^o", toggle)
    binds.set("!o", toggle)
  else
    binds.unset("^o")
    binds.unset("!o")
    close()
  end
  show()
end

-- The wheel over the box zooms; the map pixel under the pointer stays put. The map is read in the mod phase, so the
-- box is drawn again from there.
input.on_mouse(function(e)
  if not open or not view or e.kind ~= "wheel" then return end
  local x, y, side = box()
  if e.x < x or e.y < y or e.x >= x + side or e.y >= y + side then return end
  local dx, dy = e.x - (x + side / 2), e.y - (y + side / 2)
  local px, py = view.cx + dx * view.span / side, view.cy + dy * view.span / side
  view.span = math.max(512 / MAX_ZOOM, math.min(512, view.span / 1.25 ^ e.delta))
  view.cx, view.cy = px - dx * view.span / side, py - dy * view.span / side
  timer.after(0, show)
  return true
end)

-- Escape closes it, after the game's windows.
input.on_key(function(e)
  if open and e.down and e.key == "escape" and not e.typing and not ui.native.menu_open() then
    close()
    return true
  end
end)

-- Zones, map pages, the window's size and the UI change under it.
timer.every(0.25, function()
  if open then show() end
end)

events.on("settings_changed", apply)
apply()
