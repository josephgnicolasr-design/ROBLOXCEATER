--!strict
-- Abyssal — BiteReel (client).
-- Bite "!" ring (1.2 s window per GDD §5/§8: the 96px red pop) + reel track
-- (progress / tension / catcher / marker / surge warning) per GDD §8.
-- The 10 Hz ReelState stream is interpolated with RenderStepped lerp so the
-- reel stays readable under motion. Sends HookAttempt / ReelInput{holding} /
-- CancelLine intent. Bindings (E/R/LMB/Space) live in InputController; this
-- view also exposes pointer/touch hooks (press-and-hold the HOLD zone).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientFolder = script.Parent.Parent
local UI = script.Parent
local NetListener = require(ClientFolder:WaitForChild("NetListener"))
local InputController = require(ClientFolder:WaitForChild("InputController"))
local Theme = require(UI:WaitForChild("Config"):WaitForChild("Theme"))

local Shared = ReplicatedStorage:WaitForChild("AbyssalShared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local BiteReel = {}

local _gui: ScreenGui? = nil
local _conns: { RBXScriptConnection } = {}
local _unsubs: { () -> () } = {}

-- Displayed (interpolated) vs target (latest server snapshot) reel state.
local _disp = { progress = 0, tension = 0, catcher = 0.5, marker = 0.5 }
local _target = { progress = 0, tension = 0, catcher = 0.5, marker = 0.5 }
local _surge = false
local _reeling = false

local _biteFrame: Frame? = nil
local _biteMark: TextLabel? = nil
local _biteRing: Frame? = nil
local _biteDeadline = 0

local _reelFrame: Frame? = nil
local _track: Frame? = nil
local _catcherBar: Frame? = nil
local _marker: Frame? = nil
local _progressFill: Frame? = nil
local _progressLabel: TextLabel? = nil
local _tensionFill: Frame? = nil
local _surgeLabel: TextLabel? = nil
local _holdBtn: TextButton? = nil

local function trackConn(c: RBXScriptConnection)
    table.insert(_conns, c)
end

local function trackUnsub(f: () -> ())
    table.insert(_unsubs, f)
end

local function showBite(expiresIn: number)
    local frame = _biteFrame
    local ring = _biteRing
    local mark = _biteMark
    if not frame then
        return
    end
    frame.Visible = true
    _biteDeadline = os.clock() + math.max(0.2, expiresIn)
    if ring then
        ring.Size = UDim2.new(0, 220, 0, 220)
    end
    if mark then
        mark.TextSize = Theme.Sizes.Bite
        mark.Visible = true
    end
end

local function hideBite()
    if _biteFrame then
        _biteFrame.Visible = false
    end
end

local function showReel()
    _target = { progress = 0, tension = 0, catcher = 0.5, marker = 0.5 }
    _disp = { progress = 0, tension = 0, catcher = 0.5, marker = 0.5 }
    _surge = false
    if _reelFrame then
        _reelFrame.Visible = true
    end
end

local function hideReel()
    if _reelFrame then
        _reelFrame.Visible = false
    end
    if InputController then
        pcall(function()
            InputController.SetReeling(false)
        end)
    end
end

function BiteReel.Mount(parent: PlayerGui)
    if _gui then
        return
    end
    local gui = Instance.new("ScreenGui")
    gui.Name = "AbyssalBiteReel"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 20 -- above HUD, below catch card
    gui.Parent = parent
    _gui = gui

    -- Center bite overlay: giant red "!" on a dark disc + shrinking ring.
    local bite = Theme.make("Frame", {
        Parent = gui,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.38, 0),
        Size = UDim2.new(0, 260, 0, 260),
        BackgroundTransparency = 1,
        Visible = false,
    }) :: Frame
    _biteFrame = bite
    local disc = Theme.make("Frame", {
        Parent = bite,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 150, 0, 150),
    }) :: Frame
    Theme.panel(disc, true)
    local dc = disc:FindFirstChildOfClass("UICorner")
    if dc then
        (dc :: UICorner).CornerRadius = UDim.new(1, 0)
    end
    _biteMark = Theme.make("TextLabel", {
        Parent = disc,
        BackgroundTransparency = 1,
        Font = Theme.Fonts.Bold,
        Text = "!",
        TextColor3 = Theme.Colors.Red,
        TextSize = Theme.Sizes.Bite,
        Size = UDim2.new(1, 0, 1, 0),
    }) :: TextLabel
    Theme.stroke(_biteMark, Theme.Colors.Red)
    _biteRing = Theme.make("Frame", {
        Parent = bite,
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 220, 0, 220),
    }) :: Frame
    local ringStroke = Instance.new("UIStroke")
    ringStroke.Color = Theme.Colors.Red
    ringStroke.Thickness = 6
    ringStroke.Parent = _biteRing
    local ringCorner = Instance.new("UICorner")
    ringCorner.CornerRadius = UDim.new(1, 0)
    ringCorner.Parent = _biteRing

    -- Reel overlay: vertical track panel.
    local reel = Theme.make("Frame", {
        Parent = gui,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 420, 0, 390),
        Visible = false,
    }) :: Frame
    Theme.panel(reel, true)
    _reelFrame = reel
    _progressLabel = Theme.make("TextLabel", {
        Parent = reel,
        BackgroundTransparency = 1,
        Font = Theme.Fonts.Bold,
        Text = "0%",
        TextColor3 = Theme.Colors.Cyan,
        TextSize = Theme.Sizes.Number,
        Position = UDim2.new(0, 0, 0, 6),
        Size = UDim2.new(1, 0, 0, 32),
    }) :: TextLabel
    Theme.stroke(_progressLabel, Theme.Colors.Cyan)
    -- Progress bar.
    local pBack = Theme.make("Frame", {
        Parent = reel,
        BackgroundColor3 = Theme.Colors.Ink,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 20, 0, 42),
        Size = UDim2.new(1, -40, 0, 18),
    }) :: Frame
    _progressFill = Theme.make("Frame", {
        Parent = pBack,
        BackgroundColor3 = Theme.Colors.Green,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 0, 1, 0),
    }) :: Frame
    -- Main track (catcher + marker live on 0..1).
    _track = Theme.make("Frame", {
        Parent = reel,
        BackgroundColor3 = Theme.Colors.Ink,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 60, 0, 74),
        Size = UDim2.new(1, -120, 0, 180),
    }) :: Frame
    _catcherBar = Theme.make("Frame", {
        Parent = _track,
        BackgroundColor3 = Theme.Colors.Teal,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0.36, 0, 0.24, 0),
    }) :: Frame
    _marker = Theme.make("Frame", {
        Parent = _track,
        BackgroundColor3 = Theme.Colors.Gold,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0.10, 0, 0.12, 0),
    }) :: Frame
    -- Tension bar (right of track).
    local tBack = Theme.make("Frame", {
        Parent = reel,
        BackgroundColor3 = Theme.Colors.Ink,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -52, 0, 74),
        Size = UDim2.new(0, 22, 0, 180),
    }) :: Frame
    _tensionFill = Theme.make("Frame", {
        Parent = tBack,
        BackgroundColor3 = Theme.Colors.Green,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 0),
    }) :: Frame
    _surgeLabel = Theme.make("TextLabel", {
        Parent = reel,
        BackgroundTransparency = 1,
        Font = Theme.Fonts.Bold,
        Text = "SURGE — RELEASE!",
        TextColor3 = Theme.Colors.Red,
        TextSize = Theme.Sizes.Number,
        Position = UDim2.new(0, 0, 0, 258),
        Size = UDim2.new(1, 0, 0, 30),
        Visible = false,
    }) :: TextLabel
    Theme.stroke(_surgeLabel, Theme.Colors.Red)
    -- HOLD zone (>=44px) for touch/mouse hold-to-reel.
    _holdBtn = Theme.make("TextButton", {
        Parent = reel,
        BackgroundColor3 = Theme.Colors.Teal,
        Font = Theme.Fonts.Bold,
        Text = "HOLD TO REEL",
        TextColor3 = Theme.Colors.Ink,
        TextSize = Theme.Sizes.Body,
        Position = UDim2.new(0, 20, 0, 296),
        Size = UDim2.new(1, -40, 0, 60),
        AutoButtonColor = true,
    }) :: TextButton
    local hc = Instance.new("UICorner")
    hc.CornerRadius = UDim.new(0, 10)
    hc.Parent = _holdBtn
    _holdBtn.MouseButton1Down:Connect(function()
        InputController.SetReeling(true)
    end)
    _holdBtn.MouseButton1Up:Connect(function()
        InputController.SetReeling(false)
    end)
    _holdBtn.TouchLongPress:Connect(function()
        InputController.SetReeling(true)
    end)
    -- Touch release (InputEnded fires for touch too); mouse release is also
    -- covered by InputController's global LMB watcher. Belt and suspenders.
    trackConn(_holdBtn.InputEnded:Connect(function(input: InputObject)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            InputController.SetReeling(false)
        end
    end))
    trackConn(_holdBtn.MouseLeave:Connect(function()
        -- Keep it simple: releasing the button later still ends the hold via
        -- InputController's global LMB watcher.
    end))

    -- Interpolated render: lerp displayed -> target at ~12/s; countdown ring.
    trackConn(RunService.RenderStepped:Connect(function(dt: number)
        pcall(function()
            if _biteFrame and _biteFrame.Visible then
                local remain = _biteDeadline - os.clock()
                local total = math.max(0.2, Config.Fishing.HookWindow)
                local frac = math.clamp(remain / total, 0, 1)
                if _biteRing then
                    local d = 140 + 120 * frac
                    _biteRing.Size = UDim2.new(0, d, 0, d)
                end
                if remain <= 0 then
                    hideBite()
                end
            end
            if _reelFrame and _reelFrame.Visible then
                local k = math.clamp(dt * 12, 0, 1)
                _disp.progress += (_target.progress - _disp.progress) * k
                _disp.tension += (_target.tension - _disp.tension) * k
                _disp.catcher += (_target.catcher - _disp.catcher) * k
                _disp.marker += (_target.marker - _disp.marker) * k
                if _progressFill then
                    _progressFill.Size = UDim2.new(math.clamp(_disp.progress / 100, 0, 1), 0, 1, 0)
                end
                if _progressLabel then
                    _progressLabel.Text = tostring(math.floor(_disp.progress + 0.5)) .. "%"
                end
                if _tensionFill then
                    _tensionFill.Size = UDim2.new(1, 0, math.clamp(_disp.tension / 100, 0, 1), 0)
                    if _disp.tension >= 70 or _surge then
                        _tensionFill.BackgroundColor3 = Theme.Colors.Red
                    else
                        _tensionFill.BackgroundColor3 = Theme.Colors.Green
                    end
                end
                if _catcherBar then
                    _catcherBar.Position = UDim2.new(0.5, 0, math.clamp(1 - _disp.catcher, 0, 1), 0)
                end
                if _marker then
                    _marker.Position = UDim2.new(0.5, 0, math.clamp(1 - _disp.marker, 0, 1), 0)
                    if _surge then
                        _marker.BackgroundColor3 = Theme.Colors.Red
                    else
                        _marker.BackgroundColor3 = Theme.Colors.Gold
                    end
                end
                if _surgeLabel then
                    -- Flash at ~6 Hz for readability under motion.
                    _surgeLabel.Visible = _surge and (math.floor(os.clock() * 6) % 2 == 0)
                end
            elseif _surgeLabel then
                _surgeLabel.Visible = false
            end
        end)
    end))

    -- Listener bindings (NetListener only).
    trackUnsub(NetListener.On(Remotes.CastStarted, function()
        hideBite()
    end))
    trackUnsub(NetListener.On(Remotes.BitePrompt, function(payload: any)
        local expiresIn = Config.Fishing.HookWindow
        if typeof(payload) == "table" and typeof((payload :: any).expiresIn) == "number" then
            expiresIn = (payload :: any).expiresIn
        end
        showBite(expiresIn)
    end))
    trackUnsub(NetListener.On(Remotes.ReelState, function(payload: any)
        if typeof(payload) ~= "table" then
            return
        end
        if _reelFrame and not _reelFrame.Visible then
            showReel()
        end
        hideBite() -- fight started; hook window is over
        local p = payload :: any
        if typeof(p.progress) == "number" then
            _target.progress = math.clamp(p.progress, 0, 100)
        end
        if typeof(p.tension) == "number" then
            _target.tension = math.clamp(p.tension, 0, 100)
        end
        if typeof(p.catcher) == "number" then
            _target.catcher = math.clamp(p.catcher, 0, 1)
        end
        if typeof(p.marker) == "number" then
            _target.marker = math.clamp(p.marker, 0, 1)
        end
        _surge = p.surge == true
    end))
    trackUnsub(NetListener.On(Remotes.CatchResult, function()
        hideBite()
        hideReel()
        _reeling = false
    end))
    trackUnsub(NetListener.On(Remotes.LineFailed, function()
        hideBite()
        hideReel()
        _reeling = false
    end))
end

function BiteReel.Unmount()
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
    _biteFrame = nil
    _biteMark = nil
    _biteRing = nil
    _reelFrame = nil
    _track = nil
    _catcherBar = nil
    _marker = nil
    _progressFill = nil
    _progressLabel = nil
    _tensionFill = nil
    _surgeLabel = nil
    _holdBtn = nil
    if _gui then
        pcall(function()
            (_gui :: ScreenGui):Destroy()
        end)
        _gui = nil
    end
end

return BiteReel
