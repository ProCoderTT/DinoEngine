# 🦖 DinoEngine

> A modern, lightweight Roblox reanimation engine focused on limb reanimation.

**DinoEngine** is a Roblox reanimation engine inspired by projects such as **Gelatek** and **Krypton**, created by **DinoKid**.

The goal is to provide a more modern and configurable reanimation system while keeping the engine simple to use.

---

## ✨ Features

- 🦴 **Limb Reanimation**
  - Focused on limb-based reanimation.
  - Compatibility depends on the game.

- ⚙️ **Configurable**
  - Customize rig handling, animations, death behavior, chat commands, physics, and more.

- 🤖 **Automatic Startup**
  - Automatically initialize the engine when loaded.
  - Can also be configured to start manually.

- 🎭 **Animation Support**
  - Supports Roblox animations.
  - Optional emote chat integration.

- 💀 **Death Handling**
  - Permanent death support.
  - Automatic restart.
  - Configurable neck handling.

- 🌌 **Physics Features**
  - Netless lifting.
  - Anti-gravity.
  - Void protection and recovery.
  - Physics tweaks.

- 🛠️ **Debugging**
  - Ownership logging.
  - Optional ownership visualization.

---

## 📦 Installation

Load the engine directly from GitHub:

```lua
loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/ProCoderTT/DinoEngine/refs/heads/main/Engine.lua"
))()
```

Or use the engine with a custom configuration:

```lua
local Global = (getgenv and getgenv()) or shared

Global.DinoReanimateConfig = {
    -- [[ Start ]] --
    ["AutoStart"] = true,

    -- [[ Rig ]] --
    ["RigMode"] = "Auto",
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
    ["VoidRecovery"] = "LastSafe",

    -- [[ Debug ]] --
    ["OwnershipBoxes"] = false,
    ["OwnershipLog"] = true,
}

loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/ProCoderTT/DinoEngine/refs/heads/main/Engine.lua"
))()
```

---

## ⚙️ Configuration

### Start

| Option | Type | Description |
|---|---|---|
| `AutoStart` | `boolean` | Automatically starts DinoEngine after loading. |

Set `AutoStart` to `false` if you want to initialize the engine without immediately starting the reanimation.

---

### Rig

| Option | Values | Description |
|---|---|---|
| `RigMode` | `Auto`, `R15ToR6` | Controls how the player's rig is handled. |
| `Animations` | `boolean` | Enables animation support. |
| `EmoteChat` | `boolean` | Enables emote-related chat functionality. |

---

### Death

| Option | Type | Description |
|---|---|---|
| `PermanentDeath` | `boolean` | Enables permanent-death behavior. |
| `KeepNeck` | `Auto` | Controls neck handling. |
| `AutoRestart` | `boolean` | Automatically restarts the engine when necessary. |

---

### Chat

| Option | Type | Description |
|---|---|---|
| `StartMessage` | `string` | Message sent when the engine starts. |
| `ChatCommands` | `table` | Commands recognized by DinoEngine. |

Default commands:

```text
-net
-pd
```

---

### Reanimation

| Option | Type | Description |
|---|---|---|
| `NetlessLift` | `boolean` | Enables netless lifting behavior. |
| `AntiGravity` | `boolean` | Enables anti-gravity behavior. |
| `VoidGuard` | `boolean` | Helps protect against falling into the void. |
| `PhysicsTweaks` | `boolean` | Enables additional physics adjustments. |

---

### Safety

`VoidRecovery` controls what happens when the character enters a dangerous void state.

Available modes:

```text
LastSafe
Spawn
Stop
```

Example:

```lua
["VoidRecovery"] = "LastSafe"
```

---

### Debug

| Option | Type | Description |
|---|---|---|
| `OwnershipBoxes` | `boolean` | Displays ownership visualization. |
| `OwnershipLog` | `boolean` | Logs ownership information for debugging. |

---

## 🧪 Example

A minimal DinoEngine setup:

```lua
local Global = (getgenv and getgenv()) or shared

Global.DinoReanimateConfig = {
    ["AutoStart"] = true,
    ["RigMode"] = "Auto",
    ["Animations"] = true,
    ["PermanentDeath"] = true,
    ["AutoRestart"] = true,
}

loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/ProCoderTT/DinoEngine/refs/heads/main/Engine.lua"
))()
```

---

## ⚠️ Compatibility

DinoEngine currently focuses on **limb reanimation**, meaning it is **not guaranteed to work with every Roblox game**.

Game-specific character systems, custom rigs, networking behavior, and anti-exploit systems may affect compatibility.

<div align="center">

**🦖 DinoEngine**

*Modern reanimation, powered by Dino.*

</div>
