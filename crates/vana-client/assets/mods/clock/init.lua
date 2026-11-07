-- Fills the clock slot beside the game's clock; set again only when something in it changes.
local last

events.on("frame", function()
  local c = settings.get("on") and game.clock()
  local key = c and table.concat({ c.earth, c.moon_name, c.moon, c.next_day, c.next_minutes }, "|")
  if key == last then return end
  last = key
  ui.native.slot("clock", c or nil)
end)
