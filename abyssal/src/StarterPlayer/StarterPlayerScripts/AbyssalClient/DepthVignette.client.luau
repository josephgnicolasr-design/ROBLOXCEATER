--!strict
-- Abyssal — DepthVignette.client (Tech Art, NEW — touches no contracts).
-- GDD §4 atmosphere: depth vignette (darkens with depth) + swim-bubble trail.
-- Self-contained and fully pcall-guarded: any failure here only kills this
-- script, never Init.client / swim / fishing. Safe to delete or replace.
-- Expects Workspace/AtmosphereFX/SwimTrailTemplate (ParticleEmitter) from
-- src/Workspace/AtmosphereFX.rbxmx. Surface Y = 0 (matches Config.SurfaceY).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local MAX_DEPTH = 65 -- y=0 surface -> full vignette at y<=-65 (past Trench 60)
local UPDATE_HZ = 10 -- throttle GUI writes; 10 Hz is plenty for a vignette

local function buildVignette(parent: PlayerGui): { Frame }
	pcall(function()
		local old = parent:FindFirstChild("DepthVignette")
		if old then
			old:Destroy()
		end
	end)
	local gui = Instance.new("ScreenGui")
	gui.Name = "DepthVignette"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5 -- below bite/reel overlays (UI/UX owns those layers)
	local edges: { Frame } = {}
	local defs = {
		{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(1, 0, 0.22, 0), Rotation = 90 },
		{ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, 0, 0.22, 0), Rotation = -90 },
		{ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(0.14, 0, 1, 0), Rotation = 0 },
		{ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0.14, 0, 1, 0), Rotation = 180 },
	}
	for _, d in defs do
		local f = Instance.new("Frame")
		f.AnchorPoint = d.AnchorPoint
		f.Position = d.Position
		f.Size = d.Size
		f.BackgroundColor3 = Color3.fromRGB(2, 8, 20)
		f.BorderSizePixel = 0
		local g = Instance.new("UIGradient")
		g.Rotation = d.Rotation
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = f
		f.Parent = gui
		table.insert(edges, f)
	end
	gui.Parent = parent
	return edges
end

local function main()
	local player = Players.LocalPlayer
	if not player then
		return
	end
	local playerGui = player:WaitForChild("PlayerGui", 15)
	if not (playerGui and playerGui:IsA("PlayerGui")) then
		return
	end
	local edges = buildVignette(playerGui :: PlayerGui)

	-- Swim-bubble trail: clone template emitter into the character.
	local trailTemplate: ParticleEmitter? = nil
	pcall(function()
		local fx = Workspace:WaitForChild("AtmosphereFX", 15)
		if fx then
			local tpl = fx:WaitForChild("SwimTrailTemplate", 15)
			if tpl then
				local e = tpl:FindFirstChildOfClass("ParticleEmitter")
				if e and e:IsA("ParticleEmitter") then
					trailTemplate = e
				end
			end
		end
	end)
	local activeTrail: ParticleEmitter? = nil
	local function attachTrail(char: Model)
		if not trailTemplate then
			return
		end
		pcall(function()
			local root = char:WaitForChild("HumanoidRootPart", 10)
			if root and root:IsA("BasePart") then
				if activeTrail then
					pcall(function()
						(activeTrail :: ParticleEmitter):Destroy()
					end)
					activeTrail = nil
				end
				local clone = (trailTemplate :: ParticleEmitter):Clone()
				clone.Enabled = false
				clone.Parent = root
				activeTrail = clone
			end
		end)
	end
	if player.Character then
		attachTrail(player.Character)
	end
	player.CharacterAdded:Connect(attachTrail)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < (1 / UPDATE_HZ) then
			return
		end
		acc = 0
		pcall(function()
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local y = 0
			local speed = 0
			if root and root:IsA("BasePart") then
				y = (root :: BasePart).Position.Y
				speed = (root :: BasePart).AssemblyLinearVelocity.Magnitude
			end
			-- Depth vignette: 0 at surface, up to 0.6 edge darkness at max depth.
			local depth01 = math.clamp(-y / MAX_DEPTH, 0, 1)
			for _, f in edges do
				(f :: Frame).BackgroundTransparency = 1 - (0.6 * depth01)
			end
			-- Swim trail: emit only while actually moving.
			if activeTrail then
				(activeTrail :: ParticleEmitter).Enabled = speed > 3;
			end
		end)
	end)
end

pcall(main)
print("[Abyssal] DepthVignette ready")
