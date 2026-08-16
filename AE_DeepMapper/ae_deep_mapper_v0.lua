-- AE Deep Mapper V0
-- Passive-first Anime Expeditions runtime research layer.
-- This is intentionally separate from Tournament Brain.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local ENV = getgenv and getgenv() or _G
if ENV.AE_DEEP_MAPPER and ENV.AE_DEEP_MAPPER.Destroy then
    pcall(function() ENV.AE_DEEP_MAPPER:Destroy() end)
end

local Mapper = {
    Version = "AE-DM-V0",
    StartedAt = os.time(),
    StartedClock = os.clock(),
    Connections = {},
    Events = {},
    Replicas = {},
    Units = {},
    Enemies = {},
    Zones = {},
    Buffs = {},
    Economy = {},
    Markers = {},
    ClientLogic = {},
    Capabilities = {},
    Destroyed = false,
}
ENV.AE_DEEP_MAPPER = Mapper

local function now()
    return os.clock() - Mapper.StartedClock
end

local function safePath(inst)
    if typeof(inst) ~= "Instance" then return nil end
    local parts, node = {}, inst
    for _ = 1, 64 do
        if not node or node == game then break end
        table.insert(parts, 1, node.Name)
        node = node.Parent
    end
    return table.concat(parts, ".")
end

