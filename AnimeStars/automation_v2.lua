--[[
    Anime Stars Automation V2 - Efficiency Companion
    PlaceId: 122553263569744

    Goals:
    - Event-driven combat/farm telemetry with minimal polling.
    - Cooldown/lock-aware scheduling hints.
    - Stall detection and stop-condition alerts.
    - DPS / Power / kill / drop / pity efficiency tracking.
    - Trust-boundary-derived defensive features.

    Safety boundary:
    - Never calls FireServer / InvokeServer / firesignal / fireproximityprompt.
    - Never invokes conch_networking or BetterTweenService request remotes.
    - Never bypasses cooldowns, role checks, or server authorization.
    - Uses the game's existing server->client event stream as the source of truth.
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local EXPECTED_PLACE_ID = 122553263569744

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    error("LocalPlayer unavailable")
end

local ENV = (type(getgenv) == "function" and getgenv()) or _G
if type(ENV.__ANIME_STARS_V2_CLEANUP) == "function" then
    pcall(ENV.__ANIME_STARS_V2_CLEANUP)
end

local WindUI = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"
))()

local Config = {
    ObserverEnabled = true,
    HudEnabled = true,
    NotifyRare = true,
    StallWatch = true,
    StallSeconds = 15,
    PowerTarget = 0,      -- 0 = disabled
    KillTarget = 0,       -- 0 = disabled
    TimeLimitMinutes = 0, -- 0 = disabled
    HudRefresh = 0.25,
    MaxRecentDrops = 30,
    MaxRecentRolls = 30,
    MaxPathEntries = 250,
}

local State = {
    Version = 2,
    Tool = "Anime Stars Automation V2 - Efficiency Companion",
    PlaceId = game.PlaceId,
    ExpectedPlaceId = EXPECTED_PLACE_ID,
    StartedUnix = os.time(),
    StartedClock = os.clock(),

    Farm = {
        State = "IDLE",
        LastCombatClock = nil,
        LastEnemyClock = nil,
        LastProgressClock = nil,
        StallNotified = false,
        StopReason = nil,
    },

    Metrics = {
        Damage = 0,
        DamageEvents = 0,
        EnemyDamageEvents = 0,
        Kills = 0,
        Respawns = 0,
        CombatReplicates = 0,
        AbilityExecuted = 0,
        DropsShown = 0,
        DropsFlown = 0,
        Packets = 0,
        Items = 0,

        RawPower = nil,
        StartPower = nil,
        PowerGained = 0,
        ServerReportedPowerGained = 0,
        ServerDamageTotal = 0,

        SessionSeconds = 0,
        DPS = 0,
        KillsPerMinute = 0,
        PowerPerMinute = 0,
    },

    Ability = {
        Cooldowns = {},
        Locks = {},
        SwapLockUntil = 0,
        LastExecuted = nil,
    },

    Banner = {
        Pity = nil,
        RollsObserved = 0,
        RecentRolls = {},
    },

    Drops = {
        Recent = {},
    },

    TrustFeatures = {
        BatchPackets = 0,
        MultiActionPackets = 0,
        MaxBatchSize = 0,
        UnknownPaths = {},
        SensitiveSurfacePresent = false,
        BetterTweenPresent = false,
        GuardedScheduler = true,
    },

    Paths = {},
    Notes = {},
}

local Connections = {}
local Window
local HudGui
local HudText
local MainLoopGeneration = 0

local KNOWN_PATHS = {
    ["sync/update"] = true,
    ["combat/damageDealt"] = true,
    ["combat/replicate"] = true,
    ["enemies/damaged"] = true,
    ["enemies/died"] = true,
    ["enemies/respawned"] = true,
    ["enemies/sync"] = true,
    ["abilities/cooldown"] = true,
    ["abilities/lock"] = true,
    ["abilities/swapLock"] = true,
    ["abilities/executed"] = true,
    ["drops/show"] = true,
    ["drops/fly"] = true,
    ["rewards/display"] = true,
    ["banner/updatePity"] = true,
    ["banner/rollResults"] = true,
    ["gamemodes/started"] = true,
    ["render/createList"] = true,
    ["render/update"] = true,
    ["render/remove"] = true,
    ["skillTreeState"] = true,
    ["skillPurchased"] = true,
    ["passive/active"] = true,
    ["passive/expired"] = true,
    ["passive/visual"] = true,
    ["leaderboard/update"] = true,
    ["guild/leaderboard"] = true,
    ["TeamsUpdated"] = true,
    ["notify"] = true,
    ["character/refresh"] = true,
    ["shadows/sync"] = true,
}

