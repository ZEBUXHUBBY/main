-- AE Deep Mapper - clean targeted Tournament discovery
-- Read-only introspection + local JSON export. Does not invoke game remotes.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local VERSION = "AE-DM-Tournament-Discovery-1"
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

local function sanitize(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if depth > 7 then return "<max-depth>" end

    local tv = typeName(v)
    if tv == "nil" or tv == "boolean" or tv == "number" or tv == "string" then
        return v
    end
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
                        name = info.name,
                        source = info.source,
                        short_src = info.short_src,
                        linedefined = info.linedefined,
                        lastlinedefined = info.lastlinedefined,
                        what = info.what,
                        nups = info.nups,
                        numparams = info.numparams,
                        isvararg = info.isvararg,
                    }
                end
            end
        end)
        if getconstants then
            pcall(function()
                local c = getconstants(v)
                out.constants = sanitize(c, depth+1, seen)
            end)
        end
        return out
    end
    if type(v) == "table" then
        if seen[v] then return "<cycle>" end
        seen[v] = true
        local out = {}
        local n = 0
        for k,val in pairs(v) do
            n += 1
            if n > 500 then
                out["<truncated>"] = true
                break
            end
            local key = type(k) == "string" and k or safeString(k)
            out[key] = sanitize(val, depth+1, seen)
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

local TARGET_MODULE_PATHS = {
    "Shared.Information.Tournaments",
    "FusionPackage.Components.Menu.Tournament.ScoreTypeInfo",
    "FusionPackage.Components.Menu.Tournament",
    "FusionPackage.Components.Menu.Tournament.Leaderboard",
    "FusionPackage.Components.Menu.Tournament.StatLabel",
    "FusionPackage.Components.Menu.Tournament.GlobalTournament",
    "FusionPackage.Components.Menu.Tournament.EntryPage",
}

local KEYWORDS = {
    "tournament","score","scores","scoretype","damage","damagedealt","kill","kills",
    "time","wave","multiplier","rank","ranking","leaderboard","penalty","bonus","boss",
    "takedown","clear","highest","global","bracket"
}

local function lower(v)
    return string.lower(safeString(v))
end

local function keywordHits(values)
    local hits = {}
    local set = {}
    for _,value in ipairs(values or {}) do
        local s = lower(value)
        for _,kw in ipairs(KEYWORDS) do
            if string.find(s, kw, 1, true) and not set[kw] then
                set[kw] = true
                hits[#hits+1] = kw
            end
        end
    end
    table.sort(hits)
    return hits
end

local report = {
    version = VERSION,
    placeId = game.PlaceId,
    gameId = game.GameId,
    timestamp = os.time(),
    capabilities = {
        getgc = type(getgc)=="function",
        getconstants = type(getconstants)=="function",
        getupvalues = type(getupvalues)=="function",
        debug_getinfo = debug and type(debug.getinfo)=="function" or false,
        getloadedmodules = type(getloadedmodules)=="function",
        writefile = type(writefile)=="function",
        makefolder = type(makefolder)=="function",
    },
    modules = {},
    gcFunctions = {},
    loadedTournamentModules = {},
    errors = {},
}

local function addError(where, err)
    report.errors[#report.errors+1] = {where=where, error=safeString(err)}
end

local function inspectModule(inst, label)
    local entry = {
        label = label,
        path = inst and inst:GetFullName() or label,
        class = inst and inst.ClassName or nil,
        requireOk = false,
    }
    if not inst or not inst:IsA("ModuleScript") then
        entry.error = "not found or not ModuleScript"
        report.modules[#report.modules+1] = entry
        return
    end
    local ok, result = pcall(require, inst)
    entry.requireOk = ok
    if ok then
        entry.resultType = typeName(result)
        entry.data = sanitize(result)
    else
        entry.error = safeString(result)
    end
    report.modules[#report.modules+1] = entry
end

for _,path in ipairs(TARGET_MODULE_PATHS) do
    local inst = findPath(ReplicatedStorage, path)
    inspectModule(inst, path)
end

if type(getloadedmodules) == "function" then
    local ok, mods = pcall(getloadedmodules)
    if ok and type(mods)=="table" then
        for _,m in ipairs(mods) do
            local path = ""
            pcall(function() path = m:GetFullName() end)
            local s = lower(path)
            if string.find(s,"tournament",1,true) or string.find(s,"scoretype",1,true) then
                report.loadedTournamentModules[#report.loadedTournamentModules+1] = {
                    path = path,
                    name = m.Name,
                    class = m.ClassName,
                }
            end
        end
    else
        addError("getloadedmodules", mods)
    end
end

if type(getgc)=="function" then
    local ok, objects = pcall(getgc, true)
    if ok and type(objects)=="table" then
        local scanned = 0
        local matched = 0
        for _,obj in ipairs(objects) do
            if type(obj)=="function" then
                scanned += 1
                local consts = nil
                if type(getconstants)=="function" then
                    pcall(function() consts = getconstants(obj) end)
                end
                local values = {}
                if type(consts)=="table" then
                    for _,c in ipairs(consts) do values[#values+1] = c end
                end
                local hits = keywordHits(values)
                if #hits > 0 then
                    matched += 1
                    local item = {
                        hits = hits,
                        constants = sanitize(consts or {}),
                    }
                    pcall(function()
                        if debug and debug.getinfo then
                            item.info = sanitize(debug.getinfo(obj))
                        end
                    end)
                    if type(getupvalues)=="function" then
                        pcall(function()
                            local ups = getupvalues(obj)
                            item.upvalues = sanitize(ups)
                        end)
                    end
                    report.gcFunctions[#report.gcFunctions+1] = item
                    if matched >= 300 then break end
                end
            end
        end
        report.gcStats = {scanned=scanned, matched=matched}
    else
        addError("getgc", objects)
    end
end

local encoded = HttpService:JSONEncode(report)
local filename = OUT_DIR.."/tournament_discovery_"..tostring(os.time())..".json"

if type(makefolder)=="function" then
    pcall(makefolder, OUT_DIR)
end
if type(writefile)=="function" then
    local ok, err = pcall(writefile, filename, encoded)
    if not ok then addError("writefile", err) end
else
    warn("[AE-DM] writefile unavailable; JSON printed below")
    print(encoded)
end

getgenv().AE_DeepMapper_LastReport = report
getgenv().AE_DeepMapper_LastJSON = encoded
getgenv().AE_DeepMapper_LastFile = filename

print(string.format("[AE-DM] %s complete | modules=%d | gc matches=%d | file=%s",
    VERSION,
    #report.modules,
    report.gcStats and report.gcStats.matched or 0,
    filename
))
notify("AE Deep Mapper", "Tournament discovery complete. Saved: "..filename)

return report
