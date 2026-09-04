-- Antarctica Hub (ObsidianUltra UI): vacuum-only pickup + auto sell, TANPA dig
-- Game: Mine Antarctica | Freed = bebas ambil (tak ada pemilik) | Nempel = wajib dig manual
-- Cara kerja: DroppedGems prioritas -> Freed, teleport stepped -> fire prompt (hold 0)
-- UI: https://github.com/joustingmatch/ObsidianUltra (fork Obsidian, API kompatibel)
-- Debug: getgenv()._ANT_HUB_DBG() | Unload: getgenv()._ANT_HUB_UNLOAD()

if getgenv()._ANT_HUB_UNLOAD then
    pcall(getgenv()._ANT_HUB_UNLOAD)
    getgenv()._ANT_HUB_UNLOAD = nil
end

pcall(function()
    local hui = gethui and gethui() or game:GetService("CoreGui")
    for _, old in ipairs(hui:GetDescendants()) do
        if old:IsA("ScreenGui") and old.Name == "Obsidian" then
            old:Destroy()
        end
    end
end)

local repo = "https://raw.githubusercontent.com/joustingmatch/ObsidianUltra/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager, SaveManager
pcall(function() ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))() end)
pcall(function() SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))() end)

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunS = game:GetService("RunService")
local LP = Players.LocalPlayer

local RequestSell = RS:WaitForChild("GemRemotes"):WaitForChild("RequestSell")
local TeleportSell = RS:WaitForChild("BackpackRemotes"):WaitForChild("TeleportSell")
local BuyUpgrade = RS:WaitForChild("UpgradeRemotes"):WaitForChild("BuyUpgrade")
local UpgradeState = RS:WaitForChild("UpgradeRemotes"):WaitForChild("UpgradeState")
local BuyPickaxe = RS:WaitForChild("ShopRemotes"):WaitForChild("BuyPickaxe")
local EquipPickaxe = RS:WaitForChild("ShopRemotes"):WaitForChild("EquipPickaxe")
local BuyBomb = RS:WaitForChild("BombRemotes"):WaitForChild("BuyBomb")
local PickaxeData = require(RS:WaitForChild("PickaxeData"))
local BombData = require(RS:WaitForChild("BombData"))
local SG = workspace:WaitForChild("SpawnedGems")
local DG = workspace:WaitForChild("DroppedGems")

local RARITY_LIST = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Exotic" }
local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Exotic = 7 }
local RARITY_HEX = { Common = "#CD945C", Uncommon = "#5FDC69", Rare = "#469BFF", Epic = "#B45FFF", Legendary = "#FFAA2D", Mythic = "#FF4646", Exotic = "#FFD84A" }
local Cfg = { vacuum = false, teleport = false, autoSell = false, sellPct = 100, minRarity = 1, monRarity = 1, monSort = "Value", fly = false, flySpeed = 50, noclip = false, speed = false, speedVal = 32, upWarmth = false, upCarry = false, reserve = 0, bombSel = { "ClassicBomb" }, autoBomb = false, pickSel = 9 }
local Stat = { selling = false, basePos = nil, tryAt = {}, swept = false }

-- angka tuning satu tempat (jarak server: prompt ~15-17, dig <12)
local TUNE = {
    pickupRange = 14, -- fire langsung tanpa teleport (stud, dari part prompt)
    tpLift = 4, -- melayang di atas mesh (stud)
    settleWait = 0.7, -- tunggu replikasi posisi server pasca-TP (detik)
    retryS = 3, -- jeda coba ulang per crystal (detik)
    tickS = 0.4, -- interval loop vacuum (detik)
    sellTpWait = 1.5, sellWait = 1, -- tunggu sell (detik)
    monEveryS = 5, monTickS = 1, -- refresh monitor (detik)
    tpStep = 55, tpInstant = 60, tpStepWait = 0.05, -- teleport stepped (stud, stud, detik)
    promptRange = 1000, promptRestore = 0.3, -- fire prompt (stud, detik)
}

