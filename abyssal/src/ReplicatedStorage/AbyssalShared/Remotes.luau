-- Abyssal — RemoteEvent name + payload contract.
-- The UI/UX designer binds screens to these; the Lead Dev may replace the
-- folder with Knit services as long as names/payloads stay identical.
-- Convention: ClientToServer = player intent; ServerToClient = state for HUD.

local Remotes = {
	-- Client -> Server (player intent)
	CastRequest = "Abyss_CastRequest", -- payload: { spotId: string }
	HookAttempt = "Abyss_HookAttempt", -- payload: none
	CancelLine = "Abyss_CancelLine", -- payload: none (R key)
	ReelInput = "Abyss_ReelInput", -- payload: { holding: boolean } (hold LMB/Space)
	ShopInteract = "Abyss_ShopInteract", -- payload: none (E near Old Marrow)
	ShopSellAll = "Abyss_ShopSellAll", -- payload: none
	ShopSellOne = "Abyss_ShopSellOne", -- payload: { species: string }
	ShopBuyRod = "Abyss_ShopBuyRod", -- payload: { rodId: string }

	-- Server -> Client (UI binds here)
	SpotPrompt = "Abyss_SpotPrompt", -- { inSpot: boolean, spotId: string? } HUD cast prompt
	CastStarted = "Abyss_CastStarted", -- { spotId: string } bobber/ripple cue
	BitePrompt = "Abyss_BitePrompt", -- { expiresIn: number } red "!" + 1.2 s ring
	ReelState = "Abyss_ReelState", -- { progress, tension, catcher, marker, surge } 10 Hz
	CatchResult = "Abyss_CatchResult", -- { species, weight, value } catch card 2.2 s
	LineFailed = "Abyss_LineFailed", -- { reason: "escape"|"tension"|"snap"|"cancel"|"bucket_full", message }
	EconomyChanged = "Abyss_EconomyChanged", -- { pearls, bucket: {species: count}, bucketTotal }
	RodChanged = "Abyss_RodChanged", -- { rodId: string } HUD rod icon update
	ShopState = "Abyss_ShopState", -- full sell/buy snapshot for the shop screen
}

return Remotes
