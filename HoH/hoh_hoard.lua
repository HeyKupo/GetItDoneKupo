--[=====[
[[SND Metadata]]
author: HeyKupo
version: 1.2.0
description: HoH hoard farm, loaded by the HoH_hoard macro (which SND downloads it for as a dependency). Enter on a save, use Intuition, take the hoard if it's on the floor, leave, repeat. Leaving doesn't change the save.
[[End Metadata]]
--]=====]

-- SND loads this file as a dependency before the macro runs, and that step can't pause
-- (no /wait or yield), so everything lives inside HoH_Main(); the macro calls it.
function HoH_Main()

-- Logging: essentials at Info; details at Debug (set Dalamud's log level to Debug in /xllog to see them).
local function LogI(msg) Dalamud.Log("[HoH] " .. msg) end
local function LogD(msg) Dalamud.LogDebug("[HoH] " .. msg) end

-- Intuition's result comes as a chat message. Its text is taken from the game's message table
-- (LogMessage 7272 = hoard, 7273 = no hoard) in the client's language. Parts of a message that
-- the game fills in at runtime come out as gaps, so match on the longest fixed piece.
local function FixedPiece(text)
    if text == nil then return nil end
    local best = ""
    for raw in string.gmatch(text .. "  ", "(.-)%s%s+") do
        local piece = raw:gsub("^%s+", ""):gsub("%s+$", "")
        if #piece > #best then best = piece end
    end
    return #best >= 6 and best or nil
end
local function LogMessageText(id)
    local ok, v = pcall(function() return Excel.GetRow("LogMessage", id):GetProperty("Text") end)
    return ok and v ~= nil and tostring(v) or nil
end
local SENSE_YES = FixedPiece(LogMessageText(7272)) or "You sense the Accursed Hoard calling you"
local SENSE_NO  = FixedPiece(LogMessageText(7273)) or "You do not sense the call of the Accursed Hoard"
local DISCOVERED = FixedPiece(LogMessageText(7274)) or "You discover a piece of the Accursed Hoard"
-- The last hoard achievements: the script stops when the "... earns the achievement ..." chat
-- line for its mode's one comes (it's shown only once, so a restart just keeps going).
-- Sixth Sense: The Trouble with Buried II (1666, title Of the Sixth Sense). Normal: For the
-- Hoard VII (3816, 30,000 hoards). Names from the game data, in the client's language.
local function AchievementName(id, fallback)
    local ok, v = pcall(function() return Excel.GetRow("Achievement", id):GetProperty("Name") end)
    return ok and v ~= nil and tostring(v) ~= "" and tostring(v) or fallback
end
local GOAL_ACHIEVEMENT = { sixth = AchievementName(1666, "The Trouble with Buried II"),
                           normal = AchievementName(3816, "For the Hoard VII") }
LogD(string.format("Matching chat: hoard = \"%s\", no hoard = \"%s\", discovered = \"%s\", achievements = \"%s\", \"%s\"",
    SENSE_YES, SENSE_NO, DISCOVERED, GOAL_ACHIEVEMENT.normal, GOAL_ACHIEVEMENT.sixth))
HOH_DISCOVERED = false
HOH_EARNED = {}   -- "sixth" / "normal" = true once its achievement's chat line has come
-- Check: For the Hoard IV (1664, 5,000 hoards): its chat
-- line is logged (no stop) to confirm SND passes achievement lines on. Remove once seen.
local TEST_ACHIEVEMENT = AchievementName(1664, "For the Hoard IV")

-- Called by the macro's OnChatMessage (SND only hooks trigger functions written in the macro).
function HoH_OnChat(msg)
    if type(msg) ~= "string" then return end
    if string.find(msg, SENSE_NO, 1, true) then HOH_SENSE = "no"
    elseif string.find(msg, SENSE_YES, 1, true) then HOH_SENSE = "yes"
    elseif string.find(msg, DISCOVERED, 1, true) then HOH_DISCOVERED = true end
    if string.find(msg, TEST_ACHIEVEMENT, 1, true) then LogI("TEST achievement chat line seen: " .. msg) end
    for mode, name in pairs(GOAL_ACHIEVEMENT) do
        if string.find(msg, name, 1, true) then HOH_EARNED[mode] = true end
    end
end

-- ============================================================
-- Config
-- ============================================================
local ENTRY_NPC_ID     = 1025846       -- Kyusei, the HoH entrance NPC; start the script standing next to them

-- Everything is looked up by ID, and text comes from the game's own data (which is in the
-- client's language), so the script works on any client language.
local function GameText(sheet, id, field)
    local ok, v = pcall(function()
        local row = Excel.GetRow(sheet, id)
        return row ~= nil and row:GetProperty(field) or nil
    end)
    if ok and v ~= nil then
        local t = tostring(v)
        if t ~= "" then return t end
    end
    return nil
end
local function ActionName(id, fallback) return GameText("Action", id, "Name") or fallback end
local SPRINT_NAME = ActionName(3, "Sprint")
local SPRINT_STATUS = 50

-- true/false: do we have this status effect? nil if it can't be checked.
local function HasStatus(id)
    local found = false
    local ok = pcall(function()
        for st in luanet.each(Svc.Objects.LocalPlayer.StatusList) do
            if st ~= nil and st.StatusId == id then found = true; break end
        end
    end)
    collectgarbage("collect")
    collectgarbage("collect")
    if not ok then return nil end
    return found
end

-- Names of our current status effects (for the Debug log).
local function StatusNames()
    local ids = {}
    pcall(function()
        for st in luanet.each(Svc.Objects.LocalPlayer.StatusList) do
            if st ~= nil and st.StatusId ~= 0 then table.insert(ids, st.StatusId) end
        end
    end)
    collectgarbage("collect")
    collectgarbage("collect")
    local names = {}
    for _, id in ipairs(ids) do table.insert(names, (GameText("Status", id, "Name") or "?") .. " (" .. id .. ")") end
    return #names > 0 and table.concat(names, ", ") or "none"
end

local function IsDead()
    local dead = false
    pcall(function()
        local lp = Svc.Objects.LocalPlayer
        dead = lp ~= nil and (lp.IsDead or lp.CurrentHp == 0)
    end)
    collectgarbage("collect")
    collectgarbage("collect")
    return dead
end
-- Settings come from the HoH_hoard macro's metadata block (editable in SND's macro settings).
-- The numbers here are only fallbacks if a setting isn't declared there.
local function CfgInt(name, fallback)
    local ok, v = pcall(function() return Config.GetInt(name, fallback) end)
    return ok and v or fallback
end
local function CfgBool(name, fallback)
    local ok, v = pcall(function() return Config.GetBool(name, fallback) end)
    if ok and v ~= nil then return v end
    return fallback
end

local MAX_RUNS         = CfgInt("Runs", 100)     -- stop after this many entries (both modes); 0 = no limit
if MAX_RUNS <= 0 then MAX_RUNS = math.huge end
local SAVE_SLOT        = CfgInt("SaveSlot", 1)   -- 1 = first save file, 2 = second
if SAVE_SLOT ~= 2 then SAVE_SLOT = 1 end

-- Object IDs, taken from BossModReborn's deep dungeon module (AutoClear.cs)
local HOARD_MARKER_ID  = 0x1EA1F6      -- "BandedCofferIndicator": the spot Intuition reveals
local HOARD_COFFER_ID  = 0x1EA1F7      -- "BandedCoffer": the hoard once you're standing on it
local POMANDER_LOCK_SECONDS = 2.5      -- wait this long after Intuition before the next pomander/magicite
local EXPLORE_SECONDS = 90              -- when the hoard is sensed but not loaded, explore this long before giving up
local MARKER_AFTER_SENSE_SECONDS = 3   -- after the game says "hoard", wait this long for the marker
local HOARD_DETECT_SECONDS = 5         -- after Intuition, look for the hoard marker this long (usually 0.5-2s; occasionally later)
local HOARD_RETRY_SECONDS = 30         -- wait this long on the spot for the hoard to be discovered (e.g. waiting out an otter trap)
-- The hoard counts toward the achievements as soon as it's discovered (the coffer appears and
-- the game says "You discover a piece of the Accursed Hoard!"). Opening it is pointless here:
-- hoard loot is only awarded for clearing the floor set's boss, and we always leave.
local DISCOVER_CHAT_WAIT = 3           -- after the coffer appears, wait up to this long for the "discover" chat line

-- ============================================================
-- Steps that still need confirming in game (see notes in chat)
-- Each one stops the script with a message until it's filled in.
-- ============================================================
-- Callback commands for the two deep dungeon windows (both tested by hand).
local MENU_ENTER_CMD = "/callback DeepDungeonMenu true 0"       -- option 1 "Enter Heaven-on-High"
-- DeepDungeonSaveData: "true 0" = first save file (tested); "true 1" = second (assumed).
-- In Enter mode any click on a slot enters with it.
local SAVE_SLOT_CMD  = "/callback DeepDungeonSaveData true " .. (SAVE_SLOT - 1)

local function AddonReady(name)
    local a = Addons.GetAddon(name)
    return a ~= nil and a.Ready
end

local function WaitAddon(name, timeoutSec)
    local t = 0
    while not AddonReady(name) do
        yield("/wait 0.5"); t = t + 0.5
        if t >= timeoutSec then error("Timed out waiting for " .. name) end
    end
end

local function EnterWithSave(slot)
    if MENU_ENTER_CMD == nil or SAVE_SLOT_CMD == nil then
        error("Deep dungeon menu callbacks not filled in yet")
    end

    -- Find Kyusei by ID, then use the name the game shows for her.
    local npcName = nil
    for obj in luanet.each(Svc.Objects) do
        if obj ~= nil and obj.BaseId == ENTRY_NPC_ID then npcName = obj.Name.TextValue; break end
    end
    collectgarbage("collect")
    collectgarbage("collect")
    local npc = npcName and Entity.GetEntityByName(npcName) or nil
    if npc == nil then error("Kyusei (Heaven-on-High entrance) not found nearby. Start next to her.") end
    npc:SetAsTarget()
    npc:Interact()

    WaitAddon("DeepDungeonMenu", 10)
    yield(MENU_ENTER_CMD)

    WaitAddon("DeepDungeonSaveData", 10)
    yield(SAVE_SLOT_CMD)

    WaitAddon("ContentsFinderConfirm", 60)
    yield("/click ContentsFinderConfirm Commence")
end

