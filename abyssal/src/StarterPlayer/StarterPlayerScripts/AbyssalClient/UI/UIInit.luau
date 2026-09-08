--!strict
-- Abyssal — UIInit.client (client UI bootstrap).
-- NetListener.Init + mounts all views into PlayerGui. Required by Init.client
-- (one line: require(script.Parent:WaitForChild("UI"):WaitForChild("UIInit"))).
-- Mount order: Hud first (owns the prompt pill), then PromptController,
-- BiteReel, CatchCard, BucketView, ShopView. Above DepthVignette (order 5):
-- HUD 10 / bucket 15 / bite-reel 20 / shop 25 / catch card 30.

local Players = game:GetService("Players")

local ClientFolder = script.Parent.Parent
local UI = script.Parent

local NetListener = require(ClientFolder:WaitForChild("NetListener"))
local Hud = require(UI:WaitForChild("Hud"))
local PromptController = require(UI:WaitForChild("PromptController"))
local BiteReel = require(UI:WaitForChild("BiteReel"))
local CatchCard = require(UI:WaitForChild("CatchCard"))
local BucketView = require(UI:WaitForChild("BucketView"))
local ShopView = require(UI:WaitForChild("ShopView"))

local UIInit = {}
local _started = false

function UIInit.Start()
	if _started then
		return
	end
	_started = true
	NetListener.Init() -- idempotent: safe even though Init.client already ran it
	local player = Players.LocalPlayer
	if not player then
		warn("[AbyssalUI] no LocalPlayer; UI not mounted")
		return
	end
	local playerGui = player:WaitForChild("PlayerGui", 15)
	if not (playerGui and (playerGui :: Instance):IsA("PlayerGui")) then
		warn("[AbyssalUI] no PlayerGui; UI not mounted")
		return
	end
	local root = playerGui :: PlayerGui
	Hud.Mount(root)
	PromptController.Mount(root)
	BiteReel.Mount(root)
	CatchCard.Mount(root)
	BucketView.Mount(root)
	ShopView.Mount(root)
	print("[AbyssalUI] mounted (Hud + prompts + bite/reel + card + bucket + shop)")
end

UIInit.Start()

return UIInit
