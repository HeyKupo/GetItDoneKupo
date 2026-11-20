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
LogD(string.format("Matching chat: hoard = \"%s\", no hoard = \"%s\", discovered = \"%s\"", SENSE_YES, SENSE_NO, DISCOVERED))
HOH_DISCOVERED = false

-- Called by the macro's OnChatMessage (SND only hooks trigger functions written in the macro).
function HoH_OnChat(msg)
    if type(msg) ~= "string" then return end
    if string.find(msg, SENSE_NO, 1, true) then HOH_SENSE = "no"
    elseif string.find(msg, SENSE_YES, 1, true) then HOH_SENSE = "yes"
    elseif string.find(msg, DISCOVERED, 1, true) then HOH_DISCOVERED = true end
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

local MAX_RUNS         = CfgInt("Runs", 30000)   -- stop after this many entries
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
-- Callback commands for the two deep dungeon windows (both tested by hand 2026-11-17).
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
local POM = { safety = 1, intuition = 14, concealment = 18, petrification = 19 }

local function PomCmd(id) return "/callback DeepDungeonStatus true 11 " .. id end

local function UseIntuition()
    yield(PomCmd(POM.intuition))
end

-- What to use before running to the hoard (setting "Protection").
-- Magicite: code 12 + magicite slot (Inferno 0 tested; Crag 1 / Vortex 2 assumed).
-- Pomanders: code 11 + pomander ID (above).
local PROTECTION = {
    ["Inferno magicite"]          = { cmd = "/callback DeepDungeonStatus true 12 0", wait = 4 },
    ["Crag magicite"]             = { cmd = "/callback DeepDungeonStatus true 12 1", wait = 4 },
    ["Vortex magicite"]           = { cmd = "/callback DeepDungeonStatus true 12 2", wait = 4 },
    ["Pomander of Concealment"]   = POM.concealment and { cmd = PomCmd(POM.concealment), wait = 2.5, stealth = true } or nil,
    ["Pomander of Petrification"] = POM.petrification and { cmd = PomCmd(POM.petrification), wait = 2.5 } or nil,
}

local function CfgString(name, fallback)
    local ok, v = pcall(function() return Config.Get(name, fallback) end)
    if ok and type(v) == "string" and v ~= "" then return v end
    return fallback
end

local PROTECTION_CHOICE = CfgString("Protection", "Inferno magicite")
local USE_SAFETY        = CfgBool("Safety", false)

-- Pomander of Safety (ID 1): removes the floor's traps. Only used on floors with a hoard.
-- Used while running to the hoard (pomanders work on the move), so no wait afterwards.
local SAFETY_USED = false   -- reset at the start of each run; Safety once per floor
local STEALTH = false       -- true after Concealment: no abilities (dashes) or pomanders; Sprint is fine
local PENDING_CONCEAL = nil -- Concealment command to use on the move, right after dash + Sprint
local function UseSafety()
    if not USE_SAFETY or SAFETY_USED or STEALTH then return end
    SAFETY_USED = true
    LogD("Safety")
    yield(PomCmd(POM.safety))
end

-- Protection, then Safety, both before we start moving. Concealment is the exception: it's
-- cancelled by abilities and other pomanders (not Sprint), so it's only queued here and used
-- on the move after any dashes (see SpeedUp).
local function SafetyNow()
    if USE_SAFETY and not SAFETY_USED and not STEALTH then
        UseSafety()
        yield("/wait 2.5")   -- pomander animation lock
    end
end

local function UseProtection()
    local p = PROTECTION[PROTECTION_CHOICE]
    if p == nil then
        if PROTECTION_CHOICE ~= "None" then
            LogI("WARNING: Protection '" .. PROTECTION_CHOICE .. "' isn't available, running without it")
        end
    elseif p.stealth then
        PENDING_CONCEAL = p.cmd
    else
        LogD("Protection: " .. PROTECTION_CHOICE)
        yield(p.cmd)
        yield("/wait " .. p.wait)
    end
    SafetyNow()
end

-- ============================================================
-- Helpers
-- ============================================================
local function Wait(sec) yield("/wait " .. sec) end

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

local DASH_CHOICE = CfgString("Dash", "Auto (by job)")

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
        yield(PENDING_CONCEAL)
        PENDING_CONCEAL = nil
        STEALTH = true
        Wait(POM_ANIM_SECONDS)
        return true
    elseif USE_SAFETY and not SAFETY_USED and not STEALTH then
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

-- Watches for being stuck on something while vnavmesh thinks we're moving: if we've moved
-- less than half a yalm in 1.5s, plan a new path. Call the returned function every `dt` seconds.
local function StuckWatcher(target)
    local lastX, lastZ, still = nil, nil, 0
    return function(dt)
        local p = Entity.Player.Position
        if lastX ~= nil and (p.X - lastX) ^ 2 + (p.Z - lastZ) ^ 2 < 0.25 then
            still = still + dt
        else
            still = 0
        end
        lastX, lastZ = p.X, p.Z
        if still >= 1.5 and IPC.vnavmesh.IsRunning() then
            Repath(target, "stuck")
            still = 0
        end
    end
