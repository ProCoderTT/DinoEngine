--============================================================
--               ANTIKILL  by DinoKid   v3
--        TOOLKILL / WELD / GRIP / KNOCKDOWN HARDENED
--============================================================
--
-- Run it in your executor (or put it in
-- StarterPlayer > StarterPlayerScripts).
-- Running it again replaces the old copy.
-- DELETE / DISABLE ALL OTHER ANTI-FLING SCRIPTS (v2 included).
-- RightShift shows / hides the panel.
--
--============================================================
-- WHAT CHANGED IN v3
--============================================================
--
-- YOUR OWN TOOLS WORK AGAIN
-- • v2 blocked every tool, yours included. Every equip was undone
--   on the spot, and some paths deleted the tool on your screen
--   only. That is the "items in my inventory that are actually
--   deleted".
-- • A tool is now yours when it came through your own Backpack.
--   Only a tool that lands in your hand from anywhere else (picked
--   up from the floor, injected) is blocked.
-- • Blocked tools are unequipped, which makes the server take the
--   grip weld off, and then hidden from your hotbar. RESTORE in the
--   panel puts them back.
-- • Tools are never destroyed on your client any more. That only
--   ever made a copy the server disagreed with.
--
-- KNOCKDOWN LOCK   (the "lie down, then die")
-- • FallingDown / Ragdoll / PlatformStand are switched off for your
--   humanoid, and a body that still ends up on its side is stood
--   back up.
--
-- VOID SHIELD
-- • Your client never deletes your own body below the map, so a
--   drag into the void is brought back instead of killing you.
--
-- OWNERSHIP GUARD
-- • Notices the moment another client starts simulating your body
--   (that is when a toolkill has landed) and cuts every link.
--
-- PICKUP SHIELD
-- • While a dropped tool lies near you, your body stops registering
--   touches, so your own client never reports the pickup.
--
-- REANIMATE AWARE
-- • The body guards pause while Dino Reanimate (or your autorig)
--   runs, so they never fight over your body. Tool guards stay on.
--
-- PANEL
-- • Live status, counters, toggles, live log, a SECURE button, and
--   toasts instead of Roblox notifications.
--
-- Everything from v2 is retained.
--
-- IMPORTANT: this runs on your client. Once the server has welded
-- a tool to your arm, the only cut that reaches the server is the
-- unequip, and that takes one round trip. v3 shrinks that window
-- and survives what lands inside it more often; no client script
-- can close it completely.
--============================================================

--============================================================
-- SERVICES
--============================================================

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local Workspace   = game:GetService("Workspace")
local StarterGui  = game:GetService("StarterGui")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- Running it again replaces the running copy instead of doubling up
if type(_G.DinoAntikillStop) == "function" then
    pcall(_G.DinoAntikillStop)
end


--============================================================
-- CONFIG
--============================================================

local CFG: { [string]: any } = {

    --========================================================
    -- SELF PHYSICS
    --========================================================

    SelfMaxHorizontal = 180,
    SelfMaxVertical   = 155,
    SelfMaxTotal      = 200,
    SelfMaxAngular    = 120,

    SelfAccelerationMinimum = 90,
    SelfMaxAcceleration     = 4000,

    SelfMaxObservedSpeed = 280,

    SelfSevereRollbackDistance = 100,


    --========================================================
    -- ASSEMBLY FIREWALL   (new)
    --========================================================

    AssemblyGuard = true,

    -- How often to walk the assembly. Cheap: normally ~15 parts.
    AssemblyInterval = 0.20,

    -- Hard cap so a huge welded model can't stall the walk.
    AssemblyMaxParts = 120,

    -- AssemblyMass above baseline * this is treated as tampering.
    AssemblyMassRatio = 2.5,

    -- Absolute mass ceiling regardless of baseline.
    AssemblyMassCeiling = 2000,


    --========================================================
    -- JOINT GUARD   (new)
    --========================================================

    JointGuard = true,

    JointInterval = 0.25,

    -- C0/C1 drift from baseline, in studs, before we restore.
    JointMaxDrift = 6,

    -- RootJoint is the usual fling target, so it gets a tighter bound.
    RootJointMaxDrift = 2.5,


    --========================================================
    -- TOOL GUARD   (new + expanded)
    --========================================================

    ToolProtection = true,

    ToolExtremeSpeed = 250,
    ToolExtremeSpin  = 130,

    -- Grip offset beyond this many studs is a yank attempt.
    ToolMaxGripOffset = 8,

    -- A Handle heavier than this welded to you is a catapult.
    ToolMaxHandleMass = 250,

    -- Destroy tools that appear in Character without ever having
    -- been seen in Backpack. Turn OFF if your game hands tools
    -- straight to the character.
    ToolRequireProvenance = true,

    ToolScanInterval = 0.35,

    --========================================================
    -- TOOL BLOCKADE
    --========================================================
    --
    -- The pickup kill works like this:
    --
    --   1. attacker drops a Tool in your path
    --   2. you walk over it and it equips — now it is YOUR tool,
    --      parented into your character
    --   3. RightGrip welds their Handle to your Right Arm
    --   4. they keep network ownership of that Handle and
    --      teleport to the void; your arm follows the weld
    --
    -- The assembly firewall cannot see this, because after step 2
    -- both ends of the weld are inside your character and nothing
    -- crosses the boundary. The only reliable answer is to refuse
    -- the tool outright.
    --
    -- Whitelist anything your game actually needs in AllowedTools.
    --========================================================

    -- v3: only tools that reach your hand WITHOUT coming out of
    -- your own backpack are blocked (pickups, injections). Your own
    -- tools work normally.
    ToolFirewall = true,

    -- v2 behaviour: block your own tools too. Leave this off; it is
    -- what made your items look deleted.
    BlockAllTools = false,

    -- Blocked tools are taken out of your hotbar after the unequip,
    -- so a Water / Cheese Burger / Bloxy Cola spam doesn't pile up
    -- there. RESTORE in the panel puts them back.
    HideForeignTools = true,

    -- Sweep grip welds every frame. Cheap: 2-4 parts, no allocation.
    GripSweep = true,

    AllowedTools = {
        -- ["Sword"] = true,
        -- ["Ball"]  = true,
    },


    --========================================================
    -- PICKUP SHIELD   (v3)
    --========================================================
    --
    -- While a dropped tool lies within this radius, your body
    -- stops registering touches, so your client never reports the
    -- pickup touch. The attacker can still report it from his side;
    -- what gets through meets the firewall.
    --========================================================

    PickupShield       = true,
    PickupShieldRadius = 14,


    --========================================================
    -- KNOCKDOWN LOCK   (v3)
    --========================================================

    StateLock = true,

    -- Also undo the Physics state when something puts you in it.
    -- Reanimates are detected and left alone.
    StateLockPhysics = true,

    -- Degrees from upright, and for how long, before the body is
    -- stood back up.
    TipAngle = 60,
    TipTime  = 0.12,


    --========================================================
    -- VOID SHIELD   (v3)
    --========================================================

    VoidShield = true,


    --========================================================
    -- OWNERSHIP GUARD   (v3)
    --========================================================

    OwnershipGuard    = true,
    OwnershipInterval = 0.05,

    -- consecutive failed checks before it counts as taken
    OwnershipStrikes  = 3,


    --========================================================
    -- REANIMATE   (v3)
    --========================================================

    -- Pause the body guards while Dino Reanimate / autorig runs.
    ReanimateAware = true,


    --========================================================
    -- PANEL   (v3)
    --========================================================

    UI          = true,
    UIToggleKey = Enum.KeyCode.RightShift,


    --========================================================
    -- TELEPORT / VOID GUARD
    --========================================================
    --
    -- A weld-drag moves you further in one frame than any legit
    -- movement ever does. Waiting for three launches before rolling
    -- back is far too slow — by then you are already gone.
    --========================================================

    TeleportGuard = true,

    -- Single-frame displacement above this is a drag, not movement.
    --
    -- For scale: WalkSpeed 16 covers 0.27 studs per frame, and even
    -- a 200 studs/s fling only covers 3.3. Anything past ~20 in one
    -- frame cannot be locomotion.
    TeleportSnapDistance = 22,


    --========================================================
    -- ANCHOR LOCK
    --========================================================
    --
    -- The one defence a weld cannot beat.
    --
    -- Destroying a replicated Tool client-side does not stick: the
    -- server owns its parenting and re-replicates it, RightGrip and
    -- all. That is why removing the tool never worked.
    --
    -- But an anchored part does not move. Not from a weld, not from
    -- a force, not from velocity. And you are network owner of your
    -- own character, so an anchor you set locally holds.
    --
    -- So we stop contesting the tool and freeze the body instead.
    --========================================================

    AnchorLock = true,

    -- How long to stay frozen after a drag is detected.
    AnchorDuration = 0.45,

    -- Refuse to stay anchored longer than this in total, so a false
    -- positive can never leave you permanently stuck.
    AnchorMaxHold = 2.0,

    -- Rolled back if you end up this far under the map.
    VoidMargin = 60,


    --========================================================
    -- SEAT GUARD   (new)
    --========================================================

    SeatGuard = true,

    -- Seat moving faster than this while you're in it = eject.
    SeatMaxSpeed = 90,


    --========================================================
    -- TOUCH GUARD   (new)
    --========================================================

    TouchGuard = true,

    -- Foreign handle touches within the window before we react.
    TouchWindow    = 1.0,
    TouchThreshold = 6,


    --========================================================
    -- PLAYER PHYSICS
    --========================================================

    PlayerWatchRadius = 75,

    PlayerMaxHorizontal = 145,
    PlayerMaxVertical   = 125,
    PlayerMaxTotal      = 175,
    PlayerMaxAngular    = 85,

    PlayerMaxObservedSpeed = 275,
    PlayerIncomingSpeed    = 125,

    PlayerPredictionTime = 0.60,
    PlayerImpactDistance = 5,


    --========================================================
    -- THREAT SYSTEM
    --========================================================

    PlayerBadSamplesRequired = 2,

    PlayerThreatThreshold  = 10,
    PlayerCriticalThreshold = 18,

    PlayerThreatDecay = 5,
    PlayerForgetTime  = 8,
    PlayerReleaseDelay = 1.5,


    --========================================================
    -- REANIMATION
    --========================================================

    ReanimRadius = 55,

    ReanimHandleSpeed = 100,
    ReanimHandleSpin  = 70,

    ReanimIncomingSpeed = 80,

    ReanimDetachedDistance = 7,

    ReanimPredictionTime = 0.50,
    ReanimImpactDistance = 5,


    --========================================================
    -- GENERAL PHYSICS OBJECTS
    --========================================================

    NearbyPhysicsRadius = 15,
    NearbyMaxParts      = 35,

    NearbyExtremeSpeed  = 300,
    NearbyExtremeSpin   = 130,
    NearbyIncomingSpeed = 200,

    NearbyPredictionTime = 0.50,
    NearbyImpactDistance = 4,


    --========================================================
    -- SHIELD
    --========================================================

    MaxShieldPairs = 24,
    ShieldLifetime = 0.30,

    MaxProtectedBodyParts = 7,

    -- Under sustained attack the caps lift and shields last longer.
    -- A repeat attacker gets a harder target than a one-off shove.
    LockdownShieldPairs    = 64,
    LockdownShieldLifetime = 1.20,

    -- Recoveries inside this window to trigger lockdown.
    LockdownTriggerCount  = 2,
    LockdownTriggerWindow = 6,

    -- How long lockdown holds after the last hit.
    LockdownDuration = 10,


    --========================================================
    -- INJECTION
    --========================================================

    RemoveInjectedForces  = true,
    RemoveExternalTethers = true,

    -- Watch Workspace for constraints anchored to you from outside.
    WatchWorkspaceConstraints = true,


    --========================================================
    -- SCAN SPEEDS
    --========================================================

    SelfScan = true,

    PlayerScanInterval       = 0.12,
    DangerPlayerScanInterval = 0.05,

    ReanimScanInterval       = 0.10,
    DangerReanimScanInterval = 0.045,

    NearbyScanInterval       = 0.16,
    DangerNearbyScanInterval = 0.08,

    IntegrityInterval   = 1.0,
    SafeSnapshotInterval = 0.10,


    --========================================================
    -- LOGGING
    --========================================================

    Notifications = true,
    Prints        = true,

    NotificationCooldown = 1.0,
}


--============================================================
-- STATE
--============================================================

local Character = nil
local Humanoid  = nil
local Root      = nil
local Backpack  = nil

local CharacterConnections = {}
local GlobalConnections    = {}

local LastSelfPosition = nil
local LastSelfVelocity = Vector3.zero

local SafeCFrame       = nil
local LastSafeSnapshot = 0

local RecoveryUntil     = 0
local TeleportGraceUntil = 0

local LastToolScan      = 0
local LastIntegrityScan = 0
local LastAssemblyScan  = 0
local LastJointScan     = 0
local LastShieldPrune   = 0

local KnownTools    = {}
local SeenInBackpack = {}   -- provenance: tool -> true
local ToolGripBase  = {}    -- tool -> CFrame

local JointBase = {}        -- joint -> { C0, C1, Part0, Part1 }

local BaselineRootSize = nil
local BaselineAssemblyMass = nil

local TouchEvents = {}      -- timestamps of foreign handle touches

local PlayerThreats = {}
local LaunchTimes   = {}
local NotificationTimes = {}

local ActiveShields = {}
local ShieldCount   = 0

-- Rolling log so a death can be reconstructed afterwards.
-- Lets you compare an attempt you survived against the one you
-- didn't, instead of guessing at which layer failed.
local EventLog    = {}
local EventLogMax = 120
local ScriptStart = os.clock()

-- Sustained-attack mode: scans go to every frame, caps lift
local LockdownUntil = 0

-- Anchor lock
local AnchorUntil     = 0
local AnchorStarted    = 0
local WasAnchored      = false
local AuthorizedCFrame = nil

local PhysicsFilterDirty       = true
local LastPhysicsFilterRefresh = 0


--============================================================
-- STATE (v3)
--============================================================

local Alive  = true
local Global = (type(getgenv) == "function" and getgenv()) or shared

-- Tool provenance
local OwnTools        = setmetatable({}, { __mode = "k" })  -- came through our Backpack
local ForeignTools    = setmetatable({}, { __mode = "k" })  -- blocked
local ToolSeenOutside = setmetatable({}, { __mode = "k" })  -- seen in the world, not on us
local DroppedTools    = setmetatable({}, { __mode = "k" })  -- lying loose in Workspace
local HiddenTools     = {}                                   -- { tool, name, why, t }

-- Knockdown lock
local TipSince = nil

-- Ownership guard
local OwnStrikes     = 0
local OwnershipLost  = false
local OwnershipState = "?"
local LastOwnCheck   = 0

-- Pickup shield
local TouchOff    = false
local TouchSaved  = {}      -- part -> CanTouch before the shield
local NearDropped = nil

-- Void shield: the game's real destroy height, for the void guard
local VoidBaseHeight = -500
do
    local ok, h = pcall(function() return Workspace.FallenPartsDestroyHeight end)
    if ok and type(h) == "number" and h == h then VoidBaseHeight = h end
end

-- Reanimate mode, refreshed every physics step
local ReanimMode = false

-- Filled in by the panel
local UIHooks: { [string]: any } = { Feed = nil, Toast = nil }


--============================================================
-- STATS
--============================================================

local Stats = {
    TotalBlocks = 0,

    SelfVelocity     = 0,
    SelfSpin         = 0,
    SelfAcceleration = 0,
    SelfPosition     = 0,

    Player           = 0,
    PlayerApproach   = 0,
    PlayerTrajectory = 0,
    PlayerSpin       = 0,

    Reanimate          = 0,
    ReanimateAttribute = 0,
    ReanimateHandle    = 0,

    PhysicsObject = 0,

    Tool    = 0,
    ToolGrip = 0,
    Force   = 0,
    Tether  = 0,

    Assembly = 0,
    Mass     = 0,
    Joint    = 0,
    Seat     = 0,
    Touch    = 0,

    Integrity      = 0,
    RepeatedLaunch = 0,
    Recoveries     = 0,
    Lockdowns      = 0,
    ToolBlocked    = 0,
    GripSevered    = 0,
    Teleport       = 0,
    AnchorLocks    = 0,
    PositionAssert = 0,

    ToolsHidden   = 0,
    StateSaves    = 0,
    OwnershipLost = 0,
    PickupShields = 0,
    Secure        = 0,
}

local StatKey = {
    ["SELF VELOCITY"]     = "SelfVelocity",
    ["SELF SPIN"]         = "SelfSpin",
    ["SELF ACCELERATION"] = "SelfAcceleration",
    ["SELF POSITION"]     = "SelfPosition",

    ["PLAYER"]            = "Player",
    ["PLAYER APPROACH"]   = "PlayerApproach",
    ["PLAYER TRAJECTORY"] = "PlayerTrajectory",
    ["PLAYER SPIN"]       = "PlayerSpin",

    ["REANIMATE"]           = "Reanimate",
    ["REANIMATE ATTRIBUTE"] = "ReanimateAttribute",
    ["REANIMATE HANDLE"]    = "ReanimateHandle",

    ["PHYSICS OBJECT"] = "PhysicsObject",

    ["TOOL"]      = "Tool",
    ["TOOL GRIP"] = "ToolGrip",
    ["FORCE"]     = "Force",
    ["TETHER"]    = "Tether",

    ["ASSEMBLY"] = "Assembly",
    ["MASS"]     = "Mass",
    ["JOINT"]    = "Joint",
    ["SEAT"]     = "Seat",
    ["TOUCH"]    = "Touch",

    ["INTEGRITY"] = "Integrity",
    ["LOCKDOWN"]     = "Lockdowns",
    ["TOOL BLOCKED"] = "ToolBlocked",
    ["GRIP"]         = "GripSevered",
    ["TELEPORT"]     = "Teleport",
    ["ANCHOR"]       = "AnchorLocks",
    ["ASSERT"]       = "PositionAssert",
    ["STATE"]        = "StateSaves",
    ["OWNERSHIP"]    = "OwnershipLost",
    ["SECURE"]       = "Secure",
}


--============================================================
-- CLASS TABLES
--============================================================

local BadForceClasses = {
    BodyVelocity        = true,
    BodyAngularVelocity = true,
    BodyForce           = true,
    BodyThrust           = true,
    BodyPosition        = true,
    BodyGyro            = true,

    LinearVelocity  = true,
    AngularVelocity = true,
    VectorForce     = true,
    Torque          = true,

    AlignPosition    = true,
    AlignOrientation = true,
}

-- Rigid links. These join a part into your ASSEMBLY, which is the
-- toolkill vector: once joined, its momentum becomes your momentum.
local RigidJointClasses = {
    Weld           = true,
    WeldConstraint = true,
    ManualWeld     = true,
    Motor          = true,
    Motor6D        = true,
    Snap           = true,
    Glue           = true,
    Rotate         = true,
    RotateP        = true,
    RotateV        = true,
}

