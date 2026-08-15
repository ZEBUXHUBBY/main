--[[
    AE STRATEGIST | Standalone Evidence-Based Advisor
    -------------------------------------------------
    Completely independent from AE_Assistant/main.lua, v3.lua, live_assist.lua.
    This file does NOT load or call any of those scripts.

    Loader:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Strategist/main.lua"))()

    GOALS
    - Pre-game owned-unit + hotbar scan.
    - Detect selected Story/Raid/etc map/act/difficulty when exposed to the client.
    - Analyze enemy elements, speed, shields, mechanics, stage restrictions and Farm bans.
    - Recommend an owned-unit team for Balanced / Fast Clear / Max Damage / Safe Clear / Boss.
    - Compare current hotbar against the recommendation using transparent metrics.
    - Live, read-only Place-vs-Upgrade advice using current Yen, placed units and map geometry.
    - Suggest placement candidates from workspace.Map.Path (or a validated path fallback).
    - Never silently invent unavailable values. Unknown data stays UNKNOWN.

    READ-ONLY POLICY
    - No placement remote.
    - No upgrade remote.
    - No sell remote.
    - No ability remote.
    - No StartGame / matchmaking remote.
    The script only observes client-visible state and renders advice/markers.
]]

local VERSION = "1.0.0-standalone"
local EXPECTED_PLACE_ID = 84515722934860
local RAW_ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_DB/"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer
local ENV = getgenv and getgenv() or _G

if type(ENV.AE_STRATEGIST) == "table" and type(ENV.AE_STRATEGIST.Destroy) == "function" then
    pcall(ENV.AE_STRATEGIST.Destroy)
end

local App = {
    Version = VERSION,
    Connections = {},
    Destroyed = false,
    Cache = {},
    Diagnostics = {},
}
ENV.AE_STRATEGIST = App

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 6,
        })
    end)
end

local function normalize(v)
    return tostring(v or ""):lower():gsub("[^%w]", "")
end

local function trim(v)
    return tostring(v or ""):match("^%s*(.-)%s*$")
end

local function countKeys(t)
    local n = 0
    if type(t) == "table" then
        for _ in pairs(t) do n = n + 1 end
    end
    return n
end

local function getCI(t, names)
    if type(t) ~= "table" then return nil, nil end
    local wanted = {}
    for _, name in ipairs(names) do wanted[normalize(name)] = true end
    for k, v in pairs(t) do
        if wanted[normalize(k)] then return v, k end
    end
    return nil, nil
end

local function sortedKeys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out, function(a, b)
        local na, nb = tonumber(a), tonumber(b)
        if na and nb then return na < nb end
        return tostring(a) < tostring(b)
    end)
    return out
end

