--[[
AE STRATEGIST | TOURNAMENT ONLY
Manual-snapshot optimizer. No polling, no auto analysis, no gameplay remotes.
Uses the hidden standalone core only as a one-shot inventory/stage scanner.
]]

local VERSION = "tournament-1.0"
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HS = game:GetService("HttpService")
local WS = game:GetService("Workspace")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer
local ENV = getgenv and getgenv() or _G
local Core = ENV.AE_STRATEGIST
if type(Core) ~= "table" or type(Core.GetState) ~= "function" then
    warn("[AE Tournament] hidden core missing")
    return
end

if type(ENV.AE_TOURNAMENT_OPTIMIZER) == "table" and type(ENV.AE_TOURNAMENT_OPTIMIZER.Destroy) == "function" then
    pcall(ENV.AE_TOURNAMENT_OPTIMIZER.Destroy)
end

local App = {Version=VERSION, Connections={}, Destroyed=false, Result=nil, Selected=1, ScoreObserved=nil}
ENV.AE_TOURNAMENT_OPTIMIZER = App

local RAW = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_DB/"
local function norm(v) return tostring(v or ""):lower():gsub("[^%w]","") end
local function ci(t,names)
    if type(t)~="table" then return nil,nil end
    local w={}; for _,n in ipairs(names) do w[norm(n)]=true end
    for k,v in pairs(t) do if w[norm(k)] then return v,k end end
end
local function num(t,names) local v=ci(t,names); return tonumber(v) end
local function count(t) local n=0; for _ in pairs(t or {}) do n+=1 end; return n end
local function shallow(t) local o={}; for k,v in pairs(t or {}) do o[k]=v end; return o end
local function fmt(v,d)
    v=tonumber(v); if not v then return "—" end; d=d or 0
    local a=math.abs(v)
    if a>=1e9 then return string.format("%.2fB",v/1e9) end
    if a>=1e6 then return string.format("%.2fM",v/1e6) end
    if a>=1e3 then return string.format("%.2fK",v/1e3) end
    local s=string.format("%."..d.."f",v); return s:gsub("(%..-)0+$","%1"):gsub("%.$","")
end
local function json(file)
    local ok,b=pcall(function() return game:HttpGet(RAW..file) end); if not ok then return {} end
    local ok2,v=pcall(function() return HS:JSONDecode(b) end); return ok2 and type(v)=="table" and v or {}
end
local function safeRequire(m)
    if not m or not m:IsA("ModuleScript") then return nil end
    local ok,v=pcall(require,m); if ok then return v end
end
local function findModule(name,hints)
    for _,d in ipairs(RS:GetDescendants()) do
        if d:IsA("ModuleScript") and d.Name==name then
            local f=norm(d:GetFullName()); local good=true
            for _,h in ipairs(hints or {}) do if not f:find(norm(h),1,true) then good=false break end end
            if good then return d end
        end
    end
end

local Info = RS:FindFirstChild("Shared") and RS.Shared:FindFirstChild("Information")
local Traits = (Info and safeRequire(Info:FindFirstChild("Traits"))) or json("traits.json")
local TournamentScaling = json("scaling_TournamentScaling.json")
local UnitModels = RS:FindFirstChild("Assets") and RS.Assets:FindFirstChild("Units")
local EquipmentDB = safeRequire(findModule("Equipment",{"SheetSyncedModules"})) or {}
local UnitLevelDB = safeRequire(findModule("UnitLevelInfo",{"SheetSyncedModules"})) or {}
local StatPotentialDB = (Info and safeRequire(Info:FindFirstChild("StatPotential"))) or {}

