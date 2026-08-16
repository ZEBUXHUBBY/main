-- Beeconomy Semantic Auto Learner V3 (Rayfield)
-- Observer only. Learns action/state/network correlations from normal gameplay.
-- V3 fixes episode pollution: clicks are short/debounced, semantic state owns traffic,
-- and farm classification requires the CURRENT shovel hold state.

local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")
local LP=Players.LocalPlayer
local PLACE_ID=101558830312092
if game.PlaceId~=PLACE_ID then warn("[Beeconomy V3] Unexpected place",game.PlaceId) end

local CFG={Enabled=true,ClickWindow=.12,SemanticWindow=.34,ClickDebounce=.10,MaxEvents=1600,MaxEpisodes=220,AutoExport=false,ExportEvery=60,Verbose=false}
local R={started=os.clock(),events={},episodes={},learned={},patterns={},prev={},hook=false,owner=nil,lastInput=nil,lastClick=-999,lastExport=0,nextEpisodeId=0}

local ATTRS={"EquippedPickaxeId","ShovelEquipped","EquippedAxeId","EquippedTitle","EquippedNetId","EquippedFishingRodId","ActiveHoldRevision","BeeCombatTargetMobId","BeeCombatTargetFieldDb","SelectedMobId","GripHoldKind"}
local HOTBAR={One="shovel",Two="axe",Three="pickaxe",Four="fishing",Five="net",Six="hoverboard"}
local BG={tool=true,recieveSnapshot=true,receiveSnapshot=true,MatildasMarket=true}

local function now() return os.clock()-R.started end
local function log(...) print("[Beeconomy V3]",...) end
local function safe(v,d)
 d=d or 0;if d>4 then return "<deep>" end
 local t=typeof(v)
 if t=="Vector3" then return {__type="Vector3",x=v.X,y=v.Y,z=v.Z} end
 if t=="CFrame" then return {__type="CFrame",components={v:GetComponents()}} end
 if t=="Instance" then return {__type="Instance",class=v.ClassName,path=v:GetFullName()} end
 if t=="EnumItem" then return tostring(v) end
 if t=="table" then local o,n={},0;for k,x in pairs(v) do n+=1;if n>50 then o.__truncated=true;break end;o[tostring(k)]=safe(x,d+1) end;return o end
 if t=="string" or t=="number" or t=="boolean" or t=="nil" then return v end
 return tostring(v)
end
local function ls(name)local l=LP:FindFirstChild("leaderstats");local v=l and l:FindFirstChild(name);return v and v.Value or nil end
local function snap()
 local s={Level=ls("Level"),Honey=ls("Honey"),Hatches=ls("Hatches")}
 for _,a in ipairs(ATTRS) do s[a]=LP:GetAttribute(a) end
 local c=LP.Character;local h=c and c:FindFirstChild("HumanoidRootPart");if h then s.Position=h.Position end
 return s
end
local function push(kind,data)
 if not CFG.Enabled then return end
 local e={t=now(),kind=kind,data=safe(data)};table.insert(R.events,e);while #R.events>CFG.MaxEvents do table.remove(R.events,1) end
 if CFG.Verbose then log(kind,HttpService:JSONEncode(e.data)) end
end
local function packArgs(...)local p=table.pack(...);local a={n=p.n};for i=1,p.n do a[i]=p[i] end;return a end
local function argc(a)return a.n or #a end
local function sig(path,m,a)local t={};for i=1,argc(a) do t[i]=typeof(a[i]) end;return table.concat({path,m,tostring(argc(a)),table.concat(t,",")},"|") end
local function semanticKey(m,a)local x=a[3];if type(x)=="string" then return m..":"..x end;if type(x)=="number" and x>=1 and x<=12 and x%1==0 then return m..":smallnum:"..x end;return m..":"..typeof(x) end
local function pattern(m,a,anchored)local k=semanticKey(m,a);local p=R.patterns[k] or {count=0,anchored=0,unanchored=0};R.patterns[k]=p;p.count+=1;if anchored then p.anchored+=1 else p.unanchored+=1 end;return p end

