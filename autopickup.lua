--========================================================
-- QENTURY HUB (rebuild)
-- Shells/rebuild/ · UI: deividcomsono Obsidian
-- Phase 1: Main + Settings
-- Source: qentury v4.2.3 Main + donnie Auto Farm (via remake2)
--========================================================

pcall(function()
	if getgenv().QenturyRebuildCleanup then
		getgenv().QenturyRebuildCleanup()
	end
	if getgenv().MaMRemakeCleanup then
		getgenv().MaMRemakeCleanup()
	end
	if getgenv().MaMQenturyCleanup then
		getgenv().MaMQenturyCleanup()
	end
end)

pcall(function()
	local hui = gethui and gethui() or game:GetService("CoreGui")
	for _, old in ipairs(hui:GetChildren()) do
		if old.Name == "Obsidian" then
			old:Destroy()
		end
	end
end)

--========================================================
-- OBSIDIAN (https://github.com/deividcomsono/Obsidian)
-- docs: https://docs.mspaint.cc/obsidian
--========================================================
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LP = Players.LocalPlayer

--========================================================
-- CONSTANTS
--========================================================
local RARITY_MULT = { 1, 1.6, 2.6, 4.2, 7, 12 }
local LUCK_BASE = 0.00045
local LUCK_KG_CAP = 500
local LUCK_WEIGHT_EXP = 0.5
local BOMB_LUCK_MULT = 3
local MUTATION_LUCK = {
	Terminus = 40,
	Voltaic = 20,
	Aurora = 2.2,
	Radioactive = 2,
	Thunder = 1.5,
	Poison = 1.5,
	Frost = 1.4,
	Fire = 1.4,
	Starfall = 1.3,
	Wet = 1,
}

local TIER_NAMES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
local TIER_BADGE = { "C", "U", "R", "E", "L", "M" }
local TIER_LABELS = {
	"C · Common",
	"U · Uncommon",
	"R · Rare",
	"E · Epic",
	"L · Legendary",
	"M · Mythic",
}
local TIER_COLORS = {
	Color3.fromRGB(200, 200, 200),
	Color3.fromRGB(80, 220, 120),
	Color3.fromRGB(70, 140, 255),
	Color3.fromRGB(170, 90, 255),
	Color3.fromRGB(255, 80, 180),
	Color3.fromRGB(255, 60, 60),
}
local BADGE_TO_TIER = { C = 1, U = 2, R = 3, E = 4, L = 5, M = 6 }
local NAME_TO_TIER = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
}

local TP_STEP = 55

-- Crystal size (CrystalConfig.classByKg)
local SIZE_ORDER = { "S", "M", "L", "XL", "Giant", "Colossal", "Titan", "Leviathan", "Behemoth" }
local SIZE_RANK = {
	S = 1,
	M = 2,
	L = 3,
	XL = 4,
	Giant = 5,
	Colossal = 6,
	Titan = 7,
	Leviathan = 8,
	Behemoth = 9,
}
local SIZE_LABELS = {
	"S · Small",
	"M · Medium",
	"L · Large",
	"XL · Extra Large",
	"Giant",
	"Colossal",
	"Titan",
	"Leviathan",
	"Behemoth",
}
local SIZE_KG = { 0, 8, 30, 90, 200, 1000, 3000, 8000, 25000 }

-- Donnie Money Farm (peak → dig down)
local FARM = {
	columnStep = 8,
	ringMax = 6,
	peakStep = 48,
	peakRings = 12,
	peakGap = 10,
	surfaceGap = 0.15,
	columnDry = 40,
	digBurst = 7,
	digSink = 1.2,
	digLift = 6,
	digReach = 12,
	zonePad = 12,
}

--========================================================
-- STATE (Main tab only)
--========================================================
local state = {
	autoMineV2 = false,
	autoMineTPV2 = false,
	instantPrompt = false,
	mineV2Thread = nil,
	mineTPV2Thread = nil,
	instantConn = nil,
	instantInputConn = nil,
	esp = false,
	mineMinTier = 1,
	mineMinSize = 1, -- Auto Mine only (SizeClass rank 1=S … 9=Behemoth)
	listTier = 5,
	listMinSize = 1, -- ESP + crystal list display filter
	listSortBy = "money",
	highlights = {},
	charEsp = false,
	charEspBillboards = {},
	autoSell = false,
	sellAtPct = 95,
	sellThread = nil,
	sellBusy = false,
	autoFarm = false,
	autoFarmThread = nil,
	autoFarmStatus = "Idle",
	-- Runes tab
	runeEsp = false,
	runeHighlights = {},
	runeSelected = nil, -- nil = all; map id -> true when filtered
	autoPickupRune = false,
	autoTpRune = false,
	runeThread = nil,
	runeTpThread = nil,
	-- Boulders tab
	boulderEsp = false,
	boulderHl = {},
	boulderSelected = nil, -- nil = all; map name -> true
	autoBreak = false,
	breakThread = nil,
	_forceBreak = false,
	tpBusy = false,
	-- Character tab
	godmode = false,
	godmodeThread = nil,
	noFallDmg = false,
	noFallConn = nil,
	antiRagdoll = false,
	ragdollConn = nil,
	-- Favorites tab
	autoFavLuck = false,
	autoFavRarity = false,
	favLuckMin = 4,
	favRarityTiers = { [5] = true, [6] = true },
	favThread = nil,
	-- Drop tab
	dropMode = nil, -- "all" | "luck" | "value" | nil
	dropThread = nil,
	dropLuckMin = 10,
	dropValueTarget = 100000,
	dropDelay = 0.2,
	dropSkipFav = true,
	dropStatCount = 0,
	dropStatValue = 0,
}

--========================================================
-- HELPERS
--========================================================
local function getHRP()
	local char = LP.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function getCash()
	local rs = LP:FindFirstChild("PlayerData") and LP.PlayerData:FindFirstChild("RealStats")
	local cash = rs and rs:FindFirstChild("Cash")
	return cash and tonumber(cash.Value) or 0
end

local function formatMoney(n)
	n = tonumber(n) or 0
	local abs = math.abs(n)
	if abs >= 1e9 then
		return string.format("$%.1fB", n / 1e9)
	end
	if abs >= 1e6 then
		return string.format("$%.1fM", n / 1e6)
	end
	if abs >= 1e3 then
		return string.format("$%.1fK", n / 1e3)
	end
	return string.format("$%d", math.floor(n))
end

local function rarityToTier(v)
	if type(v) ~= "string" then
		return 1
	end
	if BADGE_TO_TIER[v] then
		return BADGE_TO_TIER[v]
	end
	if NAME_TO_TIER[v] then
		return NAME_TO_TIER[v]
	end
	local letter = v:match("^([CURELM])")
	if letter and BADGE_TO_TIER[letter] then
		return BADGE_TO_TIER[letter]
	end
	for name, tier in pairs(NAME_TO_TIER) do
		if v:find(name, 1, true) then
			return tier
		end
	end
	return 1
end

-- game: CrystalConfig.classByKg
local function sizeFromKg(kg)
	kg = tonumber(kg) or 0
	if kg >= 25000 then
		return "Behemoth", "Behemoth", 9
	end
	if kg >= 8000 then
		return "Leviathan", "Leviathan", 8
	end
	if kg >= 3000 then
		return "Titan", "Titan", 7
	end
	if kg >= 1000 then
		return "Colossal", "Colossal", 6
	end
	if kg >= 200 then
		return "Giant", "Giant", 5
	end
	if kg >= 90 then
		return "XL", "Extra Large", 4
	end
	if kg >= 30 then
		return "L", "Large", 3
	end
	if kg >= 8 then
		return "M", "Medium", 2
	end
	return "S", "Small", 1
end

local function crystalSize(part)
	if not part then
		return "S", "Small", 1
	end
	local code = part:GetAttribute("SizeClass")
	local name = part:GetAttribute("SizeClassName")
	if type(code) == "string" and code ~= "" then
		local rank = SIZE_RANK[code]
		if rank then
			return code, (type(name) == "string" and name ~= "" and name) or code, rank
		end
	end
	return sizeFromKg(part:GetAttribute("WeightKg") or part:GetAttribute("LuckKg"))
end

local function sizeLabelToRank(v)
	if type(v) ~= "string" then
		return 1
	end
	-- "S · Small" / "XL · Extra Large" / "Behemoth"
	local code = v:match("^(%S+)")
	if code and SIZE_RANK[code] then
		return SIZE_RANK[code]
	end
	for i, label in ipairs(SIZE_LABELS) do
		if v == label or v:find(SIZE_ORDER[i], 1, true) then
			return i
		end
	end
	return 1
end

local function meetsMinSize(part, minRank)
	minRank = minRank or state.mineMinSize or 1
	if minRank <= 1 then
		return true
	end
	local _, _, rank = crystalSize(part)
	return rank >= minRank
end

local CrystalMutationsMod
pcall(function()
	CrystalMutationsMod = require(ReplicatedStorage.Modules.Crystals.CrystalMutations)
end)

local function mutationLuckMult(mut)
	if type(mut) ~= "string" or mut == "" then
		return 1
	end
	if CrystalMutationsMod and type(CrystalMutationsMod.luckMult) == "function" then
		local ok, m = pcall(CrystalMutationsMod.luckMult, mut)
		if ok and type(m) == "number" and m > 0 then
			return m
		end
	end
	return MUTATION_LUCK[mut] or 1