-- helper di atas UI: callback tombol capture local ini (qentury/cake taruh helper duluan juga)
local function getHRP()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- posisi klaim: part prompt (server cek jarak ke situ, BUKAN pivot model yg ngaco)
local function claimPos(m, pr)
    local pp = pr and pr.Parent
    if pp and pp:IsA("BasePart") then
        return pp.Position
    end
    local mesh = m:FindFirstChild("Mesh_0", true)
    if mesh then
        return mesh.Position
    end
    local ok, piv = pcall(function() return m:GetPivot().Position end)
    if ok then
        return piv
    end
    return nil
end

local function tpTo(h, cf)
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local goal = cf.Position
    local dist = (h.Position - goal).Magnitude
    if dist <= TUNE.tpInstant then
        pcall(function()
            h.AssemblyLinearVelocity = Vector3.zero
            h.AssemblyAngularVelocity = Vector3.zero
            char:PivotTo(cf)
        end)
        return
    end
    -- stepped tanpa anchor (anchor memicu hukuman server). PivotTo + Freefall.
    local start = h.Position
    local steps = math.ceil(dist / TUNE.tpStep)
    for i = 1, steps do
        if not h.Parent then
            return
        end
        pcall(function()
            if hum then
                hum:ChangeState(Enum.HumanoidStateType.Freefall)
            end
            h.AssemblyLinearVelocity = Vector3.zero
            h.AssemblyAngularVelocity = Vector3.zero
            char:PivotTo(CFrame.new(start:Lerp(goal, i / steps)))
        end)
        task.wait(TUNE.tpStepWait)
    end
    pcall(function()
        char:PivotTo(CFrame.new(goal))
        h.AssemblyLinearVelocity = Vector3.zero
    end)
end

local function countBag()
    local n = 0
    local bp = LP:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and t:GetAttribute("BagId") ~= nil then
                n += 1
            end
        end
    end
    local c = LP.Character
    if c then
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") and t:GetAttribute("BagId") ~= nil then
                n += 1
            end
        end
    end
    return n
end

-- persen tas: kg tool / atribut CarryWeight (cara game hitung bar tas)
local function bagPct()
    local used = 0
    local function scan(container)
        if not container then
            return
        end
        for _, t in ipairs(container:GetChildren()) do
            if t:IsA("Tool") and t:GetAttribute("BagId") ~= nil then
                used += tonumber(t:GetAttribute("Kg")) or 0
            end
        end
    end
    scan(LP:FindFirstChild("Backpack"))
    scan(LP.Character)
    local cap = tonumber(LP:GetAttribute("CarryWeight")) or 0
    if cap <= 0 then
        return 0
    end
    return used / cap * 100
end

local function notify(title, desc)
    pcall(function() Library:Notify({ Title = title, Description = desc, Time = 5 }) end)
end

local function firePrompt(pr)
    if not pr or not pr.Parent then
        return false
    end
    local saved = {
        hold = pr.HoldDuration,
        sight = pr.RequiresLineOfSight,
        enabled = pr.Enabled,
        range = pr.MaxActivationDistance,
    }
    pcall(function()
        pr.HoldDuration = 0
        pr.RequiresLineOfSight = false
        pr.Enabled = true
        pr.MaxActivationDistance = TUNE.promptRange
    end)
    local ok = pcall(fireproximityprompt, pr)
    if not ok then
        ok = pcall(function()
            pr:InputHoldBegin()
            pr:InputHoldEnd()
        end)
    end
    task.delay(TUNE.promptRestore, function()
        if pr.Parent then
            pcall(function()
                pr.HoldDuration = saved.hold
                pr.RequiresLineOfSight = saved.sight
                pr.Enabled = saved.enabled
                pr.MaxActivationDistance = saved.range
            end)
        end
    end)
    return ok
end

Stat.skipPick = Stat.skipPick or {}
Stat.skipBomb = Stat.skipBomb or {}

local function buyPickaxe(idx, manual)
    local info = PickaxeData[idx]
    if not info then
        return false
    end
    if Stat.skipPick[idx] and not manual then
        return false
    end
    local coins = LP.leaderstats.Coins.Value
    if coins - tonumber(info.price or 0) < Cfg.reserve then
        return false
    end
    BuyPickaxe:FireServer(idx, "cash")
    task.wait(2)
    if LP.leaderstats.Coins.Value < coins then
        pcall(function() EquipPickaxe:FireServer(idx) end)
        Stat.skipPick[idx] = nil
        notify("Pickaxe", "Beli + equip: " .. info.name)
        print("[hub] beli pickaxe " .. info.name)
        return true
    end
    if not manual then
        Stat.skipPick[idx] = true
    end
    return false