local function shallowSerializable(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local tv = typeof(v)
    if tv == "nil" or tv == "boolean" or tv == "number" or tv == "string" then return v end
    if tv == "Vector3" then return {__type="Vector3",x=v.X,y=v.Y,z=v.Z} end
    if tv == "Vector2" then return {__type="Vector2",x=v.X,y=v.Y} end
    if tv == "CFrame" then return {__type="CFrame",components={v:GetComponents()}} end
    if tv == "Color3" then return {__type="Color3",r=v.R,g=v.G,b=v.B} end
    if tv == "Instance" then return {__type="Instance",path=safePath(v),class=v.ClassName,name=v.Name} end
    if tv ~= "table" then return {__type=tv,repr=tostring(v)} end
    if seen[v] then return {__cycle=true} end
    if depth >= 8 then return {__truncated=true} end
    seen[v] = true
    local out, n = {}, 0
    for k,val in pairs(v) do
        n += 1
        if n > 300 then out.__more=true break end
        out[tostring(k)] = shallowSerializable(val, depth+1, seen)
    end
    seen[v] = nil
    return out
end

local function push(kind, data)
    local row = {t=now(), kind=kind, data=shallowSerializable(data)}
    Mapper.Events[#Mapper.Events+1] = row
    if #Mapper.Events > 12000 then table.remove(Mapper.Events,1) end
    return row
end

local function merge(dst, src)
    if type(src) ~= "table" then return dst end
    for k,v in pairs(src) do dst[k]=v end
    return dst
end

function Mapper:Mark(label, data)
    local row={t=now(),label=tostring(label),data=shallowSerializable(data)}
    self.Markers[#self.Markers+1]=row
    push("MARK",row)
    print(string.format("[AE-DM] MARK %.3f %s",row.t,row.label))
    return row
end

-- ---------------------------------------------------------------------------
-- Capability detection. Read-only reverse features are only used when present.
-- ---------------------------------------------------------------------------
local caps = {
    "getgc","getloadedmodules","getconnections","getsenv","getscriptclosure",
    "getconstants","getupvalues","getprotos","getproto","getnamecallmethod",
    "hookmetamethod","checkcaller","newcclosure","writefile","makefolder",
}
for _,name in ipairs(caps) do
    Mapper.Capabilities[name] = type(rawget(ENV,name) or rawget(_G,name)) == "function"
end
Mapper.Capabilities.debug_getinfo = type(debug) == "table" and type(debug.getinfo) == "function"
Mapper.Capabilities.debug_getupvalue = type(debug) == "table" and type(debug.getupvalue) == "function"

-- ---------------------------------------------------------------------------
-- Anime Expeditions replica registry
-- ---------------------------------------------------------------------------
local function entityBucket(class)
    if class == "GameUnit" or class == "GamePhantom" then return Mapper.Units end
    if class == "GameSpawnedEnemy" then return Mapper.Enemies end
    if class == "GameZone" then return Mapper.Zones end
    if class == "BuffData" then return Mapper.Buffs end
    return nil
end

local function registerReplica(id, class, data, parent)
    id=tostring(id)
    local r=Mapper.Replicas[id] or {Id=id,CreatedAt=now(),History={}}
    r.Class=class or r.Class
    r.ParentReplica=parent or r.ParentReplica
    r.Data=r.Data or {}
    if type(data)=="table" then merge(r.Data,data) end
    Mapper.Replicas[id]=r
    local bucket=entityBucket(r.Class)
    if bucket then bucket[id]=r end
    return r
end

local function normalizeCreatePayload(payload)
    if type(payload)~="table" then return end
    for id,entry in pairs(payload) do
        if type(entry)=="table" then
            local class=entry[1]
            local data=entry[3]
            local parent=entry[4]
            local r=registerReplica(id,class,data,parent)
            r.History[#r.History+1]={t=now(),op="Create",data=shallowSerializable(data)}
            push("ReplicaCreateDecoded",{id=id,class=class,parent=parent,data=data})
        end
    end
end

local function pathSet(root, path, value)
    if type(root)~="table" or type(path)~="table" then return end
    local node=root
    for i=1,#path-1 do
        local k=tostring(path[i])
        if type(node[k])~="table" then node[k]={} end
        node=node[k]
    end
    if #path>0 then node[tostring(path[#path])]=value end
end

local events = ReplicatedStorage:FindFirstChild("RemoteEvents")
if events then
    local rc=events:FindFirstChild("ReplicaCreate")
    if rc and rc:IsA("RemoteEvent") then
        Mapper.Connections[#Mapper.Connections+1]=rc.OnClientEvent:Connect(function(payload,id)
            push("ReplicaCreateRaw",{payload=payload,id=id})
            normalizeCreatePayload(payload)
        end)
    end

    local rs=events:FindFirstChild("ReplicaSet")
    if rs and rs:IsA("RemoteEvent") then
        Mapper.Connections[#Mapper.Connections+1]=rs.OnClientEvent:Connect(function(id,path,value)
            id=tostring(id)
            local r=registerReplica(id)
            pathSet(r.Data,path,value)
            r.History[#r.History+1]={t=now(),op="Set",path=shallowSerializable(path),value=shallowSerializable(value)}
            push("ReplicaSetDecoded",{id=id,path=path,value=value})
        end)
    end

    local rsv=events:FindFirstChild("ReplicaSetValues")
    if rsv and rsv:IsA("RemoteEvent") then
        Mapper.Connections[#Mapper.Connections+1]=rsv.OnClientEvent:Connect(function(id,path,values)
            id=tostring(id)
            local r=registerReplica(id)
            if type(path)=="table" and #path>0 then
                local target={}
                pathSet(r.Data,path,target)
                if type(values)=="table" then merge(target,values) end
            elseif type(values)=="table" then
                merge(r.Data,values)
            end
            r.History[#r.History+1]={t=now(),op="SetValues",path=shallowSerializable(path),values=shallowSerializable(values)}
            push("ReplicaSetValuesDecoded",{id=id,path=path,values=values})

            if type(values)=="table" and values.CurrentStats and values.CurrentStats.Farm then
                Mapper.Economy[#Mapper.Economy+1]={t=now(),kind="FarmRuntime",replica=id,upgrade=values.Upgrade or r.Data.Upgrade,farm=values.CurrentStats.Farm,sell=values.SellValue or r.Data.SellValue}
            end
        end)
    end

    local rw=events:FindFirstChild("ReplicaWrite")
    if rw and rw:IsA("RemoteEvent") then
        Mapper.Connections[#Mapper.Connections+1]=rw.OnClientEvent:Connect(function(id,writeId,ops)
            id=tostring(id)
            local r=registerReplica(id)
            if type(ops)=="table" then
                for _,op in pairs(ops) do
                    if type(op)=="table" and type(op.path)=="table" then pathSet(r.Data,op.path,op.value) end
                end
            end
            r.History[#r.History+1]={t=now(),op="Write",writeId=writeId,ops=shallowSerializable(ops)}
            push("ReplicaWriteDecoded",{id=id,writeId=writeId,ops=ops})
        end)
    end

    local rd=events:FindFirstChild("ReplicaDestroy")
    if rd and rd:IsA("RemoteEvent") then
        Mapper.Connections[#Mapper.Connections+1]=rd.OnClientEvent:Connect(function(id)
            id=tostring(id)
            local r=Mapper.Replicas[id]
            if r then r.DestroyedAt=now();r.Alive=false;r.History[#r.History+1]={t=now(),op="Destroy"} end
            push("ReplicaDestroyDecoded",{id=id})
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Read-only client logic index. No closure mutation.
-- ---------------------------------------------------------------------------
local DOMAIN_WORDS={
    unit={"unit","tower","placement","upgrade"}, enemy={"enemy","boss","mob","spawn"},
    farm={"farm","income","yen","money"}, tournament={"tournament","score","rank"},
    targeting={"target","priority","first","strongest","fastest","shielded"},
    viewport={"viewport","worldmodel","camera","unitview"}, map={"map","path","waypoint","route"},
    trait={"trait","passive"}, equipment={"equipment","equip"}, wave={"wave","intermission"},
}

local function domainFor(text)
    text=string.lower(tostring(text or ""))
    local hits={}
    for domain,words in pairs(DOMAIN_WORDS) do
        for _,w in ipairs(words) do if text:find(w,1,true) then hits[#hits+1]=domain break end end
    end
    return hits
end

function Mapper:BuildLoadedModuleIndex()
    local out={}
    if not self.Capabilities.getloadedmodules then return out,"getloadedmodules unavailable" end
    local fn=rawget(ENV,"getloadedmodules") or rawget(_G,"getloadedmodules")
    local ok,mods=pcall(fn)
    if not ok or type(mods)~="table" then return out,"getloadedmodules failed" end
    for _,m in ipairs(mods) do
        if typeof(m)=="Instance" and m:IsA("ModuleScript") then
            local path=safePath(m)
            out[#out+1]={path=path,name=m.Name,domains=domainFor(path)}
        end
    end
    self.LoadedModules=out
    return out
end

function Mapper:BuildGCFunctionIndex(limit)
    local out={}
    if not self.Capabilities.getgc then return out,"getgc unavailable" end
    local fn=rawget(ENV,"getgc") or rawget(_G,"getgc")
    local ok,objects=pcall(fn,true)
    if not ok or type(objects)~="table" then return out,"getgc failed" end
    limit=tonumber(limit) or 25000
    local count=0
    for _,obj in ipairs(objects) do
        count+=1;if count>limit then break end
        if type(obj)=="function" then
            local row={kind="function"}
            if type(debug)=="table" and type(debug.getinfo)=="function" then
                local oi,info=pcall(debug.getinfo,obj)
                if oi and type(info)=="table" then
                    row.name=info.name;row.source=info.source;row.line=info.linedefined;row.lastline=info.lastlinedefined
                end
            end
            local constantsFn=rawget(ENV,"getconstants") or rawget(_G,"getconstants")
            if type(constantsFn)=="function" then
                local oc,c=pcall(constantsFn,obj)
                if oc and type(c)=="table" then
                    local strings={}
                    for _,v in ipairs(c) do if type(v)=="string" and #v<=120 then strings[#strings+1]=v end end
                    row.constants=strings
                    row.domains=domainFor(table.concat(strings," ").." "..tostring(row.source or ""))
                end
            end
            if row.domains and #row.domains>0 then out[#out+1]=row end
        end
        if count%5000==0 then task.wait() end
    end
    self.ClientLogic=out
    return out
end

function Mapper:SnapshotRuntime()
    local units,enemies,zones,buffs={},{},{},{}
    for id,r in pairs(self.Units) do if not r.DestroyedAt then units[id]=shallowSerializable(r.Data) end end
    for id,r in pairs(self.Enemies) do if not r.DestroyedAt then enemies[id]=shallowSerializable(r.Data) end end
    for id,r in pairs(self.Zones) do if not r.DestroyedAt then zones[id]=shallowSerializable(r.Data) end end
    for id,r in pairs(self.Buffs) do if not r.DestroyedAt then buffs[id]=shallowSerializable(r.Data) end end
    return {version=self.Version,t=now(),capabilities=self.Capabilities,units=units,enemies=enemies,zones=zones,buffs=buffs,economy=self.Economy,markers=self.Markers}
end

function Mapper:Save(prefix)
    if type(writefile)~="function" then return false,"writefile unavailable" end
    prefix=prefix or "AE_DeepMapper"
    if type(makefolder)=="function" then pcall(makefolder,prefix) end
    local stamp=tostring(os.time())
    local snapshot=self:SnapshotRuntime()
    writefile(prefix.."/runtime_"..stamp..".json",HttpService:JSONEncode(snapshot))
    writefile(prefix.."/events_"..stamp..".json",HttpService:JSONEncode(self.Events))
    if self.LoadedModules then writefile(prefix.."/modules_"..stamp..".json",HttpService:JSONEncode(self.LoadedModules)) end
    if self.ClientLogic then writefile(prefix.."/client_logic_"..stamp..".json",HttpService:JSONEncode(self.ClientLogic)) end
    return true,prefix
end

function Mapper:Destroy()
    if self.Destroyed then return end
    self.Destroyed=true
    for _,c in ipairs(self.Connections) do pcall(function()c:Disconnect()end) end
    self.Connections={}
    if ENV.AE_DEEP_MAPPER==self then ENV.AE_DEEP_MAPPER=nil end
end

print("[AE Deep Mapper V0] loaded")
print("[AE Deep Mapper V0] markers: getgenv().AE_DEEP_MAPPER:Mark('label')")
print("[AE Deep Mapper V0] optional reverse: :BuildLoadedModuleIndex() / :BuildGCFunctionIndex()")
print("[AE Deep Mapper V0] save: :Save()")
return Mapper
