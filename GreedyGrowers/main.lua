-- Greedy Growers Adaptive Profit Controller
-- Rayfield UI + config-driven strategy shell.
-- Intended for authorized Roblox Studio/test environments.

local Greedy = {}
local HttpService = game:GetService("HttpService")

local DEFAULTS = {
    Enabled = false,
    AutoOptimize = true,
    AutoSell = true,
    AutoHarvest = true,
    AutoBuySeed = true,
    CashReserve = 0,
    SellThreshold = 1,
    LightningSafetyMargin = 0.35,
    MinConfidence = 0.55,
    Debug = false,
    SeedStats = {}, TreeStats = {}, MutationMultipliers = {}, FertilizerStats = {},
    Lightning = {samples = {}, estimatedInterval = nil, estimatedJitter = nil, lastObservedAt = nil},
}

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local o = {}; for k,x in pairs(v) do o[k] = deepCopy(x) end; return o
end

local function merge(dst, src)
    for k,v in pairs(src or {}) do
        if type(v)=="table" and type(dst[k])=="table" then merge(dst[k],v) else dst[k]=deepCopy(v) end
    end
    return dst
end

local Config = deepCopy(DEFAULTS)
local Adapter
local Runtime = {
    State="IDLE", ActiveTree=nil, LastDecision=nil,
    RecommendedSeed=nil, RecommendedSeedPrice=nil,
    MoneyEarned=0, SellCount=0, HarvestCount=0, BuyCount=0,
    LightningAvoids=0, LastActionError=nil, Connections={}
}

local function safeCall(fn,...)
    if type(fn)~="function" then return nil,"function unavailable" end
    local ok,a,b,c=pcall(fn,...)
    if not ok then Runtime.LastActionError=tostring(a); warn("[GreedyGrowers]",a); return nil,a end
    return a,b,c
end

local function median(list)
    if #list==0 then return nil end
    local c=table.clone(list); table.sort(c); local n=#c
    if n%2==1 then return c[(n+1)/2] end
    return (c[n/2]+c[n/2+1])/2
end