local function unique(list)
    local out, seen = {}, {}
    for _, v in ipairs(list or {}) do
        local key = tostring(v)
        if not seen[key] then seen[key] = true; out[#out + 1] = v end
    end
    return out
end

local function formatNumber(value, digits)
    value = tonumber(value)
    if not value then return "?" end
    digits = digits or 2
    local a = math.abs(value)
    if a >= 1e9 then return string.format("%.2fB", value / 1e9) end
    if a >= 1e6 then return string.format("%.2fM", value / 1e6) end
    if a >= 1e3 then return string.format("%.2fK", value / 1e3) end
    local s = string.format("%." .. tostring(digits) .. "f", value)
    return s:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
end

local function walkTable(root, fn, maxDepth)
    if type(root) ~= "table" then return end
    maxDepth = maxDepth or 7
    local seen = {}
    local function visit(t, path, depth)
        if depth > maxDepth or seen[t] then return end
        seen[t] = true
        for k, v in pairs(t) do
            local p = path == "" and tostring(k) or (path .. "." .. tostring(k))
            fn(p, k, v, t, depth)
            if type(v) == "table" then visit(v, p, depth + 1) end
        end
    end
    visit(root, "", 0)
end

local function safeRequire(instance)
    if not instance or not instance:IsA("ModuleScript") then return nil end
    local ok, result = pcall(require, instance)
    if ok and type(result) == "table" then return result end
    return nil
end

local function safeJson(url)
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if not ok then return nil, tostring(body) end
    local ok2, decoded = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok2 then return nil, tostring(decoded) end
    return decoded, nil
end

local function containsInstance(root, target, depth)
    if depth < 0 or type(root) ~= "table" then return false end
    for _, v in pairs(root) do
        if v == target then return true end
        if type(v) == "table" and depth > 0 and containsInstance(v, target, depth - 1) then return true end
    end
    return false
end

-- ============================================================
-- DATABASE (runtime Shared.Information preferred, GitHub AE_DB fallback)
-- ============================================================

local DB = {Source = {}, Errors = {}}
local Shared = ReplicatedStorage:FindFirstChild("Shared")
local Information = Shared and Shared:FindFirstChild("Information")

local DB_FILES = {
    Units = "units.json",
    Enemies = "enemies.json",
    Elements = "elements.json",
    Abilities = "abilities.json",
    Passives = "passives.json",
    StatusEffects = "status_effects.json",
    GameMechanics = "game_mechanics.json",
    Gamemodes = "gamemodes.json",
    Maps = "maps_full.json",
    EnemyTypes = "enemy_types.json",
    DamageTypes = "damage_types.json",
}

for name, file in pairs(DB_FILES) do
    local runtime = Information and safeRequire(Information:FindFirstChild(name)) or nil
    if type(runtime) == "table" and countKeys(runtime) > 0 then
        DB[name] = runtime
        DB.Source[name] = "runtime Shared.Information." .. name
    else
        local data, err = safeJson(RAW_ROOT .. file)
        if type(data) == "table" then
            DB[name] = data
            DB.Source[name] = "GitHub AE_DB/" .. file
        else
            DB[name] = {}
            DB.Errors[name] = err or "unavailable"
        end
    end
end

local UnitsDB = DB.Units.Units or DB.Units.List or DB.Units
local EnemyDB = DB.Enemies.Enemies or DB.Enemies.List or DB.Enemies
local ElementDB = DB.Elements.ElementData or DB.Elements.Elements or DB.Elements
local AbilityDB = DB.Abilities.Abilities or DB.Abilities
local PassiveDB = DB.Passives.Passives or DB.Passives

if countKeys(UnitsDB) == 0 then
    notify("AE Strategist", "Units DB unavailable", 10)
    warn("[AE Strategist] Units DB unavailable")
    ENV.AE_STRATEGIST = nil
    return
end

local UnitAlias, EnemyAlias = {}, {}
for asset, info in pairs(UnitsDB) do
    UnitAlias[normalize(asset)] = asset
    if type(info) == "table" and type(info.DisplayName) == "string" then
        UnitAlias[normalize(info.DisplayName)] = asset
    end
end
for asset, info in pairs(EnemyDB) do
    EnemyAlias[normalize(asset)] = asset
    if type(info) == "table" then
        local display = getCI(info, {"DisplayName", "Name"})
        if type(display) == "string" then EnemyAlias[normalize(display)] = asset end
    end
end

-- ============================================================
-- CAPABILITY / UNIT MODEL
-- ============================================================

local CC_WORDS = {
    stun = "Stun", slow = "Slow", freeze = "Freeze", rewind = "Rewind",
    root = "Root", stagger = "Stagger", knockback = "Knockback", timestop = "TimeStop",
}
local DOT_WORDS = {fire = "Fire", bleed = "Bleed", blackfire = "BlackFire", poison = "Poison", burn = "Burn"}

local function renderDescription(entry)
    if type(entry) ~= "table" then return "" end
    local text = tostring(entry.Description or entry.Desc or "")
    for k, parameter in pairs(entry.Parameters or {}) do
        local value
        if type(parameter) == "table" then
            if parameter.Value ~= nil then value = parameter.Value
            elseif parameter.Min ~= nil and parameter.Max ~= nil then
                value = parameter.Min == parameter.Max and parameter.Min or (tostring(parameter.Min) .. "-" .. tostring(parameter.Max))
            end
        else value = parameter end
        if value ~= nil then text = text:gsub("%{" .. tostring(k) .. "%}", tostring(value)) end
    end
    return text
end

local function parseCapability(entry, sourceName)
    local description = renderDescription(entry)
    local lower = description:lower()
    local cap = {
        Name = sourceName,
        Description = description,
        Cooldown = type(entry) == "table" and tonumber(entry.Cooldown) or nil,
        CooldownType = type(entry) == "table" and entry.CooldownType or nil,
        CC = {}, DOT = {}, Buff = false, Debuff = false, ShieldCounter = false,
        Farm = false, Boss = false, Summon = false,
    }
    for key, label in pairs(CC_WORDS) do
        if lower:find(key, 1, true) then cap.CC[label] = true; cap.Debuff = true end
    end
    for key, label in pairs(DOT_WORDS) do
        if lower:find(key, 1, true) then cap.DOT[label] = true; cap.Debuff = true end
    end
    cap.Buff = lower:find("buff", 1, true) ~= nil or lower:find("increase damage", 1, true) ~= nil
    cap.Debuff = cap.Debuff or lower:find("debuff", 1, true) ~= nil or lower:find("inflict", 1, true) ~= nil
    cap.ShieldCounter = lower:find("shield", 1, true) ~= nil and (
        lower:find("break", 1, true) ~= nil or lower:find("remove", 1, true) ~= nil or
        lower:find("pierce", 1, true) ~= nil or lower:find("ignore", 1, true) ~= nil or
        lower:find("shields every tick", 1, true) ~= nil
    )
    cap.Farm = lower:find("income", 1, true) ~= nil or lower:find(" yen", 1, true) ~= nil or lower:find("farm unit", 1, true) ~= nil
    cap.Boss = lower:find("boss", 1, true) ~= nil
    cap.Summon = lower:find("summon", 1, true) ~= nil
    return cap
end

local function mergeSet(a, b)
    for k, v in pairs(b or {}) do a[k] = v end
end

local function upgradeEntries(info)
    local out = {}
    local src = type(info) == "table" and (info.UpgradeInfo or info.Upgrades) or nil
    if type(src) ~= "table" then return out end
    for k, v in pairs(src) do
        local level = tonumber(k)
        if level and type(v) == "table" then out[#out + 1] = {Level = level, Data = v} end
    end
    table.sort(out, function(a, b) return a.Level < b.Level end)
    return out
end

local function explicitIncome(data)
    if type(data) ~= "table" then return nil, nil end
    local exact = {"Income", "YenIncome", "YenPerWave", "IncomePerWave", "MoneyPerWave", "CashPerWave", "GeneratedYen"}
    for _, key in ipairs(exact) do
        local value, actual = getCI(data, {key})
        if type(value) == "number" then return value, tostring(actual) end
    end
    return nil, nil
end

local function buildProfile(asset, ownedRecord)
    local info = UnitsDB[asset]
    if type(info) ~= "table" then return nil end
    local p = {
        Asset = asset,
        DisplayName = info.DisplayName or asset,
        Element = info.Element,
        Archetype = info.Archetype,
        Rarity = info.Rarity,
        PlacementType = info.PlacementType,
        PlacementLimit = tonumber(info.PlacementLimit) or 1,
        OwnedRecord = ownedRecord,
        Upgrades = {}, Passives = {}, Abilities = {},
        CC = {}, DOT = {}, Buff = false, Debuff = false, ShieldCounter = false,
        Farm = normalize(info.Element) == "farm" or info.IsFarm == true,
        Boss = false, Summon = false,
        FarmIncomeKnown = false,
    }
    local cumulative = 0
    local seenP, seenA = {}, {}
    for _, row in ipairs(upgradeEntries(info)) do
        local d = row.Data
        local cost = tonumber(getCI(d, {"Cost", "Price"})) or 0
        cumulative = cumulative + cost
        local damage = tonumber(getCI(d, {"Damage", "DMG"})) or 0
        local spa = tonumber(getCI(d, {"SPA", "AttackSpeed", "AttackCooldown"}))
        local range = tonumber(getCI(d, {"Range", "RNG"}))
        local income, incomeSource = explicitIncome(d)
        local u = {
            Level = row.Level,
            Cost = cost,
            CumulativeCost = cumulative,
            Damage = damage,
            SPA = spa,
            Range = range,
            RawDPS = spa and spa > 0 and damage / spa or 0,
            HitboxType = getCI(d, {"HitboxType", "AOEType", "AttackType"}),
            HitboxSize = tonumber(getCI(d, {"HitboxSize", "AOESize", "Width"})),
            CritChance = tonumber(getCI(d, {"CritChance"})),
            CritDamage = tonumber(getCI(d, {"CritDamage"})),
            Income = income,
            IncomeSource = incomeSource,
        }
        p.Upgrades[#p.Upgrades + 1] = u
        if income then p.Farm = true; p.FarmIncomeKnown = true end
        for _, name in pairs(d.Passives or {}) do
            if type(name) == "string" and not seenP[name] then
                seenP[name] = true
                local cap = parseCapability(PassiveDB[name] or {}, name)
                cap.UnlockUpgrade = row.Level
                p.Passives[#p.Passives + 1] = cap
            end
        end
        for _, name in pairs(d.Abilities or {}) do
            if type(name) == "string" and not seenA[name] then
                seenA[name] = true
                local cap = parseCapability(AbilityDB[name] or {}, name)
                cap.UnlockUpgrade = row.Level
                p.Abilities[#p.Abilities + 1] = cap
            end
        end
    end
    local function consume(cap)
        mergeSet(p.CC, cap.CC); mergeSet(p.DOT, cap.DOT)
        p.Buff = p.Buff or cap.Buff; p.Debuff = p.Debuff or cap.Debuff
        p.ShieldCounter = p.ShieldCounter or cap.ShieldCounter
        p.Farm = p.Farm or cap.Farm; p.Boss = p.Boss or cap.Boss; p.Summon = p.Summon or cap.Summon
    end
    for _, cap in ipairs(p.Passives) do consume(cap) end
    for _, cap in ipairs(p.Abilities) do consume(cap) end
    p.Base = p.Upgrades[1]
    p.Final = p.Upgrades[#p.Upgrades]
    return p
end

-- ============================================================
-- OWNED INVENTORY + HOTBAR (new replica scanner)
-- ============================================================

local function isUnitRecord(v)
    if type(v) ~= "table" then return false end
    local asset = getCI(v, {"Asset", "Unit", "UnitName"})
    if type(asset) ~= "string" or not UnitAlias[normalize(asset)] then return false end
    return getCI(v, {"Level", "EXP", "StatPotential", "Trait", "ObtainedAt", "Worthiness", "Equipped"}) ~= nil
end

local function collectDirectRecords(container, path)
    local out = {}
    if type(container) ~= "table" then return out end
    for k, v in pairs(container) do
        local record = v
        if type(v) == "table" and type(v.UnitData) == "table" and isUnitRecord(v.UnitData) then record = v.UnitData end
        if isUnitRecord(record) then
            local rawAsset = getCI(record, {"Asset", "Unit", "UnitName"})
            local asset = UnitAlias[normalize(rawAsset)]
            out[#out + 1] = {
                Asset = asset,
                ID = tostring(getCI(record, {"ID", "Id", "UUID", "Guid"}) or k),
                Data = record,
                Path = path .. "." .. tostring(k),
                Wrapper = v,
            }
        end
    end
    return out
end

local function scanOwned()
    if type(getgc) ~= "function" then
        return {Found = false, Owned = {}, Hotbar = {}, Unknown = "getgc unavailable"}
    end
    local ok, objects = pcall(getgc, true)
    if not ok or type(objects) ~= "table" then
        return {Found = false, Owned = {}, Hotbar = {}, Unknown = "getgc failed"}
    end

    local candidates = {}
    for _, obj in ipairs(objects) do
        if type(obj) == "table" then
            local data = rawget(obj, "Data")
            if type(data) == "table" then
                local score = 0
                local records, recordPath = {}, ""
                local preferred = getCI(data, {"UnitData", "Units", "UnitInventory", "InventoryUnits"})
                if type(preferred) == "table" then
                    records = collectDirectRecords(preferred, "Replica.Data.UnitData")
                    if #records > 0 then score = score + 25 + math.min(#records, 30); recordPath = "UnitData" end
                end
                if #records == 0 then
                    for k, child in pairs(data) do
                        if type(child) == "table" then
                            local r = collectDirectRecords(child, "Replica.Data." .. tostring(k))
                            if #r > #records then records = r; recordPath = tostring(k) end
                        end
                    end
                    if #records > 0 then score = score + 10 + math.min(#records, 20) end
                end
                local hotbar = getCI(data, {"HotbarData", "Hotbar", "EquippedUnits"})
                if type(hotbar) == "table" then score = score + 18 end
                if containsInstance(rawget(obj, "replication"), LocalPlayer, 2) then score = score + 50 end
                if containsInstance(obj, LocalPlayer, 1) then score = score + 20 end
                local originalVotes = 0
                for _, r in ipairs(records) do
                    if tonumber(getCI(r.Data, {"OriginalOwner"})) == LocalPlayer.UserId then originalVotes = originalVotes + 1 end
                end
                score = score + math.min(originalVotes * 3, 24)
                if #records > 0 then
                    candidates[#candidates + 1] = {Score = score, Object = obj, Data = data, Records = records, HotbarData = hotbar, Path = recordPath}
                end
            end
        end
    end

    table.sort(candidates, function(a, b) return a.Score > b.Score end)
    local best = candidates[1]
    if not best then
        return {Found = false, Owned = {}, Hotbar = {}, Unknown = "No validated profile replica with unit records"}
    end
    if candidates[2] and best.Score < 40 and math.abs(best.Score - candidates[2].Score) < 5 then
        return {Found = false, Owned = {}, Hotbar = {}, Unknown = "Multiple profile replicas are ambiguous; refusing to guess local inventory"}
    end

    local byID, byAsset = {}, {}
    for _, r in ipairs(best.Records) do
        byID[normalize(r.ID)] = r
        byAsset[normalize(r.Asset)] = byAsset[normalize(r.Asset)] or {}
        table.insert(byAsset[normalize(r.Asset)], r)
    end

    local hotbar, seen = {}, {}
    local function add(r, slot, source)
        if not r then return end
        local key = r.ID .. "|" .. r.Asset
        if seen[key] then return end
        seen[key] = true
        hotbar[#hotbar + 1] = {Asset = r.Asset, Record = r, Slot = tonumber(slot) or 999, Source = source}
    end
    local function resolve(v, slot, source)
        if type(v) == "table" then
            if type(v.UnitData) == "table" and isUnitRecord(v.UnitData) then
                local a = UnitAlias[normalize(getCI(v.UnitData, {"Asset"}))]
                local id = getCI(v.UnitData, {"ID", "Id", "UUID"})
                add((id and byID[normalize(id)]) or (a and byAsset[normalize(a)] and byAsset[normalize(a)][1]), v.HotbarSlot or slot, source)
                return
            end
            local id = getCI(v, {"ID", "Id", "UnitID", "UUID"})
            if id and byID[normalize(id)] then add(byID[normalize(id)], slot, source); return end
            if id then
                local prefix = tostring(id):match("^([^#]+)#")
                local a = prefix and UnitAlias[normalize(prefix)]
                if a and byAsset[normalize(a)] then add(byAsset[normalize(a)][1], slot, source); return end
            end
            local rawAsset = getCI(v, {"Asset", "Unit", "UnitName"})
            local a = rawAsset and UnitAlias[normalize(rawAsset)]
            if a and byAsset[normalize(a)] then add(byAsset[normalize(a)][1], slot, source) end
        elseif type(v) == "string" or type(v) == "number" then
            local s = tostring(v)
            if byID[normalize(s)] then add(byID[normalize(s)], slot, source); return end
            local prefix = s:match("^([^#]+)#")
            local a = UnitAlias[normalize(prefix or s)]
            if a and byAsset[normalize(a)] then add(byAsset[normalize(a)][1], slot, source) end
        end
    end
    if type(best.HotbarData) == "table" then
        walkTable(best.HotbarData, function(path, key, value, parent, depth)
            if depth <= 3 then
                local slot = tonumber(key) or (type(parent) == "table" and tonumber(parent.HotbarSlot))
                if type(value) ~= "table" or isUnitRecord(value) or value.UnitData or getCI(value, {"ID", "Asset", "Unit"}) ~= nil then
                    resolve(value, slot, "HotbarData." .. path)
                end
            end
        end, 3)
    end
    for _, r in ipairs(best.Records) do
        if getCI(r.Data, {"Equipped"}) == true then
            local slot = getCI(r.Wrapper, {"HotbarSlot", "Slot"}) or getCI(r.Data, {"HotbarSlot", "Slot"})
            add(r, slot, "Equipped=true")
        end
    end
    table.sort(hotbar, function(a, b) return a.Slot < b.Slot end)
    return {
        Found = true, Owned = best.Records, Hotbar = hotbar, Score = best.Score,
        Source = "getgc profile replica Data." .. tostring(best.Path), CandidateCount = #candidates,
    }
end

local function bestOwnedByAsset(scan)
    local out = {}
    for _, r in ipairs(scan.Owned or {}) do
        local old = out[r.Asset]
        local lv = tonumber(getCI(r.Data, {"Level"})) or 0
        local oldLv = old and (tonumber(getCI(old.Data, {"Level"})) or 0) or -1
        if not old or lv > oldLv then out[r.Asset] = r end
    end
    return out
end

-- ============================================================
-- STAGE DETECTION / FACTS
-- ============================================================

local function parseManualStage(text)
    text = trim(text)
    if text == "" then return nil end
    local parts = {}
    for token in text:gmatch("[^|,]+") do parts[#parts + 1] = trim(token) end
    if #parts < 3 then return nil end
    return {Gamemode = parts[1], MapName = parts[2], ActName = parts[3], Difficulty = parts[4] or "Normal", Source = "manual override"}
end

local function detectStageRuntime()
    if type(getgc) ~= "function" then return nil end
    local ok, objects = pcall(getgc, true)
    if not ok or type(objects) ~= "table" then return nil end
    local candidates = {}
    for _, obj in ipairs(objects) do
        if type(obj) == "table" then
            local mapName = getCI(obj, {"MapName", "Map"})
            local actName = getCI(obj, {"ActName", "Act"})
            local mode = getCI(obj, {"Gamemode", "GameMode", "Mode"})
            local difficulty = getCI(obj, {"Difficulty"})
            if type(mapName) == "string" and type(actName) == "string" and (type(mode) == "string" or mode == nil) then
                local score = 10 + (mode and 4 or 0) + (difficulty and 2 or 0)
                candidates[#candidates + 1] = {MapName = mapName, ActName = actName, Gamemode = mode or "UNKNOWN", Difficulty = type(difficulty) == "string" and difficulty or "Normal", Score = score, Source = "getgc table"}
            end
        end
    end
    table.sort(candidates, function(a, b) return a.Score > b.Score end)
    return candidates[1]
end

local function enemyProfile(asset)
    local info = EnemyDB[asset]
    local p = {Asset = asset, DisplayName = asset, Element = nil, Type = nil, Speed = nil, Health = nil, Shield = false, Resistances = {}, Mechanics = {}}
    if type(info) ~= "table" then return p end
    p.DisplayName = getCI(info, {"DisplayName", "Name"}) or asset
    p.Element = getCI(info, {"Element", "DamageType"})
    p.Type = getCI(info, {"Type", "EnemyType", "Class"})
    p.Speed = tonumber(getCI(info, {"Speed", "MoveSpeed", "WalkSpeed", "BaseSpeed"}))
    p.Health = tonumber(getCI(info, {"Health", "BaseHealth", "HP", "MaxHealth"}))
    walkTable(info, function(path, key, value)
        local n = normalize(path)
        if (n:find("shield", 1, true) or n:find("barrier", 1, true)) and value ~= false and value ~= nil then p.Shield = true end
        if (n:find("resist", 1, true) or n:find("immune", 1, true)) and type(value) ~= "table" then p.Resistances[#p.Resistances + 1] = path .. "=" .. tostring(value) end
        if (n:find("mechanic", 1, true) or n:find("modifier", 1, true) or n:find("tag", 1, true)) and type(value) ~= "table" then p.Mechanics[#p.Mechanics + 1] = path .. "=" .. tostring(value) end
    end, 5)
    return p
end

local function findRuntimeActModule(stage)
    local maps = Information and Information:FindFirstChild("Maps")
    if not maps or not stage then return nil end
    local nm, na = normalize(stage.MapName), normalize(stage.ActName)
    local best
    for _, d in ipairs(maps:GetDescendants()) do
        if d:IsA("ModuleScript") and normalize(d.Name) == na then
            local parentText = normalize(d.Parent and d.Parent.Name)
            if parentText == nm or normalize(d:GetFullName()):find(nm, 1, true) then best = d; break end
        end
    end
    return best
end

local function mapDbCandidate(stage)
    if type(DB.Maps) ~= "table" or not stage then return nil end
    local best, bestScore = nil, 0
    local seen = {}
    local function visit(t, depth)
        if depth > 7 or seen[t] then return end
        seen[t] = true
        for k, v in pairs(t) do
            if type(v) == "table" then
                local score = 0
                local keyText = normalize(k)
                if keyText == normalize(stage.MapName) then score = score + 4 end
                if keyText == normalize(stage.ActName) then score = score + 4 end
                local mn = getCI(v, {"MapName", "Map"}); local an = getCI(v, {"ActName", "Act"}); local gm = getCI(v, {"Gamemode", "GameMode"})
                if mn and normalize(mn) == normalize(stage.MapName) then score = score + 5 end
                if an and normalize(an) == normalize(stage.ActName) then score = score + 5 end
                if gm and stage.Gamemode ~= "UNKNOWN" and normalize(gm) == normalize(stage.Gamemode) then score = score + 2 end
                if score > bestScore then best, bestScore = v, score end
                visit(v, depth + 1)
            end
        end
    end
    visit(DB.Maps, 0)
    return bestScore >= 8 and best or nil
end

local function extractStageFacts(stage)
    local facts = {
        Stage = stage, Sources = {}, Enemies = {}, EnemyCountBasis = "presence",
        WaveCount = nil, Duration = nil, StartingYen = nil, TotalYen = nil,
        NoFarm = false, FarmAllowed = false,
        AllowedElements = nil, BannedElements = nil, AllowedArchetypes = nil, BannedArchetypes = nil,
        ShieldEnemies = {}, FastEnemies = {}, Bosses = {}, Mechanics = {}, Resistances = {},
        ElementWeights = {}, Modifiers = {}, Unknowns = {},
    }
    if not stage then facts.Unknowns[#facts.Unknowns + 1] = "Stage not detected"; return facts end

    local roots = {}
    local module = findRuntimeActModule(stage)
    local moduleData = safeRequire(module)
    if moduleData then roots[#roots + 1] = moduleData; facts.Sources[#facts.Sources + 1] = module:GetFullName() end
    local dbRoot = mapDbCandidate(stage)
    if dbRoot then roots[#roots + 1] = dbRoot; facts.Sources[#facts.Sources + 1] = "AE_DB/maps_full.json candidate" end
    if #roots == 0 then facts.Unknowns[#facts.Unknowns + 1] = "No matching stage table/module found" end

    local function setFromTable(v)
        local s = {}
        if type(v) == "table" then
            for k, x in pairs(v) do
                if type(k) == "number" or tonumber(k) then s[normalize(x)] = tostring(x)
                elseif x == true then s[normalize(k)] = tostring(k)
                elseif type(x) == "string" then s[normalize(x)] = x end
            end
        end
        return s
    end

    local function addEnemy(asset, count)
        local e = facts.Enemies[asset]
        if not e then e = {Asset = asset, Count = 0, Profile = enemyProfile(asset)}; facts.Enemies[asset] = e end
        e.Count = e.Count + (tonumber(count) or 1)
    end

    for _, root in ipairs(roots) do
        walkTable(root, function(path, key, value, parent)
            local nk, np = normalize(key), normalize(path)
            local combined = np .. nk
            if type(value) == "string" then
                local enemy = EnemyAlias[normalize(value)]
                if enemy then
                    local count = tonumber(getCI(parent, {"Count", "Amount", "Quantity", "SpawnCount"})) or 1
                    if count ~= 1 then facts.EnemyCountBasis = "explicit counts where present" end
                    addEnemy(enemy, count)
                end
                local nv = normalize(value)
                if nv:find("nofarm", 1, true) or nv:find("disablefarm", 1, true) or nv:find("banfarm", 1, true) then facts.NoFarm = true end
            elseif type(value) == "boolean" and combined:find("farm", 1, true) then
                if value == true and (combined:find("disable", 1, true) or combined:find("ban", 1, true) or combined:find("nofarm", 1, true)) then facts.NoFarm = true end
                if value == false and combined:find("allow", 1, true) then facts.NoFarm = true end
                if value == true and combined:find("allow", 1, true) then facts.FarmAllowed = true end
            elseif type(value) == "number" then
                if not facts.WaveCount and (nk == "wavecount" or nk == "maxwaves" or nk == "totalwaves") then facts.WaveCount = value end
                if not facts.Duration and (nk == "duration" or nk == "stagetime" or nk == "timelimit" or nk == "totaltime") then facts.Duration = value end
                if not facts.StartingYen and (nk == "startingyen" or nk == "startyen" or nk == "startingmoney" or nk == "startcash") then facts.StartingYen = value end
                if not facts.TotalYen and (nk == "totalyen" or nk == "totalincome" or nk == "totalmoney" or nk == "availableyen") then facts.TotalYen = value end
            elseif type(value) == "table" then
                if combined:find("allowedelement", 1, true) or combined:find("elementwhitelist", 1, true) then facts.AllowedElements = setFromTable(value) end
                if combined:find("bannedelement", 1, true) or combined:find("disabledelement", 1, true) then facts.BannedElements = setFromTable(value) end
                if combined:find("allowedarchetype", 1, true) then facts.AllowedArchetypes = setFromTable(value) end
                if combined:find("bannedarchetype", 1, true) then facts.BannedArchetypes = setFromTable(value) end
            end
            if type(value) ~= "table" and (np:find("modifier", 1, true) or np:find("debuff", 1, true) or np:find("buff", 1, true) or np:find("resist", 1, true) or np:find("shield", 1, true)) then
                if #facts.Modifiers < 80 then facts.Modifiers[#facts.Modifiers + 1] = path .. "=" .. tostring(value) end
            end
        end, 9)
    end

    local speeds = {}
    for _, info in pairs(EnemyDB) do
        if type(info) == "table" then
            local s = tonumber(getCI(info, {"Speed", "MoveSpeed", "WalkSpeed", "BaseSpeed"}))
            if s then speeds[#speeds + 1] = s end
        end
    end
    table.sort(speeds)
    local q75 = #speeds > 0 and speeds[math.max(1, math.ceil(#speeds * 0.75))] or nil

    for asset, e in pairs(facts.Enemies) do
        local p = e.Profile
        if p.Element then facts.ElementWeights[p.Element] = (facts.ElementWeights[p.Element] or 0) + math.max(1, e.Count) end
        if p.Shield then facts.ShieldEnemies[#facts.ShieldEnemies + 1] = asset end
        if p.Speed and q75 and p.Speed >= q75 then facts.FastEnemies[#facts.FastEnemies + 1] = asset end
        if normalize(p.Type) == "boss" or normalize(asset):find("boss", 1, true) then facts.Bosses[#facts.Bosses + 1] = asset end
        for _, x in ipairs(p.Mechanics) do facts.Mechanics[#facts.Mechanics + 1] = asset .. ": " .. x end
        for _, x in ipairs(p.Resistances) do facts.Resistances[#facts.Resistances + 1] = asset .. ": " .. x end
    end
    facts.Modifiers = unique(facts.Modifiers); facts.Mechanics = unique(facts.Mechanics); facts.Resistances = unique(facts.Resistances)
    if countKeys(facts.Enemies) == 0 then facts.Unknowns[#facts.Unknowns + 1] = "Enemy wave roster unavailable" end
    if not facts.TotalYen then facts.Unknowns[#facts.Unknowns + 1] = "Exact total stage Yen unavailable" end
    if not facts.Duration then facts.Unknowns[#facts.Unknowns + 1] = "Exact spawn timing / clear duration unavailable" end
    return facts
end

-- ============================================================
-- ELEMENT RELATIONS (explicit only)
-- ============================================================

local function elementMatch(attacker, defender)
    if not attacker or not defender then return 0, nil end
    local info
    for k, v in pairs(ElementDB) do if normalize(k) == normalize(attacker) then info = v; break end end
    if type(info) ~= "table" then return 0, nil end
    local relation, multiplier = 0, nil
    walkTable(info, function(path, key, value)
        local n = normalize(path)
        if type(value) == "number" and normalize(key) == normalize(defender) and (n:find("multiplier", 1, true) or n:find("damage", 1, true)) then multiplier = value end
        if type(value) == "string" and normalize(value) == normalize(defender) then
            if n:find("strong", 1, true) or n:find("advantage", 1, true) then relation = 1 end
            if n:find("weak", 1, true) or n:find("disadvantage", 1, true) then relation = -1 end
        end
    end, 5)
    if multiplier then
        if multiplier > 1 then relation = 1 elseif multiplier < 1 then relation = -1 end
    end
    return relation, multiplier
end

local function stageElement(profile, facts)
    local wins, losses, weighted, total = 0, 0, 0, 0
    for element, weight in pairs(facts.ElementWeights or {}) do
        local rel, mult = elementMatch(profile.Element, element)
        if rel > 0 then wins = wins + weight elseif rel < 0 then losses = losses + weight end
        if mult then weighted = weighted + mult * weight; total = total + weight end
    end
    return {Wins = wins, Losses = losses, Net = wins - losses, Multiplier = total > 0 and weighted / total or nil}
end

local function legal(profile, facts)
    local reasons = {}
    if facts.NoFarm and profile.Farm then reasons[#reasons + 1] = "Farm explicitly prohibited" end
    local function allowed(set, value, label)
        if set and countKeys(set) > 0 and not set[normalize(value)] then reasons[#reasons + 1] = label .. " not in allow-list" end
    end
    local function banned(set, value, label)
        if set and set[normalize(value)] then reasons[#reasons + 1] = label .. " explicitly banned" end
    end
    allowed(facts.AllowedElements, profile.Element, "Element"); banned(facts.BannedElements, profile.Element, "Element")
    allowed(facts.AllowedArchetypes, profile.Archetype, "Archetype"); banned(facts.BannedArchetypes, profile.Archetype, "Archetype")
    return #reasons == 0, reasons
end

-- ============================================================
-- TEAM BUDGET MODEL / RECOMMENDER
-- ============================================================

local function dpsAtBudget(team, facts, budget)
    budget = math.max(0, tonumber(budget) or 0)
    if budget <= 0 then return 0 end
    local step = math.max(25, math.floor(budget / 450))
    local maxBucket = math.floor(budget / step)
    local dp = {[0] = 0}
    for _, p in ipairs(team) do
        local em = stageElement(p, facts).Multiplier or 1
        local options = {{Cost = 0, DPS = 0}}
        for _, u in ipairs(p.Upgrades) do options[#options + 1] = {Cost = u.CumulativeCost, DPS = u.RawDPS * em} end
        for _ = 1, math.max(1, math.floor(p.PlacementLimit or 1)) do
            local nextDP = {}
            for b, value in pairs(dp) do
                for _, o in ipairs(options) do
                    local nb = b + math.floor(o.Cost / step + 0.5)
                    if nb <= maxBucket then
                        local nv = value + o.DPS
                        if nextDP[nb] == nil or nv > nextDP[nb] then nextDP[nb] = nv end
                    end
                end
            end
            dp = nextDP
        end
    end
    local best = 0
    for _, v in pairs(dp) do if v > best then best = v end end
    return best
end

local function teamMetrics(team, facts, budget)
    local m = {Team = team, Illegal = {}, CC = {}, DOT = {}, Shield = 0, Boss = 0, Buff = 0, ElementNet = 0, FullDPS = 0, FullCost = 0, MinSPA = nil, ThreatMisses = {}, FarmUnknown = {}}
    for _, p in ipairs(team) do
        local ok, reasons = legal(p, facts)
        if not ok then m.Illegal[p.Asset] = reasons end
        mergeSet(m.CC, p.CC); mergeSet(m.DOT, p.DOT)
        if p.ShieldCounter then m.Shield = m.Shield + 1 end
        if p.Boss then m.Boss = m.Boss + 1 end
        if p.Buff then m.Buff = m.Buff + 1 end
        local e = stageElement(p, facts); m.ElementNet = m.ElementNet + e.Net
        if p.Final then
            local mult = e.Multiplier or 1
            local copies = math.max(1, p.PlacementLimit or 1)
            m.FullDPS = m.FullDPS + p.Final.RawDPS * mult * copies
            m.FullCost = m.FullCost + p.Final.CumulativeCost * copies
            if p.Final.SPA then m.MinSPA = m.MinSPA and math.min(m.MinSPA, p.Final.SPA) or p.Final.SPA end
        end
        if p.Farm and not p.FarmIncomeKnown then m.FarmUnknown[#m.FarmUnknown + 1] = p.Asset end
    end
    m.EarlyDPS = dpsAtBudget(team, facts, budget * 0.25)
    m.MidDPS = dpsAtBudget(team, facts, budget * 0.50)
    m.BudgetDPS = dpsAtBudget(team, facts, budget)
    if #facts.FastEnemies > 0 and countKeys(m.CC) == 0 then m.ThreatMisses[#m.ThreatMisses + 1] = "Fast enemies but no explicit CC" end
    if #facts.ShieldEnemies > 0 and m.Shield == 0 then m.ThreatMisses[#m.ThreatMisses + 1] = "Shield enemy but no explicit shield counter" end
    return m
end

local function better(a, b, strategy)
    if not b then return true end
    local ai, bi = countKeys(a.Illegal), countKeys(b.Illegal)
    if ai ~= bi then return ai < bi end
    if strategy == "Fast Clear" then
        if a.EarlyDPS ~= b.EarlyDPS then return a.EarlyDPS > b.EarlyDPS end
        if a.MidDPS ~= b.MidDPS then return a.MidDPS > b.MidDPS end
        if #a.ThreatMisses ~= #b.ThreatMisses then return #a.ThreatMisses < #b.ThreatMisses end
        if a.BudgetDPS ~= b.BudgetDPS then return a.BudgetDPS > b.BudgetDPS end
        return a.FullDPS > b.FullDPS
    elseif strategy == "Max Damage" then
        if a.FullDPS ~= b.FullDPS then return a.FullDPS > b.FullDPS end
        if a.BudgetDPS ~= b.BudgetDPS then return a.BudgetDPS > b.BudgetDPS end
        return #a.ThreatMisses < #b.ThreatMisses
    elseif strategy == "Safe Clear" then
        if #a.ThreatMisses ~= #b.ThreatMisses then return #a.ThreatMisses < #b.ThreatMisses end
        if countKeys(a.CC) ~= countKeys(b.CC) then return countKeys(a.CC) > countKeys(b.CC) end
        if a.Shield ~= b.Shield then return a.Shield > b.Shield end
        return a.BudgetDPS > b.BudgetDPS
    elseif strategy == "Boss" then
        if a.Boss ~= b.Boss then return a.Boss > b.Boss end
        if a.FullDPS ~= b.FullDPS then return a.FullDPS > b.FullDPS end
        return a.BudgetDPS > b.BudgetDPS
    else
        if #a.ThreatMisses ~= #b.ThreatMisses then return #a.ThreatMisses < #b.ThreatMisses end
        if a.ElementNet ~= b.ElementNet then return a.ElementNet > b.ElementNet end
        if a.BudgetDPS ~= b.BudgetDPS then return a.BudgetDPS > b.BudgetDPS end
        if a.MidDPS ~= b.MidDPS then return a.MidDPS > b.MidDPS end
        return a.FullDPS > b.FullDPS
    end
end

local function recommend(profiles, currentTeam, facts, budget, size, strategy)
    local candidates = {}
    for _, p in pairs(profiles) do
        local ok = legal(p, facts)
        if ok then
            if not p.Farm or facts.NoFarm == false then candidates[#candidates + 1] = p end
        end
    end
    table.sort(candidates, function(a, b)
        local ae = stageElement(a, facts); local be = stageElement(b, facts)
        local ad = a.Final and a.Final.RawDPS * (ae.Multiplier or 1) or 0
        local bd = b.Final and b.Final.RawDPS * (be.Multiplier or 1) or 0
        return ad > bd
    end)
    if #candidates < size then size = #candidates end
    local team, used = {}, {}
    for _ = 1, size do
        local bestP, bestM
        for _, p in ipairs(candidates) do
            if not used[p.Asset] then
                local test = {}
                for _, x in ipairs(team) do test[#test + 1] = x end
                test[#test + 1] = p
                local m = teamMetrics(test, facts, budget)
                if better(m, bestM, strategy) then bestP, bestM = p, m end
            end
        end
        if not bestP then break end
        used[bestP.Asset] = true; team[#team + 1] = bestP
    end

    -- Local-swap improvement to reduce greedy lock-in.
    local currentM = teamMetrics(team, facts, budget)
    for _ = 1, 2 do
        local improved = false
        for i = 1, #team do
            for _, p in ipairs(candidates) do
                if not used[p.Asset] then
                    local test = {}
                    for j, x in ipairs(team) do test[j] = (j == i) and p or x end
                    local m = teamMetrics(test, facts, budget)
                    if better(m, currentM, strategy) then
                        used[team[i].Asset] = nil; used[p.Asset] = true; team = test; currentM = m; improved = true; break
                    end
                end
            end
            if improved then break end
        end
        if not improved then break end
    end
    return currentM
end

-- ============================================================
-- PATH GEOMETRY / PLACEMENT
-- ============================================================

local PathState = {Root = nil, Points = {}, Segments = {}, Length = 0, Source = "UNKNOWN"}

local function positionOf(obj)
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Attachment") then return obj.WorldPosition end
    if obj:IsA("CFrameValue") then return obj.Value.Position end
    if obj:IsA("Vector3Value") then return obj.Value end
    return nil
end

local function orderedPoints(root)
    local rows = {}
    if not root then return rows end
    for _, d in ipairs(root:GetChildren()) do
        local pos = positionOf(d)
        if pos then
            local idx = tonumber(d.Name) or tonumber(d:GetAttribute("Index")) or tonumber(d:GetAttribute("Order"))
            rows[#rows + 1] = {Object = d, Position = pos, Index = idx}
        end
    end
    if #rows < 2 then
        rows = {}
        for _, d in ipairs(root:GetDescendants()) do
            if #rows >= 300 then break end
            local pos = positionOf(d)
            if pos then
                local idx = tonumber(d.Name) or tonumber(d:GetAttribute("Index")) or tonumber(d:GetAttribute("Order"))
                rows[#rows + 1] = {Object = d, Position = pos, Index = idx}
            end
        end
    end
    local indexed = 0
    for _, r in ipairs(rows) do if r.Index then indexed = indexed + 1 end end
    if indexed >= math.max(2, math.floor(#rows * 0.6)) then
        table.sort(rows, function(a, b)
            if a.Index and b.Index then return a.Index < b.Index end
            if a.Index then return true end
            if b.Index then return false end
            return a.Object.Name < b.Object.Name
        end)
    else
        -- No trustworthy order: nearest-neighbor chain, starting at the point farthest from centroid.
        if #rows > 2 then
            local c = Vector3.zero
            for _, r in ipairs(rows) do c = c + r.Position end
            c = c / #rows
            local start, far = 1, -1
            for i, r in ipairs(rows) do local d = (r.Position - c).Magnitude; if d > far then start, far = i, d end end
            local remaining, chain = {}, {}
            for i, r in ipairs(rows) do if i ~= start then remaining[#remaining + 1] = r end end
            chain[1] = rows[start]
            while #remaining > 0 do
                local last = chain[#chain].Position; local bi, bd = 1, math.huge
                for i, r in ipairs(remaining) do local d = (r.Position - last).Magnitude; if d < bd then bi, bd = i, d end end
                chain[#chain + 1] = table.remove(remaining, bi)
            end
            rows = chain
        end
    end
    return rows
end

local function discoverPath()
    local map = Workspace:FindFirstChild("Map")
    local exact = map and map:FindFirstChild("Path")
    local root, source = nil, nil
    if exact and #orderedPoints(exact) >= 2 then root, source = exact, "workspace.Map.Path" end
    if not root and map then
        local best, bestCount = nil, 0
        for _, d in ipairs(map:GetDescendants()) do
            if (d:IsA("Folder") or d:IsA("Model")) then
                local n = normalize(d.Name)
                local full = normalize(d:GetFullName())
                if (n == "path" or n:find("waypoint", 1, true) or n == "nodes") and not full:find("visualeffect", 1, true) and not full:find("pathvisualizer", 1, true) then
                    local rows = orderedPoints(d)
                    if #rows > bestCount then best, bestCount = d, #rows end
                end
            end
        end
        if best and bestCount >= 2 then root, source = best, best:GetFullName() end
    end
    if not root then PathState = {Root = nil, Points = {}, Segments = {}, Length = 0, Source = "UNKNOWN"}; return PathState end
    local rows = orderedPoints(root)
    local points, segments, total = {}, {}, 0
    for _, r in ipairs(rows) do points[#points + 1] = r.Position end
    for i = 1, #points - 1 do
        local a, b = points[i], points[i + 1]
        local len = (b - a).Magnitude
        if len > 0.01 and len < 1000 then
            segments[#segments + 1] = {A = a, B = b, Length = len, Mid = (a + b) / 2}
            total = total + len
        end
    end
    PathState = {Root = root, Points = points, Segments = segments, Length = total, Source = source}
    return PathState
end

local function pointSegmentDistanceXZ(p, a, b)
    local px, pz = p.X, p.Z; local ax, az = a.X, a.Z; local bx, bz = b.X, b.Z
    local dx, dz = bx - ax, bz - az
    local denom = dx * dx + dz * dz
    if denom <= 1e-9 then return math.sqrt((px - ax)^2 + (pz - az)^2) end
    local t = math.clamp(((px - ax) * dx + (pz - az) * dz) / denom, 0, 1)
    local x, z = ax + dx * t, az + dz * t
    return math.sqrt((px - x)^2 + (pz - z)^2)
end

local function coveredLength(pos, range)
    if not range then return 0 end
    local total = 0
    for _, s in ipairs(PathState.Segments) do
        if pointSegmentDistanceXZ(pos, s.A, s.B) <= range then total = total + s.Length end
    end
    return total
end

local function rayGround(x, z, yHint)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LocalPlayer.Character}
    local origin = Vector3.new(x, (yHint or 0) + 120, z)
    return Workspace:Raycast(origin, Vector3.new(0, -260, 0), params)
end

local PlacementCache = {}
local function placementCandidates(profile, upgrade, maxReturn)
    if not profile or not upgrade or not upgrade.Range or #PathState.Points < 2 then return {} end
    local cacheKey = profile.Asset .. ":" .. tostring(upgrade.Level) .. ":" .. tostring(PathState.Root)
    if PlacementCache[cacheKey] then return PlacementCache[cacheKey] end
    local range = upgrade.Range
    local offsets = {}
    for _, x in ipairs({4, 7, 10, 14, 18, 24, 30, 38}) do if x <= math.max(5, range * 0.82) then offsets[#offsets + 1] = x end end
    if #offsets == 0 then offsets[1] = math.max(3, range * 0.4) end
    local candidates = {}
    local stride = math.max(1, math.floor(#PathState.Points / 35))
    for i = 1, #PathState.Points, stride do
        local point = PathState.Points[i]
        local before = PathState.Points[math.max(1, i - 1)]
        local after = PathState.Points[math.min(#PathState.Points, i + 1)]
        local dir = Vector2.new(after.X - before.X, after.Z - before.Z)
        if dir.Magnitude > 0.01 then
            dir = dir.Unit; local normal = Vector2.new(-dir.Y, dir.X)
            for _, offset in ipairs(offsets) do
                for _, sign in ipairs({-1, 1}) do
                    local x = point.X + normal.X * offset * sign; local z = point.Z + normal.Y * offset * sign
                    local hit = rayGround(x, z, point.Y)
                    if hit then
                        local pos = hit.Position + Vector3.new(0, 0.15, 0)
                        local cover = coveredLength(pos, range)
                        candidates[#candidates + 1] = {Position = pos, Covered = cover, Ratio = PathState.Length > 0 and cover / PathState.Length or 0, Ground = hit.Instance and hit.Instance:GetFullName() or "raycast"}
                    end
                end
            end
        end
    end
    table.sort(candidates, function(a, b) return a.Covered > b.Covered end)
    local out = {}
    for _, c in ipairs(candidates) do
        local distinct = true
        for _, old in ipairs(out) do
            if Vector2.new(c.Position.X - old.Position.X, c.Position.Z - old.Position.Z).Magnitude < math.max(3, math.min(8, range * 0.18)) then distinct = false; break end
        end
        if distinct then out[#out + 1] = c; if #out >= (maxReturn or 8) then break end end
    end
    PlacementCache[cacheKey] = out
    return out
end

-- ============================================================
-- LIVE STATE: Yen / Wave / placed units / enemies
-- ============================================================

local function scalarRuntime(names)
    if type(getgc) ~= "function" then return nil, "getgc unavailable" end
    local ok, objects = pcall(getgc, true); if not ok then return nil, "getgc failed" end
    local bestValue, bestScore, bestSource = nil, -1, nil
    for _, obj in ipairs(objects) do
        if type(obj) == "table" then
            for _, holder in ipairs({obj, rawget(obj, "Data")}) do
                if type(holder) == "table" then
                    local v, actual = getCI(holder, names)
                    if type(v) == "number" then
                        local score = 1
                        local token = tostring(rawget(obj, "Token") or ""):lower()
                        if token:find("game", 1, true) or token:find("match", 1, true) or token:find("wave", 1, true) then score = score + 5 end
                        if getCI(holder, {"Wave", "CurrentWave"}) ~= nil and getCI(holder, {"Yen", "CurrentYen", "Money"}) ~= nil then score = score + 6 end
                        if score > bestScore then bestValue, bestScore, bestSource = v, score, "getgc " .. tostring(actual) .. (token ~= "" and (" token=" .. token) or "") end
                    end
                end
            end
        end
    end
    return bestValue, bestSource or "UNKNOWN"
end

local function modelOwnerMine(model, record)
    local function test(v)
        if v == LocalPlayer then return true end
        if type(v) == "number" and v == LocalPlayer.UserId then return true end
        if type(v) == "string" and (v == LocalPlayer.Name or tonumber(v) == LocalPlayer.UserId) then return true end
        return false
    end
    if type(record) == "table" then
        for _, key in ipairs({"Player", "Owner", "OwnerPlayer", "PlacedBy", "UserId", "OwnerUserId"}) do if test(getCI(record, {key})) then return true end end
    end
    for _, key in ipairs({"Player", "Owner", "OwnerPlayer", "PlacedBy", "UserId", "OwnerUserId"}) do if test(model:GetAttribute(key)) then return true end end
    for _, name in ipairs({"Owner", "Player", "PlacedBy"}) do
        local v = model:FindFirstChild(name)
        if v and v:IsA("ObjectValue") and v.Value == LocalPlayer then return true end
        if v and (v:IsA("IntValue") or v:IsA("StringValue")) and test(v.Value) then return true end
    end
    return false
end

local function scanPlacedUnits()
    local out, seen = {}, {}
    if type(getgc) == "function" then
        local ok, objects = pcall(getgc, true)
        if ok then
            for _, r in ipairs(objects) do
                if type(r) == "table" then
                    local model = getCI(r, {"Model", "UnitModel", "Instance", "Character"})
                    local rawAsset = getCI(r, {"Asset", "Unit", "UnitName", "UnitAsset"})
                    local asset = rawAsset and UnitAlias[normalize(rawAsset)] or nil
                    if asset and typeof(model) == "Instance" and model:IsA("Model") and model:IsDescendantOf(Workspace) and not seen[model] and modelOwnerMine(model, r) then
                        local okP, cf = pcall(model.GetPivot, model)
                        if okP then
                            local upgrade = tonumber(getCI(r, {"Upgrade", "UpgradeLevel", "CurrentUpgrade", "Level"}))
                            out[#out + 1] = {Model = model, Asset = asset, Position = cf.Position, Upgrade = upgrade, Source = "getgc model record"}; seen[model] = true
                        end
                    end
                end
            end
        end
    end
    local roots = {}
    local map = Workspace:FindFirstChild("Map")
    for _, name in ipairs({"Units", "PlacedUnits", "Towers", "UnitModels", "UnitReplicas"}) do
        local r = Workspace:FindFirstChild(name); if r then roots[#roots + 1] = r end
        if map then local mr = map:FindFirstChild(name); if mr then roots[#roots + 1] = mr end end
    end
    for _, root in ipairs(roots) do
        for _, model in ipairs(root:GetDescendants()) do
            if model:IsA("Model") and not seen[model] and modelOwnerMine(model) then
                local rawAsset = model:GetAttribute("Asset") or model:GetAttribute("Unit") or model.Name
                local asset = UnitAlias[normalize(rawAsset)]
                if asset then
                    local okP, cf = pcall(model.GetPivot, model)
                    if okP then
                        local upgrade = tonumber(model:GetAttribute("Upgrade") or model:GetAttribute("UpgradeLevel") or model:GetAttribute("CurrentUpgrade"))
                        out[#out + 1] = {Model = model, Asset = asset, Position = cf.Position, Upgrade = upgrade, Source = "workspace owner evidence"}; seen[model] = true
                    end
                end
            end
        end
    end
    return out
end

local function scanVisibleEnemies()
    local out, seen = {}, {}
    local roots = {}
    local map = Workspace:FindFirstChild("Map")
    for _, name in ipairs({"Enemies", "EnemyModels", "Mobs"}) do
        local r = Workspace:FindFirstChild(name); if r then roots[#roots + 1] = r end
        if map then local mr = map:FindFirstChild(name); if mr then roots[#roots + 1] = mr end end
    end
    for _, root in ipairs(roots) do
        for _, m in ipairs(root:GetDescendants()) do
            if m:IsA("Model") and not seen[m] then
                local raw = m:GetAttribute("Asset") or m:GetAttribute("Enemy") or m.Name
                local asset = EnemyAlias[normalize(raw)]
                if asset then
                    local okP, cf = pcall(m.GetPivot, m)
                    if okP then
                        local hum = m:FindFirstChildOfClass("Humanoid")
                        local ep = enemyProfile(asset)
                        out[#out + 1] = {Model = m, Asset = asset, Position = cf.Position, Health = hum and hum.Health or nil, MaxHealth = hum and hum.MaxHealth or nil, Speed = hum and hum.WalkSpeed or ep.Speed, Profile = ep}; seen[m] = true
                    end
                end
            end
        end
    end
    return out
end

local function nextUpgrade(profile, currentLevel)
    currentLevel = tonumber(currentLevel)
    if not currentLevel then return nil, nil end
    local current, nextU
    for i, u in ipairs(profile.Upgrades) do
        if u.Level == currentLevel then current = u; nextU = profile.Upgrades[i + 1]; break end
    end
    return nextU, current
end

local function avgVisibleSpeed(enemies)
    local total, n = 0, 0
    for _, e in ipairs(enemies) do if tonumber(e.Speed) and e.Speed > 0 then total = total + e.Speed; n = n + 1 end end
    return n > 0 and total / n or nil
end

local function opportunity(dps, covered, mult, speed)
    local value = (dps or 0) * (covered or 0) * (mult or 1)
    if speed and speed > 0 then value = value / speed end
    return value
end

local function liveActions(profiles, hotbarTeam, facts, yen, placed, visible, strategy)
    local actions, counts = {}, {}
    for _, u in ipairs(placed) do counts[u.Asset] = (counts[u.Asset] or 0) + 1 end
    local speed = avgVisibleSpeed(visible)
    for _, unit in ipairs(placed) do
        local p = profiles[unit.Asset]
        if p and unit.Upgrade ~= nil then
            local nextU, currentU = nextUpgrade(p, unit.Upgrade)
            if nextU and currentU and nextU.Cost > 0 then
                local mult = stageElement(p, facts).Multiplier or 1
                local curCov = currentU.Range and coveredLength(unit.Position, currentU.Range) or 0
                local nextCov = nextU.Range and coveredLength(unit.Position, nextU.Range) or curCov
                local gain = opportunity(nextU.RawDPS, nextCov, mult, speed) - opportunity(currentU.RawDPS, curCov, mult, speed)
                actions[#actions + 1] = {Type = "UPGRADE", Asset = p.Asset, Cost = nextU.Cost, Gain = gain, GainPerYen = gain / nextU.Cost, Detail = "U" .. tostring(currentU.Level) .. " -> U" .. tostring(nextU.Level) .. " | raw DPS " .. formatNumber(currentU.RawDPS, 1) .. " -> " .. formatNumber(nextU.RawDPS, 1), Position = unit.Position, Affordable = yen and yen >= nextU.Cost or nil}
            end
        end
    end
    local hotbarSet = {}
    for _, p in ipairs(hotbarTeam) do hotbarSet[p.Asset] = p end
    for _, p in pairs(hotbarSet) do
        local ok = legal(p, facts)
        if ok and p.Base and (counts[p.Asset] or 0) < p.PlacementLimit then
            local candidates = placementCandidates(p, p.Base, 3)
            local c = candidates[1]
            if c and p.Base.CumulativeCost > 0 then
                local mult = stageElement(p, facts).Multiplier or 1
                local gain = opportunity(p.Base.RawDPS, c.Covered, mult, speed)
                if p.Farm and p.FarmIncomeKnown then
                    local income = p.Base.Income or 0
                    gain = gain + income * 0.01 -- tiny tie-break only; not converted into fake combat DPS
                end
                actions[#actions + 1] = {Type = "PLACE", Asset = p.Asset, Cost = p.Base.CumulativeCost, Gain = gain, GainPerYen = gain / p.Base.CumulativeCost, Detail = "U" .. tostring(p.Base.Level) .. " | DPS=" .. formatNumber(p.Base.RawDPS, 1) .. " | range=" .. formatNumber(p.Base.Range, 1) .. " | path=" .. formatNumber(c.Covered, 1), Position = c.Position, Coverage = c.Covered, Affordable = yen and yen >= p.Base.CumulativeCost or nil, Farm = p.Farm}
            end
        end
    end
    table.sort(actions, function(a, b)
        if strategy == "Max Damage" then
            if a.Gain ~= b.Gain then return a.Gain > b.Gain end
        else
            if a.GainPerYen ~= b.GainPerYen then return a.GainPerYen > b.GainPerYen end
        end
        return a.Gain > b.Gain
    end)
    return actions
end

-- ============================================================
-- NATIVE GUI (no external UI library)
-- ============================================================

local parentGui
pcall(function() if gethui then parentGui = gethui() end end)
parentGui = parentGui or game:GetService("CoreGui")
if not parentGui then parentGui = LocalPlayer:WaitForChild("PlayerGui") end

local Gui = Instance.new("ScreenGui")
Gui.Name = "AE_Strategist_Standalone"
Gui.ResetOnSpawn = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = parentGui
App.Gui = Gui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(800, 565)
Main.Position = UDim2.new(0.5, -400, 0.5, -282)
Main.BackgroundColor3 = Color3.fromRGB(18, 20, 27)
Main.BorderSizePixel = 0
Main.Parent = Gui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 10)

local Top = Instance.new("Frame")
Top.Size = UDim2.new(1, 0, 0, 42); Top.BackgroundColor3 = Color3.fromRGB(25, 28, 38); Top.BorderSizePixel = 0; Top.Parent = Main
local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1; Title.Position = UDim2.fromOffset(14, 0); Title.Size = UDim2.new(1, -100, 1, 0); Title.Font = Enum.Font.GothamBold; Title.TextSize = 15; Title.TextColor3 = Color3.fromRGB(235, 238, 245); Title.TextXAlignment = Enum.TextXAlignment.Left; Title.Text = "AE Strategist | Standalone " .. VERSION; Title.Parent = Top
local Close = Instance.new("TextButton")
Close.Size = UDim2.fromOffset(34, 28); Close.Position = UDim2.new(1, -42, 0, 7); Close.BackgroundColor3 = Color3.fromRGB(45, 49, 64); Close.TextColor3 = Color3.new(1,1,1); Close.Text = "×"; Close.Font = Enum.Font.GothamBold; Close.TextSize = 18; Close.BorderSizePixel = 0; Close.Parent = Top; Instance.new("UICorner", Close).CornerRadius = UDim.new(0, 7)

local Sidebar = Instance.new("Frame")
Sidebar.Position = UDim2.fromOffset(0, 42); Sidebar.Size = UDim2.new(0, 150, 1, -42); Sidebar.BackgroundColor3 = Color3.fromRGB(22, 24, 33); Sidebar.BorderSizePixel = 0; Sidebar.Parent = Main
local sideList = Instance.new("UIListLayout", Sidebar); sideList.Padding = UDim.new(0, 5); sideList.HorizontalAlignment = Enum.HorizontalAlignment.Center
local pad = Instance.new("UIPadding", Sidebar); pad.PaddingTop = UDim.new(0, 10)

local Content = Instance.new("Frame")
Content.Position = UDim2.fromOffset(150, 42); Content.Size = UDim2.new(1, -150, 1, -42); Content.BackgroundTransparency = 1; Content.Parent = Main

local Tabs, TabButtons = {}, {}
local function makeTab(name)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -16, 0, 34); b.BackgroundColor3 = Color3.fromRGB(32, 35, 46); b.BorderSizePixel = 0; b.TextColor3 = Color3.fromRGB(210, 215, 225); b.Font = Enum.Font.GothamMedium; b.TextSize = 13; b.Text = name; b.Parent = Sidebar; Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
    local page = Instance.new("Frame")
    page.Size = UDim2.fromScale(1,1); page.BackgroundTransparency = 1; page.Visible = false; page.Parent = Content
    Tabs[name] = page; TabButtons[name] = b
    b.MouseButton1Click:Connect(function()
        for n, p in pairs(Tabs) do p.Visible = n == name; TabButtons[n].BackgroundColor3 = n == name and Color3.fromRGB(62, 72, 105) or Color3.fromRGB(32, 35, 46) end
    end)
    return page
end

local OverviewPage = makeTab("Overview")
local TeamPage = makeTab("Team Advisor")
local StagePage = makeTab("Stage")
local LivePage = makeTab("Live Assist")
local PlacementPage = makeTab("Placement")
local UnitPage = makeTab("Unit DB")
local DiagPage = makeTab("Diagnostics")

local function textPanel(page, y, height)
    local scroll = Instance.new("ScrollingFrame")
    scroll.Position = UDim2.fromOffset(10, y); scroll.Size = UDim2.new(1, -20, 0, height); scroll.BackgroundColor3 = Color3.fromRGB(23, 26, 35); scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 5; scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; scroll.CanvasSize = UDim2.new(); scroll.Parent = page; Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 8)
    local label = Instance.new("TextLabel")
    label.Position = UDim2.fromOffset(10, 8); label.Size = UDim2.new(1, -20, 0, 0); label.AutomaticSize = Enum.AutomaticSize.Y; label.BackgroundTransparency = 1; label.Font = Enum.Font.Code; label.TextSize = 13; label.TextColor3 = Color3.fromRGB(220, 224, 232); label.TextWrapped = true; label.TextXAlignment = Enum.TextXAlignment.Left; label.TextYAlignment = Enum.TextYAlignment.Top; label.Text = ""; label.Parent = scroll
    return label
end
local function guiButton(page, text, x, y, w, callback)
    local b = Instance.new("TextButton"); b.Position = UDim2.fromOffset(x,y); b.Size = UDim2.fromOffset(w,32); b.BackgroundColor3 = Color3.fromRGB(55,65,92); b.BorderSizePixel = 0; b.TextColor3 = Color3.new(1,1,1); b.Font = Enum.Font.GothamMedium; b.TextSize = 12; b.Text = text; b.Parent = page; Instance.new("UICorner", b).CornerRadius = UDim.new(0,7); b.MouseButton1Click:Connect(callback); return b
end
local function guiInput(page, placeholder, x, y, w, default)
    local box = Instance.new("TextBox"); box.Position = UDim2.fromOffset(x,y); box.Size = UDim2.fromOffset(w,32); box.BackgroundColor3 = Color3.fromRGB(31,35,47); box.BorderSizePixel = 0; box.TextColor3 = Color3.fromRGB(235,235,240); box.PlaceholderColor3 = Color3.fromRGB(130,135,150); box.Font = Enum.Font.Code; box.TextSize = 12; box.PlaceholderText = placeholder; box.Text = default or ""; box.ClearTextOnFocus = false; box.Parent = page; Instance.new("UICorner", box).CornerRadius = UDim.new(0,7); return box
end

local OverviewText = textPanel(OverviewPage, 10, 493)
local TeamText = textPanel(TeamPage, 52, 451)
local StageText = textPanel(StagePage, 10, 493)
local LiveText = textPanel(LivePage, 52, 451)
local PlacementText = textPanel(PlacementPage, 52, 451)
local UnitText = textPanel(UnitPage, 52, 451)
local DiagText = textPanel(DiagPage, 52, 451)

local BudgetBox = guiInput(TeamPage, "Budget", 10, 10, 105, "50000")
local TeamSizeBox = guiInput(TeamPage, "Team size", 122, 10, 90, "6")
local ManualStageBox = guiInput(TeamPage, "Gamemode | Map | Act | Difficulty", 219, 10, 270, "")

local State = {
    Strategy = "Balanced", Live = false, LiveToken = 0, Marker = nil,
    Scan = nil, Profiles = nil, Facts = nil, Stage = nil, CurrentMetrics = nil, Recommended = nil,
    LastLive = nil,
}
local STRATEGIES = {"Balanced", "Fast Clear", "Max Damage", "Safe Clear", "Boss"}
local StrategyIndex = 1

local function teamNames(team)
    local out = {}
    for _, p in ipairs(team or {}) do out[#out + 1] = p.DisplayName .. " [" .. p.Asset .. "]" end
    return #out > 0 and table.concat(out, ", ") or "none"
end
local function setNames(set)
    local out = {}; for k in pairs(set or {}) do out[#out + 1] = tostring(k) end; table.sort(out); return #out > 0 and table.concat(out, ", ") or "none"
end
local function delta(a, b)
    if not a or not b then return "?" end
    local d = b - a; local pct = a ~= 0 and d / math.abs(a) * 100 or nil
    return (d >= 0 and "+" or "") .. formatNumber(d, 2) .. (pct and (" (" .. (d >= 0 and "+" or "") .. formatNumber(pct,1) .. "%)") or "")
end

local function updateMarker(pos, text)
    if State.Marker then State.Marker:Destroy(); State.Marker = nil end
    if not pos then return end
    local part = Instance.new("Part"); part.Name = "AE_Strategist_Candidate"; part.Anchored = true; part.CanCollide = false; part.CanQuery = false; part.Material = Enum.Material.Neon; part.Transparency = 0.25; part.Size = Vector3.new(2.2,0.18,2.2); part.Position = pos + Vector3.new(0,0.12,0); part.Parent = Workspace
    local bill = Instance.new("BillboardGui"); bill.Size = UDim2.fromOffset(220,45); bill.StudsOffset = Vector3.new(0,2.2,0); bill.AlwaysOnTop = true; bill.Parent = part
    local lab = Instance.new("TextLabel"); lab.Size = UDim2.fromScale(1,1); lab.BackgroundColor3 = Color3.fromRGB(16,18,25); lab.BackgroundTransparency = 0.15; lab.TextColor3 = Color3.new(1,1,1); lab.TextWrapped = true; lab.Font = Enum.Font.GothamBold; lab.TextSize = 12; lab.Text = text or "Recommended candidate"; lab.Parent = bill
    State.Marker = part
end

local function currentProfilesFromScan(scan, profiles)
    local out, seen = {}, {}
    for _, h in ipairs(scan.Hotbar or {}) do if profiles[h.Asset] and not seen[h.Asset] then seen[h.Asset] = true; out[#out + 1] = profiles[h.Asset] end end
    return out
end

local function runAnalysis()
    TeamText.Text = "Analyzing owned units, hotbar, stage and DB evidence..."
    local scan = scanOwned(); State.Scan = scan
    if not scan.Found then
        TeamText.Text = "OWNED SCAN FAILED\n" .. tostring(scan.Unknown) .. "\n\nThe strategist refuses to recommend from somebody else's replica."
        return
    end
    local profiles = {}
    for asset, record in pairs(bestOwnedByAsset(scan)) do profiles[asset] = buildProfile(asset, record) end
    State.Profiles = profiles
    local manual = parseManualStage(ManualStageBox.Text)
    local stage = manual or detectStageRuntime(); State.Stage = stage
    local facts = extractStageFacts(stage); State.Facts = facts
    local currentTeam = currentProfilesFromScan(scan, profiles)
    local budget = tonumber(BudgetBox.Text) or facts.TotalYen or 50000
    local teamSize = math.max(1, math.min(8, tonumber(TeamSizeBox.Text) or math.max(1,#currentTeam)))
    local currentM = teamMetrics(currentTeam, facts, budget)
    local rec = recommend(profiles, currentTeam, facts, budget, teamSize, State.Strategy)
    State.CurrentMetrics, State.Recommended = currentM, rec

    local lines = {
        "OBJECTIVE: " .. State.Strategy,
        "BUDGET: ¥" .. formatNumber(budget,0),
        "STAGE: " .. (stage and (tostring(stage.Gamemode) .. " | " .. tostring(stage.MapName) .. " | " .. tostring(stage.ActName) .. " | " .. tostring(stage.Difficulty)) or "UNKNOWN"),
        "",
        "CURRENT HOTBAR:", teamNames(currentTeam),
        "",
        "RECOMMENDED OWNED TEAM:", teamNames(rec.Team),
        "",
        "CURRENT -> RECOMMENDED",
        "DPS @25% budget: " .. formatNumber(currentM.EarlyDPS,2) .. " -> " .. formatNumber(rec.EarlyDPS,2) .. " | " .. delta(currentM.EarlyDPS, rec.EarlyDPS),
        "DPS @50% budget: " .. formatNumber(currentM.MidDPS,2) .. " -> " .. formatNumber(rec.MidDPS,2) .. " | " .. delta(currentM.MidDPS, rec.MidDPS),
        "DPS @budget: " .. formatNumber(currentM.BudgetDPS,2) .. " -> " .. formatNumber(rec.BudgetDPS,2) .. " | " .. delta(currentM.BudgetDPS, rec.BudgetDPS),
        "Full placement-cap raw DPS: " .. formatNumber(currentM.FullDPS,2) .. " -> " .. formatNumber(rec.FullDPS,2) .. " | " .. delta(currentM.FullDPS, rec.FullDPS),
        "Threat misses: " .. tostring(#currentM.ThreatMisses) .. " -> " .. tostring(#rec.ThreatMisses),
        "Element net: " .. tostring(currentM.ElementNet) .. " -> " .. tostring(rec.ElementNet),
        "CC: " .. setNames(currentM.CC) .. " -> " .. setNames(rec.CC),
        "Shield counters: " .. tostring(currentM.Shield) .. " -> " .. tostring(rec.Shield),
        "",
        "BOUNDARY: raw DPS = DB Damage / SPA. Exact clear minutes are not claimed unless spawn timing and targeting exposure become validated.",
    }
    TeamText.Text = table.concat(lines, "\n")

    local stageLines = {
        stage and (tostring(stage.Gamemode) .. " | " .. tostring(stage.MapName) .. " | " .. tostring(stage.ActName) .. " | " .. tostring(stage.Difficulty)) or "STAGE UNKNOWN",
        "Sources: " .. (#facts.Sources > 0 and table.concat(facts.Sources," + ") or "UNKNOWN"),
        "Waves: " .. tostring(facts.WaveCount or "UNKNOWN"),
        "Duration: " .. tostring(facts.Duration or "UNKNOWN"),
        "Starting Yen: " .. tostring(facts.StartingYen or "UNKNOWN"),
        "Total Yen: " .. tostring(facts.TotalYen or "UNKNOWN"),
        "Farm: " .. (facts.NoFarm and "PROHIBITED (explicit)" or (facts.FarmAllowed and "allowed (explicit)" or "not explicitly stated")),
        "Fast enemies: " .. (#facts.FastEnemies > 0 and table.concat(facts.FastEnemies, ", ") or "none found"),
        "Shield enemies: " .. (#facts.ShieldEnemies > 0 and table.concat(facts.ShieldEnemies, ", ") or "none found"),
        "Bosses: " .. (#facts.Bosses > 0 and table.concat(facts.Bosses, ", ") or "none found"),
        "",
        "ENEMIES:",
    }
    for _, asset in ipairs(sortedKeys(facts.Enemies)) do
        local e = facts.Enemies[asset]; local p = e.Profile
        stageLines[#stageLines + 1] = string.format("%s x%s | element=%s speed=%s shield=%s type=%s", p.DisplayName, formatNumber(e.Count,0), tostring(p.Element or "?"), formatNumber(p.Speed,2), tostring(p.Shield), tostring(p.Type or "?"))
    end
    if #facts.Modifiers > 0 then stageLines[#stageLines + 1] = "\nMODIFIERS:\n- " .. table.concat(facts.Modifiers,"\n- ") end
    if #facts.Mechanics > 0 then stageLines[#stageLines + 1] = "\nENEMY MECHANICS:\n- " .. table.concat(facts.Mechanics,"\n- ") end
    if #facts.Unknowns > 0 then stageLines[#stageLines + 1] = "\nUNKNOWN:\n- " .. table.concat(facts.Unknowns,"\n- ") end
    StageText.Text = table.concat(stageLines,"\n")

    local ownedLines = {"OWNED SCAN", "Source: " .. tostring(scan.Source), "Validation score: " .. tostring(scan.Score), "Records: " .. tostring(#scan.Owned), "Hotbar: " .. tostring(#scan.Hotbar), "", "BEST OWNED COPY PER ASSET:"}
    for asset, p in pairs(profiles) do
        local r = p.OwnedRecord and p.OwnedRecord.Data or {}; ownedLines[#ownedLines + 1] = string.format("%s | Lv%s | trait=%s | element=%s | archetype=%s | limit=%s", p.Asset, tostring(getCI(r,{"Level"}) or "?"), tostring(getCI(r,{"Trait"}) or "none"), tostring(p.Element or "?"), tostring(p.Archetype or "?"), tostring(p.PlacementLimit))
    end
    UnitText.Text = table.concat(ownedLines,"\n")

    OverviewText.Text = table.concat({
        "AE STRATEGIST READY",
        "Standalone: YES — no AE_Assistant dependency.",
        "DB source: runtime Shared.Information first, AE_DB fallback.",
        "Owned records: " .. tostring(#scan.Owned),
        "Detected hotbar: " .. tostring(#scan.Hotbar),
        "Stage: " .. (stage and (stage.MapName .. " / " .. stage.ActName) or "UNKNOWN"),
        "Objective: " .. State.Strategy,
        "Recommended: " .. teamNames(rec.Team),
        "",
        "Use Live Assist after entering the map. Placement uses real path geometry when workspace.Map.Path (or a validated fallback) is present.",
    },"\n")

    local diag = {"VERSION: " .. VERSION, "PLACE ID: " .. tostring(game.PlaceId) .. (game.PlaceId == EXPECTED_PLACE_ID and " (expected)" or " (different)"), "", "DATABASE SOURCES:"}
    for _, key in ipairs(sortedKeys(DB.Source)) do diag[#diag + 1] = key .. " = " .. tostring(DB.Source[key]) end
    if countKeys(DB.Errors) > 0 then diag[#diag + 1] = "\nDB ERRORS:"; for k,v in pairs(DB.Errors) do diag[#diag + 1] = k .. " = " .. tostring(v) end end
    diag[#diag + 1] = "\nNO-SILENT-GUESS RULES:"
    diag[#diag + 1] = "- Ambiguous player replica => no recommendation."
    diag[#diag + 1] = "- Missing element multiplier => not invented."
    diag[#diag + 1] = "- Missing Farm income => no fake payback calculation."
    diag[#diag + 1] = "- Placement marker = derived candidate, not server-confirmed legality."
    diag[#diag + 1] = "- No gameplay remotes are fired."
    DiagText.Text = table.concat(diag,"\n")
    notify("AE Strategist", "Analysis complete", 5)
end

local function refreshLive(forcePath)
    if not State.Profiles or not State.Scan or not State.Scan.Found then return end
    if forcePath or not PathState.Root or not PathState.Root.Parent then PlacementCache = {}; discoverPath() end
    local yen, yenSource = scalarRuntime({"Yen", "CurrentYen", "Money", "Cash"})
    local wave, waveSource = scalarRuntime({"Wave", "CurrentWave", "WaveNumber"})
    local placed = scanPlacedUnits(); local visible = scanVisibleEnemies()
    local hotbarProfiles = currentProfilesFromScan(State.Scan, State.Profiles)
    local actions = liveActions(State.Profiles, hotbarProfiles, State.Facts or extractStageFacts(State.Stage), yen, placed, visible, State.Strategy)
    State.LastLive = {Yen=yen,Wave=wave,Placed=placed,Enemies=visible,Actions=actions,Path=PathState.Source}

    local lines = {
        "LIVE SNAPSHOT",
        "Yen: " .. tostring(yen or "UNKNOWN") .. " | " .. tostring(yenSource),
        "Wave: " .. tostring(wave or "UNKNOWN") .. " | " .. tostring(waveSource),
        "Path: " .. tostring(PathState.Source) .. " | length=" .. formatNumber(PathState.Length,1) .. " studs | points=" .. tostring(#PathState.Points),
        "Owned placed units (exact owner evidence): " .. tostring(#placed),
        "Visible recognized enemies: " .. tostring(#visible),
        "",
        "NEXT ACTION RANKING (derived opportunity, read-only):",
    }
    for i = 1, math.min(10,#actions) do
        local a = actions[i]
        lines[#lines + 1] = string.format("%d. %s %s | cost ¥%s | gain/yen=%s | %s%s", i, a.Type, a.Asset, formatNumber(a.Cost,0), formatNumber(a.GainPerYen,5), a.Detail, a.Affordable == nil and " | affordability UNKNOWN" or (a.Affordable and " | AFFORDABLE" or " | save money"))
    end
    if #actions == 0 then lines[#lines + 1] = "No validated action candidates. Common reasons: no exact placed-unit owner/upgrade data, path unavailable, or hotbar not detected." end
    LiveText.Text = table.concat(lines,"\n")

    local pLines = {"PATH / PLACEMENT", "Source: " .. tostring(PathState.Source), "Length: " .. formatNumber(PathState.Length,1), "", "BEST CURRENT PLACE ACTION:"}
    local bestPlace
    for _, a in ipairs(actions) do if a.Type == "PLACE" then bestPlace = a; break end end
    if bestPlace then
        pLines[#pLines + 1] = bestPlace.Asset .. " @ " .. string.format("(%.1f, %.1f, %.1f)", bestPlace.Position.X,bestPlace.Position.Y,bestPlace.Position.Z)
        pLines[#pLines + 1] = "Path covered: " .. formatNumber(bestPlace.Coverage,1) .. " studs"
        pLines[#pLines + 1] = "Reason: best derived attack-opportunity among current place candidates for objective " .. State.Strategy
        pLines[#pLines + 1] = "Hitbox note: radial Range exposure is the base geometry evidence. Exact Cone/Line target counts are not invented without validated orientation/width semantics."
        updateMarker(bestPlace.Position, "PLACE " .. bestPlace.Asset .. "\nDerived candidate")
    else
        pLines[#pLines + 1] = "No validated placement candidate"
        updateMarker(nil)
    end
    PlacementText.Text = table.concat(pLines,"\n")
end

local StrategyButton
guiButton(TeamPage, "ANALYZE", 496, 10, 86, function() task.spawn(runAnalysis) end)
StrategyButton = guiButton(TeamPage, "Balanced", 588, 10, 82, function()
    StrategyIndex = StrategyIndex % #STRATEGIES + 1; State.Strategy = STRATEGIES[StrategyIndex]; StrategyButton.Text = State.Strategy; task.spawn(runAnalysis)
end)

guiButton(LivePage, "REFRESH LIVE", 10, 10, 105, function() task.spawn(function() refreshLive(false) end) end)
local LiveToggle
guiButton(LivePage, "RESCAN PATH", 122, 10, 100, function() task.spawn(function() refreshLive(true) end) end)
LiveToggle = guiButton(LivePage, "LIVE: OFF", 229, 10, 90, function()
    State.Live = not State.Live; State.LiveToken = State.LiveToken + 1; LiveToggle.Text = State.Live and "LIVE: ON" or "LIVE: OFF"
    if State.Live then
        local token = State.LiveToken
        task.spawn(function()
            while State.Live and token == State.LiveToken and not App.Destroyed do
                pcall(refreshLive, false)
                task.wait(1.5)
            end
        end)
    end
end)
guiButton(LivePage, "CLEAR MARKER", 326, 10, 105, function() updateMarker(nil) end)
guiButton(PlacementPage, "RESCAN + SCORE", 10, 10, 125, function() task.spawn(function() refreshLive(true) end) end)
guiButton(UnitPage, "REFRESH OWNED", 10, 10, 115, function() task.spawn(runAnalysis) end)
guiButton(DiagPage, "SAVE SNAPSHOT", 10, 10, 115, function()
    if not writefile then notify("AE Strategist", "writefile unavailable", 5); return end
    if makefolder then pcall(makefolder, "AE_Strategist") end
    local payload = {
        Version=VERSION, DatabaseSource=DB.Source, Stage=State.Stage,
        Facts=State.Facts, LastLive=State.LastLive,
    }
    local ok, json = pcall(function() return HttpService:JSONEncode(payload) end)
    if ok then local wrote, err = pcall(writefile,"AE_Strategist/snapshot.json",json); notify("AE Strategist", wrote and "Saved AE_Strategist/snapshot.json" or tostring(err),6) else notify("AE Strategist","snapshot encode failed",6) end
end)

-- Drag window
local dragging, dragStart, startPos = false, nil, nil
Top.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; dragStart = input.Position; startPos = Main.Position end
end)
Top.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
App.Connections[#App.Connections + 1] = UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale,startPos.X.Offset+delta.X,startPos.Y.Scale,startPos.Y.Offset+delta.Y)
    end
end)

local visible = true
App.Connections[#App.Connections + 1] = UserInputService.InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.K then visible = not visible; Main.Visible = visible end
end)

function App.Destroy()
    if App.Destroyed then return end
    App.Destroyed = true; State.Live = false; State.LiveToken = State.LiveToken + 1
    updateMarker(nil)
    for _, c in ipairs(App.Connections) do pcall(function() c:Disconnect() end) end
    if Gui then pcall(function() Gui:Destroy() end) end
    if ENV.AE_STRATEGIST == App then ENV.AE_STRATEGIST = nil end
end
Close.MouseButton1Click:Connect(App.Destroy)

App.RefreshAnalysis = runAnalysis
App.RefreshLive = refreshLive
App.GetPlacementCandidates = function(asset, upgradeLevel)
    local p = State.Profiles and State.Profiles[UnitAlias[normalize(asset)] or asset]
    if not p then return {} end
    local u
    for _, row in ipairs(p.Upgrades) do if row.Level == tonumber(upgradeLevel) then u = row; break end end
    if not u then u = p.Base end
    if not PathState.Root then discoverPath() end
    return placementCandidates(p,u,12)
end
App.GetState = function() return State end

Tabs["Overview"].Visible = true; TabButtons["Overview"].BackgroundColor3 = Color3.fromRGB(62,72,105)
OverviewText.Text = "Loading standalone strategist..."
task.spawn(function()
    pcall(runAnalysis)
    pcall(function() discoverPath() end)
end)
notify("AE Strategist", "Standalone loaded. K = hide/show. No AE_Assistant dependency.", 8)
print("[AE Strategist] READY", VERSION, "PlaceId", game.PlaceId)
