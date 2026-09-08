--!strict
-- Abyssal — UI client price/rod mirror (client-side ONLY).
-- Mirrors GDD §6 species values (10/30/80) and §7 rod costs/stats so the HUD,
-- bucket preview, and shop can render without waiting on the server.
-- The server stays authoritative: these numbers are display hints only.

local Prices = {}

Prices.BucketCap = 12 -- GDD §7: forces sell trips

Prices.SpeciesOrder = { "Sunfin", "Rustbelly", "Lanternjaw" }

Prices.Species = {
	Sunfin = {
		Name = "Sunfin",
		Value = 10, -- Pearls (GDD §6)
		Initial = "S",
		Color = Color3.fromRGB(250, 204, 33), -- yellow/blue damsel
		Blurb = "Bold, bites fast",
	},
	Rustbelly = {
		Name = "Rustbelly",
		Value = 30,
		Initial = "R",
		Color = Color3.fromRGB(110, 190, 100), -- scrap-metal catfish green
		Blurb = "Shy, circles first",
	},
	Lanternjaw = {
		Name = "Lanternjaw",
		Value = 80, -- rare catch (GDD §6)
		Initial = "L",
		Color = Color3.fromRGB(168, 85, 247), -- bioluminescent lure purple
		Blurb = "RARE — deep monster",
	},
}

Prices.RodOrder = { "Twig", "Coral", "Abyss" }

-- Costs mirror Config.Rods (GDD §7: 250 / 800). Bars are 0..1 display stats
-- ("stats as bars not numbers" per GDD §8): Speed ~ bite rate, Strength ~ line.
Prices.Rods = {
	Twig = {
		Name = "Twig Rod",
		Cost = 0,
		Speed = 0.33,
		Strength = 0.20,
		Blurb = "Bendy starter",
	},
	Coral = {
		Name = "Coral Rod",
		Cost = 250,
		Speed = 0.66,
		Strength = 0.60,
		Blurb = "Snappier cast",
	},
	Abyss = {
		Name = "Abyss Rod",
		Cost = 800,
		Speed = 1.0,
		Strength = 1.0,
		Blurb = "Glowing deep-line",
	},
}

-- Client preview: estimated sale value of a bucket { [species]: count }.
function Prices.BucketValue(bucket: { [string]: number }): number
	local total = 0
	if typeof(bucket) ~= "table" then
		return 0
	end
	for species, count in bucket do
		local row = Prices.Species[species]
		if row and typeof(count) == "number" then
			total += row.Value * count
		end
	end
	return total
end

function Prices.SpeciesColor(species: string): Color3
	local row = Prices.Species[species]
	if row then
		return row.Color
	end
	return Color3.fromRGB(159, 184, 181)
end

function Prices.SpeciesName(species: string): string
	local row = Prices.Species[species]
	if row then
		return row.Name
	end
	return tostring(species)
end

function Prices.RodName(rodId: string): string
	local row = Prices.Rods[rodId]
	if row then
		return row.Name
	end
	return tostring(rodId)
end

return Prices