-- DeepDungeonStatus callbacks: code 11 = use pomander, second value = pomander ID
-- (DeepDungeonItem row). All four confirmed in game.
local POM = { safety = 1, sight = 2, steel = 4, intuition = 14, concealment = 18, petrification = 19 }   -- sight, steel: assumed (DeepDungeonItem order; the log shows steel's name)

local function PomCmd(id) return "/callback DeepDungeonStatus true 11 " .. id end

-- Deep dungeon state from SND (15.15+, InstancedContent.DeepDungeon): real pomander/magicite
-- counts, and using them by slot without the status window. Older SND isn't supported.
if not pcall(function() return InstancedContent.DeepDungeon.IsActive end) then
    error("HoH hoard needs SomethingNeedDoing 15.15 or newer (InstancedContent.DeepDungeon): please update SND")
end
local DDX = {}
-- How many of a pomander (by pomander id) we have; 0 outside a deep dungeon.
function DDX.PomCount(id)
    if id == nil then return 0 end
    return InstancedContent.DeepDungeon:GetPomanderCount(id)
end
-- How many magicite in a slot (0-2).
function DDX.MagCount(slot) return InstancedContent.DeepDungeon.Magicite[slot] end
-- Use a pomander or magicite given as a status-window command ("... true 11 <pomander id>" or
-- "... true 12 <magicite slot>"). Returns false without pressing anything if there's none.
-- (The game ignores a use during an animation lock, so callers still check that it took.)
function DDX.Use(cmd)
    local kind, n = string.match(cmd or "", "DeepDungeonStatus true (1[12]) (%d+)")
    if kind == nil then error("DDX.Use: not a pomander/magicite command: " .. tostring(cmd)) end
    n = tonumber(n)
    local dd = InstancedContent.DeepDungeon
    if kind == "12" then
        if dd.Magicite[n] == 0 then return false end
        dd:UseMagicite(n)
        return true
    end
    for p in luanet.each(dd.Pomanders) do
        if p.ItemId == n then
            if p.Count == 0 then return false end
            dd:UsePomander(p.Slot)
            return true
        end
    end
    return false
end

local function UseIntuition()
    DDX.Use(PomCmd(POM.intuition))
end

local function CfgString(name, fallback)
    local ok, v = pcall(function() return Config.Get(name, fallback) end)
    if ok and type(v) == "string" and v ~= "" then return v end
    return fallback
end

-- Protection is automatic: Concealment if the save has one, magicite kept for when
-- something attacks, Steel after that. (Logged as the floor's "protection".)
local PROTECTION_CHOICE = "Auto"
local USE_SAFETY        = true   -- always (no setting); skipped if the save has none

-- Pomander of Safety (ID 1): removes the floor's traps. Only used on floors with a hoard.
-- Used while running to the hoard (pomanders work on the move), so no wait afterwards.
local SAFETY_USED = false   -- reset at the start of each run; Safety once per floor
local STEALTH = false       -- true after Concealment: no abilities (dashes) or pomanders; Sprint is fine
local PENDING_CONCEAL = nil -- Concealment command to use on the move, right after dash + Sprint
local function UseSafety()
    if not USE_SAFETY or SAFETY_USED or STEALTH or DDX.PomCount(POM.safety) == 0 then return end
    SAFETY_USED = true
    LogD("Safety")
    DDX.Use(PomCmd(POM.safety))
end

-- Protection, then Safety, both before we start moving. Concealment is the exception: it's
-- cancelled by abilities and other pomanders (not Sprint), so it's only queued here and used
-- on the move after any dashes (see SpeedUp).
local function SafetyNow()
    if USE_SAFETY and not SAFETY_USED and not STEALTH and DDX.PomCount(POM.safety) > 0 then
        UseSafety()
        yield("/wait 2.5")   -- pomander animation lock
    end
end

local function UseProtection()
    if DDX.PomCount(POM.concealment) > 0 then PENDING_CONCEAL = PomCmd(POM.concealment) end
    SafetyNow()
end

-- ============================================================
-- Helpers
-- ============================================================
-- The floor is ready once SND says we're in a deep dungeon and in a room (no status window needed).
function DDX.FloorReady()
    local ok, r = pcall(function()
        local dd = InstancedContent.DeepDungeon
        return dd.IsActive and dd.CurrentRoomIndex >= 0
    end)
    return ok and r
end
-- Tileset: layout type 1 = A, 2 = B, 5 = hall of fallacies.
function DDX.Tileset(t) return ({ [1] = "A", [2] = "B", [5] = "hall" })[t] or "?" end

-- With RecordSpots on (development): on every wait, note the room we're in; log each floor's
-- start room and every room change with where it happened, to refine HOH11's hallway points
-- (halls["a>b"] = median switch point per direction). hoh_roomchanges.csv.
DDX.record = false   -- set from the RecordSpots setting below
DDX.ROOMLOG = Svc.PluginInterface.ConfigDirectory.FullName .. "\\hoh_roomchanges.csv"
DDX.w = { floor = nil, room = -1 }
pcall(function() DDX.Env = luanet.import_type("System.Environment") end)
function DDX.WatchRoom()
    if not DDX.record then return end
    pcall(function()
        local dd = InstancedContent.DeepDungeon
        local w = DDX.w
        if not dd.IsActive then w.floor = nil; w.room = -1; return end
        local room = dd.CurrentRoomIndex
        if room < 0 then return end
        local p = Entity.Player.Position
        local x, y, z, t = p.X, p.Y, p.Z, DDX.Env.TickCount64 / 1000
        local kind = nil
        if w.floor == nil then
            w.floor = string.format("%d,%d,%s", dd.DeepDungeonId, dd.Floor, DDX.Tileset(dd.LayoutInitializationType))
            kind = "start"
        elseif room ~= w.room then
            local dt = t - w.t
            local speed = math.sqrt((x - w.x) ^ 2 + (z - w.z) ^ 2) / math.max(dt, 0.05)
            kind = speed < 15 and "change" or "teleport"   -- sprint is ~8y/s; Return/Passage jump
        end
        if kind ~= nil then
            local old = io.open(DDX.ROOMLOG, "r")
            local new = old == nil
            if old ~= nil then old:close() end
            local f = io.open(DDX.ROOMLOG, "a")
            if f ~= nil then
                if new then f:write("time,kind,dungeon,floor,tileset,from,to,x,y,z,prev_x,prev_z,dt\n") end
                f:write(string.format("%s,%s,%s,%d,%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f\n", os.date("!%Y-%m-%dT%H:%M:%SZ"), kind,
                    w.floor, kind == "start" and -1 or w.room, room, x, y, z, w.x or x, w.z or z, w.t and (t - w.t) or 0))
                f:close()
            end
        end
        w.room, w.x, w.z, w.t = room, x, z, t
    end)
end
local function Wait(sec) DDX.WatchRoom(); yield("/wait " .. sec) end

local function WaitUntil(pred, timeoutSec, label)
    local t = 0
    while not pred() do
        Wait(0.5); t = t + 0.5
        if timeoutSec and t >= timeoutSec then
            error("Timed out waiting for " .. (label or "condition"))
        end
    end
end

-- Returns { Position, Name } for the first object on the floor with this BaseId (DataId), or nil.
-- Only plain values are kept: holding Dalamud game objects in Lua crashes the game when the
-- macro's Lua state is cleaned up off the main thread, so references are collected here,
-- while still on the main thread.
local function FindObject(baseId)
    local found = nil
    for obj in luanet.each(Svc.Objects) do
        if obj ~= nil and obj.BaseId == baseId then
            found = { Position = obj.Position, Name = obj.Name.TextValue, Targetable = obj.IsTargetable }
            break
        end
    end
    collectgarbage("collect")
    collectgarbage("collect")
    return found
end

-- Diagnostic: log every event object (BaseId >= 2,000,000) with its ID, name and distance.
-- Plain-value list of event objects (BaseId >= 2,000,000): { {Id, Name, Position, Dist}, ... }
local function ListEventObjects()
    local me = Entity.Player.Position
    local list = {}
    for obj in luanet.each(Svc.Objects) do
        if obj ~= nil and obj.BaseId ~= nil and obj.BaseId >= 2000000 then
            local p = obj.Position
            local dx, dz = p.X - me.X, p.Z - me.Z
            table.insert(list, { Id = obj.BaseId, Name = obj.Name.TextValue,
                                 Position = p, Dist = math.sqrt(dx * dx + dz * dz) })
        end
    end
    collectgarbage("collect")
    collectgarbage("collect")
    return list
end

local function DumpNearbyObjects()
    local list = ListEventObjects()
    LogD("Event objects loaded (" .. #list .. "):")
    for _, o in ipairs(list) do
        LogD(string.format(" 0x%X %s  %.0fy", o.Id, o.Name, o.Dist))
    end
end

local function InDeepDungeon() return Player.IsInDuty end

-- Leave like the game's own Leave Duty does. SND's InstancedContent.LeaveCurrentContent() calls
-- the game function with forced=true, which shows up as "expelled from the duty due to extended
-- inactivity"; call it with forced=false instead, and fall back to SND's if that isn't possible.
local EventFramework = nil
pcall(function()
    luanet.load_assembly("FFXIVClientStructs")
    EventFramework = luanet.import_type("FFXIVClientStructs.FFXIV.Client.Game.Event.EventFramework")
end)


local InCombatNow = nil          -- set once InCombat is defined (further down)
local RESULT_WAIT_SECONDS = 30   -- after dying, wait this long for the results screen
local LEAVE_CHECK_SECONDS = 5    -- how long to wait for the normal leave before falling back

local function WaitForResults()
    -- Dying ends the run: the game shows the results screen, then we can leave as usual.
    LogD("Dead: waiting for the results screen")
    local t = 0
    while Player.IsInDuty and not AddonReady("DeepDungeonResult") and t < RESULT_WAIT_SECONDS do
        Wait(0.5); t = t + 0.5
    end
    LogD(string.format("Results screen %s after %.1fs", AddonReady("DeepDungeonResult") and "shown" or "not seen", t))
    Wait(1)
end

-- Returns true if we died at any point while leaving.
local function LeaveDuty()
    local died = false
    for attempt = 1, 2 do
        if IsDead() then died = true; WaitForResults() end
        if not Player.IsInDuty or not InstancedContent.CanLeaveCurrentContent() then break end
        -- The normal leave doesn't work in combat. Rather than SND's forced leave ("expelled for
        -- inactivity"), wait for the fight to end one way or the other (better to die
        -- and leave normally), then leave normally.
        if not IsDead() and InCombatNow ~= nil and InCombatNow() then
            LogI("In combat: waiting for it to end (or to die) before leaving normally")
            local tw = 0
            local limit = HOH_DEATH_WAIT or 90
            while InCombatNow() and not IsDead() and Player.IsInDuty and tw < limit do Wait(0.5); tw = tw + 0.5 end
            LogD(string.format("Combat wait over after %.0fs (%s)", tw, IsDead() and "died" or InCombatNow() and "still in combat" or "combat ended"))
            if IsDead() then died = true; WaitForResults() end
            if not Player.IsInDuty then break end
            if not IsDead() and InCombatNow() then
                -- Still alive and fighting: a slow mob can take ages, so SND's forced leave.
                LogI(string.format("Still in combat after %.0fs: using SND's (forced) leave", tw))
                InstancedContent.LeaveCurrentContent()
                break
            end
        end
        local sent = EventFramework ~= nil and pcall(function() EventFramework.LeaveCurrentContent(false) end)
        if sent then
            -- Wait for the leave to go through; stop early if we die meanwhile (then the
            -- results screen comes first). If we were already dead, just wait.
            local deadAtSend = IsDead()
            local t = 0
            while Player.IsInDuty and (deadAtSend or not IsDead()) and t < LEAVE_CHECK_SECONDS do Wait(0.25); t = t + 0.25 end
            if not Player.IsInDuty then break end
            if IsDead() and not deadAtSend and attempt == 1 then
                died = true
                LogD("Died while leaving; trying again after the results screen")
            else
                LogI("WARNING: normal leave didn't work" .. (IsDead() and " (dead)" or "") .. ", using SND's (forced) leave this time")
                InstancedContent.LeaveCurrentContent()
                break
            end
        else
            InstancedContent.LeaveCurrentContent()
            break
        end
    end
    WaitUntil(function() return not Player.IsInDuty and Player.Available end, 60, "leaving duty")
    return died
end

local function DistanceTo(pos)
    local p = Entity.Player.Position
    local dx, dy, dz = pos.X - p.X, pos.Y - p.Y, pos.Z - p.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Forward dashes that need no target (they go the way you're facing, i.e. along the path).
-- From BossModReborn's action data. HoH caps you at level 70, so En Avant has at most 2 charges.
local DASHES = {
    ["Smudge (PCT)"]          = { action = "Smudge",          id = 34684, job = 42, range = 15, recast = 20, uses = 1 },
    ["Aetherial Shift (WHM)"] = { action = "Aetherial Shift", id = 37008, job = 24, range = 15, recast = 60, uses = 1 },
    ["Hell's Ingress (RPR)"]  = { action = "Hell's Ingress",  id = 24401, job = 39, range = 15, recast = 20, uses = 1 },
    ["En Avant (DNC)"]        = { action = "En Avant",        id = 16010, job = 38, range = 10, recast = nil, uses = 2 },  -- 2 charges at HoH levels
}

-- Ask the game whether an action can be used right now (0 = ready). Returns nil if the check
-- isn't available, in which case we fall back to our own recast tracking.
local function ActionReady(id)
    local ok, status = pcall(function() return Actions.GetActionStatus(ActionType.Action, id) end)
    if not ok or status == nil then return nil end
    return status == 0, status
end
for _, d in pairs(DASHES) do d.action = ActionName(d.id, d.action) end   -- client-language name for /ac

local ENEMY_DASH_RADIUS = 20   -- with Concealment, skip dashes if a living enemy is this close
local DASH_MARGIN = 2   -- only dash if the destination is at least range + this far, so we don't overshoot

local DASH_CHOICE = "Auto (by job)"   -- the current job's dash (no setting)

local function CurrentDash()
    if DASH_CHOICE == "None" then return nil end
    local jobId = Player.Job ~= nil and Player.Job.Id or nil
    if DASH_CHOICE == "Auto (by job)" then
        for _, d in pairs(DASHES) do
            if d.job == jobId then return d end
        end
        return nil
    end
    local d = DASHES[DASH_CHOICE]
    if d ~= nil and d.job ~= jobId then return nil end   -- picked a dash this job doesn't have
    return d
end

local function Now()
    local ok, v = pcall(function() return os.time() end)
    return ok and v or nil
end

-- Last use per dash (os.time(), or true if no clock is available) so we skip it while on
-- recast instead of waiting out an animation lock for nothing.
local lastDash = {}

local function DashReady(d)
    if d.recast == nil then return true end
    local last = lastDash[d.action]
    if last == nil then return true end
    local now = Now()
    if now == nil or last == true then return false end
    return now - last >= d.recast
end

-- Dash (if the job has one and the destination is far enough), then Sprint. Call once movement
-- has started so the dash goes along the path. Uses the game's own /ac command.
-- Vector3 constructor (for vnavmesh calls). nil if it can't be loaded; then the landing check is skipped.
local V3 = nil
pcall(function()
    pcall(function() luanet.load_assembly("System.Numerics.Vectors") end)
    V3 = luanet.import_type("System.Numerics.Vector3")
end)

-- Player position (plain numbers) and facing direction (unit vector in XZ). Dashes go this way.
local function PosAndFacing()
    local p = Entity.Player.Position
    local x, y, z = p.X, p.Y, p.Z
    local ok, rot = pcall(function() return Svc.Objects.LocalPlayer.Rotation end)
    collectgarbage("collect")
    collectgarbage("collect")
    if not ok or rot == nil then return x, y, z, nil, nil end
    return x, y, z, math.sin(rot), math.cos(rot)
end

-- Living enemies: count within radius of (cx, cz), plus distance to the nearest one from there.
local function EnemiesNear(cx, cz, radius)
    local n, nearest = 0, nil
    local ok = pcall(function()
        for obj in luanet.each(Svc.Objects) do
            if obj ~= nil and string.find(tostring(obj.ObjectKind), "BattleNpc", 1, true)
               and obj.SubKind == 5 and not obj.IsDead and obj.IsTargetable then
                local p = obj.Position
                local dx, dz = p.X - cx, p.Z - cz
                local dist = math.sqrt(dx * dx + dz * dz)
                if dist <= radius then n = n + 1 end
                if nearest == nil or dist < nearest then nearest = dist end
            end
        end
    end)
    collectgarbage("collect")
    collectgarbage("collect")
    if not ok then return 0, nil end
    return n, nearest
end

-- Patrols: enemy kinds that walk the floor and its hallways instead of staying put (floor 11:
-- base 8896 moved ~110y per floor in 70 sightings, the others ~16y; the Heavenly
-- Namazu). One counts as a threat if it's within DDX.PATROL_NEAR, or within DDX.PATROL_RADIUS
-- and walking toward us (from where it was at the last check, so a dash toward it doesn't count).
DDX.PATROL = { [8896] = true }
-- Measured on floor 11 (hoh_aggro_probe): every enemy kind ignores you under Concealment,
-- even at 1y. Without it: Namazu ~10y in front (2y behind is fine), Korpokkur ~11y, Shizuku
-- (sprite) ~10y from any side, Shiomushi ~5y. Concealment takes ~1.5s to go on.
DDX.PATROL_NEAR, DDX.PATROL_RADIUS, DDX.PATROL_COMING = 20, 40, 1.0   -- yalms, yalms, yalms/s toward us
DDX.seen = {}   -- patrol id -> { x, z, t } at the last check
-- Any living enemy within `radius` of (cx, cz), or a patrol that's a threat (above)? Returns
-- true/false and a short description of the reason. comingOnly: only a patrol walking toward us.
function DDX.ThreatNear(cx, cz, radius, comingOnly)
    local hit = nil
    local now = (DDX.Env ~= nil and DDX.Env.TickCount64 or 0) / 1000
    pcall(function()
        for obj in luanet.each(Svc.Objects) do
            if obj ~= nil and string.find(tostring(obj.ObjectKind), "BattleNpc", 1, true)
               and obj.SubKind == 5 and not obj.IsDead and obj.IsTargetable then
                local p = obj.Position
                local dist = math.sqrt((p.X - cx) ^ 2 + (p.Z - cz) ^ 2)
                if dist <= radius then hit = string.format("enemy %.0fy", dist); break end
                if DDX.PATROL[obj.BaseId] then
                    local name = tostring(obj.Name and obj.Name.TextValue or obj.BaseId)
                    local id = tostring(obj.GameObjectId)
                    local last = DDX.seen[id]
                    -- keep the older sighting until it's 0.3s old, so checks close together still see movement
                    if last == nil or now - last.t >= 0.3 then DDX.seen[id] = { x = p.X, z = p.Z, t = now } end
                    if dist <= DDX.PATROL_NEAR and not comingOnly then hit = string.format("patrol %s %.0fy", name, dist); break end
                    if dist <= DDX.PATROL_RADIUS and last ~= nil and now - last.t >= 0.3 and now - last.t <= 5 and dist > 0 then
                        -- its own movement since the last check, along the line toward us
                        local toward = ((p.X - last.x) * (cx - p.X) + (p.Z - last.z) * (cz - p.Z)) / dist / (now - last.t)
                        if toward >= DDX.PATROL_COMING then
                            hit = string.format("patrol %s %.0fy, coming at %.1fy/s", name, dist, toward); break
                        end
                    end
                end
            end
        end
    end)
    collectgarbage("collect")
    collectgarbage("collect")
    return hit ~= nil, hit
end

-- Would an enemy notice us at a spot, without Concealment? [base] = { range in its sight cone,
-- range outside it, half-width of the cone in degrees }. Measured on floor 11 (probe):
-- the three sight kinds alike: ~10.5y within ~45 degrees of where they face (aggro at 9.1-10.9y
-- inside 40 degrees; 43-49 degrees is the edge), and outside that only at touching distance
-- (1.0y straight behind a stationary Korpokkur, 1.6y beside a Shiomushi). The sprite (Shizuku)
-- notices at ~10y from any side. The cone gets 10 extra degrees: enemies turn while idle.
DDX.NOTICE = {
    [8896] = { 10.5, 1.5, 55 },   -- Heavenly Namazu (patrol): sight
    [8886] = { 10.5, 1.5, 55 },   -- Heavenly Korpokkur: sight
    [8888] = { 10.5, 1.5, 55 },   -- Heavenly Shiomushi: sight
    [8887] = { 10.5, 10.5, 180 }, -- Heavenly Shizuku (sprite): proximity, any side
}
DDX.NOTICE_OTHER = { 11.0, 11.0, 180 }  -- any kind not measured: all round
DDX.NOTICE_MARGIN = 2                   -- yalms added to every range
-- (Used for the dash and Concealment-renewal checks. Walking detours around enemies were tried
-- and dropped: vnavmesh's real path strays too far from straight lines near walls.)
-- Living enemies now, as plain values: { {x, z, fx, fz, base, name}, ... }
function DDX.Enemies()
    local list = {}
    pcall(function()
        for obj in luanet.each(Svc.Objects) do
            if obj ~= nil and string.find(tostring(obj.ObjectKind), "BattleNpc", 1, true)
               and obj.SubKind == 5 and not obj.IsDead and obj.IsTargetable then
                local rot = obj.Rotation or 0
                table.insert(list, { x = obj.Position.X, z = obj.Position.Z, fx = math.sin(rot), fz = math.cos(rot),
                    base = obj.BaseId, name = tostring(obj.Name and obj.Name.TextValue or obj.BaseId) })
            end
        end
    end)
    collectgarbage("collect")
    collectgarbage("collect")
    return list
end
-- The first enemy in `list` that would notice us at (x, z), or nil.
function DDX.NoticedAt(list, x, z, margin)
    margin = margin or DDX.NOTICE_MARGIN
    for _, e in ipairs(list) do
        local dx, dz = x - e.x, z - e.z
        local d = math.sqrt(dx * dx + dz * dz)
        if d <= 13 + margin then
            local n = DDX.NOTICE[e.base] or DDX.NOTICE_OTHER
            local ang = d < 0.01 and 0 or math.deg(math.acos(math.max(-1, math.min(1, (e.fx * dx + e.fz * dz) / d))))
            local r = (ang <= n[3] and n[1] or n[2]) + margin
            if d <= r then return e, d end
        end
    end
    return nil
end
-- The first enemy that would notice us somewhere on the straight line from a to b (every 2y).
function DDX.NoticedOnLine(list, ax, az, bx, bz, margin)
    local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
    local steps = math.max(1, math.ceil(len / 2))
    for i = 0, steps do
        local f = i / steps
        local e, d = DDX.NoticedAt(list, ax + (bx - ax) * f, az + (bz - az) * f, margin)
        if e ~= nil then return e, d end
    end
    return nil
end
-- Would a dash of `range` yalms from here land on walkable ground (not inside a wall)?
-- Returns true/false, or nil if it can't tell (then we dash anyway, as before).
local function LandingOnMesh(range)
    if V3 == nil then return nil end
    local x, y, z, fx, fz = PosAndFacing()
    if fx == nil then return nil end
    local lx, lz = x + fx * range, z + fz * range
    local ok, pt = pcall(function() return IPC.vnavmesh.NearestPoint(V3(lx, y, lz), 1.5, 3) end)
    if not ok then return nil end
    if pt == nil then return false end
    local dx, dz = pt.X - lx, pt.Z - lz
    return dx * dx + dz * dz <= 1.5 * 1.5
end

-- Concealment (if chosen) goes on the move, after any dashes (they'd cancel it) and before
-- Sprint (which doesn't), so the pomander animation doesn't eat into Sprint. `hoard` is where
-- we're headed, if it's the hoard. Safety normally went before moving (UseProtection); it's
-- only used here if that somehow didn't happen.
local CONCEAL_MIN_DIST = 10   -- don't bother with Concealment if this close to the hoard
local POM_ANIM_SECONDS = 1.5  -- most of the pomander animation lock (~2.1s); Sprint is retried after it

local function PomOnTheMove(hoard)
    if PENDING_CONCEAL ~= nil and hoard ~= nil and DistanceTo(hoard) < CONCEAL_MIN_DIST then
        LogD(string.format("Concealment skipped: %.0fy left", DistanceTo(hoard)))
        PENDING_CONCEAL = nil
    elseif PENDING_CONCEAL ~= nil then
        LogD("Protection: Pomander of Concealment (on the move)")
        DDX.Use(PENDING_CONCEAL)
        PENDING_CONCEAL = nil
        STEALTH = true
        Wait(POM_ANIM_SECONDS)
        return true
    elseif USE_SAFETY and not SAFETY_USED and not STEALTH and DDX.PomCount(POM.safety) > 0 then
        UseSafety()
        Wait(POM_ANIM_SECONDS)
        return true
    end
    return false
end

-- Ask vnavmesh for a fresh path from where we are now. vnavmesh walks straight lines between
-- the waypoints it planned, so after a dash (which goes the way we face, not along the path)
-- the next straight line can run into a wall or a pillar. A new path from the landing spot
-- avoids that.
local function Repath(target, why)
    LogD("New path: " .. why)
    IPC.vnavmesh.PathfindAndMoveTo(target, false)
    local t = 0
    while IPC.vnavmesh.PathfindInProgress() and t < 10 do Wait(0.1); t = t + 0.1 end
end

-- Step aside before planning a new path: a fresh path from the same spot is usually the same
-- path, straight back into whatever we're caught on (seen 51 repaths into one snag).
-- Walks to a navmesh point a few yalms to the side of and behind the way to the target,
-- alternating sides, then repaths. Returns the seconds spent.
local NUDGE_SIDE, NUDGE_BACK = 4, 2
local function Nudge(target, n)
    local spent = 0
    if V3 ~= nil then
        local p = Entity.Player.Position
        local dx, dz = target.X - p.X, target.Z - p.Z
        local len = math.sqrt(dx * dx + dz * dz)
        if len > 0.1 then
            dx, dz = dx / len, dz / len
            local side = (n % 2 == 1) and 1 or -1
            local x = p.X - dz * side * NUDGE_SIDE - dx * NUDGE_BACK
            local z = p.Z + dx * side * NUDGE_SIDE - dz * NUDGE_BACK
            local ok, pt = pcall(function() return IPC.vnavmesh.NearestPoint(V3(x, p.Y, z), 3, 5) end)
            if ok and pt ~= nil then
                LogD(string.format("Stuck (%d): stepping aside to %.0f,%.0f", n, pt.X, pt.Z))
                IPC.vnavmesh.PathfindAndMoveTo(pt, false)
                while IPC.vnavmesh.PathfindInProgress() and spent < 3 do Wait(0.1); spent = spent + 0.1 end
                while IPC.vnavmesh.IsRunning() and spent < 2.5 do Wait(0.25); spent = spent + 0.25 end
            end
        end
    end
    Repath(target, "stuck")
    return spent
end

-- Watches for being stuck on something while vnavmesh thinks we're moving: if we've moved
-- less than half a yalm in 1.5s, step aside and plan a new path. Call the returned function
-- every `dt` seconds; it returns how many times in a row we've been stuck in the same place
-- (within STUCK_SAME_DIST of the last stuck), and the seconds spent stepping aside.
local STUCK_SAME_DIST = 4
local function StuckWatcher(target)
    local lastX, lastZ, still = nil, nil, 0
    local count, sx, sz = 0, nil, nil
    return function(dt)
        local p = Entity.Player.Position
        if lastX ~= nil and (p.X - lastX) ^ 2 + (p.Z - lastZ) ^ 2 < 0.25 then
            still = still + dt
        else
            still = 0
        end
        lastX, lastZ = p.X, p.Z
        local spent = 0
        if still >= 1.5 and IPC.vnavmesh.IsRunning() then
            if sx ~= nil and (p.X - sx) ^ 2 + (p.Z - sz) ^ 2 < STUCK_SAME_DIST ^ 2 then
                count = count + 1
            else
                count = 1
            end
            sx, sz = p.X, p.Z
            spent = Nudge(target, count)
            still = 0
            lastX = nil
        end
        return count, spent
    end
end

-- On the way: dash (if the job has one, it's ready, the destination is far enough, and it won't
-- land in a wall), any extra dash charges, the on-the-move pomander, then Sprint.
-- Call once movement has started.
local function SpeedUp(target, hoard)
    -- Concealment coming and a threat close (a patrol on its way, or any enemy within
    -- ENEMY_DASH_RADIUS): put it on now, before (more) dashing (a Namazu nearly
    -- caught one; a dash toward it closes in fast). Checked again before each dash.
    local function ConcealIfThreat()
        -- Sixth Sense holds its first Concealment itself: it hands over a check to run here too,
        -- so that one also goes on before any dash or Sprint.
        if PENDING_CONCEAL == nil then return DDX.concealHook ~= nil and DDX.concealHook() or false end
        local p = Entity.Player.Position
        local near, why = DDX.ThreatNear(p.X, p.Z, ENEMY_DASH_RADIUS)
        if not near then return false end
        LogD("Concealment first: " .. why)
        PomOnTheMove(hoard)
        return true
    end
    ConcealIfThreat()
    local d = CurrentDash()
    if STEALTH and d ~= nil then
        LogD("Concealed: no dash")
        d = nil
    end

    -- With Concealment coming, don't dash near enemies (around us or where we'd land).
    local function SafeToDash()
        -- No Concealment coming (a magicite-only save, normal mode): dash regardless. A fight just
        -- means the magicite goes off at the hoard while the coffer is due anyway.
        if PENDING_CONCEAL == nil and not HOH_DASH_CHECK then return true end
        -- Would anything notice us over the dash and the ~1.5s of running after it, before
        -- Concealment is on? (Measured ranges and facing, DDX.NOTICE: an enemy facing away
        -- doesn't count; it used to be any enemy within 20y.)
        local x, y, z, fx, fz = PosAndFacing()
        if fx == nil then return EnemiesNear(x, z, ENEMY_DASH_RADIUS) == 0 end
        local reach = d.range + 12
        local e, dist = DDX.NoticedOnLine(DDX.Enemies(), x, z, x + fx * reach, z + fz * reach)
        if e ~= nil then
            LogD(string.format("%s skipped: %s would notice (%.0fy from the line)", d.action, e.name, dist))
            return false
        end
        LogD("Enemy check: clear")
        return true
    end

    -- Returns "dashed", "wait" (not ready / would hit a wall, try again shortly), or "stop".
    local function TryDash(isFirst)
        if DistanceTo(target) < d.range + DASH_MARGIN then return "stop" end
        local ready, status = ActionReady(d.id)
        if ready == nil then ready = (not isFirst) or DashReady(d) end   -- no game check: old behaviour
        if not ready then return "wait", "not ready (status " .. tostring(status) .. ")" end
        if LandingOnMesh(d.range) == false then return "wait", "would land in a wall" end
        if ConcealIfThreat() then return "stop" end
        if not SafeToDash() then return "stop" end
        LogD(string.format("%s (%.0fy away)", d.action, DistanceTo(target)))
        yield('/ac "' .. d.action .. '"')
        lastDash[d.action] = Now() or true
        Wait(0.9)   -- dash animation lock (~0.8s); the next action is ignored if sent during it
        Repath(target, "after " .. d.action)
        Wait(0.2)   -- let the character turn onto the new path before anything else uses facing
        return "dashed"
    end

    -- Keep trying one dash for up to `window` seconds (moving along the path meanwhile).
    local function DashWithin(isFirst, window)
        local t, why = 0, nil
        while true do
            local r, reason = TryDash(isFirst)
            if r ~= "wait" then return r end
            why = reason
            if t >= window then
                LogD(string.format("%s skipped: %s", d.action, why))
                return "stop"
            end
            Wait(0.25); t = t + 0.25
        end
    end

    if d ~= nil and DashWithin(true, 1.0) == "dashed" then
        -- Extra charges (En Avant): short lockout between charges, and the path may turn, so
        -- keep trying for a bit.
        for i = 2, d.uses do
            if DashWithin(false, 2.5) ~= "dashed" then break end
        end
    end

    -- Last check before Sprint: something close now (after the dashes)? Concealment first, so
    -- Sprint's animation lock doesn't swallow it (an ignored press, then caught).
    ConcealIfThreat()
    local usedPom = PomOnTheMove(hoard)

    -- Sprint, retried until it's on (the end of a pomander animation can swallow it).
    local t = 0
    while true do
        local on = HasStatus(SPRINT_STATUS)
        if on then
            if t > 0 then LogD(string.format("Sprint on after %.1fs", t)) end
            break
        end
        -- Not on and not usable: on cooldown (only trust this when no pomander animation is
        -- in the way, since that also makes it unusable for a moment).
        if not usedPom and t == 0 and ActionReady(3) == false then
            LogD("Sprint on cooldown")
            break
        end
        LogD("Sprint")
        yield('/ac "' .. SPRINT_NAME .. '"')
        if on == nil or t >= 4 then break end   -- can't check, or Sprint is on cooldown
        Wait(0.3); t = t + 0.3
    end
end

-- Coffer timing (Debug log): how long after reaching the hoard spot the coffer appears, and how
-- far from the spot we are when it does. Measured over ~390 hoards: 1.7-3.0s, always within 0.25y.
local ON_SPOT_DIST = 1.0   -- within this many yalms (flat distance) counts as standing on the spot
local Environment = nil
pcall(function() Environment = luanet.import_type("System.Environment") end)
local function Ms()
    local ok, v = pcall(function() return Environment.TickCount64 end)
    return ok and v or nil
end

local hoardTimer = nil   -- {Pos, Start, OnSpot, Done}

local function TimerStart(pos)
    hoardTimer = { Pos = { X = pos.X, Z = pos.Z }, Start = Ms(), OnSpot = nil, Done = false }
end

-- Call often while heading to and standing on the spot.
local function TimerTick()
    local h = hoardTimer
    if h == nil or h.Done or h.Start == nil then return end
    local now = Ms()
    local p = Entity.Player.Position
    local d = math.sqrt((p.X - h.Pos.X) ^ 2 + (p.Z - h.Pos.Z) ^ 2)
    if h.OnSpot == nil and d <= ON_SPOT_DIST then h.OnSpot = now end
    if FindObject(HOARD_COFFER_ID) ~= nil then
        h.Done = true
        local wait = h.OnSpot and (now - h.OnSpot) / 1000 or nil
        LogD(string.format("Coffer appeared %s, %.1fy from the spot",
            wait and string.format("%.2fs after reaching the spot", wait) or "before reaching the spot", d))
    end
end

-- `hoard` (optional): the hoard's position when `pos` is somewhere else (radius test), for the
-- Concealment distance check. `onTick` (optional) is called every 0.25s while moving.
local function MoveTo(pos, hoard, onTick)
    IPC.vnavmesh.PathfindAndMoveTo(pos, false)
    -- wait for the path to be computed and movement to begin, so we're facing along the path
    WaitUntil(function() return not IPC.vnavmesh.PathfindInProgress() end, 30, "pathfinding to hoard")
    Wait(0.4)
    SpeedUp(pos, hoard or pos)
    local stuck = StuckWatcher(pos)
    local t = 0
    while IPC.vnavmesh.IsRunning() and not IsDead() do
        Wait(0.25); t = t + 0.25
        local _, spent = stuck(0.25)
        t = t + spent
        TimerTick()
        if onTick ~= nil then onTick() end
        if t >= 120 then error("Timed out waiting for moving to hoard") end
    end
end

-- The game says there's a hoard but its marker isn't loaded (objects load room by room around
-- you), so walk around until it shows up. Targets, in order:
--   1. the farthest loaded event object (coffer, beacon) we haven't been near; these mark rooms.
--   2. once those run out, the nearest spot on the navmesh that's far from everywhere we've
--      walked, i.e. the closest part of the floor we haven't seen yet.
-- Returns the marker, or nil if it never showed up.
local EXPLORE_GRID_STEP = 15     -- spacing of candidate spots on the navmesh
local EXPLORE_GRID_RADIUS = 165  -- how far from the start to look for candidate spots
local EXPLORE_SEEN_DIST = 30     -- a spot within this distance of our trail counts as seen
local EXPLORE_MAX_STUCKS = 2     -- stuck this many times in one place: give up on that target

local function Explore()
    local trail = {}     -- where we've been, as {X, Z}, at least 5y apart
    local function AddTrail()
        local p = Entity.Player.Position
        local last = trail[#trail]
        if last == nil or (p.X - last.X) ^ 2 + (p.Z - last.Z) ^ 2 > 25 then
            table.insert(trail, { X = p.X, Z = p.Z })
        end
    end
    local function NearTrail(x, z, dist)
        for _, v in ipairs(trail) do
            if (x - v.X) ^ 2 + (z - v.Z) ^ 2 < dist * dist then return true end
        end
        return false
    end

    -- Spots on the floor's navmesh around the start, built the first time we need them.
    local spots = nil
    local function MeshSpots()
        if spots ~= nil then return spots end
        spots = {}
        if V3 == nil then return spots end
        local p = Entity.Player.Position
        local x0, y0, z0 = p.X, p.Y, p.Z
        for dx = -EXPLORE_GRID_RADIUS, EXPLORE_GRID_RADIUS, EXPLORE_GRID_STEP do
            for dz = -EXPLORE_GRID_RADIUS, EXPLORE_GRID_RADIUS, EXPLORE_GRID_STEP do
                local x, z = x0 + dx, z0 + dz
                local ok, pt = pcall(function() return IPC.vnavmesh.NearestPoint(V3(x, y0, z), 3, 10) end)
                if ok and pt ~= nil then
                    table.insert(spots, { X = pt.X, Y = pt.Y, Z = pt.Z, Tried = false })
                end
            end
        end
        LogD(string.format("Explore: %d navmesh spots to choose from", #spots))
        return spots
    end

    local function NextTarget()
        local me = Entity.Player.Position
        -- 1. Farthest event object we haven't been near.
        local best = nil
        for _, o in ipairs(ListEventObjects()) do
            if o.Dist > 8 and not NearTrail(o.Position.X, o.Position.Z, 8) and (best == nil or o.Dist > best.Dist) then
                best = o
            end
        end
        if best ~= nil then return best.Position, best.Name, best.Dist end
        -- 2. Nearest navmesh spot we haven't seen.
        local spot, spotDist = nil, nil
        for _, sp in ipairs(MeshSpots()) do
            if not sp.Tried and not NearTrail(sp.X, sp.Z, EXPLORE_SEEN_DIST) then
                local d = math.sqrt((sp.X - me.X) ^ 2 + (sp.Z - me.Z) ^ 2)
                if spot == nil or d < spotDist then spot, spotDist = sp, d end
            end
        end
        if spot ~= nil then
            spot.Tried = true
            return V3(spot.X, spot.Y, spot.Z), "unexplored area", spotDist
        end
        return nil
    end

    -- First, room by room in order of where hoards have been found on this layout (spot data);
    -- then, if it still hasn't shown up, the general search below.
    if HOH_EXPLORE_ROOMS ~= nil then
        local ok, err = pcall(HOH_EXPLORE_ROOMS, function() return FindObject(HOARD_MARKER_ID) ~= nil end)
        if not ok then LogD("Explore by spots: " .. tostring(err)) end
        local m = FindObject(HOARD_MARKER_ID)
        if m ~= nil or IsDead() then return m end
    end

    local t = 0
    local legs = 0
    local first = true
    AddTrail()
    while t < EXPLORE_SECONDS do
        local marker = FindObject(HOARD_MARKER_ID)
        if marker ~= nil then return marker end

        local target, name, dist = NextTarget()
        if target == nil then
            LogD("Explore: nothing left to walk to")
            return nil
        end

        legs = legs + 1
        LogD(string.format("Explore leg %d: %s at %.0fy", legs, name, dist))
        IPC.vnavmesh.PathfindAndMoveTo(target, false)
        WaitUntil(function() return not IPC.vnavmesh.PathfindInProgress() end, 30, "pathfinding (explore)")
        if first and IPC.vnavmesh.IsRunning() then
            first = false
            Wait(0.4)
            SpeedUp(target, nil)
        end

        local stuck = StuckWatcher(target)
        local skipped = false
        while IPC.vnavmesh.IsRunning() and t < EXPLORE_SECONDS do
            Wait(0.5); t = t + 0.5
            if IsDead() then IPC.vnavmesh.Stop(); return nil end
            local stucks, spent = stuck(0.5)
            t = t + spent
            if stucks >= EXPLORE_MAX_STUCKS then
                LogD(string.format("Explore: stuck %d times in one place, skipping %s", stucks, name))
                IPC.vnavmesh.Stop()
                skipped = true
                break
            end
            AddTrail()
            marker = FindObject(HOARD_MARKER_ID)
            if marker ~= nil then
                IPC.vnavmesh.Stop()
                return marker
            end
        end
        -- Count the target itself as visited, even if there was no path to it. A skipped navmesh
        -- spot is already marked Tried; leave its surroundings unseen so nearby spots can still
        -- be tried by another route.
        if not (skipped and name == "unexplored area") then
            table.insert(trail, { X = target.X, Z = target.Z })
        end
        t = t + 0.5
    end
    IPC.vnavmesh.Stop()
    LogD(string.format("Explore: gave up after %.0fs", t))
    return nil
end

-- ============================================================
-- Hoard spot file: every hoard position Intuition reveals is kept in hoh_hoard_spots.csv in
-- SND's config folder, one line per spot with how many times a hoard was found there
-- (setting "RecordSpots"). Works for any deep dungeon floor set: spots are keyed by territory.
-- It's the list of places a hoard can be, for searching without Intuition.
-- Format: territory,x,y,z,finds   (x/y/z = average of the finds at that spot)
-- ============================================================
local SPOTS_FILE = Svc.PluginInterface.ConfigDirectory.FullName .. "\\hoh_hoard_spots.csv"
-- Finds closer than this are the same spot. Kept small: Palantir's data has distinct spots under
-- 1y apart, and the Intuition marker seems to sit at a fixed point, so a repeat find should land
-- (almost) exactly on the saved position. Each find logs how far it was from the nearest saved
-- spot, to check that.
local SPOT_SAME_DIST = 0.5
local RECORD_SPOTS = CfgBool("RecordSpots", false)
DDX.record = RECORD_SPOTS   -- room-change log too (see DDX.WatchRoom)

local function Territory()
    local ok, t = pcall(function() return Svc.ClientState.TerritoryType end)
    return ok and t or 0
end

local function AddFindTo(spots, terr, x, y, z, n, present)
    present = present or 0
    for _, sp in ipairs(spots) do
        if sp.T == terr and (sp.X - x) ^ 2 + (sp.Z - z) ^ 2 < SPOT_SAME_DIST ^ 2 then
            local total = sp.N + n
            if total > 0 then
                sp.X = sp.X + (x - sp.X) * n / total
                sp.Y = sp.Y + (y - sp.Y) * n / total
                sp.Z = sp.Z + (z - sp.Z) * n / total
            end
            sp.N = total
            sp.P = sp.P + present
            return
        end
    end
    table.insert(spots, { T = terr, X = x, Y = y, Z = z, N = n, P = present })
end

-- Safe file swaps. Each save writes NAME.tmp, keeps the previous file as NAME.bak, then renames
-- the new one in. Reading takes the first of NAME / NAME.bak / NAME.tmp whose first line
-- matches `pattern` (its header): after a power cut or a Windows crash, a file written just before can come back
-- empty or full of zeros (seen the run tally came back empty and counting restarted at 0).
local function OpenValid(path, pattern)
    for _, p in ipairs({ path, path .. ".bak", path .. ".tmp" }) do
        local f = io.open(p, "r")
        if f ~= nil then
            local first = f:read("l")
            if first ~= nil and first:find(pattern) then
                f:seek("set", 0)
                if p ~= path then LogI("WARNING: " .. path .. " was missing or damaged; reading " .. p) end
                return f
            end
            f:close()
        end
    end
    return nil
end

local function SwapIn(path, write)
    local tmp = path .. ".tmp"
    local f = io.open(tmp, "w")
    if f == nil then return false end
    write(f)
    f:flush()
    f:close()
    os.remove(path .. ".bak")
    os.rename(path, path .. ".bak")
    if os.rename(tmp, path) then return true end
    os.rename(path .. ".bak", path)   -- put the old one back
    return false
end

-- Reads the spot file: list of {T, X, Y, Z, N, P}. Also reads the older one-line-per-find format
-- (time,territory,x,y,z,startX,startZ) and folds it into spots.
local oldFinds = {}   -- old-format lines seen while loading (copied into the raw finds log once)

local function LoadSpots()
    local spots = {}
    oldFinds = {}
    local f = OpenValid(SPOTS_FILE, "^territory,")
    -- (the old one-line-per-find format had no header)
    if f == nil then f = OpenValid(SPOTS_FILE, "^%d%d%d%d%-") end
    if f == nil then return spots end
    local presenceOk = true
    for line in f:lines() do
        if line:find("^territory,") then presenceOk = line:find(",in_area") ~= nil end
        local t, x, y, z, n, pr = line:match("^(%d+),([%-%d%.]+),([%-%d%.]+),([%-%d%.]+),(%d+),?(%d*)%s*$")
        if t ~= nil then
            AddFindTo(spots, tonumber(t), tonumber(x), tonumber(y), tonumber(z), tonumber(n), presenceOk and tonumber(pr) or 0)
        else
            t, x, y, z = line:match("^%d%d%d%d%-[^,]*,(%d+),([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)")
            if t ~= nil then
                AddFindTo(spots, tonumber(t), tonumber(x), tonumber(y), tonumber(z), 1)
                table.insert(oldFinds, line:match("^([^,]*,[^,]*,[^,]*,[^,]*,[^,]*)"))
            end
        end
    end
    f:close()
    return spots
end

-- Writes to a temporary file first, then swaps it in (see SwapIn).
local function SaveSpots(spots)
    table.sort(spots, function(a, b)
        if a.T ~= b.T then return a.T < b.T end
        if a.X ~= b.X then return a.X < b.X end
        return a.Z < b.Z
    end)
    return SwapIn(SPOTS_FILE, function(f)
        f:write("territory,x,y,z,finds,in_area\n")
        for _, sp in ipairs(spots) do
            f:write(string.format("%d,%.2f,%.2f,%.2f,%d,%d\n", sp.T, sp.X, sp.Y, sp.Z, sp.N, sp.P or 0))
        end
    end)
end

-- Per territory: finds, different spots, and the Good-Turing chance that the next find is at a
-- spot not seen yet (spots found only once / all finds).
-- Raw log too, one line per find (time,territory,x,y,z), so spots can be re-grouped later with a
-- different same-spot distance once we know how much a spot's position varies between finds.
local FINDS_FILE = Svc.PluginInterface.ConfigDirectory.FullName .. "\\hoh_hoard_finds.csv"

-- Per territory, from the raw finds log in order: how many finds since the last one at a spot not
-- seen before. A long run (~3x the number of spots, e.g. ~800 on floor 11) means the list is
-- very likely complete.
local function FindsSinceNewSpot()
    local seen, since = {}, {}
    local f = io.open(FINDS_FILE, "r")
    if f == nil then return since end
    for line in f:lines() do
        local t, x, z = line:match("^[^,]*,(%d+),([%-%d%.]+),[%-%d%.]+,([%-%d%.]+)")
        if t ~= nil then
            t, x, z = tonumber(t), tonumber(x), tonumber(z)
            local list = seen[t] or {}
            seen[t] = list
            local known = false
            for _, p in ipairs(list) do
                if (p[1] - x) ^ 2 + (p[2] - z) ^ 2 < SPOT_SAME_DIST ^ 2 then known = true; break end
            end
            if known then
                since[t] = (since[t] or 0) + 1
            else
                table.insert(list, { x, z })
                since[t] = 0
            end
        end
    end
    f:close()
    return since
end

local function LogSpotStats(prefix)
    local spots = LoadSpots()
    if #spots == 0 then LogI(prefix .. "no hoard spots recorded yet"); return end
    local by = {}
    for _, sp in ipairs(spots) do
        local s = by[sp.T] or { finds = 0, spots = 0, once = 0 }
        s.finds = s.finds + sp.N; s.spots = s.spots + 1
        if sp.N == 1 then s.once = s.once + 1 end
        by[sp.T] = s
    end
    local since = FindsSinceNewSpot()
    for terr, s in pairs(by) do
        LogI(string.format("%sterritory %d: %d hoard finds at %d different spots; chance the next one is a new spot: %.0f%%; %s finds since the last new spot",
            prefix, terr, s.finds, s.spots, 100 * s.once / s.finds, since[terr] and tostring(since[terr]) or "?"))
    end
end

-- Floor layout (SND's InstancedContent.DeepDungeon). The game has the whole layout from the moment
-- a floor loads, no Sight needed: a 5x5 grid of rooms (index = row * 5 + col, row 0 = north),
-- each a set of flags, 0 = no room; bits 1/2/4/8 = exits north/south/west/east. Plus the tileset
-- (A/B; on HoH floors 11-19, A = the west area, B = the east one) and our room.
-- Normal runs log it with each find (finds log "rooms" column: "tileset:myroom:f0;f1;...;f24").
local FLOOR_LOG = true

-- {dungeon, floor, tileset, me, rooms = {25 numbers}}, or nil (not in a deep dungeon).
local function FloorLayout()
    local out = nil
    pcall(function()
        local dd = InstancedContent.DeepDungeon
        if not dd.IsActive then return end
        local o = { rooms = {}, dungeon = dd.DeepDungeonId, floor = dd.Floor, me = dd.CurrentRoomIndex,
            tileset = DDX.Tileset(dd.LayoutInitializationType) }
        for r in luanet.each(dd.Rooms) do table.insert(o.rooms, r.Flags) end
        if #o.rooms == 25 then out = o end
    end)
    collectgarbage("collect")
    collectgarbage("collect")
    return out
end
local floorStart = nil   -- {X, Z} where we stood when the floor loaded
local floorRooms = nil   -- this floor's layout as "tileset:myroom:f0;...;f24" (normal runs, hoard floors)

-- Every normal floor: one line in hoh_hoard_layouts.csv (time,territory,hoard,tileset,myroom,rooms),
-- so room frequencies can be counted over all floors, hoard or not.
local LAYOUTS_FILE = Svc.PluginInterface.ConfigDirectory.FullName .. "\\hoh_hoard_layouts.csv"
local function LogFloorLayout(hoard)
    floorRooms = nil
    if not FLOOR_LOG then return end
    local fl = FloorLayout()
    if fl == nil then LogD("Floor layout: not in a deep dungeon?"); return end
    floorRooms = string.format("%s:%d:%s", fl.tileset or "?", fl.me or -1, table.concat(fl.rooms, ";"))
    local lf = io.open(LAYOUTS_FILE, "a")
    if lf ~= nil then
        lf:write(string.format("%s,%d,%s,%s,%d,%s\n", os.date("!%Y-%m-%dT%H:%M:%SZ"), Svc.ClientState.TerritoryType,
            hoard and "1" or "0", fl.tileset or "?", fl.me or -1, table.concat(fl.rooms, ";")))
        lf:close()
    end
    local n = 0
    for _, r in ipairs(fl.rooms) do if r > 0 then n = n + 1 end end
    LogD(string.format("Floor layout: %d rooms, tileset %s, we're in room %d: %s", n, fl.tileset or "?", fl.me or -1, floorRooms))
end

local function RecordSpot(pos)
    if not RECORD_SPOTS then return end
    local terr = Territory()
    local spots = LoadSpots()
    -- First time: carry over finds already recorded in the old one-line-per-find spot file.
    local existing = io.open(FINDS_FILE, "r")
    if existing ~= nil then existing:close() end
    local raw = io.open(FINDS_FILE, "a")
    if raw ~= nil then
        if existing == nil then
            for _, l in ipairs(oldFinds) do raw:write(l .. "\n") end
        end
        -- time,territory,x,y,z[,start_x,start_z,rooms]  (rooms: "tileset:startroom:f0;...;f24")
        local extra = ""
        if floorStart ~= nil then
            extra = string.format(",%.1f,%.1f,%s", floorStart.X, floorStart.Z, floorRooms or "")
        end
        raw:write(string.format("%s,%d,%.3f,%.3f,%.3f%s\n", os.date("!%Y-%m-%dT%H:%M:%SZ"), terr, pos.X, pos.Y, pos.Z, extra))
        raw:close()
    else
        LogI("WARNING: couldn't write " .. FINDS_FILE .. " (open in another program?)")
    end
    local near, nearN = nil, 0
    for _, sp in ipairs(spots) do
        if sp.T == terr then
            local d = math.sqrt((sp.X - pos.X) ^ 2 + (sp.Z - pos.Z) ^ 2)
            if near == nil or d < near then near, nearN = d, sp.N end
        end
    end
    if near ~= nil and near < SPOT_SAME_DIST then
        LogD(string.format("Hoard spot seen before (find #%d there, %.2fy from the saved position)", nearN + 1, near))
    else
        LogD(string.format("New hoard spot%s", near and string.format(" (nearest known spot %.2fy away)", near) or ""))
    end
    AddFindTo(spots, terr, pos.X, pos.Y, pos.Z, 1)
    if not SaveSpots(spots) then
        LogI("WARNING: couldn't save the hoard spot to " .. SPOTS_FILE .. " (open in another program?)")
    end
end


-- ============================================================
-- Run tally: hoh_hoard_runs.csv in SND's config folder keeps running totals per territory, so
-- the hoard rate covers every run, not just what's still in dalamud.log.
-- Format: territory,runs,hoard_floors,taken,missed,not_found,deaths
-- (hoard floor = Intuition said there was a hoard, whether or not it was taken)
-- ============================================================
local TALLY_FILE = Svc.PluginInterface.ConfigDirectory.FullName .. "\\hoh_hoard_runs.csv"
local TALLY_FIELDS = { "runs", "hoard_floors", "taken", "missed", "not_found", "deaths" }

-- What this session last saved, per territory: if the file ever reads back lower than this
-- (damaged, or swapped out from under us), keep counting from here instead of from the file.
local tallyMem = {}

local function LoadTally()
    local tally = {}
    local f = OpenValid(TALLY_FILE, "^territory,")
    if f ~= nil then
        for line in f:lines() do
            local nums = {}
            for v in line:gmatch("[^,]+") do table.insert(nums, tonumber(v)) end
            if #nums == 7 and nums[1] ~= nil then
                local t = {}
                for i, k in ipairs(TALLY_FIELDS) do t[k] = nums[i + 1] or 0 end
                tally[nums[1]] = t
            end
        end
        f:close()
    end
    for terr, m in pairs(tallyMem) do
        if tally[terr] == nil or (tally[terr].runs or 0) < m.runs then
            LogI(string.format("WARNING: run tally file reads %s runs for %d, but this session saved %d; keeping %d",
                tally[terr] and tostring(tally[terr].runs) or "no", terr, m.runs, m.runs))
            local t = {}
            for _, k in ipairs(TALLY_FIELDS) do t[k] = m[k] end
            tally[terr] = t
        end
    end
    return tally
end

local function SaveTally(tally)
    local ok = SwapIn(TALLY_FILE, function(f)
        f:write("territory," .. table.concat(TALLY_FIELDS, ",") .. "\n")
        for terr, t in pairs(tally) do
            local vals = {}
            for _, k in ipairs(TALLY_FIELDS) do table.insert(vals, tostring(t[k] or 0)) end
            f:write(terr .. "," .. table.concat(vals, ",") .. "\n")
        end
    end)
    for terr, t in pairs(tally) do
        local m = {}
        for _, k in ipairs(TALLY_FIELDS) do m[k] = t[k] or 0 end
        tallyMem[terr] = m
    end
    return ok
end

local function CountRun(terr, result, died)
    local tally = LoadTally()
    local t = tally[terr] or {}
    for _, k in ipairs(TALLY_FIELDS) do t[k] = t[k] or 0 end
    t.runs = t.runs + 1
    if result ~= "none" then t.hoard_floors = t.hoard_floors + 1 end
    if result == "taken" then t.taken = t.taken + 1 end
    if result == "missed" then t.missed = t.missed + 1 end
    if result == "unseen" then t.not_found = t.not_found + 1 end
    if died then t.deaths = t.deaths + 1 end
    tally[terr] = t
    if not SaveTally(tally) then
        LogI("WARNING: couldn't save the run tally to " .. TALLY_FILE .. " (open in another program?)")
    end
end

-- A death during the leave, after the run was already counted.
local function CountDeath(terr)
    local tally = LoadTally()
    local t = tally[terr]
    if t == nil then return end
    t.deaths = (t.deaths or 0) + 1
    if not SaveTally(tally) then
        LogI("WARNING: couldn't save the run tally to " .. TALLY_FILE .. " (open in another program?)")
    end
end

local function LogTally(prefix)
    for terr, t in pairs(LoadTally()) do
        if t.runs > 0 then
            local p = t.hoard_floors / t.runs
            LogI(string.format("%s%s: %d runs, hoard on %d floors (%.1f%% \u{00B1} %.1f), %d taken, %d missed, %d not found, %d deaths",
                prefix, terr >= 100000 and string.format("territory %d (Sixth Sense)", terr - 100000) or ("territory " .. terr),
                t.runs, t.hoard_floors, 100 * p, 196 * math.sqrt(p * (1 - p) / t.runs),
                t.taken, t.missed, t.not_found, t.deaths))
        end
    end
end

-- ============================================================
-- Radius test (data collection, temporary): how close do you have to be for the hoard to be
-- discovered? Each session runs a search on hoard floors: stop 1y short of the spot (on the side
-- we're coming from), then 1.5, 2, ... until the coffer doesn't appear, then halve the gap
-- between the farthest stop that worked and the nearest that didn't, until they're within
-- RADIUS_PRECISION. Then RADIUS_CONFIRM checks just inside and just outside, and the test stops
-- for the session. Bounds use the distance we actually stopped at, not the one we aimed for.
-- When a stop doesn't work, we walk onto the spot as usual: no hoard is lost (~5s per miss).
-- Format of hoh_hoard_radius.csv:
-- time,territory,target_dist,stop_dist,stop_dy,closest_on_way,triggered,delay,appeared_on_way,phase
--   stop_dist = flat distance from the spot where we stopped; closest_on_way = closest we got
--   while moving there (a path can pass over the spot); delay = seconds from stopping to the
--   coffer (-1 if none); appeared_on_way = the coffer appeared before we stopped.
-- ============================================================
-- Result on floor 11 (38 tests over several sessions): discovered from 2.00y, never
-- from 2.01y; coffer 1.2-1.5s after stopping inside that. Off now; set true to measure again.
local RadiusTest   -- defined in the block below (kept local to it: 200-locals limit)
do
local RADIUS_TEST_ON = false
local RADIUS_START, RADIUS_STEP = 1.0, 0.5
local RADIUS_PRECISION = 0.1
local RADIUS_CONFIRM = 6          -- after converging: this many checks, alternating inside/outside
local RADIUS_MARGIN = 0.1         -- how far inside/outside the found edge the checks aim
local RADIUS_WAIT = 4.5           -- longest coffer delay seen on the spot: 3.0s
local RADIUS_FILE = Svc.PluginInterface.ConfigDirectory.FullName .. "\\hoh_hoard_radius.csv"
local radius = { lo = 0, hi = nil, n = 0, confirm = 0, done = false, overSum = 0, overN = 0 }

local function FlatDist(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2) end

local function RadiusNext()
    if radius.done then return nil end
    if radius.hi == nil then
        if radius.n == 0 then return RADIUS_START, "up" end
        return math.max(RADIUS_START, radius.lo + RADIUS_STEP), "up"
    end
    if radius.hi - radius.lo > RADIUS_PRECISION then return (radius.lo + radius.hi) / 2, "halve" end
    if radius.confirm < RADIUS_CONFIRM then
        if radius.confirm % 2 == 0 then return math.max(0.1, radius.lo - RADIUS_MARGIN), "confirm-in" end
        return radius.hi + RADIUS_MARGIN, "confirm-out"
    end
    radius.done = true
    LogI(string.format("Radius test done for this session: discovered from %.2fy, not from %.2fy", radius.lo, radius.hi))
    return nil
end

-- Returns true if the hoard was discovered (or its coffer appeared) during the test.
RadiusTest = function(spot)
    if not RADIUS_TEST_ON or V3 == nil then return false end
    local target, phase = RadiusNext()
    if target == nil then return false end

    local me = Entity.Player.Position
    local d0 = FlatDist(me, spot)
    if d0 < target + 2 then
        LogD(string.format("Radius test skipped: only %.1fy from the spot", d0))
        return false
    end
    -- Stopping point: `target` yalms from the spot, toward where we are now. vnavmesh stops a
    -- little before the point it's sent to (0.1-0.2y), so aim that much closer.
    local over = radius.overN > 0 and radius.overSum / radius.overN or 0.15
    local aim = math.max(0.05, target - over)
    local ux, uz = (me.X - spot.X) / d0, (me.Z - spot.Z) / d0
    local ok, pt = pcall(function()
        return IPC.vnavmesh.NearestPoint(V3(spot.X + ux * aim, spot.Y, spot.Z + uz * aim), 1, 3)
    end)
    if not ok or pt == nil then
        LogD("Radius test skipped: no navmesh at the stopping point")
        return false
    end

    local closest, onWay = d0, false
    MoveTo(pt, spot, function()
        local p = Entity.Player.Position
        local d = FlatDist(p, spot)
        if d < closest then closest = d end
        if not onWay and (FindObject(HOARD_COFFER_ID) ~= nil or HOH_DISCOVERED) then onWay = true end
    end)
    if IsDead() then return false end
    Wait(0.2)
    local p = Entity.Player.Position
    local stop, dy = FlatDist(p, spot), p.Y - spot.Y
    if stop < closest then closest = stop end
    radius.overSum = radius.overSum + (stop - aim); radius.overN = radius.overN + 1

    local t, delay = 0, nil
    if onWay then delay = 0 end
    while delay == nil and t < RADIUS_WAIT and not IsDead() do
        if FindObject(HOARD_COFFER_ID) ~= nil or HOH_DISCOVERED then delay = t; break end
        Wait(0.1); t = t + 0.1
    end
    local hit = delay ~= nil

    -- Update the bounds. A test where we passed closer on the way, or the coffer came before we
    -- stopped, says nothing about the stop distance: logged, bounds unchanged.
    radius.n = radius.n + 1
    local clean = not onWay and closest >= stop - 0.05
    if clean then
        if phase:sub(1, 7) == "confirm" then radius.confirm = radius.confirm + 1 end
        if hit then
            if radius.hi ~= nil and stop >= radius.hi then
                LogI(string.format("Radius test: discovered from %.2fy, past the %.2fy that failed before; widening", stop, radius.hi))
                radius.hi = nil; radius.confirm = 0
            end
            if stop > radius.lo then radius.lo = stop end
        else
            if stop <= radius.lo then
                LogI(string.format("Radius test: NOT discovered from %.2fy, inside the %.2fy that worked before; narrowing", stop, radius.lo))
                radius.lo = math.max(0, stop - RADIUS_PRECISION); radius.confirm = 0
            end
            if radius.hi == nil or stop < radius.hi then radius.hi = stop end
        end
    end
    LogD(string.format("Radius test %d (%s): stopped %.2fy from the spot (aimed %.2f, closest on the way %.2f): %s; now works from %.2f, fails from %s",
        radius.n, phase, stop, target, closest,
        onWay and "coffer appeared on the way" or hit and string.format("coffer after %.1fs", delay)
            or string.format("no coffer in %.1fs", RADIUS_WAIT),
        radius.lo, radius.hi and string.format("%.2f", radius.hi) or "?"))
    local f = io.open(RADIUS_FILE, "a")
    if f ~= nil then
        f:write(string.format("%s,%d,%.2f,%.2f,%.2f,%.2f,%s,%.1f,%s,%s\n", os.date("!%Y-%m-%dT%H:%M:%SZ"), Territory(),
            target, stop, dy, closest, tostring(hit), delay or -1, tostring(onWay), phase))
        f:close()
    else
        LogI("WARNING: couldn't write " .. RADIUS_FILE)
    end
    return hit
end
end

-- ============================================================
-- Combat rules (HeyKupo):
--   1. In combat with a magicite left: use it (both modes), even standing on the hoard; it ends
--      combat, so the normal leave works without SND's forced leave.
--   2. Sixth Sense: after a magicite, use a Concealment right away (nothing has aggro after it).
--   3. Sixth Sense: Concealment only (no magicite left) and combat starts: leave the floor.
--      Normal mode: push on to the hoard (a death after discovering it still counts).
-- We can't read how many magicite the save holds, so each slot is tried once per floor: if
-- combat is still on 4s later it didn't work (none left, or more enemies came). A slot that
-- fails twice in a session isn't tried again (the save's contents are the same every run).
-- ============================================================
local function InCombat()
    local inC = false
    pcall(function()
        local lp = Svc.Objects.LocalPlayer
        if lp ~= nil then inC = string.find(tostring(lp.StatusFlags), "InCombat", 1, true) ~= nil end
    end)
    collectgarbage("collect")
    collectgarbage("collect")
    return inC
end

InCombatNow = InCombat
local MAGICITE_WAIT = 8   -- 4 was too short: Inferno ended combat 5.5s after use while moving
local floorMagicTried = {}    -- per floor: slot -> true
local function TryMagicite()
    for slot = 0, 2 do
        if not floorMagicTried[slot] and DDX.MagCount(slot) > 0 then
            floorMagicTried[slot] = true
            LogD("In combat: magicite (slot " .. slot .. ")")
            DDX.Use("/callback DeepDungeonStatus true 12 " .. slot)
            local t = 0
            while t < MAGICITE_WAIT and InCombat() and not IsDead() do Wait(0.25); t = t + 0.25 end
            if not InCombat() then
                LogD(string.format("Combat over %.1fs after the magicite", t))
                return true, slot
            end
        end
    end
    return false
end

-- Normal mode, rule 1 (call often while moving to / standing on the hoard, and before leaving).
-- No magicite to the rescue: Pomander of Steel, once per floor, if the save has one.
DDX.hoard = nil   -- normal runs: this floor's hoard ({X, Z}), for magicite timing
local function NormalCombatCheck()
    if IsDead() or not InCombat() then return end
    if DDX.fightLogged == false then
        -- Who started it, and where (debug).
        DDX.fightLogged = true
        pcall(function()
            local lp = Svc.Objects.LocalPlayer
            for obj in luanet.each(Svc.Objects) do
                if obj ~= nil and obj.TargetObjectId == lp.GameObjectId and string.find(tostring(obj.ObjectKind), "BattleNpc", 1, true) then
                    local dx, dz = lp.Position.X - obj.Position.X, lp.Position.Z - obj.Position.Z
                    LogD(string.format("Fight started by %s at %.1fy: it at (%.1f, %.1f), us at (%.1f, %.1f)", tostring(obj.Name.TextValue),
                        math.sqrt(dx * dx + dz * dz), obj.Position.X, obj.Position.Z, lp.Position.X, lp.Position.Z))
                end
            end
        end)
    end
    -- Attacked on the way: keep running and use the magicite at the hoard, so we discover it and
    -- can leave cleanly; right away only if the hoard is far or HP is getting low.
    if DDX.hoard ~= nil then
        local p = Entity.Player.Position
        local d = math.sqrt((p.X - DDX.hoard.X) ^ 2 + (p.Z - DDX.hoard.Z) ^ 2)
        local okh, hp = pcall(function() return Entity.Player.HealthPercent end)
        if d > 2.5 and d <= 50 and not (okh and hp ~= nil and hp < 30) then return end
    end
    if not TryMagicite() and not floorMagicTried.steel and not IsDead() and InCombat() then
        floorMagicTried.steel = true
        LogD("In combat, no magicite: Pomander of Steel")
        DDX.Use(PomCmd(POM.steel))
    end
end


-- ============================================================
-- One attempt: returns true if the hoard was taken
-- ============================================================
local function Attempt()
    floorRooms = nil
    floorMagicTried = {}
    DDX.hoard = nil
    SAFETY_USED = false
    STEALTH = false
    PENDING_CONCEAL = nil
    for k, v in pairs(lastDash) do   -- no clock: allow each dash once per run
        if v == true then lastDash[k] = nil end
    end
    EnterWithSave()
    WaitUntil(function() return InDeepDungeon() and Player.Available and not Player.IsBusy end, 120, "floor load")
    do local p = Entity.Player.Position; floorStart = { X = p.X, Z = p.Z } end
    -- Wait until SND reports the floor (in a deep dungeon, in a room) rather than a fixed delay.
    WaitUntil(DDX.FloorReady, 15, "deep dungeon floor")
    Wait(0.5)

    -- HOH_SENSE is set by HoH_OnChat (called from the macro's OnChatMessage) from Intuition's
    -- chat result: "yes" = "You sense the Accursed Hoard calling you...", "no" = "You do not sense...".
    -- It arrives ~1s after Intuition; the marker ~0.3s after that. Without the watcher, fall back
    -- to waiting HOARD_DETECT_SECONDS for the marker.
    HOH_SENSE = nil
    HOH_DISCOVERED = false
    local intuitionBefore = DDX.PomCount(POM.intuition)
    UseIntuition()

    local marker = nil
    local t = 0
    local limit = HOARD_DETECT_SECONDS
    local senseAt = nil
    local intuitionTries = 1
    while t < limit do
        Wait(0.25); t = t + 0.25
        -- A use during an animation lock is ignored: if the count hasn't dropped, use it again.
        if HOH_SENSE == nil and t >= intuitionTries * 1.0 and intuitionTries < 3
           and DDX.PomCount(POM.intuition) >= intuitionBefore and intuitionBefore > 0 then
            intuitionTries = intuitionTries + 1
            LogD("Intuition didn't take; again (try " .. intuitionTries .. ")")
            UseIntuition()
        end
        marker = FindObject(HOARD_MARKER_ID)
        if marker ~= nil then break end
        if HOH_SENSE == "no" then break end
        if HOH_SENSE == "yes" and senseAt == nil then
            senseAt = t
            limit = t + MARKER_AFTER_SENSE_SECONDS
        end
    end
    LogD(string.format("Intuition result after %.2fs: %s", t,
        HOH_SENSE == "yes" and "hoard" or HOH_SENSE == "no" and "no hoard" or "(no chat result)"))

    if RECORD_SPOTS then LogFloorLayout(marker ~= nil or HOH_SENSE == "yes") end
    if marker == nil and HOH_SENSE ~= "yes" then
        LogD("No hoard on this floor")
        return "none"
    end

    -- A pomander/magicite right after Intuition is dropped (still in Intuition's animation lock).
    if t < POMANDER_LOCK_SECONDS then Wait(POMANDER_LOCK_SECONDS - t) end

    UseProtection()

    if marker == nil then
        LogD("Hoard sensed but marker not loaded yet, exploring")
        DumpNearbyObjects()
        marker = Explore()
        if marker == nil and IsDead() then
            LogI("Died while exploring")
            return "died"
        end
        if marker == nil then
            LogI("SENSED BUT NOT FOUND after exploring")
            return "unseen"
        end
        LogD("Marker found while exploring")
    else
        LogD(string.format("Marker seen %.2fs after Intuition", t))
    end
    LogD("Hoard found")
    RecordSpot(marker.Position)
    TimerStart(marker.Position)
    if STEALTH then LogD("Status effects: " .. StatusNames()) end

    local markerPos = marker.Position   -- a copy (Vector3 is a value): don't touch `marker` after waiting
    marker = nil
    local spot = { X = markerPos.X, Y = markerPos.Y, Z = markerPos.Z }
    DDX.hoard = { X = spot.X, Z = spot.Z }
    if not RadiusTest(spot) and not IsDead() then
        local wps = HOH_ROUTE ~= nil and HOH_ROUTE(markerPos.X, markerPos.Z) or nil
        if wps ~= nil and #wps > 0 then
            LogD(string.format("Doorway route: %d waypoints to the hoard's room", #wps))
        end
        DDX.fightLogged = false
        if wps ~= nil and #wps > 0 then HOH_WALK(wps, markerPos, NormalCombatCheck) end
        if not IsDead() then MoveTo(markerPos, nil, NormalCombatCheck) end
    end
    if IsDead() then
        LogI("Died on the way to the hoard")
        return "died"
    end

    -- Standing on the spot makes the coffer appear (~2.5s). Wait for the game's "You discover a
    -- piece of the Accursed Hoard!" (or a few seconds after the coffer appears), then leave.
    local t, appearedAt = 0, nil
    while t < HOARD_RETRY_SECONDS do
        TimerTick()
        if HOH_DISCOVERED then
            LogD(string.format("Hoard discovered (chat), %.1fs", t))
            return "taken"
        end
        if appearedAt == nil and FindObject(HOARD_COFFER_ID) ~= nil then appearedAt = t end
        NormalCombatCheck()
        if appearedAt ~= nil and t - appearedAt >= DISCOVER_CHAT_WAIT then
            LogD("Hoard discovered (coffer appeared; no chat line seen)")
            return "taken"
        end
        if IsDead() then
            LogI("Died before discovering the hoard")
            return "died"
        end
        Wait(0.25); t = t + 0.25
    end
    LogI("Hoard NOT discovered: coffer never appeared after " .. HOARD_RETRY_SECONDS .. "s (didn't reach the spot, or transformed?)")
    return "missed"
end

-- Floor 11 rooms (HoH floors 11-19), from our own runs. Per tileset (A = west
-- area, B = east): [room 1..25].c = where a floor that starts in that room puts you (the room's
-- spawn point; nil = no room there), and halls["a>b"] = where the game switches the room you're in
-- from a to b, a point inside that hallway (median over our crossings). Replaces the
-- BossModReborn table used before.
local HOH11 = {
    A = {
        {},   -- 1
        { c = { -371.8, 188.2 } },   -- 2
        { c = { -287.8, 187.2 } },   -- 3
        { c = { -223.8, 199.2 } },   -- 4
        {},   -- 5
        { c = { -403.8, 244.2 } },   -- 6
        { c = { -351.8, 244.2 } },   -- 7
        { c = { -300.3, 244.2 } },   -- 8
        { c = { -235.8, 255.2 } },   -- 9
        { c = { -191.8, 254.7 } },   -- 10
        { c = { -417.8, 300.2 } },   -- 11
        { c = { -363.8, 300.2 } },   -- 12
        { c = { -299.8, 300.2 } },   -- 13
        { c = { -235.8, 312.7 } },   -- 14
        { c = { -180.3, 312.2 } },   -- 15
        { c = { -403.8, 356.2 } },   -- 16
        { c = { -351.8, 356.2 } },   -- 17
        { c = { -299.8, 356.2 } },   -- 18
        { c = { -235.8, 368.2 } },   -- 19
        { c = { -184.3, 368.2 } },   -- 20
        {},   -- 21
        { c = { -363.8, 410.2 } },   -- 22
        { c = { -279.8, 412.2 } },   -- 23
        { c = { -223.8, 426.2 } },   -- 24
        {},   -- 25
        halls = {
            ["2>7"] = { -360.5, 218.1 }, ["3>8"] = { -296.4, 219.8 }, ["4>9"] = { -232.7, 230.7 }, ["6>7"] = { -374.8, 244.1 },
            ["7>2"] = { -365.1, 214.3 }, ["7>6"] = { -381.6, 243.1 }, ["7>12"] = { -359.9, 274.0 }, ["8>3"] = { -292.7, 213.3 },
            ["8>13"] = { -300.0, 274.6 }, ["9>4"] = { -228.8, 224.1 }, ["9>10"] = { -211.2, 257.4 }, ["9>14"] = { -236.0, 281.8 },
            ["10>9"] = { -216.5, 255.0 }, ["11>12"] = { -387.3, 300.0 }, ["12>7"] = { -356.2, 268.7 }, ["12>11"] = { -393.9, 298.8 },
            ["12>13"] = { -334.3, 300.0 }, ["12>17"] = { -355.8, 330.9 }, ["13>8"] = { -300.1, 268.1 }, ["13>12"] = { -340.5, 300.0 },
            ["13>14"] = { -269.4, 308.0 }, ["13>18"] = { -300.0, 333.1 }, ["14>9"] = { -236.0, 274.9 }, ["14>13"] = { -275.1, 304.7 },
            ["14>15"] = { -205.8, 314.1 }, ["14>19"] = { -236.0, 342.5 }, ["15>14"] = { -211.6, 311.4 }, ["16>17"] = { -374.3, 356.0 },
            ["17>12"] = { -359.7, 324.6 }, ["17>16"] = { -381.4, 354.5 }, ["17>22"] = { -360.1, 386.2 }, ["18>13"] = { -300.0, 325.9 },
            ["18>23"] = { -285.2, 387.5 }, ["19>14"] = { -236.0, 335.3 }, ["19>20"] = { -206.7, 365.9 }, ["19>24"] = { -227.6, 400.1 },
            ["20>19"] = { -213.3, 368.0 }, ["22>17"] = { -356.3, 381.1 }, ["23>18"] = { -292.1, 382.6 }, ["24>19"] = { -231.9, 394.1 }
        },
    },
    B = {
        {},   -- 1
        { c = { 244.2, -410.8 } },   -- 2
        { c = { 292.2, -411.3 } },   -- 3
        { c = { 380.2, -410.8 } },   -- 4
        {},   -- 5
        { c = { 202.2, -344.8 } },   -- 6
        { c = { 256.2, -344.8 } },   -- 7
        { c = { 312.2, -356.8 } },   -- 8
        { c = { 368.2, -344.8 } },   -- 9
        { c = { 432.7, -356.8 } },   -- 10
        { c = { 188.2, -300.8 } },   -- 11
        { c = { 244.2, -288.3 } },   -- 12
        { c = { 300.2, -300.8 } },   -- 13
        { c = { 356.2, -288.8 } },   -- 14
        { c = { 409.7, -289.3 } },   -- 15
        { c = { 195.7, -230.8 } },   -- 16
        { c = { 246.2, -230.8 } },   -- 17
        { c = { 300.2, -242.8 } },   -- 18
        { c = { 354.7, -230.8 } },   -- 19
        { c = { 405.2, -230.8 } },   -- 20
        {},   -- 21
        { c = { 234.2, -171.3 } },   -- 22
        { c = { 320.7, -186.8 } },   -- 23
        { c = { 366.7, -172.8 } },   -- 24
        {},   -- 25
        halls = {
            ["2>7"] = { 252.3, -377.8 }, ["3>8"] = { 303.4, -383.3 }, ["4>9"] = { 372.6, -371.7 }, ["6>7"] = { 232.7, -345.9 },
            ["7>2"] = { 248.2, -385.2 }, ["7>6"] = { 225.2, -346.9 }, ["7>8"] = { 287.4, -352.9 }, ["8>3"] = { 299.0, -387.3 },
            ["8>7"] = { 282.1, -349.3 }, ["8>9"] = { 344.6, -349.1 }, ["8>13"] = { 303.8, -326.4 }, ["9>4"] = { 375.5, -376.5 },
            ["9>8"] = { 338.9, -352.1 }, ["9>10"] = { 399.8, -352.6 }, ["10>9"] = { 394.4, -349.4 }, ["11>12"] = { 220.8, -292.5 },
            ["12>11"] = { 213.5, -296.9 }, ["12>13"] = { 275.4, -296.9 }, ["13>8"] = { 307.8, -332.2 }, ["13>12"] = { 270.3, -293.4 },
            ["13>14"] = { 331.2, -293.3 }, ["13>18"] = { 299.9, -272.4 }, ["14>13"] = { 325.7, -296.8 }, ["14>15"] = { 385.8, -286.6 },
            ["15>14"] = { 377.6, -289.3 }, ["16>17"] = { 223.9, -231.0 }, ["17>16"] = { 218.1, -231.2 }, ["17>18"] = { 275.7, -239.0 },
            ["17>22"] = { 238.0, -198.8 }, ["18>13"] = { 300.0, -280.7 }, ["18>17"] = { 269.4, -234.8 }, ["18>19"] = { 331.1, -235.3 },
            ["18>23"] = { 314.3, -212.6 }, ["19>18"] = { 326.8, -238.2 }, ["19>20"] = { 381.6, -228.9 }, ["19>24"] = { 362.4, -198.6 },
            ["20>19"] = { 376.2, -230.5 }, ["22>17"] = { 241.3, -203.3 }, ["23>18"] = { 308.3, -217.0 }, ["24>19"] = { 359.4, -203.9 }
        },
    },
}

-- Room grid helpers (rooms indexed 1..25 here; the game's are 0..24). One table, to stay under
-- Lua's 200-locals-per-function limit (everything lives inside HoH_Main).
local DD = {}
function DD.Door(geo, r, nb)
    -- Where to pass from room r into neighbour nb: the point inside that hallway where the room
    -- switches (this direction, else the other one), else halfway between the rooms.
    local h = geo.halls[r .. ">" .. nb] or geo.halls[nb .. ">" .. r]
    if h ~= nil then return { h } end
    local a, b = geo[r], geo[nb]
    if a.c ~= nil and b.c ~= nil then return { { (a.c[1] + b.c[1]) / 2, (a.c[2] + b.c[2]) / 2 } } end
    return {}
end

-- A little variety: a hallway point moved at random up to DD.JITTER_ALONG yalms
-- along the hallway and DD.JITTER_ACROSS across it. Any point in the hallway does the same job,
-- so the route stays as good, but no two walks through it are the same.
DD.JITTER_ALONG, DD.JITTER_ACROSS = 3, 1
function DD.Jitter(geo, r, nb, p)
    local a, b = geo[r], geo[nb]
    if a == nil or b == nil or a.c == nil or b.c == nil then return p end
    local along = (math.random() * 2 - 1) * DD.JITTER_ALONG
    local across = (math.random() * 2 - 1) * DD.JITTER_ACROSS
    if math.abs(b.c[1] - a.c[1]) >= math.abs(b.c[2] - a.c[2]) then
        return { p[1] + along, p[2] + across }   -- east-west hallway
    end
    return { p[1] + across, p[2] + along }       -- north-south hallway
end

-- Room path from a to b (both 1..25) along the floor's real exits; {} if a == b, nil if unreachable.
-- Deep dungeon floors are trees (one route between any two rooms), so a plain search is enough.
function DD.Path(flags, a, b)
    if a == b then return {} end
    local prev, queue, seen = {}, { a }, { [a] = true }
    local head = 1
    while head <= #queue do
        local r = queue[head]; head = head + 1
        local f = flags[r] or 0
        local nbs = {}
        if f & 1 ~= 0 then table.insert(nbs, r - 5) end
        if f & 2 ~= 0 then table.insert(nbs, r + 5) end
        if f & 4 ~= 0 then table.insert(nbs, r - 1) end
        if f & 8 ~= 0 then table.insert(nbs, r + 1) end
        for _, nb in ipairs(nbs) do
            if nb >= 1 and nb <= 25 and not seen[nb] then
                seen[nb] = true
                prev[nb] = r
                if nb == b then
                    local path, x = {}, b
                    while x ~= a do table.insert(path, 1, x); x = prev[x] end
                    return path
                end
                table.insert(queue, nb)
            end
        end
    end
    return nil
end

-- Waypoints (list of {x, z}) to walk from room a to room b through the doorways.
function DD.Waypoints(geo, flags, a, b)
    local path = DD.Path(flags, a, b)
    if path == nil then return nil end
    local pts, cur = {}, a
    for _, nb in ipairs(path) do
        for _, p in ipairs(DD.Door(geo, cur, nb)) do table.insert(pts, DD.Jitter(geo, cur, nb, p)) end
        cur = nb
    end
    return pts
end

-- Normal runs (one went into a dead-end room and doubled back, since vnavmesh's mesh has
-- every possible passage): walk room to room through the doorways to the hoard's room first.
-- Globals, because Attempt() comes before these tables in the file.
function HOH_ROUTE(x, z)   -- doorway waypoints {x, z} from our room to the room at (x, z), or nil
    local fl = FloorLayout()
    if fl == nil or fl.floor == nil or fl.floor < 11 or fl.floor > 19 then return nil end
    local geo = HOH11[fl.tileset]
    if geo == nil then return nil end
    local flags = {}
    for i = 1, 25 do flags[i] = fl.rooms[i] or 0 end
    local a = (fl.me or -1) + 1
    local b = DD.Nearest(geo, x, z)
    if a < 1 or b == nil or flags[a] == 0 or flags[b] == 0 then return nil end
    return DD.Waypoints(geo, flags, a, b)
end
function HOH_WALK(wps, hoardPos, onTick)
    for i, w in ipairs(wps) do
        if IsDead() then return end
        local wy = Entity.Player.Position.Y
        local ok, pt = pcall(function() return IPC.vnavmesh.NearestPoint(V3(w[1], wy, w[2]), 2, 3) end)
        local target = (ok and pt ~= nil) and pt or V3(w[1], wy, w[2])
        IPC.vnavmesh.PathfindAndMoveTo(target, false)
        local t = 0
        while IPC.vnavmesh.PathfindInProgress() and t < 10 do Wait(0.1); t = t + 0.1 end
        if i == 1 then Wait(0.4); SpeedUp(target, hoardPos) end
        t = 0
        -- Move on to the next doorway when close, without stopping.
        while IPC.vnavmesh.IsRunning() and not IsDead() and DistanceTo(target) > 3 and t < 30 do
            Wait(0.25); t = t + 0.25
            TimerTick()
            if onTick ~= nil then onTick() end
        end
        if t >= 30 then LogD("Doorway route: no progress, going straight to the hoard"); return end
    end
end

-- Nearest room (1..25) of this tileset to a point, and how far its center is.
function DD.Nearest(geo, x, z)
    local best, bd = nil, nil
    for i, r in ipairs(geo) do
        if r.c ~= nil then
            local d = (r.c[1] - x) ^ 2 + (r.c[2] - z) ^ 2
            if bd == nil or d < bd then best, bd = i, d end
        end
    end
    return best, bd and math.sqrt(bd) or nil
end

-- ============================================================
-- Sixth Sense (setting "SixthSense"): hoards WITHOUT Intuition, for "Of the Sixth Sense".
-- The floor's layout area is the group of known spots nearest where the floor starts. Spots
-- within SX.COVER of one standing point share a stop (discovery works from 2.0y: measured
-- see the radius test). Stops are visited by likelihood per second of travel, and the
-- search ends after the number of stops that gives the best hoards per hour, given how long a
-- floor takes to cycle (measured as we go). Then leave and try a fresh floor.
-- Needs a save with Safety (spots are trap spots) and Concealment; magicite as a backup.
-- Logs (SND's config folder): hoh_sixth_floors.csv, hoh_sixth_stops.csv, hoh_sixth_enemies.csv,
-- hoh_sixth_events.csv. Sixth Sense finds are NOT added to the spot list (the search only finds
-- hoards at stops it reaches, so they'd skew the odds toward the already-likely spots).
-- ============================================================
local SIXTH = CfgBool("SixthSense", false)
-- Search over, still fighting: how long to wait for death (then the results screen and the
-- normal leave) before SND's forced leave, a last resort. 90s in both modes (HeyKupo: dying
-- cleanly beats a forced leave; Sixth Sense used 10s before, as one mob can take a while).
HOH_DEATH_WAIT = 90
local SX = {}   -- Sixth Sense constants (a table: Lua allows only 200 locals per function)
-- Sixth Sense doesn't leave when attacked or out of Concealment: it keeps going through the
-- planned stops until the hoard, death, or the end.
SX.TALLY_OFFSET = 100000   -- the tally keeps Sixth Sense runs as territory + this
SX.COVER = 1.8             -- a spot counts as checked from this close (edge is 2.0y)
SX.SHUFFLE = 1.9           -- after a stop, step closer to any covered spot farther than this
SX.WAIT = 1.8              -- seconds per stop: the game needs you in range ~1.2-1.5s before it counts a find
                          -- (it confirms just after we leave). Not a setting: a missed hoard costs far more
                          -- than the wait saves.
SX.MAX_SECONDS = 600       -- give up on a floor after this long, whatever the plan says
SX.CONFIG_DIR = Svc.PluginInterface.ConfigDirectory.FullName
SX.FLOORS_FILE = SX.CONFIG_DIR .. "\\hoh_sixth_floors.csv"
SX.STOPS_FILE = SX.CONFIG_DIR .. "\\hoh_sixth_stops.csv"
SX.ENEMIES_FILE = SX.CONFIG_DIR .. "\\hoh_sixth_enemies.csv"
SX.EVENTS_FILE = SX.CONFIG_DIR .. "\\hoh_sixth_events.csv"

local function NowMs()
    local v = Ms()
    if v ~= nil then return v end
    return (os.time() or 0) * 1000
end

local function AppendCsv(path, header, line)
    local exists = io.open(path, "r")
    if exists ~= nil then exists:close() end
    local f = io.open(path, "a")
    if f == nil then LogI("WARNING: couldn't write " .. path); return end
    if exists == nil then f:write(header .. "\n") end
    f:write(line .. "\n")
    f:close()
end

-- Session estimates, updated as we go (start from the model's guesses).
local est = { legT = 0.18 * 60, legD = 60, overT = 25 * 3, overN = 3 }
local function SecsPerYalm() return est.legT / est.legD end
local function Overhead() return est.overT / est.overN end

-- Spot areas and stops per territory, built once per session.
local sixthCache = {}   -- terr -> { areas = { {spots, stops, name}... }, ph, cover, spotArea }

local function BuildStops(area)
    local total = 0
    for _, s in ipairs(area) do total = total + s.N end
    if total <= 0 then total = 1 end
    local cands = {}
    for _, s in ipairs(area) do table.insert(cands, { X = s.X, Y = s.Y, Z = s.Z }) end
    local pairMax = (2 * SX.COVER) ^ 2
    for i = 1, #area do
        for j = i + 1, #area do
            local a, b = area[i], area[j]
            if (a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2 <= pairMax then
                table.insert(cands, { X = (a.X + b.X) / 2, Y = (a.Y + b.Y) / 2, Z = (a.Z + b.Z) / 2 })
            end
        end
    end
    local r2 = SX.COVER ^ 2
    local cov = {}
    for ci, c in ipairs(cands) do
        local l = {}
        for i, s in ipairs(area) do
            if (s.X - c.X) ^ 2 + (s.Z - c.Z) ^ 2 <= r2 then table.insert(l, i) end
        end
        cov[ci] = l
    end
    local left, nleft, stops = {}, #area, {}
    for i = 1, #area do left[i] = true end
    while nleft > 0 do
        local best, bestW = nil, -1
        for ci, l in ipairs(cov) do
            local w = 0
            for _, i in ipairs(l) do if left[i] then w = w + area[i].N + 0.001 end end
            if w > bestW then best, bestW = ci, w end
        end
        local c = cands[best]
        local st = { X = c.X, Y = c.Y, Z = c.Z, W = 0, Spots = {} }
        for _, i in ipairs(cov[best]) do
            if left[i] then
                left[i] = false
                nleft = nleft - 1
                st.W = st.W + area[i].N
                table.insert(st.Spots, area[i])
            end
        end
        st.W = st.W / total
        table.insert(stops, st)
    end
    return stops
end

-- Known hoard spots (shipped data: HeyKupo's normal runs, with Intuition, so the counts are unbiased).
-- {territory, x, y, z, finds}; 239 spots, 1988 finds. Combined with your own
-- hoh_hoard_spots.csv if you record spots (RecordSpots): per spot, the larger count is used.
local SHIPPED_SPOTS = {
    { 771, -427.25, 0.02, 303.50, 2 }, { 771, -426.39, 0.02, 304.37, 5 }, { 771, -422.73, 0.02, 307.18, 4 },
    { 771, -421.90, 0.02, 308.11, 2 }, { 771, -418.48, 0.02, 290.30, 3 }, { 771, -417.65, 0.02, 291.18, 5 },
    { 771, -413.12, 6.00, 355.37, 5 }, { 771, -411.82, 6.00, 356.66, 5 }, { 771, -409.30, -5.98, 234.34, 4 },
    { 771, -408.39, -5.98, 235.26, 4 }, { 771, -406.71, 6.00, 346.38, 3 }, { 771, -406.53, 0.02, 295.08, 1 },
    { 771, -405.45, 6.00, 347.72, 6 }, { 771, -404.72, 0.02, 297.81, 4 }, { 771, -400.05, 6.00, 366.45, 2 },
    { 771, -398.92, 6.00, 367.98, 4 }, { 771, -395.92, -5.98, 233.50, 4 }, { 771, -394.44, -5.98, 235.13, 10 },
    { 771, -393.54, -5.98, 241.84, 4 }, { 771, -391.39, 6.00, 357.64, 1 }, { 771, -391.13, -5.98, 244.81, 10 },
    { 771, -389.58, 6.00, 359.36, 4 }, { 771, -375.31, 0.02, 181.01, 9 }, { 771, -375.15, 0.02, 198.93, 6 },
    { 771, -374.16, 0.03, 399.66, 4 }, { 771, -372.72, 0.02, 201.27, 12 }, { 771, -372.36, 0.05, 402.33, 8 },
    { 771, -369.42, 0.05, 403.52, 3 }, { 771, -366.21, 0.02, 192.93, 10 }, { 771, -365.20, 0.02, 239.22, 6 },
    { 771, -363.42, 0.02, 241.34, 6 }, { 771, -357.53, 0.05, 415.52, 11 }, { 771, -356.30, 0.02, 348.17, 4 },
    { 771, -353.52, -0.00, 294.95, 28 }, { 771, -353.51, 0.00, 301.84, 16 }, { 771, -353.11, 0.02, 230.14, 6 },
    { 771, -352.90, 0.02, 341.46, 6 }, { 771, -351.44, 0.02, 232.40, 17 }, { 771, -351.41, 0.05, 413.10, 7 },
    { 771, -351.14, 0.02, 343.76, 13 }, { 771, -350.93, 0.00, 297.46, 24 }, { 771, -350.93, 0.00, 304.36, 26 },
    { 771, -349.98, 0.02, 255.79, 5 }, { 771, -349.22, 0.05, 416.05, 6 }, { 771, -348.08, 0.02, 257.71, 13 },
    { 771, -343.98, 0.02, 364.15, 21 }, { 771, -339.55, 0.02, 350.78, 9 }, { 771, -338.21, 0.02, 352.17, 7 },
    { 771, -305.74, -0.00, 283.42, 30 }, { 771, -305.12, 0.00, 289.43, 27 }, { 771, -304.89, 0.02, 366.56, 5 },
    { 771, -304.00, 0.00, 285.44, 29 }, { 771, -303.94, 0.02, 235.20, 9 }, { 771, -302.61, 0.02, 369.29, 6 },
    { 771, -302.07, -0.00, 168.30, 3 }, { 771, -302.06, -0.00, 177.18, 1 }, { 771, -301.58, -0.00, 168.93, 3 },
    { 771, -301.58, -0.00, 177.84, 5 }, { 771, -301.21, 0.02, 342.13, 2 }, { 771, -298.91, 0.02, 344.82, 11 },
    { 771, -292.69, 0.02, 250.27, 10 }, { 771, -291.19, 0.00, 307.15, 24 }, { 771, -291.06, 0.00, 200.82, 4 },
    { 771, -290.90, 0.02, 355.36, 4 }, { 771, -290.07, 0.02, 421.15, 1 }, { 771, -289.89, 0.02, 356.32, 14 },
    { 771, -289.79, 0.02, 401.79, 3 }, { 771, -289.16, 0.02, 422.53, 5 }, { 771, -288.67, 0.02, 238.22, 10 },
    { 771, -288.58, 0.02, 403.37, 7 }, { 771, -286.90, 0.02, 239.87, 5 }, { 771, -280.23, 0.02, 400.65, 2 },
    { 771, -279.48, 0.02, 401.72, 7 }, { 771, -275.05, 0.00, 180.18, 2 }, { 771, -274.14, 0.00, 181.05, 3 },
    { 771, -270.54, 0.02, 421.07, 2 }, { 771, -269.49, 0.02, 422.28, 4 }, { 771, -250.19, 0.00, 259.66, 14 },
    { 771, -248.88, -0.00, 261.21, 9 }, { 771, -243.14, -0.00, 352.29, 6 }, { 771, -242.01, 0.04, 246.32, 8 },
    { 771, -241.37, 0.00, 378.87, 2 }, { 771, -240.61, 0.00, 355.34, 11 }, { 771, -239.23, 0.00, 382.04, 11 },
    { 771, -238.99, 0.02, 298.25, 11 }, { 771, -236.82, 0.02, 300.69, 27 }, { 771, -233.94, 0.02, 323.96, 12 },
    { 771, -233.19, 0.02, 189.97, 9 }, { 771, -232.35, 0.02, 325.79, 18 }, { 771, -231.51, 0.02, 192.36, 7 },
    { 771, -228.57, 0.04, 262.17, 18 }, { 771, -228.05, 0.00, 356.00, 2 }, { 771, -225.26, 0.00, 358.57, 11 },
    { 771, -223.26, 0.02, 207.94, 6 }, { 771, -223.01, 0.02, 314.74, 5 }, { 771, -221.46, 0.02, 316.65, 24 },
    { 771, -221.24, 0.02, 209.82, 11 }, { 771, -215.98, 0.02, 416.45, 26 }, { 771, -214.13, 0.02, 419.03, 2 },
    { 771, -202.76, 0.02, 263.23, 4 }, { 771, -201.37, 0.02, 264.66, 12 }, { 771, -197.22, 0.02, 247.26, 8 },
    { 771, -194.85, 0.00, 305.01, 2 }, { 771, -194.65, 0.00, 314.81, 3 }, { 771, -193.83, 0.02, 357.75, 3 },
    { 771, -192.28, 0.02, 359.79, 11 }, { 771, -192.25, 0.00, 307.95, 7 }, { 771, -192.25, 0.00, 318.01, 6 },
    { 771, -192.18, 0.02, 358.50, 6 }, { 771, -184.27, 0.02, 262.23, 11 }, { 771, -177.41, 0.02, 375.25, 9 },
    { 771, -166.89, -0.00, 297.58, 2 }, { 771, -166.80, -0.00, 325.52, 2 }, { 771, -166.16, -0.00, 298.33, 2 },
    { 771, -166.16, -0.00, 326.40, 4 }, { 771, 177.70, 0.02, -310.28, 8 }, { 771, 179.68, 0.02, -308.74, 5 },
    { 771, 180.22, 0.02, -301.72, 4 }, { 771, 186.08, -5.98, -231.23, 2 }, { 771, 187.40, -5.98, -230.51, 6 },
    { 771, 194.82, -5.98, -239.67, 1 }, { 771, 194.95, -5.98, -222.52, 3 }, { 771, 194.99, 0.02, -350.46, 5 },
    { 771, 196.12, -5.98, -239.05, 8 }, { 771, 196.19, -5.98, -222.06, 6 }, { 771, 198.80, 0.02, -293.95, 4 },
    { 771, 205.18, -5.98, -231.61, 1 }, { 771, 208.03, -5.98, -230.00, 10 }, { 771, 211.16, 0.02, -337.33, 11 },
    { 771, 215.24, 0.02, -349.83, 8 }, { 771, 216.71, 0.02, -349.05, 3 }, { 771, 220.49, 0.00, -162.71, 6 },
    { 771, 225.22, -0.00, -185.40, 4 }, { 771, 227.90, 0.00, -183.27, 4 }, { 771, 228.92, 0.02, -411.15, 1 },
    { 771, 229.39, 0.02, -284.95, 9 }, { 771, 230.35, 0.02, -410.49, 6 }, { 771, 231.08, 0.02, -284.06, 9 },
    { 771, 233.84, 0.00, -232.32, 2 }, { 771, 233.87, -0.00, -244.22, 4 }, { 771, 234.60, 0.02, -292.75, 8 },
    { 771, 235.31, 0.02, -415.23, 1 }, { 771, 235.75, -0.00, -243.48, 7 }, { 771, 242.31, 0.00, -345.50, 8 },
    { 771, 242.98, 0.02, -423.05, 1 }, { 771, 244.40, 0.02, -422.44, 8 }, { 771, 244.64, 0.00, -181.20, 2 },
    { 771, 244.94, 0.00, -215.55, 4 }, { 771, 245.65, 0.00, -180.75, 5 }, { 771, 246.63, 0.00, -214.64, 13 },
    { 771, 247.49, -0.00, -153.17, 1 }, { 771, 248.21, -0.00, -152.86, 3 }, { 771, 251.42, 0.02, -402.09, 5 },
    { 771, 251.77, 0.02, -282.60, 15 }, { 771, 252.82, 0.02, -420.01, 5 }, { 771, 254.29, 0.02, -419.20, 4 },
    { 771, 255.22, 0.00, -222.29, 13 }, { 771, 255.85, -0.00, -244.59, 2 }, { 771, 257.85, -0.00, -243.48, 9 },
    { 771, 262.67, 0.04, -337.85, 17 }, { 771, 267.61, 0.00, -346.04, 12 }, { 771, 269.65, 0.00, -344.92, 13 },
    { 771, 279.11, 0.05, -401.31, 5 }, { 771, 281.54, 0.00, -400.39, 6 }, { 771, 282.42, 0.05, -413.03, 10 },
    { 771, 289.48, 0.00, -302.91, 10 }, { 771, 294.73, 0.00, -288.10, 15 }, { 771, 296.68, 0.00, -287.16, 27 },
    { 771, 298.52, 0.02, -255.16, 28 }, { 771, 298.64, 0.02, -230.88, 32 }, { 771, 298.67, 0.02, -357.47, 35 },
    { 771, 300.71, 0.02, -356.65, 30 }, { 771, 300.91, 0.02, -254.18, 33 }, { 771, 301.05, 0.02, -229.85, 23 },
    { 771, 303.02, 0.05, -403.06, 6 }, { 771, 308.31, 0.04, -294.21, 36 }, { 771, 310.12, 0.02, -189.25, 2 },
    { 771, 310.31, 0.02, -178.33, 8 }, { 771, 312.05, 0.00, -301.46, 14 }, { 771, 312.30, 0.02, -177.44, 8 },
    { 771, 314.02, 0.00, -300.43, 22 }, { 771, 314.51, 0.02, -369.45, 23 }, { 771, 316.81, 0.02, -368.47, 30 },
    { 771, 327.75, 0.02, -182.44, 6 }, { 771, 332.05, 0.02, -187.97, 3 }, { 771, 334.07, 0.02, -186.35, 9 },
    { 771, 341.91, 0.00, -230.97, 11 }, { 771, 343.86, 0.00, -230.15, 23 }, { 771, 345.59, 0.02, -279.89, 2 },
    { 771, 345.92, 0.02, -298.05, 2 }, { 771, 346.76, 0.02, -291.11, 2 }, { 771, 347.12, 0.02, -279.04, 6 },
    { 771, 347.34, 0.02, -297.50, 7 }, { 771, 353.27, 0.02, -346.03, 6 }, { 771, 354.75, 0.02, -345.37, 17 },
    { 771, 356.60, 0.02, -182.62, 3 }, { 771, 356.94, 0.02, -173.32, 4 }, { 771, 357.99, 0.02, -172.72, 2 },
    { 771, 358.30, 0.02, -347.37, 6 }, { 771, 358.61, 0.02, -181.04, 9 }, { 771, 363.03, 0.02, -282.99, 10 },
    { 771, 363.12, 0.02, -331.73, 5 }, { 771, 364.52, 0.00, -231.05, 10 }, { 771, 364.59, 0.02, -298.02, 2 },
    { 771, 364.65, 0.02, -330.84, 11 }, { 771, 366.04, 0.02, -297.45, 10 }, { 771, 366.08, 0.02, -164.11, 4 },
    { 771, 366.40, 0.00, -230.35, 19 }, { 771, 367.09, 0.02, -163.55, 7 }, { 771, 368.45, 0.02, -417.89, 1 },
    { 771, 370.53, 0.02, -417.09, 8 }, { 771, 375.18, 0.02, -164.73, 1 }, { 771, 375.98, 0.02, -398.95, 3 },
    { 771, 376.72, 0.02, -163.92, 10 }, { 771, 378.13, 0.02, -339.00, 15 }, { 771, 378.23, 0.02, -397.76, 4 },
    { 771, 379.43, 0.02, -419.94, 1 }, { 771, 380.25, 0.02, -419.61, 4 }, { 771, 388.94, 0.02, -418.66, 4 },
    { 771, 402.24, -6.00, -279.46, 7 }, { 771, 403.66, -6.00, -278.89, 7 }, { 771, 404.42, 6.02, -240.50, 3 },
    { 771, 404.65, 6.02, -221.83, 3 }, { 771, 405.18, 6.02, -240.14, 4 }, { 771, 405.41, 6.02, -221.23, 7 },
    { 771, 414.12, 6.02, -231.34, 2 }, { 771, 414.31, 6.02, -221.67, 1 }, { 771, 414.87, 6.02, -231.01, 4 },
    { 771, 415.03, 6.02, -221.40, 7 }, { 771, 418.13, -6.00, -302.87, 9 }, { 771, 418.88, -6.00, -302.52, 2 },
    { 771, 420.77, 0.00, -347.94, 2 }, { 771, 421.17, 0.00, -371.05, 2 }, { 771, 422.54, 0.05, -347.29, 10 },
    { 771, 423.30, 0.05, -370.11, 12 }, { 771, 438.66, 0.05, -357.34, 2 }, { 771, 443.20, 0.00, -355.46, 5 },
    { 771, 443.41, -0.00, -367.98, 1 }, { 771, 444.31, -0.00, -367.27, 7 }
}

local function SixthData(terr)
    if sixthCache[terr] ~= nil then return sixthCache[terr] end
    -- Shipped spots, plus your own recorded ones (RecordSpots): the larger count per spot, so
    -- nothing is counted twice; spots only you have found are added.
    local all = {}
    for _, s in ipairs(SHIPPED_SPOTS) do
        if s[1] == terr then table.insert(all, { T = s[1], X = s[2], Y = s[3], Z = s[4], N = s[5] }) end
    end
    for _, sp in ipairs(LoadSpots()) do
        if sp.T == terr then
            local same = nil
            for _, a in ipairs(all) do
                if (a.X - sp.X) ^ 2 + (a.Z - sp.Z) ^ 2 < SPOT_SAME_DIST ^ 2 then same = a; break end
            end
            if same == nil then table.insert(all, sp)
            elseif sp.N > same.N then same.X, same.Y, same.Z, same.N = sp.X, sp.Y, sp.Z, sp.N end
        end
    end
    local data = { ph = 0.45, cover = 0.95, spots = all, roomOf = {} }
    local finds, once = 0, 0
    for _, sp in ipairs(all) do
        finds = finds + sp.N
        if sp.N == 1 then once = once + 1 end
    end
    if finds > 0 then data.cover = 1 - once / finds end
    local t = LoadTally()[terr]
    if t ~= nil and t.runs >= 200 then data.ph = t.hoard_floors / t.runs end
    LogI(string.format("Spot data: %d known spots; hoard on %.0f%% of floors, spot list covers ~%.0f%% of hoards", #all, 100 * data.ph, 100 * data.cover))
    sixthCache[terr] = data
    return data
end

-- Room (1..25) of each known spot in this tileset: the nearest room center, if within
-- SX.ROOM_MAX (spots of the other tileset's area are far from all of this one's rooms).
SX.ROOM_MAX = 45
local function SpotRooms(data, tileset, geo)
    if data.roomOf[tileset] ~= nil then return data.roomOf[tileset] end
    local m, n = {}, 0
    for _, sp in ipairs(data.spots) do
        local r, d = DD.Nearest(geo, sp.X, sp.Z)
        if r ~= nil and d <= SX.ROOM_MAX then m[sp] = r; n = n + 1 end
    end
    data.roomOf[tileset] = m
    LogI(string.format("Sixth Sense: tileset %s: %d spots placed in rooms", tileset, n))
    return m
end

-- Normal runs, hoard sensed but its marker not loaded (12% of hoard floors). The marker
-- loads once you're within about 110y of it (every hoard 94-111y from the floor start was
-- seen at once, every one 112-188y away wasn't), so the hoard is one of the known spots farther
-- than that, and walking toward it until it's in range is enough. Repeatedly: the spot with the
-- most finds per yalm still to close, walked to through the hallway points, re-planning as soon
-- as it's in range; every spot that comes into range without the marker showing is ruled out.
-- Returns true once found() says the marker has loaded. Global: Explore() comes before this.
DD.MARKER_RANGE = 100   -- yalms: count a spot as ruled out from this close (a margin under ~110)
function HOH_EXPLORE_ROOMS(found)
    local fl = FloorLayout()
    if fl == nil or fl.floor == nil or fl.floor < 11 or fl.floor > 19 then return false end
    local geo = HOH11[fl.tileset]
    if geo == nil then return false end
    local data = SixthData(Svc.ClientState.TerritoryType)
    local roomOf = SpotRooms(data, fl.tileset, geo)
    local flags = {}
    for i = 1, 25 do flags[i] = fl.rooms[i] or 0 end
    local R = DD.MARKER_RANGE
    local function Me() local p = Entity.Player.Position; return p.X, p.Z end
    local function Room() local ok, r = pcall(function() return InstancedContent.DeepDungeon.CurrentRoomIndex end); return ok and r and r + 1 or nil end
    local x0, z0 = Me()
    local cands, total = {}, 0
    for sp, r in pairs(roomOf) do
        if flags[r] ~= 0 and (sp.X - x0) ^ 2 + (sp.Z - z0) ^ 2 > R * R then
            table.insert(cands, { X = sp.X, Y = sp.Y, Z = sp.Z, N = sp.N, room = r }); total = total + sp.N
        end
    end
    local function RuleOut()
        local x, z = Me()
        for _, c in ipairs(cands) do
            if not c.out and (c.X - x) ^ 2 + (c.Z - z) ^ 2 <= R * R then c.out = true end
        end
    end
    local first = true
    for _ = 1, 12 do
        if found() then return true end
        RuleOut()
        local x, z = Me()
        local best, bestScore = nil, 0
        for _, c in ipairs(cands) do
            if not c.out then
                local d = math.sqrt((c.X - x) ^ 2 + (c.Z - z) ^ 2) - R
                local score = c.N / math.max(d, 5)
                if score > bestScore then best, bestScore = c, score end
            end
        end
        if best == nil then LogD("Explore by spots: no known spot left out of range"); return false end
        LogD(string.format("Explore by spots: toward a spot in room %d (%.0f%% of the finds still possible), %.0fy to bring it in range",
            best.room, 100 * best.N / math.max(total, 1), math.sqrt((best.X - x) ^ 2 + (best.Z - z) ^ 2) - R))
        local pts = {}
        local cur = Room()
        if cur ~= nil and cur ~= best.room then pts = DD.Waypoints(geo, flags, cur, best.room) or {} end
        table.insert(pts, { best.X, best.Z })
        for _, pnt in ipairs(pts) do
            if IsDead() then return false end
            local wy = Entity.Player.Position.Y
            local ok, np = pcall(function() return IPC.vnavmesh.NearestPoint(V3(pnt[1], wy, pnt[2]), 2, 3) end)
            local target = (ok and np ~= nil) and np or V3(pnt[1], wy, pnt[2])
            IPC.vnavmesh.PathfindAndMoveTo(target, false)
            local t = 0
            while IPC.vnavmesh.PathfindInProgress() and t < 10 do Wait(0.1); t = t + 0.1 end
            if first then first = false; Wait(0.4); SpeedUp(target, nil) end
            t = 0
            while IPC.vnavmesh.IsRunning() and not IsDead() and DistanceTo(target) > 3 and t < 30 do
                if found() then IPC.vnavmesh.Stop(); return true end
                RuleOut()
                if best.out then break end   -- in range and not there: re-plan
                Wait(0.25); t = t + 0.25
            end
            if found() then IPC.vnavmesh.Stop(); return true end
            if best.out then break end
            if t >= 30 then LogD("Explore by spots: no progress"); return false end
        end
        best.out = true
    end
    return false
end

-- Visit order from `from` (in room fromRoom), and how many stops to do. Travel between rooms is
-- measured through the doorways along the floor's real exits (`legLen(ax, az, aRoom, stop)`).
-- Each step looks two stops ahead: it picks the next stop of the best pair by (likelihood of
-- both) / (time to do both), so a good stop next to us isn't skipped for a slightly better one
-- farther away.
local function PlanRoute(stops, from, fromRoom, ph, cover, legLen)
    local spy, over = SecsPerYalm(), Overhead()
    local n = #stops
    local used, order = {}, {}
    local px, pz, pr, t = from.X, from.Z, fromRoom, 0
    local function Dt(ax, az, ar, b) return legLen(ax, az, ar, b) * spy + SX.WAIT end
    for step = 1, n do
        local best, bestV = nil, -1
        for i = 1, n do
            if not used[i] then
                local si = stops[i]
                local dti = Dt(px, pz, pr, si)
                local v = si.W / dti
                if step < n then
                    for j = 1, n do
                        if j ~= i and not used[j] then
                            local sj = stops[j]
                            local vij = (si.W + sj.W) / (dti + Dt(si.X, si.Z, si.room, sj))
                            if vij > v then v = vij end
                        end
                    end
                end
                if v > bestV then best, bestV = i, v end
            end
        end
        used[best] = true
        t = t + Dt(px, pz, pr, stops[best])
        px, pz, pr = stops[best].X, stops[best].Z, stops[best].room
        table.insert(order, { stop = stops[best], t = t })
    end
    -- The greedy order above can zigzag (a pair by the exit, a 180 to the far wall,
    -- and back past the pair). Improve it directly on what we're after, hoards per hour with
    -- the best stop count, by reversing segments and moving single stops while that helps.
    -- Leg times between all stops are worked out once (index 0 = where we start).
    local D = {}
    for a = 0, n do
        D[a] = {}
        local ax, az, ar
        if a == 0 then ax, az, ar = from.X, from.Z, fromRoom else ax, az, ar = stops[a].X, stops[a].Z, stops[a].room end
        for b = 1, n do if b ~= a then D[a][b] = Dt(ax, az, ar, stops[b]) end end
    end
    local function Rate(seq)   -- best stop count and its rate for an order (list of stop indexes)
        local bK, bR = 1, -1
        local cumW, eFound, tt, prev = 0, 0, 0, 0
        for k, i in ipairs(seq) do
            tt = tt + D[prev][i]; prev = i
            cumW = cumW + stops[i].W
            eFound = eFound + ph * cover * stops[i].W * tt
            local pk = ph * cover * cumW
            local r = pk / (over + eFound + (1 - pk) * tt)
            if r > bR then bK, bR = k, r end
        end
        return bK, bR
    end
    local idx = {}
    for _, o in ipairs(order) do
        for i = 1, n do if stops[i] == o.stop then table.insert(idx, i); break end end
    end
    local _, greedyRate = Rate(idx)
    local _, cur = Rate(idx)
    local improved, passes = true, 0
    while improved and passes < 30 do
        improved, passes = false, passes + 1
        for i = 1, n - 1 do
            for j = i + 1, n do
                -- 2-opt: reverse idx[i..j]
                local cand = {}
                for q = 1, i - 1 do cand[q] = idx[q] end
                for q = i, j do cand[q] = idx[j - (q - i)] end
                for q = j + 1, n do cand[q] = idx[q] end
                local _, r = Rate(cand)
                if r > cur + 1e-12 then idx, cur, improved = cand, r, true end
                -- move the stop at i to just after j
                cand = {}
                for q = 1, n do if q ~= i then table.insert(cand, idx[q]) end if q == j then table.insert(cand, idx[i]) end end
                _, r = Rate(cand)
                if r > cur + 1e-12 then idx, cur, improved = cand, r, true end
                -- move the stop at j to just before i (e.g. a less likely spot right on the way:
                -- worth the stop if its odds beat the time it costs)
                cand = {}
                for q = 1, n do if q == i then table.insert(cand, idx[j]) end if q ~= j then table.insert(cand, idx[q]) end end
                _, r = Rate(cand)
                if r > cur + 1e-12 then idx, cur, improved = cand, r, true end
            end
        end
    end
    order = {}
    local tt, prev = 0, 0
    for _, i in ipairs(idx) do
        tt = tt + D[prev][i]; prev = i
        table.insert(order, { stop = stops[i], t = tt })
    end
    local bestK, bestRate = Rate(idx)
    return order, bestK, bestRate * 3600, greedyRate * 3600
end

-- Sprint for the move ahead: out of combat only when it's worth it (lasts 20s, 60s cooldown;
-- short hops between neighbouring stops would waste most of it standing at stops); in combat
-- (10s) whenever it's ready.
SX.SPRINT_MIN = 15
local function QuickSprint(trip, inCombat)
    -- Out of combat, not for trips too short to dash either (a dash would overshoot the mark, so
    -- neither fires). trip = true: right after a dash, always.
    if not inCombat and trip ~= true then
        local min = SX.SPRINT_MIN
        local d = CurrentDash()
        if d ~= nil then min = math.max(min, d.range + DASH_MARGIN) end
        if (trip or 0) < min then return end
    end
    if HasStatus(SPRINT_STATUS) == false and ActionReady(3) == true then
        yield('/ac "' .. SPRINT_NAME .. '"')
    end
end

local function SixthFound() return HOH_DISCOVERED or FindObject(HOARD_COFFER_ID) ~= nil end

-- Concealment wears off after ~60s (seen). Its status ID is learned the first time: the
-- status that appears right after using it. Then, when it's gone, the next Concealment is used;
-- if none takes, we're out and the floor ends.
function DD.StatusIds()
    local ids = {}
    pcall(function()
        for st in luanet.each(Svc.Objects.LocalPlayer.StatusList) do
            if st ~= nil and st.StatusId ~= 0 then ids[st.StatusId] = true end
        end
    end)
    collectgarbage("collect")
    collectgarbage("collect")
    return ids
end
DD.concealStatus = nil
SX.LEAVE_SECS = 2         -- to start the leave after the search ends (a direct call, no menu), with a second to spare
SX.RENEW_FOR_PATROL = 15  -- renew early (anywhere) if a patrol is coming and Concealment has less than this left
SX.CONCEAL_ENEMY = 25    -- first Concealment goes on early if an enemy comes this close before the first hallway
SX.RENEW_MARGIN = 5      -- renew Concealment at the last hallway that still reaches the next one with this many
                          -- seconds left (as late as possible: each renewal costs time)
-- Use a Concealment and check it took: a status with ~60s on it appears (or the known one is
-- refreshed). Learns the status ID the first time. Nothing is assumed to be on the save.
SX.MAG_HOLD_HP = 30    -- attacked on the way: magicite at the next stop, unless HP drops under this %
SX.MAG_CONFIRM = 1.0   -- seconds to wait for a magicite's status before sending it again (seen 0.3-0.7s)
-- A status that wasn't in `before` (Sprint aside), or nil.
function DD.NewStatus(before)
    for id in pairs(DD.StatusIds()) do
        if not before[id] and id ~= SPRINT_STATUS then return id end
    end
    return nil
end
-- Potions picked up this macro run (magicite kills drop them): Super-Potion, then
-- Max-Potion. Only ones over the count at the start are used, so your own stock isn't touched.
SX.POTIONS = { 23167, 13637 }   -- Super-Potion, Max-Potion (the log shows their names)
SX.POTION_AT = 50               -- drink when HP is under this % in a fight
SX.potBase = nil                -- counts when the macro started
function DD.ItemCount(id)
    local ok, n = pcall(function() return Inventory.GetItemCount(id) + Inventory.GetHqItemCount(id) end)
    return ok and n or nil
end
function DD.HpPct()
    local ok, v = pcall(function() return Entity.Player.HealthPercent end)
    return ok and v or nil
end
function DD.TryConceal()
    if DDX.PomCount(POM.concealment) == 0 then return false end   -- known: none left
    local before = DD.StatusIds()
    local leftBefore = DD.concealStatus ~= nil and DD.StatusLeft(DD.concealStatus) or nil
    local count = DDX.PomCount(POM.concealment)
    DDX.Use(PomCmd(POM.concealment))
    -- A press during an animation lock (Sprint, a dash) is ignored: if the count hasn't dropped
    -- after 0.75s, press again (two floors lost 5s waiting on an ignored press, then
    -- got caught; it went on as Sprint had just been used).
    local sincePress = 0
    for _ = 1, 6 do
        Wait(0.25); sincePress = sincePress + 0.25
        if DDX.PomCount(POM.concealment) < count then break end
        if sincePress >= 0.75 then
            LogD("Concealment didn't register; pressing again")
            DDX.Use(PomCmd(POM.concealment)); sincePress = 0
        end
    end
    for _ = 1, 12 do   -- up to ~3s more (it showed up ~1.5s after use in renewals)
        if DD.concealStatus ~= nil then
            local l = DD.StatusLeft(DD.concealStatus)
            if l ~= nil and l > 45 and (leftBefore == nil or l > leftBefore + 5) then return true end
        else
            for id in pairs(DD.StatusIds()) do
                if not before[id] and id ~= SPRINT_STATUS and (DD.StatusLeft(id) or 0) > 45 then
                    DD.concealStatus = id
                    LogD("Concealment status: " .. id .. " (" .. (GameText("Status", id, "Name") or "?") .. ")")
                    return true
                end
            end
        end
        Wait(0.25)
    end
    return false
end
function DD.StatusLeft(id)
    local left = nil
    pcall(function()
        for st in luanet.each(Svc.Objects.LocalPlayer.StatusList) do
            if st ~= nil and st.StatusId == id then left = st.RemainingTime; break end
        end
    end)
    collectgarbage("collect")
    collectgarbage("collect")
    return left
end

-- One floor without Intuition. Returns "taken", "none", "aggro" or "died", plus search seconds.
local floorNo = 0
local function AttemptSixth()
    floorNo = floorNo + 1
    local fid = os.date("!%Y-%m-%dT%H:%M:%SZ") .. "#" .. floorNo
    SAFETY_USED = false
    STEALTH = false
    PENDING_CONCEAL = nil
    floorMagicTried = {}
    for k, v in pairs(lastDash) do
        if v == true then lastDash[k] = nil end
    end
    HOH_DISCOVERED = false
    EnterWithSave()
    WaitUntil(function() return InDeepDungeon() and Player.Available and not Player.IsBusy end, 120, "floor load")
    local p0 = Entity.Player.Position
    floorStart = { X = p0.X, Z = p0.Z }
    WaitUntil(DDX.FloorReady, 15, "deep dungeon floor")
    Wait(0.5)

    if V3 == nil then error("Sixth Sense needs vnavmesh positions (System.Numerics.Vector3), which couldn't be loaded") end
    local terr = Territory()
    local data = SixthData(terr)
    if #data.spots == 0 then
        LogI("Sixth Sense: no hoard spots recorded for this floor (territory " .. terr .. "); run normally with RecordSpots first")
        return "none", 0
    end
    -- The floor's layout (from SND): which rooms exist, their exits, our room. Only spots in rooms
    -- that exist and that we can reach count; stops are built from those, weighted by finds.
    local fl = FloorLayout()
    local geo = fl ~= nil and fl.floor ~= nil and fl.floor >= 11 and fl.floor <= 19 and HOH11[fl.tileset] or nil
    if geo == nil then
        LogI("Sixth Sense: no room data for this floor (only HoH floors 11-19 so far); leaving")
        return "none", 0
    end
    if SX.potBase == nil then
        SX.potBase = {}
        for _, id in ipairs(SX.POTIONS) do
            SX.potBase[id] = DD.ItemCount(id) or 0
            LogD(string.format("Potions: %s x%d at the start", tostring(GameText("Item", id, "Name")), SX.potBase[id]))
        end
    end
    if not SX.steelNamed then
        SX.steelNamed = true
        LogD("Pomander " .. POM.steel .. " is " .. tostring(GameText("DeepDungeonItem", POM.steel, "Name")))
    end
    if fl.floor ~= 11 and not SX.warned11 then
        SX.warned11 = true
        LogI("Sixth Sense is made and tested for a floor 11 save (Concealment, magicite, Safety); on floor " .. fl.floor .. " your mileage may vary")
    end
    local flags = {}
    for i = 1, 25 do flags[i] = fl.rooms[i] or 0 end
    local myRoom = (fl.me or -1) + 1
    if myRoom < 1 or flags[myRoom] == 0 then myRoom = DD.Nearest(geo, floorStart.X, floorStart.Z) end
    local roomOf = SpotRooms(data, fl.tileset, geo)
    local cand, roomsHere = {}, 0
    for i = 1, 25 do if flags[i] > 0 then roomsHere = roomsHere + 1 end end
    for _, sp in ipairs(data.spots) do
        local r = roomOf[sp]
        -- Never the room we start in: 0 of 251 hoards were there (~60 expected otherwise).
        if r ~= nil and r ~= myRoom and flags[r] > 0 and DD.Path(flags, myRoom, r) ~= nil then table.insert(cand, sp) end
    end
    if #cand == 0 then
        LogI("Sixth Sense: no known spots in this floor's rooms; leaving")
        return "none", 0
    end
    -- Spot odds on this floor: the hoard's room looks like a uniform pick among the floor's rooms
    -- (that have known spots), then a spot within it by how often it's been found there. Checked
    -- against 251 finds with layouts: scores as well as correcting for how often each room
    -- appears, and better than raw counts.
    local roomTotal, roomList = {}, {}
    for _, sp in ipairs(cand) do
        local r = roomOf[sp]
        if roomTotal[r] == nil then roomTotal[r] = 0; table.insert(roomList, r) end
        roomTotal[r] = roomTotal[r] + sp.N
    end
    local weighted = {}
    for _, sp in ipairs(cand) do
        local r = roomOf[sp]
        table.insert(weighted, { X = sp.X, Y = sp.Y, Z = sp.Z, room = r,
                                 N = 1000 * sp.N / roomTotal[r] / #roomList })
    end
    local stops = BuildStops(weighted)
    for _, st in ipairs(stops) do st.room = st.Spots[1].room end
    -- Doorway waypoints between every pair of rooms on this floor (cached), and leg lengths.
    local wpCache = {}
    local function Waypoints(ra, rb)
        local key = ra * 32 + rb
        if wpCache[key] == nil then wpCache[key] = DD.Waypoints(geo, flags, ra, rb) or false end
        return wpCache[key] or nil
    end
    local function LegLen(ax, az, ar, b)
        local wps = (ar == b.room) and {} or Waypoints(ar, b.room)
        if wps == nil then return 1000 end
        local len, x, z = 0, ax, az
        for _, w in ipairs(wps) do
            len = len + math.sqrt((w[1] - x) ^ 2 + (w[2] - z) ^ 2)
            x, z = w[1], w[2]
        end
        return len + math.sqrt((b.X - x) ^ 2 + (b.Z - z) ^ 2)
    end
    local order, k, rate, greedyRate = PlanRoute(stops, floorStart, myRoom, data.ph, data.cover, LegLen)
    LogD(string.format("Route: model %.1f hoards/h after reordering (greedy order: %.1f)", rate, greedyRate))
    local planW = 0
    for i = 1, k do planW = planW + order[i].stop.W end
    local area = { name = fl.tileset .. ":" .. roomsHere }
    LogI(string.format("Sixth Sense floor %d: tileset %s, %d rooms (%d with known spots), %d spots in them -> plan %d of %d stops (%.0f%% of their hoards, ~%.0fs), model %.1f hoards/h",
        floorNo, fl.tileset, roomsHere, #roomList, #cand, k, #order, 100 * planW, order[k].t, rate))

    -- Protection: only what the Protection setting names; nothing else is assumed to be on the
    -- save (a save has Inferno and no Concealment). Concealment: held for the
    -- first hallway. Magicite isn't stealth: keep it for when something attacks (a hit or two
    -- does little, and clearing enemies then keeps them away longer). Safety now.
    SafetyNow()
    -- Not Concealment in the dropdown: use one anyway out of combat if the save has one.
    if DDX.PomCount(POM.concealment) > 0 then PENDING_CONCEAL = PomCmd(POM.concealment) end
    -- Hold Concealment back for the first hallway (no traps or stationary enemies there, only the
    -- odd patrol): it goes on mid-hallway, so its ~60s start where the search does.
    local heldConceal = PENDING_CONCEAL
    -- Checked by SpeedUp before each dash and before Sprint: an enemy close (or a Namazu coming)
    -- before the first hallway puts the first Concealment on now, before moving faster.
    DDX.concealHook = function()
        if heldConceal == nil or STEALTH or InCombat() then return false end
        local p = Entity.Player.Position
        local near, why = DDX.ThreatNear(p.X, p.Z, SX.CONCEAL_ENEMY)
        if not near then return false end
        LogD("Concealment first: " .. why)
        STEALTH = DD.TryConceal()
        if STEALTH or DDX.PomCount(POM.concealment) == 0 then heldConceal = nil end
        return STEALTH
    end
    PENDING_CONCEAL = nil
    local hallwayDone = false   -- reached the first hallway (Concealment goes on while walking it)
    local inHallway = false     -- walking a hallway right now (passed its midpoint, not at the stop yet)
    HOH_DASH_CHECK = true       -- dashes check for enemies even with Concealment held back
    if not USE_SAFETY then LogI("WARNING: Sixth Sense without Safety: hoard spots are trap spots") end

    local t0 = NowMs()
    local function Secs() return (NowMs() - t0) / 1000 end
    local enemies, events = {}, {}
    table.insert(events, string.format("%s,0.0,layout,%s room %d: %s", fid, fl.tileset, myRoom, table.concat(flags, ";")))
    local combats, magicites = 0, 0
    local function Event(kind, detail)
        table.insert(events, string.format("%s,%.1f,%s,%s", fid, Secs(), kind, detail or ""))
        LogD(string.format("Sixth Sense event %.1fs: %s %s", Secs(), kind, detail or ""))
    end
    -- Enemy tracking: first seen, closest approach, how far each moved (patrols move).
    local function ScanEnemies()
        local me = Entity.Player.Position
        local now = Secs()
        pcall(function()
            for obj in luanet.each(Svc.Objects) do
                if obj ~= nil and string.find(tostring(obj.ObjectKind), "BattleNpc", 1, true)
                   and obj.SubKind == 5 and not obj.IsDead and obj.IsTargetable then
                    local id = tostring(obj.EntityId)
                    local p = obj.Position
                    local d = math.sqrt((p.X - me.X) ^ 2 + (p.Z - me.Z) ^ 2)
                    local e = enemies[id]
                    if e == nil then
                        enemies[id] = { base = obj.BaseId, t = now, x = p.X, z = p.Z, d = d, minD = d, minT = now,
                                        lx = p.X, lz = p.Z, moved = 0, last = now }
                    else
                        e.moved = e.moved + math.sqrt((p.X - e.lx) ^ 2 + (p.Z - e.lz) ^ 2)
                        e.lx, e.lz, e.last = p.X, p.Z, now
                        if d < e.minD then e.minD, e.minT = d, now end
                    end
                end
            end
        end)
        collectgarbage("collect")
        collectgarbage("collect")
    end
    local lastScan = -1
    local baseStatus = DD.StatusIds()
    local concealOn, conceals = nil, 0
    local inCombatSeen = false
    local noConcealLeft = heldConceal == nil   -- this floor: no Concealment to use
    local magiciteGone = false    -- this floor: magicite tried and none worked (none left)
    local mag = { slot = nil, t = 0, dash = false, dashCheck = 0, sprintAfterDash = false, sadT = 0 }   -- magicite in use, dash/Sprint timing
    -- Checks while moving or waiting: returns nil, "found", "died", "aggro" or "unprotected".
    -- Seconds from here to the next hallway point on the planned route, or nil when there isn't
    -- one (then also the seconds to finish the planned stops). Rough: straight lines between the
    -- route's points at the measured walking pace, plus the wait at each stop.
    local function NextHall()
        local R = mag.route
        if R == nil then return nil, 0 end
        local spy = SecsPerYalm()
        local p = Entity.Player.Position
        local x, z, t = p.X, p.Z, 0
        local w = R.wps[R.wi + 1]
        if w ~= nil then return math.sqrt((w[1] - x) ^ 2 + (w[2] - z) ^ 2) * spy, nil end
        local prevRoom = order[R.i].stop.room
        for j = R.i, k do
            local st = order[j].stop
            if j > R.i and st.room ~= prevRoom then
                local w1 = (Waypoints(prevRoom, st.room) or {})[1]
                if w1 ~= nil then return t + math.sqrt((w1[1] - x) ^ 2 + (w1[2] - z) ^ 2) * spy, nil end
            end
            t = t + math.sqrt((st.X - x) ^ 2 + (st.Z - z) ^ 2) * spy + SX.WAIT
            x, z, prevRoom = st.X, st.Z, st.room
        end
        return nil, t
    end
    local function Tick()
        if IsDead() then return "died" end
        if SixthFound() then return "found" end
        -- Last protection running out, and nothing left to get out of a fight with (no
        -- Concealment, no magicite) while stops remain: finish the stop we're headed to only if
        -- there's time to get there, wait there, and start leaving with a second to spare;
        -- otherwise leave now, still concealed (searching on unprotected found 4
        -- hoards in 37 floors and died on 15; a leave, once started, can't be stopped by aggro).
        if STEALTH and DD.concealStatus ~= nil and not InCombat() and mag.stopX ~= nil then
            local left = DD.StatusLeft(DD.concealStatus)
            if left ~= nil and left > 0 and left <= 60 and DDX.PomCount(POM.concealment) == 0
               and DDX.MagCount(0) == 0 and DDX.MagCount(1) == 0 and DDX.MagCount(2) == 0
               and order[k] ~= nil and order[k].t - Secs() > left then
                local p = Entity.Player.Position
                local d = math.sqrt((mag.stopX - p.X) ^ 2 + (mag.stopZ - p.Z) ^ 2)
                local need = d * SecsPerYalm() * 1.3 + SX.WAIT + SX.LEAVE_SECS   -- path ~30% longer than straight
                if left < need then
                    Event("exit", string.format("leaving with %.0fs of Concealment left (the next stop needs ~%.0fs): none left after it, no magicite",
                        left, need))
                    return "unprotected"
                end
            end
        end
        -- A patrol on its way and Concealment due for renewal soon anyway: renew now, while it's
        -- still far off (a Namazu walked into the hallway as Concealment was renewed
        -- there with 8s left; using a pomander drops Concealment for a moment, and it was 3y away).
        if STEALTH and DD.concealStatus ~= nil and not noConcealLeft and not InCombat()
           and Secs() - (mag.patrolScan or -1) >= 0.5 then
            mag.patrolScan = Secs()
            local left = DD.StatusLeft(DD.concealStatus)
            if left ~= nil and left > 0 and left < SX.RENEW_FOR_PATROL then
                local p = Entity.Player.Position
                local near, why = DDX.ThreatNear(p.X, p.Z, 0, true)   -- a patrol walking toward us
                -- ...and nothing close by that the moment without Concealment would wake (an
                -- enemy 6y away did, on an early renewal for a Namazu still 38y off).
                if near and DDX.PomCount(POM.concealment) > 0 and DDX.NoticedAt(DDX.Enemies(), p.X, p.Z) == nil then
                    DDX.Use(PomCmd(POM.concealment))
                    Wait(POM_ANIM_SECONDS)
                    local after = DD.StatusLeft(DD.concealStatus)
                    if after ~= nil and after > left + 10 then
                        concealOn = Secs(); conceals = conceals + 1
                        Event("concealment", string.format("renewed early with %.0fs left: %s", left, why))
                    else
                        Event("concealment", string.format("early renewal didn't take (%.0fs left): %s", left, why))
                    end
                end
            end
        end
        -- Renew early, in a hallway (only the odd patrol there), rather than mid-room when it runs out.
        if inHallway and STEALTH and DD.concealStatus ~= nil and not noConcealLeft and not InCombat() and DDX.PomCount(POM.concealment) == 0 then
            noConcealLeft = true
            Event("concealment", "none left (count)")
        end
        if inHallway and STEALTH and DD.concealStatus ~= nil and not noConcealLeft and not InCombat() then
            local left = DD.StatusLeft(DD.concealStatus)
            -- Renew here only if it wouldn't last to the next hallway with a margin; if this is
            -- the route's last hallway, only if it wouldn't last to the end of the search.
            local renew = false
            if left ~= nil and left > 0 then
                local eta, rest = NextHall()
                if eta ~= nil then renew = left - eta < SX.RENEW_MARGIN else renew = left < rest end
                -- The next one covers the rest of the search anyway: renew here rather than
                -- stretching this one to the last hallway it can reach. Plan time
                -- +15%: floors run a little slower than planned.
                local remaining = order[k] ~= nil and (order[k].t - Secs()) * 1.15 or nil
                if not renew and remaining ~= nil and left < remaining and remaining <= 60 - SX.RENEW_MARGIN then
                    renew = true
                    LogD(string.format("Concealment: %.0fs left, the next one covers the rest (~%.0fs): renewing here", left, remaining))
                end
                if not renew then
                    inHallway = false   -- decided for this hallway
                    LogD(string.format("Concealment: %.0fs left, next hallway in ~%s: no renewal here", left,
                        eta and string.format("%.0fs", eta) or ("none (search ends in ~" .. string.format("%.0fs)", rest))))
                end
            end
            if renew then
                local p = Entity.Player.Position
                local e, nearest = DDX.NoticedAt(DDX.Enemies(), p.X, p.Z)
                if e ~= nil then
                    -- Something would see the moment without Concealment: wait (still in the
                    -- hallway, checked again next time).
                    if not mag.renewHeld then
                        mag.renewHeld = true
                        Event("concealment", string.format("renewal held: %s %.0fy away (%.0fs left)", e.name, nearest or 0, left))
                    end
                    renew = false
                end
            end
            if renew then
                mag.renewHeld = nil
                inHallway = false
                DDX.Use(PomCmd(POM.concealment))
                Wait(POM_ANIM_SECONDS)
                local after = DD.StatusLeft(DD.concealStatus)
                if after ~= nil and after > left + 10 then
                    concealOn = Secs(); conceals = conceals + 1
                    Event("concealment", string.format("renewed in a hallway with %.0fs left (now %.0fs)", left, after))
                elseif DDX.PomCount(POM.concealment) == 0 then
                    noConcealLeft = true
                    Event("concealment", string.format("none left (tried with %.0fs left)", left))
                else
                    Event("concealment", string.format("renewal didn't take (%.0fs left, still have one)", left))
                end
            end
        end
        -- First Concealment: in the first hallway, or right away if an enemy comes within
        -- SX.CONCEAL_ENEMY yalms first (better a second less of it than being caught
        -- as it goes on: 5 of 60 floors were).
        local enemyNear = false
        if heldConceal ~= nil and not hallwayDone and Secs() - (mag.concealScan or -1) >= 0.5 then
            mag.concealScan = Secs()
            local p = Entity.Player.Position
            local why
            enemyNear, why = DDX.ThreatNear(p.X, p.Z, SX.CONCEAL_ENEMY)
            if enemyNear then LogD("Concealment now: " .. why) end
        end
        if heldConceal ~= nil and (hallwayDone or enemyNear or Secs() > 15) and not InCombat() then
            LogD(string.format("Protection: Pomander of Concealment (first hallway, %.1fs)", Secs()))
            mag.concealTries = (mag.concealTries or 0) + 1
            if mag.concealTries >= 3 then heldConceal = nil end   -- last try either way
            STEALTH = DD.TryConceal()
            if STEALTH then
                heldConceal = nil
            elseif DDX.PomCount(POM.concealment) == 0 then
                heldConceal = nil
                noConcealLeft = true
                Event("concealment", "none on the save, searching on (magicite if attacked)")
            else
                -- Still have it: it didn't take (caught as it went on: 5 of 60 floors, all in a
                -- fight that same second). Keep it for when we're out of combat again.
                Event("concealment", InCombat() and "didn't take: caught as it went on" or "didn't take; will try again")
            end
        end
        if STEALTH then
            if DD.concealStatus == nil then
                for id in pairs(DD.StatusIds()) do
                    -- Concealment lasts 60s: a combat status that came and went (The Heat of Battle,
                    -- seen on a save) isn't it.
                    if not baseStatus[id] and id ~= SPRINT_STATUS and (DD.StatusLeft(id) or 0) > 45 then
                        DD.concealStatus = id
                        LogD("Concealment status: " .. id .. " (" .. (GameText("Status", id, "Name") or "?") .. ")")
                        break
                    end
                end
            end
            if DD.concealStatus ~= nil then
                local on = HasStatus(DD.concealStatus)
                if on and concealOn == nil then concealOn = Secs(); conceals = conceals + 1; Event("concealment", "on") end
                if on == false and concealOn ~= nil and not InCombat() then
                    Event("concealment", string.format("wore off after %.1fs", Secs() - concealOn))
                    concealOn = nil
                    if not noConcealLeft and DDX.PomCount(POM.concealment) == 0 then noConcealLeft = true end
                    local had = DDX.PomCount(POM.concealment)
                    -- Pressed again each second: a press during an animation lock is ignored.
                    local t = 0
                    while not noConcealLeft and t < 3 and not HasStatus(DD.concealStatus) do
                        if t % 1 == 0 then DDX.Use(PomCmd(POM.concealment)) end
                        Wait(0.25); t = t + 0.25
                    end
                    if HasStatus(DD.concealStatus) then
                        concealOn = Secs(); conceals = conceals + 1
                        Event("concealment", "renewed")
                        Wait(math.max(0, POM_ANIM_SECONDS - t))
                    else
                        STEALTH = false
                        -- Keep searching; if something attacks, magicites.
                        noConcealLeft = true
                        Event("concealment", had > 0 and ("renewal didn't take (had " .. had .. "); searching on (magicite if attacked)")
                            or "ran out, none left; searching on (magicite if attacked)")
                    end
                end
            end
        end
        if Secs() - lastScan >= 0.5 then ScanEnemies(); lastScan = Secs() end
        -- In combat: keep searching whatever happens (any hoard found first is a free one). With
        -- magicite left, use the next slot without stopping; it worked if combat ends within
        -- MAGICITE_WAIT. Without, there's no normal way out but dying (HeyKupo prefers that to SND's
        -- forced leave). (Seen stopping made it stand and wait; HeyKupo: keep moving, magicite or no.)
        if InCombat() then
            if not inCombatSeen then
                inCombatSeen = true
                mag.combatT = Secs()
                combats = combats + 1
                local _, near = EnemiesNear(Entity.Player.Position.X, Entity.Player.Position.Z, 0)
                Event("combat", string.format("nearest %.0fy, concealed %s, searching on; status: %s", near or -1, tostring(STEALTH), (StatusNames():gsub(",", ";"))))
                STEALTH = false
                concealOn = nil
            end
            if mag.slot ~= nil and mag.worked == nil then
                -- A magicite that fires puts a status on you within ~0.7s (Primal Rage, 1567, for
                -- Inferno; seen); an empty slot puts nothing. The command can also be lost
                -- (animation lock): send it again, up to 3 times, before calling the slot empty.
                local new = DD.NewStatus(mag.before)
                if new ~= nil then
                    mag.worked = mag.slot
                    magicites = magicites + 1
                    Event("magicite", string.format("slot %d fired: %s after %.1fs", mag.slot, GameText("Status", new, "Name") or tostring(new), Secs() - mag.t0))
                elseif Secs() - mag.t >= SX.MAG_CONFIRM then
                    if mag.tries < 3 then
                        mag.tries = mag.tries + 1; mag.t = Secs()
                        DDX.Use("/callback DeepDungeonStatus true 12 " .. mag.slot)
                    else
                        Event("magicite", string.format("slot %d: nothing after 3 tries (%.1fs), empty", mag.slot, Secs() - mag.t0))
                        mag.slot = nil
                    end
                end
            elseif mag.worked ~= nil and Secs() - mag.t0 > 12 then
                mag.slot, mag.worked = nil, nil   -- fired, but a fight is still on well after: next slot
            end
            -- Attacked on the way to a stop: keep going and use the magicite there (it stops you;
            -- a few hits don't matter, so always run to the stop first). Only an HP
            -- emergency uses it on the way.
            local holdMag = false
            if mag.stopX ~= nil then
                local p = Entity.Player.Position
                local dStop = math.sqrt((p.X - mag.stopX) ^ 2 + (p.Z - mag.stopZ) ^ 2)
                holdMag = dStop > 2.5 and (DD.HpPct() or 100) >= SX.MAG_HOLD_HP
            end
            if not magiciteGone and mag.slot == nil and not IsDead() and not holdMag then
                local slot = nil
                for s = 0, 2 do
                    if not floorMagicTried[s] and DDX.MagCount(s) > 0 then slot = s; break end
                end
                if slot == nil then
                    magiciteGone = true
                    Event("magicite", "none left, searching on until it ends or we die")
                else
                    floorMagicTried[slot] = true
                    mag.slot = slot; mag.t = Secs(); mag.t0 = mag.t
                    mag.tries = 1; mag.worked = nil; mag.before = DD.StatusIds()
                    DDX.Use("/callback DeepDungeonStatus true 12 " .. slot)
                    Event("magicite", "slot " .. slot .. " used, moving on")
                    mag.dash = true   -- PCT: Smudge right away; done on the move in Go
                end
            end
            -- No magicite to the rescue: Pomander of Steel, once per floor, if the save has one
            --. Checked like a magicite: a new status = it took; sent twice at most.
            if magiciteGone and not floorMagicTried.steel and not IsDead() and DDX.PomCount(POM.steel) > 0 then
                floorMagicTried.steel = true
                mag.steel = { before = DD.StatusIds(), t = Secs(), tries = 1 }
                DDX.Use(PomCmd(POM.steel))
            elseif mag.steel ~= nil then
                local new = DD.NewStatus(mag.steel.before)
                if new ~= nil then
                    Event("steel", "on: " .. (GameText("Status", new, "Name") or tostring(new)))
                    mag.steel = nil
                elseif Secs() - mag.steel.t >= 2.5 then
                    if mag.steel.tries < 2 then
                        mag.steel.tries = 2; mag.steel.t = Secs()
                        DDX.Use(PomCmd(POM.steel))
                    else
                        Event("steel", "nothing: none on the save")
                        mag.steel = nil
                    end
                end
            end
            -- A picked-up potion when HP is low, to keep searching longer (recast 75s; checked it
            -- was used, else tried again).
            if mag.pot ~= nil and Secs() - mag.pot.t >= 2 and Secs() < mag.potNext then
                if (DD.ItemCount(mag.pot.id) or 0) >= mag.pot.n then mag.potNext = Secs() end   -- not used: try again
                mag.pot = nil
            end
            if Secs() >= (mag.potNext or 0) and not IsDead() then
                local hp = DD.HpPct()
                if hp ~= nil and hp < SX.POTION_AT then
                    for _, id in ipairs(SX.POTIONS) do
                        local n = DD.ItemCount(id)
                        if n ~= nil and n > (SX.potBase[id] or n) then
                            pcall(function() Inventory.GetInventoryItem(id):Use() end)
                            mag.pot = { id = id, n = n, t = Secs() }
                            mag.potNext = Secs() + 75
                            Event("potion", string.format("%s at %.0f%% HP (%d picked up)", tostring(GameText("Item", id, "Name") or id), hp, n - SX.potBase[id]))
                            break
                        end
                    end
                end
            end
            if not mag.sprintAfterDash then QuickSprint(0, true) end   -- in combat: Sprint whenever it's ready (after a ready dash)
            return nil
        elseif inCombatSeen then
            inCombatSeen = false
            Event("combat", "over")
            mag.dash = false
            if mag.slot ~= nil then
                if mag.worked == nil then   -- combat ended before the status showed: count it as worked
                    magicites = magicites + 1
                end
                Event("magicite", string.format("slot %d: combat over %.1fs after it", mag.slot, Secs() - mag.t0))
                mag.slot, mag.worked = nil, nil
                -- After a magicite, enemies start appearing at random, so Concealment is more likely
                -- to be caught going on than anywhere. Concealment always comes first;
                -- a second one after the magicite only if one was already used and there's another.
                heldConceal = nil
                if conceals > 0 and not noConcealLeft and DDX.PomCount(POM.concealment) > 0 and not IsDead() then
                    STEALTH = DD.TryConceal()
                    if STEALTH then
                        concealOn = Secs(); conceals = conceals + 1
                        Event("concealment", "second one after the magicite")
                    else
                        Event("concealment", "after the magicite: didn't take")
                    end
                end
                if SixthFound() then return "found" end
            end
        end
        return nil
    end

    local function Go(target, first, trip)
        local lt0 = NowMs()
        local from = Entity.Player.Position
        local straight = math.sqrt((target.X - from.X) ^ 2 + (target.Z - from.Z) ^ 2)
        IPC.vnavmesh.PathfindAndMoveTo(target, false)
        local t = 0
        while IPC.vnavmesh.PathfindInProgress() and t < 10 do Wait(0.1); t = t + 0.1 end
        if first then
            Wait(0.4)
            SpeedUp(target, nil)
        elseif (InCombat() or (not STEALTH and heldConceal == nil)) and (trip or straight) >= SX.SPRINT_MIN then
            -- No Concealment to break (none, it ran out, or we're in combat): dash freely, then
            -- Sprint. If the dash is ready, Sprint waits for it (dash first, then
            -- Sprint); the dash goes as soon as we face along the path and it won't hit a wall.
            local d = CurrentDash()
            if d ~= nil and ActionReady(d.id) == true and DistanceTo(target) >= d.range + DASH_MARGIN then
                mag.sprintAfterDash, mag.sadT = true, Secs()
            else
                QuickSprint(trip or straight, InCombat())
            end
        else
            QuickSprint(trip or straight, InCombat())
        end
        local stuck = StuckWatcher(target)
        local tt = 0
        while IPC.vnavmesh.IsRunning() do
            Wait(0.25); tt = tt + 0.25
            local r = Tick()
            if r ~= nil then IPC.vnavmesh.Stop(); return r, straight, 0 end
            -- Dash mid-leg too, as soon as it comes up (it only tried at the start of a
            -- leg, so a dash on recast then stayed unused for the whole leg). Allowed when there's
            -- no Concealment to break (none on, none about to go on) or in combat; right after a
            -- magicite counts as combat. No enemy check here, as for the free dashes at leg start.
            if Secs() - (mag.dashCheck or 0) >= (mag.sprintAfterDash and 0.2 or 0.5) and (InCombat() or (not STEALTH and heldConceal == nil)) then
                mag.dashCheck = Secs()
                local d = CurrentDash()
                if d ~= nil and DistanceTo(target) >= d.range + DASH_MARGIN and ActionReady(d.id) == true
                   and LandingOnMesh(d.range) ~= false then
                    yield('/ac "' .. d.action .. '"')
                    lastDash[d.action] = Now() or true
                    Event("dash", d.action .. (mag.dash and " after magicite" or " mid-leg") .. string.format(" (%.0fy to go)", DistanceTo(target)))
                    mag.dash = false
                    Wait(0.9)
                    Repath(target, "after " .. d.action)
                    if mag.sprintAfterDash then
                        mag.sprintAfterDash = false
                        QuickSprint(true, InCombat())
                    end
                end
            end
            -- The dash didn't get a chance (facing a wall, etc.): don't hold Sprint any longer.
            if mag.sprintAfterDash and Secs() - mag.sadT > 2 then
                mag.sprintAfterDash = false
                QuickSprint(true, InCombat())
            end
            local n, spent = stuck(0.25)
            tt = tt + spent
            if n >= 2 then IPC.vnavmesh.Stop(); Event("stuck", string.format("%.0f,%.0f", target.X, target.Z)); return "stuck", straight, 0 end
            if tt > 60 then IPC.vnavmesh.Stop(); return "timeout", straight, 0 end
            if Secs() > SX.MAX_SECONDS then IPC.vnavmesh.Stop(); return "timeout", straight, 0 end
        end
        local legSecs = (NowMs() - lt0) / 1000
        if not first and straight > 5 then est.legT = est.legT + legSecs; est.legD = est.legD + straight end
        return "arrived", straight, legSecs
    end

    local function WaitHere(secs)
        local t = 0
        while t < secs do
            local r = Tick()
            if r ~= nil then return r end
            Wait(0.2); t = t + 0.2
        end
        return nil
    end

    local result, foundRank, stopsDone, coveredW, distance = "none", nil, 0, 0, 0
    local curRoom, firstMove = myRoom, true
    for i = 1, #order do
        -- Past the planned stops only in a fight we can't leave (pushing on out of
        -- combat wasn't better than stopping after the planned stops).
        if i > k and not inCombatSeen then break end
        local st = order[i].stop
        mag.stopX, mag.stopZ = st.X, st.Z   -- where we're headed (magicite timing)
        local target = V3(st.X, st.Y, st.Z)
        local ok, pt = pcall(function() return IPC.vnavmesh.NearestPoint(V3(st.X, st.Y, st.Z), 1.5, 3) end)
        if ok and pt ~= nil then
            local far = 0
            for _, s in ipairs(st.Spots) do
                far = math.max(far, math.sqrt((s.X - pt.X) ^ 2 + (s.Z - pt.Z) ^ 2))
            end
            if far <= SX.COVER + 0.05 then target = pt end
        end
        local arriveAt = Secs()
        local r, straight, legSecs = nil, 0, 0
        -- Through the doorways first when the stop is in another room.
        if st.room ~= curRoom then
            local wps = Waypoints(curRoom, st.room) or {}
            -- Which waypoints start a hallway: the first doorway point of each room-to-room hop
            -- (a hop has 1-2 points: this room's doorway, the next room's).
            local hallStart = {}
            do
                local path = DD.Path(flags, curRoom, st.room) or {}
                local idx, cur = 1, curRoom
                for _, nb in ipairs(path) do
                    hallStart[idx] = true
                    idx = idx + #DD.Door(geo, cur, nb)
                    cur = nb
                end
            end
            local here0 = Entity.Player.Position
            local tripLen = LegLen(here0.X, here0.Z, curRoom, st)
            for wi, w in ipairs(wps) do
                local wy = Entity.Player.Position.Y
                local okw, wp = pcall(function() return IPC.vnavmesh.NearestPoint(V3(w[1], wy, w[2]), 2, 3) end)
                local wr, ws = Go((okw and wp) or V3(w[1], wy, w[2]), firstMove, tripLen)
                firstMove = false
                inHallway = false
                straight = straight + (ws or 0)
                if wr ~= "arrived" then r = wr; break end
                mag.route = { i = i, wps = wps, wi = wi }
                -- At a hallway's start: Concealment (first one, or an early renewal) goes on
                -- during the next move, while walking the hallway.
                if hallStart[wi] then hallwayDone = true; inHallway = true end
            end
            -- (was cleared here, so a one-hop trip, the usual case, never got to decide on a
            -- renewal: the walk from the hallway point to the stop is where that happens.)
        end
        if r == nil then
            local gr, gs, gl = Go(target, firstMove)
            firstMove = false
            r, straight, legSecs = gr, straight + (gs or 0), gl
        end
        inHallway = false
        if r == "arrived" then curRoom = st.room end
        distance = distance + straight
        -- Step closer to any covered spot we're not within reach of.
        local stopFar = 0
        if r == "arrived" or r == "stuck" or r == "timeout" then
            for _, s in ipairs(st.Spots) do
                local me = Entity.Player.Position
                local d = math.sqrt((s.X - me.X) ^ 2 + (s.Z - me.Z) ^ 2)
                if d > SX.SHUFFLE and r == "arrived" then
                    local r2 = Go(V3(s.X, s.Y, s.Z), false)
                    if r2 ~= "arrived" then r = r2; break end
                    me = Entity.Player.Position
                    d = math.sqrt((s.X - me.X) ^ 2 + (s.Z - me.Z) ^ 2)
                end
                stopFar = math.max(stopFar, d)
            end
        end
        local waitStart = Secs()
        if r == "arrived" then r = WaitHere(SX.WAIT) or "empty" end
        stopsDone = i
        if r ~= "found" and r ~= "died" and r ~= "aggro" and r ~= "unprotected" then coveredW = coveredW + st.W end
        AppendCsv(SX.STOPS_FILE, "floor,order,x,z,weight,spots,arrive_s,leg_s,straight_y,farthest_spot_y,waited_s,result",
            string.format("%s,%d,%.2f,%.2f,%.4f,%d,%.1f,%.1f,%.1f,%.2f,%.1f,%s", fid, i, st.X, st.Z, st.W, #st.Spots,
                arriveAt, legSecs or 0, straight or 0, stopFar, Secs() - waitStart, r))
        if r == "found" then result = "taken"; foundRank = i; break end
        if r == "died" then result = "died"; break end
        if r == "aggro" then result = "aggro"; break end
        if r == "unprotected" then result = "unprotected"; break end
        if Secs() > SX.MAX_SECONDS then Event("timeout", "floor time limit"); break end
    end

    -- Confirm the discovery like normal runs: the chat line, or a few seconds after the coffer.
    local foundAt = nil
    if result == "taken" then
        local t = 0
        while not HOH_DISCOVERED and t < DISCOVER_CHAT_WAIT do Wait(0.25); t = t + 0.25 end
        local c = FindObject(HOARD_COFFER_ID)
        if c ~= nil then foundAt = { X = c.Position.X, Z = c.Position.Z } end
        local known = false
        if foundAt ~= nil then
            for _, sp in ipairs(data.spots) do
                if (sp.X - foundAt.X) ^ 2 + (sp.Z - foundAt.Z) ^ 2 < SPOT_SAME_DIST ^ 2 then known = true; break end
            end
            if not known then LogI(string.format("Sixth Sense: hoard at a spot NOT in the list (%.2f, %.2f)", foundAt.X, foundAt.Z)) end
        end
        Event("found", foundAt and string.format("%.2f %.2f%s", foundAt.X, foundAt.Z, known and "" or " NEW") or "")
        -- The game confirms a find a moment after you're in range, usually once we've left for the
        -- next stop (27 of 27). Credit the stop the hoard is actually at.
        if foundRank ~= nil then
            if foundAt ~= nil then
                local best, bestD = foundRank, nil
                for j = 1, foundRank do
                    local sj = order[j].stop
                    local d = (sj.X - foundAt.X) ^ 2 + (sj.Z - foundAt.Z) ^ 2
                    if bestD == nil or d < bestD then best, bestD = j, d end
                end
                foundRank = best
            elseif foundRank > 1 then
                foundRank = foundRank - 1
            end
        end
    end
    if result ~= "died" and InCombat() then TryMagicite() end   -- rule 1: so the normal leave works

    local secs = Secs()
    ScanEnemies()
    for id, e in pairs(enemies) do
        AppendCsv(SX.ENEMIES_FILE, "floor,id,base,first_s,first_x,first_z,first_dist,closest,closest_s,moved,last_s",
            string.format("%s,%s,%s,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f", fid, id, tostring(e.base), e.t, e.x, e.z, e.d,
                e.minD, e.minT, e.moved, e.last))
    end
    for _, line in ipairs(events) do AppendCsv(SX.EVENTS_FILE, "floor,t_s,event,detail", line) end
    AppendCsv(SX.FLOORS_FILE,
        "floor,territory,area,start_x,start_z,protection,safety,planned_stops,planned_share,model_per_h,stops_done,share_checked,search_s,straight_y,result,found_rank,found_x,found_z,combats,magicite,secs_per_y,overhead_s",
        string.format("%s,%d,%s,%.1f,%.1f,%s,%s,%d,%.4f,%.2f,%d,%.4f,%.1f,%.0f,%s,%s,%s,%s,%d,%d,%.3f,%.1f",
            fid, terr, area.name, floorStart.X, floorStart.Z, PROTECTION_CHOICE, tostring(USE_SAFETY), k, planW, rate,
            stopsDone, coveredW, secs, distance, result, tostring(foundRank or ""),
            foundAt and string.format("%.2f", foundAt.X) or "", foundAt and string.format("%.2f", foundAt.Z) or "",
            combats, magicites, SecsPerYalm(), Overhead()))
    LogI(string.format("Sixth Sense floor %d: %s after %d stops, %.0fs%s", floorNo,
        result == "taken" and "HOARD" or result, stopsDone, secs,
        combats > 0 and string.format(" (%d combat, %d magicite)", combats, magicites) or ""))
    return result, secs
end

-- ============================================================
-- Main
-- ============================================================
local hoards, missed, unseen, deaths = 0, 0, 0, 0
LogD("Landing check (vnavmesh): " .. (V3 ~= nil and "available" or "unavailable") .. ", normal leave: " .. (EventFramework ~= nil and "available" or "unavailable"))
LogI(string.format("Starting: %s runs, save file %d", MAX_RUNS == math.huge and "unlimited" or tostring(MAX_RUNS), SAVE_SLOT))
if RECORD_SPOTS then LogSpotStats("Spot log: ") end
LogTally("Run tally: ")
if SIXTH then
    LogI(string.format("Sixth Sense ON: no Intuition; protection %s, Safety %s; combat check: %s",
        PROTECTION_CHOICE, tostring(USE_SAFETY),
        (function() local ok, v = pcall(function() return tostring(Svc.Objects.LocalPlayer.StatusFlags) end) return ok and v or "unavailable" end)()))
end
local lastRunStart, lastSearch = nil, 0
for i = 1, MAX_RUNS do
    -- Sixth Sense: how long a floor takes apart from the search (enter, pomanders, leave, wait).
    local runStart = NowMs()
    if SIXTH and lastRunStart ~= nil then
        local over = (runStart - lastRunStart) / 1000 - lastSearch
        if over > 5 and over < 120 then est.overT = est.overT + over; est.overN = est.overN + 1 end
    end
    lastRunStart = runStart
    local result
    if SIXTH then result, lastSearch = AttemptSixth() else result = Attempt() end
    local terr = Territory()
    local tallyTerr = SIXTH and terr + SX.TALLY_OFFSET or terr
    -- Count the run right away (Attempt returns the moment the hoard is discovered), so stopping
    -- the script during the leave doesn't leave a discovery the game counted but the tally didn't.
    local diedInRun = IsDead()
    CountRun(tallyTerr, SIXTH and (result == "taken" and "taken" or "none") or result, diedInRun)
    if result == "taken" then hoards = hoards + 1 elseif result == "missed" then missed = missed + 1 elseif result == "unseen" then unseen = unseen + 1 end
    if not SIXTH then NormalCombatCheck() end   -- rule 1: end combat so the normal leave works
    local died = LeaveDuty()
    if died then
        deaths = deaths + 1
        if not diedInRun then CountDeath(tallyTerr) end
        if result == "taken" then LogI("Died after discovering the hoard (it still counts)") end
    end
    LogI(string.format("Run %d done, hoards taken: %d, missed: %d, sensed-not-found: %d, deaths: %d", i, hoards, missed, unseen, deaths))
    local goal = SIXTH and "sixth" or "normal"
    if HOH_EARNED[goal] then
        LogI("Earned " .. GOAL_ACHIEVEMENT[goal] .. ": stopping")
        break
    end
    Wait(3)
end
if RECORD_SPOTS then LogSpotStats("Spot log: ") end
LogTally("Run tally: ")
LogI(string.format("Finished: %d hoards taken, %d missed, %d sensed-not-found, %d deaths", hoards, missed, unseen, deaths))
collectgarbage("collect")
collectgarbage("collect")
end
