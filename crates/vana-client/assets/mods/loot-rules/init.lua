-- Lots, passes and drops by the character's lists (the treasury and loot add-ons). A list entry is an item name (any
-- case, the short or the log name), a pattern with * for any run of letters, or an item id.

local KINDS = { "lot", "pass", "drop" }
local TITLES = { lot = "Lot", pass = "Pass", drop = "Drop" }
local WIN = "lists"

local tried = {}  -- "slot:item:dropper" -> true: pool items already answered
local view = { tab = 1, at = 1 }

local function lists()
  local s = storage.character
  s.lists = s.lists or {}
  for _, k in ipairs(KINDS) do s.lists[k] = s.lists[k] or {} end
  return s.lists
end

local function names(id)
  local r = res.item(id)
  if not r then return {} end
  return { (r.name or ""):lower(), (r.log_name or ""):lower() }
end

local function matches(entry, id)
  if tonumber(entry) then return tonumber(entry) == id end
  local pat = entry:lower()
  if pat:find("*", 1, true) then
    pat = "^" .. pat:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
    for _, n in ipairs(names(id)) do
      if n:find(pat) then return true end
    end
    return false
  end
  for _, n in ipairs(names(id)) do
    if n == pat then return true end
  end
  return false
end

local function listed(kind, id)
  for _, e in ipairs(lists()[kind]) do
    if matches(e, id) then return true end
  end
  return false
end

-- ---- The pool and the inventory ----

local function pool()
  if not settings.get("on") then return end
  local seen = {}
  for _, t in ipairs(game.treasure()) do
    local key = ("%d:%d:%s"):format(t.slot, t.item, tostring(t.dropper))
    seen[key] = true
    if not tried[key] and not t.lotted and not t.passed then
      if listed("lot", t.item) then
        tried[key] = true
        actions.lot(t.slot)
      elseif listed("pass", t.item) or settings.get("pass_rest") then
        tried[key] = true
        actions.pass(t.slot)
      end
    end
  end
  for k in pairs(tried) do
    if not seen[k] then tried[k] = nil end
  end
end

local sort_due
events.on("item_add", function(bag, slot, id)
  if bag ~= 0 or not settings.get("on") then return end
  if settings.get("drop") and listed("drop", id) then
    actions.drop(slot)
  elseif settings.get("stack") then
    sort_due = os.clock() + 1
  end
end)

timer.every(0.5, function()
  pool()
  if sort_due and os.clock() >= sort_due then
    sort_due = nil
    actions.sort(0)
  end
end)

-- ---- The lists' window ----

local function rows()
  local out = {}
  for _, e in ipairs(lists()[KINDS[view.tab]]) do out[#out + 1] = e end
  return out
end

local function refresh()
  if not ui.is_open(WIN) then return end
  local r = rows()
  view.at = math.max(1, math.min(view.at, #r))
  ui.update(WIN, "tabs", { at = view.tab })
  ui.update(WIN, "items", { rows = r, at = view.at })
end

local function add(kind, entry)
  entry = (entry or ""):match("^%s*(.-)%s*$")
  if entry == "" then return false end
  local l = lists()[kind]
  for _, e in ipairs(l) do
    if e:lower() == entry:lower() then return false end
  end
  l[#l + 1] = entry
  storage.save()
  refresh()
  return true
end

local function remove(kind, entry)
  local l = lists()[kind]
  for i, e in ipairs(l) do
    if e:lower() == entry:lower() then
      table.remove(l, i)
      storage.save()
      refresh()
      return true
    end
  end
  return false
end

local function open()
  ui.window(WIN, {
    title = "Loot Rules", width = 420,
    help = "Type an item name (or a pattern with *) and press Enter to add it to this list.",
    elements = {
      { type = "tabs", id = "tabs", items = { "Lot", "Pass", "Drop" }, at = view.tab },
      { type = "list", id = "items", rows = rows(), height = 10, at = view.at },
      { type = "input", id = "add", label = "Add", text = "", max = 60 },
      { type = "buttons", id = "btn", items = { "Remove" } },
    },
  })
  ui.open(WIN)
  refresh()
end

ui.on(WIN, function(_, e)
  if e.kind == "set" and e.id == "tabs" then
    view.tab, view.at = e.index, 1
    refresh()
  elseif e.kind == "select" and e.id == "items" then
    view.at = e.index
  elseif e.kind == "change" and e.id == "add" then
    if add(KINDS[view.tab], e.text) then ui.update(WIN, "add", { text = "" }) end
  elseif e.kind == "press" and e.id == "btn" then
    view.at = ui.get(WIN, "items").at or view.at
    local r = rows()[view.at]
    if r then remove(KINDS[view.tab], r) end
  end
end)

-- ---- //loot ----

local USAGE = "//loot [lot | pass | drop] [add | remove] <item>, //loot list"

commands.register("loot", function(kind, op, ...)
  kind = (kind or ""):lower()
  if kind == "" then
    if ui.is_open(WIN) then ui.close(WIN) else open() end
    return
  end
  if kind == "list" then
    for _, k in ipairs(KINDS) do
      local l = lists()[k]
      chat.add(("Loot Rules: %s: %s"):format(TITLES[k], #l > 0 and table.concat(l, ", ") or "none"))
    end
    return
  end
  local entry = table.concat({ ... }, " ")
  if not TITLES[kind] or (op ~= "add" and op ~= "remove") or entry == "" then
    chat.add("Loot Rules: " .. USAGE)
    return
  end
  local done = op == "add" and add(kind, entry) or op == "remove" and remove(kind, entry)
  chat.add(("Loot Rules: %s %s the %s list."):format(entry, done and (op == "add" and "added to" or "removed from")
    or (op == "add" and "is already on" or "is not on"), TITLES[kind]))
end)
