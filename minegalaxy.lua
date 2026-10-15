--!nonstrict
-- GalaxyVacuum_Airflow v22
-- Game: Mine a Galaxy | Loot vacuum via ProximityPrompt hold (HoldLoot + swing loop game yang urus)
-- Fitur: Main + Monitor + AutoSell + Misc(InfFuel/Noclip/Server) + Shop
-- UI: Airflow joustingmatch/-3 (Window > Tab > Groupbox > Toggle) | Live-reload safe
-- UI: Airflow joustingmatch/-3 (Window > Tab > Groupbox > Toggle) | Live-reload safe
-- UI: Airflow joustingmatch/-3 (Window > Tab > Groupbox > Toggle) | Live-reload safe

-- =====================================================================
-- 0. DEDUP LINTAS-COPY (ghost copy dari live-reload timeout)
-- =====================================================================
local EPOCH_KEY = "__GALAXY_VACUUM_EPOCH"
local UI_NAME = "GalaxyVacuum" -- ScreenGui lama + folder config (jangan ubah: kompat config)
local WINDOW_TITLE = "Mine Galaxy" -- judul window
local myEpoch = (tonumber((getgenv() or {})[EPOCH_KEY]) or 0) + 1
getgenv()[EPOCH_KEY] = myEpoch
local function isMine(): boolean
	return getgenv()[EPOCH_KEY] == myEpoch
end
pcall(function()
	local hui = gethui and gethui() or game:GetService("CoreGui")
	for _, old in ipairs(hui:GetDescendants()) do
		if old:IsA("ScreenGui") and (old.Name == UI_NAME or old.Name == WINDOW_TITLE or old.Name == "Airflow" or old.Name == "__Probe" or old.Name == "__Probe2" or old.Name == "__Probe3" or old.Name == "__Probe4" or old.Name == "__Probe5" or old.Name == "__Probe6" or old.Name == "__Probe7") then
			old:Destroy()
		end
	end
end)

-- =====================================================================
-- 1. SERVICES / IMPORTS
-- =====================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Items = ReplicatedStorage:WaitForChild("Items")
local ItemData = require(Items:WaitForChild("ItemData"))
local LootFolder: Folder = workspace:WaitForChild("Loot") :: Folder

-- =====================================================================
-- 2. CONSTANTS
-- =====================================================================
local VACUUM_RADIUS = 17 -- terbukti server terima 16.2m; tiap prompt MaxDist beda (15.9-16.6+), di bawah dibatasi per-prompt
local WALK_TO_DIST = 6 -- vacuum jalan: dekati sampai segini baru hold
local TELE_RADIUS_DEF = 150
local TICK_VACUUM = 0.4
local TICK_TELE = 0.6
local TICK_VACUUM_FAST = 0.15
local TICK_TELE_FAST = 0.25
local HOLD_TIMEOUT = 10 -- stop hold kalau loot alot (detik)
local HOLD_TIMEOUT_FAST = 7
local HOVER_UP = 4 -- hover di atas loot saat TP
local TP_STEP = 55 -- teleport bertahap anti rubber-band
local RETRY_COOLDOWN = 3 -- jangan sentuh loot gagal sebelum X detik
local RETRY_COOLDOWN_FAST = 1
local STARTER_PICKAXE = ItemData.STARTERS.Pickaxe
local TIER_NAMES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Empyrean", "Pulsar", "Quasar" }
-- warna label per rarity (fixed hex, tak ikut tema agar beda tiap tier jelas)
local TIER_HEX = { "#CD945C", "#5FDC69", "#469BFF", "#B45FFF", "#FFAA2D", "#FF4646", "#B44DFF", "#4CE0E0", "#FFD84A" }

-- =====================================================================
-- 3. STATE
-- =====================================================================
local Cfg = {
	vacuum = false,
	teleVacuum = false,
	monTiers = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true },
	monSort = "Value", -- "Value" | "Luck"
	autoSell = false,
	sellPct = 90, -- jual saat cargo% >= ini
	infFuel = false,
	noclip = false,
	teleRadius = TELE_RADIUS_DEF,
	aggro = true, -- permanen agresif (tanpa toggle): tick cepat + incar value tertinggi
	vacTiers = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true },
	shopBombs = { ["meteor_charge"] = true },
	shopRadars = { ["pocket_pinger"] = true },
	autoBomb = false,
	autoRadar = false,
}
local Run = {
	busy = false, -- ada hold/TP berjalan (hindari double-hold, game disable prompt lain saat hold)
	tryAt = {} :: { [string]: number },
	status = "idle",
	selling = false,
	sellNow = false,
}

-- =====================================================================
-- 4. HELPERS
-- =====================================================================
local function setStatus(s: string)
	Run.status = s
end

-- nilai efektif tergantung mode agresif
local function effTickVacuum(): number
	return Cfg.aggro and TICK_VACUUM_FAST or TICK_VACUUM
end
local function effTickTele(): number
	return Cfg.aggro and TICK_TELE_FAST or TICK_TELE
end
local function effHoldTimeout(): number
	return Cfg.aggro and HOLD_TIMEOUT_FAST or HOLD_TIMEOUT
end
local function effRetry(): number
	return Cfg.aggro and RETRY_COOLDOWN_FAST or RETRY_COOLDOWN
end

local function getHRP(): BasePart?
	local char = LocalPlayer.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getUp(): Vector3
	local char = LocalPlayer.Character
	if char and char:GetAttribute("OnPlanet") then
		local g = char:GetAttribute("GravityUp")
		if typeof(g) == "Vector3" then
			return g :: Vector3
		end
	end
	return Vector3.yAxis
end

