--!strict
-- Abyssal — SpawnService (server).
-- Character assembly for the MVP slice: every player gets a swim-ready
-- avatar the moment they join.
--   * SpawnLocation "GrottoSpawn" is the ONLY spawn (Neutral + Enabled), so
--     players load at the Grotto Dock pontoon (0,-4.5,108) next to Old Marrow.
--   * RespawnTime is short (5 s) so a lost character never blocks the loop.
--   * On CharacterAdded the Humanoid is forced into Swimming state, physics-
--     less (Massless root, no fall damage), with JumpHeight 0 / no walking
--     gait underwater. The client's SwimController drives velocity; the
--     server only guarantees the rig is swim-capable and can't fall through
--     the world (all map parts are CanCollide false; the seafloor collision
--     floor below keeps characters inside the bowl).
-- No gameplay numbers here — swim tuning stays in Config.Swim.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local SpawnService = {}

local FLOOR_NAME = "AbyssalSeafloorGuard"
local GUARD_Y = -78 -- below the Trench floor; catches any sinking character
local GUARD_SIZE = Vector3.new(600, 4, 600)

local _started = false

-- Invisible safety net: characters can never fall through the seafloor.
local function ensureGuardFloor()
	if Workspace:FindFirstChild(FLOOR_NAME) then
		return
	end
	local floor = Instance.new("Part")
	floor.Name = FLOOR_NAME
	floor.Anchored = true
	floor.CanCollide = true
	floor.Transparency = 1
	floor.Size = GUARD_SIZE
	floor.Position = Vector3.new(0, GUARD_Y, 0)
	floor.Parent = Workspace
end

local function prepawn(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		humanoid.JumpHeight = 0
		humanoid.RequiresNeck = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
		-- Underwater: default to Swimming, never a walking gait.
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Swimming)
		end)
	end
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if root then
		root.Massless = false
		-- Keep water-drag feel stable: mild buoyancy assist is client-side;
		-- the server just makes sure the root can be velocity-driven.
		root.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.5, 1, 1)
	end
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false -- swim-through world; guard floor stops falls
		end
	end
end

local function onCharacter(player: Player, character: Model)
	prepawn(character)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		-- Re-assert Swimming shortly after spawn (avatar assembly can reset it).
		task.delay(0.5, function()
			if humanoid.Parent then
				pcall(function()
					if humanoid:GetState() ~= Enum.HumanoidStateType.Swimming then
						humanoid:ChangeState(Enum.HumanoidStateType.Swimming)
					end
				end)
			end
		end)
		humanoid.Died:Connect(function()
			task.delay(Players.RespawnTime + 0.5, function()
				if player.Parent and not player.Character then
					player:LoadCharacter()
				end
			end)
		end)
	end
end

function SpawnService.Init()
	if _started then
		return
	end
	_started = true

	Players.RespawnTime = 5
	Players.CharacterAutoLoads = true
	ensureGuardFloor()

	-- GrottoSpawn is the only SpawnLocation in the place (map file); make
	-- sure nothing else can steal spawns.
	for _, player in Players:GetPlayers() do
		player.RespawnLocation = (Workspace:FindFirstChild("GrottoSpawn", true) :: SpawnLocation?)
		if not player.Character then
			player:LoadCharacter()
		else
			onCharacter(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(function(player: Player)
		player.RespawnLocation = (Workspace:FindFirstChild("GrottoSpawn", true) :: SpawnLocation?)
		if not player.Character then
			player:LoadCharacter()
		end
		player.CharacterAdded:Connect(function(character: Model)
			onCharacter(player, character)
		end)
		-- Late bind for the character that auto-loaded before the hook.
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(character: Model)
			onCharacter(player, character)
		end)
	end

	print("[Abyssal] SpawnService ready (GrottoSpawn + swim rig)")
end

return SpawnService
