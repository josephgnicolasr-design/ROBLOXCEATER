--!strict
-- Abyssal — Init.server (server bootstrap).
-- Requires every service exactly once; services self-guard via their Init.
-- Load order matters: PlayerState first (data), FishAI (world sim), then
-- gameplay services, SaveService last (loads on PlayerAdded).

local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local FishAI = require(script.Parent:WaitForChild("FishAI"))
local RodSystem = require(script.Parent:WaitForChild("RodSystem"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local FishingService = require(script.Parent:WaitForChild("FishingService"))
local SaveService = require(script.Parent:WaitForChild("SaveService"))

PlayerState.Init()
FishAI.Init()
RodSystem.Init()
EconomyService.Init()
FishingService.Init()
SaveService.Init()

print("[Abyssal] server ready")