local function clock()
    return os.clock() - State.StartedClock
end

local function safeNumber(v)
    if type(v) == "number" then
        return v
    end
    if type(v) == "string" then
        local cleaned = v:gsub(",", ""):gsub("%s+", ""):gsub("[^%d%.%-KkMmBbTt]", "")
        local n, suffix = cleaned:match("([%d%.%-]+)([KkMmBbTt]?)")
        n = tonumber(n)
        if not n then return nil end
        local mult = {
            K = 1e3, k = 1e3,
            M = 1e6, m = 1e6,
            B = 1e9, b = 1e9,
            T = 1e12, t = 1e12,
        }
        return n * (mult[suffix] or 1)
    end
    return nil
end

local function formatNumber(n)
    n = tonumber(n) or 0
    local abs = math.abs(n)
    if abs >= 1e12 then return string.format("%.2fT", n / 1e12) end
    if abs >= 1e9 then return string.format("%.2fB", n / 1e9) end
    if abs >= 1e6 then return string.format("%.2fM", n / 1e6) end
    if abs >= 1e3 then return string.format("%.2fK", n / 1e3) end
    return string.format("%.0f", n)
end

local function notify(title, content, duration)
    pcall(function()
        WindUI:Notify({
            Title = title,
            Content = content,
            Duration = duration or 5,
        })
    end)
end

local function resolvePath(root, segments)
    local node = root
    for _, seg in ipairs(segments) do
        node = node and node:FindFirstChild(seg)
    end
    return node
end

local function getEventsRemote()
    return resolvePath(ReplicatedStorage, {
        "Shared", "Packages", "Events", "RemoteEvent"
    })
end

local function paramsOf(item)
    if type(item) ~= "table" then return {} end
    return type(item.Params) == "table" and item.Params or {}
end

local function setFarmState(nextState)
    if State.Farm.State ~= nextState then
        State.Farm.State = nextState
    end
end

local function markCombat()
    local now = clock()
    State.Farm.LastCombatClock = now
    State.Farm.LastProgressClock = now
    State.Farm.StallNotified = false
    if State.Farm.State ~= "STOP_TARGET" then
        setFarmState("FIGHTING")
    end
end

local function markEnemyProgress()
    local now = clock()
    State.Farm.LastEnemyClock = now
    State.Farm.LastProgressClock = now
    State.Farm.StallNotified = false
end

local function recordPath(path)
    local entry = State.Paths[path]
    if not entry then
        local count = 0
        for _ in pairs(State.Paths) do count += 1 end
        if count >= Config.MaxPathEntries then
            path = "<overflow>"
            entry = State.Paths[path]
        end
        if not entry then
            entry = { Count = 0, First = clock(), Last = clock() }
            State.Paths[path] = entry
        end
    end
    entry.Count += 1
    entry.Last = clock()

    if not KNOWN_PATHS[path] and path ~= "<overflow>" then
        State.TrustFeatures.UnknownPaths[path] = (State.TrustFeatures.UnknownPaths[path] or 0) + 1
    end
end

local function pushRecent(list, value, maxCount)
    table.insert(list, 1, value)
    while #list > maxCount do
        table.remove(list)
    end
end

local function updatePower(rawPower)
    local n = safeNumber(rawPower)
    if not n then return end

    if State.Metrics.StartPower == nil then
        State.Metrics.StartPower = n
    end

    State.Metrics.RawPower = n
    State.Metrics.PowerGained = math.max(0, n - (State.Metrics.StartPower or n))
    State.Farm.LastProgressClock = clock()
end

local function setCooldown(hero, ability, seconds)
    local now = clock()
    hero = tostring(hero or "?")
    ability = tostring(ability or "?")
    seconds = tonumber(seconds) or 0

    State.Ability.Cooldowns[ability] = {
        Hero = hero,
        Duration = seconds,
        ReadyAt = now + seconds,
        SeenAt = now,
    }
