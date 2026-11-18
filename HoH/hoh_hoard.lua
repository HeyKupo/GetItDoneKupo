--[=====[
[[SND Metadata]]
author: HeyKupo
version: 1.0.0
description: HoH hoard farm, loaded by the HoH_hoard macro (which SND downloads it for as a dependency). Enter on a save, use Intuition, take the hoard if it's on the floor, leave, repeat. Leaving doesn't change the save.
[[End Metadata]]
--]=====]

-- SND loads this file as a dependency before the macro runs, and that step can't pause
-- (no /wait or yield), so everything lives inside HoH_Main(); the macro calls it.
function HoH_Main()

-- Logging: essentials at Info; details at Debug (set Dalamud's log level to Debug in /xllog to see them).
local function LogI(msg) Dalamud.Log("[HoH] " .. msg) end
local function LogD(msg) Dalamud.LogDebug("[HoH] " .. msg) end

-- ============================================================
-- Config
-- ============================================================
local ENTRY_NPC_NAME   = "Kyusei"      -- HoH entrance NPC; start the script standing next to them
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
local EXPLORE_SECONDS = 45              -- when the hoard is sensed but not loaded, explore this long before giving up
local MARKER_AFTER_SENSE_SECONDS = 3   -- after the game says "hoard", wait this long for the marker
local HOARD_DETECT_SECONDS = 5         -- after Intuition, look for the hoard marker this long (usually 0.5-2s; occasionally later)
local HOARD_RETRY_SECONDS = 30         -- keep trying to open the hoard this long (e.g. waiting out an otter trap)

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

    local npc = Entity.GetEntityByName(ENTRY_NPC_NAME)
    if npc == nil then error("Entry NPC not found: " .. ENTRY_NPC_NAME) end
    npc:SetAsTarget()
    npc:Interact()

    WaitAddon("DeepDungeonMenu", 10)
    yield(MENU_ENTER_CMD)

    WaitAddon("DeepDungeonSaveData", 10)
    yield(SAVE_SLOT_CMD)

    WaitAddon("ContentsFinderConfirm", 60)
    yield("/click ContentsFinderConfirm Commence")
end

-- DeepDungeonStatus callbacks: code 11 = use pomander, second value = pomander item ID
-- (DeepDungeonItem row; Intuition = 14). Tested in game 2026-11-17.
-- Pomander IDs, looked up by name in the game's DeepDungeonItem table (the callback takes the
-- row ID). Fallbacks are the IDs confirmed in game.
local POM = { safety = 1, intuition = 14, concealment = nil, petrification = nil }
do
    local found = {}
    for id = 1, 80 do
        local ok, row = pcall(function() return Excel.GetRow("DeepDungeonItem", id) end)
        if ok and row ~= nil then
            local ok2, v = pcall(function() return row:GetProperty("Name") end)
            local name = (ok2 and v ~= nil) and string.lower(tostring(v)) or ""
            if string.find(name, "pomander of ", 1, true) and not string.find(name, "protomander", 1, true) then
                for _, key in ipairs({ "safety", "intuition", "concealment", "petrification" }) do
                    if found[key] == nil and string.find(name, key, 1, true) then found[key] = id end
                end
            end
        end
    end
    for k, v in pairs(found) do POM[k] = v end
    LogD(string.format("Pomander IDs: safety=%s intuition=%s concealment=%s petrification=%s",
        tostring(POM.safety), tostring(POM.intuition), tostring(POM.concealment), tostring(POM.petrification)))
end

local function PomCmd(id) return "/callback DeepDungeonStatus true 11 " .. id end

local function UseIntuition()
    yield(PomCmd(POM.intuition))
end

-- What to use before running to the hoard (setting "Protection").
-- Magicite: code 12 + magicite slot (Inferno 0 tested; Crag 1 / Vortex 2 assumed).
-- Pomanders: code 11 + pomander ID (looked up above).
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

