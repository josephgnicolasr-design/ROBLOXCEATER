--!strict
-- Abyssal — FishingService (server).
-- GDD §5 pipeline: cast (0.6 s) -> wait (per-species bite timer x rod
-- BiteMult) -> hook (1.2 s window) -> reel minigame (server authority per
-- Config.Reel: progress/tension/catcher/marker/surges) -> win = catch,
-- lose = LineFailed ("escape"|"tension"|"snap"|"cancel"|"bucket_full").
-- Every signal uses the Remotes contract. All tuned numbers come from Config.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("AbyssalShared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local SharedRods = require(Shared:WaitForChild("RodSystem"))

local ServerFolder = script.Parent
local PlayerState = require(ServerFolder:WaitForChild("PlayerState"))
local FishAI = require(ServerFolder:WaitForChild("FishAI"))
local EconomyService = require(ServerFolder:WaitForChild("EconomyService"))

local FishingService = {}
FishingService._rng = Random.new()

-- Generation guard: each cast bumps data.cast.gen; delayed threads capture
-- (player, gen) and abort silently when they no longer match.
local function isCurrent(data: PlayerState.PlayerData, gen: number): boolean
	return data.cast ~= nil and data.cast.gen == gen
end

local function fireClient(player: Player, remoteName: string, payload: any)
	local event = ReplicatedStorage:FindFirstChild(remoteName) :: RemoteEvent?
	if event then
		event:FireClient(player, payload)
	end
end

local function failLine(player: Player, reason: string, message: string)
	local data = PlayerState.Get(player)
	if data and data.cast then
		FishAI.NotifyHookFail(data.cast.spotId)
	end
	if data then
		PlayerState.InvalidateCast(data)
	end
	fireClient(player, Remotes.LineFailed, { reason = reason, message = message })
end

local function inSpot(position: Vector3): (boolean, string?)
	for spotId, spot in Config.Spots do
		local flat = Vector3.new(position.X - spot.Center.X, 0, position.Z - spot.Center.Z)
		if flat.Magnitude <= spot.RingRadius then
			return true, spotId
		end
	end
	return false, nil
end

local function rollSurges(speciesId: string): { { start: number, duration: number } }
	local species = Config.Species[speciesId]
	local count = FishingService._rng:NextInteger(species.SurgesMin, species.SurgesMax)
	-- Fights run ~6-12 s; surges land in the 1..7 s window (GDD §5 feel).
	local surges = {}
	for _ = 1, count do
		table.insert(surges, {
			start = FishingService._rng:NextNumber(1, 7),
			duration = Config.Reel.SurgeDuration,
		})
	end
	table.sort(surges, function(a, b)
		return a.start < b.start
	end)
	return surges
end

local function isSurging(reel: any): boolean
	for _, surge in reel.surges do
		if reel.elapsed >= surge.start and reel.elapsed <= surge.start + surge.duration then
			return true
		end
	end
	return false
end

-- Marker oscillates on the 0..1 track at the species OscHz (GDD §6).
local function markerAt(speciesId: string, phase: number): number
	local hz = (Config.Species[speciesId] :: any).OscHz :: number
	return 0.5 + 0.42 * math.sin(phase * math.pi * 2 * hz)
end

local function rollWeight(): number
	-- Flavor weight ±WeightVariance (GDD §7). Display-only, ~1 kg base.
	return 1 + (FishingService._rng:NextNumber() * 2 - 1) * Config.Economy.WeightVariance
end

-- -- Reel loop (server authority, replicates at Config.Reel.ServerTickHz) --

local function runReel(player: Player, data: PlayerState.PlayerData, gen: number)
	local cast = data.cast
	if not cast or not cast.reel then
		return
	end
	local reel = cast.reel
	local speciesId = cast.species
	local rodId = data.currentRod
	local rod = Config.Rods[rodId]
	local tickDt = 1 / Config.Reel.ServerTickHz

	while isCurrent(data, gen) and cast.phase == "reel" do
		reel.elapsed += tickDt
		reel.markerPhase += tickDt

		-- Catcher bar: hold raises, release drops (GDD §5).
		if reel.holding then
			reel.catcher = math.min(1, reel.catcher + Config.Reel.CatcherRise * tickDt)
		else
			reel.catcher = math.max(0, reel.catcher - Config.Reel.CatcherFall * tickDt)
		end

		local marker = markerAt(speciesId, reel.markerPhase)
		local surging = isSurging(reel)
		local onTarget = math.abs(reel.catcher - marker) <= Config.Reel.OnTargetWindow

		-- Progress: fill on-target (x rod ProgressRate), drain off-target.
		if onTarget then
			reel.progress = math.min(100, reel.progress + Config.Reel.ProgressPerSec * rod.ProgressRate * tickDt)
		else
			reel.progress = math.max(0, reel.progress - Config.Reel.DrainPerSec * tickDt)
		end

		-- Tension: holding during a red-flash surge spikes it (release!).
		if surging and reel.holding then
			reel.tension = math.min(100, reel.tension + Config.Reel.TensionRise * tickDt)
			-- GDD §6 soft gating: per-surge snap roll while holding in flash.
			if SharedRods.RollSnap(rodId, speciesId, FishingService._rng) then
				failLine(player, "snap", "Line snapped! That one was too strong for this rod.")
				return
			end
		else
			reel.tension = math.max(0, reel.tension - Config.Reel.TensionFall * tickDt)
		end

		fireClient(player, Remotes.ReelState, {
			progress = reel.progress,
			tension = reel.tension,
			catcher = reel.catcher,
			marker = marker,
			surge = surging,
		})

		if reel.progress >= 100 then
			FishingService.ResolveCatch(player, data, gen)
			return
		end
		if reel.tension >= 100 then
			failLine(player, "tension", "Too much tension — the line gave out!")
			return
		end
		task.wait(tickDt)
	end
end

function FishingService.ResolveCatch(player: Player, data: PlayerState.PlayerData, gen: number)
	local cast = data.cast
	if not isCurrent(data, gen) or not cast then
		return
	end
	local speciesId = cast.species
	if PlayerState.BucketIsFull(data) then
		failLine(player, "bucket_full", "Bucket full — sell at Old Marrow first!")
		return
	end
	PlayerState.TryAddFish(data, speciesId)
	FishAI.NotifyCatch(cast.spotId, speciesId)
	PlayerState.InvalidateCast(data)
	local value = (Config.Species[speciesId] :: any).Sell :: number
	fireClient(player, Remotes.CatchResult, {
		species = speciesId,
		weight = rollWeight(),
		value = value,
	})
	EconomyService.EmitEconomy(player)
	PlayerState.NotifyChanged(player)
end

-- -- Pipeline stages --

-- GDD §5(1): 0.6 s cast lockout, bobber lands within BobberDistance ahead.
function FishingService.TryCast(player: Player, claimedSpotId: string)
	local data = PlayerState.GetOrCreate(player)
	if data.cast then
		return -- already fishing; R cancels first
	end
	if PlayerState.IsOnMissCooldown(data) then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local ok, actualSpot = inSpot(root.Position)
	if not ok or actualSpot ~= claimedSpotId then
		fireClient(player, Remotes.SpotPrompt, { inSpot = ok, spotId = actualSpot })
		return
	end
	local spotId: string = actualSpot :: string

	local forward = root.CFrame.LookVector
	forward = Vector3.new(forward.X, 0, forward.Z)
	if forward.Magnitude < 0.01 then
		forward = Vector3.new(0, 0, -1)
	end
	local bobberPos = root.Position + forward.Unit * Config.Fishing.BobberDistance
		+ Vector3.new(0, -2, 0)

	local gen = (data.cast and data.cast.gen or 0) + 1
	local speciesId = FishAI.RollSpecies(spotId, FishingService._rng)
	PlayerState.SetCast(data, {
		phase = "cast",
		spotId = spotId,
		bobberPos = bobberPos,
		species = speciesId,
		gen = gen,
		hookExpiresAt = nil,
		reel = nil,
	})
	fireClient(player, Remotes.CastStarted, { spotId = spotId })
	FishAI.NotifyCast(spotId, bobberPos)

	task.delay(Config.Fishing.CastTime, function()
		if not isCurrent(data, gen) then
			return
		end
		local live = data.cast :: PlayerState.CastState
		live.phase = "wait"
		-- GDD §5(2): per-species bite timer x rod BiteMult.
		local waitSecs = SharedRods.RollBiteTime(speciesId, data.currentRod, FishingService._rng)
		if speciesId == "Rustbelly" then
			-- Shy tease pages the approach/circle VFX before the "!" lands.
			waitSecs += (Config.Species.Rustbelly.CircleDelay :: number)
		end
		task.delay(waitSecs, function()
			if not isCurrent(data, gen) then
				return
			end
			local waiting = data.cast :: PlayerState.CastState
			waiting.phase = "bite"
			waiting.hookExpiresAt = os.clock() + Config.Fishing.HookWindow
			fireClient(player, Remotes.BitePrompt, { expiresIn = Config.Fishing.HookWindow })
			task.delay(Config.Fishing.HookWindow, function()
				if not isCurrent(data, gen) then
					return
				end
				local biting = data.cast :: PlayerState.CastState
				if biting.phase == "bite" then
					-- GDD §5(3): miss = escape, 2 s cooldown, no penalty.
					PlayerState.ApplyMissCooldown(data)
					failLine(player, "escape", "It slipped away… something big circles below.")
				end
			end)
		end)
	end)
end

-- GDD §5(3): E inside the 1.2 s window starts the reel minigame.
function FishingService.TryHook(player: Player)
	local data = PlayerState.Get(player)
	if not data or not data.cast then
		return
	end
	local cast = data.cast
	if cast.phase ~= "bite" then
		return
	end
	if cast.hookExpiresAt and os.clock() > cast.hookExpiresAt then
		return -- expiry thread owns the escape
	end
	cast.phase = "reel"
	cast.reel = {
		progress = 0,
		tension = 0,
		catcher = 0.5,
		markerPhase = 0,
		elapsed = 0,
		surges = rollSurges(cast.species),
		nextSurgeIdx = 1,
		holding = false,
	}
	task.spawn(runReel, player, data, cast.gen)
end

function FishingService.Cancel(player: Player)
	local data = PlayerState.Get(player)
	if not data or not data.cast then
		return
	end
	failLine(player, "cancel", "Line reeled in.")
end

function FishingService.SetReelHolding(player: Player, holding: boolean)
	local data = PlayerState.Get(player)
	if data and data.cast and data.cast.reel then
		data.cast.reel.holding = holding
	end
end

-- Spot prompt polling: HUD shows "Press E to cast" inside a ring.
function FishingService.PollSpotPrompts()
	for _, player in game:GetService("Players"):GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local ok, spotId = inSpot(root.Position)
			fireClient(player, Remotes.SpotPrompt, { inSpot = ok, spotId = spotId })
		end
	end
end

local _started = false

function FishingService.Init()
	if _started then
		return
	end
	_started = true

	local function listen(remoteName: string, fn: (Player, any) -> ())
		local event = ReplicatedStorage:FindFirstChild(remoteName) :: RemoteEvent?
		if event then
			event.OnServerEvent:Connect(fn)
		end
	end
	listen(Remotes.CastRequest, function(player: Player, payload: any)
		local spotId = if typeof(payload) == "table" then payload.spotId else nil
		if typeof(spotId) == "string" then
			FishingService.TryCast(player, spotId)
		end
	end)
	listen(Remotes.HookAttempt, function(player: Player)
		FishingService.TryHook(player)
	end)
	listen(Remotes.CancelLine, function(player: Player)
		FishingService.Cancel(player)
	end)
	listen(Remotes.ReelInput, function(player: Player, payload: any)
		if typeof(payload) == "table" and typeof(payload.holding) == "boolean" then
			FishingService.SetReelHolding(player, payload.holding)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			FishingService.PollSpotPrompts()
		end
	end)
end

return FishingService