end

-- On the way: dash (if the job has one, it's ready, the destination is far enough, and it won't
-- land in a wall), any extra dash charges, the on-the-move pomander, then Sprint.
-- Call once movement has started.
local function SpeedUp(target, hoard)
    local d = CurrentDash()
    if STEALTH and d ~= nil then
        LogD("Concealed: no dash")
        d = nil
    end

    -- With Concealment coming, don't dash near enemies (around us or where we'd land).
    local function SafeToDash()
        if PENDING_CONCEAL == nil then return true end
        local x, y, z, fx, fz = PosAndFacing()
        local n1, near1 = EnemiesNear(x, z, ENEMY_DASH_RADIUS)
        local n2, near2 = 0, nil
        if fx ~= nil then n2, near2 = EnemiesNear(x + fx * d.range, z + fz * d.range, ENEMY_DASH_RADIUS) end
        local nearest = near1
        if near2 ~= nil and (nearest == nil or near2 < nearest) then nearest = near2 end
        if n1 + n2 > 0 then
            LogD(string.format("%s skipped: enemy within %dy (nearest %.0fy)", d.action, ENEMY_DASH_RADIUS, nearest))
            return false
        end
        LogD("Enemy check: nearest " .. (nearest and string.format("%.0fy", nearest) or "none seen"))
        return true
    end

    -- Returns "dashed", "wait" (not ready / would hit a wall, try again shortly), or "stop".
    local function TryDash(isFirst)
        if DistanceTo(target) < d.range + DASH_MARGIN then return "stop" end
        local ready, status = ActionReady(d.id)
        if ready == nil then ready = (not isFirst) or DashReady(d) end   -- no game check: old behaviour
        if not ready then return "wait", "not ready (status " .. tostring(status) .. ")" end
        if LandingOnMesh(d.range) == false then return "wait", "would land in a wall" end
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

local function MoveTo(pos)
    IPC.vnavmesh.PathfindAndMoveTo(pos, false)
    -- wait for the path to be computed and movement to begin, so we're facing along the path
    WaitUntil(function() return not IPC.vnavmesh.PathfindInProgress() end, 30, "pathfinding to hoard")
    Wait(0.4)
    SpeedUp(pos, pos)
    local stuck = StuckWatcher(pos)
    local t = 0
    while IPC.vnavmesh.IsRunning() and not IsDead() do
        Wait(0.25); t = t + 0.25
        stuck(0.25)
        TimerTick()
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
        while IPC.vnavmesh.IsRunning() and t < EXPLORE_SECONDS do
            Wait(0.5); t = t + 0.5
            if IsDead() then IPC.vnavmesh.Stop(); return nil end
            stuck(0.5)
            AddTrail()
            marker = FindObject(HOARD_MARKER_ID)
            if marker ~= nil then
                IPC.vnavmesh.Stop()
                return marker
            end
        end
        -- Count the target itself as visited, even if there was no path to it.
        table.insert(trail, { X = target.X, Z = target.Z })
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

local function Territory()
    local ok, t = pcall(function() return Svc.ClientState.TerritoryType end)
    return ok and t or 0
end

local function AddFindTo(spots, terr, x, y, z, n)
    for _, sp in ipairs(spots) do
        if sp.T == terr and (sp.X - x) ^ 2 + (sp.Z - z) ^ 2 < SPOT_SAME_DIST ^ 2 then
            local total = sp.N + n
            sp.X = sp.X + (x - sp.X) * n / total
            sp.Y = sp.Y + (y - sp.Y) * n / total
            sp.Z = sp.Z + (z - sp.Z) * n / total
            sp.N = total
            return
        end
    end
    table.insert(spots, { T = terr, X = x, Y = y, Z = z, N = n })
end

-- Reads the spot file: list of {T, X, Y, Z, N}. Also reads the older one-line-per-find format
-- (time,territory,x,y,z,startX,startZ) and folds it into spots.
local oldFinds = {}   -- old-format lines seen while loading (copied into the raw finds log once)

local function LoadSpots()
    local spots = {}
    oldFinds = {}
    local f = io.open(SPOTS_FILE, "r")
    if f == nil then return spots end
    for line in f:lines() do
        local t, x, y, z, n = line:match("^(%d+),([%-%d%.]+),([%-%d%.]+),([%-%d%.]+),(%d+)%s*$")
        if t ~= nil then
            AddFindTo(spots, tonumber(t), tonumber(x), tonumber(y), tonumber(z), tonumber(n))
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

