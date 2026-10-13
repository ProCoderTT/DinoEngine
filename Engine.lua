--[[
    DINO REANIMATE  ·  reanimate engine
    ─────────────────────────────────────────────────────────────────
    A full-body limb reanimate ENGINE, in the spirit of Gelatek
    Reanimate and Krypton: it does the hard part (fake rig, joints,
    netless, ownership, permadeath, accessories, respawns) and hands your
    script a rig to animate. No UI, no built-in moves: you build the
    reanimate on top of it.

    RUN (Gelatek style: reanimates as soon as it loads)
        local Global = (getgenv and getgenv()) or shared
        Global.DinoReanimateConfig = { RigMode = "Auto" }   -- any keys from DEFAULTS
        loadstring(game:HttpGet("<raw url of this file>"))()

    SCRIPTING ON TOP OF IT
        local Dino = loadstring(game:HttpGet("<raw url>"))()
        local rig = Dino.Start()      -- the running rig (waits if it's still starting)
        -- set AutoStart = false in the config to start it yourself with Dino.Start({...})

    ANIMATE (pick any mix)
        rig:PlayAnimation(12345678, { Loop = true })   -- any Roblox animation id
        rig:PlayAnimation("dance2")                    -- emotes from the default set
        rig:SetAnimation("idle", 12345678)             -- animation pack override
        rig:SetDefaultAnimations(false)                -- turn the movement anims off
        rig:PlayKeyframes(myKeyframeTable)             -- keyframes written in your script
        rig:PlayKeyframes("savedName")                 -- JSON from AnimationFolder
        rig:OnStep(function(dt, rig)                   -- procedural: runs every frame
            rig.JointsByPart["Right Arm"].Transform = CFrame.Angles(0, 0, math.rad(90))
        end)

    RESPAWNS
        It reanimates again by itself after a respawn (AutoRestart). Hook
        Dino.Started once and your script follows every new rig:
            Dino.Started:Connect(function(rig) ... end)

    WHAT IT DOES BETTER THAN GELATEK
      Gelatek                               Dino
      Constant (0,0,-25.8) velocity on       Velocity = the part's real motion
        every part, every frame: others        (root velocity + animation), so
        see drift and snap-back                other players see smooth motion
      CFrames limbs after physics from last  Drives before physics from live
        step's fake positions (frame late)     forward kinematics, re-pins after
      BodyVelocity/BodyAngularVelocity       Per-part anti-gravity force only
      Sets Player.Character to the fake rig  Keeps your character instance (Zeon
        (servers can read it as a respawn)     split), so no respawn is triggered
      Hard-coded R15->R6 offsets             Measured from your own body
      Hats re-welded by name                 Hats follow their exact limb and
                                               offset, by instance
      Joints broken on your screen only      Server-side break + permadeath via
                                               replicatesignal when available,
                                               rebuilt joints cut again
      Void -> dies or spawn                  Back to your last safe spot
      Old Animate script copy                Animation controller + keyframes +
                                               per-frame hook for your own anims
      Loads remote code                      Loads nothing

    Not included on purpose: Gelatek's fling modes (Bullet, TorsoFling).
]]

local Global = (getgenv and getgenv()) or shared

-- One engine at a time: retire an older copy (and its auto restart)
if type(Global.DinoReanimate) == "table" and type(Global.DinoReanimate.Destroy) == "function" then
    pcall(Global.DinoReanimate.Destroy)
end


--==================================================
-- SERVICES
--==================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui       = game:GetService("StarterGui")
local HttpService      = game:GetService("HttpService")
local TextChatService  = game:GetService("TextChatService")
local Workspace        = game:GetService("Workspace")

local Player = Players.LocalPlayer


--==================================================
-- CONFIG
--==================================================

local DEFAULTS = {
    -- Start
    AutoStart      = true,      -- reanimate as soon as the file is loaded (Gelatek style)

    -- Rig
    RigMode        = "Auto",    -- "Auto" (match your avatar) | "R15ToR6" (R15 avatar, R6 animations)
    Animations     = true,      -- built-in idle/walk/jump/... controller
    EmoteChat      = true,      -- /e wave, /e dance2, /e <id> ...
    AnimationFolder = "AutorigReanim",  -- JSON keyframe animations (FILES)

    -- Body / death
    PermanentDeath = true,      -- stay dead on the server so it never respawns you mid reanimate
    PermadeathMethod = "Auto",  -- "Auto"     : replicatesignal, and if your executor can't, character reassign
                                -- "Signal"   : replicatesignal(ConnectDiedSignalBackend) only (Krypton)
                                -- "Reassign" : Player.Character = nil -> back (Zeon / Uhhhhhh), no executor function needed
                                -- "Command"  : only the game's -pd chat command
    ReassignSettle = 5,         -- seconds the server needs to take a reassign before the body may break
    KeepNeck       = "Auto",    -- "Auto" | true | false. Keeping it keeps you alive without permadeath (head can't move on its own)
    AutoRestart    = true,      -- reanimate again after a respawn

    -- Chat, in order, before the split
    StartMessage   = "This reanimate was made by the DinoKid himself",
    StartWait      = 2,
    ChatCommands   = { "-net", "-pd" },
    CommandGap     = 1,
    SettleWait     = 1,

    -- Drive
    NetlessLift    = true,      -- keeps lost parts floating instead of dropping (see driver notes)
    AntiGravity    = true,
    VoidGuard      = true,
    MaxDriveSpeed  = 120,
    MaxDriveSpin   = 45,
    PhysicsTweaks  = true,      -- no sleep, no throttling, max simulation radius

    -- Safety
    VoidRecovery   = "LastSafe",   -- "LastSafe" | "Spawn" | "Stop"
    VoidMargin     = 40,

    -- Feedback
    OwnershipBoxes = false,     -- red box on any part you don't own
    OwnershipLog   = true,
}

-- Live config. Dino.Start(config) fills it from DEFAULTS + your table.
local Config = {}
for k, v in pairs(DEFAULTS) do Config[k] = v end


--==================================================
-- CAPABILITIES
--==================================================

local Caps = {
    replicatesignal   = type(replicatesignal) == "function" and replicatesignal or nil,
    sethiddenproperty = type(sethiddenproperty) == "function" and sethiddenproperty or nil,
    isnetworkowner    = type(isnetworkowner) == "function" and isnetworkowner or nil,
    readfile          = type(readfile) == "function" and readfile or nil,
    listfiles         = type(listfiles) == "function" and listfiles or nil,
    isfolder          = type(isfolder) == "function" and isfolder or nil,
}


--==================================================
-- LOGGING
--==================================================

local function log(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    warn("[Dino] " .. (ok and msg or tostring(fmt)))
end

local function notify(title, text, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = dur or 4 })
    end)
end

local TChannels  = TextChatService:FindFirstChild("TextChannels")
local RBXGeneral = TChannels and TChannels:FindFirstChild("RBXGeneral")

local function chat(msg)
    if not msg or msg == "" then return end
    local ok = pcall(function() Player:Chat(msg) end)
    local general = RBXGeneral or (TChannels and TChannels:FindFirstChild("RBXGeneral"))
    if general then
        pcall(function() general:SendAsync(msg) end)
    elseif not ok then
        log("couldn't send chat: %s", msg)
    end
end


--==================================================
-- STATE (one run)
--==================================================

local State: { [string]: any } = { running = false }   -- the current run
local Conns = {}     -- every connection of the current run

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(Conns, c)
    return c
end

local function disconnectAll()
    for _, c in ipairs(Conns) do pcall(c.Disconnect, c) end
    table.clear(Conns)
end


--==================================================
-- NETLESS DRIVER
--==================================================
--
-- Same driver as the autorig reanimate, hardened over many rounds:
--   · velocity = fake root's physics velocity + the spin carrying the
--     part around the root + the animation's own motion in root space,
--     so the body and the root agree on every frame (starts and stops
--     included) and other players interpolate along the real path
--   · NetlessLift: the vertical part of the SENT velocity is held at
--     ~25 studs/s. Nothing rises (the part is pinned back after every
--     step); it only matters if someone else takes the part over, then
--     it floats instead of dropping into the void
--   · real mass for the first 5.67 s of a claim, massless after
--   · anti-gravity force, so the solver doesn't bleed gravity into the
--     velocity other players see
--   · reassert after the step at the predicted pose, never behind it
--==================================================

local NETLESS_VELOCITY = 25.01
local VOID_Y = Workspace.FallenPartsDestroyHeight
if VOID_Y ~= VOID_Y then VOID_Y = -500 end

local Drive = {
    claims   = setmetatable({}, { __mode = "k" }),
    lastCf   = setmetatable({}, { __mode = "k" }),
    predCf   = setmetatable({}, { __mode = "k" }),
    localPrv = setmetatable({}, { __mode = "k" }),
    antiGrav = setmetatable({}, { __mode = "k" }),
    ctx      = { rootCF = nil, rootVel = Vector3.zero, rootAngVel = Vector3.zero },
}

local function ownsPart(part)
    if Caps.isnetworkowner then
        local ok, r = pcall(Caps.isnetworkowner, part)
        if ok then return r end
    end
    local ok, age = pcall(function() return part.ReceiveAge end)
    return ok and age == 0
end

local function applyAntiGravity(part)
    local vf = Drive.antiGrav[part]
    if not Config.AntiGravity then
        if vf then vf.Force = Vector3.zero end
        return
    end
    if not (vf and vf.Parent == part) then
        local att = Instance.new("Attachment")
        att.Name = "DinoAG"
        att.Parent = part
        vf = Instance.new("VectorForce")
        vf.Name = "DinoAG"
        vf.Attachment0 = att
        vf.RelativeTo = Enum.ActuatorRelativeTo.World
        vf.ApplyAtCenterOfMass = true
        vf.Force = Vector3.zero
        vf:SetAttribute("AntiFlingAllowed", true)
        vf.Parent = part
        Drive.antiGrav[part] = vf
    end
    if part.AssemblyRootPart == part then
        vf.Force = Vector3.new(0, part.AssemblyMass * Workspace.Gravity, 0)
    else
        vf.Force = Vector3.zero
    end
end

local function prepPart(part)
    part.CanCollide = false
    pcall(function() part.CanQuery = false end)
    pcall(function() part.CanTouch = false end)
    part.Anchored = false
    part.Massless = true
    part.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0, 0, 0, 0)
    Drive.claims[part], Drive.lastCf[part], Drive.predCf[part], Drive.localPrv[part] = nil, nil, nil, nil
