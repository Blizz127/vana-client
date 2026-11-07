-- Modes for GearSwap files, as `include('Modes.lua')` gives them: M('a', 'b'), M{['description'] = 'X', 'a', 'b'},
-- M(false, 'X') and M{['string'] = 'x'}, a list, boolean or string mode with a current value. Ours, written to the
-- calls files make; a player's Modes.lua beside the files is used instead.

local methods = {}
local meta = {}

local function track(m) return rawget(m, "_track") end

meta.__index = function(m, k)
  if type(k) ~= "string" then return nil end
  local t, lk = track(m), k:lower()
  if lk == "value" or lk == "current" then
    if t._type == "list" then return rawget(m, t._current) end
    return t._current
  end
  if lk == "index" then return t._current end
  if lk == "description" then return t._description end
  if lk == "default" then return t._type == "list" and rawget(m, t._default) or t._default end
  if lk == "_type" or lk == "type" then return t._type end
  return methods[lk]
end

meta.__tostring = function(m) return tostring(m.value) end

local function count(m)
  local n = 0
  while rawget(m, n + 1) ~= nil do n = n + 1 end
  return n
end

local function find(m, v)
  local want = tostring(v):lower()
  for i = 1, count(m) do
    if tostring(rawget(m, i)):lower() == want then return i end
  end
end

function methods.describe(m, text)
  track(m)._description = text
  return m
end

function methods.options(m, ...)
  local t = track(m)
  if t._type ~= "list" then error("options: only a list mode has options", 2) end
  for i = count(m), 1, -1 do rawset(m, i, nil) end
  for i, v in ipairs({ ... }) do rawset(m, i, v) end
  t._default, t._current = 1, 1
  return m
end

function methods.contains(m, v) return find(m, v) ~= nil end
methods.has_value = methods.contains

function methods.length(m) return count(m) end

function methods.cycle(m)
  local t = track(m)
  if t._type == "list" then
    t._current = t._current % math.max(count(m), 1) + 1
  elseif t._type == "boolean" then
    t._current = not t._current
  end
  return m.value
end

function methods.cycleback(m)
  local t = track(m)
  if t._type == "list" then
    t._current = (t._current - 2) % math.max(count(m), 1) + 1
  elseif t._type == "boolean" then
    t._current = not t._current
  end
  return m.value
end

function methods.toggle(m)
  local t = track(m)
  if t._type == "boolean" then
    t._current = not t._current
    return m.value
  end
  return methods.cycle(m)
end

local TRUE = { ["true"] = true, on = true, yes = true, ["1"] = true }
local FALSE = { ["false"] = true, off = true, no = true, ["0"] = true }

function methods.set(m, v)
  local t = track(m)
  if t._type == "boolean" then
    if v == nil or v == true then
      t._current = true
    elseif v == false then
      t._current = false
    elseif TRUE[tostring(v):lower()] then
      t._current = true
    elseif FALSE[tostring(v):lower()] then
      t._current = false
    else
      error("set: " .. tostring(v) .. " is not on or off", 2)
    end
  elseif t._type == "string" then
    t._current = v == nil and "" or tostring(v)
  else
    local i = find(m, v)
    if not i then error("set: " .. tostring(v) .. " is not one of " .. (t._description or "the mode") .. "'s values", 2) end
    t._current = i
  end
  return m.value
end

function methods.reset(m)
  local t = track(m)
  t._current = t._default
  return m.value
end

function methods.unset(m)
  local t = track(m)
  if t._type == "boolean" then t._current = false elseif t._type == "string" then t._current = "" end
  return m.value
end

-- M(...): the mode.
return function(first, ...)
  local rest = { ... }
  local opts = first
  if type(first) ~= "table" then
    opts = { first }
    for i, v in ipairs(rest) do opts[i + 1] = v end
  end
  local m = { _track = {} }
  local t = m._track
  t._description = opts.description
  if type(opts[1]) == "boolean" then
    t._type, t._default = "boolean", opts[1]
    -- M(false, 'Description'): the second argument names it.
    if type(first) ~= "table" and type(rest[1]) == "string" then t._description = rest[1] end
  elseif #opts == 0 then
    if opts.string ~= nil then
      t._type, t._default = "string", tostring(opts.string)
    else
      t._type, t._default = "boolean", false
    end
  else
    t._type, t._default = "list", 1
    for i, v in ipairs(opts) do m[i] = v end
  end
  t._current = t._default
  return setmetatable(m, meta)
end
