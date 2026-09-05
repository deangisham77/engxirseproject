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
local TeleportS = game:GetService("TeleportService")
local HttpS = game:GetService("HttpService")
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
local RARITY_C3 = {
    Common = Color3.fromRGB(205, 148, 92), Uncommon = Color3.fromRGB(95, 220, 105),
    Rare = Color3.fromRGB(70, 155, 255), Epic = Color3.fromRGB(180, 95, 255),
    Legendary = Color3.fromRGB(255, 170, 45), Mythic = Color3.fromRGB(255, 70, 70),
    Exotic = Color3.fromRGB(255, 216, 74),
}
local Cfg = { vacuum = false, teleport = false, autoSell = false, sellPct = 100, minRarity = 1, monRarity = 6, monSort = "Value", fly = false, flySpeed = 50, noclip = false, speed = false, speedVal = 32, upWarmth = false, upCarry = false, reserve = 0, bombSel = { "ClassicBomb" }, autoBomb = false, pickSel = 9, antiAfk = false, esp = false, espRar = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Exotic" }, antiLag = false, noRender = false }
local Stat = { selling = false, basePos = nil, tryAt = {}, swept = false }

-- angka tuning satu tempat (jarak server: prompt ~15-17, dig <12)
local TUNE = {
    pickupRange = 20, -- fire langsung tanpa teleport (stud; >18 mungkin ditolak server)
    tpLift = 4, -- melayang di atas mesh (stud)
    settleWait = 0.7, -- tunggu replikasi posisi server pasca-TP (detik)
    retryS = 3, -- jeda coba ulang per crystal (detik)
    tickS = 0.4, -- interval loop vacuum (detik)
    sellTpWait = 1.5, sellWait = 1, -- tunggu sell (detik)
    monEveryS = 5, monTickS = 1, -- refresh monitor (detik)
    tpStep = 25, tpInstant = 60, tpStepWait = 0.1, -- teleport stepped (stud, stud, detik). KECIL = aman kick
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

-- ESP crystal (highlight + billboard), incremental + cap
local espMarks = {}
local ESP_CAP = 150
local function espClear()
    for m, e in pairs(espMarks) do
        pcall(function() e.hl:Destroy() end)
        pcall(function() e.gui:Destroy() end)
        espMarks[m] = nil
    end
end
local function espRefresh()
    if not Cfg.esp then
        espClear()
        return
    end
    local want = {}
    for _, r in ipairs(Cfg.espRar) do
        want[r] = true
    end
    for m, e in pairs(espMarks) do
        if not m.Parent or not want[m:GetAttribute("Rarity")] then
            pcall(function() e.hl:Destroy() end)
            pcall(function() e.gui:Destroy() end)
            espMarks[m] = nil
        end
    end
    local h = getHRP()
    local myPos = h and h.Position or Vector3.zero
    local cand = {}
    local function scan(folder)
        for _, m in ipairs(folder:GetChildren()) do
            if want[m:GetAttribute("Rarity")] and not espMarks[m] then
                local mesh = m:FindFirstChild("Mesh_0", true)
                if mesh then
                    table.insert(cand, { m = m, mesh = mesh, d = (mesh.Position - myPos).Magnitude })
                end
            end
        end
    end
    scan(SG)
    scan(DG)
    table.sort(cand, function(a, b) return a.d < b.d end)
    local marked = 0
    for _ in pairs(espMarks) do
        marked += 1
    end
    for _, c in ipairs(cand) do
        if marked >= ESP_CAP then
            break
        end
        local col = RARITY_C3[c.m:GetAttribute("Rarity")] or Color3.new(1, 1, 1)
        local hl = Instance.new("Highlight")
        hl.Name = "ANT_ESP"
        hl.Adornee = c.m
        hl.DepthMode = Enum.HighlightDepthMode.Occluded
        hl.FillColor = col
        hl.OutlineColor = col
        hl.FillTransparency = 0.75
        hl.OutlineTransparency = 0.1
        hl.Parent = c.m
        local bb = Instance.new("BillboardGui")
        bb.Name = "ANT_ESPGUI"
        bb.Adornee = c.mesh
        bb.AlwaysOnTop = false
        bb.Size = UDim2.fromOffset(200, 40)
        bb.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
        bb.MaxDistance = 1500
        bb.Parent = c.m
        local lb = Instance.new("TextLabel")
        lb.BackgroundTransparency = 1
        lb.Size = UDim2.fromScale(1, 1)
        lb.Font = Enum.Font.GothamBold
        lb.TextSize = 12
        lb.TextStrokeTransparency = 0.3
        lb.TextColor3 = Color3.new(1, 1, 1)
        lb.RichText = true
        lb.TextYAlignment = Enum.TextYAlignment.Center
        local rar = c.m:GetAttribute("Rarity") or "Common"
        local luck = tonumber(c.m:GetAttribute("Luck")) or 0
        lb.Text = string.format('<font color="%s">[%s]</font> %s\n%s  +%.1f%%',
            RARITY_HEX[rar] or "#FFFFFF", rar:sub(1, 1),
            c.m:GetAttribute("GemName") or c.m.Name,
            fmtMoney(tonumber(c.m:GetAttribute("Value")) or 0), luck)
        lb.Parent = bb
        espMarks[c.m] = { hl = hl, gui = bb }
        marked += 1
    end
end

-- server actions (adaptasi tab Server qentury)
local Server = {}
function Server.playerNames()
    local names = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            table.insert(names, p.Name)
        end
    end
    table.sort(names)
    if #names == 0 then
        table.insert(names, "(none)")
    end
    return names
end
function Server.teleportTo(name)
    if not name or name == "" or name == "(none)" then
        return false, "no player"
    end
    local p = Players:FindFirstChild(name)
    if not p or not p.Character then
        return false, "not found"
    end
    local t = p.Character:FindFirstChild("HumanoidRootPart") or p.Character:FindFirstChild("Head")
    if not t then
        return false, "no hrp"
    end
    local h = getHRP()
    if not h then
        return false, "no hrp (kamu)"
    end
    tpTo(h, CFrame.new(t.Position + Vector3.new(0, 4, 0)))
    return true
end
function Server.goHome()
    return pcall(function()
        RS:WaitForChild("BaseRemotes"):WaitForChild("TeleportHome"):FireServer()
    end)
end
function Server.rejoin()
    return pcall(function()
        local placeId = game.PlaceId
        local jobId = game.JobId
        if #Players:GetPlayers() <= 1 then
            LP:Kick("\nRejoining...")
            task.wait()
            TeleportS:Teleport(placeId, LP)
        else
            TeleportS:TeleportToPlaceInstance(placeId, jobId, LP)
        end
    end)
end
function Server.hop()
    return pcall(function()
        local url = string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100",
            game.PlaceId)
        local body = game:HttpGet(url)
        local data = HttpS:JSONDecode(body)
        if not data or not data.data then
            error("no servers")
        end
        local list = {}
        for _, s in ipairs(data.data) do
            if s.playing and s.maxPlayers and s.id and s.playing < s.maxPlayers and s.id ~= game.JobId then
                table.insert(list, s.id)
            end
        end
        if #list == 0 then
            error("no free servers")
        end
        TeleportS:TeleportToPlaceInstance(game.PlaceId, list[math.random(1, #list)], LP)
    end)
end
function Server.resetCharacter()
    return pcall(function()
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.Health = 0
        else
            error("no humanoid")
        end
    end)
end
function Server.peak()
    local h = getHRP()
    if not h then
        return false, "no hrp"
    end
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Include
    rp.FilterDescendantsInstances = { workspace.Terrain }
    local cx, cz = h.Position.X, h.Position.Z
    local top = h.Position.Y + 1500
    local bestPos, bestY
    local x = cx - 400
    while x <= cx + 400 do
        local z = cz - 400
        while z <= cz + 400 do
            local hit = workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, -4000, 0), rp)
            if hit and (not bestY or hit.Position.Y > bestY) then
                bestY = hit.Position.Y
                bestPos = hit.Position
            end
            z += 100
        end
        x += 100
    end
    if not bestPos then
        return false, "no peak"
    end
    tpTo(h, CFrame.new(bestPos + Vector3.new(0, 6, 0)))
    return true, "Y=" .. math.floor(bestY)
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

local flyBV, flyBG, flyConn, flyGui
local flyUp, flyDn = false, false
-- grafik hemat (simpan setting asli buat restore)
local gfxSaved
local function setAntiLag(on)
    local L = game:GetService("Lighting")
    if on then
        if not gfxSaved then
            gfxSaved = { shadows = L.GlobalShadows, decor = workspace.Terrain.Decoration, fx = {} }
            for _, f in ipairs(L:GetChildren()) do
                if f:IsA("PostEffect") then
                    gfxSaved.fx[f] = f.Enabled
                end
            end
        end
        L.GlobalShadows = false
        pcall(function() workspace.Terrain.Decoration = false end)
        for _, f in ipairs(L:GetChildren()) do
            if f:IsA("PostEffect") then
                f.Enabled = false
            end
        end
    elseif gfxSaved then
        L.GlobalShadows = gfxSaved.shadows
        pcall(function() workspace.Terrain.Decoration = gfxSaved.decor end)
        for f, en in pairs(gfxSaved.fx) do
            if f.Parent then
                f.Enabled = en
            end
        end
        gfxSaved = nil
    end
end

local function setNoRender(on)
    pcall(function()
        game:GetService("RunService"):Set3dRenderingEnabled(not on)
    end)
end

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
    if flyGui then
        pcall(function() flyGui:Destroy() end)
        flyGui = nil
    end
    flyUp, flyDn = false, false
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.PlatformStand = false
    end
end

-- tombol ▲▼ HP (mouse/keyboard tetap jalan)
local function flyButtons()
    if not UIS.TouchEnabled then
        return
    end
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg or flyGui then
        return
    end
    local gui = Instance.new("ScreenGui")
    gui.Name = "ANT_Fly"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    local function mk(txt, x)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(64, 64)
        b.Position = UDim2.new(1, x, 1, -160)
        b.AnchorPoint = Vector2.new(1, 1)
        b.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
        b.BackgroundTransparency = 0.3
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = Enum.Font.GothamBlack
        b.TextSize = 28
        b.Text = txt
        b.AutoButtonColor = true
        b.Parent = gui
        return b
    end
    local up = mk("▲", -84)
    local dn = mk("▼", -12)
    up.MouseButton1Down:Connect(function() flyUp = true end)
    up.MouseButton1Up:Connect(function() flyUp = false end)
    up.MouseLeave:Connect(function() flyUp = false end)
    dn.MouseButton1Down:Connect(function() flyDn = true end)
    dn.MouseButton1Up:Connect(function() flyDn = false end)
    dn.MouseLeave:Connect(function() flyDn = false end)
    gui.Parent = pg
    flyGui = gui
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
    Cfg.antiAfk = false
    Cfg.esp = false
    Cfg.antiLag = false
    Cfg.noRender = false
    pcall(stopFly)
    pcall(restoreCollide)
    pcall(setAfk, false)
    pcall(setAntiLag, false)
    pcall(setNoRender, false)
    pcall(espClear)
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
local afkConn
local function setAfk(on)
    if on and not afkConn then
        afkConn = LP.Idled:Connect(function()
            pcall(function()
                local vim = game:GetService("VirtualInputManager")
                vim:SendKeyEvent(true, Enum.KeyCode.W, false, game)
                task.wait(0.1)
                vim:SendKeyEvent(false, Enum.KeyCode.W, false, game)
            end)
        end)
    elseif not on and afkConn then
        pcall(function() afkConn:Disconnect() end)
        afkConn = nil
    end
end
task.spawn(function()
    while alive and (RL_STATE == nil or RL_STATE.alive()) do
        task.wait(0.2)
        if not alive or (RL_STATE and not RL_STATE.alive()) then
            break
        end
        -- fly manager
        local wantFly = Cfg.fly
        local hasFly = flyBV ~= nil and flyBV.Parent ~= nil
        if not hasFly and (flyBV ~= nil or flyBG ~= nil or flyConn ~= nil) then
            stopFly() -- objek yatim pasca-respawn, bersihkan biar dibuat ulang
        end
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
                flyButtons()
                flyConn = RunS.Heartbeat:Connect(function()
                    if not Cfg.fly or flyBV == nil or flyBG == nil then
                        return
                    end
                    local char2 = LP.Character
                    local h2 = char2 and char2:FindFirstChild("HumanoidRootPart")
                    local hum2 = char2 and char2:FindFirstChildOfClass("Humanoid")
                    if not h2 then
                        return
                    end
                    local cam = workspace.CurrentCamera
                    -- horizontal: MoveDirection (joystick HP + WASD PC)
                    local move = Vector3.zero
                    if hum2 then
                        local md = hum2.MoveDirection
                        move = Vector3.new(md.X, 0, md.Z)
                        if move.Magnitude > 1 then
                            move = move.Unit
                        end
                    end
                    -- vertikal: keyboard atau tombol HP
                    if UIS:IsKeyDown(Enum.KeyCode.Space) or flyUp then
                        move += Vector3.new(0, 1, 0)
                    end
                    if UIS:IsKeyDown(Enum.KeyCode.LeftControl) or flyDn then
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
        setAfk(Cfg.antiAfk)
    end
    stopFly()
    if noclipConn then
        pcall(function() noclipConn:Disconnect() end)
        noclipConn = nil
    end
    setAfk(false)
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
local ServerTab = Window:AddTab({ Name = "Server", Icon = "server", Description = "Players + hop" })
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

local EspBox = MainTab:AddGroupbox({ Side = "Left", Name = "ESP", Collapsed = true })
EspBox:AddToggle("Esp", { Text = "ESP crystal", Default = false })
EspBox:AddDropdown("EspRar", { Text = "Rarity", Values = RARITY_LIST, Multi = true, Default = RARITY_LIST })

local MonitorBox = MainTab:AddGroupbox({ Side = "Left", Name = "Monitor Top 10" })
MonitorBox:AddDropdown("MonRarity", { Text = "Rarity", Values = RARITY_LIST, Default = 6 })
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
local bombFirst = nil
for _, v in ipairs(BombData.List) do
    local label = string.format("%s (%s)", v.id, fmtMoney(v.price))
    table.insert(bombIds, label)
    if not bombFirst then
        bombFirst = label
    end
end
BombBox:AddDropdown("BombSel", { Text = "Bomb", Values = bombIds, Multi = true, Default = { bombFirst } })
BombBox:AddToggle("AutoBomb", { Text = "Auto buy", Default = false })
BombBox:AddButton({ Text = "Buy Now", Func = function()
    buyBombs()
end })

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

local SrvPlayers = ServerTab:AddGroupbox({ Side = "Left", Name = "Players" })
SrvPlayers:AddDropdown("ServerPlayer", { Text = "Player", Values = Server.playerNames(), Default = 1, Searchable = true })
SrvPlayers:AddButton({ Text = "Refresh Players", Func = function()
    local vals = Server.playerNames()
    pcall(function()
        local dd = Options.ServerPlayer
        if dd then
            if dd.SetValues then
                dd:SetValues(vals)
            end
            if dd.SetValue and vals[1] then
                dd:SetValue(vals[1])
            end
        end
    end)
    notify("Players", tostring(#vals) .. " listed")
end })
SrvPlayers:AddButton({ Text = "Teleport to Player", Func = function()
    local name = Options.ServerPlayer and Options.ServerPlayer.Value
    local ok, err = Server.teleportTo(name)
    notify("TP Player", ok and ("-> " .. tostring(name)) or tostring(err))
end })

local SrvAct = ServerTab:AddGroupbox({ Side = "Left", Name = "Server Actions" })
SrvAct:AddButton({ Text = "Rejoin", Func = function()
    local ok, err = Server.rejoin()
    if not ok then
        notify("Rejoin", tostring(err))
    end
end })
SrvAct:AddButton({ Text = "Hop Server", Func = function()
    local ok, err = Server.hop()
    if not ok then
        notify("Hop", tostring(err))
    end
end })
SrvAct:AddButton({ Text = "Go Home", Func = function()
    local ok, err = Server.goHome()
    notify("Go Home", ok and "OK" or tostring(err))
end })
SrvAct:AddButton({ Text = "Teleport Peak", Func = function()
    local ok, msg = Server.peak()
    notify(ok and "Peak" or "Peak gagal", tostring(msg))
end })
SrvAct:AddButton({ Text = "Reset Character", Func = function()
    local ok, err = Server.resetCharacter()
    if not ok then
        notify("Reset", tostring(err))
    end
end })

local MoveBox = MiscTab:AddGroupbox({ Side = "Left", Name = "Movement" })
MoveBox:AddToggle("Fly", { Text = "Fly (joystick/analog + ▲▼)", Default = false })
MoveBox:AddSlider("FlySpeed", { Text = "Fly speed", Default = 50, Min = 10, Max = 150, Rounding = 0 })
MoveBox:AddToggle("Noclip", { Text = "NoClip", Default = false })
MoveBox:AddToggle("AntiAfk", { Text = "Anti-AFK", Default = false })
MoveBox:AddToggle("Speed", { Text = "Speed booster", Default = false })
MoveBox:AddSlider("SpeedVal", { Text = "Speed (risiko kick!)", Default = 32, Min = 16, Max = 120, Rounding = 0 })

local GfxBox = MiscTab:AddGroupbox({ Side = "Left", Name = "Graphic" })
GfxBox:AddToggle("AntiLag", { Text = "Anti lag", Default = false })
GfxBox:AddToggle("NoRender", { Text = "No render (layar hitam, farm jalan)", Default = false })

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
Toggles.Esp:OnChanged(function(v)
    Cfg.esp = v
    if not v then
        espClear()
    end
end)
Options.EspRar:OnChanged(function(v)
    local list = {}
    if type(v) == "table" then
        for k, on in pairs(v) do
            if on then
                table.insert(list, type(k) == "number" and v[k] or k)
            end
        end
    elseif type(v) == "string" then
        list = { v }
    end
    if #list == 0 then
        list = { "Common" }
    end
    Cfg.espRar = list
end)
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
    local function put(s)
        local id = tostring(s):match("^(%S+)")
        if id then
            table.insert(list, id)
        end
    end
    if type(v) == "table" then
        for k, on in pairs(v) do
            if on then
                put(type(k) == "number" and v[k] or k)
            end
        end
    elseif type(v) == "string" then
        put(v)
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
Toggles.AntiAfk:OnChanged(function(v) Cfg.antiAfk = v end)
Toggles.AntiLag:OnChanged(function(v)
    Cfg.antiLag = v
    setAntiLag(v)
end)
Toggles.NoRender:OnChanged(function(v)
    Cfg.noRender = v
    setNoRender(v)
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
    return string.format("vacuum=%s teleport=%s autoSell=%s minRar=%d monRar=%d monSort=%s tick=%ds lalu target=%s",
        tostring(Cfg.vacuum), tostring(Cfg.teleport), tostring(Cfg.autoSell),
        Cfg.minRarity, Cfg.monRarity, tostring(Cfg.monSort),
        math.floor(os.clock() - (Stat.lastTick or 0)), tostring(Stat.lastTarget or "-"))
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
                string.format("%.1f%%", r.luck), kg, r.d)
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
                espRefresh()
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
            Stat.lastTick = os.clock()
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
            local best, bestD, bestP, bestPos, bestScore = nil, math.huge, nil, nil, math.huge
            local function consider(m, w)
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
                        local score = d * (w or 1)
                        if score < bestScore then
                            best, bestD, bestP, bestPos, bestScore = m, d, pr, pos, score
                        end
                    end
                end
            end
            -- semua pool dinilai, terdekat menang (drop bisa despawn: bobot jarak 0.8x)
            for _, m in ipairs(DG:GetChildren()) do
                consider(m, 0.8)
            end
            for _, m in ipairs(SG:GetChildren()) do
                if m:GetAttribute("Freed") then
                    consider(m, 1)
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
            Stat.lastTarget = best.Name .. " " .. math.floor(bestD) .. "st"
            if os.clock() - (Stat.lastBeat or 0) > 30 then
                Stat.lastBeat = os.clock()
                print("[hub] kerja: " .. Stat.lastTarget)
            end
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
