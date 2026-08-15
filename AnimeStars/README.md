# Anime Stars — Authorized Diagnostic

Read-only WindUI diagnostic for **[ RELEASE ] Anime Stars** (`PlaceId 122553263569744`).

## Loader

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AnimeStars/authorized_diagnostic.lua"))()
```

## What it automates

- Periodic local-state snapshots (Power, attributes, health, WalkSpeed, position)
- Passive `Events.RemoteEvent.OnClientEvent` Path counters
- Read-only scan of replicated remote/trust-boundary surfaces
- Detection of the game's built-in automation components
- JSON report copy/save for later comparison

## Safety boundary

The diagnostic intentionally does **not** call `FireServer`, `InvokeServer`, hidden/admin remotes, proximity prompts, or GUI signals. It does not fuzz payloads, bypass cooldowns, automate combat, or modify economy state.

## Current review priorities

These are hypotheses, not confirmed vulnerabilities:

1. **Event-bus batch validation — MEDIUM**  
   The captured event bus used both one-action and two-action arrays. Review whether the server validates and rate-accounts every item independently.

2. **Client hero / attack-sequence parameters — MEDIUM**  
   The observed `combat/m1` request includes a hero identifier and attack index. The server should derive or strictly validate equipped hero and combo state.

3. **`conch_networking` command / role remotes — HIGH-PRIORITY REVIEW**  
   Replicated command, create-user, role and permission remotes are visible. Presence alone is not a bug; server handlers must authenticate and authorize every operation with deny-by-default behavior.

4. **Rate-limit / concurrency policy — REVIEW**  
   The mapper observed a `0.032s` minimum accepted gap, but the game also contains built-in `AutomaticAttackController` / `AutomationController` functionality. Fast traffic may therefore be legitimate. Verify cooldown policy server-side in an explicitly authorized environment instead of remote-spamming.

5. **BetterTween request remotes — LOW / UNEXPLORED**  
   `_requestReliable` and `_requestUnreliable` exist but were not observed in normal play. First identify and exercise the legitimate feature that uses them, then capture the real signature before deeper review.

6. **Server-authoritative Power / damage — REVIEW**  
   Keep damage, rewards and Power calculations server-authoritative. The captured outgoing combat request did not directly submit a Power amount, which is a positive signal but not proof of complete validation.

## Report output

With executor file APIs available, **Save JSON report** writes:

```text
AnimeStarsDiagnostic/report_<unix>.json
```

The report contains surface presence, findings, sampled local state and passive incoming Path counts. It does not replay captured payloads.
