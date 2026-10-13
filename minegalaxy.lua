--!nonstrict
-- GalaxyVacuum_Airflow v8
-- Game: Mine a Galaxy | Loot vacuum via ProximityPrompt hold (HoldLoot + swing loop game yang urus)
-- Fitur: [1] Vacuum jalan [2] Teleport vacuum [3] Monitor Top10 [4] Auto Sell [5] Misc: Infinite Fuel + Noclip
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

local LocalPlayer = Players.LocalPlayer
local Items = ReplicatedStorage:WaitForChild("Items")
local ItemData = require(Items:WaitForChild("ItemData"))
local LootFolder: Folder = workspace:WaitForChild("Loot") :: Folder

-- =====================================================================
-- 2. CONSTANTS
-- =====================================================================
local VACUUM_RADIUS = 14 -- MaxDist prompt game ~15.45, ambil aman 14
local TELE_RADIUS = 150 -- jangkauan scan teleport vacuum
local TICK_VACUUM = 0.4
local TICK_TELE = 0.6
local HOLD_TIMEOUT = 10 -- stop hold kalau loot alot (detik)
local HOVER_UP = 4 -- hover di atas loot saat TP
local TP_STEP = 55 -- teleport bertahap anti rubber-band
local RETRY_COOLDOWN = 3 -- jangan sentuh loot gagal sebelum X detik
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

-- Validasi target vakum: mirror syarat isLootPrompt + fitPrompt game
local function isValidTarget(loot: Instance, hrpPos: Vector3, maxDist: number): (boolean, ProximityPrompt?)
	if loot.Parent ~= LootFolder then
		return false, nil
	end
	if not loot:IsA("BasePart") then
		return false, nil
	end
	if loot:GetAttribute("Dropped") then
		return false, nil -- jalur Dropped beda, skip
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
	if prompt.ActionText == "TOO HEAVY" or prompt.ActionText == "NEEDS BETTER PICKAXE" then
		return false, nil
	end
	local tier = loot:GetAttribute("Tier") or 1
	if not ItemData.canBreak(myPickaxe(), tier) then
		return false, nil
	end
	if not cargoFits(loot:GetAttribute("Weight") or 0) then
		return false, nil
	end
	if (loot.Position - hrpPos).Magnitude > maxDist then
		return false, nil
	end
	if os.clock() - (Run.tryAt[lootUid(loot)] or 0) < RETRY_COOLDOWN then
		return false, nil
	end
	return true, prompt
end

local function findBest(maxDist: number)
	local hrp = getHRP()
	if not hrp then
		return nil, nil, nil
	end
	local hrpPos = hrp.Position
	local best: BasePart? = nil
	local bestPrompt: ProximityPrompt? = nil
	local bestDist = math.huge
	for _, loot in ipairs(LootFolder:GetChildren()) do
		local ok, prompt = isValidTarget(loot, hrpPos, maxDist)
		if ok and prompt then
			local d = ((loot :: BasePart).Position - hrpPos).Magnitude
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
	task.spawn(function()
		task.wait(HOLD_TIMEOUT)
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
	while loot.Parent and not loot:GetAttribute("Taken") and os.clock() - t0 < HOLD_TIMEOUT do
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

-- =====================================================================
-- 7. LOOPS (satu target sekali jalan, anti double-hold)
-- =====================================================================
local function vacuumTick()
	if Run.busy then
		return
	end
	local loot, prompt, dist = findBest(VACUUM_RADIUS)
	if not loot or not prompt then
		setStatus("vacuum: no target <= " .. VACUUM_RADIUS .. "m")
		return
	end
	Run.busy = true
	setStatus("vacuum: " .. loot.Name .. " " .. math.floor(dist) .. "m")
	holdTarget(loot, prompt)
	Run.busy = false
end

local function teleVacuumTick()
	if Run.busy then
		return
	end
	local loot, prompt, dist = findBest(TELE_RADIUS)
	if not loot or not prompt then
		setStatus("tele: no target <= " .. TELE_RADIUS .. "m")
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
local VacBox = MainTab:CreateGroupbox({ Name = "Vacuum", Side = "Left" })
local statusLabel: any = nil

VacBox:CreateToggle({
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
				task.wait(TICK_VACUUM)
			end
			if not Cfg.vacuum then
				setStatus("idle")
			end
		end)
	end,
})

VacBox:CreateToggle({
	Name = "Teleport vacuum",
	Desc = "TP ke loot <= 150m lalu hold otomatis",
	CurrentValue = false,
	Flag = "GalaxyVacuum_Tele",
	Callback = function(v: boolean)
		Cfg.teleVacuum = v
		task.spawn(function()
			while Cfg.teleVacuum and isMine() and (typeof(STATE) ~= "table" or STATE.alive()) do
				pcall(teleVacuumTick)
				task.wait(TICK_TELE)
			end
			if not Cfg.teleVacuum and not Cfg.vacuum then
				setStatus("idle")
			end
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
local JetBox = MainTab:CreateGroupbox({ Name = "Jetpack", Side = "Left" })
JetBox:CreateToggle({
	Name = "Infinite Fuel",
	Desc = "Drain 0 (atribut lokal, server cuma terima Thrust)",
	CurrentValue = false,
	Flag = "GalaxyVacuum_InfFuel",
	Callback = function(v: boolean)
		Cfg.infFuel = v
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
	end,
})

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
	pcall(function()
		LocalPlayer:SetAttribute("FuelDrainMult", nil)
	end)
	pcall(function()
		Window:Destroy()
	end)
end
if typeof(STATE) == "table" and STATE.onCleanup then
	STATE.onCleanup(unload)
end
getgenv().__GALAXY_VACUUM_UNLOAD = unload

print("[GalaxyVacuum] v7 loaded (-3 UI). Vacuum + TeleVac + Monitor + AutoSell + InfFuel.")
