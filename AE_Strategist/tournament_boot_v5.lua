-- AE Tournament Optimizer V5 BOOT
-- Fixes V4 owned-copy hang: no recursive UnitLevelInfo traversal per copy.
-- UI first, one-shot manual analysis, no background work.

local VERSION="tournament-boot-v5-20260816"
local ROOT="https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Strategist/"
local ENV=getgenv and getgenv() or _G
local Players=game:GetService("Players")
local LP=Players.LocalPlayer

for _,key in ipairs({"AE_TOURNAMENT_BOOT_V2","AE_TOURNAMENT_BOOT_V3","AE_TOURNAMENT_BOOT_V4","AE_TOURNAMENT_BOOT_V5","AE_TOURNAMENT_OPTIMIZER","AE_STRATEGIST_RUNTIME","AE_STRATEGIST_OWNED_STATS","AE_STRATEGIST_DASHBOARD","AE_STRATEGIST_VISUAL","AE_STRATEGIST"}) do
    local x=ENV[key]
    if type(x)=="table" and type(x.Destroy)=="function" then pcall(x.Destroy) end
end

local pg=LP:WaitForChild("PlayerGui")
for _,n in ipairs({"AE_Tournament_BootV5","AE_Tournament_BootV4","AE_Tournament_BootV3","AE_Tournament_BootV2","AE_Tournament_V4","AE_Tournament_Only","AE_Strategist_Standalone","AE_Strategist_DashboardV2"}) do
    local x=pg:FindFirstChild(n); if x then pcall(function() x:Destroy() end) end
end

local gui=Instance.new("ScreenGui"); gui.Name="AE_Tournament_BootV5"; gui.ResetOnSpawn=false; gui.DisplayOrder=100003; gui.Parent=pg
local main=Instance.new("Frame"); main.Size=UDim2.fromOffset(590,280); main.Position=UDim2.new(.5,-295,.5,-140); main.BackgroundColor3=Color3.fromRGB(13,16,23); main.BorderSizePixel=0; main.Parent=gui
Instance.new("UICorner",main).CornerRadius=UDim.new(0,12)
local stroke=Instance.new("UIStroke"); stroke.Color=Color3.fromRGB(95,112,170); stroke.Transparency=.32; stroke.Parent=main
local title=Instance.new("TextLabel"); title.BackgroundTransparency=1; title.Position=UDim2.fromOffset(18,12); title.Size=UDim2.new(1,-72,0,30); title.Text="AE • TOURNAMENT OPTIMIZER V5"; title.Font=Enum.Font.GothamBold; title.TextSize=17; title.TextColor3=Color3.fromRGB(239,241,247); title.TextXAlignment=Enum.TextXAlignment.Left; title.Parent=main
local close=Instance.new("TextButton"); close.Position=UDim2.new(1,-51,0,11); close.Size=UDim2.fromOffset(38,32); close.Text="×"; close.Font=Enum.Font.GothamBold; close.TextSize=18; close.TextColor3=Color3.new(1,1,1); close.BackgroundColor3=Color3.fromRGB(44,51,69); close.BorderSizePixel=0; close.Parent=main; Instance.new("UICorner",close).CornerRadius=UDim.new(0,8)
local status=Instance.new("TextLabel"); status.BackgroundTransparency=1; status.Position=UDim2.fromOffset(18,55); status.Size=UDim2.new(1,-36,0,125); status.Text="READY • "..VERSION.."\nFast owned-copy build: Level lookup is direct/cached; no recursive UnitLevel scan.\nBoss Waves / Speedy modifiers are read from the current UI.\nNo background analyze."; status.Font=Enum.Font.Gotham; status.TextSize=12; status.TextWrapped=true; status.TextColor3=Color3.fromRGB(173,182,205); status.TextXAlignment=Enum.TextXAlignment.Left; status.TextYAlignment=Enum.TextYAlignment.Top; status.Parent=main
local analyze=Instance.new("TextButton"); analyze.Position=UDim2.fromOffset(18,207); analyze.Size=UDim2.new(1,-36,0,50); analyze.Text="ANALYZE CURRENT TOURNAMENT"; analyze.Font=Enum.Font.GothamBold; analyze.TextSize=13; analyze.TextColor3=Color3.new(1,1,1); analyze.BackgroundColor3=Color3.fromRGB(67,84,139); analyze.BorderSizePixel=0; analyze.Parent=main; Instance.new("UICorner",analyze).CornerRadius=UDim.new(0,9)
close.MouseButton1Click:Connect(function() gui:Destroy() end)

local nonce=tostring(os.time()).."-"..tostring(math.random(100000,999999))
local function fetch(path)
    local ok,src=pcall(function() return game:HttpGet(ROOT..path.."?ae_v5="..nonce) end)
    if not ok then return nil,tostring(src) end
    return src
end
local function execute(label,src)
    local fn,ce=loadstring(src); if not fn then return false,label.." COMPILE ERROR\n"..tostring(ce) end
    local ok,re=pcall(fn); if not ok then return false,label.." RUNTIME ERROR\n"..tostring(re) end
    return true
end

local function loadCore()
    status.Text="1/3 • Loading hidden inventory/stage core…"
    local src,err=fetch("main.lua"); if not src then return false,"CORE FETCH ERROR\n"..err end
    src=src:gsub("tonumber(%b())",function(args) if args:sub(1,7)=="(getCI(" then return "tonumber(("..args:sub(2,-2).."))" end return "tonumber"..args end)
    src=src:gsub("Gui%.Parent = parentGui","Gui.Parent = parentGui\nGui.Enabled = false",1)
    src=src:gsub("task%.spawn%(function%(%)%s*pcall%(runAnalysis%)%s*pcall%(function%(%) discoverPath%(%) end%)%s*end%)","-- Tournament V5 startup analysis disabled",1)
    local ok,e=execute("CORE",src); if not ok then return false,e end
    local c=ENV.AE_STRATEGIST
    if type(c)~="table" or type(c.GetState)~="function" then return false,"CORE API MISSING" end
    if c.Gui then pcall(function() c.Gui.Enabled=false end) end
    return true
