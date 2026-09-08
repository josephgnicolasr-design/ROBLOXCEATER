--!strict
-- Abyssal — RemotesBootstrap (server).
-- Creates every RemoteEvent in the Remotes contract as a child of
-- ReplicatedStorage BEFORE any service connects listeners (services use
-- FindFirstChild at Init time; the client uses WaitForChild). Required first
-- in Init.server. Names/payloads unchanged — contract untouched.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("AbyssalShared")
local Contract = require(Shared:WaitForChild("Remotes"))

local RemotesBootstrap = {}

local ORDER = {
	-- Client -> Server (intents)
	"CastRequest", "HookAttempt", "CancelLine", "ReelInput",
	"ShopInteract", "ShopSellAll", "ShopSellOne", "ShopBuyRod",
	-- Server -> Client (state)
	"SpotPrompt", "CastStarted", "BitePrompt", "ReelState", "CatchResult",
	"LineFailed", "EconomyChanged", "RodChanged", "ShopState",
}

function RemotesBootstrap.Start()
	for _, key in ORDER do
		local eventName = (Contract :: any)[key] :: string
		assert(typeof(eventName) == "string", "Remotes contract missing key: " .. tostring(key))
		local existing = ReplicatedStorage:FindFirstChild(eventName)
		if existing and existing:IsA("RemoteEvent") then
			continue
		end
		local event = Instance.new("RemoteEvent")
		event.Name = eventName
		event.Parent = ReplicatedStorage
	end
	print("[Abyssal] remotes ready (" .. tostring(#ORDER) .. " events)")
end

return RemotesBootstrap
