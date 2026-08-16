local ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Tournament_Autopilot/core_parts/"
local nonce = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
local parts = {"01.lua","02.lua","03.lua","04.lua","05.lua","06.lua","07.lua","08.lua"}
local source = {}
for _, path in ipairs(parts) do
    local ok, body = pcall(function()
        return game:HttpGet(ROOT .. path .. "?core=" .. nonce)
    end)
    if not ok then error("Tournament Brain part fetch failed " .. path .. ": " .. tostring(body)) end
    source[#source + 1] = body
end

local joined = table.concat(source, "\n")

-- A separate read-only probe can validate the exact local-player profile when an
-- executor hides it inside function upvalues. The Brain accepts only an override
-- that still passes its own named UnitData/HotbarData shape check.
local marker = "    local function scanProfileData()\n"
local replacement = [[    local function scanProfileData()
        local env = getgenv and getgenv() or _G
        local override = env.AE_TOURNAMENT_PROFILE_OVERRIDE
        if type(override) == "table" then
            local shaped, data = tableHasProfileShape(override)
            if shaped and type(data) == "table" then
                appendDiagnostic("profile override accepted from exact profile probe")
                return data, nil
            end
            appendDiagnostic("profile override rejected: named UnitData/HotbarData shape missing")
        end
]]

local startAt, endAt = string.find(joined, marker, 1, true)
if startAt then
    joined = string.sub(joined, 1, startAt - 1) .. replacement .. string.sub(joined, endAt + 1)
else
    warn("[Tournament Brain] profile override patch marker not found")
end

-- Evidence from the Replica probes gives us stable live identities without a GC
-- sweep: profile replica emits UnitData.*, game state emits Wave/GameTime/Income,
-- player-game state emits Yen/PlacementCounts, and GameUnit replicas emit
-- TargetPriority + CurrentStats/NextStats. This cache is passive/read-only and
-- intentionally does not trigger Brain analysis or UI redraws.
local tailMarker = "    return Brain\nend"
local livePatch = [[
    function Brain:StartLiveReplicaCache()
        if self.LiveReplicaCache then return self.LiveReplicaCache end
        local cache = {
            ProfileReplicaId = nil,
            GameReplicaId = nil,
            PlayerGameReplicaId = nil,
            ProfileFields = {},
            Game = {},
            PlayerGame = {},
            Units = {},
            Connections = {},
        }
        self.LiveReplicaCache = cache

        local remoteRoot = ReplicatedStorage:FindFirstChild("RemoteEvents")
        if not remoteRoot then return cache end

        local function pathParts(path)
            if type(path) ~= "table" then return {} end
            local out = {}
            for index, value in ipairs(path) do out[index] = tostring(value) end
            return out
        end

        local function onSet(replicaId, path, value)
            replicaId = tostring(replicaId or "")
            local parts = pathParts(path)
            local first = parts[1] or ""
            if first == "UnitData" then
                cache.ProfileReplicaId = replicaId
                local unitId = parts[2]
                local field = parts[3]
                if unitId and field then
                    cache.ProfileFields[unitId] = cache.ProfileFields[unitId] or {}
                    cache.ProfileFields[unitId][field] = value
                end
            elseif first == "ProfileData" then
                cache.ProfileReplicaId = cache.ProfileReplicaId or replicaId
            elseif first == "Wave" or first == "WaveIncome" or first == "GameTime" or first == "SessionTime" or first == "EnemyCount" or first == "Intermission" then
                cache.GameReplicaId = replicaId
                cache.Game[first] = value
            elseif first == "Yen" or first == "TotalUnitsPlaced" or first == "PlacementCounts" or first == "AutoUpgradePriorities" then
                cache.PlayerGameReplicaId = replicaId
                cache.PlayerGame[first] = value
            elseif first == "TargetPriority" or first == "Upgrade" or first == "SellValue" or first == "MaxUpgrade" or first == "IsFarm" then
                cache.Units[replicaId] = cache.Units[replicaId] or {}
                cache.Units[replicaId][first] = value
            end
        end

        local setRemote = remoteRoot:FindFirstChild("ReplicaSet")
        if setRemote and setRemote:IsA("RemoteEvent") then
            cache.Connections[#cache.Connections + 1] = setRemote.OnClientEvent:Connect(onSet)
        end

        local valuesRemote = remoteRoot:FindFirstChild("ReplicaSetValues")
        if valuesRemote and valuesRemote:IsA("RemoteEvent") then
            cache.Connections[#cache.Connections + 1] = valuesRemote.OnClientEvent:Connect(function(replicaId, path, values)
                replicaId = tostring(replicaId or "")
                if type(values) == "table" then
                    cache.Units[replicaId] = cache.Units[replicaId] or {}
                    local unit = cache.Units[replicaId]
                    for _, key in ipairs({"CurrentStats","NextStats","SellValue","MaxUpgrade","Unsellable","IsFarm","Upgrade"}) do
                        if values[key] ~= nil then unit[key] = values[key] end
                    end
                end
            end)
        end
        appendDiagnostic("passive Replica live cache started")
        return cache
    end

    function Brain:GetLiveReplicaCache()
        return self.LiveReplicaCache
    end

    local _oldDestroy = Brain.Destroy
    function Brain:Destroy()
        if self.LiveReplicaCache and type(self.LiveReplicaCache.Connections) == "table" then
            for _, connection in ipairs(self.LiveReplicaCache.Connections) do
                pcall(function() connection:Disconnect() end)
            end
        end
        self.LiveReplicaCache = nil
        return _oldDestroy(self)
    end

    Brain:StartLiveReplicaCache()

    return Brain
end]]
local tailStart, tailEnd = string.find(joined, tailMarker, 1, true)
if tailStart then
    joined = string.sub(joined, 1, tailStart - 1) .. livePatch .. string.sub(joined, tailEnd + 1)
else
    warn("[Tournament Brain] live cache patch marker not found")
end

local chunk, compileError = loadstring(joined)
if not chunk then error("Tournament Brain compile error: " .. tostring(compileError)) end
return chunk()