local function UseProtection()
    local p = PROTECTION[PROTECTION_CHOICE]
    if p == nil then
        if PROTECTION_CHOICE ~= "None" then
            LogI("WARNING: Protection '" .. PROTECTION_CHOICE .. "' isn't available, running without it")
        end
        return
    end
    if p.stealth then
        -- Concealment is cancelled by abilities and other pomanders (not Sprint). So: Safety now,
        -- then dash + Sprint on the move, then Concealment (see AfterSprint).
        if USE_SAFETY and not SAFETY_USED then
            UseSafety()
            yield("/wait 2.5")   -- pomander animation lock
        end
        PENDING_CONCEAL = p.cmd
        return
    end
    LogD("Protection: " .. PROTECTION_CHOICE)
    yield(p.cmd)
    yield("/wait " .. p.wait)
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

local NORMAL_LEAVE_OK = EventFramework ~= nil   -- turned off if it ever fails to take us out

local function LeaveDuty()
    if InstancedContent.CanLeaveCurrentContent() then
        local sent = NORMAL_LEAVE_OK and pcall(function() EventFramework.LeaveCurrentContent(false) end)
        if sent then
            -- make sure it actually started leaving; otherwise fall back for good
            local t = 0
            while Player.IsInDuty and t < 5 do Wait(0.25); t = t + 0.25 end
            if Player.IsInDuty then
                LogI("WARNING: normal leave didn't work, switching to SND's (forced) leave")
                NORMAL_LEAVE_OK = false
                sent = false
            end
        end
        if not sent then
            InstancedContent.LeaveCurrentContent()
        end
    end
    WaitUntil(function() return not Player.IsInDuty and Player.Available end, 60, "leaving duty")
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

-- Dash (if the job has one, it's ready, the destination is far enough, and it won't land in a
-- wall), Sprint, then any extra dash charges. Call once movement has started.
local function SpeedUp(target)
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

    local dashed = false
    if d ~= nil then
        dashed = DashWithin(true, 1.0) == "dashed"
    end

    LogD("Sprint")
    yield('/ac "Sprint"')   -- no wait after, so trying it while on cooldown costs nothing

    -- Extra charges (En Avant): short lockout between charges, and the path may turn, so keep
    -- trying for a bit.
    if d ~= nil and dashed and d.uses > 1 then
        Wait(0.7)   -- Sprint's animation lock
        for i = 2, d.uses do
            if DashWithin(false, 2.5) ~= "dashed" then break end
        end
    end
end

-- Pomander to use on the move, ~0.7s after Sprint (its animation lock): Concealment if pending,
-- otherwise Safety.
local CONCEAL_MIN_DIST = 10   -- don't bother with Concealment if this close to where we're going

local function AfterSprint(target)
    if PENDING_CONCEAL ~= nil and target ~= nil and DistanceTo(target) < CONCEAL_MIN_DIST then
        LogD(string.format("Concealment skipped: %.0fy left", DistanceTo(target)))
        PENDING_CONCEAL = nil
    elseif PENDING_CONCEAL ~= nil then
        Wait(0.7)
        LogD("Protection: Pomander of Concealment (on the move)")
        yield(PENDING_CONCEAL)
        PENDING_CONCEAL = nil
        STEALTH = true
    elseif USE_SAFETY and not SAFETY_USED and not STEALTH then
        Wait(0.7)
        UseSafety()
    end
end

local function MoveTo(pos)
    IPC.vnavmesh.PathfindAndMoveTo(pos, false)
    -- wait for the path to be computed and movement to begin, so we're facing along the path
    WaitUntil(function() return not IPC.vnavmesh.PathfindInProgress() end, 30, "pathfinding to hoard")
    Wait(0.4)
    SpeedUp(pos)
    AfterSprint(pos)
    WaitUntil(function() return not IPC.vnavmesh.IsRunning() end, 120, "moving to hoard")
end

