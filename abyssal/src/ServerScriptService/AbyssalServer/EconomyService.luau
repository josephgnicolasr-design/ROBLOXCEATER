--!strict
-- Abyssal — EconomyService (server).
-- GDD §7: Pearls currency (fish sales only), Bucket (max
-- Config.Economy.BucketCap, stackable by species), sell all / sell one /
-- buy rod flows per the Remotes contract. Emits EconomyChanged + ShopState.
-- Sell values come from Config.Species[*].Sell (10/30/80) — never hardcoded.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("AbyssalShared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerState = require(script.Parent:WaitForChild("PlayerState"))
local RodSystem = require(script.Parent:WaitForChild("RodSystem"))

local EconomyService = {}

local function getEvent(remoteName: string): RemoteEvent?
	return ReplicatedStorage:FindFirstChild(remoteName) :: RemoteEvent?
end

local function fireClient(player: Player, remoteName: string, payload: any)
	local event = getEvent(remoteName)
	if event then
		event:FireClient(player, payload)
	end
end

function EconomyService.SellValue(speciesId: string): number
	local species = Config.Species[speciesId]
	assert(species, "Unknown species: " .. tostring(speciesId))
	return species.Sell
end

function EconomyService.BucketValue(data: PlayerState.PlayerData): number
	local total = 0
	for speciesId, count in data.bucket do
		total += EconomyService.SellValue(speciesId) * count
	end
	return total
end

-- GDD §8 HUD snapshot: { pearls, bucket: {species: count}, bucketTotal }.
function EconomyService.EmitEconomy(player: Player)
	local data = PlayerState.GetOrCreate(player)
	fireClient(player, Remotes.EconomyChanged, PlayerState.EconomySnapshot(data))
end

-- GDD §8 shop screen snapshot: sell list + rod cards + totals.
function EconomyService.EmitShop(player: Player)
	local data = PlayerState.GetOrCreate(player)
	local sellLines = {}
	for speciesId, count in data.bucket do
		table.insert(sellLines, {
			species = speciesId,
			count = count,
			unitValue = EconomyService.SellValue(speciesId),
		})
	end
	fireClient(player, Remotes.ShopState, {
		pearls = data.pearls,
		bucket = PlayerState.EconomySnapshot(data).bucket,
		bucketTotal = PlayerState.BucketCount(data),
		bucketValue = EconomyService.BucketValue(data),
		sellLines = sellLines,
		rods = RodSystem.ShopCards(data),
	})
end

-- GDD §8: one-click "Sell All" with running total.
function EconomyService.SellAll(player: Player): (boolean, string)
	local data = PlayerState.GetOrCreate(player)
	local total = EconomyService.BucketValue(data)
	if total <= 0 then
		return false, "Bucket is empty"
	end
	table.clear(data.bucket)
	PlayerState.AddPearls(player, data, total)
	EconomyService.EmitEconomy(player)
	EconomyService.EmitShop(player)
	return true, ("Sold catch for " .. tostring(total) .. " Pearls")
end

-- GDD §8: per-fish sell.
function EconomyService.SellOne(player: Player, speciesId: string): (boolean, string)
	local data = PlayerState.GetOrCreate(player)
	if not Config.Species[speciesId] then
		return false, "Unknown species"
	end
	if not PlayerState.RemoveOneFish(data, speciesId) then
		return false, "No " .. speciesId .. " in bucket"
	end
	PlayerState.AddPearls(player, data, EconomyService.SellValue(speciesId))
	EconomyService.EmitEconomy(player)
	EconomyService.EmitShop(player)
	return true, ("Sold 1 " .. speciesId)
end

-- GDD §7: buy + auto-equip. Price curve: Coral 250, Abyss 800.
function EconomyService.BuyRod(player: Player, rodId: string): (boolean, string)
	local ok, message = RodSystem.GrantRod(player, rodId)
	if ok then
		EconomyService.EmitEconomy(player)
		EconomyService.EmitShop(player)
	end
	return ok, message
end

local _started = false

function EconomyService.Init()
	if _started then
		return
	end
	_started = true

	local function onPlayer(player: Player)
		-- Push opening snapshots so HUD/shop never render stale zeros.
		task.defer(function()
			EconomyService.EmitEconomy(player)
			local data = PlayerState.Get(player)
			if data then
				local event = getEvent(Remotes.RodChanged)
				if event then
					event:FireClient(player, { rodId = data.currentRod })
				end
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)

	local function listen(remoteName: string, fn: (Player, any) -> ())
		local event = getEvent(remoteName)
		if event then
			event.OnServerEvent:Connect(fn)
		end
	end
	listen(Remotes.ShopInteract, function(player: Player)
		EconomyService.EmitShop(player)
	end)
	listen(Remotes.ShopSellAll, function(player: Player)
		EconomyService.SellAll(player)
	end)
	listen(Remotes.ShopSellOne, function(player: Player, payload: any)
		if typeof(payload) == "table" and typeof(payload.species) == "string" then
			EconomyService.SellOne(player, payload.species)
		end
	end)
	listen(Remotes.ShopBuyRod, function(player: Player, payload: any)
		if typeof(payload) == "table" and typeof(payload.rodId) == "string" then
			EconomyService.BuyRod(player, payload.rodId)
		end
	end)
end

return EconomyService
