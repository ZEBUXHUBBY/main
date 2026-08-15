-- AE Tournament Optimizer V7 BOOT
-- Working V6.1 calculation path + V7 visual layer.
-- One-shot manual analysis only. No background work.

local VERSION = "tournament-boot-v7-20260816"
local ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Strategist/"
local ENV = getgenv and getgenv() or _G
local Players = game:GetService("Players")
local LP = Players.LocalPlayer

for _, key in ipairs({
    "AE_TOURNAMENT_BOOT_V2","AE_TOURNAMENT_BOOT_V3","AE_TOURNAMENT_BOOT_V4","AE_TOURNAMENT_BOOT_V5","AE_TOURNAMENT_BOOT_V6","AE_TOURNAMENT_BOOT_V7",
    "AE_TOURNAMENT_VISUAL_V7","AE_TOURNAMENT_OPTIMIZER","AE_STRATEGIST_RUNTIME","AE_STRATEGIST_OWNED_STATS","AE_STRATEGIST_DASHBOARD","AE_STRATEGIST_VISUAL","AE_STRATEGIST"
}) do
    local x = ENV[key]
    if type(x) == "table" and type(x.Destroy) == "function" then pcall(x.Destroy) end
end

local pg = LP:WaitForChild("PlayerGui")
for _, n in ipairs({
    "AE_Tournament_BootV7","AE_Tournament_BootV6","AE_Tournament_BootV5","AE_Tournament_BootV4","AE_Tournament_BootV3","AE_Tournament_BootV2",
    "AE_Tournament_VisualV7","AE_Tournament_V4","AE_Tournament_Only","AE_Strategist_Standalone","AE_Strategist_DashboardV2"
}) do
    local x = pg:FindFirstChild(n)
    if x then pcall(function() x:Destroy() end) end
end

local gui = Instance.new("ScreenGui")
gui.Name = "AE_Tournament_BootV7"
gui.ResetOnSpawn = false
gui.DisplayOrder = 100030
gui.Parent = pg

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(620,300)
main.Position = UDim2.new(.5,-310,.5,-150)
main.BackgroundColor3 = Color3.fromRGB(13,16,23)
main.BorderSizePixel = 0
main.Parent = gui
Instance.new("UICorner",main).CornerRadius = UDim.new(0,12)
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(95,112,170)
stroke.Transparency = .3
stroke.Parent = main

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(18,12)
title.Size = UDim2.new(1,-72,0,32)
title.Text = "AE • TOURNAMENT OPTIMIZER V7"
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(239,241,247)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = main

local close = Instance.new("TextButton")
close.Position = UDim2.new(1,-51,0,11)
close.Size = UDim2.fromOffset(38,32)
close.Text = "×"
close.Font = Enum.Font.GothamBold
close.TextSize = 18
close.TextColor3 = Color3.new(1,1,1)
close.BackgroundColor3 = Color3.fromRGB(44,51,69)
close.BorderSizePixel = 0
close.Parent = main
Instance.new("UICorner",close).CornerRadius = UDim.new(0,8)

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Position = UDim2.fromOffset(18,58)
status.Size = UDim2.new(1,-36,0,150)
status.Text = "READY • "..VERSION.."\n\nV7 uses the working one-shot Tournament calculation path.\nAfter Analyze, it switches to a visual dashboard using GAME UI ICONS first, then GAME UNIT MODELS as fallback.\nIncludes Best Combat 6 + Farm Variant ROI.\nNo background analyze."
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextWrapped = true
status.TextColor3 = Color3.fromRGB(173,182,205)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.Parent = main

local analyze = Instance.new("TextButton")
analyze.Position = UDim2.fromOffset(18,230)
analyze.Size = UDim2.new(1,-36,0,50)
analyze.Text = "ANALYZE CURRENT TOURNAMENT"
analyze.Font = Enum.Font.GothamBold
analyze.TextSize = 13
analyze.TextColor3 = Color3.new(1,1,1)
analyze.BackgroundColor3 = Color3.fromRGB(67,84,139)
analyze.BorderSizePixel = 0
analyze.Parent = main
Instance.new("UICorner",analyze).CornerRadius = UDim.new(0,9)

close.MouseButton1Click:Connect(function() gui:Destroy() end)

local nonce = tostring(os.time()).."-"..tostring(math.random(100000,999999))
local function fetch(path)
    local ok, src = pcall(function()
        return game:HttpGet(ROOT..path.."?ae_v7="..nonce)
    end)
    if not ok then return nil, tostring(src) end
    return src
end

local function execute(label, src)
    local fn, ce = loadstring(src)
    if not fn then return false, label.." COMPILE ERROR\n"..tostring(ce) end
    local ok, re = pcall(fn)
    if not ok then return false, label.." RUNTIME ERROR\n"..tostring(re) end
    return true
end

local function replacePlain(source, oldText, newText)
    local s, e = string.find(source, oldText, 1, true)
    if not s then return nil end
    return string.sub(source,1,s-1)..newText..string.sub(source,e+1)
end