-- Non-rigid but still capable of dragging you around.
local TetherConstraintClasses = {
    RopeConstraint    = true,
    SpringConstraint  = true,
    RodConstraint     = true,
    PrismaticConstraint = true,
    CylindricalConstraint = true,
    HingeConstraint   = true,
    BallSocketConstraint = true,
    AlignPosition     = true,
    AlignOrientation  = true,
    Torque            = true,
    VectorForce       = true,
    LinearVelocity    = true,
    AngularVelocity   = true,
    PlaneConstraint   = true,
}


--============================================================
-- OVERLAP PARAMS
--============================================================

local PhysicsOverlap = OverlapParams.new()
PhysicsOverlap.FilterType = Enum.RaycastFilterType.Exclude
PhysicsOverlap.MaxParts   = CFG.NearbyMaxParts

local DetachedOverlap = OverlapParams.new()
DetachedOverlap.FilterType = Enum.RaycastFilterType.Exclude
DetachedOverlap.MaxParts   = 50


--============================================================
-- BASIC HELPERS
--============================================================

local function Debug(...)
    if CFG.Prints then
        print("[ANTIKILL]", ...)
    end
end


local function IsFiniteVector(v)
    if typeof(v) ~= "Vector3" then return false end
    return v.X == v.X and v.Y == v.Y and v.Z == v.Z
        and math.abs(v.X) < math.huge
        and math.abs(v.Y) < math.huge
        and math.abs(v.Z) < math.huge
end


local function IsFiniteCFrame(cf)
    if typeof(cf) ~= "CFrame" then return false end
    return IsFiniteVector(cf.Position)
end


local function FlatMagnitude(v)
    return Vector3.new(v.X, 0, v.Z).Magnitude
end


local function ValidDt(dt)
    if type(dt) ~= "number" then return nil end
    if dt <= 0.004 then return nil end
    if dt >= 0.20  then return nil end
    return dt
end


local function GetPlayerFromPart(part)
    if not part then return nil end
    local model = part:FindFirstAncestorOfClass("Model")
    if not model then return nil end
    return Players:GetPlayerFromCharacter(model)
end


local function IsPlayerCharacterPart(part)
    return GetPlayerFromPart(part) ~= nil
end


local function IsMine(inst)
    return Character ~= nil
        and inst ~= nil
        and inst:IsDescendantOf(Character)
end


--============================================================
-- LOGGING / BLOCK
--============================================================

local function LogEvent(category, message)
    local entry = {
        t   = os.clock() - ScriptStart,
        cat = category,
        msg = tostring(message),
    }
    table.insert(EventLog, entry)
    while #EventLog > EventLogMax do
        table.remove(EventLog, 1)
    end
    if UIHooks.Feed then pcall(UIHooks.Feed, entry) end
end


local function Block(category, message, key)

    Stats.TotalBlocks += 1
    LogEvent(category, message)

    local field = StatKey[category]
    if field and Stats[field] then
        Stats[field] += 1
    end

    warn("[ANTIKILL][BLOCKED][" .. category .. "] " .. tostring(message))

    if not CFG.Notifications then return end

    local now = os.clock()
    local notificationKey = key or category
    local last = NotificationTimes[notificationKey]

    if last and now - last < CFG.NotificationCooldown then
        return
    end

    NotificationTimes[notificationKey] = now

    if UIHooks.Toast then
        pcall(UIHooks.Toast, category, tostring(message))
        return
    end

    task.spawn(function()
        for _ = 1, 4 do
            local ok = pcall(function()
                StarterGui:SetCore("SendNotification", {
                    Title    = "ANTIKILL by DinoKid",
                    Text     = category .. ": " .. tostring(message),
                    Duration = 2.5,
                })
            end)
            if ok then break end
            task.wait(0.10)
        end
    end)
end


--============================================================
-- PLAYER THREAT
--============================================================

local function GetThreat(player)
    local id = player.UserId
    local data = PlayerThreats[id]
    if data then return data end

    data = {
        Player = player,
        Score  = 0,
        BadSamples = 0,
        Flagged  = false,
        Critical = false,
        LastBad   = 0,
        LastScore = os.clock(),
        SafeSince = nil,
        LastPosition     = nil,
        LastPositionTime = os.clock(),
        LastShield = 0,
    }

    PlayerThreats[id] = data
    return data
end


local function DecayThreat(data)
    local now = os.clock()
    local elapsed = now - (data.LastScore or now)
    if elapsed > 0 then
        data.Score = math.max(0, data.Score - elapsed * CFG.PlayerThreatDecay)
    end
    data.LastScore = now
end


local function AddThreat(player, amount)
    local data = GetThreat(player)
    DecayThreat(data)

    data.Score   = math.clamp(data.Score + amount, 0, 100)
    data.LastBad = os.clock()
    data.SafeSince = nil

    if data.Score >= CFG.PlayerCriticalThreshold then
        data.Flagged  = true
        data.Critical = true
    elseif data.Score >= CFG.PlayerThreatThreshold then
        data.Flagged = true
    end

    return data
end


local function HasDangerousPlayer()
    for _, data in pairs(PlayerThreats) do
        if data.Flagged and data.Player and data.Player.Parent then
            return true
        end
    end
    return false
end


--============================================================
-- PREDICTION
--============================================================

local function PredictClosestApproach(myPosition, targetPosition, targetVelocity, horizon)

    local relative = targetPosition - myPosition
    local velocitySquared = targetVelocity:Dot(targetVelocity)

    if velocitySquared <= 0.001 then
        return relative.Magnitude, horizon, false
    end

    local time = -relative:Dot(targetVelocity) / velocitySquared
    time = math.clamp(time, 0, horizon)

    local predicted = targetPosition + targetVelocity * time
    local distance  = (predicted - myPosition).Magnitude
    local incoming  = relative:Dot(targetVelocity) < 0

    return distance, time, incoming
end


--============================================================
-- SHIELD
--============================================================

local function GetShieldParts()
    if not Character then return {} end

    local result = {}
    local names = {
        "HumanoidRootPart", "Torso", "Head",
        "Left Arm", "Right Arm", "Left Leg", "Right Leg",
    }

    for _, name in ipairs(names) do
        if #result >= CFG.MaxProtectedBodyParts then break end
        local part = Character:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            table.insert(result, part)
        end
    end

    return result
end


local function DestroyShield(ownPart, targetPart)
    local targets = ActiveShields[ownPart]
    if not targets then return end

    local constraint = targets[targetPart]
    if constraint then
        pcall(function() constraint:Destroy() end)
        targets[targetPart] = nil
        ShieldCount = math.max(0, ShieldCount - 1)
    end

    if next(targets) == nil then
        ActiveShields[ownPart] = nil
    end
end


-- Recount from the table rather than trusting the running total.
--
-- The counter used to leak: if a constraint was destroyed from
-- outside (respawn, destroyed part, the attacker cleaning up) the
-- slot survived with a dead value, the replacement incremented
-- again, and the old task.delay never decremented. After ~24 leaks
-- ShieldCount sat at the cap forever and every shield request became
-- a silent no-op. That is why the third attack landed.
local function PruneShields()

    local live = 0

    for ownPart, targets in pairs(ActiveShields) do

        if not ownPart.Parent then
            for _, c in pairs(targets) do
                pcall(function() c:Destroy() end)
            end
            ActiveShields[ownPart] = nil
        else
            for targetPart, constraint in pairs(targets) do
                if not constraint or not constraint.Parent
                    or not targetPart.Parent then

                    if constraint then
                        pcall(function() constraint:Destroy() end)
                    end
                    targets[targetPart] = nil
                else
                    live += 1
                end
            end

            if next(targets) == nil then
                ActiveShields[ownPart] = nil
            end
        end
    end

    ShieldCount = live
    return live
end


local function AddShieldPair(ownPart, targetPart)
    if not ownPart or not targetPart then return end
    if not ownPart.Parent or not targetPart.Parent then return end
    if not ownPart:IsA("BasePart") or not targetPart:IsA("BasePart") then return end
    if ownPart == targetPart then return end

    local targets = ActiveShields[ownPart]
    if not targets then
        targets = {}
        ActiveShields[ownPart] = targets
    end

    local existing = targets[targetPart]

    if existing then
        if existing.Parent then
            -- still alive: refresh its lifetime instead of stacking a new one
            return
        end
        -- dead slot: reclaim it before allocating
        targets[targetPart] = nil
        ShieldCount = math.max(0, ShieldCount - 1)
    end

    local cap = (os.clock() < LockdownUntil)
        and CFG.LockdownShieldPairs
        or  CFG.MaxShieldPairs

    if ShieldCount >= cap then
        -- last resort: sweep dead entries and try once more
        if PruneShields() >= cap then
            return
        end
    end

    local constraint = Instance.new("NoCollisionConstraint")
    constraint.Part0   = ownPart
    constraint.Part1   = targetPart
    constraint.Enabled = true
    constraint.Parent  = Workspace

    targets[targetPart] = constraint
    ShieldCount += 1

    local lifetime = CFG.ShieldLifetime
    if os.clock() < LockdownUntil then
        lifetime = CFG.LockdownShieldLifetime
    end

    task.delay(lifetime, function()
        if targets[targetPart] == constraint then
            DestroyShield(ownPart, targetPart)
        end
    end)
end


local function ShieldPart(part)
    if not part or not part.Parent then return end
    for _, ownPart in ipairs(GetShieldParts()) do
        AddShieldPair(ownPart, part)
    end
end


local function ShieldPlayer(player)
    if not Character then return end

    local character = player.Character
    if not character then return end

    local now  = os.clock()
    local data = GetThreat(player)

    if now - (data.LastShield or 0) < 0.15 then return end
    data.LastShield = now

    local root = character:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then ShieldPart(root) end

    local torso = character:FindFirstChild("Torso")
    if torso and torso:IsA("BasePart") then ShieldPart(torso) end
end


--============================================================
--                  ASSEMBLY FIREWALL
--============================================================
--
-- This is the module that actually stops toolkill.
--
-- A fling that arrives through a weld is not a "fast part near
-- you" — it is a part that has become PART OF YOU. The engine
-- solves your root and that part as one rigid body, so their
-- momentum is shared. Clamping the root just fights the joint
-- every frame and loses, because the joint is re-applied by the
-- solver at a lower level than your LocalScript runs.
--
-- The only reliable answer is to cut the joint.
--============================================================


-- Destroy every rigid link that crosses the character boundary
-- for this part. Returns how many were cut.
local function SeverForeignLinks(foreignPart)

    if not foreignPart or not foreignPart.Parent then
        return 0
    end

    if not (foreignPart:IsA("BasePart")
        and foreignPart:IsDescendantOf(Workspace)) then
        return 0
    end

    local cut = 0

    local ok, joints = pcall(function()
        return foreignPart:GetJoints()
    end)

    if ok and joints then
        for _, joint in ipairs(joints) do

            local p0 = joint.Part0
            local p1 = joint.Part1

            if p0 and p1 then
                -- exactly one side inside the character = a bridge in
                if IsMine(p0) ~= IsMine(p1) then
                    pcall(function() joint:Destroy() end)
                    cut += 1
                end
            end
        end
    end

    return cut
end


-- Walk the assembly the root actually belongs to and evict
-- anything that is not part of our character.
local function ScanAssembly()

    if not CFG.AssemblyGuard then return end
    if not Root or not Root.Parent then return end

    local ok, connected = pcall(function()
        return Root:GetConnectedParts(true)
    end)

    if not ok or not connected then return end

    local examined = 0
    local evicted  = 0
    local worstName

    for _, part in ipairs(connected) do

        examined += 1
        if examined > CFG.AssemblyMaxParts then break end

        if part ~= Root and not IsMine(part) then

            -- A foreign part sharing our assembly is never legitimate
            -- for a humanoid character. Seats are handled separately.
            local cut = SeverForeignLinks(part)

            if cut > 0 then
                evicted += 1
                worstName = worstName or (part:GetFullName())

                -- stop it colliding with us on the way out
                ShieldPart(part)

                -- blame the owner if it belongs to someone
                local owner = GetPlayerFromPart(part)
                if owner and owner ~= LocalPlayer then
                    local threat = AddThreat(owner, 20)
                    threat.Flagged  = true
                    threat.Critical = true
                    ShieldPlayer(owner)
                end
            end
        end
    end

    if evicted > 0 then
        Block("ASSEMBLY",
            "Severed " .. evicted .. " foreign link(s): " .. tostring(worstName),
            "assembly")
        return true
    end

    return false
end


--============================================================
-- MASS GUARD
--============================================================
--
-- Welding a very heavy part to you is the catapult setup: your
-- own walk force, or one shove, then acts on an assembly with a
-- huge inertia tensor and the result is a launch. A mass spike
-- is therefore a reliable tell even before any velocity appears.
--============================================================

local function CheckAssemblyMass()

    if not CFG.AssemblyGuard then return end
    if not Root or not Root.Parent then return end

    local mass = Root.AssemblyMass
    if type(mass) ~= "number" or mass ~= mass then return end

    local base = BaselineAssemblyMass
    if not base or base <= 0 then
        BaselineAssemblyMass = mass
        return
    end

    local overRatio   = mass > base * CFG.AssemblyMassRatio
    local overCeiling = mass > CFG.AssemblyMassCeiling

    if overRatio or overCeiling then

        Block("MASS",
            "Assembly mass " .. math.floor(mass)
            .. " (baseline " .. math.floor(base) .. ")",
            "mass")

        -- something is welded on; find and cut it
        ScanAssembly()
    end
end


--============================================================
--                     JOINT GUARD
--============================================================
--
-- The single most common fling primitive is not a force at all:
--
--     RootJoint.C0 = CFrame.new(0, 100000, 0)
--
-- The solver snaps the character to satisfy the joint and the
-- resulting displacement over one frame becomes enormous
-- velocity. Baselining C0/C1 and restoring on drift kills it.
--
-- Part0/Part1 repointing is the same idea aimed sideways: your
-- own RootJoint is re-bound to a foreign part, so you inherit
-- that part's motion through a joint you own.
--============================================================

local function BaselineJoints()

    table.clear(JointBase)

    if not Character then return end

    for _, obj in ipairs(Character:GetDescendants()) do
        if RigidJointClasses[obj.ClassName] and obj:IsA("JointInstance") then

            local okC0, c0 = pcall(function() return obj.C0 end)
            local okC1, c1 = pcall(function() return obj.C1 end)

            JointBase[obj] = {
                C0 = okC0 and c0 or nil,
                C1 = okC1 and c1 or nil,
                Part0 = obj.Part0,
                Part1 = obj.Part1,
                IsRoot = (obj.Name == "RootJoint"),
            }
        end
    end
end


local function CheckJoints()

    if not CFG.JointGuard then return end
    if not Character then return end

    for joint, base in pairs(JointBase) do

        if not joint.Parent then
            JointBase[joint] = nil
            continue
        end

        local limit = base.IsRoot
            and CFG.RootJointMaxDrift
            or  CFG.JointMaxDrift

        ----------------------------------------------------
        -- C0 / C1 drift
        ----------------------------------------------------

        local okC0, c0 = pcall(function() return joint.C0 end)

        if okC0 and base.C0 and IsFiniteCFrame(c0) then
            local drift = (c0.Position - base.C0.Position).Magnitude
            if drift > limit then
                pcall(function() joint.C0 = base.C0 end)
                Block("JOINT",
                    joint.Name .. " C0 drifted " .. math.floor(drift) .. " studs",
                    "joint_c0_" .. joint.Name)
            end
        elseif okC0 and base.C0 and not IsFiniteCFrame(c0) then
            pcall(function() joint.C0 = base.C0 end)
            Block("JOINT", joint.Name .. " C0 was non-finite", "joint_nan")
        end

        local okC1, c1 = pcall(function() return joint.C1 end)

        if okC1 and base.C1 and IsFiniteCFrame(c1) then
            local drift = (c1.Position - base.C1.Position).Magnitude
            if drift > limit then
                pcall(function() joint.C1 = base.C1 end)
                Block("JOINT",
                    joint.Name .. " C1 drifted " .. math.floor(drift) .. " studs",
                    "joint_c1_" .. joint.Name)
            end
        end

        ----------------------------------------------------
        -- Part0 / Part1 repointing
        ----------------------------------------------------

        local p0, p1 = joint.Part0, joint.Part1

        local hijacked =
            (p0 ~= nil and not IsMine(p0)) or
            (p1 ~= nil and not IsMine(p1))

        if hijacked then

            -- put it back if the original targets still exist
            if base.Part0 and base.Part0.Parent
               and base.Part1 and base.Part1.Parent then

                pcall(function()
                    joint.Part0 = base.Part0
                    joint.Part1 = base.Part1
                end)

            else
                pcall(function() joint:Destroy() end)
                JointBase[joint] = nil
            end

            Block("JOINT",
                joint.Name .. " was repointed off the character",
                "joint_hijack")
        end
    end
end


--============================================================
--                      TOOL GUARD
--============================================================
--
-- Toolkill, specifically:
--
--   1. a Tool is forced into your Character
--   2. its Handle welds to you (Tool.Grip / RightGrip)
--   3. the Handle is then driven at speed, or given a huge
--      Grip offset, and your body follows the weld
--
-- So there are three separate things to defend:
--   • provenance  — did this tool ever legitimately reach you
--   • the grip    — is the weld offset sane
--   • the handle  — is its mass / velocity / spin sane
--============================================================

local function IsAllowedTool(tool)
    if not tool or not tool:IsA("Tool") then return true end
    if CFG.AllowedTools[tool.Name] then return true end
    if tool:GetAttribute("AntiFlingAllowed") == true then return true end
    return false
end


-- v3 provenance. A tool is yours when it reached you through your
-- own Backpack: the game gave it to you, or you unequipped it. A tool
-- that lands in your hand without passing through there was picked
-- up or injected.
local function IsForeignTool(tool)
    if not tool or not tool:IsA("Tool") then return false end
    if IsAllowedTool(tool) then return false end
    if ForeignTools[tool] then return true end
    if CFG.BlockAllTools then return true end
    if not CFG.ToolFirewall then return false end
    return not OwnTools[tool]
end


-- forward: defined in the TOOL BLOCKADE section
local RejectTool


local function LearnExistingTools()

    table.clear(KnownTools)

    if Backpack then
        for _, item in ipairs(Backpack:GetChildren()) do
            if item:IsA("Tool") then
                KnownTools[item]     = true
                SeenInBackpack[item] = true
                if not ForeignTools[item] then OwnTools[item] = true end
            end
        end
    end

    if Character then
        for _, item in ipairs(Character:GetChildren()) do
            if item:IsA("Tool") then
                KnownTools[item] = true
                -- a tool already equipped at spawn is legitimate
                SeenInBackpack[item] = true
                if not ForeignTools[item] then OwnTools[item] = true end
            end
        end
    end
end


