--========================================================
-- QENTURY HUB (rebuild)
-- Shells/rebuild/ / UI: deividcomsono Obsidian
-- Phase 1: Main + Shop (Bombs + Radars) + Settings
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
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local LP = Players.LocalPlayer

--========================================================
-- CONSTANTS
--========================================================
local RARITY_MULT = { 1, 1.6, 2.6, 4.2, 7, 12, 216, 480, 600 }
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

local TIER_NAMES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Empyrean", "Pulsar", "Quasar" }
local TIER_BADGE = { "C", "U", "R", "E", "L", "M", "Em", "Pu", "Qu" }
local TIER_LABELS = {
	"C / Common",
	"U / Uncommon",
	"R / Rare",
	"E / Epic",
	"L / Legendary",
	"M / Mythic",
	"Em / Empyrean",
	"Pu / Pulsar",
	"Qu / Quasar",
}
local TIER_COLORS = {
	Color3.fromRGB(200, 200, 200),
	Color3.fromRGB(80, 220, 120),
	Color3.fromRGB(70, 140, 255),
	Color3.fromRGB(170, 90, 255),
	Color3.fromRGB(255, 80, 180),
	Color3.fromRGB(255, 60, 60),
	Color3.fromRGB(255, 225, 150),
	Color3.fromRGB(90, 210, 255),
	Color3.fromRGB(255, 90, 220),
}
local BADGE_TO_TIER = {
	C = 1,
	U = 2,
	R = 3,
	E = 4,
	L = 5,
	M = 6,
	Em = 7,
	Pu = 8,
	Qu = 9,
}
local NAME_TO_TIER = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
	Empyrean = 7,
	Pulsar = 8,
	Quasar = 9,
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
	"S / Small",
	"M / Medium",
	"L / Large",
	"XL / Extra Large",
	"Giant",
	"Colossal",
	"Titan",
	"Leviathan",
	"Behemoth",
}
local SIZE_KG = { 0, 8, 30, 90, 200, 1000, 3000, 8000, 25000 }

-- Donnie Money Farm (peak -> dig down)
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
	-- Main
	autoMineV2 = false,
	autoMineTPV2 = false,
	mineV2Thread = nil,
	mineTPV2Thread = nil,
	esp = false,
	mineMinTier = 1,
	mineMinSize = 1,
	mineMinLuckPct = 1, -- Auto Pickup / TP filter (dropdown)
	mineMinValue = 0, -- Auto Pickup / TP filter, $ (0 = all)
	listTier = 5,
	listMinSize = 1,
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
	tpBusy = false,
	-- Runes
	runeEsp = false,
	runeHighlights = {},
	runeSelected = nil,
	autoPickupRune = false,
	autoTpRune = false,
	runeThread = nil,
	runeTpThread = nil,
	-- Boulders
	boulderEsp = false,
	boulderSelected = nil,
	autoBreak = false,
	pickupAfterBoulder = false, -- after no boulder + no rune: TP-pickup crystals per Main filter
	autoRejoin = false, -- rejoin only after farm clear (no boulder + no rune)
	breakThread = nil,
	_forceBreak = false,
	-- Misc
	godmode = false,
	godmodeThread = nil,
	noFallDmg = false,
	noFallConn = nil,
	antiRagdoll = false,
	ragdollConn = nil,
	fly = false,
	flySpeed = 50,
	flyConn = nil,
	flyBv = nil,
	flyBg = nil,
	speedBoost = false,
	walkSpeed = 32,
	antiAfk = false,
	antiAfkInterval = 120,
	antiAfkThread = nil,
	antiLag = false,
	antiLagThread = nil,
	fxSaved = {},
	antiGlow = false,
	glowThread = nil,
	glowSurfaces = {},
	glowLights = {},
	speedConn = nil,
	noclip = false,
	noclipConn = nil,
	noclipParts = {},
	-- Drop
	dropMode = nil, -- "all" | "value" | nil
	dropThread = nil,
	dropValueTargetB = 1, -- billion $ (slider 1..500)
	dropSortExpensive = false, -- false = cheapest first, true = most expensive first
	dropDelay = 0.15,
	dropStatCount = 0,
	dropStatValue = 0,
	-- Favorite
	autoFavLuck = false,
	autoFavRarity = false,
	autoFavWeight = false,
	favLuckMin = 4,
	favMinWeight = 4,
	favRarityTiers = { [5] = true, [6] = true }, -- L + M default
	favThread = nil,
	-- Shop / Bombs
	autoBuyBomb = false,
	bombTargets = { ClassicBomb = true },
	bombStock = {},
	bombThread = nil,
	-- Shop / Upgrades
	autoUpgradeCarry = false,
	upgradeThread = nil,
	-- Shop / Destroy
	destroyLowRarity = false,
	destroyMaxTier = 6,
	destroyThread = nil,
	-- Drop Rune
	runeDrop = false,
	runeDropSel = nil,
	runeDropCount = 1,
	runeDropThread = nil,
	-- Shop / Radars
	autoBuyRadar = false,
	radarTargets = { CrystalRadar = true },
	radarStock = {},
	radarThread = nil,
	-- Shop / Upgrades
	upgPrices = {}, -- kind -> { [1]=p1, [2]=p2, [3]=p3 }
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
	local two = v:match("^([EPQ][mu])")
	if two and BADGE_TO_TIER[two] then
		return BADGE_TO_TIER[two]
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
	-- "S / Small" / "XL / Extra Large" / "Behemoth"
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
	Library:Notify({ Title = "Peak TP", Description = "Scanning terrain?", Time = 2 })
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
-- PICKUP (1 fire path / Donnie aggressive / Auto + TP)
--========================================================
local HoldComplete -- lazy; remotes may not exist at load

local function getHoldComplete()
	if HoldComplete and HoldComplete.Parent then
		return HoldComplete
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	HoldComplete = remotes and remotes:FindFirstChild("CrystalHoldComplete")
	return HoldComplete
end

local PICK = {
	range = 13,
	pad = 4,
	burst = 8,
	cooldown = 0.04,
	restore = 0.2,
	retry = 0.15,
	forget = 5,
}

local promptRestores = {}
local promptGrabbed = {} -- claim stamps (crystal)
local claimed = promptGrabbed
local lastPickup = 0

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
	task.delay(PICK.restore, function()
		local saved = promptRestores[prompt]
		if not saved then
			return
		end
		promptRestores[prompt] = nil
		if prompt.Parent then
			pcall(function()
				prompt.HoldDuration = saved.hold
				prompt.RequiresLineOfSight = saved.sight
				prompt.Enabled = saved.enabled
				prompt.MaxActivationDistance = saved.range
			end)
		end
	end)
	return fired
end

-- single aggressive grab (no ActionText gate / MaxDist stretch / HoldComplete first)
local function grabCrystal(inst, prompt)
	if not inst or not inst.Parent then
		return false
	end
	local sent = false
	local hold = getHoldComplete()
	if hold then
		sent = pcall(function()
			hold:FireServer(inst)
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
	local minLuckPct = tonumber(state.mineMinLuckPct) or 1
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
		if minLuckPct > 1 then
			local okL, luck = pcall(crystalLuckValue, part)
			local pct = (okL and type(luck) == "number") and (luck * 100) or 0
			if pct < minLuckPct then
				return
			end
		end
		if (tonumber(part:GetAttribute("Value")) or 0) < (state.mineMinValue or 0) then
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
	-- no bag-full stop: keep firing even when over cap
	for inst, stamp in pairs(claimed) do
		if type(stamp) == "number" and (now - stamp >= PICK.forget or not inst or not inst.Parent) then
			claimed[inst] = nil
		end
	end
	local n = 0
	local minTier = state.mineMinTier or 1
	local limit = math.max(1, math.floor(tonumber(state._pickupBurst) or PICK.burst))
	for _, t in ipairs(listMineables(minTier, hrp, PICK.range + PICK.pad)) do
		if n >= limit or Library.Unloaded or (stillOn and not stillOn()) then
			break
		end
		local claim = claimed[t.part]
		if not (claim and now - claim < PICK.retry) then
			claimed[t.part] = now
			if grabCrystal(t.part, t.prompt) then
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
	local prevTier, prevBurst = state.mineMinTier, state._pickupBurst
	if minTier then
		state.mineMinTier = minTier
	end
	if maxCount then
		state._pickupBurst = maxCount
	end
	local n = pickupStep(stillOn)
	state.mineMinTier = prevTier
	state._pickupBurst = prevBurst
	return n
end

local function bagNearFull()
	if not state.autoSell then
		return false
	end
	local cap = getCarryCap()
	return cap > 0 and totalCrystalKg() >= cap * ((state.sellAtPct or 95) / 100)
end

local function mineAlive(flag)
	return state[flag] and not Library.Unloaded
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
			local n = pickupStep(function()
				return state.autoMineV2
			end)
			task.wait(n > 0 and PICK.cooldown or 0.08)
		end
		state.mineV2Thread = nil
	end)
end

local function stopAutoMineTPV2()
	state.autoMineTPV2 = false
end

-- one heavy TP/farm at a time (dig / pickup-TP / rune-TP / boulder)
local function uiSetToggle(name, on)
	pcall(function()
		if Toggles[name] and Toggles[name].SetValue then
			Toggles[name]:SetValue(on)
		end
	end)
end

local function stopHeavyFarms(except)
	-- except: "farm" | "mineTP" | "runeTP" | "boulder" | nil
	if except ~= "farm" and state.autoFarm then
		state.autoFarm = false
		state.autoFarmStatus = "Idle"
		uiSetToggle("AutoFarm", false)
	end
	if except ~= "mineTP" and state.autoMineTPV2 then
		state.autoMineTPV2 = false
		uiSetToggle("AutoMineTPV2", false)
	end
	if except ~= "runeTP" and state.autoTpRune then
		state.autoTpRune = false
		uiSetToggle("AutoTpRune", false)
	end
	if except ~= "boulder" and state.autoBreak then
		state.autoBreak = false
		state._forceBreak = false
		uiSetToggle("AutoFarmBoulder", false)
	end
end

