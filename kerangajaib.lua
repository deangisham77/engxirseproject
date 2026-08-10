--========================================================
-- ANTI-NUMPUK
--========================================================
pcall(function()
    if getgenv().FluentShellsLoaded and type(getgenv().FluentShellsCleanup) == "function" then
        getgenv().FluentShellsCleanup()
    end
    getgenv().FluentShellsLoaded = nil
    getgenv().FluentShellsCleanup = nil
end)
task.wait(0.1)
getgenv().FluentShellsLoaded = true

-- ============================================================
-- SERVICES & INIT
-- ============================================================
local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local LP      = Players.LocalPlayer
local HttpService = game:GetService("HttpService")

local function requireWithRetry(path, name)
    local ok, res = pcall(require, path)
    if not ok then
        warn("[Shells Auto] Failed to require " .. name .. ": " .. tostring(res))
        task.wait(1)
        ok, res = pcall(require, path)
        if not ok then error("CRITICAL: Cannot require " .. name) end
    end
    return res
end

local NetworkModule = RS:WaitForChild("Modules"):WaitForChild("Communication"):WaitForChild("Network")
local Net = requireWithRetry(NetworkModule, "Network")

local TraitsDataModule = RS:WaitForChild("Modules"):WaitForChild("GameModules"):WaitForChild("Info"):WaitForChild("TraitsData")
local TraitsData = requireWithRetry(TraitsDataModule, "TraitsData")

local ShellDataModule = RS:WaitForChild("Modules"):WaitForChild("GameModules"):WaitForChild("Info"):WaitForChild("Shells")
local ShellData = requireWithRetry(ShellDataModule, "Shells")

local ModifierDataModule = RS:WaitForChild("Modules"):WaitForChild("GameModules"):WaitForChild("Info"):WaitForChild("ModifierData")
local ModifierData = requireWithRetry(ModifierDataModule, "ModifierData")

local MerchantCatalogueModule = RS:WaitForChild("Modules"):WaitForChild("GameModules"):WaitForChild("Info"):WaitForChild("MerchantCatalogue")
local MerchantCatalogue = requireWithRetry(MerchantCatalogueModule, "MerchantCatalogue")

local RarityDataModule = RS:WaitForChild("Modules"):WaitForChild("GameModules"):WaitForChild("Info"):WaitForChild("RarityData")
local RarityData = requireWithRetry(RarityDataModule, "RarityData")

local MerchantPrices = {}
if MerchantCatalogue then
    for _, item in ipairs(MerchantCatalogue) do
        MerchantPrices[item.id] = item.price or 0
    end
end

local ToolFolder = RS.Assets.Equipment.Tools

local ToolList = {}
for _,v in ipairs(ToolFolder:GetChildren()) do
    table.insert(ToolList, v.Name)
end
table.sort(ToolList)

local TraitList = {}
if TraitsData then
    for _, v in pairs(TraitsData) do
        if type(v) == "table" and v.Name then
            table.insert(TraitList, v.Name)
        elseif type(v) == "string" then
            table.insert(TraitList, v)
        end
    end
end
table.sort(TraitList)

local SelectedTool = ToolList[1]
local TargetTrait = #TraitList > 0 and TraitList[1] or ""
local RollDelay = 0.25
local TraitRollRunning = false
local TraitRolls = 0
local TraitRollThread = nil
local LastTrait = ""

-- ============================================================
-- TRAIT ROLL FUNCTIONS
-- ============================================================
local rareTraits = {
    Pristine = true, Celestial = true, Transcendent = true,
    Rake = true, ["All or Nothing"] = true,
}

local function doSingleRoll()
    local t = os.clock()
    local ok, trait = pcall(function()
        return Net.Traits.queries.RollTrait.invoke(SelectedTool)
    end)
    if ok then
        TraitRolls += 1
        LastTrait = trait
        print(("Roll RTT: %.3f s"):format(os.clock() - t))
        return trait
    else
        warn("[TraitRoll] Roll failed: " .. tostring(trait))
        return nil
    end
end

-- ============================================================
-- WEBHOOK FUNCTIONS AND STATE
-- ============================================================
local webhookUrl = ""
local webhookSelectedRarities = {}
local webhookEnabled = false
local webhookLostCityNotify = false
local webhookMonitorThread = nil
local webhookMonitorConn = nil

local ShellRarities = {}
if ShellData and ShellData.Items then
    for _, shell in ipairs(ShellData.Items) do
        ShellRarities[shell.Name] = shell.Rarity
    end
end

local ShellNameList = {}
if ShellData and ShellData.Items then
    for _, shell in ipairs(ShellData.Items) do
        table.insert(ShellNameList, shell.Name)
    end
end
table.sort(ShellNameList)

local function getShellRarity(shellName)
    return ShellRarities[shellName]
end

local RARITY_LIST = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Exotic", "Abyssal" }

local function getShellValue(shellName, weight, modifier)
    if not ShellData or not ShellData.Names or not ModifierData then return 0 end
    local shellInfo = ShellData.Names[shellName]
    if not shellInfo then return 0 end
    local baseValue = shellInfo.Cost or 0
    if modifier and ModifierData[modifier] then
        baseValue = baseValue * (ModifierData[modifier].Mult or 1)
    end
    return math.floor(baseValue * weight + 0.5)
end

local function sendDiscordWebhook(url, payload)
    if url == nil or url == "" then return false end
    local requestFunc = syn and syn.request or http_request or request
    if not requestFunc then
        warn("[Webhook] No request function available")
        return false
    end
    local ok, response = pcall(function()
        return requestFunc({
            Url = url, Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(payload)
        })
    end)
    if not ok then warn("[Webhook] Request failed:", response); return false end
    if type(response) == "table" and response.StatusCode then
        return response.StatusCode >= 200 and response.StatusCode < 300
    end
    return true
end

local function startWebhookMonitor()
    if webhookMonitorConn then webhookMonitorConn:Disconnect(); webhookMonitorConn = nil end
    if webhookMonitorThread then task.cancel(webhookMonitorThread); webhookMonitorThread = nil end

    webhookMonitorThread = task.spawn(function()
        local processedShells = {}
        local backpack = nil
        local conn = nil

        while true do
            if not webhookEnabled then task.wait(1); continue end

            local newBackpack = LP:FindFirstChild("Backpack")
            if newBackpack ~= backpack then
                if conn then conn:Disconnect() end
                backpack = newBackpack
                if backpack then
                    processedShells = {}
                    for _, item in ipairs(backpack:GetChildren()) do
                        if item:IsA("Tool") then processedShells[item] = true end
                    end
                    conn = backpack.ChildAdded:Connect(function(item)
                        if not webhookEnabled then return end
                        if item:IsA("Tool") and not processedShells[item] then
                            processedShells[item] = true
                            local shellName = item:GetAttribute("Name")
                            local rarity = getShellRarity(shellName)
                            print("[Webhook] New Tool:", shellName, "| Rarity:", rarity)
                            if rarity and webhookSelectedRarities[rarity] then
                                local weight = item:GetAttribute("Weight") or 0
                                local modifier = item:GetAttribute("Modifier")
                                local value = getShellValue(shellName, weight, modifier)
                                sendDiscordWebhook(webhookUrl, {
                                    embeds = {{
                                        title = "New Shell Obtained!",
                                        color = 0x00ff00,
                                        fields = {
                                            { name = "Name", value = shellName, inline = true },
                                            { name = "Rarity", value = rarity, inline = true },
                                            { name = "Weight", value = tostring(weight), inline = true },
                                            { name = "Value", value = tostring(value), inline = true },
                                            { name = "Modifier", value = modifier or "None", inline = true },
                                            { name = "Player", value = LP.Name, inline = true }
                                        },
                                        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
                                    }}
                                })
                            end
                        end
                    end)
                    webhookMonitorConn = conn
                end
            end
            task.wait(1)
        end
    end)
end

local function sendLostCityWebhook(isActive)
    if not webhookLostCityNotify or webhookUrl == "" then return end
    local ok = sendDiscordWebhook(webhookUrl, {
        embeds = {{
            title = isActive and "Lost City Spawned!" or "Lost City Disappeared!",
            color = isActive and 0x00ff00 or 0xff0000,
            description = isActive
                and "Ancient Turtle telah memunculkan Lost City!"
                or "Event Lost City telah berakhir.",
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }}
    })
    if not ok then
        warn("[Webhook] Lost City notification failed")
        Fluent:Notify({ Title = "Webhook", Content = "Lost City notification failed", Duration = 3 })
    end
end

-- ============================================================
-- VARIABLES
-- ============================================================
local S = {}

local autoDig, autoSell, sellCount, busyDig, busySell, activeDig = false, false, 100, false, false, nil
local autoStorageUpgrade, storageUpgradeThread = false, nil
local mythicOnly, mythicRetryDelay = false, 0.6
S.fav = { enabled = false, rarities = {}, shells = {}, thread = nil, processed = {} }
S.vlt = { enabled = false, rarities = {}, shells = {}, thread = nil, processed = {} }
S.gft = { enabled = false, target = nil, rarities = {}, shells = {}, thread = nil, byValue = false, targetValue = 0, valueMode = "once", giftedCount = 0, giftedValue = 0 }

local function getFav() return S.fav end

local TOL     = 10
local OFFSET  = 0
local DEBOUNCE = 0.08

-- Teleport Locations
local TeleportLocations = {
    Islands = {
        ["Solmere"] = Vector3.new(-1439.899, 30.321, -1675.230),
        ["Caldera Cay"] = Vector3.new(1769.212, 81.270, -1338.000),
        ["Sea Stacks Island"] = Vector3.new(869.575, 25.097, 1354.684),
        ["Crescent Shore"] = Vector3.new(-1475.150, 34.157, 1458.112),
        ["Bay Island"] = Vector3.new(33.270, 63.200, 62.291),
        ["Sacred Mountain"] = Vector3.new(2618.481, 26.746, 274.485),
        ["Sky Island"] = Vector3.new(119.697, 3084.737, 1052.779),
        ["Frostveil Isle"] = Vector3.new(3772.228, 48.143, -969.551),
        ["Glowcap Cave"] = Vector3.new(1459.522, -106.888, 1121.578),
        ["Coral Graveyard"] = Vector3.new(2581.459, -89.776, -637.250),
        ["Lost City"] = Vector3.new(17068.666, -59.222, 3503.329),
        ["Party Island"] = Vector3.new(-1765.215, 133.315, -86.732),
        ["Rulers Kingdom"] = Vector3.new(-336.089, 159.994, -2370.950),
        ["Nautilus Hollow"] = Vector3.new(1016.467, -53.695, 1116.630),
    },
}

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================
local VIM = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")

-- ============================================================
-- STORAGE INFO
-- ============================================================
local function getStorageInfo()
    if not Net.Storage then return { Current = 0, Limit = 0, Percent = 0 } end
    local ok, info = pcall(function() return Net.Storage.queries.GetStorageInfo.invoke() end)
    if ok and info and info.Limit and info.Limit > 0 then
        return { Current = info.Current, Limit = info.Limit, Percent = (info.Current / info.Limit) * 100 }
    end
    return { Current = 0, Limit = 0, Percent = 0 }
end

-- ============================================================
-- DIGGING FUNCTIONS
-- ============================================================
local digParams = RaycastParams.new()
digParams.FilterType = Enum.RaycastFilterType.Include
digParams.IgnoreWater = true
digParams.FilterDescendantsInstances = { workspace:WaitForChild("Map") }

