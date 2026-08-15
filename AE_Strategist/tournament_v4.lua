--[[
AE TOURNAMENT OPTIMIZER V4
Manual one-shot Tournament combat optimizer.
No polling, no background analysis, no gameplay remotes.

V4 priorities:
- Always builds a 6-slot Tournament team (confirmed current hotbar size).
- Reads current Tournament modifiers from client UI/state (Boss Waves, Speedy, etc.).
- Uses owned-copy Level/Trait/Equipment/Potential data when explicit formulas are available.
- Never assumes crowd-control works on bosses.
- Trait/equipment what-if advice is lazy: only when a result card is selected.
]]

local VERSION = "tournament-v4.0"
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HS = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer
local ENV = getgenv and getgenv() or _G
local Core = ENV.AE_STRATEGIST
if type(Core) ~= "table" or type(Core.GetState) ~= "function" then
    error("hidden AE_STRATEGIST core missing")
end

if type(ENV.AE_TOURNAMENT_OPTIMIZER) == "table" and type(ENV.AE_TOURNAMENT_OPTIMIZER.Destroy) == "function" then
    pcall(ENV.AE_TOURNAMENT_OPTIMIZER.Destroy)
end

local App = {Version=VERSION, Connections={}, Destroyed=false, Result=nil, Selected=1}
ENV.AE_TOURNAMENT_OPTIMIZER = App

local function norm(v) return tostring(v or ""):lower():gsub("[^%w]","") end
local function ci(t,names)
    if type(t)~="table" then return nil,nil end
    local wanted={}; for _,n in ipairs(names) do wanted[norm(n)]=true end
    for k,v in pairs(t) do if wanted[norm(k)] then return v,k end end
end
local function num(t,names) local v=ci(t,names); return tonumber(v) end
local function shallow(t) local o={}; for k,v in pairs(t or {}) do o[k]=v end; return o end
local function count(t) local n=0; for _ in pairs(t or {}) do n+=1 end; return n end
local function fmt(v,d)
    v=tonumber(v); if not v then return "—" end; d=d or 0
    local a=math.abs(v)
    if a>=1e9 then return string.format("%.2fB",v/1e9) end
    if a>=1e6 then return string.format("%.2fM",v/1e6) end
    if a>=1e3 then return string.format("%.2fK",v/1e3) end
    local s=string.format("%."..d.."f",v)
    return s:gsub("(%..-)0+$","%1"):gsub("%.$","")
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
local function unwrap(t,keys)
    if type(t)~="table" then return {} end
    for _,k in ipairs(keys) do if type(t[k])=="table" and count(t[k])>0 then return t[k] end end
    return t
end

local Info = RS:FindFirstChild("Shared") and RS.Shared:FindFirstChild("Information")
local Traits = (Info and safeRequire(Info:FindFirstChild("Traits"))) or {}
Traits = unwrap(Traits,{"TraitData","Traits","Data","Entries"})
local EquipmentDB = safeRequire(findModule("Equipment",{"SheetSyncedModules"})) or {}
EquipmentDB = unwrap(EquipmentDB,{"EquipmentData","Equipment","Data","Entries","Items"})
local UnitLevelDB = safeRequire(findModule("UnitLevelInfo",{"SheetSyncedModules"})) or {}
UnitLevelDB = unwrap(UnitLevelDB,{"LevelData","Levels","UnitLevels","Data","Entries"})
local UnitModels = RS:FindFirstChild("Assets") and RS.Assets:FindFirstChild("Units")

local function explicitMods(entry)
    if type(entry)~="table" then return nil end
    local o={}
    local function take(names,key)
        local v=num(entry,names)
        if v and math.abs(v)<=5 then o[key]=v end
    end
    take({"DamagePercent","DamageIncrease","Damage"},"Damage")
    take({"SPAPercent","SPAIncrease","SPA"},"SPA")
    take({"RangePercent","RangeIncrease","Range"},"Range")
    take({"CritChance","CriticalChance"},"CritChance")
    take({"CritDamage","CriticalDamage"},"CritDamage")
    take({"Cost","CostPercent"},"Cost")
    take({"Farm","FarmIncome"},"Farm")
    return count(o)>0 and o or nil
end

