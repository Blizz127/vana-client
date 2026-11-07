-- Multibox control (send, SubTarget, switch_focus, stna, chatPorter and kin): what the player types in one window
-- runs in the others on this machine. Messages are "<kind>\t<payload>" to the same mod there.

local function say(t) chat.add("Multibox Control: " .. t) end

-- The worst ailment first, and the spell that removes it.
local NA = {
  { 15, 20 }, { 7, 18 }, { 6, 17 }, { 4, 15 }, { 9, 20 }, { 20, 20 }, { 31, 19 }, { 8, 19 }, { 5, 16 }, { 3, 14 },
}
local ERASE = 143
local ERASABLE = {}
for _, s in ipairs({ 11, 12, 13, 21, 134, 135, 136, 137, 138, 139, 140, 141, 142, 144, 145, 146, 147, 148, 149, 167,
  168, 174, 175, 186, 192, 194 }) do ERASABLE[s] = true end

local function knows(spell)
  for _, id in ipairs(game.spells()) do
    if id == spell then return (game.recasts().spells[spell] or 0) == 0 end
  end
  return false
end

-- The party member and spell for the worst ailment we can remove, or nil.
local function pick_na()
  local best
  for _, m in ipairs(game.party()) do
    if m.slot < 6 and m.in_zone and m.hp > 0 then
      local has = {}
      for _, b in ipairs(m.buffs or {}) do has[b] = true end
      for rank, na in ipairs(NA) do
        if has[na[1]] and knows(na[2]) and (not best or rank < best.rank) then best = { rank = rank, name = m.name, spell = na[2] } end
      end
      if not best then
        for b in pairs(has) do
          if ERASABLE[b] and knows(ERASE) then best = { rank = #NA + 1, name = m.name, spell = ERASE } break end
        end
      end
    end
  end
  return best
end

local function stna()
  local n = pick_na()
  if not n then return say("nothing to remove that this job can.") end
  actions.cast(n.spell, n.name)
end

local function me() return (game.player() or {}).name end

local HANDLERS = {
  run = function(line) commands.run(line) end,
  target = function(id) actions.target(tonumber(id)) end,
  focus = function() client.focus() end,
  stna = function() stna() end,
  tell = function(line) if settings.get("relay_tells") then chat.add(line) end end,
}

events.on("ipc_message", function(text, from)
  if not settings.get("on") then return end
  local kind, payload = text:match("^(%a+)\t?(.*)$")
  local h = kind and HANDLERS[kind]
  if h then h(payload, from) end
end)

-- To one character, every other window, or (all) them and us.
local function send(who, kind, payload)
  local msg = kind .. "\t" .. (payload or "")
  local w = (who or "others"):lower()
  if w == "all" or w == "others" then
    ipc.send(msg)
    if w == "all" then HANDLERS[kind](payload or "", me()) end
  elseif w == (me() or ""):lower() then
    HANDLERS[kind](payload or "", me())
  else
    ipc.send(msg, who)
  end
end

commands.register("send", function(who, ...)
  if not settings.get("on") then return end
  local line = table.concat({ ... }, " ")
  if not who or line == "" then say("//send <name | all | others> <command>") return end
  send(who, "run", line)
end)

commands.register("sendtarget", function(who)
  if not settings.get("on") then return end
  local t = game.target()
  if not t then say("target something first.") return end
  send(who or "others", "target", tostring(t.id))
end)

commands.register("focus", function(who)
  if not settings.get("on") then return end
  if not who then say("//focus <name>") return end
  send(who, "focus")
end)

commands.register("stna", function(who)
  if not settings.get("on") then return end
  if who then send(who, "stna") else stna() end
end)

events.on("chat_message", function(text, sender, kind)
  if settings.get("on") and kind == 3 and sender ~= "" then
    ipc.send("tell\t" .. ("[%s] %s>> %s"):format(me() or "?", sender, text))
  end
end)
