-- A small backtracking regex for rule files' (regex)...(/regex) patterns: alternation, groups, [classes], . ^ $,
-- * + ? {m,n} (greedy and lazy), \d \w \s \D \W \S \b and escaped characters. Unanchored unless the pattern anchors
-- itself.

local M = {}

local CLASSES = {
  d = function(c) return c:match("%d") ~= nil end,
  w = function(c) return c:match("[%w_]") ~= nil end,
  s = function(c) return c:match("%s") ~= nil end,
}

local function parse(p)
  local pos = 1
  local function peek(n) return p:sub(pos, pos + (n or 1) - 1) end
  local alt

  local function escape_class(c)
    local f = CLASSES[c:lower()]
    if not f then return nil end
    if c:match("%u") then return function(x) return not f(x) end end
    return f
  end

  local function set()
    pos = pos + 1
    local node = { t = "set", neg = false, items = {} }
    if peek() == "^" then
      node.neg = true
      pos = pos + 1
    end
    local first = true
    while pos <= #p and (peek() ~= "]" or first) do
      first = false
      local c = peek()
      if c == "\\" then
        local e = p:sub(pos + 1, pos + 1)
        local f = escape_class(e)
        node.items[#node.items + 1] = f and { f = f } or { a = e, b = e }
        pos = pos + 2
      elseif p:sub(pos + 1, pos + 1) == "-" and p:sub(pos + 2, pos + 2) ~= "]" and pos + 2 <= #p then
        node.items[#node.items + 1] = { a = c, b = p:sub(pos + 2, pos + 2) }
        pos = pos + 3
      else
        node.items[#node.items + 1] = { a = c, b = c }
        pos = pos + 1
      end
    end
    if peek() ~= "]" then error("regex: missing ]", 0) end
    pos = pos + 1
    return node
  end

  local function atom()
    local c = peek()
    if c == "(" then
      pos = pos + 1
      if peek(2) == "?:" then pos = pos + 2 end
      local n = alt()
      if peek() ~= ")" then error("regex: missing )", 0) end
      pos = pos + 1
      return { t = "group", n = n }
    elseif c == "[" then
      return set()
    elseif c == "." then
      pos = pos + 1
      return { t = "any" }
    elseif c == "^" then
      pos = pos + 1
      return { t = "bol" }
    elseif c == "$" then
      pos = pos + 1
      return { t = "eol" }
    elseif c == "\\" then
      local e = p:sub(pos + 1, pos + 1)
      pos = pos + 2
      if e == "b" then return { t = "wb" } end
      local f = escape_class(e)
      if f then return { t = "set", neg = false, items = { { f = f } } } end
      return { t = "char", c = e }
    end
    pos = pos + 1
    return { t = "char", c = c }
  end

  local function seq()
    local items = {}
    while pos <= #p and peek() ~= "|" and peek() ~= ")" do
      local a = atom()
      local c, mn, mx = peek(), nil, nil
      if c == "*" then
        mn, mx = 0, math.huge
      elseif c == "+" then
        mn, mx = 1, math.huge
      elseif c == "?" then
        mn, mx = 0, 1
      elseif c == "{" then
        local a1, comma, b1, e = p:match("^{(%d*)(,?)(%d*)}()", pos)
        if a1 and (a1 ~= "" or b1 ~= "") then
          mn = tonumber(a1) or 0
          mx = comma == "" and mn or (tonumber(b1) or math.huge)
          pos = e - 1
        end
      end
      if mn then
        pos = pos + 1
        local lazy = peek() == "?"
        if lazy then pos = pos + 1 end
        a = { t = "rep", n = a, mn = mn, mx = mx, lazy = lazy }
      end
      items[#items + 1] = a
    end
    return { t = "seq", items = items }
  end

  alt = function()
    local alts = { seq() }
    while peek() == "|" do
      pos = pos + 1
      alts[#alts + 1] = seq()
    end
    return #alts == 1 and alts[1] or { t = "alt", alts = alts }
  end

  local n = alt()
  if pos <= #p then error("regex: unexpected " .. peek(), 0) end
  return n
end

local function in_set(n, c, ci)
  local hit = false
  for _, it in ipairs(n.items) do
    if it.f then
      if it.f(c) then hit = true break end
    else
      if c >= it.a and c <= it.b then hit = true break end
      if ci then
        local l, u = c:lower(), c:upper()
        if (l >= it.a and l <= it.b) or (u >= it.a and u <= it.b) then hit = true break end
      end
    end
  end
  return hit ~= n.neg
end

local function word(s, i) return i >= 1 and i <= #s and s:sub(i, i):match("[%w_]") ~= nil end

local function m(n, s, i, ci, k)
  local t = n.t
  if t == "char" then
    local c = s:sub(i, i)
    if c ~= "" and (c == n.c or (ci and c:lower() == n.c:lower())) then return k(i + 1) end
    return false
  elseif t == "any" then
    if i <= #s and s:sub(i, i) ~= "\n" then return k(i + 1) end
    return false
  elseif t == "set" then
    if i <= #s and in_set(n, s:sub(i, i), ci) then return k(i + 1) end
    return false
  elseif t == "bol" then
    return i == 1 and k(i)
  elseif t == "eol" then
    return i == #s + 1 and k(i)
  elseif t == "wb" then
    return word(s, i - 1) ~= word(s, i) and k(i)
  elseif t == "group" then
    return m(n.n, s, i, ci, k)
  elseif t == "seq" then
    local items = n.items
    local function step(j, x)
      if x > #items then return k(j) end
      return m(items[x], s, j, ci, function(j2) return step(j2, x + 1) end)
    end
    return step(i, 1)
  elseif t == "alt" then
    for _, a in ipairs(n.alts) do
      if m(a, s, i, ci, k) then return true end
    end
    return false
  elseif t == "rep" then
    local function try(j, count)
      local function more()
        return count < n.mx and m(n.n, s, j, ci, function(j2)
          if j2 == j then return false end
          return try(j2, count + 1)
        end)
      end
      if n.lazy then
        if count >= n.mn and k(j) then return true end
        return more()
      end
      if more() then return true end
      return count >= n.mn and k(j)
    end
    return try(i, 0)
  end
  return false
end

local cache = {}

-- Whether `pattern` matches anywhere in `subject`; `case` makes it case-sensitive. A bad pattern raises.
function M.test(pattern, subject, case)
  local n = cache[pattern]
  if not n then
    n = parse(pattern)
    cache[pattern] = n
  end
  subject = tostring(subject)
  for i = 1, #subject + 1 do
    if m(n, subject, i, not case, function() return true end) then return true end
  end
  return false
end

return M
