-- Antarctica event webhook: weather + meteor + bomb restock -> Discord
-- File: event-webhook.luau | live-reload label: event-webhook
-- Sinyal: WeatherRemotes.State / MeteorRemotes.Active / BombRemotes.ShopState

local function hx(s) return (s:gsub("..", function(c) return string.char(tonumber(c, 16)) end)) end
local WEBHOOK_URL = hx("68747470733A2F2F646973636F72642E636F6D2F6170692F776562686F6F6B732F313534393239333936343738323333383034382F3172753575373449756576377037716C366738766439314667786F576D6764443056534C76594B646B5645614A652D5733537A52554A776E414C4663543130374162617A")
local MENTION = "<@&1539600129412309022>"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")

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

local LocalPlayer = Players.LocalPlayer

-- Gate username: hanya jalan di akun terdaftar
local ALLOWED = { ["7upIRSEE"] = true }
if not ALLOWED[LocalPlayer.Name] then
	warn("[webhook] stop: username " .. tostring(LocalPlayer.Name) .. " tak terdaftar")
	return
end
local WeatherRemotes = ReplicatedStorage:WaitForChild("WeatherRemotes")
local MeteorRemotes = ReplicatedStorage:WaitForChild("MeteorRemotes")
local BombRemotes = ReplicatedStorage:WaitForChild("BombRemotes")

local WState = WeatherRemotes:WaitForChild("State")
local WPhaseEnd = WeatherRemotes:WaitForChild("PhaseEnd")
local WNext = WeatherRemotes:WaitForChild("NextEventStart")
local MActive = MeteorRemotes:WaitForChild("Active")
local MPhase = MeteorRemotes:WaitForChild("Phase")
local MImpact = MeteorRemotes:WaitForChild("ImpactPos")
local MZoneEnd = MeteorRemotes:WaitForChild("ZoneEnd")
local MEvent = MeteorRemotes:WaitForChild("Event")
local ShopState = BombRemotes:WaitForChild("ShopState")
local AbuseRemotes = ReplicatedStorage:WaitForChild("AdminAbuseRemotes")
local AbuseStarted = AbuseRemotes:WaitForChild("Started")
local AbuseAllEnd = AbuseRemotes:WaitForChild("AllEnd")
local MountainRemotes = ReplicatedStorage:WaitForChild("MountainRemotes")
local MtState = MountainRemotes:WaitForChild("State")
local MtRotationEnd = MountainRemotes:WaitForChild("RotationEnd")
local MtChanged = MountainRemotes:WaitForChild("Changed")

local MountainData
pcall(function()
	MountainData = require(ReplicatedStorage:WaitForChild("MountainData"))
end)

local WeatherData = require(ReplicatedStorage:WaitForChild("WeatherData"))
local BombData = require(ReplicatedStorage:WaitForChild("BombData"))

local function asInt(v)
	return math.floor(tonumber(v) or 0)
end
local PLACE_ID = tostring(game.PlaceId)
local JOB_ID = tostring(game.JobId)
local GAME_LINK = "https://www.roblox.com/games/" .. PLACE_ID

local COLOR = {
	NormalWeather = 9807270,
	Rain = 2550221,
	Blizzard = 10047005,
	AcidRain = 4620980,
	Thunder = 2062263,
	Starfall = 16766720,
	Lucky = 11788715,
	Molten = 16746496,
	Aurora = 7971839,
}

local lastWeather = WState.Value
local lastMActive = MActive.Value
local lastMPhase = MPhase.Value
local lastStockSig = nil
local lastStockTotal = nil
local lastDivine = nil
local lastRefreshIn = nil
local lastGuiPoll = 0
local broadcastSynced = false
local lastAfkPulse = 0
local lastAbuse = false
local lastMountain = MtState.Value

local function abuseActive()
	local ae = asInt(AbuseAllEnd.Value)
	if ae <= 0 then
		return false, ae
	end
	local srv = 0
	pcall(function()
		srv = workspace:GetServerTimeNow()
	end)
	if srv <= 0 then
		return false, ae
	end
	return srv < ae, ae
