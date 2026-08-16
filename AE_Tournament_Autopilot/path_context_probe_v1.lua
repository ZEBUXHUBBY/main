--[[
AE Tournament Autopilot | Path + Context Probe V1
Read-only diagnostic. Captures incoming Replica traffic and inspects Workspace.Map.
No gameplay remotes are fired.
]]

local VERSION = "path-context-probe-v1.0"
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local LP = Players.LocalPlayer
local ENV = getgenv and getgenv() or _G

if type(ENV.AE_PATH_CONTEXT_PROBE) == "table" and type(ENV.AE_PATH_CONTEXT_PROBE.Destroy) == "function" then
    pcall(function() ENV.AE_PATH_CONTEXT_PROBE:Destroy() end)
end

local Probe = {
    Version = VERSION,
    Connections = {},
    CaptureConnections = {},
    Events = {},
    Replicas = {},
    WorkspaceCandidates = {},
    CaptureActive = false,
    Destroyed = false,
}
ENV.AE_PATH_CONTEXT_PROBE = Probe

local function norm(v)
    return tostring(v or ""):lower():gsub("[^%w]", "")
end

local function mask(v)
    local s = tostring(v or "")
    if #s > 30 then return s:sub(1, 12) .. "…" .. s:sub(-6) end
    return s
end

