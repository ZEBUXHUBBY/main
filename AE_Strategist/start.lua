-- AE Strategist single-UI entrypoint.
-- Stable core = hidden data engine. OwnedStats = real-copy stats. Dashboard = only visible UI.
-- Runtime data is event-driven: no recurring getgc/live scans.
-- No AE_Assistant dependency.

local ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Strategist/"
local ENV = getgenv and getgenv() or _G
local Players=game:GetService("Players")
local LP=Players.LocalPlayer

local function fetch(path)
    local ok,source=pcall(function() return game:HttpGet(ROOT..path) end)
    if not ok then return nil,source end
    return source
end
local function runSource(label,source)
    local chunk,ce=loadstring(source)
    if not chunk then warn("[AE Strategist] "..label.." compile error:",ce); return false end
    local ok,re=pcall(chunk)
    if not ok then warn("[AE Strategist] "..label.." runtime error:",re); return false end
    return true
end

if type(ENV.AE_STRATEGIST_VISUAL)=="table" and type(ENV.AE_STRATEGIST_VISUAL.Destroy)=="function" then pcall(ENV.AE_STRATEGIST_VISUAL.Destroy) end
if type(ENV.AE_STRATEGIST_DASHBOARD)=="table" and type(ENV.AE_STRATEGIST_DASHBOARD.Destroy)=="function" then pcall(ENV.AE_STRATEGIST_DASHBOARD.Destroy) end
if type(ENV.AE_STRATEGIST_RUNTIME)=="table" and type(ENV.AE_STRATEGIST_RUNTIME.Destroy)=="function" then pcall(ENV.AE_STRATEGIST_RUNTIME.Destroy) end
local function cleanupGui(root)
    if not root then return end
    for _,name in ipairs({"AE_Strategist_VisualAddon","AE_Strategist_DashboardV2","AE_Strategist_VisualV2"}) do
        local x=root:FindFirstChild(name); if x then pcall(function() x:Destroy() end) end
    end
end
pcall(function() cleanupGui(game:GetService("CoreGui")) end)
pcall(function() cleanupGui(LP:FindFirstChild("PlayerGui")) end)
pcall(function() if gethui then cleanupGui(gethui()) end end)

-- 1) Stable core, hidden before first render.
local coreSource,err=fetch("main.lua")
if not coreSource then warn("[AE Strategist] core fetch failed:",err); return end
coreSource=coreSource:gsub("tonumber(%b())",function(args)
    if args:sub(1,7)=="(getCI(" then return "tonumber(("..args:sub(2,-2).."))" end
    return "tonumber"..args
end)
coreSource=coreSource:gsub("Gui%.Parent = parentGui","Gui.Parent = parentGui\nGui.Enabled = false",1)
if not runSource("core",coreSource) then return end
local Core=ENV.AE_STRATEGIST
if Core and Core.Gui then
    pcall(function() Core.Gui.Enabled=false end)
    local m=Core.Gui:FindFirstChild("Main"); if m then m.Visible=false end
end
print("[AE Strategist] hidden stable core loaded")

-- 2) Owned-copy stat engine.
local statSource,statErr=fetch("owned_stats.lua")
if statSource then
    statSource=statSource:gsub("tonumber(%b())",function(args)
        if args:sub(1,4)=="(ci(" then return "tonumber(("..args:sub(2,-2).."))" end
        return "tonumber"..args
    end)
    statSource=statSource:gsub(
        "if exact and exact%.CritChance~=nil then cc=exact%.CritChance else cc=cc%+ccAdd end",
        "if exact and exact.CritChance~=nil then cc=exact.CritChance else cc=cc+((cc>1) and ccAdd*100 or ccAdd) end",1)
    statSource=statSource:gsub(
        "if exact and exact%.CritDamage~=nil then cd=exact%.CritDamage else cd=cd%+cdAdd end",
        "if exact and exact.CritDamage~=nil then cd=exact.CritDamage else cd=cd+((cd>5) and cdAdd*100 or cdAdd) end",1)
    if not runSource("owned stats",statSource) then warn("[AE Strategist] owned stats unavailable; lower-confidence fallback only") end