local function levelModsFromRow(row)
    if type(row)~="table" then return nil end
    local o={}
    local dm=num(row,{"DamageMultiplier","DMGMultiplier","StatMultiplier"})
    local sm=num(row,{"SPAMultiplier","AttackSpeedMultiplier"})
    local rm=num(row,{"RangeMultiplier"})
    if dm and dm>0 and dm<=10 then o.Damage=dm-1 end
    if sm and sm>0 and sm<=10 then o.SPA=sm-1 end
    if rm and rm>0 and rm<=10 then o.Range=rm-1 end
    local function additive(names,key)
        local v=num(row,names); if v and math.abs(v)<=5 then o[key]=v end
    end
    additive({"DamageIncrease","DamagePercent"},"Damage")
    additive({"SPAIncrease","SPAPercent"},"SPA")
    additive({"RangeIncrease","RangePercent"},"Range")
    return count(o)>0 and o or nil
end

local function findLevelMods(root,level,depth,seen)
    if type(root)~="table" then return nil end
    depth=depth or 0; if depth>5 then return nil end
    seen=seen or {}; if seen[root] then return nil end; seen[root]=true
    local direct=root[level] or root[tostring(level)]
    local m=levelModsFromRow(direct); if m then return m end
    if tonumber(ci(root,{"Level","UnitLevel"}))==tonumber(level) then
        m=levelModsFromRow(root); if m then return m end
    end
    for _,v in pairs(root) do
        if type(v)=="table" then local got=findLevelMods(v,level,depth+1,seen); if got then return got end end
    end
end

