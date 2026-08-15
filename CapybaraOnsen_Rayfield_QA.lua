-- Capybara Onsen - Rayfield QA / Automation Harness
-- Built from the supplied world snapshot + remote capture.
-- Scope: client-observable automation + non-destructive bug diagnostics.
-- It intentionally DOES NOT fuzz unknown remotes, spoof purchases, or invoke DevPanelAction.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local DropSpawned = Remotes:WaitForChild("DropSpawned")
local DropPickup = Remotes:WaitForChild("DropPickup")
local CarryUpdated = Remotes:WaitForChild("CarryUpdated")
local DataUpdated = Remotes:WaitForChild("DataUpdated")
local GetData = Remotes:WaitForChild("GetData")
local NotifyRemote = Remotes:FindFirstChild("Notify")

-- Rayfield stable API (Sirius)
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local Window = Rayfield:CreateWindow({
    Name = "Capybara Onsen | QA Hub",
    LoadingTitle = "Capybara Onsen QA",
    LoadingSubtitle = "Observed-remotes only",
    Theme = "Default",
    ToggleUIKeybind = "K",
    DisableRayfieldPrompts = false,
    DisableBuildWarnings = false,
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "CapybaraOnsenQA",
        FileName = "settings"
    },
    Discord = { Enabled = false },
    KeySystem = false
})

local AutoTab = Window:CreateTab("Automation")
local StateTab = Window:CreateTab("Live State")
local BugTab = Window:CreateTab("Bug Finder")
local LogTab = Window:CreateTab("Logs")

local state = {
    autoPickup = false,
    autoRefresh = true,
    refreshEvery = 2.0,
    distanceWarn = 20,
    notifyFindings = true,
    lastRefresh = 0,
    data = nil,
    carry = nil,
    carryTier = nil,
    pending = {},      -- [dropId] = metadata
    seen = {},         -- [dropId] = spawn count
    pickupSent = {},   -- [dropId] = timestamp
    findings = {},
    logs = {},
    pathTypes = {},
    acceptedFar = 0,
    duplicatedIds = 0,
    plotMismatch = 0,
}

local function now()
    return os.clock()
end

local function clampString(v, n)
    local s = tostring(v)
    if #s > n then return s:sub(1, n - 3) .. "..." end
    return s
end

local function pushLog(kind, text)
    local row = string.format("[%s] %s", kind, text)
    table.insert(state.logs, 1, row)
    if #state.logs > 60 then
        table.remove(state.logs)
    end
end

local function toast(title, content, duration)
    Rayfield:Notify({
        Title = title,
        Content = content,
        Duration = duration or 4
    })
end

local function addFinding(severity, key, text)
    local id = severity .. ":" .. key
    if state.findings[id] then return end
    state.findings[id] = {
        severity = severity,
        text = text,
        at = os.time()
    }
    pushLog("FINDING", severity .. " | " .. text)
    if state.notifyFindings then
        toast("Bug Finder: " .. severity, text, 6)
    end
end

local function finiteNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function getRoot()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getPlotName()
    local p = LP:GetAttribute("Plot")
    if p ~= nil then return tostring(p) end
    return "?"
end

local function getPlotModel()
    local tycoon = workspace:FindFirstChild("Tycoon")
    local tycoons = tycoon and tycoon:FindFirstChild("Tycoons")
    if not tycoons then return nil end
    return tycoons:FindFirstChild(getPlotName())
end

local function slotBelongsToLocalPlot(slot)
    local plot = getPlotName()
    if plot == "?" or typeof(slot) ~= "Instance" then
        return nil
    end
    local p = slot
    while p and p ~= workspace do
        if p.Parent and p.Parent.Name == "Tycoons" then
            return p.Name == plot
        end
        p = p.Parent
    end
    return nil
end

local function safeGetData()
    local ok, result = pcall(function()
        return GetData:InvokeServer()
    end)
    if not ok then
        pushLog("ERROR", "GetData failed: " .. clampString(result, 120))
        return nil
    end
    if type(result) ~= "table" then
        addFinding("MEDIUM", "getdata_type", "GetData returned " .. typeof(result) .. " instead of table")
        return nil
    end
    state.data = result
    return result
end

local function deepGet(root, ...)
    local x = root
    for i = 1, select("#", ...) do
        if type(x) ~= "table" then return nil end
        x = x[select(i, ...)]
    end
    return x
