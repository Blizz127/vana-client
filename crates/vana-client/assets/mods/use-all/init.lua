-- //useall <item>: each copy in the inventory used in turn (the pouch add-ons), the next once the last was used (its
-- action finished, s2c 0x028 category 5) or refused.

local USE_DONE, USE_START = 5, 9
local busy, stop = false, false

local function held(name)
  local n, id = 0, nil
  for _, it in ipairs(game.find_items(name, { 0 })) do
    n, id = n + it.count, it.id
  end
  return n, id
end

local finished = false
events.on("action", function(a)
  local me = game.player()
  if me and a.actor == me.id and (a.category == USE_DONE or (a.category == USE_START and a.param == 28787)) then
    finished = true
  end
end)

commands.register("useall", function(...)
  if not settings.get("on") then return end
  local name = table.concat({ ... }, " ")
  if name:lower() == "stop" then
    stop = true
    return
  end
  if name == "" then
    chat.add("Item Use Queue: //useall <item>, //useall stop")
    return
  end
  if busy then
    chat.add("Item Use Queue: still using the last item.")
    return
  end
  local n, id = held(name)
  if n == 0 then
    chat.add("Item Use Queue: you have no " .. name .. ".")
    return
  end
  busy, stop = true, false
  local used = 0
  while not stop do
    local left, iid = held(name)
    if left == 0 then break end
    finished = false
    actions.use_item(iid, "<me>")
    local waited = 0
    repeat
      sleep(0.25)
      waited = waited + 0.25
    until finished or waited > 15
    if not finished then break end
    used = used + 1
    sleep(1.5)
  end
  busy = false
  chat.add(("Item Use Queue: used %d %s."):format(used, name))
end)
