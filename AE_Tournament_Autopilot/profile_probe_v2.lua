--[[
AE Tournament Autopilot | Profile / Inventory Probe V2
Read-only diagnostic. No FireServer, InvokeServer, placement, upgrade, sell or target actions.
]]

local VERSION = "profile-probe-v2.0"
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HS = game:GetService("HttpService")
local LP = Players.LocalPlayer
local ENV = getgenv and getgenv() or _G

if type(ENV.AE_TOURNAMENT_PROFILE_PROBE_V2) == "table" and type(ENV.AE_TOURNAMENT_PROFILE_PROBE_V2.Destroy) == "function" then
    pcall(function() ENV.AE_TOURNAMENT_PROFILE_PROBE_V2:Destroy() end)
end

local Probe = {
    Version = VERSION,
    Connections = {},
    CaptureConnections = {},
    Destroyed = false,
    Busy = false,
    ExactProfile = nil,
    SyntheticProfile = nil,
    ObservedRecords = {},
    ObservedOrder = {},
    TrustedInventoryEvents = 0,
    Report = nil,
}
ENV.AE_TOURNAMENT_PROFILE_PROBE_V2 = Probe

local function norm(v)
    return tostring(v or ""):lower():gsub("[^%w]", "")
end

local function ci(t, names)
    if type(t) ~= "table" then return nil, nil end
    local wanted = {}
    for _, name in ipairs(names or {}) do wanted[norm(name)] = true end
    for key, value in pairs(t) do
        if wanted[norm(key)] then return value, key end
    end
    return nil, nil
end

local function countKeys(t, limit)
    local n = 0
    if type(t) == "table" then
        for _ in pairs(t) do
            n += 1
            if limit and n >= limit then break end
        end
    end
    return n
end

local function maskId(v)
    local s = tostring(v or "")
    local a, b = s:match("^([^#]+)#(.+)$")
    if a and b and #b > 10 then return a .. "#" .. b:sub(1, 4) .. "…" .. b:sub(-4) end
    if #s > 28 then return s:sub(1, 11) .. "…" .. s:sub(-6) end
    return s
end

local function fullName(instance)
    if typeof(instance) ~= "Instance" then return tostring(instance) end
    local ok, result = pcall(function() return instance:GetFullName() end)
    return ok and result or (instance.ClassName .. ":" .. instance.Name)
end

local function recordEvidence(record)
    if type(record) ~= "table" then return false, nil, 0 end
    local asset = ci(record, {"Asset", "Unit", "UnitName"})
    if type(asset) ~= "string" or asset == "" then return false, nil, 0 end
    local strong = 0
    for _, key in ipairs({
        "Level", "EXP", "ObtainedAt", "OriginalOwner", "OwnerId", "StatPotential",
        "Trait", "Worthiness", "TraitPity", "TraitRollAmount", "StatRollAmount",
        "TotalTakedowns", "Equipment", "Ascension"
    }) do
        if ci(record, {key}) ~= nil then strong += 1 end
    end
    local identity = ci(record, {"ObtainedAt", "OriginalOwner", "OwnerId", "StatPotential", "TraitPity"}) ~= nil
    return strong >= 3 and identity, asset, strong
end

local function recordId(record, keyHint, indexHint)
    local explicit = ci(record, {"ID", "Id", "UUID", "Guid", "UnitID", "UnitId"})
    if explicit ~= nil then return tostring(explicit) end
    if type(keyHint) == "string" and keyHint:find("#", 1, true) then return keyHint end
    local asset = tostring(ci(record, {"Asset", "Unit", "UnitName"}) or "Unit")
    local obtained = ci(record, {"ObtainedAt"})
    local owner = ci(record, {"OriginalOwner", "OwnerId"})
    if obtained ~= nil then return asset .. "#observed-" .. tostring(obtained) .. "-" .. tostring(owner or 0) end
    return asset .. "#observed-" .. tostring(indexHint or countKeys(Probe.ObservedRecords) + 1)
end

