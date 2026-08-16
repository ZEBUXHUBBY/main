--[[
AE TOURNAMENT AUTOPILOT M2.2
Standalone entrypoint. Passive Replica cache starts at boot; Brain analysis stays
manual. No gameplay remote is fired by this loader.
]]

local ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Tournament_Autopilot/"
local ENV = getgenv and getgenv() or _G
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local function notify(title, text)
    pcall(function() StarterGui:SetCore("SendNotification", {Title=title,Text=text,Duration=7}) end)
end

if type(ENV.AE_TOURNAMENT_AUTOPILOT) == "table" then
    local old = ENV.AE_TOURNAMENT_AUTOPILOT
    if old.UI and type(old.UI.Destroy) == "function" then pcall(function() old.UI:Destroy() end) end
    if old.Brain and type(old.Brain.Destroy) == "function" then pcall(function() old.Brain:Destroy() end) end
    if type(old.ExtraConnections)=="table" then for _,c in ipairs(old.ExtraConnections) do pcall(function()c:Disconnect()end) end end
end

local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local oldGui = playerGui:FindFirstChild("AE_Tournament_Autopilot_M1")
if oldGui then oldGui:Destroy() end

local nonce = tostring(os.time()) .. "-" .. tostring(math.random(100000,999999))
local function fetch(path)
    local ok, source = pcall(function() return game:HttpGet(ROOT .. path .. "?m22=" .. nonce) end)
    if not ok then return nil, tostring(source) end
    return source
end
local function compile(label, source)
    local chunk, compileError = loadstring(source)
    if not chunk then return nil, label .. " COMPILE ERROR: " .. tostring(compileError) end
    local ok, result = pcall(chunk)
    if not ok then return nil, label .. " RUNTIME ERROR: " .. tostring(result) end
    return result, nil
end

local coreSource, coreFetchError = fetch("core.lua")
if not coreSource then notify("Tournament Autopilot","Core fetch failed");warn(coreFetchError);return end
local coreFactory, coreCompileError = compile("CORE",coreSource)
if type(coreFactory)~="function" then notify("Tournament Autopilot","Core failed to load");warn(coreCompileError);return end
local brainOk, Brain = pcall(coreFactory,{DatabaseRoot="https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_DB/"})
if not brainOk or type(Brain)~="table" then notify("Tournament Autopilot","Brain initialization failed");warn(Brain);return end

