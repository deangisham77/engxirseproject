--========================================================
-- STORAGE HUNTERS OPEN WORLD - OBSIDIAN HUB V8
-- v8: removed Auto-Decline Out-of-Range (decline remote bridged nothing visible & NPC stayed; behavior reverted to leave-pending)
-- v7: Auto-Decline out-of-range offers + floor ghost cleanup (decline removed in v8)
-- v6: Auto-Accept Offers range 0%..500% (Min+Max sliders)
-- v5: Museum tab (Place 140): GetState / Donate / Withdraw / Collect / UnlockSlot
-- Auto Farm reliability from v4. Backup: …-v4.backup-*-museum-pre.lua
--========================================================
pcall(function()
	if getgenv().StorageHuntersObsidianCleanup then
		getgenv().StorageHuntersObsidianCleanup()
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

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local LP = Players.LocalPlayer

local Events = RS:WaitForChild("Events", 10)

local function remote(folderName, remoteName)
	if not Events then
		return nil
	end
	local folder = Events:FindFirstChild(folderName) or Events:WaitForChild(folderName, 5)
	if not folder then
		return nil
	end
	return folder:FindFirstChild(remoteName) or folder:WaitForChild(remoteName, 5)
end

local notifiedRemotes = {}
local function notifyMissingRemote(key)
	if notifiedRemotes[key] then
		return
	end
	notifiedRemotes[key] = true
	pcall(function()
		Library:Notify({ Title = "Remote", Description = "missing " .. key, Time = 4 })
	end)
end

local function fire(folderName, remoteName, ...)
	local r = remote(folderName, remoteName)
	if not r then
		local key = folderName .. "." .. remoteName
		notifyMissingRemote(key)
		return false, "missing " .. key
	end
	local args = { ... }
	local ok, err = pcall(function()
		r:FireServer(table.unpack(args))
	end)
	return ok, err
end

local function invoke(folderName, remoteName, ...)
	local r = remote(folderName, remoteName)
	if not r then
		local key = folderName .. "." .. remoteName
		notifyMissingRemote(key)
		return nil, "missing " .. key
	end
	local args = { ... }
	local ok, result = pcall(function()
		return r:InvokeServer(table.unpack(args))
	end)
	if not ok then
		return nil, result
	end
	return result
end

local state = {
	antiAfk = false,
	autoBid = false,
	maxBid = 0,
	autoFarm = false,
	autoCollectAuction = false,
	auctionPickupPhase = false,
	farmPhase = "idle", -- idle|travel|enter|bid|collect|leave
	farmGarage = nil,
	farmGarageGuid = nil,
	farmEnteredAt = 0,
	farmBidStartedAt = 0,
	farmCollectStartedAt = 0,
	farmLastLeaveAt = 0,
	farmWasInAuction = false,
	farmPendingLeave = false,
	farmAuctionEndedAt = 0,
	farmCollectNoPickStreak = 0,
	farmCooldownUntil = {}, -- [guid] = os.clock() when free again
	maxEntryCost = 0, -- 0 = no limit
	prioritizeNearest = false,
	garageFilter = {},
	autoAccept = false,
	-- absolute % of base value (same as GameConfig.Staff MinOfferPercent): 100 = fair, 105 = +5%
	-- v6: accept range [minAcceptPct .. maxAcceptPct], default 0..500
	-- v7→v8: auto-decline removed (not working); floor ghost cleanup kept
	minAcceptPct = 0,
	maxAcceptPct = 500,
	autoPickupGhosts = false,
	autoUnload = false,
	autoCollect = false,
	autoLostFound = false,
	autoPlace = false,
	autoWash = false,
	autoGrade = false,
	autoPawnSell = false,
	pawnSkipRarities = {},
	pawnMinPrice = 0,
	stockPriceMult = 1,
	pauseOnFull = true,
	pauseAtPct = 90,
	resumeBelow = 10,
	excludeCategories = {},
	excludeRarities = {},
	gradeRarities = {},
	autoMuseumCollect = false,
	running = true,
}

-- v202: PlaceStockItem confirms via PlaceStockItemResult(requestGUID, ok)
-- track inflight so loop doesn't stack listings on unconfirmed slots
local connections = {}
local function track(conn)
	table.insert(connections, conn)
	return conn
end
local placePending = {}
task.spawn(function()
	local rp = remote("Plot", "PlaceStockItemResult")
	if rp then
		track(rp.OnClientEvent:Connect(function(req, okFlag)
			if type(req) == "string" then
				placePending[req] = nil
			end
		end))
	end
	task.wait(20)
	-- clear stale every 20s
	while state.running do
		task.wait(20)
		for k in pairs(placePending) do
			placePending[k] = nil
		end
	end
end)

local Window = Library:CreateWindow({
	Title = "Storage Hunters",
	Footer = "Qentury Hub v8 · Offers/Ghosts",
	NotifySide = "Right",
	ShowCustomCursor = false,
	Center = true,
	Resizable = true,
	-- compact default (mobile-friendly); still resizable
	Size = UDim2.fromOffset(420, 380),
	MinContainerWidth = 280,
	SidebarCompacted = true,
	EnableCompacting = true,
	ShowMobileButtons = true,
	MobileButtonsSide = "Right",
})

local Tabs = {
	Auction = Window:AddTab("Auction", "gavel"),
	Collect = Window:AddTab("Collect", "package"),
	Sell = Window:AddTab("Sell", "coins"),
	AutoPlace = Window:AddTab("AutoPlace", "box"),
	Grading = Window:AddTab("Grading", "award"),
	Museum = Window:AddTab("Museum", "landmark"),
	Teleport = Window:AddTab("Teleport", "map-pin"),
	Inventory = Window:AddTab("Inventory", "backpack"),
	Misc = Window:AddTab("Misc", "settings"),
	["UI Settings"] = Window:AddTab("UI Settings", "wrench"),
}

-- full-width column (all groupboxes on left side only)
local function addBox(tab, name, icon)
	return tab:AddLeftGroupbox(name, icon)
end

-- Qentury-style: hide right column, stretch left to full width
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
	for _ = 1, 24 do
		task.wait(0.2)
		if Library.Unloaded then
			break
		end
		forceFullWidthTabs()
	end
	while not Library.Unloaded and state.running do
		task.wait(1)
		forceFullWidthTabs()
	end
end)

task.defer(function()
	task.wait(0.35)
	forceFullWidthTabs()
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
end)

-- Teleport helpers
local function getHRP()
	local char = LP.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function getSeatedVehicle()
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if seat and seat:IsA("VehicleSeat") then
		return seat:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function teleportTo(cf)
	local hrp = getHRP()
	if not hrp then
		Library:Notify({ Title = "TP", Description = "No character", Time = 2 })
		return
	end
	local vehicle = getSeatedVehicle()
	if vehicle then
		if not vehicle.PrimaryPart then
			local part = vehicle:FindFirstChildWhichIsA("BasePart", true)
			if part then
				pcall(function()
					vehicle.PrimaryPart = part
				end)
			end
		end
		if vehicle.PrimaryPart then
			vehicle:PivotTo(cf)
			return
		end
	end
	hrp.CFrame = cf
end

local function getMyPlot()
	local plots = workspace:FindFirstChild("_Plots")
	if not plots then
		return nil
	end
	for _, plot in ipairs(plots:GetChildren()) do
		if plot:GetAttribute("OwnerUserId") == LP.UserId then
			return plot
		end
	end
	return nil
end

local function getOwnedPlotCFrame()
	local plots = workspace:FindFirstChild("_Plots")
	if not plots then
		return nil
	end
	for _, plot in ipairs(plots:GetChildren()) do
		if plot:GetAttribute("OwnerUserId") == LP.UserId then
			local ox = plot:GetAttribute("OriginX")
			local oy = plot:GetAttribute("OriginY")
			local oz = plot:GetAttribute("OriginZ")
			if typeof(ox) == "number" and typeof(oy) == "number" and typeof(oz) == "number" then
				return CFrame.new(ox, oy + 5, oz)
			end
		end
	end
	return nil
end

-- GPS.GetPOIs + SpawnLocation (place 98800969324557) — see docs/superpowers/notes/storage-hunters-discovery.md
local TP_POINTS = {
	Base = CFrame.new(-13, 1722, 52),
	JunkYard = CFrame.new(19.876174926757812, 1720, -24.290977478027344),
	BackAlley = CFrame.new(-571.18017578125, 1720, -399.95452880859375),
	FarmYard = CFrame.new(-78.5224609375, 1720, -1148.022216796875),
	ShipYard = CFrame.new(-550.9900512695312, 1720, 698.2243041992188),
	Mall = CFrame.new(346.7200012207031, 1720, -172.73672485351562),
	ItemCleaning = CFrame.new(440.5322265625, 1722, -277.263671875),
	CarGarage = CFrame.new(-72.56291198730469, 1722, 237.34637451171875),
	Museum = CFrame.new(506.39321899414, 1728, -185.03215026855),
}

local TpBox = addBox(Tabs.Teleport, "Teleport", "map-pin")
TpBox:AddLabel("If seated in truck, vehicle TPs with you", true)
	TpBox:AddButton({
	Text = "TP base",
	Func = function()
		local plotCf = getOwnedPlotCFrame()
		if plotCf then
			teleportTo(plotCf)
			return
		end
		local hrp = getHRP()
		local before = hrp and hrp.Position
		local remoteOk = false
		pcall(function()
			local r = remote("Plot", "TeleportToPlot")
			if r then
				r:FireServer()
				remoteOk = true
			end
		end)
		if remoteOk and before then
			task.wait(0.5)
			local afterHrp = getHRP()
			local after = afterHrp and afterHrp.Position
			local moved = after and (after - before).Magnitude > 5
			local owned = getOwnedPlotCFrame()
			if moved or owned then
				if owned and not moved then
					teleportTo(owned)
				end
				return
			end
		end
		local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
		if spawn then
			teleportTo(spawn.CFrame + Vector3.new(0, 5, 0))
		else
			teleportTo(TP_POINTS.Base)
		end
	end,
})
local ZoneBox = addBox(Tabs.Teleport, "Zones", "map")
for _, key in ipairs({ "JunkYard", "BackAlley", "FarmYard", "ShipYard" }) do
	ZoneBox:AddButton({
		Text = "TP " .. key,
		Func = function()
			teleportTo(TP_POINTS[key])
		end,
	})
end
local ShopBox = addBox(Tabs.Teleport, "Shops", "store")
for _, key in ipairs({ "Mall", "ItemCleaning", "CarGarage", "Museum" }) do
	ShopBox:AddButton({
		Text = "TP " .. key,
		Func = function()
			teleportTo(TP_POINTS[key])
		end,
	})
end

-- P4: dynamic GPS POIs (all areas + shops)
local gpsPoiMap = {} -- name -> CFrame
local gpsPoiNames = {}

local function refreshGpsPois()
	table.clear(gpsPoiMap)
	table.clear(gpsPoiNames)
	local res = invoke("GPS", "GetPOIs")
	local list = res and (res.pois or res)
	if type(list) ~= "table" then
		return 0
	end
	for _, p in ipairs(list) do
		if type(p) == "table" then
			local name = p.Name or p.name
			local pos = p.Position or p.position or p.Pos
			if type(name) == "string" and name ~= "" and typeof(pos) == "Vector3" then
				gpsPoiMap[name] = CFrame.new(pos.X, pos.Y + 3, pos.Z)
				table.insert(gpsPoiNames, name)
			end
		end
	end
	table.sort(gpsPoiNames)
	return #gpsPoiNames
end

refreshGpsPois()

local GpsBox = addBox(Tabs.Teleport, "GPS All", "navigation")
GpsBox:AddDropdown("GpsPoiSelect", {
	Text = "Destination",
	Values = #gpsPoiNames > 0 and gpsPoiNames or { "(none)" },
	Default = 1,
	Searchable = true,
})
GpsBox:AddButton({
	Text = "TP Selected GPS",
	Func = function()
		local name = Options.GpsPoiSelect and Options.GpsPoiSelect.Value
		local cf = name and gpsPoiMap[name]
		if cf then
			teleportTo(cf)
		else
			Library:Notify({ Title = "GPS", Description = "No POI selected", Time = 2 })
		end
	end,
})
GpsBox:AddButton({
	Text = "Refresh GPS List",
	Func = function()
		local n = refreshGpsPois()
		if Options.GpsPoiSelect and Options.GpsPoiSelect.SetValues then
			Options.GpsPoiSelect:SetValues(gpsPoiNames)
		end
		Library:Notify({ Title = "GPS", Description = n .. " POIs", Time = 2 })
	end,
})

