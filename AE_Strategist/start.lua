-- AE Strategist | Tournament-only SAFE BOOT
-- UI appears immediately. Heavy core/stat work happens only after the user presses ANALYZE.
-- No polling / no background analyze / no AE_Assistant dependency.

local ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Strategist/"
local ENV = getgenv and getgenv() or _G
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local LP = Players.LocalPlayer

for _, key in ipairs({
    "AE_STRATEGIST_VISUAL",
    "AE_STRATEGIST_DASHBOARD",
    "AE_STRATEGIST_RUNTIME",
    "AE_STRATEGIST_OWNED_STATS",
    "AE_TOURNAMENT_OPTIMIZER",
}) do
    local obj = ENV[key]
    if type(obj) == "table" and type(obj.Destroy) == "function" then
        pcall(obj.Destroy)
    end
end
if type(ENV.AE_STRATEGIST) == "table" and type(ENV.AE_STRATEGIST.Destroy) == "function" then
    pcall(ENV.AE_STRATEGIST.Destroy)
end

local parentGui
pcall(function()
    if gethui then parentGui = gethui() end
end)
parentGui = parentGui or CoreGui
if not parentGui then parentGui = LP:WaitForChild("PlayerGui") end

for _, root in ipairs({parentGui, LP:FindFirstChild("PlayerGui")}) do
    if root then
        for _, name in ipairs({
            "AE_Tournament_Boot",
            "AE_Tournament_Only",
            "AE_Strategist_Standalone",
            "AE_Strategist_DashboardV2",
            "AE_Strategist_VisualAddon",
            "AE_Strategist_VisualV2",
        }) do
            local old = root:FindFirstChild(name)
            if old then pcall(function() old:Destroy() end) end
        end
    end
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "AE_Tournament_Boot"
Gui.ResetOnSpawn = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = parentGui

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(520, 230)
Main.Position = UDim2.new(0.5, -260, 0.5, -115)
Main.BackgroundColor3 = Color3.fromRGB(14, 17, 24)
Main.BorderSizePixel = 0
Main.Parent = Gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = Main

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.fromOffset(18, 13)
Title.Size = UDim2.new(1, -70, 0, 30)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 16
Title.TextColor3 = Color3.fromRGB(238, 240, 246)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "AE • TOURNAMENT OPTIMIZER"
Title.Parent = Main

local Close = Instance.new("TextButton")
Close.Size = UDim2.fromOffset(36, 30)
Close.Position = UDim2.new(1, -50, 0, 12)
Close.BackgroundColor3 = Color3.fromRGB(46, 52, 70)
Close.BorderSizePixel = 0
Close.Text = "×"
Close.TextColor3 = Color3.new(1,1,1)
Close.Font = Enum.Font.GothamBold
Close.TextSize = 17
Close.Parent = Main
local cc = Instance.new("UICorner")
cc.CornerRadius = UDim.new(0,8)
cc.Parent = Close

local Status = Instance.new("TextLabel")
Status.BackgroundTransparency = 1
Status.Position = UDim2.fromOffset(18, 52)
Status.Size = UDim2.new(1, -36, 0, 78)
Status.Font = Enum.Font.Gotham
Status.TextSize = 11
Status.TextWrapped = true
Status.TextColor3 = Color3.fromRGB(165, 174, 198)
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.TextYAlignment = Enum.TextYAlignment.Top
Status.Text = "READY\nNo background scan. Press ANALYZE once when you want a fresh Tournament snapshot."
Status.Parent = Main

local Analyze = Instance.new("TextButton")
Analyze.Size = UDim2.new(1, -36, 0, 48)
Analyze.Position = UDim2.fromOffset(18, 154)
Analyze.BackgroundColor3 = Color3.fromRGB(65, 82, 134)
Analyze.BorderSizePixel = 0
Analyze.Text = "ANALYZE TOURNAMENT"
Analyze.TextColor3 = Color3.new(1,1,1)
Analyze.Font = Enum.Font.GothamBold
Analyze.TextSize = 13
Analyze.Parent = Main
local ac = Instance.new("UICorner")
ac.CornerRadius = UDim.new(0,9)
ac.Parent = Analyze

Close.MouseButton1Click:Connect(function()
    Gui:Destroy()
end)

local busy = false
local function fetch(path)
    local ok, source = pcall(function()
        return game:HttpGet(ROOT .. path)
    end)
    if not ok then return nil, tostring(source) end
    return source
end

local function compileAndRun(label, source)
    local chunk, compileError = loadstring(source)
    if not chunk then
        return false, label .. " COMPILE ERROR: " .. tostring(compileError)
    end
    local ok, runtimeError = pcall(chunk)
    if not ok then
        return false, label .. " RUNTIME ERROR: " .. tostring(runtimeError)
    end
    return true
