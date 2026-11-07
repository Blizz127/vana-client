-- Hotbars (from PR #88 by Arusia): bars of multi-line macros that load by main job, then sub job; each slot shows its
-- action's icon and recast. See src/data.lua for macros.json. //hb opens the manager.

local data = require("src.data")
local bar = require("src.bar")
local manager = require("src.manager")
local stock = require("src.stock")

local ok, err = data.init({
  read = fs.read,
  write = fs.write,
  decode = json.decode,
  encode = function(value) return json.encode(value, { pretty = true }) end,
  log = log.warn,
})
if not ok then
  chat.add("Hotbars: macros.json could not be read (" .. tostring(err) .. "); a copy was kept as macros.json.bad.")
end

bar.hooks.open_manager = manager.open
bar.hooks.edit_slot = manager.edit_slot
bar.hooks.changed = manager.refresh
manager.hooks.changed = bar.rebuild
manager.hooks.rebind = bar.rebind

-- The game's macro palette hides (its drawing only) while the bars show.
local function apply_stock_palette()
  ui.native.hide("palette", settings.get("on") and settings.get("hide_stock"))
end

local function refresh()
  apply_stock_palette()
  bar.rebind()
  bar.rebuild()
  manager.refresh()
end

refresh()
-- The jobs can arrive after the mod loads, and a job change swaps the macros.
events.on("job_change", function()
  bar.rebuild()
  manager.refresh()
end)
events.on("settings_changed", refresh)
timer.every(1, bar.tick)
timer.every(0.25, bar.recasts)

local USAGE = "//hb [show | hide | run <bar> <slot> | reload | wipestock | restorestock]  (no argument opens the manager)"

commands.register("hb", function(cmd, a, b)
  cmd = (cmd or ""):lower()
  if cmd == "" then
    manager.toggle()
  elseif cmd == "show" then
    bar.set_hidden(false)
  elseif cmd == "hide" then
    bar.set_hidden(true)
  elseif cmd == "run" then
    local bn, sn = tonumber(a), tonumber(b)
    if bn and sn then bar.fire(bn, sn) else chat.add("Hotbars: " .. USAGE) end
  elseif cmd == "wipestock" then
    stock.start_wipe()
  elseif cmd == "restorestock" then
    stock.restore()
  elseif cmd == "reload" then
    local loaded, why = data.load()
    if not loaded then chat.add("Hotbars: macros.json could not be read (" .. tostring(why) .. ").") end
    bar.rebuild()
    manager.refresh()
  else
    chat.add("Hotbars: " .. USAGE)
  end
end)
