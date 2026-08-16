-- Beeconomy Event-Based Auto Learner V2 (Rayfield)
-- Learns current-session action episodes from normal gameplay.
-- State transitions anchor actions; repetitive unanchored traffic is treated as background.
-- Observer only: this script does not replay learned/unknown remotes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
local PLACE_ID = 101558830312092
if game.PlaceId ~= PLACE_ID then warn("[Beeconomy Learner] Unexpected place:", game.PlaceId) end

local CFG = {
    Enabled = true,
    PreWindow = 0.35,
    PostWindow = 0.90,
    MaxEvents = 1800,
    MaxEpisodes = 200,
    AutoExport = false,
    ExportEvery = 60,
    Verbose = false,
    BackgroundThreshold = 8,
}

local Runtime = {
    started = os.clock(),
    events = {},
    episodes = {},
    learned = {},
    patterns = {},
    lastInput = nil,
    lastExport = 0,
    hookInstalled = false,
    activeEpisode = nil,
    previousState = {},
}

local TRACKED_ATTRS = {
    "EquippedPickaxeId","ShovelEquipped","EquippedAxeId","EquippedTitle",
    "EquippedNetId","EquippedFishingRodId","ActiveHoldRevision",
    "BeeCombatTargetMobId","BeeCombatTargetFieldDb","SelectedMobId","GripHoldKind",
}

local ACTION_DRIVEN = {
    ActiveHoldRevision=true,
    GripHoldKind=true,
    ShovelEquipped=true,
}

local COMBAT_PERIODIC = {
    BeeCombatTargetMobId=true,
    BeeCombatTargetFieldDb=true,
    SelectedMobId=true,
}

local KNOWN_BACKGROUND_A3 = {
    tool=true,
    recieveSnapshot=true,
    receiveSnapshot=true,
    MatildasMarket=true,
}

local HOTBAR_KIND = {
    One="shovel", Two="axe", Three="pickaxe", Four="fishing", Five="net", Six="hoverboard",
}

local function now() return os.clock() - Runtime.started end
local function log(...) print("[Beeconomy Learner]", ...) end

local function safe(v, depth)
    depth = depth or 0
    if depth > 4 then return "<deep>" end
    local tv = typeof(v)
    if tv == "Vector3" then return {__type="Vector3",x=v.X,y=v.Y,z=v.Z} end
    if tv == "CFrame" then return {__type="CFrame",components={v:GetComponents()}} end
    if tv == "Instance" then return {__type="Instance",class=v.ClassName,path=v:GetFullName()} end
    if tv == "EnumItem" then return tostring(v) end
    if tv == "table" then
        local out,n = {},0
        for k,val in pairs(v) do
            n += 1
            if n > 60 then out.__truncated=true break end
            out[tostring(k)] = safe(val,depth+1)
        end
        return out
    end
    if tv=="string" or tv=="number" or tv=="boolean" or tv=="nil" then return v end
    return tostring(v)
end

local function getLeaderstat(name)
    local ls=LP:FindFirstChild("leaderstats")
    local v=ls and ls:FindFirstChild(name)
    return v and v.Value or nil
end

local function snapshot()
    local s={Level=getLeaderstat("Level"),Honey=getLeaderstat("Honey"),Hatches=getLeaderstat("Hatches")}
    for _,attr in ipairs(TRACKED_ATTRS) do s[attr]=LP:GetAttribute(attr) end
    local ch=LP.Character
    local hrp=ch and ch:FindFirstChild("HumanoidRootPart")
    if hrp then s.Position=hrp.Position end
    return s
end

local function push(kind,data)
    if not CFG.Enabled then return nil end
    local e={t=now(),kind=kind,data=safe(data)}
    table.insert(Runtime.events,e)
    while #Runtime.events>CFG.MaxEvents do table.remove(Runtime.events,1) end
    if CFG.Verbose then log(kind,HttpService:JSONEncode(e.data)) end
    return e
end

local function argsArray(...)
    local p=table.pack(...)
    local out={}
    for i=1,p.n do out[i]=p[i] end
    out.n=p.n
    return out
end

local function argCount(args) return args.n or #args end

local function signature(path,method,args)
    local t={}
    for i=1,argCount(args) do t[i]=typeof(args[i]) end
    return table.concat({path,method,tostring(argCount(args)),table.concat(t,",")},"|")