end

local function bombPrice(id)
    local b = BombData.ById and BombData.ById[id]
    return b and tonumber(b.price) or nil
end

local function buyBombs()
    local sel = {}
    for _, id in ipairs(Cfg.bombSel) do
        if not Stat.skipBomb[id] then
            local price = bombPrice(id)
            if price then
                table.insert(sel, { id = id, price = price })
            end
        end
    end
    table.sort(sel, function(a, b) return a.price < b.price end)
    for _, b in ipairs(sel) do
        local coins = LP.leaderstats.Coins.Value
        if coins - b.price >= Cfg.reserve then
            BuyBomb:FireServer(b.id, "cash")
            task.wait(2)
            if LP.leaderstats.Coins.Value < coins then
                notify("Bomb", "Beli: " .. b.id)
                print("[hub] beli bomb " .. b.id)
                return true
            else
                Stat.skipBomb[b.id] = true
            end
        end
    end
    return false
end

local flyBV, flyBG, flyConn
local function stopFly()
    if flyConn then
        pcall(function() flyConn:Disconnect() end)
        flyConn = nil
    end
    if flyBV then
        pcall(function() flyBV:Destroy() end)
        flyBV = nil
    end
    if flyBG then
        pcall(function() flyBG:Destroy() end)
        flyBG = nil
    end
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.PlatformStand = false
    end
end

local function restoreCollide()
    local char = LP.Character
    if char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then
                p.CanCollide = true
            end
        end
    end
end

local alive = true
local RL_STATE = rawget(getgenv(), "STATE")
if typeof(RL_STATE) ~= "table" then
    RL_STATE = nil
end
getgenv()._ANT_HUB_UNLOAD = function()
    alive = false
    Cfg.fly = false
    Cfg.noclip = false
    Cfg.speed = false
    pcall(stopFly)
    pcall(restoreCollide)
    pcall(function()
        local char = LP.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.WalkSpeed = 16
        end
    end)
    pcall(function() Library:Unload() end)
    print("[hub] unloaded")
end
if RL_STATE then
    RL_STATE.onCleanup(function()
        alive = false
        Cfg.fly = false
        Cfg.noclip = false
        pcall(stopFly)
        pcall(restoreCollide)
        pcall(function() Library:Unload() end)
    end)
end

