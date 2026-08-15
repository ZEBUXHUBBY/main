--[[
Anime Stars Game Profiler V1.3 - Minimal Core
PlaceId: 122553263569744

Purpose: prove the recorder core before adding large UI layers.
Passive-first: observes normal gameplay; does not FireServer/InvokeServer itself.
]]

if not game:IsLoaded() then game.Loaded:Wait() end

local EXPECTED_PLACE_ID = 122553263569744
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer
if not LP then error("[Profiler V1.3] LocalPlayer unavailable") end
local PlayerGui = LP:WaitForChild("PlayerGui")

local ENV = _G
if type(getgenv) == "function" then
    local ok, value = pcall(getgenv)
    if ok and type(value) == "table" then ENV = value end
end
if type(ENV.__ANIME_STARS_PROFILER_V13_CLEANUP) == "function" then
    pcall(ENV.__ANIME_STARS_PROFILER_V13_CLEANUP)
end

local Config = {
    Enabled = true,
    CaptureIncoming = true,
    CaptureOutgoing = true,
    ScanMonsters = true,
    ScanInterval = 1.5,
    HudInterval = 0.25,
    MaxTimeline = 4000,
    ContextWindow = 2.5
}

local State = {
    Version = "1.3",
    PlaceId = game.PlaceId,
    StartedUnix = os.time(),
    StartedClock = os.clock(),
    Enabled = true,
    Stage = "BOOT",
    Errors = {},
    Timeline = {},
    Actions = {},
    Monsters = {},
    Zones = {},
    Incoming = {Observer=false, Packets=0, Items=0, Paths={}},
    Outgoing = {Available=false, Installed=false, Calls=0, Items=0, Paths={}},
    Metrics = {Kills=0, Respawns=0, DamageEvents=0, EnemyDamageEvents=0, Drops=0, Rewards=0, AbilityExecuted=0, RawPower=nil, StartPower=nil, PowerGained=0},
    Current = {Zone=nil, TargetUUID=nil, TargetName=nil, TargetDistance=nil}
}

local Connections = {}
local HudGui, HudText

local function now()
    return os.clock() - State.StartedClock
end

local function log(msg)
    warn("[AnimeStars Profiler V1.3] " .. tostring(msg))
end

local function setStage(msg)
    State.Stage = tostring(msg)
    log(State.Stage)
    if HudText and HudText.Parent then
        HudText.Text = "GAME PROFILER V1.3\n" .. State.Stage
    end
end

local function addError(where, err)
    table.insert(State.Errors, {Clock=now(), Where=tostring(where), Error=tostring(err)})
    log("ERROR " .. tostring(where) .. ": " .. tostring(err))
end

-- Stage 1: HUD only.
local old = PlayerGui:FindFirstChild("AnimeStarsProfilerV13HUD")
if old then old:Destroy() end
HudGui = Instance.new("ScreenGui")
HudGui.Name = "AnimeStarsProfilerV13HUD"
HudGui.ResetOnSpawn = false
HudGui.Parent = PlayerGui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(1,0)
panel.Position = UDim2.new(1,-14,0,70)
panel.Size = UDim2.fromOffset(430,180)
panel.BackgroundColor3 = Color3.fromRGB(18,18,24)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = HudGui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0,10)
corner.Parent = panel
HudText = Instance.new("TextLabel")
HudText.BackgroundTransparency = 1
HudText.Position = UDim2.fromOffset(12,10)
HudText.Size = UDim2.new(1,-24,1,-20)
HudText.Font = Enum.Font.Code
HudText.TextSize = 14
HudText.TextColor3 = Color3.new(1,1,1)
HudText.TextXAlignment = Enum.TextXAlignment.Left
HudText.TextYAlignment = Enum.TextYAlignment.Top
HudText.Parent = panel
setStage("[1/6] HUD created")

local function pathCount(tbl, path)
    tbl[path] = (tbl[path] or 0) + 1
end

