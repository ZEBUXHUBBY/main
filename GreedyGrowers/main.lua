-- Greedy Growers Adaptive Profit Controller
-- Rayfield UI + config-driven strategy shell.
-- Intended for authorized Roblox Studio/test environments.
-- No live-game remote exploitation is implemented here.

local Greedy = {}

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local DEFAULTS = {
    Enabled = false,
    AutoOptimize = true,
    AutoSell = true,
    AutoHarvest = true,
    CashReserve = 0,
    SellThreshold = 1,
    LightningSafetyMargin = 0.35,
    MinConfidence = 0.55,
    Debug = false,

    -- Learned/runtime data. Nothing here assumes a fixed seed/tree roster.
    SeedStats = {},
    TreeStats = {},
    MutationMultipliers = {},
    FertilizerStats = {},
    Lightning = {
        samples = {},
        estimatedInterval = nil,
        estimatedJitter = nil,
        lastObservedAt = nil,
    },
}

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = deepCopy(x) end
    return o
end

local function merge(dst, src)
    for k, v in pairs(src or {}) do
        if type(v) == "table" and type(dst[k]) == "table" then
            merge(dst[k], v)
        else
            dst[k] = deepCopy(v)
        end
    end
    return dst
end

local Config = deepCopy(DEFAULTS)

local Adapter = nil
local Runtime = {
    State = "IDLE",
    ActiveTree = nil,
    LastDecision = nil,
    MoneyEarned = 0,
    SellCount = 0,
    HarvestCount = 0,
    LightningAvoids = 0,
    Connections = {},
}

local function log(...)
    if Config.Debug then
        print("[GreedyGrowers]", ...)
    end
end