-- movement (fly + noclip), pola cake file
local noclipConn
task.spawn(function()
    while alive and (RL_STATE == nil or RL_STATE.alive()) do
        task.wait(0.2)
        if not alive or (RL_STATE and not RL_STATE.alive()) then
            break
        end
        -- fly manager
        local wantFly = Cfg.fly
        local hasFly = flyBV ~= nil
        if wantFly and not hasFly then
            local char = LP.Character
            local h = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if h and hum then
                hum.PlatformStand = true
                flyBG = Instance.new("BodyGyro")
                flyBG.P = 9e4
                flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
                flyBG.CFrame = h.CFrame
                flyBG.Parent = h
                flyBV = Instance.new("BodyVelocity")
                flyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
                flyBV.Velocity = Vector3.zero
                flyBV.Parent = h
                flyConn = RunS.Heartbeat:Connect(function()
                    if not Cfg.fly or flyBV == nil or flyBG == nil then
                        return
                    end
                    local h2 = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                    if not h2 then
                        return
                    end
                    local cam = workspace.CurrentCamera
                    local move = Vector3.zero
                    if UIS:IsKeyDown(Enum.KeyCode.W) then
                        move += cam.CFrame.LookVector
                    end
                    if UIS:IsKeyDown(Enum.KeyCode.S) then
                        move -= cam.CFrame.LookVector
                    end
                    if UIS:IsKeyDown(Enum.KeyCode.A) then
                        move -= cam.CFrame.RightVector
                    end
                    if UIS:IsKeyDown(Enum.KeyCode.D) then
                        move += cam.CFrame.RightVector
                    end
                    if UIS:IsKeyDown(Enum.KeyCode.Space) then
                        move += Vector3.new(0, 1, 0)
                    end
                    if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
                        move -= Vector3.new(0, 1, 0)
                    end
                    if move.Magnitude > 0 then
                        move = move.Unit * Cfg.flySpeed
                    end
                    flyBV.Velocity = move
                    flyBG.CFrame = cam.CFrame
                end)
            end
        elseif not wantFly and hasFly then
            stopFly()
        end
        -- noclip manager
        if Cfg.noclip then
            if not noclipConn then
                noclipConn = RunS.Stepped:Connect(function()
                    if not Cfg.noclip then
                        return
                    end
                    local char = LP.Character
                    if char then
                        for _, p in ipairs(char:GetDescendants()) do
                            if p:IsA("BasePart") and p.CanCollide then
                                p.CanCollide = false
                            end
                        end
                    end
                end)
            end
        elseif noclipConn then
            pcall(function() noclipConn:Disconnect() end)
            noclipConn = nil
            restoreCollide()
        end
        -- speed booster (reapply tiap tick biar tahan respawn/reset server)
        if Cfg.speed then
            local char = LP.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.WalkSpeed ~= Cfg.speedVal then
                hum.WalkSpeed = Cfg.speedVal
            end
        end
    end
    stopFly()
    if noclipConn then
        pcall(function() noclipConn:Disconnect() end)
        noclipConn = nil
    end
    restoreCollide()
end)

local function fmtMoney(n)
    n = tonumber(n) or 0
    if n >= 1e9 then
        return string.format("$%.1fB", n / 1e9)
    end
    if n >= 1e6 then
        return string.format("$%.1fM", n / 1e6)
    end
    if n >= 1e3 then
        return string.format("$%.1fK", n / 1e3)
    end
    return "$" .. tostring(math.floor(n))
end

local Window = Library:CreateWindow({
    Title = "Antarctica Hub",
    Footer = "vacuum-only | RightShift = toggle UI",
    NotifySide = "Right",
    ToggleKeybind = Enum.KeyCode.RightShift,
    ShowCustomCursor = true,
})

local Toggles = Library.Toggles
local Options = Library.Options

local MainTab = Window:AddTab({ Name = "Main", Icon = "gem", Description = "Vacuum + sell", SingleColumn = true })
local ShopTab = Window:AddTab({ Name = "Shop", Icon = "shopping-cart", Description = "Auto upgrade", SingleColumn = true })
local MiscTab = Window:AddTab({ Name = "Misc", Icon = "rocket", Description = "Movement", SingleColumn = true })
local SettingsTab = Window:AddTab({ Name = "Setting", Icon = "settings", Description = "UI" })

local FarmBox = MainTab:AddGroupbox({ Side = "Left", Name = "Vacuum" })
FarmBox:AddToggle("Vacuum", { Text = "Auto vacuum (no dig)", Default = false })
FarmBox:AddToggle("Teleport", { Text = "Teleport ke freed (radius maksimal)", Default = false })
FarmBox:AddDropdown("MinRarity", { Text = "Min rarity", Values = RARITY_LIST, Default = 1 })

local SellBox = MainTab:AddGroupbox({ Side = "Left", Name = "Auto Sell" })
SellBox:AddToggle("AutoSell", { Text = "Sell", Default = false })
SellBox:AddSlider("SellPct", { Text = "Sell at", Default = 100, Min = 50, Max = 100, Rounding = 0, Suffix = "%" })
SellBox:AddButton({ Text = "Sell Now", Func = function()
    Stat.sellNow = true
end })

