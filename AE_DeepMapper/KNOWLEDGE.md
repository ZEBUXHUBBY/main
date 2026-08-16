# AE Deep Mapper — Knowledge Baseline

This file is the persistent evidence ledger for the clean rebuild. Tournament optimization must use VERIFIED/OBSERVED facts from here or from exported datasets; unknown mechanics stay UNKNOWN until tested.

## Goal
Build a digital twin for Anime Expeditions capable of evaluating Unit × owned copy × level × potential × trait × equipment × upgrade × placement × target mode × buffs/debuffs/CC × enemy × map/path × economy × sell/reposition timing against the exact Tournament objective.

Pipeline: Deep Mapper → Knowledge DB → Simulator → Tournament Optimizer → Live Assist → optional Autopilot.

## VERIFIED: client capabilities
The current executor exposes getgc, getconstants, getloadedmodules, getproto/getprotos, getscriptclosure, getsenv, getconnections, getupvalues/debug.getupvalue, debug.getinfo, hookmetamethod, getnamecallmethod, checkcaller, newcclosure, writefile and makefolder. These were present in the exported runtime dataset.

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

### Status / CC relevant to combo optimization
Discovered information modules include Slow, Rewind, ShadowRewind, Freeze, Stun, Knockback, Illusion, Bleed, Poison, Fire, BountyMark and other status effects. Their exact formulas/stacking rules are NOT yet considered verified.

## VERIFIED: runtime GameUnit data
Replica updates expose calculated CurrentStats and NextStats. Observed fields include:
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
- damage-type fields such as Magical when applicable

Runtime unit state also exposes TargetID / TargetPosition / IsAttacking, TotalDamage and Takedowns through replica updates/writes.

Important: CurrentStats visibly changes when runtime buffs change, so it is suitable as evidence for effective in-match stats rather than treating database base damage as final damage.

## VERIFIED: BuffData behavior observed
BuffData replicas attach to a parent GameUnit and expose at least:
- Type
- Source
- Value
- StartTime
- Stat
- HideValueChanges

Observed example: Source=$ShinigamiSwordPassive, Type=Multiply, Stat=Damage. Its Value changed over time while the parent unit's CurrentStats.Damage changed correspondingly. Exact stacking/cap/reset formula still needs targeted extraction/experiments.

## VERIFIED: enemy runtime model
GameSpawnedEnemy replicas expose fields including:
- Name / ModelName / Type
- Health / MaxHealth / BaseHealth / Overhealth / Shield
- Speed / DefaultSpeed / AttackRate
- PathIndex / WaypointIndex / PathProgress
- SpawnTime
- Modifiers / ModifiersData
- Mechanics
- StatusEffects / Debuffs / Attributes / Tags
- Resistances
- YenDropMulti
- DeathPredicted / Finished

Observed Sprinter enemies had Speed different from DefaultSpeed. Element resistance was also updated dynamically (example Terra=-15 in the captured session).

## VERIFIED: economy / progression signals
- Player/game replica Yen changes are observable.
- Unit runtime can expose SellValue, Upgrade and Farm when present.
- Expedition/card rewards are observable as CardSelectionPrompt replica data.
- A captured card example exposed complete structured parameters including Name, Description, Rarity, Upgrade, Sets, Stat and numeric effect fields.
- Examples observed include Bat Cavalry, Hemorrhage, Razor Focus and Bounty Hunter.

## VERIFIED: summon/runtime extensions
GameSpawnedSummon was observed with the same broad movement/health/status model as enemies. A Cursed Immortal summon was observed, including Attributes.ZerefZone updates.

## KNOWN TOOLING BUG / GAP
The V1 runtime export contained units=[] even though existing GameUnit IDs were receiving updates. Cause: mapper started mid-session and tracked subsequent updates without bootstrapping already-existing replica class identity. New mapper must bootstrap current ReplicaClient state before relying on live create events.

## UNKNOWN — must not be guessed
- Exact Tournament score formula and every score type/weight/penalty.
- Exact final stat formula/order for level + potential + trait + equipment + buffs + cards.
- Trait stacking/order/caps.
- Equipment passive formulas and caps, including Shinigami Sword stacking/reset behavior.
- Slow/Rewind/ShadowRewind interaction, immunity, stacking, cooldown and effective path-distance gain.
- Exact targeting comparator logic for every target mode.
- Exact hitbox geometry and multi-target collision behavior for every hitbox type.
- Kill income vs wave income vs farm income attribution across all modes.
- Sell/refund formula across units/upgrades/modifiers.
- Tournament-specific restrictions and whether farming/reposition/sell loops are optimal under its scoring objective.

## Next reverse priorities
1. Dump/inspect Shared.Information.Tournaments and Tournament.ScoreTypeInfo.
2. Dump/inspect GetCalculatedStatsFromData + StatUtils + UnitStats.
3. Dump traits/equipment/passive tables and EquipmentMultiplier.
4. Dump TargetingFunctions + HitboxFunctions + allowed-targeting logic.
5. Dump Slow/Rewind/ShadowRewind and relevant status-effect processing.
6. Bootstrap existing replicas so a mid-game scan reconstructs all placed units/enemies/buffs.
7. Build controlled experiment markers and before/after snapshots to validate formulas extracted from client code.

## Evidence policy
Every derived rule should carry provenance and confidence: VERIFIED (direct structured data + repeatable observation), HIGH (multiple consistent observations), HYPOTHESIS (client-code inference not yet validated), UNKNOWN. The optimizer must never silently replace UNKNOWN with a heuristic and present it as fact.
