--!strict
-- Abyssal — FishAI (server).
-- GDD §6: 4-6 fish per spot, 20 s respawn, 4-8 studs/s patrol, nearest 1-2
-- approach the bobber on cast (visible shadow movement), bite roll per
-- Config.BiteTable, 5 s scatter on hook-fail. Rustbelly circles ~2.5 s
-- (Config.Species.Rustbelly.CircleDelay) before biting.
--
-- Procedural simulation only (positions + states as Vector3 math, no assets):
-- the Lead Dev binds visible fish/shadow models by polling GetFish(spotId)
-- each Heartbeat and placing models at entry.pos. FishingService drives the
-- actual bite outcome; this module sells the tease.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("AbyssalShared")
local Config = require(Shared:WaitForChild("Config"))

export type FishEntry = {
	id: number,
	species: string,
	pos: Vector3,
	waypoint: Vector3,
	speed: number, -- studs/s, rolled 4-8 per GDD §6
	state: string, -- "patrol" | "approach" | "circle" | "scatter" | "gone"
	stateUntil: number,
	respawnAt: number?,
	target: Vector3?, -- bobber position when approaching/circling
}

local FishAI = {}
FishAI._spots: { [string]: { FishEntry } } = {}
FishAI._nextId = 0
FishAI._rng = Random.new()

local function randomOffset(rng: Random, center: Vector3, radius: number): Vector3
	local angle = rng:NextNumber(0, math.pi * 2)
	local r = rng:NextNumber(radius * 0.3, radius)
	return center + Vector3.new(math.cos(angle) * r, rng:NextNumber(-3, 3), math.sin(angle) * r)
end

local function rollSpeciesForWander(spotId: string): string
	-- Wandering silhouettes mirror the bite table so teases match outcomes.
	return FishAI.RollSpecies(spotId, FishAI._rng)
end

local function makeFish(spotId: string, spot: any): FishEntry
	FishAI._nextId += 1
	local speed = FishAI._rng:NextNumber(
		Config.Species.Sunfin.PatrolSpeedMin,
		Config.Species.Sunfin.PatrolSpeedMax
	)
	local pos = randomOffset(FishAI._rng, spot.Center, Config.FishAI.WaypointRadius)
	return {
		id = FishAI._nextId,
		species = rollSpeciesForWander(spotId),
		pos = pos,
		waypoint = randomOffset(FishAI._rng, spot.Center, Config.FishAI.WaypointRadius),
		speed = speed,
		state = "patrol",
		stateUntil = 0,
		respawnAt = nil,
		target = nil,
	}
end

function FishAI.EnsureSpot(spotId: string)
	if FishAI._spots[spotId] then
		return
	end
	local spot = Config.Spots[spotId]
	assert(spot, "Unknown spot: " .. tostring(spotId))
	local count = FishAI._rng:NextInteger(Config.FishAI.PerSpotMin, Config.FishAI.PerSpotMax)
	local school: { FishEntry } = {}
	for _ = 1, count do
		table.insert(school, makeFish(spotId, spot))
	end
	FishAI._spots[spotId] = school
end

-- GDD §6 bite rarity roll. Reef remainder falls back to Sunfin (common-only
-- water); Wreck/Trench weights already sum to 1.
function FishAI.RollSpecies(spotId: string, rng: Random): string
	local row = Config.BiteTable[spotId]
	assert(row, "No bite table for spot: " .. tostring(spotId))
	local roll = rng:NextNumber()
	local cursor = 0
	for _, speciesId in { "Sunfin", "Rustbelly", "Lanternjaw" } do
		cursor += (row[speciesId] or 0) :: number
		if roll < cursor then
			return speciesId
		end
	end
	return "Sunfin"
end

