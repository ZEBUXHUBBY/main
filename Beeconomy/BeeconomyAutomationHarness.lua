-- Beeconomy Event-Based Auto Learner (Rayfield)
-- Learns current-session action signatures from normal gameplay.
-- It observes outgoing remotes + local input/state changes and DOES NOT replay unknown remotes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
local PLACE_ID = 101558830312092

if game.PlaceId ~= PLACE_ID then
    warn("[Beeconomy Learner] Unexpected place:", game.PlaceId)
end

local CFG = {
    Enabled = true,
    CorrelationWindow = 1.25,
    MaxEvents = 1200,
    AutoExport = false,
    ExportEvery = 60,
    Verbose = false,
}

local Runtime = {
    started = os.clock(),
    events = {},
    learned = {},
    lastInput = nil,
    lastExport = 0,
    hookInstalled = false,
}

local TRACKED_ATTRS = {
    "EquippedPickaxeId",
    "ShovelEquipped",
    "EquippedAxeId",
    "EquippedTitle",
    "EquippedNetId",
    "EquippedFishingRodId",
    "ActiveHoldRevision",
    "BeeCombatTargetMobId",
    "BeeCombatTargetFieldDb",
    "SelectedMobId",
    "GripHoldKind",
}

local function now()
    return os.clock() - Runtime.started
end

local function log(...)
    print("[Beeconomy Learner]", ...)
end

local function safe(v, depth)
    depth = depth or 0
    if depth > 3 then return "<deep>" end
    local tv = typeof(v)
    if tv == "Vector3" then
        return {__type="Vector3", x=v.X, y=v.Y, z=v.Z}
    elseif tv == "CFrame" then
        return {__type="CFrame", components={v:GetComponents()}}
    elseif tv == "Instance" then
        return {__type="Instance", class=v.ClassName, path=v:GetFullName()}
    elseif tv == "EnumItem" then
        return tostring(v)
    elseif tv == "table" then
        local out = {}
        local n = 0
        for k,val in pairs(v) do
            n += 1
            if n > 40 then
                out.__truncated = true
                break
            end
            out[tostring(k)] = safe(val, depth+1)
        end
        return out
    elseif tv == "string" or tv == "number" or tv == "boolean" or tv == "nil" then
        return v
    end
    return tostring(v)
end

local function push(kind, data)
    if not CFG.Enabled then return end
    local e = {
        t = now(),
        kind = kind,
        data = safe(data),
    }
    table.insert(Runtime.events, e)
    while #Runtime.events > CFG.MaxEvents do
        table.remove(Runtime.events, 1)
    end
    if CFG.Verbose then
        log(kind, HttpService:JSONEncode(e.data))
    end
end

local function getLeaderstat(name)
    local ls = LP:FindFirstChild("leaderstats")
    local v = ls and ls:FindFirstChild(name)
    return v and v.Value or nil
end

local function snapshot()
    local s = {
        Level = getLeaderstat("Level"),
        Honey = getLeaderstat("Honey"),
        Hatches = getLeaderstat("Hatches"),
    }
    for _,attr in ipairs(TRACKED_ATTRS) do
        s[attr] = LP:GetAttribute(attr)
    end
    local ch = LP.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if hrp then s.Position = hrp.Position end
    return s
end

local function classifyRemote(remotePath, method, args)
    local tag = "unknown"
    local a3 = args[3]
    local a4 = args[4]
    local a5 = args[5]
    local field = LP:GetAttribute("BeeCombatTargetFieldDb")

    if method == "InvokeServer" then
        if a3 == "hourly" or a3 == "daily" or a3 == "weekly" then
            tag = "reward:" .. tostring(a3)
        elseif type(a3) == "string" and string.find(string.lower(a3), "quest", 1, true) then
            tag = "quest"
        end
    elseif method == "FireServer" then
        if type(a3) == "string" and typeof(a4) == "Vector3" and type(a5) == "table" then
            tag = "farm"
        elseif type(a3) == "string" and field and a3 == field then
            tag = "farm"
        elseif LP:GetAttribute("SelectedMobId") or LP:GetAttribute("BeeCombatTargetMobId") then
            tag = "mob_candidate"
        elseif LP:GetAttribute("EquippedFishingRodId") and LP:GetAttribute("GripHoldKind") == "fishing" then
            tag = "fishing_candidate"
        end
    end

    return tag
