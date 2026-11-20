--[=====[
[[SND Metadata]]
author: HeyKupo
version: 1.2.0
description: Farms Accursed Hoards in Heaven-on-High. https://github.com/HeyKupo/GetItDoneKupo/tree/main/HoH
plugin_dependencies:
- vnavmesh
dependencies:
- source: https://github.com/HeyKupo/GetItDoneKupo/blob/v1.2.0/HoH/hoh_hoard.lua
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
    default: true
    description: (Recommended) Use a Pomander of Safety on the way to the hoard. Removes traps so you don't lose time transformed.
  RecordSpots:
    default: false
    description: Keep a list of where hoards were found (hoh_hoard_spots.csv and hoh_hoard_finds.csv in SND's config folder), for searching without Intuition later.
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
-- Intuition result watcher. SND only hooks trigger functions written in the macro text itself,
-- so this one lives here and hands each chat message to hoh_hoard.lua.
HOH_SENSE = nil
HOH_DISCOVERED = false
function OnChatMessage()
    local msg = TriggerData and TriggerData.message
    if HoH_OnChat ~= nil then HoH_OnChat(msg) end
end

-- hoh_hoard.lua is downloaded by SND (see dependencies above) and defines HoH_Main.
-- ScriptPath, if set, loads a local copy instead.
local scriptPath = tostring(Config.Get("ScriptPath") or "")
if scriptPath ~= "" then
    assert(loadfile(scriptPath))()
end
assert(HoH_Main, "hoh_hoard.lua didn't load. Check SND's dependencies for this macro, or the ScriptPath setting.")
HoH_Main()