-- Snapshot the Grip so we can tell a yank from normal animation
local function BaselineToolGrip(tool)
    if not tool or not tool:IsA("Tool") then return end
    local ok, grip = pcall(function() return tool.Grip end)
    if ok and IsFiniteCFrame(grip) then
        ToolGripBase[tool] = grip
    end
end


local function CheckToolGrip(tool)

    if not tool or not tool.Parent then return end

    local ok, grip = pcall(function() return tool.Grip end)
    if not ok then return end

    -- A non-finite grip is always an attack
    if not IsFiniteCFrame(grip) then
        local base = ToolGripBase[tool] or CFrame.new()
        pcall(function() tool.Grip = base end)
        Block("TOOL GRIP", tool.Name .. " grip was non-finite", "grip_nan")
        return true
    end

    -- A grip is an offset from the hand. Legitimate values are a
    -- couple of studs. Anything large is dragging your arm.
    local offset = grip.Position.Magnitude

    if offset > CFG.ToolMaxGripOffset then

        local base = ToolGripBase[tool]

        if base then
            pcall(function() tool.Grip = base end)
        else
            pcall(function() tool.Grip = CFrame.new() end)
        end

        Block("TOOL GRIP",
            tool.Name .. " grip offset " .. math.floor(offset) .. " studs",
            "grip_offset")

        return true
    end

    return false
end


-- Is this handle rigidly tied to something that isn't us?
-- GetJoints only works on parts inside Workspace. Called on a part
-- that is still in Backpack or ReplicatedStorage it returns an empty
-- list AND warns, which is the console spam you saw — and it meant
-- these checks were quietly no-ops for backpack tools.
local function CanQueryJoints(part)
    return part
       and part:IsA("BasePart")
       and part:IsDescendantOf(Workspace)
end


local function HandleHasForeignLink(handle)

    if not CanQueryJoints(handle) then return false end

    local ok, joints = pcall(function() return handle:GetJoints() end)
    if not ok or not joints then return false end

    for _, joint in ipairs(joints) do
        local p0, p1 = joint.Part0, joint.Part1
        if p0 and p1 then
            local other = (p0 == handle) and p1 or p0
            if other and not IsMine(other) and other.Parent ~= handle.Parent then
                return true, other
            end
        end
    end

    return false
end


-- Full audit of one tool. Returns true if it was removed.
local function AuditTool(tool)

    if not tool or not tool.Parent then return false end
    if not tool:IsA("Tool") then return false end
    if IsAllowedTool(tool) then return false end

    ----------------------------------------------------------
    -- Provenance
    ----------------------------------------------------------

    if tool.Parent == Character and IsForeignTool(tool) then
        RejectTool(tool, "never came out of your backpack")
        return true
    end

    ----------------------------------------------------------
    -- Grip
    ----------------------------------------------------------

    CheckToolGrip(tool)

    ----------------------------------------------------------
    -- Handle
    ----------------------------------------------------------

    local handle = tool:FindFirstChild("Handle")

    if handle and handle:IsA("BasePart") then

        local velocity = handle.AssemblyLinearVelocity
        local angular  = handle.AssemblyAngularVelocity

        if IsFiniteVector(velocity) and IsFiniteVector(angular) then

            local speed = velocity.Magnitude
            local spin  = angular.Magnitude

            if speed > CFG.ToolExtremeSpeed or spin > CFG.ToolExtremeSpin then
                Block("TOOL",
                    "Extreme handle physics: " .. tool.Name
                    .. " (" .. math.floor(speed) .. " / " .. math.floor(spin) .. ")",
                    "tool_physics")

                ShieldPart(handle)
                RejectTool(tool, "extreme handle physics")
                return true
            end
        end

        -- A heavy handle welded to you is a catapult
        local okMass, mass = pcall(function() return handle.AssemblyMass end)

        if okMass and type(mass) == "number" and mass > CFG.ToolMaxHandleMass then
            Block("TOOL",
                "Handle mass " .. math.floor(mass) .. ": " .. tool.Name,
                "tool_mass")

            ShieldPart(handle)
            RejectTool(tool, "heavy handle")
            return true
        end

        -- Welded through to something outside the character
        local foreign, other = HandleHasForeignLink(handle)

        if foreign then
            Block("TOOL",
                tool.Name .. " handle linked to " .. tostring(other and other.Name),
                "tool_foreign")

            SeverForeignLinks(handle)
            ShieldPart(handle)
            return true
        end
    end

    ----------------------------------------------------------
    -- Force objects nested anywhere inside
    ----------------------------------------------------------

    for _, obj in ipairs(tool:GetDescendants()) do
        if BadForceClasses[obj.ClassName] then
            Block("FORCE", "Removed tool force: " .. obj.ClassName, "tool_force")
            pcall(function() obj:Destroy() end)
        end
    end

    return false
end


local function ScanOwnTools()

    if not CFG.ToolProtection or not Character then return end

    for _, tool in ipairs(Character:GetChildren()) do
        if tool:IsA("Tool") then
            if AuditTool(tool) then return end
        end
    end
end


--============================================================
--                     ANCHOR LOCK
--============================================================
--
-- Freeze the body rather than fight for the tool.
--
-- Ordering matters: the anchor must be applied on PostSimulation,
-- after the solver has run. Setting it before physics lets the
-- solver clear it the same frame.
--============================================================

local function EngageAnchor(reason)

    if not CFG.AnchorLock or ReanimMode then return end
    if not Root or not Root.Parent then return end

    local now = os.clock()

    -- never hold longer than AnchorMaxHold in one stretch
    if WasAnchored and now - AnchorStarted > CFG.AnchorMaxHold then
        return
    end

    if not WasAnchored then
        AnchorStarted = now
        AuthorizedCFrame = SafeCFrame or Root.CFrame
        Stats.AnchorLocks += 1
        Block("ANCHOR", "Frozen — " .. reason, "anchor")
    end

    AnchorUntil = now + CFG.AnchorDuration
    WasAnchored = true

    pcall(function()
        Root.AssemblyLinearVelocity  = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero
        Root.Anchored = true
    end)
end


local function ReleaseAnchor()

    if not WasAnchored then return end
    if not Root or not Root.Parent then
        WasAnchored = false
        return
    end

    local now = os.clock()

    local expired  = now >= AnchorUntil
    local heldTooLong = now - AnchorStarted > CFG.AnchorMaxHold

    if expired or heldTooLong then
        pcall(function()
            Root.Anchored = false
            Root.AssemblyLinearVelocity  = Vector3.zero
            Root.AssemblyAngularVelocity = Vector3.zero
        end)
        WasAnchored = false
    end
end


--============================================================
--                    TOOL BLOCKADE
--============================================================
--
-- Runs every frame. Three layers, because the window between
-- "tool touches you" and "you are in the void" is about two
-- frames and any one layer alone can be raced.
--
--   1. reject the Tool the instant it is parented to you
--   2. sever the grip weld even if the Tool survived
--   3. eject the Tool from the character entirely
--============================================================

-- Do NOT destroy the tool.
--
-- Your log showed each tool blocked four times in a row. That was
-- one tool, destroyed and re-replicated four times: the server owns
-- its parenting, so every Destroy just invites it straight back.
-- The attacker does not need to win every one of those exchanges,
-- only one — which is exactly why spamming Water, then Cheese
-- Burger, then Bloxy Cola works.
--
-- So concede the tool and take away what makes it dangerous:
-- unequip it (authoritative for your own humanoid), cut the grip,
-- and freeze. It can sit in the backpack all day doing nothing.

local BlockedToolTimes = {}

-- v3 order:
--   1. unequip FIRST. It is the only cut that reaches the server:
--      the server takes RightGrip off when the tool leaves your
--      character. Everything after it is local.
--   2. cut the handle's joints on this client, so your own physics
--      isn't dragged while the unequip travels to the server
--   3. freeze until the server has caught up
-- The tool is never destroyed here: that only removes your copy,
-- while the server keeps it, still welded to your arm.
RejectTool = function(tool, why)

    if not tool then return end

    local first = not ForeignTools[tool]
    ForeignTools[tool] = true
    OwnTools[tool] = nil

    if Character and Humanoid and tool.Parent == Character then
        pcall(function() Humanoid:UnequipTools() end)
    end

    local handle = tool:FindFirstChild("Handle")

    if handle and handle:IsA("BasePart")
        and handle:IsDescendantOf(Workspace) then

        local ok, joints = pcall(function() return handle:GetJoints() end)
        if ok and joints then
            for _, j in ipairs(joints) do
                pcall(function() j:Destroy() end)
            end
        end

        ShieldPart(handle)
    end

    -- freeze on arrival, not on displacement
    EngageAnchor("tool arrived: " .. tostring(tool.Name))

    -- the same tool coming back: handled again, logged once
    if not first then return end

    local now = os.clock()
    table.insert(BlockedToolTimes, now)

    for i = #BlockedToolTimes, 1, -1 do
        if now - BlockedToolTimes[i] > 5 then
            table.remove(BlockedToolTimes, i)
        end
    end

    if #BlockedToolTimes >= 3 then
        LockdownUntil = now + CFG.LockdownDuration
    end

    Block("TOOL BLOCKED", (tool.Name or "?") .. " - " .. why, "tool_blocked")
end


-- Every frame: cut any joint that ties one of our parts to a part
-- we do not own.
--
-- This used to walk host:GetChildren(), which was wrong. A weld is
-- parented wherever its creator chose — usually the attacker's
-- Handle or their character, never your arm. GetJoints() returns
-- every joint touching a part no matter where the joint lives, so
-- it finds the ones GetChildren() could never see.
--
-- The carry works precisely because the Tool stays parented to the
-- attacker: you hold it, so RightGrip runs from your arm to their
-- Handle. That crosses the character boundary, which makes it
-- unambiguous — no legitimate joint on your body points at another
-- player's part.

local BodyPartNames = {
    "HumanoidRootPart", "Torso", "UpperTorso", "LowerTorso", "Head",
    "Right Arm", "Left Arm", "RightHand", "LeftHand",
    "RightUpperArm", "RightLowerArm", "LeftUpperArm", "LeftLowerArm",
    "Right Leg", "Left Leg", "RightFoot", "LeftFoot",
    "RightUpperLeg", "RightLowerLeg", "LeftUpperLeg", "LeftLowerLeg",
}


local function SweepGripWelds()

    if not CFG.GripSweep or not Character then return end

    local cut = 0
    local culprit

    for _, name in ipairs(BodyPartNames) do

        local part = Character:FindFirstChild(name)

        if CanQueryJoints(part) then

            local ok, joints = pcall(function()
                return part:GetJoints()
            end)

            if ok and joints then
                for _, joint in ipairs(joints) do

                    local p0, p1 = joint.Part0, joint.Part1

                    if p0 and p1 then

                        local other = (p0 == part) and p1 or p0

                        -- crosses out of our character = carry link
                        if other and not IsMine(other) then

                            -- a seat we genuinely sat in is allowed
                            local isSeat = (joint.Name == "SeatWeld")
                                and Humanoid and Humanoid.SeatPart ~= nil

                            if not isSeat then
                                pcall(function() joint:Destroy() end)
                                cut += 1
                                culprit = culprit or other
                            end
                        end
                    end
                end
            end
        end
    end

    if cut > 0 then

        Stats.GripSevered += cut

        -- Freeze immediately. The drag is already in flight and the
        -- whole attack resolves in one or two frames, so severing
        -- alone can still leave you mid-flight.
        EngageAnchor("carry link on " ..
            tostring(culprit and culprit.Name or "?"))

        if culprit then
            ShieldPart(culprit)

            local owner = GetPlayerFromPart(culprit)
            if owner and owner ~= LocalPlayer then
                local threat = AddThreat(owner, 30)
                threat.Flagged  = true
                threat.Critical = true
                ShieldPlayer(owner)
            end

            Block("GRIP",
                "Severed " .. cut .. " carry link(s) to "
                .. culprit:GetFullName(),
                "grip_sever")
        end

        LockdownUntil = os.clock() + CFG.LockdownDuration
    end

    return cut > 0
end


-- Every physics step and render frame: a foreign tool still in your
-- character is unequipped again. Cheap: a handful of children.
local function PurgeForeignTools()

    if not Character or not Humanoid then return end

    for _, obj in ipairs(Character:GetChildren()) do
        if obj:IsA("Tool") and IsForeignTool(obj) then
            RejectTool(obj, "pickup blocked")
        end
    end
end


-- A tool landing in your character. Yours: allowed. Anything else:
-- rejected on the spot, before the next physics step.
local function ScreenIncomingTool(tool)

    if not tool or not tool:IsA("Tool") then return end

    if IsForeignTool(tool) then
        LogEvent("TOOL SEEN",
            tool.Name .. " -> " .. tostring(tool.Parent and tool.Parent.Name))
        RejectTool(tool, ToolSeenOutside[tool]
            and "picked up from the world"
            or "never came out of your backpack")
        return
    end

    BaselineToolGrip(tool)
end


--============================================================
-- HIDDEN TOOLS   (v3)
--============================================================
--
-- After the unequip a blocked tool sits in your Backpack on the
-- server. It is harmless there, but it shows in your hotbar and one
-- keypress equips it again, so it is taken out of your view. Nothing
-- is deleted on the server; RESTORE puts them back.
--============================================================

local function HideTool(tool, why, force)

    if not (CFG.HideForeignTools or force) then return end
    if not tool or not Backpack or tool.Parent ~= Backpack then return end

    for _, h in ipairs(HiddenTools) do
        if h.tool == tool then return end
    end

    local ok = pcall(function() tool.Parent = nil end)
    if not ok then return end

    table.insert(HiddenTools, { tool = tool, name = tool.Name, why = why, t = os.clock() })
    while #HiddenTools > 60 do
        table.remove(HiddenTools, 1)
    end

    Stats.ToolsHidden += 1
    LogEvent("TOOL HIDDEN", tool.Name .. " - " .. tostring(why))
end


local function RestoreHiddenTools()

    local restored = 0

    for _, h in ipairs(HiddenTools) do
        local tool = h.tool
        if tool and Backpack then
            ForeignTools[tool] = nil
            OwnTools[tool] = true
            local ok = pcall(function() tool.Parent = Backpack end)
            if ok then restored += 1 end
        end
    end

    table.clear(HiddenTools)
    LogEvent("TOOLS", restored .. " hidden tool(s) restored")
    return restored
end


-- Takes every picked-up / blocked tool out of your hotbar now.
local function CleanInventory(force)

    if not Backpack then return 0 end

    local n = 0

    for _, tool in ipairs(Backpack:GetChildren()) do
        if tool:IsA("Tool") and not IsAllowedTool(tool)
            and (ForeignTools[tool]
                or (ToolSeenOutside[tool] and not OwnTools[tool])) then
            ForeignTools[tool] = true
            HideTool(tool, "cleaned", force)
            n += 1
        end
    end

    return n
end


--============================================================
--                 POSITION ASSERTION
--============================================================
--
-- Runs after the solver. You are network owner of your own
-- character, so a CFrame you write post-physics is what the
-- server receives — it overwrites whatever the weld did.
--
-- Only fires on displacement no locomotion can produce, so
-- normal movement, jumping and falling pass straight through.
--============================================================

local function AssertPosition()

    if not Root or not Root.Parent then return end
    if not CFG.TeleportGuard then return end

    local now = os.clock()
    if now < TeleportGraceUntil then
        AuthorizedCFrame = Root.CFrame
        return
    end

    local current = Root.CFrame

    if not IsFiniteCFrame(current) then
        if AuthorizedCFrame then
            pcall(function() Root.CFrame = AuthorizedCFrame end)
        end
        EngageAnchor("non-finite CFrame")
        return
    end

    if AuthorizedCFrame then

        local jump = (current.Position - AuthorizedCFrame.Position).Magnitude

        if jump > CFG.TeleportSnapDistance then

            -- Freeze first, then restore. Anchoring before the write
            -- stops the weld reapplying between the two operations.
            EngageAnchor("dragged " .. math.floor(jump) .. " studs")

            pcall(function()
                Root.CFrame = AuthorizedCFrame
                Root.AssemblyLinearVelocity  = Vector3.zero
                Root.AssemblyAngularVelocity = Vector3.zero
            end)

            Stats.PositionAssert += 1

            SweepGripWelds()
            ScanAssembly()

            LockdownUntil    = now + CFG.LockdownDuration
            LastSelfPosition = AuthorizedCFrame.Position

            Block("ASSERT",
                "Overwrote a " .. math.floor(jump) .. " stud drag",
                "assert")

            return
        end
    end

    -- movement was plausible; accept it as the new authority
    AuthorizedCFrame = current
end


--============================================================
--                  TELEPORT / VOID GUARD
--============================================================
--
-- A weld drag covers hundreds of studs in a single frame. The
-- observed-speed check catches that eventually, but RecoverSelf
-- only rolls your position back after three launches, which is
-- two launches too late when the destination is the void.
--
-- This restores immediately, on the first frame, before the
-- camera has even interpolated.
--============================================================

local function CheckTeleport(dt)

    if not CFG.TeleportGuard then return end
    if not Root or not Root.Parent then return end
    if not SafeCFrame then return end

    local now = os.clock()
    if now < TeleportGraceUntil then return end

    local position = Root.Position

    ----------------------------------------------------------
    -- Under the map
    ----------------------------------------------------------

    local floor = VoidBaseHeight + CFG.VoidMargin

    if position.Y < floor then

        pcall(function()
            Root.CFrame = SafeCFrame
            Root.AssemblyLinearVelocity  = Vector3.zero
            Root.AssemblyAngularVelocity = Vector3.zero
        end)

        Stats.Teleport += 1
        SweepGripWelds()
        ScanAssembly()

        Block("TELEPORT",
            "Recovered from void at Y=" .. math.floor(position.Y),
            "void")

        return true
    end

    ----------------------------------------------------------
    -- Single-frame jump
    ----------------------------------------------------------

    if LastSelfPosition then

        local jump = (position - LastSelfPosition).Magnitude

        if jump > CFG.TeleportSnapDistance then

            pcall(function()
                Root.CFrame = SafeCFrame
                Root.AssemblyLinearVelocity  = Vector3.zero
                Root.AssemblyAngularVelocity = Vector3.zero
            end)

            Stats.Teleport += 1

            -- whatever dragged us is still attached; cut it now
            SweepGripWelds()
            ScanAssembly()

            LockdownUntil = now + CFG.LockdownDuration

            Block("TELEPORT",
                "Snapped " .. math.floor(jump) .. " studs in one frame",
                "teleport_snap")

            LastSelfPosition = SafeCFrame.Position
            return true
        end
    end

    return false
end


--============================================================
--                      SEAT GUARD
--============================================================
--
-- Sitting welds you to the seat with a SeatWeld, which is the
-- cleanest weld-based fling there is: the exploiter seats you,
-- then moves the seat. You cannot out-clamp a SeatWeld either,
-- so the response is to unseat.
--============================================================

