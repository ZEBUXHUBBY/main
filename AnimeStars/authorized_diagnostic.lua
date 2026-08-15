--[[
    Anime Stars - Authorized Diagnostic
    PlaceId: 122553263569744

    PURPOSE
    - Read-only runtime diagnostics for an authorized environment.
    - Samples local player state.
    - Observes server -> client Events.RemoteEvent paths.
    - Scans replicated trust-boundary surfaces without invoking them.
    - Produces a JSON report for review.

    SAFETY BOUNDARY
    - This script never calls :FireServer(), :InvokeServer(), fireproximityprompt(),
      firesignal(), or hidden/admin remotes.
    - It does not fuzz arguments, bypass cooldowns, automate combat, or alter economy state.
    - "Findings" are hypotheses/review priorities, not confirmed vulnerabilities.
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
    error("LocalPlayer is unavailable")
end

local ENV = (type(getgenv) == "function" and getgenv()) or _G
if type(ENV.__ANIME_STARS_AUTH_DIAG_CLEANUP) == "function" then
    pcall(ENV.__ANIME_STARS_AUTH_DIAG_CLEANUP)
end

local WindUI = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"
))()

local Config = {
    SampleInterval = 2,
    MaxSamples = 500,
    MaxIncomingPathEntries = 250,
    ObserveIncoming = true,
}

local State = {
    SchemaVersion = 1,
    Tool = "Anime Stars Authorized Diagnostic",
    PlaceId = game.PlaceId,
    ExpectedPlaceId = EXPECTED_PLACE_ID,
    StartedUnix = os.time(),
    StartedClock = os.clock(),
    Monitoring = false,
    IncomingObserver = false,
    Samples = {},
    Incoming = {
        TotalPackets = 0,
        TotalItems = 0,
        Paths = {},
        LastPacketClock = nil,
        MinPacketGap = nil,
    },
    Surface = {},
    Findings = {},
    Notes = {},
}

local Connections = {}
local MonitorGeneration = 0
local Window

local function safeFullName(instance)
    if not instance then
        return nil
    end
    local ok, result = pcall(function()
        return instance:GetFullName()
    end)
    return ok and result or instance.Name
end

local function resolvePath(root, segments)
    local node = root
    for _, name in ipairs(segments) do
        if not node then
            return nil
        end
        node = node:FindFirstChild(name)
    end
    return node
end

local function valueOf(object)
    if not object then
        return nil
    end

    local ok, result = pcall(function()
        if object:IsA("ValueBase") then
            return object.Value
        end
        return nil
    end)

    return ok and result or nil
end

local function shallowCount(tbl)
    local n = 0
    for _ in pairs(tbl) do
        n += 1
    end
    return n
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

local function getCharacterState()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")

    local position
    if root and root:IsA("BasePart") then
        local p = root.Position
        position = { X = p.X, Y = p.Y, Z = p.Z }
    end

    return {
        CharacterPresent = character ~= nil,
        Health = humanoid and humanoid.Health or nil,
        MaxHealth = humanoid and humanoid.MaxHealth or nil,
        WalkSpeed = humanoid and humanoid.WalkSpeed or nil,
        Position = position,
    }
end

local function getPlayerPowerState()
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    local leaderPower = leaderstats and leaderstats:FindFirstChild("Power")
    local directPower = LocalPlayer:FindFirstChild("Power")

    return {
        LeaderstatsPower = valueOf(leaderPower),
        DirectPower = valueOf(directPower),
        AttributePower = LocalPlayer:GetAttribute("Power"),
    }
end