end

local function driveNetless(part, newcf, dt)
    if dt <= 0 or not (part and part.Parent) then return end
    local timing = os.clock()

    if Config.VoidGuard and newcf.Y < VOID_Y + 5 then
        newcf = newcf + Vector3.new(0, VOID_Y + 5 - newcf.Y, 0)
    end

    -- lost it: restart the claim (strong lift + real mass) once it's back
    if Drive.claims[part] and not ownsPart(part) then
        Drive.claims[part] = nil
    end

    local lastcf = Drive.lastCf[part] or part.CFrame
    local vel = (newcf.Position - lastcf.Position) / dt
    local ra, rb = lastcf:ToObjectSpace(newcf):ToAxisAngle()
    local rvel = lastcf:VectorToWorldSpace(ra * rb) / dt
    if rvel.X ~= rvel.X then rvel = Vector3.zero end

    local ctx = Drive.ctx
    if ctx.rootCF then
        local localNow  = ctx.rootCF:ToObjectSpace(newcf)
        local localPrev = Drive.localPrv[part]
        Drive.localPrv[part] = localNow
        if localPrev then
            local animVel = ctx.rootCF:VectorToWorldSpace((localNow.Position - localPrev.Position) / dt)
            local carry   = ctx.rootAngVel:Cross(newcf.Position - ctx.rootCF.Position)
            local v2 = ctx.rootVel + carry + animVel
            local sa, sb = localPrev:ToObjectSpace(localNow):ToAxisAngle()
            local w2 = ctx.rootAngVel + ctx.rootCF:VectorToWorldSpace(localPrev:VectorToWorldSpace(sa * sb)) / dt
            if v2.X == v2.X and v2.Y == v2.Y and v2.Z == v2.Z then vel = v2 end
            if w2.X == w2.X and w2.Y == w2.Y and w2.Z == w2.Z then rvel = w2 end
        end
    end
    Drive.lastCf[part] = newcf

    local claim = Drive.claims[part]
    if not claim then
        claim = timing
        Drive.claims[part] = timing
    end
    if timing - claim < 5.67 then
        part.Massless = false
        part.CustomPhysicalProperties = nil
    else
        part.Massless = true
        part.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0, 0, 0, 0)
    end

    if vel.X ~= vel.X then vel = Vector3.zero end
    if vel.Magnitude > Config.MaxDriveSpeed then vel = vel.Unit * Config.MaxDriveSpeed end
    if rvel.Magnitude > Config.MaxDriveSpin then rvel = rvel.Unit * Config.MaxDriveSpin end

    local sendVel = vel
    if Config.NetlessLift then
        local lift = NETLESS_VELOCITY + (math.sin(timing * 0.5) + 1) / 2
        if timing - claim < 0.51 then lift = lift * 2 end
        sendVel = Vector3.new(vel.X, math.max(vel.Y, lift), vel.Z)
    end

    part.CFrame = newcf
    part.AssemblyLinearVelocity  = sendVel
    part.AssemblyAngularVelocity = rvel
    applyAntiGravity(part)

    local pred = newcf + vel * dt
    local spin = rvel.Magnitude * dt
    if spin > 1e-6 then
        pred = CFrame.fromAxisAngle(rvel.Unit, spin) * (pred - pred.Position) + pred.Position
    end
    Drive.predCf[part] = pred
end

local function reassert(part)
    if not (part and part.Parent) then return end
    local cf = Drive.predCf[part] or Drive.lastCf[part]
    if cf then part.CFrame = cf end
end


--==================================================
-- JOINTS
--==================================================

local BODY_JOINT_CLASSES = {
    AnimationConstraint = true, BallSocketConstraint = true, HingeConstraint = true,
    RigidConstraint = true, RodConstraint = true, RopeConstraint = true,
    SpringConstraint = true, PrismaticConstraint = true, CylindricalConstraint = true,
    UniversalConstraint = true,
}

local function isJoint(v)
    return v:IsA("JointInstance") or v:IsA("WeldConstraint") or BODY_JOINT_CLASSES[v.ClassName] == true
end

-- The two parts a joint/constraint connects
local function jointParts(j)
    local p0, p1
    pcall(function()
        if j:IsA("JointInstance") or j:IsA("WeldConstraint") then
            p0, p1 = j.Part0, j.Part1
        else
            p0 = j.Attachment0 and j.Attachment0.Parent
            p1 = j.Attachment1 and j.Attachment1.Parent
        end
    end)
    return p0, p1
end

-- Standard R15 rig attachments: [child] = { parent, attachment }
local R15_RIG = {
    LowerTorso    = { "HumanoidRootPart", "RootRigAttachment" },
    UpperTorso    = { "LowerTorso",    "WaistRigAttachment" },
    Head          = { "UpperTorso",    "NeckRigAttachment" },
    LeftUpperArm  = { "UpperTorso",    "LeftShoulderRigAttachment" },
    LeftLowerArm  = { "LeftUpperArm",  "LeftElbowRigAttachment" },
    LeftHand      = { "LeftLowerArm",  "LeftWristRigAttachment" },
    RightUpperArm = { "UpperTorso",    "RightShoulderRigAttachment" },
    RightLowerArm = { "RightUpperArm", "RightElbowRigAttachment" },
    RightHand     = { "RightLowerArm", "RightWristRigAttachment" },
    LeftUpperLeg  = { "LowerTorso",    "LeftHipRigAttachment" },
    LeftLowerLeg  = { "LeftUpperLeg",  "LeftKneeRigAttachment" },
    LeftFoot      = { "LeftLowerLeg",  "LeftAnkleRigAttachment" },
    RightUpperLeg = { "LowerTorso",    "RightHipRigAttachment" },
    RightLowerLeg = { "RightUpperLeg", "RightKneeRigAttachment" },
    RightFoot     = { "RightLowerLeg", "RightAnkleRigAttachment" },
}

-- Which R6 limb each R15 part rides in R15ToR6 mode
local R15_TO_R6 = {
    LowerTorso = "Torso", UpperTorso = "Torso", Head = "Head",
    LeftUpperArm = "Left Arm", LeftLowerArm = "Left Arm", LeftHand = "Left Arm",
    RightUpperArm = "Right Arm", RightLowerArm = "Right Arm", RightHand = "Right Arm",
    LeftUpperLeg = "Left Leg", LeftLowerLeg = "Left Leg", LeftFoot = "Left Leg",
    RightUpperLeg = "Right Leg", RightLowerLeg = "Right Leg", RightFoot = "Right Leg",
}

local R6_PARTS  = { "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
local R15_PARTS = {
    "LowerTorso", "UpperTorso", "Head",
    "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
}

-- Rest CFrame of every body part relative to the root, from the joints
-- as they are right now (Transform ignored = rest pose). Motor6D first,
-- then AnimationConstraint, then rig attachments.
local function restPose(model, root)
    local joints = {}   -- [childPart] = { parent = Part, c0, c1 }
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("Motor6D") and d.Part0 and d.Part1 then
            joints[d.Part1] = joints[d.Part1] or { parent = d.Part0, c0 = d.C0, c1 = d.C1 }
        end
    end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("AnimationConstraint") and d.Attachment0 and d.Attachment1 then
            local p0, p1 = d.Attachment0.Parent, d.Attachment1.Parent
            if p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") and not joints[p1] then
                joints[p1] = { parent = p0, c0 = d.Attachment0.CFrame, c1 = d.Attachment1.CFrame }
            end
        end
    end
    for child, def in pairs(R15_RIG) do
        local cp = model:FindFirstChild(child)
        local pp = model:FindFirstChild(def[1])
        if cp and pp and not joints[cp] then
            local ca, pa = cp:FindFirstChild(def[2]), pp:FindFirstChild(def[2])
            if ca and pa and ca:IsA("Attachment") and pa:IsA("Attachment") then
                joints[cp] = { parent = pp, c0 = pa.CFrame, c1 = ca.CFrame }
            end
        end
    end

    local rest = { [root] = CFrame.identity }
    for _ = 1, 64 do
        local progress = false
        for child, j in pairs(joints) do
            if not rest[child] and rest[j.parent] then
                rest[child] = rest[j.parent] * j.c0 * j.c1:Inverse()
                progress = true
            end
        end
        if not progress then break end
    end
    return rest
end

-- Animated joints of the fake rig in parent-first order, for live FK.
-- Motor6D, or AnimationConstraint on newer R15 avatars (same maths:
-- part1 = part0 * C0 * Transform * C1:Inverse(), with the constraint's
-- attachments as C0/C1). One record per child part, enabled one first.
local function orderedMotors(model, root)
    local byChild = {}
    local function consider(rec)
        local cur = byChild[rec.part1]
        local enabled = true
        pcall(function() enabled = rec.joint.Enabled ~= false end)
        rec.enabled = enabled
        if not cur or (enabled and not cur.enabled) or (enabled == cur.enabled and rec.motor and not cur.motor) then
            byChild[rec.part1] = rec
        end
    end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("Motor6D") and d.Part0 and d.Part1 then
            consider({ joint = d, part0 = d.Part0, part1 = d.Part1, motor = true })
        elseif d:IsA("AnimationConstraint") and d.Attachment0 and d.Attachment1 then
            local p0, p1 = d.Attachment0.Parent, d.Attachment1.Parent
            if p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
                consider({ joint = d, part0 = p0, part1 = p1, motor = false })
            end
        end
    end
    local placed, out = { [root] = true }, {}
    for _ = 1, 64 do
        local progress = false
        for child, r in pairs(byChild) do
            if not placed[child] and placed[r.part0] then
                placed[child] = true
                table.insert(out, r)
                progress = true
            end
        end
        if not progress then break end
    end
    return out
end

local function jointC0(r)
    if r.motor then return r.joint.C0 end
    return r.joint.Attachment0.CFrame
end

local function jointC1(r)
    if r.motor then return r.joint.C1 end
    return r.joint.Attachment1.CFrame
end


--==================================================
-- FAKE RIG
--==================================================
--
-- The fake rig is a local, invisible character that becomes your
-- Player.Character: your controls, camera and the animation controller
-- all act on it. Your real parts copy it every frame.
--
-- Auto: a stripped clone of your own character (R6 or R15), so its
--       joints are exactly yours and any animation made for your body
--       type plays natively.
-- R15ToR6: a fresh standard R6 rig; your R15 parts ride its six limbs
--       at offsets measured from your own body.
--==================================================

local R6_MOTORS = {
    { "RootJoint",      "HumanoidRootPart", "Torso",
      CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0),  CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0) },
    { "Neck",           "Torso", "Head",
      CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0),  CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0) },
    { "Right Shoulder", "Torso", "Right Arm",
      CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, -0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, -0, -1, 0, 0) },
    { "Left Shoulder",  "Torso", "Left Arm",
      CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
    { "Right Hip",      "Torso", "Right Leg",
      CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, -0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, -0, -1, 0, 0) },
    { "Left Hip",       "Torso", "Left Leg",
      CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
}

