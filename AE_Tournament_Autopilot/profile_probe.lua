--[[
AE Tournament Autopilot | Exact Profile Probe Mini
Read-only diagnostic. It never fires gameplay remotes.
]]

local VERSION = "profile-probe-mini-1.0"
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HS = game:GetService("HttpService")
local LP = Players.LocalPlayer
local ENV = getgenv and getgenv() or _G

if type(ENV.AE_TOURNAMENT_PROFILE_PROBE) == "table" and type(ENV.AE_TOURNAMENT_PROFILE_PROBE.Destroy) == "function" then
    pcall(function() ENV.AE_TOURNAMENT_PROFILE_PROBE:Destroy() end)
end

local Probe = {
    Version = VERSION,
    Connections = {},
    CaptureConnections = {},
    BestProfile = nil,
    Report = nil,
    Destroyed = false,
}
ENV.AE_TOURNAMENT_PROFILE_PROBE = Probe

local function norm(v)
    return tostring(v or ""):lower():gsub("[^%w]", "")
end

local function ci(t, names)
    if type(t) ~= "table" then return nil, nil end
    local wanted = {}
    for _, n in ipairs(names or {}) do wanted[norm(n)] = true end
    for k, v in pairs(t) do
        if wanted[norm(k)] then return v, k end
    end
    return nil, nil
end

local function countKeys(t, cap)
    local n = 0
    if type(t) == "table" then
        for _ in pairs(t) do
            n = n + 1
            if cap and n >= cap then break end
        end
    end
    return n
end

local function maskId(v)
    local s = tostring(v or "")
    local a, b = s:match("^([^#]+)#(.+)$")
    if a and b and #b > 10 then return a .. "#" .. b:sub(1,4) .. "…" .. b:sub(-4) end
    if #s > 24 then return s:sub(1,10) .. "…" .. s:sub(-5) end
    return s
end

local function safeName(x)
    if typeof(x) ~= "Instance" then return tostring(x) end
    local ok, name = pcall(function() return x:GetFullName() end)
    return ok and name or (x.ClassName .. ":" .. x.Name)
end

local function sanitize(v, seen, depth)
    seen = seen or {}
    depth = depth or 0
    if depth > 6 then return "<MAX_DEPTH>" end
    local kind = typeof(v)
    if kind == "nil" or kind == "boolean" or kind == "number" or kind == "string" then return v end
    if kind == "Instance" then return {__type="Instance", class=v.ClassName, path=safeName(v)} end
    if kind == "Vector3" then return {__type="Vector3", x=v.X, y=v.Y, z=v.Z} end
    if kind == "CFrame" then return {__type="CFrame", components={v:GetComponents()}} end
    if kind == "function" then return "<FUNCTION>" end
    if type(v) ~= "table" then return tostring(v) end
    if seen[v] then return "<CYCLE>" end
    seen[v] = true
    local out = {}
    local n = 0
    for k, child in pairs(v) do
        n = n + 1
        if n > 350 then out["<TRUNCATED>"] = true break end
        out[tostring(k)] = sanitize(child, seen, depth + 1)
    end
    seen[v] = nil
    return out
end

local function recordEvidence(rec)
    if type(rec) ~= "table" then return false, nil, 0 end
    local asset = ci(rec, {"Asset", "Unit", "UnitName"})
    if type(asset) ~= "string" then return false, nil, 0 end
    local fields = {
        "ObtainedAt", "OriginalOwner", "OwnerId", "EXP", "StatPotential",
        "Worthiness", "TraitPity", "TraitRollAmount", "StatRollAmount",
        "TotalTakedowns", "Equipment"
    }
    local strong = 0
    for _, name in ipairs(fields) do
        if ci(rec, {name}) ~= nil then strong = strong + 1 end
    end
    local identity = ci(rec, {"ObtainedAt", "OriginalOwner", "OwnerId", "StatPotential"}) ~= nil
    return strong >= 2 and identity, asset, strong
end

