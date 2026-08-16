# AE Deep Mapper

Anime Expeditions research/data-capture layer rebuilt from the Universal Bug Mapper V4.1 idea.

## Goal

Build a client-visible digital twin of an Anime Expeditions session with as little guessing as possible. This project is the data/reverse layer only. Tournament optimization/autopilot should consume its exports later rather than embedding discovery logic inside the optimizer.

## Design rules

1. **Observed runtime > static config > inferred.** Every exported value carries a source/confidence tag.
2. **Passive-first.** Normal gameplay is captured before any active testing. No blind remote fuzzing.
3. **Domain-aware.** Decode Anime Expeditions replica classes instead of treating every table as an anonymous payload.
4. **Event-sourced.** Preserve Create/Set/SetValues/Write/Signal/Destroy order so a whole unit/enemy lifecycle can be reconstructed.
5. **Separate truth from hypotheses.** Facts and inferred relationships are exported separately.
6. **No optimizer logic here.** Mapper learns and exports; Tournament Brain ranks/actions later.

## What UBM V4.1 already gives us

- Remote inventory and signatures
- FireServer / InvokeServer capture
- Incoming RemoteEvent capture
- argument type/value/schema samples
- caller + line capture where available
- return capture
- transaction correlation
- state change attribution
- periodic/background classification
- argument-source linking
- ModuleScript knowledge index
- optional require-based config dump
- world snapshot
- interaction inventory
- model/report/API/state exports

## Major gaps to add for Anime Expeditions

### 1. Replica semantic decoder

Understand these as first-class entities:

- GameUnit
- GamePhantom
- GameSpawnedEnemy
- GameZone
- BuffData
- game/session replica
- player-game replica
- profile/inventory replica

Maintain a live replica registry keyed by ReplicaId and reconstruct each entity across ReplicaCreate, ReplicaSet, ReplicaSetValues, ReplicaWrite and ReplicaDestroy.

For GameUnit capture at minimum:

- owner / unit identity / GUID / asset
- level / trait / equipment / potential when exposed
- CFrame / placed time
- upgrade / max upgrade
- CurrentStats / NextStats
- damage / SPA / range / crit / DoT
- hitbox type / size / skill
- element
- target priority
- placement limit / placement count if visible
- SellValue / Unsellable
- IsFarm / Farm income
- buffs / disabled passives / tags
- attacking state
- TotalDamage / TotalKills / TotalTakedowns

For GameSpawnedEnemy capture at minimum:

- Name / Type / boss class
- health / max health / overhealth / shield if exposed
- speed and speed changes
- path target / target position / progress
- spawn/death timestamps
- attributes
- modifiers data
- mechanics
- debuffs/status effects
- elemental/resistance data if exposed
- rewards/kill income links if exposed

### 2. Client reverse/introspection layer (read-only)

Capability-detect executor APIs, never assume them:

- getgc
- getloadedmodules
- getconnections
- getsenv
- getscriptclosure
- debug.getinfo
- debug.getupvalue / getupvalues
- debug.getconstants / getconstants
- getproto / getprotos

Use them to build a searchable **client logic index**, not to mutate closures.

Export for every interesting function:

- source script
- debug name
- line range where available
- constants/string fingerprints
- upvalue type/shape summaries
- referenced Instances/remotes/modules
- inferred domain: unit, enemy, farm, wave, map, targeting, viewport, tournament, score, inventory, trait, equipment

This is especially useful for finding:

- UnitView / ViewportFrame renderer
- unit stat calculation
- targeting modes
- upgrade UI and costs
- placement validation/preview
- map/path functions
- enemy movement/path progress
- farm payout/wave payout
- tournament score/result display

### 3. UI -> callback -> network map

When getconnections is supported, index buttons and their connected callbacks.

For each important GUI control export:

`GUI path -> visible text -> callback function -> source script -> constants/upvalues -> outgoing action(s) -> resulting replica changes`

This should make UI reverse engineering evidence-based rather than searching PlayerGui structure only.

