-- Greedy Growers passive runtime adapter
-- Read-only discovery: no remote firing, no automated gameplay actions.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local Adapter = {}
Adapter.Mode = "PASSIVE"

local function parseNumber(v)
    if typeof(v) == "number" then return v end
    if typeof(v) ~= "string" then return nil end
    local s = v:gsub("[$,%s]", "")
    local mult = 1
    local suffix = s:sub(-1):lower()
    if suffix == "k" then mult = 1e3; s = s:sub(1, -2)
    elseif suffix == "m" then mult = 1e6; s = s:sub(1, -2)
    elseif suffix == "b" then mult = 1e9; s = s:sub(1, -2)
    end
    local n = tonumber(s)
    return n and n * mult or nil
end

local function readValueObject(obj)
    if not obj then return nil end
    if obj:IsA("IntValue") or obj:IsA("NumberValue") then return obj.Value end
    if obj:IsA("StringValue") then return parseNumber(obj.Value) end
    return nil
end

function Adapter:GetCash()
    if not LocalPlayer then return 0 end

    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        for _, name in ipairs({"Cash", "Money", "Coins", "Gold"}) do
            local obj = leaderstats:FindFirstChild(name)
            local n = readValueObject(obj)
            if n ~= nil then return n end
        end
    end

    for _, name in ipairs({"Cash", "Money", "Coins", "Gold"}) do
        local attr = LocalPlayer:GetAttribute(name)
        local n = parseNumber(attr)
        if n ~= nil then return n end
    end

    return 0
end

local function looksTreeLike(inst)
    if not (inst:IsA("Model") or inst:IsA("Folder")) then return false end
    local n = inst.Name:lower()
    if n:find("tree", 1, true) or n:find("plant", 1, true) then return true end
    if inst:FindFirstChild("FruitSpawns") then return true end
    if inst:FindFirstChild("Wood") and (inst:FindFirstChild("Leaves") or inst:FindFirstChild("Flowers")) then return true end
    return false
end

local function getPivotPosition(inst)
    if inst:IsA("Model") then
        local ok, cf = pcall(inst.GetPivot, inst)
        if ok then return cf.Position end
    end
    local part = inst:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

function Adapter:GetTrees()
    local out = {}
    local seen = {}

    for _, inst in ipairs(Workspace:GetDescendants()) do
        if looksTreeLike(inst) and not seen[inst] then
            seen[inst] = true

            local ready = false
            local readyAttr = inst:GetAttribute("Ready")
            if readyAttr ~= nil then
                ready = readyAttr == true
            elseif inst:FindFirstChild("FruitSpawns") then
                ready = #inst.FruitSpawns:GetChildren() > 0
            end

            local mutation = inst:GetAttribute("Mutation")
            local plantedAt = inst:GetAttribute("PlantedAt")
            local readyAt = inst:GetAttribute("ReadyAt")
            local value = inst:GetAttribute("Value") or inst:GetAttribute("SellValue")

            out[#out + 1] = {
                instance = inst,
                key = inst:GetAttribute("SeedKey") or inst:GetAttribute("TreeKey") or inst.Name,
                name = inst.Name,
                ready = ready,
                mutation = mutation,
                plantedAt = plantedAt,
                readyAt = readyAt,
                observedValue = value,
                position = getPivotPosition(inst),
            }
        end
    end

    return out
end

function Adapter:GetInventoryCount()
    if not LocalPlayer then return 0 end
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not backpack then return 0 end
    return #backpack:GetChildren()
end

-- Explicitly non-actionable in passive mode.
function Adapter:HarvestTree()
    return false, "passive adapter: harvest unavailable"
end

function Adapter:SellAll()
    return false, "passive adapter: sell unavailable"
end

return Adapter
