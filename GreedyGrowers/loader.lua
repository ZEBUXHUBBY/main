-- Greedy Growers snapshot-aware bootstrap
-- Passive observer for supplied snapshot. No server remote invocation is performed here.
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local player = Players.LocalPlayer

local BASE = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/GreedyGrowers/"
local MAIN_SOURCE = BASE .. "main.lua"
local SNAPSHOT_SOURCE = BASE .. "snapshot_adapter.lua"
local FALLBACK_SOURCE = BASE .. "passive_adapter.lua"

local function makeStatusGui()
    local parent = CoreGui
    if not parent then parent = player and player:FindFirstChildOfClass("PlayerGui") end
    if not parent then return nil, nil end
    pcall(function()
        local old = parent:FindFirstChild("GreedyGrowersBootstrap")
        if old then old:Destroy() end
    end)
    local gui = Instance.new("ScreenGui")
    gui.Name = "GreedyGrowersBootstrap"
    gui.ResetOnSpawn = false
    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(500, 210)
    frame.Position = UDim2.new(0.5, -250, 0, 70)
    frame.BackgroundColor3 = Color3.fromRGB(24,24,30)
    frame.BorderSizePixel = 0
    frame.Parent = gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0,10)
    corner.Parent = frame
    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1,-24,0,35)
    title.Position = UDim2.fromOffset(12,8)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.new(1,1,1)
    title.Text = "Greedy Growers | Snapshot Monitor"
    title.Parent = frame
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1,-24,1,-55)
    label.Position = UDim2.fromOffset(12,43)
    label.Font = Enum.Font.Code
    label.TextSize = 14
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.TextColor3 = Color3.fromRGB(220,220,225)
    label.Parent = frame
    gui.Parent = parent
    return gui, label
end

local gui, label = makeStatusGui()
local history = {}
local function status(text, bad)
    table.insert(history, text)
    if #history > 8 then table.remove(history,1) end
    print("[GreedyGrowers]", text)
    if bad then warn("[GreedyGrowers]", text) end
    if label then
        label.Text = table.concat(history,"\n")
        label.TextColor3 = bad and Color3.fromRGB(255,135,135) or Color3.fromRGB(220,220,225)
    end
end

local function httpGet(url)
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body)=="string" and #body>0 then return body end
    local req = (syn and syn.request) or http_request or request
    if req then
        local rok, res = pcall(req,{Url=url,Method="GET"})
        if rok and res then
            local b = res.Body or res.body
            if type(b)=="string" and #b>0 then return b end
        end
    end
end

local function loadRemote(url, name)
    local source = httpGet(url)
    if not source then return nil, name.." download failed" end
    if type(loadstring) ~= "function" then return nil, "loadstring unavailable" end
    local chunk, compileErr = loadstring(source)
    if not chunk then return nil, name.." compile: "..tostring(compileErr) end
    local ok, result = pcall(chunk)
    if not ok then return nil, name.." runtime: "..tostring(result) end
    return result
end

status("[0/6] Bootstrap ready")

local Greedy, mainErr = loadRemote(MAIN_SOURCE, "main.lua")
if not Greedy or type(Greedy) ~= "table" then
    status("ERROR controller: "..tostring(mainErr or typeof(Greedy)), true)
    return
end
status("[1/6] Controller OK")

local Adapter, adapterErr = loadRemote(SNAPSHOT_SOURCE, "snapshot_adapter.lua")
local adapterMode = "snapshot"
if not Adapter or type(Adapter) ~= "table" then
    status("[2/6] Snapshot adapter failed; fallback")
    Adapter, adapterErr = loadRemote(FALLBACK_SOURCE, "passive_adapter.lua")
    adapterMode = "generic"
end
if not Adapter or type(Adapter) ~= "table" then
    status("ERROR adapter: "..tostring(adapterErr or typeof(Adapter)), true)
    return Greedy
end
status("[2/6] Adapter OK: "..adapterMode)

local okAttach, attachErr = pcall(function()
    Greedy.AttachAdapter(Adapter)
    Greedy.SetConfig({Enabled=true, AutoOptimize=true, AutoHarvest=false, AutoSell=false})
end)
if not okAttach then
    status("ERROR attach: "..tostring(attachErr), true)
    return Greedy
end
status("[3/6] Snapshot observer attached")

-- IMPORTANT: immediate lightning path.
-- This fires in the same client callback that receives Event("lightning").
-- It does not wait for CrashedAll or the controller polling loop.
local emergencyConnection
if Adapter.LightningObserved and type(Adapter.LightningObserved.Connect) == "function" then
    emergencyConnection = Adapter.LightningObserved:Connect(function(ts)
        status("LIGHTNING -> EMERGENCY HARVEST NOW")

        -- Only execute an action when an explicitly writable/authorized adapter exposes it.
        if Adapter.ReadOnly ~= true and type(Adapter.HarvestTree) == "function" and type(Adapter.GetTrees) == "function" then
            local okTrees, trees = pcall(Adapter.GetTrees, Adapter)
            if okTrees and type(trees) == "table" then
                for _, tree in ipairs(trees) do
                    task.spawn(function()
                        local ok, result = pcall(Adapter.HarvestTree, Adapter, tree)
                        if not ok then
                            warn("[GreedyGrowers] Emergency harvest failed:", result)
                        end
                    end)
                end
            end
        else
            -- Snapshot adapter is intentionally passive/read-only.
            -- Still mark the exact action point before CrashedAll arrives.
            getgenv().GreedyGrowersEmergency = {
                action = "HARVEST_NOW",
                triggeredAt = ts or os.clock(),
                reason = "Event(lightning)",
                beforeCrash = true,
            }
        end
    end)
end
status("[4/6] Lightning immediate callback armed")

if type(Adapter.GetSnapshotStatus) == "function" then
    local ok, s = pcall(Adapter.GetSnapshotStatus, Adapter)
    if ok and s then
        status(string.format("[5/6] Bound %s | Cash $%s | rounds %s", tostring(s.boundRemotes), tostring(s.cash), tostring(s.activeRounds)))
    else
        status("[5/6] Snapshot status unavailable")
    end
else
    status("[5/6] Generic adapter active")
end

local uiok, uierr = pcall(Greedy.CreateUI)
if not uiok then
    status("ERROR UI: "..tostring(uierr), true)
else
    status("[6/6] READY | waiting for Event(lightning)")
end

getgenv().GreedyGrowers = Greedy
getgenv().GreedyGrowersAdapter = Adapter
getgenv().GreedyGrowersEmergencyConnection = emergencyConnection
getgenv().GreedyGrowersStatus = function()
    if type(Adapter.GetSnapshotStatus) == "function" then
        return Adapter:GetSnapshotStatus()
    end
    return {mode=adapterMode, cash=Adapter.GetCash and Adapter:GetCash() or nil}
end

return Greedy
