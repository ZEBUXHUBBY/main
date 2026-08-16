-- Greedy Growers snapshot-aware passive adapter
-- Uses only inbound client-visible events/state observed in the supplied snapshot.
-- It does NOT invoke server remotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local Adapter = {}
Adapter.__index = Adapter

local function newSignal()
    local bindable = Instance.new("BindableEvent")
    return bindable.Event, bindable
end

local function now()
    return os.clock()
end

local function parseCash(v)
    if typeof(v) == "Instance" then
        v = v.Value
    end
    if type(v) == "number" then return v end
    if type(v) ~= "string" then return nil end
    local cleaned = v:gsub("[^%d%.%-]", "")
    return tonumber(cleaned)
end

local function findCashValue()
    if not LocalPlayer then return nil end

    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        local cash = leaderstats:FindFirstChild("Cash")
        if cash then return cash end
    end

    local cash = LocalPlayer:FindFirstChild("Cash")
    if cash then return cash end

    return nil
end

local function describeRemote(remote)
    local parts = {}
    local p = remote
    while p and p ~= game do
        table.insert(parts, 1, p.Name)
        p = p.Parent
    end
    return table.concat(parts, ".")
end

function Adapter.new()
    local self = setmetatable({}, Adapter)

    self.Mode = "SNAPSHOT_PASSIVE"
    self.ReadOnly = true
    self.Rounds = {}
    self.SeedConveyor = {}
    self.LastSelectedItemID = nil
    self.LastEvent = "INIT"
    self.LastEventAt = now()
    self.LightningCount = 0
    self.EventCount = 0
    self.BoundRemotes = {}
    self.Connections = {}
    self.CashValue = findCashValue()

    self.LightningObserved, self._LightningObserved = newSignal()
    self.TreeUpdated, self._TreeUpdated = newSignal()
    self.SaleCompleted, self._SaleCompleted = newSignal()
    self.StateChanged, self._StateChanged = newSignal()

    self:_bindSnapshotEvents()
    self:_bindCash()

    return self
end

function Adapter:_setEvent(name, payload)
    self.LastEvent = name
    self.LastEventAt = now()
    self.EventCount += 1
    self._StateChanged:Fire(name, payload)
end