local function explicit(m,a)
 local a3,a4=a[3],a[4]
 if m=="InvokeServer" then
  if a3=="hourly" or a3=="daily" or a3=="weekly" then return "reward:"..a3,98,"explicit_reward" end
  if a3=="free" and type(a4)=="number" then return "reward:free",95,"explicit_free" end
  if type(a4)=="table" and (a4.questId or a4.source=="npc_claim") then return "quest:claim",99,"explicit_quest_claim" end
  if type(a3)=="string" and string.find(string.lower(a3),"quest",1,true) then return "quest",85,"explicit_quest" end
 end
end
local function currentHold()return LP:GetAttribute("GripHoldKind") end
local function shovelNow()return currentHold()=="shovel" and LP:GetAttribute("ShovelEquipped")==true end

local function closeOwner(ep)
 if not ep or ep.closed then return end
 ep.closed=true;ep.closedAt=now();if R.owner==ep then R.owner=nil end
end
local function openOwner(tag,confidence,anchor,window)
 if R.owner and not R.owner.closed then closeOwner(R.owner) end
 R.nextEpisodeId+=1
 local ep={id=R.nextEpisodeId,tag=tag,confidence=confidence,startedAt=now(),anchor=safe(anchor),stateAtOpen=safe(snap()),remotes={},closed=false}
 table.insert(R.episodes,ep);while #R.episodes>CFG.MaxEpisodes do table.remove(R.episodes,1) end;R.owner=ep
 task.delay(window or CFG.SemanticWindow,function()if R.owner==ep then closeOwner(ep) end end)
 return ep
end
local function refreshSemantic(tag,confidence,anchor)
 local ep=R.owner
 if ep and not ep.closed and ep.tag==tag and (now()-ep.startedAt)<CFG.SemanticWindow then ep.anchorLatest=safe(anchor);return ep end
 return openOwner(tag,confidence,anchor,CFG.SemanticWindow)
end

local function classify(m,a,owner)
 local et,ec,er=explicit(m,a);if et then return et,ec,er end
 local a3,a4,a5=a[3],a[4],a[5]
 if m=="FireServer" then
  if BG[a3] then return "background",99,"known_background" end
  if type(a3)=="number" and a3>=1 and a3<=3 and argc(a)>=5 then return "background",98,"smallnum_burst" end
  -- Important V3 rule: CURRENT hold must be shovel. Old episode snapshots cannot qualify.
  if shovelNow() and type(a3)=="string" and typeof(a4)=="Vector3" and type(a5)=="table" and not BG[a3] then
   if a3=="Dandelion" or a3==LP:GetAttribute("BeeCombatTargetFieldDb") then return "farm:field_packet",94,"current_shovel+field_packet" end
  end
  if owner and owner.tag=="mob:select" then
   if type(a3)=="string" or type(a3)=="table" then return "mob:candidate",86,"owned_by_mob_select" end
  end
  if currentHold()=="fishing" and owner and (owner.tag=="hold:fishing" or owner.tag=="click:fishing") then return "fishing:candidate",82,"current_fishing_owner" end
 end
 return "unknown",0,owner and "semantic_owner_unresolved" or "unowned"
end

local function record(path,m,a,tag,conf,reason,anchored)
 local s=sig(path,m,a);local r=R.learned[s]
 if not r then r={remote=path,method=m,argc=argc(a),types={},count=0,tags={},reasons={},anchored=0,unanchored=0,samples={}};for i=1,argc(a) do r.types[i]=typeof(a[i]) end;R.learned[s]=r end
 r.count+=1;r.tags[tag]=(r.tags[tag] or 0)+1;r.reasons[reason]=(r.reasons[reason] or 0)+1;if anchored then r.anchored+=1 else r.unanchored+=1 end
 if #r.samples<5 then local z={};for i=1,argc(a) do z[i]=safe(a[i]) end;table.insert(r.samples,z) end
 return s