local function captureSnapshot(reason)
    local sample = {
        Clock = os.clock() - State.StartedClock,
        Unix = os.time(),
        Reason = reason or "interval",
        Player = {
            Name = LocalPlayer.Name,
            UserId = LocalPlayer.UserId,
            ClientActive = LocalPlayer:GetAttribute("ClientActive"),
            Dashing = LocalPlayer:GetAttribute("dashing"),
            Sprinting = LocalPlayer:GetAttribute("sprinting"),
        },
        Power = getPlayerPowerState(),
        Character = getCharacterState(),
    }

    table.insert(State.Samples, sample)
    if #State.Samples > Config.MaxSamples then
        table.remove(State.Samples, 1)
    end

    return sample
end

local function getEventsRemote()
    return resolvePath(ReplicatedStorage, {
        "Shared", "Packages", "Events", "RemoteEvent",
    })
end

local function scanSurface()
    local eventsRemote = getEventsRemote()
    local unreliableEvents = resolvePath(ReplicatedStorage, {
        "Shared", "Packages", "Events", "UnreliableRemoteEvent",
    })
    local betterTween = resolvePath(ReplicatedStorage, {
        "Shared", "Packages", "BetterTweenService",
    })
    local conch = ReplicatedStorage:FindFirstChild("conch_networking")
    local clientGeneral = resolvePath(ReplicatedStorage, { "Client", "General" })
    local clientUI = resolvePath(ReplicatedStorage, { "Client", "UI" })
    local autoAttackConfig = resolvePath(ReplicatedStorage, {
        "Shared", "Configs", "Player", "AutoAttackConfig",
    })
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local builtInAutomationFrame = playerGui and resolvePath(playerGui, {
        "Main", "Container", "Automation",
    })

    local function remoteEntry(parent, name)
        local obj = parent and parent:FindFirstChild(name)
        return {
            Present = obj ~= nil,
            ClassName = obj and obj.ClassName or nil,
            FullName = safeFullName(obj),
        }
    end

    State.Surface = {
        ScannedUnix = os.time(),
        EventBus = {
            RemoteEvent = {
                Present = eventsRemote ~= nil,
                ClassName = eventsRemote and eventsRemote.ClassName or nil,
                FullName = safeFullName(eventsRemote),
            },
            UnreliableRemoteEvent = {
                Present = unreliableEvents ~= nil,
                ClassName = unreliableEvents and unreliableEvents.ClassName or nil,
                FullName = safeFullName(unreliableEvents),
            },
        },
        BetterTweenService = {
            Present = betterTween ~= nil,
            PlayTween1 = remoteEntry(betterTween, "_playTween1"),
            PlayTween2 = remoteEntry(betterTween, "_playTween2"),
            PlayTween3 = remoteEntry(betterTween, "_playTween3"),
            RequestReliable = remoteEntry(betterTween, "_requestReliable"),
            RequestUnreliable = remoteEntry(betterTween, "_requestUnreliable"),
        },
        ConchNetworking = {
            Present = conch ~= nil,
            InvokeServerCommand = remoteEntry(conch, "invoke_server_command"),
            CreateUser = remoteEntry(conch, "create_user"),
            UpdateUserRoles = remoteEntry(conch, "update_user_roles"),
            UpdateRolePermissions = remoteEntry(conch, "update_role_permissions"),
            RegisterCommand = remoteEntry(conch, "register_command"),
            Log = remoteEntry(conch, "log"),
            LogCommand = remoteEntry(conch, "log_command"),
            Ready = remoteEntry(conch, "ready"),
        },
        BuiltInAutomation = {
            AutomaticAttackController = {
                Present = clientGeneral and clientGeneral:FindFirstChild("AutomaticAttackController") ~= nil,
            },
            AutomationController = {
                Present = clientGeneral and clientGeneral:FindFirstChild("AutomationController") ~= nil,
            },
            AutomationManager = {
                Present = clientUI and clientUI:FindFirstChild("AutomationManager") ~= nil,
            },
            AutoAttackConfig = { Present = autoAttackConfig ~= nil },
            PlayerGuiAutomationFrame = { Present = builtInAutomationFrame ~= nil },
        },
    }

    local hasBuiltinAuto =
        State.Surface.BuiltInAutomation.AutomaticAttackController.Present
        or State.Surface.BuiltInAutomation.AutomationController.Present
        or State.Surface.BuiltInAutomation.AutomationManager.Present
        or State.Surface.BuiltInAutomation.AutoAttackConfig.Present

    local conchSensitivePresent =
        State.Surface.ConchNetworking.InvokeServerCommand.Present
        or State.Surface.ConchNetworking.CreateUser.Present
        or State.Surface.ConchNetworking.UpdateUserRoles.Present
        or State.Surface.ConchNetworking.UpdateRolePermissions.Present
        or State.Surface.ConchNetworking.RegisterCommand.Present

    State.Findings = {
        {
            Id = "EVENT_BUS_RATE_POLICY",
            Severity = "REVIEW",
            Confidence = hasBuiltinAuto and 0.40 or 0.57,
            Status = "UNCONFIRMED",
            Title = "Rate-limit / concurrency policy on shared event bus",
            Evidence = "Prior mapper capture observed accepted traffic with a 0.032s minimum call gap.",
            CounterEvidence = hasBuiltinAuto
                and "Built-in automatic attack / automation components are replicated, so fast legitimate traffic is expected."
                or "Built-in automation was not detected by this runtime scan.",
            VerifyServerSide = "Measure per-action cooldown enforcement on the server under an explicitly authorized test account. Do not infer a bug from client timing alone.",
        },
        {
            Id = "EVENT_BUS_BATCH_VALIDATION",
            Severity = "MEDIUM",
            Confidence = 0.62,
            Status = "UNCONFIRMED",
            Title = "Per-item validation inside batched event payloads",
            Evidence = "Prior mapper capture observed the same event bus carrying both a one-action array and a two-action array (combat/m1 + abilities/cast).",
            Risk = "If validation/rate accounting occurs once per packet instead of once per action, batching could create inconsistent cooldown or authorization behavior.",
            VerifyServerSide = "Validate every action independently: schema, ownership, state, cooldown, target, sequence, and rate budget.",
        },
        {
            Id = "CLIENT_HERO_AND_SEQUENCE_TRUST",
            Severity = "MEDIUM",
            Confidence = 0.52,
            Status = "UNCONFIRMED",
            Title = "Client-supplied hero / attack sequence parameters",
            Evidence = "Observed combat/m1 payload includes a hero identifier and attack index (example: Huvia, 1).",
            Risk = "Server logic should not trust the client to choose a hero or sequence state that the player has not actually equipped/reached.",
            VerifyServerSide = "Derive authoritative equipped hero and combo/sequence state on the server, or strictly validate the supplied values against server state.",
        },
        {
            Id = "CONCH_ADMIN_TRUST_BOUNDARY",
            Severity = conchSensitivePresent and "HIGH-PRIORITY REVIEW" or "INFO",
            Confidence = conchSensitivePresent and 0.70 or 0.20,
            Status = "UNCONFIRMED",
            Title = "Replicated command / role-management remote surface",
            Evidence = conchSensitivePresent
                and "Command, create-user, user-role and role-permission remotes are present in ReplicatedStorage."
                or "Sensitive conch remotes were not found by this runtime scan.",
            Risk = "Remote presence is not a vulnerability. The server must authenticate identity/role and authorize every requested operation regardless of client visibility.",
            VerifyServerSide = "Review server handlers and deny-by-default authorization. This diagnostic intentionally does not invoke these remotes.",
        },
        {
            Id = "BETTER_TWEEN_REQUEST_SURFACE",
            Severity = "LOW",
            Confidence = 0.25,
            Status = "UNEXPLORED",
            Title = "BetterTweenService request remotes",
            Evidence = "Request remotes are replicated but were not observed during the supplied normal-play capture.",
            Risk = "Unknown until the legitimate feature that uses them is identified.",
            VerifyServerSide = "Capture their normal signature by using the corresponding feature normally; do not fuzz an unknown protocol.",
        },
        {
            Id = "SERVER_AUTHORITATIVE_POWER",
            Severity = "REVIEW",
            Confidence = 0.50,
            Status = "UNCONFIRMED",
            Title = "Server authority for damage / Power progression",
            Evidence = "Power changes were strongly action-correlated in the prior capture, while server -> client sync messages carried Power and DamageDealt updates.",
            PositiveSignal = "The observed outgoing combat payload did not directly contain a Power amount.",
            VerifyServerSide = "Keep damage, reward, and Power calculations server-authoritative and treat client action requests only as intent.",
        },
    }

    return State.Surface, State.Findings
