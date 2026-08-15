--[[
AE STRATEGIST | OWNED COPY STAT ENGINE
--------------------------------------
Enhances the standalone core without replacing it.
Uses the exact owned UnitData record (Level/Trait/Equipment/StatPotential) for ranking.
It first tries the game's own client UnitStats processor. If unavailable, it falls back
only to modifiers whose semantics are explicit (Trait and explicit equipment/level fields).
Ambiguous StatPotential.Range values are DETECTED but never guessed as modifiers.
]]

local VERSION = "owned-stats-1.0"
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HS = game:GetService("HttpService")
local LP = Players.LocalPlayer
local ENV = getgenv and getgenv() or _G
local Core = ENV.AE_STRATEGIST
if type(Core) ~= "table" or type(Core.GetState) ~= "function" then return end

local Engine = {Version=VERSION, Cache={}, Processor=nil, ProcessorLabel=nil}
ENV.AE_STRATEGIST_OWNED_STATS = Engine
Core.OwnedStats = Engine

local function norm(v) return tostring(v or ""):lower():gsub("[^%w]","") end
local function ci(t,names)
    if type(t)~="table" then return nil,nil end
    local wanted={}; for _,n in ipairs(names) do wanted[norm(n)]=true end
    for k,v in pairs(t) do if wanted[norm(k)] then return v,k end end
end
local function count(t) local n=0; for _ in pairs(t or {}) do n=n+1 end; return n end
local function shallow(t) local o={}; for k,v in pairs(t or {}) do o[k]=v end; return o end
local function arrcopy(t) local o={}; for i,v in ipairs(t or {}) do o[i]=v end; return o end
local function json(url)
    local ok,b=pcall(function() return game:HttpGet(url) end); if not ok then return {} end
    local ok2,v=pcall(function() return HS:JSONDecode(b) end); return ok2 and type(v)=="table" and v or {}
end
local RAW="https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_DB/"

local function safeRequire(m)
    if not m or not m:IsA("ModuleScript") then return nil end
    local ok,v=pcall(require,m); if ok then return v end
end
local Info=RS:FindFirstChild("Shared") and RS.Shared:FindFirstChild("Information")
local Traits=(Info and safeRequire(Info:FindFirstChild("Traits"))) or json(RAW.."traits.json")

local function findModule(name, mustContain)
    local best
    for _,d in ipairs(RS:GetDescendants()) do
        if d:IsA("ModuleScript") and d.Name==name then
            local full=norm(d:GetFullName())
            local ok=true
            for _,hint in ipairs(mustContain or {}) do if not full:find(norm(hint),1,true) then ok=false break end end
            if ok then best=d; break end
        end
    end
    return best
end

local LevelModule=findModule("UnitLevelInfo",{"SheetSyncedModules"})
local EquipmentModule=findModule("Equipment",{"SheetSyncedModules"})
local LevelDB=safeRequire(LevelModule)
local EquipmentDB=safeRequire(EquipmentModule)