### 4. Module/config deep catalog

Keep the safe module-name index, but add an AE-specific catalog for likely data roots:

- Units / UnitStats / UnitLevel
- Passives / TraitPassives
- Equipment
- EnemyTypes / EnemyTags / EnemyModifiers / EnemyDrops
- Maps / Stages / Waves / Challenges
- Tournament configuration / scoring
- Economy / Wave income / kill rewards
- Elements / resistances

Optional require should remain manual/allowlisted because require() executes module code.

Export both raw table and normalized tables where possible.

### 5. Session / wave / economy ledger

Build a timeline rather than only proximity effects:

- time
- wave / intermission
- Yen before/after
- wave payout
- kill payout
- farm payout
- place cost
- upgrade cost
- sell refund
- unit action causing the change
- enemy killed/leaked

This lets a later optimizer calculate opportunity cost from observed data instead of asking the user for money values.

### 6. Combat ledger

Track per placed unit over time:

- effective CurrentStats
- attacks/skill events where visible
- target priority
- damage deltas
- kills/takedowns
- buff/debuff windows
- active zones/summons
- uptime / time-in-range evidence

The mapper should not call simple Damage/SPA the final DPS when passives, DoT, summons or cycles are involved. Export raw components and observed combat contribution separately.

### 7. Dynamic path reconstruction

Static Workspace waypoint discovery is only a fallback.

Primary evidence should come from enemy runtime movement:

- TargetPosition stream
- CFrame/position stream if replicated
- waypoint/index fields
- spawn -> base progression

Aggregate several enemies to reconstruct ordered lane geometry and lane branches. Then compare with Workspace nodes.

### 8. Tournament reverse layer

Capture one complete tournament lifecycle:

`join/config -> start -> waves -> score-relevant state changes -> finish -> result UI -> reward/rank`

Search client functions/modules/UI for strings such as:

- Score
- Tournament
- Ranking
- Damage
- Kills
- Takedowns
- Time
- Wave
- Clear
- Leak
- Multiplier

Do **not** claim a scoring formula until observed state/UI/client logic supports it.

### 9. Manual experiment markers

Add buttons such as:

- MARK: before placement
- MARK: after placement
- MARK: before upgrade
- MARK: after upgrade
- MARK: target changed
- MARK: farm payout
- MARK: wave start/end
- MARK: boss spawned/killed
- MARK: leak
- MARK: tournament result

This makes correlation much cleaner than guessing from a fixed 1.5 second window.

### 10. Export layout

Each session should save:

```
AE_DeepMapper/session_<timestamp>/
  manifest.json
  remotes.json
  replicas.json
  replica_events.jsonl
  units_runtime.json
  enemies_runtime.json
  economy_ledger.jsonl
  combat_ledger.jsonl
  map_runtime.json
  ui_callbacks.json
  client_logic_index.json
  modules_index.json
  module_dumps/
  tournament.json
  unresolved.json
  report.txt
```

The later Tournament Brain should read these exports / normalized DB instead of rediscovering the game every scan.

## Development order

**Phase A — Deep passive capture**
1. modularize UBM baseline
2. AE replica registry + decoder
3. high-fidelity table serialization for selected domains
4. manual markers
5. economy + combat event ledgers

**Phase B — Read-only client reverse**
6. executor capability detection
7. loaded module + GC function index
8. function constants/upvalues/source fingerprints
9. UI callback mapping

**Phase C — Semantic reconstruction**
10. dynamic map/path model
11. unit lifecycle model
12. enemy lifecycle/mechanic model
13. tournament lifecycle/result model

**Phase D — DB build**
14. merge runtime facts into AE_DB with provenance
15. flag conflicts instead of silently overwriting
16. generate a compact truth API for Tournament Brain

## Baseline provenance

The starting reference is the user-provided `Universal Bug Mapper V4.1` source. It is ~4k lines and already states that its findings are hypotheses from client-visible behavior and that it does not actively fuzz/mutate requests. We preserve that passive-first boundary in AE Deep Mapper.
