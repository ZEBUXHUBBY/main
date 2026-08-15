--[[
    Anime Stars - Game Profiler V1
    PlaceId: 122553263569744

    Passive-first learning logger for building a data-driven farm/strategy DB.
    Captures normal gameplay without modifying/blocking remote traffic.

    Captures:
    - Shared Events.RemoteEvent outgoing + incoming paths/payload shapes
    - Player Power sync, DamageDealt, cooldown/locks, drops, rewards, pity
    - Live monster UUID <-> spawner mapping, HP, display name, difficulty, distance
    - Action labels with BEFORE/AFTER context windows
    - Auto-classified kill/combat sequences
    - Session JSON export

    Boundaries:
    - Does not call FireServer/InvokeServer itself.
    - Does not call conch_networking/admin/role remotes.
    - Does not modify rewards, cooldowns, or server state.
]]

if not game:IsLoaded() then game.Loaded:Wait() end

local EXPECTED_PLACE_ID = 122553263569744
local PROFILE_VERSION = 1

local function warnp(msg)
    warn("[AnimeStars Profiler V1] " .. tostring(msg))
end

local function safeService(name)
    local ok, svc = pcall(function() return game:GetService(name) end)
    if ok then return svc end
    warnp("Service unavailable: " .. name .. " | " .. tostring(svc))
    return nil
end

local Players = safeService("Players")
local ReplicatedStorage = safeService("ReplicatedStorage")
local HttpService = safeService("HttpService")
local RunService = safeService("RunService")
if not Players or not ReplicatedStorage or not HttpService or not RunService then
    error("[AnimeStars Profiler V1] Required services unavailable")
end

local LP = Players.LocalPlayer
if not LP then error("[AnimeStars Profiler V1] LocalPlayer unavailable") end

local ENV = (type(getgenv) == "function" and getgenv()) or _G
if type(ENV.__ANIME_STARS_PROFILER_CLEANUP) == "function" then
    pcall(ENV.__ANIME_STARS_PROFILER_CLEANUP)
end

local function resolve(root, ...)
    local node = root
    for i = 1, select("#", ...) do
        node = node and node:FindFirstChild(select(i, ...))
        if not node then return nil end
    end
    return node
end

local function fullName(inst)
    if typeof(inst) ~= "Instance" then return nil end
    local ok, v = pcall(function() return inst:GetFullName() end)
    return ok and v or inst.Name
end

local EventsRemote = resolve(ReplicatedStorage, "Shared", "Packages", "Events", "RemoteEvent")

local Config = {
    Enabled = true,
    CaptureIncoming = true,
    CaptureOutgoing = true,
    AutoClassify = true,
    ScanMonsters = true,
    ContextWindow = 2.5,
    MonsterScanInterval = 2.0,
    HudRefresh = 0.25,
    MaxTimeline = 5000,
    MaxActions = 500,
    MaxMonsters = 1000,
    MaxPayloadDepth = 4,
    MaxTableItems = 40,
}

local State = {
    SchemaVersion = 1,
    ProfileVersion = PROFILE_VERSION,
    Tool = "Anime Stars Game Profiler V1",
    PlaceId = game.PlaceId,
    ExpectedPlaceId = EXPECTED_PLACE_ID,
    StartedUnix = os.time(),
    StartedClock = os.clock(),
    Enabled = true,
    OutgoingHookAvailable = false,
    OutgoingHookInstalled = false,
    IncomingObserver = false,
    Seq = 0,
    Timeline = {},
    Actions = {},
    Monsters = {},
    Zones = {},
    KillSequences = {},
    Metrics = {
        IncomingPackets = 0,
        IncomingItems = 0,
        OutgoingCalls = 0,
        OutgoingItems = 0,
        DamageEvents = 0,
        EnemyDamageEvents = 0,
        Kills = 0,
        Respawns = 0,
        AbilityExecuted = 0,
        Drops = 0,
        Rewards = 0,
        SummonResults = 0,
        RawPower = nil,
        StartPower = nil,
        PowerGained = 0,
        ServerDamageTotal = nil,
        LastCombatClock = nil,
        LastProgressClock = nil,
    },
    Ability = { Cooldowns = {}, Locks = {}, SwapLockUntil = 0, LastExecuted = nil },
    Banner = { Pity = nil },
    Current = { Zone = nil, TargetUUID = nil, TargetName = nil, TargetDistance = nil, LastEnemyUUID = nil },
    Notes = {},
}

