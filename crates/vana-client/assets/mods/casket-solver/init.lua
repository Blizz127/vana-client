-- Treasure casket combinations, 10..99, narrowed by the hint lines the game prints (LandSandBoat's caskets: greater
-- / less than, even / odd digits, one digit is N, the first or second digit is one of three) and by wrong guesses.
-- A new casket starts over; an opened lock or the answer shown ends it.

local left
local pending = {}

local function reset()
  left = {}
  for n = 10, 99 do left[n] = true end
end

local function keep(test)
  if not left then reset() end
  for n in pairs(left) do
    if not test(n // 10, n % 10, n) then left[n] = nil end
  end
  pending[#pending + 1] = true
end

local function nums(s)
  local out = {}
  for d in s:gmatch("%d+") do out[#out + 1] = tonumber(d) end
  return out
end

local function hint(line)
  local l = line:lower()
  if l:find("concealing a treasure chest") then
    reset()
    return
  end
  if l:find("correct combination was") or l:find("succeeded in opening the lock") then
    left = nil
    return
  end
  if not l:find("you have a hunch") then return end
  local a, b = l:match("combination is greater than (%d+) and less than (%d+)")
  if a then return keep(function(_, _, n) return n > tonumber(a) and n < tonumber(b) end) end
  a = l:match("is greater than (%d+)")
  if a then return keep(function(_, _, n) return n > tonumber(a) end) end
  a = l:match("is less than (%d+)")
  if a then return keep(function(_, _, n) return n < tonumber(a) end) end
  local which, parity = l:match("(%a+) digit is (%a+)%.")
  if which and (parity == "even" or parity == "odd") then
    local want = parity == "odd" and 1 or 0
    return keep(function(t, o) return ((which == "first" and t or o) % 2) == want end)
  end
  a = l:match("one of the two digits is (%d)")
  if a then
    a = tonumber(a)
    return keep(function(t, o) return t == a or o == a end)
  end
  local w, list = l:match("(%a+) digit is ([%d ,or]+)%.")
  if w and (w == "first" or w == "second") then
    local set = {}
    for _, d in ipairs(nums(list)) do set[d] = true end
    return keep(function(t, o) return set[w == "first" and t or o] end)
  end
end

filters.chat(function(line)
  if settings.get("on") then hint(text.strip(line)) end
  return nil
end)

-- The middle of what is left: the guess that halves it.
local function report()
  if not left or #pending == 0 then return end
  pending = {}
  local list = {}
  for n in pairs(left) do list[#list + 1] = n end
  table.sort(list)
  if #list == 0 then
    chat.add("Casket Solver: no combination fits the hints.")
  elseif #list == 1 then
    chat.add(("Casket Solver: the combination is %d."):format(list[1]))
  else
    local shown = #list <= 12 and (": " .. table.concat(list, ", ")) or ""
    chat.add(("Casket Solver: %d left%s. Try %d."):format(#list, shown, list[(#list + 1) // 2]))
  end
end

timer.every(0.5, report)
