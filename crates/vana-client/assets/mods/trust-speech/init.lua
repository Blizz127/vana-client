-- A trust's party line is battle message 711 (LandSandBoat's trustPartyMessage), in s2c 0x029 or 0x02D (the message
-- id at 0x18 in both). Hidden, those packets are dropped before the client reads them; shown, nothing is hooked.
local hooks = {}

local function drop_speech(p)
  if #p.data >= 0x1a and string.unpack("<I2", p.data, 0x18 + 1) == 711 then
    return false
  end
end

local function apply()
  for _, h in ipairs(hooks) do
    packets.off(h)
  end
  hooks = {}
  if settings.get("hide") then
    hooks = { packets.on_in(0x029, drop_speech), packets.on_in(0x02D, drop_speech) }
  end
end

events.on("settings_changed", apply)
apply()