-- Auction bid UI (UIControllerGui.AuctionBiddingContainer + SetBidPrice)
local cachedNextBid = 0
local cachedCurrentBid = 0
local bidModRef = nil
local originalSetBidPrice = nil
pcall(function()
	local screens = RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("Screens")
	local bidMod = screens and screens:FindFirstChild("AuctionBidding")
	if not bidMod then
		return
	end
	local mod = require(bidMod)
	if type(mod) ~= "table" or type(mod.SetBidPrice) ~= "function" then
		return
	end
	bidModRef = mod
	originalSetBidPrice = mod.SetBidPrice
	mod.SetBidPrice = function(self, nextPrice, currentPrice, ...)
		cachedNextBid = tonumber(nextPrice) or 0
		if currentPrice ~= nil then
			cachedCurrentBid = tonumber(currentPrice) or 0
		end
		return originalSetBidPrice(self, nextPrice, currentPrice, ...)
	end
end)

local function getAuctionBidContainer()
	local gui = LP.PlayerGui:FindFirstChild("UIControllerGui")
	return gui and gui:FindFirstChild("AuctionBiddingContainer")
end

local function isBidUiOpen()
	local container = getAuctionBidContainer()
	if not container or not container.Visible then
		return false
	end
	local bar = container:FindFirstChild("BidBarRow")
	return bar == nil or bar.Visible
end

local function parseMoneyFromLabel(text)
	if type(text) ~= "string" or text == "" then
		return nil
	end
	local upper = string.upper(text)
	local nextAmt = upper:match("NEXT%s*%$([%d,%.]+)")
	if not nextAmt then
		nextAmt = upper:match("%$([%d,%.]+)")
	end
	if not nextAmt then
		return nil
	end
	return tonumber((nextAmt:gsub(",", "")))
end

local function currentBidPrice()
	if not isBidUiOpen() then
		cachedNextBid = 0
		cachedCurrentBid = 0
		return 0
	end
	local container = getAuctionBidContainer()
	local label = container and container:FindFirstChild("BidPriceLabel")
	local fromLabel = parseMoneyFromLabel(label and label.Text)
	if fromLabel and fromLabel > 0 then
		return fromLabel
	end
	return cachedNextBid
end

-- Entry fees from Modules.Garages (Min); live attr EntryCost matches
local GARAGE_ENTRY_COST = {
	["Scrap Garage 2"] = 0,
	["Scrap Garage 3"] = 0,
	["Shop Front"] = 5,
	["Camo Shop Front"] = 10,
	["Wooden Cargo Container"] = 10,
	["Stable Garage"] = 15,
	["Jurassic Stable Garage"] = 15,
	["Barn Garage"] = 25,
	["Jurassic Barn Garage"] = 25,
	["Cargo Container"] = 50,
	["Small Container Garage"] = 50,
	["Steel Cargo Container"] = 75,
	["Large Container Garage"] = 100,
	["Luxury Cargo Container"] = 100,
	["Warehouse Garage"] = 200,
	["Beach Hut Garage"] = 300,
	["Surf Shack Garage"] = 450,
	["Boat House Garage"] = 650,
}

local GARAGE_IDS = {
	"Scrap Garage 2",
	"Scrap Garage 3",
	"Shop Front",
	"Camo Shop Front",
	"Wooden Cargo Container",
	"Stable Garage",
	"Jurassic Stable Garage",
	"Barn Garage",
	"Jurassic Barn Garage",
	"Cargo Container",
	"Small Container Garage",
	"Steel Cargo Container",
	"Large Container Garage",
	"Luxury Cargo Container",
	"Warehouse Garage",
	"Beach Hut Garage",
	"Surf Shack Garage",
	"Boat House Garage",
}

