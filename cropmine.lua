-- Auto Pickup v1 (Crop Mine / Ugc garden) — Robly Airflow UI
-- Pool: workspace.DropItems (model crop jatuh, prompt "Pickup" Hold 2, range ~9-10)
-- Pola vacuum dari antarctica-hub: Hold=0 + no LoS + fireproximityprompt + restore

if _G._cropPickStop then _G._cropPickStop() end
if _G._cropSwingStop then _G._cropSwingStop() end
if _G._cropMiscStop then _G._cropMiscStop() end
if _G._cropBuyStop then _G._cropBuyStop() end
if _G._cropPickWindow then
    pcall(function() _G._cropPickWindow:Destroy() end)
    _G._cropPickWindow = nil
end
do
    local names = { ["Crop Pickup"] = true }
    local roots = { game:GetService("CoreGui") }
    local okH, hui = pcall(gethui)
    if okH and hui then table.insert(roots, hui) end
    for _, root in ipairs(roots) do
        for _, g in ipairs(root:GetChildren()) do
            if names[g.Name] then pcall(function() g:Destroy() end) end
        end
    end
end

local Airflow = nil
do
    local urls = {
        "https://raw.githubusercontent.com/bobloscript/Robly_Airflow/main/Source.luau",
        "https://raw.githubusercontent.com/bobloscript/Robly_Airflow/5a90ba011e33a808c5adbd81befabc01348bdc86/Source.luau",
        "https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/refs/heads/main/Source.luau",
    }
    for _, u in ipairs(urls) do
        local ok, lib = pcall(function() return loadstring(game:HttpGet(u))() end)
        if ok and lib then Airflow = lib break end
    end
end
assert(Airflow, "CropPickup: gagal load Robly Airflow")

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RSvc = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer

local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Mortal = 7 }
local RARITY_NAMES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Mortal" }
local RARITY_HEX = { Common = "#BDBDBD", Uncommon = "#7ED67E", Rare = "#6EA8FE", Epic = "#C58AF9", Legendary = "#FFB35C", Mythic = "#FF6B6B", Mortal = "#FFE066" }

local State = {
    AutoPick = false, Teleport = false, AutoSell = false,
    Rarities = {}, MinValue = 0, MaxDist = 400,
    ScanDelay = 0.4, MultiPop = 3, SellPct = 90,
    Running = false, StatusText = "Idle", Picked = 0, Sold = 0,
    AutoSwing = false, SwingDist = 25, Swung = 0, SwingRunning = false,
    SwingTP = true, swingTpAt = 0,
    MonRar = {}, MonSort = "Value", monRefresh = false, monAt = 0,
    SpeedHack = false, SpeedVal = 22, origWS = 0,
    NoClip = false, Fly = false, FlySpeed = 60,
    InfJump = false,
    AntiAFK = true,
    sellPos = Vector3.new(98, 39, 27), -- posisi NPC Sell (ditemukan via scan)
    AutoBuy = false, BuyRunning = false, BuySel = {}, BuyInfo = "-",
}
local BOMB_PRICE = { ClassicBomb = 33000, WindBomb = 65000, IceBomb = 105000, FireBomb = 145000,
    ThunderBomb = 225000, PoisonBomb = 325000, TimeBomb = 640000, AgonyBomb = 1300000 }
local BOMB_NAMES = { "ClassicBomb", "WindBomb", "IceBomb", "FireBomb", "ThunderBomb", "PoisonBomb", "TimeBomb", "AgonyBomb" }
for _, n in ipairs(BOMB_NAMES) do State.BuySel[n] = true end
for _, n in ipairs(RARITY_NAMES) do State.Rarities[n] = true State.MonRar[n] = true end
local tryAt = {}

local function getHRP()
    local ch = LP.Character
    return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function promptOf(m)
    local ok, pr = pcall(function() return m:FindFirstChildWhichIsA("ProximityPrompt", true) end)
    return ok and pr or nil
end

-- firePrompt ala antarctica-hub: Hold=0 + no LoS + boost range, restore setelahnya
local function firePrompt(pr, boost)
    if not pr or not pr.Parent then return false end
    local saved = { hold = pr.HoldDuration, sight = pr.RequiresLineOfSight, range = pr.MaxActivationDistance }
    pcall(function()
        pr.HoldDuration = 0
        pr.RequiresLineOfSight = false
        pr.MaxActivationDistance = math.max(pr.MaxActivationDistance, boost or 12)
    end)
    local ok = pcall(fireproximityprompt, pr)
    if not ok then
        ok = pcall(function() pr:InputHoldBegin() pr:InputHoldEnd() end)
    end
    task.delay(1, function()
        if pr.Parent then
            pcall(function()
                pr.HoldDuration = saved.hold
                pr.RequiresLineOfSight = saved.sight
                pr.MaxActivationDistance = saved.range
            end)
        end
    end)
    return ok
