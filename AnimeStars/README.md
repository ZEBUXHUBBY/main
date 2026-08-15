# Anime Stars Tools

Tools for **[ RELEASE ] Anime Stars** (`PlaceId 122553263569744`) using WindUI.

## Game Profiler V1 — use this next

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AnimeStars/game_profiler.lua?v=1"))()
```

The profiler is a passive-first learning logger. It records the game's normal shared event-bus traffic and runtime state so later automation can be based on observed behavior instead of guessed rules.

### What it records

- Normal outgoing `Events.RemoteEvent:FireServer(...)` calls when the executor exposes hook APIs
- Incoming event paths and parameters
- Raw Power sync, DamageDealt, enemy damage/death/respawn
- Ability cooldown, lock, swapLock and executed events
- Drops, rewards, summon results and pity updates
- Live monster UUID ↔ spawner mapping, zone, position and player distance
- Manual action labels with BEFORE / AFTER snapshots
- Auto-classified kill sequences
- Session timeline and capabilities

### Learning pass

Start the profiler, then play normally and mark the matching label immediately before each action:

1. M1 Attack — do several normal attacks on one monster
2. Skill — use a normal skill once or twice
3. Ultimate — use the ultimate normally
4. Kill Monster — kill 2–3 different monster types
5. Teleport Zone — move to another zone normally
6. Buy Upgrade — buy one normal upgrade
7. Quest — accept/complete or interact with one quest
8. Summon — perform one normal summon
9. Optional custom labels for equipment, passive, mount, dungeon, etc.

When finished, press **Export / Copy JSON**. If executor file APIs are available the report is saved as:

```text
AnimeStarsProfiler/session_<unix>.json
```

Send that JSON back for analysis. The next step is to generate `monsters.json`, `combat.json`, `abilities.json`, `zones.json`, `protocols.json` and efficiency benchmarks from the observed session.

## Aggressive Farm V3.1

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AnimeStars/aggressive_farm_v3.lua?v=31"))()
```

Current V3.1 uses UUID↔spawner target detection, nearest-monster hopping, respawn pre-positioning, noclip, target facing and executor-input M1 fallback. It is intentionally rule-based; the profiler exists to replace these rough rules with measured target/range/rotation/efficiency decisions.

## Automation V2

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AnimeStars/automation_v2.lua"))()
```

Event-driven telemetry, cooldown/lock tracking, efficiency HUD, stall detection, stop conditions, drops and pity tracking.

## Authorized Diagnostic

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AnimeStars/authorized_diagnostic.lua"))()
```

Read-only trust-boundary and event-surface diagnostics.

## Boundary

The profiler observes normal traffic but does not send its own server actions. The toolset does not invoke `conch_networking` admin/role remotes, unknown BetterTween request protocols, reward spoofing or duplication logic.