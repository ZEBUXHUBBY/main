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

-- Kill every previous strategist visual/runtime layer first.
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

-- Tournament source hardening --------------------------------------------------
-- ci() returns (value,key). Protect every tonumber(ci(...)) occurrence.
tour=tour:gsub("tonumber(%b())",function(args)
    if args:sub(1,4)=="(ci(" then return "tonumber(("..args:sub(2,-2).."))" end
    return "tonumber"..args
end)

-- Stat processor probing is expensive. Probe only for the actual currently-owned
-- copy; trait/equipment what-if simulations use explicit modifier tables only.
tour=tour:gsub(
    "local exact,processor=resolveExactStats%(out%.Asset,data,template%.Base%)",
    "local exact,processor=nil,nil\n    if not traitOverride and equipOverride==nil then exact,processor=resolveExactStats(out.Asset,data,template.Base) end",
    1
)

-- When the game processor gives U0 crit stats, preserve upgrade-specific base crit
-- by applying only the processor's delta instead of overwriting every upgrade.
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

-- GAME UNITSTATS may already contain combat stat modifiers, but cost/farm income
-- are separate economics. Preserve explicit Trait/Equipment Cost and Farm effects.
tour=tour:gsub(
    "local placement=tonumber%(out%.PlacementLimit%) or 1",
    "if exact then\n        if tmods and tmods.Cost then costMul=costMul*(1+tmods.Cost) end\n        if tmods and tmods.Farm then farmMul=farmMul*(1+tmods.Farm) end\n        if emods and emods.Cost then costMul=costMul*(1+emods.Cost) end\n        if emods and emods.Farm then farmMul=farmMul*(1+emods.Farm) end\n    end\n    local placement=tonumber(out.PlacementLimit) or 1",
    1
)

if not run("tournament optimizer",tour) then return end
print("[AE Tournament] READY | manual one-shot analysis only")