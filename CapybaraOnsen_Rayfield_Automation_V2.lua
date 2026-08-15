-- Capybara Onsen | Rayfield Automation + QA V2
-- Uses only observed drop remotes + physical plot buttons.
-- No forged drop IDs, no replay spam, no guessed purchase/dev remote arguments.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local DropSpawned = Remotes:WaitForChild("DropSpawned")
local DropPickup = Remotes:WaitForChild("DropPickup")
local CarryUpdated = Remotes:WaitForChild("CarryUpdated")
local DataUpdated = Remotes:WaitForChild("DataUpdated")
local GetData = Remotes:WaitForChild("GetData")
local NotifyRemote = Remotes:FindFirstChild("Notify")

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local Window = Rayfield:CreateWindow({
    Name = "Capybara Onsen | Automation V2",
    LoadingTitle = "Capybara Onsen",
    LoadingSubtitle = "Automation + QA",
    Theme = "Default",
    ToggleUIKeybind = "K",
    DisableRayfieldPrompts = false,
    DisableBuildWarnings = false,
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "CapybaraOnsenV2",
        FileName = "settings"
    },
    Discord = {Enabled = false},
    KeySystem = false
})

local AutoTab = Window:CreateTab("Automation")
local StateTab = Window:CreateTab("Dashboard")
local UpgradeTab = Window:CreateTab("Upgrades")
local BugTab = Window:CreateTab("Bug Finder")
local LogTab = Window:CreateTab("Logs")

local S = {
    autoPickup = true,
    autoDeposit = false,
    autoCashier = false,
    autoUpgrade = false,
    autoTierUpgrade = false,
    autoRefresh = true,
    refreshEvery = 1.5,
    carryThreshold = 12,
    depositCooldown = 1.0,
    cashierCooldown = 1.5,
    upgradeCooldown = 2.0,
    pickupTimeout = 2.0,
    pickupDelay = 0.03,

    data = nil,
    carry = 0,
    carryTier = nil,
    pending = {},
    sent = {},
    seen = {},
    pathTypes = {},

    spawned = 0,
    pickupSent = 0,
    pickupAccepted = 0,
    pickupTimeouts = 0,
    maxAcceptedDistance = 0,
    remotePickupConfirmed = false,
    duplicateIds = 0,
    plotMismatch = 0,

    sessionStart = os.clock(),
    startEarned = nil,
    lastEarned = nil,
    lastRefresh = 0,
    lastDeposit = 0,
    lastCashier = 0,
    lastUpgrade = 0,
    lastTierUpgrade = 0,

    findings = {},
    logs = {},
    notifyFindings = true,
}