local function formatMoneyShort(n)
	n = tonumber(n) or 0
	if n >= 1000 then
		return string.format("$%s", tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
	end
	return "$" .. tostring(n)
end

local function garageDropdownLabel(id)
	local cost = GARAGE_ENTRY_COST[id]
	if cost == nil then
		return id
	end
	return string.format("%s · %s", id, formatMoneyShort(cost))
end

local GARAGE_TYPES = {}
local GARAGE_LABEL_TO_ID = {}
for _, id in ipairs(GARAGE_IDS) do
	local label = garageDropdownLabel(id)
	table.insert(GARAGE_TYPES, label)
	GARAGE_LABEL_TO_ID[label] = id
	GARAGE_LABEL_TO_ID[id] = id
end

local function resolveGarageId(labelOrId)
	if type(labelOrId) ~= "string" then
		return nil
	end
	if GARAGE_LABEL_TO_ID[labelOrId] then
		return GARAGE_LABEL_TO_ID[labelOrId]
	end
	local base = string.match(labelOrId, "^(.-) · %$")
	return base or labelOrId
end

local AuctionBox = addBox(Tabs.Auction, "Bidding", "gavel")
AuctionBox:AddToggle("AutoBid", { Text = "Auto-Bid", Default = false })
AuctionBox:AddSlider("MaxBid", {
	Text = "Max Bid",
	Default = 0,
	Min = 0,
	Max = 1000000,
	Rounding = 0,
	Tooltip = "0 = no limit",
})
AuctionBox:AddDropdown("GarageTypes", {
	Text = "Garage Types (entry fee)",
	Values = GARAGE_TYPES,
	Multi = true,
	Default = {},
	Searchable = true,
	MaxVisibleDropdownItems = 12,
	Tooltip = "Labels show entry cost · filter by GarageId",
})
AuctionBox:AddToggle("PrioritizeNearest", {
	Text = "Prioritize Nearest to Vehicle",
	Default = false,
})
AuctionBox:AddToggle("AutoFarm", {
	Text = "Auto Farm (Full Loop)",
	Default = false,
	Tooltip = "TP selected garage → Start Auction → Auto Bid (toggle) → wait end → next. No loot pickup (→ L&F).",
})
AuctionBox:AddSlider("MaxEntryCost", {
	Text = "Max Entry Cost",
	Default = 0,
	Min = 0,
	Max = 50000,
	Rounding = 0,
	Tooltip = "0 = any fee; skip garages with higher EntryCost",
})
AuctionBox:AddToggle("AutoCollectAuction", {
	Text = "Auto Collect Auction",
	Default = false,
	Tooltip = "Pick Owner=you loot in _Carryables → goes into EquippedVehicle cargo (not inventory).",
})
AuctionBox:AddLabel(
	"Farm: idle · End signals: YOU WON / BidUI close / InAuction=false",
	true,
	"FarmPhaseLabel"
)

Toggles.AutoBid:OnChanged(function()
	state.autoBid = Toggles.AutoBid.Value
end)
Options.MaxBid:OnChanged(function()
	state.maxBid = Options.MaxBid.Value
end)
Options.GarageTypes:OnChanged(function()
	syncGarageFilterFromUI()
end)
Toggles.PrioritizeNearest:OnChanged(function()
	state.prioritizeNearest = Toggles.PrioritizeNearest.Value
end)
local function clearFarmCooldowns()
	if type(state.farmCooldownUntil) ~= "table" then
		state.farmCooldownUntil = {}
		return
	end
	for k in pairs(state.farmCooldownUntil) do
		state.farmCooldownUntil[k] = nil
	end
end

local function syncGarageFilterFromUI()
	local v = Options.GarageTypes and Options.GarageTypes.Value
	local norm = {}
	if type(v) == "table" then
		for k, val in pairs(v) do
			if val == true and type(k) == "string" then
				norm[resolveGarageId(k) or k] = true
			elseif type(val) == "string" then
				norm[resolveGarageId(val) or val] = true
			end
		end
	end
	state.garageFilter = norm
	return norm
end

Toggles.AutoFarm:OnChanged(function()
	state.autoFarm = Toggles.AutoFarm.Value
	if not state.autoFarm then
		state.farmPhase = "idle"
		state.farmGarage = nil
		state.farmWasInAuction = false
		state.farmPendingLeave = false
		pcall(function()
			if Options.FarmPhaseLabel then
				Options.FarmPhaseLabel:SetText("Farm: OFF")
			end
		end)
	else
		clearFarmCooldowns()
		syncGarageFilterFromUI()
		state.maxEntryCost = (Options.MaxEntryCost and Options.MaxEntryCost.Value) or 0
		state.farmPhase = "idle"
		state.farmGarage = nil
		state.farmWasInAuction = false
		state.farmPendingLeave = false
		state.farmAuctionEndedAt = 0
		state.farmBidQuietSince = nil
		state.farmStatus = "starting…"
		state.running = true
		-- Auto Bid handles bidding (user flow)
		state.autoBid = true
		if Toggles.AutoBid and not Toggles.AutoBid.Value then
			Toggles.AutoBid:SetValue(true)
		end
		pcall(function()
			if Options.FarmPhaseLabel then
				Options.FarmPhaseLabel:SetText("Farm: starting…")
			end
		end)
		Library:Notify({
			Title = "Auto Farm",
			Description = "TP → Start → Auto Bid → wait end → next",
			Time = 2.5,
		})
	end
end)
Options.MaxEntryCost:OnChanged(function()
	state.maxEntryCost = Options.MaxEntryCost.Value or 0
end)
Toggles.AutoCollectAuction:OnChanged(function()
	state.autoCollectAuction = Toggles.AutoCollectAuction.Value
end)

do
	-- Official end indicators from game:
	-- AuctionPickupStart = YOU WON (pickup HUD)  |  AuctionPickupEnd = pickup done
	-- ToggleBiddingUI(false) = bid UI closed     |  InAuction attr false
	local function markAuctionEnded(reason)
		if state.farmPendingLeave and state.farmPhase == "leave" then
			return
		end
		state.farmAuctionEndedAt = os.clock()
		state.farmPendingLeave = true
		state.farmStatus = reason or "auction ended"
		-- FORCE phase leave so farm loop hops next garage (don't wait bid-loop edge cases)
		if state.autoFarm then
			state.farmPhase = "leave"
			state.farmStatus = reason or "ended"
		end
		pcall(function()
			if Options.FarmPhaseLabel then
				Options.FarmPhaseLabel:SetText("Farm: ENDED · " .. tostring(reason or "done"))
			end
		end)
		pcall(function()
			Library:Notify({
				Title = "Auction ended",
				Description = tostring(reason or "done") .. " → next",
				Time = 2.5,
			})
		end)
	end

	local startR = remote("Auction", "AuctionPickupStart")
	if startR then
		track(startR.OnClientEvent:Connect(function()
			state.auctionPickupPhase = true
			local ph = state.farmPhase
			if state.autoFarm and (ph == "bid" or ph == "wait" or ph == "enter" or ph == "collect") then
				markAuctionEnded("YOU WON")
			end
		end))
	end
	local endR = remote("Auction", "AuctionPickupEnd")
	if endR then
		track(endR.OnClientEvent:Connect(function()
			state.auctionPickupPhase = false
			local ph = state.farmPhase
			if state.autoFarm and (ph == "bid" or ph == "wait" or ph == "collect") then
				markAuctionEnded("PickupEnd")
			end
		end))
	end
	local toggleBid = remote("Auction", "ToggleBiddingUI")
	if toggleBid then
		track(toggleBid.OnClientEvent:Connect(function(open)
			if open == false or open == nil then
				local ph = state.farmPhase
				if state.autoFarm
					and (ph == "bid" or ph == "wait")
					and state.farmWasInAuction
					and (os.clock() - (state.farmBidStartedAt or 0)) > 10
					and not state.farmPendingLeave
				then
					markAuctionEnded("Bid UI closed")
				end
			end
		end))
	end
	track(LP:GetAttributeChangedSignal("InAuction"):Connect(function()
		if LP:GetAttribute("InAuction") == true then
			return
		end
		local ph = state.farmPhase
		if state.autoFarm
			and (ph == "bid" or ph == "wait" or ph == "collect")
			and state.farmWasInAuction
			and (os.clock() - (state.farmBidStartedAt or 0)) > 6
		then
			markAuctionEnded("InAuction=false")
		end
	end))
end

-- Server may require player in auction slider zone for Bid to accept.
local function tryClickBidButton()
	local container = getAuctionBidContainer()
	if not container then
		return false
	end
	local btn = container:FindFirstChild("BidButton", true)
		or container:FindFirstChild("Bid", true)
		or container:FindFirstChild("ConfirmBid", true)
	if not btn then
		for _, d in ipairs(container:GetDescendants()) do
			if d:IsA("GuiButton") and string.find(string.lower(d.Name), "bid", 1, true) then
				btn = d
				break
			end
		end
	end
	if not btn then
		return false
	end
	return pcall(function()
		if typeof(firesignal) == "function" then
			pcall(function()
				firesignal(btn.Activated)
			end)
			pcall(function()
				firesignal(btn.MouseButton1Click)
			end)
		end
		if type(btn.Activate) == "function" then
			btn:Activate()
		end
	end)
end

task.spawn(function()
	while state.running do
		if state.autoBid and isBidUiOpen() then
			local price = currentBidPrice()
			local cash = LP:GetAttribute("Cash") or 0
			local underMax = state.maxBid <= 0 or price <= state.maxBid
			if underMax and cash >= price and price > 0 then
				fire("Auction", "Bid")
				pcall(tryClickBidButton)
				task.wait(0.35)
			end
		end
		task.wait(0.15)
	end
end)

local function garageFilterActive()
	local f = state.garageFilter
	if type(f) ~= "table" then
		return false
	end
	for _, v in pairs(f) do
		if v == true or (type(v) == "string" and v ~= "") then
			return true
		end
	end
	return false
end

local function garageTypeAllowed(garageId)
	if not garageFilterActive() then
		return true
	end
	local f = state.garageFilter
	if f[garageId] == true then
		return true
	end
	-- multi dropdown may store label "Name · $fee" as key or value
	for k, v in pairs(f) do
		if v == true then
			local id = resolveGarageId(k)
			if id == garageId then
				return true
			end
		elseif type(v) == "string" then
			if resolveGarageId(v) == garageId or v == garageId then
				return true
			end
		end
	end
	return false
end

local function getFarmOriginPosition()
	local vehicle = getSeatedVehicle()
	if vehicle then
		local pp = vehicle.PrimaryPart or vehicle:FindFirstChildWhichIsA("BasePart", true)
		if pp then
			return pp.Position
		end
	end
	local hrp = getHRP()
	return hrp and hrp.Position or nil
end

local function garageAuctionCFrame(garage)
	local zone = garage:FindFirstChild("AuctionZone")
	if zone and zone:IsA("BasePart") then
		return zone.CFrame
	end
	local base = garage:FindFirstChild("Base")
	if base and base:IsA("BasePart") then
		return base.CFrame
	end
	local part = garage:FindFirstChildWhichIsA("BasePart", true)
	return part and part.CFrame or nil
end

local function entryCostAllowed(garage)
	local cost = tonumber(garage:GetAttribute("EntryCost")) or 0
	if state.maxEntryCost > 0 and cost > state.maxEntryCost then
		return false
	end
	local cash = LP:GetAttribute("Cash") or 0
	if cost > cash then
		return false
	end
	return true
end

local function findEnterAuctionPrompt(garage)
	if not garage then
		return nil
	end
	for _, d in ipairs(garage:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "EnterAuction" and d.Enabled ~= false then
			return d
		end
	end
	for _, d in ipairs(garage:GetDescendants()) do
		if d:IsA("ProximityPrompt") and string.find(string.lower(d.ActionText or ""), "auction", 1, true) then
			return d
		end
	end
	return nil
end

local function garageCooldownKey(garage)
	if not garage then
		return nil
	end
	return garage:GetAttribute("GUID") or garage:GetFullName()
end

local function isGarageOnCooldown(garage)
	local key = garageCooldownKey(garage)
	if not key then
		return false
	end
	local untilT = state.farmCooldownUntil[key]
	if not untilT then
		return false
	end
	if os.clock() < untilT then
		return true
	end
	state.farmCooldownUntil[key] = nil
	return false
end

local function cooldownGarage(garage, seconds)
	local key = garageCooldownKey(garage)
	if key then
		state.farmCooldownUntil[key] = os.clock() + (seconds or 25)
	end
end

-- Idle with EnterAuction = START; live with zone = JOIN (prompt often missing when live)
local function findMatchingAuction()
	local folder = workspace:FindFirstChild("_Debris")
	folder = folder and folder:FindFirstChild("Garages")
	if not folder then
		state.farmStatus = "no Garages folder"
		return nil
	end
	local origin = getFarmOriginPosition()
	local startable, joinable = {}, {}
	for _, garage in ipairs(folder:GetChildren()) do
		if not isGarageOnCooldown(garage) then
			local garageType = garage:GetAttribute("GarageId") or garage.Name
			if garageTypeAllowed(garageType) and entryCostAllowed(garage) then
				local cf = garageAuctionCFrame(garage)
				if cf then
					local dist = math.huge
					if origin then
						dist = (cf.Position - origin).Magnitude
					end
					local live = garage:GetAttribute("InAuction") == true
					local prompt = findEnterAuctionPrompt(garage)
					local zone = garage:FindFirstChild("AuctionZone")
					local row = {
						cf = cf,
						garage = garage,
						garageType = garageType,
						entryCost = tonumber(garage:GetAttribute("EntryCost")) or 0,
						dist = dist,
						live = live,
						hasPrompt = prompt ~= nil,
						mode = live and "JOIN" or "START",
					}
					-- Prefer START (idle + EnterAuction); JOIN live only as fallback
					if not live and prompt then
						table.insert(startable, row)
					elseif live then
						table.insert(joinable, row)
					end
				end
			end
		end
	end
	local function pick(list)
		if #list == 0 then
			return nil
		end
		table.sort(list, function(a, b)
			return a.dist < b.dist
		end)
		return list[1]
	end
	-- START first; JOIN only if no idle garage to start
	local chosen = pick(startable) or pick(joinable)
	if chosen then
		state.farmStatus = string.format(
			"%s %s $%s d=%.0f (start=%d join=%d)",
			chosen.mode,
			chosen.garageType,
			tostring(chosen.entryCost),
			chosen.dist,
			#startable,
			#joinable
		)
	else
		state.farmStatus = string.format(
			"no target start=%d join=%d filter=%s cd?",
			#startable,
			#joinable,
			garageFilterActive() and "ON" or "off"
		)
	end
	return chosen
end

local function setFarmPhase(phase, detail)
	state.farmPhase = phase
	if detail then
		state.farmStatus = detail
	end
	pcall(function()
		if Options.FarmPhaseLabel then
			local extra = state.farmStatus and (" · " .. tostring(state.farmStatus)) or ""
			Options.FarmPhaseLabel:SetText("Farm: " .. phase .. extra)
		end
	end)
end

local function leaveAuction()
	local r = remote("Auction", "LeaveAuction")
	if not r then
		return false
	end
	local ok = pcall(function()
		if r:IsA("RemoteFunction") then
			r:InvokeServer()
		else
			r:FireServer()
		end
	end)
	state.farmLastLeaveAt = os.clock()
	return ok
end

local function countOwnedLootNearby(maxDist)
	local hrp = getHRP()
	if not hrp then
		return 0
	end
	local n = 0
	local function consider(model)
		if model:GetAttribute("Owner") ~= LP.UserId then
			return
		end
		local prompt = model:FindFirstChild("PickupPrompt", true)
			or model:FindFirstChild("OpenBoxPrompt", true)
		local part = model:FindFirstChild("Base")
			or model.PrimaryPart
			or model:FindFirstChildWhichIsA("BasePart", true)
		if not (prompt and part) then
			return
		end
		if (part.Position - hrp.Position).Magnitude <= (maxDist or 200) then
			n = n + 1
		end
	end
	local lost = workspace:FindFirstChild("_LostItems")
	if lost then
		for _, m in ipairs(lost:GetChildren()) do
			if m:IsA("Model") then
				consider(m)
			end
		end
	end
	if state.farmGarage and state.farmGarage.Parent then
		for _, d in ipairs(state.farmGarage:GetDescendants()) do
			if d:IsA("Model") then
				consider(d)
			end
		end
	end
	return n
end

local function farmLoadInvToTruck()
	local inv = invoke("Inventory", "GetPlayerInventory")
	if type(inv) ~= "table" then
		return 0
	end
	local n = 0
	for guid, entry in pairs(inv) do
		if type(guid) == "string" and type(entry) == "table" then
			local res = invoke("Vehicles", "TransferInventoryItemToVehicle", guid)
			if res == true or (type(res) == "table" and res.success) then
				n = n + 1
				task.wait(0.08)
			end
		end
	end
	return n
end

-- Auto Farm flow (simple):
-- 1) TP to selected garage type
-- 2) Start Auction (hold EnterAuction)
-- 3) Wait — Auto Bid toggle does the bidding
-- 4) Auction ends (win/lose signals) → leave → next garage
-- No loot pickup (items → Lost & Found)
task.spawn(function()
	while true do
		if not state.running then
			task.wait(0.5)
		elseif not state.autoFarm then
			task.wait(0.4)
		else
			local ok, err = pcall(function()
				syncGarageFilterFromUI()
				-- keep Auto Bid on while farming
				if not state.autoBid then
					state.autoBid = true
					if Toggles.AutoBid and not Toggles.AutoBid.Value then
						Toggles.AutoBid:SetValue(true)
					end
				end
				local phase = state.farmPhase

				if phase == "idle" or phase == "travel" then
					local target = findMatchingAuction()
					if not target or not target.garage then
						setFarmPhase("idle", state.farmStatus or "no target")
						task.wait(1.2)
						return
					end
					state.farmGarage = target.garage
					state.farmGarageGuid = garageCooldownKey(target.garage)
					state.farmWasInAuction = false
					state.farmPendingLeave = false
					state.farmBidQuietSince = nil
					setFarmPhase("travel", target.garageType)
					teleportTo(target.cf * CFrame.new(0, 3, 0))
					task.wait(0.4)
					setFarmPhase("enter", "start " .. tostring(target.garageType))
					state.farmEnteredAt = os.clock()

				elseif phase == "enter" then
					local g = state.farmGarage
					if not g or not g.Parent then
						setFarmPhase("idle", "garage gone")
						task.wait(0.3)
						return
					end
					if LP:GetAttribute("InAuction") == true or isBidUiOpen() then
						state.farmWasInAuction = true
						setFarmPhase("wait", "Auto Bid running…")
						state.farmBidStartedAt = os.clock()
						return
					end
					-- only START idle garages (prefer prompt)
					local prompt = findEnterAuctionPrompt(g)
					local zone = g:FindFirstChild("AuctionZone")
					local stand = prompt and prompt.Parent
					if not (stand and stand:IsA("BasePart")) then
						local es = g:FindFirstChild("EntrySquare", true)
						stand = es and (es:IsA("BasePart") and es or es:FindFirstChildWhichIsA("BasePart", true))
					end
					if not stand then
						stand = zone or g:FindFirstChild("Base")
					end
					if stand and stand:IsA("BasePart") then
						teleportTo(stand.CFrame * CFrame.new(0, 3, 0))
						task.wait(0.35)
					end
					if prompt then
						local hold = math.max(1, tonumber(prompt.HoldDuration) or 1)
						setFarmPhase("enter", "Start Auction…")
						for _ = 1, 4 do
							if LP:GetAttribute("InAuction") == true or isBidUiOpen() then
								break
							end
							if type(fireproximityprompt) == "function" then
								pcall(function()
									fireproximityprompt(prompt, hold)
								end)
								pcall(fireproximityprompt, prompt)
							end
							pcall(function()
								prompt:InputHoldBegin()
							end)
							task.wait(hold + 0.3)
							pcall(function()
								prompt:InputHoldEnd()
							end)
							task.wait(0.35)
						end
					elseif zone then
						-- fallback join live by standing in zone
						setFarmPhase("enter", "join zone…")
						for _ = 1, 8 do
							if LP:GetAttribute("InAuction") == true or isBidUiOpen() then
								break
							end
							teleportTo(zone.CFrame * CFrame.new(0, 3, 0))
							task.wait(0.4)
						end
					end
					if LP:GetAttribute("InAuction") == true or isBidUiOpen() then
						state.farmWasInAuction = true
						setFarmPhase("wait", "Auto Bid running…")
						state.farmBidStartedAt = os.clock()
					elseif os.clock() - (state.farmEnteredAt or 0) > 14 then
						cooldownGarage(g, 20)
						state.farmGarage = nil
						setFarmPhase("idle", "start failed → next")
					else
						task.wait(0.3)
					end

				elseif phase == "bid" or phase == "wait" then
					-- DO NOT bid here — standalone Auto Bid toggle does it
					if state.farmPendingLeave then
						setFarmPhase("leave", state.farmStatus or "ended")
						return
					end
					local inAuc = LP:GetAttribute("InAuction") == true
					local bidOpen = isBidUiOpen()
					local gLive = state.farmGarage
						and state.farmGarage.Parent
						and state.farmGarage:GetAttribute("InAuction") == true
					if inAuc or bidOpen or gLive then
						state.farmWasInAuction = true
					end
					local elapsed = os.clock() - (state.farmBidStartedAt or 0)
					local stillActive = inAuc or bidOpen or gLive
					if stillActive then
						state.farmBidQuietSince = nil
						setFarmPhase("wait", bidOpen and "bidding…" or "in auction…")
						task.wait(0.3)
					else
						if not state.farmBidQuietSince then
							state.farmBidQuietSince = os.clock()
						end
						local quiet = os.clock() - state.farmBidQuietSince
						if state.farmWasInAuction and elapsed >= 8 and quiet >= 3 then
							setFarmPhase("leave", "auction over")
						elseif elapsed > 150 then
							setFarmPhase("leave", "timeout")
						else
							setFarmPhase("wait", "waiting end…")
							task.wait(0.3)
						end
					end

				elseif phase == "collect" then
					setFarmPhase("leave", "skip loot → L&F")

				elseif phase == "leave" then
					setFarmPhase("leave", "leaving…")
					for _ = 1, 6 do
						leaveAuction()
						task.wait(0.2)
					end
					pcall(function()
						local hrp = getHRP()
						if hrp then
							teleportTo(hrp.CFrame * CFrame.new(0, 0, 18))
						end
					end)
					cooldownGarage(state.farmGarage, 40)
					state.farmGarage = nil
					state.farmGarageGuid = nil
					state.farmWasInAuction = false
					state.farmPendingLeave = false
					state.farmAuctionEndedAt = 0
					state.farmBidQuietSince = nil
					state.auctionPickupPhase = false
					setFarmPhase("idle", "next garage")
					task.wait(0.5)
				else
					setFarmPhase("idle", "reset")
					task.wait(0.3)
				end
				task.wait(0.05)
			end)
			if not ok then
				state.farmStatus = "ERR " .. tostring(err):sub(1, 60)
				pcall(function()
					if Options.FarmPhaseLabel then
						Options.FarmPhaseLabel:SetText("Farm: ERROR · " .. tostring(err):sub(1, 40))
					end
				end)
				task.wait(1)
			end
		end
	end
end)