function Adapter:_rememberConnection(c)
    self.Connections[#self.Connections + 1] = c
end

function Adapter:_bindCash()
    if not self.CashValue then return end
    if self.CashValue.Changed then
        self:_rememberConnection(self.CashValue.Changed:Connect(function()
            self:_setEvent("CashChanged", self:GetCash())
        end))
    end
end

function Adapter:_onRoundStarted(roundId, position, serverTimestamp, sequence, observedNumber, seedName, extra)
    if roundId == nil then return end
    local key = tostring(roundId)
    local record = self.Rounds[key] or { id = roundId }
    record.name = tostring(seedName or record.name or "Unknown")
    record.key = record.name
    record.position = position
    record.serverTimestamp = serverTimestamp
    record.sequence = sequence
    -- Snapshot exposes this numeric field but does not prove its semantic meaning.
    record.observedNumber = observedNumber
    record.extra = extra
    record.state = "ROUND_STARTED"
    record.startedAt = now()
    record.lastUpdatedAt = now()
    record.ready = false
    record.confidence = 0.5
    self.Rounds[key] = record
    self:_setEvent("RoundStartedAll", record)
    self._TreeUpdated:Fire(record)
end

function Adapter:_onPlantStopped(roundId, observedNumber)
    local key = tostring(roundId)
    local record = self.Rounds[key] or { id = roundId, name = "Unknown", key = "Unknown" }
    record.state = "PLANT_STOPPED"
    record.stoppedAt = now()
    record.stopObservedNumber = observedNumber
    record.lastUpdatedAt = now()
    -- Do not equate stopped with harvest-ready; snapshot does not prove that.
    self.Rounds[key] = record
    self:_setEvent("PlantStoppedAll", record)
    self._TreeUpdated:Fire(record)
end

function Adapter:_onCrashed(roundId, observedNumber)
    local key = tostring(roundId)
    local record = self.Rounds[key] or { id = roundId, name = "Unknown", key = "Unknown" }
    record.state = "CRASHED"
    record.crashedAt = now()
    record.crashObservedNumber = observedNumber
    record.lastUpdatedAt = now()
    record.ready = false
    self.Rounds[key] = record
    self:_setEvent("CrashedAll", record)
    self._TreeUpdated:Fire(record)
end

function Adapter:_onRoundReset(roundId)
    local key = tostring(roundId)
    local record = self.Rounds[key]
    if record then
        record.state = "RESET"
        record.resetAt = now()
        record.lastUpdatedAt = now()
        self._TreeUpdated:Fire(record)
    end
    self:_setEvent("RoundResetAll", record or { id = roundId, state = "RESET" })
end

function Adapter:_onSeedSpawned(data)
    local record = {
        raw = data,
        observedAt = now(),
    }

    if type(data) == "table" then
        record.seedKey = data.seedKey or data.SeedKey or data.seed or data.Seed or data.name or data.Name
        record.rarity = data.rarity or data.Rarity
        record.spawnId = data.spawnId or data.SpawnId or data.id or data.ID
        record.travelDuration = data.travelDuration or data.TravelDuration
    end

    self.SeedConveyor[#self.SeedConveyor + 1] = record
    if #self.SeedConveyor > 50 then table.remove(self.SeedConveyor, 1) end
    self:_setEvent("SeedSpawned", record)
end

function Adapter:_onGenericEvent(...)
    local args = { ... }
    local eventName = args[1]
    self:_setEvent("Event", args)
    if type(eventName) == "string" and eventName:lower() == "lightning" then
        self.LightningCount += 1
        local ts = now()
        self._LightningObserved:Fire(ts)
        self:_setEvent("LIGHTNING", { at = ts, count = self.LightningCount })
    end
end

function Adapter:_bindRemote(remote)
    if not remote:IsA("RemoteEvent") then return false end

    local handlers = {
        RoundStartedAll = function(...) self:_onRoundStarted(...) end,
        PlantStoppedAll = function(...) self:_onPlantStopped(...) end,
        CrashedAll = function(...) self:_onCrashed(...) end,
        RoundResetAll = function(...) self:_onRoundReset(...) end,
        SeedSpawned = function(...) self:_onSeedSpawned(...) end,
        SelectedItemID = function(id)
            self.LastSelectedItemID = id
            self:_setEvent("SelectedItemID", id)
        end,
        DataUpdate = function(...)
            self:_setEvent("DataUpdate", { ... })
        end,
        SeedGrowStarted = function(seedName)
            self:_setEvent("SeedGrowStarted", seedName)
        end,
        Event = function(...) self:_onGenericEvent(...) end,
        SendNotification = function(message, ...)
            self:_setEvent("SendNotification", message)
            if type(message) == "string" then
                local amount = message:match("Sold%s+%d+%s+items?%s+for%s+%$([%d%.]+)")
                if amount then self._SaleCompleted:Fire(tonumber(amount) or 0) end
            end
        end,
    }

    local handler = handlers[remote.Name]
    if not handler then return false end

    local ok, connection = pcall(function()
        return remote.OnClientEvent:Connect(handler)
    end)
    if not ok or not connection then return false end

    self:_rememberConnection(connection)
    self.BoundRemotes[remote.Name] = describeRemote(remote)
    return true
end

function Adapter:_bindSnapshotEvents()
    local bound = 0
    for _, descendant in ipairs(ReplicatedStorage:GetDescendants()) do
        if descendant:IsA("RemoteEvent") and self:_bindRemote(descendant) then
            bound += 1
        end
    end
    self.BoundCount = bound
    self:_setEvent("SNAPSHOT_BOUND", { count = bound })
end

function Adapter:GetCash()
    if self.CashValue and self.CashValue.Parent then
        return parseCash(self.CashValue) or 0
    end
    self.CashValue = findCashValue()
    return parseCash(self.CashValue) or 0
end

function Adapter:GetTrees()
    local out = {}
    for _, record in pairs(self.Rounds) do
        if record.state ~= "RESET" then
            out[#out + 1] = record
        end
    end
    table.sort(out, function(a, b)
        return (a.lastUpdatedAt or 0) > (b.lastUpdatedAt or 0)
    end)
    return out
end

function Adapter:GetInventoryCount()
    -- Snapshot proves item selection/data updates, but not a stable inventory schema.
    return 0
end

function Adapter:GetSnapshotStatus()
    local active = 0
    local crashed = 0
    local stopped = 0
    for _, r in pairs(self.Rounds) do
        if r.state ~= "RESET" then active += 1 end
        if r.state == "CRASHED" then crashed += 1 end
        if r.state == "PLANT_STOPPED" then stopped += 1 end
    end
    return {
        mode = self.Mode,
        readOnly = self.ReadOnly,
        boundRemotes = self.BoundCount or 0,
        cash = self:GetCash(),
        activeRounds = active,
        crashedRounds = crashed,
        stoppedRounds = stopped,
        lightningCount = self.LightningCount,
        lastEvent = self.LastEvent,
        lastEventAt = self.LastEventAt,
        selectedItemId = self.LastSelectedItemID,
        seedObservations = #self.SeedConveyor,
    }
end

function Adapter:Destroy()
    for _, c in ipairs(self.Connections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(self.Connections)
    pcall(function() self._LightningObserved:Destroy() end)
    pcall(function() self._TreeUpdated:Destroy() end)
    pcall(function() self._SaleCompleted:Destroy() end)
    pcall(function() self._StateChanged:Destroy() end)
end

return Adapter.new()
