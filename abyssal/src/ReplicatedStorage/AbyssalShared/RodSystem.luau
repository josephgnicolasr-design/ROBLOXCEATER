-- Abyssal — RodSystem (shared, pure logic; safe to require on client for
-- shop stat bars, but purchases are validated server-side in EconomyService).
-- Implements GDD §7 rod table + §6 soft-gating line-snap odds.

local Config = require(script.Parent:WaitForChild("Config"))

local RodSystem = {}

-- Ordered rod list for the shop UI (Twig -> Coral -> Abyss).
function RodSystem.GetOrder(): { string }
	return Config.RodOrder
end

function RodSystem.GetStats(rodId: string)
	local rod = Config.Rods[rodId]
	assert(rod, "Unknown rod: " .. tostring(rodId))
	return rod
end

-- Bite wait for a species under a rod: rand(species range) x rod multiplier.
function RodSystem.RollBiteTime(speciesId: string, rodId: string, rng: Random): number
	local sp = Config.Species[speciesId]
	local rod = Config.Rods[rodId]
	assert(sp and rod, "Bad species/rod roll")
	local base = rng:NextNumber(sp.BiteTimeMin, sp.BiteTimeMax)
	return base * rod.BiteMult
end

-- Soft gating: per-surge snap roll, only while the player holds during red flash.
-- Returns true when the line snaps (fish escapes, counts as a near-miss).
function RodSystem.RollSnap(rodId: string, speciesId: string, rng: Random): boolean
	local rod = Config.Rods[rodId]
	assert(rod, "Unknown rod: " .. tostring(rodId))
	local risk = (rod.SnapRisk[speciesId] or 0) :: number
	return rng:NextNumber() < risk
end

-- Can this rod ever lose to this species? Used for shop "feel" copy.
function RodSystem.DescribeGate(rodId: string, speciesId: string): string
	local risk = ((Config.Rods[rodId] :: any).SnapRisk[speciesId] or 0) :: number
	if risk <= 0 then
		return "safe"
	elseif risk < 0.3 then
		return "risky"
	else
		return "likely to snap"
	end
end

return RodSystem
