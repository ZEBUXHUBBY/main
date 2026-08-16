-- AE Deep Mapper - targeted Stats + Equipment discovery
-- Read-only introspection + local JSON export. Does not invoke game remotes.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local VERSION = "AE-DM-StatsEquipment-1"
local OUT_DIR = "AE_DeepMapper"

local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {Title=title, Text=text, Duration=8})
    end)
end

local function safeString(v)
    local ok, s = pcall(tostring, v)
    return ok and s or "<tostring failed>"
end

local function typeName(v)
    local ok, t = pcall(typeof, v)
    return ok and t or type(v)
end

local function sanitize(v, depth, seen, maxDepth)
    depth = depth or 0
    seen = seen or {}
    maxDepth = maxDepth or 10
    if depth > maxDepth then return "<max-depth>" end

    local tv = typeName(v)
    if tv == "nil" or tv == "boolean" or tv == "number" or tv == "string" then return v end
    if tv == "Instance" then
        local out = {__type="Instance", class=v.ClassName, name=v.Name}
        pcall(function() out.path = v:GetFullName() end)
        return out
    end
    if tv == "Vector2" or tv == "Vector3" or tv == "Color3" or tv == "CFrame" or tv == "UDim" or tv == "UDim2" or tv == "EnumItem" then
        return {__type=tv, value=safeString(v)}
    end
    if type(v) == "function" then
        local out = {__type="function"}
        pcall(function()
            if debug and debug.getinfo then
                local info = debug.getinfo(v)
                if info then
                    out.info = {
                        name=info.name, source=info.source, short_src=info.short_src,
                        linedefined=info.linedefined, lastlinedefined=info.lastlinedefined,
                        what=info.what, nups=info.nups, numparams=info.numparams, isvararg=info.isvararg,
                    }
                end
            end
        end)
        if type(getconstants)=="function" then
            pcall(function() out.constants = sanitize(getconstants(v), depth+1, seen, math.min(maxDepth, 5)) end)
        end
        return out
    end
    if type(v) == "table" then
        if seen[v] then return "<cycle>" end
        seen[v] = true
        local out, n = {}, 0
        for k,val in pairs(v) do
            n += 1
            if n > 1200 then out["<truncated>"] = true break end
            local key = type(k)=="string" and k or safeString(k)
            out[key] = sanitize(val, depth+1, seen, maxDepth)
        end
        seen[v] = nil
        return out
    end
    return {__type=tv, value=safeString(v)}
end

local function findPath(root, dotted)
    local node = root
    for seg in string.gmatch(dotted, "[^%.]+") do
        node = node and node:FindFirstChild(seg)
        if not node then return nil end
    end
    return node
end

local TARGETS = {
    "Shared.Information.Units",
    "Shared.Information.Traits",
    "Shared.Information.StatPotential",
    "Shared.Information.UnitLevelInfo",
    "Shared.Information.Equipment",
    "Shared.Information.AssetTypes.Equipment.Info",
    "FusionPackage.Actions.GetCalculatedStatsFromData",
    "FusionPackage.Actions.GetEquipmentData",
    "Shared.UnitUtils.StatUtils",
    "FusionPackage.Components.Processors.Asset.UnitStats",
    "FusionPackage.Components.Processors.Asset.UnitPassives",
    "FusionPackage.Components.Processors.Asset.UnitTotalCost",
    "FusionPackage.Components.Menu.UnitInventory.StatLabel.EquipmentMultiplier",
}

local report = {
    version=VERSION, placeId=game.PlaceId, gameId=game.GameId, timestamp=os.time(),
    modules={}, ownedRuntimeSamples={}, candidateFunctions={}, errors={},
    capabilities={
        getgc=type(getgc)=="function", getconstants=type(getconstants)=="function",
        getupvalues=type(getupvalues)=="function", getloadedmodules=type(getloadedmodules)=="function",
        debug_getinfo=debug and type(debug.getinfo)=="function" or false,
        writefile=type(writefile)=="function", makefolder=type(makefolder)=="function",
    }
}