end

local function sanityCheckData(d)
    if type(d) ~= "table" then return end

    local cash = d.Cash
    local carry = deepGet(d, "Tycoon", "Carry")
    local pendingCash = deepGet(d, "Tycoon", "Shop", "PendingCash")
    local pendingDrop = deepGet(d, "Tycoon", "Shop", "PendingDrop")
    local buyTier = deepGet(d, "Tycoon", "Shop", "BuyTier")
    local upgradeCount = deepGet(d, "Tycoon", "Shop", "UpgradeCount")
    local moneyMult = deepGet(d, "Multipliers", "Money")

    local numbers = {
        Cash = cash,
        Carry = carry,
        PendingCash = pendingCash,
        PendingDrop = pendingDrop,
        BuyTier = buyTier,
        UpgradeCount = upgradeCount,
        MoneyMultiplier = moneyMult,
    }

    for name, value in pairs(numbers) do
        if value ~= nil and not finiteNumber(value) then
            addFinding("HIGH", "nonfinite_" .. name, name .. " became a non-finite number: " .. tostring(value))
        end
    end

    if finiteNumber(cash) and cash < 0 then
        addFinding("HIGH", "negative_cash", "Cash became negative: " .. cash)
    end
    if finiteNumber(carry) and carry < 0 then
        addFinding("HIGH", "negative_carry", "Tycoon.Carry became negative: " .. carry)
    end
    if finiteNumber(pendingCash) and pendingCash < 0 then
        addFinding("HIGH", "negative_pendingcash", "Tycoon.Shop.PendingCash became negative: " .. pendingCash)
    end
    if finiteNumber(pendingDrop) and pendingDrop < 0 then
        addFinding("HIGH", "negative_pendingdrop", "Tycoon.Shop.PendingDrop became negative: " .. pendingDrop)
    end
    if finiteNumber(buyTier) and buyTier < 1 then
        addFinding("MEDIUM", "invalid_buytier", "Tycoon.Shop.BuyTier is below 1: " .. buyTier)
    end
end

local function sendObservedPickup(id, reason)
    local meta = state.pending[id]
    if not meta then
        pushLog("BLOCK", "Refused unobserved DropPickup(" .. tostring(id) .. ")")
        return false
    end

    -- Scope guard: never automatically act on a drop that is known to belong to another plot.
    if meta.ownPlot == false then
        state.plotMismatch += 1
        addFinding("HIGH", "crossplot_spawn", "Server delivered a DropSpawned event referencing another plot")
        return false
    end

    if state.pickupSent[id] then
        pushLog("BLOCK", "Refused duplicate/replay pickup for id " .. tostring(id))
        return false
    end

    state.pickupSent[id] = now()
    pushLog("OUT", string.format("DropPickup(%s) [%s]", tostring(id), reason or "manual"))
    DropPickup:FireServer(id)
    return true
end

-- ===== UI =====

AutoTab:CreateSection("Observed automation")
AutoTab:CreateToggle({
    Name = "Auto Pickup observed drops",
    CurrentValue = false,
    Flag = "AutoPickup",
    Callback = function(v)
        state.autoPickup = v
        pushLog("UI", "Auto Pickup = " .. tostring(v))
    end
})

AutoTab:CreateToggle({
    Name = "Auto refresh GetData",
    CurrentValue = true,
    Flag = "AutoRefresh",
    Callback = function(v)
        state.autoRefresh = v
    end
})

AutoTab:CreateSlider({
    Name = "Data refresh seconds",
    Range = {1, 10},
    Increment = 0.5,
    Suffix = "s",
    CurrentValue = 2,
    Flag = "RefreshEvery",
    Callback = function(v)
        state.refreshEvery = v
    end
})

AutoTab:CreateButton({
    Name = "Refresh data now",
    Callback = function()
        local d = safeGetData()
        if d then sanityCheckData(d) end
        toast("State", d and "GetData refreshed" or "GetData failed")
    end
})

AutoTab:CreateParagraph({
    Title = "Intentionally not automated",
    Content = "Cashier / Deposit / Upgrade / TierUpgrader / purchases are not fired here because the capture did not establish safe outgoing signatures for those actions. Unknown remotes are not fuzzed."
})

StateTab:CreateSection("Server state")
local StateParagraph = StateTab:CreateParagraph({
    Title = "Live",
    Content = "Waiting for GetData..."
})

