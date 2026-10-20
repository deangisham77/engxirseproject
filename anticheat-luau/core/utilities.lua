local Utilities = {}

function Utilities.GenerateUUID()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

function Utilities.DeepCopy(original)
    local copy = {}
    for k, v in pairs(original) do
        if type(v) == "table" then
            v = Utilities.DeepCopy(v)
        end
        copy[k] = v
    end
    return copy
end

function Utilities.GetPlayerHardwareID(player)
    return tostring(player.UserId)
end

function Utilities.CalculateDistance(pos1, pos2)
    return (pos1 - pos2).Magnitude
end

function Utilities.IsValidInstance(instance)
    return instance and instance.Parent ~= nil
end

return Utilities
