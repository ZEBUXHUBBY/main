-- Greedy Growers snapshot-aware passive adapter
-- Read-only: observes client-visible state/events. It never fires gameplay remotes.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local Adapter = {}
Adapter.Mode = "SNAPSHOT_PASSIVE"

local Signals = {
    SeedSpawned = Instance.new("BindableEvent"),
    SelectedItemChanged = Instance.new("BindableEvent"),
    RoundStarted = Instance.new("BindableEvent"),
    RoundReset = Instance.new("BindableEvent"),
    PlantCrashed = Instance.new("BindableEvent"),
    PlantStopped = Instance.new("BindableEvent"),
    LightningObserved = Instance.new("BindableEvent"),
    DataUpdated = Instance.new("BindableEvent"),
}
Adapter.SeedSpawned = Signals.SeedSpawned.Event
Adapter.SelectedItemChanged = Signals.SelectedItemChanged.Event
Adapter.RoundStarted = Signals.RoundStarted.Event
Adapter.RoundReset = Signals.RoundReset.Event
Adapter.PlantCrashed = Signals.PlantCrashed.Event
Adapter.PlantStopped = Signals.PlantStopped.Event
Adapter.LightningObserved = Signals.LightningObserved.Event
Adapter.DataUpdated = Signals.DataUpdated.Event

local State = {
    selectedItemId = nil,
    selectedSeedName = nil,
    activeRound = nil,
    lastSeedSpawn = nil,
    lastDataUpdate = nil,
    lastLightningAt = nil,
}

local function parseNumber(v)
    if typeof(v) == "number" then return v end
    if typeof(v) ~= "string" then return nil end
    local s = v:gsub("[$,%s]", "")
    local mult = 1
    local suffix = s:sub(-1):lower()
    if suffix == "k" then mult = 1e3; s = s:sub(1,-2)
    elseif suffix == "m" then mult = 1e6; s = s:sub(1,-2)
    elseif suffix == "b" then mult = 1e9; s = s:sub(1,-2) end
    local n = tonumber(s)
    return n and n * mult or nil
end

local function readValueObject(obj)
    if not obj then return nil end
    if obj:IsA("IntValue") or obj:IsA("NumberValue") then return obj.Value end
    if obj:IsA("StringValue") then return parseNumber(obj.Value) end
end

function Adapter:GetCash()
    if not LocalPlayer then return 0 end
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        for _,name in ipairs({"Cash","Money","Coins","Gold"}) do
            local n = readValueObject(leaderstats:FindFirstChild(name))
            if n ~= nil then return n end
        end
    end
    for _,name in ipairs({"Cash","Money","Coins","Gold"}) do
        local n = parseNumber(LocalPlayer:GetAttribute(name))
        if n ~= nil then return n end
    end
    return 0
end

local function getPivotPosition(inst)
    if inst:IsA("Model") then
        local ok,cf = pcall(inst.GetPivot,inst)
        if ok then return cf.Position end
    end
    local p = inst:FindFirstChildWhichIsA("BasePart",true)
    return p and p.Position or nil
end

local function looksTreeLike(inst)
    if not (inst:IsA("Model") or inst:IsA("Folder")) then return false end
    local n = inst.Name:lower()
    return n:find("tree",1,true) ~= nil
        or n:find("plant",1,true) ~= nil
        or inst:FindFirstChild("FruitSpawns") ~= nil
end

function Adapter:GetTrees()
    local out,seen = {},{}
    for _,inst in ipairs(Workspace:GetDescendants()) do
        if looksTreeLike(inst) and not seen[inst] then
            seen[inst] = true
            local ready = inst:GetAttribute("Ready") == true
            if not ready and inst:FindFirstChild("FruitSpawns") then
                ready = #inst.FruitSpawns:GetChildren() > 0
            end
            out[#out+1] = {
                instance=inst,
                key=inst:GetAttribute("SeedKey") or inst:GetAttribute("TreeKey") or inst.Name,
                name=inst.Name,
                ready=ready,
                mutation=inst:GetAttribute("Mutation"),
                observedValue=inst:GetAttribute("Value") or inst:GetAttribute("SellValue"),
                position=getPivotPosition(inst),
            }
        end
    end
    return out
end

