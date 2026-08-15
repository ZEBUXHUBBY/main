-- AE Tournament Optimizer V3 BOOT
-- UI first. One-shot manual analysis. No polling/background analyze.
-- V3 disables expensive UnitStats probing during team build and defers what-if advice.

local VERSION = "tournament-boot-v3-20260816"
local ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Strategist/"
local ENV = getgenv and getgenv() or _G
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local LP = Players.LocalPlayer

for _, key in ipairs({
    "AE_STRATEGIST_VISUAL","AE_STRATEGIST_DASHBOARD","AE_STRATEGIST_RUNTIME",
    "AE_STRATEGIST_OWNED_STATS","AE_TOURNAMENT_OPTIMIZER","AE_STRATEGIST",
    "AE_TOURNAMENT_BOOT_V2","AE_TOURNAMENT_BOOT_V3"
}) do
    local obj = ENV[key]
    if type(obj) == "table" and type(obj.Destroy) == "function" then pcall(obj.Destroy) end
end

local pg = LP:WaitForChild("PlayerGui")
local parentGui = pg
local function destroyNamed(root,name)
    if not root then return end
    local x=root:FindFirstChild(name)
    if x then pcall(function() x:Destroy() end) end
end
for _,name in ipairs({
    "AE_Tournament_BootV3","AE_Tournament_BootV2","AE_Tournament_Boot","AE_Tournament_Only",
    "AE_Strategist_Standalone","AE_Strategist_DashboardV2","AE_Strategist_VisualAddon","AE_Strategist_VisualV2"
}) do
    destroyNamed(pg,name)
    pcall(function() destroyNamed(CoreGui,name) end)
    pcall(function() if gethui then destroyNamed(gethui(),name) end end)
end

local Gui=Instance.new("ScreenGui")
Gui.Name="AE_Tournament_BootV3"
Gui.ResetOnSpawn=false
Gui.DisplayOrder=100000
Gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
Gui.Parent=parentGui

local Main=Instance.new("Frame")
Main.Size=UDim2.fromOffset(570,260)
Main.Position=UDim2.new(.5,-285,.5,-130)
Main.BackgroundColor3=Color3.fromRGB(13,16,23)
Main.BorderSizePixel=0
Main.ZIndex=100
Main.Parent=Gui
Instance.new("UICorner",Main).CornerRadius=UDim.new(0,12)
local stroke=Instance.new("UIStroke")
stroke.Thickness=1; stroke.Transparency=.32; stroke.Color=Color3.fromRGB(94,112,169); stroke.Parent=Main

local Title=Instance.new("TextLabel")
Title.BackgroundTransparency=1
Title.Position=UDim2.fromOffset(18,12)
Title.Size=UDim2.new(1,-72,0,30)
Title.Font=Enum.Font.GothamBold
Title.TextSize=17
Title.TextColor3=Color3.fromRGB(239,241,247)
Title.TextXAlignment=Enum.TextXAlignment.Left
Title.Text="AE • TOURNAMENT OPTIMIZER V3"
Title.ZIndex=101
Title.Parent=Main

local Close=Instance.new("TextButton")
Close.Position=UDim2.new(1,-51,0,11)
Close.Size=UDim2.fromOffset(38,32)
Close.BackgroundColor3=Color3.fromRGB(44,51,69)
Close.BorderSizePixel=0
Close.Text="×"
Close.TextColor3=Color3.new(1,1,1)
Close.Font=Enum.Font.GothamBold
Close.TextSize=18
Close.ZIndex=101
Close.Parent=Main
Instance.new("UICorner",Close).CornerRadius=UDim.new(0,8)

local Status=Instance.new("TextLabel")
Status.BackgroundTransparency=1
Status.Position=UDim2.fromOffset(18,55)
Status.Size=UDim2.new(1,-36,0,102)
Status.Font=Enum.Font.Gotham
Status.TextSize=12
Status.TextWrapped=true
Status.TextColor3=Color3.fromRGB(173,182,205)
Status.TextXAlignment=Enum.TextXAlignment.Left
Status.TextYAlignment=Enum.TextYAlignment.Top
Status.Text="READY • "..VERSION.."\nFast mode: no UnitStats function probing. No background work.\nPress ANALYZE once to build the Tournament combat team."
Status.ZIndex=101
Status.Parent=Main

local Analyze=Instance.new("TextButton")
Analyze.Position=UDim2.fromOffset(18,185)
Analyze.Size=UDim2.new(1,-36,0,52)
Analyze.BackgroundColor3=Color3.fromRGB(67,84,139)
Analyze.BorderSizePixel=0
Analyze.Text="ANALYZE TOURNAMENT"
Analyze.TextColor3=Color3.new(1,1,1)
Analyze.Font=Enum.Font.GothamBold
Analyze.TextSize=13
Analyze.ZIndex=101
Analyze.Parent=Main
Instance.new("UICorner",Analyze).CornerRadius=UDim.new(0,9)
Close.MouseButton1Click:Connect(function() Gui:Destroy() end)

local nonce=tostring(os.time()).."-"..tostring(math.random(100000,999999))
local function fetch(path)
    local ok,src=pcall(function() return game:HttpGet(ROOT..path.."?ae_tournament_v3="..nonce) end)
    if not ok then return nil,tostring(src) end
    return src
end
local function execute(label,src)
    local fn,ce=loadstring(src)
    if not fn then return false,label.." COMPILE ERROR\n"..tostring(ce) end
    local ok,re=pcall(fn)
    if not ok then return false,label.." RUNTIME ERROR\n"..tostring(re) end
    return true