local function CheckSeat()

    if not CFG.SeatGuard then return end
    if not Humanoid or not Root then return end

    local seat = Humanoid.SeatPart
    if not seat then return end

    local ok, velocity = pcall(function()
        return seat.AssemblyLinearVelocity
    end)

    if not ok or not IsFiniteVector(velocity) then
        pcall(function() Humanoid.Sit = false end)
        Block("SEAT", "Seat had invalid physics", "seat_nan")
        return
    end

    if velocity.Magnitude > CFG.SeatMaxSpeed then

        pcall(function()
            Humanoid.Sit = false
            Humanoid.Jump = true
        end)

        ShieldPart(seat)

        Block("SEAT",
            "Ejected from seat moving " .. math.floor(velocity.Magnitude),
            "seat_speed")
    end
end


--============================================================
--                     TOUCH GUARD
--============================================================
--
-- firetouchinterest spam is how a remote Handle is made to
-- "hit" you repeatedly without ever physically arriving. The
-- touches themselves are cheap to count, and a burst of them
-- from a foreign handle is a very clean signal.
--============================================================

local function NoteForeignTouch(otherPart)

    if not CFG.TouchGuard then return end
    if not otherPart then return end

    local now = os.clock()

    -- drop anything outside the window
    for i = #TouchEvents, 1, -1 do
        if now - TouchEvents[i] > CFG.TouchWindow then
            table.remove(TouchEvents, i)
        end
    end

    table.insert(TouchEvents, now)

    if #TouchEvents >= CFG.TouchThreshold then

        table.clear(TouchEvents)

        ShieldPart(otherPart)

        local owner = GetPlayerFromPart(otherPart)
        if owner and owner ~= LocalPlayer then
            local threat = AddThreat(owner, 14)
            threat.Flagged = true
            ShieldPlayer(owner)
        end

        Block("TOUCH",
            "Touch spam from " .. otherPart.Name
            .. (owner and (" / " .. owner.Name) or ""),
            "touch_spam")
    end
end


local function HookTouchGuard()

    if not CFG.TouchGuard or not Root then return end

    table.insert(CharacterConnections,
        Root.Touched:Connect(function(other)

            if not other or not other.Parent then return end
            if IsMine(other) then return end

            -- only accessory / tool handles and loose parts matter
            if other.Name == "Handle" or not IsPlayerCharacterPart(other) then
                NoteForeignTouch(other)
            end
        end)
    )
end


--============================================================
-- SELF RECOVERY
--============================================================

local function RecoverSelf(category, reason)

    if not Root or not Root.Parent then return end

    local now = os.clock()

    ----------------------------------------------------------
    -- Cut BEFORE the cooldown check.
    --
    -- The cooldown exists to stop log spam and clamp thrash, but
    -- severing a weld is idempotent and must never be skipped:
    -- a second toolkill arriving inside the 0.25 s window would
    -- otherwise go completely unhandled.
    ----------------------------------------------------------

    ScanAssembly()

    if now < RecoveryUntil then return end
    RecoveryUntil = now + 0.25

    Stats.Recoveries += 1

    ----------------------------------------------------------
    -- Launch history
    ----------------------------------------------------------

    table.insert(LaunchTimes, now)

    while #LaunchTimes > 0 and now - LaunchTimes[1] > 4 do
        table.remove(LaunchTimes, 1)
    end

    ----------------------------------------------------------
    -- Current physics
    ----------------------------------------------------------

    local velocity = Root.AssemblyLinearVelocity
    if not IsFiniteVector(velocity) then velocity = Vector3.zero end

    local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
    local y = velocity.Y

    if horizontal.Magnitude > CFG.SelfMaxHorizontal then
        if Humanoid and Humanoid.MoveDirection.Magnitude > 0.05 then
            horizontal = Humanoid.MoveDirection.Unit
                * math.min(Humanoid.WalkSpeed, 35)
        else
            horizontal = Vector3.zero
        end
    end

    -- preserve normal jumping / falling
    if math.abs(y) > CFG.SelfMaxVertical then
        y = math.clamp(y,
            -CFG.SelfMaxVertical * 0.55,
             CFG.SelfMaxVertical * 0.55)
    end

    pcall(function()
        Root.AssemblyLinearVelocity  = Vector3.new(horizontal.X, y, horizontal.Z)
        Root.AssemblyAngularVelocity = Vector3.zero
    end)

    Block(category, reason)

    ----------------------------------------------------------
    -- Repeated launch: something persistent is attached
    ----------------------------------------------------------

    ----------------------------------------------------------
    -- Escalation
    ----------------------------------------------------------

    local recent = 0
    for _, t in ipairs(LaunchTimes) do
        if now - t <= CFG.LockdownTriggerWindow then recent += 1 end
    end

    if recent >= CFG.LockdownTriggerCount then
        local wasLocked = os.clock() < LockdownUntil
        LockdownUntil = now + CFG.LockdownDuration
        if not wasLocked then
            Stats.Lockdowns += 1
            Block("LOCKDOWN",
                "Sustained attack — scans to every frame for "
                .. CFG.LockdownDuration .. "s",
                "lockdown")
        end
    end

    if #LaunchTimes >= 3 then

        Stats.RepeatedLaunch += 1

        -- re-verify the things that survive a velocity clamp
        CheckJoints()
        ScanAssembly()

        if SafeCFrame and now > TeleportGraceUntil then

            local distance = (Root.Position - SafeCFrame.Position).Magnitude

            if distance > CFG.SelfSevereRollbackDistance then
                pcall(function()
                    Root.CFrame = SafeCFrame
                    Root.AssemblyLinearVelocity  = Vector3.zero
                    Root.AssemblyAngularVelocity = Vector3.zero
                end)

                Block("SELF POSITION", "Repeated severe launch recovered")
            end
        end
    end
end


--============================================================
-- SELF PHYSICS
--============================================================

local function CheckSelfPhysics(dt)

    if not CFG.SelfScan then return end
    if not Root or not Root.Parent then return end

    local velocity = Root.AssemblyLinearVelocity
    local angular  = Root.AssemblyAngularVelocity

    if not IsFiniteVector(velocity) or not IsFiniteVector(angular) then
        RecoverSelf("SELF VELOCITY", "Invalid physics")
        return
    end

    local horizontal = FlatMagnitude(velocity)
    local vertical   = math.abs(velocity.Y)
    local total      = velocity.Magnitude
    local spin       = angular.Magnitude

    if horizontal > CFG.SelfMaxHorizontal then
        RecoverSelf("SELF VELOCITY", "Horizontal " .. math.floor(horizontal))
        LastSelfVelocity = velocity
        return
    end

    if vertical > CFG.SelfMaxVertical then
        RecoverSelf("SELF VELOCITY", "Vertical " .. math.floor(vertical))
        LastSelfVelocity = velocity
        return
    end

    if total > CFG.SelfMaxTotal then
        RecoverSelf("SELF VELOCITY", "Total " .. math.floor(total))
        LastSelfVelocity = velocity
        return
    end

    if spin > CFG.SelfMaxAngular then
        RecoverSelf("SELF SPIN", "Angular " .. math.floor(spin))
        LastSelfVelocity = velocity
        return
    end

    ----------------------------------------------------------
    -- Acceleration
    ----------------------------------------------------------

    local validDt = ValidDt(dt)

    if validDt and LastSelfVelocity
        and LastSelfVelocity.Magnitude > CFG.SelfAccelerationMinimum
        and velocity.Magnitude > CFG.SelfAccelerationMinimum then

        local acceleration = (velocity - LastSelfVelocity).Magnitude / validDt

        if acceleration > CFG.SelfMaxAcceleration then
            RecoverSelf("SELF ACCELERATION", "Acceleration " .. math.floor(acceleration))
            LastSelfVelocity = velocity
            return
        end
    end

    LastSelfVelocity = velocity
end


--============================================================
-- SELF POSITION
--============================================================

local function CheckSelfPosition(dt)

    if not Root or not Root.Parent then return end

    local position = Root.Position

    if not IsFiniteVector(position) then
        RecoverSelf("SELF POSITION", "Invalid position")
        return
    end

    local validDt = ValidDt(dt)

    if validDt and LastSelfPosition and os.clock() > TeleportGraceUntil then

        local distance      = (position - LastSelfPosition).Magnitude
        local observedSpeed = distance / validDt

        if observedSpeed > CFG.SelfMaxObservedSpeed then
            RecoverSelf("SELF POSITION",
                "Observed displacement " .. math.floor(observedSpeed) .. " studs/s")
            return
        end
    end

    LastSelfPosition = position
end


--============================================================
-- SAFE POSITION
--============================================================

local function RecordSafePosition()

    if not Root or not Root.Parent then return end

    local now = os.clock()
    if now - LastSafeSnapshot < CFG.SafeSnapshotInterval then return end
    if not Humanoid then return end

    local grounded = Humanoid.FloorMaterial ~= Enum.Material.Air
    local velocity = Root.AssemblyLinearVelocity

    if grounded and IsFiniteVector(velocity) and velocity.Magnitude < 75 then
        SafeCFrame = Root.CFrame
        LastSafeSnapshot = now

        -- a grounded, slow frame is by definition a legitimate one
        if not WasAnchored then
            AuthorizedCFrame = Root.CFrame
        end
    end
end


--============================================================
-- REANIMATION SIGNATURES
--============================================================

local function HasUhhhhhhSignature(part)
    if not part then return false end
    return part:GetAttribute("_Uhhhhhh_HasCollide")  ~= nil
        or part:GetAttribute("_Uhhhhhh_LastPosition") ~= nil
        or part:GetAttribute("_Uhhhhhh_ClaimTime")    ~= nil
end


local function IsHandleCandidate(part)
    if not part or not part:IsA("BasePart") then return false end
    if part.Name ~= "Handle" then return false end
    local parent = part.Parent
    if not parent then return false end
    return parent:IsA("Accessory") or parent:IsA("Tool")
end


--============================================================
-- ANALYZE REANIM PART
--============================================================

local function AnalyzeReanimPart(part, owner)

    if not part or not part.Parent or not Root then return false end
    if part:IsDescendantOf(Character) then return false end

    local position = part.Position
    local velocity = part.AssemblyLinearVelocity
    local angular  = part.AssemblyAngularVelocity

    if not IsFiniteVector(velocity) or not IsFiniteVector(angular) then
        return false
    end

    local offset   = position - Root.Position
    local distance = offset.Magnitude

    if distance > CFG.ReanimRadius then return false end

    local speed = velocity.Magnitude
    local spin  = angular.Magnitude

    local attributeSignature = HasUhhhhhhSignature(part)
    local handleCandidate    = IsHandleCandidate(part)

    local incomingSpeed = 0
    if distance > 0.1 and speed > 0.1 then
        incomingSpeed = velocity:Dot(-offset.Unit)
    end

    local incoming = incomingSpeed > CFG.ReanimIncomingSpeed

    local detached = false
    if owner and owner.Character then
        local ownerRoot = owner.Character:FindFirstChild("HumanoidRootPart")
        if ownerRoot then
            detached = (position - ownerRoot.Position).Magnitude
                > CFG.ReanimDetachedDistance
        end
    end

    local predictedDistance, _, predictedIncoming =
        PredictClosestApproach(Root.Position, position, velocity,
            CFG.ReanimPredictionTime)

    local predictedImpact = predictedIncoming
        and predictedDistance <= CFG.ReanimImpactDistance
        and speed > 70

    local extremeSpeed = speed > CFG.ReanimHandleSpeed
    local extremeSpin  = spin  > CFG.ReanimHandleSpin

    local suspicious = false

    if attributeSignature then
        if extremeSpeed or extremeSpin or incoming
            or predictedImpact or detached then
            suspicious = true
        end
    end

    if handleCandidate
        and (extremeSpeed or extremeSpin or incoming or predictedImpact) then
        suspicious = true
    end

    if not suspicious then return false end

    ShieldPart(part)

    if owner then
        local threat = AddThreat(owner, 12)
        threat.Flagged  = true
        threat.Critical = true
        threat.Score = math.max(threat.Score, CFG.PlayerCriticalThreshold)
        ShieldPlayer(owner)
    end

    local reason
    if attributeSignature   then reason = "Uhhhhhh signature"
    elseif predictedImpact  then reason = "predicted impact"
    elseif extremeSpin      then reason = "extreme spin"
    elseif incoming         then reason = "incoming"
    elseif detached         then reason = "detached"
    else                         reason = "extreme velocity" end

    Block(
        attributeSignature and "REANIMATE ATTRIBUTE" or "REANIMATE HANDLE",
        (owner and owner.Name or "unknown") .. " / " .. part.Name .. " / " .. reason,
        attributeSignature and "reanim_attribute" or "reanim_handle"
    )

    return true
end


--============================================================
-- SCAN PLAYER REANIMATION
--============================================================

local function ScanPlayerReanimation(player)

    if player == LocalPlayer then return end
    if not Root or not Root.Parent then return end

    local character = player.Character
    if not character then return end

    local targetRoot = character:FindFirstChild("HumanoidRootPart")
    if not targetRoot then return end

    if (targetRoot.Position - Root.Position).Magnitude > CFG.ReanimRadius then
        return
    end

    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Accessory") or child:IsA("Tool") then
            local handle = child:FindFirstChild("Handle")
            if handle and handle:IsA("BasePart") then
                if AnalyzeReanimPart(handle, player) then return end
            end
        end
    end

    local physicsRoot = character:FindFirstChild("PhysicsRepRootPart")
    if physicsRoot and physicsRoot:IsA("BasePart") then
        AnalyzeReanimPart(physicsRoot, player)
    end
end


--============================================================
-- DETACHED REANIMATION SCAN
--============================================================

local function ScanDetachedReanimation()

    if not Root or not Root.Parent then return end

    DetachedOverlap.FilterDescendantsInstances = { Character }

    local parts
    local success = pcall(function()
        parts = Workspace:GetPartBoundsInRadius(
            Root.Position, CFG.ReanimRadius, DetachedOverlap)
    end)

    if not success or not parts then return end

    for _, part in ipairs(parts) do

        if not part:IsA("BasePart") then continue end
        if part.Anchored then continue end
        if IsPlayerCharacterPart(part) then continue end

        local signature = HasUhhhhhhSignature(part)
        local handle    = IsHandleCandidate(part)

        if not signature and not handle then continue end

        if AnalyzeReanimPart(part, nil) then return end
    end
end


--============================================================
-- NEARBY PHYSICS OBJECTS
--============================================================

local function RefreshPhysicsFilter()

    local filter = {}

    if Character then table.insert(filter, Character) end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            table.insert(filter, player.Character)
        end
    end

    PhysicsOverlap.FilterDescendantsInstances = filter
    PhysicsFilterDirty = false
    LastPhysicsFilterRefresh = os.clock()
end


local function ScanNearbyPhysics()

    if not Root or not Root.Parent then return end

    if PhysicsFilterDirty
        or os.clock() - LastPhysicsFilterRefresh > 0.50 then
        RefreshPhysicsFilter()
    end

    local parts
    local success = pcall(function()
        parts = Workspace:GetPartBoundsInRadius(
            Root.Position, CFG.NearbyPhysicsRadius, PhysicsOverlap)
    end)

    if not success or not parts then return end

    for _, part in ipairs(parts) do

        if not part:IsA("BasePart") then continue end
        if part.Anchored then continue end
        if IsPlayerCharacterPart(part) then continue end
        if HasUhhhhhhSignature(part) then continue end

        local velocity = part.AssemblyLinearVelocity
        local angular  = part.AssemblyAngularVelocity

        if not IsFiniteVector(velocity) or not IsFiniteVector(angular) then
            continue
        end

        local speed = velocity.Magnitude
        local spin  = angular.Magnitude

        local offset   = part.Position - Root.Position
        local distance = offset.Magnitude

        local incomingSpeed = 0
        if distance > 0.1 and speed > 0.1 then
            incomingSpeed = velocity:Dot(-offset.Unit)
        end

        local predictedDistance, predictedTime, predictedIncoming =
            PredictClosestApproach(Root.Position, part.Position, velocity,
                CFG.NearbyPredictionTime)

        local predictedImpact = predictedIncoming
            and predictedDistance <= CFG.NearbyImpactDistance
            and speed > 100
            and incomingSpeed > 110

        local suspicious =
            speed > CFG.NearbyExtremeSpeed
            or spin > CFG.NearbyExtremeSpin
            or incomingSpeed > CFG.NearbyIncomingSpeed
            or predictedImpact

        if not suspicious then continue end

        ShieldPart(part)

        local reason
        if predictedImpact then
            reason = "predicted impact in " .. string.format("%.2f", predictedTime) .. "s"
        elseif spin > CFG.NearbyExtremeSpin then
            reason = "spin " .. math.floor(spin)
        elseif incomingSpeed > CFG.NearbyIncomingSpeed then
            reason = "incoming " .. math.floor(incomingSpeed)
        else
            reason = "velocity " .. math.floor(speed)
        end

        Block("PHYSICS OBJECT", part.Name .. " / " .. reason)

        if os.clock() >= RecoveryUntil then
            RecoverSelf("SELF VELOCITY", "Nearby physics attack")
        end

        return
    end
end


--============================================================
-- TETHERS AND FORCES
--============================================================

-- A link is "external" when exactly one end is on the character.
local function IsExternalTether(obj)

    if not Character then return false end

    if RigidJointClasses[obj.ClassName] or obj:IsA("WeldConstraint") then
        local p0, p1 = obj.Part0, obj.Part1
        if not p0 or not p1 then return false end
        return IsMine(p0) ~= IsMine(p1)
    end

    if obj:IsA("Constraint") and not obj:IsA("NoCollisionConstraint") then
        local a0, a1 = obj.Attachment0, obj.Attachment1
        if not a0 or not a1 then return false end
        return IsMine(a0) ~= IsMine(a1)
    end

    return false
end


local function RemoveExternalTethers()

    if not CFG.RemoveExternalTethers or not Character then return end

    for _, obj in ipairs(Character:GetDescendants()) do
        if IsExternalTether(obj) then
            Block("TETHER", "Removed external " .. obj.ClassName)
            pcall(function() obj:Destroy() end)
        end
    end
end


local function RemoveInjectedForces()

    if not CFG.RemoveInjectedForces or not Character then return end

    for _, obj in ipairs(Character:GetDescendants()) do
        if BadForceClasses[obj.ClassName] then
            if obj:GetAttribute("AntiFlingAllowed") ~= true then
                Block("FORCE", "Removed " .. obj.ClassName)
                pcall(function() obj:Destroy() end)
            end
        end
    end
end


--============================================================
-- EVENT-DRIVEN OBJECT PROTECTION
--============================================================

