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

joined = joined:gsub("return value, key", "return value", 1)

local scanStart = string.find(joined, "    local function scanProfileData()\n", 1, true)
local nextStart = scanStart and string.find(joined, "    local function isUnitRecord", scanStart, true) or nil
if scanStart and nextStart then
    local replacement = [[    local function scanProfileData()
        local env = getgenv and getgenv() or _G

        local function inventoryEvidence(value)
            if type(value) ~= "table" then return false, nil, 0, 0 end
            local data = rawget(value, "Data")
            if type(data) ~= "table" then data = value end
            local unitData = ci(data, {"UnitData", "Units"})
            local hotbarData = ci(data, {"HotbarData", "Hotbar"})
            local ownedLike = 0
            if type(unitData) == "table" then
                local scanned = 0
                for key, child in pairs(unitData) do
                    scanned = scanned + 1
                    if scanned > 800 then break end
                    local keyText = tostring(key)
                    local guidKey = keyText:find("#", 1, true) ~= nil
                    local childAsset = type(child) == "table" and ci(child, {"Asset", "Unit", "UnitName"}) or nil
                    local progression = type(child) == "table" and ci(child, {"Level", "EXP", "Trait", "StatPotential", "Worthiness", "ObtainedAt", "Equipment"}) or nil
                    if guidKey or (type(childAsset) == "string" and progression ~= nil) then ownedLike = ownedLike + 1 end
                end
            end
            local hotbarCount = type(hotbarData) == "table" and countKeys(hotbarData) or 0
            local profileEvidence = ci(data, {"ProfileData", "ItemData", "HotbarData"}) ~= nil
            local valid = ownedLike >= 2 or (ownedLike >= 1 and hotbarCount >= 2) or (hotbarCount >= 4 and profileEvidence)
            return valid, data, ownedLike, hotbarCount
        end

        local override = env.AE_TOURNAMENT_PROFILE_OVERRIDE
        if type(override) == "table" then
            local valid, data = inventoryEvidence(override)
            if valid then return data, nil end
        end

        if type(getgc) ~= "function" then return nil, "getgc unavailable" end
        local ok, objects = pcall(getgc, true)
        if not ok or type(objects) ~= "table" then return nil, "getgc failed" end
        local bestData, bestScore = nil, -math.huge
        local inspectedTables = 0
        local function consider(candidate, sourceBoost)
            local valid, data, ownedLike, hotbarCount = inventoryEvidence(candidate)
            if not valid or type(data) ~= "table" then return end
            local score = ownedLike * 100 + hotbarCount * 35 + profilePlayerAffinity(candidate) + (sourceBoost or 0)
            if ci(data, {"ProfileData"}) ~= nil then score = score + 120 end
            if ci(data, {"ItemData"}) ~= nil then score = score + 40 end
            if score > bestScore then bestScore = score; bestData = data end
        end
        for index, object in ipairs(objects) do
            if type(object) == "table" then
                inspectedTables = inspectedTables + 1
                local direct57 = rawget(object, 57) or rawget(object, "57")
                if type(direct57) == "table" then
                    consider(direct57, 5000)
                    local d = rawget(direct57, "Data")
                    if type(d) == "table" then consider(d, 5200) end
                end
                for _, field in ipairs({"Replicas","ReplicaMap","ReplicaById","ReplicaByID","ActiveReplicas","ReplicaTable"}) do
                    local map = rawget(object, field)
                    if type(map) == "table" then
                        local candidate = rawget(map,57) or rawget(map,"57")
                        if type(candidate) == "table" then
                            consider(candidate,6000)
                            local d = rawget(candidate,"Data")
                            if type(d)=="table" then consider(d,6200) end
                        end
                    end
                end
                consider(object,0)
                local data=rawget(object,"Data")
                if type(data)=="table" then consider(data,25) end
            end
            if index>=30000 then break end
            if index%6000==0 then task.wait() end
        end
        appendDiagnostic("validated profile scan tables="..tostring(inspectedTables).." score="..tostring(bestScore))
        if not bestData then return nil,"validated inventory profile not found" end
        return bestData,nil
    end

]]
    joined = string.sub(joined,1,scanStart-1)..replacement..string.sub(joined,nextStart)
end

