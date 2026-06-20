-- ============================================================================
--  ENG & IRSE PROJECT - AUTOMATION MODULE (v4.0.0)
--  Supported Features: Rayfield UI, Geode Opener, Treasure Hunt,
--                      Sand Dollar Collection, and Auto Quest.
--
--  Release Notes:
--  - Added Automated Quest (Dredge Master) system.
--  - Enhanced Sand Dollar Collection with high-speed server replication.
--  - Restored Auto Treasure Hunt capability.
-- ============================================================================

--// Executor compatibility
local cloneref = cloneref or clonereference or function(instance)
    return instance
end

--// Services
local TweenService      = cloneref(game:GetService("TweenService"))
local RunService        = cloneref(game:GetService("RunService"))
local VirtualUser       = cloneref(game:GetService("VirtualUser"))
local Services = {
    Players           = cloneref(game:GetService("Players")),
    Workspace         = cloneref(game:GetService("Workspace")),
    RunService        = RunService,
    ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage")),
}

local Player          = Services.Players.LocalPlayer
local ReplicatedStorage = Services.ReplicatedStorage
local BackpackTwo     = Player:WaitForChild("BackpackTwo", 15)

--// Character binding
local Character, HumanoidRootPart, Humanoid, Movement

local function bindCharacter(char)
    Character        = char
    Humanoid         = char:WaitForChild("Humanoid", 10)
    HumanoidRootPart = char:WaitForChild("HumanoidRootPart", 10)
end

bindCharacter(Player.Character or Player.CharacterAdded:Wait())
Player.CharacterAdded:Connect(bindCharacter)

--// Safe helpers
local function safeChildren(inst)
    if not inst then return {} end
    local ok, r = pcall(function() return inst:GetChildren() end)
    return (ok and r) or {}
end

local function safeDescendants(inst)
    if not inst then return {} end
    local ok, r = pcall(function() return inst:GetDescendants() end)
    return (ok and r) or {}
end

local function formatTime(s)
    s = tonumber(s) or 0
    if s <= 0 then return "0s" end
    local m = math.floor(s/60)
    local r = math.floor(s%60)
    return m > 0 and (m.."m "..r.."s") or (r.."s")
end

local function getPathName(obj)
    if not obj then return "None" end
    local parts, cur = {}, obj
    while cur and cur ~= game do
        table.insert(parts, 1, cur.Name)
        cur = cur.Parent
    end
    local s = table.concat(parts, "/")
    return #s > 55 and ("..."..s:sub(#s-51)) or s
end

-- ============================================================
--  STATE
-- ============================================================

local State = {
    -- Settings (speed dari simple source.txt)
    Speed         = 16,
    StopDistance  = 5,
    CruiseHeight  = 3,
    WalkSpeed     = 100,   -- WalkSpeed saat Auto Collect Sand Dollar aktif
    OrigWalkSpeed = 16,    -- Simpan WalkSpeed asli untuk restore

    -- Geode (hunting)
    GeodeRunning  = false,
    GeodeStartAt  = nil,
    GeodeCount    = 0,

    -- Treasure (hunting)
    TreasureRunning  = false,
    TreasureStartAt  = nil,
    TreasureMapCount = 0,
    TreasureCurrent  = "—",
    TreasureCompleted = 0,

    -- Sand Dollar
    SandRunning   = false,
    SandStartAt   = nil,
    SandCollected = 0,
    SandTotal     = 0,
    SandTarget    = "None",
    SandDist      = 0,
    SandLastScan  = 0,
    SandScanRoot  = "workspace",

    -- ESP
    EspEnabled    = false,

    -- Main UI features state
    AutoFarm = {
        active = false,
        actionMode = "Instant",
        travelMode = "Teleport",
        sandCFrame = nil,
        waterCFrame = nil,
        locked = false,
        interrupted = false,
        interruptReason = nil,
        running = false
    },

    Sell = {
        mode = "Teleport",
        type = "Auto",
        threshold = 300,
        delay = 60,
        autoSell = false,
        _lastSell = nil,
        _scheduledSell = nil
    },

    Excavation = {
        selected = nil,
        data = nil,
        autoClaim = false,
        autoStart = false,
        autoStartRunning = false,
        waiting = false
    },

    Crafting = {
        selectedEquipment = nil,
        selectedMaterials = {},
        discoveredRecipes = {},
        autocraft = false,
        autocraftRunning = false,
        selectBestOres = false
    },

    ESP = {
        Players = {},
        Totems = {},
        Connections = {}
    },

    Barriers = {
        vines = false,
        abyssalGate = false,
        peakObstruction = false
    },

    Pan = {
        current = 0,
        max = 100,
        isFull = false
    },

    Geode = {
        currentIndex = 1,
        autoLoopEnabled = false,
        lastTeleportTime = 0,
        teleportConnection = nil
    },

    Rune = {
        currentIndex = 0,
        autoLoopEnabled = false,
        lastTeleportTime = 0,
        teleportConnection = nil
    },

    Hunting = {
        autoGeode = false,
        autoTreasure = false,
        autoTreasureRunning = false,
        autoTreasurePausedFarm = false
    },

    TravelMerchant = {
        running = false,
        selectedItems = {},
        useMoney = true,
        useShard = false,
        totalBought = 0
    },

    Summer = {
        progress = 0,
        quality = 0,
        deliveryTime = 0,
        autoAddRunning = false,
        selectedModifiers = {},
        selectedRarities = {}
    },

    Quest = {
        autoQuest = false,
        interval = 10,
        running = false,
        statusUI = nil
    }
}

-- ============================================================
--  BACKPACK HELPERS
-- ============================================================

local function getBackpack()
    return Player:FindFirstChild("BackpackTwo")
        or Player:FindFirstChild("Backpack")
end

-- ============================================================
--  INVENTORY COUNTERS
-- ============================================================

local function isGeodeItem(item)
    if not item then return false end
    return item.Name == "Geode" or item:GetAttribute("ItemType") == "Geode"
end

local function isTreasureItem(item)
    if not item then return false end
    local t = item:GetAttribute("ItemType")
    return t == "TreasureMap" or t == "Treasure Map"
        or (item.Name:lower():find("treasure") and item.Name:lower():find("map"))
end

local function countIn(pred)
    local n = 0
    local containers = {}
    local bp = getBackpack()
    if bp then table.insert(containers, bp) end
    if Character then table.insert(containers, Character) end
    for _, c in ipairs(containers) do
        for _, it in ipairs(safeChildren(c)) do
            if pred(it) then n += 1 end
        end
    end
    return n
end

-- ============================================================
--  GEODE OPENER LOGIC
-- ============================================================

local function getInventoryCount()
    local n = 0
    for _, item in ipairs(safeChildren(BackpackTwo)) do
        local t = item:GetAttribute("ItemType")
        if t == "Valuable" or t == "Equipment" then n += 1 end
    end
    if Character then
        local eq = Character:FindFirstChildOfClass("Tool")
        if eq then
            local t = eq:GetAttribute("ItemType")
            if t == "Valuable" or t == "Equipment" then n += 1 end
        end
    end
    return n
end

local function getMaxCapacity()
    return Player:GetAttribute("InventorySize") or 100
end

local function findGeodeInBP()
    for _, item in ipairs(safeChildren(BackpackTwo)) do
        if item.Name == "Geode" then return item end
    end
    return nil
end

local function isGeodeInChar()
    if not Character then return false end
    for _, item in ipairs(safeChildren(Character)) do
        if item:GetAttribute("ItemType") == "Geode" then return true end
    end
    return false
end

local function waitGeodeInChar(timeout)
    timeout = timeout or 50
    local t = 0
    while t < timeout do
        if isGeodeInChar() then return true end
        task.wait(0.01); t += 1
    end
    return false
end

local function isGeodeDepleted()
    if not Character then return true end
    for _, item in ipairs(safeChildren(Character)) do
        if item:GetAttribute("ItemType") == "Geode" then
            local s = item:GetAttribute("Stacks")
            if s and s > 0 then return false end
        end
    end
    return true
end

local function startGeodeOpener()
    if State.GeodeRunning then return false end
    local g = findGeodeInBP()
    if not g and not isGeodeInChar() then return false end

    State.GeodeRunning = true
    State.GeodeStartAt = tick()

    task.spawn(function()
        while State.GeodeRunning do
            if getInventoryCount() >= getMaxCapacity() then break end

            local geode = findGeodeInBP()
            if not geode then break end

            pcall(function()
                ReplicatedStorage.Remotes.CustomBackpack.EquipRemote:FireServer(geode)
            end)

            if not waitGeodeInChar() then break end

            local clicks = 0
            while State.GeodeRunning do
                if isGeodeDepleted() or getInventoryCount() >= getMaxCapacity() then break end
                VirtualUser:ClickButton1(Vector2.new(math.random(100,900), math.random(100,700)))
                clicks += 1
                task.wait(0.01)
            end
        end
        State.GeodeRunning = false
    end)

    return true
end

local function stopGeodeOpener()
    State.GeodeRunning = false
end

-- ============================================================
--  TREASURE HUNT LOGIC
-- ============================================================

local function findTool(pred)
    local containers = {}
    if Character then table.insert(containers, Character) end
    local bp = getBackpack()
    if bp then table.insert(containers, bp) end
    for _, c in ipairs(containers) do
        if c then
            for _, it in ipairs(safeChildren(c)) do
                if it:IsA("Tool") and pred(it) then return it end
            end
        end
    end
    return nil
end

local function equipTool(tool)
    if not tool then return false end
    if tool.Parent == Character then return true end
    pcall(function()
        ReplicatedStorage.Remotes.CustomBackpack.EquipRemote:FireServer(tool)
    end)
    local start = tick()
    while tool.Parent ~= Character and (tick() - start) < 2.5 do
        task.wait(0.05)
    end
    return tool.Parent == Character
end

local function getPan()
    if Character then
        local eq = Character:FindFirstChildOfClass("Tool")
        if eq and eq:GetAttribute("ItemType") == "Pan" then return eq end
    end
    for _, v in ipairs(safeChildren(BackpackTwo)) do
        if v:GetAttribute("ItemType") == "Pan" then
            ReplicatedStorage.Remotes.CustomBackpack.EquipRemote:FireServer(v)
            task.wait(0.5)
            return v
        end
    end
    return nil
end

local function getTreasureCollect()
    if not Character then return nil end
    local eq = Character:FindFirstChildOfClass("Tool")
    if not eq then return nil end
    local sc = eq:FindFirstChild("Scripts")
    return sc and sc:FindFirstChild("Collect") or nil
end

local function prepareTreasureTool()
    local shovel = findTool(function(t)
        return t:GetAttribute("ItemType") == "Shovel" or t.Name:find("Shovel")
    end)
    if shovel then equipTool(shovel); return shovel end
    return getPan()
end

local function findTreasureMaps()
    local out = {}
    local containers = {}
    local bp = getBackpack()
    if bp then table.insert(containers, bp) end
    if Character then table.insert(containers, Character) end
    for _, container in ipairs(containers) do
        if container then
            for _, item in ipairs(safeChildren(container)) do
                local name = item.Name:lower()
                if item:GetAttribute("ItemType") == "TreasureMap" or (name:find("treasure") and name:find("map")) then
                    table.insert(out, item)
                end
            end
        end
    end
    return out
end

local function huntSingleMap(map)
    if not map or not map.Parent then return false end
    local location = map:GetAttribute("Location")
    local mapGUID = map:GetAttribute("GUID")

    if not location or not mapGUID then
        local bp = getBackpack()
        if bp then
            for _, v in ipairs(bp:GetChildren()) do
                local name = v.Name:lower()
                if v:GetAttribute("ItemType") == "TreasureMap" or (name:find("treasure") and name:find("map")) then
                    local loc = v:GetAttribute("Location")
                    local guid = v:GetAttribute("GUID")
                    if loc and guid then
                        location = loc
                        mapGUID = guid
                        map = v
                        break
                    end
                end
            end
        end
    end

    if not location or not mapGUID then return false end

    local targetCF = typeof(location) == "CFrame" and location or CFrame.new(location)
    local startT   = tick()
    local timeout  = 120
    local lastCol  = 0

    local function findMapInContainers(mapName, guid)
        local containers = {}
        if Character then table.insert(containers, Character) end
        local bp = getBackpack()
        if bp then table.insert(containers, bp) end
        for _, container in ipairs(containers) do
            if container then
                for _, v in ipairs(container:GetChildren()) do
                    local name = v.Name:lower()
                    local isMap = v:GetAttribute("ItemType") == "TreasureMap" or (name:find("treasure") and name:find("map"))
                    if isMap then
                        local vGUID = v:GetAttribute("GUID")
                        if guid and vGUID and vGUID == guid then
                            return v
                        end
                        if not guid or not vGUID then
                            return v
                        end
                    end
                end
            end
        end
        return nil
    end

    local attempts = 0
    while State.TreasureRunning and (tick()-startT) < timeout do
        local currentMap = findMapInContainers(map.Name, mapGUID)
        if not currentMap or currentMap:GetAttribute("GUID") ~= mapGUID then
            task.wait(0.3)
            return true
        end
        if not Character or not Character:FindFirstChild("HumanoidRootPart") then break end

        Character.HumanoidRootPart.CFrame = targetCF

        if tick() - lastCol > 0.02 then
            local col = getTreasureCollect()
            if col then pcall(function() col:InvokeServer(0) end) end
            lastCol = tick()
            attempts = attempts + 1
            if attempts > 150 then
                local mapNameDisplay = map.Name:gsub(" Treasure Map", "")
                pcall(function()
                    EngProject:CreateNotification({
                        Type = "Warning",
                        Title = "Wrong Map / Region",
                        Description = "This treasure map belongs to another region. Please travel to " .. mapNameDisplay .. " to hunt it!",
                        Duration = 8
                    })
                end)
                break
            end
        end
        task.wait(0.01)
    end
    return false
end

local function startTreasureHunting()
    if State.TreasureRunning then return false end
    local maps = findTreasureMaps()
    if #maps == 0 then return false end

    State.TreasureRunning   = true
    State.TreasureCompleted = 0
    State.TreasureStartAt   = tick()

    task.spawn(function()
        prepareTreasureTool()

        while State.TreasureRunning do
            local ms = findTreasureMaps()
            if #ms == 0 then break end
            State.TreasureMapCount = #ms

            for _, map in ipairs(ms) do
                if not State.TreasureRunning then break end
                State.TreasureCurrent = map.Name or "?"
                local ok = huntSingleMap(map)
                if ok then
                    State.TreasureCompleted += 1
                    task.wait(0.5)
                end
            end
            task.wait(1)
        end

        State.TreasureRunning  = false
        State.TreasureCurrent  = "—"
    end)
    return true
end

local function stopTreasureHunting()
    State.TreasureRunning = false
    State.TreasureCurrent = "—"
end

-- ============================================================
--  SAND DOLLAR SCANNER
--  Pendekatan PERSIS seperti engkol.txt:
--  - GeodeFolder:GetChildren() (direct children saja!)
--  - Bukan safeDescendants — itu sebabnya sebelumnya gagal
-- ============================================================

-- Cache GeodeFolder (boleh nil jika belum ada)
local GeodeFolder = Services.Workspace:FindFirstChild("Geode")

-- Update cache setiap scan
local function getGeodeFolder()
    if not GeodeFolder or not GeodeFolder.Parent then
        GeodeFolder = Services.Workspace:FindFirstChild("Geode")
    end
    return GeodeFolder
end

local function getSandPart(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    return obj:FindFirstChildWhichIsA("BasePart", true)
end

-- Scan langsung dari direct children GeodeFolder (sama dengan engkol.txt)
local function getAllSandDollars()
    local list = {}
    local folder = getGeodeFolder()

    -- Primary: workspace.Geode:GetChildren() — persis engkol.txt
    if folder then
        for _, obj in ipairs(safeChildren(folder)) do
            if obj.Name == "SandDollar" or obj.Name == "Sand Dollar" then
                local part = getSandPart(obj)
                if part then
                    table.insert(list, { obj = obj, part = part })
                end
            end
        end
    end

    -- Fallback: scan roots lain jika tidak ketemu di Geode
    if #list == 0 then
        local preferred = {"Geodes","Collectibles","Map","World","SpawnedItems","Items"}
        for _, n in ipairs(preferred) do
            local f = Services.Workspace:FindFirstChild(n)
            if f then
                for _, obj in ipairs(safeChildren(f)) do
                    if obj.Name == "SandDollar" or obj.Name == "Sand Dollar" then
                        local part = getSandPart(obj)
                        if part then table.insert(list, {obj=obj, part=part}) end
                    end
                end
            end
        end
    end

    return list
end

local function scanSandDollars()
    local char = Player.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local all  = getAllSandDollars()
    State.SandTotal = #all

    local nearObj, nearDist = nil, math.huge
    local root = GeodeFolder and GeodeFolder.Name or "workspace"

    if hrp then
        for _, e in ipairs(all) do
            local d = (hrp.Position - e.part.Position).Magnitude
            if d < nearDist then
                nearDist = d
                nearObj  = e.obj
            end
        end
    end

    State.SandTarget   = nearObj and (nearObj.Name .. " (" .. tostring(#all) .. " total)") or "None"
    State.SandDist     = nearObj and math.floor(nearDist) or 0
    State.SandLastScan = tick()
    State.SandScanRoot = root
end

-- ============================================================
--  ESP
-- ============================================================

local function clearSandESP()
    local folder = getGeodeFolder()
    if folder then
        for _, obj in ipairs(safeChildren(folder)) do
            for _, v in ipairs(safeDescendants(obj)) do
                if v.Name == "SandDollarESP" then pcall(function() v:Destroy() end) end
            end
        end
    end
end

local function createSandESP(obj, part)
    for _, v in ipairs(safeDescendants(obj)) do
        if v.Name == "SandDollarESP" then pcall(function() v:Destroy() end) end
    end

    local hl = Instance.new("Highlight")
    hl.Name = "SandDollarESP"
    hl.FillColor = Color3.fromRGB(255,255,50)
    hl.OutlineColor = Color3.fromRGB(255,220,0)
    hl.FillTransparency = 0.55
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = obj
    hl.Parent  = obj

    local bill = Instance.new("BillboardGui")
    bill.Name = "SandDollarESP"
    bill.Size = UDim2.new(0,120,0,26)
    bill.AlwaysOnTop = true
    bill.StudsOffset = Vector3.new(0,3,0)
    bill.Adornee = part
    bill.Parent  = part

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.fromScale(1,1)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 14
    lbl.TextStrokeTransparency = 0.5
    lbl.TextColor3 = Color3.fromRGB(255,240,0)
    lbl.Text = "🐚 Sand Dollar"
    lbl.Parent = bill
end

local function refreshESP()
    if not State.EspEnabled then return end
    clearSandESP()
    for _, e in ipairs(getAllSandDollars()) do
        pcall(function() createSandESP(e.obj, e.part) end)
    end
end

-- ==================================================-- ============================================================
--  AUTO COLLECT SAND DOLLAR
--  Anti-Rubber-Band Technique:
--  → WalkSpeed di-set sangat tinggi (500+) sehingga server
--    menganggap movement cepat sebagai VALID
--  → Humanoid:MoveTo() dalam loop ketat (0.05s) — ini yang
--    mengirim posisi ke server (bukan TweenService!)
--  → Noclip via Stepped.CanCollide=false agar tembus terrain
--  → setelah sampai, fire semua metode collect yang tersedia
-- ============================================================

local function enableNoclip(char)
    if not char then return end
    for _, v in ipairs(char:GetDescendants()) do
        if v:IsA("BasePart") then
            pcall(function() v.CanCollide = false end)
        end
    end
end

local function disableNoclip(char)
    if not char then return end
    for _, v in ipairs(char:GetDescendants()) do
        if v:IsA("BasePart") then
            pcall(function() v.CanCollide = true end)
        end
    end
end

-- Ambil remote Collect dari Pan tool yang di-equip (seperti Prospecting.lua)
local function getSandCollectRemote()
    local char = Player.Character
    if not char then return nil end
    for _, tool in ipairs(char:GetChildren()) do
        if tool:IsA("Tool") then
            local scripts = tool:FindFirstChild("Scripts")
            if scripts then
                local c = scripts:FindFirstChild("Collect")
                if c then return c end
            end
            local c = tool:FindFirstChild("Collect", true)
            if c and (c:IsA("RemoteFunction") or c:IsA("RemoteEvent")) then
                return c
            end
        end
    end
    return nil
end

-- Coba semua metode collect di Sand Dollar
local function tryCollectSandDollar(obj, hrp)
    if not obj or not obj.Parent then return end

    -- Method 1: fireproximityprompt (exploit API)
    if type(fireproximityprompt) == "function" then
        pcall(function()
            for _, v in ipairs(obj:GetDescendants()) do
                if v:IsA("ProximityPrompt") then
                    v.HoldDuration = 0
                    fireproximityprompt(v)
                end
            end
        end)
    end

    -- Method 2: fireclickdetector (exploit API)
    if type(fireclickdetector) == "function" then
        pcall(function()
            for _, v in ipairs(obj:GetDescendants()) do
                if v:IsA("ClickDetector") then
                    fireclickdetector(v)
                end
            end
        end)
    end

    -- Method 3: Collect:InvokeServer dari Pan tool
    local collectRemote = getSandCollectRemote()
    if collectRemote then
        if collectRemote:IsA("RemoteFunction") then
            pcall(function() collectRemote:InvokeServer() end)
            task.wait(0.02)
            pcall(function() collectRemote:InvokeServer(0) end)
        elseif collectRemote:IsA("RemoteEvent") then
            pcall(function() collectRemote:FireServer() end)
        end
    end
end

-- INTI: MoveTo dengan WalkSpeed tinggi agar server terima posisi
-- Server Roblox memvalidasi: "apakah kecepatan ≤ WalkSpeed?" 
-- Jika WalkSpeed = 500 → movement 500 studs/s dianggap SAH
local SAND_BOOST_SPEED = 500  -- studs/s (cukup tinggi untuk anti-rubber-band)
local SAND_COLLECT_DIST = 4   -- jarak minimum untuk collect

local function moveToSandDollar(hrp, hum, targetPos, runningRef)
    if not hrp or not hum then return false end

    local speed = State.Speed or 45
    local success = Movement.pathfindTween(targetPos, {
        Speed = speed,
        StopDistance = SAND_COLLECT_DIST,
        ShouldContinue = runningRef,
        OnUpdate = function(remainingDist)
            State.SandDist = math.floor(remainingDist)
        end
    })

    return success
end

local function startSandCollect()
    if State.SandRunning then return false end
    State.SandRunning   = true
    State.SandCollected = 0
    State.SandStartAt   = tick()

    task.spawn(function()
        while State.SandRunning do
            local char = Player.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            local hum  = char and char:FindFirstChildOfClass("Humanoid")
            if not hrp or not hum then task.wait(1); continue end

            local all = getAllSandDollars()
            State.SandTotal = #all

            if #all == 0 then
                State.SandTarget = "Tidak ada Sand Dollar"
                State.SandDist   = 0
                task.wait(3)
                continue
            end

            -- Sort by distance, ambil terdekat
            table.sort(all, function(a, b)
                return (hrp.Position - a.part.Position).Magnitude
                     < (hrp.Position - b.part.Position).Magnitude
            end)

            local entry = all[1]
            local obj   = entry.obj
            local part  = entry.part

            if not obj or not obj.Parent then task.wait(0.05); continue end

            local targetPos   = part.Position
            local countBefore = #all

            State.SandTarget = obj.Name .. " (" .. tostring(#all) .. " left)"
            State.SandDist   = math.floor((hrp.Position - targetPos).Magnitude)

            -- MOVE: Walk/Tween dengan pathfinding di sekitar rintangan
            moveToSandDollar(hrp, hum, targetPos, function() return State.SandRunning end)

            -- COLLECT: coba semua metode
            tryCollectSandDollar(obj, hrp)

            -- Tunggu server proses (1 detik agar server sempat check proximity)
            task.wait(1)

            local countAfter = #getAllSandDollars()
            if countAfter < countBefore then
                State.SandCollected += (countBefore - countAfter)
                if State.EspEnabled then pcall(refreshESP) end
            end

            task.wait(0.05)
        end

        disableNoclip(Player.Character)
        State.SandRunning = false
        State.SandTarget  = "None"
        State.SandDist    = 0
    end)

    return true
end

local function stopSandCollect()
    State.SandRunning = false
    pcall(function() disableNoclip(Player.Character) end)
end

-- ============================================================
--  SAND DOLLAR MAGNET COLLECT
--  MoveTo ke setiap SD dengan WalkSpeed tinggi, collect,
--  lalu MoveTo kembali ke posisi asal.
-- ============================================================

State.SandMagnetRunning = false

local function startSandMagnet()
    if State.SandMagnetRunning then return false end
    State.SandMagnetRunning = true
    State.SandCollected     = 0
    State.SandStartAt       = tick()

    task.spawn(function()
        while State.SandMagnetRunning do
            local char = Player.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            local hum  = char and char:FindFirstChildOfClass("Humanoid")
            if not hrp or not hum then task.wait(1); continue end

            local all = getAllSandDollars()
            State.SandTotal = #all

            if #all == 0 then
                State.SandTarget = "Tidak ada Sand Dollar"
                State.SandDist   = 0
                task.wait(3)
                continue
            end

            local originPos   = hrp.Position
            local countBefore = #all
            State.SandTarget  = tostring(#all) .. " Sand Dollar (MAGNET)"
            State.SandDist    = 0

            -- MoveTo ke setiap Sand Dollar satu per satu
            for _, entry in ipairs(all) do
                if not State.SandMagnetRunning then break end
                local obj  = entry.obj
                local part = entry.part
                if not obj or not obj.Parent then continue end

                moveToSandDollar(hrp, hum, part.Position, function()
                    return State.SandMagnetRunning
                end)
                tryCollectSandDollar(obj, hrp)
                task.wait(0.5)
            end

            -- Kembali ke posisi asal (player terlihat "diam")
            if State.SandMagnetRunning and (hrp.Position - originPos).Magnitude > 5 then
                local speed = State.Speed or 45
                Movement.pathfindTween(originPos, {
                    Speed = speed,
                    StopDistance = 3,
                    ShouldContinue = function() return State.SandMagnetRunning end,
                    OnUpdate = function(remainingDist)
                        State.SandDist = math.floor(remainingDist)
                    end
                })
            end

            task.wait(0.3)

            local countAfter = #getAllSandDollars()
            local collected  = countBefore - countAfter
            if collected > 0 then
                State.SandCollected += collected
                State.SandTotal = countAfter
                if State.EspEnabled then pcall(refreshESP) end
            end
        end

        disableNoclip(Player.Character)
        State.SandMagnetRunning = false
        State.SandTarget = "None"
        State.SandDist   = 0
    end)

    return true
end

local function stopSandMagnet()
    State.SandMagnetRunning = false
    pcall(function() disableNoclip(Player.Character) end)
end

-- ============================================================
--  REFRESH ALL
-- ============================================================

local function refreshAll()
    pcall(function()
        State.GeodeCount       = countIn(isGeodeItem)
        State.TreasureMapCount = countIn(isTreasureItem)
    end)
    pcall(scanSandDollars)
end
-- ============================================================
-- APPENDED FROM SIMPLE SOURCE (WITH STANDALONE SHIMS)

local gethui = gethui or function()
    return game:GetService("CoreGui")
end
local protectgui = protectgui or function()
end
local cloneref = cloneref or clonereference or function(instance)
    return instance
end
local newcclosure = newcclosure or function(func)
    return func
end
local getcustomasset = getcustomasset or function(path)
    return ""
end

local EngProject = {}

EngProject.Version = "1.1.1"
EngProject.Loaded = EngProject.Loaded or {}
EngProject.Windows = EngProject.Windows or {}

local CoreGui = cloneref(game:GetService("CoreGui"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local TweenService = cloneref(game:GetService("TweenService"))
local Lighting = cloneref(game:GetService("Lighting"))
local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))

local LocalPlayer = Players.LocalPlayer

EngProject.Constants = {
    Window = {
        MinSize = Vector2.new(600, 400),
        MaxSize = Vector2.new(1400, 900),
        DefaultAspectRatio = 1.6,
        TopBarHeight = 48,
        FooterHeight = 24,
        TabsWidthOpen = 0.22,
        ContentWidthOpen = 0.78,
        TabsWidthClosed = 55,
        ContentLeftOffsetClosed = 60,
        ContentWidthScaleClosed = 1,
        HorizontalPadding = 10,
        VerticalPadding = 10,
        DefaultScale = 0.75,
        MinScale = 0.5,
        MaxScale = 2,
        TabModes = {
            Fixed = "Fixed",
            Dynamic = "Dynamic",
            Closed = "Closed"
        },
        ResizeModes = {
            BottomRight = "BottomRight",
            Center = "Center"
        },
        TabDynamicThreshold = 2,
        TabIconSizeExpanded = 20,
        TabIconSizeCollapsed = 28,
        ClosedTabHorizontalPadding = 1,
        TabSeparatorGap = 1
    },
    Padding = {
        Small = 4,
        Medium = 8,
        Large = 10,
        ExtraLarge = 12
    },
    Spacing = {
        Tight = 2,
        Normal = 4,
        Relaxed = 6,
        Loose = 8
    },
    Corner = {
        None = 0,
        Small = 3,
        Medium = 4,
        Large = 6,
        HolyFuckingShit = 12,
        Round = 1
    },
    Animation = {
        Fast = 0.15,
        Normal = 0.2,
        Slow = 0.35,
        VerySlow = 0.4,
        Smooth = 0.25
    },
    ZIndex = {
        Background = 1,
        Base = 2,
        Content = 3,
        Control = 4,
        Overlay = 5,
        Modal = 250,
        Notification = 999
    }
}

EngProject.WindowControls = {
    MacOS = {
        ButtonSize = UDim2.new(0, 12, 0, 12),
        ButtonSpacing = 8,
        UseImages = false,
        Alignment = "Left",
        Colors = {
            Close = Color3.fromRGB(255, 95, 86),
            Maximize = Color3.fromRGB(40, 201, 64)
        }
    },
    Windows = {
        ButtonSize = UDim2.new(0, 32, 1, 0),
        ButtonSpacing = 0,
        UseImages = true,
        Alignment = "Right",
        Transparency = 1,
        Icons = {
            Maximize = {
                Image = "rbxassetid://9886659001",
                ColorKey = "TextPrimary",
                Size = UDim2.new(0, 16, 0, 16),
                HoverColor = Color3.fromRGB(60, 60, 60),
                PressedColor = Color3.fromRGB(80, 80, 80)
            },
            Close = {
                Image = "rbxassetid://10747384394",
                ColorKey = "TextPrimary",
                Size = UDim2.new(0, 16, 0, 16),
                HoverColor = Color3.fromRGB(232, 17, 35),
                PressedColor = Color3.fromRGB(180, 10, 25)
            }
        }
    }
}

EngProject.Themes = {
    IceBlack = {
        Primary = Color3.fromRGB(10, 10, 12),
        Secondary = Color3.fromRGB(18, 18, 22),
        SecondaryHover = Color3.fromRGB(28, 28, 34),
        SecondaryActive = Color3.fromRGB(38, 38, 46),
        SecondaryPressed = Color3.fromRGB(14, 14, 18),
        Tertiary = Color3.fromRGB(24, 24, 30),
        TertiaryHover = Color3.fromRGB(34, 36, 44),
        TertiaryActive = Color3.fromRGB(48, 50, 60),
        TertiaryPressed = Color3.fromRGB(20, 20, 26),
        Quaternary = Color3.fromRGB(14, 15, 18),
        QuaternaryHover = Color3.fromRGB(22, 24, 28),
        Separator = Color3.fromRGB(38, 50, 68),
        SeparatorTransparency = 0.20,
        BoxBackground = Color3.fromRGB(8, 8, 10),
        TextPrimary = Color3.fromRGB(220, 240, 255),
        TextSecondary = Color3.fromRGB(150, 180, 200),
        TextInactive = Color3.fromRGB(100, 120, 140),
        TextActive = Color3.fromRGB(255, 255, 255),
        Accent = Color3.fromRGB(100, 200, 255),
        TabAccent = Color3.fromRGB(140, 220, 255),
        TabIconActive = Color3.fromRGB(100, 200, 255),
        TabIconHover = Color3.fromRGB(180, 230, 255),
        TabIconInactive = Color3.fromRGB(100, 120, 140),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.02,
        TransparencySecondary = 0.75,
        TransparencyTertiary = 0.45
    },
    Obsidian = {
        Primary = Color3.fromRGB(14, 15, 18),
        Secondary = Color3.fromRGB(24, 25, 30),
        SecondaryHover = Color3.fromRGB(34, 36, 42),
        SecondaryActive = Color3.fromRGB(48, 50, 58),
        SecondaryPressed = Color3.fromRGB(20, 21, 26),
        Tertiary = Color3.fromRGB(30, 32, 38),
        TertiaryHover = Color3.fromRGB(42, 44, 52),
        TertiaryActive = Color3.fromRGB(56, 58, 68),
        TertiaryPressed = Color3.fromRGB(26, 28, 34),
        Quaternary = Color3.fromRGB(18, 19, 24),
        QuaternaryHover = Color3.fromRGB(28, 29, 36),
        Separator = Color3.fromRGB(48, 50, 58),
        SeparatorTransparency = 0.15,
        BoxBackground = Color3.fromRGB(12, 13, 16),
        TextPrimary = Color3.fromRGB(240, 241, 245),
        TextSecondary = Color3.fromRGB(170, 173, 180),
        TextInactive = Color3.fromRGB(115, 117, 125),
        TextActive = Color3.fromRGB(255, 255, 255),
        Accent = Color3.fromRGB(168, 85, 247),
        TabAccent = Color3.fromRGB(192, 132, 252),
        TabIconActive = Color3.fromRGB(192, 132, 252),
        TabIconHover = Color3.fromRGB(220, 220, 230),
        TabIconInactive = Color3.fromRGB(115, 117, 125),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.02,
        TransparencySecondary = 0.75,
        TransparencyTertiary = 0.45
    },

    CatppuccinMocha = {
        Primary = Color3.fromRGB(30, 30, 46),
        Secondary = Color3.fromRGB(49, 50, 68),
        SecondaryHover = Color3.fromRGB(69, 71, 90),
        SecondaryActive = Color3.fromRGB(88, 91, 112),
        SecondaryPressed = Color3.fromRGB(40, 41, 58),
        Tertiary = Color3.fromRGB(59, 61, 81),
        TertiaryHover = Color3.fromRGB(79, 82, 107),
        TertiaryActive = Color3.fromRGB(98, 102, 133),
        TertiaryPressed = Color3.fromRGB(50, 52, 71),
        Quaternary = Color3.fromRGB(36, 37, 52),
        QuaternaryHover = Color3.fromRGB(54, 56, 76),
        Separator = Color3.fromRGB(88, 91, 112),
        SeparatorTransparency = 0.25,
        BoxBackground = Color3.fromRGB(28, 28, 44),
        TextPrimary = Color3.fromRGB(205, 214, 244),
        TextSecondary = Color3.fromRGB(166, 173, 200),
        TextInactive = Color3.fromRGB(127, 132, 156),
        TextActive = Color3.fromRGB(220, 228, 255),
        Accent = Color3.fromRGB(203, 166, 247),
        TabAccent = Color3.fromRGB(221, 189, 252),
        TabIconActive = Color3.fromRGB(221, 189, 252),
        TabIconHover = Color3.fromRGB(186, 194, 222),
        TabIconInactive = Color3.fromRGB(127, 132, 156),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.01,
        TransparencySecondary = 0.70,
        TransparencyTertiary = 0.45
    },

    TokyoNight = {
        Primary = Color3.fromRGB(26, 27, 38),
        Secondary = Color3.fromRGB(41, 46, 66),
        SecondaryHover = Color3.fromRGB(58, 64, 90),
        SecondaryActive = Color3.fromRGB(73, 81, 118),
        SecondaryPressed = Color3.fromRGB(35, 39, 56),
        Tertiary = Color3.fromRGB(52, 57, 79),
        TertiaryHover = Color3.fromRGB(70, 77, 111),
        TertiaryActive = Color3.fromRGB(86, 94, 140),
        TertiaryPressed = Color3.fromRGB(44, 48, 67),
        Quaternary = Color3.fromRGB(32, 36, 54),
        QuaternaryHover = Color3.fromRGB(48, 54, 78),
        Separator = Color3.fromRGB(73, 81, 118),
        SeparatorTransparency = 0.30,
        BoxBackground = Color3.fromRGB(24, 25, 36),
        TextPrimary = Color3.fromRGB(192, 202, 245),
        TextSecondary = Color3.fromRGB(158, 168, 218),
        TextInactive = Color3.fromRGB(115, 122, 168),
        TextActive = Color3.fromRGB(207, 216, 255),
        Accent = Color3.fromRGB(125, 207, 255),
        TabAccent = Color3.fromRGB(158, 219, 255),
        TabIconActive = Color3.fromRGB(158, 219, 255),
        TabIconHover = Color3.fromRGB(167, 177, 211),
        TabIconInactive = Color3.fromRGB(115, 122, 168),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.01,
        TransparencySecondary = 0.73,
        TransparencyTertiary = 0.45
    },

    Ember = {
        Primary = Color3.fromRGB(16, 10, 8),
        Secondary = Color3.fromRGB(28, 18, 14),
        SecondaryHover = Color3.fromRGB(40, 26, 20),
        SecondaryActive = Color3.fromRGB(56, 36, 28),
        SecondaryPressed = Color3.fromRGB(22, 14, 11),
        Tertiary = Color3.fromRGB(36, 23, 18),
        TertiaryHover = Color3.fromRGB(50, 33, 26),
        TertiaryActive = Color3.fromRGB(66, 44, 34),
        TertiaryPressed = Color3.fromRGB(30, 19, 15),
        Quaternary = Color3.fromRGB(20, 13, 10),
        QuaternaryHover = Color3.fromRGB(32, 21, 16),
        Separator = Color3.fromRGB(72, 48, 36),
        SeparatorTransparency = 0.20,
        BoxBackground = Color3.fromRGB(12, 8, 6),
        TextPrimary = Color3.fromRGB(245, 232, 220),
        TextSecondary = Color3.fromRGB(195, 168, 148),
        TextInactive = Color3.fromRGB(130, 105, 88),
        TextActive = Color3.fromRGB(255, 248, 240),
        Accent = Color3.fromRGB(255, 140, 60),
        TabAccent = Color3.fromRGB(255, 170, 100),
        TabIconActive = Color3.fromRGB(255, 170, 100),
        TabIconHover = Color3.fromRGB(220, 190, 165),
        TabIconInactive = Color3.fromRGB(130, 105, 88),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.02,
        TransparencySecondary = 0.72,
        TransparencyTertiary = 0.45
    },

    Slate = {
        Primary = Color3.fromRGB(15, 20, 25),
        Secondary = Color3.fromRGB(24, 32, 40),
        SecondaryHover = Color3.fromRGB(34, 44, 55),
        SecondaryActive = Color3.fromRGB(46, 60, 74),
        SecondaryPressed = Color3.fromRGB(19, 26, 33),
        Tertiary = Color3.fromRGB(30, 40, 50),
        TertiaryHover = Color3.fromRGB(42, 55, 68),
        TertiaryActive = Color3.fromRGB(56, 72, 88),
        TertiaryPressed = Color3.fromRGB(25, 33, 42),
        Quaternary = Color3.fromRGB(18, 24, 30),
        QuaternaryHover = Color3.fromRGB(28, 37, 46),
        Separator = Color3.fromRGB(52, 68, 84),
        SeparatorTransparency = 0.22,
        BoxBackground = Color3.fromRGB(11, 15, 19),
        TextPrimary = Color3.fromRGB(220, 232, 242),
        TextSecondary = Color3.fromRGB(158, 176, 194),
        TextInactive = Color3.fromRGB(100, 118, 136),
        TextActive = Color3.fromRGB(240, 248, 255),
        Accent = Color3.fromRGB(56, 189, 248),
        TabAccent = Color3.fromRGB(103, 210, 255),
        TabIconActive = Color3.fromRGB(103, 210, 255),
        TabIconHover = Color3.fromRGB(170, 200, 224),
        TabIconInactive = Color3.fromRGB(100, 118, 136),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.02,
        TransparencySecondary = 0.74,
        TransparencyTertiary = 0.46
    },

    Rosewood = {
        Primary = Color3.fromRGB(16, 9, 12),
        Secondary = Color3.fromRGB(28, 16, 22),
        SecondaryHover = Color3.fromRGB(40, 23, 32),
        SecondaryActive = Color3.fromRGB(55, 32, 44),
        SecondaryPressed = Color3.fromRGB(22, 13, 18),
        Tertiary = Color3.fromRGB(36, 21, 29),
        TertiaryHover = Color3.fromRGB(50, 30, 42),
        TertiaryActive = Color3.fromRGB(66, 40, 56),
        TertiaryPressed = Color3.fromRGB(30, 17, 24),
        Quaternary = Color3.fromRGB(19, 11, 15),
        QuaternaryHover = Color3.fromRGB(32, 19, 26),
        Separator = Color3.fromRGB(70, 42, 58),
        SeparatorTransparency = 0.20,
        BoxBackground = Color3.fromRGB(12, 7, 10),
        TextPrimary = Color3.fromRGB(246, 230, 236),
        TextSecondary = Color3.fromRGB(198, 168, 180),
        TextInactive = Color3.fromRGB(134, 106, 118),
        TextActive = Color3.fromRGB(255, 244, 248),
        Accent = Color3.fromRGB(251, 113, 133),
        TabAccent = Color3.fromRGB(255, 150, 168),
        TabIconActive = Color3.fromRGB(255, 150, 168),
        TabIconHover = Color3.fromRGB(220, 185, 198),
        TabIconInactive = Color3.fromRGB(134, 106, 118),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.02,
        TransparencySecondary = 0.72,
        TransparencyTertiary = 0.45
    },

    Forest = {
        Primary = Color3.fromRGB(10, 15, 12),
        Secondary = Color3.fromRGB(18, 27, 22),
        SecondaryHover = Color3.fromRGB(26, 39, 32),
        SecondaryActive = Color3.fromRGB(36, 54, 44),
        SecondaryPressed = Color3.fromRGB(14, 21, 17),
        Tertiary = Color3.fromRGB(23, 35, 28),
        TertiaryHover = Color3.fromRGB(33, 50, 40),
        TertiaryActive = Color3.fromRGB(44, 66, 54),
        TertiaryPressed = Color3.fromRGB(18, 28, 23),
        Quaternary = Color3.fromRGB(12, 18, 15),
        QuaternaryHover = Color3.fromRGB(22, 33, 27),
        Separator = Color3.fromRGB(44, 66, 54),
        SeparatorTransparency = 0.22,
        BoxBackground = Color3.fromRGB(8, 12, 10),
        TextPrimary = Color3.fromRGB(220, 240, 228),
        TextSecondary = Color3.fromRGB(158, 192, 170),
        TextInactive = Color3.fromRGB(98, 130, 112),
        TextActive = Color3.fromRGB(240, 255, 245),
        Accent = Color3.fromRGB(110, 231, 183),
        TabAccent = Color3.fromRGB(150, 246, 205),
        TabIconActive = Color3.fromRGB(150, 246, 205),
        TabIconHover = Color3.fromRGB(170, 210, 188),
        TabIconInactive = Color3.fromRGB(98, 130, 112),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.02,
        TransparencySecondary = 0.74,
        TransparencyTertiary = 0.46
    },

    Abyss = {
        Primary = Color3.fromRGB(5, 5, 10),
        Secondary = Color3.fromRGB(10, 10, 20),
        SecondaryHover = Color3.fromRGB(16, 16, 32),
        SecondaryActive = Color3.fromRGB(24, 24, 46),
        SecondaryPressed = Color3.fromRGB(8, 8, 16),
        Tertiary = Color3.fromRGB(14, 14, 28),
        TertiaryHover = Color3.fromRGB(22, 22, 44),
        TertiaryActive = Color3.fromRGB(32, 32, 60),
        TertiaryPressed = Color3.fromRGB(11, 11, 22),
        Quaternary = Color3.fromRGB(7, 7, 13),
        QuaternaryHover = Color3.fromRGB(14, 14, 26),
        Separator = Color3.fromRGB(36, 36, 72),
        SeparatorTransparency = 0.18,
        BoxBackground = Color3.fromRGB(3, 3, 7),
        TextPrimary = Color3.fromRGB(200, 210, 255),
        TextSecondary = Color3.fromRGB(140, 152, 210),
        TextInactive = Color3.fromRGB(80, 88, 140),
        TextActive = Color3.fromRGB(220, 228, 255),
        Accent = Color3.fromRGB(180, 120, 255),
        TabAccent = Color3.fromRGB(200, 155, 255),
        TabIconActive = Color3.fromRGB(200, 155, 255),
        TabIconHover = Color3.fromRGB(170, 175, 220),
        TabIconInactive = Color3.fromRGB(80, 88, 140),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.0,
        TransparencySecondary = 0.80,
        TransparencyTertiary = 0.50
    },

    NordAurora = {
        Primary = Color3.fromRGB(36, 40, 49),
        Secondary = Color3.fromRGB(49, 54, 66),
        SecondaryHover = Color3.fromRGB(62, 68, 83),
        SecondaryActive = Color3.fromRGB(76, 86, 106),
        SecondaryPressed = Color3.fromRGB(42, 46, 57),
        Tertiary = Color3.fromRGB(59, 66, 82),
        TertiaryHover = Color3.fromRGB(74, 84, 104),
        TertiaryActive = Color3.fromRGB(91, 103, 128),
        TertiaryPressed = Color3.fromRGB(50, 56, 70),
        Quaternary = Color3.fromRGB(42, 47, 58),
        QuaternaryHover = Color3.fromRGB(56, 63, 78),
        Separator = Color3.fromRGB(76, 86, 106),
        SeparatorTransparency = 0.28,
        BoxBackground = Color3.fromRGB(34, 38, 46),
        TextPrimary = Color3.fromRGB(236, 239, 244),
        TextSecondary = Color3.fromRGB(189, 196, 212),
        TextInactive = Color3.fromRGB(129, 138, 160),
        TextActive = Color3.fromRGB(250, 252, 255),
        Accent = Color3.fromRGB(136, 192, 208),
        TabAccent = Color3.fromRGB(163, 212, 225),
        TabIconActive = Color3.fromRGB(163, 212, 225),
        TabIconHover = Color3.fromRGB(199, 208, 222),
        TabIconInactive = Color3.fromRGB(129, 138, 160),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.01,
        TransparencySecondary = 0.70,
        TransparencyTertiary = 0.44
    },

    Dracula = {
        Primary = Color3.fromRGB(40, 42, 54),
        Secondary = Color3.fromRGB(52, 55, 70),
        SecondaryHover = Color3.fromRGB(66, 70, 90),
        SecondaryActive = Color3.fromRGB(82, 86, 110),
        SecondaryPressed = Color3.fromRGB(46, 48, 62),
        Tertiary = Color3.fromRGB(60, 64, 82),
        TertiaryHover = Color3.fromRGB(76, 81, 104),
        TertiaryActive = Color3.fromRGB(94, 100, 128),
        TertiaryPressed = Color3.fromRGB(52, 56, 72),
        Quaternary = Color3.fromRGB(46, 48, 62),
        QuaternaryHover = Color3.fromRGB(60, 64, 82),
        Separator = Color3.fromRGB(82, 86, 110),
        SeparatorTransparency = 0.26,
        BoxBackground = Color3.fromRGB(36, 38, 48),
        TextPrimary = Color3.fromRGB(248, 248, 242),
        TextSecondary = Color3.fromRGB(200, 200, 198),
        TextInactive = Color3.fromRGB(140, 140, 148),
        TextActive = Color3.fromRGB(255, 255, 250),
        Accent = Color3.fromRGB(189, 147, 249),
        TabAccent = Color3.fromRGB(207, 170, 255),
        TabIconActive = Color3.fromRGB(207, 170, 255),
        TabIconHover = Color3.fromRGB(210, 205, 225),
        TabIconInactive = Color3.fromRGB(140, 140, 148),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.01,
        TransparencySecondary = 0.70,
        TransparencyTertiary = 0.44
    },

    GruvboxDark = {
        Primary = Color3.fromRGB(40, 40, 40),
        Secondary = Color3.fromRGB(60, 56, 54),
        SecondaryHover = Color3.fromRGB(80, 73, 69),
        SecondaryActive = Color3.fromRGB(102, 92, 84),
        SecondaryPressed = Color3.fromRGB(50, 48, 45),
        Tertiary = Color3.fromRGB(69, 65, 62),
        TertiaryHover = Color3.fromRGB(90, 84, 79),
        TertiaryActive = Color3.fromRGB(112, 104, 97),
        TertiaryPressed = Color3.fromRGB(58, 55, 52),
        Quaternary = Color3.fromRGB(50, 48, 45),
        QuaternaryHover = Color3.fromRGB(68, 64, 60),
        Separator = Color3.fromRGB(102, 92, 84),
        SeparatorTransparency = 0.24,
        BoxBackground = Color3.fromRGB(32, 32, 32),
        TextPrimary = Color3.fromRGB(235, 219, 178),
        TextSecondary = Color3.fromRGB(189, 174, 147),
        TextInactive = Color3.fromRGB(124, 111, 100),
        TextActive = Color3.fromRGB(251, 241, 199),
        Accent = Color3.fromRGB(250, 189, 47),
        TabAccent = Color3.fromRGB(255, 210, 100),
        TabIconActive = Color3.fromRGB(255, 210, 100),
        TabIconHover = Color3.fromRGB(210, 195, 160),
        TabIconInactive = Color3.fromRGB(124, 111, 100),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.01,
        TransparencySecondary = 0.68,
        TransparencyTertiary = 0.43
    },

    Phantom = {
        Primary = Color3.fromRGB(6, 6, 8),
        Secondary = Color3.fromRGB(14, 14, 18),
        SecondaryHover = Color3.fromRGB(22, 22, 29),
        SecondaryActive = Color3.fromRGB(32, 32, 42),
        SecondaryPressed = Color3.fromRGB(10, 10, 13),
        Tertiary = Color3.fromRGB(19, 19, 26),
        TertiaryHover = Color3.fromRGB(28, 28, 38),
        TertiaryActive = Color3.fromRGB(39, 39, 52),
        TertiaryPressed = Color3.fromRGB(15, 15, 21),
        Quaternary = Color3.fromRGB(9, 9, 12),
        QuaternaryHover = Color3.fromRGB(18, 18, 24),
        Separator = Color3.fromRGB(46, 46, 62),
        SeparatorTransparency = 0.16,
        BoxBackground = Color3.fromRGB(4, 4, 6),
        TextPrimary = Color3.fromRGB(220, 222, 232),
        TextSecondary = Color3.fromRGB(152, 154, 172),
        TextInactive = Color3.fromRGB(90, 92, 110),
        TextActive = Color3.fromRGB(240, 242, 255),
        Accent = Color3.fromRGB(124, 124, 255),
        TabAccent = Color3.fromRGB(158, 158, 255),
        TabIconActive = Color3.fromRGB(158, 158, 255),
        TabIconHover = Color3.fromRGB(180, 180, 215),
        TabIconInactive = Color3.fromRGB(90, 92, 110),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.0,
        TransparencySecondary = 0.82,
        TransparencyTertiary = 0.52
    },

    TurboTeal = {
        Primary = Color3.fromRGB(8, 18, 20),
        Secondary = Color3.fromRGB(13, 30, 34),
        SecondaryHover = Color3.fromRGB(18, 44, 50),
        SecondaryActive = Color3.fromRGB(26, 60, 68),
        SecondaryPressed = Color3.fromRGB(10, 24, 27),
        Tertiary = Color3.fromRGB(16, 38, 44),
        TertiaryHover = Color3.fromRGB(24, 55, 63),
        TertiaryActive = Color3.fromRGB(33, 73, 83),
        TertiaryPressed = Color3.fromRGB(13, 31, 36),
        Quaternary = Color3.fromRGB(10, 22, 26),
        QuaternaryHover = Color3.fromRGB(18, 36, 42),
        Separator = Color3.fromRGB(36, 86, 100),
        SeparatorTransparency = 0.22,
        BoxBackground = Color3.fromRGB(6, 14, 16),
        TextPrimary = Color3.fromRGB(200, 240, 244),
        TextSecondary = Color3.fromRGB(140, 196, 205),
        TextInactive = Color3.fromRGB(80, 136, 146),
        TextActive = Color3.fromRGB(220, 250, 254),
        Accent = Color3.fromRGB(45, 212, 191),
        TabAccent = Color3.fromRGB(90, 230, 212),
        TabIconActive = Color3.fromRGB(90, 230, 212),
        TabIconHover = Color3.fromRGB(140, 205, 210),
        TabIconInactive = Color3.fromRGB(80, 136, 146),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.02,
        TransparencySecondary = 0.74,
        TransparencyTertiary = 0.46
    },

    Nebula = {
        Primary = Color3.fromRGB(12, 8, 22),
        Secondary = Color3.fromRGB(22, 14, 40),
        SecondaryHover = Color3.fromRGB(32, 21, 58),
        SecondaryActive = Color3.fromRGB(44, 30, 78),
        SecondaryPressed = Color3.fromRGB(17, 11, 32),
        Tertiary = Color3.fromRGB(28, 18, 52),
        TertiaryHover = Color3.fromRGB(40, 27, 74),
        TertiaryActive = Color3.fromRGB(54, 37, 98),
        TertiaryPressed = Color3.fromRGB(23, 15, 43),
        Quaternary = Color3.fromRGB(15, 10, 28),
        QuaternaryHover = Color3.fromRGB(26, 18, 48),
        Separator = Color3.fromRGB(72, 48, 130),
        SeparatorTransparency = 0.24,
        BoxBackground = Color3.fromRGB(9, 6, 17),
        TextPrimary = Color3.fromRGB(222, 210, 255),
        TextSecondary = Color3.fromRGB(172, 155, 218),
        TextInactive = Color3.fromRGB(110, 94, 158),
        TextActive = Color3.fromRGB(240, 232, 255),
        Accent = Color3.fromRGB(196, 100, 255),
        TabAccent = Color3.fromRGB(216, 140, 255),
        TabIconActive = Color3.fromRGB(216, 140, 255),
        TabIconHover = Color3.fromRGB(185, 162, 228),
        TabIconInactive = Color3.fromRGB(110, 94, 158),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.02,
        TransparencySecondary = 0.74,
        TransparencyTertiary = 0.47
    },

    Sakura = {
        Primary = Color3.fromRGB(20, 12, 16),
        Secondary = Color3.fromRGB(34, 20, 28),
        SecondaryHover = Color3.fromRGB(48, 29, 40),
        SecondaryActive = Color3.fromRGB(64, 39, 54),
        SecondaryPressed = Color3.fromRGB(27, 16, 22),
        Tertiary = Color3.fromRGB(43, 26, 36),
        TertiaryHover = Color3.fromRGB(59, 36, 50),
        TertiaryActive = Color3.fromRGB(76, 48, 66),
        TertiaryPressed = Color3.fromRGB(36, 22, 30),
        Quaternary = Color3.fromRGB(24, 15, 20),
        QuaternaryHover = Color3.fromRGB(38, 24, 32),
        Separator = Color3.fromRGB(90, 54, 74),
        SeparatorTransparency = 0.22,
        BoxBackground = Color3.fromRGB(15, 9, 12),
        TextPrimary = Color3.fromRGB(252, 228, 236),
        TextSecondary = Color3.fromRGB(210, 172, 188),
        TextInactive = Color3.fromRGB(148, 108, 126),
        TextActive = Color3.fromRGB(255, 242, 248),
        Accent = Color3.fromRGB(255, 145, 175),
        TabAccent = Color3.fromRGB(255, 178, 200),
        TabIconActive = Color3.fromRGB(255, 178, 200),
        TabIconHover = Color3.fromRGB(228, 185, 202),
        TabIconInactive = Color3.fromRGB(148, 108, 126),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.02,
        TransparencySecondary = 0.72,
        TransparencyTertiary = 0.45
    },

    Crimson = {
        Primary = Color3.fromRGB(18, 5, 5),
        Secondary = Color3.fromRGB(34, 9, 9),
        SecondaryHover = Color3.fromRGB(52, 14, 14),
        SecondaryActive = Color3.fromRGB(72, 20, 20),
        SecondaryPressed = Color3.fromRGB(26, 7, 7),
        Tertiary = Color3.fromRGB(44, 12, 12),
        TertiaryHover = Color3.fromRGB(62, 18, 18),
        TertiaryActive = Color3.fromRGB(82, 26, 26),
        TertiaryPressed = Color3.fromRGB(36, 10, 10),
        Quaternary = Color3.fromRGB(22, 7, 7),
        QuaternaryHover = Color3.fromRGB(38, 12, 12),
        Separator = Color3.fromRGB(90, 28, 28),
        SeparatorTransparency = 0.18,
        BoxBackground = Color3.fromRGB(12, 3, 3),
        TextPrimary = Color3.fromRGB(255, 224, 224),
        TextSecondary = Color3.fromRGB(210, 160, 160),
        TextInactive = Color3.fromRGB(148, 98, 98),
        TextActive = Color3.fromRGB(255, 240, 240),
        Accent = Color3.fromRGB(255, 55, 55),
        TabAccent = Color3.fromRGB(255, 100, 100),
        TabIconActive = Color3.fromRGB(255, 100, 100),
        TabIconHover = Color3.fromRGB(225, 170, 170),
        TabIconInactive = Color3.fromRGB(148, 98, 98),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.02,
        TransparencySecondary = 0.72,
        TransparencyTertiary = 0.45
    },

    Amber = {
        Primary = Color3.fromRGB(14, 11, 4),
        Secondary = Color3.fromRGB(26, 20, 6),
        SecondaryHover = Color3.fromRGB(40, 31, 9),
        SecondaryActive = Color3.fromRGB(56, 44, 13),
        SecondaryPressed = Color3.fromRGB(20, 16, 5),
        Tertiary = Color3.fromRGB(34, 27, 8),
        TertiaryHover = Color3.fromRGB(50, 40, 12),
        TertiaryActive = Color3.fromRGB(68, 54, 16),
        TertiaryPressed = Color3.fromRGB(28, 22, 6),
        Quaternary = Color3.fromRGB(17, 13, 4),
        QuaternaryHover = Color3.fromRGB(30, 24, 8),
        Separator = Color3.fromRGB(80, 62, 18),
        SeparatorTransparency = 0.20,
        BoxBackground = Color3.fromRGB(10, 8, 2),
        TextPrimary = Color3.fromRGB(255, 240, 190),
        TextSecondary = Color3.fromRGB(210, 185, 120),
        TextInactive = Color3.fromRGB(148, 124, 72),
        TextActive = Color3.fromRGB(255, 252, 220),
        Accent = Color3.fromRGB(255, 204, 0),
        TabAccent = Color3.fromRGB(255, 220, 60),
        TabIconActive = Color3.fromRGB(255, 220, 60),
        TabIconHover = Color3.fromRGB(220, 195, 140),
        TabIconInactive = Color3.fromRGB(148, 124, 72),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.02,
        TransparencySecondary = 0.72,
        TransparencyTertiary = 0.45
    },

    Dusk = {
        Primary = Color3.fromRGB(14, 10, 20),
        Secondary = Color3.fromRGB(26, 16, 36),
        SecondaryHover = Color3.fromRGB(40, 24, 52),
        SecondaryActive = Color3.fromRGB(56, 34, 70),
        SecondaryPressed = Color3.fromRGB(20, 13, 28),
        Tertiary = Color3.fromRGB(34, 21, 48),
        TertiaryHover = Color3.fromRGB(50, 31, 68),
        TertiaryActive = Color3.fromRGB(68, 43, 90),
        TertiaryPressed = Color3.fromRGB(28, 17, 40),
        Quaternary = Color3.fromRGB(17, 12, 24),
        QuaternaryHover = Color3.fromRGB(30, 21, 42),
        Separator = Color3.fromRGB(80, 50, 110),
        SeparatorTransparency = 0.20,
        BoxBackground = Color3.fromRGB(10, 7, 15),
        TextPrimary = Color3.fromRGB(248, 224, 210),
        TextSecondary = Color3.fromRGB(200, 165, 185),
        TextInactive = Color3.fromRGB(138, 108, 128),
        TextActive = Color3.fromRGB(255, 240, 225),
        Accent = Color3.fromRGB(255, 110, 60),
        TabAccent = Color3.fromRGB(255, 148, 80),
        TabIconActive = Color3.fromRGB(255, 148, 80),
        TabIconHover = Color3.fromRGB(215, 175, 185),
        TabIconInactive = Color3.fromRGB(138, 108, 128),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.02,
        TransparencySecondary = 0.73,
        TransparencyTertiary = 0.46
    },

    Verdant = {
        Primary = Color3.fromRGB(6, 18, 8),
        Secondary = Color3.fromRGB(10, 30, 13),
        SecondaryHover = Color3.fromRGB(16, 44, 20),
        SecondaryActive = Color3.fromRGB(22, 60, 28),
        SecondaryPressed = Color3.fromRGB(8, 24, 10),
        Tertiary = Color3.fromRGB(13, 38, 17),
        TertiaryHover = Color3.fromRGB(20, 55, 26),
        TertiaryActive = Color3.fromRGB(28, 74, 36),
        TertiaryPressed = Color3.fromRGB(10, 31, 14),
        Quaternary = Color3.fromRGB(8, 22, 10),
        QuaternaryHover = Color3.fromRGB(14, 36, 17),
        Separator = Color3.fromRGB(30, 90, 42),
        SeparatorTransparency = 0.20,
        BoxBackground = Color3.fromRGB(4, 13, 6),
        TextPrimary = Color3.fromRGB(200, 255, 210),
        TextSecondary = Color3.fromRGB(140, 205, 155),
        TextInactive = Color3.fromRGB(80, 140, 96),
        TextActive = Color3.fromRGB(220, 255, 228),
        Accent = Color3.fromRGB(50, 220, 80),
        TabAccent = Color3.fromRGB(90, 240, 118),
        TabIconActive = Color3.fromRGB(90, 240, 118),
        TabIconHover = Color3.fromRGB(148, 210, 162),
        TabIconInactive = Color3.fromRGB(80, 140, 96),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.02,
        TransparencySecondary = 0.74,
        TransparencyTertiary = 0.46
    },

    Tungsten = {
        Primary = Color3.fromRGB(20, 20, 20),
        Secondary = Color3.fromRGB(36, 36, 36),
        SecondaryHover = Color3.fromRGB(52, 52, 52),
        SecondaryActive = Color3.fromRGB(70, 70, 70),
        SecondaryPressed = Color3.fromRGB(28, 28, 28),
        Tertiary = Color3.fromRGB(46, 46, 46),
        TertiaryHover = Color3.fromRGB(64, 64, 64),
        TertiaryActive = Color3.fromRGB(84, 84, 84),
        TertiaryPressed = Color3.fromRGB(38, 38, 38),
        Quaternary = Color3.fromRGB(26, 26, 26),
        QuaternaryHover = Color3.fromRGB(42, 42, 42),
        Separator = Color3.fromRGB(80, 80, 80),
        SeparatorTransparency = 0.18,
        BoxBackground = Color3.fromRGB(14, 14, 14),
        TextPrimary = Color3.fromRGB(230, 230, 230),
        TextSecondary = Color3.fromRGB(170, 170, 170),
        TextInactive = Color3.fromRGB(108, 108, 108),
        TextActive = Color3.fromRGB(255, 255, 255),
        Accent = Color3.fromRGB(220, 180, 60),
        TabAccent = Color3.fromRGB(240, 205, 90),
        TabIconActive = Color3.fromRGB(240, 205, 90),
        TabIconHover = Color3.fromRGB(195, 190, 170),
        TabIconInactive = Color3.fromRGB(108, 108, 108),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.01,
        TransparencySecondary = 0.76,
        TransparencyTertiary = 0.48
    },

    Pearl = {
        Primary = Color3.fromRGB(248, 248, 250),
        Secondary = Color3.fromRGB(238, 238, 244),
        SecondaryHover = Color3.fromRGB(228, 228, 236),
        SecondaryActive = Color3.fromRGB(214, 214, 226),
        SecondaryPressed = Color3.fromRGB(232, 232, 240),
        Tertiary = Color3.fromRGB(224, 224, 232),
        TertiaryHover = Color3.fromRGB(210, 210, 222),
        TertiaryActive = Color3.fromRGB(196, 196, 212),
        TertiaryPressed = Color3.fromRGB(218, 218, 228),
        Quaternary = Color3.fromRGB(242, 242, 246),
        QuaternaryHover = Color3.fromRGB(232, 232, 238),
        Separator = Color3.fromRGB(200, 200, 216),
        SeparatorTransparency = 0.30,
        BoxBackground = Color3.fromRGB(255, 255, 255),
        TextPrimary = Color3.fromRGB(28, 28, 40),
        TextSecondary = Color3.fromRGB(80, 80, 108),
        TextInactive = Color3.fromRGB(148, 148, 172),
        TextActive = Color3.fromRGB(12, 12, 22),
        Accent = Color3.fromRGB(109, 40, 217),
        TabAccent = Color3.fromRGB(124, 58, 237),
        TabIconActive = Color3.fromRGB(109, 40, 217),
        TabIconHover = Color3.fromRGB(60, 60, 100),
        TabIconInactive = Color3.fromRGB(148, 148, 172),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.0,
        TransparencySecondary = 0.40,
        TransparencyTertiary = 0.20
    },

    Cloud = {
        Primary = Color3.fromRGB(244, 246, 252),
        Secondary = Color3.fromRGB(232, 236, 248),
        SecondaryHover = Color3.fromRGB(218, 224, 242),
        SecondaryActive = Color3.fromRGB(200, 210, 236),
        SecondaryPressed = Color3.fromRGB(226, 230, 244),
        Tertiary = Color3.fromRGB(214, 220, 240),
        TertiaryHover = Color3.fromRGB(198, 208, 234),
        TertiaryActive = Color3.fromRGB(180, 194, 228),
        TertiaryPressed = Color3.fromRGB(207, 214, 237),
        Quaternary = Color3.fromRGB(238, 241, 250),
        QuaternaryHover = Color3.fromRGB(226, 230, 244),
        Separator = Color3.fromRGB(186, 198, 232),
        SeparatorTransparency = 0.28,
        BoxBackground = Color3.fromRGB(252, 252, 255),
        TextPrimary = Color3.fromRGB(22, 28, 52),
        TextSecondary = Color3.fromRGB(72, 88, 140),
        TextInactive = Color3.fromRGB(140, 152, 196),
        TextActive = Color3.fromRGB(10, 14, 34),
        Accent = Color3.fromRGB(79, 70, 229),
        TabAccent = Color3.fromRGB(99, 90, 245),
        TabIconActive = Color3.fromRGB(79, 70, 229),
        TabIconHover = Color3.fromRGB(38, 48, 100),
        TabIconInactive = Color3.fromRGB(140, 152, 196),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.0,
        TransparencySecondary = 0.38,
        TransparencyTertiary = 0.18
    },

    Linen = {
        Primary = Color3.fromRGB(250, 246, 240),
        Secondary = Color3.fromRGB(240, 234, 224),
        SecondaryHover = Color3.fromRGB(228, 220, 208),
        SecondaryActive = Color3.fromRGB(212, 202, 188),
        SecondaryPressed = Color3.fromRGB(235, 228, 218),
        Tertiary = Color3.fromRGB(222, 214, 202),
        TertiaryHover = Color3.fromRGB(208, 198, 184),
        TertiaryActive = Color3.fromRGB(192, 180, 164),
        TertiaryPressed = Color3.fromRGB(215, 207, 195),
        Quaternary = Color3.fromRGB(246, 242, 236),
        QuaternaryHover = Color3.fromRGB(235, 229, 221),
        Separator = Color3.fromRGB(196, 182, 164),
        SeparatorTransparency = 0.26,
        BoxBackground = Color3.fromRGB(255, 252, 248),
        TextPrimary = Color3.fromRGB(40, 30, 20),
        TextSecondary = Color3.fromRGB(100, 80, 60),
        TextInactive = Color3.fromRGB(160, 140, 120),
        TextActive = Color3.fromRGB(20, 14, 8),
        Accent = Color3.fromRGB(180, 80, 40),
        TabAccent = Color3.fromRGB(204, 100, 56),
        TabIconActive = Color3.fromRGB(180, 80, 40),
        TabIconHover = Color3.fromRGB(70, 50, 30),
        TabIconInactive = Color3.fromRGB(160, 140, 120),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.0,
        TransparencySecondary = 0.35,
        TransparencyTertiary = 0.16
    },

    Parchment = {
        Primary = Color3.fromRGB(248, 240, 224),
        Secondary = Color3.fromRGB(236, 226, 208),
        SecondaryHover = Color3.fromRGB(222, 210, 190),
        SecondaryActive = Color3.fromRGB(206, 192, 170),
        SecondaryPressed = Color3.fromRGB(230, 219, 200),
        Tertiary = Color3.fromRGB(216, 204, 183),
        TertiaryHover = Color3.fromRGB(200, 186, 163),
        TertiaryActive = Color3.fromRGB(182, 166, 143),
        TertiaryPressed = Color3.fromRGB(208, 196, 176),
        Quaternary = Color3.fromRGB(242, 234, 218),
        QuaternaryHover = Color3.fromRGB(230, 220, 202),
        Separator = Color3.fromRGB(186, 168, 144),
        SeparatorTransparency = 0.24,
        BoxBackground = Color3.fromRGB(254, 248, 234),
        TextPrimary = Color3.fromRGB(44, 32, 14),
        TextSecondary = Color3.fromRGB(100, 78, 48),
        TextInactive = Color3.fromRGB(160, 136, 104),
        TextActive = Color3.fromRGB(26, 18, 6),
        Accent = Color3.fromRGB(140, 80, 20),
        TabAccent = Color3.fromRGB(168, 102, 36),
        TabIconActive = Color3.fromRGB(140, 80, 20),
        TabIconHover = Color3.fromRGB(60, 40, 12),
        TabIconInactive = Color3.fromRGB(160, 136, 104),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.0,
        TransparencySecondary = 0.32,
        TransparencyTertiary = 0.15
    },

    Sage = {
        Primary = Color3.fromRGB(238, 244, 240),
        Secondary = Color3.fromRGB(224, 234, 228),
        SecondaryHover = Color3.fromRGB(208, 222, 214),
        SecondaryActive = Color3.fromRGB(190, 208, 198),
        SecondaryPressed = Color3.fromRGB(218, 229, 222),
        Tertiary = Color3.fromRGB(206, 220, 212),
        TertiaryHover = Color3.fromRGB(188, 206, 196),
        TertiaryActive = Color3.fromRGB(168, 190, 178),
        TertiaryPressed = Color3.fromRGB(198, 214, 206),
        Quaternary = Color3.fromRGB(232, 240, 235),
        QuaternaryHover = Color3.fromRGB(218, 229, 222),
        Separator = Color3.fromRGB(164, 194, 176),
        SeparatorTransparency = 0.26,
        BoxBackground = Color3.fromRGB(248, 252, 250),
        TextPrimary = Color3.fromRGB(20, 40, 30),
        TextSecondary = Color3.fromRGB(60, 100, 80),
        TextInactive = Color3.fromRGB(120, 156, 140),
        TextActive = Color3.fromRGB(8, 22, 15),
        Accent = Color3.fromRGB(30, 130, 90),
        TabAccent = Color3.fromRGB(44, 158, 112),
        TabIconActive = Color3.fromRGB(30, 130, 90),
        TabIconHover = Color3.fromRGB(20, 60, 42),
        TabIconInactive = Color3.fromRGB(120, 156, 140),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.0,
        TransparencySecondary = 0.34,
        TransparencyTertiary = 0.16
    },

    Harajuku = {
        Primary = Color3.fromRGB(255, 240, 248),
        Secondary = Color3.fromRGB(255, 224, 240),
        SecondaryHover = Color3.fromRGB(255, 206, 230),
        SecondaryActive = Color3.fromRGB(254, 186, 218),
        SecondaryPressed = Color3.fromRGB(255, 216, 236),
        Tertiary = Color3.fromRGB(252, 210, 232),
        TertiaryHover = Color3.fromRGB(248, 190, 220),
        TertiaryActive = Color3.fromRGB(242, 168, 206),
        TertiaryPressed = Color3.fromRGB(251, 202, 227),
        Quaternary = Color3.fromRGB(255, 232, 244),
        QuaternaryHover = Color3.fromRGB(255, 218, 236),
        Separator = Color3.fromRGB(240, 160, 210),
        SeparatorTransparency = 0.28,
        BoxBackground = Color3.fromRGB(255, 248, 252),
        TextPrimary = Color3.fromRGB(100, 20, 60),
        TextSecondary = Color3.fromRGB(180, 60, 120),
        TextInactive = Color3.fromRGB(210, 140, 175),
        TextActive = Color3.fromRGB(70, 8, 40),
        Accent = Color3.fromRGB(255, 60, 140),
        TabAccent = Color3.fromRGB(255, 100, 168),
        TabIconActive = Color3.fromRGB(255, 60, 140),
        TabIconHover = Color3.fromRGB(90, 16, 52),
        TabIconInactive = Color3.fromRGB(210, 140, 175),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.0,
        TransparencySecondary = 0.34,
        TransparencyTertiary = 0.16
    },

    Pastel = {
        Primary = Color3.fromRGB(252, 244, 255),
        Secondary = Color3.fromRGB(244, 228, 255),
        SecondaryHover = Color3.fromRGB(234, 210, 255),
        SecondaryActive = Color3.fromRGB(222, 190, 252),
        SecondaryPressed = Color3.fromRGB(239, 220, 255),
        Tertiary = Color3.fromRGB(228, 200, 252),
        TertiaryHover = Color3.fromRGB(214, 178, 248),
        TertiaryActive = Color3.fromRGB(198, 154, 242),
        TertiaryPressed = Color3.fromRGB(222, 192, 250),
        Quaternary = Color3.fromRGB(248, 236, 255),
        QuaternaryHover = Color3.fromRGB(238, 220, 255),
        Separator = Color3.fromRGB(204, 158, 240),
        SeparatorTransparency = 0.30,
        BoxBackground = Color3.fromRGB(255, 250, 255),
        TextPrimary = Color3.fromRGB(52, 14, 80),
        TextSecondary = Color3.fromRGB(118, 48, 162),
        TextInactive = Color3.fromRGB(174, 120, 210),
        TextActive = Color3.fromRGB(32, 6, 52),
        Accent = Color3.fromRGB(188, 80, 255),
        TabAccent = Color3.fromRGB(210, 120, 255),
        TabIconActive = Color3.fromRGB(188, 80, 255),
        TabIconHover = Color3.fromRGB(56, 12, 90),
        TabIconInactive = Color3.fromRGB(174, 120, 210),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.0,
        TransparencySecondary = 0.35,
        TransparencyTertiary = 0.17
    },

    Bubblegum = {
        Primary = Color3.fromRGB(255, 238, 248),
        Secondary = Color3.fromRGB(255, 214, 238),
        SecondaryHover = Color3.fromRGB(255, 190, 226),
        SecondaryActive = Color3.fromRGB(252, 164, 212),
        SecondaryPressed = Color3.fromRGB(255, 204, 233),
        Tertiary = Color3.fromRGB(250, 178, 222),
        TertiaryHover = Color3.fromRGB(244, 154, 208),
        TertiaryActive = Color3.fromRGB(236, 128, 192),
        TertiaryPressed = Color3.fromRGB(248, 168, 216),
        Quaternary = Color3.fromRGB(255, 228, 243),
        QuaternaryHover = Color3.fromRGB(255, 210, 234),
        Separator = Color3.fromRGB(238, 130, 196),
        SeparatorTransparency = 0.26,
        BoxBackground = Color3.fromRGB(255, 246, 252),
        TextPrimary = Color3.fromRGB(96, 10, 56),
        TextSecondary = Color3.fromRGB(192, 40, 120),
        TextInactive = Color3.fromRGB(226, 130, 178),
        TextActive = Color3.fromRGB(64, 4, 36),
        Accent = Color3.fromRGB(255, 20, 120),
        TabAccent = Color3.fromRGB(255, 70, 155),
        TabIconActive = Color3.fromRGB(255, 20, 120),
        TabIconHover = Color3.fromRGB(80, 6, 44),
        TabIconInactive = Color3.fromRGB(226, 130, 178),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.0,
        TransparencySecondary = 0.34,
        TransparencyTertiary = 0.16
    },

    CottonCandy = {
        Primary = Color3.fromRGB(240, 248, 255),
        Secondary = Color3.fromRGB(220, 236, 255),
        SecondaryHover = Color3.fromRGB(198, 222, 255),
        SecondaryActive = Color3.fromRGB(174, 206, 255),
        SecondaryPressed = Color3.fromRGB(210, 230, 255),
        Tertiary = Color3.fromRGB(192, 218, 255),
        TertiaryHover = Color3.fromRGB(166, 202, 252),
        TertiaryActive = Color3.fromRGB(140, 184, 248),
        TertiaryPressed = Color3.fromRGB(180, 212, 254),
        Quaternary = Color3.fromRGB(230, 242, 255),
        QuaternaryHover = Color3.fromRGB(212, 230, 255),
        Separator = Color3.fromRGB(148, 196, 255),
        SeparatorTransparency = 0.28,
        BoxBackground = Color3.fromRGB(248, 252, 255),
        TextPrimary = Color3.fromRGB(10, 36, 80),
        TextSecondary = Color3.fromRGB(40, 100, 190),
        TextInactive = Color3.fromRGB(110, 158, 220),
        TextActive = Color3.fromRGB(4, 20, 56),
        Accent = Color3.fromRGB(80, 160, 255),
        TabAccent = Color3.fromRGB(116, 184, 255),
        TabIconActive = Color3.fromRGB(80, 160, 255),
        TabIconHover = Color3.fromRGB(8, 32, 80),
        TabIconInactive = Color3.fromRGB(110, 158, 220),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.0,
        TransparencySecondary = 0.35,
        TransparencyTertiary = 0.17
    },

    Matcha = {
        Primary = Color3.fromRGB(236, 248, 238),
        Secondary = Color3.fromRGB(214, 238, 218),
        SecondaryHover = Color3.fromRGB(190, 226, 196),
        SecondaryActive = Color3.fromRGB(164, 212, 172),
        SecondaryPressed = Color3.fromRGB(204, 233, 209),
        Tertiary = Color3.fromRGB(180, 220, 188),
        TertiaryHover = Color3.fromRGB(156, 206, 166),
        TertiaryActive = Color3.fromRGB(130, 190, 142),
        TertiaryPressed = Color3.fromRGB(170, 214, 178),
        Quaternary = Color3.fromRGB(226, 244, 228),
        QuaternaryHover = Color3.fromRGB(206, 234, 210),
        Separator = Color3.fromRGB(130, 196, 142),
        SeparatorTransparency = 0.28,
        BoxBackground = Color3.fromRGB(246, 254, 248),
        TextPrimary = Color3.fromRGB(10, 44, 18),
        TextSecondary = Color3.fromRGB(34, 110, 52),
        TextInactive = Color3.fromRGB(96, 164, 110),
        TextActive = Color3.fromRGB(4, 26, 10),
        Accent = Color3.fromRGB(60, 168, 84),
        TabAccent = Color3.fromRGB(88, 196, 112),
        TabIconActive = Color3.fromRGB(60, 168, 84),
        TabIconHover = Color3.fromRGB(10, 50, 20),
        TabIconInactive = Color3.fromRGB(96, 164, 110),
        FontPrimary = Enum.Font.GothamBold,
        FontSecondary = Enum.Font.GothamMedium,
        FontSizePrimary = 18,
        FontSizeSecondary = 16,
        TransparencyPrimary = 0.0,
        TransparencySecondary = 0.34,
        TransparencyTertiary = 0.16
    }
}

EngProject.Themes.DefaultTheme = EngProject.Themes.IceBlack

-- Helper frameworks
do
    EngProject.ErrorHandler = {}
    do
        local ErrorLevels = {
            SILENT = 0,
            WARN = 1,
            ERROR = 2,
            CRITICAL = 3
        }
        EngProject.ErrorHandler.Level = ErrorLevels.WARN
        EngProject.ErrorHandler.Levels = ErrorLevels
        local Colors = {
            [ErrorLevels.WARN] = "255,255,0",
            [ErrorLevels.ERROR] = "255,100,100",
            [ErrorLevels.CRITICAL] = "255,0,0"
        }

        RunService.Heartbeat:Connect(function()
            local Console = CoreGui:FindFirstChild("DevConsoleMaster")
            if Console then
                for _, v in pairs(Console:GetDescendants()) do
                    if v:IsA("TextLabel") then
                        v.RichText = true
                    end
                end
            end
        end)

        local function RichPrint(Color, Text)
            local RGB = Colors[Color] or "255,255,255"
            print('<font color="rgb(' .. RGB .. ')">' .. tostring(Text) .. '</font>')
        end
        local function FormatError(Context, Message, Level)
            local Prefix = ({
                [ErrorLevels.WARN] = "[EngProject:WARN]",
                [ErrorLevels.ERROR] = "[EngProject:ERROR]",
                [ErrorLevels.CRITICAL] = "[EngProject:CRITICAL]"
            })[Level] or "[EngProject]"
            return Prefix .. " " .. Context .. ": " .. Message
        end
        local function LogError(Context, Message, Level)
            if Level == ErrorLevels.SILENT then
                return
            end
            if Level < EngProject.ErrorHandler.Level then
                return
            end
            RichPrint(Level, FormatError(Context, Message, Level))
        end
        function EngProject.ErrorHandler:Wrap(Func, Context, DefaultReturn)
            return function(...)
                local Success, Result = pcall(Func, ...)
                if not Success then
                    LogError(Context, tostring(Result), ErrorLevels.ERROR)
                    return DefaultReturn
                end
                return Result
            end
        end

        function EngProject.ErrorHandler:Guard(Condition, Context, Message, Level)
            if not Condition then
                LogError(Context, Message, Level or ErrorLevels.WARN)
                return false
            end
            return true
        end

        function EngProject.ErrorHandler:ValidateType(Value, ExpectedType, ParamName, Context)
            local ActualType = typeof(Value)
            if ActualType ~= ExpectedType then
                LogError(Context,
                    "Invalid type for '" .. ParamName .. "': expected " .. ExpectedType .. ", got " .. ActualType,
                    ErrorLevels.WARN)
                return false
            end
            return true
        end

        function EngProject.ErrorHandler:ValidateRange(Value, Min, Max, ParamName, Context)
            if Value < Min or Value > Max then
                LogError(Context,
                    "'" .. ParamName .. "' out of range: " .. tostring(Value) .. " not in [" .. tostring(Min) .. ", " ..
                        tostring(Max) .. "]", ErrorLevels.WARN)
                return false
            end
            return true
        end

        function EngProject.ErrorHandler:ValidateInstance(Instance, ExpectedClass, Context)
            if not Instance then
                LogError(Context, "Instance is nil", ErrorLevels.WARN)
                return false
            end
            if not Instance:IsA(ExpectedClass) then
                LogError(Context, "Invalid instance type: expected " .. ExpectedClass .. ", got " .. Instance.ClassName,
                    ErrorLevels.WARN)
                return false
            end
            return true
        end

        function EngProject.ErrorHandler:ValidateOptions(Options, Required, Optional, Context)
            Options = Options or {}
            for _, Key in ipairs(Required or {}) do
                if Options[Key] == nil then
                    LogError(Context, "Missing required option: '" .. Key .. "'", ErrorLevels.WARN)
                    return false
                end
            end
            local Allowed = {}
            for _, Key in ipairs(Required or {}) do
                Allowed[Key] = true
            end
            for _, Key in ipairs(Optional or {}) do
                Allowed[Key] = true
            end
            for Key in pairs(Options) do
                if not Allowed[Key] then
                    LogError(Context, "Unknown option: '" .. Key .. "'", ErrorLevels.WARN)
                end
            end
            return true
        end

        function EngProject.ErrorHandler:Try(Func, Fallback)
            local Success, Result = pcall(Func)
            if not Success then
                return Fallback and Fallback() or nil
            end
            return Result
        end

        function EngProject.ErrorHandler:SetLevel(Level)
            self.Level = Level
        end
    end

    EngProject.Security = {}
    do
        local ProtectedFunctions = {}
        local HookedMetatables = {}
        function EngProject.Security:WrapFunction(Func)
            if not Func or type(Func) ~= "function" then
                return Func
            end
            if ProtectedFunctions[Func] then
                return ProtectedFunctions[Func]
            end
            local Protected = newcclosure(function(...)
                return Func(...)
            end)
            ProtectedFunctions[Func] = Protected
            return Protected
        end

        function EngProject.Security:SafeCallback(Callback, ...)
            if not (Callback and typeof(Callback) == "function") then
                return nil
            end
            local _, Result = xpcall(Callback, function(Error)
                if EngProject.ErrorHandler.Level >= EngProject.ErrorHandler.Levels.ERROR then
                    EngProject.ErrorHandler:Guard(false, "SafeCallback", tostring(Error),
                        EngProject.ErrorHandler.Levels.ERROR)
                end
                return Error
            end, ...)
            return Result
        end

        function EngProject.Security:ProtectMetatable(Object)
            if not Object or HookedMetatables[Object] then
                return false
            end
            local Success = pcall(function()
                local MT = getmetatable(Object)
                if not MT then
                    return
                end
                local OriginalIndex = MT.__index
                local OriginalNewIndex = MT.__newindex
                local OriginalNamecall = MT.__namecall
                if OriginalIndex then
                    MT.__index = newcclosure(function(self, Key)
                        if type(OriginalIndex) == "function" then
                            return OriginalIndex(self, Key)
                        else
                            return OriginalIndex[Key]
                        end
                    end)
                end
                if OriginalNewIndex then
                    MT.__newindex = newcclosure(function(self, Key, Value)
                        if type(OriginalNewIndex) == "function" then
                            return OriginalNewIndex(self, Key, Value)
                        else
                            OriginalNewIndex[Key] = Value
                        end
                    end)
                end
                if OriginalNamecall then
                    MT.__namecall = newcclosure(function(self, ...)
                        return OriginalNamecall(self, ...)
                    end)
                end
                HookedMetatables[Object] = {
                    OriginalIndex = OriginalIndex,
                    OriginalNewIndex = OriginalNewIndex,
                    OriginalNamecall = OriginalNamecall
                }
            end)
            return Success
        end
    end

    EngProject.EventProtection = {} -- Deprecated
    do
        local ProtectedEvents = {}
        function EngProject.EventProtection:Protect(Event)
            if not Event or ProtectedEvents[Event] then
                return false
            end
            ProtectedEvents[Event] = true
            local OriginalConnect = Event.Connect
            Event.Connect = newcclosure(function(self, ...)
                return OriginalConnect(self, ...)
            end)
            local OriginalWait = Event.Wait
            Event.Wait = newcclosure(function(self, ...)
                return OriginalWait(self, ...)
            end)
            return true
        end
    end

    EngProject.ConnectionRegistry = {}
    do
        function EngProject.ConnectionRegistry:New()
            local registry = {
                _connections = {}
            }

            function registry:Add(connection)
                if connection and typeof(connection) == "RBXScriptConnection" then
                    table.insert(self._connections, connection)
                end
                return connection
            end

            function registry:Remove(connection)
                for i, c in ipairs(self._connections) do
                    if c == connection then
                        if c.Connected then
                            c:Disconnect()
                        end
                        table.remove(self._connections, i)
                        return
                    end
                end
            end

            function registry:Cleanup()
                for _, c in ipairs(self._connections) do
                    if c.Connected then
                        c:Disconnect()
                    end
                end
                table.clear(self._connections)
            end

            return registry
        end
    end

    EngProject.MetatableProtection = {}
    do
        local ProtectedObjects = {}
        function EngProject.MetatableProtection:Protect(Object)
            if not Object or ProtectedObjects[Object] then
                return false
            end
            ProtectedObjects[Object] = true
            return true
        end

        function EngProject.MetatableProtection:ProtectUI(ScreenGui)
            if not ScreenGui then
                return false
            end
            self:Protect(ScreenGui)
            for _, Descendant in ipairs(ScreenGui:GetDescendants()) do
                if Descendant:IsA("GuiObject") then
                    self:Protect(Descendant)
                end
            end
            return true
        end
    end

    EngProject.Utility = {}
    do
        function EngProject.Utility:GetService(ServiceName)
            return cloneref(game:GetService(ServiceName))
        end

        function EngProject.Utility:IsMobile()
            return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
        end

        function EngProject.Utility:CreateInstance(ClassName, Properties, Parent)
            local Instance = Instance.new(ClassName)
            if Properties then
                for Property, Value in pairs(Properties) do
                    Instance[Property] = Value
                end
            end
            if Parent then
                Instance.Parent = Parent
            end
            return Instance
        end

        function EngProject.Utility:GenerateId()
            local charset =
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+-=[]{}|;:,.<>?/`~"
            local rng = Random.new(math.floor(os.clock() * 1e9) + math.floor(tick() * 1e6) + math.random(1, 1e9))
            local length = rng:NextInteger(24, 40)
            local output = table.create(length)
            for i = 1, length do
                local index = rng:NextInteger(1, #charset)
                output[i] = charset:sub(index, index)
            end
            return table.concat(output)
        end

        function EngProject.Utility:MergeTables(Base, Override)
            local Result = {}
            for Key, Value in pairs(Base or {}) do
                Result[Key] = type(Value) == "table" and self:MergeTables(Value, {}) or Value
            end
            for Key, Value in pairs(Override or {}) do
                if type(Value) == "table" and type(Result[Key]) == "table" then
                    Result[Key] = self:MergeTables(Result[Key], Value)
                else
                    Result[Key] = Value
                end
            end
            return Result
        end

        function EngProject.Utility:ApplyTheme(Properties, ThemeBindings, Theme)
            local Result = {}
            local Bindings = {}
            for Property, Value in pairs(Properties) do
                Result[Property] = Value
            end
            if ThemeBindings then
                for Property, ThemeKey in pairs(ThemeBindings) do
                    if Theme[ThemeKey] then
                        Result[Property] = Theme[ThemeKey]
                        Bindings[Property] = ThemeKey
                    end
                end
            end
            return Result, Bindings
        end

        function EngProject.Utility:GetWindowFromElement(Element)
            local Current = Element
            while Current do
                if Current:IsA("ScreenGui") and EngProject.Windows[Current] then
                    return EngProject.Windows[Current]
                end
                Current = Current.Parent
            end
            return nil
        end

        function EngProject.Utility:ParentUI(Element, TargetParent)
            local Success = pcall(function()
                local FinalParent
                pcall(protectgui, Element)
                FinalParent = gethui()
                if TargetParent then
                    if type(TargetParent) == "function" then
                        FinalParent = TargetParent()
                    else
                        FinalParent = TargetParent
                    end
                end
                Element.Parent = FinalParent
            end)
            if not (Success and Element.Parent) then
                Element.Parent = LocalPlayer:WaitForChild("CoreGui", math.huge)
            end
        end

        function EngProject.Utility:Tween(object, tweenInfo, properties)
            if not object or not object.Parent then
                return
            end
            TweenService:Create(object, tweenInfo, properties):Play()
        end
    end

    EngProject.SaveManager = {}
    do
        EngProject.SaveManager.Enabled = true
        EngProject.SaveManager.AutoSave = true
        EngProject.SaveManager.Folder = "EngProject"
        EngProject.SaveManager.FileName = tostring(game.PlaceId) .. ".json"
        EngProject.SaveManager.Values = {}
        EngProject.SaveManager.Loaded = false

        local function hasFilesystem()
            return type(readfile) == "function" and type(writefile) == "function" and type(isfile) == "function" and
                       type(makefolder) == "function" and type(isfolder) == "function"
        end

        local function splitPath(path)
            local parts = {}
            for part in tostring(path or ""):gmatch("[^/\\]+") do
                table.insert(parts, part)
            end
            return parts
        end

        local function ensureFolder(path)
            if not hasFilesystem() then
                return false
            end

            local current = ""
            for _, part in ipairs(splitPath(path)) do
                current = current == "" and part or (current .. "/" .. part)
                if not isfolder(current) then
                    local ok = pcall(makefolder, current)
                    if not ok then
                        return false
                    end
                end
            end
            return true
        end

        local function sanitizeKey(value)
            local text = tostring(value or "value")
            text = text:gsub("%s+", "_"):gsub("[^%w_%-%.:]", "")
            return text ~= "" and text or "value"
        end

        function EngProject.SaveManager:IsAvailable()
            return hasFilesystem()
        end

        function EngProject.SaveManager:Configure(options)
            options = options or {}
            if options.Enabled ~= nil then
                self.Enabled = options.Enabled == true
            end
            if options.AutoSave ~= nil then
                self.AutoSave = options.AutoSave == true
            end
            if type(options.Folder) == "string" and options.Folder ~= "" then
                self.Folder = options.Folder
            end
            if type(options.FileName) == "string" and options.FileName ~= "" then
                self.FileName = options.FileName
            end
            if type(options.File) == "string" and options.File ~= "" then
                self.FileName = options.File
            end
            self:Load()
            return self
        end

        function EngProject.SaveManager:GetPath()
            return self.Folder .. "/" .. self.FileName
        end

        function EngProject.SaveManager:Load()
            if self.Loaded then
                return self.Values
            end
            self.Loaded = true
            self.Values = {}

            if not self.Enabled or not self:IsAvailable() then
                return self.Values
            end

            local path = self:GetPath()
            if not isfile(path) then
                return self.Values
            end

            local ok, data = pcall(function()
                local body = readfile(path)
                if type(body) ~= "string" or body == "" then
                    return {}
                end
                return EngProject.Utility:GetService("HttpService"):JSONDecode(body)
            end)

            if ok and type(data) == "table" then
                self.Values = data
            end

            return self.Values
        end

        function EngProject.SaveManager:Save()
            if not self.Enabled or not self:IsAvailable() then
                return false
            end
            if not ensureFolder(self.Folder) then
                return false
            end

            local ok = pcall(function()
                local body = EngProject.Utility:GetService("HttpService"):JSONEncode(self.Values or {})
                writefile(self:GetPath(), body)
            end)
            return ok
        end

        function EngProject.SaveManager:Get(key, defaultValue)
            self:Load()
            if self.Values[key] == nil then
                return defaultValue
            end
            return self.Values[key]
        end

        function EngProject.SaveManager:Set(key, value)
            if not key then
                return false
            end
            self:Load()
            self.Values[key] = value
            if self.AutoSave then
                return self:Save()
            end
            return true
        end

        function EngProject.SaveManager:Remove(key)
            if not key then
                return false
            end
            self:Load()
            self.Values[key] = nil
            if self.AutoSave then
                return self:Save()
            end
            return true
        end

        function EngProject.SaveManager:GetBinding(options, componentType, label)
            options = options or {}
            local saveConfig = options.Save
            if saveConfig == nil then
                saveConfig = options.Persist
            end

            local enabled = false
            local key = options.SaveKey or options.Flag
            local applyCallback = true

            if type(saveConfig) == "table" then
                enabled = saveConfig.Enabled ~= false
                key = saveConfig.Key or saveConfig.Flag or saveConfig.Name or key
                if saveConfig.ApplyCallback ~= nil then
                    applyCallback = saveConfig.ApplyCallback == true
                end
            elseif saveConfig == true then
                enabled = true
            end

            if not enabled then
                return {
                    Enabled = false,
                    HasValue = false,
                    ApplyCallback = false
                }
            end

            key = key or (tostring(componentType or "Component") .. ":" .. sanitizeKey(label))
            self:Load()

            return {
                Enabled = self.Enabled and self:IsAvailable(),
                Key = key,
                HasValue = self.Values[key] ~= nil,
                Value = self.Values[key],
                ApplyCallback = applyCallback
            }
        end

        function EngProject.SaveManager:WriteBinding(binding, value)
            if not binding or not binding.Enabled or not binding.Key then
                return false
            end
            if value == nil then
                return self:Remove(binding.Key)
            end
            return self:Set(binding.Key, value)
        end
    end

    EngProject.ThemeManager = {}
    do
        function EngProject.ThemeManager:Initialize(Window)
            local EH = EngProject.ErrorHandler
            if not EH:ValidateType(Window, "table", "Window", "ThemeManager:Initialize") then
                return false
            end
            Window.ThemeData = {
                Elements = {},
                CurrentTheme = Window.Theme or EngProject.Themes.DefaultTheme
            }
            return true
        end

        function EngProject.ThemeManager:GetCurrentTheme(Window)
            local EH = EngProject.ErrorHandler
            if not Window then
                EH:Guard(false, "ThemeManager:GetCurrentTheme", "Window is nil, using DefaultTheme", EH.Levels.WARN)
                return EngProject.Themes.DefaultTheme
            end
            if not Window.ThemeData then
                EH:Guard(false, "ThemeManager:GetCurrentTheme", "ThemeData not initialized, using DefaultTheme",
                    EH.Levels.WARN)
                return EngProject.Themes.DefaultTheme
            end
            return Window.ThemeData.CurrentTheme
        end

        function EngProject.ThemeManager:RegisterElement(Window, Element, Bindings)
            local EH = EngProject.ErrorHandler
            if not Window or not Window.ThemeData then
                EH:Guard(false, "ThemeManager:RegisterElement", "Invalid window", EH.Levels.WARN)
                return false
            end
            if not Element then
                EH:Guard(false, "ThemeManager:RegisterElement", "Element is nil", EH.Levels.WARN)
                return false
            end
            if not EH:ValidateType(Bindings, "table", "Bindings", "ThemeManager:RegisterElement") then
                return false
            end
            for Property, ThemeKey in pairs(Bindings) do
                if EH:ValidateType(Property, "string", "Property", "ThemeManager:RegisterElement") then
                    local found = false
                    for _, existing in ipairs(Window.ThemeData.Elements) do
                        if existing.Element == Element and existing.Property == Property then
                            existing.ThemeKey = ThemeKey
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(Window.ThemeData.Elements, {
                            Element = Element,
                            Property = Property,
                            ThemeKey = ThemeKey
                        })
                    end
                end
            end
            return true
        end

        function EngProject.ThemeManager:RegisterMultiple(Window, Elements)
            local EH = EngProject.ErrorHandler
            if not Window then
                EH:Guard(false, "ThemeManager:RegisterMultiple", "Window is nil", EH.Levels.WARN)
                return false
            end
            if not EH:ValidateType(Elements, "table", "Elements", "ThemeManager:RegisterMultiple") then
                return false
            end
            for Element, Bindings in pairs(Elements) do
                EH:Try(function()
                    self:RegisterElement(Window, Element, Bindings)
                end)
            end
            return true
        end

        function EngProject.ThemeManager:ApplyToElement(Element, Property, ThemeKey, Theme, Animate)
            local EH = EngProject.ErrorHandler
            if not Element or not Element.Parent then
                return false
            end
            if type(ThemeKey) == "function" then
                return EH:Try(function()
                    ThemeKey(Element, Theme)
                    return true
                end, function()
                    return false
                end)
            end
            if not EH:ValidateType(Property, "string", "Property", "ThemeManager:ApplyToElement") then
                return false
            end
            local Value = Theme[ThemeKey]
            if Value == nil then
                EH:Guard(false, "ThemeManager:ApplyToElement",
                    string.format("Theme key '%s' not found", tostring(ThemeKey)), EH.Levels.WARN)
                return false
            end
            return EH:Try(function()
                if Animate and (Property:find("Color") or Property:find("Transparency")) then
                    TweenService:Create(Element,
                        TweenInfo.new(EngProject.Constants.Animation.Normal, Enum.EasingStyle.Quad), {
                            [Property] = Value
                        }):Play()
                else
                    Element[Property] = Value
                end
                return true
            end, function()
                EH:Guard(false, "ThemeManager:ApplyToElement", string.format("Failed to apply property '%s'", Property),
                    EH.Levels.WARN)
                return false
            end)
        end

        function EngProject.ThemeManager:SetTheme(Window, ThemeName, Animate)
            local EH = EngProject.ErrorHandler
            if not Window or not Window.ThemeData then
                EH:Guard(false, "ThemeManager:SetTheme", "Invalid window", EH.Levels.ERROR)
                return false
            end
            if not EH:ValidateType(ThemeName, "string", "ThemeName", "ThemeManager:SetTheme") then
                return false
            end
            local NewTheme = EngProject.Themes[ThemeName]
            if not NewTheme then
                EH:Guard(false, "ThemeManager:SetTheme", string.format("Theme '%s' not found", ThemeName),
                    EH.Levels.ERROR)
                return false
            end
            Window.ThemeData.CurrentTheme = NewTheme
            Window.Theme = NewTheme
            local alive = {}
            for _, Entry in ipairs(Window.ThemeData.Elements) do
                if Entry.Element and Entry.Element.Parent then
                    table.insert(alive, Entry)
                end
            end
            Window.ThemeData.Elements = alive
            local ProcessedElements = {}
            for _, Entry in ipairs(Window.ThemeData.Elements) do
                local Element = Entry.Element
                local Property = Entry.Property
                ProcessedElements[Element] = ProcessedElements[Element] or {}
                if not ProcessedElements[Element][Property] then
                    ProcessedElements[Element][Property] = true
                    EH:Try(function()
                        if type(Entry.ThemeKey) == "function" then
                            Entry.ThemeKey(Element, NewTheme)
                        else
                            self:ApplyToElement(Element, Property, Entry.ThemeKey, NewTheme, Animate)
                        end
                    end)
                end
            end
            return true
        end

        function EngProject.ThemeManager:GetThemeName(Window)
            local EH = EngProject.ErrorHandler
            if not Window or not Window.ThemeData then
                EH:Guard(false, "ThemeManager:GetThemeName", "Invalid window, defaulting to Secondary", EH.Levels.WARN)
                return "Secondary"
            end
            for Name, Theme in pairs(EngProject.Themes) do
                if Theme == Window.ThemeData.CurrentTheme then
                    return Name
                end
            end
            EH:Guard(false, "ThemeManager:GetThemeName", "Theme not found in registry, defaulting to Secondary",
                EH.Levels.WARN)
            return "Secondary"
        end
    end

    EngProject.ScrollManager = {}
    do
        function EngProject.ScrollManager:Update(Container)
            local EH = EngProject.ErrorHandler
            if not Container or not Container.Parent then
                return Container
            end
            if not (Container:IsA("Frame") or Container:IsA("ScrollingFrame")) then
                EH:Guard(false, "ScrollManager:Update", "Container must be Frame or ScrollingFrame", EH.Levels.WARN)
                return Container
            end
            local Layout = Container:FindFirstChildWhichIsA("UIListLayout")
            if not Layout then
                return Container
            end
            local Parent = Container.Parent
            if not Parent then
                return Container
            end
            local ContentHeight = Layout.AbsoluteContentSize.Y
            local AvailableHeight = Container.AbsoluteSize.Y
            local NeedsScrolling = ContentHeight > AvailableHeight
            local IsScrollFrame = Container:IsA("ScrollingFrame")
            if NeedsScrolling and not IsScrollFrame then
                local ScrollFrame = EngProject.Utility:CreateInstance("ScrollingFrame", {
                    Name = Container.Name,
                    Position = Container.Position,
                    Size = Container.Size,
                    AnchorPoint = Container.AnchorPoint,
                    BackgroundColor3 = Container.BackgroundColor3,
                    BackgroundTransparency = Container.BackgroundTransparency,
                    BorderSizePixel = 0,
                    BorderMode = Enum.BorderMode.Inset,
                    ZIndex = Container.ZIndex,
                    LayoutOrder = Container.LayoutOrder,
                    Visible = Container.Visible,
                    ClipsDescendants = true,
                    ScrollBarThickness = 0,
                    ScrollBarImageColor3 = Color3.fromRGB(200, 200, 200),
                    ScrollBarImageTransparency = 1,
                    ScrollingDirection = Enum.ScrollingDirection.Y,
                    AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    CanvasSize = UDim2.new(0, 0, 0, 0),
                    ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
                    ScrollingEnabled = true,
                    Active = true
                }, Parent)
                for _, Child in ipairs(Container:GetChildren()) do
                    Child.Parent = ScrollFrame
                end
                local ScreenGui = Parent
                while ScreenGui and not ScreenGui:IsA("ScreenGui") do
                    ScreenGui = ScreenGui.Parent
                end
                if ScreenGui and EngProject.Windows[ScreenGui] then
                    local Window = EngProject.Windows[ScreenGui]
                    if Window.Elements and Window.Elements.Pages then
                        for PageName, Page in pairs(Window.Elements.Pages) do
                            if Page == Container then
                                Window.Elements.Pages[PageName] = ScrollFrame
                                break
                            end
                        end
                    end
                    if Window.ActivePage == Container then
                        Window.ActivePage = ScrollFrame
                    end
                    if Window.Elements.TabsContainer == Container then
                        Window.Elements.TabsContainer = ScrollFrame
                    end
                end
                Container:Destroy()
                Container = ScrollFrame
            elseif not NeedsScrolling and IsScrollFrame then
                Container.ScrollBarThickness = 0
            elseif NeedsScrolling and IsScrollFrame then
                Container.ScrollBarImageTransparency = 1
            end
            if Layout and not Layout:GetAttribute("ScrollUpdateHooked") then
                Layout:SetAttribute("ScrollUpdateHooked", true)
                local UpdateQueued = false
                local LastContentSize = Layout.AbsoluteContentSize
                Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                    if UpdateQueued or Layout.AbsoluteContentSize == LastContentSize then
                        return
                    end
                    LastContentSize = Layout.AbsoluteContentSize
                    UpdateQueued = true
                    task.defer(function()
                        UpdateQueued = false
                        if Container and Container.Parent then
                            EngProject.ScrollManager:Update(Container)
                        end
                    end)
                end)
            end
            return Container
        end
    end

    EngProject.WindowControlBuilder = {}
    do
        function EngProject.WindowControlBuilder:Create(ControlType, Style, Parent, Index, TotalControls)
            local Config = EngProject.WindowControls[Style]
            if not Config then
                return
            end
            local IconData = Config.Icons and Config.Icons[ControlType] or {}
            local Alignment = Config.Alignment or "Right"
            local BaseColor = Config.Colors and Config.Colors[ControlType] or Color3.fromRGB(45, 45, 45)
            local Spacing = Config.ButtonSpacing or 0
            local IsMobile = EngProject.Utility:IsMobile()
            local Position = Alignment == "Left" and
                                 UDim2.new(0, Index * (Config.ButtonSize.X.Offset + Spacing), 0.5, 0) or
                                 UDim2.new(1, -(TotalControls - Index) * (Config.ButtonSize.X.Offset + Spacing), 0.5, 0)
            local Button = EngProject.Utility:CreateInstance("TextButton", {
                Name = ControlType .. "Button",
                Size = Config.ButtonSize,
                Position = Position,
                AnchorPoint = Vector2.new(0, 0.5),
                BackgroundColor3 = BaseColor,
                BackgroundTransparency = Config.Transparency or 0,
                Text = "",
                BorderSizePixel = 0,
                ClipsDescendants = true,
                AutoButtonColor = false,
                ZIndex = EngProject.Constants.ZIndex.Control
            }, Parent)
            if Config.UseImages and IconData.Image then
                EngProject.Utility:CreateInstance("ImageLabel", {
                    Size = IconData.Size or UDim2.new(0, 12, 0, 12),
                    Position = UDim2.new(0.5, 0, 0.5, 0),
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    BackgroundTransparency = 1,
                    Image = IconData.Image,
                    ImageColor3 = IconData.Color or Color3.fromRGB(255, 255, 255),
                    ZIndex = EngProject.Constants.ZIndex.Control + 1
                }, Button)
            end
            EngProject.Utility:CreateInstance("UICorner", {
                CornerRadius = Alignment == "Left" and UDim.new(1, 0) or UDim.new(0, 0)
            }, Button)
            if not IsMobile then
                if IconData.HoverColor then
                    local IsHovering = false
                    Button.MouseEnter:Connect(function()
                        IsHovering = true
                        Button.BackgroundColor3 = IconData.HoverColor
                    end)
                    Button.MouseLeave:Connect(function()
                        IsHovering = false
                        Button.BackgroundColor3 = BaseColor
                    end)
                    if IconData.PressedColor then
                        Button.Activated:Connect(function()
                            Button.BackgroundColor3 = IconData.PressedColor
                            task.wait(0.1)
                            Button.BackgroundColor3 = IsHovering and IconData.HoverColor or BaseColor
                        end)
                    end
                end
            elseif IconData.PressedColor then
                Button.Activated:Connect(function()
                    Button.BackgroundColor3 = IconData.PressedColor
                    task.wait(0.1)
                    Button.BackgroundColor3 = BaseColor
                end)
            end
            self:BindActions(Button, ControlType, Parent)
            return Button
        end

        function EngProject.WindowControlBuilder:BindActions(Button, ControlType, TopBar)
            local EH = EngProject.ErrorHandler
            local ParentFrame = TopBar.Parent
            if not ParentFrame or not TopBar then
                EH:Guard(false, "WindowControlBuilder:BindActions", "Invalid frame references", EH.Levels.ERROR)
                return
            end
            if ControlType == "Close" then
                Button.Activated:Connect(function()
                    local ScreenGui = ParentFrame.Parent.Parent
                    if not ScreenGui then
                        return
                    end

                    local FadeDuration = EngProject.Constants.Animation.Slow
                    local TweenInfo = TweenInfo.new(FadeDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
                    local Tweens = {}

                    for _, Object in ipairs(ScreenGui:GetDescendants()) do
                        if Object:IsA("GuiObject") then
                            local Properties = {
                                Position = UDim2.new(Object.Position.X.Scale - 1.5, Object.Position.X.Offset,
                                    Object.Position.Y.Scale, Object.Position.Y.Offset)
                            }

                            if Object:IsA("Frame") or Object:IsA("ScrollingFrame") or Object:IsA("TextButton") or
                                Object:IsA("TextLabel") then
                                Properties.BackgroundTransparency = 1
                            end
                            if Object:IsA("TextButton") or Object:IsA("TextLabel") then
                                Properties.TextTransparency = 1
                            end
                            if Object:IsA("ImageLabel") or Object:IsA("ImageButton") then
                                Properties.ImageTransparency = 1
                            end

                            table.insert(Tweens, TweenService:Create(Object, TweenInfo, Properties))
                        end
                    end

                    for _, Tween in ipairs(Tweens) do
                        Tween:Play()
                    end

                    task.delay(FadeDuration, function()
                        EngProject.Windows[ScreenGui] = nil
                        ScreenGui:Destroy()
                    end)
                end)
            end
            if ControlType == "Maximize" then
                Button.Activated:Connect(function()
                    local ScreenGui = ParentFrame.Parent.Parent
                    if not ScreenGui then
                        return
                    end
                    local MainFrame = ScreenGui:FindFirstChild("MainFrame")
                    if not MainFrame then
                        return
                    end
                    if not MainFrame:GetAttribute("OriginalSize") then
                        MainFrame:SetAttribute("OriginalSize", MainFrame.Size)
                        MainFrame:SetAttribute("OriginalPosition", MainFrame.Position)
                        MainFrame:SetAttribute("OriginalAnchorPoint", MainFrame.AnchorPoint)
                    end
                    local IsMaximized = MainFrame:GetAttribute("Maximized") or false
                    MainFrame:SetAttribute("Maximized", not IsMaximized)

                    local TargetSize, TargetPosition, TargetAnchor
                    if not IsMaximized then
                        TargetSize = UDim2.new(0.95, 0, 0.95, 0)
                        TargetPosition = UDim2.new(0.5, 0, 0.5, 0)
                        TargetAnchor = Vector2.new(0.5, 0.5)
                    else
                        TargetSize = MainFrame:GetAttribute("OriginalSize")
                        TargetPosition = MainFrame:GetAttribute("OriginalPosition")
                        TargetAnchor = MainFrame:GetAttribute("OriginalAnchorPoint")
                    end

                    MainFrame.AnchorPoint = TargetAnchor
                    TweenService:Create(MainFrame, TweenInfo.new(EngProject.Constants.Animation.Normal,
                        Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                        Size = TargetSize,
                        Position = TargetPosition
                    }):Play()
                end)
            end
        end

        function EngProject.WindowControlBuilder:RegisterIconBindings(Window, ControlButtons, Options)
            local ControlStyle = Options.ControlStyle or "Windows"
            local Config = EngProject.WindowControls[ControlStyle]
            if not Config or not Config.Icons then
                return
            end
            local CurrentTheme = EngProject.ThemeManager:GetCurrentTheme(Window)
            for ControlType, Button in pairs(ControlButtons) do
                local IconData = Config.Icons[ControlType]
                if IconData and IconData.ColorKey then
                    local Icon = Button:FindFirstChildWhichIsA("ImageLabel")
                    if Icon then
                        local ColorValue = CurrentTheme[IconData.ColorKey]
                        if ColorValue then
                            Icon.ImageColor3 = ColorValue
                        end
                        EngProject.ThemeManager:RegisterElement(Window, Icon, {
                            ImageColor3 = function(Element, Theme)
                                local NewColorValue = Theme[IconData.ColorKey]
                                if NewColorValue then
                                    Element.ImageColor3 = NewColorValue
                                end
                            end
                        })
                    end
                end
            end
        end
    end

    EngProject.ComponentBuilder = {}
    do
        function EngProject.ComponentBuilder:CreateContainer(Config, Theme)
            if not EngProject.ErrorHandler:ValidateInstance(Config.Parent, "GuiObject", "ComponentBuilder:CreateContainer") then
                return nil
            end
            local IsDualScroll = Config.Parent:GetAttribute("IsDualScroll") or false
            local Container = EngProject.Utility:CreateInstance("Frame", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = Theme[Config.ColorTier or "Secondary"],
                BackgroundTransparency = Theme.TransparencySecondary,
                BorderSizePixel = 0,
                ZIndex = EngProject.Constants.ZIndex.Control
            }, Config.Parent)
            if Config.MinHeight then
                EngProject.Utility:CreateInstance("UISizeConstraint", {
                    MinSize = Vector2.new(0, Config.MinHeight)
                }, Container)
            end
            if Config.CornerRadius then
                EngProject.Utility:CreateInstance("UICorner", {
                    CornerRadius = UDim.new(0, Config.CornerRadius)
                }, Container)
            end
            local Padding = Config.Padding or {}
            if type(Padding) == "number" then
                Padding = {
                    Top = Padding,
                    Bottom = Padding,
                    Left = Padding,
                    Right = Padding
                }
            end
            if type(Padding) == "table" then
                for key, value in pairs(Padding) do
                    if type(value) ~= "number" then
                        Padding[key] = EngProject.Constants.Padding.Medium
                    end
                end
            end
            EngProject.Utility:CreateInstance("UIPadding", {
                PaddingTop = UDim.new(0, Padding.Top or EngProject.Constants.Padding.Medium),
                PaddingBottom = UDim.new(0, Padding.Bottom or EngProject.Constants.Padding.Medium),
                PaddingLeft = UDim.new(0, Padding.Left or EngProject.Constants.Padding.Large),
                PaddingRight = UDim.new(0, IsDualScroll and -8 or (Padding.Right or EngProject.Constants.Padding.Medium))
            }, Container)
            local TextZone, InteractiveZone, Layout
            if Config.Layout == "TextLeft" then
                TextZone = EngProject.Utility:CreateInstance("Frame", {
                    Size = UDim2.new(Config.TextWidth or 0.65, 0, 1, 0),
                    Position = UDim2.new(0, 0, 0, 0),
                    BackgroundTransparency = 1,
                    ZIndex = EngProject.Constants.ZIndex.Overlay
                }, Container)
                Layout = EngProject.Utility:CreateInstance("UIListLayout", {
                    FillDirection = Enum.FillDirection.Vertical,
                    HorizontalAlignment = Enum.HorizontalAlignment.Left,
                    VerticalAlignment = Config.HasDescription and Enum.VerticalAlignment.Top or
                        Enum.VerticalAlignment.Center,
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Padding = UDim.new(0, EngProject.Constants.Spacing.Relaxed)
                }, TextZone)
                InteractiveZone = Container
            elseif Config.Layout == "Stacked" then
                local ContentFrame = EngProject.Utility:CreateInstance("Frame", {
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    ZIndex = EngProject.Constants.ZIndex.Overlay
                }, Container)
                Layout = EngProject.Utility:CreateInstance("UIListLayout", {
                    FillDirection = Enum.FillDirection.Vertical,
                    HorizontalAlignment = Enum.HorizontalAlignment.Left,
                    VerticalAlignment = Enum.VerticalAlignment.Top,
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Padding = UDim.new(0, Config.Spacing or EngProject.Constants.Spacing.Normal)
                }, ContentFrame)
                if not Config.HasDescription then
                    ContentFrame.Position = UDim2.new(0, 0, 0.5, 0)
                    ContentFrame.AnchorPoint = Vector2.new(0, 0.5)
                end
                TextZone = ContentFrame
                InteractiveZone = ContentFrame
            else
                TextZone = Container
                InteractiveZone = Container
            end
            return {
                Container = Container,
                TextZone = TextZone,
                InteractiveZone = InteractiveZone,
                Layout = Layout
            }
        end

        function EngProject.ComponentBuilder:CreateLabel(Parent, Text, Theme, Config)
            Config = Config or {}
            if Config and
                not EngProject.ErrorHandler:ValidateType(Config, "table", "Config", "ComponentBuilder:CreateLabel") then
                Config = {}
            end
            return EngProject.Utility:CreateInstance("TextLabel", {
                Size = UDim2.new(1, Config.WidthOffset or 0, 0, 0),
                BackgroundTransparency = 1,
                Text = Text or "",
                TextColor3 = Theme[Config.ColorTier or "TextPrimary"],
                TextSize = Config.Size or 14,
                Font = Theme[Config.Font or "FontSecondary"],
                TextXAlignment = Config.Align or Enum.TextXAlignment.Left,
                TextWrapped = true,
                AutomaticSize = Enum.AutomaticSize.Y,
                LayoutOrder = Config.Order or 1,
                ZIndex = EngProject.Constants.ZIndex.Overlay
            }, Parent)
        end

        function EngProject.ComponentBuilder:CreateDescription(Parent, Text, Theme, Order)
            if not Text or Text == "" then
                return nil
            end
            return self:CreateLabel(Parent, Text, Theme, {
                ColorTier = "TextSecondary",
                Size = 14,
                Order = Order or 2
            })
        end

        function EngProject.ComponentBuilder:UpdateDescriptionPadding(Zones, HasDescription)
            local Padding = Zones.Container:FindFirstChildOfClass("UIPadding")
            if not Padding then
                return
            end
            if HasDescription then
                Padding.PaddingTop = UDim.new(0, EngProject.Constants.Padding.Large)
                Padding.PaddingBottom = UDim.new(0, EngProject.Constants.Padding.Large)
                if Zones.Layout then
                    Zones.Layout.Padding = UDim.new(0, EngProject.Constants.Spacing.Tight)
                end
                if Zones.TextZone then
                    Zones.TextZone.Position = UDim2.new(0, 0, 0, 0)
                    Zones.TextZone.AnchorPoint = Vector2.new(0, 0)
                end
            else
                Padding.PaddingTop = UDim.new(0, 0)
                Padding.PaddingBottom = UDim.new(0, 0)
                if Zones.Layout then
                    Zones.Layout.Padding = UDim.new(0, 0)
                end
                if Zones.TextZone then
                    Zones.TextZone.Position = UDim2.new(0, 0, 0.5, 0)
                    Zones.TextZone.AnchorPoint = Vector2.new(0, 0.5)
                end
            end
        end
    end

    EngProject.DropdownManager = {}
    do
        function EngProject.DropdownManager:NormalizeOptions(Options)
            local EH = EngProject.ErrorHandler
            if not EH:ValidateType(Options, "table", "Options", "DropdownManager:NormalizeOptions") then
                return {}, {}
            end
            local Normalized = {}
            local DataMap = {}
            for Index, Option in ipairs(Options) do
                if type(Option) == "table" then
                    local DisplayText = Option.Text or Option.text or Option.Label or Option.label or tostring(Option)
                    Normalized[Index] = DisplayText
                    DataMap[DisplayText] = Option
                else
                    Normalized[Index] = tostring(Option)
                    DataMap[tostring(Option)] = Option
                end
            end
            return Normalized, DataMap
        end

        function EngProject.DropdownManager:InitializeSelection(DefaultValue, IsMultiSelect, DataMap)
            local EH = EngProject.ErrorHandler
            if IsMultiSelect then
                local Selected = {}
                if type(DefaultValue) == "table" then
                    if not EH:ValidateType(DefaultValue, "table", "DefaultValue", "DropdownManager:InitializeSelection") then
                        return Selected
                    end
                    for _, Value in ipairs(DefaultValue) do
                        local Normalized = type(Value) == "table" and
                                               (Value.Text or Value.text or Value.Label or Value.label or
                                                   tostring(Value)) or tostring(Value)
                        if DataMap[Normalized] then
                            Selected[Normalized] = true
                        end
                    end
                end
                return Selected
            else
                if DefaultValue then
                    local Normalized = type(DefaultValue) == "table" and
                                           (DefaultValue.Text or DefaultValue.text or DefaultValue.Label or
                                               DefaultValue.label or tostring(DefaultValue)) or tostring(DefaultValue)
                    return DataMap[Normalized] and Normalized or nil
                end
                return nil
            end
        end

        function EngProject.DropdownManager:GetSelectedData(Selection, IsMultiSelect, DataMap)
            if IsMultiSelect then
                local Selected = {}
                for Value, Enabled in pairs(Selection) do
                    if Enabled then
                        table.insert(Selected, DataMap[Value])
                    end
                end
                return Selected
            else
                return DataMap[Selection]
            end
        end

        function EngProject.DropdownManager:UpdateDisplayText(DisplayLabel, Selection, IsMultiSelect)
            local EH = EngProject.ErrorHandler
            if not DisplayLabel or not DisplayLabel.Parent then
                EH:Guard(false, "DropdownManager:UpdateDisplayText", "Invalid DisplayLabel", EH.Levels.WARN)
                return
            end
            EH:Try(function()
                if IsMultiSelect then
                    local Selected = {}
                    for Value, Enabled in pairs(Selection) do
                        if Enabled then
                            table.insert(Selected, Value)
                        end
                    end
                    DisplayLabel.Text = #Selected > 0 and table.concat(Selected, ", ") or "Select"
                else
                    DisplayLabel.Text = Selection or "Select"
                end
            end)
        end
    end

    EngProject.WindowBuilder = {}
    do
        function EngProject.WindowBuilder:CreateMainFrame(ScreenGui, Options, Theme)
            local MainFrameProperties, MainFrameBindings = EngProject.Utility:ApplyTheme({
                Name = "MainFrame",
                AnchorPoint = Vector2.new(0.5, 0.5),
                Active = true,
                AutoButtonColor = false,
                Position = Options.Position or UDim2.new(0.5, 0, 0.5, 0),
                Size = Options.Size or UDim2.new(0, 650, 0, 600),
                Text = "",
                BorderSizePixel = 0,
                ClipsDescendants = false
            }, {
                BackgroundColor3 = "Primary",
                BackgroundTransparency = "TransparencyPrimary"
            }, Theme)
            local MainFrame = EngProject.Utility:CreateInstance("TextButton", MainFrameProperties, ScreenGui)
            EngProject.Utility:CreateInstance("UICorner", {
                CornerRadius = UDim.new(0, EngProject.Constants.Corner.Large)
            }, MainFrame)
            EngProject.Utility:CreateInstance("UISizeConstraint", {
                MinSize = Options.MinSize or EngProject.Constants.Window.MinSize,
                MaxSize = Options.MaxSize or EngProject.Constants.Window.MaxSize
            }, MainFrame)
            local UIScale = EngProject.Utility:CreateInstance("UIScale", {
                Name = "WindowScale",
                Scale = Options.DefaultScale or EngProject.Constants.Window.DefaultScale
            }, MainFrame)
            return MainFrame, UIScale, MainFrameBindings
        end

        function EngProject.WindowBuilder:CreateTopBar(Parent, Options, Theme)
            local TopBarHeight = Options.TopBarHeight or EngProject.Constants.Window.TopBarHeight
            local TopBar = EngProject.Utility:CreateInstance("Frame", {
                Name = "TopBar",
                Size = UDim2.new(1, 0, 0, TopBarHeight),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ZIndex = EngProject.Constants.ZIndex.Base,
                ClipsDescendants = false,
                Active = true
            }, Parent)
            local Sep
            local SepBindings
            local SepProps
            if Options.TopBarSeparator ~= false then
                SepProps, SepBindings = EngProject.Utility:ApplyTheme({
                    Name = "TopBarSeparator",
                    AnchorPoint = Vector2.new(0, 1),
                    Position = UDim2.new(0, 0, 1, 0),
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    ZIndex = TopBar.ZIndex + 1
                }, {
                    BackgroundColor3 = "Separator",
                    BackgroundTransparency = "SeparatorTransparency"
                }, Theme)
                Sep = EngProject.Utility:CreateInstance("Frame", SepProps, TopBar)
            end
            return TopBar, Sep, SepBindings
        end

        function EngProject.WindowBuilder:CreateTitleSection(TopBar, Options, Theme)
            local ControlStyle = Options.ControlStyle or "Windows"
            local HasBrand = Options.Brand ~= nil
            local BrandName = HasBrand and Options.Brand.Name or ""
            local BrandIcon = HasBrand and Options.Brand.Icon or nil

            local BaseLeftOffset = 10
            local IconSize = 40
            local IconGap = 12

            local BrandIconElement = nil
            local BrandInitialElement = nil

            if HasBrand then
                if BrandIcon and type(BrandIcon) == "table" and BrandIcon.Image then
                    local IconData = EngProject.IconManager:WrapIcon(BrandIcon)
                    BrandIconElement = EngProject.Utility:CreateInstance("ImageLabel", {
                        Name = "BrandIcon",
                        Size = UDim2.new(0, IconSize, 0, IconSize),
                        Position = UDim2.new(0, BaseLeftOffset, 0.5, 0),
                        AnchorPoint = Vector2.new(0, 0.5),
                        BackgroundTransparency = 1,
                        Image = IconData.Url,
                        ImageColor3 = Theme.TextPrimary,
                        ScaleType = Enum.ScaleType.Fit,
                        BorderSizePixel = 0,
                        ZIndex = EngProject.Constants.ZIndex.Content + 1
                    }, TopBar)
                else
                    local Initials = BrandName:sub(1, 1):upper()
                    BrandInitialElement = EngProject.Utility:CreateInstance("TextLabel", {
                        Name = "BrandInitial",
                        Size = UDim2.new(0, IconSize, 0, IconSize),
                        Position = UDim2.new(0, BaseLeftOffset, 0.5, 0),
                        AnchorPoint = Vector2.new(0, 0.5),
                        BackgroundTransparency = 1,
                        Text = Initials,
                        TextColor3 = Theme.TextPrimary,
                        Font = Enum.Font.GothamBold,
                        TextSize = 42,
                        BorderSizePixel = 0,
                        ZIndex = EngProject.Constants.ZIndex.Content
                    }, TopBar)
                end
            end

            local BrandTitleLabel = nil
            if HasBrand and BrandName and BrandName ~= "" then
                BrandTitleLabel = EngProject.Utility:CreateInstance("TextLabel", {
                    Name = "BrandTitle",
                    Size = UDim2.new(0, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.XY,
                    Position = UDim2.new(0, BaseLeftOffset + IconSize + IconGap, 0.5, 0),
                    AnchorPoint = Vector2.new(0, 0.5),
                    BackgroundTransparency = 1,
                    Text = BrandName,
                    TextColor3 = Theme.TextPrimary,
                    Font = Theme.FontPrimary,
                    TextSize = 16,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    TextTransparency = 1,
                    ZIndex = EngProject.Constants.ZIndex.Content
                }, TopBar)

                EngProject.Utility:CreateInstance("UISizeConstraint", {
                    MaxSize = Vector2.new(200, math.huge)
                }, BrandTitleLabel)
            end

            local TabInfoContainer = EngProject.Utility:CreateInstance("Frame", {
                Name = "TabInfoContainer",
                Position = UDim2.new(0, 0, 0.5, 0),
                AnchorPoint = Vector2.new(0, 0.5),
                Size = UDim2.new(0, 0, 0.7, 0),
                AutomaticSize = Enum.AutomaticSize.X,
                BackgroundTransparency = 1,
                ZIndex = EngProject.Constants.ZIndex.Content,
                ClipsDescendants = true,
                Visible = true
            }, TopBar)

            EngProject.Utility:CreateInstance("UIPadding", {
                PaddingLeft = UDim.new(0, 12),
                PaddingRight = UDim.new(0, 200)
            }, TabInfoContainer)

            EngProject.Utility:CreateInstance("UIListLayout", {
                FillDirection = Enum.FillDirection.Vertical,
                SortOrder = Enum.SortOrder.LayoutOrder,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                HorizontalAlignment = Enum.HorizontalAlignment.Left,
                Padding = UDim.new(0, 2)
            }, TabInfoContainer)

            local TabNameLabel = EngProject.Utility:CreateInstance("TextLabel", {
                Name = "TabNameLabel",
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Text = "Select Tab",
                TextColor3 = Theme.TextPrimary,
                Font = Theme.FontPrimary,
                TextSize = 16,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                LayoutOrder = 1,
                ZIndex = EngProject.Constants.ZIndex.Content
            }, TabInfoContainer)

            local TabDescLabel = EngProject.Utility:CreateInstance("TextLabel", {
                Name = "TabDescLabel",
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Text = "",
                TextColor3 = Theme.TextSecondary,
                Font = Theme.FontSecondary,
                TextSize = 13,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                LayoutOrder = 2,
                ZIndex = EngProject.Constants.ZIndex.Content
            }, TabInfoContainer)

            local ControlsContainer = EngProject.Utility:CreateInstance("Frame", {
                Name = "ControlsContainer",
                Position = UDim2.new(1, -10, 0.5, 0),
                AnchorPoint = Vector2.new(1, 0.5),
                Size = UDim2.new(0, 100, 0.7, 0),
                BackgroundTransparency = 1,
                ZIndex = EngProject.Constants.ZIndex.Content,
                ClipsDescendants = false
            }, TopBar)

            return TabInfoContainer, ControlsContainer, TabNameLabel, TabDescLabel, BrandIconElement,
                BrandInitialElement, BrandTitleLabel
        end

        function EngProject.WindowBuilder:CreateWindowControls(ControlsContainer, Options, Theme)
            local ControlStyle = Options.ControlStyle or "Windows"
            local Controls = Options.WindowControls or
                                 (ControlStyle == "Windows" and {"Maximize", "Close"} or {"Close", "Maximize"})
            local ControlButtons = {}
            if Controls then
                for Index, ControlType in ipairs(Controls) do
                    local Button = EngProject.WindowControlBuilder:Create(ControlType, ControlStyle, ControlsContainer,
                        Index - 1, #Controls)
                    if Button then
                        ControlButtons[ControlType] = Button
                    end
                end
            end
            return ControlButtons
        end

        function EngProject.WindowBuilder:CreateContentAreas(MainContainer, MainFrame, TopBar, Options)
            local Const = EngProject.Constants.Window
            local TabsWidth = Const.TabsWidthOpen
            local ContentWidth = Const.ContentWidthOpen
            local IsCollapsed = Options.IsCollapsed
            local HorizontalPadding = IsCollapsed and 4 or Options.HorizontalPadding or Const.HorizontalPadding
            local HasBrand = Options.Brand ~= nil

            local TabsContainer = EngProject.Utility:CreateInstance("ScrollingFrame", {
                Name = "TabsContainer",
                Position = UDim2.new(0, HorizontalPadding, 0, 0),
                Size = UDim2.new(TabsWidth, -(HorizontalPadding * 1.5), 1, 0),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ZIndex = EngProject.Constants.ZIndex.Content,
                ClipsDescendants = true,
                ScrollingDirection = Enum.ScrollingDirection.Y,
                ScrollBarThickness = 0,
                CanvasSize = UDim2.new(0, 0, 0, 0),
                AutomaticCanvasSize = Enum.AutomaticSize.Y
            }, MainContainer)
            EngProject.Utility:CreateInstance("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                HorizontalAlignment = Enum.HorizontalAlignment.Center,
                Padding = UDim.new(0, EngProject.Constants.Padding.Large)
            }, TabsContainer)
            EngProject.Utility:CreateInstance("UIPadding", {
                PaddingTop = UDim.new(0, 0),
                PaddingBottom = UDim.new(0, 0),
                PaddingLeft = UDim.new(0, 2),
                PaddingRight = UDim.new(0, 1)
            }, TabsContainer)
            local Theme = EngProject.ThemeManager:GetCurrentTheme({
                ThemeData = {
                    CurrentTheme = EngProject.Themes.DefaultTheme
                }
            })
            local TabsSeparatorProperties, TabsSeparatorBindings = EngProject.Utility:ApplyTheme({
                Name = "TabsSeparator",
                Position = UDim2.new(TabsWidth, Const.TabSeparatorGap, 0, HasBrand and 0 or Const.TopBarHeight),
                Size = UDim2.new(0, 1, 1, HasBrand and 0 or -Const.TopBarHeight),
                BorderSizePixel = 0,
                ZIndex = EngProject.Constants.ZIndex.Content
            }, {
                BackgroundColor3 = "Separator",
                BackgroundTransparency = "SeparatorTransparency"
            }, Theme)
            local TabsSeparator = EngProject.Utility:CreateInstance("Frame", TabsSeparatorProperties, MainFrame)
            local ContentsContainer = EngProject.Utility:CreateInstance("Frame", {
                Name = "ContentsContainer",
                Position = UDim2.new(TabsWidth, HorizontalPadding, 0, 0),
                Size = UDim2.new(ContentWidth, -(HorizontalPadding * 2), 1, 0),
                BorderSizePixel = 0,
                BackgroundTransparency = 1,
                ZIndex = EngProject.Constants.ZIndex.Content,
                ClipsDescendants = true
            }, MainContainer)
            EngProject.Utility:CreateInstance("UIPadding", {
                PaddingBottom = UDim.new(0, EngProject.Constants.Padding.Large),
                PaddingLeft = UDim.new(0, EngProject.Constants.Padding.Large),
                PaddingRight = UDim.new(0, EngProject.Constants.Padding.Large)
            }, ContentsContainer)
            return TabsContainer, ContentsContainer, TabsSeparator, TabsSeparatorBindings
        end

        function EngProject.WindowBuilder:CreateMainContainer(Parent, Options, Theme, TopBarHeight, FooterHeight)
            local VerticalPadding = Options.VerticalPadding or EngProject.Constants.Window.VerticalPadding
            local FooterOffset = (FooterHeight and FooterHeight > 0) and -(Options.FooterOverlap or 0) or 0
            local MainContainer = EngProject.Utility:CreateInstance("Frame", {
                Name = "MainContainer",
                Position = UDim2.new(0, 0, 0, TopBarHeight),
                Size = UDim2.new(1, 0, 1, -(TopBarHeight + FooterOffset)),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ZIndex = EngProject.Constants.ZIndex.Base,
                ClipsDescendants = true
            }, Parent)
            if Options.AcrylicEffect then
                local Blur = EngProject.Utility:CreateInstance("Frame", {
                    Name = "BlurBackground",
                    Size = UDim2.new(1, 0, 1, 0),
                    Position = UDim2.new(0, 0, 0, 0),
                    BackgroundTransparency = 0.3,
                    BackgroundColor3 = Color3.fromRGB(0, 0, 0),
                    BorderSizePixel = 0,
                    ZIndex = EngProject.Constants.ZIndex.Background
                }, MainContainer)
                EngProject.Utility:CreateInstance("UICorner", {
                    CornerRadius = UDim.new(0, EngProject.Constants.Corner.Large)
                }, Blur)
                pcall(function()
                    local BlurEffect = Instance.new("BlurEffect")
                    BlurEffect.Size = 24
                    BlurEffect.Parent = Lighting
                end)
            end
            EngProject.Utility:CreateInstance("UIPadding", {
                PaddingTop = UDim.new(0, VerticalPadding),
                PaddingBottom = UDim.new(0, VerticalPadding),
                PaddingLeft = UDim.new(0, 0),
                PaddingRight = UDim.new(0, 0)
            }, MainContainer)
            return MainContainer
        end

        function EngProject.WindowBuilder:SetupDragging(TopBar, MainFrame)
            local IsDragging = false
            local DragStart
            local StartPosition
            TopBar.InputBegan:Connect(function(Input)
                if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType ==
                    Enum.UserInputType.Touch then
                    IsDragging = true
                    DragStart = Input.Position
                    StartPosition = MainFrame.Position
                    Input:GetPropertyChangedSignal("UserInputState"):Connect(function()
                        if Input.UserInputState == Enum.UserInputState.End then
                            IsDragging = false
                        end
                    end)
                end
            end)
            UserInputService.InputEnded:Connect(function(Input)
                if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType ==
                    Enum.UserInputType.Touch then
                    IsDragging = false
                end
            end)
            UserInputService.InputChanged:Connect(function(Input)
                if IsDragging and
                    (Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType ==
                        Enum.UserInputType.Touch) then
                    local CurrentPosition = Input.Position
                    local Delta = CurrentPosition - DragStart
                    MainFrame.Position = UDim2.new(StartPosition.X.Scale, StartPosition.X.Offset + Delta.X,
                        StartPosition.Y.Scale, StartPosition.Y.Offset + Delta.Y)
                end
            end)
        end

        function EngProject.WindowBuilder:CreateFooter(Parent, Options, Theme)
            if not Options.Footer then
                return nil, {}, nil
            end
            local FooterHeight = Options.FooterHeight or 20
            local FooterOverlap = Options.FooterOverlap or -10
            local FooterProperties, FooterBindings = EngProject.Utility:ApplyTheme({
                Name = "Footer",
                Position = UDim2.new(0, 0, 1, FooterOverlap),
                AnchorPoint = Vector2.new(0, 0),
                Size = UDim2.new(1, 0, 0, FooterHeight),
                BorderSizePixel = 0,
                ZIndex = EngProject.Constants.ZIndex.Overlay,
                ClipsDescendants = false
            }, {
                BackgroundColor3 = "Secondary",
                BackgroundTransparency = "TransparencyPrimary"
            }, Theme)
            local Footer = EngProject.Utility:CreateInstance("Frame", FooterProperties, Parent)
            EngProject.Utility:CreateInstance("UICorner", {
                CornerRadius = UDim.new(0, EngProject.Constants.Corner.Large)
            }, Footer)
            local SeparatorBindings = {}
            if Options.FooterSeparator ~= false then
                local SepProps, SepBindings = EngProject.Utility:ApplyTheme({
                    Name = "FooterSeparator",
                    Position = UDim2.new(0, 0, 1, FooterOverlap),
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    ZIndex = Footer.ZIndex + 1
                }, {
                    BackgroundColor3 = "Separator",
                    BackgroundTransparency = "SeparatorTransparency"
                }, Theme)
                local Separator = EngProject.Utility:CreateInstance("Frame", SepProps, Parent)
                if SepBindings then
                    SeparatorBindings = {
                        Element = Separator,
                        Bindings = SepBindings
                    }
                end
            end
            local ContentFrame = EngProject.Utility:CreateInstance("Frame", {
                Name = "FooterContent",
                Position = UDim2.new(0, 0, 0, 0),
                Size = UDim2.new(1, Options.CanResize and -24 or 0, 1, 0),
                BackgroundTransparency = 1,
                ZIndex = Footer.ZIndex + 1
            }, Footer)
            EngProject.Utility:CreateInstance("UIPadding", {
                PaddingLeft = UDim.new(0, EngProject.Constants.Padding.Large),
                PaddingRight = UDim.new(0, EngProject.Constants.Padding.Large),
                PaddingTop = UDim.new(0, EngProject.Constants.Padding.Medium),
                PaddingBottom = UDim.new(0, EngProject.Constants.Padding.Medium)
            }, ContentFrame)
            EngProject.Utility:CreateInstance("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                HorizontalAlignment = Options.FooterAlignment or Enum.HorizontalAlignment.Center,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, EngProject.Constants.Spacing.Normal)
            }, ContentFrame)
            local ResizeContainer
            if Options.CanResize then
                ResizeContainer = EngProject.Utility:CreateInstance("Frame", {
                    Name = "FooterResizeArea",
                    AnchorPoint = Vector2.new(1, 1),
                    Position = UDim2.new(1, 1, 1, 1),
                    Size = UDim2.fromOffset(20, 20),
                    BackgroundTransparency = 1,
                    ZIndex = Footer.ZIndex + 3
                }, Footer)
            end
            return Footer, FooterBindings, ContentFrame, SeparatorBindings, ResizeContainer
        end

        function EngProject.WindowBuilder:PopulateFooter(Window, Options, Theme)
            if not Window.Elements.FooterContent or not Options.FooterItems then
                return
            end
            for _, Item in ipairs(Options.FooterItems) do
                if Item.Type == "Text" then
                    local TextProperties, TextBindings = EngProject.Utility:ApplyTheme({
                        Name = Item.Name or "FooterText",
                        LayoutOrder = Item.Order or 1,
                        Size = UDim2.new(0, 0, 1, 0),
                        AutomaticSize = Enum.AutomaticSize.X,
                        BackgroundTransparency = 1,
                        Text = Item.Text or "",
                        TextSize = Item.TextSize or 14,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        ZIndex = Window.Elements.Footer.ZIndex + 2
                    }, {
                        Font = "FontSecondary",
                        TextColor3 = Item.ColorTier or "TextSecondary"
                    }, Theme)
                    local Label = EngProject.Utility:CreateInstance("TextLabel", TextProperties,
                        Window.Elements.FooterContent)
                    if Item.Id then
                        Window.Elements[Item.Id] = Label
                    end
                    if TextBindings then
                        EngProject.ThemeManager:RegisterElement(Window, Label, TextBindings)
                    end
                elseif Item.Type == "Button" then
                    local ButtonProperties, ButtonBindings = EngProject.Utility:ApplyTheme({
                        Name = Item.Name or Item.Text or "FooterButton",
                        LayoutOrder = Item.Order or 1,
                        Size = UDim2.new(0, Item.Width or 80, 1, -8),
                        Text = Item.Text or "Button",
                        TextSize = Item.TextSize or 14,
                        BorderSizePixel = 0,
                        AutoButtonColor = false,
                        ZIndex = Window.Elements.Footer.ZIndex + 2
                    }, {
                        Font = "FontSecondary",
                        TextColor3 = "TextPrimary",
                        BackgroundColor3 = "Tertiary"
                    }, Theme)
                    local Button = EngProject.Utility:CreateInstance("TextButton", ButtonProperties,
                        Window.Elements.FooterContent)
                    EngProject.Utility:CreateInstance("UICorner", {
                        CornerRadius = UDim.new(0, EngProject.Constants.Corner.Medium)
                    }, Button)
                    if not EngProject.Utility:IsMobile() then
                        Button.MouseEnter:Connect(function()
                            TweenService:Create(Button, TweenInfo.new(0.15), {
                                BackgroundColor3 = Theme.TertiaryHover
                            }):Play()
                        end)
                        Button.MouseLeave:Connect(function()
                            TweenService:Create(Button, TweenInfo.new(0.15), {
                                BackgroundColor3 = Theme.Tertiary
                            }):Play()
                        end)
                    end
                    if Item.Callback then
                        Button.Activated:Connect(function()
                            TweenService:Create(Button, TweenInfo.new(0.1), {
                                BackgroundColor3 = Theme.TertiaryPressed
                            }):Play()
                            task.wait(0.1)
                            TweenService:Create(Button, TweenInfo.new(0.1), {
                                BackgroundColor3 = Theme.Tertiary
                            }):Play()
                            EngProject.ErrorHandler:Try(Item.Callback)
                        end)
                    end
                    if Item.Id then
                        Window.Elements[Item.Id] = Button
                    end
                    if ButtonBindings then
                        EngProject.ThemeManager:RegisterElement(Window, Button, ButtonBindings)
                    end
                elseif Item.Type == "Spacer" then
                    EngProject.Utility:CreateInstance("Frame", {
                        Name = "Spacer",
                        LayoutOrder = Item.Order or 1,
                        Size = UDim2.new(0, Item.Width or 10, 1, 0),
                        BackgroundTransparency = 1
                    }, Window.Elements.FooterContent)
                end
            end
        end

        function EngProject.WindowBuilder:SetupResizing(MainFrame, UIScale, Options, ResizeParent, ResizeMode, Theme)
            if not Options.CanResize or not ResizeParent then
                return nil, nil
            end

            local IsCenter = ResizeMode == EngProject.Constants.Window.ResizeModes.Center

            local ResizeHandle = EngProject.Utility:CreateInstance("TextButton", {
                Name = "ResizeHandle",
                Size = UDim2.fromOffset(16, 16),
                Position = UDim2.fromScale(1, 1),
                AnchorPoint = Vector2.new(1, 1),
                BackgroundTransparency = 0.8,
                BackgroundColor3 = Color3.fromRGB(100, 100, 110),
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                ZIndex = EngProject.Constants.ZIndex.Modal
            }, ResizeParent)

            EngProject.Utility:CreateInstance("UICorner", {
                CornerRadius = UDim.new(1, 0)
            }, ResizeHandle)

            local IconImage = EngProject.Utility:CreateInstance("ImageLabel", {
                Size = UDim2.fromScale(0.7, 0.7),
                Position = UDim2.fromScale(0.5, 0.5),
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundTransparency = 1,
                Image = "rbxassetid://16898613613",
                ImageRectSize = Vector2.new(48, 48),
                ImageRectOffset = Vector2.new(967, 49),
                ImageColor3 = Theme.TextPrimary or Color3.fromRGB(200, 200, 210),
                ZIndex = EngProject.Constants.ZIndex.Modal + 1
            }, ResizeHandle)

            local StartPos
            local FrameSize
            local FramePos
            local Dragging = false
            local Changed

            ResizeHandle.InputBegan:Connect(function(input)
                if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~=
                    Enum.UserInputType.Touch then
                    return
                end

                StartPos = input.Position
                FrameSize = MainFrame.Size
                FramePos = MainFrame.Position
                Dragging = true

                if IsCenter then
                    MainFrame.AnchorPoint = Vector2.new(0, 0)
                    MainFrame.Position = UDim2.new(FramePos.X.Scale, FramePos.X.Offset - FrameSize.X.Offset / 2,
                        FramePos.Y.Scale, FramePos.Y.Offset - FrameSize.Y.Offset / 2)
                    FramePos = MainFrame.Position
                end

                Changed = input.Changed:Connect(function()
                    if input.UserInputState ~= Enum.UserInputState.End then
                        return
                    end

                    Dragging = false
                    if IsCenter then
                        local centerX = FramePos.X.Offset + MainFrame.Size.X.Offset / 2
                        local centerY = FramePos.Y.Offset + MainFrame.Size.Y.Offset / 2
                        MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
                        MainFrame.Position = UDim2.new(FramePos.X.Scale, centerX, FramePos.Y.Scale, centerY)
                    end
                    if Changed and Changed.Connected then
                        Changed:Disconnect()
                        Changed = nil
                    end
                end)
            end)

            UserInputService.InputChanged:Connect(function(input)
                if not MainFrame.Visible then
                    Dragging = false
                    if Changed and Changed.Connected then
                        Changed:Disconnect()
                        Changed = nil
                    end
                    return
                end

                if Dragging and
                    (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType ==
                        Enum.UserInputType.Touch) then
                    local Delta = input.Position - StartPos

                    local newWidth = math.clamp(FrameSize.X.Offset + Delta.X, EngProject.Constants.Window.MinSize.X,
                        EngProject.Constants.Window.MaxSize.X)
                    local newHeight = math.clamp(FrameSize.Y.Offset + Delta.Y, EngProject.Constants.Window.MinSize.Y,
                        EngProject.Constants.Window.MaxSize.Y)

                    MainFrame.Size = UDim2.new(FrameSize.X.Scale, newWidth, FrameSize.Y.Scale, newHeight)
                end
            end)

            return ResizeHandle, IconImage, {
                [ResizeHandle] = {
                    BackgroundColor3 = "TextSecondary"
                },
                [IconImage] = {
                    ImageColor3 = "TextPrimary"
                }
            }
        end

        function EngProject.WindowBuilder:SetupScrollUpdates(WindowInstance)
            task.defer(function()
                local function UpdateContainers()
                    task.wait()
                    WindowInstance.Elements.TabsContainer = EngProject.ScrollManager:Update(WindowInstance.Elements
                                                                                              .TabsContainer)
                    if WindowInstance.ActivePage then
                        WindowInstance.ActivePage = EngProject.ScrollManager:Update(WindowInstance.ActivePage)
                    end
                end
                UpdateContainers()
                WindowInstance.Elements.TabsContainer.ChildAdded:Connect(UpdateContainers)
                WindowInstance.Elements.TabsContainer.ChildRemoved:Connect(UpdateContainers)
                WindowInstance.Elements.ContentsContainer.ChildAdded:Connect(function(Child)
                    if Child:IsA("Frame") then
                        local Layout = Child:FindFirstChildWhichIsA("UIListLayout")
                        if Layout then
                            Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                                if Child == WindowInstance.ActivePage then
                                    WindowInstance.ActivePage = EngProject.ScrollManager:Update(Child)
                                end
                            end)
                        end
                        local function UpdatePage()
                            if Child == WindowInstance.ActivePage then
                                task.wait()
                                WindowInstance.ActivePage = EngProject.ScrollManager:Update(Child)
                            end
                        end
                        Child.ChildAdded:Connect(UpdatePage)
                        Child.ChildRemoved:Connect(UpdatePage)
                    end
                end)
            end)
        end
    end

    EngProject.SectionManager = {}
    do
        function EngProject.SectionManager:CreateSimpleSection(Page, Text, Options, Theme, Window, Style)
            local LABEL_HEIGHT = 26
            local TEXT_SIZE = Options.TextSize or 19
            local LABEL_TEXT = Text or "Section"

            local StyleDefs = {
                sidebar = {
                    SectionHeight = LABEL_HEIGHT + 4,
                    Indent = 10
                },
                notch = {
                    SectionHeight = LABEL_HEIGHT + 4,
                    Indent = 16
                },
                filled = {
                    SectionHeight = LABEL_HEIGHT + 8,
                    Indent = 14
                },
                inset = {
                    SectionHeight = LABEL_HEIGHT + 6,
                    Indent = 10
                },
                stepped = {
                    SectionHeight = LABEL_HEIGHT + 10,
                    Indent = 8
                },
                panel = {
                    SectionHeight = LABEL_HEIGHT + 8,
                    Indent = 14
                }
            }

            local Def = StyleDefs[Style] or {
                SectionHeight = LABEL_HEIGHT + 4,
                Indent = 0
            }
            local SECTION_HEIGHT = Def.SectionHeight
            local INDENT = Def.Indent
            local LabelY = math.floor((SECTION_HEIGHT - LABEL_HEIGHT) / 2)

            local AccentElement, AccentBindings, ExtraElements = nil, {}, {}

            local Section = EngProject.Utility:CreateInstance("Frame", {
                Name = "Section",
                Size = UDim2.new(1, 0, 0, SECTION_HEIGHT),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ClipsDescendants = false,
                ZIndex = EngProject.Constants.ZIndex.Control
            }, Page)

            local LabelProperties, LabelBindings = EngProject.Utility:ApplyTheme({
                Size = UDim2.new(1, -INDENT, 0, LABEL_HEIGHT),
                Position = UDim2.new(0, INDENT, 0, LabelY),
                Text = LABEL_TEXT,
                TextSize = TEXT_SIZE,
                TextXAlignment = Enum.TextXAlignment.Left,
                BackgroundTransparency = 1,
                ZIndex = EngProject.Constants.ZIndex.Overlay
            }, {
                Font = "FontPrimary",
                TextColor3 = "TextActive"
            }, Theme)
            local Label = EngProject.Utility:CreateInstance("TextLabel", LabelProperties, Section)

            if Style == "sidebar" then
                local Thickness = Options.BarThickness or 3
                local BarProps, BarBindings = EngProject.Utility:ApplyTheme({
                    Size = UDim2.new(0, Thickness, 0, LABEL_HEIGHT),
                    Position = UDim2.new(0, 0, 0, LabelY),
                    BorderSizePixel = 0,
                    ZIndex = EngProject.Constants.ZIndex.Overlay
                }, {
                    BackgroundColor3 = "Accent"
                }, Theme)
                local Bar = EngProject.Utility:CreateInstance("Frame", BarProps, Section)
                EngProject.Utility:CreateInstance("UICorner", {
                    CornerRadius = UDim.new(1, 0)
                }, Bar)
                AccentElement, AccentBindings = Bar, BarBindings

            elseif Style == "notch" then
                local NOTCH_SIZE = 6
                local NotchProps, NotchBindings = EngProject.Utility:ApplyTheme({
                    Size = UDim2.new(0, NOTCH_SIZE, 0, NOTCH_SIZE),
                    Position = UDim2.new(0, 2, 0, LabelY + math.floor((LABEL_HEIGHT - NOTCH_SIZE) / 2)),
                    Rotation = 45,
                    BorderSizePixel = 0,
                    ZIndex = EngProject.Constants.ZIndex.Overlay
                }, {
                    BackgroundColor3 = "Accent"
                }, Theme)
                local Notch = EngProject.Utility:CreateInstance("Frame", NotchProps, Section)
                AccentElement, AccentBindings = Notch, NotchBindings

            elseif Style == "filled" then
                local STRIPE_WIDTH = Options.StripeWidth or 4

                local BgProps, BgBindings = EngProject.Utility:ApplyTheme({
                    Size = UDim2.new(1, 0, 1, 0),
                    Position = UDim2.new(0, 0, 0, 0),
                    BackgroundTransparency = 0.88,
                    BorderSizePixel = 0,
                    ZIndex = EngProject.Constants.ZIndex.Overlay - 2
                }, {
                    BackgroundColor3 = "Accent"
                }, Theme)
                local Bg = EngProject.Utility:CreateInstance("Frame", BgProps, Section)
                EngProject.Utility:CreateInstance("UICorner", {
                    CornerRadius = UDim.new(0, 4)
                }, Bg)
                EngProject.Utility:CreateInstance("UIGradient", {
                    Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0),
                                                       NumberSequenceKeypoint.new(0.6, 0),
                                                       NumberSequenceKeypoint.new(1, 1)}),
                    Rotation = 0
                }, Bg)

                local StripeProps, StripeBindings = EngProject.Utility:ApplyTheme({
                    Size = UDim2.new(0, STRIPE_WIDTH, 1, 0),
                    Position = UDim2.new(0, 0, 0, 0),
                    BorderSizePixel = 0,
                    ZIndex = EngProject.Constants.ZIndex.Overlay - 1
                }, {
                    BackgroundColor3 = "Accent"
                }, Theme)
                local Stripe = EngProject.Utility:CreateInstance("Frame", StripeProps, Section)
                EngProject.Utility:CreateInstance("UICorner", {
                    CornerRadius = UDim.new(0, 2)
                }, Stripe)

                AccentElement, AccentBindings = Stripe, StripeBindings
                table.insert(ExtraElements, {
                    Element = Bg,
                    Bindings = BgBindings
                })

            elseif Style == "inset" then
                local FillProps, FillBindings = EngProject.Utility:ApplyTheme({
                    Size = UDim2.new(1, 0, 1, 0),
                    Position = UDim2.new(0, 0, 0, 0),
                    BackgroundTransparency = 0.92,
                    BorderSizePixel = 0,
                    ZIndex = EngProject.Constants.ZIndex.Overlay - 2
                }, {
                    BackgroundColor3 = "Accent"
                }, Theme)
                local Fill = EngProject.Utility:CreateInstance("Frame", FillProps, Section)

                local TopProps, TopBindings = EngProject.Utility:ApplyTheme({
                    Size = UDim2.new(1, 0, 0, 1),
                    Position = UDim2.new(0, 0, 0, 0),
                    BackgroundTransparency = 0.5,
                    BorderSizePixel = 0,
                    ZIndex = EngProject.Constants.ZIndex.Overlay - 1
                }, {
                    BackgroundColor3 = "Accent"
                }, Theme)
                local TopLine = EngProject.Utility:CreateInstance("Frame", TopProps, Section)

                local BotProps, BotBindings = EngProject.Utility:ApplyTheme({
                    Size = UDim2.new(1, 0, 0, 1),
                    Position = UDim2.new(0, 0, 1, -1),
                    BackgroundTransparency = 0.5,
                    BorderSizePixel = 0,
                    ZIndex = EngProject.Constants.ZIndex.Overlay - 1
                }, {
                    BackgroundColor3 = "Accent"
                }, Theme)
                local BotLine = EngProject.Utility:CreateInstance("Frame", BotProps, Section)

                AccentElement, AccentBindings = TopLine, TopBindings
                table.insert(ExtraElements, {
                    Element = BotLine,
                    Bindings = BotBindings
                })
                table.insert(ExtraElements, {
                    Element = Fill,
                    Bindings = FillBindings
                })

            elseif Style == "stepped" then
                local LINE_Y = SECTION_HEIGHT - 3
                local CAP_HEIGHT = 3
                local CAP_WIDTH = Options.CapWidth or 36

                local CapProps, CapBindings = EngProject.Utility:ApplyTheme({
                    Size = UDim2.new(0, CAP_WIDTH, 0, CAP_HEIGHT),
                    Position = UDim2.new(0, 0, 0, LINE_Y - CAP_HEIGHT + 1),
                    BorderSizePixel = 0,
                    ZIndex = EngProject.Constants.ZIndex.Overlay
                }, {
                    BackgroundColor3 = "Accent"
                }, Theme)
                local Cap = EngProject.Utility:CreateInstance("Frame", CapProps, Section)
                EngProject.Utility:CreateInstance("UICorner", {
                    CornerRadius = UDim.new(0, 2)
                }, Cap)

                local HairProps, HairBindings = EngProject.Utility:ApplyTheme({
                    Size = UDim2.new(1, -CAP_WIDTH, 0, 1),
                    Position = UDim2.new(0, CAP_WIDTH, 0, LINE_Y),
                    BackgroundTransparency = 0.55,
                    BorderSizePixel = 0,
                    ZIndex = EngProject.Constants.ZIndex.Overlay - 1
                }, {
                    BackgroundColor3 = "Accent"
                }, Theme)
                local Hair = EngProject.Utility:CreateInstance("Frame", HairProps, Section)

                AccentElement, AccentBindings = Cap, CapBindings
                table.insert(ExtraElements, {
                    Element = Hair,
                    Bindings = HairBindings
                })

            elseif Style == "panel" then
                local STRIPE_WIDTH = Options.StripeWidth or 3

                local BgProps, BgBindings = EngProject.Utility:ApplyTheme({
                    Size = UDim2.new(1, 0, 1, 0),
                    Position = UDim2.new(0, 0, 0, 0),
                    BackgroundTransparency = 0.78,
                    BorderSizePixel = 0,
                    ZIndex = EngProject.Constants.ZIndex.Overlay - 2
                }, {
                    BackgroundColor3 = "Accent"
                }, Theme)
                local Bg = EngProject.Utility:CreateInstance("Frame", BgProps, Section)
                EngProject.Utility:CreateInstance("UIGradient", {
                    Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0),
                                                       NumberSequenceKeypoint.new(0.45, 0),
                                                       NumberSequenceKeypoint.new(1, 1)}),
                    Rotation = 0
                }, Bg)

                local StripeProps, StripeBindings = EngProject.Utility:ApplyTheme({
                    Size = UDim2.new(0, STRIPE_WIDTH, 1, 0),
                    Position = UDim2.new(0, 0, 0, 0),
                    BorderSizePixel = 0,
                    ZIndex = EngProject.Constants.ZIndex.Overlay - 1
                }, {
                    BackgroundColor3 = "Accent"
                }, Theme)
                local Stripe = EngProject.Utility:CreateInstance("Frame", StripeProps, Section)

                local BottomProps, BottomBindings = EngProject.Utility:ApplyTheme({
                    Size = UDim2.new(1, 0, 0, 1),
                    Position = UDim2.new(0, 0, 1, -1),
                    BackgroundTransparency = 0.65,
                    BorderSizePixel = 0,
                    ZIndex = EngProject.Constants.ZIndex.Overlay - 1
                }, {
                    BackgroundColor3 = "Accent"
                }, Theme)
                local Bottom = EngProject.Utility:CreateInstance("Frame", BottomProps, Section)

                AccentElement, AccentBindings = Stripe, StripeBindings
                table.insert(ExtraElements, {
                    Element = Bg,
                    Bindings = BgBindings
                })
                table.insert(ExtraElements, {
                    Element = Bottom,
                    Bindings = BottomBindings
                })
            end

            if Window then
                local Batch = {
                    [Label] = LabelBindings
                }
                if AccentElement then
                    Batch[AccentElement] = AccentBindings
                end
                for _, Entry in ipairs(ExtraElements) do
                    Batch[Entry.Element] = Entry.Bindings
                end
                EngProject.ThemeManager:RegisterMultiple(Window, Batch)
            end

            return {
                SetText = function(self, NewText)
                    Label.Text = NewText
                end,

                SetTextSize = function(self, Size)
                    Label.TextSize = Size
                end,

                SetVisible = function(self, Visible)
                    Section.Visible = Visible
                end,

                GetElements = function(self)
                    return {
                        Section = Section,
                        Label = Label,
                        Accent = AccentElement
                    }
                end
            }
        end

        function EngProject.SectionManager:CreateBoxSection(Page, Text, Options, Theme, Window)
            if not Page or not Page.Parent then
                EngProject.ErrorHandler:Guard(false, "CreateBoxSection", "Page is nil or unparented",
                    EngProject.ErrorHandler.Levels.ERROR)
                return nil
            end
            Options = type(Options) == "table" and Options or {}
            Theme = type(Theme) == "table" and Theme or EngProject.Themes.DefaultTheme
            Text = type(Text) == "string" and Text or "Section"

            local U = EngProject.Utility
            local TM = EngProject.ThemeManager
            local CORNER = EngProject.Constants.Corner.Medium
            local PAD = EngProject.Constants.Padding
            local ZI = EngProject.Constants.ZIndex
            local HEADER_H = 36
            local TWEEN_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            local IsExpanded = Options.DefaultExpanded ~= false

            local function GetWindowScale()
                if Window and Window.Scale and typeof(Window.Scale) == "Instance" then
                    local ok, scale = pcall(function()
                        return Window.Scale.Scale
                    end)
                    if ok and type(scale) == "number" and scale > 0 then
                        return scale
                    end
                end
                return 1
            end

            local function Tween(Object, Properties)
                if not Object or not Object.Parent then
                    return
                end
                local ok, err = pcall(function()
                    TweenService:Create(Object, TWEEN_INFO, Properties):Play()
                end)
                if not ok then
                    EngProject.ErrorHandler:Guard(false, "CreateBoxSection:Tween", tostring(err),
                        EngProject.ErrorHandler.Levels.WARN)
                end
            end

            local Section = U:CreateInstance("Frame", {
                Name = "BoxSection",
                Size = UDim2.new(1, 0, 0, HEADER_H),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ClipsDescendants = false,
                ZIndex = ZI.Control
            }, Page)

            local Border = U:CreateInstance("Frame", {
                Name = "Border",
                Size = UDim2.new(1, 0, 0, HEADER_H),
                Position = UDim2.new(0, 0, 0, 0),
                BackgroundColor3 = Theme.BoxBackground or Theme.Secondary,
                BackgroundTransparency = Theme.TransparencySecondary,
                BorderSizePixel = 0,
                ZIndex = ZI.Control
            }, Section)
            U:CreateInstance("UICorner", {
                CornerRadius = UDim.new(0, CORNER)
            }, Border)

            local Stroke = U:CreateInstance("UIStroke", {
                Color = Theme.Separator,
                Thickness = 1,
                Transparency = Theme.SeparatorTransparency,
                ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            }, Border)

            local HeaderContainer = U:CreateInstance("Frame", {
                Name = "HeaderContainer",
                Size = UDim2.new(1, 0, 0, HEADER_H),
                BackgroundTransparency = 1,
                ZIndex = ZI.Control + 1
            }, Border)
            U:CreateInstance("UIPadding", {
                PaddingLeft = UDim.new(0, PAD.Medium),
                PaddingRight = UDim.new(0, PAD.Medium)
            }, HeaderContainer)

            local HeaderContent = U:CreateInstance("Frame", {
                Name = "HeaderContent",
                Size = UDim2.new(1, -(20 + PAD.Medium), 1, 0),
                BackgroundTransparency = 1,
                ZIndex = ZI.Control + 1
            }, HeaderContainer)
            U:CreateInstance("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                Padding = UDim.new(0, PAD.Medium)
            }, HeaderContent)

            local IconContainer = nil
            if Options.Icon then
                IconContainer = U:CreateInstance("Frame", {
                    Name = "IconContainer",
                    Size = UDim2.new(0, 20, 0, 20),
                    BackgroundTransparency = 1,
                    ZIndex = ZI.Control + 1,
                    LayoutOrder = 1
                }, HeaderContent)

                local rawIcon = Options.Icon
                local iconData = EngProject.IconManager:WrapIcon(
                    type(rawIcon) == "table" and rawIcon or {
                        Image = rawIcon
                    })

                if iconData then
                    U:CreateInstance("ImageLabel", {
                        Name = "Icon",
                        Size = UDim2.new(1, 0, 1, 0),
                        BackgroundTransparency = 1,
                        Image = iconData.Url,
                        ImageColor3 = (type(rawIcon) == "table" and rawIcon.ImageColor3) or Theme.TextPrimary,
                        ImageRectOffset = iconData.ImageRectOffset,
                        ImageRectSize = iconData.ImageRectSize,
                        ZIndex = ZI.Control + 1
                    }, IconContainer)
                end
            end

            local Title = U:CreateInstance("TextLabel", {
                Name = "Title",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = Text,
                TextColor3 = Theme.TextActive,
                Font = Theme.FontPrimary,
                TextSize = type(Options.TextSize) == "number" and Options.TextSize or 15,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Center,
                TextTruncate = Enum.TextTruncate.AtEnd,
                ZIndex = ZI.Control + 1,
                LayoutOrder = 2
            }, HeaderContent)

            local Arrow = U:CreateInstance("ImageLabel", {
                Name = "Arrow",
                Size = UDim2.new(0, 12, 0, 12),
                Position = UDim2.new(1, 0, 0.5, 0),
                AnchorPoint = Vector2.new(1, 0.5),
                BackgroundTransparency = 1,
                Image = "rbxassetid://10709790948",
                ImageColor3 = Theme.TextPrimary,
                Rotation = IsExpanded and 0 or -90,
                ZIndex = ZI.Control + 1
            }, HeaderContainer)

            local Content = U:CreateInstance("Frame", {
                Name = "Content",
                Size = UDim2.new(1, 0, 0, 0),
                Position = UDim2.new(0, 0, 0, HEADER_H),
                BackgroundTransparency = 1,
                ClipsDescendants = true,
                ZIndex = ZI.Control + 1
            }, Border)

            Content:SetAttribute("IsDualScroll", false)

            local ContentPadding = U:CreateInstance("UIPadding", {
                PaddingTop = UDim.new(0, PAD.Medium),
                PaddingBottom = UDim.new(0, PAD.Large),
                PaddingLeft = UDim.new(0, PAD.Medium),
                PaddingRight = UDim.new(0, PAD.Medium)
            }, Content)

            local ListLayout = U:CreateInstance("UIListLayout", {
                Padding = UDim.new(0, EngProject.Constants.Spacing.Loose),
                SortOrder = Enum.SortOrder.LayoutOrder
            }, Content)

            local ClickButton = U:CreateInstance("TextButton", {
                Name = "ClickButton",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
                ZIndex = ZI.Modal
            }, HeaderContainer)

            local function CalculateContentHeight()
                local scale = GetWindowScale()
                local logicalContent = ListLayout.AbsoluteContentSize.Y / scale
                return logicalContent + ContentPadding.PaddingTop.Offset + ContentPadding.PaddingBottom.Offset
            end

            local function SetExpandedSize()
                if not IsExpanded then
                    return
                end
                local contentH = CalculateContentHeight()
                local totalH = HEADER_H + contentH
                Tween(Content, {
                    Size = UDim2.new(1, 0, 0, contentH)
                })
                Tween(Border, {
                    Size = UDim2.new(1, 0, 0, totalH)
                })
                Tween(Section, {
                    Size = UDim2.new(1, 0, 0, totalH)
                })
            end

            local function SetCollapsedSize()
                Tween(Content, {
                    Size = UDim2.new(1, 0, 0, 0)
                })
                Tween(Border, {
                    Size = UDim2.new(1, 0, 0, HEADER_H)
                })
                Tween(Section, {
                    Size = UDim2.new(1, 0, 0, HEADER_H)
                })
            end

            local ToggleDebounce = false

            local function Toggle()
                if ToggleDebounce then
                    return
                end
                ToggleDebounce = true
                task.delay(0.1, function()
                    ToggleDebounce = false
                end)

                IsExpanded = not IsExpanded
                Tween(Arrow, {
                    Rotation = IsExpanded and 0 or -90
                })
                if IsExpanded then
                    SetExpandedSize()
                else
                    SetCollapsedSize()
                end
            end

            ClickButton.Activated:Connect(Toggle)

            local resizePending = false
            local function RequestResize()
                if not IsExpanded or resizePending then
                    return
                end
                resizePending = true
                task.defer(function()
                    resizePending = false
                    if Section.Parent then
                        SetExpandedSize()
                    end
                end)
            end

            Content.ChildAdded:Connect(RequestResize)
            Content.ChildRemoved:Connect(RequestResize)
            ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(RequestResize)

            if Window and Window.Scale and typeof(Window.Scale) == "Instance" then
                Window.Scale:GetPropertyChangedSignal("Scale"):Connect(function()
                    if IsExpanded and Section.Parent then
                        local contentH = CalculateContentHeight()
                        local totalH = HEADER_H + contentH
                        Content.Size = UDim2.new(1, 0, 0, contentH)
                        Border.Size = UDim2.new(1, 0, 0, totalH)
                        Section.Size = UDim2.new(1, 0, 0, totalH)
                    end
                end)
            end

            if IsExpanded then
                task.defer(SetExpandedSize)
            end

            if Window then
                local themeTargets = {
                    [Border] = {
                        BackgroundColor3 = "BoxBackground",
                        BackgroundTransparency = "TransparencySecondary"
                    },
                    [Stroke] = {
                        Color = "Separator",
                        Transparency = "SeparatorTransparency"
                    },
                    [Title] = {
                        TextColor3 = "TextActive",
                        Font = "FontPrimary"
                    },
                    [Arrow] = {
                        ImageColor3 = "TextPrimary"
                    }
                }

                if IconContainer then
                    local iconEl = IconContainer:FindFirstChild("Icon")
                    if iconEl then
                        local hasExplicitColor = type(Options.Icon) == "table" and Options.Icon.ImageColor3 ~= nil
                        if not hasExplicitColor then
                            themeTargets[iconEl] = {
                                ImageColor3 = "TextPrimary"
                            }
                        end
                    end
                end

                TM:RegisterMultiple(Window, themeTargets)
            end

            return {
                Container = Content,
                Section = Section,
                Header = HeaderContainer,
                Title = Title,
                Arrow = Arrow,
                IconContainer = IconContainer,

                SetExpanded = function(_, value)
                    if type(value) ~= "boolean" then
                        return
                    end
                    if value ~= IsExpanded then
                        Toggle()
                    end
                end,

                IsExpanded = function()
                    return IsExpanded
                end,

                Refresh = function()
                    if IsExpanded then
                        SetExpandedSize()
                    end
                end,

                SetTitle = function(_, newText)
                    if type(newText) == "string" then
                        Title.Text = newText
                    end
                end
            }
        end
    end

    EngProject.IconManager = {}
    do
        function EngProject.IconManager:WrapIcon(IconInput)
            if not IconInput then
                return nil
            end

            if type(IconInput) == "table" and IconInput.Image then
                return {
                    Url = IconInput.Image,
                    ImageRectOffset = IconInput.ImageRectOffset or Vector2.zero,
                    ImageRectSize = IconInput.ImageRectSize or Vector2.zero
                }
            end

            return {
                Url = tostring(IconInput),
                ImageRectOffset = Vector2.zero,
                ImageRectSize = Vector2.zero
            }
        end
    end

    EngProject.NotificationManager = {}
    do
        local ActiveNotifications = {}

        function EngProject.NotificationManager:Initialize()
            if self.Initialized then
                return
            end
            self.Initialized = true
            self.Container = nil
            self.ScreenGui = nil
        end

        function EngProject.NotificationManager:GetScreenGui()
            if self.ScreenGui and self.ScreenGui.Parent then
                return self.ScreenGui
            end

            local ScreenGui = EngProject.Utility:CreateInstance("ScreenGui", {
                Name = EngProject.Utility:GenerateId(),
                ResetOnSpawn = false,
                ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
                DisplayOrder = EngProject.Constants.ZIndex.Notification
            })

            EngProject.Utility:ParentUI(ScreenGui)
            self.ScreenGui = ScreenGui
            return ScreenGui
        end

        function EngProject.NotificationManager:GetContainer()
            if self.Container and self.Container.Parent then
                return self.Container
            end

            local ScreenGui = self:GetScreenGui()
            local Scale = EngProject.Utility:IsMobile() and 0.5 or 1

            local Parent = EngProject.Utility:CreateInstance("Frame", {
                Name = EngProject.Utility:GenerateId(),
                Size = UDim2.fromScale(1, 1),
                Position = UDim2.fromScale(0, 0),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ZIndex = EngProject.Constants.ZIndex.Notification
            }, ScreenGui)

            EngProject.Utility:CreateInstance("UIScale", {
                Scale = Scale
            }, Parent)

            self.Container = Parent

            local Holder = EngProject.Utility:CreateInstance("Frame", {
                Name = EngProject.Utility:GenerateId(),
                Position = UDim2.new(1, -20, 0, 20),
                AnchorPoint = Vector2.new(1, 0),
                Size = UDim2.new(0, 360, 1, -40),
                BackgroundTransparency = 1,
                ZIndex = EngProject.Constants.ZIndex.Notification
            }, Parent)

            EngProject.Utility:CreateInstance("UIListLayout", {
                FillDirection = Enum.FillDirection.Vertical,
                VerticalAlignment = Enum.VerticalAlignment.Top,
                HorizontalAlignment = Enum.HorizontalAlignment.Right,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 10)
            }, Holder)

            pcall(protectgui, Parent)

            return Parent
        end

        function EngProject.NotificationManager:GetHolder()
            local Container = self:GetContainer()
            for _, Child in ipairs(Container:GetChildren()) do
                if Child:IsA("Frame") then
                    local Layout = Child:FindFirstChildOfClass("UIListLayout")
                    if Layout then
                        return Child
                    end
                end
            end
            return Container
        end

        function EngProject.NotificationManager:CreateNotificationUI(Config)
            local Theme = EngProject.Themes.Obsidian
            local Holder = self:GetHolder()
            local IsMobile = EngProject.Utility:IsMobile()
            local HasDuration = Config.Duration and Config.Duration > 0

            local TypeColors = {
                Default = Theme.Accent,
                Info = Color3.fromRGB(30, 144, 255),
                Success = Color3.fromRGB(40, 187, 109),
                Warning = Color3.fromRGB(255, 193, 7),
                Error = Color3.fromRGB(220, 60, 69)
            }
            local TypeTags = {
                Default = "NOTICE",
                Info = "INFO",
                Success = "SUCCESS",
                Warning = "WARNING",
                Error = "ERROR"
            }

            local Accent = TypeColors[Config.Type] or Config.Color or Theme.Accent
            local LightAccent = Accent:Lerp(Color3.new(1, 1, 1), 0.4)
            local TagText = Config.Tag or TypeTags[Config.Type] or "NOTICE"
            local BasePad = IsMobile and 8 or 10
            local SidePad = IsMobile and 10 or 12

            local Notification = EngProject.Utility:CreateInstance("Frame", {
                Name = EngProject.Utility:GenerateId(),
                Size = UDim2.new(1, 0, 0, 0),
                BackgroundColor3 = Theme.Secondary,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ClipsDescendants = false,
                ZIndex = EngProject.Constants.ZIndex.Notification,
                LayoutOrder = tick()
            }, Holder)

            local AccentBar = EngProject.Utility:CreateInstance("Frame", {
                Name = EngProject.Utility:GenerateId(),
                Size = UDim2.new(0, 3, 1, 0),
                BackgroundColor3 = Accent,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ZIndex = EngProject.Constants.ZIndex.Notification + 1
            }, Notification)

            local Shadow = EngProject.Utility:CreateInstance("ImageLabel", {
                Name = EngProject.Utility:GenerateId(),
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, 0, 0.5, 0),
                Size = UDim2.new(1, 20, 1, 20),
                BackgroundTransparency = 1,
                Image = "rbxassetid://7717391613",
                ImageColor3 = Color3.new(0, 0, 0),
                ImageTransparency = 1,
                ScaleType = Enum.ScaleType.Slice,
                SliceCenter = Rect.new(100, 100, 100, 100),
                ZIndex = EngProject.Constants.ZIndex.Notification - 1
            }, Notification)

            local Content = EngProject.Utility:CreateInstance("Frame", {
                Name = EngProject.Utility:GenerateId(),
                Position = UDim2.new(0, 3, 0, 0),
                Size = UDim2.new(1, -3, 1, 0),
                BackgroundTransparency = 1,
                ZIndex = EngProject.Constants.ZIndex.Notification + 2
            }, Notification)

            EngProject.Utility:CreateInstance("UIPadding", {
                PaddingTop = UDim.new(0, BasePad),
                PaddingBottom = UDim.new(0, BasePad),
                PaddingLeft = UDim.new(0, SidePad),
                PaddingRight = UDim.new(0, IsMobile and 26 or 30)
            }, Content)

            local TextContainer = EngProject.Utility:CreateInstance("Frame", {
                Name = EngProject.Utility:GenerateId(),
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                ZIndex = EngProject.Constants.ZIndex.Notification + 2
            }, Content)

            EngProject.Utility:CreateInstance("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                Padding = UDim.new(0, IsMobile and 2 or 3)
            }, TextContainer)

            local TitleRow = EngProject.Utility:CreateInstance("Frame", {
                Name = EngProject.Utility:GenerateId(),
                Size = UDim2.new(1, Config.Closable ~= false and -(IsMobile and 22 or 26) or 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                LayoutOrder = 1,
                ZIndex = EngProject.Constants.ZIndex.Notification + 2
            }, TextContainer)

            EngProject.Utility:CreateInstance("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 5)
            }, TitleRow)

            local TitleLabel = EngProject.Utility:CreateInstance("TextLabel", {
                Name = EngProject.Utility:GenerateId(),
                Size = UDim2.new(0, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.XY,
                BackgroundTransparency = 1,
                Text = Config.Title or "Notification",
                TextColor3 = Theme.TextActive,
                TextTransparency = 1,
                TextSize = IsMobile and 12 or 13,
                Font = Theme.FontPrimary,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextWrapped = false,
                RichText = true,
                LineHeight = 1.1,
                LayoutOrder = 1,
                ZIndex = EngProject.Constants.ZIndex.Notification + 3
            }, TitleRow)

            local Tag = EngProject.Utility:CreateInstance("TextLabel", {
                Name = EngProject.Utility:GenerateId(),
                Size = UDim2.new(0, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.XY,
                BackgroundColor3 = Accent,
                BackgroundTransparency = 1,
                Text = TagText,
                TextColor3 = LightAccent,
                TextTransparency = 1,
                TextSize = IsMobile and 8 or 9,
                Font = Theme.FontPrimary,
                TextXAlignment = Enum.TextXAlignment.Left,
                LayoutOrder = 2,
                ZIndex = EngProject.Constants.ZIndex.Notification + 3
            }, TitleRow)

            EngProject.Utility:CreateInstance("UICorner", {
                CornerRadius = UDim.new(0, 3)
            }, Tag)
            EngProject.Utility:CreateInstance("UIPadding", {
                PaddingLeft = UDim.new(0, 5),
                PaddingRight = UDim.new(0, 5),
                PaddingTop = UDim.new(0, 2),
                PaddingBottom = UDim.new(0, 2)
            }, Tag)

            local DescriptionLabel = nil
            if Config.Description then
                DescriptionLabel = EngProject.Utility:CreateInstance("TextLabel", {
                    Name = EngProject.Utility:GenerateId(),
                    Size = UDim2.new(1, Config.Closable ~= false and -(IsMobile and 22 or 26) or 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Text = Config.Description,
                    TextColor3 = Theme.TextSecondary,
                    TextTransparency = 1,
                    TextSize = IsMobile and 11 or 12,
                    Font = Theme.FontSecondary,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextWrapped = true,
                    RichText = true,
                    LineHeight = 1.2,
                    LayoutOrder = 2,
                    ZIndex = EngProject.Constants.ZIndex.Notification + 3
                }, TextContainer)
            end

            if Config.Closable ~= false then
                local CloseBtn = EngProject.Utility:CreateInstance("TextButton", {
                    Name = EngProject.Utility:GenerateId(),
                    Position = UDim2.new(1, 0, 0, 0),
                    AnchorPoint = Vector2.new(1, 0),
                    Size = UDim2.new(0, IsMobile and 16 or 18, 0, IsMobile and 16 or 18),
                    BackgroundTransparency = 1,
                    Text = "×",
                    Font = Theme.FontPrimary,
                    TextSize = IsMobile and 18 or 20,
                    TextColor3 = Theme.TextInactive,
                    TextTransparency = 1,
                    AutoButtonColor = false,
                    ZIndex = EngProject.Constants.ZIndex.Notification + 5
                }, Content)

                CloseBtn.MouseEnter:Connect(function()
                    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {
                        TextColor3 = Color3.fromRGB(255, 85, 85),
                        Rotation = 90
                    }):Play()
                end)
                CloseBtn.MouseLeave:Connect(function()
                    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {
                        TextColor3 = Theme.TextInactive,
                        Rotation = 0
                    }):Play()
                end)
                CloseBtn.Activated:Connect(function()
                    EngProject.NotificationManager:Dismiss(Notification)
                end)
            end

            if Config.Callback then
                local ClickArea = EngProject.Utility:CreateInstance("TextButton", {
                    Name = EngProject.Utility:GenerateId(),
                    Size = UDim2.new(1, 0, 1, 0),
                    BackgroundTransparency = 1,
                    Text = "",
                    AutoButtonColor = false,
                    ZIndex = EngProject.Constants.ZIndex.Notification
                }, Notification)

                ClickArea.Activated:Connect(function()
                    EngProject.ErrorHandler:Try(function()
                        Config.Callback(Notification)
                    end)
                end)
                ClickArea.MouseEnter:Connect(function()
                    TweenService:Create(Notification, TweenInfo.new(0.15), {
                        BackgroundColor3 = Theme.SecondaryHover
                    }):Play()
                end)
                ClickArea.MouseLeave:Connect(function()
                    TweenService:Create(Notification, TweenInfo.new(0.15), {
                        BackgroundColor3 = Theme.Secondary
                    }):Play()
                end)
            end

            task.defer(function()
                task.wait()

                local TextH = 0
                for _, Child in ipairs(TextContainer:GetChildren()) do
                    if Child:IsA("TextLabel") or Child:IsA("Frame") then
                        TextH = TextH + Child.AbsoluteSize.Y
                    end
                end
                local Layout = TextContainer:FindFirstChildOfClass("UIListLayout")
                local ChildCount = 0
                for _, Child in ipairs(TextContainer:GetChildren()) do
                    if Child:IsA("TextLabel") or Child:IsA("Frame") then
                        ChildCount = ChildCount + 1
                    end
                end
                if Layout and ChildCount > 1 then
                    TextH = TextH + Layout.Padding.Offset * (ChildCount - 1)
                end

                local MinH = IsMobile and 38 or 42
                local CardH = math.max(TextH + BasePad * 2, MinH)
                local BarH = HasDuration and 2 or 0

                Notification.Size = UDim2.new(1, 0, 0, CardH + BarH)
                Notification.Position = UDim2.new(0, 0, 0, 0)
                Notification.BackgroundTransparency = 1
                Shadow.ImageTransparency = 1

                for _, Child in ipairs(Notification:GetDescendants()) do
                    if Child:IsA("TextLabel") or Child:IsA("TextButton") then
                        Child.TextTransparency = 1
                    elseif Child:IsA("ImageLabel") and Child.Name ~= Shadow.Name then
                        Child.ImageTransparency = 1
                    elseif Child:IsA("Frame") and Child ~= Notification then
                        Child.BackgroundTransparency = 1
                    end
                end

                local SlideInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
                local Tweens = {}

                table.insert(Tweens, TweenService:Create(Notification, SlideInfo, {
                    Position = UDim2.new(0, 0, 0, 0),
                    BackgroundTransparency = 0
                }))
                table.insert(Tweens, TweenService:Create(Shadow, SlideInfo, {
                    ImageTransparency = 0.75
                }))
                table.insert(Tweens, TweenService:Create(AccentBar, SlideInfo, {
                    BackgroundTransparency = 0
                }))
                table.insert(Tweens, TweenService:Create(Tag, SlideInfo, {
                    TextTransparency = 0,
                    BackgroundTransparency = 0.78
                }))

                for _, Child in ipairs(Notification:GetDescendants()) do
                    if Child:IsA("TextLabel") and Child.Name ~= Tag.Name then
                        table.insert(Tweens, TweenService:Create(Child, SlideInfo, {
                            TextTransparency = 0
                        }))
                    elseif Child:IsA("TextButton") then
                        table.insert(Tweens, TweenService:Create(Child, SlideInfo, {
                            TextTransparency = 0
                        }))
                    end
                end

                for _, Tween in ipairs(Tweens) do
                    Tween:Play()
                end

                if HasDuration then
                    local ProgressBar = EngProject.Utility:CreateInstance("Frame", {
                        Name = EngProject.Utility:GenerateId(),
                        Position = UDim2.new(0, 0, 1, -BarH),
                        Size = UDim2.new(1, 0, 0, BarH),
                        BackgroundColor3 = Accent,
                        BorderSizePixel = 0,
                        ZIndex = EngProject.Constants.ZIndex.Notification + 4
                    }, Notification)

                    TweenService:Create(ProgressBar, TweenInfo.new(Config.Duration, Enum.EasingStyle.Linear), {
                        Size = UDim2.new(0, 0, 0, BarH)
                    }):Play()

                    task.delay(Config.Duration, function()
                        if Notification and Notification.Parent then
                            EngProject.NotificationManager:Dismiss(Notification)
                        end
                    end)
                end
            end)

            return {
                Container = Notification,
                Title = TitleLabel,
                Description = DescriptionLabel,
                Tag = Tag,
                Content = Content,
                AccentBar = AccentBar
            }
        end

        function EngProject.NotificationManager:Dismiss(Notification)
            if not Notification or not Notification.Parent then
                return false
            end

            local FadeInfo = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
            local Shadow = Notification:FindFirstChild("Shadow")
            local Tweens = {}

            table.insert(Tweens, TweenService:Create(Notification, FadeInfo, {
                BackgroundTransparency = 1
            }))
            if Shadow then
                table.insert(Tweens, TweenService:Create(Shadow, FadeInfo, {
                    ImageTransparency = 1
                }))
            end

            for _, o in ipairs(Notification:GetDescendants()) do
                if o:IsA("TextLabel") or o:IsA("TextButton") then
                    table.insert(Tweens, TweenService:Create(o, FadeInfo, {
                        TextTransparency = 1,
                        BackgroundTransparency = 1
                    }))
                elseif o:IsA("ImageLabel") and o ~= Shadow then
                    table.insert(Tweens, TweenService:Create(o, FadeInfo, {
                        ImageTransparency = 1
                    }))
                elseif o:IsA("Frame") and o ~= Notification then
                    table.insert(Tweens, TweenService:Create(o, FadeInfo, {
                        BackgroundTransparency = 1
                    }))
                end
            end

            for _, Tween in ipairs(Tweens) do
                Tween:Play()
            end

            task.delay(0.35, function()
                if not Notification or not Notification.Parent then
                    return
                end
                TweenService:Create(Notification, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
                    {
                        Size = UDim2.new(1, 0, 0, 0)
                    }):Play()
                task.wait(0.15)
                if Notification and Notification.Parent then
                    Notification:Destroy()
                end
            end)

            return true
        end

        function EngProject.NotificationManager:DismissAll()
            local Holder = self:GetHolder()
            local ToRemove = {}
            for _, Child in ipairs(Holder:GetChildren()) do
                if Child:IsA("Frame") then
                    table.insert(ToRemove, Child)
                end
            end
            for _, Child in ipairs(ToRemove) do
                self:Dismiss(Child)
            end
        end
    end

    EngProject.MarkdownParser = {}
    do
        function EngProject.MarkdownParser:ConvertToRichText(Markdown)
            local Text = Markdown
            Text = Text:gsub("### (.-)\n", '<font size="18"><b>%1</b></font>\n')
            Text = Text:gsub("## (.-)\n", '<font size="20"><b>%1</b></font>\n')
            Text = Text:gsub("# (.-)\n", '<font size="22"><b>%1</b></font>\n')
            Text = Text:gsub("%*%*%*(.-)%*%*%*", "<b><i>%1</i></b>")
            Text = Text:gsub("%*%*(.-)%*%*", "<b>%1</b>")
            Text = Text:gsub("%*(.-)%*", "<i>%1</i>")
            Text = Text:gsub("__(.-)__", "<b>%1</b>")
            Text = Text:gsub("_(.-)_", "<i>%1</i>")
            Text = Text:gsub("~~(.-)~~", "<s>%1</s>")
            Text = Text:gsub("`([^`]+)`",
                '<font face="RobotoMono"><stroke color="rgb(50,50,60)" joins="miter" thickness="3" transparency="0">%1</stroke></font>')
            Text = Text:gsub("```(.-)```", function(Code)
                return
                    '<font face="RobotoMono" size="13"><stroke color="rgb(50,50,60)" joins="miter" thickness="3" transparency="0">' ..
                        Code .. '</stroke></font>'
            end)
            Text = Text:gsub("%[(.-)%]%((.-)%)", '<font color="rgb(100,150,255)"><u>%1</u></font>')
            Text = Text:gsub("^%- (.-)\n", "• %1\n")
            Text = Text:gsub("\n%- (.-)\n", "\n• %1\n")
            Text = Text:gsub("\n%- (.-)", "\n• %1")
            Text = Text:gsub("^%* (.-)\n", "• %1\n")
            Text = Text:gsub("\n%* (.-)\n", "\n• %1\n")
            Text = Text:gsub("\n%* (.-)", "\n• %1")
            Text = Text:gsub("^%d+%. (.-)\n", "%1\n")
            Text = Text:gsub("\n%d+%. (.-)\n", "\n%1\n")
            Text = Text:gsub("%-%-%-+", "────────────────────────")
            Text = Text:gsub("%*%*%*+", "────────────────────────")
            return Text
        end
    end
end

function EngProject:CreateWindow(options)
    options = options or {}

    local theme = type(options.Theme) == "string" and (self.Themes[options.Theme] or self.Themes.DefaultTheme) or
                      type(options.Theme) == "table" and options.Theme or self.Themes.DefaultTheme

    local scale = math.clamp(options.DefaultScale or self.Constants.Window.DefaultScale, self.Constants.Window.MinScale,
        self.Constants.Window.MaxScale)

    local screenGui = self.Utility:CreateInstance("ScreenGui", {
        Name = options.Name or self.Utility:GenerateId(),
        ResetOnSpawn = false,
        DisplayOrder = options.DisplayOrder or 1,
        IgnoreGuiInset = options.IgnoreGuiInset or false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    })
    self.Utility:ParentUI(screenGui)

    local mainFrame, uiScale, mainFrameBindings = self.WindowBuilder:CreateMainFrame(screenGui, options, theme)
    local topBarHeight = options.TopBarHeight or self.Constants.Window.TopBarHeight
    local footerHeight = options.Footer and (options.FooterHeight or 10) or 0

    local topBar, topBarSeparator, topBarSeparatorBindings = self.WindowBuilder:CreateTopBar(mainFrame, options, theme)

    local tabInfoContainer, controlsContainer, tabNameLabel, tabDescLabel, brandIconElement, brandInitialElement,
        brandTitleLabel = self.WindowBuilder:CreateTitleSection(topBar, options, theme)

    local controlButtons = self.WindowBuilder:CreateWindowControls(controlsContainer, options, theme)

    local footer, footerBindings, footerContent, separatorBindings, resizeContainer =
        self.WindowBuilder:CreateFooter(mainFrame, options, theme)
    local ResizeMode = options.ResizeMode or self.Constants.Window.ResizeModes.BottomRight

    local mainContainer = self.WindowBuilder:CreateMainContainer(mainFrame, options, theme, topBarHeight, footerHeight)

    local tabsContainer, contentsContainer, tabsSeparator, tabsSeparatorBindings =
        self.WindowBuilder:CreateContentAreas(mainContainer, mainFrame, topBar, options)

    local window = {
        _connections = EngProject.ConnectionRegistry:New(),
        Theme = theme,
        TabMode = options.TabMode or self.Constants.Window.TabModes.Fixed,
        TabsExpanded = true,
        ActiveTab = nil,
        ActivePage = nil,
        TabCallbacks = {},
        Scale = uiScale,
        Elements = {
            ScreenGui = screenGui,
            MainFrame = mainFrame,
            TopBar = topBar,
            TabInfoContainer = tabInfoContainer,
            TitleLabel = tabNameLabel,
            SubtitleLabel = tabDescLabel,
            BrandIcon = brandIconElement,
            BrandInitial = brandInitialElement,
            BrandTitle = brandTitleLabel,
            ControlsContainer = controlsContainer,
            ControlButtons = controlButtons,
            Footer = footer,
            FooterContent = footerContent,
            FooterResizeArea = resizeContainer,
            MainContainer = mainContainer,
            TabsContainer = tabsContainer,
            TabsSeparator = tabsSeparator,
            ContentsContainer = contentsContainer,
            Tabs = {},
            Pages = {}
        },

        GetScale = function()
            return uiScale.Scale
        end,

        SetScale = function(self, value, animate)
            value = math.clamp(tonumber(value) or 1, EngProject.Constants.Window.MinScale,
                EngProject.Constants.Window.MaxScale)

            if animate then
                TweenService:Create(uiScale, TweenInfo.new(EngProject.Constants.Animation.Normal, Enum.EasingStyle.Sine,
                    Enum.EasingDirection.Out), {
                    Scale = value
                }):Play()
            else
                uiScale.Scale = value
            end
        end,

        SetTheme = function(self, themeName, animate)
            if type(themeName) ~= "string" then
                return
            end
            EngProject.ThemeManager:SetTheme(self, themeName, animate ~= false)
        end,

        GetTheme = function(self)
            return EngProject.ThemeManager:GetThemeName(self)
        end,

        SetTabMode = function(self, mode, animate, threshold)
            threshold = threshold or EngProject.Constants.Window.TabDynamicThreshold
            local modes = EngProject.Constants.Window.TabModes

            if not modes[mode] then
                EngProject.ErrorHandler:Guard(false, "SetTabMode",
                    string.format("Invalid tab mode '%s', using Dynamic", tostring(mode)),
                    EngProject.ErrorHandler.Levels.WARN)
                mode = modes.Dynamic
            end

            self.TabMode = mode
            local duration = EngProject.Constants.Animation.Smooth
            local const = EngProject.Constants.Window

            local function updateTopBarLayout(expanded, tweenDuration)
                if not tabsSeparator then
                    return
                end

                local hasBrand = options.Brand ~= nil
                local xScale, xOffset

                if expanded then
                    xScale = const.TabsWidthOpen
                    xOffset = const.TabSeparatorGap
                    if tabNameLabel then
                        TweenService:Create(tabNameLabel, TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad), {
                            TextTransparency = 1
                        }):Play()
                    end
                    if tabDescLabel then
                        TweenService:Create(tabDescLabel, TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad), {
                            TextTransparency = 1
                        }):Play()
                    end
                    TweenService:Create(tabsSeparator,
                        TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                            Size = UDim2.new(0, 1, 1, -topBarHeight),
                            Position = UDim2.new(xScale, xOffset, 0, topBarHeight)
                        }):Play()

                    if brandTitleLabel then
                        TweenService:Create(brandTitleLabel, TweenInfo.new(tweenDuration * 0.8, Enum.EasingStyle.Quad,
                            Enum.EasingDirection.Out), {
                            TextTransparency = 0
                        }):Play()
                    end

                    if tabInfoContainer then
                        TweenService:Create(tabInfoContainer, TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad,
                            Enum.EasingDirection.Out), {
                            Position = UDim2.new(xScale, xOffset + 1, 0.5, 0)
                        }):Play()
                    end
                else
                    xOffset = const.TabsWidthClosed + const.ClosedTabHorizontalPadding + const.TabSeparatorGap

                    if tabNameLabel then
                        TweenService:Create(tabNameLabel, TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad), {
                            TextTransparency = 0
                        }):Play()
                    end
                    if tabDescLabel then
                        TweenService:Create(tabDescLabel, TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad), {
                            TextTransparency = 0
                        }):Play()
                    end

                    TweenService:Create(tabsSeparator,
                        TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                            Size = UDim2.new(0, 1, 1, hasBrand and 0 or -topBarHeight),
                            Position = UDim2.new(0, xOffset, 0, hasBrand and 0 or topBarHeight)
                        }):Play()

                    if brandTitleLabel then
                        TweenService:Create(brandTitleLabel, TweenInfo.new(tweenDuration * 0.5, Enum.EasingStyle.Quad,
                            Enum.EasingDirection.In), {
                            TextTransparency = 1
                        }):Play()
                    end

                    if tabInfoContainer then
                        TweenService:Create(tabInfoContainer, TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad,
                            Enum.EasingDirection.Out), {
                            Position = UDim2.new(0, xOffset + 1, 0.5, 0)
                        }):Play()
                    end
                end
            end

            local function setExpanded(expanded, tweenDuration)
                self.TabsExpanded = expanded
                tweenDuration = tweenDuration and duration or 0

                updateTopBarLayout(expanded, tweenDuration)

                local hPad = const.HorizontalPadding
                local tabsSize, tabsPos, contentsPos, contentsSize

                if expanded then
                    tabsSize = UDim2.new(const.TabsWidthOpen, -(hPad * 0.5), 1, 0)
                    tabsPos = UDim2.new(0, hPad * 0.5, 0, 0)
                    contentsPos = UDim2.new(const.TabsWidthOpen, hPad, 0, 0)
                    contentsSize = UDim2.new(const.ContentWidthOpen, -(hPad * 2), 1, 0)
                else
                    local contentLeft = const.ContentLeftOffsetClosed
                    tabsSize = UDim2.new(0, const.TabsWidthClosed, 1, 0)
                    tabsPos = UDim2.new(0, const.ClosedTabHorizontalPadding, 0, 0)
                    contentsPos = UDim2.new(0, contentLeft, 0, 0)
                    contentsSize = UDim2.new(1, -(contentLeft + hPad), 1, 0)
                end

                TweenService:Create(tabsContainer,
                    TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                        Size = tabsSize,
                        Position = tabsPos
                    }):Play()

                TweenService:Create(contentsContainer,
                    TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                        Position = contentsPos,
                        Size = contentsSize
                    }):Play()

                for _, tabData in pairs(self.Elements.Tabs) do
                    if type(tabData) == "table" and tabData.Container then

                        local isActive = tabData.Container == self.ActiveTab

                        if not isActive then
                            local currentTheme = EngProject.ThemeManager:GetCurrentTheme(self)
                            local targetColor = expanded and currentTheme.Secondary or currentTheme.Secondary
                            local targetTransparency = expanded and (currentTheme.TransparencySecondary or 0.8) or 1

                            TweenService:Create(tabData.Container, TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad),
                                {
                                    BackgroundColor3 = targetColor,
                                    BackgroundTransparency = targetTransparency
                                }):Play()
                        end

                        TweenService:Create(tabData.Container, TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad), {
                            Size = UDim2.new(1, -8, 0, expanded and 32 or 44)
                        }):Play()

                        if tabData.Icon then
                            local iconSize = expanded and const.TabIconSizeExpanded or 24
                            TweenService:Create(tabData.Icon, TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad), {
                                Size = UDim2.new(0, iconSize, 0, iconSize)
                            }):Play()
                        end

                        if tabData.TextLabel then
                            if expanded then
                                tabData.TextLabel.Visible = true
                                TweenService:Create(tabData.TextLabel,
                                    TweenInfo.new(tweenDuration * 0.5, Enum.EasingStyle.Quad), {
                                        TextTransparency = 0
                                    }):Play()
                            else
                                TweenService:Create(tabData.TextLabel,
                                    TweenInfo.new(tweenDuration * 0.5, Enum.EasingStyle.Quad), {
                                        TextTransparency = 1
                                    }):Play()
                                task.delay(tweenDuration * 0.5, function()
                                    if not self.TabsExpanded then
                                        tabData.TextLabel.Visible = false
                                    end
                                end)
                            end
                        end

                        if tabData.ContentContainer then
                            TweenService:Create(tabData.ContentContainer,
                                TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad), expanded and {
                                    Position = UDim2.new(0, 0, 0, 0),
                                    AnchorPoint = Vector2.new(0, 0)
                                } or {
                                    Position = UDim2.new(0.5, 0, 0.5, 0),
                                    AnchorPoint = Vector2.new(0.5, 0.5)
                                }):Play()
                        end

                        if tabData.AccentLine then
                            local isActive = tabData.Container == self.ActiveTab
                            if isActive then
                                TweenService:Create(tabData.AccentLine,
                                    TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad), {
                                        BackgroundTransparency = expanded and 1 or 0
                                    }):Play()
                            end
                        end
                    end
                end

                task.delay(tweenDuration, function()
                    for _, tabData in pairs(self.Elements.Tabs) do
                        if type(tabData) == "table" and tabData.RefreshVisuals then
                            tabData.RefreshVisuals()
                        end
                    end
                end)
            end

            if mode == modes.Fixed then
                setExpanded(true, animate)
            elseif mode == modes.Closed then
                setExpanded(false, animate)
            elseif mode == modes.Dynamic then
                setExpanded(false, animate)
                local mouseInside = false
                local expandConnection = nil

                local function scheduleExpand()
                    if expandConnection then
                        expandConnection:Disconnect()
                    end
                    expandConnection = task.spawn(function()
                        task.wait(threshold)
                        if mouseInside and self.TabMode == modes.Dynamic then
                            setExpanded(true, true)
                        end
                        expandConnection = nil
                    end)
                end

                tabsContainer.MouseEnter:Connect(function()
                    if self.TabMode ~= modes.Dynamic then
                        return
                    end
                    mouseInside = true
                    scheduleExpand()
                end)

                tabsContainer.MouseLeave:Connect(function()
                    mouseInside = false
                    if expandConnection then
                        task.cancel(expandConnection)
                        expandConnection = nil
                    end
                    if self.TabMode == modes.Dynamic then
                        setExpanded(false, true)
                    end
                end)
            end
        end,

        AddFooterText = function(self, config)
            if not footer or not footerContent then
                return nil
            end
            config = config or {}

            local currentTheme = EngProject.ThemeManager:GetCurrentTheme(self)
            local properties, bindings = EngProject.Utility:ApplyTheme({
                Name = config.Name or "FooterText",
                LayoutOrder = config.Order or 1,
                Size = UDim2.new(0, 0, 1, 0),
                AutomaticSize = Enum.AutomaticSize.X,
                BackgroundTransparency = 1,
                Text = config.Text or "",
                TextSize = config.TextSize or 14,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = footer.ZIndex + 2
            }, {
                Font = "FontSecondary",
                TextColor3 = config.ColorTier or "TextSecondary"
            }, currentTheme)

            local label = EngProject.Utility:CreateInstance("TextLabel", properties, footerContent)
            if bindings then
                EngProject.ThemeManager:RegisterElement(self, label, bindings)
            end
            return label
        end,

        SetFooterText = function(self, element, newText)
            if element and element:IsA("TextLabel") then
                element.Text = tostring(newText)
            end
        end,

        AddFooterButton = function(self, config)
            if not footer or not footerContent then
                return nil
            end
            config = config or {}

            local currentTheme = EngProject.ThemeManager:GetCurrentTheme(self)
            local buttonText = config.Text or "Button"
            local callback = config.Callback or function()
            end

            local properties, bindings = EngProject.Utility:ApplyTheme({
                Name = config.Name or buttonText,
                LayoutOrder = config.Order or 1,
                Size = UDim2.new(0, config.Width or 80, 1, -8),
                Text = buttonText,
                TextSize = config.TextSize or 14,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                ZIndex = footer.ZIndex + 2
            }, {
                Font = "FontSecondary",
                TextColor3 = "TextPrimary",
                BackgroundColor3 = "Tertiary"
            }, currentTheme)

            local button = EngProject.Utility:CreateInstance("TextButton", properties, footerContent)
            EngProject.Utility:CreateInstance("UICorner", {
                CornerRadius = UDim.new(0, EngProject.Constants.Corner.Medium)
            }, button)

            if not EngProject.Utility:IsMobile() then
                button.MouseEnter:Connect(function()
                    TweenService:Create(button, TweenInfo.new(0.15), {
                        BackgroundColor3 = currentTheme.TertiaryHover
                    }):Play()
                end)
                button.MouseLeave:Connect(function()
                    TweenService:Create(button, TweenInfo.new(0.15), {
                        BackgroundColor3 = currentTheme.Tertiary
                    }):Play()
                end)
            end

            button.Activated:Connect(function()
                TweenService:Create(button, TweenInfo.new(0.1), {
                    BackgroundColor3 = currentTheme.TertiaryPressed
                }):Play()
                task.wait(0.1)
                TweenService:Create(button, TweenInfo.new(0.1), {
                    BackgroundColor3 = currentTheme.Tertiary
                }):Play()
                EngProject.ErrorHandler:Try(function()
                    EngProject.Security:SafeCallback(callback())
                end)
            end)

            if bindings then
                EngProject.ThemeManager:RegisterElement(self, button, bindings)
            end
            return button
        end,

        ClearFooter = function(self)
            if footerContent then
                for _, child in ipairs(footerContent:GetChildren()) do
                    if not child:IsA("UIListLayout") then
                        child:Destroy()
                    end
                end
            end
        end,

        SetFooterAlignment = function(self, alignment)
            if footerContent then
                local layout = footerContent:FindFirstChildOfClass("UIListLayout")
                if layout then
                    layout.HorizontalAlignment = alignment
                end
            end
        end,

        Hide = function(self)
            mainFrame.Visible = false
        end,

        Show = function(self)
            mainFrame.Visible = true
        end,

        Toggle = function(self)
            mainFrame.Visible = not mainFrame.Visible
        end,

        Destroy = function(self)
            self._connections:Cleanup()
            EngProject.Windows[screenGui] = nil
            screenGui:Destroy()
        end,

        IsVisible = function(self)
            return mainFrame.Visible
        end,

        SetOpacity = function(self, value, animate)
            value = math.clamp(tonumber(value) or 1, 0, 1)
            local tweenDuration = animate and EngProject.Constants.Animation.Normal or 0

            for _, element in ipairs({topBar, mainContainer, footer}) do
                if element then
                    local originalTransparency = element:GetAttribute("OriginalTransparency")
                    if not originalTransparency then
                        originalTransparency = element.BackgroundTransparency
                        element:SetAttribute("OriginalTransparency", originalTransparency)
                    end

                    local newTransparency = 1 - ((1 - originalTransparency) * value)

                    if animate then
                        TweenService:Create(element, TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad), {
                            BackgroundTransparency = newTransparency
                        }):Play()
                    else
                        element.BackgroundTransparency = newTransparency
                    end
                end
            end
        end,

        EnableBlur = function(self, intensity)
            pcall(function()
                intensity = math.clamp(tonumber(intensity) or 24, 0, 56)
                local existing = Lighting:FindFirstChild("Eng ProjectBlur")
                if existing then
                    existing.Size = intensity
                else
                    local blur = Instance.new("BlurEffect")
                    blur.Name = "Eng ProjectBlur"
                    blur.Size = intensity
                    blur.Parent = Lighting
                end
            end)
        end,

        DisableBlur = function(self)
            pcall(function()
                local existing = Lighting:FindFirstChild("Eng ProjectBlur")
                if existing then
                    existing:Destroy()
                end
            end)
        end
    }

    self.Windows[screenGui] = window
    self.ThemeManager:Initialize(window)

    if mainFrameBindings then
        self.ThemeManager:RegisterElement(window, mainFrame, mainFrameBindings)
    end
    if footer and footerBindings then
        self.ThemeManager:RegisterElement(window, footer, footerBindings)
    end
    if separatorBindings and separatorBindings.Element then
        self.ThemeManager:RegisterElement(window, separatorBindings.Element, separatorBindings.Bindings)
    end
    if topBarSeparatorBindings then
        self.ThemeManager:RegisterElement(window, topBarSeparator, topBarSeparatorBindings)
    end
    if tabsSeparatorBindings then
        self.ThemeManager:RegisterElement(window, tabsSeparator, tabsSeparatorBindings)
    end

    if tabNameLabel then
        self.ThemeManager:RegisterElement(window, tabNameLabel, {
            TextColor3 = "TextPrimary",
            Font = "FontPrimary"
        })
    end

    if tabDescLabel then
        self.ThemeManager:RegisterElement(window, tabDescLabel, {
            TextColor3 = "TextSecondary",
            Font = "FontSecondary"
        })
    end

    if brandTitleLabel then
        self.ThemeManager:RegisterElement(window, brandTitleLabel, {
            TextColor3 = "TextPrimary",
            Font = "FontPrimary"
        })
    end

    if brandInitialElement then
        self.ThemeManager:RegisterElement(window, brandInitialElement, {
            TextColor3 = "TextPrimary"
        })
    end

    self.WindowControlBuilder:RegisterIconBindings(window, controlButtons, options)

    self.WindowBuilder:SetupDragging(topBar, mainFrame)

    local resizeHandle, resizeIcon, resizeBindings = self.WindowBuilder:SetupResizing(mainFrame, uiScale, options,
        window.Elements.FooterResizeArea, ResizeMode, theme)

    self.WindowBuilder:SetupScrollUpdates(window)

    if resizeBindings then
        self.ThemeManager:RegisterMultiple(window, resizeBindings)
    end

    for _, methodName in ipairs({"Destroy", "SetTheme", "SetScale", "Hide", "Show", "Toggle", "IsVisible", "SetTitle",
                                 "SetSubtitle", "AddFooterButton", "ClearFooter", "SetFooterAlignment", "SetOpacity",
                                 "EnableBlur", "DisableBlur", "SetTabMode", "PopulateFooter"}) do
        if window[methodName] then
            window[methodName] = self.Security:WrapFunction(window[methodName])
        end
    end

    if footer and options.FooterItems then
        self.WindowBuilder:PopulateFooter(window, options, theme)
    end

    if options.StartHidden then
        mainFrame.Visible = false
    end

    if options.TabMode then
        window:SetTabMode(options.TabMode, true, options.TabDynamicThreshold)
    end

    if options.InitialOpacity then
        window:SetOpacity(options.InitialOpacity, false)
    end

    return window
end

function EngProject:CreateTab(Window, Name, Options)
    if not Window or not Window.Elements or not Window.Elements.TabsContainer then
        return
    end
    Options = Options or {}
    local Theme = self.ThemeManager:GetCurrentTheme(Window)
    local IsMobile = self.Utility:IsMobile()

    if not Window.TabActivationLock then
        Window.TabActivationLock = false
    end

    local Tab = self.Utility:CreateInstance("TextButton", {
        Name = Name,
        Size = UDim2.new(1, -8, 0, Window.TabsExpanded and 32 or 44),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = self.Constants.ZIndex.Content,
        LayoutOrder = #Window.Elements.Tabs
    }, Window.Elements.TabsContainer)
    self.Utility:CreateInstance("UICorner", {
        CornerRadius = UDim.new(0, self.Constants.Corner.Medium)
    }, Tab)

    local AccentLine = self.Utility:CreateInstance("Frame", {
        Name = "AccentLine",
        Size = UDim2.new(0, 2, 0, 24),
        Position = UDim2.new(0, -4, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = Theme.TabAccent or Theme.Accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = self.Constants.ZIndex.Control + 2
    }, Tab)
    self.Utility:CreateInstance("UICorner", {
        CornerRadius = UDim.new(1, 0)
    }, AccentLine)

    local ContentContainer = self.Utility:CreateInstance("Frame", {
        Name = "ContentContainer",
        Size = UDim2.new(1, 0, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        AnchorPoint = Vector2.new(0, 0),
        BackgroundTransparency = 1,
        ZIndex = self.Constants.ZIndex.Content + 1
    }, Tab)
    self.Utility:CreateInstance("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8)
    }, ContentContainer)
    self.Utility:CreateInstance("UIPadding", {
        PaddingLeft = UDim.new(0, self.Constants.Padding.Large),
        PaddingRight = UDim.new(0, self.Constants.Padding.Large)
    }, ContentContainer)

    local Icon = nil
    local IconSize = 0

    if Options.Icon and type(Options.Icon) == "table" and Options.Icon.Image then
        IconSize = Window.TabsExpanded and self.Constants.Window.TabIconSizeExpanded or 24
        local IconData = self.IconManager:WrapIcon(Options.Icon)

        Icon = self.Utility:CreateInstance("ImageLabel", {
            Name = "TabIcon",
            Image = IconData.Url,
            ImageColor3 = Theme.TextInactive,
            Size = UDim2.new(0, IconSize, 0, IconSize),
            ImageTransparency = 0,
            ImageRectOffset = IconData.ImageRectOffset,
            ImageRectSize = IconData.ImageRectSize,
            BackgroundTransparency = 1,
            LayoutOrder = 1,
            ZIndex = self.Constants.ZIndex.Control
        }, ContentContainer)
    end

    local TextLabel = self.Utility:CreateInstance("TextLabel", {
        Name = "TabText",
        Text = Name,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -(IconSize > 0 and (IconSize + 8) or 0), 1, 0),
        AutomaticSize = Enum.AutomaticSize.None,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Font = Theme.FontSecondary,
        TextColor3 = Theme.TextInactive,
        LayoutOrder = 2,
        ZIndex = self.Constants.ZIndex.Control
    }, ContentContainer)

    local Page = self:CreatePage(Window, Name, Options)

    local TabState = {
        IsHovering = false
    }

    local function UpdateActiveBrandDisplay(TabName, TabOptions)
        local TabNameLabel = Window.Elements.TitleLabel
        local TabDescLabel = Window.Elements.SubtitleLabel

        if TabNameLabel then
            TabNameLabel.Text = TabName
        end
        if TabDescLabel then
            TabDescLabel.Text = TabOptions.Description or ""
        end
    end

    local function RefreshTabVisuals()
        local CurrentTheme = self.ThemeManager:GetCurrentTheme(Window)
        local IsCollapsed = not Window.TabsExpanded
        local IsActive = Window.ActiveTab == Tab

        if IsActive then
            Tab.BackgroundColor3 = CurrentTheme.SecondaryActive
            Tab.BackgroundTransparency = 0
            TextLabel.TextColor3 = CurrentTheme.TextActive
            if Icon then
                Icon.ImageColor3 = CurrentTheme.TabIconActive or CurrentTheme.TextActive
            end
            if IsCollapsed then
                AccentLine.BackgroundTransparency = 0
            else
                AccentLine.BackgroundTransparency = 1
            end
            UpdateActiveBrandDisplay(Name, Options)
        elseif TabState.IsHovering then
            Tab.BackgroundColor3 = CurrentTheme.Secondary
            Tab.BackgroundTransparency = 0
            TextLabel.TextColor3 = CurrentTheme.TextPrimary
            if Icon then
                Icon.ImageColor3 = CurrentTheme.TabIconHover or CurrentTheme.TextPrimary
            end
            AccentLine.BackgroundTransparency = 1
        else
            if IsCollapsed then
                Tab.BackgroundColor3 = CurrentTheme.Secondary
                Tab.BackgroundTransparency = 1
            else
                Tab.BackgroundColor3 = CurrentTheme.Secondary
                Tab.BackgroundTransparency = CurrentTheme.TransparencySecondary or 0.8
            end
            TextLabel.TextColor3 = CurrentTheme.TextInactive
            if Icon then
                Icon.ImageColor3 = CurrentTheme.TabIconInactive or CurrentTheme.TextInactive
            end
            AccentLine.BackgroundTransparency = 1
        end
    end

    if not IsMobile then
        Tab.MouseEnter:Connect(function()
            if Window.ActiveTab ~= Tab then
                TabState.IsHovering = true
                RefreshTabVisuals()
            end
        end)
        Tab.MouseLeave:Connect(function()
            TabState.IsHovering = false
            RefreshTabVisuals()
        end)
    end

    Tab.Activated:Connect(function()
        if Window.TabActivationLock then
            return
        end
        if Window.ActiveTab == Tab then
            return
        end

        Window.TabActivationLock = true

        if Window.ActivePage then
            local pageToHide = Window.ActivePage
            if type(pageToHide) == "table" and pageToHide.Container then
                pageToHide = pageToHide.Container
            end
            pageToHide.Visible = false
        end

        Window.ActiveTab = Tab

        local CurrentPage = Window.Elements.ContentsContainer:FindFirstChild(Name .. "Page")
        if CurrentPage then
            Page = CurrentPage
            if type(Page) == "table" and Page._isDualScroll then
                Page.Left = self.ScrollManager:Update(Page.Left)
                Page.Right = self.ScrollManager:Update(Page.Right)
            else
                Page = self.ScrollManager:Update(Page)
            end
            Window.Elements.Pages[Name] = Page
        end
        Window.ActivePage = Page
        local pageToShow = Window.ActivePage
        if type(pageToShow) == "table" and pageToShow.Container then
            pageToShow = pageToShow.Container
        end
        pageToShow.Visible = true

        for TabName, TabData in pairs(Window.Elements.Tabs) do
            TabData.State.IsHovering = false
            TabData.RefreshVisuals()
        end

        task.delay(0.15, function()
            Window.TabActivationLock = false
        end)
    end)

    Window.Elements.Tabs[Name] = {
        Container = Tab,
        Icon = Icon,
        ContentContainer = ContentContainer,
        TextLabel = TextLabel,
        AccentLine = AccentLine,
        Page = Page,
        RefreshVisuals = RefreshTabVisuals,
        State = TabState
    }

    local ThemeBindings = {
        [AccentLine] = {
            BackgroundColor3 = function(Element, CurrentTheme)
                Element.BackgroundColor3 = CurrentTheme.TabAccent or CurrentTheme.Accent
            end
        },
        [TextLabel] = {
            Font = "FontSecondary"
        },
        [Tab] = {
            BackgroundColor3 = function(Element, CurrentTheme)
                RefreshTabVisuals()
            end,
            BackgroundTransparency = function(Element, CurrentTheme)
                RefreshTabVisuals()
            end
        }
    }

    if Icon then
        ThemeBindings[Icon] = {
            ImageColor3 = function(Element, CurrentTheme)
                RefreshTabVisuals()
            end
        }
    end

    if Window then
        self.ThemeManager:RegisterMultiple(Window, ThemeBindings)
    end

    if not Window.ActiveTab then
        Window.ActiveTab = Tab
        Window.ActivePage = Page
        local pageToShow = Window.ActivePage
        if type(pageToShow) == "table" and pageToShow.Container then
            pageToShow = pageToShow.Container
        end
        pageToShow.Visible = true
    else
        Page.Visible = false
    end

    RefreshTabVisuals()

    return {
        Tab = Tab,
        Page = Page,
        Icon = Icon,
        AccentLine = AccentLine
    }
end

function EngProject:CreatePage(Window, Name, Options)
    if not Window or not Window.Elements or not Window.Elements.ContentsContainer then
        return
    end
    Options = Options or {}
    local IsDualScroll = Options.DualScroll or false

    if not IsDualScroll then
        local Page = self.Utility:CreateInstance("Frame", {
            Name = Name .. "Page",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = self.Constants.ZIndex.Content,
            ClipsDescendants = false
        }, Window.Elements.ContentsContainer)
        self.Utility:CreateInstance("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, self.Constants.Spacing.Loose)
        }, Page)
        self.Utility:CreateInstance("UIPadding", {
            PaddingTop = UDim.new(0, 2),
            PaddingBottom = UDim.new(0, 0),
            PaddingLeft = UDim.new(0, 2),
            PaddingRight = UDim.new(0, 2)
        }, Page)
        Window.Elements.Pages[Name] = Page
        task.defer(function()
            if Window.ActivePage then
                local pageToUpdate = Window.ActivePage
                if type(pageToUpdate) == "table" and pageToUpdate.Container then
                    pageToUpdate = pageToUpdate.Container
                end
                Window.ActivePage = self.ScrollManager:Update(pageToUpdate)
            end
        end)
        return Page
    else
        local PageContainer = self.Utility:CreateInstance("Frame", {
            Name = Name .. "Page",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = self.Constants.ZIndex.Content,
            ClipsDescendants = false
        }, Window.Elements.ContentsContainer)

        self.Utility:CreateInstance("UIPadding", {
            PaddingTop = UDim.new(0, 2),
            PaddingBottom = UDim.new(0, 0),
            PaddingLeft = UDim.new(0, 2),
            PaddingRight = UDim.new(0, 2)
        }, PageContainer)

        self.Utility:CreateInstance("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 8)
        }, PageContainer)

        local LeftPage = self.Utility:CreateInstance("Frame", {
            Name = Name .. "PageLeft",
            Size = UDim2.new(0.5, -4, 1, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = self.Constants.ZIndex.Content,
            ClipsDescendants = false,
            LayoutOrder = 1
        }, PageContainer)

        self.Utility:CreateInstance("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, self.Constants.Spacing.Loose)
        }, LeftPage)

        self.Utility:CreateInstance("UIPadding", {
            PaddingTop = UDim.new(0, 2),
            PaddingBottom = UDim.new(0, 2),
            PaddingLeft = UDim.new(0, 2),
            PaddingRight = UDim.new(0, 2)
        }, LeftPage)
        local RightPage = self.Utility:CreateInstance("Frame", {
            Name = Name .. "PageRight",
            Size = UDim2.new(0.5, -4, 1, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = self.Constants.ZIndex.Content,
            ClipsDescendants = false,
            LayoutOrder = 2
        }, PageContainer)

        self.Utility:CreateInstance("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, self.Constants.Spacing.Loose)
        }, RightPage)

        self.Utility:CreateInstance("UIPadding", {
            PaddingTop = UDim.new(0, 2),
            PaddingBottom = UDim.new(0, 2),
            PaddingLeft = UDim.new(0, 2),
            PaddingRight = UDim.new(0, 2)
        }, RightPage)
        local PageWrapper = {
            Container = PageContainer,
            Left = LeftPage,
            Right = RightPage,
            _isDualScroll = true
        }

        Window.Elements.Pages[Name] = PageWrapper

        task.defer(function()
            PageWrapper.Left = self.ScrollManager:Update(PageWrapper.Left)
            PageWrapper.Right = self.ScrollManager:Update(PageWrapper.Right)
        end)

        return PageWrapper
    end
end

function EngProject:CreateSection(Page, Text, Options)
    if not Page then
        return
    end
    Options = Options or {}
    local Theme = self.ThemeManager:GetCurrentTheme(self.Utility:GetWindowFromElement(Page))
    local Window = self.Utility:GetWindowFromElement(Page)
    local Style = Options.Style or "solid"

    if Style == "box" then
        return self.SectionManager:CreateBoxSection(Page, Text, Options, Theme, Window)
    else
        return self.SectionManager:CreateSimpleSection(Page, Text, Options, Theme, Window, Style)
    end
end

function EngProject:CreateButton(Page, Text, Callback, Options)
    local EH = self.ErrorHandler
    if not EH:ValidateInstance(Page, "GuiObject", "CreateButton") then
        return nil
    end
    if not EH:ValidateType(Text, "string", "Text", "CreateButton") then
        Text = "Button"
    end
    if Callback then
        Callback = (EH:ValidateType(Callback, "function", "Callback", "CreateButton") == false) and nil or Callback
    end
    Options = Options or {}
    local Theme = self.ThemeManager:GetCurrentTheme(self.Utility:GetWindowFromElement(Page))
    local IsMobile = self.Utility:IsMobile()
    local Window = self.Utility:GetWindowFromElement(Page)
    local HasDescription = Options.Description and Options.Description ~= ""

    local Zones = self.ComponentBuilder:CreateContainer({
        Parent = Page,
        Layout = "TextLeft",
        TextWidth = 0.85,
        MinHeight = 35,
        Padding = HasDescription and {
            Top = self.Constants.Padding.Large,
            Bottom = self.Constants.Padding.Large,
            Left = self.Constants.Padding.Large,
            Right = self.Constants.Padding.Small
        } or {
            Top = 2,
            Bottom = 2,
            Left = self.Constants.Padding.Large,
            Right = self.Constants.Padding.Small
        },
        Spacing = HasDescription and self.Constants.Spacing.Tight or 0,
        HasDescription = HasDescription,
        CornerRadius = self.Constants.Corner.Medium,
        ColorTier = "Secondary"
    }, Theme)

    local Title = self.ComponentBuilder:CreateLabel(Zones.TextZone, Text, Theme, {
        ColorTier = "TextPrimary",
        Size = 15,
        Order = 1
    })

    local Description = HasDescription and
                            self.ComponentBuilder:CreateDescription(Zones.TextZone, Options.Description, Theme, 2) or
                            nil

    local ArrowContainer = self.Utility:CreateInstance("Frame", {
        Size = UDim2.new(0.15, -self.Constants.Padding.Large, 1, 0),
        Position = UDim2.new(0.85, 0, 0, 0),
        BackgroundTransparency = 1,
        ZIndex = self.Constants.ZIndex.Overlay
    }, Zones.Container)

    local Arrow = self.Utility:CreateInstance("ImageLabel", {
        Size = UDim2.new(0, 16, 0, 16),
        Position = UDim2.new(1, -10, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundTransparency = 1,
        Image = "rbxassetid://113826256227095",
        ImageRectOffset = Vector2.new(448, 192),
        ImageRectSize = Vector2.new(64, 64),
        ImageColor3 = Theme.TextPrimary,
        ZIndex = self.Constants.ZIndex.Overlay
    }, ArrowContainer)

    local ThemeBindings = {
        [Zones.Container] = {
            BackgroundColor3 = "Secondary",
            BackgroundTransparency = "TransparencySecondary"
        },
        [Title] = {
            TextColor3 = "TextPrimary",
            Font = "FontSecondary"
        },
        [Arrow] = {
            ImageColor3 = "TextPrimary"
        }
    }
    if Description then
        ThemeBindings[Description] = {
            TextColor3 = "TextSecondary",
            Font = "FontSecondary"
        }
    end
    if Window then
        self.ThemeManager:RegisterMultiple(Window, ThemeBindings)
    end

    local State = "Base"
    local IsHeld = false

    local function UpdateButtonState(NewState)
        local CurrentTheme = Window and self.ThemeManager:GetCurrentTheme(Window) or Theme
        local ColorGoal = CurrentTheme.Secondary
        local ArrowOffset = 0

        if NewState == "Hover" then
            ColorGoal = CurrentTheme.SecondaryHover
            ArrowOffset = -2
        elseif NewState == "Pressed" then
            ColorGoal = CurrentTheme.SecondaryPressed
            ArrowOffset = 2
        end

        TweenService:Create(Zones.Container, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
            BackgroundColor3 = ColorGoal
        }):Play()

        TweenService:Create(Arrow, TweenInfo.new(0.15, Enum.EasingStyle.Back, NewState == "Pressed" and
            Enum.EasingDirection.In or Enum.EasingDirection.Out), {
            Position = UDim2.new(1, -10 + ArrowOffset, 0.5, 0)
        }):Play()
    end

    local InteractButton = self.Utility:CreateInstance("TextButton", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = self.Constants.ZIndex.Modal
    }, Zones.Container)

    if not IsMobile then
        InteractButton.MouseEnter:Connect(function()
            if not IsHeld then
                State = "Hover"
                UpdateButtonState(State)
            end
        end)
        InteractButton.MouseLeave:Connect(function()
            if IsHeld then
                IsHeld = false
            end
            State = "Base"
            UpdateButtonState(State)
        end)
        InteractButton.MouseButton1Down:Connect(function()
            IsHeld = true
            State = "Pressed"
            UpdateButtonState(State)
        end)
        InteractButton.MouseButton1Up:Connect(function()
            if IsHeld then
                IsHeld = false
                State = "Hover"
                UpdateButtonState(State)
                if Callback then
                    EH:Try(Callback)
                end
            end
        end)
    else
        InteractButton.Activated:Connect(function()
            State = "Pressed"
            UpdateButtonState(State)
            task.delay(0.15, function()
                State = "Base"
                UpdateButtonState(State)
            end)
            if Callback then
                EH:Try(Callback)
            end
        end)
    end

    return {
        SetTitle = function(self, NewText)
            if EH:ValidateType(NewText, "string", "NewText", "Button:SetTitle") then
                Title.Text = NewText
            end
        end,
        SetDescription = function(self, NewDescription)
            local HadDescription = Description ~= nil and Description.Visible
            local HasNewDescription = NewDescription and NewDescription ~= ""
            if Description and NewDescription then
                Description.Text = NewDescription
                Description.Visible = true
            elseif Description and not NewDescription then
                Description.Visible = false
            elseif not Description and NewDescription then
                Description = EngProject.ComponentBuilder:CreateDescription(Zones.TextZone, NewDescription, Theme, 2)
                if Window then
                    EngProject.ThemeManager:RegisterElement(Window, Description, {
                        TextColor3 = "TextSecondary",
                        Font = "FontSecondary"
                    })
                end
            end
            if HadDescription ~= HasNewDescription then
                EngProject.ComponentBuilder:UpdateDescriptionPadding(Zones, HasNewDescription)
            end
        end,
        SetCallback = function(self, NewCallback)
            if EH:ValidateType(NewCallback, "function", "NewCallback", "Button:SetCallback") then
                Callback = NewCallback
            end
        end,
        SetVisible = function(self, Visible)
            if EH:ValidateType(Visible, "boolean", "Visible", "Button:SetVisible") then
                Zones.Container.Visible = Visible
            end
        end,
        GetElements = function(self)
            return {
                Container = Zones.Container,
                Title = Title,
                Description = Description,
                Arrow = Arrow
            }
        end,
        GetState = function(self)
            return State
        end
    }
end

function EngProject:CreateToggle(Page, Text, DefaultValue, Callback, Options)
    local EH = self.ErrorHandler
    if not EH:ValidateInstance(Page, "GuiObject", "CreateToggle") then
        return nil
    end
    if not EH:ValidateType(Text, "string", "Text", "CreateToggle") then
        Text = "Toggle"
    end
    if DefaultValue ~= nil and not EH:ValidateType(DefaultValue, "boolean", "DefaultValue", "CreateToggle") then
        DefaultValue = false
    end
    if Callback then
        Callback = (EH:ValidateType(Callback, "function", "Callback", "CreateToggle") == false) and nil or Callback
    end
    Options = Options or {}
    local SaveBinding = self.SaveManager:GetBinding(Options, "Toggle", Text)
    if SaveBinding.Enabled and type(SaveBinding.Value) == "boolean" then
        DefaultValue = SaveBinding.Value
    end
    local Theme = self.ThemeManager:GetCurrentTheme(self.Utility:GetWindowFromElement(Page))
    local Window = self.Utility:GetWindowFromElement(Page)
    local HasDescription = Options.Description and Options.Description ~= ""

    local Zones = self.ComponentBuilder:CreateContainer({
        Parent = Page,
        Layout = "TextLeft",
        TextWidth = 0.75,
        MinHeight = 35,
        Padding = HasDescription and {
            Top = self.Constants.Padding.Large,
            Bottom = self.Constants.Padding.Large,
            Left = self.Constants.Padding.Large,
            Right = self.Constants.Padding.Small
        } or {
            Top = 2,
            Bottom = 2,
            Left = self.Constants.Padding.Large,
            Right = self.Constants.Padding.Small
        },
        Spacing = HasDescription and self.Constants.Spacing.Tight or 0,
        HasDescription = HasDescription,
        CornerRadius = self.Constants.Corner.Medium,
        ColorTier = "Secondary"
    }, Theme)

    local Label = self.ComponentBuilder:CreateLabel(Zones.TextZone, Text, Theme, {
        ColorTier = "TextPrimary",
        Size = 14,
        Order = 1
    })

    local Description = HasDescription and
                            self.ComponentBuilder:CreateDescription(Zones.TextZone, Options.Description, Theme, 2) or
                            nil

    local SwitchContainer = self.Utility:CreateInstance("Frame", {
        Size = UDim2.new(0.25, -self.Constants.Padding.Large, 1, 0),
        Position = UDim2.new(0.75, 0, 0, 0),
        BackgroundTransparency = 1,
        ZIndex = self.Constants.ZIndex.Overlay
    }, Zones.Container)

    local Switch = self.Utility:CreateInstance("TextButton", {
        Size = UDim2.new(0, 44, 0, 22),
        Position = UDim2.new(1, -10, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = Theme.SecondaryPressed,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = self.Constants.ZIndex.Overlay
    }, SwitchContainer)

    self.Utility:CreateInstance("UICorner", {
        CornerRadius = UDim.new(1, 0)
    }, Switch)

    local Indicator = self.Utility:CreateInstance("Frame", {
        Size = UDim2.new(0, 18, 0, 18),
        Position = UDim2.new(0, 2, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = Theme.TextInactive,
        BorderSizePixel = 0,
        ZIndex = self.Constants.ZIndex.Modal
    }, Switch)

    self.Utility:CreateInstance("UICorner", {
        CornerRadius = UDim.new(1, 0)
    }, Indicator)

    local State = DefaultValue or false

    local function UpdateToggle(Animate)
        local CurrentTheme = Window and self.ThemeManager:GetCurrentTheme(Window) or Theme
        local PositionGoal = State and UDim2.new(1, -20, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
        local ColorGoal = State and CurrentTheme.Accent or CurrentTheme.SecondaryPressed
        local IndicatorColorGoal = State and CurrentTheme.TextActive or CurrentTheme.TextInactive

        if Animate then
            TweenService:Create(Indicator, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Position = PositionGoal
            }):Play()
            TweenService:Create(Switch, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
                BackgroundColor3 = ColorGoal
            }):Play()
            TweenService:Create(Indicator, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
                BackgroundColor3 = IndicatorColorGoal
            }):Play()
        else
            Indicator.Position = PositionGoal
            Switch.BackgroundColor3 = ColorGoal
            Indicator.BackgroundColor3 = IndicatorColorGoal
        end
    end

    local ThemeBindings = {
        [Zones.Container] = {
            BackgroundColor3 = "Secondary",
            BackgroundTransparency = "TransparencySecondary"
        },
        [Label] = {
            TextColor3 = "TextPrimary",
            Font = "FontSecondary"
        },
        [Switch] = {
            BackgroundColor3 = function()
                UpdateToggle(false)
            end
        },
        [Indicator] = {
            BackgroundColor3 = function()
                UpdateToggle(false)
            end
        }
    }
    if Description then
        ThemeBindings[Description] = {
            TextColor3 = "TextSecondary",
            Font = "FontSecondary"
        }
    end
    if Window then
        self.ThemeManager:RegisterMultiple(Window, ThemeBindings)
    end

    UpdateToggle(false)

    if Callback and ((SaveBinding.HasValue and SaveBinding.ApplyCallback) or (not SaveBinding.HasValue and State)) then
        EH:Try(function()
            Callback(State)
        end)
    end

    Switch.Activated:Connect(function()
        State = not State
        UpdateToggle(true)
        EngProject.SaveManager:WriteBinding(SaveBinding, State)
        if Callback then
            EH:Try(function()
                Callback(State)
            end)
        end
    end)

    return {
        GetState = function(self)
            return State
        end,
        SetState = function(self, Value)
            if EH:ValidateType(Value, "boolean", "Value", "Toggle:SetState") then
                State = Value
                UpdateToggle(true)
                EngProject.SaveManager:WriteBinding(SaveBinding, State)
            end
        end,
        SetDescription = function(self, NewDescription)
            local HadDescription = Description ~= nil and Description.Visible
            local HasNewDescription = NewDescription and NewDescription ~= ""
            if Description and NewDescription then
                Description.Text = NewDescription
                Description.Visible = true
            elseif Description and not NewDescription then
                Description.Visible = false
            elseif not Description and NewDescription then
                Description = EngProject.ComponentBuilder:CreateDescription(Zones.TextZone, NewDescription, Theme, 2)
                if Window then
                    EngProject.ThemeManager:RegisterElement(Window, Description, {
                        TextColor3 = "TextSecondary",
                        Font = "FontSecondary"
                    })
                end
            end
            if HadDescription ~= HasNewDescription then
                EngProject.ComponentBuilder:UpdateDescriptionPadding(Zones, HasNewDescription)
            end
        end,
        GetElements = function(self)
            return {
                Container = Zones.Container,
                Label = Label,
                Description = Description,
                Switch = Switch,
                Indicator = Indicator
            }
        end
    }
end

function EngProject:CreateTextInput(Page, Text, DefaultValue, Callback, Options)
    local EH = self.ErrorHandler
    if not EH:ValidateInstance(Page, "GuiObject", "CreateTextInput") then
        return nil
    end
    if not EH:ValidateType(Text, "string", "Text", "CreateTextInput") then
        Text = "Input"
    end
    if DefaultValue and not EH:ValidateType(DefaultValue, "string", "DefaultValue", "CreateTextInput") then
        DefaultValue = ""
    end
    if Callback then
        Callback = (EH:ValidateType(Callback, "function", "Callback", "CreateTextInput") == false) and nil or Callback
    end

    Options = Options or {}
    local SaveBinding = self.SaveManager:GetBinding(Options, "TextInput", Text)
    if SaveBinding.Enabled and type(SaveBinding.Value) == "string" then
        DefaultValue = SaveBinding.Value
    end
    local InputType = Options.Type or "Text"
    local ValidTypes = {
        Text = true,
        Numbers = true,
        Decimals = true,
        Alphanumeric = true
    }
    if not ValidTypes[InputType] then
        InputType = "Text"
    end

    local Theme = self.ThemeManager:GetCurrentTheme(self.Utility:GetWindowFromElement(Page))
    local IsMobile = self.Utility:IsMobile()
    local Window = self.Utility:GetWindowFromElement(Page)
    local HasDescription = Options.Description and Options.Description ~= ""

    local Zones = self.ComponentBuilder:CreateContainer({
        Parent = Page,
        Layout = "TextLeft",
        TextWidth = 0.55,
        MinHeight = 35,
        Padding = HasDescription and {
            Top = self.Constants.Padding.Large,
            Bottom = self.Constants.Padding.Large,
            Left = self.Constants.Padding.Large,
            Right = self.Constants.Padding.Small
        } or {
            Top = 2,
            Bottom = 2,
            Left = self.Constants.Padding.Large,
            Right = self.Constants.Padding.Small
        },
        Spacing = HasDescription and self.Constants.Spacing.Tight or 0,
        HasDescription = HasDescription,
        CornerRadius = self.Constants.Corner.Medium,
        ColorTier = "Secondary"
    }, Theme)

    local Label = self.ComponentBuilder:CreateLabel(Zones.TextZone, Text, Theme, {
        ColorTier = "TextPrimary",
        Size = 14,
        Order = 1
    })

    local Description = HasDescription and
                            self.ComponentBuilder:CreateDescription(Zones.TextZone, Options.Description, Theme, 2) or
                            nil

    local InputContainer = self.Utility:CreateInstance("Frame", {
        Size = UDim2.new(0.45, -self.Constants.Padding.Large, 1, 0),
        Position = UDim2.new(0.55, 0, 0, 0),
        BackgroundTransparency = 1,
        ZIndex = self.Constants.ZIndex.Overlay
    }, Zones.Container)

    local InputBox = self.Utility:CreateInstance("TextBox", {
        Size = UDim2.new(1, -10, 0, 32),
        Position = UDim2.new(1, -10, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = Theme.Tertiary,
        BorderSizePixel = 0,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = DefaultValue or "",
        PlaceholderText = Options.Placeholder or "Enter text...",
        TextColor3 = Theme.TextPrimary,
        PlaceholderColor3 = Theme.TextSecondary,
        TextSize = 13,
        Font = Theme.FontSecondary,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        ZIndex = self.Constants.ZIndex.Overlay
    }, InputContainer)

    self.Utility:CreateInstance("UICorner", {
        CornerRadius = UDim.new(0, self.Constants.Corner.Medium)
    }, InputBox)

    self.Utility:CreateInstance("UIPadding", {
        PaddingLeft = UDim.new(0, self.Constants.Padding.Medium),
        PaddingRight = UDim.new(0, self.Constants.Padding.Medium)
    }, InputBox)

    local Underline = self.Utility:CreateInstance("Frame", {
        Size = UDim2.new(1, 0, 0, 2),
        Position = UDim2.new(0, 0, 1, -2),
        BackgroundColor3 = Theme.Tertiary,
        BorderSizePixel = 0,
        ZIndex = self.Constants.ZIndex.Modal
    }, InputBox)

    self.Utility:CreateInstance("UICorner", {
        CornerRadius = UDim.new(1, 0)
    }, Underline)

    local ErrorLabel = self.Utility:CreateInstance("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = Color3.fromRGB(255, 100, 100),
        TextSize = 11,
        Font = Theme.FontSecondary,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextWrapped = true,
        Visible = false,
        ZIndex = self.Constants.ZIndex.Overlay
    }, InputContainer)

    local ThemeBindings = {
        [Zones.Container] = {
            BackgroundColor3 = "Secondary",
            BackgroundTransparency = "TransparencySecondary"
        },
        [Label] = {
            TextColor3 = "TextPrimary",
            Font = "FontSecondary"
        },
        [InputBox] = {
            TextColor3 = "TextPrimary",
            PlaceholderColor3 = "TextSecondary",
            BackgroundColor3 = "Tertiary",
            Font = "FontSecondary"
        },
        [Underline] = {
            BackgroundColor3 = "Tertiary"
        }
    }
    if Description then
        ThemeBindings[Description] = {
            TextColor3 = "TextSecondary",
            Font = "FontSecondary"
        }
    end
    if Window then
        self.ThemeManager:RegisterMultiple(Window, ThemeBindings)
    end

    local IsFocused = false
    local LastValidValue = DefaultValue or ""

    local ValidationPatterns = {
        Numbers = "^%-?%d+$",
        Decimals = "^%-?%d*%.?%d*$",
        Alphanumeric = "^[%a%d]+$"
    }

    local function validateInput(inputValue)
        if InputType == "Text" then
            return true
        end
        if inputValue == "" or (InputType == "Decimals" and inputValue == "-") then
            return true
        end

        local pattern = ValidationPatterns[InputType]
        return pattern and string.match(inputValue, pattern) ~= nil
    end

    local function showError(message)
        ErrorLabel.Text = message
        ErrorLabel.Visible = true
        TweenService:Create(InputBox, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
            BackgroundColor3 = Color3.fromRGB(100, 40, 40)
        }):Play()
    end

    local function clearError()
        ErrorLabel.Visible = false
        local CurrentTheme = Window and self.ThemeManager:GetCurrentTheme(Window) or Theme
        TweenService:Create(InputBox, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
            BackgroundColor3 = CurrentTheme.Tertiary
        }):Play()
    end

    local function updateHover(state)
        if IsFocused then
            return
        end
        local CurrentTheme = Window and self.ThemeManager:GetCurrentTheme(Window) or Theme
        TweenService:Create(InputBox, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
            BackgroundColor3 = state and CurrentTheme.TertiaryHover or CurrentTheme.Tertiary
        }):Play()
    end

    InputBox:GetPropertyChangedSignal("Text"):Connect(function()
        local currentText = InputBox.Text
        if not validateInput(currentText) then
            InputBox.Text = LastValidValue
            showError("Invalid " .. InputType)
        else
            LastValidValue = currentText
            if IsFocused then
                clearError()
            end
        end
    end)

    InputBox.Focused:Connect(function()
        IsFocused = true
        clearError()
        local CurrentTheme = Window and self.ThemeManager:GetCurrentTheme(Window) or Theme
        TweenService:Create(Underline, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
            BackgroundColor3 = CurrentTheme.Accent,
            Size = UDim2.new(1, 0, 0, 3)
        }):Play()
        TweenService:Create(InputBox, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
            BackgroundColor3 = CurrentTheme.TertiaryHover
        }):Play()
    end)

    InputBox.FocusLost:Connect(function()
        IsFocused = false
        local CurrentTheme = Window and self.ThemeManager:GetCurrentTheme(Window) or Theme
        TweenService:Create(Underline, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
            BackgroundColor3 = CurrentTheme.TertiaryPressed,
            Size = UDim2.new(1, 0, 0, 2)
        }):Play()
        updateHover(false)
        if validateInput(InputBox.Text) then
            EngProject.SaveManager:WriteBinding(SaveBinding, InputBox.Text)
            if Callback then
                EH:Try(function()
                    Callback(InputBox.Text)
                end)
            end
        else
            InputBox.Text = LastValidValue
        end
    end)

    if not IsMobile then
        InputBox.MouseEnter:Connect(function()
            updateHover(true)
        end)
        InputBox.MouseLeave:Connect(function()
            updateHover(false)
        end)
    end

    if SaveBinding.HasValue and SaveBinding.ApplyCallback and Callback then
        EH:Try(function()
            Callback(InputBox.Text)
        end)
    end

    return {
        GetValue = function(self)
            return InputBox.Text
        end,
        SetValue = function(self, Value)
            if EH:ValidateType(Value, "string", "Value", "TextInput:SetValue") and validateInput(Value) then
                InputBox.Text = Value
                LastValidValue = Value
                clearError()
                EngProject.SaveManager:WriteBinding(SaveBinding, Value)
            end
        end,
        SetPlaceholder = function(self, Placeholder)
            if EH:ValidateType(Placeholder, "string", "Placeholder", "TextInput:SetPlaceholder") then
                InputBox.PlaceholderText = Placeholder
            end
        end,
        Clear = function(self)
            InputBox.Text = ""
            LastValidValue = ""
            clearError()
            EngProject.SaveManager:WriteBinding(SaveBinding, "")
        end,
        GetInputType = function(self)
            return InputType
        end,
        SetInputType = function(self, NewType)
            if ValidTypes[NewType] then
                InputType = NewType
                clearError()
            end
        end,
        SetDescription = function(self, NewDescription)
            local HadDescription = Description ~= nil and Description.Visible
            local HasNewDescription = NewDescription and NewDescription ~= ""
            if Description and NewDescription then
                Description.Text = NewDescription
                Description.Visible = true
            elseif Description and not NewDescription then
                Description.Visible = false
            elseif not Description and NewDescription then
                Description = EngProject.ComponentBuilder:CreateDescription(Zones.TextZone, NewDescription, Theme, 2)
                if Window then
                    EngProject.ThemeManager:RegisterElement(Window, Description, {
                        TextColor3 = "TextSecondary",
                        Font = "FontSecondary"
                    })
                end
            end
            if HadDescription ~= HasNewDescription then
                EngProject.ComponentBuilder:UpdateDescriptionPadding(Zones, HasNewDescription)
            end
        end,
        GetElements = function(self)
            return {
                Container = Zones.Container,
                Label = Label,
                Description = Description,
                InputBox = InputBox,
                Underline = Underline,
                ErrorLabel = ErrorLabel
            }
        end
    }
end

function EngProject:CreateKeybind(Page, Text, DefaultKey, Callback, Options)
    local EH = self.ErrorHandler
    if not EH:ValidateInstance(Page, "GuiObject", "CreateKeybind") then
        return nil
    end
    if not EH:ValidateType(Text, "string", "Text", "CreateKeybind") then
        Text = "Keybind"
    end
    if DefaultKey and typeof(DefaultKey) ~= "EnumItem" then
        EH:Guard(false, "CreateKeybind", "DefaultKey must be a KeyCode Enum", EH.Levels.WARN)
        DefaultKey = nil
    elseif DefaultKey and DefaultKey.EnumType ~= Enum.KeyCode then
        EH:Guard(false, "CreateKeybind", "DefaultKey must be a KeyCode (not " .. tostring(DefaultKey.EnumType) .. ")",
            EH.Levels.WARN)
        DefaultKey = nil
    end
    if Callback then
        Callback = (EH:ValidateType(Callback, "function", "Callback", "CreateKeybind") == false) and nil or Callback
    end
    Options = Options or {}
    local SaveBinding = self.SaveManager:GetBinding(Options, "Keybind", Text)
    if SaveBinding.Enabled and type(SaveBinding.Value) == "string" then
        local SavedKey = Enum.KeyCode[SaveBinding.Value]
        if SavedKey then
            DefaultKey = SavedKey
        end
    end
    local Theme = self.ThemeManager:GetCurrentTheme(self.Utility:GetWindowFromElement(Page))
    local IsMobile = self.Utility:IsMobile()
    local Window = self.Utility:GetWindowFromElement(Page)
    local HasDescription = Options.Description and Options.Description ~= ""

    local Zones = self.ComponentBuilder:CreateContainer({
        Parent = Page,
        Layout = "TextLeft",
        TextWidth = 0.65,
        MinHeight = 35,
        Padding = HasDescription and {
            Top = self.Constants.Padding.Large,
            Bottom = self.Constants.Padding.Large,
            Left = self.Constants.Padding.Large,
            Right = self.Constants.Padding.Small
        } or {
            Top = 2,
            Bottom = 2,
            Left = self.Constants.Padding.Large,
            Right = self.Constants.Padding.Small
        },
        Spacing = HasDescription and self.Constants.Spacing.Tight or 0,
        HasDescription = HasDescription,
        CornerRadius = self.Constants.Corner.Medium,
        ColorTier = "Secondary"
    }, Theme)

    local Label = self.ComponentBuilder:CreateLabel(Zones.TextZone, Text, Theme, {
        ColorTier = "TextPrimary",
        Size = 14,
        Order = 1
    })

    local Description = HasDescription and
                            self.ComponentBuilder:CreateDescription(Zones.TextZone, Options.Description, Theme, 2) or
                            nil

    local DisplayContainer = self.Utility:CreateInstance("Frame", {
        Size = UDim2.new(0.35, -self.Constants.Padding.Large, 1, 0),
        Position = UDim2.new(0.65, 0, 0, 0),
        BackgroundTransparency = 1,
        ZIndex = self.Constants.ZIndex.Overlay
    }, Zones.Container)

    local Display = self.Utility:CreateInstance("TextButton", {
        Size = UDim2.new(1, -10, 0, 32),
        Position = UDim2.new(1, -10, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = Theme.Tertiary,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = self.Constants.ZIndex.Overlay
    }, DisplayContainer)

    self.Utility:CreateInstance("UICorner", {
        CornerRadius = UDim.new(0, self.Constants.Corner.Medium)
    }, Display)

    self.Utility:CreateInstance("UIPadding", {
        PaddingLeft = UDim.new(0, self.Constants.Padding.Medium),
        PaddingRight = UDim.new(0, self.Constants.Padding.Medium)
    }, Display)

    local DisplayLabel = self.Utility:CreateInstance("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = Theme.TextPrimary,
        TextSize = 13,
        Font = Theme.FontSecondary,
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = self.Constants.ZIndex.Modal
    }, Display)

    local ThemeBindings = {
        [Zones.Container] = {
            BackgroundColor3 = "Secondary",
            BackgroundTransparency = "TransparencySecondary"
        },
        [Label] = {
            TextColor3 = "TextPrimary",
            Font = "FontSecondary"
        },
        [DisplayLabel] = {
            TextColor3 = "TextPrimary",
            Font = "FontSecondary"
        }
    }
    if Description then
        ThemeBindings[Description] = {
            TextColor3 = "TextSecondary",
            Font = "FontSecondary"
        }
    end
    if Window then
        self.ThemeManager:RegisterMultiple(Window, ThemeBindings)
    end

    local CurrentKey = DefaultKey
    local IsListening = false
    local BindConnection
    local InputConnection

    local function UpdateDisplay()
        local CurrentTheme = Window and self.ThemeManager:GetCurrentTheme(Window) or Theme
        if IsListening then
            DisplayLabel.Text = "Press a key..."
            TweenService:Create(Display, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
                BackgroundColor3 = CurrentTheme.Accent
            }):Play()
            TweenService:Create(DisplayLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
                TextColor3 = CurrentTheme.TextActive
            }):Play()
        else
            DisplayLabel.Text = CurrentKey and CurrentKey.Name or "None"
            TweenService:Create(Display, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
                BackgroundColor3 = CurrentTheme.Tertiary
            }):Play()
            TweenService:Create(DisplayLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
                TextColor3 = CurrentTheme.TextPrimary
            }):Play()
        end
    end

    local function SetupBind()
        if BindConnection then
            BindConnection:Disconnect()
        end
        if CurrentKey and Callback then
            BindConnection = UserInputService.InputBegan:Connect(
                function(Input, GameProcessed)
                    if not GameProcessed and Input.KeyCode == CurrentKey then
                        EH:Try(function()
                            Callback(CurrentKey)
                        end)
                    end
                end)
        end
    end

    Display.Activated:Connect(function()
        if IsListening then
            return
        end
        IsListening = true
        UpdateDisplay()
        InputConnection = UserInputService.InputBegan:Connect(
            function(Input, GameProcessed)
                if Input.UserInputType == Enum.UserInputType.Keyboard then
                    CurrentKey = Input.KeyCode
                    IsListening = false
                    if InputConnection then
                        InputConnection:Disconnect()
                        InputConnection = nil
                    end
                    UpdateDisplay()
                    SetupBind()
                    EngProject.SaveManager:WriteBinding(SaveBinding, CurrentKey and CurrentKey.Name or nil)
                end
            end)
    end)

    if not IsMobile then
        Display.MouseEnter:Connect(function()
            if not IsListening then
                local CurrentTheme = Window and self.ThemeManager:GetCurrentTheme(Window) or Theme
                TweenService:Create(Display, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
                    BackgroundColor3 = CurrentTheme.TertiaryHover
                }):Play()
            end
        end)
        Display.MouseLeave:Connect(function()
            if not IsListening then
                local CurrentTheme = Window and self.ThemeManager:GetCurrentTheme(Window) or Theme
                TweenService:Create(Display, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
                    BackgroundColor3 = CurrentTheme.Tertiary
                }):Play()
            end
        end)
    end

    UpdateDisplay()
    SetupBind()

    if Window then
        self.ThemeManager:RegisterElement(Window, Display, {
            BackgroundColor3 = function(Element, Theme)
                if not IsListening then
                    Element.BackgroundColor3 = Theme.Tertiary
                end
            end
        })
    end

    return {
        GetKey = function(self)
            return CurrentKey
        end,
        SetKey = function(self, Key)
            if Key and typeof(Key) ~= "EnumItem" then
                EH:Guard(false, "Keybind:SetKey", "Key must be a KeyCode Enum", EH.Levels.WARN)
                return
            end
            CurrentKey = Key
            UpdateDisplay()
            SetupBind()
            EngProject.SaveManager:WriteBinding(SaveBinding, CurrentKey and CurrentKey.Name or nil)
        end,
        Clear = function(self)
            CurrentKey = nil
            UpdateDisplay()
            if BindConnection then
                BindConnection:Disconnect()
                BindConnection = nil
            end
            EngProject.SaveManager:WriteBinding(SaveBinding, nil)
        end,
        SetDescription = function(self, NewDescription)
            local HadDescription = Description ~= nil and Description.Visible
            local HasNewDescription = NewDescription and NewDescription ~= ""
            if Description and NewDescription then
                Description.Text = NewDescription
                Description.Visible = true
            elseif Description and not NewDescription then
                Description.Visible = false
            elseif not Description and NewDescription then
                Description = EngProject.ComponentBuilder:CreateDescription(Zones.TextZone, NewDescription, Theme, 2)
                if Window then
                    EngProject.ThemeManager:RegisterElement(Window, Description, {
                        TextColor3 = "TextSecondary",
                        Font = "FontSecondary"
                    })
                end
            end
            if HadDescription ~= HasNewDescription then
                EngProject.ComponentBuilder:UpdateDescriptionPadding(Zones, HasNewDescription)
            end
        end,
        GetElements = function(self)
            return {
                Container = Zones.Container,
                Label = Label,
                Description = Description,
                Display = Display,
                DisplayLabel = DisplayLabel
            }
        end
    }
end

function EngProject:CreateSlider(Page, Text, Min, Max, DefaultValue, Callback, Options)
    local EH = self.ErrorHandler
    if not EH:ValidateInstance(Page, "GuiObject", "CreateSlider") then
        return nil
    end
    if not EH:ValidateType(Text, "string", "Text", "CreateSlider") then
        Text = "Slider"
    end
    if not EH:ValidateType(Min, "number", "Min", "CreateSlider") then
        Min = 0
    end
    if not EH:ValidateType(Max, "number", "Max", "CreateSlider") then
        Max = 100
    end
    if Min >= Max then
        EH:Guard(false, "CreateSlider", "Min must be less than Max, swapping values", EH.Levels.WARN)
        Min, Max = Max, Min
    end
    if DefaultValue then
        if not EH:ValidateType(DefaultValue, "number", "DefaultValue", "CreateSlider") then
            DefaultValue = Min
        else
            DefaultValue = math.clamp(DefaultValue, Min, Max)
        end
    else
        DefaultValue = Min
    end
    if Callback then
        Callback = (EH:ValidateType(Callback, "function", "Callback", "CreateSlider") == false) and nil or Callback
    end
    Options = Options or {}
    local SaveBinding = self.SaveManager:GetBinding(Options, "Slider", Text)
    if SaveBinding.Enabled and type(SaveBinding.Value) == "number" then
        DefaultValue = math.clamp(SaveBinding.Value, Min, Max)
    end
    local Theme = self.ThemeManager:GetCurrentTheme(self.Utility:GetWindowFromElement(Page))
    local Window = self.Utility:GetWindowFromElement(Page)
    local Increment = Options.Increment or 1
    if not EH:ValidateType(Increment, "number", "Increment", "CreateSlider") then
        Increment = 1
    elseif Increment <= 0 then
        EH:Guard(false, "CreateSlider", "Increment must be positive, using 1", EH.Levels.WARN)
        Increment = 1
    end
    local HasDescription = Options.Description and Options.Description ~= ""
    local Zones = self.ComponentBuilder:CreateContainer({
        Parent = Page,
        Layout = "Stacked",
        MinHeight = 50,
        Padding = HasDescription and {
            Top = self.Constants.Padding.Large,
            Bottom = self.Constants.Padding.Large,
            Left = self.Constants.Padding.Large,
            Right = self.Constants.Padding.Small
        } or {
            Top = 2,
            Bottom = 2,
            Left = self.Constants.Padding.Large,
            Right = self.Constants.Padding.Small
        },
        Spacing = HasDescription and self.Constants.Spacing.Normal or self.Constants.Spacing.Tight,
        HasDescription = HasDescription,
        CornerRadius = self.Constants.Corner.Medium,
        ColorTier = "Secondary"
    }, Theme)
    local LabelContainer = self.Utility:CreateInstance("Frame", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        ZIndex = self.Constants.ZIndex.Overlay
    }, Zones.TextZone)
    local Label = self.ComponentBuilder:CreateLabel(LabelContainer, Text, Theme, {
        ColorTier = "TextPrimary",
        Size = 14,
        WidthOffset = -60
    })
    local ValueLabel = self.Utility:CreateInstance("TextLabel", {
        Size = UDim2.new(0, 50, 1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        AnchorPoint = Vector2.new(1, 0),
        BackgroundTransparency = 1,
        Text = tostring(DefaultValue or Min),
        TextColor3 = Theme.TextSecondary,
        TextSize = 13,
        Font = Theme.FontSecondary,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = self.Constants.ZIndex.Overlay
    }, LabelContainer)
    local Description = HasDescription and
                            self.ComponentBuilder:CreateDescription(Zones.TextZone, Options.Description, Theme, 2) or
                            nil
    local TrackContainer = self.Utility:CreateInstance("Frame", {
        Size = UDim2.new(1, 0, 0, 24),
        BackgroundTransparency = 1,
        LayoutOrder = 3,
        ZIndex = self.Constants.ZIndex.Overlay
    }, Zones.TextZone)
    local Track = self.Utility:CreateInstance("Frame", {
        Size = UDim2.new(1, 0, 0, 4),
        Position = UDim2.new(0, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = Theme.TertiaryPressed,
        BorderSizePixel = 0,
        ZIndex = self.Constants.ZIndex.Overlay
    }, TrackContainer)
    self.Utility:CreateInstance("UICorner", {
        CornerRadius = UDim.new(1, 0)
    }, Track)
    local Fill = self.Utility:CreateInstance("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        ZIndex = self.Constants.ZIndex.Modal
    }, Track)
    self.Utility:CreateInstance("UICorner", {
        CornerRadius = UDim.new(1, 0)
    }, Fill)
    local Thumb = self.Utility:CreateInstance("Frame", {
        Size = UDim2.new(0, 14, 0, 14),
        Position = UDim2.new(0, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Theme.TextActive,
        BorderSizePixel = 0,
        ZIndex = self.Constants.ZIndex.Notification
    }, Track)
    self.Utility:CreateInstance("UICorner", {
        CornerRadius = UDim.new(1, 0)
    }, Thumb)
    local ThemeBindings = {
        [Zones.Container] = {
            BackgroundColor3 = "Secondary",
            BackgroundTransparency = "TransparencySecondary"
        },
        [Label] = {
            TextColor3 = "TextPrimary",
            Font = "FontSecondary"
        },
        [ValueLabel] = {
            TextColor3 = "TextSecondary",
            Font = "FontSecondary"
        },
        [Track] = {
            BackgroundColor3 = "TertiaryPressed"
        },
        [Fill] = {
            BackgroundColor3 = "Accent"
        },
        [Thumb] = {
            BackgroundColor3 = "TextActive"
        }
    }
    if Description then
        ThemeBindings[Description] = {
            TextColor3 = "TextSecondary",
            Font = "FontSecondary"
        }
    end
    if Window then
        self.ThemeManager:RegisterMultiple(Window, ThemeBindings)
    end
    local IsDragging = false
    local Value = DefaultValue or Min
    local function RoundToIncrement(Number)
        return math.floor(Number / Increment + 0.5) * Increment
    end
    local function UpdateSlider(NewValue)
        Value = math.clamp(RoundToIncrement(NewValue), Min, Max)
        local Percent = (Value - Min) / (Max - Min)
        Fill.Size = UDim2.new(Percent, 0, 1, 0)
        Thumb.Position = UDim2.new(Percent, 0, 0.5, 0)
        ValueLabel.Text = tostring(Value)
        EngProject.SaveManager:WriteBinding(SaveBinding, Value)
        if Callback then
            EH:Try(function()
                Callback(Value)
            end)
        end
    end
    local function HandleInput(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
            IsDragging = true
            local Percent = math.clamp((Input.Position.X - Track.AbsolutePosition.X) / Track.AbsoluteSize.X, 0, 1)
            UpdateSlider(Min + (Max - Min) * Percent)
        end
    end
    Track.InputBegan:Connect(HandleInput)
    Thumb.InputBegan:Connect(HandleInput)
    UserInputService.InputChanged:Connect(function(Input)
        if IsDragging and
            (Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch) then
            local Percent = math.clamp((Input.Position.X - Track.AbsolutePosition.X) / Track.AbsoluteSize.X, 0, 1)
            UpdateSlider(Min + (Max - Min) * Percent)
        end
    end)
    UserInputService.InputEnded:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
            IsDragging = false
        end
    end)
    UpdateSlider(Value)
    return {
        GetValue = function(self)
            return Value
        end,
        SetValue = function(self, NewValue)
            if EH:ValidateType(NewValue, "number", "NewValue", "Slider:SetValue") then
                UpdateSlider(NewValue)
            end
        end,
        SetMin = function(self, NewMin)
            if EH:ValidateType(NewMin, "number", "NewMin", "Slider:SetMin") then
                if NewMin < Max then
                    Min = NewMin
                    UpdateSlider(Value)
                else
                    EH:Guard(false, "Slider:SetMin", "Min must be less than Max", EH.Levels.WARN)
                end
            end
        end,
        SetMax = function(self, NewMax)
            if EH:ValidateType(NewMax, "number", "NewMax", "Slider:SetMax") then
                if NewMax > Min then
                    Max = NewMax
                    UpdateSlider(Value)
                else
                    EH:Guard(false, "Slider:SetMax", "Max must be greater than Min", EH.Levels.WARN)
                end
            end
        end,
        SetDescription = function(self, NewDescription)
            local HadDescription = Description ~= nil and Description.Visible
            local HasNewDescription = NewDescription and NewDescription ~= ""
            if Description and NewDescription then
                Description.Text = NewDescription
                Description.Visible = true
            elseif Description and not NewDescription then
                Description.Visible = false
            elseif not Description and NewDescription then
                Description = EngProject.ComponentBuilder:CreateDescription(Zones.TextZone, NewDescription, Theme, 2)
                if Window then
                    EngProject.ThemeManager:RegisterElement(Window, Description, {
                        TextColor3 = "TextSecondary",
                        Font = "FontSecondary"
                    })
                end
            end
            if HadDescription ~= HasNewDescription then
                EngProject.ComponentBuilder:UpdateDescriptionPadding(Zones, HasNewDescription)
            end
        end,
        GetElements = function(self)
            return {
                Container = Zones.Container,
                Label = Label,
                ValueLabel = ValueLabel,
                Description = Description,
                Track = Track,
                Fill = Fill,
                Thumb = Thumb
            }
        end
    }
end

function EngProject:CreateParagraph(Page, Title, Fields, Options)
    local EH = self.ErrorHandler
    if not EH:ValidateInstance(Page, "GuiObject", "CreateParagraph") then
        return nil
    end
    if not EH:ValidateType(Title, "string", "Title", "CreateParagraph") then
        Title = "Paragraph"
    end
    if Fields and not EH:ValidateType(Fields, "table", "Fields", "CreateParagraph") then
        Fields = {}
    end
    Options = Options or {}
    local Theme = self.ThemeManager:GetCurrentTheme(self.Utility:GetWindowFromElement(Page))
    local Window = self.Utility:GetWindowFromElement(Page)
    local Container = self.Utility:CreateInstance("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Secondary,
        BackgroundTransparency = Theme.TransparencySecondary,
        BorderSizePixel = 0,
        ZIndex = self.Constants.ZIndex.Control
    }, Page)
    if not Container then
        EH:Guard(false, "CreateParagraph", "Failed to create container", EH.Levels.ERROR)
        return nil
    end
    self.Utility:CreateInstance("UICorner", {
        CornerRadius = UDim.new(0, self.Constants.Corner.Medium)
    }, Container)
    self.Utility:CreateInstance("UIPadding", {
        PaddingTop = UDim.new(0, self.Constants.Padding.Large),
        PaddingBottom = UDim.new(0, self.Constants.Padding.Large),
        PaddingLeft = UDim.new(0, self.Constants.Padding.Large),
        PaddingRight = UDim.new(0, self.Constants.Padding.Large)
    }, Container)
    local ContentFrame = self.Utility:CreateInstance("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ZIndex = self.Constants.ZIndex.Overlay
    }, Container)
    self.Utility:CreateInstance("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        VerticalAlignment = Enum.VerticalAlignment.Top,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, self.Constants.Spacing.Normal)
    }, ContentFrame)
    local TitleLabel = self.Utility:CreateInstance("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        Text = Title or "Paragraph",
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true,
        LayoutOrder = 0,
        ZIndex = self.Constants.ZIndex.Overlay,
        TextColor3 = Theme.TextActive,
        Font = Theme.FontPrimary
    }, ContentFrame)
    local ThemeBindings = {
        [Container] = {
            BackgroundColor3 = function(Element, CurrentTheme)
                Element.BackgroundColor3 = CurrentTheme.Secondary
            end,
            BackgroundTransparency = function(Element, CurrentTheme)
                Element.BackgroundTransparency = CurrentTheme.TransparencySecondary
            end
        },
        [TitleLabel] = {
            TextColor3 = function(Element, CurrentTheme)
                Element.TextColor3 = CurrentTheme.TextActive
            end,
            Font = "FontPrimary"
        }
    }
    if Window then
        self.ThemeManager:RegisterMultiple(Window, ThemeBindings)
    end
    local FieldElements = {}
    local FieldCounter = 0
    local function CreateField(FieldData, LayoutOrder)
        if type(FieldData) ~= "table" and type(FieldData) ~= "string" then
            EH:Guard(false, "Paragraph:CreateField", "Invalid field data type", EH.Levels.WARN)
            return nil
        end
        FieldCounter = FieldCounter + 1
        local FieldId = "Field_" .. FieldCounter
        local IsSubField = FieldData.IsSubField or false
        local FieldText = type(FieldData) == "string" and FieldData or (FieldData.Text or "")
        if not EH:ValidateType(FieldText, "string", "FieldText", "Paragraph:CreateField") then
            FieldText = ""
        end
        local CurrentTheme = Window and self.ThemeManager:GetCurrentTheme(Window) or Theme
        local Field = self.Utility:CreateInstance("TextLabel", {
            Size = UDim2.new(1, IsSubField and -20 or 0, 0, 0),
            Position = IsSubField and UDim2.new(0, 20, 0, 0) or UDim2.new(0, 0, 0, 0),
            BackgroundTransparency = 1,
            Text = FieldText,
            TextSize = IsSubField and 13 or 14,
            TextXAlignment = Enum.TextXAlignment.Left,
            AutomaticSize = Enum.AutomaticSize.Y,
            TextWrapped = true,
            LayoutOrder = LayoutOrder or (FieldCounter + 1),
            ZIndex = self.Constants.ZIndex.Overlay,
            TextColor3 = IsSubField and CurrentTheme.TextSecondary or CurrentTheme.TextActive,
            Font = CurrentTheme.FontSecondary
        }, ContentFrame)
        if not Field then
            EH:Guard(false, "Paragraph:CreateField", "Failed to create field", EH.Levels.WARN)
            return nil
        end
        if Window then
            self.ThemeManager:RegisterElement(Window, Field, {
                TextColor3 = function(Element, CurrentTheme)
                    Element.TextColor3 = IsSubField and CurrentTheme.TextSecondary or CurrentTheme.TextActive
                end,
                Font = "FontSecondary"
            })
        end
        FieldElements[FieldId] = {
            Element = Field,
            Data = type(FieldData) == "table" and FieldData or {
                Text = FieldData,
                IsSubField = false
            },
            Id = FieldId
        }
        return FieldId, Field
    end
    if Fields and type(Fields) == "table" then
        for Index, FieldData in ipairs(Fields) do
            EH:Try(function()
                CreateField(FieldData, Index)
            end)
        end
    end
    return {
        AddField = function(self, Text, IsSubField, Position)
            if not EH:ValidateType(Text, "string", "Text", "Paragraph:AddField") then
                return nil
            end
            return EH:Try(function()
                return CreateField({
                    Text = Text,
                    IsSubField = IsSubField or false
                }, Position or (FieldCounter + 2))
            end)
        end,
        RemoveField = function(self, FieldId)
            if not EH:ValidateType(FieldId, "string", "FieldId", "Paragraph:RemoveField") then
                return false
            end
            if not FieldElements[FieldId] then
                EH:Guard(false, "Paragraph:RemoveField", string.format("Field '%s' not found", FieldId), EH.Levels.WARN)
                return false
            end
            return EH:Try(function()
                FieldElements[FieldId].Element:Destroy()
                FieldElements[FieldId] = nil
                return true
            end, function()
                return false
            end)
        end,
        SetField = function(self, FieldId, Text)
            if not EH:ValidateType(FieldId, "string", "FieldId", "Paragraph:SetField") then
                return false
            end
            if not EH:ValidateType(Text, "string", "Text", "Paragraph:SetField") then
                return false
            end
            if not FieldElements[FieldId] then
                EH:Guard(false, "Paragraph:SetField", string.format("Field '%s' not found", FieldId), EH.Levels.WARN)
                return false
            end
            return EH:Try(function()
                FieldElements[FieldId].Element.Text = Text
                FieldElements[FieldId].Data.Text = Text
                return true
            end, function()
                return false
            end)
        end,
        GetField = function(self, FieldId)
            if not EH:ValidateType(FieldId, "string", "FieldId", "Paragraph:GetField") then
                return nil
            end
            return FieldElements[FieldId] and FieldElements[FieldId].Data.Text or nil
        end,
        FindField = function(self, SearchText)
            if not EH:ValidateType(SearchText, "string", "SearchText", "Paragraph:FindField") then
                return nil
            end
            for Id, FieldData in pairs(FieldElements) do
                if FieldData.Data.Text:find(SearchText, 1, true) then
                    return Id, FieldData.Data.Text
                end
            end
            return nil
        end,
        GetAllFields = function(self)
            local Result = {}
            for Id, FieldData in pairs(FieldElements) do
                table.insert(Result, {
                    Id = Id,
                    Text = FieldData.Data.Text,
                    IsSubField = FieldData.Data.IsSubField
                })
            end
            return Result
        end,
        SetFields = function(self, NewFields)
            if not EH:ValidateType(NewFields, "table", "NewFields", "Paragraph:SetFields") then
                return false
            end
            return EH:Try(function()
                for Id, FieldData in pairs(FieldElements) do
                    FieldData.Element:Destroy()
                end
                FieldElements = {}
                FieldCounter = 0
                if NewFields and type(NewFields) == "table" then
                    for Index, FieldData in ipairs(NewFields) do
                        CreateField(FieldData, Index)
                    end
                end
                return true
            end, function()
                return false
            end)
        end,
        ClearFields = function(self)
            return EH:Try(function()
                for Id, FieldData in pairs(FieldElements) do
                    FieldData.Element:Destroy()
                end
                FieldElements = {}
                FieldCounter = 0
                return true
            end, function()
                return false
            end)
        end,
        SetTitle = function(self, NewTitle)
            if not EH:ValidateType(NewTitle, "string", "NewTitle", "Paragraph:SetTitle") then
                return false
            end
            TitleLabel.Text = NewTitle
            return true
        end,
        GetFieldCount = function(self)
            local Count = 0
            for _ in pairs(FieldElements) do
                Count = Count + 1
            end
            return Count
        end,
        GetElements = function(self)
            return {
                Container = Container,
                ContentFrame = ContentFrame,
                TitleLabel = TitleLabel,
                Fields = FieldElements
            }
        end
    }
end

function EngProject:CreateDropdown(Page, Text, Options, DefaultValue, Callback, DropdownOptions)
    local EH = self.ErrorHandler
    if not EH:ValidateInstance(Page, "GuiObject", "CreateDropdown") then
        return nil
    end
    if not EH:ValidateType(Text, "string", "Text", "CreateDropdown") then
        Text = "Dropdown"
    end
    if not EH:ValidateType(Options, "table", "Options", "CreateDropdown") then
        Options = {}
    end
    if #Options == 0 then
        EH:Guard(false, "CreateDropdown", "Options array is empty", EH.Levels.WARN)
    end
    if Callback and not EH:ValidateType(Callback, "function", "Callback", "CreateDropdown") then
        Callback = nil
    end
    DropdownOptions = DropdownOptions or {}
    local Theme = self.ThemeManager:GetCurrentTheme(self.Utility:GetWindowFromElement(Page))
    local IsMobile = self.Utility:IsMobile()
    local Window = self.Utility:GetWindowFromElement(Page)
    local IsMultiSelect = DropdownOptions.MultiSelect or false
    local ChangedEvent = Instance.new("BindableEvent")
    local HasDescription = DropdownOptions.Description and DropdownOptions.Description ~= ""
    local SaveBinding = self.SaveManager:GetBinding(DropdownOptions, "Dropdown", Text)
    if SaveBinding.Enabled then
        if IsMultiSelect and type(SaveBinding.Value) == "table" then
            DefaultValue = SaveBinding.Value
        elseif not IsMultiSelect and type(SaveBinding.Value) == "string" then
            DefaultValue = SaveBinding.Value
        end
    end

    local Zones = self.ComponentBuilder:CreateContainer({
        Parent = Page,
        Layout = "TextLeft",
        TextWidth = 0.55,
        MinHeight = 35,
        Padding = HasDescription and {
            Top = self.Constants.Padding.Large,
            Bottom = self.Constants.Padding.Large,
            Left = self.Constants.Padding.Large,
            Right = self.Constants.Padding.Small
        } or {
            Top = 2,
            Bottom = 2,
            Left = self.Constants.Padding.Large,
            Right = self.Constants.Padding.Small
        },
        Spacing = HasDescription and self.Constants.Spacing.Tight or 0,
        HasDescription = HasDescription,
        CornerRadius = self.Constants.Corner.Medium,
        ColorTier = "Secondary"
    }, Theme)

    local Label = self.ComponentBuilder:CreateLabel(Zones.TextZone, Text, Theme, {
        ColorTier = "TextPrimary",
        Size = 14,
        Order = 1
    })

    local Description = HasDescription and
                            self.ComponentBuilder:CreateDescription(Zones.TextZone, DropdownOptions.Description, Theme,
            2) or nil

    local DisplayContainer = self.Utility:CreateInstance("Frame", {
        Size = UDim2.new(0.45, -self.Constants.Padding.Large, 1, 0),
        Position = UDim2.new(0.55, 0, 0, 0),
        BackgroundTransparency = 1,
        ZIndex = self.Constants.ZIndex.Overlay
    }, Zones.Container)

    local Display = self.Utility:CreateInstance("TextButton", {
        Size = UDim2.new(1, -10, 0, 32),
        Position = UDim2.new(1, -10, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = Theme.Tertiary,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = self.Constants.ZIndex.Overlay
    }, DisplayContainer)

    self.Utility:CreateInstance("UICorner", {
        CornerRadius = UDim.new(0, self.Constants.Corner.Medium)
    }, Display)

    local DisplayLabel = self.Utility:CreateInstance("TextLabel", {
        Size = UDim2.new(1, -32, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = Theme.TextPrimary,
        TextSize = 13,
        Font = Theme.FontSecondary,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = self.Constants.ZIndex.Modal
    }, Display)

    local Arrow = self.Utility:CreateInstance("ImageLabel", {
        Size = UDim2.new(0, 14, 0, 14),
        Position = UDim2.new(1, -10, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundTransparency = 1,
        Image = "rbxassetid://10709790948",
        ImageColor3 = Theme.TextPrimary,
        ZIndex = self.Constants.ZIndex.Modal
    }, Display)

    local ThemeBindings = {
        [Zones.Container] = {
            BackgroundColor3 = "Secondary",
            BackgroundTransparency = "TransparencySecondary"
        },
        [Label] = {
            TextColor3 = "TextPrimary",
            Font = "FontSecondary"
        },
        [Display] = {
            BackgroundColor3 = "Tertiary"
        },
        [DisplayLabel] = {
            TextColor3 = "TextPrimary",
            Font = "FontSecondary"
        },
        [Arrow] = {
            ImageColor3 = "TextPrimary"
        }
    }
    if Description then
        ThemeBindings[Description] = {
            TextColor3 = "TextSecondary",
            Font = "FontSecondary"
        }
    end
    if Window then
        self.ThemeManager:RegisterMultiple(Window, ThemeBindings)
    end

    local ScreenGui = Page
    while ScreenGui do
        if ScreenGui:IsA("ScreenGui") then
            break
        end
        ScreenGui = ScreenGui.Parent
    end
    if not ScreenGui then
        EH:Guard(false, "CreateDropdown", "Failed to find ScreenGui parent", EH.Levels.ERROR)
        return nil
    end

    local ListContainer = self.Utility:CreateInstance("Frame", {
        Size = UDim2.new(0, Display.AbsoluteSize.X, 0, 0),
        BackgroundColor3 = Theme.Tertiary,
        BackgroundTransparency = Theme.TransparencyPrimary,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = self.Constants.ZIndex.Modal,
        ClipsDescendants = true
    }, ScreenGui)

    self.Utility:CreateInstance("UICorner", {
        CornerRadius = UDim.new(0, self.Constants.Corner.Medium)
    }, ListContainer)

    local SearchBox = self.Utility:CreateInstance("TextBox", {
        Size = UDim2.new(1, -8, 0, 30),
        Position = UDim2.new(0, 4, 0, 4),
        BackgroundColor3 = Theme.Tertiary,
        BorderSizePixel = 0,
        Text = "",
        PlaceholderText = "Search...",
        TextColor3 = Theme.TextPrimary,
        PlaceholderColor3 = Theme.TextSecondary,
        TextSize = 13,
        Font = Theme.FontSecondary,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        Visible = false,
        ZIndex = self.Constants.ZIndex.Modal + 1
    }, ListContainer)

    self.Utility:CreateInstance("UICorner", {
        CornerRadius = UDim.new(0, self.Constants.Corner.Medium)
    }, SearchBox)

    self.Utility:CreateInstance("UIPadding", {
        PaddingLeft = UDim.new(0, self.Constants.Padding.Medium),
        PaddingRight = UDim.new(0, self.Constants.Padding.Medium)
    }, SearchBox)

    if Window then
        self.ThemeManager:RegisterMultiple(Window, {
            [ListContainer] = {
                BackgroundColor3 = "Tertiary",
                BackgroundTransparency = "TransparencyPrimary"
            },
            [SearchBox] = {
                BackgroundColor3 = "Tertiary",
                TextColor3 = "TextPrimary",
                PlaceholderColor3 = "TextSecondary",
                Font = "FontSecondary"
            }
        })
    end

    local ScrollList = self.Utility:CreateInstance("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, -38),
        Position = UDim2.new(0, 0, 0, 38),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        ScrollBarImageColor3 = Theme.TextSecondary,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ZIndex = self.Constants.ZIndex.Modal + 1,
        AutomaticCanvasSize = Enum.AutomaticSize.Y
    }, ListContainer)

    self.Utility:CreateInstance("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Top,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, self.Constants.Spacing.Tight)
    }, ScrollList)

    self.Utility:CreateInstance("UIPadding", {
        PaddingTop = UDim.new(0, IsMobile and 0 or 1),
        PaddingBottom = UDim.new(0, IsMobile and 0 or 1),
        PaddingLeft = UDim.new(0, IsMobile and 0 or 1),
        PaddingRight = UDim.new(0, IsMobile and 0 or 1)
    }, ScrollList)

    local NormalizedOptions, OptionDataMap = self.DropdownManager:NormalizeOptions(Options)
    local SelectedValues = self.DropdownManager:InitializeSelection(DefaultValue, IsMultiSelect, OptionDataMap)
    local IsOpen = false
    local IsToggling = false
    local InputBlocker = nil
    local TargetHeight = 0
    local HasSearch = false
    local InputConnection
    local DisplayState = "Base"

    local function UpdateDisplayColor()
        local CurrentTheme = Window and self.ThemeManager:GetCurrentTheme(Window) or Theme
        local ColorGoal = CurrentTheme.Tertiary
        local ArrowRotation = 0

        if DisplayState == "Hover" then
            ColorGoal = CurrentTheme.TertiaryHover
        elseif DisplayState == "Active" then
            ColorGoal = CurrentTheme.TertiaryActive
            ArrowRotation = 180
        elseif DisplayState == "Pressed" then
            ColorGoal = CurrentTheme.TertiaryPressed
        end

        TweenService:Create(Display, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
            BackgroundColor3 = ColorGoal
        }):Play()

        TweenService:Create(Arrow, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
            Rotation = ArrowRotation
        }):Play()
    end

    if not IsMobile then
        Display.MouseEnter:Connect(function()
            if not IsOpen then
                DisplayState = "Hover"
                UpdateDisplayColor()
            end
        end)
        Display.MouseLeave:Connect(function()
            if not IsOpen then
                DisplayState = "Base"
                UpdateDisplayColor()
            end
        end)
        Display.MouseButton1Down:Connect(function()
            DisplayState = "Pressed"
            UpdateDisplayColor()
        end)
        Display.MouseButton1Up:Connect(function()
            if not IsOpen then
                DisplayState = "Hover"
            end
            UpdateDisplayColor()
        end)
    end

    local function CloseDropdown()
        if InputBlocker then
            InputBlocker:Destroy()
            InputBlocker = nil
        end
        if not IsOpen then
            return
        end
        IsOpen = false
        DisplayState = "Base"
        UpdateDisplayColor()

        TweenService:Create(ListContainer, TweenInfo.new(self.Constants.Animation.Fast, Enum.EasingStyle.Quad,
            Enum.EasingDirection.In), {
            Size = UDim2.new(0, Display.AbsoluteSize.X, 0, 0)
        }):Play()
        task.wait(self.Constants.Animation.Fast)
        ListContainer.Visible = false
        SearchBox.Text = ""

        if InputConnection then
            InputConnection:Disconnect()
            InputConnection = nil
        end
    end

    local function UpdateDisplay()
        self.DropdownManager:UpdateDisplayText(DisplayLabel, SelectedValues, IsMultiSelect)
    end

    local function SerializeSelection()
        if IsMultiSelect then
            local values = {}
            for OptionText, Selected in pairs(SelectedValues) do
                if Selected then
                    table.insert(values, OptionText)
                end
            end
            table.sort(values)
            return values
        end
        return SelectedValues
    end

    local function FilterOptions(Query)
        Query = Query:lower()
        for _, Child in ipairs(ScrollList:GetChildren()) do
            if Child:IsA("Frame") then
                local OptionButton = Child:FindFirstChild("TextButton")
                if OptionButton then
                    if Query == "" or OptionButton.Text:lower():find(Query, 1, true) then
                        Child.Visible = true
                    else
                        Child.Visible = false
                    end
                end
            end
        end
    end

    local function UpdateListPosition()
        local DisplayPos = Display.AbsolutePosition
        local DisplaySize = Display.AbsoluteSize
        local ScreenSize = ScreenGui.AbsoluteSize
        local BaseMaxHeight = 160
        local Layout = ScrollList:FindFirstChildOfClass("UIListLayout")
        local ContentHeight = Layout and Layout.AbsoluteContentSize.Y + 16 or 0
        HasSearch = ContentHeight > BaseMaxHeight
        SearchBox.Visible = HasSearch

        if HasSearch then
            ScrollList.Size = UDim2.new(1, 0, 1, -38)
            ScrollList.Position = UDim2.new(0, 0, 0, 38)
        else
            ScrollList.Size = UDim2.new(1, 0, 1, 0)
            ScrollList.Position = UDim2.new(0, 0, 0, 0)
        end

        TargetHeight = math.min(BaseMaxHeight, ContentHeight) + (HasSearch and 38 or 0)

        local YPos = DisplayPos.Y + DisplaySize.Y + 4
        if YPos + TargetHeight > ScreenSize.Y then
            YPos = DisplayPos.Y - TargetHeight - 4
        end

        ListContainer.Size = UDim2.new(0, DisplaySize.X, 0, 0)
        ListContainer.Position = UDim2.new(0, DisplayPos.X, 0, YPos)
    end

    local function CreateOption(OptionText, Index)
        local CurrentTheme = Window and self.ThemeManager:GetCurrentTheme(Window) or Theme
        local OptionContainer = self.Utility:CreateInstance("Frame", {
            Size = UDim2.new(1, -8, 0, IsMobile and 24 or 30),
            BackgroundTransparency = 1,
            ZIndex = self.Constants.ZIndex.Modal + 2,
            LayoutOrder = Index
        }, ScrollList)

        local OptionButton = self.Utility:CreateInstance("TextButton", {
            Size = UDim2.new(1, 0, 1, 0),
            Position = UDim2.new(0, 0, 0, 0),
            BackgroundColor3 = CurrentTheme.Tertiary,
            BorderSizePixel = 0,
            Text = OptionText,
            TextColor3 = CurrentTheme.TextPrimary,
            TextSize = IsMobile and 8 or 13,
            Font = CurrentTheme.FontSecondary,
            TextTruncate = Enum.TextTruncate.SplitWord,
            TextXAlignment = Enum.TextXAlignment.Left,
            AutoButtonColor = false,
            ZIndex = self.Constants.ZIndex.Modal + 3
        }, OptionContainer)

        self.Utility:CreateInstance("UICorner", {
            CornerRadius = UDim.new(0, self.Constants.Corner.Small)
        }, OptionButton)

        self.Utility:CreateInstance("UIPadding", {
            PaddingLeft = UDim.new(0, IsMobile and 4 or 6),
            PaddingRight = UDim.new(0, IsMobile and 2 or self.Constants.Padding.Small)
        }, OptionButton)

        local Indicator = self.Utility:CreateInstance("Frame", {
            Size = UDim2.new(0, IsMobile and 1 or 2, 0.35, 0),
            Position = UDim2.new(0, IsMobile and 0.1 or 2, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundColor3 = CurrentTheme.Accent,
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = self.Constants.ZIndex.Modal + 4
        }, OptionContainer)

        self.Utility:CreateInstance("UICorner", {
            CornerRadius = UDim.new(1, 0)
        }, Indicator)

        if Window then
            self.ThemeManager:RegisterElement(Window, OptionButton, {
                BackgroundColor3 = "Tertiary",
                TextColor3 = "TextPrimary",
                Font = "FontSecondary"
            })
            self.ThemeManager:RegisterElement(Window, Indicator, {
                BackgroundColor3 = "Accent"
            })
        end

        if IsMultiSelect then
            local function UpdateIndicator()
                Indicator.Visible = SelectedValues[OptionText] or false
            end
            OptionButton.Activated:Connect(function()
                SelectedValues[OptionText] = not SelectedValues[OptionText]
                UpdateIndicator()
                UpdateDisplay()
                local Selected = EngProject.DropdownManager:GetSelectedData(SelectedValues, IsMultiSelect, OptionDataMap)
                EngProject.SaveManager:WriteBinding(SaveBinding, SerializeSelection())
                if Callback then
                    EH:Try(function()
                        Callback(Selected)
                    end)
                end
                ChangedEvent:Fire(Selected)
            end)
            UpdateIndicator()
        else
            Indicator.Visible = SelectedValues == OptionText
            OptionButton.Activated:Connect(function()
                for _, Child in ipairs(ScrollList:GetChildren()) do
                    if Child:IsA("Frame") then
                        local Ind = Child:FindFirstChild("Frame")
                        if Ind then
                            Ind.Visible = false
                        end
                    end
                end
                SelectedValues = OptionText
                Indicator.Visible = true
                UpdateDisplay()
                CloseDropdown()
                local Selected = EngProject.DropdownManager:GetSelectedData(SelectedValues, IsMultiSelect, OptionDataMap)
                EngProject.SaveManager:WriteBinding(SaveBinding, SerializeSelection())
                if Callback then
                    EH:Try(function()
                        Callback(Selected)
                    end)
                end
                ChangedEvent:Fire(Selected)
            end)
        end

        if not IsMobile then
            OptionButton.MouseEnter:Connect(function()
                local CurrentTheme = Window and EngProject.ThemeManager:GetCurrentTheme(Window) or Theme
                TweenService:Create(OptionButton, TweenInfo.new(0.1, Enum.EasingStyle.Quad), {
                    BackgroundColor3 = CurrentTheme.TertiaryHover
                }):Play()
            end)
            OptionButton.MouseLeave:Connect(function()
                local CurrentTheme = Window and EngProject.ThemeManager:GetCurrentTheme(Window) or Theme
                TweenService:Create(OptionButton, TweenInfo.new(0.1, Enum.EasingStyle.Quad), {
                    BackgroundColor3 = CurrentTheme.Tertiary
                }):Play()
            end)
            OptionButton.MouseButton1Down:Connect(function()
                local CurrentTheme = Window and EngProject.ThemeManager:GetCurrentTheme(Window) or Theme
                OptionButton.BackgroundColor3 = CurrentTheme.TertiaryPressed
            end)
            OptionButton.MouseButton1Up:Connect(function()
                local CurrentTheme = Window and EngProject.ThemeManager:GetCurrentTheme(Window) or Theme
                OptionButton.BackgroundColor3 = CurrentTheme.TertiaryHover
            end)
        end
    end

    for Index, OptionText in ipairs(NormalizedOptions) do
        CreateOption(OptionText, Index)
    end

    SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        FilterOptions(SearchBox.Text)
    end)

    UpdateDisplay()
    UpdateDisplayColor()

    if SaveBinding.HasValue and SaveBinding.ApplyCallback and Callback then
        EH:Try(function()
            Callback(EngProject.DropdownManager:GetSelectedData(SelectedValues, IsMultiSelect, OptionDataMap))
        end)
    end

    Display.Activated:Connect(function()
        if IsToggling then
            return
        end
        IsToggling = true
        if IsOpen then
            CloseDropdown()
        else
            IsOpen = true
            InputBlocker = EH:Try(function()
                return self.Utility:CreateInstance("TextButton", {
                    Name = "DropdownInputBlocker",
                    Size = UDim2.fromScale(1, 1),
                    Position = UDim2.fromScale(0, 0),
                    Text = "",
                    BackgroundTransparency = 1,
                    AutoButtonColor = false,
                    ZIndex = self.Constants.ZIndex.Modal - 1
                }, ScreenGui)
            end)
            if InputBlocker then
                InputBlocker.Activated:Connect(function()
                    CloseDropdown()
                end)
            end
            DisplayState = "Active"
            UpdateDisplayColor()
            UpdateListPosition()
            ListContainer.Visible = true
            TweenService:Create(ListContainer, TweenInfo.new(self.Constants.Animation.Normal, Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out), {
                Size = UDim2.new(0, Display.AbsoluteSize.X, 0, TargetHeight)
            }):Play()
            task.wait()
            InputConnection = UserInputService.InputBegan:Connect(function(Input)
                if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType ==
                    Enum.UserInputType.Touch then
                    local MousePos = Input.Position
                    local ListPos = ListContainer.AbsolutePosition
                    local ListSize = ListContainer.AbsoluteSize
                    local DisplayPos = Display.AbsolutePosition
                    local DisplaySize = Display.AbsoluteSize
                    local InList = MousePos.X >= ListPos.X and MousePos.X <= ListPos.X + ListSize.X and MousePos.Y >=
                                       ListPos.Y and MousePos.Y <= ListPos.Y + ListSize.Y
                    local InDisplay = MousePos.X >= DisplayPos.X and MousePos.X <= DisplayPos.X + DisplaySize.X and
                                          MousePos.Y >= DisplayPos.Y and MousePos.Y <= DisplayPos.Y + DisplaySize.Y
                    if not InList and not InDisplay and not IsToggling then
                        CloseDropdown()
                    end
                end
            end)
        end
        task.wait(0.1)
        IsToggling = false
    end)

    return {
        GetValue = function(self)
            return EngProject.DropdownManager:GetSelectedData(SelectedValues, IsMultiSelect, OptionDataMap)
        end,
        SetValue = function(self, Value)
            if IsMultiSelect then
                SelectedValues = {}
                if EH:ValidateType(Value, "table", "Value", "Dropdown:SetValue") then
                    for _, V in ipairs(Value) do
                        local Normalized = type(V) == "table" and
                                               (V.Text or V.text or V.Label or V.label or tostring(V)) or tostring(V)
                        if OptionDataMap[Normalized] then
                            SelectedValues[Normalized] = true
                        end
                    end
                end
            else
                local Normalized = type(Value) == "table" and
                                       (Value.Text or Value.text or Value.Label or Value.label or tostring(Value)) or
                                       tostring(Value)
                if OptionDataMap[Normalized] then
                    SelectedValues = Normalized
                end
            end
            for _, Child in ipairs(ScrollList:GetChildren()) do
                if Child:IsA("Frame") then
                    local Ind = Child:FindFirstChild("Frame")
                    local Opt = Child:FindFirstChild("TextButton")
                    if Ind and Opt then
                        if IsMultiSelect then
                            Ind.Visible = SelectedValues[Opt.Text] or false
                        else
                            Ind.Visible = SelectedValues == Opt.Text
                        end
                    end
                end
            end
            UpdateDisplay()
            EngProject.SaveManager:WriteBinding(SaveBinding, SerializeSelection())
            ChangedEvent:Fire(Value)
            if Callback then
                EH:Try(function()
                    Callback(EngProject.DropdownManager:GetSelectedData(SelectedValues, IsMultiSelect, OptionDataMap))
                end)
            end
        end,
        SetOptions = function(self, NewOptions)
            if not EH:ValidateType(NewOptions, "table", "NewOptions", "Dropdown:SetOptions") then
                return
            end
            for _, Child in ipairs(ScrollList:GetChildren()) do
                if Child:IsA("Frame") then
                    Child:Destroy()
                end
            end
            Options = NewOptions
            NormalizedOptions, OptionDataMap = EngProject.DropdownManager:NormalizeOptions(Options)
            for Index, OptionText in ipairs(NormalizedOptions) do
                CreateOption(OptionText, Index)
            end
            if IsMultiSelect then
                local ValidSelected = {}
                for Value, Enabled in pairs(SelectedValues) do
                    if OptionDataMap[Value] then
                        ValidSelected[Value] = Enabled
                    end
                end
                SelectedValues = ValidSelected
            else
                if not OptionDataMap[SelectedValues] and NormalizedOptions[1] then
                    SelectedValues = nil
                end
            end
            UpdateDisplay()
        end,
        SetDescription = function(self, NewDescription)
            local HadDescription = Description ~= nil and Description.Visible
            local HasNewDescription = NewDescription and NewDescription ~= ""
            if Description and NewDescription then
                Description.Text = NewDescription
                Description.Visible = true
            elseif Description and not NewDescription then
                Description.Visible = false
            elseif not Description and NewDescription then
                Description = EngProject.ComponentBuilder:CreateDescription(Zones.TextZone, NewDescription, Theme, 2)
                if Window then
                    EngProject.ThemeManager:RegisterElement(Window, Description, {
                        TextColor3 = "TextSecondary",
                        Font = "FontSecondary"
                    })
                end
            end
            if HadDescription ~= HasNewDescription then
                EngProject.ComponentBuilder:UpdateDescriptionPadding(Zones, HasNewDescription)
            end
        end,
        Close = function(self)
            CloseDropdown()
        end,
        GetElements = function(self)
            return {
                Container = Zones.Container,
                Label = Label,
                Description = Description,
                Display = Display,
                DisplayLabel = DisplayLabel,
                Arrow = Arrow,
                ListContainer = ListContainer,
                SearchBox = SearchBox,
                ScrollList = ScrollList
            }
        end,
        Changed = ChangedEvent.Event
    }
end

function EngProject:CreateNotification(Options)
    local EH = self.ErrorHandler
    Options = Options or {}
    if not EH:ValidateType(Options, "table", "Options", "CreateNotification") then
        Options = {}
    end

    local Title = Options.Title
    if not EH:ValidateType(Title, "string", "Title", "CreateNotification") then
        Title = "Notification"
    end

    local Description = Options.Description
    if Description and not EH:ValidateType(Description, "string", "Description", "CreateNotification") then
        Description = nil
    end

    local Duration = Options.Duration or 5
    if not EH:ValidateType(Duration, "number", "Duration", "CreateNotification") then
        Duration = 5
    else
        Duration = math.clamp(Duration, 0, 300)
    end

    local Tag = Options.Tag
    if Tag and not EH:ValidateType(Tag, "string", "Tag", "CreateNotification") then
        Tag = nil
    end

    local Type = Options.Type
    if Type and not EH:ValidateType(Type, "string", "Type", "CreateNotification") then
        Type = nil
    end

    local Theme = type(Options.Theme) == "string" and (self.Themes[Options.Theme] or self.Themes.DefaultTheme) or
                      type(Options.Theme) == "table" and Options.Theme or self.Themes.DefaultTheme

    local Color = Options.Color
    if Color and typeof(Color) ~= "Color3" then
        Color = Theme.Accent
    else
        Color = Color or Theme.Accent
    end

    local Callback = Options.Callback
    if Callback and not EH:ValidateType(Callback, "function", "Callback", "CreateNotification") then
        Callback = nil
    end

    local Closable = Options.Closable ~= false

    self.NotificationManager:Initialize()

    local NotificationUI = self.NotificationManager:CreateNotificationUI({
        Title = Title,
        Description = Description,
        Theme = Theme,
        Color = Color,
        Type = Type,
        Tag = Tag,
        Callback = Callback,
        Closable = Closable,
        Duration = Duration
    })

    return {
        Dismiss = function(self)
            EngProject.NotificationManager:Dismiss(NotificationUI.Container)
        end,
        SetTitle = function(self, NewTitle)
            if EH:ValidateType(NewTitle, "string", "NewTitle", "Notification:SetTitle") then
                NotificationUI.Title.Text = NewTitle
            end
        end,
        SetDescription = function(self, NewDescription)
            if NotificationUI.Description then
                if NewDescription and
                    EH:ValidateType(NewDescription, "string", "NewDescription", "Notification:SetDescription") then
                    NotificationUI.Description.Text = NewDescription
                    NotificationUI.Description.Visible = true
                else
                    NotificationUI.Description.Visible = false
                end
            end
        end,
        SetTag = function(self, NewTag)
            if EH:ValidateType(NewTag, "string", "NewTag", "Notification:SetTag") and NotificationUI.Tag then
                NotificationUI.Tag.Text = NewTag
            end
        end,
        GetElements = function(self)
            return {
                Container = NotificationUI.Container,
                Card = NotificationUI.Card,
                Title = NotificationUI.Title,
                Description = NotificationUI.Description,
                Tag = NotificationUI.Tag,
                Content = NotificationUI.Content,
                ProgressFill = NotificationUI.ProgressFill
            }
        end
    }
end

-- ================= VALIDATION =================

local TaskManagerMock = {
    _currentTask = nil,
    _nextTask = nil,
    _subTasks = {},
}
function TaskManagerMock:requestTask(name, priority) return true end
function TaskManagerMock:waitForTurn(name, timeout) return true end
function TaskManagerMock:startTask(name) self._currentTask = name; return true end
function TaskManagerMock:finishTask(name) if self._currentTask == name then self._currentTask = nil end end
function TaskManagerMock:setCurrentTask(name) self._currentTask = name end
function TaskManagerMock:getCurrentTask() return self._currentTask end
function TaskManagerMock:setNextTask(name) self._nextTask = name end
function TaskManagerMock:getNextTask() return self._nextTask end
function TaskManagerMock:getMainTask() return self._currentTask end
function TaskManagerMock:clearSubTasks() table.clear(self._subTasks) end
function TaskManagerMock:canRun(name) return true end

local ShoppingMartMock = {}
ShoppingMartMock.__index = ShoppingMartMock
function ShoppingMartMock.new(scale)
    return setmetatable({}, ShoppingMartMock)
end
function ShoppingMartMock:Toggle()
    pcall(function()
        local PlayerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
        local keywords = {"shop", "market", "amazong", "store", "buy", "merchant", "vendor", "toko", "mall"}
        local found = nil
        -- Scan all descendants of PlayerGui (not just direct children)
        for _, gui in ipairs(PlayerGui:GetDescendants()) do
            if gui:IsA("ScreenGui") or gui:IsA("Frame") or gui:IsA("ScrollingFrame") then
                local nameLower = gui.Name:lower()
                for _, kw in ipairs(keywords) do
                    if nameLower:find(kw) then
                        -- Hindari mencocokkan tombol atau template kecil
                        if not nameLower:find("button") and not nameLower:find("icon") and not nameLower:find("template") and not nameLower:find("item") then
                            found = gui
                            break
                        end
                    end
                end
            end
            if found then break end
        end
        if found then
            if found:IsA("ScreenGui") then
                found.Enabled = not found.Enabled
            else
                found.Visible = not found.Visible
            end
        else
            -- Fallback: toggle ScreenGui yang tersembunyi
            for _, gui in ipairs(PlayerGui:GetDescendants()) do
                if gui:IsA("ScreenGui") and not gui.Enabled and not gui.Name:find("EngProject") and not gui.Name:find("Roblox") then
                    gui.Enabled = true
                    return
                end
            end
        end
    end)
end

local function getStorage()
    local registry = getgenv().__PrereqStorageRegistry
    if not registry then
        return nil
    end

    for k, v in pairs(getgenv()) do
        if type(k) == "userdata" and v == true and registry[k] then
            return k
        end
    end
    return nil
end

local proxy = getStorage()
local TaskManager, ShoppingMart

if proxy then
    local storageRegistry = getgenv().__PrereqStorageRegistry
    local moduleRegistry = getgenv().__PrereqModuleRegistry
    if storageRegistry and moduleRegistry then
        local data = storageRegistry[proxy]
        local prereqs = data and data.Prereqs
        if prereqs and next(prereqs) then
            local function getPrerequisite(name)
                for p in pairs(prereqs) do
                    local info = moduleRegistry[p]
                    if info and info.name == name then
                        return info.module
                    end
                end
                return nil
            end
            TaskManager = getPrerequisite("TaskManager")
            ShoppingMart = getPrerequisite("ShoppingMart")
        end
    end
end

if not TaskManager then
    TaskManager = TaskManagerMock
end
if not ShoppingMart then
    ShoppingMart = ShoppingMartMock
end
-- ================= MAIN CODE =================

EngProject:CreateNotification({
    Title = "Validated!",
    Type = "Success",
    Description = "Pre-requisites validated, script will start soon! Powered by EngProject",
    Duration = 3
})

EngProject:CreateNotification({
    Title = "UI keybind",
    Type = "Info",
    Description = "Default UI visibility toggle is the Q button on PC",
    Duration = 10
})

local Services = {
    Players = EngProject.Utility:GetService("Players"),
    ReplicatedStorage = EngProject.Utility:GetService("ReplicatedStorage"),
    PathfindingService = EngProject.Utility:GetService("PathfindingService"),
    TeleportService = EngProject.Utility:GetService("TeleportService"),
    Workspace = EngProject.Utility:GetService("Workspace"),
    RunService = EngProject.Utility:GetService("RunService"),
    HttpService = EngProject.Utility:GetService("HttpService"),
    Lighting = EngProject.Utility:GetService("Lighting"),
    VirtualUser = EngProject.Utility:GetService("VirtualUser")
}

local Player = Services.Players.LocalPlayer
local Camera = Services.Workspace.CurrentCamera
local Characters = Services.Workspace:WaitForChild("Characters", 15)
local PlayerGui = Player:WaitForChild("PlayerGui", 15)
local BackpackTwo = Player:WaitForChild("BackpackTwo", 15)
local Map = Services.Workspace:WaitForChild("Map", 15)

local ReplicatedStorage = Services.ReplicatedStorage
local PanningAnimations = ReplicatedStorage.Assets.Animations.Panning
local Excavations = require(ReplicatedStorage.GameInfo.Excavations)
local CraftingRemotes = ReplicatedStorage.Remotes.Crafting

local Character, LocalCharacter, HumanoidRootPart, Humanoid, Animator, WashAnimation

local function bindCharacter(char)
    Character = char
    LocalCharacter = Characters:WaitForChild(Player.Name)
    Humanoid = char:WaitForChild("Humanoid")
    HumanoidRootPart = char:WaitForChild("HumanoidRootPart")
    Animator = Humanoid:WaitForChild("Animator")
    WashAnimation = Animator:LoadAnimation(PanningAnimations.Wash)
end

bindCharacter(Player.Character or Player.CharacterAdded:Wait())
Player.CharacterAdded:Connect(bindCharacter)


local Config = {
    GEODE_AUTO_LOOP_DELAY = 0.01,
    RUNE_AUTO_LOOP_DELAY = 1
}

local Utility = {}
do
    function Utility.createNotification(content, duration)
        EngProject:CreateNotification({
            Type = "Default",
            Title = "Notification",
            Description = content or "[DEBUG] TEST",
            Duration = duration or 5
        })
    end

    function Utility.formatPrice(price, isShardPrice)
        local symbol = isShardPrice and "ƒ" or "$"
        local suffixes = {{1e21, "Sx"}, {1e18, "Q"}, {1e15, "qd"}, {1e12, "T"}, {1e9, "B"}, {1e6, "M"}, {1e3, "K"}}

        for _, data in ipairs(suffixes) do
            if price >= data[1] then
                return string.format("%s%.1f%s", symbol, price / data[1], data[2])
            end
        end

        return symbol .. tostring(price)
    end

    function Utility.validateSellValue(str)
        if not str or str == "" then
            return nil, nil
        end

        local n, u = str:lower():match("^(%d+)%s*(%a*)$")
        n = tonumber(n)
        if not n then
            return nil, nil
        end
        u = (u or ""):gsub("s+$", "")

        local multipliers = {
            [""] = 1,
            s = 1,
            sec = 1,
            secs = 1,
            second = 1,
            seconds = 1,
            m = 60,
            min = 60,
            mins = 60,
            minute = 60,
            minutes = 60,
            h = 3600,
            hr = 3600,
            hrs = 3600,
            hour = 3600,
            hours = 3600,
            d = 86400,
            day = 86400,
            days = 86400
        }

        if u ~= "" then
            local seconds = n * (multipliers[u] or 0)
            if seconds >= 30 and seconds <= 86400 then
                return seconds, "time"
            end
            return nil, nil
        end

        if n >= 10 and n <= 2000 then
            return n, "value"
        end

        return nil, nil
    end

    function Utility.encodeJSON(value, indentLevel)
        indentLevel = indentLevel or 0
        local indent = string.rep("    ", indentLevel)
        local nextIndent = string.rep("    ", indentLevel + 1)

        if typeof(value) == "table" then
            local isArray = (#value > 0)
            local buffer = {}

            if isArray then
                table.insert(buffer, "[")
                for i, v in ipairs(value) do
                    table.insert(buffer,
                        nextIndent .. Utility.encodeJSON(v, indentLevel + 1) .. (i < #value and "," or ""))
                end
                table.insert(buffer, indent .. "]")
            else
                table.insert(buffer, "{")
                local keys = {}
                for k in pairs(value) do
                    table.insert(keys, k)
                end
                table.sort(keys, function(a, b)
                    return tostring(a) < tostring(b)
                end)

                for i, k in ipairs(keys) do
                    local v = value[k]
                    local keyStr = ("%q"):format(tostring(k))
                    local entry = nextIndent .. keyStr .. ": " .. Utility.encodeJSON(v, indentLevel + 1)
                    if i < #keys then
                        entry = entry .. ","
                    end
                    table.insert(buffer, entry)
                end
                table.insert(buffer, indent .. "}")
            end

            return table.concat(buffer, "\n")
        elseif typeof(value) == "string" then
            return ("%q"):format(value)
        elseif typeof(value) == "boolean" or typeof(value) == "number" then
            return tostring(value)
        elseif value == nil then
            return "null"
        else
            return ("%q"):format("<unsupported>")
        end
    end
end

local PanModule = {}
do
    function PanModule.equipPan()
        local function findPan(container)
            for _, v in ipairs(container:GetChildren()) do
                if v:GetAttribute("ItemType") == "Pan" then
                    return v
                end
            end
        end

        local pan = findPan(Character) or findPan(Player.Backpack) or findPan(BackpackTwo)
        if pan then
            ReplicatedStorage.Remotes.CustomBackpack.EquipRemote:FireServer(pan)
            return pan
        end
        return nil
    end

    function PanModule.getStatus()
        local ToolUI = PlayerGui:WaitForChild("ToolUI")
        local FillingPan = ToolUI:WaitForChild("FillingPan")
        local FillText = FillingPan:WaitForChild("FillText")

        local function getDefaultStatus()
            return {
                current = 0,
                max = 100,
                isFull = false,
                isEmpty = true
            }
        end

        local function cleanAndParseNumber(raw, fallback)
            if not raw then
                return fallback
            end
            local cleaned = string.gsub(string.gsub(string.gsub(tostring(raw), ",", ""), " ", ""), "%s+", ""):lower()
            if cleaned == "" then
                return fallback
            end
            local multiplier = 1
            if string.find(cleaned, "k") then
                multiplier = 1000
                cleaned = string.gsub(cleaned, "k", "")
            elseif string.find(cleaned, "m") then
                multiplier = 1000000
                cleaned = string.gsub(cleaned, "m", "")
            elseif string.find(cleaned, "b") then
                multiplier = 1000000000
                cleaned = string.gsub(cleaned, "b", "")
            elseif string.find(cleaned, "t") then
                multiplier = 1000000000000
                cleaned = string.gsub(cleaned, "t", "")
            end
            local parsed = tonumber(cleaned)
            return parsed and math.max(0, math.floor(parsed * multiplier)) or fallback
        end

        if not FillText or not FillText.ContentText then
            return getDefaultStatus()
        end

        local contentText = tostring(FillText.ContentText)
        if contentText == "" then
            return getDefaultStatus()
        end

        local fillNumbers = string.split(contentText, "/")
        if not fillNumbers or #fillNumbers < 2 then
            return getDefaultStatus()
        end

        local current = cleanAndParseNumber(fillNumbers[1], 0)
        local max = math.max(1, cleanAndParseNumber(fillNumbers[2], 100))

        return {
            current = current,
            max = max,
            isFull = current >= max,
            isEmpty = current <= 0
        }
    end

    function PanModule.getRegion(rootPart)
        local PointToRegion = require(ReplicatedStorage.Modules.Location.PointToRegion)
        local region, _ = PointToRegion.GetPanningRegion(rootPart.Position)
        return region
    end

    function PanModule.handleAction(mode, actionType, executeToCompletion, killSwitch)
        executeToCompletion = executeToCompletion or false

        local function validatePan()
            local pan = PanModule.equipPan()
            local folder = pan and pan:FindFirstChild("Scripts")
            if not folder then
                Utility.createNotification("No Pan found.")
                return nil
            end

            local scripts = {}
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("RemoteFunction") or child:IsA("RemoteEvent") then
                    scripts[child.Name] = child
                end
            end

            if next(scripts) then
                return scripts
            else
                Utility.createNotification("Pan has no scripts.")
                return nil
            end
        end

        local function isInValidRegion(forWhat)
            return true
        end

        local function shakeUntilNotPanning(shakeScript, killSwitch)
            while LocalCharacter:GetAttribute("Panning") do
                if killSwitch and not killSwitch() then
                    return false
                end
                pcall(function()
                    shakeScript:FireServer()
                end)
                task.wait()
            end
            return true
        end

        local function fillToCompletion(collectScript)
            local scripts = validatePan()
            local shakeScript = scripts and scripts.Shake

            while task.wait() do
                if killSwitch and not killSwitch() then
                    return "KILLED"
                end

                if LocalCharacter:GetAttribute("Panning") then
                    if shakeScript and not shakeUntilNotPanning(shakeScript, killSwitch) then
                        return "KILLED"
                    end
                end

                local status = PanModule.getStatus()
                if status and status.isFull then
                    break
                end

                if not isInValidRegion("Deposit") then
                    break
                end

                pcall(function()
                    collectScript:InvokeServer()
                end)
                task.wait(0.25)
                pcall(function()
                    collectScript:InvokeServer(0)
                end)
            end

            return (not killSwitch or killSwitch()) and "SUCCESS" or "KILLED"
        end

        local function executeSingle(collectScript)
            if killSwitch and not killSwitch() then
                return "KILLED"
            end
            pcall(function()
                collectScript:InvokeServer()
            end)
            task.wait(0.25)
            pcall(function()
                collectScript:InvokeServer(0)
            end)
            return "SUCCESS"
        end

        local function emptyToCompletion(shakeScript)
            while task.wait() do
                if killSwitch and not killSwitch() then
                    WashAnimation:Stop()
                    return "KILLED"
                end

                if not shakeUntilNotPanning(shakeScript, killSwitch) then
                    WashAnimation:Stop()
                    return "KILLED"
                end

                local status = PanModule.getStatus()
                if not status or status.isEmpty then
                    break
                end

                pcall(function()
                    shakeScript:FireServer()
                end)
            end

            WashAnimation:Stop()
            return (not killSwitch or killSwitch()) and "SUCCESS" or "KILLED"
        end

        local handlers = {
            Dig = function()
                if killSwitch and not killSwitch() then
                    return "KILLED"
                end

                local scripts = validatePan()
                if not scripts then
                    return "FAIL"
                end

                local collectScript = scripts.Collect
                if not collectScript then
                    return "FAIL"
                end

                local status = PanModule.getStatus()
                if status and status.isFull then
                    return "SUCCESS"
                end

                if mode == "Legit" then
                    Utility.createNotification("Legit mode is Work In Progress!")
                    return "FAIL"
                elseif mode == "Instant" then
                    if executeToCompletion then
                        return fillToCompletion(collectScript)
                    else
                        return executeSingle(collectScript)
                    end
                end

                return "FAIL"
            end,

            Wash = function()
                if killSwitch and not killSwitch() then
                    return "KILLED"
                end

                local scripts = validatePan()
                if not scripts then
                    return "FAIL"
                end

                local shakeScript = scripts.Shake
                local panScript = scripts.Pan

                if not shakeScript or not panScript then
                    return "FAIL"
                end

                local status = PanModule.getStatus()
                if status and status.isEmpty then
                    return "SUCCESS"
                end

                pcall(function()
                    panScript:InvokeServer()
                end)

                return emptyToCompletion(shakeScript)
            end
        }

        local handler = handlers[actionType]
        if not handler then
            Utility.createNotification("Invalid action type! Use 'Dig' or 'Wash'.")
            return "FAIL"
        end

        local ok, result = pcall(handler)
        if not ok then
            warn("PanAction failed: " .. tostring(result))
            return "FAIL"
        end

        return result or "SUCCESS"
    end
end

Movement = {}
do
    function Movement.tweenToTarget(target, config)
        local player = Services.Players.LocalPlayer
        local character = player.Character or player.CharacterAdded:Wait()
        local hrp = character:WaitForChild("HumanoidRootPart")
        local humanoid = character:WaitForChild("Humanoid")

        config = config or {}
        local offset = config.Offset or Vector3.new(0, 0, 0)
        local stopDist = config.StopDistance or 20
        local speed = config.Speed or 24
        local cruiseHeight = config.CruiseHeight or 25
        local minHeight = config.MinHeight or 15
        local maxHeight = config.MaxHeight or 100
        local agentRadius = config.AgentRadius or 3
        local longDistanceThreshold = config.LongDistanceThreshold or 150
        local directFlightThreshold = config.DirectFlightThreshold or 50
        local waypointDistance = config.WaypointDistance or 12
        local smoothness = config.Smoothness or 0.5
        local landingDuration = config.LandingDuration or 1.2
        local hoverDuration = config.HoverDuration or 0.3
        local pathTimeout = config.PathTimeout or 8
        local maxTimeout = config.MaxTimeout or 45
        local adaptiveHeight = config.AdaptiveHeight ~= false
        local useDirectFlight = config.UseDirectFlight ~= false

        local isActive = true
        local waypoints = {}
        local currentWaypointIndex = 1
        local lastWaypointTime = tick()
        local startTime = tick()
        local isLanding = false
        local currentHeight = cruiseHeight
        local bg, bv, bp
        local originalPlatformStand

        local TweenService = EngProject.Utility:GetService("TweenService")

        local function setNoclip(state)
            for _, v in pairs(character:GetDescendants()) do
                if v:IsA("BasePart") then
                    v.CanCollide = not state
                end
            end

            if humanoid then
                if state then
                    originalPlatformStand = humanoid.PlatformStand
                    humanoid.PlatformStand = true
                else
                    if originalPlatformStand ~= nil then
                        humanoid.PlatformStand = originalPlatformStand
                    end
                end
            end
        end

        local function cleanup()
            isActive = false
            if bg then
                bg:Destroy()
            end
            if bv then
                bv:Destroy()
            end
            if bp then
                bp:Destroy()
            end
            setNoclip(false)
            if humanoid and originalPlatformStand ~= nil then
                humanoid.PlatformStand = originalPlatformStand
            end
        end

        local function toVector3(t)
            if typeof(t) == "Vector3" then
                return t
            elseif typeof(t) == "Instance" and t:IsA("BasePart") then
                return t.Position
            elseif typeof(t) == "CFrame" then
                return t.Position
            elseif typeof(t) == "table" then
                if t.Position then
                    return t.Position
                elseif t.X and t.Y and t.Z then
                    return Vector3.new(t.X, t.Y, t.Z)
                end
            end
            error("Invalid target type")
        end

        local function getOptimalHeight(position, targetPos)
            if not adaptiveHeight then
                return currentHeight
            end

            local distance = (targetPos - position).Magnitude
            local terrainHeight = 0

            local rayParams = RaycastParams.new()
            rayParams.FilterDescendantsInstances = {character}
            rayParams.FilterType = Enum.RaycastFilterType.Blacklist

            local result = Services.Workspace:Raycast(position, Vector3.new(0, -200, 0), rayParams)
            if result then
                terrainHeight = result.Position.Y
            end

            local baseHeight = math.max(minHeight, terrainHeight + 10)

            if distance > longDistanceThreshold then
                return math.min(maxHeight, baseHeight + 30)
            elseif distance > 75 then
                return math.min(cruiseHeight + 15, baseHeight + 20)
            else
                return math.min(cruiseHeight, baseHeight + 15)
            end
        end

        local function hasObstaclesBetween(start, destination, checkHeight)
            local direction = (destination - start)
            local distance = direction.Magnitude
            local unit = direction.Unit

            local rayParams = RaycastParams.new()
            rayParams.FilterDescendantsInstances = {character}
            rayParams.FilterType = Enum.RaycastFilterType.Blacklist

            local checkPoints = math.max(3, math.floor(distance / 10))

            for i = 1, checkPoints do
                local checkPos = start + unit * (distance * i / checkPoints)
                checkPos = Vector3.new(checkPos.X, checkPos.Y + checkHeight, checkPos.Z)

                local directions = {Vector3.new(0, 0, 0), Vector3.new(agentRadius, 0, 0),
                                    Vector3.new(-agentRadius, 0, 0), Vector3.new(0, 0, agentRadius),
                                    Vector3.new(0, 0, -agentRadius), Vector3.new(0, agentRadius, 0),
                                    Vector3.new(0, -agentRadius, 0)}

                for _, dir in pairs(directions) do
                    local testPos = checkPos + dir
                    local result = Services.Workspace:Raycast(testPos, Vector3.new(0, -checkHeight - 10, 0), rayParams)
                    if result and result.Position.Y > testPos.Y - 5 then
                        return true
                    end

                    local ceilingResult = Services.Workspace:Raycast(testPos, Vector3.new(0, 10, 0), rayParams)
                    if ceilingResult and ceilingResult.Position.Y < testPos.Y + 6 then
                        return true
                    end

                    local forwardRay = Services.Workspace:Raycast(testPos, unit * 10, rayParams)
                    if forwardRay then
                        return true
                    end
                end
            end

            return false
        end

        local function canDirectFly(start, destination)
            if not useDirectFlight then
                return false
            end

            local distance = (destination - start).Magnitude
            if distance > directFlightThreshold then
                return false
            end

            return not hasObstaclesBetween(start, destination, currentHeight)
        end

        local function createPath(destination)
            local startPos = hrp.Position
            local targetPos = destination

            currentHeight = getOptimalHeight(startPos, targetPos)

            if canDirectFly(startPos, targetPos) then
                return {{
                    Position = startPos
                }, {
                    Position = Vector3.new(targetPos.X, targetPos.Y + currentHeight, targetPos.Z),
                    Action = Enum.PathWaypointAction.Walk
                }}
            end

            local groundStart = Vector3.new(startPos.X, startPos.Y, startPos.Z)
            local groundTarget = Vector3.new(targetPos.X, targetPos.Y, targetPos.Z)

            local path = Services.PathfindingService:CreatePath({
                AgentRadius = agentRadius,
                AgentHeight = 6,
                AgentCanJump = false,
                AgentCanClimb = false,
                WaypointSpacing = math.max(8, waypointDistance),
                Costs = {
                    Danger = math.huge
                }
            })

            local success, err = pcall(function()
                path:ComputeAsync(groundStart, groundTarget)
            end)

            if success and path.Status == Enum.PathStatus.Success then
                local pathWaypoints = path:GetWaypoints()
                local modifiedWaypoints = {}

                for i, waypoint in ipairs(pathWaypoints) do
                    local elevatedPos = Vector3.new(waypoint.Position.X, waypoint.Position.Y + currentHeight,
                        waypoint.Position.Z)
                    table.insert(modifiedWaypoints, {
                        Position = elevatedPos,
                        Action = waypoint.Action
                    })
                end

                return modifiedWaypoints
            else
                local direction = (targetPos - startPos)
                local distance = direction.Magnitude
                local unit = direction.Unit

                local fallbackWaypoints = {}
                table.insert(fallbackWaypoints, {
                    Position = startPos,
                    Action = Enum.PathWaypointAction.Walk
                })

                local midPoint = startPos + unit * (distance * 0.5)
                local highMidPoint = Vector3.new(midPoint.X, midPoint.Y + currentHeight + 20, midPoint.Z)
                table.insert(fallbackWaypoints, {
                    Position = highMidPoint,
                    Action = Enum.PathWaypointAction.Walk
                })

                table.insert(fallbackWaypoints, {
                    Position = Vector3.new(targetPos.X, targetPos.Y + currentHeight, targetPos.Z),
                    Action = Enum.PathWaypointAction.Walk
                })

                return fallbackWaypoints
            end
        end

        local function initializePhysics()
            bg = Instance.new("BodyGyro")
            bg.MaxTorque = Vector3.new(4000, 4000, 4000)
            bg.P = 3000
            bg.D = 500
            bg.CFrame = hrp.CFrame
            bg.Parent = hrp

            bv = Instance.new("BodyVelocity")
            bv.MaxForce = Vector3.new(4000, 4000, 4000)
            bv.Velocity = Vector3.new(0, 0, 0)
            bv.Parent = hrp

            bp = Instance.new("BodyPosition")
            bp.MaxForce = Vector3.new(4000, 4000, 4000)
            bp.P = 3000
            bp.D = 500
            bp.Position = hrp.Position + Vector3.new(0, currentHeight, 0)
            bp.Parent = hrp
        end

        local function performLanding(targetPos)
            if isLanding then
                return
            end
            isLanding = true

            local rayParams = RaycastParams.new()
            rayParams.FilterDescendantsInstances = {character}
            rayParams.FilterType = Enum.RaycastFilterType.Blacklist

            local groundResult = Services.Workspace:Raycast(targetPos, Vector3.new(0, -200, 0), rayParams)
            local landingY = groundResult and groundResult.Position.Y + 3 or targetPos.Y

            local hoverPos = Vector3.new(targetPos.X, targetPos.Y + 8, targetPos.Z)
            bp.Position = hoverPos
            task.wait(hoverDuration)

            local finalPos = Vector3.new(targetPos.X, landingY, targetPos.Z)

            local landingTween = TweenService:Create(bp, TweenInfo.new(landingDuration, Enum.EasingStyle.Quart,
                Enum.EasingDirection.Out), {
                Position = finalPos
            })

            local velocityTween = TweenService:Create(bv, TweenInfo.new(landingDuration * 0.8, Enum.EasingStyle.Quart,
                Enum.EasingDirection.Out), {
                Velocity = Vector3.new(0, 0, 0)
            })

            landingTween:Play()
            velocityTween:Play()

            landingTween.Completed:Connect(function()
                task.wait(0.3)
                setNoclip(false)
                hrp.Velocity = Vector3.new(0, 0, 0)
            end)
        end

        local function updatePath(destination)
            waypoints = createPath(destination)
            currentWaypointIndex = 1
            lastWaypointTime = tick()
            return waypoints ~= nil
        end

        local function detectObstacles(position, direction, distance)
            local rayParams = RaycastParams.new()
            rayParams.FilterDescendantsInstances = {character}
            rayParams.FilterType = Enum.RaycastFilterType.Blacklist

            local obstacles = {}
            local checkDistance = math.min(distance, 10)

            local rayDirections = {direction, direction:Cross(Vector3.new(0, 1, 0)).Unit * 0.3 + direction * 0.954,
                                   direction:Cross(Vector3.new(0, -1, 0)).Unit * 0.3 + direction * 0.954}

            for i, rayDir in pairs(rayDirections) do
                local result = Services.Workspace:Raycast(position, rayDir * checkDistance, rayParams)
                if result and result.Distance > 2 then
                    table.insert(obstacles, {
                        position = result.Position,
                        normal = result.Normal,
                        distance = result.Distance,
                        direction = i
                    })
                end
            end

            local upwardRay = Services.Workspace:Raycast(position, Vector3.new(0, 10, 0), rayParams)
            if upwardRay and upwardRay.Distance < 8 then
                table.insert(obstacles, {
                    position = upwardRay.Position,
                    normal = upwardRay.Normal,
                    distance = upwardRay.Distance,
                    direction = "ceiling"
                })
            end

            return obstacles
        end

        local function calculateAvoidanceVector(obstacles, currentDirection)
            if #obstacles == 0 then
                return Vector3.new(0, 0, 0)
            end

            local avoidanceVector = Vector3.new(0, 0, 0)
            local totalWeight = 0

            for _, obstacle in pairs(obstacles) do
                if obstacle.distance < 2 then
                    local weight = (2 - obstacle.distance) / 6
                    weight = weight * 0.3

                    local pushDirection = obstacle.normal
                    if obstacle.direction == "ceiling" then
                        pushDirection = Vector3.new(0, -1, 0)
                    elseif pushDirection.Y < 0.2 then
                        pushDirection = pushDirection + Vector3.new(0, 0.4, 0)
                        pushDirection = pushDirection.Unit
                    end

                    avoidanceVector = avoidanceVector + (pushDirection * weight)
                    totalWeight = totalWeight + weight
                end
            end

            if totalWeight > 0 then
                avoidanceVector = avoidanceVector / totalWeight
                avoidanceVector = avoidanceVector * math.min(0.4, totalWeight)
            end

            return avoidanceVector
        end

        local function moveToWaypoint(waypoint)
            local currentPos = hrp.Position
            local targetPos = waypoint.Position
            local direction = (targetPos - currentPos)
            local distance = direction.Magnitude

            if distance <= waypointDistance then
                currentWaypointIndex = currentWaypointIndex + 1
                lastWaypointTime = tick()
                return true
            end

            local baseDirection = direction.Unit
            local obstacles = detectObstacles(currentPos, baseDirection, distance)
            local avoidanceVector = calculateAvoidanceVector(obstacles, baseDirection)

            local finalDirection = baseDirection + avoidanceVector
            finalDirection = finalDirection.Unit

            local velocity = finalDirection * speed
            local currentVel = bv.Velocity
            local smoothedVel = currentVel:lerp(velocity, smoothness)

            bv.Velocity = smoothedVel
            bp.Position = Vector3.new(targetPos.X, targetPos.Y, targetPos.Z)

            local lookDirection = Vector3.new(smoothedVel.X, 0, smoothedVel.Z)
            if lookDirection.Magnitude > 0.1 then
                local targetCFrame = CFrame.lookAt(currentPos, currentPos + lookDirection)
                bg.CFrame = bg.CFrame:lerp(targetCFrame, smoothness)
            end

            return false
        end

        local finalTarget = toVector3(target) + offset

        initializePhysics()
        setNoclip(true)

        if not updatePath(finalTarget) then
            cleanup()
            if config.OnComplete then
                config.OnComplete(false, "Initial pathfinding failed")
            end
            return
        end

        local conn = Services.RunService.Heartbeat:Connect(function()
            if not isActive then
                return
            end

            if typeof(target) == "Instance" and target:IsA("BasePart") then
                local newTarget = target.Position + offset
                if (newTarget - finalTarget).Magnitude > 10 then
                    finalTarget = newTarget
                    updatePath(finalTarget)
                end
            end

            local currentPos = hrp.Position
            local distToTarget = (finalTarget - currentPos).Magnitude

            if distToTarget <= stopDist then
                performLanding(finalTarget)
                task.wait(landingDuration + hoverDuration)
                cleanup()
                if config.OnComplete then
                    config.OnComplete(true, "Target reached successfully")
                end
                return
            end

            if tick() - startTime > maxTimeout then
                cleanup()
                if config.OnComplete then
                    config.OnComplete(false, "Maximum timeout exceeded")
                end
                return
            end

            if tick() - lastWaypointTime > pathTimeout then
                if not updatePath(finalTarget) then
                    cleanup()
                    if config.OnComplete then
                        config.OnComplete(false, "Path recalculation failed")
                    end
                    return
                end
            end

            if currentWaypointIndex <= #waypoints then
                moveToWaypoint(waypoints[currentWaypointIndex])
            else
                if distToTarget > stopDist then
                    if not updatePath(finalTarget) then
                        local direction = (finalTarget - currentPos).Unit
                        bv.Velocity = bv.Velocity:lerp(direction * speed, smoothness)
                        bp.Position = finalTarget + Vector3.new(0, currentHeight, 0)
                    end
                end
            end
        end)

        return {
            connection = conn,
            stop = function()
                cleanup()
            end,
            setSpeed = function(newSpeed)
                speed = math.max(5, math.min(50, newSpeed))
            end,
            setTarget = function(newTarget)
                target = newTarget
                finalTarget = toVector3(newTarget) + offset
                updatePath(finalTarget)
            end,
            getProgress = function()
                if #waypoints == 0 then
                    return 0
                end
                return math.min(1, currentWaypointIndex / #waypoints)
            end,
            getCurrentHeight = function()
                return currentHeight
            end,
            getDistanceRemaining = function()
                return (finalTarget - hrp.Position).Magnitude
            end,
            getETA = function()
                local distance = (finalTarget - hrp.Position).Magnitude
                return distance / speed
            end,
            isActive = function()
                return isActive
            end,
            pause = function()
                if bv then
                    bv.Velocity = Vector3.new(0, 0, 0)
                end
            end,
            resume = function()
            end,
            result = (hrp.Position - finalTarget).Magnitude <= stopDist
        }
    end

    function Movement.pathfindTween(target, config)
        config = config or {}
        local character = Player.Character or Player.CharacterAdded:Wait()
        local hrp = character and character:WaitForChild("HumanoidRootPart", 10)
        local humanoid = character and character:WaitForChild("Humanoid", 10)
        if not hrp or not humanoid then
            return false
        end

        local targetPos
        if typeof(target) == "Vector3" then
            targetPos = target
        elseif typeof(target) == "CFrame" then
            targetPos = target.Position
        elseif typeof(target) == "Instance" and target:IsA("BasePart") then
            targetPos = target.Position
        elseif typeof(target) == "table" and target.Position then
            targetPos = target.Position
        else
            targetPos = target
        end

        if not targetPos or typeof(targetPos) ~= "Vector3" then
            return false
        end

        local speed = config.Speed or State.Speed or 24
        local stopDist = config.StopDistance or 4
        local shouldContinue = config.ShouldContinue or function() return true end
        local onUpdate = config.OnUpdate

        local startPos = hrp.Position
        local distance = (startPos - targetPos).Magnitude

        if distance <= stopDist then
            return true
        end

        local PathfindingService = EngProject.Utility:GetService("PathfindingService")
        local TweenService = EngProject.Utility:GetService("TweenService")
        local RunService = EngProject.Utility:GetService("RunService")

        local path
        if PathfindingService then
            pcall(function()
                path = PathfindingService:CreatePath({
                    AgentRadius = 2,
                    AgentHeight = 5,
                    AgentCanJump = true,
                    WaypointSpacing = 4
                })
            end)
        end

        local success = false
        if path then
            success = pcall(function()
                path:ComputeAsync(startPos, targetPos)
            end)
        end

        local waypoints = {}
        if success and path and path.Status == Enum.PathStatus.Success then
            waypoints = path:GetWaypoints()
        else
            waypoints = {
                { Position = targetPos }
            }
        end

        local originalPlatformStand = humanoid.PlatformStand
        humanoid.PlatformStand = true

        local noclipConnection
        if RunService then
            noclipConnection = RunService.Stepped:Connect(function()
                if character then
                    for _, v in ipairs(character:GetDescendants()) do
                        if v:IsA("BasePart") then
                            v.CanCollide = false
                        end
                    end
                end
            end)
        end

        local tweenSuccess = true
        for idx, waypoint in ipairs(waypoints) do
            if not shouldContinue() then
                tweenSuccess = false
                break
            end

            local wpPos = waypoint.Position
            local lookAt = Vector3.new(wpPos.X, hrp.Position.Y, wpPos.Z)
            local targetWP_CFrame
            if (lookAt - hrp.Position).Magnitude > 0.1 then
                targetWP_CFrame = CFrame.lookAt(hrp.Position, lookAt)
                targetWP_CFrame = CFrame.new(wpPos) * (targetWP_CFrame - targetWP_CFrame.Position)
            else
                targetWP_CFrame = CFrame.new(wpPos) * (hrp.CFrame - hrp.CFrame.Position)
            end

            local dist = (hrp.Position - wpPos).Magnitude
            local duration = dist / speed
            if duration > 0 and TweenService then
                local tween = TweenService:Create(hrp, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = targetWP_CFrame})
                tween:Play()

                while tween.PlaybackState == Enum.PlaybackState.Playing and shouldContinue() do
                    if typeof(onUpdate) == "function" then
                        onUpdate((hrp.Position - targetPos).Magnitude)
                    end
                    task.wait(0.02)
                end

                if tween.PlaybackState == Enum.PlaybackState.Playing then
                    tween:Cancel()
                    tweenSuccess = false
                    break
                end
            elseif duration > 0 then
                hrp.CFrame = targetWP_CFrame
                task.wait(duration)
            end
        end

        if noclipConnection then
            noclipConnection:Disconnect()
        end

        for _, v in ipairs(character:GetDescendants()) do
            if v:IsA("BasePart") then
                v.CanCollide = true
            end
        end

        if humanoid and originalPlatformStand ~= nil then
            humanoid.PlatformStand = originalPlatformStand
        end

        return tweenSuccess and (hrp.Position - targetPos).Magnitude <= (stopDist + 5)
    end

    function Movement.walkToTarget(target, config)
        config = config or {}
        local character = Player.Character or Player.CharacterAdded:Wait()
        local hrp = character:WaitForChild("HumanoidRootPart")
        local humanoid = character:WaitForChild("Humanoid")
        local route = config.Route or {target.Position or target}
        local stopDist = config.StopDistance or 5
        local shouldContinue = config.ShouldContinue or function()
            return true
        end

        for _, point in ipairs(route) do
            if not shouldContinue() then
                return false
            end

            local position
            if typeof(point) == "Vector3" then
                position = point
            elseif typeof(point) == "CFrame" then
                position = point.Position
            elseif typeof(point) == "table" and point.Position then
                position = point.Position
            end

            if position then
                local done = false
                local reached = false
                local connection
                connection = humanoid.MoveToFinished:Connect(function(ok)
                    reached = ok
                    done = true
                end)

                humanoid:MoveTo(position)

                local timeout = math.max(6, (hrp.Position - position).Magnitude / math.max(humanoid.WalkSpeed, 8) + 4)
                local elapsed = 0
                while not done and elapsed < timeout and shouldContinue() do
                    if (hrp.Position - position).Magnitude <= stopDist then
                        reached = true
                        break
                    end
                    task.wait(0.1)
                    elapsed = elapsed + 0.1
                end

                if connection then
                    connection:Disconnect()
                end

                if not shouldContinue() or not reached then
                    return false
                end
            end
        end

        return true
    end

    function Movement.teleportToTarget(target, options)
        local character = Player.Character or Player.CharacterAdded:Wait()
        local hrp = character:WaitForChild("HumanoidRootPart")

        local targetPos
        if typeof(target) == "Vector3" then
            targetPos = target
        elseif typeof(target) == "Instance" and target:IsA("BasePart") then
            targetPos = target.Position
        else
            error("Invalid target type")
        end

        options = options or {}
        local mode = options.Mode or "Standard"
        local fireRemoteFunc = options.FireRemoteFunc
        local timeout = options.Timeout or 10
        local tpWaitTime = options.TeleportWaitTime or 0.03
        local maxFiresPerTeleport = options.MaxFiresPerTeleport or 10
        local offsetRange = options.OffsetRange or 0.25
        local exitDelay = options.ExitDelay or 0.2
        local onComplete = options.OnComplete
        local rubberBandTolerance = options.RubberBandTolerance or 12
        local rubberBandWaitTime = options.RubberBandWaitTime or 0.3

        local success = false

        local function handleRubberBand(expectedPos)
            local currentPos = hrp.Position
            local distance = (currentPos - expectedPos).Magnitude

            if distance > rubberBandTolerance then
                if (currentPos - expectedPos).Magnitude > 350 then
                    EngProject:CreateNotification({
                        Type = "Default",
                        Title = "Notification",
                        Description = "Distance is too long, try again while being closer to the target",
                        Duration = 10
                    })
                    return false
                end

                local tweenConfig = {
                    CruiseHeight = 6,
                    MinHeight = 1,
                    MaxHeight = 10,
                    LongDistanceThreshold = 150,
                    DirectFlightThreshold = 50,
                    AdaptiveHeight = true,
                    UseDirectFlight = true,
                    HoverDuration = 0,
                    LandingDuration = 1.2,
                    StopDistance = 10,
                    OnComplete = function(tweenSuccess, message)
                        if typeof(onComplete) == "function" then
                            onComplete(tweenSuccess)
                        end
                    end
                }

                Movement.tweenToTarget(expectedPos, tweenConfig)
                return true
            end

            return false
        end

        if mode == "Standard" then
            local maxAttempts = 10
            local tolerance = 10

            for attempt = 1, maxAttempts do
                hrp.CFrame = CFrame.new(targetPos)
                local startTime = tick()
                local settled = false

                task.wait(rubberBandWaitTime)
                if handleRubberBand(targetPos) then
                    return true
                end

                while tick() - startTime < 1 do
                    task.wait(0.05)
                    local distance = (hrp.Position - targetPos).Magnitude

                    if distance <= tolerance then
                        local stableStart = tick()
                        local stable = true

                        while tick() - stableStart < 0.2 do
                            task.wait(0.05)
                            if (hrp.Position - targetPos).Magnitude > tolerance then
                                if handleRubberBand(targetPos) then
                                    return true
                                end
                                stable = false
                                break
                            end
                        end

                        if stable then
                            settled = true
                            success = true
                            break
                        end
                    end
                end

                if success then
                    break
                end
                if attempt < maxAttempts then
                    task.wait(0.2)
                end
            end

            if success then
                task.wait(rubberBandWaitTime)
                if handleRubberBand(targetPos) then
                    return true
                end
            end

        elseif mode == "Critical" then
            if typeof(fireRemoteFunc) ~= "function" then
                error("Critical mode requires FireRemoteFunc")
            end

            local originalPos = hrp.Position
            local startTime = tick()
            local remoteRunning = true

            local remoteThread = task.spawn(function()
                while task.wait() do
                    local ok, result = pcall(fireRemoteFunc)
                    if ok and typeof(result) == "number" and result > 0 then
                        success = true
                        hrp.CFrame = CFrame.new(originalPos)
                        break
                    end
                end
            end)

            while tick() - startTime < timeout and not success do
                for i = 1, 15 do
                    if success then
                        break
                    end

                    local offset = Vector3.new(math.random() * offsetRange - offsetRange / 2, math.random(5, 10),
                        math.random() * offsetRange - offsetRange / 2)

                    hrp.CFrame = CFrame.new(targetPos + offset)
                    task.wait()
                end

                hrp.CFrame = CFrame.new(originalPos)
                task.wait(1)
            end

            if remoteThread then
                task.cancel(remoteThread)
            end

            hrp.CFrame = CFrame.new(originalPos)
        end

        if typeof(onComplete) == "function" then
            onComplete(success)
        end

        return success
    end
end

local CharacterLock = {}
do
    local storedValues = {}

    function CharacterLock.lock(targetCFrame)
        local char = Player.Character
        if not char then
            return
        end

        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then
            return
        end

        hrp.CFrame = targetCFrame
        hrp.Velocity = Vector3.new(0, 0, 0)
        hrp.RotVelocity = Vector3.new(0, 0, 0)

        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            storedValues[Player.UserId] = {
                WalkSpeed = hum.WalkSpeed,
                JumpPower = hum.JumpPower
            }

            hum.WalkSpeed = 0
            hum.JumpPower = 0
            hum:ChangeState(Enum.HumanoidStateType.Seated)
        end
    end

    function CharacterLock.unlock()
        local char = Player.Character
        if not char then
            return
        end

        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            local values = storedValues[Player.UserId] or {
                WalkSpeed = 16,
                JumpPower = 50
            }

            hum.WalkSpeed = values.WalkSpeed
            hum.JumpPower = values.JumpPower
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            storedValues[Player.UserId] = nil
        end
    end
end

local MerchantModule = {}
do
    function MerchantModule.isMerchant(npc)
        local imgPass = false
        local icon = npc:FindFirstChild("IconUI")
        local img = icon and icon:FindFirstChild("ImageLabel")
        if img and img.Image == "rbxassetid://2246496691" then
            imgPass = true
        end

        local objPass = false
        local dialog = npc:FindFirstChild("Dialog")
        if dialog and dialog.ClassName == "ObjectValue" and dialog.Value and dialog.Value.Name == "Seller" then
            objPass = true
        end

        return imgPass and objPass
    end

    function MerchantModule.getClosest()
        local NPCs = Services.Workspace:WaitForChild("NPCs")
        local char = Player.Character
        local playerHrp = char and char:FindFirstChild("HumanoidRootPart")
        if not playerHrp then
            return nil, math.huge
        end

        local closest, closestDist = nil, math.huge

        for _, folder in ipairs(NPCs:GetChildren()) do
            for _, npc in ipairs(folder:GetChildren()) do
                if MerchantModule.isMerchant(npc) and npc:FindFirstChild("HumanoidRootPart") then
                    local hrp = npc.HumanoidRootPart
                    local dist = (playerHrp.Position - hrp.Position).Magnitude
                    if dist < closestDist then
                        closestDist = dist
                        closest = hrp
                    end
                end
            end
        end

        return closest, closestDist
    end

    function MerchantModule.getSellPosition(merchantHrp, options)
        options = options or {}
        if not merchantHrp then
            return nil
        end

        local basePosition = merchantHrp.Position
        local outwardDistance = options.OutwardDistance or 5
        -- FIXED: VerticalOffset 3 bukan 20 — player berdiri di depan merchant, bukan melayang
        local verticalOffset = options.VerticalOffset or 3
        local char = Player.Character
        local playerHrp = char and char:FindFirstChild("HumanoidRootPart")

        -- Arah menghadap ke merchant: dari depan merchant (LookVector)
        local direction = -merchantHrp.CFrame.LookVector

        local horizontalDirection = Vector3.new(direction.X, 0, direction.Z)
        if horizontalDirection.Magnitude < 1 then
            horizontalDirection = Vector3.new(0, 0, -1)
        end

        return basePosition + (horizontalDirection.Unit * outwardDistance) + Vector3.new(0, verticalOffset, 0)
    end

    -- Cari semua merchant di semua folder NPC di workspace
    function MerchantModule.getAllMerchants()
        local results = {}
        local ok, NPCs = pcall(function()
            return Services.Workspace:FindFirstChild("NPCs")
        end)
        if not ok or not NPCs then return results end

        for _, folder in ipairs(NPCs:GetChildren()) do
            for _, npc in ipairs(folder:GetChildren()) do
                -- Cari merchant dengan Dialog Seller ATAU Name berisi "Merchant"/"Seller"/"Shop"
                local isSeller = false

                -- Method 1: Dialog ObjectValue ke Seller
                local dialog = npc:FindFirstChild("Dialog")
                if dialog and dialog.ClassName == "ObjectValue" and dialog.Value then
                    local valName = dialog.Value.Name or ""
                    if valName == "Seller" or valName:lower():find("sell") or valName:lower():find("merchant") then
                        isSeller = true
                    end
                end

                -- Method 2: Icon image check
                if not isSeller then
                    local icon = npc:FindFirstChild("IconUI")
                    local img = icon and icon:FindFirstChild("ImageLabel")
                    if img and img.Image == "rbxassetid://2246496691" then
                        isSeller = true
                    end
                end

                -- Method 3: NPC name contains merchant/seller/shop keywords
                if not isSeller then
                    local n = npc.Name:lower()
                    if n:find("merchant") or n:find("seller") or n:find("vendor") or n:find("shop") then
                        isSeller = true
                    end
                end

                -- Method 4: Has SellAll-related prompt or child
                if not isSeller then
                    local sp = npc:FindFirstChildWhichIsA("ProximityPrompt", true)
                    if sp and (sp.ActionText:lower():find("sell") or sp.ObjectText:lower():find("sell")) then
                        isSeller = true
                    end
                end

                if isSeller and npc:FindFirstChild("HumanoidRootPart") then
                    table.insert(results, {
                        npc = npc,
                        hrp = npc.HumanoidRootPart,
                        name = npc.Name,
                        folder = folder.Name
                    })
                end
            end
        end
        return results
    end

    -- Teleport langsung ke depan merchant terdekat dan jual
    function MerchantModule.directTeleportAndSell()
        local char = Player.Character
        local playerHrp = char and char:FindFirstChild("HumanoidRootPart")
        if not playerHrp then
            Utility.createNotification("Character not found!", 3)
            return false
        end

        -- Cari semua merchant
        local allMerchants = MerchantModule.getAllMerchants()

        if #allMerchants == 0 then
            -- Fallback: coba getClosest() (original method)
            local closestHrp, dist = MerchantModule.getClosest()
            if not closestHrp then
                Utility.createNotification("Tidak ada merchant ditemukan di peta ini!", 4)
                return false
            end
            table.insert(allMerchants, { hrp = closestHrp, name = "Merchant" })
        end

        -- Sort by distance
        table.sort(allMerchants, function(a, b)
            local da = (playerHrp.Position - a.hrp.Position).Magnitude
            local db = (playerHrp.Position - b.hrp.Position).Magnitude
            return da < db
        end)

        local nearest = allMerchants[1]
        local sellPos = MerchantModule.getSellPosition(nearest.hrp)

        if not sellPos then
            Utility.createNotification("Gagal hitung posisi merchant!", 3)
            return false
        end

        -- Simpan posisi asal
        local originCF = playerHrp.CFrame

        -- Teleport langsung ke depan merchant
        Utility.createNotification("Teleport ke merchant: " .. nearest.name, 3)
        pcall(function()
            playerHrp.CFrame = CFrame.new(sellPos)
        end)

        task.wait(0.6)

        -- Jual semua
        local ok, result = pcall(function()
            return ReplicatedStorage.Remotes.Shop.SellAll:InvokeServer()
        end)

        if ok then
            local itemsSold = type(result) == "number" and result or (type(result) == "table" and result[1]) or 0
            Utility.createNotification("Berhasil dijual! Items: " .. tostring(itemsSold), 4)
            return true
        else
            -- Coba FireServer sebagai fallback
            pcall(function()
                ReplicatedStorage.Remotes.Shop.SellAll:FireServer()
            end)
            Utility.createNotification("Sell dikirim (fallback)!", 3)
            return true
        end
    end
end

local SellModule = {}
do
    function SellModule.getInventoryCount()
        local count = 0
        local bp = getBackpack()
        if bp then
            for _, item in ipairs(bp:GetChildren()) do
                local t = item:GetAttribute("ItemType")
                if t == "Valuable" or t == "Equipment" then
                    count = count + 1
                end
            end
        end

        local character = Player.Character
        if character then
            local equipped = character:FindFirstChildOfClass("Tool")
            if equipped then
                local t = equipped:GetAttribute("ItemType")
                if t == "Valuable" or t == "Equipment" then
                    count = count + 1
                end
            end
        end

        return count
    end

    function SellModule.getBackpackSpaceFromLabel()
        local toolUI = PlayerGui and PlayerGui:FindFirstChild("ToolUI")
        local fillingPan = toolUI and toolUI:FindFirstChild("FillingPan")
        local inventorySpace = fillingPan and fillingPan:FindFirstChild("InventorySpace")

        if not inventorySpace or not inventorySpace:IsA("TextLabel") then
            return nil, nil, nil
        end

        local text = inventorySpace.Text or ""
        local currentRaw, maxRaw = text:match("([^/]+)%s*/%s*(.+)")
        if not currentRaw or not maxRaw then
            return nil, nil, text
        end

        local function parseValue(raw)
            local cleaned = string.gsub(string.gsub(string.gsub(tostring(raw), ",", ""), " ", ""), "%s+", ""):lower()
            local multiplier = 1
            if string.find(cleaned, "k") then
                multiplier = 1000
                cleaned = string.gsub(cleaned, "k", "")
            elseif string.find(cleaned, "m") then
                multiplier = 1000000
                cleaned = string.gsub(cleaned, "m", "")
            elseif string.find(cleaned, "b") then
                multiplier = 1000000000
                cleaned = string.gsub(cleaned, "b", "")
            elseif string.find(cleaned, "t") then
                multiplier = 1000000000000
                cleaned = string.gsub(cleaned, "t", "")
            end
            local parsed = tonumber(cleaned)
            return parsed and math.max(0, math.floor(parsed * multiplier)) or nil
        end

        local current = parseValue(currentRaw)
        local max = parseValue(maxRaw)

        if not current or not max then
            return nil, nil, text
        end

        return current, max, text
    end

    function SellModule.isBackpackAtCapacity()
        local current, max = SellModule.getBackpackSpaceFromLabel()
        return current ~= nil and max ~= nil and max > 0 and current >= max
    end

    function SellModule.execute()
        return ReplicatedStorage.Remotes.Shop.SellAll:InvokeServer()
    end

    function SellModule.handleVoidRequest()
        Utility.createNotification("Exiting The Void to find merchant...", 5)

        HumanoidRootPart.CFrame = CFrame.new(Map.EventStuff["The Void"].Model.ExitPortal.CFrame.Position +
                                                 Vector3.new(0, 3, 0))

        local maxWait = tick() + 7
        repeat
            task.wait(0.1)
        until (Player:GetAttribute("CurrentArea") == "Fortune River" and Player:GetAttribute("GameplayPaused") == false) or
            tick() > maxWait

        if Player:GetAttribute("CurrentArea") ~= "Fortune River" then
            Utility.createNotification("Failed to exit The Void properly.", 5)
            return false
        end

        task.wait(2)

        local closestHrp
        for i = 1, 4 do
            closestHrp = MerchantModule.getClosest()
            if closestHrp then
                break
            end
            if i < 4 then
                task.wait(1)
            end
        end

        if not closestHrp then
            Utility.createNotification("No merchant found after exiting void.", 5)
            HumanoidRootPart.CFrame = CFrame.new(Map.EventStuff.VoidPortal.Part.CFrame.Position + Vector3.new(0, 3, 0))
            return false
        end

        Utility.createNotification("Found merchant, teleporting and selling..", 5)

        local sellPosition = MerchantModule.getSellPosition(closestHrp)
        local sellSuccess = Movement.teleportToTarget(sellPosition, {
            Mode = "Critical",
            FireRemoteFunc = function()
                Utility.createNotification("Selling all valuables...", 3)
                return SellModule.execute()
            end,
            Timeout = 90
        })

        if sellSuccess then
            local success
            task.wait(3)
            Utility.createNotification("Returning to The Void...", 5)

            local voidportal = Map.EventStuff.VoidPortal
            Movement.teleportToTarget(voidportal.WorldPivot.Position, {
                Mode = "Standard",
                OnComplete = function(moveSuccess)
                    success = moveSuccess or false
                end
            })

            task.wait()
            return success
        end

        return sellSuccess
    end

    function SellModule.sell(config, mode)
        local closestHrp, dist = MerchantModule.getClosest()

        local ServerTime = Services.Workspace:GetServerTimeNow()
        local trialTime = Player:GetAttribute("SellAnywhereTrialTime")
        local requiredDistance = config.RequiredDistance or 45

        if Player:GetAttribute("SellAnywhere") == true or (trialTime and trialTime + 600 > ServerTime) then
            local itemsSold, _ = SellModule.execute()
            if itemsSold and itemsSold > 0 then
                return true
            end
        end

        if not closestHrp and Player:GetAttribute("CurrentArea") == "The Void" then
            return SellModule.handleVoidRequest(config, mode)
        end

        if closestHrp and dist <= requiredDistance then
            SellModule.execute()
            return true
        end

        if not closestHrp then
            EngProject:CreateNotification({
                Type = "Error",
                Title = "Notification",
                Description = "No merchant found nearby.",
                Duration = 5
            })
            return false
        end

        local function applyDefaults(cfg, m)
            local defaults = {}
            if m == "Tween" then
                defaults = {
                    StopDistance = 20,
                    CruiseHeight = 6,
                    MaxHeight = 10,
                    MinHeight = 1,
                    LongDistanceThreshold = 150,
                    DirectFlightThreshold = 50,
                    AdaptiveHeight = true,
                    UseDirectFlight = true,
                    HoverDuration = 0.3,
                    LandingDuration = 1.2
                }
            else
                defaults = {
                    Mode = "Critical",
                    Timeout = 90
                }
            end

            for k, v in pairs(defaults) do
                if cfg[k] == nil then
                    cfg[k] = v
                end
            end
        end

        applyDefaults(config, mode)
        local sellPosition = MerchantModule.getSellPosition(closestHrp)

        if mode == "Tween" then
            local completed = false
            local successSell = false

            config.OnStart = function()
                EngProject:CreateNotification({
                    Type = "Default",
                    Title = "Notification",
                    Description = "Tweening to merchant...",
                    Duration = 5
                })
            end

            config.OnComplete = function()
                task.wait(1)
                local _, finalDistance = MerchantModule.getClosest()
                if finalDistance and finalDistance <= requiredDistance then
                    SellModule.execute()
                    successSell = true
                else
                    EngProject:CreateNotification({
                        Type = "Error",
                        Title = "Notification",
                        Description = "Could not reach merchant via tween",
                        Duration = 5
                    })
                end
                completed = true
            end

            Movement.tweenToTarget(sellPosition, config)

            repeat
                task.wait()
            until completed

            return successSell
        else
            config.FireRemoteFunc = function()
                return SellModule.execute()
            end
            return Movement.teleportToTarget(sellPosition, config)
        end
    end
end

local ExcavationModule = {}
do
    function ExcavationModule.refreshData()
        if State.Excavation.waiting then
            return
        end
        State.Excavation.waiting = true

        local UpdateRemote = ReplicatedStorage.Remotes.Excavation.UpdateExcavationData
        local con

        con = UpdateRemote.OnClientEvent:Connect(function(d)
            State.Excavation.data = d
            State.Excavation.waiting = false
            con:Disconnect()
        end)

        UpdateRemote:FireServer()
    end

    function ExcavationModule.getCurrentStatus()
        if not State.Excavation.data then
            ExcavationModule.refreshData()
        end

        repeat
            task.wait()
        until State.Excavation.data

        local d = State.Excavation.data
        local ce = d.CurrentExcavation
        local marker = Services.Workspace:FindFirstChild("Marker")

        if marker then
            local ui = marker:FindFirstChild("UI")
            if ui then
                local n = ui:FindFirstChild("ExcavationName")
                if n and typeof(n.Text) == "string" and n.Text ~= "" then
                    return "Finished", n.Text
                end
            end
        end

        if ce and ce ~= "" then
            return "Active", ce
        end

        return "None", nil
    end

    function ExcavationModule.canStart()
        local status = ExcavationModule.getCurrentStatus()
        return status == "None"
    end

    function ExcavationModule.claim()
        local status, name = ExcavationModule.getCurrentStatus()
        if status ~= "Finished" or not name then
            return false
        end

        local ClaimRemote = ReplicatedStorage.Remotes.Excavation.ClaimExcavation
        local ok = ClaimRemote:InvokeServer(name)

        if ok then
            task.wait(2)
            ExcavationModule.refreshData()
            return true
        end

        return false
    end

    function ExcavationModule.start()
        if not State.Excavation.selected then
            return false, "No excavation selected."
        end

        local d = State.Excavation.data
        if not d then
            ExcavationModule.refreshData()
            repeat
                task.wait()
            until State.Excavation.data
            d = State.Excavation.data
        end

        local unlocked = d.UnlockedExcavationSites
        if not table.find(unlocked, State.Excavation.selected) then
            return false, "You haven't unlocked this excavation."
        end

        if not ExcavationModule.canStart() then
            if d.CurrentExcavation and d.CurrentExcavation ~= "" then
                return false, "Cannot start — active excavation: " .. d.CurrentExcavation
            else
                return false, "Cannot start — check for unclaimed excavation."
            end
        end

        local StartRemote = ReplicatedStorage.Remotes.Excavation.StartExcavation
        local ok = StartRemote:InvokeServer(State.Excavation.selected)

        if ok then
            ExcavationModule.refreshData()
            return true
        end

        return false, "Server rejected the request."
    end

    function ExcavationModule.autoStartCycle()
        local status = ExcavationModule.getCurrentStatus()

        if status == "Finished" then
            ExcavationModule.claim()
            task.wait(1)
            status = ExcavationModule.getCurrentStatus()
        end

        if status == "None" then
            return ExcavationModule.start()
        end

        return false, status == "Active" and "Excavation already active." or "Waiting for excavation state."
    end

    function ExcavationModule.getNames()
        local t = {}
        for name in pairs(Excavations.Sites) do
            table.insert(t, name)
        end
        return t
    end
end

local GeodeModule = {}
do
    function GeodeModule.isCollected(geode)
        return not geode or not geode.Parent
    end

    function GeodeModule.getModels()
        local geodeFolder = Services.Workspace:FindFirstChild("Geode")
        if not geodeFolder then
            return {}
        end

        local geodeModels = {}
        for _, child in pairs(geodeFolder:GetChildren()) do
            if child:IsA("Model") then
                table.insert(geodeModels, child)
            end
        end

        return geodeModels
    end

    function GeodeModule.getTeleportPosition(geodeModel)
        local cf, size = geodeModel:GetBoundingBox()
        return cf.Position
    end

    function GeodeModule.teleportToPosition(position)
        local character = Player.Character
        if not character then
            return false
        end

        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoidRootPart then
            return false
        end

        humanoidRootPart.CFrame = CFrame.new(position)
        return true
    end

    function GeodeModule.teleportToNext(geodeStatus)
        local geodeModels = GeodeModule.getModels()

        if #geodeModels == 0 then
            if geodeStatus then
                geodeStatus:SetFields({"No geodes found"})
            end
            return false
        end

        if State.Geode.currentIndex > #geodeModels then
            State.Geode.currentIndex = 1
        end

        local targetGeode = geodeModels[State.Geode.currentIndex]

        if GeodeModule.isCollected(targetGeode) then
            State.Geode.currentIndex = State.Geode.currentIndex + 1
            return false
        end

        local geodePosition = GeodeModule.getTeleportPosition(targetGeode)

        if GeodeModule.teleportToPosition(geodePosition) then
            if geodeStatus then
                geodeStatus:SetFields({string.format("Teleported to: %s (%d/%d)", targetGeode.Name,
                    State.Geode.currentIndex, #geodeModels)})
            end
            return true
        else
            if geodeStatus then
                geodeStatus:SetFields({"Failed to teleport – Character not found"})
            end
            return false
        end
    end
end

local RuneModule = {}
do
    function RuneModule.getList()
        local folder = Map:FindFirstChild("FindableRunes")
        return folder and folder:GetChildren() or {}
    end

    function RuneModule.teleportToNext(runeStatus)
        local list = RuneModule.getList()

        if #list == 0 then
            if runeStatus then
                runeStatus:SetFields({"No runes found in workspace"})
            end
            return
        end

        State.Rune.currentIndex = State.Rune.currentIndex + 1
        if State.Rune.currentIndex > #list then
            State.Rune.currentIndex = 1
        end

        local rune = list[State.Rune.currentIndex]
        if not rune or not rune:IsA("Model") then
            if runeStatus then
                runeStatus:SetFields({"Invalid rune"})
            end
            return
        end

        local target = rune:FindFirstChild("MainPart")
        if not target or not target:IsA("BasePart") then
            if runeStatus then
                runeStatus:SetFields({"Rune has no MainPart"})
            end
            return
        end

        local char = Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then
            if runeStatus then
                runeStatus:SetFields({"No HumanoidRootPart"})
            end
            return
        end

        root.CFrame = target.CFrame + Vector3.new(0, 3, 0)

        if runeStatus then
            runeStatus:SetFields({string.format("Teleported to rune %d/%d", State.Rune.currentIndex, #list)})
        end
    end
end

local CraftingModule = {}
do
    local Modifiers = require(ReplicatedStorage.GameInfo.Modifiers)

    local function determineQuality(selected, recipe)
        local totalScore = 0
        local totalCount = 0
        for materialName, req in pairs(recipe.Materials) do
            local sel = selected[materialName]
            if not sel then
                return nil
            end
            for i = 1, #sel do
                local tool = sel[i]
                local d = tool:FindFirstChild("ItemData")
                if d then
                    local w = d:GetAttribute("Weight") or 0
                    local mod = d:GetAttribute("Modifier")
                    if mod and Modifiers[mod] then
                        w = w * Modifiers[mod].Multiplier
                    end
                    totalScore = totalScore + ((w - (req.MinWeight or 0)) / req.QualityStep + 1)
                    totalCount = totalCount + 1
                end
            end
            if #sel < req.Amount then
                return nil
            end
        end
        if totalCount == 0 then
            return nil
        end
        return math.clamp(math.floor(totalScore / totalCount), 1, 5)
    end

    local function getTools()
        local tools = {}
        local bp = getBackpack()
        local backpack = bp and bp:GetChildren() or {}
        for i = 1, #backpack do
            tools[#tools + 1] = backpack[i]
        end
        local char = Character
        if char then
            local t = char:FindFirstChildOfClass("Tool")
            if t then
                tools[#tools + 1] = t
            end
        end
        return tools
    end

    local function effectiveWeight(tool)
        local d = tool:FindFirstChild("ItemData")
        if not d then
            return 0
        end
        local w = d:GetAttribute("Weight") or 0
        local mod = d:GetAttribute("Modifier")
        if mod and Modifiers[mod] then
            w = w * Modifiers[mod].Multiplier
        end
        return w
    end

    function CraftingModule.getModifierNames()
        local t = {}
        for k in pairs(Modifiers) do
            t[#t + 1] = k
        end
        return t
    end

    function CraftingModule.getOreNames()
        local t = {}
        for _, obj in ipairs(ReplicatedStorage.Items.Valuables:GetChildren()) do
            t[#t + 1] = obj.Name
        end
        return t
    end

    function CraftingModule.getDiscoveredRecipes()
        local ids = {}
        local waiting = true
        local conn
        conn = ReplicatedStorage.Remotes.Crafting.UpdateDiscoveredEquipment.OnClientEvent:Connect(function(data)
            ids = data
            waiting = false
            conn:Disconnect()
        end)
        ReplicatedStorage.Remotes.Crafting.UpdateDiscoveredEquipment:FireServer()
        local t = 0
        while waiting and t < 5 do
            task.wait(0.1)
            t = t + 0.1
        end

        local recipes = {}
        for _, item in ipairs(ReplicatedStorage.Items.Equipment:GetChildren()) do
            local equipData = item:FindFirstChild("EquipmentData")
            if equipData and equipData:IsA("ModuleScript") then
                local ok, data = pcall(require, equipData)
                if ok and data.Materials then
                    local hidden = item:GetAttribute("Hidden")
                    local admin = item:GetAttribute("AdminLimited")
                    local xmas = item:GetAttribute("ChristmasLimited")
                    local add = false
                    if hidden then
                        if table.find(ids, item:GetAttribute("ItemID")) then
                            add = true
                        end
                    elseif not admin and not xmas then
                        add = true
                    end
                    if add then
                        recipes[#recipes + 1] = {
                            Name = item.Name,
                            Item = item,
                            Data = data
                        }
                    end
                end
            end
        end

        table.sort(recipes, function(a, b)
            return a.Name < b.Name
        end)
        return recipes
    end

    function CraftingModule.getOwned(materialName, minWeight)
        local owned = {}
        local tools = getTools()
        for i = 1, #tools do
            local tool = tools[i]
            if tool.Name == materialName then
                local d = tool:FindFirstChild("ItemData")
                if d then
                    local w = d:GetAttribute("Weight") or 0
                    if w >= (minWeight or 0) then
                        owned[#owned + 1] = tool
                    end
                end
            end
        end
        return owned
    end

    function CraftingModule.selectBest(recipe)
        local selected = {}
        for materialName, req in pairs(recipe.Materials) do
            local owned = CraftingModule.getOwned(materialName, req.MinWeight)
            table.sort(owned, function(a, b)
                return effectiveWeight(a) > effectiveWeight(b)
            end)
            selected[materialName] = {}
            local limit = math.min(req.Amount, #owned)
            for i = 1, limit do
                selected[materialName][i] = owned[i]
            end
        end
        return selected
    end

    function CraftingModule.buildFields(eq, selected)
        local recipe = eq.Data
        local fields = {}
        local LINE = "- - - - - - - - - - - - - -"

        fields[#fields + 1] = eq.Name
        fields[#fields + 1] = {
            Text = "Price:" .. Utility.formatPrice(recipe.Price or 0),
            IsSubField = true
        }
        fields[#fields + 1] = {
            Text = LINE,
            IsSubField = true
        }

        local allReady = true
        local missingCount = 0

        for materialName, req in pairs(recipe.Materials) do
            local owned = CraftingModule.getOwned(materialName, req.MinWeight)
            local sel = selected[materialName] or {}
            local count = 0
            for i = 1, #sel do
                if sel[i] and sel[i].Parent then
                    count = count + 1
                end
            end

            if count < req.Amount then
                allReady = false
                missingCount = missingCount + (req.Amount - count)
            end

            local icon = count >= req.Amount and "[+]" or "[-]"
            local label
            if req.MinWeight and req.MinWeight > 0 then
                label = string.format("%s %s [+%dkg]  %d/%d  (%d owned)", icon, materialName, req.MinWeight, count,
                    req.Amount, #owned)
            else
                label = string.format("%s %s  %d/%d  (%d owned)", icon, materialName, count, req.Amount, #owned)
            end
            fields[#fields + 1] = {
                Text = label,
                IsSubField = true
            }
        end

        fields[#fields + 1] = {
            Text = LINE,
            IsSubField = true
        }

        if allReady then
            local quality = determineQuality(selected, recipe)

            if quality then
                local stars = string.rep("☆", quality) .. string.rep(".", 5 - quality)
                local qualityNames = {"Poor", "Common", "Good", "Great", "Perfect"}
                fields[#fields + 1] = "Quality: [" .. stars .. "]  " .. qualityNames[quality]

                if recipe.Stats then
                    local ok, ItemStatsInfo = pcall(require, ReplicatedStorage.GameInfo.ItemStatsInfo)
                    local ok2, FormatNumber = pcall(require, ReplicatedStorage.Modules.Utility.FormatNumber)
                    if ok and ok2 then
                        for statName, statData in pairs(recipe.Stats) do
                            local info = ItemStatsInfo[statName]
                            if info then
                                local minVal = statData.Min + statData.QualityStep * (quality - 1)
                                local maxVal = statData.Min + statData.QualityStep * quality
                                local statText
                                if info.Percentage then
                                    statText = string.format("  %s: %.0f%% - %.0f%%", info.DisplayName, minVal * 100,
                                        maxVal * 100)
                                else
                                    statText = string.format("  %s: %s - %s", info.DisplayName,
                                        FormatNumber.Format(minVal), FormatNumber.Format(maxVal))
                                end
                                fields[#fields + 1] = {
                                    Text = statText,
                                    IsSubField = true
                                }
                            end
                        end
                    end
                end

                if quality < 5 then
                    fields[#fields + 1] = {
                        Text = "Use heavier materials for better quality",
                        IsSubField = true
                    }
                else
                    fields[#fields + 1] = {
                        Text = "Maximum quality achieved",
                        IsSubField = true
                    }
                end
            else
                fields[#fields + 1] = "Quality: [.....]  Unknown"
            end

            fields[#fields + 1] = {
                Text = LINE,
                IsSubField = true
            }
            fields[#fields + 1] = "Ready to craft"
        else
            fields[#fields + 1] = "Missing " .. missingCount .. " material" .. (missingCount == 1 and "" or "s")
        end

        return fields
    end

    function CraftingModule.canCraft(recipe, selected)
        for materialName, req in pairs(recipe.Materials) do
            local sel = selected[materialName] or {}
            local count = 0
            for i = 1, #sel do
                if sel[i] and sel[i].Parent then
                    count = count + 1
                end
            end
            if count < req.Amount then
                return false
            end
        end
        return true
    end

    function CraftingModule.craft(equipmentItem, selected)
        local ok, result, _, craftedItem = pcall(function()
            return ReplicatedStorage.Remotes.Crafting.CraftEquipment:InvokeServer(equipmentItem, selected)
        end)
        if not ok then
            return false, "Remote failed"
        end
        if not result then
            return false, "Server rejected"
        end
        return true, craftedItem
    end
end

local EnchantModule = {}
do
    function EnchantModule.getNames(type)
        if type == "pan" then
            local enchantsModule = require(ReplicatedStorage.GameInfo.Enchants)
            local names = {}
            for name in pairs(enchantsModule) do
                names[#names + 1] = name
            end
            table.sort(names)
            return names
        elseif type == "shovel" then
            local shovelEnchantsModule = require(ReplicatedStorage.GameInfo.ShovelEnchants)
            local names = {}
            for name in pairs(shovelEnchantsModule) do
                names[#names + 1] = name
            end
            table.sort(names)
            return names
        end
        return {}
    end

    function EnchantModule.findPanMaterial(materialName)
        local bp = getBackpack()
        if not bp then
            return nil
        end
        return bp:FindFirstChild(materialName)
    end

    function EnchantModule.findShovelMaterial(modifier)
        local bp = getBackpack()
        if not bp then
            return nil
        end

        for _, tool in ipairs(bp:GetChildren()) do
            if tool:IsA("Tool") and tool.Name == "Aetherite" then
                local itemData = tool:FindFirstChild("ItemData")
                if itemData and itemData:GetAttribute("Modifier") == modifier then
                    return tool
                end
            end
        end

        return nil
    end

    function EnchantModule.enchant(remote, item, itemName)
        local ok, result = pcall(function()
            return remote:InvokeServer(item)
        end)

        if ok then
            Utility.createNotification("Successfully enchanted with " .. tostring(result) .. " using " .. itemName, 4)
            return result
        else
            Utility.createNotification("Error enchanting " .. itemName, 3)
            return nil
        end
    end

    function EnchantModule.performAuto(findFunc, remote, itemName, target, flag)
        task.spawn(function()
            while flag[1] do
                local item = findFunc()
                if not item then
                    flag[1] = false
                    Utility.createNotification("Item not found: " .. itemName, 3)
                    break
                end

                local enchant = EnchantModule.enchant(remote, item, itemName)
                if enchant then
                    if enchant == target then
                        flag[1] = false
                        Utility.createNotification("Got target enchant: " .. enchant, 5)
                        break
                    end
                end

                task.wait(1.5)
            end
        end)
    end
end

local FavouriteModule = {}
do
    function FavouriteModule.isLocked(item)
        return item:GetAttribute("Locked") == true
    end

    function FavouriteModule.toggle(item)
        ReplicatedStorage.Remotes.Inventory.ToggleLock:FireServer(item)
    end

    function FavouriteModule.favourite(item)
        if not FavouriteModule.isLocked(item) then
            FavouriteModule.toggle(item)
        end
    end

    function FavouriteModule.matchesModifier(item, modifier)
        return item:FindFirstChild("ItemData"):GetAttribute("Modifier") == modifier
    end

    function FavouriteModule.matchesOre(item, oreName)
        return item.Name == oreName
    end

    function FavouriteModule.isValuable(item)
        return item:GetAttribute("ItemType") == "Valuable"
    end
end

local ReforgeModule = {}
do
    function ReforgeModule.updateInfo(guid, infoDisplay)
        local function safeSetFields(fields)
            pcall(function()
                infoDisplay:SetFields(fields)
            end)
        end

        if not guid then
            safeSetFields({"No equipment selected"})
            return
        end

        local bp = getBackpack()
        if not bp then
            safeSetFields({"Backpack unavailable"})
            return
        end

        local equipment
        for _, child in ipairs(bp:GetChildren() or {}) do
            if child and child.GetAttribute and child:GetAttribute("GUID") == guid then
                equipment = child
                break
            end
        end

        if not equipment then
            safeSetFields({"Equipment not found"})
            return
        end

        local fields = {}
        table.insert(fields, "Name: " .. tostring(equipment.Name or "Unknown"))

        local reforges = (equipment:FindFirstChild("ItemData") and equipment.ItemData:GetAttribute("Reforges")) or 0
        table.insert(fields, "Reforges: " .. tostring(reforges))

        local cost
        pcall(function()
            cost = ReplicatedStorage.Remotes.Crafting.GetReforgeCost:InvokeServer(equipment)
        end)
        table.insert(fields, "Price: " .. Utility.formatPrice(cost or 0))

        local statRolls
        pcall(function()
            statRolls = equipment:FindFirstChild("StatRolls")
        end)

        if statRolls and statRolls.GetAttributes then
            table.insert(fields, "Stats:")
            local attributes = {}
            pcall(function()
                attributes = statRolls:GetAttributes()
            end)

            for attrName, attrValue in pairs(attributes or {}) do
                table.insert(fields, {
                    Text = tostring(attrName) .. ": " .. tostring(attrValue),
                    IsSubField = true
                })
            end
        end

        safeSetFields(fields)
    end

    function ReforgeModule.perform(guid)
        if not guid then
            Utility.createNotification("Select an Equipment from your Backpack first!")
            return
        end

        local bp = getBackpack()
        if not bp then
            Utility.createNotification("Backpack unavailable.")
            return
        end

        local equipment
        for _, child in ipairs(bp:GetChildren() or {}) do
            if child and child.GetAttribute and child:GetAttribute("GUID") == guid then
                equipment = child
                break
            end
        end

        if not equipment then
            Utility.createNotification("Selected equipment not found.")
            return
        end

        local success, result = pcall(function()
            return CraftingRemotes.ReforgeEquipment:InvokeServer(equipment)
        end)

        if not success then
            Utility.createNotification("Reforge failed: " .. tostring(result))
            return
        end

        Utility.createNotification("Reforge successful!")

        local newEquipment
        local timeout = 2
        local startTime = os.clock()

        while os.clock() - startTime < timeout do
            local bp = getBackpack()
            if bp then
                for _, child in ipairs(bp:GetChildren() or {}) do
                    if child and child.GetAttribute and child:GetAttribute("GUID") == guid then
                        newEquipment = child
                        break
                    end
                end
            end
            if newEquipment then
                break
            end
            task.wait(0.1)
        end

        if not newEquipment then
            Utility.createNotification("Reforge succeeded, but updated item not found.")
            return
        end

        pcall(function()
            CraftingRemotes.GetReforgeCost:InvokeServer(newEquipment)
        end)

        return guid
    end
end

local FireflyModule = {}
do
    function FireflyModule.craft(amount)
        if typeof(amount) ~= "number" or amount < 1 or amount >= 1000 then
            EngProject:CreateNotification({
                Type = "Error",
                Title = "Invalid Amount",
                Description = "Craft amount must be between 1 and 999."
            })
            return false
        end

        local stones = {}
        local bp = getBackpack()
        if bp then
            for _, tool in ipairs(bp:GetChildren()) do
                if tool:IsA("Tool") and tool.Name == "Firefly Stone" then
                    table.insert(stones, tool)
                end
            end
        end

        if #stones < amount then
            EngProject:CreateNotification({
                Type = "Error",
                Title = "Insufficient Materials",
                Description = "Not enough Firefly Stones."
            })
            return false
        end

        local flareTable = Map:WaitForChild("LushCaverns"):WaitForChild("AbyssAssets"):WaitForChild("FlareTable")
        local prompt = flareTable:FindFirstChild("Prompt", true)

        if not prompt or not fireproximityprompt then
            EngProject:CreateNotification({
                Type = "Error",
                Title = "Executor Unsupported",
                Description = "fireproximityprompt is unavailable."
            })
            return false
        end

        if not HumanoidRootPart then
            return false
        end

        local distance = (HumanoidRootPart.Position - flareTable:GetPivot().Position).Magnitude

        if distance > 20 then
            EngProject:CreateNotification({
                Type = "Warning",
                Title = "Too Far Away",
                Description = "Go to the Firefly crafting table."
            })
            return false
        elseif distance > 10 then
            EngProject:CreateNotification({
                Type = "Info",
                Title = "Get Closer",
                Description = "Move closer to the crafting table."
            })
            return false
        end

        prompt.HoldDuration = 0

        EngProject:CreateNotification({
            Type = "Info",
            Title = "Crafting Started",
            Description = "Crafting Firefly Flares..."
        })

        local EquipRemote = ReplicatedStorage.Remotes.CustomBackpack.EquipRemote

        for i = 1, amount do
            if not Character or not HumanoidRootPart then
                break
            end

            local currentDistance = (HumanoidRootPart.Position - flareTable:GetPivot().Position).Magnitude
            if currentDistance > 20 then
                break
            end

            local tool = stones[i]
            if not tool or not tool.Parent then
                break
            end

            pcall(function()
                EquipRemote:FireServer(tool)
            end)

            task.wait(0.05)

            pcall(function()
                fireproximityprompt(prompt)
            end)

            task.wait(0.15)
        end

        EngProject:CreateNotification({
            Type = "Success",
            Title = "Crafting Complete",
            Description = "Firefly crafting process finished."
        })

        return true
    end
end

local ESPModule = {}
do
    function ESPModule.createBillboard(target, name, color, player)
        local bb = Instance.new("BillboardGui")
        bb.Name = "ESPBillboard"
        bb.Adornee = target
        bb.AlwaysOnTop = true
        bb.StudsOffset = Vector3.new(0, 2.6, 0)
        bb.Size = UDim2.fromOffset(200, 24)
        bb.Parent = target

        local frame = Instance.new("Frame")
        frame.BackgroundTransparency = 1
        frame.Size = UDim2.fromScale(1, 1)
        frame.Parent = bb

        local padding = Instance.new("UIPadding")
        padding.PaddingLeft = UDim.new(0, 4)
        padding.PaddingRight = UDim.new(0, 4)
        padding.Parent = frame

        local layout = Instance.new("UIListLayout")
        layout.FillDirection = Enum.FillDirection.Horizontal
        layout.VerticalAlignment = Enum.VerticalAlignment.Center
        layout.Padding = UDim.new(0, 5)
        layout.Parent = frame

        if player then
            local avatar = Instance.new("ImageLabel")
            avatar.BackgroundTransparency = 1
            avatar.Size = UDim2.fromOffset(16, 16)
            avatar.Image = Services.Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot,
                Enum.ThumbnailSize.Size48x48)
            avatar.Parent = frame

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(1, 0)
            corner.Parent = avatar
        end

        local nameLabel = Instance.new("TextLabel")
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamSemibold
        nameLabel.TextSize = 13
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextColor3 = color or Color3.new(1, 1, 1)
        nameLabel.Text = name
        nameLabel.AutomaticSize = Enum.AutomaticSize.X
        nameLabel.Parent = frame

        local distLabel = Instance.new("TextLabel")
        distLabel.BackgroundTransparency = 1
        distLabel.Font = Enum.Font.Gotham
        distLabel.TextSize = 11
        distLabel.TextXAlignment = Enum.TextXAlignment.Left
        distLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
        distLabel.AutomaticSize = Enum.AutomaticSize.X
        distLabel.Parent = frame

        local conn
        conn = Services.RunService.RenderStepped:Connect(function()
            if not bb.Parent or not target.Parent then
                conn:Disconnect()
                return
            end
            local d = (Camera.CFrame.Position - target.Position).Magnitude
            distLabel.Text = string.format("%dm", d + 0.5)
        end)

        return bb
    end

    function ESPModule.enablePlayers()
        local function attachESP(plr)
            if plr == Player then
                return
            end

            local char = plr.Character
            if not char then
                return
            end

            local head = char:FindFirstChild("Head")
            if not head then
                return
            end

            if State.ESP.Players[plr] then
                State.ESP.Players[plr]:Destroy()
            end

            State.ESP.Players[plr] = ESPModule.createBillboard(head, plr.Name, Color3.fromRGB(255, 255, 255), plr)
        end

        local function hookPlayer(plr)
            if plr == Player then
                return
            end

            if plr.Character then
                attachESP(plr)
            end

            State.ESP.Connections["Char_" .. plr.UserId] = plr.CharacterAdded:Connect(function()
                attachESP(plr)
            end)

            plr.CharacterRemoving:Connect(function()
                if State.ESP.Players[plr] then
                    State.ESP.Players[plr]:Destroy()
                    State.ESP.Players[plr] = nil
                end
            end)
        end

        for _, plr in ipairs(Services.Players:GetPlayers()) do
            hookPlayer(plr)
        end

        State.ESP.Connections.PlayerAdded = Services.Players.PlayerAdded:Connect(hookPlayer)

        State.ESP.Connections.PlayerRemoving = Services.Players.PlayerRemoving:Connect(function(plr)
            if State.ESP.Players[plr] then
                State.ESP.Players[plr]:Destroy()
                State.ESP.Players[plr] = nil
            end

            local conn = State.ESP.Connections["Char_" .. plr.UserId]
            if conn then
                conn:Disconnect()
                State.ESP.Connections["Char_" .. plr.UserId] = nil
            end
        end)
    end

    function ESPModule.disablePlayers()
        for _, bb in pairs(State.ESP.Players) do
            if bb then
                bb:Destroy()
            end
        end

        for _, conn in pairs(State.ESP.Connections) do
            if typeof(conn) == "RBXScriptConnection" then
                conn:Disconnect()
            end
        end

        State.ESP.Players = {}
        State.ESP.Connections = {}
    end

    function ESPModule.enableTotems()
        local folder = Services.Workspace:FindFirstChild("ActiveTotems")
        if not folder then
            return
        end

        local function addTotem(model)
            if model:IsA("Model") then
                local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
                if part then
                    local color = model:GetAttribute("NameColor")
                    if typeof(color) ~= "Color3" then
                        color = Color3.fromRGB(150, 200, 255)
                    end
                    local bb = ESPModule.createBillboard(part, model.Name, color)
                    State.ESP.Totems[model] = bb
                end
            end
        end

        for _, m in ipairs(folder:GetChildren()) do
            addTotem(m)
        end

        State.ESP.Connections.TotemAdded = folder.ChildAdded:Connect(addTotem)
        State.ESP.Connections.TotemRemoved = folder.ChildRemoved:Connect(function(m)
            if State.ESP.Totems[m] then
                State.ESP.Totems[m]:Destroy()
                State.ESP.Totems[m] = nil
            end
        end)
    end

    function ESPModule.disableTotems()
        for _, v in pairs(State.ESP.Totems) do
            v:Destroy()
        end

        if State.ESP.Connections.TotemAdded then
            State.ESP.Connections.TotemAdded:Disconnect()
        end

        if State.ESP.Connections.TotemRemoved then
            State.ESP.Connections.TotemRemoved:Disconnect()
        end

        State.ESP.Totems = {}
    end

    function ESPModule.clearAll()
        local function clearFromFolder(folder)
            if not folder then
                return
            end
            for _, obj in ipairs(folder:GetDescendants()) do
                if obj:IsA("BillboardGui") and obj.Name == "ESPBillboard" then
                    obj:Destroy()
                end
            end
        end

        clearFromFolder(Services.Workspace:FindFirstChild("ActiveTotems"))
        clearFromFolder(Services.Workspace:FindFirstChild("Characters"))

        for _, bb in pairs(State.ESP.Players or {}) do
            if bb and bb.Parent then
                bb:Destroy()
            end
        end
        State.ESP.Players = {}

        for _, bb in pairs(State.ESP.Totems or {}) do
            if bb and bb.Parent then
                bb:Destroy()
            end
        end
        State.ESP.Totems = {}

        for _, conn in pairs(State.ESP.Connections or {}) do
            if typeof(conn) == "RBXScriptConnection" then
                conn:Disconnect()
            end
        end
        State.ESP.Connections = {}
    end
end

local InventoryFilterModule = {}
do
    function InventoryFilterModule.create()
        local inventory = PlayerGui.BackpackGui.Backpack.Inventory
        local scrollingFrame = inventory.ScrollingFrame
        local gridFrame = scrollingFrame.UIGridFrame

        local existingPanel = inventory:FindFirstChild("FilterPanel")
        if existingPanel then
            existingPanel:Destroy()
            task.wait()
        end

        local filterPanel = Instance.new("Frame")
        filterPanel.Name = "FilterPanel"
        filterPanel.Parent = inventory
        filterPanel.AnchorPoint = Vector2.new(0, 0)
        filterPanel.Position = UDim2.new(1, 0.02, 0, -30)
        filterPanel.Size = UDim2.new(0.22, 0, 1.08, 0)
        filterPanel.BackgroundTransparency = 1
        filterPanel.BorderSizePixel = 0

        local padding = Instance.new("UIPadding")
        padding.PaddingTop = UDim.new(0, 0)
        padding.PaddingBottom = UDim.new(0.04, 0)
        padding.PaddingLeft = UDim.new(0.06, 0)
        padding.PaddingRight = UDim.new(0.06, 0)
        padding.Parent = filterPanel

        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0.018, 0)
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Parent = filterPanel

        local fontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.SemiBold,
            Enum.FontStyle.Italic)

        local title = Instance.new("TextLabel")
        title.Name = "CurrentFilter"
        title.Parent = filterPanel
        title.Size = UDim2.new(1, 0, 0.16, 0)
        title.BackgroundTransparency = 1
        title.Text = "Filter: All Items"
        title.TextWrapped = true
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.TextYAlignment = Enum.TextYAlignment.Center
        title.FontFace = fontFace
        title.TextScaled = true
        title.LineHeight = 1
        title.TextColor3 = Color3.fromRGB(245, 245, 245)
        title.LayoutOrder = 1

        local titleStroke = Instance.new("UIStroke")
        titleStroke.Color = Color3.fromRGB(0, 0, 0)
        titleStroke.Thickness = 1
        titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
        titleStroke.Parent = title

        local function createFilterButton(text, color, order)
            local button = Instance.new("TextButton")
            button.Name = text .. "Filter"
            button.Parent = filterPanel
            button.Size = UDim2.new(1, 0, 0.075, 0)
            button.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
            button.BorderSizePixel = 0
            button.Text = text
            button.FontFace = fontFace
            button.TextScaled = true
            button.LineHeight = 1
            button.TextColor3 = color
            button.AutoButtonColor = false
            button.LayoutOrder = order

            local stroke = Instance.new("UIStroke")
            stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            stroke.Color = color
            stroke.Thickness = 1
            stroke.Parent = button

            return button
        end

        local FILTER_BUTTONS = {{"Ores", Color3.fromRGB(190, 190, 190)}, {"Equipments", Color3.fromRGB(255, 90, 90)},
                                {"Totems/Relics", Color3.fromRGB(120, 220, 120)},
                                {"Geodes", Color3.fromRGB(90, 170, 255)}, {"Maps", Color3.fromRGB(200, 160, 255)},
                                {"Others", Color3.fromRGB(200, 120, 255)}, {"All Items", Color3.fromRGB(245, 245, 245)}}

        local ICON_CATEGORY = {
            ["rbxassetid://71590406800942"] = "Equipments",
            ["rbxassetid://128090935503267"] = "Equipments",
            ["rbxassetid://95192688083586"] = "Equipments",
            ["rbxassetid://84287308918508"] = "Ores",
            ["rbxassetid://18624930841"] = "Totems/Relics",
            ["rbxassetid://6947202399"] = "Totems/Relics",
            ["rbxassetid://9019175526"] = "Geodes",
            ["rbxassetid://8360687671"] = "Maps"
        }

        local connections = {}
        local itemCache = {}
        local currentFilter = "All Items"
        local isUpdating = false
        local filterChanged = false

        local PADDING = 10
        local originalCanvasSize = scrollingFrame.CanvasSize

        local function getCategory(button)
            local icon = button:FindFirstChild("TypeIcon")
            if icon and icon:IsA("ImageLabel") then
                return ICON_CATEGORY[icon.Image] or "Others"
            end
            return "Others"
        end

        local function cacheItem(button)
            if not itemCache[button] then
                itemCache[button] = {
                    pos = button.Position,
                    vis = button.Visible,
                    cat = getCategory(button)
                }
            end
            return itemCache[button]
        end

        local function getAllItems()
            local items = {}
            for _, child in ipairs(gridFrame:GetChildren()) do
                if child:IsA("TextButton") then
                    table.insert(items, child)
                end
            end
            return items
        end

        local function calculateLayout(visibleItems)
            if #visibleItems == 0 then
                return 0
            end

            local firstItem = visibleItems[1]
            local itemWidth = firstItem.AbsoluteSize.X
            local itemHeight = firstItem.AbsoluteSize.Y
            local frameWidth = gridFrame.AbsoluteSize.X

            local cols = math.max(1, math.floor((frameWidth + PADDING) / (itemWidth + PADDING)))
            local rows = math.ceil(#visibleItems / cols)

            for i, item in ipairs(visibleItems) do
                local row = math.floor((i - 1) / cols)
                local col = (i - 1) % cols
                item.Position = UDim2.fromOffset(col * (itemWidth + PADDING), row * (itemHeight + PADDING))
            end

            return rows * (itemHeight + PADDING)
        end

        local function applyFilter(filter)
            if isUpdating then
                return
            end
            isUpdating = true

            local savedScroll = scrollingFrame.CanvasPosition
            currentFilter = filter
            local items = getAllItems()

            if filter == "All Items" then
                for _, item in ipairs(items) do
                    local cached = itemCache[item]
                    if cached then
                        item.Visible = cached.vis
                        item.Position = cached.pos
                    else
                        item.Visible = true
                    end
                end
                scrollingFrame.CanvasSize = originalCanvasSize
            else
                local visible = {}
                for _, item in ipairs(items) do
                    local cached = cacheItem(item)
                    if cached.cat == filter then
                        item.Visible = true
                        table.insert(visible, item)
                    else
                        item.Visible = false
                    end
                end
                local canvasHeight = calculateLayout(visible)
                scrollingFrame.CanvasSize = UDim2.fromOffset(0, canvasHeight)
            end

            if filterChanged then
                scrollingFrame.CanvasPosition = Vector2.zero
                filterChanged = false
            else
                scrollingFrame.CanvasPosition = savedScroll
            end

            isUpdating = false
        end

        local debounce = false
        local function onItemsChanged(child)
            if debounce then
                return
            end
            if not child:IsA("TextButton") then
                return
            end

            debounce = true
            task.wait(0.05)

            for _, item in ipairs(getAllItems()) do
                cacheItem(item)
            end

            applyFilter(currentFilter)
            debounce = false
        end

        for _, item in ipairs(getAllItems()) do
            cacheItem(item)
        end

        for i, data in ipairs(FILTER_BUTTONS) do
            local text, color = data[1], data[2]
            local button = createFilterButton(text, color, i + 1)

            table.insert(connections, button.MouseButton1Click:Connect(function()
                filterChanged = true
                title.Text = "Filter: " .. text
                applyFilter(text)
            end))

            table.insert(connections, button.MouseEnter:Connect(function()
                button.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
            end))

            table.insert(connections, button.MouseLeave:Connect(function()
                button.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
            end))
        end

        table.insert(connections, gridFrame.ChildAdded:Connect(onItemsChanged))
        table.insert(connections, gridFrame.ChildRemoved:Connect(onItemsChanged))

        table.insert(connections, filterPanel.Destroying:Connect(function()
            for _, conn in ipairs(connections) do
                if conn.Connected then
                    conn:Disconnect()
                end
            end
            table.clear(connections)
            table.clear(itemCache)
        end))
    end

    function InventoryFilterModule.destroy()
        local inventory = PlayerGui.BackpackGui.Backpack.Inventory
        local existingPanel = inventory:FindFirstChild("FilterPanel")
        if existingPanel then
            existingPanel:Destroy()
        end
    end
end

local MobileUIModule = {}
do
    function MobileUIModule.createToggleButton(window, forceMobile)
        if not forceMobile and not EngProject.Utility:IsMobile() then
            return
        end

        local TweenService = EngProject.Utility:GetService("TweenService")
        local UserInputService = EngProject.Utility:GetService("UserInputService")

        local folderName = "Eng Project"
        local fileName = folderName .. "/logo.png"
        local iconUrl = "https://raw.githubusercontent.com/dawnpetal/website/refs/heads/main/assets/images/logo.png"
        local logoAsset

        local canUseFilesystem = makefolder and isfolder and listfiles and isfile and delfile and writefile and
                                     getcustomasset

        if canUseFilesystem then
            if not isfolder(folderName) then
                makefolder(folderName)
            end

            for _, file in ipairs(listfiles("")) do
                local cleanFile = file:gsub("^/", "")
                if cleanFile:lower():find("simpleui") and isfile(cleanFile) then
                    delfile(cleanFile)
                end
            end

            if not isfile(fileName) then
                local success, imageData = pcall(function()
                    return game:HttpGet(iconUrl)
                end)
                if success and imageData then
                    writefile(fileName, imageData)
                end
            end

            logoAsset = getcustomasset(fileName)
        end

        local toggleButton = Instance.new("ImageButton")
        toggleButton.Name = "ToggleUIButton"
        toggleButton.Size = UDim2.new(0, 40, 0, 40)
        toggleButton.Position = UDim2.new(0, 30, 0.5, -20)
        toggleButton.AnchorPoint = Vector2.new(0.5, 0.5)
        toggleButton.BackgroundTransparency = 1
        toggleButton.ImageColor3 = Color3.fromRGB(255, 255, 255)
        toggleButton.ScaleType = Enum.ScaleType.Fit
        toggleButton.Active = true
        toggleButton.Image = logoAsset or "rbxassetid://10734900011"
        toggleButton.Parent = window.Elements.ScreenGui

        local dragging = false
        local dragStart, startPos
        local hasMoved = false
        local normalSize = UDim2.new(0, 40, 0, 40)
        local pressSize = UDim2.new(0, 50, 0, 50)
        local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

        if toggleButton and TweenService then
            toggleButton.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType ==
                    Enum.UserInputType.Touch then
                    dragging = true
                    dragStart = input.Position
                    startPos = toggleButton.Position
                    hasMoved = false
                    TweenService:Create(toggleButton, tweenInfo, {
                        Size = pressSize
                    }):Play()
                end
            end)

            toggleButton.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType ==
                    Enum.UserInputType.Touch then
                    dragging = false
                    TweenService:Create(toggleButton, tweenInfo, {
                        Size = normalSize
                    }):Play()
                    if not hasMoved then
                        if window.IsVisible() then
                            window.Hide()
                        else
                            window.Show()
                        end
                    end
                end
            end)
        end

        if UserInputService then
            UserInputService.InputChanged:Connect(function(input)
                if dragging and
                    (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType ==
                        Enum.UserInputType.Touch) then
                    local delta = input.Position - dragStart
                    if math.abs(delta.X) > 5 or math.abs(delta.Y) > 5 then
                        hasMoved = true
                        toggleButton.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
                            startPos.Y.Scale, startPos.Y.Offset + delta.Y)
                    end
                end
            end)
        end
    end
end

local LegitWaypointReader = {}
do
    LegitWaypointReader.Routes = {
        [tostring(game.PlaceId)] = {
            Default = {
                Dig = {},
                Wash = {},
                Merchant = {}
            }
        }
    }

    local function toPosition(point)
        if typeof(point) == "Vector3" then
            return point
        elseif typeof(point) == "CFrame" then
            return point.Position
        elseif typeof(point) == "table" then
            if point.Position then
                return toPosition(point.Position)
            elseif point.X and point.Y and point.Z then
                return Vector3.new(point.X, point.Y, point.Z)
            end
        end
        return nil
    end

    function LegitWaypointReader:getAreaKey()
        local area = Player:GetAttribute("CurrentArea")
        return area and tostring(area) or "Default"
    end

    function LegitWaypointReader:getAreaRoutes()
        local placeRoutes = self.Routes[tostring(game.PlaceId)] or self.Routes[game.PlaceId] or {}
        local areaKey = self:getAreaKey()
        return placeRoutes[areaKey] or placeRoutes.Default or placeRoutes
    end

    function LegitWaypointReader:getVariants(category)
        local routes = self:getAreaRoutes()
        return routes[category] or routes[string.lower(category)] or {}
    end

    function LegitWaypointReader:buildRoute(category, targetCFrame)
        local variants = self:getVariants(category)
        local selected = {}

        if type(variants) == "table" and #variants > 0 then
            if type(variants[1]) == "table" and not variants[1].X and not variants[1].Position then
                selected = variants[math.random(1, #variants)] or {}
            else
                selected = variants
            end
        end

        local route = {}
        for _, point in ipairs(selected) do
            local position = toPosition(point)
            if position then
                table.insert(route, position)
            end
        end

        table.insert(route, targetCFrame.Position)
        return route
    end
end

_G.scanRegionPos = function(centerPos, targetRegion)
    local ok, PointToRegion = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Location"):WaitForChild("PointToRegion"))
    end)
    if not ok or not PointToRegion then return nil end
    
    -- Multi-stage radial search in 3D: accurate nearby, fast far away
    local stages = {
        {max = 150, step = 15},
        {max = 500, step = 35},
        {max = 1200, step = 60}
    }
    
    for _, stage in ipairs(stages) do
        local r = stage.max
        local step = stage.step
        for dist = 0, r, step do
            for x = -dist, dist, step do
                for z = -dist, dist, step do
                    if math.abs(x) == dist or math.abs(z) == dist then
                        -- Test multiple height offsets (water level vs peak vs cave depth)
                        for _, yOffset in ipairs({0, -10, 10, -30, 30, -60, 60}) do
                            local testPos = centerPos + Vector3.new(x, yOffset, z)
                            local region, _ = PointToRegion.GetPanningRegion(testPos)
                            if region == targetRegion then
                                return CFrame.new(testPos)
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local autoFarmToggle1, autoFarmToggle2
local settingToggleState = false
local function syncToggles(state)
    if settingToggleState then return end
    settingToggleState = true
    if autoFarmToggle1 then
        pcall(function()
            if autoFarmToggle1.Set then
                autoFarmToggle1:Set(state)
            elseif autoFarmToggle1.SetValue then
                autoFarmToggle1:SetValue(state)
            end
        end)
    end
    if autoFarmToggle2 then
        pcall(function()
            if autoFarmToggle2.Set then
                autoFarmToggle2:Set(state)
            elseif autoFarmToggle2.SetValue then
                autoFarmToggle2:SetValue(state)
            end
        end)
    end
    settingToggleState = false
end

local AutoFarmModule = {}
do
    function AutoFarmModule.moveToLocation(targetCFrame, routeType)
        local completed = false
        local success = false

        local targetObj = {
            Position = targetCFrame.Position,
            CFrame = targetCFrame
        }

        local controller

        if State.AutoFarm.travelMode == "Legit" then
            success = Movement.walkToTarget(targetObj, {
                Route = LegitWaypointReader:buildRoute(routeType or "Dig", targetCFrame),
                StopDistance = 5,
                ShouldContinue = function()
                    return State.AutoFarm.active and not State.AutoFarm.interrupted
                end
            })
            completed = true
        elseif State.AutoFarm.travelMode == "Tween" then
            controller = Movement.tweenToTarget(targetObj, {
                CruiseHeight = 4,
                MinHeight = 1,
                MaxHeight = 6,
                LongDistanceThreshold = 100,
                DirectFlightThreshold = 30,
                AdaptiveHeight = false,
                UseDirectFlight = true,
                HoverDuration = 0,
                LandingDuration = 0.3,
                StopDistance = 5,
                OnComplete = function(ok)
                    success = ok or false
                    completed = true
                end
            })
        elseif State.AutoFarm.travelMode == "Visual" then
            success = Movement.pathfindTween(targetCFrame, {
                Speed = State.Speed or 24,
                StopDistance = 8,
                ShouldContinue = function()
                    return State.AutoFarm.active and not State.AutoFarm.interrupted
                end
            })
            completed = true
        else
            Movement.teleportToTarget(targetObj.Position, {
                Mode = "Standard",
                OnComplete = function(ok)
                    success = ok or false
                    completed = true
                end
            })
        end

        local elapsed = 0
        while not completed and elapsed < 45 and State.AutoFarm.active and not State.AutoFarm.interrupted do
            task.wait(0.05)
            elapsed = elapsed + 0.05
        end

        if not completed and controller and controller.stop then
            controller.stop()
        end

        if success and not State.AutoFarm.interrupted then
            CharacterLock.lock(targetCFrame)
            State.AutoFarm.locked = true
        end

        return success and not State.AutoFarm.interrupted
    end

    function AutoFarmModule.doAction(actionType, expectedRegion)
        local ok, result = pcall(function()
            local pan = PanModule.equipPan()
            if not pan then
                return false
            end

            -- Bypass region check to mimic prospecting.lua
            -- if PanModule.getRegion(HumanoidRootPart) ~= expectedRegion then
            --     return false
            -- end

            local killSwitch = function()
                return State.AutoFarm.active and not State.AutoFarm.interrupted
            end

            local r = PanModule.handleAction(State.AutoFarm.actionMode, actionType, true, killSwitch)
            return r ~= "MAX_RETRY_FAIL" and r ~= "KILLED"
        end)

        return ok and result
    end

    function AutoFarmModule.performTask(taskName, nextTask, targetCFrame, actionType, expectedRegion)
        TaskManager:setCurrentTask(taskName)
        TaskManager:setNextTask(nextTask)

        if not AutoFarmModule.moveToLocation(targetCFrame, actionType) then
            return false
        end

        task.wait(0.1)

        if State.AutoFarm.interrupted then
            return false
        end

        TaskManager:setCurrentTask(nextTask or actionType)
        TaskManager:setNextTask("AutoFarm")

        if not AutoFarmModule.doAction(actionType, expectedRegion) then
            return false
        end

        TaskManager:setCurrentTask("AutoFarm")
        return true
    end

    function AutoFarmModule.checkAndDoSell()
        if not State.Sell.autoSell then
            return
        end

        local shouldSell = false
        local mode = State.Sell.type or "Auto"

        if mode == "Auto" then
            shouldSell = SellModule.isBackpackAtCapacity()
        elseif mode == "Threshold" then
            shouldSell = SellModule.getInventoryCount() >= (tonumber(State.Sell.threshold) or 50)
        elseif mode == "Duration" then
            shouldSell = State.Sell._scheduledSell or
                             (os.clock() - (State.Sell._lastSell or 0) >= (tonumber(State.Sell.delay) or 300))
        end

        if shouldSell then
            if SellModule.sell({}, State.Sell.mode or "Teleport") then
                State.Sell._lastSell = os.clock()
                State.Sell._scheduledSell = false

                if Player and Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
                    CharacterLock.lock(Player.Character.HumanoidRootPart.CFrame)
                    State.AutoFarm.locked = true
                end
            end
        end
    end

    function AutoFarmModule.teardown()
        if State.AutoFarm.locked then
            CharacterLock.unlock()
            State.AutoFarm.locked = false
        end

        State.AutoFarm.interrupted = false
        State.AutoFarm.interruptReason = nil

        if TaskManager:getMainTask() == "AutoFarm" then
            TaskManager:finishTask("AutoFarm")
        end

        TaskManager:clearSubTasks()
        State.AutoFarm.running = false
        syncToggles(false)
    end

    function AutoFarmModule.pause(reason)
        if not (State.AutoFarm.active and State.AutoFarm.running) then
            return false
        end

        State.AutoFarm.interrupted = true
        State.AutoFarm.interruptReason = reason or "Pause"

        if State.AutoFarm.locked then
            CharacterLock.unlock()
            State.AutoFarm.locked = false
        end

        return true
    end

    function AutoFarmModule.resume(reason)
        if reason and State.AutoFarm.interruptReason and State.AutoFarm.interruptReason ~= reason then
            return false
        end

        if not State.AutoFarm.interrupted then
            State.AutoFarm.interruptReason = nil
            return false
        end

        State.AutoFarm.interrupted = false
        State.AutoFarm.interruptReason = nil
        return true
    end

    function AutoFarmModule.start()
        if State.AutoFarm.running then
            return
        end

        State.AutoFarm.active = true
        State.AutoFarm.running = true
        State.AutoFarm.interrupted = false
        State.AutoFarm.interruptReason = nil

        local currentArea = Player:GetAttribute("CurrentArea")
        if State.AutoFarm.savedArea ~= currentArea then
            State.AutoFarm.sandCFrame = nil
            State.AutoFarm.waterCFrame = nil
            State.AutoFarm.manualSand = nil
            State.AutoFarm.manualWater = nil
            State.AutoFarm.savedArea = currentArea
        end

        if not State.AutoFarm.travelMode or State.AutoFarm.travelMode == "" then
            Utility.createNotification("❌ Select travel mode!")
            State.AutoFarm.active = false
            State.AutoFarm.running = false
            syncToggles(false)
            return
        end

        if not State.AutoFarm.actionMode or State.AutoFarm.actionMode == "" then
            Utility.createNotification("❌ Select farming mode!")
            State.AutoFarm.active = false
            State.AutoFarm.running = false
            syncToggles(false)
            return
        end

        -- Dynamic location scanning fallback if not set
        local char = Player.Character
        local playerHrp = char and char:FindFirstChild("HumanoidRootPart")
        if playerHrp then
            if not State.AutoFarm.manualSand or not State.AutoFarm.sandCFrame then
                State.AutoFarm.sandCFrame = scanRegionPos(playerHrp.Position, "Deposit")
            end
            if not State.AutoFarm.manualWater or not State.AutoFarm.waterCFrame then
                State.AutoFarm.waterCFrame = scanRegionPos(playerHrp.Position, "Water")
            end
        end

        if not State.AutoFarm.sandCFrame or not State.AutoFarm.waterCFrame then
            -- Retry scan up to 3 times
            for attempt = 1, 3 do
                task.wait(1)
                char = Player.Character
                playerHrp = char and char:FindFirstChild("HumanoidRootPart")
                if playerHrp then
                    if not State.AutoFarm.manualSand or not State.AutoFarm.sandCFrame then
                        State.AutoFarm.sandCFrame = scanRegionPos(playerHrp.Position, "Deposit")
                    end
                    if not State.AutoFarm.manualWater or not State.AutoFarm.waterCFrame then
                        State.AutoFarm.waterCFrame = scanRegionPos(playerHrp.Position, "Water")
                    end
                end
                if State.AutoFarm.sandCFrame and State.AutoFarm.waterCFrame then
                    break
                end
            end
        end

        if not State.AutoFarm.sandCFrame or not State.AutoFarm.waterCFrame then
            Utility.createNotification("❌ Deposit or Water not found! Stopping.", 5)
            State.AutoFarm.active = false
            State.AutoFarm.running = false
            syncToggles(false)
            return
        end

        syncToggles(true)
        Utility.createNotification("🚀 Starting!")

        task.spawn(function()
            while State.AutoFarm.active do
                local acquired = TaskManager:requestTask("AutoFarm", 1)

                if acquired then
                    local hasTurn = TaskManager:waitForTurn("AutoFarm", 5)

                    if hasTurn then
                        local started = TaskManager:startTask("AutoFarm")

                        if started then
                            while State.AutoFarm.active and TaskManager:canRun("AutoFarm") do
                                if State.AutoFarm.interrupted then
                                    if State.AutoFarm.locked then
                                        CharacterLock.unlock()
                                        State.AutoFarm.locked = false
                                    end

                                    while State.AutoFarm.interrupted and State.AutoFarm.active do
                                        task.wait(0.1)
                                    end
                                end

                                local ok = pcall(function()
                                    local panStatus = PanModule.getStatus()
                                    if not panStatus then
                                        task.wait(0.05)
                                        return
                                    end

                                    AutoFarmModule.checkAndDoSell()

                                    local loopChar = Player.Character
                                    local loopHrp = loopChar and loopChar:FindFirstChild("HumanoidRootPart")
                                    if not loopHrp then
                                        task.wait(0.05)
                                        return
                                    end

                                    if panStatus.isFull then
                                        -- Verify / find nearest Water region dynamically!
                                        local targetCFrame = State.AutoFarm.waterCFrame
                                        if not State.AutoFarm.manualWater or State.Quest.autoQuest then
                                            local nearestWater = scanRegionPos(loopHrp.Position, "Water")
                                            if nearestWater then
                                                targetCFrame = nearestWater
                                                State.AutoFarm.waterCFrame = nearestWater
                                            end
                                        end

                                        if not targetCFrame then
                                            Utility.createNotification("❌ No water region found! Stopping Auto Farm.", 5)
                                            State.AutoFarm.active = false
                                            return
                                        end

                                        if not AutoFarmModule.performTask("MovingToWater", "WashPan",
                                            targetCFrame, "Wash", "Water") then
                                            if not State.AutoFarm.interrupted then
                                                State.AutoFarm.active = false
                                            end
                                        end
                                    else
                                        -- Verify / find nearest Deposit region dynamically!
                                        local targetCFrame = State.AutoFarm.sandCFrame
                                        if not State.AutoFarm.manualSand or State.Quest.autoQuest then
                                            local nearestDeposit = scanRegionPos(loopHrp.Position, "Deposit")
                                            if nearestDeposit then
                                                targetCFrame = nearestDeposit
                                                State.AutoFarm.sandCFrame = nearestDeposit
                                            end
                                        end

                                        if not targetCFrame then
                                            Utility.createNotification("❌ No sand deposit found! Stopping Auto Farm.", 5)
                                            State.AutoFarm.active = false
                                            return
                                        end

                                        if not AutoFarmModule.performTask("MovingToSand", "DigSand",
                                            targetCFrame, "Dig", "Deposit") then
                                            if not State.AutoFarm.interrupted then
                                                State.AutoFarm.active = false
                                            end
                                        end
                                    end
                                end)

                                if not ok then
                                    if State.AutoFarm.locked then
                                        CharacterLock.unlock()
                                        State.AutoFarm.locked = false
                                    end
                                    task.wait(0.05)
                                end

                                task.wait(0.01)
                            end

                            TaskManager:finishTask("AutoFarm")
                        else
                            task.wait(0.1)
                        end
                    end
                else
                    task.wait(0.1)
                end
            end

            AutoFarmModule.teardown()
            Utility.createNotification("🛑 Stopped")
        end)
    end

    function AutoFarmModule.stop()
        if not State.AutoFarm.active and not State.AutoFarm.running then
            return
        end
        State.AutoFarm.active = false
        State.AutoFarm.interrupted = false
        State.AutoFarm.interruptReason = nil
        syncToggles(false)
    end
end

local HuntingModule = {}
do
    HuntingModule.geodeState = {
        isOpening = false,
        currentGeode = nil,
        startTime = nil,
        cachedInventoryCount = 0,
        cachedMaxCapacity = 0
    }

    HuntingModule.treasureState = {
        isHunting = false,
        mapsCompleted = 0,
        currentMap = nil,
        currentMapGUID = nil,
        previousShovelName = nil,
        previousShovelGUID = nil,
        startTime = nil
    }

    function HuntingModule.getInventoryCount()
        local count = 0
        local bp = getBackpack()
        if bp then
            for _, item in ipairs(bp:GetChildren()) do
                local t = item:GetAttribute("ItemType")
                if t == "Valuable" or t == "Equipment" then
                    count = count + 1
                end
            end
        end
        local character = Character
        if character then
            local equipped = character:FindFirstChildOfClass("Tool")
            if equipped then
                local t = equipped:GetAttribute("ItemType")
                if t == "Valuable" or t == "Equipment" then
                    count = count + 1
                end
            end
        end
        return count
    end

    function HuntingModule.updateInventoryCache()
        HuntingModule.geodeState.cachedInventoryCount = HuntingModule.getInventoryCount()
        HuntingModule.geodeState.cachedMaxCapacity = Player:GetAttribute("InventorySize") or 100
    end

    function HuntingModule.getCachedInventoryCount()
        return HuntingModule.geodeState.cachedInventoryCount
    end

    function HuntingModule.getCachedMaxCapacity()
        return HuntingModule.geodeState.cachedMaxCapacity
    end

    function HuntingModule.isBackpackFull()
        return HuntingModule.getCachedInventoryCount() >= HuntingModule.getCachedMaxCapacity()
    end

    function HuntingModule.findGeodeInBackpack()
        local bp = getBackpack()
        if bp then
            for _, item in ipairs(bp:GetChildren()) do
                if item.Name == "Geode" then
                    return item
                end
            end
        end
        return nil
    end

    function HuntingModule.isGeodeEquipped()
        if not Character then
            return false
        end
        for _, item in ipairs(Character:GetChildren()) do
            if item:GetAttribute("ItemType") == "Geode" then
                return true
            end
        end
        return false
    end

    function HuntingModule.isGeodeInHotbar()
        for _, item in ipairs(Player.Backpack:GetChildren()) do
            if item.Name == "Geode" then
                return true
            end
        end
        return false
    end

    function HuntingModule.waitForGeodeInCharacter(timeout)
        timeout = timeout or 50
        if not Character then
            return false
        end
        local elapsed = 0
        while elapsed < timeout do
            for _, item in ipairs(Character:GetChildren()) do
                if item:GetAttribute("ItemType") == "Geode" then
                    return true
                end
            end
            task.wait(0.01)
            elapsed = elapsed + 1
        end
        return false
    end

    function HuntingModule.isGeodeDepleted()
        if not Character then
            return true
        end
        for _, item in ipairs(Character:GetChildren()) do
            if item:GetAttribute("ItemType") == "Geode" then
                local stacks = item:GetAttribute("Stacks")
                if stacks and stacks > 0 then
                    return false
                end
            end
        end
        return true
    end

    function HuntingModule.waitForGeodes(maxWait)
        maxWait = maxWait or 30
        local elapsed = 0
        while elapsed < maxWait do
            if HuntingModule.findGeodeInBackpack() ~= nil then
                return true
            end
            task.wait(0.5)
            elapsed = elapsed + 0.5
        end
        return false
    end

    function HuntingModule.startGeodeOpening()
        if HuntingModule.geodeState.isOpening then
            return false
        end

        local geode = HuntingModule.findGeodeInBackpack()
        if not geode and not HuntingModule.isGeodeEquipped() and not HuntingModule.isGeodeInHotbar() then
            return false
        end

        HuntingModule.updateInventoryCache()
        HuntingModule.geodeState.isOpening = true
        HuntingModule.geodeState.startTime = tick()

        task.spawn(function()
            while HuntingModule.geodeState.isOpening do
                if HuntingModule.isBackpackFull() then
                    break
                end

                local geode = HuntingModule.findGeodeInBackpack()
                if not geode then
                    break
                end

                pcall(function()
                    ReplicatedStorage.Remotes.CustomBackpack.EquipRemote:FireServer(geode)
                end)

                if not HuntingModule.waitForGeodeInCharacter() then
                    break
                end

                local clickCount = 0
                while HuntingModule.geodeState.isOpening do
                    if HuntingModule.isGeodeDepleted() or HuntingModule.isBackpackFull() then
                        break
                    end
                    Services.VirtualUser:ClickButton1(Vector2.new(math.random(100, 900), math.random(100, 700)))
                    clickCount = clickCount + 1
                    if clickCount % 100 == 0 then
                        HuntingModule.updateInventoryCache()
                    end
                    task.wait(0.01)
                end
            end

            HuntingModule.geodeState.isOpening = false
            HuntingModule.geodeState.currentGeode = nil
        end)

        return true
    end

    function HuntingModule.stopGeodeOpening()
        HuntingModule.geodeState.isOpening = false
    end

    function HuntingModule.isGeodeOpening()
        return HuntingModule.geodeState.isOpening
    end

    function HuntingModule.getFormattedInventoryStatus()
        local toolUI = Player.PlayerGui:FindFirstChild("ToolUI")
        if toolUI then
            local fillingPan = toolUI:FindFirstChild("FillingPan")
            if fillingPan then
                local inventorySpace = fillingPan:FindFirstChild("InventorySpace")
                if inventorySpace and inventorySpace:IsA("TextLabel") then
                    return inventorySpace.Text
                end
            end
        end
        return "Inventory: N/A"
    end

    function HuntingModule.getPan()
        if not Character then
            return nil
        end
        local equipped = Character:FindFirstChildOfClass("Tool")
        if equipped and equipped:GetAttribute("ItemType") == "Pan" then
            return equipped
        end
        local bp = getBackpack()
        if bp then
            for _, v in ipairs(bp:GetChildren()) do
                if v:GetAttribute("ItemType") == "Pan" then
                    ReplicatedStorage.Remotes.CustomBackpack.EquipRemote:FireServer(v)
                    task.wait(0.5)
                    return v
                end
            end
        end
        return nil
    end

    function HuntingModule.findNextMap()
        local containers = {}
        local bp = getBackpack()
        if bp then table.insert(containers, bp) end
        if Character then table.insert(containers, Character) end
        for _, container in ipairs(containers) do
            if container then
                for _, v in ipairs(container:GetChildren()) do
                    local name = v.Name:lower()
                    if v:GetAttribute("ItemType") == "TreasureMap" or (name:find("treasure") and name:find("map")) then
                        return v
                    end
                end
            end
        end
        return nil
    end

    function HuntingModule.findTool(predicate)
        local containers = {}
        if Character then table.insert(containers, Character) end
        local bp = getBackpack()
        if bp then table.insert(containers, bp) end
        for _, container in ipairs(containers) do
            if container then
                for _, item in ipairs(container:GetChildren()) do
                    if item:IsA("Tool") and predicate(item) then
                        return item
                    end
                end
            end
        end
        return nil
    end

    function HuntingModule.equipTool(tool)
        if not tool then
            return false
        end

        if tool.Parent == Character then
            return true
        end

        ReplicatedStorage.Remotes.CustomBackpack.EquipRemote:FireServer(tool)
        
        local start = tick()
        while tool.Parent ~= Character and (tick() - start) < 2.5 do
            task.wait(0.05)
        end

        return tool.Parent == Character
    end

    function HuntingModule.getEquippedShovel()
        if not Character then
            return nil
        end

        local equipped = Character:FindFirstChildOfClass("Tool")
        if equipped and (equipped:GetAttribute("ItemType") == "Shovel" or equipped.Name:find("Shovel")) then
            return equipped
        end
        return nil
    end

    function HuntingModule.storeCurrentShovel()
        local shovel = HuntingModule.getEquippedShovel()
        HuntingModule.treasureState.previousShovelName = shovel and shovel.Name or nil
        HuntingModule.treasureState.previousShovelGUID = shovel and shovel:GetAttribute("GUID") or nil
    end

    function HuntingModule.restoreStoredShovel()
        local guid = HuntingModule.treasureState.previousShovelGUID
        local name = HuntingModule.treasureState.previousShovelName

        if not guid and not name then
            return false
        end

        local shovel = HuntingModule.findTool(function(tool)
            return tool:GetAttribute("ItemType") == "Shovel" and
                       ((guid and tool:GetAttribute("GUID") == guid) or (name and tool.Name == name))
        end)

        HuntingModule.treasureState.previousShovelName = nil
        HuntingModule.treasureState.previousShovelGUID = nil
        return HuntingModule.equipTool(shovel)
    end

    function HuntingModule.prepareTreasureTool()
        HuntingModule.storeCurrentShovel()

        local shovel = HuntingModule.findTool(function(tool)
            return tool:GetAttribute("ItemType") == "Shovel" or tool.Name:find("Shovel")
        end)

        if shovel then
            HuntingModule.equipTool(shovel)
            return shovel
        end

        return HuntingModule.getPan()
    end

    function HuntingModule.getTreasureCollectTool()
        local shovel = HuntingModule.findTool(function(tool)
            return tool:GetAttribute("ItemType") == "Shovel" or tool.Name:find("Shovel")
        end)

        if shovel and shovel.Parent ~= Character then
            HuntingModule.equipTool(shovel)
        end

        local equipped = Character and Character:FindFirstChildOfClass("Tool") or nil
        if equipped and equipped:FindFirstChild("Scripts") and equipped.Scripts:FindFirstChild("Collect") then
            return equipped
        end

        return HuntingModule.getPan()
    end

    function HuntingModule.huntSingleMap(map)
        if not map or not map.Parent then
            return false
        end

        local location = map:GetAttribute("Location")
        local mapGUID = map:GetAttribute("GUID")

        if not location or not mapGUID then
            local bp = getBackpack()
            if bp then
                for _, v in ipairs(bp:GetChildren()) do
                    local name = v.Name:lower()
                    if v:GetAttribute("ItemType") == "TreasureMap" or (name:find("treasure") and name:find("map")) then
                        local loc = v:GetAttribute("Location")
                        local guid = v:GetAttribute("GUID")
                        if loc and guid then
                            location = loc
                            mapGUID = guid
                            map = v
                            break
                        end
                    end
                end
            end
        end

        if not location or not mapGUID then
            return false
        end

        local treasureTool = HuntingModule.getTreasureCollectTool()
        if not treasureTool then
            return false
        end

        local targetCFrame = typeof(location) == "CFrame" and location or CFrame.new(location)
        local collect = treasureTool:FindFirstChild("Scripts") and treasureTool.Scripts:FindFirstChild("Collect")

        if not collect then
            return false
        end

        local startTime = tick()
        local timeout = 120
        local lastCollectTime = 0

        local function findMapInContainers(mapName, guid)
            local containers = {}
            if Character then table.insert(containers, Character) end
            local bp = getBackpack()
            if bp then table.insert(containers, bp) end
            for _, container in ipairs(containers) do
                if container then
                    for _, v in ipairs(container:GetChildren()) do
                        local name = v.Name:lower()
                        local isMap = v:GetAttribute("ItemType") == "TreasureMap" or (name:find("treasure") and name:find("map"))
                        if isMap then
                            local vGUID = v:GetAttribute("GUID")
                            if guid and vGUID and vGUID == guid then
                                return v
                            end
                            if not guid or not vGUID then
                                return v
                            end
                        end
                    end
                end
            end
            return nil
        end

        local attempts = 0
        while HuntingModule.treasureState.isHunting and (tick() - startTime) < timeout do
            local currentMap = findMapInContainers(map.Name, mapGUID)

            if not currentMap then
                task.wait(0.5)
                return true
            end

            if currentMap:GetAttribute("GUID") ~= mapGUID then
                task.wait(0.5)
                return true
            end

            if not Character or not Character:FindFirstChild("HumanoidRootPart") then
                break
            end

            Character.HumanoidRootPart.CFrame = targetCFrame

            if tick() - lastCollectTime > 0.02 then
                pcall(function()
                    collect:InvokeServer(0)
                end)
                lastCollectTime = tick()
                attempts = attempts + 1
                if attempts > 150 then
                    local mapNameDisplay = map.Name:gsub(" Treasure Map", "")
                    EngProject:CreateNotification({
                        Type = "Warning",
                        Title = "Wrong Map / Region",
                        Description = "This treasure map belongs to another region. Please travel to " .. mapNameDisplay .. " to hunt it!",
                        Duration = 8
                    })
                    break
                end
            end

            task.wait(0.01)
        end

        return false
    end

    function HuntingModule.startTreasureHunting(options)
        options = options or {}
        if HuntingModule.treasureState.isHunting then
            return false
        end

        HuntingModule.treasureState.isHunting = true
        if not options.PreserveCount then
            HuntingModule.treasureState.mapsCompleted = 0
        end
        HuntingModule.treasureState.currentMap = nil
        HuntingModule.treasureState.currentMapGUID = nil
        HuntingModule.treasureState.startTime = tick()
        HuntingModule.prepareTreasureTool()

        task.spawn(function()
            while HuntingModule.treasureState.isHunting do
                local map = HuntingModule.findNextMap()
                if not map then
                    break
                end

                HuntingModule.treasureState.currentMap = map.Name
                HuntingModule.treasureState.currentMapGUID = map:GetAttribute("GUID")

                local success = HuntingModule.huntSingleMap(map)

                if success then
                    HuntingModule.treasureState.mapsCompleted = HuntingModule.treasureState.mapsCompleted + 1
                    task.wait(1)
                else
                    break
                end
            end

            HuntingModule.treasureState.isHunting = false
            HuntingModule.treasureState.currentMap = nil
            HuntingModule.treasureState.currentMapGUID = nil
            HuntingModule.restoreStoredShovel()
        end)

        return true
    end

    function HuntingModule.stopTreasureHunting()
        HuntingModule.treasureState.isHunting = false
        HuntingModule.treasureState.currentMap = nil
        HuntingModule.treasureState.currentMapGUID = nil
    end

    function HuntingModule.isTreasureHunting()
        return HuntingModule.treasureState.isHunting
    end

    function HuntingModule.getTreasureHuntStatus()
        return {
            isHunting = HuntingModule.treasureState.isHunting,
            mapsCompleted = HuntingModule.treasureState.mapsCompleted,
            currentMap = HuntingModule.treasureState.currentMap,
            currentMapGUID = HuntingModule.treasureState.currentMapGUID,
            duration = HuntingModule.treasureState.startTime and (tick() - HuntingModule.treasureState.startTime) or 0
        }
    end
end

local ServerUtilityModule = {}
do
    function ServerUtilityModule.rejoin()
        if #Services.Players:GetPlayers() <= 1 then
            Player:Kick("Rejoining...")
            task.wait()
            Services.TeleportService:Teleport(game.PlaceId, Player)
        else
            Services.TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, Player)
        end
    end

    function ServerUtilityModule.serverHop()
        local servers = {}
        local req = Services.HttpService:JSONDecode(game:HttpGet(
            "https://games.roblox.com/v1/games/" .. game.PlaceId ..
                "/servers/Public?sortOrder=Desc&limit=100&excludeFullGames=true"))

        for _, v in pairs(req.data or {}) do
            if v.id ~= game.JobId and v.playing < v.maxPlayers then
                table.insert(servers, v.id)
            end
        end

        if #servers > 0 then
            Services.TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[math.random(#servers)], Player)
        else
            Utility.createNotification("No available servers found", 4)
        end
    end

    function ServerUtilityModule.setupAntiAFK(enabled)
        -- Hardcode: use ALL available methods simultaneously for maximum reliability
        local GC = getconnections or get_signal_cons
        local VU = cloneref and cloneref(game:GetService("VirtualUser")) or game:GetService("VirtualUser")

        -- Cleanup previous connections
        if getgenv().AntiAFKConnection then
            pcall(function() getgenv().AntiAFKConnection:Disconnect() end)
            getgenv().AntiAFKConnection = nil
        end
        if getgenv().AntiAFKHeartbeat then
            pcall(function() getgenv().AntiAFKHeartbeat:Disconnect() end)
            getgenv().AntiAFKHeartbeat = nil
        end
        getgenv().AntiAFKActive = false

        if enabled then
            getgenv().AntiAFKActive = true

            -- Method 1: Disable all Idled listeners (getconnections)
            if GC then
                pcall(function()
                    for _, c in pairs(GC(Player.Idled)) do
                        if c.Disable then pcall(function() c:Disable() end) end
                        if c.Disconnect then pcall(function() c:Disconnect() end) end
                    end
                end)
            end

            -- Method 2: Connect to Idled signal and cancel it
            getgenv().AntiAFKConnection = Player.Idled:Connect(function()
                pcall(function()
                    VU:CaptureController()
                    VU:ClickButton2(Vector2.new())
                end)
            end)

            -- Method 3: Hardcode background loop — click every 4.5 min to prevent 5-min idle
            task.spawn(function()
                while getgenv().AntiAFKActive do
                    task.wait(270) -- 4.5 minutes
                    if not getgenv().AntiAFKActive then break end
                    pcall(function()
                        VU:CaptureController()
                        VU:ClickButton1(Vector2.new(512, 400))
                        task.wait(0.05)
                        VU:ClickButton2(Vector2.new(512, 400))
                        -- Wiggle character to reset idle timer server-side
                        local char = Player.Character
                        local hum = char and char:FindFirstChildOfClass("Humanoid")
                        if hum then
                            hum.Jump = true
                            task.wait(0.1)
                            hum.Jump = false
                        end
                    end)
                end
            end)
        end
    end
end

local WaypointModule = {}
do
    function WaypointModule.getList()
        local waypointFolder = Map:FindFirstChild("Waypoints")
        if not waypointFolder then
            return {}
        end

        local waypoints = {}
        for _, wp in pairs(waypointFolder:GetChildren()) do
            if wp:IsA("Model") then
                table.insert(waypoints, wp.Name)
            end
        end

        return waypoints
    end

    function WaypointModule.teleport(selection)
        local waypointFolder = Map:FindFirstChild("Waypoints")
        if not waypointFolder then
            return
        end

        local attr = Player:GetAttribute("CurrentArea")
        local currentWaypoint = nil

        for _, w in pairs(waypointFolder:GetChildren()) do
            if string.find(string.lower(attr), string.lower(w.Name)) then
                currentWaypoint = w
                break
            end
        end

        currentWaypoint = currentWaypoint or waypointFolder["Museum"]
        local targetWaypoint = waypointFolder:FindFirstChild(selection)

        if currentWaypoint and targetWaypoint then
            ReplicatedStorage.Remotes.Misc.FastTravel:FireServer(currentWaypoint, targetWaypoint)
        end
    end

    function WaypointModule.unlockAll()
        if not fireproximityprompt then
            return EngProject:CreateNotification({
                Title = "Not supported",
                Type = "Error",
                Description = "Your exploit does not support fireproximityprompt",
                Duration = 4
            })
        end

        local waypointFolder = Map:FindFirstChild("Waypoints")
        if not waypointFolder then
            return
        end

        local waypoints = waypointFolder:GetChildren()
        local FastTravelDataRemote = ReplicatedStorage.Remotes.Misc.GetFastTravelData
        local unlocked = {}

        FastTravelDataRemote.OnClientEvent:Connect(function(data)
            unlocked = data
        end)

        FastTravelDataRemote:FireServer()

        local function unlock(model)
            local prompt = model:FindFirstChild("WaypointPrompt", true)
            if not prompt then
                return
            end

            while unlocked[model.Name] ~= true do
                HumanoidRootPart.CFrame = model:GetPivot() + Vector3.new(0, 5, 0)
                fireproximityprompt(prompt)
                Services.RunService.Heartbeat:Wait()
            end
        end

        task.spawn(function()
            while true do
                for _, model in ipairs(waypoints) do
                    if not unlocked[model.Name] then
                        unlock(model)
                    end
                end

                task.wait(1)
                FastTravelDataRemote:FireServer()

                if next(unlocked) and not table.find(unlocked, false) then
                    break
                end
            end
        end)
    end
end

local BarrierRemovalModule = {}
do
    BarrierRemovalModule._states = {}

    local function rememberPart(cache, part)
        if cache[part] then
            return
        end

        cache[part] = {
            CanCollide = part.CanCollide,
            CanTouch = part.CanTouch,
            CanQuery = part.CanQuery,
            Transparency = part.Transparency
        }
    end

    function BarrierRemovalModule.getVines()
        return Map and Map:FindFirstChild("LushCaverns") and Map.LushCaverns:FindFirstChild("Vines")
    end

    function BarrierRemovalModule.getAbyssalGate()
        local abyssAssets = Map and Map:FindFirstChild("LushCaverns") and Map.LushCaverns:FindFirstChild("AbyssAssets")
        return abyssAssets and abyssAssets:FindFirstChild("Gate")
    end

    function BarrierRemovalModule.getMountainBlock()
        local mountains = Map and Map:FindFirstChild("Mountains")
        local added = mountains and mountains:FindFirstChild("Added")
        return added and added:FindFirstChild("GateBlockScript") and added.GateBlockScript:FindFirstChild("GateBlockage")
    end

    function BarrierRemovalModule.setBarrierEnabled(key, root, enabled)
        if not root then
            return false
        end

        local cache = BarrierRemovalModule._states[key] or {}
        BarrierRemovalModule._states[key] = cache

        local objects = root:IsA("BasePart") and {root} or root:GetDescendants()
        for _, object in ipairs(objects) do
            if object:IsA("BasePart") then
                if enabled then
                    local saved = cache[object]
                    if saved then
                        object.CanCollide = saved.CanCollide
                        object.CanTouch = saved.CanTouch
                        object.CanQuery = saved.CanQuery
                        object.Transparency = saved.Transparency
                    end
                else
                    rememberPart(cache, object)
                    object.CanCollide = false
                    object.CanTouch = false
                    object.CanQuery = false
                    object.Transparency = math.max(object.Transparency, 0.75)
                end
            end
        end

        if enabled then
            for part in pairs(cache) do
                if not part.Parent then
                    cache[part] = nil
                end
            end
        end

        return true
    end

    function BarrierRemovalModule.toggleVines(disabled)
        return BarrierRemovalModule.setBarrierEnabled("vines", BarrierRemovalModule.getVines(), not disabled)
    end

    function BarrierRemovalModule.toggleAbyssalGate(disabled)
        return BarrierRemovalModule.setBarrierEnabled("abyssalGate", BarrierRemovalModule.getAbyssalGate(), not disabled)
    end

    function BarrierRemovalModule.toggleMountainBlock(disabled)
        return BarrierRemovalModule.setBarrierEnabled("peakObstruction", BarrierRemovalModule.getMountainBlock(),
            not disabled)
    end

    function BarrierRemovalModule.removeCrocodiles()
        local crocsFolder = Map and Map:FindFirstChild("Crocodiles")
        if crocsFolder then
            crocsFolder:Destroy()
            Utility.createNotification("Crocodiles removed!")
            return
        end
        Utility.createNotification("Crocodiles not found, already removed?")
    end
end

local TravelMerchantModule = {}
do
    TravelMerchantModule.running = false
    TravelMerchantModule.selectedItems = {}
    TravelMerchantModule.totalBought = 0
    TravelMerchantModule.restockBindable = nil

    -- HARDCODE: Lazy remote resolution — find at call time, not at load time
    local function getBuyItemRemote()
        -- Hardcoded path: ReplicatedStorage.Remotes.Shop.BuyItem
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if not remotes then return nil end
        local shop = remotes:FindFirstChild("Shop")
        if not shop then return nil end
        return shop:FindFirstChild("BuyItem")
    end

    TravelMerchantModule.KnownItems = {
        "Blessed Enchant Book",
        "Boosting Enchant Book",
        "Cosmic Enchant Book",
        "Destructive Enchant Book",
        "Gigantic Enchant Book",
        "Glowing Enchant Book",
        "Greedy Enchant Book",
        "Infernal Enchant Book",
        "Midas Enchant Book",
        "Prismatic Enchant Book",
        "Titanic Enchant Book",
        "Unstable Enchant Book",
        "Meteor Shower Token",
        "Rapid Rivers Token",
        "Solar Token",
        "Perfect Reforge Ticket",
        "Perfect Reforge Token",
        "Traveler's Backpack",
        "Warp Device",
        "Meteor Fragment",
        "Instability Potion",
        "Quake Potion",
    }

    -- Robust shop item finder — scans all descendants of Workspace (all map scanner method)
    function TravelMerchantModule.getShopItem(itemName)
        local lowerItemName = itemName:lower()
        -- Scan all descendants of Workspace
        for _, desc in ipairs(Services.Workspace:GetDescendants()) do
            local isMatch = false
            if desc.Name:lower() == lowerItemName then
                isMatch = true
            elseif desc:GetAttribute("ItemName") and desc:GetAttribute("ItemName"):lower() == lowerItemName then
                isMatch = true
            end

            if isMatch then
                -- Check if it is the shop item itself or has the purchase attributes
                if desc:GetAttribute("Price") ~= nil or desc:GetAttribute("ShardPrice") ~= nil or desc:GetAttribute("MerchantBaseStock") ~= nil then
                    return desc
                end

                -- Check if it has a ShopItem child
                local si = desc:FindFirstChild("ShopItem")
                if si then return si end

                -- Check descendants of this matched object for buy attributes
                for _, ch in ipairs(desc:GetChildren()) do
                    if ch:GetAttribute("Price") ~= nil or ch:GetAttribute("ShardPrice") ~= nil or ch:GetAttribute("MerchantBaseStock") ~= nil then
                        return ch
                    end
                end
            end

            -- Also check if the object is named "ShopItem" and its parent matches or it has attribute matching itemName
            if desc.Name == "ShopItem" then
                if desc:GetAttribute("ItemName") and desc:GetAttribute("ItemName"):lower() == lowerItemName then
                    return desc
                elseif desc.Parent and desc.Parent.Name:lower() == lowerItemName then
                    return desc
                end
            end
        end

        -- Fallback: check if we can find any child of Workspace.Purchasable
        local purchasable = Services.Workspace:FindFirstChild("Purchasable")
        if purchasable then
            local item = purchasable:FindFirstChild(itemName)
            if item then return item:FindFirstChild("ShopItem") or item end
        end

        return nil
    end

    function TravelMerchantModule.getItemCurrency(shopItem)
        if not shopItem then return "Unknown" end
        if shopItem:GetAttribute("Price") then return "Money" end
        if shopItem:GetAttribute("ShardPrice") then return "Shard" end
        return "Unknown"
    end

    function TravelMerchantModule.matchesFilter(shopItem, useMoney, useShard)
        if not shopItem then return false end
        local hasPrice = shopItem:GetAttribute("Price") ~= nil
        local hasShard = shopItem:GetAttribute("ShardPrice") ~= nil
        -- If neither attribute found, allow buying anyway (hardcode: be permissive)
        if not hasPrice and not hasShard then return true end
        if useMoney and hasPrice then return true end
        if useShard and hasShard then return true end
        return false
    end

    -- HARDCODE: Buy without depending on MerchantBaseStock attribute
    -- Detects success by inventory count change OR stock attribute change
    function TravelMerchantModule.buyAndValidate(itemName, useMoney, useShard)
        local shopItem = TravelMerchantModule.getShopItem(itemName)
        if not shopItem then return false, "not_found" end

        -- HARDCODE: Check stock if attribute exists, but don't block if attribute is missing
        local stock = shopItem:GetAttribute("MerchantBaseStock")
        if stock ~= nil and stock <= 0 then return false, "no_stock" end

        if not TravelMerchantModule.matchesFilter(shopItem, useMoney, useShard) then
            return false, "filter_mismatch"
        end

        local BuyItemRemote = getBuyItemRemote()
        if not BuyItemRemote then return false, "no_remote" end

        -- Snapshot inventory count before buying
        local invBefore = 0
        pcall(function()
            local bp = Player:FindFirstChild("BackpackTwo") or Player:FindFirstChild("Backpack")
            if bp then invBefore = #bp:GetChildren() end
        end)
        local stockBefore = stock or 0

        -- HARDCODE: Fire the remote — try InvokeServer then FireServer as fallback
        local ok, result = pcall(function()
            return BuyItemRemote:InvokeServer(shopItem, 1)
        end)
        if not ok then
            -- Fallback: try FireServer
            pcall(function() BuyItemRemote:FireServer(shopItem, 1) end)
        end

        task.wait(0.6)

        -- Confirm by stock attribute change
        local stockAfter = shopItem:GetAttribute("MerchantBaseStock")
        if stockAfter ~= nil and stockBefore ~= nil and stockAfter < stockBefore then
            return true, "confirmed_stock"
        end

        -- Confirm by inventory count change
        local invAfter = 0
        pcall(function()
            local bp = Player:FindFirstChild("BackpackTwo") or Player:FindFirstChild("Backpack")
            if bp then invAfter = #bp:GetChildren() end
        end)
        if invAfter > invBefore then
            return true, "confirmed_inv"
        end

        -- If stock attribute doesn't exist, assume success if remote didn't error
        if ok and stock == nil then
            return true, "assumed_ok"
        end

        return false, "stock_unchanged"
    end

    function TravelMerchantModule.waitForRestock()
        local bindable = Instance.new("BindableEvent")
        TravelMerchantModule.restockBindable = bindable
        local connections = {}

        local function onRestock()
            if TravelMerchantModule.restockBindable then
                bindable:Fire()
            end
        end

        -- Listen for attribute changes on all selected items' ShopItems
        for _, itemName in ipairs(TravelMerchantModule.selectedItems) do
            local shopItem = TravelMerchantModule.getShopItem(itemName)
            if shopItem then
                local conn = shopItem:GetAttributeChangedSignal("MerchantBaseStock"):Connect(function()
                    local newStock = shopItem:GetAttribute("MerchantBaseStock") or 0
                    if newStock > 0 then onRestock() end
                end)
                table.insert(connections, conn)
            end
        end

        -- Watch Workspace for new shop items/descendants (merchant spawned/restocked)
        local descConn = Services.Workspace.DescendantAdded:Connect(function(desc)
            local nameLower = desc.Name:lower()
            if nameLower:find("shop") or nameLower:find("merchant") then
                task.wait(0.5)
                onRestock()
            else
                for _, itemName in ipairs(TravelMerchantModule.selectedItems) do
                    if nameLower:find(itemName:lower(), 1, true) then
                        task.wait(0.5)
                        onRestock()
                        break
                    end
                end
            end
        end)
        table.insert(connections, descConn)

        -- HARDCODE: Timeout after 5 minutes regardless (don't wait forever)
        task.spawn(function()
            task.wait(300)
            onRestock()
        end)

        bindable.Event:Wait()
        for _, conn in ipairs(connections) do
            pcall(function() conn:Disconnect() end)
        end
        pcall(function() bindable:Destroy() end)
        TravelMerchantModule.restockBindable = nil
    end
end

local SummerModule = {}
do
    local AddCauldronItem = ReplicatedStorage:FindFirstChild("Remotes")
        and ReplicatedStorage.Remotes:FindFirstChild("TemporaryEvents")
        and ReplicatedStorage.Remotes.TemporaryEvents:FindFirstChild("AddCauldronItem")

    local UpdateCauldronData = ReplicatedStorage:FindFirstChild("Remotes")
        and ReplicatedStorage.Remotes:FindFirstChild("TemporaryEvents")
        and ReplicatedStorage.Remotes.TemporaryEvents:FindFirstChild("UpdateCauldronData")

    local ClaimCauldron = ReplicatedStorage:FindFirstChild("Remotes")
        and ReplicatedStorage.Remotes:FindFirstChild("TemporaryEvents")
        and ReplicatedStorage.Remotes.TemporaryEvents:FindFirstChild("ClaimCauldron")

    SummerModule.ModifierPriority = {"Hearthflame", "Tidal", "Summer"}
    SummerModule.RarityPriority = {"Exotic", "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common"}

    function SummerModule.getAllRarities()
        local rMod = require(ReplicatedStorage.GameInfo.Rarities)
        local rarities = {}
        local seen = {}
        for _, item in ipairs(ReplicatedStorage.Items.Valuables:GetChildren()) do
            local r = item:GetAttribute("Rarity")
            if r and not seen[r] then
                seen[r] = true
                table.insert(rarities, r)
            end
        end
        table.sort(rarities, function(a, b)
            return (rMod.Rank[a] or 0) > (rMod.Rank[b] or 0)
        end)
        return rarities
    end

    local function isInList(list, value)
        for _, v in ipairs(list) do
            if v == value then return true end
        end
        return false
    end

    function SummerModule.summerEquipTool(tool)
        local equipRemote = ReplicatedStorage:FindFirstChild("Remotes")
            and ReplicatedStorage.Remotes:FindFirstChild("CustomBackpack")
            and ReplicatedStorage.Remotes.CustomBackpack:FindFirstChild("EquipRemote")

        if equipRemote then
            pcall(function()
                equipRemote:FireServer(tool)
            end)
        else
            local character = Player.Character
            if not character then return false end
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if not humanoid then return false end
            pcall(function() humanoid:EquipTool(tool) end)
        end

        task.wait(0.5)
        local character = Player.Character
        if not character then return false end
        return character:FindFirstChild(tool.Name) ~= nil
    end

    function SummerModule.findBestToolByPriority()
        local bp = getBackpack()
        if not bp then return nil, nil, nil end

        local Valuables = ReplicatedStorage.Items.Valuables

        for _, modifier in ipairs(SummerModule.ModifierPriority) do
            if not isInList(State.Summer.selectedModifiers, modifier) then continue end

            for _, rarity in ipairs(SummerModule.RarityPriority) do
                if not isInList(State.Summer.selectedRarities, rarity) then continue end

                for _, tool in ipairs(bp:GetChildren()) do
                    if tool:IsA("Tool") then
                        local itemData = tool:FindFirstChild("ItemData")
                        local mod = (itemData and itemData:GetAttribute("Modifier"))
                            or tool:GetAttribute("Modifier")

                        if mod == modifier then
                            local valuable = Valuables:FindFirstChild(tool.Name)
                            if valuable and valuable:GetAttribute("Rarity") == rarity then
                                return tool, modifier, rarity
                            end
                        end
                    end
                end
            end
        end
        return nil, nil, nil
    end

    function SummerModule.countAllMatchingTools()
        local bp = getBackpack()
        if not bp then return 0 end

        local Valuables = ReplicatedStorage.Items.Valuables
        local count = 0

        for _, tool in ipairs(bp:GetChildren()) do
            if tool:IsA("Tool") then
                local itemData = tool:FindFirstChild("ItemData")
                local mod = (itemData and itemData:GetAttribute("Modifier"))
                    or tool:GetAttribute("Modifier")

                if isInList(State.Summer.selectedModifiers, mod) then
                    local valuable = Valuables:FindFirstChild(tool.Name)
                    local rarity = valuable and valuable:GetAttribute("Rarity")
                    if rarity and isInList(State.Summer.selectedRarities, rarity) then
                        count = count + 1
                    end
                end
            end
        end
        return count
    end

    function SummerModule.init()
        if UpdateCauldronData then
            UpdateCauldronData.OnClientEvent:Connect(function(progress, quality, deliveryTime)
                State.Summer.progress = progress or 0
                State.Summer.quality = quality or 0
                State.Summer.deliveryTime = deliveryTime or 0
            end)

            task.spawn(function()
                repeat task.wait(1) until Player:GetAttribute("DataLoaded")
                UpdateCauldronData:FireServer()
            end)
        end
    end
end


local AutoQuestModule = {}
do
    local running = false
    local questThread = nil
    
    local ItemToWaypoint = {
        ["amethyst"] = "Crystal Cavern",
        ["crystal"] = "Crystal Cavern",
        ["gold"] = "Fortune River",
        ["obsidian"] = "Volcano",
        ["dragon"] = "Volcano",
        ["fossil"] = "Windswept Beach",
        ["ammonite"] = "Windswept Beach",
        ["amber"] = "Fungal Marsh",
        ["swamp"] = "Rotwood Swamp",
        ["cinnabar"] = "Volcano",
        ["ice"] = "Frozen Peak",
        ["glacial"] = "Frozen Peak",
        ["sand"] = "Rubble Creek",
        ["dollar"] = "Fortune River",
        
        -- Additional items / ores mappings for Prospecting!
        ["silver"] = "Sunset Beach",
        ["copper"] = "Crystal Cavern",
        ["pyrite"] = "Rubble Creek",
        ["platinum"] = "Rubble Creek",
        ["seashell"] = "Sunset Beach",
        ["pearl"] = "Sunset Beach",
        ["blue ice"] = "Frozen Peak",
        ["titanium"] = "Rubble Creek",
        ["neodymium"] = "Rubble Creek",
        ["topaz"] = "Rubble Creek",
        ["nickel"] = "Starfall River",
        ["ruby"] = "Crystal Cavern",
        ["sapphire"] = "Sunset Beach",
        ["diamond"] = "Crystal Cavern",
        ["emerald"] = "Fortune River",
        ["uranium"] = "Overgrown Grotto",
        ["sulfur"] = "Volcano",
        ["meteor"] = "Meteor Valley",
        ["starfall"] = "Starfall River",

        -- Missing/New Minerals
        ["starpiercer"] = "Meteor Falls",
        ["singularium"] = "Starfall River",
        ["celestium"] = "Astral Caverns",
        ["cryonic"] = "Frozen Peak",
        ["umbrite"] = "Abyssal Depths",
        ["malachite"] = "Crystal Caverns",
        ["astral spore"] = "Fungal Marsh",
        ["bloodstone"] = "Rotwood Swamp",
        ["voidstone"] = "The Void",
        ["dinosaur skull"] = "Infernal Heart",
        ["vineheart"] = "Deeproot Spring"
    }

    local MineralDifficulty = {
        ["sand"] = 1, ["fossil"] = 1, ["ammonite"] = 1, ["seashell"] = 1, ["pearl"] = 1, ["dollar"] = 1,
        ["copper"] = 2, ["pyrite"] = 2, ["gold"] = 2, ["amethyst"] = 2, ["crystal"] = 2, ["malachite"] = 2, ["silver"] = 2, ["amber"] = 2, ["swamp"] = 2,
        ["platinum"] = 3, ["blue ice"] = 3, ["ice"] = 3, ["glacial"] = 3, ["titanium"] = 3, ["neodymium"] = 3, ["topaz"] = 3, ["nickel"] = 3, ["ruby"] = 3, ["sapphire"] = 3, ["diamond"] = 3, ["emerald"] = 3, ["sulfur"] = 3,
        ["uranium"] = 4, ["meteor"] = 4, ["starfall"] = 4, ["starpiercer"] = 4, ["singularium"] = 4, ["celestium"] = 4, ["astral spore"] = 4, ["bloodstone"] = 4, ["voidstone"] = 4, ["dinosaur skull"] = 4, ["vineheart"] = 4,
        ["cryonic"] = 5, ["umbrite"] = 5, ["cryonic artifact"] = 5
    }

    local function findDredgeMaster()
        local NPCs = workspace:FindFirstChild("NPCs")
        if NPCs then
            for _, folder in ipairs(NPCs:GetChildren()) do
                local dm = folder:FindFirstChild("Dredge Master") or folder:FindFirstChild("DredgeMaster")
                if dm then
                    return dm
                end
            end
            for _, desc in ipairs(NPCs:GetDescendants()) do
                if desc.Name == "Dredge Master" or desc.Name == "DredgeMaster" then
                    return desc
                end
            end
        end
        return nil
    end

    local function isDredgeMaster(desc, text)
        local t = (text or ""):lower()
        if t:find("dredge%s*master") or t:find("dredgemaster") then
            return true
        end
        if desc.Parent then
            for _, sibling in ipairs(desc.Parent:GetChildren()) do
                if sibling:IsA("TextLabel") and sibling.Text ~= "" then
                    local st = sibling.Text:lower()
                    if st:find("dredge%s*master") or st:find("dredgemaster") then
                        return true
                    end
                end
            end
        end
        local p = desc.Parent
        local playerGui = Player:FindFirstChild("PlayerGui")
        for i = 1, 5 do
            if not p or p == playerGui then break end
            for _, child in ipairs(p:GetChildren()) do
                if child:IsA("TextLabel") and child.Text ~= "" then
                    local ct = child.Text:lower()
                    if ct:find("dredge%s*master") or ct:find("dredgemaster") then
                        return true
                    end
                end
            end
            p = p.Parent
        end
        return false
    end

    local function getActiveQuestDetails()
        local playerGui = Player:FindFirstChild("PlayerGui")
        if not playerGui then return nil, nil, nil end
        
        local candidates = {}
        local seenItems = {}
        for _, desc in ipairs(playerGui:GetDescendants()) do
            if desc:IsA("TextLabel") and desc.Text ~= "" then
                local text = desc.Text
                -- Find the numbers separated by a slash (e.g. 0/70)
                local cur, tot = text:match("(%d+)%s*/%s*(%d+)")
                if cur and tot then
                    cur = tonumber(cur)
                    tot = tonumber(tot)
                    
                    if isDredgeMaster(desc, text) then
                        -- Strip progress portion from start/end to get the potential quest name/item
                        local cleanText = text:gsub("^%s*[%(%[]?%s*%d+%s*/%s*%d+%s*[%]%)]?%s*", "")
                        cleanText = cleanText:gsub("%s*[%(%[]?%s*%d+%s*/%s*%d+%s*[%]%)]?%s*$", "")
                        cleanText = cleanText:gsub("^%s*[^%w%s]+%s*", ""):gsub("%s*[^%w%s]+%s*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
                        
                        -- Sibling fallback
                        if cleanText == "" and desc.Parent then
                            for _, sibling in ipairs(desc.Parent:GetChildren()) do
                                if sibling:IsA("TextLabel") and sibling ~= desc and sibling.Text ~= "" then
                                    local sibText = sibling.Text
                                    if not sibText:match("^%s*%d+%s*$") and not sibText:match("%d+%s*/%s*%d+") then
                                        cleanText = sibText
                                        cleanText = cleanText:gsub("^%s*[Dd]redge%s*[Mm]aster%s*[Qq]uest%s*:%s*", "")
                                        cleanText = cleanText:gsub("^%s*[Qq]uest%s*:%s*", "")
                                        cleanText = cleanText:gsub("^%s*[Tt]ask%s*:%s*", "")
                                        cleanText = cleanText:gsub("^%s*[Mm]ission%s*:%s*", "")
                                        cleanText = cleanText:gsub("^%s*[Aa]ctive%s*[Qq]uest%s*:%s*", "")
                                        cleanText = cleanText:gsub("^%s*[^%w%s]+%s*", ""):gsub("%s*[^%w%s]+%s*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
                                        break
                                    end
                                end
                            end
                        end
                        
                        -- Extract action verb
                        local startPos, endPos = cleanText:lower():find("bring%s*%d*%s*")
                        if not startPos then startPos, endPos = cleanText:lower():find("collect%s*%d*%s*") end
                        if not startPos then startPos, endPos = cleanText:lower():find("find%s*%d*%s*") end
                        if not startPos then startPos, endPos = cleanText:lower():find("get%s*%d*%s*") end
                        if not startPos then startPos, endPos = cleanText:lower():find("deliver%s*%d*%s*") end
                        if not startPos then startPos, endPos = cleanText:lower():find("gather%s*%d*%s*") end
                        if not startPos then startPos, endPos = cleanText:lower():find("harvest%s*%d*%s*") end
                        if not startPos then startPos, endPos = cleanText:lower():find("mine%s*%d*%s*") end
                        if not startPos then startPos, endPos = cleanText:lower():find("fish%s*%d*%s*") end
                        if not startPos then startPos, endPos = cleanText:lower():find("obtain%s*%d*%s*") end
                        
                        if startPos then
                            cleanText = cleanText:sub(startPos)
                        end
                        
                        local item = cleanText
                        item = item:gsub("^%s*[Bb]ring%s*%d*%s*", "")
                        item = item:gsub("^%s*[Cc]ollect%s*%d*%s*", "")
                        item = item:gsub("^%s*[Ff]ind%s*%d*%s*", "")
                        item = item:gsub("^%s*[Gg]et%s*%d*%s*", "")
                        item = item:gsub("^%s*[Dd]eliver%s*%d*%s*", "")
                        item = item:gsub("^%s*[Gg]ather%s*%d*%s*", "")
                        item = item:gsub("^%s*[Hh]arvest%s*%d*%s*", "")
                        item = item:gsub("^%s*[Mm]ine%s*%d*%s*", "")
                        item = item:gsub("^%s*[Ff]ish%s*%d*%s*", "")
                        item = item:gsub("^%s*[Oo]btain%s*%d*%s*", "")
                        item = item:gsub("^%s*%d+%s*", "")
                        item = item:gsub("[:;%.,]+%s*$", "")
                        item = item:gsub("^%s+", ""):gsub("%s+$", "")
                        
                        local itemLower = item:lower()
                        local difficulty = 3
                        for k, diff in pairs(MineralDifficulty) do
                            if itemLower:find(k) then
                                difficulty = diff
                                break
                            end
                        end
                        
                        if not seenItems[itemLower] then
                            seenItems[itemLower] = true
                            table.insert(candidates, {
                                item = item,
                                cur = cur,
                                tot = tot,
                                difficulty = difficulty,
                                text = text
                            })
                        end
                    end
                end
            end
        end
        
        if #candidates > 0 then
            local incomplete = {}
            local complete = {}
            for _, c in ipairs(candidates) do
                if c.cur < c.tot then
                    table.insert(incomplete, c)
                else
                    table.insert(complete, c)
                end
            end
            
            if #incomplete > 0 then
                local best = incomplete[1]
                print("[AutoQuest] Selected Incomplete Task: '" .. tostring(best.text) .. "' -> Parsed Item: '" .. tostring(best.item) .. "' (" .. tostring(best.cur) .. "/" .. tostring(best.tot) .. ")")
                return best.item, best.cur, best.tot, candidates
            else
                local best = complete[1]
                print("[AutoQuest] All tasks completed! Selected: '" .. tostring(best.text) .. "' -> Parsed Item: '" .. tostring(best.item) .. "' (" .. tostring(best.cur) .. "/" .. tostring(best.tot) .. ")")
                return best.item, best.cur, best.tot, candidates
            end
        end
        
        return nil, nil, nil, nil
    end

    local function processDialogue()
        task.spawn(function()
            local playerGui = Player:FindFirstChild("PlayerGui")
            if not playerGui then return end
            
            for _, child in ipairs(playerGui:GetChildren()) do
                if child:IsA("ScreenGui") and (child.Name:lower():find("dialog") or child.Name:lower():find("quest") or child.Name:lower():find("chat") or child.Name:lower():find("npc")) then
                    for _, desc in ipairs(child:GetDescendants()) do
                        local isClickable = desc:IsA("TextButton") or desc:IsA("ImageButton")
                        local textObj = nil
                        if desc:IsA("TextLabel") then
                            textObj = desc
                        elseif desc:IsA("TextButton") then
                            textObj = desc
                        end
                        
                        if textObj and textObj.Text ~= "" and textObj.Visible then
                            local txt = textObj.Text:lower()
                            if txt:find("accept") or txt:find("yes") or txt:find("sure") or txt:find("complete") or txt:find("claim") or txt:find("turn in") or txt:find("ok") or txt:find("next") or txt:find("confirm") then
                                local button = nil
                                if isClickable then
                                    button = desc
                                else
                                    local p = desc.Parent
                                    while p and p ~= child do
                                        if p:IsA("TextButton") or p:IsA("ImageButton") then
                                            button = p
                                            break
                                        end
                                        p = p.Parent
                                    end
                                end
                                
                                if button and button.Visible then
                                    pcall(function()
                                        if firesignal then
                                            firesignal(button.MouseButton1Click)
                                            firesignal(button.Activated)
                                        end
                                        button:Activate()
                                    end)
                                    task.wait(0.2)
                                end
                            end
                        end
                    end
                end
            end
        end)
    end

    local function updateUI(fields)
        if State.Quest.statusUI and State.Quest.statusUI.SetFields then
            pcall(function()
                State.Quest.statusUI:SetFields(fields)
            end)
        end
    end

    function AutoQuestModule.start()
        if running then return end
        running = true
        questThread = task.spawn(function()
            while running do
                local item, cur, tot, candidates = getActiveQuestDetails()
                
                if not item or (cur and tot and cur >= tot) then
                    local targetStr = item and (item .. " (Complete!)") or "No Active Quest"
                    
                    local uiLines = {
                        "Status: Teleporting to NPC",
                        "Target: " .. targetStr
                    }
                    if candidates and #candidates > 0 then
                        table.insert(uiLines, "Quest Tasks:")
                        for _, c in ipairs(candidates) do
                            local statusStr = c.cur >= c.tot and "Completed" or "Pending"
                            table.insert(uiLines, string.format("- %s: %d/%d (%s)", c.item, c.cur, c.tot, statusStr))
                        end
                    end
                    updateUI(uiLines)
                    
                    -- Stop Auto Farm before talking to NPC
                    AutoFarmModule.stop()
                    
                    local dm = findDredgeMaster()
                    if dm and dm:FindFirstChild("HumanoidRootPart") then
                        local hrp = dm.HumanoidRootPart
                        local char = Player.Character
                        local playerHrp = char and char:FindFirstChild("HumanoidRootPart")
                        
                        if playerHrp then
                            Utility.createNotification("Teleporting to Dredge Master...", 3)
                            pcall(function()
                                playerHrp.CFrame = hrp.CFrame * CFrame.new(0, 0, -3)
                            end)
                            task.wait(1.5)
                            
                            local prompt = dm:FindFirstChildWhichIsA("ProximityPrompt", true) or hrp:FindFirstChildWhichIsA("ProximityPrompt", true)
                            if prompt then
                                prompt.HoldDuration = 0
                                updateUI({"Status: Talking to NPC", "Target: " .. targetStr})
                                if fireproximityprompt then
                                    fireproximityprompt(prompt)
                                else
                                    prompt:InputHoldBegin()
                                    task.wait(0.1)
                                    prompt:InputHoldEnd()
                                end
                                task.wait(0.5)
                                
                                processDialogue()
                                task.wait(2.0)
                            else
                                Utility.createNotification("ProximityPrompt not found!", 3)
                            end
                        end
                    else
                        Utility.createNotification("Dredge Master not found!", 3)
                    end
                else
                    -- We have a quest and need more items!
                    local waypoint = nil
                    local itemLower = item:lower()
                    for key, wp in pairs(ItemToWaypoint) do
                        if itemLower:find(key) then
                            waypoint = wp
                            break
                        end
                    end
                    
                    waypoint = waypoint or "Fortune River"
                    
                    -- Match waypoint case-insensitively and partially against active game waypoints
                    if WaypointModule and WaypointModule.getList then
                        local list = WaypointModule.getList()
                        local lowerWP = waypoint:lower()
                        for _, wpName in ipairs(list) do
                            local lowerName = wpName:lower()
                            if lowerName:find(lowerWP, 1, true) or lowerWP:find(lowerName, 1, true) then
                                waypoint = wpName
                                break
                            end
                        end
                    end
                    
                    local currentArea = Player:GetAttribute("CurrentArea") or ""
                    local areaMatch = string.find(currentArea:lower(), waypoint:lower())
                    
                    if not areaMatch then
                        -- Stop Auto Farm before teleporting
                        AutoFarmModule.stop()
                        
                        local uiLines = {
                            "Status: Traveling to Zone",
                            "Target Zone: " .. waypoint .. " (for " .. item .. ")"
                        }
                        if candidates and #candidates > 0 then
                            table.insert(uiLines, "Quest Tasks:")
                            for _, c in ipairs(candidates) do
                                local statusStr = c.cur >= c.tot and "Completed" or (c.item == item and "Traveling" or "Pending")
                                table.insert(uiLines, string.format("- %s: %d/%d (%s)", c.item, c.cur, c.tot, statusStr))
                            end
                        end
                        updateUI(uiLines)
                        Utility.createNotification("Traveling to " .. waypoint .. " for " .. item .. "...", 4)
                        if WaypointModule and WaypointModule.teleport then
                            WaypointModule.teleport(waypoint)
                            task.wait(3.0)
                        else
                            Utility.createNotification("WaypointModule not found!", 3)
                        end
                    else
                        local char = Player.Character
                        local playerHrp = char and char:FindFirstChild("HumanoidRootPart")
                        if playerHrp then
                            local nearestDeposit = scanRegionPos(playerHrp.Position, "Deposit")
                            local nearestWater = scanRegionPos(playerHrp.Position, "Water")
                            
                            -- Retry scan up to 3 times if not found
                            if not nearestDeposit or not nearestWater then
                                for attempt = 1, 3 do
                                    task.wait(1)
                                    char = Player.Character
                                    playerHrp = char and char:FindFirstChild("HumanoidRootPart")
                                    if playerHrp then
                                        nearestDeposit = nearestDeposit or scanRegionPos(playerHrp.Position, "Deposit")
                                        nearestWater = nearestWater or scanRegionPos(playerHrp.Position, "Water")
                                        if nearestDeposit and nearestWater then
                                            break
                                        end
                                    end
                                end
                            end
                            
                             if nearestDeposit and nearestWater then
                                 State.AutoFarm.sandCFrame = nearestDeposit
                                 State.AutoFarm.waterCFrame = nearestWater
                                 
                                 -- Start Auto Farm if active but not running
                                 if State.AutoFarm.active and not State.AutoFarm.running then
                                     AutoFarmModule.start()
                                 end
                                 
                                 local uiLines = {
                                     "Status: " .. (State.AutoFarm.active and "Farming Quest Items" or "Auto Farm Paused"),
                                     "Active Target: " .. item .. " (" .. tostring(cur) .. "/" .. tostring(tot) .. ")"
                                 }
                                if candidates and #candidates > 0 then
                                    table.insert(uiLines, "All Quest Tasks:")
                                    for _, c in ipairs(candidates) do
                                        local statusStr = c.cur >= c.tot and "Completed" or (c.item == item and "Farming" or "Pending")
                                        table.insert(uiLines, string.format("- %s: %d/%d (%s)", c.item, c.cur, c.tot, statusStr))
                                    end
                                end
                                updateUI(uiLines)
                            else
                                -- Stop Auto Farm since we don't have both
                                AutoFarmModule.stop()
                                
                                local uiLines = {
                                    "Status: Waiting for Deposit/Water",
                                    "Active Target: " .. item
                                }
                                if candidates and #candidates > 0 then
                                    table.insert(uiLines, "All Quest Tasks:")
                                    for _, c in ipairs(candidates) do
                                        local statusStr = c.cur >= c.tot and "Completed" or "Pending"
                                        table.insert(uiLines, string.format("- %s: %d/%d (%s)", c.item, c.cur, c.tot, statusStr))
                                    end
                                end
                                updateUI(uiLines)
                                Utility.createNotification("Waiting for deposit/water in " .. waypoint .. "...", 3)
                            end
                        end
                    end
                end
                task.wait(State.Quest.interval or 10)
            end
        end)
    end

    function AutoQuestModule.stop()
        running = false
        if questThread then
            pcall(task.cancel, questThread)
            questThread = nil
        end
        updateUI({"Status: Idle", "Target: None"})
        -- Stop Auto Farm when Auto Quest is stopped
        AutoFarmModule.stop()
    end
end


local amazong = ShoppingMart.new(EngProject.Utility:IsMobile() and 0.5 or 0.90)

local window = EngProject:CreateWindow({
    Brand = {
        Name = "Eng Project"
    },
    DefaultScale = EngProject.Utility:IsMobile() and 0.50 or 0.75,
    TabMode = "Dynamic",
    CanResize = true,
    Footer = true,
    FooterItems = {{
        Type = "Text",
        Text = "Eng Project v" .. EngProject.Version .. " - https://discord.gg/fmHk8ZbM",
        ColorTier = "TextSecondary",
        Order = 1
    }},
    StartHidden = false,
    IgnoreGuiInset = false,
    DisplayOrder = 1
})

local Tabs = {
    Dashboard = EngProject:CreateTab(window, "Dashboard", {
        Description = "Info, socials & credits",
        Icon = {
            Image = "rbxassetid://10734950309",
            ImageColor3 = Color3.fromRGB(255, 255, 255)
        }
    }),
    Main = EngProject:CreateTab(window, "Main", {
        Description = "Auto Farm and Auto Sell",
        Icon = {
            Image = "rbxassetid://10734975692",
            Size = UDim2.new(0, 16, 0, 16),
            ImageColor3 = Color3.fromRGB(255, 255, 255)
        },
        DualScroll = true
    }),
    Hunting = EngProject:CreateTab(window, "Hunting", {
        Description = "Treasure map hunting and geode opening",
        Icon = {
            Image = "rbxassetid://16898613613",
            Size = UDim2.new(0, 16, 0, 16),
            ImageRectSize = Vector2.new(48, 48),
            ImageRectOffset = Vector2.new(306, 771),
            ImageColor3 = Color3.fromRGB(255, 255, 255)
        },
        DualScroll = true
    }),
    Teleport = EngProject:CreateTab(window, "Teleport", {
        Description = "Fast travel network, geode locations, and runes",
        Icon = {
            Image = "rbxassetid://16898613777",
            Size = UDim2.new(0, 16, 0, 16),
            ImageRectSize = Vector2.new(48, 48),
            ImageRectOffset = Vector2.new(771, 98),
            ImageColor3 = Color3.fromRGB(255, 255, 255)
        },
        DualScroll = true
    }),
    Tools = EngProject:CreateTab(window, "Tools", {
        Description = "Equipment reforging and tool enchantment",
        Icon = {
            Image = "rbxassetid://16898613044",
            Size = UDim2.new(0, 16, 0, 16),
            ImageRectSize = Vector2.new(48, 48),
            ImageRectOffset = Vector2.new(771, 955),
            ImageColor3 = Color3.fromRGB(255, 255, 255)
        },
        DualScroll = true
    }),
    Crafting = EngProject:CreateTab(window, "Crafting", {
        Description = "Equipment crafting and resource conversion",
        Icon = {
            Image = "rbxassetid://10723396542",
            ImageColor3 = Color3.fromRGB(255, 255, 255)
        }
    }),
    Favourite = EngProject:CreateTab(window, "Favourite", {
        Description = "Favourite valuable items",
        Icon = {
            Image = "rbxassetid://10734966248",
            ImageColor3 = Color3.fromRGB(255, 255, 255)
        }
    }),
    Shop = EngProject:CreateTab(window, "Shop", {
        Description = "Amazong - Credits: Jeff Bozo",
        Icon = {
            Image = "rbxassetid://10734952479",
            ImageColor3 = Color3.fromRGB(255, 255, 255)
        }
    }),
    TravelMerchant = EngProject:CreateTab(window, "Travel Merchant", {
        Description = "Automated purchasing from the Travel Merchant",
        Icon = {
            Image = "rbxassetid://10734952479",
            ImageColor3 = Color3.fromRGB(255, 255, 255)
        },
        DualScroll = true
    }),
    Summer = EngProject:CreateTab(window, "Summer Collection", {
        Description = "Automated Summer Cauldron event items and rewards",
        Icon = {
            Image = "rbxassetid://10734963191",
            ImageColor3 = Color3.fromRGB(255, 255, 255)
        },
        DualScroll = true
    }),
    Miscellaneous = EngProject:CreateTab(window, "Miscellaneous", {
        Description = "Excavation sites, environmental barriers, and utilities",
        Icon = {
            Image = "rbxassetid://10734963191",
            ImageColor3 = Color3.fromRGB(255, 255, 255)
        },
        DualScroll = true
    }),
    Settings = EngProject:CreateTab(window, "Settings", {
        Description = "Interface customization and control configuration",
        Icon = {
            Image = "rbxassetid://16898613777",
            Size = UDim2.new(0, 16, 0, 16),
            ImageRectSize = Vector2.new(48, 48),
            ImageRectOffset = Vector2.new(771, 257),
            ImageColor3 = Color3.fromRGB(255, 255, 255)
        }
    })
}

local function initializeDashboardTab()
    local page = Tabs.Dashboard.Page

    EngProject:CreateSection(page, "Eng & Irse Project")

    EngProject:CreateParagraph(page, "About", {
        "Script made by Eng & Irse for Roblox Prospecting.",
        "Version: " .. EngProject.Version,
        "Join our Discord for updates, bug reports, and support!"
    })

    EngProject:CreateSection(page, "Socials")

    EngProject:CreateButton(page, "Discord Server  -  discord.gg/fmHk8ZbM", function()
        local link = "https://discord.gg/fmHk8ZbM"
        local setclip = setclipboard or toclipboard
        if setclip then
            pcall(function() setclip(link) end)
            EngProject:CreateNotification({
                Type = "Success",
                Title = "Link Copied!",
                Description = "Discord link disalin ke clipboard. Paste di browser!",
                Duration = 5
            })
        else
            EngProject:CreateNotification({
                Type = "Warning",
                Title = "Clipboard tidak tersedia",
                Description = "Link: discord.gg/fmHk8ZbM",
                Duration = 8
            })
        end
    end)

    EngProject:CreateButton(page, "TikTok iTrick01  -  @itrick01", function()
        local link = "https://www.tiktok.com/@itrick01"
        local setclip = setclipboard or toclipboard
        if setclip then
            pcall(function() setclip(link) end)
            EngProject:CreateNotification({
                Type = "Success",
                Title = "Link Copied!",
                Description = "TikTok @itrick01 disalin ke clipboard!",
                Duration = 5
            })
        else
            EngProject:CreateNotification({
                Type = "Warning",
                Title = "Clipboard tidak tersedia",
                Description = "Link: tiktok.com/@itrick01",
                Duration = 8
            })
        end
    end)

    EngProject:CreateButton(page, "TikTok Irse  -  @irse.roblox", function()
        local link = "https://www.tiktok.com/@irse.roblox"
        local setclip = setclipboard or toclipboard
        if setclip then
            pcall(function() setclip(link) end)
            EngProject:CreateNotification({
                Type = "Success",
                Title = "Link Copied!",
                Description = "TikTok @irse.roblox disalin ke clipboard!",
                Duration = 5
            })
        else
            EngProject:CreateNotification({
                Type = "Warning",
                Title = "Clipboard tidak tersedia",
                Description = "Link: tiktok.com/@irse.roblox",
                Duration = 8
            })
        end
    end)

    EngProject:CreateSection(page, "Credits")

    EngProject:CreateParagraph(page, "Made partner", {
        "Eng - Core script, modules, and automation",
        "Irse - Testing, balancing, and feature ideas",
        "Klik tombol di atas untuk copy link social media kami!"
    })
end

local function initializeMainTab()
    local page = Tabs.Main.Page
    local LeftPage = page.Left
    local RightPage = page.Right

    local AutoFarmSection = EngProject:CreateSection(LeftPage, "Auto Farm", {
        Style = "box",
        Icon = "rbxassetid://10789587520",
        DefaultExpanded = true,
        TextSize = 15
    })

    EngProject:CreateDropdown(AutoFarmSection.Container, "Movement Method", {"Legit", "Tween", "Teleport", "Visual"}, "Teleport",
        function(selection)
            State.AutoFarm.travelMode = selection
        end, {
            Save = {
                Key = "prospecting.auto_farm.movement_method"
            }
        })

    EngProject:CreateSlider(AutoFarmSection.Container, "Walk / Tween Speed", 16, 250, State.Speed or 24, function(val)
        State.Speed = val
        pcall(function()
            if Humanoid then Humanoid.WalkSpeed = val end
        end)
    end, {
        Increment = 1,
        Save = {
            Key = "prospecting.auto_farm.speed"
        }
    })

    EngProject:CreateButton(AutoFarmSection.Container, "Save Dig Location", function()
        State.AutoFarm.sandCFrame = HumanoidRootPart.CFrame
        State.AutoFarm.manualSand = true
        State.AutoFarm.savedArea = Player:GetAttribute("CurrentArea")
        EngProject:CreateNotification({
            Type = "Success",
            Title = "Location Saved",
            Description = "Dig location has been saved successfully.",
            Duration = 5
        })
    end)

    EngProject:CreateButton(AutoFarmSection.Container, "Save Washing Location", function()
        State.AutoFarm.waterCFrame = HumanoidRootPart.CFrame
        State.AutoFarm.manualWater = true
        State.AutoFarm.savedArea = Player:GetAttribute("CurrentArea")
        EngProject:CreateNotification({
            Type = "Success",
            Title = "Location Saved",
            Description = "Washing location has been saved successfully.",
            Duration = 5
        })
    end)

    autoFarmToggle1 = EngProject:CreateToggle(AutoFarmSection.Container, "Enable Auto Farm", false, function(state)
        if settingToggleState then return end
        if state then
            AutoFarmModule.start()
        else
            AutoFarmModule.stop()
        end
    end)

    EngProject:CreateButton(AutoFarmSection.Container, "Unstuck Character", function()
        CharacterLock.unlock()
    end)

    EngProject:CreateButton(AutoFarmSection.Container, "Remove Crocodiles", function()
        BarrierRemovalModule.removeCrocodiles()
    end)

    EngProject:CreateParagraph(AutoFarmSection.Container, "How Automated Farm Works",
        {"Configure your movement method, set digging and washing locations, then activate the system to begin the continuous cycle.",
         {
            Text = "Teleport mode is significantly faster and recommended for efficiency.",
            IsSubField = true
        }, {
            Text = "You must stand within the correct region before saving each location to ensure proper positioning.",
            IsSubField = true
        }, {
            Text = "Use Unstuck Character if movement freezes or the tweening animation becomes unresponsive.",
            IsSubField = true
        }})

    local AutoQuestSection = EngProject:CreateSection(LeftPage, "Auto Quest", {
        Style = "box",
        Icon = "rbxassetid://10734963191",
        DefaultExpanded = true,
        TextSize = 15
    })

    local questStatusPara = EngProject:CreateParagraph(AutoQuestSection.Container, "Quest Status", {
        "Status: Idle",
        "Target: None"
    })
    State.Quest.statusUI = questStatusPara

    EngProject:CreateToggle(AutoQuestSection.Container, "Enable Auto Quest (Dredge Master)", false, function(state)
        State.Quest.autoQuest = state
        if state then
            AutoQuestModule.start()
        else
            AutoQuestModule.stop()
        end
    end)

    autoFarmToggle2 = EngProject:CreateToggle(AutoQuestSection.Container, "Enable Auto Farm", false, function(state)
        if settingToggleState then return end
        if state then
            AutoFarmModule.start()
        else
            AutoFarmModule.stop()
        end
    end)

    EngProject:CreateSlider(AutoQuestSection.Container, "Quest Check Interval (s)", 5, 120, State.Quest.interval, function(val)
        State.Quest.interval = val
    end, {
        Increment = 1
    })

    local SellSection = EngProject:CreateSection(RightPage, "Auto Sell", {
        Style = "box",
        Icon = "rbxassetid://2246496691",
        DefaultExpanded = true,
        TextSize = 15
    })

    EngProject:CreateDropdown(SellSection.Container, "Selling Trigger Mode", {"Auto", "Threshold", "Duration"}, "Auto",
        function(selection)
            State.Sell.type = selection
            Utility.createNotification("Selling mode changed to: " .. selection)
        end, {
            Save = {
                Key = "prospecting.sell.trigger_mode"
            }
        })

    EngProject:CreateTextInput(SellSection.Container, "Configure Threshold or Duration", nil, function(input)
        local result, kind = Utility.validateSellValue(input)
        if result then
            if kind == "time" then
                State.Sell.delay = result
                Utility.createNotification("Inventory will be sold every " .. result .. " seconds.", 10)
            else
                State.Sell.threshold = result
                Utility.createNotification("Inventory will be sold after collecting " .. result .. " items.", 10)
            end
        else
            Utility.createNotification("Enter a value between 10-2000 items or 30 seconds to 1 day.", 10)
        end
    end, {
        Save = {
            Key = "prospecting.sell.trigger_value"
        }
    })

    -- Tombol utama: teleport langsung ke merchant & jual
    EngProject:CreateButton(SellSection.Container, "⚡ Teleport ke Merchant & Jual Sekarang", function()
        task.spawn(function()
            MerchantModule.directTeleportAndSell()
        end)
    end)

    -- Tombol cari semua merchant di peta
    EngProject:CreateButton(SellSection.Container, "🔍 Cari Merchant di Peta Ini", function()
        task.spawn(function()
            local all = MerchantModule.getAllMerchants()
            if #all == 0 then
                Utility.createNotification("Tidak ada merchant ditemukan! Cek workspace.NPCs", 5)
                return
            end

            local char = Player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local lines = "Merchant ditemukan: " .. #all

            for i, m in ipairs(all) do
                local dist = hrp and math.floor((hrp.Position - m.hrp.Position).Magnitude) or 0
                lines = lines .. "\n[" .. i .. "] " .. m.name .. " (" .. m.folder .. ") - " .. dist .. " studs"
            end
            Utility.createNotification(lines, 8)
        end)
    end)

    -- Tombol sell lama (pakai TaskManager)
    EngProject:CreateButton(SellSection.Container, "Sell All Items Now (TaskManager)", function()
        if TaskManager:getMainTask() then
            return Utility.createNotification("Please wait for the current task to finish before selling.", 5)
        end

        if not TaskManager:requestTask("ManualSell", 3) then
            return Utility.createNotification("Unable to initiate selling sequence.", 5)
        end

        task.spawn(function()
            if TaskManager:waitForTurn("ManualSell", 10) and TaskManager:startTask("ManualSell") then
                TaskManager:setCurrentTask("Selling")
                SellModule.sell({}, State.Sell.mode or "Teleport")
                TaskManager:finishTask("ManualSell")
            end
        end)
    end)

    EngProject:CreateToggle(SellSection.Container, "Enable Automatic Selling", false, function(state)
        State.Sell.autoSell = state
        State.Sell._lastSell = State.Sell._lastSell or 0
        State.Sell._scheduledSell = false

        if state then
            task.spawn(function()
                while State.Sell.autoSell do
                    if State.Sell.type == "Duration" then
                        local delay = tonumber(State.Sell.delay) or 300
                        if os.clock() - State.Sell._lastSell >= delay then
                            State.Sell._scheduledSell = true
                        end
                    end
                    task.wait(5)
                end
            end)
        end

        Utility.createNotification(state and "Automatic Selling Enabled" or "Automatic Selling Disabled")
    end)

    EngProject:CreateParagraph(SellSection.Container, "Selling Configuration",
        {"Select your selling trigger method and configure the corresponding threshold or duration below.", {
            Text = "Auto Mode: Automatically sells when the backpack UI shows your inventory is full.",
            IsSubField = true
        }, {
            Text = "Threshold Mode: Automatically sells when your inventory reaches a specified item count.",
            IsSubField = true
        }, {
            Text = "Duration Mode: Automatically sells at regular intervals you define.",
            IsSubField = true
        }, {
            Text = "Manual Selling: Waits for the current farming task to complete before initiating the sale.",
            IsSubField = true
        }})
end

local function initializeHuntingTab()
    local page = Tabs.Hunting.Page
    local LeftPage = page.Left
    local RightPage = page.Right

    local TreasureSection = EngProject:CreateSection(LeftPage, "Treasure Hunting", {
        Style = "box",
        Icon = "rbxassetid://6947202399",
        DefaultExpanded = true,
        TextSize = 15
    })

    local treasureStatus = EngProject:CreateParagraph(TreasureSection.Container, "Hunt Status",
        {"Idle", "No maps detected"})

    local function setTreasureStatus(status, detail)
        treasureStatus:SetFields({"Status: " .. status, detail})
    end

    local function getTreasureStatusText()
        local status = HuntingModule.getTreasureHuntStatus()
        local mapText = status.currentMap and ("Current map: " .. status.currentMap) or "Searching for maps"
        return "Maps completed: " .. status.mapsCompleted, mapText
    end

    local function isAutoFarmWashPending()
        if not (State.AutoFarm.active and State.AutoFarm.running) then
            return false
        end

        local currentTask = TaskManager:getCurrentTask()
        local nextTask = TaskManager:getNextTask()
        if currentTask == "WashPan" or nextTask == "WashPan" then
            return true
        end

        local ok, panStatus = pcall(function()
            return PanModule.getStatus()
        end)

        return ok and panStatus and panStatus.isFull == true
    end

    local function waitForAutoFarmWash()
        if not isAutoFarmWashPending() then
            return true
        end

        local startedAt = tick()
        setTreasureStatus("Waiting", "Pan is ready to wash; finishing wash before treasure hunt")

        while State.Hunting.autoTreasure and isAutoFarmWashPending() do
            if tick() - startedAt > 120 then
                setTreasureStatus("Waiting", "Wash has not completed yet; treasure hunt will retry soon")
                return false
            end
            task.wait(0.5)
        end

        return State.Hunting.autoTreasure
    end

    local function pauseAutoFarmForTreasure()
        if State.Hunting.autoTreasurePausedFarm then
            return true
        end

        if not waitForAutoFarmWash() then
            return false
        end

        if AutoFarmModule.pause("TreasureHunt") then
            State.Hunting.autoTreasurePausedFarm = true
            setTreasureStatus("Pausing Farm", "Treasure map found; auto farm is paused until maps are cleared")
            task.wait(0.35)
        end

        return true
    end

    local function resumeAutoFarmFromTreasure()
        if not State.Hunting.autoTreasurePausedFarm then
            return
        end

        State.Hunting.autoTreasurePausedFarm = false
        if AutoFarmModule.resume("TreasureHunt") and State.AutoFarm.active then
            setTreasureStatus("Resuming Farm", "Treasure maps cleared; auto farm resumed")
            task.wait(0.5)
        end
    end

    EngProject:CreateParagraph(TreasureSection.Container, "Treasure Hunt Instructions",
        {"Ensure you have a treasure map in your inventory before starting.", {
            Text = "The system will automatically navigate to the map location and collect items.",
            IsSubField = true
        }, {
            Text = "Hunt completes when the map is consumed.",
            IsSubField = true
        }})

    EngProject:CreateButton(TreasureSection.Container, "Start Treasure Hunt", function()
        if State.Hunting.autoTreasure then
            setTreasureStatus("Auto Running", "Disable auto treasure hunt before starting a manual hunt")
            return
        end

        if HuntingModule.isTreasureHunting() then
            setTreasureStatus("Already Running", "Hunt in progress")
            return
        end

        local map = HuntingModule.findNextMap()
        if not map then
            setTreasureStatus("Failed", "No treasure maps found in inventory")
            return
        end

        if HuntingModule.startTreasureHunting() then
            setTreasureStatus("Active", "Hunting in progress")
            task.spawn(function()
                while HuntingModule.isTreasureHunting() do
                    local progress, mapText = getTreasureStatusText()
                    treasureStatus:SetFields({"Status: Active", progress, {
                        Text = mapText,
                        IsSubField = true
                    }})
                    task.wait(1)
                end
                setTreasureStatus("Completed", "Hunt finished - " .. HuntingModule.treasureState.mapsCompleted ..
                    " maps hunted")
            end)
        else
            setTreasureStatus("Failed", "Unable to start hunt")
        end
    end)

    EngProject:CreateButton(TreasureSection.Container, "Stop Treasure Hunt", function()
        State.Hunting.autoTreasure = false

        if not HuntingModule.isTreasureHunting() then
            resumeAutoFarmFromTreasure()
            setTreasureStatus("Idle", "No hunt in progress")
            return
        end
        HuntingModule.stopTreasureHunting()
        resumeAutoFarmFromTreasure()
        setTreasureStatus("Stopped", "Hunt halted")
    end)



    EngProject:CreateToggle(TreasureSection.Container, "Enable Auto Treasure Hunt", false, function(state)
        State.Hunting.autoTreasure = state

        if not state then
            if HuntingModule.isTreasureHunting() then
                HuntingModule.stopTreasureHunting()
            end
            resumeAutoFarmFromTreasure()
            setTreasureStatus("Idle", "Auto treasure hunt disabled")
            return
        end

        if State.Hunting.autoTreasureRunning then
            setTreasureStatus("Already Running", "Auto treasure hunt is already active")
            return
        end

        State.Hunting.autoTreasureRunning = true
        setTreasureStatus("Starting", "Initializing auto treasure hunt...")

        task.spawn(function()
            while State.Hunting.autoTreasure do
                local ok, err = pcall(function()
                    if HuntingModule.isTreasureHunting() then
                        local progress, mapText = getTreasureStatusText()
                        treasureStatus:SetFields({"Status: Active", progress, {
                            Text = mapText,
                            IsSubField = true
                        }})
                        task.wait(1)
                        return
                    end

                    local map = HuntingModule.findNextMap()
                    if not map then
                        resumeAutoFarmFromTreasure()
                        setTreasureStatus("Waiting", "No treasure maps found, checking again soon")
                        task.wait(3)
                        return
                    end

                    if not pauseAutoFarmForTreasure() then
                        task.wait(2)
                        return
                    end
                    setTreasureStatus("Preparing", "Starting hunt on map: " .. map.Name)
                    task.wait(0.25)

                    if not HuntingModule.startTreasureHunting({
                        PreserveCount = true
                    }) then
                        setTreasureStatus("Retrying", "Could not start hunt yet")
                        task.wait(2)
                        return
                    end

                    local deadline = tick() + 180
                    local lastMapGUID = nil
                    while State.Hunting.autoTreasure and HuntingModule.isTreasureHunting() do
                        local status = HuntingModule.getTreasureHuntStatus()
                        if status.currentMapGUID and status.currentMapGUID ~= lastMapGUID then
                            lastMapGUID = status.currentMapGUID
                            deadline = tick() + 180
                        end

                        local progress, mapText = getTreasureStatusText()
                        treasureStatus:SetFields({"Status: Active", progress, {
                            Text = mapText,
                            IsSubField = true
                        }})

                        if tick() >= deadline then
                            setTreasureStatus("Timeout", "Hunt took too long, restarting cycle")
                            HuntingModule.stopTreasureHunting()
                            break
                        end

                        task.wait(1)
                    end
                end)

                if not ok then
                    warn("AutoTreasure Error: " .. tostring(err))
                    resumeAutoFarmFromTreasure()
                    State.Hunting.autoTreasure = false
                    setTreasureStatus("Error", "Auto treasure hunt stopped after an error")
                    break
                end

                task.wait(0.35)
            end

            if HuntingModule.isTreasureHunting() then
                HuntingModule.stopTreasureHunting()
            end

            resumeAutoFarmFromTreasure()
            State.Hunting.autoTreasure = false
            State.Hunting.autoTreasureRunning = false
            setTreasureStatus("Idle", "Auto treasure hunt disabled")
        end)
    end)

    local GeodeSection = EngProject:CreateSection(RightPage, "Geode Extraction", {
        Style = "box",
        Icon = "rbxassetid://9019175526",
        DefaultExpanded = true,
        TextSize = 15
    })

    local geodeStatus = EngProject:CreateParagraph(GeodeSection.Container, "Extraction Status",
        {"Idle", "No geodes located"})

    local inventoryDisplay = EngProject:CreateParagraph(GeodeSection.Container, "Inventory Status",
        {HuntingModule.getFormattedInventoryStatus()})

    EngProject:CreateParagraph(GeodeSection.Container, "Geode Extraction Guide",
        {"Geodes are automatically detected when available in your inventory.", {
            Text = "The system will equip geodes and automate clicking to extract contents.",
            IsSubField = true
        }, {
            Text = "Extraction continues until all geodes are depleted or backpack is full.",
            IsSubField = true
        }})

    EngProject:CreateButton(GeodeSection.Container, "Start Geode Opening", function()
        if HuntingModule.isGeodeOpening() then
            geodeStatus:SetFields({"Status: Already Running", "Geode extraction in progress"})
            return
        end

        local hasGeode = HuntingModule.findGeodeInBackpack() ~= nil
        local isEquipped = HuntingModule.isGeodeEquipped()
        local inHotbar = HuntingModule.isGeodeInHotbar()

        if not hasGeode and not isEquipped and not inHotbar then
            geodeStatus:SetFields({"Status: Failed", "No geodes found in inventory, hotbar, or equipped"})
            return
        end

        HuntingModule.updateInventoryCache()

        if HuntingModule.isBackpackFull() then
            geodeStatus:SetFields({"Status: Failed", "Backpack is full, cannot extract geodes"})
            return
        end

        if HuntingModule.startGeodeOpening() then
            geodeStatus:SetFields({"Status: Active", "Opening geodes"})
            inventoryDisplay:SetFields({HuntingModule.getFormattedInventoryStatus()})

            task.spawn(function()
                while HuntingModule.isGeodeOpening() do
                    inventoryDisplay:SetFields({HuntingModule.getFormattedInventoryStatus()})
                    task.wait(0.5)
                end
                inventoryDisplay:SetFields({HuntingModule.getFormattedInventoryStatus()})
            end)
        else
            geodeStatus:SetFields({"Status: Failed", "Unable to start geode opening"})
        end
    end)

    EngProject:CreateButton(GeodeSection.Container, "Stop Geode Opening", function()
        if not HuntingModule.isGeodeOpening() then
            geodeStatus:SetFields({"Status: Idle", "No extraction in progress"})
            return
        end

        HuntingModule.stopGeodeOpening()
        geodeStatus:SetFields({"Status: Stopped", "Extraction halted"})
        HuntingModule.updateInventoryCache()
        inventoryDisplay:SetFields({HuntingModule.getFormattedInventoryStatus()})
    end)

    EngProject:CreateButton(GeodeSection.Container, "Sell All Items", function()
        if TaskManager:getMainTask() then
            return Utility.createNotification("Please wait for current task to finish before selling.", 5)
        end

        if not TaskManager:requestTask("ManualSell", 3) then
            return Utility.createNotification("Unable to initiate selling sequence.", 5)
        end

        task.spawn(function()
            if TaskManager:waitForTurn("ManualSell", 10) and TaskManager:startTask("ManualSell") then
                TaskManager:setCurrentTask("Selling")
                SellModule.sell({}, State.Sell.mode or "Teleport")
                TaskManager:finishTask("ManualSell")
            end
        end)
    end)

    EngProject:CreateToggle(GeodeSection.Container, "Enable Auto Opening", false, function(state)
        State.Hunting.autoGeode = state

        if state then
            HuntingModule.updateInventoryCache()

            task.spawn(function()
                while State.Hunting.autoGeode do
                    local hasGeode = HuntingModule.findGeodeInBackpack() ~= nil
                    local isEquipped = HuntingModule.isGeodeEquipped()
                    local inHotbar = HuntingModule.isGeodeInHotbar()
                    local isFull = HuntingModule.isBackpackFull()

                    inventoryDisplay:SetFields({HuntingModule.getFormattedInventoryStatus()})

                    if isFull then
                        if HuntingModule.isGeodeOpening() then
                            HuntingModule.stopGeodeOpening()
                        end
                        geodeStatus:SetFields({"Status: Paused", "Backpack full, waiting for space"})
                    elseif hasGeode or isEquipped or inHotbar then
                        if not HuntingModule.isGeodeOpening() then
                            HuntingModule.startGeodeOpening()
                            geodeStatus:SetFields({"Status: Running", "Auto-opening in progress"})
                        end
                    else
                        if HuntingModule.isGeodeOpening() then
                            HuntingModule.stopGeodeOpening()
                        end
                        geodeStatus:SetFields({"Status: Waiting", "Waiting for geodes to arrive"})

                        if HuntingModule.waitForGeodes(5) then
                            if HuntingModule.startGeodeOpening() then
                                geodeStatus:SetFields({"Status: Running", "Auto-opening in progress"})
                            end
                        end
                    end

                    HuntingModule.updateInventoryCache()
                    task.wait(1)
                end

                if HuntingModule.isGeodeOpening() then
                    HuntingModule.stopGeodeOpening()
                end
                HuntingModule.updateInventoryCache()
                geodeStatus:SetFields({"Status: Idle", "Auto-opening disabled"})
                inventoryDisplay:SetFields({HuntingModule.getFormattedInventoryStatus()})
            end)
        else
            if HuntingModule.isGeodeOpening() then
                HuntingModule.stopGeodeOpening()
            end
            HuntingModule.updateInventoryCache()
            geodeStatus:SetFields({"Status: Idle", "Auto-opening disabled"})
            inventoryDisplay:SetFields({HuntingModule.getFormattedInventoryStatus()})
        end
    end)

    -- ── Sand Dollar Automation ──
    local SandDollarSection = EngProject:CreateSection(LeftPage, "Sand Dollar Automation", {
        Style = "box",
        Icon = "rbxassetid://13589886367",
        DefaultExpanded = true,
        TextSize = 15
    })

    local sandStatus = EngProject:CreateParagraph(SandDollarSection.Container, "Status & Scanner", {"Status: Idle", "Scanning..."})

    local function updateSandStatus()
        local info = {}
        if State.SandRunning then
            table.insert(info, "🟢 Status      : RUNNING")
            table.insert(info, "🎯 Target     : " .. tostring(State.SandTarget))
            table.insert(info, "📏 Distance   : " .. tostring(State.SandDist) .. " studs")
            table.insert(info, "✅ Collected  : " .. tostring(State.SandCollected))
            table.insert(info, "⏱ Time        : " .. formatTime(tick() - (State.SandStartAt or tick())))
        else
            table.insert(info, "⚪ Status      : Idle")
            table.insert(info, "✅ Last Session: " .. tostring(State.SandCollected) .. " Sand Dollars")
            table.insert(info, "Total in area : " .. tostring(State.SandTotal))
        end
        sandStatus:SetFields(info)
    end

    EngProject:CreateToggle(SandDollarSection.Container, "Auto Collect Sand Dollar", false, function(state)
        if state then
            if State.SandMagnetRunning then
                stopSandMagnet()
            end
            startSandCollect()
            task.spawn(function()
                while State.SandRunning do
                    pcall(updateSandStatus)
                    task.wait(0.5)
                end
                pcall(updateSandStatus)
            end)
        else
            stopSandCollect()
            pcall(updateSandStatus)
        end
    end)

    -- Magnet Collect: player diam, Sand Dollar ditarik ke player
    EngProject:CreateToggle(SandDollarSection.Container, "🧲 Magnet Collect (Diam di Tempat)", false, function(state)
        if state then
            if State.SandRunning then
                stopSandCollect()
            end
            startSandMagnet()
            task.spawn(function()
                while State.SandMagnetRunning do
                    pcall(function()
                        local info = {}
                        table.insert(info, "🟢 Status      : MAGNET ACTIVE")
                        table.insert(info, "🎯 Target     : " .. tostring(State.SandTarget))
                        table.insert(info, "✅ Collected  : " .. tostring(State.SandCollected))
                        table.insert(info, "⏱ Time        : " .. formatTime(tick() - (State.SandStartAt or tick())))
                        table.insert(info, "📦 Remaining  : " .. tostring(State.SandTotal))
                        sandStatus:SetFields(info)
                    end)
                    task.wait(0.5)
                end
                pcall(updateSandStatus)
            end)
        else
            stopSandMagnet()
            pcall(updateSandStatus)
        end
    end)

    EngProject:CreateToggle(SandDollarSection.Container, "Sand Dollar ESP", false, function(state)
        State.EspEnabled = state
        if state then
            pcall(refreshESP)
            -- Listen to new sand dollars in real-time
            pcall(function()
                if not State.SandConn then
                    local folder = getGeodeFolder()
                    if folder then
                        State.SandConn = folder.ChildAdded:Connect(function(obj)
                            task.wait(0.1)
                            if (obj.Name == "SandDollar" or obj.Name == "Sand Dollar") and State.EspEnabled then
                                local part = getSandPart(obj)
                                if part then
                                    pcall(function() createSandESP(obj, part) end)
                                    pcall(scanSandDollars)
                                    pcall(updateSandStatus)
                                end
                            end
                        end)
                        State.SandRemoveConn = folder.ChildRemoved:Connect(function(obj)
                            if obj.Name == "SandDollar" or obj.Name == "Sand Dollar" then
                                pcall(scanSandDollars)
                                pcall(updateSandStatus)
                            end
                        end)
                    end
                end
            end)
        else
            pcall(clearSandESP)
            if State.SandConn then
                pcall(function() State.SandConn:Disconnect() end)
                State.SandConn = nil
            end
            if State.SandRemoveConn then
                pcall(function() State.SandRemoveConn:Disconnect() end)
                State.SandRemoveConn = nil
            end
        end
    end)

    EngProject:CreateSlider(SandDollarSection.Container, "WalkSpeed Config", 16, 500, State.WalkSpeed, function(v)
        State.WalkSpeed = tonumber(v) or State.WalkSpeed
        pcall(function()
            if State.SandRunning and Humanoid then
                Humanoid.WalkSpeed = State.WalkSpeed
            end
        end)
    end, {
        Increment = 1,
        Save = {
            Key = "prospecting.sand.walk_speed"
        }
    })

    EngProject:CreateButton(SandDollarSection.Container, "Refresh Scan", function()
        pcall(scanSandDollars)
        if State.EspEnabled then pcall(refreshESP) end
        pcall(updateSandStatus)
    end)

    task.spawn(function()
        while true do
            if not State.SandRunning then
                pcall(scanSandDollars)
                pcall(updateSandStatus)
            end
            task.wait(2)
        end
    end)
end

local function initializeTeleportTab()
    local page = Tabs.Teleport.Page
    local LeftPage = page.Left
    local RightPage = page.Right

    local WaypointsSection = EngProject:CreateSection(LeftPage, "Fast Travel", {
        Style = "box",
        Icon = "rbxassetid://102208106546256",
        DefaultExpanded = true,
        TextSize = 15
    })

    local waypointsDropdown = EngProject:CreateDropdown(WaypointsSection.Container, "Select Destination",
        WaypointModule.getList(), nil, function(selection)
            WaypointModule.teleport(selection)
        end, {
            Description = "Choose a waypoint to initiate fast travel. Refresh the list to load newly unlocked destinations."
        })

    EngProject:CreateButton(WaypointsSection.Container, "Refresh Destinations", function()
        waypointsDropdown:SetOptions(WaypointModule.getList())
    end)

    EngProject:CreateButton(WaypointsSection.Container, "Unlock All Waypoints", function()
        WaypointModule.unlockAll()
    end)

    EngProject:CreateButton(WaypointsSection.Container, "Emergency Return", function()
        local waypointFolder = Map:FindFirstChild("Waypoints")
        if waypointFolder then
            ReplicatedStorage.Remotes.Misc.FastTravel:FireServer(waypointFolder["Museum"],
                waypointFolder["Rubble Creek"])
        end
    end, {
        Description = "Instantly return to the starter town in emergencies or when stuck in difficult terrain."
    })

    local GeodesSection = EngProject:CreateSection(RightPage, "Geode Locations", {
        Style = "box",
        Icon = "rbxassetid://9019175526",
        DefaultExpanded = false,
        TextSize = 15
    })

    local geodeStatus = EngProject:CreateParagraph(GeodesSection.Container, "Geode Scanner", {"Scanning..."})

    local geodes = GeodeModule.getModels()
    geodeStatus:SetFields({#geodes > 0 and ("Found " .. #geodes .. " geodes") or "No geodes found"})

    EngProject:CreateButton(GeodesSection.Container, "Teleport to Next Geode", function()
        GeodeModule.teleportToNext(geodeStatus)
    end)

    EngProject:CreateToggle(GeodesSection.Container, "Auto Teleport to Geodes", false, function(state)
        State.Geode.autoLoopEnabled = state

        if State.Geode.teleportConnection then
            State.Geode.teleportConnection:Disconnect()
            State.Geode.teleportConnection = nil
        end

        if not state then
            local list = GeodeModule.getModels()
            geodeStatus:SetFields({#list > 0 and ("Found " .. #list .. " geodes") or "No geodes found"})
            return
        end

        geodeStatus:SetFields({"Auto Navigation: Active"})
        State.Geode.lastTeleportTime = tick()

        State.Geode.teleportConnection = Services.RunService.Heartbeat:Connect(function()
            if tick() - State.Geode.lastTeleportTime >= Config.GEODE_AUTO_LOOP_DELAY then
                GeodeModule.teleportToNext(geodeStatus)
                State.Geode.lastTeleportTime = tick()
            end
        end)
    end)

    local RunesSection = EngProject:CreateSection(RightPage, "Runes", {
        Style = "box",
        Icon = "rbxassetid://104824630248708",
        DefaultExpanded = false,
        TextSize = 15
    })

    local runeStatus = EngProject:CreateParagraph(RunesSection.Container, "Rune Tracker", {"Scanning..."})

    local runes = RuneModule.getList()
    runeStatus:SetFields({#runes > 0 and ("Found " .. #runes .. " runes") or "No runes found"})

    EngProject:CreateButton(RunesSection.Container, "Teleport to Next Rune", function()
        RuneModule.teleportToNext(runeStatus)
    end)

    EngProject:CreateToggle(RunesSection.Container, "Auto Teleport to Runes", false, function(state)
        State.Rune.autoLoopEnabled = state

        if State.Rune.teleportConnection then
            State.Rune.teleportConnection:Disconnect()
            State.Rune.teleportConnection = nil
        end

        if not state then
            local list = RuneModule.getList()
            runeStatus:SetFields({#list > 0 and ("Found " .. #list .. " runes") or "No runes found"})
            return
        end

        runeStatus:SetFields({"Auto Navigation: Active"})
        State.Rune.lastTeleportTime = tick()

        State.Rune.teleportConnection = Services.RunService.Heartbeat:Connect(function()
            if tick() - State.Rune.lastTeleportTime >= Config.RUNE_AUTO_LOOP_DELAY then
                RuneModule.teleportToNext(runeStatus)
                State.Rune.lastTeleportTime = tick()
            end
        end)
    end)
end

local function initializeToolsTab()
    local page = Tabs.Tools.Page
    local LeftPage = page.Left
    local RightPage = page.Right

    local ReforgeSection = EngProject:CreateSection(LeftPage, "Equipment Reforging", {
        Style = "box",
        Icon = "rbxassetid://10516069182",
        DefaultExpanded = true,
        TextSize = 15
    })

    local selectedGUID = nil
    local equipmentInfo = EngProject:CreateParagraph(ReforgeSection.Container, "Equipment Details", {})

    local equipmentReforgeDropdown = EngProject:CreateDropdown(ReforgeSection.Container, "Choose Equipment", {}, nil,
        function(selection)
            if type(selection) ~= "table" then
                selectedGUID = nil
                ReforgeModule.updateInfo(nil, equipmentInfo)
                return
            end
            selectedGUID = selection.guid
            ReforgeModule.updateInfo(selectedGUID, equipmentInfo)
        end)

    EngProject:CreateButton(ReforgeSection.Container, "Load Inventory Equipment", function()
        local equipmentOptions = {}
        local nameCounts = {}

        local bp = getBackpack()
        if bp then
            for _, child in ipairs(bp:GetChildren() or {}) do
                if child and child.GetAttribute and child:GetAttribute("ItemType") == "Equipment" then
                    local baseName = tostring(child.Name or "Unknown")
                    nameCounts[baseName] = (nameCounts[baseName] or 0) + 1

                    local displayName = baseName
                    if nameCounts[baseName] > 1 then
                        displayName = baseName .. " #" .. nameCounts[baseName]
                    end

                    table.insert(equipmentOptions, {
                        text = displayName,
                        guid = child:GetAttribute("GUID")
                    })
                end
            end
        end

        selectedGUID = nil
        pcall(function()
            equipmentReforgeDropdown:SetOptions(equipmentOptions)
        end)
        ReforgeModule.updateInfo(nil, equipmentInfo)
    end)

    EngProject:CreateButton(ReforgeSection.Container, "Reforge Selected Equipment", function()
        local guid = ReforgeModule.perform(selectedGUID)
        if guid then
            ReforgeModule.updateInfo(guid, equipmentInfo)
            pcall(function()
                equipmentReforgeDropdown:SetOptions({})
            end)
        end
    end)

    local PanEnchantsSection = EngProject:CreateSection(RightPage, "Pan Enchantment", {
        Style = "box",
        Icon = "rbxassetid://87273393473760",
        DefaultExpanded = true,
        TextSize = 15
    })

    local selectedMaterial = "Aurorite"
    local targetPanEnchant = "Prismatic"
    local autoEnchantingPan = {false}

    local PanEnchantRemote = ReplicatedStorage.Remotes.Crafting.Enchant

    EngProject:CreateDropdown(PanEnchantsSection.Container, "Enchantment Material", {{
        text = "Aetherite"
    }, {
        text = "Aurorite"
    }}, "Aurorite", function(selection)
        if selection and selection.text then
            selectedMaterial = selection.text
        end
    end)

    EngProject:CreateDropdown(PanEnchantsSection.Container, "Target Enchantment", EnchantModule.getNames("pan"), nil,
        function(selection)
            targetPanEnchant = selection
        end, {
            Description = "Select your desired enchantment. Book-exclusive enchantments OBVIOUSLY cannot be obtained through this method."
        })

    EngProject:CreateButton(PanEnchantsSection.Container, "Apply Enchantment", function()
        local match = EnchantModule.findPanMaterial(selectedMaterial)
        if not match then
            Utility.createNotification("The selected material was not found in your inventory.", 3)
            return
        end
        EnchantModule.enchant(PanEnchantRemote, match, selectedMaterial)
    end)

    EngProject:CreateButton(PanEnchantsSection.Container, "Auto Enchant Until Target", function()
        if autoEnchantingPan[1] then
            autoEnchantingPan[1] = false
            Utility.createNotification("Pan enchantment process has been stopped.", 2)
            return
        end

        autoEnchantingPan[1] = true
        Utility.createNotification("Automatically enchanting pan until " .. targetPanEnchant .. " is achieved.", 3)

        EnchantModule.performAuto(function()
            return EnchantModule.findPanMaterial(selectedMaterial)
        end, PanEnchantRemote, selectedMaterial, targetPanEnchant, autoEnchantingPan)
    end)

    local ShovelEnchantsSection = EngProject:CreateSection(RightPage, "Shovel Enchantment", {
        Style = "box",
        Icon = "rbxassetid://10098013519",
        DefaultExpanded = false,
        TextSize = 15
    })

    local selectedShovelModifier = "Iridescent"
    local targetShovelEnchant = "WellBalanced"
    local autoEnchantingShovel = {false}

    local ShovelEnchantRemote = ReplicatedStorage.Remotes.Crafting.EnchantShovel

    EngProject:CreateDropdown(ShovelEnchantsSection.Container, "Aetherite Modifier", {{
        text = "Iridescent"
    }, {
        text = "Voidtorn"
    }, {
        text = "Electrified"
    }}, nil, function(sel)
        if sel and sel.text then
            selectedShovelModifier = sel.text
        end
    end)

    EngProject:CreateDropdown(ShovelEnchantsSection.Container, "Target Enchantment", EnchantModule.getNames("shovel"),
        nil, function(selection)
            targetShovelEnchant = selection
        end)

    EngProject:CreateButton(ShovelEnchantsSection.Container, "Apply Enchantment", function()
        local shovel = EnchantModule.findShovelMaterial(selectedShovelModifier)
        if not shovel then
            Utility.createNotification("The selected Aetherite variant is not in your inventory.", 3)
            return
        end
        EnchantModule.enchant(ShovelEnchantRemote, shovel, selectedShovelModifier .. " Aetherite")
    end)

    EngProject:CreateButton(ShovelEnchantsSection.Container, "Auto Enchant Until Target", function()
        if autoEnchantingShovel[1] then
            autoEnchantingShovel[1] = false
            Utility.createNotification("Shovel enchantment process has been stopped.", 2)
            return
        end

        autoEnchantingShovel[1] = true
        Utility.createNotification("Automatically enchanting shovel until " .. targetShovelEnchant .. " is achieved.", 3)

        EnchantModule.performAuto(function()
            return EnchantModule.findShovelMaterial(selectedShovelModifier)
        end, ShovelEnchantRemote, selectedShovelModifier .. " Aetherite", targetShovelEnchant, autoEnchantingShovel)
    end)

    EngProject:CreateButton(LeftPage, "Stop All Enchanting", function()
        if autoEnchantingPan then
            autoEnchantingPan[1] = false
        end
        if autoEnchantingShovel then
            autoEnchantingShovel[1] = false
        end
        Utility.createNotification("All active enchantment processes have been terminated.", 3)
    end, {
        Description = "Immediately halts all automatic enchanting for both pan and shovel tools in case of interruption or preference change."
    })
end

local function initializeCraftingTab()
    local page = Tabs.Crafting.Page

    EngProject:CreateSection(page, "Equipment Crafting")

    local craftingStatus = EngProject:CreateParagraph(page, "Crafting Status",
        {"No equipment selected", "Select an equipment to begin"})

    local function tick()
        local eq = State.Crafting.selectedEquipment
        if not eq then
            craftingStatus:SetFields({"No equipment selected", "Select an equipment to begin"})
            return
        end

        if State.Crafting.selectBestOres then
            State.Crafting.selectedMaterials = CraftingModule.selectBest(eq.Data)
        end

        local fields = CraftingModule.buildFields(eq, State.Crafting.selectedMaterials)
        craftingStatus:SetFields(fields)
    end

    local equipmentDropdown = EngProject:CreateDropdown(page, "Select Equipment", {}, nil, function(selection)
        for _, recipe in ipairs(State.Crafting.discoveredRecipes) do
            if recipe.Name == selection then
                State.Crafting.selectedEquipment = recipe
                State.Crafting.selectedMaterials = {}
                tick()
                return
            end
        end
    end)

    EngProject:CreateButton(page, "Load Discovered Recipes", function()
        State.Crafting.discoveredRecipes = CraftingModule.getDiscoveredRecipes()
        local options = {}
        for i = 1, #State.Crafting.discoveredRecipes do
            options[#options + 1] = State.Crafting.discoveredRecipes[i].Name
        end
        equipmentDropdown:SetOptions(options)
        Utility.createNotification("Loaded " .. #options .. " recipes", 3)
    end)

    EngProject:CreateToggle(page, "Auto Select Best Materials", false, function(state)
        State.Crafting.selectBestOres = state
        tick()
    end, {
        Description = "Automatically select highest quality materials when equipment is chosen"
    })

    EngProject:CreateButton(page, "Craft Equipment", function()
        local eq = State.Crafting.selectedEquipment
        if not eq then
            Utility.createNotification("No equipment selected", 3)
            return
        end
        if State.Crafting.selectBestOres then
            State.Crafting.selectedMaterials = CraftingModule.selectBest(eq.Data)
        end
        if not CraftingModule.canCraft(eq.Data, State.Crafting.selectedMaterials) then
            Utility.createNotification("Missing materials", 3)
            return
        end
        local success, result = CraftingModule.craft(eq.Item, State.Crafting.selectedMaterials)
        State.Crafting.selectedMaterials = {}
        task.wait(0.5)
        tick()
        if success then
            Utility.createNotification("Crafted " .. eq.Name .. "!", 3)
        else
            Utility.createNotification("Failed: " .. tostring(result), 3)
        end
    end)

    EngProject:CreateToggle(page, "Enable Automatic Crafting", false, function(state)
        State.Crafting.autocraft = state
        if not state or State.Crafting.autocraftRunning then
            return
        end
        State.Crafting.autocraftRunning = true

        task.spawn(function()
            while State.Crafting.autocraft do
                local eq = State.Crafting.selectedEquipment
                if not eq then
                    task.wait(1)
                else
                    if State.Crafting.selectBestOres then
                        State.Crafting.selectedMaterials = CraftingModule.selectBest(eq.Data)
                    end

                    tick()

                    if CraftingModule.canCraft(eq.Data, State.Crafting.selectedMaterials) then
                        local success, result = CraftingModule.craft(eq.Item, State.Crafting.selectedMaterials)
                        State.Crafting.selectedMaterials = {}
                        task.wait(0.5)
                        tick()
                        if success then
                            task.wait(0.5)
                        else
                            Utility.createNotification("Autocraft failed: " .. tostring(result), 3)
                            task.wait(3)
                        end
                    else
                        task.wait(2)
                    end
                end
            end
            State.Crafting.autocraftRunning = false
        end)
    end, {
        Description = "Continuously craft selected equipment when materials are available"
    })

    EngProject:CreateSection(page, "Firefly Flare Conversion")

    local fireflyAmount = 1
    local FireflyCrafting = false

    EngProject:CreateTextInput(page, "Conversion Amount", "1", function(input)
        local value = tonumber(input)
        if not value or value ~= math.floor(value) or value < 1 or value >= 1000 then
            EngProject:CreateNotification({
                Type = "Error",
                Title = "Invalid Amount",
                Description = "Enter a whole number between 1 and 999."
            })
            return
        end
        fireflyAmount = value
    end, {
        Description = "One Firefly Stone produces one Firefly Flare."
    })

    EngProject:CreateButton(page, "Begin Conversion", function()
        if FireflyCrafting then
            EngProject:CreateNotification({
                Type = "Warning",
                Title = "Already Converting",
                Description = "Conversion already in progress."
            })
            return
        end
        FireflyCrafting = true
        task.spawn(function()
            FireflyModule.craft(fireflyAmount)
            FireflyCrafting = false
        end)
    end, {
        Description = "Convert Firefly Stones to Firefly Flares at the conversion table."
    })

    EngProject:CreateButton(page, "Stop Conversion", function()
        if not FireflyCrafting then
            EngProject:CreateNotification({
                Type = "Info",
                Title = "Idle",
                Description = "No conversion running."
            })
            return
        end
        FireflyModule.stop()
        EngProject:CreateNotification({
            Type = "Warning",
            Title = "Stopping",
            Description = "Halting conversion."
        })
    end)

    EngProject:CreateParagraph(page, "Conversion Requirements",
        {"You must be near the firefly conversion table to begin."})
end

local function initializeFavouriteTab()
    local page = Tabs.Favourite.Page

    EngProject:CreateSection(page, "Item Preservation System")

    local selectedModifiers = {}
    local selectedOre = nil
    local autoFavEnabled = false

    EngProject:CreateDropdown(page, "Select Modifier(s)", CraftingModule.getModifierNames(), nil, function(values)
        selectedModifiers = {}
        for _, v in pairs(values or {}) do
            table.insert(selectedModifiers, v)
        end
    end, {
        MultiSelect = true
    })

    EngProject:CreateButton(page, "Preserve Items By Modifier", function()
        if #selectedModifiers == 0 then
            EngProject:CreateNotification({
                Type = "Warning",
                Title = "No Modifiers Selected",
                Description = "Select at least one modifier first."
            })
            return
        end

        local bp = getBackpack()
        if bp then
            for _, item in pairs(bp:GetChildren()) do
                for _, modifier in ipairs(selectedModifiers) do
                    if FavouriteModule.isValuable(item) and FavouriteModule.matchesModifier(item, modifier) then
                        FavouriteModule.favourite(item)
                        break
                    end
                end
            end
        end

        EngProject:CreateNotification({
            Type = "Success",
            Title = "Complete",
            Description = "Items with selected modifiers have been preserved."
        })
    end)

    EngProject:CreateDropdown(page, "Select Ore Type", CraftingModule.getOreNames(), nil, function(value)
        selectedOre = value
    end)

    EngProject:CreateButton(page, "Preserve Items By Ore", function()
        if not selectedOre then
            EngProject:CreateNotification({
                Type = "Warning",
                Title = "No Ore Selected",
                Description = "Select an ore type first."
            })
            return
        end

        local bp = getBackpack()
        if bp then
            for _, item in pairs(bp:GetChildren()) do
                if FavouriteModule.isValuable(item) and FavouriteModule.matchesOre(item, selectedOre) then
                    FavouriteModule.favourite(item)
                end
            end
        end

        EngProject:CreateNotification({
            Type = "Success",
            Title = "Complete",
            Description = "All matching ore items have been preserved."
        })
    end)

    EngProject:CreateButton(page, "Preserve Ore with Modifiers", function()
        if not selectedOre or #selectedModifiers == 0 then
            EngProject:CreateNotification({
                Type = "Warning",
                Title = "Selection Incomplete",
                Description = "Select both an ore type and at least one modifier."
            })
            return
        end

        local bp = getBackpack()
        if bp then
            for _, item in pairs(bp:GetChildren()) do
                if FavouriteModule.isValuable(item) and FavouriteModule.matchesOre(item, selectedOre) then
                    for _, modifier in ipairs(selectedModifiers) do
                        if FavouriteModule.matchesModifier(item, modifier) then
                            FavouriteModule.favourite(item)
                            break
                        end
                    end
                end
            end
        end

        EngProject:CreateNotification({
            Type = "Success",
            Title = "Complete",
            Description = "Matching items have been preserved."
        })
    end)

    EngProject:CreateToggle(page, "Enable Automatic Preservation", false, function(state)
        autoFavEnabled = state
    end, {
        Description = "Automatically preserve items as they are obtained."
    })

    local function handleAutoFav(item)
        if not autoFavEnabled then
            return
        end
        if not FavouriteModule.isValuable(item) then
            return
        end

        if selectedOre and #selectedModifiers > 0 then
            if FavouriteModule.matchesOre(item, selectedOre) then
                for _, modifier in ipairs(selectedModifiers) do
                    if FavouriteModule.matchesModifier(item, modifier) then
                        task.wait(0.1)
                        FavouriteModule.favourite(item)
                        break
                    end
                end
            end
        elseif selectedOre then
            if FavouriteModule.matchesOre(item, selectedOre) then
                task.wait(0.1)
                FavouriteModule.favourite(item)
            end
        elseif #selectedModifiers > 0 then
            for _, modifier in ipairs(selectedModifiers) do
                if FavouriteModule.matchesModifier(item, modifier) then
                    task.wait(0.1)
                    FavouriteModule.favourite(item)
                    break
                end
            end
        end
    end

    if BackpackTwo then
        BackpackTwo.ChildAdded:Connect(handleAutoFav)
    end
    local bp = Player:FindFirstChild("Backpack")
    if bp then
        bp.ChildAdded:Connect(handleAutoFav)
    else
        task.spawn(function()
            local foundBp = Player:WaitForChild("Backpack", 15)
            if foundBp then
                foundBp.ChildAdded:Connect(handleAutoFav)
            end
        end)
    end

    EngProject:CreateParagraph(page, "Preservation Guide", {"Select Modifier: Choose which modifiers to protect.",
                                                          "Preserve Items By Modifier: Protects all items with selected modifiers.",
                                                          "Select Ore Type: Choose an ore category.",
                                                          "Preserve Items By Ore: Protects all items of that ore.",
                                                          "Preserve Ore with Modifiers: Requires both ore and modifier selections.",
                                                          "Enable Automatic Preservation: Protects newly obtained items based on your selections."})
end

local function initializeShopTab()
    local page = Tabs.Shop.Page

    EngProject:CreateSection(page, "Marketplace")

    EngProject:CreateParagraph(page, "Marketplace Access", {"Browse and purchase items from the amazong marketplace.",
        "Klik Open Marketplace untuk membuka/menutup toko.",
        "Jika tidak berhasil, klik 'Cari GUI Marketplace' untuk debug."})

    EngProject:CreateButton(page, "Open Marketplace", function()
        amazong:Toggle()
    end)

    EngProject:CreateButton(page, "Cari GUI Marketplace (Debug)", function()
        local PlayerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
        local names = {}
        for _, gui in ipairs(PlayerGui:GetChildren()) do
            if gui:IsA("ScreenGui") then
                table.insert(names, gui.Name .. " [" .. (gui.Enabled and "ON" or "OFF") .. "]")
            end
        end
        EngProject:CreateNotification({
            Type = "Info",
            Title = "Daftar GUI di PlayerGui:",
            Description = table.concat(names, ", "),
            Duration = 15
        })
    end)

    EngProject:CreateButton(page, "Toggle GUI by Name (Manual)", function()
        local PlayerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
        -- Coba toggle semua ScreenGui yang bukan HUD utama
        local skipList = {"EngProjectUI", "RobloxGui", "TopBarApp", "BillboardGui"}
        local function isSkipped(name)
            for _, s in ipairs(skipList) do
                if name:find(s) then return true end
            end
            return false
        end
        local count = 0
        for _, gui in ipairs(PlayerGui:GetChildren()) do
            if gui:IsA("ScreenGui") and not isSkipped(gui.Name) then
                gui.Enabled = not gui.Enabled
                count = count + 1
            end
        end
        EngProject:CreateNotification({
            Type = "Info",
            Title = "Toggle GUI",
            Description = count .. " ScreenGui di-toggle",
            Duration = 5
        })
    end)
end

local function initializeMiscellaneousTab()
    local page = Tabs.Miscellaneous.Page
    local LeftPage = page.Left
    local RightPage = page.Right

    local ExcavationSection = EngProject:CreateSection(LeftPage, "Archaeological Sites", {
        Style = "box",
        Icon = "rbxassetid://14257565324",
        DefaultExpanded = true,
        TextSize = 15
    })

    local excavationStatus = EngProject:CreateParagraph(ExcavationSection.Container, "Site Status",
        {"Idle", "No site selected"})

    EngProject:CreateDropdown(ExcavationSection.Container, "Select Excavation Site", ExcavationModule.getNames(), nil,
        function(s)
            State.Excavation.selected = s
            excavationStatus:SetFields({"Status: Ready", "Selected: " .. tostring(s)})
        end, {
            Save = {
                Key = "prospecting.excavation.selected_site"
            }
        })

    EngProject:CreateButton(ExcavationSection.Container, "Begin Excavation", function()
        if not State.Excavation.selected then
            excavationStatus:SetFields({"Status: Error", "No site selected"})
            return
        end

        local ok, msg = ExcavationModule.start()
        if ok then
            excavationStatus:SetFields({"Status: Running", "Site: " .. State.Excavation.selected})
        else
            excavationStatus:SetFields({"Status: Failed", tostring(msg)})
        end
    end)

    EngProject:CreateToggle(ExcavationSection.Container, "Auto Claim Rewards", true, function(state)
        State.Excavation.autoClaim = state
        excavationStatus:SetFields({"Status: " .. (state and "Auto-Claim Enabled" or "Auto-Claim Disabled"),
                                    "Site: " .. tostring(State.Excavation.selected)})

        if not state then
            return
        end

        task.spawn(function()
            while State.Excavation.autoClaim do
                if ExcavationModule.getCurrentStatus() == "Finished" then
                    ExcavationModule.claim()
                end
                task.wait(1)
            end
        end)
    end, {
        Save = {
            Key = "prospecting.excavation.auto_claim"
        }
    })

    EngProject:CreateToggle(ExcavationSection.Container, "Auto Start Excavation", false, function(state)
        State.Excavation.autoStart = state

        if not state then
            excavationStatus:SetFields({"Status: Auto-Start Disabled", "Site: " .. tostring(State.Excavation.selected)})
            return
        end

        if State.Excavation.autoStartRunning then
            excavationStatus:SetFields({"Status: Auto-Start Running", "Site: " .. tostring(State.Excavation.selected)})
            return
        end

        State.Excavation.autoStartRunning = true
        excavationStatus:SetFields({"Status: Auto-Start Enabled", "Site: " .. tostring(State.Excavation.selected)})

        task.spawn(function()
            while State.Excavation.autoStart do
                if not State.Excavation.selected then
                    excavationStatus:SetFields({"Status: Waiting", "Select an excavation site to auto-start"})
                    task.wait(2)
                    continue
                end

                local ok, msg = ExcavationModule.autoStartCycle()
                if ok then
                    excavationStatus:SetFields({"Status: Running", "Site: " .. tostring(State.Excavation.selected)})
                elseif msg ~= "Excavation already active." then
                    excavationStatus:SetFields({"Status: Waiting", tostring(msg)})
                end

                task.wait(5)
            end

            State.Excavation.autoStartRunning = false
        end)
    end, {
        Save = {
            Key = "prospecting.excavation.auto_start"
        }
    })

    local PlayerSettingsSection = EngProject:CreateSection(LeftPage, "Character Settings", {
        Style = "box",
        Icon = {
            Image = "rbxassetid://16898613869",
            Size = UDim2.new(0, 16, 0, 16),
            ImageRectSize = Vector2.new(48, 48),
            ImageRectOffset = Vector2.new(404, 869)
        },
        DefaultExpanded = false,
        TextSize = 15
    })

    EngProject:CreateSection(PlayerSettingsSection.Container, "Humanoid Properties")

    local jumpPower = (Humanoid and Humanoid.JumpPower) or 50
    local walkSpeedValue = Humanoid and Humanoid.WalkSpeed or 16

    local function applySavedHumanoidSettings()
        if not Humanoid then
            return
        end

        Humanoid.WalkSpeed = walkSpeedValue
        Humanoid.UseJumpPower = true
        Humanoid.JumpPower = jumpPower
    end

    EngProject:CreateSlider(PlayerSettingsSection.Container, "Movement Speed", 0, 100, walkSpeedValue, function(val)
        pcall(function()
            walkSpeedValue = val
            State.Speed = val
            applySavedHumanoidSettings()
        end)
    end, {
        Save = {
            Key = "prospecting.character.walk_speed"
        }
    })

    if Humanoid then
        Humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            if Humanoid.WalkSpeed ~= walkSpeedValue then
                Humanoid.WalkSpeed = walkSpeedValue
            end
        end)
    end

    EngProject:CreateSlider(PlayerSettingsSection.Container, "Jump Height", 1, 100, jumpPower, function(val)
        pcall(function()
            jumpPower = val
            applySavedHumanoidSettings()
        end)
    end, {
        Save = {
            Key = "prospecting.character.jump_power"
        }
    })

    if Humanoid then
        Humanoid:GetPropertyChangedSignal("JumpPower"):Connect(function()
            if Humanoid.JumpPower ~= jumpPower then
                Humanoid.UseJumpPower = true
                Humanoid.JumpPower = jumpPower
            end
        end)
    end

    Player.CharacterAdded:Connect(function()
        task.wait(1)
        applySavedHumanoidSettings()
    end)

    EngProject:CreateSlider(PlayerSettingsSection.Container, "Camera Field of View", 30, 120, Camera.FieldOfView,
        function(value)
            Camera.FieldOfView = value
        end, {
            Increment = 1,
            Save = {
                Key = "prospecting.character.camera_fov"
            }
        })

    local fogDensity = 0.1
    local atmosphere = Services.Lighting:FindFirstChildWhichIsA("Atmosphere") or
                           Instance.new("Atmosphere", Services.Lighting)

    Services.RunService.RenderStepped:Connect(function()
        if atmosphere then
            atmosphere.Density = math.clamp(fogDensity, 0, 1)
        end
    end)

    EngProject:CreateSlider(PlayerSettingsSection.Container, "Environmental Fog Density", 0.30, 1, 0.40, function(value)
        fogDensity = value
    end, {
        Increment = 0.01,
        Save = {
            Key = "prospecting.character.fog_density"
        }
    })

    local RemoveBarriersSection = EngProject:CreateSection(RightPage, "Environmental Barriers", {
        Style = "box",
        Icon = {
            Image = "rbxassetid://16898613869",
            Size = UDim2.new(0, 16, 0, 16),
            ImageRectSize = Vector2.new(48, 48),
            ImageRectOffset = Vector2.new(820, 355)
        },
        DefaultExpanded = false,
        TextSize = 15
    })

    EngProject:CreateToggle(RemoveBarriersSection.Container, "Disable Vine Blockades", false, function(state)
        State.Barriers.vines = state
        if not BarrierRemovalModule.toggleVines(state) then
            Utility.createNotification("Vine blockades were not found.", 4)
        end
    end, {
        Description = "Temporarily disables vine collision without deleting the objects.",
        Save = {
            Key = "prospecting.barriers.vines"
        }
    })

    EngProject:CreateToggle(RemoveBarriersSection.Container, "Disable Abyssal Gate", false, function(state)
        State.Barriers.abyssalGate = state
        if not BarrierRemovalModule.toggleAbyssalGate(state) then
            Utility.createNotification("Abyssal Gate was not found.", 4)
        end
    end, {
        Description = "Temporarily disables the Abyssal Gate collision and can restore it.",
        Save = {
            Key = "prospecting.barriers.abyssal_gate"
        }
    })

    EngProject:CreateToggle(RemoveBarriersSection.Container, "Disable Peak Obstruction", false, function(state)
        State.Barriers.peakObstruction = state
        if not BarrierRemovalModule.toggleMountainBlock(state) then
            Utility.createNotification("Peak obstruction was not found.", 4)
        end
    end, {
        Description = "Temporarily disables the summit blockage and can restore it.",
        Save = {
            Key = "prospecting.barriers.peak_obstruction"
        }
    })

    local ServerSection = EngProject:CreateSection(RightPage, "Server Management", {
        Style = "box",
        Icon = "rbxassetid://10723405749",
        DefaultExpanded = true,
        TextSize = 15
    })

    EngProject:CreateToggle(ServerSection.Container, "Enable Anti-AFK Protection", true, function(state)
        ServerUtilityModule.setupAntiAFK(state)
    end)

    EngProject:CreateButton(ServerSection.Container, "Rejoin Current Server", function()
        ServerUtilityModule.rejoin()
    end)

    EngProject:CreateButton(ServerSection.Container, "Server Hop", function()
        ServerUtilityModule.serverHop()
    end)

    local EspBox = EngProject:CreateSection(RightPage, "ESP", {
        Style = "box",
        DefaultExpanded = false,
        TextSize = 15
    })

    EngProject:CreateToggle(EspBox.Container, "Highlight Players", false, function(enabled)
        if enabled then
            ESPModule.enablePlayers()
        else
            ESPModule.disablePlayers()
        end
    end)

    EngProject:CreateToggle(EspBox.Container, "Highlight Totems", false, function(enabled)
        if enabled then
            ESPModule.enableTotems()
        else
            ESPModule.disableTotems()
        end
    end)

    EngProject:CreateButton(EspBox.Container, "Clear All Highlights", function()
        ESPModule.clearAll()
    end)
end

local function initializeSettingsTab()
    local page = Tabs.Settings.Page

    EngProject:CreateSection(page, "Interface Customization")

    EngProject:CreateToggle(page, "Enable Inventory Filtering", true, function(state)
        if state then
            InventoryFilterModule.create()
        else
            InventoryFilterModule.destroy()
        end
    end, {
        Save = {
            Key = "prospecting.settings.inventory_filter"
        }
    })

    EngProject:CreateSlider(page, "Interface Scale", 0.5, 2, window.GetScale(), function(value)
        window:SetScale(value, true)
    end, {
        Increment = 0.001,
        Save = {
            Key = "prospecting.settings.interface_scale"
        }
    })

    local themes = {}
    for name in pairs(EngProject.Themes) do
        themes[#themes + 1] = name
    end

    EngProject:CreateDropdown(page, "Select Color Theme", themes, nil, function(val)
        window:SetTheme(val, true)
    end, {
        Description = "Choose from " .. (#themes > 0 and #themes or "a variety of") .. " available themes.",
        Save = {
            Key = "prospecting.settings.theme"
        }
    })

    if not EngProject.Utility:IsMobile() then
        EngProject:CreateKeybind(page, "Toggle Interface Visibility", Enum.KeyCode.Q, function(key)
            window.Toggle()
        end, {
            Save = {
                Key = "prospecting.settings.toggle_keybind"
            }
        })
    end
end

local function initializeTravelMerchantTab()
    local page = Tabs.TravelMerchant.Page
    local LeftPage = page.Left
    local RightPage = page.Right

    local MerchantBuySection = EngProject:CreateSection(LeftPage, "Travel Merchant Auto Buy", {
        Style = "box",
        Icon = "rbxassetid://10734952479",
        DefaultExpanded = true,
        TextSize = 15
    })

    local statsParagraph = EngProject:CreateParagraph(MerchantBuySection.Container, "Statistics",
        {"Total bought: 0", "Status: Idle"})

    task.spawn(function()
        while true do
            pcall(function()
                statsParagraph:SetFields({
                    "Total bought: " .. tostring(State.TravelMerchant.totalBought),
                    "Status: " .. (State.TravelMerchant.running and "Running" or "Idle")
                })
            end)
            task.wait(1)
        end
    end)

    EngProject:CreateDropdown(MerchantBuySection.Container, "Select Items to Buy", TravelMerchantModule.KnownItems, nil,
        function(values)
            State.TravelMerchant.selectedItems = {}
            for _, v in pairs(values or {}) do
                table.insert(State.TravelMerchant.selectedItems, v)
            end
            TravelMerchantModule.selectedItems = State.TravelMerchant.selectedItems
        end, {
            MultiSelect = true
        })

    EngProject:CreateToggle(MerchantBuySection.Container, "Use Money", true, function(state)
        State.TravelMerchant.useMoney = state
    end)

    EngProject:CreateToggle(MerchantBuySection.Container, "Use Shard", false, function(state)
        State.TravelMerchant.useShard = state
    end)

    local function disableAutoBuy(reason)
        State.TravelMerchant.running = false
        TravelMerchantModule.running = false
        if TravelMerchantModule.restockBindable then
            pcall(function() TravelMerchantModule.restockBindable:Fire() end)
        end
        Utility.createNotification("Auto Buy OFF: " .. reason, 5)
    end

    EngProject:CreateToggle(MerchantBuySection.Container, "Enable Auto Buy", false, function(state)
        State.TravelMerchant.running = state
        TravelMerchantModule.running = state

        if not state then return end

        if not State.TravelMerchant.useMoney and not State.TravelMerchant.useShard then
            disableAutoBuy("Select filter first (Use Money / Use Shard)!")
            return
        end

        if #State.TravelMerchant.selectedItems == 0 then
            disableAutoBuy("Select items to buy first!")
            return
        end

        task.spawn(function()
            Utility.createNotification("Travel Merchant Auto Buy ON", 3)

            while State.TravelMerchant.running do
                local m = State.TravelMerchant.useMoney
                local s = State.TravelMerchant.useShard
                if not m and not s then
                    disableAutoBuy("All filters turned off!")
                    break
                end

                local boughtThisRound = 0
                for _, itemName in ipairs(State.TravelMerchant.selectedItems) do
                    if not State.TravelMerchant.running then break end

                    local success, reason = TravelMerchantModule.buyAndValidate(itemName, m, s)
                    if success then
                        State.TravelMerchant.totalBought = State.TravelMerchant.totalBought + 1
                        boughtThisRound = boughtThisRound + 1
                        Utility.createNotification("Bought: " .. itemName, 2)
                    end
                    task.wait(1)
                end

                if boughtThisRound == 0 and State.TravelMerchant.running then
                    Utility.createNotification("All stock depleted. Waiting for restock...", 3)
                    TravelMerchantModule.waitForRestock()
                    if State.TravelMerchant.running then
                        Utility.createNotification("Restock detected! Continuing...", 3)
                    end
                end
            end
        end)
    end)

    EngProject:CreateButton(MerchantBuySection.Container, "Reset Counter", function()
        State.TravelMerchant.totalBought = 0
        Utility.createNotification("Counter reset!", 2)
    end)

    EngProject:CreateButton(MerchantBuySection.Container, "Buy Selected Now", function()
        if #State.TravelMerchant.selectedItems == 0 then
            Utility.createNotification("Select items first!", 2)
            return
        end
        local m = State.TravelMerchant.useMoney
        local s = State.TravelMerchant.useShard
        if not m and not s then
            Utility.createNotification("Select filter first!", 2)
            return
        end

        task.spawn(function()
            local bought = 0
            for _, itemName in ipairs(State.TravelMerchant.selectedItems) do
                local success, reason = TravelMerchantModule.buyAndValidate(itemName, m, s)
                if success then
                    bought = bought + 1
                    State.TravelMerchant.totalBought = State.TravelMerchant.totalBought + 1
                    Utility.createNotification("Bought: " .. itemName, 2)
                end
                task.wait(1)
            end
            Utility.createNotification("Manual Purchase complete. Bought: " .. bought, 4)
        end)
    end)
end

local function initializeSummerCollectionTab()
    local page = Tabs.Summer.Page
    local LeftPage = page.Left
    local RightPage = page.Right

    local CauldronSection = EngProject:CreateSection(LeftPage, "Summer Cauldron", {
        Style = "box",
        Icon = "rbxassetid://10734963191",
        DefaultExpanded = true,
        TextSize = 15
    })

    local summerStatus = EngProject:CreateParagraph(CauldronSection.Container, "Status",
        {"Waiting for data..."})

    local function updateSummerDisplay()
        local syncedTime = Services.Workspace:GetAttribute("SyncedTime") or 0
        local content = {}

        if State.Summer.progress < 10 then
            content = {
                "Progress: " .. tostring(State.Summer.progress) .. "/10",
                "Quality: " .. string.format("%.0f%%", State.Summer.quality * 100)
            }
        else
            local sisa = State.Summer.deliveryTime - syncedTime + 3600
            if sisa > 0 then
                local menit = math.floor(sisa / 60)
                local detik = math.floor(sisa % 60)
                content = {
                    "Progress: 10/10 (FULL)",
                    "Quality: " .. string.format("%.0f%%", State.Summer.quality * 100),
                    string.format("Delivery in: %02d:%02d", menit, detik)
                }
            else
                content = {
                    "Progress: 10/10 (FULL)",
                    "Quality: " .. string.format("%.0f%%", State.Summer.quality * 100),
                    "READY TO CLAIM!"
                }
            end
        end
        summerStatus:SetFields(content)
    end

    task.spawn(function()
        while true do
            pcall(updateSummerDisplay)
            task.wait(1)
        end
    end)

    local allRarities = SummerModule.getAllRarities()

    EngProject:CreateDropdown(CauldronSection.Container, "Select Modifiers", SummerModule.ModifierPriority, nil,
        function(values)
            State.Summer.selectedModifiers = {}
            for _, v in pairs(values or {}) do
                table.insert(State.Summer.selectedModifiers, v)
            end
        end, {
            MultiSelect = true,
            Description = "Priority: Hearthflame > Tidal > Summer"
        })

    EngProject:CreateDropdown(CauldronSection.Container, "Select Rarities", allRarities, nil,
        function(values)
            State.Summer.selectedRarities = {}
            for _, v in pairs(values or {}) do
                table.insert(State.Summer.selectedRarities, v)
            end
        end, {
            MultiSelect = true,
            Description = "Priority: Exotic > Mythic > ... > Common"
        })

    local itemInfoParagraph = EngProject:CreateParagraph(CauldronSection.Container, "Matching Items Info",
        {"Scanning inventory..."})

    task.spawn(function()
        while true do
            pcall(function()
                local total = SummerModule.countAllMatchingTools()
                local nextTool, nextMod, nextRar = SummerModule.findBestToolByPriority()

                local info = {
                    "Matching items: " .. tostring(total),
                    "Progress: " .. tostring(State.Summer.progress) .. "/10"
                }
                if nextMod and nextRar then
                    table.insert(info, "Next up: " .. nextMod .. " + " .. nextRar)
                elseif #State.Summer.selectedModifiers > 0 and #State.Summer.selectedRarities > 0 then
                    table.insert(info, "Next up: No matching items")
                else
                    table.insert(info, "Next up: Select filters first")
                end
                itemInfoParagraph:SetFields(info)
            end)
            task.wait(2)
        end
    end)

    local ClaimCauldron = ReplicatedStorage:FindFirstChild("Remotes")
        and ReplicatedStorage.Remotes:FindFirstChild("TemporaryEvents")
        and ReplicatedStorage.Remotes.TemporaryEvents:FindFirstChild("ClaimCauldron")

    local AddCauldronItem = ReplicatedStorage:FindFirstChild("Remotes")
        and ReplicatedStorage.Remotes:FindFirstChild("TemporaryEvents")
        and ReplicatedStorage.Remotes.TemporaryEvents:FindFirstChild("AddCauldronItem")

    local UpdateCauldronData = ReplicatedStorage:FindFirstChild("Remotes")
        and ReplicatedStorage.Remotes:FindFirstChild("TemporaryEvents")
        and ReplicatedStorage.Remotes.TemporaryEvents:FindFirstChild("UpdateCauldronData")

    EngProject:CreateToggle(CauldronSection.Container, "Auto Add + Claim", false, function(state)
        State.Summer.autoAddRunning = state

        if not state then return end

        if #State.Summer.selectedModifiers == 0 then
            State.Summer.autoAddRunning = false
            Utility.createNotification("Select at least 1 modifier!", 3)
            return
        end
        if #State.Summer.selectedRarities == 0 then
            State.Summer.autoAddRunning = false
            Utility.createNotification("Select at least 1 rarity!", 3)
            return
        end

        task.spawn(function()
            local totalAdded = 0
            Utility.createNotification("Auto Add + Claim Cauldron ON", 4)

            while State.Summer.autoAddRunning do

                -- PHASE 1: ADD ITEMS
                while State.Summer.autoAddRunning and State.Summer.progress < 10 do
                    local tool, mod, rar = SummerModule.findBestToolByPriority()

                    if not tool then
                        local waited = 0
                        while State.Summer.autoAddRunning and waited < 30 do
                            task.wait(1)
                            waited = waited + 1
                        end
                        tool, mod, rar = SummerModule.findBestToolByPriority()
                        if not tool and State.Summer.autoAddRunning then
                            Utility.createNotification("No matching tools. Scanning...", 3)
                        end
                    end

                    if not State.Summer.autoAddRunning then break end
                    if not tool then continue end

                    local equipped = SummerModule.summerEquipTool(tool)
                    if not equipped then
                        task.wait(1)
                        continue
                    end

                    local equippedTool = Player.Character:FindFirstChildOfClass("Tool")
                    if not equippedTool then
                        task.wait(1)
                        continue
                    end

                    local ok = pcall(function()
                        AddCauldronItem:InvokeServer(equippedTool)
                    end)

                    if ok then
                        totalAdded = totalAdded + 1
                        Utility.createNotification(string.format("Added: %s + %s (%d/10)", mod, rar, State.Summer.progress + 1), 2)
                    end
                    task.wait(1)
                end

                if not State.Summer.autoAddRunning then break end

                -- PHASE 2: WAIT FOR RESET
                Utility.createNotification("Cauldron full! Waiting for delivery/claim...", 3)

                while State.Summer.autoAddRunning and State.Summer.progress >= 10 do
                    task.wait(2)

                    if State.Summer.progress >= 10 then
                        local syncedTime = Services.Workspace:GetAttribute("SyncedTime") or 0
                        local sisa = State.Summer.deliveryTime - syncedTime + 3600
                        if sisa <= 0 then
                            local ok, result = pcall(function()
                                return ClaimCauldron:InvokeServer()
                            end)
                            if ok and result then
                                Utility.createNotification("Reward claimed successfully! Waiting for next cycle...", 5)
                                task.wait(3)
                            end
                        end
                    end
                end

                if not State.Summer.autoAddRunning then break end
                Utility.createNotification("New cycle started! Continuing...", 3)
            end
        end)
    end)

    EngProject:CreateButton(CauldronSection.Container, "Claim Cauldron Reward", function()
        local ok, result = pcall(function()
            return ClaimCauldron:InvokeServer()
        end)
        if ok and result then
            Utility.createNotification("Reward claimed successfully!", 3)
        else
            Utility.createNotification("Claim failed. Not ready yet.", 3)
        end
    end)

    EngProject:CreateButton(CauldronSection.Container, "Refresh Cauldron Data", function()
        pcall(function() UpdateCauldronData:FireServer() end)
        Utility.createNotification("Data refreshed!", 2)
    end)
end

SummerModule.init()

initializeDashboardTab()
initializeMainTab()
initializeHuntingTab()
initializeTeleportTab()
initializeToolsTab()
initializeCraftingTab()
initializeFavouriteTab()
initializeShopTab()
initializeTravelMerchantTab()
initializeSummerCollectionTab()
initializeMiscellaneousTab()
initializeSettingsTab()

if EngProject.Utility:IsMobile() then
    MobileUIModule.createToggleButton(window)
end