local R6_SIZES = {
    HumanoidRootPart = Vector3.new(2, 2, 1), Torso = Vector3.new(2, 2, 1), Head = Vector3.new(2, 1, 1),
    ["Left Arm"] = Vector3.new(1, 2, 1), ["Right Arm"] = Vector3.new(1, 2, 1),
    ["Left Leg"] = Vector3.new(1, 2, 1), ["Right Leg"] = Vector3.new(1, 2, 1),
}

local function copyHumanoidSettings(from, to)
    for _, prop in ipairs({ "WalkSpeed", "UseJumpPower", "JumpPower", "JumpHeight", "MaxSlopeAngle", "AutoRotate" }) do
        pcall(function() to[prop] = from[prop] end)
    end
    pcall(function() to.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end)
    pcall(function() to.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff end)
    pcall(function() to.BreakJointsOnDeath = false end)
end

local function buildR6Rig(realHum, rootCF)
    local rig = Instance.new("Model")
    rig.Name = "DinoRig"

    local parts = {}
    for name, size in pairs(R6_SIZES) do
        local p = Instance.new("Part")
        p.Name = name
        p.Size = size
        p.Transparency = 1
        p.CanCollide = false
        p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
        p.Parent = rig
        parts[name] = p
    end
    rig.PrimaryPart = parts.HumanoidRootPart
    parts.HumanoidRootPart.CFrame = rootCF

    for _, m in ipairs(R6_MOTORS) do
        local j = Instance.new("Motor6D")
        j.Name, j.Part0, j.Part1, j.C0, j.C1 = m[1], parts[m[2]], parts[m[3]], m[4], m[5]
        j.Parent = parts[m[2]]
        parts[m[3]].CFrame = parts[m[2]].CFrame * m[4] * m[5]:Inverse()
    end

    local hum = Instance.new("Humanoid")
    hum.RigType = Enum.HumanoidRigType.R6
    hum.HipHeight = 0
    copyHumanoidSettings(realHum, hum)
    hum.Parent = rig
    Instance.new("Animator").Parent = hum
    return rig
end

local STRIP_CLASSES = {
    Script = true, LocalScript = true, ModuleScript = true, Tool = true, Accessory = true,
    Accoutrement = true, ForceField = true, BillboardGui = true, SurfaceGui = true, Sound = true,
    ParticleEmitter = true, Trail = true, Beam = true, Fire = true, Smoke = true, Sparkles = true,
    Highlight = true, SelectionBox = true,
}

