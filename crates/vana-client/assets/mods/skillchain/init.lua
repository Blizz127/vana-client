-- The client's skillchain view (its party skills, our target's open resonance and LSB's properties) in the skillchain
-- helper's edge window: panel "skillchains" draws it, beside the Timers in the classic UI.
local function show()
  if settings.get("on") then
    ui.window("skillchains", { edge = true, panel = "skillchains", resize = true, title = "Skillchains" })
    ui.open("skillchains")
  else
    ui.close("skillchains")
  end
end

show()
events.on("settings_changed", show)