local function pathText(path)
    if type(path) ~= "table" then return tostring(path) end
    local out = {}
    for i = 1, math.min(#path, 16) do out[#out + 1] = tostring(path[i]) end
    return table.concat(out, ".")
end

local function positionOf(instance)
    if not instance then return nil end
    if instance:IsA("Attachment") then return instance.WorldPosition end
    if instance:IsA("BasePart") then return instance.Position end
    if instance:IsA("Vector3Value") then return instance.Value end
    if instance:IsA("CFrameValue") then return instance.Value.Position end
    return nil
end

local function preview(value, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if depth > 2 then return "<depth>" end
    local t = typeof(value)
    if t == "nil" or t == "string" or t == "number" or t == "boolean" then return tostring(value) end
    if t == "Vector3" then return string.format("Vector3(%.2f,%.2f,%.2f)", value.X, value.Y, value.Z) end
    if t == "CFrame" then
        local p = value.Position
        return string.format("CFrame(%.2f,%.2f,%.2f)", p.X, p.Y, p.Z)
    end
    if t == "Instance" then return value:GetFullName() end
    if type(value) ~= "table" then return t end
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local parts, n = {}, 0
    for k, child in pairs(value) do
        n += 1
        if n > 14 then parts[#parts + 1] = "…" break end
        parts[#parts + 1] = tostring(k) .. "=" .. preview(child, depth + 1, seen)
    end
    seen[value] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

local function safe(value, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if depth > 6 then return "<MAX_DEPTH>" end
    local t = typeof(value)
    if t == "nil" or t == "string" or t == "number" or t == "boolean" then return value end
    if t == "Vector3" then return {__type="Vector3", x=value.X, y=value.Y, z=value.Z} end
    if t == "CFrame" then local p=value.Position; return {__type="CFrame", x=p.X,y=p.Y,z=p.Z} end
    if t == "Instance" then return {__type="Instance", class=value.ClassName, path=value:GetFullName()} end
    if type(value) ~= "table" then return tostring(t) end
    if seen[value] then return "<CYCLE>" end
    seen[value] = true
    local out, n = {}, 0
    for k, child in pairs(value) do
        n += 1
        if n > 180 then out["<TRUNCATED>"] = true break end
        out[tostring(k)] = safe(child, depth + 1, seen)
    end
    seen[value] = nil
    return out
end

local function countKeys(t)
    local n=0
    if type(t)=="table" then for _ in pairs(t) do n+=1 end end
    return n
end

local pg = LP:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("AE_PathContextProbe")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "AE_PathContextProbe"
gui.ResetOnSpawn = false
gui.DisplayOrder = 100350
gui.Parent = pg

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(760, 500)
main.Position = UDim2.new(.5, -380, .5, -250)
main.BackgroundColor3 = Color3.fromRGB(13,16,23)
main.BorderSizePixel = 0
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 14)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(18, 10)
title.Size = UDim2.new(1,-70,0,30)
title.Text = "PATH + TOURNAMENT CONTEXT PROBE"
title.Font = Enum.Font.GothamBold
title.TextSize = 17
title.TextColor3 = Color3.fromRGB(244,246,250)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = main

local sub = Instance.new("TextLabel")
sub.BackgroundTransparency = 1
sub.Position = UDim2.fromOffset(18, 39)
sub.Size = UDim2.new(1,-70,0,18)
sub.Text = "Read-only • enemy progress + match fields + Workspace.Map structure"
sub.Font = Enum.Font.Gotham
sub.TextSize = 10
sub.TextColor3 = Color3.fromRGB(154,168,195)
sub.TextXAlignment = Enum.TextXAlignment.Left
sub.Parent = main

local close = Instance.new("TextButton")
close.Position = UDim2.new(1,-50,0,12)
close.Size = UDim2.fromOffset(36,32)
close.Text = "×"
close.Font = Enum.Font.GothamBold
close.TextSize = 18
close.TextColor3 = Color3.new(1,1,1)
close.BackgroundColor3 = Color3.fromRGB(44,51,70)
close.BorderSizePixel = 0
close.Parent = main
Instance.new("UICorner", close).CornerRadius = UDim.new(0,9)

local status = Instance.new("TextLabel")
status.Position = UDim2.fromOffset(18,68)
status.Size = UDim2.new(1,-36,0,54)
status.BackgroundColor3 = Color3.fromRGB(23,28,39)
status.BorderSizePixel = 0
status.Text = "READY — take a Workspace snapshot, then capture during active waves."
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextWrapped = true
status.TextColor3 = Color3.fromRGB(205,213,230)
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = main
Instance.new("UICorner", status).CornerRadius = UDim.new(0,10)
local sp = Instance.new("UIPadding", status); sp.PaddingLeft=UDim.new(0,12); sp.PaddingRight=UDim.new(0,12)

local output = Instance.new("TextLabel")
output.Position = UDim2.fromOffset(18,134)
output.Size = UDim2.new(1,-36,1,-214)
output.BackgroundColor3 = Color3.fromRGB(18,22,31)
output.BorderSizePixel = 0
output.Text = "No data yet."
output.Font = Enum.Font.Code
output.TextSize = 11
output.TextColor3 = Color3.fromRGB(223,228,238)
output.TextXAlignment = Enum.TextXAlignment.Left
output.TextYAlignment = Enum.TextYAlignment.Top
output.TextWrapped = false
output.Parent = main
Instance.new("UICorner", output).CornerRadius = UDim.new(0,10)
local op = Instance.new("UIPadding", output); op.PaddingLeft=UDim.new(0,12);op.PaddingTop=UDim.new(0,10)

local function setStatus(text) status.Text=tostring(text) end

local snapshotBtn, captureBtn, saveBtn
local function button(text,x,w,cb)
    local b=Instance.new("TextButton")
    b.Position=UDim2.new(x,8,1,-62)
    b.Size=UDim2.new(w,-12,0,42)
    b.Text=text
    b.Font=Enum.Font.GothamBold
    b.TextSize=11
    b.TextColor3=Color3.new(1,1,1)
    b.BackgroundColor3=Color3.fromRGB(68,84,139)
    b.BorderSizePixel=0
    b.Parent=main
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,10)
    Probe.Connections[#Probe.Connections+1]=b.MouseButton1Click:Connect(cb)
    return b
end

local interestingField = {
    waypointindex=true,pathprogress=true,currentwaypoint=true,waypoint=true,
    cframe=true,position=true,speed=true,movespeed=true,maxspeed=true,
    health=true,maxhealth=true,shield=true,shieldhealth=true,
    asset=true,enemy=true,enemydata=true,unitdata=true,
    wave=true,waveincome=true,enemycount=true,gametime=true,sessiontime=true,intermission=true,
    map=true,mapname=true,act=true,actname=true,difficulty=true,gamemode=true,mode=true,
    modifiers=true,gamemodifiers=true,modifierdata=true,stage=true,stagedata=true,
    yen=true,totalunitsplaced=true,placementcounts=true,targetpriority=true,
}

local function ensureReplica(id)
    id=tostring(id or "")
    Probe.Replicas[id]=Probe.Replicas[id] or {Count=0,Fields={},Paths={},Type=nil,Parent=nil}
    return Probe.Replicas[id]
end

local function extractCreateType(...)
    local args=table.pack(...)
    local typeName,parentId=nil,nil
    local function inspect(v)
        if type(v)~="table" then return end
        for k,x in pairs(v) do
            local nk=norm(k)
            if (nk=="token" or nk=="class" or nk=="type" or nk=="replicatype") and type(x)=="string" then typeName=typeName or x end
            if (nk=="parent" or nk=="parentid" or nk=="parentreplica") and (type(x)=="number" or type(x)=="string") then parentId=parentId or tostring(x) end
        end
    end
    for i=1,args.n do inspect(args[i]) end
    return typeName,parentId
end

local function record(remote,...)
    local args=table.pack(...)
    local name=norm(remote.Name)
    local id=tostring(args[1] or "")
    local replica=ensureReplica(id)
    replica.Count+=1

    if name=="replicacreate" then
        local typeName,parentId=extractCreateType(...)
        if typeName then replica.Type=typeName end
        if parentId then replica.Parent=parentId end
        if #Probe.Events<800 then
            Probe.Events[#Probe.Events+1]={Remote=remote.Name,ReplicaId=mask(id),Type=typeName,Parent=parentId,Argc=args.n,Preview=preview(args[2])}
        end
        return
    end

    local path=pathText(args[2])
    local first=""
    if type(args[2])=="table" and args[2][1]~=nil then first=tostring(args[2][1]) end
    local key=norm(first)

    if name=="replicaset" then
        if interestingField[key] or key:find("waypoint",1,true) or key:find("path",1,true) or key:find("modifier",1,true) then
            replica.Fields[first]=args[3]
            replica.Paths[#replica.Paths+1]={Path=path,Value=preview(args[3])}
            if #Probe.Events<800 then Probe.Events[#Probe.Events+1]={Remote=remote.Name,ReplicaId=mask(id),Path=path,Value=preview(args[3])} end
        end
    elseif name=="replicasetvalues" then
        local values=args[3]
        if type(values)=="table" then
            local hit={}
            for k,v in pairs(values) do
                local nk=norm(k)
                if interestingField[nk] or nk:find("waypoint",1,true) or nk:find("path",1,true) or nk:find("modifier",1,true) then
                    replica.Fields[tostring(k)]=v
                    hit[tostring(k)]=preview(v)
                end
            end
            if countKeys(hit)>0 and #Probe.Events<800 then Probe.Events[#Probe.Events+1]={Remote=remote.Name,ReplicaId=mask(id),Path=path,Values=hit} end
        end
    end
end

local function summarize()
    local enemyLike,matchLike,gameUnitLike=0,0,0
    local examples={}
    for id,r in pairs(Probe.Replicas) do
        local typ=norm(r.Type)
        local hasProgress=r.Fields.WaypointIndex~=nil or r.Fields.PathProgress~=nil or r.Fields.CurrentWaypoint~=nil
        local hasStage=r.Fields.Wave~=nil or r.Fields.MapName~=nil or r.Fields.Gamemode~=nil or r.Fields.Difficulty~=nil or r.Fields.GameModifiers~=nil
        if typ:find("spawnedenemy",1,true) or typ:find("enemy",1,true) or hasProgress then enemyLike+=1 end
        if hasStage then matchLike+=1 end
        if typ:find("gameunit",1,true) then gameUnitLike+=1 end
        if (#examples<8) and (hasProgress or hasStage or typ:find("enemy",1,true)) then
            examples[#examples+1]=string.format("%s type=%s WP=%s progress=%s wave=%s map=%s",
                mask(id), tostring(r.Type or "?"), tostring(r.Fields.WaypointIndex or r.Fields.CurrentWaypoint or "?"), tostring(r.Fields.PathProgress or "?"), tostring(r.Fields.Wave or "?"), tostring(r.Fields.MapName or r.Fields.Map or "?"))
        end
    end
    local lines={
        "PATH + CONTEXT PROBE "..VERSION,
        "Workspace path candidates: "..tostring(#Probe.WorkspaceCandidates),
        "Replica events saved: "..tostring(#Probe.Events),
        "Enemy-like replicas: "..tostring(enemyLike),
        "Match/context replicas: "..tostring(matchLike),
        "GameUnit replicas: "..tostring(gameUnitLike),
        "",
        "Examples:"
    }
    for _,line in ipairs(examples) do lines[#lines+1]="  "..line end
    if #examples==0 then lines[#lines+1]="  none yet — capture during an active wave" end
    lines[#lines+1]=""
    lines[#lines+1]="Workspace candidates:"
    for i=1,math.min(8,#Probe.WorkspaceCandidates) do
        local c=Probe.WorkspaceCandidates[i]
        lines[#lines+1]=string.format("  %s | positional=%d | ordered=%d | children=%d",c.Path,c.PositionalCount,c.OrderedCount,c.DescendantCount)
    end
    output.Text=table.concat(lines,"\n")
end

function Probe:SnapshotWorkspace()
    self.WorkspaceCandidates={}
    local map=Workspace:FindFirstChild("Map")
    if not map then setStatus("Workspace.Map not found.");summarize();return end
    setStatus("Inspecting Workspace.Map path-like containers…")
    local seen={}
    local inspected=0
    for _,obj in ipairs(map:GetDescendants()) do
        inspected+=1
        if inspected>6000 then break end
        local n=norm(obj.Name)
        if n:find("path",1,true) or n:find("waypoint",1,true) or n:find("route",1,true) or n:find("node",1,true) or n:find("spawn",1,true) or n:find("base",1,true) then
            local parent=obj
            if not seen[parent] then
                seen[parent]=true
                local positional,ordered,samples=0,0,{}
                local descendants=parent:GetDescendants()
                for i,d in ipairs(descendants) do
                    if i>1200 then break end
                    local p=positionOf(d)
                    if p then
                        positional+=1
                        local order=tonumber(d.Name) or tonumber(d.Name:match("%d+"))
                        if order then ordered+=1 end
                        if #samples<10 then samples[#samples+1]={Name=d.Name,Class=d.ClassName,Order=order,Position={x=p.X,y=p.Y,z=p.Z}} end
                    end
                end
                if positional>0 then
                    self.WorkspaceCandidates[#self.WorkspaceCandidates+1]={Path=parent:GetFullName(),Name=parent.Name,Class=parent.ClassName,DescendantCount=#descendants,PositionalCount=positional,OrderedCount=ordered,Samples=samples}
                end
            end
        end
    end
    table.sort(self.WorkspaceCandidates,function(a,b)
        if a.OrderedCount~=b.OrderedCount then return a.OrderedCount>b.OrderedCount end
        return a.PositionalCount>b.PositionalCount
    end)
    summarize()
    setStatus("Workspace snapshot complete. Now capture 30s during active waves.")
end

function Probe:Capture(seconds)
    if self.CaptureActive then return end
    seconds=tonumber(seconds) or 30
    self.CaptureActive=true
    self.Events={}
    self.Replicas={}
    for _,c in ipairs(self.CaptureConnections) do pcall(function()c:Disconnect()end) end
    self.CaptureConnections={}

    local roots={RS:FindFirstChild("RemoteEvents"),RS:FindFirstChild("Nodes")}
    for _,root in ipairs(roots) do
        if root then
            for _,r in ipairs(root:GetDescendants()) do
                if r:IsA("RemoteEvent") then
                    local n=norm(r.Name)
                    if n=="replicaset" or n=="replicasetvalues" or n=="replicacreate" or n=="replicawrite" then
                        self.CaptureConnections[#self.CaptureConnections+1]=r.OnClientEvent:Connect(function(...)
                            local packed=table.pack(...)
                            task.defer(function() record(r,table.unpack(packed,1,packed.n)) end)
                        end)
                    end
                end
            end
        end
    end
    captureBtn.Text="CAPTURING…"
    setStatus("Capture active for "..seconds.."s. Let enemies move through at least 1 full wave; open Stage Info / Modifiers once if available.")
    task.delay(seconds,function()
        if self.Destroyed then return end
        for _,c in ipairs(self.CaptureConnections) do pcall(function()c:Disconnect()end) end
        self.CaptureConnections={}
        self.CaptureActive=false
        captureBtn.Text="CAPTURE 30s"
        summarize()
        setStatus("Capture complete. SAVE REPORT and send path_context_probe_v1_latest.json.")
    end)
end

function Probe:Save()
    if type(writefile)~="function" then setStatus("writefile unavailable") return end
    if type(makefolder)=="function" then pcall(makefolder,"AE_Tournament_Autopilot") end
    local replicas={}
    for id,r in pairs(self.Replicas) do
        replicas[mask(id)]={Type=r.Type,Parent=r.Parent,Count=r.Count,Fields=safe(r.Fields),Paths=safe(r.Paths)}
    end
    local report={Version=VERSION,PlaceId=game.PlaceId,Time=os.time(),WorkspaceCandidates=safe(self.WorkspaceCandidates),Replicas=replicas,Events=safe(self.Events)}
    local ok,json=pcall(function()return HttpService:JSONEncode(report)end)
    if not ok then setStatus("JSON encode failed: "..tostring(json)) return end
    local path="AE_Tournament_Autopilot/path_context_probe_v1_latest.json"
    local wrote,err=pcall(writefile,path,json)
    setStatus(wrote and ("Saved "..path) or ("Save failed: "..tostring(err)))
end

snapshotBtn=button("SNAPSHOT MAP",0,.33,function()Probe:SnapshotWorkspace()end)
captureBtn=button("CAPTURE 30s",.33,.34,function()Probe:Capture(30)end)
saveBtn=button("SAVE REPORT",.67,.33,function()Probe:Save()end)
Probe.Connections[#Probe.Connections+1]=close.MouseButton1Click:Connect(function()Probe:Destroy()end)

function Probe:Destroy()
    if self.Destroyed then return end
    self.Destroyed=true
    for _,c in ipairs(self.Connections) do pcall(function()c:Disconnect()end) end
    for _,c in ipairs(self.CaptureConnections) do pcall(function()c:Disconnect()end) end
    if gui then gui:Destroy() end
    if ENV.AE_PATH_CONTEXT_PROBE==self then ENV.AE_PATH_CONTEXT_PROBE=nil end
end

print("[AE Path Context Probe] READY",VERSION)