-- Writes to a temporary file first, then swaps it in, so a crash mid-write can't wipe the list.
local function SaveSpots(spots)
    table.sort(spots, function(a, b)
        if a.T ~= b.T then return a.T < b.T end
        if a.X ~= b.X then return a.X < b.X end
        return a.Z < b.Z
    end)
    local tmp = SPOTS_FILE .. ".tmp"
    local f = io.open(tmp, "w")
    if f == nil then return false end
    f:write("territory,x,y,z,finds\n")
    for _, sp in ipairs(spots) do
        f:write(string.format("%d,%.2f,%.2f,%.2f,%d\n", sp.T, sp.X, sp.Y, sp.Z, sp.N))
    end
    f:close()
    os.remove(SPOTS_FILE)
    return os.rename(tmp, SPOTS_FILE) and true or false
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
        raw:write(string.format("%s,%d,%.3f,%.3f,%.3f\n", os.date("!%Y-%m-%dT%H:%M:%SZ"), terr, pos.X, pos.Y, pos.Z))
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

local function LoadTally()
    local tally = {}
    local f = io.open(TALLY_FILE, "r")
    if f == nil then return tally end
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
    return tally
end

local function SaveTally(tally)
    local tmp = TALLY_FILE .. ".tmp"
    local f = io.open(tmp, "w")
    if f == nil then return false end
    f:write("territory," .. table.concat(TALLY_FIELDS, ",") .. "\n")
    for terr, t in pairs(tally) do
        local vals = {}
        for _, k in ipairs(TALLY_FIELDS) do table.insert(vals, tostring(t[k] or 0)) end
        f:write(terr .. "," .. table.concat(vals, ",") .. "\n")
    end
    f:close()
    os.remove(TALLY_FILE)
    return os.rename(tmp, TALLY_FILE) and true or false
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

local function LogTally(prefix)
    for terr, t in pairs(LoadTally()) do
        if t.runs > 0 then
            local p = t.hoard_floors / t.runs
            LogI(string.format("%sterritory %d: %d runs, hoard on %d floors (%.1f%% \u{00B1} %.1f), %d taken, %d missed, %d not found, %d deaths",
                prefix, terr, t.runs, t.hoard_floors, 100 * p, 196 * math.sqrt(p * (1 - p) / t.runs),
                t.taken, t.missed, t.not_found, t.deaths))
        end
    end
end

-- ============================================================
-- One attempt: returns true if the hoard was taken
-- ============================================================
local function Attempt()
    SAFETY_USED = false
    STEALTH = false
    PENDING_CONCEAL = nil
    for k, v in pairs(lastDash) do   -- no clock: allow each dash once per run
        if v == true then lastDash[k] = nil end
    end
    EnterWithSave()
    WaitUntil(function() return InDeepDungeon() and Player.Available and not Player.IsBusy end, 120, "floor load")
    -- Intuition goes through the status window, so wait for it rather than a fixed delay.
    WaitAddon("DeepDungeonStatus", 15)
    Wait(0.5)

    -- HOH_SENSE is set by HoH_OnChat (called from the macro's OnChatMessage) from Intuition's
    -- chat result: "yes" = "You sense the Accursed Hoard calling you...", "no" = "You do not sense...".
    -- It arrives ~1s after Intuition; the marker ~0.3s after that. Without the watcher, fall back
    -- to waiting HOARD_DETECT_SECONDS for the marker.
    HOH_SENSE = nil
    HOH_DISCOVERED = false
    UseIntuition()

    local marker = nil
    local t = 0
    local limit = HOARD_DETECT_SECONDS
    local senseAt = nil
    while t < limit do
        Wait(0.25); t = t + 0.25
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

    MoveTo(marker.Position)
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

-- ============================================================
-- Main
-- ============================================================
local hoards, missed, unseen, deaths = 0, 0, 0, 0
LogD("Landing check (vnavmesh): " .. (V3 ~= nil and "available" or "unavailable") .. ", normal leave: " .. (EventFramework ~= nil and "available" or "unavailable"))
LogI(string.format("Starting: %d runs, save file %d", MAX_RUNS, SAVE_SLOT))
if RECORD_SPOTS then LogSpotStats("Spot log: ") end
LogTally("Run tally: ")
for i = 1, MAX_RUNS do
    local result = Attempt()
    local terr = Territory()
    if result == "taken" then hoards = hoards + 1 elseif result == "missed" then missed = missed + 1 elseif result == "unseen" then unseen = unseen + 1 end
    local died = LeaveDuty()
    if died then
        deaths = deaths + 1
        if result == "taken" then LogI("Died after opening the hoard (it still counts)") end
    end
    CountRun(terr, result, died)
    LogI(string.format("Run %d done, hoards taken: %d, missed: %d, sensed-not-found: %d, deaths: %d", i, hoards, missed, unseen, deaths))
    Wait(3)
end
if RECORD_SPOTS then LogSpotStats("Spot log: ") end
LogTally("Run tally: ")
LogI(string.format("Finished %d runs: %d hoards taken, %d missed, %d sensed-not-found, %d deaths", MAX_RUNS, hoards, missed, unseen, deaths))
collectgarbage("collect")
collectgarbage("collect")
end