local function estimateLightning()
    local s=Config.Lightning.samples
    if #s<2 then Config.Lightning.estimatedInterval=nil; Config.Lightning.estimatedJitter=nil; return end
    local gaps={}; for i=2,#s do gaps[#gaps+1]=s[i]-s[i-1] end
    local center=median(gaps); Config.Lightning.estimatedInterval=center
    local dev={}; for _,g in ipairs(gaps) do dev[#dev+1]=math.abs(g-center) end
    Config.Lightning.estimatedJitter=median(dev) or 0
end

local function observeLightning(ts)
    ts=ts or os.clock(); local s=Config.Lightning.samples; s[#s+1]=ts
    if #s>30 then table.remove(s,1) end
    Config.Lightning.lastObservedAt=ts; estimateLightning()
end

local function getTreeStats(tree)
    if not tree then return nil end
    local key=tree.key or tree.seedKey or tree.name
    if not key then return nil end
    return Config.TreeStats[key] or Config.SeedStats[key],key
end

local function expectedTreeValue(tree)
    local stats=getTreeStats(tree)
    if not stats then
        local v=tonumber(tree and tree.observedValue) or 0
        return v, v>0 and 0.65 or 0
    end
    local base=tonumber(stats.expectedValue or stats.sellValue or stats.value) or tonumber(tree.observedValue) or 0
    local yield=tonumber(stats.expectedYield or stats.yield) or 1
    local mutation=1
    local mk=tree.mutation or stats.mutation
    if mk then mutation=tonumber(Config.MutationMultipliers[mk]) or tonumber(stats.mutationMultiplier) or 1 end
    return base*yield*mutation, tonumber(stats.confidence) or 0.5
end

local function scoreTree(tree)
    local value,confidence=expectedTreeValue(tree)
    local score=value*math.max(confidence,0.01)
    if tree.ready then score=score+1e9 end
    return score, tree.ready and "ready" or "highest-observed-value"
end

local function chooseBestTree(trees)
    local best,bestScore,reason=nil,-math.huge,nil
    for _,tree in ipairs(trees or {}) do
        local score,why=scoreTree(tree)
        if score>bestScore then best,bestScore,reason=tree,score,why end
    end
    return best,bestScore,reason
end

local function seedPrice(seed)
    return tonumber(seed and (seed.price or seed.cost or seed.Price or seed.Cost))
end

local function chooseAffordableSeed(offers,cash)
    local budget=math.max(0,(tonumber(cash) or 0)-(tonumber(Config.CashReserve) or 0))
    local best,bestPrice=nil,-math.huge
    for _,seed in ipairs(offers or {}) do
        local price=seedPrice(seed)
        if price and price<=budget and price>bestPrice then best,bestPrice=seed,price end
    end
    return best, bestPrice==-math.huge and nil or bestPrice
end

local function emergencyHarvest(reason)
    Runtime.State="EMERGENCY_HARVEST"
    local trees=Adapter and (safeCall(Adapter.GetTrees,Adapter) or {}) or {}
    local didAny=false
    if Config.AutoHarvest and Adapter and type(Adapter.HarvestTree)=="function" then
        for _,tree in ipairs(trees) do
            if tree.ready then
                local ok,amount=safeCall(Adapter.HarvestTree,Adapter,tree)
                if ok then
                    didAny=true; Runtime.HarvestCount+=1; Runtime.LightningAvoids+=1; Runtime.MoneyEarned+=tonumber(amount) or 0
                end
            end
        end
    end
    if not didAny then
        local best=chooseBestTree(trees)
        Runtime.LastDecision={action="HARVEST_NOW",tree=best and (best.key or best.name),reason=reason,at=os.clock()}
    end
end

local function disconnectAll()
    for _,c in ipairs(Runtime.Connections) do pcall(function() c:Disconnect() end) end
    table.clear(Runtime.Connections)
end

local function bindSignal(signal,fn)
    if signal and typeof(signal)=="RBXScriptSignal" then Runtime.Connections[#Runtime.Connections+1]=signal:Connect(fn)
    elseif signal and type(signal.Connect)=="function" then Runtime.Connections[#Runtime.Connections+1]=signal:Connect(fn) end
end

local lastBuyAttempt=0
local function tickController()
    if not Config.Enabled or not Adapter then return end
    local trees=safeCall(Adapter.GetTrees,Adapter) or {}

    if Config.AutoOptimize then
        local best,score,reason=chooseBestTree(trees)
        Runtime.ActiveTree=best
        Runtime.LastDecision={tree=best and (best.key or best.name),score=score,reason=reason,at=os.clock()}
    end

    if type(Adapter.GetSeedOffers)=="function" then
        local offers=safeCall(Adapter.GetSeedOffers,Adapter) or {}
        local cash=tonumber(safeCall(Adapter.GetCash,Adapter)) or 0
        local seed,price=chooseAffordableSeed(offers,cash)
        Runtime.RecommendedSeed=seed and (seed.key or seed.seedKey or seed.name) or nil
        Runtime.RecommendedSeedPrice=price
        if Config.AutoBuySeed and seed and type(Adapter.BuySeed)=="function" and os.clock()-lastBuyAttempt>=1 then
            lastBuyAttempt=os.clock()
            local ok=safeCall(Adapter.BuySeed,Adapter,seed)
            if ok then Runtime.BuyCount+=1 end
        end
    end

    if Config.AutoSell and type(Adapter.GetInventoryCount)=="function" and type(Adapter.SellAll)=="function" then
        local count=tonumber(safeCall(Adapter.GetInventoryCount,Adapter)) or 0
        if count>=Config.SellThreshold then
            local ok,amount=safeCall(Adapter.SellAll,Adapter)
            if ok then Runtime.SellCount+=1; Runtime.MoneyEarned+=tonumber(amount) or 0 end
        end
    end
end

function Greedy.AttachAdapter(adapter)
    Adapter=adapter; disconnectAll(); if not Adapter then return end
    bindSignal(Adapter.LightningObserved,function(ts) observeLightning(ts); emergencyHarvest("lightning-event") end)
    bindSignal(Adapter.TreeUpdated,function(tree) Runtime.ActiveTree=tree end)
    bindSignal(Adapter.SaleCompleted,function(amount) Runtime.MoneyEarned+=tonumber(amount) or 0 end)
end

function Greedy.SetConfig(partial) merge(Config,partial or {}); estimateLightning() end
function Greedy.GetConfig() return deepCopy(Config) end
function Greedy.GetRuntime() return deepCopy(Runtime) end
function Greedy.ObserveLightning(ts) observeLightning(ts); emergencyHarvest("manual-lightning") end
function Greedy.ScoreTree(tree) return scoreTree(tree) end
function Greedy.ChooseBestTree(trees) return chooseBestTree(trees) end
function Greedy.ChooseAffordableSeed(offers,cash) return chooseAffordableSeed(offers,cash) end

local CONFIG_FILE="GreedyGrowers/config.json"
function Greedy.SaveConfig()
    if not(writefile and makefolder) then return false end
    pcall(makefolder,"GreedyGrowers")
    local ok,encoded=pcall(HttpService.JSONEncode,HttpService,Config)
    return ok and pcall(writefile,CONFIG_FILE,encoded) or false
end
function Greedy.LoadConfig()
    if not(isfile and readfile) or not isfile(CONFIG_FILE) then return false end
    local ok,raw=pcall(readfile,CONFIG_FILE); if not ok then return false end
    local dok,decoded=pcall(HttpService.JSONDecode,HttpService,raw)
    if not dok or type(decoded)~="table" then return false end
    merge(Config,decoded); estimateLightning(); return true
end

function Greedy.CreateUI()
    local ok,Rayfield=pcall(function() return loadstring(game:HttpGet("https://sirius.menu/rayfield"))() end)
    if not ok or not Rayfield then warn("[GreedyGrowers] Rayfield failed to load"); return end
    local Window=Rayfield:CreateWindow({Name="Greedy Growers | Adaptive Profit",LoadingTitle="Greedy Growers",LoadingSubtitle="Adaptive money optimizer",ConfigurationSaving={Enabled=false},Discord={Enabled=false},KeySystem=false})
    local Main=Window:CreateTab("Main",4483362458)
    local Strategy=Window:CreateTab("Strategy",4483362458)
    local StateLabel=Main:CreateLabel("State: "..Runtime.State)
    local SeedLabel=Main:CreateLabel("Seed recommendation: learning")
    local ActionLabel=Main:CreateLabel("Last action: none")
    Main:CreateToggle({Name="Enable optimizer",CurrentValue=Config.Enabled,Callback=function(v) Config.Enabled=v end})
    Main:CreateToggle({Name="Auto harvest on lightning",CurrentValue=Config.AutoHarvest,Callback=function(v) Config.AutoHarvest=v end})
    Main:CreateToggle({Name="Auto buy closest affordable seed",CurrentValue=Config.AutoBuySeed,Callback=function(v) Config.AutoBuySeed=v end})
    Main:CreateToggle({Name="Auto sell inventory",CurrentValue=Config.AutoSell,Callback=function(v) Config.AutoSell=v end})
    Strategy:CreateInput({Name="Cash reserve",PlaceholderText=tostring(Config.CashReserve),RemoveTextAfterFocusLost=false,Callback=function(t) Config.CashReserve=tonumber(t) or Config.CashReserve end})
    Strategy:CreateInput({Name="Sell inventory at",PlaceholderText=tostring(Config.SellThreshold),RemoveTextAfterFocusLost=false,Callback=function(t) Config.SellThreshold=math.max(1,tonumber(t) or Config.SellThreshold) end})
    task.spawn(function()
        while task.wait(.4) do pcall(function()
            StateLabel:Set("State: "..tostring(Runtime.State))
            SeedLabel:Set("Seed recommendation: "..tostring(Runtime.RecommendedSeed or "none").." | $"..tostring(Runtime.RecommendedSeedPrice or "-"))
            local d=Runtime.LastDecision
            ActionLabel:Set("Last action: "..(d and tostring(d.action or d.reason or d.tree) or "none"))
        end) end
    end)
end

Greedy.LoadConfig()
task.spawn(function() while task.wait(.2) do if Config.Enabled then tickController() end end end)
return Greedy
