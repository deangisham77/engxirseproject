--========================================================
-- QENTURY HUB v4-tes — Mine a Mountain
-- + Shovels / Backpacks / Boulders / Runes (1 file, loadstring chunk)
--========================================================
pcall(function()
	if getgenv().MaMQenturyCleanup then
		getgenv().MaMQenturyCleanup()
	end
	if getgenv().MaMObsidianCleanup then
		getgenv().MaMObsidianCleanup()
	end
	if getgenv().MaMTestCleanup then
		getgenv().MaMTestCleanup()
	end
	if getgenv().MaMV4ExtrasCleanup then
		getgenv().MaMV4ExtrasCleanup()
	end
	if getgenv().MaMV3ExtrasCleanup then
		getgenv().MaMV3ExtrasCleanup()
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

local repo = "https://raw.githubusercontent.com/uhfork/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

-- game formula: ReplicatedStorage.Modules.Crystals.CrystalLuck
local RARITY_MULT = { 1, 1.6, 2.6, 4.2, 7, 12 }
local LUCK_BASE = 0.00045
local LUCK_KG_CAP = 500
local LUCK_WEIGHT_EXP = 0.5
local BOMB_LUCK_MULT = 3
local MUTATION_LUCK = {
	Frost = 1.4,
	Fire = 1.4,
	Thunder = 1.5,
	Starfall = 1.3,
	Aurora = 2.2,
	Radioactive = 2,
	Poison = 1.5,
	Wet = 1,
}

local function mutationLuckMult(mut)
	if type(mut) ~= "string" or mut == "" then
		return 1
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

local TIER_NAMES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
local TIER_BADGE = { "C", "U", "R", "E", "L", "M" }
-- dropdown labels (NexHub letters + full name)
local TIER_LABELS = {
	"C · Common",
	"U · Uncommon",
	"R · Rare",
	"E · Epic",
	"L · Legendary",
	"M · Mythic",
}
local TIER_COLORS = {
	Color3.fromRGB(200, 200, 200), -- C
	Color3.fromRGB(80, 220, 120), -- U
	Color3.fromRGB(70, 140, 255), -- R
	Color3.fromRGB(170, 90, 255), -- E
	Color3.fromRGB(255, 80, 180), -- L
	Color3.fromRGB(255, 60, 60), -- M
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
	-- "L · Legendary" / "C · Common"
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

local state = {
	autoMineV2 = false, -- Auto Pickup (mine+drop, instant)
	autoMineTPV2 = false, -- Auto Pickup TP
	mineV2Thread = nil,
	mineTPV2Thread = nil,
	esp = false,
	mineMinTier = 1,
	listTier = 5, -- Legendary default (matches common hunting)
	listSortBy = "money", -- "money" or "luck"
	crystalMap = {}, -- label -> part
	highlights = {}, -- part -> Highlight
	charEsp = false,
	charEspBillboards = {}, -- player -> BillboardGui
	autoBuyBomb = false,
	bombTargets = { ClassicBomb = true }, -- multi-select map id -> true
	bombStock = {},
	bombThread = nil,
	autoSell = false,
	sellAtPct = 95, -- % of CarryWeight
	sellThread = nil,
	sellBusy = false,
	autoBuyPick = false,
	pickThread = nil,
	noFallDmg = true,
	fallCap = -72, -- studs/s (threshold hardlanding ~75)
	fallConn = nil,
	antiAfk = true,
	antiAfkThread = nil,
	antiAfkIdledConn = nil,
	antiRagdoll = true,
	antiRagdollConn = nil,
	fly = false,
	flySpeed = 50,
	flyBv = nil,
	flyBg = nil,
	flyConn = nil,
	speedBoost = false,
	walkSpeed = 32,
	speedConn = nil,
	antiLag = false,
	upgPrices = {}, -- kind -> {p1,p2,p3}
	-- favorite
	autoFavLuck = false,
	autoFavRarity = false,
	favLuckMin = 4, -- percent
	favRarityTiers = { [5] = true, [6] = true }, -- Legendary + Mythic default
	favThread = nil,
	-- rune
	runeEsp = false,
	runeHighlights = {}, -- part -> Highlight
	runeMinRarity = 1, -- min rarity tier to show
	listCategory = "Crystals", -- "Crystals" or "Runes"
	-- strip mine mountain
	stripMine = false,
	stripMineThread = nil,
	-- auto dig forward (walk + dig look direction)
	autoDigFwd = false,
	autoDigFwdThread = nil,
	stripOrigin = nil,
	stripCellSize = 8,
	stripRange = 120,
	stripLayerStep = 10,
	stripX = 0,
	stripZ = 0,
	stripLayer = 0,
	stripDir = 1, -- 1 = forward, -1 = backward
}

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
	return part:IsDescendantOf(workspace:FindFirstChild("DroppedCrystals") or workspace)
		and part.Name:find("Dropped", 1, true) ~= nil
end

local function collectByExactTier(tier, limit)
	local hrp = getHRP()
	local rows = {}
	iterCrystals(function(part)
		if (part:GetAttribute("Tier") or 0) == tier then
			local dropped = isDroppedCrystal(part)
			local ok, luck = pcall(crystalLuckValue, part)
			table.insert(rows, {
				part = part,
				value = tonumber(part:GetAttribute("Value")) or 0,
				luck = (ok and type(luck) == "number") and luck or 0,
				dropped = dropped,
			})
		end
	end)
	-- sort by selected mode
	local sortBy = state.listSortBy or "money"
	if sortBy == "luck" then
		table.sort(rows, function(a, b)
			if a.luck ~= b.luck then
				return a.luck > b.luck
			end
			if a.value ~= b.value then
				return a.value > b.value
			end
			if a.dropped ~= b.dropped then
				return a.dropped
			end
			return false
		end)
	else
		table.sort(rows, function(a, b)
			if a.value ~= b.value then
				return a.value > b.value
			end
			if a.dropped ~= b.dropped then
				return a.dropped
			end
			return false
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
		})
	end
	return out
end

local function clearESP()
	for part, hl in pairs(state.highlights) do
		pcall(function()
			hl:Destroy()
		end)
		state.highlights[part] = nil
	end
end

local function applyESP()
	clearESP()
	if not state.esp then
		return
	end
	local tier = state.listTier
	local color = TIER_COLORS[tier] or Color3.new(1, 1, 1)
	iterCrystals(function(part)
		if (part:GetAttribute("Tier") or 0) ~= tier then
			return
		end
		if state.highlights[part] then
			return
		end
		local hl = Instance.new("Highlight")
		hl.Name = "MaM_ESP"
		hl.Adornee = part
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.FillColor = color
		hl.OutlineColor = color
		hl.FillTransparency = 0.65
		hl.OutlineTransparency = 0.1
		hl.Parent = part
		state.highlights[part] = hl
	end)
end

--========================================================
-- RUNE ESP — highlight runes in workspace
--========================================================
local RUNE_RARITY = {
	Luck = 1, Haste = 1, -- Common
	Storm = 2, Weight = 2, -- Uncommon
	Fortune = 3, Detonation = 3, -- Rare
	Preservation = 4, Warmth = 4, -- Legendary
	Excavator = 5, Colossus = 5, -- Mythic
}
local RUNE_COLORS = {
	Color3.fromRGB(200, 200, 200), -- Common
	Color3.fromRGB(80, 220, 120), -- Uncommon
	Color3.fromRGB(70, 140, 255), -- Rare
	Color3.fromRGB(170, 90, 255), -- Epic
	Color3.fromRGB(255, 80, 180), -- Legendary
	Color3.fromRGB(255, 60, 60), -- Mythic
}

local function getRuneIdFromPart(part)
	local name = part.Name or ""
	local id = name:gsub("%s*Rune%s*", ""):gsub("^%s+", ""):gsub("%s+$", "")
	return id
end

local function iterRunes(fn)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local runesFolder = assets and assets:FindFirstChild("Runes")
	if not runesFolder then return end
	-- scan workspace for rune mesh parts (dropped/placed)
	for _, v in ipairs(workspace:GetDescendants()) do
		if v:IsA("MeshPart") and v.Name:find("Rune", 1, true) then
			fn(v)
		end
	end
end

local function clearRuneESP()
	for part, hl in pairs(state.runeHighlights) do
		pcall(function() hl:Destroy() end)
		state.runeHighlights[part] = nil
	end
end

local function applyRuneESP()
	clearRuneESP()
	if not state.runeEsp then return end
	local minTier = state.runeMinRarity or 1
	iterRunes(function(part)
		if state.runeHighlights[part] then return end
		local runeId = getRuneIdFromPart(part)
		local tier = RUNE_RARITY[runeId] or 1
		if tier < minTier then return end
		local color = RUNE_COLORS[tier] or Color3.new(1, 1, 1)
		local hl = Instance.new("Highlight")
		hl.Name = "MaM_RuneESP"
		hl.Adornee = part
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.FillColor = color
		hl.OutlineColor = color
		hl.FillTransparency = 0.5
		hl.OutlineTransparency = 0.05
		hl.Parent = part
		state.runeHighlights[part] = hl
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
	local hrp = getHRP()
	if not hrp then
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LP then
			local char = player.Character
			local head = char and char:FindFirstChild("Head")
			local target = head or (char and char:FindFirstChild("HumanoidRootPart"))
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
				label.TextStrokeColor3 = Color3.new(0, 0, 0)
				label.Text = player.DisplayName
				label.Parent = bg

				bb.Parent = LP.Character or game.Players.LocalPlayer:WaitForChild("PlayerGui")
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
				pcall(function() bb:Destroy() end)
				state.charEspBillboards[player] = nil
			end
		end
	end
end

local TP_STEP = 55
local stateTpBusy = false

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

-- stepped TP (tested: less rubber-band than single CFrame jump)
local function steppedTeleport(goalPos, yOffset)
	local hrp = getHRP()
	if not hrp then
		return false, "no hrp"
	end
	if stateTpBusy then
		return false, "busy"
	end
	stateTpBusy = true
	local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
	local start = hrp.Position
	local goal = goalPos + Vector3.new(0, yOffset or 4, 0)
	local dist = (goal - start).Magnitude
	local steps = math.max(1, math.ceil(dist / TP_STEP))
	for i = 1, steps do
		if not hrp.Parent then
			stateTpBusy = false
			return false, "char gone"
		end
		local pos = start:Lerp(goal, i / steps)
		softSetCFrame(hrp, hum, CFrame.new(pos))
		task.wait(0.05)
	end
	softSetCFrame(hrp, hum, CFrame.new(goal))
	stateTpBusy = false
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
		Library:Notify({
			Title = "Teleport",
			Description = "Crystal gone.",
			Time = 2,
		})
		return
	end
	local ok, err = steppedTeleport(part.Position, 3)
	if not ok then
		Library:Notify({
			Title = "Teleport",
			Description = tostring(err),
			Time = 2,
		})
	end
end

local function teleportToPeak()
	Library:Notify({
		Title = "Peak TP",
		Description = "Scanning terrain…",
		Time = 2,
	})
	local peak = findTerrainPeak()
	if not peak then
		Library:Notify({
			Title = "Peak TP",
			Description = "No peak found.",
			Time = 2,
		})
		return
	end
	local ok, err = steppedTeleport(peak, 6)
	Library:Notify({
		Title = ok and "Peak TP" or "Peak TP failed",
		Description = ok and string.format("Y=%d", math.floor(peak.Y)) or tostring(err),
		Time = 3,
	})
end

-- nearest in prompt range (used by vacuum helpers)
local function findNearestMineable(minTier)
	local hrp = getHRP()
	if not hrp then
		return nil
	end
	local best, bestD
	iterCrystals(function(part)
		local tier = part:GetAttribute("Tier") or 0
		if tier < minTier then
			return
		end
		local prompt = getPrompt(part)
		if not prompt or not prompt.Enabled then
			return
		end
		local maxDist = prompt.MaxActivationDistance
		if maxDist < 1 then
			maxDist = 10
		end
		local d = (part.Position - hrp.Position).Magnitude
		if d <= maxDist + 1.5 and (not bestD or d < bestD) then
			bestD = d
			best = part
		end
	end)
	return best, bestD
end

-- any enabled crystal on map (for TP+mine). Prefer highest Value ($), then nearer.
local function findBestMineTarget(minTier, skipSet)
	local hrp = getHRP()
	if not hrp then
		return nil
	end
	local best, bestScore
	iterCrystals(function(part)
		if skipSet and skipSet[part] then
			return
		end
		if not part.Parent then
			return
		end
		local tier = tonumber(part:GetAttribute("Tier")) or 0
		if tier < minTier then
			return
		end
		local prompt = getPrompt(part)
		if not prompt or not prompt.Enabled then
			return
		end
		local value = tonumber(part:GetAttribute("Value")) or 0
		local d = (part.Position - hrp.Position).Magnitude
		-- score: richest first, then closer as tiebreak
		local score = value * 1e6 - d
		if not bestScore or score > bestScore then
			bestScore = score
			best = part
		end
	end)
	return best
end

local function stopAutoMineV2()
	state.autoMineV2 = false
end

-- StarForge-style: patch HoldDuration=0 (InstantMineController pattern) + fire complete
local function tryMineInstant(part)
	if not part or not part.Parent then
		return false
	end
	local prompt = getPrompt(part)
	if not prompt or not prompt.Enabled then
		return false
	end
	local hrp = getHRP()
	if not hrp then
		return false
	end
	local maxDist = prompt.MaxActivationDistance
	if maxDist < 1 then
		maxDist = 12
	end
	if (part.Position - hrp.Position).Magnitude > maxDist + 3 then
		return false
	end

	-- InstantMineController: save original, force hold 0 so CustomProx skips timer
	if typeof(prompt:GetAttribute("IMC_OrigHold")) ~= "number" then
		prompt:SetAttribute("IMC_OrigHold", prompt.HoldDuration)
	end
	prompt.HoldDuration = 0

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local hold = remotes and remotes:FindFirstChild("CrystalHoldComplete")
	if hold and (prompt.ActionText == "Pickup" or prompt.ActionText == "Mine") then
		pcall(function()
			hold:FireServer(part)
		end)
	end
	pcall(function()
		prompt:InputHoldBegin()
	end)
	pcall(function()
		prompt:InputHoldEnd()
	end)
	if fireproximityprompt then
		pcall(fireproximityprompt, prompt)
	end
	return true
end

-- vacuum all in-range crystals (mountain + dropped) with instant hold
local function vacuumNearbyInstant(minTier, maxCount, stillOn)
	local n = 0
	maxCount = maxCount or 16
	local hrp = getHRP()
	if not hrp then
		return 0
	end
	local targets = {}
	iterCrystals(function(part)
		local tier = tonumber(part:GetAttribute("Tier")) or 0
		if tier < minTier then
			return
		end
		local prompt = getPrompt(part)
		if not prompt or not prompt.Enabled then
			return
		end
		local maxDist = prompt.MaxActivationDistance
		if maxDist < 1 then
			maxDist = 12
		end
		local d = (part.Position - hrp.Position).Magnitude
		if d <= maxDist + 3 then
			table.insert(targets, { part = part, d = d, value = tonumber(part:GetAttribute("Value")) or 0 })
		end
	end)
	table.sort(targets, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.d < b.d
	end)
	for _, t in ipairs(targets) do
		if n >= maxCount then
			break
		end
		if stillOn and not stillOn() then
			break
		end
		if Library.Unloaded then
			break
		end
		if t.part.Parent and tryMineInstant(t.part) then
			n += 1
			task.wait(0.05)
		end
	end
	return n
end

-- unified Auto Pickup: mine world + collect dropped (in prompt range, instant)
local function startAutoMineV2()
	if state.mineV2Thread then
		return
	end
	state.mineV2Thread = task.spawn(function()
		while state.autoMineV2 and not Library.Unloaded do
			if state.autoSell then
				local cap = getCarryCap()
				local kg = totalCrystalKg()
				local pct = state.sellAtPct or 95
				if cap > 0 and kg >= cap * (pct / 100) then
					task.wait(0.8)
					continue
				end
			end
			local n = vacuumNearbyInstant(state.mineMinTier, 20, function()
				return state.autoMineV2
			end)
			task.wait(n > 0 and 0.08 or 0.15)
		end
		state.mineV2Thread = nil
	end)
end

--========================================================
-- NO FALL DMG (cap fall velocity — TractionController peak > 75)
--========================================================
local RunService = game:GetService("RunService")

local function stopNoFallDmg()
	state.noFallDmg = false
	if state.fallConn then
		pcall(function()
			state.fallConn:Disconnect()
		end)
		state.fallConn = nil
	end
end

local function startNoFallDmg()
	if state.fallConn then
		return
	end
	state.noFallDmg = true
	state.fallConn = RunService.Heartbeat:Connect(function()
		if not state.noFallDmg or Library.Unloaded then
			return
		end
		local hrp = getHRP()
		if not hrp then
			return
		end
		local v = hrp.AssemblyLinearVelocity
		local cap = state.fallCap or -72
		if v.Y < cap then
			hrp.AssemblyLinearVelocity = Vector3.new(v.X, cap, v.Z)
		end
	end)
end

--========================================================
-- MISC QoL (StarForge-style: AFK / ragdoll / fly / speed / lag)
--========================================================
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")

local function antiAfkPulse()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
	pcall(function()
		local vim = game:GetService("VirtualInputManager")
		if vim then
			vim:SendKeyEvent(true, Enum.KeyCode.RightShift, false, game)
			task.wait(0.02)
			vim:SendKeyEvent(false, Enum.KeyCode.RightShift, false, game)
		end
	end)
end

local function stopAntiAfk()
	state.antiAfk = false
	if state.antiAfkIdledConn then
		pcall(function()
			state.antiAfkIdledConn:Disconnect()
		end)
		state.antiAfkIdledConn = nil
	end
end

local function startAntiAfk()
	if state.antiAfkThread then
		return
	end
	state.antiAfk = true
	-- Roblox fires Idled ~20min before kick — block idle immediately
	if not state.antiAfkIdledConn then
		state.antiAfkIdledConn = LP.Idled:Connect(function()
			if state.antiAfk and not Library.Unloaded then
				antiAfkPulse()
			end
		end)
	end
	state.antiAfkThread = task.spawn(function()
		while state.antiAfk and not Library.Unloaded do
			antiAfkPulse()
			task.wait(45)
		end
		state.antiAfkThread = nil
	end)
end

local function stopAntiRagdoll()
	state.antiRagdoll = false
	if state.antiRagdollConn then
		pcall(function()
			state.antiRagdollConn:Disconnect()
		end)
		state.antiRagdollConn = nil
	end
end

local function startAntiRagdoll()
	if state.antiRagdollConn then
		return
	end
	state.antiRagdoll = true
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local names = { "RagdollRequest", "RagdollSound", "GrabRagdollState", "FallDamage" }
	local function nuke(inst)
		if not inst or not inst:IsA("RemoteEvent") then
			return
		end
		for _, n in ipairs(names) do
			if inst.Name == n then
				pcall(function()
					inst:Destroy()
				end)
				break
			end
		end
	end
	if remotes then
		for _, c in ipairs(remotes:GetChildren()) do
			nuke(c)
		end
		state.antiRagdollConn = remotes.ChildAdded:Connect(function(c)
			if state.antiRagdoll then
				task.defer(nuke, c)
			end
		end)
	end
end

local function stopFly()
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

local function startFly()
	stopFly()
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
		local hu = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
		if not h or not hu or not state.flyBv or not state.flyBg then
			return
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

local function stopSpeedBoost()
	state.speedBoost = false
	if state.speedConn then
		pcall(function()
			state.speedConn:Disconnect()
		end)
		state.speedConn = nil
	end
end

local function startSpeedBoost()
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

local function applyAntiLag(on)
	state.antiLag = on
	pcall(function()
		local lighting = game:GetService("Lighting")
		if on then
			settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
			lighting.GlobalShadows = false
			lighting.FogEnd = 1e6
			for _, d in ipairs(workspace:GetDescendants()) do
				if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") then
					d.Enabled = false
				elseif d:IsA("Explosion") then
					d:Destroy()
				end
			end
		else
			settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
			lighting.GlobalShadows = true
		end
	end)
end

local function goHome()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local r = remotes and remotes:FindFirstChild("GoHome")
	if not r then
		return false, "no GoHome"
	end
	return pcall(function()
		r:FireServer()
	end)
end

local function claimGroupReward()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local r = remotes and remotes:FindFirstChild("ClaimGroupReward")
	if not r then
		return false, "no remote"
	end
	return pcall(function()
		r:FireServer()
	end)
end

local function rejoinServer()
	return pcall(function()
		TeleportService:Teleport(game.PlaceId, LP)
	end)
end

local function hopServer()
	return pcall(function()
		local htt = game:GetService("HttpService")
		local url = string.format(
			"https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100",
			game.PlaceId
		)
		local body = game:HttpGet(url)
		local data = htt:JSONDecode(body)
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

local function playerDropdownValues()
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

local function teleportToPlayerName(name)
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

--========================================================
-- SELL — SellRequest:FireServer("all") near SellProx
-- NOTE: CrystalDropRequest("all") is NOT sell (drops/no-op for bulk)
-- Game path: ShopDialogController → SellRequest "all" | "held"
-- True capacity is HUD "cur / cap kg" (CarryWeight alone is base, e.g. 6176 vs 49408)
--========================================================
local function parseBackpackHud()
	local pg = LP:FindFirstChild("PlayerGui")
	local hud = pg and pg:FindFirstChild("ExplorerHud")
	local panel = hud and hud:FindFirstChild("BackpackPanel")
	local label = panel and panel:FindFirstChild("Value")
	local text = label and label.Text
	if type(text) ~= "string" then
		return nil, nil
	end
	-- e.g. "31594.9 / 49408.0 kg"
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
	local char = LP.Character
	if char then
		scan(char)
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
	local char = LP.Character
	if char then
		scan(char)
	end
	return n
end

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
	local dist = (hrp.Position - sellPos).Magnitude
	if dist <= maxDist then
		return true
	end
	-- GoHome("sell") is game UI path; also stepped TP as backup
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
	local ok = steppedTeleport(sellPos + Vector3.new(0, 3, 0), 3)
	if not ok then
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
	-- hold near sell briefly so server range check passes
	local hrp = getHRP()
	local sellPos = getSellPosition()
	local holdConn
	if hrp and sellPos then
		local RunService = game:GetService("RunService")
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
	return true, {
		sold = sold,
		cashDelta = cash1 - cash0,
	}
end

local function buildInfoText()
	local rs = LP:FindFirstChild("PlayerData") and LP.PlayerData:FindFirstChild("RealStats")
	local cash = getCash()
	local kg = totalCrystalKg()
	local cap = getCarryCap()
	local height = rs and rs:FindFirstChild("Height") and rs.Height.Value or 0
	local best = rs and rs:FindFirstChild("Best") and rs.Best.Value or 0
	local plotLuck = rs and rs:FindFirstChild("PlotLuck") and rs.PlotLuck.Value or 0
	local tools = countCrystalTools()
	local players = #Players:GetPlayers()
	return string.format(
		"Player: %s (@%s)\nCash: %s\nBackpack: %d tools · %.0f / %.0f kg\nHeight: %.0f · Best: %.0f\nPlotLuck: %.2f\nPlace: %s\nPlayers: %d · Job: %s",
		LP.DisplayName,
		LP.Name,
		formatMoney(cash),
		tools,
		kg,
		cap,
		height,
		best,
		plotLuck,
		tostring(game.PlaceId),
		players,
		string.sub(game.JobId, 1, 8)
	)
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
-- PICKAXE SHOP
-- ShopBuy:FireServer(id) / ShopEquip:FireServer(id)
--========================================================
local ShopCatalog
pcall(function()
	ShopCatalog = require(ReplicatedStorage.Modules.Shop.ShopCatalog)
end)

local function getPickaxeList()
	if ShopCatalog and type(ShopCatalog.Pickaxes) == "table" then
		return ShopCatalog.Pickaxes
	end
	return {}
end

local function pickOwned(id)
	local inv = LP:FindFirstChild("PlayerData") and LP.PlayerData:FindFirstChild("Inventory")
	local folder = inv and inv:FindFirstChild("Pickaxes")
	local owned = folder and folder:FindFirstChild("Owned")
	local v = owned and owned:FindFirstChild(id)
	return v and v.Value == true
end

local function pickEquippedId()
	local inv = LP:FindFirstChild("PlayerData") and LP.PlayerData:FindFirstChild("Inventory")
	local folder = inv and inv:FindFirstChild("Pickaxes")
	local eq = folder and folder:FindFirstChild("Equipped")
	return eq and tostring(eq.Value) or ""
end

local function shopBuy(id)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local r = remotes and remotes:FindFirstChild("ShopBuy")
	if not r then
		return false, "no ShopBuy"
	end
	local ok, err = pcall(function()
		r:FireServer(id)
	end)
	return ok, err
end

local function shopEquip(id)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local r = remotes and remotes:FindFirstChild("ShopEquip")
	if not r then
		return false, "no ShopEquip"
	end
	local ok, err = pcall(function()
		r:FireServer(id)
	end)
	return ok, err
end

local function nextAffordablePickaxe()
	local cash = getCash()
	for _, p in ipairs(getPickaxeList()) do
		local price = tonumber(p.price) or 0
		if price > 0 and not pickOwned(p.id) and cash >= price then
			return p
		end
	end
	return nil
end

local function bestOwnedPickaxe()
	local best
	for _, p in ipairs(getPickaxeList()) do
		if pickOwned(p.id) then
			local dig = p.stats and tonumber(p.stats.DigPower) or 0
			if not best or dig > (best.stats and best.stats.DigPower or 0) then
				best = p
			end
		end
	end
	return best
end

local pickScroll
local PICK_LIST_H = 280
local PICK_ROW_H = 38

local function buildPickListUI()
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "PickaxeListScroll"
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

local function refreshPickList()
	if not pickScroll or not pickScroll.Parent then
		return 0
	end
	local ok, result = pcall(function()
		for _, ch in ipairs(pickScroll:GetChildren()) do
			if ch:IsA("Frame") or ch:IsA("TextButton") then
				ch:Destroy()
			end
		end
		local list = getPickaxeList()
		local equipped = pickEquippedId()
		local cash = getCash()
		local n = 0
		for i, p in ipairs(list) do
			n += 1
			local owned = pickOwned(p.id)
			local price = tonumber(p.price) or 0
			local dig = p.stats and tonumber(p.stats.DigPower) or 0
			local matTier = p.stats and tonumber(p.stats.MaterialTier) or 0
			local isEq = equipped == p.id
			local isGP = price <= 0 and p.id == "DiamondPickaxe"

			local row = Instance.new("Frame")
			row.Name = p.id
			row.LayoutOrder = i
			row.Size = UDim2.new(1, 0, 0, 38)
			row.BackgroundColor3 = isEq and Color3.fromRGB(22, 38, 28) or Color3.fromRGB(28, 28, 34)
			row.BorderSizePixel = 0
			row.Parent = pickScroll
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 4)
			corner.Parent = row

			-- Power badge (left)
			local pwrBadge = Instance.new("TextLabel")
			pwrBadge.BackgroundColor3 = Color3.fromRGB(255, 170, 40)
			pwrBadge.BackgroundTransparency = 0.15
			pwrBadge.Size = UDim2.fromOffset(42, 18)
			pwrBadge.Position = UDim2.fromOffset(4, 3)
			pwrBadge.Font = Enum.Font.GothamBold
			pwrBadge.TextSize = 11
			pwrBadge.TextColor3 = Color3.new(1, 1, 1)
			pwrBadge.Text = string.format("%.1f", dig)
			pwrBadge.Parent = row
			local pbc = Instance.new("UICorner")
			pbc.CornerRadius = UDim.new(0, 3)
			pbc.Parent = pwrBadge

			-- Name + power
			local info = Instance.new("TextLabel")
			info.BackgroundTransparency = 1
			info.Position = UDim2.fromOffset(50, 0)
			info.Size = UDim2.new(1, -144, 0, 18)
			info.Font = Enum.Font.GothamBold
			info.TextSize = 12
			info.TextColor3 = isEq and Color3.fromRGB(120, 220, 160) or Color3.fromRGB(230, 230, 235)
			info.TextXAlignment = Enum.TextXAlignment.Left
			info.TextTruncate = Enum.TextTruncate.AtEnd
			info.Text = string.format("%s  ·  PWR %.1f", p.name or p.id, dig)
			info.Parent = row

			-- Material + price line
			local matName = ({ [1] = "Stone", [2] = "Metal", [3] = "Crystal" })[matTier] or "?"
			local statsLabel = Instance.new("TextLabel")
			statsLabel.BackgroundTransparency = 1
			statsLabel.Position = UDim2.fromOffset(50, 18)
			statsLabel.Size = UDim2.new(1, -144, 0, 16)
			statsLabel.Font = Enum.Font.Gotham
			statsLabel.TextSize = 10
			statsLabel.TextColor3 = Color3.fromRGB(150, 150, 165)
			statsLabel.TextXAlignment = Enum.TextXAlignment.Left
			statsLabel.TextTruncate = Enum.TextTruncate.AtEnd
			statsLabel.Text = string.format("%s tier  ·  %s", matName, formatMoney(price))
			statsLabel.Parent = row

			local btn = Instance.new("TextButton")
			btn.Size = UDim2.fromOffset(88, 22)
			btn.Position = UDim2.new(1, -94, 0.5, -11)
			btn.Font = Enum.Font.GothamBold
			btn.TextSize = 11
			btn.TextColor3 = Color3.new(1, 1, 1)
			btn.BorderSizePixel = 0
			btn.AutoButtonColor = true
			local bc = Instance.new("UICorner")
			bc.CornerRadius = UDim.new(0, 4)
			bc.Parent = btn
			btn.Parent = row

			if isEq then
				btn.Text = "Equipped"
				btn.BackgroundColor3 = Color3.fromRGB(60, 120, 80)
				btn.Active = false
			elseif owned then
				btn.Text = "Equip"
				btn.BackgroundColor3 = Color3.fromRGB(50, 100, 180)
				btn.MouseButton1Click:Connect(function()
					local ok2 = shopEquip(p.id)
					task.wait(0.35)
					refreshPickList()
					Library:Notify({
						Title = ok2 and "Equipped" or "Equip failed",
						Description = p.name or p.id,
						Time = 2,
					})
				end)
			elseif isGP then
				btn.Text = "Gamepass"
				btn.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
				btn.Active = false
			elseif cash >= price then
				btn.Text = "Buy " .. formatMoney(price)
				btn.BackgroundColor3 = Color3.fromRGB(40, 150, 90)
				btn.MouseButton1Click:Connect(function()
					local ok2 = shopBuy(p.id)
					task.wait(0.45)
					refreshPickList()
					Library:Notify({
						Title = ok2 and "Bought" or "Buy failed",
						Description = string.format("%s · %s", p.name or p.id, formatMoney(price)),
						Time = 2,
					})
				end)
			else
				btn.Text = formatMoney(price)
				btn.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
				btn.Active = false
			end
		end
		return n
	end)
	if not ok then
		warn("[PickList]", result)
		return 0
	end
	return result or 0
end

local function stopAutoBuyPick()
	state.autoBuyPick = false
end

local function startAutoBuyPick()
	if state.pickThread then
		return
	end
	state.pickThread = task.spawn(function()
		while state.autoBuyPick and not Library.Unloaded do
			local nextP = nextAffordablePickaxe()
			if nextP then
				local ok = shopBuy(nextP.id)
				if ok then
					Library:Notify({
						Title = "Auto-Buy Pick",
						Description = nextP.name or nextP.id,
						Time = 2,
					})
					task.wait(0.6)
					refreshPickList()
				else
					task.wait(1.5)
				end
			else
				task.wait(2)
			end
		end
		state.pickThread = nil
	end)
end

local bombStockLabel -- set when Bombs UI builds

--========================================================
-- BOMB SHOP
-- BombShopQuery:InvokeServer() -> { stock = { [id]=n } }
-- BombBuyRequest:InvokeServer(id) -> { ok=true, remaining=n }
--========================================================
local BombShopConfig
pcall(function()
	BombShopConfig = require(ReplicatedStorage.Modules.BombShopConfig)
end)

local BOMB_ORDER = {
	"ClassicBomb",
	"WindBomb",
	"IceBomb",
	"FireBomb",
	"ThunderBomb",
	"PoisonBomb",
	"TimeBomb",
	"AgonyBomb",
}

local function bombMeta(id)
	if BombShopConfig and BombShopConfig.BOMBS then
		return BombShopConfig.BOMBS[id]
	end
	return nil
end

local function bombDisplayName(id)
	local m = bombMeta(id)
	return (m and m.displayName) or id
end

local function bombPrice(id)
	local m = bombMeta(id)
	return (m and m.cashPrice) or 0
end

local function bombDropdownLabels()
	local labels = {}
	for _, id in ipairs(BOMB_ORDER) do
		local m = bombMeta(id)
		if m and m.enabled ~= false then
			table.insert(labels, string.format("%s ($%s)", m.displayName, formatMoney(m.cashPrice):gsub("%$", "")))
		end
	end
	return labels
end

local function labelToBombId(label)
	if type(label) ~= "string" then
		return nil
	end
	for _, id in ipairs(BOMB_ORDER) do
		local m = bombMeta(id)
		if m and label:find(m.displayName, 1, true) then
			return id
		end
		if label == id then
			return id
		end
	end
	return nil
end

-- Obsidian multi dropdown: Value = { [label]=true, ... }
local function syncBombTargetsFromDropdown(value)
	local map = {}
	if type(value) == "table" then
		for label, on in pairs(value) do
			if on then
				local id = labelToBombId(label)
				if id then
					map[id] = true
				end
			end
		end
	elseif type(value) == "string" then
		local id = labelToBombId(value)
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

local function selectedBombIds()
	local list = {}
	for _, id in ipairs(BOMB_ORDER) do
		if state.bombTargets[id] then
			table.insert(list, id)
		end
	end
	return list
end

-- prefer highest rarity with stock + cash (scan BOMB_ORDER reverse)
local function pickBuyableBomb()
	for i = #BOMB_ORDER, 1, -1 do
		local id = BOMB_ORDER[i]
		if state.bombTargets[id] then
			local stock = tonumber(state.bombStock[id]) or 0
			if stock > 0 and getCash() >= bombPrice(id) then
				return id
			end
		end
	end
	return nil
end

local function getOwnedBomb(id)
	local inv = LP:FindFirstChild("PlayerData") and LP.PlayerData:FindFirstChild("Inventory")
	local bombs = inv and inv:FindFirstChild("Bombs")
	local v = bombs and bombs:FindFirstChild(id)
	return v and tonumber(v.Value) or 0
end

local function queryBombStock()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local q = remotes and remotes:FindFirstChild("BombShopQuery")
	if not q then
		-- offline roll from config window
		if BombShopConfig and BombShopConfig.rollStockForWindow then
			local win = BombShopConfig.currentWindow and BombShopConfig.currentWindow() or 0
			state.bombStock = BombShopConfig.rollStockForWindow(win) or {}
			return state.bombStock, true
		end
		return state.bombStock, false
	end
	local ok, result = pcall(function()
		return q:InvokeServer()
	end)
	if ok and type(result) == "table" and type(result.stock) == "table" then
		state.bombStock = result.stock
		return state.bombStock, true
	end
	-- RF may fail under some executors; fallback local roll
	if BombShopConfig and BombShopConfig.rollStockForWindow then
		local win = BombShopConfig.currentWindow and BombShopConfig.currentWindow() or 0
		state.bombStock = BombShopConfig.rollStockForWindow(win) or {}
		return state.bombStock, false
	end
	return state.bombStock, false
end

local function secondsToRestock()
	if BombShopConfig and BombShopConfig.secondsToRestock then
		return BombShopConfig.secondsToRestock()
	end
	return 0
end

local function formatTimer(sec)
	sec = math.max(0, math.floor(sec))
	local m = math.floor(sec / 60)
	local s = sec % 60
	return string.format("%dm %02ds", m, s)
end

local function buildStockText()
	local stock = state.bombStock or {}
	local lines = {}
	table.insert(lines, "Restock in: " .. formatTimer(secondsToRestock()))
	for _, id in ipairs(BOMB_ORDER) do
		local m = bombMeta(id)
		if m and m.enabled ~= false then
			local n = tonumber(stock[id]) or 0
			local own = getOwnedBomb(id)
			local tag = n > 0 and ("x" .. n) or "OUT"
			table.insert(
				lines,
				string.format("%s  stock %s  own %d  %s", m.displayName, tag, own, formatMoney(m.cashPrice))
			)
		end
	end
	return table.concat(lines, "\n")
end

local function tryBuyBomb(id)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local buy = remotes and remotes:FindFirstChild("BombBuyRequest")
	if not buy then
		return false, "no remote"
	end
	local price = bombPrice(id)
	if getCash() < price then
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

local function stopAutoBuyBomb()
	state.autoBuyBomb = false
end

local function startAutoBuyBomb()
	if state.bombThread then
		return
	end
	state.bombThread = task.spawn(function()
		while state.autoBuyBomb and not Library.Unloaded do
			queryBombStock()
			local id = pickBuyableBomb()
			if id then
				local ok = tryBuyBomb(id)
				if ok then
					Library:Notify({
						Title = "Bomb Buy",
						Description = string.format(
							"Bought %s · left %s",
							bombDisplayName(id),
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
			pcall(function()
				if bombStockLabel and bombStockLabel.SetText then
					bombStockLabel:SetText(buildStockText())
				end
			end)
		end
		state.bombThread = nil
	end)
end

local function waitBackpackIncrease(beforeCount, timeout, stillOn)
	timeout = timeout or 6
	local t0 = os.clock()
	while os.clock() - t0 < timeout do
		if Library.Unloaded or (stillOn and not stillOn()) then
			return false
		end
		local n = countCrystalTools()
		if n > beforeCount then
			return true, n
		end
		task.wait(0.15)
	end
	return false, countCrystalTools()
end

local function stopAutoMineTPV2()
	state.autoMineTPV2 = false
end

-- Auto-Mine TP v2: vacuum near → TP richest (world+dropped) → instant mine → backpack +1 → next
local function startAutoMineTPV2()
	if state.mineTPV2Thread then
		return
	end
	state.mineTPV2Thread = task.spawn(function()
		local skip = {}
		local failStreak = 0
		local still = function()
			return state.autoMineTPV2
		end
		while state.autoMineTPV2 and not Library.Unloaded do
			if state.autoSell then
				local cap = getCarryCap()
				local kg = totalCrystalKg()
				local pct = state.sellAtPct or 95
				if cap > 0 and kg >= cap * (pct / 100) then
					task.wait(0.8)
					continue
				end
			end

			vacuumNearbyInstant(state.mineMinTier, 16, still)
			if not state.autoMineTPV2 then
				break
			end

			local part = findBestMineTarget(state.mineMinTier, skip)
			if not part then
				skip = {}
				failStreak += 1
				if failStreak >= 3 then
					Library:Notify({
						Title = "Auto-Mine TP v2",
						Description = "No crystals (tier ≥ " .. tostring(state.mineMinTier) .. ")",
						Time = 2,
					})
					failStreak = 0
				end
				task.wait(0.8)
				continue
			end
			failStreak = 0

			if not part.Parent then
				skip[part] = true
				continue
			end

			local before = countCrystalTools()
			local hrp = getHRP()
			local prompt = getPrompt(part)
			local maxDist = (prompt and prompt.MaxActivationDistance) or 12
			if maxDist < 1 then
				maxDist = 12
			end
			local needTP = not hrp or (part.Position - hrp.Position).Magnitude > maxDist + 2

			if needTP then
				local tpOk = steppedTeleport(part.Position, 3)
				if not tpOk or not state.autoMineTPV2 or Library.Unloaded then
					if not tpOk then
						skip[part] = true
					end
					task.wait(0.25)
					continue
				end
				task.wait(0.12)
			end

			if not part.Parent then
				skip[part] = true
				continue
			end

			tryMineInstant(part)
			vacuumNearbyInstant(state.mineMinTier, 10, still)

			local got = waitBackpackIncrease(before, 2.5, still)
			if got then
				skip[part] = nil
				task.wait(0.08)
			else
				skip[part] = true
				task.wait(0.2)
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
-- DIG INFRASTRUCTURE (used by Strip Mine)
-- DigRequest:FireServer(toolName, Vector3)
--========================================================
local ToolConfig, ZoneCheck
pcall(function()
	ToolConfig = require(ReplicatedStorage.Modules.Tools.ToolConfig)
end)
pcall(function()
	ZoneCheck = require(ReplicatedStorage.Modules.Tools.ZoneCheck)
end)

local DIG_RING_RADII = { 3, 5, 7, 9 }
local DIG_RING_POINTS = 12
-- pitch: down → level → up (all directions around player)
local DIG_PITCHES = { -0.95, -0.55, -0.2, 0, 0.25, 0.55, 0.9 }

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

local function digMaxReach(toolName)
	if ToolConfig and ToolConfig.getTool then
		local cfg = ToolConfig.getTool(toolName)
		if cfg and cfg.maxReach then
			return cfg.maxReach
		end
	end
	return 10
end

local function digTerrainRay(origin, direction)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	return workspace:Raycast(origin, direction, params)
end

local function digCanAt(pos, hrp)
	if not pos or not hrp then
		return false
	end
	if (pos - hrp.Position).Magnitude > 14 then
		return false
	end
	if ZoneCheck then
		if ZoneCheck.isInNoDiggingZone and ZoneCheck.isInNoDiggingZone(pos) then
			return false
		end
		if ZoneCheck.isInMountainZone and not ZoneCheck.isInMountainZone(pos) then
			return false
		end
	end
	return true
end

local function digPointFromHit(hit)
	if not hit then
		return nil
	end
	return hit.Position - hit.Normal * 1.2
end

local function collectSpinDigTargets(hrp, reach, angleIdx)
	local targets = {}
	local seen = {}
	local function add(hit, tag)
		if not hit then
			return
		end
		local pos = digPointFromHit(hit)
		if not digCanAt(pos, hrp) then
			return
		end
		local key = string.format("%d_%d_%d", math.floor(pos.X), math.floor(pos.Y), math.floor(pos.Z))
		if seen[key] then
			return
		end
		seen[key] = true
		table.insert(targets, {
			pos = pos,
			tag = tag,
			mat = tostring(hit.Material),
		})
	end

	local rayLen = reach + 4
	local origin = hrp.Position + Vector3.new(0, 1.2, 0)
	-- pure down / pure up
	add(digTerrainRay(hrp.Position + Vector3.new(0, 2, 0), Vector3.new(0, -rayLen, 0)), "down")
	add(digTerrainRay(hrp.Position + Vector3.new(0, 1, 0), Vector3.new(0, rayLen, 0)), "up")

	local start = angleIdx
	for step = 0, DIG_RING_POINTS - 1 do
		local idx = (start + step - 1) % DIG_RING_POINTS
		local ang = idx * (math.pi * 2 / DIG_RING_POINTS)
		local cos, sin = math.cos(ang), math.sin(ang)
		for _, r in ipairs(DIG_RING_RADII) do
			for _, pitch in ipairs(DIG_PITCHES) do
				local dir = Vector3.new(cos, pitch, sin)
				if dir.Magnitude > 0.01 then
					add(digTerrainRay(origin, dir.Unit * rayLen), "spin")
				end
			end
			-- floor + ceiling samples at ring offset
			add(
				digTerrainRay(hrp.Position + Vector3.new(cos * r, 3, sin * r), Vector3.new(0, -rayLen, 0)),
				"floor"
			)
			add(
				digTerrainRay(hrp.Position + Vector3.new(cos * r, 1, sin * r), Vector3.new(0, rayLen, 0)),
				"ceil"
			)
		end
	end
	return targets
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

local digAngleIdx = 0
local digCount = 0

local function stopAutoDigForward()
	state.autoDigFwd = false
end

local function digForwardOnce()
	local hrp = getHRP()
	local tool = getEquippedPickaxe()
	if not hrp or not tool then
		return false
	end
	local reach = digMaxReach(tool.Name)
	-- dig toward camera aim (not character facing)
	local cam = workspace.CurrentCamera
	local look = cam and cam.CFrame.LookVector or hrp.CFrame.LookVector
	if look.Magnitude < 0.05 then
		look = hrp.CFrame.LookVector
	end
	look = look.Unit
	local origin = hrp.Position + Vector3.new(0, 1.5, 0)
	-- cone around camera: center + slight offsets
	local right = cam and cam.CFrame.RightVector or hrp.CFrame.RightVector
	local up = cam and cam.CFrame.UpVector or Vector3.yAxis
	local dirs = {
		look,
		(look + up * 0.25).Unit,
		(look - up * 0.35).Unit,
		(look + right * 0.3).Unit,
		(look - right * 0.3).Unit,
		(look + up * 0.15 + right * 0.2).Unit,
		(look - up * 0.2 - right * 0.2).Unit,
	}
	local hit = 0
	local rayLen = reach + 4
	for _, dir in ipairs(dirs) do
		if dir.Magnitude > 0.01 then
			local ray = digTerrainRay(origin, dir.Unit * rayLen)
			if ray then
				local pos = digPointFromHit(ray)
				if digCanAt(pos, hrp) and fireDig(tool.Name, pos) then
					hit += 1
					digCount += 1
				end
			end
		end
	end
	return hit > 0
end

local function startAutoDigForward()
	if state.autoDigFwdThread then
		return
	end
	state.autoDigFwdThread = task.spawn(function()
		while state.autoDigFwd and not Library.Unloaded do
			local tool = getEquippedPickaxe()
			pcall(digForwardOnce)
			local waitT = tool and digCooldown(tool.Name) or 0.35
			task.wait(math.clamp(waitT, 0.12, 0.8))
		end
		state.autoDigFwdThread = nil
	end)
end

local function digCycleOnce()
	local hrp = getHRP()
	local tool = getEquippedPickaxe()
	if not hrp then
		return false, "no character"
	end
	if not tool then
		return false, "equip pickaxe"
	end

	local reach = digMaxReach(tool.Name)
	digAngleIdx = (digAngleIdx % DIG_RING_POINTS) + 1
	local angDeg = math.floor((digAngleIdx - 1) * (360 / DIG_RING_POINTS))

	local targets = collectSpinDigTargets(hrp, reach, digAngleIdx)
	if #targets == 0 then
		return false, "no terrain (mountain?)"
	end

	table.sort(targets, function(a, b)
		local rank = { spin = 1, floor = 2, ceil = 3, down = 4, up = 5 }
		return (rank[a.tag] or 9) < (rank[b.tag] or 9)
	end)

	local hit = 0
	local lastTag, lastMat = "?", "?"
	for _, t in ipairs(targets) do
		if hit >= 12 then
			break
		end
		if fireDig(tool.Name, t.pos) then
			hit += 1
			digCount += 1
			lastTag = t.tag
			lastMat = (t.mat or ""):gsub("Enum.Material.", "")
			task.wait(0.04)
		end
	end

	if hit == 0 then
		return false, "no valid hit"
	end
	return true, string.format("spin %d° · %s/%s · +%d", angDeg, lastTag, lastMat, hit)
end

--========================================================
-- STRIP MINE — random diggable terrain TP + fast omni dig
-- 5s delay between teleports to next diggable spot
--========================================================
local STRIP_TP_DELAY = 5

local function findRandomDiggableTerrain()
	local hrp = getHRP()
	local peak = state.stripOrigin or findTerrainPeak()
	if not peak then
		return nil
	end
	state.stripOrigin = peak
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local range = state.stripRange or 120
	-- sample random XZ around peak, accept diggable surface
	for _ = 1, 40 do
		local ox = (math.random() - 0.5) * 2 * range
		local oz = (math.random() - 0.5) * 2 * range
		local probe = Vector3.new(peak.X + ox, peak.Y + 400, peak.Z + oz)
		local hit = workspace:Raycast(probe, Vector3.new(0, -1200, 0), params)
		if hit and hit.Position then
			local pos = hit.Position + Vector3.new(0, 3, 0)
			-- prefer mountain-ish height
			if hit.Position.Y > 30 then
				local okZone = true
				if ZoneCheck then
					if ZoneCheck.isInNoDiggingZone and ZoneCheck.isInNoDiggingZone(hit.Position) then
						okZone = false
					end
					if ZoneCheck.isInMountainZone and not ZoneCheck.isInMountainZone(hit.Position) then
						okZone = false
					end
				end
				if okZone then
					return pos, hit.Material
				end
			end
		end
	end
	-- fallback: near peak
	local hit = workspace:Raycast(peak + Vector3.new(0, 200, 0), Vector3.new(0, -500, 0), params)
	if hit then
		return hit.Position + Vector3.new(0, 3, 0), hit.Material
	end
	return peak + Vector3.new(0, 3, 0), nil
end

local function digOmniFast()
	-- several full spin cycles, short wait = dig ke segala arah cepat
	local hits = 0
	for _ = 1, 6 do
		if not state.stripMine or Library.Unloaded then
			break
		end
		local ok, msg = digCycleOnce()
		if ok then
			hits += 1
		end
		-- vacuum between dig bursts
		vacuumNearbyInstant(state.mineMinTier, 16, function()
			return state.stripMine
		end)
		task.wait(0.05)
	end
	return hits > 0
end

local function stopStripMine()
	state.stripMine = false
end

local function startStripMine()
	if state.stripMineThread then
		return
	end
	state.stripMineThread = task.spawn(function()
		local peak = findTerrainPeak()
		if peak then
			state.stripOrigin = peak
		end
		Library:Notify({
			Title = "Strip Mine",
			Description = "Random diggable TP · omni dig · 5s antar teleport",
			Time = 3,
		})
		while state.stripMine and not Library.Unloaded do
			local spot, mat = findRandomDiggableTerrain()
			if not spot then
				Library:Notify({ Title = "Strip Mine", Description = "No diggable terrain", Time = 2 })
				task.wait(2)
				continue
			end
			local tpOk, tpErr = steppedTeleport(spot, 5)
			if not tpOk then
				Library:Notify({ Title = "Strip Mine", Description = "TP fail: " .. tostring(tpErr), Time = 2 })
				task.wait(1)
				continue
			end
			task.wait(0.2)
			-- dig cepat ke segala arah di spot ini
			pcall(digOmniFast)
			if state.stripMine and state.autoSell then
				local cap = getCarryCap()
				local kg = totalCrystalKg()
				if cap > 0 and kg >= cap * (state.sellAtPct or 95) / 100 then
					doSellAll()
					task.wait(0.8)
				end
			end
			-- jeda 5 detik sebelum teleport ke terrain diggable berikutnya
			if state.stripMine and not Library.Unloaded then
				local left = STRIP_TP_DELAY
				while left > 0 and state.stripMine and not Library.Unloaded do
					-- keep vacuum while waiting
					vacuumNearbyInstant(state.mineMinTier, 12, function()
						return state.stripMine
					end)
					task.wait(math.min(1, left))
					left -= 1
				end
			end
		end
		state.stripMineThread = nil
		Library:Notify({ Title = "Strip Mine", Description = "Stopped", Time = 2 })
	end)
end

--========================================================
-- FAVORITE (ToggleFavorite:FireServer(tool, bool))
--========================================================
local function getCrystalTools()
	local tools = {}
	local function scan(container)
		if not container then
			return
		end
		for _, t in ipairs(container:GetChildren()) do
			if t:IsA("Tool") and t:GetAttribute("Tier") ~= nil and t:GetAttribute("Value") ~= nil then
				table.insert(tools, t)
			end
		end
	end
	scan(LP:FindFirstChild("Backpack"))
	scan(LP.Character)
	return tools
end

local function setToolFavorite(tool, want)
	if not tool or not tool.Parent then
		return false
	end
	local cur = tool:GetAttribute("Favorited") == true
	if cur == want then
		return true
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local fav = remotes and remotes:FindFirstChild("ToggleFavorite")
	if not fav then
		return false
	end
	tool:SetAttribute("Favorited", want)
	return pcall(function()
		fav:FireServer(tool, want)
	end)
end

local function toolLuckPct(tool)
	local ok, luck = pcall(crystalLuckValue, tool)
	if not ok or type(luck) ~= "number" then
		return 0
	end
	return luck * 100
end

local function favCountStatus()
	local tools = getCrystalTools()
	local favN, matchLuck, matchRar = 0, 0, 0
	local minPct = state.favLuckMin or 4
	for _, t in ipairs(tools) do
		if t:GetAttribute("Favorited") == true then
			favN += 1
		end
		if toolLuckPct(t) > minPct then
			matchLuck += 1
		end
		local tier = tonumber(t:GetAttribute("Tier")) or 0
		if state.favRarityTiers[tier] then
			matchRar += 1
		end
	end
	return string.format(
		"Backpack: %d tools · %d favorited\nLuck > %.1f%%: %d match\nRarity filter: %d match",
		#tools,
		favN,
		minPct,
		matchLuck,
		matchRar
	)
end

local function runFavoritePass()
	local tools = getCrystalTools()
	local nLuck, nRar = 0, 0
	local minPct = state.favLuckMin or 4
	for _, tool in ipairs(tools) do
		if Library.Unloaded then
			break
		end
		local want = false
		if state.autoFavLuck and toolLuckPct(tool) > minPct then
			want = true
			nLuck += 1
		end
		if state.autoFavRarity then
			local tier = tonumber(tool:GetAttribute("Tier")) or 0
			if state.favRarityTiers[tier] then
				want = true
				nRar += 1
			end
		end
		if want and tool:GetAttribute("Favorited") ~= true then
			setToolFavorite(tool, true)
			task.wait(0.04)
		end
	end
	return nLuck, nRar
end

local function startFavoriteLoop()
	if state.favThread then
		return
	end
	state.favThread = task.spawn(function()
		while (state.autoFavLuck or state.autoFavRarity) and not Library.Unloaded do
			pcall(runFavoritePass)
			task.wait(1.5)
		end
		state.favThread = nil
	end)
end

local function stopFavoriteLoopIfIdle()
	if not state.autoFavLuck and not state.autoFavRarity then
		-- thread exits on next loop check
	end
end

local function favoriteAllInBag()
	local n = 0
	for _, tool in ipairs(getCrystalTools()) do
		if setToolFavorite(tool, true) then
			n += 1
		end
		task.wait(0.04)
	end
	return n
end

local function unfavoriteAllInBag()
	local n = 0
	for _, tool in ipairs(getCrystalTools()) do
		if setToolFavorite(tool, false) then
			n += 1
		end
		task.wait(0.04)
	end
	return n
end

local function syncFavRarityFromDropdown(value)
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

local LIST_HEIGHT = 220
local ROW_H = 26

local function buildCrystalListUI()
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "CrystalListScroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 130)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 3)
	layout.Parent = scroll

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 2)
	pad.PaddingRight = UDim.new(0, 2)
	pad.PaddingTop = UDim.new(0, 2)
	pad.Parent = scroll

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

local crystalScroll, crystalEmpty

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

local function collectRunes(minTier, limit)
	local hrp = getHRP()
	local rows = {}
	iterRunes(function(part)
		local runeId = getRuneIdFromPart(part)
		local tier = RUNE_RARITY[runeId] or 1
		if tier >= (minTier or 1) then
			local pos = part.Position
			table.insert(rows, {
				part = part,
				tier = tier,
				runeId = runeId,
				name = runeId .. " Rune",
				dist = hrp and math.floor((pos - hrp.Position).Magnitude) or 0,
				color = RUNE_COLORS[tier] or Color3.new(1, 1, 1),
			})
		end
	end)
	table.sort(rows, function(a, b)
		if a.tier ~= b.tier then return a.tier > b.tier end
		return a.dist < b.dist
	end)
	local out = {}
	local n = math.min(limit or 20, #rows)
	for i = 1, n do
		table.insert(out, rows[i])
	end
	return out
end

local function refreshCrystalList()
	local rows
	local isRunes = state.listCategory == "Runes"
	if isRunes then
		rows = collectRunes(state.runeMinRarity, 20)
	else
		rows = collectByExactTier(state.listTier, 20)
	end
	state.crystalMap = {}
	clearListRows()

	if crystalEmpty then
		crystalEmpty.Visible = #rows == 0
	end

	for i, row in ipairs(rows) do
		local btn = Instance.new("TextButton")
		btn.Name = isRunes and "RuneRow" or "CrystalRow"
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
		badge.Text = isRunes and (TIER_BADGE[row.tier] or "?") or (row.dropped and "DROP" or row.badge)
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
		if isRunes then
			info.Text = string.format("%s  [%s]", row.name, TIER_NAMES[row.tier] or "?")
		else
			local luckStr = crystalLuckText(row.part)
			local nameOnly = row.name:gsub("^%[DROP%]%s*", "")
			info.Text = string.format("%s  %.1fkg  %s", nameOnly, row.kg, luckStr)
		end
		info.Parent = btn

		if not isRunes then
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
		end

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

	if state.esp and not isRunes then
		applyESP()
	end
	if state.runeEsp and isRunes then
		applyRuneESP()
	end
	return #rows
end

--========================================================
-- UI
--========================================================
local Window = Library:CreateWindow({
	Title = "Mine a Mountain",
	Footer = "Qentury Hub v4-tes",
	NotifySide = "Right",
	ShowCustomCursor = false,
	Resizable = true,
})

-- Compact sidebar letter badge: Title:sub(1,1) = "M" → force "Q"
task.defer(function()
	for _ = 1, 5 do
		pcall(function()
			local root = Library.ScreenGui
			if not root then
				return
			end
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("TextLabel") and d.TextScaled == true and (d.Text == "M" or d.Text == "m") then
					d.Text = "Q"
				end
			end
		end)
		task.wait(0.15)
	end
end)

-- Floating icon toggle (draggable) — pickaxe
local pickaxeIcon = Library:GetIcon("pickaxe")
local Minimizer = Instance.new("ImageButton")
Minimizer.Name = "Minimizer"
Minimizer.Size = UDim2.fromOffset(40, 40)
Minimizer.AnchorPoint = Vector2.new(0.5, 0)
Minimizer.Position = UDim2.new(0.5, 0, 0, 50)
Minimizer.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
Minimizer.BackgroundTransparency = 0.15
Minimizer.ImageColor3 = Color3.fromRGB(125, 85, 255)
Minimizer.ScaleType = Enum.ScaleType.Fit
Minimizer.Parent = Library.ScreenGui

if pickaxeIcon then
	Minimizer.Image = pickaxeIcon.Url
	Minimizer.ImageRectOffset = pickaxeIcon.ImageRectOffset
	Minimizer.ImageRectSize = pickaxeIcon.ImageRectSize
else
	Minimizer.Image = "rbxassetid://6031068420"
end

local minimCorner = Instance.new("UICorner")
minimCorner.CornerRadius = UDim.new(0, 10)
minimCorner.Parent = Minimizer

local minimStroke = Instance.new("UIStroke")
minimStroke.Color = Color3.fromRGB(125, 85, 255)
minimStroke.Thickness = 1.5
minimStroke.Transparency = 0.4
minimStroke.Parent = Minimizer

Library:MakeDraggable(Minimizer, Minimizer)

Minimizer.MouseButton1Click:Connect(function()
	Window:Toggle()
end)

Library:OnUnload(function()
	pcall(function()
		Minimizer:Destroy()
	end)
end)

local Tabs = {
	Main = Window:AddTab("Main", "gem", "Auto mine + ESP + TP"),
	Boulders = Window:AddTab("Boulders", "box", "ESP + auto break"),
	Runes = Window:AddTab("Runes", "star", "ESP + auto pickup"),
	Terrain = Window:AddTab("Terrain", "layers", "Bomb material ESP"),
	AutoDrop = Window:AddTab("Auto Drop", "minus", "Drop crystals from bag"),
	Favorite = Window:AddTab("Favorite", "star", "Auto favorite crystals"),
	Pickaxes = Window:AddTab("Pickaxes", "pickaxe", "Shop buy / equip"),
	Bombs = Window:AddTab("Bombs", "bomb", "Stock + auto buy"),
	Upgrades = Window:AddTab("Upgrades", "arrow-up", "Warmth / Carry / Plot"),
	Shovels = Window:AddTab("Shovels", "hammer", "Soft dig shop"),
	Backpacks = Window:AddTab("Backpacks", "package", "Weight shop"),
	Misc = Window:AddTab("Misc", "wrench", "QoL utilities"),
	Server = Window:AddTab("Server", "server", "Players / hop / rejoin"),
	Settings = Window:AddTab("Settings", "settings", "UI"),
}

-- single column (left only); right column hidden + left stretched full
local Main = Tabs.Main:AddLeftGroupbox("Main", "gem")

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
				-- Obsidian tab columns are ~0.5 width (sometimes 0.5 + offset)
				if sx > 0.4 and sx < 0.6 then
					table.insert(halves, ch)
				end
			end
		end
		if #halves >= 2 then
			-- widest / first = left content column → full width
			table.sort(halves, function(a, b)
				return a.AbsoluteSize.X > b.AbsoluteSize.X
			end)
			-- prefer the one that has groupbox content
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

-- keep re-applying (tab switch / theme can reset column sizes)
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

Main:AddToggle("AutoMineV2", {
	Text = "Auto Pickup (mine+drop)",
	Default = false,
	Tooltip = "Vacuum in-range: mountain + DroppedCrystals. Instant hold. No TP. Min Rarity filter.",
	Callback = function(v)
		state.autoMineV2 = v
		if v then
			startAutoMineV2()
			Library:Notify({
				Title = "Auto Pickup",
				Description = "ON — mine + drop vacuum",
				Time = 2,
			})
		else
			stopAutoMineV2()
			Library:Notify({
				Title = "Auto Pickup",
				Description = "OFF",
				Time = 2,
			})
		end
	end,
})

Main:AddToggle("AutoMineTPV2", {
	Text = "Auto Pickup TP (mine+drop)",
	Default = false,
	Tooltip = "Vacuum near → TP richest Value$ off-range → instant. Mine + DroppedCrystals.",
	Callback = function(v)
		state.autoMineTPV2 = v
		if v then
			startAutoMineTPV2()
			Library:Notify({
				Title = "Auto Pickup TP",
				Description = "ON — vacuum + TP richest",
				Time = 2,
			})
		else
			stopAutoMineTPV2()
			Library:Notify({
				Title = "Auto Pickup TP",
				Description = "OFF",
				Time = 2,
			})
		end
	end,
})

Main:AddToggle("StripMine", {
	Text = "Strip Mine Mountain",
	Default = false,
	Tooltip = "TP random diggable terrain → dig omni cepat → jeda 5s → repeat. Auto-sell if ON.",
	Callback = function(v)
		if v then
			state.stripMine = true
			startStripMine()
			Library:Notify({
				Title = "Strip Mine",
				Description = "ON — random TP + dig · 5s delay",
				Time = 2,
			})
		else
			stopStripMine()
			if state.stripMineThread then
				task.cancel(state.stripMineThread)
				state.stripMineThread = nil
			end
			Library:Notify({
				Title = "Strip Mine",
				Description = "OFF",
				Time = 2,
			})
		end
	end,
})

Main:AddToggle("AutoDigForward", {
	Text = "Auto Dig Forward",
	Default = false,
	Tooltip = "Manual walk — digs where the camera aims (no TP).",
	Callback = function(v)
		state.autoDigFwd = v
		if v then
			startAutoDigForward()
			Library:Notify({ Title = "Auto Dig Forward", Description = "ON — dig toward camera", Time = 2 })
		else
			stopAutoDigForward()
			Library:Notify({ Title = "Auto Dig Forward", Description = "OFF", Time = 2 })
		end
	end,
})

Main:AddDropdown("MineMinRarity", {
	Text = "Min Rarity (Auto-Mine)",
	Values = TIER_LABELS,
	Default = 1,
	Multi = false,
	Searchable = false,
	Tooltip = "Only mine crystals at this rarity or higher.",
	Callback = function(v)
		state.mineMinTier = rarityToTier(v)
	end,
})

Main:AddLabel("Must stand near crystal.")

Main:AddToggle("AutoSell", {
	Text = "Auto-Sell (At Capacity)",
	Default = false,
	Tooltip = "When bag kg >= % capacity: go to sell zone, SellRequest(\"all\").",
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
	Tooltip = "Trigger auto-sell at this % of carry capacity.",
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

Main:AddDivider()

Main:AddToggle("CharESP", {
	Text = "Player ESP (name + dist)",
	Default = false,
	Tooltip = "Shows player names and distance via billboard above their head.",
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
		Text = "Crystal ESP (box)",
		Default = false,
		Tooltip = "Outline boxes colored by rarity. Filter = rarity dropdown below.",
		Callback = function(v)
			state.esp = v
			if v then
				applyESP()
				task.spawn(function()
					while state.esp and not Library.Unloaded do
						applyESP()
						task.wait(1.5)
					end
				end)
			else
				clearESP()
			end
		end,
	})

	Main:AddToggle("RuneESP", {
		Text = "Rune ESP (box)",
		Default = false,
		Tooltip = "Highlight runes in workspace by rarity.",
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

	Main:AddDropdown("ListCategory", {
		Text = "Category",
		Values = { "Crystals", "Runes" },
		Default = 1,
		Multi = false,
		Searchable = false,
		Tooltip = "Switch between crystal list and rune list.",
		Callback = function(v)
			state.listCategory = v
			refreshCrystalList()
		end,
	})

	Main:AddDropdown("ListRarity", {
		Text = "Rarity (ESP + Top 20 · mountain+drop)",
		Values = TIER_LABELS,
		Default = 5, -- Legendary
		Multi = false,
		Searchable = false,
		Tooltip = "Exact rarity for ESP boxes and crystal/rune list.",
		Callback = function(v)
			state.listTier = rarityToTier(v)
			state.runeMinRarity = rarityToTier(v)
			local n = refreshCrystalList()
			Library:Notify({
				Title = "Rarity",
				Description = string.format("%s · top %d", TIER_NAMES[state.listTier] or v, math.min(n, 20)),
				Time = 2,
			})
		end,
	})

	Main:AddDropdown("ListSortBy", {
		Text = "Sort Crystal List",
		Values = { "Money ($)", "Luck (%)" },
		Default = 1,
		Multi = false,
		Searchable = false,
		Tooltip = "Sort by Value or Luck%. Changed list auto-refreshes.",
		Callback = function(v)
			if v == "Luck (%)" then
				state.listSortBy = "luck"
			else
				state.listSortBy = "money"
			end
			refreshCrystalList()
		end,
	})

	Main:AddLabel("List (Top 20) — click = TP · Crystals/Runes")

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
			Description = string.format("%d crystals (tier %s)", n, TIER_BADGE[state.listTier] or "?"),
			Time = 2,
		})
	end,
})

do -- Pickaxes + Bombs + Upgrades + Favorite + Misc tabs (scope locals)
local PickBox = Tabs.Pickaxes:AddLeftGroupbox("Pickaxe Shop", "pickaxe")

PickBox:AddLabel("Pickaxe Power Stats · Buy / Equip per row.")

pickScroll = buildPickListUI()
PickBox:AddUIPassthrough("PickaxeListUI", {
	Instance = pickScroll,
	Height = PICK_LIST_H,
})

task.spawn(function()
	for _ = 1, 5 do
		task.wait(0.2)
		if pickScroll and pickScroll.Parent and pickScroll.AbsoluteSize.Y > 0 then
			local n = refreshPickList()
			if n > 0 then
				break
			end
		end
	end
end)

PickBox:AddButton({
	Text = "Refresh List",
	Func = function()
		local n = refreshPickList()
		Library:Notify({ Title = "Pickaxes", Description = tostring(n) .. " items", Time = 2 })
	end,
})

PickBox:AddButton({
	Text = "Buy Next Affordable",
	Func = function()
		local p = nextAffordablePickaxe()
		if not p then
			Library:Notify({
				Title = "Pickaxe",
				Description = "Nothing affordable / all owned.",
				Time = 2,
			})
			return
		end
		local ok = shopBuy(p.id)
		task.wait(0.45)
		refreshPickList()
		Library:Notify({
			Title = ok and "Bought" or "Buy failed",
			Description = string.format("%s · %s", p.name or p.id, formatMoney(p.price or 0)),
			Time = 2,
		})
	end,
})

PickBox:AddButton({
	Text = "Equip Best Owned",
	Func = function()
		local p = bestOwnedPickaxe()
		if not p then
			Library:Notify({ Title = "Pickaxe", Description = "No owned pickaxe.", Time = 2 })
			return
		end
		local ok = shopEquip(p.id)
		task.wait(0.35)
		refreshPickList()
		Library:Notify({
			Title = ok and "Equipped" or "Equip failed",
			Description = p.name or p.id,
			Time = 2,
		})
	end,
})

PickBox:AddToggle("AutoBuyPick", {
	Text = "Auto-Buy Next (ladder)",
	Default = false,
	Tooltip = "Buys next unowned pickaxe you can afford (catalog order).",
	Callback = function(v)
		state.autoBuyPick = v
		if v then
			startAutoBuyPick()
		else
			stopAutoBuyPick()
		end
	end,
})

-- Bombs tab
local BombBox = Tabs.Bombs:AddLeftGroupbox("Bomb Shop", "bomb")

queryBombStock()
bombStockLabel = BombBox:AddLabel(buildStockText(), true)

local function refreshBombStockUI()
	queryBombStock()
	if bombStockLabel and bombStockLabel.SetText then
		bombStockLabel:SetText(buildStockText())
	end
end

BombBox:AddButton({
	Text = "Refresh Stock",
	Func = function()
		refreshBombStockUI()
		Library:Notify({
			Title = "Bomb Stock",
			Description = "Updated · restock " .. formatTimer(secondsToRestock()),
			Time = 2,
		})
	end,
})

local bombLabels = bombDropdownLabels()
local classicLabel = bombLabels[1] or "Classic Bomb"
BombBox:AddDropdown("BombSelect", {
	Text = "Bombs to buy (multi)",
	Values = #bombLabels > 0 and bombLabels or BOMB_ORDER,
	Default = { classicLabel },
	Multi = true,
	Searchable = true,
	Tooltip = "Multi-select. Auto-buy prefers higher rarity first when in stock.",
	Callback = function(v)
		syncBombTargetsFromDropdown(v)
	end,
})

BombBox:AddToggle("AutoBuyBomb", {
	Text = "Auto Buy (selected)",
	Default = false,
	Tooltip = "Buys all selected bombs while stock + cash available (rarest first).",
	Callback = function(v)
		state.autoBuyBomb = v
		if v then
			syncBombTargetsFromDropdown(Options.BombSelect and Options.BombSelect.Value)
			startAutoBuyBomb()
		else
			stopAutoBuyBomb()
		end
	end,
})

BombBox:AddButton({
	Text = "Buy Once (all selected)",
	Func = function()
		queryBombStock()
		syncBombTargetsFromDropdown(Options.BombSelect and Options.BombSelect.Value)
		local bought, failed = {}, {}
		for _, id in ipairs(selectedBombIds()) do
			local stock = tonumber(state.bombStock[id]) or 0
			if stock > 0 and getCash() >= bombPrice(id) then
				local ok, info = tryBuyBomb(id)
				if ok then
					table.insert(bought, bombDisplayName(id))
				else
					table.insert(failed, bombDisplayName(id) .. ":" .. tostring(info))
				end
				task.wait(0.35)
			else
				table.insert(failed, bombDisplayName(id) .. ":skip")
			end
		end
		refreshBombStockUI()
		Library:Notify({
			Title = #bought > 0 and "Bought" or "Buy failed",
			Description = (#bought > 0 and table.concat(bought, ", ") or "none")
				.. (#failed > 0 and (" | " .. table.concat(failed, ", ")) or ""),
			Time = 3,
		})
	end,
})

BombBox:AddLabel("Uses cash only (not Robux).\nMulti: rarest-with-stock first.\nStock rolls each hour.")

--========================================================
-- UPGRADES TAB — NexHub style: just buttons
--   UpgradeBuy:FireServer(kind, amount)  kind in {Air, Weight}; amount 1/2/3
--   UpgradePrices:InvokeServer(kind) -> {p1, p2, p3}
--   PlotUpgradeController: UpgradePlotCapacity:FireServer() (no args)
--========================================================
local UPG_KINDS = {
	{ kind = "Air", label = "Warmth +10", amount = 1, key = "Air" },
	{ kind = "Air", label = "Warmth +50", amount = 2, key = "Air" },
	{ kind = "Air", label = "Warmth +100", amount = 3, key = "Air" },
	{ kind = "Weight", label = "Carry +1kg", amount = 1, key = "Weight" },
	{ kind = "Weight", label = "Carry +5kg", amount = 2, key = "Weight" },
	{ kind = "Weight", label = "Carry +10kg", amount = 3, key = "Weight" },
}

local UpgradeBuyRE = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("UpgradeBuy")
local UpgradePricesRF = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("UpgradePrices")
local UpgradePlotRE = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("UpgradePlotCapacity")

local function refreshUpgPrices()
	for _, kind in ipairs({ "Air", "Weight" }) do
		local ok, res = pcall(function()
			return UpgradePricesRF and UpgradePricesRF:InvokeServer(kind)
		end)
		if ok and type(res) == "table" then
			state.upgPrices[kind] = res
		end
	end
end

local function upgPrice(kind, amount)
	local t = state.upgPrices[kind]
	return (type(t) == "table" and tonumber(t[amount])) or 0
end

local function buyUpgrade(kind, amount)
	local price = upgPrice(kind, amount)
	if price > 0 and getCash() < price then
		return false, "no cash"
	end
	local ok, err = pcall(function()
		UpgradeBuyRE:FireServer(kind, amount)
	end)
	task.wait(0.3)
	return ok, err
end

local function buyPlot()
	local ok, err = pcall(function()
		UpgradePlotRE:FireServer()
	end)
	task.wait(0.3)
	return ok, err
end

local UpgBox = Tabs.Upgrades:AddLeftGroupbox("Upgrades", "gem")

refreshUpgPrices()

for _, def in ipairs(UPG_KINDS) do
	local p = upgPrice(def.kind, def.amount)
	local label = string.format("%s [%s]", def.label, formatMoney(p))
	if p > 0 and getCash() < p then
		label = label .. " (insufficient)"
	end
	UpgBox:AddButton({
		Text = label,
		Func = function()
			local ok, err = buyUpgrade(def.kind, def.amount)
			Library:Notify({
				Title = def.label,
				Description = ok and "OK" or tostring(err),
				Time = 2,
			})
		end,
	})
end

UpgBox:AddButton({
	Text = "Plot Capacity",
	Func = function()
		local ok, err = buyPlot()
		Library:Notify({
			Title = "Plot Capacity",
			Description = ok and "OK" or tostring(err),
			Time = 2,
		})
	end,
})

--========================================================
-- FAVORITE TAB
--========================================================
local FavLuckBox = Tabs.Favorite:AddLeftGroupbox("By Luck %", "percent")
local favStatusLabel = FavLuckBox:AddLabel(favCountStatus(), true)

FavLuckBox:AddSlider("FavLuckMin", {
	Text = "Min luck %",
	Default = 4,
	Min = 0.5,
	Max = 20,
	Rounding = 1,
	Tooltip = "Favorite tools with luck > this percent (hub formula).",
	Callback = function(v)
		state.favLuckMin = v
	end,
})

FavLuckBox:AddToggle("AutoFavLuck", {
	Text = "Auto Favorite by Luck",
	Default = false,
	Tooltip = "Loop: favorite backpack tools with luck > min %.",
	Callback = function(v)
		state.autoFavLuck = v
		if v then
			startFavoriteLoop()
			Library:Notify({ Title = "Favorite", Description = "Luck auto ON", Time = 2 })
		else
			stopFavoriteLoopIfIdle()
			Library:Notify({ Title = "Favorite", Description = "Luck auto OFF", Time = 2 })
		end
	end,
})

FavLuckBox:AddButton({
	Text = "Favorite Now (luck filter)",
	Func = function()
		local n = 0
		local minPct = state.favLuckMin or 4
		for _, tool in ipairs(getCrystalTools()) do
			if toolLuckPct(tool) > minPct then
				if setToolFavorite(tool, true) then
					n += 1
				end
				task.wait(0.04)
			end
		end
		if favStatusLabel and favStatusLabel.SetText then
			favStatusLabel:SetText(favCountStatus())
		end
		Library:Notify({ Title = "Favorite Luck", Description = tostring(n) .. " favorited", Time = 2 })
	end,
})

local FavRarBox = Tabs.Favorite:AddLeftGroupbox("By Rarity", "gem")
FavRarBox:AddDropdown("FavRaritySelect", {
	Text = "Rarities to favorite",
	Values = TIER_LABELS,
	Default = { "L · Legendary", "M · Mythic" },
	Multi = true,
	Searchable = false,
	Tooltip = "Multi-select. Auto rarity uses these tiers.",
	Callback = function(v)
		syncFavRarityFromDropdown(v)
	end,
})

FavRarBox:AddToggle("AutoFavRarity", {
	Text = "Auto Favorite by Rarity",
	Default = false,
	Tooltip = "Loop: favorite backpack tools matching selected rarities.",
	Callback = function(v)
		state.autoFavRarity = v
		if v then
			syncFavRarityFromDropdown(Options.FavRaritySelect and Options.FavRaritySelect.Value)
			startFavoriteLoop()
			Library:Notify({ Title = "Favorite", Description = "Rarity auto ON", Time = 2 })
		else
			stopFavoriteLoopIfIdle()
			Library:Notify({ Title = "Favorite", Description = "Rarity auto OFF", Time = 2 })
		end
	end,
})

FavRarBox:AddButton({
	Text = "Favorite Now (rarity filter)",
	Func = function()
		syncFavRarityFromDropdown(Options.FavRaritySelect and Options.FavRaritySelect.Value)
		local n = 0
		for _, tool in ipairs(getCrystalTools()) do
			local tier = tonumber(tool:GetAttribute("Tier")) or 0
			if state.favRarityTiers[tier] then
				if setToolFavorite(tool, true) then
					n += 1
				end
				task.wait(0.04)
			end
		end
		if favStatusLabel and favStatusLabel.SetText then
			favStatusLabel:SetText(favCountStatus())
		end
		Library:Notify({ Title = "Favorite Rarity", Description = tostring(n) .. " favorited", Time = 2 })
	end,
})

local FavBulk = Tabs.Favorite:AddLeftGroupbox("Bulk", "star")
FavBulk:AddButton({
	Text = "Favorite All in Bag",
	Func = function()
		local n = favoriteAllInBag()
		if favStatusLabel and favStatusLabel.SetText then
			favStatusLabel:SetText(favCountStatus())
		end
		Library:Notify({ Title = "Favorite All", Description = tostring(n) .. " tools", Time = 2 })
	end,
})
FavBulk:AddButton({
	Text = "Unfavorite All in Bag",
	Func = function()
		local n = unfavoriteAllInBag()
		if favStatusLabel and favStatusLabel.SetText then
			favStatusLabel:SetText(favCountStatus())
		end
		Library:Notify({ Title = "Unfavorite All", Description = tostring(n) .. " tools", Time = 2 })
	end,
})
FavBulk:AddButton({
	Text = "Refresh Status",
	Func = function()
		if favStatusLabel and favStatusLabel.SetText then
			favStatusLabel:SetText(favCountStatus())
		end
	end,
})

task.spawn(function()
	while not Library.Unloaded do
		task.wait(2)
		if favStatusLabel and favStatusLabel.SetText then
			pcall(function()
				favStatusLabel:SetText(favCountStatus())
			end)
		end
	end
end)

--========================================================
-- MISC TAB
--========================================================
local MiscBox = Tabs.Misc:AddLeftGroupbox("Combat / Fall", "shield")

MiscBox:AddToggle("NoFallDmg", {
	Text = "No Fall Dmg (cap velocity)",
	Default = true,
	Tooltip = "Clamps AssemblyLinearVelocity.Y so hardlanding/ragdoll fall dmg rarely triggers.",
	Callback = function(v)
		if v then
			startNoFallDmg()
		else
			stopNoFallDmg()
		end
	end,
})

MiscBox:AddSlider("FallCap", {
	Text = "Max fall speed (studs/s)",
	Default = 72,
	Min = 40,
	Max = 75,
	Rounding = 0,
	Tooltip = "Lower = safer. Hardlanding triggers above ~75.",
	Callback = function(v)
		state.fallCap = -math.abs(v)
	end,
})

MiscBox:AddToggle("AntiRagdoll", {
	Text = "Anti Ragdoll",
	Default = true,
	Tooltip = "Destroys ragdoll/fall-damage remotes (StarForge-style).",
	Callback = function(v)
		if v then
			startAntiRagdoll()
			Library:Notify({ Title = "Anti Ragdoll", Description = "ON", Time = 2 })
		else
			stopAntiRagdoll()
			Library:Notify({ Title = "Anti Ragdoll", Description = "OFF", Time = 2 })
		end
	end,
})

local MoveBox = Tabs.Misc:AddLeftGroupbox("Movement", "gauge")

MoveBox:AddToggle("FlyToggle", {
	Text = "Fly",
	Default = false,
	Tooltip = "WASD + Space/Ctrl. Camera-relative.",
	Callback = function(v)
		if v then
			startFly()
		else
			stopFly()
		end
	end,
})

MoveBox:AddSlider("FlySpeed", {
	Text = "Fly Speed",
	Default = 50,
	Min = 10,
	Max = 200,
	Rounding = 0,
	Callback = function(v)
		state.flySpeed = v
	end,
})

MoveBox:AddToggle("SpeedBoost", {
	Text = "Speed Boost",
	Default = false,
	Tooltip = "Locks WalkSpeed (disabled while flying).",
	Callback = function(v)
		if v then
			startSpeedBoost()
		else
			stopSpeedBoost()
		end
	end,
})

MoveBox:AddSlider("WalkSpeed", {
	Text = "Walk Speed",
	Default = 32,
	Min = 16,
	Max = 120,
	Rounding = 0,
	Callback = function(v)
		state.walkSpeed = v
	end,
})

local QoLBox = Tabs.Misc:AddLeftGroupbox("QoL", "cpu")

QoLBox:AddToggle("AntiAfk", {
	Text = "Anti AFK",
	Default = true,
	Tooltip = "Idled hook + VirtualUser pulse every 45s (blocks AFK kick).",
	Callback = function(v)
		if v then
			startAntiAfk()
		else
			stopAntiAfk()
		end
	end,
})

QoLBox:AddToggle("AntiLag", {
	Text = "Anti-Lag",
	Default = false,
	Tooltip = "Lowers quality, disables particles/shadows.",
	Callback = function(v)
		applyAntiLag(v)
	end,
})

end -- do Pickaxes..Misc tabs

--========================================================
-- SERVER TAB
--========================================================
local ServerBox = Tabs.Server:AddLeftGroupbox("Players", "users")
local playerNames = playerDropdownValues()
ServerBox:AddDropdown("ServerPlayer", {
	Text = "Player",
	Values = playerNames,
	Default = playerNames[1],
	Multi = false,
	Searchable = true,
})
ServerBox:AddButton({
	Text = "Refresh Players",
	Func = function()
		local vals = playerDropdownValues()
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
ServerBox:AddButton({
	Text = "Teleport to Player",
	Func = function()
		local name = Options.ServerPlayer and Options.ServerPlayer.Value
		local ok, err = teleportToPlayerName(name)
		Library:Notify({
			Title = "TP Player",
			Description = ok and ("→ " .. tostring(name)) or tostring(err),
			Time = 2,
		})
	end,
})

local ActBox = Tabs.Server:AddLeftGroupbox("Server Actions", "server")
ActBox:AddButton({
	Text = "Rejoin",
	Func = function()
		local ok, err = rejoinServer()
		if not ok then
			Library:Notify({ Title = "Rejoin", Description = tostring(err), Time = 3 })
		end
	end,
})
ActBox:AddButton({
	Text = "Hop Server",
	Func = function()
		local ok, err = hopServer()
		if not ok then
			Library:Notify({ Title = "Hop", Description = tostring(err), Time = 3 })
		end
	end,
})
ActBox:AddButton({
	Text = "Reset Character",
	Func = function()
		pcall(function()
			local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Health = 0
			end
		end)
	end,
})
ActBox:AddButton({
	Text = "Go Home",
	Func = function()
		local ok, err = goHome()
		Library:Notify({
			Title = "Go Home",
			Description = ok and "OK" or tostring(err),
			Time = 2,
		})
	end,
})

--========================================================
-- SETTINGS — single column: Menu → Configuration → Themes
-- Docs: https://github.com/deividcomsono/Obsidian
--========================================================
local Menu = Tabs.Settings:AddLeftGroupbox("Menu", "wrench")
Menu:AddToggle("KeybindMenuOpen", {
	Default = Library.KeybindFrame and Library.KeybindFrame.Visible or false,
	Text = "Open Keybind Menu",
	Callback = function(value)
		if Library.KeybindFrame then
			Library.KeybindFrame.Visible = value
		end
	end,
})
Menu:AddToggle("ShowCustomCursor", {
	Text = "Custom Cursor",
	Default = Library.ShowCustomCursor == true,
	Callback = function(Value)
		Library.ShowCustomCursor = Value
	end,
})
Menu:AddDropdown("NotificationSide", {
	Values = { "Left", "Right" },
	Default = "Right",
	Text = "Notification Side",
	Callback = function(Value)
		if Library.SetNotifySide then
			Library:SetNotifySide(Value)
		end
	end,
})
Menu:AddDivider()
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
SaveManager:SetFolder("QenturyHub/MineAMountainV4")

-- BuildConfigSection uses AddRightGroupbox by default → force Left (single column stack)
-- Order: Menu → Configuration → Themes
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
elseif ThemeManager.AddThemeOptions then
	ThemeManager:AddThemeOptions(Tabs.Settings)
elseif ThemeManager.ApplyToGroupbox then
	local themeBox = Tabs.Settings:AddLeftGroupbox("Themes", "paintbrush")
	ThemeManager:ApplyToGroupbox(themeBox)
end

if SaveManager.LoadAutoloadConfig then
	task.defer(function()
		pcall(function()
			SaveManager:LoadAutoloadConfig()
		end)
	end)
end

-- cleanup
local function stopFeatures()
	state.autoMineV2 = false
	state.autoMineTPV2 = false
	state.stripMine = false
	state.autoDigFwd = false
	state.autoFavLuck = false
	state.autoFavRarity = false
	state.esp = false
	state.charEsp = false
	state.runeEsp = false
	state.autoBuyBomb = false
	state.autoSell = false
	state.autoBuyPick = false
	stopNoFallDmg()
	stopAntiAfk()
	stopAntiRagdoll()
	stopFly()
	stopSpeedBoost()
	if state.antiLag then
		applyAntiLag(false)
	end
	clearESP()
	clearCharESP()
	clearRuneESP()
end

getgenv().MaMQenturyCleanup = function()
	stopFeatures()
	pcall(function()
		if Library and not Library.Unloaded then
			Library:Unload()
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
end
getgenv().MaMObsidianCleanup = getgenv().MaMQenturyCleanup

Library:OnUnload(stopFeatures)

-- initial list + full-width main layout
task.defer(function()
	task.wait(0.2)
	forceFullWidthTabs()
	-- re-apply when user clicks tab buttons
	pcall(function()
		local root = Library.ScreenGui
		if not root then
			return
		end
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("TextButton") or d:IsA("ImageButton") then
				d.MouseButton1Click:Connect(function()
					task.defer(forceFullWidthTabs)
					task.delay(0.05, forceFullWidthTabs)
					task.delay(0.2, forceFullWidthTabs)
				end)
			end
		end
	end)
	state.listTier = rarityToTier(Options.ListRarity and Options.ListRarity.Value) or 5
	state.mineMinTier = rarityToTier(Options.MineMinRarity and Options.MineMinRarity.Value) or 1
	syncBombTargetsFromDropdown(Options.BombSelect and Options.BombSelect.Value)
	refreshCrystalList()
	refreshBombStockUI()
	refreshPickList()
	-- defaults ON
	startNoFallDmg()
	startAntiRagdoll()
	startAntiAfk()
	task.spawn(function()
		while not Library.Unloaded do
			task.wait(5)
			refreshBombStockUI()
		end
	end)
	task.spawn(function()
		while not Library.Unloaded do
			task.wait(3)
			refreshCrystalList()
		end
	end)
end)

-- expose API for v4 extras (separate loadstring = fresh register pool)
getgenv().MaMV4API = {
	Library = Library,
	Window = Window,
	Tabs = Tabs,
	LP = LP,
	ReplicatedStorage = ReplicatedStorage,
	ShopCatalog = ShopCatalog,
	shopBuy = shopBuy,
	shopEquip = shopEquip,
	steppedTeleport = steppedTeleport,
	getHRP = getHRP,
	getCash = getCash,
	formatMoney = formatMoney,
	TIER_COLORS = TIER_COLORS,
	toolLuckPct = toolLuckPct,
	getCrystalTools = getCrystalTools,
	Options = Options,
	Toggles = Toggles,
}

-- v4 extras embedded (loadstring = separate register pool)
local V4_EXTRAS_SRC = [=[
-- Qentury v4 extras — loaded via loadstring (own register pool)
-- Requires getgenv().MaMV4API
local API = getgenv().MaMV4API
if not API then
	return
end

local Library = API.Library
local Tabs = API.Tabs
local LP = API.LP
local ReplicatedStorage = API.ReplicatedStorage
local ShopCatalog = API.ShopCatalog
local shopBuy = API.shopBuy
local shopEquip = API.shopEquip
local steppedTeleport = API.steppedTeleport
local getHRP = API.getHRP
local getCash = API.getCash
local formatMoney = API.formatMoney
local TIER_COLORS = API.TIER_COLORS
local toolLuckPct = API.toolLuckPct
local getCrystalTools = API.getCrystalTools
local Options = API.Options
local Toggles = API.Toggles

local state = {
	boulderEsp = false,
	runeEsp = false,
	autoBreak = false,
	autoPickupRune = false,
	breakThread = nil,
	runeThread = nil,
	boulderHl = {},
	runeHl = {},
	minBoulderRarity = 1,
	minRuneRarity = 1,
	-- auto drop
	dropMode = nil, -- "all" | "luck" | "value" | nil
	dropThread = nil,
	dropDelay = 0.2,
	dropSkipFav = true,
	dropLuckMin = 10, -- drop luck >= this %
	dropValueTarget = 1e9, -- $1B default
	dropRunes = false,
	dropRuneThread = nil,
	dropRuneSelected = {}, -- RuneId -> true
	dropRuneAmount = 1, -- per selected type per run
	dropStatCount = 0,
	dropStatValue = 0,
	-- terrain bomb ESP
	terrainEsp = false,
	terrainEspThread = nil,
	terrainMarkers = {}, -- {part=..., key=...}
	terrainRadius = 160,
	terrainStep = 8,
	terrainFilter = {
		ClassicBomb = true,
		WindBomb = true,
		IceBomb = true,
		FireBomb = true,
		ThunderBomb = true,
		PoisonBomb = true,
		TimeBomb = true,
		AgonyBomb = true,
	},
}

local RUNE_DROP_LIST = {
	{ id = "LuckRune", name = "Luck Rune" },
	{ id = "HasteRune", name = "Haste Rune" },
	{ id = "StormRune", name = "Storm Rune" },
	{ id = "WeightRune", name = "Weight Rune" },
	{ id = "FortuneRune", name = "Fortune Rune" },
	{ id = "DetonationRune", name = "Detonation Rune" },
	{ id = "PreservationRune", name = "Preservation Rune" },
	{ id = "WarmthRune", name = "Warmth Rune" },
	{ id = "ExcavatorRune", name = "Excavator Rune" },
	{ id = "ColossusRune", name = "Colossus Rune" },
}

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
local BOULDER_TIER = {
	Mossite = 1,
	Voltite = 2,
	Gildrite = 3,
	Rimeveil = 4,
	Nocturnite = 5,
}

local function invOwned(cat, id)
	local inv = LP:FindFirstChild("PlayerData") and LP.PlayerData:FindFirstChild("Inventory")
	local folder = inv and inv:FindFirstChild(cat)
	local owned = folder and folder:FindFirstChild("Owned")
	if not owned then
		return false
	end
	local v = owned:FindFirstChild(id)
	if v and v.Value == true then
		return true
	end
	if cat == "Shovels" and id == "SplinteredPaddle" then
		local b = owned:FindFirstChild("ShovelBasic")
		return b and b.Value == true
	end
	return false
end

local function invEquipped(cat)
	local inv = LP:FindFirstChild("PlayerData") and LP.PlayerData:FindFirstChild("Inventory")
	local folder = inv and inv:FindFirstChild(cat)
	local eq = folder and folder:FindFirstChild("Equipped")
	return eq and tostring(eq.Value) or ""
end

local function makeScroll()
	local scroll = Instance.new("ScrollingFrame")
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

local function clearScroll(scroll)
	if not scroll then
		return
	end
	for _, ch in ipairs(scroll:GetChildren()) do
		if ch:IsA("Frame") or ch:IsA("TextButton") then
			ch:Destroy()
		end
	end
end

local function addShopRow(scroll, i, opts)
	local row = Instance.new("Frame")
	row.LayoutOrder = i
	row.Size = UDim2.new(1, 0, 0, 36)
	row.BackgroundColor3 = opts.equipped and Color3.fromRGB(22, 38, 28) or Color3.fromRGB(28, 28, 34)
	row.BorderSizePixel = 0
	row.Parent = scroll
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = row

	local badge = Instance.new("TextLabel")
	badge.BackgroundColor3 = Color3.fromRGB(255, 170, 40)
	badge.BackgroundTransparency = 0.15
	badge.Size = UDim2.fromOffset(44, 18)
	badge.Position = UDim2.fromOffset(4, 3)
	badge.Font = Enum.Font.GothamBold
	badge.TextSize = 11
	badge.TextColor3 = Color3.new(1, 1, 1)
	badge.Text = opts.badge or "?"
	badge.Parent = row
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 3)
	bc.Parent = badge

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(52, 0)
	name.Size = UDim2.new(1, -150, 0, 18)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 12
	name.TextColor3 = opts.equipped and Color3.fromRGB(120, 220, 160) or Color3.fromRGB(230, 230, 235)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = opts.name or "?"
	name.Parent = row

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromOffset(52, 18)
	sub.Size = UDim2.new(1, -150, 0, 14)
	sub.Font = Enum.Font.Gotham
	sub.TextSize = 10
	sub.TextColor3 = Color3.fromRGB(150, 150, 165)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Text = opts.sub or ""
	sub.Parent = row

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromOffset(88, 22)
	btn.Position = UDim2.new(1, -94, 0.5, -11)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 11
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	local bbc = Instance.new("UICorner")
	bbc.CornerRadius = UDim.new(0, 4)
	bbc.Parent = btn
	btn.Parent = row

	if opts.equipped then
		btn.Text = "Equipped"
		btn.BackgroundColor3 = Color3.fromRGB(60, 120, 80)
		btn.Active = false
	elseif opts.owned then
		btn.Text = "Equip"
		btn.BackgroundColor3 = Color3.fromRGB(50, 100, 180)
		btn.MouseButton1Click:Connect(function()
			if opts.onEquip then
				opts.onEquip()
			end
		end)
	elseif opts.price and opts.price > 0 and getCash() >= opts.price then
		btn.Text = "Buy " .. formatMoney(opts.price)
		btn.BackgroundColor3 = Color3.fromRGB(40, 150, 90)
		btn.MouseButton1Click:Connect(function()
			if opts.onBuy then
				opts.onBuy()
			end
		end)
	elseif opts.price and opts.price <= 0 then
		btn.Text = "Free"
		btn.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
		btn.Active = false
	else
		btn.Text = formatMoney(opts.price or 0)
		btn.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
		btn.Active = false
	end
end

local shovelScroll, packScroll, boulderScroll, runeScroll

local function refreshShovels()
	clearScroll(shovelScroll)
	if not shovelScroll then
		return 0
	end
	local list = (ShopCatalog and ShopCatalog.Shovels) or {}
	local eq = invEquipped("Shovels")
	local n = 0
	for i, s in ipairs(list) do
		n += 1
		local dig = s.stats and tonumber(s.stats.DigPower) or 0
		local price = tonumber(s.price) or 0
		local isEq = eq == s.id or (s.id == "SplinteredPaddle" and eq == "ShovelBasic")
		addShopRow(shovelScroll, i, {
			name = s.name or s.id,
			badge = string.format("%.1f", dig),
			sub = "Dig " .. string.format("%.1f", dig) .. " · " .. formatMoney(price),
			owned = invOwned("Shovels", s.id) or isEq,
			equipped = isEq,
			price = price,
			onBuy = function()
				local ok = shopBuy(s.id)
				task.wait(0.4)
				refreshShovels()
				Library:Notify({ Title = ok and "Bought" or "Buy fail", Description = s.name or s.id, Time = 2 })
			end,
			onEquip = function()
				local ok = shopEquip(s.id)
				task.wait(0.35)
				refreshShovels()
				Library:Notify({ Title = ok and "Equipped" or "Equip fail", Description = s.name or s.id, Time = 2 })
			end,
		})
	end
	return n
end

local function refreshPacks()
	clearScroll(packScroll)
	if not packScroll then
		return 0
	end
	local list = (ShopCatalog and ShopCatalog.Backpacks) or {}
	local eq = invEquipped("Backpacks")
	local n = 0
	for i, b in ipairs(list) do
		n += 1
		local kg = b.stats and tonumber(b.stats.WeightLimit) or 0
		local price = tonumber(b.price) or 0
		local isEq = eq == b.id
		addShopRow(packScroll, i, {
			name = b.name or b.id,
			badge = tostring(kg),
			sub = kg .. " kg · " .. formatMoney(price),
			owned = invOwned("Backpacks", b.id) or isEq,
			equipped = isEq,
			price = price,
			onBuy = function()
				local ok = shopBuy(b.id)
				task.wait(0.4)
				refreshPacks()
				Library:Notify({ Title = ok and "Bought" or "Buy fail", Description = b.name or b.id, Time = 2 })
			end,
			onEquip = function()
				local ok = shopEquip(b.id)
				task.wait(0.35)
				refreshPacks()
				Library:Notify({ Title = ok and "Equipped" or "Equip fail", Description = b.name or b.id, Time = 2 })
			end,
		})
	end
	return n
end

local function boulderFolder()
	local md = workspace:FindFirstChild("MountainDecorations")
	return md and md:FindFirstChild("Boulders")
end

local function boulderPrimary(model)
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function iterBoulders(fn)
	local folder = boulderFolder()
	if not folder then
		return
	end
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("BoulderName") then
			fn(m)
		end
	end
end

local function clearBoulderESP()
	for m, hl in pairs(state.boulderHl) do
		pcall(function()
			hl:Destroy()
		end)
		state.boulderHl[m] = nil
	end
end

local function applyBoulderESP()
	clearBoulderESP()
	if not state.boulderEsp then
		return
	end
	iterBoulders(function(m)
		local name = m:GetAttribute("BoulderName") or m.Name
		local tier = BOULDER_TIER[name] or 1
		if tier < state.minBoulderRarity then
			return
		end
		local color = (TIER_COLORS and TIER_COLORS[tier]) or Color3.new(1, 1, 1)
		local hl = Instance.new("Highlight")
		hl.Name = "MaMV4_BoulderESP"
		hl.Adornee = m
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.FillColor = color
		hl.OutlineColor = color
		hl.FillTransparency = 0.55
		hl.OutlineTransparency = 0.05
		hl.Parent = m
		state.boulderHl[m] = hl
	end)
end

local function getPickName()
	local c = LP.Character
	if not c then
		return nil
	end
	local tool = c:FindFirstChildOfClass("Tool")
	if tool and not tool:GetAttribute("Tier") then
		local n = tool.Name
		if not n:find("Bomb") and n ~= "Push" then
			return n
		end
	end
	local hum = c:FindFirstChildOfClass("Humanoid")
	local bp = LP:FindFirstChild("Backpack")
	if not bp or not hum then
		return nil
	end
	local prefer = {
		"The Terminus",
		"Singularity",
		"Voidreign",
		"Nebular Throne",
		"Eclipse Fang",
		"Astral Rend",
		"Celestial Apex",
		"Tempest Pick",
		"Obsidian Edge",
		"Volcano Basalt",
		"Emerald Carver",
		"Frostbite Pick",
		"Titanium Spike",
		"Reinforced Steel",
		"Diamond Pickaxe",
		"Shark Pickaxe",
	}
	for _, want in ipairs(prefer) do
		local t = bp:FindFirstChild(want)
		if t and t:IsA("Tool") then
			pcall(function()
				hum:EquipTool(t)
			end)
			task.wait(0.15)
			local eq = c:FindFirstChildOfClass("Tool")
			return eq and eq.Name or want
		end
	end
	return nil
end

local function digAt(toolName, pos)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local dig = remotes and remotes:FindFirstChild("DigRequest")
	if not dig or not toolName then
		return false
	end
	return pcall(function()
		dig:FireServer(toolName, pos)
	end)
end

local function breakBoulderOnce(model)
	local pp = boulderPrimary(model)
	if not pp then
		return false, "no part"
	end
	local hrp = getHRP()
	if not hrp then
		return false, "no hrp"
	end
	local stand = pp.Position + Vector3.new(0, 4, 6)
	local ok = steppedTeleport(stand, 10)
	if not ok then
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
	-- hit until destroyed / HP 0 (Mossite ~240 swings; Nocturnite much more)
	local hits = 0
	local maxHits = 8000
	local stallHits = 0
	local lastHp = hp0
	local forced = state._forceBreak == true
	while model.Parent and hits < maxHits do
		-- stop if auto-break toggle off (unless Break Nearest one-shot)
		if not forced and not state.autoBreak then
			return false, string.format("stopped · hits %d", hits)
		end
		local hp = tonumber(model:GetAttribute("HP")) or 0
		if hp <= 0 then
			break
		end
		if hits % 12 == 0 then
			local pp2 = boulderPrimary(model)
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
			digAt(toolName, cell.Position)
		else
			local pp2 = boulderPrimary(model)
			if pp2 then
				digAt(toolName, pp2.Position)
			end
		end
		hits += 1
		task.wait(0.055)
		if hits % 25 == 0 then
			local hpNow = tonumber(model:GetAttribute("HP")) or 0
			if hpNow >= lastHp - 1 then
				stallHits += 1
				if stallHits >= 2 then
					local pp2 = boulderPrimary(model)
					if pp2 then
						stand = pp2.Position + Vector3.new(0, 3, 2)
						steppedTeleport(stand, 3)
					end
					toolName = getPickName() or toolName
					-- rebuild cell list (boulder may fragment)
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
	return gone, string.format("hits %d · dHP %d%s", hits, math.floor(hp0 - hp1), gone and " · broke" or " · stuck")
end

local function nearestBoulder(minTier)
	local hrp = getHRP()
	if not hrp then
		return nil
	end
	local best, bestD
	iterBoulders(function(m)
		local name = m:GetAttribute("BoulderName") or m.Name
		local tier = BOULDER_TIER[name] or 1
		if tier < (minTier or 1) then
			return
		end
		local pp = boulderPrimary(m)
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

local function getRuneId(part)
	return (part.Name or ""):gsub("%s*Rune%s*", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function iterRunes(fn)
	for _, v in ipairs(workspace:GetDescendants()) do
		if v:IsA("BasePart") and v.Name:find("Rune", 1, true) then
			fn(v)
		end
	end
end

local function clearRuneESP()
	for p, hl in pairs(state.runeHl) do
		pcall(function()
			hl:Destroy()
		end)
		state.runeHl[p] = nil
	end
end

local function applyRuneESP()
	clearRuneESP()
	if not state.runeEsp then
		return
	end
	iterRunes(function(part)
		local id = getRuneId(part)
		local tier = RUNE_RARITY[id] or 1
		if tier < state.minRuneRarity then
			return
		end
		local color = (TIER_COLORS and TIER_COLORS[tier]) or Color3.fromRGB(190, 130, 255)
		local hl = Instance.new("Highlight")
		hl.Name = "MaMV4_RuneESP"
		hl.Adornee = part
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.FillColor = color
		hl.OutlineColor = color
		hl.FillTransparency = 0.45
		hl.OutlineTransparency = 0.05
		hl.Parent = part
		state.runeHl[part] = hl
	end)
end

local function pickupNearbyRunes()
	local hrp = getHRP()
	if not hrp then
		return 0
	end
	local n = 0
	iterRunes(function(part)
		if not part.Parent then
			return
		end
		local d = (part.Position - hrp.Position).Magnitude
		if d > 80 then
			return
		end
		if d > 12 then
			steppedTeleport(part.Position + Vector3.new(0, 3, 0), 4)
		end
		for _, d2 in ipairs(part:GetDescendants()) do
			if d2:IsA("ProximityPrompt") then
				pcall(function()
					fireproximityprompt(d2)
				end)
				n += 1
			end
		end
	end)
	return n
end

local function stopAutoBreak()
	state.autoBreak = false
	state._forceBreak = false
	-- thread exits on next hit check / loop iteration
end

local function startAutoBreak()
	if state.breakThread then
		return
	end
	state.autoBreak = true
	state.breakThread = task.spawn(function()
		while state.autoBreak and not Library.Unloaded do
			local m = nearestBoulder(state.minBoulderRarity)
			if not state.autoBreak then
				break
			end
			if not m then
				Library:Notify({ Title = "Auto Break", Description = "No boulder", Time = 2 })
				task.wait(2)
			else
				local name = m:GetAttribute("BoulderName") or m.Name
				local ok, msg = breakBoulderOnce(m)
				if not state.autoBreak then
					break
				end
				Library:Notify({
					Title = ok and "Broke " .. name or "Break " .. name,
					Description = tostring(msg),
					Time = 2,
				})
				if not ok then
					task.wait(1.2)
				else
					task.wait(0.5)
					if state.autoPickupRune then
						pickupNearbyRunes()
					end
				end
			end
			task.wait(0.15)
		end
		state.breakThread = nil
	end)
end

local function startAutoPickup()
	if state.runeThread then
		return
	end
	state.runeThread = task.spawn(function()
		while state.autoPickupRune and not Library.Unloaded do
			local n = pickupNearbyRunes()
			if n > 0 then
				Library:Notify({ Title = "Rune Pickup", Description = "fired " .. n, Time = 1.5 })
			end
			task.wait(1.2)
		end
		state.runeThread = nil
	end)
end

local function refreshBoulders()
	clearScroll(boulderScroll)
	if not boulderScroll then
		return 0
	end
	local hrp = getHRP()
	local rows = {}
	iterBoulders(function(m)
		local name = m:GetAttribute("BoulderName") or m.Name
		local tier = BOULDER_TIER[name] or 1
		if tier < state.minBoulderRarity then
			return
		end
		local pp = boulderPrimary(m)
		local hp = tonumber(m:GetAttribute("HP")) or 0
		local maxHp = tonumber(m:GetAttribute("MaxHP")) or hp
		local dist = (hrp and pp) and math.floor((pp.Position - hrp.Position).Magnitude) or 0
		table.insert(rows, {
			model = m,
			name = name,
			tier = tier,
			hp = hp,
			maxHp = maxHp,
			dist = dist,
			rarity = m:GetAttribute("Rarity") or "?",
			color = (TIER_COLORS and TIER_COLORS[tier]) or Color3.new(1, 1, 1),
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
		btn.Parent = boulderScroll
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
			local pp = boulderPrimary(model)
			if pp then
				steppedTeleport(pp.Position + Vector3.new(0, 4, 6), 10)
			end
		end)
	end
	return #rows
end

local function refreshRunes()
	clearScroll(runeScroll)
	if not runeScroll then
		return 0
	end
	local hrp = getHRP()
	local rows = {}
	iterRunes(function(part)
		local id = getRuneId(part)
		local tier = RUNE_RARITY[id] or 1
		if tier < state.minRuneRarity then
			return
		end
		local dist = hrp and math.floor((part.Position - hrp.Position).Magnitude) or 0
		table.insert(rows, {
			part = part,
			id = id,
			tier = tier,
			dist = dist,
			color = (TIER_COLORS and TIER_COLORS[tier]) or Color3.fromRGB(190, 130, 255),
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
		info.Text = string.format("%s Rune · %dm", row.id, row.dist)
		info.Parent = btn
		local part = row.part
		btn.MouseButton1Click:Connect(function()
			if part and part.Parent then
				steppedTeleport(part.Position + Vector3.new(0, 3, 0), 6)
				task.wait(0.2)
				for _, d in ipairs(part:GetDescendants()) do
					if d:IsA("ProximityPrompt") then
						pcall(function()
							fireproximityprompt(d)
						end)
					end
				end
			end
		end)
	end
	return #rows
end

-- tabs pre-created by hub (order: Main → Boulders → Runes → … → Upgrades → Shovels → Backpacks)
local TabBoulders = Tabs.Boulders
local TabRunes = Tabs.Runes
local TabShovels = Tabs.Shovels
local TabPacks = Tabs.Backpacks

local ShovelBox = TabShovels:AddLeftGroupbox("Shovel Shop", "hammer")
ShovelBox:AddLabel("Soft terrain · DigPower badge")
shovelScroll = makeScroll()
ShovelBox:AddUIPassthrough("V4ShovelList", { Instance = shovelScroll, Height = 260 })
ShovelBox:AddButton({
	Text = "Refresh",
	Func = function()
		Library:Notify({ Title = "Shovels", Description = refreshShovels() .. " items", Time = 2 })
	end,
})

local PackBox = TabPacks:AddLeftGroupbox("Backpack Shop", "package")
PackBox:AddLabel("WeightLimit (kg)")
packScroll = makeScroll()
PackBox:AddUIPassthrough("V4PackList", { Instance = packScroll, Height = 260 })
PackBox:AddButton({
	Text = "Refresh",
	Func = function()
		Library:Notify({ Title = "Backpacks", Description = refreshPacks() .. " items", Time = 2 })
	end,
})

local BBox = TabBoulders:AddLeftGroupbox("Boulders", "box")
BBox:AddToggle("V4BoulderESP", {
	Text = "Boulder ESP",
	Default = false,
	Callback = function(v)
		state.boulderEsp = v
		if v then
			applyBoulderESP()
			task.spawn(function()
				while state.boulderEsp and not Library.Unloaded do
					applyBoulderESP()
					task.wait(2)
				end
			end)
		else
			clearBoulderESP()
		end
	end,
})
BBox:AddDropdown("V4BoulderMin", {
	Text = "Min Boulder Rarity",
	Values = { "C · Common", "U · Uncommon", "R · Rare", "E · Epic", "L · Legendary" },
	Default = 1,
	Callback = function(v)
		local map = { C = 1, U = 2, R = 3, E = 4, L = 5 }
		state.minBoulderRarity = map[type(v) == "string" and v:match("^([CUREL])") or "C"] or 1
		refreshBoulders()
		if state.boulderEsp then
			applyBoulderESP()
		end
	end,
})
BBox:AddToggle("V4AutoBreak", {
	Text = "Auto Break Boulder",
	Default = false,
	Callback = function(v)
		if v then
			startAutoBreak()
			Library:Notify({ Title = "Auto Break", Description = "ON", Time = 2 })
		else
			stopAutoBreak()
			Library:Notify({ Title = "Auto Break", Description = "OFF", Time = 2 })
		end
	end,
})
BBox:AddButton({
	Text = "Break Nearest Now",
	Func = function()
		local m = nearestBoulder(state.minBoulderRarity)
		if not m then
			Library:Notify({ Title = "Break", Description = "No boulder", Time = 2 })
			return
		end
		task.spawn(function()
			state._forceBreak = true
			local ok, msg = breakBoulderOnce(m)
			state._forceBreak = false
			Library:Notify({ Title = ok and "Break" or "Fail", Description = tostring(msg), Time = 2 })
		end)
	end,
})
boulderScroll = makeScroll()
BBox:AddUIPassthrough("V4BoulderList", { Instance = boulderScroll, Height = 200 })
BBox:AddButton({
	Text = "Refresh List",
	Func = function()
		Library:Notify({ Title = "Boulders", Description = refreshBoulders() .. " found", Time = 2 })
	end,
})

local RBox = TabRunes:AddLeftGroupbox("Runes", "star")
RBox:AddToggle("V4RuneESP", {
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
RBox:AddDropdown("V4RuneMin", {
	Text = "Min Rune Rarity",
	Values = { "C · Common", "U · Uncommon", "R · Rare", "L · Legendary", "M · Mythic" },
	Default = 1,
	Callback = function(v)
		local map = { C = 1, U = 2, R = 3, L = 5, M = 6 }
		state.minRuneRarity = map[type(v) == "string" and v:match("^([CURLM])") or "C"] or 1
		refreshRunes()
		if state.runeEsp then
			applyRuneESP()
		end
	end,
})
RBox:AddToggle("V4AutoPickupRune", {
	Text = "Auto Pickup Runes",
	Default = false,
	Callback = function(v)
		state.autoPickupRune = v
		if v then
			startAutoPickup()
			Library:Notify({ Title = "Rune Pickup", Description = "ON", Time = 2 })
		else
			state.autoPickupRune = false
			Library:Notify({ Title = "Rune Pickup", Description = "OFF", Time = 2 })
		end
	end,
})
RBox:AddButton({
	Text = "Pickup Nearby Now",
	Func = function()
		Library:Notify({ Title = "Rune Pickup", Description = "fired " .. pickupNearbyRunes(), Time = 2 })
	end,
})
runeScroll = makeScroll()
RBox:AddUIPassthrough("V4RuneList", { Instance = runeScroll, Height = 200 })
RBox:AddButton({
	Text = "Refresh List",
	Func = function()
		Library:Notify({ Title = "Runes", Description = refreshRunes() .. " found", Time = 2 })
	end,
})

--========================================================
-- AUTO DROP (CrystalDropRequest:FireServer(tool.Name))
-- Modes mutual exclusive: all | luck | value
--========================================================
local function listDroppableCrystals()
	local tools = {}
	if type(getCrystalTools) == "function" then
		tools = getCrystalTools() or {}
	else
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
		scan(LP:FindFirstChild("Backpack"))
		scan(LP.Character)
	end
	return tools
end

local function crystalValue(tool)
	return tonumber(tool:GetAttribute("Value")) or 0
end

local function crystalLuck(tool)
	if type(toolLuckPct) == "function" then
		local ok, v = pcall(toolLuckPct, tool)
		if ok and type(v) == "number" then
			return v
		end
	end
	return 0
end

local function canDropTool(tool)
	if not tool or not tool.Parent then
		return false
	end
	if tool:GetAttribute("Tier") == nil then
		return false
	end
	if state.dropSkipFav and tool:GetAttribute("Favorited") == true then
		return false
	end
	return true
end

local function fireDropTool(tool)
	if not canDropTool(tool) then
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

local function stopAutoDrop()
	state.dropMode = nil
end

local function dropStatusText()
	local target = tonumber(state.dropValueTarget) or 0
	local mode = state.dropMode or "off"
	return string.format(
		"Live status\nMode: %s\nJumlah drop crystal: %d\nTotal value: %s / %s",
		mode,
		state.dropStatCount or 0,
		formatMoney(state.dropStatValue or 0),
		formatMoney(target)
	)
end

local dropStatusLabel

local function refreshDropStatus()
	if dropStatusLabel and dropStatusLabel.SetText then
		pcall(function()
			dropStatusLabel:SetText(dropStatusText())
		end)
	end
end

local function startAutoDropLoop()
	if state.dropThread then
		return
	end
	-- reset stats when a mode starts
	state.dropStatCount = 0
	state.dropStatValue = 0
	refreshDropStatus()
	state.dropThread = task.spawn(function()
		while state.dropMode and not Library.Unloaded do
			local mode = state.dropMode
			local delay = math.clamp(tonumber(state.dropDelay) or 0.2, 0.05, 1)
			local tools = listDroppableCrystals()
			local dropped = 0

			if mode == "all" then
				for _, tool in ipairs(tools) do
					if state.dropMode ~= "all" or Library.Unloaded then
						break
					end
					if canDropTool(tool) then
						local v = crystalValue(tool)
						if fireDropTool(tool) then
							dropped += 1
							state.dropStatCount += 1
							state.dropStatValue += v
							refreshDropStatus()
							task.wait(delay)
						end
					end
				end
				if dropped == 0 then
					task.wait(1)
					refreshDropStatus()
				end
			elseif mode == "luck" then
				local thr = tonumber(state.dropLuckMin) or 10
				local any = false
				for _, tool in ipairs(tools) do
					if state.dropMode ~= "luck" or Library.Unloaded then
						break
					end
					if canDropTool(tool) and crystalLuck(tool) >= thr then
						any = true
						local v = crystalValue(tool)
						if fireDropTool(tool) then
							dropped += 1
							state.dropStatCount += 1
							state.dropStatValue += v
							refreshDropStatus()
							task.wait(delay)
						end
					end
				end
				if not any then
					task.wait(1)
					refreshDropStatus()
				end
			elseif mode == "value" then
				local target = tonumber(state.dropValueTarget) or 0
				if target <= 0 then
					task.wait(1)
				else
					local list = {}
					for _, tool in ipairs(tools) do
						if canDropTool(tool) then
							table.insert(list, tool)
						end
					end
					table.sort(list, function(a, b)
						return crystalValue(a) < crystalValue(b)
					end)
					-- continue from session sum (continuous across batches)
					local sessionSum = state.dropStatValue or 0
					for _, tool in ipairs(list) do
						if state.dropMode ~= "value" or Library.Unloaded then
							break
						end
						if sessionSum >= target then
							break
						end
						local v = crystalValue(tool)
						if fireDropTool(tool) then
							sessionSum += v
							state.dropStatCount += 1
							state.dropStatValue = sessionSum
							dropped += 1
							refreshDropStatus()
							task.wait(delay)
						end
					end
					if sessionSum >= target then
						-- keep mode on but idle until more crystals / target raised
						task.wait(1.2)
					elseif dropped == 0 then
						task.wait(1)
					else
						task.wait(0.5)
					end
					refreshDropStatus()
				end
			else
				break
			end
		end
		state.dropThread = nil
		refreshDropStatus()
	end)
end

local DropBox = Tabs.AutoDrop:AddLeftGroupbox("Auto Drop", "minus")
DropBox:AddLabel("CrystalDropRequest(tool.Name) · 1 mode only")
DropBox:AddLabel("Not sell — drops to ground (DroppedCrystals)")
dropStatusLabel = DropBox:AddLabel(dropStatusText(), true)

DropBox:AddToggle("V4DropAll", {
	Text = "Drop All crystals",
	Default = false,
	Tooltip = "Drops every crystal until empty. Toggle ON twice to confirm.",
	Callback = function(v)
		if v then
			if not state._dropAllConfirm then
				state._dropAllConfirm = true
				Library:Notify({
					Title = "Drop All — confirm",
					Description = "Toggle ON again within 5s to start",
					Time = 4,
				})
				task.delay(5, function()
					state._dropAllConfirm = false
				end)
				task.defer(function()
					pcall(function()
						if Toggles.V4DropAll then
							Toggles.V4DropAll:SetValue(false)
						end
					end)
				end)
				return
			end
			state._dropAllConfirm = false
			state.dropMode = "all"
			pcall(function()
				if Toggles.V4DropLuck and Toggles.V4DropLuck.Value then
					Toggles.V4DropLuck:SetValue(false)
				end
				if Toggles.V4DropValue and Toggles.V4DropValue.Value then
					Toggles.V4DropValue:SetValue(false)
				end
			end)
			startAutoDropLoop()
			Library:Notify({
				Title = "Drop All",
				Description = "ON — dumping bag",
				Time = 2,
			})
		else
			if state.dropMode == "all" then
				stopAutoDrop()
			end
			Library:Notify({ Title = "Drop All", Description = "OFF", Time = 2 })
		end
	end,
})

local luckLabels = {}
for i = 0, 10 do
	table.insert(luckLabels, tostring(i * 10) .. "%")
end
DropBox:AddDropdown("V4DropLuckMin", {
	Text = "Luck threshold (≥)",
	Values = luckLabels,
	Default = 2, -- 10%
	Callback = function(v)
		local n = tonumber(tostring(v):match("(%d+)")) or 10
		state.dropLuckMin = n
	end,
})

DropBox:AddToggle("V4DropLuck", {
	Text = "Drop luck ≥ threshold",
	Default = false,
	Tooltip = "Continuous: drop crystals with luck % >= dropdown.",
	Callback = function(v)
		if v then
			state.dropMode = "luck"
			pcall(function()
				if Toggles.V4DropAll and Toggles.V4DropAll.Value then
					Toggles.V4DropAll:SetValue(false)
				end
				if Toggles.V4DropValue and Toggles.V4DropValue.Value then
					Toggles.V4DropValue:SetValue(false)
				end
			end)
			startAutoDropLoop()
			Library:Notify({
				Title = "Drop Luck",
				Description = string.format("ON · drop luck ≥ %d%%", state.dropLuckMin or 10),
				Time = 2,
			})
		else
			if state.dropMode == "luck" then
				stopAutoDrop()
			end
			Library:Notify({ Title = "Drop Luck", Description = "OFF", Time = 2 })
		end
	end,
})

DropBox:AddSlider("V4DropValueTarget", {
	Text = "Total value target ($B)",
	Default = 1,
	Min = 1,
	Max = 100,
	Rounding = 0,
	Tooltip = "Target in billions. 1 = $1B, 10 = $10B.",
	Callback = function(v)
		state.dropValueTarget = (tonumber(v) or 1) * 1e9
	end,
})

DropBox:AddToggle("V4DropValue", {
	Text = "Drop until total value",
	Default = false,
	Tooltip = "Continuous: drop cheapest first until sum Value >= target ($B slider).",
	Callback = function(v)
		if v then
			state.dropMode = "value"
			pcall(function()
				if Toggles.V4DropAll and Toggles.V4DropAll.Value then
					Toggles.V4DropAll:SetValue(false)
				end
				if Toggles.V4DropLuck and Toggles.V4DropLuck.Value then
					Toggles.V4DropLuck:SetValue(false)
				end
			end)
			startAutoDropLoop()
			Library:Notify({
				Title = "Drop Value",
				Description = "ON · until " .. formatMoney(state.dropValueTarget or 0) .. " (cheap first)",
				Time = 2,
			})
		else
			if state.dropMode == "value" then
				stopAutoDrop()
			end
			Library:Notify({ Title = "Drop Value", Description = "OFF", Time = 2 })
		end
	end,
})

DropBox:AddSlider("V4DropDelay", {
	Text = "Drop delay (s)",
	Default = 0.2,
	Min = 0.05,
	Max = 1,
	Rounding = 2,
	Callback = function(v)
		state.dropDelay = v
	end,
})

DropBox:AddToggle("V4DropSkipFav", {
	Text = "Skip Favorited",
	Default = true,
	Callback = function(v)
		state.dropSkipFav = v
	end,
})

DropBox:AddDivider()
DropBox:AddLabel("Drop Runes (independent of crystal modes)")

local runeDropLabels = {}
for _, r in ipairs(RUNE_DROP_LIST) do
	table.insert(runeDropLabels, r.name)
end

DropBox:AddDropdown("V4DropRuneSelect", {
	Text = "Runes to drop",
	Values = runeDropLabels,
	Multi = true,
	Default = {},
	Tooltip = "Multi-select which rune types to dump.",
	Callback = function(v)
		local selected = {}
		if type(v) == "table" then
			for label, on in pairs(v) do
				if on == true then
					for _, r in ipairs(RUNE_DROP_LIST) do
						if r.name == label or label == r.name then
							selected[r.id] = true
						end
					end
					-- also if value is array of labels
					if type(label) == "number" and type(on) == "string" then
						for _, r in ipairs(RUNE_DROP_LIST) do
							if r.name == on then
								selected[r.id] = true
							end
						end
					end
				end
			end
			-- array form { "Luck Rune", ... }
			for _, item in ipairs(v) do
				if type(item) == "string" then
					for _, r in ipairs(RUNE_DROP_LIST) do
						if r.name == item then
							selected[r.id] = true
						end
					end
				end
			end
		end
		state.dropRuneSelected = selected
	end,
})

local function runeStock(runeId)
	local inv = LP:FindFirstChild("PlayerData") and LP.PlayerData:FindFirstChild("Inventory")
	local folder = inv and inv:FindFirstChild("Runes")
	local v = folder and folder:FindFirstChild(runeId)
	return v and (tonumber(v.Value) or 0) or 0
end

local function fireDropRune(displayName)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local drop = remotes and remotes:FindFirstChild("CrystalDropRequest")
	if not drop then
		return false
	end
	return pcall(function()
		drop:FireServer(displayName)
	end)
end

local function stopAutoDropRunes()
	state.dropRunes = false
end

local function startAutoDropRunes()
	if state.dropRuneThread then
		return
	end
	state.dropRunes = true
	state.dropRuneThread = task.spawn(function()
		-- one-shot batch: drop up to Amount per selected rune type, then turn off
		local delay = math.clamp(tonumber(state.dropDelay) or 0.2, 0.05, 1)
		local amount = math.clamp(math.floor(tonumber(state.dropRuneAmount) or 1), 1, 100)
		local totalDropped = 0
		for _, r in ipairs(RUNE_DROP_LIST) do
			if not state.dropRunes or Library.Unloaded then
				break
			end
			if state.dropRuneSelected[r.id] then
				local need = amount
				while need > 0 and state.dropRunes and not Library.Unloaded do
					local stock = runeStock(r.id)
					if stock <= 0 then
						break
					end
					if fireDropRune(r.name) then
						need -= 1
						totalDropped += 1
						task.wait(delay)
					else
						task.wait(0.3)
						break
					end
				end
			end
		end
		state.dropRunes = false
		state.dropRuneThread = nil
		pcall(function()
			if Toggles.V4DropRunes and Toggles.V4DropRunes.Value then
				Toggles.V4DropRunes:SetValue(false)
			end
		end)
		Library:Notify({
			Title = "Drop Runes",
			Description = string.format("Done · dropped %d (max %d each)", totalDropped, amount),
			Time = 3,
		})
	end)
end

DropBox:AddSlider("V4DropRuneAmount", {
	Text = "Rune drop amount",
	Default = 1,
	Min = 1,
	Max = 100,
	Rounding = 0,
	Tooltip = "How many of each selected rune type to drop (1–100).",
	Callback = function(v)
		state.dropRuneAmount = math.clamp(math.floor(tonumber(v) or 1), 1, 100)
	end,
})

DropBox:AddToggle("V4DropRunes", {
	Text = "Drop selected runes",
	Default = false,
	Tooltip = "Drops up to Amount of each selected rune type, then turns OFF.",
	Callback = function(v)
		if v then
			local n = 0
			for _ in pairs(state.dropRuneSelected) do
				n += 1
			end
			if n == 0 then
				Library:Notify({
					Title = "Drop Runes",
					Description = "Select at least 1 rune type first",
					Time = 3,
				})
				task.defer(function()
					pcall(function()
						if Toggles.V4DropRunes then
							Toggles.V4DropRunes:SetValue(false)
						end
					end)
				end)
				return
			end
			startAutoDropRunes()
			Library:Notify({
				Title = "Drop Runes",
				Description = string.format("Dropping ≤%d of %d type(s)…", state.dropRuneAmount or 1, n),
				Time = 2,
			})
		else
			stopAutoDropRunes()
		end
	end,
})

--========================================================
-- TERRAIN — bomb-breakable material ESP
-- BombMaterials.BY_MATERIAL: Ice/Salt/Pavement/... → bomb type
--========================================================
local BombMaterials
pcall(function()
	BombMaterials = require(ReplicatedStorage.Modules.BombMaterials)
end)

local TERRAIN_BOMB_META = {
	ClassicBomb = { label = "Classic", color = Color3.fromRGB(180, 180, 180) },
	WindBomb = { label = "Wind", color = Color3.fromRGB(160, 220, 255) },
	IceBomb = { label = "Ice", color = Color3.fromRGB(120, 200, 255) },
	FireBomb = { label = "Fire", color = Color3.fromRGB(255, 120, 60) },
	ThunderBomb = { label = "Thunder", color = Color3.fromRGB(255, 220, 80) },
	PoisonBomb = { label = "Poison", color = Color3.fromRGB(120, 220, 100) },
	TimeBomb = { label = "Time", color = Color3.fromRGB(180, 120, 255) },
	AgonyBomb = { label = "Agony", color = Color3.fromRGB(255, 60, 80) },
}

local function clearTerrainESP()
	for _, m in ipairs(state.terrainMarkers) do
		pcall(function()
			if m.part then
				m.part:Destroy()
			elseif m.bb then
				m.bb:Destroy()
			end
		end)
	end
	table.clear(state.terrainMarkers)
end

local function stopTerrainESP()
	state.terrainEsp = false
	clearTerrainESP()
end

local function terrainBombInfo(material)
	if not BombMaterials then
		return nil
	end
	local ok, info = pcall(function()
		if BombMaterials.infoFor then
			return BombMaterials.infoFor(material)
		end
		local by = BombMaterials.BY_MATERIAL
		return by and by[material]
	end)
	if ok and type(info) == "table" and info.bombId then
		return info
	end
	return nil
end

local terrainStatusLabel
local lastTerrainScan = { count = 0, byBomb = {} }

local function terrainStatusText()
	local parts = { string.format("Markers: %d", lastTerrainScan.count or 0) }
	local by = lastTerrainScan.byBomb or {}
	local keys = {}
	for k in pairs(by) do
		table.insert(keys, k)
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local meta = TERRAIN_BOMB_META[k]
		table.insert(parts, string.format("%s: %d", meta and meta.label or k, by[k]))
	end
	if #keys == 0 then
		table.insert(parts, "No bomb terrain in radius")
		table.insert(parts, "(walk toward Ice/Salt/Lava zones)")
	end
	return table.concat(parts, "\n")
end

local function refreshTerrainStatus()
	if terrainStatusLabel and terrainStatusLabel.SetText then
		pcall(function()
			terrainStatusLabel:SetText(terrainStatusText())
		end)
	end
end

local function makeTerrainMarker(pos, normal, info, cellSize)
	local meta = TERRAIN_BOMB_META[info.bombId] or { label = info.bombId, color = Color3.new(1, 1, 1) }
	local size = math.clamp((cellSize or 8) * 1.15, 7, 16)
	local n = (normal and normal.Magnitude > 0.1) and normal.Unit or Vector3.yAxis
	local baseCF = CFrame.lookAt(pos + n * 0.4, pos + n * 0.4 + n) * CFrame.Angles(-math.pi / 2, 0, 0)

	-- folder-like: ground plate + upright box so it reads as a "zone"
	local model = Instance.new("Model")
	model.Name = "MaMV4_TerrainESP"

	local plate = Instance.new("Part")
	plate.Name = "Plate"
	plate.Anchored = true
	plate.CanCollide = false
	plate.CanQuery = false
	plate.CanTouch = false
	plate.CastShadow = false
	plate.Size = Vector3.new(size, 0.8, size)
	plate.CFrame = baseCF
	plate.Color = meta.color
	plate.Material = Enum.Material.Neon
	plate.Transparency = 0.4
	plate.Parent = model

	-- hollow-looking wire box (SelectionBox = classic "dikotakin")
	local box = Instance.new("Part")
	box.Name = "Box"
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.CastShadow = false
	box.Size = Vector3.new(size * 0.92, size * 0.75, size * 0.92)
	box.CFrame = baseCF * CFrame.new(0, box.Size.Y * 0.5, 0)
	box.Color = meta.color
	box.Material = Enum.Material.ForceField
	box.Transparency = 0.55
	box.Parent = model

	local sel = Instance.new("SelectionBox")
	sel.Name = "MaMV4_TerrainBox"
	sel.Adornee = box
	sel.Color3 = meta.color
	sel.LineThickness = 0.08
	sel.SurfaceTransparency = 0.85
	sel.SurfaceColor3 = meta.color
	sel.Parent = box

	local hl = Instance.new("Highlight")
	hl.Name = "MaMV4_TerrainHL"
	hl.Adornee = model
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.FillColor = meta.color
	hl.OutlineColor = Color3.new(1, 1, 1)
	hl.FillTransparency = 0.55
	hl.OutlineTransparency = 0
	hl.Parent = model

	-- tall pillar so you spot it from far
	local pillar = Instance.new("Part")
	pillar.Name = "Pillar"
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.CastShadow = false
	pillar.Size = Vector3.new(1.2, 18, 1.2)
	pillar.CFrame = CFrame.new(pos + n * 9)
	pillar.Color = meta.color
	pillar.Material = Enum.Material.Neon
	pillar.Transparency = 0.35
	pillar.Parent = model

	local bb = Instance.new("BillboardGui")
	bb.Name = "MaMV4_TerrainBB"
	bb.Adornee = pillar
	bb.Size = UDim2.fromOffset(160, 44)
	bb.StudsOffset = Vector3.new(0, 12, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 500
	bb.Parent = pillar

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 0.1
	lbl.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 14
	lbl.TextColor3 = meta.color
	lbl.TextStrokeTransparency = 0.25
	lbl.Text = string.format("%s\n→ %s", info.matName or meta.label, info.bombName or meta.label)
	lbl.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 5)
	c.Parent = lbl

	model.Parent = workspace
	return { part = model, bb = bb, key = info.bombId }
end

local function applyTerrainESP()
	clearTerrainESP()
	if not state.terrainEsp then
		return
	end
	local hrp = getHRP()
	if not hrp then
		return
	end
	local radius = math.clamp(tonumber(state.terrainRadius) or 160, 40, 250)
	local step = math.clamp(tonumber(state.terrainStep) or 8, 5, 20)
	local origin = hrp.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }

	local seen = {}
	local count = 0
	local byBomb = {}
	local maxMarkers = 120
	local yOffsets = { 120, 60, 20, 0, -30, -70 }
	local dirs = {
		Vector3.new(0, -280, 0),
		Vector3.new(0, 200, 0),
		Vector3.new(step * 2, -40, 0),
		Vector3.new(-step * 2, -40, 0),
		Vector3.new(0, -40, step * 2),
		Vector3.new(0, -40, -step * 2),
	}

	local function tryHit(hit)
		if not hit or not hit.Material or count >= maxMarkers then
			return
		end
		local info = terrainBombInfo(hit.Material)
		if not info or not state.terrainFilter[info.bombId] then
			return
		end
		local cellX = math.floor(hit.Position.X / step)
		local cellY = math.floor(hit.Position.Y / step)
		local cellZ = math.floor(hit.Position.Z / step)
		local key = cellX .. "_" .. cellY .. "_" .. cellZ .. "_" .. tostring(info.bombId)
		if seen[key] then
			return
		end
		seen[key] = true
		table.insert(state.terrainMarkers, makeTerrainMarker(hit.Position, hit.Normal, info, step))
		count += 1
		byBomb[info.bombId] = (byBomb[info.bombId] or 0) + 1
	end

	for x = -radius, radius, step do
		for z = -radius, radius, step do
			if count >= maxMarkers then
				break
			end
			if x * x + z * z <= radius * radius then
				for _, yOff in ipairs(yOffsets) do
					local from = origin + Vector3.new(x, yOff, z)
					for _, dir in ipairs(dirs) do
						tryHit(workspace:Raycast(from, dir, params))
						if count >= maxMarkers then
							break
						end
					end
					if count >= maxMarkers then
						break
					end
				end
			end
		end
		if count >= maxMarkers then
			break
		end
	end

	lastTerrainScan = { count = count, byBomb = byBomb }
	refreshTerrainStatus()
end

local function startTerrainESP()
	if state.terrainEspThread then
		return
	end
	state.terrainEsp = true
	state.terrainEspThread = task.spawn(function()
		while state.terrainEsp and not Library.Unloaded do
			pcall(applyTerrainESP)
			task.wait(2.2)
		end
		clearTerrainESP()
		state.terrainEspThread = nil
	end)
end

local TerrainBox = Tabs.Terrain:AddLeftGroupbox("Bomb Terrain", "layers")
TerrainBox:AddLabel("ESP: Ice/Salt/Fire-plate/… → correct bomb")
TerrainBox:AddLabel("Only shows bomb materials (not normal rock)")
terrainStatusLabel = TerrainBox:AddLabel(terrainStatusText(), true)

TerrainBox:AddToggle("V4TerrainESP", {
	Text = "Terrain ESP",
	Default = false,
	Tooltip = "Multi-ray scan for bomb-only terrain. Markers = neon ball + label.",
	Callback = function(v)
		if v then
			startTerrainESP()
			Library:Notify({ Title = "Terrain ESP", Description = "ON — scanning…", Time = 2 })
		else
			stopTerrainESP()
			lastTerrainScan = { count = 0, byBomb = {} }
			refreshTerrainStatus()
			Library:Notify({ Title = "Terrain ESP", Description = "OFF", Time = 2 })
		end
	end,
})

TerrainBox:AddSlider("V4TerrainRadius", {
	Text = "Scan radius",
	Default = 160,
	Min = 60,
	Max = 250,
	Rounding = 0,
	Callback = function(v)
		state.terrainRadius = v
	end,
})

TerrainBox:AddSlider("V4TerrainStep", {
	Text = "Grid step (studs)",
	Default = 8,
	Min = 5,
	Max = 16,
	Rounding = 0,
	Tooltip = "Lower = denser (heavier).",
	Callback = function(v)
		state.terrainStep = v
	end,
})

local bombFilterLabels = {
	"Classic Bomb",
	"Wind Bomb",
	"Ice Bomb",
	"Fire Bomb",
	"Thunder Bomb",
	"Poison Bomb",
	"Time Bomb",
	"Agony Bomb",
}
local bombFilterIds = {
	["Classic Bomb"] = "ClassicBomb",
	["Wind Bomb"] = "WindBomb",
	["Ice Bomb"] = "IceBomb",
	["Fire Bomb"] = "FireBomb",
	["Thunder Bomb"] = "ThunderBomb",
	["Poison Bomb"] = "PoisonBomb",
	["Time Bomb"] = "TimeBomb",
	["Agony Bomb"] = "AgonyBomb",
}

TerrainBox:AddDropdown("V4TerrainFilter", {
	Text = "Show bomb types",
	Values = bombFilterLabels,
	Multi = true,
	Default = bombFilterLabels,
	Callback = function(v)
		local selected = {}
		if type(v) == "table" then
			for a, b in pairs(v) do
				if b == true and type(a) == "string" then
					local id = bombFilterIds[a]
					if id then
						selected[id] = true
					end
				elseif type(b) == "string" then
					local id = bombFilterIds[b]
					if id then
						selected[id] = true
					end
				end
			end
			for _, item in ipairs(v) do
				if type(item) == "string" then
					local id = bombFilterIds[item]
					if id then
						selected[id] = true
					end
				end
			end
		end
		if next(selected) == nil then
			-- keep all if empty parse
			for _, id in pairs(bombFilterIds) do
				selected[id] = true
			end
		end
		state.terrainFilter = selected
		if state.terrainEsp then
			applyTerrainESP()
		end
	end,
})

TerrainBox:AddButton({
	Text = "Refresh ESP Now",
	Func = function()
		if state.terrainEsp then
			applyTerrainESP()
			Library:Notify({
				Title = "Terrain ESP",
				Description = #state.terrainMarkers .. " markers",
				Time = 2,
			})
		else
			Library:Notify({ Title = "Terrain ESP", Description = "Enable toggle first", Time = 2 })
		end
	end,
})

task.defer(function()
	task.wait(0.35)
	refreshShovels()
	refreshPacks()
	refreshBoulders()
	refreshRunes()
end)

getgenv().MaMV4ExtrasCleanup = function()
	stopAutoBreak()
	stopAutoDrop()
	stopAutoDropRunes()
	stopTerrainESP()
	state.autoPickupRune = false
	state.boulderEsp = false
	state.runeEsp = false
	clearBoulderESP()
	clearRuneESP()
end

Library:Notify({
	Title = "Qentury v4 extras",
	Description = "Shovels · Packs · Boulders · Runes · Terrain · Auto Drop",
	Time = 3,
})

]=]
task.spawn(function()
	local ok, err = pcall(function()
		local fn, lerr = loadstring(V4_EXTRAS_SRC)
		if not fn then
			error(lerr)
		end
		fn()
	end)
	if not ok then
		warn("[v4 extras]", err)
	end
end)

Library:Notify({
	Title = "Mine a Mountain",
	Description = "Qentury Hub v4-tes · loading extras…",
	Time = 4,
})
