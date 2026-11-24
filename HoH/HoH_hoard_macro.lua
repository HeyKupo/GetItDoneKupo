--[=====[
[[SND Metadata]]
author: HeyKupo
version: 1.3.0
description: Farms Accursed Hoards in Heaven-on-High. https://github.com/HeyKupo/GetItDoneKupo/tree/main/HoH
plugin_dependencies:
- vnavmesh
dependencies:
- source: https://github.com/HeyKupo/GetItDoneKupo/blob/v1.3.0/HoH/hoh_hoard.lua
configs:
  SaveSlot:
    default: 1
    description: Save file to use (1 or 2).
    min: 1
    max: 2
  Runs:
    default: 100
    description: Stop after this many runs (0 = until you stop it).
    min: 0
    max: 30000
  SixthSense:
    default: false
    description: Search without Intuition (Of the Sixth Sense).
  RecordSpots:
    default: false
    description: Leave off (only for improving spot data).
    section: Development
  ScriptPath:
    default: ""
    description: Leave empty (testing only).
    section: Development
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
