--!strict
-- Abyssal — FishVisuals (client).
-- Visible fish (GDD §6): procedural primitive models bound per-Heartbeat to
-- the server's ReplicatedStorage/AbyssalFish mirror (written by FishBinder
-- from FishAI.GetFish). No external assets.
--   * Per spot × slot: body (Part, species-tinted) + tail (wedge Part that
--     wags with a sine) + optional glow lure (Lanternjaw, violet PointLight).
--   * Species colors from Config: Sunfin yellow/blue, Rustbelly green/rust,
--     Lanternjaw black/violet. Bite tease is readable: approach/circle fish
--     visibly hurry to the bobber; scatter visibly bursts away.
--   * Pool of PerSpotMax models per spot; "gone" slots park at y=-500.
-- Self-contained + pcall-guarded; mounts from Init.client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("AbyssalShared")
local Config = require(Shared:WaitForChild("Config"))

local FishVisuals = {}

local FOLDER_NAME = "AbyssalFish"
local ROOT_NAME = "AbyssalFishModels"
local PARKED = Vector3.new(0, -500, 0)

-- Species tints (GDD §6 looks; Config has no colors, so tints live here).
local TINTS = {
    Sunfin = {
        Body = Color3.fromRGB(250, 204, 21), -- yellow damsel
        Tail = Color3.fromRGB(59, 130, 246), -- blue forked tail
        Glow = nil :: Color3?,
    },
    Rustbelly = {
        Body = Color3.fromRGB(74, 124, 89), -- fat green catfish
        Tail = Color3.fromRGB(183, 65, 14), -- scrap-metal rust flank
        Glow = nil :: Color3?,
    },
    Lanternjaw = {
        Body = Color3.fromRGB(10, 10, 14), -- black anglerfish
        Tail = Color3.fromRGB(76, 29, 149), -- violet fins
        Glow = Color3.fromRGB(168, 85, 247), -- glowing lure
    },
}

type FishModel = {
    root: Part,
    body: Part,
    tail: Part,
    lure: Part?,
    phase: number,
}

local _pool: { [string]: { FishModel } } = {}
local _container: Folder? = nil
local _started = false

local function makePart(name: string, size: Vector3, color: Color3, material: Enum.Material, transparency: number): Part
    local p = Instance.new("Part")
    p.Name = name
    p.Size = size
    p.Color = color
    p.Material = material
    p.Transparency = transparency
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.CanTouch = false
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    return p
end

local function makeFishModel(slotName: string): FishModel
    local root = makePart(slotName, Vector3.new(1, 1, 1), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, 1)
    root.Transparency = 1
    local body = makePart(slotName .. "_Body", Vector3.new(1.1, 0.9, 2.2), Color3.fromRGB(250, 204, 21), Enum.Material.SmoothPlastic, 0)
    body.Shape = Enum.PartType.Ball
    body.Parent = root
    local tail = makePart(slotName .. "_Tail", Vector3.new(0.25, 0.8, 0.9), Color3.fromRGB(59, 130, 246), Enum.Material.SmoothPlastic, 0)
    tail.Shape = Enum.PartType.Wedge
    tail.Parent = root
    local lure = makePart(slotName .. "_Lure", Vector3.new(0.35, 0.35, 0.35), Color3.fromRGB(168, 85, 247), Enum.Material.Neon, 0)
    lure.Shape = Enum.PartType.Ball
    lure.Parent = root
    local light = Instance.new("PointLight")
    light.Name = "LureGlow"
    light.Color = Color3.fromRGB(168, 85, 247)
    light.Brightness = 2
    light.Range = 8
    light.Shadows = false
    light.Parent = lure
    root.Parent = _container
    return { root = root, body = body, tail = tail, lure = lure, phase = math.random() * math.pi * 2 }
end