end

local function bagFull()
    local cap, kg = 25, 0
    pcall(function()
        cap = tonumber(LP:GetAttribute("BagCap")) or 25
        kg = tonumber(LP:GetAttribute("BagKg")) or 0
        if LP:GetAttribute("BagFull") == true then return true end
    end)
    return kg >= cap * (State.SellPct / 100), kg, cap
end

local function findPromptByAction(action, maxDist)
    local h = getHRP()
    if not h then return nil end
    local myPos = h.Position
    local best, bd = nil, maxDist or math.huge
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Enabled and d.ActionText == action then
            local par = d.Parent
            local okP, pp = pcall(function()
                if par:IsA("BasePart") then return par.Position end
                if par:IsA("Model") then return par:GetPivot().Position end
                return nil
            end)
            if okP and pp then
                local dist = (pp - myPos).Magnitude
                if dist < bd then best, bd = d, dist end
            end
        end
    end
    return best
end

local function closeSellDialog()
    local dlg = LP.PlayerGui:FindFirstChild("SellConfirmGui")
    local no = dlg and dlg:FindFirstChild("No", true)
    if dlg and no then
        pcall(function() firesignal(no.Activated) end)
        task.wait(0.5)
    end
end

local function goSell()
    local h = getHRP()
    if not h then return false, "no-char" end
    local backTo = h.CFrame -- jaga-jaga: balik ke posisi semula
    -- jual langsung via remote, tanpa prompt/dialog/teleport
    local bagKg = tonumber(LP:GetAttribute("BagKg")) or 0
    if bagKg <= 0 then return false, "tas-kosong" end
    local remotes = RS:FindFirstChild("Remotes")
    local rem = remotes and remotes:FindFirstChild("ShopSellConfirm")
    if not rem then return false, "no-remote" end
    -- server kemungkinan validasi jarak: merapat ke NPC "Sell crops" dulu
    local pr = findPromptByAction("Sell crops")
    if not pr and State.sellPos then
        -- area sell belum ke-stream: teleport ke posisi terakhir, tunggu stream, scan ulang
        h.CFrame = CFrame.new(State.sellPos + Vector3.new(0, 6, 0))
        task.wait(2.5)
        pr = findPromptByAction("Sell crops")
    end
    if pr then
        local par = pr.Parent
        local okP, pp = pcall(function()
            if par:IsA("BasePart") then return par.Position end
            return par:GetPivot().Position
        end)
        if okP and pp then
            State.sellPos = pp -- ingat posisi NPC buat berikutnya
            if (pp - h.Position).Magnitude > 12 then
                h.CFrame = CFrame.new(pp + Vector3.new(0, 6, 0))
                task.wait(0.6)
            end
        end
    end
    local function monedas()
        local ls = LP:FindFirstChild("leaderstats")
        local m = ls and ls:FindFirstChild("Monedas")
        return m and m.Value or 0
    end
    local before = monedas()
    local ok = pcall(function() rem:FireServer("all") end)
    if not ok then
        pcall(function() h.CFrame = backTo end)
        return false, "fire-gagal"
    end
    task.wait(2)
    local gained = monedas() - before
    closeSellDialog() -- buang dialog basi kalau ada
    pcall(function() h.CFrame = backTo end)
    if gained > 0 then
        State.Sold += 1
        return true, ("sold +%d"):format(gained)
    end
    return false, "no-change"
end

-- batas kebun sendiri dari posisi PlacedCrops + margin (drop plot tak bisa diambil)
local function plotBounds()
    local parcels = workspace:FindFirstChild("Parcelas")
    if not parcels then return nil end
    local mine = nil
    for _, p in ipairs(parcels:GetChildren()) do
        local ok, uid = pcall(function() return p:GetAttribute("OwnerUserId") end)
        if ok and tonumber(uid) == LP.UserId then mine = p break end
    end
    if not mine then return nil end
    local pc = mine:FindFirstChild("PlacedCrops")
    if not pc then return nil end
    local minX, maxX, minZ, maxZ
    for _, m in ipairs(pc:GetChildren()) do
        local ok, pos = pcall(function() return m:GetPivot().Position end)
        if ok then
            minX = math.min(minX or pos.X, pos.X)
            maxX = math.max(maxX or pos.X, pos.X)
            minZ = math.min(minZ or pos.Z, pos.Z)
            maxZ = math.max(maxZ or pos.Z, pos.Z)
        end
    end
    if not minX then return nil end
    local mg = 50
    return { x1 = minX - mg, x2 = maxX + mg, z1 = minZ - mg, z2 = maxZ + mg }