local function collectTexts(root)
    local texts={}
    for _,d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            if type(d.Text)=="string" and d.Text~="" then texts[#texts+1]=d.Text end
        elseif d:IsA("ProximityPrompt") then
            if d.ObjectText and d.ObjectText~="" then texts[#texts+1]=d.ObjectText end
            if d.ActionText and d.ActionText~="" then texts[#texts+1]=d.ActionText end
        end
    end
    return texts
end

local function extractOfferFromRoot(root)
    local price=parseNumber(root:GetAttribute("Price") or root:GetAttribute("Cost") or root:GetAttribute("SeedCost"))
    local seedName=root:GetAttribute("SeedKey") or root:GetAttribute("SeedName") or root:GetAttribute("ItemName")
    local rarity=root:GetAttribute("Rarity")
    for _,t in ipairs(collectTexts(root)) do
        local low=t:lower()
        if not seedName then local n=t:match("^%s*(.-)%s+[Ss]eed%s*$"); if n and n~="" then seedName=n end end
        if not price then
            local token=t:match("%$[%d,%.]+[KkMmBb]?")
            if token then price=parseNumber(token) end
        end
        if not rarity then
            for _,r in ipairs({"Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret"}) do
                if low:find(r:lower(),1,true) then rarity=r break end
            end
        end
    end
    if not seedName then local n=root.Name:match("^(.-)[Ss]eed"); if n and n~="" then seedName=n end end
    if seedName and price and price>0 then
        return {instance=root,name=tostring(seedName),key=tostring(seedName),price=price,rarity=rarity,position=getPivotPosition(root)}
    end
end

function Adapter:GetSeedOffers()
    local offers,seen={},{}
    for _,inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("Model") or inst:IsA("Folder") then
            local low=inst.Name:lower()
            if low:find("seed",1,true) or inst:GetAttribute("SeedKey")~=nil or inst:GetAttribute("SeedCost")~=nil then
                local offer=extractOfferFromRoot(inst)
                if offer then
                    local id=offer.key..":"..tostring(offer.price)..":"..inst:GetFullName()
                    if not seen[id] then seen[id]=true; offers[#offers+1]=offer end
                end
            end
        end
    end
    return offers
end

function Adapter:GetHeldSeedName()
    if State.selectedSeedName then return State.selectedSeedName end
    if not LocalPlayer then return nil end
    for _,root in ipairs({LocalPlayer.Character,LocalPlayer:FindFirstChildOfClass("Backpack")}) do
        if root then
            for _,item in ipairs(root:GetChildren()) do
                if item.Name:lower():find("seed",1,true) then return item.Name:gsub("%s*[Ss]eed%s*$","") end
            end
        end
    end
end

function Adapter:GetSelectedItemId() return State.selectedItemId end
function Adapter:GetActiveRound() return State.activeRound end
function Adapter:GetLastSeedSpawn() return State.lastSeedSpawn end
function Adapter:GetInventoryCount()
    local b=LocalPlayer and LocalPlayer:FindFirstChildOfClass("Backpack")
    return b and #b:GetChildren() or 0
end

local function findRemoteEventByName(name)
    for _,d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") and d.Name==name then return d end
    end
end

local function connectIncoming()
    local function bind(name,fn)
        local r=findRemoteEventByName(name)
        if r then r.OnClientEvent:Connect(fn) end
    end

    bind("SeedSpawned",function(data)
        if type(data)=="table" then
            State.lastSeedSpawn=data
            Signals.SeedSpawned:Fire(data)
        end
    end)

    bind("SelectedItemID",function(id)
        State.selectedItemId=id
        if id==nil then State.selectedSeedName=nil end
        Signals.SelectedItemChanged:Fire(id)
    end)

    bind("RoundStartedAll",function(roundId,pos,startTime,slot,value,seedKey,extra)
        State.activeRound={roundId=roundId,startTime=startTime,slot=slot,observedNumber=value,seedKey=seedKey,extra=extra}
        State.selectedSeedName=nil
        Signals.RoundStarted:Fire(State.activeRound)
    end)

    bind("RoundResetAll",function(roundId)
        if State.activeRound and State.activeRound.roundId==roundId then State.activeRound=nil end
        Signals.RoundReset:Fire(roundId)
    end)

    bind("CrashedAll",function(roundId,value)
        Signals.PlantCrashed:Fire(roundId,value)
    end)

    bind("PlantStoppedAll",function(roundId,value)
        Signals.PlantStopped:Fire(roundId,value)
    end)

    bind("DataUpdate",function(data,path)
        State.lastDataUpdate={data=data,path=path}
        -- Best-effort extraction only: snapshot shows Hotbar/Storage/Index structures but not a stable item schema.
        local function walk(v,depth)
            if depth>5 or type(v)~="table" then return nil end
            for k,x in pairs(v) do
                if type(x)=="string" and x:lower():find("seed",1,true) then
                    return x:gsub("%s*[Ss]eed%s*$","")
                elseif type(k)=="string" and k:lower():find("seed",1,true) and type(x)=="string" then
                    return x
                elseif type(x)=="table" then
                    local got=walk(x,depth+1); if got then return got end
                end
            end
        end
        local seed=walk(data,0)
        if seed then State.selectedSeedName=seed end
        Signals.DataUpdated:Fire(data,path)
    end)

    bind("Event",function(kind,...)
        if type(kind)=="string" and kind:lower()=="lightning" then
            State.lastLightningAt=os.clock()
            Signals.LightningObserved:Fire(State.lastLightningAt,...)
        end
    end)
end

connectIncoming()

-- Action interface intentionally disabled for third-party live-game use.
function Adapter:HarvestTree() return false,"snapshot-passive: harvest action unavailable" end
function Adapter:BuySeed() return false,"snapshot-passive: buy action unavailable" end
function Adapter:PlantSeed() return false,"snapshot-passive: plant action unavailable" end
function Adapter:SellAll() return false,"snapshot-passive: sell action unavailable" end

return Adapter
