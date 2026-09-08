# ABYSSAL — MVP Module Map

Source of truth: `/home/team/shared/gdd-mvp.md`. Tuning: `src/ReplicatedStorage/AbyssalShared/Config.luau`
(the only file gameplay numbers live in). Contracts (untouched, pre-existing):
`Config.luau`, `Remotes.luau`, shared `RodSystem.luau`, `default.project.json`.

## Modules → GDD

| Module | GDD | One-liner |
|---|---|---|
| Server `PlayerState` | §3 oxygen flavor, §7 pearls/bucket/rods, §10.4 telemetry | Per-player runtime data: rod ownership, pearls, stackable bucket, active cast + generation guard, oxygen tick + 20% slow helper, pearls/min metric |
| Server `FishAI` | §6 AI + bite rarity, Rustbelly tease | Procedural school sim per spot (patrol/approach/circle/scatter/gone); `RollSpecies` mirrors `BiteTable`; respawn 20 s; `GetFish` feeds the Lead Dev's model binder |
| Server `RodSystem` | §7 rods, §6 soft gating | Equip/ownership validation + `RodChanged`; purchase grant shared with Economy; snap odds stay in shared `RollSnap`, applied per-surge in the reel loop |
| Server `EconomyService` | §7 currency/prices, §8 shop screen | Sell values from `Config.Species` (10/30/80); `SellAll`/`SellOne`/`BuyRod`; emits `EconomyChanged` + `ShopState` snapshots |
| Server `FishingService` | §5 pipeline, §6 gating, §8 prompts | Cast→wait→hook→reel state machine; server-authoritative reel loop at `ServerTickHz`; win→`CatchResult`, lose→`LineFailed`; 1 Hz `SpotPrompt` polling |
| Server `SaveService` | §3 save, §10.6 best-effort | `AbyssalMVP_v1` DataStore + autosave with in-memory fallback; saves pearls/rods/bucket; failures warn, never block |
| Client `InputController` | §5 inputs | E (shop > hook > cast), R cancel, hold LMB/Space reel; shop tab senders `SellAll`/`SellOne`/`BuyRod` |
| Client `NetListener` | §8 UI binding | Callback registry over all 10 ServerToClient remotes; header documents every payload shape for the UI/UX designer |
| Client `SwimController` | §3 swim + oxygen slow | `GetTargetVelocity` (Base/Sprint/Vertical, `AccelLerp` smoothing, 20% empty-oxygen slow) + local oxygen mirror for the HUD bar |

## Public event API (contract: `Remotes.luau`)

Client→Server (intents, sent by `InputController`): `CastRequest {spotId}`,
`HookAttempt`, `CancelLine`, `ReelInput {holding}`, `ShopInteract`,
`ShopSellAll`, `ShopSellOne {species}`, `ShopBuyRod {rodId}`.
Server→Client (UI binds via `NetListener.On`): `SpotPrompt`,
`CastStarted`, `BitePrompt {expiresIn}`, `ReelState
{progress, tension, catcher, marker, surge}`, `CatchResult
{species, weight, value}`, `LineFailed {reason, message}`,
`EconomyChanged {pearls, bucket, bucketTotal}`, `RodChanged {rodId}`,
`ShopState {…sellLines, rods…}`. Coverage: every remote name is fired by at
least one server module and consumed (or sent) by at least one client module —
`ShopSellAll`/`ShopSellOne`/`ShopBuyRod` sends live in `InputController`
shop helpers; `FishAI` outcomes surface through `FishingService` remotes.

## Stubbed / left for the Lead Dev

1. **Character assembly** — swim rig/Humanoid states, animations, camera, water
   volume: `SwimController` is control logic only; wire `GetTargetVelocity`
   into your movement hook or keep its default binding.
2. **Map placement** — spot centers/vent offsets/NPC position are Config
   placeholders; place `OldMarrowNPCHint` (Vector3Value) in workspace for the
   real shop position (client falls back to the Grotto Dock pontoon).