local function startAutoMineTPV2()
	stopHeavyFarms("mineTP")
	state.autoMineTPV2 = true
	-- if previous loop still winding down, just re-arm flag
	if state.mineTPV2Thread then
		return
	end
	state.mineTPV2Thread = task.spawn(function()
		local skip, fails = {}, 0
		local on = function()
			return mineAlive("autoMineTPV2")
		end
		while state.autoMineTPV2 and not Library.Unloaded do
			pickupStep(on)
			local best = listMineables(state.mineMinTier, getHRP(), nil, skip)[1]
			if not best or not best.part.Parent then
				skip, fails = {}, fails + 1
				if fails >= 3 then
					Library:Notify({
						Title = "Auto Pickup TP",
						Description = "No crystals ? tier " .. state.mineMinTier,
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
							"Sold %s / +%s",
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

local function isCrystalTool(tool)
	if not tool or not tool:IsA("Tool") then
		return false
	end
	-- pickaxes also have DisplayName — never use DisplayName alone
	if tool:GetAttribute("IsPickaxe") == true then
		return false
	end
	if tool:GetAttribute("DigPower") ~= nil and tool:GetAttribute("Value") == nil then
		return false
	end
	-- bag crystals: Tier + Value (pickaxes have no Value $)
	if tool:GetAttribute("Tier") ~= nil and tool:GetAttribute("Value") ~= nil then
		return true
	end
	if tool:GetAttribute("CrystalName") ~= nil then
		return true
	end
	return false
end

local function isPickaxeTool(tool)
	if not tool or not tool:IsA("Tool") then
		return false
	end
	-- authoritative attrs first (The Terminus has IsPickaxe=true)
	if tool:GetAttribute("IsPickaxe") == true then
		return true
	end
	if tool:GetAttribute("DigPower") ~= nil and tool:GetAttribute("Value") == nil then
		return true
	end
	if isCrystalTool(tool) then
		return false
	end
	if ToolConfig and ToolConfig.PickaxeNames and ToolConfig.PickaxeNames[tool.Name] then
		return true
	end
	local n = tool.Name
	return n:find("Pick", 1, true) ~= nil
		or n:find("Apex", 1, true) ~= nil
		or n:find("Scrapper", 1, true) ~= nil
		or n:find("Spike", 1, true) ~= nil
		or n:find("Carver", 1, true) ~= nil
		or n:find("Basalt", 1, true) ~= nil
		or n:find("Edge", 1, true) ~= nil
		or n:find("Tempest", 1, true) ~= nil
		or n:find("Terminus", 1, true) ~= nil
		or n:find("Voidreign", 1, true) ~= nil
		or n:find("Singularity", 1, true) ~= nil
		or n:find("Nebular", 1, true) ~= nil
		or n:find("Eclipse", 1, true) ~= nil
		or n:find("Astral", 1, true) ~= nil
		or n:find("Celestial", 1, true) ~= nil
		or n:find("Frostbite", 1, true) ~= nil
		or n:find("Obsidian", 1, true) ~= nil
		or n:find("Titanium", 1, true) ~= nil
		or n:find("Emerald", 1, true) ~= nil
		or n:find("Volcano", 1, true) ~= nil
end

-- held only: player equips themselves (peak dig)
local function getHeldPickaxe()
	local c = LP.Character
	if not c then
		return nil
	end
	local equipped = c:FindFirstChildOfClass("Tool")
	if isPickaxeTool(equipped) then
		return equipped
	end
	return nil
end

-- auto-equip from bag (boulder farm)
local function getEquippedPickaxe()
	local held = getHeldPickaxe()
	if held then
		return held
	end
	local c = LP.Character
	if not c then
		return nil
	end
	local hum = c:FindFirstChildOfClass("Humanoid")
	local equipped = c:FindFirstChildOfClass("Tool")
	-- holding crystal / shovel / junk -> unequip so pickaxe can equip
	if equipped and hum then
		pcall(function()
			hum:UnequipTools()
		end)
		task.wait(0.05)
	end
	local bp = LP:FindFirstChild("Backpack")
	if bp then
		for _, tool in ipairs(bp:GetChildren()) do
			if isPickaxeTool(tool) then
				if hum then
					pcall(function()
						hum:EquipTool(tool)
					end)
					task.wait(0.15)
				end
				local now = c:FindFirstChildOfClass("Tool")
				if isPickaxeTool(now) then
					return now
				end
				return tool
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
-- AUTO FARM (Donnie Money Farm): peak -> dig column down
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
	stopHeavyFarms("farm")
	state.autoFarm = true
	if state.autoFarmThread then
		return
	end
	state.autoFarmThread = task.spawn(function()
		local target, columnY
		local columnDry, columnSwings = 0, 0
		local surfaceClock, peakClock, swingClock = 0, 0, 0
		local loaded = false
		local lastEquipWarn = 0

		Library:Notify({
			Title = "Auto Farm",
			Description = "Peak -> dig down (Donnie money farm)",
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
				-- dig only - vacuum crystals via Auto Pickup toggle
				-- player equips pickaxe themselves (no auto EquipTool)
				local tool = getHeldPickaxe()
				if not tool then
					state.autoFarmStatus = "Equip pickaxe"
					local now = os.clock()
					if now - lastEquipWarn >= 4 then
						lastEquipWarn = now
						Library:Notify({
							Title = "Auto Farm",
							Description = "Equip pickaxe first",
							Time = 2,
						})
					end
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
	height = 72, -- 4 lines: title, money/kg, dist/luck, size
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

		-- Donnie 4-line billboard (no box background - stroke only)
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
		lineMoney.Text = string.format("%s  /  %s", formatMoney(val), formatKgESP(kg))
		lineExtra.Text = string.format(
			'<font color="#%s">%s</font>  /  <font color="#%s">%s</font>',
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
	empty.Text = "No crystals - Refresh"
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
	local rows = collectByExactTier(state.listTier, 10)
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
-- RUNES
--========================================================
local RUNE_RARITY = {
	Luck = 1,
	Haste = 1,
	Storm = 2,
	Weight = 2,
	Fortune = 3,
	Detonation = 3,
	Preservation = 5,
	Warmth = 5,
	Excavator = 6,
	Colossus = 6,
}
local RUNE_NAMES = {
	"Luck",
	"Haste",
	"Storm",
	"Weight",
	"Fortune",
	"Detonation",
	"Preservation",
	"Warmth",
	"Excavator",
	"Colossus",
}
local RUNE_LIST_H = (Library.IsMobile == true) and 160 or 200
local runeScroll

local function getRuneId(part)
	local fromAttr = part:GetAttribute("RuneId") or part:GetAttribute("RuneName")
	if type(fromAttr) == "string" and fromAttr ~= "" then
		return fromAttr:gsub("%s*Rune%s*", ""):gsub("^%s+", ""):gsub("%s+$", "")
	end
	return (part.Name or ""):gsub("%s*Rune%s*", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function runeAllowed(id)
	local sel = state.runeSelected
	if not sel or next(sel) == nil then
		return true
	end
	return sel[id] == true
end

local function syncRuneSelected(value)
	local map = {}
	if type(value) == "table" then
		for a, b in pairs(value) do
			if b == true and type(a) == "string" then
				map[a] = true
			elseif type(b) == "string" then
				map[b] = true
			end
		end
		for _, item in ipairs(value) do
			if type(item) == "string" then
				map[item] = true
			end
		end
	elseif type(value) == "string" and value ~= "" then
		map[value] = true
	end
	state.runeSelected = next(map) == nil and nil or map
	return state.runeSelected
end

local function isPlacedPlotRune(inst)
	if not inst then
		return true
	end
	local p = inst
	while p and p ~= workspace do
		local n = p.Name
		if n == "PlacedRunes" or n == "Plots" or n == "Garden" or n == "Gardens" then
			return true
		end
		if n == "Slots" and p.Parent and p.Parent.Name == "Plots" then
			return true
		end
		p = p.Parent
	end
	return false
end

local function looksLikeRune(inst)
	if not inst then
		return false
	end
	if inst:GetAttribute("RuneId") or inst:GetAttribute("IsRune") or inst:GetAttribute("RuneName") then
		return true
	end
	local n = inst.Name
	return type(n) == "string" and n:find("Rune", 1, true) ~= nil
end

-- lighter than GetDescendants: skip whole plot/garden trees; optional radius bias
local function iterRunes(fn)
	local seen = {}
	local function offer(part)
		if not part or seen[part] or isPlacedPlotRune(part) then
			return
		end
		seen[part] = true
		fn(part)
	end
	local function consider(inst)
		if not inst or seen[inst] then
			return
		end
		if inst:IsA("BasePart") and looksLikeRune(inst) then
			offer(inst)
		elseif inst:IsA("Model") and looksLikeRune(inst) then
			offer(inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true))
		end
	end
	local function walk(parent)
		for _, child in ipairs(parent:GetChildren()) do
			local n = child.Name
			-- skip entire placed-plot / garden subtrees (big win vs GetDescendants)
			if n == "PlacedRunes" or n == "Plots" or n == "Garden" or n == "Gardens" then
				-- no descend
			elseif n == "Slots" and parent.Name == "Plots" then
				-- no descend
			else
				consider(child)
				walk(child)
			end
		end
	end
	walk(workspace)
	-- nearby radius pass (streaming / late parents)
	local hrp = getHRP()
	if hrp then
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { LP.Character or LP }
		pcall(function()
			params.MaxParts = 200
		end)
		local ok, hits = pcall(function()
			return workspace:GetPartBoundsInRadius(hrp.Position, 120, params)
		end)
		if ok and hits then
			for _, part in ipairs(hits) do
				if looksLikeRune(part) then
					offer(part)
				elseif part.Parent and looksLikeRune(part.Parent) then
					offer(part.Parent.PrimaryPart or part)
				end
			end
		end
	end
end

local function clearRuneESP()
	for part, hl in pairs(state.runeHighlights) do
		pcall(function()
			hl:Destroy()
		end)
		state.runeHighlights[part] = nil
	end
end

local function applyRuneESP()
	clearRuneESP()
	if not state.runeEsp then
		return
	end
	iterRunes(function(part)
		local id = getRuneId(part)
		if not runeAllowed(id) or state.runeHighlights[part] then
			return
		end
		local tier = RUNE_RARITY[id] or 1
		local color = TIER_COLORS[tier] or Color3.fromRGB(190, 130, 255)
		local hl = Instance.new("Highlight")
		hl.Name = "MaM_RuneESP"
		hl.Adornee = part
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.FillColor = color
		hl.OutlineColor = color
		hl.FillTransparency = 0.45
		hl.OutlineTransparency = 0.05
		hl.Parent = part
		state.runeHighlights[part] = hl
	end)
end

-- hybrid: donnie fire+dedup+burst / rebuild filter/plot / optional short TP
local RUNE_PICK = {
	range = 30,
	tpBeyond = 18,
	scanRadius = 120,
	burst = 6,
	step = 0.25,
	retry = 0.2,
	forget = 5,
}

local runeGrabbed = {} -- prompt -> stamp

local function fireRunePrompt(part)
	if not part or not part.Parent then
		return 0
	end
	local now = os.clock()
	for prompt, stamp in pairs(runeGrabbed) do
		if type(stamp) ~= "number" or now - stamp >= RUNE_PICK.forget or not prompt or not prompt.Parent then
			runeGrabbed[prompt] = nil
		end
	end
	local n, seen = 0, {}
	local function try(prompt)
		if not prompt or seen[prompt] then
			return
		end
		seen[prompt] = true
		local last = runeGrabbed[prompt]
		if last and now - last < RUNE_PICK.retry then
			return
		end
		runeGrabbed[prompt] = now
		if firePrompt(prompt) then
			n += 1
		end
	end
	if part:IsA("ProximityPrompt") then
		try(part)
	end
	for _, d in ipairs(part:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			try(d)
		end
	end
	local owner = part.Parent
	if owner and owner:IsA("Model") then
		try(owner:FindFirstChildOfClass("ProximityPrompt"))
	end
	return n
end

-- vacuum near; optional short TP only when beyond tpBeyond (Auto Pickup)
-- allowTp=false -> pure donnie vacuum (no TP)
local function pickupNearbyRunes(allowTp)
	local hrp = getHRP()
	if not hrp then
		return 0
	end
	if allowTp == nil then
		allowTp = true
	end
	local origin = hrp.Position
	local candidates = {}
	iterRunes(function(part)
		if not part.Parent or not runeAllowed(getRuneId(part)) then
			return
		end
		local d = (part.Position - origin).Magnitude
		if d > RUNE_PICK.range then
			return
		end
		table.insert(candidates, { part = part, d = d })
	end)
	table.sort(candidates, function(a, b)
		return a.d < b.d
	end)
	local n = 0
	for _, row in ipairs(candidates) do
		if n >= RUNE_PICK.burst or Library.Unloaded then
			break
		end
		local part = row.part
		if part and part.Parent then
			if allowTp and row.d > RUNE_PICK.tpBeyond then
				steppedTeleport(part.Position + Vector3.new(0, 3, 0), 3)
				hrp = getHRP()
				if not hrp then
					break
				end
			end
			n += fireRunePrompt(part)
		end
	end
	return n
end

local function listWorldRunes()
	local hrp = getHRP()
	local rows = {}
	iterRunes(function(part)
		if not part.Parent then
			return
		end
		local id = getRuneId(part)
		if not runeAllowed(id) then
			return
		end
		local tier = RUNE_RARITY[id] or 1
		table.insert(rows, {
			part = part,
			id = id,
			tier = tier,
			dist = hrp and (part.Position - hrp.Position).Magnitude or 0,
			color = TIER_COLORS[tier] or Color3.fromRGB(190, 130, 255),
		})
	end)
	table.sort(rows, function(a, b)
		return a.dist < b.dist
	end)
	return rows
end

local function startAutoPickupRune()
	if state.runeThread then
		return
	end
	state.runeThread = task.spawn(function()
		while state.autoPickupRune and not Library.Unloaded do
			-- vacuum only (no TP); far runes = use Auto TP Rune
			pickupNearbyRunes(false)
			task.wait(RUNE_PICK.step)
		end
		state.runeThread = nil
	end)
end

local function stopAutoTpRune()
	state.autoTpRune = false
end

local function startAutoTpRune()
	stopHeavyFarms("runeTP")
	state.autoTpRune = true
	if state.runeTpThread then
		return
	end
	state.runeTpThread = task.spawn(function()
		while state.autoTpRune and not Library.Unloaded do
			local rows = listWorldRunes()
			if #rows == 0 then
				task.wait(1.5)
			else
				local got = 0
				for _, row in ipairs(rows) do
					if not state.autoTpRune or Library.Unloaded then
						break
					end
					local part = row.part
					if part and part.Parent then
						steppedTeleport(part.Position + Vector3.new(0, 3, 0), 6)
						task.wait(0.12)
						got += fireRunePrompt(part)
						task.wait(0.18)
					end
				end
				if got > 0 then
					Library:Notify({
						Title = "Auto TP Rune",
						Description = "pickup " .. tostring(got) .. " / " .. tostring(#rows) .. " runes",
						Time = 1.5,
					})
				end
				task.wait(0.4)
			end
		end
		state.runeTpThread = nil
	end)
end

local function clearRuneScroll()
	if not runeScroll then
		return
	end
	for _, ch in ipairs(runeScroll:GetChildren()) do
		if ch:IsA("TextButton") or ch:IsA("Frame") then
			ch:Destroy()
		end
	end
end

local function buildRuneListUI()
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "RuneListScroll"
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
	return scroll
end

local function refreshRunes()
	clearRuneScroll()
	if not runeScroll then
		return 0
	end
	local rows = listWorldRunes()
	table.sort(rows, function(a, b)
		if a.tier ~= b.tier then
			return a.tier > b.tier
		end
		return a.dist < b.dist
	end)
	for i, row in ipairs(rows) do
		if i > 25 then
			break
		end
		local btn = Instance.new("TextButton")
		btn.LayoutOrder = i
		btn.Size = UDim2.new(1, 0, 0, 28)
		btn.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = true
		btn.Text = ""
		btn.Parent = runeScroll
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 4)
		c.Parent = btn
		local stroke = Instance.new("UIStroke")
		stroke.Color = row.color
		stroke.Thickness = 1
		stroke.Transparency = 0.3
		stroke.Parent = btn
		local info = Instance.new("TextLabel")
		info.BackgroundTransparency = 1
		info.Position = UDim2.fromOffset(8, 0)
		info.Size = UDim2.new(1, -16, 1, 0)
		info.Font = Enum.Font.Gotham
		info.TextSize = 12
		info.TextColor3 = Color3.fromRGB(230, 230, 235)
		info.TextXAlignment = Enum.TextXAlignment.Left
		info.Text = string.format("%s Rune / %dm", row.id, math.floor(row.dist))
		info.Parent = btn
		local part = row.part
		btn.MouseButton1Click:Connect(function()
			if part and part.Parent then
				steppedTeleport(part.Position + Vector3.new(0, 3, 0), 6)
				task.wait(0.2)
				fireRunePrompt(part)
			end
		end)
	end
	if state.runeEsp then
		applyRuneESP()
	end
	return #rows
end

--========================================================
-- BOULDERS (module / keeps top-level locals low)
--========================================================
local Boulders = {}
do
	local NAMES = { "Mossite", "Voltite", "Gildrite", "Rimeveil", "Nocturnite" }
	local TIER = { Mossite = 1, Voltite = 2, Gildrite = 3, Rimeveil = 4, Nocturnite = 5 }
	local INFO = {
		Mossite = { rarity = "Common", pickaxe = "Titanium Spike", crystals = "8-11", runes = "Luck / Haste", color = Color3.fromRGB(150, 220, 120) },
		Voltite = { rarity = "Uncommon", pickaxe = "Celestial Apex", crystals = "10-14", runes = "Storm / Weight", color = Color3.fromRGB(110, 190, 240) },
		Gildrite = { rarity = "Rare", pickaxe = "Eclipse Fang", crystals = "11-15", runes = "Fortune / Detonation", color = Color3.fromRGB(255, 200, 60) },
		Rimeveil = { rarity = "Epic", pickaxe = "Voidreign", crystals = "13-18", runes = "Preservation / Warmth", color = Color3.fromRGB(170, 100, 255) },
		Nocturnite = { rarity = "Legendary", pickaxe = "The Terminus", crystals = "16-22", runes = "Excavator / Colossus", color = Color3.fromRGB(255, 80, 180) },
	}
	local LIST_H = (Library.IsMobile == true) and 160 or 200
	local scroll
	local espCache = {}

	Boulders.NAMES = NAMES
	Boulders.LIST_H = LIST_H

	local function folder()
		local md = workspace:FindFirstChild("MountainDecorations")
		return md and md:FindFirstChild("Boulders")
	end

	local function primary(model)
		return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	end

	local function allowed(name)
		local sel = state.boulderSelected
		if not sel or next(sel) == nil then
			return true
		end
		return sel[name] == true
	end

	function Boulders.syncSelected(value)
		local map = {}
		if type(value) == "table" then
			for a, b in pairs(value) do
				if b == true and type(a) == "string" then
					map[a] = true
				elseif type(b) == "string" then
					map[b] = true
				end
			end
			for _, item in ipairs(value) do
				if type(item) == "string" then
					map[item] = true
				end
			end
		elseif type(value) == "string" and value ~= "" then
			map[value] = true
		end
		state.boulderSelected = next(map) == nil and nil or map
		return state.boulderSelected
	end

	local function each(fn)
		local f = folder()
		if not f then
			return
		end
		for _, m in ipairs(f:GetChildren()) do
			if m:IsA("Model") and m:GetAttribute("BoulderName") then
				local name = m:GetAttribute("BoulderName") or m.Name
				if allowed(name) then
					fn(m, name)
				end
			end
		end
	end

	function Boulders.clearESP()
		for m, entry in pairs(espCache) do
			if entry.gui then
				pcall(function()
					entry.gui:Destroy()
				end)
			end
			espCache[m] = nil
		end
	end

	function Boulders.applyESP()
		Boulders.clearESP()
		if not state.boulderEsp then
			return
		end
		local hrp = getHRP()
		local origin = hrp and hrp.Position
		local scale = (Library.IsMobile == true) and 0.7 or 1
		local textSize = math.max(6, math.floor(12 * scale + 0.5))
		each(function(m, name)
			local info = INFO[name]
			local anchor = primary(m)
			if not info or not anchor then
				return
			end
			local entry = espCache[m]
			if not entry then
				local bb = Instance.new("BillboardGui")
				bb.Name = "MaM_BoulderESP"
				bb.Adornee = anchor
				bb.AlwaysOnTop = true
				bb.ResetOnSpawn = false
				bb.LightInfluence = 0
				bb.Size = UDim2.fromOffset(300 * scale, 78 * scale)
				bb.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
				bb.MaxDistance = math.huge
				bb.Parent = Library.ScreenGui
				local labels = {}
				local colors = { info.color, Color3.fromRGB(200, 200, 200), Color3.fromRGB(180, 180, 180) }
				for i = 1, 3 do
					local label = Instance.new("TextLabel")
					label.BackgroundTransparency = 1
					label.Size = UDim2.new(1, -12, 1 / 3, -2)
					label.Position = UDim2.new(0, 6, (i - 1) / 3, 1)
					label.Font = Enum.Font.GothamBold
					label.TextColor3 = colors[i]
					label.TextStrokeTransparency = 0.3
					label.TextSize = textSize
					label.TextXAlignment = Enum.TextXAlignment.Left
					label.TextTruncate = Enum.TextTruncate.AtEnd
					label.Text = ""
					label.Parent = bb
					labels[i] = label
				end
				entry = { gui = bb, labels = labels }
				espCache[m] = entry
			elseif entry.gui.Adornee ~= anchor then
				entry.gui.Adornee = anchor
			end
			local hp = tonumber(m:GetAttribute("HP")) or 0
			local maxHp = tonumber(m:GetAttribute("MaxHP")) or hp
			local pct = maxHp > 0 and math.floor(100 * hp / maxHp) or 0
			local dist = origin and math.floor((anchor.Position - origin).Magnitude) or 0
			entry.labels[1].Text = string.format("[%s] %s", info.rarity, name)
			entry.labels[2].Text = string.format("%s  /  %s crystals", info.pickaxe, info.crystals)
			entry.labels[3].Text = string.format("%s  /  %dm  /  HP %d%%", info.runes, dist, pct)
		end)
		for m, entry in pairs(espCache) do
			if not m.Parent then
				if entry.gui then
					entry.gui:Destroy()
				end
				espCache[m] = nil
			end
		end
	end

	local function getPickName()
		local tool = getEquippedPickaxe()
		return tool and tool.Name or nil
	end

	function Boulders.breakOnce(model)
		local pp = primary(model)
		if not pp then
			return false, "no part"
		end
		local hrp = getHRP()
		if not hrp then
			return false, "no hrp"
		end
		local stand = pp.Position + Vector3.new(0, 4, 6)
		if not steppedTeleport(stand, 10) then
			return false, "tp fail"
		end
		local toolName = getPickName()
		if not toolName then
			return false, "equip pickaxe"
		end
		local hp0 = tonumber(model:GetAttribute("HP")) or 0
		local cells = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(cells, d)
			end
		end
		if #cells == 0 then
			table.insert(cells, pp)
		end
		local hits, lastHp, stallHits = 0, hp0, 0
		local forced = state._forceBreak == true
		while model.Parent and hits < 8000 do
			if not forced and not state.autoBreak then
				return false, string.format("stopped / hits %d", hits)
			end
			local hp = tonumber(model:GetAttribute("HP")) or 0
			if hp <= 0 then
				break
			end
			if hits % 12 == 0 then
				local pp2 = primary(model)
				if pp2 then
					stand = pp2.Position + Vector3.new(0, 4, 5)
				end
				hrp = getHRP()
				if not hrp then
					return false, "no hrp"
				end
				toolName = getPickName() or toolName
			end
			hrp.CFrame = CFrame.new(stand)
			hrp.AssemblyLinearVelocity = Vector3.zero
			local cell = cells[(hits % #cells) + 1]
			if cell and cell.Parent then
				fireDig(toolName, cell.Position)
			else
				local pp2 = primary(model)
				if pp2 then
					fireDig(toolName, pp2.Position)
				end
			end
			hits += 1
			task.wait(0.055)
			if hits % 25 == 0 then
				local hpNow = tonumber(model:GetAttribute("HP")) or 0
				if hpNow >= lastHp - 1 then
					stallHits += 1
					if stallHits >= 2 then
						local pp2 = primary(model)
						if pp2 then
							stand = pp2.Position + Vector3.new(0, 3, 2)
							steppedTeleport(stand, 3)
						end
						toolName = getPickName() or toolName
						cells = {}
						for _, d in ipairs(model:GetDescendants()) do
							if d:IsA("BasePart") then
								table.insert(cells, d)
							end
						end
						if #cells == 0 and pp then
							table.insert(cells, pp)
						end
						stallHits = 0
					end
				else
					stallHits = 0
				end
				lastHp = hpNow
			end
		end
		local hp1 = tonumber(model:GetAttribute("HP")) or 0
		local gone = not model.Parent or hp1 <= 0
		return gone, string.format("hits %d / dHP %d%s", hits, math.floor(hp0 - hp1), gone and " / broke" or " / stuck")
	end

	function Boulders.nearest()
		local hrp = getHRP()
		if not hrp then
			return nil
		end
		local best, bestD
		each(function(m)
			local pp = primary(m)
			if not pp then
				return
			end
			local d = (pp.Position - hrp.Position).Magnitude
			if not bestD or d < bestD then
				best, bestD = m, d
			end
		end)
		return best
	end

	local function drainRunes()
		local total, idle = 0, 0
		local deadline = os.clock() + 20
		while state.autoBreak and not Library.Unloaded and os.clock() < deadline do
			local n = pickupNearbyRunes()
			total += n
			if n == 0 then
				idle += 1
				if idle >= 4 then
					break
				end
				task.wait(0.35)
			else
				idle = 0
				task.wait(0.2)
			end
		end
		return total
	end

	function Boulders.stop()
		state.autoBreak = false
		state._forceBreak = false
	end

	-- no boulders left: TP to remaining world runes (pickup = Auto Pickup Rune vacuum)
	local function tpToRemainingRunes()
		local rows = listWorldRunes()
		if #rows == 0 then
			return 0
		end
		local n = 0
		for _, row in ipairs(rows) do
			if not state.autoBreak or Library.Unloaded then
				break
			end
			local part = row.part
			if part and part.Parent then
				steppedTeleport(part.Position + Vector3.new(0, 3, 0), 6)
				n += 1
				-- dwell so Auto Pickup Rune (0.25s vacuum) can fire
				task.wait(0.35)
			end
		end
		return n
	end

	function Boulders.start()
		stopHeavyFarms("boulder")
		-- set flag BEFORE early-return: old breakThread may still be alive after stop
		state.autoBreak = true
		if state.breakThread then
			return
		end
		state.breakThread = task.spawn(function()
			-- teleport ke tengah gunung dulu sebelum cari boulder
			pcall(function()
				local cx = workspace:GetAttribute("MountainCenterX")
				local cz = workspace:GetAttribute("MountainCenterZ")
				local base = workspace:GetAttribute("MountainBaseY") or 0
				local peak = workspace:GetAttribute("MountainPeakY") or (base + 100)
				if typeof(cx) == "number" and typeof(cz) == "number" then
					local goal = Vector3.new(cx, base + (peak - base) * 0.5, cz)
					steppedTeleport(goal, 4)
				end
			end)
			while state.autoBreak and not Library.Unloaded do
				local m = Boulders.nearest()
				if not state.autoBreak then
					break
				end
				if not m then
					-- all boulders gone -> TP leftover runes (grab left to Auto Pickup Rune)
					local hopped = tpToRemainingRunes()
					if hopped > 0 then
						Library:Notify({
							Title = "Boulder Farm",
							Description = "No boulder / TP runes " .. tostring(hopped),
							Time = 2,
						})
						task.wait(0.4)
					else
						-- farm done: no boulder + no rune -> TP-pickup crystals per Main filters
						if state.pickupAfterBoulder then
							local picked, skip = 0, {}
							local on = function()
								return state.autoBreak and state.pickupAfterBoulder and not Library.Unloaded
							end
							while on() do
								pickupStep(on)
								local best = listMineables(state.mineMinTier, getHRP(), nil, skip)[1]
								if not best or not best.part.Parent then
									break
								end
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
									if got then
										picked = picked + 1
									end
									task.wait(got and PICK.cooldown or 0.12)
								end
								for p in pairs(skip) do
									if not p or not p.Parent then
										skip[p] = nil
									end
								end
							end
							if picked > 0 then
								Library:Notify({
									Title = "Boulder Farm",
									Description = "Crystal pickup " .. tostring(picked),
									Time = 2,
								})
							end
							task.wait(0.3)
						end
						if state.autoRejoin then
							Library:Notify({
								Title = "Auto Rejoin",
								Description = "Farm clear / rejoining?",
								Time = 2,
							})
							task.wait(0.35)
							-- same as Server.rejoin (inline - Server local defined later)
							local ok, err = pcall(function()
								local placeId = game.PlaceId
								local jobId = game.JobId
								if #Players:GetPlayers() <= 1 then
									LP:Kick("\nRejoining...")
									task.wait()
									TeleportService:Teleport(placeId, LP)
								else
									TeleportService:TeleportToPlaceInstance(placeId, jobId, LP)
								end
							end)
							if not ok then
								Library:Notify({
									Title = "Rejoin failed",
									Description = tostring(err),
									Time = 3,
								})
								task.wait(3)
							else
								task.wait(5)
							end
						else
							task.wait(2)
						end
					end
				else
					local name = m:GetAttribute("BoulderName") or m.Name
					local ok, msg = Boulders.breakOnce(m)
					if not state.autoBreak then
						break
					end
					if ok then
						task.wait(0.35)
						local got = drainRunes()
						Library:Notify({
							Title = "Broke " .. name,
							Description = tostring(msg) .. " / runes " .. tostring(got),
							Time = 2,
						})
					else
						Library:Notify({
							Title = "Break " .. name,
							Description = tostring(msg),
							Time = 2,
						})
						task.wait(1.2)
					end
				end
				task.wait(0.15)
			end
			state.breakThread = nil
		end)
	end

	function Boulders.buildListUI()
		local s = Instance.new("ScrollingFrame")
		s.Name = "BoulderListScroll"
		s.BackgroundTransparency = 1
		s.BorderSizePixel = 0
		s.Size = UDim2.fromScale(1, 1)
		s.CanvasSize = UDim2.fromOffset(0, 0)
		s.ScrollBarThickness = 4
		s.AutomaticCanvasSize = Enum.AutomaticSize.Y
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 3)
		layout.Parent = s
		return s
	end

	function Boulders.count()
		local n = 0
		each(function()
			n += 1
		end)
		return n
	end

	function Boulders.folderCount()
		local f = folder()
		return f and #f:GetChildren() or 0
	end

	function Boulders.refresh()
		if not scroll then
			return 0
		end
		for _, ch in ipairs(scroll:GetChildren()) do
			if ch:IsA("TextButton") or ch:IsA("Frame") then
				ch:Destroy()
			end
		end
		local hrp = getHRP()
		local rows = {}
		each(function(m, name)
			local tier = TIER[name] or 1
			local pp = primary(m)
			local hp = tonumber(m:GetAttribute("HP")) or 0
			local maxHp = tonumber(m:GetAttribute("MaxHP")) or hp
			table.insert(rows, {
				model = m,
				name = name,
				tier = tier,
				hp = hp,
				maxHp = maxHp,
				dist = (hrp and pp) and math.floor((pp.Position - hrp.Position).Magnitude) or 0,
				rarity = m:GetAttribute("Rarity") or "?",
				color = TIER_COLORS[tier] or Color3.new(1, 1, 1),
			})
		end)
		table.sort(rows, function(a, b)
			if a.tier ~= b.tier then
				return a.tier > b.tier
			end
			return a.dist < b.dist
		end)
		for i, row in ipairs(rows) do
			if i > 25 then
				break
			end
			local btn = Instance.new("TextButton")
			btn.LayoutOrder = i
			btn.Size = UDim2.new(1, 0, 0, 32)
			btn.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
			btn.BorderSizePixel = 0
			btn.AutoButtonColor = true
			btn.Text = ""
			btn.Parent = scroll
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 4)
			c.Parent = btn
			local stroke = Instance.new("UIStroke")
			stroke.Color = row.color
			stroke.Thickness = 1
			stroke.Transparency = 0.3
			stroke.Parent = btn
			local info = Instance.new("TextLabel")
			info.BackgroundTransparency = 1
			info.Position = UDim2.fromOffset(8, 0)
			info.Size = UDim2.new(1, -16, 1, 0)
			info.Font = Enum.Font.Gotham
			info.TextSize = 12
			info.TextColor3 = Color3.fromRGB(230, 230, 235)
			info.TextXAlignment = Enum.TextXAlignment.Left
			info.TextTruncate = Enum.TextTruncate.AtEnd
			local pct = row.maxHp > 0 and math.floor(100 * row.hp / row.maxHp) or 0
			info.Text = string.format("%s [%s] HP %d%% %dm", row.name, row.rarity, pct, row.dist)
			info.Parent = btn
			local model = row.model
			btn.MouseButton1Click:Connect(function()
				local pp = primary(model)
				if pp then
					steppedTeleport(pp.Position + Vector3.new(0, 4, 6), 10)
				end
			end)
		end
		if state.boulderEsp then
			Boulders.applyESP()
		end
		return #rows
	end

	function Boulders.setScroll(s)
		scroll = s
	end
end

--========================================================
-- DROP (CrystalDropRequest / module)
--========================================================
local Drop = {}
do
	local function getCrystalTools()
		local tools = {}
		local function scan(container)
			if not container then
				return
			end
			for _, t in ipairs(container:GetChildren()) do
				if t:IsA("Tool") and t:GetAttribute("Tier") ~= nil then
					table.insert(tools, t)
				end
			end
		end
		scan(LP:FindFirstChildOfClass("Backpack") or LP:FindFirstChild("Backpack"))
		scan(LP.Character)
		return tools
	end

	local function toolValue(tool)
		return tonumber(tool:GetAttribute("Value")) or 0
	end

	local function canDrop(tool)
		if not tool or not tool.Parent then
			return false
		end
		if tool:GetAttribute("Tier") == nil then
			return false
		end
		-- always skip favorited
		if tool:GetAttribute("Favorited") == true then
			return false
		end
		return true
	end

	local function fireDrop(tool)
		if not canDrop(tool) then
			return false
		end
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local drop = remotes and remotes:FindFirstChild("CrystalDropRequest")
		if not drop then
			return false
		end
		local name = tool.Name
		if type(name) ~= "string" or name == "" then
			return false
		end
		return pcall(function()
			drop:FireServer(name)
		end)
	end

	function Drop.statusText()
		local mode = state.dropMode or "off"
		local target = (tonumber(state.dropValueTargetB) or 1) * 1e9
		local sort = state.dropSortExpensive and "expensive" or "cheap"
		return string.format(
			"Mode: %s / sort %s\nDropped: %d / %s\nTarget: %s",
			mode,
			sort,
			state.dropStatCount or 0,
			formatMoney(state.dropStatValue or 0),
			formatMoney(target)
		)
	end

	function Drop.stop()
		state.dropMode = nil
	end

	function Drop.start(mode)
		if mode ~= "all" and mode ~= "value" then
			return
		end
		state.dropMode = mode
		if state.dropThread then
			return
		end
		state.dropStatCount = 0
		state.dropStatValue = 0
		state.dropThread = task.spawn(function()
			while state.dropMode and not Library.Unloaded do
				local modeNow = state.dropMode
				local delay = math.clamp(tonumber(state.dropDelay) or 0.15, 0.05, 1)
				local tools = getCrystalTools()
				local dropped = 0

				if modeNow == "all" then
					for _, tool in ipairs(tools) do
						if state.dropMode ~= "all" or Library.Unloaded then
							break
						end
						if canDrop(tool) then
							local v = toolValue(tool)
							if fireDrop(tool) then
								dropped += 1
								state.dropStatCount += 1
								state.dropStatValue += v
								task.wait(delay)
							end
						end
					end
					if dropped == 0 then
						-- bag empty of droppable (or all fav) - idle
						task.wait(1)
					end
				elseif modeNow == "value" then
					local target = (tonumber(state.dropValueTargetB) or 1) * 1e9
					if target <= 0 then
						task.wait(1)
					else
						local list = {}
						for _, tool in ipairs(tools) do
							if canDrop(tool) then
								table.insert(list, tool)
							end
						end
						-- sort by $ : expensive first or cheapest first
						if state.dropSortExpensive then
							table.sort(list, function(a, b)
								return toolValue(a) > toolValue(b)
							end)
						else
							table.sort(list, function(a, b)
								return toolValue(a) < toolValue(b)
							end)
						end
						local session = state.dropStatValue or 0
						for _, tool in ipairs(list) do
							if state.dropMode ~= "value" or Library.Unloaded then
								break
							end
							if session >= target then
								break
							end
							local v = toolValue(tool)
							if fireDrop(tool) then
								session += v
								state.dropStatCount += 1
								state.dropStatValue = session
								dropped += 1
								task.wait(delay)
							end
						end
						if session >= target then
							task.wait(1.2)
						elseif dropped == 0 then
							task.wait(1)
						else
							task.wait(0.4)
						end
					end
				else
					break
				end
			end
			state.dropThread = nil
		end)
	end
end

--========================================================
-- DESTROY WORLD CRYSTALS (client-side, by rarity)
--========================================================
do
	local function worldCrystals()
		local things = workspace:FindFirstChild("Things")
		local roots = {
			things and things:FindFirstChild("Crystals"),
			workspace:FindFirstChild("DroppedCrystals"),
		}
		local parts = {}
		for _, root in ipairs(roots) do
			if root then
				for _, p in ipairs(root:GetDescendants()) do
					if p:IsA("BasePart") and p:GetAttribute("Tier") ~= nil then
						parts[#parts + 1] = p
					end
				end
			end
		end
		return parts
	end

	state.CrystalDestroy = state.CrystalDestroy or {}

	function state.CrystalDestroy.stop()
		state.destroyLowRarity = false
	end

	function state.CrystalDestroy.start()
		if state.destroyThread then
			return
		end
		state.destroyLowRarity = true
		state.destroyThread = task.spawn(function()
			while state.destroyLowRarity and not Library.Unloaded do
				local maxTier = tonumber(state.destroyMaxTier) or 6
				local parts = worldCrystals()
				local killed = 0
				for _, p in ipairs(parts) do
					if not state.destroyLowRarity or Library.Unloaded then
						break
					end
					local t = tonumber(p:GetAttribute("Tier")) or 0
					if t <= maxTier then
						pcall(function()
							p:Destroy()
						end)
						killed = killed + 1
					end
				end
				task.wait(killed > 0 and 0.5 or 1.5)
			end
			state.destroyThread = nil
		end)
	end
end

--========================================================
-- DROP RUNE (equip + CrystalDropRequest -> DroppedRunes)
--========================================================
do
	local RUNE_MAP = {
		["Luck Rune"] = "LuckRune",
		["Haste Rune"] = "HasteRune",
		["Storm Rune"] = "StormRune",
		["Fortune Rune"] = "FortuneRune",
		["Detonation Rune"] = "DetonationRune",
		["Preservation Rune"] = "PreservationRune",
		["Weight Rune"] = "WeightRune",
		["Excavator Rune"] = "ExcavatorRune",
		["Warmth Rune"] = "WarmthRune",
		["Colossus Rune"] = "ColossusRune",
	}

	local function runeTools()
		local tools = {}
		local function scan(c)
			if not c then
				return
			end
			for _, t in ipairs(c:GetChildren()) do
				if t:IsA("Tool") and type(t:GetAttribute("RuneId")) == "string" then
					tools[#tools + 1] = t
				end
			end
		end
		scan(LP:FindFirstChildOfClass("Backpack"))
		scan(LP.Character)
		return tools
	end

	state.DropRune = state.DropRune or {}
	state.DropRune.map = RUNE_MAP

	function state.DropRune.stop()
		state.runeDrop = false
	end

	function state.DropRune.start()
		if state.runeDropThread then
			return
		end
		state.runeDrop = true
		state.runeDropThread = task.spawn(function()
			local ok, err = pcall(function()
				local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
				local budget = math.max(1, tonumber(state.runeDropCount) or 1)
				local sel = state.runeDropSel
				local dropped = 0
				local seen = {}
				local ids = {}
				for _, t in ipairs(runeTools()) do
					local id = t:GetAttribute("RuneId")
					if type(id) == "string" and (sel == nil or id == sel) and not seen[id] then
						seen[id] = true
						ids[#ids + 1] = id
					end
				end
				for _, id in ipairs(ids) do
					if not state.runeDrop or Library.Unloaded then
						break
					end
					local tool
					for _, t in ipairs(runeTools()) do
						if t:GetAttribute("RuneId") == id then
							tool = t
							break
						end
					end
					if not tool or not hum then
						continue
					end
					pcall(function()
						hum:EquipTool(tool)
					end)
					task.wait(0.4)
					local remotes = ReplicatedStorage:FindFirstChild("Remotes")
					local dr = remotes and remotes:FindFirstChild("CrystalDropRequest")
					if not dr then
						continue
					end
					local name = tool.Name
					for i = 1, budget do
						if not state.runeDrop or Library.Unloaded then
							break
						end
						pcall(function()
							dr:FireServer(name)
						end)
						dropped = dropped + 1
						task.wait(0.35)
					end
				end
				state.runeDrop = false
				pcall(function()
					if Toggles.RuneDrop then
						Toggles.RuneDrop:SetValue(false)
					end
				end)
				if dropped > 0 then
					Library:Notify({
						Title = "Drop Rune",
						Description = string.format("dropped %s", tostring(dropped)),
						Time = 2,
					})
				end
			end)
			if not ok then
				warn("[DropRune] " .. tostring(err))
				state.runeDrop = false
				pcall(function()
					if Toggles.RuneDrop then
						Toggles.RuneDrop:SetValue(false)
					end
				end)
			end
			state.runeDropThread = nil
		end)
	end
end

--========================================================
-- FAVORITE (ToggleFavorite / server-authoritative / v4.2.3)
--========================================================
local Fav = {}
do
	local _favIndex = nil

	local function getCrystalTools()
		local tools = {}
		local function scan(container)
			if not container then
				return
			end
			for _, t in ipairs(container:GetChildren()) do
				if t:IsA("Tool") and t:GetAttribute("Tier") ~= nil then
					table.insert(tools, t)
				end
			end
		end
		scan(LP.Character)
		scan(LP:FindFirstChildOfClass("Backpack") or LP:FindFirstChild("Backpack"))
		return tools
	end

	local function crystalKey(inst)
		if not inst then
			return nil
		end
		return tostring(inst:GetAttribute("Value"))
			.. "|"
			.. tostring(inst:GetAttribute("WeightKg"))
			.. "|"
			.. tostring(inst:GetAttribute("DisplayName") or inst:GetAttribute("CrystalName") or inst.Name)
	end

	local function rebuildFavIndex()
		local map = {}
		local inv = LP:FindFirstChild("PlayerData")
		inv = inv and inv:FindFirstChild("Inventory")
		local folder = inv and inv:FindFirstChild("Crystals")
		if folder then
			for _, c in ipairs(folder:GetChildren()) do
				local k = crystalKey(c)
				if k then
					map[k] = c
				end
			end
		end
		_favIndex = map
		return map
	end

	local function isToolFavorited(tool)
		if not tool then
			return false
		end
		if tool:GetAttribute("Favorited") ~= nil then
			return tool:GetAttribute("Favorited") == true
		end
		local data = (_favIndex or rebuildFavIndex())[crystalKey(tool)]
		if data then
			return data:GetAttribute("Favorited") == true
		end
		return false
	end

	local function setToolFavorite(tool, want)
		if not tool or not tool.Parent then
			return false
		end
		if isToolFavorited(tool) == want then
			return true
		end
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local fav = remotes and remotes:FindFirstChild("ToggleFavorite")
		if not fav then
			return false
		end
		-- FireServer only - never SetAttribute first (ghost = loop skip)
		local ok = pcall(function()
			fav:FireServer(tool, want)
		end)
		if not ok then
			return false
		end
		local t0 = os.clock()
		while os.clock() - t0 < 0.4 do
			_favIndex = nil
			if isToolFavorited(tool) == want then
				return true
			end
			task.wait(0.05)
		end
		if tool:GetAttribute("Favorited") == true and not isToolFavorited(tool) then
			pcall(function()
				tool:SetAttribute("Favorited", false)
			end)
		end
		_favIndex = nil
		return isToolFavorited(tool) == want
	end

	local function toolLuckPct(tool)
		local ok, luck = pcall(crystalLuckValue, tool)
		if not ok or type(luck) ~= "number" or luck ~= luck then
			return 0
		end
		return luck * 100
	end

	function Fav.statusText()
		rebuildFavIndex()
		local tools = getCrystalTools()
		local favN, matchLuck, matchRar, matchWt = 0, 0, 0, 0
		local minPct = tonumber(state.favLuckMin) or 4
		local minWt = tonumber(state.favMinWeight) or 4
		for _, t in ipairs(tools) do
			if isToolFavorited(t) then
				favN += 1
			end
			if toolLuckPct(t) >= minPct then
				matchLuck += 1
			end
			local tier = tonumber(t:GetAttribute("Tier")) or 0
			if state.favRarityTiers and state.favRarityTiers[tier] then
				matchRar += 1
			end
			local _, _, wtRank = crystalSize(t)
			if wtRank and wtRank >= minWt then
				matchWt += 1
			end
		end
		return string.format(
			"Bag: %d / Fav: %d\nLuck ? %.0f%%: %d / Rarity: %d / Weight: %d",
			#tools,
			favN,
			minPct,
			matchLuck,
			matchRar,
			matchWt
		)
	end

	function Fav.syncRarity(value)
		local map = {}
		if type(value) == "table" then
			for label, on in pairs(value) do
				if on then
					local tier = rarityToTier(label)
					if tier then
						map[tier] = true
					end
				end
			end
		end
		if next(map) == nil then
			map[5] = true
			map[6] = true
		end
		state.favRarityTiers = map
		return map
	end

	local function wantsFavorite(tool, minPct)
		if state.autoFavLuck and toolLuckPct(tool) >= minPct then
			return true
		end
		if state.autoFavRarity then
			local tier = tonumber(tool:GetAttribute("Tier")) or 0
			if state.favRarityTiers and state.favRarityTiers[tier] then
				return true
			end
		end
		if state.autoFavWeight then
			local _, _, wtRank = crystalSize(tool)
			if wtRank and wtRank >= (tonumber(state.favMinWeight) or 4) then
				return true
			end
		end
		return false
	end

	local function runPass()
		rebuildFavIndex()
		local minPct = tonumber(state.favLuckMin) or 4
		local n = 0
		for _, tool in ipairs(getCrystalTools()) do
			if Library.Unloaded or not (state.autoFavLuck or state.autoFavRarity or state.autoFavWeight) then
				break
			end
			if wantsFavorite(tool, minPct) and not isToolFavorited(tool) then
				if setToolFavorite(tool, true) then
					n += 1
					task.wait(0.06)
				else
					task.wait(0.1)
				end
			end
		end
		return n
	end

	function Fav.start()
		if state.favThread then
			return
		end
		state.favThread = task.spawn(function()
			pcall(runPass)
			while (state.autoFavLuck or state.autoFavRarity or state.autoFavWeight) and not Library.Unloaded do
				pcall(runPass)
				task.wait(0.75)
			end
			state.favThread = nil
		end)
	end

	function Fav.stop()
		state.autoFavLuck = false
		state.autoFavRarity = false
		state.autoFavWeight = false
	end

	function Fav.favoriteAll()
		rebuildFavIndex()
		local n = 0
		for _, tool in ipairs(getCrystalTools()) do
			if Library.Unloaded then
				break
			end
			if setToolFavorite(tool, true) then
				n += 1
			end
			task.wait(0.05)
		end
		return n
	end

	function Fav.unfavoriteAll()
		rebuildFavIndex()
		local n = 0
		for _, tool in ipairs(getCrystalTools()) do
			if Library.Unloaded then
				break
			end
			if setToolFavorite(tool, false) then
				n += 1
			end
			task.wait(0.05)
		end
		return n
	end
end

--========================================================
-- SHOP / BOMBS (module)
--========================================================
local Bombs = {}
do
	local BombShopConfig
	pcall(function()
		BombShopConfig = require(ReplicatedStorage.Modules.BombShopConfig)
	end)

	local ORDER = {
		"ClassicBomb",
		"WindBomb",
		"IceBomb",
		"FireBomb",
		"ThunderBomb",
		"PoisonBomb",
		"TimeBomb",
		"AgonyBomb",
	}

	local function meta(id)
		return BombShopConfig and BombShopConfig.BOMBS and BombShopConfig.BOMBS[id]
	end

	local function displayName(id)
		local m = meta(id)
		return (m and m.displayName) or id
	end

	local function price(id)
		local m = meta(id)
		return (m and m.cashPrice) or 0
	end

	function Bombs.dropdownLabels()
		local labels = {}
		for _, id in ipairs(ORDER) do
			local m = meta(id)
			if m and m.enabled ~= false then
				table.insert(labels, string.format("%s ($%s)", m.displayName, formatMoney(m.cashPrice):gsub("%$", "")))
			end
		end
		return labels
	end

	local function labelToId(label)
		if type(label) ~= "string" then
			return nil
		end
		for _, id in ipairs(ORDER) do
			local m = meta(id)
			if m and label:find(m.displayName, 1, true) then
				return id
			end
			if label == id then
				return id
			end
		end
		return nil
	end

	function Bombs.syncTargets(value)
		local map = {}
		if type(value) == "table" then
			for label, on in pairs(value) do
				if on then
					local id = labelToId(label)
					if id then
						map[id] = true
					end
				end
			end
		elseif type(value) == "string" then
			local id = labelToId(value)
			if id then
				map[id] = true
			end
		end
		if next(map) == nil then
			map.ClassicBomb = true
		end
		state.bombTargets = map
		return map
	end

	function Bombs.queryStock()
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local q = remotes and remotes:FindFirstChild("BombShopQuery")
		if q then
			local ok, result = pcall(function()
				return q:InvokeServer()
			end)
			if ok and type(result) == "table" and type(result.stock) == "table" then
				state.bombStock = result.stock
				return state.bombStock, true
			end
		end
		if BombShopConfig and BombShopConfig.rollStockForWindow then
			local win = BombShopConfig.currentWindow and BombShopConfig.currentWindow() or 0
			state.bombStock = BombShopConfig.rollStockForWindow(win) or {}
			return state.bombStock, false
		end
		return state.bombStock, false
	end

	-- rarer first among selected with stock + cash
	local function pickBuyable()
		for i = #ORDER, 1, -1 do
			local id = ORDER[i]
			if state.bombTargets[id] then
				local stock = tonumber(state.bombStock[id]) or 0
				if stock > 0 and getCash() >= price(id) then
					return id
				end
			end
		end
		return nil
	end

	local function tryBuy(id)
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local buy = remotes and remotes:FindFirstChild("BombBuyRequest")
		if not buy then
			return false, "no remote"
		end
		if getCash() < price(id) then
			return false, "no cash"
		end
		local stock = state.bombStock[id]
		if stock ~= nil and stock <= 0 then
			return false, "no stock"
		end
		local ok, result = pcall(function()
			return buy:InvokeServer(id)
		end)
		if not ok then
			return false, "invoke fail"
		end
		if type(result) == "table" and result.ok then
			if result.remaining ~= nil then
				state.bombStock[id] = result.remaining
			else
				state.bombStock[id] = math.max(0, (state.bombStock[id] or 1) - 1)
			end
			return true, result.remaining
		end
		return false, "rejected"
	end

	function Bombs.stop()
	state.autoBuyBomb = false
	state.autoUpgradeCarry = false
	state.destroyLowRarity = false
	end

	function Bombs.start()
		if state.bombThread then
			return
		end
		state.autoBuyBomb = true
		state.bombThread = task.spawn(function()
			while state.autoBuyBomb and not Library.Unloaded do
				Bombs.queryStock()
				local id = pickBuyable()
				if id then
					local ok = tryBuy(id)
					if ok then
						Library:Notify({
							Title = "Bomb Buy",
							Description = string.format(
								"Bought %s / left %s",
								displayName(id),
								tostring(state.bombStock[id] or "?")
							),
							Time = 2,
						})
						task.wait(0.45)
					else
						task.wait(1.2)
					end
				else
					task.wait(1.5)
				end
			end
			state.bombThread = nil
		end)
	end

	Bombs.ORDER = ORDER
	Bombs.displayName = displayName
end

--========================================================
-- SHOP / RADARS (module)
--========================================================
local Radars = {}
do
	local RadarShopConfig
	pcall(function()
		RadarShopConfig = require(ReplicatedStorage.Modules.RadarShopConfig)
	end)

	local function meta(id)
		return RadarShopConfig and RadarShopConfig.RADARS and RadarShopConfig.RADARS[id]
	end

	local function displayName(id)
		local m = meta(id)
		return (m and m.displayName) or id
	end

	local function price(id)
		local m = meta(id)
		return (m and m.cashPrice) or 0
	end

	local function duration(id)
		local m = meta(id)
		return (m and m.durationSeconds) or 45
	end

	local function rarity(id)
		local m = meta(id)
		return (m and m.rarity) or "Common"
	end

	function Radars.dropdownLabels()
		local labels = {}
		if RadarShopConfig and RadarShopConfig.orderedIds then
			for _, id in ipairs(RadarShopConfig.orderedIds()) do
				local m = meta(id)
				if m and m.enabled ~= false then
					table.insert(labels, string.format("%s ($%s)", m.displayName, formatMoney(m.cashPrice):gsub("%$", "")))
				end
			end
		end
		return labels
	end

	local function labelToId(label)
		if type(label) ~= "string" then
			return nil
		end
		if RadarShopConfig and RadarShopConfig.RADARS then
			for id, m in pairs(RadarShopConfig.RADARS) do
				if label:find(m.displayName, 1, true) then
					return id
				end
				if label == id then
					return id
				end
			end
		end
		return nil
	end

	function Radars.syncTargets(value)
		local map = {}
		if type(value) == "table" then
			for label, on in pairs(value) do
				if on then
					local id = labelToId(label)
					if id then
						map[id] = true
					end
				end
			end
		elseif type(value) == "string" then
			local id = labelToId(value)
			if id then
				map[id] = true
			end
		end
		if next(map) == nil then
			map.CrystalRadar = true
		end
		state.radarTargets = map
		return map
	end

	function Radars.queryStock()
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local q = remotes and remotes:FindFirstChild("RadarShopQuery")
		if q then
			local ok, result = pcall(function()
				return q:InvokeServer()
			end)
			if ok and type(result) == "table" and type(result.stock) == "table" then
				state.radarStock = result.stock
				return state.radarStock, true
			end
		end
		if RadarShopConfig and RadarShopConfig.rollStockForWindow then
			local win = RadarShopConfig.currentWindow and RadarShopConfig.currentWindow() or 0
			state.radarStock = RadarShopConfig.rollStockForWindow(win) or {}
			return state.radarStock, false
		end
		return state.radarStock, false
	end

	local function pickBuyable()
		if not RadarShopConfig or not RadarShopConfig.orderedIds then
			return nil
		end
		for _, id in ipairs(RadarShopConfig.orderedIds()) do
			if state.radarTargets[id] then
				local stock = tonumber(state.radarStock[id]) or 0
				if stock > 0 and getCash() >= price(id) then
					return id
				end
			end
		end
		return nil
	end

	local function tryBuy(id)
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local buy = remotes and remotes:FindFirstChild("RadarBuyRequest")
		if not buy then
			return false, "no remote"
		end
		if getCash() < price(id) then
			return false, "no cash"
		end
		local stock = state.radarStock[id]
		if stock ~= nil and stock <= 0 then
			return false, "no stock"
		end
		local ok, result = pcall(function()
			return buy:InvokeServer(id)
		end)
		if not ok then
			return false, "invoke fail"
		end
		if type(result) == "table" and result.ok then
			if result.remaining ~= nil then
				state.radarStock[id] = result.remaining
			else
				state.radarStock[id] = math.max(0, (state.radarStock[id] or 1) - 1)
			end
			return true, result.remaining
		end
		return false, "rejected"
	end

	function Radars.stop()
		state.autoBuyRadar = false
	end

	function Radars.start()
		if state.radarThread then
			return
		end
		state.autoBuyRadar = true
		state.radarThread = task.spawn(function()
			while state.autoBuyRadar and not Library.Unloaded do
				Radars.queryStock()
				local id = pickBuyable()
				if id then
					local ok = tryBuy(id)
					if ok then
						Library:Notify({
							Title = "Radar Buy",
							Description = string.format(
								"Bought %s / left %s / %ds",
								displayName(id),
								tostring(state.radarStock[id] or "?"),
								duration(id)
							),
							Time = 2,
						})
						task.wait(0.45)
					else
						task.wait(1.2)
					end
				else
					task.wait(1.5)
				end
			end
			state.radarThread = nil
		end)
	end

	Radars.meta = meta
	Radars.displayName = displayName
	Radars.price = price
	Radars.duration = duration
	Radars.rarity = rarity
	Radars.IDS = (RadarShopConfig and RadarShopConfig.orderedIds and RadarShopConfig.orderedIds()) or { "CrystalRadar" }
end

--========================================================
-- SHOP / UPGRADES (module)
-- UpgradeBuy:FireServer(kind, amount) kind Air|Weight amount 1|2|3
-- UpgradePrices:InvokeServer(kind) -> {p1,p2,p3}
-- UpgradePlotCapacity:FireServer()
--========================================================
local Upgrades = {}
do
	local KINDS = {
		{ kind = "Air", label = "Warmth +10", amount = 1 },
		{ kind = "Air", label = "Warmth +50", amount = 2 },
		{ kind = "Air", label = "Warmth +100", amount = 3 },
		{ kind = "Weight", label = "Carry +1kg", amount = 1 },
		{ kind = "Weight", label = "Carry +5kg", amount = 2 },
		{ kind = "Weight", label = "Carry +10kg", amount = 3 },
	}

	local function remotes()
		local r = ReplicatedStorage:FindFirstChild("Remotes")
		return r
	end

	function Upgrades.refreshPrices()
		local r = remotes()
		local rf = r and r:FindFirstChild("UpgradePrices")
		if not rf then
			return false
		end
		for _, kind in ipairs({ "Air", "Weight" }) do
			local ok, res = pcall(function()
				return rf:InvokeServer(kind)
			end)
			if ok and type(res) == "table" then
				state.upgPrices[kind] = res
			end
		end
		return true
	end

	local function price(kind, amount)
		local t = state.upgPrices[kind]
		if type(t) ~= "table" then
			return 0
		end
		return tonumber(t[amount]) or tonumber(t["p" .. amount]) or 0
	end

	function Upgrades.buy(kind, amount)
		local p = price(kind, amount)
		if p > 0 and getCash() < p then
			return false, "no cash"
		end
		local r = remotes()
		local re = r and r:FindFirstChild("UpgradeBuy")
		if not re then
			return false, "no remote"
		end
		local ok, err = pcall(function()
			re:FireServer(kind, amount)
		end)
		task.wait(0.3)
		return ok, err
	end

	function Upgrades.buyPlot()
		local r = remotes()
		local re = r and r:FindFirstChild("UpgradePlotCapacity")
		if not re then
			return false, "no remote"
		end
		local ok, err = pcall(function()
			re:FireServer()
		end)
		task.wait(0.3)
		return ok, err
	end

	function Upgrades.buildUI(box)
		Upgrades.refreshPrices()
		for _, def in ipairs(KINDS) do
			local p = price(def.kind, def.amount)
			local label = string.format("%s [%s]", def.label, formatMoney(p))
			if p > 0 and getCash() < p then
				label = label .. " (broke)"
			end
			local kind, amount = def.kind, def.amount
			box:AddButton({
				Text = label,
				Func = function()
					Upgrades.refreshPrices()
					local ok, err = Upgrades.buy(kind, amount)
					Library:Notify({
						Title = ok and "Upgrade" or "Upgrade fail",
						Description = ok and def.label or tostring(err),
						Time = 2,
					})
					-- rebuild prices on buttons next open is hard; refresh text via notify only
					Upgrades.refreshPrices()
				end,
			})
		end
		box:AddDivider()
		box:AddButton({
			Text = "Upgrade Plot Capacity",
			Func = function()
				local ok, err = Upgrades.buyPlot()
				Library:Notify({
					Title = ok and "Plot Upgrade" or "Plot fail",
					Description = ok and "UpgradePlotCapacity fired" or tostring(err),
					Time = 2,
				})
			end,
		})
		box:AddButton({
			Text = "Refresh Prices",
			Func = function()
				Upgrades.refreshPrices()
				local a = state.upgPrices.Air
				local w = state.upgPrices.Weight
				Library:Notify({
					Title = "Upgrade Prices",
					Description = string.format(
						"Warmth %s/%s/%s / Carry %s/%s/%s",
						formatMoney(a and a[1]),
						formatMoney(a and a[2]),
						formatMoney(a and a[3]),
						formatMoney(w and w[1]),
						formatMoney(w and w[2]),
						formatMoney(w and w[3])
					),
					Time = 3,
				})
			end,
		})
	end

	function Upgrades.stop()
		state.autoUpgradeCarry = false
	end

	function Upgrades.start()
		if state.upgradeThread then
			return
		end
		state.autoUpgradeCarry = true
		state.upgradeThread = task.spawn(function()
			while state.autoUpgradeCarry and not Library.Unloaded do
				Upgrades.refreshPrices()
				local p = price("Weight", 3)
				if p > 0 and getCash() >= p * 1.15 then
					local ok = Upgrades.buy("Weight", 3)
					if ok then
						Library:Notify({
							Title = "Auto Carry",
							Description = string.format("+10kg (paid %s)", formatMoney(p)),
							Time = 2,
						})
						task.wait(3)
					else
						task.wait(1.5)
					end
				else
					task.wait(2)
				end
			end
			state.upgradeThread = nil
		end)
	end
end

--========================================================
-- SERVER (players + hop/rejoin)
--========================================================
local Server = {}
do
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
		return steppedTeleport(t.Position, 3)
	end

	function Server.goHome()
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local r = remotes and remotes:FindFirstChild("GoHome")
		if not r then
			return false, "no GoHome"
		end
		return pcall(function()
			r:FireServer()
		end)
	end

	function Server.rejoin()
		return pcall(function()
			local placeId = game.PlaceId
			local jobId = game.JobId
			if #Players:GetPlayers() <= 1 then
				LP:Kick("\nRejoining...")
				task.wait()
				TeleportService:Teleport(placeId, LP)
			else
				TeleportService:TeleportToPlaceInstance(placeId, jobId, LP)
			end
		end)
	end

	function Server.hop()
		return pcall(function()
			local url = string.format(
				"https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100",
				game.PlaceId
			)
			local body
			if typeof(game.HttpGet) == "function" then
				body = game:HttpGet(url)
			elseif syn and syn.request then
				local res = syn.request({ Url = url, Method = "GET" })
				body = res and res.Body
			elseif request then
				local res = request({ Url = url, Method = "GET" })
				body = res and res.Body
			else
				error("no HttpGet")
			end
			local data = HttpService:JSONDecode(body)
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
			TeleportService:TeleportToPlaceInstance(game.PlaceId, list[math.random(1, #list)], LP)
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
-- MOVEMENT (Fly / Noclip / Speed) - module
--========================================================
local Move = {}
do
	function Move.stopFly()
		state.fly = false
		if state.flyConn then
			pcall(function()
				state.flyConn:Disconnect()
			end)
			state.flyConn = nil
		end
		if state.flyBv then
			pcall(function()
				state.flyBv:Destroy()
			end)
			state.flyBv = nil
		end
		if state.flyBg then
			pcall(function()
				state.flyBg:Destroy()
			end)
			state.flyBg = nil
		end
		local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.PlatformStand = false
		end
	end

	function Move.startFly()
		Move.stopFly()
		local hrp = getHRP()
		local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum then
			return
		end
		state.fly = true
		hum.PlatformStand = true
		local bv = Instance.new("BodyVelocity")
		bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
		bv.Velocity = Vector3.zero
		bv.Parent = hrp
		state.flyBv = bv
		local bg = Instance.new("BodyGyro")
		bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
		bg.P = 9e4
		bg.Parent = hrp
		state.flyBg = bg
		state.flyConn = RunService.RenderStepped:Connect(function()
			if not state.fly or Library.Unloaded then
				return
			end
			local h = getHRP()
			if not h or not state.flyBv or not state.flyBg then
				return
			end
			-- reattach after respawn
			if state.flyBv.Parent ~= h then
				state.flyBv.Parent = h
				state.flyBg.Parent = h
				local hu = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
				if hu then
					hu.PlatformStand = true
				end
			end
			local cam = workspace.CurrentCamera
			if not cam then
				return
			end
			state.flyBg.CFrame = cam.CFrame
			local dir = Vector3.zero
			if UserInputService:IsKeyDown(Enum.KeyCode.W) then
				dir += cam.CFrame.LookVector
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) then
				dir -= cam.CFrame.LookVector
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) then
				dir -= cam.CFrame.RightVector
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) then
				dir += cam.CFrame.RightVector
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
				dir += Vector3.new(0, 1, 0)
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
				dir -= Vector3.new(0, 1, 0)
			end
			if dir.Magnitude > 0 then
				state.flyBv.Velocity = dir.Unit * (state.flySpeed or 50)
			else
				state.flyBv.Velocity = Vector3.zero
			end
		end)
	end

	function Move.stopSpeed()
		state.speedBoost = false
		if state.speedConn then
			pcall(function()
				state.speedConn:Disconnect()
			end)
			state.speedConn = nil
		end
	end

	function Move.stopAntiAfk()
state.antiAfk = false
	state.antiLag = false
	state.antiGlow = false
		if state.antiAfkThread then
			pcall(task.cancel, state.antiAfkThread)
			state.antiAfkThread = nil
		end
	end

	function Move.startAntiAfk()
		if state.antiAfkThread then
			return
		end
		state.antiAfk = true
		state.antiAfkThread = task.spawn(function()
			local lastStamp = 0
			while state.antiAfk and not Library.Unloaded do
				task.wait(1)
				local now = os.clock()
				local interval = state.antiAfkInterval or 120
				if now - lastStamp >= interval then
					lastStamp = now
					local c = LP.Character
					local hrp = c and c:FindFirstChild("HumanoidRootPart")
					local hum = c and c:FindFirstChildOfClass("Humanoid")
					if hrp and hrp.Parent then
						local orig = hrp.CFrame
						hrp.CFrame = orig * CFrame.new(1, 0, 0)
						if hum then
							hum.Jump = true
						end
						task.wait(0.4)
						if hrp.Parent then
							hrp.CFrame = orig
						end
					end
				end
			end
			state.antiAfkThread = nil
		end)
	end

	function Move.startSpeed()
		if state.speedConn then
			return
		end
		state.speedBoost = true
		state.speedConn = RunService.Heartbeat:Connect(function()
			if not state.speedBoost or Library.Unloaded then
				return
			end
			local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
			if hum and not state.fly then
				hum.WalkSpeed = state.walkSpeed or 32
			end
		end)
	end

	function Move.stopNoclip()
		state.noclip = false
		if state.noclipConn then
			pcall(function()
				state.noclipConn:Disconnect()
			end)
			state.noclipConn = nil
		end
		for part, was in pairs(state.noclipParts) do
			if part and part.Parent then
				pcall(function()
					part.CanCollide = was
				end)
			end
		end
		table.clear(state.noclipParts)
	end

	function Move.startNoclip()
		if state.noclipConn then
			return
		end
		state.noclip = true
		state.noclipConn = RunService.Stepped:Connect(function()
			if not state.noclip or Library.Unloaded then
				return
			end
			local char = LP.Character
			if not char then
				return
			end
			for _, part in ipairs(char:GetDescendants()) do
				if part:IsA("BasePart") and part.CanCollide then
					if state.noclipParts[part] == nil then
						state.noclipParts[part] = true
					end
					part.CanCollide = false
				end
			end
		end)
	end

	function Move.stopAll()
		Move.stopFly()
		Move.stopSpeed()
		Move.stopNoclip()
		Move.stopAntiAfk()
	end
end

--========================================================
-- GRAPHICS (Anti-Lag + Disable Glow) - module
--========================================================
do
	local FX_TYPES = {
		"BloomEffect",
		"ColorCorrectionEffect",
		"DepthOfFieldEffect",
		"SunRaysEffect",
		"BlurEffect",
	}
	state.gfx = {}

	function state.gfx.stopLag()
		state.antiLag = false
		if state.antiLagThread then
			pcall(task.cancel, state.antiLagThread)
			state.antiLagThread = nil
		end
		restoreFx()
	end

	function restoreFx()
		for fx, was in pairs(state.fxSaved) do
			if fx and fx.Enabled ~= nil then
				pcall(function()
					fx.Enabled = was
				end)
			end
			state.fxSaved[fx] = nil
		end
	end

	function applyFx()
		local lg = game:GetService("Lighting")
		for _, typ in ipairs(FX_TYPES) do
			for _, fx in ipairs(lg:GetChildren()) do
				if fx.ClassName == typ then
					if state.fxSaved[fx] == nil then
						state.fxSaved[fx] = fx.Enabled
					end
					pcall(function()
						fx.Enabled = false
					end)
				end
			end
		end
	end

	function state.gfx.startLag()
		if state.antiLagThread then
			return
		end
		state.antiLag = true
		applyFx()
		state.antiLagThread = task.spawn(function()
			while state.antiLag and not Library.Unloaded do
				task.wait(4)
				applyFx()
			end
			state.antiLagThread = nil
		end)
	end

	function state.gfx.clearGlow()
		state.antiGlow = false
		if state.glowThread then
			pcall(task.cancel, state.glowThread)
			state.glowThread = nil
		end
		restoreGlow()
	end

	function restoreGlow()
		for part, sa in pairs(state.glowSurfaces) do
			if part and part.Parent and sa then
				pcall(function()
					sa.Parent = part
				end)
			end
			state.glowSurfaces[part] = nil
		end
		for part, pl in pairs(state.glowLights) do
			if part and part.Parent and pl then
				pcall(function()
					pl.Enabled = true
				end)
			end
			state.glowLights[part] = nil
		end
	end

	local function areasToGlow(fn)
		local function visit(folder)
			if not folder then
				return
			end
			for _, part in ipairs(folder:GetChildren()) do
				if part:IsA("BasePart") then
					fn(part)
				end
			end
		end
		visit(workspace:FindFirstChild("Things") and workspace.Things:FindFirstChild("Crystals"))
		visit(workspace:FindFirstChild("DroppedCrystals"))
	end

	function applyGlow()
		areasToGlow(function(part)
			local pl = part:FindFirstChildOfClass("PointLight")
			if pl then
				if state.glowLights[part] == nil then
					state.glowLights[part] = pl
				end
				pl.Enabled = false
			end
			local sa = part:FindFirstChildOfClass("SurfaceAppearance")
			if sa then
				if state.glowSurfaces[part] == nil then
					state.glowSurfaces[part] = sa
				end
				sa.Parent = nil
			end
		end)
	end

	function state.gfx.startGlow()
		if state.antiGlow then
			return
		end
		state.antiGlow = true
		applyGlow()
		state.glowThread = task.spawn(function()
			while state.antiGlow and not Library.Unloaded do
				task.wait(4)
				applyGlow()
			end
			state.glowThread = nil
		end)
	end
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
	Footer = "Qentury Hub | Mine A Mountain",
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
	-- Runes + Boulders in one tab; sections collapsed by default
	RuneBoulder = Window:AddTab("Rune & Boulder", "boxes", "Runes + Boulders"),
	Drop = Window:AddTab("Drop", "minus", "Drop crystals from bag"),
	Favorite = Window:AddTab("Favorite", "star", "Auto favorite crystals"),
	Shop = Window:AddTab("Shop", "shopping-cart", "Bombs & more"),
	Server = Window:AddTab("Server", "server", "Players / hop / rejoin"),
	Misc = Window:AddTab("Misc", "shield", "Godmode / fall / ragdoll"),
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
	for _ = 1, 6 do
		task.wait(0.25)
		if Library.Unloaded then
			break
		end
		forceFullWidthTabs()
	end
	while not Library.Unloaded do
		task.wait(2)
		forceFullWidthTabs()
	end
end)

-- --- Main controls (from qentury v4.2.3 Main tab) ---
Main:AddToggle("AutoMineV2", {
	Text = "Auto Pickup (mine+drop)",
	Default = false,
	Tooltip = "Donnie-style burst grab: HoldComplete + fireprox MaxDist 1000. No bag-full stop. No TP.",
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
	Tooltip = "Vacuum near -> TP richest Value$ -> instant mine.",
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

Main:AddToggle("AutoFarm", {
	Text = "Auto Farm (peak dig)",
	Default = false,
	Tooltip = "Peak -> dig down. Equip pickaxe yourself (no auto equip). Vacuum = Auto Pickup. Auto-Sell if ON.",
	Callback = function(v)
		if v then
			state.autoFarm = true
			startAutoFarm()
			Library:Notify({
				Title = "Auto Farm",
				Description = "ON - equip pickaxe, peak dig",
				Time = 2,
			})
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
		if state.autoFarm then
			task.wait(0.25)
		else
			task.wait(2)
		end
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
	Tooltip = "Filter pickup only. S<8kg / M?8 / L?30 / XL?90 / ?",
	Callback = function(v)
		state.mineMinSize = sizeLabelToRank(v)
	end,
})

Main:AddDropdown("MineMinLuck", {
	Text = "Min Luck % (Auto-Mine)",
	Values = { "1%", "50%", "100%", "200%", "250%", "500%", "1000%" },
	Default = 1,
	Multi = false,
	Tooltip = "Skip crystals with luck below this (Auto Pickup + Auto Pickup TP).",
	Callback = function(v)
		local n = tonumber((tostring(v or "1%"):gsub("%%", ""))) or 1
		state.mineMinLuckPct = n
	end,
})

Main:AddDropdown("MineMinValue", {
	Text = "Min Value (Auto-Mine)",
	Values = { "0", "1b", "2b", "3b", "4b", "5b" },
	Default = "0",
	Multi = false,
	Tooltip = "Skip crystals worth less than this (Auto Pickup + TP + Farm). 0 = all.",
	Callback = function(v)
		local s = tostring(v or "0"):lower()
		local n = tonumber((s:gsub("b", ""))) or 0
		state.mineMinValue = s:find("b") and n * 1e9 or n
	end,
})

Main:AddLabel("Must stand near crystal for Auto Pickup (no TP).")

Main:AddToggle("AutoSell", {
	Text = "Auto-Sell (At Capacity)",
	Default = false,
	Tooltip = "When bag kg >= % capacity -> sell zone -> SellRequest all.",
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
					and string.format("Sold %s / +%s", tostring(info.sold), formatMoney(info.cashDelta or 0))
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
	Tooltip = "Donnie-style label: rarity / name / $ / kg / dist / luck / size. Filter = Rarity + Min Size.",
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
			Description = string.format("%s / top %d", TIER_NAMES[state.listTier] or v, math.min(n, 10)),
			Time = 2,
		})
	end,
})

Main:AddDropdown("EspMinSize", {
	Text = "Min Size (ESP + List)",
	Values = SIZE_LABELS,
	Default = 1,
	Multi = false,
	Tooltip = "Hanya tampilkan crystal size ? ini di ESP & list. S/M/L/XL/?",
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

Main:AddLabel("Crystal list (Top 10) - click = TP")

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
-- RUNES TAB
--========================================================
-- groupbox args: title, icon, visible, collapsed, disableCollapse
local RBox = Tabs.RuneBoulder:AddLeftGroupbox("Runes", "star", true, true)

RBox:AddToggle("RuneESP", {
	Text = "Rune ESP",
	Default = false,
	Callback = function(v)
		state.runeEsp = v
		if v then
			applyRuneESP()
			task.spawn(function()
				while state.runeEsp and not Library.Unloaded do
					applyRuneESP()
					task.wait(1.5)
				end
			end)
		else
			clearRuneESP()
		end
	end,
})

RBox:AddDropdown("RuneSelect", {
	Text = "Runes (filter)",
	Values = RUNE_NAMES,
	Default = RUNE_NAMES,
	Multi = true,
	Searchable = true,
	Tooltip = "Pilih rune tampil/pickup. Kosong = semua.",
	Callback = function(v)
		syncRuneSelected(v)
		refreshRunes()
		if state.runeEsp then
			applyRuneESP()
		end
	end,
})

RBox:AddToggle("AutoPickupRune", {
	Text = "Auto Pickup Runes",
	Default = false,
	Tooltip = "Hybrid: vacuum ~30 stud / 0.25s / burst 6 / firePrompt dedup. No TP (pakai Auto TP Rune for far).",
	Callback = function(v)
		state.autoPickupRune = v
		if v then
			startAutoPickupRune()
			Library:Notify({ Title = "Rune Pickup", Description = "ON / vacuum 30", Time = 2 })
		else
			Library:Notify({ Title = "Rune Pickup", Description = "OFF", Time = 2 })
		end
	end,
})

RBox:AddToggle("AutoTpRune", {
	Text = "Auto TP Rune",
	Default = false,
	Tooltip = "TP tiap rune terpilih -> firePrompt -> repeat (far runes).",
	Callback = function(v)
		if v then
			startAutoTpRune()
			Library:Notify({ Title = "Auto TP Rune", Description = "ON", Time = 2 })
		else
			stopAutoTpRune()
			Library:Notify({ Title = "Auto TP Rune", Description = "OFF", Time = 2 })
		end
	end,
})

RBox:AddButton({
	Text = "Pickup Nearby Now",
	Func = function()
		Library:Notify({
			Title = "Rune Pickup",
			Description = "fired " .. tostring(pickupNearbyRunes(true)),
			Time = 2,
		})
	end,
}):AddButton({
	Text = "Refresh List",
	Func = function()
		Library:Notify({
			Title = "Runes",
			Description = tostring(refreshRunes()) .. " found",
			Time = 2,
		})
	end,
})

runeScroll = buildRuneListUI()
RBox:AddUIPassthrough("RuneListUI", {
	Instance = runeScroll,
	Height = RUNE_LIST_H,
})

--========================================================
-- BOULDERS TAB
--========================================================
local BBox = Tabs.RuneBoulder:AddLeftGroupbox("Boulders", "box", true, true)

local boulderStatusLabel = BBox:AddLabel("World: ? / Listed: ?", true)

local function updateBoulderStatus(listed)
	local world = Boulders.folderCount()
	local n = listed
	if n == nil then
		n = Boulders.count()
	end
	local text
	if world == 0 then
		text = "World: 0 models / dig/stream mountain or hop server"
	else
		text = string.format("World: %d / Listed (filter): %d", world, n)
	end
	pcall(function()
		if boulderStatusLabel and boulderStatusLabel.SetText then
			boulderStatusLabel:SetText(text)
		end
	end)
	return n
end

BBox:AddToggle("BoulderESP", {
	Text = "Boulder ESP",
	Default = false,
	Callback = function(v)
		state.boulderEsp = v
		if v then
			Boulders.applyESP()
			task.spawn(function()
				while state.boulderEsp and not Library.Unloaded do
					Boulders.applyESP()
					task.wait(2)
				end
			end)
		else
			Boulders.clearESP()
		end
	end,
})

BBox:AddDropdown("BoulderSelect", {
	Text = "Boulders (filter)",
	Values = Boulders.NAMES,
	Default = Boulders.NAMES,
	Multi = true,
	Searchable = true,
	Tooltip = "Pilih tipe boulder. Kosong = semua.",
	Callback = function(v)
		Boulders.syncSelected(v)
		updateBoulderStatus(Boulders.refresh())
		if state.boulderEsp then
			Boulders.applyESP()
		end
	end,
})

BBox:AddToggle("AutoFarmBoulder", {
	Text = "Auto Farm Boulder",
	Default = false,
	Tooltip = "Nearest selected boulder -> break -> drain runes -> next. Empty: TP leftover runes.",
	Callback = function(v)
		if v then
			Boulders.start()
			Library:Notify({
				Title = "Boulder Farm",
				Description = "ON - break -> drain runes -> next",
				Time = 2,
			})
		else
			Boulders.stop()
			Library:Notify({ Title = "Boulder Farm", Description = "OFF", Time = 2 })
		end
	end,
})

BBox:AddToggle("PickupAfterBoulder", {
	Text = "Pickup Crystal After Boulder",
	Default = false,
	Tooltip = "When Auto Farm Boulder clears (no boulder + no rune): TP-pickup crystals per Main tab filters, then rejoin if Auto Rejoin.",
	Callback = function(v)
		state.pickupAfterBoulder = v
		Library:Notify({
			Title = "Pickup Crystal",
			Description = v and "ON - crystal phase after boulder clear" or "OFF",
			Time = 2,
		})
	end,
})

BBox:AddToggle("AutoRejoin", {
	Text = "Auto Rejoin",
	Default = false,
	Tooltip = "Flag only. When Auto Farm Boulder finishes (no boulder + no rune) -> rejoin same place (Server tab logic).",
	Callback = function(v)
		state.autoRejoin = v
		Library:Notify({
			Title = "Auto Rejoin",
			Description = v and "ON - rejoin after farm clear" or "OFF",
			Time = 2,
		})
	end,
})

BBox:AddButton({
	Text = "Break Nearest Now",
	Func = function()
		local m = Boulders.nearest()
		if not m then
			Library:Notify({ Title = "Break", Description = "No boulder", Time = 2 })
			return
		end
		task.spawn(function()
			state._forceBreak = true
			local ok, msg = Boulders.breakOnce(m)
			state._forceBreak = false
			Library:Notify({
				Title = ok and "Break" or "Fail",
				Description = tostring(msg),
				Time = 2,
			})
		end)
	end,
}):AddButton({
	Text = "Refresh List",
	Func = function()
		local n = updateBoulderStatus(Boulders.refresh())
		Library:Notify({
			Title = "Boulders",
			Description = string.format("%d listed / %d in world", n, Boulders.folderCount()),
			Time = 2,
		})
	end,
})

do
	local s = Boulders.buildListUI()
	Boulders.setScroll(s)
	BBox:AddUIPassthrough("BoulderListUI", {
		Instance = s,
		Height = Boulders.LIST_H,
	})
end

task.defer(function()
	task.wait(0.3)
	updateBoulderStatus(Boulders.refresh())
end)

task.spawn(function()
	while not Library.Unloaded do
		task.wait(4)
		pcall(updateBoulderStatus)
	end
end)

--========================================================
-- MISC (character protections)
--========================================================
local MiscBox = Tabs.Misc:AddLeftGroupbox("Combat / Fall", "shield")

MiscBox:AddToggle("Godmode", {
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

MiscBox:AddToggle("NoFallDmg", {
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

MiscBox:AddToggle("AntiRagdoll", {
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

local MoveBox = Tabs.Misc:AddLeftGroupbox("Movement", "gauge")

MoveBox:AddToggle("Fly", {
	Text = "Fly",
	Default = false,
	Tooltip = "WASD + Space/Ctrl. Camera-relative.",
	Callback = function(v)
		if v then
			Move.startFly()
			Library:Notify({ Title = "Fly", Description = "ON", Time = 2 })
		else
			Move.stopFly()
			Library:Notify({ Title = "Fly", Description = "OFF", Time = 2 })
		end
	end,
})

MoveBox:AddSlider("FlySpeed", {
	Text = "Fly speed",
	Default = 50,
	Min = 10,
	Max = 200,
	Rounding = 0,
	Callback = function(v)
		state.flySpeed = v
	end,
})

MoveBox:AddToggle("Noclip", {
	Text = "Noclip",
	Default = false,
	Tooltip = "Disable character part collisions.",
	Callback = function(v)
		if v then
			Move.startNoclip()
			Library:Notify({ Title = "Noclip", Description = "ON", Time = 2 })
		else
			Move.stopNoclip()
			Library:Notify({ Title = "Noclip", Description = "OFF", Time = 2 })
		end
	end,
})

MoveBox:AddToggle("SpeedBoost", {
	Text = "Speed boost",
	Default = false,
	Tooltip = "Locks WalkSpeed (off while flying).",
	Callback = function(v)
		if v then
			Move.startSpeed()
			Library:Notify({ Title = "Speed", Description = "ON", Time = 2 })
		else
			Move.stopSpeed()
			Library:Notify({ Title = "Speed", Description = "OFF", Time = 2 })
		end
	end,
})

MoveBox:AddSlider("WalkSpeed", {
	Text = "Walk speed",
	Default = 32,
	Min = 16,
	Max = 200,
	Rounding = 0,
	Callback = function(v)
		state.walkSpeed = v
	end,
})

MoveBox:AddDivider()

MoveBox:AddToggle("AntiAfk", {
	Text = "Anti AFK",
	Default = false,
	Tooltip = "Nudge HRP 1 stud + jump every interval (default 120s). Keeps the server from kicking you idle.",
	Callback = function(v)
		if v then
			Move.startAntiAfk()
			Library:Notify({ Title = "Anti AFK", Description = "ON", Time = 2 })
		else
			Move.stopAntiAfk()
			Library:Notify({ Title = "Anti AFK", Description = "OFF", Time = 2 })
		end
	end,
})

MoveBox:AddSlider("AntiAfkInterval", {
	Text = "Anti AFK interval",
	Default = 120,
	Min = 30,
	Max = 300,
	Rounding = 0,
	Suffix = "s",
	Callback = function(v)
		state.antiAfkInterval = v
	end,
})

--========================================================
-- GRAPHIC TAB (Anti-Lag + Disable Glow)
--========================================================
local GraphicBox = Tabs.Misc:AddLeftGroupbox("Graphic", "sun")
GraphicBox:AddToggle("DestroyLowRarity", {
	Text = "Destroy World Crystals by Rarity",
	Default = false,
	Tooltip = "Client-side Destroy() on world crystals (Things.Crystals / DroppedCrystals) with Tier <= max. Reduces lag. Permanent!",
	Callback = function(v)
		if v then
			state.CrystalDestroy.start()
		else
			state.CrystalDestroy.stop()
		end
	end,
})
GraphicBox:AddDropdown("DestroyMaxRarity", {
	Text = "Destroy max rarity",
	Values = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" },
	Default = "Mythic",
	Multi = false,
	Tooltip = "Crystals with rarity up to (and including) this are destroyed.",
	Callback = function(v)
		state.destroyMaxTier = rarityToTier(v)
	end,
})
GraphicBox:AddToggle("AntiLag", {
	Text = "Anti Lag",
	Default = false,
	Tooltip = "Disables Lighting FX (Bloom, ColorCorrection, DepthOfField, SunRays, Blur) for FPS.",
	Callback = function(v)
		if v then
			state.gfx.startLag()
			Library:Notify({ Title = "Anti Lag", Description = "ON", Time = 2 })
		else
			state.gfx.stopLag()
			Library:Notify({ Title = "Anti Lag", Description = "OFF", Time = 2 })
		end
	end,
})
GraphicBox:AddToggle("DisableGlow", {
		Text = "Disable Glow",
		Default = false,
		Tooltip = "Turns off PointLights and SurfaceAppearances on crystals. Saves FPS.",
		Callback = function(v)
			if v then
				state.gfx.startGlow()
				Library:Notify({ Title = "Disable Glow", Description = "ON", Time = 2 })
			else
				state.gfx.clearGlow()
				Library:Notify({ Title = "Disable Glow", Description = "OFF", Time = 2 })
			end
		end,
	})

--========================================================
-- SHOP TAB (Bombs section)
--========================================================
local BombBox = Tabs.Shop:AddLeftGroupbox("Bombs", "bomb")

local bombLabels = Bombs.dropdownLabels()
local classicLabel = bombLabels[1] or "Classic Bomb ($50.0K)"

BombBox:AddDropdown("BombSelect", {
	Text = "Bombs to buy (multi)",
	Values = #bombLabels > 0 and bombLabels or Bombs.ORDER,
	Default = { classicLabel },
	Multi = true,
	Searchable = true,
	Tooltip = "Multi-select. Auto-buy prefers rarer bombs first when in stock.",
	Callback = function(v)
		Bombs.syncTargets(v)
	end,
})

BombBox:AddToggle("AutoBuyBomb", {
	Text = "Auto Buy when in stock",
	Default = false,
	Tooltip = "Buys selected bombs while shop stock + cash available (rarest first).",
	Callback = function(v)
		if v then
			Bombs.syncTargets(Options.BombSelect and Options.BombSelect.Value)
			Bombs.start()
			Library:Notify({ Title = "Auto Buy Bomb", Description = "ON", Time = 2 })
		else
			Bombs.stop()
			Library:Notify({ Title = "Auto Buy Bomb", Description = "OFF", Time = 2 })
		end
	end,
})

task.defer(function()
	task.wait(0.25)
	pcall(function()
		Bombs.syncTargets(Options.BombSelect and Options.BombSelect.Value)
	end)
end)

--========================================================
-- SHOP / RADARS section
--========================================================
local RadarBox = Tabs.Shop:AddLeftGroupbox("Radars", "radar")

local radarLabels = Radars.dropdownLabels()
local crystalRadarLabel = radarLabels[1] or "Crystal Radar ($300K)"

RadarBox:AddDropdown("RadarSelect", {
	Text = "Radars to buy (multi)",
	Values = #radarLabels > 0 and radarLabels or Radars.IDS,
	Default = { crystalRadarLabel },
	Multi = true,
	Searchable = true,
	Tooltip = "Multi-select. Auto-buy prefers rarer radars first when in stock.",
	Callback = function(v)
		Radars.syncTargets(v)
	end,
})

RadarBox:AddToggle("AutoBuyRadar", {
	Text = "Auto Buy when in stock",
	Default = false,
	Tooltip = "Buys selected radars while shop stock + cash available (rarest first).",
	Callback = function(v)
		if v then
			Radars.syncTargets(Options.RadarSelect and Options.RadarSelect.Value)
			Radars.start()
			Library:Notify({ Title = "Auto Buy Radar", Description = "ON", Time = 2 })
		else
			Radars.stop()
			Library:Notify({ Title = "Auto Buy Radar", Description = "OFF", Time = 2 })
		end
	end,
})

task.defer(function()
	task.wait(0.25)
	pcall(function()
		Radars.syncTargets(Options.RadarSelect and Options.RadarSelect.Value)
	end)
end)

-- Upgrades section under Radars (collapsed by default)
-- AddLeftGroupbox(title, icon, visible, collapsed)
local UpgBox = Tabs.Shop:AddLeftGroupbox("Upgrades", "arrow-up", true, true)
UpgBox:AddToggle("AutoUpgradeCarry", {
	Text = "Auto-Upgrade Carry +10kg",
	Default = false,
	Tooltip = "Buy Carry +10kg (Weight tier 3) when cash >= 115% of price.",
	Callback = function(v)
		if v then
			Upgrades.start()
		else
			Upgrades.stop()
		end
	end,
})
Upgrades.buildUI(UpgBox)

--========================================================
-- FAVORITE TAB
--========================================================
local FavBox = Tabs.Favorite:AddLeftGroupbox("Favorite", "star")

FavBox:AddLabel("ToggleFavorite / server truth (Inventory.Crystals)", true)

local favStatusLabel = FavBox:AddLabel(Fav.statusText(), true)

local function refreshFavStatus()
	pcall(function()
		if favStatusLabel and favStatusLabel.SetText then
			favStatusLabel:SetText(Fav.statusText())
		end
	end)
end

FavBox:AddSlider("FavLuckMin", {
	Text = "Min Luck %",
	Default = 4,
	Min = 0,
	Max = 5000,
	Rounding = 0,
	Suffix = "%",
	Tooltip = "Auto-favorite crystals with luck >= this percent (0-5000).",
	Callback = function(v)
		state.favLuckMin = v
		refreshFavStatus()
	end,
})

FavBox:AddToggle("AutoFavLuck", {
	Text = "Auto Favorite by Luck",
	Default = false,
	Tooltip = "Loop: favorite bag tools with luck ? min %.",
	Callback = function(v)
		state.autoFavLuck = v
		if v then
			Fav.start()
			Library:Notify({ Title = "Favorite", Description = "Luck auto ON", Time = 2 })
		else
			if not (state.autoFavRarity or state.autoFavWeight) then
				Fav.stop()
			end
			Library:Notify({ Title = "Favorite", Description = "Luck auto OFF", Time = 2 })
		end
		refreshFavStatus()
	end,
})

FavBox:AddDivider()

FavBox:AddDropdown("FavRaritySelect", {
	Text = "Rarity filter",
	Values = TIER_LABELS,
	Default = { "L / Legendary", "M / Mythic" },
	Multi = true,
	Searchable = false,
	Tooltip = "Tiers used by Auto Favorite by Rarity.",
	Callback = function(v)
		Fav.syncRarity(v)
		refreshFavStatus()
	end,
})

FavBox:AddToggle("AutoFavRarity", {
	Text = "Auto Favorite by Rarity",
	Default = false,
	Tooltip = "Loop: favorite bag tools matching selected rarities.",
	Callback = function(v)
		state.autoFavRarity = v
		if v then
			Fav.syncRarity(Options.FavRaritySelect and Options.FavRaritySelect.Value)
			Fav.start()
			Library:Notify({ Title = "Favorite", Description = "Rarity auto ON", Time = 2 })
		else
			if not (state.autoFavLuck or state.autoFavWeight) then
				Fav.stop()
			end
			Library:Notify({ Title = "Favorite", Description = "Rarity auto OFF", Time = 2 })
		end
		refreshFavStatus()
	end,
})

FavBox:AddDivider()

FavBox:AddDropdown("FavWeightSelect", {
	Text = "Min Weight (Auto-Fav)",
	Values = { SIZE_LABELS[4], SIZE_LABELS[5], SIZE_LABELS[6], SIZE_LABELS[7], SIZE_LABELS[8], SIZE_LABELS[9] },
	Default = 1,
	Multi = false,
	Searchable = false,
	Tooltip = "Favorite tools whose crystal size is at least this (XL+).",
	Callback = function(v)
		state.favMinWeight = sizeLabelToRank(v)
		refreshFavStatus()
	end,
})

FavBox:AddToggle("AutoFavWeight", {
	Text = "Auto Favorite by Weight",
	Default = false,
	Tooltip = "Loop: favorite bag tools with crystal size ? min weight.",
	Callback = function(v)
		state.autoFavWeight = v
		if v then
			state.favMinWeight = sizeLabelToRank(Options.FavWeightSelect and Options.FavWeightSelect.Value) or 4
			Fav.start()
			Library:Notify({ Title = "Favorite", Description = "Weight auto ON", Time = 2 })
		else
			if not (state.autoFavLuck or state.autoFavRarity) then
				Fav.stop()
			end
			Library:Notify({ Title = "Favorite", Description = "Weight auto OFF", Time = 2 })
		end
		refreshFavStatus()
	end,
})

FavBox:AddDivider()

FavBox:AddButton({
	Text = "Favorite All in Bag",
	Func = function()
		local n = Fav.favoriteAll()
		refreshFavStatus()
		Library:Notify({ Title = "Favorite All", Description = tostring(n) .. " tools", Time = 2 })
	end,
}):AddButton({
	Text = "Unfavorite All in Bag",
	Func = function()
		local n = Fav.unfavoriteAll()
		refreshFavStatus()
		Library:Notify({ Title = "Unfavorite All", Description = tostring(n) .. " tools", Time = 2 })
	end,
})

task.spawn(function()
	while not Library.Unloaded do
		task.wait(1)
		if state.autoFavLuck or state.autoFavRarity then
			refreshFavStatus()
		end
	end
end)

--========================================================
-- DROP TAB
--========================================================
local DropBox = Tabs.Drop:AddLeftGroupbox("Crystal", "gem", true, true)

DropBox:AddLabel("CrystalDropRequest / not sell / skip Favorited", true)

state.dropStatusLabel = DropBox:AddLabel(Drop.statusText(), true)

function state.refreshDropStatus()
	pcall(function()
		if state.dropStatusLabel and state.dropStatusLabel.SetText then
			state.dropStatusLabel:SetText(Drop.statusText())
		end
	end)
end

state.dropAllConfirm = false

DropBox:AddToggle("DropAll", {
	Text = "Drop All (skip Favorited)",
	Default = false,
	Tooltip = "Dump every non-favorited crystal. Toggle twice to confirm.",
	Callback = function(v)
		if v then
			if not state.dropAllConfirm then
				state.dropAllConfirm = true
				Library:Notify({
					Title = "Drop All - confirm",
					Description = "Toggle ON again within 5s to start",
					Time = 4,
				})
				task.delay(5, function()
					state.dropAllConfirm = false
				end)
				task.defer(function()
					pcall(function()
						if Toggles.DropAll then
							Toggles.DropAll:SetValue(false)
						end
					end)
				end)
				return
			end
			state.dropAllConfirm = false
			pcall(function()
				if Toggles.DropValue and Toggles.DropValue.Value then
					Toggles.DropValue:SetValue(false)
				end
			end)
			Drop.start("all")
			Library:Notify({ Title = "Drop All", Description = "ON - skip Favorited", Time = 2 })
		else
			if state.dropMode == "all" then
				Drop.stop()
			end
			Library:Notify({ Title = "Drop All", Description = "OFF", Time = 2 })
		end
		state.refreshDropStatus()
	end,
})

local RuneBox = Tabs.Drop:AddLeftGroupbox("Rune", "gem", true, true)
RuneBox:AddDropdown("RuneDropSelect", {
	Text = "Rune to drop",
	Values = { "All", "Luck Rune", "Haste Rune", "Storm Rune", "Fortune Rune", "Detonation Rune", "Preservation Rune", "Weight Rune", "Excavator Rune", "Warmth Rune", "Colossus Rune" },
	Default = "All",
	Multi = false,
	Tooltip = "Which rune type to drop. All = every rune in backpack.",
	Callback = function(v)
		state.runeDropSel = state.DropRune and state.DropRune.map and state.DropRune.map[v]
	end,
})
RuneBox:AddSlider("RuneDropCount", {
	Text = "Runes to drop",
	Default = 1,
	Min = 1,
	Max = 500,
	Rounding = 0,
	Tooltip = "Drop this many of each selected rune (1 fire = 1 rune), then auto-stop. All = N per rune type.",
	Callback = function(v)
		state.runeDropCount = v
	end,
})
RuneBox:AddToggle("RuneDrop", {
	Text = "Drop Runes (auto)",
	Default = false,
	Tooltip = "Drop RuneDropCount of each selected rune (All = N per type), then auto-stop.",
	Callback = function(v)
		if v then
			state.DropRune.start()
		else
			state.DropRune.stop()
		end
	end,
})

DropBox:AddDivider()

DropBox:AddSlider("DropValueTargetB", {
	Text = "Drop value target",
	Default = 1,
	Min = 1,
	Max = 500,
	Rounding = 0,
	Suffix = "B $",
	Tooltip = "Drop non-fav crystals until total dropped $ ? this (1-500 billion).",
	Callback = function(v)
		state.dropValueTargetB = v
		state.refreshDropStatus()
	end,
})

DropBox:AddDropdown("DropValueSort", {
	Text = "Value drop order",
	Values = { "Cheapest first", "Most expensive first" },
	Default = 1,
	Multi = false,
	Tooltip = "Which crystals drop first when value target is ON.",
	Callback = function(v)
		state.dropSortExpensive = (v == "Most expensive first")
		state.refreshDropStatus()
	end,
})

DropBox:AddToggle("DropValue", {
	Text = "Drop until value target",
	Default = false,
	Tooltip = "Skip Favorited / sort by order above / stop when dropped sum ? target.",
	Callback = function(v)
		if v then
			pcall(function()
				if Toggles.DropAll and Toggles.DropAll.Value then
					Toggles.DropAll:SetValue(false)
				end
			end)
			Drop.start("value")
			local sort = state.dropSortExpensive and "expensive" or "cheap"
			Library:Notify({
				Title = "Drop Value",
				Description = string.format("ON - %s / target %sB", sort, tostring(state.dropValueTargetB or 1)),
				Time = 2,
			})
		else
			if state.dropMode == "value" then
				Drop.stop()
			end
			Library:Notify({ Title = "Drop Value", Description = "OFF", Time = 2 })
		end
		state.refreshDropStatus()
	end,
})

DropBox:AddSlider("DropDelay", {
	Text = "Drop delay",
	Default = 15,
	Min = 5,
	Max = 50,
	Rounding = 0,
	Suffix = " = ms/100",
	Tooltip = "15 = 0.15s between drops. Lower = faster.",
	Callback = function(v)
		state.dropDelay = v / 100
	end,
})

task.spawn(function()
	while not Library.Unloaded do
		task.wait(0.5)
		if state.dropMode then
			state.refreshDropStatus()
		end
	end
end)

--========================================================
-- SERVER TAB
--========================================================
local ServerPlayers = Tabs.Server:AddLeftGroupbox("Players", "users")
local playerNames = Server.playerNames()

ServerPlayers:AddDropdown("ServerPlayer", {
	Text = "Player",
	Values = playerNames,
	Default = playerNames[1],
	Multi = false,
	Searchable = true,
})

ServerPlayers:AddButton({
	Text = "Refresh Players",
	Func = function()
		local vals = Server.playerNames()
		pcall(function()
			local dd = Options.ServerPlayer
			if dd then
				if dd.SetValues then
					dd:SetValues(vals)
				elseif dd.Values then
					dd.Values = vals
				end
				if dd.SetValue and vals[1] then
					dd:SetValue(vals[1])
				end
			end
		end)
		Library:Notify({ Title = "Players", Description = tostring(#vals) .. " listed", Time = 2 })
	end,
})

ServerPlayers:AddButton({
	Text = "Teleport to Player",
	Func = function()
		local name = Options.ServerPlayer and Options.ServerPlayer.Value
		local ok, err = Server.teleportTo(name)
		Library:Notify({
			Title = "TP Player",
			Description = ok and ("-> " .. tostring(name)) or tostring(err),
			Time = 2,
		})
	end,
})

local ServerAct = Tabs.Server:AddLeftGroupbox("Server Actions", "server")

ServerAct:AddButton({
	Text = "Rejoin",
	Func = function()
		local ok, err = Server.rejoin()
		if not ok then
			Library:Notify({ Title = "Rejoin", Description = tostring(err), Time = 3 })
		end
	end,
})

ServerAct:AddButton({
	Text = "Hop Server",
	Func = function()
		local ok, err = Server.hop()
		if not ok then
			Library:Notify({ Title = "Hop", Description = tostring(err), Time = 3 })
		end
	end,
})

ServerAct:AddButton({
	Text = "Go Home",
	Func = function()
		local ok, err = Server.goHome()
		Library:Notify({
			Title = "Go Home",
			Description = ok and "OK" or tostring(err),
			Time = 2,
		})
	end,
})

ServerAct:AddButton({
	Text = "Reset Character",
	Func = function()
		local ok, err = Server.resetCharacter()
		if not ok then
			Library:Notify({ Title = "Reset", Description = tostring(err), Time = 2 })
		end
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
	-- explicit flags (clarity + safety if module stop order changes)
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
	state.fly = false
	state.speedBoost = false
	state.noclip = false
	state.antiAfk = false
	state.runeEsp = false
	state.autoPickupRune = false
	state.autoTpRune = false
	state.boulderEsp = false
	state.autoBreak = false
	state._forceBreak = false
	state.pickupAfterBoulder = false
	state.dropMode = nil
	state.autoFavLuck = false
	state.autoFavRarity = false
	state.autoFavWeight = false
	state.autoBuyBomb = false
	Boulders.stop()
	Drop.stop()
	Fav.stop()
	Bombs.stop()
	Radars.stop()
	Move.stopAll()
	state.gfx.stopLag()
	state.gfx.clearGlow()
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
	clearRuneESP()
	Boulders.clearESP()
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
	pcall(function()
		local luckV = Options.MineMinLuck and Options.MineMinLuck.Value
		state.mineMinLuckPct = tonumber((tostring(luckV or "1%"):gsub("%%", ""))) or 1
	end)
	pcall(function()
		local valV = Options.MineMinValue and Options.MineMinValue.Value
		local s = tostring(valV or "0"):lower()
		local n = tonumber((s:gsub("b", ""))) or 0
		state.mineMinValue = s:find("b") and n * 1e9 or n
	end)
	pcall(function()
		state.antiAfkInterval = Options.AntiAfkInterval and Options.AntiAfkInterval.Value or 120
	end)
	pcall(function()
		if Options.AntiLag and Options.AntiLag.Value then
			state.gfx.startLag()
		end
	end)
	pcall(function()
		if Options.DisableGlow and Options.DisableGlow.Value then
			state.gfx.startGlow()
		end
	end)
	state.listMinSize = sizeLabelToRank(Options.EspMinSize and Options.EspMinSize.Value) or 1
	pcall(function()
		syncRuneSelected(Options.RuneSelect and Options.RuneSelect.Value)
	end)
	pcall(function()
		Boulders.syncSelected(Options.BoulderSelect and Options.BoulderSelect.Value)
	end)
	pcall(function()
		state.pickupAfterBoulder = Toggles.PickupAfterBoulder and Toggles.PickupAfterBoulder.Value == true or false
	end)
	pcall(function()
		if Toggles.AutoUpgradeCarry and Toggles.AutoUpgradeCarry.Value == true then
			Upgrades.start()
		end
	end)
	pcall(function()
		if Toggles.DestroyLowRarity and Toggles.DestroyLowRarity.Value == true then
			state.CrystalDestroy.start()
		end
	end)
	pcall(refreshCrystalList)
	pcall(refreshRunes)
	pcall(function()
		updateBoulderStatus(Boulders.refresh())
	end)
	pcall(function()
		Fav.syncRarity(Options.FavRaritySelect and Options.FavRaritySelect.Value)
	end)
	pcall(function()
		state.favMinWeight = sizeLabelToRank(Options.FavWeightSelect and Options.FavWeightSelect.Value) or 4
	end)
	pcall(refreshFavStatus)
	pcall(Upgrades.refreshPrices)
	task.spawn(function()
		while not Library.Unloaded do
			task.wait(3)
			pcall(refreshCrystalList)
		end
	end)
end)

Library:Notify({
	Title = "Qentury Hub",
	Description = "Qentury Hub | Mine A Mountain",
	Time = 4,
})
