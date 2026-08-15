--[[
Anime Stars Game Profiler V1.4
PlaceId: 122553263569744

Changes from V1.3:
- Server-authoritative enemy registry from enemies/sync, enemies/added,
  enemies/respawned, enemies/damaged and enemies/died.
- Tracks dungeon room / EnemiesAlive and zone state.
- Tracks gacha/results, pity, abilities and drops.
- Compacts very large leaderboard/guild payloads.
- Outgoing observer tries hookfunction(RemoteEvent.FireServer) first,
  then falls back to __namecall. It records argc/all args when Path decoding fails.
- Passive observer only. It never sends FireServer/InvokeServer itself.
]]

if not game:IsLoaded() then game.Loaded:Wait() end

local EXPECTED_PLACE_ID = 122553263569744
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer
if not LP then error("[Profiler V1.4] LocalPlayer unavailable") end
local PlayerGui = LP:WaitForChild("PlayerGui")

local ENV = _G
if type(getgenv) == "function" then
    local ok, v = pcall(getgenv)
    if ok and type(v) == "table" then ENV = v end
end
if type(ENV.__ANIME_STARS_PROFILER_V14_CLEANUP) == "function" then
    pcall(ENV.__ANIME_STARS_PROFILER_V14_CLEANUP)
end

local Config = {
    Enabled = true,
    CaptureIncoming = true,
    CaptureOutgoing = true,
    HudInterval = 0.25,
    ContextWindow = 2.5,
    MaxTimeline = 5000,
    MaxActions = 500,
    MaxPayloadDepth = 4,
    MaxTableItems = 60,
    CompactHeavyPaths = true,
}

local State = {
    Version = "1.4",
    PlaceId = game.PlaceId,
    StartedUnix = os.time(),
    StartedClock = os.clock(),
    Enabled = true,
    Errors = {},
    Timeline = {},
    Actions = {},
    Incoming = { Observer=false, Packets=0, Items=0, Paths={} },
    Outgoing = { Available=false, Installed=false, HookMode="none", Calls=0, Items=0, Paths={}, Argc={} },
    Metrics = {
        Kills=0, Respawns=0, DamageEvents=0, EnemyDamageEvents=0,
        Drops=0, Rewards=0, AbilityExecuted=0, GachaBatches=0,
        RawPower=nil, StartPower=nil, PowerGained=0, ServerDamageTotal=nil,
    },
    World = {
        CurrentZone = "skylands",
        Enemies = {},
        ZoneCounts = {},
    },
    Dungeon = { Active=false, Zone=nil, Room=nil, EnemiesAlive=nil, Phase=nil, Duration=nil, StartTimestamp=nil, BestRoom=nil },
    Ability = { Cooldowns={}, Locks={}, SwapLockUntil=0, Executions={} },
    Gacha = { Pity={}, Spins=nil, Results={} },
    Drops = { Counts={}, Recent={} },
    Current = { TargetUUID=nil, TargetName=nil, TargetHealth=nil, TargetMaxHealth=nil, TargetDistance=nil },
}

local Connections = {}
local HudGui, HudText
local oldDirectFire = nil
local oldNamecall = nil

local function now()
    return os.clock() - State.StartedClock
end

local function log(msg)
    warn("[AnimeStars Profiler V1.4] " .. tostring(msg))
end

local function trim(arr, n)
    while #arr > n do table.remove(arr, 1) end
end

local function addError(where, err)
    table.insert(State.Errors, {Clock=now(), Where=tostring(where), Error=tostring(err)})
    trim(State.Errors, 100)
    log("ERROR " .. tostring(where) .. ": " .. tostring(err))
end

local function fullName(inst)
    local ok, value = pcall(function() return inst:GetFullName() end)
    return ok and value or tostring(inst)
end