local MonitorBox = MainTab:AddGroupbox({ Side = "Left", Name = "Monitor Top 10" })
MonitorBox:AddDropdown("MonRarity", { Text = "Rarity", Values = RARITY_LIST, Default = 1 })
MonitorBox:AddDropdown("MonSort", { Text = "Sort by", Values = { "Value", "Luck" }, Default = 1 })
MonitorBox:AddButton({ Text = "Refresh", Func = function()
    Stat.monRefresh = true
end })
local MonSlots = {}
for i = 1, 10 do
    local idx = i
    local btn = MonitorBox:AddButton({ Text = "-", Func = function()
        local t = MonSlots[idx].target
        local h = getHRP()
        if t and t.Parent and h then
            local ok, err = pcall(function()
                tpTo(h, CFrame.new(claimPos(t) + Vector3.new(0, TUNE.tpLift, 0)))
            end)
            if ok then
                print("[hub] tp ke " .. t.Name)
            else
                notify("Monitor", "TP gagal: " .. tostring(err):sub(1, 60))
            end
        else
            notify("Monitor", "Crystal hilang.")
        end
    end })
    btn:SetVisible(false)
    MonSlots[i] = { btn = btn, target = nil }
end

local ShopBox = ShopTab:AddGroupbox({ Side = "Left", Name = "Auto Upgrade" })
ShopBox:AddToggle("UpWarmth", { Text = "Warmth", Default = false })
ShopBox:AddToggle("UpCarry", { Text = "Carry", Default = false })
ShopBox:AddSlider("Reserve", { Text = "Simpan coins", Default = 0, Min = 0, Max = 10000000, Rounding = 0 })
local UpgLabel = ShopBox:AddLabel("upgrade: -", true)

local PickBox = ShopTab:AddGroupbox({ Side = "Left", Name = "Pickaxe" })
local pickNames = {}
for i, v in ipairs(PickaxeData) do
    pickNames[i] = string.format("%d. %s (%s)", i, v.name, fmtMoney(v.price))
end
PickBox:AddDropdown("PickList", { Text = "Pickaxe", Values = pickNames, Default = 9 })
PickBox:AddButton({ Text = "Buy", Func = function()
    buyPickaxe(Cfg.pickSel, true)
end })
PickBox:AddButton({ Text = "Equip", Func = function()
    pcall(function() EquipPickaxe:FireServer(Cfg.pickSel) end)
    print("[hub] equip pickaxe " .. Cfg.pickSel)
end })

local BombBox = ShopTab:AddGroupbox({ Side = "Left", Name = "Bomb" })
local bombIds = {}
for _, v in ipairs(BombData.List) do
    table.insert(bombIds, v.id)
end
BombBox:AddDropdown("BombSel", { Text = "Bomb", Values = bombIds, Multi = true, Default = { "ClassicBomb" } })
BombBox:AddToggle("AutoBomb", { Text = "Auto buy", Default = false })
BombBox:AddButton({ Text = "Buy Now", Func = function()
    buyBombs()
end })

local MenuBox = SettingsTab:AddGroupbox({ Side = "Left", Name = "Menu" })MenuBox:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
MenuBox:AddButton({ Text = "Unload", Func = function()
    if getgenv()._ANT_HUB_UNLOAD then
        pcall(getgenv()._ANT_HUB_UNLOAD)
        getgenv()._ANT_HUB_UNLOAD = nil
    end
end })
Library.ToggleKeybind = Options.MenuKeybind

local DisplayBox = SettingsTab:AddGroupbox({ Side = "Right", Name = "Display" })
DisplayBox:AddSlider("DPI", { Text = "DPI scale", Default = 100, Min = 50, Max = 150, Rounding = 0, Suffix = "%" })

local MoveBox = MiscTab:AddGroupbox({ Side = "Left", Name = "Movement" })
MoveBox:AddToggle("Fly", { Text = "Fly (WASD + Space/Ctrl)", Default = false })
MoveBox:AddSlider("FlySpeed", { Text = "Fly speed", Default = 50, Min = 10, Max = 150, Rounding = 0 })
MoveBox:AddToggle("Noclip", { Text = "NoClip", Default = false })
MoveBox:AddToggle("Speed", { Text = "Speed booster", Default = false })
MoveBox:AddSlider("SpeedVal", { Text = "Speed", Default = 32, Min = 16, Max = 120, Rounding = 0 })

pcall(function()
    ThemeManager:SetLibrary(Library)
    ThemeManager:SetFolder("AntarcticaHub")
    ThemeManager:ApplyToTab(SettingsTab)
    SaveManager:SetLibrary(Library)
    SaveManager:SetFolder("AntarcticaHub")
    SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
    SaveManager:BuildConfigSection(SettingsTab)
    SaveManager:LoadAutoloadConfig()
end)