local function InspectNewObject(obj)

    if not obj or not obj.Parent then return end

    ----------------------------------------------------------
    -- FORCE
    ----------------------------------------------------------

    if BadForceClasses[obj.ClassName] then
        if CFG.RemoveInjectedForces
            and obj:GetAttribute("AntiFlingAllowed") ~= true then
            Block("FORCE", "Removed " .. obj.ClassName)
            pcall(function() obj:Destroy() end)
        end
        return
    end

    ----------------------------------------------------------
    -- RIGID LINK  — the toolkill vector, checked immediately
    ----------------------------------------------------------

    if RigidJointClasses[obj.ClassName] then

        task.spawn(function()

            -- Part0/Part1 are often set a frame or two after parenting
            local p0, p1
            for _ = 1, 6 do
                if not obj or not obj.Parent then return end
                p0, p1 = obj.Part0, obj.Part1
                if p0 and p1 then break end
                RunService.Heartbeat:Wait()
            end

            if not obj or not obj.Parent then return end
            if not p0 or not p1 then return end

            if IsMine(p0) ~= IsMine(p1) then

                -- SeatWeld from a seat we actually sat in is allowed
                local isSeatWeld = (obj.Name == "SeatWeld")
                    and Humanoid and Humanoid.SeatPart ~= nil

                if not isSeatWeld then
                    Block("ASSEMBLY",
                        "Blocked incoming " .. obj.ClassName
                        .. " from " .. tostring((not IsMine(p0)) and p0.Name or p1.Name),
                        "link_added")

                    pcall(function() obj:Destroy() end)

                    local foreign = (not IsMine(p0)) and p0 or p1
                    ShieldPart(foreign)

                    local owner = GetPlayerFromPart(foreign)
                    if owner and owner ~= LocalPlayer then
                        local threat = AddThreat(owner, 20)
                        threat.Flagged  = true
                        threat.Critical = true
                    end
                end
            end
        end)

        return
    end

    ----------------------------------------------------------
    -- TOOL
    ----------------------------------------------------------

    if obj:IsA("Tool") then
        BaselineToolGrip(obj)
        task.defer(function() AuditTool(obj) end)
        return
    end

    ----------------------------------------------------------
    -- CONSTRAINT TETHER
    ----------------------------------------------------------

    if CFG.RemoveExternalTethers
        and (obj:IsA("Constraint") or obj:IsA("WeldConstraint")) then

        task.defer(function()
            if obj and obj.Parent and IsExternalTether(obj) then
                Block("TETHER", "Removed external " .. obj.ClassName)
                pcall(function() obj:Destroy() end)
            end
        end)
    end
end


--============================================================
-- WORKSPACE CONSTRAINT WATCHER
--============================================================
--
-- Constraints do not have to live inside your character to
-- affect it. An exploiter will usually parent them to Workspace
-- so a character-only scan never sees them.
--============================================================

local function HookWorkspaceWatcher()

    if not CFG.WatchWorkspaceConstraints then return end

    table.insert(GlobalConnections,
        Workspace.DescendantAdded:Connect(function(obj)

            -- cheap class test first; this fires constantly
            if not (TetherConstraintClasses[obj.ClassName]
                or RigidJointClasses[obj.ClassName]) then
                return
            end

            if not Character then return end

            -- An exploiter usually parents first and assigns Part0/Part1
            -- after, so a single deferred check sees an empty joint and
            -- lets it through. Re-check over the next few frames.
            task.spawn(function()
                for _ = 1, 6 do
                    if not obj or not obj.Parent then return end

                    if not obj:IsDescendantOf(Character)
                        and IsExternalTether(obj) then

                        Block("TETHER",
                            "Removed workspace-side " .. obj.ClassName,
                            "ws_tether")

                        pcall(function() obj:Destroy() end)
                        return
                    end

                    RunService.Heartbeat:Wait()
                end
            end)
        end)
    )
end


--============================================================
-- THREAT PLAYER SCAN
--============================================================

local function ScanPlayer(player)

    if player == LocalPlayer then return end
    if not Root or not Root.Parent then return end

    local character = player.Character
    if not character then return end

    local targetRoot = character:FindFirstChild("HumanoidRootPart")
    if not targetRoot then return end

    local data     = GetThreat(player)
    local offset   = targetRoot.Position - Root.Position
    local distance = offset.Magnitude

    if distance > CFG.PlayerWatchRadius then return end

    local velocity = targetRoot.AssemblyLinearVelocity
    local angular  = targetRoot.AssemblyAngularVelocity

    if not IsFiniteVector(velocity) or not IsFiniteVector(angular) then
        AddThreat(player, 8)
        return
    end

    ----------------------------------------------------------
    -- Also inspect R6 torso
    ----------------------------------------------------------

    local torso = character:FindFirstChild("Torso")
    local torsoVelocity = Vector3.zero
    local torsoSpin = 0

    if torso and torso:IsA("BasePart") then
        torsoVelocity = torso.AssemblyLinearVelocity
        torsoSpin     = torso.AssemblyAngularVelocity.Magnitude
    end

    local total      = velocity.Magnitude
    local horizontal = FlatMagnitude(velocity)
    local vertical   = math.abs(velocity.Y)
    local spin       = angular.Magnitude

    if torsoVelocity.Magnitude > total then
        total = torsoVelocity.Magnitude
    end
    if FlatMagnitude(torsoVelocity) > horizontal then
        horizontal = FlatMagnitude(torsoVelocity)
    end
    if math.abs(torsoVelocity.Y) > vertical then
        vertical = math.abs(torsoVelocity.Y)
    end
    spin = math.max(spin, torsoSpin)

    ----------------------------------------------------------
    -- Observed movement speed
    ----------------------------------------------------------

    local now = os.clock()
    local observedSpeed = 0
    local elapsed = now - (data.LastPositionTime or now)
    local validDt = ValidDt(elapsed)

    if validDt and data.LastPosition then
        observedSpeed = (targetRoot.Position - data.LastPosition).Magnitude / validDt
    end

    data.LastPosition     = targetRoot.Position
    data.LastPositionTime = now

    ----------------------------------------------------------
    -- Incoming velocity
    ----------------------------------------------------------

    local incomingSpeed = 0
    if distance > 0.1 and total > 0.1 then
        incomingSpeed = velocity:Dot(
            -Vector3.new(offset.X, 0, offset.Z).Unit)
    end

    local predictedDistance, predictedTime, predictedIncoming =
        PredictClosestApproach(Root.Position, targetRoot.Position, velocity,
            CFG.PlayerPredictionTime)

    local predictedImpact = predictedIncoming
        and predictedDistance <= CFG.PlayerImpactDistance
        and (total > 90 or incomingSpeed > 95)

    ----------------------------------------------------------
    -- Abnormal signals
    ----------------------------------------------------------

    local badHorizontal = horizontal    > CFG.PlayerMaxHorizontal
    local badVertical   = vertical      > CFG.PlayerMaxVertical
    local badTotal      = total         > CFG.PlayerMaxTotal
    local badSpin       = spin          > CFG.PlayerMaxAngular
    local badObserved   = observedSpeed > CFG.PlayerMaxObservedSpeed
    local badIncoming   = incomingSpeed > CFG.PlayerIncomingSpeed

    local signals = 0
    if badHorizontal  then signals += 1 end
    if badVertical    then signals += 1 end
    if badTotal       then signals += 1 end
    if badSpin        then signals += 1 end
    if badObserved    then signals += 1 end
    if badIncoming    then signals += 1 end
    if predictedImpact then signals += 1 end

    if signals > 0 then
        data.BadSamples = (data.BadSamples or 0) + 1
    else
        data.BadSamples = math.max(0, (data.BadSamples or 0) - 1)
    end

    local points = 0
    if badHorizontal  then points += 4 end
    if badVertical    then points += 3 end
    if badTotal       then points += 4 end
    if badSpin        then points += 4 end
    if badObserved    then points += 4 end
    if badIncoming    then points += 3 end
    if predictedImpact then points += 5 end

    if points > 0 then
        if data.BadSamples >= CFG.PlayerBadSamplesRequired then
            AddThreat(player, points)
        else
            AddThreat(player, math.min(2, points))
        end
    end

    if badSpin then
        Block("PLAYER SPIN", player.Name .. " / " .. math.floor(spin),
            "player_spin_" .. player.UserId)
    end

    if badIncoming and distance <= 40 then
        Block("PLAYER APPROACH",
            player.Name .. " / " .. math.floor(incomingSpeed),
            "player_approach_" .. player.UserId)
    end

    if predictedImpact then
        Block("PLAYER TRAJECTORY",
            player.Name .. " / " .. string.format("%.2f", predictedTime) .. "s",
            "player_trajectory_" .. player.UserId)
    end

    if data.Flagged then
        ShieldPlayer(player)
    end
end


--============================================================
-- MAINTAIN PLAYER THREATS
--============================================================

local function MaintainThreats()

    local now = os.clock()

    for id, data in pairs(PlayerThreats) do

        local player = data.Player

        if not player or not player.Parent then
            PlayerThreats[id] = nil
            continue
        end

        local character  = player.Character
        local targetRoot = character
            and character:FindFirstChild("HumanoidRootPart")

        if not targetRoot then continue end
        if not Root or not Root.Parent then continue end

        local distance = (targetRoot.Position - Root.Position).Magnitude

        DecayThreat(data)

        if data.Flagged and distance <= CFG.PlayerWatchRadius then

            ShieldPlayer(player)

            local velocity = targetRoot.AssemblyLinearVelocity
            local angular  = targetRoot.AssemblyAngularVelocity

            local normal =
                IsFiniteVector(velocity)
                and IsFiniteVector(angular)
                and FlatMagnitude(velocity) <= CFG.PlayerMaxHorizontal
                and math.abs(velocity.Y)    <= CFG.PlayerMaxVertical
                and velocity.Magnitude      <= CFG.PlayerMaxTotal
                and angular.Magnitude       <= CFG.PlayerMaxAngular

            if normal then
                data.SafeSince = data.SafeSince or now
            else
                data.SafeSince = nil
            end
        end

        if data.Flagged and data.SafeSince
            and now - data.SafeSince > CFG.PlayerReleaseDelay
            and distance > 40 then

            data.Flagged  = false
            data.Critical = false
            PlayerThreats[id] = nil
            continue
        end

        if distance > CFG.PlayerWatchRadius
            and now - (data.LastBad or 0) > CFG.PlayerForgetTime then
            PlayerThreats[id] = nil
        end
    end
end


--============================================================
-- INTEGRITY
--============================================================

local function BuildBaseline()

    if not Root then return end

    BaselineRootSize = Root.Size

    local ok, mass = pcall(function() return Root.AssemblyMass end)
    BaselineAssemblyMass = (ok and type(mass) == "number" and mass > 0)
        and mass or nil
end


local function CheckIntegrity()

    if not Root or not Root.Parent then return end

    if BaselineRootSize then

        local current = Root.Size
        local base    = BaselineRootSize

        local rx = math.abs(current.X - base.X) / math.max(base.X, 0.01)
        local ry = math.abs(current.Y - base.Y) / math.max(base.Y, 0.01)
        local rz = math.abs(current.Z - base.Z) / math.max(base.Z, 0.01)

        local largest = math.max(rx, ry, rz)

        if largest > 0.75 then
            Block("INTEGRITY", "Abnormal root size")
            if largest > 1.5 then
                pcall(function() Root.Size = base end)
            end
        end
    end
end


--============================================================
-- CLEANUP
--============================================================

local function ClearAllShields()

    for ownPart, targets in pairs(ActiveShields) do
        for targetPart, constraint in pairs(targets) do
            if constraint then
                pcall(function() constraint:Destroy() end)
            end
            targets[targetPart] = nil
        end
        ActiveShields[ownPart] = nil
    end

    ShieldCount = 0
end


local function DisconnectCharacterConnections()

    for _, connection in ipairs(CharacterConnections) do
        if connection then
            pcall(function() connection:Disconnect() end)
        end
    end

    table.clear(CharacterConnections)
end


--============================================================
--                   DEATH FORENSICS
--============================================================
--
-- Your log showed the tool and the weld both being blocked, then
-- silence, then a respawn. No teleport, no assertion, no anchor.
--
-- That means the kill did not arrive through the physics the rest
-- of this script watches. Rather than guess again, this records
-- what actually happened in the moments before you died: health,
-- height, velocity, humanoid state, and who was standing near you.
--============================================================

local HealthHistory = {}     -- rolling { t, health }
local LastHealth    = nil


local function SnapshotHealth()

    if not Humanoid then return end

    local h = Humanoid.Health
    local now = os.clock()

    table.insert(HealthHistory, { t = now, h = h })

    while #HealthHistory > 40 do
        table.remove(HealthHistory, 1)
    end

    -- A large drop in a single sample is worth recording on its own,
    -- because that is what a scripted kill looks like versus falling.
    if LastHealth and h < LastHealth then

        local drop = LastHealth - h

        if drop > 20 then
            LogEvent("HEALTH",
                string.format("-%d  (%d -> %d)",
                    math.floor(drop), math.floor(LastHealth), math.floor(h)))
        end
    end

    LastHealth = h
end


local function ReportDeath()

    local pos = Root and Root.Position or Vector3.zero
    local vel = Root and Root.AssemblyLinearVelocity or Vector3.zero

    LogEvent("DIED", string.format(
        "Y=%d  speed=%d  anchored=%s",
        math.floor(pos.Y),
        math.floor(vel.Magnitude),
        tostring(Root and Root.Anchored)))

    -- who was close enough to be responsible
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local r = p.Character:FindFirstChild("HumanoidRootPart")
            if r then
                local d = (r.Position - pos).Magnitude
                if d < 100 then
                    local hum = p.Character:FindFirstChildOfClass("Humanoid")
                    LogEvent("NEARBY", string.format(
                        "%s at %d studs  humanoid=%s",
                        p.Name, math.floor(d),
                        hum and "yes" or "NO"))
                end
            end
        end
    end

    -- the shape of the health curve tells you the cause
    local drops = {}
    for i = 2, #HealthHistory do
        local a, b = HealthHistory[i - 1], HealthHistory[i]
        if b.h < a.h then
            table.insert(drops, string.format("%.2fs: %d->%d",
                b.t - ScriptStart, math.floor(a.h), math.floor(b.h)))
        end
    end

    if #drops == 0 then
        LogEvent("HEALTH", "no gradual damage — health went straight to 0")
    else
        for _, d in ipairs(drops) do
            LogEvent("HEALTH", d)
        end
    end

    task.defer(function()
        warn("[ANTIKILL] ---- DEATH REPORT ----")
        if _G.AntiFlingLog then _G.AntiFlingLog(25) end
    end)
end


--============================================================
--                REANIMATE AWARENESS   (v3)
--============================================================
--
-- Dino Reanimate and your autorig move your real body into a
-- sub-model and drive it themselves. Pinning, anchoring or standing
-- that body up would fight them, so the body guards pause while one
-- runs. Tool and link cutting keeps going in every mode.
--============================================================

local function ReanimDetect()

    if not CFG.ReanimateAware then return false end

    if Character and (Character:FindFirstChild("DinoBody")
        or Character:FindFirstChild("Corpse")) then
        return true
    end

    local dino = Global and Global.DinoReanimate
    if type(dino) == "table" and type(dino.IsRunning) == "function" then
        local ok, running = pcall(dino.IsRunning)
        if ok and running then return true end
    end

    return false
end


local function ForceReleaseAnchor()
    if not WasAnchored then return end
    AnchorUntil   = 0
    AnchorStarted = 0
    ReleaseAnchor()
end


--============================================================
--                    KNOCKDOWN LOCK   (v3)
--============================================================
--
-- The "lie down, then die". A knocked-down humanoid stops holding
-- itself upright, so whatever drags it next meets no resistance.
-- Your humanoid is yours: switching those states off here holds,
-- and a body that still ends up on its side is stood back up.
--============================================================

local KnockdownStates = {
    [Enum.HumanoidStateType.FallingDown]      = true,
    [Enum.HumanoidStateType.Ragdoll]          = true,
    [Enum.HumanoidStateType.PlatformStanding] = true,
}

local UprightSkipStates = {
    [Enum.HumanoidStateType.Climbing] = true,
    [Enum.HumanoidStateType.Swimming] = true,
    [Enum.HumanoidStateType.Seated]   = true,
    [Enum.HumanoidStateType.Dead]     = true,
}


local function ApplyStateLock()

    if not Humanoid then return end

    local on = CFG.StateLock and not ReanimMode

    pcall(function()
        Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, not on)
        Humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, not on)
    end)
end


-- FAKE LAG (and anything else that lays you down on purpose) sets
-- this a little into the future every frame it's in charge of your
-- pose, so the upright guard leaves you lying there.
local function PoseOverridden()
    return (tonumber(_G.DinoPoseOverrideUntil) or 0) > os.clock()
end


local function StandUp(reason)

    if not Humanoid or not Root or not Root.Parent then return end
    if PoseOverridden() then return end

    pcall(function() Humanoid.PlatformStand = false end)
    pcall(function() Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end)

    Block("STATE", reason, "state")
end


local function HookStateLock()

    if not Humanoid then return end
    local hum = Humanoid

    ApplyStateLock()

    table.insert(CharacterConnections,
        hum.StateChanged:Connect(function(_, new)

            if not CFG.StateLock then return end

            local physics = new == Enum.HumanoidStateType.Physics
                and CFG.StateLockPhysics

            if not (KnockdownStates[new] or physics) then return end

            -- Deferred: a reanimate switches to Physics a moment
            -- before its split is visible, so look again first.
            task.defer(function()
                if hum ~= Humanoid or ReanimDetect() then return end
                if hum.Health <= 0 then return end
                if hum:GetState() == new then
                    StandUp("Knocked into " .. new.Name .. " - stood back up")
                end
            end)
        end))

    table.insert(CharacterConnections,
        hum:GetPropertyChangedSignal("PlatformStand"):Connect(function()

            if not (CFG.StateLock and hum.PlatformStand) then return end
            if hum ~= Humanoid or ReanimDetect() then return end

            pcall(function() hum.PlatformStand = false end)
            Block("STATE", "PlatformStand was forced on - turned off", "state_ps")
        end))
end


-- Runs after the solver. Only acts on a body that has been on its
-- side for TipTime, so a normal stumble never triggers it.
local function CheckUpright()

    if not CFG.StateLock or ReanimMode or WasAnchored or PoseOverridden() then
        TipSince = nil
        return
    end

    if not Humanoid or not Root or not Root.Parent then return end

    if Humanoid.SeatPart or Humanoid.Health <= 0
        or UprightSkipStates[Humanoid:GetState()] then
        TipSince = nil
        return
    end

    local cf = Root.CFrame

    if cf.UpVector.Y >= math.cos(math.rad(CFG.TipAngle)) then
        TipSince = nil
        return
    end

    local now = os.clock()
    TipSince = TipSince or now
    if now - TipSince < CFG.TipTime then return end
    TipSince = nil

    -- keep the heading: the flat part of the look vector, or of the
    -- up vector when lying face down / face up
    local look = cf.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.05 then
        local up = cf.UpVector
        flat = Vector3.new(up.X, 0, up.Z)
    end
    if flat.Magnitude < 0.05 then
        flat = Vector3.new(0, 0, -1)
    end

    local standAt = cf.Position + Vector3.new(0, 1.5, 0)

    pcall(function()
        Root.CFrame = CFrame.lookAt(standAt, standAt + flat.Unit)
        Root.AssemblyAngularVelocity = Vector3.zero
    end)

    AuthorizedCFrame = Root.CFrame
    StandUp("Body was on its side - stood back up")