local function preview(value, depth)
    depth = depth or 0
    local kind = typeof(value)
    if kind == "nil" or kind == "boolean" or kind == "number" then return value end
    if kind == "string" then return maskId(value) end
    if kind == "Instance" then return {Type="Instance", Class=value.ClassName, Path=fullName(value)} end
    if kind ~= "table" then return tostring(value) end
    if depth >= 2 then return {Type="table", Keys=countKeys(value, 9999)} end
    local out = {Type="table", Keys=countKeys(value, 9999), Fields={}}
    local n = 0
    for key, child in pairs(value) do
        n += 1
        if n > 12 then break end
        local childKind = typeof(child)
        if childKind == "string" or childKind == "number" or childKind == "boolean" then
            out.Fields[tostring(key)] = preview(child, depth + 1)
        elseif childKind == "table" then
            out.Fields[tostring(key)] = {Type="table", Keys=countKeys(child, 9999)}
        else
            out.Fields[tostring(key)] = childKind
        end
    end
    return out
end

local function sanitize(value, seen, depth)
    seen = seen or {}
    depth = depth or 0
    if depth > 7 then return "<MAX_DEPTH>" end
    local kind = typeof(value)
    if kind == "nil" or kind == "boolean" or kind == "number" or kind == "string" then return value end
    if kind == "Instance" then return {__type="Instance", class=value.ClassName, path=fullName(value)} end
    if kind == "Vector3" then return {__type="Vector3", x=value.X, y=value.Y, z=value.Z} end
    if kind == "CFrame" then return {__type="CFrame", components={value:GetComponents()}} end
    if kind == "function" then return "<FUNCTION>" end
    if type(value) ~= "table" then return tostring(value) end
    if seen[value] then return "<CYCLE>" end
    seen[value] = true
    local out, n = {}, 0
    for key, child in pairs(value) do
        n += 1
        if n > 400 then out["<TRUNCATED>"] = true break end
        out[tostring(key)] = sanitize(child, seen, depth + 1)
    end
    seen[value] = nil
    return out
end

local function parseHotbar(raw)
    local result = {}
    if type(raw) ~= "table" then return result end
    local slots = ci(raw, {"Slots"})
    if type(slots) ~= "table" then slots = raw end
    for key, value in pairs(slots) do
        local id
        if type(value) == "string" or type(value) == "number" then
            id = tostring(value)
        elseif type(value) == "table" then
            local assetType = ci(value, {"AssetType", "Type"})
            local candidate = ci(value, {"ID", "Id", "UnitID", "UnitId", "UUID", "Guid"})
            if candidate ~= nil and (assetType == nil or norm(assetType) == "unit") then id = tostring(candidate) end
        end
        if id then
            result[#result + 1] = {
                Slot = tonumber(ci(type(value) == "table" and value or {}, {"HotbarSlot", "Slot"})) or tonumber(key) or 999,
                ID = id,
                Masked = maskId(id),
            }
        end
    end
    table.sort(result, function(a, b) return a.Slot < b.Slot end)
    return result
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
        local result = {}
        for index = 1, 100 do
            local ok, name, value = pcall(debug.getupvalue, fn, index)
            if not ok or name == nil then break end
            result[name or tostring(index)] = value
        end
        return result
    end
    return nil
end

