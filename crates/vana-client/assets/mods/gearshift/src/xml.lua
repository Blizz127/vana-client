-- A lenient XML reader for players' rule files, accepting what the add-ons' parsers accept: raw < > & in
-- attribute values, any closing tag closing the open element, element names with = and quotes in them (a known bad
-- export), unquoted attribute values. Comments, processing instructions and the doctype are skipped; CDATA and the
-- five entities plus &#n; / &#xn; decoded, unknown entities kept as written.

local M = {}

local ENTITY = { lt = "<", gt = ">", amp = "&", quot = '"', apos = "'" }

local function decode(s)
  return (s:gsub("&(#?[xX]?)(%w+);", function(kind, v)
    if kind == "" then return ENTITY[v] or ("&" .. v .. ";") end
    local n = tonumber(v, (kind == "#x" or kind == "#X") and 16 or 10)
    return n and n < 0x110000 and utf8.char(n) or ("&" .. kind .. v .. ";")
  end))
end

-- An element: {name, attrs = {{name, value}...} in order, attr = {lower name -> first value}, children, text, line}.
-- `text` is its first text run that is not all whitespace, verbatim; such runs are also children named "".
local function node(name, line)
  return { name = name, attrs = {}, attr = {}, children = {}, text = "", line = line }
end

local function add_text(top, run, line)
  if run:find("%S") then
    if top.text == "" then top.text = run end
    table.insert(top.children, { name = "", text = run, attrs = {}, attr = {}, children = {}, line = line })
  end
end

function M.parse(src)
  local pos, len = 1, #src
  local function line_at(p)
    local _, n = src:sub(1, p):gsub("\n", "")
    return n + 1
  end
  local function fail(msg) error(("XML line %d: %s"):format(line_at(pos), msg), 0) end

  local root = node("#document", 1)
  local stack = { root }
  while pos <= len do
    local lt = src:find("<", pos, true)
    local top = stack[#stack]
    if not lt then
      add_text(top, decode(src:sub(pos)), line_at(pos))
      break
    end
    if lt > pos then add_text(top, decode(src:sub(pos, lt - 1)), line_at(pos)) end
    pos = lt
    if src:sub(pos, pos + 3) == "<!--" then
      local e = src:find("-->", pos + 4, true) or fail("unclosed comment")
      pos = e + 3
    elseif src:sub(pos, pos + 8) == "<![CDATA[" then
      local e = src:find("]]>", pos + 9, true) or fail("unclosed CDATA")
      add_text(top, src:sub(pos + 9, e - 1), line_at(pos))
      pos = e + 3
    elseif src:sub(pos, pos + 1) == "<?" then
      local e = src:find("?>", pos + 2, true) or fail("unclosed processing instruction")
      pos = e + 2
    elseif src:sub(pos, pos + 1) == "<!" then
      local e = src:find(">", pos + 2, true) or fail("unclosed declaration")
      pos = e + 1
    elseif src:sub(pos, pos + 1) == "</" then
      -- Any closing tag closes the open element, as the add-ons' parser has it.
      local e = src:find(">", pos + 2, true) or fail("unclosed closing tag")
      if #stack == 1 then fail("a closing tag with nothing open") end
      table.remove(stack)
      pos = e + 1
    else
      local name, p = src:match("^<([^%s/>%?\0]+)()", pos)
      if not name then fail("bad tag") end
      local n = node(name, line_at(pos))
      while true do
        p = src:match("^%s*()", p)
        if src:sub(p, p + 1) == "/>" then
          p = p + 2
          table.insert(top.children, n)
          break
        elseif src:sub(p, p) == ">" then
          p = p + 1
          table.insert(top.children, n)
          table.insert(stack, n)
          break
        elseif p > len then
          fail("<" .. name .. "> is never finished")
        end
        local an, _, av, after = src:match("^([^%s/<>=%?!]+)%s*=%s*(['\"])(.-)%2()", p)
        if not an then
          an, av, after = src:match("^([^%s/<>=%?!]+)%s*=%s*([^%s/>]+)()", p)
          if not an then fail("bad attribute in <" .. name .. ">") end
        end
        av = decode(av)
        table.insert(n.attrs, { name = an, value = av })
        if n.attr[an:lower()] == nil then n.attr[an:lower()] = av end
        p = after
      end
      pos = p
    end
  end
  if #stack > 1 then
    local open = stack[#stack]
    error(("XML: <%s> (line %d) is never closed"):format(open.name, open.line), 0)
  end
  return root
end

-- An attribute's first value by its exact name (case counts), or nil.
function M.get(n, name)
  for _, a in ipairs(n.attrs) do
    if a.name == name then return a.value end
  end
end

-- The first child element named `name` (any case), or nil.
function M.child(n, name)
  local want = name:lower()
  for _, c in ipairs(n.children) do
    if c.name:lower() == want then return c end
  end
end

-- The text of a node with its whitespace trimmed.
function M.trim(s)
  return (s or ""):match("^%s*(.-)%s*$")
end

return M
