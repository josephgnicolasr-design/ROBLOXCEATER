# ABYSSAL — MVP Vertical Slice GDD
**Studio:** Abyssal Studios | **Version:** 1.0 (2026-09-08) | **Scope:** 15-minute vertical slice. Single source of truth for scripter, UI/UX, tech artist, lead dev.

## 1. Vision & Player Fantasy
You are a freediver in a glowing sunken cove where every shadow could hide something valuable. Swim out, read the water, hook something that fights back, and cash in to earn a rod that reaches deeper, darker, richer water. The fantasy: *ten more minutes and one more cast turns into a monster catch.*

## 2. Core Loop + Retention Hook
**Loop (text diagram):**
```
SPAWN (Grotto dock, Twig Rod) → SWIM to glowing fishing spot → CAST (bobber lands, ripple ring)
→ WAIT (bite timer, ambient tension) → ! BITE → HOOK (timed press) → REEL minigame (win/lose)
→ CATCH toast + fish to Bucket → repeat 2–4x → SWIM to shop → SELL → BUY better rod
→ previously "too strong" fish/spot becomes catchable → chase next tier
```
**Why one more cast feels good:** (a) variable-ratio bite timing (never exactly predictable), (b) near-miss design — rare fish visibly tease the bobber (shadow circles it) even when you fail, (c) every session ends one upgrade away: price curve guarantees the player can afford Rod 2 after ~8–10 min of decent play, so quitting feels like leaving money on the table.

## 3. MVP Scope Checklist
**IN:** 3rd-person swim movement (WASD + Space up / C or Ctrl down, Shift sprint); 1 small map with 3 marked fishing spots; cast/wait/reel catch flow; 3 fish species with simple AI; 1 shop NPC (sell + 3 rod tiers); Bucket inventory (max 12 fish); starter HUD + shop + catch UI; flavor oxygen bar (drains over ~3 min, refills at surface/breath vents — never kills in MVP, only slows swim 20% at empty); save via DataStore (currency, rod, bucket) — best effort.
**OUT:** diving gear/suits, day/night cycle, weather, multiplayer boats/trading, PvP, pets, quests/story, crafting/bait crafting, achievements, gamepasses/DevProducts, mobile-specific controls (keyboard+mouse first, touch = stretch), voice chat, procedural map, more than 3 rods/species/spots.

## 4. Map Design
Small bowl, ~240×240 studs, bounded by rock walls + fog. Spawn: **Grotto Dock** (shallow, bright, shop NPC "Old Marrow" on a pontoon). Three spots in a triangle ~60–90 studs apart, each marked by a light beam + bubble ring visible from anywhere:
1. **Reef Gardens** (shallow, ~15 studs deep): bright coral, warm cyan light, dense cover. Safe tutorial water. Common fish only.
2. **The Rustwreck** (mid, ~35 studs): a broken trawler hull on its side, silhouetted ribs, drifting particles. Mid-tier fish patrol the hull.
3. **Trench Edge** (deep, ~60 studs): dark drop-off, cold blue fog, bioluminescent dots. Rare fish; visibly ominous from a distance.
**Atmosphere notes (tech artist):** depth-graded fog (cyan → deep blue → near-black), god-rays only at Reef, floating particulate, spot beams as beacons, breath-vent bubble columns (oxygen refill) at each spot, swim bubble trail + depth vignette. Target 60 FPS on mid devices — particles + lighting over geometry.

## 5. Fishing Mechanic Spec
**Inputs (PC):** E = cast / hook / confirm; hold LMB or Space = reel (during minigame); R = cancel line; E at shop = trade. Cast only works inside a spot ring (prompt: "Press E to cast").
**Flow & numbers:** (1) **Cast:** 0.6 s anim, bobber lands ≤12 studs ahead + ripple VFX. (2) **Wait:** bite timer per species (§6) × rod multiplier (§7); bobber bobs, line tenses, audio tick. (3) **Hook:** red "!" + splash; **1.2 s window** to press E (miss = escape, 2 s cooldown, no penalty). (4) **Reel minigame:** hold to raise a catcher bar, release to drop; keep it on the oscillating fish marker to fill Progress; drains off-target. Win at 100%; lose if Tension maxes by holding during a red-flash "surge" (release!). Fights run ~6–12 s.
**Feel targets:** every state has a distinct sound + camera punch (bite = FOV kick 0.15 s); bobber vibrates with tension; catch = 0.4 s slow-mo + splash + species card with value. Fails must feel like "almost" ("It slipped away… something big circles below").

## 6. Fish Species (first-pass balance; scripter tunes ±30%)
AI (all): spawn 4–6 per spot, despawn/respawn 20 s; patrol waypoints at 4–8 studs/s; on cast, nearest 1–2 approach bobber (visible shadows); bite roll per Table; on hook-fail, scatter 5 s. All sellable, stackable in Bucket.

