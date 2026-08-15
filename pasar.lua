--!nocheck
-- Pasar Setan Auto Forage v2 (mode konservatif)-- Improvement berbasis analisis anti-cheat:
--   * server-authoritative: validasi state, bukan deteksi client
--   * teleport horizontal aman (tidak dicek), tapi minimalkan warp supaya tak mencolok
--   * pickup = fireproximityprompt (API engine, seperti pemain pegang E)
--   * rate-limit poll longgar; yg berbahaya cuma spam remote pengubah state (bukan ini)
-- MODE KONSERVATIF (anti-kick 267):
--   * delay 3-6s antar pickup
--   * max 4 pickup per cycle (tidak sapu semua)
--   * jeda 30-60s antar cycle (seperti pemain AFK)
--   * tanpa warp antar spawn — jalan kaki normal

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles
getgenv().PasarsetanHub = Library

local Window = Library:CreateWindow({
	Title = "Pasar Setan",
	Footer = "Auto Forage v2",
	Icon = 95816097006870,
	NotifySide = "Right",
	ShowCustomCursor = true,
})

local Tab = Window:AddTab("Main", "user")

-- ============ PRIORITAS URUTAN ============
local PrioBox = Tab:AddLeftGroupbox("Prioritas Urutan")

PrioBox:AddToggle("PrioritasUrutan", {
	Text = "Mode Prioritas",
	Default = false,
	Tooltip = "Jalankan auto sesuai urutan slot di bawah (1 thread, anti-tabrakan)",
	Risky = true,
})
PrioBox:AddSlider("PrioJeda", {
	Text = "Jeda antar fitur (s)", Default = 10, Min = 3, Max = 60, Rounding = 0,
	Tooltip = "Jeda saat pindah dari satu fitur ke fitur berikutnya",
})

local FITUR = { "Forage", "Tanam", "Siram", "Panen", "Potong", "Cook", "Serve" }
local FITUR_KOSONG = "Kosong"

-- peta fitur -> toggle yang mengontrol
local FITUR_TOGGLE = {
	Forage = "AutoForage",
	Tanam = "AutoTanam",
	Siram = "AutoSiram",
	Panen = "AutoHarvest",
	Potong = "AutoCut",
	Cook = "AutoCook",
	Serve = "AutoServe",
}

local function clearFiturDariSlotLain(fitur, sourceSlot)
	for i = 1, 7 do
		if i ~= sourceSlot then
			local opt = Options["Slot" .. i]
			if opt and opt.Value == fitur then
				opt:SetValue(FITUR_KOSONG)
			end
		end
	end
end

for i = 1, 7 do
	local slotName = "Slot" .. i
	PrioBox:AddDropdown(slotName, {
		Values = { FITUR_KOSONG, unpack(FITUR) },
		Default = FITUR_KOSONG,
		Text = "Urutan " .. i,
		Tooltip = "Fitur yang jalan di posisi ke-" .. i,
		Callback = function(Value)
			if Value and Value ~= FITUR_KOSONG then
				clearFiturDariSlotLain(Value, i)
			end
		end,
	})
end

local Box = Tab:AddLeftGroupbox("Auto Forage")

Box:AddToggle("AutoForage", {
	Text = "Auto Forage",
	Default = false,
	Tooltip = "Mulai / stop forage otomatis",
	Risky = true,
})

local BAHAN = { "Melati", "Kemenyan", "Dupa", "Gagak", "JamurKuburan", "KepitingSungai" }
Box:AddDropdown("BahanFilter", {
	Values = BAHAN,
	Default = 1,
	Multi = true,
	Text = "Bahan yang diambil",
	Callback = function(Value)
		if next(Value) == nil then
			Options.BahanFilter:SetValue({ Melati = true, Kemenyan = true, Dupa = true, Gagak = true, JamurKuburan = true, KepitingSungai = true })
		end
	end,
})
Options.BahanFilter:SetValue({ Melati = true, Kemenyan = true, Dupa = true, Gagak = true, JamurKuburan = true, KepitingSungai = true })

Box:AddSlider("DelayMin", {
	Text = "Delay min (s)", Default = 3, Min = 0.5, Max = 10, Rounding = 1,
	Tooltip = "Jeda acak minimal antar pickup",
})
Box:AddSlider("DelayMax", {
	Text = "Delay max (s)", Default = 6, Min = 1, Max = 15, Rounding = 1,
	Tooltip = "Jeda acak maksimal antar pickup",
})
Box:AddSlider("SkipChance", {
	Text = "Skip chance (%)", Default = 30, Min = 0, Max = 70, Rounding = 0,
	Tooltip = "Peluang melewatkan 1 spawn (seperti manusia yg tak ambil semua)",
})
Box:AddSlider("MaxPerCycle", {
	Text = "Max pickup / cycle", Default = 4, Min = 1, Max = 10, Rounding = 0,
	Tooltip = "Batas pickup per cycle — jangan sapu semua spawn sekaligus",
})
Box:AddSlider("CyclePause", {
	Text = "Jeda antar cycle (s)", Default = 45, Min = 10, Max = 180, Rounding = 0,
	Tooltip = "Berhenti lama setelah 1 cycle, seperti pemain yg beralih kegiatan",
})
Box:AddSlider("RestEvery", {
	Text = "Rest tiap (pickup)", Default = 3, Min = 1, Max = 10, Rounding = 0,
	Tooltip = "Setiap N pickup, berhenti sejenak (2-6 dtk)",
})
Box:AddSlider("WalkSpeed", {
	Text = "Walk speed", Default = 18, Min = 16, Max = 64, Rounding = 0,
	Tooltip = "Kecepatan jalan antar spawn",
})
Box:AddSlider("WarpDist", {
	Text = "Warp threshold (stud)", Default = 150, Min = 50, Max = 300, Rounding = 0,
	Tooltip = "Teleport HANYA utk jarak sangat jauh (>150); sisanya jalan normal",
})

