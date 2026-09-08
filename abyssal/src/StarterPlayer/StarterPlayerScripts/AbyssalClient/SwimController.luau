--!strict
-- Abyssal — SwimController (client).
-- GDD §3 swim feel per Config.Swim: Base 16 / Sprint 24 / Vertical 12 with
-- AccelLerp 8 smoothing, plus the empty-oxygen 20% slow (flavor only).
--
-- NOTE (Lead Dev): this module is control logic ONLY — velocity math driven
-- by Humanoid.MoveDirection + Space/C/Ctrl/Shift. Character assembly
-- (swim-state Humanoid rig, animations, water volume/drowning flags, camera)
-- stays your job. Call SwimController.GetTargetVelocity(dt) from your
-- movement hook, or Init() for the default Humanoid-physics binding below.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("AbyssalShared")
local Config = require(Shared:WaitForChild("Config"))

local SwimController = {}
SwimController._velocity = Vector3.zero
SwimController._oxygenEmpty = false -- mirrored locally; server is authoritative
SwimController._oxygen = Config.Oxygen.Max
SwimController._swimUp = false -- Space held (bound in Init)
SwimController._swimDown = false -- C / Ctrl held (bound in Init)
SwimController._sprint = false -- Shift held (bound in Init)

local function humanoid(): Humanoid?
    local character = Players.LocalPlayer.Character
    return character and character:FindFirstChildOfClass("Humanoid")
end

function SwimController.SetOxygenEmpty(empty: boolean)
    SwimController._oxygenEmpty = empty
end

-- Local oxygen mirror for the HUD bar + slow. Server ticks the real value;
-- no oxygen remote exists in the contract, so the client replays the same
-- Config.Oxygen math (drain/refill) from the character position.
function SwimController.TickLocalOxygen(position: Vector3, dt: number)
    local refilling = position.Y >= Config.Oxygen.SurfaceY
    if not refilling then
        for _, spot in Config.Spots do
            if (position - spot.VentOffset).Magnitude <= spot.VentRadius then
                refilling = true
                break
            end
        end
    end
    if refilling then
        SwimController._oxygen = math.min(Config.Oxygen.Max, SwimController._oxygen + Config.Oxygen.RefillPerSec * dt)
    else
        SwimController._oxygen =
            math.max(0, SwimController._oxygen - (Config.Oxygen.Max / Config.Oxygen.DrainTime) * dt)
    end
    SwimController._oxygenEmpty = SwimController._oxygen <= 0
end

function SwimController.OxygenFraction(): number
    return SwimController._oxygen / Config.Oxygen.Max
end

-- GDD §3: empty oxygen slows swim 20%, never a fail state.
function SwimController.SpeedMultiplier(): number
    if SwimController._oxygenEmpty then
        return 1 - Config.Swim.EmptyOxygenSlow
    end
    return 1
end

local function sprinting(): boolean
    return SwimController._sprint
end

-- Core feel: target velocity from input, exponentially smoothed by
-- AccelLerp (higher = snappier, lower = floatier). Returns the smoothed
-- velocity the Lead Dev's movement hook should apply.
function SwimController.GetTargetVelocity(dt: number, moveDir: Vector3, vertical: number, wantSprint: boolean): Vector3
    local speed = if wantSprint then Config.Swim.SprintSpeed else Config.Swim.BaseSpeed
    speed *= SwimController.SpeedMultiplier()
    local horizontal = Vector3.new(moveDir.X, 0, moveDir.Z)
    if horizontal.Magnitude > 1 then
        horizontal = horizontal.Unit
    end
    local target = horizontal * speed + Vector3.new(0, vertical * Config.Swim.VerticalSpeed, 0)
    local alpha = 1 - math.exp(-Config.Swim.AccelLerp * dt)
    SwimController._velocity = SwimController._velocity:Lerp(target, alpha)
    return SwimController._velocity
end

local _started = false

function SwimController.Init()
    if _started then
        return
    end
    _started = true

    -- Default binding: track Space / C / Ctrl / Shift, then drive a swimming
    -- Humanoid via MoveDirection. The Lead Dev replaces the velocity hook
    -- with the real rig/camera work if needed; GetTargetVelocity stays the
    -- tuning surface either way.
    local function bindHold(action: string, key: Enum.KeyCode, set: (boolean) -> ())
        ContextActionService:BindAction(action, function(_, state: EnumItem)
            if state == Enum.UserInputState.Begin then
                set(true)
            elseif state == Enum.UserInputState.End then
                set(false)
            end
            return Enum.ContextActionResult.Pass
        end, false, key)
    end
    bindHold("AbyssalSwimUp", Enum.KeyCode.Space, function(v: boolean)
        SwimController._swimUp = v
    end)
    bindHold("AbyssalSwimDown", Enum.KeyCode.C, function(v: boolean)
        SwimController._swimDown = v
    end)
    bindHold("AbyssalSwimDownCtrl", Enum.KeyCode.LeftControl, function(v: boolean)
        SwimController._swimDown = v
    end)
    bindHold("AbyssalSprint", Enum.KeyCode.LeftShift, function(v: boolean)
        SwimController._sprint = v
    end)
    RunService.RenderStepped:Connect(function(dt: number)
        local character = Players.LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
        local hum = humanoid()
        if not root or not hum then
            return
        end
        SwimController.TickLocalOxygen(root.Position, dt)
        local vertical = (if SwimController._swimUp then 1 else 0) - (if SwimController._swimDown then 1 else 0)
        local velocity = SwimController.GetTargetVelocity(dt, hum.MoveDirection, vertical, sprinting())
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, velocity.Y, velocity.Z)
    end)
end

return SwimController
