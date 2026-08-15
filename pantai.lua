--========================================================
-- PANTAI AUTO FISH - OBSIDIAN HUB
-- Game: PANTAI VOICE CHAT (u9506253021)
--========================================================
pcall(function()
	if getgenv().PantaiAutofishCleanup then
		getgenv().PantaiAutofishCleanup()
	end
end)

getgenv().gethui = function()
	return game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
end

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

-- ============================================================
-- SERVICES
-- ============================================================
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local LP = Players.LocalPlayer

-- ============================================================
-- GAME DATA
-- ============================================================
local FishingSystem = RS:WaitForChild("FishingSystem")
local CastRod = FishingSystem:WaitForChild("Events"):WaitForChild("CastRod")
local JualIkanRemote = RS:WaitForChild("JualIkanRemote")
local UpdateInventoryRemote = RS:FindFirstChild("InventorySystem") and RS.InventorySystem:FindFirstChild("InventoryRemotes") and RS.InventorySystem.InventoryRemotes:FindFirstChild("UpdateInventory")

-- ============================================================
-- STATE
-- ============================================================
local running = false
local stats = { casts = 0, catches = 0, fails = 0 }
local fishCount = 0
local lastSell = 0
local sessionStart = os.clock()
local antiAfkEnabled = false
local afkHome = nil
local castHome = nil

-- Track fish from server payloads (reliable), not the GUI
local serverFish = {}
local sellToken = nil

if UpdateInventoryRemote and UpdateInventoryRemote:IsA("RemoteEvent") then
	UpdateInventoryRemote.OnClientEvent:Connect(function(items)
		if type(items) ~= "table" then return end
		local fish = {}
		for _, item in ipairs(items) do
			if type(item) == "table" and item.category == "Fish" then
				table.insert(fish, item.itemName or item.toolId or item.itemId or "")
			end
		end
		serverFish = fish
		fishCount = #fish
	end)
end

-- v8983: server sends a sell token inbound before selling is allowed
if JualIkanRemote and JualIkanRemote:IsA("RemoteEvent") then
	JualIkanRemote.OnClientEvent:Connect(function(action, token)
		if action == "Jualan" and typeof(token) == "string" and token ~= "" then
			sellToken = token
		end
	end)
end

-- ============================================================
-- HELPERS
-- ============================================================
local function getRod()
	local ch = LP.Character
	if ch then
		for _, t in ipairs(ch:GetChildren()) do
			if t:IsA("Tool") and t:FindFirstChild("CastToPosition", true) then
				return t
			end
		end
	end
	for _, t in ipairs(LP.Backpack:GetChildren()) do
		if t:IsA("Tool") and t:FindFirstChild("CastToPosition", true) then
			return t
		end
	end
	return nil
end

local function cast(rod)
	local ctp = rod:FindFirstChild("CastToPosition", true)
	if ctp and ctp:IsA("RemoteEvent") then
		ctp:FireServer(nil)
	else
		CastRod:FireServer(nil, rod.Name)
	end
end

local function getMinigame()
	local mg = LP.PlayerGui:FindFirstChild("MiniGameGUI")
	if not mg or not mg.Enabled then
		return nil
	end
	local bar = mg:FindFirstChild("Bar Attc", true)
	local bd = mg:FindFirstChild("Bar Duration", true)
	if not bar or not bd then
		return nil
	end
	local detec = bar:FindFirstChild("Detec", true)
	local attc = bar:FindFirstChild("Attc", true)
	local barVol = bd:FindFirstChild("BarVol", true)
	if not detec or not attc or not barVol then
		return nil
	end
	return detec, attc, barVol
end

local function waitForBite(timeout)
	local t0 = os.clock()
	while os.clock() - t0 < timeout do
		if getMinigame() then
			return true
		end
		task.wait(0.1)
	end
	return false
end

-- v8983 anti-cheat: track SessionId from inbound Start, send Input events manually
local mgSessionId = nil
local mgRemote = nil