-- Collect: unload truck, auto-collect world loot, auto-accept NPC offers
local pendingOffers = {}

pcall(function()
	local showOffer = remote("NPCShopper", "ShowOffer")
	if showOffer then
		track(showOffer.OnClientEvent:Connect(function(offerId, _chat, _p3, offerPrice, baseValue)
			pendingOffers[offerId] = {
				price = tonumber(offerPrice) or 0,
				base = tonumber(baseValue) or 0,
				at = os.clock(),
			}
		end))
	end
	local hideOffer = remote("NPCShopper", "HideOffer")
	if hideOffer then
		track(hideOffer.OnClientEvent:Connect(function(offerId)
			pendingOffers[offerId] = nil
		end))
	end
end)

local function inventorySpaceLeft()
	local cap = LP:GetAttribute("InventoryCap") or 0
	local count = LP:GetAttribute("InventoryCount") or 0
	return math.max(0, cap - count)
end

local function shouldPauseInventory()
	if not state.pauseOnFull then
		return false
	end
	local cap = LP:GetAttribute("InventoryCap") or 0
	local count = LP:GetAttribute("InventoryCount") or 0
	if cap <= 0 then
		return false
	end
	local pct = (count / cap) * 100
	if count <= state.resumeBelow then
		return false
	end
	return pct >= state.pauseAtPct
end

local function collectVehicleGuids(items)
	local guids = {}
	if type(items) ~= "table" then
		return guids
	end
	for k, entry in pairs(items) do
		local guid = nil
		if type(k) == "string" and k ~= "" then
			guid = k
		elseif type(entry) == "string" then
			guid = entry
		elseif type(entry) == "table" then
			guid = entry.guid or entry.GUID or entry.Id
		end
		if guid then
			table.insert(guids, guid)
		end
	end
	return guids
end

local function unloadTruckAll()
	if not getSeatedVehicle() then
		return false, "not seated"
	end
	local vehicleId = LP:GetAttribute("EquippedVehicle")
	if type(vehicleId) ~= "string" or vehicleId == "" then
		return false, "no equipped vehicle"
	end
	local ok, items = pcall(function()
		return remote("Vehicles", "GetVehicleItems"):InvokeServer(vehicleId)
	end)
	if not ok or type(items) ~= "table" then
		return false, "no items"
	end
	local guids = collectVehicleGuids(items)
	if #guids == 0 then
		return false, "empty"
	end
	local space = inventorySpaceLeft()
	if space <= 0 then
		return false, "inventory full"
	end
	while #guids > space do
		table.remove(guids)
	end
	return fire("Vehicles", "TransferVehicleItemsToInventory", guids)
end

local function canPickupLostItem(model)
	if not model or not model.Parent then
		return false
	end
	local owner = model:GetAttribute("Owner")
	if owner ~= nil and owner ~= 0 and owner ~= LP.UserId then
		return false
	end
	return true
end

local function firePickupPrompt(prompt)
	if not prompt or not prompt.Parent then
		return false
	end
	local hold = tonumber(prompt.HoldDuration) or 0.4
	if type(fireproximityprompt) == "function" then
		local ok = pcall(function()
			-- some executors: fireproximityprompt(prompt, holdDuration)
			fireproximityprompt(prompt, hold)
		end)
		if not ok then
			ok = pcall(fireproximityprompt, prompt)
		end
		if ok and hold <= 0.15 then
			return true
		end
	end
	pcall(function()
		prompt:InputHoldBegin()
	end)
	task.wait(math.max(0.05, hold + 0.12))
	pcall(function()
		prompt:InputHoldEnd()
	end)
	if type(fireproximityprompt) == "function" then
		pcall(fireproximityprompt, prompt)
	end
	return true
end

local function collectNearestLostItem()
	if inventorySpaceLeft() <= 0 or shouldPauseInventory() then
		return false
	end
	local hrp = getHRP()
	if not hrp then
		return false
	end
	local best, bestDist
	local function scanFolder(folder)
		if not folder then
			return
		end
		for _, model in ipairs(folder:GetChildren()) do
			if model:IsA("Model") and canPickupLostItem(model) then
				local prompt = model:FindFirstChild("PickupPrompt", true)
					or model:FindFirstChild("OpenBoxPrompt", true)
				local part = model:FindFirstChild("Base")
					or model.PrimaryPart
					or model:FindFirstChildWhichIsA("BasePart", true)
				if prompt and part then
					local dist = (part.Position - hrp.Position).Magnitude
					local maxDist = (prompt.MaxActivationDistance or 8) + 4
					if dist <= maxDist and (not bestDist or dist < bestDist) then
						best = prompt
						bestDist = dist
					end
				end
			end
		end
	end
	scanFolder(workspace:FindFirstChild("_LostItems"))
	scanFolder(workspace:FindFirstChild("_Carryables"))
	if not best then
		return false
	end
	return firePickupPrompt(best)
end

-- Win loot: Owner == you; prompts in garage or _LostItems. AuctionPickup* are HUD-only.
local function isOwnedAuctionLoot(model)
	if not model or not model:IsA("Model") or not model.Parent then
		return false
	end
	return model:GetAttribute("Owner") == LP.UserId
end

local function findAuctionLootPromptIn(root, hrp, best, bestDist)
	if not root then
		return best, bestDist
	end
	for _, model in ipairs(root:GetChildren()) do
		if isOwnedAuctionLoot(model) then
			local prompt = model:FindFirstChild("PickupPrompt", true)
				or model:FindFirstChild("OpenBoxPrompt", true)
			local part = model:FindFirstChild("Base")
				or model.PrimaryPart
				or model:FindFirstChildWhichIsA("BasePart", true)
			if prompt and prompt:IsA("ProximityPrompt") and part then
				local dist = (part.Position - hrp.Position).Magnitude
				local maxDist = (prompt.MaxActivationDistance or 10) + 12
				if dist <= maxDist and (not bestDist or dist < bestDist) then
					best = prompt
					bestDist = dist
				end
			end
		end
		-- items may be nested under garage models
		if model:IsA("Model") or model:IsA("Folder") then
			for _, child in ipairs(model:GetDescendants()) do
				if child:IsA("Model") and isOwnedAuctionLoot(child) then
					local prompt = child:FindFirstChild("PickupPrompt", true)
						or child:FindFirstChild("OpenBoxPrompt", true)
					local part = child:FindFirstChild("Base")
						or child.PrimaryPart
						or child:FindFirstChildWhichIsA("BasePart", true)
					if prompt and prompt:IsA("ProximityPrompt") and part then
						local dist = (part.Position - hrp.Position).Magnitude
						local maxDist = (prompt.MaxActivationDistance or 10) + 12
						if dist <= maxDist and (not bestDist or dist < bestDist) then
							best = prompt
							bestDist = dist
						end
					end
				end
			end
		end
	end
	return best, bestDist
end

local function findNearestOwnedAuctionLoot(hrp, rangeOnly)
	local bestPrompt, bestPart, bestDist = nil, nil, nil
	local function consider(model)
		if not isOwnedAuctionLoot(model) then
			return
		end
		local prompt = model:FindFirstChild("PickupPrompt", true)
			or model:FindFirstChild("OpenBoxPrompt", true)
		if not prompt or not prompt:IsA("ProximityPrompt") then
			return
		end
		local part = model:FindFirstChild("Base")
			or model.PrimaryPart
			or model:FindFirstChildWhichIsA("BasePart", true)
		if not part then
			return
		end
		local dist = (part.Position - hrp.Position).Magnitude
		if rangeOnly then
			local maxDist = (prompt.MaxActivationDistance or 10) + 12
			if dist > maxDist then
				return
			end
		end
		if not bestDist or dist < bestDist then
			bestPrompt = prompt
			bestPart = part
			bestDist = dist
		end
	end
	-- post-win loot lives in _Carryables; also _LostItems / garages
	local roots = {
		workspace:FindFirstChild("_Carryables"),
		workspace:FindFirstChild("_LostItems"),
	}
	local debris = workspace:FindFirstChild("_Debris")
	if debris then
		table.insert(roots, debris:FindFirstChild("Garages"))
	end
	for _, root in ipairs(roots) do
		if root then
			for _, model in ipairs(root:GetChildren()) do
				if model:IsA("Model") then
					consider(model)
				end
			end
			-- nested models (boxes inside folders / garage children)
			if root.Name == "Garages" then
				for _, d in ipairs(root:GetDescendants()) do
					if d:IsA("Model") then
						consider(d)
					end
				end
			end
		end
	end
	return bestPrompt, bestPart, bestDist
end

-- Auction win loot: proximity put items into EquippedVehicle (not player InventoryCount).
local function countOwnedCarryables()
	local n = 0
	local function scan(folder)
		if not folder then
			return
		end
		for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("Model") and m:GetAttribute("Owner") == LP.UserId then
				local prompt = m:FindFirstChild("PickupPrompt", true)
					or m:FindFirstChild("OpenBoxPrompt", true)
				if prompt then
					n = n + 1
				end
			end
		end
	end
	scan(workspace:FindFirstChild("_Carryables"))
	scan(workspace:FindFirstChild("_LostItems"))
	return n
end

local function countVehicleCargo()
	local vehicleId = LP:GetAttribute("EquippedVehicle")
	if type(vehicleId) ~= "string" or vehicleId == "" then
		return 0
	end
	local ok, items = pcall(function()
		return remote("Vehicles", "GetVehicleItems"):InvokeServer(vehicleId)
	end)
	if not ok or type(items) ~= "table" then
		return 0
	end
	local n = 0
	for _ in pairs(items) do
		n = n + 1
	end
	return n
end

