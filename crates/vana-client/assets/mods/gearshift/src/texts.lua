-- Windower's texts library for GearSwap files, drawn as HUD texts: a box at a position with ${name|default} fields,
-- \cs(r,g,b) ... \cr colour runs, a background, an outline, a size; each run placed after the one before it by the
-- width it was drawn at (the layout settles a frame after a change).

local M = {}

local state = setmetatable({}, { __mode = "k" })
local boxes = {}
local count = 0
-- Pixels of line height per HUD text size, measured from what was drawn.
local px_per_size = 18

local function copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = copy(v) end
  return o
end

-- `over` on top of `base`, both Windower settings tables.
local function merged(base, over)
  local o = copy(base)
  if type(over) ~= "table" then return o end
  for k, v in pairs(over) do
    if type(v) == "table" and type(o[k]) == "table" then o[k] = merged(o[k], v) else o[k] = copy(v) end
  end
  return o
end

local DEFAULTS = {
  pos = { x = 0, y = 0 },
  bg = { alpha = 255, red = 0, green = 0, blue = 0, visible = true },
  flags = { right = false, bottom = false, bold = false, italic = false, draggable = true },
  padding = 0,
  text = { size = 12, font = "Arial", alpha = 255, red = 255, green = 255, blue = 255,
    stroke = { width = 0, alpha = 255, red = 0, green = 0, blue = 0 } },
}

local methods = {}

local meta = {
  __index = function(t, k)
    local m = methods[k]
    if m then return m end
    local s = state[t]
    return s and s.values[k]
  end,
  __newindex = function(t, k, v)
    local s = state[t]
    if s then
      s.values[k] = v
      s.dirty = true
    end
  end,
}

