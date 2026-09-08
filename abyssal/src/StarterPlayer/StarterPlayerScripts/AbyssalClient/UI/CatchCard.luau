--!strict
-- Abyssal — CatchCard (client).
-- Catch toast per GDD §8: species silhouette initial, name, flavor weight,
-- sell value, rare styling for Lanternjaw (contract has no rarity flag, so
-- the species name IS the rarity signal). Shows 2.2 s, skippable with E.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientFolder = script.Parent.Parent
local UI = script.Parent
local NetListener = require(ClientFolder:WaitForChild("NetListener"))
local Theme = require(UI:WaitForChild("Config"):WaitForChild("Theme"))
local Prices = require(UI:WaitForChild("Config"):WaitForChild("Prices"))
local Remotes = (require(ReplicatedStorage:WaitForChild("AbyssalShared"):WaitForChild("Remotes")) :: any)

local CatchCard = {}

local _gui: ScreenGui? = nil
local _unsubs: { () -> () } = {}
local _card: Frame? = nil
local _nameLabel: TextLabel? = nil
local _artLabel: TextLabel? = nil
local _detailLabel: TextLabel? = nil
local _valueLabel: TextLabel? = nil
local _rareLabel: TextLabel? = nil
local _gen = 0

local CARD_SECS = 2.2 -- GDD §8
local RARE_SPECIES = "Lanternjaw"

local function trackUnsub(f: () -> ())
	table.insert(_unsubs, f)
end

function CatchCard.Skip()
	_gen += 1
	if _card then
		_card.Visible = false
	end
end

local function show(payload: any)
	local card = _card
	if not card then
		return
	end
	_gen += 1
	local gen = _gen
	local species = "Sunfin"
	local weight = 0
	local value = 0
	if typeof(payload) == "table" then
		if typeof((payload :: any).species) == "string" then
			species = (payload :: any).species
		end
		if typeof((payload :: any).weight) == "number" then
			weight = (payload :: any).weight
		end
		if typeof((payload :: any).value) == "number" then
			value = (payload :: any).value
		end
	end
	local rare = species == RARE_SPECIES
	if _nameLabel then
		_nameLabel.Text = Prices.SpeciesName(species)
		if rare then
			_nameLabel.TextColor3 = Theme.Colors.Rare
		else
			_nameLabel.TextColor3 = Theme.Colors.Text
		end
	end
	if _artLabel then
		local row = Prices.Species[species]
		_artLabel.Text = if row then row.Initial else "?"
		_artLabel.TextColor3 = Prices.SpeciesColor(species)
	end
	if _detailLabel then
		_detailLabel.Text = string.format("%.1f kg", weight)
	end
	if _valueLabel then
		_valueLabel.Text = "+" .. tostring(value) .. " Pearls"
	end
	if _rareLabel then
		_rareLabel.Visible = rare
	end
	card.Visible = true
	task.delay(CARD_SECS, function()
		if gen == _gen and card then
			card.Visible = false
		end
	end)
end

function CatchCard.Mount(parent: PlayerGui)
	if _gui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "AbyssalCatchCard"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30 -- above bite/reel
	gui.Parent = parent
	_gui = gui

	local card = Theme.make("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.30, 0),
		Size = UDim2.new(0, 380, 0, 210),
		Visible = false,
	}) :: Frame
	Theme.panel(card, true)
	_card = card
	_artLabel = Theme.make("TextLabel", {
		Parent = card,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Bold,
		Text = "?",
		TextSize = 72,
		Position = UDim2.new(0, 0, 0, 6),
		Size = UDim2.new(0, 120, 0, 110),
	}) :: TextLabel
	Theme.stroke(_artLabel)
	_nameLabel = Theme.make("TextLabel", {
		Parent = card,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Bold,
		Text = "",
		TextSize = Theme.Sizes.Title,
		Position = UDim2.new(0, 120, 0, 14),
		Size = UDim2.new(1, -130, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
	}) :: TextLabel
	Theme.stroke(_nameLabel)
	_detailLabel = Theme.make("TextLabel", {
		Parent = card,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Regular,
		Text = "",
		TextColor3 = Theme.Colors.Dim,
		TextSize = Theme.Sizes.Body,
		Position = UDim2.new(0, 120, 0, 58),
		Size = UDim2.new(1, -130, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
	}) :: TextLabel
	_valueLabel = Theme.make("TextLabel", {
		Parent = card,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Bold,
		Text = "",
		TextColor3 = Theme.Colors.Gold,
		TextSize = Theme.Sizes.Number,
		Position = UDim2.new(0, 120, 0, 88),
		Size = UDim2.new(1, -130, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
	}) :: TextLabel
	Theme.stroke(_valueLabel, Theme.Colors.Gold)
	_rareLabel = Theme.make("TextLabel", {
		Parent = card,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Bold,
		Text = "✦ RARE CATCH ✦",
		TextColor3 = Theme.Colors.Rare,
		TextSize = 20,
		Position = UDim2.new(0, 0, 0, 128),
		Size = UDim2.new(1, 0, 0, 30),
		Visible = false,
	}) :: TextLabel
	Theme.stroke(_rareLabel, Theme.Colors.Rare)
	local skipHint = Theme.make("TextLabel", {
		Parent = card,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Regular,
		Text = "Press E to continue",
		TextColor3 = Theme.Colors.Dim,
		TextSize = Theme.Sizes.Small,
		Position = UDim2.new(0, 0, 0, 162),
		Size = UDim2.new(1, 0, 0, 24),
	}) :: TextLabel
	(skipHint :: TextLabel).TextTransparency = 0.2

	-- Tap card to skip too (mobile-friendly; E skip bound below).
	local skipBtn = Theme.make("TextButton", {
		Parent = card,
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.new(1, 0, 1, 0),
	}) :: TextButton
	skipBtn.Activated:Connect(function()
		CatchCard.Skip()
	end)

	-- E-skip: card listens for E Begin while visible (passes through so E
	-- still reaches InputController's cast/hook binding).
	ContextActionService:BindAction("AbyssalCatchSkip", function(_, state: EnumItem)
		if state == Enum.UserInputState.Begin and _card and _card.Visible then
			CatchCard.Skip()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.E)

	trackUnsub(NetListener.On(Remotes.CatchResult, show))
end

function CatchCard.Unmount()
	for _, unsub in _unsubs do
		pcall(unsub)
	end
	_unsubs = {}
	pcall(function()
		ContextActionService:UnbindAction("AbyssalCatchSkip")
	end)
	_card = nil
	_nameLabel = nil
	_artLabel = nil
	_detailLabel = nil
	_valueLabel = nil
	_rareLabel = nil
	if _gui then
		pcall(function()
			(_gui :: ScreenGui):Destroy()
		end)
		_gui = nil
	end
end

return CatchCard
