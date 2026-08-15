--[[
Anime Stars Game Profiler V1.2 (core-first)
PlaceId: 122553263569744

Design:
- HUD first
- incoming recorder second
- monster scan third
- optional outgoing hook fourth
- controls/UI last
- every optional system isolated by pcall

Passive-first. Does not call FireServer/InvokeServer itself.
]]

if not game:IsLoaded() then game.Loaded:Wait() end

local EXPECTED_PLACE_ID = 122553263569744
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer
if not LP then error("[Profiler V1.2] LocalPlayer unavailable") end
local PlayerGui = LP:WaitForChild("PlayerGui")

local ENV = _G
if type(getgenv) == "function" then
    local ok, v = pcall(getgenv)
    if ok and type(v) == "table" then ENV = v end
end
if type(ENV.__ANIME_STARS_PROFILER_V12_CLEANUP) == "function" then
    pcall(ENV.__ANIME_STARS_PROFILER_V12_CLEANUP)
end

local Config = {
    Enabled = true,
    CaptureIncoming = true,
    CaptureOutgoing = true,
    ScanMonsters = true,
    ScanInterval = 1.25,
    HudInterval = 0.25,
    ContextWindow = 2.5,
    MaxTimeline = 5000,
    MaxActions = 500,
    MaxPayloadDepth = 4,
    MaxTableItems = 50,
}

local State = {
    Version = "1.2",
    PlaceId = game.PlaceId,
    StartedUnix = os.time(),
    StartedClock = os.clock(),
    Enabled = true,
    Stage = "BOOT",
    Seq = 0,
    Timeline = {},
    Actions = {},
    Monsters = {},
    Zones = {},
    Errors = {},
    Incoming = { Observer = false, Packets = 0, Items = 0, Paths = {} },
    Outgoing = { Available = false, Installed = false, Calls = 0, Items = 0, Paths = {} },
    Metrics = {
        Kills = 0, Respawns = 0, DamageEvents = 0, EnemyDamageEvents = 0,
        AbilityExecuted = 0, Drops = 0, Rewards = 0, SummonResults = 0,
        RawPower = nil, StartPower = nil, PowerGained = 0, ServerDamageTotal = nil,
    },
    Ability = { Cooldowns = {}, Locks = {}, SwapLockUntil = 0, LastExecuted = nil },
    Banner = { Pity = nil },
    Current = { Zone = nil, TargetUUID = nil, TargetName = nil, TargetDistance = nil, LastEnemyUUID = nil },
}

local Connections = {}
local BootGui, BootText, ControlsGui, WindWindow

local function clock()
    return os.clock() - State.StartedClock
end

local function trim(arr, maxCount)
    while #arr > maxCount do table.remove(arr, 1) end
end

local function console(msg)
    warn("[AnimeStars Profiler V1.2] " .. tostring(msg))
end

local function setStage(msg)
    State.Stage = tostring(msg)
    console(State.Stage)
    if BootText and BootText.Parent then
        BootText.Text = "GAME PROFILER V1.2\n" .. State.Stage
    end
end

local function addError(where, err)
    local row = { Clock = clock(), Where = tostring(where), Error = tostring(err) }
    table.insert(State.Errors, row)
    trim(State.Errors, 100)
    console("ERROR " .. row.Where .. ": " .. row.Error)
end

-- Stage 1: HUD, no optional dependencies.
local oldHud = PlayerGui:FindFirstChild("AnimeStarsProfilerV12HUD")
if oldHud then oldHud:Destroy() end
BootGui = Instance.new("ScreenGui")
BootGui.Name = "AnimeStarsProfilerV12HUD"
BootGui.ResetOnSpawn = false
BootGui.Parent = PlayerGui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -14, 0, 70)
panel.Size = UDim2.fromOffset(430, 180)
panel.BackgroundColor3 = Color3.fromRGB(18,18,24)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = BootGui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0,10)
corner.Parent = panel
BootText = Instance.new("TextLabel")
BootText.BackgroundTransparency = 1
BootText.Position = UDim2.fromOffset(12,10)
BootText.Size = UDim2.new(1,-24,1,-20)
BootText.Font = Enum.Font.Code
BootText.TextSize = 14
BootText.TextColor3 = Color3.new(1,1,1)
BootText.TextXAlignment = Enum.TextXAlignment.Left
BootText.TextYAlignment = Enum.TextYAlignment.Top
BootText.TextWrapped = false
BootText.Parent = panel
setStage("[1/7] HUD created")