end

local function addIncomingItem(item)
    if type(item) ~= "table" then return end

    local path = item.Path
    if type(path) ~= "string" then path = "<unknown>" end

    local entry = State.Incoming.Paths[path]
    if not entry then
        if shallowCount(State.Incoming.Paths) >= Config.MaxIncomingPathEntries then
            path = "<overflow>"
            entry = State.Incoming.Paths[path]
        end

        if not entry then
            entry = {
                Count = 0,
                FirstClock = os.clock() - State.StartedClock,
                LastClock = nil,
            }
            State.Incoming.Paths[path] = entry
        end
    end

    entry.Count += 1
    entry.LastClock = os.clock() - State.StartedClock
    State.Incoming.TotalItems += 1
end

local function stopIncomingObserver()
    local connection = Connections.Incoming
    if connection then
        pcall(function() connection:Disconnect() end)
        Connections.Incoming = nil
    end
    State.IncomingObserver = false
end

local function startIncomingObserver()
    stopIncomingObserver()

    local remote = getEventsRemote()
    if not remote or not remote:IsA("RemoteEvent") then
        notify("Incoming observer", "Events.RemoteEvent was not found.", 5)
        return false
    end

    Connections.Incoming = remote.OnClientEvent:Connect(function(payload)
        local now = os.clock()
        State.Incoming.TotalPackets += 1

        if State.Incoming.LastPacketClock then
            local gap = now - State.Incoming.LastPacketClock
            if not State.Incoming.MinPacketGap or gap < State.Incoming.MinPacketGap then
                State.Incoming.MinPacketGap = gap
            end
        end
        State.Incoming.LastPacketClock = now

        if type(payload) == "table" then
            local sawArrayItem = false
            for _, item in ipairs(payload) do
                sawArrayItem = true
                addIncomingItem(item)
            end
            if not sawArrayItem and payload.Path then
                addIncomingItem(payload)
            end
        end
    end)

    State.IncomingObserver = true
    return true