end


--============================================================
--                    OWNERSHIP GUARD   (v3)
--============================================================
--
-- Your client simulates your own body. A toolkill that lands takes
-- that away: the moment another client is simulating your root, it
-- can lay you down and drag you wherever it wants, and nothing you
-- write locally reaches the server any more. This notices it and
-- cuts every link straight away; unequipping is the cut that the
-- server actually honours.
--============================================================

local function ReadOwnership()

    if not Root or not Root.Parent then return nil end
    if Root.Anchored then return true end

    if type(isnetworkowner) == "function" then
        local ok, owned = pcall(isnetworkowner, Root)
        if ok and type(owned) == "boolean" then return owned end
    end

    -- ReceiveAge stays 0 on parts this client simulates itself
    local ok, age = pcall(function() return Root.ReceiveAge end)
    if ok and type(age) == "number" then return age == 0 end

    return nil
end


local function CheckOwnership()

    if not CFG.OwnershipGuard then
        OwnershipState = "OFF"
        return
    end

    if ReanimMode then
        OwnershipState = "REANIM"
        OwnStrikes = 0
        return
    end

    local now = os.clock()
    if now - LastOwnCheck < CFG.OwnershipInterval then return end
    LastOwnCheck = now

    if now < TeleportGraceUntil or not Humanoid then
        OwnStrikes = 0
        return
    end

    -- someone else driving a vehicle you sit in owns it legitimately
    if Humanoid.SeatPart then
        OwnStrikes = 0
        return
    end

    local owned = ReadOwnership()
    if owned == nil then
        OwnershipState = "?"
        return
    end

    if owned then

        OwnStrikes = 0
        OwnershipState = "OWNED"

        if OwnershipLost then
            OwnershipLost = false

            if SafeCFrame and Root
                and (Root.Position - SafeCFrame.Position).Magnitude > CFG.TeleportSnapDistance then

                pcall(function()
                    Root.CFrame = SafeCFrame
                    Root.AssemblyLinearVelocity  = Vector3.zero
                    Root.AssemblyAngularVelocity = Vector3.zero
                end)

                AuthorizedCFrame = SafeCFrame
                LastSelfPosition = SafeCFrame.Position
                LogEvent("OWNERSHIP", "back under your control - returned to your last safe spot")
            else
                LogEvent("OWNERSHIP", "back under your control")
            end
        end

        return
    end

    OwnStrikes += 1
    if OwnStrikes < CFG.OwnershipStrikes or OwnershipLost then return end

    OwnershipLost  = true
    OwnershipState = "LOST"

    pcall(function() Humanoid:UnequipTools() end)
    PurgeForeignTools()
    SweepGripWelds()
    ScanAssembly()

    LockdownUntil = now + CFG.LockdownDuration

    Block("OWNERSHIP",
        "Another client took over your body - links cut, tools unequipped",
        "ownership")
end


--============================================================
--                      VOID SHIELD   (v3)
--============================================================
--
-- The machine that simulates a part deletes it below the destroy
-- height, and for your own body that machine is you. With the
-- height off on your client, a drag under the map can't delete you
-- here; the void guard brings you back up instead. The game's real
-- height is kept in VoidBaseHeight for that guard.
--============================================================

local function ApplyVoidShield()

    pcall(function()
        local h = Workspace.FallenPartsDestroyHeight
        if CFG.VoidShield then
            if h == h then
                Workspace.FallenPartsDestroyHeight = 0 / 0
            end
        elseif h ~= h and not ReanimMode then
            Workspace.FallenPartsDestroyHeight = VoidBaseHeight
        end
    end)
end


--============================================================
--                     PICKUP SHIELD   (v3)
--============================================================
--
-- A dropped tool reaches your hand through a touch. While one lies
-- near you, your body stops registering touches, so your own client
-- never reports that touch to the server. An attacker can still
-- report it from his side; whatever gets through meets the tool
-- firewall.
--============================================================

local function SetBodyTouch(enabled)

    if enabled then
        for part, was in pairs(TouchSaved) do
            if part.Parent then
                pcall(function() part.CanTouch = was end)
            end
        end
        table.clear(TouchSaved)
        TouchOff = false
        return
    end

    if not Character then return end

    for _, d in ipairs(Character:GetDescendants()) do
        if d:IsA("BasePart") and TouchSaved[d] == nil
            and not d:FindFirstAncestorOfClass("Tool") then
            TouchSaved[d] = d.CanTouch
            pcall(function() d.CanTouch = false end)
        end
    end

    TouchOff = true
end


local function CheckPickupShield()

    if not Root or not Root.Parent then return end

    local nearest = nil

    if CFG.PickupShield and not ReanimMode then

        local best = CFG.PickupShieldRadius

        for tool in pairs(DroppedTools) do
            if tool.Parent ~= Workspace or OwnTools[tool] or IsAllowedTool(tool) then
                DroppedTools[tool] = nil
            else
                local handle = tool:FindFirstChild("Handle")
                if handle and handle:IsA("BasePart") then
                    local d = (handle.Position - Root.Position).Magnitude
                    if d < best then
                        best = d
                        nearest = tool
                    end
                end
            end
        end
    end

    NearDropped = nearest

    if nearest and not TouchOff then
        SetBodyTouch(false)
        Stats.PickupShields += 1
        LogEvent("PICKUP", "dropped " .. nearest.Name .. " near you - touch off")
    elseif not nearest and TouchOff then
        SetBodyTouch(true)
    end
end


--============================================================
--                     TOOL WATCHER   (v3)
--============================================================
--
-- Remembers every tool seen anywhere in the world that isn't on
-- you, and which ones are lying loose. A tool that later shows up
-- in your backpack after being seen out there was picked up.
--============================================================

local function NoteWorldTool(obj)

    if not obj:IsA("Tool") or IsMine(obj) then return end

    ToolSeenOutside[obj] = true

    if obj.Parent == Workspace and not OwnTools[obj] then
        DroppedTools[obj] = true
    end
end


local function HookToolWatcher()

    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("Tool") then NoteWorldTool(obj) end
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            for _, obj in ipairs(player.Character:GetChildren()) do
                if obj:IsA("Tool") then NoteWorldTool(obj) end
            end
        end
    end

    -- ClassName first: this fires for every new part in the game
    table.insert(GlobalConnections,
        Workspace.DescendantAdded:Connect(function(obj)
            if obj.ClassName == "Tool" then NoteWorldTool(obj) end
        end))

    -- a tool dropped out of a character was already a descendant of
    -- Workspace, so only ChildAdded sees it land
    table.insert(GlobalConnections,
        Workspace.ChildAdded:Connect(function(obj)
            if obj.ClassName == "Tool" then NoteWorldTool(obj) end
        end))
end


--============================================================
--                    REANIMATE MODE SWITCH
--============================================================

local function UpdateReanimMode()

    local mode = ReanimDetect()
    if mode == ReanimMode then return end

    ReanimMode = mode

    if mode then
        ForceReleaseAnchor()
        if TouchOff then SetBodyTouch(true) end
        TipSince = nil
        LogEvent("REANIMATE", "reanimate detected - body guards paused, tool guards stay on")
    else
        LogEvent("REANIMATE", "reanimate ended - body guards back on")
    end

    ApplyStateLock()
end


--============================================================
--                         SECURE   (v3)
--============================================================
--
-- The panic button: every cut at once, a lockdown, and back to the
-- last spot you were standing safely.
--============================================================

local function SecureNow(source)

    local now = os.clock()

    if Humanoid and not Humanoid.SeatPart then
        pcall(function() Humanoid:UnequipTools() end)
    end

    PurgeForeignTools()
    SweepGripWelds()
    ScanAssembly()
    RemoveExternalTethers()
    RemoveInjectedForces()
    CheckJoints()

    LockdownUntil = now + CFG.LockdownDuration

    if not ReanimMode and Root and Root.Parent and SafeCFrame then
        pcall(function()
            Root.CFrame = SafeCFrame
            Root.AssemblyLinearVelocity  = Vector3.zero
            Root.AssemblyAngularVelocity = Vector3.zero
        end)
        AuthorizedCFrame = SafeCFrame
        LastSelfPosition = SafeCFrame.Position

        if Humanoid and CFG.StateLock then
            pcall(function()
                Humanoid.PlatformStand = false
                Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end)
        end
    end

    Block("SECURE",
        tostring(source or "manual") .. ": links cut, tools unequipped, lockdown on",
        "secure")
end


--============================================================
-- CHARACTER SETUP
--============================================================

local function SetupBackpackWatcher()

    if not Backpack then return end

    local function Classify(obj)

        if not obj:IsA("Tool") then return end
        KnownTools[obj] = true

        -- a tool we blocked, now unequipped into the backpack
        if ForeignTools[obj] then
            task.delay(0.35, function() HideTool(obj, "blocked tool") end)
            return
        end

        -- picked up from the world straight into the backpack
        if CFG.ToolFirewall and ToolSeenOutside[obj] and not OwnTools[obj]
            and not IsAllowedTool(obj) then
            ForeignTools[obj] = true
            Block("TOOL BLOCKED", obj.Name .. " - picked up into your backpack",
                "tool_blocked")
            task.delay(0.35, function() HideTool(obj, "picked up") end)
            return
        end

        -- everything else came from the game or from your own hand
        OwnTools[obj]       = true
        SeenInBackpack[obj] = true
        BaselineToolGrip(obj)
    end

    table.insert(CharacterConnections, Backpack.ChildAdded:Connect(Classify))

    -- anything that arrived before the connection
    for _, obj in ipairs(Backpack:GetChildren()) do
        if obj:IsA("Tool") and not OwnTools[obj] then Classify(obj) end
    end
end


local SetupTarget = nil

local function SetupCharacter(newCharacter)

    -- Your log printed "Character protection active" and
    -- "Joint baseline captured" twice for one spawn. Running setup
    -- twice doubles every connection, so each event then fires twice
    -- and the deferred baselines race each other.
    if SetupTarget == newCharacter then return end
    SetupTarget = newCharacter

    DisconnectCharacterConnections()
    ClearAllShields()

    if TouchOff then SetBodyTouch(true) end
    table.clear(TouchSaved)
    TouchOff = false

    Character = newCharacter

    Humanoid = Character:WaitForChild("Humanoid", 10)
    Root     = Character:WaitForChild("HumanoidRootPart", 10)
    Backpack = LocalPlayer:WaitForChild("Backpack", 10)

    if not Humanoid or not Root then return end

    ----------------------------------------------------------
    -- Reset state
    ----------------------------------------------------------

    LastSelfPosition = Root.Position
    LastSelfVelocity = Root.AssemblyLinearVelocity

    SafeCFrame       = Root.CFrame
    LastSafeSnapshot = 0

    RecoveryUntil       = 0
    TeleportGraceUntil  = os.clock() + 2

    LastToolScan      = 0
    LastIntegrityScan = 0
    LastAssemblyScan  = 0
    LastJointScan     = 0

    table.clear(LaunchTimes)
    table.clear(TouchEvents)
    table.clear(ToolGripBase)

    -- Clear the joint baseline IMMEDIATELY, not in the deferred
    -- BaselineJoints call 0.5 s later.
    --
    -- Otherwise CheckJoints spends that half second iterating the
    -- OLD character's joints, whose Part0/Part1 legitimately are not
    -- descendants of the new Character — so every one of them reads
    -- as hijacked. That is the burst of "repointed off the character"
    -- lines in your log at 20:12:43, and it was restoring or
    -- destroying joints on a body that no longer existed.
    table.clear(JointBase)

    LockdownUntil   = 0
    LastShieldPrune = 0

    AnchorUntil      = 0
    AnchorStarted    = 0
    WasAnchored      = false
    AuthorizedCFrame = Root.CFrame

    pcall(function() Root.Anchored = false end)

    OwnStrikes     = 0
    OwnershipLost  = false
    OwnershipState = "?"
    TipSince       = nil
    ReanimMode     = ReanimDetect()

    PruneShields()

    BuildBaseline()
    LearnExistingTools()

    ----------------------------------------------------------
    -- Joint baseline
    --
    -- Deferred one beat so the rig is fully assembled first —
    -- baselining a half-built R15 would bake in wrong C0s.
    ----------------------------------------------------------

    task.delay(0.5, function()
        if Character == newCharacter then
            BaselineJoints()
            Debug("Joint baseline captured (" ..
                (function()
                    local n = 0
                    for _ in pairs(JointBase) do n += 1 end
                    return n
                end)() .. " joints)")
        end
    end)

    ----------------------------------------------------------
    -- Grip baselines for anything already held
    ----------------------------------------------------------

    -- tools already held at spawn are yours (LearnExistingTools)
    for _, obj in ipairs(Character:GetChildren()) do
        if obj:IsA("Tool") then
            BaselineToolGrip(obj)
        end
    end

    if Backpack then
        for _, obj in ipairs(Backpack:GetChildren()) do
            if obj:IsA("Tool") then BaselineToolGrip(obj) end
        end
    end

    PhysicsFilterDirty = true

    ----------------------------------------------------------
    -- Watchers
    ----------------------------------------------------------

    table.insert(CharacterConnections,
        Character.DescendantAdded:Connect(InspectNewObject))

    table.insert(CharacterConnections,
        Character.ChildAdded:Connect(function(obj)
            if obj:IsA("Tool") then
                -- screened before anything else touches it
                ScreenIncomingTool(obj)
                KnownTools[obj] = true
                BaselineToolGrip(obj)
            end
            PhysicsFilterDirty = true
        end)
    )

    table.insert(CharacterConnections,
        Character.ChildRemoved:Connect(function()
            PhysicsFilterDirty = true
        end)
    )

    ----------------------------------------------------------
    -- Seat events
    ----------------------------------------------------------

    if CFG.SeatGuard then
        table.insert(CharacterConnections,
            Humanoid.Seated:Connect(function(active, seat)
                if active and seat then
                    task.defer(CheckSeat)
                end
            end)
        )
    end

    ----------------------------------------------------------
    -- Death forensics
    ----------------------------------------------------------

    LastHealth = Humanoid.Health
    table.clear(HealthHistory)

    table.insert(CharacterConnections,
        Humanoid.Died:Connect(ReportDeath))

    table.insert(CharacterConnections,
        Humanoid.HealthChanged:Connect(function()
            SnapshotHealth()
        end))

    -- A Humanoid that is removed outright kills you with no
    -- HealthChanged and no Died, so watch for that separately.
    table.insert(CharacterConnections,
        Humanoid.AncestryChanged:Connect(function(_, parent)
            if not parent then
                LogEvent("HUMANOID", "Humanoid was removed from the character")
                warn("[ANTIKILL] Humanoid destroyed — that is the kill")
            end
        end))

    HookTouchGuard()
    SetupBackpackWatcher()
    HookStateLock()
    ApplyVoidShield()

    Debug("Character protection active for " .. LocalPlayer.Name)
end


--============================================================
-- PLAYERS
--============================================================

table.insert(GlobalConnections, Players.PlayerAdded:Connect(function(player)
    PhysicsFilterDirty = true
    table.insert(GlobalConnections, player.CharacterAdded:Connect(function()
        PhysicsFilterDirty = true
    end))
end))


table.insert(GlobalConnections, Players.PlayerRemoving:Connect(function(player)
    PlayerThreats[player.UserId] = nil
    PhysicsFilterDirty = true
end))


for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        table.insert(GlobalConnections, player.CharacterAdded:Connect(function()
            PhysicsFilterDirty = true
        end))
    end
end


--============================================================
-- PUBLIC API
--============================================================

_G.AntiFlingTeleportGrace = function(seconds)
    seconds = tonumber(seconds) or 1
    TeleportGraceUntil = os.clock() + math.max(0, seconds)
    Debug("Teleport grace:", seconds, "seconds")
end


-- Call this after your game legitimately welds something to the
-- player, so the assembly firewall doesn't immediately cut it.
_G.AntiFlingAllow = function(instance)
    if typeof(instance) == "Instance" then
        instance:SetAttribute("AntiFlingAllowed", true)
        Debug("Allowed:", instance:GetFullName())
    end
end


-- Whitelist a tool your game legitimately gives you.
_G.AntiFlingAllowTool = function(name)
    if type(name) == "string" then
        CFG.AllowedTools[name] = true
        Debug("Tool allowed:", name)
    end
end


_G.AntiFlingBlockTools = function(state)
    CFG.ToolFirewall = state and true or false
    Debug("Tool firewall:", CFG.ToolFirewall and "ON" or "OFF")
end


-- Every cut at once + lockdown + back to your last safe spot.
_G.AntiFlingSecure = function()
    SecureNow("_G.AntiFlingSecure")
end


-- Put hidden (blocked) tools back into your inventory.
_G.AntiFlingRestoreTools = function()
    return RestoreHiddenTools()
end


-- Take picked-up tools out of your inventory now.
_G.AntiFlingCleanTools = function()
    return CleanInventory(true)
end


_G.AntiFlingRebaseline = function()
    BuildBaseline()
    BaselineJoints()
    Debug("Baselines rebuilt")
end