-- GDD §6: on cast, the nearest ApproachCount (1-2) fish approach the bobber.
function FishAI.NotifyCast(spotId: string, bobberPos: Vector3)
	FishAI.EnsureSpot(spotId)
	local school = FishAI._spots[spotId]
	local sorted = table.clone(school)
	table.sort(sorted, function(a: FishEntry, b: FishEntry)
		return (a.pos - bobberPos).Magnitude < (b.pos - bobberPos).Magnitude
	end)
	local now = os.clock()
	for i = 1, math.min(Config.FishAI.ApproachCount, #sorted) do
		local fish = sorted[i]
		if fish.state == "patrol" then
			if fish.species == "Rustbelly" then
				-- Shy: circles the bobber CircleDelay seconds before biting.
				fish.state = "circle"
				fish.stateUntil = now + (Config.Species.Rustbelly.CircleDelay :: number)
			else
				fish.state = "approach"
				fish.stateUntil = now + 30 -- released by bite/fail/catch paths
			end
			fish.target = bobberPos
		end
	end
end

-- GDD §6: on hook-fail the school scatters for ScatterTime (5 s).
function FishAI.NotifyHookFail(spotId: string)
	local school = FishAI._spots[spotId]
	if not school then
		return
	end
	local spot = Config.Spots[spotId]
	local now = os.clock()
	for _, fish in school do
		if fish.state == "approach" or fish.state == "circle" then
			fish.state = "scatter"
			fish.stateUntil = now + Config.FishAI.ScatterTime
			-- Scatter waypoint: away from the bobber, still near the spot.
			local away = fish.pos - (fish.target or spot.Center)
			if away.Magnitude < 0.01 then
				away = Vector3.new(1, 0, 0)
			end
			fish.waypoint = fish.pos + away.Unit * Config.FishAI.WaypointRadius
			fish.target = nil
		end
	end
end

-- A catch removes one fish of that species (the hooked one); it respawns
-- after RespawnTime (20 s) per GDD §6.
function FishAI.NotifyCatch(spotId: string, speciesId: string)
	local school = FishAI._spots[spotId]
	if not school then
		return
	end
	for _, fish in school do
		if fish.species == speciesId and fish.state ~= "gone" then
			fish.state = "gone"
			fish.respawnAt = os.clock() + Config.FishAI.RespawnTime
			fish.target = nil
			return
		end
	end
end

-- Read-only view for the Lead Dev's model binder. Mutate via Notify* only.
function FishAI.GetFish(spotId: string): { FishEntry }
	FishAI.EnsureSpot(spotId)
	return FishAI._spots[spotId]
end

function FishAI.Tick(dt: number)
	local now = os.clock()
	for spotId, school in FishAI._spots do
		local spot = Config.Spots[spotId]
		for _, fish in school do
			if fish.state == "gone" then
				if fish.respawnAt and now >= fish.respawnAt then
					local fresh = makeFish(spotId, spot)
					fish.species = fresh.species
					fish.pos = fresh.pos
					fish.waypoint = fresh.waypoint
					fish.speed = fresh.speed
					fish.state = "patrol"
					fish.respawnAt = nil
				end
				continue
			end
			if (fish.state == "scatter" or fish.state == "circle") and now >= fish.stateUntil then
				fish.state = "patrol"
				fish.waypoint = randomOffset(FishAI._rng, spot.Center, Config.FishAI.WaypointRadius)
				if fish.stateUntil ~= 0 and fish.state == "patrol" then
					fish.target = nil
				end
			end

			local goal: Vector3
			local speed = fish.speed
			if fish.state == "approach" and fish.target then
				goal = fish.target
				speed = math.max(speed, 6) -- visibly hurries to the bobber
			elseif fish.state == "circle" and fish.target then
				-- Orbit the bobber at ~3 studs so the shadow visibly circles.
				local t = now * 2.2 + fish.id
				goal = fish.target + Vector3.new(math.cos(t) * 3, 0.5, math.sin(t) * 3)
				speed = math.max(speed, 5)
			else
				goal = fish.waypoint
				if (fish.pos - goal).Magnitude < 2 then
					fish.waypoint = randomOffset(FishAI._rng, spot.Center, Config.FishAI.WaypointRadius)
					goal = fish.waypoint
				end
			end

			local delta = goal - fish.pos
			local dist = delta.Magnitude
			if dist > 0.01 then
				local step = math.min(dist, speed * dt)
				fish.pos += delta.Unit * step
			end
		end
	end
end

local _started = false

function FishAI.Init()
	if _started then
		return
	end
	_started = true
	for spotId in Config.Spots do
		FishAI.EnsureSpot(spotId)
	end
	game:GetService("RunService").Heartbeat:Connect(function(dt: number)
		FishAI.Tick(dt)
	end)
end

return FishAI
