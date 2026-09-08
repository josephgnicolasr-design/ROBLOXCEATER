--!strict
-- Abyssal — SaveService (server).
-- GDD §3 + §10.6: best-effort DataStore (Config.Save.DatastoreName,
-- autosave Config.Save.AutosaveSecs) persisting pearls / current rod /
-- owned rods / bucket. In-memory fallback keeps the full loop playable
-- with zero Roblox services; failures warn, never block.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("AbyssalShared")
local Config = require(Shared:WaitForChild("Config"))

local PlayerState = require(script.Parent:WaitForChild("PlayerState"))

local SaveService = {}
SaveService._fallback: { [number]: any } = {} -- userId -> snapshot (session cache)

-- TODO: replace the pcall-wrapped DataStoreService access below with a real
-- versioned DataStore integration (keyed per userId, UpdateAsync with retry
-- + session lock) once the Lead Dev provisions production persistence.

local function getStore(): DataStore?
	local ok, service = pcall(function()
		return game:GetService("DataStoreService")
	end)
	if not ok or service == nil then
		return nil
	end
	local okStore, store = pcall(function()
		return (service :: DataStoreService):GetDataStore(Config.Save.DatastoreName)
	end)
	if not okStore then
		warn("[Abyssal] SaveService: DataStore unavailable, using session fallback")
		return nil
	end
	return store
end

local function keyFor(userId: number): string
	return "player_" .. tostring(userId)
end

function SaveService.Snapshot(data: PlayerState.PlayerData): any
	local bucketCopy: { [string]: number } = {}
	for speciesId, count in data.bucket do
		bucketCopy[speciesId] = count
	end
	local ownedCopy: { [string]: boolean } = {}
	for rodId, owned in data.rodOwned do
		ownedCopy[rodId] = owned
	end
	return {
		pearls = data.pearls,
		currentRod = data.currentRod,
		rodOwned = ownedCopy,
		bucket = bucketCopy,
		savedAt = os.time(),
	}
end

function SaveService.Apply(data: PlayerState.PlayerData, snapshot: any)
	if typeof(snapshot) ~= "table" then
		return
	end
	if typeof(snapshot.pearls) == "number" then
		data.pearls = math.max(0, math.floor(snapshot.pearls))
	end
	if typeof(snapshot.currentRod) == "string" and Config.Rods[snapshot.currentRod] then
		data.currentRod = snapshot.currentRod
	end
	if typeof(snapshot.rodOwned) == "table" then
		data.rodOwned = { Twig = true }
		for rodId, owned in snapshot.rodOwned do
			if Config.Rods[rodId] and owned == true then
				data.rodOwned[rodId] = true
			end
		end
		if not data.rodOwned[data.currentRod] then
			data.currentRod = "Twig" -- never load into an unowned rod
		end
	end
	if typeof(snapshot.bucket) == "table" then
		table.clear(data.bucket)
		local total = 0
		for speciesId, count in snapshot.bucket do
			if Config.Species[speciesId] and typeof(count) == "number" then
				local take = math.min(math.max(0, math.floor(count)), Config.Economy.BucketCap - total)
				if take > 0 then
					data.bucket[speciesId] = take
					total += take
				end
			end
		end
	end
end

function SaveService.SavePlayer(player: Player)
	local data = PlayerState.Get(player)
	if not data then
		return
	end
	local snapshot = SaveService.Snapshot(data)
	SaveService._fallback[player.UserId] = snapshot -- session cache always fresh
	local store = getStore()
	if not store then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync(keyFor(player.UserId), snapshot)
	end)
	if not ok then
		warn("[Abyssal] SaveService: save failed (best-effort): " .. tostring(err))
	end
end

function SaveService.LoadPlayer(player: Player, data: PlayerState.PlayerData)
	local cached = SaveService._fallback[player.UserId]
	if cached then
		SaveService.Apply(data, cached)
		return
	end
	local store = getStore()
	if not store then
		return
	end
	local ok, result = pcall(function()
		return store:GetAsync(keyFor(player.UserId))
	end)
	if ok and result ~= nil then
		SaveService.Apply(data, result)
	elseif not ok then
		warn("[Abyssal] SaveService: load failed (best-effort): " .. tostring(result))
	end
end

local _started = false

function SaveService.Init()
	if _started then
		return
	end
	_started = true

	PlayerState.OnPlayerAdded(function(player: Player, data: PlayerState.PlayerData)
		SaveService.LoadPlayer(player, data)
		PlayerState.NotifyChanged(player)
	end)
	PlayerState.OnPlayerRemoving(function(player: Player)
		SaveService.SavePlayer(player)
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Save.AutosaveSecs)
			for _, player in Players:GetPlayers() do
				SaveService.SavePlayer(player)
			end
		end
	end)
end

return SaveService