local function collectNearestAuctionLoot()
	-- do NOT gate on InventoryCount — auction pick goes into truck/cargo
	local hrp = getHRP()
	if not hrp then
		return false
	end
	-- 1) already in range → fire prompt
	local prompt, part, dist = findNearestOwnedAuctionLoot(hrp, true)
	if prompt then
		return firePickupPrompt(prompt)
	end
	-- 2) owned loot exists but far → TP then fire
	prompt, part, dist = findNearestOwnedAuctionLoot(hrp, false)
	if not prompt or not part then
		return false
	end
	if dist and dist > 8 then
		teleportTo(part.CFrame * CFrame.new(0, 3, 0))
		task.wait(0.15)
	end
	return firePickupPrompt(prompt)
end

-- Standalone only — Auto Place / other tabs never set this.
-- Auto Farm collect phase calls collectNearestAuctionLoot() itself.
task.spawn(function()
	while state.running do
		if state.autoCollectAuction then
			-- skip if farm already collecting (avoid double TP spam)
			if state.autoFarm and state.farmPhase == "collect" then
				task.wait(0.4)
			else
				local got = collectNearestAuctionLoot()
				local dense = state.auctionPickupPhase
					or LP:GetAttribute("InAuction") == true
					or countOwnedCarryables() > 0
				task.wait(got and 0.25 or (dense and 0.2 or 0.45))
			end
		else
			task.wait(0.4)
		end
	end
end)

-- Stock UI shows delta: (offer-base)/base*100 as [+5%] / [-10%]
-- Staff auto-accept uses absolute: offer/base*100 (DefaultMinOfferPercent = 105)
-- Hub Min Accept uses ABSOLUTE (same as staff), so 100 = fair value, 105 = +5% over base.
local function offerAbsolutePercent(price, base)
	if type(price) ~= "number" or type(base) ~= "number" or base <= 0 then
		return nil
	end
	return (price / base) * 100
end

local function processPendingOffers()
	local now = os.clock()
	local minPct = tonumber(state.minAcceptPct)
	local maxPct = tonumber(state.maxAcceptPct)
	if not minPct or not maxPct or minPct > maxPct then
		minPct, maxPct = 0, 500
	end
	for offerId, data in pairs(pendingOffers) do
		if now - (data.at or 0) > 30 then
			pendingOffers[offerId] = nil
		else
			local pct = offerAbsolutePercent(data.price, data.base)
			if pct and pct >= minPct and pct <= maxPct then
				fire("NPCShopper", "RespondOffer", offerId, true)
				pendingOffers[offerId] = nil
			end
			-- outside range: leave pending until HideOffer / expire (no auto-decline)
		end
	end
end

-- Floor ghost cleanup: old display placements (no ShelfGUID attr, resting at floor Y) -> PickUpStockItem
-- Shelf-listed renders also lack ShelfGUID client-side, so require near-floor height.
local ghostPickupCooldown = {} -- [guid] = os.clock()
local GHOST_FLOOR_TOLERANCE = 1.5 -- studs above plot OriginY counts as floor-resting

local function isFloorGhost(model, floorY)
	if not model:IsA("Model") then
		return false
	end
	if model:GetAttribute("ShelfGUID") then
		return false
	end
	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not part then
		return false
	end
	local dy = part.Position.Y - floorY
	return dy <= GHOST_FLOOR_TOLERANCE
end

local function countFloorGhosts()
	local plot = getMyPlot()
	if not plot then
		return 0
	end
	local floorY = plot:GetAttribute("OriginY") or 0
	local stock = plot:FindFirstChild("Stock")
	if not stock then
		return 0
	end
	local n = 0
	for _, m in ipairs(stock:GetChildren()) do
		if isFloorGhost(m, floorY) then
			n = n + 1
		end
	end
	return n
end

local function pickupFloorGhostsOnce()
	local plot = getMyPlot()
	if not plot then
		return 0, "no plot"
	end
	local floorY = plot:GetAttribute("OriginY") or 0
	local stock = plot:FindFirstChild("Stock")
	if not stock or #stock:GetChildren() == 0 then
		return 0, "stock not streamed (near plot?)"
	end
	local now = os.clock()
	local picked = 0
	local lastErr
	for _, m in ipairs(stock:GetChildren()) do
		if isFloorGhost(m, floorY) then
			local guid = m:GetAttribute("GUID")
			if type(guid) == "string" then
				local last = ghostPickupCooldown[guid] or 0
				if now - last >= 6 then
					ghostPickupCooldown[guid] = now
					local ok, err = fire("Plot", "PickUpStockItem", guid)
					if ok then
						picked = picked + 1
						task.wait(0.15)
					else
						lastErr = err
					end
				end
			end
		end
	end
	return picked, lastErr
end

-- Lost & Found UI: GetLostItems(area) / ClaimLostItem(area, guid)
-- Live: claim goes into EquippedVehicle cargo (InventoryCount unchanged).
local LOST_FOUND_AREAS = {
	"Junk Yard",
	"Back Alley",
	"Farmyard",
	"Shipyard",
	"Shopping Mall",
	"Jurassic",
	"Lucky Beach",
}

local function countLostFoundPending()
	local n = 0
	for _, area in ipairs(LOST_FOUND_AREAS) do
		local res = invoke("UI", "GetLostItems", area)
		local items = res and res.items
		if type(items) == "table" then
			for _ in pairs(items) do
				n = n + 1
			end
		end
	end
	return n
end

local function claimLostFoundOnce()
	local vehicleId = LP:GetAttribute("EquippedVehicle")
	if type(vehicleId) ~= "string" or vehicleId == "" then
		return 0, "no equipped vehicle"
	end
	local pending = countLostFoundPending()
	if pending <= 0 then
		return 0, "empty"
	end
	local claimed = 0
	local lastErr = nil
	for _, area in ipairs(LOST_FOUND_AREAS) do
		local res = invoke("UI", "GetLostItems", area)
		local items = res and res.items
		if type(items) == "table" then
			for guid, _entry in pairs(items) do
				if type(guid) == "string" then
					local result = invoke("UI", "ClaimLostItem", area, guid)
					if type(result) == "table" and result.success then
						claimed = claimed + 1
						task.wait(0.12)
					elseif type(result) == "table" then
						lastErr = result.error or result.message or lastErr
						-- truck cargo full / other reject — stop this area
						if lastErr and (tostring(lastErr):lower():find("full") or tostring(lastErr):lower():find("space")) then
							return claimed, lastErr
						end
					end
				end
			end
		end
	end
	return claimed, lastErr
end

local CollectBox = addBox(Tabs.Collect, "Collect", "package")
CollectBox:AddToggle("AutoCollect", {
	Text = "Auto-Collect (World)",
	Default = false,
	Tooltip = "Proximity pick on _LostItems in range (not Lost & Found UI)",
})
CollectBox:AddToggle("AutoLostFound", {
	Text = "Auto Lost & Found",
	Default = false,
	Tooltip = "ClaimLostItem → EquippedVehicle cargo (not inventory). Needs a vehicle equipped.",
})
CollectBox:AddToggle("AutoUnload", {
	Text = "Unload Truck",
	Default = false,
	Tooltip = "Must be seated in truck",
})
CollectBox:AddToggle("AutoAccept", {
	Text = "Auto-Accept Offers",
	Default = false,
	Tooltip = "NPC shopper offers. Accept when offer % is between Min and Max % of item base value.",
})
CollectBox:AddSlider("MinAcceptPct", {
	Text = "Min Accept % of value",
	Default = 0,
	Min = 0,
	Max = 500,
	Rounding = 0,
	Tooltip = "Absolute % of base (staff-style). 100=fair, 105=+5% (game UI [+5%]), 0=lowest. v6 range 0–500.",
})
CollectBox:AddSlider("MaxAcceptPct", {
	Text = "Max Accept % of value",
	Default = 500,
	Min = 0,
	Max = 500,
	Rounding = 0,
	Tooltip = "Absolute % of base. Offers above this % are left pending. 500 = accept up to 5x base.",
})
CollectBox:AddToggle("AutoPickupGhosts", {
	Text = "Auto-Cleanup Floor Ghosts",
	Default = false,
	Tooltip = "PickUpStockItem for stock models with no ShelfGUID (old floor listings) → back to inventory.",
})
CollectBox:AddButton({
	Text = "Cleanup Floor Ghosts Now",
	Func = function()
		local n, err = pickupFloorGhostsOnce()
		local msg
		if n > 0 then
			msg = "Picked " .. n .. " → inventory"
		elseif err then
			msg = tostring(err)
		else
			msg = "No floor ghosts found"
		end
		Library:Notify({
			Title = "Ghost Cleanup",
			Description = msg,
			Time = 3,
		})
	end,
})
CollectBox:AddButton({
	Text = "Unload Now",
	Func = function()
		local ok, err = unloadTruckAll()
		Library:Notify({
			Title = "Unload",
			Description = ok and "Transfer sent" or tostring(err or "failed"),
			Time = 2,
		})
	end,
})
CollectBox:AddButton({
	Text = "Claim Lost & Found Now",
	Func = function()
		local n, err = claimLostFoundOnce()
		local msg
		if n > 0 then
			msg = "Claimed " .. n .. " → truck"
		elseif err == "empty" then
			msg = "Nothing to recover"
		elseif err == "no equipped vehicle" then
			msg = "Equip a vehicle first"
		elseif err then
			msg = tostring(err)
		else
			msg = "Nothing claimed"
		end
		Library:Notify({
			Title = "Lost & Found",
			Description = msg,
			Time = 3,
		})
	end,
})

Toggles.AutoCollect:OnChanged(function()
	state.autoCollect = Toggles.AutoCollect.Value
end)
Toggles.AutoLostFound:OnChanged(function()
	state.autoLostFound = Toggles.AutoLostFound.Value
end)
Toggles.AutoUnload:OnChanged(function()
	state.autoUnload = Toggles.AutoUnload.Value
end)
Toggles.AutoAccept:OnChanged(function()
	state.autoAccept = Toggles.AutoAccept.Value
end)
Options.MinAcceptPct:OnChanged(function()
	state.minAcceptPct = Options.MinAcceptPct.Value
end)
Options.MaxAcceptPct:OnChanged(function()
	state.maxAcceptPct = Options.MaxAcceptPct.Value
end)
Toggles.AutoPickupGhosts:OnChanged(function()
	state.autoPickupGhosts = Toggles.AutoPickupGhosts.Value
end)

task.spawn(function()
	while state.running do
		if state.autoUnload and not shouldPauseInventory() then
			unloadTruckAll()
			task.wait(1.5)
		else
			task.wait(0.4)
		end
	end
end)

task.spawn(function()
	while state.running do
		if state.autoCollect and not shouldPauseInventory() then
			collectNearestLostItem()
			task.wait(0.35)
		else
			task.wait(0.4)
		end
	end
end)

task.spawn(function()
	while state.running do
		if state.autoLostFound then
			-- L&F → vehicle cargo (no inventory space needed)
			local n = claimLostFoundOnce()
			task.wait(n > 0 and 0.8 or 2.0)
		else
			task.wait(0.5)
		end
	end
end)

task.spawn(function()
	while state.running do
		if state.autoAccept then
			processPendingOffers()
			task.wait(0.2)
		else
			task.wait(0.4)
		end
	end
end)

task.spawn(function()
	while state.running do
		if state.autoPickupGhosts and not shouldPauseInventory() then
			local n = pickupFloorGhostsOnce()
			task.wait(n > 0 and 0.8 or 2.0)
		else
			task.wait(0.5)
		end
	end
end)

-- AutoPlace + Auto Wash
local CATEGORIES = {
	"Accessories",
	"Decoration",
	"Electronics",
	"Food",
	"Furniture",
	"Livestock",
	"Misc",
	"Structure",
	"Tool",
	"Trophy",
	"Vehicle",
	"Weapon",
}
local RARITIES = {
	"Epic",
	"Junk",
	"Legendary",
	"Limited",
	"Lost",
	"Mythical",
	"Rare",
	"Trophy",
	"Uncommon",
}

local ItemsMod, MutatorMod, GradingMod
pcall(function()
	ItemsMod = require(RS.Modules.Items)
end)
pcall(function()
	MutatorMod = require(RS.Modules.MutatorModule)
end)
pcall(function()
	GradingMod = require(RS.Modules.Grading)
end)

local function multiSelectActive(map)
	if type(map) ~= "table" then
		return false
	end
	for _, v in pairs(map) do
		if v == true or (type(v) == "string" and v ~= "") then
			return true
		end
	end
	return false
end

