--[[
    Anime Expeditions Assistant | Analyzer V1
    Stable entrypoint:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Assistant/main.lua"))()

    V1 scope:
      - Live-load AE_DB JSON from GitHub
      - Browse all units and upgrades
      - Stat DPS (Damage / SPA)
      - Cumulative cost and DPS per total cost
      - Marginal DPS per upgrade cost
      - Attack timing / ticks from SkillInfo
      - Passive + ability descriptions with parameter values
      - Placement guidance by attack geometry

    Notes:
      - Tick count is NOT multiplied into Damage for Stat DPS because the DB's
        Damage field may already represent the attack's configured damage.
      - Placement optimizer / map path simulation will be added in later versions.
]]

if getgenv and getgenv().AE_ASSISTANT_LOADED then
    warn("[AE Assistant] Already loaded")
    return
end

if getgenv then
    getgenv().AE_ASSISTANT_LOADED = true
end

local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")

local RAW = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_DB/"

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 5,
        })
    end)
end

local function fetchJSON(name, required)
    local okHttp, body = pcall(function()
        return game:HttpGet(RAW .. name .. "?t=" .. tostring(os.time()))
    end)

    if not okHttp then
        if required then
            error("[AE Assistant] Failed to download " .. name .. ": " .. tostring(body), 0)
        end
        warn("[AE Assistant] Failed to download", name, body)
        return {}
    end

    local okDecode, data = pcall(function()
        return HttpService:JSONDecode(body)
    end)

    if not okDecode or type(data) ~= "table" then
        if required then
            error("[AE Assistant] Failed to decode " .. name .. ": " .. tostring(data), 0)
        end
        warn("[AE Assistant] Failed to decode", name, data)
        return {}
    end

    return data
end

notify("AE Assistant", "Loading database from GitHub...", 4)

local DB = {
    Units = fetchJSON("units.json", true),
    Abilities = fetchJSON("abilities.json", false),
    Passives = fetchJSON("passives.json", false),
    StatusEffects = fetchJSON("status_effects.json", false),
    Maps = fetchJSON("maps.json", false),
    Enemies = fetchJSON("enemies.json", false),
    Mechanics = fetchJSON("game_mechanics.json", false),
}

local function tableCount(t)
    local n = 0
    if type(t) ~= "table" then return 0 end
    for _ in pairs(t) do n += 1 end
    return n
end

