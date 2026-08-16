--[[
AE TOURNAMENT AUTOPILOT | BRAIN M1
----------------------------------
Read-only, one-shot Tournament decision engine.

M1 outputs a stable decision model for the future execution layer:
- owned-copy team recommendation
- per-unit target priority
- per-unit target upgrade
- Farm / no-Farm decision with exact-income ROI when available
- top-view route + per-unit Sweet Spots
- initial action queue (Place / Upgrade / Farm / Save / Target)

No gameplay remotes are fired. No background polling is started.
]]

return function(config)
    config = config or {}

    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local HttpService = game:GetService("HttpService")
    local Workspace = game:GetService("Workspace")
    local LocalPlayer = Players.LocalPlayer

    local Brain = {
        Version = "brain-m1.0.0",
        Config = config,
        Cache = {},
        Diagnostics = {},
        State = nil,
        Destroyed = false,
    }

    local RAW_DB = config.DatabaseRoot or "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_DB/"

    -- -------------------------------------------------------------------------
    -- Utilities
    -- -------------------------------------------------------------------------

    local function norm(value)
        return tostring(value or ""):lower():gsub("[^%w]", "")
    end

    local function trim(value)
        return tostring(value or ""):match("^%s*(.-)%s*$")
    end

    local function clamp(value, minimum, maximum)
        value = tonumber(value) or minimum
        if value < minimum then return minimum end
        if value > maximum then return maximum end
        return value
    end

    local function countKeys(value)
        local count = 0
        if type(value) == "table" then
            for _ in pairs(value) do count = count + 1 end
        end
        return count
    end

    local function shallowCopy(value)
        local output = {}
        for key, child in pairs(type(value) == "table" and value or {}) do
            output[key] = child
        end
        return output
    end

    local function arrayCopy(value)
        local output = {}
        for index, child in ipairs(type(value) == "table" and value or {}) do
            output[index] = child
        end
        return output
    end

    local function ci(tableValue, names)
        if type(tableValue) ~= "table" then return nil end
        local wanted = {}
        for _, name in ipairs(names or {}) do wanted[norm(name)] = true end
        for key, value in pairs(tableValue) do
            if wanted[norm(key)] then return value end
        end
        return nil
    end

    local function numberCI(tableValue, names)
        local value = ci(tableValue, names)
        return tonumber(value)
    end

    local function sortedKeys(value)
        local output = {}
        for key in pairs(type(value) == "table" and value or {}) do
            output[#output + 1] = key
        end
        table.sort(output, function(a, b)
            local numberA, numberB = tonumber(a), tonumber(b)
            if numberA and numberB then return numberA < numberB end
            return tostring(a) < tostring(b)
        end)
        return output
    end

    local function mergeSet(destination, source)
        for key, value in pairs(type(source) == "table" and source or {}) do
            if value then destination[key] = true end
        end
    end

    local function setCount(value)
        local count = 0
        for _, enabled in pairs(type(value) == "table" and value or {}) do
            if enabled then count = count + 1 end
        end
        return count
    end

    local function safeRequire(module)
        if not module or not module:IsA("ModuleScript") then return nil end
        local ok, result = pcall(require, module)
        if ok and type(result) == "table" then return result end
        return nil
    end

    local function safeJson(fileName)
        local ok, body = pcall(function()
            return game:HttpGet(RAW_DB .. fileName)
        end)
        if not ok then return {} end
        local decodedOk, decoded = pcall(function()
            return HttpService:JSONDecode(body)
        end)
        if decodedOk and type(decoded) == "table" then return decoded end
        return {}
    end

    local function unwrap(value, keys)
        if type(value) ~= "table" then return {} end
        for _, key in ipairs(keys or {}) do
            local child = value[key]
            if type(child) == "table" and countKeys(child) > 0 then return child end
        end
        return value
    end

    local function findModule(name, hints)
        for _, instance in ipairs(ReplicatedStorage:GetDescendants()) do
            if instance:IsA("ModuleScript") and instance.Name == name then
                local fullName = norm(instance:GetFullName())
                local valid = true
                for _, hint in ipairs(hints or {}) do
                    if not fullName:find(norm(hint), 1, true) then
                        valid = false
                        break
                    end
                end
                if valid then return instance end
            end
        end
        return nil
    end

    local function appendDiagnostic(message)
        Brain.Diagnostics[#Brain.Diagnostics + 1] = tostring(message)
    end

    -- -------------------------------------------------------------------------
    -- Database
    -- -------------------------------------------------------------------------

    local function loadDatabases()
        if Brain.Cache.Database then return Brain.Cache.Database end

        local Shared = ReplicatedStorage:FindFirstChild("Shared")
        local Information = Shared and Shared:FindFirstChild("Information")

        local function runtimeOrFile(runtimeName, fileName, unwrapKeys)
            local runtime = Information and safeRequire(Information:FindFirstChild(runtimeName)) or nil
            if type(runtime) == "table" and countKeys(runtime) > 0 then
                return unwrap(runtime, unwrapKeys), "runtime"
            end
            local fallback = safeJson(fileName)
            return unwrap(fallback, unwrapKeys), "github"
        end

        local Units, unitsSource = runtimeOrFile("Units", "units.json", {"Units", "UnitData", "Data", "Entries"})
        local Traits, traitsSource = runtimeOrFile("Traits", "traits.json", {"TraitData", "Traits", "Data", "Entries"})
        local Passives = runtimeOrFile("Passives", "passives.json", {"Passives", "Data", "Entries"})
        local Abilities = runtimeOrFile("Abilities", "abilities.json", {"Abilities", "Data", "Entries"})
        local Enemies = runtimeOrFile("Enemies", "enemies.json", {"Enemies", "Data", "Entries"})
        local Elements = runtimeOrFile("Elements", "elements.json", {"ElementData", "Elements", "Data", "Entries"})
        local GameMechanics = runtimeOrFile("GameMechanics", "game_mechanics.json", {"GameMechanics", "Data", "Entries"})

        local Equipment = safeRequire(findModule("Equipment", {"SheetSyncedModules"})) or {}
        Equipment = unwrap(Equipment, {"EquipmentData", "Equipment", "Data", "Entries", "Items"})

        local UnitLevel = safeRequire(findModule("UnitLevelInfo", {"SheetSyncedModules"})) or {}
        UnitLevel = unwrap(UnitLevel, {"LevelData", "Levels", "UnitLevels", "Data", "Entries"})

        local database = {
            Units = Units,
            Traits = Traits,
            Passives = Passives,
            Abilities = Abilities,
            Enemies = Enemies,
            Elements = Elements,
            GameMechanics = GameMechanics,
            Equipment = Equipment,
            UnitLevel = UnitLevel,
            Source = {
                Units = unitsSource,
                Traits = traitsSource,
            },
            EquipmentIndex = {},
            UnitAlias = {},
        }
