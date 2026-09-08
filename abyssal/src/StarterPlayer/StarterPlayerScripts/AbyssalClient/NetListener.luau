--!strict
-- Abyssal — NetListener (client).
-- Subscribes to every ServerToClient remote and routes payloads to a simple
-- callback registry. The UI/UX designer binds screens here:
--   NetListener.On(Remotes.CatchResult, function(payload) ... end)
-- Returns an unsubscribe function. Every payload shape is documented below
-- (mirrors Remotes.luau) so UI can be built without reading server code.
--
-- Payload shapes:
--   SpotPrompt:      { inSpot: boolean, spotId: string? }
--   CastStarted:     { spotId: string }
--   BitePrompt:      { expiresIn: number } (HookWindow, 1.2 s ring)
--   ReelState:       { progress: number (0-100), tension: number (0-100),
--                      catcher: number (0-1), marker: number (0-1),
--                      surge: boolean } (~10 Hz)
--   CatchResult:     { species: string, weight: number (flavor kg),
--                      value: number (Pearls) }
--   LineFailed:      { reason: "escape"|"tension"|"snap"|"cancel"|"bucket_full",
--                      message: string }
--   EconomyChanged:  { pearls: number, bucket: { [species]: count },
--                      bucketTotal: number }
--   RodChanged:      { rodId: string }
--   ShopState:       { pearls: number, bucket: { [species]: count },
--                      bucketTotal: number, bucketValue: number,
--                      sellLines: { { species, count, unitValue } },
--                      rods: { { rodId, name, cost, owned, equipped } } }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("AbyssalShared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local NetListener = {}
NetListener._callbacks: { [string]: { (any) -> () } } = {}
NetListener._connected: { [string]: boolean } = {}

local function ensureConnected(remoteName: string)
	if NetListener._connected[remoteName] then
		return
	end
	NetListener._connected[remoteName] = true
	local event = ReplicatedStorage:WaitForChild(remoteName) :: RemoteEvent
	event.OnClientEvent:Connect(function(payload: any)
		local list = NetListener._callbacks[remoteName]
		if list then
			for _, fn in list do
				task.spawn(fn, payload)
			end
		end
	end)
end

-- Subscribe. Returns an unsubscribe closure.
function NetListener.On(remoteName: string, fn: (any) -> ()): () -> ()
	ensureConnected(remoteName)
	local list = NetListener._callbacks[remoteName]
	if not list then
		list = {}
		NetListener._callbacks[remoteName] = list
	end
	table.insert(list, fn)
	return function()
		local live = NetListener._callbacks[remoteName]
		if live then
			local idx = table.find(live, fn)
			if idx then
				table.remove(live, idx)
			end
		end
	end
end

-- Convenience: subscribe to all ten ServerToClient remotes at once.
function NetListener.Init()
	for _, remoteName in
		{
			Remotes.SpotPrompt,
			Remotes.CastStarted,
			Remotes.BitePrompt,
			Remotes.ReelState,
			Remotes.CatchResult,
			Remotes.LineFailed,
			Remotes.EconomyChanged,
			Remotes.RodChanged,
			Remotes.ShopState,
		} :: { string }
	do
		ensureConnected(remoteName)
	end
end

return NetListener