-- texts.new([text], [settings], [root settings]) or texts.new(settings).
function M.new(str, settings)
  if type(str) == "table" then str, settings = "", str end
  count = count + 1
  local t = setmetatable({}, meta)
  state[t] = { id = "gstext" .. count, raw = str or "", values = {}, cfg = merged(DEFAULTS, settings), visible = false,
    dirty = true, drawn = {}, sizes = {} }
  boxes[#boxes + 1] = t
  return t
end

-- The text with its fields filled: ${name}, ${name|default}, ${name|default|format}.
local function filled(s)
  return (s.raw:gsub("%${([^}|]+)|?([^}|]*)|?([^}]*)}", function(name, default, form)
    local v = s.values[name]
    if v == nil then return default end
    if form ~= "" and pcall(string.format, form, v) then return string.format(form, v) end
    return tostring(v)
  end))
end

-- Lines of runs {text, colour}: \cs(r,g,b) starts a colour, \cr goes back to the box's colour.
local function runs(text, base)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    local out, colour, i = {}, base, 1
    while i <= #line do
      local a, b, r, g, bl = line:find("\\cs%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*%)", i)
      local c, d = line:find("\\cr", i, true)
      local nxt, kind = a, "cs"
      if c and (not a or c < a) then nxt, kind = c, "cr" end
      if not nxt then
        out[#out + 1] = { line:sub(i), colour }
        break
      end
      if nxt > i then out[#out + 1] = { line:sub(i, nxt - 1), colour } end
      if kind == "cs" then
        colour = { tonumber(r), tonumber(g), tonumber(bl), base[4] }
        i = b + 1
      else
        colour = base
        i = d + 1
      end
    end
    lines[#lines + 1] = out
  end
  return lines
end

local function changed(t)
  state[t].dirty = true
  state[t].sizes = {}
end

local function remove_drawn(s)
  for id in pairs(s.drawn) do hud.remove(id) end
  s.drawn = {}
end

local function draw(t)
  local s = state[t]
  if not s.visible then
    remove_drawn(s)
    return
  end
  local cfg = s.cfg
  local tc = cfg.text
  local base = { tc.red, tc.green, tc.blue, tc.alpha }
  local size = (tc.size or 12) * 1.33 / px_per_size
  local pad = cfg.padding or 0
  local st = tc.stroke or {}
  local outline = (st.width or 0) > 0 and { st.red, st.green, st.blue, st.alpha } or nil
  local font = cfg.flags.bold and "bold" or "regular"
  local lines = runs(filled(s), base)
  local scr = hud.screen()
  local x0, y0 = cfg.pos.x, cfg.pos.y
  local now, y, width = {}, 0, 0
  local line_h = (tc.size or 12) * 1.33
  for li, line in ipairs(lines) do
    local x, h = 0, line_h
    for ri, run in ipairs(line) do
      if run[1] ~= "" then
        local id = s.id .. "_" .. li .. "_" .. ri
        local w = s.sizes[id]
        now[id] = { x = x, y = y, text = run[1], colour = run[2], size = size }
        x = x + (w and w[1] or #run[1] * line_h * 0.5)
        if w then h = math.max(h, w[2]) end
      end
    end
    width = math.max(width, x)
    y = y + h
  end
  local w, h = width + pad * 2, y + pad * 2
  -- Right / bottom flags: the position counts from that edge.
  if cfg.flags.right then x0 = scr.width + x0 - w end
  if cfg.flags.bottom then y0 = scr.height + y0 - h end
  s.extent = { w, h }
  local bg = cfg.bg
  if bg.visible ~= false and (bg.alpha or 0) > 0 then
    hud.rect(s.id .. "_bg", { x = x0, y = y0, w = w, h = h, colour = { bg.red, bg.green, bg.blue, bg.alpha } })
    now[s.id .. "_bg"] = true
  end
  for id, r in pairs(now) do
    if r ~= true then
      hud.text(id, { x = x0 + pad + r.x, y = y0 + pad + r.y, text = r.text, size = size, colour = r.colour, font = font,
        outline = outline, outline_width = outline and st.width or nil, layer = 1 })
    end
  end
  for id in pairs(s.drawn) do
    if not now[id] then hud.remove(id) end
  end
  s.drawn = now
  s.dirty = false
end

-- Each frame: boxes changed, or whose runs were drawn at another width than laid out, are drawn again.
function M.frame()
  for i = #boxes, 1, -1 do
    local t = boxes[i]
    local s = state[t]
    if not s then
      table.remove(boxes, i)
    elseif s.visible then
      for id, r in pairs(s.drawn) do
        if r ~= true then
          local b = hud.bounds(id)
          if b then
            -- The HUD's text height per size, so a box's point size comes out at its pixel height.
            local per = b.h / r.size
            if math.abs(per - px_per_size) > 0.5 then
              px_per_size = per
              for _, o in ipairs(boxes) do if state[o] then changed(o) end end
            end
            local old = s.sizes[id]
            if not old or math.abs(old[1] - b.w) > 0.5 or math.abs(old[2] - b.h) > 0.5 then
              s.sizes[id] = { b.w, b.h }
              s.dirty = true
            end
          end
        end
      end
      if s.dirty then draw(t) end
    end
  end
end

-- Every box gone (the file unloaded).
function M.clear_all()
  for _, t in ipairs(boxes) do
    local s = state[t]
    if s then remove_drawn(s) end
  end
  boxes = {}
end

-- ---- The library's functions, each also a method ----

function methods.text(t, str)
  local s = state[t]
  if str == nil then return s.raw end
  s.raw = tostring(str)
  changed(t)
end
function methods.append(t, str)
  local s = state[t]
  s.raw = s.raw .. tostring(str)
  changed(t)
end
function methods.appendline(t, str) methods.append(t, "\n" .. tostring(str)) end
function methods.clear(t) methods.text(t, "") end
function methods.update(t, values)
  local s = state[t]
  for k, v in pairs(values or {}) do s.values[k] = v end
  s.dirty = true
end
function methods.show(t)
  state[t].visible = true
  state[t].dirty = true
end
function methods.hide(t)
  state[t].visible = false
  remove_drawn(state[t])
end
function methods.visible(t, v)
  if v == nil then return state[t].visible end
  if v then methods.show(t) else methods.hide(t) end
end
function methods.pos(t, x, y)
  local p = state[t].cfg.pos
  if x == nil then return p.x, p.y end
  p.x, p.y = x, y or p.y
  state[t].dirty = true
end
function methods.pos_x(t, x)
  if x == nil then return state[t].cfg.pos.x end
  methods.pos(t, x, nil)
end
function methods.pos_y(t, y)
  if y == nil then return state[t].cfg.pos.y end
  methods.pos(t, state[t].cfg.pos.x, y)
end
function methods.extents(t)
  local e = state[t].extent or { 0, 0 }
  return e[1], e[2]
end
local function field(path, key)
  return function(t, v)
    local c = state[t].cfg
    for _, p in ipairs(path) do c = c[p] end
    if v == nil then return c[key] end
    c[key] = v
    changed(t)
  end
end
methods.size = field({ "text" }, "size")
methods.font = field({ "text" }, "font")
methods.alpha = field({ "text" }, "alpha")
methods.pad = function(t, v)
  if v == nil then return state[t].cfg.padding end
  state[t].cfg.padding = v
  changed(t)
end
methods.bg_alpha = field({ "bg" }, "alpha")
methods.bg_visible = field({ "bg" }, "visible")
methods.stroke_width = field({ "text", "stroke" }, "width")
methods.stroke_alpha = field({ "text", "stroke" }, "alpha")
methods.bold = field({ "flags" }, "bold")
methods.italic = field({ "flags" }, "italic")
methods.right_justified = field({ "flags" }, "right")
methods.bottom_justified = field({ "flags" }, "bottom")
methods.draggable = field({ "flags" }, "draggable")
function methods.color(t, r, g, b)
  local c = state[t].cfg.text
  if r == nil then return c.red, c.green, c.blue end
  c.red, c.green, c.blue = r, g, b
  changed(t)
end
function methods.bg_color(t, r, g, b)
  local c = state[t].cfg.bg
  if r == nil then return c.red, c.green, c.blue end
  c.red, c.green, c.blue = r, g, b
  changed(t)
end
function methods.stroke_color(t, r, g, b)
  local c = state[t].cfg.text.stroke
  if r == nil then return c.red, c.green, c.blue end
  c.red, c.green, c.blue = r, g, b
  changed(t)
end
function methods.transparency(t, v) methods.alpha(t, math.floor((1 - v) * 255)) end
function methods.bg_transparency(t, v) methods.bg_alpha(t, math.floor((1 - v) * 255)) end
function methods.stroke_transparency(t, v) methods.stroke_alpha(t, math.floor((1 - v) * 255)) end
function methods.hover(t, x, y)
  local s = state[t]
  if not s.visible or not s.extent then return false end
  local px, py = s.cfg.pos.x, s.cfg.pos.y
  return x >= px and y >= py and x <= px + s.extent[1] and y <= py + s.extent[2]
end
function methods.destroy(t)
  local s = state[t]
  if s then remove_drawn(s) end
  state[t] = nil
end
function methods.register_event() end

for k, f in pairs(methods) do
  if M[k] == nil then M[k] = f end
end

return M
