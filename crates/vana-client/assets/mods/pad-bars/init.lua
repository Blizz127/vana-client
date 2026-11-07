-- Controller crossbars (the crossbar add-ons): two sides, LT and RT, of two diamonds each (the d-pad's four slots and
-- the face buttons' four). Holding a trigger, the d-pad and face buttons use that side's slots and the game never
-- sees them. Slots hold multi-line macros, kept per main job; //padbars edits them.

local actions = require("src.actions")
local runner = require("src.runner")

local SIDES = { "lt", "rt" }
local BUTTONS = { "up", "right", "down", "left", "y", "b", "a", "x" }
local LABELS = { up = "Up", right = "Right", down = "Down", left = "Left", y = "Y", b = "B", a = "A", x = "X" }
local SLOT = {}
for i, b in ipairs(BUTTONS) do SLOT[b] = i end

local shown = {}     -- id -> {action, x, y, size} for the recast shades
local last_sig

-- ---- Macros: storage.account.bars[job][side][button] = {name, lines} ----

local function job()
  local p = game.player()
  return p and p.main_job and res.job(p.main_job)
end

local function set_of(j, side, create)
  local s = storage.account
  s.bars = s.bars or {}
  if not s.bars[j] then
    if not create then return nil end
    s.bars[j] = {}
  end
  if not s.bars[j][side] then
    if not create then return nil end
    s.bars[j][side] = {}
  end
  return s.bars[j][side]
end

local function macro(side, button)
  local j = job()
  local set = j and set_of(j, side, false)
  return set and set[button]
end

-- ---- Using a slot ----

local function held()
  local p = input.pad()
  if not p.connected then return nil end
  local l, r = p.buttons.lt, p.buttons.rt
  if l and not r then return "lt" end
  if r and not l then return "rt" end
  return nil
end

input.on_pad(function(e)
  if not settings.get("on") or not input.pad().connected then return nil end
  if e.button == "lt" or e.button == "rt" then return true end
  local side = held()
  if not side or not SLOT[e.button] then return nil end
  if e.down then
    local m = macro(side, e.button)
    if m then timer.after(0, function() runner.run_checked(m) end) end
  end
  return true
end)

-- ---- The bars ----

local function opts()
  local scr = hud.screen()
  local u = scr.ui_scale
  return scr, u, math.floor(settings.get("size") * u)
end

-- Over the chat window at its full height, as Hotbars stand (they stay put while it grows and folds).
local function floor_y(scr, x0, w)
  local c = ui.native.rect("chat")
  c = c and (c.room or c)
  if c and c.x < x0 + w and c.x + c.w > x0 and c.y < scr.height then return c.y end
  return scr.height
end

local function label_of(m)
  local n = (m.name or ""):match("^%s*(.-)%s*$")
  if n == "" then n = (m.lines[1] or ""):match('"([^"]+)"') or (m.lines[1] or "") end
  return n:sub(1, 9)
end

local function draw()
  local on = settings.get("on") and input.pad().connected and job()
  if not on then
    if last_sig then hud.clear() end
    last_sig = nil
    shown = {}
    return
  end
  local scr, u, size = opts()
  local active = held()
  local sig_parts = { job(), tostring(active), scr.width, scr.height, u, size, settings.get("offset_y") }
  for _, side in ipairs(SIDES) do
    for _, b in ipairs(BUTTONS) do
      local m = macro(side, b)
      sig_parts[#sig_parts + 1] = m and table.concat(m.lines, "|") or "-"
    end
  end
  local sig = table.concat(sig_parts, ";")
  if sig ~= last_sig then
    last_sig = sig
    hud.clear()
    shown = {}
    local gap = math.floor(size * 0.15)
    local d = size + gap          -- a diamond's arm
    local dw = 2 * d + size       -- a diamond's width
    local side_w = 2 * dw + 2 * gap
    local total = 2 * side_w + 6 * gap
    local x0 = math.floor((scr.width - total) / 2)
    local h = 2 * d + size
    local y0 = floor_y(scr, x0, total) - settings.get("offset_y") * u - h
    local spots = { up = { 1, 0 }, right = { 2, 1 }, down = { 1, 2 }, left = { 0, 1 } }
    for si, side in ipairs(SIDES) do
      local sx = x0 + (si - 1) * (side_w + 6 * gap)
      local lit = active == nil or active == side
      hud.text(side .. "_t", { x = sx + side_w / 2, y = y0 - 18 * u, text = side:upper(), size = 0.8, align = "center",
        colour = lit and { 235, 220, 170 } or { 140, 140, 150 }, outline = { 0, 0, 0, 200 } })
      for di = 1, 2 do
        local dx = sx + (di - 1) * (dw + 2 * gap)
        for k = 1, 4 do
          local b = BUTTONS[(di - 1) * 4 + k]
          local pos = spots[BUTTONS[k]]
          local x, y = dx + pos[1] * d, y0 + pos[2] * d
          local id = side .. "_" .. b
          local m = macro(side, b)
          local act = m and actions.of(m)
          hud.rect(id, { x = x, y = y, w = size, h = size, round = 6 * u, layer = 1,
            colour = m and (lit and { 22, 26, 40, 225 } or { 22, 26, 40, 150 }) or { 14, 16, 24, lit and 150 or 90 },
            tip = m and { title = m.name ~= "" and m.name or label_of(m), text = table.concat(m.lines, "\n") } or nil })
          hud.rect(id .. "_f", { x = x - 1, y = y - 1, w = size + 2, h = size + 2, round = 7 * u, line = 1.5 * u, layer = 0,
            colour = active == side and { 196, 160, 86, 235 } or { 80, 84, 96, 140 } })
          if act then
            local isz = math.floor(size * 0.7)
            hud.icon(id .. "_i", { x = x + (size - isz) / 2, y = y + size * 0.08, size = isz, kind = act.kind, id = act.id,
              layer = 2, colour = lit and nil or { 150, 150, 150 } })
            shown[id] = { action = act, x = x, y = y, size = size }
          elseif m then
            hud.text(id .. "_l", { x = x + size / 2, y = y + size * 0.3, text = label_of(m), size = 0.7 * size / (46 * u),
              align = "center", colour = { 240, 240, 245 }, outline = { 0, 0, 0, 220 }, layer = 4 })
          end
          hud.text(id .. "_k", { x = x + 3 * u, y = y + 1 * u, text = LABELS[b], size = 0.55 * size / (46 * u),
            colour = { 210, 210, 220 }, outline = { 0, 0, 0, 220 }, layer = 4 })
        end
      end
    end
  end
  -- Recast shades, as Hotbars draw them.
  local r = game.recasts()
  for id, s in pairs(shown) do
    local left, frac = actions.recast(s.action, r)
    if left > 0 then
      hud.rect(id .. "_r", { x = s.x, y = s.y, w = s.size, h = math.max(2, s.size * frac), round = 6 * u,
        colour = { 0, 0, 0, 165 }, layer = 3 })
      local secs = math.ceil(left)
      hud.text(id .. "_c", { x = s.x + s.size / 2, y = s.y + s.size * 0.24, text = secs >= 60 and
        ("%d:%02d"):format(secs // 60, secs % 60) or tostring(secs), size = s.size / (52 * u), align = "center",
        colour = { 255, 236, 180 }, outline = { 0, 0, 0 }, layer = 4 })
    else
      hud.remove(id .. "_r")
      hud.remove(id .. "_c")
    end
  end
end

events.on("frame", draw)

-- ---- The editor ----

local WIN = "editor"
local view = { side = 1, slot = 1 }

local function rows()
  local out = {}
  for _, b in ipairs(BUTTONS) do
    local m = macro(SIDES[view.side], b)
    out[#out + 1] = { LABELS[b], m and label_of(m) or "" }
  end
  return out
end

local function refresh()
  if not ui.is_open(WIN) then return end
  local m = macro(SIDES[view.side], BUTTONS[view.slot])
  ui.update(WIN, "tabs", { at = view.side })
  ui.update(WIN, "slots", { rows = rows(), at = view.slot })
  ui.update(WIN, "name", { text = m and m.name or "" })
  ui.update(WIN, "lines", { text = m and table.concat(m.lines, " | ") or "" })
  ui.update(WIN, "where", { text = ("%s, %s for %s"):format(SIDES[view.side]:upper(), LABELS[BUTTONS[view.slot]], job() or "?") })
end

local function open()
  ui.window(WIN, {
    title = "Pad Bars", width = 460,
    help = "Pick a slot, type its lines (separate them with |) and Save. Hold LT or RT on the controller to use a side.",
    elements = {
      { type = "tabs", id = "tabs", items = { "LT", "RT" }, at = view.side },
      { type = "list", id = "slots", rows = rows(), height = 8, at = view.slot,
        columns = { { title = "Button", width = 70 }, { title = "Macro" } } },
      { type = "text", id = "where", text = "" },
      { type = "input", id = "name", label = "Name", text = "", max = 24 },
      { type = "input", id = "lines", label = "Lines (separate with |)", text = "", max = 600,
        tip = 'Example: /ja "Provoke" <t> | /wait 1 | /p Provoked!' },
      { type = "buttons", id = "btn", items = { "Save", "Clear", "Close" } },
    },
  })
  ui.open(WIN)
  refresh()
end

ui.on(WIN, function(_, e)
  if e.kind == "set" and e.id == "tabs" then
    view.side = e.index
    refresh()
  elseif e.kind == "select" and e.id == "slots" then
    view.slot = e.index
    refresh()
  elseif e.kind == "press" and e.id == "btn" then
    view.slot = ui.get(WIN, "slots").at or view.slot
    local j = job()
    if e.index == 3 or not j then
      ui.close(WIN)
      return
    end
    local set = set_of(j, SIDES[view.side], true)
    local b = BUTTONS[view.slot]
    if e.index == 1 then
      local lines = {}
      for l in (ui.get(WIN, "lines").text or ""):gmatch("[^|]+") do
        l = l:match("^%s*(.-)%s*$")
        if l ~= "" then lines[#lines + 1] = l end
      end
      if #lines > 0 then
        set[b] = { name = (ui.get(WIN, "name").text or ""):match("^%s*(.-)%s*$"), lines = lines }
      end
    else
      set[b] = nil
    end
    storage.save()
    refresh()
  end
end)

commands.register("padbars", function()
  if ui.is_open(WIN) then ui.close(WIN) else open() end
end)