end

local function setLock(ability, seconds)
    ability = tostring(ability or "?")
    seconds = tonumber(seconds) or 0
    State.Ability.Locks[ability] = {
        Duration = seconds,
        Until = clock() + seconds,
    }
end

local function handleSyncUpdate(params)
    local key = params[1]
    local value = params[2]

    if key == "Power" then
        updatePower(value)
    elseif key == "Stats.PowerGained" then
        local n = tonumber(value)
        if n then
            State.Metrics.ServerReportedPowerGained = math.max(
                State.Metrics.ServerReportedPowerGained,
                n
            )
        end
    elseif key == "Stats.DamageDealt" then
        local n = tonumber(value)
        if n then
            State.Metrics.ServerDamageTotal = math.max(State.Metrics.ServerDamageTotal, n)
        end
    end
end

local function handleIncomingItem(item)
    if type(item) ~= "table" then return end

    local path = type(item.Path) == "string" and item.Path or "<unknown>"
    local params = paramsOf(item)

    State.Metrics.Items += 1
    recordPath(path)

    if path == "sync/update" then
        handleSyncUpdate(params)

    elseif path == "combat/damageDealt" then
        local amount = tonumber(params[1])
        if amount then
            State.Metrics.DamageEvents += 1
            State.Metrics.Damage += math.max(0, amount)
        end
        markCombat()

    elseif path == "combat/replicate" then
        State.Metrics.CombatReplicates += 1
        markCombat()

    elseif path == "enemies/damaged" then
        State.Metrics.EnemyDamageEvents += 1
        markCombat()

    elseif path == "enemies/died" then
        State.Metrics.Kills += 1
        markEnemyProgress()
        setFarmState("WAIT_RESPAWN")

    elseif path == "enemies/respawned" then
        State.Metrics.Respawns += 1
        markEnemyProgress()
        if State.Farm.State ~= "STOP_TARGET" then
            setFarmState("FIGHTING")
        end

    elseif path == "abilities/cooldown" then
        setCooldown(params[1], params[2], params[3])

    elseif path == "abilities/lock" then
        setLock(params[1], params[2])

    elseif path == "abilities/swapLock" then
        local seconds = tonumber(params[1]) or 0
        State.Ability.SwapLockUntil = clock() + seconds

    elseif path == "abilities/executed" then
        State.Metrics.AbilityExecuted += 1
        State.Ability.LastExecuted = {
            At = clock(),
            Raw = params[1],
        }
        markCombat()

    elseif path == "drops/show" then
        State.Metrics.DropsShown += 1
        pushRecent(State.Drops.Recent, {
            At = clock(),
            Kind = "show",
            Value = params[1],
        }, Config.MaxRecentDrops)
        if Config.NotifyRare then
            notify("Drop observed", "A server-confirmed drop event was observed.", 3)
        end

    elseif path == "drops/fly" then
        State.Metrics.DropsFlown += 1

    elseif path == "banner/updatePity" then
        State.Banner.Pity = params[1] or params[2] or State.Banner.Pity

    elseif path == "banner/rollResults" then
        State.Banner.RollsObserved += 1
        pushRecent(State.Banner.RecentRolls, {
            At = clock(),
            Result = params[1],
        }, Config.MaxRecentRolls)

    elseif path == "gamemodes/started" then
        State.Farm.StallNotified = false
        State.Farm.LastProgressClock = clock()
        setFarmState("FIGHTING")
    end
end

local function recomputeRates()
    local elapsed = math.max(0.001, clock())
    State.Metrics.SessionSeconds = elapsed
    State.Metrics.DPS = State.Metrics.Damage / elapsed
    State.Metrics.KillsPerMinute = State.Metrics.Kills / (elapsed / 60)
    State.Metrics.PowerPerMinute = State.Metrics.PowerGained / (elapsed / 60)
end

