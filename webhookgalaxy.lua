-- Galaxy webhook: rotation + planets + bomb/radar stock + cosmic mutation -> Discord
-- File: galaxy-webhook.luau | live-reload label: galaxy-webhook
-- Scope: TANPA meteor. Cosmic/mutation + BigBang ikut.

local function hx(s) return (s:gsub("..", function(c) return string.char(tonumber(c, 16) or 0) end)) end
local WEBHOOK_URL = hx("68747470733a2f2f646973636f72642e636f6d2f6170692f776562686f6f6b732f313536303236323135363938383036333735372f79776e79774d5f624574316c565368576e4233435833544b346b4c65713630764f744661614f4c777a6e79306f5262514c5a505a6a314b55554e416e57556d6c776a7473")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

-- Shim: jalan juga via loadstring (tanpa live-reload)
if typeof(STATE) ~= "table" then
	STATE = {
		connect = function(sig, fn)
			return sig:Connect(fn)
		end,
		onCleanup = function() end,
		alive = function()
			return true
		end,
	}
end

-- Dedup lintas copy (ghost reload-timeout berbagi getgenv): 1 event = 1 kirim
local _genv = getgenv()
_genv.__gwSent = _genv.__gwSent or {}
local _sentAt = _genv.__gwSent
local function once(key, windowSec)
	local now = os.clock()
	if _sentAt[key] and now - _sentAt[key] < (windowSec or 600) then
		return false
	end
	_sentAt[key] = now
	return true
end

local Galaxies, Stock, Mutations
pcall(function()
	Galaxies = require(ReplicatedStorage:WaitForChild("Galaxies"))
end)
pcall(function()
	Stock = require(ReplicatedStorage:WaitForChild("Items"):WaitForChild("Stock"))
end)
pcall(function()
	Mutations = require(ReplicatedStorage:WaitForChild("Items"):WaitForChild("Mutations"))
end)

local RotationNotify
pcall(function()
	RotationNotify = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RotationNotify")
end)
local PlanetsFolder
pcall(function()
	PlanetsFolder = ReplicatedStorage:WaitForChild("Planets")
end)

local GALAXY_COLOR = {
	Common = 9807270,
	Uncommon = 5767174,
	Rare = 10047005,
	Epic = 16766720,
	Legendary = 15435867,
	Mythic = 16746496,
}
local SLOT_ORDER = { "Near", "Mid", "Far", "Deep" }
local BOMB_IDS = { "meteor_charge", "solar_wind", "comet_frost", "nova_flare", "ion_storm", "nebula_toxin", "chrono_rift", "supernova" }
local RADAR_IDS = { "pocket_pinger", "dowsing_dish", "sonar_scope", "quantum_sensor", "star_chart_array", "omniscope" }
local RARE_STOCK = { supernova = true, omniscope = true, chrono_rift = true }
-- Emoji lingkaran warna ikut rarity game (Common silver .. Mythic merah)
local RARITY_EMOJI = { "⚪", "🟢", "🔵", "🟣", "🟡", "🔴" }
local function rarityOf(id)
	local r = 1
	pcall(function()
		local t = Stock and Stock.TABLE and Stock.TABLE[id]
		if type(t) == "table" and tonumber(t.rarity) then
			r = tonumber(t.rarity)
		end
	end)
	return math.clamp(math.floor(r), 1, 6)
end

-- State panel UI sederhana (ala Antarctica)
local uiLastText = "-"
local uiLog = {}
local uiGalaxyTxt, uiPlanetTxt, uiStockTxt, uiCosmicTxt = "-", "-", "-", "-"
local refreshUI -- fwd, diisi blok UI bawah

local function uiPushLog(s)
	table.insert(uiLog, 1, os.date("%H:%M:%S") .. " " .. s)
	while #uiLog > 4 do
		table.remove(uiLog)
	end
end

-- Generation guard: copy lama (ghost reload) mati sendiri max 1 tick
_genv.__gwGen = (_genv.__gwGen or 0) + 1
local MYGEN = _genv.__gwGen
local function mine()
	return _genv.__gwGen == MYGEN
end

local function srvTime()
	local t = 0
	pcall(function()
		t = Workspace:GetServerTimeNow()
	end)
	if t and t > 0 then
		return t
	end
	return os.time()
end