local function onDiggable()
    local char = LP.Character
    if not char then return false end
    local hit = workspace:Raycast(char:GetPivot().Position, Vector3.new(0, -12, 0), digParams)
    return hit and (hit.Material == Enum.Material.Sand or (hit.Instance and hit.Instance:HasTag("Diggable")))
end

local function getEquip()
    local char = LP.Character
    if not char then return nil end
    local cur = char:FindFirstChildOfClass("Tool")
    if cur and cur:GetAttribute("Type") == "Equipment" then return cur end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    for _, t in ipairs(LP.Backpack:GetChildren()) do
        if t:IsA("Tool") and t:GetAttribute("Type") == "Equipment" then
            hum:EquipTool(t)
            task.wait(0.25)
            return char:FindFirstChildOfClass("Tool")
        end
    end
    return nil
end

local function nearestMerchant()
    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local best, bestD
    for _, m in ipairs(workspace.Map:GetDescendants()) do
        if m.Name == "Merchant" and m:FindFirstChild("HumanoidRootPart") then
            local d = (m.HumanoidRootPart.Position - hrp.Position).Magnitude
            if not bestD or d < bestD then bestD, best = d, m end
        end
    end
    return best
end

-- ============================================================
-- SELL ALL
-- ============================================================
local function sellAll()
    if busySell then return end
    busySell = true
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local m = nearestMerchant()
    local oldCFrame = hrp and hrp.CFrame

    if m and hrp then
        hrp.CFrame = m.HumanoidRootPart.CFrame * CFrame.new(0, 0, 5)
        task.wait(0.4)
    end
    pcall(function()
        Net.Merchant.packets.SellAll.send()
    end)
    task.wait(0.55)
    if oldCFrame and hrp then hrp.CFrame = oldCFrame end
    Fluent:Notify({ Title = "Shells Auto", Content = "Inventory sold", Duration = 2 })
    busySell = false
end

local function tpTo(position)
    local char = LP.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    hrp.CFrame = CFrame.new(position)
end

-- ============================================================
-- QTE NETWORKING
-- ============================================================
local function nrm(a) return (a % 360 + 360) % 360 end
local function adiff(a, b) return math.abs(((a - b + 180) % 360) - 180) end

task.spawn(function()
    while not Net.QTE do task.wait(0.5) end

    Net.QTE.packets.BarSwap.listen(function(p)
        local s = activeDig
        if not s then return end
        local now = workspace:GetServerTimeNow()
        if p.swapId == s.swapId then
            s.swapStartLine = p.swapStartLine
            s.swapTime = p.swapTime
        else
            local v = (s.swapStartLine + s.barSpeed * (now - s.swapTime)) % 360
            s.swapId = p.swapId
            s.swapStartLine = v
            s.swapTime = now
        end
        s.barSpeed = p.barSpeed
        s.barRotation = p.barRotation
    end)

    Net.QTE.packets.FinishQTE.listen(function(_)
        local s = activeDig
        if s then s.finished = true end
    end)
end)

local function doDigWithResponse(r)
    if not r or r.fail then return false, r end
    local s = {
        swapId = r.swapId, swapTime = r.swapTime,
        swapStartLine = r.swapStartLine, barSpeed = r.barSpeed,
        barRotation = r.barRotation, finished = false,
    }
    activeDig = s
    local lastClick = 0
    local deadline = os.clock() + 25
    local loopStart = os.clock()
    while not s.finished and os.clock() < deadline and (autoDig or mythicOnly) do
        local sp = s.barSpeed
        if sp and sp ~= 0 then
            local now = workspace:GetServerTimeNow()
            local line = (s.swapStartLine + sp * (now - s.swapTime)) % 360
            local target = (s.barRotation - OFFSET) % 360
            if math.abs(((line - target + 180) % 360) - 180) <= TOL and (os.clock() - lastClick) >= DEBOUNCE then
                s.swapStartLine = line
                s.swapTime = now
                s.barSpeed = -sp
                local frameAge = math.clamp(os.clock() - loopStart, 0, 5)
                Net.QTE.packets.Click.send({ swapId = s.swapId, clickTime = now, clickAngle = line, frameAge = frameAge })
                lastClick = os.clock()
            end
        end
        task.wait()
        loopStart = os.clock()
    end
    if not s.finished then pcall(function() Net.QTE.packets.CancelQTE.send() end) end
    activeDig = nil
    return s.finished
end

local function traitRollLoop()
    while TraitRollRunning do
        local trait = doSingleRoll()
        if trait then
            local rare = rareTraits[trait]
            if rare then
                TraitRollRunning = false
                Fluent:Notify({ Title = "Shells Auto", Content = "Rare trait: " .. trait .. " (" .. TraitRolls .. " rolls)", Duration = 8 })
                Window:Dialog({
                    Title = "Rare Trait Found!",
                    Content = trait .. " detected after " .. TraitRolls .. " rolls!",
                    Buttons = {
                        {
                            Title = "Continue Rolling",
                            Callback = function()
                                if TraitRollThread then task.cancel(TraitRollThread) end
                                TraitRollRunning = true
                                TraitRollThread = task.spawn(traitRollLoop)
                            end,
                        },
                        {
                            Title = "Stop Rolling",
                            Callback = function()
                                TraitRollRunning = false
                                if TraitRollThread then task.cancel(TraitRollThread); TraitRollThread = nil end
                            end,
                        },
                    }
                })
                break
            end
            if trait == TargetTrait then
                TraitRollRunning = false
                Fluent:Notify({ Title = "Shells Auto", Content = "Target trait " .. TargetTrait .. " found! (" .. TraitRolls .. " rolls)", Duration = 5 })
                if TraitRollThread then task.cancel(TraitRollThread); TraitRollThread = nil end
                break
            end
        end
        task.wait(RollDelay)
    end
end

local function digLoop()
    if busyDig then return end
    busyDig = true
    while autoDig or mythicOnly do
        local info = getStorageInfo()
        if info.Current >= info.Limit then
            if autoSell then sellAll()
            else Fluent:Notify({ Title = "Shells Auto", Content = "Inventory full - digging paused", Duration = 3 }); task.wait(3) end
            task.wait(); continue
        end
        if not onDiggable() then task.wait(0.5); continue end
        if not getEquip() then task.wait(0.5); continue end

        if mythicOnly and not autoDig then
            local r = Net.QTE.queries.StartQTE.invoke()
            if not r or r.fail then task.wait(0.5); continue end
            if not r.hasSurgeBar then
                pcall(function() Net.QTE.packets.CancelQTE.send() end)
                task.wait(mythicRetryDelay); continue
            end
            doDigWithResponse(r); task.wait(0.05); continue
        end
        if autoDig then
            local r = Net.QTE.queries.StartQTE.invoke()
            if not r or r.fail then task.wait(0.5); continue end
            doDigWithResponse(r); task.wait(0.05)
        else task.wait(0.5) end
    end
    busyDig = false
end

-- ============================================================
-- SELL WATCHER
-- ============================================================
local function sellWatcher()
    while autoSell do
        local info = getStorageInfo()
        if info.Current >= sellCount and not busySell then
            sellAll()
            task.wait(1)
        end
        task.wait(2)
    end
end

-- ============================================================
-- LOST CITY
-- ============================================================
local LOST_CITY_POS = Vector3.new(17303.939, -65.534, 3661.151)
local lostCityActive = false
local lostCityReturnCF = nil
local lostCityThread = nil
local lostCityLockThread = nil

local function startLostCityMonitor()
    if lostCityThread then task.cancel(lostCityThread) end
    lostCityThread = task.spawn(function()
        local wasFound = false
        while true do
            local lostCity = workspace:FindFirstChild("Lost City", true)
            if lostCity and not wasFound then
                wasFound = true
                print("[Lost City] DETECTED")
                Fluent:Notify({ Title = "Shells Auto", Content = "Lost City detected! Teleporting...", Duration = 3 })
                local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                if hrp and not lostCityActive then
                    lostCityReturnCF = hrp.CFrame
                    lostCityActive = true
                    hrp.CFrame = CFrame.new(LOST_CITY_POS)
                    sendLostCityWebhook(true)
                    if lostCityLockThread then task.cancel(lostCityLockThread) end
                    lostCityLockThread = task.spawn(function()
                        while lostCityActive do
                            task.wait(0.5)
                            local h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                            if h and (h.Position - LOST_CITY_POS).Magnitude > 1 then
                                h.CFrame = CFrame.new(LOST_CITY_POS)
                            end
                        end
                    end)
                end
            elseif not lostCity and wasFound then
                wasFound = false
                Fluent:Notify({ Title = "Shells Auto", Content = "Lost City disappeared, returning...", Duration = 3 })
                sendLostCityWebhook(false)
                if lostCityReturnCF then
                    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then hrp.CFrame = lostCityReturnCF end
                    lostCityReturnCF = nil
                end
                lostCityActive = false
                if lostCityLockThread then task.cancel(lostCityLockThread); lostCityLockThread = nil end
            end
            task.wait(1)
        end
    end)
end

-- ============================================================
-- AUTO DEBRIS — v3: TP → Gali (QTE) → MoonGiftBox → Interact
-- ============================================================
local debrisReturnPos = nil
local debrisActive = false
local debrisCompleted = {}
local debrisThread = nil

local function getDebrisPos(d)
    if d:IsA("BasePart") then return d.Position end
    if d:IsA("Model") then
        if d.PrimaryPart then return d.PrimaryPart.Position end
        local sum, count = Vector3.new(), 0
        for _, c in ipairs(d:GetChildren()) do
            if c:IsA("BasePart") then sum = sum + c.Position; count = count + 1 end
        end
        if count > 0 then return sum / count end
    end
    return nil
end

local function findNearestDebris()
    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local impact = workspace:FindFirstChild("ImpactDebris")
    if not impact then return nil end
    local best, bestD
    for _, d in ipairs(impact:GetChildren()) do
        if not debrisCompleted[d] then
            local claimer = d:GetAttribute("ClaimerUserId")
            if claimer and claimer ~= LP.UserId then continue end
            local pos = getDebrisPos(d)
            if pos then
                local dist = (pos - hrp.Position).Magnitude
                if not bestD or dist < bestD then bestD, best = dist, d end
            end
        end
    end
    return best
end

local function waitForMoonGift(maxWait)
    local waitStart = os.clock()
    while os.clock() - waitStart < maxWait do
        local moon = workspace:FindFirstChild("MoonGiftBox")
        if moon then return moon end
        task.wait(0.5)
    end
    return nil
end