local function hookMinigameRemote(rod)
	mgRemote = rod:FindFirstChild("MiniGame", true)
	if mgRemote and mgRemote:IsA("RemoteEvent") then
		mgRemote.OnClientEvent:Connect(function(action, payload)
			if action == "Start" and type(payload) == "table" and type(payload.SessionId) == "string" then
				mgSessionId = payload.SessionId
			end
		end)
	end
end

local function sendInput(holding)
	if mgRemote and mgRemote:IsA("RemoteEvent") and typeof(mgSessionId) == "string" then
		pcall(function()
			mgRemote:FireServer("Input", { SessionId = mgSessionId, Holding = holding })
		end)
	end
end

local function playMinigame(timeout, snap)
	local t0 = os.clock()
	local peak = 0
	local nilCount = 0
	local holding = false
	local lastToggle = 0
	while os.clock() - t0 < timeout do
		local detec, attc, barVol = getMinigame()
		if not detec then
			nilCount += 1
			if nilCount >= 10 then
				return "done", peak
			end
		else
			nilCount = 0
			if snap then
				-- drive the game's own PlayerClick via real mouse input so it
				-- sends Input events; no direct position writes
				if os.clock() - lastToggle >= 0.1 then
					lastToggle = os.clock()
					local wantHold = detec.Position.X.Scale < attc.Position.X.Scale
					if wantHold ~= holding then
						holding = wantHold
						if holding then
							pcall(function() VirtualUser:Button1Down(Vector2.new(960, 540)) end)
						else
							pcall(function() VirtualUser:Button1Up(Vector2.new(960, 540)) end)
						end
					end
				end
			end
			peak = math.max(peak, barVol.Size.X.Scale)
			if barVol.Size.X.Scale >= 0.999 then
				return "win", peak
			end
		end
		task.wait()
	end
	return "timeout", peak
end

local function countFish()
	-- authoritative source: server GetInventory RemoteFunction
	local rf = FishingSystem:FindFirstChild("Remotes") and FishingSystem.Remotes:FindFirstChild("GetInventory")
	if rf and rf:IsA("RemoteFunction") then
		local ok, res = pcall(function()
			return rf:InvokeServer()
		end)
		if ok and type(res) == "table" then
			local n = 0
			local names = {}
			for _, item in ipairs(res) do
				if type(item) == "table" and (item.Name or item.ModelName or item.itemName) then
					local nm = item.Name or item.ModelName or item.itemName
					if nm ~= "" and (item.Rarity or item.Weight or item.Zone) then
						n += 1
						table.insert(names, tostring(nm) .. " [" .. tostring(item.Weight or "?") .. "Kg]")
					end
				end
			end
			serverFish = names
			fishCount = n
			return n
		end
	end
	-- fallback: GUI
	local n = 0
	local inv = LP.PlayerGui:FindFirstChild("InventoryPantai")
	if inv then
		for _, c in ipairs(inv:GetDescendants()) do
			if c:IsA("TextLabel") and c.Name:find("FishName", 1, true) then
				local t = c.Text
				if not t or not t:find("Slot Name", 1, true) then
					n += 1
				end
			end
		end
	end
	return n
end

local function getCharacter()
	return LP.Character
end

local function teleportTo(pos)
	local ch = getCharacter()
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = CFrame.new(pos)
	end
end

local function getHrpPos()
	local ch = getCharacter()
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	return hrp and hrp.Position or nil
end

local function returnToHome(home)
	local pos = getHrpPos()
	if home and pos and (pos - home).Magnitude > 8 then
		teleportTo(home)
	end
end

local function getSellNPC()
	return workspace:FindFirstChild("SellFish")
end

