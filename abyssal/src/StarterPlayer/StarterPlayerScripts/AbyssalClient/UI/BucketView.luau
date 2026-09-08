--!strict
-- Abyssal — BucketView (client).
-- Hold-Tab right panel per GDD §8: 12 slots with species icons + counts,
-- total sale value preview (client Prices table mirroring GDD §6: 10/30/80),
-- "Bucket full — visit Old Marrow" state. Binds via NetListener.On
-- (EconomyChanged) only.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientFolder = script.Parent.Parent
local UI = script.Parent
local NetListener = require(ClientFolder:WaitForChild("NetListener"))
local Theme = require(UI:WaitForChild("Config"):WaitForChild("Theme"))
local Prices = require(UI:WaitForChild("Config"):WaitForChild("Prices"))
local Remotes = (require(ReplicatedStorage:WaitForChild("AbyssalShared"):WaitForChild("Remotes")) :: any)

local BucketView = {}

local _gui: ScreenGui? = nil
local _unsubs: { () -> () } = {}
local _panel: Frame? = nil
local _slots: { Frame } = {}
local _totalLabel: TextLabel? = nil
local _fullLabel: TextLabel? = nil
local _bucket: { [string]: number } = {}
local _held = false

local function trackUnsub(f: () -> ())
    table.insert(_unsubs, f)
end

local function countTotal(): number
    local n = 0
    for _, species in Prices.SpeciesOrder do
        local c = _bucket[species]
        if typeof(c) == "number" then
            n += c
        end
    end
    return n
end

local function refresh()
    if not _panel then
        return
    end
    local total = countTotal()
    for _, slot in _slots do
        slot:Destroy()
    end
    _slots = {}
    local order: { string } = {}
    for _, species in Prices.SpeciesOrder do
        local c = _bucket[species]
        if typeof(c) == "number" then
            for _ = 1, c do
                table.insert(order, species)
            end
        end
    end
    local grid = _panel:FindFirstChild("Grid")
    for i = 1, Prices.BucketCap do
        local species = order[i]
        local slot = Theme.make("Frame", {
            Parent = grid,
            BackgroundColor3 = Theme.Colors.Ink,
            BorderSizePixel = 0,
            Size = UDim2.new(0, 60, 0, 60),
        }) :: Frame
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 8)
        c.Parent = slot
        if species then
            local row = Prices.Species[species]
            local icon = Theme.make("TextLabel", {
                Parent = slot,
                BackgroundTransparency = 1,
                Font = Theme.Fonts.Bold,
                Text = row.Initial,
                TextColor3 = row.Color,
                TextSize = 30,
                Size = UDim2.new(1, 0, 1, -20),
            }) :: TextLabel
            Theme.stroke(icon)
            local nm = Theme.make("TextLabel", {
                Parent = slot,
                BackgroundTransparency = 1,
                Font = Theme.Fonts.Regular,
                Text = row.Name,
                TextColor3 = Theme.Colors.Dim,
                TextSize = 11,
                Position = UDim2.new(0, 0, 1, -20),
                Size = UDim2.new(1, 0, 0, 18),
            }) :: TextLabel
            (nm :: TextLabel).TextTruncate = Enum.TextTruncate.AtEnd
        else
            local empty = Theme.make("TextLabel", {
                Parent = slot,
                BackgroundTransparency = 1,
                Font = Theme.Fonts.Regular,
                Text = "·",
                TextColor3 = Theme.Colors.Dim,
                TextSize = 28,
                Size = UDim2.new(1, 0, 1, 0),
            }) :: TextLabel
            (empty :: any).Name = "Empty"
        end
        table.insert(_slots, slot)
    end
    if _totalLabel then
        local value = Prices.BucketValue(_bucket)
        _totalLabel.Text = string.format("Bucket %d/%d  ·  ≈%d P", total, Prices.BucketCap, value)
    end
    if _fullLabel then
        _fullLabel.Visible = total >= Prices.BucketCap
    end
end

function BucketView.IsOpen(): boolean
    return _panel ~= nil and _panel.Visible == true
end

