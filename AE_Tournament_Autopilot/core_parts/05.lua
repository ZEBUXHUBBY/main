        local equipmentMods, equipmentLabels, equipmentIcons = equipmentData(equipmentValue, database)
        copy.EquipmentLabels = equipmentLabels
        copy.EquipmentIcons = equipmentIcons
        copy.EquipmentLabel = #equipmentLabels > 0 and table.concat(equipmentLabels, ", ") or "None"

        local potentialLabels, potentialMods = potentialData(ci(data, {"StatPotential", "Potential"}))
        copy.PotentialLabels = potentialLabels
        copy.PotentialLabel = #potentialLabels > 0 and table.concat(potentialLabels, " • ") or "Unknown formula"

        local levelMods = directLevelMods(copy.Level, database)
        local combined = {}
        mergeMods(combined, levelMods)
        mergeMods(combined, traitMods)
        mergeMods(combined, equipmentMods)
        mergeMods(combined, potentialMods)

        local source = {}
        if levelMods then source[#source + 1] = "LEVEL EXPLICIT" end
        if traitMods then source[#source + 1] = "TRAIT EXACT" end
        if equipmentMods then source[#source + 1] = "EQUIPMENT EXPLICIT" end
        if potentialMods then source[#source + 1] = "POTENTIAL EXPLICIT" end

        local damageMultiplier = 1 + (combined.Damage or 0)
        local spaMultiplier = 1 + (combined.SPA or 0)
        local rangeMultiplier = 1 + (combined.Range or 0)
        local costMultiplier = 1 + (combined.Cost or 0)
        local farmMultiplier = 1 + (combined.Farm or 0)

        copy.PlacementLimit = tonumber(template.PlacementLimit) or 1
        if type(traitRow) == "table" and tonumber(traitRow.PlacementLimit) then
            copy.PlacementLimit = tonumber(traitRow.PlacementLimit)
        end

        copy.Upgrades = {}
        local cumulativeCost = 0
        for _, sourceUpgrade in ipairs(template.Upgrades or {}) do
            local upgrade = shallowCopy(sourceUpgrade)
            upgrade.Damage = (tonumber(sourceUpgrade.Damage) or 0) * damageMultiplier
            upgrade.SPA = math.max(0.01, (tonumber(sourceUpgrade.SPA) or 1) * spaMultiplier)
            upgrade.Range = math.max(0, (tonumber(sourceUpgrade.Range) or 0) * rangeMultiplier)
            upgrade.Cost = math.max(0, (tonumber(sourceUpgrade.Cost) or 0) * costMultiplier)
            cumulativeCost = cumulativeCost + upgrade.Cost
            upgrade.CumulativeCost = cumulativeCost
            if tonumber(sourceUpgrade.Income) then upgrade.Income = tonumber(sourceUpgrade.Income) * farmMultiplier end
            upgrade.CritChance = nativeCritAdd(sourceUpgrade.CritChance, combined.CritChance, false)
            upgrade.CritDamage = nativeCritAdd(sourceUpgrade.CritDamage, combined.CritDamage, true)
            upgrade.DPS = (upgrade.Damage / upgrade.SPA) * critFactor(upgrade.CritChance, upgrade.CritDamage)
            upgrade.RawDPS = upgrade.DPS
            copy.Upgrades[#copy.Upgrades + 1] = upgrade
        end

        copy.Base = copy.Upgrades[1]
        copy.Final = copy.Upgrades[#copy.Upgrades]
        copy.CapDPS = ((copy.Final and copy.Final.DPS) or 0) * math.max(1, copy.PlacementLimit)
        copy.OpenerEfficiency = ((copy.Base and copy.Base.CumulativeCost or 0) > 0) and (((copy.Base and copy.Base.DPS) or 0) * math.max(1, copy.PlacementLimit) / copy.Base.CumulativeCost) or 0
        copy.StatSource = #source > 0 and table.concat(source, " + ") or "BASE ONLY"
        copy.StatConfidence = #source >= 3 and "HIGH" or (#source > 0 and "PARTIAL" or "BASE")
        return copy
    end

    -- -------------------------------------------------------------------------
    -- Tournament ranking, targeting, upgrades
    -- -------------------------------------------------------------------------

    local function rankContext(copies)
        local maximum = {
            CapDPS = 1,
            Opener = 1,
            Range = 1,
            Hitbox = 1,
        }
        for _, copy in pairs(copies or {}) do
            maximum.CapDPS = math.max(maximum.CapDPS, copy.CapDPS or 0)
            maximum.Opener = math.max(maximum.Opener, copy.OpenerEfficiency or 0)
            maximum.Range = math.max(maximum.Range, copy.Final and copy.Final.Range or 0)
            maximum.Hitbox = math.max(maximum.Hitbox, copy.Final and copy.Final.HitboxSize or 0)
        end
        return maximum
    end

    local function rankUnit(copy, context, maximum, reasons)
        if not copy or not copy.Final then return -math.huge end
        if copy.Farm and (copy.CapDPS or 0) <= 0 then return -math.huge end

        maximum = maximum or {CapDPS = 1, Opener = 1, Range = 1, Hitbox = 1}
        local cap = (copy.CapDPS or 0) / maximum.CapDPS
        local opener = (copy.OpenerEfficiency or 0) / maximum.Opener
        local range = (copy.Final.Range or 0) / maximum.Range
        local hitbox = (copy.Final.HitboxSize or 0) / maximum.Hitbox

        local score = cap * 58 + opener * 14 + range * 10 + hitbox * 6
        if reasons then
            reasons[#reasons + 1] = {Label = "Sustained damage", Value = cap * 58}
            reasons[#reasons + 1] = {Label = "Early efficiency", Value = opener * 14}
        end

        if context.BossWaves then
            score = score + cap * 10 + range * 8
            if copy.BossBonus then score = score + 14 end
            if reasons then
                reasons[#reasons + 1] = {Label = "Boss-wave uptime", Value = cap * 10 + range * 8}
                if copy.BossBonus then reasons[#reasons + 1] = {Label = "Verified boss mechanic", Value = 14} end
            end
        end

        if context.Speedy then
            score = score + range * 14
            if not context.BossWaves and setCount(copy.CC) > 0 then score = score + 8 end
            if reasons then
                reasons[#reasons + 1] = {Label = "Speedy coverage", Value = range * 14}
                if not context.BossWaves and setCount(copy.CC) > 0 then reasons[#reasons + 1] = {Label = "Control coverage", Value = 8} end
            end
        end

        if context.HardMode then score = score + cap * 5 + opener * 4 end
        if context.Shielded and copy.ShieldCounter then score = score + 14 end
        if copy.Buff then score = score + 5 end
        if copy.Summon then score = score + 3 end
        return score
    end

    local function roleFor(copy, context, teamIndex)
        if copy.Farm then return "FARM" end
        if context.Shielded and copy.ShieldCounter then return "SHIELD" end
        if context.BossWaves and (copy.BossBonus or teamIndex <= 2) then return "BOSS DPS" end
        if context.Speedy and setCount(copy.CC) > 0 and not context.BossWaves then return "CONTROL" end
        if teamIndex == 1 then return "OPENER" end
        local hitbox = norm(copy.Final and copy.Final.HitboxType)
        if hitbox:find("circle", 1, true) or hitbox:find("cone", 1, true) or hitbox:find("line", 1, true) then return "AOE" end
        return "DPS"
    end

    local function targetPriority(copy, context, role)
        local result = {
            Primary = "First",
            Alternate = "Strongest",
            Trigger = "default anti-leak",
            Scores = {},
        }

        local modes = {"First", "Last", "Closest", "Strongest", "Boss", "Weakest", "Shielded", "Fastest"}
        for _, mode in ipairs(modes) do result.Scores[mode] = 0 end

        result.Scores.First = 55
        result.Scores.Strongest = 42
        result.Scores.Closest = 34
        result.Scores.Last = 20
        result.Scores.Weakest = 18

        if context.Shielded and copy.ShieldCounter then
            result.Scores.Shielded = 100
            result.Primary = "Shielded"
            result.Alternate = "First"
            result.Trigger = "focus shields with a verified shield counter"
            return result
        end

        if context.BossWaves then
            result.Scores.Boss = copy.BossBonus and 98 or 72
            result.Scores.Strongest = 88
            result.Scores.First = role == "OPENER" and 78 or 84
            if context.Speedy then result.Scores.First = result.Scores.First + 10 end

            if role == "BOSS DPS" and copy.BossBonus then
                result.Primary = "Boss"
                result.Alternate = "Strongest"
                result.Trigger = "verified boss-focused damage"
            elseif role == "OPENER" or role == "CONTROL" then
                result.Primary = "First"
                result.Alternate = "Strongest"
                result.Trigger = "prevent the fastest boss from leaking"
            else
                result.Primary = "Strongest"
                result.Alternate = "First"
                result.Trigger = "concentrate sustained damage on the highest-HP boss"
            end
            return result
        end

        if context.Speedy then
            result.Scores.Fastest = setCount(copy.CC) > 0 and 100 or 82
            result.Scores.First = 88
            if setCount(copy.CC) > 0 then
                result.Primary = "Fastest"
                result.Alternate = "First"
                result.Trigger = "control the current leak threat"
            else
                result.Primary = "First"
                result.Alternate = "Fastest"
                result.Trigger = "keep damage on the enemy nearest the exit"
            end
            return result
        end

        if copy.BossBonus then
            result.Primary = "Boss"
            result.Alternate = "Strongest"
            result.Trigger = "unit has a positive boss mechanic"
        elseif norm(copy.Final.HitboxType):find("single", 1, true) then
            result.Primary = "Strongest"
            result.Alternate = "First"
            result.Trigger = "single-target damage benefits from focusing high HP"
        else
            result.Primary = "First"
            result.Alternate = "Strongest"
            result.Trigger = "stable wave-clear targeting"
        end
        return result
    end

    local function upgradeStepValue(copy, previous, nextUpgrade, context)
        local placement = math.max(1, copy.PlacementLimit or 1)
        local cost = math.max(1, tonumber(nextUpgrade.Cost) or 1)
        local dpsGain = math.max(0, (nextUpgrade.DPS or 0) - (previous.DPS or 0)) * placement
        local rangeGain = math.max(0, (nextUpgrade.Range or 0) - (previous.Range or 0))
        local hitboxGain = math.max(0, (nextUpgrade.HitboxSize or 0) - (previous.HitboxSize or 0))
        local unlocks = 0

        for passive in pairs(nextUpgrade.Passives or {}) do if not (previous.Passives or {})[passive] then unlocks = unlocks + 1 end end
        for ability in pairs(nextUpgrade.Abilities or {}) do if not (previous.Abilities or {})[ability] then unlocks = unlocks + 2 end end
