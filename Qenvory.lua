local scripts = {
    [129827112113663] = "https://github.com/deangisham77/engxirseproject/raw/refs/heads/main/EngIRSE.lua",
    [111896378748580] = "https://raw.githubusercontent.com/irsemoticon9/QenturyHub/refs/heads/main/kerangajaib.lua",
	[117623186846996] = "https://github.com/deangisham77/engxirseproject/raw/refs/heads/main/EngIRSE.lua",
    [86111605798689] = "https://raw.githubusercontent.com/irsemoticon9/QenturyHub/refs/heads/main/starfishing.lua",
    [90457367396205] = "https://raw.githubusercontent.com/irsemoticon9/QenturyHub/refs/heads/main/fishandmonster.lua",
    [111385005478215] = "https://raw.githubusercontent.com/irsemoticon9/QenturyHub/refs/heads/main/fishandmonster.lua",
    [125927821145949] = "https://raw.githubusercontent.com/irsemoticon9/QenturyHub/refs/heads/main/nambangfreeport.lua",
    [98800969324557] = "https://raw.githubusercontent.com/irsemoticon9/QenturyHub/refs/heads/main/Storagehunter.lua",
}

local url = scripts[game.PlaceId]

if url then
    loadstring(game:HttpGet(url))()
else
    warn(("Unsupported PlaceId: %s"):format(game.PlaceId))
end
