# AE Deep Mapper — Knowledge Baseline

This file is the persistent evidence ledger for the clean rebuild. Tournament optimization must use VERIFIED/OBSERVED facts from here or from exported datasets; unknown mechanics stay UNKNOWN until tested.

## Goal
Build a digital twin capable of evaluating Unit × owned copy × level × potential × trait × equipment × upgrade × placement × target mode × buffs/debuffs/CC × enemy × map/path × economy × sell/reposition timing against the exact Tournament objective.

Pipeline: Deep Mapper → Knowledge DB → Simulator → Tournament Optimizer → Live Assist → optional Autopilot.

## Evidence policy
Every derived rule carries provenance and confidence: VERIFIED = direct structured data plus repeatable observation; HIGH = multiple consistent observations; HYPOTHESIS = client-code inference not yet validated; UNKNOWN = not established. The optimizer must never silently replace UNKNOWN with a heuristic and present it as fact.

---

## VERIFIED: client capabilities
The current executor exposes getgc, getconstants, getloadedmodules, getproto/getprotos, getscriptclosure, getsenv, getconnections, getupvalues/debug.getupvalue, debug.getinfo, hookmetamethod, getnamecallmethod, checkcaller, newcclosure, writefile and makefolder.

## VERIFIED: authoritative client data location
Research on 2026-08-16 found that gameplay data relevant to the optimizer is populated under `ReplicatedStorage.Shared.Information.*`. Many corresponding `ReplicatedStorage.SheetSyncedModules.*` data modules return empty tables client-side, although scaling/template modules can still contain usable data. New code must prefer `Shared.Information` for Units, Traits, Equipment, UnitLevelInfo, StatPotential and Tournaments unless a specific SheetSynced scaling module is intentionally requested.

Many methods in these information modules are colon-style (`Module:Method(...)`) and should not be invoked as dot-style functions unless their signature has been independently verified.

## VERIFIED: high-value game modules discovered
### Stat / owned-copy calculation
- ReplicatedStorage.FusionPackage.Actions.GetCalculatedStatsFromData
- ReplicatedStorage.Shared.UnitUtils.StatUtils
- ReplicatedStorage.FusionPackage.Components.Processors.Asset.UnitStats
- ReplicatedStorage.FusionPackage.Components.Processors.Asset.UnitPassives
- ReplicatedStorage.FusionPackage.Components.Processors.Asset.UnitTotalCost
- ReplicatedStorage.Shared.Information.UnitLevelInfo
- ReplicatedStorage.Shared.Information.StatPotential
- ReplicatedStorage.Shared.Information.StatPotential.Stats

### Traits / equipment / passives
- ReplicatedStorage.FusionPackage.Actions.GetEquipmentData
- ReplicatedStorage.Shared.Information.Equipment
- ReplicatedStorage.Shared.Information.AssetTypes.Equipment.Info
- ReplicatedStorage.Shared.Information.Traits
- ReplicatedStorage.Shared.Information.Passives
- ReplicatedStorage.Shared.Information.Passives.TraitPassives
- ReplicatedStorage.FusionPackage.Components.Menu.UnitInventory.StatLabel.EquipmentMultiplier
- ReplicatedStorage.FusionPackage.Components.Processors.Asset.Equipment
- ReplicatedStorage.FusionPackage.Components.Processors.Asset.AssetEquipData

### Combat / targeting / geometry
- ReplicatedStorage.Shared.UnitUtils.HitboxFunctions
- ReplicatedStorage.Shared.UnitUtils.TargetingFunctions
- ReplicatedStorage.FusionPackage.Actions.GetAllowedUnitTargeting
- Players.<player>.PlayerScripts.ClientUnitTargeting
- Players.<player>.PlayerScripts.ClientUnitAttack
- Players.<player>.PlayerScripts.ClientUnitDPS
- ReplicatedStorage.FusionPackage.Components.Game.RangeIndicator.GameUnit
- ReplicatedStorage.FusionPackage.Components.Game.HitboxIndicator.GameUnit

### Tournament
- ReplicatedStorage.Shared.Information.Tournaments
- ReplicatedStorage.FusionPackage.Components.Menu.Tournament.ScoreTypeInfo
- ReplicatedStorage.FusionPackage.Components.Menu.Tournament
- ReplicatedStorage.FusionPackage.Components.Menu.Tournament.Leaderboard
- ReplicatedStorage.FusionPackage.Components.Menu.Tournament.StatLabel
- ReplicatedStorage.FusionPackage.Components.Menu.Tournament.GlobalTournament
- ReplicatedStorage.FusionPackage.Components.Menu.Tournament.EntryPage