local function interactMoonGift(moon)
    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not hrp or not moon then return end
    local pos = getDebrisPos(moon)
    if pos then hrp.CFrame = CFrame.new(pos) end
    task.wait(0.3)
    for _, desc in ipairs(moon:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            pcall(function() fireproximityprompt(desc) end)
            Fluent:Notify({ Title = "Shells Auto", Content = "Moon Gift opened!", Duration = 2 })
            return true
        end
    end
    return false
end

local function startAutoDebris()
    if debrisThread then task.cancel(debrisThread) end
    debrisThread = task.spawn(function()
        while true do
            if lostCityActive then task.wait(1); continue end

            local d = findNearestDebris()
            if not d then
                if debrisActive and debrisReturnPos then
                    local h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                    if h then h.CFrame = debrisReturnPos end
                    debrisReturnPos = nil
                    debrisActive = false
                    Fluent:Notify({ Title = "Shells Auto", Content = "All debris done, returned", Duration = 2 })
                end
                task.wait(1)
                continue
            end

            local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then task.wait(0.5); continue end

            if not debrisActive then
                debrisReturnPos = hrp.CFrame
                debrisActive = true
            end

            local pos = getDebrisPos(d)
            if not pos then debrisCompleted[d] = true; continue end

            hrp.CFrame = CFrame.new(pos)
            Fluent:Notify({ Title = "Shells Auto", Content = "Teleport to debris", Duration = 1 })

            while activeDig do task.wait(0.1) end

            if not getEquip() then task.wait(0.5); continue end
            local r = Net.QTE.queries.StartQTE.invoke()
            if r and not r.fail then
                doDigWithResponse(r)
            end

            local moon = waitForMoonGift(30)
            if moon then interactMoonGift(moon) end

            debrisCompleted[d] = true
            d.AncestryChanged:Connect(function(_, parent)
                if not parent then debrisCompleted[d] = nil end
            end)

            task.wait(0.5)
        end
    end)
end

-- ============================================================
-- HERMIT FUNCTIONS — v3: Use proper HermitCrab API
-- ============================================================
local hermitClaimThread = nil
local hermitAutoClaim = false

local function claimHermit()
    local ok = pcall(function()
        Net.HermitCrab.queries.ClaimAllShells.invoke()
    end)
    if ok then Fluent:Notify({ Title = "Shells Auto", Content = "Hermit shells claimed!", Duration = 2 }) end
end

local function hermitClaimLoop()
    while hermitAutoClaim do
        claimHermit()
        task.wait(300)
    end
end

local selectedHermitUpgrades = {}
local hermitUpgradeThread = nil
local hermitAutoUpgrade = false

local hermitUpgradeNames = { "Luck", "Speed", "Space", "Weight" }
table.sort(hermitUpgradeNames)

local function doHermitUpgrades()
    for name, enabled in pairs(selectedHermitUpgrades) do
        if enabled then
            pcall(function()
                Net.HermitCrab.queries.UpgradeStat.invoke(name)
            end)
            task.wait(0.6)
        end
    end
end

local function hermitUpgradeLoop()
    while hermitAutoUpgrade do doHermitUpgrades(); task.wait(8) end
end

-- ============================================================
-- MISC FUNCTIONS
-- ============================================================
local DataReplicator = require(RS:WaitForChild("Modules"):WaitForChild("Communication"):WaitForChild("DataReplicator"))
local DR = DataReplicator.GetReplicator()

local questAutoClaim = false
local questClaimThread = nil

local function claimReadyQuests()
    local progress = nil
    pcall(function() progress = DR:Get({"DailyRequests", "Progress"}) end)
    if not progress then return end
    for island, quests in pairs(progress) do
        local config = nil
        pcall(function() config = require(RS.Modules.DailyRequests.Zones:WaitForChild(island)) end)
        if not config then continue end
        for index, questData in pairs(quests) do
            local goal = config[index] and config[index].Goal or 0
            local current = questData.Current or 0
            local claimed = questData.Claimed == true
            if current >= goal and not claimed then
                pcall(function()
                    Net.DailyRequests.queries.Claim.invoke({island = island, index = index})
                end)
                task.wait(0.1)
            end
        end
    end
end

local function questClaimLoop()
    while questAutoClaim do
        claimReadyQuests()
        task.wait(60)
    end
end

local sifterAutoCollect = false
local sifterCollectThread = nil

local function sifterCollectLoop()
    while sifterAutoCollect do
        pcall(function() RS:WaitForChild("ByteNetReliable"):FireServer(buffer.fromstring("\003\001\0001")) end)
        task.wait(60)
    end
end

local function storageUpgradeLoop()
    while autoStorageUpgrade do
        local ok, info = pcall(function()
            return Net.Storage.queries.GetUpgradeInfo.invoke()
        end)
        if ok and info and info.Cost and not info.MaxLevel then
            pcall(function() Net.Storage.queries.Upgrade.invoke() end)
        end
        task.wait(30)
    end
end

local antiAfkThread = nil

local function startAntiAfk()
    pcall(function()
        LP.Idled:Connect(function()
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new(math.random(0, 800), math.random(0, 600)))
            end)
        end)
    end)

    antiAfkThread = task.spawn(function()
        while task.wait(math.random(150, 240)) do
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new(math.random(0, 800), math.random(0, 600)))
            end)
            pcall(function()
                local Keys = { Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.Space }
                local Key = Keys[math.random(#Keys)]
                VIM:SendKeyEvent(true, Key, false, game)
                task.wait(math.random(5, 20) / 100)
                VIM:SendKeyEvent(false, Key, false, game)
            end)
            pcall(function()
                local humanoid = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.Health > 0 then humanoid.Jump = true end
            end)
        end
    end)
end
startAntiAfk()

-- ============================================================
-- AUTO FAVORITE
-- ============================================================
local ByteNetReliable = RS:WaitForChild("ByteNetReliable")

local function favoriteShell(item)
    local shellName = item:GetAttribute("Name") or item.Name
    pcall(function()
        Net.General.packets.FavouriteItem.send({ shellId = shellName, state = true })
    end)
end

local function startAutoFavorite()
    if autoFavoriteThread then task.cancel(autoFavoriteThread) end
    autoFavoriteProcessed = {}
    autoFavoriteThread = task.spawn(function()
        while autoFavoriteEnabled do
            local backpack = LP:FindFirstChild("Backpack")
            if not backpack then task.wait(1); continue end
            for _, tool in ipairs(backpack:GetChildren()) do
                if tool:IsA("Tool") and tool:GetAttribute("Type") == "Item" and not autoFavoriteProcessed[tool] then
                    autoFavoriteProcessed[tool] = true
                    if tool:GetAttribute("Favourite") then continue end
                    local shellName = tool:GetAttribute("Name") or tool.Name
                    local rarity = getShellRarity(shellName)
                    local shouldFav = false
                    if rarity and autoFavoriteRarities[rarity] then
                        shouldFav = true
                    end
                    if autoFavoriteShells[shellName] then
                        shouldFav = true
                    end
                    if shouldFav then
                        favoriteShell(tool)
                        Fluent:Notify({ Title = "Auto Favorite", Content = "Favorited: " .. shellName .. " (" .. (rarity or "?") .. ")", Duration = 2 })
                    end
                end
            end
            task.wait(0.5)
        end
    end)
end

-- ============================================================
-- AUTO VAULT DEPOSIT
-- ============================================================
local function startAutoVaultDeposit()
    if autoVaultDepositThread then task.cancel(autoVaultDepositThread) end
    autoVaultDepositProcessed = {}
    autoVaultDepositThread = task.spawn(function()
        while autoVaultDepositEnabled do
            local backpack = LP:FindFirstChild("Backpack")
            if not backpack then task.wait(1); continue end
            for _, tool in ipairs(backpack:GetChildren()) do
                if tool:IsA("Tool") and tool:GetAttribute("Type") == "Item" and not autoVaultDepositProcessed[tool] then
                    autoVaultDepositProcessed[tool] = true
                    local shellName = tool:GetAttribute("Name") or tool.Name
                    local rarity = getShellRarity(shellName)
                    local shouldDeposit = false
                    if rarity and autoVaultDepositRarities[rarity] then
                        shouldDeposit = true
                    end
                    if autoVaultDepositShells[shellName] then
                        shouldDeposit = true
                    end
                    if shouldDeposit then
                        local ok, res = pcall(function()
                            return Net.Vault.queries.Deposit.invoke(tool.Name)
                        end)
                        if ok and res and res.Success then
                            Fluent:Notify({ Title = "Auto Vault", Content = "Deposited: " .. shellName, Duration = 2 })
                        end
                    end
                end
            end
            task.wait(1)
        end
    end)
end

-- ============================================================
-- AUTO GIFT
-- ============================================================
local ShellCosts = {}
do
    local ShellData = require(RS.Modules.GameModules.Info.Shells)
    if ShellData and ShellData.Items then
        for _, shell in ipairs(ShellData.Items) do
            ShellCosts[shell.Name] = shell.Cost
        end
    end
end

local function getToolShellValue(tool)
    local name = tool:GetAttribute("Name") or tool.Name
    local weight = tool:GetAttribute("Weight") or 0
    local cost = ShellCosts[name] or 0
    return weight * cost
end

local function giftOneShell(backpack, targetPlayer, targetChar, humanoid)
    if autoGiftByValue then
        local bestTool = nil
        local bestValue = 0
        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") and tool:GetAttribute("Type") == "Item" then
                local shellName = tool:GetAttribute("Name") or tool.Name
                local rarity = getShellRarity(shellName)
                local shouldGift = false
                if rarity and autoGiftRarities[rarity] then shouldGift = true end
                if autoGiftShells[shellName] then shouldGift = true end
                if shouldGift then
                    local val = getToolShellValue(tool)
                    if val <= (autoGiftTargetValue - autoGiftedValue) and val > bestValue then
                        bestTool = tool
                        bestValue = val
                    end
                end
            end
        end
        if not bestTool then return false, 0 end
        humanoid:EquipTool(bestTool)
        task.wait(0.3)
        pcall(function()
            Net.General.packets.GiftItem.send({ otherPlr = targetChar.Name })
        end)
        autoGiftedCount = autoGiftedCount + 1
        autoGiftedValue = autoGiftedValue + bestValue
        Fluent:Notify({ Title = "Auto Gift", Content = string.format("#%d: %s [$%s] → %s", autoGiftedCount, bestTool:GetAttribute("Name"), bestValue, autoGiftTarget), Duration = 2 })
        return true, bestValue
    else
        local matchingTool = nil
        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") and tool:GetAttribute("Type") == "Item" then
                local shellName = tool:GetAttribute("Name") or tool.Name
                local rarity = getShellRarity(shellName)
                local shouldGift = false
                if rarity and autoGiftRarities[rarity] then shouldGift = true end
                if autoGiftShells[shellName] then shouldGift = true end
                if shouldGift then
                    matchingTool = tool
                    break
                end
            end
        end
        if not matchingTool then return false, 0 end
        humanoid:EquipTool(matchingTool)
        task.wait(0.3)
        pcall(function()
            Net.General.packets.GiftItem.send({ otherPlr = targetChar.Name })
        end)
        autoGiftedCount = autoGiftedCount + 1
        Fluent:Notify({ Title = "Auto Gift", Content = string.format("#%d: %s → %s", autoGiftedCount, matchingTool:GetAttribute("Name") or matchingTool.Name, autoGiftTarget), Duration = 2 })
        return true, 0
    end
end

local function startAutoGift()
    if autoGiftThread then task.cancel(autoGiftThread) end
    autoGiftedCount = 0
    autoGiftedValue = 0
    autoGiftThread = task.spawn(function()
        while autoGiftEnabled do
            if not autoGiftTarget then task.wait(1); continue end
            local targetPlayer = game.Players:FindFirstChild(autoGiftTarget)
            if not targetPlayer then task.wait(1); continue end
            local backpack = LP:FindFirstChild("Backpack")
            local character = LP.Character
            if not backpack or not character then task.wait(1); continue end
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if not humanoid then task.wait(1); continue end
            local targetChar = targetPlayer.Character
            if not targetChar or not targetChar:FindFirstChild("HumanoidRootPart") then task.wait(1); continue end
            local ok1, canGiftResult = pcall(function()
                return Net.General.queries.CanGiftItem.invoke({ targetUserId = tostring(targetPlayer.UserId) })
            end)
            if not ok1 or not canGiftResult or not canGiftResult.canGift then
                task.wait(2)
                continue
            end
            if autoGiftByValue then
                local totalGifted = 0
                while autoGiftEnabled and totalGifted < autoGiftTargetValue do
                    if not backpack or not character or not humanoid or not targetChar then break end
                    local ok, val = giftOneShell(backpack, targetPlayer, targetChar, humanoid)
                    if not ok then break end
                    totalGifted = totalGifted + val
                    task.wait(0.5)
                end
                Fluent:Notify({ Title = "Auto Gift", Content = string.format("Done! Total gifted: $%s", totalGifted), Duration = 3 })
                if autoGiftValueMode == "once" then
                    autoGiftEnabled = false
                    break
                end
            else
                giftOneShell(backpack, targetPlayer, targetChar, humanoid)
            end
            task.wait(1)
        end
    end)
end

local lightBoostEnabled = false
local lightBoostObjects = {}

local function applyLightBoost()
    lightBoostObjects = {}
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam")
            or v:IsA("Smoke") or v:IsA("Fire") or v:IsA("Sparkles")
            or v:IsA("Highlight") then
            table.insert(lightBoostObjects, { obj = v, prop = "Enabled", old = v.Enabled })
            v.Enabled = false
        elseif v:IsA("BillboardGui") or v:IsA("SurfaceGui") then
            table.insert(lightBoostObjects, { obj = v, prop = "Enabled", old = v.Enabled })
            v.Enabled = false
        elseif v:IsA("Explosion") then
            table.insert(lightBoostObjects, { obj = v, prop = "Visible", old = v.Visible })
            v.Visible = false
        end
    end
end

local function restoreLightBoost()
    for _, entry in ipairs(lightBoostObjects) do
        pcall(function() entry.obj[entry.prop] = entry.old end)
    end
    lightBoostObjects = {}
end

local fpsBoostEnabled = false
local fpsBoostObjects = {}

local function applyFpsBoost()
    fpsBoostObjects = {}
    settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    pcall(function() sethiddenproperty(settings().Rendering, "QualityLevel", 1) end)
    local Lighting = game:GetService("Lighting")
    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        Lighting.Brightness = 1
        Lighting.EnvironmentDiffuseScale = 0
        Lighting.EnvironmentSpecularScale = 0
        Lighting.ClockTime = 14
        Lighting.Technology = Enum.Technology.Compatibility
    end)
    for _, v in ipairs(Lighting:GetChildren()) do
        if v:IsA("BloomEffect") or v:IsA("BlurEffect") or v:IsA("SunRaysEffect")
            or v:IsA("ColorCorrectionEffect") or v:IsA("DepthOfFieldEffect") or v:IsA("Atmosphere") then
            table.insert(fpsBoostObjects, { obj = v, prop = "Enabled", old = v.Enabled })
            v.Enabled = false
        end
    end
    local Terrain = workspace:FindFirstChildOfClass("Terrain")
    if Terrain then
        pcall(function()
            Terrain.WaterWaveSize = 0; Terrain.WaterWaveSpeed = 0
            Terrain.WaterReflectance = 0; Terrain.WaterTransparency = 1
            Terrain.Decoration = false
        end)
    end
    for _, v in ipairs(game:GetDescendants()) do
        if v:IsA("BasePart") then
            table.insert(fpsBoostObjects, { obj = v, prop = "CastShadow", old = v.CastShadow })
            table.insert(fpsBoostObjects, { obj = v, prop = "Reflectance", old = v.Reflectance })
            table.insert(fpsBoostObjects, { obj = v, prop = "Material", old = v.Material })
            v.CastShadow = false; v.Reflectance = 0; v.Material = Enum.Material.SmoothPlastic
        elseif v:IsA("Decal") or v:IsA("Texture") then
            table.insert(fpsBoostObjects, { obj = v, prop = "Transparency", old = v.Transparency })
            v.Transparency = 1
        elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke")
            or v:IsA("Fire") or v:IsA("Sparkles") or v:IsA("Beam") or v:IsA("Highlight") then
            table.insert(fpsBoostObjects, { obj = v, prop = "Enabled", old = v.Enabled })
            v.Enabled = false
        elseif v:IsA("Explosion") then
            table.insert(fpsBoostObjects, { obj = v, prop = "Visible", old = v.Visible })
            v.Visible = false
        elseif v:IsA("PointLight") or v:IsA("SpotLight") or v:IsA("SurfaceLight") then
            table.insert(fpsBoostObjects, { obj = v, prop = "Enabled", old = v.Enabled })
            v.Enabled = false
        end
    end