local function gatherStrings(root,out,depth,seen)
    out=out or {}; depth=depth or 0; seen=seen or {}
    if type(root)=="string" then out[#out+1]=root; return out end
    if type(root)~="table" or seen[root] or depth>5 then return out end; seen[root]=true
    for k,v in pairs(root) do
        if type(v)=="string" then
            local n=norm(k)
            if n:find("asset",1,true) or n:find("equipment",1,true) or n=="id" or n=="name" then out[#out+1]=v end
        elseif type(v)=="table" then gatherStrings(v,out,depth+1,seen) end
    end
    return out
end
local function equipmentRow(id)
    if type(EquipmentDB)~="table" then return nil end
    if EquipmentDB[id] then return EquipmentDB[id] end
    local nid=norm(id)
    for k,v in pairs(EquipmentDB) do
        if norm(k)==nid or (type(v)=="table" and (norm(v.Asset)==nid or norm(v.DisplayName)==nid or norm(v.Name)==nid)) then return v,k end
    end
end
local function mergeMods(dst,src) for k,v in pairs(src or {}) do dst[k]=(dst[k] or 0)+v end end
local function equipmentMods(eq)
    local mods,labels={},{}
    if type(eq)=="table" then mergeMods(mods,explicitMods(eq)) end
    local seen={}
    for _,s in ipairs(gatherStrings(eq)) do
        s=tostring(s):gsub("#.*$","")
        if s~="" and not seen[s] then
            seen[s]=true
            local row=equipmentRow(s)
            if type(row)=="table" then
                labels[#labels+1]=tostring(ci(row,{"DisplayName","Name","Asset"}) or s)
                mergeMods(mods,explicitMods(row))
                mergeMods(mods,explicitMods(ci(row,{"Stats","Modifiers","StatValues"})))
            end
        end
    end
    return count(mods)>0 and mods or nil,labels
end
local function potentialLabels(pot)
    local out={}
    for stat,row in pairs(type(pot)=="table" and pot or {}) do
        if type(row)=="table" then
            local grade=ci(row,{"Potential","Grade"})
            if grade then out[#out+1]=tostring(stat).." "..tostring(grade) end
        end
    end
    table.sort(out); return out
end
local function potentialExplicit(pot)
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
    if cc>1 then cc/=100 end; if cd>5 then cd/=100 end
    return 1+math.max(0,cc)*math.max(0,cd)
end
local function nativeAdd(base,add,isCD)
    if not add then return tonumber(base) or 0 end
    base=tonumber(base) or 0
    if (isCD and base>5) or ((not isCD) and base>1) then return base+add*100 end
    return base+add
end

local function buildCopy(template,record,traitOverride,equipOverride)
    if not template or not template.Base or not record or type(record.Data)~="table" then return nil end
    local data=record.Data; local out=shallow(template)
    out.Record=record; out.Level=tonumber(ci(data,{"Level"})) or 1
    out.Trait=tostring(traitOverride or ci(data,{"Trait"}) or "No Trait")
    out.Potential=potentialLabels(ci(data,{"StatPotential","Potential"}))
    local eq= equipOverride~=nil and equipOverride or ci(data,{"Equipment","Equipments"})
    local emods,elabels=equipmentMods(eq)
    out.EquipmentLabels=elabels; out.EquipmentLabel=#elabels>0 and table.concat(elabels,", ") or "None"
    local traitRow=type(Traits)=="table" and Traits[out.Trait] or nil
    local tmods=explicitMods(traitRow)
    local lmods=findLevelMods(UnitLevelDB,out.Level)
    local pmods=potentialExplicit(ci(data,{"StatPotential","Potential"}))
    local dmgMul,spaMul,rangeMul,costMul,farmMul=1,1,1,1,1; local ccAdd,cdAdd=0,0
    local fidelity={Level=false,Trait=false,Equipment=false,Potential=false}; local sources={}
    local function apply(m,label,key)
        if not m then return end
        if m.Damage then dmgMul*=1+m.Damage end
        if m.SPA then spaMul*=1+m.SPA end
        if m.Range then rangeMul*=1+m.Range end
        if m.Cost then costMul*=1+m.Cost end
        if m.Farm then farmMul*=1+m.Farm end
        ccAdd+=m.CritChance or 0; cdAdd+=m.CritDamage or 0
        fidelity[key]=true; sources[#sources+1]=label
    end
    apply(lmods,"LEVEL EXPLICIT","Level")
    apply(tmods,"TRAIT EXACT","Trait")
    apply(emods,"EQUIP EXPLICIT","Equipment")
    apply(pmods,"POTENTIAL EXPLICIT","Potential")
    local placement=tonumber(out.PlacementLimit) or 1
    if traitRow and tonumber(traitRow.PlacementLimit) then placement=tonumber(traitRow.PlacementLimit) end
    out.PlacementLimit=placement; out.Upgrades={}; local cumulative=0
    for _,u0 in ipairs(template.Upgrades or {}) do
        local u=shallow(u0)
        u.Damage=(tonumber(u0.Damage) or 0)*dmgMul
        u.SPA=math.max(.01,(tonumber(u0.SPA) or 1)*spaMul)
        u.Range=(tonumber(u0.Range) or 0)*rangeMul
        u.Cost=(tonumber(u0.Cost) or 0)*costMul; cumulative+=u.Cost; u.CumulativeCost=cumulative
        if tonumber(u0.Income) then u.Income=tonumber(u0.Income)*farmMul end
        local cc=nativeAdd(u0.CritChance,ccAdd,false); local cd=nativeAdd(u0.CritDamage,cdAdd,true)
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
    for asset,list in pairs(byAsset) do
        table.sort(list,function(a,b) return a.CapDPS>b.CapDPS end); best[asset]=list[1]
    end
    return best,byAsset
end
local function currentTeam(state,best)
    local out={}
    for _,h in ipairs(state.Scan and state.Scan.Hotbar or {}) do
        local c
        if h.Record and state.Profiles[h.Asset] then c=buildCopy(state.Profiles[h.Asset],h.Record) end
        c=c or best[h.Asset]
        if c then out[#out+1]=c end
    end
    return out
end

local function scanModifierText()
    local pieces={}; local pg=LP:FindFirstChild("PlayerGui")
    if pg then
        local n=0
        for _,d in ipairs(pg:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and type(d.Text)=="string" and d.Text~="" then
                n+=1; pieces[#pieces+1]=d.Text
                if n>=650 then break end
            end
        end
    end
    return table.concat(pieces,"\n"):lower()
end
local function stageThreats(state)
    local f=state.Facts or {}; local blob=scanModifierText()
    local bossWaves=blob:find("boss waves",1,true)~=nil or blob:find("all enemies are bosses",1,true)~=nil
    local speedy=blob:find("speedy",1,true)~=nil or blob:find("enemies are 50%% faster")~=nil
    local speedPct=tonumber(blob:match("enemies are%s+(%d+)%%%s+faster"))
    local labels={}
    if bossWaves then labels[#labels+1]="BOSS WAVES" end
    if speedy then labels[#labels+1]="SPEEDY +"..tostring(speedPct or 50).."%" end
    if blob:find("hard mode",1,true) then labels[#labels+1]="HARD MODE" end
    return {
        BossWaves=bossWaves, Speedy=speedy, SpeedPercent=speedPct or (speedy and 50 or nil),
        Shield=#(f.ShieldEnemies or {})>0, Fast=#(f.FastEnemies or {})>0 or speedy,
        Boss=#(f.Bosses or {})>0 or bossWaves, NoFarm=f.NoFarm==true,
        Labels=labels,
    }
end
local function setCount(t) local n=0; for _ in pairs(t or {}) do n+=1 end; return n end
local function positiveBossMechanic(c)
    for _,group in ipairs({c.Passives or {},c.Abilities or {}}) do
        for _,x in ipairs(group) do
            local s=tostring(x.Description or ""):lower()
            if s:find("boss",1,true) and not s:find("cannot",1,true) and not s:find("does not",1,true) then
                if s:find("increase",1,true) or s:find("more damage",1,true) or s:find("damage to",1,true) or s:find("against",1,true) then return true end
            end
        end
    end
    return false
end
local function rankContext(best)
    local maxCap,maxOpen,maxRange,maxHit=1,1,1,1
    for _,c in pairs(best) do
        maxCap=math.max(maxCap,c.CapDPS or 0)
        maxOpen=math.max(maxOpen,c.OpenerEfficiency or 0)
        maxRange=math.max(maxRange,c.Final and c.Final.Range or 0)
        maxHit=math.max(maxHit,c.Final and c.Final.HitboxSize or 0)
    end
    return {MaxCap=maxCap,MaxOpen=maxOpen,MaxRange=maxRange,MaxHit=maxHit}
end
local function tournamentRank(c,threat,ctx,reasons)
    if not c or not c.Final then return -math.huge end
    if threat.NoFarm and c.Farm then return -math.huge end
    if c.Farm and (c.CapDPS or 0)<=0 then return -math.huge end -- economy is not yet score-verified
    ctx=ctx or {MaxCap=1,MaxOpen=1,MaxRange=1,MaxHit=1}
    local capN=(c.CapDPS or 0)/ctx.MaxCap
    local openN=(c.OpenerEfficiency or 0)/ctx.MaxOpen
    local rangeN=(c.Final.Range or 0)/ctx.MaxRange
    local hitN=(c.Final.HitboxSize or 0)/ctx.MaxHit
    local score=capN*70 + openN*15 + rangeN*5 + hitN*5
    if reasons then reasons[#reasons+1]="sustained "..fmt(capN*70,1) end
    if threat.BossWaves then
        score+=rangeN*10
        if positiveBossMechanic(c) then score+=20; if reasons then reasons[#reasons+1]="positive boss mechanic +20" end end
        if reasons then reasons[#reasons+1]="Boss Waves: range uptime +"..fmt(rangeN*10,1) end
    end
    if threat.Speedy then
        score+=rangeN*15
        if reasons then reasons[#reasons+1]="Speedy: range uptime +"..fmt(rangeN*15,1) end
        -- Do not assume stun/freeze/slow affects bosses.
        if not threat.BossWaves and setCount(c.CC)>0 then score+=8; if reasons then reasons[#reasons+1]="CC coverage +8" end end
    elseif threat.Fast and not threat.BossWaves and setCount(c.CC)>0 then
        score+=5
    end
    if threat.Shield and c.ShieldCounter then score+=15; if reasons then reasons[#reasons+1]="shield counter +15" end end
    return score
end
local function chooseTournamentTeam(best,size,threat)
    local ctx=rankContext(best); local arr={}
    for _,c in pairs(best) do arr[#arr+1]=c end
    table.sort(arr,function(a,b) return tournamentRank(a,threat,ctx)>tournamentRank(b,threat,ctx) end)
    local team={}
    for _,c in ipairs(arr) do
        if #team>=size then break end
        if tournamentRank(c,threat,ctx)>-math.huge then team[#team+1]=c end
    end
    return team,ctx
end

local function traitAdvice(template,record,threat,ctx)
    local rows={}
    for name,row in pairs(type(Traits)=="table" and Traits or {}) do
        if type(row)=="table" and (row.Trait or row.DisplayName or row.Description) then
            local c=buildCopy(template,record,name,nil)
            if c then rows[#rows+1]={Name=name,Copy=c,Fit=tournamentRank(c,threat,ctx)} end
        end
    end
    table.sort(rows,function(a,b) return a.Fit>b.Fit end); local fit=rows[1]
    table.sort(rows,function(a,b) return a.Copy.OpenerEfficiency>b.Copy.OpenerEfficiency end); local early=rows[1]
    table.sort(rows,function(a,b) return a.Copy.CapDPS>b.Copy.CapDPS end); local high=rows[1]
    return fit,high,early
end
local function equipmentAdvice(template,record,threat,ctx)
    local rows={}; local seen=0
    for key,row in pairs(type(EquipmentDB)=="table" and EquipmentDB or {}) do
        if type(row)=="table" then
            local mods=explicitMods(row) or explicitMods(ci(row,{"Stats","Modifiers","StatValues"}))
            if mods then
                seen+=1; local id=tostring(ci(row,{"Asset","Name","DisplayName"}) or key)
                local c=buildCopy(template,record,nil,id)
                if c then rows[#rows+1]={Name=tostring(ci(row,{"DisplayName","Name","Asset"}) or key),Copy=c,Fit=tournamentRank(c,threat,ctx)} end
            end
        end
    end
    table.sort(rows,function(a,b) return a.Fit>b.Fit end)
    return rows[1],seen
end
local function total(team,key) local n=0; for _,c in ipairs(team or {}) do n+=tonumber(c[key]) or 0 end; return n end
local function fidelity(c)
    local n=0; for _,v in pairs(c.Fidelity or {}) do if v then n+=1 end end
    return n>=3 and "HIGH" or (n>0 and "PARTIAL" or "BASE")
end

local function findAssetModel(asset)
    if not UnitModels then return nil end
    local folder=UnitModels:FindFirstChild(asset); if not folder then return nil end
    if folder:IsA("Model") then return folder end
    for _,name in ipairs({"Model","Shiny","Default","Unit"}) do local x=folder:FindFirstChild(name); if x and x:IsA("Model") then return x end end
    return folder:FindFirstChildWhichIsA("Model",true)
end
local function addViewport(parent,asset)
    local ok=pcall(function()
        local src=findAssetModel(asset); if not src then error("no model") end
        local vf=Instance.new("ViewportFrame"); vf.Size=UDim2.fromScale(1,1); vf.BackgroundTransparency=1; vf.Parent=parent
        local world=Instance.new("WorldModel"); world.Parent=vf
        local model=src:Clone(); model.Parent=world
        for _,d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then d.Anchored=true; d.CanCollide=false end end
        local cf,size=model:GetBoundingBox(); model:PivotTo(CFrame.new(-cf.Position)*model:GetPivot())
        local _,s=model:GetBoundingBox(); local m=math.max(s.X,s.Y,s.Z,1)
        local cam=Instance.new("Camera"); cam.FieldOfView=34; cam.CFrame=CFrame.new(m*1.25,m*.15,m*2.45, 1,0,0, 0,1,0, 0,0,1); cam.CFrame=CFrame.lookAt(Vector3.new(m*1.25,m*.15,m*2.45),Vector3.new(0,m*.05,0)); cam.Parent=vf; vf.CurrentCamera=cam
    end)
    return ok
end

-- GUI -------------------------------------------------------------------------
local pg=LP:WaitForChild("PlayerGui")
for _,n in ipairs({"AE_Tournament_V4","AE_Tournament_Only","AE_Tournament_BootV4","AE_Tournament_BootV3"}) do local x=pg:FindFirstChild(n); if x then x:Destroy() end end
local gui=Instance.new("ScreenGui"); gui.Name="AE_Tournament_V4"; gui.ResetOnSpawn=false; gui.DisplayOrder=100001; gui.Parent=pg
local function corner(x,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 8); c.Parent=x end
local function label(p,s,pos,size,bold)
    local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; l.Position=pos; l.Size=size; l.Text=s; l.TextColor3=Color3.fromRGB(232,235,243); l.Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham; l.TextSize=11; l.TextXAlignment=Enum.TextXAlignment.Left; l.TextYAlignment=Enum.TextYAlignment.Center; l.TextWrapped=true; l.Parent=p; return l
end
local function btn(p,s,pos,size,cb)
    local b=Instance.new("TextButton"); b.Position=pos; b.Size=size; b.Text=s; b.TextColor3=Color3.new(1,1,1); b.Font=Enum.Font.GothamBold; b.TextSize=11; b.BackgroundColor3=Color3.fromRGB(63,78,126); b.BorderSizePixel=0; b.Parent=p; corner(b,8); App.Connections[#App.Connections+1]=b.MouseButton1Click:Connect(cb); return b
end
local main=Instance.new("Frame"); main.Size=UDim2.fromOffset(980,640); main.Position=UDim2.new(.5,-490,.5,-320); main.BackgroundColor3=Color3.fromRGB(14,17,24); main.BorderSizePixel=0; main.Parent=gui; corner(main,12)
local top=Instance.new("Frame"); top.Size=UDim2.new(1,0,0,56); top.BackgroundColor3=Color3.fromRGB(23,27,38); top.BorderSizePixel=0; top.Parent=main
local title=label(top,"TOURNAMENT OPTIMIZER V4",UDim2.fromOffset(16,0),UDim2.fromOffset(230,56),true); title.TextSize=15
local status=label(top,"Ready • modifier-aware • manual snapshot",UDim2.fromOffset(245,0),UDim2.fromOffset(470,56),false); status.TextColor3=Color3.fromRGB(155,166,191)
local AnalyzeButton; AnalyzeButton=btn(top,"ANALYZE TOURNAMENT",UDim2.new(1,-230,0,12),UDim2.fromOffset(170,32),function() task.spawn(function() App.Analyze() end) end)
btn(top,"×",UDim2.new(1,-50,0,12),UDim2.fromOffset(38,32),function() App.Destroy() end).TextSize=18

local statBar=Instance.new("Frame"); statBar.Position=UDim2.fromOffset(16,70); statBar.Size=UDim2.new(1,-32,0,72); statBar.BackgroundTransparency=1; statBar.Parent=main
local statBoxes={}
for i,name in ipairs({"STAT ACCURACY","COMBAT FIT","ACTIVE MODIFIERS","CURRENT SCAN"}) do
    local f=Instance.new("Frame"); f.Position=UDim2.fromOffset((i-1)*235,0); f.Size=UDim2.fromOffset(223,68); f.BackgroundColor3=Color3.fromRGB(23,27,37); f.BorderSizePixel=0; f.Parent=statBar; corner(f,9)
    local t=label(f,name,UDim2.fromOffset(10,6),UDim2.new(1,-20,0,16),true); t.TextSize=8; t.TextColor3=Color3.fromRGB(151,162,187)
    local v=label(f,"—",UDim2.fromOffset(10,23),UDim2.new(1,-20,0,25),true); v.TextSize=15
    local s=label(f,"",UDim2.fromOffset(10,49),UDim2.new(1,-20,0,13),false); s.TextSize=8; s.TextColor3=Color3.fromRGB(151,162,187)
    statBoxes[i]={Value=v,Sub=s}
end
local recTitle=label(main,"BEST TOURNAMENT COMBAT TEAM",UDim2.fromOffset(16,151),UDim2.fromOffset(700,22),true)
local teamScroll=Instance.new("ScrollingFrame"); teamScroll.Position=UDim2.fromOffset(16,178); teamScroll.Size=UDim2.new(1,-32,0,194); teamScroll.BackgroundColor3=Color3.fromRGB(18,21,29); teamScroll.BorderSizePixel=0; teamScroll.ScrollBarThickness=3; teamScroll.ScrollingDirection=Enum.ScrollingDirection.X; teamScroll.CanvasSize=UDim2.new(); teamScroll.Parent=main; corner(teamScroll,9)
local detail=Instance.new("Frame"); detail.Position=UDim2.fromOffset(16,386); detail.Size=UDim2.new(1,-32,1,-402); detail.BackgroundColor3=Color3.fromRGB(22,26,36); detail.BorderSizePixel=0; detail.Parent=main; corner(detail,10)
local detailTitle=label(detail,"SELECT A UNIT",UDim2.fromOffset(14,8),UDim2.new(1,-28,0,22),true); detailTitle.TextSize=13
local detailText=label(detail,"Press ANALYZE TOURNAMENT. No work runs in the background.",UDim2.fromOffset(14,36),UDim2.new(1,-28,1,-46),false); detailText.TextSize=10; detailText.TextYAlignment=Enum.TextYAlignment.Top

local function clearCards() for _,c in ipairs(teamScroll:GetChildren()) do if not c:IsA("UICorner") then c:Destroy() end end end
local function renderDetail(c,index)
    local r=App.Result; if not c or not r then return end
    App.Selected=index
    local advice=r.Advice[c.Asset]
    if not advice then
        status.Text="Calculating trait/equipment fit for "..c.DisplayName.."…"
        local t=r.State.Profiles[c.Asset]; local rec=c.Record
        local fit,high,early=traitAdvice(t,rec,r.Threat,r.RankContext)
        local equip,equipCount=equipmentAdvice(t,rec,r.Threat,r.RankContext)
        advice={TraitFit=fit,TraitHigh=high,TraitEarly=early,Equipment=equip,EquipmentCandidates=equipCount}
        r.Advice[c.Asset]=advice
        status.Text=r.StatusText
    end
    local reasons={}; local fit=tournamentRank(c,r.Threat,r.RankContext,reasons)
    detailTitle.Text="#"..index.."  "..c.DisplayName.." • Lv"..c.Level.." • "..c.Trait
    local lines={
        "CURRENT COPY  final DPS "..fmt(c.Final and c.Final.DPS,1).."  | placement ×"..c.PlacementLimit.."  | cap DPS "..fmt(c.CapDPS,1).."  | combat-fit "..fmt(fit,1),
        "Equipment: "..c.EquipmentLabel,
        "Potential: "..(#c.Potential>0 and table.concat(c.Potential," • ") or "detected formula unavailable"),
        "Stat source: "..c.SourceLabel.." ["..fidelity(c).."]",
        "",
        "WHY THIS UNIT: "..table.concat(reasons," • "),
    }
    if r.Threat.BossWaves then lines[#lines+1]="BOSS WAVES: CC is NOT credited unless boss compatibility is proven; sustained damage/range get priority." end
    if r.Threat.Speedy then lines[#lines+1]="SPEEDY +"..tostring(r.Threat.SpeedPercent or 50).."%: range uptime is weighted more heavily." end
    lines[#lines+1]=""
    if advice.TraitFit then lines[#lines+1]="BEST TRAIT FOR THESE MODIFIERS: "..advice.TraitFit.Name.." → fit "..fmt(advice.TraitFit.Fit,1).." / cap DPS "..fmt(advice.TraitFit.Copy.CapDPS,1) end
    if advice.TraitHigh then lines[#lines+1]="BEST PURE HIGH-WAVE DPS TRAIT: "..advice.TraitHigh.Name.." → "..fmt(advice.TraitHigh.Copy.CapDPS,1).." cap DPS" end
    if advice.TraitEarly then lines[#lines+1]="BEST OPENER TRAIT: "..advice.TraitEarly.Name end
    if advice.Equipment then lines[#lines+1]="BEST THEORETICAL EQUIPMENT FOR THESE MODIFIERS: "..advice.Equipment.Name.." → fit "..fmt(advice.Equipment.Fit,1).." [ownership not yet verified]" else lines[#lines+1]="Equipment: no explicit stat table resolved" end
    lines[#lines+1]=""
    lines[#lines+1]="Tournament leaderboard score formula is still UNVERIFIED. This is a combat/wave-reach optimizer for the current modifiers, not a fabricated score prediction."
    detailText.Text=table.concat(lines,"\n")
end
local function card(c,index)
    local f=Instance.new("TextButton"); f.Position=UDim2.fromOffset(8+(index-1)*151,10); f.Size=UDim2.fromOffset(143,174); f.Text=""; f.BackgroundColor3=Color3.fromRGB(28,32,44); f.BorderSizePixel=0; f.Parent=teamScroll; corner(f,9)
    local vis=Instance.new("Frame"); vis.Position=UDim2.fromOffset(6,6); vis.Size=UDim2.fromOffset(131,94); vis.BackgroundColor3=Color3.fromRGB(16,19,27); vis.BorderSizePixel=0; vis.ClipsDescendants=true; vis.Parent=f; corner(vis,7)
    if not addViewport(vis,c.Asset) then local ph=label(vis,c.DisplayName:sub(1,1),UDim2.fromScale(0,0),UDim2.fromScale(1,1),true); ph.TextXAlignment=Enum.TextXAlignment.Center; ph.TextSize=31 end
    local badge=label(f,"#"..index,UDim2.fromOffset(7,7),UDim2.fromOffset(31,18),true); badge.BackgroundTransparency=.05; badge.BackgroundColor3=Color3.fromRGB(66,83,132); badge.TextXAlignment=Enum.TextXAlignment.Center; badge.TextSize=8; corner(badge,8)
    local n=label(f,c.DisplayName,UDim2.fromOffset(7,104),UDim2.new(1,-14,0,29),true); n.TextSize=9
    local m=label(f,"Lv"..c.Level.." • "..c.Trait,UDim2.fromOffset(7,133),UDim2.new(1,-14,0,16),false); m.TextSize=8; m.TextColor3=Color3.fromRGB(156,166,189)
    local d=label(f,fmt(c.CapDPS,0).." cap DPS",UDim2.fromOffset(7,151),UDim2.new(1,-14,0,15),true); d.TextSize=9
    App.Connections[#App.Connections+1]=f.MouseButton1Click:Connect(function() renderDetail(c,index) end)
end

function App.Analyze()
    if App.Destroyed then return end
    AnalyzeButton.Text="ANALYZING…"; status.Text="Scanning inventory once…"
    local ok,err=pcall(Core.RefreshAnalysis)
    if not ok then status.Text="Core scan failed: "..tostring(err); AnalyzeButton.Text="ANALYZE TOURNAMENT"; return end
    local state=Core.GetState()
    if not state or not state.Scan or not state.Scan.Found then status.Text="Owned inventory not resolved"; AnalyzeButton.Text="ANALYZE TOURNAMENT"; return end
    status.Text="Building owned-copy stats…"; task.wait()
    local best=bestCopies(state); local current=currentTeam(state,best); local threat=stageThreats(state)
    local team,ctx=chooseTournamentTeam(best,6,threat)
    local exact,partial,base=0,0,0
    for _,c in pairs(best) do local f=fidelity(c); if f=="BASE" then base+=1 elseif f=="PARTIAL" then partial+=1 else exact+=1 end end
    local curD=total(current,"CapDPS"); local recD=total(team,"CapDPS")
    local mods=#threat.Labels>0 and table.concat(threat.Labels," + ") or "no modifier text detected"
    local st=state.Stage; local mode=st and tostring(st.Gamemode) or "Tournament"; local map=st and tostring(st.MapName) or "UNKNOWN"
    local statusText=mode.." • "..map.." • "..mods.." • manual snapshot"
    App.Result={State=state,Best=best,Current=current,Team=team,Threat=threat,RankContext=ctx,Advice={},StatusText=statusText}
    clearCards(); teamScroll.CanvasSize=UDim2.fromOffset(math.max(0,#team*151+16),0)
    for i,c in ipairs(team) do card(c,i) end
    statBoxes[1].Value.Text=partial.." partial / "..base.." base"; statBoxes[1].Sub.Text=exact.." fully explicit copies"
    statBoxes[2].Value.Text=fmt(recD,0); statBoxes[2].Sub.Text="placement-cap DPS before modifier fit bonuses"
    statBoxes[3].Value.Text=mods; statBoxes[3].Sub.Text=threat.BossWaves and "boss CC compatibility not assumed" or "runtime UI/state evidence"
    statBoxes[4].Value.Text=(#current>=6 and (fmt(curD,0).." → "..fmt(recD,0)) or (tostring(#current).."/6 hotbar read")); statBoxes[4].Sub.Text=#current>=6 and ((recD>=curD and "+" or "")..fmt((recD/math.max(curD,1)-1)*100,1).."% cap DPS") or "current comparison suppressed: scan incomplete"
    recTitle.Text="BEST 6-SLOT TEAM • "..mods
    status.Text=statusText
    if #team>0 then renderDetail(team[1],1) end
    AnalyzeButton.Text="ANALYZE TOURNAMENT"
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

print("[AE Tournament V4] READY | modifier-aware | manual analysis only")