local function now() return os.clock() end
local function finite(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
local function short(v,n)
    local x=tostring(v)
    if #x>n then return x:sub(1,n-3).."..." end
    return x
end
local function log(kind,msg)
    table.insert(S.logs,1,string.format("[%s] %s",kind,msg))
    if #S.logs>80 then table.remove(S.logs) end
end
local function toast(title,msg,dur)
    Rayfield:Notify({Title=title,Content=msg,Duration=dur or 4})
end
local function finding(level,key,msg)
    if S.findings[key] then return end
    S.findings[key]={level=level,msg=msg}
    log("FINDING",level.." | "..msg)
    if S.notifyFindings then toast("Bug Finder | "..level,msg,5) end
end

local function deepGet(t,...)
    local x=t
    for i=1,select("#",...) do
        if type(x)~="table" then return nil end
        x=x[select(i,...)]
    end
    return x
end

local function getRoot()
    local c=LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function plotName()
    local p=LP:GetAttribute("Plot")
    return p and tostring(p) or "?"
end
local function plotModel()
    local tycoon=workspace:FindFirstChild("Tycoon")
    local tycoons=tycoon and tycoon:FindFirstChild("Tycoons")
    return tycoons and tycoons:FindFirstChild(plotName()) or nil
end
local function buttonsModel()
    local p=plotModel()
    return p and p:FindFirstChild("Buttons") or nil
end

local function belongsToOurPlot(inst)
    if typeof(inst)~="Instance" then return nil end
    local cur=inst
    while cur and cur~=workspace do
        if cur.Parent and cur.Parent.Name=="Tycoons" then
            return cur.Name==plotName()
        end
        cur=cur.Parent
    end
    return nil
end

local function safeGetData()
    local ok,res=pcall(function() return GetData:InvokeServer() end)
    if not ok then log("ERROR","GetData: "..short(res,100)); return nil end
    if type(res)~="table" then
        finding("MEDIUM","getdata_type","GetData returned "..typeof(res))
        return nil
    end
    S.data=res
    if S.startEarned==nil and finite(res.TotalEarned) then S.startEarned=res.TotalEarned end
    if finite(res.TotalEarned) then S.lastEarned=res.TotalEarned end
    local c=deepGet(res,"Tycoon","Carry")
    if finite(c) then S.carry=c end
    return res
end

local function touchButton(name)
    local buttons=buttonsModel()
    local model=buttons and buttons:FindFirstChild(name)
    if not model then
        log("BLOCK","Button not found: "..name)
        return false
    end
    local head=model:FindFirstChild("Head",true) or model:FindFirstChild("Base",true)
    if not head or not head:IsA("BasePart") then
        log("BLOCK","No touch part for "..name)
        return false
    end

    -- Prefer executor touch simulation; avoids moving the player.
    if type(firetouchinterest)=="function" then
        local root=getRoot()
        if not root then return false end
        local ok,err=pcall(function()
            firetouchinterest(root,head,0)
            task.wait()
            firetouchinterest(root,head,1)
        end)
        if ok then
            log("TOUCH",name)
            return true
        end
        log("ERROR","firetouchinterest "..name..": "..short(err,90))
        return false
    end

    log("BLOCK","firetouchinterest unavailable")
    return false
end

local function sendPickup(id,reason)
    local m=S.pending[id]
    if not m then return false end
    if m.ownPlot==false then return false end
    if S.sent[id] then return false end

    S.sent[id]={sentAt=now(),meta=m}
    S.pickupSent+=1
    DropPickup:FireServer(id)
    log("OUT",string.format("DropPickup(%s) [%s]",id,reason or "auto"))
    return true
end

-- ===== UI =====
AutoTab:CreateSection("Main loop")
AutoTab:CreateToggle({Name="Auto Pickup",CurrentValue=true,Flag="AutoPickup",Callback=function(v) S.autoPickup=v end})
AutoTab:CreateToggle({Name="Auto Deposit when carry threshold reached",CurrentValue=false,Flag="AutoDeposit",Callback=function(v) S.autoDeposit=v end})
AutoTab:CreateToggle({Name="Auto Cashier",CurrentValue=false,Flag="AutoCashier",Callback=function(v) S.autoCashier=v end})
AutoTab:CreateSlider({Name="Deposit carry threshold",Range={1,50},Increment=1,CurrentValue=12,Flag="CarryThreshold",Callback=function(v) S.carryThreshold=v end})
AutoTab:CreateSlider({Name="Pickup delay",Range={0,1},Increment=0.01,Suffix="s",CurrentValue=0.03,Flag="PickupDelay",Callback=function(v) S.pickupDelay=v end})
AutoTab:CreateToggle({Name="Auto refresh state",CurrentValue=true,Flag="AutoRefresh",Callback=function(v) S.autoRefresh=v end})
AutoTab:CreateSlider({Name="Refresh interval",Range={0.5,10},Increment=0.5,Suffix="s",CurrentValue=1.5,Flag="RefreshEvery",Callback=function(v) S.refreshEvery=v end})
AutoTab:CreateButton({Name="Deposit now",Callback=function() touchButton("Deposit") end})
AutoTab:CreateButton({Name="Cashier now",Callback=function() touchButton("Cashier") end})
AutoTab:CreateButton({Name="Refresh state now",Callback=function() safeGetData() end})

UpgradeTab:CreateSection("Optional spending")
UpgradeTab:CreateToggle({Name="Auto Upgrade",CurrentValue=false,Flag="AutoUpgrade",Callback=function(v) S.autoUpgrade=v end})
UpgradeTab:CreateToggle({Name="Auto Tier Upgrader",CurrentValue=false,Flag="AutoTierUpgrade",Callback=function(v) S.autoTierUpgrade=v end})
UpgradeTab:CreateSlider({Name="Upgrade attempt cooldown",Range={1,20},Increment=0.5,Suffix="s",CurrentValue=2,Flag="UpgradeCooldown",Callback=function(v) S.upgradeCooldown=v end})
UpgradeTab:CreateButton({Name="Try Upgrade once",Callback=function() touchButton("Upgrade") end})
UpgradeTab:CreateButton({Name="Try Tier Upgrader once",Callback=function() touchButton("TierUpgrader") end})
UpgradeTab:CreateParagraph({Title="Safety",Content="Upgrade automation is OFF by default. The game decides affordability server-side; this script does not forge cash or purchase arguments."})

local Dash=StateTab:CreateParagraph({Title="Live",Content="Starting..."})
local BugP=BugTab:CreateParagraph({Title="QA status",Content="Waiting for pickups..."})
local LogP=LogTab:CreateParagraph({Title="Recent events",Content="Waiting..."})

BugTab:CreateToggle({Name="Notify new findings",CurrentValue=true,Flag="NotifyFindings",Callback=function(v) S.notifyFindings=v end})
BugTab:CreateButton({Name="Clear findings",Callback=function() table.clear(S.findings) end})
BugTab:CreateParagraph({Title="Remote pickup detector",Content="A single status is shown after a distant observed drop is followed by CarryUpdated. Max accepted distance continues updating silently instead of creating one finding per drop."})

LogTab:CreateButton({Name="Clear logs",Callback=function() table.clear(S.logs) end})

local function ratePerMinute()
    local elapsed=math.max(now()-S.sessionStart,1)
    if finite(S.lastEarned) and finite(S.startEarned) then
        return (S.lastEarned-S.startEarned)/(elapsed/60)
    end
    return 0
end
local function dropsPerMinute()
    return S.spawned/(math.max(now()-S.sessionStart,1)/60)
end
local function successRate()
    local done=S.pickupAccepted+S.pickupTimeouts
    if done<=0 then return 0 end
    return S.pickupAccepted/done*100
end

local function render()
    local d=S.data
    local cash=d and d.Cash or "?"
    local total=d and d.TotalEarned or "?"
    local pc=d and deepGet(d,"Tycoon","Shop","PendingCash") or "?"
    local pd=d and deepGet(d,"Tycoon","Shop","PendingDrop") or "?"
    local bt=d and deepGet(d,"Tycoon","Shop","BuyTier") or "?"
    local uc=d and deepGet(d,"Tycoon","Shop","UpgradeCount") or "?"
    local active=0 for _ in pairs(S.pending) do active+=1 end

    Dash:Set({
        Title="Live | Plot "..plotName(),
        Content=table.concat({
            "Cash: "..tostring(cash).." | TotalEarned: "..tostring(total),
            "Carry: "..tostring(S.carry).." | Tier: "..tostring(S.carryTier),
            "PendingCash: "..tostring(pc).." | PendingDrop: "..tostring(pd),
            "BuyTier: "..tostring(bt).." | UpgradeCount: "..tostring(uc),
            string.format("¥/min: %.2f | Drops/min: %.2f",ratePerMinute(),dropsPerMinute()),
            string.format("Pickup: %d sent / %d accepted / %d timeout | %.1f%%",S.pickupSent,S.pickupAccepted,S.pickupTimeouts,successRate()),
            string.format("Active drops: %d | Max accepted distance: %.1f studs",active,S.maxAcceptedDistance),
            "Remote Pickup: "..(S.remotePickupConfirmed and "CONFIRMED" or "observing")
        },"\n")
    })

    local rows={}
    if S.remotePickupConfirmed then
        rows[#rows+1]=string.format("[INFO] Remote pickup accepted; max observed distance %.1f studs",S.maxAcceptedDistance)
    else
        rows[#rows+1]="[INFO] Remote pickup not confirmed yet"
    end
    rows[#rows+1]=string.format("Duplicate IDs: %d | Cross-plot refs: %d",S.duplicateIds,S.plotMismatch)
    for _,f in pairs(S.findings) do rows[#rows+1]="["..f.level.."] "..f.msg end
    if #rows>12 then while #rows>12 do table.remove(rows) end end
    BugP:Set({Title="QA status",Content=table.concat(rows,"\n")})

    local logs={}
    for i=1,math.min(#S.logs,26) do logs[i]=S.logs[i] end
    if #logs==0 then logs[1]="No events." end
    LogP:Set({Title="Recent events",Content=table.concat(logs,"\n")})
end

-- ===== EVENTS =====
DropSpawned.OnClientEvent:Connect(function(id,tier,pos,unit,slot)
    if type(id)~="number" then finding("HIGH","drop_type","DropSpawned ID is "..typeof(id)); return end
    S.spawned+=1
    S.seen[id]=(S.seen[id] or 0)+1
    if S.seen[id]>1 then
        S.duplicateIds+=1
        finding("HIGH","dup_"..id,"Drop ID reused: "..id)
    end

    local own=belongsToOurPlot(slot)
    if own==false then
        S.plotMismatch+=1
        finding("HIGH","plot_"..id,"Drop references another plot: "..id)
    end

    local dist=nil
    local root=getRoot()
    if root and typeof(pos)=="Vector3" then dist=(root.Position-pos).Magnitude end

    S.pending[id]={id=id,tier=tostring(tier),position=pos,unit=unit,slot=slot,ownPlot=own,spawnAt=now(),distance=dist}
    log("DROP",string.format("id=%s tier=%s dist=%s",id,tostring(tier),dist and string.format("%.1f",dist) or "?"))

    if S.autoPickup and own~=false then
        task.delay(S.pickupDelay,function() sendPickup(id,"auto") end)
    end
end)

CarryUpdated.OnClientEvent:Connect(function(count,tier)
    local old=S.carry
    if finite(count) then S.carry=count end
    S.carryTier=tier

    -- Match the most recent outstanding pickup request.
    local t=now()
    local bestId,bestAge=nil,math.huge
    for id,info in pairs(S.sent) do
        if not info.accepted then
            local age=t-info.sentAt
            if age>=0 and age<bestAge and age<=1.5 then bestId,bestAge=id,age end
        end
    end

    if bestId then
        local info=S.sent[bestId]
        info.accepted=true
        S.pickupAccepted+=1
        local m=info.meta
        if m and finite(m.distance) then
            if m.distance>S.maxAcceptedDistance then S.maxAcceptedDistance=m.distance end
            if m.distance>20 then S.remotePickupConfirmed=true end
        end
        S.pending[bestId]=nil
        log("ACK",string.format("pickup %s accepted in %.2fs",bestId,bestAge))
    end

    if finite(old) and finite(count) and count-old>50 then
        finding("MEDIUM","carry_jump","Carry jumped "..old.." -> "..count)
    end
end)

DataUpdated.OnClientEvent:Connect(function(path,value)
    if type(path)~="string" then return end
    local typ=typeof(value)
    local old=S.pathTypes[path]
    if old and old~=typ then finding("MEDIUM","type_"..path,"Type changed for "..path..": "..old.." -> "..typ) end
    S.pathTypes[path]=typ
    if type(value)=="number" and not finite(value) then finding("HIGH","nan_"..path,"Non-finite value at "..path) end
end)

if NotifyRemote and NotifyRemote:IsA("RemoteEvent") then
    NotifyRemote.OnClientEvent:Connect(function(msg,kind)
        log("NOTIFY",tostring(kind).." | "..short(msg,75))
    end)
end

-- ===== MAIN LOOP =====
task.spawn(function()
    while task.wait(0.1) do
        local t=now()

        -- Timeout accounting only; no retries/replays.
        for id,info in pairs(S.sent) do
            if not info.accepted and not info.timedOut and t-info.sentAt>=S.pickupTimeout then
                info.timedOut=true
                S.pickupTimeouts+=1
                log("TIMEOUT","pickup "..id)
                S.pending[id]=nil
            end
        end

        if S.autoRefresh and t-S.lastRefresh>=S.refreshEvery then
            S.lastRefresh=t
            safeGetData()
        end

        if S.autoDeposit and finite(S.carry) and S.carry>=S.carryThreshold and t-S.lastDeposit>=S.depositCooldown then
            S.lastDeposit=t
            touchButton("Deposit")
        end

        if S.autoCashier and t-S.lastCashier>=S.cashierCooldown then
            local pendingCash=S.data and deepGet(S.data,"Tycoon","Shop","PendingCash")
            if finite(pendingCash) and pendingCash>0 then
                S.lastCashier=t
                touchButton("Cashier")
            end
        end

        if S.autoUpgrade and t-S.lastUpgrade>=S.upgradeCooldown then
            S.lastUpgrade=t
            touchButton("Upgrade")
        end

        if S.autoTierUpgrade and t-S.lastTierUpgrade>=S.upgradeCooldown then
            S.lastTierUpgrade=t
            touchButton("TierUpgrader")
        end
    end
end)

task.spawn(function()
    while task.wait(0.25) do render() end
end)

safeGetData()
log("READY","Loaded for Plot "..plotName())
toast("Capybara Onsen V2","Loaded. Auto Pickup ON; spending automation OFF.",5)

pcall(function() Rayfield:LoadConfiguration() end)
