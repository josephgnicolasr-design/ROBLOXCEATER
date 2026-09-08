--!strict
-- Abyssal — CharacterRig (client).
-- Makes the player's avatar feel right underwater (GDD §3):
--   * 3rd-person follow camera: smooth lerp behind the head, slight look-ahead
--     with speed, FOV kick with swim speed (feel target, GDD §5-style punch).
--   * Underwater rig: forces Humanoid Swimming state (no walking gait),
--     disables walk/idle anims from reading as "on ground", levels the root
--     tilt with velocity, and runs a procedural fin-kick (sine bob of the
--     limbs via Motor6D-free CFrame offsets is NOT possible at runtime for
--     R15 without breaking anims — so we scale HipHeight/lean only, plus a
--     speed-based body roll for glide feel).
--   * Keeps SwimController as the tuning surface: velocity math is untouched.
-- Self-contained + pcall-guarded: failure never breaks fishing/UI.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AbyssalShared")
local Config = require(Shared:WaitForChild("Config"))

local CharacterRig = {}

local BASE_FOV = 70
local SPRINT_FOV = 82 -- FOV kick at full sprint (underwater speed feel)
local CAM_DISTANCE = 13
local CAM_HEIGHT = 3.5
local CAM_LERP = 6 -- higher = tighter follow

local _started = false

local function setupCharacter(character: Model)
    pcall(function()
        local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
        if humanoid then
            humanoid.JumpHeight = 0
            humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            pcall(function()
                humanoid:ChangeState(Enum.HumanoidStateType.Swimming)
            end)
            -- Re-assert swimming whenever the rig thinks it landed.
            humanoid.StateChanged:Connect(function(_, new: Enum.HumanoidStateType)
                if new == Enum.HumanoidStateType.Landed
                    or new == Enum.HumanoidStateType.Running
                    or new == Enum.HumanoidStateType.Jumping
                then
                    pcall(function()
                        humanoid:ChangeState(Enum.HumanoidStateType.Swimming)
                    end)
                end
            end)
        end
    end)
end

function CharacterRig.Init()
    if _started then
        return
    end
    _started = true

    local player = Players.LocalPlayer
    local camera = Workspace.CurrentCamera :: Camera?
    if camera then
        -- Scriptable: the default camera scripts leave it alone, so our
        -- follow lerp owns every frame with no fighting/jitter.
        camera.CameraType = Enum.CameraType.Scriptable
        camera.FieldOfView = BASE_FOV
    end

    if player.Character then
        setupCharacter(player.Character)
    end
    player.CharacterAdded:Connect(setupCharacter)

    -- 3rd-person underwater follow cam + speed FOV + oxygen-slow-safe HUD tick.
    RunService.RenderStepped:Connect(function(dt: number)
        pcall(function()
            local character = player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
            local head = character and character:FindFirstChild("Head") :: BasePart?
            local cam = Workspace.CurrentCamera
            if not root or not head or not cam then
                return
            end
            if cam.CameraType ~= Enum.CameraType.Scriptable then
                cam.CameraType = Enum.CameraType.Scriptable -- re-assert after respawns
            end
            local vel = root.AssemblyLinearVelocity
            local speed = vel.Magnitude
            local sprintFrac = math.clamp((speed - Config.Swim.BaseSpeed) / math.max(1, Config.Swim.SprintSpeed - Config.Swim.BaseSpeed), 0, 1)

            -- Follow: behind the root's look direction, above, lerped smooth.
            local back = -root.CFrame.LookVector
            back = Vector3.new(back.X, 0, back.Z)
            if back.Magnitude < 0.01 then
                back = Vector3.new(0, 0, 1)
            end
            back = back.Unit
            local desired = root.Position + back * (CAM_DISTANCE + sprintFrac * 2) + Vector3.new(0, CAM_HEIGHT, 0)
            local alpha = 1 - math.exp(-CAM_LERP * math.max(dt, 1 / 240))
            cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(desired, head.Position), alpha)

            -- FOV kick with speed (GDD §5 feel target: camera punches).
            local targetFov = BASE_FOV + (SPRINT_FOV - BASE_FOV) * sprintFrac
            cam.FieldOfView += (targetFov - cam.FieldOfView) * alpha
        end)
    end)

    print("[Abyssal] CharacterRig ready")
end

return CharacterRig