end

local function semanticKey(method,args)
    local a3=args[3]
    if type(a3)=="string" then return method..":"..a3 end
    if type(a3)=="number" and a3>=1 and a3<=12 and math.floor(a3)==a3 then return method..":smallnum:"..tostring(a3) end
    return method..":"..typeof(a3)
end

local function notePattern(method,args,anchored)
    local key=semanticKey(method,args)
    local p=Runtime.patterns[key]
    if not p then p={count=0,anchored=0,unanchored=0};Runtime.patterns[key]=p end
    p.count+=1
    if anchored then p.anchored+=1 else p.unanchored+=1 end
    return p
end

local function explicitRemoteTag(method,args)
    local a3,a4=args[3],args[4]
    if method=="InvokeServer" then
        if a3=="hourly" or a3=="daily" or a3=="weekly" then return "reward:"..a3,95 end
        if a3=="free" and type(a4)=="number" then return "reward:free",90 end
        if type(a4)=="table" and (a4.questId or a4.source=="npc_claim") then return "quest:claim",98 end
        if type(a3)=="string" and string.find(string.lower(a3),"quest",1,true) then return "quest",80 end
    end
    return nil,0
end

local function inferAnchorTag(anchor)
    if not anchor then return "unknown",0 end
    if anchor.kind=="input" then
        local key=anchor.keyShort
        local k=HOTBAR_KIND[key]
        if k then return "equip:"..k,75 end
        if anchor.inputType=="MouseButton1" then return "click",45 end
    elseif anchor.kind=="state" then
        local n,v,old=anchor.name,anchor.value,anchor.old
        if n=="ShovelEquipped" and v==true then return "equip:shovel",98 end
        if n=="GripHoldKind" and type(v)=="string" then return "hold:"..v,96 end
        if n=="ActiveHoldRevision" and old~=nil and v~=old then return "hold_revision",88 end
        if n=="SelectedMobId" and v and v~=old then return "mob:select",90 end
        if n=="BeeCombatTargetMobId" and v and v~=old then return "mob:target",82 end
    elseif anchor.kind=="leaderstat" then
        if anchor.name=="Hatches" then return "hatch_result",85 end
        if anchor.name=="Honey" then return "honey_change",55 end
    end
    return "unknown",0
end

local function closeEpisode(ep)
    if not ep or ep.closed then return end
    ep.closed=true
    ep.closedAt=now()
    local bestTag,bestConf=inferAnchorTag(ep.anchor)
    for _,r in ipairs(ep.remotes) do
        if r.explicitConfidence and r.explicitConfidence>bestConf then
            bestTag,bestConf=r.explicitTag,r.explicitConfidence
        end
    end
    ep.tag=bestTag
    ep.confidence=bestConf
    Runtime.activeEpisode=nil
end

