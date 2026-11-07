-- Corsair rolls (the roll tracker add-ons): our roll's number, lucky or unlucky, and its power, after each roll and
-- Double-Up; optionally holds back a Double-Up on a lucky roll or an 11. Powers as LandSandBoat has them (its
-- corsair job utilities), by roll: the stat and the power for each number 1..11 (12 busts).

local ROLLS = {
  corsairsroll = { "Experience", { 10, 11, 11, 12, 20, 13, 15, 16, 8, 17, 24 } },
  ninjaroll = { "Evasion", { 10, 13, 15, 40, 18, 20, 25, 5, 28, 30, 50 } },
  huntersroll = { "Accuracy", { 10, 13, 15, 40, 18, 20, 25, 5, 28, 30, 50 } },
  chaosroll = { "Attack %", { 6, 8, 9, 25, 11, 13, 16, 3, 17, 19, 31 } },
  magussroll = { "Magic defense", { 5, 20, 6, 8, 9, 3, 10, 13, 14, 15, 25 } },
  healersroll = { "Cure potency received", { 3, 4, 12, 5, 6, 7, 1, 8, 9, 10, 16 } },
  drachenroll = { "", { 10, 13, 15, 40, 18, 20, 25, 5, 28, 30, 50 } },
  choralroll = { "Spell interruption", { 8, 42, 11, 15, 19, 4, 23, 27, 31, 35, 50 } },
  monksroll = { "Subtle Blow", { 8, 10, 32, 12, 14, 16, 4, 20, 22, 24, 40 } },
  beastroll = { "", { 4, 5, 7, 19, 8, 9, 11, 2, 13, 14, 23 } },
  samurairoll = { "Store TP", { 8, 32, 10, 12, 14, 4, 16, 20, 22, 24, 40 } },
  evokersroll = { "Refresh", { 1, 1, 1, 1, 3, 2, 2, 2, 1, 3, 4 } },
  roguesroll = { "Critical hit rate", { 2, 2, 3, 4, 12, 5, 6, 6, 1, 8, 19 } },
  warlocksroll = { "Magic accuracy", { 10, 13, 15, 40, 18, 20, 25, 5, 28, 30, 50 } },
  fightersroll = { "Double Attack", { 2, 2, 3, 4, 12, 5, 6, 7, 1, 9, 18 } },
  puppetroll = { "", { 4, 5, 18, 7, 9, 10, 2, 11, 13, 15, 22 } },
  gallantsroll = { "Defense %", { 4, 5, 19, 7, 8, 10, 3, 11, 13, 15, 23 } },
  wizardsroll = { "Magic attack", { 4, 6, 8, 10, 25, 12, 14, 17, 2, 20, 30 } },
  dancersroll = { "Regen", { 3, 4, 12, 5, 6, 7, 1, 8, 9, 10, 16 } },
  scholarsroll = { "Conserve MP", { 2, 10, 3, 4, 4, 1, 5, 6, 7, 7, 12 } },
  naturalistsroll = { "Enhancing duration", { 6, 7, 15, 8, 9, 10, 5, 11, 12, 13, 20 } },
  runeistsroll = { "Magic evasion", { 4, 6, 8, 25, 10, 12, 14, 2, 17, 20, 30 } },
  boltersroll = { "Movement speed", { 6, 6, 16, 8, 8, 10, 10, 12, 4, 14, 20 } },
  castersroll = { "Fast Cast", { 6, 15, 7, 8, 9, 10, 5, 11, 12, 13, 20 } },
  coursersroll = { "", { 2, 3, 11, 4, 5, 6, 7, 8, 1, 10, 12 } },
  blitzersroll = { "Delay", { -2, -3, -4, -11, -5, -6, -7, -8, -1, -10, -12 } },
  tacticiansroll = { "Regain", { 10, 10, 10, 10, 30, 10, 10, 0, 20, 20, 40 } },
  alliesroll = { "Skillchain damage", { 2, 3, 20, 5, 7, 9, 11, 13, 15, 1, 25 } },
  misersroll = { "Save TP", { 30, 50, 70, 90, 200, 110, 20, 130, 150, 170, 250 } },
  companionsroll = { "", { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 } },
  avengersroll = { "Counter", { 2, 2, 3, 12, 4, 5, 6, 1, 7, 9, 18 } },
}
local ROLL, ROLL_FAIL, DOUBLE, DOUBLE_FAIL, BUST = 420, 422, 424, 425, 426

local current  -- {key, name, total}

local function key_of(name)
  return (name or ""):lower():gsub("[^%a]", "")
end

-- Lucky: the spike among 1..10; unlucky: the dip.
local function lucky_unlucky(powers)
  local hi, lo = 1, 1
  for i = 1, 10 do
    if powers[i] > powers[hi] then hi = i end
    if powers[i] < powers[lo] then lo = i end
  end
  return hi, lo
end

local function say(r, total)
  local d = ROLLS[r.key]
  if not d then return end
  local lucky, unlucky = lucky_unlucky(d[2])
  local mark = total == 11 and " (11!)" or total == lucky and " (Lucky!)" or total == unlucky and " (Unlucky)" or ""
  local stat = d[1] ~= "" and (" %s +%d"):format(d[1], d[2][total]) or (" +%d"):format(d[2][total])
  chat.add(("%s %d%s:%s  (lucky %d, unlucky %d)"):format(r.name, total, mark, stat, lucky, unlucky))
end

events.on("action", function(a)
  local me = game.player()
  if not settings.get("on") or not me or a.actor ~= me.id or a.category ~= 6 then return end
  local first = a.targets and a.targets[1] and a.targets[1].results and a.targets[1].results[1]
  if not first then return end
  local name = (res.ability(0x200 + a.param) or {}).name
  if first.message == ROLL or first.message == ROLL_FAIL then
    if ROLLS[key_of(name)] then
      current = { key = key_of(name), name = name, total = first.value }
      say(current, first.value)
    end
  elseif (first.message == DOUBLE or first.message == DOUBLE_FAIL) and current then
    current.total = first.value
    say(current, first.value)
  elseif first.message == BUST and current then
    chat.add(current.name .. ": Bust!")
    current = nil
  end
end)

-- Double-Up held back on a lucky roll or an 11.
filters.typed(function(line)
  if not settings.get("on") or not settings.get("guard") or not current then return nil end
  if not line:lower():match('^/ja%s+"?double%-up') and not line:lower():match("^/doubleup") then return nil end
  local d = ROLLS[current.key]
  local lucky = d and lucky_unlucky(d[2])
  if current.total == 11 or current.total == lucky then
    chat.add(("Roll Helper: %s is at %d; Double-Up held back."):format(current.name, current.total))
    return false
  end
  return nil
end)

events.on("buff_lose", function(id)
  if current and res.status(id) and key_of(res.status(id)) == current.key then current = nil end
end)
