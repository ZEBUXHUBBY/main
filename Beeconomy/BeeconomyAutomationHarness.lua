-- Beeconomy Semantic Auto Learner V4 (Rayfield)
-- Observer/classifier only: recognizes confirmed action shapes from V3 capture.
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")
local LP=Players.LocalPlayer
local CFG={Enabled=true,MaxEvents=1800,MaxEpisodes=260,Verbose=false}
local R={started=os.clock(),events={},episodes={},learned={},patterns={},prev={},hook=false,owner=nil,lastClick=-999,nextEpisodeId=0}
local ATTRS={"EquippedPickaxeId","ShovelEquipped","EquippedAxeId","EquippedNetId","EquippedFishingRodId","ActiveHoldRevision","BeeCombatTargetMobId","BeeCombatTargetFieldDb","SelectedMobId","GripHoldKind"}
local HOTBAR={One="shovel",Two="axe",Three="pickaxe",Four="fishing_rod",Five="net",Six="hoverboard"}
local function now()return os.clock()-R.started end
local function log(...)print("[Beeconomy V4]",...)end
local function safe(v,d)d=d or 0;if d>4 then return "<deep>" end;local t=typeof(v);if t=="Vector3" then return {__type="Vector3",x=v.X,y=v.Y,z=v.Z} end;if t=="CFrame" then return {__type="CFrame",components={v:GetComponents()}} end;if t=="Instance" then return {__type="Instance",class=v.ClassName,path=v:GetFullName()} end;if t=="EnumItem" then return tostring(v) end;if t=="table" then local o,n={},0;for k,x in pairs(v) do n+=1;if n>60 then o.__truncated=true;break end;o[tostring(k)]=safe(x,d+1) end;return o end;if t=="string" or t=="number" or t=="boolean" or t=="nil" then return v end;return tostring(v)end
local function ls(n)local l=LP:FindFirstChild("leaderstats");local v=l and l:FindFirstChild(n);return v and v.Value or nil end
local function snap()local s={Level=ls("Level"),Honey=ls("Honey"),Hatches=ls("Hatches")};for _,a in ipairs(ATTRS)do s[a]=LP:GetAttribute(a)end;local c=LP.Character;local h=c and c:FindFirstChild("HumanoidRootPart");if h then s.Position=h.Position end;return s end
local function push(k,d)local e={t=now(),kind=k,data=safe(d)};table.insert(R.events,e);while #R.events>CFG.MaxEvents do table.remove(R.events,1)end;if CFG.Verbose then log(k,HttpService:JSONEncode(e.data))end end
local function pack(...)local p=table.pack(...);local a={n=p.n};for i=1,p.n do a[i]=p[i]end;return a end
local function argc(a)return a.n or #a end
local function signature(path,m,a)local t={};for i=1,argc(a)do t[i]=typeof(a[i])end;return table.concat({path,m,tostring(argc(a)),table.concat(t,",")},"|")end
local function hold()return LP:GetAttribute("GripHoldKind")end
local function classify(m,a)
 local n=argc(a);local a3,a4,a5=a[3],a[4],a[5]
 if m=="FireServer" then
  if n==7 and type(a3)=="string" and type(a4)=="boolean" then return "tool:equip",99,"confirmed_tool_packet" end
  if n==5 and a3=="Rock" and type(a4)=="string" and type(a5)=="number" then return "mining:rock",99,"confirmed_rock_packet" end
  if n==4 and a3=="Tree" and type(a4)=="string" then return "chop:tree",99,"confirmed_tree_packet" end
  if n==5 and type(a3)=="number" and typeof(a4)=="Vector3" and type(a5)=="table" then return "farm:pollen",99,"confirmed_shovel_packet" end
  if a3=="recieveSnapshot" or a3=="receiveSnapshot" then return "background:snapshot",100,"known_background" end
  if a3=="tool" then return "background:tool",100,"known_background" end
  if type(a3)=="string" and (a3=="Dandelion" or a3==LP:GetAttribute("BeeCombatTargetFieldDb")) then return "field:state",90,"field_packet" end
  if n==3 and type(a3)=="table" then return "world:ids",80,"id_table_packet" end
 end
 if m=="InvokeServer" then
  if a3=="free" and type(a4)=="number" then return "reward:free",99,"confirmed_free_reward" end
  if a3=="hourly" or a3=="daily" or a3=="weekly" then return "reward:"..a3,99,"confirmed_reward" end
  if type(a3)=="string" and string.find(a3,":hatch:",1,true) then return "hatch",99,"confirmed_hatch" end
  if a3=="complete" and type(a4)=="table" then return "action:complete",99,"confirmed_complete" end
  if type(a4)=="table" and (a4.questId or a4.source=="npc_claim") then return "quest:claim",99,"confirmed_quest_claim" end
  if a3=="Basic" or a3=="World1/Basic" then return "hatch:basic",92,"hatch_context" end
 end
 return "unknown",0,"unclassified"
