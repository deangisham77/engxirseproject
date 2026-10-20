local Sentinel = {}

local Core = {
    Config = require(script.Core.Config),
    Utilities = require(script.Core.Utilities),
    Logger = require(script.Core.Logger)
}

local Modules = {
    ScriptScanner = require(script.Modules.ScriptScanner),
    RemoteMonitor = require(script.Modules.RemoteMonitor),
    PlayerMonitor = require(script.Modules.PlayerMonitor)
}

Sentinel.Version = "4.0.0"
Sentinel.SessionId = Core.Utilities.GenerateUUID()
Sentinel.ActiveDetections = 0
Sentinel.DetectionThreshold = Core.Config.DetectionThreshold

function Sentinel:Initialize()
    if self._initialized then return end
    
    Core.Logger:LogEvent("SYSTEM_INIT", "Sentinel Anti-Exploit v" .. self.Version .. " initializing...")
    
    for name, module in pairs(Modules) do
        local success, err = pcall(function()
            module:Initialize()
        end)
        
        if success then
            Core.Logger:LogEvent("MODULE_LOADED", name .. " initialized successfully")
        else
            Core.Logger:LogEvent("MODULE_ERROR", name .. " failed: " .. tostring(err))
        end
    end
    
    self:_SetupHeartbeat()
    self._initialized = true
    
    Core.Logger:LogEvent("SYSTEM_READY", "Sentinel Anti-Exploit fully operational")
end

function Sentinel:_SetupHeartbeat()
    game:GetService("RunService").Heartbeat:Connect(function()
        self:_PerformPeriodicScans()
    end)
end

function Sentinel:_PerformPeriodicScans()
    local currentTime = os.time()
    
    if not self._lastScan then
        self._lastScan = currentTime
    end
    
    if currentTime - self._lastScan >= Core.Config.ScanInterval then
        self:_ScanMemory()
        self:_ScanConnections()
        self._lastScan = currentTime
    end
end

function Sentinel:_ScanMemory()
    local memoryUsage = collectgarbage("count")
    
    if memoryUsage > Core.Config.MaxMemorySpike then
        Core.Logger:LogDetection("MEMORY_SPIKE_DETECTED", {
            MemoryUsage = memoryUsage,
            Threshold = Core.Config.MaxMemorySpike
        })
    end
end

function Sentinel:_ScanConnections()
    local connectionCount = 0
    for _ in pairs(getconnections) do
        connectionCount = connectionCount + 1
    end
    
    if connectionCount > 1000 then
        Core.Logger:LogDetection("EXCESSIVE_CONNECTIONS", {
            ConnectionCount = connectionCount
        })
    end
end

function Sentinel:GetDetectionCount()
    return self.ActiveDetections
end

function Sentinel:GetPlayerData(player)
    return Modules.PlayerMonitor._playerData[player]
end

function Sentinel:SetDebugMode(enabled)
    Core.Logger.DebugMode = enabled
    Core.Logger:LogEvent("DEBUG_MODE", enabled and "enabled" or "disabled")
end

function Sentinel:Shutdown()
    for _, connection in pairs(self._connections) do
        connection:Disconnect()
    end
    
    self._initialized = false
    Core.Logger:LogEvent("SYSTEM_SHUTDOWN", "Sentinel Anti-Exploit shutdown complete")
end

Sentinel:Initialize()
return Sentinel