end

local function inOwnPlot(pos, pb)
    return pb and pos.X >= pb.x1 and pos.X <= pb.x2 and pos.Z >= pb.z1 and pos.Z <= pb.z2
end

local function pickOnce()
    local h = getHRP()
    if not h then return false, "no-char" end
    local di = workspace:FindFirstChild("DropItems")
    if not di then return false, "no-dropitems" end
    local myPos = h.Position
    local pb = plotBounds()
    local cand = {}
    for _, m in ipairs(di:GetChildren()) do
        if m:IsA("Model") then
            local okA, rar, val, fav = pcall(function()
                return m:GetAttribute("Rarity"), tonumber(m:GetAttribute("Value")) or 0,
                    m:GetAttribute("Favorited")
            end)
            if okA and fav ~= true and State.Rarities[rar]
                and (RARITY_RANK[rar] or 1) >= 1 and val >= State.MinValue then
                local okP, piv = pcall(function() return m:GetPivot().Position end)
                if okP and piv.Magnitude > 1 and not inOwnPlot(piv, pb) then
                    local pr = promptOf(m)
                    if pr and pr.Enabled then
                        local d = (piv - myPos).Magnitude
                        if d <= State.MaxDist then
                            local r = tonumber(pr.MaxActivationDistance) or 10
                            table.insert(cand, { m = m, d = d, pr = pr, range = r })
                        end
                    end
                end
            end
        end
    end
    if #cand == 0 then return false, "no-target" end
    table.sort(cand, function(a, b) return a.d < b.d end)
    local now = os.clock()
    local fired = 0
    for _, c in ipairs(cand) do
        if fired >= State.MultiPop then break end
        local uid = c.m:GetDebugId()
        if now - (tryAt[uid] or 0) >= 1.0 and c.d <= c.range + 2 then
            tryAt[uid] = now
            if firePrompt(c.pr, 12) then fired += 1 end
        end
    end
    if fired > 0 then
        State.Picked += fired
        return true, "x" .. fired
    end
    -- tak ada yg in-range: teleport ke terdekat
    local best = cand[1]
    if not State.Teleport then return false, "far-" .. math.floor(best.d) end
    local uid = best.m:GetDebugId()
    if now - (tryAt[uid] or 0) < 1.0 then return false, "retry" end
    tryAt[uid] = now
    local okP, pos = pcall(function() return best.m:GetPivot().Position end)
    if not okP then return false, "no-pivot" end
    h.CFrame = CFrame.new(pos + Vector3.new(0, 6, 0))
    task.wait(0.5)
    if best.m.Parent == nil then return false, "target-gone" end
    firePrompt(best.pr, 12)
    State.Picked += 1
    return true, best.m.Name
end

local LogPara, logLines = nil, {}
local function uiLog(msg)
    table.insert(logLines, 1, msg)
    if #logLines > 8 then table.remove(logLines) end
    if LogPara then pcall(function() LogPara:Set(table.concat(logLines, "\n")) end) end
end
local function log(msg) uiLog(msg) print("[CropPickup] " .. msg) end

local function mainLoop()
    if State.Running then return end
    State.Running = true
    task.spawn(function()
        log("Loop mulai (DropItems)")
        while State.AutoPick do
            if State.AutoSell then
                local full = bagFull()
                if full then
                    State.StatusText = "Selling..."
                    local ok, info = goSell()
                    log(ok and "Sell OK" or ("Sell gagal: " .. tostring(info)))
                    task.wait(1)
                    continue
                end
            end
            State.StatusText = "Picking..."
            local ok, info = pickOnce()
            State.StatusText = ok and ("Picked " .. tostring(info)) or ("Retry (" .. tostring(info) .. ")")
            if not ok and (info == "no-target" or info == "no-dropitems") then
                task.wait(1.5)
            else
                task.wait(State.ScanDelay)
            end
        end
        State.Running = false State.StatusText = "Idle"
        log("Loop berhenti")
    end)
end