end

local function signature(remotePath, method, args)
    local types = {}
    for i=1,#args do
        types[i] = typeof(args[i])
    end
    return table.concat({remotePath, method, tostring(#args), table.concat(types, ",")}, "|")
end

local function learnRemote(remote, method, args)
    local path = remote:GetFullName()
    local tag = classifyRemote(path, method, args)
    local sig = signature(path, method, args)

    local rec = Runtime.learned[sig]
    if not rec then
        rec = {
            remote = path,
            method = method,
            argc = #args,
            types = {},
            count = 0,
            tags = {},
            samples = {},
        }
        for i=1,#args do rec.types[i] = typeof(args[i]) end
        Runtime.learned[sig] = rec
    end

    rec.count += 1
    rec.tags[tag] = (rec.tags[tag] or 0) + 1
    if #rec.samples < 5 then
        local sample = {}
        for i=1,#args do sample[i] = safe(args[i]) end
        table.insert(rec.samples, sample)
    end

    push("remote_out", {
        remote = path,
        method = method,
        tag = tag,
        signature = sig,
        args = args,
        state = snapshot(),
        lastInput = Runtime.lastInput,
    })
end

local function installNetworkObserver()
    if Runtime.hookInstalled then return true end
    if not hookmetamethod or not getnamecallmethod or not newcclosure then
        warn("[Beeconomy Learner] Executor does not expose hookmetamethod/getnamecallmethod/newcclosure")
        return false
    end

    local old
    old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if CFG.Enabled and typeof(self) == "Instance" and (method == "FireServer" or method == "InvokeServer") then
            local args = {...}
            task.defer(function()
                pcall(learnRemote, self, method, args)
            end)
        end
        return old(self, ...)
    end))

    Runtime.hookInstalled = true
    log("Network observer installed")
    return true
end

local function watchState()
    for _,attr in ipairs(TRACKED_ATTRS) do
        LP:GetAttributeChangedSignal(attr):Connect(function()
            push("state", {name=attr, value=LP:GetAttribute(attr), snapshot=snapshot()})
        end)
    end

    local ls = LP:FindFirstChild("leaderstats") or LP:WaitForChild("leaderstats", 10)
    if ls then
        for _,name in ipairs({"Level","Honey","Hatches"}) do
            local v = ls:FindFirstChild(name)
            if v and v:IsA("ValueBase") then
                v.Changed:Connect(function(new)
                    push("leaderstat", {name=name, value=new, snapshot=snapshot()})
                end)
            end
        end
    end
end

local function watchInput()
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        local item = {
            type = tostring(input.UserInputType),
            key = tostring(input.KeyCode),
            pos = input.Position,
            t = now(),
        }
        Runtime.lastInput = item
        push("input", item)
    end)
end

local function recentCorrelations(seconds)
    seconds = seconds or CFG.CorrelationWindow
    local cutoff = now() - seconds
    local out = {}
    for i=#Runtime.events,1,-1 do
        local e = Runtime.events[i]
        if e.t < cutoff then break end
        table.insert(out, 1, e)
    end
    return out
end

local function summarizeLearned()
    local rows = {}
    for sig,rec in pairs(Runtime.learned) do
        local bestTag, bestN = "unknown", 0
        for tag,n in pairs(rec.tags) do
            if n > bestN then bestTag,bestN = tag,n end
        end
        table.insert(rows, {
            signature=sig,
            remote=rec.remote,
            method=rec.method,
            argc=rec.argc,
            types=rec.types,
            count=rec.count,
            bestTag=bestTag,
            confidence=rec.count > 0 and math.floor((bestN/rec.count)*100+0.5) or 0,
            samples=rec.samples,
        })
    end
    table.sort(rows, function(a,b) return a.count > b.count end)
    return rows
end

local function buildReport()
    return {
        game = game.Name,
        placeId = game.PlaceId,
        generatedAt = os.time(),
        sessionSeconds = now(),
        state = safe(snapshot()),
        learned = summarizeLearned(),
        recent = recentCorrelations(5),
    }
end