local function registerObserved(record, keyHint, source, trusted)
    local valid, asset, strong = recordEvidence(record)
    if not valid then return nil end
    local id = recordId(record, keyHint)
    local dedupe = tostring(asset) .. "|" .. tostring(ci(record, {"ObtainedAt"}) or id) .. "|" .. tostring(ci(record, {"OriginalOwner", "OwnerId"}) or "")
    local existing = Probe.ObservedRecords[dedupe]
    if not existing then
        existing = {ID=id, Asset=asset, Data=record, Source=source, Strong=strong, Trusted=trusted == true}
        Probe.ObservedRecords[dedupe] = existing
        Probe.ObservedOrder[#Probe.ObservedOrder + 1] = existing
    elseif trusted then
        existing.Trusted = true
        existing.Source = source
    end
    return existing
end

local function collectRecords(root, source, trusted, maxDepth, budget)
    local found = {}
    local foundSet = {}
    local seen = {}
    maxDepth = maxDepth or 5
    local remaining = budget or 1800

    local function walk(value, path, depth, keyHint)
        if remaining <= 0 or depth > maxDepth or type(value) ~= "table" or seen[value] then return end
        remaining -= 1
        seen[value] = true

        local record = value
        if type(value.Data) == "table" and recordEvidence(value.Data) then record = value.Data end
        local registered = registerObserved(record, keyHint, source .. path, trusted)
        if registered and not foundSet[registered] then
            foundSet[registered] = true
            found[#found + 1] = registered
        end

        local scanned = 0
        for key, child in pairs(value) do
            scanned += 1
            if scanned > 250 then break end
            if type(child) == "table" then
                walk(child, path .. "." .. tostring(key), depth + 1, tostring(key))
            end
        end
    end

    walk(root, "", 0, nil)
    return found
end

local function inspectProfile(profile, source, report, origin)
    if type(profile) ~= "table" then return nil end
    local data = rawget(profile, "Data")
    if type(data) ~= "table" then data = profile end
    local unitData = ci(data, {"UnitData"})
    if type(unitData) ~= "table" then return nil end

    local records = {}
    local byExact, byNorm = {}, {}
    local ownerMatches = 0
    for key, value in pairs(unitData) do
        local record = type(value) == "table" and type(value.UnitData) == "table" and value.UnitData or value
        local valid, asset, strong = recordEvidence(record)
        if valid then
            local id = recordId(record, tostring(key))
            local row = {ID=id, Asset=asset, Data=record, Strong=strong}
            records[#records + 1] = row
            byExact[id] = row
            byNorm[norm(id)] = row
            local owner = tonumber(ci(record, {"OwnerId", "OriginalOwner"}))
            if owner and owner == tonumber(LP.UserId) then ownerMatches += 1 end
        end
    end
    if #records == 0 then return nil end

    local hotbar = parseHotbar(ci(data, {"HotbarData"}))
    local matches = 0
    for _, item in ipairs(hotbar) do
        if byExact[item.ID] or byNorm[norm(item.ID)] then matches += 1 end
    end
    local allMatched = #hotbar > 0 and matches == #hotbar
    local score = #records + ownerMatches * 8 + matches * 35 + (allMatched and 220 or 0)
    local candidate = {
        Profile=data,
        Source=source,
        Origin=origin,
        OwnedCount=#records,
        HotbarCount=#hotbar,
        HotbarMatches=matches,
        OwnerMatches=ownerMatches,
        AllMatched=allMatched,
        Score=score,
        Sample={},
    }
    for index = 1, math.min(5, #records) do
        candidate.Sample[#candidate.Sample + 1] = {
            ID=maskId(records[index].ID), Asset=records[index].Asset, Strong=records[index].Strong,
        }
    end
    report.ProfileCandidates[#report.ProfileCandidates + 1] = candidate
    return candidate
end

local function collectGC(report)
    local objects, seen = {}, {}
    local function merge(...)
        if type(getgc) ~= "function" then return end
        local ok, result = pcall(getgc, ...)
        if ok and type(result) == "table" then
            for _, object in ipairs(result) do
                if not seen[object] then seen[object] = true; objects[#objects + 1] = object end
            end
        end
    end
    merge(true)
    merge()
    report.ObjectCount = #objects
    return objects
end

local function scanModuleExports(report)
    local scanned = 0
    for _, module in ipairs(RS:GetDescendants()) do
        if module:IsA("ModuleScript") then
            local name = norm(module.Name)
            if name == "replicaclient" or name == "replicacontroller" or name == "replicastore" then
                scanned += 1
                local ok, export = pcall(require, module)
                if ok then
                    if type(export) == "table" then
                        inspectProfile(export, "module:" .. fullName(module), report, "module")
                        for key, value in pairs(export) do
                            if type(value) == "table" then inspectProfile(value, "module:" .. fullName(module) .. "." .. tostring(key), report, "module") end
                            if type(value) == "function" then
                                local ups = getUpvalues(value)
                                for upName, upValue in pairs(type(ups) == "table" and ups or {}) do
                                    if type(upValue) == "table" then inspectProfile(upValue, "module-upvalue:" .. tostring(upName), report, "module-upvalue") end
                                end
                            end
                        end
                    elseif type(export) == "function" then
                        local ups = getUpvalues(export)
                        for upName, upValue in pairs(type(ups) == "table" and ups or {}) do
                            if type(upValue) == "table" then inspectProfile(upValue, "module-function-upvalue:" .. tostring(upName), report, "module-upvalue") end
                        end
                    end
                end
            end
        end
    end
    report.ReplicaModulesScanned = scanned
end

-- UI --------------------------------------------------------------------------
local pg = LP:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("AE_ProfileProbe_V2")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "AE_ProfileProbe_V2"
gui.ResetOnSpawn = false
gui.DisplayOrder = 100250
gui.Parent = pg

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(780, 560)
main.Position = UDim2.new(.5, -390, .5, -280)
main.BackgroundColor3 = Color3.fromRGB(14,17,24)
main.BorderSizePixel = 0
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0,14)
local outline = Instance.new("UIStroke")
outline.Color = Color3.fromRGB(92,113,172)
outline.Transparency = .30
outline.Parent = main

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(20,11)
title.Size = UDim2.new(1,-75,0,30)
title.Text = "PROFILE + INVENTORY PROBE V2"
title.Font = Enum.Font.GothamBold
title.TextSize = 17
title.TextColor3 = Color3.fromRGB(240,242,248)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = main

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.fromOffset(20,40)
subtitle.Size = UDim2.new(1,-75,0,20)
subtitle.Text = "Read-only • logs Replica paths/payload shapes • can build an evidence-backed inventory override"
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 10
subtitle.TextColor3 = Color3.fromRGB(158,171,198)
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = main

local close = Instance.new("TextButton")
close.Position = UDim2.new(1,-51,0,12)
close.Size = UDim2.fromOffset(37,32)
close.Text = "×"
close.Font = Enum.Font.GothamBold
close.TextSize = 18
close.TextColor3 = Color3.new(1,1,1)
close.BackgroundColor3 = Color3.fromRGB(45,52,71)
close.BorderSizePixel = 0
close.Parent = main
Instance.new("UICorner", close).CornerRadius = UDim.new(0,9)

local status = Instance.new("TextLabel")
status.Position = UDim2.fromOffset(20,72)
status.Size = UDim2.new(1,-40,0,62)
status.BackgroundColor3 = Color3.fromRGB(23,28,39)
status.BorderSizePixel = 0
status.Text = "Starting one static scan…"
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextWrapped = true
status.TextColor3 = Color3.fromRGB(204,212,230)
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = main
Instance.new("UICorner", status).CornerRadius = UDim.new(0,10)
local statusPad = Instance.new("UIPadding")
statusPad.PaddingLeft = UDim.new(0,13)
statusPad.PaddingRight = UDim.new(0,13)
statusPad.Parent = status

local output = Instance.new("TextLabel")
output.Position = UDim2.fromOffset(20,147)
output.Size = UDim2.new(1,-40,1,-232)
output.BackgroundColor3 = Color3.fromRGB(18,22,31)
output.BorderSizePixel = 0
output.Text = "Preparing…"
output.Font = Enum.Font.Code
output.TextSize = 11
output.TextColor3 = Color3.fromRGB(222,227,238)
output.TextXAlignment = Enum.TextXAlignment.Left
output.TextYAlignment = Enum.TextYAlignment.Top
output.TextWrapped = false
output.Parent = main
Instance.new("UICorner", output).CornerRadius = UDim.new(0,10)
local outputPad = Instance.new("UIPadding")
outputPad.PaddingLeft = UDim.new(0,13)
outputPad.PaddingTop = UDim.new(0,11)
outputPad.Parent = output

local function setStatus(text) status.Text = tostring(text) end

local function addButton(text, x, width, callback)
    local button = Instance.new("TextButton")
    button.Position = UDim2.new(x, 10, 1, -68)
    button.Size = UDim2.new(width, -15, 0, 45)
    button.Text = text
    button.Font = Enum.Font.GothamBold
    button.TextSize = 10
    button.TextColor3 = Color3.new(1,1,1)
    button.BackgroundColor3 = Color3.fromRGB(67,84,139)
    button.BorderSizePixel = 0
    button.Parent = main
    Instance.new("UICorner", button).CornerRadius = UDim.new(0,10)
    Probe.Connections[#Probe.Connections + 1] = button.MouseButton1Click:Connect(callback)
    return button
end

local scanButton, captureButton, useButton, saveButton

local function capabilityTable()
    return {
        GetGC = type(getgc) == "function",
        Upvalues = (debug and (type(debug.getupvalues) == "function" or type(debug.getupvalue) == "function")) or type(getupvalues) == "function",
        WriteFile = type(writefile) == "function",
        GetLoadedModules = type(getloadedmodules) == "function",
    }
end

local function chooseProfile(report)
    table.sort(report.ProfileCandidates, function(a, b)
        if a.AllMatched ~= b.AllMatched then return a.AllMatched end
        if a.HotbarMatches ~= b.HotbarMatches then return a.HotbarMatches > b.HotbarMatches end
        if a.OwnerMatches ~= b.OwnerMatches then return a.OwnerMatches > b.OwnerMatches end
        return a.Score > b.Score
    end)
    local best = report.ProfileCandidates[1]
    if best and (best.AllMatched or best.OwnerMatches > 0 or (best.HotbarCount > 0 and best.HotbarMatches > 0)) then
        Probe.ExactProfile = best.Profile
        report.BestProfile = {
            Source=best.Source, Origin=best.Origin, OwnedCount=best.OwnedCount,
            HotbarCount=best.HotbarCount, HotbarMatches=best.HotbarMatches,
            OwnerMatches=best.OwnerMatches, Score=best.Score, Sample=best.Sample,
        }
    end
end

local function buildSynthetic(report)
    if Probe.ExactProfile then return Probe.ExactProfile, "EXACT PROFILE" end
    local trusted = {}
    for _, row in ipairs(Probe.ObservedOrder) do
        if row.Trusted then trusted[#trusted + 1] = row end
    end
    local sourceRows = #trusted >= 2 and trusted or Probe.ObservedOrder
    if #sourceRows < 2 then return nil, nil end

    local unitData = {}
    for index, row in ipairs(sourceRows) do
        local id = row.ID
        if unitData[id] ~= nil then id = id .. "-" .. tostring(index) end
        unitData[id] = row.Data
    end
    local profile = {UnitData=unitData, HotbarData={}}
    Probe.SyntheticProfile = profile
    report.SyntheticProfile = {
        OwnedCount=#sourceRows,
        TrustedCount=#trusted,
        Source=#trusted >= 2 and "trusted incoming inventory payload" or "progression-record evidence",
        Sample={},
    }
    for index = 1, math.min(6, #sourceRows) do
        report.SyntheticProfile.Sample[#report.SyntheticProfile.Sample + 1] = {
            ID=maskId(sourceRows[index].ID), Asset=sourceRows[index].Asset,
            Source=sourceRows[index].Source, Trusted=sourceRows[index].Trusted,
        }
    end
    return profile, report.SyntheticProfile.Source
end

local function reportText(report)
    local lines = {}
    lines[#lines + 1] = "PROFILE / INVENTORY PROBE " .. VERSION
    lines[#lines + 1] = "PlaceId: " .. tostring(game.PlaceId)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "CAPABILITIES"
    for _, key in ipairs({"GetGC","Upvalues","WriteFile","GetLoadedModules"}) do
        lines[#lines + 1] = "  " .. key .. ": " .. tostring(report.Capabilities[key])
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "STATIC SCAN"
    lines[#lines + 1] = "  GC objects: " .. tostring(report.ObjectCount or 0)
    lines[#lines + 1] = "  Replica modules: " .. tostring(report.ReplicaModulesScanned or 0)
    lines[#lines + 1] = "  Profile candidates: " .. tostring(#(report.ProfileCandidates or {}))
    lines[#lines + 1] = ""
    if report.BestProfile then
        lines[#lines + 1] = "EXACT PROFILE FOUND"
        lines[#lines + 1] = "  source: " .. tostring(report.BestProfile.Source)
        lines[#lines + 1] = "  owned: " .. tostring(report.BestProfile.OwnedCount)
        lines[#lines + 1] = "  hotbar: " .. tostring(report.BestProfile.HotbarMatches) .. "/" .. tostring(report.BestProfile.HotbarCount)
        lines[#lines + 1] = "  owner matches: " .. tostring(report.BestProfile.OwnerMatches)
    elseif report.SyntheticProfile then
        lines[#lines + 1] = "INVENTORY PAYLOAD FOUND"
        lines[#lines + 1] = "  owned records: " .. tostring(report.SyntheticProfile.OwnedCount)
        lines[#lines + 1] = "  trusted records: " .. tostring(report.SyntheticProfile.TrustedCount)
        lines[#lines + 1] = "  source: " .. tostring(report.SyntheticProfile.Source)
        lines[#lines + 1] = "  hotbar: not reconstructed yet"
    else
        lines[#lines + 1] = "NO USABLE PROFILE / INVENTORY YET"
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "PASSIVE CAPTURE"
    lines[#lines + 1] = "  events: " .. tostring(report.Capture and report.Capture.EventCount or 0)
    lines[#lines + 1] = "  relevant Replica paths: " .. tostring(report.Capture and #(report.Capture.RelevantReplicaPaths or {}) or 0)
    lines[#lines + 1] = "  incoming unit records observed: " .. tostring(#Probe.ObservedOrder)
    lines[#lines + 1] = "  trusted inventory events: " .. tostring(Probe.TrustedInventoryEvents)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "NEXT"
    if report.BestProfile or report.SyntheticProfile then
        lines[#lines + 1] = "  Press USE + OPEN BRAIN."
    else
        lines[#lines + 1] = "  Press CAPTURE 15s, then open Unit Manager and change one hotbar slot once."
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Saved report: AE_Tournament_Autopilot/profile_probe_v2_latest.json"
    return table.concat(lines, "\n")
end

function Probe:Save()
    if not self.Report then return false, "no report" end
    if type(writefile) ~= "function" then return false, "writefile unavailable" end
    if type(makefolder) == "function" then pcall(makefolder, "AE_Tournament_Autopilot") end
    local ok, encoded = pcall(function() return HS:JSONEncode(sanitize(self.Report)) end)
    if not ok then return false, tostring(encoded) end
    local path = "AE_Tournament_Autopilot/profile_probe_v2_latest.json"
    local wrote, err = pcall(writefile, path, encoded)
    return wrote, wrote and path or tostring(err)
end

function Probe:StaticScan(reuseCapture)
    if self.Destroyed or self.Busy then return end
    self.Busy = true
    scanButton.Text = "SCANNING…"
    setStatus("Collecting GC objects and checking exact Profile.UnitData / HotbarData evidence…")

    local previousCapture = reuseCapture and self.Report and self.Report.Capture or nil
    local report = {
        Version=VERSION,
        PlaceId=game.PlaceId,
        Time=os.time(),
        Capabilities=capabilityTable(),
        ObjectCount=0,
        ReplicaModulesScanned=0,
        ProfileCandidates={},
        BestProfile=nil,
        SyntheticProfile=nil,
        Capture=previousCapture,
    }

    self.ExactProfile = nil
    local objects = collectGC(report)
    local seenTables = {}
    for index, object in ipairs(objects) do
        if type(object) == "table" then
            local function inspect(value, source)
                if type(value) ~= "table" or seenTables[value] then return end
                seenTables[value] = true
                inspectProfile(value, source, report, "direct")
            end
            inspect(object, "getgc.table")
            for _, field in ipairs({"Data","Profile","ProfileData","PlayerData"}) do
                inspect(rawget(object, field), "getgc.table." .. field)
            end
        end
        if index % 4500 == 0 then setStatus("Direct GC tables: " .. index .. "/" .. #objects); task.wait() end
    end

    chooseProfile(report)
    if not self.ExactProfile and report.Capabilities.Upvalues then
        setStatus("No exact direct profile; checking function upvalues…")
        local functions = 0
        for _, object in ipairs(objects) do
            if type(object) == "function" then
                functions += 1
                local ups = getUpvalues(object)
                if type(ups) == "table" then
                    for name, value in pairs(ups) do
                        if type(value) == "table" then
                            inspectProfile(value, "upvalue." .. tostring(name), report, "upvalue")
                            local data = rawget(value, "Data")
                            if type(data) == "table" then inspectProfile(data, "upvalue." .. tostring(name) .. ".Data", report, "upvalue") end
                        end
                    end
                end
                if functions % 600 == 0 then setStatus("Function upvalues checked: " .. functions); task.wait() end
            end
        end
    end

    setStatus("Inspecting loaded ReplicaClient exports…")
    scanModuleExports(report)
    chooseProfile(report)
    buildSynthetic(report)

    self.Report = report
    output.Text = reportText(report)
    useButton.BackgroundColor3 = (report.BestProfile or report.SyntheticProfile) and Color3.fromRGB(50,145,96) or Color3.fromRGB(71,77,93)
    local saved, path = self:Save()
    setStatus((report.BestProfile or report.SyntheticProfile)
        and ("Evidence-backed data found. Press USE + OPEN BRAIN." .. (saved and (" Auto-saved " .. path) or ""))
        or ("Static scan finished without usable inventory. Press CAPTURE 15s and interact with Unit Manager/hotbar." .. (saved and (" Auto-saved " .. path) or "")))
    scanButton.Text = "STATIC SCAN"
    self.Busy = false
end

local function pathText(path)
    if type(path) ~= "table" then return tostring(path) end
    local pieces = {}
    for index = 1, math.min(12, #path) do pieces[#pieces + 1] = tostring(path[index]) end
    return table.concat(pieces, ".")
end

local function commandFromArgs(args)
    local strings = {}
    for index = 1, math.min(args.n, 5) do
        if type(args[index]) == "string" then strings[#strings + 1] = args[index] end
    end
    return table.concat(strings, " | ")
end

function Probe:Capture(seconds)
    if self.Destroyed or self.Busy then return end
    self.Busy = true
    seconds = tonumber(seconds) or 15
    self.ObservedRecords = {}
    self.ObservedOrder = {}
    self.TrustedInventoryEvents = 0
    for _, connection in ipairs(self.CaptureConnections) do pcall(function() connection:Disconnect() end) end
    self.CaptureConnections = {}

    local report = self.Report or {
        Version=VERSION, PlaceId=game.PlaceId, Time=os.time(), Capabilities=capabilityTable(),
        ObjectCount=0, ReplicaModulesScanned=0, ProfileCandidates={},
    }
    local capture = {
        EventCount=0,
        Signatures={},
        Events={},
        RelevantReplicaPaths={},
        UnitBatches={},
    }
    report.Capture = capture
    self.Report = report

    local function addSignature(remote, argc)
        local key = fullName(remote) .. " argc=" .. tostring(argc)
        capture.Signatures[key] = (capture.Signatures[key] or 0) + 1
    end

    local function handle(remote, ...)
        if self.Destroyed then return end
        local args = table.pack(...)
        capture.EventCount += 1
        addSignature(remote, args.n)

        local remoteName = fullName(remote)
        local normalizedRemote = norm(remote.Name)
        local event = {
            Remote=remoteName,
            Argc=args.n,
            Types={},
            Command=commandFromArgs(args),
        }
        for index = 1, math.min(args.n, 6) do event.Types[index] = typeof(args[index]) end

        if normalizedRemote == "replicaset" or normalizedRemote == "replicasetvalues" then
            event.ReplicaId = maskId(args[1])
            event.Path = pathText(args[2])
            event.Value = preview(args[3])
            local relevant = norm(event.Path)
            if relevant:find("unit",1,true) or relevant:find("hotbar",1,true) or relevant:find("trait",1,true)
                or relevant:find("equipment",1,true) or relevant:find("statpotential",1,true) or relevant:find("level",1,true) then
                if #capture.RelevantReplicaPaths < 180 then capture.RelevantReplicaPaths[#capture.RelevantReplicaPaths + 1] = event end
            end
        elseif normalizedRemote == "replicacreate" then
            event.Payload = preview(args[1])
        elseif normalizedRemote:find("updatenode",1,true) then
            event.Payload = preview(args[3] or args[1])
        end

        if #capture.Events < 180 then capture.Events[#capture.Events + 1] = event end

        local commandNorm = norm(event.Command)
        local trusted = commandNorm:find("unitupdateforplayer",1,true) ~= nil
            or commandNorm:find("requestassetreturnnode",1,true) ~= nil
            or commandNorm:find("unitmanager",1,true) ~= nil
        local eventRecords = {}
        local eventSet = {}
        for index = 1, math.min(args.n, 6) do
            if type(args[index]) == "table" then
                inspectProfile(args[index], "incoming:" .. remoteName .. ".arg" .. index, report, "incoming")
                local depth = (normalizedRemote == "replicacreate" or normalizedRemote:find("updatenode",1,true)) and 6 or 4
                local budget = (normalizedRemote == "replicacreate" or normalizedRemote:find("updatenode",1,true)) and 3000 or 700
                local rows = collectRecords(args[index], "incoming:" .. remoteName .. ".arg" .. index, trusted, depth, budget)
                for _, row in ipairs(rows) do
                    if not eventSet[row] then eventSet[row] = true; eventRecords[#eventRecords + 1] = row end
                end
            end
        end
        if #eventRecords >= 2 then
            if trusted then self.TrustedInventoryEvents += 1 end
            if #capture.UnitBatches < 80 then
                local sample = {}
                for index = 1, math.min(5, #eventRecords) do
                    sample[#sample + 1] = {Asset=eventRecords[index].Asset, ID=maskId(eventRecords[index].ID), Trusted=eventRecords[index].Trusted}
                end
                capture.UnitBatches[#capture.UnitBatches + 1] = {
                    Remote=remoteName, Command=event.Command, Count=#eventRecords, Trusted=trusted, Sample=sample,
                }
            end
        end
    end

    for _, root in ipairs({RS:FindFirstChild("RemoteEvents"), RS:FindFirstChild("Nodes")}) do
        if root then
            for _, remote in ipairs(root:GetDescendants()) do
                if remote:IsA("RemoteEvent") then
                    local name = norm(remote.Name)
                    if name:find("replica",1,true) or name:find("updatenode",1,true) then
                        self.CaptureConnections[#self.CaptureConnections + 1] = remote.OnClientEvent:Connect(function(...)
                            local packed = table.pack(...)
                            task.defer(function() handle(remote, table.unpack(packed, 1, packed.n)) end)
                        end)
                    end
                end
            end
        end
    end

    captureButton.Text = "CAPTURING…"
    setStatus("Capture running for " .. seconds .. "s. NOW open Unit Manager, scroll once, then change one hotbar slot once.")
    task.delay(seconds, function()
        if self.Destroyed then return end
        for _, connection in ipairs(self.CaptureConnections) do pcall(function() connection:Disconnect() end) end
        self.CaptureConnections = {}
        captureButton.Text = "CAPTURE 15s"
        self.Busy = false
        setStatus("Capture complete. Running one static re-scan and building an inventory override from observed progression records…")
        task.spawn(function() self:StaticScan(true) end)
    end)
end

function Probe:UseAndOpenBrain()
    if self.Destroyed or not self.Report then return end
    local profile, source
    if self.ExactProfile then profile, source = self.ExactProfile, "exact profile" else profile, source = buildSynthetic(self.Report) end
    if type(profile) ~= "table" then
        setStatus("No evidence-backed profile or inventory is available. Run CAPTURE 15s first.")
        return
    end
    ENV.AE_TOURNAMENT_PROFILE_OVERRIDE = profile
    ENV.AE_TOURNAMENT_PROFILE_OVERRIDE_SOURCE = source
    setStatus("Installed " .. tostring(source) .. " override. Loading Tournament Brain with a cache-busting nonce…")
    local url = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Tournament_Autopilot/start.lua?probe_v2=" .. tostring(os.time())
    local ok, sourceCode = pcall(function() return game:HttpGet(url) end)
    if not ok then setStatus("Brain loader fetch failed: " .. tostring(sourceCode)) return end
    local chunk, compileError = loadstring(sourceCode)
    if not chunk then setStatus("Brain loader compile failed: " .. tostring(compileError)) return end
    local ran, runtimeError = pcall(chunk)
    if not ran then setStatus("Brain loader runtime failed: " .. tostring(runtimeError)) return end
    setStatus("Tournament Brain loaded. Press SCAN there; this Probe can now be closed.")
end

scanButton = addButton("STATIC SCAN", 0, .25, function() task.spawn(function() Probe:StaticScan(true) end) end)
captureButton = addButton("CAPTURE 15s", .25, .25, function() Probe:Capture(15) end)
useButton = addButton("USE + OPEN BRAIN", .50, .25, function() Probe:UseAndOpenBrain() end)
saveButton = addButton("SAVE REPORT", .75, .25, function()
    local ok, result = Probe:Save()
    setStatus(ok and ("Saved " .. tostring(result)) or ("Save failed: " .. tostring(result)))
end)

Probe.Connections[#Probe.Connections + 1] = close.MouseButton1Click:Connect(function() Probe:Destroy() end)

function Probe:Destroy()
    if self.Destroyed then return end
    self.Destroyed = true
    for _, connection in ipairs(self.Connections) do pcall(function() connection:Disconnect() end) end
    for _, connection in ipairs(self.CaptureConnections) do pcall(function() connection:Disconnect() end) end
    self.Connections = {}
    self.CaptureConnections = {}
    if gui then gui:Destroy() end
    if ENV.AE_TOURNAMENT_PROFILE_PROBE_V2 == self then ENV.AE_TOURNAMENT_PROFILE_PROBE_V2 = nil end
end

task.delay(.35, function()
    if not Probe.Destroyed then task.spawn(function() Probe:StaticScan(false) end) end
end)

print("[AE Profile Probe V2] READY", VERSION)
