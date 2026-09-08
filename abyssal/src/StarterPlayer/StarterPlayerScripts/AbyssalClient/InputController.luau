--!strict
-- Abyssal — InputController (client).
-- GDD §5 inputs (PC): E = cast / hook / confirm; hold LMB or Space = reel;
-- R = cancel line; E near shop = trade. Sends ClientToServer intent remotes
-- only — the server owns validation and state. Hook/cancel/reel sends are
-- cheap and idempotent; the server ignores them outside the right phase.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("AbyssalShared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local NetListener = require(script.Parent:WaitForChild("NetListener"))

local InputController = {}
InputController._lastSpotId = nil
InputController._inSpot = false
InputController._reeling = false
InputController._nearShop = false

local function getEvent(remoteName: string): RemoteEvent?
    return ReplicatedStorage:FindFirstChild(remoteName) :: RemoteEvent?
end

local function fireServer(remoteName: string, payload: any)
    local event = getEvent(remoteName)
    if event then
        event:FireServer(payload)
    end
end

local function playerPosition(): Vector3?
    local character = Players.LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if root then
        return root.Position
    end
    return nil
end

-- E near Old Marrow = trade. The Lead Dev places the NPC; its position is
-- read from a `OldMarrowNPCHint` Vector3Value in workspace when present,
-- else the Grotto Dock pontoon fallback (GDD §4 spawn).
local function shopPosition(): Vector3
    local hint = workspace:FindFirstChild("OldMarrowNPCHint") :: Vector3Value?
    if hint then
        return hint.Value
    end
    return Vector3.new(0, -2, 60)
end

function InputController.IsNearShop(): boolean
    local pos = playerPosition()
    if not pos then
        return false
    end
    return (pos - shopPosition()).Magnitude <= Config.Fishing.ShopPromptDistance
end

-- E is context-sensitive per GDD §5: shop trade > hook attempt > cast.
function InputController.PressE()
    if InputController.IsNearShop() then
        fireServer(Remotes.ShopInteract, nil)
        return
    end
    fireServer(Remotes.HookAttempt, nil) -- server no-ops unless phase == "bite"
    if InputController._inSpot and InputController._lastSpotId then
        fireServer(Remotes.CastRequest, { spotId = InputController._lastSpotId })
    end
end

function InputController.Cancel()
    fireServer(Remotes.CancelLine, nil)
    if InputController._reeling then
        InputController._reeling = false
    end
end

-- GDD §8 shop tab intents (the UI/UX designer's shop screen calls these;
-- exposing them here keeps all server-bound sends in one module).
function InputController.SellAll()
    fireServer(Remotes.ShopSellAll, nil)
end

function InputController.SellOne(speciesId: string)
    fireServer(Remotes.ShopSellOne, { species = speciesId })
end

function InputController.BuyRod(rodId: string)
    fireServer(Remotes.ShopBuyRod, { rodId = rodId })
end

function InputController.SetReeling(holding: boolean)
    if InputController._reeling == holding then
        return
    end
    InputController._reeling = holding
    fireServer(Remotes.ReelInput, { holding = holding })
end

local _started = false

function InputController.Init()
    if _started then
        return
    end
    _started = true

    NetListener.On(Remotes.SpotPrompt, function(payload: any)
        InputController._inSpot = payload and payload.inSpot == true
        if payload and typeof(payload.spotId) == "string" then
            InputController._lastSpotId = payload.spotId
        elseif not InputController._inSpot then
            InputController._lastSpotId = nil
        end
    end)
    NetListener.On(Remotes.CatchResult, function()
        InputController._reeling = false -- fight over; release the hold state
    end)
    NetListener.On(Remotes.LineFailed, function()
        InputController._reeling = false
    end)

    ContextActionService:BindAction("AbyssalCastHook", function(_, state: EnumItem)
        if state == Enum.UserInputState.Begin then
            InputController.PressE()
        end
        return Enum.ContextActionResult.Pass
    end, false, Enum.KeyCode.E)

    ContextActionService:BindAction("AbyssalCancel", function(_, state: EnumItem)
        if state == Enum.UserInputState.Begin then
            InputController.Cancel()
        end
        return Enum.ContextActionResult.Pass
    end, false, Enum.KeyCode.R)

    -- Hold LMB or Space = reel. Space doubles as swim-up; the server only
    -- reads ReelInput during the reel phase, so overlap is harmless.
    UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
        if processed then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.Space then
            InputController.SetReeling(true)
        end
    end)
    UserInputService.InputEnded:Connect(function(input: InputObject)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.Space then
            InputController.SetReeling(false)
        end
    end)
end

return InputController