local Connections = {}
local Window
local HudGui
local HudText
local WindUI

local function clock()
    return os.clock() - State.StartedClock
end

local function trimArray(arr, max)
    while #arr > max do table.remove(arr, 1) end
end

local function safeValue(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local tv = typeof(v)
    if tv == "nil" or tv == "boolean" or tv == "number" or tv == "string" then
        return v
    elseif tv == "Instance" then
        return { __type = "Instance", ClassName = v.ClassName, Name = v.Name, FullName = fullName(v) }
    elseif tv == "Vector3" then
        return { __type = "Vector3", X = v.X, Y = v.Y, Z = v.Z }
    elseif tv == "Vector2" then
        return { __type = "Vector2", X = v.X, Y = v.Y }
    elseif tv == "CFrame" then
        return { __type = "CFrame", Components = { v:GetComponents() } }
    elseif tv == "Color3" then
        return { __type = "Color3", R = v.R, G = v.G, B = v.B }
    elseif tv == "EnumItem" then
        return tostring(v)
    elseif tv == "table" then
        if seen[v] then return "<cycle>" end
        if depth >= Config.MaxPayloadDepth then return "<max-depth>" end
        seen[v] = true
        local out, count = {}, 0
        for k, value in pairs(v) do
            count += 1
            if count > Config.MaxTableItems then out.__truncated = true break end
            local key = type(k) == "string" and k or tostring(k)
            out[key] = safeValue(value, depth + 1, seen)
        end
        seen[v] = nil
        return out
    end
    return "<" .. tv .. ">"
end

local function pushTimeline(kind, path, payload, meta)
    State.Seq += 1
    local row = { Seq = State.Seq, Clock = clock(), Unix = os.time(), Kind = kind, Path = path, Payload = payload, Meta = meta }
    table.insert(State.Timeline, row)
    trimArray(State.Timeline, Config.MaxTimeline)
    return row
end

local function unpackEventItems(payload)
    if type(payload) ~= "table" then return {} end
    local items, arrayFound = {}, false
    for _, item in ipairs(payload) do
        arrayFound = true
        if type(item) == "table" then items[#items + 1] = item end
    end
    if not arrayFound and type(payload.Path) == "string" then items[1] = payload end
    return items
end

local function getCharacterContext()
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local p = root and root.Position
    return {
        Present = char ~= nil,
        Health = hum and hum.Health or nil,
        MaxHealth = hum and hum.MaxHealth or nil,
        WalkSpeed = hum and hum.WalkSpeed or nil,
        Position = p and { X = p.X, Y = p.Y, Z = p.Z } or nil,
    }
end

local function displayedPower()
    local ls = LP:FindFirstChild("leaderstats")
    local obj = ls and ls:FindFirstChild("Power")
    if obj and obj:IsA("ValueBase") then return obj.Value end
    return nil
end

local function findText(model, wanted)
    for _, obj in ipairs(model:GetDescendants()) do
        if obj:IsA("TextLabel") then
            local n = string.lower(obj.Name)
            if wanted[n] and obj.Text and obj.Text ~= "" then return obj.Text end
        end
    end
    return nil
end

local function enemyDisplay(model)
    return findText(model, { title = true }), findText(model, { difficulty = true, difficult = true }), findText(model, { label = true })
end

local function enemyInfo(model, zone)
    if not model or not model:IsA("Model") or not zone or not zone:IsA("Folder") then return nil end
    local spawners = zone:FindFirstChild("Spawners")
    local chars = zone:FindFirstChild("Characters")
    if not spawners or not chars or model.Parent ~= chars then return nil end
    local spawner = spawners:FindFirstChild(model.Name)
    if not spawner or not spawner:IsA("BasePart") then return nil end
    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if not root or not root:IsA("BasePart") then return nil end
    local hum = model:FindFirstChildOfClass("Humanoid")
    local displayName, difficulty, healthText = enemyDisplay(model)
    return { UUID = model.Name, Zone = zone.Name, Model = model, Root = root, Spawner = spawner, Humanoid = hum, DisplayName = displayName, Difficulty = difficulty, HealthText = healthText }
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
            State.Zones[zone.Name] = State.Zones[zone.Name] or { Name = zone.Name, FirstSeenClock = clock(), MonsterUUIDs = {} }
            if chars and spawners then
                for _, model in ipairs(chars:GetChildren()) do
                    local info = enemyInfo(model, zone)
                    if info then
                        local rec = State.Monsters[info.UUID] or {
                            UUID = info.UUID, Zone = info.Zone, FirstSeenClock = clock(), Seen = 0,
                            DeathsObserved = 0, RespawnsObserved = 0, DamageObserved = 0, DamageEvents = 0,
                        }
                        rec.Seen += 1
                        rec.LastSeenClock = clock()
                        rec.Zone = info.Zone
                        rec.DisplayName = info.DisplayName or rec.DisplayName
                        rec.Difficulty = info.Difficulty or rec.Difficulty
                        rec.HealthText = info.HealthText or rec.HealthText
                        rec.Health = info.Humanoid and info.Humanoid.Health or nil
                        rec.MaxHealth = info.Humanoid and info.Humanoid.MaxHealth or nil
                        rec.Position = { X = info.Root.Position.X, Y = info.Root.Position.Y, Z = info.Root.Position.Z }
                        rec.SpawnerPosition = { X = info.Spawner.Position.X, Y = info.Spawner.Position.Y, Z = info.Spawner.Position.Z }
                        State.Monsters[info.UUID] = rec
                        State.Zones[zone.Name].MonsterUUIDs[info.UUID] = true
                        if playerRoot then
                            local d = (info.Root.Position - playerRoot.Position).Magnitude
                            if not nearestDist or d < nearestDist then nearest, nearestDist = info, d end
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
        State.Current.TargetDistance = nearestDist
    else
        State.Current.TargetUUID = nil
        State.Current.TargetName = nil
        State.Current.TargetDistance = nil
    end
end

local function snapshotContext()
    return {
        Clock = clock(),
        Player = {
            Name = LP.Name, UserId = LP.UserId, DisplayedPower = displayedPower(), RawPower = State.Metrics.RawPower,
            ClientActive = LP:GetAttribute("ClientActive"), Dashing = LP:GetAttribute("dashing"), Sprinting = LP:GetAttribute("sprinting"),
        },
        Character = getCharacterContext(),
        Current = safeValue(State.Current),
        Metrics = { Kills = State.Metrics.Kills, DamageEvents = State.Metrics.DamageEvents, PowerGained = State.Metrics.PowerGained, Drops = State.Metrics.Drops, Rewards = State.Metrics.Rewards },
        Ability = safeValue(State.Ability),
        Banner = safeValue(State.Banner),
        TimelineSeq = State.Seq,
    }
end

local function labelAction(label, extra)
    if not State.Enabled then return end
    scanMonsters()
    local action = {
        Id = #State.Actions + 1, Label = label, Extra = extra, Clock = clock(), Unix = os.time(),
        Before = snapshotContext(), StartSeq = State.Seq + 1, EndSeq = nil, After = nil,
    }
    table.insert(State.Actions, action)
    trimArray(State.Actions, Config.MaxActions)
    task.delay(Config.ContextWindow, function()
        scanMonsters()
        action.EndSeq = State.Seq
        action.After = snapshotContext()
    end)
end

local function updatePower(params)
    if type(params) ~= "table" then return end
    local key, value = params[1], params[2]
    if key == "Power" and type(value) == "number" then
        State.Metrics.RawPower = value
        if State.Metrics.StartPower == nil then State.Metrics.StartPower = value end
        State.Metrics.PowerGained = value - State.Metrics.StartPower
        State.Metrics.LastProgressClock = clock()
    elseif key == "Stats.DamageDealt" and type(value) == "number" then
        State.Metrics.ServerDamageTotal = value
    end
end

local function noteMonsterEvent(uuid, field, amount)
    if type(uuid) ~= "string" then return end
    local rec = State.Monsters[uuid]
    if not rec then return end
    rec[field] = (rec[field] or 0) + (amount or 1)
end

local function autoKillSequence(path, params)
    if not Config.AutoClassify then return end
    if path == "enemies/damaged" then
        local uuid = type(params) == "table" and params[1] or nil
        local damage = type(params) == "table" and tonumber(params[2]) or nil
        State.Current.LastEnemyUUID = uuid or State.Current.LastEnemyUUID
        noteMonsterEvent(uuid, "DamageEvents", 1)
        if damage then noteMonsterEvent(uuid, "DamageObserved", damage) end
    elseif path == "enemies/died" then
        local uuid = type(params) == "table" and params[1] or State.Current.LastEnemyUUID
        noteMonsterEvent(uuid, "DeathsObserved", 1)
        table.insert(State.KillSequences, { Clock = clock(), UUID = uuid, Zone = State.Current.Zone, TargetName = State.Current.TargetName, Power = State.Metrics.RawPower, TimelineSeq = State.Seq })
        trimArray(State.KillSequences, 500)
    elseif path == "enemies/respawned" then
        local uuid = type(params) == "table" and params[1] or nil
        noteMonsterEvent(uuid, "RespawnsObserved", 1)
    end
end

local function processIncomingItem(item)
    if type(item) ~= "table" then return end
    local path = type(item.Path) == "string" and item.Path or "<unknown>"
    local params = item.Params
    State.Metrics.IncomingItems += 1
    pushTimeline("IN", path, safeValue(params))

    if path == "sync/update" then updatePower(params)
    elseif path == "combat/damageDealt" then State.Metrics.DamageEvents += 1; State.Metrics.LastCombatClock = clock(); State.Metrics.LastProgressClock = clock()
    elseif path == "enemies/damaged" then State.Metrics.EnemyDamageEvents += 1; State.Metrics.LastCombatClock = clock()
    elseif path == "enemies/died" then State.Metrics.Kills += 1; State.Metrics.LastProgressClock = clock()
    elseif path == "enemies/respawned" then State.Metrics.Respawns += 1
    elseif path == "abilities/executed" then State.Metrics.AbilityExecuted += 1; State.Ability.LastExecuted = safeValue(params)
    elseif path == "abilities/cooldown" and type(params) == "table" then
        local hero, ability, seconds = params[1], params[2], tonumber(params[3])
        local key = tostring(hero) .. "/" .. tostring(ability)
        State.Ability.Cooldowns[key] = { Hero = hero, Ability = ability, Seconds = seconds, SeenClock = clock(), ReadyClock = seconds and (clock() + seconds) or nil }
    elseif path == "abilities/lock" and type(params) == "table" then
        local s = tonumber(params[2])
        State.Ability.Locks[tostring(params[1])] = { Seconds = s, SeenClock = clock(), ReadyClock = s and (clock() + s) or nil }
    elseif path == "abilities/swapLock" and type(params) == "table" then State.Ability.SwapLockUntil = clock() + (tonumber(params[1]) or 0)
    elseif path == "drops/show" then State.Metrics.Drops += 1
    elseif path == "rewards/display" then State.Metrics.Rewards += 1
    elseif path == "banner/rollResults" then State.Metrics.SummonResults += 1
    elseif path == "banner/updatePity" then State.Banner.Pity = safeValue(params)
    end
    autoKillSequence(path, params)
end

local function startIncoming()
    if not EventsRemote or not EventsRemote:IsA("RemoteEvent") then warnp("Events.RemoteEvent missing; incoming capture unavailable") return end
    Connections.Incoming = EventsRemote.OnClientEvent:Connect(function(payload)
        if not State.Enabled or not Config.CaptureIncoming then return end
        State.Metrics.IncomingPackets += 1
        for _, item in ipairs(unpackEventItems(payload)) do processIncomingItem(item) end
    end)
    State.IncomingObserver = true
end

local function processOutgoingArgs(args, executorOrigin)
    if not State.Enabled or not Config.CaptureOutgoing then return end
    State.Metrics.OutgoingCalls += 1
    local payload = args and args[1]
    local items = unpackEventItems(payload)
    if #items == 0 then pushTimeline("OUT", "<unknown>", safeValue(payload), { ExecutorOrigin = executorOrigin }) return end
    for _, item in ipairs(items) do
        State.Metrics.OutgoingItems += 1
        pushTimeline("OUT", type(item.Path) == "string" and item.Path or "<unknown>", safeValue(item.Params), { ExecutorOrigin = executorOrigin })
    end
end

local function installOutgoingHook()
    local hasHook = type(hookmetamethod) == "function" and type(getnamecallmethod) == "function"
    State.OutgoingHookAvailable = hasHook
    if not hasHook then warnp("Outgoing hook APIs unavailable; incoming/state capture still active") return false end

    if ENV.__ANIME_STARS_PROFILER_HOOK_INSTALLED then
        State.OutgoingHookInstalled = true
        ENV.__ANIME_STARS_PROFILER_CAPTURE = processOutgoingArgs
        ENV.__ANIME_STARS_PROFILER_REMOTE = EventsRemote
        return true
    end

    local old
    local closure = function(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer" and self == ENV.__ANIME_STARS_PROFILER_REMOTE then
            local args = table.pack(...)
            local origin = type(checkcaller) == "function" and checkcaller() or nil
            local cb = ENV.__ANIME_STARS_PROFILER_CAPTURE
            if type(cb) == "function" then task.defer(function() pcall(cb, args, origin) end) end
        end
        return old(self, ...)
    end
    if type(newcclosure) == "function" then closure = newcclosure(closure) end
    local hookOk, hookResult = pcall(function() old = hookmetamethod(game, "__namecall", closure); return old end)
    if not hookOk or type(hookResult) ~= "function" then warnp("Outgoing hook install failed: " .. tostring(hookResult)); return false end

    ENV.__ANIME_STARS_PROFILER_HOOK_INSTALLED = true
    ENV.__ANIME_STARS_PROFILER_CAPTURE = processOutgoingArgs
    ENV.__ANIME_STARS_PROFILER_REMOTE = EventsRemote
    State.OutgoingHookInstalled = true
    return true
end

local function exportTable()
    scanMonsters()
    return {
        SchemaVersion = State.SchemaVersion, ProfileVersion = State.ProfileVersion, Tool = State.Tool,
        PlaceId = State.PlaceId, ExpectedPlaceId = State.ExpectedPlaceId, StartedUnix = State.StartedUnix,
        GeneratedUnix = os.time(), DurationSeconds = clock(), Config = Config,
        Capabilities = {
            IncomingObserver = State.IncomingObserver, OutgoingHookAvailable = State.OutgoingHookAvailable,
            OutgoingHookInstalled = State.OutgoingHookInstalled, WriteFile = type(writefile) == "function", Clipboard = type(setclipboard) == "function",
        },
        Metrics = State.Metrics, Ability = State.Ability, Banner = State.Banner, Current = State.Current,
        Zones = State.Zones, Monsters = State.Monsters, Actions = State.Actions, KillSequences = State.KillSequences,
        Timeline = State.Timeline, Notes = State.Notes,
    }
end

local function exportJSON()
    local ok, json = pcall(function() return HttpService:JSONEncode(exportTable()) end)
    if not ok then warnp("JSON encode failed: " .. tostring(json)) return nil end
    if type(makefolder) == "function" and type(isfolder) == "function" then pcall(function() if not isfolder("AnimeStarsProfiler") then makefolder("AnimeStarsProfiler") end end) end
    if type(writefile) == "function" then
        local file = "AnimeStarsProfiler/session_" .. tostring(os.time()) .. ".json"
        local wok, werr = pcall(writefile, file, json)
        if wok then warnp("Saved " .. file) else warnp("Save failed: " .. tostring(werr)) end
    end
    if type(setclipboard) == "function" then pcall(setclipboard, json) end
    return json
end

local function createHud()
    local pg = LP:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("AnimeStarsProfilerHUD")
    if old then old:Destroy() end
    HudGui = Instance.new("ScreenGui"); HudGui.Name = "AnimeStarsProfilerHUD"; HudGui.ResetOnSpawn = false; HudGui.Parent = pg
    local frame = Instance.new("Frame"); frame.AnchorPoint = Vector2.new(1,0); frame.Position = UDim2.new(1,-12,0,70); frame.Size = UDim2.fromOffset(390,154); frame.BackgroundColor3 = Color3.fromRGB(18,18,22); frame.BackgroundTransparency = 0.12; frame.BorderSizePixel = 0; frame.Parent = HudGui
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,10); corner.Parent = frame
    HudText = Instance.new("TextLabel"); HudText.BackgroundTransparency = 1; HudText.Position = UDim2.fromOffset(12,8); HudText.Size = UDim2.new(1,-24,1,-16); HudText.Font = Enum.Font.Code; HudText.TextSize = 14; HudText.TextColor3 = Color3.new(1,1,1); HudText.TextXAlignment = Enum.TextXAlignment.Left; HudText.TextYAlignment = Enum.TextYAlignment.Top; HudText.Parent = frame
end

local function countMonsters()
    local n = 0
    for _ in pairs(State.Monsters) do n += 1 end
    return n
end

local function refreshHud()
    if not HudText then return end
    local m = State.Metrics
    HudText.Text = string.format(
        "GAME PROFILER V1 | %s\nIN %d/%d | OUT %d/%d\nKills %d | DmgEvt %d | Drops %d | Rolls %d\nPower %s | Gain %.2f | Monsters %d\nZone %s | Target %s | Dist %s\nOutgoingHook: %s",
        State.Enabled and "RECORDING" or "PAUSED", m.IncomingPackets, m.IncomingItems, m.OutgoingCalls, m.OutgoingItems,
        m.Kills, m.DamageEvents, m.Drops, m.SummonResults, tostring(m.RawPower or displayedPower() or "?"), tonumber(m.PowerGained) or 0,
        countMonsters(), tostring(State.Current.Zone or "?"), tostring(State.Current.TargetName or State.Current.TargetUUID or "none"),
        State.Current.TargetDistance and string.format("%.1f", State.Current.TargetDistance) or "?", State.OutgoingHookInstalled and "YES" or "NO"
    )
end

local function fallbackUI()
    local pg = LP:WaitForChild("PlayerGui")
    local gui = Instance.new("ScreenGui"); gui.Name = "AnimeStarsProfilerFallback"; gui.ResetOnSpawn = false; gui.Parent = pg
    local frame = Instance.new("Frame"); frame.Position = UDim2.fromOffset(20,240); frame.Size = UDim2.fromOffset(230,300); frame.BackgroundColor3 = Color3.fromRGB(22,22,28); frame.Parent = gui
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,10); corner.Parent = frame
    local list = Instance.new("UIListLayout"); list.Padding = UDim.new(0,6); list.Parent = frame
    local pad = Instance.new("UIPadding"); pad.PaddingTop = UDim.new(0,8); pad.PaddingLeft = UDim.new(0,8); pad.PaddingRight = UDim.new(0,8); pad.Parent = frame
    local function button(text, cb)
        local b = Instance.new("TextButton"); b.Size = UDim2.new(1,0,0,32); b.Text = text; b.BackgroundColor3 = Color3.fromRGB(42,42,52); b.TextColor3 = Color3.new(1,1,1); b.Parent = frame; b.MouseButton1Click:Connect(cb); return b
    end
    local recBtn
    recBtn = button("Recording: ON", function() State.Enabled = not State.Enabled; recBtn.Text = "Recording: " .. (State.Enabled and "ON" or "OFF") end)
    button("Label M1", function() labelAction("M1_ATTACK") end)
    button("Label Skill", function() labelAction("SKILL") end)
    button("Label Ultimate", function() labelAction("ULTIMATE") end)
    button("Label Kill", function() labelAction("KILL_MONSTER") end)
    button("Label Zone TP", function() labelAction("TELEPORT_ZONE") end)
    button("Label Upgrade", function() labelAction("BUY_UPGRADE") end)
    button("Label Quest", function() labelAction("QUEST") end)
    button("Label Summon", function() labelAction("SUMMON") end)
    button("Export JSON", exportJSON)
    Connections.FallbackGui = { Disconnect = function() if gui then gui:Destroy() end end }
end

local function buildWindUI()
    local ok, result = pcall(function()
        local src = game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua")
        return loadstring(src)()
    end)
    if not ok then warnp("WindUI load failed; fallback UI | " .. tostring(result)); fallbackUI(); return end
    WindUI = result
    Window = WindUI:CreateWindow({
        Title = "Anime Stars | Game Profiler V1", Folder = "AnimeStarsProfiler", Icon = "database", NewElements = true, HideSearchBar = false,
        OpenButton = { Title = "Profiler", Enabled = true, Draggable = true, OnlyMobile = false },
    })
    local Learn = Window:Tab({ Title = "Learning", Icon = "brain", Border = true })
    Learn:Toggle({ Title = "Record Session", Desc = "Passive capture of normal gameplay", Value = true, Callback = function(v) State.Enabled = v == true end })
    Learn:Toggle({ Title = "Capture Outgoing", Desc = "Read-only hook of normal Events.RemoteEvent FireServer calls", Value = Config.CaptureOutgoing, Callback = function(v) Config.CaptureOutgoing = v == true end })
    Learn:Toggle({ Title = "Capture Incoming", Value = Config.CaptureIncoming, Callback = function(v) Config.CaptureIncoming = v == true end })
    Learn:Toggle({ Title = "Auto Classify Kill Sequences", Value = Config.AutoClassify, Callback = function(v) Config.AutoClassify = v == true end })

    local Labels = Window:Tab({ Title = "Labels", Icon = "tag", Border = true })
    local labels = {
        {"M1 Attack", "M1_ATTACK"}, {"Skill", "SKILL"}, {"Ultimate", "ULTIMATE"}, {"Kill Monster", "KILL_MONSTER"},
        {"Teleport Zone", "TELEPORT_ZONE"}, {"Buy Upgrade", "BUY_UPGRADE"}, {"Quest", "QUEST"}, {"Summon", "SUMMON"},
    }
    for _, pair in ipairs(labels) do Labels:Button({ Title = pair[1], Callback = function() labelAction(pair[2]) end }) end
    local custom = "CUSTOM"
    Labels:Input({ Title = "Custom Label", Placeholder = "example: equip weapon", Value = "", Callback = function(v) custom = tostring(v or "CUSTOM") end })
    Labels:Button({ Title = "Mark Custom Action", Callback = function() labelAction("CUSTOM", custom) end })

    local Data = Window:Tab({ Title = "Data", Icon = "database", Border = true })
    Data:Button({ Title = "Scan Monsters Now", Callback = function() scanMonsters(); warnp("Monster scan complete") end })
    Data:Button({ Title = "Export / Copy JSON", Callback = exportJSON })

    local Info = Window:Tab({ Title = "Info", Icon = "info", Border = true })
    Info:Paragraph({ Title = "How to train the profiler", Desc = "Play normally. Before an important action, press its label once, then do the action. V1 stores BEFORE/AFTER context and all observed event traffic inside the time window." })
    Info:Paragraph({ Title = "Best learning pass", Desc = "Do M1, Skill, Ultimate, kill 2-3 different monsters, teleport zone, buy one upgrade, accept/finish a quest, and summon once. Then export the JSON and send it back." })
end

local function bindMonsterSignals()
    local zones = workspace:FindFirstChild("Zones")
    if not zones then return end
    local function bindZone(zone)
        if not zone:IsA("Folder") then return end
        local chars = zone:FindFirstChild("Characters")
        if not chars then return end
        local k1, k2 = "add_"..zone.Name, "rem_"..zone.Name
        if Connections[k1] then Connections[k1]:Disconnect() end
        if Connections[k2] then Connections[k2]:Disconnect() end
        Connections[k1] = chars.ChildAdded:Connect(function(model)
            task.defer(function()
                local info = enemyInfo(model, zone)
                if info then pushTimeline("WORLD", "monster/added", { UUID=info.UUID, Zone=info.Zone, Name=info.DisplayName }); scanMonsters() end
            end)
        end)
        Connections[k2] = chars.ChildRemoved:Connect(function(model) pushTimeline("WORLD", "monster/removed", { UUID=model.Name, Zone=zone.Name }) end)
    end
    for _, z in ipairs(zones:GetChildren()) do bindZone(z) end
    Connections.ZoneAdded = zones.ChildAdded:Connect(function(z) task.defer(function() bindZone(z) end) end)
end

local function startLoops()
    task.spawn(function()
        while State.Enabled ~= nil do
            if State.Enabled and Config.ScanMonsters then scanMonsters() end
            task.wait(Config.MonsterScanInterval)
        end
    end)
    task.spawn(function()
        while State.Enabled ~= nil do refreshHud(); task.wait(Config.HudRefresh) end
    end)
end

createHud()
scanMonsters()
startIncoming()
installOutgoingHook()
bindMonsterSignals()
buildWindUI()
startLoops()

if game.PlaceId ~= EXPECTED_PLACE_ID then warnp("Place mismatch: expected " .. tostring(EXPECTED_PLACE_ID) .. " got " .. tostring(game.PlaceId)) end

State.Enabled = Config.Enabled
ENV.__ANIME_STARS_PROFILER_STATE = State
ENV.__ANIME_STARS_PROFILER_CONFIG = Config
ENV.__ANIME_STARS_PROFILER_EXPORT = exportJSON
ENV.__ANIME_STARS_PROFILER_LABEL = labelAction
ENV.__ANIME_STARS_PROFILER_CLEANUP = function()
    State.Enabled = nil
    ENV.__ANIME_STARS_PROFILER_CAPTURE = nil
    for k, c in pairs(Connections) do if c then pcall(function() c:Disconnect() end) end; Connections[k] = nil end
    if HudGui then pcall(function() HudGui:Destroy() end); HudGui = nil end
    if Window then pcall(function() Window:Destroy() end); Window = nil end
end

warnp("Loaded | incoming=" .. tostring(State.IncomingObserver) .. " outgoingHook=" .. tostring(State.OutgoingHookInstalled))