-- Greedy Growers snapshot-aware monitor/optimizer
-- Event-driven observation. Gameplay actions require an authorized adapter.

local Greedy={}
local HttpService=game:GetService("HttpService")

local DEFAULTS={
    Enabled=false,AutoOptimize=true,AutoSell=true,AutoHarvest=true,AutoBuySeed=true,
    CashReserve=0,SellThreshold=1,Debug=false,
    SeedStats={},TreeStats={},FertilizerStats={},MutationMultipliers={},
}
local function copy(v) if type(v)~="table" then return v end local o={} for k,x in pairs(v) do o[k]=copy(x) end return o end
local function merge(a,b) for k,v in pairs(b or {}) do if type(v)=="table" and type(a[k])=="table" then merge(a[k],v) else a[k]=copy(v) end end return a end
local Config=copy(DEFAULTS)
local Adapter

local Runtime={
    State="IDLE",Cash=0,RecommendedSeed=nil,RecommendedSeedPrice=nil,
    SelectedItemId=nil,HeldSeed=nil,ActiveRound=nil,ActiveSeed=nil,
    LastDecision=nil,LastActionError=nil,ObservedPlantCost=nil,
    BuyCount=0,HarvestCount=0,SellCount=0,MoneyEarned=0,
    Connections={}
}

local function safeCall(fn,...)
    if type(fn)~="function" then return nil,"unavailable" end
    local ok,a,b,c=pcall(fn,...)
    if not ok then Runtime.LastActionError=tostring(a); warn("[GreedyGrowers]",a); return nil,a end
    return a,b,c
