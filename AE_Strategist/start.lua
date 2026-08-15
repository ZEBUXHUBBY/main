-- AE Strategist | Tournament-only entrypoint
-- Hidden core is used only for one-shot data scans. Tournament UI is the only visible UI.
-- No background analyze, no polling, no AE_Assistant dependency.

local ROOT="https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Strategist/"
local ENV=getgenv and getgenv() or _G
local Players=game:GetService("Players")
local LP=Players.LocalPlayer

local function fetch(path)
    local ok,s=pcall(function() return game:HttpGet(ROOT..path) end)
    if not ok then return nil,s end
    return s
end
local function run(label,src)
    local fn,ce=loadstring(src); if not fn then warn("[AE Tournament] "..label.." compile error:",ce); return false end
    local ok,re=pcall(fn); if not ok then warn("[AE Tournament] "..label.." runtime error:",re); return false end
    return true
end

for _,key in ipairs({"AE_STRATEGIST_VISUAL","AE_STRATEGIST_DASHBOARD","AE_STRATEGIST_RUNTIME","AE_STRATEGIST_OWNED_STATS","AE_TOURNAMENT_OPTIMIZER"}) do
    local x=ENV[key]; if type(x)=="table" and type(x.Destroy)=="function" then pcall(x.Destroy) end
end
local function cleanup(root)
    if not root then return end
    for _,n in ipairs({"AE_Strategist_VisualAddon","AE_Strategist_DashboardV2","AE_Strategist_VisualV2","AE_Tournament_Only","AE_Strategist_Standalone"}) do
        local x=root:FindFirstChild(n); if x then pcall(function() x:Destroy() end) end
    end
end
pcall(function() cleanup(game:GetService("CoreGui")) end)
pcall(function() cleanup(LP:FindFirstChild("PlayerGui")) end)
pcall(function() if gethui then cleanup(gethui()) end end)
if type(ENV.AE_STRATEGIST)=="table" and type(ENV.AE_STRATEGIST.Destroy)=="function" then pcall(ENV.AE_STRATEGIST.Destroy) end

local core,err=fetch("main.lua")
if not core then warn("[AE Tournament] core fetch failed:",err); return end
core=core:gsub("tonumber(%b())",function(args)
    if args:sub(1,7)=="(getCI(" then return "tonumber(("..args:sub(2,-2).."))" end
    return "tonumber"..args
end)
core=core:gsub("Gui%.Parent = parentGui","Gui.Parent = parentGui\nGui.Enabled = false",1)
core=core:gsub(
    "task%.spawn%(function%(%)\n    pcall%(runAnalysis%)\n    pcall%(function%(%) discoverPath%(%) end%)\nend%)",
    "-- startup auto-analysis disabled by Tournament-only loader",
    1
)
if not run("hidden core",core) then return end
local Core=ENV.AE_STRATEGIST
if Core and Core.Gui then pcall(function() Core.Gui.Enabled=false end) end
print("[AE Tournament] hidden core ready | auto analyze disabled")

local tour,tErr=fetch("tournament_only.lua")
if not tour then warn("[AE Tournament] tournament UI fetch failed:",tErr); return end

-- ci() returns (value,key). Collapse to one return before tonumber.
tour=tour:gsub("tonumber(%b())",function(args)
    if args:sub(1,4)=="(ci(" then return "tonumber(("..args:sub(2,-2).."))" end
    return "tonumber"..args
end)

-- Processor probing only on actual owned copies, never on what-if simulations.
tour=tour:gsub(
    "local exact,processor=resolveExactStats%(out%.Asset,data,template%.Base%)",
    "local exact,processor=nil,nil\n    if not traitOverride and equipOverride==nil then exact,processor=resolveExactStats(out.Asset,data,template.Base) end",
    1
)

-- Preserve upgrade-specific critical stats by applying processor delta from U0.
tour=tour:gsub(
    "if exact and exact%.CritChance~=nil and not traitOverride and equipOverride==nil then cc=exact%.CritChance else cc=nativeAdd%(cc,ccAdd,false%) end",
    "if exact and exact.CritChance~=nil and not traitOverride and equipOverride==nil then cc=cc+(exact.CritChance-(template.Base.CritChance or 0)) else cc=nativeAdd(cc,ccAdd,false) end",
    1
)
tour=tour:gsub(
    "if exact and exact%.CritDamage~=nil and not traitOverride and equipOverride==nil then cd=exact%.CritDamage else cd=nativeAdd%(cd,cdAdd,true%) end",
    "if exact and exact.CritDamage~=nil and not traitOverride and equipOverride==nil then cd=cd+(exact.CritDamage-(template.Base.CritDamage or 0)) else cd=nativeAdd(cd,cdAdd,true) end",
    1
)

-- Processor covers combat stats, not necessarily economy fields.
tour=tour:gsub(
    "local placement=tonumber%(out%.PlacementLimit%) or 1",
    "if exact then\n        if tmods and tmods.Cost then costMul=costMul*(1+tmods.Cost) end\n        if tmods and tmods.Farm then farmMul=farmMul*(1+tmods.Farm) end\n        if emods and emods.Cost then costMul=costMul*(1+emods.Cost) end\n        if emods and emods.Farm then farmMul=farmMul*(1+emods.Farm) end\n    end\n    local placement=tonumber(out.PlacementLimit) or 1",
    1
)

