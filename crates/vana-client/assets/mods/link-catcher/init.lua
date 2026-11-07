-- Web links in chat get a number (the chat link add-ons): //links lists the last ones to open or copy, //links <n>
-- opens one.

local KEEP = 30
local WIN = "links"
local links = {}   -- {n, url}, newest last
local count = 0

local function catch(url)
  for _, l in ipairs(links) do
    if l.url == url then return l.n end
  end
  count = count + 1
  links[#links + 1] = { n = count, url = url }
  if #links > KEEP then table.remove(links, 1) end
  return count
end

filters.chat(function(line)
  if not settings.get("on") or not (line:find("https?://") or line:find("www%.")) then return nil end
  local out = line:gsub("(%f[%w]https?://[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]+)", function(url)
    return url .. " [" .. catch(url) .. "]"
  end)
  if out == line then
    out = line:gsub("(%f[%w]www%.[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]+)", function(url)
      return url .. " [" .. catch(url) .. "]"
    end)
  end
  return out ~= line and out or nil
end)

local function full(url)
  return url:find("^https?://") and url or ("https://" .. url)
end

local function rows()
  local out = {}
  for i = #links, 1, -1 do out[#out + 1] = ("[%d] %s"):format(links[i].n, links[i].url) end
  return out
end

local function show()
  if #links == 0 then
    chat.add("Link Catcher: no links yet.")
    return
  end
  ui.window(WIN, {
    title = "Links", width = 620,
    elements = {
      { type = "list", id = "list", rows = rows(), height = math.min(10, #links), at = 1 },
      { type = "buttons", id = "btn", items = { "Open", "Copy", "Close" } },
    },
  })
  ui.open(WIN)
end

ui.on(WIN, function(_, e)
  local function picked()
    local at = ui.get(WIN, "list").at or 1
    return links[#links + 1 - at]
  end
  if e.kind == "select" and e.id == "list" then
    local l = links[#links + 1 - e.index]
    if l then net.open_url(full(l.url)) end
  elseif e.kind == "press" and e.id == "btn" then
    local l = picked()
    if e.index == 1 and l then
      net.open_url(full(l.url))
    elseif e.index == 2 and l then
      client.copy(l.url)
      chat.add("Link Catcher: copied " .. l.url)
    else
      ui.close(WIN)
    end
  end
end)

commands.register("links", function(n)
  n = tonumber(n)
  if not n then
    show()
    return
  end
  for _, l in ipairs(links) do
    if l.n == n then
      net.open_url(full(l.url))
      return
    end
  end
  chat.add("Link Catcher: no link [" .. n .. "].")
end)
