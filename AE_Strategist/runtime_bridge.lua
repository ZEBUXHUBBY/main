--[[
AE STRATEGIST | ULTRA-LIGHT EVENT RUNTIME BRIDGE
-------------------------------------------------
Read-only cache. No polling. No getgc. No automatic analysis.

Important rule:
  Runtime events may update tiny scalar caches or mark TeamDirty,
  but they NEVER call Core.RefreshAnalysis().

Heavy analysis happens only when the user presses SYNC.
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
    Version = "event-bridge-2.0-light",
    Yen = nil,
    Wave = nil,
    YenSource = "UNKNOWN",
    WaveSource = "UNKNOWN",
    TeamDirty = false,
    TeamDirtyReason = nil,
    Connections = {},
    Destroyed = false,
    Changed = Instance.new("BindableEvent"),
}
ENV.AE_STRATEGIST_RUNTIME = Bridge
Core.RuntimeBridge = Bridge

local function norm(v)
    return tostring(v or ""):lower():gsub("[^%w]", "")
end

local function connect(c)
    if c then Bridge.Connections[#Bridge.Connections + 1] = c end
    return c
end

local function setYen(v, source)
    v = tonumber(v)
    if not v or v < 0 or Bridge.Yen == v then return end
    Bridge.Yen = v
    Bridge.YenSource = source or "runtime"
    Bridge.Changed:Fire("Yen", v)
end

local function setWave(v, source)
    v = tonumber(v)
    if not v or v < 0 or v > 100000 or Bridge.Wave == v then return end
    Bridge.Wave = v
    Bridge.WaveSource = source or "runtime"
    Bridge.Changed:Fire("Wave", v)
end

local YEN = {yen=true,currentyen=true,money=true,cash=true}
local WAVE = {wave=true,currentwave=true,wavenumber=true,round=true,currentround=true}
local TEAM_LEAF = {
    trait=true,equipment=true,equipments=true,statpotential=true,
    level=true,equipped=true,hotbarslot=true,unitdata=true,hotbardata=true,
}

local function pathInfo(path)
    if type(path) ~= "table" then return nil,nil,false,false end
    local leaf
    local inUnit = false
    local inHotbar = false
    local n = 0
    for i,v in ipairs(path) do
        n = n + 1
        local t = norm(v)
        leaf = t
        if t == "unitdata" then inUnit = true end
        if t == "hotbardata" then inHotbar = true end
    end
    -- Some paths are dictionary-like rather than arrays.
    if n == 0 then
        for _,v in pairs(path) do
            if type(v) == "string" or type(v) == "number" then
                local t = norm(v)
                leaf = t
                if t == "unitdata" then inUnit = true end
                if t == "hotbardata" then inHotbar = true end
            end
        end
    end
    return leaf, path, inUnit, inHotbar
end

local function markTeamDirty(reason)
    Bridge.TeamDirty = true
    Bridge.TeamDirtyReason = reason
    -- Tiny notification only. Never run analysis here.
    Bridge.Changed:Fire("TeamDirty", reason)
end

local function onReplicaSet(replicaId, path, value)
    local leaf, _, inUnit, inHotbar = pathInfo(path)
    if not leaf then return end

    -- Scalar runtime cache: exact leaf only, O(1).
    if type(value) == "number" then
        if YEN[leaf] then setYen(value, "ReplicaSet." .. leaf)
        elseif WAVE[leaf] then setWave(value, "ReplicaSet." .. leaf) end
    end

    -- Team changes only count inside UnitData/HotbarData.
    -- Generic Level changes elsewhere in the game are ignored.
    if (inUnit or inHotbar) and TEAM_LEAF[leaf] then
        markTeamDirty("ReplicaSet:" .. leaf)
    elseif leaf == "unitdata" or leaf == "hotbardata" then
        markTeamDirty("ReplicaSet:" .. leaf)
    end
end

local RemoteEvents = RS:FindFirstChild("RemoteEvents")
if RemoteEvents then
    local replicaSet = RemoteEvents:FindFirstChild("ReplicaSet")
    if replicaSet and replicaSet:IsA("RemoteEvent") then
        connect(replicaSet.OnClientEvent:Connect(onReplicaSet))
    end
    -- Intentionally do NOT inspect ReplicaSetValues. It can be very high-frequency
    -- and its payload shape is not needed for the lightweight cache.
end

-- Cheap Player attribute listeners when the game exposes exact scalar values.
for _,name in ipairs({"Yen","CurrentYen","Money","Cash","Wave","CurrentWave","WaveNumber","Round"}) do
    local current = LP:GetAttribute(name)
    if current ~= nil then
        if YEN[norm(name)] then setYen(current, "PlayerAttribute."..name) end
        if WAVE[norm(name)] then setWave(current, "PlayerAttribute."..name) end
        connect(LP:GetAttributeChangedSignal(name):Connect(function()
            local v = LP:GetAttribute(name)
            if YEN[norm(name)] then setYen(v, "PlayerAttribute."..name) end
            if WAVE[norm(name)] then setWave(v, "PlayerAttribute."..name) end
        end))
    end
end

-- One-time fallback discovery for exact Yen/Wave UI labels.
-- Bind at most 8 labels; after binding, there is no traversal again.
local function numericText(s)
    if type(s) ~= "string" then return nil end
    return tonumber((s:gsub("[,¥$%s]", "")):match("[-+]?%d+%.?%d*"))
end

local pg = LP:FindFirstChild("PlayerGui")
if pg then
    local bound = 0
    for _,d in ipairs(pg:GetDescendants()) do
        if bound >= 8 then break end
        if d:IsA("TextLabel") or d:IsA("TextBox") then
            local context = norm(d.Name .. " " .. (d.Parent and d.Parent.Name or ""))
            local kind
            if context == "yen" or context:find("yendisplay",1,true) or context:find("currencylabel",1,true) then
                kind = "Yen"
            elseif context == "wave" or context:find("wavelabel",1,true) or context:find("wavedisplay",1,true) then
                kind = "Wave"
            end
            if kind then
                bound = bound + 1
                local function read()
                    local v = numericText(d.Text)
                    if kind == "Yen" then setYen(v, "Gui."..d:GetFullName())
                    else setWave(v, "Gui."..d:GetFullName()) end
                end
                read()
                connect(d:GetPropertyChangedSignal("Text"):Connect(read))
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
        TeamDirty = Bridge.TeamDirty,
        TeamDirtyReason = Bridge.TeamDirtyReason,
    }
end

function Bridge.ClearTeamDirty()
    Bridge.TeamDirty = false
    Bridge.TeamDirtyReason = nil
end

function Bridge.Destroy()
    if Bridge.Destroyed then return end
    Bridge.Destroyed = true
    for _,c in ipairs(Bridge.Connections) do pcall(function() c:Disconnect() end) end
    Bridge.Connections = {}
    pcall(function() Bridge.Changed:Destroy() end)
    if Core.RuntimeBridge == Bridge then Core.RuntimeBridge = nil end
    if ENV.AE_STRATEGIST_RUNTIME == Bridge then ENV.AE_STRATEGIST_RUNTIME = nil end
end

print("[AE RuntimeBridge] READY | ultra-light | auto analysis OFF")
