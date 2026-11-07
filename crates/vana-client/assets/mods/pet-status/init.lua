-- Our pet in an edge window (the pet status add-ons): HP, MP, TP, its target, and the recasts of the pet commands and
-- the job abilities that work through it.

local PET_JAS = { "Blood Pact: Rage", "Blood Pact: Ward", "Ready", "Sic", "Reward", "Call Beast", "Deploy", "Retrieve",
  "Activate", "Repair", "Deus Ex Automata", "Spirit Link", "Steady Wing", "Full Circle", "Ecliptic Attrition",
  "Life Cycle", "Blaze of Glory" }

local function clock(s)
  s = math.ceil(s)
  return s >= 60 and ("%d:%02d"):format(s // 60, s % 60) or tostring(s)
end

-- Recast rows for the abilities that act through the pet, by recast id (several abilities share one).
local function recast_rows()
  local want = {}
  for _, n in ipairs(PET_JAS) do want[n:lower()] = true end
  local seen, out = {}, {}
  local r = game.recasts()
  for _, id in ipairs(game.abilities()) do
    local a = res.ability(id)
    if a and a.recast_id and (id >= 0x400 or want[(a.name or ""):lower()]) and not seen[a.recast_id] then
      seen[a.recast_id] = true
      local left = r.abilities[a.recast_id] or 0
      local total = r.totals.abilities[a.recast_id] or 0
      out[#out + 1] = { type = "gauge", style = "row", label = a.name,
        text = left > 0 and clock(left) or "Ready", value = left > 0 and total > 0 and 1 - left / total or 1,
        dim = left > 0 }
    end
  end
  table.sort(out, function(a, b) return a.label < b.label end)
  return out
end

local function tick()
  local pet = settings.get("on") and game.entity_by_tag("pet")
  if not pet then
    ui.close("pet")
    return
  end
  local rows = {
    { type = "gauge", style = "row", label = "HP", text = (pet.hpp or 0) .. "%", value = (pet.hpp or 0) / 100 },
  }
  if pet.mpp and pet.mpp > 0 then
    rows[#rows + 1] = { type = "gauge", style = "row", label = "MP", text = pet.mpp .. "%", value = pet.mpp / 100 }
  end
  if pet.tp then
    rows[#rows + 1] = { type = "gauge", style = "row", label = "TP", text = tostring(pet.tp), value = math.min(1, pet.tp / 3000) }
  end
  local foe = pet.pet_target and game.entity(pet.pet_target)
  if foe then
    rows[#rows + 1] = { type = "gauge", style = "row", label = "Fighting " .. foe.name, text = (foe.hpp or 0) .. "%",
      value = (foe.hpp or 0) / 100 }
  end
  for _, r in ipairs(recast_rows()) do rows[#rows + 1] = r end
  ui.window("pet", { edge = true, width = 280, title = "Pet", heading = pet.name, elements = rows })
  ui.open("pet")
end

timer.every(0.5, tick)
events.on("settings_changed", tick)
