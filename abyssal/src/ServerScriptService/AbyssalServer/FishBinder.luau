--!strict
-- Abyssal — FishBinder (server).
-- Lead Dev integration: mirrors FishAI.GetFish(spotId) positions into
-- ReplicatedStorage/AbyssalFish/<SpotId>/<1..6> Vector3Values (10 Hz) with
-- Species + State attributes, so the client's FishVisuals binder can place
-- visible fish models without touching the Remotes contract. "gone" fish
-- park at y=-500. No gameplay numbers here — visuals only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("AbyssalShared")
local Config = require(Shared:WaitForChild("Config"))

local FishAI = require(script.Parent:WaitForChild("FishAI"))

local FishBinder = {}

local FOLDER_NAME = "AbyssalFish"
local UPDATE_HZ = 10
local PARKED = Vector3.new(0, -500, 0)

local _started = false

local function ensureFolder(): Folder
	local found = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if found and found:IsA("Folder") then
		return found
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

function FishBinder.Start()
	if _started then
		return
	end
	_started = true

	local root = ensureFolder()
	local slots: { [string]: { Vector3Value } } = {}
	for spotId, _ in Config.Spots do
		local spotFolder = Instance.new("Folder")
		spotFolder.Name = spotId
		spotFolder.Parent = root
		local list: { Vector3Value } = {}
		for i = 1, Config.FishAI.PerSpotMax do
			local v = Instance.new("Vector3Value")
			v.Name = tostring(i)
			v.Value = PARKED
			v:SetAttribute("Species", "Sunfin")
			v:SetAttribute("State", "gone")
			v.Parent = spotFolder
			table.insert(list, v)
		end
		slots[spotId] = list
	end

	task.spawn(function()
		while true do
			task.wait(1 / UPDATE_HZ)
			pcall(function()
				for spotId, list in slots do
					local school = FishAI.GetFish(spotId)
					for i, v in list do
						local fish = school[i]
						if fish ~= nil and fish.state ~= "gone" then
							v.Value = fish.pos
							v:SetAttribute("Species", fish.species)
							v:SetAttribute("State", fish.state)
						else
							v.Value = PARKED
							v:SetAttribute("State", "gone")
						end
					end
				end
			end)
		end
	end)

	print("[Abyssal] FishBinder mirroring")
end

return FishBinder