end
local function openOwner(tag,conf,anchor,window)if R.owner then R.owner.closedAt=now()end;R.nextEpisodeId+=1;local e={id=R.nextEpisodeId,tag=tag,confidence=conf,startedAt=now(),anchor=safe(anchor),stateAtOpen=safe(snap()),remotes={}};table.insert(R.episodes,e);while #R.episodes>CFG.MaxEpisodes do table.remove(R.episodes,1)end;R.owner=e;task.delay(window or .25,function()if R.owner==e then e.closedAt=now();R.owner=nil end end);return e end
local function record(remote,m,a)local tag,conf,reason=classify(m,a);local path=remote:GetFullName();local s=signature(path,m,a);local x=R.learned[s] or {remote=path,method=m,argc=argc(a),count=0,tags={},reasons={},samples={}};R.learned[s]=x;x.count+=1;x.tags[tag]=(x.tags[tag]or 0)+1;x.reasons[reason]=(x.reasons[reason]or 0)+1;if #x.samples<6 then local z={};for i=1,argc(a)do z[i]=safe(a[i])end;table.insert(x.samples,z)end;local ev={t=now(),remote=path,method=m,tag=tag,confidence=conf,reason=reason,args=safe(a),state=safe(snap()),ownerTag=R.owner and R.owner.tag or nil};if R.owner then table.insert(R.owner.remotes,ev)end;push("remote_out",ev)end
local function hook()if not hookmetamethod or not getnamecallmethod or not newcclosure then warn("[Beeconomy V4] executor hook APIs missing");return end;local old;old=hookmetamethod(game,"__namecall",newcclosure(function(self,...)local m=getnamecallmethod();if CFG.Enabled and typeof(self)=="Instance" and (m=="FireServer" or m=="InvokeServer")then local a=pack(...);task.defer(function()pcall(record,self,m,a)end)end;return old(self,...)end));R.hook=true end
local function sk(k)return tostring(k):match("Enum%.KeyCode%.(.+)")or tostring(k)end
local function st(t)return tostring(t):match("Enum%.UserInputType%.(.+)")or tostring(t)end
UIS.InputBegan:Connect(function(i,p)if p then return end;local typ,key=st(i.UserInputType),sk(i.KeyCode);local d={inputType=typ,key=key,state=safe(snap()),pos=safe(i.Position)};push("input",d);if HOTBAR[key]then openOwner("equip:"..HOTBAR[key],80,d,.2)elseif typ=="MouseButton1" and now()-R.lastClick>.1 then R.lastClick=now();openOwner("click:"..tostring(hold()),50,d,.14)end end)
for _,a in ipairs(ATTRS)do R.prev[a]=LP:GetAttribute(a);LP:GetAttributeChangedSignal(a):Connect(function()local old=R.prev[a];local new=LP:GetAttribute(a);R.prev[a]=new;local d={name=a,old=old,value=new,state=safe(snap())};push("state",d);if a=="GripHoldKind" and old~=new then openOwner("hold:"..tostring(new),97,d,.36)elseif a=="ShovelEquipped" and old~=new then openOwner(new and "equip:shovel" or "unequip:shovel",98,d,.36)elseif a=="SelectedMobId" and new and new~=old then openOwner("mob:select",94,d,.36)end end)end
local function summaries()local o={};for s,r in pairs(R.learned)do local bt,bn="unknown",0;for t,n in pairs(r.tags)do if n>bn then bt,bn=t,n end end;table.insert(o,{signature=s,remote=r.remote,method=r.method,argc=r.argc,count=r.count,bestTag=bt,confidence=math.floor(bn/r.count*100+.5),reasons=r.reasons,samples=r.samples})end;table.sort(o,function(a,b)return a.count>b.count end);return o end
local function report()return {version=4,game=game.Name,placeId=game.PlaceId,generatedAt=os.time(),sessionSeconds=now(),state=safe(snap()),learned=summaries(),episodes=safe(R.episodes),notes={"V4 classifier built from confirmed V3 capture","Recognizes tool equip, rock mining, tree chopping, pollen harvesting, rewards, hatch, completion and quest claim","Observer/classifier only; unknown traffic is not replayed"}}end
local function export()local f="Beeconomy_AutoLearnV4_"..os.time()..".json";local j=HttpService:JSONEncode(report());if writefile then local ok=pcall(writefile,f,j);if ok then log("Saved",f);return end end;print(j)end
local function printTop()print("===== BEE V4 CLASSIFIED =====");for i,r in ipairs(summaries())do if i>25 then break end;print(string.format("[%d] %s argc=%d n=%d => %s (%d%%)",i,r.method,r.argc,r.count,r.bestTag,r.confidence))end;print("===== END =====")end
hook();push("start",{state=snap()})
local Rayfield=loadstring(game:HttpGet(((getgenv and getgenv().RayfieldUrl)or"https://sirius.menu/rayfield")))()
local W=Rayfield:CreateWindow({Name="Beeconomy Auto Learner V4",LoadingTitle="Beeconomy V4 Classifier",LoadingSubtitle="ZEBUXHUBBY",ConfigurationSaving={Enabled=false},KeySystem=false})
local T=W:CreateTab("Auto Detect",4483362458);local D=W:CreateTab("Debug",4483362458)
T:CreateToggle({Name="Enable Learning",CurrentValue=true,Flag="BeeV4Enabled",Callback=function(v)CFG.Enabled=v end})
T:CreateToggle({Name="Verbose Console",CurrentValue=false,Flag="BeeV4Verbose",Callback=function(v)CFG.Verbose=v end})
T:CreateButton({Name="Print Classified Actions",Callback=printTop})
T:CreateButton({Name="Export V4 Report",Callback=export})
D:CreateButton({Name="Print Current State",Callback=function()print(HttpService:JSONEncode(safe(snap())))end})
D:CreateParagraph({Title="V4",Content="Play normally. V4 classifies the confirmed packet shapes from the V3 capture instead of labeling them unknown. Export the V4 report after testing each system."})
Rayfield:Notify({Title="Beeconomy V4 ready",Content="Confirmed V3 action shapes are now classified.",Duration=6.5})
log("loaded")