local function safeValue(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local t = typeof(v)
    if t == "nil" or t == "boolean" or t == "number" or t == "string" then return v end
    if t == "Instance" then return {__type="Instance",Name=v.Name,ClassName=v.ClassName,FullName=fullName(v)} end
    if t == "Vector3" then return {__type="Vector3",X=v.X,Y=v.Y,Z=v.Z} end
    if t == "Vector2" then return {__type="Vector2",X=v.X,Y=v.Y} end
    if t == "CFrame" then local p=v.Position; return {__type="CFrame",X=p.X,Y=p.Y,Z=p.Z} end
    if t == "Color3" then return {__type="Color3",R=v.R,G=v.G,B=v.B} end
    if t == "EnumItem" then return tostring(v) end
    if t == "table" then
        if seen[v] then return "<cycle>" end
        if depth >= Config.MaxPayloadDepth then return "<max-depth>" end
        seen[v] = true
        local out, count = {}, 0
        for k, child in pairs(v) do
            count = count + 1
            if count > Config.MaxTableItems then out.__truncated = true break end
            out[type(k)=="string" and k or tostring(k)] = safeValue(child, depth+1, seen)
        end
        seen[v] = nil
        return out
    end
    return "<" .. tostring(t) .. ">"
end

local function pushTimeline(kind, path, payload, meta)
    local row = {Clock=now(), Unix=os.time(), Kind=kind, Path=path, Payload=payload, Meta=meta}
    table.insert(State.Timeline, row)
    trim(State.Timeline, Config.MaxTimeline)
    return row
end

local function eventItems(payload)
    local out = {}
    if type(payload) ~= "table" then return out end
    local saw = false
    for _, item in ipairs(payload) do
        saw = true
        if type(item) == "table" then table.insert(out, item) end
    end
    if not saw and type(payload.Path) == "string" then table.insert(out, payload) end
    return out
end

local function inc(tbl, key, amount)
    tbl[key] = (tbl[key] or 0) + (amount or 1)
end

local function getEventsRemote()
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    local packages = shared and shared:FindFirstChild("Packages")
    local events = packages and packages:FindFirstChild("Events")
    return events and events:FindFirstChild("RemoteEvent")
end

local EventsRemote = getEventsRemote()

local function currentRoot()
    local char = LP.Character
    return char and char:FindFirstChild("HumanoidRootPart") or nil
end

local function getPosition(info)
    if not info then return nil end
    if typeof(info.GroundPosition) == "Vector3" then return info.GroundPosition end
    if typeof(info.CFrame) == "CFrame" then return info.CFrame.Position end
    if type(info.GroundPosition) == "table" then
        local p=info.GroundPosition
        if tonumber(p.X) and tonumber(p.Y) and tonumber(p.Z) then return Vector3.new(p.X,p.Y,p.Z) end
    end
    return nil
end

local function mergeEnemy(zone, uuid, info)
    if type(uuid) ~= "string" then return end
    zone = tostring(zone or State.World.CurrentZone or "unknown")
    local rec = State.World.Enemies[uuid]
    if not rec then
        rec = {UUID=uuid, Zone=zone, Alive=true, FirstSeenClock=now(), DamageEvents=0, DamageTaken=0}
        State.World.Enemies[uuid] = rec
    end
    rec.Zone = zone
    rec.LastSeenClock = now()
    if type(info) == "table" then
        if info.Index ~= nil then rec.Index = info.Index end
        if info.Health ~= nil then rec.Health = info.Health end
        if info.MaxHealth ~= nil then rec.MaxHealth = info.MaxHealth end
        if info.Alive ~= nil then rec.Alive = info.Alive end
        if info.Scale ~= nil then rec.Scale = info.Scale end
        if info.GroundPosition ~= nil then rec.GroundPosition = info.GroundPosition end
        if info.CFrame ~= nil then rec.CFrame = info.CFrame end
        if info.DisplayDrops ~= nil then rec.DisplayDrops = info.DisplayDrops end
    end
    return rec
end

local function mergeEnemyBatch(zone, batch)
    if type(batch) ~= "table" then return end
    for uuid, info in pairs(batch) do
        if type(uuid) == "string" and type(info) == "table" then mergeEnemy(zone, uuid, info) end
    end
end

local function aliveEnemies(zone)
    local out = {}
    zone = zone or State.World.CurrentZone
    for _, rec in pairs(State.World.Enemies) do
        if rec.Alive ~= false and (zone == nil or rec.Zone == zone) then table.insert(out, rec) end
    end
    return out
end

local function refreshCurrentTarget()
    local root = currentRoot()
    local best, bestDistance = nil, nil
    local zone = State.World.CurrentZone
    for _, rec in ipairs(aliveEnemies(zone)) do
        local pos = getPosition(rec)
        if pos and root then
            local d = (pos-root.Position).Magnitude
            if bestDistance == nil or d < bestDistance then best,bestDistance=rec,d end
        elseif not best then best=rec end
    end
    if best then
        State.Current.TargetUUID=best.UUID
        State.Current.TargetName=best.Index
        State.Current.TargetHealth=best.Health
        State.Current.TargetMaxHealth=best.MaxHealth
        State.Current.TargetDistance=bestDistance
    else
        State.Current.TargetUUID=nil; State.Current.TargetName=nil; State.Current.TargetHealth=nil; State.Current.TargetMaxHealth=nil; State.Current.TargetDistance=nil
    end
end

local HEAVY = { ["leaderboard/update"]=true, ["guild/leaderboard"]=true, ["render/createList"]=true }
local function compactPayload(path, params)
    if Config.CompactHeavyPaths and HEAVY[path] then
        local out={Compacted=true}
        if type(params)=="table" then out.Arg1=safeValue(params[1],0,{}) end
        return out
    end
    if path=="enemies/sync" or path=="enemies/added" then
        local zone=type(params)=="table" and params[1] or nil
        local batch=type(params)=="table" and params[2] or nil
        local names={}, count=0
        if type(batch)=="table" then
            for uuid,info in pairs(batch) do
                count=count+1
                if count<=12 then table.insert(names,{UUID=uuid,Index=type(info)=="table" and info.Index or nil,Health=type(info)=="table" and info.Health or nil,MaxHealth=type(info)=="table" and info.MaxHealth or nil}) end
            end
        end
        return {Zone=zone,Count=count,Enemies=names}
    end
    return safeValue(params)
end

local function handleSync(params)
    if type(params)~="table" then return end
    local key,value=params[1],params[2]
    if key=="Power" and type(value)=="number" then
        State.Metrics.RawPower=value
        if State.Metrics.StartPower==nil then State.Metrics.StartPower=value end
        State.Metrics.PowerGained=value-State.Metrics.StartPower
    elseif key=="Stats.DamageDealt" and type(value)=="number" then State.Metrics.ServerDamageTotal=value
    elseif key=="zone" and type(value)=="string" then State.World.CurrentZone=value
    elseif type(key)=="string" and string.find(key,"GachaStats.PityCounters.",1,true)==1 then State.Gacha.Pity[key]=value
    elseif key=="GachaStats.ChampionSpins" then State.Gacha.Spins=value
    elseif type(key)=="string" and string.find(key,"Gamemodes.Dungeon.BestRooms.",1,true)==1 then State.Dungeon.BestRoom=value end
end

local function addDrop(item)
    if type(item)~="table" then return end
    local name=item.Name or item.Key or item.UniqueKey or "unknown"
    local amount=tonumber(item.Amount) or 1
    inc(State.Drops.Counts,name,amount)
    table.insert(State.Drops.Recent,{Clock=now(),Name=name,Amount=amount,Rarity=item.Rarity,UniqueKey=item.UniqueKey})
    trim(State.Drops.Recent,100)
end

local function processIncoming(item)
    if type(item)~="table" then return end
    local path=type(item.Path)=="string" and item.Path or "<unknown>"
    local params=item.Params
    State.Incoming.Items=State.Incoming.Items+1
    inc(State.Incoming.Paths,path)
    pushTimeline("IN",path,compactPayload(path,params))

    if path=="sync/update" then handleSync(params)
    elseif path=="enemies/sync" or path=="enemies/added" then
        local zone=type(params)=="table" and params[1] or nil
        local batch=type(params)=="table" and params[2] or nil
        mergeEnemyBatch(zone,batch)
    elseif path=="enemies/respawned" and type(params)=="table" then
        local zone,uuid,info=params[1],params[2],params[3]
        local rec=mergeEnemy(zone,uuid,info); if rec then rec.Alive=true; rec.Respawns=(rec.Respawns or 0)+1 end
        State.Metrics.Respawns=State.Metrics.Respawns+1
    elseif path=="enemies/damaged" and type(params)=="table" then
        local uuid,damage,remaining,crit=params[1],tonumber(params[2]),tonumber(params[3]),params[4]
        local rec=State.World.Enemies[uuid] or mergeEnemy(State.World.CurrentZone,uuid,{})
        if rec then rec.Health=remaining or rec.Health; rec.Alive=true; rec.LastDamage=damage; rec.LastCrit=crit; rec.DamageEvents=(rec.DamageEvents or 0)+1; rec.DamageTaken=(rec.DamageTaken or 0)+(damage or 0) end
        State.Metrics.EnemyDamageEvents=State.Metrics.EnemyDamageEvents+1
    elseif path=="enemies/died" and type(params)=="table" then
        local uuid=params[1]; local rec=State.World.Enemies[uuid] or mergeEnemy(State.World.CurrentZone,uuid,{})
        if rec then rec.Alive=false; rec.Health=0; rec.Deaths=(rec.Deaths or 0)+1 end
        State.Metrics.Kills=State.Metrics.Kills+1
    elseif path=="combat/damageDealt" then State.Metrics.DamageEvents=State.Metrics.DamageEvents+1
    elseif path=="abilities/executed" and type(params)=="table" then
        State.Metrics.AbilityExecuted=State.Metrics.AbilityExecuted+1
        local detail=params[1]
        table.insert(State.Ability.Executions,safeValue(detail)); trim(State.Ability.Executions,100)
    elseif path=="abilities/cooldown" and type(params)=="table" then
        local hero,ability,sec=params[1],params[2],tonumber(params[3]); State.Ability.Cooldowns[tostring(hero).."/"..tostring(ability)]={Hero=hero,Ability=ability,Seconds=sec,SeenClock=now(),ReadyClock=sec and now()+sec or nil}
    elseif path=="abilities/lock" and type(params)=="table" then
        local sec=tonumber(params[2]); State.Ability.Locks[tostring(params[1])] = {Seconds=sec,SeenClock=now(),ReadyClock=sec and now()+sec or nil}
    elseif path=="abilities/swapLock" and type(params)=="table" then State.Ability.SwapLockUntil=now()+(tonumber(params[1]) or 0)
    elseif path=="gacha/results" and type(params)=="table" then
        State.Metrics.GachaBatches=State.Metrics.GachaBatches+1
        table.insert(State.Gacha.Results,{Clock=now(),Category=params[1],Results=safeValue(params[2])}); trim(State.Gacha.Results,100)
    elseif path=="drops/show" and type(params)=="table" then
        State.Metrics.Drops=State.Metrics.Drops+1
        local group=params[1]; if type(group)=="table" then for _,drop in pairs(group) do addDrop(drop) end end
    elseif path=="rewards/display" then State.Metrics.Rewards=State.Metrics.Rewards+1
    elseif path=="gamemodes/started" and type(params)=="table" then State.Dungeon.Active=true; State.Dungeon.Zone=params[1]
    elseif path=="gamemodes/joined" and type(params)=="table" then State.Dungeon.Active=true; State.Dungeon.Zone=params[1]; State.World.CurrentZone=params[1]
    elseif path=="gamemodes/replicateData" and type(params)=="table" then
        local zone,detail=params[1],params[2]
        if type(zone)=="string" and string.find(zone,"Dungeon",1,true) then State.Dungeon.Active=true; State.Dungeon.Zone=zone end
        if type(detail)=="table" then
            if detail.Room~=nil then State.Dungeon.Room=detail.Room end
            if detail.EnemiesAlive~=nil then State.Dungeon.EnemiesAlive=detail.EnemiesAlive end
            if detail.Phase~=nil then State.Dungeon.Phase=detail.Phase end
            if detail.Duration~=nil then State.Dungeon.Duration=detail.Duration end
            if detail.StartTimestamp~=nil then State.Dungeon.StartTimestamp=detail.StartTimestamp end
        end
    end
    refreshCurrentTarget()
end

local function startIncoming()
    if not EventsRemote or not EventsRemote:IsA("RemoteEvent") then return false,"Events.RemoteEvent missing" end
    local ok,conn=pcall(function()
        return EventsRemote.OnClientEvent:Connect(function(payload)
            if not State.Enabled or not Config.CaptureIncoming then return end
            State.Incoming.Packets=State.Incoming.Packets+1
            for _,item in ipairs(eventItems(payload)) do local x,e=pcall(processIncoming,item); if not x then addError("incoming",e) end end
        end)
    end)
    if not ok then return false,conn end
    Connections.Incoming=conn; State.Incoming.Observer=true; return true
end

local function captureOutgoing(source, args)
    if not State.Enabled or not Config.CaptureOutgoing then return end
    State.Outgoing.Calls=State.Outgoing.Calls+1
    local argc=#args
    inc(State.Outgoing.Argc,tostring(argc))
    local decoded=0
    for i=1,argc do
        local items=eventItems(args[i])
        for _,item in ipairs(items) do
            decoded=decoded+1; State.Outgoing.Items=State.Outgoing.Items+1
            local path=type(item.Path)=="string" and item.Path or "<unknown>"; inc(State.Outgoing.Paths,path)
            pushTimeline("OUT",path,safeValue(item.Params),{Hook=source,ArgIndex=i,Argc=argc})
        end
    end
    if decoded==0 then
        local safeArgs={}; for i=1,argc do safeArgs[tostring(i)]=safeValue(args[i]) end
        local meta={Hook=source,Argc=argc}
        if type(getcallingscript)=="function" then local ok,s=pcall(getcallingscript); if ok and s then meta.CallingScript=fullName(s) end end
        pushTimeline("OUT","<undecoded>",safeArgs,meta)
    end
end

local function installOutgoing()
    if not EventsRemote then return false,"remote missing" end
    State.Outgoing.Available = type(hookfunction)=="function" or (type(hookmetamethod)=="function" and type(getnamecallmethod)=="function")

    if type(hookfunction)=="function" then
        local ok,result=pcall(function()
            local original=EventsRemote.FireServer
            local wrapper=function(self,...)
                if self==EventsRemote then local a={...}; task.defer(function() pcall(captureOutgoing,"hookfunction",a) end) end
                return oldDirectFire(self,...)
            end
            if type(newcclosure)=="function" then local x,w=pcall(newcclosure,wrapper); if x and type(w)=="function" then wrapper=w end end
            oldDirectFire=hookfunction(original,wrapper)
            return oldDirectFire
        end)
        if ok and type(result)=="function" then State.Outgoing.Installed=true; State.Outgoing.HookMode="hookfunction"; return true,"hookfunction" end
    end

    if type(hookmetamethod)=="function" and type(getnamecallmethod)=="function" then
        local ok,result=pcall(function()
            local wrapper=function(self,...)
                if getnamecallmethod()=="FireServer" and self==EventsRemote then local a={...}; task.defer(function() pcall(captureOutgoing,"namecall",a) end) end
                return oldNamecall(self,...)
            end
            if type(newcclosure)=="function" then local x,w=pcall(newcclosure,wrapper); if x and type(w)=="function" then wrapper=w end end
            oldNamecall=hookmetamethod(game,"__namecall",wrapper)
            return oldNamecall
        end)
        if ok and type(result)=="function" then State.Outgoing.Installed=true; State.Outgoing.HookMode="namecall"; return true,"namecall" end
    end
    return false,"no compatible hook"
end

-- HUD
local oldHud=PlayerGui:FindFirstChild("AnimeStarsProfilerV14HUD"); if oldHud then oldHud:Destroy() end
HudGui=Instance.new("ScreenGui"); HudGui.Name="AnimeStarsProfilerV14HUD"; HudGui.ResetOnSpawn=false; HudGui.Parent=PlayerGui
local panel=Instance.new("Frame"); panel.AnchorPoint=Vector2.new(1,0); panel.Position=UDim2.new(1,-14,0,70); panel.Size=UDim2.fromOffset(455,190); panel.BackgroundColor3=Color3.fromRGB(18,18,24); panel.BackgroundTransparency=.08; panel.BorderSizePixel=0; panel.Parent=HudGui
local corner=Instance.new("UICorner"); corner.CornerRadius=UDim.new(0,10); corner.Parent=panel
HudText=Instance.new("TextLabel"); HudText.BackgroundTransparency=1; HudText.Position=UDim2.fromOffset(12,10); HudText.Size=UDim2.new(1,-24,1,-20); HudText.Font=Enum.Font.Code; HudText.TextSize=14; HudText.TextColor3=Color3.new(1,1,1); HudText.TextXAlignment=Enum.TextXAlignment.Left; HudText.TextYAlignment=Enum.TextYAlignment.Top; HudText.Parent=panel

local function enemyCount()
    local a=0; for _,rec in pairs(State.World.Enemies) do if rec.Alive~=false and rec.Zone==State.World.CurrentZone then a=a+1 end end; return a
end

local function refreshHud()
    local m=State.Metrics
    HudText.Text=table.concat({
        "GAME PROFILER V1.4 | "..(State.Enabled and "RECORDING" or "PAUSED"),
        "IN "..State.Incoming.Packets.."/"..State.Incoming.Items.." | OUT "..State.Outgoing.Calls.."/"..State.Outgoing.Items.." ["..State.Outgoing.HookMode.."]",
        "Kills "..m.Kills.." | Hits "..m.EnemyDamageEvents.." | Drops "..m.Drops.." | Gacha "..m.GachaBatches,
        "Power "..tostring(m.RawPower or "?").." | Gain "..tostring(m.PowerGained),
        "Zone "..tostring(State.World.CurrentZone).." | Alive "..enemyCount().." | Room "..tostring(State.Dungeon.Room or "-"),
        "Target "..tostring(State.Current.TargetName or State.Current.TargetUUID or "none").." HP "..tostring(State.Current.TargetHealth or "?").."/"..tostring(State.Current.TargetMaxHealth or "?"),
        "Dist "..(State.Current.TargetDistance and string.format("%.1f",State.Current.TargetDistance) or "?").." | Errors "..#State.Errors,
        "F1 M1 | F2 Skill | F3 Ult | F4 Kill | F8 Export"
    },"\n")
end

local function snapshot()
    refreshCurrentTarget()
    return {Clock=now(),Zone=State.World.CurrentZone,Dungeon=safeValue(State.Dungeon),Current=safeValue(State.Current),Metrics=safeValue(State.Metrics),Ability=safeValue(State.Ability),Gacha={Pity=safeValue(State.Gacha.Pity),Spins=State.Gacha.Spins}}
end

local function labelAction(label)
    if not State.Enabled then return end
    local a={Label=label,Clock=now(),Before=snapshot(),StartIndex=#State.Timeline+1}; table.insert(State.Actions,a); trim(State.Actions,Config.MaxActions)
    task.delay(Config.ContextWindow,function() if State.Enabled==nil then return end; a.EndIndex=#State.Timeline; a.After=snapshot() end)
end

local function exportEnemies()
    local out={}; for uuid,rec in pairs(State.World.Enemies) do out[uuid]=safeValue(rec) end; return out
end

local function exportJSON()
    local data={SchemaVersion=5,Version=State.Version,PlaceId=State.PlaceId,StartedUnix=State.StartedUnix,GeneratedUnix=os.time(),DurationSeconds=now(),Config=Config,
        Incoming=State.Incoming,Outgoing=State.Outgoing,Metrics=State.Metrics,World={CurrentZone=State.World.CurrentZone,Enemies=exportEnemies()},Dungeon=safeValue(State.Dungeon),Ability=safeValue(State.Ability),Gacha=safeValue(State.Gacha),Drops=safeValue(State.Drops),Actions=State.Actions,Timeline=State.Timeline,Errors=State.Errors}
    local ok,json=pcall(function() return HttpService:JSONEncode(data) end); if not ok then addError("JSON",json); return nil end
    if type(makefolder)=="function" then pcall(function() if type(isfolder)~="function" or not isfolder("AnimeStarsProfiler") then makefolder("AnimeStarsProfiler") end end) end
    if type(writefile)=="function" then local path="AnimeStarsProfiler/session_v14_"..os.time()..".json"; local x,e=pcall(writefile,path,json); if x then log("Saved "..path) else addError("writefile",e) end end
    if type(setclipboard)=="function" then pcall(setclipboard,json) end
    return json
end

local okIn,errIn=startIncoming(); log("incoming="..tostring(okIn).." "..tostring(errIn or ""))
task.defer(function() local ok,a,b=pcall(installOutgoing); if not ok then addError("outgoing install",a) else log("outgoing="..tostring(a).." "..tostring(b)) end end)

task.spawn(function() while State.Enabled~=nil do local ok,e=pcall(refreshHud); if not ok then addError("HUD",e) end; task.wait(Config.HudInterval) end end)

Connections.Input=UserInputService.InputBegan:Connect(function(input,processed)
    if processed then return end
    if input.KeyCode==Enum.KeyCode.F1 then labelAction("M1_ATTACK")
    elseif input.KeyCode==Enum.KeyCode.F2 then labelAction("SKILL")
    elseif input.KeyCode==Enum.KeyCode.F3 then labelAction("ULTIMATE")
    elseif input.KeyCode==Enum.KeyCode.F4 then labelAction("KILL_MONSTER")
    elseif input.KeyCode==Enum.KeyCode.F8 then exportJSON() end
end)

ENV.__ANIME_STARS_PROFILER_V14_STATE=State
ENV.__ANIME_STARS_PROFILER_V14_EXPORT=exportJSON
ENV.__ANIME_STARS_PROFILER_V14_LABEL=labelAction
ENV.__ANIME_STARS_PROFILER_V14_CLEANUP=function()
    State.Enabled=nil
    for k,c in pairs(Connections) do if c then pcall(function() c:Disconnect() end) end Connections[k]=nil end
    if HudGui then pcall(function() HudGui:Destroy() end) end
end

if game.PlaceId~=EXPECTED_PLACE_ID then log("WARNING PlaceId mismatch "..tostring(game.PlaceId)) end
log("READY")