-- Probe-verified route: Workspace.Map.Paths contains exactly ordered Parts 1..43.
-- Live enemies report WaypointIndex 43 at the end, so this is the canonical route.
local pathStart = string.find(joined, "    local function discoverPath()\n", 1, true)
local pathNext = pathStart and string.find(joined, "    local function pathDistance", pathStart, true) or nil
if pathStart and pathNext then
    local strictPath = [[    local function discoverPath()
        local map = Workspace:FindFirstChild("Map")
        if not map then
            appendDiagnostic("verified path: Workspace.Map missing")
            return {}, "MAP_NOT_FOUND"
        end
        local pathRoot = map:FindFirstChild("Paths")
        if not pathRoot then
            appendDiagnostic("verified path: Workspace.Map.Paths missing")
            return {}, "MAP_PATHS_NOT_FOUND"
        end

        local indexed = {}
        local maxOrder = 0
        for _, child in ipairs(pathRoot:GetChildren()) do
            local order = tonumber(child.Name)
            local position = order and worldPosition(child) or nil
            if order and position then
                indexed[order] = {Position=position, Order=order, Name=child.Name, Instance=child}
                maxOrder = math.max(maxOrder, order)
            end
        end

        if maxOrder < 3 then
            return {}, "MAP_PATHS_NO_ORDER"
        end

        local points = {}
        for order = 1, maxOrder do
            if not indexed[order] then
                appendDiagnostic("verified path gap at "..tostring(order))
                return {}, "MAP_PATHS_GAP_"..tostring(order)
            end
            points[#points+1] = indexed[order]
        end

        appendDiagnostic("verified path resolved "..tostring(#points).." points from Workspace.Map.Paths")
        return points, "VERIFIED_MAP_PATHS_"..tostring(#points)
    end

]]
    joined = string.sub(joined,1,pathStart-1)..strictPath..string.sub(joined,pathNext)
else
    warn("[Tournament Brain] verified path patch marker missing")
end

local tailMarker = "    return Brain\nend"
local livePatch = [[
    function Brain:StartLiveReplicaCache()
        if self.LiveReplicaCache then return self.LiveReplicaCache end
        local cache={ProfileReplicaId=nil,GameReplicaId=nil,PlayerGameReplicaId=nil,ProfileFields={},Game={},PlayerGame={},Units={},Connections={}}
        self.LiveReplicaCache=cache
        local remoteRoot=ReplicatedStorage:FindFirstChild("RemoteEvents")
        if not remoteRoot then return cache end
        local function pathParts(path) local out={};if type(path)=="table" then for i,v in ipairs(path) do out[i]=tostring(v) end end;return out end
        local function onSet(replicaId,path,value)
            replicaId=tostring(replicaId or "");local p=pathParts(path);local first=p[1] or ""
            if first=="UnitData" then cache.ProfileReplicaId=replicaId;local unitId,field=p[2],p[3];if unitId and field then cache.ProfileFields[unitId]=cache.ProfileFields[unitId] or {};cache.ProfileFields[unitId][field]=value end
            elseif first=="ProfileData" then cache.ProfileReplicaId=cache.ProfileReplicaId or replicaId
            elseif first=="Wave" or first=="WaveIncome" or first=="GameTime" or first=="SessionTime" or first=="EnemyCount" or first=="Intermission" then cache.GameReplicaId=replicaId;cache.Game[first]=value
            elseif first=="Yen" or first=="TotalUnitsPlaced" or first=="PlacementCounts" or first=="AutoUpgradePriorities" then cache.PlayerGameReplicaId=replicaId;cache.PlayerGame[first]=value
            elseif first=="TargetPriority" or first=="Upgrade" or first=="SellValue" or first=="MaxUpgrade" or first=="IsFarm" then cache.Units[replicaId]=cache.Units[replicaId] or {};cache.Units[replicaId][first]=value end
        end
        local r=remoteRoot:FindFirstChild("ReplicaSet");if r and r:IsA("RemoteEvent") then cache.Connections[#cache.Connections+1]=r.OnClientEvent:Connect(onSet) end
        local rv=remoteRoot:FindFirstChild("ReplicaSetValues");if rv and rv:IsA("RemoteEvent") then cache.Connections[#cache.Connections+1]=rv.OnClientEvent:Connect(function(replicaId,path,values)
            replicaId=tostring(replicaId or "");if type(values)=="table" then cache.Units[replicaId]=cache.Units[replicaId] or {};local unit=cache.Units[replicaId];for _,key in ipairs({"CurrentStats","NextStats","SellValue","MaxUpgrade","Unsellable","IsFarm","Upgrade"}) do if values[key]~=nil then unit[key]=values[key] end end end
        end) end
        return cache
    end
    function Brain:GetLiveReplicaCache() return self.LiveReplicaCache end
    local _oldDestroy=Brain.Destroy
    function Brain:Destroy()
        if self.LiveReplicaCache and type(self.LiveReplicaCache.Connections)=="table" then for _,c in ipairs(self.LiveReplicaCache.Connections) do pcall(function()c:Disconnect()end) end end
        self.LiveReplicaCache=nil
        return _oldDestroy(self)
    end
    Brain:StartLiveReplicaCache()
    return Brain
end]]
local tailStart,tailEnd=string.find(joined,tailMarker,1,true)
if tailStart then joined=string.sub(joined,1,tailStart-1)..livePatch..string.sub(joined,tailEnd+1) end

local chunk, compileError=loadstring(joined)
if not chunk then error("Tournament Brain compile error: "..tostring(compileError)) end
return chunk()
