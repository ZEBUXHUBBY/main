--[[
AE Tournament Autopilot | Profile Probe V3
Event-first, bounded, read-only diagnostic.
NO full getgc function-upvalue crawl.
NO FireServer / InvokeServer / placement / upgrade / sell / targeting actions.
]]

local VERSION = "profile-probe-v3.0"
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HS = game:GetService("HttpService")
local LP = Players.LocalPlayer
local ENV = getgenv and getgenv() or _G

if type(ENV.AE_TOURNAMENT_PROFILE_PROBE_V3)=="table" and type(ENV.AE_TOURNAMENT_PROFILE_PROBE_V3.Destroy)=="function" then
    pcall(function() ENV.AE_TOURNAMENT_PROFILE_PROBE_V3:Destroy() end)
end

local Probe={Version=VERSION,Connections={},CaptureConnections={},Destroyed=false,Busy=false,Observed={},ObservedOrder={},Hotbar={},Report=nil,Profile=nil}
ENV.AE_TOURNAMENT_PROFILE_PROBE_V3=Probe

local function norm(v) return tostring(v or ""):lower():gsub("[^%w]","") end
local function ci(t,names)
    if type(t)~="table" then return nil,nil end
    local w={} for _,n in ipairs(names or {}) do w[norm(n)]=true end
    for k,v in pairs(t) do if w[norm(k)] then return v,k end end
    return nil,nil
end
local function countKeys(t,limit)
    local n=0 if type(t)=="table" then for _ in pairs(t) do n+=1 if limit and n>=limit then break end end end return n
end
local function fullName(x)
    if typeof(x)~="Instance" then return tostring(x) end
    local ok,v=pcall(function() return x:GetFullName() end)
    return ok and v or (x.ClassName..":"..x.Name)
end
local function mask(v)
    local s=tostring(v or "")
    local a,b=s:match("^([^#]+)#(.+)$")
    if a and b and #b>10 then return a.."#"..b:sub(1,4).."…"..b:sub(-4) end
    if #s>30 then return s:sub(1,12).."…"..s:sub(-6) end
    return s
