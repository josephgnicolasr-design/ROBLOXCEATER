--!strict
-- Abyssal — PlayerState (server).
-- GDD §3 (oxygen flavor), §7 (pearls/bucket/rods), §10.4 (telemetry).
-- Per-player runtime state. Single owner of mutable player data; other
-- services read/write through this module's helpers. Oxygen here is
-- authoritative for the swim-slow flavor; the client mirrors the same
-- Config.Oxygen math locally for its HUD bar (no oxygen remote exists in
-- the Remotes contract — see README).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("AbyssalShared")
local Config = require(Shared:WaitForChild("Config"))

export type CastState = {
	phase: string, -- "cast" | "wait" | "bite" | "reel"
	spotId: string,
	bobberPos: Vector3,
	species: string,
	gen: number, -- generation counter: stale async timers abort when mismatched
	hookExpiresAt: number?,
	reel: {
		progress: number, -- 0..100
		tension: number, -- 0..100
		catcher: number, -- 0..1 track position
		markerPhase: number,
		elapsed: number,
		surges: { { start: number, duration: number } },
		nextSurgeIdx: number,
		holding: boolean,
	}?,
}

export type PlayerData = {
	userId: number,
	rodOwned: { [string]: boolean },
	currentRod: string,
	pearls: number,
	bucket: { [string]: number },
	cast: CastState?,
	oxygen: number, -- 0..Config.Oxygen.Max
	missCooldownUntil: number,
	telemetry: { pearlsEarned: number, sessionStart: number },
}

local PlayerState = {}
PlayerState._data: { [Player]: PlayerData } = {}

-- Listener registries so services react without circular requires.
PlayerState._addedListeners: { (Player, PlayerData) -> () } = {}
PlayerState._removingListeners: { (Player, PlayerData) -> () } = {}
PlayerState._changedListeners: { (Player, PlayerData) -> () } = {}

function PlayerState.OnPlayerAdded(fn: (Player, PlayerData) -> ())
	table.insert(PlayerState._addedListeners, fn)
end

function PlayerState.OnPlayerRemoving(fn: (Player, PlayerData) -> ())
	table.insert(PlayerState._removingListeners, fn)
end

function PlayerState.OnChanged(fn: (Player, PlayerData) -> ())
	table.insert(PlayerState._changedListeners, fn)
end

function PlayerState.NotifyChanged(player: Player)
	local data = PlayerState._data[player]
	if not data then
		return
	end
	for _, fn in PlayerState._changedListeners do
		task.spawn(fn, player, data)
	end
end

function PlayerState.FreshData(player: Player): PlayerData
	return {
		userId = player.UserId,
		rodOwned = { Twig = true }, -- GDD §7: everyone starts with the Twig Rod
		currentRod = "Twig",
		pearls = 0,
		bucket = {},
		cast = nil,
		oxygen = Config.Oxygen.Max,
		missCooldownUntil = 0,
		telemetry = { pearlsEarned = 0, sessionStart = os.clock() },
	}
end

function PlayerState.Get(player: Player): PlayerData?
	return PlayerState._data[player]
end

function PlayerState.GetOrCreate(player: Player): PlayerData
	local data = PlayerState._data[player]
	if not data then
		data = PlayerState.FreshData(player)
		PlayerState._data[player] = data
	end
	return data
end

-- GDD §7: bucket helpers. Stackable by species, hard cap forces sell trips.
function PlayerState.BucketCount(data: PlayerData): number
	local total = 0
	for _, count in data.bucket do
		total += count
	end
	return total
end

function PlayerState.BucketIsFull(data: PlayerData): boolean
	return PlayerState.BucketCount(data) >= Config.Economy.BucketCap
end

-- Returns false when the bucket is full (caller reports "bucket_full").
function PlayerState.TryAddFish(data: PlayerData, speciesId: string): boolean
	if PlayerState.BucketIsFull(data) then
		return false
	end
	data.bucket[speciesId] = (data.bucket[speciesId] or 0) + 1
	return true
end

