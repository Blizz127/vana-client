-- What players' files written for Lua 5.1 (LuaJIT) and the add-ons' libraries expect, for a 5.4 environment table:
-- unpack, loadstring, math.pow, table.getn, bit.*, and the Windower / Ashita sugar most files use (T{}, S{}, L{},
-- string:split / startswith / endswith / contains / trim, table:contains ...).

local M = {}

local bitlib = {
  band = function(a, ...) for _, b in ipairs({ ... }) do a = a & b end return a end,
  bor = function(a, ...) for _, b in ipairs({ ... }) do a = a | b end return a end,
  bxor = function(a, ...) for _, b in ipairs({ ... }) do a = a ~ b end return a end,
  bnot = function(a) return ~a end,
  lshift = function(a, n) return (a << n) & 0xffffffff end,
  rshift = function(a, n) return (a & 0xffffffff) >> n end,
  arshift = function(a, n) return a >> n end,
  tobit = function(a) a = a & 0xffffffff if a >= 0x80000000 then a = a - 0x100000000 end return a end,
}

-- 5.1 printed 2.0 as "2": strings built from numbers stay as the file expects.
local function tostring51(v)
  if math.type(v) == "float" and v == math.floor(v) and v > -2 ^ 53 and v < 2 ^ 53 then
    return string.format("%d", v)
  end
  return tostring(v)
end

-- ---- Tables: T{} / L{} lists and S{} sets ----

local T_methods = {}
local T_meta = { __index = T_methods }

function M.T(t)
  return setmetatable(t or {}, T_meta)
end

function T_methods:contains(v)
  for _, x in pairs(self) do if x == v then return true end end
  return false
end
function T_methods:append(v) self[#self + 1] = v return self end
function T_methods:extend(t) for _, v in ipairs(t) do self[#self + 1] = v end return self end
function T_methods:length() local n = 0 for _ in pairs(self) do n = n + 1 end return n end
function T_methods:empty() return next(self) == nil end
function T_methods:find(v) for k, x in pairs(self) do if x == v then return k end end end
function T_methods:map(f) local o = M.T() for k, v in pairs(self) do o[k] = f(v) end return o end
function T_methods:filter(f) local o = M.T() for k, v in pairs(self) do if f(v) then o[k] = v end end return o end
function T_methods:keyset() local o = M.S() for k in pairs(self) do o[k] = true end return o end
function T_methods:copy() local o = M.T() for k, v in pairs(self) do o[k] = v end return o end
function T_methods:update(t) for k, v in pairs(t) do self[k] = v end return self end
function T_methods:concat(sep) return table.concat(self, sep) end
function T_methods:it() local k, v return function() k, v = next(self, k) return v end end

local S_methods = {}
local S_meta = { __index = S_methods }
S_meta.__add = function(a, b) local o = M.S() for k in pairs(a) do o[k] = true end for k in pairs(b) do o[k] = true end return o end
S_meta.__mul = function(a, b) local o = M.S() for k in pairs(a) do if b[k] then o[k] = true end end return o end
S_meta.__sub = function(a, b) local o = M.S() for k in pairs(a) do if not b[k] then o[k] = true end end return o end

function M.S(t)
  local s = setmetatable({}, S_meta)
  for _, v in pairs(t or {}) do s[v] = true end
  return s
end
function S_methods:contains(v) return rawget(self, v) == true end
function S_methods:add(v) self[v] = true return self end
function S_methods:remove(v) self[v] = nil return self end
function S_methods:empty() return next(self) == nil end
function S_methods:length() local n = 0 for _ in pairs(self) do n = n + 1 end return n end
function S_methods:it() local k return function() k = next(self, k) return k end end

-- ---- Strings (on the string table: every string has them in this mod) ----

function string.startswith(s, p) return s:sub(1, #p) == p end
function string.endswith(s, p) return p == "" or s:sub(-#p) == p end
function string.contains(s, p) return s:find(p, 1, true) ~= nil end
function string.trim(s) return (s:match("^%s*(.-)%s*$")) end
function string.ucfirst(s) return s:sub(1, 1):upper() .. s:sub(2) end
function string.split(s, sep, max)
  sep = sep or " "
  local out, at = M.T(), 1
  while true do
    if max and #out == max - 1 then out[#out + 1] = s:sub(at) break end
    local i, j = s:find(sep, at, true)
    if not i then out[#out + 1] = s:sub(at) break end
    out[#out + 1] = s:sub(at, i - 1)
    at = j + 1
  end
  return out
end
-- Words, a quoted run ("Cure IV") counting as one.
function M.tokens(s)
  local out, i, n = M.T(), 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c:match("%s") then
      i = i + 1
    elseif c == '"' then
      local j = s:find('"', i + 1, true) or n + 1
      out[#out + 1] = s:sub(i + 1, j - 1)
      i = j + 1
    else
      local j = s:find("%s", i) or n + 1
      out[#out + 1] = s:sub(i, j - 1)
      i = j
    end
  end
  return out
end
string.args = M.tokens
function string.fmt(s, ...) return s:format(...) end

-- The globals a 5.1 file expects, put in `env`.
function M.install(env)
  env.unpack = table.unpack
  env.loadstring = function(text, name) return load(text, name, "t", env) end
  env.tostring = tostring51
  env.bit = bitlib
  env.T, env.S, env.L = M.T, M.S, M.T
  env.math = setmetatable({ pow = function(a, b) return a ^ b end, mod = math.fmod }, { __index = math })
  env.table = setmetatable({ getn = function(t) return #t end, unpack = table.unpack }, { __index = table })
  env.string = string
end

return M