end

local function loadHiddenCore()
    if type(ENV.AE_STRATEGIST) == "table" and type(ENV.AE_STRATEGIST.GetState) == "function" then
        return true
    end

    Status.Text = "1/3  Loading hidden data core…"
    local source, err = fetch("main.lua")
    if not source then return false, "CORE FETCH ERROR: " .. tostring(err) end

    source = source:gsub("tonumber(%b())", function(args)
        if args:sub(1, 7) == "(getCI(" then
            return "tonumber((" .. args:sub(2, -2) .. "))"
        end
        return "tonumber" .. args
    end)

    source = source:gsub("Gui%.Parent = parentGui", "Gui.Parent = parentGui\nGui.Enabled = false", 1)
    source = source:gsub(
        "task%.spawn%(function%(%)%s*pcall%(runAnalysis%)%s*pcall%(function%(%) discoverPath%(%) end%)%s*end%)",
        "-- AE Tournament: startup analysis disabled",
        1
    )

    local ok, runErr = compileAndRun("CORE", source)
    if not ok then return false, runErr end

    local core = ENV.AE_STRATEGIST
    if type(core) ~= "table" or type(core.GetState) ~= "function" then
        return false, "CORE ERROR: loaded but AE_STRATEGIST.GetState is missing"
    end
    if core.Gui then pcall(function() core.Gui.Enabled = false end) end
    return true
end

local function loadTournamentEngine()
    Status.Text = "2/3  Loading Tournament engine…"
    local source, err = fetch("tournament_only.lua")
    if not source then return false, "TOURNAMENT FETCH ERROR: " .. tostring(err) end

    source = source:gsub("tonumber(%b())", function(args)
        if args:sub(1, 4) == "(ci(" then
            return "tonumber((" .. args:sub(2, -2) .. "))"
        end
        return "tonumber" .. args
    end)

    source = source:gsub(
        "local exact,processor=resolveExactStats%(out%.Asset,data,template%.Base%)",
        "local exact,processor=nil,nil\n    if not traitOverride and equipOverride==nil then exact,processor=resolveExactStats(out.Asset,data,template.Base) end",
        1
    )

    source = source:gsub(
        "if exact and exact%.CritChance~=nil and not traitOverride and equipOverride==nil then cc=exact%.CritChance else cc=nativeAdd%(cc,ccAdd,false%) end",
        "if exact and exact.CritChance~=nil and not traitOverride and equipOverride==nil then cc=cc+(exact.CritChance-(template.Base.CritChance or 0)) else cc=nativeAdd(cc,ccAdd,false) end",
        1
    )
    source = source:gsub(
        "if exact and exact%.CritDamage~=nil and not traitOverride and equipOverride==nil then cd=exact%.CritDamage else cd=nativeAdd%(cd,cdAdd,true%) end",
        "if exact and exact.CritDamage~=nil and not traitOverride and equipOverride==nil then cd=cd+(exact.CritDamage-(template.Base.CritDamage or 0)) else cd=nativeAdd(cd,cdAdd,true) end",
        1
    )

    local ok, runErr = compileAndRun("TOURNAMENT", source)
    if not ok then return false, runErr end
    if type(ENV.AE_TOURNAMENT_OPTIMIZER) ~= "table" then
        return false, "TOURNAMENT ERROR: engine returned without creating AE_TOURNAMENT_OPTIMIZER"
    end
    return true
end

Analyze.MouseButton1Click:Connect(function()
    if busy then return end
    busy = true
    Analyze.Text = "LOADING…"

    task.spawn(function()
        local ok, err = loadHiddenCore()
        if not ok then
            Status.Text = err
            Analyze.Text = "RETRY"
            busy = false
            return
        end

        ok, err = loadTournamentEngine()
        if not ok then
            Status.Text = err
            Analyze.Text = "RETRY"
            busy = false
            return
        end

        Status.Text = "3/3  Running one-shot inventory/stat analysis…"
        local optimizer = ENV.AE_TOURNAMENT_OPTIMIZER
        local analyzed, analyzeErr = pcall(function()
            optimizer.Analyze()
        end)
        if not analyzed then
            Status.Text = "ANALYZE ERROR: " .. tostring(analyzeErr)
            Analyze.Text = "RETRY"
            busy = false
            return
        end

        pcall(function() Gui:Destroy() end)
        print("[AE Tournament] SAFE BOOT -> optimizer loaded and analyzed")
    end)
end)

print("[AE Tournament] SAFE BOOT READY | heavy engine not loaded yet")