end

local function setMonitoring(enabled)
    State.Monitoring = enabled
    MonitorGeneration += 1
    local generation = MonitorGeneration
    if not enabled then return end

    task.spawn(function()
        while State.Monitoring and generation == MonitorGeneration do
            captureSnapshot("interval")
            task.wait(Config.SampleInterval)
        end
    end)
end

local function normalizeForJson()
    return {
        SchemaVersion = State.SchemaVersion,
        Tool = State.Tool,
        PlaceId = State.PlaceId,
        ExpectedPlaceId = State.ExpectedPlaceId,
        StartedUnix = State.StartedUnix,
        GeneratedUnix = os.time(),
        Monitoring = State.Monitoring,
        IncomingObserver = State.IncomingObserver,
        Config = Config,
        Samples = State.Samples,
        Incoming = State.Incoming,
        Surface = State.Surface,
        Findings = State.Findings,
        Notes = State.Notes,
    }
end

local function reportJson()
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(normalizeForJson())
    end)
    if not ok then
        warn("[Anime Stars Diagnostic] JSON encode failed:", encoded)
        return nil, encoded
    end
    return encoded
end

local function copyReport()
    local encoded, err = reportJson()
    if not encoded then
        notify("Copy failed", tostring(err), 6)
        return false
    end
    if type(setclipboard) ~= "function" then
        notify("Clipboard unavailable", "Executor does not expose setclipboard().", 5)
        return false
    end
    local ok, clipErr = pcall(setclipboard, encoded)
    if not ok then
        notify("Copy failed", tostring(clipErr), 6)
        return false
    end
    notify("Report copied", ("JSON report copied (%d bytes)."):format(#encoded), 5)
    return true
end

local function saveReport()
    local encoded, err = reportJson()
    if not encoded then
        notify("Save failed", tostring(err), 6)
        return false
    end
    if type(writefile) ~= "function" then
        notify("Save unavailable", "Executor does not expose writefile().", 5)
        return false
    end

    local folder = "AnimeStarsDiagnostic"
    if type(makefolder) == "function" then
        pcall(function()
            if type(isfolder) ~= "function" or not isfolder(folder) then
                makefolder(folder)
            end
        end)
    end

    local filename = ("%s/report_%d.json"):format(folder, os.time())
    local ok, writeErr = pcall(writefile, filename, encoded)
    if not ok then
        notify("Save failed", tostring(writeErr), 6)
        return false
    end
    notify("Report saved", filename, 6)
    return true
end

local function findingsSummary()
    local counts = {}
    for _, finding in ipairs(State.Findings) do
        counts[finding.Severity] = (counts[finding.Severity] or 0) + 1
    end
    local parts = {}
    for severity, count in pairs(counts) do
        table.insert(parts, severity .. "=" .. tostring(count))
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

scanSurface()
captureSnapshot("startup")
if Config.ObserveIncoming then startIncomingObserver() end

Window = WindUI:CreateWindow({
    Title = "Anime Stars | Authorized Diagnostic",
    Folder = "AnimeStarsDiagnostic",
    Icon = "solar:shield-check-bold",
    NewElements = true,
    HideSearchBar = false,
    OpenButton = {
        Title = "Open Anime Stars Diagnostic",
        Enabled = true,
        Draggable = true,
        OnlyMobile = false,
        Scale = 0.55,
    },
    Topbar = { Height = 44, ButtonsType = "Mac" },
})

pcall(function()
    Window:Tag({ Title = "READ-ONLY", Icon = "shield-check", Border = true })
end)

local OverviewTab = Window:Tab({
    Title = "Overview",
    Desc = "Read-only authorized diagnostics",
    Icon = "solar:home-2-bold",
    IconShape = "Square",
    Border = true,
})

OverviewTab:Section({
    Title = "Safety boundary",
    Desc = "No FireServer/InvokeServer, no fuzzing, no cooldown bypass, no hidden/admin remote calls. The tool only reads replicated/client state and listens to server -> client traffic.",
    Box = true,
    BoxBorder = true,
    Opened = true,
})

OverviewTab:Section({
    Title = "Runtime",
    Desc = ("Player: %s (%d) | PlaceId: %d | Expected: %d | Studio: %s")
        :format(LocalPlayer.Name, LocalPlayer.UserId, game.PlaceId, EXPECTED_PLACE_ID, tostring(RunService:IsStudio())),
    Box = true,
    BoxBorder = true,
    Opened = true,
})

OverviewTab:Button({
    Title = "Capture snapshot now",
    Desc = "Record player attributes, Power values, health, WalkSpeed and position.",
    Icon = "camera",
    Callback = function()
        captureSnapshot("manual")
        notify("Snapshot captured", ("Samples: %d"):format(#State.Samples), 4)
    end,
})

OverviewTab:Button({
    Title = "Rescan replicated surfaces",
    Desc = "Checks event bus, BetterTween, conch command remotes and built-in automation components. Does not call them.",
    Icon = "scan-search",
    Callback = function()
        scanSurface()
        notify("Surface scan complete", ("Findings: %d | %s"):format(#State.Findings, findingsSummary()), 6)
    end,
})

local MonitorTab = Window:Tab({
    Title = "Monitor",
    Desc = "Automated passive sampling",
    Icon = "activity",
    IconShape = "Square",
    Border = true,
})

MonitorTab:Toggle({
    Title = "Auto sample local state",
    Desc = "Periodically records local state only. No gameplay action is sent.",
    Callback = function(value)
        setMonitoring(value)
        notify("Auto sample", value and "Enabled" or "Disabled", 3)
    end,
})

MonitorTab:Slider({
    Title = "Sample interval",
    Desc = "Seconds between read-only snapshots.",
    Step = 0.5,
    Width = 220,
    Value = { Min = 0.5, Max = 10, Default = Config.SampleInterval },
    Callback = function(value)
        Config.SampleInterval = math.max(0.5, tonumber(value) or 2)
    end,
})

MonitorTab:Toggle({
    Title = "Observe incoming event paths",
    Desc = "Counts server -> client Path names from Events.RemoteEvent. Payload values are not replayed.",
    Callback = function(value)
        if value then
            local ok = startIncomingObserver()
            if ok then notify("Incoming observer", "Enabled", 3) end
        else
            stopIncomingObserver()
            notify("Incoming observer", "Disabled", 3)
        end
    end,
})

MonitorTab:Button({
    Title = "Incoming summary",
    Desc = "Shows packet/item/path counts collected by the passive listener.",
    Icon = "list-tree",
    Callback = function()
        notify(
            "Incoming summary",
            ("Packets=%d | Items=%d | Paths=%d | min incoming gap=%s"):format(
                State.Incoming.TotalPackets,
                State.Incoming.TotalItems,
                shallowCount(State.Incoming.Paths),
                State.Incoming.MinPacketGap and string.format("%.4fs", State.Incoming.MinPacketGap) or "n/a"
            ),
            7
        )
    end,
})

local FindingsTab = Window:Tab({
    Title = "Findings",
    Desc = "Investigation priorities, not confirmed vulnerabilities",
    Icon = "solar:danger-triangle-bold",
    IconShape = "Square",
    Border = true,
})

FindingsTab:Section({
    Title = "[MEDIUM] Event-bus batch validation",
    Desc = "Observed capture contained both one-action and two-action arrays. Server should validate and rate-account every action independently, not only the outer packet.",
    Box = true, BoxBorder = true, Opened = true,
})

FindingsTab:Section({
    Title = "[MEDIUM] Client hero / combo parameters",
    Desc = "Observed combat/m1 includes hero + attack index. Server should derive or strictly validate equipped hero and sequence state.",
    Box = true, BoxBorder = true, Opened = true,
})

FindingsTab:Section({
    Title = "[HIGH-PRIORITY REVIEW] conch command / role remotes",
    Desc = "invoke_server_command, create_user, update_user_roles, update_role_permissions and register_command are replicated in this snapshot. Presence alone is not a bug; server authorization must be deny-by-default.",
    Box = true, BoxBorder = true, Opened = true,
})

FindingsTab:Section({
    Title = "[REVIEW] Rate policy",
    Desc = "The mapper saw a 0.032s minimum accepted gap, but this game also exposes built-in automatic attack / automation components. Fast traffic can be legitimate; verify server cooldown policy in an authorized test environment rather than spamming the remote.",
    Box = true, BoxBorder = true, Opened = true,
})

FindingsTab:Section({
    Title = "[LOW] BetterTween request remotes",
    Desc = "The supplied capture never exercised _requestReliable/_requestUnreliable. Identify their legitimate feature and real signature before any deeper testing.",
    Box = true, BoxBorder = true, Opened = true,
})

local SurfaceTab = Window:Tab({
    Title = "Surface",
    Desc = "Read-only trust-boundary inventory",
    Icon = "network",
    IconShape = "Square",
    Border = true,
})

SurfaceTab:Section({
    Title = "Events.RemoteEvent",
    Desc = State.Surface.EventBus.RemoteEvent.Present
        and ("Present: " .. tostring(State.Surface.EventBus.RemoteEvent.FullName))
        or "Not found",
    Box = true, BoxBorder = true, Opened = true,
})

SurfaceTab:Section({
    Title = "Built-in automation",
    Desc = ("AutomaticAttackController=%s | AutomationController=%s | AutomationManager=%s | AutoAttackConfig=%s | AutomationFrame=%s"):format(
        tostring(State.Surface.BuiltInAutomation.AutomaticAttackController.Present),
        tostring(State.Surface.BuiltInAutomation.AutomationController.Present),
        tostring(State.Surface.BuiltInAutomation.AutomationManager.Present),
        tostring(State.Surface.BuiltInAutomation.AutoAttackConfig.Present),
        tostring(State.Surface.BuiltInAutomation.PlayerGuiAutomationFrame.Present)
    ),
    Box = true, BoxBorder = true, Opened = true,
})

SurfaceTab:Section({
    Title = "conch_networking",
    Desc = ("Present=%s | invoke=%s | create_user=%s | roles=%s | permissions=%s"):format(
        tostring(State.Surface.ConchNetworking.Present),
        tostring(State.Surface.ConchNetworking.InvokeServerCommand.Present),
        tostring(State.Surface.ConchNetworking.CreateUser.Present),
        tostring(State.Surface.ConchNetworking.UpdateUserRoles.Present),
        tostring(State.Surface.ConchNetworking.UpdateRolePermissions.Present)
    ),
    Box = true, BoxBorder = true, Opened = true,
})

local ExportTab = Window:Tab({
    Title = "Export",
    Desc = "Save evidence without sending gameplay actions",
    Icon = "file-json",
    IconShape = "Square",
    Border = true,
})

ExportTab:Button({
    Title = "Copy JSON report",
    Desc = "Copies surface inventory, findings, samples and incoming Path counters.",
    Icon = "copy",
    Callback = copyReport,
})

ExportTab:Button({
    Title = "Save JSON report",
    Desc = "Writes AnimeStarsDiagnostic/report_<unix>.json when executor writefile() is available.",
    Icon = "save",
    Callback = saveReport,
})

ExportTab:Button({
    Title = "Print finding IDs",
    Desc = "Prints current review priorities to the executor console.",
    Icon = "terminal",
    Callback = function()
        print("===== ANIME STARS AUTHORIZED DIAGNOSTIC FINDINGS =====")
        for _, finding in ipairs(State.Findings) do
            print(finding.Id, "|", finding.Severity, "| confidence", finding.Confidence, "|", finding.Title)
        end
        print("===== END =====")
        notify("Printed", ("Findings: %d"):format(#State.Findings), 3)
    end,
})

if game.PlaceId ~= EXPECTED_PLACE_ID then
    table.insert(State.Notes, ("WARNING: running on PlaceId %d, expected %d."):format(game.PlaceId, EXPECTED_PLACE_ID))
    notify(
        "Wrong PlaceId",
        ("This diagnostic was built for %d; current place is %d. Read-only mode remains active."):format(EXPECTED_PLACE_ID, game.PlaceId),
        8
    )
else
    notify("Anime Stars Diagnostic", ("Ready. Read-only surface scan found %d review items."):format(#State.Findings), 6)
end

ENV.__ANIME_STARS_AUTH_DIAG_STATE = State
ENV.__ANIME_STARS_AUTH_DIAG_CLEANUP = function()
    State.Monitoring = false
    MonitorGeneration += 1
    stopIncomingObserver()

    for key, connection in pairs(Connections) do
        if connection then
            pcall(function() connection:Disconnect() end)
        end
        Connections[key] = nil
    end

    if Window then
        pcall(function() Window:Destroy() end)
    end
end
