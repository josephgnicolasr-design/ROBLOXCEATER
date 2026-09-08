--!strict
-- Abyssal — Hud (client).
-- Always-on HUD per GDD §8: pearls count (+fly-up on sale), rod chip, Bucket
-- 12-slot mini-strip, depth meter, flavor oxygen bar, prompt-pill anchor,
-- fail toasts, spawn control-hint card, sprint hint, touch bucket toggle.
-- Binds via NetListener.On only. Never bare text on water: every label sits
-- on a Theme.panel or carries Theme.stroke.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientFolder = script.Parent.Parent
local UI = script.Parent
local Theme = require(UI:WaitForChild("Config"):WaitForChild("Theme"))
local Prices = require(UI:WaitForChild("Config"):WaitForChild("Prices"))
local NetListener = require(ClientFolder:WaitForChild("NetListener"))
local SwimController = require(ClientFolder:WaitForChild("SwimController"))

local Shared = ReplicatedStorage:WaitForChild("AbyssalShared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Hud = {}

local _gui: ScreenGui? = nil
local _conns: { RBXScriptConnection } = {}
local _unsubs: { () -> () } = {}

local _pearls = 0
local _rodId = "Twig"
local _bucket: { [string]: number } = {}

local _pearlsLabel: TextLabel? = nil
local _pearlsPanel: Frame? = nil
local _rodLabel: TextLabel? = nil
local _slots: { TextLabel } = {}
local _stripCount: TextLabel? = nil
local _depthLabel: TextLabel? = nil
local _oxyFill: Frame? = nil
local _oxyLabel: TextLabel? = nil
local _pill: Frame? = nil
local _pillLabel: TextLabel? = nil
local _toast: Frame? = nil
local _toastLabel: TextLabel? = nil
local _toastGen = 0
local _hintCard: Frame? = nil
local _pollAcc = 0

local function trackConn(c: RBXScriptConnection)
    table.insert(_conns, c)
end

local function trackUnsub(f: () -> ())
    table.insert(_unsubs, f)
end

-- Floating "+N" over the pearls panel; gold number with stroke+glow.
local function flyUp(amount: number)
    local panel = _pearlsPanel
    local label = _pearlsLabel
    if not panel or not label then
        return
    end
    local f = Theme.make("TextLabel", {
        BackgroundTransparency = 1,
        Font = Theme.Fonts.Bold,
        Text = "+" .. tostring(amount),
        TextColor3 = Theme.Colors.Gold,
        TextSize = Theme.Sizes.Number,
        Size = UDim2.new(1, 0, 0, 30),
        Position = UDim2.new(0, 0, 0, -6),
        ZIndex = 12,
    }) :: TextLabel
    Theme.stroke(f, Theme.Colors.Gold)
    f.Parent = panel
    local tween = TweenService:Create(f, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new(0, 0, 0, -52),
        TextTransparency = 1,
    })
    tween:Play()
    task.delay(1, function()
        pcall(function()
            f:Destroy()
        end)
    end)
end

local function refreshPearls()
    if _pearlsLabel then
        _pearlsLabel.Text = tostring(_pearls) .. " P"
    end
end

local function refreshRod()
    if _rodLabel then
        _rodLabel.Text = "🪝 " .. Prices.RodName(_rodId)
    end
end

-- Mini-strip: 12 slots in SpeciesOrder, filled slots get the species color.
local function refreshStrip()
    local flat: { string } = {}
    if typeof(_bucket) == "table" then
        for _, species in Prices.SpeciesOrder do
            local n = _bucket[species]
            if typeof(n) == "number" then
                for _ = 1, math.min(n, 99) do
                    table.insert(flat, species)
                end
            end
        end
    end
    local total = #flat
    for idx, slot in _slots do
        local species = flat[idx]
        if species then
            local row = Prices.Species[species]
            slot.Text = row.Initial
            slot.TextColor3 = Theme.Colors.Text
            slot.BackgroundColor3 = row.Color
            slot.BackgroundTransparency = 0.25
        else
            slot.Text = "·"
            slot.TextColor3 = Theme.Colors.Dim
            slot.BackgroundColor3 = Theme.Colors.Panel
            slot.BackgroundTransparency = 0.55
        end
    end
    if _stripCount then
        _stripCount.Text = tostring(math.min(total, Prices.BucketCap)) .. "/" .. tostring(Prices.BucketCap)
        if total >= Prices.BucketCap then
            _stripCount.TextColor3 = Theme.Colors.Red
        else
            _stripCount.TextColor3 = Theme.Colors.Dim
        end
    end