end

local function combinedLuckMult(part)
	local mult = mutationLuckMult(part:GetAttribute("Mutation"))
	local roll = part:GetAttribute("MutationLuckRoll")
	if type(roll) == "number" and roll > 0 then
		mult = roll
	end
	local extra = part:GetAttribute("ExtraMutations")
	if type(extra) == "string" and extra ~= "" then
		for name in string.gmatch(extra, "[^,]+") do
			if name ~= "" then
				mult = mult * mutationLuckMult(name)
			end
		end
	end
	if part:GetAttribute("AdminMutation") == "Radioactive" and part:GetAttribute("Mutation") ~= "Radioactive" then
		if not (type(extra) == "string" and extra:find("Radioactive", 1, true)) then
			mult = mult * mutationLuckMult("Radioactive")
		end
	end
	return mult
end

local function crystalLuckValue(part)
	local tier = tonumber(part:GetAttribute("Tier")) or 1
	local kg = tonumber(part:GetAttribute("LuckKg") or part:GetAttribute("WeightKg")) or 0
	kg = math.min(math.max(0, kg), LUCK_KG_CAP)
	local luck = (RARITY_MULT[tier] or 1) * (kg ^ LUCK_WEIGHT_EXP) * LUCK_BASE
	if part:GetAttribute("BombCrystal") == true then
		luck = luck * BOMB_LUCK_MULT
	end
	return luck * combinedLuckMult(part)
end

local function crystalLuckText(part)
	if not part then
		return ""
	end
	local ok, luck = pcall(crystalLuckValue, part)
	if not ok or type(luck) ~= "number" then
		return ""
	end
	local pct = luck * 100
	if pct == 0 then
		return "+0%"
	end
	if pct < 1 then
		return string.format("+%.2f%%", pct)
	end
	if pct < 10 then
		return string.format("+%.1f%%", pct)
	end
	return string.format("+%.0f%%", pct)
end

local function crystalFolders()
	local list = {}
	local things = workspace:FindFirstChild("Things")
	if things then
		local c = things:FindFirstChild("Crystals")
		if c then
			table.insert(list, c)
		end
	end
	local dropped = workspace:FindFirstChild("DroppedCrystals")
	if dropped then
		table.insert(list, dropped)
	end
	local rootCrystals = workspace:FindFirstChild("Crystals")
	if rootCrystals then
		table.insert(list, rootCrystals)
	end
	return list
end

local function iterCrystals(fn)
	for _, folder in ipairs(crystalFolders()) do
		for _, part in ipairs(folder:GetChildren()) do
			if part:IsA("BasePart") and part:GetAttribute("Tier") then
				fn(part)
			end
		end
	end
end

local function getPrompt(part)
	return part:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function isDroppedCrystal(part)
	if not part then
		return false
	end
	local p = part.Parent
	if p and p.Name == "DroppedCrystals" then
		return true
	end
	local dropped = workspace:FindFirstChild("DroppedCrystals")
	return dropped and part:IsDescendantOf(dropped) and part.Name:find("Dropped", 1, true) ~= nil
end

local function parseBackpackHud()
	local pg = LP:FindFirstChild("PlayerGui")
	local hud = pg and pg:FindFirstChild("ExplorerHud")
	local panel = hud and hud:FindFirstChild("BackpackPanel")
	local label = panel and panel:FindFirstChild("Value")
	local text = label and label.Text
	if type(text) ~= "string" then
		return nil, nil
	end
	local curS, capS = string.match(text, "([%d%.]+)%s*/%s*([%d%.]+)")
	return tonumber(curS), tonumber(capS)
end

local function getCarryCap()
	local _, cap = parseBackpackHud()
	if cap and cap > 0 then
		return cap
	end
	local rs = LP:FindFirstChild("PlayerData") and LP.PlayerData:FindFirstChild("RealStats")
	local w = rs and rs:FindFirstChild("CarryWeight")
	local b = rs and rs:FindFirstChild("CarryWeightBonus")
	return (w and tonumber(w.Value) or 0) + (b and tonumber(b.Value) or 0)
end

local function totalCrystalKg()
	local cur = parseBackpackHud()
	if cur and cur >= 0 then
		return cur
	end
	local sum = 0
	local function scan(container)
		if not container then
			return
		end
		for _, t in ipairs(container:GetChildren()) do
			if t:IsA("Tool") and t:GetAttribute("Tier") ~= nil then
				sum += tonumber(t:GetAttribute("WeightKg")) or 0
			end
		end
	end
	scan(LP:FindFirstChild("Backpack"))
	if LP.Character then
		scan(LP.Character)
	end
	return sum
end

local function countCrystalTools()
	local n = 0
	local function scan(container)
		if not container then
			return
		end
		for _, t in ipairs(container:GetChildren()) do
			if t:IsA("Tool") and t:GetAttribute("Tier") ~= nil then
				n += 1
			end
		end
	end
	scan(LP:FindFirstChild("Backpack"))
	if LP.Character then
		scan(LP.Character)
	end
	return n
end

--========================================================
-- TELEPORT
--========================================================
local function softSetCFrame(hrp, hum, cf)
	if hum then
		hum.Sit = false
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.Freefall)
		end)
	end
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	for _ = 1, 4 do
		hrp.CFrame = cf
		hrp.AssemblyLinearVelocity = Vector3.zero
		task.wait()
	end
end

local function steppedTeleport(goalPos, yOffset)
	local hrp = getHRP()
	if not hrp then
		return false, "no hrp"
	end
	if state.tpBusy then
		return false, "busy"
	end
	state.tpBusy = true
	local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
	local start = hrp.Position
	local goal = goalPos + Vector3.new(0, yOffset or 4, 0)
	local dist = (goal - start).Magnitude
	local steps = math.max(1, math.ceil(dist / TP_STEP))
	for i = 1, steps do
		if not hrp.Parent then
			state.tpBusy = false
			return false, "char gone"
		end
		softSetCFrame(hrp, hum, CFrame.new(start:Lerp(goal, i / steps)))
		task.wait(0.05)
	end
	softSetCFrame(hrp, hum, CFrame.new(goal))
	state.tpBusy = false
	return true
end

local function findTerrainPeak()
	local char = LP.Character
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local best
	for x = -800, 800, 40 do
		for z = -400, 900, 40 do
			local hit = workspace:Raycast(Vector3.new(x, 3500, z), Vector3.new(0, -5000, 0), params)
			if hit and hit.Position.Y > 100 and (not best or hit.Position.Y > best.Y) then
				best = hit.Position
			end
		end
	end
	if best then
		local bx, by, bz = best.X, best.Y, best.Z
		for x = bx - 45, bx + 45, 4 do
			for z = bz - 45, bz + 45, 4 do
				local hit = workspace:Raycast(Vector3.new(x, by + 700, z), Vector3.new(0, -1600, 0), params)
				if hit and hit.Position.Y > best.Y then
					best = hit.Position
				end
			end
		end
	end
	return best
end

local function teleportTo(part)
	if not part or not part.Parent then
		Library:Notify({ Title = "Teleport", Description = "Crystal gone.", Time = 2 })
		return
	end
	local ok, err = steppedTeleport(part.Position, 3)
	if not ok then
		Library:Notify({ Title = "Teleport", Description = tostring(err), Time = 2 })
	end
end

local function teleportToPeak()
	Library:Notify({ Title = "Peak TP", Description = "Scanning terrain…", Time = 2 })
	local peak = findTerrainPeak()
	if not peak then
		Library:Notify({ Title = "Peak TP", Description = "No peak found.", Time = 2 })
		return
	end
	local ok, err = steppedTeleport(peak, 6)
	Library:Notify({
		Title = ok and "Peak TP" or "Peak TP failed",
		Description = ok and string.format("Y=%d", math.floor(peak.Y)) or tostring(err),
		Time = 3,
	})
end

--========================================================
-- PICKUP (1 fire path · Donnie aggressive · Auto + Instant + TP)
--========================================================
local HoldComplete = ReplicatedStorage:FindFirstChild("Remotes")
	and ReplicatedStorage.Remotes:FindFirstChild("CrystalHoldComplete")

local PICK = {
	range = 13,
	pad = 4,
	burst = 8,
	cooldown = 0.04,
	restore = 0.2,
	retry = 0.15,
	forget = 5,
	instantRadius = 60,
	instantTick = 0.25,
}

local promptRestores = {}
local promptGrabbed = {} -- alias for cleanup / claim stamps (crystal or prompt)
local claimed = promptGrabbed
local instantPatched = {}
local lastPickup = 0
local lastBagWarn = 0
local instantAccumulator = math.huge

local promptCache = setmetatable({}, { __mode = "k" })

local function crystalPrompt(inst)
	local cached = promptCache[inst]
	if cached and cached.Parent then
		return cached
	end
	local prompt = getPrompt(inst)
	if prompt then
		promptCache[inst] = prompt
		return prompt
	end
	promptCache[inst] = nil
	return nil
end

local function surfaceDistance(part, origin)
	local ok, distance = pcall(function()
		local point = part.CFrame:PointToObjectSpace(origin)
		local half = part.Size * 0.5
		local clamped = Vector3.new(
			math.clamp(point.X, -half.X, half.X),
			math.clamp(point.Y, -half.Y, half.Y),
			math.clamp(point.Z, -half.Z, half.Z)
		)
		return (point - clamped).Magnitude
	end)
	if ok and distance then
		return distance
	end
	return (part.Position - origin).Magnitude