-- Manual placement visualization. No path work until SHOW BEST SPOT is pressed.
tour=tour:gsub(
    "local App = %{%s*Version=VERSION, Connections=%{%}, Destroyed=false, Result=nil, Selected=1, ScoreObserved=nil%s*%}",
    "local App = {Version=VERSION, Connections={}, Destroyed=false, Result=nil, Selected=1, ScoreObserved=nil, WorldVisuals={}}",
    1
)
tour=tour:gsub(
    "local detailText=label%(detail,\"Press ANALYZE TOURNAMENT%. Heavy work runs once, then stops%.\",UDim2%.fromOffset%(14,36%),UDim2%.new%(1,-28,1,-46%),false%); detailText%.TextSize=10; detailText%.TextYAlignment=Enum%.TextYAlignment%.Top",
    "local detailText=label(detail,\"Press ANALYZE TOURNAMENT. Heavy work runs once, then stops.\",UDim2.fromOffset(14,36),UDim2.new(1,-28,1,-88),false); detailText.TextSize=10; detailText.TextYAlignment=Enum.TextYAlignment.Top\nlocal SpotButton=btn(detail,\"SHOW BEST SPOT\",UDim2.new(1,-160,1,-42),UDim2.fromOffset(146,30),function() task.spawn(function() if App.ShowSpot then App.ShowSpot() end end) end)",
    1
)

tour=tour:gsub(
    "%-%- Optional ultra%-light score observer:",
    [[local function clearWorldVisuals()
    for _,v in ipairs(App.WorldVisuals or {}) do pcall(function() v:Destroy() end) end
    App.WorldVisuals={}
end
function App.ShowSpot()
    clearWorldVisuals()
    local result=App.Result
    local c=result and result.Team and result.Team[App.Selected]
    if not c then detailText.Text=detailText.Text.."\n\nPLACEMENT: analyze and select a unit first."; return end
    local state=Core.GetState()
    if not state or not state.Profiles or type(Core.GetPlacementCandidates)~="function" then detailText.Text=detailText.Text.."\n\nPLACEMENT: core placement helper unavailable."; return end
    local old=state.Profiles[c.Asset]
    state.Profiles[c.Asset]=c
    local level=(c.Final and c.Final.Level) or (c.Base and c.Base.Level) or 0
    local ok,cands=pcall(Core.GetPlacementCandidates,c.Asset,level)
    state.Profiles[c.Asset]=old
    if not ok or type(cands)~="table" or #cands==0 then
        detailText.Text=detailText.Text.."\n\nPLACEMENT: no validated match path/ground candidate. Enter the Tournament match and press SHOW BEST SPOT again."
        return
    end
    local lines={"","BEST MATCH SPOTS (manual scan):"}
    for i=1,math.min(3,#cands) do
        local x=cands[i]; local pos=x.Position; local range=(c.Final and c.Final.Range) or (c.Base and c.Base.Range) or 10
        lines[#lines+1]=string.format("#%d  cover %s studs  @ %.1f, %.1f, %.1f",i,fmt(x.Covered or x.Coverage,1),pos.X,pos.Y,pos.Z)
        local ring=Instance.new("Part"); ring.Name="AE_TournamentSpot"..i; ring.Shape=Enum.PartType.Cylinder; ring.Anchored=true; ring.CanCollide=false; ring.CanQuery=false; ring.Material=Enum.Material.Neon; ring.Transparency=i==1 and .70 or .84; ring.Color=i==1 and Color3.fromRGB(91,255,167) or Color3.fromRGB(116,143,225); ring.Size=Vector3.new(.14,range*2,range*2); ring.CFrame=CFrame.new(pos+Vector3.new(0,.08,0))*CFrame.Angles(0,0,math.rad(90)); ring.Parent=WS; App.WorldVisuals[#App.WorldVisuals+1]=ring
        local beam=Instance.new("Part"); beam.Anchored=true; beam.CanCollide=false; beam.CanQuery=false; beam.Material=Enum.Material.Neon; beam.Transparency=i==1 and .15 or .5; beam.Color=ring.Color; beam.Size=Vector3.new(.35,5,.35); beam.Position=pos+Vector3.new(0,2.5,0); beam.Parent=WS; App.WorldVisuals[#App.WorldVisuals+1]=beam
    end
    detailText.Text=detailText.Text..table.concat(lines,"\n")
end

-- Optional ultra-light score observer:]],
    1
)

tour=tour:gsub(
    "function App%.Destroy%(%)\n    if App%.Destroyed then return end; App%.Destroyed=true",
    "function App.Destroy()\n    if App.Destroyed then return end; App.Destroyed=true\n    clearWorldVisuals()",
    1
)

if not run("tournament optimizer",tour) then return end
print("[AE Tournament] READY | manual one-shot analysis + manual placement")