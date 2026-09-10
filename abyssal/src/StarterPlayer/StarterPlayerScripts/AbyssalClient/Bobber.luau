--!strict
-- Abyssal — Bobber (client).
-- Bobber + line visuals (GDD §5): a visible bobber at the cast point with a
-- line tether to the rod, driven by server remotes (contract untouched):
--   * CastStarted -> spawn bobber ~12 studs ahead (server owns the real
--     position; the client mirrors the same math from its own root).
--   * Waiting: bobbing sine on the water; BitePrompt -> red "!" flash, splash
--     particles, vibration with tension; ReelState surge -> line tenses red.
--   * CatchResult / LineFailed -> splash burst + cleanup (catch = 0.4 s
--     slow-mo style scale pop; fails read as "almost").
-- All procedural primitives; pcall-guarded; mounts from Init.client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClientFolder = script.Parent
local NetListener = require(ClientFolder:WaitForChild("NetListener"))

local Shared = ReplicatedStorage:WaitForChild("AbyssalShared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Bobber = {}

local ROOT_NAME = "AbyssalBobber"

local _bobber: Part? = nil
local _line: Part? = nil -- stretched cylinder from hand to bobber
local _ring: Part? = nil -- ripple ring on cast land
local _promptBillboard: BillboardGui? = nil
local _active = false
local _landAt = 0
local _biteAt: number? = nil
local _surging = false
local _started = false

local function clear()
	pcall(function()
		local old = Workspace:FindFirstChild(ROOT_NAME)
		if old then
			old:Destroy()
		end
	end)
	_bobber = nil
	_line = nil
	_ring = nil
	_promptBillboard = nil
	_active = false
	_biteAt = nil
	_surging = false
end

local function makePart(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Transparency = 0
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function handPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		return root.Position + Vector3.new(0, 1.2, 0) + root.CFrame.LookVector * 1.2
	end
	return nil
end

local function castPoint(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local forward = root.CFrame.LookVector
	forward = Vector3.new(forward.X, 0, forward.Z)
	if forward.Magnitude < 0.01 then
		forward = Vector3.new(0, 0, -1)
	end
	-- Mirror of FishingService.TryCast bobber math (client-side visual only).
	return root.Position + forward.Unit * Config.Fishing.BobberDistance + Vector3.new(0, -2, 0)
end

local function spawnBobber()
	clear()
	local folder = Instance.new("Folder")
	folder.Name = ROOT_NAME
	folder.Parent = Workspace

	local point = castPoint() or ((handPosition() or Vector3.new(0, -10, 80)) + Vector3.new(0, 0, -8))

	local bobber = makePart("Bobber", Vector3.new(0.9, 0.9, 0.9), Color3.fromRGB(255, 70, 70), Enum.Material.Neon)
	bobber.Shape = Enum.PartType.Ball
	bobber.Position = point
	bobber.Parent = folder
	_bobber = bobber

	local tip = makePart("BobberTip", Vector3.new(0.35, 0.7, 0.35), Color3.fromRGB(255, 255, 255), Enum.Material.Neon)
	tip.Position = point + Vector3.new(0, 0.7, 0)
	tip.Parent = folder

	local ring = makePart("Ripple", Vector3.new(3.5, 0.2, 3.5), Color3.fromRGB(150, 230, 255), Enum.Material.Neon)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.4
	ring.Position = point
	ring.Parent = folder
	_ring = ring

	local line = makePart("Line", Vector3.new(0.08, 1, 0.08), Color3.fromRGB(230, 240, 245), Enum.Material.SmoothPlastic)
	line.Transparency = 0.25
	line.Parent = folder
	_line = line

	_active = true
	_landAt = os.clock()
end

local function splash(at: Vector3, big: boolean)
	pcall(function()
		local folder = Workspace:FindFirstChild(ROOT_NAME)
		if not folder then
			return
		end
		local burst = makePart("Splash", Vector3.new(1.4, 1.4, 1.4), Color3.fromRGB(180, 235, 255), Enum.Material.Neon)
		burst.Shape = Enum.PartType.Ball
		burst.Transparency = 0.3
		burst.Position = at
		burst.Parent = folder
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < 0.5 do
				local k = (os.clock() - t0) / 0.5
				pcall(function()
					burst.Size = Vector3.new(1.4, 1.4, 1.4) * (1 + k * (if big then 2.5 else 1.2))
					burst.Transparency = 0.3 + k * 0.7
				end)
				task.wait()
			end
			pcall(function()
				burst:Destroy()
			end)
		end)
	end)
end

local function flashBite()
	if not _bobber then
		return
	end
	_biteAt = os.clock()
	splash(_bobber.Position, false)
	pcall(function()
		local bobber = _bobber :: Part
		local gui = Instance.new("BillboardGui")
		gui.Name = "BiteFlash"
		gui.Size = UDim2.new(0, 90, 0, 90)
		gui.StudsOffset = Vector3.new(0, 2.5, 0)
		gui.AlwaysOnTop = true
		gui.Parent = bobber
		local label = Instance.new("TextLabel")
		label.Text = "!"
		label.Font = Enum.Font.GothamBold
		label.TextSize = 72
		label.TextColor3 = Color3.fromRGB(255, 45, 45)
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 1, 0)
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Thickness = 3
		stroke.Parent = label
		label.Parent = gui
		_promptBillboard = gui
		task.delay(Config.Fishing.HookWindow + 0.3, function()
			pcall(function()
				gui:Destroy()
			end)
			if _promptBillboard == gui then
				_promptBillboard = nil
			end
		end)
	end)
end

function Bobber.Init()
	if _started then
		return
	end
	_started = true

	NetListener.On(Remotes.CastStarted, function()
		spawnBobber()
	end)
	NetListener.On(Remotes.BitePrompt, function()
		flashBite()
	end)
	NetListener.On(Remotes.ReelState, function(payload: any)
		if typeof(payload) == "table" then
			_surging = (payload :: any).surge == true
		end
	end)
	NetListener.On(Remotes.CatchResult, function()
		if _bobber then
			splash(_bobber.Position, true) -- catch = big splash + card (UI-side)
		end
		clear()
	end)
	NetListener.On(Remotes.LineFailed, function()
		clear() -- miss reads as "almost": splash already fired on bite
	end)

	RunService.RenderStepped:Connect(function()
		pcall(function()
			if not _active or not _bobber or not _line then
				return
			end
			local bobber = _bobber :: Part
			local line = _line :: Part
			local t = os.clock()
			-- Bobbing during wait; vibration after the bite lands.
			local bobAmp = if _biteAt ~= nil then 0.35 else 0.15
			local bobHz = if _biteAt ~= nil then 10 else 2
			bobber.Position += Vector3.new(0, math.sin(t * bobHz) * bobAmp * 0.016, 0)
			if _biteAt ~= nil then
				bobber.Color = Color3.fromRGB(255, 30, 30)
			elseif _surging then
				bobber.Color = Color3.fromRGB(255, 150, 60)
			else
				bobber.Color = Color3.fromRGB(255, 70, 70)
			end
			-- Ripple ring expands + fades after the cast lands.
			if _ring then
				local k = math.clamp((t - _landAt) / 1.2, 0, 1)
				;(_ring :: Part).Size = Vector3.new(3.5 + k * 6, 0.2, 3.5 + k * 6);
				(_ring :: Part).Transparency = 0.4 + k * 0.6
				if k >= 1 then
					pcall(function()
						(_ring :: Part):Destroy()
					end)
					_ring = nil
				end
			end
			-- Line tether: stretch a cylinder from hand to bobber.
			local hand = handPosition()
			if hand then
				local mid = (hand + bobber.Position) / 2
				local dist = (hand - bobber.Position).Magnitude
				line.Size = Vector3.new(0.08, dist, 0.08)
				line.CFrame = CFrame.lookAt(mid, bobber.Position) * CFrame.Angles(math.pi / 2, 0, 0)
				line.Color = if _surging then Color3.fromRGB(255, 60, 60) else Color3.fromRGB(230, 240, 245)
			end
		end)
	end)

	print("[Abyssal] Bobber ready")
end

return Bobber
