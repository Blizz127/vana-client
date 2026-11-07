-- Job counters (the job gauge add-ons). Charges as LandSandBoat counts them (abilities_charges: recast id, job, level,
-- charges, seconds a charge): a running recast is the time until every charge is back.

local CHARGES = {
  { name = "Stratagems", recast = 231, job = 20, by_level = { { 10, 1, 240 }, { 30, 2, 120 }, { 50, 3, 80 }, { 70, 4, 60 }, { 90, 5, 48 } } },
  { name = "Ready", recast = 102, job = 9, by_level = { { 25, 3, 30 } } },
  { name = "Quick Draw", recast = 195, job = 17, by_level = { { 40, 2, 60 } } },
}
local NIN, PUP = 13, 18
local SHADOWS = { [66] = 1, [444] = 2, [445] = 3, [446] = 4 }
local TOOLS = { { "Shihei", "Utsusemi" }, { "Inoshishinofuda", "elemental" }, { "Shikanofuda", "support" },
  { "Chonofuda", "enfeebling" } }
local ELEMENTS = { "Fire", "Ice", "Wind", "Earth", "Thunder", "Water", "Light", "Dark" }

local function level_of(job)
  local p = game.player()
  if not p then return 0 end
  if p.main_job == job then return p.main_level or 0 end
  if p.sub_job == job then return p.sub_level or 0 end
  return 0
end

local function row(label, text, value, dim)
  return { type = "gauge", style = "row", label = label, text = text, value = value, dim = dim }
end

local function rows()
  local out = {}
  local r = game.recasts()
  for _, c in ipairs(CHARGES) do
    local lv = level_of(c.job)
    local max, per
    for _, t in ipairs(c.by_level) do
      if lv >= t[1] then max, per = t[2], t[3] end
    end
    if max then
      local left = r.abilities[c.recast] or 0
      local have = math.max(0, max - math.ceil(left / per - 1e-6))
      local text = ("%d / %d"):format(have, max)
      if have < max then text = text .. ("  +1 in %ds"):format(math.ceil(left - (max - have - 1) * per)) end
      out[#out + 1] = row(c.name, text, have / max, have == 0)
    end
  end
  local buffs = {}
  for _, b in ipairs(game.buffs()) do buffs[b.id] = (buffs[b.id] or 0) + 1 end
  if level_of(NIN) > 0 then
    local n = 0
    for id, k in pairs(SHADOWS) do
      if buffs[id] then n = math.max(n, k) end
    end
    out[#out + 1] = row("Shadows", n >= 4 and "4+" or tostring(n), math.min(1, n / 3), n == 0)
    for _, t in ipairs(TOOLS) do
      local count = 0
      for _, it in ipairs(game.find_items(t[1])) do count = count + it.count end
      if count > 0 or t[1] == "Shihei" then
        out[#out + 1] = row(t[1], tostring(count), math.min(1, count / 99), count == 0)
      end
    end
  end
  if level_of(PUP) > 0 then
    for k, el in ipairs(ELEMENTS) do
      local n = buffs[299 + k]
      if n then out[#out + 1] = row(el .. " Maneuver", tostring(n), n / 3) end
    end
  end
  return out
end

timer.every(0.5, function()
  local els = settings.get("on") and rows() or {}
  if #els == 0 then
    ui.close("gauges")
    return
  end
  ui.window("gauges", { edge = true, width = 280, title = "Job", heading = "Job Gauges", elements = els })
  ui.open("gauges")
end)