local function sellFish(kind)
	if LP:GetAttribute("SellFishProcessing") then
		return false, "sell already processing"
	end
	local npc = getSellNPC()
	local ch = getCharacter()
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if not npc or not hrp then
		return false, "no npc or character"
	end
	teleportTo(npc.Position + Vector3.new(0, 1, 0))
	task.wait(0.5)
	local prompt = npc:FindFirstChild("ProximityPrompt")
	if prompt then
		pcall(function() fireproximityprompt(prompt) end)
		-- wait for the inbound sell token (v8983)
		local t0 = os.clock()
		while not sellToken and os.clock() - t0 < 3 do
			task.wait(0.1)
		end
	end
	-- v8983: need the inbound token; prompt interaction should have set it
	local token = sellToken
	sellToken = nil
	if token then
		JualIkanRemote:FireServer(kind, token)
	else
		JualIkanRemote:FireServer(kind)
	end
	lastSell = os.clock()
	return true, token ~= nil
end

local function formatNum(n)
	return tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

-- ============================================================
-- ROD UPGRADE HELPERS
-- ============================================================
local function getOwnedRods()
	local owned = {}
	local function scan(container)
		if not container then return end
		for _, c in ipairs(container:GetChildren()) do
			if c:IsA("Tool") and c:FindFirstChild("CastToPosition", true) then
				owned[c.Name] = true
			end
		end
	end
	scan(LP.Character)
	scan(LP.Backpack)
	-- gamepass/attribute rods
	for k, v in pairs(LP:GetAttributes()) do
		if v and tostring(k):find("^Owns") then
			local name = tostring(k):sub(5)
			if name ~= "" then owned[name] = true end
		end
	end
	return owned
end

local rodPrices = nil
local function getRodPrices()
	if rodPrices then return rodPrices end
	local ok, cfg = pcall(require, FishingSystem:FindFirstChild("FishNRodPriceConfig"))
	if ok and cfg and cfg.Rods then
		rodPrices = {}
		for name, data in pairs(cfg.Rods) do
			if type(data) == "table" and type(data.Price) == "number" then
				rodPrices[name] = data.Price
			end
		end
	end
	return rodPrices or {}
end

local function buyRod(name)
	local part = workspace:FindFirstChild("BuyTool") and workspace.BuyTool:FindFirstChild(name)
	if not part then
		return false, "rod part not found"
	end
	local prompt = part:FindFirstChild("BuyRodInventoryPrompt")
	local ch = getCharacter()
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false, "no character"
	end
	local from = hrp.Position
	teleportTo(part.Position + Vector3.new(0, 1, 0))
	task.wait(0.5)
	if prompt then
		pcall(function() fireproximityprompt(prompt) end)
		task.wait(0.5)
	end
	teleportTo(from)
	return true
end

-- ============================================================
-- WINDOW
-- ============================================================
local Window = Library:CreateWindow({
	Title = "Pantai Auto Fish",
	Footer = "Obsidian",
	Icon = 13208846895,
	NotifySide = "Right",
	ShowCustomCursor = false,
	Resizable = true,
})

