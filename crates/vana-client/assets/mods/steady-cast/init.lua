-- Steady Cast (castdelay): a spell, item or shot started while we move is held until we stand still. Gearshift's
-- hooks run before ours (it loads first), so its gear before the action goes at once and the rest waits with it.

local hold = require("src.hold")

local function on_out(p)
  -- A packet another mod dropped (Gearshift sends a copy of it) is not ours to hold.
  if p.blocked or not settings.get("on") then return nil end
  hold.holds.items, hold.holds.shots = settings.get("items"), settings.get("shots")
  return hold.out(p.id, p.data, clock())
end
for _, id in ipairs({ 0x01A, 0x037, 0x050, 0x051 }) do packets.on_out(id, on_out) end

events.on("frame", function()
  local p = game.player()
  hold.frame(p and p.pos, clock(), function(d) packets.inject_out(d) end)
end)