local function checkStopConditions()
    if State.Farm.StopReason then return end

    if Config.PowerTarget > 0
        and State.Metrics.RawPower
        and State.Metrics.RawPower >= Config.PowerTarget
    then
        State.Farm.StopReason = "Power target reached"
    elseif Config.KillTarget > 0
        and State.Metrics.Kills >= Config.KillTarget
    then
        State.Farm.StopReason = "Kill target reached"
    elseif Config.TimeLimitMinutes > 0
        and clock() >= Config.TimeLimitMinutes * 60
    then
        State.Farm.StopReason = "Time limit reached"
    end

    if State.Farm.StopReason then
        setFarmState("STOP_TARGET")
        notify("Farm target", State.Farm.StopReason, 8)
    end
end

local function checkStall()
    if not Config.StallWatch then return end
    if State.Farm.State == "IDLE" or State.Farm.State == "STOP_TARGET" then return end

    local last = State.Farm.LastProgressClock or State.Farm.LastCombatClock
    if not last then return end

    local idle = clock() - last
    if idle >= Config.StallSeconds then
        setFarmState("STALLED")
        if not State.Farm.StallNotified then
            State.Farm.StallNotified = true
            notify(
                "Farm stalled",
                string.format("No combat/progress event for %.1fs. Check the game's native automation/target state.", idle),
                6
            )
        end
    end
end

local function abilityStatus()
    local now = clock()
    local parts = {}

    for name, info in pairs(State.Ability.Cooldowns) do
        local remain = math.max(0, (info.ReadyAt or 0) - now)
        local lock = State.Ability.Locks[name]
        local locked = lock and (lock.Until or 0) > now
        local text
        if remain <= 0 and not locked and State.Ability.SwapLockUntil <= now then
            text = name .. ": READY"
        else
            text = string.format("%s: %.1fs%s", name, remain, locked and " LOCK" or "")
        end
        table.insert(parts, text)
    end

    table.sort(parts)
    if #parts == 0 then return "Abilities: waiting for cooldown events" end
    return table.concat(parts, " | ")
end

local function detectTrustSurfaces()
    local conch = ReplicatedStorage:FindFirstChild("conch_networking")
    local betterTween = resolvePath(ReplicatedStorage, {
        "Shared", "Packages", "BetterTweenService"
    })

    State.TrustFeatures.SensitiveSurfacePresent = conch ~= nil
    State.TrustFeatures.BetterTweenPresent = betterTween ~= nil

    if conch then
        table.insert(State.Notes,
            "conch_networking present: intentionally excluded from automation."
        )
    end
    if betterTween then
        table.insert(State.Notes,
            "BetterTweenService request surface present: observe-only until legitimate protocol is known."
        )
    end
end

local function findBuiltInAutomation()
    local clientGeneral = resolvePath(ReplicatedStorage, {"Client", "General"})
    local clientUI = resolvePath(ReplicatedStorage, {"Client", "UI"})
    local autoAttackConfig = resolvePath(ReplicatedStorage, {
        "Shared", "Configs", "Player", "AutoAttackConfig"
    })
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local automationFrame = playerGui and resolvePath(playerGui, {
        "Main", "Container", "Automation"
    })

    return {
        AutomaticAttackController = clientGeneral
            and clientGeneral:FindFirstChild("AutomaticAttackController") ~= nil,
        AutomationController = clientGeneral
            and clientGeneral:FindFirstChild("AutomationController") ~= nil,
        AutomationManager = clientUI
            and clientUI:FindFirstChild("AutomationManager") ~= nil,
        AutoAttackConfig = autoAttackConfig ~= nil,
        AutomationFrame = automationFrame,
    }
end

local BuiltIn = findBuiltInAutomation()