local function applyTint(m: FishModel, species: string)
    local tint = TINTS[species] or TINTS.Sunfin
    m.body.Color = tint.Body
    m.tail.Color = tint.Tail
    if tint.Glow ~= nil then
        (m.lure :: Part).Transparency = 0
        local light = (m.lure :: Part):FindFirstChildOfClass("PointLight")
        if light then
            light.Enabled = true
        end
    else
        (m.lure :: Part).Transparency = 1
        local light = (m.lure :: Part):FindFirstChildOfClass("PointLight")
        if light then
            light.Enabled = false
        end
    end
end

function FishVisuals.Init()
    if _started then
        return
    end
    _started = true

    pcall(function()
        local old = Workspace:FindFirstChild(ROOT_NAME)
        if old then
            old:Destroy()
        end
        local container = Instance.new("Folder")
        container.Name = ROOT_NAME
        container.Parent = Workspace
        _container = container

        for spotId, _ in Config.Spots do
            _pool[spotId] = {}
            for i = 1, Config.FishAI.PerSpotMax do
                local m = makeFishModel(spotId .. "_" .. tostring(i))
                applyTint(m, "Sunfin")
                m.root.Position = PARKED
                table.insert(_pool[spotId], m)
            end
        end

        RunService.Heartbeat:Connect(function(_dt: number)
            pcall(function()
                local mirror = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder?
                if not mirror then
                    return
                end
                local t = os.clock()
                for spotId, models in _pool do
                    local spotFolder = mirror:FindFirstChild(spotId) :: Folder?
                    for i, m in models do
                        local slot: Vector3Value? = nil
                        if spotFolder then
                            local child = spotFolder:FindFirstChild(tostring(i))
                            if child and child:IsA("Vector3Value") then
                                slot = child
                            end
                        end
                        if slot == nil or (slot :: Vector3Value):GetAttribute("State") == "gone" then
                            m.root.Position = PARKED
                            continue
                        end
                        local pos = (slot :: Vector3Value).Value
                        local species = tostring((slot :: Vector3Value):GetAttribute("Species") or "Sunfin")
                        local state = tostring((slot :: Vector3Value):GetAttribute("State") or "patrol")
                        applyTint(m, species)
                        -- Face travel: orient along horizontal motion (flattened so
                        -- near-vertical approaches can't hit lookAt's up-vector
                        -- singularity); hold last heading when near-stationary.
                        local prev = m.root.Position
                        local dir = pos - prev
                        local flat = Vector3.new(dir.X, 0, dir.Z)
                        local look: CFrame
                        if flat.Magnitude > 0.05 then
                            look = CFrame.lookAt(pos, pos + flat)
                        else
                            look = CFrame.new(pos) * m.root.CFrame.Rotation
                        end
                        m.root.CFrame = look
                        m.root.Position = pos
                        -- Body + tail layout (tail behind, wagging sine; faster
                        -- wag when approaching/circling the bobber = readable tease).
                        local wagSpeed = if state == "approach" or state == "circle" then 14 else 7
                        local wag = math.sin(t * wagSpeed + m.phase) * 0.45
                        m.body.CFrame = m.root.CFrame
                        m.tail.CFrame = m.root.CFrame * CFrame.new(0, 0, 1.5) * CFrame.Angles(0, wag, 0)
                        if (m.lure :: Part).Transparency < 0.5 then
                            (m.lure :: Part).CFrame = m.root.CFrame * CFrame.new(0, 0.7, -1.5)
                        else
                            (m.lure :: Part).CFrame = m.root.CFrame * CFrame.new(0, -50, 0)
                        end
                        -- Circle-state ring pulse: scale up slightly so the
                        -- Rustbelly tease reads at a glance.
                        local s = if state == "circle" then 1.25 else 1.0
                        m.body.Size = Vector3.new(1.1 * s, 0.9 * s, 2.2 * s)
                    end
                end
            end)
        end)
    end)

    print("[Abyssal] FishVisuals ready")
end

return FishVisuals
