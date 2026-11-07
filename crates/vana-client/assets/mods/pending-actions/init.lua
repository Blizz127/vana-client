-- Pending actions (modern UI): a spell, weapon skill, job ability or item we asked for (c2s 0x01A / 0x037) waits
-- until the server answers. An action of ours of its kind confirms it; a battle message of ours soon after the ask is
-- its refusal, kept a few seconds; no answer for a while says so. The window stands in for the "pending" panel.

local WIN = "pending"
local SHOW_AFTER, TIMEOUT, REFUSED_WITHIN, KEEP = 0.15, 5, 2, 4
-- Messages of ours that are not answers: experience, limit and capacity points, a defeat, a level.
local NOT_ANSWERS = { [6] = true, [8] = true, [105] = true, [253] = true, [371] = true, [372] = true, [718] = true, [735] = true }
-- The 0x028 categories that answer each kind: its start or its finish (monster skills finish as 11).
local ANSWERS = { spell = { [4] = true, [8] = true }, ws = { [3] = true, [7] = true, [11] = true },
  ability = { [6] = true, [14] = true, [15] = true }, item = { [5] = true, [9] = true } }
local KIND = { [3] = "spell", [7] = "ws", [9] = "ability" }

local asked

local function me() return (game.player() or {}).id end

local function start(kind, id, target)
  local now = os.clock()
  asked = { kind = kind, id = id, target = target, at = now, state = "waiting", since = now }
end

-- c2s 0x01A: target @4, category @0x0a, param @0x0c (abilities: name-table id - 0x200).
packets.on_out(0x01A, function(p)
  local d = p.data
  if #d < 0x10 then return end
  local target, _, cat, param = string.unpack("<I4I2I2I4", d, 5)
  local kind = KIND[cat]
  if kind then start(kind, kind == "ability" and param + 0x200 or param, target) end
end)

-- c2s 0x037: target @4, the item's index @0x0e and bag @0x10.
packets.on_out(0x037, function(p)
  local d = p.data
  if #d < 0x14 then return end
  local target = string.unpack("<I4", d, 5)
  local index, bag = string.unpack("B", d, 0x0e + 1), string.unpack("<I4", d, 0x10 + 1)
  for _, it in ipairs(game.items(bag)) do
    if it.slot == index then start("item", it.id, target) return end
  end
end)

events.on("action", function(a)
  if asked and asked.state == "waiting" and a.actor == me() and ANSWERS[asked.kind][a.category] then asked = nil end
end)

events.on("battle_message", function(actor, target, message, p1, p2)
  if not asked or asked.state ~= "waiting" or NOT_ANSWERS[message] or actor ~= me() then return end
  if os.clock() - asked.at >= REFUSED_WITHIN then return end
  local m = res.message(message, { actor = actor, target = target, values = { p1, p2 } })
  local why = m and text.strip(m.text):gsub("\n", " "):match("^%s*(.-)%s*$") or ""
  asked.state, asked.since, asked.why = "refused", os.clock(), why
end)

local function name_of(a)
  local r
  if a.kind == "spell" then r = res.spell(a.id) elseif a.kind == "item" then r = res.item(a.id) else r = res.ability(a.id) end
  return r and r.name or ""
end

local function view()
  if not asked then return nil end
  local now = os.clock()
  if asked.state == "waiting" and now - asked.at > TIMEOUT then
    asked.state, asked.since = "quiet", now
  elseif asked.state ~= "waiting" and now - asked.since > KEEP then
    asked = nil
    return nil
  end
  if asked.state == "waiting" and now - asked.at < SHOW_AFTER then return nil end
  local on
  if asked.target ~= 0 and asked.target ~= me() then
    local e = game.entity(asked.target)
    on = e and e.name ~= "" and e.name or nil
  end
  local text = name_of(asked) .. (on and (" \u{2192} " .. on) or "")
  if asked.state == "waiting" then
    return { text = text, note = "waiting" .. ("."):rep(1 + math.floor((now - asked.at) * 3) % 3), tone = "waiting", detail = "" }
  elseif asked.state == "refused" then
    return { text = text, note = "refused", tone = "refused", detail = asked.why or "" }
  end
  return { text = text, note = "no reply", tone = "quiet", detail = "The server has not answered." }
end

local shown
events.on("frame", function()
  local v = settings.get("on") and view() or nil
  if not v then
    if shown then ui.close(WIN) shown = nil end
    return
  end
  local key = v.text .. "|" .. v.note .. "|" .. v.tone .. "|" .. v.detail
  if key == shown then return end
  if shown then
    ui.update(WIN, "chip", v)
  else
    v.type, v.id = "chip", "chip"
    ui.window(WIN, { panel = "pending", hud = true, width = 300, elements = { v } })
    ui.open(WIN)
  end
  shown = key
end)
