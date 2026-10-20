local Config = {}

Config.DetectionThreshold = 5
Config.MaxRemoteCallsPerSecond = 30
Config.MaxMemorySpike = 100
Config.MaxPlayerSpeed = 100
Config.MaxTeleportDistance = 50
Config.FlyDetectionTime = 2
Config.ScanInterval = 10

Config.SuspiciousNames = {
    "exploit", "inject", "cheat", "hack", "dex", 
    "saveinstance", "bypass", "crack", "scriptware"
}

Config.ProtectedProperties = {
    "Source", "LinkedSource", "ScriptGuid", "ClassName"
}

Config.WhitelistedInstances = {
    "CoreGui", "CorePackages", "PlayerScripts", "StarterPack"
}

return Config
