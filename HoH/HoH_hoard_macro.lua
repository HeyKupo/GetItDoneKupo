--[=====[
[[SND Metadata]]
author: HeyKupo
version: 1.0.0
description: Farms Accursed Hoards in Heaven-on-High. https://github.com/HeyKupo/GetItDoneKupo/tree/main/HoH
plugin_dependencies:
- vnavmesh
dependencies:
- source: https://github.com/HeyKupo/GetItDoneKupo/blob/v1.0.0/HoH/hoh_hoard.lua
configs:
  ScriptPath:
    default: ""
    description: Leave empty. Only for testing a local copy of hoh_hoard.lua (full path); normally SND downloads it.
  SaveSlot:
    default: 1
    description: Which save file to enter with (1 or 2). Deep dungeon saves are tied to the job that made them.
    min: 1
    max: 2
  Runs:
    default: 30000
    description: How many times to enter
    min: 1
    max: 30000
  Protection:
    description: What to use before running to the hoard
    is_choice: true
    default: "Inferno magicite"
    choices:
      - "Inferno magicite"
      - "Crag magicite"
      - "Vortex magicite"
      - "Pomander of Concealment"
      - "Pomander of Petrification"
      - "None"
  Safety:
    default: false
    description: Use a Pomander of Safety (removes traps) on the way to the hoard
  Dash:
    description: Forward dash to use on the way to the hoard (only fires if your current job has it)
    is_choice: true
    default: "Auto (by job)"
    choices:
      - "Auto (by job)"
      - "Smudge (PCT)"
      - "Aetherial Shift (WHM)"
      - "Hell's Ingress (RPR)"
      - "En Avant (DNC)"
      - "None"
[[End Metadata]]
--]=====]
-- Intuition result watcher. SND only hooks trigger functions whose names appear in the macro
-- text itself, so it lives here; hoh_hoard.lua reads HOH_SENSE.
HOH_SENSE = nil
function OnChatMessage()
    local msg = TriggerData and TriggerData.message
    if type(msg) ~= "string" then return end
    if string.find(msg, "You do not sense the call of the Accursed Hoard", 1, true) then
        HOH_SENSE = "no"
    elseif string.find(msg, "You sense the Accursed Hoard calling you", 1, true) then
        HOH_SENSE = "yes"
    end
end

-- hoh_hoard.lua is downloaded by SND (see dependencies above) and defines HoH_Main.
-- ScriptPath, if set, loads a local copy instead.
local scriptPath = tostring(Config.Get("ScriptPath") or "")
if scriptPath ~= "" then
    assert(loadfile(scriptPath))()
end
assert(HoH_Main, "hoh_hoard.lua didn't load. Check SND's dependencies for this macro, or the ScriptPath setting.")
HoH_Main()