local function renderState()
    local d = state.data
    local cash = d and d.Cash or "?"
    local total = d and d.TotalEarned or "?"
    local carry = state.carry
    if carry == nil and d then carry = deepGet(d, "Tycoon", "Carry") end
    local pendingCash = d and deepGet(d, "Tycoon", "Shop", "PendingCash") or "?"
    local pendingDrop = d and deepGet(d, "Tycoon", "Shop", "PendingDrop") or "?"
    local buyTier = d and deepGet(d, "Tycoon", "Shop", "BuyTier") or "?"
    local upgrades = d and deepGet(d, "Tycoon", "Shop", "UpgradeCount") or "?"

    StateParagraph:Set({
        Title = "Live | Plot " .. getPlotName(),
        Content = table.concat({
            "Cash: " .. tostring(cash),
            "TotalEarned: " .. tostring(total),
            "Carry: " .. tostring(carry) .. " | Tier: " .. tostring(state.carryTier),
            "PendingCash: " .. tostring(pendingCash),
            "PendingDrop: " .. tostring(pendingDrop),
            "BuyTier: " .. tostring(buyTier),
            "UpgradeCount: " .. tostring(upgrades),
            "Observed active drops: " .. tostring((function() local n=0 for _ in pairs(state.pending) do n+=1 end return n end)()),
        }, "\n")
    })
end

BugTab:CreateSection("Passive / non-destructive checks")
BugTab:CreateSlider({
    Name = "Far-pickup warning distance",
    Range = {5, 100},
    Increment = 1,
    Suffix = " studs",
    CurrentValue = 20,
    Flag = "DistanceWarn",
    Callback = function(v)
        state.distanceWarn = v
    end
})

BugTab:CreateToggle({
    Name = "Notify new findings",
    CurrentValue = true,
    Flag = "NotifyFindings",
    Callback = function(v)
        state.notifyFindings = v
    end
})

local BugParagraph = BugTab:CreateParagraph({
    Title = "Findings",
    Content = "No findings yet."
})

local function renderFindings()
    local rows = {}
    for _, f in pairs(state.findings) do
        table.insert(rows, string.format("[%s] %s", f.severity, f.text))
    end
    table.sort(rows)
    if #rows == 0 then rows[1] = "No findings yet." end
    if #rows > 10 then
        while #rows > 10 do table.remove(rows) end
    end
    BugParagraph:Set({
        Title = string.format("Findings | far accepted: %d | duplicate IDs: %d | plot mismatch: %d", state.acceptedFar, state.duplicatedIds, state.plotMismatch),
        Content = table.concat(rows, "\n")
    })
end

BugTab:CreateButton({
    Name = "Run state sanity scan",
    Callback = function()
        local d = safeGetData()
        if d then sanityCheckData(d) end
        renderFindings()
        toast("Bug Finder", "State sanity scan complete")
    end
})

BugTab:CreateParagraph({
    Title = "What this scanner can prove",
    Content = "It can flag duplicate server IDs, cross-plot references, malformed state, and a pickup that the server appears to accept while your character is far away. It does not send forged IDs or replay requests, so authorization/replay weaknesses remain candidates until tested in an authorized QA environment."
})

LogTab:CreateSection("Recent events")
local LogParagraph = LogTab:CreateParagraph({
    Title = "Event log",
    Content = "Waiting..."
})

LogTab:CreateButton({
    Name = "Clear logs",
    Callback = function()
        table.clear(state.logs)
    end
})

