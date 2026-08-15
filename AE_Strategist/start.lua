-- AE Strategist single-UI entrypoint.
-- Stable core = data engine only (hidden). OwnedStats enhances real copies.
-- Dashboard V2 is the only visible UI. No AE_Assistant dependency.

local ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Strategist/"
local ENV = getgenv and getgenv() or _G

-- Clean old optional layers from previous executions first.
if type(ENV.AE_STRATEGIST_VISUAL)=="table" and type(ENV.AE_STRATEGIST_VISUAL.Destroy)=="function" then pcall(ENV.AE_STRATEGIST_VISUAL.Destroy) end
if type(ENV.AE_STRATEGIST_DASHBOARD)=="table" and type(ENV.AE_STRATEGIST_DASHBOARD.Destroy)=="function" then pcall(ENV.AE_STRATEGIST_DASHBOARD.Destroy) end

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

-- 1) Stable core.
local coreSource,err=fetch("main.lua")
if not coreSource then warn("[AE Strategist] core fetch failed:",err); return end
coreSource=coreSource:gsub("tonumber(%b())",function(args)
    if args:sub(1,7)=="(getCI(" then return "tonumber(("..args:sub(2,-2).."))" end
    return "tonumber"..args
end)
if not runSource("core",coreSource) then return end
local Core=ENV.AE_STRATEGIST

-- Core is now a hidden data engine. Never show its old window.
if Core and Core.Gui then
    pcall(function() Core.Gui.Enabled=false end)
    local m=Core.Gui:FindFirstChild("Main"); if m then m.Visible=false end
end
print("[AE Strategist] hidden stable core loaded")

-- 2) Owned-copy stat engine: Level / Trait / Equipment / Potential evidence.
local statSource,statErr=fetch("owned_stats.lua")
if statSource then
    if not runSource("owned stats",statSource) then warn("[AE Strategist] owned stats unavailable; dashboard will show lower confidence") end
else
    warn("[AE Strategist] owned stats fetch failed:",statErr)
end

-- Re-run analysis once through the wrapped pipeline.
if Core and type(Core.RefreshAnalysis)=="function" then pcall(Core.RefreshAnalysis) end

-- 3) Dashboard only.
task.spawn(function()
    local dashSource,dashErr=fetch("dashboard_v2.lua")
    if not dashSource then warn("[AE Strategist] dashboard fetch failed:",dashErr); return end

    -- V2 preflight fixes retained from the working build.
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

    -- Current team must use the exact equipped copies created by OwnedStats.
    dashSource=dashSource:gsub(
        "local function currentTeam%(state%)\n    local out=%{%}",
        "local function currentTeam(state)\n    if state and type(state.EffectiveCurrentTeam) == 'table' and #state.EffectiveCurrentTeam > 0 then return state.EffectiveCurrentTeam end\n    local out={}",1)

    -- Make the recommendation heading tell the truth in Tournament.
    dashSource=dashSource:gsub(
        "local function renderTeam%(state%)\n",
        "local function renderTeam(state)\n    RecTitle.Text = state.RecommendationWarning or 'RECOMMENDED OWNED COPIES'\n",1)

    -- Cards: show real copy Level / Trait / Equipment + effective DPS.
    dashSource=dashSource:gsub("f%.Size = UDim2%.fromOffset%(118,136%)","f.Size = UDim2.fromOffset(118,148)",1)
    dashSource=dashSource:gsub(
        "local stat = text%(f,tostring%(p and p%.Element or \"%?\"%)%.%.\"  •  \"%.%.fmt%(dps,0%)%.%.\" DPS\",UDim2%.fromOffset%(6,117%),UDim2%.new%(1,-12,0,14%),false%)",
        "local meta1 = 'Lv'..tostring(p and p.OwnedLevel or '?')..' • '..tostring(p and p.OwnedTrait or 'No Trait')\n    local meta2 = tostring(p and p.EquipmentLabel or 'No Equip')..' • '..fmt(dps,0)..' DPS'\n    local stat = text(f,meta1..'\\n'..meta2,UDim2.fromOffset(6,114),UDim2.new(1,-12,0,29),false)\n    stat.TextWrapped=true",1)

    -- Add stat-confidence summary to the stage line.
    dashSource=dashSource:gsub(
        "StageLabel%.Text=st and %(tostring%(st%.Gamemode%)%.%.\"  •  \"%.%.tostring%(st%.MapName%)%.%.\"  •  \"%.%.tostring%(st%.ActName%)%.%.\"  •  \"%.%.tostring%(st%.Difficulty%)%) or \"stage not detected\"",
        "local fidelity=state.StatFidelity\n    local fidelityText=fidelity and ('  •  stats '..tostring(fidelity.Exact or 0)..' exact / '..tostring(fidelity.Partial or 0)..' partial') or ''\n    StageLabel.Text=(st and (tostring(st.Gamemode)..'  •  '..tostring(st.MapName)..'  •  '..tostring(st.ActName)..'  •  '..tostring(st.Difficulty)) or 'stage not detected')..fidelityText",1)

    if not runSource("dashboard",dashSource) then return end

    -- There must be only one visible UI. Remove CORE button and force old core hidden.
    local D=ENV.AE_STRATEGIST_DASHBOARD
    if Core and Core.Gui then pcall(function() Core.Gui.Enabled=false end) end
    if D and D.Gui then
        for _,x in ipairs(D.Gui:GetDescendants()) do
            if x:IsA("TextButton") and x.Text=="CORE" then x:Destroy() end
        end
    end
    print("[AE Strategist] single Dashboard UI loaded with owned-copy stats")
end)