Toggles.Vacuum:OnChanged(function(v) Cfg.vacuum = v end)
Toggles.Teleport:OnChanged(function(v) Cfg.teleport = v end)
Toggles.AutoSell:OnChanged(function(v) Cfg.autoSell = v end)
Options.SellPct:OnChanged(function(v) Cfg.sellPct = math.clamp(math.floor(v), 50, 100) end)
Toggles.Fly:OnChanged(function(v) Cfg.fly = v end)
Toggles.UpWarmth:OnChanged(function(v) Cfg.upWarmth = v end)
Toggles.UpCarry:OnChanged(function(v) Cfg.upCarry = v end)
Toggles.AutoBomb:OnChanged(function(v) Cfg.autoBomb = v end)
Options.PickList:OnChanged(function(v)
    if type(v) == "number" then
        Cfg.pickSel = math.clamp(math.floor(v), 1, #PickaxeData)
    elseif type(v) == "string" then
        Cfg.pickSel = math.clamp(tonumber(v:match("^(%d+)")) or 9, 1, #PickaxeData)
    end
end)
Options.BombSel:OnChanged(function(v)
    local list = {}
    if type(v) == "table" then
        for k, on in pairs(v) do
            if on then
                if type(k) == "number" then
                    table.insert(list, v[k])
                else
                    table.insert(list, k)
                end
            end
        end
    elseif type(v) == "string" then
        list = { v }
    end
    Cfg.bombSel = list
end)
Options.Reserve:OnChanged(function(v) Cfg.reserve = math.floor(v) end)
Toggles.Speed:OnChanged(function(v)
    Cfg.speed = v
    if not v then
        local char = LP.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.WalkSpeed = 16
        end
    end
end)
Options.SpeedVal:OnChanged(function(v) Cfg.speedVal = math.clamp(math.floor(v), 16, 120) end)
Toggles.Noclip:OnChanged(function(v)
    Cfg.noclip = v
    if not v then
        restoreCollide()
    end
end)
Options.FlySpeed:OnChanged(function(v) Cfg.flySpeed = math.clamp(math.floor(v), 10, 150) end)
Options.DPI:OnChanged(function(v)
    pcall(function() Library:SetDPIScale(math.clamp(math.floor(v), 50, 150)) end)
end)
Options.MinRarity:OnChanged(function(v)
    if type(v) == "number" then
        Cfg.minRarity = math.clamp(math.floor(v), 1, #RARITY_LIST)
    elseif type(v) == "string" then
        Cfg.minRarity = RARITY_RANK[v] or 1
    end
end)
Options.MonRarity:OnChanged(function(v)
    if type(v) == "number" then
        Cfg.monRarity = math.clamp(math.floor(v), 1, #RARITY_LIST)
    elseif type(v) == "string" then
        Cfg.monRarity = RARITY_RANK[v] or 1
    end
end)
Options.MonSort:OnChanged(function(v)
    if type(v) == "string" then
        Cfg.monSort = v
    elseif type(v) == "number" then
        Cfg.monSort = ({ "Value", "Luck" })[math.clamp(math.floor(v), 1, 2)]
    end
end)

local function doSell()
    local h = getHRP()
    if not h then
        return
    end
    if countBag() <= 0 then
        Stat.sellNow = false
        return
    end
    Stat.selling = true
    local back = h.CFrame
    pcall(function() TeleportSell:FireServer() end)
    task.wait(TUNE.sellTpWait)
    pcall(function() RequestSell:FireServer("All") end)
    task.wait(TUNE.sellWait)
    tpTo(h, back)
    Stat.sellNow = false
    Stat.selling = false
    local c = tostring(LP.leaderstats.Coins.Value)
    print("[hub] sold, coins=" .. c)
    notify("Sold", "Coins: " .. c)
end

-- cache UpgradeState server (level + harga). koneksi ikut teardown reload.
local Upg = {}
local function hookUpgrade()
    UpgradeState.OnClientEvent:Connect(function(p)
        if type(p) == "table" then
            Upg = p
        end
    end)
end
if RL_STATE then
    RL_STATE.connect(UpgradeState.OnClientEvent, function(p)
        if type(p) == "table" then
            Upg = p
        end
    end)
else
    hookUpgrade()
end

local WARM_STEPS = { 10, 50, 100 }
local CARRY_STEPS = { 1, 5, 10 }

local function biggestStep(prices, steps, coins)
    local idx
    for i = 1, #steps do
        local price = tonumber(prices and prices[i]) or 0
        if price > 0 and coins >= price then
            idx = i
        end
    end
    return idx
end

local function doUpgrade()
    local coins = LP.leaderstats.Coins.Value
    local budget = coins - Cfg.reserve
    if budget <= 0 then
        return
    end
    -- warmth / carry: ambil step terbesar yg kebeli (max 1 aksi per 10 detik)
    for _, kind in ipairs({ "warmth", "carry" }) do
        local on = (kind == "warmth" and Cfg.upWarmth) or (kind == "carry" and Cfg.upCarry)
        if on then
            local lvl = tonumber(Upg[kind]) or 0
            local maxN = tonumber(Upg[kind == "warmth" and "maxWarmthN" or "maxCarryN"]) or 0
            if maxN <= 0 or lvl < maxN then
                local prices = Upg[kind .. "Prices"]
                local steps = kind == "warmth" and WARM_STEPS or CARRY_STEPS
                local idx = biggestStep(prices, steps, budget)
                if idx then
                    BuyUpgrade:FireServer(kind, steps[idx])
                    print("[hub] buy " .. kind .. " +" .. steps[idx])
                    return
                end
            end
        end
    end
    -- bomb pilihan: termurah dulu, verifikasi coins turun
    if Cfg.autoBomb then
        if buyBombs() then
            return
        end
    end
end

local function upgradeLabel()
    local w = Upg.warmth and ("W" .. Upg.warmth) or "W?"
    local c = Upg.carry and ("C" .. Upg.carry) or "C?"
    local eq = tonumber(LP:GetAttribute("EquippedPickaxe")) or 0
    local pn = PickaxeData[eq] and PickaxeData[eq].name or "?"
    local txt = string.format("upgrade: %s %s | %s", w, c, pn)
    pcall(function() UpgLabel:SetText(txt) end)
end

task.spawn(function()
    while alive and (RL_STATE == nil or RL_STATE.alive()) do
        local ok, err = pcall(function()
            if (Cfg.upWarmth or Cfg.upCarry or Cfg.autoBomb) and not Stat.selling then
                doUpgrade()
                upgradeLabel()
            end
        end)
        if not ok then
            warn("[hub] upgrade " .. tostring(err))
        end
        task.wait(10)
    end
end)

getgenv()._ANT_HUB_DBG = function()
    return string.format("vacuum=%s teleport=%s autoSell=%s minRar=%d monRar=%d monSort=%s",
        tostring(Cfg.vacuum), tostring(Cfg.teleport), tostring(Cfg.autoSell),
        Cfg.minRarity, Cfg.monRarity, tostring(Cfg.monSort))
end

local function refreshMonitor()
    local h = getHRP()
    local myPos = h and h.Position or Vector3.zero
    local rows = {}
    local wantRar = RARITY_LIST[Cfg.monRarity] or "Common"
    local function scan(folder)
        for _, m in ipairs(folder:GetChildren()) do
            if m:GetAttribute("Rarity") == wantRar then
                local pos = claimPos(m)
                if pos then
                    table.insert(rows, {
                        m = m,
                        d = (pos - myPos).Magnitude,
                        value = tonumber(m:GetAttribute("Value")) or 0,
                        luck = tonumber(m:GetAttribute("Luck")) or 0,
                        kg = tonumber(m:GetAttribute("Kg")) or 0,
                    })
                end
            end
        end
    end
    scan(SG)
    scan(DG)
    if Cfg.monSort == "Luck" then
        table.sort(rows, function(a, b) return a.luck > b.luck end)
    else
        table.sort(rows, function(a, b) return a.value > b.value end)
    end
    for i = 1, 10 do
        local slot = MonSlots[i]
        local r = rows[i]
        if r and r.m.Parent then
            slot.target = r.m
            local rar = r.m:GetAttribute("Rarity") or "Common"
            local badge = rar:sub(1, 1)
            local kg = r.kg >= 1000 and string.format("%.2ft", r.kg / 1000) or string.format("%.1fkg", r.kg)
            local txt = string.format('%d. <font color="%s">[%s] %s</font> %s +%s %s %.0fm', i,
                RARITY_HEX[rar] or "#FFFFFF", badge,
                r.m:GetAttribute("GemName") or r.m.Name, fmtMoney(r.value),
                string.format("%.1f%%", r.luck * 100), kg, r.d)
            pcall(function()
                slot.btn:SetText(txt)
                slot.btn:SetVisible(true)
            end)
        else
            slot.target = nil
            pcall(function() slot.btn:SetVisible(false) end)
        end
    end
end

task.spawn(function()
    while alive and (RL_STATE == nil or RL_STATE.alive()) do
        local ok, err = pcall(function()
            if Stat.monRefresh or os.clock() - (Stat.monAt or 0) > TUNE.monEveryS then
                Stat.monAt = os.clock()
                Stat.monRefresh = false
                refreshMonitor()
            end
        end)
        if not ok then
            warn("[hub] monitor " .. tostring(err))
        end
        task.wait(TUNE.monTickS)
    end
end)

task.spawn(function()
    while alive and (RL_STATE == nil or RL_STATE.alive()) do
        local ok, err = pcall(function()
            local h = getHRP()
            if not h then
                return
            end
            if Stat.sellNow or (Cfg.autoSell and not Stat.selling
                and (LP:GetAttribute("BagFull") == true or bagPct() >= Cfg.sellPct)) then
                doSell()
                return
            end
            if Stat.selling or not Cfg.vacuum then
                return
            end
            local myPos = h.Position
            local best, bestD, bestP, bestPos = nil, math.huge, nil, nil
            local function consider(m)
                if (RARITY_RANK[m:GetAttribute("Rarity")] or 1) < Cfg.minRarity then
                    return
                end
                local pr
                for _, d in ipairs(m:GetDescendants()) do
                    if d:IsA("ProximityPrompt") then
                        pr = d
                        break
                    end
                end
                if pr then
                    local pos = claimPos(m, pr)
                    if pos then
                        local d = (pos - myPos).Magnitude
                        if d < bestD then
                            best, bestD, bestP, bestPos = m, d, pr, pos
                        end
                    end
                end
            end
            -- DroppedGems dulu (free-for-all, bisa despawn), tanpa filter Owner
            for _, m in ipairs(DG:GetChildren()) do
                consider(m)
            end
            -- lalu semua Freed di SpawnedGems (tak ada pemilik = bebas ambil)
            if not best then
                for _, m in ipairs(SG:GetChildren()) do
                    if m:GetAttribute("Freed") then
                        consider(m)
                    end
                end
            end
            if not best then
                if Stat.basePos then
                    tpTo(h, Stat.basePos)
                    Stat.basePos = nil
                end
                if not Stat.swept then
                    Stat.swept = true
                    print("[hub] tak ada freed, standby")
                end
                return
            end
            Stat.swept = false
            local uid = best:GetAttribute("Uid") or best.Name
            if os.clock() - (Stat.tryAt[uid] or 0) < TUNE.retryS then
                return
            end
            if bestD > TUNE.pickupRange then
                if not Cfg.teleport then
                    return
                end
                if not Stat.basePos then
                    Stat.basePos = h.CFrame
                end
                local tp = (bestPos or best:GetPivot().Position) + Vector3.new(0, TUNE.tpLift, 0)
                tpTo(h, CFrame.new(tp))
                task.wait(TUNE.settleWait)
                if best.Parent == nil then
                    return
                end
            end
            Stat.tryAt[uid] = os.clock()
            firePrompt(bestP)
            print("[hub] pickup " .. best.Name .. " d=" .. math.floor(bestD))
        end)
        if not ok then
            warn("[hub] " .. tostring(err))
        end
        task.wait(TUNE.tickS)
    end
end)

print("[hub] loaded (vacuum-only + drop orang)")
