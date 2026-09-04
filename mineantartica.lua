-- Antarctica Hub v3 (ObsidianUltra UI): vacuum-only pickup + auto sell, TANPA dig
-- Game: Mine Antarctica | SpawnedGems Owner-lock, DroppedGems free-for-all
-- Cara kerja: DroppedGems prioritas -> own Freed, teleport max 14 stud -> fire prompt
-- UI: https://github.com/joustingmatch/ObsidianUltra (fork Obsidian, API kompatibel)

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
local LP = Players.LocalPlayer

local RequestSell = RS:WaitForChild("GemRemotes"):WaitForChild("RequestSell")
local TeleportSell = RS:WaitForChild("BackpackRemotes"):WaitForChild("TeleportSell")
local SG = workspace:WaitForChild("SpawnedGems")
local DG = workspace:WaitForChild("DroppedGems")

local RARITY_LIST = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Exotic" }
local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Exotic = 7 }
local RARITY_HEX = { Common = "#CD945C", Uncommon = "#5FDC69", Rare = "#469BFF", Epic = "#B45FFF", Legendary = "#FFAA2D", Mythic = "#FF4646", Exotic = "#FFD84A" }
local Cfg = { vacuum = false, teleport = false, autoSell = false, sellInterval = 120, minRarity = 1, monRarity = 1, monSort = "Value" }
local Stat = { lastSell = 0, selling = false, basePos = nil, tryAt = {}, lastStatus = "", swept = false }

-- helper di atas UI: callback tombol capture local ini (qentury/cake taruh helper duluan juga)
local function hrp()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local TP_STEP = 55
local function tpTo(h, cf)
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local goal = cf.Position
    local dist = (h.Position - goal).Magnitude
    if dist <= 60 then
        pcall(function()
            h.AssemblyLinearVelocity = Vector3.zero
            h.AssemblyAngularVelocity = Vector3.zero
            char:PivotTo(cf)
        end)
        return
    end
    -- stepped tanpa anchor (anchor memicu hukuman server). PivotTo + Freefall.
    local start = h.Position
    local steps = math.ceil(dist / TP_STEP)
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
        task.wait(0.05)
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
        pr.MaxActivationDistance = 1000
    end)
    local ok = pcall(fireproximityprompt, pr)
    if not ok then
        ok = pcall(function()
            pr:InputHoldBegin()
            pr:InputHoldEnd()
        end)
    end
    task.delay(0.3, function()
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
local SettingsTab = Window:AddTab({ Name = "Setting", Icon = "settings", Description = "UI" })

local FarmBox = MainTab:AddGroupbox({ Side = "Left", Name = "Vacuum" })
FarmBox:AddToggle("Vacuum", { Text = "Auto vacuum (no dig)", Default = false })
FarmBox:AddToggle("Teleport", { Text = "Teleport ke freed (radius maksimal)", Default = false })
FarmBox:AddDropdown("MinRarity", { Text = "Min rarity", Values = RARITY_LIST, Default = 1 })

local SellBox = MainTab:AddGroupbox({ Side = "Left", Name = "Auto Sell" })
SellBox:AddToggle("AutoSell", { Text = "Auto sell", Default = false })
SellBox:AddSlider("SellInterval", { Text = "Sell tiap", Default = 120, Min = 30, Max = 600, Rounding = 0, Suffix = "s" })
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
        print("[hub] klik slot " .. idx)
        local t = MonSlots[idx].target
        local h = hrp()
        print("[hub] klik target=" .. tostring(t and t.Name) .. " parent=" .. tostring(t and t.Parent ~= nil))
        if t and t.Parent and h then
            local ok, err = pcall(function()
                local mesh = t:FindFirstChild("Mesh_0", true)
                local tp = mesh and (mesh.Position + Vector3.new(0, 4, 0))
                    or (t:GetPivot().Position + Vector3.new(0, 4, 0))
                tpTo(h, CFrame.new(tp))
            end)
            print("[hub] tp " .. (ok and "ok" or ("GAGAL: " .. tostring(err))))
            if not ok then
                notify("Monitor", "TP gagal: " .. tostring(err):sub(1, 60))
            end
        else
            notify("Monitor", "Crystal hilang.")
        end
    end })
    btn:SetVisible(false)
    MonSlots[i] = { btn = btn, target = nil }
end

