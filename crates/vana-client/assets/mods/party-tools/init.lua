-- Invites answered by list and invites sent for a word in a tell (the auto-join and auto-invite add-ons).

local TELL = 3

local function names(key)
  local out = {}
  for n in (settings.get(key) or ""):gmatch("[^,]+") do
    n = n:match("^%s*(.-)%s*$"):lower()
    if n ~= "" then out[n] = true end
  end
  return out
end

events.on("party_invite", function(from)
  if not settings.get("on") then return end
  local ok = names("join")
  if ok["*"] or ok[(from or ""):lower()] then
    sleep(1)
    actions.join()
  elseif settings.get("decline") then
    sleep(1)
    actions.decline()
  end
end)

events.on("chat_message", function(line, sender, kind)
  if not settings.get("on") or kind ~= TELL then return end
  local word = (settings.get("word") or ""):lower():match("^%s*(.-)%s*$")
  if word == "" or not text.plain(line):lower():find(word, 1, true) then return end
  local only = names("invite")
  if next(only) and not only[sender:lower()] then return end
  for _, m in ipairs(game.party()) do
    if m.name == sender then return end
  end
  actions.invite(sender)
end)