end

-- Anti-AFK (menyatu): lumpuhkan Idled bawaan + denyut 4 menit di loop utama
do
	for _, c in ipairs(getconnections(LocalPlayer.Idled)) do
		pcall(function()
			c:Disable()
		end)
	end
	STATE.connect(LocalPlayer.Idled, function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new(0, 0))
		print("[antiafk] Idled dipukul " .. os.date("%H:%M:%S"))
	end)
	print("[antiafk] aktif (menyatu webhook)")
end

-- Dedup lintas copy (ghost reload-timeout berbagi getgenv): 1 event = 1 kirim
local _genv = getgenv()
_genv.__whSent = _genv.__whSent or {}
local _sentAt = _genv.__whSent
local function once(key, windowSec)
	local now = os.clock()
	if _sentAt[key] and now - _sentAt[key] < (windowSec or 600) then
		return false
	end
	_sentAt[key] = now
	return true
end
local uiLastText = "-"
local uiLog = {}
local refreshUI

local function uiPushLog(s)
	table.insert(uiLog, 1, os.date("%H:%M:%S") .. " " .. s)
	while #uiLog > 4 do
		table.remove(uiLog)
	end
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
		warn("[webhook] request gagal: " .. tostring(res):sub(1, 200))
		return false
	end
	if type(res) == "table" and not res.Success and res.StatusCode ~= 200 and res.StatusCode ~= 204 then
		warn("[webhook] http " .. tostring(res.StatusCode) .. " " .. tostring(res.Body):sub(1, 200))
		return false
	end
	return true
end

local function baseFields()
	return {}
end

local function send(title, desc, color, extraFields, ping)
	if ping == nil then
		ping = true
	end
	local fields = baseFields()
	if extraFields then
		for _, f in ipairs(extraFields) do
			table.insert(fields, f)
		end
	end
	print("[webhook] kirim: " .. title)
	local okSend = discord({
		username = "Antarctica Watch",
		content = (ping and ("Halo " .. MENTION .. "! ") or "") .. title,
		allowed_mentions = { parse = { "roles", "users" } },
		embeds = { {
			title = title,
			description = desc,
			color = color or 9807270,
			fields = fields,
			timestamp = DateTime.now():ToIsoDate(),
		} },
	})
	uiLastText = (okSend and "OK " or "GAGAL ") .. os.date("%H:%M:%S")
	uiPushLog((okSend and "✓ " or "✗ ") .. title)
	return okSend
end

local function weatherDesc(id)
	local info = WeatherData.byId and WeatherData.byId[id]
	if not info or id == "NormalWeather" then
		return "Cuaca clear."
	end
	return string.format(
		"**%s** (%s) — mutasi `%s`, mult x%d, luck +%d",
		info.name or id, info.rarity or "?", info.mutation or "?", info.mult or 1, info.luck or 0
	)
end

local function weatherTimers()
	local now = os.time()
	local pe = asInt(WPhaseEnd.Value)
	local nx = asInt(WNext.Value)
	local parts = {}
	if pe > now then
		table.insert(parts, string.format("Berakhir <t:%d:R>", pe))
	end
	if nx > now then
		table.insert(parts, string.format("Event berikut <t:%d:R>", nx))
	end
	if #parts == 0 then
		return "Timer tak ada."
	end
	return table.concat(parts, " • ")
end

local function notifyWeather(state)
	if state == "NormalWeather" then
		return
	end
	if not once("w:" .. tostring(state), 600) then
		return
	end
	send("🌦️ Cuaca mulai: " .. tostring(state), weatherDesc(state) .. "\n" .. weatherTimers(), COLOR[state] or 9807270)
end

local function notifyMeteor(kind)
	if not once("m:aktif", 900) then
		return
	end
	local now = os.time()
	local ze = asInt(MZoneEnd.Value)
	local extra = {}
	if ze > now then
		table.insert(extra, { name = "Zona tutup", value = string.format("<t:%d:R>", ze), inline = true })
	end
	send("☄️ " .. kind, "Aktif=`true`", 16746496, extra)
