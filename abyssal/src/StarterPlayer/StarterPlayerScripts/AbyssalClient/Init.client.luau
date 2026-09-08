--!strict
-- Abyssal — Init.client (client bootstrap).
-- Starts NetListener first (so no early server payload is missed), then
-- input + swim feel + character rig, then visual binders (fish, bobber, NPC).
-- UI screens bind via NetListener.On (see its header).

local NetListener = require(script.Parent:WaitForChild("NetListener"))
local InputController = require(script.Parent:WaitForChild("InputController"))
local SwimController = require(script.Parent:WaitForChild("SwimController"))
local CharacterRig = require(script.Parent:WaitForChild("CharacterRig"))
local FishVisuals = require(script.Parent:WaitForChild("FishVisuals"))
local Bobber = require(script.Parent:WaitForChild("Bobber"))
local OldMarrowNPC = require(script.Parent:WaitForChild("OldMarrowNPC"))

NetListener.Init()
InputController.Init()
SwimController.Init()
CharacterRig.Init()
FishVisuals.Init()
Bobber.Init()
OldMarrowNPC.Init()
require(script.Parent:WaitForChild("UI"):WaitForChild("UIInit"))

print("[Abyssal] client ready")
