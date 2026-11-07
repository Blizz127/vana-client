-- //calc <sum> (the calculator add-ons): + - * / % ^, brackets, and 1.5k / 2m. Parsed by hand, never run as Lua.

local function commas(n)
  local int, frac = tostring(n):match("^(-?%d+)(%.?%d*)$")
  if not int then return tostring(n) end
  local neg = int:sub(1, 1) == "-"
  int = int:gsub("^-", ""):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (neg and "-" or "") .. int .. frac
end

-- A recursive descent over the sum's characters.
local function evaluate(src)
  local s = src:lower():gsub("%s+", ""):gsub(",", "")
  local i = 1
  local expr
  local function peek() return s:sub(i, i) end
  local function number()
    local num = s:match("^%d*%.?%d+", i)
    if not num then error("a number was expected at " .. i, 0) end
    i = i + #num
    local v = tonumber(num)
    local mult = ({ k = 1e3, m = 1e6 })[peek()]
    if mult then
      i = i + 1
      v = v * mult
    end
    return v
  end
  local function atom()
    local c = peek()
    if c == "(" then
      i = i + 1
      local v = expr()
      if peek() ~= ")" then error("a ) is missing", 0) end
      i = i + 1
      return v
    elseif c == "-" then
      i = i + 1
      return -atom()
    end
    return number()
  end
  local function power()
    local v = atom()
    if peek() == "^" then
      i = i + 1
      v = v ^ power()
    end
    return v
  end
  local function term()
    local v = power()
    while true do
      local c = peek()
      if c == "*" or c == "x" then i = i + 1; v = v * power()
      elseif c == "/" then i = i + 1; v = v / power()
      elseif c == "%" then i = i + 1; v = v % power()
      else return v end
    end
  end
  expr = function()
    local v = term()
    while true do
      local c = peek()
      if c == "+" then i = i + 1; v = v + term()
      elseif c == "-" then i = i + 1; v = v - term()
      else return v end
    end
  end
  local v = expr()
  if i <= #s then error("I don't understand '" .. s:sub(i) .. "'", 0) end
  return v
end

local function answer(sum)
  local ok, v = pcall(evaluate, sum)
  if not ok then return nil, v end
  if v ~= v or v == math.huge or v == -math.huge then return nil, "no answer" end
  if v == math.floor(v) and math.abs(v) < 1e15 then return commas(("%d"):format(v)) end
  return commas(("%.4f"):format(v):gsub("0+$", ""):gsub("%.$", ""))
end

local WIN = "calc"
local function open()
  ui.window(WIN, { title = "Calculator", width = 360, elements = {
    { type = "input", id = "sum", label = "Sum", text = "", max = 80 },
    { type = "text", id = "out", text = "" },
  } })
  ui.open(WIN)
end

ui.on(WIN, function(_, e)
  if e.kind == "change" and e.id == "sum" then
    local v, err = answer(e.text)
    ui.update(WIN, "out", { text = v and ("= " .. v) or err })
  end
end)

commands.register("calc", function(...)
  if not settings.get("on") then return end
  local sum = table.concat({ ... }, " ")
  if sum == "" then
    open()
    return
  end
  local v, err = answer(sum)
  chat.add(v and (sum .. " = " .. v) or ("Calculator: " .. err))
end)
