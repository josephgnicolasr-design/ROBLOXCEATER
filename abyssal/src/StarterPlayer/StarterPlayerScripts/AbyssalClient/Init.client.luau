--!strict
-- Abyssal — Init.client (client bootstrap).
-- Starts NetListener first (so no early server payload is missed), then
-- input + swim feel. UI screens bind via NetListener.On (see its header).

local NetListener = require(script.Parent:WaitForChild("NetListener"))
local InputController = require(script.Parent:WaitForChild("InputController"))
local SwimController = require(script.Parent:WaitForChild("SwimController"))

NetListener.Init()
InputController.Init()
SwimController.Init()
require(script.Parent:WaitForChild("UI"):WaitForChild("UIInit"))

print("[Abyssal] client ready")