end

local function bagFree()
	local cap = getCarryCap()
	if not cap or cap <= 0 then
		return math.huge
	end
	return math.max(0, cap - totalCrystalKg())
end

local function firePrompt(prompt)
	if not prompt or not prompt.Parent then
		return false
	end
	if not promptRestores[prompt] then
		promptRestores[prompt] = {
			hold = prompt.HoldDuration,
			sight = prompt.RequiresLineOfSight,
			enabled = prompt.Enabled,
			range = prompt.MaxActivationDistance,
		}
	end
	pcall(function()
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Enabled = true
		prompt.MaxActivationDistance = 1000
	end)
	local fired = false
	if typeof(fireproximityprompt) == "function" then
		fired = pcall(fireproximityprompt, prompt, 1)
		if not fired then
			fired = pcall(fireproximityprompt, prompt)
		end
	end
	if not fired then
		fired = pcall(function()
			prompt:InputHoldBegin()
			prompt:InputHoldEnd()
		end)
	end
	-- Instant ON keeps hold=0 via instantPatched; still restore MaxDist later
	if not state.instantPrompt then
		task.delay(PICK.restore, function()
			local saved = promptRestores[prompt]
			if not saved then
				return
			end
			promptRestores[prompt] = nil
			if prompt.Parent and not instantPatched[prompt] then
				pcall(function()
					prompt.HoldDuration = saved.hold
					prompt.RequiresLineOfSight = saved.sight
					prompt.Enabled = saved.enabled
					prompt.MaxActivationDistance = saved.range
				end)
			elseif prompt.Parent and saved.range then
				pcall(function()
					prompt.MaxActivationDistance = saved.range
				end)
				promptRestores[prompt] = nil
			end
		end)
	end
	return fired
end

-- single aggressive grab (no ActionText gate · MaxDist stretch · HoldComplete first)
local function grabCrystal(inst, prompt)
	if not inst or not inst.Parent then
		return false
	end
	local sent = false
	if HoldComplete then
		sent = pcall(function()
			HoldComplete:FireServer(inst)
		end)
	end
	prompt = prompt or crystalPrompt(inst)
	if prompt and prompt.Parent and firePrompt(prompt) then
		sent = true
	end
	if not sent and typeof(fireclickdetector) == "function" then
		local ok, detector = pcall(inst.FindFirstChildWhichIsA, inst, "ClickDetector", true)
		if ok and detector then
			sent = pcall(fireclickdetector, detector, 0)
		end
	end
	return sent
end

local function tryMineInstant(part)
	return grabCrystal(part, crystalPrompt(part))
end

local function inRange(part, hrp, pad)
	if not part or not hrp then
		return false, nil
	end
	local prompt = crystalPrompt(part)
	local d = surfaceDistance(part, hrp.Position)
	return d <= PICK.range + (pad or 0), prompt
end

local function listMineables(minTier, hrp, maxDist, skip)
	local minSize = state.mineMinSize or 1
	local origin = hrp and hrp.Position
	local list = {}
	iterCrystals(function(part)
		if skip and skip[part] then
			return
		end
		if not part.Parent or part:GetAttribute("Collected") == true then
			return
		end
		if (tonumber(part:GetAttribute("Tier")) or 0) < minTier then
			return
		end
		if not meetsMinSize(part, minSize) then
			return
		end
		local d = origin and surfaceDistance(part, origin) or 0
		if maxDist and d > maxDist then
			return
		end
		table.insert(list, {
			part = part,
			d = d,
			value = tonumber(part:GetAttribute("Value")) or 0,
			weight = tonumber(part:GetAttribute("WeightKg")) or 0,
			prompt = crystalPrompt(part),
		})
	end)
	table.sort(list, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.d < b.d
	end)
	return list
end

local function pickupStep(stillOn)
	local now = os.clock()
	if now - lastPickup < PICK.cooldown then
		return 0
	end
	local hrp = getHRP()
	if not hrp then
		return 0
	end
	local free = bagFree()
	if free <= 0 then
		if now - lastBagWarn >= 8 then
			lastBagWarn = now
			Library:Notify({ Title = "Pickup", Description = "Backpack full", Time = 2 })
		end
		return 0
	end
	for inst, stamp in pairs(claimed) do
		if type(stamp) == "number" and (now - stamp >= PICK.forget or not inst or not inst.Parent) then
			claimed[inst] = nil
		end
	end
	local n = 0
	local budget = free
	local minTier = state.mineMinTier or 1
	for _, t in ipairs(listMineables(minTier, hrp, PICK.range + PICK.pad)) do
		if n >= PICK.burst or Library.Unloaded or (stillOn and not stillOn()) then
			break
		end
		local claim = claimed[t.part]
		local skip = (claim and now - claim < PICK.retry) or (t.weight > budget)
		if not skip then
			claimed[t.part] = now
			if grabCrystal(t.part, t.prompt) then
				budget -= t.weight
				n += 1
			end
		end
	end
	if n > 0 then
		lastPickup = now
	end
	return n
end

-- vacuumNearby = pickupStep wrapper (TP / farm still call this name)
local function vacuumNearby(minTier, maxCount, stillOn)
	local prev = state.mineMinTier
	if minTier then
		state.mineMinTier = minTier
	end
	local n = pickupStep(stillOn)
	state.mineMinTier = prev
	return n
end

local function instantPromptPatch(prompt)
	if not prompt or instantPatched[prompt] or promptRestores[prompt] then
		return
	end
	instantPatched[prompt] = {
		hold = prompt.HoldDuration,
		sight = prompt.RequiresLineOfSight,
		enabled = prompt.Enabled,
	}
	pcall(function()
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Enabled = true
	end)
end

local function restoreInstantPrompts()
	for prompt, saved in pairs(instantPatched) do
		if prompt.Parent then
			pcall(function()
				prompt.HoldDuration = saved.hold
				prompt.RequiresLineOfSight = saved.sight
				prompt.Enabled = saved.enabled
			end)
		end
	end
	table.clear(instantPatched)
end

local function refreshInstantPrompts()
	local hrp = getHRP()
	if not hrp then
		return
	end
	for prompt in pairs(instantPatched) do
		if not prompt.Parent then
			instantPatched[prompt] = nil
		end
	end
	iterCrystals(function(part)
		if part:GetAttribute("Collected") == true then
			return
		end
		if surfaceDistance(part, hrp.Position) > PICK.instantRadius then
			return
		end
		local prompt = crystalPrompt(part)
		if prompt then
			instantPromptPatch(prompt)
		end
	end)
end

local function instantGrab()
	if not state.instantPrompt then
		return
	end
	local hrp = getHRP()
	if not hrp then
		return
	end
	local best, bestPrompt, bestD
	iterCrystals(function(part)
		if not part.Parent or part:GetAttribute("Collected") == true then
			return
		end
		local d = surfaceDistance(part, hrp.Position)
		if d <= PICK.range and (not bestD or d < bestD) then
			best = part
			bestPrompt = crystalPrompt(part)
			bestD = d
		end
	end)
	if not best then
		return
	end
	if bestPrompt then
		instantPromptPatch(bestPrompt)
	end
	if grabCrystal(best, bestPrompt) then
		claimed[best] = os.clock()
	end
end

local function setInstantPrompt(on)
	state.instantPrompt = on
	instantAccumulator = math.huge
	if not on then
		if state.instantConn then
			pcall(function()
				state.instantConn:Disconnect()
			end)
			state.instantConn = nil
		end
		if state.instantInputConn then
			pcall(function()
				state.instantInputConn:Disconnect()
			end)
			state.instantInputConn = nil
		end
		restoreInstantPrompts()
		return
	end
	if not state.instantConn then
		state.instantConn = RunService.Heartbeat:Connect(function(dt)
			if not state.instantPrompt or Library.Unloaded then
				return
			end
			instantAccumulator += dt
			if instantAccumulator >= PICK.instantTick then
				instantAccumulator = 0
				pcall(refreshInstantPrompts)
			end
		end)
	end
	if not state.instantInputConn then
		state.instantInputConn = UserInputService.InputBegan:Connect(function(input, processed)
			if processed or not state.instantPrompt or Library.Unloaded then
				return
			end
			if UserInputService:GetFocusedTextBox() then
				return
			end
			if input.KeyCode == Enum.KeyCode.E then
				pcall(instantGrab)
			end
		end)
	end
	refreshInstantPrompts()
end

local function bagNearFull()
	if not state.autoSell then
		return false
	end
	local cap = getCarryCap()
	return cap > 0 and totalCrystalKg() >= cap * ((state.sellAtPct or 95) / 100)
end

local function mineAlive(flag)
	return state[flag] and not Library.Unloaded and not bagNearFull()
end

local function stopAutoMineV2()
	state.autoMineV2 = false
end

local function startAutoMineV2()
	if state.mineV2Thread then
		return
	end
	state.mineV2Thread = task.spawn(function()
		while state.autoMineV2 and not Library.Unloaded do
			if bagNearFull() then
				task.wait(0.5)
			else
				local n = pickupStep(function()
					return state.autoMineV2
				end)
				task.wait(n > 0 and PICK.cooldown or 0.08)
			end
		end
		state.mineV2Thread = nil
	end)