end

local function showToast(text: string, color: Color3?)
    _toastGen += 1
    local gen = _toastGen
    local box = _toast
    local label = _toastLabel
    if not box or not label then
        return
    end
    label.Text = text
    label.TextColor3 = color or Theme.Colors.Text
    box.Visible = true
    task.delay(2.5, function()
        if gen == _toastGen and box then
            box.Visible = false
        end
    end)
end

-- Prompt pill (owned by Hud, driven by PromptController — exactly one prompt).
function Hud.SetPrompt(text: string, accent: Color3?)
    local pill = _pill
    local label = _pillLabel
    if not pill or not label then
        return
    end
    label.Text = text
    if accent then
        label.TextColor3 = accent
    else
        label.TextColor3 = Theme.Colors.Text
    end
    pill.Visible = true
end

function Hud.ClearPrompt()
    if _pill then
        _pill.Visible = false
    end
end

function Hud.Toast(text: string, color: Color3?)
    showToast(text, color)
end

function Hud.Mount(parent: PlayerGui)
    if _gui then
        return
    end
    local gui = Instance.new("ScreenGui")
    gui.Name = "AbyssalHud"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 10
    gui.Parent = parent
    _gui = gui

    -- Top-left: pearls panel.
    local pearlsPanel = Theme.make("Frame", {
        Parent = gui,
        AnchorPoint = Vector2.new(0, 0),
        Position = UDim2.new(0, 16, 0, 16),
        Size = UDim2.new(0, 190, 0, 56),
    }) :: Frame
    Theme.panel(pearlsPanel, true)
    _pearlsPanel = pearlsPanel
    _pearlsLabel = Theme.make("TextLabel", {
        Parent = pearlsPanel,
        BackgroundTransparency = 1,
        Font = Theme.Fonts.Bold,
        Text = "0 P",
        TextColor3 = Theme.Colors.Gold,
        TextSize = 26,
        Size = UDim2.new(1, -12, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
    }) :: TextLabel
    Theme.stroke(_pearlsLabel, Theme.Colors.Gold)

    -- Top-right: rod chip.
    local rodChip = Theme.make("Frame", {
        Parent = gui,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -16, 0, 16),
        Size = UDim2.new(0, 200, 0, 56),
    }) :: Frame
    Theme.panel(rodChip, true)
    _rodLabel = Theme.make("TextLabel", {
        Parent = rodChip,
        BackgroundTransparency = 1,
        Font = Theme.Fonts.Bold,
        Text = "🪝 Twig Rod",
        TextColor3 = Theme.Colors.Text,
        TextSize = Theme.Sizes.Body,
        Size = UDim2.new(1, -12, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
    }) :: TextLabel
    Theme.stroke(_rodLabel)

    -- Top-center: depth meter.
    local depthPanel = Theme.make("Frame", {
        Parent = gui,
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 16),
        Size = UDim2.new(0, 150, 0, 44),
    }) :: Frame
    Theme.panel(depthPanel, false)
    _depthLabel = Theme.make("TextLabel", {
        Parent = depthPanel,
        BackgroundTransparency = 1,
        Font = Theme.Fonts.Bold,
        Text = "0m",
        TextColor3 = Theme.Colors.Cyan,
        TextSize = Theme.Sizes.Number,
        Size = UDim2.new(1, 0, 1, 0),
    }) :: TextLabel
    Theme.stroke(_depthLabel, Theme.Colors.Cyan)

    -- Bottom-left: bucket strip + oxygen in one panel.
    local leftPanel = Theme.make("Frame", {
        Parent = gui,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 16, 1, -16),
        Size = UDim2.new(0, 420, 0, 118),
    }) :: Frame
    Theme.panel(leftPanel, true)
    local strip = Theme.make("Frame", {
        Parent = leftPanel,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, 8),
        Size = UDim2.new(1, -20, 0, 34),
    }) :: Frame
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.Padding = UDim.new(0, 4)
    layout.Parent = strip
    _slots = {}
    for _ = 1, Prices.BucketCap do
        local slot = Theme.make("TextLabel", {
            Parent = strip,
            BackgroundColor3 = Theme.Colors.Panel,
            BorderSizePixel = 0,
            Font = Theme.Fonts.Bold,
            Text = "·",
            TextColor3 = Theme.Colors.Dim,
            TextSize = 16,
            Size = UDim2.new(0, 28, 0, 32),
        }) :: TextLabel
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = slot
        table.insert(_slots, slot)
    end
    _stripCount = Theme.make("TextLabel", {
        Parent = leftPanel,
        BackgroundTransparency = 1,
        Font = Theme.Fonts.Regular,
        Text = "0/12  (hold TAB)",
        TextColor3 = Theme.Colors.Dim,
        TextSize = Theme.Sizes.Small,
        Position = UDim2.new(0, 10, 0, 44),
        Size = UDim2.new(1, -20, 0, 20),
        TextXAlignment = Enum.TextXAlignment.Left,
    }) :: TextLabel
    -- Oxygen bar.
    local oxyBack = Theme.make("Frame", {
        Parent = leftPanel,
        BackgroundColor3 = Theme.Colors.Ink,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 10, 0, 68),
        Size = UDim2.new(1, -20, 0, 16),
    }) :: Frame
    local oc = Instance.new("UICorner")
    oc.CornerRadius = UDim.new(0, 8)
    oc.Parent = oxyBack
    _oxyFill = Theme.make("Frame", {
        Parent = oxyBack,
        BackgroundColor3 = Theme.Colors.Cyan,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
    }) :: Frame
    local oc2 = Instance.new("UICorner")
    oc2.CornerRadius = UDim.new(0, 8)
    oc2.Parent = _oxyFill
    _oxyLabel = Theme.make("TextLabel", {
        Parent = leftPanel,
        BackgroundTransparency = 1,
        Font = Theme.Fonts.Regular,
        Text = "OXYGEN",
        TextColor3 = Theme.Colors.Dim,
        TextSize = 14,
        Position = UDim2.new(0, 10, 0, 88),
        Size = UDim2.new(1, -20, 0, 18),
        TextXAlignment = Enum.TextXAlignment.Left,
    }) :: TextLabel

    -- Bottom-center: context prompt pill (PromptController drives text).
    _pill = Theme.make("Frame", {
        Parent = gui,
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -150),
        Size = UDim2.new(0, 380, 0, 52),
        Visible = false,
    }) :: Frame
    Theme.panel(_pill, true)
    _pillLabel = Theme.make("TextLabel", {
        Parent = _pill,
        BackgroundTransparency = 1,
        Font = Theme.Fonts.Bold,
        Text = "",
        TextColor3 = Theme.Colors.Text,
        TextSize = 20,
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
    }) :: TextLabel
    Theme.stroke(_pillLabel)

    -- Fail toast above the pill.
    _toast = Theme.make("Frame", {
        Parent = gui,
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -215),
        Size = UDim2.new(0, 420, 0, 48),
        Visible = false,
    }) :: Frame
    Theme.panel(_toast, false)
    _toastLabel = Theme.make("TextLabel", {
        Parent = _toast,
        BackgroundTransparency = 1,
        Font = Theme.Fonts.Regular,
        Text = "",
        TextColor3 = Theme.Colors.Text,
        TextSize = Theme.Sizes.Body,
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
    }) :: TextLabel

    -- Bottom-right: sprint hint.
    local sprint = Theme.make("TextLabel", {
        Parent = gui,
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -16, 1, -16),
        Size = UDim2.new(0, 220, 0, 30),
        BackgroundTransparency = 1,
        Font = Theme.Fonts.Regular,
        Text = "Shift = sprint · R = cancel line",
        TextColor3 = Theme.Colors.Dim,
        TextSize = Theme.Sizes.Small,
        TextXAlignment = Enum.TextXAlignment.Right,
    }) :: TextLabel
    Theme.stroke(sprint)

    -- Spawn control-hint card (dismissible, auto-hides after 8 s per GDD §8).
    local hint = Theme.make("Frame", {
        Parent = gui,
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 72),
        Size = UDim2.new(0, 460, 0, 96),
    }) :: Frame
    Theme.panel(hint, true)
    _hintCard = hint
    local hintText = Theme.make("TextLabel", {
        Parent = hint,
        BackgroundTransparency = 1,
        Font = Theme.Fonts.Regular,
        Text = "Swim with WASD + Space/C · E = cast / hook · Hold LMB to reel · Sell fish at Old Marrow (click to dismiss)",
        TextColor3 = Theme.Colors.Text,
        TextSize = Theme.Sizes.Body,
        TextWrapped = true,
        Size = UDim2.new(1, -20, 1, -10),
        Position = UDim2.new(0, 10, 0, 5),
    }) :: TextLabel
    Theme.stroke(hintText)
    local hintBtn = Theme.make("TextButton", {
        Parent = hint,
        BackgroundTransparency = 1,
        Text = "",
        Size = UDim2.new(1, 0, 1, 0),
    }) :: TextButton
    hintBtn.Activated:Connect(function()
        if _hintCard then
            _hintCard.Visible = false
        end
    end)
    task.delay(8, function()
        if _hintCard then
            _hintCard.Visible = false
        end
    end)

    -- Server-state bindings (NetListener only — no direct RemoteEvent access).
    trackUnsub(NetListener.On(Remotes.EconomyChanged, function(payload: any)
        if typeof(payload) ~= "table" then
            return
        end
        local newPearls = (payload :: any).pearls
        if typeof(newPearls) == "number" then
            if newPearls > _pearls then
                flyUp(newPearls - _pearls)
            end
            _pearls = newPearls
            refreshPearls()
        end
        local bucket = (payload :: any).bucket
        if typeof(bucket) == "table" then
            _bucket = bucket
            refreshStrip()
        end
    end))
    trackUnsub(NetListener.On(Remotes.RodChanged, function(payload: any)
        if typeof(payload) == "table" and typeof((payload :: any).rodId) == "string" then
            _rodId = (payload :: any).rodId
            refreshRod()
        end
    end))
    trackUnsub(NetListener.On(Remotes.LineFailed, function(payload: any)
        local msg = "It slipped away…"
        if typeof(payload) == "table" and typeof((payload :: any).message) == "string" then
            msg = (payload :: any).message
        end
        showToast(msg, Theme.Colors.Red)
    end))
    -- SpotPrompt is consumed by PromptController; Hud ignores it.

    refreshPearls()
    refreshRod()
    refreshStrip()

    -- 10 Hz poll: oxygen bar + depth meter from the local character.
    trackConn(RunService.RenderStepped:Connect(function(dt: number)
        _pollAcc += dt
        if _pollAcc < 0.1 then
            return
        end
        _pollAcc = 0
        pcall(function()
            local player = Players.LocalPlayer
            local char = player and player.Character
            local rootPart = char and (char :: any):FindFirstChild("HumanoidRootPart")
            local y = 0
            if rootPart and (rootPart :: Instance):IsA("BasePart") then
                y = ((rootPart :: any) :: BasePart).Position.Y
            end
            local depth = math.max(0, Config.Oxygen.SurfaceY - y)
            if _depthLabel then
                _depthLabel.Text = tostring(math.floor(depth + 0.5)) .. "m"
            end
            local frac = SwimController.OxygenFraction()
            if _oxyFill then
                _oxyFill.Size = UDim2.new(math.clamp(frac, 0, 1), 0, 1, 0)
                if frac <= 0 then
                    _oxyFill.BackgroundColor3 = Theme.Colors.Red;
                else
                    _oxyFill.BackgroundColor3 = Theme.Colors.Cyan
                end
            end
            if _oxyLabel then
                if frac <= 0 then
                    _oxyLabel.Text = "OXYGEN EMPTY — swim slowed 20%"
                else
                    _oxyLabel.Text = "OXYGEN"
                end
            end
        end)
    end))
end

function Hud.Unmount()
    for _, unsub in _unsubs do
        pcall(unsub)
    end
    _unsubs = {}
    for _, c in _conns do
        pcall(function()
            c:Disconnect()
        end)
    end
    _conns = {}
    _slots = {}
    _pearlsLabel = nil
    _pearlsPanel = nil
    _rodLabel = nil
    _stripCount = nil
    _depthLabel = nil
    _oxyFill = nil
    _oxyLabel = nil
    _pill = nil
    _pillLabel = nil
    _toast = nil
    _toastLabel = nil
    _hintCard = nil
    if _gui then
        pcall(function()
            (_gui :: ScreenGui):Destroy()
        end)
        _gui = nil
    end
end

return Hud