local function safeCall(fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
        warn("[GreedyGrowers]", a)
        return nil
    end
    return a, b, c
end

local function median(list)
    if #list == 0 then return nil end
    local copy = table.clone(list)
    table.sort(copy)
    local n = #copy
    if n % 2 == 1 then return copy[(n + 1) / 2] end
    return (copy[n / 2] + copy[n / 2 + 1]) / 2
end

local function estimateLightning()
    local samples = Config.Lightning.samples
    if #samples < 2 then
        Config.Lightning.estimatedInterval = nil
        Config.Lightning.estimatedJitter = nil
        return
    end

    local gaps = {}
    for i = 2, #samples do
        gaps[#gaps + 1] = samples[i] - samples[i - 1]
    end

    local center = median(gaps)
    Config.Lightning.estimatedInterval = center

    local deviations = {}
    for _, gap in ipairs(gaps) do
        deviations[#deviations + 1] = math.abs(gap - center)
    end
    Config.Lightning.estimatedJitter = median(deviations) or 0
end

local function observeLightning(timestamp)
    timestamp = timestamp or os.clock()
    local samples = Config.Lightning.samples
    samples[#samples + 1] = timestamp
    if #samples > 30 then table.remove(samples, 1) end
    Config.Lightning.lastObservedAt = timestamp
    estimateLightning()
    log("Lightning observed", timestamp, Config.Lightning.estimatedInterval)
end

local function timeUntilLightning()
    local L = Config.Lightning
    if not L.lastObservedAt or not L.estimatedInterval then return math.huge, 0 end

    local jitter = L.estimatedJitter or 0
    local predicted = L.lastObservedAt + L.estimatedInterval
    local safeAt = predicted - jitter - Config.LightningSafetyMargin
    return safeAt - os.clock(), math.max(0, 1 - (jitter / math.max(L.estimatedInterval, 0.001)))
end

local function getTreeStats(tree)
    if not tree then return nil end
    local key = tree.key or tree.seedKey or tree.name
    if not key then return nil end
    return Config.TreeStats[key] or Config.SeedStats[key], key
end

local function expectedTreeValue(tree)
    local stats = getTreeStats(tree)
    if not stats then return 0, 0 end

    local base = tonumber(stats.expectedValue or stats.sellValue or stats.value) or 0
    local yield = tonumber(stats.expectedYield or stats.yield) or 1
    local mutation = 1

    local mutationKey = tree.mutation or stats.mutation
    if mutationKey then
        mutation = tonumber(Config.MutationMultipliers[mutationKey]) or tonumber(stats.mutationMultiplier) or 1
    end

    local confidence = tonumber(stats.confidence) or 0.5
    return base * yield * mutation, confidence
end

local function remainingGrowthTime(tree)
    if not tree then return math.huge end
    if tree.ready == true then return 0 end
    if tree.readyAt then return math.max(0, tree.readyAt - os.clock()) end

    local stats = getTreeStats(tree)
    if stats then
        local grow = tonumber(stats.growTime or stats.growthTime)
        local plantedAt = tonumber(tree.plantedAt)
        if grow and plantedAt then return math.max(0, plantedAt + grow - os.clock()) end
    end

    return math.huge
end

local function scoreTree(tree)
    local value, confidence = expectedTreeValue(tree)
    if confidence < Config.MinConfidence then return -math.huge, "low-confidence" end

    local remaining = remainingGrowthTime(tree)
    local untilLightning = timeUntilLightning()

    if remaining == math.huge then
        return value * confidence, "unknown-growth"
    end

    if untilLightning ~= math.huge and remaining >= untilLightning then
        -- It is unlikely to mature before the safety window.
        return -math.huge, "lightning-risk"
    end

    local minutes = math.max(remaining / 60, 1 / 60)
    return (value / minutes) * confidence, "profit-rate"
end

local function chooseBestTree(trees)
    local best, bestScore, reason = nil, -math.huge, nil
    for _, tree in ipairs(trees or {}) do
        local score, why = scoreTree(tree)
        if score > bestScore then
            best, bestScore, reason = tree, score, why
        end
    end
    return best, bestScore, reason
end

local function shouldEmergencyHarvest(tree)
    if not tree then return false end
    local untilLightning = timeUntilLightning()
    if untilLightning == math.huge then return false end

    local remaining = remainingGrowthTime(tree)
    local value, confidence = expectedTreeValue(tree)

    return confidence >= Config.MinConfidence
        and value > 0
        and remaining <= 0
        and untilLightning <= math.max(0.1, Config.LightningSafetyMargin)
end

local function disconnectAll()
    for _, c in ipairs(Runtime.Connections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(Runtime.Connections)
end

local function bindSignal(signal, fn)
    if signal and typeof(signal) == "RBXScriptSignal" then
        Runtime.Connections[#Runtime.Connections + 1] = signal:Connect(fn)
    elseif signal and type(signal.Connect) == "function" then
        Runtime.Connections[#Runtime.Connections + 1] = signal:Connect(fn)
    end
end

local function tickController()
    if not Config.Enabled or not Adapter then return end

    local trees = safeCall(Adapter.GetTrees, Adapter) or {}

    if Config.AutoHarvest then
        for _, tree in ipairs(trees) do
            if shouldEmergencyHarvest(tree) then
                local ok, amount = safeCall(Adapter.HarvestTree, Adapter, tree)
                if ok then
                    Runtime.HarvestCount += 1
                    Runtime.LightningAvoids += 1
                    Runtime.MoneyEarned += tonumber(amount) or 0
                end
            end
        end
    end

    if Config.AutoOptimize then
        local best, score, reason = chooseBestTree(trees)
        Runtime.LastDecision = {
            tree = best and (best.key or best.seedKey or best.name) or nil,
            score = score,
            reason = reason,
            at = os.clock(),
        }
        Runtime.ActiveTree = best
    end

    if Config.AutoSell and Adapter.GetInventoryCount and Adapter.SellAll then
        local count = tonumber(safeCall(Adapter.GetInventoryCount, Adapter)) or 0
        if count >= Config.SellThreshold then
            local ok, amount = safeCall(Adapter.SellAll, Adapter)
            if ok then
                Runtime.SellCount += 1
                Runtime.MoneyEarned += tonumber(amount) or 0
            end
        end
    end
end

local function startLoop()
    task.spawn(function()
        while true do
            if Config.Enabled then tickController() end
            task.wait(0.2)
        end
    end)
end

function Greedy.AttachAdapter(adapter)
    Adapter = adapter
    disconnectAll()

    if not Adapter then return end

    bindSignal(Adapter.LightningObserved, function(ts)
        observeLightning(ts)
    end)

    bindSignal(Adapter.TreeUpdated, function(tree)
        Runtime.ActiveTree = tree
    end)

    bindSignal(Adapter.SaleCompleted, function(amount)
        Runtime.MoneyEarned += tonumber(amount) or 0
    end)
end

function Greedy.SetConfig(partial)
    merge(Config, partial or {})
    estimateLightning()
end

function Greedy.GetConfig()
    return deepCopy(Config)
end

function Greedy.GetRuntime()
    return deepCopy(Runtime)
end

function Greedy.ObserveLightning(timestamp)
    observeLightning(timestamp)
end

function Greedy.ScoreTree(tree)
    return scoreTree(tree)
end

function Greedy.ChooseBestTree(trees)
    return chooseBestTree(trees)
end

-- Optional executor persistence. Fails closed if filesystem APIs are unavailable.
local CONFIG_FILE = "GreedyGrowers/config.json"

function Greedy.SaveConfig()
    if not (writefile and makefolder) then return false end
    pcall(makefolder, "GreedyGrowers")
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, Config)
    if not ok then return false end
    return pcall(writefile, CONFIG_FILE, encoded)
end

function Greedy.LoadConfig()
    if not (isfile and readfile) or not isfile(CONFIG_FILE) then return false end
    local ok, raw = pcall(readfile, CONFIG_FILE)
    if not ok then return false end
    local decodedOk, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
    if not decodedOk or type(decoded) ~= "table" then return false end
    merge(Config, decoded)
    estimateLightning()
    return true
end

function Greedy.CreateUI()
    local ok, Rayfield = pcall(function()
        return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
    end)
    if not ok or not Rayfield then
        warn("[GreedyGrowers] Rayfield failed to load")
        return
    end

    local Window = Rayfield:CreateWindow({
        Name = "Greedy Growers | Adaptive Profit",
        LoadingTitle = "Greedy Growers",
        LoadingSubtitle = "Adaptive money optimizer",
        ConfigurationSaving = { Enabled = false },
        Discord = { Enabled = false },
        KeySystem = false,
    })

    local Main = Window:CreateTab("Main", 4483362458)
    local Strategy = Window:CreateTab("Strategy", 4483362458)
    local Data = Window:CreateTab("Learning", 4483362458)

    local StateLabel = Main:CreateLabel("State: " .. Runtime.State)
    local ProfitLabel = Main:CreateLabel("Tracked money: $0")
    local LightningLabel = Main:CreateLabel("Lightning: learning")

    Main:CreateToggle({
        Name = "Enable optimizer",
        CurrentValue = Config.Enabled,
        Callback = function(v) Config.Enabled = v end,
    })

    Main:CreateToggle({
        Name = "Auto choose highest $/min tree",
        CurrentValue = Config.AutoOptimize,
        Callback = function(v) Config.AutoOptimize = v end,
    })

    Main:CreateToggle({
        Name = "Harvest ready tree before lightning window",
        CurrentValue = Config.AutoHarvest,
        Callback = function(v) Config.AutoHarvest = v end,
    })

    Main:CreateToggle({
        Name = "Auto sell inventory",
        CurrentValue = Config.AutoSell,
        Callback = function(v) Config.AutoSell = v end,
    })

    Strategy:CreateSlider({
        Name = "Lightning safety margin (seconds)",
        Range = {0.05, 3.0},
        Increment = 0.05,
        Suffix = "s",
        CurrentValue = Config.LightningSafetyMargin,
        Callback = function(v) Config.LightningSafetyMargin = v end,
    })

    Strategy:CreateSlider({
        Name = "Minimum data confidence",
        Range = {0.1, 1.0},
        Increment = 0.05,
        CurrentValue = Config.MinConfidence,
        Callback = function(v) Config.MinConfidence = v end,
    })

    Strategy:CreateInput({
        Name = "Cash reserve",
        PlaceholderText = "0",
        RemoveTextAfterFocusLost = false,
        Callback = function(text)
            Config.CashReserve = tonumber(text) or Config.CashReserve
        end,
    })

    Strategy:CreateInput({
        Name = "Sell inventory at",
        PlaceholderText = tostring(Config.SellThreshold),
        RemoveTextAfterFocusLost = false,
        Callback = function(text)
            Config.SellThreshold = math.max(1, tonumber(text) or Config.SellThreshold)
        end,
    })

    Data:CreateButton({
        Name = "Record lightning now",
        Callback = function()
            observeLightning(os.clock())
        end,
    })

    Data:CreateButton({
        Name = "Save learned/config data",
        Callback = function()
            local saved = Greedy.SaveConfig()
            Rayfield:Notify({
                Title = "Greedy Growers",
                Content = saved and "Config saved" or "Save API unavailable",
                Duration = 3,
            })
        end,
    })

    Data:CreateButton({
        Name = "Load learned/config data",
        Callback = function()
            local loaded = Greedy.LoadConfig()
            Rayfield:Notify({
                Title = "Greedy Growers",
                Content = loaded and "Config loaded" or "No config loaded",
                Duration = 3,
            })
        end,
    })

    task.spawn(function()
        while task.wait(0.5) do
            pcall(function()
                StateLabel:Set("State: " .. tostring(Runtime.State))
                ProfitLabel:Set("Tracked money: $" .. tostring(math.floor(Runtime.MoneyEarned)))
                local L = Config.Lightning
                if L.estimatedInterval then
                    local left, confidence = timeUntilLightning()
                    LightningLabel:Set(string.format("Lightning: %.2fs | confidence %.0f%%", left, confidence * 100))
                else
                    LightningLabel:Set("Lightning: learning (need 2+ observations)")
                end
            end)
        end
    end)
end

Greedy.LoadConfig()
startLoop()

return Greedy