local function exportReport()
    local report = buildReport()
    local json = HttpService:JSONEncode(report)
    local filename = "Beeconomy_AutoLearn_" .. tostring(os.time()) .. ".json"
    if writefile then
        local ok,err = pcall(writefile, filename, json)
        if ok then
            log("Saved", filename)
            return filename
        end
        warn("[Beeconomy Learner] writefile failed", err)
    end
    print("===== BEEconomy AUTO LEARN REPORT =====")
    print(json)
    print("===== END REPORT =====")
    return nil
end

local function printTop()
    local rows = summarizeLearned()
    print("===== LEARNED SIGNATURES =====")
    for i=1,math.min(#rows,20) do
        local r = rows[i]
        print(string.format("[%d] %s %s argc=%d count=%d tag=%s confidence=%d%%", i, r.method, r.remote, r.argc, r.count, r.bestTag, r.confidence))
    end
    print("===== END =====")
end

installNetworkObserver()
watchState()
watchInput()
push("start", {state=snapshot()})

local Rayfield = loadstring(game:HttpGet(((getgenv and getgenv().RayfieldUrl) or "https://sirius.menu/rayfield")))()
local Window = Rayfield:CreateWindow({
    Name = "Beeconomy Auto Learner",
    Icon = 0,
    LoadingTitle = "Beeconomy Event Learner",
    LoadingSubtitle = "ZEBUXHUBBY",
    ConfigurationSaving = {Enabled=false},
    KeySystem = false,
})

local LearnTab = Window:CreateTab("Auto Detect",4483362458)
local DebugTab = Window:CreateTab("Debug",4483362458)

LearnTab:CreateToggle({
    Name="Enable Event Learning",
    CurrentValue=CFG.Enabled,
    Flag="BeeLearnEnabled",
    Callback=function(v) CFG.Enabled=v end,
})

LearnTab:CreateSlider({
    Name="Correlation Window",
    Range={0.25,3},
    Increment=0.25,
    Suffix="s",
    CurrentValue=CFG.CorrelationWindow,
    Flag="BeeCorrelation",
    Callback=function(v) CFG.CorrelationWindow=v end,
})

LearnTab:CreateToggle({
    Name="Verbose Console",
    CurrentValue=CFG.Verbose,
    Flag="BeeVerbose",
    Callback=function(v) CFG.Verbose=v end,
})

LearnTab:CreateToggle({
    Name="Auto Export Every 60s",
    CurrentValue=CFG.AutoExport,
    Flag="BeeAutoExport",
    Callback=function(v) CFG.AutoExport=v end,
})

LearnTab:CreateButton({Name="Print Learned Signatures",Callback=printTop})
LearnTab:CreateButton({Name="Export Learning Report",Callback=exportReport})
LearnTab:CreateButton({Name="Print Last 1.25s Events",Callback=function()
    print("===== RECENT CORRELATION =====")
    for _,e in ipairs(recentCorrelations()) do
        print(string.format("+%.3f %s %s", e.t, e.kind, HttpService:JSONEncode(e.data)))
    end
    print("===== END =====")
end})

DebugTab:CreateButton({Name="Print Current State",Callback=function()
    print(HttpService:JSONEncode(safe(snapshot())))
end})

DebugTab:CreateButton({Name="Count Learned Signatures",Callback=function()
    local n=0
    for _ in pairs(Runtime.learned) do n+=1 end
    log("Learned signatures:",n,"events:",#Runtime.events,"hook:",Runtime.hookInstalled)
end})

DebugTab:CreateParagraph({
    Title="How to train it",
    Content="Just play normally. Do one action at a time (equip shovel, swing, click mob, fish, claim reward, quest). The learner watches input + state + remotes and groups signatures automatically. No old opcode is replayed.",
})

task.spawn(function()
    while task.wait(1) do
        if CFG.AutoExport and now()-Runtime.lastExport >= CFG.ExportEvery then
            Runtime.lastExport = now()
            exportReport()
        end
    end
end)

Rayfield:Notify({
    Title="Beeconomy Auto Learner",
    Content=Runtime.hookInstalled and "Event learner active. Play normally to train it." or "Loaded, but network hook is unavailable in this executor.",
    Duration=6,
})

log("Loaded event-based learner. hookInstalled =", Runtime.hookInstalled)