end

local function stopAutoMineTPV2()
	state.autoMineTPV2 = false
end

local function startAutoMineTPV2()
	if state.mineTPV2Thread then
		return
	end
	state.mineTPV2Thread = task.spawn(function()
		local skip, fails = {}, 0
		local on = function()
			return mineAlive("autoMineTPV2")
		end
		while state.autoMineTPV2 and not Library.Unloaded do
			if bagNearFull() then
				task.wait(0.5)
			else
				pickupStep(on)
				local best = listMineables(state.mineMinTier, getHRP(), nil, skip)[1]
				if not best or not best.part.Parent then
					skip, fails = {}, fails + 1
					if fails >= 3 then
						Library:Notify({
							Title = "Auto Pickup TP",
							Description = "No crystals ≥ tier " .. state.mineMinTier,
							Time = 2,
						})
						fails = 0
					end
					task.wait(0.5)
				else
					fails = 0
					local part, before = best.part, countCrystalTools()
					local hrp = getHRP()
					local near = hrp and select(1, inRange(part, hrp, 2))
					if not near then
						if not steppedTeleport(part.Position, 3) or not on() then
							skip[part] = true
							task.wait(0.15)
						else
							task.wait(0.08)
						end
					end
					if part.Parent and on() then
						grabCrystal(part, crystalPrompt(part))
						pickupStep(on)
						local t0 = os.clock()
						local got = false
						while os.clock() - t0 < 1.5 do
							if not on() then
								break
							end
							if countCrystalTools() > before then
								got = true
								break
							end
							task.wait(0.1)
						end
						skip[part] = not got and true or nil
						task.wait(got and PICK.cooldown or 0.12)
					end
				end
				for p in pairs(skip) do
					if not p or not p.Parent then
						skip[p] = nil
					end
				end
			end
		end
		state.mineTPV2Thread = nil
	end)
end

--========================================================
-- SELL
--========================================================
local function getSellPosition()
	local things = workspace:FindFirstChild("Things")
	local prox = things and things:FindFirstChild("SellProx")
	if prox and prox:IsA("BasePart") then
		return prox.Position
	end
	local model = things and things:FindFirstChild("SellModel")
	if model then
		local p = model:FindFirstChildWhichIsA("BasePart", true)
		if p then
			return p.Position
		end
	end
	return nil
end

local function ensureNearSell(maxDist)
	maxDist = maxDist or 12
	local hrp = getHRP()
	local sellPos = getSellPosition()
	if not hrp or not sellPos then
		return false, "no sell zone"
	end
	if (hrp.Position - sellPos).Magnitude <= maxDist then
		return true
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local goHome = remotes and remotes:FindFirstChild("GoHome")
	if goHome then
		pcall(function()
			goHome:FireServer("sell")
		end)
		task.wait(1.2)
		hrp = getHRP()
		if hrp and (hrp.Position - sellPos).Magnitude <= maxDist + 5 then
			return true
		end
	end
	if not steppedTeleport(sellPos + Vector3.new(0, 3, 0), 3) then
		return false, "tp sell fail"
	end
	task.wait(0.35)
	hrp = getHRP()
	if not hrp then
		return false, "no hrp"
	end
	return (hrp.Position - sellPos).Magnitude <= maxDist + 8, "still far"
end

local function doSellAll()
	if state.sellBusy then
		return false, "busy"
	end
	if countCrystalTools() <= 0 then
		return false, "empty"
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local sellReq = remotes and remotes:FindFirstChild("SellRequest")
	if not sellReq then
		return false, "no SellRequest"
	end
	state.sellBusy = true
	local nearOk, nearErr = ensureNearSell(12)
	if not nearOk then
		state.sellBusy = false
		return false, nearErr or "not near sell"
	end
	local hrp = getHRP()
	local sellPos = getSellPosition()
	local holdConn
	if hrp and sellPos then
		holdConn = RunService.Heartbeat:Connect(function()
			local h = getHRP()
			if h then
				h.CFrame = CFrame.new(sellPos + Vector3.new(0, 3, 0))
				h.AssemblyLinearVelocity = Vector3.zero
			end
		end)
	end
	local cash0 = getCash()
	local tools0 = countCrystalTools()
	local ok, err = pcall(function()
		sellReq:FireServer("all")
	end)
	task.wait(1.4)
	if holdConn then
		holdConn:Disconnect()
	end
	state.sellBusy = false
	if not ok then
		return false, tostring(err)
	end
	local tools1 = countCrystalTools()
	local cash1 = getCash()
	local sold = tools0 - tools1
	if sold <= 0 and cash1 <= cash0 then
		return false, "sell rejected (need near buyer?)"
	end
	return true, { sold = sold, cashDelta = cash1 - cash0 }
end

local function stopAutoSell()
	state.autoSell = false
end

local function startAutoSell()
	if state.sellThread then
		return
	end
	state.sellThread = task.spawn(function()
		while state.autoSell and not Library.Unloaded do
			local cap = getCarryCap()
			local kg = totalCrystalKg()
			local pct = state.sellAtPct or 95
			if cap > 0 and kg >= cap * (pct / 100) then
				local ok, info = doSellAll()
				if ok then
					Library:Notify({
						Title = "Auto-Sell",
						Description = string.format(
							"Sold %s · +%s",
							tostring(info.sold or "?"),
							formatMoney(info.cashDelta or 0)
						),
						Time = 3,
					})
					task.wait(1.5)
				else
					task.wait(1.2)
				end
			else
				task.wait(0.8)
			end
		end
		state.sellThread = nil
	end)
end

--========================================================
-- DIG / STRIP MINE / AUTO DIG FORWARD
--========================================================
local ToolConfig, ZoneCheck
pcall(function()
	ToolConfig = require(ReplicatedStorage.Modules.Tools.ToolConfig)
end)
pcall(function()
	ZoneCheck = require(ReplicatedStorage.Modules.Tools.ZoneCheck)
end)

local digAngleIdx = 0

local function isPickaxeTool(tool)
	if not tool or not tool:IsA("Tool") then
		return false
	end
	if tool:GetAttribute("IsPickaxe") or tool:GetAttribute("DigPower") then
		return true
	end
	local n = tool.Name
	return n:find("Pick") ~= nil
		or n:find("Apex") ~= nil
		or n:find("Scrapper") ~= nil
		or n:find("Spike") ~= nil
		or n:find("Carver") ~= nil
		or n:find("Basalt") ~= nil
		or n:find("Edge") ~= nil
		or n:find("Tempest") ~= nil
end

local function getEquippedPickaxe()
	local c = LP.Character
	if not c then
		return nil
	end
	local equipped = c:FindFirstChildOfClass("Tool")
	if isPickaxeTool(equipped) then
		return equipped
	end
	local hum = c:FindFirstChildOfClass("Humanoid")
	local bp = LP:FindFirstChild("Backpack")
	if bp then
		for _, tool in ipairs(bp:GetChildren()) do
			if isPickaxeTool(tool) then
				if hum then
					pcall(function()
						hum:EquipTool(tool)
					end)
					task.wait(0.12)
				end
				return c:FindFirstChildOfClass("Tool") or tool
			end
		end
	end
	return nil
end

local function digCooldown(toolName)
	if ToolConfig and ToolConfig.getTool then
		local cfg = ToolConfig.getTool(toolName)
		if cfg and cfg.cooldown then
			return math.max(0.35, cfg.cooldown * 0.72)
		end
	end
	return 0.4
end

local function fireDig(toolName, pos)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local dig = remotes and remotes:FindFirstChild("DigRequest")
	if not dig then
		return false
	end
	return pcall(function()
		dig:FireServer(toolName, pos)
	end)
end