else
    warn("[AE Strategist] owned stats fetch failed:",statErr)
end
if Core and type(Core.RefreshAnalysis)=="function" then pcall(Core.RefreshAnalysis) end

-- 3) Event-driven runtime cache. Passive OnClientEvent/Changed listeners only.
local bridgeSource,bridgeErr=fetch("runtime_bridge.lua")
if bridgeSource then
    if not runSource("runtime bridge",bridgeSource) then
        warn("[AE Strategist] runtime bridge failed; manual live refresh still available")
    end
else
    warn("[AE Strategist] runtime bridge fetch failed:",bridgeErr)
end

-- 4) Dashboard only.
task.spawn(function()
    local dashSource,dashErr=fetch("dashboard_v2.lua")
    if not dashSource then warn("[AE Strategist] dashboard fetch failed:",dashErr); return end

    -- No background heavy work. Economy learner is OFF by default.
    dashSource=dashSource:gsub("Running = true,","Running = false,",1)
    dashSource=dashSource:gsub('local LearnButton=button%(EconStatus,"AUTO: ON"','local LearnButton=button(EconStatus,"AUTO: OFF"',1)
    dashSource=dashSource:gsub(
        "    pcall%(function%(%) Dashboard%.Sync%(false%) end%)\n    Dashboard%.StartTracker%(%)",
        "    pcall(function() Dashboard.Sync(false) end)",1)

    -- If AUTO learner is manually enabled, read the event cache instead of Core.RefreshLive/getgc.
    dashSource=dashSource:gsub(
        "function Dashboard%.TrackerTick%(%)\n    if Dashboard%.Destroyed or not Dashboard%.Tracker%.Running then return end\n    pcall%(Core%.RefreshLive%)\n    local state=Core%.GetState%(%)\n    local live=state and state%.LastLive",
        "function Dashboard.TrackerTick()\n    if Dashboard.Destroyed or not Dashboard.Tracker.Running then return end\n    local state=Core.GetState()\n    local bridge=ENV.AE_STRATEGIST_RUNTIME\n    local snap=bridge and bridge.GetSnapshot and bridge.GetSnapshot() or nil\n    state.LastLive=state.LastLive or {}\n    if snap then\n        if snap.Yen~=nil then state.LastLive.Yen=snap.Yen end\n        if snap.Wave~=nil then state.LastLive.Wave=snap.Wave end\n    end\n    local live=state and state.LastLive",1)

    -- Learner may sample cache frequently because this is now cheap, but it must NOT rebuild the UI.
    dashSource=dashSource:gsub("task%.wait%(2%.0%)","task.wait(1.0)",1)
    dashSource=dashSource:gsub("    pcall%(Dashboard%.Refresh%)\nend\n\nfunction Dashboard%.StartTracker", "end\n\nfunction Dashboard.StartTracker",1)

    -- Every manual dashboard refresh imports the latest event cache without scanning the client.
    dashSource=dashSource:gsub(
        "function Dashboard%.Refresh%(%)\n    if Dashboard%.Destroyed then return end\n    local state=Core%.GetState%(%)",
        "function Dashboard.Refresh()\n    if Dashboard.Destroyed then return end\n    local state=Core.GetState()\n    local bridge=ENV.AE_STRATEGIST_RUNTIME\n    local snap=bridge and bridge.GetSnapshot and bridge.GetSnapshot() or nil\n    state.LastLive=state.LastLive or {}\n    if snap then\n        if snap.Yen~=nil then state.LastLive.Yen=snap.Yen end\n        if snap.Wave~=nil then state.LastLive.Wave=snap.Wave end\n    end",1)

    dashSource=dashSource:gsub("local LearnButton=button%(","local LearnButton\nLearnButton=button(",1)
    dashSource=dashSource:gsub(
        "for i,obj in ipairs%(objectives%) do\n    local b = button%(TeamPage,obj,",
        "for i,obj in ipairs(objectives) do\n    local objective = obj\n    local b = button(TeamPage,objective,",1)
    dashSource=dashSource:gsub("        st%.Strategy = obj","        st.Strategy = objective",1)
    dashSource=dashSource:gsub("    objectiveButtons%[obj%] = b","    objectiveButtons[objective] = b",1)
    dashSource=dashSource:gsub("local autoBudget=stageTotal or learned or starting","local autoBudget=stageTotal or learned",1)
    dashSource=dashSource:gsub(
        "    rebuildViewports%(state%)\n    renderTeam%(state%)",
        "    if not Dashboard.LastViewportScan or os.clock() - Dashboard.LastViewportScan > 10 then\n        rebuildViewports(state)\n        Dashboard.LastViewportScan = os.clock()\n    end\n    renderTeam(state)",1)

    dashSource=dashSource:gsub(
        "local function currentTeam%(state%)\n    local out=%{%}",
        "local function currentTeam(state)\n    if state and type(state.EffectiveCurrentTeam) == 'table' and #state.EffectiveCurrentTeam > 0 then return state.EffectiveCurrentTeam end\n    local out={}",1)

    dashSource=dashSource:gsub(
        "local function renderTeam%(state%)\n",
        "local function renderTeam(state)\n    RecTitle.Text = state.RecommendationWarning or 'RECOMMENDED OWNED COPIES'\n",1)

    dashSource=dashSource:gsub("f%.Size = UDim2%.fromOffset%(118,136%)","f.Size = UDim2.fromOffset(118,148)",1)
    dashSource=dashSource:gsub(
        "local stat = text%(f,tostring%(p and p%.Element or \"%?\"%)%.%.\"  •  \"%.%.fmt%(dps,0%)%.%.\" DPS\",UDim2%.fromOffset%(6,117%),UDim2%.new%(1,-12,0,14%),false%)",
        "local meta1='Lv'..tostring(p and p.OwnedLevel or '?')..' • '..tostring(p and p.OwnedTrait or 'No Trait')\n    local meta2=tostring(p and p.EquipmentLabel or 'No Equip')..' • '..fmt(dps,0)..' DPS'\n    local stat=text(f,meta1..'\\n'..meta2,UDim2.fromOffset(6,113),UDim2.new(1,-12,0,31),false)\n    stat.TextWrapped=true",1)

    dashSource=dashSource:gsub(
        "StageLabel%.Text=st and %(tostring%(st%.Gamemode%)%.%.\"  •  \"%.%.tostring%(st%.MapName%)%.%.\"  •  \"%.%.tostring%(st%.ActName%)%.%.\"  •  \"%.%.tostring%(st%.Difficulty%)%) or \"stage not detected\"",
        "local fidelity=state.StatFidelity\n    local fidelityText=fidelity and ('  •  stats '..tostring(fidelity.Exact or 0)..' exact / '..tostring(fidelity.Partial or 0)..' partial') or ''\n    StageLabel.Text=(st and (tostring(st.Gamemode)..'  •  '..tostring(st.MapName)..'  •  '..tostring(st.ActName)..'  •  '..tostring(st.Difficulty)) or 'stage not detected')..fidelityText",1)

    if not runSource("dashboard",dashSource) then return end
    local D=ENV.AE_STRATEGIST_DASHBOARD
    if D and D.Tracker then
        D.Tracker.Running=false
        D.Tracker.Token=(D.Tracker.Token or 0)+1
    end
    if Core and Core.Gui then pcall(function() Core.Gui.Enabled=false end) end
    if D and D.Gui then for _,x in ipairs(D.Gui:GetDescendants()) do if x:IsA("TextButton") and x.Text=="CORE" then x:Destroy() end end end
    print("[AE Strategist] single Dashboard UI loaded | event-driven runtime cache | no polling")
end)