_G._cropPickStop = function() State.AutoPick = false end
_G._cropSwingStop = function() State.AutoSwing = false end
_G._cropBuyStop = function() State.AutoBuy = false end
_G._cropMiscStop = function()
    State.SpeedHack = false
    State.NoClip = false
    State.Fly = false
    State.InfJump = false
end

local VU = game:GetService("VirtualUser")
LP.Idled:Connect(function()
    if not State.AntiAFK then return end
    pcall(function()
        VU:CaptureController()
        VU:ClickButton2(Vector2.new())
    end)
end)

local function getHoe()
    local lp = LP
    local ch = lp.Character
    if ch then
        for _, t in ipairs(ch:GetChildren()) do
            if t:IsA("Tool") and t:FindFirstChild("AzadaServer") then return t end
        end
    end
    for _, t in ipairs(lp.Backpack:GetChildren()) do
        if t:IsA("Tool") and t:FindFirstChild("AzadaServer") then return t end
    end
    return nil
end

local function getOwnPlot()
    local parcels = workspace:FindFirstChild("Parcelas")
    if not parcels then return nil end
    for _, p in ipairs(parcels:GetChildren()) do
        local ok, uid = pcall(function() return p:GetAttribute("OwnerUserId") end)
        if ok and tonumber(uid) == LP.UserId then return p end
    end
    return nil
end

local function swingOnce()
    local h = getHRP()
    if not h then return false, "no-char" end
    local hoe = getHoe()
    if not hoe then return false, "no-hoe" end
    local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if hum and hoe.Parent ~= LP.Character then
        pcall(function() hum:EquipTool(hoe) end)
        task.wait(0.4)
    end
    local best, bd = nil, State.SwingDist
    local far, fd = nil, math.huge
    local function consider(m)
        local okP, pos = pcall(function()
            if m:IsA("Model") then return m:GetPivot().Position end
            return m.Position
        end)
        if okP then
            local d = (pos - h.Position).Magnitude
            if d < bd then best, bd = m, d end
            if d < fd then far, fd = m, d end
        end
    end
    -- gandum liar di WheatFieldClient
    local wf = workspace:FindFirstChild("WheatFieldClient")
    if wf then
        for _, m in ipairs(wf:GetChildren()) do
            if m:IsA("BasePart") then consider(m) end
        end
    end
    -- crop di semua plot
    local parcels = workspace:FindFirstChild("Parcelas")
    if not parcels and not wf then return false, "no-parcelas" end
    if parcels then
        for _, plot in ipairs(parcels:GetChildren()) do
            local pc = plot:FindFirstChild("PlacedCrops")
            if pc then
                for _, m in ipairs(pc:GetChildren()) do consider(m) end
            end
        end
    end
    if not best then
        -- tidak ada yg in-range: ikut teleport ke crop terdekat bila diizinkan
        if State.SwingTP and far and os.clock() - State.swingTpAt > 5 then
            State.swingTpAt = os.clock()
            local okP, pos = pcall(function() return far:GetPivot().Position end)
            if okP then
                h.CFrame = CFrame.new(pos + Vector3.new(0, 6, 4))
                return false, ("tp-plot %dst"):format(fd)
            end
        end
        return false, ("no-target %dst"):format(fd ~= math.huge and math.floor(fd) or -1)
    end
    local okP, pos = pcall(function() return best:GetPivot().Position end)
    if not okP then return false, "no-pivot" end
    pcall(function()
        h.CFrame = CFrame.new(h.Position, Vector3.new(pos.X, h.Position.Y, pos.Z))
    end)
    pcall(function() hoe:Activate() end)
    State.Swung += 1
    return true, best.Name .. " " .. math.floor(bd) .. "st"
end

local function swingLoop()
    if State.SwingRunning then return end
    State.SwingRunning = true
    task.spawn(function()
        log("Swing loop mulai")
        while State.AutoSwing do
            local ok, info = swingOnce()
            State.StatusText = ok and ("Swing " .. tostring(info)) or ("Swing (" .. tostring(info) .. ")")
            task.wait(ok and 0.6 or 1.5)
        end
        State.SwingRunning = false
        log("Swing loop berhenti")
    end)
end

local Window = Airflow:CreateWindow({
    Name = "Crop Pickup",
    LoadingSubtitle = "DropItems vacuum",
    ToggleUIKeybind = "RightControl",
    ConfigurationSaving = { Enabled = true, FolderName = "CropPickup" },
})
_G._cropPickWindow = Window

local Main = Window:CreateTab({ Name = "Main", Icon = "sprout" })

