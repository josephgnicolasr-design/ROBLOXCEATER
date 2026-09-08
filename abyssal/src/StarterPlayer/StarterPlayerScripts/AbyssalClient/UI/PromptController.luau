--!strict
-- Abyssal — PromptController (client).
-- E-priority logic per GDD §5: shop > hook > cast. Exactly one prompt pill is
-- shown at a time (Hud owns the pill; this module owns the decision).
-- Also drives the shop 30 s auto-close fallback and exposes IsShopOpen so
-- UIInit/exploration scripts can query state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientFolder = script.Parent.Parent
local UI = script.Parent
local NetListener = require(ClientFolder:WaitForChild("NetListener"))
local InputController = require(ClientFolder:WaitForChild("InputController"))
local Hud = require(UI:WaitForChild("Hud"))

local Shared = ReplicatedStorage:WaitForChild("AbyssalShared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PromptController = {}

local _unsubs: { () -> () } = {}
local _mounted = false

local _inSpot = false
local _spotId: string? = nil
local _biteActive = false -- hook window open (BitePrompt -> CatchResult/LineFailed)
local _biteGen = 0 -- guards the safety timeout against a second bite
local _shopOpen = false -- ShopState visible since last open
local _shopGen = 0

local function trackUnsub(f: () -> ())
    table.insert(_unsubs, f)
end

local function shopPosition(): Vector3
    local hint = workspace:FindFirstChild("OldMarrowNPCHint") :: Vector3Value?
    if hint then
        return hint.Value
    end
    return Vector3.new(0, -2, 60)
end

local function nearShop(): boolean
    local player = Players.LocalPlayer
    local char = player and player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then
        return InputController.IsNearShop()
    end
    return (root.Position - shopPosition()).Magnitude <= Config.Fishing.ShopPromptDistance
end

-- Priority render: exactly one prompt at a time.
function PromptController.Refresh()
    if not _mounted then
        return
    end
    if nearShop() then
        Hud.SetPrompt("Press E to trade with Old Marrow", (require(UI:WaitForChild("Config"):WaitForChild("Theme")) :: any).Colors.Gold)
        return
    end
    if _biteActive then
        Hud.SetPrompt("Press E — HOOK NOW!", (require(UI:WaitForChild("Config"):WaitForChild("Theme")) :: any).Colors.Red)
        return
    end
    if _inSpot then
        Hud.SetPrompt("Press E to cast", (require(UI:WaitForChild("Config"):WaitForChild("Theme")) :: any).Colors.Teal)
        return
    end
    Hud.ClearPrompt()
end

function PromptController.IsShopOpen(): boolean
    return _shopOpen
end

-- Called by ShopView when the shop opens/closes (starts/cancels the 30 s
-- fallback auto-close so an orphaned shop can never trap the player).
function PromptController.NotifyShopOpened()
    _shopOpen = true
    _shopGen += 1
    local gen = _shopGen
    task.delay(30, function()
        if gen == _shopGen and _shopOpen then
            local ShopView = require(UI:WaitForChild("ShopView"))
            ShopView.Close()
        end
    end)
end

function PromptController.NotifyShopClosed()
    _shopOpen = false
    _shopGen += 1
    PromptController.Refresh()
end

function PromptController.Mount(_parent: PlayerGui)
    if _mounted then
        return
    end
    _mounted = true
    trackUnsub(NetListener.On(Remotes.SpotPrompt, function(payload: any)
        if typeof(payload) == "table" then
            _inSpot = (payload :: any).inSpot == true
            if typeof((payload :: any).spotId) == "string" then
                _spotId = (payload :: any).spotId
            elseif not _inSpot then
                _spotId = nil
            end
        end
        PromptController.Refresh()
    end))
    trackUnsub(NetListener.On(Remotes.BitePrompt, function(_payload: any)
        _biteActive = true
        _biteGen += 1
        local gen = _biteGen
        PromptController.Refresh()
        -- Safety: if no CatchResult/LineFailed arrives, drop hook priority.
        task.delay(Config.Fishing.HookWindow + 1.0, function()
            if gen == _biteGen and _biteActive then
                _biteActive = false
                PromptController.Refresh()
            end
        end)
    end))
    trackUnsub(NetListener.On(Remotes.CatchResult, function()
        _biteActive = false
        _biteGen += 1
        PromptController.Refresh()
    end))
    trackUnsub(NetListener.On(Remotes.LineFailed, function()
        _biteActive = false
        _biteGen += 1
        PromptController.Refresh()
    end))
    trackUnsub(NetListener.On(Remotes.ReelState, function()
        -- Reel started: hook window is over; keep the pill hidden during fight
        -- unless the player is also near the shop (shop wins).
        _biteActive = false
        PromptController.Refresh()
    end))
    PromptController.Refresh()
end

function PromptController.Unmount()
    for _, unsub in _unsubs do
        pcall(unsub)
    end
    _unsubs = {}
    _mounted = false
    _inSpot = false
    _spotId = nil
    _biteActive = false
    _biteGen += 1
    _shopOpen = false
end

return PromptController
