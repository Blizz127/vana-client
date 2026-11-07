-- NPC talk in a speech bubble (the balloon add-ons): the page being read, the speaker's name on a tab over it,
-- placed over the speaker's head or at the bottom of the screen. The log keeps its copy; keys are the game's.

local BODY = { 240, 236, 224, 255 }
local NAME = { 232, 200, 120, 255 }
local BG = { 14, 16, 26, 235 }
local EDGE = { 0, 0, 0, 200 }
-- over other mods' HUD (the hotbars use 0..4)
local LAYER = 20

local shown = false

local function hide()
  if shown then
    hud.clear()
    shown = false
  end
end

-- "Name : text" opens NPC talk; narration has no name. Later lines lose the log's continuation indent.
local function split(lines)
  local name, first = lines[1]:match("^(.-) : (.*)$")
  local body = { first or lines[1] }
  for i = 2, #lines do body[#body + 1] = (lines[i]:gsub("^%s+", "")) end
  return name, table.concat(body, "\n")
end

-- The bubble's bottom centre: over the speaker's head when it is on screen, else above the log.
local function anchor(actor, scr, u)
  if settings.get("place") == "Over the Speaker" then
    local e = actor and game.entity(actor)
    if e and not e.me and e.pos then
      -- clear of the name plate over the head
      local p = draw.to_screen({ x = e.pos.x, y = e.pos.y - 2.6, z = e.pos.z })
      if p and p.on_screen then return p.x, p.y - 34 * u end
    end
  end
  return scr.width / 2, scr.height * 0.66
end

local function draw()
  local e = settings.get("on") and game.event()
  local t = e and not e.menu and e.text
  if not (t and t.lines and #t.lines > 0) then return hide() end
  local name, body = split(t.lines)
  local scr = hud.screen()
  local u = scr.ui_scale
  local size = settings.get("size")
  local pad = 10 * u
  -- last frame's box sizes this one (the first frame guesses)
  local b = hud.bounds("body")
  local w = b and b.w or 420 * u
  local h = b and b.h or (#t.lines * 20 * size * u + 2 * pad)
  local ax, ay = anchor(t.actor, scr, u)
  local x = math.max(8 * u + w / 2, math.min(scr.width - 8 * u - w / 2, ax))
  local y = math.max((name and 34 or 8) * u, ay - h)
  hud.text("body", { x = x, y = y, text = body, size = size, align = "center", colour = BODY, bg = BG, pad = pad,
    outline = EDGE, layer = LAYER })
  if name then
    hud.text("name", { x = x - w / 2, y = y - 22 * size * u, text = name, size = size * 0.9, font = "bold",
      colour = NAME, bg = BG, pad = 5 * u, outline = EDGE, layer = LAYER })
  else
    hud.remove("name")
  end
  -- the tail under the bubble, blinking while the page waits for a key
  local a = t.waiting and math.floor(140 + 115 * math.abs(math.sin(os.clock() * 4))) or 110
  hud.text("more", { x = x, y = y + h - 9 * u, text = "▼", size = size, font = "game", align = "center",
    colour = { NAME[1], NAME[2], NAME[3], a }, outline = EDGE, layer = LAYER })
  shown = true
end

events.on("frame", draw)
events.on("settings_changed", hide)