-- Run this right after a death. It prints the last two minutes of
-- everything that fired, with timestamps, so you can see which
-- layer caught the attempts you survived and what was different
-- about the one you didn't.
_G.AntiFlingLog = function(count)

    count = tonumber(count) or 40

    print("")
    print("========== ANTIKILL EVENT LOG ==========")

    local start = math.max(1, #EventLog - count + 1)

    if #EventLog == 0 then
        print("  (nothing fired — no layer detected anything)")
    end

    for i = start, #EventLog do
        local e = EventLog[i]
        print(string.format("  %8.2fs  [%s] %s", e.t, e.cat, e.msg))
    end

    print("==========================================")
    print("If the fatal attempt shows a TOOL SEEN with no")
    print("TOOL BLOCKED or GRIP line after it, the blockade")
    print("was off or the tool was whitelisted.")
    print("If it shows nothing at all, the kill did not come")
    print("through a tool and we are looking at the wrong thing.")
    print("==========================================")
end


_G.AntiFlingStats = function()

    print("")
    print("========== ANTIKILL STATS ==========")

    for name, value in pairs(Stats) do
        print(name .. ":", value)
    end

    PruneShields()
    print("Active shields:", ShieldCount,
        "/", (os.clock() < LockdownUntil)
            and CFG.LockdownShieldPairs or CFG.MaxShieldPairs)
    print("Lockdown:", (os.clock() < LockdownUntil)
        and string.format("ACTIVE (%.1fs left)", LockdownUntil - os.clock())
        or "idle")
    print("Baseline assembly mass:", BaselineAssemblyMass)

    if Root then
        print("Current assembly mass:", Root.AssemblyMass)
    end

    print("Tracked threats:")

    for _, data in pairs(PlayerThreats) do
        if data.Player then
            print("  ", data.Player.Name,
                "Score=", math.floor(data.Score),
                "Flagged=", data.Flagged,
                "Critical=", data.Critical)
        end
    end

    print("=======================================")
end


--============================================================
-- INITIAL CHARACTER
--============================================================

if LocalPlayer.Character then
    task.spawn(function()
        SetupCharacter(LocalPlayer.Character)
    end)
end

table.insert(GlobalConnections, LocalPlayer.CharacterAdded:Connect(function(character)
    SetupCharacter(character)
end))

HookWorkspaceWatcher()
HookToolWatcher()


--============================================================
-- PRE-SIMULATION
--============================================================

table.insert(GlobalConnections, RunService.PreSimulation:Connect(function(dt)

    if not Character or not Character.Parent
        or not Root or not Root.Parent
        or not Humanoid then
        return
    end

    ----------------------------------------------------------
    -- Highest priority, in this order:
    --
    --   grip sweep   — cut the drag before it can pull
    --   teleport     — undo it if it already pulled
    --   then normal physics checks
    --
    -- The sweep runs first because a severed weld cannot drag you
    -- on the frame it is severed, whereas a clamp applied to an
    -- intact weld is overruled by the solver immediately.
    ----------------------------------------------------------

    UpdateReanimMode()

    -- Before the solver: a joint cut here never gets to pull at all.
    -- Tool and link cuts run in every mode, reanimated included.
    SweepGripWelds()
    PurgeForeignTools()

    -- A reanimate drives the body; the body guards stand down.
    if ReanimMode then return end

    if CheckTeleport(dt) then
        -- position was restored this frame; skip the velocity
        -- checks so they don't fight the rollback
        RecordSafePosition()
        return
    end

    CheckSelfPhysics(dt)
    CheckSelfPosition(dt)
    RecordSafePosition()

    local now = os.clock()

    ----------------------------------------------------------
    -- Assembly firewall
    --
    -- Runs often, because a weld only needs one frame to start
    -- moving you. It is cheap: a humanoid assembly is ~15 parts.
    ----------------------------------------------------------

    -- A weld needs one frame to start moving you, so under sustained
    -- attack this drops to every frame rather than every 0.2 s.
    local locked = now < LockdownUntil
    local assemblyGap = locked and 0 or CFG.AssemblyInterval

    if now - LastAssemblyScan >= assemblyGap then
        LastAssemblyScan = now
        ScanAssembly()
        CheckAssemblyMass()
        CheckSeat()
    end

    -- Keep the shield table honest even when nothing is attacking
    if now - LastShieldPrune >= 1.0 then
        LastShieldPrune = now
        PruneShields()
    end

    ----------------------------------------------------------
    -- Joint guard
    ----------------------------------------------------------

    if now - LastJointScan >= (locked and 0 or CFG.JointInterval) then
        LastJointScan = now
        CheckJoints()
    end

    ----------------------------------------------------------
    -- Tools
    ----------------------------------------------------------

    if now - LastToolScan >= CFG.ToolScanInterval then
        LastToolScan = now
        ScanOwnTools()
    end

    ----------------------------------------------------------
    -- Slow maintenance
    ----------------------------------------------------------

    if now - LastIntegrityScan >= CFG.IntegrityInterval then
        LastIntegrityScan = now
        CheckIntegrity()
        RemoveInjectedForces()
        RemoveExternalTethers()
    end
end))


--============================================================
-- POST-SIMULATION   (after the solver)
--============================================================
--
-- PreSimulation runs before physics, so anything written there is
-- still subject to the solver, including a weld drag. Assertion,
-- anchor, ownership and the stand-up therefore run here, where the
-- last write of the frame is ours.
--============================================================

table.insert(GlobalConnections, RunService.PostSimulation:Connect(function()

    if not Character or not Character.Parent
        or not Root or not Root.Parent then
        return
    end

    -- cut first, so a severed weld cannot pull on the next step
    SweepGripWelds()
    PurgeForeignTools()

    if ReanimMode then
        ForceReleaseAnchor()
        return
    end

    CheckOwnership()
    CheckUpright()
    AssertPosition()
    ReleaseAnchor()
end))


-- One more unequip pass per rendered frame: a tool that arrives
-- between physics steps is out of your hand before the next one.
table.insert(GlobalConnections, RunService.RenderStepped:Connect(function()
    if Character and Humanoid then
        PurgeForeignTools()
    end
end))


--============================================================
-- PLAYER SCANNER
--============================================================

task.spawn(function()
    while Alive do

        if HasDangerousPlayer() then
            task.wait(CFG.DangerPlayerScanInterval)
        else
            task.wait(CFG.PlayerScanInterval)
        end

        if not Character or not Character.Parent
            or not Root or not Root.Parent then
            continue
        end

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                ScanPlayer(player)
            end
        end

        MaintainThreats()
    end
end)


--============================================================
-- REANIMATION SCANNER
--============================================================

task.spawn(function()
    while Alive do

        if HasDangerousPlayer() then
            task.wait(CFG.DangerReanimScanInterval)
        else
            task.wait(CFG.ReanimScanInterval)
        end

        if not Character or not Character.Parent
            or not Root or not Root.Parent then
            continue
        end

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                ScanPlayerReanimation(player)
            end
        end

        ScanDetachedReanimation()
    end
end)


--============================================================
-- GENERIC PHYSICS SCANNER
--============================================================

task.spawn(function()
    while Alive do

        if HasDangerousPlayer() then
            task.wait(CFG.DangerNearbyScanInterval)
        else
            task.wait(CFG.NearbyScanInterval)
        end

        if Character and Character.Parent and Root and Root.Parent then
            ScanNearbyPhysics()
        end
    end
end)


--============================================================
-- PICKUP SHIELD + VOID SHIELD UPKEEP   (v3)
--============================================================

task.spawn(function()
    while Alive do
        task.wait(0.05)
        if Character and Character.Parent and Root and Root.Parent then
            local ok, err = pcall(CheckPickupShield)
            if not ok then Debug("pickup shield error:", err) end
        end
    end
end)

task.spawn(function()
    while Alive do
        task.wait(1)
        -- some games reset it; keep it the way the toggle says
        ApplyVoidShield()
    end
end)


--============================================================
-- STARTUP
--============================================================

--============================================================
--                            UI
--============================================================
--
-- ANTIKILL panel and toasts. Everything it shows is read from the
-- state above; the buttons call the same functions the guards use.
--============================================================

local UI: { [string]: any } = { Built = false }

local Theme = {
    Bg     = Color3.fromRGB(4, 10, 7),
    Panel  = Color3.fromRGB(8, 19, 13),
    Panel2 = Color3.fromRGB(12, 28, 19),
    Hover  = Color3.fromRGB(16, 40, 26),
    Green  = Color3.fromRGB(0, 255, 120),
    Green2 = Color3.fromRGB(0, 185, 75),
    Deep   = Color3.fromRGB(0, 80, 38),
    Dim    = Color3.fromRGB(85, 150, 108),
    Text   = Color3.fromRGB(212, 255, 226),
    Yellow = Color3.fromRGB(255, 212, 70),
    Red    = Color3.fromRGB(255, 82, 82),
    Cyan   = Color3.fromRGB(90, 220, 255),
    Ink    = Color3.fromRGB(4, 18, 9),
}

local UIFont = Enum.Font.Code


local function Make(className, props, children)
    local inst: any = Instance.new(className)
    local parent = nil
    for key, value in pairs(props or {}) do
        if key == "Parent" then
            parent = value
        else
            inst[key] = value
        end
    end
    for _, child in ipairs(children or {}) do
        child.Parent = inst
    end
    if parent then inst.Parent = parent end
    return inst
end


local function Corner(radius)
    return Make("UICorner", { CornerRadius = UDim.new(0, radius) })
end


local function Stroke(color, thickness, transparency)
    return Make("UIStroke", {
        Color           = color,
        Thickness       = thickness or 1,
        Transparency    = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
end


local function Label(props)
    local p: { [string]: any } = {
        BackgroundTransparency = 1,
        Font           = UIFont,
        TextColor3     = Theme.Text,
        TextSize       = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate   = Enum.TextTruncate.AtEnd,
    }
    for key, value in pairs(props) do p[key] = value end
    return Make("TextLabel", p)
end


local function Hover(button, normal, hover)
    button.MouseEnter:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = hover }):Play()
    end)
    button.MouseLeave:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = normal }):Play()
    end)
end


local CategoryColor = {
    ["TOOL BLOCKED"] = Theme.Red,    ["GRIP"]      = Theme.Red,
    ["ASSEMBLY"]     = Theme.Red,    ["OWNERSHIP"] = Theme.Red,
    ["ANCHOR"]       = Theme.Red,    ["TELEPORT"]  = Theme.Red,
    ["ASSERT"]       = Theme.Red,    ["JOINT"]     = Theme.Red,
    ["TOOL"]         = Theme.Red,    ["TOOL GRIP"] = Theme.Red,
    ["MASS"]         = Theme.Red,    ["TETHER"]    = Theme.Red,
    ["FORCE"]        = Theme.Red,    ["DIED"]      = Theme.Red,
    ["HUMANOID"]     = Theme.Red,
    ["STATE"]        = Theme.Yellow, ["TOUCH"]     = Theme.Yellow,
    ["LOCKDOWN"]     = Theme.Yellow, ["PICKUP"]    = Theme.Yellow,
    ["SEAT"]         = Theme.Yellow, ["HEALTH"]    = Theme.Yellow,
    ["TOOL HIDDEN"]  = Theme.Yellow, ["NEARBY"]    = Theme.Yellow,
    ["REANIMATE"]    = Theme.Cyan,
    ["SECURE"]       = Theme.Green,  ["TOOLS"]     = Theme.Green,
    ["UI"]           = Theme.Dim,
}


local function ColorFor(category)
    local c = CategoryColor[category]
    if c then return c end
    for _, word in ipairs({ "PLAYER", "REANIMATE", "SELF", "PHYSICS" }) do
        if string.find(category, word, 1, true) then return Theme.Yellow end
    end
    return Theme.Green
end


local function Escape(s)
    local out = tostring(s)
    out = string.gsub(out, "&", "&amp;")
    out = string.gsub(out, "<", "&lt;")
    out = string.gsub(out, ">", "&gt;")
    return out
end


-- gethui (executors) > CoreGui (if allowed) > PlayerGui
local function UIParent()

    if type(gethui) == "function" then
        local ok, holder = pcall(gethui)
        if ok and typeof(holder) == "Instance" then return holder end
    end

    local ok, core = pcall(function()
        local cg = game:GetService("CoreGui")
        local probe = Instance.new("Folder")
        probe.Parent = cg
        probe:Destroy()
        return cg
    end)
    if ok and core then return core end

    return LocalPlayer:WaitForChild("PlayerGui")
end