end
local function learnRemote(remote,m,a)
 local owner=R.owner;if owner and owner.closed then owner=nil end
 local anchored=owner~=nil;pattern(m,a,anchored)
 local tag,conf,reason=classify(m,a,owner);local path=remote:GetFullName();local s=record(path,m,a,tag,conf,reason,anchored)
 local rr={t=now(),remote=path,method=m,signature=s,tag=tag,confidence=conf,reason=reason,args=safe(a),state=safe(snap()),ownerId=owner and owner.id or nil,ownerTag=owner and owner.tag or nil}
 if owner then table.insert(owner.remotes,rr) end;push("remote_out",rr)
end
local function installHook()
 if R.hook then return true end
 if not hookmetamethod or not getnamecallmethod or not newcclosure then warn("[Beeconomy V3] missing executor hook APIs");return false end
 local old;old=hookmetamethod(game,"__namecall",newcclosure(function(self,...)
  local m=getnamecallmethod();if CFG.Enabled and typeof(self)=="Instance" and (m=="FireServer" or m=="InvokeServer") then local a=packArgs(...);task.defer(function()pcall(learnRemote,self,m,a)end) end
  return old(self,...)
 end));R.hook=true;return true
end

local function shortKey(k)local s=tostring(k);return s:match("Enum%.KeyCode%.(.+)") or s end
local function shortType(t)local s=tostring(t);return s:match("Enum%.UserInputType%.(.+)") or s end
local function watchInput()
 UIS.InputBegan:Connect(function(input,processed)
  if processed then return end
  local typ,key=shortType(input.UserInputType),shortKey(input.KeyCode)
  local item={kind="input",inputType=typ,keyShort=key,t=now(),pos=safe(input.Position),state=safe(snap())};R.lastInput=item;push("input",item)
  local hk=HOTBAR[key]
  if hk then openOwner("equip:"..hk,80,item,.18);return end
  if typ=="MouseButton1" then
   if now()-R.lastClick<CFG.ClickDebounce then return end;R.lastClick=now()
   local hold=currentHold();local tag=hold and ("click:"..hold) or "click"
   -- click is intentionally weak/short; semantic state can replace it immediately.
   openOwner(tag,50,item,CFG.ClickWindow)
  end
 end)
end
local function watchState()
 for _,a in ipairs(ATTRS) do
  R.prev[a]=LP:GetAttribute(a)
  LP:GetAttributeChangedSignal(a):Connect(function()
   local old=R.prev[a];local new=LP:GetAttribute(a);R.prev[a]=new
   local d={kind="state",name=a,old=old,value=new,t=now(),state=safe(snap())};push("state",d)
   if a=="GripHoldKind" and old~=new then refreshSemantic("hold:"..tostring(new),97,d)
   elseif a=="ShovelEquipped" and old~=new then refreshSemantic(new and "equip:shovel" or "unequip:shovel",98,d)
   elseif a=="SelectedMobId" and new and new~=old then refreshSemantic("mob:select",94,d)
   elseif a=="ActiveHoldRevision" and new~=old then
    -- Do NOT create a separate episode. It only strengthens the current semantic owner.
    if R.owner and not R.owner.closed then R.owner.holdRevisionChanges=(R.owner.holdRevisionChanges or 0)+1;R.owner.lastHoldRevision=new end
   end
  end)
 end
end

local function summaries()
 local out={};for s,r in pairs(R.learned) do local bt,bn="unknown",0;for t,n in pairs(r.tags) do if n>bn then bt,bn=t,n end end;table.insert(out,{signature=s,remote=r.remote,method=r.method,argc=r.argc,types=r.types,count=r.count,bestTag=bt,confidence=r.count>0 and math.floor(bn/r.count*100+.5) or 0,anchored=r.anchored,unanchored=r.unanchored,reasons=r.reasons,samples=r.samples}) end;table.sort(out,function(a,b)return a.count>b.count end);return out