local MonFilterBox = Main:CreateGroupbox({ Name = "Monitor Filter", Side = "Right" })
MonFilterBox:CreateDropdown({
    Name = "Rarity", Options = RARITY_NAMES, CurrentOption = RARITY_NAMES,
    MultipleOptions = true, Flag = "MonRarity",
    Callback = function(List)
        local set = {}
        if type(List) == "table" then
            for _, v in ipairs(List) do set[v] = true end
        elseif type(List) == "string" then set[List] = true end
        State.MonRar = set State.monRefresh = true
    end,
})
MonFilterBox:CreateDropdown({
    Name = "Sort by", Options = { "Value", "Kg", "Jarak" }, CurrentOption = { "Value" },
    Flag = "MonSort",
    Callback = function(v) State.MonSort = type(v) == "table" and v[1] or v end,
})
MonFilterBox:CreateButton({ Name = "Refresh", Callback = function() State.monRefresh = true end })

local MonRowsWorld = {}
local function monTp(i, rows)
    local s = rows[i]
    local h = getHRP()
    if s and s.m.Parent and s.pos and h then
        pcall(function() h.CFrame = CFrame.new(s.pos + Vector3.new(0, 6, 0)) end)
        log("TP ke " .. s.name)
    else
        log("Drop sudah hilang.")
    end
end
local MonTblWorld = Main:CreateTable({
    Name = "Top 10 World",
    MaxRows = 10,
    Search = false,
    Columns = {
        { Name = "#", Width = 0.08 },
        { Name = "Crop", Width = 0.4 },
        { Name = "Value", Width = 0.2 },
        { Name = "Kg", Width = 0.16 },
        { Name = "Jarak", Width = 0.16 },
    },
    Rows = {},
    Callback = function(_, i) monTp(i, MonRowsWorld) end,
})