end

local function mountainName(id)
	if type(MountainData) == "table" then
		if MountainData.byId and MountainData.byId[id] then
			return MountainData.byId[id].name or tostring(id)
		end
		for _, m in ipairs(MountainData) do
			if type(m) == "table" and m.id == id then
				return m.name or tostring(id)
			end
		end
	end
	return tostring(id)
end

local function notifyMountain(state)
	if not once("mt:" .. tostring(state), 1200) then
		return
	end
	local rot = asInt(MtRotationEnd.Value)
	local extra = {}
	if rot > os.time() then
		table.insert(extra, { name = "Rotasi berikut", value = string.format("<t:%d:R>", rot), inline = true })
	end
	send("⛰️ Gunung: " .. mountainName(state), "Rotasi tiap jam.", 10047005, extra, false)
end

local function stockSig(stock)
	local parts = {}
	for _, entry in ipairs(BombData.List) do
		table.insert(parts, entry.id .. ":" .. tostring(stock[entry.id] or 0))
	end
	return table.concat(parts, "|")
end

local function stockTotal(stock)
	local n = 0
	for _, entry in ipairs(BombData.List) do
		n += (stock[entry.id] or 0)
	end
	return n
end

local function stockLines(stock)
	local lines = {}
	for _, entry in ipairs(BombData.List) do
		local c = stock[entry.id] or 0
		if c > 0 then
			table.insert(lines, string.format("• %s x%d", entry.displayName or entry.id, c))
		end
	end
	if #lines == 0 then
		return "_Stok kosong semua._"
	end
	return table.concat(lines, "\n")
end

local function notifyAbuse()
	if not once("aa", 1800) then
		return
	end
	local on, ae = abuseActive()
	local extra = {}
	if on then
		table.insert(extra, { name = "Berakhir", value = string.format("<t:%d:R>", ae), inline = true })
	end
	send("🔥 ADMIN ABUSE!", "Event admin aktif. Gas farm!", 16724582, extra)
end

local function notifyRestock(stock, refreshIn)
	if not once("r:" .. stockSig(stock), 900) then
		return
	end
	local divine = stock["DivineBomb"] or 0
	local isDivine = divine > 0 and (lastDivine == 0 or lastDivine == nil)
	local title = isDivine and "✨ DIVINE BOMB RESTOCK!" or "💣 Bom restock!"
	local desc = isDivine and "Divine Bomb tersedia! Gas beli sebelum habis." or "Stok toko bom reset."
	local color = isDivine and 16766720 or 4620980
	local extra = { { name = "Stok", value = stockLines(stock):sub(1, 900), inline = false } }
	if divine > 0 then
		table.insert(extra, 1, { name = "Divine", value = string.format("x%d — 25B, 30 radius, 20 crystal", divine), inline = true })
	end
	if refreshIn and refreshIn > 0 then
		table.insert(extra, 1, { name = "Restock berikut", value = string.format("<t:%d:R>", os.time() + math.floor(refreshIn)), inline = true })
	end
	send(title, desc, color, extra, isDivine)
end

local function readGuiStock()
	local ok, stock = pcall(function()
		local gui = LocalPlayer.PlayerGui:FindFirstChild("BombShopGui")
		if not gui then
			return nil
		end
		local window = gui:FindFirstChild("Window")
		local body = window and window:FindFirstChild("Body")
		if not body then
			return nil
		end
		local t = {}
		for _, entry in ipairs(BombData.List) do
			local slot = body:FindFirstChild("Slot_" .. entry.id)
			local card = slot and slot:FindFirstChild("Card")
			local label = card and card:FindFirstChild("Stock")
			if label and label:IsA("TextLabel") then
				local n = tonumber(string.match(label.Text, "X(%d+)")) or 0
				t[entry.id] = n
			end
		end
		return t
	end)
	if ok then
		return stock
	end
	return nil
end

