--!strict
-- Abyssal — Init.server (server bootstrap).
-- Requires every service exactly once; services self-guard via their Init.
-- Load order matters: RemotesBootstrap first (creates RemoteEvents),
-- PlayerState (data), spawn/character assembly, fish sim + mirror, then
-- gameplay services, SaveService last (loads on PlayerAdded).

local RemotesBootstrap = require(script.Parent:WaitForChild("RemotesBootstrap"))
local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local SpawnService = require(script.Parent:WaitForChild("SpawnService"))
local FishAI = require(script.Parent:WaitForChild("FishAI"))
local FishBinder = require(script.Parent:WaitForChild("FishBinder"))
local RodSystem = require(script.Parent:WaitForChild("RodSystem"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local FishingService = require(script.Parent:WaitForChild("FishingService"))
local SaveService = require(script.Parent:WaitForChild("SaveService"))

RemotesBootstrap.Start()
PlayerState.Init()
SpawnService.Init()
FishAI.Init()
FishBinder.Start()
RodSystem.Init()
EconomyService.Init()
FishingService.Init()
SaveService.Init()

print("[Abyssal] server ready")
