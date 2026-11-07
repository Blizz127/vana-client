-- One of the game's call sounds when chat needs us (the chat monitor add-ons): tells, our name, chosen words, invites,
-- checks, emotes at us. The call sounds are the interface sounds 17 (<call0>) .. 38 (<call21>).

local TELL, PARTY, LINKSHELL, LINKSHELL2 = 3, 4, 5, 0x1b
local SPOKEN = { [0] = true, [1] = true, [4] = true, [5] = true, [0x1a] = true, [0x1b] = true, [0x21] = true }

local focused = true
local last = 0

local function alert()
  if not settings.get("on") or (settings.get("away") and focused) then return end
  -- One call at a time, as the game plays them.
  if os.clock() - last < 1 then return end
  last = os.clock()
  audio.play_ui(17 + settings.get("sound"))
end

local function has_word(text, word)
  return word ~= "" and (" " .. text:lower() .. " "):find("[^%w]" .. word:lower():gsub("%p", "%%%0") .. "[^%w]") ~= nil
end

local function words()
  local out = {}
  for w in (settings.get("words") or ""):gmatch("[^,]+") do
    w = w:match("^%s*(.-)%s*$")
    if w ~= "" then out[#out + 1] = w end
  end
  return out
end

events.on("chat_message", function(line, sender, kind)
  local me = game.player()
  local name = me and me.name or ""
  if sender == name then return end
  line = text.plain(line)
  if kind == TELL then
    if settings.get("tells") then alert() end
    return
  end
  if (kind == PARTY and settings.get("party")) or ((kind == LINKSHELL or kind == LINKSHELL2) and settings.get("linkshell"))
    or (SPOKEN[kind] and settings.get("mentions") and has_word(line, name)) then
    alert()
    return
  end
  for _, w in ipairs(words()) do
    if has_word(line, w) then
      alert()
      return
    end
  end
end)

events.on("party_invite", function()
  if settings.get("invites") then alert() end
end)

events.on("examined", function()
  if settings.get("examined") then alert() end
end)

events.on("emote", function(actor, target)
  local me = game.player()
  if settings.get("emotes") and me and target == me.id and actor ~= me.id then alert() end
end)

events.on("focus_change", function(has) focused = has end)