--========================================================
-- AUTO FARM (Donnie Money Farm): peak → dig column down
--========================================================
local farmOffsets, farmPeakOffsets
do
	farmOffsets = { Vector2.new(0, 0) }
	farmPeakOffsets = { Vector2.new(0, 0) }
	for ring = 1, FARM.ringMax do
		local slices = ring * 6
		for slice = 0, slices - 1 do
			local ang = slice / slices * math.pi * 2
			local r = ring * FARM.columnStep
			farmOffsets[#farmOffsets + 1] = Vector2.new(math.cos(ang) * r, math.sin(ang) * r)
		end
	end
	for ring = 1, FARM.peakRings do
		local slices = ring * 3
		for slice = 0, slices - 1 do
			local ang = slice / slices * math.pi * 2
			local r = ring * FARM.peakStep
			farmPeakOffsets[#farmPeakOffsets + 1] = Vector2.new(math.cos(ang) * r, math.sin(ang) * r)
		end
	end
end

local function mountainCenter()
	local cx = workspace:GetAttribute("MountainCenterX")
	local cz = workspace:GetAttribute("MountainCenterZ")
	if typeof(cx) == "number" and typeof(cz) == "number" then
		local base = workspace:GetAttribute("MountainBaseY")
		local peak = workspace:GetAttribute("MountainPeakY")
		local y = 700
		if typeof(base) == "number" and typeof(peak) == "number" then
			y = base + (peak - base) * 0.55
		end
		return Vector3.new(cx, y, cz)
	end
	return findTerrainPeak()
end

local function mountainRadius()
	local r = workspace:GetAttribute("MountainRadius")
	if typeof(r) == "number" and r > 20 then
		return r
	end
	return 150
end

local function zoneBaseY()
	local b = workspace:GetAttribute("MountainBaseY")
	return typeof(b) == "number" and b or 0
end

local function zonePeakY()
	local p = workspace:GetAttribute("MountainPeakY")
	return typeof(p) == "number" and p or (zoneBaseY() + 900)
end

local function insideMountainZone(x, z)
	local c = mountainCenter()
	if not c then
		return true
	end
	return (Vector2.new(x, z) - Vector2.new(c.X, c.Z)).Magnitude <= mountainRadius() + FARM.zonePad
end

local surfaceParams = RaycastParams.new()
surfaceParams.FilterType = Enum.RaycastFilterType.Include
surfaceParams.FilterDescendantsInstances = { workspace.Terrain }
surfaceParams.IgnoreWater = true

local function surfaceAt(x, z)
	if not insideMountainZone(x, z) then
		return nil
	end
	local base = zoneBaseY()
	local top = zonePeakY() + 120
	local hit = workspace:Raycast(
		Vector3.new(x, top, z),
		Vector3.new(0, -(top - base + 60), 0),
		surfaceParams
	)
	if not hit or hit.Position.Y <= base + 1 then
		return nil
	end
	if ZoneCheck then
		if ZoneCheck.isInNoDiggingZone and ZoneCheck.isInNoDiggingZone(hit.Position) then
			return nil
		end
		if ZoneCheck.isInMountainZone and not ZoneCheck.isInMountainZone(hit.Position) then
			return nil
		end
	end
	return hit.Position
end

local function highestColumn(origin, offsets)
	local best
	for _, off in ipairs(offsets) do
		local spot = surfaceAt(origin.X + off.X, origin.Z + off.Y)
		if spot and (not best or spot.Y > best.Y) then
			best = spot
		end
	end
	return best
end

local function farmDigBurst(toolName, spot)
	if not toolName or not spot then
		return false
	end
	local ok = false
	for step = 0, FARM.digBurst - 1 do
		if fireDig(toolName, spot - Vector3.new(0, step * FARM.digSink, 0)) then
			ok = true
		end
	end
	return ok
end

local function holdAbove(spot)
	local hrp = getHRP()
	if not hrp or not spot then
		return false
	end
	local goal = spot + Vector3.new(0, FARM.digLift, 0)
	if (hrp.Position - goal).Magnitude > 8 then
		return steppedTeleport(goal, 0)
	end
	local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
	softSetCFrame(hrp, hum, CFrame.new(goal, spot))
	return true
end

local function stopAutoFarm()
	state.autoFarm = false
	state.autoFarmStatus = "Idle"
end

local function startAutoFarm()
	if state.autoFarmThread then
		return
	end
	state.autoFarmThread = task.spawn(function()
		local target, columnY
		local columnDry, columnSwings = 0, 0
		local surfaceClock, peakClock, swingClock = 0, 0, 0
		local loaded = false

		Library:Notify({
			Title = "Auto Farm",
			Description = "Peak → dig down (Donnie money farm)",
			Time = 3,
		})
		state.autoFarmStatus = "Starting"

		-- load: TP peak once
		local peak = mountainCenter() or findTerrainPeak()
		if peak then
			state.autoFarmStatus = "Loading peak"
			steppedTeleport(peak + Vector3.new(0, FARM.digLift, 0), 0)
			task.wait(0.4)
			loaded = true
		end

		while state.autoFarm and not Library.Unloaded do
			local hrp = getHRP()
			if not hrp then
				state.autoFarmStatus = "Waiting character"
				task.wait(0.3)
			elseif state.autoSell and bagNearFull() then
				state.autoFarmStatus = "Selling"
				doSellAll()
				task.wait(1)
				target, columnY, columnDry = nil, nil, 0
			else
				-- dig only — vacuum crystals via Auto Pickup toggle
				local tool = getEquippedPickaxe()
				if not tool then
					state.autoFarmStatus = "No pickaxe"
					task.wait(0.5)
				else
					local now = os.clock()
					local gap = math.max(0.02, digCooldown(tool.Name) * 0.4)
					local origin = hrp.Position
					local center = mountainCenter()
					if center and insideMountainZone(origin.X, origin.Z) then
						origin = origin
					elseif center then
						origin = center
					end

					-- refresh surface under current column
					if target and now - surfaceClock >= FARM.surfaceGap then
						surfaceClock = now
						local spot = surfaceAt(target.X, target.Z)
						if not spot then
							target, columnY, columnDry, columnSwings = nil, nil, 0, 0
						else
							if not columnY or spot.Y < columnY - 0.05 then
								columnDry = 0
							else
								columnDry += columnSwings
							end
							columnSwings = 0
							columnY = spot.Y
							target = spot
							if columnDry >= FARM.columnDry then
								target, columnY, columnDry = nil, nil, 0
							end
						end
					end

					-- pick new highest column
					if not target then
						local spot
						if center and now - peakClock >= FARM.peakGap then
							peakClock = now
							spot = highestColumn(center, farmPeakOffsets)
						end
						if not spot then
							spot = highestColumn(origin, farmOffsets)
						end
						if not spot and center then
							spot = highestColumn(center, farmPeakOffsets)
						end
						if not spot then
							spot = surfaceAt(origin.X, origin.Z)
						end
						if not spot then
							state.autoFarmStatus = "Loading terrain"
							if center then
								pcall(steppedTeleport, center + Vector3.new(0, FARM.digLift, 0), 0)
							end
							-- dig below feet while loading
							if now - swingClock >= gap then
								swingClock = now
								farmDigBurst(tool.Name, hrp.Position - Vector3.new(0, FARM.digReach * 0.5, 0))
							end
							task.wait(0.08)
						else
							target = spot
							columnY = spot.Y
							columnDry, columnSwings = 0, 0
							surfaceClock = now
						end
					end

					if target then
						holdAbove(target)
						if now - swingClock >= gap then
							swingClock = now
							columnSwings += 1
							farmDigBurst(tool.Name, target)
						end
						state.autoFarmStatus = string.format("Mining surface %dm", math.floor(target.Y))
						task.wait(0.03)
					end
				end
			end
		end

		state.autoFarmThread = nil
		state.autoFarmStatus = "Idle"
		Library:Notify({ Title = "Auto Farm", Description = "Stopped", Time = 2 })
	end)
end

--========================================================
-- ESP (Donnie-style billboard + size class)
--========================================================
local ESP_STYLE = {
	font = Enum.Font.GothamBold,
	offset = Vector3.new(0, 3, 0),
	width = 250,
	height = 72, -- 4 lines: title, money·kg, dist·luck, size
	text = 16,
	scale = 0.75,
	hexDist = "00E5FF",
	hexLuck = "FFC400",
	hexSize = "FFAA40",
	money = Color3.fromRGB(60, 255, 90),
	extra = Color3.fromRGB(255, 255, 255),
	stroke = Color3.fromRGB(0, 0, 0),
}
pcall(function()
	ESP_STYLE.font = Enum.Font.LuckiestGuy
end)

local function espGuiSize()
	return UDim2.fromOffset(ESP_STYLE.width * ESP_STYLE.scale, ESP_STYLE.height * ESP_STYLE.scale)
end

local function espTextSize()
	return math.max(8, math.floor(ESP_STYLE.text * ESP_STYLE.scale + 0.5))
end

local function espNewLabel(name, parent, order, total, color, rich, maxText)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = UDim2.new(1, 0, 1 / total, 0)
	label.Position = UDim2.new(0, 0, order / total, 0)
	label.Font = ESP_STYLE.font
	label.TextScaled = true
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = ESP_STYLE.stroke
	label.TextColor3 = color
	label.RichText = rich == true
	label.Text = ""
	label.Parent = parent
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxText
	constraint.Parent = label
	return label, constraint
end

local function formatDistESP(studs)
	studs = tonumber(studs) or 0
	if studs >= 1000 then
		return string.format("%.1fkm", studs / 1000)
	end
	return string.format("%dm", math.floor(studs + 0.5))
end

local function formatKgESP(kg)
	kg = tonumber(kg) or 0
	if kg >= 1000 then
		return string.format("%.1fk kg", kg / 1000)
	end
	return string.format("%.1fkg", kg)
end

local function clearESP()
	for part, entry in pairs(state.highlights) do
		if type(entry) == "table" then
			pcall(function()
				if entry.hl then
					entry.hl:Destroy()
				end
				if entry.gui then
					entry.gui:Destroy()
				end
			end)
		else
			-- legacy Highlight-only
			pcall(function()
				entry:Destroy()
			end)
			if part and part.Parent then
				local bb = part:FindFirstChild("MaM_SizeESP") or part:FindFirstChild("MaM_CrystalESP")
				if bb then
					pcall(function()
						bb:Destroy()
					end)
				end
			end
		end
		state.highlights[part] = nil
	end
end

local function applyESP()
	clearESP()
	if not state.esp then
		return
	end
	local tier = state.listTier
	local minSize = state.listMinSize or 1
	local hrp = getHRP()
	local origin = hrp and hrp.Position
	local textSize = espTextSize()
	local guiSize = espGuiSize()

	iterCrystals(function(part)
		if (part:GetAttribute("Tier") or 0) ~= tier then
			return
		end
		if not meetsMinSize(part, minSize) then
			return
		end
		if state.highlights[part] then
			return
		end

		local sizeCode, sizeName = crystalSize(part)
		local kg = tonumber(part:GetAttribute("WeightKg")) or 0
		local cname = part:GetAttribute("CrystalName") or part.Name
		local val = tonumber(part:GetAttribute("Value")) or 0
		local mut = part:GetAttribute("Mutation")
		local luckStr = crystalLuckText(part)
		local color = part:GetAttribute("TierColorR")
				and Color3.fromRGB(
					tonumber(part:GetAttribute("TierColorR")) or 200,
					tonumber(part:GetAttribute("TierColorG")) or 200,
					tonumber(part:GetAttribute("TierColorB")) or 200
				)
			or (TIER_COLORS[tier] or Color3.fromRGB(0, 225, 255))
		local rarityName = TIER_NAMES[tier] or "?"
		local title
		if type(mut) == "string" and mut ~= "" then
			title = string.format("[%s] %s (%s)", rarityName, tostring(cname), mut)
		else
			title = string.format("[%s] %s", rarityName, tostring(cname))
		end
		local distText = origin and formatDistESP((part.Position - origin).Magnitude) or "--"

		local hl = Instance.new("Highlight")
		hl.Name = "MaM_ESP"
		hl.Adornee = part
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.FillColor = color
		hl.OutlineColor = color
		hl.FillTransparency = 0.7
		hl.OutlineTransparency = 0.15
		hl.Parent = part

		-- Donnie 4-line billboard (no box background — stroke only)
		local bb = Instance.new("BillboardGui")
		bb.Name = "MaM_CrystalESP"
		bb.Adornee = part
		bb.AlwaysOnTop = true
		bb.ResetOnSpawn = false
		bb.LightInfluence = 0
		bb.Size = guiSize
		bb.StudsOffsetWorldSpace = ESP_STYLE.offset
		bb.MaxDistance = math.huge
		bb.Parent = part

		local lineTitle = espNewLabel("Title", bb, 0, 4, color, false, textSize)
		local lineMoney = espNewLabel("Money", bb, 1, 4, ESP_STYLE.money, false, textSize)
		local lineExtra = espNewLabel("Extra", bb, 2, 4, ESP_STYLE.extra, true, textSize)
		local lineSize = espNewLabel("Size", bb, 3, 4, Color3.fromRGB(255, 170, 64), false, textSize)

		lineTitle.Text = title
		lineMoney.Text = string.format("%s  ·  %s", formatMoney(val), formatKgESP(kg))
		lineExtra.Text = string.format(
			'<font color="#%s">%s</font>  ·  <font color="#%s">%s</font>',
			ESP_STYLE.hexDist,
			distText,
			ESP_STYLE.hexLuck,
			luckStr
		)
		lineSize.Text = string.format("[%s] %s", sizeCode, sizeName or sizeCode)

		state.highlights[part] = { hl = hl, gui = bb }
		hl.Destroying:Connect(function()
			pcall(function()
				bb:Destroy()
			end)
		end)
	end)
end

local function clearCharESP()
	for player, bb in pairs(state.charEspBillboards) do
		pcall(function()
			bb:Destroy()
		end)
		state.charEspBillboards[player] = nil
	end
end

local function applyCharESP()
	clearCharESP()
	if not state.charEsp then
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LP then
			local char = player.Character
			local target = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
			if target then
				local bb = Instance.new("BillboardGui")
				bb.Name = "MaM_CharESP"
				bb.Adornee = target
				bb.Size = UDim2.fromOffset(160, 40)
				bb.StudsOffset = Vector3.new(0, 2.5, 0)
				bb.AlwaysOnTop = true
				bb.LightInfluence = 0
				bb.MaxDistance = 500
				local bg = Instance.new("Frame")
				bg.Size = UDim2.fromScale(1, 1)
				bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
				bg.BackgroundTransparency = 0.5
				bg.BorderSizePixel = 0
				bg.Parent = bb
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0, 4)
				corner.Parent = bg
				local label = Instance.new("TextLabel")
				label.Size = UDim2.fromScale(1, 1)
				label.BackgroundTransparency = 1
				label.Font = Enum.Font.GothamBold
				label.TextSize = 13
				label.TextColor3 = Color3.fromRGB(125, 85, 255)
				label.TextStrokeTransparency = 0.5
				label.Text = player.DisplayName
				label.Parent = bg
				bb.Parent = LP:FindFirstChild("PlayerGui") or game:GetService("CoreGui")
				state.charEspBillboards[player] = bb
			end
		end
	end
end

local function updateCharESP()
	if not state.charEsp then
		return
	end
	local hrp = getHRP()
	if not hrp then
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LP then
			local bb = state.charEspBillboards[player]
			local char = player.Character
			local target = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
			if bb and target then
				local dist = math.floor((target.Position - hrp.Position).Magnitude)
				local label = bb:FindFirstChild("Frame") and bb.Frame:FindFirstChildOfClass("TextLabel")
				if label then
					label.Text = string.format("%s [%dm]", player.DisplayName, dist)
				end
			elseif bb and not target then
				pcall(function()
					bb:Destroy()
				end)
				state.charEspBillboards[player] = nil
			end
		end
	end
end

--========================================================
-- CRYSTAL / RUNE LIST
--========================================================
local LIST_HEIGHT = (Library.IsMobile == true) and 160 or 200
local ROW_H = 26
local crystalScroll, crystalEmpty

local function buildCrystalListUI()
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "CrystalListScroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.ScrollBarThickness = 4
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 3)
	layout.Parent = scroll
	local empty = Instance.new("TextLabel")
	empty.Name = "Empty"
	empty.BackgroundTransparency = 1
	empty.Size = UDim2.new(1, 0, 0, 28)
	empty.Font = Enum.Font.Gotham
	empty.TextSize = 12
	empty.TextColor3 = Color3.fromRGB(160, 160, 170)
	empty.Text = "No crystals — Refresh"
	empty.TextXAlignment = Enum.TextXAlignment.Left
	empty.Visible = false
	empty.Parent = scroll
	return scroll, empty