local function handleShopStock(stock, refreshIn)
	if type(stock) ~= "table" then
		return
	end
	local sig = stockSig(stock)
	local total = stockTotal(stock)
	local divineNow = stock["DivineBomb"] or 0
	if refreshIn then
		-- Reset timer 0 -> besar = restock baru saja terjadi
		if lastRefreshIn and lastRefreshIn < 60 and refreshIn > 3000 and lastStockSig and sig ~= lastStockSig then
			notifyRestock(stock, refreshIn)
		elseif lastStockTotal and total > lastStockTotal + 1 then
			-- Stok naik signifikan tanpa lihat timer = restock
			notifyRestock(stock, refreshIn)
		elseif lastDivine == 0 and divineNow > 0 then
			-- Divine muncul tanpa total naik banyak (misal Divine 0->1, total +1 saja)
			notifyRestock(stock, refreshIn)
		end
		lastRefreshIn = refreshIn
	elseif lastStockTotal == nil or sig ~= lastStockSig then
		-- Poll GUI / data tanpa timer: update baseline diam saja.
		-- Notifikasi restock hanya dari broadcast server (ada refreshIn).
	end
	lastStockSig = sig
	lastStockTotal = total
	lastDivine = divineNow
end

-- Event: cuaca ganti (Value replicate)
STATE.connect(WState:GetPropertyChangedSignal("Value"), function()
	local s = WState.Value
	if s ~= lastWeather then
		lastWeather = s
		notifyWeather(s)
	end
end)

-- Event: meteor aktif saja (+countdown zona tutup di isi pesan)
STATE.connect(MActive:GetPropertyChangedSignal("Value"), function()
	local a = MActive.Value
	if a ~= lastMActive then
		lastMActive = a
		if a then
			notifyMeteor("METEOR JATUH!")
		end
	end
end)

-- Event: gunung rotasi (Changed + Value + poll)
STATE.connect(MtChanged.OnClientEvent, function(p1)
	local s = MtState.Value
	if type(p1) == "string" and p1 ~= "" then
		s = p1
	end
	if s ~= lastMountain then
		lastMountain = s
	end
	notifyMountain(s)
end)
STATE.connect(MtState:GetPropertyChangedSignal("Value"), function()
	local s = MtState.Value
	if s ~= lastMountain then
		lastMountain = s
		notifyMountain(s)
	end
end)

-- Event: admin abuse mulai (Started) + tangkap via AllEnd di poll
STATE.connect(AbuseStarted.OnClientEvent, function()
	lastAbuse = true
	notifyAbuse()
end)

-- Event: bom ShopState broadcast (stock + refreshIn)
STATE.connect(ShopState.OnClientEvent, function(p1)
	if typeof(p1) ~= "table" then
		return
	end
	if p1.stock then
		if not broadcastSynced then
			-- Sinkronisasi pertama: baseline diam, bukan restock
			broadcastSynced = true
			lastStockSig = stockSig(p1.stock)
			lastStockTotal = stockTotal(p1.stock)
			lastDivine = p1.stock["DivineBomb"] or 0
			if p1.refreshIn then
				lastRefreshIn = p1.refreshIn
			end
			refreshUI()
			return
		end
		handleShopStock(p1.stock, p1.refreshIn)
	elseif p1.refreshIn then
		lastRefreshIn = p1.refreshIn
	end
end)

-- UI status sederhana (native, draggable)
local uiBody, lblWeather, lblTimer, lblMeteor, lblMountain, lblBomb, lblLast, lblLog
local function fmtCountdown(unixTs)
	local d = unixTs - os.time()
	if d < 0 then
		d = 0
	end
	return string.format("%02d:%02d", math.floor(d / 60), d % 60)
