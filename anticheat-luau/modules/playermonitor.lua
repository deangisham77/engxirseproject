local PlayerMonitor = {}
PlayerMonitor._playerData = {}
PlayerMonitor._characterMonitors = {}

function PlayerMonitor:Initialize()
    self:_MonitorPlayerJoining()
    self:_MonitorExistingPlayers()
end

function PlayerMonitor:_MonitorPlayerJoining()
    game.Players.PlayerAdded:Connect(function(player)
        self:_InitializePlayerData(player)
        self:_MonitorPlayerCharacter(player)
        self:_MonitorPlayerTools(player)
    end)
end

function PlayerMonitor:_MonitorExistingPlayers()
    for _, player in ipairs(game.Players:GetPlayers()) do
        self:_InitializePlayerData(player)
        self:_MonitorPlayerCharacter(player)
        self:_MonitorPlayerTools(player)
    end
end

function PlayerMonitor:_InitializePlayerData(player)
    self._playerData[player] = {
        JoinTime = os.time(),
        DetectionCount = 0,
        LastPosition = Vector3.new(0, 0, 0),
        LastSpeedCheck = os.time(),
        RemoteCallCount = 0,
        Tools = {}
    }
end

function PlayerMonitor:_MonitorPlayerCharacter(player)
    player.CharacterAdded:Connect(function(character)
        self:_SetupCharacterMonitoring(character, player)
    end)
    
    if player.Character then
        self:_SetupCharacterMonitoring(player.Character, player)
    end
end

function PlayerMonitor:_SetupCharacterMonitoring(character, player)
    if self._characterMonitors[player] then
        self._characterMonitors[player]:Disconnect()
    end
    
    local monitorCoroutine = coroutine.create(function()
        self:_MonitorMovement(character, player)
        self:_MonitorFlight(character, player)
        self:_MonitorTeleportation(character, player)
    end)
    
    coroutine.resume(monitorCoroutine)
end

function PlayerMonitor:_MonitorMovement(character, player)
    local lastPosition = character:GetPivot().Position
    local lastCheck = os.time()
    
    while character and character.Parent do
        wait(0.1)
        local currentTime = os.time()
        local currentPosition = character:GetPivot().Position
        local distance = Utilities.CalculateDistance(currentPosition, lastPosition)
        local timeDiff = currentTime - lastCheck
        
        if timeDiff > 0 then
            local speed = distance / timeDiff
            
            if speed > Config.MaxPlayerSpeed then
                Logger:LogDetection("SPEED_HACK_DETECTED", {
                    Player = player.Name,
                    Speed = speed,
                    MaxAllowed = Config.MaxPlayerSpeed,
                    Position = currentPosition
                })
            end
        end
        
        lastPosition = currentPosition
        lastCheck = currentTime
    end
end

function PlayerMonitor:_MonitorFlight(character, player)
    local lastY = character:GetPivot().Position.Y
    local flightStartTime = nil
    
    while character and character.Parent do
        wait(0.5)
        local currentY = character:GetPivot().Position.Y
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        
        if humanoid and not humanoid:GetStateEnabled(Enum.HumanoidStateType.Freefall) then
            if currentY > lastY + 10 then
                flightStartTime = flightStartTime or os.time()
                
                if os.time() - flightStartTime > Config.FlyDetectionTime then
                    Logger:LogDetection("FLY_HACK_DETECTED", {
                        Player = player.Name,
                        Duration = os.time() - flightStartTime,
                        Height = currentY
                    })
                end
            else
                flightStartTime = nil
            end
        else
            flightStartTime = nil
        end
        
        lastY = currentY
    end
end

function PlayerMonitor:_MonitorTeleportation(character, player)
    local lastPosition = character:GetPivot().Position
    
    while character and character.Parent do
        wait(0.1)
        local currentPosition = character:GetPivot().Position
        local distance = Utilities.CalculateDistance(currentPosition, lastPosition)
        
        if distance > Config.MaxTeleportDistance then
            Logger:LogDetection("TELEPORT_HACK_DETECTED", {
                Player = player.Name,
                Distance = distance,
                FromPosition = lastPosition,
                ToPosition = currentPosition
            })
        end
        
        lastPosition = currentPosition
    end
end

function PlayerMonitor:_MonitorPlayerTools(player)
    player.CharacterAdded:Connect(function(character)
        local backpack = player:FindFirstChildOfClass("Backpack")
        if backpack then
            self:_MonitorBackpack(backpack, player)
        end
    end)
end

function PlayerMonitor:_MonitorBackpack(backpack, player)
    backpack.ChildAdded:Connect(function(tool)
        if tool:IsA("Tool") then
            self:_AnalyzeTool(tool, player)
        end
    end)
end

function PlayerMonitor:_AnalyzeTool(tool, player)
    for _, script in ipairs(tool:GetDescendants()) do
        if script:IsA("LuaSourceContainer") then
            if self:_IsSuspiciousScript(script) then
                Logger:LogDetection("SUSPICIOUS_TOOL_SCRIPT", {
                    Player = player.Name,
                    Tool = tool.Name,
                    Script = script:GetFullName()
                })
            end
        end
    end
end

function PlayerMonitor:_IsSuspiciousScript(script)
    if script.Source then
        local sourceLower = script.Source:lower()
        for _, pattern in ipairs(Config.SuspiciousNames) do
            if string.find(sourceLower, pattern) then
                return true
            end
        end
    end
    return false
end

return PlayerMonitor