function UI.Build()

    if UI.Built or not CFG.UI then return end

    local parent = UIParent()
    local old = parent:FindFirstChild("DinoAntikill")
    if old then old:Destroy() end

    local gui = Make("ScreenGui", {
        Name           = "DinoAntikill",
        ResetOnSpawn   = false,
        IgnoreGuiInset = true,
        DisplayOrder   = 999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    local parented = pcall(function() gui.Parent = parent end)
    if not parented or not gui.Parent then
        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
    UI.Gui = gui

    ------------------------------------------------------------
    -- window
    ------------------------------------------------------------

    local WIDTH = 340
    local GAP   = 8
    local PAD   = 12

    local main = Make("Frame", {
        Name                   = "Main",
        Size                   = UDim2.fromOffset(WIDTH, 100),
        Position               = UDim2.new(0, 24, 0.5, -280),
        BackgroundColor3       = Theme.Bg,
        BackgroundTransparency = 0.04,
        BorderSizePixel        = 0,
        ClipsDescendants       = true,
        Active                 = true,
        Parent                 = gui,
    }, { Corner(12) })

    local edge = Stroke(Theme.Green, 1.6, 0.1)
    edge.Parent = main
    local edgeGradient = Make("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Theme.Green),
            ColorSequenceKeypoint.new(0.5, Theme.Deep),
            ColorSequenceKeypoint.new(1, Theme.Green),
        }),
        Parent = edge,
    })
    TweenService:Create(edgeGradient,
        TweenInfo.new(5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
        { Rotation = 360 }):Play()

    local scale = Make("UIScale", { Parent = main })

    -- faint glow along the top
    Make("Frame", {
        Size                   = UDim2.new(1, 0, 0, 80),
        BackgroundColor3       = Theme.Green,
        BackgroundTransparency = 0.92,
        BorderSizePixel        = 0,
        Parent                 = main,
    }, {
        Make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0, 1) }),
    })

    local content = Make("Frame", {
        BackgroundTransparency = 1,
        Size                   = UDim2.fromScale(1, 1),
        Parent                 = main,
    }, {
        Make("UIPadding", {
            PaddingTop = UDim.new(0, PAD), PaddingBottom = UDim.new(0, PAD),
            PaddingLeft = UDim.new(0, PAD), PaddingRight = UDim.new(0, PAD),
        }),
        Make("UIListLayout", {
            Padding   = UDim.new(0, GAP),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })

    local order, fullHeight = 0, PAD * 2 - GAP
    local function Section(height)
        order += 1
        fullHeight += height + GAP
        return Make("Frame", {
            BackgroundTransparency = 1,
            Size                   = UDim2.new(1, 0, 0, height),
            LayoutOrder            = order,
            Parent                 = content,
        })
    end

    local function Panel(frame, radius, strokeTransparency)
        frame.BackgroundTransparency = 0
        frame.BackgroundColor3 = Theme.Panel
        Corner(radius).Parent = frame
        local s = Stroke(Theme.Green, 1, strokeTransparency)
        s.Parent = frame
        return s
    end

    ------------------------------------------------------------
    -- header
    ------------------------------------------------------------

    local HEADER = 44
    local header = Section(HEADER)
    header.Active = true

    Label({
        Text                   = "ANTIKILL",
        TextSize               = 20,
        TextColor3             = Theme.Green,
        TextStrokeColor3       = Theme.Green,
        TextStrokeTransparency = 0.85,
        Size                   = UDim2.new(1, -52, 0, 24),
        Parent                 = header,
    })
    Label({
        Text       = "by DinoKid  //  toolkill shield v3",
        TextSize   = 11,
        TextColor3 = Theme.Dim,
        Position   = UDim2.fromOffset(0, 25),
        Size       = UDim2.new(1, -52, 0, 16),
        Parent     = header,
    })

    local badge = Make("TextButton", {
        AnchorPoint      = Vector2.new(1, 0),
        Position         = UDim2.new(1, 0, 0, 2),
        Size             = UDim2.fromOffset(40, 40),
        BackgroundColor3 = Theme.Panel2,
        AutoButtonColor  = false,
        Text             = "[DK]",
        Font             = UIFont,
        TextSize         = 12,
        TextColor3       = Theme.Green,
        Parent           = header,
    }, { Corner(8) })
    Stroke(Theme.Green, 1, 0.45).Parent = badge
    Hover(badge, Theme.Panel2, Theme.Hover)

    ------------------------------------------------------------
    -- status bar
    ------------------------------------------------------------

    local statusBar = Section(28)
    Panel(statusBar, 6, 0.75)
    statusBar.ClipsDescendants = true

    local statusText = Label({
        Text       = "SHIELD ARMED",
        TextColor3 = Theme.Yellow,
        Position   = UDim2.fromOffset(10, 0),
        Size       = UDim2.new(1, -20, 1, 0),
        Parent     = statusBar,
    })

    local sweep = Make("Frame", {
        Size             = UDim2.new(0, 80, 0, 2),
        Position         = UDim2.new(0, -80, 1, -2),
        BackgroundColor3 = Theme.Green,
        BorderSizePixel  = 0,
        Parent           = statusBar,
    }, {
        Make("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.5, 0),
                NumberSequenceKeypoint.new(1, 1),
            }),
        }),
    })
    TweenService:Create(sweep,
        TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1),
        { Position = UDim2.new(1, 0, 1, -2) }):Play()

    ------------------------------------------------------------
    -- body card
    ------------------------------------------------------------

    local card = Section(58)
    Panel(card, 8, 0.75)

    local iconBox = Make("Frame", {
        Position         = UDim2.fromOffset(8, 8),
        Size             = UDim2.fromOffset(42, 42),
        BackgroundColor3 = Theme.Panel2,
        Parent           = card,
    }, { Corner(8) })
    local iconStroke = Stroke(Theme.Green, 1, 0.45)
    iconStroke.Parent = iconBox

    local icon = Make("TextLabel", {
        BackgroundTransparency = 1,
        Size                   = UDim2.fromScale(1, 1),
        Text                   = "🔒",
        TextSize               = 20,
        Font                   = Enum.Font.SourceSans,
        TextColor3             = Theme.Text,
        Parent                 = iconBox,
    })

    local bodyLine = Label({
        Text       = "> BODY // ?",
        TextColor3 = Theme.Green,
        Position   = UDim2.fromOffset(60, 9),
        Size       = UDim2.new(1, -68, 0, 18),
        Parent     = card,
    })
    local toolLine = Label({
        Text       = "> TOOLS // ?",
        TextSize   = 11,
        TextColor3 = Theme.Dim,
        Position   = UDim2.fromOffset(60, 31),
        Size       = UDim2.new(1, -68, 0, 18),
        Parent     = card,
    })

    ------------------------------------------------------------
    -- secure button
    ------------------------------------------------------------

    local secureHolder = Section(44)
    local secure = Make("TextButton", {
        Size             = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        AutoButtonColor  = false,
        Text             = "SECURE NOW",
        Font             = UIFont,
        TextSize         = 15,
        TextColor3       = Theme.Ink,
        Parent           = secureHolder,
    }, {
        Corner(8),
        Make("UIGradient", { Color = ColorSequence.new(Theme.Green, Theme.Green2) }),
    })
    local secureScale = Make("UIScale", { Parent = secure })

    secure.MouseEnter:Connect(function()
        TweenService:Create(secureScale, TweenInfo.new(0.12), { Scale = 1.02 }):Play()
    end)
    secure.MouseLeave:Connect(function()
        TweenService:Create(secureScale, TweenInfo.new(0.12), { Scale = 1 }):Play()
    end)
    secure.Activated:Connect(function()
        SecureNow("SECURE button")
        secure.Text = "SECURED"
        secureScale.Scale = 0.96
        TweenService:Create(secureScale,
            TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = 1 }):Play()
        task.delay(0.9, function()
            if secure.Parent then secure.Text = "SECURE NOW" end
        end)
    end)

    ------------------------------------------------------------
    -- counters
    ------------------------------------------------------------

    local statsRow = Section(48)
    Make("UIGridLayout", {
        CellSize    = UDim2.new(0.25, -6, 1, 0),
        CellPadding = UDim2.fromOffset(8, 0),
        SortOrder   = Enum.SortOrder.LayoutOrder,
        Parent      = statsRow,
    })

    local tiles = {}
    for i, caption in ipairs({ "BLOCKS", "TOOLKILL", "LINKS", "SAVES" }) do
        local tile = Make("Frame", {
            BackgroundColor3 = Theme.Panel,
            LayoutOrder      = i,
            Parent           = statsRow,
        }, { Corner(6) })
        Stroke(Theme.Green, 1, 0.8).Parent = tile

        tiles[caption] = Label({
            Text           = "0",
            TextSize       = 17,
            TextColor3     = Theme.Green,
            TextXAlignment = Enum.TextXAlignment.Center,
            Position       = UDim2.fromOffset(0, 5),
            Size           = UDim2.new(1, 0, 0, 22),
            Parent         = tile,
        })
        Label({
            Text           = caption,
            TextSize       = 10,
            TextColor3     = Theme.Dim,
            TextXAlignment = Enum.TextXAlignment.Center,
            Position       = UDim2.fromOffset(0, 28),
            Size           = UDim2.new(1, 0, 0, 14),
            Parent         = tile,
        })
    end

    ------------------------------------------------------------
    -- toggles
    ------------------------------------------------------------

    local toggleDefs = {
        { "TOOL FIREWALL",  "ToolFirewall", nil },
        { "PICKUP SHIELD",  "PickupShield", function(on)
            if not on and TouchOff then SetBodyTouch(true) end
        end },
        { "KNOCKDOWN LOCK", "StateLock",    function() ApplyStateLock() end },
        { "VOID SHIELD",    "VoidShield",   function() ApplyVoidShield() end },
        { "ANCHOR LOCK",    "AnchorLock",   function(on)
            if not on then ForceReleaseAnchor() end
        end },
        { "TOASTS",         "Notifications", nil },
    }

    local rows = math.ceil(#toggleDefs / 2)
    local toggles = Section(rows * 26 + (rows - 1) * 6)
    Make("UIGridLayout", {
        CellSize    = UDim2.new(0.5, -4, 0, 26),
        CellPadding = UDim2.fromOffset(8, 6),
        SortOrder   = Enum.SortOrder.LayoutOrder,
        Parent      = toggles,
    })

    for i, def in ipairs(toggleDefs) do

        local name, key, callback = def[1], def[2], def[3]

        local button = Make("TextButton", {
            BackgroundColor3 = Theme.Panel,
            AutoButtonColor  = false,
            Text             = "",
            LayoutOrder      = i,
            Parent           = toggles,
        }, { Corner(6) })
        local buttonStroke = Stroke(Theme.Green, 1, 0.75)
        buttonStroke.Parent = button
        Hover(button, Theme.Panel, Theme.Hover)

        local dot = Make("Frame", {
            AnchorPoint      = Vector2.new(0, 0.5),
            Position         = UDim2.new(0, 9, 0.5, 0),
            Size             = UDim2.fromOffset(10, 10),
            BackgroundColor3 = Theme.Green,
            BorderSizePixel  = 0,
            Parent           = button,
        }, { Corner(3) })
        Stroke(Theme.Green, 1, 0.3).Parent = dot

        local caption = Label({
            Text     = name,
            TextSize = 11,
            Position = UDim2.fromOffset(26, 0),
            Size     = UDim2.new(1, -30, 1, 0),
            Parent   = button,
        })

        local function Paint()
            local on = CFG[key] == true
            TweenService:Create(dot, TweenInfo.new(0.15),
                { BackgroundTransparency = on and 0 or 1 }):Play()
            caption.TextColor3 = on and Theme.Text or Theme.Dim
            buttonStroke.Transparency = on and 0.55 or 0.85
        end
        Paint()

        button.Activated:Connect(function()
            CFG[key] = not CFG[key]
            if callback then pcall(callback, CFG[key]) end
            Paint()
            LogEvent("UI", name .. (CFG[key] and " on" or " off"))
        end)
    end

    ------------------------------------------------------------
    -- hidden tools
    ------------------------------------------------------------

    local inv = Section(26)
    local hiddenText = Label({
        Text       = "HIDDEN TOOLS: 0",
        TextSize   = 11,
        TextColor3 = Theme.Dim,
        Size       = UDim2.new(1, -152, 1, 0),
        Parent     = inv,
    })

    local function SmallButton(text, offsetX, onClick)
        local b = Make("TextButton", {
            AnchorPoint      = Vector2.new(1, 0),
            Position         = UDim2.new(1, offsetX, 0, 0),
            Size             = UDim2.fromOffset(70, 26),
            BackgroundColor3 = Theme.Panel2,
            AutoButtonColor  = false,
            Text             = text,
            Font             = UIFont,
            TextSize         = 11,
            TextColor3       = Theme.Green,
            Parent           = inv,
        }, { Corner(6) })
        Stroke(Theme.Green, 1, 0.5).Parent = b
        Hover(b, Theme.Panel2, Theme.Hover)
        b.Activated:Connect(onClick)
        return b
    end

    SmallButton("RESTORE", 0, function()
        local n = RestoreHiddenTools()
        UI.Toast("TOOLS", n .. " hidden tool(s) put back in your inventory")
    end)
    SmallButton("CLEAN", -78, function()
        local n = CleanInventory(true)
        UI.Toast("TOOLS", n .. " picked-up tool(s) taken out of your inventory")
    end)

    ------------------------------------------------------------
    -- live log
    ------------------------------------------------------------

    local feedHead = Section(14)
    Label({
        Text       = "LIVE LOG",
        TextSize   = 11,
        TextColor3 = Theme.Dim,
        Size       = UDim2.new(0.5, 0, 1, 0),
        Parent     = feedHead,
    })
    local feedCountText = Label({
        Text           = "0 events",
        TextSize       = 11,
        TextColor3     = Theme.Dim,
        TextXAlignment = Enum.TextXAlignment.Right,
        Position       = UDim2.fromScale(0.5, 0),
        Size           = UDim2.new(0.5, 0, 1, 0),
        Parent         = feedHead,
    })

    local feedBox = Section(112)
    local feed = Make("ScrollingFrame", {
        Size                 = UDim2.fromScale(1, 1),
        BackgroundColor3     = Theme.Panel,
        BorderSizePixel      = 0,
        ScrollBarThickness   = 3,
        ScrollBarImageColor3 = Theme.Green,
        CanvasSize           = UDim2.new(),
        AutomaticCanvasSize  = Enum.AutomaticSize.Y,
        ScrollingDirection   = Enum.ScrollingDirection.Y,
        Parent               = feedBox,
    }, {
        Corner(6),
        Make("UIPadding", {
            PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
            PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
        }),
        Make("UIListLayout", {
            Padding   = UDim.new(0, 3),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })
    Stroke(Theme.Green, 1, 0.8).Parent = feed

    ------------------------------------------------------------
    -- footer
    ------------------------------------------------------------

    local footer = Section(16)
    local footLeft = Label({
        Text       = "Gui Ready",
        TextColor3 = Theme.Green,
        Size       = UDim2.new(0.55, 0, 1, 0),
        Parent     = footer,
    })
    Label({
        Text           = "Toggle with " .. CFG.UIToggleKey.Name,
        TextSize       = 11,
        TextColor3     = Theme.Dim,
        TextXAlignment = Enum.TextXAlignment.Right,
        Position       = UDim2.fromScale(0.45, 0),
        Size           = UDim2.new(0.55, 0, 1, 0),
        Parent         = footer,
    })

    ------------------------------------------------------------
    -- size, fit to screen, minimise, drag, hotkey
    ------------------------------------------------------------

    local FULL = fullHeight
    local MINI = PAD * 2 + HEADER
    local minimized = false

    main.Size = UDim2.fromOffset(WIDTH, FULL)

    local function Fit()
        local cam = Workspace.CurrentCamera
        if not cam then return end
        local s = math.clamp((cam.ViewportSize.Y - 40) / FULL, 0.55, 1)
        scale.Scale = s
        return s
    end
    local s0 = Fit() or 1
    main.Position = UDim2.new(0, 24, 0.5, -math.floor(FULL * s0 / 2))

    if Workspace.CurrentCamera then
        table.insert(GlobalConnections,
            Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(Fit))
    end

    badge.Activated:Connect(function()
        minimized = not minimized
        TweenService:Create(main,
            TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
            { Size = UDim2.fromOffset(WIDTH, minimized and MINI or FULL) }):Play()
        badge.Text = minimized and "[+]" or "[DK]"
    end)

    local dragging, dragStart, startPos = false, nil, nil

    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging  = true
            dragStart = input.Position
            startPos  = main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    table.insert(GlobalConnections,
        UserInputService.InputChanged:Connect(function(input)
            if not dragging or not dragStart or not startPos then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch then
                local delta = input.Position - dragStart
                main.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end))

    table.insert(GlobalConnections,
        UserInputService.InputBegan:Connect(function(input, processed)
            if processed then return end
            if input.KeyCode == CFG.UIToggleKey then
                main.Visible = not main.Visible
            end
        end))

    ------------------------------------------------------------
    -- toasts
    ------------------------------------------------------------

    local toastHolder = Make("Frame", {
        AnchorPoint            = Vector2.new(1, 1),
        Position               = UDim2.new(1, -16, 1, -16),
        Size                   = UDim2.fromOffset(310, 320),
        BackgroundTransparency = 1,
        Parent                 = gui,
    }, {
        Make("UIListLayout", {
            VerticalAlignment   = Enum.VerticalAlignment.Bottom,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            Padding             = UDim.new(0, 8),
            SortOrder           = Enum.SortOrder.LayoutOrder,
        }),
    })

    local toastCount = 0
    local liveToasts = {}

    function UI.Toast(category, message)

        if not CFG.Notifications or not toastHolder.Parent then return end

        toastCount += 1
        local color = ColorFor(category)

        local slot = Make("Frame", {
            Size                   = UDim2.fromOffset(310, 58),
            BackgroundTransparency = 1,
            LayoutOrder            = toastCount,
            Parent                 = toastHolder,
        })
        local body = Make("Frame", {
            Size                   = UDim2.fromScale(1, 1),
            Position               = UDim2.fromOffset(340, 0),
            BackgroundColor3       = Theme.Bg,
            BackgroundTransparency = 0.03,
            Parent                 = slot,
        }, { Corner(8) })
        Stroke(color, 1.2, 0.2).Parent = body

        Make("Frame", {
            Size             = UDim2.new(0, 4, 1, -14),
            Position         = UDim2.fromOffset(7, 7),
            BackgroundColor3 = color,
            BorderSizePixel  = 0,
            Parent           = body,
        }, { Corner(2) })

        Label({
            Text       = "ANTIKILL  -  BY DINOKID",
            TextSize   = 11,
            TextColor3 = color,
            Position   = UDim2.fromOffset(19, 7),
            Size       = UDim2.new(1, -28, 0, 16),
            Parent     = body,
        })
        Label({
            Text           = category .. ": " .. tostring(message),
            TextSize       = 12,
            TextWrapped    = true,
            TextYAlignment = Enum.TextYAlignment.Top,
            Position       = UDim2.fromOffset(19, 25),
            Size           = UDim2.new(1, -28, 0, 28),
            Parent         = body,
        })

        TweenService:Create(body,
            TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
            { Position = UDim2.fromOffset(0, 0) }):Play()

        table.insert(liveToasts, slot)
        while #liveToasts > 4 do
            local oldest = table.remove(liveToasts, 1)
            if oldest then oldest:Destroy() end
        end

        task.delay(3.2, function()
            if not slot.Parent then return end
            local out = TweenService:Create(body,
                TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
                { Position = UDim2.fromOffset(340, 0) })
            out:Play()
            out.Completed:Wait()
            local i = table.find(liveToasts, slot)
            if i then table.remove(liveToasts, i) end
            slot:Destroy()
        end)
    end

    ------------------------------------------------------------
    -- live log feed
    ------------------------------------------------------------

    local feedItems = {}
    local feedCount = 0
    local dimHex = Theme.Dim:ToHex()

    function UI.Feed(entry)

        if not feed.Parent then return end

        feedCount += 1

        local line = string.format(
            '<font color="#%s">%6.1f</font>  <font color="#%s">%s</font>  %s',
            dimHex, entry.t, ColorFor(entry.cat):ToHex(),
            Escape(entry.cat), Escape(entry.msg))

        local item = Label({
            Text           = line,
            RichText       = true,
            TextSize       = 11,
            TextWrapped    = true,
            TextTruncate   = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top,
            AutomaticSize  = Enum.AutomaticSize.Y,
            Size           = UDim2.new(1, 0, 0, 0),
            LayoutOrder    = -feedCount,
            Parent         = feed,
        })

        table.insert(feedItems, item)
        while #feedItems > 45 do
            local oldest = table.remove(feedItems, 1)
            if oldest then oldest:Destroy() end
        end

        feedCountText.Text = feedCount .. " events"
    end

    ------------------------------------------------------------
    -- live refresh
    ------------------------------------------------------------

    local function CountOwnTools()
        local n = 0
        for _, container in ipairs({ Backpack or false, Character or false }) do
            if container then
                for _, t in ipairs(container:GetChildren()) do
                    if t:IsA("Tool") and not IsForeignTool(t) then n += 1 end
                end
            end
        end
        return n
    end

    task.spawn(function()

        local dots = 0

        while Alive and gui.Parent do

            dots = dots % 3 + 1
            local now = os.clock()
            local text, color

            if ReanimMode then
                text, color = "REANIMATED // BODY GUARD PAUSED", Theme.Cyan
            elseif OwnershipLost then
                text, color = "BODY TAKEN OVER // CUTTING LINKS", Theme.Red
            elseif WasAnchored then
                text, color = "FROZEN // TOOL LINK CUT", Theme.Red
            elseif now < LockdownUntil then
                text, color = string.format("LOCKDOWN // %.1fs", LockdownUntil - now), Theme.Yellow
            elseif TouchOff then
                text, color = "DROPPED " .. string.upper(NearDropped and NearDropped.Name or "TOOL")
                    .. " NEAR // TOUCH OFF", Theme.Yellow
            elseif not Root or not Root.Parent then
                text, color = "WAITING FOR CHARACTER" .. string.rep(".", dots), Theme.Dim
            else
                text, color = "SHIELD ARMED // SCANNING" .. string.rep(".", dots), Theme.Green
            end

            statusText.Text       = text
            statusText.TextColor3 = color
            sweep.BackgroundColor3 = color
            iconStroke.Color      = color
            icon.Text = ReanimMode and "🦖" or (color == Theme.Red and "⚠️" or "🔒")

            local upright = Root ~= nil and Root.Parent ~= nil
                and Root.CFrame.UpVector.Y > 0.5
            bodyLine.Text = string.format("> BODY // %s  |  %s",
                OwnershipState, upright and "UPRIGHT" or "DOWN")
            bodyLine.TextColor3 = (OwnershipState == "LOST" or not upright)
                and Theme.Red or Theme.Green

            toolLine.Text = string.format("> TOOLS // %d yours  |  %d hidden  |  %d blocked",
                CountOwnTools(), #HiddenTools, Stats.ToolBlocked)

            tiles.BLOCKS.Text   = tostring(Stats.TotalBlocks)
            tiles.TOOLKILL.Text = tostring(Stats.ToolBlocked)
            tiles.LINKS.Text    = tostring(Stats.GripSevered + Stats.Assembly
                + Stats.Tether + Stats.Joint)
            tiles.SAVES.Text    = tostring(Stats.Recoveries + Stats.Teleport
                + Stats.PositionAssert + Stats.StateSaves + Stats.OwnershipLost)

            hiddenText.Text = "HIDDEN TOOLS: " .. #HiddenTools

            local worst = nil
            for _, data in pairs(PlayerThreats) do
                if data.Flagged and data.Player and data.Player.Parent
                    and (not worst or data.Score > worst.Score) then
                    worst = data
                end
            end
            if worst then
                footLeft.Text = "THREAT: " .. worst.Player.Name
                footLeft.TextColor3 = Theme.Red
            else
                footLeft.Text = "Gui Ready"
                footLeft.TextColor3 = Theme.Green
            end

            task.wait(0.2)
        end
    end)

    ------------------------------------------------------------
    -- go live
    ------------------------------------------------------------

    UI.Built = true
    UIHooks.Feed  = UI.Feed
    UIHooks.Toast = UI.Toast

    -- what happened before the panel existed
    for i = math.max(1, #EventLog - 20), #EventLog do
        if EventLog[i] then UI.Feed(EventLog[i]) end
    end

    UI.Toast("SECURE", "shield armed - " .. CFG.UIToggleKey.Name .. " shows / hides the panel")
end


--============================================================
-- STOP   (a re-run calls this on the old copy)
--============================================================

_G.DinoAntikillStop = function()

    Alive = false

    for _, connection in ipairs(GlobalConnections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(GlobalConnections)

    DisconnectCharacterConnections()
    ClearAllShields()

    if TouchOff then SetBodyTouch(true) end
    ForceReleaseAnchor()

    CFG.StateLock = false
    ApplyStateLock()

    UIHooks.Feed, UIHooks.Toast = nil, nil
    if UI.Gui then pcall(function() UI.Gui:Destroy() end) end
end


--============================================================
-- STARTUP
--============================================================

if CFG.UI then
    task.spawn(function()
        local ok, err = pcall(UI.Build)
        if not ok then
            warn("[ANTIKILL] panel failed to build: " .. tostring(err))
        end
    end)
end

Debug("=======================================")
Debug("ANTIKILL by DinoKid  v3  READY")
Debug("---------------------------------------")
Debug("Tool firewall:            " .. (CFG.ToolFirewall and "ON (your own tools allowed)" or "OFF"))
Debug("Hide blocked tools:       " .. (CFG.HideForeignTools and "ON" or "OFF"))
Debug("Pickup shield:            " .. (CFG.PickupShield and "ON" or "OFF"))
Debug("Knockdown lock:           " .. (CFG.StateLock and "ON" or "OFF"))
Debug("Void shield:              " .. (CFG.VoidShield and "ON" or "OFF"))
Debug("Ownership guard:          " .. (CFG.OwnershipGuard and "ON" or "OFF"))
Debug("Reanimate aware:          " .. (CFG.ReanimateAware and "ON" or "OFF"))
Debug("Carry-link sweep:         " .. (CFG.GripSweep and "ON (physics + render)" or "OFF"))
Debug("Teleport / void guard:    " .. (CFG.TeleportGuard and "ON" or "OFF"))
Debug("Anchor lock:              " .. (CFG.AnchorLock and "ON" or "OFF"))
Debug("Assembly / joint / seat / touch guards: ON")
Debug("Player threat + reanimation detection:  ON")
Debug("---------------------------------------")
Debug("_G.AntiFlingSecure()         every cut at once")
Debug("_G.AntiFlingRestoreTools()   un-hide blocked tools")
Debug("_G.AntiFlingCleanTools()     hide picked-up tools now")
Debug("_G.AntiFlingStats()          stats dump")
Debug("_G.AntiFlingLog()            timeline after a death")
Debug("_G.AntiFlingAllowTool(name)  whitelist a tool by name")
Debug("_G.AntiFlingTeleportGrace(n) suppress for n seconds")
