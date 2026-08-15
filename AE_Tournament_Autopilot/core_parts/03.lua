
    local function scanStageTable()
        if type(getgc) ~= "function" then return nil end
        local ok, objects = pcall(getgc, true)
        if not ok or type(objects) ~= "table" then return nil end
        local best, bestScore = nil, -math.huge
        for _, object in ipairs(objects) do
            if type(object) == "table" then
                local gamemode = ci(object, {"Gamemode", "GameMode", "Mode"})
                local mapName = ci(object, {"MapName", "Map"})
                local actName = ci(object, {"ActName", "Act"})
                local difficulty = ci(object, {"Difficulty"})
                if gamemode or mapName or actName or difficulty then
                    local score = 0
                    if gamemode then score = score + 5 end
                    if mapName then score = score + 4 end
                    if actName then score = score + 3 end
                    if difficulty then score = score + 2 end
                    if norm(gamemode):find("tournament", 1, true) then score = score + 10 end
                    if score > bestScore then
                        bestScore = score
                        best = {
                            Gamemode = gamemode,
                            MapName = mapName,
                            ActName = actName,
                            Difficulty = difficulty,
                            Raw = object,
                        }
                    end
                end
            end
        end
        return best
    end

    local function detectContext()
        local text = collectVisibleText()
        local lower = text:lower()
        local stage = scanStageTable() or {}

        local bossWaves = lower:find("boss waves", 1, true) ~= nil or lower:find("all enemies are bosses", 1, true) ~= nil
        local speedy = lower:find("speedy", 1, true) ~= nil or lower:find("faster", 1, true) ~= nil
        local speedPercent = tonumber(lower:match("(%d+)%%%s+faster")) or (speedy and 50 or nil)
        local hardMode = lower:find("hard mode", 1, true) ~= nil or norm(stage.Difficulty) == "hard"
        local shielded = lower:find("shielded", 1, true) ~= nil or lower:find("shield", 1, true) ~= nil

        local labels = {}
        if bossWaves then labels[#labels + 1] = "BOSS WAVES" end
        if speedy then labels[#labels + 1] = "SPEEDY +" .. tostring(speedPercent or 50) .. "%" end
        if hardMode then labels[#labels + 1] = "HARD MODE" end
        if shielded then labels[#labels + 1] = "SHIELDED" end

        local waveCount = tonumber(lower:match("wave%s*count%s*[:%-]?%s*(%d+)"))
        local currentWave = tonumber(lower:match("wave%s*(%d+)"))

        return {
            Gamemode = stage.Gamemode or (lower:find("tournament", 1, true) and "Tournament" or "UNKNOWN"),
            MapName = stage.MapName or lower:match("tournament%s+[%-%•]?%s*([%w%s]+)") or "UNKNOWN",
            ActName = stage.ActName,
            Difficulty = stage.Difficulty or (hardMode and "Hard" or "UNKNOWN"),
            BossWaves = bossWaves,
            Speedy = speedy,
            SpeedPercent = speedPercent,
            HardMode = hardMode,
            Shielded = shielded,
            Labels = labels,
            WaveCount = waveCount,
            CurrentWave = currentWave,
            ScoreModel = "WAVE_REACH_PROXY",
            ScoreConfidence = "PROXY",
            TextEvidence = text,
        }
    end

    -- -------------------------------------------------------------------------
    -- Unit model
    -- -------------------------------------------------------------------------

    local CC_WORDS = {
        stun = "Stun",
        slow = "Slow",
        freeze = "Freeze",
        rewind = "Rewind",
        knockback = "Knockback",
        stagger = "Stagger",
        root = "Root",
        timestop = "TimeStop",
    }

    local function renderDescription(row)
        if type(row) ~= "table" then return "" end
        local description = tostring(ci(row, {"Description", "Desc"}) or "")
        local parameters = ci(row, {"Parameters", "Params"})
        if type(parameters) == "table" then
            for key, parameter in pairs(parameters) do
                local value = parameter
                if type(parameter) == "table" then
                    value = ci(parameter, {"Value", "Default", "Amount"})
                    if value == nil then
                        local minimum = ci(parameter, {"Min", "Minimum"})
                        local maximum = ci(parameter, {"Max", "Maximum"})
                        if minimum ~= nil and maximum ~= nil then value = tostring(minimum) .. "-" .. tostring(maximum) end
                    end
                end
                if value ~= nil then
                    description = description:gsub("%{" .. tostring(key) .. "%}", tostring(value))
                end
            end
        end
        return description
    end

    local function capabilityFromDescription(description)
        local lower = tostring(description or ""):lower()
        local result = {
            CC = {},
            ShieldCounter = false,
            BossBonus = false,
            Buff = false,
            Debuff = false,
            Summon = false,
            DOT = false,
        }

        for word, label in pairs(CC_WORDS) do
            if lower:find(word, 1, true) then result.CC[label] = true end
        end

        if lower:find("shield", 1, true) then
            if lower:find("break", 1, true) or lower:find("remove", 1, true) or lower:find("pierce", 1, true) or lower:find("ignore", 1, true) or lower:find("damage shields", 1, true) then
                result.ShieldCounter = true
            end
        end

        if lower:find("boss", 1, true) and not lower:find("cannot", 1, true) and not lower:find("does not", 1, true) then
            if lower:find("increase", 1, true) or lower:find("more damage", 1, true) or lower:find("damage to", 1, true) or lower:find("against", 1, true) then
                result.BossBonus = true
            end
        end

        result.Buff = lower:find("buff", 1, true) ~= nil or lower:find("increase damage", 1, true) ~= nil
        result.Debuff = setCount(result.CC) > 0 or lower:find("debuff", 1, true) ~= nil
        result.Summon = lower:find("summon", 1, true) ~= nil
        result.DOT = lower:find("damage over time", 1, true) ~= nil or lower:find("burn", 1, true) ~= nil or lower:find("bleed", 1, true) ~= nil or lower:find("poison", 1, true) ~= nil or lower:find("black fire", 1, true) ~= nil
        return result
    end

    local function upgradeRows(info)
        local source = ci(info, {"UpgradeInfo", "Upgrades"})
        local output = {}
        if type(source) ~= "table" then return output end
        for key, row in pairs(source) do
            local level = tonumber(key)
            if level and type(row) == "table" then output[#output + 1] = {Level = level, Row = row} end
        end
        table.sort(output, function(a, b) return a.Level < b.Level end)
        return output
    end

    local function critFactor(chance, damage)
        chance = tonumber(chance) or 0
        damage = tonumber(damage) or 0
        if chance > 1 then chance = chance / 100 end
        if damage > 5 then damage = damage / 100 end
        return 1 + math.max(0, chance) * math.max(0, damage)
    end

    local function buildTemplate(asset, database)
        Brain.Cache.Templates = Brain.Cache.Templates or {}
        if Brain.Cache.Templates[asset] then return Brain.Cache.Templates[asset] end

        local info = database.Units[asset]
        if type(info) ~= "table" then return nil end

        local template = {
            Asset = asset,
            DisplayName = ci(info, {"DisplayName", "Name"}) or asset,
            Element = ci(info, {"Element"}),
            Archetype = ci(info, {"Archetype"}),
            Rarity = ci(info, {"Rarity"}),
            PlacementType = ci(info, {"PlacementType"}),
            PlacementLimit = tonumber(ci(info, {"PlacementLimit", "Limit"})) or 1,
            Upgrades = {},
            CC = {},
            ShieldCounter = false,
            BossBonus = false,
            Buff = false,
            Debuff = false,
            Summon = false,
            DOT = false,
            Farm = norm(ci(info, {"Element"})) == "farm" or ci(info, {"IsFarm"}) == true,
            FarmIncomeKnown = false,
        }

        local cumulativeCost = 0
        local cumulativePassives = {}
        local cumulativeAbilities = {}
        local cumulativeTags = {}

        for _, entry in ipairs(upgradeRows(info)) do
            local row = entry.Row
            local cost = tonumber(ci(row, {"Cost", "Price"})) or 0
            cumulativeCost = cumulativeCost + cost

            local damage = tonumber(ci(row, {"Damage", "DMG"})) or 0
            local spa = tonumber(ci(row, {"SPA", "AttackSpeed", "AttackCooldown"})) or 1
            local range = tonumber(ci(row, {"Range", "RNG"})) or 0
            local critChance = tonumber(ci(row, {"CritChance", "CriticalChance"})) or 0
            local critDamage = tonumber(ci(row, {"CritDamage", "CriticalDamage"})) or 0
            local income = tonumber(ci(row, {"Income", "YenIncome", "YenPerWave", "IncomePerWave", "MoneyPerWave", "CashPerWave", "GeneratedYen"}))

            local passives = ci(row, {"Passives"})
            if type(passives) == "table" then
                for _, passiveName in pairs(passives) do
                    if type(passiveName) == "string" then cumulativePassives[passiveName] = true end
                end
            end

            local abilities = ci(row, {"Abilities"})
            if type(abilities) == "table" then