end
local function episodeSummaries()
 local o={};for _,e in ipairs(R.episodes) do local c={};for _,r in ipairs(e.remotes) do c[r.tag]=(c[r.tag] or 0)+1 end;table.insert(o,{id=e.id,tag=e.tag,confidence=e.confidence,startedAt=e.startedAt,closedAt=e.closedAt,anchor=e.anchor,anchorLatest=e.anchorLatest,stateAtOpen=e.stateAtOpen,remoteCount=#e.remotes,remoteTags=c,holdRevisionChanges=e.holdRevisionChanges or 0}) end;return o
end
local function report()return {version=3,game=game.Name,placeId=game.PlaceId,generatedAt=os.time(),sessionSeconds=now(),state=safe(snap()),patterns=R.patterns,learned=summaries(),episodes=episodeSummaries(),notes={"V3 semantic owner model","Mouse clicks are debounced and use a short ownership window","GripHoldKind/ShovelEquipped/SelectedMobId replace weak click ownership","ActiveHoldRevision strengthens owner instead of opening a competing episode","Farm requires CURRENT GripHoldKind=shovel and ShovelEquipped=true","Observer only; no learned remote replay"}} end
local function export()
 local j=HttpService:JSONEncode(report());local f="Beeconomy_AutoLearnV3_"..os.time()..".json";if writefile then local ok,err=pcall(writefile,f,j);if ok then log("Saved",f);return f else warn(err) end end;print(j)
end
local function printEpisodes()
 print("===== V3 EPISODES =====");local es=episodeSummaries();for i=math.max(1,#es-24),#es do local e=es[i];print(string.format("#%d %-18s conf=%d remotes=%d revisions=%d",e.id,e.tag,e.confidence,e.remoteCount,e.holdRevisionChanges)) end;print("===== END =====")
end
local function printTop()
 print("===== V3 LEARNED =====");for i,r in ipairs(summaries()) do if i>20 then break end;print(string.format("[%d] %s %s argc=%d n=%d tag=%s conf=%d%% a/u=%d/%d",i,r.method,r.remote,r.argc,r.count,r.bestTag,r.confidence,r.anchored,r.unanchored)) end;print("===== END =====")
end

installHook();watchState();watchInput();push("start",{state=snap()})
local Rayfield=loadstring(game:HttpGet(((getgenv and getgenv().RayfieldUrl) or "https://sirius.menu/rayfield")))()
local W=Rayfield:CreateWindow({Name="Beeconomy Auto Learner V3",Icon=0,LoadingTitle="Beeconomy Semantic Learner",LoadingSubtitle="ZEBUXHUBBY",ConfigurationSaving={Enabled=false},KeySystem=false})
local T=W:CreateTab("Auto Detect",4483362458);local D=W:CreateTab("Debug",4483362458)
T:CreateToggle({Name="Enable Learning",CurrentValue=CFG.Enabled,Flag="BeeV3Enabled",Callback=function(v)CFG.Enabled=v end})
T:CreateToggle({Name="Verbose Console",CurrentValue=CFG.Verbose,Flag="BeeV3Verbose",Callback=function(v)CFG.Verbose=v end})
T:CreateToggle({Name="Auto Export 60s",CurrentValue=CFG.AutoExport,Flag="BeeV3AutoExport",Callback=function(v)CFG.AutoExport=v end})
T:CreateButton({Name="Print Semantic Episodes",Callback=printEpisodes});T:CreateButton({Name="Print Learned Signatures",Callback=printTop});T:CreateButton({Name="Export V3 Report",Callback=export})
D:CreateButton({Name="Print Current State",Callback=function()print(HttpService:JSONEncode(safe(snap())))end})
D:CreateParagraph({Title="V3 training",Content="Play normally. Test shovel farming, switch shovel↔axe/pickaxe, click mobs, fish, and claim rewards/quests. V3 gives traffic to one semantic owner at a time and does not replay unknown remotes."})
task.spawn(function()while task.wait(1) do if CFG.AutoExport and now()-R.lastExport>=CFG.ExportEvery then R.lastExport=now();export() end end end)
Rayfield:Notify({Title="Beeconomy Learner V3",Content=R.hook and "Semantic learner active" or "Loaded but network hook unavailable",Duration=6})
log("Loaded V3; hook=",R.hook)