### AutoPlay / pathing
- ReplicatedStorage.Shared.Information.AutoPlayUtils

### Status / CC relevant to combo optimization
Discovered information modules include Slow, Rewind, ShadowRewind, Freeze, Stun, Knockback, Illusion, Bleed, Poison, Fire, BountyMark and other status effects. Their exact formulas/stacking rules are NOT yet considered verified.

---

## VERIFIED: Tournament configuration and score types
`Shared.Information.Tournaments` exposes score-type sets rather than one permanent universal objective.

Known configurations from the 2026-08-16 dump:
- Solo: `ScoreTypes = {TotalDamage, TotalKills}`, PlayerCount=1, ModifierCount=2, ExtraModifiers includes None and Traitless, Duration=604800 seconds.
- Duo: `ScoreTypes = {TotalDamage, TotalKills}`, PlayerCount=2, ModifierCount=2, SeedOffset=123456789.
- Infinite_1..5: `ScoreTypes = {WavesCleared}`, PlayerCount=4 and global-tournament configuration.
- TowerOfGod: `ScoreTypes = {FloorsReached}`, PlayerCount=1.
- Release: `ScoreTypes = {TotalDamage}`.

`Tournament.ScoreTypeInfo` maps score IDs to UI names/descriptions:
- TotalDamage → `Damage Dealt` → dealing damage to enemies.
- TotalKills → `Enemy Kills` → defeating enemies.
- WavesCleared → `Waves Cleared`.
- FloorsReached → `Floors Reached`.

IMPORTANT: the active Solo/Duo score criterion must be read from live tournament state/UI/server-derived state. A simple `week % #ScoreTypes` rotation was tested in the imported research and contradicted the live UI. Do not predict the active criterion using that formula.

The imported 2026-08-16 session reported the active Solo scoring condition as `Damage Dealt / TotalDamage`. Treat this as session-specific evidence, not a permanent rule.

Useful callable functions observed in `Shared.Information.Tournaments` include:
- `GetBracketSeed`
- `GetModifierValue_UpgradeCap`
- `GetModifierValue_Resistance`
- `GetBracketDisplayName`
- `ComputeModifiers`
- `ComputeResistances`
- `GetTournamentModule`

`ComputeModifiers` constants reveal tournament mechanics including `Resistance`, `UpgradeCap`, `Speedy`, `BossWaves`, `ShortRange`, `NoFarms`, `Traitless` and modifier filtering. Exact generated values for a live bracket still need robust extraction.

---

## VERIFIED: Level damage scaling
Imported probe results identify `UnitLevelInfo.LevelInfo[lv].DamageMulti` and report the damage multiplier as:

`DamageMulti = 1.0123 ^ (level - 1)` with MaxLevel=50.

Observed checkpoints include approximately 1.1163 at level 10, 1.3410 at 25, 1.4255 at 30 and 1.8203 at level 50. The research reports Level affecting Damage, not SPA or Range. This formula should still be cross-checked against `GetCalculatedStatsFromData` before being treated as the final operation order with trait/equipment/buffs.

## VERIFIED: StatPotential interpolation
Owned units store potential per stat as `{Potential=<grade>, Range=<0..1 roll position>}`.

`StatPotential:GetStatValue(stat, grade, roll)` was probed and matches linear interpolation inside the grade's percentage band:

`valuePercent = minPercent + roll * (maxPercent - minPercent)`.

Example from the probe: Damage / Z / 0.37 → 17.5 + 0.37*(20-17.5) = 18.425%, and the game function returned about 18.4.

Known Z ranges:
- Damage +17.5% to +20%
- Range +12.5% to +15%
- SPA -12.5% to -15% (negative is beneficial)

The imported research also dumped grades SSS through F. Preserve the complete table in source exports; the mapper should dump it directly rather than hardcode it.

---

## VERIFIED: Trait data format and known traits
`Shared.Information.Traits.TraitData` contains trait modifiers expressed as fractional multipliers (e.g. 0.35 = +35%), unlike StatPotential values which are percentages.