end

local function clearListRows()
	if not crystalScroll then
		return
	end
	for _, ch in ipairs(crystalScroll:GetChildren()) do
		if ch:IsA("TextButton") then
			ch:Destroy()
		end
	end
end

local function collectByExactTier(tier, limit)
	local hrp = getHRP()
	local rows = {}
	local minSize = state.listMinSize or 1
	iterCrystals(function(part)
		if (part:GetAttribute("Tier") or 0) == tier then
			if not meetsMinSize(part, minSize) then
				return
			end
			local dropped = isDroppedCrystal(part)
			local ok, luck = pcall(crystalLuckValue, part)
			local sizeCode, sizeName = crystalSize(part)
			table.insert(rows, {
				part = part,
				value = tonumber(part:GetAttribute("Value")) or 0,
				luck = (ok and type(luck) == "number") and luck or 0,
				dropped = dropped,
				sizeCode = sizeCode,
				sizeName = sizeName,
			})
		end
	end)
	if state.listSortBy == "luck" then
		table.sort(rows, function(a, b)
			if a.luck ~= b.luck then
				return a.luck > b.luck
			end
			return a.value > b.value
		end)
	else
		table.sort(rows, function(a, b)
			return a.value > b.value
		end)
	end
	local out = {}
	local n = math.min(limit or 20, #rows)
	for i = 1, n do
		local part = rows[i].part
		local tierN = part:GetAttribute("Tier") or 1
		local dropped = rows[i].dropped
		local baseName = part:GetAttribute("CrystalName") or part.Name
		table.insert(out, {
			part = part,
			tier = tierN,
			badge = TIER_BADGE[tierN] or "?",
			name = dropped and ("[DROP] " .. baseName) or baseName,
			kg = part:GetAttribute("WeightKg") or 0,
			value = part:GetAttribute("Value") or 0,
			dist = hrp and math.floor((part.Position - hrp.Position).Magnitude) or 0,
			color = TIER_COLORS[tierN] or Color3.new(1, 1, 1),
			dropped = dropped,
			sizeCode = rows[i].sizeCode or "S",
		})
	end
	return out
end

local function refreshCrystalList()
	local rows = collectByExactTier(state.listTier, 20)
	clearListRows()
	if crystalEmpty then
		crystalEmpty.Visible = #rows == 0
	end
	for i, row in ipairs(rows) do
		local btn = Instance.new("TextButton")
		btn.LayoutOrder = i
		btn.Size = UDim2.new(1, 0, 0, ROW_H)
		btn.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = true
		btn.Text = ""
		btn.Parent = crystalScroll
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = btn
		local stroke = Instance.new("UIStroke")
		stroke.Color = row.color
		stroke.Thickness = 1
		stroke.Transparency = 0.35
		stroke.Parent = btn
		local badge = Instance.new("TextLabel")
		badge.BackgroundColor3 = row.color
		badge.BackgroundTransparency = 0.15
		badge.Size = UDim2.fromOffset(20, 18)
		badge.Position = UDim2.fromOffset(4, 4)
		badge.Font = Enum.Font.GothamBold
		badge.TextSize = 11
		badge.TextColor3 = Color3.new(1, 1, 1)
		badge.Text = row.dropped and "DROP" or row.badge
		badge.Parent = btn
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 3)
		bc.Parent = badge
		local info = Instance.new("TextLabel")
		info.BackgroundTransparency = 1
		info.Position = UDim2.fromOffset(28, 0)
		info.Size = UDim2.new(1, -130, 1, 0)
		info.Font = Enum.Font.Gotham
		info.TextSize = 12
		info.TextColor3 = row.dropped and Color3.fromRGB(255, 210, 140) or Color3.fromRGB(230, 230, 235)
		info.TextXAlignment = Enum.TextXAlignment.Left
		info.TextTruncate = Enum.TextTruncate.AtEnd
		local luckStr = crystalLuckText(row.part)
		local nameOnly = row.name:gsub("^%[DROP%]%s*", "")
		info.Text = string.format("[%s] %s  %.1fkg  %s", row.sizeCode or "S", nameOnly, row.kg, luckStr)
		info.Parent = btn
		local money = Instance.new("TextLabel")
		money.BackgroundTransparency = 1
		money.AnchorPoint = Vector2.new(1, 0)
		money.Position = UDim2.new(1, -52, 0, 0)
		money.Size = UDim2.fromOffset(70, ROW_H)
		money.Font = Enum.Font.GothamMedium
		money.TextSize = 11
		money.TextColor3 = Color3.fromRGB(140, 220, 160)
		money.TextXAlignment = Enum.TextXAlignment.Right
		money.Text = formatMoney(row.value)
		money.Parent = btn
		local dist = Instance.new("TextLabel")
		dist.BackgroundTransparency = 1
		dist.AnchorPoint = Vector2.new(1, 0)
		dist.Position = UDim2.new(1, -4, 0, 0)
		dist.Size = UDim2.fromOffset(44, ROW_H)
		dist.Font = Enum.Font.Gotham
		dist.TextSize = 11
		dist.TextColor3 = Color3.fromRGB(160, 160, 175)
		dist.TextXAlignment = Enum.TextXAlignment.Right
		dist.Text = row.dist .. "m"
		dist.Parent = btn
		local part = row.part
		btn.MouseButton1Click:Connect(function()
			teleportTo(part)
		end)
	end
	if state.esp then
		applyESP()
	end
	return #rows