local UnitStatsModules={}
for _,d in ipairs(RS:GetDescendants()) do
    if d:IsA("ModuleScript") and d.Name=="UnitStats" then
        local f=norm(d:GetFullName())
        if f:find("processor",1,true) or f:find("asset",1,true) then UnitStatsModules[#UnitStatsModules+1]=d end
    end
end

local function numberCI(t,names)
    local v=ci(t,names); return tonumber(v)
end
local function findStatTable(root,depth,seen)
    if type(root)~="table" then return nil end
    depth=depth or 0; if depth>6 then return nil end
    seen=seen or {}; if seen[root] then return nil end; seen[root]=true
    local dmg=numberCI(root,{"Damage","DMG","CurrentDamage"})
    local spa=numberCI(root,{"SPA","AttackSpeed","AttackCooldown","CurrentSPA"})
    local rng=numberCI(root,{"Range","RNG","CurrentRange"})
    if dmg and spa and rng and dmg>=0 and spa>0 and rng>0 then
        return {
            Damage=dmg, SPA=spa, Range=rng,
            CritChance=numberCI(root,{"CritChance","CriticalChance"}),
            CritDamage=numberCI(root,{"CritDamage","CriticalDamage"}),
        }
    end
    for _,v in pairs(root) do if type(v)=="table" then local r=findStatTable(v,depth+1,seen); if r then return r end end end
end

local processorFns={}
local function collectProcessorFns()
    if #processorFns>0 then return end
    for _,m in ipairs(UnitStatsModules) do
        local exp=safeRequire(m)
        if type(exp)=="function" then processorFns[#processorFns+1]={Fn=exp,Owner=nil,Label=m:GetFullName().." <function>"} end
        if type(exp)=="table" then
            for k,v in pairs(exp) do
                if type(v)=="function" then
                    local nk=norm(k)
                    if nk:find("stat",1,true) or nk:find("get",1,true) or nk:find("calc",1,true) or nk:find("compute",1,true) or nk:find("process",1,true) or nk:find("build",1,true) then
                        processorFns[#processorFns+1]={Fn=v,Owner=exp,Label=m:GetFullName().."."..tostring(k)}
                    end
                end
            end
        end
    end
end

local function plausible(actual,base)
    if not actual or not base or not base.Damage or not base.SPA or not base.Range then return false end
    if base.Damage<=0 or base.SPA<=0 or base.Range<=0 then return false end
    local dr=actual.Damage/base.Damage; local sr=actual.SPA/base.SPA; local rr=actual.Range/base.Range
    return dr>=0.15 and dr<=12 and sr>=0.25 and sr<=3 and rr>=0.45 and rr<=3
end

local function tryGameProcessor(asset,data,base)
    collectProcessorFns()
    if Engine.Processor then
        local p=Engine.Processor
        local variants={
            {data}, {asset,data}, {data,asset}, {p.Owner,data}, {p.Owner,asset,data},
            {{Asset=asset,Data=data}}, {asset,data,0}, {data,0},
        }
        for _,args in ipairs(variants) do
            local ok,res=pcall(p.Fn,table.unpack(args))
            local st=ok and findStatTable(res) or nil
            if st and plausible(st,base) then return st,p.Label end
        end
        Engine.Processor=nil
    end
    for _,p in ipairs(processorFns) do
        local variants={
            {data}, {asset,data}, {data,asset}, {p.Owner,data}, {p.Owner,asset,data},
            {{Asset=asset,Data=data}}, {asset,data,0}, {data,0},
        }
        for _,args in ipairs(variants) do
            local ok,res=pcall(p.Fn,table.unpack(args))
            local st=ok and findStatTable(res) or nil
            if st and plausible(st,base) then Engine.Processor=p; Engine.ProcessorLabel=p.Label; return st,p.Label end
        end
    end
end

local function explicitMods(entry)
    if type(entry)~="table" then return nil end
    local out={}
    local function take(names,key)
        local v=numberCI(entry,names)
        if v and math.abs(v)<=5 then out[key]=v end
    end
    take({"DamageMultiplier","DamagePercent","DamageIncrease","Damage"},"Damage")
    take({"SPAMultiplier","SPAPercent","SPAIncrease","SPA"},"SPA")
    take({"RangeMultiplier","RangePercent","RangeIncrease","Range"},"Range")
    take({"CritChance","CriticalChance"},"CritChance")
    take({"CritDamage","CriticalDamage"},"CritDamage")
    take({"Cost","CostMultiplier","CostPercent"},"Cost")
    take({"Farm","FarmIncome","IncomeMultiplier"},"Farm")
    return count(out)>0 and out or nil
end

local function lookupLevelMods(level)
    if type(LevelDB)~="table" then return nil end
    local e=LevelDB[level] or LevelDB[tostring(level)]
    if type(e)~="table" then
        local levels=ci(LevelDB,{"Levels","LevelData","UnitLevels"})
        if type(levels)=="table" then e=levels[level] or levels[tostring(level)] end
    end
    if type(e)~="table" then return nil end
    -- Only accept explicit modifier-shaped fields. EXP-only rows are ignored.
    return explicitMods(e)
end

local function gatherStrings(root,out,depth,seen)
    out=out or {}; depth=depth or 0; seen=seen or {}
    if depth>5 then return out end
    if type(root)=="string" then out[#out+1]=root; return out end
    if type(root)~="table" or seen[root] then return out end; seen[root]=true
    for k,v in pairs(root) do
        if type(v)=="string" then
            local nk=norm(k)
            if nk:find("asset",1,true) or nk:find("equipment",1,true) or nk=="id" or nk=="name" then out[#out+1]=v end
        elseif type(v)=="table" then gatherStrings(v,out,depth+1,seen) end
    end
    return out
end

local function equipmentInfo(eq)
    if eq==nil then return {},nil end
    local labels,mods={},{}
    local function merge(m)
        if not m then return end
        for k,v in pairs(m) do mods[k]=(mods[k] or 0)+v end
    end
    if type(eq)=="table" then merge(explicitMods(eq)) end
    local strings=gatherStrings(eq)
    local used={}
    for _,s in ipairs(strings) do
        if not used[s] then
            used[s]=true
            local row=type(EquipmentDB)=="table" and (EquipmentDB[s] or EquipmentDB[norm(s)]) or nil
            if type(row)=="table" then
                labels[#labels+1]=tostring(ci(row,{"DisplayName","Name"}) or s)
                merge(explicitMods(row))
                local stats=ci(row,{"Stats","StatValues","Modifiers"}); if type(stats)=="table" then merge(explicitMods(stats)) end
            elseif #s<60 then labels[#labels+1]=s:gsub("#.*$","") end
        end
    end
    if #labels==0 and type(eq)=="string" then labels[1]=eq:gsub("#.*$","") end
    return labels,count(mods)>0 and mods or nil
end

local function potentialInfo(pot)
    local labels,mods={},{}
    if type(pot)~="table" then return labels,nil end
    for stat,row in pairs(pot) do
        if type(row)=="table" then
            local grade=ci(row,{"Potential","Grade"})
            if grade then labels[#labels+1]=tostring(stat).." "..tostring(grade) end
            -- Do NOT use the ambiguous field named Range. Only explicit modifier/value keys.
            local v=numberCI(row,{"Value","Modifier","StatIncrease","Percent","Bonus"})
            if v and math.abs(v)<=5 then mods[stat]=v end
        end
    end
    table.sort(labels)
    return labels,count(mods)>0 and mods or nil
end

local function traitMods(name)
    local row=type(Traits)=="table" and Traits[name] or nil
    return row,explicitMods(row)
end

local function critFactor(chance,damage)
    local c=tonumber(chance) or 0; local d=tonumber(damage) or 0
    if c>1 then c=c/100 end
    if d>5 then d=d/100 end
    c=math.max(0,c); d=math.max(0,d)
    return 1+c*d
end

local function applyMod(base,mod,mode)
    base=tonumber(base); mod=tonumber(mod); if not base or not mod then return base end
    if mode=="multiplier" then return base*mod end
    return base*(1+mod)
end

local function effectiveCopy(template,record)
    if not template or not record or type(record.Data)~="table" then return nil end
    local data=record.Data
    local out=shallow(template)
    out.OwnedRecord=record
    out.OwnedLevel=tonumber(ci(data,{"Level"})) or 1
    out.OwnedTrait=tostring(ci(data,{"Trait"}) or "No Trait")
    local eqLabels,eqMods=equipmentInfo(ci(data,{"Equipment","Equipments"}))
    out.EquipmentLabels=eqLabels
    out.EquipmentLabel=#eqLabels>0 and table.concat(eqLabels,",") or "No Equip"
    if #out.EquipmentLabel>18 then out.EquipmentLabel=out.EquipmentLabel:sub(1,17).."…" end
    local potLabels,potMods=potentialInfo(ci(data,{"StatPotential","Potential"}))
    out.PotentialLabels=potLabels
    out.PotentialLabel=#potLabels>0 and table.concat(potLabels," • ") or "No Potential"

    local traitRow,tmods=traitMods(out.OwnedTrait)
    local lmods=lookupLevelMods(out.OwnedLevel)
    local base=template.Base
    local exact,exactSource=tryGameProcessor(template.Asset,data,base)
    local dmgMul,spaMul,rangeMul=1,1,1
    local ccAdd,cdAdd=0,0
    local fidelity={Level=false,Trait=false,Equipment=false,Potential=false,GameProcessor=false}
    local sources={}

    if exact then
        dmgMul=exact.Damage/base.Damage; spaMul=exact.SPA/base.SPA; rangeMul=exact.Range/base.Range
        fidelity.GameProcessor=true; fidelity.Level=true; fidelity.Trait=true; fidelity.Equipment=true; fidelity.Potential=true
        sources[#sources+1]="GAME UNITSTATS"
    else
        if lmods then
            if lmods.Damage then dmgMul=dmgMul*(1+lmods.Damage) end
            if lmods.SPA then spaMul=spaMul*(1+lmods.SPA) end
            if lmods.Range then rangeMul=rangeMul*(1+lmods.Range) end
            ccAdd=ccAdd+(lmods.CritChance or 0); cdAdd=cdAdd+(lmods.CritDamage or 0)
            fidelity.Level=true; sources[#sources+1]="LEVEL EXPLICIT"
        end
        if tmods then
            if tmods.Damage then dmgMul=dmgMul*(1+tmods.Damage) end
            if tmods.SPA then spaMul=spaMul*(1+tmods.SPA) end
            if tmods.Range then rangeMul=rangeMul*(1+tmods.Range) end
            ccAdd=ccAdd+(tmods.CritChance or 0); cdAdd=cdAdd+(tmods.CritDamage or 0)
            fidelity.Trait=true; sources[#sources+1]="TRAIT EXACT"
        end
        if eqMods then
            if eqMods.Damage then dmgMul=dmgMul*(1+eqMods.Damage) end
            if eqMods.SPA then spaMul=spaMul*(1+eqMods.SPA) end
            if eqMods.Range then rangeMul=rangeMul*(1+eqMods.Range) end
            ccAdd=ccAdd+(eqMods.CritChance or 0); cdAdd=cdAdd+(eqMods.CritDamage or 0)
            fidelity.Equipment=true; sources[#sources+1]="EQUIP EXPLICIT"
        end
        if potMods then
            if potMods.Damage then dmgMul=dmgMul*(1+potMods.Damage) end
            if potMods.SPA then spaMul=spaMul*(1+potMods.SPA) end
            if potMods.Range then rangeMul=rangeMul*(1+potMods.Range) end
            fidelity.Potential=true; sources[#sources+1]="POTENTIAL EXPLICIT"
        end
    end

    local placement=tonumber(template.PlacementLimit) or 1
    local costMul,farmMul=1,1
    if traitRow then
        if tonumber(traitRow.PlacementLimit) then placement=tonumber(traitRow.PlacementLimit) end
        if tonumber(traitRow.Cost) then costMul=1+tonumber(traitRow.Cost) end
        if tonumber(traitRow.Farm) then farmMul=1+tonumber(traitRow.Farm) end
    end
    if eqMods then
        if eqMods.Cost then costMul=costMul*(1+eqMods.Cost) end
        if eqMods.Farm then farmMul=farmMul*(1+eqMods.Farm) end
    end
    out.PlacementLimit=placement
    out.Upgrades={}
    local cumulative=0
    for _,u0 in ipairs(template.Upgrades or {}) do
        local u=shallow(u0)
        u.Damage=(tonumber(u0.Damage) or 0)*dmgMul
        u.SPA=math.max(.01,(tonumber(u0.SPA) or 1)*spaMul)
        u.Range=(tonumber(u0.Range) or 0)*rangeMul
        u.Cost=math.max(0,(tonumber(u0.Cost) or 0)*costMul)
        cumulative=cumulative+u.Cost; u.CumulativeCost=cumulative
        if tonumber(u0.Income) then u.Income=tonumber(u0.Income)*farmMul end
        local cc=tonumber(u0.CritChance) or 0; local cd=tonumber(u0.CritDamage) or 0
        if exact and exact.CritChance~=nil then cc=exact.CritChance else cc=cc+ccAdd end
        if exact and exact.CritDamage~=nil then cd=exact.CritDamage else cd=cd+cdAdd end
        u.CritChance=cc; u.CritDamage=cd
        u.RawDPS=(u.Damage/u.SPA)*critFactor(cc,cd)
        u.EffectiveDPS=u.RawDPS
        out.Upgrades[#out.Upgrades+1]=u
    end
    out.Base=out.Upgrades[1]; out.Final=out.Upgrades[#out.Upgrades]
    out.StatFidelity=fidelity
    out.StatSources=sources
    out.StatSourceLabel=#sources>0 and table.concat(sources," + ") or "BASE + DETECTED ONLY"
    local applied=0; for _,v in pairs(fidelity) do if v then applied=applied+1 end end
    out.StatConfidence=fidelity.GameProcessor and "EXACT GAME" or (applied>=3 and "HIGH" or (applied>=1 and "PARTIAL" or "BASE ONLY"))
    return out
end

local function findBudget(core)
    if not core.Gui then return nil end
    for _,d in ipairs(core.Gui:GetDescendants()) do if d:IsA("TextBox") and norm(d.PlaceholderText)=="budget" then return tonumber(d.Text) end end
end

local function metric(team,budget)
    local m={Team=team,EarlyDPS=0,MidDPS=0,BudgetDPS=0,FullDPS=0,CC={},Shield=0,Farm=0}
    local function dpsAt(p,b)
        local best=0
        for _,u in ipairs(p.Upgrades or {}) do if (u.CumulativeCost or math.huge)<=b then best=math.max(best,u.RawDPS or 0) end end
        return best
    end
    local n=math.max(1,#team); local share=(budget or 50000)/n
    for _,p in ipairs(team) do
        local lim=math.max(1,tonumber(p.PlacementLimit) or 1)
        m.EarlyDPS=m.EarlyDPS+dpsAt(p,share*.25)*lim
        m.MidDPS=m.MidDPS+dpsAt(p,share*.5)*lim
        m.BudgetDPS=m.BudgetDPS+dpsAt(p,share)*lim
        m.FullDPS=m.FullDPS+((p.Final and p.Final.RawDPS) or 0)*lim
        for k in pairs(p.CC or {}) do m.CC[k]=true end
        if p.ShieldCounter then m.Shield=m.Shield+1 end
        if p.Farm then m.Farm=m.Farm+1 end
    end
    return m
end
local function setCount(t) local n=0; for _ in pairs(t or {}) do n=n+1 end; return n end
local function score(p,budget,strategy,facts)
    if not p or not p.Base or not p.Final then return -math.huge end
    if facts and facts.NoFarm and p.Farm then return -math.huge end
    local best=0
    for _,u in ipairs(p.Upgrades or {}) do if (u.CumulativeCost or math.huge)<=budget then best=math.max(best,u.RawDPS or 0) end end
    local lim=math.max(1,tonumber(p.PlacementLimit) or 1)
    local utility=setCount(p.CC)*160+(p.Buff and 220 or 0)+(p.ShieldCounter and 260 or 0)+(p.Boss and 180 or 0)
    if strategy=="Max Damage" then return (p.Final.RawDPS or 0)*lim+utility*.15 end
    if strategy=="Fast Clear" then return best*lim*1.7+((p.Base.CumulativeCost or 0)>0 and best/(p.Base.CumulativeCost)*12000 or 0)+utility*.45 end
    if strategy=="Safe Clear" then return best*lim+utility*2 end
    if strategy=="Boss" then return (p.Final.RawDPS or 0)*lim+(p.Boss and 1200 or 0)+utility end
    return best*lim+utility
end

local function chooseTeam(candidates,size,budget,strategy,facts)
    local arr={}; for _,p in pairs(candidates) do arr[#arr+1]=p end
    table.sort(arr,function(a,b) return score(a,budget/math.max(1,size),strategy,facts)>score(b,budget/math.max(1,size),strategy,facts) end)
    local out={}; for _,p in ipairs(arr) do if score(p,budget/math.max(1,size),strategy,facts)>-math.huge then out[#out+1]=p; if #out>=size then break end end end
    return out
end

function Engine.EnhanceState()
    local state=Core.GetState(); if not state or not state.Scan or not state.Profiles then return state end
    local templates=state.Profiles
    local byAsset={}
    for _,r in ipairs(state.Scan.Owned or {}) do
        local a=r.Asset
        local template=templates[a]
        if template then
            local e=effectiveCopy(template,r)
            if e then byAsset[a]=byAsset[a] or {}; byAsset[a][#byAsset[a]+1]=e end
        end
    end
    local best={}
    for a,list in pairs(byAsset) do
        table.sort(list,function(x,y) return ((x.Final and x.Final.RawDPS or 0)*math.max(1,x.PlacementLimit or 1))>((y.Final and y.Final.RawDPS or 0)*math.max(1,y.PlacementLimit or 1)) end)
        best[a]=list[1]
    end

    local current={}; local display=shallow(best)
    for _,h in ipairs(state.Scan.Hotbar or {}) do
        local chosen
        if h.Record then
            local t=templates[h.Asset] or best[h.Asset]
            if t then chosen=effectiveCopy(t,h.Record) end
        end
        chosen=chosen or best[h.Asset]
        if chosen then current[#current+1]=chosen; display[h.Asset]=chosen end
    end
    state.Profiles=display
    state.EffectiveCopies=byAsset
    state.EffectiveCurrentTeam=current
    state.EffectiveBestByAsset=best

    local budget=tonumber(state.Facts and state.Facts.TotalYen) or findBudget(Core) or 50000
    local size=math.max(1,#current>0 and #current or 6)
    local strategy=state.Strategy or "Balanced"
    local recTeam=chooseTeam(best,size,budget,strategy,state.Facts or {})
    state.CurrentMetrics=metric(current,budget)
    state.Recommended=metric(recTeam,budget)
    state.Recommended.Team=recTeam
    state.RecommendationBudget=budget

    local stageMode=norm(state.Stage and state.Stage.Gamemode)
    if stageMode:find("tournament",1,true) then
        state.TournamentRecommendationVerified=false
        state.RecommendationWarning="COMBAT CANDIDATE • TOURNAMENT SCORE MODEL UNVERIFIED"
    else
        state.TournamentRecommendationVerified=true
        state.RecommendationWarning="RECOMMENDED OWNED COPIES"
    end

    local exact,partial,baseOnly=0,0,0
    for _,p in pairs(best) do
        if p.StatConfidence=="EXACT GAME" then exact=exact+1 elseif p.StatConfidence=="BASE ONLY" then baseOnly=baseOnly+1 else partial=partial+1 end
    end
    state.StatFidelity={Exact=exact,Partial=partial,BaseOnly=baseOnly,Processor=Engine.ProcessorLabel}
    return state
end

local original=Core.RefreshAnalysis
if type(original)=="function" and not Core._OwnedStatsWrapped then
    Core._OwnedStatsWrapped=true
    Core._OriginalRefreshAnalysis=original
    Core.RefreshAnalysis=function(...)
        local result=original(...)
        pcall(Engine.EnhanceState)
        return result
    end
end
pcall(Engine.EnhanceState)
print("[AE OwnedStats] READY",VERSION,"processor",Engine.ProcessorLabel or "not resolved yet")