local function multiSelectHas(map, key)
	if not multiSelectActive(map) then
		return false
	end
	if map[key] == true then
		return true
	end
	for _, v in pairs(map) do
		if v == key then
			return true
		end
	end
	return false
end

local function getItemInfo(itemId)
	if not ItemsMod or itemId == nil then
		return nil
	end
	return ItemsMod[tostring(itemId)] or ItemsMod[itemId]
end

local function entryRarity(entry)
	if type(entry) ~= "table" then
		return "Uncommon"
	end
	local info = getItemInfo(entry.ItemId)
	return (info and info.Rarity) or entry.Rarity or "Uncommon"
end

local function entryNeedsGrade(entry)
	if type(entry) ~= "table" then
		return false
	end
	if entry.Grade ~= nil and entry.Grade ~= "" then
		return false
	end
	return multiSelectHas(state.gradeRarities, entryRarity(entry))
end

local function entryExcluded(entry)
	if type(entry) ~= "table" then
		return true
	end
	local info = getItemInfo(entry.ItemId)
	local cat = (info and info.Category) or entry.Category or "Misc"
	local rarity = entryRarity(entry)
	if multiSelectHas(state.excludeCategories, cat) then
		return true
	end
	if multiSelectHas(state.excludeRarities, rarity) then
		return true
	end
	if entryNeedsGrade(entry) then
		return true
	end
	return false
end

local function stockPriceFor(entry)
	local info = getItemInfo(entry.ItemId)
	local base = (info and info.BasePrice) or 0
	local price = base
	if MutatorMod and type(MutatorMod.CalculatePriceForEntry) == "function" then
		local ok, v = pcall(function()
			return MutatorMod:CalculatePriceForEntry(base, entry)
		end)
		if ok and type(v) == "number" then
			price = v
		end
	end
	if entry.Grade and GradingMod and GradingMod.GradeMultipliers and GradingMod.GradeMultipliers[entry.Grade] then
		price = price * GradingMod.GradeMultipliers[entry.Grade]
	end
	local mult = state.stockPriceMult or 1
	if mult ~= 1 then
		price = price * mult
	end
	return price or 0
end

local function getOwnedPlotModel()
	local plots = workspace:FindFirstChild("_Plots")
	if not plots then
		return nil
	end
	for _, plot in ipairs(plots:GetChildren()) do
		if plot:GetAttribute("OwnerUserId") == LP.UserId then
			return plot
		end
	end
	return nil
end

-- P1: Pawn sell + stock reprice / pickup
local function pawnSellFiltered()
	local sellable = invoke("Pawn", "GetSellableItems")
	if type(sellable) ~= "table" then
		return 0, "no sellable"
	end
	local guids = {}
	for guid, entry in pairs(sellable) do
		if type(guid) == "string" and type(entry) == "table" then
			local rarity = entryRarity(entry)
			if not multiSelectHas(state.pawnSkipRarities, rarity) then
				local price = stockPriceFor(entry)
				local mult = state.stockPriceMult or 1
				if mult ~= 0 then
					price = price / mult
				end
				if price >= (state.pawnMinPrice or 0) then
					table.insert(guids, guid)
				end
			end
		end
	end
	if #guids == 0 then
		return 0, "nothing matches filter"
	end
	local result = invoke("Pawn", "SellItems", guids)
	if type(result) == "table" and result.success then
		return result.sold or #guids, result.totalEarned or 0
	end
	return 0, (type(result) == "table" and result.error) or "sell failed"
end

local function repriceAllStock()
	local plot = getOwnedPlotModel()
	if not plot then
		return 0, "no plot"
	end
	local stock = plot:FindFirstChild("Stock")
	if not stock then
		return 0, "no stock"
	end
	local n = 0
	for _, item in ipairs(stock:GetChildren()) do
		local guid = item:GetAttribute("GUID") or item.Name
		local itemId = item:GetAttribute("ItemId")
		local entry = {
			ItemId = itemId,
			Grade = item:GetAttribute("Grade"),
			Mutators = item:GetAttribute("Mutators"),
			Condition = item:GetAttribute("Condition"),
		}
		local price = math.floor(stockPriceFor(entry) * 100) / 100
		if type(guid) == "string" and price > 0 then
			if fire("Plot", "ChangeStockPrice", guid, price) then
				n = n + 1
			end
			task.wait(0.05)
		end
	end
	return n
end

local function pickupAllStock()
	local plot = getOwnedPlotModel()
	if not plot then
		return 0, "no plot"
	end
	local stock = plot:FindFirstChild("Stock")
	if not stock then
		return 0, "no stock"
	end
	local n = 0
	for _, item in ipairs(stock:GetChildren()) do
		if inventorySpaceLeft() <= 0 then
			break
		end
		local guid = item:GetAttribute("GUID") or item.Name
		if type(guid) == "string" and fire("Plot", "PickUpStockItem", guid) then
			n = n + 1
			task.wait(0.08)
		end
	end
	return n
end

-- Game key: Stock attrs ShelfGUID + SnapPointName → "guid:SnapPoint_N" (GhostEvaluation)
local function occupiedShelfSnaps(plot)
	local used = {}
	local stock = plot and plot:FindFirstChild("Stock")
	if not stock then
		return used
	end
	for _, item in ipairs(stock:GetChildren()) do
		local shelfGuid = item:GetAttribute("ShelfGUID")
		local snap = item:GetAttribute("SnapPointName")
			or item:GetAttribute("SnapPoint")
			or item:GetAttribute("SnapName")
		if type(shelfGuid) == "string" and type(snap) == "string" and snap ~= "" then
			used[shelfGuid .. ":" .. snap] = true
		end
	end
	return used
end

local function listFreePlaceSlots(plot)
	local free = {}
	if not plot then
		return free
	end
	local used = occupiedShelfSnaps(plot)
	local furniture = plot:FindFirstChild("Furniture")
	local roots = {}
	if furniture then
		for _, ch in ipairs(furniture:GetChildren()) do
			table.insert(roots, ch)
		end
	else
		table.insert(roots, plot)
	end
	for _, root in ipairs(roots) do
		local shelves = {}
		if root:GetAttribute("IsShelf") == true then
			table.insert(shelves, root)
		end
		for _, desc in ipairs(root:GetDescendants()) do
			if desc:GetAttribute("IsShelf") == true then
				table.insert(shelves, desc)
			end
		end
		for _, shelf in ipairs(shelves) do
			local shelfGuid = shelf:GetAttribute("GUID")
			if type(shelfGuid) == "string" then
				for _, att in ipairs(shelf:GetDescendants()) do
					if att:IsA("Attachment") and string.match(att.Name, "^SnapPoint") then
						local key = shelfGuid .. ":" .. att.Name
						if not used[key] then
							table.insert(free, {
								cf = att.WorldCFrame,
								shelfGuid = shelfGuid,
								snapName = att.Name,
								surface = false,
								key = key,
							})
							used[key] = true -- reserve so list has unique slots only once
						end
					end
				end
			end
		end
	end
	-- floor fallback removed: game has no floor listing path (v202). Only shelf snaps.
return free
end

local function placeOneStockItem()
	local plot = getOwnedPlotModel()
	if not plot then
		return false, "no plot"
	end
	local inv = invoke("Inventory", "GetPlayerInventory")
	if type(inv) ~= "table" then
		return false, "no inventory"
	end
	local freeSlots = listFreePlaceSlots(plot)
	if #freeSlots == 0 then
		return false, "no slot"
	end
	local slotIdx = 1
	local placed = 0
	for guid, entry in pairs(inv) do
		if slotIdx > #freeSlots then
			break
		end
		if type(guid) == "string" and type(entry) == "table" and not entryExcluded(entry) then
			local itemId = entry.ItemId
			if itemId ~= nil then
				local slot = freeSlots[slotIdx]
				local price = stockPriceFor(entry)
				-- v202 contract (ShelfInteraction): 10 args — arg9=true (sell listing),
				-- arg10 = request GUID; server confirms via PlaceStockItemResult.
				-- arg9=false tell server "display/decor" → no listing (old v140 9-arg).
				local req = HttpService:GenerateGUID(false)
				placePending[req] = true
				local r = remote("Plot", "PlaceStockItem")
				local ok = false
				if r then
					ok = pcall(function()
						r:FireServer(
							guid,
							tostring(itemId),
							slot.cf * CFrame.Angles(0, 0, 0),
							price,
							slot.shelfGuid,
							slot.snapName,
							nil,
							nil,
							true,
							req
						)
					end)
				end
				if ok then
					placed = placed + 1
					slotIdx = slotIdx + 1
					task.wait(0.25)
				end
			end
		end
	end
	if placed > 0 then
		return true, placed
	end
	return false, "nothing to place"
end

local function washProcessSlots()
	local result = invoke("Wash", "GetSlotState")
	if type(result) ~= "table" then
		return
	end
	local unlocked = result.unlockedCount or 1
	local slots = result.slots or {}
	local now = workspace:GetServerTimeNow()
	for i = 1, unlocked do
		local data = slots[tostring(i)] or slots[i]
		if type(data) == "table" then
			if data.Washed then
				invoke("Wash", "ClaimWashedItem", i)
			else
				local start = data.StartTime or 0
				local dur = data.Duration or 15
				if start > 0 and now >= start + dur then
					local col = invoke("Wash", "CollectWash", i)
					if type(col) == "table" and col.success then
						invoke("Wash", "ClaimWashedItem", i)
					end
				end
			end
		end
	end
end

local function washStartDirty()
	local result = invoke("Wash", "GetSlotState")
	if type(result) ~= "table" then
		return
	end
	local unlocked = result.unlockedCount or 1
	local slots = result.slots or {}
	local freeSlots = {}
	for i = 1, unlocked do
		local data = slots[tostring(i)] or slots[i]
		if data == nil then
			table.insert(freeSlots, i)
		end
	end
	if #freeSlots == 0 then
		return
	end
	local washable = invoke("Wash", "GetWashableItems")
	local items = washable and washable.items
	if type(items) ~= "table" then
		return
	end
	local idx = 1
	for _, item in ipairs(items) do
		if idx > #freeSlots then
			break
		end
		if type(item) == "table" and item.guid then
			local slotIdx = freeSlots[idx]
			local res = invoke("Wash", "StartWash", slotIdx, item.guid, item.source, item.vehicleGUID)
			if type(res) == "table" and res.success then
				idx = idx + 1
			end
		end
	end
end

local function gradeProcessSlots()
	local result = invoke("Grading", "GetSlotState")
	if type(result) ~= "table" then
		return
	end
	local unlocked = result.unlockedCount or 1
	local slots = result.slots or {}
	local now = workspace:GetServerTimeNow()
	for i = 1, unlocked do
		local data = slots[tostring(i)] or slots[i]
		if type(data) == "table" then
			if data.Grade or data.Graded then
				invoke("Grading", "ClaimGradedItem", i)
			else
				local start = data.StartTime or 0
				local dur = data.Duration or 60
				if start > 0 and now >= start + dur then
					local col = invoke("Grading", "CollectGrade", i)
					if type(col) == "table" and col.success then
						invoke("Grading", "ClaimGradedItem", i)
					end
				end
			end
		end
	end
end

local function gradeStartEligible()
	if not multiSelectActive(state.gradeRarities) then
		return
	end
	local result = invoke("Grading", "GetSlotState")
	if type(result) ~= "table" then
		return
	end
	local unlocked = result.unlockedCount or 1
	local slots = result.slots or {}
	local freeSlots = {}
	for i = 1, unlocked do
		local data = slots[tostring(i)] or slots[i]
		if data == nil then
			table.insert(freeSlots, i)
		end
	end
	if #freeSlots == 0 then
		return
	end
	local gradable = invoke("Grading", "GetGradableItems")
	local items = gradable and gradable.items
	if type(items) ~= "table" then
		return
	end
	local idx = 1
	for _, item in ipairs(items) do
		if idx > #freeSlots then
			break
		end
		if type(item) == "table" and item.guid then
			local entry = item.data or item
			local rarity = entryRarity(entry)
			if multiSelectHas(state.gradeRarities, rarity) then
				local slotIdx = freeSlots[idx]
				local res = invoke("Grading", "StartGrading", slotIdx, item.guid, item.source, item.vehicleGUID)
				if type(res) == "table" and res.success then
					idx = idx + 1
				end
			end
		end
	end
end