Box:AddDivider()
Box:AddLabel("StatusLabel", {
	Text = "Status: Idle",
	DoesWrap = true,
	Size = 14,
})
Box:AddLabel("StatsLabel", {
	Text = "Picked: 0",
	DoesWrap = true,
	Size = 13,
})

-- ============ AUTO KEBUN ============
local KebunBox = Tab:AddRightGroupbox("Auto Kebun")

KebunBox:AddToggle("AutoTanam", {
	Text = "Auto Tanam",
	Default = false,
	Tooltip = "Tanam seed di plot kebunmu otomatis (butuh seed di backpack)",
	Risky = true,
})
KebunBox:AddDropdown("SeedPilihan", {
	Values = { "Melati", "Kamboja", "Pisang", "Semua" },
	Default = "Semua",
	Text = "Jenis bibit",
	Tooltip = "Pilih bibit yang ditanam (Semua = pakai bibit pertama yang ditemukan)",
})
KebunBox:AddToggle("AutoSiram", {
	Text = "Auto Siram",
	Default = false,
	Tooltip = "Siram tanaman yang butuh air secara otomatis",
	Risky = true,
})
KebunBox:AddToggle("AutoHarvest", {
	Text = "Auto Panen",
	Default = false,
	Tooltip = "Panen tanaman yang sudah siap secara otomatis",
	Risky = true,
})
KebunBox:AddSlider("TanamJeda", {
	Text = "Jeda tanam (s)", Default = 8, Min = 3, Max = 30, Rounding = 0,
	Tooltip = "Jeda antar penanaman bibit",
})
KebunBox:AddSlider("SiramJeda", {
	Text = "Jeda siram (s)", Default = 2, Min = 0.5, Max = 10, Rounding = 1,
	Tooltip = "Jeda antar penyiraman",
})

-- ============ AUTO COOK ============
local CookBox = Tab:AddRightGroupbox("Auto Cook")

CookBox:AddToggle("AutoCook", {
	Text = "Auto Cook",
	Default = false,
	Tooltip = "Masak menu terpilih di kompor kiosmu secara otomatis",
	Risky = true,
})
CookBox:AddDropdown("MenuPilihan", {
	Values = { "Bakar", "Rebus", "TumisKamboja", "SateKepiting", "PisangRebus" },
	Default = "Rebus",
	Multi = true,
	Text = "Menu masakan (multi)",
	Tooltip = "Pilih satu atau lebih resep yang dimasak (coba semua yang punya bahan)",
	Callback = function(Value)
		if next(Value) == nil then
			Options.MenuPilihan:SetValue({ Rebus = true })
		end
	end,
})
Options.MenuPilihan:SetValue({ Rebus = true })
CookBox:AddToggle("AutoCut", {
	Text = "Auto Potong Gagak",
	Default = false,
	Tooltip = "Potong Gagak jadi Daging Gagak di meja pemotongan otomatis",
	Risky = true,
})
CookBox:AddSlider("CookJeda", {
	Text = "Jeda masak (s)", Default = 5, Min = 2, Max = 30, Rounding = 0,
	Tooltip = "Jeda antar mulai masak",
})

-- ============ AUTO SERVE ============
local ServeBox = Tab:AddRightGroupbox("Auto Serve")

ServeBox:AddToggle("AutoServe", {
	Text = "Auto Serve",
	Default = false,
	Tooltip = "Layani arwah di kiosmu: ambil item yg diminta dari rak/meja, lalu berikan ke arwah",
	Risky = true,
})
ServeBox:AddSlider("ServeJeda", {
	Text = "Jeda serve (s)", Default = 3, Min = 1, Max = 15, Rounding = 0,
	Tooltip = "Jeda antar layanan arwah",
})

local UISettingsTab = Window:AddTab("UI Settings", "settings")
local MenuGroup = UISettingsTab:AddLeftGroupbox("Menu", "wrench")
MenuGroup:AddToggle("KeybindMenuOpen", {
	Default = Library.KeybindFrame.Visible,
	Text = "Open Keybind Menu",
	Callback = function(value)
		Library.KeybindFrame.Visible = value
	end,
})
MenuGroup:AddDropdown("NotificationSide", {
	Values = { "Left", "Right" },
	Default = "Right",
	Text = "Notification Side",
	Callback = function(Value)
		Library:SetNotifySide(Value)
	end,
})
MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
Library.ToggleKeybind = Options.MenuKeybind