local function buildHud()
    if HudGui then
        pcall(function() HudGui:Destroy() end)
    end

    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    HudGui = Instance.new("ScreenGui")
    HudGui.Name = "AnimeStarsEfficiencyHUD"
    HudGui.ResetOnSpawn = false
    HudGui.IgnoreGuiInset = false
    HudGui.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.Name = "Panel"
    frame.AnchorPoint = Vector2.new(1, 0)
    frame.Position = UDim2.new(1, -18, 0, 72)
    frame.Size = UDim2.fromOffset(420, 178)
    frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    frame.BackgroundTransparency = 0.12
    frame.BorderSizePixel = 0
    frame.Parent = HudGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Transparency = 0.65
    stroke.Thickness = 1
    stroke.Parent = frame

    HudText = Instance.new("TextLabel")
    HudText.Name = "Text"
    HudText.Position = UDim2.fromOffset(14, 10)
    HudText.Size = UDim2.new(1, -28, 1, -20)
    HudText.BackgroundTransparency = 1
    HudText.TextColor3 = Color3.fromRGB(245, 245, 248)
    HudText.TextXAlignment = Enum.TextXAlignment.Left
    HudText.TextYAlignment = Enum.TextYAlignment.Top
    HudText.Font = Enum.Font.Code
    HudText.TextSize = 14
    HudText.TextWrapped = true
    HudText.RichText = false
    HudText.Parent = frame
end

local function updateHud()
    if not HudGui then return end
    HudGui.Enabled = Config.HudEnabled
    if not Config.HudEnabled or not HudText then return end

    recomputeRates()

    local pwr = State.Metrics.RawPower and formatNumber(State.Metrics.RawPower) or "?"
    local gained = formatNumber(State.Metrics.PowerGained)
    local pity = State.Banner.Pity ~= nil and tostring(State.Banner.Pity) or "?"
    local batch = State.TrustFeatures.MultiActionPackets

    HudText.Text = table.concat({
        "ANIME STARS  |  Efficiency Companion V2",
        string.format(
            "State: %-12s  Time: %.1fm  Power: %s (+%s)",
            State.Farm.State,
            State.Metrics.SessionSeconds / 60,
            pwr,
            gained
        ),
        string.format(
            "DPS: %s  Kills: %d (%.2f/min)  Power/min: %s",
            formatNumber(State.Metrics.DPS),
            State.Metrics.Kills,
            State.Metrics.KillsPerMinute,
            formatNumber(State.Metrics.PowerPerMinute)
        ),
        string.format(
            "Enemy hits: %d  Respawns: %d  Abilities: %d  Drops: %d",
            State.Metrics.EnemyDamageEvents,
            State.Metrics.Respawns,
            State.Metrics.AbilityExecuted,
            State.Metrics.DropsShown
        ),
        abilityStatus(),
        string.format(
            "Pity: %s  Incoming: %d items  Multi-action packets: %d",
            pity,
            State.Metrics.Items,
            batch
        ),
        State.Farm.StopReason and ("Target: " .. State.Farm.StopReason) or
            "Guard: cooldown/lock-aware • no admin/hidden remote invocation",
    }, "\n")
end

local function stopObserver()
    if Connections.Incoming then
        pcall(function() Connections.Incoming:Disconnect() end)
        Connections.Incoming = nil
    end
end

local function startObserver()
    stopObserver()
    if not Config.ObserverEnabled then return false end

    local remote = getEventsRemote()
    if not remote or not remote:IsA("RemoteEvent") then
        notify("Observer", "Events.RemoteEvent not found.", 5)
        return false
    end

    Connections.Incoming = remote.OnClientEvent:Connect(function(payload)
        State.Metrics.Packets += 1

        if type(payload) ~= "table" then return end

        local items = {}
        local count = 0
        for _, item in ipairs(payload) do
            count += 1
            items[count] = item
        end

        if count == 0 and payload.Path then
            count = 1
            items[1] = payload
        end

        if count > 0 then
            State.TrustFeatures.BatchPackets += 1
            if count > 1 then
                State.TrustFeatures.MultiActionPackets += 1
            end
            if count > State.TrustFeatures.MaxBatchSize then
                State.TrustFeatures.MaxBatchSize = count
            end
        end

        for i = 1, count do
            handleIncomingItem(items[i])
        end
    end)

    return true
end

local function openNativeAutomationPanel()
    BuiltIn = findBuiltInAutomation()
    local frame = BuiltIn.AutomationFrame
    if not frame then
        notify("Native automation", "Automation frame not found in PlayerGui.", 5)
        return
    end

    -- UI-only convenience. No network call and no simulated click.
    pcall(function()
        frame.Visible = true
    end)
    notify(
        "Native automation",
        "Opened the game's automation panel. Enable supported options there normally.",
        4
    )