local function addError(where, err)
    report.errors[#report.errors+1] = {where=where, error=safeString(err)}
end

for _,path in ipairs(TARGETS) do
    local inst = findPath(ReplicatedStorage, path)
    local entry = {label=path, path=inst and inst:GetFullName() or path, requireOk=false}
    if inst and inst:IsA("ModuleScript") then
        local ok, result = pcall(require, inst)
        entry.requireOk = ok
        if ok then
            entry.resultType = typeName(result)
            entry.data = sanitize(result, 0, {}, 11)
        else
            entry.error = safeString(result)
        end
    else
        entry.error = "not found or not ModuleScript"
    end
    report.modules[#report.modules+1] = entry
end

-- Targeted GC search: capture only tables that look like live GameUnit data.
-- This is intentionally selective to avoid dumping the entire GC heap.
if type(getgc)=="function" then
    local ok, objects = pcall(getgc, true)
    if ok and type(objects)=="table" then
        local seenSample = {}
        local function scoreTable(t)
            local score = 0
            if rawget(t,"UnitData") ~= nil then score += 3 end
            if rawget(t,"CurrentStats") ~= nil then score += 3 end
            if rawget(t,"EquipmentData") ~= nil then score += 4 end
            if rawget(t,"GameID") ~= nil then score += 1 end
            if rawget(t,"UnitID") ~= nil then score += 1 end
            if rawget(t,"Upgrade") ~= nil then score += 1 end
            return score
        end
        for _,obj in ipairs(objects) do
            if type(obj)=="table" and scoreTable(obj) >= 6 and not seenSample[obj] then
                seenSample[obj] = true
                local sample = {
                    UnitID = sanitize(rawget(obj,"UnitID"),0,{},4),
                    GameID = sanitize(rawget(obj,"GameID"),0,{},4),
                    Upgrade = sanitize(rawget(obj,"Upgrade"),0,{},4),
                    UnitData = sanitize(rawget(obj,"UnitData"),0,{},10),
                    CurrentStats = sanitize(rawget(obj,"CurrentStats"),0,{},8),
                    NextStats = sanitize(rawget(obj,"NextStats"),0,{},8),
                    EquipmentData = sanitize(rawget(obj,"EquipmentData"),0,{},12),
                    Passives = sanitize(rawget(obj,"Passives"),0,{},10),
                    Element = sanitize(rawget(obj,"Element"),0,{},4),
                    Archetype = sanitize(rawget(obj,"Archetype"),0,{},4),
                    SellValue = sanitize(rawget(obj,"SellValue"),0,{},4),
                    IsFarm = sanitize(rawget(obj,"IsFarm"),0,{},4),
                }
                report.ownedRuntimeSamples[#report.ownedRuntimeSamples+1] = sample
                if #report.ownedRuntimeSamples >= 24 then break end
            end
        end

        -- Find functions likely involved in final stat/equipment math.
        local keywords = {
            "Damage","SPA","Range","CritChance","CritDamage","DoTDamage","Farm","Cost",
            "StatPotential","Potential","Level","DamageMulti","Trait","Equipment","GetCalculatedStats",
            "GetCalculatedStatsFromData","GetEquipmentData","Multiplier","Multiply","Add","Percent"
        }
        local matched = 0
        for _,obj in ipairs(objects) do
            if type(obj)=="function" and type(getconstants)=="function" then
                local okc, consts = pcall(getconstants, obj)
                if okc and type(consts)=="table" then
                    local hits, seen = {}, {}
                    for _,c in ipairs(consts) do
                        if type(c)=="string" then
                            local lc = string.lower(c)
                            for _,kw in ipairs(keywords) do
                                if string.find(lc, string.lower(kw), 1, true) and not seen[kw] then
                                    seen[kw] = true; hits[#hits+1] = kw
                                end
                            end
                        end
                    end
                    if #hits >= 2 then
                        local item = {hits=hits, constants=sanitize(consts,0,{},5)}
                        pcall(function()
                            if debug and debug.getinfo then item.info = sanitize(debug.getinfo(obj),0,{},5) end
                        end)
                        if type(getupvalues)=="function" then
                            pcall(function()
                                local ups = getupvalues(obj)
                                -- Upvalues can be enormous; keep depth low here.
                                item.upvalues = sanitize(ups,0,{},5)
                            end)
                        end
                        report.candidateFunctions[#report.candidateFunctions+1] = item
                        matched += 1
                        if matched >= 160 then break end
                    end
                end
            end
        end
        report.gcStats = {objects=#objects, runtimeSamples=#report.ownedRuntimeSamples, candidateFunctions=#report.candidateFunctions}
    else
        addError("getgc", objects)
    end
end

local encoded = HttpService:JSONEncode(report)
local filename = OUT_DIR.."/stats_equipment_discovery_"..tostring(os.time())..".json"
if type(makefolder)=="function" then pcall(makefolder, OUT_DIR) end
if type(writefile)=="function" then
    local ok, err = pcall(writefile, filename, encoded)
    if not ok then addError("writefile", err) end
else
    print(encoded)
end

getgenv().AE_DeepMapper_LastReport = report
getgenv().AE_DeepMapper_LastJSON = encoded
getgenv().AE_DeepMapper_LastFile = filename

print(string.format("[AE-DM] %s complete | modules=%d | runtime=%d | funcs=%d | file=%s",
    VERSION, #report.modules, #report.ownedRuntimeSamples, #report.candidateFunctions, filename))
notify("AE Deep Mapper", string.format("Stats+Equipment discovery complete | runtime %d | funcs %d", #report.ownedRuntimeSamples, #report.candidateFunctions))

return report