local function parseHotbar(raw)
    local out = {}
    if type(raw) ~= "table" then return out end
    local slots = ci(raw, {"Slots"})
    if type(slots) ~= "table" then slots = raw end
    for key, value in pairs(slots) do
        local id = nil
        if type(value) == "string" or type(value) == "number" then
            id = tostring(value)
        elseif type(value) == "table" then
            local assetType = ci(value, {"AssetType", "Type"})
            local candidate = ci(value, {"ID", "Id", "UnitID", "UnitId", "UUID", "Guid"})
            if candidate ~= nil and (assetType == nil or norm(assetType) == "unit") then
                id = tostring(candidate)
            end
        end
        if id then
            local slot = tonumber(ci(type(value) == "table" and value or {}, {"HotbarSlot", "Slot"})) or tonumber(key) or 999
            out[#out + 1] = {Slot=slot, ID=id, Masked=maskId(id)}
        end
    end
    table.sort(out, function(a, b) return a.Slot < b.Slot end)
    return out
end

local function getUpvalues(fn)
    if debug and type(debug.getupvalues) == "function" then
        local ok, result = pcall(debug.getupvalues, fn)
        if ok and type(result) == "table" then return result end
    end
    if type(getupvalues) == "function" then
        local ok, result = pcall(getupvalues, fn)
        if ok and type(result) == "table" then return result end
    end
    if debug and type(debug.getupvalue) == "function" then
        local out = {}
        for i = 1, 80 do
            local ok, name, value = pcall(debug.getupvalue, fn, i)
            if not ok or name == nil then break end
            out[name or tostring(i)] = value
        end
        return out
    end
    return nil
end

local pg = LP:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("AE_ProfileProbe_Mini")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "AE_ProfileProbe_Mini"
gui.ResetOnSpawn = false
gui.DisplayOrder = 100200
gui.Parent = pg

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(720, 510)
main.Position = UDim2.new(.5, -360, .5, -255)
main.BackgroundColor3 = Color3.fromRGB(14,17,24)
main.BorderSizePixel = 0
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0,14)
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(94,113,170)
stroke.Transparency = .32
stroke.Parent = main

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(18,10)
title.Size = UDim2.new(1,-72,0,28)
title.Text = "EXACT PROFILE PROBE"
title.Font = Enum.Font.GothamBold
title.TextSize = 17
title.TextColor3 = Color3.fromRGB(240,242,248)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = main

local sub = Instance.new("TextLabel")
sub.BackgroundTransparency = 1
sub.Position = UDim2.fromOffset(18,37)
sub.Size = UDim2.new(1,-72,0,18)
sub.Text = "Read-only • direct GC + upvalue evidence • no gameplay remotes fired"
sub.Font = Enum.Font.Gotham
sub.TextSize = 10
sub.TextColor3 = Color3.fromRGB(158,170,197)
sub.TextXAlignment = Enum.TextXAlignment.Left
sub.Parent = main

local close = Instance.new("TextButton")
close.Position = UDim2.new(1,-50,0,12)
close.Size = UDim2.fromOffset(36,32)
close.Text = "×"
close.Font = Enum.Font.GothamBold
close.TextSize = 18
close.TextColor3 = Color3.new(1,1,1)
close.BackgroundColor3 = Color3.fromRGB(45,52,71)
close.BorderSizePixel = 0
close.Parent = main
Instance.new("UICorner", close).CornerRadius = UDim.new(0,9)

local status = Instance.new("TextLabel")
status.Position = UDim2.fromOffset(18,68)
status.Size = UDim2.new(1,-36,0,54)
status.BackgroundColor3 = Color3.fromRGB(23,28,39)
status.BorderSizePixel = 0
status.Text = "READY — press RUN PROBE."
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextWrapped = true
status.TextColor3 = Color3.fromRGB(203,211,229)
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = main
Instance.new("UICorner", status).CornerRadius = UDim.new(0,10)
local sp = Instance.new("UIPadding")
sp.PaddingLeft = UDim.new(0,12)
sp.PaddingRight = UDim.new(0,12)
sp.Parent = status