end

local function exportReport()
    recomputeRates()

    local report = {
        Version = State.Version,
        Tool = State.Tool,
        PlaceId = State.PlaceId,
        GeneratedUnix = os.time(),
        Config = Config,
        Farm = State.Farm,
        Metrics = State.Metrics,
        Ability = State.Ability,
        Banner = State.Banner,
        Drops = State.Drops,
        TrustFeatures = State.TrustFeatures,
        Paths = State.Paths,
        Notes = State.Notes,
        BuiltInAutomation = {
            AutomaticAttackController = BuiltIn.AutomaticAttackController,
            AutomationController = BuiltIn.AutomationController,
            AutomationManager = BuiltIn.AutomationManager,
            AutoAttackConfig = BuiltIn.AutoAttackConfig,
        },
    }

    local json = HttpService:JSONEncode(report)

    if type(setclipboard) == "function" then
        pcall(setclipboard, json)
    end

    if type(writefile) == "function" then
        if type(makefolder) == "function" then
            pcall(makefolder, "AnimeStarsAutomation")
        end
        local path = "AnimeStarsAutomation/v2_report_" .. tostring(os.time()) .. ".json"
        pcall(writefile, path, json)
        notify("Report exported", path, 5)
    else
        notify("Report copied", "JSON copied to clipboard when supported.", 5)
    end
end

local function resetSession()
    local keepRawPower = State.Metrics.RawPower

    State.StartedUnix = os.time()
    State.StartedClock = os.clock()

    State.Farm.State = "IDLE"
    State.Farm.LastCombatClock = nil
    State.Farm.LastEnemyClock = nil
    State.Farm.LastProgressClock = nil
    State.Farm.StallNotified = false
    State.Farm.StopReason = nil

    for k in pairs(State.Metrics) do
        if type(State.Metrics[k]) == "number" then
            State.Metrics[k] = 0
        end
    end
    State.Metrics.RawPower = keepRawPower
    State.Metrics.StartPower = keepRawPower

    State.Ability.Cooldowns = {}
    State.Ability.Locks = {}
    State.Ability.SwapLockUntil = 0
    State.Ability.LastExecuted = nil

    State.Banner.RollsObserved = 0
    State.Banner.RecentRolls = {}
    State.Drops.Recent = {}

    State.TrustFeatures.BatchPackets = 0
    State.TrustFeatures.MultiActionPackets = 0
    State.TrustFeatures.MaxBatchSize = 0
    State.TrustFeatures.UnknownPaths = {}
    State.Paths = {}

    notify("Session reset", "Efficiency counters reset.", 4)
end

local function startMainLoop()
    MainLoopGeneration += 1
    local generation = MainLoopGeneration

    task.spawn(function()
        while generation == MainLoopGeneration do
            checkStopConditions()
            checkStall()
            updateHud()
            task.wait(Config.HudRefresh)
        end
    end)
end

