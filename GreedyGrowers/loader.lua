-- Greedy Growers diagnostic bootstrap
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local player = Players.LocalPlayer

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
    frame.Size = UDim2.fromOffset(430, 155)
    frame.Position = UDim2.new(0.5, -215, 0, 70)
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
    if #history > 6 then table.remove(history,1) end
    print("[GreedyGrowers]", text)
    if bad then warn("[GreedyGrowers]", text) end
    if label then
        label.Text = table.concat(history,"\n")
        label.TextColor3 = bad and Color3.fromRGB(255,135,135) or Color3.fromRGB(220,220,225)
    end
end

status("[0/4] Bootstrap GUI created")
local SOURCE = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/GreedyGrowers/main.lua"

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

status("[1/4] Testing GitHub download...")
local source = httpGet(SOURCE)
if not source then status("ERROR: HTTP/request unavailable or blocked",true) return end
status("[1/4] Download OK: "..#source.." bytes")

status("[2/4] Compiling main.lua...")
if type(loadstring)~="function" then status("ERROR: loadstring unavailable",true) return end
local chunk, err = loadstring(source)
if not chunk then status("ERROR compile: "..tostring(err),true) return end
status("[2/4] Compile OK")

status("[3/4] Starting controller...")
local ok, Greedy = pcall(chunk)
if not ok then status("ERROR controller: "..tostring(Greedy),true) return end
if type(Greedy)~="table" then status("ERROR: controller returned "..typeof(Greedy),true) return end
status("[3/4] Controller OK")

status("[4/4] Starting Rayfield...")
local uiok, uierr = pcall(Greedy.CreateUI)
if not uiok then status("ERROR UI: "..tostring(uierr),true) return Greedy end
status("[4/4] UI call completed")
getgenv().GreedyGrowers = Greedy
return Greedy
