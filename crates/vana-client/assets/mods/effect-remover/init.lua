-- //cancel <effects>: cancels our status effects by name (any case, * for any run of letters) or id, several
-- separated by commas (the cancel add-ons). The server refuses the ones that cannot be cancelled.

local function matcher(entry)
  entry = entry:match("^%s*(.-)%s*$")
  local id = tonumber(entry)
  if id then return function(s) return s == id end end
  local pat = entry:lower()
  if pat:find("*", 1, true) then
    pat = "^" .. pat:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
    return function(s) return ((res.status(s) or ""):lower()):find(pat) ~= nil end
  end
  return function(s) return (res.status(s) or ""):lower() == pat end
end

commands.register("cancel", function(...)
  if not settings.get("on") then return end
  local line = table.concat({ ... }, " ")
  if line:match("^%s*$") then
    chat.add("Effect Remover: //cancel <effect>[, <effect>...] (a name, a name with *, or an id)")
    return
  end
  local done = {}
  for entry in line:gmatch("[^,]+") do
    local hit = matcher(entry)
    for _, b in ipairs(game.buffs()) do
      if not done[b.id] and hit(b.id) then
        done[b.id] = true
        actions.cancel(b.id)
      end
    end
  end
  if not next(done) then chat.add("Effect Remover: you have no such effect.") end
end)