end

local function restoreFpsBoost()
    for _, entry in ipairs(fpsBoostObjects) do
        pcall(function() entry.obj[entry.prop] = entry.old end)
    end
    fpsBoostObjects = {}
    pcall(function()
        game:GetService("Lighting").GlobalShadows = true
        game:GetService("Lighting").FogEnd = 100000
        game:GetService("Lighting").EnvironmentDiffuseScale = 1
        game:GetService("Lighting").EnvironmentSpecularScale = 1
    end)
    settings().Rendering.QualityLevel = Enum.QualityLevel.Level10
end

local disablePauseEnabled = false
local disablePauseThread = nil

local pauseScreenNames = { "PauseGui", "LoadingGui", "Cutscene", "BlackScreen", "LoadingScreen", "TransitionScreen" }

local function disablePauseLoop()
    while disablePauseEnabled do
        pcall(function()
            local playerGui = LP:FindFirstChildOfClass("PlayerGui")
            if playerGui then
                for _, gui in ipairs(playerGui:GetDescendants()) do
                    if gui:IsA("ScreenGui") then
                        for _, name in ipairs(pauseScreenNames) do
                            if gui.Name:find(name) then gui.Enabled = false end
                        end
                    end
                end
            end
            local humanoid = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.WalkSpeed == 0 then humanoid.WalkSpeed = 16 end
            local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if hrp and hrp.Anchored then hrp.Anchored = false end
        end)
        task.wait(1)
    end
end

local blackScreenEnabled = false
local blackScreenGui = nil

local function enableBlackScreen()
    if blackScreenGui then return end
    blackScreenGui = Instance.new("ScreenGui")
    blackScreenGui.Name = "QenturyBlackScreen"
    blackScreenGui.IgnoreGuiInset = true
    blackScreenGui.DisplayOrder = 9999
    blackScreenGui.ResetOnSpawn = false
    local frame = Instance.new("Frame", blackScreenGui)
    frame.Size = UDim2.fromScale(1, 1)
    frame.BackgroundColor3 = Color3.new(0, 0, 0)
    frame.BorderSizePixel = 0
    blackScreenGui.Parent = game:GetService("CoreGui")
    pcall(function() game:GetService("RunService"):Set3dRenderingEnabled(false) end)
end

local function disableBlackScreen()
    if blackScreenGui then blackScreenGui:Destroy(); blackScreenGui = nil end
    pcall(function() game:GetService("RunService"):Set3dRenderingEnabled(true) end)
end

-- ============================================================
-- FLUENT PLUS UI
-- ============================================================
local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/discoart/FluentPlus/refs/heads/main/Beta.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Qentury Hub", SubTitle = "Shells v4",
    Search = true, Icon = "shell",
    TabWidth = 160, Size = UDim2.fromOffset(580, 460),
    Acrylic = true, Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl,
    UserInfo = true, UserInfoTop = false,
    UserInfoTitle = LP.DisplayName,
    UserInfoSubtitle = "User",
    UserInfoSubtitleColor = Color3.fromRGB(71, 127, 252),
})

Fluent:CreateMinimizer({
    Icon = "shell", Size = UDim2.fromOffset(44, 44),
    Position = UDim2.new(0, 320, 0, 24),
    Acrylic = true, Corner = 10, Transparency = 1,
    Draggable = true, Visible = true,
})