local MenuBox = SettingsTab:AddGroupbox({ Side = "Left", Name = "Menu" })
MenuBox:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
MenuBox:AddButton({ Text = "Unload", Func = function()
    if getgenv()._ANT_HUB_UNLOAD then
        pcall(getgenv()._ANT_HUB_UNLOAD)
        getgenv()._ANT_HUB_UNLOAD = nil
    end
end })
Library.ToggleKeybind = Options.MenuKeybind

local DisplayBox = SettingsTab:AddGroupbox({ Side = "Right", Name = "Display" })
DisplayBox:AddSlider("DPI", { Text = "DPI scale", Default = 100, Min = 50, Max = 150, Rounding = 0, Suffix = "%" })

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
Options.SellInterval:OnChanged(function(v) Cfg.sellInterval = v end)
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

local RL_STATE = rawget(getgenv(), "STATE")
if typeof(RL_STATE) ~= "table" then
    RL_STATE = nil
end

local function doSell()
    local h = hrp()
    if not h then
        return
    end
    if countBag() <= 0 then
        Stat.lastSell = os.clock()
        Stat.sellNow = false
        return
    end
    Stat.selling = true
    local back = h.CFrame
    pcall(function() TeleportSell:FireServer() end)
    task.wait(1.5)
    pcall(function() RequestSell:FireServer("All") end)
    task.wait(1)
    tpTo(h, back)
    Stat.lastSell = os.clock()
    Stat.sellNow = false
    Stat.selling = false
    local c = tostring(LP.leaderstats.Coins.Value)
    print("[hub] sold, coins=" .. c)
    notify("Sold", "Coins: " .. c)
end

local alive = true
getgenv()._ANT_HUB_UNLOAD = function()
    alive = false
    pcall(function() Library:Unload() end)
    print("[hub] unloaded")
end
if RL_STATE then
    RL_STATE.onCleanup(function()
        alive = false
        pcall(function() Library:Unload() end)
    end)
end

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

getgenv()._ANT_HUB_DBG = function()
    return string.format("vacuum=%s teleport=%s autoSell=%s minRar=%d monRar=%d monSort=%s",
        tostring(Cfg.vacuum), tostring(Cfg.teleport), tostring(Cfg.autoSell),
        Cfg.minRarity, Cfg.monRarity, tostring(Cfg.monSort))
end

local function refreshMonitor()
    local h = hrp()
    local myPos = h and h.Position or Vector3.zero
    local rows = {}
    local wantRar = RARITY_LIST[Cfg.monRarity] or "Common"
    local function scan(folder)
        for _, m in ipairs(folder:GetChildren()) do
            if m:GetAttribute("Rarity") == wantRar then
                local okP, piv = pcall(function() return m:GetPivot().Position end)
                if okP then
                    table.insert(rows, {
                        m = m,
                        d = (piv - myPos).Magnitude,
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
            if Stat.monRefresh or os.clock() - (Stat.monAt or 0) > 5 then
                Stat.monAt = os.clock()
                Stat.monRefresh = false
                refreshMonitor()
            end
        end)
        if not ok then
            warn("[hub] monitor " .. tostring(err))
        end
        task.wait(1)
    end
end)

task.spawn(function()
    local tick = 0
    while alive and (RL_STATE == nil or RL_STATE.alive()) do
        local ok, err = pcall(function()
            tick += 1
            local h = hrp()
            if not h then
                return
            end
            if Stat.sellNow or (Cfg.autoSell and not Stat.selling
                and (LP:GetAttribute("BagFull") == true or os.clock() - Stat.lastSell > Cfg.sellInterval)) then
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
                    -- ukur dari part prompt (server cek jarak ke situ, bukan pivot model)
                    local pp = pr.Parent
                    local pos = (pp and pp:IsA("BasePart") and pp.Position)
                        or (function()
                            local mesh = m:FindFirstChild("Mesh_0", true)
                            return mesh and mesh.Position
                        end)()
                    if not pos then
                        local okP, piv = pcall(function() return m:GetPivot().Position end)
                        if okP then
                            pos = piv
                        end
                    end
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
            if os.clock() - (Stat.tryAt[uid] or 0) < 3 then
                return
            end
            if bestD > 14 then
                if not Cfg.teleport then
                    return
                end
                if not Stat.basePos then
                    Stat.basePos = h.CFrame
                end
                local tp = (bestPos or best:GetPivot().Position) + Vector3.new(0, 4, 0)
                tpTo(h, CFrame.new(tp))
                task.wait(0.7)
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
        task.wait(0.4)
    end
end)

print("[hub] v3 loaded (vacuum-only + drop orang)")