end
function refreshUI()
	if not lblWeather then
		return
	end
	lblWeather.Text = "Cuaca: " .. tostring(lastWeather)
	local pe = asInt(WPhaseEnd.Value)
	local nx = asInt(WNext.Value)
	local now = os.time()
	local t = {}
	if pe > now then
		table.insert(t, "akhir " .. fmtCountdown(pe))
	end
	if nx > now then
		table.insert(t, "event " .. fmtCountdown(nx))
	end
	lblTimer.Text = "Timer: " .. (#t > 0 and table.concat(t, " • ") or "-")
	local mph = tostring(lastMPhase)
	lblMeteor.Text = "Meteor: " .. (lastMActive and "AKTIF!" or ("-" .. (mph ~= "" and (" (" .. mph .. ")") or "")))
	local rot = asInt(MtRotationEnd.Value)
	lblMountain.Text = "Gunung: " .. mountainName(lastMountain)
		.. (rot > os.time() and (" • " .. fmtCountdown(rot)) or "")
	lblBomb.Text = "Bom: "
		.. (lastStockTotal ~= nil and (tostring(lastStockTotal) .. " stok") or "?")
		.. (lastRefreshIn and (" • restock " .. fmtCountdown(os.time() + math.floor(lastRefreshIn))) or "")
	lblLast.Text = "Terakhir: " .. uiLastText
	lblLog.Text = table.concat(uiLog, "\n")
end
do
	local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
	local old = PlayerGui:FindFirstChild("WebhookMonitorGui")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "WebhookMonitorGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 90
	gui.Parent = PlayerGui
	STATE.onCleanup(function()
		if gui then
			gui:Destroy()
		end
	end)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 260, 0, 254)
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
	local function mkLabel(y, h, size, color)
		local l = Instance.new("TextLabel")
		l.Position = UDim2.new(0, 10, 0, y)
		l.Size = UDim2.new(1, -20, 0, h)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Gotham
		l.TextSize = size
		l.TextColor3 = color
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextTruncate = Enum.TextTruncate.AtEnd
		l.Parent = frame
		return l
	end
	local title = mkLabel(6, 20, 14, Color3.fromRGB(255, 255, 255))
	title.Font = Enum.Font.GothamBold
	title.Text = "📡 Webhook Monitor"
	uiBody = Instance.new("Frame")
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
	lblWeather = mkBody(0, 16, 13, Color3.fromRGB(255, 224, 77))
	lblTimer = mkBody(17, 16, 12, Color3.fromRGB(170, 175, 190))
	lblMeteor = mkBody(34, 16, 13, Color3.fromRGB(255, 140, 90))
	lblMountain = mkBody(51, 16, 13, Color3.fromRGB(150, 200, 255))
	lblBomb = mkBody(68, 16, 13, Color3.fromRGB(140, 220, 150))
	lblLast = mkBody(85, 16, 12, Color3.fromRGB(170, 175, 190))
	lblLog = mkBody(103, 45, 11, Color3.fromRGB(130, 135, 150))
	lblLog.TextYAlignment = Enum.TextYAlignment.Top
	local btnTest = Instance.new("TextButton")
	btnTest.Position = UDim2.new(0, 10, 0, 168)
	btnTest.Size = UDim2.new(0.62, -14, 0, 28)
	btnTest.BackgroundColor3 = Color3.fromRGB(70, 130, 200)
	btnTest.Font = Enum.Font.GothamBold
	btnTest.TextSize = 13
	btnTest.TextColor3 = Color3.fromRGB(255, 255, 255)
	btnTest.Text = "🧪 Tes Webhook"
	btnTest.Parent = uiBody
	local btnTestCorner = Instance.new("UICorner")
	btnTestCorner.CornerRadius = UDim.new(0, 6)
	btnTestCorner.Parent = btnTest
	local btnMin = Instance.new("TextButton")
	btnMin.Position = UDim2.new(0.62, 0, 0, 168)
	btnMin.Size = UDim2.new(0.38, -10, 0, 28)
	btnMin.BackgroundColor3 = Color3.fromRGB(45, 48, 58)
	btnMin.Font = Enum.Font.GothamBold
	btnMin.TextSize = 13
	btnMin.TextColor3 = Color3.fromRGB(200, 205, 215)
	btnMin.Text = "–/+"
	btnMin.Parent = uiBody
	local btnMinCorner = Instance.new("UICorner")
	btnMinCorner.CornerRadius = UDim.new(0, 6)
	btnMinCorner.Parent = btnMin
	local open = true
	STATE.connect(btnTest.MouseButton1Click, function()
		send(
			"🧪 Tes manual",
			"Tombol tes dipencet.\n" .. weatherTimers(),
			9807270,
			{
				{ name = "Cuaca", value = "`" .. tostring(WState.Value) .. "`", inline = true },
				{ name = "Meteor aktif", value = "`" .. tostring(MActive.Value) .. "`", inline = true },
			}
		)
		refreshUI()
	end)
	STATE.connect(btnMin.MouseButton1Click, function()
		open = not open
		for _, v in ipairs(uiBody:GetChildren()) do
			if v ~= btnMin and v:IsA("GuiObject") then
				v.Visible = open or v == btnMin
			end
		end
		btnTest.Visible = open
		lblWeather.Visible = open
		lblTimer.Visible = open
		lblMeteor.Visible = open
		lblMountain.Visible = open
		lblBomb.Visible = open
		lblLast.Visible = open
		lblLog.Visible = open
		frame.Size = open and UDim2.new(0, 260, 0, 254) or UDim2.new(0, 260, 0, 62)
	end)