local Tabs = {
	Fishing = Window:AddTab("Auto Fish", "fish"),
	Shop = Window:AddTab("Shop", "shopping-bag"),
	Sell = Window:AddTab("Sell", "coins"),
	Teleport = Window:AddTab("Teleport", "map-pin"),
	Misc = Window:AddTab("Misc", "cpu"),
	["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

-- ============================================================
-- AUTO FISH TAB
-- ============================================================
local CtrlGroup = Tabs.Fishing:AddLeftGroupbox("Controls", "crosshair")

CtrlGroup:AddToggle("AutoFish", {
	Text = "Auto Fish",
	Tooltip = "Cast, auto-win minigame, repeat",
	Default = false,
	Risky = true,
})

CtrlGroup:AddToggle("AutoWin", {
	Text = "Auto Win Minigame",
	Tooltip = "Snap the detector onto the target so the bar always fills",
	Default = true,
})

CtrlGroup:AddToggle("AutoSell", {
	Text = "Auto Sell",
	Tooltip = "Sell all fish when the inventory count reaches the threshold",
	Default = false,
})

CtrlGroup:AddToggle("SellWhenFull", {
	Text = "Sell When Bag Full",
	Tooltip = "Auto-sell once the inventory hits 250 slots (overrides threshold)",
	Default = false,
})

CtrlGroup:AddSlider("CastDelay", {
	Text = "Cast Delay (s)",
	Default = 1,
	Min = 0.2,
	Max = 5,
	Rounding = 1,
	Tooltip = "Wait between fishing cycles",
})

CtrlGroup:AddSlider("RecastTimeout", {
	Text = "Recast Timeout (s)",
	Default = 12,
	Min = 3,
	Max = 30,
	Rounding = 0,
	Tooltip = "If no bite within this long, recast",
})

CtrlGroup:AddSlider("MinigameTimeout", {
	Text = "Minigame Timeout (s)",
	Default = 25,
	Min = 5,
	Max = 40,
	Rounding = 0,
	Tooltip = "Abort a minigame that runs too long",
})

CtrlGroup:AddSlider("SellThreshold", {
	Text = "Auto Sell at fish",
	Default = 10,
	Min = 1,
	Max = 50,
	Rounding = 0,
	Tooltip = "Fish count that triggers auto sell",
})

CtrlGroup:AddDivider()

CtrlGroup:AddButton({
	Text = "Cast Now",
	Tooltip = "Cast the equipped rod once",
	Func = function()
		local rod = getRod()
		if not rod then
			Library:Notify({ Title = "Cast", Description = "No rod equipped!", Time = 2 })
			return
		end
		cast(rod)
		stats.casts += 1
	end,
})

local StatusGroup = Tabs.Fishing:AddRightGroupbox("Status", "info")

local StatusRow = StatusGroup:AddLabel("Status: --")
local RodRow = StatusGroup:AddLabel("Rod: --")
local PosRow = StatusGroup:AddLabel("Position: --")
StatusGroup:AddDivider()
local FishRow = StatusGroup:AddLabel("Fish: 0")
local SaldoRow = StatusGroup:AddLabel("Saldo: Rp. 0")
StatusGroup:AddDivider()
local CastsRow = StatusGroup:AddLabel("Casts: 0")
local CatchesRow = StatusGroup:AddLabel("Catches: 0")
local FailsRow = StatusGroup:AddLabel("Fails: 0")
local RateRow = StatusGroup:AddLabel("Rate: 0/min")
local TimeRow = StatusGroup:AddLabel("Session: 0m 0s")

local function refreshStatus()
	local rod = getRod()
	local ch = LP.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	local pos = hrp and hrp.Position or nil
	fishCount = countFish()

	StatusRow:SetText("Status: " .. (running and "RUNNING" or "STOPPED"))
	RodRow:SetText("Rod: " .. (rod and rod.Name or "None"))
	PosRow:SetText(string.format(
		"Position: %s",
		pos and string.format("%d, %d, %d", pos.X, pos.Y, pos.Z) or "?"
	))
	FishRow:SetText("Fish: " .. fishCount)
	SaldoRow:SetText("Saldo: Rp. " .. formatNum(
		LP.leaderstats and LP.leaderstats.Saldo and LP.leaderstats.Saldo.Value or 0
	))

	local elapsed = os.clock() - sessionStart
	local cpm = elapsed > 60 and (stats.catches / (elapsed / 60)) or 0
	CastsRow:SetText("Casts: " .. stats.casts)
	CatchesRow:SetText("Catches: " .. stats.catches)
	FailsRow:SetText("Fails: " .. stats.fails)
	RateRow:SetText(string.format("Rate: %.2f/min", cpm))
	TimeRow:SetText(string.format("Session: %dm %ds", math.floor(elapsed / 60), math.floor(elapsed % 60)))
end

task.spawn(function()
	while not Library.Unloaded do
		refreshStatus()
		task.wait(1)
	end
end)

-- ============================================================
-- SHOP TAB
-- ============================================================
local ShopGroup = Tabs.Shop:AddLeftGroupbox("Buyable Rods", "shopping-bag")

local function getCoinRods()
	local prices = getRodPrices()
	local rods = {}
	for name, price in pairs(prices) do
		if price > 0 then
			table.insert(rods, { name = name, price = price })
		end
	end
	table.sort(rods, function(a, b) return a.price < b.price end)
	return rods
end

local ShopStatus = ShopGroup:AddLabel("Loading...")

local function refreshShop()
	ShopStatus:SetText("Saldo: Rp. " .. formatNum(
		LP.leaderstats and LP.leaderstats.Saldo and LP.leaderstats.Saldo.Value or 0
	))
end

local function addRodButtons()
	for _, rod in ipairs(getCoinRods()) do
		ShopGroup:AddButton({
			Text = rod.name .. "  (Rp. " .. formatNum(rod.price) .. ")",
			Tooltip = "Teleport to the rod and buy it",
			Func = function()
				local owned = getOwnedRods()
				if owned[rod.name] then
					Library:Notify({ Title = "Shop", Description = rod.name .. " already owned!", Time = 2 })
					return
				end
				local ok, err = buyRod(rod.name)
				if ok then
					Library:Notify({ Title = "Shop", Description = "Bought " .. rod.name .. "!", Time = 2 })
				else
					Library:Notify({ Title = "Shop", Description = "Failed: " .. tostring(err), Time = 3 })
				end
				refreshShop()
			end,
		})
	end
end

addRodButtons()
refreshShop()

task.spawn(function()
	while not Library.Unloaded do
		refreshShop()
		task.wait(1)
	end
end)

-- ============================================================
-- SELL TAB
-- ============================================================
local SellGroup = Tabs.Sell:AddLeftGroupbox("Sell", "coins")

SellGroup:AddButton({
	Text = "Sell All Fish",
	Tooltip = "Fire JualIkanRemote with All",
	Func = function()
		local ok = sellFish("All")
		if ok then
			Library:Notify({ Title = "Sell", Description = "Selling all fish...", Time = 2 })
		else
			Library:Notify({ Title = "Sell", Description = "Sell already processing", Time = 2 })
		end
	end,
})

SellGroup:AddButton({
	Text = "Sell Fish in Hand",
	Tooltip = "Fire JualIkanRemote with Hand",
	Func = function()
		local ok = sellFish("Hand")
		if ok then
			Library:Notify({ Title = "Sell", Description = "Selling hand fish...", Time = 2 })
		else
			Library:Notify({ Title = "Sell", Description = "Sell already processing", Time = 2 })
		end
	end,
})

local SellFishRow = SellGroup:AddLabel("Fish: 0")
local SellSaldoRow = SellGroup:AddLabel("Saldo: Rp. 0")

task.spawn(function()
	while not Library.Unloaded do
		SellFishRow:SetText("Fish: " .. countFish())
		SellSaldoRow:SetText("Saldo: Rp. " .. formatNum(
			LP.leaderstats and LP.leaderstats.Saldo and LP.leaderstats.Saldo.Value or 0
		))
		task.wait(1)
	end
end)

-- ============================================================
-- TELEPORT TAB
-- ============================================================
local TpGroup = Tabs.Teleport:AddLeftGroupbox("Locations", "map-pin")

TpGroup:AddButton({
	Text = "Sell NPC",
	Tooltip = "Teleport to the fish seller",
	Func = function()
		local npc = getSellNPC()
		if not npc then
			Library:Notify({ Title = "Teleport", Description = "Sell NPC not found", Time = 2 })
			return
		end
		teleportTo(npc.Position + Vector3.new(0, 1, 0))
		Library:Notify({ Title = "Teleport", Description = "At sell NPC", Time = 2 })
	end,
})

TpGroup:AddButton({
	Text = "Fishing Pier",
	Tooltip = "Teleport to the fishing pier",
	Func = function()
		teleportTo(Vector3.new(1838, 75, -812))
		Library:Notify({ Title = "Teleport", Description = "At fishing pier", Time = 2 })
	end,
})

TpGroup:AddDivider()

TpGroup:AddButton({
	Text = "Rod Shop",
	Tooltip = "Teleport to the rod store",
	Func = function()
		-- BuyTool is a Folder (no Position); use center of the rod parts
		local folder = workspace:FindFirstChild("BuyTool")
		if not folder then
			Library:Notify({ Title = "Teleport", Description = "Rod shop not found", Time = 2 })
			return
		end
		local sum, n = Vector3.new(), 0
		for _, p in ipairs(folder:GetChildren()) do
			if p:IsA("BasePart") then
				sum = sum + p.Position
				n = n + 1
			end
		end
		if n == 0 then
			Library:Notify({ Title = "Teleport", Description = "Rod shop empty", Time = 2 })
			return
		end
		teleportTo(sum / n + Vector3.new(0, 3, 0))
		Library:Notify({ Title = "Teleport", Description = "At rod shop", Time = 2 })
	end,
})

local PlayerGroup = Tabs.Teleport:AddRightGroupbox("Players", "user")

local playerNames = {}
for _, p in ipairs(Players:GetPlayers()) do
	if p ~= LP then table.insert(playerNames, p.Name) end
end
table.sort(playerNames)

local PlayerDropdown = PlayerGroup:AddDropdown("TpPlayer", {
	Values = playerNames,
	Default = 1,
	Text = "Select Player",
	Searchable = true,
	Tooltip = "Player to teleport to",
})

PlayerGroup:AddButton({
	Text = "Teleport to Player",
	Tooltip = "Go to the selected player",
	Func = function()
		local name = Options.TpPlayer and Options.TpPlayer.Value
		if not name then
			Library:Notify({ Title = "Teleport", Description = "No player selected", Time = 2 })
			return
		end
		local target = Players:FindFirstChild(name)
		local hrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
		if not hrp then
			Library:Notify({ Title = "Teleport", Description = name .. " not in server or no character", Time = 2 })
			return
		end
		teleportTo(hrp.Position + Vector3.new(0, 2, 0))
		Library:Notify({ Title = "Teleport", Description = "Teleported to " .. name, Time = 2 })
	end,
})

-- ============================================================
-- MISC TAB
-- ============================================================
local MiscGroup = Tabs.Misc:AddLeftGroupbox("Utility", "wrench")

MiscGroup:AddToggle("AntiAfk", {
	Text = "Anti AFK",
	Tooltip = "Prevent kicked for inactivity (virtual input every 20-40s)",
	Default = false,
	Callback = function(state)
		antiAfkEnabled = state
		if state then
			afkHome = getHrpPos() or afkHome
			task.spawn(function()
				while antiAfkEnabled and not Library.Unloaded do
					task.wait(math.random(20, 40))
					pcall(function()
						VirtualUser:CaptureController()
						VirtualUser:ClickButton2(Vector2.new(math.random(100, 700), math.random(100, 500)))
					end)
					returnToHome(afkHome)
				end
			end)
		end
	end,
})

MiscGroup:AddDivider()

local FPSGroup = Tabs.Misc:AddRightGroupbox("Performance", "settings")

local fpsBoostObjects = {}
FPSGroup:AddToggle("FPSBoost", {
	Text = "FPS Boost",
	Tooltip = "Disable shadows, particles and effects",
	Default = false,
	Callback = function(state)
		if state then
			settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
			pcall(function()
				local Lighting = game:GetService("Lighting")
				Lighting.GlobalShadows = false
				Lighting.FogEnd = 9e9
				Lighting.Brightness = 1
			end)
			local Terrain = workspace:FindFirstChildOfClass("Terrain")
			if Terrain then
				pcall(function()
					Terrain.WaterWaveSize = 0
					Terrain.WaterWaveSpeed = 0
					Terrain.WaterReflectance = 0
					Terrain.WaterTransparency = 1
				end)
			end
			for _, v in ipairs(workspace:GetDescendants()) do
				if v:IsA("BasePart") then
					table.insert(fpsBoostObjects, { obj = v, prop = "CastShadow", old = v.CastShadow })
					v.CastShadow = false
				elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") then
					table.insert(fpsBoostObjects, { obj = v, prop = "Enabled", old = v.Enabled })
					v.Enabled = false
				end
			end
			Library:Notify({ Title = "FPS", Description = "FPS Boost enabled", Time = 2 })
		else
			for _, entry in ipairs(fpsBoostObjects) do
				pcall(function() entry.obj[entry.prop] = entry.old end)
			end
			fpsBoostObjects = {}
			settings().Rendering.QualityLevel = Enum.QualityLevel.Level10
			Library:Notify({ Title = "FPS", Description = "FPS Boost disabled", Time = 2 })
		end
	end,
})

-- ============================================================
-- AUTO FISH LOOP
-- ============================================================
Toggles.AutoFish:OnChanged(function()
	running = Toggles.AutoFish.Value
	if running then
		Library:Notify({ Title = "Auto Fish", Description = "Started!", Time = 2 })
		task.spawn(function()
			while running and not Library.Unloaded do
				local rod = getRod()
				if not rod then
					task.wait(3)
				else
				hookMinigameRemote(rod)
				if Toggles.AutoSell.Value
					and (Toggles.SellWhenFull.Value and countFish() >= 250 or (not Toggles.SellWhenFull.Value and countFish() >= Options.SellThreshold.Value))
					and os.clock() - lastSell > 15 and not LP:GetAttribute("SellFishProcessing") then
					local ch = getCharacter()
					local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
					local fishPos = hrp and hrp.Position
					Library:Notify({ Title = "Auto Sell", Description = "Teleporting to sell NPC...", Time = 2 })
					task.spawn(function()
						local ok, err = sellFish("All")
						if not ok then
							Library:Notify({ Title = "Auto Sell", Description = "Failed: " .. tostring(err), Time = 3 })
						end
						task.wait(1.5)
						if fishPos then
							teleportTo(fishPos)
						end
					end)
					task.wait(4)
				end

					if not castHome then
						castHome = getHrpPos() or castHome
					end

					stats.casts += 1
					cast(rod)

					local bit = waitForBite(Options.RecastTimeout.Value)
					if not bit then
						stats.fails += 1
					else
						local result = playMinigame(Options.MinigameTimeout.Value, Toggles.AutoWin.Value)
						if result == "win" then
							task.wait(0.8)
							stats.catches += 1
						else
							stats.fails += 1
						end
						-- Button1Down drifts the character toward the camera; pull back
						returnToHome(castHome)
					end
					task.wait(Options.CastDelay.Value)
				end
			end
		end)
	else
		Library:Notify({ Title = "Auto Fish", Description = "Stopped", Time = 2 })
	end
end)

-- ============================================================
-- UI SETTINGS
-- ============================================================
local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu", "wrench")

MenuGroup:AddToggle("KeybindMenuOpen", {
	Text = "Open Keybind Menu",
	Default = Library.KeybindFrame.Visible,
	Callback = function(value)
		Library.KeybindFrame.Visible = value
	end,
})

MenuGroup:AddDivider()

MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
	Default = "RightShift",
	NoUI = true,
	Text = "Menu keybind",
})

Library.ToggleKeybind = Options.MenuKeybind

MenuGroup:AddDivider()

MenuGroup:AddButton({
	Text = "Unload",
	Func = function()
		Library:Unload()
	end,
})

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("PantaiObsidian")
SaveManager:SetFolder("PantaiObsidian")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])

SaveManager:LoadAutoloadConfig()

-- ============================================================
-- CLEANUP
-- ============================================================
Library:OnUnload(function()
	running = false
	antiAfkEnabled = false
	for _, entry in ipairs(fpsBoostObjects) do
		pcall(function() entry.obj[entry.prop] = entry.old end)
	end
	fpsBoostObjects = {}
	pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level10 end)
	getgenv().PantaiAutofishCleanup = nil
end)

getgenv().PantaiAutofishCleanup = function()
	pcall(function() Library:Unload() end)
end

print("[Pantai Auto Fish] Obsidian Hub loaded! RightShift to toggle GUI.")
