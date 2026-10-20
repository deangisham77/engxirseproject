local RemoteMonitor = {}
RemoteMonitor._remoteCallLog = {}
RemoteMonitor._rateLimits = {}

function RemoteMonitor:Initialize()
    self:_SecureExistingRemotes()
    self:_MonitorNewRemotes()
end

function RemoteMonitor:_SecureExistingRemotes()
    for _, remote in ipairs(game:GetDescendants()) do
        if remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction") then
            self:_ApplySecurity(remote)
        end
    end
end

function RemoteMonitor:_MonitorNewRemotes()
    game.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("RemoteEvent") or descendant:IsA("RemoteFunction") then
            self:_ApplySecurity(descendant)
        end
    end)
end

function RemoteMonitor:_ApplySecurity(remote)
    if remote:IsA("RemoteEvent") then
        local originalFireServer = remote.FireServer
        remote.FireServer = function(self, player, ...)
            local args = {...}
            if not self:_ValidateRemoteCall(remote, player, args) then
                return
            end
            return originalFireServer(self, player, unpack(args))
        end
    elseif remote:IsA("RemoteFunction") then
        local originalInvokeServer = remote.InvokeServer
        remote.InvokeServer = function(self, player, ...)
            local args = {...}
            if not self:_ValidateRemoteCall(remote, player, args) then
                error("Security validation failed")
            end
            return originalInvokeServer(self, player, unpack(args))
        end
    end
end

function RemoteMonitor:_ValidateRemoteCall(remote, player, args)
    if not self:_CheckRateLimit(player) then
        Logger:LogDetection("RATE_LIMIT_EXCEEDED", {
            Player = player.Name,
            UserId = player.UserId,
            Remote = remote:GetFullName()
        })
        return false
    end
    
    if not self:_ValidateArguments(args) then
        Logger:LogDetection("INVALID_REMOTE_ARGS", {
            Player = player.Name,
            Remote = remote:GetFullName(),
            Args = #args
        })
        return false
    end
    
    if not self:_CheckCallStack() then
        Logger:LogDetection("SUSPICIOUS_CALL_STACK", {
            Player = player.Name,
            Remote = remote:GetFullName(),
            StackTrace = debug.traceback()
        })
        return false
    end
    
    return true
end

function RemoteMonitor:_CheckRateLimit(player)
    local currentTime = os.time()
    local playerId = player.UserId
    
    if not self._rateLimits[playerId] then
        self._rateLimits[playerId] = {
            Count = 0,
            LastReset = currentTime
        }
    end
    
    local rateData = self._rateLimits[playerId]
    
    if currentTime - rateData.LastReset >= 1 then
        rateData.Count = 0
        rateData.LastReset = currentTime
    end
    
    rateData.Count = rateData.Count + 1
    
    return rateData.Count <= Config.MaxRemoteCallsPerSecond
end

function RemoteMonitor:_ValidateArguments(args)
    for i, arg in ipairs(args) do
        local argType = type(arg)
        
        if argType == "function" then
            return false
        end
        
        if argType == "table" and getmetatable(arg) then
            return false
        end
        
        if argType == "userdata" then
            local success = pcall(function()
                return tostring(arg)
            end)
            if not success then
                return false
            end
        end
    end
    
    return true
end

function RemoteMonitor:_CheckCallStack()
    local stack = debug.traceback()
    local suspiciousPatterns = {
        "hookfunction",
        "gethui",
        "getrawmetatable",
        "setclipboard"
    }
    
    for _, pattern in ipairs(suspiciousPatterns) do
        if string.find(stack:lower(), pattern:lower()) then
            return false
        end
    end
    
    return true
end

return RemoteMonitor