local function renderLogs()
    local rows = {}
    for i = 1, math.min(#state.logs, 25) do
        rows[i] = state.logs[i]
    end
    if #rows == 0 then rows[1] = "No events." end
    LogParagraph:Set({ Title = "Event log", Content = table.concat(rows, "\n") })
end

-- ===== EVENT MONITORS =====

DropSpawned.OnClientEvent:Connect(function(id, tier, position, unit, slot)
    if type(id) ~= "number" then
        addFinding("HIGH", "drop_id_type", "DropSpawned delivered non-number ID: " .. typeof(id))
        return
    end

    state.seen[id] = (state.seen[id] or 0) + 1
    if state.seen[id] > 1 then
        state.duplicatedIds += 1
        addFinding("HIGH", "duplicate_drop_" .. tostring(id), "DropSpawned reused ID " .. tostring(id))
    end

    local ownPlot = slotBelongsToLocalPlot(slot)
    if ownPlot == false then
        state.plotMismatch += 1
        addFinding("HIGH", "plot_mismatch_" .. tostring(id), "Drop " .. id .. " references a slot outside local Plot " .. getPlotName())
    end

    local distance = nil
    local root = getRoot()
    if root and typeof(position) == "Vector3" then
        distance = (root.Position - position).Magnitude
    end

    state.pending[id] = {
        id = id,
        tier = tostring(tier),
        position = position,
        unit = unit,
        slot = slot,
        ownPlot = ownPlot,
        spawnTime = now(),
        spawnDistance = distance,
    }

    pushLog("IN", string.format("DropSpawned id=%s tier=%s dist=%s", tostring(id), tostring(tier), distance and string.format("%.1f", distance) or "?"))

    if state.autoPickup then
        task.defer(function()
            sendObservedPickup(id, "auto")
        end)
    end
end)

CarryUpdated.OnClientEvent:Connect(function(count, tier)
    local oldCarry = state.carry
    state.carry = count
    state.carryTier = tier
    pushLog("IN", string.format("CarryUpdated(%s, %s)", tostring(count), tostring(tier)))

    if type(count) == "number" and count < 0 then
        addFinding("HIGH", "carry_negative_event", "CarryUpdated delivered negative carry: " .. count)
    end

    -- Correlate an accepted pickup with the nearest recently sent observed ID.
    local bestId, bestAge = nil, math.huge
    local t = now()
    for id, sentAt in pairs(state.pickupSent) do
        local age = t - sentAt
        if age >= 0 and age < bestAge and age <= 1.5 and state.pending[id] then
            bestId, bestAge = id, age
        end
    end

    if bestId then
        local meta = state.pending[bestId]
        if type(meta.spawnDistance) == "number" and meta.spawnDistance > state.distanceWarn then
            -- This is only a signal: CarryUpdated is correlated, not cryptographic proof that this exact request caused it.
            state.acceptedFar += 1
            addFinding(
                "HIGH",
                "far_pickup_" .. tostring(bestId),
                string.format("Potential missing proximity validation: observed drop %s was requested from %.1f studs away and CarryUpdated followed in %.2fs", bestId, meta.spawnDistance, bestAge)
            )
        end
        state.pending[bestId] = nil
    end

    if type(oldCarry) == "number" and type(count) == "number" and count - oldCarry > 25 then
        addFinding("MEDIUM", "carry_jump", "Carry jumped by more than 25 in one update: " .. oldCarry .. " -> " .. count)
    end
end)

DataUpdated.OnClientEvent:Connect(function(path, value)
    if type(path) ~= "string" then
        addFinding("MEDIUM", "data_path_type", "DataUpdated path is " .. typeof(path) .. " instead of string")
        return
    end

    local valueType = typeof(value)
    local oldType = state.pathTypes[path]
    if oldType and oldType ~= valueType then
        addFinding("MEDIUM", "typeflip_" .. path, "DataUpdated type changed for " .. path .. ": " .. oldType .. " -> " .. valueType)
    else
        state.pathTypes[path] = valueType
    end

    if type(value) == "number" and not finiteNumber(value) then
        addFinding("HIGH", "nonfinite_event_" .. path, path .. " received non-finite numeric value")
    end
end)

if NotifyRemote and NotifyRemote:IsA("RemoteEvent") then
    NotifyRemote.OnClientEvent:Connect(function(message, kind)
        pushLog("NOTIFY", tostring(kind) .. " | " .. clampString(message, 80))
    end)
end

-- ===== BACKGROUND UI / STATE LOOP =====

task.spawn(function()
    while task.wait(0.25) do
        local t = now()
        if state.autoRefresh and t - state.lastRefresh >= state.refreshEvery then
            state.lastRefresh = t
            local d = safeGetData()
            if d then sanityCheckData(d) end
        end
        renderState()
        renderFindings()
        renderLogs()
    end
end)

-- Initial snapshot
local initial = safeGetData()
if initial then sanityCheckData(initial) end

pushLog("READY", "Loaded for Plot " .. getPlotName())
toast("Capybara Onsen QA", "Loaded. Auto Pickup is OFF by default.", 5)

-- Load saved Rayfield flags after controls exist.
pcall(function()
    Rayfield:LoadConfiguration()
end)