end

--========================================================
-- CHARACTER PROTECTIONS
--========================================================
local function startGodmode()
	if state.godmodeThread then return end
	state.godmodeThread = task.spawn(function()
		while state.godmode and not Library.Unloaded do
			local char = LP.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then
				pcall(function()
					hum.MaxHealth = math.huge
					hum.Health = hum.MaxHealth
					hum.BreakJointsOnDeath = false
				end)
			end
			task.wait(0.3)
		end
		state.godmodeThread = nil
	end)
end

local function stopGodmode()
	state.godmode = false
end

local function applyNoFallDmg()
	if state.noFallConn then
		state.noFallConn:Disconnect()
		state.noFallConn = nil
	end
	local function hook(char)
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		state.noFallConn = hum.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.FallingDown or new == Enum.HumanoidStateType.Dead then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hrp then
					hrp.AssemblyLinearVelocity = Vector3.new(0, -20, 0)
				end
			end
		end)
	end
	local char = LP.Character
	if char then
		hook(char)
	end
	LP.CharacterAdded:Connect(function(char)
		task.wait(0.3)
		if state.noFallDmg then
			hook(char)
		end
	end)
end

local function applyAntiRagdoll()
	if state.ragdollConn then
		state.ragdollConn:Disconnect()
		state.ragdollConn = nil
	end
	local function hook(char)
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		state.ragdollConn = hum.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Ragdoll then
				task.wait(0.05)
				pcall(function()
					hum:ChangeState(Enum.HumanoidStateType.GettingUp)
				end)
			end
		end)
	end
	local char = LP.Character
	if char then
		hook(char)
	end
	LP.CharacterAdded:Connect(function(char)
		task.wait(0.3)
		if state.antiRagdoll then
			hook(char)
		end
	end)
end

--========================================================
-- WINDOW + MAIN TAB UI
--========================================================
local isMobile = Library.IsMobile == true
	or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
local WIN_W = isMobile and 400 or 520
local WIN_H = isMobile and 340 or 440

local Window = Library:CreateWindow({
	Title = "Qentury Hub",
	Footer = "rebuild · Main",
	NotifySide = "Right",
	ShowCustomCursor = false,
	Resizable = true,
	Center = true,
	AutoShow = true,
	Size = UDim2.fromOffset(WIN_W, WIN_H),
	MobileButtonsSide = "Right",
})

pcall(function()
	if Library.SetDPIScale then
		Library:SetDPIScale(isMobile and 80 or 90)
	end
end)

local Tabs = {
	Main = Window:AddTab("Main", "gem", "Auto mine + ESP + TP"),
	Settings = Window:AddTab("Settings", "settings", "UI"),
}

local Main = Tabs.Main:AddLeftGroupbox("Main", "gem")

-- full-width left column (Obsidian default is half)
local function forceFullWidthTabs()
	local root = Library.ScreenGui
	if not root then
		return
	end
	for _, parent in ipairs(root:GetDescendants()) do
		local halves = {}
		for _, ch in ipairs(parent:GetChildren()) do
			if ch:IsA("ScrollingFrame") then
				local sx = ch.Size.X.Scale
				if sx > 0.4 and sx < 0.6 then
					table.insert(halves, ch)
				end
			end
		end
		if #halves >= 2 then
			table.sort(halves, function(a, b)
				return a.AbsoluteSize.X > b.AbsoluteSize.X
			end)
			local left = halves[1]
			for _, h in ipairs(halves) do
				if #h:GetChildren() >= #left:GetChildren() then
					left = h
				end
			end
			for _, h in ipairs(halves) do
				if h == left then
					h.Visible = true
					h.Size = UDim2.new(1, -6, 1, 0)
					h.Position = UDim2.fromScale(0, 0)
				else
					h.Visible = false
					h.Size = UDim2.new(0, 0, 1, 0)
				end
			end
		end
	end
end

task.spawn(function()
	for _ = 1, 20 do
		task.wait(0.25)
		if Library.Unloaded then
			break
		end
		forceFullWidthTabs()
	end
	while not Library.Unloaded do
		task.wait(1)
		forceFullWidthTabs()
	end
end)

-- --- Main controls (from qentury v4.2.3 Main tab) ---
Main:AddToggle("AutoMineV2", {
	Text = "Auto Pickup (mine+drop)",
	Default = false,
	Tooltip = "Donnie-style burst grab: HoldComplete + fireprox MaxDist 1000. Bag free-check. No TP.",
	Callback = function(v)
		state.autoMineV2 = v
		if v then
			startAutoMineV2()
			Library:Notify({ Title = "Auto Pickup", Description = "ON", Time = 2 })
		else
			stopAutoMineV2()
			Library:Notify({ Title = "Auto Pickup", Description = "OFF", Time = 2 })
		end
	end,
})

Main:AddToggle("AutoMineTPV2", {
	Text = "Auto Pickup TP (mine+drop)",
	Default = false,
	Tooltip = "Vacuum near → TP richest Value$ → instant mine.",
	Callback = function(v)
		state.autoMineTPV2 = v
		if v then
			startAutoMineTPV2()
			Library:Notify({ Title = "Auto Pickup TP", Description = "ON", Time = 2 })
		else
			stopAutoMineTPV2()
			Library:Notify({ Title = "Auto Pickup TP", Description = "OFF", Time = 2 })
		end
	end,
})

Main:AddToggle("InstantPrompt", {
	Text = "Instant Prompt (hold=0)",
	Default = false,
	Tooltip = "Nearby crystal prompts HoldDuration=0. Press E = grab nearest. Same fire path as Auto Pickup.",
	Callback = function(v)
		setInstantPrompt(v)
		Library:Notify({
			Title = "Instant Prompt",
			Description = v and "ON — E grab nearest" or "OFF",
			Time = 2,
		})
	end,
})

Main:AddToggle("AutoFarm", {
	Text = "Auto Farm (peak dig)",
	Default = false,
	Tooltip = "Peak → dig highest column down. Vacuum = pakai Auto Pickup. Auto-Sell jika ON.",
	Callback = function(v)
		if v then
			state.autoFarm = true
			startAutoFarm()
			Library:Notify({ Title = "Auto Farm", Description = "ON — peak → dig down", Time = 2 })
		else
			stopAutoFarm()
			if state.autoFarmThread then
				pcall(task.cancel, state.autoFarmThread)
				state.autoFarmThread = nil
			end
			Library:Notify({ Title = "Auto Farm", Description = "OFF", Time = 2 })
		end
	end,
})

Main:AddLabel("FarmStatus", {
	Text = "Farm: Idle",
	DoesWrap = true,
})

task.spawn(function()
	while not Library.Unloaded do
		task.wait(0.25)
		pcall(function()
			if Options.FarmStatus and Options.FarmStatus.SetText then
				Options.FarmStatus:SetText("Farm: " .. (state.autoFarmStatus or "Idle"))
			end
		end)
	end
end)

Main:AddDropdown("MineMinRarity", {
	Text = "Min Rarity (Auto-Mine)",
	Values = TIER_LABELS,
	Default = 1,
	Multi = false,
	Callback = function(v)
		state.mineMinTier = rarityToTier(v)
	end,
})