Known imported values include:
- Primordial: Damage +35%, SPA -15%, Range +20%.
- Draconic: Damage +20%, DoTDamage +50%, Cost -10%.
- Forsaken: CritChance +35%, CritDamage +35%, Range +10%.
- Bolt: SPA -15%.
- Limit Breaker: Damage +15%.
- Optics: Range +25%.
- Investor: Farm +25%.
- Precision 2: CritChance +20%, CritDamage +10%.
- Precision 1: CritChance +10%, CritDamage +5%.
- Enlightenment: ExpIncrease +50%.
- Range 2: Range +10%.
- Speed 2: SPA -10%.
- Range 1: Range +5%.
- Speed 1: SPA -5%.

Strength 1, Strength 2 and Unbound still need their exact trait-table dump. Runtime owned-unit data confirms `Unbound` exists and is equipable.

---

## VERIFIED: equipment schema; owned-roll extraction still incomplete
`Shared.Information.AssetTypes.Equipment.Info` exposes equipment definitions and roll ranges. Examples from imported research:
- Bottle can roll Range with a configured min/max range.
- MegumiEquipment can roll Damage and Range.
- Equipment subtype can be Standard or Unit-specific.

The tournament discovery runtime also revealed that placed-unit `GameData.EquipmentData` contains per-equipped-item structures with `Asset`, `Stats`, optional `Passives`, `RerollAmount` and `Equipped`. In the current export, individual `Stats[].Value` fields were truncated by mapper depth. This is a strong path to obtaining the ACTUAL rolled equipment values and should be the next equipment probe target.

Do not confuse equipment definition min/max roll bands with the actual roll on the user's owned GUID item.

---

## VERIFIED: runtime GameUnit data
Replica/Fusion runtime state exposes calculated CurrentStats and NextStats. Observed fields include:
- Damage
- SPA
- Range
- CritChance
- CritDamage
- HitboxType
- HitboxSize
- DoTDamage
- BuffBonusDamage
- Cost
- Farm
- SkillName / DisplayName

Runtime unit state also exposes TargetID / TargetPosition / IsAttacking, TotalDamage, Takedowns/Kills/Assists, Upgrade, MaxUpgrade, SellValue, TargetPriority, TotalFarmYen, IsFarm, UnitData, EquipmentData, Passives, Attributes, Element and Archetype.

Important: CurrentStats visibly changes when runtime buffs change, so it is evidence for effective in-match stats rather than database base damage.

A 2026-08-16 runtime capture of a placed ZerefEVO showed owned-copy fields including Level 50, Trait Unbound, Ascension 3, SSS StatPotential rolls, equipped equipment GUIDs, equipment runtime data, current/next calculated stats and passive parameter arrays. This demonstrates that a live placed unit can expose substantially more truth than the old optimizer was using.

## VERIFIED: BuffData behavior observed
BuffData replicas attach to a parent GameUnit and expose at least Type, Source, Value, StartTime, Stat and HideValueChanges.

Observed example: Source=$ShinigamiSwordPassive, Type=Multiply, Stat=Damage. Its Value changed over time while the parent unit's CurrentStats.Damage changed correspondingly. Exact stacking/cap/reset formula still needs targeted extraction/experiments.

## VERIFIED: enemy runtime model
GameSpawnedEnemy replicas expose fields including Name/ModelName/Type, Health/MaxHealth/BaseHealth/Overhealth/Shield, Speed/DefaultSpeed/AttackRate, PathIndex/WaypointIndex/PathProgress, SpawnTime, Modifiers/ModifiersData, Mechanics, StatusEffects/Debuffs/Attributes/Tags, Resistances, YenDropMulti and DeathPredicted/Finished.

Observed Sprinter enemies had Speed different from DefaultSpeed. Element resistance can update dynamically.

---

## VERIFIED/HIGH: Tournament scaling data
`SheetSyncedModules.TournamentScaling` is one of the SheetSynced scaling modules that does contain useful client data. Imported research reported:
- WaveScaling[1] = 1.12
- base-health categories for Basic/Elite/Boss
- Difficulty, Act, WaveJump and Multiplayer scaling tables

The research interprets WaveScaling 1.12 as compound HP growth by wave. Before using an exact enemy-HP equation in the simulator, validate how BaseHealth × difficulty × act × wave jump × modifiers are composed in the game's actual spawn/stat calculator.

---

## VERIFIED: AutoPlayUtils capabilities
Imported research found `Shared.Information.AutoPlayUtils` containing defaults including:
- DefaultTargeting = First
- DefaultUpgradeMode = Sequential
- DefaultFarmUnitRange = 28
- DefaultNonFarmUnitRange = 9
- MaxSlots = 6
- MaxAutoUpgradePriority = 6
- MaxRange = 100
- PlacementAttempts = 30