function BucketView.Mount(parent: PlayerGui)
    if _gui then
        return
    end
    local gui = Instance.new("ScreenGui")
    gui.Name = "AbyssalBucket"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 15
    gui.Parent = parent
    _gui = gui

    local panel = Theme.make("Frame", {
        Parent = gui,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -16, 0.5, 0),
        Size = UDim2.new(0, 300, 0, 420),
        Visible = false,
    }) :: Frame
    Theme.panel(panel, true)
    _panel = panel
    local title = Theme.make("TextLabel", {
        Parent = panel,
        BackgroundTransparency = 1,
        Font = Theme.Fonts.Bold,
        Text = "BUCKET (hold TAB)",
        TextColor3 = Theme.Colors.Text,
        TextSize = Theme.Sizes.Body,
        Position = UDim2.new(0, 0, 0, 8),
        Size = UDim2.new(1, 0, 0, 28),
    }) :: TextLabel
    Theme.stroke(title)
    local grid = Theme.make("Frame", {
        Parent = panel,
        Name = "Grid",
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 14, 0, 44),
        Size = UDim2.new(1, -28, 0, 248),
    }) :: Frame
    local gl = Instance.new("UIGridLayout")
    gl.CellSize = UDim2.new(0, 60, 0, 60) -- 4 cols x 3 rows = 12, fits the panel
    gl.CellPadding = UDim2.new(0, 8, 0, 8)
    gl.FillDirection = Enum.FillDirection.Horizontal
    gl.HorizontalAlignment = Enum.HorizontalAlignment.Center
    gl.Parent = grid
    _totalLabel = Theme.make("TextLabel", {
        Parent = panel,
        BackgroundTransparency = 1,
        Font = Theme.Fonts.Bold,
        Text = "Bucket 0/12  ·  ≈0 P",
        TextColor3 = Theme.Colors.Gold,
        TextSize = Theme.Sizes.Body,
        Position = UDim2.new(0, 0, 0, 300),
        Size = UDim2.new(1, 0, 0, 30),
    }) :: TextLabel
    Theme.stroke(_totalLabel, Theme.Colors.Gold)
    _fullLabel = Theme.make("TextLabel", {
        Parent = panel,
        BackgroundTransparency = 1,
        Font = Theme.Fonts.Bold,
        Text = "Bucket full — visit Old Marrow!",
        TextColor3 = Theme.Colors.Red,
        TextSize = Theme.Sizes.Body,
        TextWrapped = true,
        Position = UDim2.new(0, 10, 0, 334),
        Size = UDim2.new(1, -20, 0, 56),
        Visible = false,
    }) :: TextLabel
    Theme.stroke(_fullLabel, Theme.Colors.Red)

    -- Hold-Tab: Begin = show, End = hide (Pass so Tab keeps default behavior).
    ContextActionService:BindAction("AbyssalBucket", function(_, state: EnumItem)
        if state == Enum.UserInputState.Begin then
            _held = true
            if _panel then
                _panel.Visible = true
            end
            refresh()
        elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
            _held = false
            if _panel then
                _panel.Visible = false
            end
        end
        return Enum.ContextActionResult.Pass
    end, false, Enum.KeyCode.Tab)

    trackUnsub(NetListener.On(Remotes.EconomyChanged, function(payload: any)
        if typeof(payload) == "table" and typeof((payload :: any).bucket) == "table" then
            _bucket = (payload :: any).bucket
            if _held then
                refresh()
            else
                -- Keep hidden totals fresh for the next open.
                refresh()
                if _panel then
                    _panel.Visible = false
                end
            end
        end
    end))
    refresh()
end

function BucketView.Unmount()
    for _, unsub in _unsubs do
        pcall(unsub)
    end
    _unsubs = {}
    pcall(function()
        ContextActionService:UnbindAction("AbyssalBucket")
    end)
    _slots = {}
    _panel = nil
    _totalLabel = nil
    _fullLabel = nil
    if _gui then
        pcall(function()
            (_gui :: ScreenGui):Destroy()
        end)
        _gui = nil
    end
end

return BucketView
