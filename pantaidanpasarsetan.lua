local scripts = {
    [126463495082631] = "https://raw.githubusercontent.com/deangisham77/engxirseproject/refs/heads/main/pantai.lua",
    [108679402300081] = "https://raw.githubusercontent.com/deangisham77/engxirseproject/refs/heads/main/pasar.lua",
}

local url = scripts[game.PlaceId]

if url then
    loadstring(game:HttpGet(url))()
else
    warn(("Unsupported PlaceId: %s"):format(game.PlaceId))
end