Useful path-related functions include `GetPath`, `GetClosestPointOnPath`, `GetAnchorCFrame`, `GetAnchorCFrameFromPath(s)`, `GetClosestAnchor`, `GetMapAnchor`, `GetMapKey` and `GetRandomPlacementCFrame`.

This should replace hand-rolled Workspace path discovery where possible and gives us a direct route toward accurate placement/sweet-spot geometry.

---

## VERIFIED: economy / progression signals
- Player/game replica Yen changes are observable.
- Unit runtime exposes SellValue, Upgrade and Farm when present.
- Expedition/card rewards are observable as CardSelectionPrompt replica data.
- A captured card example exposed structured parameters including Name, Description, Rarity, Upgrade, Sets, Stat and numeric effect fields.

## VERIFIED: summon/runtime extensions
GameSpawnedSummon was observed with the same broad movement/health/status model as enemies. A Cursed Immortal/Zeref summon was observed, including state/zone attributes.

---

## KNOWN OLD-BRAIN FAILURES — DO NOT PORT
Imported code review identified old optimizer issues that justify the clean rebuild:
- Some old code read SheetSyncedModules for data that is empty client-side instead of Shared.Information.
- Level and StatPotential were effectively omitted from calculations.
- Potential parser looked for nonexistent Value/Modifier/Percent fields.
- Ranking used max-upgrade DPS while generated upgrade plans could stop lower.
- Farm math reportedly double-counted costs and mixed DPS into Yen value.
- The old objective used a wave-reach proxy even when Solo Tournament used TotalDamage or TotalKills.
- DoTDamage was read but not used, invalidating effects such as Draconic's DoT bonus.
- Old generic value clamps could discard valid StatPotential percentages above 5.
- Text-based patching/version drift and unstable iteration made recommendations non-deterministic.

These points are retained as migration warnings, not as architecture to repair. Clean mapper/simulator code should be built from the verified data sources above.

## KNOWN TOOLING BUG / GAP
An earlier runtime export contained units=[] even though existing GameUnit IDs were receiving updates because the mapper started mid-session without bootstrapping existing replica class identity. New mapper must bootstrap current Replica/Fusion state before relying on live create events.

---

## UNKNOWN — must not be guessed
- Exact active-score selection/rotation algorithm for Solo/Duo; read live criterion instead.
- Whether Tournament TotalDamage counts overkill/overflow damage, and exactly when damage ceases to count on death prediction.
- Exact final stat operation order for base upgrade stats × level × potential × trait × equipment × ascension × buffs × cards × tournament modifiers.
- Exact actual rolls for every owned equipment GUID until EquipmentData is dumped without truncation.
- Strength 1, Strength 2 and Unbound exact trait effects.
- Trait stacking/order/caps where multiple systems modify the same stat.
- Equipment passive formulas and caps, including Shinigami Sword stacking/reset behavior.
- Slow/Rewind/ShadowRewind interaction, immunity, stacking, cooldown and effective path-distance gain.
- Exact targeting comparator logic for every target mode.
- Exact hitbox geometry and multi-target collision behavior for every hitbox type.
- Kill income vs wave income vs farm income attribution across all modes.
- Sell/refund formula across units/upgrades/modifiers.
- Exact Tournament modifier values/restrictions for the current live bracket until extracted.
- Whether farming/reposition/sell loops are optimal under a given active Tournament score objective.

## Next reverse priorities
1. Build a robust live Tournament context reader: active ScoreType + modifiers + resistances + map/act + bracket.
2. Dump `GetCalculatedStatsFromData`, `StatUtils`, `UnitStats` and validate exact stat operation order against CurrentStats.
3. Dump owned `EquipmentData.Stats[].Value` without max-depth truncation and link each equipment GUID to its actual roll/passive.
4. Dump full TraitData including Strength 1, Strength 2 and Unbound.
5. Dump TargetingFunctions + HitboxFunctions + allowed-targeting logic.
6. Dump Slow/Rewind/ShadowRewind and relevant status-effect processing.
7. Probe whether TotalDamage counts overkill and how DoT/crit/summons/rewind-generated extra uptime contribute.
8. Use AutoPlayUtils path functions to reconstruct exact route coverage and placement candidates.
9. Bootstrap existing replicas/Fusion GameData so mid-game scans reconstruct all placed units/enemies/buffs.
10. Build controlled experiment markers and before/after snapshots to validate extracted formulas.
