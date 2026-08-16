-- Greedy Growers diagnostic bootstrap + passive adapter
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local player = Players.LocalPlayer

local BASE = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/GreedyGrowers/"
local MAIN_SOURCE = BASE .. "main.lua"
local ADAPTER_SOURCE = BASE .. "passive_adapter.lua"

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
    frame.Size = UDim2.fromOffset(460, 185)
    frame.Position = UDim2.new(0.5, -230, 0, 70)
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
    title.Text = "Greedy Growers | Bootstrap"
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
    if #history > 7 then table.remove(history,1) end
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

local function loadRemote(url, labelName)
    local source = httpGet(url)
    if not source then return nil, labelName .. " download failed" end
    if type(loadstring) ~= "function" then return nil, "loadstring unavailable" end
    local chunk, compileErr = loadstring(source)
    if not chunk then return nil, labelName .. " compile: " .. tostring(compileErr) end
    local ok, result = pcall(chunk)
    if not ok then return nil, labelName .. " runtime: " .. tostring(result) end
    return result
end

status("[0/5] Bootstrap GUI created")
status("[1/5] Loading controller...")
local Greedy, mainErr = loadRemote(MAIN_SOURCE, "main.lua")
if not Greedy then status("ERROR: "..tostring(mainErr), true) return end
if type(Greedy) ~= "table" then status("ERROR: controller returned "..typeof(Greedy), true) return end
status("[1/5] Controller OK")

status("[2/5] Loading passive runtime adapter...")
local Adapter, adapterErr = loadRemote(ADAPTER_SOURCE, "passive_adapter.lua")
if not Adapter then status("ERROR: "..tostring(adapterErr), true) return Greedy end
if type(Adapter) ~= "table" then status("ERROR: adapter returned "..typeof(Adapter), true) return Greedy end
status("[2/5] Adapter OK")

status("[3/5] Attaching runtime discovery...")
local attachOk, attachErr = pcall(function()
    Greedy.AttachAdapter(Adapter)
    Greedy.SetConfig({Enabled = true, AutoHarvest = false, AutoSell = false, AutoOptimize = true})
end)
if not attachOk then status("ERROR attach: "..tostring(attachErr), true) return Greedy end
status("[3/5] Passive runtime active")

status("[4/5] Testing discovery...")
local trees = {}
local discoverOk, discoverErr = pcall(function()
    trees = Adapter:GetTrees()
end)
if discoverOk then
    status("[4/5] Found "..tostring(#trees).." tree-like objects | Cash $"..tostring(Adapter:GetCash()))
else
    status("[4/5] Discovery warning: "..tostring(discoverErr))
end

status("[5/5] Starting Rayfield...")
local uiok, uierr = pcall(Greedy.CreateUI)
if not uiok then status("ERROR UI: "..tostring(uierr),true) return Greedy end
status("[5/5] READY | Passive optimizer/monitor active")

getgenv().GreedyGrowers = Greedy
getgenv().GreedyGrowersAdapter = Adapter
return Greedy
