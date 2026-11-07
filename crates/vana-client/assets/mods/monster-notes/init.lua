-- An info bar (the info bar add-ons): the zone, Vana'diel time and weather, and the target with its last /check
-- and our notes on its name. A check's answer is message 170..178 (evasion and defence), the level and 64 + the
-- difficulty.

local DIFFICULTY = { [0] = "too weak", "incredibly easy prey", "easy prey", "decent challenge", "even match", "tough",
  "very tough", "incredibly tough" }
local checks = {}

local function notes()
  local s = storage.account
  s.notes = s.notes or {}
  return s.notes
end

events.on("battle_message", function(actor, target, message, p1, p2)
  if message >= 170 and message <= 178 then
    -- 170 high evasion and defence .. 174 neither .. 178 low evasion and defence
    local k = message - 174
    local def = (k == -4 or k == -1 or k == 2) and "high defence" or ((k == -2 or k == 1 or k == 4) and "low defence" or nil)
    local eva = k <= -2 and "high evasion" or (k >= 2 and "low evasion" or nil)
    -- the checked monster is the message's target when we are the actor
    local id = (actor == (game.player() or {}).id) and target or actor
    checks[id] = { level = p1, word = DIFFICULTY[p2 - 64], def = def, eva = eva }
  elseif message == 249 then
    local id = (actor == (game.player() or {}).id) and target or actor
    checks[id] = { word = "impossible to gauge" }
  end
end)

events.on("zone_change", function() checks = {} end)

local function target_text()
  local t = game.target()
  if not t then return nil end
  local parts = { t.name }
  if t.kind == "mob" then parts[#parts + 1] = ("%d%%"):format(t.hpp) end
  parts[#parts + 1] = ("%.1f'"):format(t.distance)
  local c = checks[t.id]
  if c then
    local bits = {}
    if c.level then bits[#bits + 1] = "Lv " .. c.level end
    if c.word then bits[#bits + 1] = c.word end
    if c.def then bits[#bits + 1] = c.def end
    if c.eva then bits[#bits + 1] = c.eva end
    parts[#parts + 1] = table.concat(bits, ", ")
  end
  local n = notes()[t.name:lower()]
  if n then parts[#parts + 1] = "\u{201C}" .. n .. "\u{201D}" end
  return table.concat(parts, "  \u{00B7}  ")
end

local function draw()
  if not settings.get("on") then hud.clear() return end
  local p = game.player()
  if not p then return end
  local tm = game.time()
  local left = ("%s  \u{00B7}  %02d:%02d %s  \u{00B7}  %s"):format(res.zone(p.zone) or "?", tm.hour, tm.minute,
    res.day(tm.weekday) or "", res.weather(game.weather()) or "")
  local tt = target_text()
  local scr = hud.screen()
  local u = scr.ui_scale
  local y = settings.get("place") == "Top" and 6 * u or scr.height * 0.6
  hud.text("bar", { x = scr.width / 2, y = y, text = left .. (tt and ("   \u{2014}   " .. tt) or ""), size = 0.95,
    align = "center", colour = { 235, 230, 215, 255 }, bg = { 12, 14, 22, 190 }, pad = 5 * u, outline = { 0, 0, 0, 180 } })
end

events.on("frame", draw)

commands.register("mobnote", function(...)
  local text = table.concat({ ... }, " ")
  local t = game.target()
  if not t then chat.add("Monster Notes: target a monster first.") return end
  local key = t.name:lower()
  if text == "" then
    chat.add("Monster Notes: " .. t.name .. ": " .. (notes()[key] or "no note."))
  elseif text:lower() == "clear" then
    notes()[key] = nil
    chat.add("Monster Notes: note on " .. t.name .. " removed.")
  else
    notes()[key] = text
    chat.add("Monster Notes: noted on " .. t.name .. ".")
  end
end)
