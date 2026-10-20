local ScriptScanner = {}
ScriptScanner._trackedScripts = {}
ScriptScanner._injectionAttempts = 0

function ScriptScanner:Initialize()
    self:_MonitorDescendants()
    self:_MonitorEnvironment()
    self:_HookRequire()
end

function ScriptScanner:_MonitorDescendants()
    game.DescendantAdded:Connect(function(descendant)
        if not Utilities.IsValidInstance(descendant) then return end
        
        if self:_IsSuspiciousInstance(descendant) then
            Logger:LogDetection("ILLEGAL_INSTANCE_CREATION", {
                Instance = descendant:GetFullName(),
                ClassName = descendant.ClassName,
                Parent = descendant.Parent:GetFullName()
            })
        end
        
        if descendant:IsA("LuaSourceContainer") then
            self:_MonitorScriptBehavior(descendant)
        end
    end)
end

function ScriptScanner:_MonitorEnvironment()
    local originalEnv = Utilities.DeepCopy(getfenv(0))
    
    setmetatable(getfenv(0), {
        __newindex = function(t, k, v)
            if not rawget(t, k) and string.sub(k, 1, 2) == "__" then
                Logger:LogDetection("ENVIRONMENT_MODIFICATION", {
                    Key = k,
                    ValueType = type(v),
                    StackTrace = debug.traceback()
                })
            end
            rawset(t, k, v)
        end
    })
end

function ScriptScanner:_HookRequire()
    local originalRequire = require
    require = function(module)
        local result = originalRequire(module)
        
        if type(result) == "table" then
            for k, v in pairs(result) do
                if type(v) == "function" then
                    if string.find(tostring(k):lower(), "exploit") then
                        Logger:LogDetection("SUSPICIOUS_MODULE", {
                            Module = tostring(module),
                            Method = tostring(k)
                        })
                    end
                end
            end
        end
        
        return result
    end
end

function ScriptScanner:_IsSuspiciousInstance(instance)
    local name = instance.Name:lower()
    
    for _, suspiciousName in ipairs(Config.SuspiciousNames) do
        if string.find(name, suspiciousName) then
            return true
        end
    end
    
    return false
end

function ScriptScanner:_MonitorScriptBehavior(script)
    if script:IsA("ModuleScript") then
        self._trackedScripts[script] = {
            LoadTime = os.time(),
            RequireCount = 0
        }
    end
end

return ScriptScanner