Main:AddDropdown("MineMinSize", {
	Text = "Min Size (Auto-Mine)",
	Values = SIZE_LABELS,
	Default = 1,
	Multi = false,
	Tooltip = "Filter pickup only. S<8kg · M≥8 · L≥30 · XL≥90 · …",
	Callback = function(v)
		state.mineMinSize = sizeLabelToRank(v)
	end,
})

Main:AddLabel("Must stand near crystal for Auto Pickup (no TP).")

Main:AddToggle("AutoSell", {
	Text = "Auto-Sell (At Capacity)",
	Default = false,
	Tooltip = "When bag kg >= % capacity → sell zone → SellRequest all.",
	Callback = function(v)
		state.autoSell = v
		if v then
			startAutoSell()
		else
			stopAutoSell()
		end
	end,
})

Main:AddSlider("SellAtPct", {
	Text = "Sell when full %",
	Default = 95,
	Min = 50,
	Max = 100,
	Rounding = 0,
	Callback = function(v)
		state.sellAtPct = v
	end,
})

Main:AddButton({
	Text = "Sell All Now",
	Func = function()
		local ok, info = doSellAll()
		Library:Notify({
			Title = ok and "Sold" or "Sell failed",
			Description = ok
					and string.format("Sold %s · +%s", tostring(info.sold), formatMoney(info.cashDelta or 0))
				or tostring(info),
			Time = 3,
		})
	end,
})

Main:AddButton({
	Text = "TP Peak (stepped)",
	Func = function()
		task.spawn(teleportToPeak)
	end,
})

Main:AddDivider("Character")

Main:AddToggle("Godmode", {
	Text = "Godmode (loop health)",
	Default = false,
	Tooltip = "Set MaxHealth = huge, loop heal every 0.3s.",
	Callback = function(v)
		state.godmode = v
		if v then
			startGodmode()
			Library:Notify({ Title = "Godmode", Description = "ON", Time = 2 })
		else
			stopGodmode()
			Library:Notify({ Title = "Godmode", Description = "OFF", Time = 2 })
		end
	end,
})

Main:AddToggle("NoFallDmg", {
	Text = "No Fall Damage",
	Default = false,
	Tooltip = "Catch FallingDown state, reset velocity.",
	Callback = function(v)
		state.noFallDmg = v
		if v then
			applyNoFallDmg()
			Library:Notify({ Title = "No Fall Dmg", Description = "ON", Time = 2 })
		elseif state.noFallConn then
			state.noFallConn:Disconnect()
			state.noFallConn = nil
			Library:Notify({ Title = "No Fall Dmg", Description = "OFF", Time = 2 })
		end
	end,
})

Main:AddToggle("AntiRagdoll", {
	Text = "Anti Ragdoll",
	Default = false,
	Tooltip = "Force GettingUp when Ragdoll state detected.",
	Callback = function(v)
		state.antiRagdoll = v
		if v then
			applyAntiRagdoll()
			Library:Notify({ Title = "Anti Ragdoll", Description = "ON", Time = 2 })
		elseif state.ragdollConn then
			state.ragdollConn:Disconnect()
			state.ragdollConn = nil
			Library:Notify({ Title = "Anti Ragdoll", Description = "OFF", Time = 2 })
		end
	end,
})

Main:AddDivider()

Main:AddToggle("CharESP", {
	Text = "Player ESP (name + dist)",
	Default = false,
	Callback = function(v)
		state.charEsp = v
		if v then
			applyCharESP()
			task.spawn(function()
				while state.charEsp and not Library.Unloaded do
					updateCharESP()
					task.wait(0.5)
				end
			end)
		else
			clearCharESP()
		end
	end,
})

Main:AddToggle("CrystalESP", {
	Text = "Crystal ESP",
	Default = false,
	Tooltip = "Donnie-style label: rarity · name · $ · kg · dist · luck · size. Filter = Rarity + Min Size.",
	Callback = function(v)
		state.esp = v
		if v then
			applyESP()
			task.spawn(function()
				while state.esp and not Library.Unloaded do
					applyESP()
					task.wait(1.2)
				end
			end)
		else
			clearESP()
		end
	end,
})

Main:AddSlider("EspScale", {
	Text = "ESP text scale",
	Default = 75,
	Min = 50,
	Max = 120,
	Rounding = 0,
	Suffix = "%",
	Tooltip = "Ukuran font ESP (Donnie default ~75%).",
	Callback = function(v)
		ESP_STYLE.scale = math.clamp((tonumber(v) or 75) / 100, 0.45, 1.4)
		if state.esp then
			applyESP()
		end
	end,
})

Main:AddDropdown("ListRarity", {
	Text = "Rarity (ESP + List)",
	Values = TIER_LABELS,
	Default = 5,
	Multi = false,
	Callback = function(v)
		state.listTier = rarityToTier(v)
		local n = refreshCrystalList()
		if state.esp then
			applyESP()
		end
		Library:Notify({
			Title = "Rarity",
			Description = string.format("%s · top %d", TIER_NAMES[state.listTier] or v, math.min(n, 20)),
			Time = 2,
		})
	end,
})

Main:AddDropdown("EspMinSize", {
	Text = "Min Size (ESP + List)",
	Values = SIZE_LABELS,
	Default = 1,
	Multi = false,
	Tooltip = "Hanya tampilkan crystal size ≥ ini di ESP & list. S/M/L/XL/…",
	Callback = function(v)
		state.listMinSize = sizeLabelToRank(v)
		if state.esp then
			applyESP()
		end
		refreshCrystalList()
	end,
})

Main:AddDropdown("ListSortBy", {
	Text = "Sort Crystal List",
	Values = { "Money ($)", "Luck (%)" },
	Default = 1,
	Multi = false,
	Callback = function(v)
		state.listSortBy = (v == "Luck (%)") and "luck" or "money"
		refreshCrystalList()
	end,
})

Main:AddLabel("Crystal list (Top 20) — click = TP")

crystalScroll, crystalEmpty = buildCrystalListUI()
Main:AddUIPassthrough("CrystalListUI", {
	Instance = crystalScroll,
	Height = LIST_HEIGHT,
})

Main:AddButton({
	Text = "Refresh List / ESP",
	Func = function()
		local n = refreshCrystalList()
		Library:Notify({
			Title = "Refreshed",
			Description = string.format("%d items (tier %s)", n, TIER_BADGE[state.listTier] or "?"),
			Time = 2,
		})
	end,
})

--========================================================
-- SETTINGS (minimal)
--========================================================
local Menu = Tabs.Settings:AddLeftGroupbox("Menu", "wrench")
Menu:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
	Default = "RightShift",
	NoUI = true,
	Text = "Menu keybind",
})
Menu:AddButton("Unload", function()
	Library:Unload()
end)
Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("QenturyHub")
SaveManager:SetFolder("QenturyHub/MineAMountainRebuild")

do
	local tab = Tabs.Settings
	local origRight = tab.AddRightGroupbox
	if type(origRight) == "function" then
		tab.AddRightGroupbox = function(self, name, icon)
			return self:AddLeftGroupbox(name, icon)
		end
	end
	SaveManager:BuildConfigSection(Tabs.Settings)
	if type(origRight) == "function" then
		tab.AddRightGroupbox = origRight
	end
end

if ThemeManager.ApplyToTab then
	ThemeManager:ApplyToTab(Tabs.Settings)
end

if SaveManager.LoadAutoloadConfig then
	task.defer(function()
		pcall(function()
			SaveManager:LoadAutoloadConfig()
		end)
	end)
end

--========================================================
-- CLEANUP
--========================================================
local function stopFeatures()
	state.autoMineV2 = false
	state.autoMineTPV2 = false
	state.autoFarm = false
	state.autoFarmStatus = "Idle"
	state.autoSell = false
	state.esp = false
	state.charEsp = false
	state.godmode = false
	state.noFallDmg = false
	state.antiRagdoll = false
	setInstantPrompt(false)
	if state.noFallConn then
		state.noFallConn:Disconnect()
		state.noFallConn = nil
	end
	if state.ragdollConn then
		state.ragdollConn:Disconnect()
		state.ragdollConn = nil
	end
	table.clear(promptGrabbed)
	table.clear(promptRestores)
	clearESP()
	clearCharESP()
end

getgenv().QenturyRebuildCleanup = function()
	stopFeatures()
	pcall(function()
		if Library and not Library.Unloaded then
			Library:Unload()
		end
	end)
end

Library:OnUnload(stopFeatures)

task.defer(function()
	task.wait(0.2)
	forceFullWidthTabs()
	state.listTier = rarityToTier(Options.ListRarity and Options.ListRarity.Value) or 5
	state.mineMinTier = rarityToTier(Options.MineMinRarity and Options.MineMinRarity.Value) or 1
	state.mineMinSize = sizeLabelToRank(Options.MineMinSize and Options.MineMinSize.Value) or 1
	state.listMinSize = sizeLabelToRank(Options.EspMinSize and Options.EspMinSize.Value) or 1
	pcall(refreshCrystalList)
	task.spawn(function()
		while not Library.Unloaded do
			task.wait(3)
			pcall(refreshCrystalList)
		end
	end)
end)

Library:Notify({
	Title = "Qentury rebuild",
	Description = "Phase 1 · Main + Settings · Obsidian",
	Time = 4,
})