local function openEpisode(anchor)
    if Runtime.activeEpisode and not Runtime.activeEpisode.closed then closeEpisode(Runtime.activeEpisode) end
    local ep={id=#Runtime.episodes+1,startedAt=now(),anchor=safe(anchor),remotes={},stateAfter=safe(snapshot()),closed=false}
    table.insert(Runtime.episodes,ep)
    while #Runtime.episodes>CFG.MaxEpisodes do table.remove(Runtime.episodes,1) end
    Runtime.activeEpisode=ep
    task.delay(CFG.PostWindow,function()
        if Runtime.activeEpisode==ep then closeEpisode(ep) end
    end)
    return ep
end

local function recentActionInput(maxAge)
    local li=Runtime.lastInput
    if not li then return nil end
    if now()-(li.t or -999)>maxAge then return nil end
    return li
end

local function isMeaningfulInput(input)
    local ut=tostring(input.UserInputType)
    local kc=tostring(input.KeyCode)
    if ut:find("MouseButton1",1,true) then return true end
    if ut:find("Keyboard",1,true) then
        return not kc:find("Unknown",1,true)
    end
    return false
end

local function isStrongFarmCandidate(args,state,anchor)
    local a3,a4,a5=args[3],args[4],args[5]
    if state.GripHoldKind~="shovel" and state.ShovelEquipped~=true then return false end
    if type(a3)~="string" or typeof(a4)~="Vector3" or type(a5)~="table" then return false end
    if KNOWN_BACKGROUND_A3[a3] then return false end
    if a3=="Dandelion" or a3==state.BeeCombatTargetFieldDb then
        return anchor~=nil
    end
    return false
end

local function classifyRemote(method,args,state,anchor,pattern)
    local explicit,ec=explicitRemoteTag(method,args)
    if explicit then return explicit,ec,"explicit" end

    local a3=args[3]
    if method=="FireServer" then
        if KNOWN_BACKGROUND_A3[a3] then return "background",98,"known_background" end
        if type(a3)=="number" and a3>=1 and a3<=3 and argCount(args)>=5 then
            return "background",92,"repeated_small_number" end
        if isStrongFarmCandidate(args,state,anchor) then return "farm:candidate",88,"shovel_state+field_packet" end
        if state.SelectedMobId or state.BeeCombatTargetMobId then
            if anchor and anchor.kind=="state" and (anchor.name=="SelectedMobId" or anchor.name=="BeeCombatTargetMobId") then
                return "mob:candidate",82,"mob_state_anchor"
            end
        end
        if state.GripHoldKind=="fishing" and anchor then return "fishing:candidate",75,"fishing_hold_anchor" end
    end

    if not anchor and pattern and pattern.unanchored>=CFG.BackgroundThreshold and pattern.anchored==0 then
        return "background",80,"repetitive_unanchored"
    end
    return "unknown",0,"insufficient_anchor"
end

local function recordLearned(path,method,args,tag,confidence,reason,anchored)
    local sig=signature(path,method,args)
    local rec=Runtime.learned[sig]
    if not rec then
        rec={remote=path,method=method,argc=argCount(args),types={},count=0,tags={},reasons={},anchored=0,unanchored=0,samples={}}
        for i=1,argCount(args) do rec.types[i]=typeof(args[i]) end
        Runtime.learned[sig]=rec
    end
    rec.count+=1
    rec.tags[tag]=(rec.tags[tag] or 0)+1
    rec.reasons[reason]=(rec.reasons[reason] or 0)+1
    if anchored then rec.anchored+=1 else rec.unanchored+=1 end
    if #rec.samples<5 then
        local s={}
        for i=1,argCount(args) do s[i]=safe(args[i]) end
        table.insert(rec.samples,s)
    end
    return sig
end

local function learnRemote(remote,method,args)
    local path=remote:GetFullName()
    local state=snapshot()
    local ep=Runtime.activeEpisode
    local anchor=ep and ep.anchor or nil
    if not anchor then
        local li=recentActionInput(CFG.PreWindow)
        if li then anchor=li end
    end
    local anchored=anchor~=nil
    local pattern=notePattern(method,args,anchored)
    local tag,confidence,reason=classifyRemote(method,args,state,anchor,pattern)
    local sig=recordLearned(path,method,args,tag,confidence,reason,anchored)
    local explicitTag,explicitConfidence=explicitRemoteTag(method,args)

    local remoteRec={
        t=now(),remote=path,method=method,signature=sig,tag=tag,confidence=confidence,reason=reason,
        args=safe(args),state=safe(state),explicitTag=explicitTag,explicitConfidence=explicitConfidence,
    }
    if ep and not ep.closed then table.insert(ep.remotes,remoteRec) end
    push("remote_out",remoteRec)
end

local function installNetworkObserver()
    if Runtime.hookInstalled then return true end
    if not hookmetamethod or not getnamecallmethod or not newcclosure then
        warn("[Beeconomy Learner] Missing hookmetamethod/getnamecallmethod/newcclosure")
        return false
    end
    local old
    old=hookmetamethod(game,"__namecall",newcclosure(function(self,...)
        local method=getnamecallmethod()
        if CFG.Enabled and typeof(self)=="Instance" and (method=="FireServer" or method=="InvokeServer") then
            local args=argsArray(...)
            task.defer(function() pcall(learnRemote,self,method,args) end)
        end
        return old(self,...)
    end))
    Runtime.hookInstalled=true
    log("Network observer installed")
    return true
end

local function stateAnchor(name,old,new)
    if ACTION_DRIVEN[name] then return true end
    if name=="SelectedMobId" and old~=new and new~=nil then return true end
    return false
end

local function watchState()
    for _,attr in ipairs(TRACKED_ATTRS) do
        Runtime.previousState[attr]=LP:GetAttribute(attr)
        LP:GetAttributeChangedSignal(attr):Connect(function()
            local old=Runtime.previousState[attr]
            local new=LP:GetAttribute(attr)
            Runtime.previousState[attr]=new
            local data={kind="state",name=attr,old=old,value=new,snapshot=safe(snapshot())}
            push("state",data)
            if stateAnchor(attr,old,new) then openEpisode(data) end
        end)
    end

    local ls=LP:FindFirstChild("leaderstats") or LP:WaitForChild("leaderstats",10)
    if ls then
        for _,name in ipairs({"Level","Honey","Hatches"}) do
            local v=ls:FindFirstChild(name)
            if v and v:IsA("ValueBase") then
                local old=v.Value
                v.Changed:Connect(function(new)
                    local data={kind="leaderstat",name=name,old=old,value=new,snapshot=safe(snapshot())}
                    old=new
                    push("leaderstat",data)
                    if name=="Hatches" then openEpisode(data) end
                end)
            end
        end
    end
end

local function shortKey(keyCode)
    local s=tostring(keyCode)
    return s:match("Enum%.KeyCode%.(.+)") or s
end

local function shortInputType(t)
    local s=tostring(t)
    return s:match("Enum%.UserInputType%.(.+)") or s
end

local function watchInput()
    UserInputService.InputBegan:Connect(function(input,processed)
        if processed or not isMeaningfulInput(input) then return end
        local item={
            kind="input",inputType=shortInputType(input.UserInputType),key=tostring(input.KeyCode),keyShort=shortKey(input.KeyCode),
            pos=safe(input.Position),t=now(),snapshot=safe(snapshot()),
        }
        Runtime.lastInput=item
        push("input",item)
        if HOTBAR_KIND[item.keyShort] or item.inputType=="MouseButton1" then openEpisode(item) end
    end)
end

local function summarizeLearned()
    local rows={}
    for sig,rec in pairs(Runtime.learned) do
        local bestTag,bestN="unknown",0
        for tag,n in pairs(rec.tags) do if n>bestN then bestTag,bestN=tag,n end end
        local bestReason,bestRN="",0
        for reason,n in pairs(rec.reasons) do if n>bestRN then bestReason,bestRN=reason,n end end
        table.insert(rows,{
            signature=sig,remote=rec.remote,method=rec.method,argc=rec.argc,types=rec.types,count=rec.count,
            bestTag=bestTag,confidence=rec.count>0 and math.floor(bestN/rec.count*100+0.5) or 0,
            anchored=rec.anchored,unanchored=rec.unanchored,bestReason=bestReason,samples=rec.samples,
        })
    end
    table.sort(rows,function(a,b)
        if (a.bestTag=="background")~=(b.bestTag=="background") then return a.bestTag~="background" end
        return a.count>b.count
    end)
    return rows
end

local function summarizedEpisodes()
    local out={}
    for _,ep in ipairs(Runtime.episodes) do
        local calls={}
        for _,r in ipairs(ep.remotes) do
            table.insert(calls,{remote=r.remote,method=r.method,tag=r.tag,confidence=r.confidence,reason=r.reason,signature=r.signature,args=r.args})
        end
        table.insert(out,{id=ep.id,startedAt=ep.startedAt,closedAt=ep.closedAt,anchor=ep.anchor,tag=ep.tag,confidence=ep.confidence,remotes=calls})
    end
    return out
end

local function buildReport()
    return {
        game=game.Name,placeId=game.PlaceId,generatedAt=os.time(),sessionSeconds=now(),state=safe(snapshot()),
        learned=summarizeLearned(),episodes=summarizedEpisodes(),patterns=safe(Runtime.patterns),
        notes={
            "V2 uses action/state anchored episodes.",
            "Known repeating traffic (tool, recieveSnapshot/receiveSnapshot, MatildasMarket, numeric 1..3 bursts) is filtered as background.",
            "Farm classification requires shovel state plus a field/Vector3/table packet near an action anchor.",
            "Observer only; no learned remote is automatically replayed.",
        },
    }
end

local function exportReport()
    if Runtime.activeEpisode then closeEpisode(Runtime.activeEpisode) end
    local json=HttpService:JSONEncode(buildReport())
    local filename="Beeconomy_AutoLearnV2_"..tostring(os.time())..".json"
    if writefile then
        local ok,err=pcall(writefile,filename,json)
        if ok then log("Saved",filename) return filename end
        warn("[Beeconomy Learner] writefile failed",err)
    end
    print("===== BEEconomy AUTO LEARN V2 =====") print(json) print("===== END =====")
end

local function printTop()
    print("===== LEARNED SIGNATURES V2 =====")
    local rows=summarizeLearned()
    for i=1,math.min(#rows,30) do
        local r=rows[i]
        print(string.format("[%02d] %s argc=%d x%d tag=%s (%d%%) anchor=%d bg=%d reason=%s",i,r.method,r.argc,r.count,r.bestTag,r.confidence,r.anchored,r.unanchored,r.bestReason))
    end
    print("===== END =====")
end

local function printEpisodes()
    if Runtime.activeEpisode then closeEpisode(Runtime.activeEpisode) end
    print("===== ACTION EPISODES =====")
    local start=math.max(1,#Runtime.episodes-14)
    for i=start,#Runtime.episodes do
        local ep=Runtime.episodes[i]
        print(string.format("EP#%d t=%.2f tag=%s conf=%d%% calls=%d anchor=%s",ep.id,ep.startedAt,ep.tag or "open",ep.confidence or 0,#ep.remotes,HttpService:JSONEncode(ep.anchor)))
        for j,r in ipairs(ep.remotes) do
            if j<=12 then print("  ",r.method,r.tag,r.confidence,r.reason,r.signature) end
        end
    end
    print("===== END =====")
end

installNetworkObserver()
watchState()
watchInput()
push("start",{state=safe(snapshot())})

local Rayfield=loadstring(game:HttpGet(((getgenv and getgenv().RayfieldUrl) or "https://sirius.menu/rayfield")))()
local Window=Rayfield:CreateWindow({Name="Beeconomy Auto Learner V2",Icon=0,LoadingTitle="Beeconomy Event Learner V2",LoadingSubtitle="ZEBUXHUBBY",ConfigurationSaving={Enabled=false},KeySystem=false})
local LearnTab=Window:CreateTab("Auto Detect",4483362458)
local DebugTab=Window:CreateTab("Debug",4483362458)

LearnTab:CreateToggle({Name="Enable Event Learning",CurrentValue=CFG.Enabled,Flag="BeeLearnV2",Callback=function(v) CFG.Enabled=v end})
LearnTab:CreateSlider({Name="Post-Action Window",Range={0.4,1.8},Increment=0.1,Suffix="s",CurrentValue=CFG.PostWindow,Flag="BeePostWindow",Callback=function(v) CFG.PostWindow=v end})
LearnTab:CreateToggle({Name="Verbose Console",CurrentValue=CFG.Verbose,Flag="BeeVerboseV2",Callback=function(v) CFG.Verbose=v end})
LearnTab:CreateToggle({Name="Auto Export Every 60s",CurrentValue=CFG.AutoExport,Flag="BeeAutoExportV2",Callback=function(v) CFG.AutoExport=v end})
LearnTab:CreateButton({Name="Print Learned Signatures",Callback=printTop})
LearnTab:CreateButton({Name="Print Action Episodes",Callback=printEpisodes})
LearnTab:CreateButton({Name="Export V2 Report",Callback=exportReport})

DebugTab:CreateButton({Name="Print Current State",Callback=function() print(HttpService:JSONEncode(safe(snapshot()))) end})
DebugTab:CreateButton({Name="Print Background Patterns",Callback=function()
    print("===== PATTERNS =====")
    for k,p in pairs(Runtime.patterns) do if p.count>=3 then print(k,"count",p.count,"anchored",p.anchored,"unanchored",p.unanchored) end end
    print("===== END =====")
end})
DebugTab:CreateParagraph({Title="Training V2",Content="Play normally. V2 creates an episode when a meaningful click/hotbar input or action-driven state transition happens, then associates only nearby network calls. Repeating unanchored traffic is background-filtered automatically."})

task.spawn(function()
    while task.wait(1) do
        if CFG.AutoExport and now()-Runtime.lastExport>=CFG.ExportEvery then Runtime.lastExport=now();exportReport() end
    end
end)

Rayfield:Notify({Title="Beeconomy Auto Learner V2",Content=Runtime.hookInstalled and "V2 active: state-anchored episodes + background filtering." or "Loaded, but network hook unavailable.",Duration=6})
log("Loaded V2. hookInstalled =",Runtime.hookInstalled)
