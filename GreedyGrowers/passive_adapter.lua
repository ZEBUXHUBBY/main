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
            out[#out + 1] = {
                instance = inst,
                key = inst:GetAttribute("SeedKey") or inst:GetAttribute("TreeKey") or inst.Name,
                name = inst.Name,
                ready = ready,
                mutation = inst:GetAttribute("Mutation"),
                plantedAt = inst:GetAttribute("PlantedAt"),
                readyAt = inst:GetAttribute("ReadyAt"),
                observedValue = inst:GetAttribute("Value") or inst:GetAttribute("SellValue"),
                position = getPivotPosition(inst),
            }
        end
    end
    return out
end

local function collectTexts(root)
    local texts = {}
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            local t = d.Text
            if type(t) == "string" and t ~= "" then texts[#texts + 1] = t end
        elseif d:IsA("ProximityPrompt") then
            if d.ObjectText and d.ObjectText ~= "" then texts[#texts + 1] = d.ObjectText end
            if d.ActionText and d.ActionText ~= "" then texts[#texts + 1] = d.ActionText end
        end
    end
    return texts
end

local function extractOfferFromRoot(root)
    local price = parseNumber(root:GetAttribute("Price") or root:GetAttribute("Cost") or root:GetAttribute("SeedCost"))
    local seedName = root:GetAttribute("SeedKey") or root:GetAttribute("SeedName") or root:GetAttribute("ItemName")
    local rarity = root:GetAttribute("Rarity")
    local texts = collectTexts(root)

    for _, t in ipairs(texts) do
        local low = t:lower()
        if not seedName then
            local n = t:match("^%s*(.-)%s+[Ss]eed%s*$")
            if n and n ~= "" then seedName = n end
        end
        if not price and (t:find("$") or low:find("cost") or low:find("price")) then
            local token = t:match("%$[%d,%.]+[KkMmBb]?") or t:match("[%d,%.]+[KkMmBb]?")
            local p = token and parseNumber(token)
            if p and p > 0 then price = p end
        end
        if not rarity then
            for _, r in ipairs({"Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret"}) do
                if low:find(r:lower(), 1, true) then rarity = r; break end
            end
        end
    end

    if not seedName then
        local n = root.Name:match("^(.-)[Ss]eed")
        if n and n ~= "" then seedName = n end
    end

    if seedName and price and price > 0 then
        return {
            instance = root,
            name = tostring(seedName),
            key = tostring(seedName),
            price = price,
            rarity = rarity,
            position = getPivotPosition(root),
        }
    end
end

function Adapter:GetSeedOffers()
    local offers, seen = {}, {}
    for _, inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("Model") or inst:IsA("Folder") then
            local low = inst.Name:lower()
            local candidate = low:find("seed", 1, true)
                or inst:GetAttribute("SeedKey") ~= nil
                or inst:GetAttribute("SeedName") ~= nil
                or inst:GetAttribute("SeedCost") ~= nil
            if candidate then
                local offer = extractOfferFromRoot(inst)
                if offer then
                    local id = offer.key .. ":" .. tostring(offer.price) .. ":" .. inst:GetFullName()
                    if not seen[id] then seen[id] = true; offers[#offers + 1] = offer end
                end
            end
        end
    end
    return offers
end

function Adapter:GetInventoryCount()
    if not LocalPlayer then return 0 end
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not backpack then return 0 end
    return #backpack:GetChildren()
end

function Adapter:GetHeldSeedName()
    if not LocalPlayer then return nil end
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    for _, root in ipairs({char, backpack}) do
        if root then
            for _, item in ipairs(root:GetChildren()) do
                local low = item.Name:lower()
                if low:find("seed", 1, true) then return item.Name end
            end
        end
    end
    return nil
end

-- Explicitly non-actionable in passive mode.
function Adapter:HarvestTree()
    return false, "passive adapter: harvest unavailable"
end
function Adapter:BuySeed()
    return false, "passive adapter: buy unavailable"
end
function Adapter:PlantSeed()
    return false, "passive adapter: plant unavailable"
end
function Adapter:SellAll()
    return false, "passive adapter: sell unavailable"
end

return Adapter
