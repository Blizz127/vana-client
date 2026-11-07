-- Tells while away (the answering machine add-ons): while the game's /away flag is up they are kept (and each sender
-- may get one away reply); back /online, they are listed; //tells shows them again; //r <message> answers the last
-- tell whenever.

local TELL = 3
local WIN = "tells"
local last_sender

local function state()
  local s = storage.character
  s.inbox = s.inbox or {}
  return s
end

local function rows()
  local out = {}
  for _, t in ipairs(state().inbox) do out[#out + 1] = ("%s  %s: %s"):format(t.at, t.from, t.text) end
  return out
end

local function show()
  local r = rows()
  if #r == 0 then
    chat.add("Tell Inbox: no tells kept.")
    return
  end
  ui.window(WIN, {
    title = "Tells", width = 560,
    elements = {
      { type = "list", id = "list", rows = r, height = math.min(12, #r), at = #r },
      { type = "buttons", id = "btn", items = { "Clear", "Close" } },
    },
  })
  ui.open(WIN)
end

ui.on(WIN, function(_, e)
  if e.kind == "press" and e.id == "btn" then
    if e.index == 1 then
      state().inbox = {}
      storage.save()
    end
    ui.close(WIN)
  end
end)

local function away()
  local me = game.player()
  return me and me.away
end

events.on("chat_message", function(line, sender, kind)
  if kind ~= TELL or not settings.get("on") then return end
  local me = game.player()
  if me and sender == me.name then return end
  last_sender = sender
  if not away() then return end
  local s = state()
  s.inbox[#s.inbox + 1] = { at = os.date("%H:%M"), from = sender, text = text.strip(text.plain(line)) }
  storage.save()
  local reply = settings.get("reply") or ""
  s.answered = s.answered or {}
  if reply ~= "" and not s.answered[sender] then
    s.answered[sender] = true
    commands.run(("/tell %s %s"):format(sender, reply))
  end
end)

-- Back from /away: what came meanwhile.
local was_away = false
timer.every(1, function()
  local now = away() or false
  if was_away and not now and settings.get("on") then
    local s = state()
    s.answered = {}
    local n = #s.inbox
    chat.add(("Tell Inbox: %d tell%s while you were away."):format(n, n == 1 and "" or "s"))
    if n > 0 then show() end
  end
  was_away = now
end)

commands.register("r", function(...)
  local msg = table.concat({ ... }, " ")
  if not last_sender then
    chat.add("Tell Inbox: no tell to answer yet.")
  elseif msg == "" then
    chat.add("Tell Inbox: //r <message> answers " .. last_sender .. ".")
  else
    commands.run(("/tell %s %s"):format(last_sender, msg))
  end
end)

commands.register("tells", show)