local function cloneRig(realChar, realHum)
    for _, d in ipairs(realChar:GetDescendants()) do pcall(function() d.Archivable = true end) end
    realChar.Archivable = true
    local rig = realChar:Clone()
    rig.Name = "DinoRig"

    for _, d in ipairs(rig:GetDescendants()) do
        if STRIP_CLASSES[d.ClassName] then
            pcall(d.Destroy, d)
        end
    end
    for _, d in ipairs(rig:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Transparency = 1
            d.CanCollide = false
            d.Anchored = false
        elseif d:IsA("Decal") or d:IsA("Texture") then
            d.Transparency = 1
        elseif d:IsA("BallSocketConstraint") or d:IsA("HingeConstraint") then
            pcall(d.Destroy, d)
        end
    end

    local hum = rig:FindFirstChildOfClass("Humanoid")
    copyHumanoidSettings(realHum, hum)
    if not hum:FindFirstChildOfClass("Animator") then
        Instance.new("Animator").Parent = hum
    end
    rig.PrimaryPart = rig:FindFirstChild("HumanoidRootPart")
    return rig
end


--==================================================
-- ACCESSORIES
--==================================================
--
-- Every worn accessory follows the body part it was attached to, at the
-- exact offset it had, by instance. No re-welding by name, so two hats
-- with the same name can't steal each other's spot.
--==================================================

local function accessoryLimb(acc, handle, bodySet, model)
    -- the joint holding it
    local function viaJoint(container)
        for _, d in ipairs(container:GetDescendants()) do
            if isJoint(d) then
                local p0, p1 = jointParts(d)
                if p0 == handle and p1 and bodySet[p1] then return p1 end
                if p1 == handle and p0 and bodySet[p0] then return p0 end
            end
        end
        return nil
    end
    local limb = viaJoint(acc)
    if not limb then
        for part in pairs(bodySet) do
            for _, d in ipairs(part:GetChildren()) do
                if isJoint(d) then
                    local p0, p1 = jointParts(d)
                    if p0 == handle or p1 == handle then return part end
                end
            end
        end
    end
    if limb then return limb end

    -- matching attachment name
    for _, a in ipairs(handle:GetChildren()) do
        if a:IsA("Attachment") then
            for part in pairs(bodySet) do
                if part:FindFirstChild(a.Name) then return part end
            end
        end
    end
    return model:FindFirstChild("Head")
end


--==================================================
-- JOINT BREAKING
--==================================================

-- Cut every joint between two body parts (wherever it is parented) and
-- keep cutting anything that gets rebuilt. keepNeck leaves the head on.
local function startJointSweep(run, bodySet, keepNeck, headPart)
    run.hatSet = run.hatSet or {}
    local function shouldCut(j)
        if j.Name == "DinoAG" or not isJoint(j) then return false end
        local p0, p1 = jointParts(j)
        if not (p0 and p1) then return false end
        if keepNeck and (p0 == headPart or p1 == headPart) and (bodySet[p0] and bodySet[p1]) then
            return false
        end
        -- body-to-body, or the weld of an accessory we drive
        if bodySet[p0] and bodySet[p1] then return true end
        local other = bodySet[p0] and p1 or (bodySet[p1] and p0)
        if other and run.hatSet[other] then return true end
        return false
    end

    local function sweep()
        local cut = 0
        for part in pairs(bodySet) do
            if part.Parent then
                local ok, joints = pcall(function() return part:GetJoints() end)
                if ok and type(joints) == "table" then
                    for _, j in ipairs(joints) do
                        if shouldCut(j) then
                            pcall(j.Destroy, j)
                            cut += 1
                        end
                    end
                end
            end
        end
        return cut
    end

    local first = sweep()
    local rebuilt, told = 0, false
    task.spawn(function()
        local t0 = os.clock()
        while run.running do
            task.wait((os.clock() - t0 < 5) and 0.1 or 0.5)
            local n = sweep()
            if n > 0 then
                rebuilt += n
                if not told then
                    told = true
                    log("the game rebuilt %d body joints; they're cut as they come back", n)
                end
            end
        end
    end)
    return first
end


--==================================================
-- PHYSICS TWEAKS
--==================================================

local function physicsTweaks()
    if not Config.PhysicsTweaks then return end
    pcall(function() settings().Physics.AllowSleep = false end)
    pcall(function()
        settings().Physics.PhysicsEnvironmentalThrottle = Enum.EnviromentalPhysicsThrottle.Disabled
    end)
    if Caps.sethiddenproperty then
        pcall(Caps.sethiddenproperty, Workspace, "InterpolationThrottling", Enum.InterpolationThrottlingMode.Disabled)
    end
end

local function maxSimulationRadius()
    if Caps.sethiddenproperty then
        pcall(Caps.sethiddenproperty, Player, "SimulationRadius", 1e9)
        pcall(Caps.sethiddenproperty, Player, "MaximumSimulationRadius", 1e9)
    else
        pcall(function() Player.SimulationRadius = 1e9 end)
    end
end


--==================================================
-- ANIMATION CONTROLLER
--==================================================
--
-- Runs on the fake rig's real Animator, so anything Roblox can play
-- plays: the default sets below, emotes, any animation id this game is
-- allowed to load, and animation-pack overrides per state.
--==================================================

local ANIM_SETS = {
    R6 = {
        idle     = { { "180435571", 9 }, { "180435792", 1 } },
        walk     = { { "180426354", 1 } },
        run      = { { "180426354", 1 } },
        jump     = { { "125750702", 1 } },
        fall     = { { "180436148", 1 } },
        climb    = { { "180436334", 1 } },
        sit      = { { "178130996", 1 } },
        swim     = { { "180426354", 1 } },
        swimidle = { { "180435571", 1 } },
        wave     = { { "128777973", 1 } },
        point    = { { "128853357", 1 } },
        dance1   = { { "182435998", 1 }, { "182491037", 1 }, { "182491065", 1 } },
        dance2   = { { "182436842", 1 }, { "182491248", 1 }, { "182491277", 1 } },
        dance3   = { { "182436935", 1 }, { "182491368", 1 }, { "182491423", 1 } },
        laugh    = { { "129423131", 1 } },
        cheer    = { { "129423030", 1 } },
    },
    R15 = {
        idle     = { { "507766666", 9 }, { "507766951", 1 } },
        walk     = { { "507777826", 1 } },
        run      = { { "507767714", 1 } },
        jump     = { { "507765000", 1 } },
        fall     = { { "507767968", 1 } },
        climb    = { { "507765644", 1 } },
        sit      = { { "2506281703", 1 } },
        swim     = { { "913384386", 1 } },
        swimidle = { { "913389285", 1 } },
        wave     = { { "507770239", 1 } },
        point    = { { "507770453", 1 } },
        dance1   = { { "507771019", 1 }, { "507771955", 1 }, { "507772104", 1 } },
        dance2   = { { "507776043", 1 }, { "507776720", 1 }, { "507776879", 1 } },
        dance3   = { { "507777268", 1 }, { "507777451", 1 }, { "507777623", 1 } },
        laugh    = { { "507770818", 1 } },
        cheer    = { { "507770677", 1 } },
    },
}

-- emote name -> loops
local EMOTES = { wave = false, point = false, dance1 = true, dance2 = true, dance3 = true, laugh = false, cheer = false }
local LOOPED = { idle = true, walk = true, run = true, climb = true, sit = true, swim = true, swimidle = true, fall = true }
local STATE_NAMES = { "idle", "walk", "run", "jump", "fall", "climb", "sit", "swim", "swimidle" }

local Anim = {
    overrides = {},   -- survives restarts
}

local function parseId(v)
    if type(v) == "number" then return tostring(math.floor(v)) end
    if type(v) ~= "string" then return nil end
    return v:match("(%d%d%d%d+)")
end

function Anim.reset(hum, root, rigType)
    Anim.hum, Anim.root, Anim.rigType = hum, root, rigType
    Anim.animator = hum:FindFirstChildOfClass("Animator")
    Anim.set = ANIM_SETS[rigType] or ANIM_SETS.R6
    Anim.cache = {}
    Anim.base, Anim.baseId, Anim.baseName = nil, nil, nil
    Anim.action, Anim.actionOpts, Anim.actionId = nil, nil, nil
    Anim.jumpUntil = 0
end

local function trackFor(id)
    id = parseId(id)
    if not id or not Anim.animator then return nil end
    local t = Anim.cache[id]
    if t then return t end
    local a = Instance.new("Animation")
    a.AnimationId = "rbxassetid://" .. id
    local ok, track = pcall(function() return Anim.animator:LoadAnimation(a) end)
    if ok and track then
        Anim.cache[id] = track
        return track
    end
    return nil
end

local function pick(name)
    if Anim.overrides[name] then return Anim.overrides[name] end
    local list = Anim.set and Anim.set[name]
    if not list then return nil end
    local total = 0
    for _, e in ipairs(list) do total += e[2] end
    local r = math.random() * total
    for _, e in ipairs(list) do
        r -= e[2]
        if r <= 0 then return e[1] end
    end
    return list[#list][1]
end

local function playBase(name, fade, speed)
    local id = (Anim.baseName == name and Anim.baseId) or pick(name)
    if not id then return end
    if Anim.base and Anim.baseId == id then
        Anim.baseName = name
        if speed then pcall(Anim.base.AdjustSpeed, Anim.base, speed) end
        return
    end
    local track = trackFor(id)
    if not track then return end
    if Anim.base then pcall(Anim.base.Stop, Anim.base, fade or 0.15) end
    pcall(function()
        track.Priority = Enum.AnimationPriority.Core
        track.Looped = LOOPED[name] or false
    end)
    track:Play(fade or 0.15, 1, speed or 1)
    Anim.base, Anim.baseId, Anim.baseName = track, id, name
end

function Anim.setOverride(state, id)
    Anim.overrides[state] = parseId(id)
    if Anim.baseName == state then Anim.baseId = nil end
end

function Anim.stopAction(fade)
    if Anim.action then pcall(Anim.action.Stop, Anim.action, fade or 0.2) end
    Anim.action, Anim.actionOpts, Anim.actionId = nil, nil, nil
end

-- Any animation id, or an emote name from the current set
function Anim.playAction(idOrEmote, opts)
    opts = opts or {}
    local id = parseId(idOrEmote)
    local emote = nil
    if not id and type(idOrEmote) == "string" and Anim.set and Anim.set[idOrEmote:lower()] then
        emote = idOrEmote:lower()
        id = pick(emote)
        if opts.Loop == nil then opts.Loop = EMOTES[emote] end
        if opts.StopOnMove == nil then opts.StopOnMove = true end
    end
    if not id then return false, "no animation id" end

    local track = trackFor(id)
    if not track then return false, "couldn't load " .. id end
    if Anim.action and Anim.action ~= track then pcall(Anim.action.Stop, Anim.action, opts.FadeTime or 0.15) end
    pcall(function()
        track.Priority = Enum.AnimationPriority.Action4
    end)
    track.Looped = opts.Loop and true or false
    track:Play(opts.FadeTime or 0.15, 1, opts.Speed or 1)
    Anim.action, Anim.actionOpts, Anim.actionId = track, opts, id

    -- report whether it actually loaded
    task.spawn(function()
        local t0 = os.clock()
        while track.Length <= 0 and os.clock() - t0 < 4 do task.wait(0.1) end
        if track.Length <= 0 then
            log("animation %s didn't load: invalid id, wrong body type (%s), or this game can't play it", id, Anim.rigType)
            notify("Animation", id .. " didn't load (see F9)")
        end
    end)
    return true, id
end

function Anim.update()
    if not (Config.Animations and Anim.hum and Anim.root and Anim.root.Parent) then return end
    local hum, root = Anim.hum, Anim.root
    local st = hum:GetState()
    local v = root.AssemblyLinearVelocity
    local speed = Vector3.new(v.X, 0, v.Z).Magnitude
    local moving = hum.MoveDirection.Magnitude > 0.05 and speed > 0.5

    if Anim.action then
        if not Anim.action.IsPlaying then
            Anim.action, Anim.actionOpts, Anim.actionId = nil, nil, nil
        elseif Anim.actionOpts and Anim.actionOpts.StopOnMove and moving then
            Anim.stopAction(0.2)
        end
    end

    local S = Enum.HumanoidStateType
    if st == S.Jumping then
        Anim.jumpUntil = os.clock() + 0.3
        playBase("jump", 0.1)
    elseif st == S.Freefall then
        if os.clock() > Anim.jumpUntil then playBase("fall", 0.2) end
    elseif st == S.Climbing then
        playBase("climb", 0.1, v.Y / 12)
    elseif st == S.Seated then
        playBase("sit", 0.5)
    elseif st == S.Swimming then
        if speed > 1 then playBase("swim", 0.2, speed / 16) else playBase("swimidle", 0.2) end
    elseif moving then
        if Anim.rigType == "R6" then
            playBase("walk", 0.1, speed / 14.5)
        elseif speed > 9 then
            playBase("run", 0.15, speed / 16)
        else
            playBase("walk", 0.15, math.max(0.1, speed / 7.5))
        end
    else
        playBase("idle", 0.2)
    end
end

function Anim.stopAll()
    Anim.stopAction(0)
    if Anim.base then pcall(Anim.base.Stop, Anim.base, 0) end
    Anim.base, Anim.baseId, Anim.baseName = nil, nil, nil
end


--==================================================
-- JSON KEYFRAME ANIMATIONS
--==================================================
--
-- Plays the same JSON files as the autorig reanimate (its FILES tab,
-- Anim Spy SAVE): R6 pose tracks on an R6 rig, raw "R15:<part>" joint
-- tracks on an R15 rig. They override the Animator's joints with a
-- short crossfade in and out.
--==================================================

local Files = { current = nil }

local POSE_JOINT = {
    Head        = { Vector3.new(0, 1, 0), 0.5 },
    ["Left Arm"]  = { Vector3.new(-1.5, 1, 0), -1 },
    ["Right Arm"] = { Vector3.new(1.5, 1, 0), -1 },
    ["Left Leg"]  = { Vector3.new(-0.5, -1, 0), -1 },
    ["Right Leg"] = { Vector3.new(0.5, -1, 0), -1 },
}
local ZERO = { rx = 0, ry = 0, rz = 0, ox = 0, oy = 0, oz = 0 }
local AXES = { "rx", "ry", "rz", "ox", "oy", "oz" }

function Files.list()
    local out = {}
    if not (Caps.listfiles and Caps.isfolder) then return out end
    pcall(function()
        if not Caps.isfolder(Config.AnimationFolder) then return end
        for _, f in ipairs(Caps.listfiles(Config.AnimationFolder)) do
            local n = tostring(f):match("([^/\\]+)%.json$")
            if n then table.insert(out, n) end
        end
    end)
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

function Files.load(name)
    if not Caps.readfile then return nil, "executor has no readfile" end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(Caps.readfile(Config.AnimationFolder .. "/" .. name .. ".json"))
    end)
    if not ok or type(data) ~= "table" or type(data.frames) ~= "table" or #data.frames == 0 then
        return nil, "couldn't read " .. name
    end
    table.sort(data.frames, function(a, b) return (a.t or 0) < (b.t or 0) end)
    return {
        name   = name,
        loop   = data.loop and true or false,
        length = tonumber(data.length) or data.frames[#data.frames].t or 1,
        linear = data.linear and true or false,
        frames = data.frames,
    }
end

local function lerpTrack(a, b, k)
    a, b = a or ZERO, b or ZERO
    local o = {}
    for _, ax in ipairs(AXES) do
        local va, vb = tonumber(a[ax]) or 0, tonumber(b[ax]) or 0
        o[ax] = va + (vb - va) * k
    end
    return o
end

local function samplePose(anim, t)
    local f = anim.frames
    if anim.loop and anim.length > 0 then t = t % anim.length end
    if #f == 1 or t <= (tonumber(f[1].t) or 0) then return f[1].pose end
    if t >= (tonumber(f[#f].t) or 0) then return f[#f].pose end
    for i = 1, #f - 1 do
        local a, b = f[i], f[i + 1]
        local at, bt = tonumber(a.t) or 0, tonumber(b.t) or 0
        if t >= at and t < bt then
            local k = (bt - at) > 0 and (t - at) / (bt - at) or 0
            if not anim.linear then k = k * k * (3 - 2 * k) end
            local keys, out = {}, {}
            for n in pairs(a.pose) do keys[n] = true end
            for n in pairs(b.pose) do keys[n] = true end
            for n in pairs(keys) do out[n] = lerpTrack(a.pose[n], b.pose[n], k) end
            return out
        end
    end
    return f[#f].pose
end

local function rad3(q)
    return CFrame.Angles(math.rad(tonumber(q.rx) or 0), math.rad(tonumber(q.ry) or 0), math.rad(tonumber(q.rz) or 0))
end

-- pose -> { [Motor6D] = Transform } for the fake rig
-- R6 limb track -> the R15 joint it bends (the rest stay straight
-- unless the pose has their own "R15:<part>" track)
local R15_DRIVER6 = {
    Head = "Head",
    LeftUpperArm = "Left Arm", RightUpperArm = "Right Arm",
    LeftUpperLeg = "Left Leg", RightUpperLeg = "Right Leg",
}

local function trackCF(q, offsetFirst)
    local o = CFrame.new(tonumber(q.ox) or 0, tonumber(q.oy) or 0, tonumber(q.oz) or 0)
    if offsetFirst then return o * rad3(q) end
    return rad3(q) * o
end

local function poseTransforms(P, motors, rigType)
    local out = {}
    if rigType == "R15" then
        local w = P["R15:_w"]
        local hasRaw = w ~= nil and (tonumber(w.rx) or 0) > 0
        for _, r in ipairs(motors) do
            local name = r.part1.Name
            local q = P["R15:" .. name]
            if q then
                -- raw joint data (R15 imports) or a per-joint edit
                out[r] = trackCF(q, true)
            elseif not hasRaw then
                -- R6 pose on an R15 body: torso drives the root joint,
                -- each R6 limb its shoulder/hip/neck, in the parent's axes
                local g = (name == "LowerTorso") and "Torso" or R15_DRIVER6[name]
                if g then
                    local R0 = jointC0(r).Rotation
                    out[r] = R0:Inverse() * trackCF(P[g] or ZERO, name == "LowerTorso") * R0
                else
                    out[r] = CFrame.identity
                end
            end
        end
        return out
    end

    local tp = P.Torso or ZERO
    local rel = { Torso = CFrame.new(tonumber(tp.ox) or 0, tonumber(tp.oy) or 0, tonumber(tp.oz) or 0) * rad3(tp) }
    for limb, j in pairs(POSE_JOINT) do
        local q = P[limb] or ZERO
        rel[limb] = rel.Torso * CFrame.new(j[1]) * rad3(q)
            * CFrame.new(tonumber(q.ox) or 0, j[2] + (tonumber(q.oy) or 0), tonumber(q.oz) or 0)
    end
    for _, r in ipairs(motors) do
        local p0 = (r.part0.Name == "HumanoidRootPart") and CFrame.identity or rel[r.part0.Name]
        local p1 = rel[r.part1.Name]
        if p0 and p1 then
            out[r] = jointC0(r):Inverse() * p0:Inverse() * p1 * jointC1(r)
        end
    end
    return out
end

function Files.play(name, speed)
    local anim, err = Files.load(name)
    if not anim then return false, err end
    Files.current = { anim = anim, t = 0, speed = speed or 1, weight = 0, fadingOut = false }
    log("playing file %s (%.2fs, %s)", name, anim.length, anim.loop and "loops" or "once")
    return true
end

-- Keyframes written in a script, same format as the JSON files:
--   { loop = true, length = 1.2, linear = false,
--     frames = { { t = 0, pose = { ["Right Arm"] = { rx = -90 }, ... } }, ... } }
function Files.playTable(anim, opts)
    opts = opts or {}
    if type(anim) ~= "table" or type(anim.frames) ~= "table" or #anim.frames == 0 then
        return false, "keyframe table needs a non-empty frames list"
    end
    local frames = {}
    for _, f in ipairs(anim.frames) do
        if type(f) == "table" and type(f.pose) == "table" then
            table.insert(frames, { t = tonumber(f.t) or 0, pose = f.pose })
        end
    end
    if #frames == 0 then return false, "no valid frames" end
    table.sort(frames, function(a, b) return a.t < b.t end)
    local loop = anim.loop
    if opts.Loop ~= nil then loop = opts.Loop end
    Files.current = {
        anim = {
            name   = anim.name or "script",
            loop   = loop and true or false,
            length = tonumber(anim.length) or frames[#frames].t,
            linear = anim.linear and true or false,
            frames = frames,
        },
        t = 0, speed = opts.Speed or 1, weight = 0, fadingOut = false,
    }
    return true
end

function Files.stop()
    if Files.current then Files.current.fadingOut = true end
end

-- Called every PreSimulation BEFORE the drive, after the Animator ran
function Files.step(dt, motors, rigType)
    local cur = Files.current
    if not cur then return end
    local FADE = 0.2
    if cur.fadingOut then
        cur.weight -= dt / FADE
        if cur.weight <= 0 then
            Files.current = nil
            return
        end
    else
        cur.weight = math.min(1, cur.weight + dt / FADE)
    end

    cur.t += dt * cur.speed
    if not cur.anim.loop and cur.t >= cur.anim.length then
        cur.t = cur.anim.length
        cur.fadingOut = true
    end

    local T = poseTransforms(samplePose(cur.anim, cur.t), motors, rigType)
    local w = cur.weight
    for r, t in pairs(T) do
        local j = r.joint
        pcall(function()
            j.Transform = (w >= 1) and t or j.Transform:Lerp(t, w)
        end)
    end
end


--==================================================
-- LIFECYCLE
--==================================================
--
-- Character handling is the Zeon split, not a Player.Character swap:
-- your character model stays the SAME instance (the server never sees
-- a character change, so it never answers with a respawn). Inside it,
-- your real body moves into a sub-model "DinoBody" and the fake rig's
-- parts and Humanoid take its place as direct children, so your
-- controls, camera and Animator all act on the fake rig.
--
-- Gelatek and Krypton set Player.Character to the fake rig instead;
-- that reads as a respawn request on many servers, which is why you
-- died instantly in the first version of this.
--==================================================

local Dino: { [string]: any } = {}   -- the module (returned at the end)
local LastUserConfig = nil
local everStarted   = false   -- Dino.Start was called at least once
local userStopped   = false   -- Dino.Stop / rig:Stop was called by a script
local destroyed     = false
local stopRun                 -- internal stop (forward)

-- Lua signals. BindableEvent:Fire deep-copies tables: it errors on the
-- rig ("tables cannot be cyclic", the rig points at its run and back)
-- and would strip the rig's methods even if it didn't.
local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
    assert(type(fn) == "function", "Connect needs a function")
    local handlers = self._handlers
    local conn = { Connected = true }
    function conn.Disconnect()
        if not conn.Connected then return end
        conn.Connected = false
        for i, h in ipairs(handlers) do
            if h == conn then
                table.remove(handlers, i)
                break
            end
        end
    end
    conn._fn = fn
    table.insert(handlers, conn)
    return conn
end

function Signal:Once(fn)
    local conn
    conn = self:Connect(function(...)
        conn.Disconnect()
        fn(...)
    end)
    return conn
end

function Signal:Wait()
    local thread = coroutine.running()
    self:Once(function(...) task.spawn(thread, ...) end)
    return coroutine.yield()
end

function Signal:Fire(...)
    -- copy first: handlers may disconnect while firing
    local list = table.clone(self._handlers)
    for _, conn in ipairs(list) do
        if conn.Connected then
            local fn = conn._fn
            task.spawn(function(...)
                local ok, err = pcall(fn, ...)
                if not ok then warn("[Dino] event handler error: " .. tostring(err)) end
            end, ...)
        end
    end
end

function Signal:DisconnectAll()
    for _, conn in ipairs(table.clone(self._handlers)) do conn.Disconnect() end
end

local startedEvent = Signal.new()
local stoppedEvent = Signal.new()

local function spawnCFrame()
    local sp = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
    return sp and (sp.CFrame + Vector3.new(0, 4, 0)) or CFrame.new(0, 50, 0)
end

local function addHat(run, acc)
    if not (acc and acc:IsA("Accoutrement")) then return nil end
    local h = acc:FindFirstChild("Handle") or acc:FindFirstChildWhichIsA("BasePart", true)
    if not (h and h:IsA("BasePart")) then return nil end
    for _, hd in ipairs(run.hats) do
        if hd.handle == h then return nil end
    end
    local limb = accessoryLimb(acc, h, run.bodySet, run.bodyModel or run.char)
    if not limb then return nil end
    local hd = { handle = h, limb = limb, rel = limb.CFrame:ToObjectSpace(h.CFrame), name = acc.Name, accessory = acc }
    run.hatSet[h] = true
    -- measured; now cut it loose so it can't drag the body part
    pcall(function()
        for _, j in ipairs(h:GetJoints()) do
            if isJoint(j) then
                local p0, p1 = jointParts(j)
                local other = (p0 == h) and p1 or p0
                if other and run.bodySet[other] then
                    pcall(j.Destroy, j)
                end
            end
        end
    end)
    prepPart(h)
    table.insert(run.hats, hd)
    return hd
end

local function applyConfig(user)
    for k, v in pairs(DEFAULTS) do
        if type(user) == "table" and user[k] ~= nil and (type(user[k]) == type(v) or k == "KeepNeck") then
            Config[k] = user[k]
        else
            Config[k] = v
        end
    end
end


--==================================================
-- RIG OBJECT
--==================================================
--
-- What Dino.Start returns. Everything a reanimate script needs:
--
--   rig.Mode        "R6" | "R15" | "R15ToR6"
--   rig.RigType     "R6" | "R15"   (what animations the fake rig takes)
--   rig.Character   your character model (same instance as always)
--   rig.Humanoid    fake Humanoid (controls act on it)
--   rig.RootPart    fake HumanoidRootPart
--   rig.Animator    fake Animator
--   rig.Parts       { [name] = fake BasePart }
--   rig.Joints      { [name] = Motor6D / AnimationConstraint } (by joint name)
--   rig.JointsByPart{ [partName] = joint that moves that part }
--   rig.RealParts   { [name] = your real BasePart }
--   rig.Accessories { { handle, limb, name, accessory } ... }
--
--   rig:PlayAnimation(idOrEmote, { Loop, Speed, FadeTime, StopOnMove }) -> ok, id
--   rig:StopAnimation(fade)
--   rig:LoadAnimation(id)                -> AnimationTrack (your own control)
--   rig:SetAnimation(state, id)          idle/walk/run/jump/fall/climb/sit/swim/swimidle
--   rig:SetDefaultAnimations(on)
--   rig:PlayKeyframes(tableOrFileName, { Speed, Loop }) -> ok, err
--   rig:StopKeyframes()
--   rig:OnStep(function(dt, rig) end)    -> handle with :Disconnect()
--                                           runs every frame right before the
--                                           body copies the rig: set
--                                           joint.Transform here for
--                                           procedural animation
--   rig:RotateJoint(partName, rotCFrame) rotate a joint in its parent's
--                                           axes on top of the animation
--                                           (use inside OnStep)
--   rig:GetOwnership()                   -> owned, total, losses
--   rig:Stop(opts)                       opts.keepBody: don't kill/respawn
--   rig.Stopped                          event
--==================================================

local RigMethods = {}
RigMethods.__index = RigMethods

function RigMethods:PlayAnimation(idOrEmote, opts)
    return Anim.playAction(idOrEmote, opts)
end

function RigMethods:StopAnimation(fade)
    Anim.stopAction(fade or 0.2)
end

function RigMethods:LoadAnimation(id)
    local track = nil
    local pid = parseId(id)
    if pid and self.Animator then
        local a = Instance.new("Animation")
        a.AnimationId = "rbxassetid://" .. pid
        local ok, t = pcall(function() return self.Animator:LoadAnimation(a) end)
        if ok then track = t end
    end
    return track
end

function RigMethods:SetAnimation(state, id)
    Anim.setOverride(state, id)
end

function RigMethods:SetDefaultAnimations(on)
    Config.Animations = on and true or false
    if not Config.Animations and Anim.base then
        pcall(Anim.base.Stop, Anim.base, 0.2)
        Anim.base, Anim.baseId, Anim.baseName = nil, nil, nil
    end
end

function RigMethods:PlayKeyframes(anim, opts)
    opts = opts or {}
    if type(anim) == "string" then
        return Files.play(anim, opts.Speed)
    end
    return Files.playTable(anim, opts)
end

function RigMethods:StopKeyframes()
    Files.stop()
end

function RigMethods:OnStep(fn)
    local run = self._run
    table.insert(run.stepHooks, fn)
    return {
        Disconnect = function()
            local i = table.find(run.stepHooks, fn)
            if i then table.remove(run.stepHooks, i) end
        end,
    }
end

-- Rotate a joint by `rot`, given in its PARENT part's axes (X right,
-- Y up, -Z forward), on top of whatever the animation set this frame.
-- Use it inside OnStep. Same result on R6 and R15 even though their
-- joint frames differ (R6 joints are turned sideways internally).
function RigMethods:RotateJoint(partName, rot)
    local r = self._run.recByPart[partName]
    if not r then return false end
    local R0 = jointC0(r).Rotation
    r.joint.Transform = (R0:Inverse() * rot.Rotation * R0) * r.joint.Transform
    return true
end

function RigMethods:GetOwnership()
    local s = self._run.ownStats
    return s.owned, s.total, s.losses
end

function RigMethods:Stop(opts)
    Dino.Stop(opts)
end


--==================================================
-- START
--==================================================

-- Zeon / Uhhhhhh permadeath: hand the server the same character again.
-- The server's "died -> respawn" hookup goes with the old assignment, so
-- once it has settled (ReassignSettle) a dead body is NOT respawned.
-- Doing it again on a dead body is how you ask for the respawn back.
local function reassignCharacter()
    local cam = Workspace.CurrentCamera
    local camCF = cam and cam.CFrame
    local ch = Player.Character
    if not ch then return false end
    local ok = pcall(function()
        Player.Character = nil
        Player.Character = ch
    end)
    if cam and camCF then
        local con
        con = cam.Changed:Connect(function(prop)
            if prop ~= "Parent" and prop ~= "CFrame" then return end
            cam.CFrame = camCF
            con:Disconnect()
        end)
        task.delay(1, function() if con.Connected then con:Disconnect() end end)
    end
    return ok and Player.Character == ch
end

local function start()
    if State.running then return nil, "already running" end
    local char = Player.Character or Player.CharacterAdded:Wait()
    local realHum  = char:WaitForChild("Humanoid", 10)
    local realRoot = char:WaitForChild("HumanoidRootPart", 10)
    if not (realHum and realRoot) then
        return nil, "no Humanoid / HumanoidRootPart on your character"
    end
    if realHum.Health <= 0 then
        return nil, "you're dead; start again after you respawn"
    end
    if char:FindFirstChild("DinoBody") then
        return nil, "this character was already reanimated; respawn first"
    end
    if #orderedMotors(char, realRoot) == 0 then
        return nil, "this body's joints are already broken; it starts again after you respawn"
    end

    local run: { [string]: any } = {
        running = true, char = char, realHum = realHum, realRoot = realRoot,
        hats = {}, hatSet = {}, map = {}, rigid = {}, targets = {}, driven = {},
        stepHooks = {}, ownStats = { owned = 0, total = 0, losses = 0 },
    }
    State = run
    local function alive() return run.running and char.Parent ~= nil and State == run end
    local function fail(msg)
        run.running = false
        return nil, msg
    end

    ----------------------------------------------------------------
    -- 0. permadeath first: everything below counts toward its wait
    ----------------------------------------------------------------
    local method = Config.PermanentDeath and tostring(Config.PermadeathMethod or "Auto") or "Off"
    local permaSignal, permaReassign = false, false
    local permaAt = os.clock()
    if method == "Auto" or method == "Signal" then
        if Caps.replicatesignal then
            local ok, perr = pcall(function() Caps.replicatesignal(Player.ConnectDiedSignalBackend) end)
            if ok then
                permaSignal = true
            else
                log("replicatesignal(ConnectDiedSignalBackend) failed (%s)", tostring(perr))
            end
        else
            log("your executor has no replicatesignal")
        end
    end
    if not permaSignal and (method == "Auto" or method == "Reassign") then
        permaReassign = reassignCharacter()
        if not permaReassign then log("character reassign failed") end
    end
    if Player.Character ~= char then return fail("character changed while starting") end
    log("permadeath: %s", permaSignal and "replicatesignal"
        or permaReassign and "character reassign"
        or (method == "Command" and "-pd command only") or "none")
    run.permaSignal, run.permaReassign = permaSignal, permaReassign

    ----------------------------------------------------------------
    -- 1. chat: start line, avatar loaded, game commands
    ----------------------------------------------------------------
    if Config.StartMessage ~= "" then
        chat(Config.StartMessage)
        task.wait(Config.StartWait)
        if not alive() then return fail("character changed while starting") end
    end

    if not Player:HasAppearanceLoaded() then
        local loaded = false
        local c = Player.CharacterAppearanceLoaded:Connect(function() loaded = true end)
        local t0 = os.clock()
        while not loaded and not Player:HasAppearanceLoaded() and os.clock() - t0 < 10 do
            task.wait(0.2)
        end
        c:Disconnect()
        if not alive() then return fail("character changed while starting") end
    end

    for _, cmd in ipairs(Config.ChatCommands) do
        chat(cmd)
        task.wait(Config.CommandGap)
        if not alive() then return fail("character changed while starting") end
    end
    task.wait(Config.SettleWait)
    if not alive() then return fail("character changed while starting") end

    -- Never break before the server has taken the permadeath:
    -- signal  -> the respawn timer (Krypton's order)
    -- reassign -> ReassignSettle (break early and Health = 0 reads as a
    --             real death: you get respawned, worst on busy servers)
    local need = permaSignal and (Players.RespawnTime + 0.15)
        or permaReassign and Config.ReassignSettle or 0
    local left = need - (os.clock() - permaAt)
    if left > 0 then
        log("permadeath: waiting %.1fs more for the server", left)
        task.wait(left)
        if not alive() then return fail("character changed while starting") end
    end

    ----------------------------------------------------------------
    -- 2. body type + body parts
    ----------------------------------------------------------------
    local isR15 = realHum.RigType == Enum.HumanoidRigType.R15 or char:FindFirstChild("UpperTorso") ~= nil
    local mode = isR15 and (Config.RigMode == "R15ToR6" and "R15ToR6" or "R15") or "R6"
    run.mode = mode
    run.rigType = (mode == "R15") and "R15" or "R6"
    log("body type %s · rig %s", isR15 and "R15" or "R6", mode)

    local body, bodySet = {}, {}
    for _, n in ipairs(isR15 and R15_PARTS or R6_PARTS) do
        local p = char:FindFirstChild(n)
        if p and p:IsA("BasePart") then
            body[n] = p
            bodySet[p] = true
        end
    end
    bodySet[realRoot] = true
    run.body, run.bodySet = body, bodySet

    for _, acc in ipairs(char:GetChildren()) do addHat(run, acc) end
    local realRest = restPose(char, realRoot)

    ----------------------------------------------------------------
    -- 3. fake rig (built unparented, moved in at the split)
    ----------------------------------------------------------------
    local fake = (mode == "R15ToR6") and buildR6Rig(realHum, realRoot.CFrame) or cloneRig(char, realHum)
    local fakeHum  = fake:FindFirstChildOfClass("Humanoid")
    local fakeRoot = fake:FindFirstChild("HumanoidRootPart")
    if not (fakeHum and fakeRoot) then
        pcall(fake.Destroy, fake)
        return fail("couldn't build the fake rig")
    end
    pcall(function() fake:PivotTo(realRoot.CFrame) end)
    run.fakeHum, run.fakeRoot = fakeHum, fakeRoot
    run.motors = orderedMotors(fake, fakeRoot)
    run.fakeParts, run.parts = {}, {}
    for _, d in ipairs(fake:GetDescendants()) do
        if d:IsA("BasePart") then
            table.insert(run.fakeParts, d)
            run.parts[d.Name] = d
        end
    end

    ----------------------------------------------------------------
    -- 4. real -> fake mapping
    ----------------------------------------------------------------
    if mode == "R15ToR6" then
        local fakeRest = restPose(fake, fakeRoot)
        for n, p in pairs(body) do
            local fp = fake:FindFirstChild(R15_TO_R6[n])
            if fp and realRest[p] and fakeRest[fp] then
                run.map[p] = { fake = fp, offset = fakeRest[fp]:Inverse() * realRest[p] }
            end
        end
    else
        for n, p in pairs(body) do
            local fp = fake:FindFirstChild(n)
            if fp then run.map[p] = { fake = fp, offset = CFrame.identity } end
        end
    end
    local mapped = 0
    for _ in pairs(run.map) do mapped += 1 end
    log("%d body parts mapped, %d accessories", mapped, #run.hats)

    ----------------------------------------------------------------
    -- 5. death / neck
    ----------------------------------------------------------------
    local permaCmd = Config.PermanentDeath and table.find(Config.ChatCommands, "-pd") ~= nil
    local perma = permaSignal or permaReassign or permaCmd
    local keepNeck = (Config.KeepNeck == true) or (Config.KeepNeck == "Auto" and not perma)
    run.keepNeck = keepNeck

    local head = body.Head
    if keepNeck and head then
        local parent = body.Torso or body.UpperTorso
        if parent and realRest[head] and realRest[parent] then
            run.rigid[head] = { parent = parent, rel = realRest[parent]:Inverse() * realRest[head] }
        end
        log("no permadeath: keeping your neck so you stay alive (head turns with the torso)")
    end
    if not permaSignal and not permaCmd then
        log("no replicatesignal and no -pd: the server keeps your joints, other players may see your body move as one piece")
    end

    ----------------------------------------------------------------
    -- 6. silence the real character
    ----------------------------------------------------------------
    pcall(function()
        local animate = char:FindFirstChild("Animate")
        if animate then animate.Disabled = true end
    end)
    pcall(function()
        for _, t in ipairs(realHum:GetPlayingAnimationTracks()) do t:Stop(0) end
    end)
    pcall(function()
        local a = realHum:FindFirstChildOfClass("Animator")
        if a then a:Destroy() end
    end)
    pcall(realHum.ChangeState, realHum, Enum.HumanoidStateType.Physics)
    pcall(function() realHum.BreakJointsOnDeath = false end)

    local function antiRagdoll(v)
        if v:IsA("BallSocketConstraint") or v:IsA("HingeConstraint") then
            local p0 = v.Attachment0 and v.Attachment0.Parent
            local p1 = v.Attachment1 and v.Attachment1.Parent
            if (p0 and bodySet[p0]) or (p1 and bodySet[p1]) then
                task.defer(function() pcall(v.Destroy, v) end)
            end
        end
    end
    for _, v in ipairs(char:GetDescendants()) do antiRagdoll(v) end
    connect(char.DescendantAdded, antiRagdoll)

    for p in pairs(bodySet) do prepPart(p) end

    -- The real body must never be "floor". A dead R15 humanoid turns its
    -- limbs collidable again; the fake humanoid's floor check then hits
    -- the real torso right under its own root, stands up on it, the real
    -- body follows the fake up (with the netless lift on top) and you
    -- climb forever. Keep collision, queries and touches off, always.
    local function ghost(p)
        if p.CanCollide then p.CanCollide = false end
        if p.CanQuery then pcall(function() p.CanQuery = false end) end
        if p.CanTouch then pcall(function() p.CanTouch = false end) end
    end
    run.ghost = ghost
    local function watchGhost(p)
        connect(p:GetPropertyChangedSignal("CanCollide"), function()
            if run.running and p.CanCollide then p.CanCollide = false end
        end)
    end
    for p in pairs(bodySet) do
        ghost(p)
        watchGhost(p)
    end
    for _, hd in ipairs(run.hats) do
        ghost(hd.handle)
        watchGhost(hd.handle)
    end
    run.watchGhost = watchGhost

    ----------------------------------------------------------------
    -- 7. split: real body into DinoBody, fake rig takes its place
    ----------------------------------------------------------------
    local cam = Workspace.CurrentCamera
    local camCF = cam.CFrame

    local bodyModel = Instance.new("Model")
    bodyModel.Name = "DinoBody"
    bodyModel.Parent = char                       -- parent first: nothing leaves the world
    for _, v in ipairs(char:GetChildren()) do
        if v ~= bodyModel then v.Parent = bodyModel end
    end
    for _, v in ipairs(fake:GetChildren()) do v.Parent = char end
    pcall(fake.Destroy, fake)
    pcall(function() char.PrimaryPart = fakeRoot end)
    run.bodyModel = bodyModel

    cam.CameraSubject = fakeHum
    cam.CFrame = camCF

    ----------------------------------------------------------------
    -- 8. break
    ----------------------------------------------------------------
    local cut = startJointSweep(run, bodySet, keepNeck, head)
    if permaSignal then
        local ok = pcall(function() Caps.replicatesignal(realHum.ServerBreakJoints) end)
        if not ok then log("replicatesignal(ServerBreakJoints) failed: joints only break on your screen") end
    end
    if perma and not keepNeck then
        -- the real body is a corpse from here on; keep it that way
        pcall(function() realHum.Health = 0 end)
        task.spawn(function()
            while run.running and realHum.Parent do
                if realHum.Health > 0 then pcall(function() realHum.Health = 0 end) end
                task.wait(0.5)
            end
        end)
    end
    log("cut %d joints · permadeath: %s · neck: %s", cut,
        perma and (permaSignal and "replicatesignal" or permaReassign and "reassign" or "-pd") or "off",
        keepNeck and "kept" or "free")

    Anim.reset(fakeHum, fakeRoot, run.rigType)
    physicsTweaks()

    ----------------------------------------------------------------
    -- 9. per-frame
    ----------------------------------------------------------------
    connect(RunService.PreSimulation, function(dt)
        if not run.running then return end
        maxSimulationRadius()
        if Config.VoidGuard then
            pcall(function() Workspace.FallenPartsDestroyHeight = 0 / 0 end)
        end
        for _, p in ipairs(run.fakeParts) do
            if p.CanCollide then p.CanCollide = false end
        end
        for p in pairs(bodySet) do ghost(p) end
        for _, hd in ipairs(run.hats) do ghost(hd.handle) end

        -- keyframes, then the script's own hooks, override the Animator
        Files.step(dt, run.motors, run.rigType)
        for _, fn in ipairs(run.stepHooks) do
            local ok, err = pcall(fn, dt, run.rig)
            if not ok then log("OnStep error: %s", tostring(err)) end
        end

        -- forward kinematics of the fake rig, from this frame's joints
        local rootCF = fakeRoot.CFrame
        Drive.ctx.rootCF     = rootCF
        Drive.ctx.rootVel    = fakeRoot.AssemblyLinearVelocity
        Drive.ctx.rootAngVel = fakeRoot.AssemblyAngularVelocity

        local cfs = { [fakeRoot] = rootCF }
        for _, r in ipairs(run.motors) do
            local p0 = cfs[r.part0]
            if p0 and r.joint.Parent then
                cfs[r.part1] = p0 * jointC0(r) * r.joint.Transform * jointC1(r):Inverse()
            end
        end

        local targets = run.targets
        table.clear(targets)
        for real, info in pairs(run.map) do
            local f = cfs[info.fake]
            if f then targets[real] = f * info.offset end
        end
        for real, info in pairs(run.rigid) do
            local pt = targets[info.parent]
            if pt then targets[real] = pt * info.rel end
        end

        table.clear(run.driven)
        for real, cf in pairs(targets) do
            if not run.rigid[real] then
                driveNetless(real, cf, dt)
                table.insert(run.driven, real)
            end
        end
        driveNetless(realRoot, rootCF, dt)
        table.insert(run.driven, realRoot)

        for _, hd in ipairs(run.hats) do
            local base = targets[hd.limb] or (hd.limb == realRoot and rootCF)
            if base and hd.handle.Parent then
                driveNetless(hd.handle, base * hd.rel, dt)
                table.insert(run.driven, hd.handle)
            end
        end
    end)

    connect(RunService.PostSimulation, function()
        if not run.running then return end
        for _, p in ipairs(run.driven) do
            ghost(p)
            reassert(p)
        end
    end)

    local lastSafeAt = 0
    connect(RunService.Heartbeat, function()
        if not run.running then return end
        Anim.update()

        if cam.CameraSubject ~= fakeHum then cam.CameraSubject = fakeHum end

        local pos = fakeRoot.Position
        if os.clock() - lastSafeAt > 0.25 and fakeHum.FloorMaterial ~= Enum.Material.Air
            and pos.Y > VOID_Y + Config.VoidMargin + 10 then
            lastSafeAt = os.clock()
            run.lastSafe = fakeRoot.CFrame
        end
        if pos.Y < VOID_Y + Config.VoidMargin then
            if Config.VoidRecovery == "Stop" then
                task.defer(stopRun)
                return
            end
            local to = (Config.VoidRecovery == "Spawn" or not run.lastSafe) and spawnCFrame() or run.lastSafe
            fakeRoot.CFrame = to + Vector3.new(0, 3, 0)
            fakeRoot.AssemblyLinearVelocity = Vector3.zero
            fakeRoot.AssemblyAngularVelocity = Vector3.zero
            log("fell into the void, brought back")
        end
    end)

    -- the control script may still hold the old Humanoid for jumping
    connect(UserInputService.JumpRequest, function()
        if run.running and fakeHum.Parent then fakeHum.Jump = true end
    end)

    ----------------------------------------------------------------
    -- 10. ownership monitor
    ----------------------------------------------------------------
    task.spawn(function()
        local last, lostAt, boxes = {}, {}, {}
        while run.running do
            local owned, total = 0, 0
            for _, p in ipairs(run.driven) do
                if p.Parent then
                    total += 1
                    local o = ownsPart(p)
                    if o then owned += 1 end
                    if last[p] == true and not o then
                        run.ownStats.losses += 1
                        lostAt[p] = os.clock()
                        if Config.OwnershipLog then log("lost ownership of %s", p.Name) end
                    elseif last[p] == false and o and Config.OwnershipLog and lostAt[p] then
                        log("got %s back after %.2fs", p.Name, os.clock() - lostAt[p])
                    end
                    last[p] = o

                    local box = boxes[p]
                    if Config.OwnershipBoxes and not o then
                        if not box then
                            box = Instance.new("SelectionBox")
                            box.Name = "DinoOwnership"
                            box.LineThickness = 0.03
                            box.Color3 = Color3.fromRGB(220, 60, 70)
                            box.Adornee = p
                            box.Parent = p
                            boxes[p] = box
                        end
                        box.Visible = true
                    elseif box then
                        box.Visible = false
                    end
                end
            end
            run.ownStats.owned, run.ownStats.total = owned, total
            task.wait(0.1)
        end
        for _, b in pairs(boxes) do pcall(b.Destroy, b) end
    end)

    ----------------------------------------------------------------
    -- 11. events
    ----------------------------------------------------------------
    -- accessories the server adds later land on the character itself
    connect(char.ChildAdded, function(v)
        if not v:IsA("Accoutrement") then return end
        task.spawn(function()
            local h = v:WaitForChild("Handle", 5)
            if not h then return end
            local t0 = os.clock()
            local hd = nil
            repeat
                task.wait(0.1)
                hd = addHat(run, v)
            until hd or os.clock() - t0 > 3 or not run.running
            if hd then
                run.watchGhost(hd.handle)
                log("new accessory follows %s: %s", hd.limb.Name, v.Name)
            end
        end)
    end)

    connect(fakeHum.Died, function() task.defer(stopRun) end)

    local resetEvent = Instance.new("BindableEvent")
    connect(resetEvent.Event, function() task.defer(stopRun) end)
    pcall(function() StarterGui:SetCore("ResetButtonCallback", resetEvent) end)
    run.resetEvent = resetEvent

    if Config.EmoteChat then
        connect(Player.Chatted, function(msg)
            msg = tostring(msg)
            local arg = msg:match("^/e%s+(.+)$") or msg:match("^/emote%s+(.+)$")
            if not arg then return end
            arg = arg:lower():gsub("%s+$", "")
            if arg == "dance" then
                Anim.playAction("dance" .. math.random(1, 3))
            elseif EMOTES[arg] ~= nil then
                Anim.playAction(arg)
            elseif parseId(arg) then
                Anim.playAction(arg, { Loop = true, StopOnMove = true })
            end
        end)
    end

    ----------------------------------------------------------------
    -- 12. rig object
    ----------------------------------------------------------------
    local joints, jointsByPart = {}, {}
    run.recByPart = {}
    for _, r in ipairs(run.motors) do
        joints[r.joint.Name] = r.joint
        jointsByPart[r.part1.Name] = r.joint
        run.recByPart[r.part1.Name] = r
    end
    local realParts = {}
    for n, p in pairs(body) do realParts[n] = p end
    realParts.HumanoidRootPart = realRoot

    local rig = setmetatable({
        _run         = run,
        Mode         = mode,
        RigType      = run.rigType,
        Character    = char,
        Humanoid     = fakeHum,
        RootPart     = fakeRoot,
        Animator     = fakeHum:FindFirstChildOfClass("Animator"),
        Parts        = run.parts,
        Joints       = joints,
        JointsByPart = jointsByPart,
        RealParts    = realParts,
        RealHumanoid = realHum,
        Accessories  = run.hats,
        Stopped      = stoppedEvent,
    }, RigMethods)
    run.rig = rig
    Dino.Current = rig

    log("ready")
    startedEvent:Fire(rig)
    return rig
end


--==================================================
-- STOP
--==================================================

stopRun = function(opts)
    opts = opts or {}
    local run = State
    if not run.running then return end
    run.running = false
    disconnectAll()

    Anim.stopAll()
    Files.current = nil
    pcall(function() Workspace.FallenPartsDestroyHeight = VOID_Y end)
    for part, vf in pairs(Drive.antiGrav) do
        pcall(function()
            if vf.Attachment0 then vf.Attachment0:Destroy() end
            vf:Destroy()
        end)
        Drive.antiGrav[part] = nil
    end
    pcall(function() StarterGui:SetCore("ResetButtonCallback", true) end)
    if run.resetEvent then pcall(run.resetEvent.Destroy, run.resetEvent) end

    local char = run.char
    if char and char.Parent and run.bodyModel and not opts.respawned then
        -- take the fake rig out, put the real body back
        for _, v in ipairs(char:GetChildren()) do
            if v ~= run.bodyModel then pcall(v.Destroy, v) end
        end
        for _, v in ipairs(run.bodyModel:GetChildren()) do v.Parent = char end
        pcall(run.bodyModel.Destroy, run.bodyModel)
        pcall(function() char.PrimaryPart = run.realRoot end)
        pcall(function() Workspace.CurrentCamera.CameraSubject = run.realHum end)

        if not opts.keepBody then
            -- broken joints can't be put back: respawn. With signal
            -- permadeath the server needs the died signal again.
            if run.permaSignal then
                pcall(function() Caps.replicatesignal(Player.ConnectDiedSignalBackend) end)
            end
            pcall(function() run.realHum.Health = 0 end)
            pcall(run.realHum.ChangeState, run.realHum, Enum.HumanoidStateType.Dead)
            if run.permaReassign then
                -- reassigning a dead body asks the server for the respawn
                task.delay(0.1, reassignCharacter)
            end
        end
    end

    if Dino.Current and Dino.Current._run == run then Dino.Current = nil end
    log("stopped")
    stoppedEvent:Fire()
end


--==================================================
-- MODULE
--==================================================

Dino.Version       = "1.0"
Dino.DefaultConfig = DEFAULTS
Dino.Config        = Config
Dino.Started       = startedEvent    -- fires with the rig, also after auto restarts
Dino.Stopped       = stoppedEvent
Dino.AnimationSets = ANIM_SETS
Dino.MovementStates = STATE_NAMES   -- valid states for rig:SetAnimation
Dino.Current       = nil

-- Dino.Start(config) -> rig | nil, err   (yields until running)
-- config: a table of overrides, or nil for getgenv().DinoReanimateConfig
-- (or the last config used).
local starting, lastStartErr = false, nil

function Dino.Start(config)
    if destroyed then return nil, "this engine copy was replaced" end
    if starting or State.running then
        -- already running (or starting, e.g. the auto start): hand back that rig
        local t0 = os.clock()
        while (starting or State.running) and not Dino.Current and os.clock() - t0 < 60 do
            task.wait(0.1)
        end
        if State.running and Dino.Current then return Dino.Current, nil end
        return nil, lastStartErr or "start didn't finish"
    end
    if config ~= nil then
        LastUserConfig = config
    elseif LastUserConfig == nil and type(Global.DinoReanimateConfig) == "table" then
        LastUserConfig = Global.DinoReanimateConfig
    end
    applyConfig(LastUserConfig)
    everStarted, userStopped = true, false
    starting, lastStartErr = true, nil
    local ok, rig, err = pcall(start)
    starting = false
    if not ok then
        err, rig = tostring(rig), nil
        -- a crash halfway must not leave a dead body with no driver:
        -- full stop (restore + respawn), which also frees the reset button
        if State.running then
            local sok, serr = pcall(stopRun, {})
            if not sok then
                State.running = false
                log("cleanup after the failed start errored: %s", tostring(serr))
            end
        end
    end
    if not rig then
        lastStartErr = err
        log("start failed: %s", tostring(err))
    end
    return rig, err
end

-- Ends the reanimate (respawns you unless opts.keepBody) and stops the
-- auto restart until Dino.Start is called again.
function Dino.Stop(opts)
    userStopped = true
    stopRun(opts)
end

function Dino.IsRunning()
    return State.running == true
end

-- Respawns: tidy up, then go again with the same config
local respawnConn = Player.CharacterAdded:Connect(function(c)
    if destroyed then return end
    -- the permadeath reassign hands back the SAME model: not a respawn
    if c == State.char then return end
    if State.running and c ~= State.char then
        stopRun({ keepBody = true, respawned = true })
    end
    if everStarted and not userStopped and Config.AutoRestart and not State.running then
        c:WaitForChild("HumanoidRootPart", 10)
        task.wait(0.5)
        if not destroyed and not userStopped and not State.running then
            Dino.Start()
        end
    end
end)

-- Retire this copy for good (a newer copy calls this on load)
function Dino.Destroy()
    destroyed, userStopped = true, true
    pcall(function() respawnConn:Disconnect() end)
    stopRun()
    startedEvent:DisconnectAll()
    stoppedEvent:DisconnectAll()
end

Global.DinoReanimate = Dino

-- Gelatek style: loading the file starts the reanimate
do
    local user = Global.DinoReanimateConfig
    if not (type(user) == "table" and user.AutoStart == false) then
        task.spawn(Dino.Start)
    end
end

return Dino
