--[[
AE STRATEGIST VISUAL V2 | standalone
Loads no AE_Assistant code and no AE_Strategist v1 code.
Read-only advisor: no placement/upgrade/sell/ability remotes are fired.

Direct loader:
loadstring(game:HttpGet("https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Strategist/visual_v2.lua"))()
]]

local VERSION = "2.0.0-visual"
local RAW = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_DB/"
local EXPECTED_PLACE = 84515722934860

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HS = game:GetService("HttpService")
local WS = game:GetService("Workspace")
local UIS = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local LP = Players.LocalPlayer
local ENV = getgenv and getgenv() or _G

if ENV.AE_STRATEGIST_V2 and ENV.AE_STRATEGIST_V2.Destroy then pcall(ENV.AE_STRATEGIST_V2.Destroy) end

local App = {Version=VERSION, Connections={}, Visuals={}, State={Tab="Team Advisor", Objective="Balanced"}}
ENV.AE_STRATEGIST_V2 = App

local function norm(v) return tostring(v or ""):lower():gsub("[^%w]","") end
local function fmt(v,d)
    v=tonumber(v); if not v then return "?" end; d=d or 1
    if math.abs(v)>=1e9 then return string.format("%.2fB",v/1e9) end
    if math.abs(v)>=1e6 then return string.format("%.2fM",v/1e6) end
    if math.abs(v)>=1e3 then return string.format("%.2fK",v/1e3) end
    local s=string.format("%."..d.."f",v); return s:gsub("(%..-)0+$","%1"):gsub("%.$","")
end
local function ci(t,names)
    if type(t)~="table" then return nil,nil end
    local w={}; for _,n in ipairs(names) do w[norm(n)]=true end
    for k,v in pairs(t) do if w[norm(k)] then return v,k end end
end
local function keys(t) local n=0; if type(t)=="table" then for _ in pairs(t) do n+=1 end end; return n end
local function safeRequire(x) if not x or not x:IsA("ModuleScript") then return nil end local ok,v=pcall(require,x); return ok and type(v)=="table" and v or nil end
local function json(file) local ok,b=pcall(function() return game:HttpGet(RAW..file) end); if not ok then return {} end local ok2,v=pcall(function() return HS:JSONDecode(b) end); return ok2 and type(v)=="table" and v or {} end
local function walk(t,fn,depth,seen,path)
    if type(t)~="table" then return end; depth=depth or 0; if depth>8 then return end; seen=seen or {}; if seen[t] then return end; seen[t]=true; path=path or ""
    for k,v in pairs(t) do local p=path=="" and tostring(k) or path.."."..tostring(k); fn(p,k,v,t); if type(v)=="table" then walk(v,fn,depth+1,seen,p) end end
end
local function notify(s) pcall(function() StarterGui:SetCore("SendNotification",{Title="AE Strategist V2",Text=s,Duration=6}) end) end

-- DB --------------------------------------------------------------------------
local Info = RS:FindFirstChild("Shared") and RS.Shared:FindFirstChild("Information")
local files={Units="units.json",Enemies="enemies.json",Elements="elements.json",Abilities="abilities.json",Passives="passives.json",Maps="maps_full.json",EnemyDrops="enemy_drops.json",Gamemodes="gamemodes.json",GameMechanics="game_mechanics.json",StatusEffects="status_effects.json"}
local DB,Source={},{}
for n,f in pairs(files) do local r=Info and safeRequire(Info:FindFirstChild(n)); if r and keys(r)>0 then DB[n]=r; Source[n]="runtime" else DB[n]=json(f); Source[n]="AE_DB" end end
local Units=DB.Units.Units or DB.Units.List or DB.Units
local Enemies=DB.Enemies.Enemies or DB.Enemies.List or DB.Enemies
local Elements=DB.Elements.ElementData or DB.Elements.Elements or DB.Elements
local Abilities=DB.Abilities.Abilities or DB.Abilities
local Passives=DB.Passives.Passives or DB.Passives
local Drops=DB.EnemyDrops.List or DB.EnemyDrops
local Alias,EnemyAlias={},{}
for a,i in pairs(Units) do Alias[norm(a)]=a; if type(i)=="table" and i.DisplayName then Alias[norm(i.DisplayName)]=a end end
for a,i in pairs(Enemies) do EnemyAlias[norm(a)]=a; if type(i)=="table" then local d=ci(i,{"DisplayName","Name"}); if d then EnemyAlias[norm(d)]=a end end end

local function imageOf(info)
    local best=nil
    if type(info)~="table" then return nil end
    walk(info,function(path,k,v)
        if best then return end
        local nk=norm(k)
        if nk:find("icon") or nk:find("image") or nk:find("thumbnail") or nk:find("portrait") then
            if type(v)=="number" and v>1000 then best="rbxassetid://"..tostring(math.floor(v))
            elseif type(v)=="string" then
                local id=v:match("rbxassetid://(%d+)") or v:match("(%d%d%d%d%d%d%d%d+)")
                if id then best="rbxassetid://"..id end
            end
        end
    end)
    return best
end