| # | Species / look | Home spot | Behavior | Bite time | Reel difficulty (osc. speed / surges) | Rarity | Sell |
|---|---|---|---|---|---|---|---|
| 1 | **Sunfin** — palm-size, yellow/blue damsel, forked tail | Reef Gardens | Bold, bites fast, weak fight | 3–6 s | slow (0.8 Hz), 0–1 surges | 65% of Reef bites | 10 P |
| 2 | **Rustbelly** — fat green catfish, whiskers, scrap-metal flank | Rustwreck | Shy: circles bobber 2–3 s before biting; medium fight | 6–11 s | med (1.3 Hz), 1–2 surges | 55% of Wreck bites (else Sunfin) | 30 P |
| 3 | **Lanternjaw** — black anglerfish, glowing lure, big teeth | Trench Edge | Aggressive but strong: bites mid; hard fight, frequent surges | 5–9 s | fast (1.9 Hz), 2–4 surges | 40% of Trench bites (else Rustbelly) | 80 P |

**Rod gating:** Twig Rod can catch all species (no hard lock — never frustrate MVP testers) but Lanternjaw escapes 50% mid-reel on Twig (line-strength check: surge during red flash snaps Twig line); Coral Rod = normal rates; Abyss Rod = bite times ×0.7 and no snap. This makes upgrades *felt* in the fight, not a menu stat.

## 7. Economy & Progression
**Currency:** Pearls (P). Sources: selling fish only (no pickups in MVP). Bucket cap 12 forces sell trips.
**Price curve (15-min session):** Reef farming ≈ 90–120 P per full bucket (~4 min) → Coral Rod at 250 P reachable ~minute 8–10 → Wreck/reef mix ≈ 200 P per trip → Abyss Rod 800 P by ~minute 15–18 for good players (testers may not reach it — fine; it's the "one more session" tease).

| Rod | Cost | Bite-speed mult. | Line strength | Feel |
|---|---|---|---|---|
| Twig Rod (start) | — | ×1.0 | Weak: 50% snap on Lanternjaw surges | bendy, slow |
| Coral Rod | 250 P | ×0.8 bite time | Sturdy: no snap vs Rustbelly, 15% vs Lanternjaw | snappier cast |
| Abyss Rod | 800 P | ×0.7 bite time | Deep-line: no snap anywhere, +10% reel progress rate | glowing tip, taut sound |

## 8. UI Requirements (for UI/UX designer)
1. **HUD (always on):** Pearls count (+fly-up "+30" on sale), rod icon + name, Bucket 12-slot mini-strip, depth meter, flavor oxygen bar, spot prompt ("Press E to cast" / "Not a fishing spot"), sprint hint. Minimize clutter; big readable numbers.
2. **Bite/Reel overlay:** center "!" flash + 1.2 s ring timer; reel meter (catcher bar, fish marker, progress %, tension bar flashing red on surge). Must be readable in 0.3 s — high contrast, no small text.
3. **Catch card (toast, 2.2 s):** species art silhouette, name, weight (flavor random ±20%), sell value, "rare!" styling for Lanternjaw. Skippable with E.
4. **Bucket/inventory (hold Tab):** 12 slots with species icons + counts, total sale value preview, "Bucket full — visit Old Marrow" state.
5. **Shop screen (E at NPC):** two tabs — Sell (one-click "Sell All" + per-fish sell, running total) and Rods (3 cards: art, stats as bars not numbers, cost, owned/equipped state, buy confirm). Esc/E closes; game pauses line timers while open.
**Flow:** spawn → control hint card (dismissible, 8 s) → HUD → cast → reel overlay → catch card → bucket → shop → rod card updates HUD icon. All UI must work at 1280×720 minimum, controller-agnostic text ("Press E", not icons alone).

## 9. Monetization Hooks — POST-MVP APPENDIX (do NOT build)
Gamepasses: Fast Line (bite ×0.8), Lucky Lure (rare chance +10%), Extra Bucket (+12 slots), Deep Lungs (no slow at empty oxygen). DevProducts: Pearl pouches (100/550/1500), limited event rods. Cosmetics: bobber/trail skins, dive suits. Never sell direct power that skips the 15-min learning arc; test price points after retention ≥ D1 20%.

## 10. Risks & Open Questions
1. **Reel minigame difficulty** — biggest fun/fail risk; needs playtest within days (is 1.9 Hz too hard on trackpads?). Open: fallback "simple tap timing" mode if fail rate >40%.
2. **Swim feel** — underwater movement easily feels floaty/bad; needs tuned accel/damping + FOV-by-speed before any content work.
3. **Spot readability** — players must find spots without a minimap (MVP has none); light beams + vents must be visible from spawn. Open: add compass arrows if testers get lost.
4. **Economy pacing** — numbers above are guesses; scripter should log P/min and time-to-Coral-Rod in playtests; tune price, not fish values, first.
5. **Performance on low-end** — fog + particles can tank mobile-class GPUs; tech artist to set a particle budget early. Open: quality toggle in MVP? (Lean: yes, simple Low/High.)
6. **DataStore failure** — save best-effort; game must play fully without it (session-only fallback, warn don't block).
