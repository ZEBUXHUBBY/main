--[[
    Anime Stars - Game Profiler V1.1
    PlaceId: 122553263569744

    Compatibility-first learning logger.
    The bootstrap HUD is created BEFORE WindUI, hooks, scans, or optional systems.

    Passive capture only:
    - Incoming Events.RemoteEvent traffic
    - Optional read-only outgoing FireServer observation when hook APIs exist
    - Power / damage / ability / drop / pity events
    - Monster UUID <-> spawner mapping
    - Manual action labels with before/after context
    - JSON export
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local EXPECTED_PLACE_ID = 122553263569744
local PROFILE_VERSION = "1.1"

local function console(msg)
    warn("[AnimeStars Profiler V1.1] " .. tostring(msg))
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer
if not LP then
    error("[AnimeStars Profiler V1.1] LocalPlayer unavailable")
end

local ENV = _G
if type(getgenv) == "function" then
    local ok, result = pcall(getgenv)
    if ok and type(result) == "table" then
        ENV = result
    end
end

if type(ENV.__ANIME_STARS_PROFILER_CLEANUP) == "function" then
    pcall(ENV.__ANIME_STARS_PROFILER_CLEANUP)
end

local PlayerGui = LP:WaitForChild("PlayerGui")

-- ============================================================
-- BOOTSTRAP HUD: created before any optional feature.
-- ============================================================
local oldBoot = PlayerGui:FindFirstChild("AnimeStarsProfilerBootstrap")
if oldBoot then
    oldBoot:Destroy()
end

local BootGui = Instance.new("ScreenGui")
BootGui.Name = "AnimeStarsProfilerBootstrap"
BootGui.ResetOnSpawn = false
BootGui.IgnoreGuiInset = false
BootGui.Parent = PlayerGui

local BootFrame = Instance.new("Frame")
BootFrame.Name = "Panel"
BootFrame.AnchorPoint = Vector2.new(1, 0)
BootFrame.Position = UDim2.new(1, -14, 0, 70)
BootFrame.Size = UDim2.fromOffset(420, 190)
BootFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
BootFrame.BackgroundTransparency = 0.08
BootFrame.BorderSizePixel = 0
BootFrame.Parent = BootGui

local BootCorner = Instance.new("UICorner")
BootCorner.CornerRadius = UDim.new(0, 10)
BootCorner.Parent = BootFrame

local BootText = Instance.new("TextLabel")
BootText.BackgroundTransparency = 1
BootText.Position = UDim2.fromOffset(12, 10)
BootText.Size = UDim2.new(1, -24, 1, -20)
BootText.Font = Enum.Font.Code
BootText.TextSize = 14
BootText.TextColor3 = Color3.new(1, 1, 1)
BootText.TextXAlignment = Enum.TextXAlignment.Left
BootText.TextYAlignment = Enum.TextYAlignment.Top
BootText.TextWrapped = false
BootText.Text = "GAME PROFILER V1.1\nBOOTING..."
BootText.Parent = BootFrame

local BootLines = {}
local function stage(msg)
    console(msg)
    table.insert(BootLines, tostring(msg))
    while #BootLines > 8 do
        table.remove(BootLines, 1)
    end
    if BootText and BootText.Parent then
        BootText.Text = "GAME PROFILER V1.1\n" .. table.concat(BootLines, "\n")
    end
end

stage("[1/7] bootstrap HUD created")

local Config = {
    Enabled = true,
    CaptureIncoming = true,
    CaptureOutgoing = true,
    ScanMonsters = true,
    AutoClassify = true,
    ContextWindow = 2.5,
    MonsterScanInterval = 1.5,
    HudRefresh = 0.25,
    MaxTimeline = 4000,
    MaxActions = 300,
    MaxMonsters = 1000,
    MaxPayloadDepth = 4,
    MaxTableItems = 40
}

local State = {
    SchemaVersion = 2,
    ProfileVersion = PROFILE_VERSION,
    Tool = "Anime Stars Game Profiler V1.1",
    PlaceId = game.PlaceId,
    ExpectedPlaceId = EXPECTED_PLACE_ID,
    StartedUnix = os.time(),
    StartedClock = os.clock(),
    Enabled = true,
    Status = "BOOTING",
    IncomingObserver = false,
    OutgoingHookAvailable = false,
    OutgoingHookInstalled = false,
    Seq = 0,
    Timeline = {},
    Actions = {},
    Monsters = {},
    Zones = {},
    KillSequences = {},
    Ability = {
        Cooldowns = {},
        Locks = {},
        SwapLockUntil = 0,
        LastExecuted = nil
    },
    Banner = {
        Pity = nil
    },
    Current = {
        Zone = nil,
        TargetUUID = nil,
        TargetName = nil,
        TargetDistance = nil,
        LastEnemyUUID = nil
    },
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
        LastProgressClock = nil
    },
    Errors = {}
}

local Connections = {}
local WindUI = nil
local Window = nil
local FallbackGui = nil

local function nowClock()
    return os.clock() - State.StartedClock
end

local function addError(where, err)
    local row = {
        Clock = nowClock(),
        Where = tostring(where),
        Error = tostring(err)
    }
    table.insert(State.Errors, row)
    while #State.Errors > 100 do
        table.remove(State.Errors, 1)
    end
    stage("ERROR " .. tostring(where) .. ": " .. tostring(err))
end

local function trimArray(arr, maxCount)
    while #arr > maxCount do
        table.remove(arr, 1)
    end
end

local function resolve(root, ...)
    local node = root
    local count = select("#", ...)
    local i = 1
    while i <= count do
        if not node then
            return nil
        end
        node = node:FindFirstChild(select(i, ...))
        i = i + 1
    end
    return node
end

local function fullName(inst)
    if typeof(inst) ~= "Instance" then
        return nil
    end
    local ok, result = pcall(function()
        return inst:GetFullName()
    end)
    if ok then
        return result
    end
    return inst.Name
end

local function safeValue(value, depth, seen)
    depth = depth or 0
    seen = seen or {}

    local valueType = typeof(value)
    if valueType == "nil" or valueType == "boolean" or valueType == "number" or valueType == "string" then
        return value
    end

    if valueType == "Instance" then
        return {
            __type = "Instance",
            ClassName = value.ClassName,
            Name = value.Name,
            FullName = fullName(value)
        }
    end

    if valueType == "Vector3" then
        return { __type = "Vector3", X = value.X, Y = value.Y, Z = value.Z }
    end

    if valueType == "Vector2" then
        return { __type = "Vector2", X = value.X, Y = value.Y }
    end

    if valueType == "CFrame" then
        return { __type = "CFrame", Position = safeValue(value.Position) }
    end

    if valueType == "Color3" then
        return { __type = "Color3", R = value.R, G = value.G, B = value.B }
    end

    if valueType == "EnumItem" then
        return tostring(value)
    end

    if valueType == "table" then
        if seen[value] then
            return "<cycle>"
        end
        if depth >= Config.MaxPayloadDepth then
            return "<max-depth>"
        end

        seen[value] = true
        local out = {}
        local count = 0
        for key, child in pairs(value) do
            count = count + 1
            if count > Config.MaxTableItems then
                out.__truncated = true
                break
            end
            local safeKey
            if type(key) == "string" then
                safeKey = key
            else
                safeKey = tostring(key)
            end
            out[safeKey] = safeValue(child, depth + 1, seen)
        end
        seen[value] = nil
        return out
    end

    return "<" .. tostring(valueType) .. ">"
end

local function pushTimeline(kind, path, payload, meta)
    State.Seq = State.Seq + 1
    local row = {
        Seq = State.Seq,
        Clock = nowClock(),
        Unix = os.time(),
        Kind = kind,
        Path = path,
        Payload = payload,
        Meta = meta
    }
    table.insert(State.Timeline, row)
    trimArray(State.Timeline, Config.MaxTimeline)
    return row
end

local function unpackEventItems(payload)
    local items = {}
    if type(payload) ~= "table" then
        return items
    end

    local arrayFound = false
    for _, item in ipairs(payload) do
        arrayFound = true
        if type(item) == "table" then
            table.insert(items, item)
        end
    end

    if not arrayFound and type(payload.Path) == "string" then
        table.insert(items, payload)
    end

    return items
end

local function displayedPower()
    local leaderstats = LP:FindFirstChild("leaderstats")
    local power = leaderstats and leaderstats:FindFirstChild("Power")
    if power and power:IsA("ValueBase") then
        return power.Value
    end
    return nil
end

local function characterContext()
    local character = LP.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local position = root and root.Position or nil

    return {
        Present = character ~= nil,
        Health = humanoid and humanoid.Health or nil,
        MaxHealth = humanoid and humanoid.MaxHealth or nil,
        WalkSpeed = humanoid and humanoid.WalkSpeed or nil,
        Position = position and { X = position.X, Y = position.Y, Z = position.Z } or nil
    }
end

local function textFromModel(model, acceptedNames)
    local descendants = model:GetDescendants()
    for _, obj in ipairs(descendants) do
        if obj:IsA("TextLabel") then
            local lowerName = string.lower(obj.Name)
            if acceptedNames[lowerName] and obj.Text and obj.Text ~= "" then
                return obj.Text
            end
        end
    end
    return nil
end

local function enemyInfo(model, zone)
    if not model or not model:IsA("Model") then
        return nil
    end
    if not zone or not zone:IsA("Folder") then
        return nil
    end

    local characters = zone:FindFirstChild("Characters")
    local spawners = zone:FindFirstChild("Spawners")
    if not characters or not spawners then
        return nil
    end
    if model.Parent ~= characters then
        return nil
    end

    local spawner = spawners:FindFirstChild(model.Name)
    if not spawner or not spawner:IsA("BasePart") then
        return nil
    end

    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if not root or not root:IsA("BasePart") then
        return nil
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local displayName = textFromModel(model, { title = true })
    local difficulty = textFromModel(model, { difficulty = true, difficult = true })

    return {
        UUID = model.Name,
        Zone = zone.Name,
        Model = model,
        Root = root,
        Spawner = spawner,
        Humanoid = humanoid,
        DisplayName = displayName,
        Difficulty = difficulty
    }
end

local function scanMonsters()
    if not Config.ScanMonsters then
        return
    end

    local zones = workspace:FindFirstChild("Zones")
    if not zones then
        return
    end

    local character = LP.Character
    local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
    local nearest = nil
    local nearestDistance = nil

    for _, zone in ipairs(zones:GetChildren()) do
        if zone:IsA("Folder") then
            local zoneRecord = State.Zones[zone.Name]
            if not zoneRecord then
                zoneRecord = {
                    Name = zone.Name,
                    FirstSeenClock = nowClock(),
                    MonsterUUIDs = {}
                }
                State.Zones[zone.Name] = zoneRecord
            end

            local characters = zone:FindFirstChild("Characters")
            if characters then
                for _, model in ipairs(characters:GetChildren()) do
                    local info = enemyInfo(model, zone)
                    if info then
                        local rec = State.Monsters[info.UUID]
                        if not rec then
                            rec = {
                                UUID = info.UUID,
                                Zone = info.Zone,
                                FirstSeenClock = nowClock(),
                                Seen = 0,
                                DeathsObserved = 0,
                                RespawnsObserved = 0,
                                DamageObserved = 0,
                                DamageEvents = 0
                            }
                            State.Monsters[info.UUID] = rec
                        end

                        rec.Seen = rec.Seen + 1
                        rec.LastSeenClock = nowClock()
                        rec.Zone = info.Zone
                        rec.DisplayName = info.DisplayName or rec.DisplayName
                        rec.Difficulty = info.Difficulty or rec.Difficulty
                        rec.Health = info.Humanoid and info.Humanoid.Health or nil
                        rec.MaxHealth = info.Humanoid and info.Humanoid.MaxHealth or nil
                        rec.Position = {
                            X = info.Root.Position.X,
                            Y = info.Root.Position.Y,
                            Z = info.Root.Position.Z
                        }
                        rec.SpawnerPosition = {
                            X = info.Spawner.Position.X,
                            Y = info.Spawner.Position.Y,
                            Z = info.Spawner.Position.Z
                        }

                        zoneRecord.MonsterUUIDs[info.UUID] = true

                        if playerRoot then
                            local distance = (info.Root.Position - playerRoot.Position).Magnitude
                            if nearestDistance == nil or distance < nearestDistance then
                                nearest = info
                                nearestDistance = distance
                            end
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

local function snapshotContext()
    return {
        Clock = nowClock(),
        Player = {
            Name = LP.Name,
            UserId = LP.UserId,
            DisplayedPower = displayedPower(),
            RawPower = State.Metrics.RawPower,
            ClientActive = LP:GetAttribute("ClientActive"),
            Dashing = LP:GetAttribute("dashing"),
            Sprinting = LP:GetAttribute("sprinting")
        },
        Character = characterContext(),
        Current = safeValue(State.Current),
        Metrics = safeValue(State.Metrics),
        Ability = safeValue(State.Ability),
        Banner = safeValue(State.Banner),
        TimelineSeq = State.Seq
    }
end

local function labelAction(label, extra)
    if not State.Enabled then
        return
    end

    pcall(scanMonsters)
    local action = {
        Id = #State.Actions + 1,
        Label = label,
        Extra = extra,
        Clock = nowClock(),
        Unix = os.time(),
        Before = snapshotContext(),
        StartSeq = State.Seq + 1,
        EndSeq = nil,
        After = nil
    }

    table.insert(State.Actions, action)
    trimArray(State.Actions, Config.MaxActions)

    task.delay(Config.ContextWindow, function()
        if State.Enabled == nil then
            return
        end
        pcall(scanMonsters)
        action.EndSeq = State.Seq
        action.After = snapshotContext()
    end)
end

local function noteMonster(uuid, field, amount)
    if type(uuid) ~= "string" then
        return
    end
    local rec = State.Monsters[uuid]
    if not rec then
        return
    end
    rec[field] = (rec[field] or 0) + (amount or 1)
end

local function updatePower(params)
    if type(params) ~= "table" then
        return
    end

    local key = params[1]
    local value = params[2]

    if key == "Power" and type(value) == "number" then
        State.Metrics.RawPower = value
        if State.Metrics.StartPower == nil then
            State.Metrics.StartPower = value
        end
        State.Metrics.PowerGained = value - State.Metrics.StartPower
        State.Metrics.LastProgressClock = nowClock()
    elseif key == "Stats.DamageDealt" and type(value) == "number" then
        State.Metrics.ServerDamageTotal = value
    end
end

local function classifyEnemyEvent(path, params)
    if not Config.AutoClassify then
        return
    end

    if path == "enemies/damaged" then
        local uuid = type(params) == "table" and params[1] or nil
        local damage = type(params) == "table" and tonumber(params[2]) or nil
        if uuid then
            State.Current.LastEnemyUUID = uuid
            noteMonster(uuid, "DamageEvents", 1)
            if damage then
                noteMonster(uuid, "DamageObserved", damage)
            end
        end
    elseif path == "enemies/died" then
        local uuid = type(params) == "table" and params[1] or State.Current.LastEnemyUUID
        noteMonster(uuid, "DeathsObserved", 1)
        table.insert(State.KillSequences, {
            Clock = nowClock(),
            UUID = uuid,
            Zone = State.Current.Zone,
            TargetName = State.Current.TargetName,
            Power = State.Metrics.RawPower,
            TimelineSeq = State.Seq
        })
        trimArray(State.KillSequences, 500)
    elseif path == "enemies/respawned" then
        local uuid = type(params) == "table" and params[1] or nil
        noteMonster(uuid, "RespawnsObserved", 1)
    end
end

local function processIncomingItem(item)
    if type(item) ~= "table" then
        return
    end

    local path = type(item.Path) == "string" and item.Path or "<unknown>"
    local params = item.Params

    State.Metrics.IncomingItems = State.Metrics.IncomingItems + 1
    pushTimeline("IN", path, safeValue(params))

    if path == "sync/update" then
        updatePower(params)
    elseif path == "combat/damageDealt" then
        State.Metrics.DamageEvents = State.Metrics.DamageEvents + 1
        State.Metrics.LastCombatClock = nowClock()
        State.Metrics.LastProgressClock = nowClock()
    elseif path == "enemies/damaged" then
        State.Metrics.EnemyDamageEvents = State.Metrics.EnemyDamageEvents + 1
        State.Metrics.LastCombatClock = nowClock()
    elseif path == "enemies/died" then
        State.Metrics.Kills = State.Metrics.Kills + 1
        State.Metrics.LastProgressClock = nowClock()
    elseif path == "enemies/respawned" then
        State.Metrics.Respawns = State.Metrics.Respawns + 1
    elseif path == "abilities/executed" then
        State.Metrics.AbilityExecuted = State.Metrics.AbilityExecuted + 1
        State.Ability.LastExecuted = safeValue(params)
    elseif path == "abilities/cooldown" and type(params) == "table" then
        local hero = params[1]
        local ability = params[2]
        local seconds = tonumber(params[3])
        local key = tostring(hero) .. "/" .. tostring(ability)
        State.Ability.Cooldowns[key] = {
            Hero = hero,
            Ability = ability,
            Seconds = seconds,
            SeenClock = nowClock(),
            ReadyClock = seconds and (nowClock() + seconds) or nil
        }
    elseif path == "abilities/lock" and type(params) == "table" then
        local seconds = tonumber(params[2])
        State.Ability.Locks[tostring(params[1])] = {
            Seconds = seconds,
            SeenClock = nowClock(),
            ReadyClock = seconds and (nowClock() + seconds) or nil
        }
    elseif path == "abilities/swapLock" and type(params) == "table" then
        State.Ability.SwapLockUntil = nowClock() + (tonumber(params[1]) or 0)
    elseif path == "drops/show" then
        State.Metrics.Drops = State.Metrics.Drops + 1
    elseif path == "rewards/display" then
        State.Metrics.Rewards = State.Metrics.Rewards + 1
    elseif path == "banner/rollResults" then
        State.Metrics.SummonResults = State.Metrics.SummonResults + 1
    elseif path == "banner/updatePity" then
        State.Banner.Pity = safeValue(params)
    end

    classifyEnemyEvent(path, params)
end

local EventsRemote = resolve(ReplicatedStorage, "Shared", "Packages", "Events", "RemoteEvent")

local function startIncoming()
    if not EventsRemote or not EventsRemote:IsA("RemoteEvent") then
        stage("[3/7] Events.RemoteEvent missing")
        return false
    end

    local ok, connectionOrError = pcall(function()
        return EventsRemote.OnClientEvent:Connect(function(payload)
            if not State.Enabled or not Config.CaptureIncoming then
                return
            end
            State.Metrics.IncomingPackets = State.Metrics.IncomingPackets + 1
            local items = unpackEventItems(payload)
            for _, item in ipairs(items) do
                processIncomingItem(item)
            end
        end)
    end)

    if not ok then
        addError("startIncoming", connectionOrError)
        return false
    end

    Connections.Incoming = connectionOrError
    State.IncomingObserver = true
    stage("[3/7] incoming observer ON")
    return true
end

local function processOutgoingArgs(args, executorOrigin)
    if not State.Enabled or not Config.CaptureOutgoing then
        return
    end

    State.Metrics.OutgoingCalls = State.Metrics.OutgoingCalls + 1
    local payload = args and args[1] or nil
    local items = unpackEventItems(payload)

    if #items == 0 then
        pushTimeline("OUT", "<unknown>", safeValue(payload), {
            ExecutorOrigin = executorOrigin
        })
        return
    end

    for _, item in ipairs(items) do
        State.Metrics.OutgoingItems = State.Metrics.OutgoingItems + 1
        pushTimeline(
            "OUT",
            type(item.Path) == "string" and item.Path or "<unknown>",
            safeValue(item.Params),
            { ExecutorOrigin = executorOrigin }
        )
    end
end

local function installOutgoingHook()
    local hasHook = type(hookmetamethod) == "function" and type(getnamecallmethod) == "function"
    State.OutgoingHookAvailable = hasHook

    if not hasHook then
        stage("[4/7] outgoing hook unavailable (OK)")
        return false
    end

    ENV.__ANIME_STARS_PROFILER_CAPTURE = processOutgoingArgs
    ENV.__ANIME_STARS_PROFILER_REMOTE = EventsRemote

    if ENV.__ANIME_STARS_PROFILER_HOOK_INSTALLED then
        State.OutgoingHookInstalled = true
        stage("[4/7] outgoing hook reused")
        return true
    end

    local oldNamecall = nil
    local hookFunction

    hookFunction = function(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer" and self == ENV.__ANIME_STARS_PROFILER_REMOTE then
            local args = { ... }
            local executorOrigin = nil
            if type(checkcaller) == "function" then
                local ok, result = pcall(checkcaller)
                if ok then
                    executorOrigin = result
                end
            end

            local callback = ENV.__ANIME_STARS_PROFILER_CAPTURE
            if type(callback) == "function" then
                task.defer(function()
                    pcall(callback, args, executorOrigin)
                end)
            end
        end

        return oldNamecall(self, ...)
    end

    if type(newcclosure) == "function" then
        local ok, result = pcall(newcclosure, hookFunction)
        if ok and type(result) == "function" then
            hookFunction = result
        end
    end

    local ok, result = pcall(function()
        oldNamecall = hookmetamethod(game, "__namecall", hookFunction)
        return oldNamecall
    end)

    if not ok or type(result) ~= "function" then
        addError("installOutgoingHook", result)
        stage("[4/7] outgoing hook failed; passive mode continues")
        return false
    end

    ENV.__ANIME_STARS_PROFILER_HOOK_INSTALLED = true
    State.OutgoingHookInstalled = true
    stage("[4/7] outgoing hook ON")
    return true
end

local function exportTable()
    pcall(scanMonsters)
    return {
        SchemaVersion = State.SchemaVersion,
        ProfileVersion = State.ProfileVersion,
        Tool = State.Tool,
        PlaceId = State.PlaceId,
        ExpectedPlaceId = State.ExpectedPlaceId,
        StartedUnix = State.StartedUnix,
        GeneratedUnix = os.time(),
        DurationSeconds = nowClock(),
        Config = Config,
        Capabilities = {
            IncomingObserver = State.IncomingObserver,
            OutgoingHookAvailable = State.OutgoingHookAvailable,
            OutgoingHookInstalled = State.OutgoingHookInstalled,
            WriteFile = type(writefile) == "function",
            Clipboard = type(setclipboard) == "function"
        },
        Metrics = State.Metrics,
        Ability = State.Ability,
        Banner = State.Banner,
        Current = State.Current,
        Zones = State.Zones,
        Monsters = State.Monsters,
        Actions = State.Actions,
        KillSequences = State.KillSequences,
        Timeline = State.Timeline,
        Errors = State.Errors
    }
end

local function exportJSON()
    local ok, jsonOrError = pcall(function()
        return HttpService:JSONEncode(exportTable())
    end)

    if not ok then
        addError("JSONEncode", jsonOrError)
        return nil
    end

    local json = jsonOrError

    if type(makefolder) == "function" then
        pcall(function()
            if type(isfolder) ~= "function" or not isfolder("AnimeStarsProfiler") then
                makefolder("AnimeStarsProfiler")
            end
        end)
    end

    if type(writefile) == "function" then
        local path = "AnimeStarsProfiler/session_" .. tostring(os.time()) .. ".json"
        local writeOk, writeErr = pcall(writefile, path, json)
        if writeOk then
            stage("saved: " .. path)
        else
            addError("writefile", writeErr)
        end
    end

    if type(setclipboard) == "function" then
        pcall(setclipboard, json)
    end

    return json
end

local function countMonsters()
    local count = 0
    for _ in pairs(State.Monsters) do
        count = count + 1
    end
    return count
end

local function refreshHud()
    if not BootText or not BootText.Parent then
        return
    end

    local metrics = State.Metrics
    local lines = {
        "GAME PROFILER V1.1 | " .. (State.Enabled and "RECORDING" or "PAUSED"),
        "IN " .. tostring(metrics.IncomingPackets) .. "/" .. tostring(metrics.IncomingItems) ..
            " | OUT " .. tostring(metrics.OutgoingCalls) .. "/" .. tostring(metrics.OutgoingItems),
        "Kills " .. tostring(metrics.Kills) ..
            " | DmgEvt " .. tostring(metrics.DamageEvents) ..
            " | Drops " .. tostring(metrics.Drops) ..
            " | Rolls " .. tostring(metrics.SummonResults),
        "Power " .. tostring(metrics.RawPower or displayedPower() or "?") ..
            " | Gain " .. tostring(metrics.PowerGained) ..
            " | Monsters " .. tostring(countMonsters()),
        "Zone " .. tostring(State.Current.Zone or "?") ..
            " | Target " .. tostring(State.Current.TargetName or State.Current.TargetUUID or "none"),
        "Distance " .. (State.Current.TargetDistance and string.format("%.1f", State.Current.TargetDistance) or "?") ..
            " | OutHook " .. (State.OutgoingHookInstalled and "YES" or "NO"),
        "Errors " .. tostring(#State.Errors)
    }

    BootText.Text = table.concat(lines, "\n")
end

local function createFallbackControls()
    local old = PlayerGui:FindFirstChild("AnimeStarsProfilerControls")
    if old then
        old:Destroy()
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "AnimeStarsProfilerControls"
    gui.ResetOnSpawn = false
    gui.Parent = PlayerGui
    FallbackGui = gui

    local frame = Instance.new("Frame")
    frame.Position = UDim2.fromOffset(18, 260)
    frame.Size = UDim2.fromOffset(230, 330)
    frame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    frame.BorderSizePixel = 0
    frame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 5)
    list.Parent = frame

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 8)
    padding.PaddingLeft = UDim.new(0, 8)
    padding.PaddingRight = UDim.new(0, 8)
    padding.Parent = frame

    local function addButton(text, callback)
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(1, 0, 0, 30)
        button.BackgroundColor3 = Color3.fromRGB(44, 44, 56)
        button.TextColor3 = Color3.new(1, 1, 1)
        button.Text = text
        button.Parent = frame
        button.MouseButton1Click:Connect(callback)
        return button
    end

    local recordButton
    recordButton = addButton("Recording: ON", function()
        State.Enabled = not State.Enabled
        recordButton.Text = "Recording: " .. (State.Enabled and "ON" or "OFF")
    end)

    addButton("Label M1", function() labelAction("M1_ATTACK") end)
    addButton("Label Skill", function() labelAction("SKILL") end)
    addButton("Label Ultimate", function() labelAction("ULTIMATE") end)
    addButton("Label Kill", function() labelAction("KILL_MONSTER") end)
    addButton("Label Zone TP", function() labelAction("TELEPORT_ZONE") end)
    addButton("Label Upgrade", function() labelAction("BUY_UPGRADE") end)
    addButton("Label Quest", function() labelAction("QUEST") end)
    addButton("Label Summon", function() labelAction("SUMMON") end)
    addButton("Scan Monsters", function()
        local ok, err = pcall(scanMonsters)
        if not ok then addError("manual scan", err) end
    end)
    addButton("Export JSON", function()
        exportJSON()
    end)

    stage("[2/7] fallback controls created")
end

createFallbackControls()

local function buildWindUI()
    local ok, result = pcall(function()
        local source = game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua")
        local loader, compileError = loadstring(source)
        if not loader then
            error("WindUI compile: " .. tostring(compileError))
        end
        return loader()
    end)

    if not ok then
        addError("WindUI load", result)
        stage("[6/7] WindUI unavailable; fallback controls active")
        return false
    end

    WindUI = result

    local uiOk, uiError = pcall(function()
        Window = WindUI:CreateWindow({
            Title = "Anime Stars | Game Profiler V1.1",
            Folder = "AnimeStarsProfiler",
            Icon = "database",
            NewElements = true,
            HideSearchBar = false,
            OpenButton = {
                Title = "Profiler",
                Enabled = true,
                Draggable = true,
                OnlyMobile = false
            }
        })

        local Learn = Window:Tab({
            Title = "Learning",
            Icon = "brain",
            Border = true
        })

        Learn:Toggle({
            Title = "Record Session",
            Value = true,
            Callback = function(value)
                State.Enabled = value == true
            end
        })

        Learn:Toggle({
            Title = "Capture Incoming",
            Value = Config.CaptureIncoming,
            Callback = function(value)
                Config.CaptureIncoming = value == true
            end
        })

        Learn:Toggle({
            Title = "Capture Outgoing",
            Desc = "Passive observation only; requires executor hook APIs",
            Value = Config.CaptureOutgoing,
            Callback = function(value)
                Config.CaptureOutgoing = value == true
            end
        })

        local Labels = Window:Tab({
            Title = "Labels",
            Icon = "tag",
            Border = true
        })

        Labels:Button({ Title = "M1 Attack", Callback = function() labelAction("M1_ATTACK") end })
        Labels:Button({ Title = "Skill", Callback = function() labelAction("SKILL") end })
        Labels:Button({ Title = "Ultimate", Callback = function() labelAction("ULTIMATE") end })
        Labels:Button({ Title = "Kill Monster", Callback = function() labelAction("KILL_MONSTER") end })
        Labels:Button({ Title = "Teleport Zone", Callback = function() labelAction("TELEPORT_ZONE") end })
        Labels:Button({ Title = "Buy Upgrade", Callback = function() labelAction("BUY_UPGRADE") end })
        Labels:Button({ Title = "Quest", Callback = function() labelAction("QUEST") end })
        Labels:Button({ Title = "Summon", Callback = function() labelAction("SUMMON") end })

        local Data = Window:Tab({
            Title = "Data",
            Icon = "database",
            Border = true
        })

        Data:Button({
            Title = "Scan Monsters Now",
            Callback = function()
                local scanOk, scanErr = pcall(scanMonsters)
                if not scanOk then
                    addError("WindUI scan", scanErr)
                end
            end
        })

        Data:Button({
            Title = "Export / Copy JSON",
            Callback = function()
                exportJSON()
            end
        })
    end)

    if not uiOk then
        addError("WindUI build", uiError)
        stage("[6/7] WindUI build failed; fallback controls active")
        return false
    end

    stage("[6/7] WindUI ready")
    return true
end

local function bindMonsterSignals()
    local zones = workspace:FindFirstChild("Zones")
    if not zones then
        stage("[5/7] Workspace.Zones missing; periodic scan only")
        return
    end

    local function bindZone(zone)
        if not zone:IsA("Folder") then
            return
        end

        local characters = zone:FindFirstChild("Characters")
        if not characters then
            return
        end

        local addKey = "add_" .. zone.Name
        local removeKey = "remove_" .. zone.Name

        if Connections[addKey] then
            Connections[addKey]:Disconnect()
        end
        if Connections[removeKey] then
            Connections[removeKey]:Disconnect()
        end

        Connections[addKey] = characters.ChildAdded:Connect(function(model)
            task.defer(function()
                local ok, err = pcall(function()
                    local info = enemyInfo(model, zone)
                    if info then
                        pushTimeline("WORLD", "monster/added", {
                            UUID = info.UUID,
                            Zone = info.Zone,
                            Name = info.DisplayName
                        })
                        scanMonsters()
                    end
                end)
                if not ok then
                    addError("monster ChildAdded", err)
                end
            end)
        end)

        Connections[removeKey] = characters.ChildRemoved:Connect(function(model)
            pushTimeline("WORLD", "monster/removed", {
                UUID = model.Name,
                Zone = zone.Name
            })
        end)
    end

    for _, zone in ipairs(zones:GetChildren()) do
        bindZone(zone)
    end

    Connections.ZoneAdded = zones.ChildAdded:Connect(function(zone)
        task.defer(function()
            bindZone(zone)
        end)
    end)

    stage("[5/7] monster signals bound")
end

local function startLoops()
    task.spawn(function()
        while State.Enabled ~= nil do
            if State.Enabled and Config.ScanMonsters then
                local ok, err = pcall(scanMonsters)
                if not ok then
                    addError("periodic monster scan", err)
                end
            end
            task.wait(Config.MonsterScanInterval)
        end
    end)

    task.spawn(function()
        while State.Enabled ~= nil do
            local ok, err = pcall(refreshHud)
            if not ok then
                console("HUD refresh error: " .. tostring(err))
            end
            task.wait(Config.HudRefresh)
        end
    end)
end

local bootOk, bootError = pcall(function()
    stage("[2/7] starting core")

    local scanOk, scanErr = pcall(scanMonsters)
    if not scanOk then
        addError("initial scan", scanErr)
    end

    startIncoming()

    task.defer(function()
        local ok, err = pcall(installOutgoingHook)
        if not ok then
            addError("outgoing hook task", err)
        end
    end)

    local bindOk, bindErr = pcall(bindMonsterSignals)
    if not bindOk then
        addError("bindMonsterSignals", bindErr)
    end

    task.defer(function()
        local ok, err = pcall(buildWindUI)
        if not ok then
            addError("buildWindUI task", err)
        end
    end)

    startLoops()
end)

if not bootOk then
    addError("bootstrap", bootError)
end

State.Status = "READY"
State.Enabled = Config.Enabled

ENV.__ANIME_STARS_PROFILER_STATE = State
ENV.__ANIME_STARS_PROFILER_CONFIG = Config
ENV.__ANIME_STARS_PROFILER_EXPORT = exportJSON
ENV.__ANIME_STARS_PROFILER_LABEL = labelAction
ENV.__ANIME_STARS_PROFILER_CLEANUP = function()
    State.Enabled = nil
    ENV.__ANIME_STARS_PROFILER_CAPTURE = nil

    for key, connection in pairs(Connections) do
        if connection then
            pcall(function()
                connection:Disconnect()
            end)
        end
        Connections[key] = nil
    end

    if Window then
        pcall(function()
            Window:Destroy()
        end)
        Window = nil
    end

    if FallbackGui then
        pcall(function()
            FallbackGui:Destroy()
        end)
        FallbackGui = nil
    end

    if BootGui then
        pcall(function()
            BootGui:Destroy()
        end)
        BootGui = nil
    end
end

stage("[7/7] READY")

if game.PlaceId ~= EXPECTED_PLACE_ID then
    stage("WARNING: PlaceId mismatch " .. tostring(game.PlaceId))
end