-- The game says there's a hoard but its marker isn't loaded (objects load room by room around
-- you). Walk toward the farthest loaded object, checking for the marker as more rooms load;
-- repeat with the next unvisited object. Returns the marker, or nil if it never showed up.
local function Explore()
    local visited = {}
    local function Visited(pos)
        for _, v in ipairs(visited) do
            local dx, dz = pos.X - v.X, pos.Z - v.Z
            if dx * dx + dz * dz < 64 then return true end   -- within 8y of a spot we've been to
        end
        return false
    end

    local t = 0
    local legs = 0
    local first = true
    while t < EXPLORE_SECONDS do
        local marker = FindObject(HOARD_MARKER_ID)
        if marker ~= nil then return marker end

        local target = nil
        for _, o in ipairs(ListEventObjects()) do
            if o.Dist > 8 and not Visited(o.Position) and (target == nil or o.Dist > target.Dist) then
                target = o
            end
        end
        if target == nil then
            LogD("Explore: nothing left to walk to")
            return nil
        end

        legs = legs + 1
        LogD(string.format("Explore leg %d: %s at %.0fy", legs, target.Name, target.Dist))
        IPC.vnavmesh.PathfindAndMoveTo(target.Position, false)
        WaitUntil(function() return not IPC.vnavmesh.PathfindInProgress() end, 30, "pathfinding (explore)")
        if first then
            first = false
            Wait(0.4)
            SpeedUp(target.Position)
            AfterSprint(nil)
        end

        while IPC.vnavmesh.IsRunning() and t < EXPLORE_SECONDS do
            Wait(0.5); t = t + 0.5
            marker = FindObject(HOARD_MARKER_ID)
            if marker ~= nil then
                IPC.vnavmesh.Stop()
                return marker
            end
        end
        table.insert(visited, target.Position)
        t = t + 0.5
    end
    IPC.vnavmesh.Stop()
    LogD(string.format("Explore: gave up after %.0fs", t))
    return nil
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

    -- HOH_SENSE is set by OnChatMessage in the macro text from Intuition's chat result:
    -- "yes" = "You sense the Accursed Hoard calling you...", "no" = "You do not sense the call...".
    -- It arrives ~1s after Intuition; the marker ~0.3s after that. Without the watcher, fall back
    -- to waiting HOARD_DETECT_SECONDS for the marker.
    HOH_SENSE = nil
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
        if marker == nil then
            LogI("SENSED BUT NOT FOUND after exploring")
            return "unseen"
        end
        LogD("Marker found while exploring")
    else
        LogD(string.format("Marker seen %.2fs after Intuition", t))
    end
    LogD("Hoard found")

    MoveTo(marker.Position)

    -- Standing on the spot makes the coffer appear. Interact until it's gone (opened), retrying
    -- for a while in case we're transformed by a trap (otter etc.) and can't open it yet.
    local function CofferUp()
        local c = FindObject(HOARD_COFFER_ID)
        return c ~= nil and c.Targetable, c
    end

    -- Check often (so we leave as soon as it's opened), but only re-interact every 2s.
    local t = 0
    local nextInteract = 0
    local seen = false
    while t < HOARD_RETRY_SECONDS do
        local up, c = CofferUp()
        if up then
            seen = true
            if t >= nextInteract then
                local e = Entity.GetEntityByName(c.Name)
                if e ~= nil then
                    e:SetAsTarget()
                    e:Interact()
                end
                nextInteract = t + 2
            end
        elseif seen then
            LogD("Hoard taken")
            return "taken"
        end
        Wait(0.3); t = t + 0.3
    end

    if seen then
        LogI("Hoard NOT taken: coffer still there after " .. HOARD_RETRY_SECONDS .. "s (transformed or blocked?)")
    else
        LogI("Hoard NOT taken: coffer never appeared (didn't reach the spot?)")
    end
    return "missed"
end

-- ============================================================
-- Main
-- ============================================================
local hoards, missed, unseen = 0, 0, 0
LogD("Landing check (vnavmesh): " .. (V3 ~= nil and "available" or "unavailable") .. ", normal leave: " .. (EventFramework ~= nil and "available" or "unavailable"))
LogI(string.format("Starting: %d runs, save file %d", MAX_RUNS, SAVE_SLOT))
for i = 1, MAX_RUNS do
    local result = Attempt()
    if result == "taken" then hoards = hoards + 1 elseif result == "missed" then missed = missed + 1 elseif result == "unseen" then unseen = unseen + 1 end
    LeaveDuty()
    LogI(string.format("Run %d done, hoards taken: %d, missed: %d, sensed-not-found: %d", i, hoards, missed, unseen))
    Wait(3)
end
LogI(string.format("Finished %d runs: %d hoards taken, %d missed, %d sensed-not-found", MAX_RUNS, hoards, missed, unseen))
collectgarbage("collect")
collectgarbage("collect")
end