-- P1 Sell tab: Pawn
local SellBox = addBox(Tabs.Sell, "Pawn Shop", "coins")
SellBox:AddToggle("AutoPawnSell", {
	Text = "Auto Pawn Sell",
	Default = false,
	Tooltip = "SellItems via Pawn remotes using filters below",
})
SellBox:AddSlider("PawnMinPrice", {
	Text = "Min Sell Price",
	Default = 0,
	Min = 0,
	Max = 100000,
	Rounding = 0,
	Tooltip = "Skip items estimated below this",
})
SellBox:AddDropdown("PawnSkipRarities", {
	Text = "Skip Rarities",
	Values = RARITIES,
	Multi = true,
	Default = {},
	Tooltip = "Never sell these rarities",
})
SellBox:AddButton({
	Text = "Sell Matching Now",
	Func = function()
		local sold, earned = pawnSellFiltered()
		Library:Notify({
			Title = "Pawn",
			Description = sold > 0 and ("Sold " .. sold .. " · $" .. tostring(earned)) or tostring(earned),
			Time = 3,
		})
	end,
})
SellBox:AddButton({
	Text = "TP Quick Sell Shop",
	Func = function()
		local cf = gpsPoiMap["Quck Sell Shop"] or gpsPoiMap["Quick Sell Shop"]
		if cf then
			teleportTo(cf)
		else
			Library:Notify({ Title = "GPS", Description = "Quick Sell POI missing — Refresh GPS", Time = 2 })
		end
	end,
})

Toggles.AutoPawnSell:OnChanged(function()
	state.autoPawnSell = Toggles.AutoPawnSell.Value
end)
Options.PawnMinPrice:OnChanged(function()
	state.pawnMinPrice = Options.PawnMinPrice.Value or 0
end)
Options.PawnSkipRarities:OnChanged(function()
	local v = Options.PawnSkipRarities.Value
	state.pawnSkipRarities = type(v) == "table" and v or {}
end)

task.spawn(function()
	while state.running do
		if state.autoPawnSell then
			pawnSellFiltered()
			task.wait(4)
		else
			task.wait(0.5)
		end
	end
end)

local PlaceBox = addBox(Tabs.AutoPlace, "Place", "box")
PlaceBox:AddToggle("AutoPlace", { Text = "Auto Place Items", Default = false })
PlaceBox:AddDropdown("ExcludeCategories", {
	Text = "Exclude Categories",
	Values = CATEGORIES,
	Multi = true,
	Default = {},
})
PlaceBox:AddDropdown("ExcludeRarities", {
	Text = "Exclude Rarities",
	Values = RARITIES,
	Multi = true,
	Default = {},
})
PlaceBox:AddSlider("StockPriceMult", {
	Text = "Stock Price Mult",
	Default = 1,
	Min = 0.5,
	Max = 5,
	Rounding = 1,
	Tooltip = "Multiplier when placing / reprice",
})
PlaceBox:AddToggle("AutoWash", {
	Text = "Auto Wash",
	Default = false,
	Tooltip = "Independent of Auto Place",
})
PlaceBox:AddButton({
	Text = "Place One Now",
	Func = function()
		local ok, res = placeOneStockItem()
		Library:Notify({
			Title = "Place",
			Description = ok and ("Placed " .. tostring(res)) or tostring(res or "fail"),
			Time = 2.5,
		})
	end,
	Tooltip = "Places 1+ item to free slot, ignores inventory pause",
})
PlaceBox:AddButton({
	Text = "Reprice All Stock",
	Func = function()
		local n = repriceAllStock()
		Library:Notify({ Title = "Stock", Description = "Repriced " .. tostring(n), Time = 2 })
	end,
})
PlaceBox:AddButton({
	Text = "Pick Up All Stock",
	Func = function()
		local n, err = pickupAllStock()
		Library:Notify({
			Title = "Stock",
			Description = n > 0 and ("Picked " .. n) or tostring(err or "none"),
			Time = 2,
		})
	end,
})

Toggles.AutoPlace:OnChanged(function()
	state.autoPlace = Toggles.AutoPlace.Value
end)
Toggles.AutoWash:OnChanged(function()
	state.autoWash = Toggles.AutoWash.Value
end)
Options.ExcludeCategories:OnChanged(function()
	local v = Options.ExcludeCategories.Value
	state.excludeCategories = type(v) == "table" and v or {}
end)
Options.ExcludeRarities:OnChanged(function()
	local v = Options.ExcludeRarities.Value
	state.excludeRarities = type(v) == "table" and v or {}
end)
Options.StockPriceMult:OnChanged(function()
	state.stockPriceMult = Options.StockPriceMult.Value or 1
end)

local GradeBox = addBox(Tabs.Grading, "Grading", "award")
GradeBox:AddDropdown("GradeRarities", {
	Text = "Rarities to Grade",
	Values = RARITIES,
	Multi = true,
	Default = {},
})
GradeBox:AddToggle("AutoGrade", { Text = "Auto Grade", Default = false })
GradeBox:AddLabel("Ungraded selected rarities are never placed by Auto Place", true)

Toggles.AutoGrade:OnChanged(function()
	state.autoGrade = Toggles.AutoGrade.Value
end)
Options.GradeRarities:OnChanged(function()
	local v = Options.GradeRarities.Value
	state.gradeRarities = type(v) == "table" and v or {}
end)

-- ========================================================
-- Museum (Place 140): display items → luck + hourly gifts
-- Remotes: Events.Museum.{GetState,Donate,Withdraw,Collect,UnlockSlot,GetTopExhibits}
-- Donate(slotIndex, guid) · Withdraw(slot) · Collect(slot) · UnlockSlot(slot)
-- ========================================================
local museumEligibleCache = {} -- label -> {slotIndex?, guid, name, value}
local museumEligibleLabels = { "(refresh)" }
local museumTopCache = {}

local function museumFmtMoney(n)
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

local function museumSlotData(slots, i)
	if type(slots) ~= "table" then
		return nil
	end
	return slots[tostring(i)] or slots[i]
end

local function museumEligibleEntry(row)
	if type(row) ~= "table" then
		return nil, nil
	end
	local guid = row.guid or row.Guid or row.GUID or row.ItemGUID
	local data = row.data or row.Entry or row.item or row
	local name = (type(data) == "table" and (data.Name or data.name)) or row.Name or row.name or "?"
	local value = (type(data) == "table" and (data.BasePrice or data.Value or data.value))
		or row.Value
		or row.value
		or 0
	if type(guid) ~= "string" or guid == "" then
		return nil, nil
	end
	return guid, {
		guid = guid,
		name = tostring(name),
		value = tonumber(value) or 0,
		source = row.source or row.Source,
		vehicleGUID = row.vehicleGUID or row.VehicleGUID,
	}
end

local function museumRefreshState()
	local st = invoke("Museum", "GetState")
	if type(st) ~= "table" then
		return nil, "GetState failed"
	end
	local unlocked = tonumber(st.Unlocked) or 1
	local maxSlots = tonumber(st.MaxSlots) or unlocked
	local luck = tonumber(st.LuckTotal) or 0
	local nwLock = st.NetWorthLocked == true
	local nwReq = tonumber(st.NetWorthRequirement) or 0
	local slotLines = {}
	local pendingAny = false
	for i = 1, math.max(maxSlots, unlocked) do
		local s = museumSlotData(st.Slots, i)
		if i > unlocked then
			local cost = st.Costs and (st.Costs[tostring(i)] or st.Costs[i])
			table.insert(slotLines, string.format("#%d LOCKED · %s💎", i, tostring(cost or "?")))
		elseif type(s) == "table" and (s.ItemGUID or s.guid or s.Guid) then
			local entry = s.ItemData or s.Entry or s.item or s
			local nm = type(entry) == "table" and (entry.Name or entry.name) or "item"
			local pend = s.Pending or s.pending
			if type(pend) == "table" then
				pendingAny = true
			end
			local tag = type(pend) == "table" and " · GIFT!" or ""
			table.insert(slotLines, string.format("#%d %s%s", i, tostring(nm), tag))
		elseif nwLock then
			table.insert(slotLines, string.format("#%d need NW %s", i, museumFmtMoney(nwReq)))
		else
			table.insert(slotLines, string.format("#%d empty", i))
		end
	end
	table.clear(museumEligibleCache)
	table.clear(museumEligibleLabels)
	local eligible = st.Eligible
	if type(eligible) == "table" then
		local rows = {}
		for k, row in pairs(eligible) do
			local guid, info = museumEligibleEntry(row)
			if not guid and type(k) == "string" and type(row) == "table" then
				guid, info = museumEligibleEntry(row)
				if not guid then
					guid = row.guid or k
					if type(guid) == "string" then
						info = {
							guid = guid,
							name = tostring(row.Name or row.name or k),
							value = tonumber(row.Value or row.value or row.BasePrice) or 0,
						}
					end
				end
			elseif not guid and type(row) == "string" then
				guid = row
				info = { guid = row, name = row, value = 0 }
			end
			if guid and info then
				table.insert(rows, info)
			end
		end
		-- also array-style
		if #rows == 0 then
			for _, row in ipairs(eligible) do
				local guid, info = museumEligibleEntry(row)
				if guid and info then
					table.insert(rows, info)
				end
			end
		end
		table.sort(rows, function(a, b)
			return (a.value or 0) > (b.value or 0)
		end)
		for _, info in ipairs(rows) do
			local label = string.format("%s · %s", info.name, museumFmtMoney(info.value))
			-- uniquify
			local base, n = label, 2
			while museumEligibleCache[label] do
				label = base .. " #" .. n
				n = n + 1
			end
			museumEligibleCache[label] = info
			table.insert(museumEligibleLabels, label)
		end
	end
	if #museumEligibleLabels == 0 then
		table.insert(museumEligibleLabels, "(no eligible)")
	end
	local summary = string.format(
		"Luck %s · slots %d/%d%s",
		tostring(luck),
		unlocked,
		maxSlots,
		nwLock and (" · NW lock " .. museumFmtMoney(nwReq)) or ""
	)
	if pendingAny then
		summary = summary .. " · gift ready"
	end
	return {
		state = st,
		summary = summary,
		slotText = table.concat(slotLines, "\n"),
		pendingAny = pendingAny,
		unlocked = unlocked,
		maxSlots = maxSlots,
		luck = luck,
	}, nil
end

local function museumNotify(title, desc)
	Library:Notify({ Title = title or "Museum", Description = tostring(desc or ""), Time = 3 })
end

local function museumApplyEligibleDropdown()
	if Options.MuseumEligibleSelect and Options.MuseumEligibleSelect.SetValues then
		Options.MuseumEligibleSelect:SetValues(museumEligibleLabels)
	end
end

local function museumRefreshUi()
	local info, err = museumRefreshState()
	if not info then
		if Options.MuseumStatusLabel then
			Options.MuseumStatusLabel:SetText("Museum: " .. tostring(err or "fail"))
		end
		if Options.MuseumSlotsLabel then
			Options.MuseumSlotsLabel:SetText("—")
		end
		return nil
	end
	pcall(function()
		if Options.MuseumStatusLabel then
			Options.MuseumStatusLabel:SetText(info.summary)
		end
		if Options.MuseumSlotsLabel then
			Options.MuseumSlotsLabel:SetText(info.slotText ~= "" and info.slotText or "no slots")
		end
	end)
	museumApplyEligibleDropdown()
	return info
end

local function museumFreeSlot(st)
	st = st or invoke("Museum", "GetState")
	if type(st) ~= "table" then
		return nil
	end
	local unlocked = tonumber(st.Unlocked) or 1
	for i = 1, unlocked do
		local s = museumSlotData(st.Slots, i)
		if not (type(s) == "table" and (s.ItemGUID or s.guid or s.Guid)) then
			if st.NetWorthLocked ~= true then
				return i
			end
		end
	end
	return nil
end

local function museumOccupiedSlots(st)
	st = st or invoke("Museum", "GetState")
	local list = {}
	if type(st) ~= "table" then
		return list
	end
	local unlocked = tonumber(st.Unlocked) or 1
	for i = 1, unlocked do
		local s = museumSlotData(st.Slots, i)
		if type(s) == "table" and (s.ItemGUID or s.guid or s.Guid) then
			table.insert(list, i)
		end
	end
	return list
end

local function museumPendingSlots(st)
	st = st or invoke("Museum", "GetState")
	local list = {}
	if type(st) ~= "table" then
		return list
	end
	local unlocked = tonumber(st.Unlocked) or 1
	for i = 1, unlocked do
		local s = museumSlotData(st.Slots, i)
		if type(s) == "table" and type(s.Pending or s.pending) == "table" then
			table.insert(list, i)
		end
	end
	return list