local function monTrows(rows, store)
    for i = 1, #store do store[i] = nil end
    local trows = {}
    for i = 1, math.min(#rows, 10) do
        local r = rows[i]
        store[i] = r
        trows[i] = {
            ["#"] = i,
            Crop = string.format("[%s] %s", (r.rar or "?"):sub(1, 1), r.name),
            Value = tostring(math.floor(r.value)),
            Kg = string.format("%.1f", r.kg),
            Jarak = string.format("%.0fm", r.d),
            Colors = { Crop = RARITY_HEX[r.rar] or "#FFFFFF" },
        }
    end
    return trows
end

local function refreshMonitor()
    local h = getHRP()
    local myPos = h and h.Position or Vector3.zero
    local di = workspace:FindFirstChild("DropItems")
    local pb = plotBounds()
    local inWorld = {}
    if di then
        for _, m in ipairs(di:GetChildren()) do
            if m:IsA("Model") then
                local okA, rar, val, kg, gem, fav = pcall(function()
                    return m:GetAttribute("Rarity"), tonumber(m:GetAttribute("Value")) or 0,
                        tonumber(m:GetAttribute("Kg")) or 0, m:GetAttribute("GemName"),
                        m:GetAttribute("Favorited")
                end)
                if okA and fav ~= true and State.MonRar[rar] then
                    local okP, pos = pcall(function() return m:GetPivot().Position end)
                    if okP and pos.Magnitude > 1 then
                        local e = { m = m, name = gem or m.Name, rar = rar,
                            d = (pos - myPos).Magnitude, pos = pos, value = val, kg = kg }
                        if inOwnPlot(pos, pb) then
                            -- di plot sendiri: tidak bisa diambil, skip
                        else
                            table.insert(inWorld, e)
                        end
                    end
                end
            end
        end
    end
    local function sortRows(t)
        if State.MonSort == "Kg" then
            table.sort(t, function(a, b) return a.kg > b.kg end)
        elseif State.MonSort == "Jarak" then
            table.sort(t, function(a, b) return a.d < b.d end)
        else
            table.sort(t, function(a, b) return a.value > b.value end)
        end
    end
    sortRows(inWorld)
    pcall(function() MonTblWorld:SetRows(monTrows(inWorld, MonRowsWorld)) end)
end

task.spawn(function()
    while true do
        pcall(function()
            if State.monRefresh or os.clock() - State.monAt > 2 then
                State.monAt = os.clock()
                State.monRefresh = false
                refreshMonitor()
            end
        end)
        task.wait(0.5)
    end
end)
local Vac = Main:CreateGroupbox({ Name = "Vacuum", Side = "Left" })
Vac:CreateToggle({
    Name = "Auto Pickup", Flag = "AutoPick", CurrentValue = false,
    Callback = function(On)
        State.AutoPick = On
        if On then mainLoop() else _G._cropPickStop() end
    end,
})
Vac:CreateToggle({
    Name = "Teleport ke drop", Desc = "Mati = hanya fire yg dalam jangkauan",
    Flag = "Teleport", CurrentValue = false,
    Callback = function(V) State.Teleport = V end,
})
Vac:CreateDropdown({
    Name = "Rarity Filter", Options = RARITY_NAMES, CurrentOption = RARITY_NAMES,
    MultipleOptions = true, Flag = "RarityFilter",
    Callback = function(List)
        local set = {}
        if type(List) == "table" then
            for _, v in ipairs(List) do set[v] = true end
        elseif type(List) == "string" then set[List] = true end
        State.Rarities = set
    end,
})
Vac:CreateSlider({
    Name = "Min Value", Range = { 0, 2000 }, Increment = 50, Suffix = " coins",
    CurrentValue = 0, Flag = "MinValue",
    Callback = function(V) State.MinValue = V end,
})
Vac:CreateSlider({
    Name = "Jarak Scan", Desc = "Radius DropItems dari karakter",
    Range = { 50, 500 }, Increment = 10, Suffix = " studs",
    CurrentValue = 400, Flag = "MaxDist",
    Callback = function(V) State.MaxDist = V end,
})
Vac:CreateSlider({
    Name = "Multi Pop", Desc = "Maks fire per tick",
    Range = { 1, 6 }, Increment = 1,
    CurrentValue = 3, Flag = "MultiPop",
    Callback = function(V) State.MultiPop = math.floor(V) end,
})
Vac:CreateSlider({
    Name = "Jeda Scan", Range = { 0.2, 2 }, Increment = 0.1, Suffix = "s",
    CurrentValue = 0.4, Flag = "ScanDelay",
    Callback = function(V) State.ScanDelay = V end,
})

local Swing = Main:CreateGroupbox({ Name = "Auto Swing", Side = "Left" })
Swing:CreateToggle({
    Name = "Auto Swing Sabit", Flag = "AutoSwing", CurrentValue = false,
    Callback = function(On)
        State.AutoSwing = On
        if On then swingLoop() else _G._cropSwingStop() end
    end,
})
Swing:CreateSlider({
    Name = "Jarak Swing", Desc = "Hanya crop plot sendiri dalam radius ini",
    Range = { 10, 60 }, Increment = 5, Suffix = " studs",
    CurrentValue = 25, Flag = "SwingDist",
    Callback = function(V) State.SwingDist = V end,
})
Swing:CreateToggle({
    Name = "TP ke Plot", Desc = "Teleport ke crop bila tidak ada yg dekat",
    Flag = "SwingTP", CurrentValue = true,
    Callback = function(V) State.SwingTP = V end,
})
Swing:CreateButton({
    Name = "Go Plot", Callback = function()
        local h = getHRP()
        local plot = getOwnPlot()
        local pc = plot and plot:FindFirstChild("PlacedCrops")
        local kids = pc and pc:GetChildren() or {}
        local first = kids[1]
        if h and first then
            local okP, pos = pcall(function() return first:GetPivot().Position end)
            if okP then
                h.CFrame = CFrame.new(pos + Vector3.new(0, 6, 4))
                log("TP ke plot")
            end
        else
            log("Plot tidak ketemu.")
        end
    end,
})

local Sell = Main:CreateGroupbox({ Name = "Sell", Side = "Right" })
Sell:CreateToggle({
    Name = "Auto Sell", Flag = "AutoSell", CurrentValue = false,
    Callback = function(V) State.AutoSell = V end,
})
Sell:CreateSlider({
    Name = "Jual saat", Desc = "% kapasitas tas",
    Range = { 50, 100 }, Increment = 5, Suffix = "%",
    CurrentValue = 90, Flag = "SellPct",
    Callback = function(V) State.SellPct = V end,
})
Sell:CreateButton({
    Name = "Sell Sekarang", Callback = function()
        local ok, info = goSell()
        log(ok and "Sell OK" or ("Sell gagal: " .. tostring(info)))
    end,
})
Sell:CreateStatus({
    Name = "Tas", Style = "Row", Pin = true,
    Update = function()
        local full, kg, cap = bagFull()
        return (full and "<Warning>PENUH</Warning> " or "") .. string.format("%.1f/%.0f kg", kg, cap)
    end,
})

Main:CreateGroupbox({ Name = "Info", Side = "Right" }):CreateLabel({
    Text = "Target: -",
    Update = function()
        local n = 0
        local di = workspace:FindFirstChild("DropItems")
        if di then
            for _, m in ipairs(di:GetChildren()) do
                if m:IsA("Model") then
                    local okA, rar, val, fav = pcall(function()
                        return m:GetAttribute("Rarity"), tonumber(m:GetAttribute("Value")) or 0,
                            m:GetAttribute("Favorited")
                    end)
                    if okA and fav ~= true and State.Rarities[rar] and val >= State.MinValue then
                        n += 1
                    end
                end
            end
        end
        return ("Target: %d drop | picked %d | swung %d | sold %d | %s"):format(n, State.Picked, State.Swung, State.Sold, State.StatusText)
    end,
    UpdateRate = 0.5,
})

local Misc = Window:CreateTab({ Name = "Misc", Icon = "ghost" })
local Move = Misc:CreateGroupbox({ Name = "Movement", Side = "Left" })
Move:CreateToggle({
    Name = "Speed Hack", Flag = "SpeedHack", CurrentValue = false,
    Desc = "Kunci WalkSpeed (game suka reset sendiri)",
    Callback = function(On)
        State.SpeedHack = On
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if On then
            if hum then
                if State.origWS == 0 then State.origWS = hum.WalkSpeed end
                hum.WalkSpeed = State.SpeedVal
            end
        elseif hum and State.origWS > 0 then
            hum.WalkSpeed = State.origWS
        end
    end,
})
Move:CreateSlider({
    Name = "WalkSpeed", Range = { 16, 200 }, Increment = 2, Suffix = " st/s",
    CurrentValue = 22, Flag = "SpeedVal",
    Callback = function(V) State.SpeedVal = math.floor(V) end,
})
Move:CreateToggle({
    Name = "NoClip", Flag = "NoClip", CurrentValue = false,
    Desc = "Tembus tembok (jalan santai)",
    Callback = function(On) State.NoClip = On end,
})
Move:CreateToggle({
    Name = "Fly", Flag = "Fly", CurrentValue = false,
    Desc = "WASD gerak, Space/E naik, Ctrl/Q turun",
    Callback = function(On) State.Fly = On end,
})
Move:CreateToggle({
    Name = "Inf Jump", Flag = "InfJump", CurrentValue = false,
    Desc = "Lompat berkali-kali di udara (Space)",
    Callback = function(On) State.InfJump = On end,
})

UIS.JumpRequest:Connect(function()
    if not State.InfJump then return end
    pcall(function()
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end)
end)
Move:CreateSlider({
    Name = "Fly Speed", Range = { 10, 200 }, Increment = 5, Suffix = " st/s",
    CurrentValue = 60, Flag = "FlySpeed",
    Callback = function(V) State.FlySpeed = V end,
})

local Util = Misc:CreateGroupbox({ Name = "Utility", Side = "Right" })
Util:CreateToggle({
    Name = "Anti AFK", Flag = "AntiAFK", CurrentValue = true,
    Desc = "Klik virtual tiap game deteksi idle",
    Callback = function(On) State.AntiAFK = On end,
})

task.spawn(function()
    while true do
        pcall(function()
            local ch = LP.Character
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")
            if hum and State.SpeedHack then
                if hum.WalkSpeed ~= State.SpeedVal then hum.WalkSpeed = State.SpeedVal end
            end
            if ch and (State.NoClip or State.Fly) then
                for _, p in ipairs(ch:GetDescendants()) do
                    if p:IsA("BasePart") then p.CanCollide = false end
                end
            end
        end)
        task.wait(0.3)
    end
end)

RSvc.Heartbeat:Connect(function(dt)
    if not State.Fly then return end
    pcall(function()
        local h = getHRP()
        if not h then return end
        local cam = workspace.CurrentCamera
        if not cam then return end
        h.Velocity = Vector3.zero
        h.RotVelocity = Vector3.zero
        local dir = Vector3.zero
        local cf = cam.CFrame
        if UIS:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.Space) or UIS:IsKeyDown(Enum.KeyCode.E) then dir += Vector3.new(0, 1, 0) end
        if UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.Q) then dir -= Vector3.new(0, 1, 0) end
        if dir.Magnitude > 0 then
            h.CFrame = h.CFrame + (dir.Unit * State.FlySpeed * math.min(dt, 0.1))
        end
    end)
