--[[
    Anime Expeditions Assistant | V2 Evidence Team Advisor

    Stable loader after upload:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Assistant/main.lua"))()

    Design rule: NO SILENT GUESSING.
    - Direct DB fields are labelled EXACT.
    - Math derived from direct fields is labelled DERIVED.
    - Runtime helper output is used only after structural validation.
    - Missing stage/path/economy facts remain UNKNOWN and are not invented.
    - Exact clear time / win chance are not claimed until the required evidence exists.

    V2 scope:
    - Read the in-game Shared.Information database (fresh for the current server).
    - Scan owned units and the equipped hotbar using validated profile structures.
    - Index stages from the in-game Maps module hierarchy.
    - Extract explicit stage restrictions, enemies, elements, speed, shields,
      resistances, mechanics, wave count and economy fields when present.
    - Hard-filter illegal units, including Farm units only when the stage data
      explicitly prohibits them.
    - Compare current team vs a recommended owned-unit team using transparent,
      lexicographic objectives instead of a hidden single score.
    - Compare exact DB raw DPS/cost curves, max raw DPS ceiling, explicit counters,
      element coverage, CC, buffs/debuffs and documented ability cooldowns.

    This is an advisory/read-only build. It does not place, upgrade, sell or fire
    gameplay remotes.
]]

local VERSION = "2.0.1-scanfix"
local EXPECTED_PLACE_ID = 84515722934860
local RAW_ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_DB/"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer

local ENV = getgenv and getgenv() or _G

-- Replace an older instance instead of being blocked by the old V1 flag.
if type(ENV.AE_ASSISTANT) == "table" and type(ENV.AE_ASSISTANT.Destroy) == "function" then
    pcall(ENV.AE_ASSISTANT.Destroy)
end
ENV.AE_ASSISTANT_LOADED = nil

local App = {
    Version = VERSION,
    Connections = {},
    Destroyed = false,
    Evidence = {},
    Unknowns = {},
    Diagnostics = {},
}
ENV.AE_ASSISTANT = App
ENV.AE_ASSISTANT_LOADED = true

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 6,
        })
    end)
end