3. **Visible fish/shadow models** — `FishAI.GetFish(spotId)` returns positions;
   bind models per Heartbeat (no assets ship in this tree).
4. **Real DataStore** — `SaveService` has a marked TODO: swap the
   pcall-wrapped access for versioned `UpdateAsync` + session lock.
5. **Visuals/audio** — bobber/ripple/"!"/surge/catch-card effects, FOV kick,
   slow-mo, sound cues: server fires the state remotes; presentation is Tech
   Art + UI/UX. Economy/gameplay needs no gamepasses (GDD §9 is post-MVP).

## Assumptions (flagged for lead)

- Reef fallback: `BiteTable.Reef` remainder resolves to Sunfin (matches "common
  fish only" water, GDD §4/§6).
- `RodSystem` (server) requires the shared pure-logic module of the same name
  rather than duplicating stat math.
- `InputController.PressE` fires `HookAttempt` before `CastRequest`; the server
  no-ops each outside its phase, so E stays single-key simple per GDD §5.
- Space is both swim-up and reel-hold; harmless because the server only reads
  `ReelInput` mid-fight.

## Map / Atmosphere (Tech Art — MVP)
What: underwater bowl + Grotto Dock spawn + 3 fishing spots + lighting/particles.
Where: `src/Workspace/Map.model.json` (terrain, bowl, dock, Old Marrow placeholder),
`src/Workspace/Spots.model.json` (all three spots), `src/Workspace/AtmosphereFX.rbxmx`
(all particle emitters, wrapped in one `AtmosphereFX` Folder), `src/Lighting/*.model.json`
(Atmosphere/Bloom/SunRays/ColorCorrection), `src/.../AbyssalClient/DepthVignette.client.luau`
(depth vignette + swim-bubble trail; NEW file, self-contained, safe to delete).
Config.Spots + GDD §4 mapping: Reef Gardens (0,-15,80) r18 — 6 neon corals + seaweed,
warm cyan PointLight, god-ray shafts (Reef only per GDD); The Rustwreck (70,-35,-40) r20 —
26-stud hull + bow/stern + mast + 5 translucent ribs, amber lamp, drifting motes;
Trench Edge (-70,-60,-50) r22 — trench walls + near-black maw + `ColdFogShell`,
14 bioluminescent BioDots, blue PointLight. Every spot: `SpotId`/`Center` values,
neon beacon pillar floor→surface + PointLight + SpotLight + 10-bulb ring + vent
glyph at the exact VentOffset (Reef (4,-14,76), Wreck (66,-34,-44), Trench (-66,-59,-46)).
Grotto Dock spawn at (0,-4.5,108): platform, pontoon, lanterns, `GrottoSpawn`
SpawnLocation; shop NPC placeholder "Old Marrow" at (5,-4,103) +
`OldMarrowNPCHint` Vector3Value (contracts §2 satisfied; client falls back to dock).
Budget: ~120 parts total (primitives only, no meshes/assets); 11 particle
emitters ≈ 174 particles/s worst case (3 vents 24/18/20 + 3 rings 10 + 3 zones 12 +
ambient 8 + trail 8); 9 lights total, all Shadows off. All anchored + CanCollide
false (swim-through), fog/light over geometry per GDD. Note: global Atmosphere is
a depth-gradient approximation; Trench "cold fog" is a local translucent shell
(`ColdFogShell`) since real zoned fog isn't possible.
Left for Lead Dev / final art: wire `SwimTrailTemplate` into character (path in its
`WireUp` value; vignette script handles it automatically), character rig + water
volume + audio, visible fish/shadow models via `FishAI.GetFish`, replace primitive
coral/hull/BioDots with final meshes, retune Atmosphere density after playtest,
add quality toggle (GDD §10.5).
- Space is both swim-up and reel-hold; harmless because the server only reads
  `ReelInput` mid-fight.
