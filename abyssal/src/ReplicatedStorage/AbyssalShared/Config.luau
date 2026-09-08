--!strict
-- Abyssal — single tuning file. EVERY gameplay number lives here.
-- Each block cites its GDD section. Tuning later = edit this file only.
-- First-pass values per GDD tables; scripter may tune ±30% (GDD §6).

local Config = {}

-- GDD §3/§5: swim movement targets (feel: tuned accel/damping over raw speed).
Config.Swim = {
	BaseSpeed = 16, -- studs/s cruise
	SprintSpeed = 24, -- held Shift
	VerticalSpeed = 12, -- Space up / C or Ctrl down
	AccelLerp = 8, -- higher = snappier, lower = floatier
	EmptyOxygenSlow = 0.20, -- GDD §3: at empty oxygen, swim 20% slower (never a fail state)
}

-- GDD §3: flavor oxygen bar. Drains over ~3 min, refills at surface or breath vents.
Config.Oxygen = {
	Max = 100,
	DrainTime = 180, -- seconds to drain full -> empty
	RefillPerSec = 40, -- at surface or inside a vent radius
	SurfaceY = 0, -- water surface height; y >= this counts as "at surface"
}

-- GDD §4: three spots, triangle ~60-90 studs apart. Positions are placeholders
-- for the Lead Dev's map build; gameplay only needs Center + RingRadius + Depth.
Config.Spots = {
	Reef = {
		Name = "Reef Gardens",
		Center = Vector3.new(0, -15, 80),
		RingRadius = 18,
		Depth = 15,
		VentOffset = Vector3.new(4, -14, 76), -- breath-vent bubble column (refill zone)
		VentRadius = 6,
	},
	Wreck = {
		Name = "The Rustwreck",
		Center = Vector3.new(70, -35, -40),
		RingRadius = 20,
		Depth = 35,
		VentOffset = Vector3.new(66, -34, -44),
		VentRadius = 6,
	},
	Trench = {
		Name = "Trench Edge",
		Center = Vector3.new(-70, -60, -50),
		RingRadius = 22,
		Depth = 60,
		VentOffset = Vector3.new(-66, -59, -46),
		VentRadius = 6,
	},
}

-- GDD §5: fishing pipeline timings.
Config.Fishing = {
	CastTime = 0.6, -- cast animation lockout before bobber lands
	BobberDistance = 12, -- bobber lands <= 12 studs ahead of caster
	HookWindow = 1.2, -- seconds to press E on "!" before escape
	MissCooldown = 2.0, -- no-penalty cooldown after a missed hook
	ShopPromptDistance = 12, -- studs from Old Marrow to open trade
}

-- GDD §6: species table. BiteTime in seconds; OscHz = reel marker oscillation
-- speed; Surges = {min,max} red-flash surges per fight.
Config.Species = {
	Sunfin = {
		Name = "Sunfin",
		Sell = 10, -- Pearls (GDD §6)
		BiteTimeMin = 3,
		BiteTimeMax = 6,
		OscHz = 0.8,
		SurgesMin = 0,
		SurgesMax = 1,
		PatrolSpeedMin = 4,
		PatrolSpeedMax = 8,
	},
	Rustbelly = {
		Name = "Rustbelly",
		Sell = 30,
		BiteTimeMin = 6,
		BiteTimeMax = 11,
		OscHz = 1.3,
		SurgesMin = 1,
		SurgesMax = 2,
		PatrolSpeedMin = 4,
		PatrolSpeedMax = 8,
		CircleDelay = 2.5, -- GDD §6: shy, circles bobber ~2-3 s before biting
	},
	Lanternjaw = {
		Name = "Lanternjaw",
		Sell = 80,
		BiteTimeMin = 5,
		BiteTimeMax = 9,
		OscHz = 1.9,
		SurgesMin = 2,
		SurgesMax = 4,
		PatrolSpeedMin = 4,
		PatrolSpeedMax = 8,
	},
}

-- GDD §6 bite rarity: per-spot weights. Reef remainder falls back to Sunfin
-- ("common fish only" water; see README assumption).
Config.BiteTable = {
	Reef = { Sunfin = 0.65, Rustbelly = 0.0, Lanternjaw = 0.0 }, -- rest -> Sunfin
	Wreck = { Sunfin = 0.45, Rustbelly = 0.55, Lanternjaw = 0.0 },
	Trench = { Sunfin = 0.0, Rustbelly = 0.60, Lanternjaw = 0.40 },
}

-- GDD §6 fish AI population.
Config.FishAI = {
	PerSpotMin = 4,
	PerSpotMax = 6,
	RespawnTime = 20, -- despawn/respawn cycle
	ApproachCount = 2, -- nearest 1-2 fish approach the bobber on cast
	ScatterTime = 5, -- scatter duration after a failed hook
	WaypointRadius = 14, -- patrol wandering radius around spot center
}

-- GDD §7 rods. BiteMult multiplies bite time (lower = faster). SnapRisk[rod][species]
-- = chance the line snaps per surge while the player holds during red flash.
-- Soft gating only: no hard locks anywhere (GDD §6 rod gating).
Config.Rods = {
	Twig = { Name = "Twig Rod", Cost = 0, BiteMult = 1.0, ProgressRate = 1.0,
		SnapRisk = { Sunfin = 0, Rustbelly = 0, Lanternjaw = 0.50 } },
	Coral = { Name = "Coral Rod", Cost = 250, BiteMult = 0.8, ProgressRate = 1.0,
		SnapRisk = { Sunfin = 0, Rustbelly = 0, Lanternjaw = 0.15 } },
	Abyss = { Name = "Abyss Rod", Cost = 800, BiteMult = 0.7, ProgressRate = 1.10,
		SnapRisk = { Sunfin = 0, Rustbelly = 0, Lanternjaw = 0 } },
}
Config.RodOrder = { "Twig", "Coral", "Abyss" } -- shop display / upgrade order

-- GDD §7 economy.
Config.Economy = {
	BucketCap = 12, -- forces sell trips
	WeightVariance = 0.20, -- flavor weight random ±20% on catch card
}

-- GDD §5 reel minigame. Calibrated so fights run ~6-12 s.
-- Catcher/marker live on a 0..1 track; on-target window fills Progress.
Config.Reel = {
	OnTargetWindow = 0.12, -- |catcher - marker| under this counts as on-target
	ProgressPerSec = 11, -- on-target fill (%/s); x rod ProgressRate
	DrainPerSec = 12, -- off-target drain (%/s)
	CatcherRise = 1.2, -- track units/s while holding
	CatcherFall = 1.0, -- track units/s while released
	TensionRise = 55, -- tension %/s while holding during a surge (release!)
	TensionFall = 30, -- tension %/s decay otherwise
	SurgeDuration = 1.2, -- red-flash window per surge
	ServerTickHz = 10, -- reel state replication rate to client
}

-- GDD §10.4: economy tuning metrics the Designer flagged.
Config.Telemetry = {
	SampleWindow = 60, -- Pearls/min computed over trailing 60 s
}

-- GDD §3/§10.6: best-effort DataStore save.
Config.Save = {
	DatastoreName = "AbyssalMVP_v1",
	AutosaveSecs = 120,
}

return Config