local function resolve(root, ...)
    local node = root
    local n = select("#", ...)
    for i = 1, n do
        if not node then return nil end
        node = node:FindFirstChild(select(i, ...))
    end
    return node
end

local function fullName(inst)
    if typeof(inst) ~= "Instance" then return nil end
    local ok, v = pcall(function() return inst:GetFullName() end)
    return ok and v or inst.Name
end

local function safeValue(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local t = typeof(v)
    if t == "nil" or t == "boolean" or t == "number" or t == "string" then return v end
    if t == "Instance" then return {__type="Instance",Name=v.Name,ClassName=v.ClassName,FullName=fullName(v)} end
    if t == "Vector3" then return {__type="Vector3",X=v.X,Y=v.Y,Z=v.Z} end
    if t == "Vector2" then return {__type="Vector2",X=v.X,Y=v.Y} end
    if t == "CFrame" then return {__type="CFrame",X=v.X,Y=v.Y,Z=v.Z} end
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
    State.Seq = State.Seq + 1
    local row = { Seq=State.Seq, Clock=clock(), Unix=os.time(), Kind=kind, Path=path, Payload=payload, Meta=meta }
    table.insert(State.Timeline, row)
    trim(State.Timeline, Config.MaxTimeline)
    return row
end

local function eventItems(payload)
    local out = {}
    if type(payload) ~= "table" then return out end
    local sawArray = false
    for _, item in ipairs(payload) do
        sawArray = true
        if type(item) == "table" then table.insert(out, item) end
    end
    if not sawArray and type(payload.Path) == "string" then table.insert(out, payload) end
    return out
end

local function displayedPower()
    local ls = LP:FindFirstChild("leaderstats")
    local p = ls and ls:FindFirstChild("Power")
    if p and p:IsA("ValueBase") then return p.Value end
    return nil
end

local function characterContext()
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local pos = root and root.Position or nil
    return {
        Present = char ~= nil,
        Health = hum and hum.Health or nil,
        MaxHealth = hum and hum.MaxHealth or nil,
        WalkSpeed = hum and hum.WalkSpeed or nil,
        Position = pos and {X=pos.X,Y=pos.Y,Z=pos.Z} or nil,
    }
end

local function findText(model, names)
    for _, obj in ipairs(model:GetDescendants()) do
        if obj:IsA("TextLabel") then
            local n = string.lower(obj.Name)
            if names[n] and obj.Text ~= "" then return obj.Text end
        end
    end
    return nil
end

local function enemyInfo(model, zone)
    if not model or not model:IsA("Model") or not zone or not zone:IsA("Folder") then return nil end
    local chars = zone:FindFirstChild("Characters")
    local spawners = zone:FindFirstChild("Spawners")
    if not chars or not spawners or model.Parent ~= chars then return nil end
    local spawner = spawners:FindFirstChild(model.Name)
    if not spawner or not spawner:IsA("BasePart") then return nil end
    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if not root or not root:IsA("BasePart") then return nil end
    return {
        UUID=model.Name, Zone=zone.Name, Model=model, Root=root, Spawner=spawner,
        Humanoid=model:FindFirstChildOfClass("Humanoid"),
        DisplayName=findText(model,{title=true}),
        Difficulty=findText(model,{difficulty=true,difficult=true}),
    }
end

local function scanMonsters()
    if not Config.ScanMonsters then return end
    local zones = workspace:FindFirstChild("Zones")
    if not zones then return end
    local char = LP.Character
    local playerRoot = char and char:FindFirstChild("HumanoidRootPart")
    local nearest, nearestDistance = nil, nil

    for _, zone in ipairs(zones:GetChildren()) do
        if zone:IsA("Folder") then
            local zrec = State.Zones[zone.Name]
            if not zrec then
                zrec = {Name=zone.Name,FirstSeenClock=clock(),MonsterUUIDs={}}
                State.Zones[zone.Name] = zrec
            end
            local chars = zone:FindFirstChild("Characters")
            if chars then
                for _, model in ipairs(chars:GetChildren()) do
                    local info = enemyInfo(model, zone)
                    if info then
                        local rec = State.Monsters[info.UUID]
                        if not rec then
                            rec = {UUID=info.UUID,Zone=info.Zone,FirstSeenClock=clock(),Seen=0,DeathsObserved=0,RespawnsObserved=0,DamageObserved=0,DamageEvents=0}
                            State.Monsters[info.UUID] = rec
                        end
                        rec.Seen = rec.Seen + 1
                        rec.LastSeenClock = clock()
                        rec.Zone = info.Zone
                        rec.DisplayName = info.DisplayName or rec.DisplayName
                        rec.Difficulty = info.Difficulty or rec.Difficulty
                        rec.Health = info.Humanoid and info.Humanoid.Health or nil
                        rec.MaxHealth = info.Humanoid and info.Humanoid.MaxHealth or nil
                        rec.Position = {X=info.Root.Position.X,Y=info.Root.Position.Y,Z=info.Root.Position.Z}
                        rec.SpawnerPosition = {X=info.Spawner.Position.X,Y=info.Spawner.Position.Y,Z=info.Spawner.Position.Z}
                        zrec.MonsterUUIDs[info.UUID] = true
                        if playerRoot then
                            local d = (info.Root.Position-playerRoot.Position).Magnitude
                            if nearestDistance == nil or d < nearestDistance then nearest, nearestDistance = info, d end
                        end
                    end
                end
            end
        end
    end

    if nearest then
        State.Current.Zone = nearest.Zone
        State.Current.TargetUUID = nearest.UUID
        State.Current.TargetName = nearest.DisplayName
        State.Current.TargetDistance = nearestDistance
    else
        State.Current.TargetUUID = nil
        State.Current.TargetName = nil
        State.Current.TargetDistance = nil
    end
end

local function snapshot()
    return {
        Clock=clock(),
        Player={Name=LP.Name,UserId=LP.UserId,DisplayedPower=displayedPower(),RawPower=State.Metrics.RawPower},
        Character=characterContext(), Current=safeValue(State.Current), Metrics=safeValue(State.Metrics),
        Ability=safeValue(State.Ability), Banner=safeValue(State.Banner), TimelineSeq=State.Seq,
    }
end

local function labelAction(label, extra)
    if not State.Enabled then return end
    pcall(scanMonsters)
    local a = {Id=#State.Actions+1,Label=label,Extra=extra,Clock=clock(),Unix=os.time(),Before=snapshot(),StartSeq=State.Seq+1}
    table.insert(State.Actions,a)
    trim(State.Actions, Config.MaxActions)
    task.delay(Config.ContextWindow,function()
        if State.Enabled == nil then return end
        pcall(scanMonsters)
        a.EndSeq = State.Seq
        a.After = snapshot()
    end)
end

local function noteMonster(uuid, field, amount)
    if type(uuid) ~= "string" then return end
    local rec = State.Monsters[uuid]
    if not rec then return end
    rec[field] = (rec[field] or 0) + (amount or 1)
end

local function updatePower(params)
    if type(params) ~= "table" then return end
    local key, value = params[1], params[2]
    if key == "Power" and type(value) == "number" then
        State.Metrics.RawPower = value
        if State.Metrics.StartPower == nil then State.Metrics.StartPower = value end
        State.Metrics.PowerGained = value - State.Metrics.StartPower
    elseif key == "Stats.DamageDealt" and type(value) == "number" then
        State.Metrics.ServerDamageTotal = value
    end
end

local function processIncoming(item)
    if type(item) ~= "table" then return end
    local path = type(item.Path)=="string" and item.Path or "<unknown>"
    local params = item.Params
    State.Incoming.Items = State.Incoming.Items + 1
    State.Incoming.Paths[path] = (State.Incoming.Paths[path] or 0) + 1
    pushTimeline("IN",path,safeValue(params))

    if path == "sync/update" then updatePower(params)
    elseif path == "combat/damageDealt" then State.Metrics.DamageEvents = State.Metrics.DamageEvents + 1
    elseif path == "enemies/damaged" then
        State.Metrics.EnemyDamageEvents = State.Metrics.EnemyDamageEvents + 1
        local uuid = type(params)=="table" and params[1] or nil
        local dmg = type(params)=="table" and tonumber(params[2]) or nil
        if uuid then State.Current.LastEnemyUUID = uuid; noteMonster(uuid,"DamageEvents",1); if dmg then noteMonster(uuid,"DamageObserved",dmg) end end
    elseif path == "enemies/died" then
        State.Metrics.Kills = State.Metrics.Kills + 1
        local uuid = type(params)=="table" and params[1] or State.Current.LastEnemyUUID
        noteMonster(uuid,"DeathsObserved",1)
    elseif path == "enemies/respawned" then
        State.Metrics.Respawns = State.Metrics.Respawns + 1
        local uuid = type(params)=="table" and params[1] or nil
        noteMonster(uuid,"RespawnsObserved",1)
    elseif path == "abilities/executed" then State.Metrics.AbilityExecuted=State.Metrics.AbilityExecuted+1; State.Ability.LastExecuted=safeValue(params)
    elseif path == "abilities/cooldown" and type(params)=="table" then
        local hero, ability, sec = params[1],params[2],tonumber(params[3])
        State.Ability.Cooldowns[tostring(hero).."/"..tostring(ability)]={Hero=hero,Ability=ability,Seconds=sec,SeenClock=clock(),ReadyClock=sec and clock()+sec or nil}
    elseif path == "abilities/lock" and type(params)=="table" then
        local sec=tonumber(params[2]); State.Ability.Locks[tostring(params[1])]={Seconds=sec,SeenClock=clock(),ReadyClock=sec and clock()+sec or nil}
    elseif path == "abilities/swapLock" and type(params)=="table" then State.Ability.SwapLockUntil=clock()+(tonumber(params[1]) or 0)
    elseif path == "drops/show" then State.Metrics.Drops=State.Metrics.Drops+1
    elseif path == "rewards/display" then State.Metrics.Rewards=State.Metrics.Rewards+1
    elseif path == "banner/rollResults" then State.Metrics.SummonResults=State.Metrics.SummonResults+1
    elseif path == "banner/updatePity" then State.Banner.Pity=safeValue(params)
    end
end

local EventsRemote = resolve(ReplicatedStorage,"Shared","Packages","Events","RemoteEvent")

-- Stage 2: core incoming capture BEFORE controls/UI.
do
    local ok, err = pcall(function()
        if EventsRemote and EventsRemote:IsA("RemoteEvent") then
            Connections.Incoming = EventsRemote.OnClientEvent:Connect(function(payload)
                if not State.Enabled or not Config.CaptureIncoming then return end
                State.Incoming.Packets = State.Incoming.Packets + 1
                for _, item in ipairs(eventItems(payload)) do
                    local itemOk, itemErr = pcall(processIncoming,item)
                    if not itemOk then addError("incoming item",itemErr) end
                end
            end)
            State.Incoming.Observer = true
            setStage("[2/7] incoming recorder ON")
        else
            setStage("[2/7] event remote missing; state-only mode")
        end
    end)
    if not ok then addError("incoming setup",err); setStage("[2/7] incoming failed; continuing") end
end

-- Stage 3: initial world scan.
do
    local ok, err = pcall(scanMonsters)
    if not ok then addError("initial monster scan",err) end
    setStage("[3/7] world scan complete")
end

local function processOutgoing(args, executorOrigin)
    if not State.Enabled or not Config.CaptureOutgoing then return end
    State.Outgoing.Calls = State.Outgoing.Calls + 1
    local payload = args and args[1] or nil
    local items = eventItems(payload)
    if #items == 0 then pushTimeline("OUT","<unknown>",safeValue(payload),{ExecutorOrigin=executorOrigin}); return end
    for _, item in ipairs(items) do
        local path = type(item.Path)=="string" and item.Path or "<unknown>"
        State.Outgoing.Items = State.Outgoing.Items + 1
        State.Outgoing.Paths[path] = (State.Outgoing.Paths[path] or 0) + 1
        pushTimeline("OUT",path,safeValue(item.Params),{ExecutorOrigin=executorOrigin})
    end
end

local function installOutgoingHook()
    local has = type(hookmetamethod)=="function" and type(getnamecallmethod)=="function"
    State.Outgoing.Available = has
    if not has then return false,"hook APIs unavailable" end
    ENV.__ANIME_STARS_PROFILER_V12_CAPTURE = processOutgoing
    ENV.__ANIME_STARS_PROFILER_V12_REMOTE = EventsRemote
    if ENV.__ANIME_STARS_PROFILER_V12_HOOK_INSTALLED then State.Outgoing.Installed=true; return true,"reused" end

    local oldNamecall
    local function hook(self,...)
        local method = getnamecallmethod()
        if method == "FireServer" and self == ENV.__ANIME_STARS_PROFILER_V12_REMOTE then
            local args={...}
            local origin=nil
            if type(checkcaller)=="function" then local ok,v=pcall(checkcaller); if ok then origin=v end end
            local cb=ENV.__ANIME_STARS_PROFILER_V12_CAPTURE
            if type(cb)=="function" then task.defer(function() pcall(cb,args,origin) end) end
        end
        return oldNamecall(self,...)
    end
    if type(newcclosure)=="function" then local ok,v=pcall(newcclosure,hook); if ok and type(v)=="function" then hook=v end end
    local ok,v=pcall(function() oldNamecall=hookmetamethod(game,"__namecall",hook); return oldNamecall end)
    if not ok or type(v)~="function" then return false,v end
    ENV.__ANIME_STARS_PROFILER_V12_HOOK_INSTALLED=true
    State.Outgoing.Installed=true
    return true,"installed"
end

-- Stage 4 is async; it can never block the profiler.
task.defer(function()
    local ok, a, b = pcall(installOutgoingHook)
    if not ok then addError("outgoing hook",a); setStage("[4/7] outgoing hook error; passive continues")
    elseif a then setStage("[4/7] outgoing hook ON ("..tostring(b)..")")
    else setStage("[4/7] outgoing hook OFF: "..tostring(b)) end
end)

local function countMonsters()
    local n=0; for _ in pairs(State.Monsters) do n=n+1 end; return n
end

local function refreshHud()
    if not BootText or not BootText.Parent then return end
    local m=State.Metrics
    BootText.Text=table.concat({
        "GAME PROFILER V1.2 | "..(State.Enabled and "RECORDING" or "PAUSED"),
        "IN "..State.Incoming.Packets.."/"..State.Incoming.Items.." | OUT "..State.Outgoing.Calls.."/"..State.Outgoing.Items,
        "Kills "..m.Kills.." | Dmg "..m.DamageEvents.." | Drops "..m.Drops.." | Rolls "..m.SummonResults,
        "Power "..tostring(m.RawPower or displayedPower() or "?").." | Gain "..tostring(m.PowerGained),
        "Monsters "..countMonsters().." | Zone "..tostring(State.Current.Zone or "?"),
        "Target "..tostring(State.Current.TargetName or State.Current.TargetUUID or "none").." | Dist "..(State.Current.TargetDistance and string.format("%.1f",State.Current.TargetDistance) or "?"),
        "Incoming "..(State.Incoming.Observer and "YES" or "NO").." | OutHook "..(State.Outgoing.Installed and "YES" or "NO").." | Errors "..#State.Errors,
    },"\n")
end

local function exportJSON()
    pcall(scanMonsters)
    local data={
        SchemaVersion=3,ProfileVersion=State.Version,PlaceId=State.PlaceId,StartedUnix=State.StartedUnix,GeneratedUnix=os.time(),DurationSeconds=clock(),
        Config=Config,Incoming=State.Incoming,Outgoing=State.Outgoing,Metrics=State.Metrics,Ability=State.Ability,Banner=State.Banner,
        Current=State.Current,Zones=State.Zones,Monsters=State.Monsters,Actions=State.Actions,Timeline=State.Timeline,Errors=State.Errors,
    }
    local ok,json=pcall(function() return HttpService:JSONEncode(data) end)
    if not ok then addError("JSON encode",json); return nil end
    if type(makefolder)=="function" then pcall(function() if type(isfolder)~="function" or not isfolder("AnimeStarsProfiler") then makefolder("AnimeStarsProfiler") end end) end
    if type(writefile)=="function" then
        local path="AnimeStarsProfiler/session_v12_"..os.time()..".json"
        local wok,werr=pcall(writefile,path,json)
        if wok then console("Saved "..path) else addError("writefile",werr) end
    end
    if type(setclipboard)=="function" then pcall(setclipboard,json) end
    return json
end

-- Stage 5: background recorder loops.
task.spawn(function()
    while State.Enabled ~= nil do
        if State.Enabled and Config.ScanMonsters then local ok,err=pcall(scanMonsters); if not ok then addError("periodic scan",err) end end
        task.wait(Config.ScanInterval)
    end
end)
task.spawn(function()
    while State.Enabled ~= nil do local ok,err=pcall(refreshHud); if not ok then console("HUD refresh: "..tostring(err)) end; task.wait(Config.HudInterval) end
end)
setStage("[5/7] recorder loops ON")

-- Stage 6: optional simple controls, isolated from core.
task.defer(function()
    local ok,err=pcall(function()
        local old=PlayerGui:FindFirstChild("AnimeStarsProfilerV12Controls"); if old then old:Destroy() end
        ControlsGui=Instance.new("ScreenGui"); ControlsGui.Name="AnimeStarsProfilerV12Controls"; ControlsGui.ResetOnSpawn=false; ControlsGui.Parent=PlayerGui
        local f=Instance.new("Frame"); f.Position=UDim2.fromOffset(18,260); f.Size=UDim2.fromOffset(220,310); f.BackgroundColor3=Color3.fromRGB(22,22,28); f.BorderSizePixel=0; f.Parent=ControlsGui
        local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,10); c.Parent=f
        local l=Instance.new("UIListLayout"); l.Padding=UDim.new(0,4); l.Parent=f
        local p=Instance.new("UIPadding"); p.PaddingTop=UDim.new(0,7); p.PaddingLeft=UDim.new(0,7); p.PaddingRight=UDim.new(0,7); p.Parent=f
        local function btn(text,cb)
            local b=Instance.new("TextButton"); b.Size=UDim2.new(1,0,0,27); b.BackgroundColor3=Color3.fromRGB(44,44,56); b.TextColor3=Color3.new(1,1,1); b.Text=text; b.Parent=f
            b.Activated:Connect(function() local x,e=pcall(cb); if not x then addError("button "..text,e) end end)
            return b
        end
        local rec
        rec=btn("Recording: ON",function() State.Enabled=not State.Enabled; rec.Text="Recording: "..(State.Enabled and "ON" or "OFF") end)
        btn("Label M1",function() labelAction("M1_ATTACK") end)
        btn("Label Skill",function() labelAction("SKILL") end)
        btn("Label Ultimate",function() labelAction("ULTIMATE") end)
        btn("Label Kill",function() labelAction("KILL_MONSTER") end)
        btn("Label Zone TP",function() labelAction("TELEPORT_ZONE") end)
        btn("Label Upgrade",function() labelAction("BUY_UPGRADE") end)
        btn("Label Quest",function() labelAction("QUEST") end)
        btn("Label Summon",function() labelAction("SUMMON") end)
        btn("Export JSON",exportJSON)
    end)
    if ok then setStage("[6/7] controls ready") else addError("controls",err); setStage("[6/7] controls failed; recorder still active") end
end)

-- Hotkeys work even if controls fail.
Connections.Input=UserInputService.InputBegan:Connect(function(input,processed)
    if processed then return end
    if input.KeyCode==Enum.KeyCode.F1 then labelAction("M1_ATTACK")
    elseif input.KeyCode==Enum.KeyCode.F2 then labelAction("SKILL")
    elseif input.KeyCode==Enum.KeyCode.F3 then labelAction("ULTIMATE")
    elseif input.KeyCode==Enum.KeyCode.F4 then labelAction("KILL_MONSTER")
    elseif input.KeyCode==Enum.KeyCode.F8 then exportJSON() end
end)

State.Enabled=Config.Enabled
ENV.__ANIME_STARS_PROFILER_V12_STATE=State
ENV.__ANIME_STARS_PROFILER_V12_EXPORT=exportJSON
ENV.__ANIME_STARS_PROFILER_V12_LABEL=labelAction
ENV.__ANIME_STARS_PROFILER_V12_CLEANUP=function()
    State.Enabled=nil
    ENV.__ANIME_STARS_PROFILER_V12_CAPTURE=nil
    for k,c in pairs(Connections) do if c then pcall(function() c:Disconnect() end) end Connections[k]=nil end
    if ControlsGui then pcall(function() ControlsGui:Destroy() end) end
    if BootGui then pcall(function() BootGui:Destroy() end) end
end

setStage("[7/7] READY")
if game.PlaceId~=EXPECTED_PLACE_ID then console("WARNING PlaceId mismatch: "..tostring(game.PlaceId)) end