local function loadCore()
    status.Text = "1/4 • Loading hidden inventory/stage core…"
    local src, err = fetch("main.lua")
    if not src then return false, "CORE FETCH ERROR\n"..err end

    src = src:gsub("tonumber(%b())", function(args)
        if args:sub(1,7) == "(getCI(" then return "tonumber(("..args:sub(2,-2).."))" end
        return "tonumber"..args
    end)
    src = src:gsub("Gui%.Parent = parentGui","Gui.Parent = parentGui\nGui.Enabled = false",1)
    src = src:gsub(
        "task%.spawn%(function%(%)%s*pcall%(runAnalysis%)%s*pcall%(function%(%) discoverPath%(%) end%)%s*end%)",
        "-- Tournament V7 startup analysis disabled",
        1
    )

    local ok, e = execute("CORE",src)
    if not ok then return false,e end
    local c = ENV.AE_STRATEGIST
    if type(c) ~= "table" or type(c.GetState) ~= "function" then return false,"CORE API MISSING" end
    if c.Gui then pcall(function() c.Gui.Enabled=false end) end
    return true
end

local function patchWorkingEngine(src)
    -- Preserve the exact V6.1 calculation path that already produced a 6-slot result.
    src = src:gsub("tonumber(%b())", function(args)
        if args:sub(1,4) == "(ci(" then return "tonumber(("..args:sub(2,-2).."))" end
        return "tonumber"..args
    end)

    local oldLevel = "local lmods=findLevelMods(UnitLevelDB,out.Level)"
    local newLevel = [[local levelRow = UnitLevelDB[out.Level] or UnitLevelDB[tostring(out.Level)]
    if type(levelRow) ~= "table" then
        local shallowLevels = ci(UnitLevelDB,{"Levels","LevelData","UnitLevels","Data","Entries"})
        if type(shallowLevels) == "table" then
            levelRow = shallowLevels[out.Level] or shallowLevels[tostring(out.Level)]
        end
    end
    local lmods = levelModsFromRow(levelRow)]]
    local patched = replacePlain(src,oldLevel,newLevel)
    if not patched then return nil,"V7 PATCH ERROR: level call site not found" end
    src = patched

    local oldDetail = "if #team>0 then renderDetail(team[1],1) end"
    local newDetail = [[if #team > 0 then
        detailTitle.Text = "TEAM READY"
        detailText.Text = "V7 visual dashboard will open next. No Trait/Equipment what-if runs automatically."
    end]]
    patched = replacePlain(src,oldDetail,newDetail)
    if not patched then return nil,"V7 PATCH ERROR: initial detail call not found" end
    return patched
end

local function loadEngine()
    status.Text = "2/4 • Loading working Tournament calculation engine…"
    local src, err = fetch("tournament_v4.lua")
    if not src then return false,"ENGINE FETCH ERROR\n"..err end
    local patched, patchErr = patchWorkingEngine(src)
    if not patched then return false,patchErr end
    local ok, e = execute("TOURNAMENT ENGINE",patched)
    if not ok then return false,e end
    local opt = ENV.AE_TOURNAMENT_OPTIMIZER
    if type(opt) ~= "table" or type(opt.Analyze) ~= "function" then return false,"TOURNAMENT Analyze API missing" end
    return true
end

local function loadVisual()
    status.Text = "4/4 • Opening V7 game-icon dashboard…"
    local src, err = fetch("tournament_visual_v7.lua")
    if not src then return false,"VISUAL FETCH ERROR\n"..err end
    local ok, e = execute("V7 VISUAL",src)
    if not ok then return false,e end
    return true
end

local busy = false
analyze.MouseButton1Click:Connect(function()
    if busy then return end
    busy = true
    analyze.Text = "ANALYZING…"

    task.spawn(function()
        local ok, e = loadCore()
        if not ok then status.Text=e; analyze.Text="RETRY"; busy=false; return end

        ok, e = loadEngine()
        if not ok then status.Text=e; analyze.Text="RETRY"; busy=false; return end

        status.Text = "3/4 • One-shot Tournament snapshot + 6-slot team…"
        local opt = ENV.AE_TOURNAMENT_OPTIMIZER
        local ok2, e2 = pcall(function() opt.Analyze() end)
        if not ok2 then status.Text="ANALYZE ERROR\n"..tostring(e2); analyze.Text="RETRY"; busy=false; return end

        if type(opt.Result) ~= "table" or type(opt.Result.Team) ~= "table" or #opt.Result.Team == 0 then
            status.Text = "ANALYZE ERROR\nCalculation finished but no Tournament team was produced."
            analyze.Text = "RETRY"
            busy = false
            return
        end

        ok, e = loadVisual()
        if not ok then status.Text=e; analyze.Text="RETRY"; busy=false; return end

        pcall(function() gui:Destroy() end)
    end)
end)

ENV.AE_TOURNAMENT_BOOT_V7 = {
    Gui = gui,
    Version = VERSION,
    Destroy = function() if gui then gui:Destroy() end end,
}

print("[AE Tournament V7] BOOT READY | game-icon visual + farm variant")
