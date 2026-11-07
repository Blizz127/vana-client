-- The synthesis window's count step (client option synth_amount) asks how many; the first goes out from the window,
-- the rest one after another, each once the last is over, from fresh stacks.
local left, recipe = 0, nil

local function update()
  local on = settings.get("on") == true
  client.set_option("synth_amount", on)
  if not on then left = 0 end
end

update()
events.on("settings_changed", update)

events.on("synth_amount", function(count, r)
  left, recipe = count - 1, r
end)

-- Anything but a result (made or failed) ends the run, as does a zone change.
events.on("synth_result", function(result)
  if result ~= 0 and result ~= 1 and result ~= 12 then left = 0 end
end)
events.on("zone_change", function() left = 0 end)

events.on("frame", function()
  if left > 0 and not game.synth().busy then
    left = left - 1
    -- A refusal (missing materials, a full bag) prints its line and ends the run.
    if not actions.synth(recipe.crystal, recipe.items) then left = 0 end
  end
end)
