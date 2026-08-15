# AE Tournament Autopilot

Clean standalone project for a future Tournament Autopilot. It does **not** load `AE_Strategist` or `AE_Assistant`.

## Current milestone — M1 Tournament Brain

M1 is a read-only, one-shot advisor. Nothing polls or analyzes in the background.

It produces one standard decision model:

```text
Tournament context
+ owned unit copies
+ Level / Trait / Equipment / Potential evidence
+ unit upgrade stats
+ route geometry
+ Farm income
=> recommended six
=> target priority per unit
=> target upgrade per unit
=> Sweet Spots A/B/C
=> Farm / no-Farm decision
=> action queue
```

### Target priority modes

The engine scores and recommends the game's available modes:

- First
- Last
- Closest
- Strongest
- Boss
- Weakest
- Shielded
- Fastest

`None` is not recommended until its exact in-game meaning is confirmed.

### UI direction

The M1 UI is a cartoony-minimal tactical overlay with three surfaces:

- **PLAN** — best six, target mode, target upgrade, Farm decision, initial queue
- **PLAY** — one-shot manual refresh of route/modifiers/current Yen
- **REVIEW** — placeholder for the run-learning milestone

The center is a top-view route, not a text dashboard. It shows per-unit Sweet Spots:

- **A** — opener
- **B** — sustained damage
- **C** — catch / sell-and-reposition

Game visuals are resolved in this order:

1. live unit icon / viewport already rendered by the game
2. model under `ReplicatedStorage.Assets.Units`
3. text fallback only when neither is exposed

Trait and equipment image IDs come from the game's own data when available.

## Reliability boundaries

M1 does not claim an exact Tournament leaderboard score formula. Until that formula is verified, the objective is marked `WAVE_REACH_PROXY` and ranks survival, sustained damage, anti-leak coverage, modifier fit, and economy efficiency.

Level and Stat Potential are applied only when the client exposes explicit modifier fields. Ambiguous roll fields are displayed but not guessed.

Farm is recommended only when exact per-wave `Income` fields are available. Otherwise the UI reports `UNKNOWN` rather than inventing ROI.

## Roadmap

### M2 — Geometry + reposition

- exact path discovery per map
- Circle / Cone / Line exposure models
- current placed-unit detection
- enemy progress and leak line
- sell refund and relocation comparison
- `KEEP` vs `SELL + MOVE A→C`

### M3 — Live action planner

- compare Place / Upgrade / Save / Farm / Sell / Reposition / Target / Ability
- marginal Tournament value per Yen
- target changes while threats change
- target upgrade for every placed unit

### M4 — Run learner

- record score, wave, damage, leaks, economy and decisions
- infer the verified Tournament criteria from repeated runs
- controlled experiments such as Farm U1 vs U2 or First vs Fastest target schedules

### M5 — Assisted execution

- explicit confirmation before each action
- no autonomous execution yet

### M6 — Autopilot

- execute the highest expected-score action
- continuously re-plan from live state
- learn from every completed run

## Loader

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Tournament_Autopilot/start.lua"))()
```