local function createWindow()
    Window = WindUI:CreateWindow({
        Title = "Anime Stars | Automation V2",
        Folder = "AnimeStarsAutomation",
        Icon = "activity",
        NewElements = true,
        HideSearchBar = false,
        OpenButton = {
            Title = "Anime Stars V2",
            Enabled = true,
            Draggable = true,
            OnlyMobile = false,
            Scale = 0.8,
        },
        Topbar = {
            Height = 44,
            ButtonsType = "Mac",
        },
    })

    local Main = Window:Section({ Title = "Automation" })
    local FarmTab = Main:Tab({
        Title = "Smart Farm",
        Icon = "zap",
        Border = true,
    })
    local CombatTab = Main:Tab({
        Title = "Combat",
        Icon = "swords",
        Border = true,
    })
    local TrackerTab = Main:Tab({
        Title = "Trackers",
        Icon = "chart-no-axes-combined",
        Border = true,
    })
    local GuardTab = Main:Tab({
        Title = "Efficiency Guard",
        Icon = "shield-check",
        Border = true,
    })

    FarmTab:Section({
        Title = "Event-driven companion",
        Desc = "Uses server-confirmed incoming events. The game's native automation remains the action layer.",
        Box = true,
        BoxBorder = true,
        Opened = true,
    })

    FarmTab:Toggle({
        Title = "Observe gameplay events",
        Desc = "Single shared event listener for combat, abilities, drops, pity and farm state.",
        Default = Config.ObserverEnabled,
        Callback = function(v)
            Config.ObserverEnabled = v
            if v then startObserver() else stopObserver() end
        end,
    })

    FarmTab:Toggle({
        Title = "Efficiency HUD",
        Desc = "Low-overhead live DPS / kills / Power/min / cooldown status.",
        Default = Config.HudEnabled,
        Callback = function(v)
            Config.HudEnabled = v
            updateHud()
        end,
    })

    FarmTab:Toggle({
        Title = "Stall detector",
        Desc = "Warn when no combat/progress event arrives for the configured window.",
        Default = Config.StallWatch,
        Callback = function(v)
            Config.StallWatch = v
        end,
    })

    FarmTab:Slider({
        Title = "Stall timeout",
        Desc = "Seconds without combat/progress before STALLED.",
        Step = 1,
        Value = { Min = 5, Max = 60, Default = Config.StallSeconds },
        Callback = function(v)
            Config.StallSeconds = tonumber(v) or Config.StallSeconds
        end,
    })

    FarmTab:Section({
        Title = "Stop conditions",
        Desc = "Alert/mark STOP_TARGET when a target is reached. No server action is sent.",
        Box = true,
        BoxBorder = true,
        Opened = true,
    })

    FarmTab:Input({
        Title = "Power target",
        Desc = "Supports 100K / 2.5M / raw number. 0 disables.",
        Placeholder = "0",
        Value = "0",
        Callback = function(v)
            Config.PowerTarget = safeNumber(v) or 0
            State.Farm.StopReason = nil
            if State.Farm.State == "STOP_TARGET" then
                setFarmState("IDLE")
            end
        end,
    })

    FarmTab:Input({
        Title = "Kill target",
        Desc = "0 disables.",
        Placeholder = "0",
        Value = "0",
        Callback = function(v)
            Config.KillTarget = math.max(0, tonumber(v) or 0)
            State.Farm.StopReason = nil
            if State.Farm.State == "STOP_TARGET" then
                setFarmState("IDLE")
            end
        end,
    })

    FarmTab:Input({
        Title = "Time limit (minutes)",
        Desc = "0 disables.",
        Placeholder = "0",
        Value = "0",
        Callback = function(v)
            Config.TimeLimitMinutes = math.max(0, tonumber(v) or 0)
            State.Farm.StopReason = nil
            if State.Farm.State == "STOP_TARGET" then
                setFarmState("IDLE")
            end
        end,
    })

    FarmTab:Button({
        Title = "Open game's native automation",
        Desc = "UI-only bridge. No remote call or simulated click.",
        Callback = openNativeAutomationPanel,
    })

    FarmTab:Button({
        Title = "Reset efficiency session",
        Callback = resetSession,
    })

    CombatTab:Section({
        Title = "Cooldown-aware scheduler guard",
        Desc = "Tracks abilities/cooldown, abilities/lock and swapLock so automation logic never needs blind retry loops.",
        Box = true,
        BoxBorder = true,
        Opened = true,
    })

    CombatTab:Toggle({
        Title = "Guarded Scheduler",
        Desc = "Keeps cooldown/lock-aware guard enabled. This does not bypass or generate ability requests.",
        Default = true,
        Callback = function(v)
            State.TrustFeatures.GuardedScheduler = v
        end,
    })

    CombatTab:Button({
        Title = "Show ability status",
        Callback = function()
            notify("Ability status", abilityStatus(), 7)
        end,
    })

    CombatTab:Button({
        Title = "Show current farm state",
        Callback = function()
            recomputeRates()
            notify(
                "Farm state",
                string.format(
                    "%s | DPS %s | Kills %d | Power/min %s",
                    State.Farm.State,
                    formatNumber(State.Metrics.DPS),
                    State.Metrics.Kills,
                    formatNumber(State.Metrics.PowerPerMinute)
                ),
                7
            )
        end,
    })

    TrackerTab:Toggle({
        Title = "Drop notifications",
        Desc = "Notify on server-confirmed drops/show events.",
        Default = Config.NotifyRare,
        Callback = function(v)
            Config.NotifyRare = v
        end,
    })

    TrackerTab:Button({
        Title = "Session summary",
        Callback = function()
            recomputeRates()
            notify(
                "Efficiency",
                string.format(
                    "%.1fm | %d kills | %s DPS | %s Power/min | %d drops | pity %s",
                    State.Metrics.SessionSeconds / 60,
                    State.Metrics.Kills,
                    formatNumber(State.Metrics.DPS),
                    formatNumber(State.Metrics.PowerPerMinute),
                    State.Metrics.DropsShown,
                    tostring(State.Banner.Pity or "?")
                ),
                9
            )
        end,
    })

    TrackerTab:Button({
        Title = "Export JSON report",
        Desc = "Copies JSON and saves to AnimeStarsAutomation when file APIs are available.",
        Callback = exportReport,
    })

    GuardTab:Section({
        Title = "Trust-boundary-derived features",
        Desc = "Turns mapper findings into efficiency/safety guards instead of exploiting them.",
        Box = true,
        BoxBorder = true,
        Opened = true,
    })

    GuardTab:Button({
        Title = "Batch telemetry",
        Desc = "Shows multi-action packet usage observed from the server event stream.",
        Callback = function()
            notify(
                "Batch telemetry",
                string.format(
                    "Packets %d | multi-action %d | max batch %d",
                    State.TrustFeatures.BatchPackets,
                    State.TrustFeatures.MultiActionPackets,
                    State.TrustFeatures.MaxBatchSize
                ),
                7
            )
        end,
    })

    GuardTab:Button({
        Title = "Unknown path watcher",
        Desc = "Lists counts for event paths not in the known gameplay set.",
        Callback = function()
            local rows = {}
            for path, count in pairs(State.TrustFeatures.UnknownPaths) do
                table.insert(rows, path .. "=" .. tostring(count))
            end
            table.sort(rows)
            notify(
                "Unknown paths",
                #rows > 0 and table.concat(rows, ", ") or "No unknown paths observed.",
                8
            )
        end,
    })

    GuardTab:Button({
        Title = "Sensitive surface status",
        Callback = function()
            notify(
                "Sensitive surfaces",
                string.format(
                    "conch=%s | BetterTween=%s | both are observe-only/excluded",
                    tostring(State.TrustFeatures.SensitiveSurfacePresent),
                    tostring(State.TrustFeatures.BetterTweenPresent)
                ),
                7
            )
        end,
    })

    GuardTab:Button({
        Title = "Why no exploit mode?",
        Callback = function()
            notify(
                "Guard policy",
                "Rate/batch/admin findings are used for anti-spam, observability and validation guards—not cooldown bypass or privilege actions.",
                9
            )
        end,
    })
