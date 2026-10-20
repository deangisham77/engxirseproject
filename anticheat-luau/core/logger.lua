local Logger = {}
Logger.DebugMode = false

function Logger:LogDetection(detectionType, data)
    local logEntry = {
        Type = detectionType,
        Timestamp = os.time(),
        Data = data,
        StackTrace = debug.traceback()
    }
    
    if self.DebugMode then
        print("[SENTINEL DETECTION] " .. detectionType)
        for k, v in pairs(data) do
            print("   " .. k .. ": " .. tostring(v))
        end
    end
    
    self:SaveToDatastore(logEntry)
end

function Logger:LogEvent(eventType, message)
    if self.DebugMode then
        print("[SENTINEL EVENT] " .. eventType .. " - " .. message)
    end
end

function Logger:SaveToDatastore(logEntry)
    local success, result = pcall(function()
        local DataStoreService = game:GetService("DataStoreService")
        local detectionLogs = DataStoreService:GetDataStore("SentinelDetectionLogs")
        
        local logId = Utilities.GenerateUUID()
        detectionLogs:SetAsync(logId, logEntry)
    end)
end

return Logger