local function safePayload(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local t = typeof(v)
    if t == "nil" or t == "boolean" or t == "number" or t == "string" then return v end
    if t == "Instance" then return {__type="Instance", Name=v.Name, ClassName=v.ClassName} end
    if t == "Vector3" then return {__type="Vector3", X=v.X, Y=v.Y, Z=v.Z} end
    if t == "CFrame" then local p=v.Position; return {__type="CFrame", X=p.X, Y=p.Y, Z=p.Z} end
    if t == "table" then
        if seen[v] then return "<cycle>" end
        if depth >= 4 then return "<max-depth>" end
        seen[v] = true
        local out, n = {}, 0
        for k, child in pairs(v) do
            n = n + 1
            if n > 50 then out.__truncated = true break end
            out[type(k)=="string" and k or tostring(k)] = safePayload(child, depth+1, seen)
        end
        seen[v] = nil
        return out
    end
    return "<" .. tostring(t) .. ">"
end

local function push(kind, path, payload)
    table.insert(State.Timeline, {Clock=now(), Unix=os.time(), Kind=kind, Path=path, Payload=safePayload(payload)})
    while #State.Timeline > Config.MaxTimeline do table.remove(State.Timeline,1) end
end

local function unpackItems(payload)
    local result = {}
    if type(payload) ~= "table" then return result end
    local found = false
    for _, item in ipairs(payload) do
        found = true
        if type(item) == "table" then table.insert(result,item) end
    end
    if not found and type(payload.Path) == "string" then table.insert(result,payload) end
    return result
end

local function processIncoming(item)
    if type(item) ~= "table" then return end
    local path = type(item.Path)=="string" and item.Path or "<unknown>"
    local params = item.Params
    State.Incoming.Items = State.Incoming.Items + 1
    pathCount(State.Incoming.Paths,path)
    push("IN",path,params)

    if path == "enemies/died" then State.Metrics.Kills = State.Metrics.Kills + 1
    elseif path == "enemies/respawned" then State.Metrics.Respawns = State.Metrics.Respawns + 1
    elseif path == "enemies/damaged" then State.Metrics.EnemyDamageEvents = State.Metrics.EnemyDamageEvents + 1
    elseif path == "combat/damageDealt" then State.Metrics.DamageEvents = State.Metrics.DamageEvents + 1
    elseif path == "drops/show" then State.Metrics.Drops = State.Metrics.Drops + 1
    elseif path == "rewards/display" then State.Metrics.Rewards = State.Metrics.Rewards + 1
    elseif path == "abilities/executed" then State.Metrics.AbilityExecuted = State.Metrics.AbilityExecuted + 1
    elseif path == "sync/update" and type(params)=="table" then
        local key, value = params[1], params[2]
        if key == "Power" and type(value)=="number" then
            State.Metrics.RawPower = value
            if State.Metrics.StartPower == nil then State.Metrics.StartPower = value end
            State.Metrics.PowerGained = value - State.Metrics.StartPower
        end
    end
end

-- Stage 2: explicit path lookup; no vararg resolver.
local Shared = ReplicatedStorage:FindFirstChild("Shared")
local Packages = Shared and Shared:FindFirstChild("Packages")
local Events = Packages and Packages:FindFirstChild("Events")
local EventsRemote = Events and Events:FindFirstChild("RemoteEvent")

local incomingOK, incomingErr = pcall(function()
    if EventsRemote and EventsRemote:IsA("RemoteEvent") then
        Connections.Incoming = EventsRemote.OnClientEvent:Connect(function(payload)
            if not State.Enabled or not Config.CaptureIncoming then return end
            State.Incoming.Packets = State.Incoming.Packets + 1
            for _, item in ipairs(unpackItems(payload)) do
                local ok, err = pcall(processIncoming,item)
                if not ok then addError("incoming item",err) end
            end
        end)
        State.Incoming.Observer = true
        setStage("[2/6] incoming recorder ON")
    else
        setStage("[2/6] RemoteEvent missing; state-only mode")
    end
end)
if not incomingOK then
    addError("incoming setup",incomingErr)
    setStage("[2/6] incoming setup failed; continuing")
end

local function enemyName(model)
    for _, obj in ipairs(model:GetDescendants()) do
        if obj:IsA("TextLabel") and string.lower(obj.Name)=="title" and obj.Text ~= "" then return obj.Text end
    end
    return nil
end

local function scanMonsters()
    if not Config.ScanMonsters then return end
    local zones = workspace:FindFirstChild("Zones")
    if not zones then return end
    local char = LP.Character
    local playerRoot = char and char:FindFirstChild("HumanoidRootPart")
    local nearest, nearestDist

    for _, zone in ipairs(zones:GetChildren()) do
        if zone:IsA("Folder") then
            local chars = zone:FindFirstChild("Characters")
            local spawners = zone:FindFirstChild("Spawners")
            State.Zones[zone.Name] = State.Zones[zone.Name] or {Name=zone.Name, MonsterUUIDs={}}
            if chars and spawners then
                for _, model in ipairs(chars:GetChildren()) do
                    if model:IsA("Model") then
                        local spawner = spawners:FindFirstChild(model.Name)
                        local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
                        if spawner and spawner:IsA("BasePart") and root and root:IsA("BasePart") then
                            local hum = model:FindFirstChildOfClass("Humanoid")
                            local rec = State.Monsters[model.Name] or {UUID=model.Name, FirstSeen=now(), Seen=0}
                            rec.Seen = rec.Seen + 1
                            rec.Zone = zone.Name
                            rec.Name = enemyName(model) or rec.Name
                            rec.Health = hum and hum.Health or nil
                            rec.MaxHealth = hum and hum.MaxHealth or nil
                            rec.Position = {X=root.Position.X,Y=root.Position.Y,Z=root.Position.Z}
                            rec.SpawnerPosition = {X=spawner.Position.X,Y=spawner.Position.Y,Z=spawner.Position.Z}
                            State.Monsters[model.Name] = rec
                            State.Zones[zone.Name].MonsterUUIDs[model.Name] = true
                            if playerRoot then
                                local d = (root.Position-playerRoot.Position).Magnitude
                                if nearestDist==nil or d<nearestDist then nearest={UUID=model.Name,Zone=zone.Name,Name=rec.Name}; nearestDist=d end
                            end
                        end
                    end
                end
            end
        end
    end

    if nearest then
        State.Current.Zone=nearest.Zone; State.Current.TargetUUID=nearest.UUID; State.Current.TargetName=nearest.Name; State.Current.TargetDistance=nearestDist
    else
        State.Current.TargetUUID=nil; State.Current.TargetName=nil; State.Current.TargetDistance=nil
    end
end

local scanOK, scanErr = pcall(scanMonsters)
if not scanOK then addError("initial scan",scanErr) end
setStage("[3/6] world scan complete")

local function processOutgoing(args, origin)
    if not State.Enabled or not Config.CaptureOutgoing then return end
    State.Outgoing.Calls = State.Outgoing.Calls + 1
    local payload = args and args[1] or nil
    local items = unpackItems(payload)
    if #items == 0 then push("OUT","<unknown>",payload); return end
    for _, item in ipairs(items) do
        local path = type(item.Path)=="string" and item.Path or "<unknown>"
        State.Outgoing.Items = State.Outgoing.Items + 1
        pathCount(State.Outgoing.Paths,path)
        push("OUT",path,item.Params)
    end
end

local function installHook()
    if type(hookmetamethod)~="function" or type(getnamecallmethod)~="function" then return false,"hook APIs unavailable" end
    State.Outgoing.Available = true
    ENV.__ANIME_STARS_PROFILER_V13_CAPTURE = processOutgoing
    ENV.__ANIME_STARS_PROFILER_V13_REMOTE = EventsRemote
    if ENV.__ANIME_STARS_PROFILER_V13_HOOK_INSTALLED then State.Outgoing.Installed=true return true,"reused" end
    local oldNamecall
    local function hook(self,...)
        if getnamecallmethod()=="FireServer" and self==ENV.__ANIME_STARS_PROFILER_V13_REMOTE then
            local args={...}
            local origin=nil
            if type(checkcaller)=="function" then local ok,v=pcall(checkcaller); if ok then origin=v end end
            local cb=ENV.__ANIME_STARS_PROFILER_V13_CAPTURE
            if type(cb)=="function" then task.defer(function() pcall(cb,args,origin) end) end
        end
        return oldNamecall(self,...)
    end
    if type(newcclosure)=="function" then local ok,v=pcall(newcclosure,hook); if ok and type(v)=="function" then hook=v end end
    local ok,v=pcall(function() oldNamecall=hookmetamethod(game,"__namecall",hook); return oldNamecall end)
    if not ok or type(v)~="function" then return false,v end
    ENV.__ANIME_STARS_PROFILER_V13_HOOK_INSTALLED=true
    State.Outgoing.Installed=true
    return true,"installed"
end

task.spawn(function()
    local ok,a,b=pcall(installHook)
    if not ok then addError("outgoing hook",a); log("[4/6] outgoing hook error")
    elseif a then log("[4/6] outgoing hook ON "..tostring(b))
    else log("[4/6] outgoing hook OFF "..tostring(b)) end
end)

local function countTable(t)
    local n=0 for _ in pairs(t) do n=n+1 end return n
end

local function refreshHud()
    if not HudText or not HudText.Parent then return end
    local m=State.Metrics
    HudText.Text=table.concat({
        "GAME PROFILER V1.3 | "..(State.Enabled and "RECORDING" or "PAUSED"),
        "IN "..State.Incoming.Packets.."/"..State.Incoming.Items.." | OUT "..State.Outgoing.Calls.."/"..State.Outgoing.Items,
        "Kills "..m.Kills.." | Dmg "..m.DamageEvents.." | EnemyHit "..m.EnemyDamageEvents,
        "Drops "..m.Drops.." | Power "..tostring(m.RawPower or "?").." | Gain "..tostring(m.PowerGained),
        "Monsters "..countTable(State.Monsters).." | Zone "..tostring(State.Current.Zone or "?"),
        "Target "..tostring(State.Current.TargetName or State.Current.TargetUUID or "none").." | Dist "..(State.Current.TargetDistance and string.format("%.1f",State.Current.TargetDistance) or "?"),
        "Incoming "..(State.Incoming.Observer and "YES" or "NO").." | OutHook "..(State.Outgoing.Installed and "YES" or "NO").." | Errors "..#State.Errors,
        "F1 M1 | F2 Skill | F3 Ult | F4 Kill | F8 Export"
    },"\n")
end

local function snapshot()
    return {Clock=now(), Current=safePayload(State.Current), Metrics=safePayload(State.Metrics), TimelineIndex=#State.Timeline}
end

local function labelAction(label)
    if not State.Enabled then return end
    local a={Label=label,Clock=now(),Before=snapshot(),StartIndex=#State.Timeline+1}
    table.insert(State.Actions,a)
    task.delay(Config.ContextWindow,function()
        if State.Enabled==nil then return end
        a.EndIndex=#State.Timeline
        a.After=snapshot()
    end)
    log("Label: "..label)
end

local function exportJSON()
    pcall(scanMonsters)
    local data={SchemaVersion=4,Version=State.Version,PlaceId=State.PlaceId,StartedUnix=State.StartedUnix,GeneratedUnix=os.time(),DurationSeconds=now(),Config=Config,Incoming=State.Incoming,Outgoing=State.Outgoing,Metrics=State.Metrics,Current=State.Current,Zones=State.Zones,Monsters=State.Monsters,Actions=State.Actions,Timeline=State.Timeline,Errors=State.Errors}
    local ok,json=pcall(function() return HttpService:JSONEncode(data) end)
    if not ok then addError("JSONEncode",json) return nil end
    if type(makefolder)=="function" then pcall(function() if type(isfolder)~="function" or not isfolder("AnimeStarsProfiler") then makefolder("AnimeStarsProfiler") end end) end
    if type(writefile)=="function" then
        local path="AnimeStarsProfiler/session_v13_"..tostring(os.time())..".json"
        local wok,werr=pcall(writefile,path,json)
        if wok then log("Saved "..path) else addError("writefile",werr) end
    end
    if type(setclipboard)=="function" then pcall(setclipboard,json) end
    return json
end

Connections.Input = UserInputService.InputBegan:Connect(function(input,processed)
    if processed then return end
    if input.KeyCode==Enum.KeyCode.F1 then labelAction("M1_ATTACK")
    elseif input.KeyCode==Enum.KeyCode.F2 then labelAction("SKILL")
    elseif input.KeyCode==Enum.KeyCode.F3 then labelAction("ULTIMATE")
    elseif input.KeyCode==Enum.KeyCode.F4 then labelAction("KILL_MONSTER")
    elseif input.KeyCode==Enum.KeyCode.F8 then exportJSON() end
end)

setStage("[5/6] hotkeys ready")

task.spawn(function()
    while State.Enabled~=nil do
        if State.Enabled and Config.ScanMonsters then local ok,err=pcall(scanMonsters); if not ok then addError("periodic scan",err) end end
        task.wait(Config.ScanInterval)
    end
end)
task.spawn(function()
    while State.Enabled~=nil do
        local ok,err=pcall(refreshHud)
        if not ok then log("HUD error: "..tostring(err)) end
        task.wait(Config.HudInterval)
    end
end)

State.Enabled=Config.Enabled
ENV.__ANIME_STARS_PROFILER_V13_STATE=State
ENV.__ANIME_STARS_PROFILER_V13_EXPORT=exportJSON
ENV.__ANIME_STARS_PROFILER_V13_LABEL=labelAction
ENV.__ANIME_STARS_PROFILER_V13_CLEANUP=function()
    State.Enabled=nil
    ENV.__ANIME_STARS_PROFILER_V13_CAPTURE=nil
    for k,c in pairs(Connections) do if c then pcall(function() c:Disconnect() end) end Connections[k]=nil end
    if HudGui then pcall(function() HudGui:Destroy() end) end
end

setStage("[6/6] READY")
if game.PlaceId~=EXPECTED_PLACE_ID then log("WARNING PlaceId mismatch: "..tostring(game.PlaceId)) end