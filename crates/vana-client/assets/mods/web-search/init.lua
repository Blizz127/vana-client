-- //wiki and //ah (the lookup add-ons): the words given, else the item / spell / ability under a list's cursor, else
-- our target's name, looked up in the browser.

local SITES = {
  wiki = "https://www.bg-wiki.com/index.php?search=",
  ah = "https://www.ffxiah.com/search/item?q=",
}

local function encode(s)
  return (s:gsub("[^%w%-%._~]", function(c) return ("%%%02X"):format(c:byte()) end))
end

-- What the player points at: a list row's item, spell or ability, else the target.
local function pointed()
  local h = ui.native.highlighted()
  if h then
    if h.kind == "item" then
      local r = res.item(h.id)
      if r then return r.name end
    elseif h.kind == "spell" then
      local r = res.spell(h.id)
      if r then return r.name end
    elseif h.kind == "ability" then
      local r = res.ability(h.id)
      if r then return r.name end
    elseif h.kind == "key_item" then
      local r = res.key_item(h.id)
      if r then return r.name end
    end
  end
  local t = game.target()
  return t and t.name
end

local function search(site)
  return function(...)
    if not settings.get("on") then return end
    local words = table.concat({ ... }, " "):match("^%s*(.-)%s*$")
    if words == "" then words = pointed() or "" end
    if words == "" then
      chat.add(("Web Search: //%s <words>, or point at an item or target something."):format(site))
      return
    end
    net.open_url(SITES[site] .. encode(words))
  end
end

commands.register("wiki", search("wiki"))
commands.register("ah", search("ah"))