end

local function museumDonateSelected()
	local label = Options.MuseumEligibleSelect and Options.MuseumEligibleSelect.Value
	local info = label and museumEligibleCache[label]
	if not info or not info.guid then
		museumNotify("Museum", "Pick an eligible item (Refresh first)")
		return
	end
	local st = invoke("Museum", "GetState")
	local slot = museumFreeSlot(st)
	if not slot then
		museumNotify("Museum", "No free slot (unlock / withdraw / NW)")
		return
	end
	local res = invoke("Museum", "Donate", slot, info.guid)
	if type(res) == "table" and res.success then
		museumNotify("Museum", "Donated " .. info.name .. " → slot " .. slot)
	else
		local err = type(res) == "table" and (res.error or res.Error) or tostring(res)
		museumNotify("Museum", "Donate fail: " .. tostring(err))
	end
	museumRefreshUi()
end

local function museumWithdrawAll()
	local slots = museumOccupiedSlots()
	if #slots == 0 then
		museumNotify("Museum", "Nothing to withdraw")
		return
	end
	local n = 0
	for _, i in ipairs(slots) do
		local res = invoke("Museum", "Withdraw", i)
		if type(res) == "table" and res.success ~= false then
			n = n + 1
		elseif res == true then
			n = n + 1
		end
		task.wait(0.15)
	end
	museumNotify("Museum", "Withdrawn " .. n .. "/" .. #slots)
	museumRefreshUi()
end

local function museumCollectAll()
	local st = invoke("Museum", "GetState")
	local pending = museumPendingSlots(st)
	-- also try all occupied if Pending shape unknown
	local targets = #pending > 0 and pending or museumOccupiedSlots(st)
	if #targets == 0 then
		museumNotify("Museum", "No slots to collect")
		return 0
	end
	local n = 0
	for _, i in ipairs(targets) do
		local res = invoke("Museum", "Collect", i)
		if type(res) == "table" and (res.success or res.Pending or res.ItemData) then
			n = n + 1
		elseif res == true then
			n = n + 1
		end
		task.wait(0.2)
	end
	if n > 0 then
		museumNotify("Museum", "Collect tried " .. n)
	end
	museumRefreshUi()
	return n
end

local function museumUnlockNext()
	local st = invoke("Museum", "GetState")
	if type(st) ~= "table" then
		museumNotify("Museum", "GetState failed")
		return
	end
	local unlocked = tonumber(st.Unlocked) or 1
	local maxSlots = tonumber(st.MaxSlots) or unlocked
	local nextSlot = unlocked + 1
	if nextSlot > maxSlots and maxSlots <= unlocked then
		-- try costs keys for next
		if st.Costs then
			for k in pairs(st.Costs) do
				local idx = tonumber(k)
				if idx and idx > unlocked then
					nextSlot = math.min(nextSlot == unlocked + 1 and idx or nextSlot, idx)
				end
			end
		end
	end
	if nextSlot <= unlocked then
		museumNotify("Museum", "No higher slot to unlock")
		return
	end
	local cost = st.Costs and (st.Costs[tostring(nextSlot)] or st.Costs[nextSlot])
	local res = invoke("Museum", "UnlockSlot", nextSlot)
	if type(res) == "table" and res.success then
		museumNotify("Museum", "Unlocked slot " .. nextSlot)
	else
		local err = type(res) == "table" and (res.error or res.Error) or tostring(res)
		museumNotify("Museum", "Unlock #" .. nextSlot .. " fail: " .. tostring(err) .. (cost and (" (" .. cost .. "💎)") or ""))
	end
	museumRefreshUi()
end

local function museumRefreshTop()
	local top = invoke("Museum", "GetTopExhibits")
	table.clear(museumTopCache)
	local lines = {}
	if type(top) ~= "table" then
		return "Top exhibits failed"
	end
	-- array or map of rank -> row
	local rows = {}
	if #top > 0 then
		for i, row in ipairs(top) do
			table.insert(rows, { rank = i, row = row })
		end
	else
		for k, row in pairs(top) do
			local rank = tonumber(k) or 0
			table.insert(rows, { rank = rank, row = row })
		end
		table.sort(rows, function(a, b)
			return a.rank < b.rank
		end)
	end
	for _, item in ipairs(rows) do
		if #lines >= 10 then
			break
		end
		local row = item.row
		if type(row) == "table" then
			local entry = row.Entry or row.ItemData or row
			local name = type(entry) == "table" and (entry.Name or entry.name) or "?"
			local owner = row.OwnerName or row.ownerName or "?"
			local value = row.Value or row.value or 0
			table.insert(lines, string.format(
				"#%d %s · %s · %s",
				item.rank,
				tostring(name),
				museumFmtMoney(value),
				tostring(owner)
			))
		end
	end
	return #lines > 0 and table.concat(lines, "\n") or "no top data"
end

local MuseumBox = addBox(Tabs.Museum, "Museum", "landmark")
MuseumBox:AddLabel("Luck 0 · slots —", true, "MuseumStatusLabel")
MuseumBox:AddLabel("slots…", true, "MuseumSlotsLabel")
MuseumBox:AddButton({
	Text = "Refresh State",
	Func = function()
		local info = museumRefreshUi()
		museumNotify("Museum", info and info.summary or "failed")
	end,
})
MuseumBox:AddButton({
	Text = "TP Museum",
	Func = function()
		local cf = gpsPoiMap["Museum "] or gpsPoiMap["Museum"] or TP_POINTS.Museum
		teleportTo(cf)
	end,
})
MuseumBox:AddDropdown("MuseumEligibleSelect", {
	Text = "Eligible Item",
	Values = museumEligibleLabels,
	Default = 1,
	Searchable = true,
	Tooltip = "From GetState.Eligible — Refresh State first",
})
MuseumBox:AddButton({
	Text = "Donate Selected → Free Slot",
	Func = museumDonateSelected,
	Tooltip = "Donate(slotIndex, guid)",
})
MuseumBox:AddButton({
	Text = "Withdraw All Displayed",
	Func = museumWithdrawAll,
})
MuseumBox:AddButton({
	Text = "Collect Gifts",
	Func = function()
		museumCollectAll()
	end,
	Tooltip = "Collect(slot) when Pending gift ready",
})
MuseumBox:AddToggle("AutoMuseumCollect", {
	Text = "Auto Collect Gifts",
	Default = false,
	Tooltip = "Poll GetState · Collect pending every ~30s",
})
MuseumBox:AddButton({
	Text = "Unlock Next Slot",
	Func = museumUnlockNext,
	Tooltip = "UnlockSlot(n) — costs diamonds (75 / 250…)",
})

local MuseumTopBox = addBox(Tabs.Museum, "Top Exhibits", "trophy")
MuseumTopBox:AddLabel("Refresh for top 10", true, "MuseumTopLabel")
MuseumTopBox:AddButton({
	Text = "Refresh Top 10",
	Func = function()
		local text = museumRefreshTop()
		pcall(function()
			if Options.MuseumTopLabel then
				Options.MuseumTopLabel:SetText(text)
			end
		end)
		museumNotify("Museum", "Top exhibits updated")
	end,
})

Toggles.AutoMuseumCollect:OnChanged(function()
	state.autoMuseumCollect = Toggles.AutoMuseumCollect.Value
end)

task.spawn(function()
	task.wait(1)
	pcall(museumRefreshUi)
end)

task.spawn(function()
	while state.running do
		if state.autoMuseumCollect then
			pcall(function()
				local pending = museumPendingSlots()
				if #pending > 0 then
					museumCollectAll()
				end
			end)
			task.wait(30)
		else
			task.wait(0.5)
		end
	end
end)

local InvBox = addBox(Tabs.Inventory, "Capacity", "backpack")
InvBox:AddToggle("PauseOnFull", { Text = "Auto-Pause on Full Inventory", Default = true })
InvBox:AddSlider("PauseAtPct", {
	Text = "Pause at % Full",
	Default = 90,
	Min = 1,
	Max = 100,
	Rounding = 0,
})
InvBox:AddSlider("ResumeBelow", {
	Text = "Resume Below (items)",
	Default = 10,
	Min = 0,
	Max = 200,
	Rounding = 0,
})

Toggles.PauseOnFull:OnChanged(function()
	state.pauseOnFull = Toggles.PauseOnFull.Value
end)
Options.PauseAtPct:OnChanged(function()
	state.pauseAtPct = Options.PauseAtPct.Value or 90
end)
Options.ResumeBelow:OnChanged(function()
	state.resumeBelow = Options.ResumeBelow.Value or 10
end)

	task.spawn(function()
	while state.running do
		if state.autoPlace then
			-- placing frees inventory, so no shouldPauseInventory() gate here
			-- (pause gate there deadlocks: full inv → never place → stays full)
			local ok = placeOneStockItem()
			task.wait(ok and 0.6 or 1.2)
		else
			task.wait(0.5)
		end
	end
end)

task.spawn(function()
	while state.running do
		if state.autoWash then
			washProcessSlots()
			washStartDirty()
			task.wait(1.5)
		else
			task.wait(0.5)
		end
	end
end)

task.spawn(function()
	while state.running do
		if state.autoGrade then
			gradeProcessSlots()
			gradeStartEligible()
			task.wait(1.5)
		else
			task.wait(0.5)
		end
	end
end)

-- Misc Anti-AFK
local MiscBox = addBox(Tabs.Misc, "Session", "shield")
MiscBox:AddToggle("AntiAfk", {
	Text = "Anti-AFK",
	Default = true,
	Tooltip = "VirtualUser click every 60s",
})
Toggles.AntiAfk:OnChanged(function()
	state.antiAfk = Toggles.AntiAfk.Value
end)
state.antiAfk = true

local StatusBox = addBox(Tabs.Misc, "Status", "activity")
local CashLabel = StatusBox:AddLabel("Cash: —")
local InvLabel = StatusBox:AddLabel("Inv: —")
local FlagsLabel = StatusBox:AddLabel("Flags: —", true)

task.spawn(function()
	while state.running do
		local cash = LP:GetAttribute("Cash") or 0
		local count = LP:GetAttribute("InventoryCount") or 0
		local cap = LP:GetAttribute("InventoryCap") or 0
		pcall(function()
			CashLabel:SetText(string.format("Cash: $%s", tostring(cash)))
			InvLabel:SetText(string.format("Inv: %s / %s", tostring(count), tostring(cap)))
			FlagsLabel:SetText(string.format(
				"AFK:%s Bid:%s Farm:%s Unload:%s Collect:%s Place:%s Wash:%s Grade:%s Mus:%s Pause:%s",
				state.antiAfk and "Y" or "N",
				state.autoBid and "Y" or "N",
				state.autoFarm and "Y" or "N",
				state.autoUnload and "Y" or "N",
				state.autoCollect and "Y" or "N",
				state.autoPlace and "Y" or "N",
				state.autoWash and "Y" or "N",
				state.autoGrade and "Y" or "N",
				state.autoMuseumCollect and "Y" or "N",
				shouldPauseInventory() and "Y" or "N"
			))
		end)
		task.wait(1)
	end
end)

task.spawn(function()
	while state.running do
		if state.antiAfk then
			pcall(function()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.new())
			end)
		end
		task.wait(60)
	end
end)

-- UI Settings
local MenuGroup = addBox(Tabs["UI Settings"], "Menu", "wrench")
MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
	Default = "RightShift",
	NoUI = true,
	Text = "Menu keybind",
})
MenuGroup:AddButton({
	Text = "Unload",
	Func = function()
		Library:Unload()
	end,
})
Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("ShellsHub")
SaveManager:SetFolder("ShellsHub/StorageHuntersV5")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])

getgenv().StorageHuntersObsidianCleanup = function()
	state.running = false
	for _, c in ipairs(connections) do
		pcall(function()
			c:Disconnect()
		end)
	end
	table.clear(connections)
	if bidModRef and originalSetBidPrice then
		pcall(function()
			bidModRef.SetBidPrice = originalSetBidPrice
		end)
		bidModRef = nil
		originalSetBidPrice = nil
	end
	pcall(function()
		Library:Unload()
	end)
end

Library:OnUnload(function()
	state.running = false
end)

SaveManager:LoadAutoloadConfig()

Library:Notify({ Title = "Storage Hunters", Description = "Hub loaded", Time = 3 })