local function upgradeRows(info)
    local src=type(info)=="table" and (info.UpgradeInfo or info.Upgrades) or nil; local out={}; if type(src)~="table" then return out end
    for k,v in pairs(src) do local lv=tonumber(k); if lv and type(v)=="table" then out[#out+1]={Level=lv,Data=v} end end
    table.sort(out,function(a,b) return a.Level<b.Level end); return out
end
local CC={stun="Stun",slow="Slow",freeze="Freeze",rewind="Rewind",root="Root",knockback="Knockback",timestop="TimeStop"}
local function capabilityText(entry)
    if type(entry)~="table" then return "" end; local s=tostring(entry.Description or "")
    for k,p in pairs(entry.Parameters or {}) do local v=type(p)=="table" and (p.Value or p.Min) or p; if v~=nil then s=s:gsub("%{"..tostring(k).."%}",tostring(v)) end end
    return s
end
local function unitProfile(asset,owned)
    local info=Units[asset]; if type(info)~="table" then return nil end
    local p={Asset=asset,Name=info.DisplayName or asset,Icon=imageOf(info),Element=info.Element,Archetype=info.Archetype,Rarity=info.Rarity,PlacementType=info.PlacementType,Limit=tonumber(info.PlacementLimit) or 1,Upgrades={},CC={},Buff=false,Debuff=false,Shield=false,Boss=false,Farm=(norm(info.Element)=="farm" or info.IsFarm==true),Owned=owned}
    local cum=0; local sp,sa={},{}
    for _,r in ipairs(upgradeRows(info)) do
        local d=r.Data; local cost=tonumber((ci(d,{"Cost","Price"}))) or 0; cum+=cost
        local dmg=tonumber((ci(d,{"Damage","DMG"}))) or 0; local spa=tonumber((ci(d,{"SPA","AttackSpeed","AttackCooldown"}))); local range=tonumber((ci(d,{"Range","RNG"})))
        local income=tonumber((ci(d,{"Income","YenIncome","YenPerWave","IncomePerWave","MoneyPerWave","GeneratedYen"})))
        p.Upgrades[#p.Upgrades+1]={Level=r.Level,Cost=cost,Cumulative=cum,Damage=dmg,SPA=spa,Range=range,DPS=(spa and spa>0) and dmg/spa or 0,Hitbox=ci(d,{"HitboxType","AOEType","AttackType"}),HitboxSize=tonumber((ci(d,{"HitboxSize","AOESize","Width"}))),Income=income}
        if income then p.Farm=true end
        for _,name in pairs(d.Passives or {}) do if type(name)=="string" and not sp[name] then sp[name]=true; local txt=capabilityText(Passives[name]):lower(); for w,l in pairs(CC) do if txt:find(w,1,true) then p.CC[l]=true end end; p.Buff=p.Buff or txt:find("buff",1,true)~=nil or txt:find("increase damage",1,true)~=nil; p.Debuff=p.Debuff or txt:find("debuff",1,true)~=nil or txt:find("inflict",1,true)~=nil; p.Shield=p.Shield or (txt:find("shield",1,true) and (txt:find("break",1,true) or txt:find("pierce",1,true) or txt:find("remove",1,true)))~=nil; p.Boss=p.Boss or txt:find("boss",1,true)~=nil end end
        for _,name in pairs(d.Abilities or {}) do if type(name)=="string" and not sa[name] then sa[name]=true; local txt=capabilityText(Abilities[name]):lower(); for w,l in pairs(CC) do if txt:find(w,1,true) then p.CC[l]=true end end; p.Buff=p.Buff or txt:find("buff",1,true)~=nil; p.Debuff=p.Debuff or txt:find("debuff",1,true)~=nil; p.Boss=p.Boss or txt:find("boss",1,true)~=nil end end
    end
    p.Base=p.Upgrades[1]; p.Final=p.Upgrades[#p.Upgrades]; return p
end

-- PLAYER PROFILE --------------------------------------------------------------
local function ownedRecord(v)
    if type(v)~="table" then return nil end; local a=ci(v,{"Asset","Unit","UnitName"}); if type(a)~="string" or not Units[a] then return nil end
    if ci(v,{"Level","EXP","OriginalOwner","Trait","StatPotential","Equipment","Equipped"})~=nil then return a end
end
local function collectDirect(t)
    local out={}; if type(t)~="table" then return out end
    for k,v in pairs(t) do local a=ownedRecord(v); if a then out[#out+1]={Asset=a,ID=tostring(ci(v,{"ID","UUID","Guid"}) or k),Data=v} end end; return out
end
local function hasLP(t,depth)
    if type(t)~="table" or depth<0 then return false end
    for _,v in pairs(t) do if v==LP then return true end; if type(v)=="table" and hasLP(v,depth-1) then return true end end; return false
end
local function scanProfile()
    if type(getgc)~="function" then return {Found=false,Owned={},Hotbar={},Reason="getgc unavailable"} end
    local ok,gc=pcall(getgc,true); if not ok then return {Found=false,Owned={},Hotbar={},Reason="getgc failed"} end
    local best=nil
    for _,o in ipairs(gc) do if type(o)=="table" then
        local data=rawget(o,"Data"); if type(data)=="table" then
            local candidates={{data,"Data"}}; for k,v in pairs(data) do if type(v)=="table" then candidates[#candidates+1]={v,"Data."..tostring(k)} end end
            for _,c in ipairs(candidates) do local rec=collectDirect(c[1]); if #rec>0 then local score=#rec + (hasLP(rawget(o,"replication"),2) and 100 or 0) + (type(data.HotbarData)=="table" and 20 or 0); if not best or score>best.Score then best={Score=score,Owned=rec,Data=data,Container=c[1],Path=c[2]} end end end
        end
    end end
    if not best then return {Found=false,Owned={},Hotbar={},Reason="no validated owned-unit replica"} end
    local byID,byAsset={},{}; for _,r in ipairs(best.Owned) do byID[norm(r.ID)]=r; byAsset[norm(r.Asset)]=byAsset[norm(r.Asset)] or {}; table.insert(byAsset[norm(r.Asset)],r) end
    local hot={}; local hb=best.Data.HotbarData; if type(hb)=="table" then hb=hb.Slots or hb end
    if type(hb)=="table" then for slot,v in pairs(hb) do local id,asset;if type(v)=="table" then id=ci(v,{"ID","UnitID","UUID"}); asset=ci(v,{"Asset","Unit","UnitName"}) else id=v end; local r=id and byID[norm(id)]; if not r and id then local prefix=tostring(id):match("^([^#]+)#"); local a=prefix and Alias[norm(prefix)]; r=a and byAsset[norm(a)] and byAsset[norm(a)][1] end; if not r and asset then r=byAsset[norm(asset)] and byAsset[norm(asset)][1] end; if r then hot[#hot+1]={Slot=tonumber(slot) or 99,Record=r,Asset=r.Asset} end end end
    if #hot==0 then for _,r in ipairs(best.Owned) do if ci(r.Data,{"Equipped"})==true then hot[#hot+1]={Slot=tonumber((ci(r.Data,{"HotbarSlot","Slot"}))) or 99,Record=r,Asset=r.Asset} end end end
    table.sort(hot,function(a,b) return a.Slot<b.Slot end)
    return {Found=true,Owned=best.Owned,Hotbar=hot,Path=best.Path,Score=best.Score}
end

-- STAGE + ECONOMY -------------------------------------------------------------
local function detectStage()
    local best=nil
    if type(getgc)=="function" then local ok,gc=pcall(getgc,true); if ok then for _,o in ipairs(gc) do if type(o)=="table" then local map=ci(o,{"MapName","Map"}); local act=ci(o,{"ActName","Act"}); local mode=ci(o,{"Gamemode","GameMode","Mode"}); local diff=ci(o,{"Difficulty"}); if type(map)=="string" and type(act)=="string" then local s={MapName=map,ActName=act,Gamemode=type(mode)=="string" and mode or "?",Difficulty=type(diff)=="string" and diff or "?",Raw=o}; if not best or (s.Gamemode~="?" and best.Gamemode=="?") then best=s end end end end end end
    return best
end
local function enemyDrop(enemy)
    local e=Drops[enemy] or Drops[norm(enemy)]; if type(e)=="number" then return e,"EnemyDrops" end
    if type(e)=="table" then local v,k=ci(e,{"Yen","YenDrop","Money","Cash","Reward","Amount"}); if type(v)=="number" then return v,"EnemyDrops."..tostring(k) end end
    local info=Enemies[enemy]; if type(info)=="table" then local v,k=ci(info,{"Yen","YenDrop","MoneyDrop","RewardYen"}); if type(v)=="number" then return v,"Enemies."..tostring(k) end end
end
local function extractStage(stage)
    local f={Enemies={},Waves={},WaveCount=nil,StartingYen=nil,WaveIncome=0,KillIncome=0,NoFarm=false,Unknown={},Raw=nil,EconomySources={}}
    if not stage then f.Unknown[#f.Unknown+1]="stage not detected"; return f end
    local Maps=DB.Maps; local candidate=nil
    -- direct search for a subtable whose path mentions map + act
    walk(Maps,function(path,k,v) if not candidate and type(v)=="table" and norm(path):find(norm(stage.MapName),1,true) and norm(path):find(norm(stage.ActName),1,true) then candidate=v end end)
    if not candidate and type(stage.Raw)=="table" then candidate=stage.Raw end; f.Raw=candidate
    if type(candidate)~="table" then f.Unknown[#f.Unknown+1]="exact stage table not resolved"; return f end
    walk(candidate,function(path,k,v,parent)
        local nk,np=norm(k),norm(path)
        if type(v)=="number" then
            if not f.StartingYen and (nk=="startingyen" or nk=="startyen" or nk=="startingmoney" or nk=="startcash") then f.StartingYen=v; f.EconomySources[#f.EconomySources+1]=path end
            if nk=="wavereward" or nk=="waveyen" or nk=="roundreward" or nk=="roundyen" or nk=="waveincome" then f.WaveIncome+=v; f.EconomySources[#f.EconomySources+1]=path end
            if (nk=="wavecount" or nk=="maxwaves" or nk=="totalwaves") and not f.WaveCount then f.WaveCount=v end
        elseif type(v)=="string" then
            local ek=EnemyAlias[norm(v)]; if ek then local c=tonumber((ci(parent,{"Count","Amount","Quantity","SpawnCount"}))) or 1; f.Enemies[ek]=(f.Enemies[ek] or 0)+c end
            local nv=norm(v); if nv:find("nofarm",1,true) or nv:find("banfarm",1,true) or nv:find("disablefarm",1,true) then f.NoFarm=true end
        elseif type(v)=="boolean" and np:find("farm",1,true) then if (np:find("disable",1,true) or np:find("ban",1,true) or np:find("nofarm",1,true)) and v then f.NoFarm=true end end
        if type(v)=="table" and (nk=="waves" or nk=="wavedata" or nk=="enemywaves") then local mx=0; for wk,wv in pairs(v) do local wi=tonumber(wk); if wi then mx=math.max(mx,wi); f.Waves[wi]=wv end end; if mx>0 then f.WaveCount=math.max(f.WaveCount or 0,mx) end end
    end)
    for e,c in pairs(f.Enemies) do local y,src=enemyDrop(e); if y then f.KillIncome+=y*c; f.EconomySources[#f.EconomySources+1]=src.." x "..e end end
    if not f.StartingYen then f.Unknown[#f.Unknown+1]="starting Yen" end
    if f.KillIncome==0 then f.Unknown[#f.Unknown+1]="kill Yen/drop values" end
    if f.WaveIncome==0 then f.Unknown[#f.Unknown+1]="wave/round Yen" end
    f.BaseBudget=(f.StartingYen or 0)+f.KillIncome+f.WaveIncome
    f.BudgetExact=(f.StartingYen~=nil and (#f.Enemies==0 or f.KillIncome>0))
    return f
end
local function farmPotential(profiles,waves)
    local total,perWave=0,0; local lines={}
    for _,p in ipairs(profiles or {}) do if p.Farm and p.Final and p.Final.Income then local n=math.max(1,p.Limit); local inc=p.Final.Income*n; perWave+=inc; if waves then total+=inc*waves end; lines[#lines+1]=p.Name.." "..fmt(inc,0).."/wave x cap" end end
    return total,perWave,lines
end

-- TEAM MODEL ------------------------------------------------------------------
local function buildOwned(scan)
    local best={}; for _,r in ipairs(scan.Owned or {}) do local old=best[r.Asset]; local lv=tonumber((ci(r.Data,{"Level"}))) or 0; local ol=old and tonumber((ci(old.Data,{"Level"}))) or -1; if not old or lv>ol then best[r.Asset]=r end end
    local profiles={}; for a,r in pairs(best) do profiles[a]=unitProfile(a,r) end; return profiles
end
local function setCount(t) local n=0; for _ in pairs(t or {}) do n+=1 end; return n end
local function scoreUnit(p,budget,obj,facts)
    if not p or not p.Base or not p.Final then return -math.huge end
    if facts.NoFarm and p.Farm then return -math.huge end
    local d=0; for _,u in ipairs(p.Upgrades) do if u.Cumulative<=budget then d=math.max(d,u.DPS) end end
    local utility=setCount(p.CC)*200 + (p.Buff and 350 or 0)+(p.Shield and 300 or 0)+(p.Boss and 250 or 0)
    if obj=="Max Damage" then return p.Final.DPS*p.Limit + utility*.1 end
    if obj=="Safe Clear" then return d + utility*2 end
    if obj=="Boss" then return d + (p.Boss and 2500 or 0) + utility end
    if obj=="Fast Clear" then return d*2 + (p.Base.Cost>0 and d/p.Base.Cost*1000 or 0)+utility*.5 end
    return d + utility
end
local function recommend(profiles,current,facts,budget,size,obj)
    local arr={}; for _,p in pairs(profiles) do arr[#arr+1]=p end; table.sort(arr,function(a,b) return scoreUnit(a,budget/math.max(size,1),obj,facts)>scoreUnit(b,budget/math.max(size,1),obj,facts) end)
    local team={}; for _,p in ipairs(arr) do if scoreUnit(p,budget/math.max(size,1),obj,facts)>-math.huge then team[#team+1]=p; if #team>=size then break end end end; return team
end
local function metrics(team,budget)
    local m={BudgetDPS=0,FullDPS=0,CC={},Shield=0,Farm=0}
    local per=budget/math.max(#team,1)
    for _,p in ipairs(team) do local best=0; for _,u in ipairs(p.Upgrades) do if u.Cumulative<=per then best=math.max(best,u.DPS) end end; m.BudgetDPS+=best*math.max(1,p.Limit); m.FullDPS+=(p.Final and p.Final.DPS or 0)*math.max(1,p.Limit); for k in pairs(p.CC) do m.CC[k]=true end; if p.Shield then m.Shield+=1 end; if p.Farm then m.Farm+=1 end end
    return m
end

-- PATH / PLACEMENT ------------------------------------------------------------
local function posOf(x)
    if x:IsA("BasePart") then return x.Position end
    if x:IsA("Attachment") then return x.WorldPosition end
    if x:IsA("CFrameValue") then return x.Value.Position end
    if x:IsA("Vector3Value") then return x.Value end
end
local function pathCandidatesRoots()
    local roots={}; local map=WS:FindFirstChild("Map")
    if map then
        local direct=map:FindFirstChild("Path",true); if direct then roots[#roots+1]=direct end
        for _,d in ipairs(map:GetDescendants()) do local n=norm(d.Name); if (n=="path" or n=="waypoints" or n=="nodes" or n=="enemywaypoints") and d~=direct then roots[#roots+1]=d end end
    end
    return roots
end
local function scanPath()
    local best=nil
    for _,root in ipairs(pathCandidatesRoots()) do
        local pts={}
        for _,d in ipairs(root:GetDescendants()) do local p=posOf(d); if p then local order=tonumber(d.Name) or tonumber(d:GetAttribute("Index")) or tonumber(d:GetAttribute("Order")); pts[#pts+1]={P=p,O=order,Name=d.Name} end end
        if #pts>=2 then
            table.sort(pts,function(a,b) if a.O and b.O then return a.O<b.O elseif a.O then return true elseif b.O then return false else return a.Name<b.Name end end)
            local len=0; for i=1,#pts-1 do len+=(pts[i+1].P-pts[i].P).Magnitude end
            local rec={Root=root,Points=pts,Length=len,Source=root:GetFullName()}; if not best or #pts>#best.Points or (#pts==#best.Points and len>best.Length) then best=rec end
        end
    end
    return best
end
local function segDist2D(p,a,b)
    local P=Vector2.new(p.X,p.Z); local A=Vector2.new(a.X,a.Z); local B=Vector2.new(b.X,b.Z); local AB=B-A; local den=AB:Dot(AB); if den<=1e-7 then return (P-A).Magnitude end; local t=math.clamp((P-A):Dot(AB)/den,0,1); return (P-(A+AB*t)).Magnitude
end
local function coverage(path,p,r)
    if not path or not r then return 0 end; local c=0
    for i=1,#path.Points-1 do local a,b=path.Points[i].P,path.Points[i+1].P; if segDist2D(p,a,b)<=r then c+=(b-a).Magnitude end end; return c
end
local function groundAt(x,z,y)
    local rp=RaycastParams.new(); rp.FilterType=Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances={LP.Character}; local hit=WS:Raycast(Vector3.new(x,y+100,z),Vector3.new(0,-220,0),rp); return hit and hit.Position
end
local function placementFor(p,path,limit)
    local u=p and (p.Base or p.Final); if not u or not u.Range or not path then return {} end; local out={}
    for i=1,#path.Points-1 do local a,b=path.Points[i].P,path.Points[i+1].P; local d=b-a; if d.Magnitude>0 then local t=d.Unit; local n=Vector3.new(-t.Z,0,t.X); local mid=(a+b)/2; for _,off in ipairs({math.max(4,u.Range*.28),math.max(6,u.Range*.48),math.max(8,u.Range*.68)}) do for _,sgn in ipairs({-1,1}) do local q=mid+n*off*sgn; local g=groundAt(q.X,q.Z,mid.Y); if g then local cov=coverage(path,g,u.Range); out[#out+1]={Position=g+Vector3.new(0,.15,0),Coverage=cov,Ratio=path.Length>0 and cov/path.Length or 0,Range=u.Range,Asset=p.Asset} end end end end end
    table.sort(out,function(a,b) return a.Coverage>b.Coverage end); local kept={}; for _,c in ipairs(out) do local ok=true; for _,k in ipairs(kept) do if (Vector2.new(c.Position.X,c.Position.Z)-Vector2.new(k.Position.X,k.Position.Z)).Magnitude<5 then ok=false break end end; if ok then kept[#kept+1]=c; if #kept>= (limit or 8) then break end end end; return kept
end

local function modelOwned(m,rec)
    for _,k in ipairs({"Owner","OwnerUserId","PlayerUserId","UserId","OriginalOwner"}) do local v=m:GetAttribute(k); if tonumber(v)==LP.UserId or v==LP.Name then return true end end
    if type(rec)=="table" then local v=ci(rec,{"Owner","Player","OriginalOwner","OwnerUserId"}); if v==LP or tonumber(v)==LP.UserId or v==LP.Name then return true end end
    return false
end
local function scanPlaced()
    local out,seen={},{}
    if type(getgc)=="function" then local ok,gc=pcall(getgc,true); if ok then for _,r in ipairs(gc) do if type(r)=="table" then local m=ci(r,{"Model","UnitModel","Instance"}); local a=ci(r,{"Asset","Unit","UnitName","UnitAsset"}); a=a and Alias[norm(a)]; if a and typeof(m)=="Instance" and m:IsA("Model") and m:IsDescendantOf(WS) and not seen[m] and modelOwned(m,r) then local okp,cf=pcall(m.GetPivot,m); if okp then out[#out+1]={Model=m,Asset=a,Position=cf.Position,Upgrade=tonumber((ci(r,{"Upgrade","UpgradeLevel","CurrentUpgrade"}))) or 0}; seen[m]=true end end end end end end
    local roots={WS:FindFirstChild("Units"),WS:FindFirstChild("PlacedUnits"),WS:FindFirstChild("Towers")}; if WS:FindFirstChild("Map") then roots[#roots+1]=WS.Map:FindFirstChild("Units") end
    for _,root in ipairs(roots) do if root then for _,m in ipairs(root:GetDescendants()) do if m:IsA("Model") and not seen[m] then local a=Alias[norm(m:GetAttribute("Asset") or m.Name)]; if a and modelOwned(m) then local okp,cf=pcall(m.GetPivot,m); if okp then out[#out+1]={Model=m,Asset=a,Position=cf.Position,Upgrade=tonumber(m:GetAttribute("Upgrade") or m:GetAttribute("UpgradeLevel")) or 0}; seen[m]=true end end end end end end
    return out
end
local function liveState()
    local s={Yen=nil,Wave=nil,Source=nil}
    if type(getgc)=="function" then local ok,gc=pcall(getgc,true); if ok then for _,o in ipairs(gc) do if type(o)=="table" then local y=ci(o,{"Yen","Money","Cash","CurrentYen"}); local w=ci(o,{"Wave","CurrentWave","Round","CurrentRound"}); if type(y)=="number" and (type(w)=="number" or hasLP(o,2)) then s.Yen=y; s.Wave=type(w)=="number" and w or s.Wave; s.Source="runtime table"; if s.Yen and s.Wave then break end end end end end end
    return s
end
local function nextAction(profiles,hot,path,placed,yen)
    local actions={}
    for _,e in ipairs(hot or {}) do local p=profiles[e.Asset]; if p and p.Base and p.Base.Cost>0 and (not yen or p.Base.Cost<=yen) then local cand=placementFor(p,path,1)[1]; if cand then local gain=p.Base.DPS*cand.Coverage; actions[#actions+1]={Kind="PLACE",Profile=p,Cost=p.Base.Cost,Gain=gain,Efficiency=gain/p.Base.Cost,Candidate=cand,Text="Place "..p.Name} end end end
    for _,x in ipairs(placed or {}) do local p=profiles[x.Asset]; if p then local cur,nextu=nil,nil; for i,u in ipairs(p.Upgrades) do if u.Level==x.Upgrade then cur=u; nextu=p.Upgrades[i+1]; break end end; cur=cur or p.Upgrades[1]; if cur and nextu and nextu.Cost>0 and (not yen or nextu.Cost<=yen) then local cg=cur.DPS*coverage(path,x.Position,cur.Range or 0); local ng=nextu.DPS*coverage(path,x.Position,nextu.Range or cur.Range or 0); local g=math.max(0,ng-cg); actions[#actions+1]={Kind="UPGRADE",Profile=p,Cost=nextu.Cost,Gain=g,Efficiency=g/nextu.Cost,Placed=x,From=cur.Level,To=nextu.Level,Text="Upgrade "..p.Name.." U"..cur.Level.." → U"..nextu.Level} end end end
    table.sort(actions,function(a,b) return a.Efficiency>b.Efficiency end); return actions
end

-- GUI -------------------------------------------------------------------------
local old=LP.PlayerGui:FindFirstChild("AE_Strategist_VisualV2"); if old then old:Destroy() end
local gui=Instance.new("ScreenGui"); gui.Name="AE_Strategist_VisualV2"; gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true; gui.Parent=LP.PlayerGui
local main=Instance.new("Frame"); main.Size=UDim2.fromOffset(980,650); main.Position=UDim2.new(.5,-490,.5,-325); main.BackgroundColor3=Color3.fromRGB(15,18,27); main.BorderSizePixel=0; main.Parent=gui
Instance.new("UICorner",main).CornerRadius=UDim.new(0,12)
local title=Instance.new("TextLabel"); title.Size=UDim2.new(1,-70,0,42); title.Position=UDim2.fromOffset(16,4); title.BackgroundTransparency=1; title.Text="AE Strategist | Visual "..VERSION; title.TextColor3=Color3.fromRGB(238,241,248); title.Font=Enum.Font.GothamBold; title.TextSize=15; title.TextXAlignment=Enum.TextXAlignment.Left; title.Parent=main
local close=Instance.new("TextButton"); close.Size=UDim2.fromOffset(36,30); close.Position=UDim2.new(1,-46,0,10); close.Text="×"; close.TextSize=20; close.Font=Enum.Font.GothamBold; close.TextColor3=Color3.new(1,1,1); close.BackgroundColor3=Color3.fromRGB(36,41,56); close.BorderSizePixel=0; close.Parent=main; Instance.new("UICorner",close).CornerRadius=UDim.new(0,8)
local side=Instance.new("Frame"); side.Size=UDim2.fromOffset(150,590); side.Position=UDim2.fromOffset(10,50); side.BackgroundTransparency=1; side.Parent=main
local content=Instance.new("Frame"); content.Size=UDim2.new(1,-180,1,-60); content.Position=UDim2.fromOffset(170,50); content.BackgroundTransparency=1; content.Parent=main
local tabs={"Overview","Team Advisor","Stage","Live Assist","Placement","Unit DB","Diagnostics"}; local pages={}; local buttons={}
local function page(name) local f=Instance.new("Frame"); f.Size=UDim2.fromScale(1,1); f.BackgroundTransparency=1; f.Visible=false; f.Parent=content; pages[name]=f; return f end
local function show(name) App.State.Tab=name; for n,p in pairs(pages) do p.Visible=n==name end; for n,b in pairs(buttons) do b.BackgroundColor3=n==name and Color3.fromRGB(64,78,126) or Color3.fromRGB(30,34,48) end end
for i,n in ipairs(tabs) do local b=Instance.new("TextButton"); b.Size=UDim2.new(1,0,0,38); b.Position=UDim2.fromOffset(0,(i-1)*46); b.Text=n; b.TextColor3=Color3.fromRGB(226,229,238); b.Font=Enum.Font.Gotham; b.TextSize=13; b.BackgroundColor3=Color3.fromRGB(30,34,48); b.BorderSizePixel=0; b.Parent=side; Instance.new("UICorner",b).CornerRadius=UDim.new(0,8); b.MouseButton1Click:Connect(function() show(n) end); buttons[n]=b; page(n) end

local function text(parent,text,pos,size,bold)
    local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; l.Text=text; l.TextColor3=Color3.fromRGB(228,231,239); l.Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham; l.TextSize=13; l.TextWrapped=true; l.TextXAlignment=Enum.TextXAlignment.Left; l.TextYAlignment=Enum.TextYAlignment.Top; l.Position=pos or UDim2.new(); l.Size=size or UDim2.new(1,0,0,24); l.Parent=parent; return l
end
local function button(parent,label,pos,w,cb)
    local b=Instance.new("TextButton"); b.Size=UDim2.fromOffset(w or 130,34); b.Position=pos; b.Text=label; b.TextColor3=Color3.new(1,1,1); b.Font=Enum.Font.GothamBold; b.TextSize=12; b.BackgroundColor3=Color3.fromRGB(57,69,111); b.BorderSizePixel=0; b.Parent=parent; Instance.new("UICorner",b).CornerRadius=UDim.new(0,8); b.MouseButton1Click:Connect(cb); return b
end
local function card(parent,p,x,y,w,h,tag)
    local f=Instance.new("Frame"); f.Size=UDim2.fromOffset(w or 112,h or 140); f.Position=UDim2.fromOffset(x,y); f.BackgroundColor3=Color3.fromRGB(27,31,44); f.BorderSizePixel=0; f.Parent=parent; Instance.new("UICorner",f).CornerRadius=UDim.new(0,9)
    local img=Instance.new("ImageLabel"); img.Size=UDim2.new(1,-10,0,84); img.Position=UDim2.fromOffset(5,5); img.BackgroundColor3=Color3.fromRGB(19,22,31); img.BorderSizePixel=0; img.Image=p.Icon or ""; img.ScaleType=Enum.ScaleType.Crop; img.Parent=f; Instance.new("UICorner",img).CornerRadius=UDim.new(0,7)
    if not p.Icon or p.Icon=="" then local ph=text(img,p.Name:sub(1,2):upper(),UDim2.fromScale(0,0),UDim2.fromScale(1,1),true); ph.TextSize=30; ph.TextXAlignment=Enum.TextXAlignment.Center; ph.TextYAlignment=Enum.TextYAlignment.Center end
    local nm=text(f,p.Name,UDim2.fromOffset(6,94),UDim2.new(1,-12,0,30),true); nm.TextSize=11; nm.TextWrapped=true
    local st=text(f,string.format("%s • %s\nDPS %s",tostring(p.Element or "?"),tostring(p.Archetype or "?"),fmt(p.Final and p.Final.DPS or 0,0)),UDim2.fromOffset(6,120),UDim2.new(1,-12,0,36),false); st.TextSize=9; st.TextColor3=Color3.fromRGB(169,177,197)
    if tag then local t=text(f,tag,UDim2.fromOffset(6,6),UDim2.fromOffset(48,18),true); t.BackgroundTransparency=.15; t.BackgroundColor3=Color3.fromRGB(65,81,132); t.TextSize=9; t.TextXAlignment=Enum.TextXAlignment.Center; Instance.new("UICorner",t).CornerRadius=UDim.new(1,0) end
    return f
end
local function clearChildren(frame,keep) for _,c in ipairs(frame:GetChildren()) do if not keep or not keep[c] then c:Destroy() end end end

-- state + refresh -------------------------------------------------------------
local S={Scan=nil,Profiles=nil,Stage=nil,Facts=nil,Path=nil,Placed={},Live=nil,Recommended={},Current={},Actions={},Marker=nil}
App.State.Data=S

local teamPage=pages["Team Advisor"]
local teamHeader=text(teamPage,"TEAM ADVISOR",UDim2.fromOffset(0,0),UDim2.fromOffset(180,24),true)
local objBtn=button(teamPage,"Balanced",UDim2.fromOffset(620,0),120,function() local order={"Balanced","Fast Clear","Max Damage","Safe Clear","Boss"}; local i=table.find(order,App.State.Objective) or 1; App.State.Objective=order[i%#order+1]; objBtn.Text=App.State.Objective; task.spawn(function() App.RefreshAnalysis() end) end)
local econChip=text(teamPage,"AUTO ECONOMY",UDim2.fromOffset(190,0),UDim2.fromOffset(410,28),true); econChip.TextSize=11
local currentLabel=text(teamPage,"CURRENT HOTBAR",UDim2.fromOffset(0,38),UDim2.fromOffset(200,22),true)
local currentCards=Instance.new("ScrollingFrame"); currentCards.Size=UDim2.new(1,0,0,164); currentCards.Position=UDim2.fromOffset(0,64); currentCards.BackgroundTransparency=1; currentCards.BorderSizePixel=0; currentCards.ScrollBarThickness=3; currentCards.ScrollingDirection=Enum.ScrollingDirection.X; currentCards.Parent=teamPage
local recLabel=text(teamPage,"RECOMMENDED",UDim2.fromOffset(0,238),UDim2.fromOffset(200,22),true)
local recCards=currentCards:Clone(); recCards.Position=UDim2.fromOffset(0,264); recCards.Parent=teamPage
local compareBox=text(teamPage,"",UDim2.fromOffset(0,438),UDim2.new(1,0,0,120),false); compareBox.BackgroundTransparency=0; compareBox.BackgroundColor3=Color3.fromRGB(22,25,36); compareBox.TextColor3=Color3.fromRGB(184,191,210); compareBox.TextSize=11; compareBox.BorderSizePixel=0; Instance.new("UICorner",compareBox).CornerRadius=UDim.new(0,8)

local stagePage=pages["Stage"]; local stageTitle=text(stagePage,"STAGE + AUTO ECONOMY",UDim2.fromOffset(0,0),UDim2.fromOffset(300,24),true); local stageText=text(stagePage,"",UDim2.fromOffset(0,38),UDim2.new(1,0,1,-44),false); stageText.BackgroundTransparency=0; stageText.BackgroundColor3=Color3.fromRGB(22,25,36); stageText.BorderSizePixel=0; Instance.new("UICorner",stageText).CornerRadius=UDim.new(0,8)

local livePage=pages["Live Assist"]; local liveTitle=text(livePage,"LIVE ASSIST • TOP VIEW",UDim2.fromOffset(0,0),UDim2.fromOffset(300,24),true)
local mapFrame=Instance.new("Frame"); mapFrame.Size=UDim2.new(.66,0,1,-42); mapFrame.Position=UDim2.fromOffset(0,38); mapFrame.BackgroundColor3=Color3.fromRGB(18,22,31); mapFrame.BorderSizePixel=0; mapFrame.ClipsDescendants=true; mapFrame.Parent=livePage; Instance.new("UICorner",mapFrame).CornerRadius=UDim.new(0,10)
local liveInfo=text(livePage,"",UDim2.new(.68,8,0,38),UDim2.new(.32,-8,1,-42),false); liveInfo.BackgroundTransparency=0; liveInfo.BackgroundColor3=Color3.fromRGB(22,25,36); liveInfo.BorderSizePixel=0; liveInfo.TextSize=11; Instance.new("UICorner",liveInfo).CornerRadius=UDim.new(0,10)
button(livePage,"REFRESH",UDim2.new(1,-110,0,0),110,function() task.spawn(function() App.RefreshLive() end) end)

local placementPage=pages["Placement"]; local placeStatus=text(placementPage,"Placement scan not run",UDim2.fromOffset(0,48),UDim2.new(1,0,1,-56),false); placeStatus.BackgroundTransparency=0; placeStatus.BackgroundColor3=Color3.fromRGB(22,25,36); placeStatus.BorderSizePixel=0; Instance.new("UICorner",placeStatus).CornerRadius=UDim.new(0,8)
button(placementPage,"SCAN PATH + SPOTS",UDim2.fromOffset(0,0),170,function() task.spawn(function() App.ScanPlacement() end) end)

local overview=pages["Overview"]; local overviewText=text(overview,"",UDim2.fromOffset(0,0),UDim2.fromScale(1,1),false)
local unitPage=pages["Unit DB"]; local unitScroll=Instance.new("ScrollingFrame"); unitScroll.Size=UDim2.fromScale(1,1); unitScroll.BackgroundTransparency=1; unitScroll.BorderSizePixel=0; unitScroll.ScrollBarThickness=4; unitScroll.Parent=unitPage
local diag=pages["Diagnostics"]; local diagText=text(diag,"",UDim2.fromScale(0,0),UDim2.fromScale(1,1),false)

local function drawLine(parent,a,b,thickness,color)
    local d=b-a; local f=Instance.new("Frame"); f.AnchorPoint=Vector2.new(.5,.5); f.Position=UDim2.fromOffset((a.X+b.X)/2,(a.Y+b.Y)/2); f.Size=UDim2.fromOffset(d.Magnitude,thickness or 3); f.Rotation=math.deg(math.atan2(d.Y,d.X)); f.BackgroundColor3=color or Color3.fromRGB(110,126,186); f.BorderSizePixel=0; f.Parent=parent; Instance.new("UICorner",f).CornerRadius=UDim.new(1,0); return f
end
local function drawMap(path,actions)
    clearChildren(mapFrame)
    if not path or #path.Points<2 then text(mapFrame,"PATH NOT FOUND\nRun Placement → SCAN PATH + SPOTS",UDim2.fromScale(0,0),UDim2.fromScale(1,1),true).TextXAlignment=Enum.TextXAlignment.Center; return end
    local minx,maxx,minz,maxz=math.huge,-math.huge,math.huge,-math.huge; for _,pt in ipairs(path.Points) do local p=pt.P; minx=math.min(minx,p.X);maxx=math.max(maxx,p.X);minz=math.min(minz,p.Z);maxz=math.max(maxz,p.Z) end
    for _,a in ipairs(actions or {}) do if a.Candidate then local p=a.Candidate.Position; minx=math.min(minx,p.X);maxx=math.max(maxx,p.X);minz=math.min(minz,p.Z);maxz=math.max(maxz,p.Z) end end
    local W,H=mapFrame.AbsoluteSize.X,mapFrame.AbsoluteSize.Y; if W<10 then W=500;H=500 end; local pad=28; local sx=(W-pad*2)/math.max(1,maxx-minx); local sz=(H-pad*2)/math.max(1,maxz-minz); local scale=math.min(sx,sz)
    local function project(p) return Vector2.new(pad+(p.X-minx)*scale,pad+(p.Z-minz)*scale) end
    for i=1,#path.Points-1 do drawLine(mapFrame,project(path.Points[i].P),project(path.Points[i+1].P),5,Color3.fromRGB(94,108,163)) end
    local start=text(mapFrame,"START",UDim2.fromOffset(project(path.Points[1].P).X-22,project(path.Points[1].P).Y-24),UDim2.fromOffset(45,18),true); start.TextSize=9
    for i,a in ipairs(actions or {}) do if a.Candidate and i<=3 then local c=a.Candidate; local pp=project(c.Position); local dia=(c.Range or 10)*2*scale; local ring=Instance.new("Frame"); ring.AnchorPoint=Vector2.new(.5,.5); ring.Position=UDim2.fromOffset(pp.X,pp.Y); ring.Size=UDim2.fromOffset(dia,dia); ring.BackgroundTransparency=.82; ring.BackgroundColor3= i==1 and Color3.fromRGB(84,235,157) or Color3.fromRGB(116,139,210); ring.BorderSizePixel=0; ring.Parent=mapFrame; Instance.new("UICorner",ring).CornerRadius=UDim.new(1,0); local stroke=Instance.new("UIStroke",ring); stroke.Thickness=i==1 and 3 or 1.5; stroke.Color=i==1 and Color3.fromRGB(107,255,179) or Color3.fromRGB(150,165,225); local dot=Instance.new("Frame"); dot.AnchorPoint=Vector2.new(.5,.5); dot.Position=UDim2.fromOffset(pp.X,pp.Y); dot.Size=UDim2.fromOffset(12,12); dot.BackgroundColor3=i==1 and Color3.fromRGB(107,255,179) or Color3.fromRGB(150,165,225); dot.BorderSizePixel=0; dot.Parent=mapFrame; Instance.new("UICorner",dot).CornerRadius=UDim.new(1,0); local lab=text(mapFrame,"#"..i.." "..a.Profile.Name,UDim2.fromOffset(pp.X+8,pp.Y-10),UDim2.fromOffset(140,20),true); lab.TextSize=9 end end
end

local function worldSpot(a)
    for _,v in ipairs(App.Visuals) do pcall(function() v:Destroy() end) end; App.Visuals={}
    if not a or not a.Candidate then return end; local c=a.Candidate; local p=Instance.new("Part"); p.Name="AE_BestSpot"; p.Shape=Enum.PartType.Cylinder; p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.Material=Enum.Material.Neon; p.Color=Color3.fromRGB(94,255,170); p.Transparency=.72; p.Size=Vector3.new(.18,c.Range*2,c.Range*2); p.CFrame=CFrame.new(c.Position+Vector3.new(0,.08,0))*CFrame.Angles(0,0,math.rad(90)); p.Parent=WS; App.Visuals[#App.Visuals+1]=p
    local beam=Instance.new("Part"); beam.Anchored=true; beam.CanCollide=false; beam.CanQuery=false; beam.Material=Enum.Material.Neon; beam.Color=p.Color; beam.Transparency=.15; beam.Size=Vector3.new(.5,7,.5); beam.Position=c.Position+Vector3.new(0,3.5,0); beam.Parent=WS; App.Visuals[#App.Visuals+1]=beam
end

function App.RefreshAnalysis()
    S.Scan=scanProfile(); S.Profiles=S.Scan.Found and buildOwned(S.Scan) or {}; S.Stage=detectStage(); S.Facts=extractStage(S.Stage)
    S.Current={}; for _,h in ipairs(S.Scan.Hotbar or {}) do local p=S.Profiles[h.Asset]; if p then S.Current[#S.Current+1]=p end end
    local farmTotal,farmWave,farmLines=farmPotential(S.Current,S.Facts.WaveCount)
    local budget=S.Facts.BaseBudget; if budget<=0 then budget=math.max(1,(S.Facts.StartingYen or 0)) end
    S.Recommended=recommend(S.Profiles,S.Current,S.Facts,budget,math.max(1,#S.Current>0 and #S.Current or 6),App.State.Objective)
    local cm,rm=metrics(S.Current,budget),metrics(S.Recommended,budget)
    clearChildren(currentCards); clearChildren(recCards); local cw=126; for i,p in ipairs(S.Current) do card(currentCards,p,(i-1)*cw,0,118,156,"S"..i) end; currentCards.CanvasSize=UDim2.fromOffset(#S.Current*cw,0)
    for i,p in ipairs(S.Recommended) do card(recCards,p,(i-1)*cw,0,118,156,"#"..i) end; recCards.CanvasSize=UDim2.fromOffset(#S.Recommended*cw,0)
    econChip.Text=string.format("AUTO BUDGET  ¥%s  • KILL %s  • WAVE %s  • FARM %s/w",fmt(budget,0),fmt(S.Facts.KillIncome,0),fmt(S.Facts.WaveIncome,0),fmt(farmWave,0))
    compareBox.Text=string.format("BUDGET DPS   %s  →  %s\nFULL CEILING %s  →  %s\nCC TYPES     %d → %d     SHIELD COUNTERS %d → %d\nFARM SLOTS   %d → %d\n\nBudget is derived from stage/runtime evidence. No manual budget input.",fmt(cm.BudgetDPS,0),fmt(rm.BudgetDPS,0),fmt(cm.FullDPS,0),fmt(rm.FullDPS,0),setCount(cm.CC),setCount(rm.CC),cm.Shield,rm.Shield,cm.Farm,rm.Farm)
    local st=S.Stage and (S.Stage.Gamemode.." | "..S.Stage.MapName.." | "..S.Stage.ActName.." | "..S.Stage.Difficulty) or "UNKNOWN"
    stageText.Text=string.format("%s\n\nStarting Yen     %s\nKill income      %s\nWave/Round income %s\nBase obtainable  %s\nFarm current cap %s/wave%s\nWave count       %s\nNo-Farm          %s\n\nEnemy types: %d\nEconomy sources: %s\n\nUnknown: %s",st,fmt(S.Facts.StartingYen,0),fmt(S.Facts.KillIncome,0),fmt(S.Facts.WaveIncome,0),fmt(S.Facts.BaseBudget,0),fmt(farmWave,0),S.Facts.WaveCount and ("  • projected "..fmt(farmTotal,0)) or "",tostring(S.Facts.WaveCount or "?"),tostring(S.Facts.NoFarm),keys(S.Facts.Enemies),#S.Facts.EconomySources>0 and table.concat(S.Facts.EconomySources,"\n") or "none validated",#S.Facts.Unknown>0 and table.concat(S.Facts.Unknown,", ") or "none")
    overviewText.Text=string.format("OWNED %d  • HOTBAR %d\nSTAGE %s\nAUTO BUDGET ¥%s\n\nUse Team Advisor for visual cards.\nUse Live Assist for top-view path + action spotlight.\nUse Placement to force a path/spot rescan.",#(S.Scan.Owned or {}),#(S.Scan.Hotbar or {}),st,fmt(S.Facts.BaseBudget,0))
    diagText.Text="DB SOURCES\n"; for n,src in pairs(Source) do diagText.Text..=n.." = "..src.."\n" end; diagText.Text..="\nProfile: "..tostring(S.Scan.Path or S.Scan.Reason).."\nPlaceId: "..game.PlaceId..(game.PlaceId==EXPECTED_PLACE and " (expected)" or " (different)")
    clearChildren(unitScroll); local arr={}; for _,p in pairs(S.Profiles) do arr[#arr+1]=p end; table.sort(arr,function(a,b) return a.Name<b.Name end); local cols=6; for i,p in ipairs(arr) do local x=((i-1)%cols)*126; local y=math.floor((i-1)/cols)*166; card(unitScroll,p,x,y,118,156) end; unitScroll.CanvasSize=UDim2.fromOffset(0,math.ceil(#arr/cols)*166)
end

function App.ScanPlacement()
    if not S.Scan then App.RefreshAnalysis() end
    S.Path=scanPath(); local lines={}
    if not S.Path then placeStatus.Text="PATH SCAN FAILED\n\nSearched Workspace.Map descendants for Path / Waypoints / Nodes / EnemyWaypoints with BasePart, Attachment, CFrameValue or Vector3Value children.\n\nThis is why the old Placement tab appeared to do nothing: it had no useful visible failure state."; drawMap(nil,{}); return end
    lines[#lines+1]="PATH FOUND"; lines[#lines+1]=S.Path.Source; lines[#lines+1]=string.format("%d points • %s studs",#S.Path.Points,fmt(S.Path.Length,1)); lines[#lines+1]=""
    local n=0; for _,h in ipairs(S.Scan.Hotbar or {}) do local p=S.Profiles[h.Asset]; if p then local c=placementFor(p,S.Path,3); if #c>0 then lines[#lines+1]=p.Name; for i,v in ipairs(c) do lines[#lines+1]=string.format("  #%d  cover %s studs (%s%%)  @ %.1f, %.1f, %.1f",i,fmt(v.Coverage,1),fmt(v.Ratio*100,0),v.Position.X,v.Position.Y,v.Position.Z) end; n+=#c end end end
    if n==0 then lines[#lines+1]="No ground-valid candidates were raycast. Path works, but placement ground needs another locator for this map." end
    placeStatus.Text=table.concat(lines,"\n"); App.RefreshLive()
end

function App.RefreshLive()
    if not S.Scan then App.RefreshAnalysis() end; if not S.Path then S.Path=scanPath() end
    S.Live=liveState(); S.Placed=scanPlaced(); S.Actions=nextAction(S.Profiles,S.Scan.Hotbar,S.Path,S.Placed,S.Live.Yen)
    drawMap(S.Path,S.Actions); worldSpot(S.Actions[1])
    local a=S.Actions[1]; local lines={"RUNTIME", "Yen: "..tostring(S.Live.Yen and ("¥"..fmt(S.Live.Yen,0)) or "UNKNOWN"),"Wave: "..tostring(S.Live.Wave or "UNKNOWN"),"Placed owned: "..#S.Placed,""}
    if a then lines[#lines+1]="BEST NEXT ACTION"; lines[#lines+1]=a.Text; lines[#lines+1]="Cost ¥"..fmt(a.Cost,0); lines[#lines+1]="Gain/¥ "..fmt(a.Efficiency,3); if a.Candidate then lines[#lines+1]="Path coverage "..fmt(a.Candidate.Coverage,1).." studs"; lines[#lines+1]=string.format("Spot %.1f, %.1f, %.1f",a.Candidate.Position.X,a.Candidate.Position.Y,a.Candidate.Position.Z) end; lines[#lines+1]=""; lines[#lines+1]="Green circle on top-view = same green spotlight in world." else lines[#lines+1]="NO ACTION RANKED"; lines[#lines+1]=S.Path and "Path found; no affordable/validated place-or-upgrade action." or "Path missing; run Placement scan." end
    liveInfo.Text=table.concat(lines,"\n")
end

close.MouseButton1Click:Connect(function() App.Destroy() end)
-- drag window
local dragging,dragStart,startPos=false,nil,nil
title.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true;dragStart=i.Position;startPos=main.Position end end)
UIS.InputChanged:Connect(function(i) if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then local d=i.Position-dragStart; main.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y) end end)
UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)

function App.Destroy()
    for _,c in ipairs(App.Connections) do pcall(function() c:Disconnect() end) end
    for _,v in ipairs(App.Visuals) do pcall(function() v:Destroy() end) end
    if gui then gui:Destroy() end; if ENV.AE_STRATEGIST_V2==App then ENV.AE_STRATEGIST_V2=nil end
end

show("Team Advisor")
task.spawn(function() local ok,e=pcall(App.RefreshAnalysis); if not ok then diagText.Text="ANALYSIS ERROR\n"..tostring(e); notify("Analysis error: "..tostring(e)) end; task.wait(.2); pcall(App.ScanPlacement) end)
notify("Visual V2 loaded • unit cards + top-view + auto economy")
print("[AE Strategist V2] READY",VERSION)