MenuGroup:AddButton("Unload", function()
	Library:Unload()
end)

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("PasarSetan")
SaveManager:SetFolder("PasarSetan/forage")
SaveManager:BuildConfigSection(UISettingsTab)
ThemeManager:ApplyToTab(UISettingsTab)
SaveManager:LoadAutoloadConfig()

-- ==================== LOGIC ====================

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")

local running = false
local totalPicked = 0
local cycle = 0
local consecutive = 0

local function setStatus(text)
	if Options.StatusLabel then Options.StatusLabel:SetText(text) end
end

local function setStats()
	if Options.StatsLabel then
		Options.StatsLabel:SetText("Picked: " .. totalPicked .. " | Cycle: " .. cycle)
	end
end

local function randDelay()
	local mn = Options.DelayMin.Value
	local mx = Options.DelayMax.Value
	if mx < mn then mx = mn end
	return mn + (math.random() * (mx - mn))
end

local function shuffle(t)
	for i = #t, 2, -1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

local function getCharacter()
	return LocalPlayer.Character
end

-- tunggu karakter kalau lagi mati/respawn
local function waitForCharacter()
	while STATE.alive() and not getCharacter() do
		task.wait(1)
	end
end

local function getSpawns()
	local sb = workspace:FindFirstChild("SpawnBahan")
	if not sb then return {} end
	local filter = Options.BahanFilter.Value
	local out = {}
	for _, c in ipairs(sb:GetChildren()) do
		local item = c.Name:match("^Spawn_(.+)$")
		if item and (filter[item] or filter == true) then
			local bv = c:FindFirstChild("BahanVisual")
			if bv then
				local grip = bv:FindFirstChild("Grip")
				local prompt = grip and grip:FindFirstChildOfClass("ProximityPrompt")
				if prompt and prompt.Enabled then
					out[#out + 1] = { spawn = c, grip = grip, prompt = prompt, item = item }
				end
			end
		end
	end
	return out
end

local function moveTo(target, warpDist)
	local char = getCharacter()
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return false end

	local dist = (hrp.Position - target).Magnitude
	if dist > warpDist then
		-- warp hanya utk jarak SANGAT jauh; server tidak mendeteksi tp horizontal
		-- (mode konservatif: jarang terjadi karena threshold tinggi)
		hrp.CFrame = CFrame.new(target + Vector3.new(0, 1.5, 0))
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		return true
	end

	hum.WalkSpeed = Options.WalkSpeed.Value
	hum:MoveTo(target)
	local elapsed = 0
	local lastPos = hrp.Position
	while STATE.alive() and elapsed < 6 do
		local now = hrp.Position
		if (now - target).Magnitude <= 3.0 then
			hum:MoveTo(hrp.Position)
			return true
		end
		-- stuck detector: tak bergerak > 2.5s -> warp
		if elapsed > 2.5 and (now - lastPos).Magnitude < 1 then
			hum:MoveTo(hrp.Position)
			hrp.CFrame = CFrame.new(target + Vector3.new(0, 1.5, 0))
			return true
		end
		lastPos = now
		task.wait(0.1)
		elapsed = elapsed + 0.1
	end
	hum:MoveTo(hrp.Position)
	hrp.CFrame = CFrame.new(target + Vector3.new(0, 1.5, 0))
	return true
end

local function pickup(spawnData)
	local char = getCharacter()
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local arrived = moveTo(spawnData.grip.Position + Vector3.new(0, 1, 0), Options.WarpDist.Value)
	if not arrived then return false end

	-- arahkan kamera/karakter ke spawn (seperti pemain)
	task.wait(0.15 + math.random() * 0.3)

	-- retry 2x kalau prompt belum siap
	local fired = false
	for attempt = 1, 2 do
		local held = pcall(function()
			spawnData.prompt:InputHoldBegin()
			task.wait(0.5 + math.random() * 0.2)
		end)
		local ok = pcall(function()
			fireproximityprompt(spawnData.prompt)
		end)
		pcall(function()
			spawnData.prompt:InputHoldEnd()
		end)
		if ok then fired = true break end
		task.wait(0.2)
	end
	if fired then
		totalPicked = totalPicked + 1
		consecutive = consecutive + 1
		setStats()
		return true
	end
	return false
end

local function forageCycle()
	local spawns = shuffle(getSpawns())
	if #spawns == 0 then return 0 end
	local picked = 0
	local skipChance = Options.SkipChance.Value / 100
	local maxPerCycle = Options.MaxPerCycle.Value
	for _, s in ipairs(spawns) do
		if not STATE.alive() then break end
		-- batas pickup per cycle (anti-pola bot)
		if picked >= maxPerCycle then break end
		-- kadang skip spawn (manusiawi)
		if math.random() < skipChance then
			task.wait(1 + math.random() * 2)
			continue
		end
		local ok = pcall(pickup, s)
		if ok then picked = picked + 1 end
		-- istirahat berkala (anti-pola bot)
		if consecutive >= Options.RestEvery.Value then
			consecutive = 0
			setStatus("Istirahat sejenak...")
			task.wait(2 + math.random() * 4)
			continue
		end
		if running and STATE.alive() then
			task.wait(randDelay())
		end
	end
	return picked
end

-- ============ AUTO KEBUN ============

local me = LocalPlayer
local function myPlots()
	local lp = workspace:FindFirstChild("LahanPlot")
	if not lp then return {} end
	local out = {}
	for _, c in ipairs(lp:GetChildren()) do
		if c:IsA("BasePart") and c:GetAttribute("Owner") == me.UserId then
			out[#out + 1] = c
		end
	end
	return out
end

local function findTool(name)
	for _, c in ipairs(me.Backpack:GetChildren()) do
		if c:IsA("Tool") and (c.Name == name or c:GetAttribute("IsSeed")) then
			return c
		end
	end
	if me.Character then
		for _, c in ipairs(me.Character:GetChildren()) do
			if c:IsA("Tool") and (c.Name == name or c:GetAttribute("IsSeed")) then
				return c
			end
		end
	end
	return nil
end

local function equipTool(tool)
	local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
	if hum and tool then
		pcall(function() hum:EquipTool(tool) end)
		task.wait(0.3)
	end
end

local function plantSeed(plot)
	-- pilihan bibit: filter by nama tool
	local pilihan = Options.SeedPilihan and Options.SeedPilihan.Value or "Semua"
	local seed = nil
	local function isMatch(name)
		local lower = name:lower()
		if pilihan == "Semua" then return true end
		return lower:find(string.lower(pilihan), 1, true) ~= nil
	end
	-- scan backpack + karakter, prefer tool yang masih ada
	for _, c in ipairs(me.Backpack:GetChildren()) do
		if c:IsA("Tool") and c:GetAttribute("IsSeed") and isMatch(c.Name) then seed = c break end
	end
	if not seed and me.Character then
		for _, c in ipairs(me.Character:GetChildren()) do
			if c:IsA("Tool") and c:GetAttribute("IsSeed") and isMatch(c.Name) then seed = c break end
		end
	end
	if not seed then return "no_seed" end

	equipTool(seed)
	local char = getCharacter()
	if not char then return "no_char" end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return "no_hrp" end

	-- posisi acak di dalam plot (dari tengah, offset dalam bounds)
	local size = plot.Size
	local x = (math.random() - 0.5) * (size.X - 4)
	local z = (math.random() - 0.5) * (size.Z - 4)
	local pos = plot.Position + Vector3.new(x, 1, z)

	-- pindah dekat lokasi tanam
	moveTo(pos, Options.WarpDist.Value)
	task.wait(0.3)

	local Tanam = game.ReplicatedStorage.Remotes:FindFirstChild("Tanam")
	if not Tanam then return "no_remote" end
	local ok = pcall(function()
		Tanam:FireServer(pos)
	end)
	task.wait(1)
	return ok and "planted" or "fail"
end

local function waterPlants()
	local penyiram = findTool("PenyiramTanaman")
	if not penyiram then return "no_tool" end
	equipTool(penyiram)

	-- tanaman milik kita yang butuh air
	local watered = 0
	local lp = workspace:FindFirstChild("LahanPlot")
	if lp then
		for _, d in ipairs(lp:GetDescendants()) do
			if not STATE.alive() then break end
			if d:IsA("BasePart") and d:GetAttribute("OwnerId") == me.UserId and d:GetAttribute("PlantKey") then
				local wet = d:GetAttribute("Wet") == true
				local airSisa = tonumber(d:GetAttribute("AirSisa")) or 0
				local airMax = tonumber(d:GetAttribute("AirMax")) or 0
				if not wet or (airMax > 0 and airSisa < airMax) then
					moveTo(d.Position + Vector3.new(0, 1, 0), Options.WarpDist.Value)
					task.wait(0.3)
					local Siram = game.ReplicatedStorage.Remotes:FindFirstChild("Siram")
					if Siram then
						-- 1 fire ≈ +37 air; butuh ~5 fire untuk penuh (150)
						for i = 1, 6 do
							if not STATE.alive() then break end
							pcall(function() Siram:FireServer() end)
							task.wait(0.25 + math.random() * 0.15)
						end
						watered = watered + 1
					end
					task.wait(0.5 + math.random() * 0.5)
				end
			end
		end
	end
	return watered > 0 and "watered" or "done"
end

local function harvestPlants()
	local lp = workspace:FindFirstChild("LahanPlot")
	if not lp then return "no_plot" end
	local harvested = 0
	local Panen = game.ReplicatedStorage.Remotes:FindFirstChild("Panen")
	if not Panen then return "no_remote" end
	for _, d in ipairs(lp:GetDescendants()) do
		if not STATE.alive() then break end
		if d:IsA("BasePart") and d:GetAttribute("OwnerId") == me.UserId and d:GetAttribute("PlantKey") then
			local ready = d:GetAttribute("Ready") == true
			local harvestedFlag = d:GetAttribute("Harvested") == true
			if ready and not harvestedFlag then
				local char = getCharacter()
				if not char then break end
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if not hrp then break end
				moveTo(d.Position + Vector3.new(0, 1, 0), Options.WarpDist.Value)
				task.wait(0.3)
				local ok = pcall(function()
					Panen:FireServer(d)
				end)
				if ok then
					harvested = harvested + 1
				end
				task.wait(0.5 + math.random() * 0.5)
			end
		end
	end
	return harvested > 0 and "panen" or "none"
end

local function kebunCycle()
	local result = {}
	local plots = myPlots()
	-- siram + panen dulu, tanam terakhir (biar tak ganti-ganti tool di tengah siram)
	if Toggles.AutoSiram.Value then
		local r = pcall(waterPlants)
		result.siram = r
	end
	if Toggles.AutoHarvest.Value then
		local r = pcall(harvestPlants)
		result.panen = r
	end
	if Toggles.AutoTanam.Value and #plots > 0 then
		local r = pcall(plantSeed, plots[1])
		result.tanam = r
		-- kalau siram juga aktif, equip balik penyiram (jangan keliatan megang bibit)
		if Toggles.AutoSiram.Value then
			local penyiram = findTool("PenyiramTanaman")
			if penyiram then equipTool(penyiram) end
		end
		task.wait(Options.TanamJeda.Value * (0.7 + math.random() * 0.6))
	end
	return result
end

-- ============ AUTO COOK ============

local function myKios()
	local ka = workspace:FindFirstChild("KiosAktif")
	if not ka then return nil end
	-- kios pemilik = nama "Kios_<PlayerName>"
	local named = ka:FindFirstChild("Kios_" .. me.Name)
	if named then return named end
	for _, k in ipairs(ka:GetChildren()) do
		if k:GetAttribute("Owner") == me.UserId or k:GetAttribute("OwnerId") == me.UserId then
			return k
		end
	end
	return nil
end

local function countItem(itemId)
	local total = 0
	for _, c in ipairs(me.Backpack:GetChildren()) do
		if c:IsA("Tool") and c:GetAttribute("ItemId") == itemId then
			total = total + (c:GetAttribute("Count") or 1)
		end
	end
	if me.Character then
		for _, c in ipairs(me.Character:GetChildren()) do
			if c:IsA("Tool") and c:GetAttribute("ItemId") == itemId then
				total = total + (c:GetAttribute("Count") or 1)
			end
		end
	end
	return total
end

local function cookMenu(menuId)
	local kios = myKios()
	if not kios then return "no_kios" end
	local kompor = kios:FindFirstChild("AlatMasak") and kios.AlatMasak:FindFirstChild("Kompor")
	if not kompor then return "no_kompor" end

	local char = getCharacter()
	if not char then return "no_char" end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return "no_hrp" end

	moveTo(kompor.Position + Vector3.new(0, 1, 0), Options.WarpDist.Value)
	task.wait(0.3)

	local CookStove = game.ReplicatedStorage.Remotes:FindFirstChild("CookStove")
	if not CookStove then return "no_remote" end
	local ok, resp = pcall(function()
		return CookStove:InvokeServer(menuId)
	end)
	if not ok then return "fail" end
	if type(resp) == "table" and resp.ok then
		return "cooking"
	end
	return "no_ingredient"
end

local function cutGagak()
	local kios = myKios()
	if not kios then return "no_kios" end
	local am = kios:FindFirstChild("AlatMasak")
	local potong = am and am:FindFirstChild("Pemotongan")
	if not potong then return "no_meja" end
	local prompt = nil
	for _, d in ipairs(potong:GetDescendants()) do
		if d:IsA("ProximityPrompt") then prompt = d break end
	end
	if not prompt then return "no_prompt" end

	-- cek punya Gagak
	if countItem("Gagak") <= 0 then return "no_gagak" end

	local char = getCharacter()
	if not char then return "no_char" end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return "no_hrp" end

	moveTo(potong.Position + Vector3.new(0, 1, 0), Options.WarpDist.Value)
	task.wait(0.3)

	prompt:InputHoldBegin()
	task.wait(0.5 + math.random() * 0.2)
	local ok = pcall(function()
		fireproximityprompt(prompt)
	end)
	pcall(function()
		prompt:InputHoldEnd()
	end)
	if ok then
		return "cut"
	end
	return "fail"
end

local function cookCycle()
	if not Toggles.AutoCook.Value then return end
	local sel = Options.MenuPilihan and Options.MenuPilihan.Value
	local menus = {}
	if type(sel) == "table" then
		for k, v in pairs(sel) do
			if v then menus[#menus + 1] = k end
		end
	end
	if #menus == 0 then
		menus = { "Rebus" }
	end

	-- auto cut dulu kalau nyala (Gagak -> DagingGagak)
	if Toggles.AutoCut.Value then
		local r = pcall(cutGagak)
		if r then
			setStatus("[Cut] " .. tostring(r))
		end
	end

	-- coba semua menu terpilih
	local cooked = 0
	for _, menu in ipairs(menus) do
		if not STATE.alive() then break end
		local r = pcall(cookMenu, menu)
		if r == "cooking" or r == true then
			cooked = cooked + 1
		end
	end
	if cooked > 0 then
		setStatus("[Cook] " .. cooked .. "x cooking")
	end
	task.wait(Options.CookJeda.Value * (0.7 + math.random() * 0.6))
end

-- ============ AUTO SERVE ============

local function kiosSaya()
	local ka = workspace:FindFirstChild("KiosAktif")
	if not ka then return nil end
	local named = ka:FindFirstChild("Kios_" .. me.Name)
	if named then return named end
	for _, k in ipairs(ka:GetChildren()) do
		if k:GetAttribute("Owner") == me.UserId or k:GetAttribute("OwnerId") == me.UserId then
			return k
		end
	end
	return nil
end

-- cari prompt "Ambil X" di rak/meja kios, kembalikan {prompt, part}
local function cariPromptAmbil(kios, kataKunci)
	local folders = { "Rak", "MejaMakan" }
	for _, folder in ipairs(folders) do
		local f = kios:FindFirstChild(folder)
		if f then
			for _, d in ipairs(f:GetDescendants()) do
				if d:IsA("ProximityPrompt") and d.ActionText and d.ActionText:find("Ambil", 1, true) then
					-- cocokkan ObjectText/ActionText dgn kata kunci item
					local teks = (d.ObjectText or "") .. " " .. (d.ActionText or "")
					if teks:find(kataKunci, 1, true) then
						return d, d.Parent
					end
				end
			end
		end
	end
	return nil, nil
end

-- ambil item dari rak/meja, return itemId atau nil
local function ambilDariKios(kios, kataKunci)
	local prompt, part = cariPromptAmbil(kios, kataKunci)
	if not (prompt and part) then return nil end
	local char = getCharacter()
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	-- kosongkan tangan (pindah tool ke backpack) biar item langsung ke tangan
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") then
			c.Parent = me.Backpack
		end
	end
	task.wait(0.3)

	moveTo(part.Position + Vector3.new(0, 2, 0), Options.WarpDist.Value)
	task.wait(0.4)
	prompt:InputHoldBegin()
	task.wait(0.6)
	local ok = pcall(function()
		fireproximityprompt(prompt)
	end)
	task.wait(0.3)
	pcall(function()
		prompt:InputHoldEnd()
	end)
	task.wait(0.5)
	if not ok then return nil end

	-- item yg baru di tangan (Tool di karakter)
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") and c:GetAttribute("ItemId") then
			return c:GetAttribute("ItemId")
		end
	end
	return nil
end

-- cari ghost yg prompt enabled (siap dilayani) dekat kios
local function ghostSiap(kios, radius)
	local arw = workspace:FindFirstChild("Arwah")
	if not arw then return nil end
	local kpos = kios:GetPivot().Position
	local best = nil
	local bestDist = radius
	for _, g in ipairs(arw:GetChildren()) do
		if g:IsA("Model") and g.PrimaryPart then
			local dist = (g.PrimaryPart.Position - kpos).Magnitude
			if dist <= bestDist then
				for _, d in ipairs(g:GetDescendants()) do
					if d:IsA("ProximityPrompt") and d.Enabled and d.ActionText and d.ActionText:find("Beri ", 1, true) then
						bestDist = dist
						best = { ghost = g, prompt = d, dist = dist }
						break
					end
				end
			end
		end
	end
	return best
end

-- ekstrak nama item dari "Beri X Y"
local function itemDariAksi(act)
	local s = act:gsub("^Beri%s+", "")
	s = s:gsub("Kuburan%s+$", ""):gsub("%s+Kuburan$", "")
	return s
end

local function serveOne(kios, data)
	local act = data.prompt.ActionText
	local kata = itemDariAksi(act)
	-- kata kunci untuk pencarian prompt ambil: pakai kata unik item
	local cari = kata
	-- "Jamur Rebus Kuburan" -> cari "Jamur Rebus"
	if act:find("Jamur Rebus", 1, true) then cari = "Jamur Rebus" end
	if act:find("Sate Gagak", 1, true) then cari = "Sate Gagak" end
	if act:find("Bunga Melati", 1, true) then cari = "Bunga Melati" end
	if act:find("Sate Kepiting", 1, true) then cari = "Sate Kepiting" end
	if act:find("Tumis Kamboja", 1, true) then cari = "Tumis Kamboja" end
	if act:find("Pisang Raja Rebus", 1, true) then cari = "Pisang Raja Rebus" end

	-- ambil item sesuai pesanan ghost
	local itemId = ambilDariKios(kios, cari)
	if not itemId then return "no_item" end

	-- verifikasi ghost masih minta item yg sama + enabled
	if not data.prompt.Enabled or not data.prompt.ActionText:find(cari:gsub("Bunga ", ""), 1, true) then
		return "ghost_changed"
	end

	local char = getCharacter()
	if not char then return "no_char" end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return "no_hrp" end
	local gpos = data.ghost.PrimaryPart and data.ghost.PrimaryPart.Position or data.ghost:GetPivot().Position

	moveTo(gpos + Vector3.new(0, 2, 4), Options.WarpDist.Value)
	task.wait(0.4)
	local dist = (hrp.Position - gpos).Magnitude
	if dist > 10 then return "too_far" end

	local coinsBefore = me.leaderstats and me.leaderstats.Koin and me.leaderstats.Koin.Value or 0
	data.prompt:InputHoldBegin()
	task.wait(0.6)
	local ok = pcall(function()
		fireproximityprompt(data.prompt)
	end)
	task.wait(0.3)
	pcall(function()
		data.prompt:InputHoldEnd()
	end)
	task.wait(1.5)
	local coinsAfter = me.leaderstats and me.leaderstats.Koin and me.leaderstats.Koin.Value or 0
	if ok and coinsAfter > coinsBefore then
		return "served+" .. (coinsAfter - coinsBefore)
	end
	return "no_coin"
end

local function serveCycle()
	if not Toggles.AutoServe.Value then return end
	local kios = kiosSaya()
	if not kios then return "no_kios" end
	-- layani semua ghost siap (max beberapa per cycle)
	local served = 0
	for _ = 1, 3 do
		if not STATE.alive() then break end
		local data = ghostSiap(kios, 30)
		if not data then break end
		local r = pcall(serveOne, kios, data)
		if r == "no_item" or r == "ghost_changed" then
			break
		end
		if type(r) == "string" and r:find("served", 1, true) then
			served = served + 1
		end
		task.wait(Options.ServeJeda.Value * (0.6 + math.random() * 0.8))
	end
	if served > 0 then
		setStatus("[Serve] " .. served .. "x served")
	end
	return served > 0 and "served" or "none"
end

-- ============ PRIORITAS URUTAN ============

-- runner tiap fitur: panggil cycle-nya (selalu return, tak error)
local function runFitur(fitur)
	local r
	if fitur == "Forage" then
		r = pcall(forageCycle)
	elseif fitur == "Tanam" then
		local plots = myPlots()
		if #plots > 0 then
			r = pcall(plantSeed, plots[1])
		else
			r = "no_plot"
		end
	elseif fitur == "Siram" then
		r = pcall(waterPlants)
	elseif fitur == "Panen" then
		r = pcall(harvestPlants)
	elseif fitur == "Potong" then
		r = pcall(cutGagak)
	elseif fitur == "Cook" then
		r = pcall(cookCycle)
	elseif fitur == "Serve" then
		r = pcall(serveCycle)
	end
	setStatus("[Prioritas] " .. fitur .. ": " .. tostring(r))
end

local function fiturOn(fitur)
	local toggleName = FITUR_TOGGLE[fitur]
	if not toggleName then return false end
	local t = Toggles[toggleName]
	return t and t.Value == true
end

-- baca slot 1-6
local function slotUrutan()
	local order = {}
	local seen = {}
	for i = 1, 7 do
		local opt = Options["Slot" .. i]
		local v = opt and opt.Value
		if v and v ~= FITUR_KOSONG and not seen[v] then
			order[#order + 1] = v
			seen[v] = true
		end
	end
	return order
end

-- fitur ON tapi tak masuk slot -> jalan di akhir
local function sisaFitur(order)
	local seen = {}
	for _, f in ipairs(order) do seen[f] = true end
	local sisa = {}
	for _, f in ipairs(FITUR) do
		if not seen[f] and fiturOn(f) then
			sisa[#sisa + 1] = f
		end
	end
	return sisa
end

local prioRunning = false
local prioLoopOn = false
local function mainPrioLoop()
	if prioLoopOn then return end
	prioLoopOn = true
	task.spawn(function()
		while STATE.alive() do
			prioRunning = Toggles.PrioritasUrutan and Toggles.PrioritasUrutan.Value == true
			-- saat prioritas ON, matikan loop existing biar tak tabrakan
			running = not prioRunning and (Toggles.AutoForage and Toggles.AutoForage.Value == true)
			kebunRunning = not prioRunning and ((Toggles.AutoTanam and Toggles.AutoTanam.Value) or (Toggles.AutoSiram and Toggles.AutoSiram.Value) or (Toggles.AutoHarvest and Toggles.AutoHarvest.Value))
			cookRunning = not prioRunning and (Toggles.AutoCook and Toggles.AutoCook.Value == true)
			if prioRunning then
				waitForCharacter()
				local order = slotUrutan()
				-- slot utama
				for _, f in ipairs(order) do
					if not prioRunning or not STATE.alive() then break end
					if fiturOn(f) then
						runFitur(f)
						task.wait(Options.PrioJeda.Value * (0.7 + math.random() * 0.6))
					end
				end
				-- fitur ON yang tak masuk slot, di akhir
				for _, f in ipairs(sisaFitur(order)) do
					if not prioRunning or not STATE.alive() then break end
					runFitur(f)
					task.wait(Options.PrioJeda.Value * (0.7 + math.random() * 0.6))
				end
				-- jeda antar putaran
				setStatus("[Prioritas] putaran selesai, tunggu...")
				task.wait(15 + math.random() * 10)
			end
			task.wait(1)
		end
		prioLoopOn = false
	end)
end

local function syncPrioRunning()
	prioRunning = Toggles.PrioritasUrutan and Toggles.PrioritasUrutan.Value == true
	-- saat prioritas ON, matikan loop existing biar tak tabrakan
	running = prioRunning and false or (Toggles.AutoForage and Toggles.AutoForage.Value == true)
	kebunRunning = prioRunning and false or ((Toggles.AutoTanam and Toggles.AutoTanam.Value) or (Toggles.AutoSiram and Toggles.AutoSiram.Value) or (Toggles.AutoHarvest and Toggles.AutoHarvest.Value))
	cookRunning = prioRunning and false or (Toggles.AutoCook and Toggles.AutoCook.Value == true)
	serveRunning = prioRunning and false or (Toggles.AutoServe and Toggles.AutoServe.Value == true)
end

local antiAfkConn
local function startAntiAfk()
	if antiAfkConn then return end
	antiAfkConn = RunService.Heartbeat:Connect(function()
		if not running or not STATE.alive() then return end
		local char = getCharacter()
		if not char then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hum and hrp and math.random() < 0.004 then
			hum:MoveTo(hrp.Position + Vector3.new((math.random() - 0.5) * 4, 0, (math.random() - 0.5) * 4))
		end
	end)
end

local loopRunning = false
local function mainLoop()
	if loopRunning then return end
	loopRunning = true
	task.spawn(function()
		while STATE.alive() do
			if running then
				setStatus("Foraging... cycle " .. (cycle + 1))
				local picked = forageCycle()
				if picked > 0 then
					cycle = cycle + 1
				end
				setStatus("Cycle " .. cycle .. " done (" .. picked .. " picks) | total: " .. totalPicked)
				if running then
					-- jeda panjang antar cycle (seperti pemain AFK/belok kegiatan)
					setStatus("Jeda " .. Options.CyclePause.Value .. "s...")
					task.wait(Options.CyclePause.Value * (0.7 + math.random() * 0.6))
				end
			else
				setStatus("Status: Idle")
			end
			task.wait(0.5)
		end
		loopRunning = false
	end)
end

-- ============ COOK LOOP ============
local cookRunning = false
local cookLoopOn = false
local function mainCookLoop()
	if cookLoopOn then return end
	cookLoopOn = true
	task.spawn(function()
		while STATE.alive() do
			cookRunning = not prioRunning and Toggles.AutoCook and Toggles.AutoCook.Value == true
			if cookRunning then
				waitForCharacter()
				cookCycle()
			end
			task.wait(1)
		end
		cookLoopOn = false
	end)
end

local function syncCookRunning()
	cookRunning = not prioRunning and Toggles.AutoCook and Toggles.AutoCook.Value == true
end

-- ============ SERVE LOOP ============
local serveRunning = false
local serveLoopOn = false
local function mainServeLoop()
	if serveLoopOn then return end
	serveLoopOn = true
	task.spawn(function()
		while STATE.alive() do
			serveRunning = not prioRunning and Toggles.AutoServe and Toggles.AutoServe.Value == true
			if serveRunning then
				waitForCharacter()
				serveCycle()
			end
			task.wait(1)
		end
		serveLoopOn = false
	end)
end

local function syncServeRunning()
	serveRunning = not prioRunning and Toggles.AutoServe and Toggles.AutoServe.Value == true
end

-- ============ KEBUN LOOP ============
local kebunRunning = false
local kebunLoopOn = false
local function mainKebunLoop()
	if kebunLoopOn then return end
	kebunLoopOn = true
	task.spawn(function()
		while STATE.alive() do
			kebunRunning = not prioRunning and ((Toggles.AutoTanam and Toggles.AutoTanam.Value) or (Toggles.AutoSiram and Toggles.AutoSiram.Value) or (Toggles.AutoHarvest and Toggles.AutoHarvest.Value))
			if kebunRunning then
				waitForCharacter()
				local r = kebunCycle()
				if r and r.tanam then
					setStatus("[Kebun] Tanam: " .. tostring(r.tanam))
				end
				if r and r.siram then
					setStatus("[Kebun] Siram: " .. tostring(r.siram))
				end
				if r and r.panen then
					setStatus("[Kebun] Panen: " .. tostring(r.panen))
				end
			end
			task.wait(1)
		end
		kebunLoopOn = false
	end)
end

local function syncKebunRunning()
	kebunRunning = not prioRunning and ((Toggles.AutoTanam and Toggles.AutoTanam.Value) or (Toggles.AutoSiram and Toggles.AutoSiram.Value) or (Toggles.AutoHarvest and Toggles.AutoHarvest.Value))
end

Toggles.AutoForage:OnChanged(function()
	if prioRunning then
		running = false
		return
	end
	running = Toggles.AutoForage.Value
	if running then
		cycle = 0
		consecutive = 0
		setStatus("Starting forage...")
		Library:Notify({
			Title = "Auto Forage",
			Description = "Mulai mencari bahan...",
			Time = 3,
		})
		waitForCharacter()
		mainLoop()
	else
		setStatus("Status: Idle (stopped)")
		Library:Notify({
			Title = "Auto Forage",
			Description = "Dihentikan. Total: " .. totalPicked .. " bahan",
			Time = 3,
		})
	end
end)

startAntiAfk()
mainLoop()
mainKebunLoop()
mainCookLoop()
mainServeLoop()
mainPrioLoop()

Toggles.AutoTanam:OnChanged(syncKebunRunning)
Toggles.AutoSiram:OnChanged(syncKebunRunning)
Toggles.AutoHarvest:OnChanged(syncKebunRunning)
Toggles.AutoCook:OnChanged(syncCookRunning)
Toggles.AutoServe:OnChanged(syncServeRunning)
Toggles.PrioritasUrutan:OnChanged(syncPrioRunning)
syncKebunRunning()
syncCookRunning()
syncServeRunning()
syncPrioRunning()

STATE.onCleanup(function()
	running = false
	kebunRunning = false
	cookRunning = false
	serveRunning = false
	prioRunning = false
	if antiAfkConn then antiAfkConn:Disconnect() end
	pcall(function() Library:Unload() end)
end)

Library:OnUnload(function()
	running = false
	kebunRunning = false
	cookRunning = false
	serveRunning = false
	prioRunning = false
	if antiAfkConn then antiAfkConn:Disconnect() end
end)
