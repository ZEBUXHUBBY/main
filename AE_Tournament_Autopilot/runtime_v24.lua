-- AE Tournament Brain V2.4 runtime evidence layer
-- Read-only: listens to the same Replica events the game client receives.
return function(Brain)
    if type(Brain) ~= "table" then return Brain end

    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = Players.LocalPlayer
    local remotes = ReplicatedStorage:FindFirstChild("RemoteEvents")

    local R = {
        Version = "V2.4-RUNTIME",
        Units = {},
        Enemies = {},
        Game = {},
        Economy = {},
        Connections = {},
        Evidence = {},
    }
    Brain.RuntimeV24 = R

    local function copyShallow(t)
        local o = {}
        if type(t) == "table" then for k,v in pairs(t) do o[k]=v end end
        return o
    end

    local function merge(dst, src)
        if type(dst) ~= "table" or type(src) ~= "table" then return dst end
        for k,v in pairs(src) do dst[k]=v end
        return dst
    end

    local function pathStrings(path)
        local out = {}
        if type(path) == "table" then
            for i,v in ipairs(path) do out[i] = tostring(v) end
        end
        return out
    end

    local function pathHas(parts, needles)
        for _,part in ipairs(parts) do
            local p = part:lower()
            for _,needle in ipairs(needles) do
                if p == needle or p:find(needle,1,true) then return true end
            end
        end
        return false
    end

    local function evidence(text)
        R.Evidence[#R.Evidence+1] = string.format("%.2f %s", os.clock(), tostring(text))
        if #R.Evidence > 80 then table.remove(R.Evidence,1) end
    end

    local function ingestReplica(id, kind, data)
        id = tostring(id or "")
        if id == "" or type(data) ~= "table" then return end
        if kind == "GameUnit" then
            local u = R.Units[id] or {ReplicaId=id}
            merge(u, data)
            u.ReplicaId = id
            u.Kind = kind
            if type(data.CurrentStats)=="table" then u.CurrentStats=copyShallow(data.CurrentStats) end
            if type(data.NextStats)=="table" then u.NextStats=copyShallow(data.NextStats) end
            R.Units[id] = u
            evidence("GameUnit create "..id)
        elseif kind == "GameSpawnedEnemy" then
            local e = R.Enemies[id] or {ReplicaId=id}
            merge(e, data)
            e.ReplicaId=id; e.Kind=kind
            R.Enemies[id]=e
            evidence("Enemy create "..id.." "..tostring(data.Name or data.Type or "?"))
        elseif kind == "Game" or kind == "PlayerGame" then
            merge(R.Game,data)
        end
    end

    local function ingestCreate(payload)
        if type(payload) ~= "table" then return end
        for id,row in pairs(payload) do
            if type(row)=="table" then
                local kind=row[1]
                local data=row[3]
                if type(kind)=="string" and type(data)=="table" then ingestReplica(id,kind,data) end
            end
        end
    end

    local function setNestedKnown(unit, parts, value)
        local first = parts[1]
        if not first then return end
        if first=="CurrentStats" and parts[2] then
            unit.CurrentStats=unit.CurrentStats or {}; unit.CurrentStats[parts[2]]=value
        elseif first=="NextStats" and parts[2] then
            unit.NextStats=unit.NextStats or {}; unit.NextStats[parts[2]]=value
        elseif first=="TargetPriority" or first=="Upgrade" or first=="SellValue" or first=="MaxUpgrade" or first=="IsFarm" or first=="CFrame" or first=="Element" or first=="IsAttacking" then
            unit[first]=value
        end
    end

    local function onSet(replicaId, path, value)
        local id=tostring(replicaId or "")
        local parts=pathStrings(path)
        local u=R.Units[id]
        local e=R.Enemies[id]
        if u then setNestedKnown(u,parts,value) end
        if e and parts[1] then
            local k=parts[1]
            if k=="Speed" or k=="Overhealth" or k=="DeathPredicted" or k=="TargetPosition" or k=="Health" or k=="HP" or k=="CFrame" or k=="Debuffs" or k=="Mechanics" or k=="ModifiersData" or k=="Attributes" then e[k]=value end
        end
        if pathHas(parts,{"yen","money","cash"}) and tonumber(value) then R.Economy.Yen=tonumber(value);R.Economy.YenSource="ReplicaSet:"..table.concat(parts,".") end
        if pathHas(parts,{"waveincome"}) and tonumber(value) then R.Economy.WaveIncome=tonumber(value) end
        if pathHas(parts,{"wave"}) and tonumber(value) then R.Game.Wave=tonumber(value) end
        if pathHas(parts,{"enemycount"}) and tonumber(value) then R.Game.EnemyCount=tonumber(value) end
    end

    local function onSetValues(replicaId, path, values)
        local id=tostring(replicaId or "")
        if type(values)~="table" then return end
        local u=R.Units[id]
        if not u and (values.CurrentStats or values.IsFarm~=nil or values.Upgrade~=nil or values.SellValue~=nil) then
            u={ReplicaId=id,Kind="GameUnit"};R.Units[id]=u
        end
        if u then
            for _,key in ipairs({"SellValue","MaxUpgrade","Unsellable","IsFarm","Upgrade","TargetPriority","CFrame","Element","IsAttacking"}) do
                if values[key]~=nil then u[key]=values[key] end
            end
            if type(values.CurrentStats)=="table" then u.CurrentStats=copyShallow(values.CurrentStats) end
            if type(values.NextStats)=="table" then u.NextStats=copyShallow(values.NextStats) end
            if u.IsFarm or (u.CurrentStats and (u.CurrentStats.HitboxType=="Farm" or tonumber(u.CurrentStats.Farm))) then
                u.IsFarm=true
                evidence("Farm runtime "..id.." U"..tostring(u.Upgrade or "?").." income="..tostring(u.CurrentStats and u.CurrentStats.Farm))
            end
        end
    end

    local function scanGuiYen()
        if tonumber(R.Economy.Yen) then return R.Economy.Yen,R.Economy.YenSource end
        local pg=LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
        if not pg then return nil,nil end
        local best=nil
        for _,d in ipairs(pg:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") then
                local context=(d.Name.." "..(d.Parent and d.Parent.Name or "")):lower()
                if context:find("yen",1,true) or context:find("money",1,true) or context:find("cash",1,true) then
                    local cleaned=tostring(d.Text):gsub("[,¥$%s]","")
                    local n=tonumber(cleaned:match("%d+%.?%d*"))
                    if n and (not best or n>best.Value) then best={Value=n,Source=d:GetFullName()} end
                end
            end
        end
        if best then R.Economy.Yen=best.Value;R.Economy.YenSource=best.Source;return best.Value,best.Source end
        return nil,nil
    end

    local function runtimeSnapshot()
        local out={Units={},Enemies={},FarmUnits={},FarmIncomePerWave=0,FarmSellValue=0,PlacedCount=0,EnemyCount=0,Game=copyShallow(R.Game),EvidenceCount=#R.Evidence}
        for id,u in pairs(R.Units) do
            local ownerOk=(u.Owner==nil or u.Owner==LocalPlayer)
            if ownerOk then
                out.Units[id]=u;out.PlacedCount+=1
                local stats=u.CurrentStats or {}
                if u.IsFarm or stats.HitboxType=="Farm" or tonumber(stats.Farm) then
                    out.FarmUnits[id]=u
                    out.FarmIncomePerWave+=tonumber(stats.Farm) or 0
                    out.FarmSellValue+=tonumber(u.SellValue) or 0
                end
            end
        end
        for id,e in pairs(R.Enemies) do out.Enemies[id]=e;out.EnemyCount+=1 end
        local yen,source=scanGuiYen();out.Yen=yen;out.YenSource=source
        return out
    end

    local function reconcileState(state)
        if type(state)~="table" then return state end
        local snap=runtimeSnapshot();state.Runtime=snap
        state.Live=state.Live or {}
        if snap.Yen~=nil then state.Live.Yen=snap.Yen;state.Live.YenSource=snap.YenSource end
        state.Confidence=state.Confidence or {}
        state.Confidence.Runtime="REPLICA OBSERVED"

        if next(snap.FarmUnits)~=nil then
            local chosen=nil
            for _,u in pairs(snap.FarmUnits) do chosen=u;break end
            local stats=chosen and chosen.CurrentStats or {}
            state.FarmPlan={
                Decision="USE",
                RuntimeObserved=true,
                Exact=true,
                TargetLevel=tonumber(chosen and chosen.Upgrade) or 0,
                IncomePerWave=snap.FarmIncomePerWave,
                SellValue=snap.FarmSellValue,
                Cost=tonumber(stats.Cost),
                Reason="Runtime Farm observed from ReplicaSetValues: ¥"..string.format("%.0f",snap.FarmIncomePerWave).." per wave across active Farm units.",
            }
        elseif state.FarmPlan and state.FarmPlan.Decision=="UNKNOWN" then
            state.FarmPlan.RuntimeObserved=false
            state.FarmPlan.Reason=(state.FarmPlan.Reason or "Farm unresolved").." No active Farm replica has been observed yet."
        end
        return state
    end

    if remotes then
        local create=remotes:FindFirstChild("ReplicaCreate")
        if create and create:IsA("RemoteEvent") then R.Connections[#R.Connections+1]=create.OnClientEvent:Connect(function(payload) pcall(ingestCreate,payload) end) end
        local set=remotes:FindFirstChild("ReplicaSet")
        if set and set:IsA("RemoteEvent") then R.Connections[#R.Connections+1]=set.OnClientEvent:Connect(function(id,path,value) pcall(onSet,id,path,value) end) end
        local setv=remotes:FindFirstChild("ReplicaSetValues")
        if setv and setv:IsA("RemoteEvent") then R.Connections[#R.Connections+1]=setv.OnClientEvent:Connect(function(id,path,values) pcall(onSetValues,id,path,values) end) end
        local destroy=remotes:FindFirstChild("ReplicaDestroy")
        if destroy and destroy:IsA("RemoteEvent") then R.Connections[#R.Connections+1]=destroy.OnClientEvent:Connect(function(id) id=tostring(id or "");R.Units[id]=nil;R.Enemies[id]=nil end) end
    end

    local oldAnalyze=Brain.Analyze
    if type(oldAnalyze)=="function" then
        function Brain:Analyze(...)
            local state,err=oldAnalyze(self,...)
            if state then reconcileState(state) end
            return state,err
        end
    end

    local oldRefresh=Brain.RefreshTactical
    if type(oldRefresh)=="function" then
        function Brain:RefreshTactical(...)
            local state,err=oldRefresh(self,...)
            if state then reconcileState(state) end
            return state,err
        end
    end

    function Brain:GetRuntimeV24()
        return runtimeSnapshot()
    end

    local oldDestroy=Brain.Destroy
    function Brain:Destroy(...)
        for _,c in ipairs(R.Connections) do pcall(function()c:Disconnect()end) end
        R.Connections={}
        if type(oldDestroy)=="function" then return oldDestroy(self,...) end
    end

    evidence("runtime layer ready")
    return Brain
end