local function getPrompt(loot: Instance): ProximityPrompt?
	local direct = loot:FindFirstChildOfClass("ProximityPrompt")
	if direct and direct:IsA("ProximityPrompt") then
		return direct
	end
	for _, d in ipairs(loot:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			return d
		end
	end
	return nil
end

local function lootUid(loot: Instance): string
	return tostring(loot:GetAttribute("Uid") or loot.Name)
end

local function myPickaxe()
	local id = LocalPlayer:GetAttribute("Equipped_Pickaxe") or STARTER_PICKAXE
	local it = ItemData.get(id) or ItemData.get(STARTER_PICKAXE)
	return it
end

local function cargoFits(weight: number): boolean
	local kg = LocalPlayer:GetAttribute("CargoKg") or 0
	local max = LocalPlayer:GetAttribute("CargoMax") or 50
	if kg <= 1e-6 then
		return true
	end
	return kg + weight <= max + 1e-6
end

-- Validasi target vakum: mirror isLootPrompt/isDroppedPrompt + fitPrompt/fitDropped game.
-- Dropped = pickup instan 0.25s tanpa nambang (batu jatuh/meteor). allowDropped=true untuk vakum.
local function isValidTarget(loot: Instance, hrpPos: Vector3, maxDist: number, allowDropped: boolean?)
	if loot.Parent ~= LootFolder then
		return false, nil
	end
	if not loot:IsA("BasePart") then
		return false, nil
	end
	local dropped = loot:GetAttribute("Dropped") == true
	if dropped and not allowDropped then
		return false, nil
	end
	if loot:GetAttribute("Taken") then
		return false, nil
	end
	local prompt = getPrompt(loot)
	if not prompt or not prompt.Enabled then
		return false, nil
	end
	if prompt:GetAttribute("TooHard") then
		return false, nil
	end
	if prompt.ActionText == "TOO HEAVY" or prompt.ActionText == "NEEDS BETTER PICKAXE" or prompt.ActionText == "TOO HEAVY TO PICK UP" then
		return false, nil
	end
	local tier = math.clamp(tonumber(loot:GetAttribute("Tier")) or 1, 1, #TIER_NAMES)
	if not Cfg.vacTiers[tier] then
		return false, nil -- filter tier vakum
	end
	if not dropped and not ItemData.canBreak(myPickaxe(), tier) then
		return false, nil -- dropped tak perlu pickaxe
	end
	if not cargoFits(loot:GetAttribute("Weight") or 0) then
		return false, nil
	end
	if (loot.Position - hrpPos).Magnitude > maxDist then
		return false, nil
	end
	if os.clock() - (Run.tryAt[lootUid(loot)] or 0) < effRetry() then
		return false, nil
	end
	return true, prompt
end

local function findBest(maxDist: number, perPrompt: boolean?)
	local hrp = getHRP()
	if not hrp then
		return nil, nil, nil
	end
	local hrpPos = hrp.Position
	local best: BasePart? = nil
	local bestPrompt: ProximityPrompt? = nil
	local bestDist = math.huge
	for _, loot in ipairs(LootFolder:GetChildren()) do
		local ok, prompt = isValidTarget(loot, hrpPos, maxDist, true)
		if ok and prompt then
			local d = ((loot :: BasePart).Position - hrpPos).Magnitude
			-- server ikut MaxDist tiap prompt: batasi per-loot (margin 0.3m)
			if perPrompt then
				local lim = (tonumber(prompt.MaxActivationDistance) or (maxDist + 0.3)) - 0.3
				if d > math.min(lim, maxDist) then
					continue
				end
			end
			if d < bestDist then
				bestDist = d
				best = loot :: BasePart
				bestPrompt = prompt
			end
		end
	end
	if not best then
		return nil, nil, nil
	end
	return best, bestPrompt, bestDist
end

-- varian agresif: target value tertinggi dalam radius (bukan terdekat)
local function findRichest(maxDist: number)
	local hrp = getHRP()
	if not hrp then
		return nil, nil, nil
	end
	local hrpPos = hrp.Position
	local best: BasePart? = nil
	local bestPrompt: ProximityPrompt? = nil
	local bestValue = -1
	local bestDist = 0
	for _, loot in ipairs(LootFolder:GetChildren()) do
		local ok, prompt = isValidTarget(loot, hrpPos, maxDist, true)
		if ok and prompt then
			local v = tonumber((loot :: BasePart):GetAttribute("Value")) or 0
			if v > bestValue then
				bestValue = v
				best = loot :: BasePart
				bestPrompt = prompt
				bestDist = ((loot :: BasePart).Position - hrpPos).Magnitude
			end
		end
	end
	if not best then
		return nil, nil, nil
	end
	return best, bestPrompt, bestDist
end

-- =====================================================================
-- 5. CORE: HOLD (InputHoldBegin/End agar HoldLoot + swing game jalan)
-- =====================================================================
local function holdTarget(loot: BasePart, prompt: ProximityPrompt): boolean
	Run.tryAt[lootUid(loot)] = os.clock()
	local holdTime = tonumber(prompt.HoldDuration) or tonumber(ItemData.GEM_HOLD) or 0.3
	if holdTime > 30 then
		return false -- TOO HEAVY / NEEDS BETTER lolos filter, jangan hold 600s
	end
	local done = false
	local cap = effHoldTimeout()
	task.spawn(function()
		task.wait(cap)
		if not done and loot.Parent then
			pcall(function()
				prompt:InputHoldEnd()
			end)
		end
	end)
	local okBegin = pcall(function()
		prompt:InputHoldBegin()
	end)
	if not okBegin then
		return false
	end
	task.wait(holdTime + 0.25)
	-- beri waktu swing loop game menambang (MiningHits 2-4x ayun)
	local t0 = os.clock()
	while loot.Parent and not loot:GetAttribute("Taken") and os.clock() - t0 < cap do
		task.wait(0.2)
		-- kalau MiningBy direbut orang lain, lepas
		local by = loot:GetAttribute("MiningBy")
		if by ~= nil and by ~= LocalPlayer.UserId then
			break
		end
		-- loot dekat biasanya habis < 4 detik; keluar cepat kalau prompt mati
		if not prompt.Enabled then
			break
		end
	end
	pcall(function()
		prompt:InputHoldEnd()
	end)
	done = true
	task.wait(0.15)
	return loot.Parent == nil or loot:GetAttribute("Taken") == true
end

-- =====================================================================
-- 6. MOVER: TELEPORT BERTAHAP
-- =====================================================================
local function teleportNear(targetPos: Vector3)
	local hrp = getHRP()
	local char = LocalPlayer.Character
	if not hrp or not char then
		return false
	end
	local up = getUp()
	local goal = targetPos + up * HOVER_UP
	local dist = (hrp.Position - goal).Magnitude
	if dist <= 12 then
		pcall(function()
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
			char:PivotTo(CFrame.lookAt(goal, targetPos, up))
		end)
		return true
	end
	local start = hrp.Position
	local steps = math.clamp(math.ceil(dist / TP_STEP), 2, 8)
	for i = 1, steps do
		if not isMine() then
			return false
		end
		hrp = getHRP()
		char = LocalPlayer.Character
		if not hrp or not char then
			return false
		end
		pcall(function()
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum:ChangeState(Enum.HumanoidStateType.Freefall)
			end
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
			char:PivotTo(CFrame.new(start:Lerp(goal, i / steps)))
		end)
		task.wait(0.05)
	end
	return true
end

local function tpToMeteor(): boolean
	local folder = workspace:FindFirstChild("Meteors")
	local best: Instance? = nil
	if folder then
		for _, c in ipairs(folder:GetChildren()) do
			best = c
			break
		end
	end
	if not best then
		setStatus("meteor: tidak aktif")
		return false
	end
	local ok, piv = pcall(function()
		return (best :: Model):GetPivot()
	end)
	if not ok or not piv then
		setStatus("meteor: posisi tak terbaca")
		return false
	end
	setStatus("meteor: TP...")
	teleportNear((piv :: CFrame).Position)
	setStatus("meteor: sampai")
	return true
end

-- =====================================================================
-- 6c. PLANETS (baca live ReplicatedStorage.Planets, TP ke permukaan)
-- =====================================================================
local function planetList(): { { key: string, name: string, slot: string, hard: number, center: Vector3, radius: number, bonus: number } }
	local out: { { key: string, name: string, slot: string, hard: number, center: Vector3, radius: number, bonus: number } } = {}
	pcall(function()
		for _, v in ipairs(ReplicatedStorage:WaitForChild("Planets"):GetChildren()) do
			local c = v:GetAttribute("Center")
			if typeof(c) == "Vector3" then
				table.insert(out, {
					key = v.Name,
					name = tostring(v:GetAttribute("PlanetName") or v.Name),
					slot = tostring(v:GetAttribute("Slot") or "?"),
					hard = tonumber(v:GetAttribute("Hardness")) or 0,
					center = c :: Vector3,
					radius = tonumber(v:GetAttribute("Radius")) or 300,
					bonus = tonumber(v:GetAttribute("ValueBonus")) or 0,
				})
			end
		end
	end)
	table.sort(out, function(a, b)
		return a.hard < b.hard
	end)
	return out
end

local function teleportToPlanet(displayName: string): (boolean, string)
	local list = planetList()
	local pick = nil
	for _, p in ipairs(list) do
		if p.name == displayName or p.key == displayName then
			pick = p
			break
		end
	end
	if not pick then
		return false, "planet tak ada"
	end
	local hrp = getHRP()
	local from = hrp and hrp.Position or (pick.center + Vector3.new(0, pick.radius + 50, 0))
	local dir = from - pick.center
	if dir.Magnitude < 1 then
		dir = Vector3.yAxis
	end
	-- permukaan sisi pemain + hover, biar tak nyangkut di inti
	local goal = pick.center + dir.Unit * (pick.radius + 12)
	teleportNear(goal)
	return true, "-> " .. pick.name
end

-- =====================================================================
-- 6b. SERVER (adaptasi tab Server Antarctica: TP player + rejoin/hop/reset/refresh)
-- =====================================================================
local function playerNames(): { string }
	local names: { string } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			table.insert(names, p.Name)
		end
	end
	table.sort(names)
	if #names == 0 then
		return { "-" }
	end
	return names
end

local function teleportToPlayer(name: string): (boolean, string)
	if not name or name == "-" then
		return false, "pilih player dulu"
	end
	local target = Players:FindFirstChild(name)
	local char = target and (target :: Player).Character
	local t = char and char:FindFirstChild("HumanoidRootPart")
	if not t then
		return false, "player tak ada"
	end
	teleportNear((t :: BasePart).Position)
	return true, "-> " .. name
end

local function serverRejoin(): (boolean, string)
	local ok, err = pcall(function()
		if #Players:GetPlayers() <= 1 then
			LocalPlayer:Kick("\nRejoining...")
			task.wait()
			TeleportService:Teleport(game.PlaceId, LocalPlayer)
		else
			TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
		end
	end)
	if ok then
		return true, "rejoin..."
	end
	return false, tostring(err)
end

local function serverHop(): (boolean, string)
	local ok, err = pcall(function()
		local body = game:HttpGet(string.format(
			"https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", game.PlaceId))
		local data = HttpService:JSONDecode(body)
		if not data or not data.data then
			error("no servers")
		end
		local list: { string } = {}
		for _, s in ipairs(data.data) do
			if s.playing and s.maxPlayers and s.id and s.playing < s.maxPlayers and s.id ~= game.JobId then
				table.insert(list, s.id)
			end
		end
		if #list == 0 then
			error("no free servers")
		end
		TeleportService:TeleportToPlaceInstance(game.PlaceId, list[math.random(1, #list)], LocalPlayer)
	end)
	if ok then
		return true, "hopping..."
	end
	return false, tostring(err)
end

local function resetCharacter(): (boolean, string)
	local ok, err = pcall(function()
		local char = LocalPlayer.Character
		local hum = char and char:FindFirstChildWhichIsA("Humanoid")
		if hum then
			(hum :: Humanoid):ChangeState(Enum.HumanoidStateType.Dead)
		elseif char then
			char:BreakJoints()
		else
			error("no character")
		end
	end)
	if ok then
		return true, "reset..."
	end
	return false, tostring(err)
end

-- refresh ala IY: respawn, posisi + kamera balik
local function refreshKeepPos(): (boolean, string)
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false, "no hrp"
	end
	local pos = (root :: BasePart).CFrame
	local camPos = workspace.CurrentCamera.CFrame
	local ok, err = resetCharacter()
	if not ok then
		return false, err
	end
	task.spawn(function()
		local nc = LocalPlayer.CharacterAdded:Wait()
		local hum = nc:WaitForChild("Humanoid", 10)
		if hum then
			local nhrp = nc:WaitForChild("HumanoidRootPart", 10)
			if nhrp then
				task.wait(0.2)
				pcall(function()
					(nhrp :: BasePart).CFrame = pos
					workspace.CurrentCamera.CFrame = camPos
				end)
			end
		end
	end)
	return true, "respawn..."
end

-- =====================================================================
-- 7. LOOPS (satu target sekali jalan, anti double-hold)
-- =====================================================================
-- jalan kaki ke loot (Humanoid.MoveTo, anti-stuck). Return true kalau sampai dekat.
local function walkTo(loot: BasePart): boolean
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = getHRP()
	if not hum or not hrp then
		return false
	end
	(hum :: Humanoid):MoveTo(loot.Position)
	local t0 = os.clock()
	local lastD = (loot.Position - hrp.Position).Magnitude
	local lastT = os.clock()
	while loot.Parent and isMine() do
		task.wait(0.2)
		hrp = getHRP()
		char = LocalPlayer.Character
		hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or not hrp then
			return false
		end
		local d = (loot.Position - hrp.Position).Magnitude
		if d <= WALK_TO_DIST then
			pcall(function()
				(hum :: Humanoid):MoveTo(hrp.Position) -- berhenti
			end)
			return true
		end
		if os.clock() - t0 > 6 then
			break -- timeout: hold dari sini saja
		end
		if d < lastD - 1 then
			lastD = d
			lastT = os.clock()
		elseif os.clock() - lastT > 1.5 then
			break -- stuck (tebing/lubang): hold dari sini saja
		end
		-- jaga MoveTo tetap aktif
		if (hum :: Humanoid).MoveDirection.Magnitude < 0.05 then
			pcall(function()
				(hum :: Humanoid):MoveTo(loot.Position)
			end)
		end
	end
	return (loot.Parent ~= nil)
end

local function vacuumTick()
	if Run.busy then
		return
	end
	local loot, prompt, dist = findBest(VACUUM_RADIUS, true)
	if not loot or not prompt then
		setStatus("vacuum: no target <= ~17m")
		return
	end
	Run.busy = true
	if dist > WALK_TO_DIST then
		setStatus("vacuum: jalan -> " .. loot.Name)
		walkTo(loot)
		if loot.Parent == nil then
			Run.busy = false
			return
		end
		-- re-validasi prompt habis jalan (bisa direbut / taken)
		prompt = getPrompt(loot)
		if not prompt or not prompt.Enabled then
			Run.busy = false
			return
		end
	end
	setStatus("vacuum: " .. loot.Name)
	holdTarget(loot, prompt)
	Run.busy = false
end

local function teleVacuumTick()
	if Run.busy then
		return
	end
	local radius = Cfg.teleRadius or TELE_RADIUS_DEF
	local loot, prompt, dist
	if Cfg.aggro then
		loot, prompt, dist = findRichest(radius)
	else
		loot, prompt, dist = findBest(radius)
	end
	if not loot or not prompt then
		setStatus("tele: no target <= " .. radius .. "m")
		return
	end
	Run.busy = true
	setStatus("tele: " .. loot.Name .. " " .. math.floor(dist) .. "m")
	if dist > VACUUM_RADIUS then
		teleportNear(loot.Position)
		task.wait(0.35)
		if loot.Parent == nil then
			Run.busy = false
			return
		end
		-- re-ambil prompt (game bisa rebuild prompt pas kita TP)
		prompt = getPrompt(loot) or prompt
	end
	holdTarget(loot, prompt)
	Run.busy = false
end

-- =====================================================================
-- 7b. MONITOR TOP10 (adopsi Antarctica: filter tier, sort value/luck, klik TP)
-- =====================================================================
local MonRows: { BasePart? } = {} -- paralel urutan baris Table (Search/sort bawaan mati, index aman)
local monAt = 0
local monRefreshSoon = true
local monTable: any = nil

local function fmtMoney(n: number): string
	n = tonumber(n) or 0
	if n >= 1e9 then
		return string.format("$%.1fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("$%.1fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("$%.1fK", n / 1e3)
	end
	return "$" .. tostring(math.floor(n))
end

local function fmtKg(w: number): string
	w = tonumber(w) or 0
	if w >= 1000 then
		return string.format("%.2ft", w / 1000)
	end
	return string.format("%.1fkg", w)
end

local function tierTag(tier: number): string
	local hex = TIER_HEX[math.clamp(tier, 1, #TIER_HEX)] or "#FFFFFF"
	local name = TIER_NAMES[math.clamp(tier, 1, #TIER_NAMES)] or ("T" .. tier)
	return string.format('<font color="%s"><b>T%d %s</b></font>', hex, tier, name)
end

local function refreshMonitor()
	local hrp = getHRP()
	local myPos = hrp and hrp.Position or Vector3.zero
	local rows: { { m: BasePart, d: number, value: number, luck: number, kg: number, tier: number } } = {}
	for _, loot in ipairs(LootFolder:GetChildren()) do
		if loot:IsA("BasePart") and loot.Parent == LootFolder and not loot:GetAttribute("Taken") then
			local tier = math.clamp(tonumber(loot:GetAttribute("Tier")) or 1, 1, #TIER_NAMES)
			if Cfg.monTiers[tier] then
				table.insert(rows, {
					m = loot :: BasePart,
					d = ((loot :: BasePart).Position - myPos).Magnitude,
					value = tonumber(loot:GetAttribute("Value")) or 0,
					luck = tonumber(loot:GetAttribute("Luck")) or 0,
					kg = tonumber(loot:GetAttribute("Weight")) or 0,
					tier = tier,
				})
			end
		end
	end
	if Cfg.monSort == "Luck" then
		table.sort(rows, function(a, b)
			return a.luck > b.luck
		end)
	else
		table.sort(rows, function(a, b)
			return a.value > b.value
		end)
	end
	table.clear(MonRows)
	local tblRows: { { string } } = {}
	for i = 1, math.min(10, #rows) do
		local r = rows[i]
		if r.m.Parent then
			table.insert(MonRows, r.m)
			table.insert(tblRows, {
				tierTag(r.tier),
				r.m.Name,
				fmtMoney(r.value),
				string.format("%.1f", r.luck),
				fmtKg(r.kg),
				string.format("%.0fm", r.d),
			})
		end
	end
	if monTable then
		pcall(function()
			monTable:SetRows(tblRows)
		end)
	end
end

local function clickRow(_row: any, i: number)
	local t = MonRows[i]
	if t and t.Parent then
		teleportNear(t.Position)
	else
		setStatus("monitor: target hilang")
	end
end

-- =====================================================================
-- 7c. AUTO SELL (TP SellStand -> SellGems "all" -> balik)
-- =====================================================================
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SellGems = Remotes:WaitForChild("SellGems")

-- =====================================================================
-- 7e. SHOP (GearBuy:InvokeServer(id), stok rotasi 600s, cek Stock.left + coins)
-- =====================================================================
local GearBuy = Remotes:WaitForChild("GearBuy")
local Stock = require(Items:WaitForChild("Stock"))
local BOMB_IDS = { "meteor_charge", "solar_wind", "comet_frost", "nova_flare", "ion_storm", "nebula_toxin", "chrono_rift", "supernova" }
local RADAR_IDS = { "pocket_pinger", "dowsing_dish", "sonar_scope", "quantum_sensor", "star_chart_array", "omniscope" }
local boughtMark: { [string]: boolean } = {} -- period..id -> sudah beli (anti boros)

local function buyGear(id: string, auto: boolean): (boolean, string)
	local it = ItemData.get(id)
	local price = it and it.price or nil
	if price == nil then
		return false, "unknown item"
	end
	local left: any = nil
	pcall(function()
		left = Stock.left(LocalPlayer, id)
	end)
	if left ~= nil and left <= 0 then
		return false, "out of stock"
	end
	if auto then
		local mark = tostring(Stock.period()) .. ":" .. id
		if boughtMark[mark] then
			return false, "already bought"
		end
	end
	if (tonumber(LocalPlayer:GetAttribute("Coins")) or 0) < price then
		return false, "need $" .. tostring(price)
	end
	local ok, res = pcall(function()
		return GearBuy:InvokeServer(id)
	end)
	if not ok then
		return false, "try again"
	end
	if res == nil or res == true then
		if auto then
			boughtMark[tostring(Stock.period()) .. ":" .. id] = true
		end
		return true, "bought " .. id
	end
	return false, typeof(res) == "string" and res or "rejected"
end

local function cargoPct(): number
	local kg = tonumber(LocalPlayer:GetAttribute("CargoKg")) or 0
	local max = tonumber(LocalPlayer:GetAttribute("CargoMax")) or 50
	if max <= 0 then
		return 0
	end
	return kg / max * 100
end

local function doSell()
	if Run.selling then
		return
	end
	if (tonumber(LocalPlayer:GetAttribute("CargoKg")) or 0) <= 0 then
		Run.sellNow = false
		return
	end
	Run.selling = true
	setStatus("selling...")
	local hrp = getHRP()
	local char = LocalPlayer.Character
	local back = hrp and hrp.CFrame or nil
	-- ke stand (server kemungkinan cek jarak; prompt 12m)
	local okStand, counter = pcall(function()
		return workspace:WaitForChild("Hub"):WaitForChild("Stands"):WaitForChild("SellStand"):WaitForChild("CounterTop")
	end)
	if okStand and counter then
		teleportNear((counter :: BasePart).Position)
		task.wait(0.6)
	end
	pcall(function()
		SellGems:FireServer("all")
	end)
	task.wait(1.2)
	Run.sellNow = false
	Run.selling = false
	if back and getHRP() then
		hrp = getHRP()
		char = LocalPlayer.Character
		if hrp and char then
			pcall(function()
				hrp.AssemblyLinearVelocity = Vector3.zero
				hrp.AssemblyAngularVelocity = Vector3.zero
				char:PivotTo(back)
			end)
		end
	end
	setStatus("sold")
end

-- =====================================================================
-- 8. UI: AIRFLOW joustingmatch/-3 (Window > Tab > Groupbox > Toggle)
-- =====================================================================
-- UI: AIRFLOW joustingmatch/-3 (jangan ganti URL tanpa cek probe Tab.* dulu)
local AIRFLOW_URL = "https://raw.githubusercontent.com/joustingmatch/-3/refs/heads/main/Source.luau"
local Airflow = loadstring(game:HttpGet(AIRFLOW_URL))()
pcall(function()
	Airflow:LoadFont({ Name = "ValleySans" })
end)
pcall(function()
	Airflow:SetDefaultTheme("Sakura")
end)

local Window = Airflow:CreateWindow({
	Name = WINDOW_TITLE,
	ToggleUIKeybind = "RightControl",
	ConfigurationSaving = { Enabled = true, FolderName = UI_NAME }, -- folder tetap: config lama kebaca
	Backdrop = { Weather = "Sakura", Mode = "UI", Dim = false }, -- preset default: sakura di dalam window, tint mati
})
local MainTab = Window:CreateTab({ Name = "Vacuum", Icon = "magnet" })
local VacBox = MainTab:CreateGroupbox({ Name = "Main", Side = "Left" })
local statusLabel: any = nil

local vacWalkT: any = nil
vacWalkT = VacBox:CreateToggle({
	Name = "Vacuum jalan",
	Desc = "Ambil loot <= 14m tanpa teleport",
	CurrentValue = false,
	Flag = "GalaxyVacuum_Walk",
	Callback = function(v: boolean)
		Cfg.vacuum = v
		task.spawn(function()
			while Cfg.vacuum and isMine() and (typeof(STATE) ~= "table" or STATE.alive()) do
				if not Cfg.teleVacuum then -- teleport mode prioritas, vacuum pause biar tak double-hold
					pcall(vacuumTick)
				end
				task.wait(effTickVacuum())
			end
			if not Cfg.vacuum then
				setStatus("idle")
			end
		end)
	end,
})

VacBox:CreateKeybind({
	Name = "Key Vacuum",
	CurrentKeybind = "G",
	Flag = "GalaxyVacuum_KeyWalk",
	Callback = function()
		if vacWalkT then
			pcall(function()
				vacWalkT:Set(not vacWalkT:Get())
			end)
		end
	end,
})

local vacTeleT: any = nil
vacTeleT = VacBox:CreateToggle({
	Name = "Teleport vacuum",
	Desc = "TP ke loot lalu hold otomatis",
	CurrentValue = false,
	Flag = "GalaxyVacuum_Tele",
	Callback = function(v: boolean)
		Cfg.teleVacuum = v
		task.spawn(function()
			while Cfg.teleVacuum and isMine() and (typeof(STATE) ~= "table" or STATE.alive()) do
				pcall(teleVacuumTick)
				task.wait(effTickTele())
			end
			if not Cfg.teleVacuum and not Cfg.vacuum then
				setStatus("idle")
			end
		end)
	end,
})

VacBox:CreateKeybind({
	Name = "Key Tele-Vacuum",
	CurrentKeybind = "T",
	Flag = "GalaxyVacuum_KeyTele",
	Callback = function()
		if vacTeleT then
			pcall(function()
				vacTeleT:Set(not vacTeleT:Get())
			end)
		end
	end,
})

VacBox:CreateSlider({
	Name = "Radius tele",
	Range = { 50, 500 },
	Increment = 25,
	Suffix = "m",
	CurrentValue = TELE_RADIUS_DEF,
	Flag = "GalaxyVacuum_TeleRadius",
	Callback = function(v: any)
		Cfg.teleRadius = math.clamp(math.floor(tonumber(v) or TELE_RADIUS_DEF), 50, 500)
	end,
})
VacBox:CreateDropdown({
	Name = "Tier vakum (multi)",
	Desc = "Kosongkan Common biar cuma Legendary+",
	Options = TIER_NAMES,
	CurrentOption = TIER_NAMES,
	MultipleOptions = true,
	AllowNone = false,
	Flag = "GalaxyVacuum_VacTiers",
	Callback = function(v: any)
		local sel: { [number]: boolean } = {}
		local function pick(item: any)
			if type(item) == "number" then
				sel[math.clamp(math.floor(item), 1, #TIER_NAMES)] = true
			elseif type(item) == "string" then
				for i, n in ipairs(TIER_NAMES) do
					if n == item then
						sel[i] = true
						break
					end
				end
			end
		end
		if type(v) == "table" then
			for _, item in ipairs(v) do
				pick(item)
			end
		else
			pick(v)
		end
		if next(sel) ~= nil then
			Cfg.vacTiers = sel
		end
	end,
})

VacBox:CreateButton({
	Name = "Teleport to Meteor",
	Callback = function()
		task.spawn(function()
			pcall(tpToMeteor)
		end)
	end,
})

statusLabel = VacBox:CreateLabel({
	Text = "idle",
})
task.spawn(function()
	while isMine() and (typeof(STATE) ~= "table" or STATE.alive()) do
		pcall(function()
			local txt = Run.status .. (Run.busy and " ..." or "")
			if not (Cfg.vacuum or Cfg.teleVacuum) then
				txt = "idle"
			end
			if statusLabel.Set then
				statusLabel:Set(txt)
			else
				statusLabel:Update(txt)
			end
		end)
		task.wait(0.5)
	end
end)

local SellBox = MainTab:CreateGroupbox({ Name = "Auto Sell", Side = "Left" })
SellBox:CreateSlider({
	Name = "Jual saat",
	Range = { 10, 100 },
	Increment = 5,
	Suffix = "%",
	CurrentValue = 90,
	Flag = "GalaxyVacuum_SellPct",
	Callback = function(v: any)
		local n = tonumber(v) or 90
		Cfg.sellPct = math.clamp(math.floor(n), 10, 100)
	end,
})
SellBox:CreateToggle({
	Name = "Auto sell",
	Desc = "TP stand + jual semua saat tas penuh",
	CurrentValue = false,
	Flag = "GalaxyVacuum_AutoSell",
	Callback = function(v: boolean)
		Cfg.autoSell = v
		task.spawn(function()
			while Cfg.autoSell and isMine() and (typeof(STATE) ~= "table" or STATE.alive()) do
				pcall(function()
					if Run.sellNow or cargoPct() >= Cfg.sellPct then
						doSell()
					end
				end)
				task.wait(1)
			end
		end)
	end,
})
SellBox:CreateButton({
	Name = "Sell Now",
	Callback = function()
		task.spawn(function()
			pcall(doSell)
		end)
	end,
})

-- Jetpack: drain = 28 * FuelDrainMult (JetpackFlight:638). 0 = infinite. Tutorial overwrite nil -> loop reapply.
local function setInfFuel(on: boolean)
	Cfg.infFuel = on
	task.spawn(function()
		while Cfg.infFuel and isMine() and (typeof(STATE) ~= "table" or STATE.alive()) do
			pcall(function()
				LocalPlayer:SetAttribute("FuelDrainMult", 0)
			end)
			task.wait(0.5)
		end
		pcall(function()
			LocalPlayer:SetAttribute("FuelDrainMult", nil)
		end)
	end)
end

-- Noclip: CanCollide false tiap 0.1s (respawn-safe). Off: balikin true.
local function setNoclip(on: boolean)
	Cfg.noclip = on
	task.spawn(function()
		while Cfg.noclip and isMine() and (typeof(STATE) ~= "table" or STATE.alive()) do
			pcall(function()
				local char = LocalPlayer.Character
				if char then
					for _, d in ipairs(char:GetDescendants()) do
						if d:IsA("BasePart") then
							(d :: BasePart).CanCollide = false
						end
					end
				end
			end)
			task.wait(0.1)
		end
		pcall(function()
			local char = LocalPlayer.Character
			if char then
				for _, d in ipairs(char:GetDescendants()) do
					if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
						(d :: BasePart).CanCollide = true
					end
				end
			end
		end)
	end)
end

local MonBox = MainTab:CreateGroupbox({ Name = "Monitor Top10", Side = "Right" })
MonBox:CreateDropdown({
	Name = "Tier (multi)",
	Options = TIER_NAMES,
	CurrentOption = TIER_NAMES, -- semua terpilih default
	MultipleOptions = true,
	AllowNone = false,
	Flag = "GalaxyVacuum_MonTiers",
	Callback = function(v: any)
		local sel: { [number]: boolean } = {}
		local function pick(item: any)
			if type(item) == "number" then
				sel[math.clamp(math.floor(item), 1, #TIER_NAMES)] = true
			elseif type(item) == "string" then
				for i, n in ipairs(TIER_NAMES) do
					if n == item then
						sel[i] = true
						break
					end
				end
			end
		end
		if type(v) == "table" then
			for _, item in ipairs(v) do
				pick(item)
			end
		else
			pick(v)
		end
		if next(sel) ~= nil then
			Cfg.monTiers = sel
		end
		monRefreshSoon = true
	end,
})
MonBox:CreateDropdown({
	Name = "Sort by",
	Options = { "Value", "Luck" },
	CurrentOption = "Value",
	Flag = "GalaxyVacuum_MonSort",
	Callback = function(v: any)
		if type(v) == "string" and (v == "Value" or v == "Luck") then
			Cfg.monSort = v
		elseif type(v) == "number" then
			Cfg.monSort = (v == 2) and "Luck" or "Value"
		end
		monRefreshSoon = true
	end,
})
MonBox:CreateButton({
	Name = "Refresh",
	Callback = function()
		monRefreshSoon = true
	end,
})
monTable = MonBox:CreateTable({
	Name = "Top loot (klik = TP)",
	Columns = { "Tier", "Gem", "Value", "Luck", "Wt", "Dist" },
	Rows = {},
	MaxRows = 10,
	Search = false, -- mati agar index baris = MonRows (klik mapping aman)
	Callback = clickRow,
})
task.spawn(function()
	while isMine() and (typeof(STATE) ~= "table" or STATE.alive()) do
		pcall(function()
			if monRefreshSoon or os.clock() - monAt > 5 then
				monAt = os.clock()
				monRefreshSoon = false
				refreshMonitor()
			end
		end)
		task.wait(1)
	end
end)

local TeleTab = Window:CreateTab({ Name = "Teleport", Icon = "rocket" })
local TeleBox = TeleTab:CreateGroupbox({ Name = "Planets", Side = "Left" })
TeleBox:CreateStatusList({
	Name = "Aktif",
	MaxRows = 4,
	UpdateRate = 5,
	Update = function()
		local hrp = getHRP()
		local myPos = hrp and hrp.Position or Vector3.zero
		local rows: { any } = {}
		for _, p in ipairs(planetList()) do
			local d = math.floor((p.center - myPos).Magnitude)
			table.insert(rows, {
				Text = string.format("%s (%s h%d)", p.name, p.slot, p.hard),
				Value = string.format("+%d%% bonus Â· %dm", math.floor(p.bonus * 100 + 0.5), d),
			})
		end
		return rows
	end,
})
local telePlanetDD: any = nil
telePlanetDD = TeleBox:CreateDropdown({
	Name = "Planet",
	Options = { "Zenith", "Maelstrom", "Tidal", "Cyclone" },
	CurrentOption = "Zenith",
	Flag = "GalaxyVacuum_TelePlanet",
	Callback = function(_v: any)
	end,
})
TeleBox:CreateButton({
	Name = "Refresh Planets",
	Callback = function()
		pcall(function()
			local names: { string } = {}
			for _, p in ipairs(planetList()) do
				table.insert(names, p.name)
			end
			if #names > 0 then
				telePlanetDD:Refresh(names, true)
			end
		end)
		setStatus("planets refreshed")
	end,
})
TeleBox:CreateButton({
	Name = "Teleport",
	Callback = function()
		task.spawn(function()
			pcall(function()
				local sel: any = "Zenith"
				pcall(function()
					sel = telePlanetDD:Get()
				end)
				if type(sel) == "table" then
					sel = sel[1] or "Zenith"
				end
				if type(sel) == "number" then
					local names: { string } = {}
					for _, p in ipairs(planetList()) do
						table.insert(names, p.name)
					end
					sel = names[sel] or "Zenith"
				end
				local _, msg = teleportToPlanet(tostring(sel))
				setStatus("tp: " .. msg)
			end)
		end)
	end,
})

local ShopTab = Window:CreateTab({ Name = "Shop", Icon = "shopping-cart" })
local ShopBox = ShopTab:CreateGroupbox({ Name = "Auto Buy", Side = "Left" })
local shopLabel: any = nil
shopLabel = ShopBox:CreateLabel({ Text = "stock rotates 10 min" })
ShopBox:CreateDropdown({
	Name = "Bomb (multi)",
	Options = BOMB_IDS,
	CurrentOption = { "meteor_charge" },
	MultipleOptions = true,
	AllowNone = false,
	Flag = "GalaxyVacuum_ShopBombs",
	Callback = function(v: any)
		local sel: { [string]: boolean } = {}
		if type(v) == "table" then
			for _, item in ipairs(v) do
				if table.find(BOMB_IDS, item) then
					sel[item] = true
				end
			end
		elseif type(v) == "string" and table.find(BOMB_IDS, v) then
			sel[v] = true
		end
		if next(sel) ~= nil then
			Cfg.shopBombs = sel
		end
	end,
})
ShopBox:CreateToggle({
	Name = "Auto Buy Bomb",
	Desc = "1x per stok per jenis (anti boros)",
	CurrentValue = false,
	Flag = "GalaxyVacuum_AutoBomb",
	Callback = function(v: boolean)
		Cfg.autoBomb = v
		task.spawn(function()
			while Cfg.autoBomb and isMine() and (typeof(STATE) ~= "table" or STATE.alive()) do
				pcall(function()
					for id in pairs(Cfg.shopBombs) do
						local okB, msg = buyGear(id, true)
						if shopLabel and (okB or (msg ~= "already bought" and msg ~= "out of stock")) then
							shopLabel:Set("bomb: " .. msg)
						end
						if okB then
							break -- 1 beli per tick, hemat
						end
					end
				end)
				task.wait(5)
			end
		end)
	end,
})
ShopBox:CreateButton({
	Name = "Buy Bomb Now",
	Callback = function()
		task.spawn(function()
			pcall(function()
				local last = ""
				for id in pairs(Cfg.shopBombs) do
					local _, msg = buyGear(id, false)
					last = msg
				end
				if shopLabel then
					shopLabel:Set("bomb: " .. last)
				end
			end)
		end)
	end,
})
ShopBox:CreateDropdown({
	Name = "Radar (multi)",
	Options = RADAR_IDS,
	CurrentOption = { "pocket_pinger" },
	MultipleOptions = true,
	AllowNone = false,
	Flag = "GalaxyVacuum_ShopRadars",
	Callback = function(v: any)
		local sel: { [string]: boolean } = {}
		if type(v) == "table" then
			for _, item in ipairs(v) do
				if table.find(RADAR_IDS, item) then
					sel[item] = true
				end
			end
		elseif type(v) == "string" and table.find(RADAR_IDS, v) then
			sel[v] = true
		end
		if next(sel) ~= nil then
			Cfg.shopRadars = sel
		end
	end,
})
ShopBox:CreateToggle({
	Name = "Auto Buy Radar",
	Desc = "1x per stok per jenis (anti boros)",
	CurrentValue = false,
	Flag = "GalaxyVacuum_AutoRadar",
	Callback = function(v: boolean)
		Cfg.autoRadar = v
		task.spawn(function()
			while Cfg.autoRadar and isMine() and (typeof(STATE) ~= "table" or STATE.alive()) do
				pcall(function()
					for id in pairs(Cfg.shopRadars) do
						local okR, msg = buyGear(id, true)
						if shopLabel and (okR or (msg ~= "already bought" and msg ~= "out of stock")) then
							shopLabel:Set("radar: " .. msg)
						end
						if okR then
							break
						end
					end
				end)
				task.wait(5)
			end
		end)
	end,
})
ShopBox:CreateButton({
	Name = "Buy Radar Now",
	Callback = function()
		task.spawn(function()
			pcall(function()
				local last = ""
				for id in pairs(Cfg.shopRadars) do
					local _, msg = buyGear(id, false)
					last = msg
				end
				if shopLabel then
					shopLabel:Set("radar: " .. last)
				end
			end)
		end)
	end,
})

local MiscTab = Window:CreateTab({ Name = "Misc", Icon = "wrench" })
local MiscBox = MiscTab:CreateGroupbox({ Name = "Movement", Side = "Left" })
MiscBox:CreateToggle({
	Name = "Infinite Fuel",
	Desc = "Drain 0 (atribut lokal, server cuma terima Thrust)",
	CurrentValue = false,
	Flag = "GalaxyVacuum_InfFuel",
	Callback = setInfFuel,
})
MiscBox:CreateToggle({
	Name = "Noclip",
	Desc = "Tembus terrain/planet",
	CurrentValue = false,
	Flag = "GalaxyVacuum_Noclip",
	Callback = setNoclip,
})

local SrvPlayers = MiscTab:CreateGroupbox({ Name = "Players", Side = "Right" })
local srvPlayerDD: any = nil
srvPlayerDD = SrvPlayers:CreateDropdown({
	Name = "Player",
	Options = playerNames(),
	CurrentOption = 1,
	Searchable = true,
	Flag = "GalaxyVacuum_SrvPlayer",
	Callback = function(_v: any)
	end,
})
SrvPlayers:CreateButton({
	Name = "Refresh Players",
	Callback = function()
		local vals = playerNames()
		pcall(function()
			srvPlayerDD:Refresh(vals, true)
		end)
		setStatus("server: " .. #vals .. " listed")
	end,
})
SrvPlayers:CreateButton({
	Name = "Teleport to Player",
	Callback = function()
		task.spawn(function()
			pcall(function()
				local name: string = "-"
				pcall(function()
					name = srvPlayerDD:Get()
				end)
				if type(name) == "table" then
					name = (name :: any)[1] or "-"
				end
				if type(name) == "number" then
					name = playerNames()[name] or "-"
				end
				local ok, msg = teleportToPlayer(name)
				setStatus("tp: " .. msg)
			end)
		end)
	end,
})

local SrvAct = MiscTab:CreateGroupbox({ Name = "Server Actions", Side = "Right" })
SrvAct:CreateButton({
	Name = "Rejoin",
	Callback = function()
		local _, msg = serverRejoin()
		setStatus("server: " .. msg)
	end,
})
SrvAct:CreateButton({
	Name = "Hop Server",
	Callback = function()
		task.spawn(function()
			local _, msg = serverHop()
			setStatus("server: " .. msg)
		end)
	end,
})
SrvAct:CreateButton({
	Name = "Reset Character",
	Callback = function()
		local _, msg = resetCharacter()
		setStatus("server: " .. msg)
	end,
})
SrvAct:CreateButton({
	Name = "Refresh (posisi balik)",
	Callback = function()
		task.spawn(function()
			local _, msg = refreshKeepPos()
			setStatus("server: " .. msg)
		end)
	end,
})


local SettingsTab = Window:CreateTab({ Name = "Settings", Icon = "settings" })
SettingsTab:CreateConfigManager({ Side = "Left" })
SettingsTab:CreateThemeManager({ Side = "Right" })
Window:LoadAutoload()

-- =====================================================================
-- 9. CLEANUP (live-reload safe)
-- =====================================================================
local function unload()
	getgenv()[EPOCH_KEY] = -1
	Cfg.vacuum = false
	Cfg.teleVacuum = false
	Cfg.autoSell = false
	Cfg.infFuel = false
	Cfg.noclip = false
	pcall(function()
		LocalPlayer:SetAttribute("FuelDrainMult", nil)
	end)
	pcall(function()
		local char = LocalPlayer.Character
		if char then
			for _, d in ipairs(char:GetDescendants()) do
				if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
					(d :: BasePart).CanCollide = true
				end
			end
		end
	end)
	pcall(function()
		Window:Destroy()
	end)
end
if typeof(STATE) == "table" and STATE.onCleanup then
	STATE.onCleanup(unload)
end
getgenv().__GALAXY_VACUUM_UNLOAD = unload

print("[GalaxyVacuum] v22 loaded (-3 UI). Dropped ikut + aggro permanen.")
