-- Hides chat lines (the chat filter add-ons) by speaker, word or kind, and repeated says, shouts and yells. The log
-- modes: 9 say, 10 shout, 11 yell, 12 tell, 13 party, 14 linkshell, 15 emote.

local SAY, SHOUT, YELL = 9, 10, 11
local CHAT = { [9] = true, [10] = true, [11] = true, [12] = true, [13] = true, [14] = true, [15] = true }
local REPEAT_SECS = 60

local seen = {}  -- repeated lines: text -> when

local function list(key)
  local out = {}
  for w in (settings.get(key) or ""):gmatch("[^,]+") do
    w = w:match("^%s*(.-)%s*$"):lower()
    if w ~= "" then out[#out + 1] = w end
  end
  return out
end

-- The speaker as the line shows them: "Name : text", "(Name) text", "<Name> text", "[1]<Name> text", "Name>> text".
local function speaker(line)
  return (line:gsub("^%[%d%]", ""):match("^[<%(>%s]*([%a]+)") or ""):lower()
end

filters.chat(function(raw, mode)
  if not settings.get("on") or not CHAT[mode] then return nil end
  local line = text.strip(raw)
  if (mode == SHOUT and settings.get("shouts")) or (mode == YELL and settings.get("yells")) then return false end
  local who = speaker(line)
  for _, p in ipairs(list("players")) do
    if who == p then return false end
  end
  local low = line:lower()
  for _, w in ipairs(list("words")) do
    if low:find(w, 1, true) then return false end
  end
  if settings.get("repeats") and (mode == SAY or mode == SHOUT or mode == YELL) then
    local now = os.clock()
    local last = seen[low]
    seen[low] = now
    if last and now - last < REPEAT_SECS then return false end
  end
  return nil
end)

-- Old repeats forgotten now and then.
timer.every(60, function()
  local now = os.clock()
  for k, t in pairs(seen) do
    if now - t >= REPEAT_SECS then seen[k] = nil end
  end
end)
