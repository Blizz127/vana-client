-- The hotbars on screen: a slot shows its action's icon (or its label), its hotkey, a shade with the seconds left
-- while the action recasts, and its macro in a tip. A click fires it, a right click edits it, and a slot dragged onto
-- another swaps them. Slots the main job's set fills have a gold edge, the sub job's set's a blue one.

local data = require("src.data")
local runner = require("src.runner")
local jobs = require("src.jobs")
local keys = require("src.keys")
local actions = require("src.actions")

local M = {}

-- Set by init.lua: open_manager(), edit_slot(bar, slot, from), changed()
M.hooks = {}

local hidden = false   -- //hb show | hide
local built_sig = nil  -- what the drawing was made for
local shown = {}       -- slot id -> {action, x, y, size} as drawn, for the recast shades

local EMPTY_BG = { 14, 16, 24, 140 }
local FILLED_BG = { 22, 26, 40, 215 }
local EMPTY_EDGE = { 80, 84, 96, 120 }
local EDGE = { main = { 196, 160, 86, 235 }, sub = { 96, 156, 226, 240 } }
local SHADE = { 0, 0, 0, 165 }

-- Sizes and offsets are in UI units, so the bars keep their size at any resolution and UI size.
local function opts()
  local u = hud.screen().ui_scale
  return {
    bars = math.min(settings.get("bars"), data.MAX_BARS),
    slots = math.min(settings.get("slots"), data.MAX_SLOTS),
    size = math.floor(settings.get("size") * u),
    gap = math.floor(settings.get("gap") * u),
    ox = settings.get("offset_x") * u,
    oy = settings.get("offset_y") * u,
    show_keys = settings.get("show_keys"),
  }
end

-- The line the bottom bar stands over: the window's bottom, or the top of the modern chat window at its full height
-- when it is under the bars (they stay put while it grows and folds).
local function floor_y(scr, x0, w)
  local c = ui.native.rect("chat")
  c = c and (c.room or c)
  if c and c.x < x0 + w and c.x + c.w > x0 and c.y < scr.height then return c.y end
  return scr.height
end

local function span(o, scr)
  local w = o.slots * o.size + (o.slots - 1) * o.gap
  return math.floor((scr.width - w) / 2 + o.ox), w
end

local function signature()
  local main, sub = jobs.current()
  local scr = hud.screen()
  local x0, w = span(opts(), scr)
  return table.concat({ tostring(main), tostring(sub), scr.width, scr.height, scr.ui_scale, floor_y(scr, x0, w) }, ":")
end

-- Runs the macro in a slot for the current jobs.
function M.fire(bar, slot)
  local main, sub = jobs.current()
  if not main then return end
  local macro = data.resolve(main, sub, bar, slot)
  if macro then runner.run_checked(macro) end
end

local function slot_menu(bar, slot)
  local main, sub = jobs.current()
  local _, from = data.resolve(main, sub, bar, slot)
  ui.menu({ "Edit / assign macro", "Clear slot", "Open manager" }, function(i)
    if i == 1 then
      M.hooks.edit_slot(bar, slot, from)
    elseif i == 2 and main then
      data.clear(main, from == "sub" and sub or nil, bar, slot)
      M.rebuild()
      if M.hooks.changed then M.hooks.changed() end
    elseif i == 3 then
      M.hooks.open_manager()
    end
  end)
end

-- A slot dropped on another: the two swap, in the sub job's set when either comes from it.
local function dropped(bar, slot, from_id)
  local fb, fs = from_id:match("^s(%d+)_(%d+)$")
  fb, fs = tonumber(fb), tonumber(fs)
  if not fb or (fb == bar and fs == slot) then return end
  local main, sub = jobs.current()
  if not main then return end
  local _, a = data.resolve(main, sub, fb, fs)
  local _, b = data.resolve(main, sub, bar, slot)
  data.swap(main, (a == "sub" or b == "sub") and sub or nil, fb, fs, bar, slot)
  M.rebuild()
  if M.hooks.changed then M.hooks.changed() end
end

local function tip_of(macro)
  local lines = table.concat(macro.lines or {}, "\n")
  local name = data.trim(macro.name)
  if name == "" then return lines end
  return { title = name, text = lines }
end

