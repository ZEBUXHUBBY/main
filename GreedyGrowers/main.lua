-- Greedy Growers snapshot-aware monitor/optimizer
-- Event-driven observation. Gameplay actions require an authorized adapter.

local Greedy={}
local HttpService=game:GetService("HttpService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")

local DEFAULTS={
    Enabled=false,AutoOptimize=true,AutoSell=true,AutoHarvest=true,AutoBuySeed=true,
    CashReserve=0,SellThreshold=1,Debug=false,
    LightningSafetyMargin=0.25,
    SeedStats={},TreeStats={},FertilizerStats={},MutationMultipliers={},
    Lightning={samples={},interval=nil,jitter=nil,lastAt=nil,source="none",configInterval=nil},
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
    LightningSamples=0,LightningCountdown=nil,LightningConfidence=0,LightningSource="learning",
    AdapterMode="UNKNOWN",Connections={}
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

local function median(t)
    if #t==0 then return nil end
    local c=table.clone(t); table.sort(c); local n=#c
    if n%2==1 then return c[(n+1)/2] end
    return (c[n/2]+c[n/2+1])/2
end

local function recomputeLightning()
    local L=Config.Lightning
    Runtime.LightningSamples=#L.samples
    if #L.samples>=2 then
        local gaps={}
        for i=2,#L.samples do local g=L.samples[i]-L.samples[i-1]; if g>0.2 then gaps[#gaps+1]=g end end
        local center=median(gaps)
        if center then
            local dev={}; for _,g in ipairs(gaps) do dev[#dev+1]=math.abs(g-center) end
            L.interval=center; L.jitter=median(dev) or 0; L.source="observed"
        end
    elseif L.configInterval then
        L.interval=L.configInterval; L.jitter=0; L.source="WeatherConfig"
    end
    Runtime.LightningSource=L.source or "learning"
end

local function observeLightning(ts)
    ts=tonumber(ts) or os.clock()
    local L=Config.Lightning
    if not L.lastAt or math.abs(ts-L.lastAt)>0.25 then
        L.samples[#L.samples+1]=ts
        if #L.samples>20 then table.remove(L.samples,1) end
        L.lastAt=ts
    end
    recomputeLightning()
end

local function discoverWeatherConfig()
    local ok,module=pcall(function()
        local shared=ReplicatedStorage:FindFirstChild("Shared")
        local info=shared and shared:FindFirstChild("Info")
        local wc=info and info:FindFirstChild("WeatherConfig")
        if not wc or not wc:IsA("ModuleScript") then return nil end
        return require(wc)
    end)
    if not ok or type(module)~="table" then return end
    local candidates={}
    local function walk(t,path,depth)
        if depth>4 then return end
        for k,v in pairs(t) do
            local p=path.."."..tostring(k)
            if type(v)=="number" then
                local low=p:lower()
                if low:find("lightning",1,true) or low:find("storm",1,true) or low:find("interval",1,true) or low:find("cooldown",1,true) then
                    if v>0.2 and v<3600 then candidates[#candidates+1]={path=p,value=v} end
                end
            elseif type(v)=="table" then walk(v,p,depth+1) end
        end
    end
    walk(module,"WeatherConfig",0)
    table.sort(candidates,function(a,b) return a.value<b.value end)
    if #candidates>0 then
        Config.Lightning.configInterval=candidates[1].value
        recomputeLightning()
    end
end

discoverWeatherConfig()

local function updateCountdown()
    local L=Config.Lightning
    if L.interval and L.lastAt then
        local predicted=L.lastAt+L.interval
        local safe=predicted-(L.jitter or 0)-(Config.LightningSafetyMargin or 0)
        Runtime.LightningCountdown=safe-os.clock()
        Runtime.LightningConfidence=math.max(0,math.min(1,1-((L.jitter or 0)/math.max(L.interval,0.001))))
    else
        Runtime.LightningCountdown=nil
        Runtime.LightningConfidence=0
    end
end

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

local function passiveDecisionLoop()
    if not Config.Enabled or not Adapter then return end
    updateCountdown()
    local seed,price=refreshRecommendation()
    Runtime.HeldSeed=type(Adapter.GetHeldSeedName)=="function" and safeCall(Adapter.GetHeldSeedName,Adapter) or Runtime.HeldSeed

    if Runtime.LightningCountdown and Runtime.LightningCountdown<=0.35 and Runtime.ActiveRound then
        Runtime.State="HARVEST WARNING"
        Runtime.LastDecision={action="HARVEST SOON",seconds=Runtime.LightningCountdown,source=Runtime.LightningSource,at=os.clock()}
    end

    if Runtime.State=="HARVEST NOW" or Runtime.State=="GROWING" or Runtime.State=="ROUND STARTED" or Runtime.State=="HARVEST WARNING" then return end

    if Runtime.SelectedItemId~=nil or Runtime.HeldSeed then
        Runtime.State="READY TO PLANT"
        Runtime.LastDecision={action="PLANT",seed=Runtime.HeldSeed or Runtime.ActiveSeed,reason="selected-item-observed",at=os.clock()}
        return
    end

    if seed then
        Runtime.State="BUY RECOMMENDED"
        Runtime.LastDecision={action=(Runtime.AdapterMode=="PASSIVE" and "BUY MANUALLY" or "BUY"),seed=Runtime.RecommendedSeed,price=price,cash=Runtime.Cash,remaining=Runtime.Cash-(price or 0),reason="closest-affordable",at=os.clock()}
    else
        Runtime.State="WAITING SEED OFFER"
        Runtime.LastDecision={action="WAIT",reason="no-affordable-offer",at=os.clock()}
    end
end

local function emergencyHarvest(reason)
    Runtime.State="HARVEST NOW"
    Runtime.LastDecision={action=(Runtime.AdapterMode=="PASSIVE" and "HARVEST MANUALLY NOW" or "HARVEST NOW"),reason=reason,beforeCrash=true,seed=Runtime.ActiveSeed,round=Runtime.ActiveRound,at=os.clock(),executed=false}
    pcall(function() getgenv().GreedyGrowersEmergency=copy(Runtime.LastDecision) end)
end

function Greedy.AttachAdapter(adapter)
    Adapter=adapter; disconnectAll(); if not Adapter then return end
    Runtime.AdapterMode=tostring(Adapter.Mode or "UNKNOWN")

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
            Runtime.State="PURCHASED / READY TO PLANT"
            Runtime.LastDecision={action=(Runtime.AdapterMode=="PASSIVE" and "PLANT MANUALLY" or "PLANT"),selectedItemId=id,seed=Runtime.RecommendedSeed,at=os.clock()}
        elseif Runtime.ActiveRound then Runtime.State="ROUND STARTED" end
    end)
    bind(Adapter.RoundStarted,function(round)
        local before=Runtime.Cash
        Runtime.Cash=tonumber(safeCall(Adapter.GetCash,Adapter)) or Runtime.Cash
        if before and Runtime.Cash and before>Runtime.Cash then Runtime.ObservedPlantCost=before-Runtime.Cash end
        Runtime.ActiveRound=round; Runtime.ActiveSeed=round and round.seedKey or Runtime.RecommendedSeed
        Runtime.SelectedItemId=nil; Runtime.HeldSeed=nil; Runtime.State="GROWING"
        Runtime.LastDecision={action="WAIT / WATCH LIGHTNING",seed=Runtime.ActiveSeed,roundId=round and round.roundId,at=os.clock()}
    end)
    bind(Adapter.PlantStopped,function(roundId,value)
        Runtime.State="PLANT STOPPED / DANGER"; Runtime.LastDecision={action="PREPARE HARVEST",roundId=roundId,observedNumber=value,at=os.clock()}
    end)
    bind(Adapter.LightningObserved,function(ts) observeLightning(ts); emergencyHarvest("Event(lightning)") end)
    bind(Adapter.PlantCrashed,function(roundId,value)
        Runtime.State="CRASHED"; Runtime.LastDecision={action="ROUND LOST / RESET",roundId=roundId,observedNumber=value,at=os.clock()}
    end)
    bind(Adapter.RoundReset,function(roundId)
        Runtime.ActiveRound=nil; Runtime.ActiveSeed=nil; Runtime.SelectedItemId=nil; Runtime.HeldSeed=nil
        Runtime.State="RESET"; Runtime.LastDecision={action="BUY AGAIN",roundId=roundId,at=os.clock()}
    end)
    bind(Adapter.DataUpdated,function() Runtime.Cash=tonumber(safeCall(Adapter.GetCash,Adapter)) or Runtime.Cash end)
end

function Greedy.SetConfig(v) merge(Config,v or {}); recomputeLightning() end
function Greedy.GetConfig() return copy(Config) end
function Greedy.GetRuntime() updateCountdown(); return copy(Runtime) end
function Greedy.ChooseAffordableSeed(offers,cash) return chooseAffordable(offers,cash) end

local CONFIG_FILE="GreedyGrowers/config.json"
function Greedy.SaveConfig() if not(writefile and makefolder) then return false end pcall(makefolder,"GreedyGrowers") local ok,s=pcall(HttpService.JSONEncode,HttpService,Config) return ok and pcall(writefile,CONFIG_FILE,s) or false end
function Greedy.LoadConfig() if not(isfile and readfile) or not isfile(CONFIG_FILE) then return false end local ok,r=pcall(readfile,CONFIG_FILE); if not ok then return false end local dok,d=pcall(HttpService.JSONDecode,HttpService,r); if not dok or type(d)~="table" then return false end merge(Config,d); recomputeLightning(); return true end

function Greedy.CreateUI()
    local ok,Rayfield=pcall(function() return loadstring(game:HttpGet("https://sirius.menu/rayfield"))() end)
    if not ok or not Rayfield then warn("[GreedyGrowers] Rayfield failed to load"); return end
    local W=Rayfield:CreateWindow({Name="Greedy Growers | Snapshot Optimizer",LoadingTitle="Greedy Growers",LoadingSubtitle="Event-driven monitor",ConfigurationSaving={Enabled=false},Discord={Enabled=false},KeySystem=false})
    local Main=W:CreateTab("Main",4483362458); local Strategy=W:CreateTab("Strategy",4483362458)
    local L1=Main:CreateLabel("State: "..Runtime.State)
    local L2=Main:CreateLabel("Cash: $0")
    local L3=Main:CreateLabel("Seed recommendation: learning")
    local L4=Main:CreateLabel("Next action: none")
    local L5=Main:CreateLabel("Lightning predictor: learning 0/2")
    local L6=Main:CreateLabel("Adapter: unknown")
    Main:CreateToggle({Name="Enable optimizer",CurrentValue=Config.Enabled,Callback=function(v) Config.Enabled=v end})
    Main:CreateToggle({Name="Lightning warning / harvest signal",CurrentValue=Config.AutoHarvest,Callback=function(v) Config.AutoHarvest=v end})
    Main:CreateToggle({Name="Recommend closest affordable seed",CurrentValue=Config.AutoBuySeed,Callback=function(v) Config.AutoBuySeed=v end})
    Strategy:CreateInput({Name="Cash reserve",PlaceholderText=tostring(Config.CashReserve),RemoveTextAfterFocusLost=false,Callback=function(t) Config.CashReserve=tonumber(t) or Config.CashReserve end})
    Strategy:CreateInput({Name="Lightning safety margin",PlaceholderText=tostring(Config.LightningSafetyMargin),RemoveTextAfterFocusLost=false,Callback=function(t) Config.LightningSafetyMargin=tonumber(t) or Config.LightningSafetyMargin end})
    task.spawn(function() while task.wait(.15) do pcall(function()
        updateCountdown()
        L1:Set("State: "..tostring(Runtime.State)); L2:Set("Cash: $"..tostring(Runtime.Cash or 0))
        L3:Set("Seed recommendation: "..tostring(Runtime.RecommendedSeed or "none").." | $"..tostring(Runtime.RecommendedSeedPrice or "-"))
        local d=Runtime.LastDecision; L4:Set("Next action: "..(d and tostring(d.action or d.reason) or "none"))
        if Runtime.LightningCountdown then
            L5:Set(string.format("Lightning safe window: %.2fs | %.0f%% | %s",Runtime.LightningCountdown,Runtime.LightningConfidence*100,tostring(Runtime.LightningSource)))
        else
            L5:Set("Lightning predictor: learning "..tostring(Runtime.LightningSamples).."/2 | source "..tostring(Runtime.LightningSource))
        end
        L6:Set("Adapter: "..tostring(Runtime.AdapterMode)..(Runtime.AdapterMode=="PASSIVE" and " | recommendations only" or ""))
    end) end end)
end

Greedy.LoadConfig()
task.spawn(function() while task.wait(.15) do if Config.Enabled then passiveDecisionLoop() end end end)
return Greedy
