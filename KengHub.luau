-- Keng Hub v5.1 | Punch and Steal an Egg (Place 86978157069603)
-- Walk-only: Humanoid:MoveTo. NO teleport, NO WalkSpeed (kick 267, terbukti).
local AIRFLOW_URL = "https://raw.githubusercontent.com/joustingmatch/-3/main/Source.luau"
pcall(function()
    local old = getgenv()._EggPetAirWin
    if old and old.Destroy then old:Destroy() end
end)
getgenv()._EggPetAirWin = nil
getgenv()._KengHub = nil
local Airflow = loadstring(game:HttpGet(AIRFLOW_URL))()
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer
local Remotes = RS:WaitForChild("GameShared"):WaitForChild("Remotes")
local EggPunch = Remotes:WaitForChild("EggPunch")
local PetAction = Remotes:WaitForChild("PetAction")
local IDLE_MSG = "Idle: hub ready. Nyalakan Auto Punch / Steal."
-- Urutan rarity sesuai IndexConfig live (RarityByName.Order)
local RORDER = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythical = 6, Divine = 7, Exotic = 8, Celestial = 9, Cosmic = 10 }
local RARITY_OPTS = { "Any", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythical", "Divine", "Exotic", "Celestial", "Cosmic" }
local BIOME_OPTS = { "Any", "1 Forest", "2 Desert", "3 Snow", "4 Candy", "5 Tropical Beach", "6 Mushroom Grove", "7 Haunted Graveyard", "8 Volcano", "9 Cave", "10 Galaxy" }
local function parseBiome(v)
    if type(v) == "table" then v = v[1] end
    if v == "Any" then return nil end
    return tonumber(tostring(v):match("^(%d+)"))
end
local H = {
    running = { punch = false, steal = false, treadmill = false, base = false, antihit = false },
    counts = { punch = 0, steal = 0, stealFail = 0, errors = 0, tread = 0, based = 0, retreats = 0 },
    status = IDLE_MSG,
    idleMsg = IDLE_MSG,
    targetEgg = "-",
    eggDetail = "-",
    targetPet = "-",
    petDetail = "-",
    threat = "-",
    biome = nil, -- nil = Any
    rarity = "Any",
    punchDelay = 0.25,
    treadSecs = 30,
    treadmillUntil = 0,
    stopMove = false,
    moving = false,
    ui = {},
}
getgenv()._KengHub = H
function H.set(which, on)
    on = on and true or false
    local h = H.ui[which]
    if h and h.Set then
        local ok, e = pcall(function() h:Set(on) end)
        return ok, ok and "ui" or ("ui fail: " .. tostring(e))
    end
    if H.running[which] ~= nil then
        H.running[which] = on
        if not on and which ~= "treadmill" then stopAllMoves() end
        if which == "treadmill" and not on then H.treadmillUntil = 0 end
        return true, "direct"
    end
    return false, "unknown:" .. tostring(which)
end
local function logPush(msg)
    pcall(function()
        local f = H.log
        if f and f.Push then f:Push(tostring(msg)) end
    end)
end
local function err(msg, src)
    H.counts.errors = H.counts.errors + 1
    H.status = "Error [" .. tostring(src) .. "]: " .. tostring(msg)
    logPush("[ERR][" .. tostring(src) .. "] " .. tostring(msg))
end
local function charParts()
    local c = LP.Character
    if not c then return nil, nil end
    return c, c:FindFirstChildOfClass("Humanoid"), c:FindFirstChild("HumanoidRootPart")
end
local function hrpPos()
    local _, _, hrp = charParts()
    return hrp and hrp.Position or nil
end
local moveToken = 0
local function stopAllMoves()
    moveToken = moveToken + 1
    H.stopMove = true
    H.moving = false
end
-- Single mover: hanya farm loop yang memanggil ini. Satu MoveTo chain per waktu.
local function moveToPos(pos, radius)
    radius = radius or 4
    local myToken = moveToken + 1
    moveToken = myToken
    H.stopMove = false
    H.moving = true
    local _, hum, hrp = charParts()
    if not hum or not hrp then H.moving = false return false, "no character" end
    local dist = (hrp.Position - pos).Magnitude
    if dist > 60 then
        local ok, path = pcall(function()
            local p = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
            p:ComputeAsync(hrp.Position, pos)
            return p
        end)
        if ok and path and path.Status == Enum.PathStatus.Success then
            for _, wp in ipairs(path:GetWaypoints()) do
                if moveToken ~= myToken or H.stopMove then H.moving = false return false, "stopped" end
                local _, h2, _ = charParts()
                if not h2 then H.moving = false return false, "lost char" end
                if wp.Action == Enum.PathWaypointAction.Jump then pcall(function() h2:ChangeState(Enum.HumanoidStateType.Jumping) end) end
                h2:MoveTo(wp.Position)
                local t0 = os.clock()
                while (os.clock() - t0) < 4 do
                    if moveToken ~= myToken or H.stopMove then H.moving = false return false, "stopped" end
                    local _, _, hrp2 = charParts()
                    if not hrp2 then break end
                    if (hrp2.Position - wp.Position).Magnitude < 5 then break end
                    task.wait(0.15)
                end
            end
        end
    end
    local _, hum2, hrp2 = charParts()
    if not hum2 or not hrp2 then H.moving = false return false, "lost char" end
    hum2:MoveTo(pos)
    local lastRe = os.clock()
    local t0 = os.clock()
    while (os.clock() - t0) < 10 do
        if moveToken ~= myToken or H.stopMove then H.moving = false return false, "stopped" end
        local _, _, h = charParts()
        if not h then H.moving = false return false, "lost char" end
        if (h.Position - pos).Magnitude <= (radius + 2) then H.moving = false return true end
        if os.clock() - lastRe > 2 then
            lastRe = os.clock()
            pcall(function() hum2:MoveTo(pos) end)
        end
        task.wait(0.2)
    end
    local _, _, h3 = charParts()
    local ok = h3 and (h3.Position - pos).Magnitude <= (radius + 6)
    H.moving = false
    return ok, ok and "ok" or "too far"
end
local function worldEggs()
    local folder = workspace:FindFirstChild("WorldEggs")
    if not folder then return {} end
    local list = {}
    for _, biomeF in ipairs(folder:GetChildren()) do
        for _, egg in ipairs(biomeF:GetChildren()) do
            if egg:IsA("Model") and egg.Name == "WorldEgg" then
                table.insert(list, egg)
            end
        end
    end
    return list
end
local function eggMatches(egg)
    if H.biome then
        if tonumber(egg:GetAttribute("Biome")) ~= tonumber(H.biome) then return false end
    end
    if H.rarity and H.rarity ~= "Any" then
        if tostring(egg:GetAttribute("Rarity") or "") ~= H.rarity then return false end
    end
    return true
end
local function eggInfo(egg, d)
    local an, r, hp, kg = "?", "?", "?", "?"
    pcall(function()
        an = tostring(egg:GetAttribute("AnimalName") or egg:GetAttribute("Animal") or "?")
        r = tostring(egg:GetAttribute("Rarity") or "?")
        hp = tostring(egg:GetAttribute("HP") or "?")
        kg = tostring(egg:GetAttribute("Kg") or "?")
    end)
    return an .. " | " .. r .. " | HP " .. hp .. " | " .. kg .. "kg | " .. math.floor(d or 0) .. "m"
end
local function nearestEgg()
    local me = hrpPos()
    if not me then return nil end
    local best, bestD = nil, math.huge
    for _, egg in ipairs(worldEggs()) do
        local okM, match = pcall(eggMatches, egg)
        if okM and match then
            local okP, piv = pcall(function() return egg:GetPivot().Position end)
            if okP and piv then
                local d = (me - piv).Magnitude
                if d < bestD then best, bestD = egg, d end
            end
        end
    end
    return best, bestD
end
local function stealPrompts()
    local list = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            local root = d.Parent
            local hatched = root and root.Parent
            if root and root.Name == "Root" and hatched and hatched.Name == "HatchedPet" then
                if H.rarity and H.rarity ~= "Any" then
                    local pr2 = tostring(hatched:GetAttribute("Rarity") or "")
                    if pr2 ~= H.rarity then continue end
                end
                table.insert(list, d)
            end
        end
    end
    return list
end
local function petInfo(pr)
    local hatched = pr.Parent and pr.Parent.Parent
    local an, r, kg, inc = "?", "?", "?", "?"
    pcall(function()
        if hatched then
            an = tostring(hatched:GetAttribute("AnimalName") or "?")
            r = tostring(hatched:GetAttribute("Rarity") or "?")
            kg = tostring(hatched:GetAttribute("Kg") or "?")
            inc = tostring(hatched:GetAttribute("Income") or "?")
        end
    end)
    return an .. " | " .. r .. " | " .. kg .. "kg | $" .. inc
end
local function nearestPrompt()
    local me = hrpPos()
    if not me then return nil end
    local best, bestD = nil, math.huge
    for _, pr in ipairs(stealPrompts()) do
        local ok, piv = pcall(function()
            if pr.Parent and pr.Parent:IsA("BasePart") then return pr.Parent.Position end
            return pr.Parent:GetPivot().Position
        end)
        if ok and piv then
            local d = (me - piv).Magnitude
            if d < bestD then best, bestD = pr, d end
        end
    end
    return best, bestD
end
local function doStealPrompt(pr)
    local hold = 0.6
    pcall(function() hold = pr.HoldDuration end)
    hold = math.clamp(tonumber(hold) or 0.6, 0.3, 5)
    if typeof(fireproximityprompt) == "function" then
        local ok, e = pcall(function() fireproximityprompt(pr) end)
        if ok then task.wait(hold + 0.2) end
        return ok, ok and "fireproximityprompt" or ("fpp fail: " .. tostring(e))
    end
    local ok, e = pcall(function()
        pr:InputHoldBegin()
        task.wait(hold + 0.15)
        pr:InputHoldEnd()
    end)
    return ok, ok and "InputHold" or ("hold fail: " .. tostring(e))
end
local function myPenName()
    local uid = LP.UserId
    local pens = workspace:FindFirstChild("Pens")
    if pens then
        for _, pen in ipairs(pens:GetChildren()) do
            if tonumber(pen:GetAttribute("Owner")) == tonumber(uid) then
                return pen.Name
            end
        end
    end
    return nil
end
local function ownPenSpawn()
    local pn = myPenName()
    local pens = workspace:FindFirstChild("Pens")
    if pens and pn then
        local pen = pens:FindFirstChild(pn)
        local gs = pen and pen:FindFirstChild("GardenSpawn", true)
        if gs then
            local ok, p = pcall(function()
                if gs:IsA("BasePart") then return gs.Position end
                return gs:GetPivot().Position
            end)
            if ok and p then return p, pn end
        end
    end
    local me = hrpPos()
    local best, bestD = nil, math.huge
    for _, d in ipairs(workspace:GetDescendants()) do
        if d.Name == "GardenSpawn" then
            local ok, p = pcall(function()
                if d:IsA("BasePart") then return d.Position end
                return d:GetPivot().Position
            end)
            if ok and p then
                local dist = me and (me - p).Magnitude or 0
                if dist < bestD then best, bestD = p, dist end
            end
        end
    end
    return best, "fallback-nearest"
end
local function ownStationDeck()
    local pn = myPenName()
    local sts = workspace:FindFirstChild("TreadmillStations")
    local st = sts and pn and sts:FindFirstChild("Station_" .. pn)
    local deck = st and st:FindFirstChild("DeckCollider", true)
    if deck and deck:IsA("BasePart") then return deck.Position, "Station_" .. pn end
    return nil, nil
end
-- Ancaman = pemain lain dalam 45m saat kita di luar safe zone (X > -98).
-- Respons murni mundur jalan kaki ke base. Tanpa block remote, tanpa serang balik.
local function nearestThreat()
    local me = hrpPos()
    if not me then return nil end
    if me.X < -98 then return nil end -- di safe zone: aman
    local best, bestD = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local d = (me - hrp.Position).Magnitude
                if d < bestD then best, bestD = plr, d end
            end
        end
    end
    if best and bestD <= 45 then return best, bestD end
    return nil
end
-- SATU orchestrator. Break = spam tanpa nunggu menetas.
task.spawn(function()
    while true do
        task.wait(0.3)
        local ok, e = pcall(function()
            if os.clock() < H.treadmillUntil then
                local left = math.floor(H.treadmillUntil - os.clock())
                H.status = "Treadmill: training " .. left .. "s lagi | sessions=" .. H.counts.tread
                task.wait(1)
                return
            end
            -- anti hit: ada pemain dekat di luar safe zone -> mundur ke base
            if H.running.antihit then
                local tp, td = nearestThreat()
                if tp then
                    H.threat = tp.Name .. " " .. math.floor(td) .. "m"
                    H.status = "AntiHit: " .. H.threat .. " dekat! mundur ke base..."
                    logPush("[WARN] threat " .. H.threat .. ", retreat")
                    local p, penName = ownPenSpawn()
                    if p then moveToPos(p, 6) end
                    H.counts.retreats = H.counts.retreats + 1
                    task.wait(1)
                    return
                else
                    H.threat = "clear"
                end
            end
            local wantPunch, wantSteal = H.running.punch, H.running.steal
            if not wantPunch and not wantSteal then
                if H.status ~= H.idleMsg then H.status = H.idleMsg end
                task.wait(0.5)
                return
            end
            local egg, eggD = nil, nil
            if wantPunch then egg, eggD = nearestEgg() end
            local pr, prD = nil, nil
            if wantSteal then pr, prD = nearestPrompt() end
            local job = nil
            if pr and egg then job = (prD <= eggD) and "steal" or "punch"
            elseif pr then job = "steal"
            elseif egg then job = "punch" end
            if job == nil then
                H.status = "Farm: idle, tidak ada target cocok (biome/rarity?) | punches=" .. H.counts.punch .. " stolen=" .. H.counts.steal
                task.wait(1)
                return
            end
            if job == "punch" then
                H.targetEgg = egg:GetFullName()
                H.eggDetail = eggInfo(egg, eggD)
                if (eggD or 9999) > 14 then
                    H.status = "Punch: jalan (" .. math.floor(eggD) .. "m) | " .. H.eggDetail
                    local piv = egg:GetPivot().Position
                    local reached = moveToPos(piv + Vector3.new(4, 0, 0), 8)
                    if not reached then return end
                end
                -- spam tanpa nunggu menetas
                H.status = "Punch: hajar " .. H.eggDetail .. " | punches=" .. H.counts.punch
                EggPunch:FireServer(egg)
                H.counts.punch = H.counts.punch + 1
                task.wait(H.punchDelay)
            else
                H.targetPet = pr:GetFullName()
                H.petDetail = petInfo(pr)
                local tpos = nil
                pcall(function()
                    if pr.Parent:IsA("BasePart") then tpos = pr.Parent.Position
                    else tpos = pr.Parent:GetPivot().Position end
                end)
                if not tpos then task.wait(0.5) return end
                if (prD or 9999) > 10 then
                    H.status = "Steal: jalan (" .. math.floor(prD or 0) .. "m) | " .. H.petDetail
                    moveToPos(tpos, 6)
                    return
                end
                H.status = "Steal: hold prompt | " .. H.petDetail
                local sOk, how = doStealPrompt(pr)
                task.wait(0.8)
                local carried = false
                pcall(function()
                    local c = LP.Character
                    if c then
                        for _, t in ipairs(c:GetChildren()) do
                            if t:IsA("Tool") and t:GetAttribute("Kind") == "Pet" then carried = true end
                        end
                    end
                end)
                local gone = (pr.Parent == nil)
                if sOk and (carried or gone) then
                    H.counts.steal = H.counts.steal + 1
                    H.status = "Steal: sukses (" .. how .. ") | stolen=" .. H.counts.steal
                    logPush("[OK] steal #" .. H.counts.steal .. " " .. H.petDetail)
                    -- TANPA DELAY: langsung gerak. Base didahulukan, lalu treadmill.
                    if H.running.base then
                        local p, penName = ownPenSpawn()
                        if p then
                            H.status = "Base: langsung pulang ke " .. tostring(penName) .. "..."
                            moveToPos(p, 6)
                            H.counts.based = H.counts.based + 1
                            H.status = "Base: sampai " .. tostring(penName) .. " (#" .. H.counts.based .. ")"
                            logPush("[OK] base return #" .. H.counts.based)
                        end
                    elseif H.running.treadmill then
                        local deck, stName = ownStationDeck()
                        if deck then
                            H.status = "Treadmill: jalan ke " .. stName .. "..."
                            moveToPos(deck, 4)
                            H.counts.tread = H.counts.tread + 1
                            H.treadmillUntil = os.clock() + H.treadSecs
                            logPush("[OK] treadmill #" .. H.counts.tread .. " (" .. H.treadSecs .. "s)")
                        end
                    end
                else
                    H.counts.stealFail = H.counts.stealFail + 1
                    H.status = "Steal: hold done, verifikasi (" .. how .. ") fail=" .. H.counts.stealFail
                end
                task.wait(0.3)
            end
        end)
        if not ok then err(e, "farm") task.wait(1) end
    end
end)
local Window = Airflow:CreateWindow({
    Name = "Keng Hub",
    LoadingSubtitle = "Punch and Steal an Egg",
    Icon = "egg",
    ToggleUIKeybind = "RightControl",
    ConfigurationSaving = { Enabled = true, FolderName = "KengHub" },
    Home = { Discord = "dsc.gg/kenghub" },
})
getgenv()._EggPetAirWin = Window
local TabFarm = Window:CreateTab({ Name = "Farm", Icon = "swords" })
local GBLoop = TabFarm:CreateGroupbox({ Name = "Auto", Side = "Left" })
local GBInfo = TabFarm:CreateGroupbox({ Name = "Status", Side = "Right" })
GBInfo:CreateStatus({ Name = "State", Style = "Row", Pin = true, Update = function() return H.status end, UpdateRate = 0.5 })
GBInfo:CreateStatus({ Name = "Target", Style = "Row", Update = function() return H.eggDetail end, UpdateRate = 1 })
GBInfo:CreateStatus({ Name = "Pet", Style = "Row", Update = function() return H.petDetail end, UpdateRate = 1 })
GBInfo:CreateStatus({ Name = "Threat", Style = "Row", Update = function() return H.threat end, UpdateRate = 1 })
GBInfo:CreateStatus({ Name = "Punches", Style = "Row", Update = function() return tostring(H.counts.punch) end })
GBInfo:CreateStatus({ Name = "Stolen", Style = "Row", Pin = true, Update = function() return tostring(H.counts.steal) end })
GBInfo:CreateStatus({ Name = "Treadmill", Style = "Row", Update = function() return tostring(H.counts.tread) end })
GBInfo:CreateStatus({ Name = "Errors", Style = "Row", Update = function() return tostring(H.counts.errors) end })
GBInfo:CreateLabel({ Text = "Walk = Humanoid:MoveTo only. No teleport." })
local tgPunch = GBLoop:CreateToggle({ Name = "Auto Punch (spam, no wait)", Flag = "Keng_AutoPunch", CurrentValue = false, Callback = function(on)
    H.running.punch = on and true or false
    if on then H.status = "Punch: mulai, cari target..." else stopAllMoves() H.status = H.idleMsg end
end })
local tgSteal = GBLoop:CreateToggle({ Name = "Auto Steal", Flag = "Keng_AutoSteal", CurrentValue = false, Callback = function(on)
    H.running.steal = on and true or false
    if on then H.status = "Steal: mulai, cari pet..." else H.status = H.idleMsg end
end })
local tgBase = GBLoop:CreateToggle({ Name = "Auto Base after steal", Flag = "Keng_AutoBase", CurrentValue = false, Tooltip = "Habis steal sukses: TANPA DELAY langsung jalan ke base (pen sendiri). Bukan teleport.", Callback = function(on)
    H.running.base = on and true or false
end })
local tgTread = GBLoop:CreateToggle({ Name = "Auto Treadmill after steal", Flag = "Keng_AutoTread", CurrentValue = false, Tooltip = "Habis steal sukses: jalan ke deck treadmill pen sendiri. Kalah prioritas bila Auto Base on.", Callback = function(on)
    H.running.treadmill = on and true or false
    if not on then H.treadmillUntil = 0 end
end })
local tgAnti = GBLoop:CreateToggle({ Name = "Anti Hit (retreat)", Flag = "Keng_AntiHit", CurrentValue = false, Tooltip = "Pemain lain <=45m di luar safe zone: farm berhenti, jalan ke base. Tanpa serang balik.", Callback = function(on)
    H.running.antihit = on and true or false
    if not on then H.threat = "-" end
end })
H.ui.punch = tgPunch
H.ui.steal = tgSteal
H.ui.base = tgBase
H.ui.treadmill = tgTread
H.ui.antihit = tgAnti
GBLoop:CreateSlider({ Name = "Punch delay", Range = { 15, 100 }, Increment = 5, Suffix = "ms", CurrentValue = 25, Flag = "Keng_PunchDelay", Callback = function(v) H.punchDelay = math.clamp((tonumber(v) or 25) / 100, 0.15, 1) end })
GBLoop:CreateSlider({ Name = "Treadmill secs", Range = { 10, 120 }, Increment = 5, Suffix = "s", CurrentValue = 30, Flag = "Keng_TreadSecs", Callback = function(v) H.treadSecs = math.clamp(math.floor(tonumber(v) or 30), 10, 120) end })
local TabTarget = Window:CreateTab({ Name = "Target", Icon = "crosshair" })
local GBFilter = TabTarget:CreateGroupbox({ Name = "Filter (Zone/Rarity)", Side = "Left" })
local GBRef = TabTarget:CreateGroupbox({ Name = "Referensi", Side = "Right" })
GBRef:CreateParagraph({ Title = "Rarity (Order)", Content = "Common < Uncommon < Rare < Epic < Legendary < Mythical < Divine < Exotic < Celestial < Cosmic" })
GBRef:CreateParagraph({ Title = "Zone (Biome)", Content = "1 Forest, 2 Desert, 3 Snow, 4 Candy, 5 Tropical Beach, 6 Mushroom Grove, 7 Haunted Graveyard, 8 Volcano, 9 Cave, 10 Galaxy" })
GBRef:CreateParagraph({ Title = "Gerak", Content = "Semua gerak = jalan (MoveTo). Tidak ada teleport: teleport = kick 267." })
GBFilter:CreateDropdown({ Name = "Zone", Options = BIOME_OPTS, CurrentOption = "Any", Flag = "Keng_Zone", Callback = function(v)
    if type(v) == "table" then v = v[1] end
    H.biome = parseBiome(v)
end })
GBFilter:CreateDropdown({ Name = "Egg/Pet Rarity", Options = RARITY_OPTS, CurrentOption = "Any", Flag = "Keng_Rarity", Callback = function(v)
    if type(v) == "table" then v = v[1] end
    H.rarity = tostring(v or "Any")
end })
GBFilter:CreateLabel({ Text = "Filter berlaku untuk punch & steal. Any = semua." })
local TabPets = Window:CreateTab({ Name = "Pets", Icon = "paw-print" })
local GBPets = TabPets:CreateGroupbox({ Name = "Pets", Side = "Left" })
local GBShop = TabPets:CreateGroupbox({ Name = "Info", Side = "Right" })
GBShop:CreateParagraph({ Title = "Steal flow", Content = "Punch egg > HatchedPet Root prompt Steal (0.6s hold) > carried Tool Kind=Pet > server auto-stores." })
GBPets:CreateButton({ Name = "Equip Best", Callback = function()
    task.spawn(function()
        local ok, res = pcall(function() return PetAction:InvokeServer(true, "equipBest") end)
        if ok then H.status = "Pets: equipBest sent" logPush("[OK] equipBest") else err(res, "equipBest") end
    end)
end })
GBPets:CreateButton({ Name = "Refresh pet state", Callback = function()
    task.spawn(function()
        local ok, res = pcall(function() return PetAction:InvokeServer(true, "state") end)
        if ok then H.status = "Pets: state refreshed" logPush("state: " .. tostring(res)) else err(res, "petState") end
    end)
end })
local TabMove = Window:CreateTab({ Name = "Move", Icon = "footprints" })
local GBMove = TabMove:CreateGroupbox({ Name = "Travel (walk only)", Side = "Left" })
local GBMoveInfo = TabMove:CreateGroupbox({ Name = "Where", Side = "Right" })
GBMoveInfo:CreateLabel({ Text = "Safe zone X < -98. 10 biomes along +X." })
GBMove:CreateButton({ Name = "Walk to target egg", Callback = function()
    task.spawn(function()
        local ok, e = pcall(function()
            local egg, d = nearestEgg()
            if not egg then H.status = "Move: tidak ada telur cocok filter" return end
            H.status = "Move: jalan ke target (" .. math.floor(d or 0) .. "m) | " .. eggInfo(egg, d)
            moveToPos(egg:GetPivot().Position + Vector3.new(4, 0, 0), 8)
            H.status = "Move: sampai target"
        end)
        if not ok then err(e, "gotoTarget") end
    end)
end })
GBMove:CreateButton({ Name = "Walk to own Pen (base)", Callback = function()
    task.spawn(function()
        local ok, e = pcall(function()
            local p, penName = ownPenSpawn()
            if not p then H.status = "Move: no GardenSpawn found" return end
            H.status = "Move: jalan ke base " .. tostring(penName) .. "..."
            moveToPos(p, 6)
            H.status = "Move: di base " .. tostring(penName) .. " (safe)"
        end)
        if not ok then err(e, "gotoPen") end
    end)
end })
GBMove:CreateButton({ Name = "Walk to treadmill", Callback = function()
    task.spawn(function()
        local ok, e = pcall(function()
            local deck, stName = ownStationDeck()
            if not deck then H.status = "Move: station sendiri tidak ketemu" return end
            H.status = "Move: jalan ke " .. tostring(stName) .. "..."
            moveToPos(deck, 4)
            H.status = "Move: on treadmill deck (game lock)"
        end)
        if not ok then err(e, "gotoTread") end
    end)
end })
GBMove:CreateButton({ Name = "Stop", Callback = function()
    stopAllMoves()
    H.treadmillUntil = 0
    H.running.punch = false
    H.running.steal = false
    H.running.base = false
    H.running.treadmill = false
    H.running.antihit = false
    H.threat = "-"
    pcall(function() tgPunch:Set(false, true) end)
    pcall(function() tgSteal:Set(false, true) end)
    pcall(function() tgBase:Set(false, true) end)
    pcall(function() tgTread:Set(false, true) end)
    pcall(function() tgAnti:Set(false, true) end)
    H.status = H.idleMsg
end })
local GBLogBox = TabFarm:CreateGroupbox({ Name = "Log", Side = "Left" })
H.log = GBLogBox:CreateLog({ MaxEntries = 100, MaxRows = 6, EmptyText = "log ready" })
local TabSettings = Window:CreateTab({ Name = "Settings", Icon = "settings" })
TabSettings:CreateConfigManager({ Side = "Left" })
TabSettings:CreateThemeManager({ Side = "Right" })
Window:LoadAutoload()
H.running.punch = false
H.running.steal = false
H.running.base = false
H.running.treadmill = false
H.running.antihit = false
H.threat = "-"
H.treadmillUntil = 0
stopAllMoves()
pcall(function() tgPunch:Set(false, true) end)
pcall(function() tgSteal:Set(false, true) end)
pcall(function() tgBase:Set(false, true) end)
pcall(function() tgTread:Set(false, true) end)
pcall(function() tgAnti:Set(false, true) end)
H.status = H.idleMsg
logPush("[OK] Keng Hub v5.1 loaded.")
return "KengHub OK v5.1"