local function sortedKeys(t, numeric)
    local keys = {}
    if type(t) ~= "table" then return keys end

    for k in pairs(t) do
        keys[#keys + 1] = k
    end

    table.sort(keys, function(a, b)
        if numeric then
            return (tonumber(a) or math.huge) < (tonumber(b) or math.huge)
        end
        return tostring(a):lower() < tostring(b):lower()
    end)

    return keys
end

local function nfmt(v, digits)
    v = tonumber(v) or 0
    digits = digits or 2

    if math.abs(v) >= 1000000 then
        return string.format("%.2fM", v / 1000000)
    elseif math.abs(v) >= 1000 then
        return string.format("%.2fK", v / 1000)
    end

    return string.format("%." .. tostring(digits) .. "f", v)
end

local function money(v)
    v = tonumber(v) or 0
    local s = tostring(math.floor(v + 0.5))
    local out = s

    while true do
        local changed
        out, changed = out:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if changed == 0 then break end
    end

    return "$" .. out
end

local function statDPS(stats)
    if type(stats) ~= "table" then return 0 end
    local damage = tonumber(stats.Damage) or 0
    local spa = tonumber(stats.SPA) or 0
    if spa <= 0 then return 0 end
    return damage / spa
end

local function getUpgrade(unit, level)
    if not unit or type(unit.UpgradeInfo) ~= "table" then return nil end
    return unit.UpgradeInfo[tostring(level)] or unit.UpgradeInfo[level]
end

local function getMaxUpgrade(unit)
    local maxU = 0
    if not unit or type(unit.UpgradeInfo) ~= "table" then return 0 end

    for k in pairs(unit.UpgradeInfo) do
        local n = tonumber(k)
        if n and n > maxU then maxU = n end
    end

    return maxU
end

local function closestUpgrade(unit, requested)
    requested = math.max(0, math.floor(tonumber(requested) or 0))
    local maxU = getMaxUpgrade(unit)
    if requested > maxU then requested = maxU end

    if getUpgrade(unit, requested) then return requested end

    for delta = 1, maxU + 1 do
        if requested - delta >= 0 and getUpgrade(unit, requested - delta) then
            return requested - delta
        end
        if requested + delta <= maxU and getUpgrade(unit, requested + delta) then
            return requested + delta
        end
    end

    return 0
end

local function cumulativeCost(unit, level)
    local total = 0
    for u = 0, level do
        local info = getUpgrade(unit, u)
        if info then
            total += tonumber(info.Cost) or 0
        end
    end
    return total
end

local function marginalValue(unit, level)
    local cur = getUpgrade(unit, level)
    if not cur then
        return 0, 0, 0
    end

    local currentDPS = statDPS(cur)
    local cost = tonumber(cur.Cost) or 0

    if level <= 0 then
        return currentDPS, cost > 0 and currentDPS / cost or 0, cost
    end

    local prev = getUpgrade(unit, level - 1)
    local prevDPS = statDPS(prev)
    local gain = currentDPS - prevDPS
    local efficiency = cost > 0 and gain / cost or 0

    return gain, efficiency, cost
end

local function listValues(t)
    local result = {}
    if type(t) ~= "table" then return result end

    local keys = sortedKeys(t, true)
    for _, k in ipairs(keys) do
        local value = t[k]
        if value ~= nil then
            result[#result + 1] = tostring(value)
        end
    end

    return result
end

local function parameterValue(p)
    if type(p) ~= "table" then return "?" end
    local minV = p.Min
    local maxV = p.Max

    if minV == maxV then
        return tostring(minV)
    elseif minV ~= nil and maxV ~= nil then
        return tostring(minV) .. "-" .. tostring(maxV)
    end

    return tostring(minV or maxV or "?")
end

local function renderDescription(entry)
    if type(entry) ~= "table" then return "" end
    local text = tostring(entry.Description or "")
    local params = entry.Parameters or {}

    text = text:gsub("{(%d+)}", function(index)
        local p = params[index] or params[tonumber(index)]
        return parameterValue(p)
    end)

    return text
end

local function mechanicBlock(title, ids, database, limit)
    limit = limit or 4
    if #ids == 0 then
        return title .. ": none"
    end

    local lines = {title .. ":"}

    for i = 1, math.min(#ids, limit) do
        local id = ids[i]
        local entry = database[id]

        if type(entry) == "table" then
            local display = entry.DisplayName or id
            lines[#lines + 1] = "• " .. tostring(display) .. " [" .. id .. "]"

            local desc = renderDescription(entry)
            if desc ~= "" then
                lines[#lines + 1] = desc
            end

            if entry.Cooldown ~= nil then
                lines[#lines + 1] = string.format(
                    "Cooldown: %ss | Type: %s",
                    tostring(entry.Cooldown),
                    tostring(entry.CooldownType or "Unknown")
                )
            end
        else
            lines[#lines + 1] = "• " .. id
        end

        if i < math.min(#ids, limit) then
            lines[#lines + 1] = ""
        end
    end

    if #ids > limit then
        lines[#lines + 1] = "... +" .. tostring(#ids - limit) .. " more"
    end

    return table.concat(lines, "\n")
end

local function timingText(unit, stats)
    if type(unit.SkillInfo) ~= "table" or type(stats) ~= "table" then
        return "No SkillInfo timing found."
    end

    local skillName = stats.SkillName
    local timing = skillName and unit.SkillInfo[skillName]

    if type(timing) ~= "table" then
        return "No timing entry for " .. tostring(skillName or "unknown skill")
    end

    local ticks = tonumber(timing.Ticks) or 1
    local before = tonumber(timing.DelayBeforeAttack) or 0
    local between = tonumber(timing.DelayBetweenTicks) or 0
    local after = tonumber(timing.DelayAfterAttack) or 0
    local attackSpeed = tonumber(timing.AttackSpeed)
    local animationWindow = before + math.max(0, ticks - 1) * between + after

    local lines = {
        "Skill: " .. tostring(skillName),
        "Attack name: " .. tostring(stats.DisplayName or "?"),
        "Ticks: " .. tostring(ticks),
        "Delay before: " .. nfmt(before, 3) .. "s",
        "Delay between ticks: " .. nfmt(between, 3) .. "s",
        "Delay after: " .. nfmt(after, 3) .. "s",
        "Animation/tick window: " .. nfmt(animationWindow, 3) .. "s",
        "Configured SPA: " .. nfmt(stats.SPA, 3) .. "s",
    }

    if attackSpeed then
        lines[#lines + 1] = "AttackSpeed: " .. nfmt(attackSpeed, 3)
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Note: Stat DPS = Damage / SPA. Ticks are shown for timing/mechanics and are not multiplied into Damage in V1."

    return table.concat(lines, "\n")
end

local function placementHint(stats)
    if type(stats) ~= "table" then return "No placement data." end

    local hitbox = tostring(stats.HitboxType or "Unknown")
    local range = tonumber(stats.Range) or 0
    local size = tonumber(stats.HitboxSize) or 0
    local lower = hitbox:lower()

    local hint

    if lower:find("cone", 1, true) then
        hint = "Face the cone along the direction enemies travel. Prefer long straight/curved segments where the path stays inside the cone, rather than placing perpendicular to the path."
    elseif lower:find("line", 1, true) then
        hint = "Align the line with the path so enemies travel through the hitbox lengthwise. Long straight sections and path overlaps are high-value positions."
    elseif lower:find("circle", 1, true) then
        hint = "Prefer corners, U-turns, intersections, or path sections that remain inside range for a long time. For AoE, favor positions where multiple enemies naturally bunch together."
    elseif lower:find("full", 1, true) then
        hint = "Range coverage matters more than aim direction. Favor central positions that maximize total path length inside range."
    else
        hint = "Maximize enemy time-inside-range. V2 will score actual path coverage and expected attack count from the current map."
    end

    return table.concat({
        "Hitbox: " .. hitbox,
        "Range: " .. nfmt(range, 1),
        "AoE/Hitbox size: " .. nfmt(size, 1),
        "",
        hint,
    }, "\n")
end

local function upgradeTableText(unit)
    if not unit then return "No unit selected." end

    local maxU = getMaxUpgrade(unit)
    local lines = {
        "Upgrade | Cost | DPS | ΔDPS | ΔDPS/$ | Total Cost | DPS/Total$",
    }

    for u = 0, maxU do
        local info = getUpgrade(unit, u)
        if info then
            local dps = statDPS(info)
            local gain, marginal = marginalValue(unit, u)
            local totalCost = cumulativeCost(unit, u)
            local totalEff = totalCost > 0 and dps / totalCost or 0

            lines[#lines + 1] = string.format(
                "U%d | %s | %s | %s | %.6f | %s | %.6f",
                u,
                money(info.Cost),
                nfmt(dps, 2),
                (gain >= 0 and "+" or "") .. nfmt(gain, 2),
                marginal,
                money(totalCost),
                totalEff
            )
        end
    end

    return table.concat(lines, "\n")
end

local function bestMarginalText(unit)
    if not unit then return "No unit selected." end

    local rows = {}
    local maxU = getMaxUpgrade(unit)

    for u = 0, maxU do
        local gain, eff, cost = marginalValue(unit, u)
        rows[#rows + 1] = {
            Upgrade = u,
            Gain = gain,
            Efficiency = eff,
            Cost = cost,
        }
    end

    table.sort(rows, function(a, b)
        return a.Efficiency > b.Efficiency
    end)

    local lines = {
        "Highest marginal Stat-DPS value steps:",
    }

    for i = 1, math.min(5, #rows) do
        local row = rows[i]
        lines[#lines + 1] = string.format(
            "%d) U%d | %s | ΔDPS %s | ΔDPS/$ %.6f",
            i,
            row.Upgrade,
            money(row.Cost),
            (row.Gain >= 0 and "+" or "") .. nfmt(row.Gain, 2),
            row.Efficiency
        )
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Important: upgrades are sequential. This ranking shows efficiency of each step, not a recommendation to skip earlier upgrades. Passive/ability value is not yet included in this V1 score."

    return table.concat(lines, "\n")
end

local unitNames = sortedKeys(DB.Units, false)

if #unitNames == 0 then
    error("[AE Assistant] units.json loaded but no units were found", 0)
end

local okRay, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)

if not okRay then
    error("[AE Assistant] Rayfield failed: " .. tostring(Rayfield), 0)
end

local Window = Rayfield:CreateWindow({
    Name = "Anime Expeditions | Strategy Assistant V1",
    Icon = 0,
    LoadingTitle = "AE Strategy Assistant",
    LoadingSubtitle = "Database Analyzer V1",
    ShowText = "AE Assist",
    Theme = "Default",
    ToggleUIKeybind = "K",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "AE_Strategy_Assistant",
        FileName = "settings",
    },
})

local AnalyzerTab = Window:CreateTab("Unit Analyzer", 0)
local ValueTab = Window:CreateTab("Money Value", 0)
local DatabaseTab = Window:CreateTab("Database", 0)

local State = {
    UnitName = unitNames[1],
    Upgrade = 0,
}

local Summary = AnalyzerTab:CreateParagraph({
    Title = "Unit",
    Content = "Loading...",
})

local StatsParagraph = AnalyzerTab:CreateParagraph({
    Title = "Stats",
    Content = "",
})

local TimingParagraph = AnalyzerTab:CreateParagraph({
    Title = "Attack Timing",
    Content = "",
})

local PlacementParagraph = AnalyzerTab:CreateParagraph({
    Title = "Placement Guidance",
    Content = "",
})

local MechanicsParagraph = AnalyzerTab:CreateParagraph({
    Title = "Passives / Abilities",
    Content = "",
})

local ValueParagraph = ValueTab:CreateParagraph({
    Title = "Upgrade Value",
    Content = "",
})

local RankingParagraph = ValueTab:CreateParagraph({
    Title = "Marginal Efficiency",
    Content = "",
})

local function currentUnit()
    return DB.Units[State.UnitName]
end

local function refresh()
    local unit = currentUnit()
    if not unit then return end

    State.Upgrade = closestUpgrade(unit, State.Upgrade)

    local stats = getUpgrade(unit, State.Upgrade)
    if not stats then return end

    local dps = statDPS(stats)
    local totalCost = cumulativeCost(unit, State.Upgrade)
    local totalEff = totalCost > 0 and dps / totalCost or 0
    local gain, marginal, upgradeCost = marginalValue(unit, State.Upgrade)
    local maxU = getMaxUpgrade(unit)

    Summary:Set({
        Title = tostring(unit.DisplayName or State.UnitName),
        Content = string.format(
            "Asset: %s\nRarity: %s | Element: %s | Archetype: %s\nPlacement: %s | Limit: %s\nUpgrade: %d / %d",
            tostring(unit.Asset or State.UnitName),
            tostring(unit.Rarity or "?"),
            tostring(unit.Element or "?"),
            tostring(unit.Archetype or "?"),
            tostring(unit.PlacementType or "?"),
            tostring(unit.PlacementLimit or "?"),
            State.Upgrade,
            maxU
        ),
    })

    StatsParagraph:Set({
        Title = "U" .. tostring(State.Upgrade) .. " | " .. tostring(stats.DisplayName or stats.SkillName or "Attack"),
        Content = string.format(
            "Damage: %s\nSPA: %ss\nStat DPS: %s\nRange: %s\nHitbox: %s | Size: %s\nCrit: %s%% | Crit Damage: %s%%\nDoT Damage field: %s\n\nUpgrade/Placement Cost: %s\nCumulative Cost: %s\nStat DPS / Total $: %.6f\nMarginal ΔDPS: %s\nMarginal ΔDPS/$: %.6f",
            nfmt(stats.Damage, 2),
            nfmt(stats.SPA, 3),
            nfmt(dps, 2),
            nfmt(stats.Range, 2),
            tostring(stats.HitboxType or "?"),
            nfmt(stats.HitboxSize, 2),
            nfmt(stats.CritChance, 2),
            nfmt(stats.CritDamage, 2),
            nfmt(stats.DoTDamage, 2),
            money(upgradeCost),
            money(totalCost),
            totalEff,
            (gain >= 0 and "+" or "") .. nfmt(gain, 2),
            marginal
        ),
    })

    TimingParagraph:Set({
        Title = "Attack Timing",
        Content = timingText(unit, stats),
    })

    PlacementParagraph:Set({
        Title = "Placement Guidance (V1 heuristic)",
        Content = placementHint(stats),
    })

    local passiveIds = listValues(stats.Passives)
    local abilityIds = listValues(stats.Abilities)

    MechanicsParagraph:Set({
        Title = "Mechanics unlocked at U" .. tostring(State.Upgrade),
        Content = mechanicBlock("Passives", passiveIds, DB.Passives, 4)
            .. "\n\n"
            .. mechanicBlock("Abilities", abilityIds, DB.Abilities, 4),
    })

    ValueParagraph:Set({
        Title = tostring(unit.DisplayName or State.UnitName) .. " | Upgrade Value Table",
        Content = upgradeTableText(unit),
    })

    RankingParagraph:Set({
        Title = "Stat-DPS Efficiency",
        Content = bestMarginalText(unit),
    })
end

AnalyzerTab:CreateDropdown({
    Name = "Unit",
    Options = unitNames,
    CurrentOption = {State.UnitName},
    MultipleOptions = false,
    Flag = "AEUnit",
    Callback = function(options)
        local value = type(options) == "table" and options[1] or options
        if value and DB.Units[value] then
            State.UnitName = value
            State.Upgrade = 0
            refresh()
        end
    end,
})

AnalyzerTab:CreateSlider({
    Name = "Upgrade",
    Range = {0, 15},
    Increment = 1,
    Suffix = "",
    CurrentValue = 0,
    Flag = "AEUpgrade",
    Callback = function(value)
        local unit = currentUnit()
        if unit then
            State.Upgrade = closestUpgrade(unit, value)
            refresh()
        end
    end,
})

AnalyzerTab:CreateButton({
    Name = "Previous Upgrade",
    Callback = function()
        State.Upgrade = math.max(0, State.Upgrade - 1)
        refresh()
    end,
})

AnalyzerTab:CreateButton({
    Name = "Next Upgrade",
    Callback = function()
        local unit = currentUnit()
        if unit then
            State.Upgrade = math.min(getMaxUpgrade(unit), State.Upgrade + 1)
            refresh()
        end
    end,
})

ValueTab:CreateParagraph({
    Title = "How V1 scores money value",
    Content = "Stat DPS = Damage / SPA\nMarginal ΔDPS/$ = (new Stat DPS - previous Stat DPS) / current upgrade cost\nTotal DPS/$ = current Stat DPS / cumulative placement+upgrade cost\n\nV1 intentionally does not assign numeric value to passives, abilities, crowd-control, buffs, multi-hit behavior or map coverage yet. Those will be added to Effective DPS and Strategy Score later.",
})

DatabaseTab:CreateParagraph({
    Title = "Database loaded from GitHub",
    Content = string.format(
        "Units: %d\nAbilities: %d\nPassives: %d\nStatus Effects: %d\nEnemies: %d\nMaps/top-level entries: %d\n\nSource:\nZEBUXHUBBY/main/AE_DB\n\nThe database is downloaded fresh when this script starts.",
        tableCount(DB.Units),
        tableCount(DB.Abilities),
        tableCount(DB.Passives),
        tableCount(DB.StatusEffects),
        tableCount(DB.Enemies),
        tableCount(DB.Maps)
    ),
})

DatabaseTab:CreateButton({
    Name = "Copy stable loader",
    Callback = function()
        local loader = 'loadstring(game:HttpGet("https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Assistant/main.lua"))()'

        if setclipboard then
            setclipboard(loader)
            Rayfield:Notify({
                Title = "Copied",
                Content = "Stable loader copied to clipboard.",
                Duration = 4,
                Image = 0,
            })
        else
            Rayfield:Notify({
                Title = "Clipboard unavailable",
                Content = loader,
                Duration = 8,
                Image = 0,
            })
        end
    end,
})

DatabaseTab:CreateButton({
    Name = "Unload flag (for re-execute)",
    Callback = function()
        if getgenv then
            getgenv().AE_ASSISTANT_LOADED = nil
        end
        Rayfield:Notify({
            Title = "Reload enabled",
            Content = "You can execute the loader again after closing this UI.",
            Duration = 4,
            Image = 0,
        })
    end,
})

refresh()

pcall(function()
    Rayfield:LoadConfiguration()
end)

notify("AE Assistant V1", "Ready - K to hide/show UI", 6)
print("[AE Assistant] Analyzer V1 ready | Units:", tableCount(DB.Units))