end
local function bind(signal,fn)
    if not signal then return end
    local ok,c=pcall(function() return signal:Connect(fn) end)
    if ok and c then Runtime.Connections[#Runtime.Connections+1]=c end
end
local function disconnectAll() for _,c in ipairs(Runtime.Connections) do pcall(function() c:Disconnect() end) end table.clear(Runtime.Connections) end

local function seedPrice(s) return tonumber(s and (s.price or s.cost or s.Price or s.Cost)) end
local function chooseAffordable(offers,cash)
    local budget=math.max(0,(tonumber(cash) or 0)-(tonumber(Config.CashReserve) or 0))
    local best,bp=nil,-math.huge
    for _,s in ipairs(offers or {}) do local p=seedPrice(s); if p and p<=budget and p>bp then best,bp=s,p end end
    return best,bp==-math.huge and nil or bp
end

local function refreshRecommendation()
    if not Adapter then return end
    Runtime.Cash=tonumber(safeCall(Adapter.GetCash,Adapter)) or Runtime.Cash or 0
    local offers=type(Adapter.GetSeedOffers)=="function" and (safeCall(Adapter.GetSeedOffers,Adapter) or {}) or {}
    local s,p=chooseAffordable(offers,Runtime.Cash)
    Runtime.RecommendedSeed=s and (s.key or s.seedKey or s.name) or nil
    Runtime.RecommendedSeedPrice=p
    return s,p
end

local lastBuyAttempt=0
local function passiveDecisionLoop()
    if not Config.Enabled or not Adapter then return end
    local seed,price=refreshRecommendation()
    Runtime.HeldSeed=type(Adapter.GetHeldSeedName)=="function" and safeCall(Adapter.GetHeldSeedName,Adapter) or Runtime.HeldSeed

    if Runtime.State=="HARVEST NOW" or Runtime.State=="GROWING" or Runtime.State=="ROUND STARTED" then return end

    if Runtime.SelectedItemId~=nil or Runtime.HeldSeed then
        Runtime.State="READY TO PLANT"
        Runtime.LastDecision={action="PLANT",seed=Runtime.HeldSeed or Runtime.ActiveSeed,reason="selected-item-observed",at=os.clock()}
        if type(Adapter.PlantSeed)=="function" then safeCall(Adapter.PlantSeed,Adapter,Runtime.HeldSeed or Runtime.ActiveSeed) end
        return
    end

    if seed then
        Runtime.State="BUY RECOMMENDED"
        Runtime.LastDecision={action="BUY",seed=Runtime.RecommendedSeed,price=price,cash=Runtime.Cash,remaining=Runtime.Cash-(price or 0),reason="closest-affordable",at=os.clock()}
        if Config.AutoBuySeed and type(Adapter.BuySeed)=="function" and os.clock()-lastBuyAttempt>=1 then
            lastBuyAttempt=os.clock(); local ok=safeCall(Adapter.BuySeed,Adapter,seed); if ok then Runtime.BuyCount+=1 end
        end
    else
        Runtime.State="WAITING SEED OFFER"
        Runtime.LastDecision={action="WAIT",reason="no-affordable-offer",at=os.clock()}
    end
end

local function emergencyHarvest(reason)
    Runtime.State="HARVEST NOW"
    Runtime.LastDecision={action="HARVEST NOW",reason=reason,beforeCrash=true,seed=Runtime.ActiveSeed,round=Runtime.ActiveRound,at=os.clock(),executed=false}
    if Config.AutoHarvest and Adapter and type(Adapter.HarvestTree)=="function" then
        local trees=type(Adapter.GetTrees)=="function" and (safeCall(Adapter.GetTrees,Adapter) or {}) or {}
        local any=false
        for _,t in ipairs(trees) do
            local ok,amount=safeCall(Adapter.HarvestTree,Adapter,t)
            if ok then any=true; Runtime.HarvestCount+=1; Runtime.MoneyEarned+=tonumber(amount) or 0 end
        end
        Runtime.LastDecision.executed=any
    end
    pcall(function() getgenv().GreedyGrowersEmergency=copy(Runtime.LastDecision) end)
end

function Greedy.AttachAdapter(adapter)
    Adapter=adapter; disconnectAll(); if not Adapter then return end

    bind(Adapter.SeedSpawned,function(data)
        refreshRecommendation()
        if Runtime.State=="WAITING SEED OFFER" or Runtime.State=="IDLE" or Runtime.State=="RESET" then
            Runtime.State="SEED OFFER OBSERVED"
            Runtime.LastDecision={action="EVALUATE BUY",seed=data and data.seedKey,rarity=data and data.rarity,spawnId=data and data.spawnId,at=os.clock()}
        end
    end)

    bind(Adapter.SelectedItemChanged,function(id)
        Runtime.SelectedItemId=id
        if id~=nil then
            Runtime.Cash=tonumber(safeCall(Adapter.GetCash,Adapter)) or Runtime.Cash
            Runtime.HeldSeed=type(Adapter.GetHeldSeedName)=="function" and safeCall(Adapter.GetHeldSeedName,Adapter) or Runtime.HeldSeed
            Runtime.State="PURCHASED / READY TO PLANT"
            Runtime.LastDecision={action="PLANT",selectedItemId=id,seed=Runtime.HeldSeed or Runtime.RecommendedSeed,at=os.clock()}
        elseif Runtime.ActiveRound then
            Runtime.State="ROUND STARTED"
        end
    end)

    bind(Adapter.RoundStarted,function(round)
        local before=Runtime.Cash
        Runtime.Cash=tonumber(safeCall(Adapter.GetCash,Adapter)) or Runtime.Cash
        if before and Runtime.Cash and before>Runtime.Cash then Runtime.ObservedPlantCost=before-Runtime.Cash end
        Runtime.ActiveRound=round
        Runtime.ActiveSeed=round and round.seedKey or Runtime.HeldSeed or Runtime.RecommendedSeed
        Runtime.SelectedItemId=nil; Runtime.HeldSeed=nil
        Runtime.State="GROWING"
        Runtime.LastDecision={action="WAIT FOR LIGHTNING / READY",seed=Runtime.ActiveSeed,roundId=round and round.roundId,observedNumber=round and round.observedNumber,observedPlantCost=Runtime.ObservedPlantCost,at=os.clock()}
    end)

    bind(Adapter.PlantStopped,function(roundId,value)
        if Runtime.ActiveRound and Runtime.ActiveRound.roundId==roundId then
            Runtime.State="PLANT STOPPED / DANGER"
            Runtime.LastDecision={action="PREPARE HARVEST",roundId=roundId,observedNumber=value,at=os.clock()}
        end
    end)

    bind(Adapter.LightningObserved,function(ts)
        emergencyHarvest("Event(lightning)")
    end)

    bind(Adapter.PlantCrashed,function(roundId,value)
        Runtime.State="CRASHED"
        Runtime.LastDecision={action="ROUND LOST / RESET",roundId=roundId,observedNumber=value,at=os.clock()}
    end)

    bind(Adapter.RoundReset,function(roundId)
        Runtime.ActiveRound=nil; Runtime.ActiveSeed=nil; Runtime.SelectedItemId=nil; Runtime.HeldSeed=nil
        Runtime.State="RESET"
        Runtime.LastDecision={action="BUY AGAIN",roundId=roundId,at=os.clock()}
    end)

    bind(Adapter.DataUpdated,function()
        Runtime.Cash=tonumber(safeCall(Adapter.GetCash,Adapter)) or Runtime.Cash
        Runtime.HeldSeed=type(Adapter.GetHeldSeedName)=="function" and safeCall(Adapter.GetHeldSeedName,Adapter) or Runtime.HeldSeed
    end)
end

function Greedy.SetConfig(v) merge(Config,v or {}) end
function Greedy.GetConfig() return copy(Config) end
function Greedy.GetRuntime() return copy(Runtime) end
function Greedy.ChooseAffordableSeed(offers,cash) return chooseAffordable(offers,cash) end

local CONFIG_FILE="GreedyGrowers/config.json"
function Greedy.SaveConfig() if not(writefile and makefolder) then return false end pcall(makefolder,"GreedyGrowers") local ok,s=pcall(HttpService.JSONEncode,HttpService,Config) return ok and pcall(writefile,CONFIG_FILE,s) or false end
function Greedy.LoadConfig() if not(isfile and readfile) or not isfile(CONFIG_FILE) then return false end local ok,r=pcall(readfile,CONFIG_FILE); if not ok then return false end local dok,d=pcall(HttpService.JSONDecode,HttpService,r); if not dok or type(d)~="table" then return false end merge(Config,d); return true end

function Greedy.CreateUI()
    local ok,Rayfield=pcall(function() return loadstring(game:HttpGet("https://sirius.menu/rayfield"))() end)
    if not ok or not Rayfield then warn("[GreedyGrowers] Rayfield failed to load"); return end
    local W=Rayfield:CreateWindow({Name="Greedy Growers | Snapshot Optimizer",LoadingTitle="Greedy Growers",LoadingSubtitle="Event-driven monitor",ConfigurationSaving={Enabled=false},Discord={Enabled=false},KeySystem=false})
    local Main=W:CreateTab("Main",4483362458); local Strategy=W:CreateTab("Strategy",4483362458)
    local L1=Main:CreateLabel("State: "..Runtime.State)
    local L2=Main:CreateLabel("Cash: $0")
    local L3=Main:CreateLabel("Seed recommendation: learning")
    local L4=Main:CreateLabel("Next action: none")
    local L5=Main:CreateLabel("Observed plant/fertilizer cost: -")
    Main:CreateToggle({Name="Enable optimizer",CurrentValue=Config.Enabled,Callback=function(v) Config.Enabled=v end})
    Main:CreateToggle({Name="Auto harvest on lightning",CurrentValue=Config.AutoHarvest,Callback=function(v) Config.AutoHarvest=v end})
    Main:CreateToggle({Name="Auto buy closest affordable seed",CurrentValue=Config.AutoBuySeed,Callback=function(v) Config.AutoBuySeed=v end})
    Strategy:CreateInput({Name="Cash reserve",PlaceholderText=tostring(Config.CashReserve),RemoveTextAfterFocusLost=false,Callback=function(t) Config.CashReserve=tonumber(t) or Config.CashReserve end})
    task.spawn(function() while task.wait(.25) do pcall(function()
        L1:Set("State: "..tostring(Runtime.State)); L2:Set("Cash: $"..tostring(Runtime.Cash or 0))
        L3:Set("Seed recommendation: "..tostring(Runtime.RecommendedSeed or "none").." | $"..tostring(Runtime.RecommendedSeedPrice or "-"))
        local d=Runtime.LastDecision; L4:Set("Next action: "..(d and tostring(d.action or d.reason) or "none"))
        L5:Set("Observed plant/fertilizer cost: "..tostring(Runtime.ObservedPlantCost or "-"))
    end) end end)
end

Greedy.LoadConfig()
task.spawn(function() while task.wait(.2) do if Config.Enabled then passiveDecisionLoop() end end end)
return Greedy
