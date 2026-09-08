--!strict
-- Abyssal — OldMarrowNPC (client).
-- Makes the shop NPC readable + approachable (GDD §4/§8):
--   * Finds the map's Old Marrow placeholder parts (OldMarrowBody/Head/Hat at
--     5,-4,103) and augments them: name billboard ("OLD MARROW — E to trade"),
--     gold shop ring on the seafloor marking the ShopPromptDistance radius
--     edge is too big to draw; instead a 4-stud welcome ring pulses at his
--     feet so players SEE where to stand.
--   * Proximity loop (10 Hz): inside Config.Fishing.ShopPromptDistance the
--     billboard turns gold and the prompt pill is driven via
--     PromptController.Refresh (priority: shop > hook > cast already holds).
--   * Immobile by design (MVP): he bobs gently + his lantern flickers.
-- Self-contained + pcall-guarded; mounts from Init.client.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("AbyssalShared")
local Config = require(Shared:WaitForChild("Config"))

local OldMarrowNPC = {}

local _started = false

local function npcAnchor(): BasePart?
	local map = Workspace:FindFirstChild("AbyssalMap")
	local head: Instance? = nil
	if map then
		head = map:FindFirstChild("OldMarrowHead", true)
	end
	if head and head:IsA("BasePart") then
		return head
	end
	local fallback = Workspace:FindFirstChild("OldMarrowHead", true)
	if fallback and fallback:IsA("BasePart") then
		return fallback
	end
	return nil
end

local function ensureBillboard(head: BasePart): TextLabel?
	pcall(function()
		if head:FindFirstChild("MarrowTag") then
			return
		end
		local gui = Instance.new("BillboardGui")
		gui.Name = "MarrowTag"
		gui.Size = UDim2.new(0, 260, 0, 70)
		gui.StudsOffset = Vector3.new(0, 2.6, 0)
		gui.AlwaysOnTop = true
		gui.Parent = head
		local label = Instance.new("TextLabel")
		label.Name = "TagText"
		label.Text = "OLD MARROW"
		label.Font = Enum.Font.GothamBold
		label.TextSize = 22
		label.TextColor3 = Color3.fromRGB(251, 191, 36)
		label.BackgroundColor3 = Color3.fromRGB(2, 12, 15)
		label.BackgroundTransparency = 0.25
		label.Size = UDim2.new(1, 0, 1, 0)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = label
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(251, 191, 36)
		stroke.Thickness = 2
		stroke.Parent = label
		label.Parent = gui
	end)
	local gui = head:FindFirstChild("MarrowTag") :: BillboardGui?
	local label = gui and gui:FindFirstChild("TagText") :: TextLabel?
	return label
end

local function ensureWelcomeRing(npcPos: Vector3): Part?
	local old = Workspace:FindFirstChild("MarrowWelcomeRing") :: Part?
	if old and old:IsA("Part") then
		return old
	end
	local ring: Part? = nil
	pcall(function()
		local r = Instance.new("Part")
		r.Name = "MarrowWelcomeRing"
		r.Shape = Enum.PartType.Cylinder
		r.Size = Vector3.new(0.3, 8, 8)
		r.Color = Color3.fromRGB(251, 191, 36)
		r.Material = Enum.Material.Neon
		r.Transparency = 0.55
		r.Anchored = true
		r.CanCollide = false
		r.CanQuery = false
		r.CanTouch = false
		r.Position = Vector3.new(npcPos.X, npcPos.Y - 1.5, npcPos.Z)
		r.Parent = Workspace
		ring = r
	end)
	return ring
end

function OldMarrowNPC.Init()
	if _started then
		return
	end
	_started = true

	task.spawn(function()
		-- Wait for the map to stream in (Rojo places it at load).
		local head: BasePart? = nil
		for _ = 1, 100 do
			head = npcAnchor()
			if head then
				break
			end
			task.wait(0.3)
		end
		if not head then
			warn("[Abyssal] OldMarrowNPC: placeholder not found; shop prompt still works via hint")
			return
		end
		local label = ensureBillboard(head)
		local ring = ensureWelcomeRing(head.Position)
		local baseY = head.Position.Y

		local acc = 0
		RunService.Heartbeat:Connect(function(dt: number)
			pcall(function()
				acc += dt
				if acc < 0.1 then
					return
				end
				acc = 0
				local player = Players.LocalPlayer
				local character = player and player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local near = false
				if root then
					near = (root.Position - head.Position).Magnitude <= Config.Fishing.ShopPromptDistance
				end
				if label then
					label.Text = if near then "OLD MARROW — Press E to trade" else "OLD MARROW"
					label.TextColor3 = if near then Color3.fromRGB(255, 235, 170) else Color3.fromRGB(251, 191, 36)
				end
				if ring then
					-- Gentle pulse so the trade spot reads from across the dock.
					local pulse = 0.45 + 0.2 * math.sin(os.clock() * 2.5)
					ring.Transparency = if near then 0.25 else pulse
				end
				-- Idle bob (immobile NPC, alive feel).
				head.Position = Vector3.new(head.Position.X, baseY + math.sin(os.clock() * 1.2) * 0.15, head.Position.Z)
			end)
		end)
	end)

	print("[Abyssal] OldMarrowNPC ready")
end

return OldMarrowNPC