-- Only specific stat processors; discovery happens once when ANALYZE is pressed.
local ProcessorModules={}
for _,d in ipairs(RS:GetDescendants()) do
    if d:IsA("ModuleScript") and (d.Name=="UnitStats" or d.Name=="UnitStat") then
        local f=norm(d:GetFullName())
        if f:find("processorsasset",1,true) or f:find("processorsgameunit",1,true) then ProcessorModules[#ProcessorModules+1]=d end
    end
end
local ResolvedProcessor=nil

local function findStats(root,depth,seen)
    if type(root)~="table" then return nil end
    depth=depth or 0; if depth>5 then return nil end
    seen=seen or {}; if seen[root] then return nil end; seen[root]=true
    local damage=num(root,{"Damage","DMG","CurrentDamage"})
    local spa=num(root,{"SPA","AttackSpeed","AttackCooldown","CurrentSPA"})
    local range=num(root,{"Range","RNG","CurrentRange"})
    if damage and spa and range and damage>=0 and spa>0 and range>0 then
        return {Damage=damage,SPA=spa,Range=range,CritChance=num(root,{"CritChance","CriticalChance"}),CritDamage=num(root,{"CritDamage","CriticalDamage"})}
    end
    for _,v in pairs(root) do if type(v)=="table" then local r=findStats(v,depth+1,seen); if r then return r end end end
end
local function plausible(s,b)
    if not s or not b or not b.Damage or not b.SPA or not b.Range or b.Damage<=0 or b.SPA<=0 or b.Range<=0 then return false end
    local dr=s.Damage/b.Damage; local sr=s.SPA/b.SPA; local rr=s.Range/b.Range
    return dr>=0.1 and dr<=15 and sr>=0.2 and sr<=4 and rr>=0.35 and rr<=4
end
local function callableExports(m)
    local exp=safeRequire(m); local out={}
    if type(exp)=="function" then out[#out+1]={Fn=exp,Owner=nil,Label=m:GetFullName()} end
    if type(exp)=="table" then
        for k,v in pairs(exp) do
            if type(v)=="function" then
                local n=norm(k)
                if n:find("stat",1,true) or n:find("get",1,true) or n:find("calc",1,true) or n:find("compute",1,true) or n:find("process",1,true) then
                    out[#out+1]={Fn=v,Owner=exp,Label=m:GetFullName().."."..tostring(k)}
                end
            end
        end
    end
    return out
end
local function tryCall(p,asset,data,upgrade,base)
    local variants={
        {data}, {asset,data}, {data,asset}, {{Asset=asset,Data=data}},
        {asset,data,upgrade}, {data,upgrade}, {{Asset=asset,Data=data},upgrade},
    }
    if p.Owner then
        variants[#variants+1]={p.Owner,data}; variants[#variants+1]={p.Owner,asset,data}; variants[#variants+1]={p.Owner,asset,data,upgrade}
    end
    for _,args in ipairs(variants) do
        local ok,res=pcall(p.Fn,table.unpack(args))
        local s=ok and findStats(res) or nil
        if s and plausible(s,base) then return s end
    end
end
local function resolveExactStats(asset,data,base)
    if ResolvedProcessor then
        local s=tryCall(ResolvedProcessor,asset,data,0,base)
        if s then return s,ResolvedProcessor.Label end
        ResolvedProcessor=nil
    end
    for _,m in ipairs(ProcessorModules) do
        for _,p in ipairs(callableExports(m)) do
            local s=tryCall(p,asset,data,0,base)
            if s then ResolvedProcessor=p; return s,p.Label end
        end
    end
end

local function explicitMods(entry)
    if type(entry)~="table" then return nil end
    local o={}
    local function take(names,key)
        local v=num(entry,names)
        if v and math.abs(v)<=5 then o[key]=v end
    end
    take({"DamageMultiplier","DamagePercent","DamageIncrease","Damage"},"Damage")
    take({"SPAMultiplier","SPAPercent","SPAIncrease","SPA"},"SPA")
    take({"RangeMultiplier","RangePercent","RangeIncrease","Range"},"Range")
    take({"CritChance","CriticalChance"},"CritChance")
    take({"CritDamage","CriticalDamage"},"CritDamage")
    take({"Cost","CostMultiplier","CostPercent"},"Cost")
    take({"Farm","FarmIncome","IncomeMultiplier"},"Farm")
    return count(o)>0 and o or nil
end
local function mergeMods(dst,src)
    for k,v in pairs(src or {}) do dst[k]=(dst[k] or 0)+v end
end
local function gatherStrings(root,out,depth,seen)
    out=out or {}; depth=depth or 0; seen=seen or {}
    if type(root)=="string" then out[#out+1]=root; return out end
    if type(root)~="table" or seen[root] or depth>5 then return out end; seen[root]=true
    for k,v in pairs(root) do
        if type(v)=="string" then
            local n=norm(k); if n:find("asset",1,true) or n:find("equipment",1,true) or n=="id" or n=="name" then out[#out+1]=v end
        elseif type(v)=="table" then gatherStrings(v,out,depth+1,seen) end
    end
    return out
end
local function equipmentRow(id)
    if type(EquipmentDB)~="table" then return nil end
    if EquipmentDB[id] then return EquipmentDB[id] end
    local nid=norm(id)
    for k,v in pairs(EquipmentDB) do
        if norm(k)==nid or (type(v)=="table" and (norm(v.Asset)==nid or norm(v.DisplayName)==nid)) then return v,k end
    end
end
local function equipmentMods(eq)
    local mods,labels={},{}
    if type(eq)=="table" then mergeMods(mods,explicitMods(eq)) end
    local seen={}
    for _,s in ipairs(gatherStrings(eq)) do
        s=tostring(s):gsub("#.*$","")
        if s~="" and not seen[s] then
            seen[s]=true; local row=equipmentRow(s)
            if type(row)=="table" then
                labels[#labels+1]=tostring(ci(row,{"DisplayName","Name","Asset"}) or s)
                mergeMods(mods,explicitMods(row)); mergeMods(mods,explicitMods(ci(row,{"Stats","Modifiers","StatValues"})))
            end
        end
    end
    return count(mods)>0 and mods or nil,labels
end
local function potentialLabels(pot)
    local out={}
    for stat,row in pairs(type(pot)=="table" and pot or {}) do
        if type(row)=="table" then local grade=ci(row,{"Potential","Grade"}); if grade then out[#out+1]=tostring(stat).." "..tostring(grade) end end
    end
    table.sort(out); return out
end
local function levelExplicit(level)
    if type(UnitLevelDB)~="table" then return nil end
    local row=UnitLevelDB[level] or UnitLevelDB[tostring(level)]
    if type(row)~="table" then local x=ci(UnitLevelDB,{"Levels","LevelData","UnitLevels"}); if type(x)=="table" then row=x[level] or x[tostring(level)] end end
    return explicitMods(row)
end
local function potentialExplicit(pot)
    -- Ambiguous fields named Range inside the roll record are deliberately ignored.
    local o={}
    for stat,row in pairs(type(pot)=="table" and pot or {}) do
        if type(row)=="table" then
            local v=num(row,{"Value","Modifier","Percent","Bonus","StatIncrease"})
            if v and math.abs(v)<=5 then o[stat]=v end
        end
    end
    return count(o)>0 and o or nil
end
local function critFactor(cc,cd)
    cc=tonumber(cc) or 0; cd=tonumber(cd) or 0
    if cc>1 then cc=cc/100 end; if cd>5 then cd=cd/100 end
    return 1+math.max(0,cc)*math.max(0,cd)
end
local function nativeAdd(base,add,isCritDamage)
    if not add then return base end
    if isCritDamage and (tonumber(base) or 0)>5 then return (tonumber(base) or 0)+add*100 end
    if not isCritDamage and (tonumber(base) or 0)>1 then return (tonumber(base) or 0)+add*100 end
    return (tonumber(base) or 0)+add
end

local function buildCopy(template,record,traitOverride,equipOverride)
    if not template or not template.Base or not record or type(record.Data)~="table" then return nil end
    local data=record.Data; local out=shallow(template)
    out.Record=record; out.Level=tonumber(ci(data,{"Level"})) or 1
    out.Trait=tostring(traitOverride or ci(data,{"Trait"}) or "No Trait")
    out.Potential=potentialLabels(ci(data,{"StatPotential","Potential"}))
    local eqValue=equipOverride~=nil and equipOverride or ci(data,{"Equipment","Equipments"})
    local emods,elabels=equipmentMods(eqValue)
    out.EquipmentLabels=elabels; out.EquipmentLabel=#elabels>0 and table.concat(elabels,", ") or "None"
    local traitRow=type(Traits)=="table" and Traits[out.Trait] or nil
    local tmods=explicitMods(traitRow); local lmods=levelExplicit(out.Level); local pmods=potentialExplicit(ci(data,{"StatPotential","Potential"}))
    local exact,processor=resolveExactStats(out.Asset,data,template.Base)
    local dmgMul,spaMul,rangeMul,costMul,farmMul=1,1,1,1,1; local ccAdd,cdAdd=0,0
    local fidelity={Processor=false,Level=false,Trait=false,Equipment=false,Potential=false}; local sources={}
    if exact and not traitOverride and equipOverride==nil then
        dmgMul=exact.Damage/template.Base.Damage; spaMul=exact.SPA/template.Base.SPA; rangeMul=exact.Range/template.Base.Range
        fidelity.Processor=true; fidelity.Level=true; fidelity.Trait=true; fidelity.Equipment=true; fidelity.Potential=true; sources[#sources+1]="GAME UNITSTATS"
    else
        local function apply(m,label,key)
            if not m then return end
            if m.Damage then dmgMul*=1+m.Damage end; if m.SPA then spaMul*=1+m.SPA end; if m.Range then rangeMul*=1+m.Range end
            if m.Cost then costMul*=1+m.Cost end; if m.Farm then farmMul*=1+m.Farm end
            ccAdd+=m.CritChance or 0; cdAdd+=m.CritDamage or 0; fidelity[key]=true; sources[#sources+1]=label
        end
        apply(lmods,"LEVEL EXPLICIT","Level"); apply(tmods,"TRAIT EXACT","Trait"); apply(emods,"EQUIP EXPLICIT","Equipment"); apply(pmods,"POTENTIAL EXPLICIT","Potential")
    end
    local placement=tonumber(out.PlacementLimit) or 1
    if traitRow and tonumber(traitRow.PlacementLimit) then placement=tonumber(traitRow.PlacementLimit) end
    out.PlacementLimit=placement; out.Upgrades={}; local cumulative=0
    for _,u0 in ipairs(template.Upgrades or {}) do
        local u=shallow(u0); u.Damage=(u0.Damage or 0)*dmgMul; u.SPA=math.max(.01,(u0.SPA or 1)*spaMul); u.Range=(u0.Range or 0)*rangeMul
        u.Cost=(u0.Cost or 0)*costMul; cumulative+=u.Cost; u.CumulativeCost=cumulative
        if u0.Income then u.Income=u0.Income*farmMul end
        local cc=u0.CritChance or 0; local cd=u0.CritDamage or 0
        if exact and exact.CritChance~=nil and not traitOverride and equipOverride==nil then cc=exact.CritChance else cc=nativeAdd(cc,ccAdd,false) end
        if exact and exact.CritDamage~=nil and not traitOverride and equipOverride==nil then cd=exact.CritDamage else cd=nativeAdd(cd,cdAdd,true) end
        u.CritChance=cc; u.CritDamage=cd; u.DPS=(u.Damage/u.SPA)*critFactor(cc,cd); u.RawDPS=u.DPS
        out.Upgrades[#out.Upgrades+1]=u
    end
    out.Base=out.Upgrades[1]; out.Final=out.Upgrades[#out.Upgrades]
    out.CapDPS=(out.Final and out.Final.DPS or 0)*placement
    out.OpenerEfficiency=(out.Base and out.Base.CumulativeCost and out.Base.CumulativeCost>0) and (out.Base.DPS/out.Base.CumulativeCost)*placement or 0
    out.Fidelity=fidelity; out.Sources=sources; out.SourceLabel=#sources>0 and table.concat(sources," + ") or "BASE ONLY"
    return out
end

local function bestCopies(state)
    local byAsset={}
    for _,r in ipairs(state.Scan and state.Scan.Owned or {}) do
        local t=state.Profiles and state.Profiles[r.Asset]
        if t then local c=buildCopy(t,r); if c then byAsset[r.Asset]=byAsset[r.Asset] or {}; table.insert(byAsset[r.Asset],c) end end
    end
    local best={}
    for asset,list in pairs(byAsset) do table.sort(list,function(a,b) return a.CapDPS>b.CapDPS end); best[asset]=list[1] end
    return best,byAsset
end

local function currentTeam(state,best)
    local out={}
    for _,h in ipairs(state.Scan and state.Scan.Hotbar or {}) do
        local c
        if h.Record and state.Profiles[h.Asset] then c=buildCopy(state.Profiles[h.Asset],h.Record) end
        c=c or best[h.Asset]; if c then out[#out+1]=c end
    end
    return out
end

local function stageThreats(state)
    local f=state.Facts or {}; return {
        Shield=#(f.ShieldEnemies or {})>0, Fast=#(f.FastEnemies or {})>0, Boss=#(f.Bosses or {})>0,
        NoFarm=f.NoFarm==true, WaveCount=f.WaveCount,
    }
end
local function setCount(t) local n=0; for _ in pairs(t or {}) do n+=1 end; return n end
local function tournamentRank(c,threat)
    if threat.NoFarm and c.Farm then return -math.huge end
    local utility=0
    if threat.Shield and c.ShieldCounter then utility+=c.CapDPS*.35 end
    if threat.Fast and setCount(c.CC)>0 then utility+=c.CapDPS*.18 end
    if threat.Boss and c.Boss then utility+=c.CapDPS*.15 end
    return c.CapDPS+utility
end
local function chooseTournamentTeam(best,size,threat)
    local arr={}; for _,c in pairs(best) do arr[#arr+1]=c end
    table.sort(arr,function(a,b) return tournamentRank(a,threat)>tournamentRank(b,threat) end)
    local team,used={},{}
    -- One strong opener first when it is not a farm unit.
    local opener
    for _,c in ipairs(arr) do if not c.Farm and (not opener or c.OpenerEfficiency>opener.OpenerEfficiency) then opener=c end end
    if opener then team[#team+1]=opener; used[opener.Asset]=true end
    -- Explicit threat coverage.
    local function addWhere(pred)
        if #team>=size then return end
        local pick
        for _,c in ipairs(arr) do if not used[c.Asset] and pred(c) and (not pick or tournamentRank(c,threat)>tournamentRank(pick,threat)) then pick=c end end
        if pick then team[#team+1]=pick; used[pick.Asset]=true end
    end
    if threat.Shield then addWhere(function(c) return c.ShieldCounter end) end
    if threat.Fast then addWhere(function(c) return setCount(c.CC)>0 end) end
    for _,c in ipairs(arr) do if #team>=size then break end; if not used[c.Asset] and tournamentRank(c,threat)>-math.huge then team[#team+1]=c; used[c.Asset]=true end end
    return team
end

local function traitAdvice(template,record)
    local rows={}
    for name,row in pairs(type(Traits)=="table" and Traits or {}) do
        if type(row)=="table" then local c=buildCopy(template,record,name,nil); if c then rows[#rows+1]={Name=name,Copy=c,Row=row} end end
    end
    table.sort(rows,function(a,b) return a.Copy.CapDPS>b.Copy.CapDPS end)
    local high=rows[1]; table.sort(rows,function(a,b) return a.Copy.OpenerEfficiency>b.Copy.OpenerEfficiency end); local early=rows[1]
    return high,early
end
local function equipmentAdvice(template,record)
    local rows={}; local seen=0
    for key,row in pairs(type(EquipmentDB)=="table" and EquipmentDB or {}) do
        if type(row)=="table" then
            local mods=explicitMods(row) or explicitMods(ci(row,{"Stats","Modifiers","StatValues"}))
            if mods then
                seen+=1; local id=tostring(ci(row,{"Asset","Name","DisplayName"}) or key); local c=buildCopy(template,record,nil,id)
                if c then rows[#rows+1]={Name=tostring(ci(row,{"DisplayName","Name","Asset"}) or key),Copy=c} end
            end
        end
    end
    table.sort(rows,function(a,b) return a.Copy.CapDPS>b.Copy.CapDPS end)
    return rows[1],seen
end

local function total(team,key)
    local n=0; for _,c in ipairs(team or {}) do n+=tonumber(c[key]) or 0 end; return n
end

-- Proper Viewport renderer from ReplicatedStorage.Assets.Units; no cropped hotbar clone.
local function findAssetModel(asset)
    if not UnitModels then return nil end
    local folder=UnitModels:FindFirstChild(asset)
    if not folder then return nil end
    if folder:IsA("Model") then return folder end
    for _,name in ipairs({"Model","Shiny","Default","Unit"}) do local x=folder:FindFirstChild(name); if x and x:IsA("Model") then return x end end
    return folder:FindFirstChildWhichIsA("Model",true)
end
local function addViewport(parent,asset)
    local vf=Instance.new("ViewportFrame"); vf.Size=UDim2.fromScale(1,1); vf.BackgroundTransparency=1; vf.BorderSizePixel=0; vf.Parent=parent
    local src=findAssetModel(asset); if not src then return vf,false end
    local ok,model=pcall(function() return src:Clone() end); if not ok or not model then return vf,false end
    local world=Instance.new("WorldModel"); world.Parent=vf; model.Parent=world
    for _,d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then d.Anchored=true; d.CanCollide=false end end
    local cf,size=model:GetBoundingBox(); model:PivotTo(CFrame.new(-cf.Position)*model:GetPivot())
    local _,s2=model:GetBoundingBox(); local max=math.max(s2.X,s2.Y,s2.Z,1)
    local cam=Instance.new("Camera"); cam.FieldOfView=32; cam.CFrame=CFrame.new(Vector3.new(max*1.35,max*.18,max*2.4),Vector3.new(0,max*.05,0)); cam.Parent=vf; vf.CurrentCamera=cam
    return vf,true
end

-- GUI -------------------------------------------------------------------------
local parentGui; pcall(function() if gethui then parentGui=gethui() end end); parentGui=parentGui or game:GetService("CoreGui") or LP.PlayerGui
for _,root in ipairs({parentGui,LP:FindFirstChild("PlayerGui")}) do if root then for _,n in ipairs({"AE_Strategist_DashboardV2","AE_Strategist_VisualAddon","AE_Tournament_Only"}) do local x=root:FindFirstChild(n); if x then x:Destroy() end end end end
local gui=Instance.new("ScreenGui"); gui.Name="AE_Tournament_Only"; gui.ResetOnSpawn=false; gui.Parent=parentGui
local function corner(x,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 8); c.Parent=x end
local function label(p,s,pos,size,bold)
    local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; l.Position=pos; l.Size=size; l.Text=s; l.TextColor3=Color3.fromRGB(232,235,243); l.Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham; l.TextSize=11; l.TextXAlignment=Enum.TextXAlignment.Left; l.TextYAlignment=Enum.TextYAlignment.Center; l.TextWrapped=true; l.Parent=p; return l
end
local function btn(p,s,pos,size,cb)
    local b=Instance.new("TextButton"); b.Position=pos; b.Size=size; b.Text=s; b.TextColor3=Color3.new(1,1,1); b.Font=Enum.Font.GothamBold; b.TextSize=11; b.BackgroundColor3=Color3.fromRGB(63,78,126); b.BorderSizePixel=0; b.Parent=p; corner(b,8); App.Connections[#App.Connections+1]=b.MouseButton1Click:Connect(cb); return b
end
local main=Instance.new("Frame"); main.Size=UDim2.fromOffset(960,620); main.Position=UDim2.new(.5,-480,.5,-310); main.BackgroundColor3=Color3.fromRGB(14,17,24); main.BorderSizePixel=0; main.Parent=gui; corner(main,12)
local top=Instance.new("Frame"); top.Size=UDim2.new(1,0,0,54); top.BackgroundColor3=Color3.fromRGB(23,27,38); top.BorderSizePixel=0; top.Parent=main
local title=label(top,"TOURNAMENT OPTIMIZER",UDim2.fromOffset(16,0),UDim2.fromOffset(230,54),true); title.TextSize=15
local status=label(top,"Manual snapshot • no background analyze",UDim2.fromOffset(245,0),UDim2.fromOffset(430,54),false); status.TextColor3=Color3.fromRGB(155,166,191)
local AnalyzeButton
AnalyzeButton=btn(top,"ANALYZE TOURNAMENT",UDim2.new(1,-230,0,11),UDim2.fromOffset(170,32),function() task.spawn(function() App.Analyze() end) end)
btn(top,"×",UDim2.new(1,-50,0,11),UDim2.fromOffset(38,32),function() App.Destroy() end).TextSize=18

local statBar=Instance.new("Frame"); statBar.Position=UDim2.fromOffset(16,68); statBar.Size=UDim2.new(1,-32,0,72); statBar.BackgroundTransparency=1; statBar.Parent=main
local statBoxes={}
for i,name in ipairs({"STAT ACCURACY","COMBAT INDEX","TOURNAMENT MODEL","CURRENT → RECOMMENDED"}) do
    local f=Instance.new("Frame"); f.Position=UDim2.fromOffset((i-1)*230,0); f.Size=UDim2.fromOffset(218,68); f.BackgroundColor3=Color3.fromRGB(23,27,37); f.BorderSizePixel=0; f.Parent=statBar; corner(f,9)
    local t=label(f,name,UDim2.fromOffset(10,6),UDim2.new(1,-20,0,16),true); t.TextSize=8; t.TextColor3=Color3.fromRGB(151,162,187)
    local v=label(f,"—",UDim2.fromOffset(10,23),UDim2.new(1,-20,0,25),true); v.TextSize=16
    local s=label(f,"",UDim2.fromOffset(10,49),UDim2.new(1,-20,0,13),false); s.TextSize=8; s.TextColor3=Color3.fromRGB(151,162,187)
    statBoxes[i]={Value=v,Sub=s}
end
local recTitle=label(main,"BEST TOURNAMENT COMBAT TEAM",UDim2.fromOffset(16,150),UDim2.fromOffset(350,22),true)
local teamScroll=Instance.new("ScrollingFrame"); teamScroll.Position=UDim2.fromOffset(16,176); teamScroll.Size=UDim2.new(1,-32,0,190); teamScroll.BackgroundColor3=Color3.fromRGB(18,21,29); teamScroll.BorderSizePixel=0; teamScroll.ScrollBarThickness=3; teamScroll.ScrollingDirection=Enum.ScrollingDirection.X; teamScroll.AutomaticCanvasSize=Enum.AutomaticSize.X; teamScroll.Parent=main; corner(teamScroll,9)
local layout=Instance.new("UIListLayout"); layout.FillDirection=Enum.FillDirection.Horizontal; layout.Padding=UDim.new(0,8); layout.VerticalAlignment=Enum.VerticalAlignment.Center; layout.Parent=teamScroll
local pad=Instance.new("UIPadding"); pad.PaddingLeft=UDim.new(0,8); pad.PaddingRight=UDim.new(0,8); pad.Parent=teamScroll
local detail=Instance.new("Frame"); detail.Position=UDim2.fromOffset(16,380); detail.Size=UDim2.new(1,-32,1,-396); detail.BackgroundColor3=Color3.fromRGB(22,26,36); detail.BorderSizePixel=0; detail.Parent=main; corner(detail,10)
local detailTitle=label(detail,"SELECT A UNIT",UDim2.fromOffset(14,8),UDim2.new(1,-28,0,22),true); detailTitle.TextSize=13
local detailText=label(detail,"Press ANALYZE TOURNAMENT. Heavy work runs once, then stops.",UDim2.fromOffset(14,36),UDim2.new(1,-28,1,-46),false); detailText.TextSize=10; detailText.TextYAlignment=Enum.TextYAlignment.Top

local function clearCards() for _,c in ipairs(teamScroll:GetChildren()) do if not c:IsA("UIListLayout") and not c:IsA("UIPadding") and not c:IsA("UICorner") then c:Destroy() end end end
local function fidelity(c)
    if c.Fidelity.Processor then return "EXACT GAME" end
    local a=0; for _,v in pairs(c.Fidelity) do if v then a+=1 end end
    return a>=3 and "HIGH" or (a>0 and "PARTIAL" or "BASE")
end
local function renderDetail(c,index)
    if not c then return end
    App.Selected=index; local r=App.Result; local advice=r and r.Advice and r.Advice[c.Asset]
    detailTitle.Text="#"..index.."  "..c.DisplayName.."  •  Lv"..c.Level.."  •  "..c.Trait
    local lines={
        "Effective final DPS: "..fmt(c.Final and c.Final.DPS,1).."   | placement cap ×"..tostring(c.PlacementLimit).."   | cap DPS "..fmt(c.CapDPS,1),
        "Current equipment: "..c.EquipmentLabel,
        "Potential: "..(#c.Potential>0 and table.concat(c.Potential," • ") or "not exposed"),
        "Stat source: "..c.SourceLabel.."  ["..fidelity(c).."]",
        "",
    }
    if advice then
        if advice.TraitHigh then lines[#lines+1]="BEST HIGH-WAVE TRAIT: "..advice.TraitHigh.Name.."  → cap DPS "..fmt(advice.TraitHigh.Copy.CapDPS,1).." ("..fmt((advice.TraitHigh.Copy.CapDPS/c.CapDPS-1)*100,1).."%)" end
        if advice.TraitEarly then lines[#lines+1]="BEST OPENER TRAIT: "..advice.TraitEarly.Name.."  → opener efficiency "..fmt(advice.TraitEarly.Copy.OpenerEfficiency,4) end
        if advice.Equipment then lines[#lines+1]="BEST DB EQUIPMENT: "..advice.Equipment.Name.."  → cap DPS "..fmt(advice.Equipment.Copy.CapDPS,1).."  [theoretical unless owned]" else lines[#lines+1]="BEST EQUIPMENT: no explicit equipment stat table resolved" end
    end
    lines[#lines+1]=""
    lines[#lines+1]="PLACEMENT PRIORITY: place opener first, then fill this unit up to cap when its cap-DPS contribution is higher than the next team's upgrade opportunity. Exact world coordinates are intentionally manual until a real match path exists."
    lines[#lines+1]="TOURNAMENT SCORE: score formula not yet exposed; this optimizer targets wave reach / kill throughput, not a fabricated leaderboard-score estimate."
    detailText.Text=table.concat(lines,"\n")
end
local function card(c,index)
    local f=Instance.new("TextButton"); f.Size=UDim2.fromOffset(138,172); f.Text=""; f.AutoButtonColor=true; f.BackgroundColor3=Color3.fromRGB(28,32,44); f.BorderSizePixel=0; f.Parent=teamScroll; corner(f,9)
    local vis=Instance.new("Frame"); vis.Position=UDim2.fromOffset(6,6); vis.Size=UDim2.fromOffset(126,95); vis.BackgroundColor3=Color3.fromRGB(16,19,27); vis.BorderSizePixel=0; vis.ClipsDescendants=true; vis.Parent=f; corner(vis,7)
    local _,ok=addViewport(vis,c.Asset); if not ok then local ph=label(vis,c.DisplayName:sub(1,1),UDim2.fromScale(0,0),UDim2.fromScale(1,1),true); ph.TextXAlignment=Enum.TextXAlignment.Center; ph.TextSize=30 end
    local badge=label(f,"#"..index,UDim2.fromOffset(7,7),UDim2.fromOffset(31,18),true); badge.BackgroundTransparency=.05; badge.BackgroundColor3=Color3.fromRGB(66,83,132); badge.TextXAlignment=Enum.TextXAlignment.Center; badge.TextSize=8; corner(badge,8)
    local n=label(f,c.DisplayName,UDim2.fromOffset(7,105),UDim2.new(1,-14,0,27),true); n.TextSize=9
    local m=label(f,"Lv"..c.Level.." • "..c.Trait,UDim2.fromOffset(7,132),UDim2.new(1,-14,0,15),false); m.TextSize=8; m.TextColor3=Color3.fromRGB(156,166,189)
    local d=label(f,fmt(c.CapDPS,0).." cap DPS",UDim2.fromOffset(7,149),UDim2.new(1,-14,0,15),true); d.TextSize=9
    App.Connections[#App.Connections+1]=f.MouseButton1Click:Connect(function() renderDetail(c,index) end)
end

function App.Analyze()
    if App.Destroyed then return end
    AnalyzeButton.Text="ANALYZING…"; status.Text="One-shot scan: inventory → stats → tournament team"
    local ok,err=pcall(Core.RefreshAnalysis)
    if not ok then status.Text="Core scan failed: "..tostring(err); AnalyzeButton.Text="ANALYZE TOURNAMENT"; return end
    local state=Core.GetState(); if not state or not state.Scan or not state.Scan.Found then status.Text="Owned inventory not resolved"; AnalyzeButton.Text="ANALYZE TOURNAMENT"; return end
    local best=bestCopies(state); local current=currentTeam(state,best); local threat=stageThreats(state); local size=math.max(1,#current>0 and #current or 6)
    local team=chooseTournamentTeam(best,size,threat); local advice={}
    for _,c in ipairs(team) do
        local t=state.Profiles[c.Asset]; local rec=c.Record
        local high,early=traitAdvice(t,rec); local equip,equipCount=equipmentAdvice(t,rec)
        advice[c.Asset]={TraitHigh=high,TraitEarly=early,Equipment=equip,EquipmentCandidates=equipCount}
    end
    local exact,partial,base=0,0,0
    for _,c in pairs(best) do local f=fidelity(c); if f=="EXACT GAME" then exact+=1 elseif f=="BASE" then base+=1 else partial+=1 end end
    local curD=total(current,"CapDPS"); local recD=total(team,"CapDPS")
    App.Result={State=state,Best=best,Current=current,Team=team,Threat=threat,Advice=advice}
    clearCards(); for i,c in ipairs(team) do card(c,i) end
    statBoxes[1].Value.Text=exact.." exact / "..partial.." partial"; statBoxes[1].Sub.Text=base.." base-only copies"
    statBoxes[2].Value.Text=fmt(recD,0); statBoxes[2].Sub.Text="placement-cap combat DPS"
    statBoxes[3].Value.Text="UNVERIFIED"; statBoxes[3].Sub.Text="optimizes wave reach, not fake score"
    statBoxes[4].Value.Text=fmt(curD,0).." → "..fmt(recD,0); statBoxes[4].Sub.Text=curD>0 and ((recD>=curD and "+" or "")..fmt((recD/curD-1)*100,1).."% cap DPS") or "current unavailable"
    local st=state.Stage; local mode=st and tostring(st.Gamemode) or "UNKNOWN"; local map=st and tostring(st.MapName) or "UNKNOWN"
    status.Text=mode.." • "..map.." • Tournament WaveScaling field "..tostring(TournamentScaling.WaveScaling and TournamentScaling.WaveScaling["1"] or "?").." • no background work"
    if #team>0 then renderDetail(team[1],1) end
    AnalyzeButton.Text="ANALYZE TOURNAMENT"
end

-- Optional ultra-light score observer: exact ReplicaSet leaf only, no scanning and no analysis.
local re=RS:FindFirstChild("RemoteEvents") and RS.RemoteEvents:FindFirstChild("ReplicaSet")
if re and re:IsA("RemoteEvent") then
    App.Connections[#App.Connections+1]=re.OnClientEvent:Connect(function(_,path,value)
        if type(path)~="table" then return end
        local leaf=norm(path[#path]); local joined=""; for _,v in ipairs(path) do joined..=norm(v).."." end
        if type(value)=="number" and (leaf=="score" or leaf=="tournamentscore" or joined:find("tournament",1,true) and leaf:find("score",1,true)) then
            App.ScoreObserved=value; statBoxes[3].Sub.Text="runtime score observed: "..fmt(value,0).." (formula still unknown)"
        end
    end)
end

local dragging=false; local ds,sp
App.Connections[#App.Connections+1]=top.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true; ds=i.Position; sp=main.Position end end)
App.Connections[#App.Connections+1]=UIS.InputChanged:Connect(function(i) if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then local d=i.Position-ds; main.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y) end end)
App.Connections[#App.Connections+1]=UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)
function App.Destroy()
    if App.Destroyed then return end; App.Destroyed=true
    for _,c in ipairs(App.Connections) do pcall(function() c:Disconnect() end) end
    if gui then gui:Destroy() end
    if ENV.AE_TOURNAMENT_OPTIMIZER==App then ENV.AE_TOURNAMENT_OPTIMIZER=nil end
end

print("[AE Tournament] READY",VERSION,"| manual analyze only")