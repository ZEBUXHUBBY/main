--[[
AE STRATEGIST | EVENT-DRIVEN RUNTIME BRIDGE
-------------------------------------------
Passive, read-only runtime cache.
No polling loop and no gameplay remotes are fired.

Goals:
- Observe replicated Yen/Wave changes from incoming Replica events.
- Observe likely GUI/ValueObject Yen/Wave values via Changed signals.
- Debounce expensive core analysis only when UnitData/HotbarData actually changes.
- Expose one lightweight Changed BindableEvent for the dashboard.
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer
local ENV = getgenv and getgenv() or _G
local Core = ENV.AE_STRATEGIST
if type(Core) ~= "table" then return end

if type(ENV.AE_STRATEGIST_RUNTIME) == "table" and type(ENV.AE_STRATEGIST_RUNTIME.Destroy) == "function" then
    pcall(ENV.AE_STRATEGIST_RUNTIME.Destroy)
end

local Bridge = {
    Version = "event-bridge-1.0",
    Yen = nil,
    Wave = nil,
    YenSource = "UNKNOWN",
    WaveSource = "UNKNOWN",
    Connections = {},
    Destroyed = false,
    AnalysisQueued = false,
    LastAnalysisReason = nil,
    Changed = Instance.new("BindableEvent"),
}
ENV.AE_STRATEGIST_RUNTIME = Bridge
Core.RuntimeBridge = Bridge

local function norm(v)
    return tostring(v or ""):lower():gsub("[^%w]", "")
end

local function addConnection(c)
    if c then Bridge.Connections[#Bridge.Connections + 1] = c end
    return c
end

local function setYen(v, source)
    v = tonumber(v)
    if not v or v < 0 then return end
    if Bridge.Yen ~= v or Bridge.YenSource ~= source then
        Bridge.Yen = v
        Bridge.YenSource = source or "runtime"
        Bridge.Changed:Fire("Yen", v, Bridge.YenSource)
    end
end

local function setWave(v, source)
    v = tonumber(v)
    if not v or v < 0 or v > 100000 then return end
    if Bridge.Wave ~= v or Bridge.WaveSource ~= source then
        Bridge.Wave = v
        Bridge.WaveSource = source or "runtime"
        Bridge.Changed:Fire("Wave", v, Bridge.WaveSource)
    end
end

local function pathTokens(path)
    local out = {}
    if type(path) == "table" then
        for _, v in pairs(path) do
            if type(v) == "string" or type(v) == "number" then
                out[#out + 1] = norm(v)
            end
        end
    elseif path ~= nil then
        out[1] = norm(path)
    end
    return out
end

local function tokenMatches(tokens, wanted)
    for _, t in ipairs(tokens) do
        for _, w in ipairs(wanted) do
            if t == w or t:find(w, 1, true) then return true end
        end
    end
    return false
end

local function queueAnalysis(reason)
    if Bridge.AnalysisQueued or Bridge.Destroyed then return end
    Bridge.AnalysisQueued = true
    Bridge.LastAnalysisReason = reason
    task.delay(0.75, function()
        Bridge.AnalysisQueued = false
        if Bridge.Destroyed then return end
        if Core and type(Core.RefreshAnalysis) == "function" then
            pcall(Core.RefreshAnalysis)
            Bridge.Changed:Fire("Analysis", reason or "replica change")
        end
    end)
end

local YEN_NAMES = {yen=true, currentyen=true, money=true, cash=true, currency=true}
local WAVE_NAMES = {wave=true, currentwave=true, wavenumber=true, round=true, currentround=true}
local TEAM_TOKENS = {"unitdata", "hotbardata", "trait", "equipment", "statpotential", "level", "equipped", "hotbarslot"}

local function inspectScalarByName(name, value, source)
    local n = norm(name)
    if YEN_NAMES[n] then setYen(value, source .. "." .. tostring(name)) end
    if WAVE_NAMES[n] then setWave(value, source .. "." .. tostring(name)) end
end

local function inspectValueTable(t, source, depth)
    if type(t) ~= "table" then return end
    depth = depth or 0
    if depth > 2 then return end
    local seen = 0
    for k, v in pairs(t) do
        seen = seen + 1
        if seen > 40 then break end
        if type(v) == "number" then
            inspectScalarByName(k, v, source)
        elseif type(v) == "table" and depth < 2 then
            inspectValueTable(v, source .. "." .. tostring(k), depth + 1)
        end
    end
end

local function onReplicaEvent(remoteName, ...)
    local args = table.pack(...)
    local possiblePath = nil
    local value = nil

    -- Common ReplicaSet signature observed in this game:
    -- (replicaId, pathTable, value)
    if type(args[2]) == "table" then
        possiblePath = args[2]
        value = args[3]
    elseif type(args[1]) == "table" then
        possiblePath = args[1]
        value = args[2]
    end

    if possiblePath then
        local tokens = pathTokens(possiblePath)
        local leaf = tokens[#tokens]
        if leaf and type(value) == "number" then
            inspectScalarByName(leaf, value, "Replica." .. remoteName)
        elseif type(value) == "table" then
            inspectValueTable(value, "Replica." .. remoteName, 0)
        end
        if tokenMatches(tokens, TEAM_TOKENS) then
            queueAnalysis("Replica " .. remoteName .. " changed " .. table.concat(tokens, "."))
        end
    else
        -- ReplicaSetValues and other compact variants: only shallow inspect args.
        for i = 1, math.min(args.n, 4) do
            local a = args[i]
            if type(a) == "table" then
                inspectValueTable(a, "Replica." .. remoteName .. ".arg" .. tostring(i), 0)
            end
        end
    end
end

local RemoteEvents = RS:FindFirstChild("RemoteEvents")
if RemoteEvents then
    for _, name in ipairs({"ReplicaSet", "ReplicaSetValues"}) do
        local r = RemoteEvents:FindFirstChild(name)
        if r and r:IsA("RemoteEvent") then
            addConnection(r.OnClientEvent:Connect(function(...)
                onReplicaEvent(name, ...)
            end))
        end
    end
end

-- Attribute listeners: extremely cheap and only bind to already-exposed fields.
for _, name in ipairs({"Yen","CurrentYen","Money","Cash","Wave","CurrentWave","WaveNumber","Round"}) do
    if LP:GetAttribute(name) ~= nil then
        inspectScalarByName(name, LP:GetAttribute(name), "PlayerAttribute")
        addConnection(LP:GetAttributeChangedSignal(name):Connect(function()
            inspectScalarByName(name, LP:GetAttribute(name), "PlayerAttribute")
        end))
    end
end

-- One-time GUI/value discovery, then Changed listeners only. No recurring traversal.
local function numericText(s)
    if type(s) ~= "string" then return nil end
    local cleaned = s:gsub("[,¥$%s]", "")
    return tonumber(cleaned:match("[-+]?%d+%.?%d*"))
end

local pg = LP:FindFirstChild("PlayerGui")
if pg then
    local bound = 0
    for _, d in ipairs(pg:GetDescendants()) do
        if bound >= 40 then break end
        local context = norm(d.Name .. " " .. (d.Parent and d.Parent.Name or ""))
        local isYen = context:find("yen",1,true) or context:find("money",1,true) or context:find("cash",1,true) or context:find("currency",1,true)
        local isWave = context:find("wave",1,true) or context:find("round",1,true)
        if isYen or isWave then
            if d:IsA("IntValue") or d:IsA("NumberValue") then
                bound = bound + 1
                if isYen then setYen(d.Value, "ValueObject:" .. d:GetFullName()) end
                if isWave then setWave(d.Value, "ValueObject:" .. d:GetFullName()) end
                addConnection(d.Changed:Connect(function(v)
                    if isYen then setYen(v, "ValueObject:" .. d:GetFullName()) end
                    if isWave then setWave(v, "ValueObject:" .. d:GetFullName()) end
                end))
            elseif d:IsA("TextLabel") or d:IsA("TextBox") then
                bound = bound + 1
                local function readText()
                    local v = numericText(d.Text)
                    if isYen then setYen(v, "GuiText:" .. d:GetFullName()) end
                    if isWave then setWave(v, "GuiText:" .. d:GetFullName()) end
                end
                readText()
                addConnection(d:GetPropertyChangedSignal("Text"):Connect(readText))
            end
        end
    end
end

function Bridge.GetSnapshot()
    return {
        Yen = Bridge.Yen,
        Wave = Bridge.Wave,
        YenSource = Bridge.YenSource,
        WaveSource = Bridge.WaveSource,
        LastAnalysisReason = Bridge.LastAnalysisReason,
    }
end

function Bridge.Destroy()
    if Bridge.Destroyed then return end
    Bridge.Destroyed = true
    for _, c in ipairs(Bridge.Connections) do pcall(function() c:Disconnect() end) end
    Bridge.Connections = {}
    pcall(function() Bridge.Changed:Destroy() end)
    if Core and Core.RuntimeBridge == Bridge then Core.RuntimeBridge = nil end
    if ENV.AE_STRATEGIST_RUNTIME == Bridge then ENV.AE_STRATEGIST_RUNTIME = nil end
end

print("[AE RuntimeBridge] READY | event-driven, no polling")