local summary = Instance.new("TextLabel")
summary.Position = UDim2.fromOffset(18,134)
summary.Size = UDim2.new(1,-36,1,-210)
summary.BackgroundColor3 = Color3.fromRGB(18,22,31)
summary.BorderSizePixel = 0
summary.Text = "No report yet."
summary.Font = Enum.Font.Code
summary.TextSize = 11
summary.TextColor3 = Color3.fromRGB(222,226,237)
summary.TextXAlignment = Enum.TextXAlignment.Left
summary.TextYAlignment = Enum.TextYAlignment.Top
summary.TextWrapped = false
summary.Parent = main
Instance.new("UICorner", summary).CornerRadius = UDim.new(0,10)
local sump = Instance.new("UIPadding")
sump.PaddingLeft = UDim.new(0,12)
sump.PaddingTop = UDim.new(0,10)
sump.Parent = summary

local function button(text, x, width, callback)
    local b = Instance.new("TextButton")
    b.Position = UDim2.new(x, 8, 1, -62)
    b.Size = UDim2.new(width, -12, 0, 42)
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.TextColor3 = Color3.new(1,1,1)
    b.BackgroundColor3 = Color3.fromRGB(67,84,139)
    b.BorderSizePixel = 0
    b.Parent = main
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,10)
    Probe.Connections[#Probe.Connections + 1] = b.MouseButton1Click:Connect(callback)
    return b
end

local runButton
local captureButton
local useButton
local saveButton

local function setStatus(text)
    status.Text = tostring(text)
end

local function reportText(r)
    local lines = {}
    lines[#lines+1] = "PROFILE PROBE " .. VERSION
    lines[#lines+1] = "PlaceId: " .. tostring(game.PlaceId)
    lines[#lines+1] = ""
    lines[#lines+1] = "CAPABILITIES"
    lines[#lines+1] = "  getgc: " .. tostring(r.Capabilities.GetGC)
    lines[#lines+1] = "  upvalues: " .. tostring(r.Capabilities.Upvalues)
    lines[#lines+1] = "  writefile: " .. tostring(r.Capabilities.WriteFile)
    lines[#lines+1] = ""
    lines[#lines+1] = "GC OBJECTS: " .. tostring(r.ObjectCount)
    lines[#lines+1] = "HOTBAR REPLICAS: " .. tostring(#r.HotbarReplicas)
    lines[#lines+1] = "DIRECT CANDIDATES: " .. tostring(r.DirectCandidates)
    lines[#lines+1] = "UPVALUE CANDIDATES: " .. tostring(r.UpvalueCandidates)
    lines[#lines+1] = "LOOSE UNITDATA: " .. tostring(#r.LooseUnitData)
    lines[#lines+1] = ""
    if r.Best then
        lines[#lines+1] = "PROFILE FOUND"
        lines[#lines+1] = "  source: " .. tostring(r.Best.Source)
        lines[#lines+1] = "  owned records: " .. tostring(r.Best.OwnedCount)
        lines[#lines+1] = "  hotbar match: " .. tostring(r.Best.HotbarMatches) .. "/" .. tostring(r.Best.HotbarCount)
        lines[#lines+1] = "  local-owner records: " .. tostring(r.Best.OwnerMatches)
        lines[#lines+1] = "  USE FOUND is now available."
    else
        lines[#lines+1] = "NO VALIDATED PROFILE"
        lines[#lines+1] = "  Press CAPTURE 12s, then open Unit Manager or change one hotbar slot once."
    end
    if r.Capture then
        lines[#lines+1] = ""
        lines[#lines+1] = "CAPTURE: " .. tostring(r.Capture.EventCount or 0) .. " events / " .. tostring(#(r.Capture.StructuralHits or {})) .. " structural hits"
    end
    lines[#lines+1] = ""
    lines[#lines+1] = "Report path: AE_Tournament_Autopilot/profile_probe_latest.json"
    return table.concat(lines, "\n")
end

local function collectObjects(report)
    local objects = {}
    local seen = {}
    report.Capabilities = {
        GetGC = type(getgc) == "function",
        Upvalues = (debug and (type(debug.getupvalues)=="function" or type(debug.getupvalue)=="function")) or type(getupvalues)=="function",
        WriteFile = type(writefile) == "function",
    }
    if type(getgc) ~= "function" then return objects end
    local function merge(...)
        local ok, result = pcall(getgc, ...)
        if ok and type(result) == "table" then
            for _, object in ipairs(result) do
                if not seen[object] then
                    seen[object] = true
                    objects[#objects+1] = object
                end
            end
        end
    end
    merge(true)
    merge()
    return objects
end

local function findReplicaHotbar(objects, report)
    local best = {}
    for _, object in ipairs(objects) do
        if type(object) == "table" and tostring(rawget(object, "Token") or "") == "HotbarData" then
            local data = rawget(object, "Data")
            local entries = parseHotbar(data)
            if #entries > 0 then
                report.HotbarReplicas[#report.HotbarReplicas+1] = {
                    Count = #entries,
                    Shape = countKeys(data,9999),
                }
                if #entries > #best then best = entries end
            end
        end
    end
    return best
end

local function scanProfile(objects, replicaHotbar, report)
    local seen = {}
    local candidates = {}
    local looseSeen = {}

    local function loose(container, source)
        if type(container) ~= "table" or looseSeen[container] then return end
        looseSeen[container] = true
        local ownedLike = 0
        local sample = {}
        local scanned = 0
        for key, value in pairs(container) do
            scanned = scanned + 1
            if scanned > 600 then break end
            local prefix, suffix = type(key)=="string" and key:match("^([^#]+)#([%w%-]+)$") or nil, nil
            if prefix then suffix = tostring(key):match("^.-#([%w%-]+)$") end
            local okRec, asset, strong = recordEvidence(value)
            if prefix and suffix and #suffix >= 8 and okRec then
                ownedLike = ownedLike + 1
                if #sample < 3 then sample[#sample+1] = {ID=maskId(key), Asset=asset, Strong=strong} end
            end
        end
        if ownedLike >= 2 and #report.LooseUnitData < 30 then
            report.LooseUnitData[#report.LooseUnitData+1] = {Source=source, Count=ownedLike, Sample=sample}
        end
    end

    local function inspect(profile, source, origin)
        if type(profile) ~= "table" or seen[profile] then return end
        seen[profile] = true
        local unitData = ci(profile, {"UnitData"})
        if type(unitData) ~= "table" then
            loose(profile, source)
            return
        end

        local profileHotbar = parseHotbar(ci(profile,{"HotbarData"}))
        local hotbar = #replicaHotbar > 0 and replicaHotbar or profileHotbar
        local byExact = {}
        local byNorm = {}
        local records = {}
        local ownerMatches = 0

        for key, value in pairs(unitData) do
            local prefix, suffix = type(key)=="string" and key:match("^([^#]+)#([%w%-]+)$") or nil, nil
            if prefix then suffix = tostring(key):match("^.-#([%w%-]+)$") end
            local okRec, asset, strong = recordEvidence(value)
            if prefix and suffix and #suffix >= 8 and okRec then
                local row = {ID=tostring(key), Asset=asset, Data=value, Strong=strong}
                records[#records+1] = row
                byExact[row.ID] = row
                byNorm[norm(row.ID)] = row
                local owner = tonumber(ci(value,{"OwnerId","OriginalOwner"}))
                if owner and owner == tonumber(LP.UserId) then ownerMatches = ownerMatches + 1 end
            end
        end
        loose(unitData, source .. ".UnitData")
        if #records == 0 then return end

        local matches = 0
        for _, item in ipairs(hotbar) do
            if byExact[item.ID] or byNorm[norm(item.ID)] then matches = matches + 1 end
        end
        local allMatched = #hotbar > 0 and matches == #hotbar
        local score = #records + ownerMatches*8 + matches*30 + (allMatched and 200 or 0) + (type(ci(profile,{"HotbarData"}))=="table" and 30 or 0)
        candidates[#candidates+1] = {
            Profile=profile,
            Source=source,
            Origin=origin,
            OwnedCount=#records,
            HotbarCount=#hotbar,
            HotbarMatches=matches,
            OwnerMatches=ownerMatches,
            AllMatched=allMatched,
            Score=score,
            Sample=records,
        }
        if origin == "direct" then report.DirectCandidates = report.DirectCandidates + 1 else report.UpvalueCandidates = report.UpvalueCandidates + 1 end
    end

    local function inspectChildren(object, source, origin)
        inspect(object, source, origin)
        if type(object) ~= "table" then return end
        for _, field in ipairs({"Data","Profile","ProfileData","PlayerData"}) do
            local child = rawget(object, field)
            if type(child) == "table" then
                inspect(child, source .. "." .. field, origin)
                local data = rawget(child,"Data")
                if type(data)=="table" then inspect(data, source .. "." .. field .. ".Data", origin) end
            end
        end
    end

    setStatus("Direct scan: checking GC tables…")
    for i, object in ipairs(objects) do
        if type(object)=="table" then inspectChildren(object,"getgc.table","direct") end
        if i % 4000 == 0 then setStatus("Direct scan "..i.."/"..#objects); task.wait() end
    end

    local strongDirect = false
    for _, c in ipairs(candidates) do
        if c.Origin=="direct" and (c.AllMatched or c.OwnerMatches>0) then strongDirect=true break end
    end

    if not strongDirect and report.Capabilities.Upvalues then
        setStatus("No strong direct profile; checking function upvalues…")
        local fnCount = 0
        for i, object in ipairs(objects) do
            if type(object)=="function" then
                fnCount = fnCount + 1
                local ups = getUpvalues(object)
                if type(ups)=="table" then
                    for name, value in pairs(ups) do
                        if type(value)=="table" then inspectChildren(value,"upvalue."..tostring(name),"upvalue") end
                    end
                end
                if fnCount % 500 == 0 then setStatus("Upvalues checked: "..fnCount); task.wait() end
            end
            if i % 8000 == 0 then task.wait() end
        end
    end

    table.sort(candidates,function(a,b)
        if a.AllMatched ~= b.AllMatched then return a.AllMatched end
        if a.HotbarMatches ~= b.HotbarMatches then return a.HotbarMatches > b.HotbarMatches end
        if a.OwnerMatches ~= b.OwnerMatches then return a.OwnerMatches > b.OwnerMatches end
        return a.Score > b.Score
    end)

    local best = candidates[1]
    if best and (best.AllMatched or best.OwnerMatches>0 or (best.HotbarCount>0 and best.HotbarMatches>0)) then
        Probe.BestProfile = best.Profile
        report.Best = {
            Source=best.Source,
            OwnedCount=best.OwnedCount,
            HotbarCount=best.HotbarCount,
            HotbarMatches=best.HotbarMatches,
            OwnerMatches=best.OwnerMatches,
            Score=best.Score,
            Sample={},
        }
        for i=1,math.min(5,#best.Sample) do
            local row=best.Sample[i]
            report.Best.Sample[#report.Best.Sample+1]={ID=maskId(row.ID),Asset=row.Asset,Strong=row.Strong}
        end
    end
end

function Probe:Run()
    if self.Destroyed then return end
    self.BestProfile = nil
    setStatus("Collecting GC objects…")
    local report = {
        Version=VERSION,
        PlaceId=game.PlaceId,
        Time=os.time(),
        Capabilities={},
        ObjectCount=0,
        HotbarReplicas={},
        DirectCandidates=0,
        UpvalueCandidates=0,
        LooseUnitData={},
        Best=nil,
        Capture=self.Report and self.Report.Capture or nil,
    }
    local objects = collectObjects(report)
    report.ObjectCount = #objects
    if #objects == 0 then
        self.Report = report
        summary.Text = reportText(report)
        setStatus("getgc unavailable or returned no objects.")
        return
    end
    setStatus("Finding HotbarData replicas…")
    local hotbar = findReplicaHotbar(objects,report)
    scanProfile(objects,hotbar,report)
    self.Report = report
    summary.Text = reportText(report)
    useButton.BackgroundColor3 = report.Best and Color3.fromRGB(52,145,96) or Color3.fromRGB(70,75,91)
    setStatus(report.Best and "Validated profile found. Press USE FOUND, then press SCAN in Tournament Brain." or "No exact profile accepted. Run CAPTURE 12s and interact with Unit Manager/hotbar once.")
end

local function structuralHit(v, source, out)
    if type(v) ~= "table" then return end
    local unitData = ci(v,{"UnitData"})
    local hotbarData = ci(v,{"HotbarData"})
    if type(unitData)=="table" or type(hotbarData)=="table" or tostring(rawget(v,"Token") or "")=="HotbarData" then
        if #out < 60 then
            out[#out+1]={Source=source,Token=tostring(rawget(v,"Token") or ""),HasUnitData=type(unitData)=="table",HasHotbarData=type(hotbarData)=="table",Shape=countKeys(v,9999)}
        end
    end
end

function Probe:Capture(seconds)
    if self.Destroyed then return end
    seconds = tonumber(seconds) or 12
    for _,c in ipairs(self.CaptureConnections) do pcall(function() c:Disconnect() end) end
    self.CaptureConnections = {}
    self.Report = self.Report or {Version=VERSION,PlaceId=game.PlaceId,Capabilities={},HotbarReplicas={},DirectCandidates=0,UpvalueCandidates=0,LooseUnitData={}}
    local capture={EventCount=0,StructuralHits={},Events={}}
    self.Report.Capture=capture

    local roots={RS:FindFirstChild("RemoteEvents"),RS:FindFirstChild("Nodes")}
    for _,root in ipairs(roots) do
        if root then
            for _,d in ipairs(root:GetDescendants()) do
                if d:IsA("RemoteEvent") then
                    local n=norm(d.Name)
                    if n:find("replica",1,true) or n:find("update",1,true) then
                        self.CaptureConnections[#self.CaptureConnections+1]=d.OnClientEvent:Connect(function(...)
                            capture.EventCount=capture.EventCount+1
                            local args=table.pack(...)
                            if #capture.Events<80 then capture.Events[#capture.Events+1]={Remote=safeName(d),Argc=args.n,Types={}} end
                            for i=1,math.min(args.n,5) do structuralHit(args[i],safeName(d)..".arg"..i,capture.StructuralHits) end
                        end)
                    end
                end
            end
        end
    end
    captureButton.Text="CAPTURING…"
    setStatus("Capturing incoming replica evidence for "..seconds.."s. Open Unit Manager or change one hotbar slot once.")
    task.delay(seconds,function()
        for _,c in ipairs(self.CaptureConnections) do pcall(function() c:Disconnect() end) end
        self.CaptureConnections={}
        captureButton.Text="CAPTURE 12s"
        summary.Text=reportText(self.Report)
        setStatus("Capture complete: "..capture.EventCount.." events, "..#capture.StructuralHits.." structural hits. Save the report.")
    end)
end

function Probe:UseFound()
    if not self.BestProfile then
        setStatus("No validated profile is available yet.")
        return
    end
    ENV.AE_TOURNAMENT_PROFILE_OVERRIDE=self.BestProfile
    setStatus("Profile override installed. Re-run the Autopilot loader or press SCAN if it was loaded after the override patch.")
end

function Probe:Save()
    if not self.Report then setStatus("Run the probe first.") return end
    if type(writefile)~="function" then setStatus("writefile unavailable in this executor.") return end
    if type(makefolder)=="function" then pcall(makefolder,"AE_Tournament_Autopilot") end
    local ok,encoded=pcall(function() return HS:JSONEncode(sanitize(self.Report)) end)
    if not ok then setStatus("JSON encode failed: "..tostring(encoded)) return end
    local path="AE_Tournament_Autopilot/profile_probe_latest.json"
    local wrote,err=pcall(writefile,path,encoded)
    setStatus(wrote and ("Saved "..path) or ("Save failed: "..tostring(err)))
end

runButton=button("RUN PROBE",0,.25,function() task.spawn(function() Probe:Run() end) end)
captureButton=button("CAPTURE 12s",.25,.25,function() Probe:Capture(12) end)
useButton=button("USE FOUND",.50,.25,function() Probe:UseFound() end)
saveButton=button("SAVE REPORT",.75,.25,function() Probe:Save() end)

Probe.Connections[#Probe.Connections+1]=close.MouseButton1Click:Connect(function() Probe:Destroy() end)

function Probe:Destroy()
    if self.Destroyed then return end
    self.Destroyed=true
    for _,c in ipairs(self.Connections) do pcall(function() c:Disconnect() end) end
    for _,c in ipairs(self.CaptureConnections) do pcall(function() c:Disconnect() end) end
    self.Connections={}
    self.CaptureConnections={}
    if gui then gui:Destroy() end
    if ENV.AE_TOURNAMENT_PROFILE_PROBE==self then ENV.AE_TOURNAMENT_PROFILE_PROBE=nil end
end

print("[AE Profile Probe] READY",VERSION)
