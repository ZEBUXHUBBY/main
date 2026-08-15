# Anime Stars — Automation V2 + Authorized Diagnostic

Tools for **[ RELEASE ] Anime Stars** (`PlaceId 122553263569744`) using WindUI.

## Automation V2 loader

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AnimeStars/automation_v2.lua"))()
```

## Diagnostic loader

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AnimeStars/authorized_diagnostic.lua"))()
```

## Automation V2 features

- Event-driven Smart Farm state: `IDLE`, `FIGHTING`, `WAIT_RESPAWN`, `STALLED`, `STOP_TARGET`
- One shared incoming-event listener instead of multiple high-frequency polling loops
- Live efficiency HUD: DPS, kills/min, Power/min, respawns, ability executions, drops and pity
- Cooldown / lock / swapLock tracker from server-confirmed ability events
- Stall detection with configurable timeout
- Power, kill and time stop-condition alerts
- Drop notifications and banner pity/result tracking
- Opens the game's existing native Automation panel without invoking a remote or simulating a click
- JSON report export to `AnimeStarsAutomation/v2_report_<unix>.json` when executor file APIs exist

## Trust-boundary findings turned into safe features

The mapper findings are used as efficiency/observability guards rather than exploit actions:

- **Batch telemetry** — counts multi-action packets and maximum observed batch size
- **Guarded Scheduler** — cooldown/lock-aware state to prevent blind retry/spam logic
- **Unknown Path Watcher** — surfaces new event paths after game updates
- **Sensitive Surface Guard** — detects `conch_networking` and BetterTween request surfaces but excludes them from automation
- **Server-authority metrics** — favors server-confirmed `sync/update`, damage, death, respawn and ability execution events as state signals

## Why the V2 is time-efficient

The expensive work is event-driven. Incoming `Events.RemoteEvent` traffic is parsed once and fan-outs update combat, ability, farm, drop, pity and trust metrics in the same pass. Only the HUD/stall/target checks use a lightweight 0.25-second loop.

## Safety boundary

V2 intentionally does **not** call `FireServer`, `InvokeServer`, `firesignal`, `fireproximityprompt`, `conch_networking`, or unknown BetterTween request remotes. It does not bypass cooldowns, role checks, authorization, or modify economy values.

The separate authorized diagnostic remains available for passive surface discovery and report generation.