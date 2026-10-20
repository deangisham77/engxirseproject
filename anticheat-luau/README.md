# Sentinel Anti-Exploit System
Advanced multi-layered anti-exploit protection system for Roblox games. Provides comprehensive security against various types of exploits and cheating methods.

## Features
- **Script Injection Detection** - Monitors and blocks unauthorized script injections
- **Remote Exploit Protection** - Secures RemoteEvents and RemoteFunctions with rate limiting
- **Player Behavior Analysis** - Detects speed hacks, fly hacks, and teleportation
- **Memory Protection** - Monitors memory usage for suspicious spikes
- **Environment Security** - Protects global environment from tampering
- **Real-time Monitoring** - Continuous scanning and detection
- **Comprehensive Logging** - Detailed logs for all security events

## Installation

### Using Roblox Studio
1. Download the entire `SentinelAntiExploit` folder
2. In Roblox Studio, insert the folder into `ServerScriptService`
3. Rename the folder to `SentinelAntiExploit`

### Manual Setup
1. Create a new ModuleScript in `ServerScriptService` named `SentinelAntiExploit`
2. Copy the contents from `MainModule.lua` into this ModuleScript
3. Create the folder structure as shown below



## Quick Start Implementation
```lua
-- In a ServerScript in ServerScriptService
local Sentinel = require(game.ServerScriptService.SentinelAntiExploit.MainModule)

-- Enable debug mode for development
Sentinel:SetDebugMode(true)

print("Sentinel Anti-Exploit initialized successfully")
```

### Advanced Implementation
```lua
-- In a ServerScript
local Sentinel = require(game.ServerScriptService.SentinelAntiExploit.MainModule)

-- Custom event handling
game.Players.PlayerAdded:Connect(function(player)
    print(player.Name .. " joined - Sentinel is monitoring")
    
    -- Get player security data
    local playerData = Sentinel:GetPlayerData(player)
    if playerData then
        print("Join time: " .. playerData.JoinTime)
    end
end)

-- Check system status
game:GetService("RunService").Heartbeat:Connect(function()
    local detections = Sentinel:GetDetectionCount()
    if detections > 0 then
        print("Active detections: " .. detections)
    end
end)
```

## Configuration

Edit `Core/Config.lua` to customize detection thresholds:

```lua
local Config = {}

-- Detection thresholds
Config.DetectionThreshold = 5
Config.MaxRemoteCallsPerSecond = 30
Config.MaxMemorySpike = 100
Config.MaxPlayerSpeed = 100
Config.MaxTeleportDistance = 50
Config.FlyDetectionTime = 2
Config.ScanInterval = 10

-- Suspicious patterns
Config.SuspiciousNames = {
    "exploit", "inject", "cheat", "hack", "dex", 
    "saveinstance", "bypass", "crack", "scriptware"
}

return Config
```

## API Reference

### Main Methods

| Method | Parameters | Description |
|--------|------------|-------------|
| `Initialize()` | None | Initializes the anti-exploit system |
| `SetDebugMode(enabled)` | `boolean` | Enables/disables debug logging |
| `GetDetectionCount()` | None | Returns number of active detections |
| `GetPlayerData(player)` | `Player` | Returns security data for player |
| `Shutdown()` | None | Safely shuts down the system |

### Detection Types

- `SCRIPT_INJECTION` - Unauthorized script injection attempts
- `ILLEGAL_INSTANCE` - Suspicious instance creation
- `REMOTE_EXPLOIT` - Remote event/function exploitation
- `SPEED_HACK` - Player movement speed violations
- `FLY_HACK` - Unauthorized flight detection
- `TELEPORT_HACK` - Instant teleportation detection
- `MEMORY_CORRUPT` - Memory usage anomalies


### Injection Detection
Monitors for:
- Unauthorized scripts with suspicious names
- Environment tampering attempts
- Suspicious module requirements

### Remote Exploit Protection
- Rate limits remote calls (30/second default)
- Validates argument types
- Checks call stack for suspicious patterns

### Player Monitoring
- **Speed Hack**: Detects movement >100 studs/second
- **Fly Hack**: Detects sustained flight >2 seconds
- **Teleport Hack**: Detects instant movement >50 studs

## Customization / Adding Custom Detectors
```lua
-- In a new module file
local CustomDetector = {}

function CustomDetector:Initialize()
    -- Add custom detection logic here
    game.DescendantAdded:Connect(function(descendant)
        -- Custom detection conditions
        if descendant:IsA("Part") and descendant.Name == "SuspiciousPart" then
            Logger:LogDetection("CUSTOM_DETECTION", {
                Instance = descendant:GetFullName()
            })
        end
    end)
end

return CustomDetector
```

### Modifying Detection Responses
```lua
-- In MainModule.lua, modify _TakeAction function
function Sentinel:_TakeAction(detectionType, data)
    if data.player then
        -- Custom actions based on detection type
        if detectionType == "SPEED_HACK" then
            data.player:Kick("Speed hacking detected")
        elseif detectionType == "SCRIPT_INJECTION" then
            data.player:Kick("Script injection attempt detected")
        end
    end
end
```


## Troubleshooting / Common Issues

1. **False Positives**
   - Adjust thresholds in `Config.lua`
   - Review detection logs for patterns

2. **Performance Impact**
   - Increase scan intervals
   - Disable unnecessary modules

3. **Detection Not Working**
   - Verify module placement in `ServerScriptService`
   - Check debug mode for logs

### Debug Mode
Enable debug mode to see detailed logs:
```lua
Sentinel:SetDebugMode(true)
```



**Note**: This system is designed to work alongside Roblox's built-in security features, not replace them. Regular security updates and monitoring are recommended for optimal protection.
```

## Step-by-Step Installation Guide

### Step 1: Download the Project
```bash
git clone https://github.com/REBL0X/anticheat-luau.git
```

### Setup in Roblox Studio
1. Open your Roblox game in Studio
2. In the Explorer window, locate `ServerScriptService`
3. Right-click `ServerScriptService` → `Insert From File`
4. Select the entire `SentinelAntiExploit` folder
5. Rename the inserted folder to `SentinelAntiExploit`

### Initialize the System
Create a new Script in `ServerScriptService`:

```lua
-- ServerScriptService/InitSentinel.lua
local Sentinel = require(game.ServerScriptService.SentinelAntiExploit.MainModule)

-- Optional: Enable debug mode during testing
Sentinel:SetDebugMode(true)

print("✅ Sentinel Anti-Exploit v4.0.0 initialized successfully")
```

### Test the System
1. Publish your game
2. Join as a player
3. Check output for initialization message
4. Monitor for any detection logs
