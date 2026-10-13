# DinoEngine
Reanimate Engine like gelatek and krypton, made by DinoKid or badbadbadfr on roblox 
basic reanimate engine like gelatek but more modern, only limb reanimate meaning supported only in some games
basic reanimate script with use of this engine for example is this 
-- local Global = (getgenv and getgenv()) or shared
Global.DinoReanimateConfig = {
    -- [[ Start ]] --
    ["AutoStart"] = true,              -- false = only load it, start it yourself with Dino.Start()

    -- [[ Rig ]] --
    ["RigMode"] = "Auto",              -- "Auto" | "R15ToR6"
    ["Animations"] = true,
    ["EmoteChat"] = true,

    -- [[ Death ]] --
    ["PermanentDeath"] = true,
    ["KeepNeck"] = "Auto",
    ["AutoRestart"] = true,

    -- [[ Chat ]] --
    ["StartMessage"] = "mi giletik",
    ["ChatCommands"] = { "-net", "-pd" },

    -- [[ Reanimation ]] --
    ["NetlessLift"] = true,
    ["AntiGravity"] = true,
    ["VoidGuard"] = true,
    ["PhysicsTweaks"] = true,

    -- [[ Safety ]] --
    ["VoidRecovery"] = "LastSafe",     -- "LastSafe" | "Spawn" | "Stop"

    -- [[ Debug ]] --
    ["OwnershipBoxes"] = false,
    ["OwnershipLog"] = true,
}
loadstring(game:HttpGet("https://raw.githubusercontent.com/ProCoderTT/DinoEngine/refs/heads/main/Engine.lua"))() --
