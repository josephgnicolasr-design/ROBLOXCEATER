--!strict
-- Abyssal — ShopView (client).
-- Shop screen per GDD §8: two tabs (Sell with one-click Sell All + per-fish
-- sell and running total; Rods with 3 cards, stats as bars, cost,
-- owned/equipped state, buy confirm). Esc/E closes. Sends ShopInteract /
-- ShopSellAll / ShopSellOne / ShopBuyRod — via InputController helpers so all
-- server-bound sends stay in one module.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientFolder = script.Parent.Parent
local UI = script.Parent
local NetListener = require(ClientFolder:WaitForChild("NetListener"))
local InputController = require(ClientFolder:WaitForChild("InputController"))
local Theme = require(UI:WaitForChild("Config"):WaitForChild("Theme"))
local Prices = require(UI:WaitForChild("Config"):WaitForChild("Prices"))
local Remotes = (require(ReplicatedStorage:WaitForChild("AbyssalShared"):WaitForChild("Remotes")) :: any)

local ShopView = {}

local _gui: ScreenGui? = nil
local _unsubs: { () -> () } = {}
local _frame: Frame? = nil
local _sellTab: Frame? = nil
local _rodsTab: Frame? = nil
local _sellBtn: TextButton? = nil
local _rodsBtn: TextButton? = nil
local _confirm: Frame? = nil
local _confirmLabel: TextLabel? = nil
local _pendingRod: string? = nil
local _equippedRod: string? = nil

local _snapshot: any = nil
local _bound = false

local function trackUnsub(f: () -> ())
	table.insert(_unsubs, f)
end

local function bar(parent: Instance, frac: number, color: Color3, y: number): Frame
	local back = Theme.make("Frame", {
		Parent = parent,
		BackgroundColor3 = (Theme.Colors :: any).Ink,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 8, 0, y),
		Size = UDim2.new(1, -16, 0, 10),
	}) :: Frame
	local fill = Theme.make("Frame", {
		Parent = back,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.new(math.clamp(frac, 0, 1), 0, 1, 0),
	}) :: Frame
	return fill
end

local function bigButton(parent: Instance, text: string, pos: UDim2, size: UDim2, fill: Color3): TextButton
	local b = Theme.make("TextButton", {
		Parent = parent,
		BackgroundColor3 = fill,
		Font = Theme.Fonts.Bold,
		Text = text,
		TextColor3 = Theme.Colors.Ink,
		TextSize = Theme.Sizes.Body,
		Position = pos,
		Size = size,
	}) :: TextButton
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = b
	return b
end

local function clearChildren(f: Instance)
	for _, ch in f:GetChildren() do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
end