task.spawn(function()
    local ok, thumb = pcall(function()
        return Players:GetUserThumbnailAsync(LP.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
    end)
    if ok and thumb then
        for _, gui in ipairs(game:GetService("CoreGui"):GetDescendants()) do
            if gui:IsA("ImageLabel") and gui.Name == "Icon" then
                local parent = gui.Parent
                if parent and parent.Name == "FloatingButton" then
                    gui.Image = thumb
                    break
                end
            end
        end
    end
end)

local Options = Fluent.Options

local Tabs = {
    Farm     = Window:AddTab({ Title = "Farm", Icon = "shovel" }),
    Favorite = Window:AddTab({ Title = "Favorite", Icon = "heart" }),
    Vault    = Window:AddTab({ Title = "Vault", Icon = "archive" }),
    Gift     = Window:AddTab({ Title = "Gift", Icon = "gift" }),
    Travel   = Window:AddTab({ Title = "Travel & Boat", Icon = "plane" }),
    Hermit   = Window:AddTab({ Title = "Hermit", Icon = "anchor" }),
    Merchant = Window:AddTab({ Title = "Travel Merchant", Icon = "shopping-cart" }),
    Shop     = Window:AddTab({ Title = "Tool Shop", Icon = "wrench" }),
    Trait    = Window:AddTab({ Title = "Trait Roll", Icon = "dice-5" }),
    Misc     = Window:AddTab({ Title = "Misc", Icon = "cpu" }),
    Webhook  = Window:AddTab({ Title = "Webhook", Icon = "bell" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}

-- ============================================================
-- FARM TAB
-- ============================================================
Tabs.Farm:AddSection("Automation", "zap")

Tabs.Farm:AddToggle("AutoDig", { Title = "Auto Dig", Default = false }):OnChanged(function(state)
    if state and mythicOnly then
        mythicOnly = false
        Fluent:Notify({ Title = "Shells Auto", Content = "Mythic Only disabled (Auto Dig enabled)", Duration = 2 })
    end
    autoDig = state
    if state then task.spawn(digLoop) end
end)

Tabs.Farm:AddToggle("MythicOnly", { Title = "Mythic Only", Description = "Only dig when surge bar appears", Default = false }):OnChanged(function(state)
    if state and autoDig then
        autoDig = false
        Fluent:Notify({ Title = "Shells Auto", Content = "Auto Dig disabled (Mythic Only enabled)", Duration = 2 })
    end
    mythicOnly = state
    if state then task.spawn(digLoop); Fluent:Notify({ Title = "Shells Auto", Content = "Mythic Only started", Duration = 2 })
    else Fluent:Notify({ Title = "Shells Auto", Content = "Mythic Only stopped", Duration = 2 }) end
end)

Tabs.Farm:AddToggle("AutoLostCity", { Title = "Auto Lost City", Default = false }):OnChanged(function(state)
    if state then startLostCityMonitor()
    else
        if lostCityThread then task.cancel(lostCityThread); lostCityThread = nil end
        if lostCityLockThread then task.cancel(lostCityLockThread); lostCityLockThread = nil end
        lostCityActive = false
    end
end)

Tabs.Farm:AddToggle("AutoDebris", { Title = "Auto Debris", Default = false }):OnChanged(function(state)
    if state then startAutoDebris()
    else
        if debrisThread then task.cancel(debrisThread); debrisThread = nil end
        debrisActive = false
    end
end)

local function getBackpackValue()
    local total = 0
    local backpack = LP:FindFirstChild("Backpack")
    if not backpack then return 0 end
    for _, item in ipairs(backpack:GetChildren()) do
        if item:IsA("Tool") then
            local shellName = item:GetAttribute("Name") or item.Name
            local weight = item:GetAttribute("Weight") or 1
            local modifier = item:GetAttribute("Modifier")
            total += getShellValue(shellName, weight, modifier)
        end
    end
    return total
end

Tabs.Farm:AddSection("Inventory", "backpack")
local InventoryParagraph = Tabs.Farm:AddParagraph({ Title = "Inventory", Content = "Loading..." })
local ValueParagraph = Tabs.Farm:AddParagraph({ Title = "Total Value", Content = "Loading..." })

task.spawn(function()
    while true do
        local info = getStorageInfo()
        InventoryParagraph:SetDesc(info.Current .. " / " .. info.Limit)
        local ok, val = pcall(function() return Net.Merchant.queries.AllWorth.invoke() end)
        if ok and val and val > 0 then
            ValueParagraph:SetDesc(string.format("%d coins", val))
        else
            ValueParagraph:SetDesc(string.format("%d coins (local)", getBackpackValue()))
        end
        task.wait(5)
    end
end)

Tabs.Farm:AddSection("Sell", "coins")

Tabs.Farm:AddToggle("AutoSell", { Title = "Auto Sell", Default = false }):OnChanged(function(state)
    autoSell = state
    if state then task.spawn(sellWatcher); Fluent:Notify({ Title = "Shells Auto", Content = "Auto Sell enabled", Duration = 2 }) end
end)

Tabs.Farm:AddSlider("SellCount", { Title = "Sell when items >=", Description = "Auto sell threshold", Default = 100, Min = 0, Max = 5000, Rounding = 1 }):OnChanged(function(value) sellCount = math.floor(value) end)

Tabs.Farm:AddButton({ Title = "Sell Now", Description = "Sell all items immediately", Callback = function() task.spawn(sellAll) end })

Tabs.Farm:AddSection("Misc", "list")

Tabs.Farm:AddToggle("AutoDailyQuest", { Title = "Auto Claim Daily Quest", Default = false }):OnChanged(function(state)
    questAutoClaim = state
    if state then questClaimThread = task.spawn(questClaimLoop); Fluent:Notify({ Title = "Shells Auto", Content = "Auto Daily Quest started", Duration = 2 })
    else questClaimThread = nil; Fluent:Notify({ Title = "Shells Auto", Content = "Auto Daily Quest stopped", Duration = 2 }) end
end)

Tabs.Farm:AddToggle("AutoCollectSifter", { Title = "Auto Collect Sifter", Default = false }):OnChanged(function(state)
    sifterAutoCollect = state
    if state then sifterCollectThread = task.spawn(sifterCollectLoop); Fluent:Notify({ Title = "Shells Auto", Content = "Auto Collect Sifter started", Duration = 2 })
    else sifterCollectThread = nil; Fluent:Notify({ Title = "Shells Auto", Content = "Auto Collect Sifter stopped", Duration = 2 }) end
end)

Tabs.Farm:AddToggle("AutoStorageUpgrade", { Title = "Auto Storage Upgrade", Description = "Auto upgrade storage when affordable", Default = false }):OnChanged(function(state)
    autoStorageUpgrade = state
    if state then storageUpgradeThread = task.spawn(storageUpgradeLoop); Fluent:Notify({ Title = "Shells Auto", Content = "Auto Storage Upgrade started", Duration = 2 })
    elseif storageUpgradeThread then task.cancel(storageUpgradeThread); storageUpgradeThread = nil; Fluent:Notify({ Title = "Shells Auto", Content = "Auto Storage Upgrade stopped", Duration = 2 }) end
end)

-- ============================================================
-- FAVORITE TAB
-- ============================================================
local function setupFavoriteTab()
Tabs.Favorite:AddSection("Auto Favorite", "heart")

Tabs.Favorite:AddDropdown("FavRarities", {
    Title = "Favorite by Rarity",
    Description = "Auto-favorite shells matching these rarities",
    Values = RARITY_LIST,
    Multi = true,
    Default = {},
}):OnChanged(function(selected)
    autoFavoriteRarities = selected or {}
end)

Tabs.Favorite:AddDropdown("FavShells", {
    Title = "Favorite by Shell Name",
    Description = "Auto-favorite these specific shells",
    Values = ShellNameList,
    Multi = true,
    Default = {},
    Search = true,
}):OnChanged(function(selected)
    autoFavoriteShells = selected or {}
end)

Tabs.Favorite:AddToggle("AutoFavorite", { Title = "Enable Auto Favorite", Description = "Auto-favorite shells matching above filters", Default = false }):OnChanged(function(state)
    autoFavoriteEnabled = state
    if state then startAutoFavorite(); Fluent:Notify({ Title = "Auto Favorite", Content = "Auto Favorite enabled", Duration = 2 })
    else
        if autoFavoriteThread then task.cancel(autoFavoriteThread); autoFavoriteThread = nil end
        Fluent:Notify({ Title = "Auto Favorite", Content = "Auto Favorite disabled", Duration = 2 })
    end
end)

Tabs.Favorite:AddSection("Status", "info")
local FavStatusParagraph = Tabs.Favorite:AddParagraph({ Title = "Favorited Count", Content = "0" })

task.spawn(function()
    while true do
        local count = 0
        local backpack = LP:FindFirstChild("Backpack")
        if backpack then
            for _, tool in ipairs(backpack:GetChildren()) do
                if tool:IsA("Tool") and tool:GetAttribute("Type") == "Item" and tool:GetAttribute("Favourite") then
                    count = count + 1
                end
            end
        end
        FavStatusParagraph:SetDesc(tostring(count))
        task.wait(3)
    end
end)
end
setupFavoriteTab()

-- ============================================================
-- VAULT TAB
-- ============================================================
local function setupVaultTab()
Tabs.Vault:AddSection("Deposit", "download")

Tabs.Vault:AddDropdown("VaultDepositRarities", {
    Title = "Deposit by Rarity",
    Description = "Auto-deposit shells matching these rarities",
    Values = RARITY_LIST,
    Multi = true,
    Default = {},
}):OnChanged(function(selected)
    autoVaultDepositRarities = selected or {}
end)

Tabs.Vault:AddDropdown("VaultDepositShells", {
    Title = "Deposit by Shell Name",
    Description = "Auto-deposit these specific shells",
    Values = ShellNameList,
    Multi = true,
    Default = {},
    Search = true,
}):OnChanged(function(selected)
    autoVaultDepositShells = selected or {}
end)

Tabs.Vault:AddToggle("AutoVaultDeposit", { Title = "Enable Auto Deposit", Description = "Auto-deposit shells matching above filters", Default = false }):OnChanged(function(state)
    autoVaultDepositEnabled = state
    if state then startAutoVaultDeposit(); Fluent:Notify({ Title = "Auto Vault", Content = "Auto Deposit enabled", Duration = 2 })
    else
        if autoVaultDepositThread then task.cancel(autoVaultDepositThread); autoVaultDepositThread = nil end
        Fluent:Notify({ Title = "Auto Vault", Content = "Auto Deposit disabled", Duration = 2 })
    end
end)

Tabs.Vault:AddSection("Withdraw", "upload")

local vaultWithdrawRarities = {}
local vaultWithdrawShells = {}

Tabs.Vault:AddDropdown("VaultWithdrawRarities", {
    Title = "Withdraw by Rarity",
    Description = "Withdraw shells matching these rarities",
    Values = RARITY_LIST,
    Multi = true,
    Default = {},
}):OnChanged(function(selected)
    vaultWithdrawRarities = selected or {}
end)

Tabs.Vault:AddDropdown("VaultWithdrawShells", {
    Title = "Withdraw by Shell Name",
    Description = "Withdraw these specific shells",
    Values = ShellNameList,
    Multi = true,
    Default = {},
    Search = true,
}):OnChanged(function(selected)
    vaultWithdrawShells = selected or {}
end)

Tabs.Vault:AddButton({
    Title = "Withdraw Selected",
    Description = "Withdraw matching shells from vault to backpack",
    Callback = function()
        task.spawn(function()
            local DataReplicator = require(RS.Modules.Communication.DataReplicator)
            local DR = DataReplicator.GetReplicator()
            local vaultData = DR:Get({"Vault"}) or {}
            if #vaultData == 0 then
                Fluent:Notify({ Title = "Vault", Content = "Vault is empty", Duration = 2 })
                return
            end
            local withdrawn = 0
            for _, shellId in ipairs(vaultData) do
                local parts = string.split(shellId, "_")
                local shellName = parts[1] or shellId
                local rarity = getShellRarity(shellName)
                local shouldWithdraw = false
                if rarity and vaultWithdrawRarities[rarity] then
                    shouldWithdraw = true
                end
                if vaultWithdrawShells[shellName] then
                    shouldWithdraw = true
                end
                if shouldWithdraw then
                    local ok, res = pcall(function()
                        return Net.Vault.queries.Withdraw.invoke(shellId)
                    end)
                    if ok and res and res.Success then
                        withdrawn = withdrawn + 1
                        Fluent:Notify({ Title = "Vault", Content = "Withdrawn: " .. shellName, Duration = 2 })
                    end
                    task.wait(0.3)
                end
            end
            Fluent:Notify({ Title = "Vault", Content = "Withdrawn " .. withdrawn .. " shells", Duration = 3 })
        end)
    end
})

Tabs.Vault:AddSection("Status", "info")
local VaultStatusParagraph = Tabs.Vault:AddParagraph({ Title = "Vault Capacity", Content = "Loading..." })

task.spawn(function()
    local DataReplicator = require(RS.Modules.Communication.DataReplicator)
    local DR = DataReplicator.GetReplicator()
    while true do
        local vaultData = DR:Get({"Vault"}) or {}
        local info = Net.Vault.queries.GetInfo.invoke()
        if info then
            VaultStatusParagraph:SetDesc(info.Current .. "/" .. info.Limit)
        else
            VaultStatusParagraph:SetDesc(#vaultData .. " shells")
        end
        task.wait(5)
    end
end)
end
setupVaultTab()

-- ============================================================
-- GIFT TAB
-- ============================================================
local function setupGiftTab()
Tabs.Gift:AddSection("Target", "user")

local playerNames = {}
for _, p in ipairs(game.Players:GetPlayers()) do
    if p ~= LP then table.insert(playerNames, p.Name) end
end
table.sort(playerNames)

game.Players.PlayerAdded:Connect(function(p)
    table.insert(playerNames, p.Name)
    table.sort(playerNames)
end)
game.Players.PlayerRemoving:Connect(function(p)
    for i, name in ipairs(playerNames) do
        if name == p.Name then table.remove(playerNames, i); break end
    end
end)

Tabs.Gift:AddDropdown("GiftTarget", {
    Title = "Target Player",
    Description = "Player to gift shells to",
    Values = playerNames,
    Default = nil,
}):OnChanged(function(selected)
    autoGiftTarget = selected
end)

Tabs.Gift:AddSection("Filters", "filter")

Tabs.Gift:AddDropdown("GiftRarities", {
    Title = "Gift by Rarity",
    Description = "Gift shells matching these rarities",
    Values = RARITY_LIST,
    Multi = true,
    Default = {},
}):OnChanged(function(selected)
    autoGiftRarities = selected or {}
end)

Tabs.Gift:AddDropdown("GiftShells", {
    Title = "Gift by Shell Name",
    Description = "Gift these specific shells",
    Values = ShellNameList,
    Multi = true,
    Default = {},
    Search = true,
}):OnChanged(function(selected)
    autoGiftShells = selected or {}
end)

Tabs.Gift:AddSection("Gift by Value", "dollar-sign")

Tabs.Gift:AddToggle("GiftByValue", { Title = "Gift by Value", Description = "Gift shells until total value reaches target", Default = false }):OnChanged(function(state)
    autoGiftByValue = state
end)

Tabs.Gift:AddInput("GiftTargetValue", {
    Title = "Target Value ($)",
    Description = "Total value to gift (e.g. 100000)",
    Default = "100000",
    Placeholder = "100000",
}):OnChanged(function(value)
    autoGiftTargetValue = tonumber(value) or 0
end)

Tabs.Gift:AddDropdown("GiftValueMode", {
    Title = "Value Mode",
    Description = "Once = stop after reaching target, Loop = repeat",
    Values = { "once", "loop" },
    Default = "once",
}):OnChanged(function(selected)
    autoGiftValueMode = selected
end)

Tabs.Gift:AddSection("Auto Gift", "zap")

Tabs.Gift:AddToggle("AutoGift", { Title = "Enable Auto Gift", Description = "Auto-gift matching shells to target player", Default = false }):OnChanged(function(state)
    autoGiftEnabled = state
    if state then startAutoGift(); Fluent:Notify({ Title = "Auto Gift", Content = "Auto Gift enabled", Duration = 2 })
    else
        if autoGiftThread then task.cancel(autoGiftThread); autoGiftThread = nil end
        Fluent:Notify({ Title = "Auto Gift", Content = "Auto Gift disabled", Duration = 2 })
    end
end)

Tabs.Gift:AddSection("Status", "info")
local GiftStatusParagraph = Tabs.Gift:AddParagraph({ Title = "Gift Status", Content = "Loading..." })

task.spawn(function()
    while true do
        local backpack = LP:FindFirstChild("Backpack")
        if backpack then
            local matching = 0
            local totalValue = 0
            for _, tool in ipairs(backpack:GetChildren()) do
                if tool:IsA("Tool") and tool:GetAttribute("Type") == "Item" then
                    local shellName = tool:GetAttribute("Name") or tool.Name
                    local rarity = getShellRarity(shellName)
                    if autoGiftRarities[rarity] or autoGiftShells[shellName] then
                        matching = matching + 1
                        totalValue = totalValue + getToolShellValue(tool)
                    end
                end
            end
            local progress = ""
            local cnt = autoGiftedCount or 0
            local val = autoGiftedValue or 0
            local tgt = autoGiftTargetValue or 0
            if autoGiftByValue and tgt > 0 then
                progress = string.format("\nGifted: %d shells ($%d / $%d)", cnt, val, tgt)
            else
                progress = string.format("\nGifted: %d shells", cnt)
            end
            GiftStatusParagraph:SetDesc(string.format("Matching: %d shells ($%d) | To: %s%s", matching, totalValue, autoGiftTarget or "None", progress))
        end
        task.wait(3)
    end
end)
end
setupGiftTab()

-- ============================================================
-- TRAVEL & BOAT TAB
-- ============================================================
Tabs.Travel:AddSection("Destinations", "map-pin")

local islandNames = {}
for name in pairs(TeleportLocations.Islands) do table.insert(islandNames, name) end
table.sort(islandNames)

local currentDestName = islandNames[1]
local destPos = TeleportLocations.Islands[currentDestName]

Tabs.Travel:AddDropdown("TPDest", { Title = "Destination", Values = islandNames, Default = currentDestName, Search = true }):OnChanged(function(v) currentDestName = v; destPos = TeleportLocations.Islands[v] end)

Tabs.Travel:AddButton({
    Title = "Teleport Now", Description = "Teleport to selected destination",
    Callback = function()
        if destPos then tpTo(destPos); Fluent:Notify({ Title = "Shells Auto", Content = "Teleported to " .. currentDestName, Duration = 2 })
        else Fluent:Notify({ Title = "Shells Auto", Content = "Select a destination first", Duration = 3 }) end
    end,
})

Tabs.Travel:AddButton({
    Title = "Frostveil Ngumpet", Description = "Teleport ke Frostveil Ngumpet",
    Callback = function() tpTo(Vector3.new(3812.801, 27.747, -1246.018)); Fluent:Notify({ Title = "Shells Auto", Content = "Teleported to Frostveil Ngumpet", Duration = 2 }) end,
})

Tabs.Travel:AddSection("Boat", "ship")

pcall(function()
local BoatUI = require(LP.PlayerScripts.Client.Boat.BoatUI)

Tabs.Travel:AddButton({
    Title = "Open Boat Spawn", Description = "Spawn near shipwright",
    Callback = function()
        pcall(function()
            BoatUI.SpawnAnywhere = false
            BoatUI.PopInAnim()
        end)
    end,
})
end) -- pcall Boat

-- ============================================================
-- HERMIT TAB
-- ============================================================
Tabs.Hermit:AddSection("Hermit Shells", "anchor")

Tabs.Hermit:AddButton({ Title = "Claim All Now", Description = "Claim hermit shells immediately", Callback = function() task.spawn(claimHermit) end })

Tabs.Hermit:AddToggle("AutoHermitClaim", { Title = "Auto Claim", Default = false }):OnChanged(function(state)
    hermitAutoClaim = state
    if state then hermitClaimThread = task.spawn(hermitClaimLoop)
    elseif hermitClaimThread then task.cancel(hermitClaimThread); hermitClaimThread = nil end
end)

Tabs.Hermit:AddSection("Upgrades", "arrow-up")

Tabs.Hermit:AddDropdown("HermitUpgrades", { Title = "Upgrades", Values = hermitUpgradeNames, Multi = true, Default = {} }):OnChanged(function(selected) selectedHermitUpgrades = selected or {} end)

Tabs.Hermit:AddToggle("AutoHermitUpgrade", { Title = "Auto Upgrade", Default = false }):OnChanged(function(state)
    hermitAutoUpgrade = state
    if state then hermitUpgradeThread = task.spawn(hermitUpgradeLoop)
    elseif hermitUpgradeThread then task.cancel(hermitUpgradeThread); hermitUpgradeThread = nil end
end)

-- ============================================================
-- MERCHANT FUNCTIONS — v3: Use Stock API + GetShop
-- ============================================================
local merchantItems = {
    "Starfish Charm", "Sea Glass Charm", "Pebble Charm",
    "Coral Charm", "Prism Charm", "Driftwood Charm",
    "Moonstone Charm", "Crystal Charm", "Tide Charm",
    "Abyssal Charm", "Void Charm", "Leviathan Charm",
    "Tidal Charm", "Eclipse Charm", "Colossus Charm",
}

local merchantAutoBuy = false
local merchantNotify = false
local webhookMerchantNotify = false
local merchantThread = nil
local merchantShopData = nil
local merchantStockListener = nil

local MerchantRef = workspace:WaitForChild("TravellingMerchant")
local CurrentZone = MerchantRef:WaitForChild("MerchantModel"):WaitForChild("CurrentZone")
local TimerObject = MerchantRef:WaitForChild("MerchantModel"):WaitForChild("Sign"):WaitForChild("GUI"):WaitForChild("Timer")

local function parseMerchantShopData()
    local ok, json = pcall(function()
        return Net.TravellingMerchant.queries.GetShop.invoke()
    end)
    if not ok or not json then return nil end
    local parsed = pcall(function()
        merchantShopData = HttpService:JSONDecode(json)
    end)
    if not parsed then merchantShopData = nil end
    return merchantShopData
end

local function getMerchantStockFromAPI(itemName)
    if not merchantShopData then parseMerchantShopData() end
    if not merchantShopData then return -1 end
    if merchantShopData.stock and merchantShopData.stock[itemName] ~= nil then
        return merchantShopData.stock[itemName]
    end
    return -1
end

local function getMerchantStockFromGUI(itemName)
    local pgui = LP:FindFirstChild("PlayerGui")
    if not pgui then return -1 end
    local gui = pgui:FindFirstChild("TravellingMerchant")
    if not gui then return -1 end
    local scroll = gui:FindFirstChild("RuntimeTravel", true)
    if not scroll then return -1 end
    scroll = scroll:FindFirstChild("ScrollingFrame", true)
    if not scroll then return -1 end
    local frame = scroll:FindFirstChild(itemName)
    if not frame then return 0 end
    local holder = frame:FindFirstChild("TxtHolder")
    if not holder then return 0 end
    for _, obj in ipairs(holder:GetChildren()) do
        if obj:IsA("TextLabel") then
            local stock = obj.Text:match("^x(%d+)%s+Stock$")
            if stock then return tonumber(stock) end
        end
    end
    return 0
end

local function getItemStock(itemName)
    local stock = getMerchantStockFromAPI(itemName)
    if stock >= 0 then return stock end
    return getMerchantStockFromGUI(itemName)
end

local function buySelectedItems()
    local selected = Options.AutoMerchantItems and Options.AutoMerchantItems.Value or {}
    local purchases = {}
    for _, itemName in ipairs(merchantItems) do
        if selected[itemName] then
            local stock = getItemStock(itemName)
            if stock > 0 then
                local ok, result = pcall(function()
                    return Net.TravellingMerchant.queries.BuyItem.invoke(itemName)
                end)
                if ok and result and result.success then
                    purchases[itemName] = (purchases[itemName] or 0) + 1
                end
            end
            task.wait(0.3)
        end
    end
    return purchases
end

local function waitForMerchantGUI()
    for _ = 1, 30 do
        local pgui = LP:FindFirstChild("PlayerGui")
        if pgui and pgui:FindFirstChild("TravellingMerchant") then
            local gui = pgui.TravellingMerchant
            local scroll = gui:FindFirstChild("RuntimeTravel", true)
            if scroll then
                local sf = scroll:FindFirstChild("ScrollingFrame", true)
                if sf and #sf:GetChildren() > 0 then return true end
            end
        end
        task.wait(1)
    end
    return false
end

local function buyUntilDone()
    local totalPurchases = {}
    repeat
        local purchases = buySelectedItems()
        local boughtAny = false
        for name, qty in pairs(purchases) do
            totalPurchases[name] = (totalPurchases[name] or 0) + qty
            boughtAny = true
        end
        if boughtAny then task.wait(1) end
    until not boughtAny
    return totalPurchases
end

local function sendMerchantSummary(purchases)
    if not webhookMerchantNotify or webhookUrl == "" then return end
    local lines = {}
    local totalCost = 0
    local totalItems = 0
    for _, itemName in ipairs(merchantItems) do
        local qty = purchases[itemName]
        if qty and qty > 0 then
            local price = MerchantPrices[itemName] or 0
            local cost = price * qty
            totalCost = totalCost + cost
            totalItems = totalItems + qty
            table.insert(lines, string.format("**%s** x%d — %d coins", itemName, qty, cost))
        end
    end
    if #lines == 0 then return end
    local desc = table.concat(lines, "\n") .. string.format("\n\n**Total: %d items | %d coins**", totalItems, totalCost)
    local ok = sendDiscordWebhook(webhookUrl, {
        embeds = {{
            title = "Travel Merchant Purchase Summary",
            color = 0x00aaff,
            description = desc,
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }}
    })
    if not ok then
        warn("[Webhook] Merchant summary failed")
        Fluent:Notify({ Title = "Webhook", Content = "Merchant summary failed", Duration = 3 })
    end
end

local merchantWasActive = false
local merchantInitialStock = {}
local merchantSummarySent = false

local function saveInitialStock()
    merchantInitialStock = {}
    local selected = Options.AutoMerchantItems and Options.AutoMerchantItems.Value or {}
    for _, itemName in ipairs(merchantItems) do
        if selected[itemName] then
            merchantInitialStock[itemName] = getItemStock(itemName)
        end
    end
end

local function allSelectedItemsSoldOut()
    local selected = Options.AutoMerchantItems and Options.AutoMerchantItems.Value or {}
    for _, itemName in ipairs(merchantItems) do
        if selected[itemName] then
            if getItemStock(itemName) > 0 then return false end
        end
    end
    return true
end

local function buildPurchaseSummary()
    local purchases = {}
    for itemName, startStock in pairs(merchantInitialStock) do
        local current = getItemStock(itemName)
        if current >= 0 then
            local bought = math.max(startStock - current, 0)
            if bought > 0 then purchases[itemName] = bought end
        end
    end
    return purchases
end

local function startMerchantStockListener()
    if merchantStockListener then merchantStockListener:Disconnect() end
    merchantStockListener = nil
    local ok, _ = pcall(function()
        merchantStockListener = Net.TravellingMerchant.packets.StockUpdate.listen(function(payload)
            local parsed = pcall(function()
                merchantShopData = HttpService:JSONDecode(payload)
            end)
            if parsed then
                print("[Merchant] Stock updated via API")
            end
        end)
    end)
    if not ok then
        warn("[Merchant] StockUpdate listener not available, using polling")
    end
end

local function stopMerchantStockListener()
    if merchantStockListener then merchantStockListener:Disconnect(); merchantStockListener = nil end
end

local function merchantMonitorLoop()
    while merchantAutoBuy or merchantNotify or webhookMerchantNotify do
        local isActive = CurrentZone.Value ~= nil

        if isActive and not merchantWasActive then
            merchantSummarySent = false
            merchantShopData = nil
            merchantInitialStock = {}
            parseMerchantShopData()
            startMerchantStockListener()
            if merchantNotify then
                Fluent:Notify({ Title = "Travel Merchant", Content = "Merchant is now active! Location: " .. (CurrentZone.Value and CurrentZone.Value.Name or "Unknown"), Duration = 5 })
            end
            if (merchantAutoBuy or webhookMerchantNotify) and waitForMerchantGUI() then
                saveInitialStock()
            end
        end

        if isActive and merchantAutoBuy then
            parseMerchantShopData()
            buyUntilDone()
            if webhookMerchantNotify and not merchantSummarySent and allSelectedItemsSoldOut() then
                merchantSummarySent = true
                local purchases = buildPurchaseSummary()
                sendMerchantSummary(purchases)
            end
            task.wait(3)
        end

        if not isActive and merchantWasActive and webhookMerchantNotify and not merchantSummarySent then
            merchantSummarySent = true
            local purchases = buildPurchaseSummary()
            sendMerchantSummary(purchases)
        end

        merchantWasActive = isActive
        task.wait(1)
    end
end

-- ============================================================
-- MERCHANT TAB
-- ============================================================
local function setupMerchantTab()
Tabs.Merchant:AddSection("Status", "info")
local MerchantStatusParagraph = Tabs.Merchant:AddParagraph({ Title = "Status", Content = "Checking..." })
local MerchantLocationParagraph = Tabs.Merchant:AddParagraph({ Title = "Location", Content = "Unknown" })
local MerchantTimerParagraph = Tabs.Merchant:AddParagraph({ Title = "Leaves In", Content = "--:--" })

local function updateMerchantStatus()
    local active = CurrentZone.Value ~= nil
    MerchantStatusParagraph:SetDesc(active and "Active" or "Inactive")
    MerchantLocationParagraph:SetDesc(active and (CurrentZone.Value and CurrentZone.Value.Name or "Unknown") or "Unknown")
end

local function updateMerchantTimer()
    local t = TimerObject.Text:match("%d+:%d+")
    MerchantTimerParagraph:SetDesc(t or "--:--")
end

updateMerchantStatus()
updateMerchantTimer()
CurrentZone:GetPropertyChangedSignal("Value"):Connect(updateMerchantStatus)
TimerObject:GetPropertyChangedSignal("Text"):Connect(updateMerchantTimer)

local merchantGuiReady = false
local function ensureMerchantGui()
    if merchantGuiReady then return true end
    local ok, mod = pcall(function()
        return require(LP.PlayerScripts.Client.TravellingMerchant.TravellingMerchantClient)
    end)
    if ok and mod and mod.Start then
        pcall(mod.Start)
    end
    task.wait(0.5)
    merchantGuiReady = true
    return true
end

local function openMerchantGui()
    ensureMerchantGui()
    local gui = LP.PlayerGui:FindFirstChild("TravellingMerchant")
    local runtime = gui and gui:FindFirstChild("RuntimeTravel")
    local scale = runtime and runtime:FindFirstChildOfClass("UIScale")
    if runtime then
        runtime.Visible = true
        if scale then scale.Scale = 1 end
        parseMerchantShopData()
        Fluent:Notify({ Title = "Travel Merchant", Content = "Shop opened", Duration = 2 })
    else
        Fluent:Notify({ Title = "Travel Merchant", Content = "Merchant not available", Duration = 3 })
    end
end

local function closeMerchantGui()
    local gui = LP.PlayerGui:FindFirstChild("TravellingMerchant")
    local runtime = gui and gui:FindFirstChild("RuntimeTravel")
    local scale = runtime and runtime:FindFirstChildOfClass("UIScale")
    if runtime then
        if scale then scale.Scale = 0 end
        runtime.Visible = false
    end
end

local ShopSection = Tabs.Merchant:AddSection("Shop", "store")

Tabs.Merchant:AddButton({ Title = "Open Shop", Description = "Open merchant purchase window", Callback = function() task.spawn(openMerchantGui) end })
Tabs.Merchant:AddButton({ Title = "Close Shop", Description = "Close merchant purchase window", Callback = function() closeMerchantGui() end })

Tabs.Merchant:AddSection("Auto Buy", "shopping-cart")

Tabs.Merchant:AddDropdown("AutoMerchantItems", {
    Title = "Select Items",
    Values = merchantItems,
    Multi = true,
    Default = {},
}):OnChanged(function() end)

Tabs.Merchant:AddToggle("AutoMerchant", { Title = "Auto Buy When Active", Default = false }):OnChanged(function(state)
    merchantAutoBuy = state
    if state then
        if not merchantThread then merchantThread = task.spawn(merchantMonitorLoop) end
    else
        if not merchantAutoBuy and not merchantNotify and not webhookMerchantNotify and merchantThread then
            task.cancel(merchantThread); merchantThread = nil
        end
    end
end)

Tabs.Merchant:AddToggle("MerchantNotify", { Title = "Notify On Spawn", Default = false }):OnChanged(function(state)
    merchantNotify = state
    if state then
        if not merchantThread then merchantThread = task.spawn(merchantMonitorLoop) end
    else
        if not merchantAutoBuy and not merchantNotify and not webhookMerchantNotify and merchantThread then
            task.cancel(merchantThread); merchantThread = nil
        end
    end
end)
end
setupMerchantTab()

-- ============================================================
-- SHOP TAB — Sifter & Tideclaw
-- ============================================================
local function setupShopTab()
local ToolCatalogueModule2 = RS:WaitForChild("Modules"):WaitForChild("GameModules"):WaitForChild("Info"):WaitForChild("ToolCatalogue")
local ToolCatalogueData = requireWithRetry(ToolCatalogueModule2, "ToolCatalogue")

local shopItems = {}
if ToolCatalogueData then
    for name, data in pairs(ToolCatalogueData) do
        if type(data) == "table" and data.type == "money" and data.price and data.price > 0 then
            if name:find("Sifter") or name:find("Tideclaw") or name:find("Sceptre") or name:find("Sunspace") then
                table.insert(shopItems, { name = name, price = data.price })
            end
        end
    end
end
table.sort(shopItems, function(a, b) return a.price < b.price end)

local function getShopItemNames()
    local names = {}
    for _, item in ipairs(shopItems) do
        table.insert(names, item.name)
    end
    return names
end

local function getShopItemInfo(name)
    for _, item in ipairs(shopItems) do
        if item.name == name then return item end
    end
    return nil
end

local function formatPriceLong(price)
    return tostring(price):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
end

Tabs.Shop:AddSection("Equipment Shop", "store")

local ShopNameParagraph = Tabs.Shop:AddParagraph({ Title = "Select an item", Content = "—" })
local ShopPriceParagraph = Tabs.Shop:AddParagraph({ Title = "Price", Content = "—" })

local ShopItemDropdown = Tabs.Shop:AddDropdown("ShopItem", {
    Title = "Item",
    Values = getShopItemNames(),
    Default = nil,
    Search = true,
})

ShopItemDropdown:OnChanged(function(v)
    if v then
        local info = getShopItemInfo(v)
        if info then
            ShopNameParagraph:SetDesc(info.name)
            ShopPriceParagraph:SetDesc(formatPriceLong(info.price) .. " coins")
        end
    else
        ShopNameParagraph:SetDesc("—")
        ShopPriceParagraph:SetDesc("—")
    end
end)

Tabs.Shop:AddButton({
    Title = "Buy",
    Description = "Purchase selected item",
    Callback = function()
        local selected = Options.ShopItem and Options.ShopItem.Value
        if not selected then
            Fluent:Notify({ Title = "Shop", Content = "Select an item first", Duration = 3 })
            return
        end
        task.spawn(function()
            local ok, result = pcall(function()
                return Net.Equipment.queries.Buy.invoke(selected)
            end)
            if ok then
                if result == 0 then
                    Fluent:Notify({ Title = "Shop", Content = "Failed to buy " .. selected, Duration = 3 })
                elseif result == 1 then
                    Fluent:Notify({ Title = "Shop", Content = "Already own " .. selected, Duration = 3 })
                elseif result == 2 then
                    Fluent:Notify({ Title = "Shop", Content = "Not enough money for " .. selected, Duration = 3 })
                elseif result == 3 then
                    Fluent:Notify({ Title = "Shop", Content = "Bought " .. selected .. "!", Duration = 3 })
                end
            else
                Fluent:Notify({ Title = "Shop", Content = "Error: " .. tostring(result), Duration = 3 })
            end
        end)
    end,
})
end
setupShopTab()

-- ============================================================
-- TRAIT ROLL TAB
-- ============================================================
Tabs.Trait:AddSection("Trait Rolling", "dice-5")

local CurrentTraitParagraph = Tabs.Trait:AddParagraph({ Title = "Current Trait", Content = "-" })
local RollCounterParagraph = Tabs.Trait:AddParagraph({ Title = "Roll Counter", Content = "0" })

task.spawn(function()
    while true do
        if LastTrait ~= "" then
            CurrentTraitParagraph:SetDesc(LastTrait)
            RollCounterParagraph:SetDesc(tostring(TraitRolls))
        end
        task.wait(0.1)
    end
end)

Tabs.Trait:AddDropdown("TraitTool", { Title = "Tool", Values = ToolList, Default = SelectedTool, Search = true }):OnChanged(function(v) SelectedTool = v end)

Tabs.Trait:AddDropdown("TargetTrait", { Title = "Target Trait", Values = TraitList, Default = TargetTrait, Search = true }):OnChanged(function(v) TargetTrait = v end)

Tabs.Trait:AddButton({
    Title = "Roll Once", Description = "Roll trait once",
    Callback = function()
        task.spawn(function()
            local trait = doSingleRoll()
            if trait then
                if TargetTrait ~= "" and trait == TargetTrait then
                    Fluent:Notify({ Title = "Shells Auto", Content = "Target trait " .. TargetTrait .. " found!", Duration = 5 })
                end
            else Fluent:Notify({ Title = "Shells Auto", Content = "Roll failed!", Duration = 3 }) end
        end)
    end,
})

Tabs.Trait:AddToggle("AutoTraitRoll", { Title = "Auto Roll", Default = false }):OnChanged(function(state)
    TraitRollRunning = state
    if state then TraitRollThread = task.spawn(traitRollLoop)
    elseif TraitRollThread then task.cancel(TraitRollThread); TraitRollThread = nil end
end)

-- ============================================================
-- MISC TAB
-- ============================================================
Tabs.Misc:AddSection("Performance & QoL", "settings")

Tabs.Misc:AddToggle("LightBoost", { Title = "Light Boost", Description = "Disable particles, effects, UI only", Default = false }):OnChanged(function(state)
    lightBoostEnabled = state
    if state then applyLightBoost(); Fluent:Notify({ Title = "Shells Auto", Content = "Light Boost enabled", Duration = 2 })
    else restoreLightBoost(); Fluent:Notify({ Title = "Shells Auto", Content = "Light Boost disabled", Duration = 2 }) end
end)

Tabs.Misc:AddToggle("FPSBoost", { Title = "Full Boost", Description = "Light Boost + terrain, lighting, shadows, materials", Default = false }):OnChanged(function(state)
    fpsBoostEnabled = state
    if state then applyFpsBoost(); Fluent:Notify({ Title = "Shells Auto", Content = "Full Boost enabled", Duration = 2 })
    else restoreFpsBoost(); Fluent:Notify({ Title = "Shells Auto", Content = "Full Boost disabled", Duration = 2 }) end
end)

Tabs.Misc:AddToggle("DisablePause", { Title = "Disable Pause", Default = false }):OnChanged(function(state)
    disablePauseEnabled = state
    if state then disablePauseThread = task.spawn(disablePauseLoop); Fluent:Notify({ Title = "Shells Auto", Content = "Disable Pause enabled", Duration = 2 })
    elseif disablePauseThread then task.cancel(disablePauseThread); disablePauseThread = nil; Fluent:Notify({ Title = "Shells Auto", Content = "Disable Pause disabled", Duration = 2 }) end
end)

Tabs.Misc:AddToggle("BlackScreen", { Title = "Black Screen", Description = "Turn screen black + disable 3D rendering", Default = false }):OnChanged(function(state)
    blackScreenEnabled = state
    if state then enableBlackScreen(); Fluent:Notify({ Title = "Shells Auto", Content = "Black Screen enabled", Duration = 2 })
    else disableBlackScreen(); Fluent:Notify({ Title = "Shells Auto", Content = "Black Screen disabled", Duration = 2 }) end
end)

-- ============================================================
-- WEBHOOK TAB
-- ============================================================
Tabs.Webhook:AddSection("Discord Webhook", "bell")

Tabs.Webhook:AddInput("WebhookUrl", { Title = "Webhook URL", Default = "", Placeholder = "https://discord.com/api/webhooks/...", Numeric = false, Finished = false }):OnChanged(function(v) webhookUrl = v end)

Tabs.Webhook:AddButton({
    Title = "Test Webhook", Description = "Send test message to Discord",
    Callback = function()
        if webhookUrl == "" then Fluent:Notify({ Title = "Shells Auto", Content = "Enter webhook URL first", Duration = 3 }); return end
        local ok = sendDiscordWebhook(webhookUrl, { content = "Qentury Hub webhook test!" })
        if ok then Fluent:Notify({ Title = "Shells Auto", Content = "Test sent to Discord!", Duration = 2 })
        else Fluent:Notify({ Title = "Shells Auto", Content = "Webhook test failed, check URL/console", Duration = 3 }) end
    end,
})

Tabs.Webhook:AddSection("Notifications", "bell-ring")

Tabs.Webhook:AddDropdown("WebhookRarities", { Title = "Notify Rarities", Values = RARITY_LIST, Multi = true, Default = {} }):OnChanged(function(selected) webhookSelectedRarities = selected or {} end)

Tabs.Webhook:AddToggle("WebhookLostCity", { Title = "Lost City Notify", Default = false }):OnChanged(function(state) webhookLostCityNotify = state end)

Tabs.Webhook:AddToggle("MerchantWebhook", { Title = "Travel Merchant Summary", Description = "Send purchase summary to Discord after auto buy", Default = false }):OnChanged(function(state)
    webhookMerchantNotify = state
    if state then
        if not merchantThread then merchantThread = task.spawn(merchantMonitorLoop) end
    else
        if not merchantAutoBuy and not merchantNotify and not webhookMerchantNotify and merchantThread then
            task.cancel(merchantThread); merchantThread = nil
        end
    end
end)

Tabs.Webhook:AddToggle("WebhookEnabled", { Title = "Enable Webhook", Default = false }):OnChanged(function(state)
    webhookEnabled = state
    if state then startWebhookMonitor(); Fluent:Notify({ Title = "Shells Auto", Content = "Webhook monitoring started", Duration = 2 })
    else
        if webhookMonitorConn then webhookMonitorConn:Disconnect(); webhookMonitorConn = nil end
        if webhookMonitorThread then task.cancel(webhookMonitorThread); webhookMonitorThread = nil end
        Fluent:Notify({ Title = "Shells Auto", Content = "Webhook monitoring stopped", Duration = 2 })
    end
end)

-- ============================================================
-- SETTINGS
-- ============================================================
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "AutoDig", "MythicOnly", "AutoLostCity", "AutoDebris", "AutoSell", "AutoTraitRoll", "AutoMerchant", "AutoFavorite", "FavRarities", "FavShells", "AutoVaultDeposit", "VaultDepositRarities", "VaultDepositShells", "VaultWithdrawRarities", "VaultWithdrawShells", "AutoGift", "GiftTarget", "GiftRarities", "GiftShells", "GiftByValue", "GiftTargetValue", "GiftValueMode" })
InterfaceManager:SetFolder("ShellsFarmConfigs")
SaveManager:SetFolder("ShellsFarmConfigs")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Tabs.Settings:AddButton({
    Title = "Unload Script", Description = "Stop all automation and destroy UI",
    Callback = function()
        Window:Dialog({
            Title = "Unload Script", Content = "Are you sure you want to unload? All automation will stop.",
            Buttons = {
                { Title = "Confirm", Callback = function()
                    Fluent:Notify({ Title = "Shells Auto", Content = "Unloading script...", Duration = 2 })
                    task.spawn(function()
                        autoDig = false; autoSell = false; busyDig = false; busySell = false
                        mythicOnly = false; questAutoClaim = false; sifterAutoCollect = false
    autoFavoriteEnabled = false
    autoVaultDepositEnabled = false
    autoGiftEnabled = false
                        hermitAutoClaim = false; hermitAutoUpgrade = false; TraitRollRunning = false
                        disablePauseEnabled = false; fpsBoostEnabled = false
                        merchantAutoBuy = false; merchantNotify = false; webhookMerchantNotify = false
                        if lostCityThread then task.cancel(lostCityThread); lostCityThread = nil end
                        if lostCityLockThread then task.cancel(lostCityLockThread); lostCityLockThread = nil end
                        if debrisThread then task.cancel(debrisThread); debrisThread = nil end
                        if hermitClaimThread then task.cancel(hermitClaimThread); hermitClaimThread = nil end
                        if hermitUpgradeThread then task.cancel(hermitUpgradeThread); hermitUpgradeThread = nil end
                        if merchantThread then task.cancel(merchantThread); merchantThread = nil end
                        if questClaimThread then task.cancel(questClaimThread); questClaimThread = nil end
                        if sifterCollectThread then task.cancel(sifterCollectThread); sifterCollectThread = nil end
                        if TraitRollThread then task.cancel(TraitRollThread); TraitRollThread = nil end
                        if disablePauseThread then task.cancel(disablePauseThread); disablePauseThread = nil end
                        restoreLightBoost()
                        restoreFpsBoost()
                        disableBlackScreen()
                        if webhookMonitorConn then webhookMonitorConn:Disconnect(); webhookMonitorConn = nil end
                        if webhookMonitorThread then task.cancel(webhookMonitorThread); webhookMonitorThread = nil end
                        webhookEnabled = false
                        Fluent:Destroy()
                        pcall(function()
                            for _, child in ipairs(game:GetService("CoreGui"):GetChildren()) do
                                if child:IsA("ScreenGui") and child.Name:find("FluentPlus") then child:Destroy() end
                            end
                        end)
                        getgenv().FluentShellsLoaded = false
                        getgenv().FluentShellsCleanup = nil
                        print("[Shells Auto] Script unloaded successfully.")
                    end)
                end },
                { Title = "Cancel", Callback = function() end },
            }
        })
    end,
})

-- ============================================================
-- INIT
-- ============================================================
Window:SelectTab(1)
SaveManager:LoadAutoloadConfig()
webhookUrl = Options.WebhookUrl and Options.WebhookUrl.Value or ""
print("[Shells Auto] v4 loaded. Press LeftControl to open GUI.")

-- ANTI-NUMPUK: register cleanup for next execute
getgenv().FluentShellsCleanup = function()
    pcall(function()
        autoDig = false; autoSell = false; busyDig = false; busySell = false
        mythicOnly = false; questAutoClaim = false; sifterAutoCollect = false
        autoFavoriteEnabled = false
        hermitAutoClaim = false; hermitAutoUpgrade = false; TraitRollRunning = false
        disablePauseEnabled = false; fpsBoostEnabled = false
        merchantAutoBuy = false; merchantNotify = false; webhookMerchantNotify = false
        autoStorageUpgrade = false
        if lostCityThread then pcall(task.cancel, lostCityThread) end
        if lostCityLockThread then pcall(task.cancel, lostCityLockThread) end
        if debrisThread then pcall(task.cancel, debrisThread) end
        if hermitClaimThread then pcall(task.cancel, hermitClaimThread) end
        if hermitUpgradeThread then pcall(task.cancel, hermitUpgradeThread) end
        if merchantThread then pcall(task.cancel, merchantThread) end
        if questClaimThread then pcall(task.cancel, questClaimThread) end
        if sifterCollectThread then pcall(task.cancel, sifterCollectThread) end
        if TraitRollThread then pcall(task.cancel, TraitRollThread) end
        if disablePauseThread then pcall(task.cancel, disablePauseThread) end
        if storageUpgradeThread then pcall(task.cancel, storageUpgradeThread) end
        pcall(restoreLightBoost)
        pcall(restoreFpsBoost)
        pcall(disableBlackScreen)
        if webhookMonitorConn then pcall(function() webhookMonitorConn:Disconnect() end) end
        if webhookMonitorThread then pcall(task.cancel, webhookMonitorThread) end
        webhookEnabled = false
        pcall(function() Fluent:Destroy() end)
        pcall(function()
            for _, child in ipairs(game:GetService("CoreGui"):GetChildren()) do
                if child:IsA("ScreenGui") and child.Name:find("FluentPlus") then child:Destroy() end
            end
        end)
        pcall(function()
            for _, conn in ipairs(getconnections and getconnections(LP.Idled) or {}) do
                conn:Disconnect()
            end
        end)
    end)
end