-- Extend the core's passive cache with placed-unit and enemy state. This only
-- listens to incoming Replica traffic; it never sends a gameplay request.
local ExtraConnections = {}
local function augmentLiveTracking()
    if type(Brain.GetLiveReplicaCache)~="function" then return end
    local cache=Brain:GetLiveReplicaCache();if type(cache)~="table" then return end
    cache.Enemies=cache.Enemies or {};cache.ReplicaTypes=cache.ReplicaTypes or {};cache.Units=cache.Units or {}
    local root=ReplicatedStorage:FindFirstChild("RemoteEvents");if not root then return end
    local function pathFirst(path) return type(path)=="table" and tostring(path[1] or "") or tostring(path or "") end
    local unitKeys={TargetPriority=true,Upgrade=true,SellValue=true,MaxUpgrade=true,IsFarm=true,CurrentStats=true,NextStats=true,CFrame=true,Position=true,UnitData=true,Asset=true,Owner=true}
    local enemyKeys={WaypointIndex=true,PathProgress=true,Speed=true,Health=true,HP=true,MaxHealth=true,Shield=true,ShieldHealth=true,CFrame=true,Position=true,Resistances=true,Element=true,EnemyData=true}
    local function copyRelevant(target,value,keys,depth)
        depth=depth or 0;if type(value)~="table" or depth>3 then return end
        for k,v in pairs(value) do local key=tostring(k);if keys[key] then target[key]=v end;if type(v)=="table" then copyRelevant(target,v,keys,depth+1) end end
    end
    local function inferType(args)
        for i=1,args.n do if type(args[i])=="string" then local n=args[i]:lower();if n:find("gamespawnedenemy",1,true) or n:find("enemy",1,true) then return "GameSpawnedEnemy" elseif n:find("gameunit",1,true) then return "GameUnit" end end end
        return nil
    end
    local function inferId(args)
        local v=args[1];if type(v)=="number" or type(v)=="string" then return tostring(v) end
        return nil
    end
    local create=root:FindFirstChild("ReplicaCreate")
    if create and create:IsA("RemoteEvent") then ExtraConnections[#ExtraConnections+1]=create.OnClientEvent:Connect(function(...)
        local args=table.pack(...);local id=inferId(args);local kind=inferType(args);if not id or not kind then return end;cache.ReplicaTypes[id]=kind
        local target;if kind=="GameUnit" then cache.Units[id]=cache.Units[id] or {};target=cache.Units[id] else cache.Enemies[id]=cache.Enemies[id] or {};target=cache.Enemies[id] end
        target.ReplicaType=kind
        for i=1,args.n do if type(args[i])=="table" then copyRelevant(target,args[i],kind=="GameUnit" and unitKeys or enemyKeys,0) end end
    end) end
    local set=root:FindFirstChild("ReplicaSet")
    if set and set:IsA("RemoteEvent") then ExtraConnections[#ExtraConnections+1]=set.OnClientEvent:Connect(function(replicaId,path,value)
        local id=tostring(replicaId or "");local first=pathFirst(path);local kind=cache.ReplicaTypes[id]
        if enemyKeys[first] and (kind=="GameSpawnedEnemy" or first=="WaypointIndex" or first=="PathProgress" or first=="Speed" or first=="Health" or first=="Shield") then cache.Enemies[id]=cache.Enemies[id] or {};cache.Enemies[id][first]=value;cache.ReplicaTypes[id]=cache.ReplicaTypes[id] or "GameSpawnedEnemy"
        elseif unitKeys[first] and (kind=="GameUnit" or first=="TargetPriority" or first=="Upgrade" or first=="SellValue" or first=="CurrentStats" or first=="NextStats") then cache.Units[id]=cache.Units[id] or {};cache.Units[id][first]=value;cache.ReplicaTypes[id]=cache.ReplicaTypes[id] or "GameUnit" end
    end) end
    local values=root:FindFirstChild("ReplicaSetValues")
    if values and values:IsA("RemoteEvent") then ExtraConnections[#ExtraConnections+1]=values.OnClientEvent:Connect(function(replicaId,path,data)
        local id=tostring(replicaId or "");if type(data)~="table" then return end;local kind=cache.ReplicaTypes[id]
        if kind=="GameSpawnedEnemy" then cache.Enemies[id]=cache.Enemies[id] or {};copyRelevant(cache.Enemies[id],data,enemyKeys,0)
        else
            local looksUnit=data.CurrentStats~=nil or data.NextStats~=nil or data.SellValue~=nil or data.Upgrade~=nil or data.TargetPriority~=nil
            local looksEnemy=data.WaypointIndex~=nil or data.PathProgress~=nil or data.Speed~=nil or data.Health~=nil or data.Shield~=nil
            if looksEnemy and not looksUnit then cache.Enemies[id]=cache.Enemies[id] or {};copyRelevant(cache.Enemies[id],data,enemyKeys,0);cache.ReplicaTypes[id]="GameSpawnedEnemy" elseif looksUnit then cache.Units[id]=cache.Units[id] or {};copyRelevant(cache.Units[id],data,unitKeys,0);cache.ReplicaTypes[id]="GameUnit" end
        end
    end) end
    local destroy=root:FindFirstChild("ReplicaDestroy")
    if destroy and destroy:IsA("RemoteEvent") then ExtraConnections[#ExtraConnections+1]=destroy.OnClientEvent:Connect(function(replicaId)
        local id=tostring(replicaId or "");cache.Enemies[id]=nil;cache.Units[id]=nil;cache.ReplicaTypes[id]=nil
    end) end
end
augmentLiveTracking()

local uiSource, uiFetchError = fetch("ui.lua")
if not uiSource then Brain:Destroy();notify("Tournament Autopilot","UI fetch failed");warn(uiFetchError);return end
local uiFactory, uiCompileError = compile("UI",uiSource)
if type(uiFactory)~="function" then Brain:Destroy();notify("Tournament Autopilot","UI failed to load");warn(uiCompileError);return end
local uiOk, UI = pcall(uiFactory,Brain,{})
if not uiOk or type(UI)~="table" then Brain:Destroy();notify("Tournament Autopilot","UI initialization failed");warn(UI);return end

ENV.AE_TOURNAMENT_AUTOPILOT={
    Version="m2.2-live-combat-state",
    Brain=Brain,UI=UI,ExtraConnections=ExtraConnections,
    Live=function() return Brain:GetLiveReplicaCache() end,
    Destroy=function()
        for _,c in ipairs(ExtraConnections) do pcall(function()c:Disconnect()end) end
        if UI and type(UI.Destroy)=="function" then pcall(function()UI:Destroy()end) end
        if Brain and type(Brain.Destroy)=="function" then pcall(function()Brain:Destroy()end) end
        ENV.AE_TOURNAMENT_AUTOPILOT=nil
    end,
}
print("[AE Tournament Autopilot] M2.2 READY | model portraits + placed unit/enemy passive state")