local function fmtDur(sec)
	sec = math.max(0, math.floor(sec or 0))
	if sec >= 3600 then
		return string.format("%d:%02d:%02d", sec // 3600, sec % 3600 // 60, sec % 60)
	end
	return string.format("%d:%02d", sec // 60, sec % 60)
end

local function pretty(id)
	return (tostring(id):gsub("_", " "):gsub("(%l)(%w*)", function(a, b)
		return a:upper() .. b
	end))
end

local function c3int(c)
	if typeof(c) ~= "Color3" then
		return 9807270
	end
	local r = math.floor(c.R * 255 + 0.5)
	local g = math.floor(c.G * 255 + 0.5)
	local b = math.floor(c.B * 255 + 0.5)
	return r * 65536 + g * 256 + b
end

-- Game pakai <b> HTML; Discord pakai **markdown** — konversi + strip sisa tag
local function md(s)
	s = tostring(s or "")
	s = s:gsub("<b>(.-)</b>", "**%1**")
	s = s:gsub("</?[^>]+>", "")
	return s
end

-- Counter mutation harian (file persisten, tahan rejoin; hanya hari ini disimpan)
local COUNT_FILE = "galaxy-mutation-counts.json"
local counts = {}
local lastCountKey = nil
local function loadCounts()
	pcall(function()
		if isfile(COUNT_FILE) then
			local data = HttpService:JSONDecode(readfile(COUNT_FILE))
			if type(data) == "table" then
				counts = data
			end
		end
	end)
	local d = os.date("%Y-%m-%d")
	for k in pairs(counts) do
		if k ~= d then
			counts[k] = nil
		end
	end
end
local function saveCounts()
	pcall(function()
		writefile(COUNT_FILE, HttpService:JSONEncode(counts))
	end)
end
local function bumpCount(evId)
	local d = os.date("%Y-%m-%d")
	counts[d] = counts[d] or {}
	counts[d][evId] = (counts[d][evId] or 0) + 1
	for k in pairs(counts) do
		if k ~= d then
			counts[k] = nil
		end
	end
	saveCounts()
	return counts[d][evId]
end
local function todayCount(evId)
	local d = counts[os.date("%Y-%m-%d")]
	return (d and d[evId]) or 0
end
local function countSummary()
	local d = counts[os.date("%Y-%m-%d")] or {}
	local parts = {}
	for id, n in pairs(d) do
		table.insert(parts, { id = id, n = n })
	end
	if #parts == 0 then
		return "-"
	end
	table.sort(parts, function(a, b)
		return a.n > b.n
	end)
	local out = {}
	for _, p in ipairs(parts) do
		table.insert(out, p.id .. " x" .. tostring(p.n))
	end
	return table.concat(out, " • ")
end

local function discord(payload)
	local body = HttpService:JSONEncode(payload)
	local ok, res = pcall(function()
		return request({
			Url = WEBHOOK_URL .. "?wait=true",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = body,
		})
	end)
	if not ok then
		warn("[gwebhook] request gagal: " .. tostring(res):sub(1, 200))
		return false
	end
	if type(res) == "table" and not res.Success and res.StatusCode ~= 200 and res.StatusCode ~= 204 then
		warn("[gwebhook] http " .. tostring(res.StatusCode) .. " " .. tostring(res.Body):sub(1, 200))
		return false
	end
	return true
end

local function send(title, desc, color, fields)
	print("[gwebhook] kirim: " .. title)
	local okSend = discord({
		username = "Galaxy Watch",
		content = title,
		embeds = { {
			title = title,
			description = desc,
			color = color or 9807270,
			fields = fields or {},
			timestamp = DateTime.now():ToIsoDate(),
		} },
	})
	uiLastText = (okSend and "OK " or "GAGAL ") .. os.date("%H:%M:%S")
	uiPushLog((okSend and "✓ " or "✗ ") .. title)
	if refreshUI then
		refreshUI()
	end
	return okSend
end

local function curGalaxy()
	if type(Galaxies) ~= "table" then
		return nil
	end
	local ok, g = pcall(function()
		return Galaxies.galaxyFor()
	end)
	if ok and type(g) == "table" and g.name then
		return g
	end
	return nil
end

local function curStamp()
	if type(Galaxies) ~= "table" then
		return "?"
	end
	local ok, s = pcall(function()
		return Galaxies.stamp()
	end)
	if ok and s then
		return tostring(s)
	end
	return "?"
end

local function planetRows()
	local rows = {}
	if not PlanetsFolder then
		return rows
	end
	for _, p in ipairs(PlanetsFolder:GetChildren()) do
		local ok, a = pcall(function()
			return p:GetAttributes()
		end)
		if ok and type(a) == "table" and a.Slot then
			table.insert(rows, {
				slot = tostring(a.Slot),
				planet = tostring(a.PlanetName or p.Name),
				galaxy = tostring(a.Galaxy or "?"),
				rarity = tostring(a.GalaxyRarity or "?"),
				bonus = tonumber(a.ValueBonus) or 0,
				hard = tonumber(a.Hardness) or 0,
			})
		end
	end
	local ord = { Near = 1, Mid = 2, Far = 3, Deep = 4 }
	table.sort(rows, function(x, y)
		return (ord[x.slot] or 9) < (ord[y.slot] or 9)
	end)
	return rows
end

local function stockAmounts(period)
	if type(Stock) ~= "table" then
		return {}, false
	end
	local ok, ov = pcall(function()
		return Stock.override(period)
	end)
	if ok and type(ov) == "table" and type(ov.amounts) == "table" then
		return ov.amounts, true
	end
	local t = {}
	for _, id in ipairs(BOMB_IDS) do
		local ok2, v = pcall(function()
			return Stock.rolledAmount(id, period)
		end)
		t[id] = (ok2 and tonumber(v)) or 0
	end
	for _, id in ipairs(RADAR_IDS) do
		local ok2, v = pcall(function()
			return Stock.rolledAmount(id, period)
		end)
		t[id] = (ok2 and tonumber(v)) or 0
	end
	return t, false
end

local function stockLines(ids, amounts)
	local out = {}
	for _, id in ipairs(ids) do
		local n = tonumber(amounts[id]) or 0
		if n > 0 then
			local mark = RARE_STOCK[id] and " ★" or ""
			table.insert(out, RARITY_EMOJI[rarityOf(id)] .. " " .. pretty(id) .. " x" .. tostring(n) .. mark)
		end
	end
	if #out == 0 then
		return "— kosong"
	end
	return table.concat(out, "\n")
end

local function checkRotation()
	local g = curGalaxy()
	if not g then
		return
	end
	local stamp = curStamp()
	if not once("gw:rot:" .. stamp, 3600) then
		return
	end
	local rotSec = 3600
	pcall(function()
		rotSec = Galaxies.ROTATION_SECONDS or 3600
	end)
	local left = rotSec - (srvTime() % rotSec)
	local rows = planetRows()
	uiGalaxyTxt = tostring(g.name) .. " (" .. tostring(g.rarity or "?") .. ")"
	do
		local _pn = {}
		for _, r in ipairs(rows) do
			table.insert(_pn, r.planet)
		end
		uiPlanetTxt = #_pn > 0 and table.concat(_pn, " / ") or "-"
	end
	local pfields = {}
	for _, r in ipairs(rows) do
		table.insert(pfields, {
			name = r.slot .. ": " .. r.planet,
			value = string.format("hard %d | bonus +%d%%", r.hard, math.floor(r.bonus * 100 + 0.5)),
			inline = true,
		})
	end
	send(
		"🌌 Galaxy: " .. tostring(g.name) .. " (" .. tostring(g.rarity or "?") .. ")",
		string.format("Bonus +%d%% | next rotation %s", math.floor((tonumber(g.bonus) or 0) * 100 + 0.5), fmtDur(left)),
		GALAXY_COLOR[tostring(g.rarity)] or 9807270,
		pfields
	)
end

local function checkStock(force)
	if type(Stock) ~= "table" then
		return
	end
	local period = 0
	pcall(function()
		period = Stock.period()
	end)
	if not force and not once("gw:stock:" .. tostring(period), 700) then
		return
	end
	if force and not once("gw:stock:" .. tostring(period), 5) then
		return
	end
	local amounts, isOv = stockAmounts(period)
	do
		local _bt, _rt = 0, 0
		for _, id in ipairs(BOMB_IDS) do
			_bt += tonumber(amounts[id]) or 0
		end
		for _, id in ipairs(RADAR_IDS) do
			_rt += tonumber(amounts[id]) or 0
		end
		uiStockTxt = string.format("B:%d R:%d", _bt, _rt)
	end
	local left = 0
	pcall(function()
		left = Stock.secondsLeft()
	end)
	local title = "🛒 Stock restock"
	if isOv then
		title ..= " (override)"
	end
	send(title, "Next restock " .. fmtDur(left), 5767174, {
		{ name = "Bombs", value = stockLines(BOMB_IDS, amounts), inline = true },
		{ name = "Radars", value = stockLines(RADAR_IDS, amounts), inline = true },
	})
end

local function checkMutation(force)
	local ce = Workspace:GetAttribute("CosmicEvent")
	local ceUntil = tonumber(Workspace:GetAttribute("CosmicEventUntil")) or 0
	local ceNext = tonumber(Workspace:GetAttribute("CosmicEventNext")) or 0
	local bbUntil = tonumber(Workspace:GetAttribute("BigBangUntil")) or 0
	local now = srvTime()
	local key = tostring(ce or "none") .. ":" .. tostring(ceUntil) .. ":" .. tostring(bbUntil)
	if not force and not once("gw:cos:" .. key, 200) then
		return
	end
	if force and not once("gw:cos:" .. key, 5) then
		return
	end
	if ce ~= nil and now < ceUntil and type(Mutations) == "table" then
		local ev = Mutations.eventById and Mutations.eventById[tostring(ce)]
		if ev then
			local mut = Mutations.byId and Mutations.byId[ev.mutation]
			local desc = md(ev.text)
			if mut then
				desc ..= string.format("\n%s: %sx cash, %sx luck", tostring(mut.name), tostring(mut.value), tostring(mut.luck))
			end
			desc ..= "\nSisa " .. fmtDur(ceUntil - now)
			if key ~= lastCountKey then
				lastCountKey = key
				bumpCount(tostring(ce))
			end
			desc ..= string.format("\nHari ini: %s x%d", tostring(ev.name or ce), todayCount(tostring(ce)))
			uiCosmicTxt = tostring(ev.name or ce) .. " sisa " .. fmtDur(ceUntil - now)
			send("✨ " .. tostring(ev.name or ce), desc, (mut and c3int(mut.color)) or 9807270, {})
			return
		end
		uiCosmicTxt = tostring(ce) .. " sisa " .. fmtDur(ceUntil - now)
		send("✨ Cosmic: " .. tostring(ce), "Sisa " .. fmtDur(ceUntil - now), 9807270, {})
		return
	end
	if bbUntil > now then
		if key ~= lastCountKey then
			lastCountKey = key
			bumpCount("BigBang")
		end
		uiCosmicTxt = "BIG BANG sisa " .. fmtDur(bbUntil - now)
		send("💥 THE BIG BANG", string.format("Genesis | sisa %s\nHari ini: BigBang x%d", fmtDur(bbUntil - now), todayCount("BigBang")), 16766720, {})
		return
	end
	if ceNext > now then
		uiCosmicTxt = "idle, next " .. fmtDur(ceNext - now)
		print("[gwebhook] mutation idle, next " .. fmtDur(ceNext - now))
	else
		uiCosmicTxt = "idle"
		print("[gwebhook] mutation idle")
	end
end

-- Panel UI sederhana (ala Antarctica): status + tombol kirim semua + minimize
local lblGalaxy, lblTimer, lblPlanet, lblStock, lblCosmic, lblCount, lblLast, lblLog
function refreshUI()
	if not lblGalaxy then
		return
	end
	local rotSec = 3600
	pcall(function()
		rotSec = (type(Galaxies) == "table" and Galaxies.ROTATION_SECONDS) or 3600
	end)
	lblGalaxy.Text = "Galaxy: " .. uiGalaxyTxt
	lblTimer.Text = "Rotation: " .. fmtDur(rotSec - (srvTime() % rotSec))
	lblPlanet.Text = "Planet: " .. uiPlanetTxt
	local sleft = 0
	pcall(function()
		sleft = (type(Stock) == "table" and Stock.secondsLeft()) or 0
	end)
	lblStock.Text = "Stock: " .. uiStockTxt .. " • restock " .. fmtDur(sleft)
	lblCosmic.Text = "Cosmic: " .. uiCosmicTxt
	lblCount.Text = "Count: " .. countSummary()
	lblLast.Text = "Terakhir: " .. uiLastText
	lblLog.Text = table.concat(uiLog, "\n")
end

local function sendAll()
	table.clear(_sentAt)
	checkRotation()
	checkStock(true)
	checkMutation(true)
	refreshUI()
end

do
	local LocalPlayer = Players.LocalPlayer
	if not LocalPlayer then
		warn("[gwebhook] tanpa LocalPlayer, panel skip")
	else
		local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
		local old = PlayerGui:FindFirstChild("GalaxyWebhookGui")
		if old then
			old:Destroy()
		end
		local gui = Instance.new("ScreenGui")
		gui.Name = "GalaxyWebhookGui"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 90
		gui.Parent = PlayerGui
		STATE.onCleanup(function()
			if gui then
				gui:Destroy()
			end
		end)
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(0, 260, 0, 288)
		frame.Position = UDim2.new(0, 12, 0.35, 0)
		frame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
		frame.BorderSizePixel = 0
		frame.Active = true
		frame.Draggable = true
		frame.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(60, 65, 80)
		stroke.Thickness = 1
		stroke.Parent = frame
		local title = Instance.new("TextLabel")
		title.Position = UDim2.new(0, 10, 0, 6)
		title.Size = UDim2.new(1, -48, 0, 20)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBold
		title.TextSize = 14
		title.TextColor3 = Color3.fromRGB(255, 255, 255)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = "🌌 Galaxy Webhook"
		title.Parent = frame
		local uiBody = Instance.new("Frame")
		uiBody.Position = UDim2.new(0, 0, 0, 28)
		uiBody.Size = UDim2.new(1, 0, 1, -28)
		uiBody.BackgroundTransparency = 1
		uiBody.Parent = frame
		local function mkBody(y, h, size, color)
			local l = Instance.new("TextLabel")
			l.Position = UDim2.new(0, 10, 0, y)
			l.Size = UDim2.new(1, -20, 0, h)
			l.BackgroundTransparency = 1
			l.Font = Enum.Font.Gotham
			l.TextSize = size
			l.TextColor3 = color
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.TextTruncate = Enum.TextTruncate.AtEnd
			l.Parent = uiBody
			return l
		end
		lblGalaxy = mkBody(0, 16, 13, Color3.fromRGB(255, 224, 77))
		lblTimer = mkBody(17, 16, 12, Color3.fromRGB(170, 175, 190))
		lblPlanet = mkBody(34, 16, 12, Color3.fromRGB(150, 200, 255))
		lblStock = mkBody(51, 16, 13, Color3.fromRGB(140, 220, 150))
		lblCosmic = mkBody(68, 16, 13, Color3.fromRGB(230, 150, 255))
		lblCount = mkBody(85, 16, 12, Color3.fromRGB(255, 200, 90))
		lblLast = mkBody(102, 16, 12, Color3.fromRGB(170, 175, 190))
		lblLog = mkBody(119, 43, 11, Color3.fromRGB(130, 135, 150))
		lblLog.TextYAlignment = Enum.TextYAlignment.Top
		local btnAll = Instance.new("TextButton")
		btnAll.Position = UDim2.new(0, 10, 0, 167)
		btnAll.Size = UDim2.new(0.62, -14, 0, 28)
		btnAll.BackgroundColor3 = Color3.fromRGB(70, 130, 200)
		btnAll.Font = Enum.Font.GothamBold
		btnAll.TextSize = 13
		btnAll.TextColor3 = Color3.fromRGB(255, 255, 255)
		btnAll.Text = "📨 Kirim Semua"
		btnAll.Parent = uiBody
		local btnAllCorner = Instance.new("UICorner")
		btnAllCorner.CornerRadius = UDim.new(0, 6)
		btnAllCorner.Parent = btnAll
		local btnMin = Instance.new("TextButton")
		btnMin.Position = UDim2.new(1, -38, 0, 6)
		btnMin.Size = UDim2.new(0, 28, 0, 20)
		btnMin.BackgroundColor3 = Color3.fromRGB(45, 48, 58)
		btnMin.Font = Enum.Font.GothamBold
		btnMin.TextSize = 12
		btnMin.TextColor3 = Color3.fromRGB(200, 205, 215)
		btnMin.Text = "–"
		btnMin.Parent = frame
		local btnMinCorner = Instance.new("UICorner")
		btnMinCorner.CornerRadius = UDim.new(0, 6)
		btnMinCorner.Parent = btnMin
		local btnSend = Instance.new("TextButton")
		btnSend.Position = UDim2.new(0.62, 0, 0, 167)
		btnSend.Size = UDim2.new(0.38, -10, 0, 28)
		btnSend.BackgroundColor3 = Color3.fromRGB(60, 160, 90)
		btnSend.Font = Enum.Font.GothamBold
		btnSend.TextSize = 13
		btnSend.TextColor3 = Color3.fromRGB(255, 255, 255)
		btnSend.Text = "📤 Kirim"
		btnSend.Parent = uiBody
		local btnSendCorner = Instance.new("UICorner")
		btnSendCorner.CornerRadius = UDim.new(0, 6)
		btnSendCorner.Parent = btnSend
		local box = Instance.new("TextBox")
		box.Position = UDim2.new(0, 10, 0, 200)
		box.Size = UDim2.new(1, -20, 0, 26)
		box.BackgroundColor3 = Color3.fromRGB(30, 32, 40)
		box.Font = Enum.Font.Gotham
		box.TextSize = 13
		box.TextColor3 = Color3.fromRGB(255, 255, 255)
		box.PlaceholderColor3 = Color3.fromRGB(120, 125, 140)
		box.PlaceholderText = "Ketik pesan webhook..."
		box.Text = ""
		box.ClearTextOnFocus = false
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.Parent = uiBody
		local boxCorner = Instance.new("UICorner")
		boxCorner.CornerRadius = UDim.new(0, 6)
		boxCorner.Parent = box
		local EMOJIS = { "🌌", "✨", "💥", "🛒", "⭐", "🔥", "💎", "🚀" }
		for i, e in ipairs(EMOJIS) do
			local b = Instance.new("TextButton")
			b.Position = UDim2.new(0, 10 + (i - 1) * 29, 0, 230)
			b.Size = UDim2.new(0, 26, 0, 24)
			b.BackgroundColor3 = Color3.fromRGB(35, 38, 48)
			b.Font = Enum.Font.Gotham
			b.TextSize = 14
			b.TextColor3 = Color3.fromRGB(255, 255, 255)
			b.Text = e
			b.Parent = uiBody
			local bc = Instance.new("UICorner")
			bc.CornerRadius = UDim.new(0, 6)
			bc.Parent = b
			STATE.connect(b.MouseButton1Click, function()
				box.Text = box.Text .. e
				pcall(function()
					box:CaptureFocus()
				end)
			end)
		end
		local open = true
		STATE.connect(btnAll.MouseButton1Click, function()
			task.spawn(sendAll)
		end)
		STATE.connect(btnSend.MouseButton1Click, function()
			local t = box.Text:gsub("^%s+", ""):gsub("%s+$", "")
			if t == "" then
				return
			end
			box.Text = ""
			task.spawn(function()
				send("💬 " .. t:sub(1, 80), t, 5767174, {})
			end)
		end)
		STATE.connect(btnMin.MouseButton1Click, function()
			open = not open
			uiBody.Visible = open
			btnMin.Text = open and "–" or "+"
			frame.Size = open and UDim2.new(0, 260, 0, 288) or UDim2.new(0, 260, 0, 34)
		end)
		refreshUI()
	end
end

if RotationNotify then
	STATE.connect(RotationNotify.OnClientEvent, function()
		if not mine() then
			return
		end
		task.spawn(function()
			checkRotation()
		end)
	end)
	print("[gwebhook] RotationNotify hook aktif")
end

task.spawn(function()
	loadCounts()
	checkRotation()
	checkStock(true)
	checkMutation(true)
	print("[gwebhook] sync awal done (gen " .. tostring(MYGEN) .. ")")
	while mine() and STATE.alive() do
		task.wait(15)
		if not mine() or not STATE.alive() then
			break
		end
		local ok, err = pcall(function()
			checkRotation()
			checkStock(false)
			checkMutation(false)
		end)
		if not ok then
			warn("[gwebhook] loop err: " .. tostring(err):sub(1, 200))
		end
		pcall(function()
			if refreshUI then
				refreshUI()
			end
		end)
	end
	print("[gwebhook] stop")
end)
print("[gwebhook] loaded gen " .. tostring(MYGEN))