-- Re-render both tabs from the latest ShopState snapshot.
local function render()
	if not _frame or not _sellTab or not _rodsTab then
		return
	end
	clearChildren(_sellTab)
	clearChildren(_rodsTab)
	local snap = _snapshot
	local pearls = 0
	local bucketValue = 0
	local sellLines: { any } = {}
	local rods: { any } = {}
	if typeof(snap) == "table" then
		if typeof(snap.pearls) == "number" then
			pearls = snap.pearls
		end
		if typeof(snap.bucketValue) == "number" then
			bucketValue = snap.bucketValue
		end
		if typeof(snap.sellLines) == "table" then
			sellLines = snap.sellLines
		end
		if typeof(snap.rods) == "table" then
			rods = snap.rods
		end
	end
	if bucketValue == 0 and #sellLines > 0 then
		for _, line in sellLines do
			if typeof(line) == "table" then
				bucketValue += (line.count or 0) * (line.unitValue or 0)
			end
		end
	end

	-- Header line (pearls + total) on the sell tab.
	local header = Theme.make("TextLabel", {
		Parent = _sellTab,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Bold,
		Text = string.format("%d P  ·  Bucket ≈%d P", pearls, bucketValue),
		TextColor3 = Theme.Colors.Gold,
		TextSize = Theme.Sizes.Number,
		Position = UDim2.new(0, 0, 0, 4),
		Size = UDim2.new(1, 0, 0, 32),
	}) :: TextLabel
	Theme.stroke(header, Theme.Colors.Gold)

	local y = 44
	for _, line in sellLines do
		if typeof(line) ~= "table" then
			continue
		end
		local species = tostring(line.species or "?")
		local count = tonumber(line.count) or 0
		local unit = tonumber(line.unitValue) or (Prices.Species[species] and Prices.Species[species].Value or 0)
		if count <= 0 then
			continue
		end
		local row = Theme.make("Frame", {
			Parent = _sellTab,
			BackgroundColor3 = Theme.Colors.Ink,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 8, 0, y),
			Size = UDim2.new(1, -16, 0, 52),
		}) :: Frame
		local icon = Theme.make("TextLabel", {
			Parent = row,
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Bold,
			Text = Prices.Species[species] and Prices.Species[species].Initial or "?",
			TextColor3 = Prices.SpeciesColor(species),
			TextSize = 24,
			Position = UDim2.new(0, 8, 0, 0),
			Size = UDim2.new(0, 40, 1, 0),
		}) :: TextLabel
		Theme.stroke(icon)
		local info = Theme.make("TextLabel", {
			Parent = row,
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Regular,
			Text = string.format("%s ×%d  (%d P ea)", Prices.SpeciesName(species), count, unit),
			TextColor3 = Theme.Colors.Text,
			TextSize = Theme.Sizes.Body,
			Position = UDim2.new(0, 52, 0, 0),
			Size = UDim2.new(1, -180, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
		}) :: TextLabel
		; (info :: any).TextTruncate = Enum.TextTruncate.AtEnd
		local sellOne = bigButton(row, "SELL", UDim2.new(1, -118, 0, 4), UDim2.new(0, 110, 0, 44), Theme.Colors.Teal)
		local sp = species
		sellOne.Activated:Connect(function()
			InputController.SellOne(sp)
		end)
		y += 58
	end
	local sellAll = bigButton(_sellTab, string.format("SELL ALL (≈%d P)", bucketValue), UDim2.new(0, 8, 1, -56), UDim2.new(1, -16, 0, 48), Theme.Colors.Gold)
	sellAll.Activated:Connect(function()
		InputController.SellAll()
	end)

	-- Rods tab: 3 cards, stats as bars, cost, owned/equipped, buy confirm.
	local ry = 8
	local order: { string } = {}
	if #rods > 0 then
		for _, r in rods do
			if typeof(r) == "table" and typeof(r.rodId) == "string" then
				table.insert(order, r.rodId)
			end
		end
	end
	if #order == 0 then
		order = { "Twig", "Coral", "Abyss" }
	end
	for _, rodId in order do
		local info: any = nil
		for _, r in rods do
			if typeof(r) == "table" and r.rodId == rodId then
				info = r
				break
			end
		end
		local static = Prices.Rods[rodId] or { Name = tostring(rodId), Cost = 0, Speed = 0.5, Strength = 0.5, Blurb = "" }
		local name = if info and typeof(info.name) == "string" then info.name else static.Name
		local cost = if info and typeof(info.cost) == "number" then info.cost else static.Cost
		local owned = if info and info.owned ~= nil then info.owned == true else (rodId == "Twig")
		local equipped = (rodId == _equippedRod) or (info and info.equipped == true)
		local card = Theme.make("Frame", {
			Parent = _rodsTab,
			BackgroundColor3 = Theme.Colors.Ink,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 8, 0, ry),
			Size = UDim2.new(1, -16, 0, 118),
		}) :: Frame
		local nm = Theme.make("TextLabel", {
			Parent = card,
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Bold,
			Text = name .. (if equipped then "  ● EQUIPPED" else ""),
			TextColor3 = if equipped then Theme.Colors.Green else Theme.Colors.Text,
			TextSize = Theme.Sizes.Body,
			Position = UDim2.new(0, 8, 0, 2),
			Size = UDim2.new(1, -140, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
		}) :: TextLabel
		; (nm :: any).TextTruncate = Enum.TextTruncate.AtEnd
		bar(card, static.Speed, Theme.Colors.Cyan, 32)
		bar(card, static.Strength, Theme.Colors.Gold, 46)
		local blurb = Theme.make("TextLabel", {
			Parent = card,
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Regular,
			Text = static.Blurb,
			TextColor3 = Theme.Colors.Dim,
			TextSize = Theme.Sizes.Small,
			Position = UDim2.new(0, 8, 0, 60),
			Size = UDim2.new(1, -140, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Left,
		}) :: TextLabel
		; (blurb :: any).TextTruncate = Enum.TextTruncate.AtEnd
		local costLabel = Theme.make("TextLabel", {
			Parent = card,
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Bold,
			Text = if owned then "OWNED" else tostring(cost) .. " P",
			TextColor3 = if owned then Theme.Colors.Green else Theme.Colors.Gold,
			TextSize = Theme.Sizes.Body,
			Position = UDim2.new(0, 8, 0, 82),
			Size = UDim2.new(0, 150, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
		}) :: TextLabel
		if not owned then
			local buy = bigButton(card, "BUY", UDim2.new(1, -118, 0, 62), UDim2.new(0, 110, 0, 48), Theme.Colors.Gold)
			local rid = rodId
			buy.Activated:Connect(function()
				_pendingRod = rid
				if _confirm and _confirmLabel then
					_confirmLabel.Text = string.format("Buy %s for %d P?", Prices.RodName(rid), cost)
					_confirm.Visible = true
				end
			end)
		end
		ry += 126
	end
end

local function setTab(sell: boolean)
	if not _sellTab or not _rodsTab or not _sellBtn or not _rodsBtn then
		return
	end
	_sellTab.Visible = sell
	_rodsTab.Visible = not sell
	_sellBtn.BackgroundColor3 = if sell then Theme.Colors.Teal else Theme.Colors.Panel
	_rodsBtn.BackgroundColor3 = if sell then Theme.Colors.Panel else Theme.Colors.Teal
end

function ShopView.IsOpen(): boolean
	return _frame ~= nil and _frame.Visible == true
end

function ShopView.Open()
	if _frame then
		_frame.Visible = true
		setTab(true)
		render()
	end
end

function ShopView.Close()
	_pendingRod = nil
	if _confirm then
		_confirm.Visible = false
	end
	if _frame then
		_frame.Visible = false
	end
	local PromptController = require(UI:WaitForChild("PromptController"))
	PromptController.NotifyShopClosed()
end

function ShopView.Mount(parent: PlayerGui)
	if _gui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "AbyssalShop"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 25 -- above reel, below catch card
	gui.Parent = parent
	_gui = gui

	local frame = Theme.make("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 560, 0, 480),
		Visible = false,
	}) :: Frame
	Theme.panel(frame, true)
	_frame = frame
	local title = Theme.make("TextLabel", {
		Parent = frame,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Bold,
		Text = "OLD MARROW'S SHOP",
		TextColor3 = Theme.Colors.Gold,
		TextSize = Theme.Sizes.Title,
		Position = UDim2.new(0, 0, 0, 8),
		Size = UDim2.new(1, 0, 0, 36),
	}) :: TextLabel
	Theme.stroke(title, Theme.Colors.Gold)
	_sellBtn = bigButton(frame, "SELL", UDim2.new(0, 12, 0, 50), UDim2.new(0, 200, 0, 48), Theme.Colors.Teal)
	_rodsBtn = bigButton(frame, "RODS", UDim2.new(0, 222, 0, 50), UDim2.new(0, 200, 0, 48), Theme.Colors.Panel)
	; (_rodsBtn :: TextButton).TextColor3 = Theme.Colors.Text
	local closeBtn = bigButton(frame, "X", UDim2.new(1, -60, 0, 50), UDim2.new(0, 48, 0, 48), Theme.Colors.Red)
	; (closeBtn :: TextButton).TextColor3 = Theme.Colors.Text
	_sellBtn.Activated:Connect(function()
		setTab(true)
	end)
	_rodsBtn.Activated:Connect(function()
		setTab(false)
	end)
	closeBtn.Activated:Connect(function()
		ShopView.Close()
	end)
	_sellTab = Theme.make("Frame", {
		Parent = frame,
		Name = "SellTab",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 108),
		Size = UDim2.new(1, -24, 1, -118),
	}) :: Frame
	_rodsTab = Theme.make("Frame", {
		Parent = frame,
		Name = "RodsTab",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 108),
		Size = UDim2.new(1, -24, 1, -118),
		Visible = false,
	}) :: Frame

	-- Confirm-buy dialog.
	_confirm = Theme.make("Frame", {
		Parent = frame,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 380, 0, 180),
		Visible = false,
	}) :: Frame
	Theme.panel(_confirm, true)
	_confirmLabel = Theme.make("TextLabel", {
		Parent = _confirm,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Bold,
		Text = "",
		TextColor3 = Theme.Colors.Text,
		TextSize = 20,
		TextWrapped = true,
		Position = UDim2.new(0, 10, 0, 12),
		Size = UDim2.new(1, -20, 0, 70),
	}) :: TextLabel
	local yesBtn = bigButton(_confirm, "CONFIRM", UDim2.new(0, 16, 0, 96), UDim2.new(0, 160, 0, 56), Theme.Colors.Gold)
	local noBtn = bigButton(_confirm, "CANCEL", UDim2.new(1, -176, 0, 96), UDim2.new(0, 160, 0, 56), Theme.Colors.Panel)
	; (noBtn :: TextButton).TextColor3 = Theme.Colors.Text
	yesBtn.Activated:Connect(function()
		if _pendingRod then
			InputController.BuyRod(_pendingRod)
		end
		_pendingRod = nil
		if _confirm then
			_confirm.Visible = false
		end
	end)
	noBtn.Activated:Connect(function()
		_pendingRod = nil
		if _confirm then
			_confirm.Visible = false
		end
	end)

	if not _bound then
		_bound = true
		-- ShopState opens the shop (server answers ShopInteract with a
		-- snapshot) and re-renders it on every update while open.
		trackUnsub(NetListener.On(Remotes.ShopState, function(payload: any)
			_snapshot = payload
			ShopView.Open()
			render()
			local PromptController = require(UI:WaitForChild("PromptController"))
			PromptController.NotifyShopOpened()
		end))
		trackUnsub(NetListener.On(Remotes.EconomyChanged, function(payload: any)
			-- Keep the header totals fresh while the shop is open.
			if ShopView.IsOpen() and typeof(payload) == "table" and _snapshot ~= nil then
				if typeof((payload :: any).pearls) == "number" then
					_snapshot.pearls = (payload :: any).pearls
				end
				if typeof((payload :: any).bucket) == "table" then
					_snapshot.bucket = (payload :: any).bucket
				end
				if typeof((payload :: any).bucketValue) == "number" then
					_snapshot.bucketValue = (payload :: any).bucketValue
				end
				render()
			end
		end))
		trackUnsub(NetListener.On(Remotes.RodChanged, function(payload: any)
			if typeof(payload) == "table" and typeof((payload :: any).rodId) == "string" then
				_equippedRod = (payload :: any).rodId
				if ShopView.IsOpen() then
					render()
				end
			end
		end))
		-- Esc / E closes (Pass so E still reaches InputController).
		ContextActionService:BindAction("AbyssalShopClose", function(_, state: EnumItem)
			if state == Enum.UserInputState.Begin and ShopView.IsOpen() then
				if _confirm and _confirm.Visible then
					_pendingRod = nil
					_confirm.Visible = false
				else
					ShopView.Close()
				end
			end
			return Enum.ContextActionResult.Pass
		end, false, Enum.KeyCode.Escape, Enum.KeyCode.E)
	end
	setTab(true)
end

function ShopView.Unmount()
	for _, unsub in _unsubs do
		pcall(unsub)
	end
	_unsubs = {}
	_bound = false
	pcall(function()
		ContextActionService:UnbindAction("AbyssalShopClose")
	end)
	_snapshot = nil
	_pendingRod = nil
	_equippedRod = nil
	_frame = nil
	_sellTab = nil
	_rodsTab = nil
	_sellBtn = nil
	_rodsBtn = nil
	_confirm = nil
	_confirmLabel = nil
	if _gui then
		pcall(function()
			(_gui :: ScreenGui):Destroy()
		end)
		_gui = nil
	end
end

return ShopView
