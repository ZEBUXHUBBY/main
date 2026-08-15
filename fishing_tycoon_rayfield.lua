--[[
    Fishing / Tycoon Rayfield Hub

    Built from the supplied Cobalt Logger capture.

    Confirmed client -> server calls used by this script:
      ReplicatedStorage.LockPlayerEvent:FireServer(boolean)
      ReplicatedStorage.GiveFishEvent:FireServer()
      ReplicatedStorage.UpdateTutorialEvent:FireServer(4)
      ReplicatedStorage.RebirthEvent:FireServer("NormalRebirth")

    Events that appeared only as server -> client responses are monitored only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Environment = (getgenv and getgenv()) or _G
local HUB_KEY = "__FishingTycoonRayfieldHub_20260815"

-- Unload an older copy before creating a new one.
local PreviousHub = Environment[HUB_KEY]
if type(PreviousHub) == "table" and type(PreviousHub.Cleanup) == "function" then
    pcall(PreviousHub.Cleanup)
end

local Rayfield
local Loaded, LoadError = pcall(function()
    local Source = game:HttpGet("https://sirius.menu/rayfield")
    local Chunk, CompileError = loadstring(Source)

    if not Chunk then
        error(CompileError or "Rayfield could not be compiled")
    end

    Rayfield = Chunk()
end)

if not Loaded or not Rayfield then
    warn("[Fishing Hub] Rayfield failed to load: " .. tostring(LoadError))
    return
end

local State = {
    Alive = true,

    Auto = {
        GiveFish = false,
        Rebirth = false,
    },

    Generation = {
        GiveFish = 0,
        Rebirth = 0,
    },

    GiveFishDelay = 0.75,
    RebirthDelay = 2.0,

    ManualLocked = false,
    LockWhileAutoFish = false,

    NotifyFish = true,
    NotifyWeather = true,
    NotifyActions = true,

    Connections = {},
    MissingWarned = {},
    NotificationTimes = {},

    Counters = {
        FishRewards = 0,
        RebirthSuccess = 0,
        UpgradeSuccess = 0,
        SoldEvents = 0,
    },

    LastWeather = "Unknown",
    LastFish = "None",
    LastEventSignature = nil,
    LastEventTime = 0,
}

Environment[HUB_KEY] = State

local REMOTE_PATHS = {
    -- Confirmed outgoing calls
    LockPlayer = {"LockPlayerEvent"},
    GiveFish = {"GiveFishEvent"},
    Tutorial = {"UpdateTutorialEvent"},
    Rebirth = {"RebirthEvent"},

    -- Incoming/status events
    FishReward = {"FishRewardResultEvent"},
    SellFish = {"SellFishEvent"},
    DailyReward = {"DailyRewardEvent"},
    Weather = {"WeatherEvents", "WeatherUpdateEvent"},
    RodUpgrade = {"RodUpgradeEvents", "RequestUpgradeEvent"},
    BuyRod = {"RodUpgradeEvents", "BuyRodEvent"},
    UpgradeVFX = {"TycoonEvents", "SyncUpgradeVFX"},
    CoinVFX = {"SpawnCoinVFX"},
}

local function pathToString(Path)
    return "ReplicatedStorage." .. table.concat(Path, ".")
end

local function resolvePath(Path)
    local Current = ReplicatedStorage

    for _, ChildName in ipairs(Path) do
        Current = Current:FindFirstChild(ChildName)
        if not Current then
            return nil
        end
    end

    return Current
end

local function getRemote(Key)
    local Path = REMOTE_PATHS[Key]
    if not Path then
        return nil
    end

    local Remote = resolvePath(Path)
    if Remote and Remote:IsA("RemoteEvent") then
        return Remote
    end

    return nil
end

local function notify(Title, Content, Duration, RateKey, Cooldown)
    if not State.Alive then
        return
    end

    if RateKey then
        local Now = os.clock()
        local Last = State.NotificationTimes[RateKey] or -math.huge
        local RequiredDelay = Cooldown or 0

        if Now - Last < RequiredDelay then
            return
        end

        State.NotificationTimes[RateKey] = Now
    end

    pcall(function()
        Rayfield:Notify({
            Title = tostring(Title),
            Content = tostring(Content),
            Duration = Duration or 4,
        })
    end)
end

local function fireRemote(Key, ...)
    local Remote = getRemote(Key)

    if not Remote then
        if not State.MissingWarned[Key] then
            State.MissingWarned[Key] = true
            notify(
                "Remote missing",
                pathToString(REMOTE_PATHS[Key] or {Key}) .. " was not found.",
                5,
                "Missing_" .. tostring(Key),
                5
            )
        end

        return false
    end

    local Arguments = {...}
    local ArgumentCount = select("#", ...)
    local Unpack = table.unpack or unpack

    local Success, ErrorMessage = pcall(function()
        Remote:FireServer(Unpack(Arguments, 1, ArgumentCount))
    end)

    if not Success then
        notify(
            "Remote error",
            tostring(Key) .. ": " .. tostring(ErrorMessage),
            5,
            "RemoteError_" .. tostring(Key),
            4
        )
    end

    return Success
end

local function desiredLockState()
    return State.ManualLocked or (State.Auto.GiveFish and State.LockWhileAutoFish)
end

local function syncLockState()
    fireRemote("LockPlayer", desiredLockState())
end

local function setAutomation(Name, Enabled, DelayField, Action)
    State.Auto[Name] = Enabled == true
    State.Generation[Name] = (State.Generation[Name] or 0) + 1

    local ThisGeneration = State.Generation[Name]

    if not State.Auto[Name] then
        return
    end

    task.spawn(function()
        while State.Alive
            and State.Auto[Name]
            and State.Generation[Name] == ThisGeneration do

            local Success, ErrorMessage = pcall(Action)
            if not Success then
                notify(
                    "Automation stopped",
                    tostring(Name) .. ": " .. tostring(ErrorMessage),
                    5,
                    "LoopError_" .. tostring(Name),
                    4
                )
                State.Auto[Name] = false
                break
            end

            local Delay = tonumber(State[DelayField]) or 1
            task.wait(math.max(Delay, 0.1))
        end
    end)
end

local Window = Rayfield:CreateWindow({
    Name = "Fishing Tycoon Utility",
    Icon = 0,
    LoadingTitle = "Fishing Tycoon Utility",
    LoadingSubtitle = "Rayfield UI",
    ShowText = "Fish Hub",
    Theme = "Default",
    ToggleUIKeybind = "K",

    DisableRayfieldPrompts = false,
    DisableBuildWarnings = false,

    ConfigurationSaving = {
        Enabled = true,
        FolderName = "FishingTycoonHub",
        FileName = "Settings",
    },

    Discord = {
        Enabled = false,
        Invite = "",
        RememberJoins = true,
    },

    KeySystem = false,
})

local AutomationTab = Window:CreateTab("Automation", 4483362458)
local MonitorTab = Window:CreateTab("Monitor", 4483362458)
local SettingsTab = Window:CreateTab("Settings", 4483362458)

AutomationTab:CreateSection("Manual actions")

AutomationTab:CreateButton({
    Name = "Give Fish Once",
    Callback = function()
        if fireRemote("GiveFish") then
            notify("Give Fish", "GiveFishEvent was sent once.", 3, "GiveFishManual", 0.5)
        end
    end,
})

AutomationTab:CreateButton({
    Name = "Normal Rebirth Once",
    Callback = function()
        if fireRemote("Rebirth", "NormalRebirth") then
            notify("Rebirth", "NormalRebirth request was sent.", 3, "RebirthManual", 0.5)
        end
    end,
})

local LockPlayerToggle
LockPlayerToggle = AutomationTab:CreateToggle({
    Name = "Lock Player",
    CurrentValue = false,
    Flag = "ManualLockPlayer",
    Callback = function(Value)
        State.ManualLocked = Value == true
        syncLockState()
    end,
})

AutomationTab:CreateButton({
    Name = "Set Tutorial Step to 4",
    Callback = function()
        if fireRemote("Tutorial", 4) then
            notify("Tutorial", "UpdateTutorialEvent(4) was sent.", 3, "Tutorial4", 1)
        end
    end,
})

AutomationTab:CreateSection("Auto Give Fish")

AutomationTab:CreateSlider({
    Name = "Give Fish Delay",
    Range = {0.2, 5},
    Increment = 0.05,
    Suffix = " sec",
    CurrentValue = State.GiveFishDelay,
    Flag = "GiveFishDelay",
    Callback = function(Value)
        State.GiveFishDelay = math.max(tonumber(Value) or 0.75, 0.2)
    end,
})

AutomationTab:CreateToggle({
    Name = "Lock While Auto Give Fish",
    CurrentValue = false,
    Flag = "LockWhileAutoFish",
    Callback = function(Value)
        State.LockWhileAutoFish = Value == true
        syncLockState()
    end,
})

local AutoFishToggle
AutoFishToggle = AutomationTab:CreateToggle({
    Name = "Auto Give Fish",
    CurrentValue = false,
    Flag = "AutoGiveFish",
    Callback = function(Value)
        local Enabled = Value == true

        setAutomation("GiveFish", Enabled, "GiveFishDelay", function()
            fireRemote("GiveFish")
        end)

        syncLockState()
    end,
})

AutomationTab:CreateSection("Auto Rebirth")

AutomationTab:CreateSlider({
    Name = "Rebirth Delay",
    Range = {0.5, 15},
    Increment = 0.1,
    Suffix = " sec",
    CurrentValue = State.RebirthDelay,
    Flag = "RebirthDelay",
    Callback = function(Value)
        State.RebirthDelay = math.max(tonumber(Value) or 2, 0.5)
    end,
})

local AutoRebirthToggle
AutoRebirthToggle = AutomationTab:CreateToggle({
    Name = "Auto Normal Rebirth",
    CurrentValue = false,
    Flag = "AutoNormalRebirth",
    Callback = function(Value)
        setAutomation("Rebirth", Value == true, "RebirthDelay", function()
            fireRemote("Rebirth", "NormalRebirth")
        end)
    end,
})

AutomationTab:CreateButton({
    Name = "Stop All Automation",
    Callback = function()
        if AutoFishToggle then
            AutoFishToggle:Set(false)
        end

        if AutoRebirthToggle then
            AutoRebirthToggle:Set(false)
        end

        if LockPlayerToggle then
            LockPlayerToggle:Set(false)
        end

        notify("Automation", "All automation was stopped.", 3, "StopAll", 0.5)
    end,
})

MonitorTab:CreateSection("Live status")

local LatestEventParagraph = MonitorTab:CreateParagraph({
    Title = "Latest event",
    Content = "Waiting for a server response...",
})

local CounterParagraph = MonitorTab:CreateParagraph({
    Title = "Session counters",
    Content = "Fish rewards: 0\nSuccessful rebirths: 0\nSuccessful upgrades: 0\nSell responses: 0",
})

local RemoteStatusParagraph = MonitorTab:CreateParagraph({
    Title = "Remote status",
    Content = "Not scanned yet.",
})

local function setParagraph(Paragraph, Title, Content)
    if not State.Alive or not Paragraph then
        return
    end

    pcall(function()
        Paragraph:Set({
            Title = tostring(Title),
            Content = tostring(Content),
        })
    end)
end

local function updateCounters()
    setParagraph(
        CounterParagraph,
        "Session counters",
        string.format(
            "Fish rewards: %d\nSuccessful rebirths: %d\nSuccessful upgrades: %d\nSell responses: %d\nLatest fish: %s\nWeather: %s",
            State.Counters.FishRewards,
            State.Counters.RebirthSuccess,
            State.Counters.UpgradeSuccess,
            State.Counters.SoldEvents,
            tostring(State.LastFish),
            tostring(State.LastWeather)
        )
    )
end

local function updateLatest(Title, Content, DedupeWindow)
    local Signature = tostring(Title) .. "|" .. tostring(Content)
    local Now = os.clock()

    if State.LastEventSignature == Signature
        and Now - State.LastEventTime < (DedupeWindow or 0) then
        return
    end

    State.LastEventSignature = Signature
    State.LastEventTime = Now
    setParagraph(LatestEventParagraph, Title, Content)
end

local function refreshRemoteStatus()
    State.MissingWarned = {}

    local OrderedKeys = {
        "LockPlayer",
        "GiveFish",
        "Tutorial",
        "Rebirth",
        "FishReward",
        "SellFish",
        "DailyReward",
        "Weather",
        "RodUpgrade",
        "BuyRod",
        "UpgradeVFX",
        "CoinVFX",
    }

    local Lines = {}

    for _, Key in ipairs(OrderedKeys) do
        local Exists = getRemote(Key) ~= nil
        table.insert(
            Lines,
            string.format(
                "%s %s",
                Exists and "[OK]" or "[MISSING]",
                pathToString(REMOTE_PATHS[Key])
            )
        )
    end

    setParagraph(RemoteStatusParagraph, "Remote status", table.concat(Lines, "\n"))
end

MonitorTab:CreateToggle({
    Name = "Notify Fish Rewards",
    CurrentValue = true,
    Flag = "NotifyFishRewards",
    Callback = function(Value)
        State.NotifyFish = Value == true
    end,
})

MonitorTab:CreateToggle({
    Name = "Notify Weather Changes",
    CurrentValue = true,
    Flag = "NotifyWeatherChanges",
    Callback = function(Value)
        State.NotifyWeather = Value == true
    end,
})

MonitorTab:CreateToggle({
    Name = "Notify Rebirth / Upgrade Results",
    CurrentValue = true,
    Flag = "NotifyActionResults",
    Callback = function(Value)
        State.NotifyActions = Value == true
    end,
})

MonitorTab:CreateButton({
    Name = "Refresh Remote Status",
    Callback = refreshRemoteStatus,
})

local function connectListener(Key, Callback)
    local Remote = getRemote(Key)
    if not Remote then
        return false
    end

    local Connection = Remote.OnClientEvent:Connect(function(...)
        if not State.Alive then
            return
        end

        local Success, ErrorMessage = pcall(Callback, ...)
        if not Success then
            warn("[Fishing Hub] Listener error for " .. tostring(Key) .. ": " .. tostring(ErrorMessage))
        end
    end)

    table.insert(State.Connections, Connection)
    return true
end

connectListener("FishReward", function(FishName, Mutation)
    State.Counters.FishRewards = State.Counters.FishRewards + 1

    local FishText = FishName ~= nil and tostring(FishName) or "nil"
    local MutationText = Mutation ~= nil and tostring(Mutation) or "nil"
    State.LastFish = FishText .. " / " .. MutationText

    updateLatest("Fish reward", "Fish: " .. FishText .. "\nMutation: " .. MutationText)
    updateCounters()

    if State.NotifyFish then
        notify(
            "Fish reward",
            FishText .. " | " .. MutationText,
            4,
            nil,
            0
        )
    end
end)

connectListener("Weather", function(WeatherName, Timestamp)
    local NewWeather = WeatherName ~= nil and tostring(WeatherName) or "nil"
    local Changed = NewWeather ~= State.LastWeather

    State.LastWeather = NewWeather
    updateLatest(
        "Weather update",
        "Weather: " .. NewWeather .. "\nTimestamp: " .. tostring(Timestamp),
        1
    )
    updateCounters()

    if Changed and State.NotifyWeather then
        notify("Weather changed", NewWeather, 4, "Weather_" .. NewWeather, 1)
    end
end)

connectListener("Rebirth", function(Success)
    if Success == true then
        State.Counters.RebirthSuccess = State.Counters.RebirthSuccess + 1
    end

    updateLatest("Rebirth result", "Success: " .. tostring(Success), 0.25)
    updateCounters()

    if State.NotifyActions then
        notify(
            "Rebirth result",
            Success == true and "Rebirth succeeded." or "Rebirth was rejected.",
            3,
            "RebirthResult_" .. tostring(Success),
            0.75
        )
    end
end)

connectListener("RodUpgrade", function(Success, Message)
    if Success == true then
        State.Counters.UpgradeSuccess = State.Counters.UpgradeSuccess + 1
    end

    updateLatest(
        "Rod upgrade result",
        "Success: " .. tostring(Success) .. "\nMessage: " .. tostring(Message),
        0.25
    )
    updateCounters()

    if State.NotifyActions then
        notify(
            "Rod upgrade",
            tostring(Message),
            3,
            "RodUpgrade_" .. tostring(Success) .. "_" .. tostring(Message),
            0.75
        )
    end
end)

connectListener("BuyRod", function(Success)
    updateLatest("Buy rod result", "Success: " .. tostring(Success), 0.5)
end)

connectListener("SellFish", function(Amount)
    State.Counters.SoldEvents = State.Counters.SoldEvents + 1
    updateLatest("Sell fish result", "Amount: " .. tostring(Amount), 0.25)
    updateCounters()
end)

connectListener("DailyReward", function(Message)
    -- The capture showed this event firing rapidly, so identical messages are deduplicated.
    updateLatest("Daily reward", tostring(Message), 2)
end)

connectListener("UpgradeVFX", function(_, UpgradeName, Enabled)
    updateLatest(
        "Tycoon upgrade VFX",
        "Upgrade: " .. tostring(UpgradeName) .. "\nEnabled: " .. tostring(Enabled),
        0.5
    )
end)

connectListener("CoinVFX", function(ClaimPad)
    updateLatest("Coin VFX", "Pad: " .. tostring(ClaimPad), 0.25)
end)

SettingsTab:CreateSection("Information")

SettingsTab:CreateParagraph({
    Title = "What this build uses",
    Content = "Automation only uses the four client-to-server calls confirmed in the supplied logger capture. Rod upgrade, sell, reward, weather and VFX remotes are listeners because the capture only showed them arriving from the server.",
})

SettingsTab:CreateParagraph({
    Title = "Controls",
    Content = "Press K to hide or show the UI. Delays and toggles are saved by Rayfield. Very small delays may be rejected or rate-limited by the server.",
})

SettingsTab:CreateButton({
    Name = "Rescan All Remotes",
    Callback = function()
        refreshRemoteStatus()
        notify("Remote scan", "Remote availability was refreshed.", 3, "RemoteScan", 0.5)
    end,
})

local function cleanup()
    if not State.Alive then
        return
    end

    State.Alive = false
    State.Auto.GiveFish = false
    State.Auto.Rebirth = false
    State.Generation.GiveFish = State.Generation.GiveFish + 1
    State.Generation.Rebirth = State.Generation.Rebirth + 1

    -- Try to release the local player if this script locked them.
    local LockRemote = getRemote("LockPlayer")
    if LockRemote then
        pcall(function()
            LockRemote:FireServer(false)
        end)
    end

    for _, Connection in ipairs(State.Connections) do
        pcall(function()
            Connection:Disconnect()
        end)
    end

    State.Connections = {}

    pcall(function()
        Rayfield:Destroy()
    end)

    if Environment[HUB_KEY] == State then
        Environment[HUB_KEY] = nil
    end
end

State.Cleanup = cleanup

SettingsTab:CreateButton({
    Name = "Unload Script",
    Callback = cleanup,
})

refreshRemoteStatus()
updateCounters()

Rayfield:LoadConfiguration()

notify(
    "Fishing Tycoon Utility",
    "Loaded. Press K to hide or show the UI.",
    5,
    "Loaded",
    1
)