end

local function patchV4(src)
    -- Critical performance fix: NEVER recursively walk UnitLevelDB for every copy.
    -- Only accept direct level-indexed rows or one known shallow Levels/LevelData table.
    src=src:gsub(
        "local lmods=findLevelMods%(UnitLevelDB,out%.Level%)",
        "local levelRow=UnitLevelDB[out.Level] or UnitLevelDB[tostring(out.Level)]\n    if type(levelRow)~='table' then\n        local shallowLevels=ci(UnitLevelDB,{'Levels','LevelData','UnitLevels','Data','Entries'})\n        if type(shallowLevels)=='table' then levelRow=shallowLevels[out.Level] or shallowLevels[tostring(out.Level)] end\n    end\n    local lmods=levelModsFromRow(levelRow)",
        1
    )

    -- Build a normalized equipment index once. Avoid full EquipmentDB scan for every copy.
    src=src:gsub(
        "local UnitModels = RS:FindFirstChild%(\"Assets\"%) and RS%.Assets:FindFirstChild%(\"Units\"%)",
        "local UnitModels = RS:FindFirstChild(\"Assets\") and RS.Assets:FindFirstChild(\"Units\")\nlocal EquipmentIndex={}\nfor k,v in pairs(type(EquipmentDB)=='table' and EquipmentDB or {}) do\n    EquipmentIndex[norm(k)]=v\n    if type(v)=='table' then\n        for _,field in ipairs({'Asset','DisplayName','Name'}) do local x=v[field]; if type(x)=='string' then EquipmentIndex[norm(x)]=v end end\n    end\nend",
        1
    )
    src=src:gsub(
        "local function equipmentRow%(id%)%s*if type%(EquipmentDB%)~=\"table\" then return nil end%s*if EquipmentDB%[id%] then return EquipmentDB%[id%] end%s*local nid=norm%(id%)%s*for k,v in pairs%(EquipmentDB%) do%s*if norm%(k%)==nid or %(type%(v%)==\"table\" and %(norm%(v%.Asset%)==nid or norm%(v%.DisplayName%)==nid or norm%(v%.Name%)==nid%)%) then return v,k end%s*end%s*end",
        "local function equipmentRow(id)\n    if type(EquipmentDB)~='table' then return nil end\n    return EquipmentDB[id] or EquipmentIndex[norm(id)]\nend",
        1
    )

    -- Progress + cooperative yield while processing inventory copies.
    src=src:gsub(
        "local function bestCopies%(state%)%s*local byAsset=%{%}%s*for _,r in ipairs%(state%.Scan and state%.Scan%.Owned or %{%}%) do",
        "local function bestCopies(state)\n    local byAsset={}\n    local owned=state.Scan and state.Scan.Owned or {}\n    local processed=0\n    for _,r in ipairs(owned) do\n        processed+=1\n        if processed%10==0 then status.Text='Building owned-copy stats… '..processed..'/'..#owned; task.wait() end",
        1
    )

    -- Do not run lazy trait simulation automatically when first card renders.
    -- renderDetail will show current stats first; a second click can request advice later.
    src=src:gsub(
        "if r and not advice then%s*local t=r%.State and r%.State%.Profiles and r%.State%.Profiles%[c%.Asset%]%s*local rec=c%.Record%s*if t and rec then%s*local fit,high,early=traitAdvice%(t,rec,r%.Threat,r%.Ctx%)%s*advice=%{TraitFit=fit,TraitHigh=high,TraitEarly=early,Equipment=nil,EquipmentCandidates=0%}%s*r%.Advice%[c%.Asset%]=advice%s*end%s*end",
        "-- V5: trait/equipment what-if is not run during initial render",
        1
    )

    return src
end

local function loadV5()
    status.Text="2/3 • Loading cached modifier-aware engine…"
    local src,err=fetch("tournament_v4.lua"); if not src then return false,"V5 ENGINE FETCH ERROR\n"..err end
    src=patchV4(src)
    local ok,e=execute("V5 ENGINE",src); if not ok then return false,e end
    local opt=ENV.AE_TOURNAMENT_OPTIMIZER
    if type(opt)~="table" or type(opt.Analyze)~="function" then return false,"V5 Analyze API missing" end
    return true
end

local busy=false
analyze.MouseButton1Click:Connect(function()
    if busy then return end; busy=true; analyze.Text="LOADING…"
    task.spawn(function()
        local ok,e=loadCore(); if not ok then status.Text=e; analyze.Text="RETRY"; busy=false; return end
        ok,e=loadV5(); if not ok then status.Text=e; analyze.Text="RETRY"; busy=false; return end
        status.Text="3/3 • Scanning owned inventory once…"
        local opt=ENV.AE_TOURNAMENT_OPTIMIZER
        local ok2,e2=pcall(function() opt.Analyze() end)
        if not ok2 then status.Text="ANALYZE ERROR\n"..tostring(e2); analyze.Text="RETRY"; busy=false; return end
        pcall(function() gui:Destroy() end)
    end)
end)

ENV.AE_TOURNAMENT_BOOT_V5={Gui=gui,Version=VERSION,Destroy=function() if gui then gui:Destroy() end end}
print("[AE Tournament V5] BOOT READY | cached owned-copy build")