end

local function cleanup()
    MainLoopGeneration += 1
    stopObserver()

    if HudGui then
        pcall(function() HudGui:Destroy() end)
        HudGui = nil
        HudText = nil
    end

    if Window then
        pcall(function() Window:Destroy() end)
        Window = nil
    end
end

ENV.__ANIME_STARS_V2_CLEANUP = cleanup

if game.PlaceId ~= EXPECTED_PLACE_ID then
    notify(
        "Place mismatch",
        string.format("Expected %d, current %d. Observer can still run but assumptions may be wrong.",
            EXPECTED_PLACE_ID, game.PlaceId),
        8
    )
end

detectTrustSurfaces()
buildHud()
createWindow()

-- Seed local displayed Power until a raw sync/update arrives.
do
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    local power = leaderstats and leaderstats:FindFirstChild("Power")
    if power and power:IsA("ValueBase") then
        updatePower(power.Value)
    end
end

if Config.ObserverEnabled then
    startObserver()
end
startMainLoop()
updateHud()

notify(
    "Anime Stars V2",
    "Efficiency companion active: event-driven metrics, cooldown guard, stall detection, drops/pity and trust telemetry.",
    7
)

return {
    State = State,
    Config = Config,
    Cleanup = cleanup,
    Export = exportReport,
    BuiltInAutomation = BuiltIn,
}