function PlayerState.RemoveOneFish(data: PlayerData, speciesId: string): boolean
	if (data.bucket[speciesId] or 0) <= 0 then
		return false
	end
	data.bucket[speciesId] -= 1
	if data.bucket[speciesId] <= 0 then
		data.bucket[speciesId] = nil
	end
	return true
end

function PlayerState.AddPearls(player: Player, data: PlayerData, amount: number)
	data.pearls += amount
	if amount > 0 then
		data.telemetry.pearlsEarned += amount -- GDD §10.4 tuning metric
	end
	PlayerState.NotifyChanged(player)
end

-- GDD §10.4: trailing-window Pearls/min for economy pacing playtests.
function PlayerState.PearlsPerMinute(data: PlayerData): number
	local elapsedMin = math.max((os.clock() - data.telemetry.sessionStart) / 60, 1 / 60)
	return data.telemetry.pearlsEarned / elapsedMin
end

-- Active cast accessors (owned by FishingService).
function PlayerState.SetCast(data: PlayerData, cast: CastState?)
	data.cast = cast
end

function PlayerState.ClearCast(data: PlayerData)
	data.cast = nil
end

-- Bump the generation so in-flight timers for an old line abort. Call on
-- every line teardown (catch, fail, cancel).
function PlayerState.InvalidateCast(data: PlayerData)
	if data.cast then
		data.cast.gen += 1
	end
	data.cast = nil
end

function PlayerState.IsOnMissCooldown(data: PlayerData): boolean
	return os.clock() < data.missCooldownUntil
end

function PlayerState.ApplyMissCooldown(data: PlayerData)
	data.missCooldownUntil = os.clock() + Config.Fishing.MissCooldown
end

-- GDD §3 flavor oxygen. Drains over Config.Oxygen.DrainTime, refills at the
-- surface (y >= SurfaceY) or inside any spot's vent radius. Never a fail
-- state: at empty the swim code applies the 20% slow only.
function PlayerState.TickOxygen(data: PlayerData, position: Vector3, dt: number)
	local refilling = position.Y >= Config.Oxygen.SurfaceY
	if not refilling then
		for _, spot in Config.Spots do
			if (position - spot.VentOffset).Magnitude <= spot.VentRadius then
				refilling = true
				break
			end
		end
	end
	if refilling then
		data.oxygen = math.min(Config.Oxygen.Max, data.oxygen + Config.Oxygen.RefillPerSec * dt)
	else
		data.oxygen = math.max(0, data.oxygen - (Config.Oxygen.Max / Config.Oxygen.DrainTime) * dt)
	end
end

function PlayerState.IsOxygenEmpty(data: PlayerData): boolean
	return data.oxygen <= 0
end

-- Applies the GDD §3 empty-oxygen 20% swim slow. Flavor only, never fails.
function PlayerState.SwimSpeedMultiplier(data: PlayerData): number
	if PlayerState.IsOxygenEmpty(data) then
		return 1 - Config.Swim.EmptyOxygenSlow
	end
	return 1
end

-- Snapshot shape reused by EconomyService for EconomyChanged payloads.
function PlayerState.EconomySnapshot(data: PlayerData): { pearls: number, bucket: { [string]: number }, bucketTotal: number }
	local copy: { [string]: number } = {}
	for speciesId, count in data.bucket do
		copy[speciesId] = count
	end
	return { pearls = data.pearls, bucket = copy, bucketTotal = PlayerState.BucketCount(data) }
end

local _started = false

function PlayerState.Init()
	if _started then
		return
	end
	_started = true

	Players.PlayerAdded:Connect(function(player: Player)
		local data = PlayerState.FreshData(player)
		PlayerState._data[player] = data
		for _, fn in PlayerState._addedListeners do
			task.spawn(fn, player, data)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		local data = PlayerState._data[player]
		if data then
			for _, fn in PlayerState._removingListeners do
				task.spawn(fn, player, data)
			end
			PlayerState._data[player] = nil
		end
	end)

	-- Authoritative oxygen tick (1 Hz is plenty for a 3-minute drain).
	task.spawn(function()
		while true do
			task.wait(1)
			for player, data in PlayerState._data do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					PlayerState.TickOxygen(data, root.Position, 1)
				end
			end
		end
	end)
end

return PlayerState
