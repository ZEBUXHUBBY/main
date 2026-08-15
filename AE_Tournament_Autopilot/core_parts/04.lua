                for _, abilityName in pairs(abilities) do
                    if type(abilityName) == "string" then cumulativeAbilities[abilityName] = true end
                end
            end

            local tags = ci(row, {"Tags"})
            if type(tags) == "table" then
                for _, tag in pairs(tags) do
                    if type(tag) == "string" then cumulativeTags[tag] = true end
                end
            end

            local upgrade = {
                Level = entry.Level,
                Cost = cost,
                CumulativeCost = cumulativeCost,
                Damage = damage,
                SPA = math.max(0.01, spa),
                Range = range,
                CritChance = critChance,
                CritDamage = critDamage,
                DPS = (damage / math.max(0.01, spa)) * critFactor(critChance, critDamage),
                RawDPS = (damage / math.max(0.01, spa)) * critFactor(critChance, critDamage),
                HitboxType = ci(row, {"HitboxType", "AOEType", "AttackType"}) or "Unknown",
                HitboxSize = tonumber(ci(row, {"HitboxSize", "AOESize", "Width"})) or 0,
                SkillName = ci(row, {"SkillName", "DisplayName"}),
                Income = income,
                Passives = shallowCopy(cumulativePassives),
                Abilities = shallowCopy(cumulativeAbilities),
                Tags = shallowCopy(cumulativeTags),
            }

            template.Upgrades[#template.Upgrades + 1] = upgrade
            if income then
                template.Farm = true
                template.FarmIncomeKnown = true
            end
        end

        local function consumeDescription(description)
            local capability = capabilityFromDescription(description)
            mergeSet(template.CC, capability.CC)
            template.ShieldCounter = template.ShieldCounter or capability.ShieldCounter
            template.BossBonus = template.BossBonus or capability.BossBonus
            template.Buff = template.Buff or capability.Buff
            template.Debuff = template.Debuff or capability.Debuff
            template.Summon = template.Summon or capability.Summon
            template.DOT = template.DOT or capability.DOT
        end

        local seen = {}
        for _, upgrade in ipairs(template.Upgrades) do
            for passiveName in pairs(upgrade.Passives) do
                if not seen["P:" .. passiveName] then
                    seen["P:" .. passiveName] = true
                    local row = database.Passives[passiveName]
                    consumeDescription(renderDescription(row))
                end
            end
            for abilityName in pairs(upgrade.Abilities) do
                if not seen["A:" .. abilityName] then
                    seen["A:" .. abilityName] = true
                    local row = database.Abilities[abilityName]
                    consumeDescription(renderDescription(row))
                end
            end
            for tag in pairs(upgrade.Tags) do
                local capability = capabilityFromDescription(tag)
                mergeSet(template.CC, capability.CC)
            end
        end

        template.Base = template.Upgrades[1]
        template.Final = template.Upgrades[#template.Upgrades]
        Brain.Cache.Templates[asset] = template
        return template
    end

    -- -------------------------------------------------------------------------
    -- Owned-copy modifiers
    -- -------------------------------------------------------------------------

    local function explicitMods(row)
        if type(row) ~= "table" then return nil end
        local output = {}

        local function takeAdditive(names, key)
            local value = numberCI(row, names)
            if value and math.abs(value) <= 5 then output[key] = value end
        end

        local function takeMultiplier(names, key)
            local value = numberCI(row, names)
            if value and value > 0 and value <= 10 then output[key] = value - 1 end
        end

        takeMultiplier({"DamageMultiplier", "DMGMultiplier"}, "Damage")
        takeMultiplier({"SPAMultiplier", "AttackSpeedMultiplier"}, "SPA")
        takeMultiplier({"RangeMultiplier"}, "Range")

        if output.Damage == nil then takeAdditive({"DamagePercent", "DamageIncrease", "Damage"}, "Damage") end
        if output.SPA == nil then takeAdditive({"SPAPercent", "SPAIncrease", "SPA"}, "SPA") end
        if output.Range == nil then takeAdditive({"RangePercent", "RangeIncrease", "Range"}, "Range") end

        takeAdditive({"CritChance", "CriticalChance"}, "CritChance")
        takeAdditive({"CritDamage", "CriticalDamage"}, "CritDamage")
        takeAdditive({"Cost", "CostPercent"}, "Cost")
        takeAdditive({"Farm", "FarmIncome", "IncomeMultiplier"}, "Farm")
        takeAdditive({"DoTDamage", "DOTDamage"}, "DOT")

        return countKeys(output) > 0 and output or nil
    end

    local function mergeMods(destination, source)
        for key, value in pairs(type(source) == "table" and source or {}) do
            destination[key] = (destination[key] or 0) + value
        end
    end

    local function gatherEquipmentStrings(root, output, depth, seen)
        output = output or {}
        depth = depth or 0
        seen = seen or {}
        if depth > 5 then return output end
        if type(root) == "string" then
            output[#output + 1] = root
            return output
        end
        if type(root) ~= "table" or seen[root] then return output end
        seen[root] = true
        for key, value in pairs(root) do
            if type(value) == "string" then
                local normalizedKey = norm(key)
                if normalizedKey:find("asset", 1, true) or normalizedKey:find("equipment", 1, true) or normalizedKey == "id" or normalizedKey == "name" then
                    output[#output + 1] = value
                end
            elseif type(value) == "table" then
                gatherEquipmentStrings(value, output, depth + 1, seen)
            end
        end
        return output
    end

    local function equipmentData(value, database)
        local mods = {}
        local labels = {}
        local icons = {}

        if type(value) == "table" then mergeMods(mods, explicitMods(value)) end
        local used = {}
        for _, rawName in ipairs(gatherEquipmentStrings(value)) do
            local name = tostring(rawName):gsub("#.*$", "")
            if name ~= "" and not used[norm(name)] then
                used[norm(name)] = true
                local row = database.Equipment[name] or database.EquipmentIndex[norm(name)]
                if type(row) == "table" then
                    labels[#labels + 1] = tostring(ci(row, {"DisplayName", "Name", "Asset"}) or name)
                    local image = ci(row, {"Image", "Icon"})
                    if type(image) == "string" then icons[#icons + 1] = image end
                    mergeMods(mods, explicitMods(row))
                    local statTable = ci(row, {"Stats", "Modifiers", "StatValues"})
                    mergeMods(mods, explicitMods(statTable))
                else
                    labels[#labels + 1] = name
                end
            end
        end

        return countKeys(mods) > 0 and mods or nil, labels, icons
    end

    local function potentialData(value)
        local labels = {}
        local mods = {}
        if type(value) ~= "table" then return labels, nil end
        for statName, row in pairs(value) do
            if type(row) == "table" then
                local grade = ci(row, {"Potential", "Grade"})
                if grade then labels[#labels + 1] = tostring(statName) .. " " .. tostring(grade) end
                -- Only use fields whose names explicitly mean a modifier.
                local explicit = numberCI(row, {"Value", "Modifier", "Percent", "Bonus", "StatIncrease"})
                if explicit and math.abs(explicit) <= 5 then mods[statName] = explicit end
            end
        end
        table.sort(labels)
        return labels, countKeys(mods) > 0 and mods or nil
    end

    local function directLevelMods(level, database)
        if type(database.UnitLevel) ~= "table" then return nil end
        local row = database.UnitLevel[level] or database.UnitLevel[tostring(level)]
        if type(row) ~= "table" then
            local shallow = ci(database.UnitLevel, {"Levels", "LevelData", "UnitLevels", "Data", "Entries"})
            if type(shallow) == "table" then row = shallow[level] or shallow[tostring(level)] end
        end
        return explicitMods(row)
    end

    local function nativeCritAdd(base, addition, isDamage)
        base = tonumber(base) or 0
        addition = tonumber(addition) or 0
        if isDamage and base > 5 then return base + addition * 100 end
        if (not isDamage) and base > 1 then return base + addition * 100 end
        return base + addition
    end

    local function applyOwnedCopy(template, record, database)
        if not template or not template.Base or not record or type(record.Data) ~= "table" then return nil end
        local data = record.Data
        local copy = shallowCopy(template)
        copy.Record = record
        copy.ID = record.ID
        copy.Level = tonumber(ci(data, {"Level", "UnitLevel"})) or 1
        copy.Trait = tostring(ci(data, {"Trait"}) or "No Trait")

        local traitRow = database.Traits[copy.Trait]
        local traitMods = explicitMods(traitRow)
        copy.TraitIcon = type(traitRow) == "table" and ci(traitRow, {"Image", "Icon"}) or nil

        local equipmentValue = ci(data, {"Equipment", "Equipments"})