function M.rebuild()
  hud.clear()
  shown = {}
  built_sig = signature()
  if hidden or not settings.get("on") or not settings.get("visible") then return end
  local main, sub = jobs.current()
  if not main then
    built_sig = nil -- jobs not known yet; the tick tries again
    return
  end

  local o = opts()
  local scr = hud.screen()
  local u = scr.ui_scale
  local eff = data.effective(main, sub)
  local round = 6 * u
  local x0, w = span(o, scr)
  local y_bottom = floor_y(scr, x0, w) - o.oy - o.size
  -- Text sizes follow the slot size: 1 is the UI's text.
  local k = o.size / (52 * u)
  local name_size, hint_size, text_size = 0.7 * k, 0.7 * k, 0.8 * k
  local line_h = 16 * u

  for b = 1, o.bars do
    -- Bar 1 is the top row; the last bar sits at the bottom offset.
    local y = y_bottom - (o.bars - b) * (o.size + o.gap)
    for i = 1, o.slots do
      local x = x0 + (i - 1) * (o.size + o.gap)
      local id = ("s%d_%d"):format(b, i)
      local cell = eff[b] and eff[b][i]
      local macro = cell and cell.macro
      local act = macro and actions.of(macro)
      hud.rect(id .. "_f", { x = x - 1, y = y - 1, w = o.size + 2, h = o.size + 2, round = round + 1,
        colour = macro and EDGE[cell.from] or EMPTY_EDGE, line = 1.5 * u, layer = 0 })
      hud.rect(id, { x = x, y = y, w = o.size, h = o.size, round = round, colour = macro and FILLED_BG or EMPTY_BG,
        layer = 1, tip = macro and tip_of(macro) or nil })
      hud.on(id, function(_, e)
        if e.kind == "click" then
          if e.button == "right" then slot_menu(b, i) else M.fire(b, i) end
        elseif e.kind == "drop" and e.from then
          dropped(b, i, e.from)
        end
      end)
      if act then
        local isz = math.floor(o.size * 0.7)
        hud.icon(id .. "_i", { x = x + (o.size - isz) / 2, y = y + o.size * 0.08, size = isz, kind = act.kind, id = act.id,
          layer = 2 })
        shown[id] = { action = act, x = x, y = y, size = o.size, round = round }
      end
      if macro then
        local label = data.display_label(macro)
        if act then
          -- Over the icon's foot: the label's first line.
          hud.text(id .. "_t", { x = x + o.size / 2, y = y + o.size - line_h * name_size - 3 * u,
            text = label:match("^[^\n]*"), size = name_size, align = "center", colour = { 240, 240, 245 },
            outline = { 0, 0, 0, 230 }, layer = 4 })
        else
          local lines = {}
          for l in label:gmatch("[^\n]+") do lines[#lines + 1] = l end
          local top = y + (o.size - #lines * line_h * text_size) / 2
          for n, l in ipairs(lines) do
            hud.text(id .. "_t" .. n, { x = x + o.size / 2, y = top + (n - 1) * line_h * text_size, text = l,
              size = text_size, align = "center", colour = { 255, 255, 255 }, outline = { 0, 0, 0, 230 }, layer = 4 })
          end
        end
      end
      if o.show_keys then
        hud.text(id .. "_k", { x = x + 3 * u, y = y + 1 * u, text = keys.hint(b, i), size = hint_size,
          colour = { 225, 225, 232 }, outline = { 0, 0, 0, 230 }, layer = 4 })
      end
    end
  end

  -- The jobs above the top bar; a click opens the manager.
  local top = y_bottom - (o.bars - 1) * (o.size + o.gap)
  hud.text("hdr", { x = x0, y = top - line_h * 0.8 - 8 * u, text = main .. "/" .. (sub or "-"), size = 0.8,
    colour = { 230, 215, 170 }, bg = { 0, 0, 0, 140 }, pad = 3 * u, layer = 2 })
  hud.on("hdr", function() M.hooks.open_manager() end)
  M.recasts()
end

-- The recast shades: the part still to go, from the top, and the seconds over it.
function M.recasts()
  if not next(shown) then return end
  local r = game.recasts()
  for id, s in pairs(shown) do
    local left, frac = actions.recast(s.action, r)
    if left > 0 then
      hud.rect(id .. "_r", { x = s.x, y = s.y, w = s.size, h = math.max(2, s.size * frac), round = s.round,
        colour = SHADE, layer = 3 })
      local secs = math.ceil(left)
      local text = secs >= 60 and ("%d:%02d"):format(secs // 60, secs % 60) or tostring(secs)
      hud.text(id .. "_c", { x = s.x + s.size / 2, y = s.y + s.size * 0.24, text = text, size = s.size / (52 * hud.screen().ui_scale), align = "center",
        colour = { 255, 236, 180 }, outline = { 0, 0, 0 }, layer = 4 })
    else
      hud.remove(id .. "_r")
      hud.remove(id .. "_c")
    end
  end
end

function M.rebind()
  if not settings.get("on") then
    keys.bind_all(0, 0, M.fire)
    return
  end
  local o = opts()
  keys.bind_all(o.bars, o.slots, M.fire)
end

-- Once a second: redraws when the jobs or the window size changed.
function M.tick()
  if signature() ~= built_sig then M.rebuild() end
end

function M.set_hidden(value)
  hidden = value
  M.rebuild()
end

function M.is_hidden() return hidden end

return M
