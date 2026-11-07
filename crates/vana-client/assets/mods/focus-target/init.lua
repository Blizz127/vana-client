-- The focus panel (modern UI): the focus target and the last target, each a row with its HP; a click targets it.
-- The window stands in for the built-in "focus" panel, so it sits on the target panel as that did.

local WIN = "focus"
local last_key

local function rows()
  local p = game.player()
  local out = {}
  if p and p.focus_target then out[#out + 1] = { entity = p.focus_target, label = "Focus", tag = "<ft>" } end
  if p and p.last_target then out[#out + 1] = { entity = p.last_target, label = "Last", tag = "<lt>" } end
  return out
end

events.on("frame", function()
  local r = settings.get("on") and rows() or {}
  local key = {}
  for _, row in ipairs(r) do key[#key + 1] = row.label .. row.entity end
  key = table.concat(key, ",")
  if key == last_key then return end
  last_key = key
  if #r == 0 then
    ui.close(WIN)
    return
  end
  ui.window(WIN, { panel = "focus", hud = true, width = 340, elements = { { type = "targets", id = "rows", rows = r } } })
  ui.open(WIN)
end)