end)

local function buyMonedas()
    local ls = LP:FindFirstChild("leaderstats")
    local m = ls and ls:FindFirstChild("Monedas")
    return m and m.Value or 0
end

local function buyLoop()
    if State.BuyRunning then return end
    State.BuyRunning = true
    task.spawn(function()
        log("Buy loop mulai")
        while State.AutoBuy do
            local remotes = RS:FindFirstChild("Remotes")
            local q = remotes and remotes:FindFirstChild("BombShopQuery")
            local buy = remotes and remotes:FindFirstChild("BombBuyRequest")
            if not (q and buy) then
                State.BuyInfo = "no-remote"
                task.wait(3)
            else
                local okQ, res = pcall(function() return q:InvokeServer() end)
                if not (okQ and type(res) == "table") then
                    State.BuyInfo = "query-gagal"
                    task.wait(3)
                else
                    local stock = res.stock or {}
                    local bought, spent = 0, 0
                    local cheapest = math.huge
                    for _, name in ipairs(BOMB_NAMES) do
                        local price = BOMB_PRICE[name] or math.huge
                        if State.BuySel[name] and price < cheapest then cheapest = price end
                    end
                    if buyMonedas() < cheapest then
                        State.BuyInfo = "duit habis"
                        State.AutoBuy = false
                        local el = Airflow.Flags.AutoBuy
                        if el then el:Set(false, true) end
                    else
                        for _, name in ipairs(BOMB_NAMES) do
                            if not State.AutoBuy then break end
                            local price = BOMB_PRICE[name] or 0
                            local s = tonumber(stock[name]) or 0
                            while State.BuySel[name] and s > 0 and buyMonedas() >= price do
                                local okB = pcall(function() buy:InvokeServer(name) end)
                                if not okB then break end
                                bought += 1
                                spent += price
                                s -= 1
                                task.wait(0.5)
                            end
                        end
                        State.BuyInfo = bought > 0 and ("beli %d (%d coins)"):format(bought, spent) or "stock kosong"
                        task.wait(bought > 0 and 2 or 10)
                    end
                end
            end
        end
        State.BuyRunning = false
        log("Buy loop berhenti")
    end)