local function warnf(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    warn("[AE Assistant] " .. table.concat(parts, " "))
end

local function printf(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    print("[AE Assistant] " .. table.concat(parts, " "))
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function normalize(value)
    return trim(value):lower():gsub("[^%w]", "")
end

local function round(value, digits)
    local p = 10 ^ (digits or 0)
    return math.floor((tonumber(value) or 0) * p + 0.5) / p
end

local function formatNumber(value, digits)
    value = tonumber(value)
    if not value then
        return "?"
    end
    digits = digits or 2
    local abs = math.abs(value)
    if abs >= 1000000000 then
        return string.format("%.2fB", value / 1000000000)
    elseif abs >= 1000000 then
        return string.format("%.2fM", value / 1000000)
    elseif abs >= 1000 then
        return string.format("%.2fK", value / 1000)
    end
    local fmt = "%0." .. tostring(digits) .. "f"
    local text = string.format(fmt, value)
    text = text:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
    return text
end

local function countKeys(tbl)
    if type(tbl) ~= "table" then
        return 0
    end
    local n = 0
    for _ in pairs(tbl) do
        n = n + 1
    end
    return n
end

local function shallowCopy(tbl)
    local out = {}
    if type(tbl) == "table" then
        for k, v in pairs(tbl) do
            out[k] = v
        end
    end
    return out
end

local function sortedKeys(tbl, sorter)
    local keys = {}
    if type(tbl) == "table" then
        for key in pairs(tbl) do
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, sorter or function(a, b)
        local na, nb = tonumber(a), tonumber(b)
        if na and nb then
            return na < nb
        end
        return tostring(a) < tostring(b)
    end)
    return keys
end

local function tableToSet(value)
    local out = {}
    if type(value) == "table" then
        for k, v in pairs(value) do
            if type(k) == "number" or tonumber(k) then
                if type(v) == "string" or type(v) == "number" then
                    out[normalize(v)] = tostring(v)
                end
            elseif v == true then
                out[normalize(k)] = tostring(k)
            elseif type(v) == "string" or type(v) == "number" then
                out[normalize(v)] = tostring(v)
            end
        end
    elseif type(value) == "string" or type(value) == "number" then
        out[normalize(value)] = tostring(value)
    end
    return out
end

local function uniqueArray(list)
    local out, seen = {}, {}
    for _, value in ipairs(list or {}) do
        local key = tostring(value)
        if not seen[key] then
            seen[key] = true
            out[#out + 1] = value
        end
    end
    return out
end

local function getCI(tbl, names)
    if type(tbl) ~= "table" then
        return nil, nil
    end
    local wanted = {}
    for _, name in ipairs(names) do
        wanted[normalize(name)] = true
    end
    for key, value in pairs(tbl) do
        if wanted[normalize(key)] then
            return value, key
        end
    end
    return nil, nil
end

local function safeRequire(instance)
    if not instance or not instance:IsA("ModuleScript") then
        return nil, "missing ModuleScript"
    end
    local ok, result = pcall(require, instance)
    if not ok then
        return nil, tostring(result)
    end
    return result, nil
end

local function safeJsonGet(url)
    local ok, body = pcall(function()
        return game:HttpGet(url)
    end)
    if not ok then
        return nil, tostring(body)
    end
    local decodedOk, decoded = pcall(function()
        return HttpService:JSONDecode(body)
    end)
    if not decodedOk then
        return nil, tostring(decoded)
    end
    return decoded, nil
end

local function walkTable(root, callback, maxDepth)
    if type(root) ~= "table" then
        return
    end
    maxDepth = maxDepth or 8
    local seen = {}

    local function visit(tbl, path, depth)
        if depth > maxDepth or seen[tbl] then
            return
        end
        seen[tbl] = true
        for key, value in pairs(tbl) do
            local nextPath = path == "" and tostring(key) or (path .. "." .. tostring(key))
            callback(nextPath, key, value, tbl, depth)
            if type(value) == "table" then
                visit(value, nextPath, depth + 1)
            end
        end
    end

    visit(root, "", 0)
end

local function sanitize(value, seen, depth)
    seen = seen or {}
    depth = depth or 0
    if depth > 12 then
        return "<MAX_DEPTH>"
    end
    local kind = typeof(value)
    if kind == "nil" or kind == "string" or kind == "number" or kind == "boolean" then
        return value
    elseif kind == "Vector3" then
        return {__type = "Vector3", x = value.X, y = value.Y, z = value.Z}
    elseif kind == "CFrame" then
        return {__type = "CFrame", components = {value:GetComponents()}}
    elseif kind == "Color3" then
        return {__type = "Color3", r = value.R, g = value.G, b = value.B}
    elseif kind == "Instance" then
        return {__type = "Instance", path = value:GetFullName(), class = value.ClassName}
    elseif kind == "function" then
        return "<FUNCTION>"
    elseif kind ~= "table" then
        return tostring(value)
    end
    if seen[value] then
        return "<CYCLE>"
    end
    seen[value] = true
    local out = {}
    for key, item in pairs(value) do
        out[tostring(key)] = sanitize(item, seen, depth + 1)
    end
    seen[value] = nil
    return out
end

local function writeDiagnostic(name, data)
    if not writefile then
        return false, "writefile unavailable"
    end
    if makefolder then
        pcall(makefolder, "AE_Assistant")
    end
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(sanitize(data))
    end)
    if not ok then
        return false, tostring(encoded)
    end
    local path = "AE_Assistant/" .. name
    local wrote, err = pcall(writefile, path, encoded)
    return wrote, wrote and path or tostring(err)
end

-- ============================================================
-- DATABASE LOAD
-- ============================================================

local Database = {
    Source = {},
    Errors = {},
}

local Shared = ReplicatedStorage:FindFirstChild("Shared")
local InformationRoot = Shared and Shared:FindFirstChild("Information")
local SheetRoot = ReplicatedStorage:FindFirstChild("SheetSyncedModules")
local FusionPackage = ReplicatedStorage:FindFirstChild("FusionPackage")
local ActionsRoot = FusionPackage and FusionPackage:FindFirstChild("Actions")

local CORE_MODULES = {
    "Units",
    "Maps",
    "Enemies",
    "EnemyTypes",
    "Elements",
    "Abilities",
    "Passives",
    "StatusEffects",
    "DamageTypes",
    "Gamemodes",
    "GameMechanics",
    "StageDrops",
}

for _, name in ipairs(CORE_MODULES) do
    local result, err
    local module = InformationRoot and InformationRoot:FindFirstChild(name)
    if module then
        result, err = safeRequire(module)
    end
    if type(result) == "table" and countKeys(result) > 0 then
        Database[name] = result
        Database.Source[name] = module:GetFullName()
    else
        local fallback, fallbackErr = safeJsonGet(RAW_ROOT .. ({
            Units = "units.json",
            Enemies = "enemies.json",
            EnemyTypes = "enemy_types.json",
            Elements = "elements.json",
            Abilities = "abilities.json",
            Passives = "passives.json",
            StatusEffects = "status_effects.json",
            DamageTypes = "damage_types.json",
            Gamemodes = "gamemodes.json",
            GameMechanics = "game_mechanics.json",
            StageDrops = "stage_drops.json",
            Maps = "maps_full.json",
        })[name])
        if type(fallback) == "table" then
            Database[name] = fallback
            Database.Source[name] = "GitHub AE_DB fallback"
        else
            Database.Errors[name] = err or fallbackErr or "unavailable"
        end
    end
end

Database.Scaling = {}
if SheetRoot then
    for _, name in ipairs({
        "StoryScaling",
        "RaidScaling",
        "InfiniteScaling",
        "MasteryScaling",
        "TournamentScaling",
        "RegularChallengeScaling",
        "DailyChallengeScaling",
        "WeeklyChallengeScaling",
        "AllScaling",
    }) do
        local data = safeRequire(SheetRoot:FindFirstChild(name))
        if type(data) == "table" and countKeys(data) > 0 then
            Database.Scaling[name] = data
        end
    end
end

local UnitsDB = Database.Units or {}
local MapsDB = Database.Maps or {}
local EnemiesModule = Database.Enemies or {}
local EnemyList = EnemiesModule.List or EnemiesModule
local AbilitiesDB = (Database.Abilities and (Database.Abilities.Abilities or Database.Abilities)) or {}
local PassivesDB = (Database.Passives and (Database.Passives.Passives or Database.Passives)) or {}
local EffectsDB = (Database.StatusEffects and (Database.StatusEffects.Effects or Database.StatusEffects)) or {}
local ElementData = (Database.Elements and (Database.Elements.ElementData or Database.Elements)) or {}

if countKeys(UnitsDB) == 0 then
    notify("AE Assistant", "Units database unavailable; advisor cannot run.", 10)
    warnf("Units database unavailable")
    ENV.AE_ASSISTANT_LOADED = nil
    return
end

local UnitNames = sortedKeys(UnitsDB, function(a, b)
    local da = tostring((UnitsDB[a] or {}).DisplayName or a)
    local db = tostring((UnitsDB[b] or {}).DisplayName or b)
    return da:lower() < db:lower()
end)

local UnitAlias = {}
for asset, info in pairs(UnitsDB) do
    UnitAlias[normalize(asset)] = asset
    if type(info) == "table" and info.DisplayName then
        UnitAlias[normalize(info.DisplayName)] = asset
    end
end

local ElementNames = {}
for key in pairs(ElementData) do
    ElementNames[normalize(key)] = tostring(key)
end

-- Enemy aliases and explicit speed distribution.
local EnemyAlias = {}
local EnemySpeeds = {}
for key, info in pairs(EnemyList or {}) do
    EnemyAlias[normalize(key)] = key
    if type(info) == "table" then
        local display = getCI(info, {"DisplayName", "Name"})
        if type(display) == "string" then
            EnemyAlias[normalize(display)] = key
        end
        local speed = getCI(info, {"Speed", "MoveSpeed", "WalkSpeed", "BaseSpeed"})
        if type(speed) == "number" then
            EnemySpeeds[#EnemySpeeds + 1] = speed
        end
    end
end

table.sort(EnemySpeeds)
local function percentile(sorted, p)
    if #sorted == 0 then
        return nil
    end
    local index = math.clamp(math.ceil(#sorted * p), 1, #sorted)
    return sorted[index]
end
local SPEED_Q25 = percentile(EnemySpeeds, 0.25)
local SPEED_Q50 = percentile(EnemySpeeds, 0.50)
local SPEED_Q75 = percentile(EnemySpeeds, 0.75)

-- ============================================================
-- DESCRIPTION / CAPABILITY PARSING
-- ============================================================

local function parameterValue(parameter)
    if type(parameter) ~= "table" then
        return tostring(parameter)
    end
    local minimum = parameter.Min
    local maximum = parameter.Max
    if minimum ~= nil and maximum ~= nil then
        if minimum == maximum then
            return formatNumber(minimum, 3)
        end
        return formatNumber(minimum, 3) .. "-" .. formatNumber(maximum, 3)
    end
    if parameter.Value ~= nil then
        return tostring(parameter.Value)
    end
    return "?"
end

local function renderDescription(entry)
    if type(entry) ~= "table" then
        return ""
    end
    local text = tostring(entry.Description or "")
    for key, parameter in pairs(entry.Parameters or {}) do
        text = text:gsub("%{" .. tostring(key) .. "%}", parameterValue(parameter))
    end
    return text
end

local CC_TOKENS = {
    stun = "Stun",
    slow = "Slow",
    freeze = "Freeze",
    rewind = "Rewind",
    shadowrewind = "ShadowRewind",
    stagger = "Stagger",
    root = "Root",
    knockback = "Knockback",
    timestop = "TimeStop",
    dismember = "Dismember",
}

local DOT_TOKENS = {
    fire = "Fire",
    bleed = "Bleed",
    blackfire = "BlackFire",
    manaburn = "ManaBurn",
    austereflames = "AustereFlames",
}

local function parseCapabilityEntry(entry, sourceType, sourceName)
    local description = renderDescription(entry)
    local lower = description:lower()
    local result = {
        SourceType = sourceType,
        SourceName = sourceName,
        DisplayName = type(entry) == "table" and (entry.DisplayName or sourceName) or sourceName,
        Description = description,
        CCTypes = {},
        DoTTypes = {},
        Tokens = {},
        Buff = false,
        Debuff = false,
        ShieldCounter = false,
        Farm = false,
        Summon = false,
        Transform = false,
        Relocate = false,
        BossSpecific = false,
        Cooldown = type(entry) == "table" and tonumber(entry.Cooldown) or nil,
        CooldownType = type(entry) == "table" and entry.CooldownType or nil,
        AutoUseAllowed = type(entry) == "table" and entry.AutoUseAllowed or nil,
        ExactPeriodicDamage = {},
    }

    for token in description:gmatch("%$([%w_]+)") do
        result.Tokens[normalize(token)] = token
    end

    for token, label in pairs(CC_TOKENS) do
        if result.Tokens[token] or lower:find(token, 1, true) then
            result.CCTypes[label] = true
            result.Debuff = true
        end
    end
    for token, label in pairs(DOT_TOKENS) do
        if result.Tokens[token] or lower:find(token, 1, true) then
            result.DoTTypes[label] = true
            result.Debuff = true
        end
    end

    if result.Tokens.buff or lower:find("increase damage", 1, true) or lower:find("damage buff", 1, true) then
        result.Buff = true
    end
    if result.Tokens.debuff or lower:find("inflict", 1, true) or lower:find("apply $", 1, true) then
        result.Debuff = true
    end
    result.Summon = lower:find("summon", 1, true) ~= nil
    result.Transform = lower:find("transform", 1, true) ~= nil
    result.Relocate = lower:find("relocate", 1, true) ~= nil
    result.BossSpecific = lower:find("boss", 1, true) ~= nil

    local farmWords = {" yen", "$yen", "income", "earn ", "money", "farm unit", "$farm"}
    for _, word in ipairs(farmWords) do
        if lower:find(word, 1, true) then
            result.Farm = true
            break
        end
    end

    if lower:find("shield", 1, true) then
        local verbs = {"break", "remove", "ignore", "pierce", "damage shield", "shields every tick"}
        for _, verb in ipairs(verbs) do
            if lower:find(verb, 1, true) then
                result.ShieldCounter = true
                break
            end
        end
    end

    -- Only recognize highly explicit periodic-damage wording. This is reported as
    -- conditional potential and is not silently added to base Stat DPS.
    for percent, seconds in lower:gmatch("take%s+([%d%.]+)%%%s+of%s+this%s+unit['’]s%s+current%s+damage%s+every%s+([%d%.]+)%s+second") do
        percent, seconds = tonumber(percent), tonumber(seconds)
        if percent and seconds and seconds > 0 then
            result.ExactPeriodicDamage[#result.ExactPeriodicDamage + 1] = {
                Percent = percent,
                Seconds = seconds,
                RatioPerSecond = percent / 100 / seconds,
                Evidence = description,
            }
        end
    end
    for percent, seconds in lower:gmatch("dealing%s+([%d%.]+)%%%s+of%s+this%s+unit['’]s%s+current%s+damage%s+every%s+([%d%.]+)%s+second") do
        percent, seconds = tonumber(percent), tonumber(seconds)
        if percent and seconds and seconds > 0 then
            result.ExactPeriodicDamage[#result.ExactPeriodicDamage + 1] = {
                Percent = percent,
                Seconds = seconds,
                RatioPerSecond = percent / 100 / seconds,
                Evidence = description,
            }
        end
    end

    return result
end

local function mergeSets(target, source)
    for key, value in pairs(source or {}) do
        target[key] = value
    end
end

-- ============================================================
-- ACTUAL STAT HELPER (STRUCTURALLY VALIDATED ONLY)
-- ============================================================

local CalcStatsFunction = nil
local CalcPattern = nil
if ActionsRoot then
    local candidate = safeRequire(ActionsRoot:FindFirstChild("GetCalculatedStatsFromData"))
    if type(candidate) == "function" then
        CalcStatsFunction = candidate
    end
end

local function extractStatsTable(result)
    if type(result) ~= "table" then
        return nil
    end
    local current = getCI(result, {"CurrentStats", "Stats"})
    if type(current) == "table" then
        result = current
    end
    local damage = getCI(result, {"Damage"})
    local spa = getCI(result, {"SPA", "AttackSpeed", "Cooldown"})
    local range = getCI(result, {"Range", "RNG"})
    if type(damage) == "number" and type(spa) == "number" and spa > 0 then
        return result
    end
    if type(range) == "number" and (type(damage) == "number" or type(spa) == "number") then
        return result
    end
    return nil
end

local CALC_PATTERNS = {
    {
        Name = "record, baseStats",
        Call = function(fn, record, info, baseStats, upgrade)
            return fn(record, baseStats)
        end,
    },
    {
        Name = "baseStats, record",
        Call = function(fn, record, info, baseStats, upgrade)
            return fn(baseStats, record)
        end,
    },
    {
        Name = "record, baseStats, upgrade",
        Call = function(fn, record, info, baseStats, upgrade)
            return fn(record, baseStats, upgrade)
        end,
    },
    {
        Name = "record, info, baseStats, upgrade",
        Call = function(fn, record, info, baseStats, upgrade)
            return fn(record, info, baseStats, upgrade)
        end,
    },
    {
        Name = "info, record, baseStats, upgrade",
        Call = function(fn, record, info, baseStats, upgrade)
            return fn(info, record, baseStats, upgrade)
        end,
    },
}

local function statsDiffer(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    for _, key in ipairs({"Damage", "SPA", "Range", "RNG"}) do
        local av = tonumber((getCI(a, {key})))
        local bv = tonumber((getCI(b, {key})))
        if av and bv and math.abs(av - bv) > 1e-7 then
            return true
        end
    end
    return false
end

local function ensureCalcPattern(record, info)
    if CalcPattern then
        return true
    end
    if not CalcStatsFunction or type(record) ~= "table" or type(info) ~= "table" then
        return false
    end
    -- numericUpgradeEntries is declared later, so use the raw UpgradeInfo here.
    local raw = {}
    for key, base in pairs(info.UpgradeInfo or {}) do
        local level = tonumber(key)
        if level and type(base) == "table" then
            raw[#raw + 1] = {Level = level, Base = base}
        end
    end
    table.sort(raw, function(a, b) return a.Level < b.Level end)
    if #raw < 2 then
        return false
    end
    local first, last = raw[1], raw[#raw]
    local baseChanged = statsDiffer(first.Base, last.Base)
    if not baseChanged then
        return false
    end
    for _, pattern in ipairs(CALC_PATTERNS) do
        local okA, resultA = pcall(pattern.Call, CalcStatsFunction, record, info, first.Base, first.Level)
        local okB, resultB = pcall(pattern.Call, CalcStatsFunction, record, info, last.Base, last.Level)
        local statsA = okA and extractStatsTable(resultA) or nil
        local statsB = okB and extractStatsTable(resultB) or nil
        if statsA and statsB and statsDiffer(statsA, statsB) then
            CalcPattern = pattern
            return true
        end
    end
    return false
end

local function calculateOwnedStats(record, info, baseStats, upgrade)
    if not ensureCalcPattern(record, info) then
        return nil, nil
    end
    local ok, result = pcall(CalcPattern.Call, CalcStatsFunction, record, info, baseStats, upgrade)
    if ok then
        local stats = extractStatsTable(result)
        if stats then
            return stats, CalcPattern.Name
        end
    end
    return nil, nil
end

-- ============================================================
-- OWNED PROFILE SCANNER
-- ============================================================

local function isOwnedUnitRecord(value)
    if type(value) ~= "table" then
        return false
    end
    local asset = getCI(value, {"Asset", "Unit", "UnitName"})
    if type(asset) ~= "string" or not UnitsDB[asset] then
        return false
    end
    local evidenceFields = {
        "Level", "EXP", "ObtainedAt", "OriginalOwner", "Trait",
        "StatPotential", "Equipment", "Equipped", "Worthiness",
        "TraitPity", "TraitRollAmount", "TotalTakedowns",
    }
    for _, field in ipairs(evidenceFields) do
        if getCI(value, {field}) ~= nil then
            return true
        end
    end
    return false
end

local function collectOwnedRecords(root)
    local out = {}
    local seen = {}
    local pointerSeen = {}

    local function visit(value, path, depth, keyHint)
        if depth > 7 or type(value) ~= "table" or pointerSeen[value] then
            return
        end
        pointerSeen[value] = true
        if isOwnedUnitRecord(value) then
            local asset = getCI(value, {"Asset", "Unit", "UnitName"})
            local id = getCI(value, {"ID", "Id", "UUID", "Guid", "ReplicaID"})
            id = id or keyHint or path
            local unique = tostring(id) .. "|" .. tostring(asset)
            if not seen[unique] then
                seen[unique] = true
                out[#out + 1] = {
                    Asset = asset,
                    ID = tostring(id),
                    Data = value,
                    Path = path,
                }
            end
            return
        end
        for key, item in pairs(value) do
            if type(item) == "table" then
                visit(item, path .. "." .. tostring(key), depth + 1, key)
            end
        end
    end

    visit(root, "Profile", 0, nil)
    return out
end

local function locateNamedTable(root, names, maxDepth)
    if type(root) ~= "table" then
        return nil, nil
    end
    local wanted = {}
    for _, name in ipairs(names) do
        wanted[normalize(name)] = true
    end
    local seen = {}
    local found, foundPath
    local function visit(tbl, path, depth)
        if found or depth > (maxDepth or 6) or seen[tbl] then
            return
        end
        seen[tbl] = true
        for key, value in pairs(tbl) do
            local nextPath = path .. "." .. tostring(key)
            if wanted[normalize(key)] and type(value) == "table" then
                found, foundPath = value, nextPath
                return
            end
            if type(value) == "table" then
                visit(value, nextPath, depth + 1)
            end
        end
    end
    visit(root, "Root", 0)
    return found, foundPath
end

local function scoreProfileCandidate(candidate)
    if type(candidate) ~= "table" then
        return -1, nil, {}, nil
    end
    local roots = {candidate}
    if type(candidate.Data) == "table" then
        roots[#roots + 1] = candidate.Data
    end
    if type(candidate.ProfileData) == "table" then
        roots[#roots + 1] = candidate.ProfileData
    end

    local bestScore, bestRoot, bestOwned, bestHotbar = -1, nil, {}, nil
    for _, root in ipairs(roots) do
        local owned = collectOwnedRecords(root)
        local hotbar = locateNamedTable(root, {"HotbarData", "Hotbar"}, 6)
        local unitData = locateNamedTable(root, {"UnitData", "Units"}, 6)
        local score = math.min(#owned, 30)
        if #owned > 0 then
            score = score + 10
        end
        if type(unitData) == "table" then
            score = score + 8
        end
        if type(hotbar) == "table" then
            score = score + 8
        end
        if getCI(root, {"ProfileData"}) ~= nil then
            score = score + 2
        end
        if getCI(root, {"ItemData"}) ~= nil then
            score = score + 1
        end
        if score > bestScore then
            bestScore, bestRoot, bestOwned, bestHotbar = score, root, owned, hotbar
        end
    end
    return bestScore, bestRoot, bestOwned, bestHotbar
end

local function inspectProviderResult(result, source, candidates)
    if type(result) ~= "table" then
        return
    end
    local score, root, owned, hotbar = scoreProfileCandidate(result)
    if score >= 10 and #owned > 0 then
        candidates[#candidates + 1] = {
            Score = score,
            Root = root,
            Owned = owned,
            Hotbar = hotbar,
            Source = source,
        }
    end

    local seen = {}
    local function searchNested(tbl, path, depth)
        if depth > 4 or seen[tbl] then
            return
        end
        seen[tbl] = true
        for key, value in pairs(tbl) do
            if type(value) == "table" then
                local nestedScore, nestedRoot, nestedOwned, nestedHotbar = scoreProfileCandidate(value)
                if nestedScore >= 10 and #nestedOwned > 0 then
                    candidates[#candidates + 1] = {
                        Score = nestedScore,
                        Root = nestedRoot,
                        Owned = nestedOwned,
                        Hotbar = nestedHotbar,
                        Source = source .. "." .. tostring(key),
                    }
                end
                searchNested(value, path .. "." .. tostring(key), depth + 1)
            end
        end
    end
    searchNested(result, source, 0)
end

local function callProfileProvider(provider, source, candidates)
    if type(provider) == "table" then
        inspectProviderResult(provider, source, candidates)
        for key, method in pairs(provider) do
            if type(method) == "function" then
                local nk = normalize(key)
                if nk == "get" or nk == "fetch" or nk == "getdata" or nk == "getprofiledata" or nk == "fetchprofiledata" then
                    for _, args in ipairs({{}, {LocalPlayer}, {LocalPlayer.UserId}, {LocalPlayer.Name}}) do
                        local ok, result = pcall(method, table.unpack(args))
                        if ok then
                            inspectProviderResult(result, source .. "." .. tostring(key), candidates)
                        end
                        local selfArgs = {provider}
                        for _, arg in ipairs(args) do selfArgs[#selfArgs + 1] = arg end
                        local selfOk, selfResult = pcall(method, table.unpack(selfArgs))
                        if selfOk then
                            inspectProviderResult(selfResult, source .. "." .. tostring(key) .. "(self)", candidates)
                        end
                    end
                end
            end
        end
    elseif type(provider) == "function" then
        for index, args in ipairs({{}, {LocalPlayer}, {LocalPlayer.UserId}, {LocalPlayer.Name}}) do
            local ok, result = pcall(provider, table.unpack(args))
            if ok then
                inspectProviderResult(result, source .. " call#" .. tostring(index), candidates)
            end
        end
    end
end

local function scanOwnedProfile(progress)
    progress = progress or function() end

    -- IMPORTANT:
    -- Do not call FetchProfileData / player lookup helpers here. During testing
    -- those helpers accepted several argument shapes and invalid probes caused
    -- the game's own "Could not find player to look up..." warnings.
    -- We already know the client keeps the replicated profile + HotbarData in
    -- memory, so scan those structures read-only instead.
    if type(getgc) ~= "function" then
        return {
            Found = false,
            Source = "none",
            Owned = {},
            CurrentTeam = {},
            Unknown = "getgc is unavailable; safe owned-unit scan cannot inspect replicated client tables.",
        }
    end

    progress("Reading client replica tables...")
    local ok, objects = pcall(getgc, true)
    if not ok or type(objects) ~= "table" then
        return {
            Found = false,
            Source = "none",
            Owned = {},
            CurrentTeam = {},
            Unknown = "getgc failed while reading client replica tables.",
        }
    end

    local bestOwned = {}
    local bestRoot = nil
    local bestPath = nil
    local hotbarData = nil
    local hotbarSource = nil
    local inspected = 0

    local function collectDirect(container, path)
        if type(container) ~= "table" then
            return {}
        end
        local out, seen = {}, {}
        for key, value in pairs(container) do
            if isOwnedUnitRecord(value) then
                local asset = getCI(value, {"Asset", "Unit", "UnitName"})
                local id = getCI(value, {"ID", "Id", "UUID", "Guid", "ReplicaID"}) or key
                local unique = tostring(id) .. "|" .. tostring(asset)
                if not seen[unique] then
                    seen[unique] = true
                    out[#out + 1] = {
                        Asset = asset,
                        ID = tostring(id),
                        Data = value,
                        Path = tostring(path) .. "." .. tostring(key),
                    }
                end
            end
        end
        return out
    end

    local function considerOwned(container, path)
        local records = collectDirect(container, path)
        if #records > #bestOwned then
            bestOwned = records
            bestRoot = container
            bestPath = path
        end
        return #records
    end

    -- Pass 1: inspect replica-shaped tables only. This is much faster than
    -- recursively scoring every GC table and also finds HotbarData even when it
    -- lives in a different replica from the player's owned-unit inventory.
    for _, object in ipairs(objects) do
        if type(object) == "table" then
            local token = rawget(object, "Token")
            local data = rawget(object, "Data")

            if token == "HotbarData" and type(data) == "table" then
                local slots = getCI(data, {"Slots"})
                if type(slots) == "table" then
                    hotbarData = slots
                    hotbarSource = "getgc replica Token=HotbarData.Data.Slots"
                end
            end

            if type(data) == "table" then
                considerOwned(data, "Replica.Data")

                -- Player profile data stores owned assets in a child table.
                -- Search only one child level; no deep recursive crawl.
                for key, child in pairs(data) do
                    if type(child) == "table" then
                        local hits = considerOwned(child, "Replica.Data." .. tostring(key))
                        if hits > 0 and hits >= #bestOwned then
                            bestRoot = child
                            bestPath = "Replica.Data." .. tostring(key)
                        end
                    end
                end
            end

            -- Some executors expose the data table itself rather than its
            -- replica wrapper. A direct check is cheap and catches that case.
            considerOwned(object, "getgc.table")
        end

        inspected += 1
        if inspected % 4000 == 0 then
            progress(string.format("Scanning client tables... %d / %d", inspected, #objects))
            task.wait()
        end
    end

    if #bestOwned == 0 then
        return {
            Found = false,
            Source = "getgc replica scan",
            Owned = {},
            CurrentTeam = {},
            CandidateCount = 0,
            Unknown = "No owned-unit container matched the validated Unit record structure.",
        }
    end

    progress(string.format("Owned inventory found: %d records. Resolving hotbar...", #bestOwned))

    local byID = {}
    local byAsset = {}
    for _, record in ipairs(bestOwned) do
        byID[normalize(record.ID)] = record
        byAsset[normalize(record.Asset)] = byAsset[normalize(record.Asset)] or {}
        table.insert(byAsset[normalize(record.Asset)], record)
    end

    local currentTeam = {}
    local currentSeen = {}
    local function addCurrent(record, slot)
        if not record then return end
        local identity = normalize(record.ID or record.Asset)
        if currentSeen[identity] then return end
        currentSeen[identity] = true
        currentTeam[#currentTeam + 1] = {
            Asset = record.Asset,
            Record = record,
            Slot = tonumber(slot) or 999,
        }
    end

    local function resolveHotbarValue(value, slot)
        if type(value) == "table" then
            local id = getCI(value, {"ID", "Id", "UnitID", "UUID"})
            if id ~= nil then
                local record = byID[normalize(tostring(id))]
                if record then
                    addCurrent(record, slot)
                    return
                end
                -- Exact hotbar IDs look like Asset#guid. If inventory record ID
                -- was normalized differently, resolve the asset prefix only as
                -- a last structural fallback.
                local prefix = tostring(id):match("^([^#]+)#")
                local asset = prefix and UnitAlias[normalize(prefix)] or nil
                if asset and byAsset[normalize(asset)] and byAsset[normalize(asset)][1] then
                    addCurrent(byAsset[normalize(asset)][1], slot)
                    return
                end
            end
            local asset = getCI(value, {"Asset", "Unit", "UnitName"})
            if asset and byAsset[normalize(asset)] and byAsset[normalize(asset)][1] then
                addCurrent(byAsset[normalize(asset)][1], slot)
                return
            end
        elseif type(value) == "string" or type(value) == "number" then
            local text = tostring(value)
            local record = byID[normalize(text)]
            if record then
                addCurrent(record, slot)
                return
            end
            local prefix = text:match("^([^#]+)#")
            local asset = UnitAlias[normalize(prefix or text)]
            if asset and byAsset[normalize(asset)] and byAsset[normalize(asset)][1] then
                addCurrent(byAsset[normalize(asset)][1], slot)
            end
        end
    end

    if type(hotbarData) == "table" then
        for slot, value in pairs(hotbarData) do
            resolveHotbarValue(value, slot)
        end
    end

    -- Some profile versions also carry an Equipped boolean on records.
    for _, record in ipairs(bestOwned) do
        if getCI(record.Data, {"Equipped"}) == true then
            addCurrent(record, getCI(record.Data, {"HotbarSlot", "Slot"}))
        end
    end

    table.sort(currentTeam, function(a, b)
        return a.Slot < b.Slot
    end)

    progress("Owned-unit scan complete.")
    return {
        Found = true,
        Score = #bestOwned + (hotbarData and 8 or 0),
        Source = "getgc replica scan @ " .. tostring(bestPath),
        HotbarSource = hotbarSource or "not found",
        Root = bestRoot,
        Owned = bestOwned,
        CurrentTeam = currentTeam,
        CandidateCount = 1,
    }
end

local function chooseBestOwnedByAsset(scan)
    local best = {}
    for _, record in ipairs(scan.Owned or {}) do
        local existing = best[record.Asset]
        local level = tonumber((getCI(record.Data, {"Level"}))) or 0
        local existingLevel = existing and (tonumber((getCI(existing.Data, {"Level"}))) or 0) or -1
        if not existing or level > existingLevel then
            best[record.Asset] = record
        end
    end
    return best
end

-- ============================================================
-- STAGE INDEX + AUTO-DETECTION
-- ============================================================

local StageIndex = {}
local StageByKey = {}
local MapsInstance = InformationRoot and InformationRoot:FindFirstChild("Maps")

local function instancePathFrom(root, instance)
    local parts = {}
    local node = instance
    while node and node ~= root do
        table.insert(parts, 1, node.Name)
        node = node.Parent
    end
    return parts
end

if MapsInstance then
    for _, instance in ipairs(MapsInstance:GetDescendants()) do
        if instance:IsA("ModuleScript") then
            local n = normalize(instance.Name)
            if n:match("^act%d+$") then
                local parts = instancePathFrom(MapsInstance, instance)
                if #parts >= 2 then
                    local gamemode = parts[1]
                    local mapName = parts[#parts - 1]
                    local actName = parts[#parts]
                    local key = table.concat(parts, "/")
                    local option = string.format("%s | %s | %s", gamemode, mapName, actName)
                    local record = {
                        Key = key,
                        Option = option,
                        Gamemode = gamemode,
                        MapName = mapName,
                        ActName = actName,
                        Module = instance,
                        Source = instance:GetFullName(),
                    }
                    StageIndex[#StageIndex + 1] = record
                    StageByKey[normalize(option)] = record
                    StageByKey[normalize(key)] = record
                end
            end
        end
    end
end

table.sort(StageIndex, function(a, b)
    return a.Option < b.Option
end)

local StageOptions = {}
for _, stage in ipairs(StageIndex) do
    StageOptions[#StageOptions + 1] = stage.Option
end
if #StageOptions == 0 then
    StageOptions[1] = "No indexed stage modules found"
end

local function resolveStageFromFields(data)
    if type(data) ~= "table" then
        return nil
    end
    local mapName = getCI(data, {"MapName", "Map"})
    local actName = getCI(data, {"ActName", "Act"})
    local gamemode = getCI(data, {"Gamemode", "GameMode", "Mode"})
    local difficulty = getCI(data, {"Difficulty"})
    if type(mapName) ~= "string" or type(actName) ~= "string" then
        return nil
    end
    local best, bestScore
    for _, stage in ipairs(StageIndex) do
        local score = 0
        if normalize(stage.MapName) == normalize(mapName) then
            score = score + 5
        end
        if normalize(stage.ActName) == normalize(actName) then
            score = score + 4
        end
        if gamemode and normalize(stage.Gamemode) == normalize(gamemode) then
            score = score + 3
        end
        if not bestScore or score > bestScore then
            best, bestScore = stage, score
        end
    end
    if bestScore and bestScore >= 9 then
        return {
            Stage = best,
            Difficulty = type(difficulty) == "string" and difficulty or nil,
            Fields = data,
            Score = bestScore,
        }
    end
    return nil
end

local function autoDetectStage()
    local candidates = {}

    -- Exact field tables from loaded runtime state.
    if type(getgc) == "function" then
        local ok, objects = pcall(getgc, true)
        if ok and type(objects) == "table" then
            local checked = 0
            for _, object in ipairs(objects) do
                if type(object) == "table" then
                    local result = resolveStageFromFields(object)
                    if result then
                        result.Source = "getgc table with MapName/ActName"
                        candidates[#candidates + 1] = result
                    end
                end
                checked = checked + 1
                if checked % 3500 == 0 then
                    task.wait()
                end
            end
        end
    end

    -- Exact attributes on UI/state Instances.
    local roots = {LocalPlayer:FindFirstChild("PlayerGui"), LocalPlayer}
    for _, root in ipairs(roots) do
        if root then
            for _, instance in ipairs(root:GetDescendants()) do
                local attrs = instance:GetAttributes()
                local result = resolveStageFromFields(attrs)
                if result then
                    result.Source = instance:GetFullName() .. " attributes"
                    candidates[#candidates + 1] = result
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        return a.Score > b.Score
    end)
    return candidates[1]
end

-- ============================================================
-- ELEMENT RELATIONSHIPS (ONLY EXPLICIT DATA)
-- ============================================================

local ElementRules = {}
for element, info in pairs(ElementData) do
    local rule = {Strong = {}, Weak = {}, Numeric = {}}
    if type(info) == "table" then
        walkTable(info, function(path, key, value)
            local np = normalize(path)
            if type(value) == "string" and ElementNames[normalize(value)] then
                if np:find("strong", 1, true) or np:find("advantage", 1, true) then
                    rule.Strong[normalize(value)] = value
                elseif np:find("weak", 1, true) or np:find("disadvantage", 1, true) then
                    rule.Weak[normalize(value)] = value
                end
            elseif type(value) == "number" then
                local parentElement = tostring(key)
                if ElementNames[normalize(parentElement)]
                    and (np:find("damagemultiplier", 1, true) or np:find("damagedealtmultiplier", 1, true))
                    and value >= 0 and value <= 5 then
                    rule.Numeric[normalize(parentElement)] = value
                end
            elseif type(value) == "table" then
                if np:find("strong", 1, true) or np:find("advantage", 1, true) then
                    mergeSets(rule.Strong, tableToSet(value))
                elseif np:find("weak", 1, true) or np:find("disadvantage", 1, true) then
                    mergeSets(rule.Weak, tableToSet(value))
                end
            end
        end, 5)
    end
    ElementRules[normalize(element)] = rule
end

local function elementMatch(unitElement, enemyElement)
    local rule = ElementRules[normalize(unitElement)]
    if not rule or not enemyElement then
        return 0, nil
    end
    local enemy = normalize(enemyElement)
    if rule.Numeric[enemy] ~= nil then
        return 0, tonumber(rule.Numeric[enemy])
    end
    if rule.Strong[enemy] then
        return 1, nil
    elseif rule.Weak[enemy] then
        return -1, nil
    end
    return 0, nil
end

-- ============================================================
-- STAGE FACT EXTRACTION
-- ============================================================

local function extractEnemyProfile(enemyKey)
    local info = EnemyList and EnemyList[enemyKey]
    local profile = {
        Key = enemyKey,
        DisplayName = enemyKey,
        Speed = nil,
        Health = nil,
        Element = nil,
        Type = nil,
        ShieldFacts = {},
        Resistances = {},
        Mechanics = {},
        Raw = info,
    }
    if type(info) ~= "table" then
        return profile
    end
    profile.DisplayName = getCI(info, {"DisplayName", "Name"}) or enemyKey
    profile.Speed = tonumber((getCI(info, {"Speed", "MoveSpeed", "WalkSpeed", "BaseSpeed"})))
    profile.Health = tonumber((getCI(info, {"Health", "BaseHealth", "HP", "MaxHealth"})))
    profile.Element = getCI(info, {"Element", "DamageType"})
    profile.Type = getCI(info, {"Type", "EnemyType", "Class"})

    walkTable(info, function(path, key, value)
        local np = normalize(path)
        local nk = normalize(key)
        if not profile.Speed and type(value) == "number" and (nk == "speed" or nk == "movespeed" or nk == "walkspeed" or nk == "basespeed") then
            profile.Speed = value
        end
        if not profile.Health and type(value) == "number" and (nk == "health" or nk == "basehealth" or nk == "hp" or nk == "maxhealth") then
            profile.Health = value
        end
        if not profile.Element and type(value) == "string" and (nk == "element" or nk == "damagetype") then
            profile.Element = value
        end
        if not profile.Type and type(value) == "string" and (nk == "type" or nk == "enemytype" or nk == "class") then
            profile.Type = value
        end
        local lowerValue = type(value) == "string" and value:lower() or ""
        if ((np:find("shield", 1, true) or np:find("barrier", 1, true) or np:find("overhealth", 1, true))
            or ((np:find("description", 1, true) or np:find("mechanic", 1, true)) and lowerValue:find("shield", 1, true)))
            and value ~= false and value ~= nil then
            profile.ShieldFacts[#profile.ShieldFacts + 1] = path .. "=" .. tostring(value)
        end
        if np:find("resist", 1, true) or np:find("immune", 1, true) then
            if type(value) ~= "table" then
                profile.Resistances[#profile.Resistances + 1] = path .. "=" .. tostring(value)
            elseif type(key) == "string" then
                for subKey, subValue in pairs(value) do
                    profile.Resistances[#profile.Resistances + 1] = path .. "." .. tostring(subKey) .. "=" .. tostring(subValue)
                end
            end
        end
        if np:find("mechanic", 1, true) or np:find("attribute", 1, true) or np:find("modifier", 1, true) or np:find("tag", 1, true) then
            if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
                profile.Mechanics[#profile.Mechanics + 1] = path .. "=" .. tostring(value)
            elseif type(value) == "table" then
                for subKey, subValue in pairs(value) do
                    if subValue == true or type(subValue) == "string" or type(subValue) == "number" then
                        profile.Mechanics[#profile.Mechanics + 1] = path .. "." .. tostring(subKey) .. "=" .. tostring(subValue)
                    end
                end
            end
        end
    end, 6)

    profile.ShieldFacts = uniqueArray(profile.ShieldFacts)
    profile.Resistances = uniqueArray(profile.Resistances)
    profile.Mechanics = uniqueArray(profile.Mechanics)
    return profile
end

local function validateEnemyResult(result)
    if type(result) ~= "table" then
        return false
    end
    local found = 0
    walkTable(result, function(_, _, value)
        if type(value) == "string" and EnemyAlias[normalize(value)] then
            found = found + 1
        end
    end, 8)
    return found > 0
end

local function validateStageData(result)
    if type(result) ~= "table" then
        return false
    end
    local score = 0
    walkTable(result, function(path, key, value)
        local nk = normalize(key)
        if nk:find("wave", 1, true) or nk:find("enemy", 1, true) or nk:find("spawn", 1, true) then
            score = score + 1
        end
        if type(value) == "string" and EnemyAlias[normalize(value)] then
            score = score + 2
        end
    end, 6)
    return score >= 2
end

local function tryValidatedFunction(fn, stage, difficulty, validator)
    if type(fn) ~= "function" then
        return nil, nil
    end
    local calls = {
        {stage.Gamemode, stage.MapName, stage.ActName, difficulty},
        {stage.MapName, stage.ActName, difficulty, stage.Gamemode},
        {stage.MapName, stage.ActName, difficulty},
        {stage.MapName, stage.ActName},
        {stage.Gamemode, stage.MapName, stage.ActName},
        {stage.Module},
    }
    for index, args in ipairs(calls) do
        local ok, result = pcall(fn, table.unpack(args))
        if ok and validator(result) then
            return result, "validated call pattern #" .. tostring(index)
        end
    end
    return nil, nil
end

local function directDifficultyTable(data, difficulty)
    if type(data) ~= "table" then
        return data, nil
    end
    for key, value in pairs(data) do
        if type(value) == "table" and normalize(key) == normalize(difficulty) then
            return value, "direct difficulty key " .. tostring(key)
        end
    end
    return data, nil
end

local function parseRestriction(facts, path, key, value)
    local nk = normalize(key)
    local np = normalize(path)
    local combined = np .. nk

    local function addRaw(kind)
        facts.RestrictionEvidence[#facts.RestrictionEvidence + 1] = {
            Kind = kind,
            Path = path,
            Value = sanitize(value),
        }
    end

    if type(value) == "string" then
        local nv = normalize(value)
        if nv:find("nofarm", 1, true) or nv:find("disablefarm", 1, true) or nv:find("banfarm", 1, true) or nv:find("farmprohibited", 1, true) then
            facts.NoFarm = true
            addRaw("NoFarm")
        end
    end

    if combined:find("farm", 1, true) and type(value) == "boolean" then
        if (combined:find("disable", 1, true) or combined:find("ban", 1, true) or combined:find("nofarm", 1, true) or combined:find("prohibit", 1, true)) and value == true then
            facts.NoFarm = true
            addRaw("NoFarm")
        elseif combined:find("allow", 1, true) and value == false then
            facts.NoFarm = true
            addRaw("NoFarm")
        elseif combined:find("allow", 1, true) and value == true then
            facts.FarmExplicitlyAllowed = true
            addRaw("FarmAllowed")
        end
    end

    if type(value) == "table" then
        if combined:find("allowedelement", 1, true) or combined:find("elementwhitelist", 1, true) then
            facts.AllowedElements = tableToSet(value)
            addRaw("AllowedElements")
        elseif combined:find("bannedelement", 1, true) or combined:find("disabledelement", 1, true) then
            facts.BannedElements = tableToSet(value)
            addRaw("BannedElements")
        elseif combined:find("allowedarchetype", 1, true) or combined:find("archetypewhitelist", 1, true) then
            facts.AllowedArchetypes = tableToSet(value)
            addRaw("AllowedArchetypes")
        elseif combined:find("bannedarchetype", 1, true) or combined:find("disabledarchetype", 1, true) then
            facts.BannedArchetypes = tableToSet(value)
            addRaw("BannedArchetypes")
        elseif combined:find("allowedplacement", 1, true) then
            facts.AllowedPlacementTypes = tableToSet(value)
            addRaw("AllowedPlacementTypes")
        elseif combined:find("bannedplacement", 1, true) or combined:find("disabledplacement", 1, true) then
            facts.BannedPlacementTypes = tableToSet(value)
            addRaw("BannedPlacementTypes")
        elseif combined:find("allowedrarity", 1, true) then
            facts.AllowedRarities = tableToSet(value)
            addRaw("AllowedRarities")
        elseif combined:find("bannedrarity", 1, true) or combined:find("disabledrarity", 1, true) then
            facts.BannedRarities = tableToSet(value)
            addRaw("BannedRarities")
        elseif combined:find("bannedunit", 1, true) or combined:find("disabledunit", 1, true) then
            facts.BannedUnits = tableToSet(value)
            addRaw("BannedUnits")
        elseif combined:find("allowedunit", 1, true) or combined:find("unitwhitelist", 1, true) then
            facts.AllowedUnits = tableToSet(value)
            addRaw("AllowedUnits")
        end
    end
end

local function addEnemyOccurrence(facts, enemyKey, count, path, explicit)
    local entry = facts.Enemies[enemyKey]
    if not entry then
        entry = {
            Key = enemyKey,
            Count = 0,
            ExplicitCount = false,
            Paths = {},
            Profile = extractEnemyProfile(enemyKey),
        }
        facts.Enemies[enemyKey] = entry
    end
    entry.Count = entry.Count + (tonumber(count) or 1)
    entry.ExplicitCount = entry.ExplicitCount or explicit == true
    if #entry.Paths < 12 then
        entry.Paths[#entry.Paths + 1] = path
    end
end

local COUNT_KEYS = {"Count", "Amount", "Quantity", "SpawnCount", "Total", "Number"}
local ENEMY_VALUE_KEYS = {"Enemy", "EnemyName", "Name", "Asset", "Unit"}

local function extractStageFacts(stage, difficulty)
    local facts = {
        Stage = stage,
        Difficulty = difficulty,
        DataSources = {},
        Enemies = {},
        WaveCount = nil,
        Duration = nil,
        StartingYen = nil,
        TotalYen = nil,
        NoFarm = false,
        FarmExplicitlyAllowed = false,
        AllowedElements = nil,
        BannedElements = nil,
        AllowedArchetypes = nil,
        BannedArchetypes = nil,
        AllowedPlacementTypes = nil,
        BannedPlacementTypes = nil,
        AllowedRarities = nil,
        BannedRarities = nil,
        AllowedUnits = nil,
        BannedUnits = nil,
        RestrictionEvidence = {},
        Evidence = {},
        Unknowns = {},
        EnemyCountBasis = "presence",
        ElementWeights = {},
        Bosses = {},
        ShieldEnemies = {},
        FastEnemies = {},
        Resistances = {},
        Mechanics = {},
        StageModifiers = {},
        ScalingData = nil,
        ScalingSource = nil,
    }

    local moduleData, moduleErr = safeRequire(stage.Module)
    if type(moduleData) == "table" then
        facts.DataSources[#facts.DataSources + 1] = stage.Source
    else
        facts.Unknowns[#facts.Unknowns + 1] = "Stage module require failed: " .. tostring(moduleErr)
        moduleData = {}
    end

    local selectedData, difficultySource = directDifficultyTable(moduleData, difficulty)
    if difficultySource then
        facts.DataSources[#facts.DataSources + 1] = difficultySource
    end

    local actData, actPattern = tryValidatedFunction(MapsDB.GetActData, stage, difficulty, validateStageData)
    if actData then
        selectedData = actData
        facts.DataSources[#facts.DataSources + 1] = "Maps.GetActData " .. actPattern
    end

    local actEnemies, enemyPattern = tryValidatedFunction(MapsDB.GetActEnemies, stage, difficulty, validateEnemyResult)
    if actEnemies then
        facts.DataSources[#facts.DataSources + 1] = "Maps.GetActEnemies " .. enemyPattern
    end

    local root = selectedData
    local enemyRoot = actEnemies or root
    local gamemodeData = type(Database.Gamemodes) == "table" and Database.Gamemodes[stage.Gamemode] or nil
    if type(gamemodeData) == "table" then
        facts.DataSources[#facts.DataSources + 1] = "Shared.Information.Gamemodes." .. tostring(stage.Gamemode)
    end

    local function scalingValidator(result)
        if type(result) ~= "table" or countKeys(result) == 0 then
            return false
        end
        local related = 0
        walkTable(result, function(path, key, value)
            local np = normalize(path)
            if np:find("health", 1, true)
                or np:find("wave", 1, true)
                or np:find("scal", 1, true)
                or np:find("difficulty", 1, true)
                or np:find("multiplayer", 1, true)
                or np:find("act", 1, true)
                or np:find("map", 1, true) then
                related = related + 1
            end
        end, 5)
        return related > 0
    end
    local scalingData, scalingPattern = tryValidatedFunction(MapsDB.GetMapScaling, stage, difficulty, scalingValidator)
    if scalingData ~= nil then
        facts.ScalingData = scalingData
        facts.ScalingSource = "Maps.GetMapScaling " .. tostring(scalingPattern)
        facts.DataSources[#facts.DataSources + 1] = facts.ScalingSource
    end

    -- Prefer validated enemy output. Each exact enemy reference is presence unless
    -- an adjacent explicit Count/Amount field exists.
    walkTable(enemyRoot, function(path, key, value, parent)
        local enemyKey
        if type(value) == "string" then
            enemyKey = EnemyAlias[normalize(value)]
        end
        if not enemyKey and type(parent) == "table" then
            local keyNorm = normalize(key)
            for _, candidateKey in ipairs(ENEMY_VALUE_KEYS) do
                if keyNorm == normalize(candidateKey) and type(value) == "string" then
                    enemyKey = EnemyAlias[normalize(value)]
                    break
                end
            end
        end
        if enemyKey then
            local count = 1
            local explicit = false
            for _, countKey in ipairs(COUNT_KEYS) do
                local found = getCI(parent, {countKey})
                if type(found) == "number" then
                    count = found
                    explicit = true
                    facts.EnemyCountBasis = "explicit counts where present"
                    break
                end
            end
            addEnemyOccurrence(facts, enemyKey, count, path, explicit)
        end
    end, 10)

    local function inspectStageValue(path, key, value)
        local nk = normalize(key)
        local np = normalize(path)
        parseRestriction(facts, path, key, value)

        if type(value) ~= "table" then
            local relevant = np:find("buff", 1, true)
                or np:find("debuff", 1, true)
                or np:find("modifier", 1, true)
                or np:find("status", 1, true)
                or np:find("resist", 1, true)
                or np:find("immune", 1, true)
                or np:find("element", 1, true)
                or np:find("shield", 1, true)
                or np:find("speed", 1, true)
                or np:find("farm", 1, true)
                or np:find("restrict", 1, true)
            if relevant and #facts.StageModifiers < 80 then
                facts.StageModifiers[#facts.StageModifiers + 1] = path .. "=" .. tostring(value)
            end
        end

        if type(value) == "number" then
            if (nk == "wavecount" or nk == "maxwave" or nk == "maxwaves" or nk == "totalwaves") and not facts.WaveCount then
                facts.WaveCount = value
                facts.Evidence[#facts.Evidence + 1] = path .. "=" .. tostring(value)
            elseif (nk == "duration" or nk == "stagetime" or nk == "timelimit" or nk == "totaltime") and not facts.Duration then
                facts.Duration = value
                facts.Evidence[#facts.Evidence + 1] = path .. "=" .. tostring(value)
            elseif (nk == "startingyen" or nk == "startyen" or nk == "startingmoney" or nk == "startcash" or nk == "startingcurrency") and not facts.StartingYen then
                facts.StartingYen = value
                facts.Evidence[#facts.Evidence + 1] = path .. "=" .. tostring(value)
            elseif (nk == "totalyen" or nk == "totalincome" or nk == "totalmoney" or nk == "availableyen") and not facts.TotalYen then
                facts.TotalYen = value
                facts.Evidence[#facts.Evidence + 1] = path .. "=" .. tostring(value)
            end
        elseif type(value) == "table" then
            if nk == "waves" or nk == "wavedata" or nk == "enemywaves" then
                local maxWave = 0
                for waveKey in pairs(value) do
                    local wave = tonumber(waveKey)
                    if wave and wave > maxWave then
                        maxWave = wave
                    end
                end
                if maxWave > 0 and (not facts.WaveCount or maxWave > facts.WaveCount) then
                    facts.WaveCount = maxWave
                    facts.Evidence[#facts.Evidence + 1] = path .. " numeric max=" .. tostring(maxWave)
                end
            end
        end
    end

    walkTable(root, inspectStageValue, 10)
    if type(gamemodeData) == "table" then
        walkTable(gamemodeData, function(path, key, value)
            inspectStageValue("Gamemode." .. path, key, value)
        end, 8)
    end

    facts.StageModifiers = uniqueArray(facts.StageModifiers)

    for enemyKey, entry in pairs(facts.Enemies) do
        local profile = entry.Profile
        if profile.Element then
            local weight = entry.Count > 0 and entry.Count or 1
            facts.ElementWeights[profile.Element] = (facts.ElementWeights[profile.Element] or 0) + weight
        end
        local typeText = normalize(profile.Type or "")
        if typeText == "boss" or normalize(enemyKey):find("boss", 1, true) then
            facts.Bosses[#facts.Bosses + 1] = enemyKey
        end
        if #profile.ShieldFacts > 0 then
            facts.ShieldEnemies[#facts.ShieldEnemies + 1] = enemyKey
        end
        if profile.Speed and SPEED_Q75 and profile.Speed >= SPEED_Q75 then
            facts.FastEnemies[#facts.FastEnemies + 1] = enemyKey
        end
        for _, resistance in ipairs(profile.Resistances) do
            facts.Resistances[#facts.Resistances + 1] = enemyKey .. ": " .. resistance
        end
        for _, mechanic in ipairs(profile.Mechanics) do
            facts.Mechanics[#facts.Mechanics + 1] = enemyKey .. ": " .. mechanic
        end
    end

    facts.Resistances = uniqueArray(facts.Resistances)
    facts.Mechanics = uniqueArray(facts.Mechanics)
    facts.FastEnemies = uniqueArray(facts.FastEnemies)
    facts.ShieldEnemies = uniqueArray(facts.ShieldEnemies)
    facts.Bosses = uniqueArray(facts.Bosses)

    if countKeys(facts.Enemies) == 0 then
        facts.Unknowns[#facts.Unknowns + 1] = "No enemy references were validated from stage data."
    end
    if not facts.Duration then
        facts.Unknowns[#facts.Unknowns + 1] = "Exact stage duration/spawn timing unavailable."
    end
    if not facts.TotalYen then
        facts.Unknowns[#facts.Unknowns + 1] = "Exact total in-stage Yen unavailable; use the manual comparison budget."
    end
    facts.Unknowns[#facts.Unknowns + 1] = "Path exposure and placement geometry are not yet simulated; exact clear time is intentionally not claimed."

    return facts, root
end

-- ============================================================
-- UNIT PROFILE + COST CURVE
-- ============================================================

local function numericUpgradeEntries(info)
    local entries = {}
    local upgradeInfo = type(info) == "table" and info.UpgradeInfo or nil
    if type(upgradeInfo) ~= "table" then
        return entries
    end
    for key, value in pairs(upgradeInfo) do
        local level = tonumber(key)
        if level and type(value) == "table" then
            entries[#entries + 1] = {Level = level, Base = value}
        end
    end
    table.sort(entries, function(a, b)
        return a.Level < b.Level
    end)
    return entries
end

local function buildUnitProfile(asset, ownedRecord)
    local info = UnitsDB[asset]
    if type(info) ~= "table" then
        return nil
    end
    local profile = {
        Asset = asset,
        DisplayName = info.DisplayName or asset,
        Element = info.Element,
        Archetype = info.Archetype,
        Rarity = info.Rarity,
        PlacementType = info.PlacementType,
        PlacementLimit = tonumber(info.PlacementLimit) or 1,
        OwnedRecord = ownedRecord,
        OwnedData = ownedRecord and ownedRecord.Data or nil,
        Upgrades = {},
        Passives = {},
        Abilities = {},
        CCTypes = {},
        DoTTypes = {},
        Buff = false,
        Debuff = false,
        ShieldCounter = false,
        Farm = normalize(info.Element) == "farm" or info.IsFarm == true,
        FarmEvidence = {},
        Summon = false,
        Transform = false,
        Relocate = false,
        BossSpecific = false,
        SynergyTargets = {},
        ActualStatsSource = nil,
        PeriodicPotential = {},
    }

    local cumulativeCost = 0
    local passiveSeen, abilitySeen = {}, {}
    for _, entry in ipairs(numericUpgradeEntries(info)) do
        local base = entry.Base
        cumulativeCost = cumulativeCost + (tonumber(base.Cost) or 0)
        local actual, calcSource = calculateOwnedStats(profile.OwnedData, info, base, entry.Level)
        if actual then
            profile.ActualStatsSource = "validated GetCalculatedStatsFromData: " .. tostring(calcSource)
        end
        local stats = actual or base
        local damage = tonumber((getCI(stats, {"Damage"}))) or tonumber(base.Damage) or 0
        local spa = tonumber((getCI(stats, {"SPA"}))) or tonumber(base.SPA)
        local range = tonumber((getCI(stats, {"Range", "RNG"}))) or tonumber(base.Range)
        local rawDPS = spa and spa > 0 and damage / spa or 0
        local upgrade = {
            Level = entry.Level,
            Cost = tonumber(base.Cost) or 0,
            CumulativeCost = cumulativeCost,
            Damage = damage,
            SPA = spa,
            Range = range,
            RawDPS = rawDPS,
            HitboxType = base.HitboxType,
            HitboxSize = tonumber(base.HitboxSize),
            CritChance = tonumber(base.CritChance),
            CritDamage = tonumber(base.CritDamage),
            DoTDamage = tonumber(base.DoTDamage),
            SkillName = base.SkillName,
            DisplayName = base.DisplayName,
            IsFarm = base.IsFarm == true,
        }
        profile.Upgrades[#profile.Upgrades + 1] = upgrade
        if upgrade.IsFarm then
            profile.Farm = true
            profile.FarmEvidence[#profile.FarmEvidence + 1] = "Upgrade " .. tostring(entry.Level) .. " IsFarm=true"
        end

        for _, passiveName in pairs(base.Passives or {}) do
            if type(passiveName) == "string" and not passiveSeen[passiveName] then
                passiveSeen[passiveName] = true
                local parsed = parseCapabilityEntry(PassivesDB[passiveName] or {}, "Passive", passiveName)
                parsed.UnlockUpgrade = entry.Level
                profile.Passives[#profile.Passives + 1] = parsed
            end
        end
        for _, abilityName in pairs(base.Abilities or {}) do
            if type(abilityName) == "string" and not abilitySeen[abilityName] then
                abilitySeen[abilityName] = true
                local parsed = parseCapabilityEntry(AbilitiesDB[abilityName] or {}, "Ability", abilityName)
                parsed.UnlockUpgrade = entry.Level
                profile.Abilities[#profile.Abilities + 1] = parsed
            end
        end
    end

    for _, parsed in ipairs(profile.Passives) do
        mergeSets(profile.CCTypes, parsed.CCTypes)
        mergeSets(profile.DoTTypes, parsed.DoTTypes)
        profile.Buff = profile.Buff or parsed.Buff
        profile.Debuff = profile.Debuff or parsed.Debuff
        profile.ShieldCounter = profile.ShieldCounter or parsed.ShieldCounter
        profile.Farm = profile.Farm or parsed.Farm
        profile.Summon = profile.Summon or parsed.Summon
        profile.Transform = profile.Transform or parsed.Transform
        profile.Relocate = profile.Relocate or parsed.Relocate
        profile.BossSpecific = profile.BossSpecific or parsed.BossSpecific
        for _, periodic in ipairs(parsed.ExactPeriodicDamage) do
            profile.PeriodicPotential[#profile.PeriodicPotential + 1] = periodic
        end
        local lower = parsed.Description:lower()
        for _, archetype in ipairs({"Magical", "Physical", "Psychic"}) do
            if lower:find(archetype:lower(), 1, true) and (lower:find("buff", 1, true) or lower:find("increase damage", 1, true)) then
                profile.SynergyTargets[normalize(archetype)] = archetype
            end
        end
        for _, element in pairs(ElementNames) do
            if lower:find(element:lower(), 1, true) and (lower:find("buff", 1, true) or lower:find("increase damage", 1, true)) then
                profile.SynergyTargets[normalize(element)] = element
            end
        end
    end
    for _, parsed in ipairs(profile.Abilities) do
        mergeSets(profile.CCTypes, parsed.CCTypes)
        mergeSets(profile.DoTTypes, parsed.DoTTypes)
        profile.Buff = profile.Buff or parsed.Buff
        profile.Debuff = profile.Debuff or parsed.Debuff
        profile.ShieldCounter = profile.ShieldCounter or parsed.ShieldCounter
        profile.Farm = profile.Farm or parsed.Farm
        profile.Summon = profile.Summon or parsed.Summon
        profile.Transform = profile.Transform or parsed.Transform
        profile.Relocate = profile.Relocate or parsed.Relocate
        profile.BossSpecific = profile.BossSpecific or parsed.BossSpecific
    end

    if profile.Farm and #profile.FarmEvidence == 0 then
        profile.FarmEvidence[#profile.FarmEvidence + 1] = "Explicit Farm element/field or income wording in DB"
    end

    profile.Final = profile.Upgrades[#profile.Upgrades]
    profile.Base = profile.Upgrades[1]
    return profile
end

local function unitLegal(profile, facts)
    local reasons = {}
    if facts.NoFarm and profile.Farm then
        reasons[#reasons + 1] = "Stage explicitly prohibits Farm units"
    end
    local function checkAllowed(set, value, label)
        if set and countKeys(set) > 0 and not set[normalize(value)] then
            reasons[#reasons + 1] = label .. " not in explicit allow-list: " .. tostring(value)
        end
    end
    local function checkBanned(set, value, label)
        if set and set[normalize(value)] then
            reasons[#reasons + 1] = label .. " explicitly banned: " .. tostring(value)
        end
    end
    checkAllowed(facts.AllowedElements, profile.Element, "Element")
    checkBanned(facts.BannedElements, profile.Element, "Element")
    checkAllowed(facts.AllowedArchetypes, profile.Archetype, "Archetype")
    checkBanned(facts.BannedArchetypes, profile.Archetype, "Archetype")
    checkAllowed(facts.AllowedPlacementTypes, profile.PlacementType, "Placement type")
    checkBanned(facts.BannedPlacementTypes, profile.PlacementType, "Placement type")
    checkAllowed(facts.AllowedRarities, profile.Rarity, "Rarity")
    checkBanned(facts.BannedRarities, profile.Rarity, "Rarity")
    checkAllowed(facts.AllowedUnits, profile.Asset, "Unit")
    checkBanned(facts.BannedUnits, profile.Asset, "Unit")
    return #reasons == 0, reasons
end

local function unitElementStage(profile, facts)
    local wins, losses, numericWeight, numericTotal = 0, 0, 0, 0
    for enemyElement, weight in pairs(facts.ElementWeights) do
        local relation, multiplier = elementMatch(profile.Element, enemyElement)
        if relation > 0 then
            wins = wins + weight
        elseif relation < 0 then
            losses = losses + weight
        end
        if multiplier then
            numericWeight = numericWeight + multiplier * weight
            numericTotal = numericTotal + weight
        end
    end
    return {
        Wins = wins,
        Losses = losses,
        Net = wins - losses,
        NumericMultiplier = numericTotal > 0 and numericWeight / numericTotal or nil,
    }
end

-- ============================================================
-- TEAM COST FRONTIER
-- ============================================================

local function placementOptions(profile, elementMultiplier)
    local options = {{Cost = 0, DPS = 0, Upgrade = -1}}
    for _, upgrade in ipairs(profile.Upgrades) do
        local dps = upgrade.RawDPS
        if elementMultiplier then
            dps = dps * elementMultiplier
        end
        options[#options + 1] = {
            Cost = upgrade.CumulativeCost,
            DPS = dps,
            Upgrade = upgrade.Level,
        }
    end
    return options
end

local function pruneFrontier(states, cap)
    table.sort(states, function(a, b)
        if a.Cost == b.Cost then
            return a.DPS > b.DPS
        end
        return a.Cost < b.Cost
    end)
    local pruned = {}
    local best = -math.huge
    local lastCost = nil
    for _, state in ipairs(states) do
        if lastCost == state.Cost then
            if #pruned > 0 and state.DPS > pruned[#pruned].DPS then
                pruned[#pruned] = state
                best = math.max(best, state.DPS)
            end
        elseif state.DPS > best + 1e-9 then
            pruned[#pruned + 1] = state
            best = state.DPS
            lastCost = state.Cost
        end
    end
    local exact = true
    cap = cap or 12000
    if #pruned > cap then
        exact = false
        local compressed = {}
        local stride = math.ceil(#pruned / cap)
        for i = 1, #pruned, stride do
            compressed[#compressed + 1] = pruned[i]
        end
        if compressed[#compressed] ~= pruned[#pruned] then
            compressed[#compressed + 1] = pruned[#pruned]
        end
        pruned = compressed
    end
    return pruned, exact
end

local function buildTeamFrontier(team, facts, budget)
    local frontier = {{Cost = 0, DPS = 0}}
    local exact = true
    budget = math.max(0, tonumber(budget) or math.huge)
    for _, profile in ipairs(team) do
        local match = unitElementStage(profile, facts)
        local allOptions = placementOptions(profile, match.NumericMultiplier)
        local options = {}
        for _, option in ipairs(allOptions) do
            if option.Cost <= budget then
                options[#options + 1] = option
            end
        end
        local copies = math.max(1, math.floor(profile.PlacementLimit or 1))
        for _ = 1, copies do
            local bestByCost = {}
            for _, state in ipairs(frontier) do
                for _, option in ipairs(options) do
                    local cost = state.Cost + option.Cost
                    if cost <= budget then
                        local dps = state.DPS + option.DPS
                        if bestByCost[cost] == nil or dps > bestByCost[cost] then
                            bestByCost[cost] = dps
                        end
                    end
                end
            end
            local nextStates = {}
            for cost, dps in pairs(bestByCost) do
                nextStates[#nextStates + 1] = {Cost = cost, DPS = dps}
            end
            local wasExact
            frontier, wasExact = pruneFrontier(nextStates, 5000)
            exact = exact and wasExact
        end
    end
    return frontier, exact
end

local function dpsAtBudget(frontier, budget)
    local best = 0
    for _, state in ipairs(frontier or {}) do
        if state.Cost <= budget and state.DPS > best then
            best = state.DPS
        end
    end
    return best
end

local function fullTeamCostAndDPS(team, facts)
    local cost, dps = 0, 0
    for _, profile in ipairs(team) do
        if profile.Final then
            local match = unitElementStage(profile, facts)
            local multiplier = match.NumericMultiplier or 1
            local copies = math.max(1, profile.PlacementLimit or 1)
            cost = cost + profile.Final.CumulativeCost * copies
            dps = dps + profile.Final.RawDPS * multiplier * copies
        end
    end
    return cost, dps
end

local function synergyPairs(team)
    local pairsOut = {}
    for _, source in ipairs(team) do
        for _, target in ipairs(team) do
            if source ~= target then
                if source.SynergyTargets[normalize(target.Archetype)] then
                    pairsOut[#pairsOut + 1] = source.Asset .. " -> " .. target.Asset .. " (" .. tostring(target.Archetype) .. ")"
                elseif source.SynergyTargets[normalize(target.Element)] then
                    pairsOut[#pairsOut + 1] = source.Asset .. " -> " .. target.Asset .. " (" .. tostring(target.Element) .. ")"
                end
            end
        end
    end
    return pairsOut
end

local function teamMetrics(team, facts, budget)
    local metrics = {
        Team = team,
        Illegal = {},
        FarmUnknown = {},
        CC = {},
        DoT = {},
        ShieldCounters = 0,
        BossSpecific = 0,
        BuffUnits = 0,
        DebuffUnits = 0,
        ElementWins = 0,
        ElementLosses = 0,
        MinSPA = nil,
        AverageSPA = nil,
        SPAValues = {},
        ThreatMisses = {},
        Synergy = {},
        AbilityCooldowns = {},
    }

    for _, profile in ipairs(team) do
        local legal, reasons = unitLegal(profile, facts)
        if not legal then
            metrics.Illegal[profile.Asset] = reasons
        end
        if profile.Farm and not facts.NoFarm and not facts.TotalYen then
            metrics.FarmUnknown[#metrics.FarmUnknown + 1] = profile.Asset
        end
        mergeSets(metrics.CC, profile.CCTypes)
        mergeSets(metrics.DoT, profile.DoTTypes)
        if profile.ShieldCounter then metrics.ShieldCounters = metrics.ShieldCounters + 1 end
        if profile.BossSpecific then metrics.BossSpecific = metrics.BossSpecific + 1 end
        if profile.Buff then metrics.BuffUnits = metrics.BuffUnits + 1 end
        if profile.Debuff then metrics.DebuffUnits = metrics.DebuffUnits + 1 end
        for _, ability in ipairs(profile.Abilities or {}) do
            if ability.Cooldown then
                metrics.AbilityCooldowns[#metrics.AbilityCooldowns + 1] = {
                    Unit = profile.Asset,
                    Ability = ability.DisplayName,
                    Cooldown = ability.Cooldown,
                    CooldownType = ability.CooldownType,
                    DurationRatio = facts.Duration and facts.Duration / ability.Cooldown or nil,
                }
            end
        end
        local match = unitElementStage(profile, facts)
        metrics.ElementWins = metrics.ElementWins + match.Wins
        metrics.ElementLosses = metrics.ElementLosses + match.Losses
        if profile.Final and profile.Final.SPA then
            metrics.SPAValues[#metrics.SPAValues + 1] = profile.Final.SPA
            metrics.MinSPA = not metrics.MinSPA and profile.Final.SPA or math.min(metrics.MinSPA, profile.Final.SPA)
        end
    end

    if #metrics.SPAValues > 0 then
        local sum = 0
        for _, value in ipairs(metrics.SPAValues) do sum = sum + value end
        metrics.AverageSPA = sum / #metrics.SPAValues
    end

    metrics.Synergy = synergyPairs(team)
    metrics.Frontier, metrics.FrontierExact = buildTeamFrontier(team, facts, budget)
    metrics.Budget = budget
    metrics.EarlyDPS = dpsAtBudget(metrics.Frontier, budget * 0.25)
    metrics.MidDPS = dpsAtBudget(metrics.Frontier, budget * 0.50)
    metrics.BudgetDPS = dpsAtBudget(metrics.Frontier, budget)
    metrics.FullCost, metrics.FullDPS = fullTeamCostAndDPS(team, facts)

    -- Threat requirements are activated only when the stage contains explicit
    -- evidence and at least one owned candidate can provide that counter.
    if #facts.FastEnemies > 0 and countKeys(metrics.CC) == 0 then
        metrics.ThreatMisses[#metrics.ThreatMisses + 1] = "Fast enemies present but team has no explicit CC token"
    end
    if #facts.ShieldEnemies > 0 and metrics.ShieldCounters == 0 then
        metrics.ThreatMisses[#metrics.ThreatMisses + 1] = "Shield mechanic present but team has no explicit shield-counter wording"
    end
    if #facts.Bosses > 0 and metrics.BossSpecific == 0 then
        -- This is informational, not a hard legality failure.
        metrics.ThreatMisses[#metrics.ThreatMisses + 1] = "Boss present; no boss-specific unit wording found"
    end

    return metrics
end

local function compareMetricTuple(a, b, strategy)
    local function less(x, y)
        return (x or 0) < (y or 0)
    end
    local function greater(x, y)
        return (x or 0) > (y or 0)
    end

    local aIllegal, bIllegal = countKeys(a.Illegal), countKeys(b.Illegal)
    if aIllegal ~= bIllegal then return less(aIllegal, bIllegal) end

    if strategy == "Fast Clear" then
        if a.EarlyDPS ~= b.EarlyDPS then return greater(a.EarlyDPS, b.EarlyDPS) end
        if a.MidDPS ~= b.MidDPS then return greater(a.MidDPS, b.MidDPS) end
        if #a.ThreatMisses ~= #b.ThreatMisses then return less(#a.ThreatMisses, #b.ThreatMisses) end
        if a.BudgetDPS ~= b.BudgetDPS then return greater(a.BudgetDPS, b.BudgetDPS) end
        if (a.MinSPA or math.huge) ~= (b.MinSPA or math.huge) then return less(a.MinSPA or math.huge, b.MinSPA or math.huge) end
        return greater(a.FullDPS, b.FullDPS)
    elseif strategy == "Max Damage" then
        if a.FullDPS ~= b.FullDPS then return greater(a.FullDPS, b.FullDPS) end
        if a.BudgetDPS ~= b.BudgetDPS then return greater(a.BudgetDPS, b.BudgetDPS) end
        if #a.ThreatMisses ~= #b.ThreatMisses then return less(#a.ThreatMisses, #b.ThreatMisses) end
        return greater(#a.Synergy, #b.Synergy)
    elseif strategy == "Safe Clear" then
        if #a.ThreatMisses ~= #b.ThreatMisses then return less(#a.ThreatMisses, #b.ThreatMisses) end
        if countKeys(a.CC) ~= countKeys(b.CC) then return greater(countKeys(a.CC), countKeys(b.CC)) end
        if a.ShieldCounters ~= b.ShieldCounters then return greater(a.ShieldCounters, b.ShieldCounters) end
        if a.BudgetDPS ~= b.BudgetDPS then return greater(a.BudgetDPS, b.BudgetDPS) end
        return greater(a.FullDPS, b.FullDPS)
    elseif strategy == "Boss" then
        if a.BossSpecific ~= b.BossSpecific then return greater(a.BossSpecific, b.BossSpecific) end
        if a.FullDPS ~= b.FullDPS then return greater(a.FullDPS, b.FullDPS) end
        if #a.ThreatMisses ~= #b.ThreatMisses then return less(#a.ThreatMisses, #b.ThreatMisses) end
        return greater(a.BudgetDPS, b.BudgetDPS)
    end

    -- Balanced: legality -> explicit counters -> element coverage -> budget curve
    -- -> full ceiling -> documented synergy.
    local aElement = a.ElementWins - a.ElementLosses
    local bElement = b.ElementWins - b.ElementLosses
    if aElement ~= bElement then return greater(aElement, bElement) end
    if a.BudgetDPS ~= b.BudgetDPS then return greater(a.BudgetDPS, b.BudgetDPS) end
    if #a.ThreatMisses ~= #b.ThreatMisses then return less(#a.ThreatMisses, #b.ThreatMisses) end
    if a.MidDPS ~= b.MidDPS then return greater(a.MidDPS, b.MidDPS) end
    if a.FullDPS ~= b.FullDPS then return greater(a.FullDPS, b.FullDPS) end
    return greater(#a.Synergy, #b.Synergy)
end

local function individualApprox(profile, facts, perUnitBudget)
    local match = unitElementStage(profile, facts)
    local multiplier = match.NumericMultiplier or 1
    local budgetDPS = 0
    for _, upgrade in ipairs(profile.Upgrades) do
        if upgrade.CumulativeCost <= perUnitBudget then
            budgetDPS = math.max(budgetDPS, upgrade.RawDPS * multiplier)
        end
    end
    return {
        Profile = profile,
        BudgetDPS = budgetDPS,
        FullDPS = profile.Final and profile.Final.RawDPS * multiplier * profile.PlacementLimit or 0,
        Utility = countKeys(profile.CCTypes) + (profile.ShieldCounter and 1 or 0) + (profile.Buff and 1 or 0) + (profile.BossSpecific and 1 or 0),
        ElementNet = match.Net,
    }
end

local function recommendTeam(allProfiles, currentProfiles, facts, budget, teamSize, strategy)
    local legalProfiles = {}
    local relevantUtility = {}
    local currentSet = {}
    for _, profile in ipairs(currentProfiles) do currentSet[profile.Asset] = true end

    for _, profile in pairs(allProfiles) do
        local legal = unitLegal(profile, facts)
        -- Farm units are not recommended until their exact in-stage income and
        -- payback can be validated. They are still evaluated in the current team.
        local farmPaybackValidated = false
        if legal and (not profile.Farm or farmPaybackValidated) then
            legalProfiles[#legalProfiles + 1] = profile
            if countKeys(profile.CCTypes) > 0 or profile.ShieldCounter or profile.Buff or profile.BossSpecific or currentSet[profile.Asset] then
                relevantUtility[profile.Asset] = true
            end
        end
    end

    local perUnitBudget = budget / math.max(teamSize, 1)
    local ranked = {}
    for _, profile in ipairs(legalProfiles) do
        ranked[#ranked + 1] = individualApprox(profile, facts, perUnitBudget)
    end
    table.sort(ranked, function(a, b)
        if strategy == "Max Damage" then
            if a.FullDPS ~= b.FullDPS then return a.FullDPS > b.FullDPS end
        elseif strategy == "Safe Clear" then
            if a.Utility ~= b.Utility then return a.Utility > b.Utility end
        elseif strategy == "Boss" then
            local ab, bb = a.Profile.BossSpecific and 1 or 0, b.Profile.BossSpecific and 1 or 0
            if ab ~= bb then return ab > bb end
        else
            if a.BudgetDPS ~= b.BudgetDPS then return a.BudgetDPS > b.BudgetDPS end
        end
        if a.ElementNet ~= b.ElementNet then return a.ElementNet > b.ElementNet end
        return a.FullDPS > b.FullDPS
    end)

    local shortlist = {}
    local shortlistSeen = {}
    local maxShortlist = math.max(teamSize, math.min(18, teamSize + 12))
    local function addShortlist(profile)
        if profile and not shortlistSeen[profile.Asset] and #shortlist < maxShortlist then
            shortlistSeen[profile.Asset] = true
            shortlist[#shortlist + 1] = profile
        end
    end

    -- Preserve ranking order; do not alphabetically discard strong candidates.
    for i = 1, math.min(#ranked, 12) do
        addShortlist(ranked[i].Profile)
    end
    for _, profile in ipairs(currentProfiles) do
        if unitLegal(profile, facts) and not profile.Farm then
            addShortlist(profile)
        end
    end
    for _, item in ipairs(ranked) do
        if relevantUtility[item.Profile.Asset] then
            addShortlist(item.Profile)
        end
    end
    for _, item in ipairs(ranked) do
        addShortlist(item.Profile)
        if #shortlist >= maxShortlist then break end
    end

    if #shortlist < teamSize then
        return nil, "Not enough legal owned unit types for requested team size."
    end

    local approximate = {}
    local built = {}
    local generated = 0
    local function enumerate(startIndex)
        if #built == teamSize then
            generated = generated + 1
            local team = {table.unpack(built)}
            local approxEarly, approxFull, utility, elementNet = 0, 0, 0, 0
            local cc = {}
            local shield, boss = 0, 0
            for _, profile in ipairs(team) do
                local item = individualApprox(profile, facts, perUnitBudget)
                approxEarly = approxEarly + item.BudgetDPS
                approxFull = approxFull + item.FullDPS
                utility = utility + item.Utility
                elementNet = elementNet + item.ElementNet
                mergeSets(cc, profile.CCTypes)
                if profile.ShieldCounter then shield = shield + 1 end
                if profile.BossSpecific then boss = boss + 1 end
            end
            approximate[#approximate + 1] = {
                Team = team,
                Early = approxEarly,
                Full = approxFull,
                Utility = utility,
                Element = elementNet,
                CC = countKeys(cc),
                Shield = shield,
                Boss = boss,
            }
            if generated % 1500 == 0 then task.wait() end
            return
        end
        local remaining = teamSize - #built
        for index = startIndex, #shortlist - remaining + 1 do
            built[#built + 1] = shortlist[index]
            enumerate(index + 1)
            built[#built] = nil
        end
    end
    enumerate(1)

    table.sort(approximate, function(a, b)
        if strategy == "Safe Clear" then
            if a.CC ~= b.CC then return a.CC > b.CC end
            if a.Shield ~= b.Shield then return a.Shield > b.Shield end
        elseif strategy == "Boss" then
            if a.Boss ~= b.Boss then return a.Boss > b.Boss end
        elseif strategy == "Max Damage" then
            if a.Full ~= b.Full then return a.Full > b.Full end
        else
            if a.Early ~= b.Early then return a.Early > b.Early end
        end
        if a.Element ~= b.Element then return a.Element > b.Element end
        if a.Utility ~= b.Utility then return a.Utility > b.Utility end
        return a.Full > b.Full
    end)

    local finalists = {}
    for i = 1, math.min(#approximate, 12) do
        finalists[#finalists + 1] = teamMetrics(approximate[i].Team, facts, budget)
    end
    table.sort(finalists, function(a, b)
        return compareMetricTuple(a, b, strategy)
    end)

    return finalists[1], {
        Shortlist = #shortlist,
        Combinations = generated,
        Finalists = #finalists,
    }
end

-- ============================================================
-- FORMATTING
-- ============================================================

local function teamNames(team)
    local names = {}
    for _, profile in ipairs(team or {}) do
        names[#names + 1] = profile.DisplayName .. " [" .. profile.Asset .. "]"
    end
    return table.concat(names, "\n")
end

local function setText(set)
    local list = {}
    for key, value in pairs(set or {}) do
        if value == true then
            list[#list + 1] = tostring(key)
        else
            list[#list + 1] = tostring(value)
        end
    end
    table.sort(list)
    return #list > 0 and table.concat(list, ", ") or "none found"
end

local function stageSummary(facts)
    local lines = {
        string.format("%s | %s | %s | %s", facts.Stage.Gamemode, facts.Stage.MapName, facts.Stage.ActName, facts.Difficulty),
        "Source: " .. table.concat(facts.DataSources, " + "),
        "Wave count: " .. tostring(facts.WaveCount or "UNKNOWN"),
        "Exact duration: " .. (facts.Duration and (formatNumber(facts.Duration, 2) .. "s") or "UNKNOWN"),
        "Starting Yen: " .. tostring(facts.StartingYen or "UNKNOWN"),
        "Total in-stage Yen: " .. tostring(facts.TotalYen or "UNKNOWN"),
        "Farm restriction: " .. (facts.NoFarm and "PROHIBITED (explicit)" or (facts.FarmExplicitlyAllowed and "allowed (explicit)" or "not explicitly stated")),
        "Enemy count basis: " .. facts.EnemyCountBasis,
    }

    local enemyLines = {}
    local keys = sortedKeys(facts.Enemies)
    for _, key in ipairs(keys) do
        local entry = facts.Enemies[key]
        local p = entry.Profile
        local tags = {}
        if p.Type then tags[#tags + 1] = "type=" .. tostring(p.Type) end
        if p.Element then tags[#tags + 1] = "element=" .. tostring(p.Element) end
        if p.Speed then
            local speedClass = SPEED_Q75 and p.Speed >= SPEED_Q75 and "FAST>=Q75" or ""
            tags[#tags + 1] = "speed=" .. formatNumber(p.Speed, 2) .. (speedClass ~= "" and (" " .. speedClass) or "")
        end
        if #p.ShieldFacts > 0 then tags[#tags + 1] = "SHIELD" end
        enemyLines[#enemyLines + 1] = string.format("%s x%s [%s]", tostring(p.DisplayName), formatNumber(entry.Count, 0), table.concat(tags, ", "))
    end
    if #enemyLines == 0 then enemyLines[1] = "UNKNOWN" end
    lines[#lines + 1] = "Enemies:\n" .. table.concat(enemyLines, "\n")

    local elementLines = {}
    for element, weight in pairs(facts.ElementWeights) do
        elementLines[#elementLines + 1] = tostring(element) .. "=" .. formatNumber(weight, 0)
    end
    table.sort(elementLines)
    lines[#lines + 1] = "Enemy elements: " .. (#elementLines > 0 and table.concat(elementLines, ", ") or "UNKNOWN")
    lines[#lines + 1] = "Fast enemies (DB Q75 threshold " .. tostring(SPEED_Q75 or "UNKNOWN") .. "): " .. (#facts.FastEnemies > 0 and table.concat(facts.FastEnemies, ", ") or "none found")
    lines[#lines + 1] = "Shield enemies: " .. (#facts.ShieldEnemies > 0 and table.concat(facts.ShieldEnemies, ", ") or "none found")
    lines[#lines + 1] = "Bosses: " .. (#facts.Bosses > 0 and table.concat(facts.Bosses, ", ") or "none found")
    lines[#lines + 1] = "Scaling source: " .. tostring(facts.ScalingSource or "UNKNOWN")
    return table.concat(lines, "\n")
end

local function metricSummary(title, metrics)
    local lines = {
        title,
        "Legal violations: " .. tostring(countKeys(metrics.Illegal)),
        "Explicit threat misses: " .. tostring(#metrics.ThreatMisses),
        "Raw DPS @25% budget: " .. formatNumber(metrics.EarlyDPS, 2),
        "Raw DPS @50% budget: " .. formatNumber(metrics.MidDPS, 2),
        "Raw DPS @budget: " .. formatNumber(metrics.BudgetDPS, 2),
        "Full placement-cap raw DPS ceiling: " .. formatNumber(metrics.FullDPS, 2),
        "Full ceiling cost: " .. formatNumber(metrics.FullCost, 0),
        "Fastest final SPA: " .. formatNumber(metrics.MinSPA, 2),
        "CC: " .. setText(metrics.CC),
        "DoT/debuff tokens: " .. setText(metrics.DoT),
        "Shield counters (explicit wording): " .. tostring(metrics.ShieldCounters),
        "Boss-specific wording: " .. tostring(metrics.BossSpecific),
        "Buff units: " .. tostring(metrics.BuffUnits),
        "Element relation net: " .. tostring(metrics.ElementWins - metrics.ElementLosses),
        "Documented synergy links: " .. tostring(#metrics.Synergy),
        "Frontier exact: " .. tostring(metrics.FrontierExact),
    }
    if #metrics.AbilityCooldowns > 0 then
        local cooldownLines = {}
        for _, item in ipairs(metrics.AbilityCooldowns) do
            cooldownLines[#cooldownLines + 1] = string.format(
                "%s: %s CD=%ss type=%s%s",
                tostring(item.Unit),
                tostring(item.Ability),
                formatNumber(item.Cooldown, 2),
                tostring(item.CooldownType or "UNKNOWN"),
                item.DurationRatio and (" | stageDuration/CD=" .. formatNumber(item.DurationRatio, 2) .. " (upper-bound windows, not guaranteed casts)") or ""
            )
        end
        lines[#lines + 1] = "Ability cooldown evidence:\n" .. table.concat(cooldownLines, "\n")
    end
    if #metrics.ThreatMisses > 0 then
        lines[#lines + 1] = "Threat notes:\n- " .. table.concat(metrics.ThreatMisses, "\n- ")
    end
    if #metrics.FarmUnknown > 0 then
        lines[#lines + 1] = "Farm value UNKNOWN (economy missing): " .. table.concat(metrics.FarmUnknown, ", ")
    end
    return table.concat(lines, "\n")
end

local function comparisonSummary(current, recommended)
    local lines = {}
    local function delta(label, a, b)
        local diff = b - a
        local pct = a ~= 0 and diff / math.abs(a) * 100 or nil
        lines[#lines + 1] = string.format(
            "%s: %s -> %s (%s%s)",
            label,
            formatNumber(a, 2),
            formatNumber(b, 2),
            diff >= 0 and "+" or "",
            pct and (formatNumber(pct, 1) .. "%") or formatNumber(diff, 2)
        )
    end
    delta("Raw DPS @25% budget", current.EarlyDPS, recommended.EarlyDPS)
    delta("Raw DPS @50% budget", current.MidDPS, recommended.MidDPS)
    delta("Raw DPS @budget", current.BudgetDPS, recommended.BudgetDPS)
    delta("Full raw DPS ceiling", current.FullDPS, recommended.FullDPS)
    lines[#lines + 1] = "CC types: " .. tostring(countKeys(current.CC)) .. " -> " .. tostring(countKeys(recommended.CC))
    lines[#lines + 1] = "Shield counters: " .. tostring(current.ShieldCounters) .. " -> " .. tostring(recommended.ShieldCounters)
    lines[#lines + 1] = "Boss-specific: " .. tostring(current.BossSpecific) .. " -> " .. tostring(recommended.BossSpecific)
    lines[#lines + 1] = "Element relation net: " .. tostring(current.ElementWins - current.ElementLosses) .. " -> " .. tostring(recommended.ElementWins - recommended.ElementLosses)
    lines[#lines + 1] = "Synergy links: " .. tostring(#current.Synergy) .. " -> " .. tostring(#recommended.Synergy)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Clear-time statement: exact minutes are NOT claimed in V2 because path exposure/spawn timing is not fully validated. The budget DPS curve above is the transparent clear-speed proxy."
    lines[#lines + 1] = "Max-damage statement: the full ceiling is exact DB Damage/SPA/cost math, adjusted only by an explicit numeric element multiplier when one was found. Conditional passive/AoE target counts are not silently added."
    return table.concat(lines, "\n")
end

local function changedUnits(currentTeam, recommendedTeam)
    local current, recommended = {}, {}
    for _, p in ipairs(currentTeam) do current[p.Asset] = true end
    for _, p in ipairs(recommendedTeam) do recommended[p.Asset] = true end
    local removed, added = {}, {}
    for asset in pairs(current) do if not recommended[asset] then removed[#removed + 1] = asset end end
    for asset in pairs(recommended) do if not current[asset] then added[#added + 1] = asset end end
    table.sort(removed)
    table.sort(added)
    return removed, added
end

local function unitChangeReasons(removed, added, currentMetrics, recommendedMetrics, profiles, facts, budget)
    local lines = {}
    for _, asset in ipairs(removed) do
        local profile = profiles[asset]
        local reasons = currentMetrics.Illegal[asset]
        if reasons then
            lines[#lines + 1] = "REMOVE " .. asset .. ": " .. table.concat(reasons, "; ")
        elseif profile and profile.Farm and not facts.TotalYen then
            lines[#lines + 1] = "REMOVE " .. asset .. ": Farm payback is UNKNOWN from available stage economy data, so it is not recommended."
        elseif profile then
            local item = individualApprox(profile, facts, budget / math.max(#currentMetrics.Team, 1))
            lines[#lines + 1] = "REMOVE " .. asset .. ": exact raw DPS at per-slot budget=" .. formatNumber(item.BudgetDPS, 2)
        end
    end
    for _, asset in ipairs(added) do
        local profile = profiles[asset]
        if profile then
            local match = unitElementStage(profile, facts)
            local tags = {
                "raw final DPS=" .. formatNumber(profile.Final and profile.Final.RawDPS or 0, 2),
                "element net=" .. tostring(match.Net),
            }
            if countKeys(profile.CCTypes) > 0 then tags[#tags + 1] = "CC=" .. setText(profile.CCTypes) end
            if profile.ShieldCounter then tags[#tags + 1] = "explicit shield counter" end
            if profile.BossSpecific then tags[#tags + 1] = "boss-specific wording" end
            if profile.Buff then tags[#tags + 1] = "documented buff" end
            lines[#lines + 1] = "ADD " .. asset .. ": " .. table.concat(tags, "; ")
        end
    end
    return #lines > 0 and table.concat(lines, "\n") or "No roster change."
end

-- ============================================================
-- UI + ANALYSIS STATE
-- ============================================================

local State = {
    SelectedStageOption = StageOptions[1],
    Difficulty = "Normal",
    Strategy = "Balanced",
    Budget = 50000,
    TeamSize = 6,
    ManualTeam = "",
    OwnedScan = nil,
    LastFacts = nil,
    LastCurrent = nil,
    LastRecommended = nil,
    LastMeta = nil,
    SelectedUnit = UnitNames[1],
}

local okRayfield, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)
if not okRayfield then
    notify("AE Assistant", "Rayfield failed to load", 8)
    warnf("Rayfield failed", Rayfield)
    ENV.AE_ASSISTANT_LOADED = nil
    return
end
App.Rayfield = Rayfield

local Window = Rayfield:CreateWindow({
    Name = "Anime Expeditions | Evidence Advisor V2",
    Icon = 0,
    LoadingTitle = "AE Evidence Advisor",
    LoadingSubtitle = "No silent guessing",
    ShowText = "AE Advisor",
    Theme = "Default",
    ToggleUIKeybind = "K",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "AE_EvidenceAdvisor",
        FileName = "settings",
    },
})

local AdvisorTab = Window:CreateTab("Team Advisor", 0)
local StageTab = Window:CreateTab("Stage Evidence", 0)
local OwnedTab = Window:CreateTab("Owned Units", 0)
local UnitTab = Window:CreateTab("Unit Analyzer", 0)
local DiagnosticsTab = Window:CreateTab("Evidence & Unknowns", 0)

local StatusParagraph = AdvisorTab:CreateParagraph({
    Title = "Status",
    Content = "Ready. Select a stage and press Analyze.",
})
local CurrentParagraph = AdvisorTab:CreateParagraph({Title = "Current Team", Content = "Not analyzed"})
local RecommendedParagraph = AdvisorTab:CreateParagraph({Title = "Recommended Team", Content = "Not analyzed"})
local CompareParagraph = AdvisorTab:CreateParagraph({Title = "Comparison", Content = "Not analyzed"})
local StageParagraph = StageTab:CreateParagraph({Title = "Stage facts", Content = "Not analyzed"})
local RulesParagraph = StageTab:CreateParagraph({Title = "Restrictions / mechanics", Content = "Not analyzed"})
local OwnedParagraph = OwnedTab:CreateParagraph({Title = "Owned scan", Content = "Not scanned"})
local UnitParagraph = UnitTab:CreateParagraph({Title = "Unit", Content = "Select a unit"})
local UpgradeParagraph = UnitTab:CreateParagraph({Title = "Upgrade curve", Content = "Select a unit"})
local EvidenceParagraph = DiagnosticsTab:CreateParagraph({Title = "Model boundaries", Content = "Not analyzed"})

AdvisorTab:CreateDropdown({
    Name = "Stage",
    Options = StageOptions,
    CurrentOption = {State.SelectedStageOption},
    MultipleOptions = false,
    Flag = "AdvisorStage",
    Callback = function(options)
        State.SelectedStageOption = options and options[1] or State.SelectedStageOption
    end,
})

AdvisorTab:CreateDropdown({
    Name = "Difficulty",
    Options = {"Normal", "Hard"},
    CurrentOption = {State.Difficulty},
    MultipleOptions = false,
    Flag = "AdvisorDifficulty",
    Callback = function(options)
        State.Difficulty = options and options[1] or State.Difficulty
    end,
})

AdvisorTab:CreateDropdown({
    Name = "Strategy objective",
    Options = {"Balanced", "Fast Clear", "Max Damage", "Safe Clear", "Boss"},
    CurrentOption = {State.Strategy},
    MultipleOptions = false,
    Flag = "AdvisorStrategy",
    Callback = function(options)
        State.Strategy = options and options[1] or State.Strategy
    end,
})

AdvisorTab:CreateInput({
    Name = "Comparison Yen budget",
    CurrentValue = tostring(State.Budget),
    PlaceholderText = "e.g. 50000",
    RemoveTextAfterFocusLost = false,
    Flag = "AdvisorBudget",
    Callback = function(text)
        local value = tonumber(text)
        if value and value > 0 then State.Budget = value end
    end,
})

AdvisorTab:CreateSlider({
    Name = "Team size",
    Range = {1, 8},
    Increment = 1,
    Suffix = " slots",
    CurrentValue = State.TeamSize,
    Flag = "AdvisorTeamSize",
    Callback = function(value)
        State.TeamSize = value
    end,
})

AdvisorTab:CreateInput({
    Name = "Manual current team override (asset/display names, comma separated)",
    CurrentValue = "",
    PlaceholderText = "blank = use detected hotbar",
    RemoveTextAfterFocusLost = false,
    Flag = "AdvisorManualTeam",
    Callback = function(text)
        State.ManualTeam = text or ""
    end,
})

local function findStageRecord(option)
    return StageByKey[normalize(option)]
end

local function parseManualTeam(text, profiles)
    local out, seen, unknown = {}, {}, {}
    for token in tostring(text or ""):gmatch("[^,;\n]+") do
        token = trim(token)
        if token ~= "" then
            local asset = UnitAlias[normalize(token)]
            if asset and profiles[asset] and not seen[asset] then
                seen[asset] = true
                out[#out + 1] = profiles[asset]
            else
                unknown[#unknown + 1] = token
            end
        end
    end
    return out, unknown
end

local function profilesFromDetectedTeam(scan, profiles)
    local out, seen = {}, {}
    for _, current in ipairs(scan.CurrentTeam or {}) do
        local profile = profiles[current.Asset]
        if profile and not seen[current.Asset] then
            seen[current.Asset] = true
            out[#out + 1] = profile
        end
    end
    return out
end

local function updateOwnedParagraph(scan)
    if not scan.Found then
        OwnedParagraph:Set({
            Title = "Owned scan",
            Content = "FAILED\n" .. tostring(scan.Unknown) .. "\nUse Diagnostics and/or the manual team override. Recommendations are disabled without an owned-unit set.",
        })
        return
    end
    local assets = {}
    local unique = {}
    for _, record in ipairs(scan.Owned) do
        if not unique[record.Asset] then
            unique[record.Asset] = true
            local level = tonumber((getCI(record.Data, {"Level"})))
            local trait = getCI(record.Data, {"Trait"})
            assets[#assets + 1] = string.format("%s%s%s", record.Asset, level and (" Lv" .. tostring(level)) or "", trait and (" [" .. tostring(trait) .. "]") or "")
        end
    end
    table.sort(assets)
    local hotbar = {}
    for _, entry in ipairs(scan.CurrentTeam or {}) do hotbar[#hotbar + 1] = entry.Asset end
    OwnedParagraph:Set({
        Title = "Owned scan",
        Content = string.format(
            "Source: %s\nValidation score: %s\nOwned records: %d\nUnique unit types: %d\nDetected hotbar: %s\n\n%s",
            tostring(scan.Source),
            tostring(scan.Score),
            #scan.Owned,
            #assets,
            #hotbar > 0 and table.concat(hotbar, ", ") or "not found",
            table.concat(assets, "\n")
        ),
    })
end

local CachedProfiles = nil
local function scanOwnedAndBuildProfiles(forceRescan, progress)
    progress = progress or function() end

    if not forceRescan and State.OwnedScan and State.OwnedScan.Found and CachedProfiles and countKeys(CachedProfiles) > 0 then
        progress("Using cached owned-unit scan.")
        return State.OwnedScan, CachedProfiles
    end

    progress("Step 1/2: locating owned inventory + hotbar...")
    local scan = scanOwnedProfile(progress)
    State.OwnedScan = scan
    updateOwnedParagraph(scan)
    if not scan.Found then
        CachedProfiles = nil
        return scan, nil
    end

    progress("Step 2/2: building unit profiles...")
    local bestByAsset = chooseBestOwnedByAsset(scan)
    local profiles = {}
    local total = countKeys(bestByAsset)
    local built = 0
    for asset, record in pairs(bestByAsset) do
        profiles[asset] = buildUnitProfile(asset, record)
        built += 1
        if built % 5 == 0 or built == total then
            progress(string.format("Building unit profiles... %d / %d", built, total))
            task.wait()
        end
    end
    CachedProfiles = profiles
    return scan, profiles
end

AdvisorTab:CreateButton({
    Name = "Auto-detect currently selected stage",
    Callback = function()
        task.spawn(function()
            StatusParagraph:Set({Title = "Status", Content = "Searching for exact MapName/ActName runtime fields..."})
            local detected = autoDetectStage()
            if detected then
                State.SelectedStageOption = detected.Stage.Option
                if detected.Difficulty then State.Difficulty = detected.Difficulty end
                StatusParagraph:Set({
                    Title = "Stage detected",
                    Content = detected.Stage.Option .. "\nDifficulty: " .. tostring(State.Difficulty) .. "\nSource: " .. tostring(detected.Source),
                })
                notify("AE Advisor", "Stage detected: " .. detected.Stage.Option, 6)
            else
                StatusParagraph:Set({Title = "Stage detection", Content = "No exact MapName/ActName runtime table found. Select the stage manually."})
            end
        end)
    end,
})

AdvisorTab:CreateButton({
    Name = "Scan owned units now",
    Callback = function()
        task.spawn(function()
            StatusParagraph:Set({Title = "Status", Content = "Scanning validated profile structures..."})
            local scan = scanOwnedAndBuildProfiles(true, function(msg)
                StatusParagraph:Set({Title = "Owned scan", Content = msg})
            end)
            StatusParagraph:Set({
                Title = "Owned scan",
                Content = scan.Found and ("Found " .. tostring(#scan.Owned) .. " records via " .. tostring(scan.Source) .. "\nHotbar: " .. tostring(scan.HotbarSource or "not found")) or tostring(scan.Unknown),
            })
            notify("AE Advisor", scan.Found and ("Owned scan: " .. tostring(#scan.Owned) .. " records, hotbar " .. tostring(#(scan.CurrentTeam or {})) .. " slots") or ("Owned scan failed: " .. tostring(scan.Unknown)), 7)
        end)
    end,
})

local function analyze()
    StatusParagraph:Set({Title = "Status", Content = "Analyze started..."})
    notify("AE Advisor", "Analyze started — reading stage and owned team", 4)

    local stage = findStageRecord(State.SelectedStageOption)
    if not stage then
        StatusParagraph:Set({Title = "Error", Content = "Selected stage is not backed by an indexed stage module."})
        notify("AE Advisor", "Select a valid stage first — no stage record is currently selected.", 8)
        return
    end

    local facts, rawStage = extractStageFacts(stage, State.Difficulty)
    State.LastFacts = facts
    StageParagraph:Set({Title = "Stage facts", Content = stageSummary(facts)})

    local ruleLines = {}
    if #facts.RestrictionEvidence > 0 then
        for _, evidence in ipairs(facts.RestrictionEvidence) do
            ruleLines[#ruleLines + 1] = evidence.Kind .. " @ " .. evidence.Path
        end
    else
        ruleLines[#ruleLines + 1] = "No recognized explicit restriction fields found. This does NOT prove that no restrictions exist."
    end
    if #facts.StageModifiers > 0 then
        ruleLines[#ruleLines + 1] = "\nStage/gamemode modifier fields:\n- " .. table.concat(facts.StageModifiers, "\n- ")
    end
    if facts.ScalingData ~= nil then
        local scalingText
        if type(facts.ScalingData) == "number" then
            scalingText = tostring(facts.ScalingData)
        else
            local pieces = {}
            walkTable(facts.ScalingData, function(path, _, value)
                if type(value) ~= "table" and #pieces < 30 then
                    pieces[#pieces + 1] = path .. "=" .. tostring(value)
                end
            end, 5)
            scalingText = #pieces > 0 and table.concat(pieces, ", ") or "table returned; no primitive fields shown"
        end
        ruleLines[#ruleLines + 1] = "\nValidated scaling data: " .. scalingText
    end
    if #facts.Mechanics > 0 then
        ruleLines[#ruleLines + 1] = "\nEnemy mechanics:\n- " .. table.concat(facts.Mechanics, "\n- ")
    end
    if #facts.Resistances > 0 then
        ruleLines[#ruleLines + 1] = "\nResistances/immunities:\n- " .. table.concat(facts.Resistances, "\n- ")
    end
    RulesParagraph:Set({Title = "Restrictions / mechanics", Content = table.concat(ruleLines, "\n")})

    StatusParagraph:Set({Title = "Status", Content = "Stage read. Loading owned units..."})
    local scan, profiles = scanOwnedAndBuildProfiles(false, function(msg)
        StatusParagraph:Set({Title = "Status", Content = msg})
    end)
    if not scan.Found or not profiles or countKeys(profiles) == 0 then
        local msg = scan.Unknown or "Owned-unit profile was not structurally validated. No team recommendation was fabricated."
        StatusParagraph:Set({Title = "Cannot recommend", Content = msg})
        notify("AE Advisor", "Cannot analyze owned team: " .. tostring(msg), 8)
        return
    end

    local currentTeam, unknownManual
    if trim(State.ManualTeam) ~= "" then
        currentTeam, unknownManual = parseManualTeam(State.ManualTeam, profiles)
    else
        currentTeam = profilesFromDetectedTeam(scan, profiles)
        unknownManual = {}
    end

    if #currentTeam == 0 then
        StatusParagraph:Set({
            Title = "Cannot compare current team",
            Content = "No hotbar was detected and the manual team override is blank. Enter your current team as comma-separated asset/display names.",
        })
        notify("AE Advisor", "Owned units found, but HotbarData was not resolved. Use manual team override or rescan.", 8)
        return
    end

    local currentMetrics = teamMetrics(currentTeam, facts, State.Budget)
    local recommendedMetrics, meta = recommendTeam(profiles, currentTeam, facts, State.Budget, State.TeamSize, State.Strategy)
    if not recommendedMetrics then
        StatusParagraph:Set({Title = "Recommendation unavailable", Content = tostring(meta)})
        return
    end

    State.LastCurrent = currentMetrics
    State.LastRecommended = recommendedMetrics
    State.LastMeta = meta

    CurrentParagraph:Set({
        Title = "Current Team",
        Content = teamNames(currentTeam) .. "\n\n" .. metricSummary("CURRENT METRICS", currentMetrics) .. (#unknownManual > 0 and ("\nUnknown manual names: " .. table.concat(unknownManual, ", ")) or ""),
    })
    RecommendedParagraph:Set({
        Title = "Recommended Team — " .. State.Strategy,
        Content = teamNames(recommendedMetrics.Team) .. "\n\n" .. metricSummary("RECOMMENDED METRICS", recommendedMetrics),
    })

    local removed, added = changedUnits(currentTeam, recommendedMetrics.Team)
    local compare = comparisonSummary(currentMetrics, recommendedMetrics)
    compare = "Remove: " .. (#removed > 0 and table.concat(removed, ", ") or "none")
        .. "\nAdd: " .. (#added > 0 and table.concat(added, ", ") or "none")
        .. "\n\nWHY (evidence only):\n" .. unitChangeReasons(removed, added, currentMetrics, recommendedMetrics, profiles, facts, State.Budget)
        .. "\n\n" .. compare
        .. "\n\nSearch: shortlist=" .. tostring(meta.Shortlist)
        .. ", combinations=" .. tostring(meta.Combinations)
        .. ", exact finalists=" .. tostring(meta.Finalists)
    CompareParagraph:Set({Title = "Current vs Recommended", Content = compare})

    local unknownLines = {
        "Evidence model version: " .. VERSION,
        "Direct DB source: " .. tostring(Database.Source.Units),
        "Owned source: " .. tostring(scan.Source),
        "Actual trait/equipment stat helper: " .. tostring(CalcPattern and CalcPattern.Name or "NOT VALIDATED — base DB stats used"),
        "Element numeric adjustment: only used when an explicit numeric matrix entry was found.",
        "Conditional passive/AoE target counts: not added to raw DPS.",
        "Exact clear time: NOT AVAILABLE until stage spawn timing + path exposure + placement are validated.",
        "Win chance: NOT CLAIMED.",
        "Unknown stage facts:",
        "- " .. table.concat(facts.Unknowns, "\n- "),
    }
    EvidenceParagraph:Set({Title = "Evidence & Unknowns", Content = table.concat(unknownLines, "\n")})

    writeDiagnostic("last_analysis.json", {
        Version = VERSION,
        PlaceId = game.PlaceId,
        Stage = facts,
        OwnedSource = scan.Source,
        Current = currentMetrics,
        Recommended = recommendedMetrics,
        Search = meta,
    })

    StatusParagraph:Set({
        Title = "Analysis complete",
        Content = string.format(
            "%s | budget %s | %s\nCurrent raw DPS@budget %s -> recommended %s\nExact clear minutes intentionally withheld until path/timing evidence exists.",
            stage.Option,
            formatNumber(State.Budget, 0),
            State.Strategy,
            formatNumber(currentMetrics.BudgetDPS, 2),
            formatNumber(recommendedMetrics.BudgetDPS, 2)
        ),
    })
    notify("AE Advisor", "Team analysis complete", 6)
end

AdvisorTab:CreateButton({
    Name = "ANALYZE CURRENT VS BEST OWNED TEAM",
    Callback = function()
        task.spawn(function()
            local ok, err = pcall(analyze)
            if not ok then
                warnf("Analysis error", err)
                StatusParagraph:Set({Title = "Analysis error", Content = tostring(err)})
                notify("AE Advisor", "Analysis error: " .. tostring(err), 10)
            end
        end)
    end,
})

-- Unit analyzer retained from V1, now using the same evidence rules.
local UnitDisplayOptions = {}
local DisplayToAsset = {}
for _, asset in ipairs(UnitNames) do
    local info = UnitsDB[asset]
    local option = tostring(info.DisplayName or asset) .. " [" .. tostring(asset) .. "]"
    UnitDisplayOptions[#UnitDisplayOptions + 1] = option
    DisplayToAsset[normalize(option)] = asset
end
State.SelectedUnit = DisplayToAsset[normalize(UnitDisplayOptions[1])] or UnitNames[1]

UnitTab:CreateDropdown({
    Name = "Unit",
    Options = UnitDisplayOptions,
    CurrentOption = {UnitDisplayOptions[1]},
    MultipleOptions = false,
    Flag = "AnalyzerUnit",
    Callback = function(options)
        local option = options and options[1]
        State.SelectedUnit = DisplayToAsset[normalize(option)] or UnitAlias[normalize(option)] or State.SelectedUnit
    end,
})

local function showUnit(asset)
    local profile = buildUnitProfile(asset, nil)
    if not profile then return end
    local lines = {
        profile.DisplayName .. " [" .. profile.Asset .. "]",
        "Rarity: " .. tostring(profile.Rarity),
        "Element: " .. tostring(profile.Element),
        "Archetype: " .. tostring(profile.Archetype),
        "Placement: " .. tostring(profile.PlacementType),
        "Limit: " .. tostring(profile.PlacementLimit),
        "Farm: " .. tostring(profile.Farm),
        "CC: " .. setText(profile.CCTypes),
        "DoT: " .. setText(profile.DoTTypes),
        "Buff: " .. tostring(profile.Buff),
        "Debuff: " .. tostring(profile.Debuff),
        "Shield counter wording: " .. tostring(profile.ShieldCounter),
        "Boss-specific wording: " .. tostring(profile.BossSpecific),
    }
    local cooldowns = {}
    for _, ability in ipairs(profile.Abilities) do
        cooldowns[#cooldowns + 1] = string.format(
            "%s U%d | CD=%s | %s | auto=%s",
            tostring(ability.DisplayName),
            tonumber(ability.UnlockUpgrade) or 0,
            tostring(ability.Cooldown or "UNKNOWN"),
            tostring(ability.CooldownType or "UNKNOWN"),
            tostring(ability.AutoUseAllowed)
        )
    end
    if #cooldowns > 0 then lines[#lines + 1] = "Abilities:\n" .. table.concat(cooldowns, "\n") end
    UnitParagraph:Set({Title = "Unit evidence", Content = table.concat(lines, "\n")})

    local upgrades = {}
    for _, upgrade in ipairs(profile.Upgrades) do
        upgrades[#upgrades + 1] = string.format(
            "U%d | cost %s (cum %s) | dmg %s | SPA %s | raw DPS %s | RNG %s | %s/%s",
            upgrade.Level,
            formatNumber(upgrade.Cost, 0),
            formatNumber(upgrade.CumulativeCost, 0),
            formatNumber(upgrade.Damage, 2),
            formatNumber(upgrade.SPA, 2),
            formatNumber(upgrade.RawDPS, 2),
            formatNumber(upgrade.Range, 2),
            tostring(upgrade.HitboxType or "?"),
            tostring(upgrade.HitboxSize or "?")
        )
    end
    UpgradeParagraph:Set({Title = "Exact DB raw upgrade curve", Content = table.concat(upgrades, "\n")})
end

UnitTab:CreateButton({
    Name = "Analyze selected unit",
    Callback = function()
        showUnit(State.SelectedUnit)
    end,
})

DiagnosticsTab:CreateButton({
    Name = "Save current evidence JSON",
    Callback = function()
        local ok, path = writeDiagnostic("manual_evidence.json", {
            Version = VERSION,
            DatabaseSource = Database.Source,
            DatabaseErrors = Database.Errors,
            Owned = State.OwnedScan,
            Stage = State.LastFacts,
            Current = State.LastCurrent,
            Recommended = State.LastRecommended,
            Meta = State.LastMeta,
        })
        notify("AE Advisor", ok and ("Saved " .. tostring(path)) or ("Save failed: " .. tostring(path)), 7)
    end,
})

DiagnosticsTab:CreateParagraph({
    Title = "What V2 will not invent",
    Content = table.concat({
        "• No exact clear minutes without spawn timing + path exposure + placement.",
        "• No win-chance percentage.",
        "• No assumed elemental rock-paper-scissors; only explicit ElementData relationships are used.",
        "• No assumed Farm payback when stage Yen income is missing; Farm units are excluded from recommendations until payback is validated.",
        "• No passive/ability damage added unless wording is structurally explicit; conditional target counts remain conditional.",
        "• No claim that absence of a discovered restriction means the stage has no restriction.",
        "• Raw DPS is Damage / SPA from DB. Crit and DoT are displayed but not silently folded into DPS without their exact formula/tick interval.",
    }, "\n"),
})

App.Destroy = function()
    if App.Destroyed then return end
    App.Destroyed = true
    for _, connection in ipairs(App.Connections) do
        pcall(function() connection:Disconnect() end)
    end
    if App.Rayfield and type(App.Rayfield.Destroy) == "function" then
        pcall(function() App.Rayfield:Destroy() end)
    end
    if ENV.AE_ASSISTANT == App then ENV.AE_ASSISTANT = nil end
    ENV.AE_ASSISTANT_LOADED = nil
end

pcall(function()
    Rayfield:LoadConfiguration()
end)

showUnit(State.SelectedUnit)
notify("AE Evidence Advisor V2", "Loaded. Select stage, set budget, then Analyze. K = hide/show.", 8)
printf("READY", VERSION, "PlaceId", game.PlaceId, game.PlaceId == EXPECTED_PLACE_ID and "expected" or "different place")
