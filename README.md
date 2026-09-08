# Abyssal Studios — Roblox Fishing MVP

Underwater fishing-and-exploration experience for Roblox (working title per GDD). This is the studio's source repo: gameplay systems, map/atmosphere, UI, and the approved design docs.

## Layout

- `docs/` — design. `gdd-mvp.md` is the ratified source of truth (v1.0, owner-approved 2026-09-08).
- `abyssal/` — Rojo project. Build the place with:
  ```sh
  export PATH=/home/team/shared/bin:$PATH
  cd abyssal && rojo build -o ../build/abyssal.rbxlx
  ```

## Workflow

Follow `/home/team/shared/WORKFLOW.md` — feature-branch + PR model, one writer at a time, review-and-merge by the lead.

## Status (2026-09-08)

- Gameplay systems: complete (fishing pipeline, reel minigame, fish AI, economy, save)
- Map + atmosphere: complete (3 spots, fog, VFX — verified `rojo build`)
- Starter UI: in build
- Lead Dev integration: queued