end

local Buy = Window:CreateTab({ Name = "Buy", Icon = "shopping-cart" })
local BB = Buy:CreateGroupbox({ Name = "Auto Buy Bom", Side = "Left" })
BB:CreateToggle({
    Name = "Auto Buy", Desc = "Beli selagi ada stock & duit cukup, sampai habis",
    Flag = "AutoBuy", CurrentValue = false,
    Callback = function(On)
        State.AutoBuy = On
        if On then buyLoop() else _G._cropBuyStop() end
    end,
})
BB:CreateDropdown({
    Name = "Bom", Options = BOMB_NAMES, CurrentOption = BOMB_NAMES,
    MultipleOptions = true, Flag = "BuySel",
    Callback = function(List)
        local set = {}
        if type(List) == "table" then
            for _, v in ipairs(List) do set[v] = true end
        elseif type(List) == "string" then set[List] = true end
        State.BuySel = set
    end,
})
BB:CreateStatus({
    Name = "Stock", Style = "Row", Pin = true,
    Update = function()
        local remotes = RS:FindFirstChild("Remotes")
        local q = remotes and remotes:FindFirstChild("BombShopQuery")
        if not q then return "no-remote" end
        local ok, res = pcall(function() return q:InvokeServer() end)
        if not (ok and type(res) == "table") then return "query-gagal" end
        local parts = {}
        for _, name in ipairs(BOMB_NAMES) do
            local s = tonumber((res.stock or {})[name]) or 0
            if s > 0 then table.insert(parts, name:gsub("Bomb", "") .. " x" .. s) end
        end
        local owned = 0
        for _, v in pairs(res.owned or {}) do owned += tonumber(v) or 0 end
        return ("[%s] milik:%d | %s"):format(
            tostring(buyMonedas()), owned,
            #parts > 0 and table.concat(parts, ", ") or "kosong")
    end,
    UpdateRate = 5,
})
BB:CreateLabel({ Text = "Status: -", Update = function() return "Status: " .. State.BuyInfo end, UpdateRate = 1 })

local Settings = Window:CreateTab({ Name = "Settings", Icon = "settings" })
Settings:CreateConfigManager({ Side = "Left" })
Settings:CreateThemeManager({ Side = "Right" })

Window:LoadAutoload()
print("[CropPickup] loaded (DropItems vacuum)")
