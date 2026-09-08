--!strict
-- Abyssal — RodSystem (server).
-- GDD §7: equip/ownership of the 3 rods (Config.Rods + RodOrder); snap-risk
-- soft gating is applied in the reel minigame (FishingService calls the
-- shared RollSnap per surge). This module owns equip validation + RodChanged.
-- Pure stat math (bite rolls, snap odds) lives in the shared RodSystem
-- (ReplicatedStorage/AbyssalShared/RodSystem.luau) — required here, not forked.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("AbyssalShared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local SharedRods = require(Shared:WaitForChild("RodSystem"))

local PlayerState = require(script.Parent:WaitForChild("PlayerState"))

local RodSystem = {}

local function fireClient(player: Player, remoteName: string, payload: any)
	local event = ReplicatedStorage:FindFirstChild(remoteName) :: RemoteEvent?
	if event then
		event:FireClient(player, payload)
	end
end

function RodSystem.OwnsRod(data: PlayerState.PlayerData, rodId: string): boolean
	return data.rodOwned[rodId] == true
end

function RodSystem.GetEquipped(data: PlayerState.PlayerData): string
	return data.currentRod
end

-- Equip an owned rod. Returns false (no event) when unowned/unknown.
function RodSystem.EquipRod(player: Player, rodId: string): boolean
	if not Config.Rods[rodId] then
		return false
	end
	local data = PlayerState.GetOrCreate(player)
	if not RodSystem.OwnsRod(data, rodId) then
		return false
	end
	data.currentRod = rodId
	fireClient(player, Remotes.RodChanged, { rodId = rodId }) -- GDD §8 HUD icon update
	PlayerState.NotifyChanged(player)
	return true
end

-- Purchase helper shared with EconomyService: validates cost/ownership,
-- deducts Pearls, marks owned, equips. Returns (ok, message).
function RodSystem.GrantRod(player: Player, rodId: string): (boolean, string)
	local rod = Config.Rods[rodId]
	if not rod then
		return false, "Unknown rod"
	end
	local data = PlayerState.GetOrCreate(player)
	if RodSystem.OwnsRod(data, rodId) then
		return false, "Already owned"
	end
	if data.pearls < rod.Cost then
		return false, "Not enough Pearls"
	end
	data.pearls -= rod.Cost
	data.rodOwned[rodId] = true
	data.currentRod = rodId
	fireClient(player, Remotes.RodChanged, { rodId = rodId })
	PlayerState.NotifyChanged(player)
	return true, ("Equipped " .. rod.Name)
end

-- Ordered shop cards for ShopState snapshots (bars, not numbers — GDD §8).
function RodSystem.ShopCards(data: PlayerState.PlayerData): { any }
	local cards = {}
	for _, rodId in SharedRods.GetOrder() do
		local rod = SharedRods.GetStats(rodId)
		table.insert(cards, {
			rodId = rodId,
			name = rod.Name,
			cost = rod.Cost,
			owned = RodSystem.OwnsRod(data, rodId),
			equipped = data.currentRod == rodId,
		})
	end
	return cards
end

function RodSystem.Init()
	-- Passive module: no loops. Init kept for symmetric bootstrap wiring.
end

return RodSystem