end

-- Snapshot awal
do
	local winfo = WeatherData.byId and WeatherData.byId[lastWeather]
	local extra = {
		{ name = "Cuaca", value = "`" .. tostring(lastWeather) .. "`", inline = true },
		{ name = "Meteor aktif", value = "`" .. tostring(lastMActive) .. "`", inline = true },
		{ name = "Gunung", value = "`" .. mountainName(lastMountain) .. "`", inline = true },
		{ name = "Timer", value = weatherTimers(), inline = false },
	}
	if winfo and winfo.mult then
		table.insert(extra, { name = "Mult cuaca", value = string.format("x%d, luck +%d", winfo.mult or 1, winfo.luck or 0), inline = true })
	end
	do
		local on, ae = abuseActive()
		lastAbuse = on
		if on then
			table.insert(extra, { name = "Admin Abuse", value = string.format("AKTIF sampai <t:%d:R>", ae), inline = false })
		end
	end
	local guiStock = readGuiStock()
	if guiStock then
		lastStockSig = stockSig(guiStock)
		lastStockTotal = stockTotal(guiStock)
		lastDivine = guiStock["DivineBomb"] or 0
		table.insert(extra, { name = "Stok bom (GUI)", value = stockLines(guiStock):sub(1, 900), inline = false })
	end
	send("✅ Monitor online", "Webhook jalan. Notifikasi: cuaca, meteor, bom restock, gunung.", 4620980, extra)
	print("[webhook] monitor online, cuaca=" .. tostring(lastWeather) .. " meteor=" .. tostring(lastMActive) .. " gunung=" .. tostring(lastMountain))
	refreshUI()
end

-- Poll tiap 5 dtk (tangkap sinyal terlewat) + GUI stock tiap 30 dtk
while STATE.alive() do
	task.wait(5)
	if WState.Value ~= lastWeather then
		lastWeather = WState.Value
		notifyWeather(lastWeather)
	end
	if MActive.Value ~= lastMActive then
		lastMActive = MActive.Value
		if lastMActive then
			notifyMeteor("METEOR JATUH!")
		end
	end
	lastMPhase = MPhase.Value
	if MtState.Value ~= lastMountain then
		lastMountain = MtState.Value
		notifyMountain(lastMountain)
	end
	do
		local on = abuseActive()
		if on and not lastAbuse then
			notifyAbuse()
		end
		lastAbuse = on
	end
	if os.clock() - lastGuiPoll > 30 then
		lastGuiPoll = os.clock()
		local s = readGuiStock()
		if s then
			handleShopStock(s, nil)
		end
	end
	if os.clock() - lastAfkPulse > 240 then
		lastAfkPulse = os.clock()
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new(0, 0))
		end)
		local char = LocalPlayer.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum.Jump = true
		end
		print("[antiafk] denyut " .. os.date("%H:%M:%S"))
	end
	refreshUI()
end
