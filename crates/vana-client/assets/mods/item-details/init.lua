-- Weapon skill points on trial weapons (latentchecker and kin): the extdata's first u16 is the points so far; the
-- points each weapon needs are LandSandBoat's.

local TRIALS = require("src.trials")
local BAGS = { 0, 1, 2, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16 }

local function points(it)
  local x = it and it.extdata
  if not x or #x < 2 then return 0 end
  local a, b = x:byte(1, 2)
  return a + b * 256
end

local function line(id, it)
  local r = res.item(id)
  local have, need = math.min(points(it), TRIALS[id]), TRIALS[id]
  return ("%s: %d / %d weapon skill points%s"):format(r and r.name or ("item " .. id), have, need,
    have >= need and " (ready)" or "")
end

-- The highlighted trial weapon's line, under the screen's top.
local shown
timer.every(0.2, function()
  local h = settings.get("on") and ui.native.highlighted()
  local text
  if h and h.kind == "item" and TRIALS[h.id] and h.bag and h.slot then
    for _, it in ipairs(game.items(h.bag)) do
      if it.slot == h.slot then text = line(h.id, it) break end
    end
  end
  if text then
    local scr = hud.screen()
    local u = scr.ui_scale
    hud.text("trial", { x = scr.width / 2, y = scr.height * 0.12, text = text, size = 1.0, align = "center",
      colour = { 240, 236, 224, 255 }, bg = { 14, 16, 26, 220 }, pad = 6 * u, outline = { 0, 0, 0, 200 }, layer = 20 })
    shown = true
  elseif shown then
    hud.remove("trial")
    shown = false
  end
end)

commands.register("trials", function()
  if not settings.get("on") then return end
  local n = 0
  for _, bag in ipairs(BAGS) do
    for _, it in ipairs(game.items(bag)) do
      if TRIALS[it.id] then
        chat.add("Item Details: " .. line(it.id, it))
        n = n + 1
      end
    end
  end
  if n == 0 then chat.add("Item Details: no trial weapon held.") end
end)
