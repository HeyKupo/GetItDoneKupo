--[=====[
[[SND Metadata]]
author: HeyKupo
version: 1.4.0
description: Farms Accursed Hoards in Heaven-on-High. https://github.com/HeyKupo/GetItDoneKupo/tree/main/HoH
plugin_dependencies:
- vnavmesh
dependencies:
- source: https://github.com/HeyKupo/GetItDoneKupo/blob/v1.4.0/HoH/hoh_hoard.lua
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
  ForTheHoard:
    default: 0
    description: "(I 1, II 100, III 1,000, IV 5,000, V 10,000, VI 20,000, VII 30,000)"
    section: Achievement Progress
  TroubleWithBuried:
    default: 0
    description: "(I 1, II 100)"
    section: Achievement Progress
  StopOnAchievement:
    default: true
    description: Stop when the mode's last achievement is earned (For the Hoard VII, or The Trouble with Buried II in Sixth Sense).
    section: Achievement Progress
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

-- Session report. SND runs OnStop however the macro ends.
function OnStop()
    if HoH_OnStop ~= nil then HoH_OnStop() end
end

-- hoh_hoard.lua is downloaded by SND (see dependencies above) and defines HoH_Main.
-- ScriptPath, if set, loads a local copy instead.
local scriptPath = tostring(Config.Get("ScriptPath") or "")
if scriptPath ~= "" then
    assert(loadfile(scriptPath))()
end
assert(HoH_Main, "hoh_hoard.lua didn't load. Check SND's dependencies for this macro, or the ScriptPath setting.")
HoH_Main()