end
local function preview(v)
    local k=typeof(v)
    if k=="string" or k=="number" or k=="boolean" then return tostring(v):sub(1,120) end
    if k=="Instance" then return fullName(v) end
    if k=="table" then
        local pieces={} local n=0
        for key,val in pairs(v) do n+=1 if n>10 then pieces[#pieces+1]="…" break end
            pieces[#pieces+1]=tostring(key).."="..typeof(val)
        end
        return "{"..table.concat(pieces,",").."}"
    end
    return k
end
local function recordEvidence(r)
    if type(r)~="table" then return false,nil,0 end
    local asset=ci(r,{"Asset","Unit","UnitName"})
    if type(asset)~="string" or asset=="" then return false,nil,0 end
    local strong=0
    for _,f in ipairs({"Level","EXP","ObtainedAt","OriginalOwner","OwnerId","StatPotential","Trait","Equipment","Worthiness","TraitPity","TraitRollAmount","StatRollAmount","TotalTakedowns"}) do
        if ci(r,{f})~=nil then strong+=1 end
    end
    local identity=ci(r,{"ObtainedAt","OriginalOwner","OwnerId","StatPotential"})~=nil
    return strong>=2 and identity,asset,strong
end
local function recordId(r,keyHint)
    return tostring(ci(r,{"ID","Id","UUID","Guid"}) or keyHint or (tostring(ci(r,{"Asset"}) or "Unit").."#"..tostring(#Probe.ObservedOrder+1)))
end
local function registerRecord(r,keyHint,source,trusted)
    local ok,asset,strong=recordEvidence(r) if not ok then return nil end
    local id=recordId(r,keyHint)
    local dedupe=tostring(asset).."|"..tostring(ci(r,{"ObtainedAt"}) or id).."|"..tostring(ci(r,{"OriginalOwner","OwnerId"}) or "")
    local row=Probe.Observed[dedupe]
    if not row then
        row={ID=id,Asset=asset,Data=r,Source=source,Strong=strong,Trusted=trusted==true}
        Probe.Observed[dedupe]=row Probe.ObservedOrder[#Probe.ObservedOrder+1]=row
    elseif trusted then row.Trusted=true row.Source=source end
    return row
end
local function collectRecords(root,source,trusted,maxDepth,budget)
    if type(root)~="table" then return {} end
    local out,seen,found={}, {}, {}
    local left=budget or 1000
    local function walk(v,path,depth,keyHint)
        if left<=0 or depth>(maxDepth or 4) or type(v)~="table" or seen[v] then return end
        left-=1 seen[v]=true
        local candidate=(type(v.Data)=="table" and recordEvidence(v.Data)) and v.Data or v
        local row=registerRecord(candidate,keyHint,source..path,trusted)
        if row and not found[row] then found[row]=true out[#out+1]=row end
        local n=0
        for k,c in pairs(v) do n+=1 if n>180 then break end
            if type(c)=="table" then walk(c,path.."."..tostring(k),depth+1,tostring(k)) end
        end
    end
    walk(root,"",0,nil)
    return out
end
local function parseHotbar(raw)
    if type(raw)~="table" then return end
    local slots=ci(raw,{"Slots"}) if type(slots)~="table" then slots=raw end
    for k,v in pairs(slots) do
        local id
        if type(v)=="string" or type(v)=="number" then id=tostring(v)
        elseif type(v)=="table" then id=ci(v,{"ID","Id","UnitID","UnitId","UUID","Guid"}) if id then id=tostring(id) end end
        if id then
            local slot=tonumber(ci(type(v)=="table" and v or {},{"HotbarSlot","Slot"})) or tonumber(k) or 999
            Probe.Hotbar[slot]=id
        end
    end
end
local function inspectProfile(t,source)
    if type(t)~="table" then return nil end
    local data=type(rawget(t,"Data"))=="table" and rawget(t,"Data") or t
    local unitData=ci(data,{"UnitData"})
    if type(unitData)~="table" then return nil end
    local records={}
    for key,val in pairs(unitData) do
        local rec=type(val)=="table" and type(val.UnitData)=="table" and val.UnitData or val
        local row=registerRecord(rec,tostring(key),source..".UnitData",true)
        if row then records[#records+1]=row end
    end
    if #records==0 then return nil end
    parseHotbar(ci(data,{"HotbarData"}))
    Probe.Profile=data
    return data
end

-- UI
local pg=LP:WaitForChild("PlayerGui")
local old=pg:FindFirstChild("AE_ProfileProbe_V3") if old then old:Destroy() end
local gui=Instance.new("ScreenGui") gui.Name="AE_ProfileProbe_V3" gui.ResetOnSpawn=false gui.DisplayOrder=100260 gui.Parent=pg
local main=Instance.new("Frame") main.Size=UDim2.fromOffset(760,520) main.Position=UDim2.new(.5,-380,.5,-260) main.BackgroundColor3=Color3.fromRGB(14,17,24) main.BorderSizePixel=0 main.Parent=gui Instance.new("UICorner",main).CornerRadius=UDim.new(0,14)
local title=Instance.new("TextLabel") title.BackgroundTransparency=1 title.Position=UDim2.fromOffset(18,10) title.Size=UDim2.new(1,-70,0,30) title.Text="PROFILE + INVENTORY PROBE V3" title.Font=Enum.Font.GothamBold title.TextSize=17 title.TextColor3=Color3.fromRGB(240,242,248) title.TextXAlignment=Enum.TextXAlignment.Left title.Parent=main
local subtitle=Instance.new("TextLabel") subtitle.BackgroundTransparency=1 subtitle.Position=UDim2.fromOffset(18,39) subtitle.Size=UDim2.new(1,-70,0,18) subtitle.Text="Event-first • bounded scan • no full function-upvalue crawl" subtitle.Font=Enum.Font.Gotham subtitle.TextSize=10 subtitle.TextColor3=Color3.fromRGB(158,171,198) subtitle.TextXAlignment=Enum.TextXAlignment.Left subtitle.Parent=main
local close=Instance.new("TextButton") close.Position=UDim2.new(1,-50,0,11) close.Size=UDim2.fromOffset(36,32) close.Text="×" close.Font=Enum.Font.GothamBold close.TextSize=18 close.TextColor3=Color3.new(1,1,1) close.BackgroundColor3=Color3.fromRGB(45,52,71) close.BorderSizePixel=0 close.Parent=main Instance.new("UICorner",close).CornerRadius=UDim.new(0,9)
local status=Instance.new("TextLabel") status.Position=UDim2.fromOffset(18,70) status.Size=UDim2.new(1,-36,0,56) status.BackgroundColor3=Color3.fromRGB(23,28,39) status.BorderSizePixel=0 status.Text="READY" status.Font=Enum.Font.Gotham status.TextSize=11 status.TextWrapped=true status.TextColor3=Color3.fromRGB(204,212,230) status.TextXAlignment=Enum.TextXAlignment.Left status.Parent=main Instance.new("UICorner",status).CornerRadius=UDim.new(0,10)
local pad=Instance.new("UIPadding") pad.PaddingLeft=UDim.new(0,12) pad.PaddingRight=UDim.new(0,12) pad.Parent=status
local output=Instance.new("TextLabel") output.Position=UDim2.fromOffset(18,140) output.Size=UDim2.new(1,-36,1,-220) output.BackgroundColor3=Color3.fromRGB(18,22,31) output.BorderSizePixel=0 output.Text="No report yet." output.Font=Enum.Font.Code output.TextSize=11 output.TextColor3=Color3.fromRGB(222,227,238) output.TextXAlignment=Enum.TextXAlignment.Left output.TextYAlignment=Enum.TextYAlignment.Top output.Parent=main Instance.new("UICorner",output).CornerRadius=UDim.new(0,10)
local opad=Instance.new("UIPadding") opad.PaddingLeft=UDim.new(0,12) opad.PaddingTop=UDim.new(0,10) opad.Parent=output
local function setStatus(t) status.Text=tostring(t) end
local function addButton(text,x,width,cb)
    local b=Instance.new("TextButton") b.Position=UDim2.new(x,9,1,-62) b.Size=UDim2.new(width,-13,0,42) b.Text=text b.Font=Enum.Font.GothamBold b.TextSize=10 b.TextColor3=Color3.new(1,1,1) b.BackgroundColor3=Color3.fromRGB(67,84,139) b.BorderSizePixel=0 b.Parent=main Instance.new("UICorner",b).CornerRadius=UDim.new(0,10)
    Probe.Connections[#Probe.Connections+1]=b.MouseButton1Click:Connect(cb) return b
end
local quickButton,captureButton,useButton,saveButton

local function render()
    local trusted=0 for _,r in ipairs(Probe.ObservedOrder) do if r.Trusted then trusted+=1 end end
    local hotbarCount=0 for _ in pairs(Probe.Hotbar) do hotbarCount+=1 end
    local r=Probe.Report or {}
    output.Text=table.concat({
        "PROFILE PROBE "..VERSION,
        "",
        "STATIC",
        "  GC objects checked: "..tostring(r.GCChecked or 0),
        "  Replica modules checked: "..tostring(r.ModulesChecked or 0),
        "  Exact profile: "..tostring(Probe.Profile~=nil),
        "",
        "EVENT CAPTURE",
        "  events: "..tostring(r.EventCount or 0),
        "  relevant paths: "..tostring(r.RelevantPaths or 0),
        "  observed owned records: "..tostring(#Probe.ObservedOrder),
        "  trusted owned records: "..tostring(trusted),
        "  hotbar slots reconstructed: "..tostring(hotbarCount),
        "",
        (Probe.Profile or #Probe.ObservedOrder>=2) and "READY: USE + OPEN BRAIN" or "NEXT: CAPTURE 15s, open Unit Manager, scroll, then change one hotbar slot once.",
        "",
        "No full function-upvalue scan is performed."
    },"\n")
end

function Probe:QuickScan()
    if self.Busy then return end self.Busy=true quickButton.Text="SCANNING…"
    self.Report=self.Report or {Version=VERSION,EventCount=0,RelevantPaths=0,Events={}}
    setStatus("Bounded direct scan (max ~12k GC objects, no function upvalues)…")
    local objects={}
    if type(getgc)=="function" then
        local ok,res=pcall(getgc,true) if ok and type(res)=="table" then objects=res end
    end
    local checked=0
    for i,obj in ipairs(objects) do
        if i>12000 then break end
        if type(obj)=="table" then
            inspectProfile(obj,"getgc.table")
            for _,f in ipairs({"Data","Profile","ProfileData","PlayerData"}) do inspectProfile(rawget(obj,f),"getgc.table."..f) end
        end
        checked=i
        if i%2500==0 then task.wait() end
    end
    self.Report.GCChecked=checked
    setStatus("Checking ReplicaClient-like modules only…")
    local modulesChecked=0
    for _,m in ipairs(RS:GetDescendants()) do
        if m:IsA("ModuleScript") then
            local n=norm(m.Name)
            if n=="replicaclient" or n=="replicacontroller" or n=="replicastore" then
                modulesChecked+=1
                local ok,export=pcall(require,m)
                if ok and type(export)=="table" then
                    inspectProfile(export,"module:"..fullName(m))
                    for k,v in pairs(export) do if type(v)=="table" then inspectProfile(v,"module:"..fullName(m).."."..tostring(k)) end end
                end
            end
        end
    end
    self.Report.ModulesChecked=modulesChecked
    self.Busy=false quickButton.Text="QUICK SCAN" render()
    setStatus((Probe.Profile or #Probe.ObservedOrder>=2) and "Usable inventory evidence found." or "Quick scan done. Use CAPTURE 15s next; no exhaustive scan will run.")
end

function Probe:Capture(seconds)
    if self.Busy then return end self.Busy=true seconds=tonumber(seconds) or 15
    for _,c in ipairs(self.CaptureConnections) do pcall(function() c:Disconnect() end) end self.CaptureConnections={}
    self.Report=self.Report or {Version=VERSION,GCChecked=0,ModulesChecked=0,EventCount=0,RelevantPaths=0,Events={}}
    self.Report.EventCount=0 self.Report.RelevantPaths=0 self.Report.Events={}
    local function handle(remote,...)
        local args=table.pack(...)
        self.Report.EventCount+=1
        local rn=norm(remote.Name)
        local event={Remote=fullName(remote),Argc=args.n,Types={},Path=nil,Value=nil}
        for i=1,math.min(args.n,6) do event.Types[i]=typeof(args[i]) end
        if rn=="replicaset" or rn=="replicasetvalues" or rn=="replicawrite" then
            event.Path=type(args[2])=="table" and table.concat(args[2],".") or tostring(args[2] or "")
            event.Value=preview(args[3])
            local p=norm(event.Path)
            if p:find("unit",1,true) or p:find("hotbar",1,true) or p:find("trait",1,true) or p:find("equipment",1,true) or p:find("statpotential",1,true) or p:find("level",1,true) then self.Report.RelevantPaths+=1 end
            -- Reconstruct hotbar when exact path + ID are exposed.
            if p:find("hotbar",1,true) and (type(args[3])=="string" or type(args[3])=="number") then
                local slot=tonumber(type(args[2])=="table" and args[2][#args[2]] or nil)
                if slot then Probe.Hotbar[slot]=tostring(args[3]) end
            end
        end
        if #self.Report.Events<120 then self.Report.Events[#self.Report.Events+1]=event end
        for i=1,math.min(args.n,6) do
            if type(args[i])=="table" then
                inspectProfile(args[i],"incoming:"..fullName(remote)..".arg"..i)
                local rows=collectRecords(args[i],"incoming:"..fullName(remote)..".arg"..i,true,(rn=="replicacreate" and 6 or 4),(rn=="replicacreate" and 2600 or 900))
                for _,row in ipairs(rows) do row.Trusted=true end
                parseHotbar(args[i])
            end
        end
    end
    for _,root in ipairs({RS:FindFirstChild("RemoteEvents"),RS:FindFirstChild("Nodes")}) do
        if root then
            for _,remote in ipairs(root:GetDescendants()) do
                if remote:IsA("RemoteEvent") then
                    local n=norm(remote.Name)
                    if n:find("replica",1,true) or n:find("updatenode",1,true) then
                        self.CaptureConnections[#self.CaptureConnections+1]=remote.OnClientEvent:Connect(function(...)
                            local packed=table.pack(...) task.defer(function() handle(remote,table.unpack(packed,1,packed.n)) end)
                        end)
                    end
                end
            end
        end
    end
    captureButton.Text="CAPTURING…" setStatus("Capture 15s: open Unit Manager, scroll once, change one hotbar slot once.")
    task.delay(seconds,function()
        if self.Destroyed then return end
        for _,c in ipairs(self.CaptureConnections) do pcall(function() c:Disconnect() end) end self.CaptureConnections={}
        self.Busy=false captureButton.Text="CAPTURE 15s" render()
        setStatus((Probe.Profile or #Probe.ObservedOrder>=2) and "Capture found usable inventory evidence. Press USE + OPEN BRAIN." or "Capture finished. Save report and send it if observed records are still 0.")
        self:Save()
    end)
end

function Probe:BuildProfile()
    if Probe.Profile then return Probe.Profile,"exact profile" end
    if #Probe.ObservedOrder<2 then return nil,nil end
    local unitData={}
    for i,row in ipairs(Probe.ObservedOrder) do
        local id=row.ID if unitData[id]~=nil then id=id.."-"..i end unitData[id]=row.Data
    end
    local hotbar={}
    for slot,id in pairs(Probe.Hotbar) do hotbar[tostring(slot)]=id end
    return {UnitData=unitData,HotbarData=hotbar},"captured inventory evidence"
end
function Probe:UseAndOpen()
    local profile,source=self:BuildProfile()
    if type(profile)~="table" then setStatus("No usable inventory yet. Run CAPTURE 15s first.") return end
    ENV.AE_TOURNAMENT_PROFILE_OVERRIDE=profile ENV.AE_TOURNAMENT_PROFILE_OVERRIDE_SOURCE=source
    setStatus("Installed "..source..". Loading Tournament Brain…")
    local ok,src=pcall(function() return game:HttpGet("https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Tournament_Autopilot/start.lua?v3="..tostring(os.time())) end)
    if not ok then setStatus("Brain fetch failed: "..tostring(src)) return end
    local fn,ce=loadstring(src) if not fn then setStatus("Brain compile failed: "..tostring(ce)) return end
    local ran,re=pcall(fn) if not ran then setStatus("Brain runtime failed: "..tostring(re)) return end
    setStatus("Brain loaded. Press SCAN there.")
end
function Probe:Save()
    if type(writefile)~="function" then return false,"writefile unavailable" end
    if type(makefolder)=="function" then pcall(makefolder,"AE_Tournament_Autopilot") end
    local report={Version=VERSION,PlaceId=game.PlaceId,GCChecked=self.Report and self.Report.GCChecked or 0,ModulesChecked=self.Report and self.Report.ModulesChecked or 0,EventCount=self.Report and self.Report.EventCount or 0,RelevantPaths=self.Report and self.Report.RelevantPaths or 0,ObservedCount=#Probe.ObservedOrder,HotbarCount=countKeys(Probe.Hotbar,100),Events=self.Report and self.Report.Events or {}}
    local ok,encoded=pcall(function() return HS:JSONEncode(report) end) if not ok then return false,encoded end
    local path="AE_Tournament_Autopilot/profile_probe_v3_latest.json" local wrote,err=pcall(writefile,path,encoded) return wrote,wrote and path or err
end
function Probe:Destroy()
    if self.Destroyed then return end self.Destroyed=true
    for _,c in ipairs(self.Connections) do pcall(function() c:Disconnect() end) end
    for _,c in ipairs(self.CaptureConnections) do pcall(function() c:Disconnect() end) end
    if gui then gui:Destroy() end if ENV.AE_TOURNAMENT_PROFILE_PROBE_V3==self then ENV.AE_TOURNAMENT_PROFILE_PROBE_V3=nil end
end

quickButton=addButton("QUICK SCAN",0,.25,function() task.spawn(function() Probe:QuickScan() end) end)
captureButton=addButton("CAPTURE 15s",.25,.25,function() Probe:Capture(15) end)
useButton=addButton("USE + OPEN BRAIN",.50,.25,function() Probe:UseAndOpen() end)
saveButton=addButton("SAVE REPORT",.75,.25,function() local ok,res=Probe:Save() setStatus(ok and ("Saved "..tostring(res)) or ("Save failed: "..tostring(res))) end)
Probe.Connections[#Probe.Connections+1]=close.MouseButton1Click:Connect(function() Probe:Destroy() end)
render()
print("[AE Profile Probe V3] READY")