end

local function loadCore()
    Status.Text="1/3 • Loading hidden inventory core…"
    local src,err=fetch("main.lua")
    if not src then return false,"CORE FETCH ERROR\n"..tostring(err) end
    src=src:gsub("tonumber(%b())",function(args)
        if args:sub(1,7)=="(getCI(" then return "tonumber(("..args:sub(2,-2).."))" end
        return "tonumber"..args
    end)
    src=src:gsub("Gui%.Parent = parentGui","Gui.Parent = parentGui\nGui.Enabled = false",1)
    src=src:gsub("task%.spawn%(function%(%)%s*pcall%(runAnalysis%)%s*pcall%(function%(%) discoverPath%(%) end%)%s*end%)","-- Tournament V3 startup analysis disabled",1)
    local ok,e=execute("CORE",src)
    if not ok then return false,e end
    local core=ENV.AE_STRATEGIST
    if type(core)~="table" or type(core.GetState)~="function" then return false,"CORE LOADED BUT API MISSING" end
    if core.Gui then pcall(function() core.Gui.Enabled=false end) end
    return true
end

local function patchTournament(src)
    -- ci() multi-return guard.
    src=src:gsub("tonumber(%b())",function(args)
        if args:sub(1,4)=="(ci(" then return "tonumber(("..args:sub(2,-2).."))" end
        return "tonumber"..args
    end)

    -- IMPORTANT: completely remove automatic UnitStats processor discovery/probing.
    -- The old probe tried many unknown signatures for every owned copy and could hang.
    src=src:gsub(
        "local ProcessorModules=%{%}%s*for _,d in ipairs%(RS:GetDescendants%(%)%) do.-end%s*local ResolvedProcessor=nil",
        "local ProcessorModules={}\nlocal ResolvedProcessor=nil",
        1
    )
    -- Force exact processor path off even if a cached processor somehow exists.
    src=src:gsub(
        "local exact,processor=resolveExactStats%(out%.Asset,data,template%.Base%)",
        "local exact,processor=nil,nil",
        1
    )

    -- Do NOT calculate all trait/equipment what-if advice before showing the team.
    src=src:gsub(
        "local team=chooseTournamentTeam%(best,size,threat%); local advice=%{%}%s*for _,c in ipairs%(team%) do.-end%s*local exact,partial,base=0,0,0",
        "local team=chooseTournamentTeam(best,size,threat); local advice={}\n    status.Text='RANKING COMPLETE • rendering team…'\n    task.wait()\n    local exact,partial,base=0,0,0",
        1
    )

    -- Lazy advice: calculate only for the card the user selects.
    src=src:gsub(
        "App%.Selected=index; local r=App%.Result; local advice=r and r%.Advice and r%.Advice%[c%.Asset%]",
        "App.Selected=index; local r=App.Result; local advice=r and r.Advice and r.Advice[c.Asset]\n    if r and not advice then\n        local t=r.State and r.State.Profiles and r.State.Profiles[c.Asset]\n        local rec=c.Record\n        if t and rec then\n            local high,early=traitAdvice(t,rec)\n            advice={TraitHigh=high,TraitEarly=early,Equipment=nil,EquipmentCandidates=0}\n            r.Advice[c.Asset]=advice\n        end\n    end",
        1
    )

    -- Make status text explicitly identify FAST deterministic mode.
    src=src:gsub(
        "status%.Text=mode%.%.\" • \"%.%.map%.%.\" • Tournament WaveScaling field \"%.%.tostring%(TournamentScaling%.WaveScaling and TournamentScaling%.WaveScaling%[\"1\"%] or \"%?\"%)%.%.\" • no background work\"",
        "status.Text=mode..' • '..map..' • FAST STAT MODE • no UnitStats probing • no background work'",
        1
    )
    return src
end

local function loadTournament()
    Status.Text="2/3 • Loading fast Tournament calculator…"
    local src,err=fetch("tournament_only.lua")
    if not src then return false,"TOURNAMENT FETCH ERROR\n"..tostring(err) end
    src=patchTournament(src)
    local ok,e=execute("TOURNAMENT",src)
    if not ok then return false,e end
    local opt=ENV.AE_TOURNAMENT_OPTIMIZER
    if type(opt)~="table" or type(opt.Analyze)~="function" then return false,"TOURNAMENT LOADED BUT Analyze API MISSING" end
    return true
end

local busy=false
Analyze.MouseButton1Click:Connect(function()
    if busy then return end
    busy=true
    Analyze.Text="LOADING…"
    task.spawn(function()
        local ok,e=loadCore()
        if not ok then Status.Text=e; Analyze.Text="RETRY"; busy=false; return end
        ok,e=loadTournament()
        if not ok then Status.Text=e; Analyze.Text="RETRY"; busy=false; return end
        Status.Text="3/3 • Scanning owned inventory once…"
        local opt=ENV.AE_TOURNAMENT_OPTIMIZER
        local ok2,e2=pcall(function() opt.Analyze() end)
        if not ok2 then Status.Text="ANALYZE ERROR\n"..tostring(e2); Analyze.Text="RETRY"; busy=false; return end
        pcall(function() Gui:Destroy() end)
    end)
end)

ENV.AE_TOURNAMENT_BOOT_V3={Gui=Gui,Version=VERSION,Destroy=function() if Gui then Gui:Destroy() end end}
print("[AE Tournament V3] BOOT READY | fast deterministic mode | no UnitStats probing")