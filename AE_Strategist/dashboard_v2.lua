--[[
AE STRATEGIST | DASHBOARD V2
---------------------------
Safe visual layer over the known-working standalone core.
- Does not replace or modify core scanners.
- Hides the core window by default, but core remains alive.
- Team-first visual dashboard.
- Economy cards + Farm ROI from exact DB Income fields when present.
- Runtime economy learner records positive Yen inflow per wave/stage.
- No gameplay remotes are fired.
]]

local VERSION = "dashboard-v2.0"
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local HS = game:GetService("HttpService")
local WS = game:GetService("Workspace")
local LP = Players.LocalPlayer
local ENV = getgenv and getgenv() or _G
local Core = ENV.AE_STRATEGIST

if type(Core) ~= "table" or type(Core.GetState) ~= "function" then
    warn("[AE Dashboard] core missing")
    return
end

if type(ENV.AE_STRATEGIST_DASHBOARD) == "table" and type(ENV.AE_STRATEGIST_DASHBOARD.Destroy) == "function" then
    pcall(ENV.AE_STRATEGIST_DASHBOARD.Destroy)
end

local Dashboard = {
    Version = VERSION,
    Connections = {},
    Destroyed = false,
    Viewports = {},
    Tracker = {
        Running = true,
        Token = 0,
        PrevYen = nil,
        PrevWave = nil,
        StageKey = nil,
        RunPositive = 0,
        WavePositive = {},
        LastDelta = 0,
    },
}
ENV.AE_STRATEGIST_DASHBOARD = Dashboard
Core.Dashboard = Dashboard

local function norm(v)
    return tostring(v or ""):lower():gsub("[^%w]", "")
end

local function fmt(v, d)
    v = tonumber(v)
    if not v then return "—" end
    d = d or 0
    local a = math.abs(v)
    if a >= 1e9 then return string.format("%.2fB", v / 1e9) end
    if a >= 1e6 then return string.format("%.2fM", v / 1e6) end
    if a >= 1e3 then return string.format("%.2fK", v / 1e3) end
    local s = string.format("%." .. tostring(d) .. "f", v)
    return s:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
end

local function setCount(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function round(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = obj
    return c
end

local function text(parent, value, pos, size, bold, align)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Position = pos or UDim2.new()
    l.Size = size or UDim2.new(1,0,0,20)
    l.Text = value or ""
    l.TextColor3 = Color3.fromRGB(232,235,243)
    l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextSize = 12
    l.TextXAlignment = align or Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Parent = parent
    return l
end

local function button(parent, value, pos, size, callback)
    local b = Instance.new("TextButton")
    b.Position = pos
    b.Size = size
    b.BackgroundColor3 = Color3.fromRGB(54,65,98)
    b.BorderSizePixel = 0
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.Text = value
    b.Parent = parent
    round(b,7)
    local con = b.MouseButton1Click:Connect(callback)
    Dashboard.Connections[#Dashboard.Connections + 1] = con
    return b
end

local function panel(parent, pos, size)
    local f = Instance.new("Frame")
    f.Position = pos
    f.Size = size
    f.BackgroundColor3 = Color3.fromRGB(22,26,36)
    f.BorderSizePixel = 0
    f.Parent = parent
    round(f,9)
    return f
end

local parentGui
pcall(function() if gethui then parentGui = gethui() end end)
parentGui = parentGui or game:GetService("CoreGui") or LP:WaitForChild("PlayerGui")

local old = parentGui:FindFirstChild("AE_Strategist_DashboardV2")
if old then old:Destroy() end

local Gui = Instance.new("ScreenGui")
Gui.Name = "AE_Strategist_DashboardV2"
Gui.ResetOnSpawn = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = parentGui
Dashboard.Gui = Gui

local CoreMain = Core.Gui and Core.Gui:FindFirstChild("Main")
if CoreMain then CoreMain.Visible = false end

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(930,620)
Main.Position = UDim2.new(.5,-465,.5,-310)
Main.BackgroundColor3 = Color3.fromRGB(14,17,24)
Main.BorderSizePixel = 0
Main.Parent = Gui
round(Main,12)

local Top = Instance.new("Frame")
Top.Size = UDim2.new(1,0,0,52)
Top.BackgroundColor3 = Color3.fromRGB(23,27,38)
Top.BorderSizePixel = 0
Top.Parent = Main
round(Top,12)

local Title = text(Top,"AE Strategist",UDim2.fromOffset(16,0),UDim2.fromOffset(160,52),true)
Title.TextSize = 15
local StageLabel = text(Top,"waiting for core…",UDim2.fromOffset(180,0),UDim2.fromOffset(400,52),false)
StageLabel.TextSize = 11
StageLabel.TextColor3 = Color3.fromRGB(158,168,194)

local CoreButton
CoreButton = button(Top,"CORE",UDim2.new(1,-196,0,11),UDim2.fromOffset(58,30),function()
    if CoreMain then CoreMain.Visible = not CoreMain.Visible end
end)
local SyncButton
SyncButton = button(Top,"SYNC",UDim2.new(1,-132,0,11),UDim2.fromOffset(62,30),function()
    task.spawn(function() Dashboard.Sync(true) end)
end)
button(Top,"×",UDim2.new(1,-62,0,11),UDim2.fromOffset(46,30),function() Dashboard.Destroy() end).TextSize = 18

local Nav = Instance.new("Frame")
Nav.Position = UDim2.fromOffset(16,64)
Nav.Size = UDim2.new(1,-32,0,36)
Nav.BackgroundTransparency = 1
Nav.Parent = Main

local Pages = {}
local NavButtons = {}
local pageNames = {"TEAM","ECONOMY","LIVE"}
local function showPage(name)
    for n,p in pairs(Pages) do p.Visible = (n == name) end
    for n,b in pairs(NavButtons) do
        b.BackgroundColor3 = n == name and Color3.fromRGB(67,83,132) or Color3.fromRGB(29,34,47)
    end
end

for i,name in ipairs(pageNames) do
    local b = button(Nav,name,UDim2.fromOffset((i-1)*112,0),UDim2.fromOffset(104,32),function() showPage(name) end)
    b.BackgroundColor3 = Color3.fromRGB(29,34,47)
    NavButtons[name] = b
    local p = Instance.new("Frame")
    p.Position = UDim2.fromOffset(16,106)
    p.Size = UDim2.new(1,-32,1,-122)
    p.BackgroundTransparency = 1
    p.Visible = false
    p.Parent = Main
    Pages[name] = p
end

-- -----------------------------------------------------------------------------
-- Viewport resolver
-- -----------------------------------------------------------------------------
local function nearbyText(vf)
    local node = vf
    for _ = 1,5 do
        node = node and node.Parent
        if not node then break end
        local words = {}
        for _,d in ipairs(node:GetDescendants()) do
            if d:IsA("TextLabel") and d.Visible and d.Text ~= "" and #d.Text < 70 then
                words[#words+1] = d.Text
                if #words >= 10 then break end
            end
        end
        if #words > 0 then return norm(table.concat(words," ")) end
    end
    return ""
end

local function viewportAsset(vf, profiles)
    local aliases = {}
    for asset,p in pairs(profiles or {}) do
        aliases[norm(asset)] = asset
        if p and p.DisplayName then aliases[norm(p.DisplayName)] = asset end
    end
    for _,d in ipairs(vf:GetDescendants()) do
        local a = aliases[norm(d.Name)]
        if a then return a end
    end
    local node = vf
    for _ = 1,6 do
        if not node then break end
        for _,k in ipairs({"Asset","Unit","UnitName","UnitAsset"}) do
            local v = node:GetAttribute(k)
            local a = v and aliases[norm(v)]
            if a then return a end
        end
        node = node.Parent
    end
    local words = nearbyText(vf)
    for alias,asset in pairs(aliases) do
        if #alias >= 4 and words:find(alias,1,true) then return asset end
    end
end

local function rebuildViewports(state)
    Dashboard.Viewports = {}
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return 0 end
    local total = 0
    for _,d in ipairs(pg:GetDescendants()) do
        if d:IsA("ViewportFrame") then
            total = total + 1
            local asset = viewportAsset(d,state.Profiles or {})
            if asset and not Dashboard.Viewports[asset] then Dashboard.Viewports[asset] = d end
        end
    end
    -- hotbar positional fallback
    local camera = WS.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1920,1080)
    local candidates = {}
    for _,d in ipairs(pg:GetDescendants()) do
        if d:IsA("ViewportFrame") and d.Visible then
            local s,p = d.AbsoluteSize,d.AbsolutePosition
            if s.X >= 30 and s.Y >= 30 and s.X <= 190 and s.Y <= 190 and p.Y > viewport.Y * .52 then
                candidates[#candidates+1] = d
            end
        end
    end
    table.sort(candidates,function(a,b)
        if math.abs(a.AbsolutePosition.X-b.AbsolutePosition.X) > 3 then return a.AbsolutePosition.X < b.AbsolutePosition.X end
        return a.AbsolutePosition.Y < b.AbsolutePosition.Y
    end)
    for i,h in ipairs(state.Scan and state.Scan.Hotbar or {}) do
        if h.Asset and not Dashboard.Viewports[h.Asset] and candidates[i] then Dashboard.Viewports[h.Asset] = candidates[i] end
    end
    return total
end

local function cloneViewport(vf)
    if not vf then return nil end
    local ok,c = pcall(function() return vf:Clone() end)
    if not ok or not c then return nil end
    c.Position = UDim2.fromScale(0,0)
    c.Size = UDim2.fromScale(1,1)
    c.BackgroundTransparency = 1
    c.BorderSizePixel = 0
    c.Visible = true
    for _,d in ipairs(c:GetDescendants()) do
        if d:IsA("BaseScript") then d:Destroy() end
    end
    return c
end

-- -----------------------------------------------------------------------------
-- Team page
-- -----------------------------------------------------------------------------
local TeamPage = Pages.TEAM
local ObjectiveTitle = text(TeamPage,"OBJECTIVE",UDim2.fromOffset(0,0),UDim2.fromOffset(90,28),true)
ObjectiveTitle.TextSize = 10
local objectives = {"Balanced","Fast Clear","Max Damage","Safe Clear","Boss"}
local objectiveButtons = {}
for i,obj in ipairs(objectives) do
    local b = button(TeamPage,obj,UDim2.fromOffset(90+(i-1)*134,0),UDim2.fromOffset(126,28),function()
        local st = Core.GetState()
        st.Strategy = obj
        task.spawn(function() Dashboard.Sync(true) end)
    end)
    b.TextSize = 10
    b.BackgroundColor3 = Color3.fromRGB(29,34,47)
    objectiveButtons[obj] = b
end

local MetricArea = Instance.new("Frame")
MetricArea.Position = UDim2.fromOffset(0,38)
MetricArea.Size = UDim2.new(1,0,0,88)
MetricArea.BackgroundTransparency = 1
MetricArea.Parent = TeamPage

local metricFrames = {}
local function metricCard(index,titleText)
    local w = 210
    local f = panel(MetricArea,UDim2.fromOffset((index-1)*(w+10),0),UDim2.fromOffset(w,82))
    local t = text(f,titleText,UDim2.fromOffset(12,8),UDim2.new(1,-24,0,18),true)
    t.TextSize = 9; t.TextColor3 = Color3.fromRGB(155,165,188)
    local val = text(f,"—",UDim2.fromOffset(12,27),UDim2.new(1,-24,0,24),true)
    val.TextSize = 18
    local sub = text(f,"",UDim2.fromOffset(12,53),UDim2.new(1,-24,0,18),false)
    sub.TextSize = 9; sub.TextColor3 = Color3.fromRGB(155,165,188)
    metricFrames[index] = {Value=val,Sub=sub,Frame=f}
end
metricCard(1,"EARLY DPS")
metricCard(2,"MID DPS")
metricCard(3,"MAX DPS")
metricCard(4,"CONTROL")

local CurTitle = text(TeamPage,"CURRENT",UDim2.fromOffset(0,136),UDim2.fromOffset(220,20),true)
local CurScroll = Instance.new("ScrollingFrame")
CurScroll.Position = UDim2.fromOffset(0,160)
CurScroll.Size = UDim2.new(1,0,0,154)
CurScroll.BackgroundColor3 = Color3.fromRGB(18,21,29)
CurScroll.BorderSizePixel = 0
CurScroll.ScrollBarThickness = 3
CurScroll.ScrollingDirection = Enum.ScrollingDirection.X
CurScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
CurScroll.CanvasSize = UDim2.new()
CurScroll.Parent = TeamPage
round(CurScroll,9)
local curLayout = Instance.new("UIListLayout",CurScroll)
curLayout.FillDirection = Enum.FillDirection.Horizontal
curLayout.Padding = UDim.new(0,8)
curLayout.VerticalAlignment = Enum.VerticalAlignment.Center
local curPad = Instance.new("UIPadding",CurScroll); curPad.PaddingLeft=UDim.new(0,8); curPad.PaddingRight=UDim.new(0,8)

local RecTitle = text(TeamPage,"RECOMMENDED",UDim2.fromOffset(0,326),UDim2.fromOffset(220,20),true)
local RecScroll = CurScroll:Clone()
RecScroll.Position = UDim2.fromOffset(0,350)
RecScroll.Parent = TeamPage

local function clearScroll(scroll)
    for _,c in ipairs(scroll:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIPadding") and not c:IsA("UICorner") then c:Destroy() end
    end
end

local function unitCard(parent,p,tag)
    local f = Instance.new("Frame")
    f.Size = UDim2.fromOffset(118,136)
    f.BackgroundColor3 = Color3.fromRGB(28,32,44)
    f.BorderSizePixel = 0
    f.Parent = parent
    round(f,9)
    local visual = Instance.new("Frame")
    visual.Position=UDim2.fromOffset(5,5); visual.Size=UDim2.fromOffset(108,82); visual.BackgroundColor3=Color3.fromRGB(17,20,28); visual.BorderSizePixel=0; visual.ClipsDescendants=true; visual.Parent=f; round(visual,7)
    local vp = cloneViewport(p and Dashboard.Viewports[p.Asset])
    if vp then vp.Parent = visual else
        local initial = tostring(p and p.DisplayName or "?"):match("%S") or "?"
        local ph = text(visual,initial:upper(),UDim2.fromScale(0,0),UDim2.fromScale(1,1),true,Enum.TextXAlignment.Center); ph.TextSize=32
    end
    local name = text(f,tostring(p and p.DisplayName or "UNKNOWN"),UDim2.fromOffset(6,91),UDim2.new(1,-12,0,24),true)
    name.TextSize=9; name.TextWrapped=true; name.TextTruncate=Enum.TextTruncate.None
    local dps = p and p.Final and p.Final.RawDPS or nil
    local stat = text(f,tostring(p and p.Element or "?").."  •  "..fmt(dps,0).." DPS",UDim2.fromOffset(6,117),UDim2.new(1,-12,0,14),false)
    stat.TextSize=8; stat.TextColor3=Color3.fromRGB(155,165,188)
    if tag then
        local badge=text(f,tag,UDim2.fromOffset(7,7),UDim2.fromOffset(32,17),true,Enum.TextXAlignment.Center); badge.TextSize=8; badge.BackgroundTransparency=.12; badge.BackgroundColor3=Color3.fromRGB(70,87,139); round(badge,8)
    end
end

-- -----------------------------------------------------------------------------
-- Economy model + history
-- -----------------------------------------------------------------------------
local HISTORY_PATH = "AE_Strategist/economy_history.json"
local History = {Version=1,Stages={}}
if readfile and isfile then
    local okExists,exists = pcall(isfile,HISTORY_PATH)
    if okExists and exists then
        local okRead,raw = pcall(readfile,HISTORY_PATH)
        if okRead then
            local okJson,data = pcall(function() return HS:JSONDecode(raw) end)
            if okJson and type(data)=="table" then History=data; History.Stages=History.Stages or {} end
        end
    end
end

local function saveHistory()
    if not writefile then return end
    if makefolder then pcall(makefolder,"AE_Strategist") end
    local ok,raw=pcall(function() return HS:JSONEncode(History) end)
    if ok then pcall(writefile,HISTORY_PATH,raw) end
end

local function stageKey(state)
    local s=state and state.Stage
    if not s then return "UNKNOWN" end
    return table.concat({tostring(s.Gamemode or "?"),tostring(s.MapName or "?"),tostring(s.ActName or "?"),tostring(s.Difficulty or "?")},"|")
end

local function currentTeam(state)
    local out={}
    for _,h in ipairs(state.Scan and state.Scan.Hotbar or {}) do
        local p=state.Profiles and state.Profiles[h.Asset]
        if p then out[#out+1]=p end
    end
    return out
end

local function recommendedTeam(state)
    return state and state.Recommended and state.Recommended.Team or {}
end

local function incomeUpgrade(p,level)
    if not p then return nil end
    local best=nil
    for _,u in ipairs(p.Upgrades or {}) do
        if u.Income and (level==nil or tonumber(u.Level)==tonumber(level)) then best=u end
    end
    return best
end

local function farmRows(state)
    local rows={}
    for _,p in pairs(state.Profiles or {}) do
        if p.Farm then
            local firstIncome=nil; local maxIncome=nil
            for _,u in ipairs(p.Upgrades or {}) do
                if tonumber(u.Income) then
                    if not firstIncome then firstIncome=u end
                    if not maxIncome or (u.Income or 0)>(maxIncome.Income or 0) then maxIncome=u end
                end
            end
            local cap=math.max(1,tonumber(p.PlacementLimit) or 1)
            local maxWave=maxIncome and (maxIncome.Income or 0)*cap or nil
            local cost=maxIncome and (maxIncome.CumulativeCost or maxIncome.Cost) or nil
            local payback=(cost and maxWave and maxWave>0) and cost/maxWave or nil
            rows[#rows+1]={Profile=p,First=firstIncome,Max=maxIncome,Cap=cap,MaxWave=maxWave,Cost=cost,Payback=payback}
        end
    end
    table.sort(rows,function(a,b) return (a.MaxWave or -1)>(b.MaxWave or -1) end)
    return rows
end

local function farmCeilingForHotbar(state)
    if state.Facts and state.Facts.NoFarm then return 0 end
    local total=0
    for _,p in ipairs(currentTeam(state)) do
        if p.Farm then
            local best=nil
            for _,u in ipairs(p.Upgrades or {}) do if tonumber(u.Income) and (not best or u.Income>best.Income) then best=u end end
            if best then total=total+(best.Income or 0)*math.max(1,tonumber(p.PlacementLimit) or 1) end
        end
    end
    return total
end

local function placedFarmPerWave(state)
    local total=0
    local live=state.LastLive
    for _,x in ipairs(live and live.Placed or {}) do
        local p=state.Profiles and state.Profiles[x.Asset]
        if p and p.Farm then
            local u=incomeUpgrade(p,x.Upgrade)
            if u then total=total+(u.Income or 0) end
        end
    end
    return total
end

local function learnedProjection(state)
    local rec=History.Stages[stageKey(state)]
    return rec and tonumber(rec.ProjectedGross) or nil,rec
end

local function economy(state)
    local facts=state.Facts or {}
    local waveCount=tonumber(facts.WaveCount)
    local starting=tonumber(facts.StartingYen)
    local stageTotal=tonumber(facts.TotalYen)
    local learned,history=learnedProjection(state)
    local farmMax=farmCeilingForHotbar(state)
    local farmNow=placedFarmPerWave(state)
    local farmTotal=(waveCount and farmMax>0) and farmMax*waveCount or nil
    local autoBudget=stageTotal or learned or starting
    return {
        Starting=starting,StageTotal=stageTotal,Learned=learned,History=history,
        WaveCount=waveCount,FarmMax=farmMax,FarmNow=farmNow,FarmTotal=farmTotal,
        AutoBudget=autoBudget,
    }
end

local function findCoreBudgetBox()
    if not Core.Gui then return nil end
    for _,d in ipairs(Core.Gui:GetDescendants()) do
        if d:IsA("TextBox") and norm(d.PlaceholderText)=="budget" then return d end
    end
end

-- Economy page UI
local EconomyPage=Pages.ECONOMY
local summary={}
local function moneyCard(index,titleText)
    local w=168
    local f=panel(EconomyPage,UDim2.fromOffset((index-1)*(w+10),0),UDim2.fromOffset(w,88))
    local t=text(f,titleText,UDim2.fromOffset(12,9),UDim2.new(1,-24,0,16),true); t.TextSize=9; t.TextColor3=Color3.fromRGB(155,165,188)
    local v=text(f,"—",UDim2.fromOffset(12,29),UDim2.new(1,-24,0,30),true); v.TextSize=20
    local s=text(f,"",UDim2.fromOffset(12,61),UDim2.new(1,-24,0,16),false); s.TextSize=8; s.TextColor3=Color3.fromRGB(145,155,179)
    summary[index]={Value=v,Sub=s}
end
moneyCard(1,"STARTING")
moneyCard(2,"STAGE BASE")
moneyCard(3,"LEARNED RUN")
moneyCard(4,"FARM / WAVE")
moneyCard(5,"FARM MAX TOTAL")

local EconStatus=panel(EconomyPage,UDim2.fromOffset(0,100),UDim2.new(1,0,0,54))
local EconStatusTitle=text(EconStatus,"ECONOMY LEARNER",UDim2.fromOffset(12,6),UDim2.fromOffset(160,18),true); EconStatusTitle.TextSize=9
local EconStatusText=text(EconStatus,"waiting for runtime…",UDim2.fromOffset(12,25),UDim2.new(1,-180,0,20),false); EconStatusText.TextSize=10; EconStatusText.TextColor3=Color3.fromRGB(165,175,198)
local LearnButton=button(EconStatus,"AUTO: ON",UDim2.new(1,-120,0,11),UDim2.fromOffset(106,30),function()
    Dashboard.Tracker.Running=not Dashboard.Tracker.Running
    Dashboard.Tracker.Token=Dashboard.Tracker.Token+1
    LearnButton.Text=Dashboard.Tracker.Running and "AUTO: ON" or "AUTO: OFF"
    if Dashboard.Tracker.Running then Dashboard.StartTracker() end
end)

local FarmTitle=text(EconomyPage,"FARM UNITS • MAX ROI",UDim2.fromOffset(0,168),UDim2.fromOffset(260,20),true)
local FarmScroll=Instance.new("ScrollingFrame")
FarmScroll.Position=UDim2.fromOffset(0,194); FarmScroll.Size=UDim2.new(1,0,1,-194); FarmScroll.BackgroundColor3=Color3.fromRGB(18,21,29); FarmScroll.BorderSizePixel=0; FarmScroll.ScrollBarThickness=3; FarmScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; FarmScroll.CanvasSize=UDim2.new(); FarmScroll.Parent=EconomyPage; round(FarmScroll,9)
local farmLayout=Instance.new("UIListLayout",FarmScroll); farmLayout.Padding=UDim.new(0,7); farmLayout.HorizontalAlignment=Enum.HorizontalAlignment.Center
local farmPad=Instance.new("UIPadding",FarmScroll); farmPad.PaddingTop=UDim.new(0,8); farmPad.PaddingBottom=UDim.new(0,8)

local function farmCard(parent,row)
    local f=Instance.new("Frame"); f.Size=UDim2.new(1,-16,0,68); f.BackgroundColor3=Color3.fromRGB(28,32,44); f.BorderSizePixel=0; f.Parent=parent; round(f,8)
    local p=row.Profile
    local vpBox=Instance.new("Frame"); vpBox.Position=UDim2.fromOffset(7,7); vpBox.Size=UDim2.fromOffset(54,54); vpBox.BackgroundColor3=Color3.fromRGB(17,20,28); vpBox.BorderSizePixel=0; vpBox.ClipsDescendants=true; vpBox.Parent=f; round(vpBox,7)
    local vp=cloneViewport(Dashboard.Viewports[p.Asset]); if vp then vp.Parent=vpBox else local ph=text(vpBox,(p.DisplayName or "?"):sub(1,1),UDim2.fromScale(0,0),UDim2.fromScale(1,1),true,Enum.TextXAlignment.Center); ph.TextSize=22 end
    local n=text(f,p.DisplayName,UDim2.fromOffset(72,8),UDim2.fromOffset(190,20),true); n.TextSize=10
    local cap=text(f,"cap ×"..tostring(row.Cap),UDim2.fromOffset(72,31),UDim2.fromOffset(80,18),false); cap.TextSize=9; cap.TextColor3=Color3.fromRGB(155,165,188)
    local inc=text(f,row.MaxWave and ("¥"..fmt(row.MaxWave,0).." / wave") or "income unknown",UDim2.fromOffset(275,8),UDim2.fromOffset(170,22),true); inc.TextSize=13
    local cost=text(f,row.Cost and ("full cost ¥"..fmt(row.Cost,0)) or "cost —",UDim2.fromOffset(275,34),UDim2.fromOffset(170,18),false); cost.TextSize=9; cost.TextColor3=Color3.fromRGB(155,165,188)
    local roi=text(f,row.Payback and (fmt(row.Payback,1).." waves payback") or "ROI unknown",UDim2.new(1,-210,0,20),UDim2.fromOffset(195,24),true,Enum.TextXAlignment.Right); roi.TextSize=11
end

-- -----------------------------------------------------------------------------
-- Live page
-- -----------------------------------------------------------------------------
local LivePage=Pages.LIVE
local liveSummary={}
local function liveCard(index,titleText)
    local w=210
    local f=panel(LivePage,UDim2.fromOffset((index-1)*(w+10),0),UDim2.fromOffset(w,82))
    local t=text(f,titleText,UDim2.fromOffset(12,8),UDim2.new(1,-24,0,18),true); t.TextSize=9; t.TextColor3=Color3.fromRGB(155,165,188)
    local v=text(f,"—",UDim2.fromOffset(12,28),UDim2.new(1,-24,0,28),true); v.TextSize=20
    local s=text(f,"",UDim2.fromOffset(12,58),UDim2.new(1,-24,0,14),false); s.TextSize=8; s.TextColor3=Color3.fromRGB(145,155,179)
    liveSummary[index]={Value=v,Sub=s}
end
liveCard(1,"CURRENT YEN")
liveCard(2,"WAVE")
liveCard(3,"OBSERVED INFLOW")
liveCard(4,"FARM NOW / WAVE")
button(LivePage,"REFRESH",UDim2.new(1,-104,0,90),UDim2.fromOffset(104,30),function() task.spawn(function() pcall(Core.RefreshLive); Dashboard.Refresh() end) end)
local ActionTitle=text(LivePage,"NEXT BEST ACTIONS",UDim2.fromOffset(0,124),UDim2.fromOffset(260,20),true)
local ActionList=Instance.new("Frame"); ActionList.Position=UDim2.fromOffset(0,150); ActionList.Size=UDim2.new(1,0,1,-150); ActionList.BackgroundTransparency=1; ActionList.Parent=LivePage

local function actionCard(parent,a,index)
    local f=panel(parent,UDim2.fromOffset(0,(index-1)*92),UDim2.new(1,0,0,82))
    local badge=text(f,tostring(index),UDim2.fromOffset(10,10),UDim2.fromOffset(34,34),true,Enum.TextXAlignment.Center); badge.TextSize=15; badge.BackgroundTransparency=0; badge.BackgroundColor3=index==1 and Color3.fromRGB(67,118,91) or Color3.fromRGB(55,64,87); round(badge,8)
    local kind=text(f,tostring(a.Type or "ACTION"),UDim2.fromOffset(56,8),UDim2.fromOffset(90,18),true); kind.TextSize=9; kind.TextColor3=Color3.fromRGB(151,164,194)
    local name=text(f,tostring(a.Asset or "?"),UDim2.fromOffset(56,27),UDim2.fromOffset(250,22),true); name.TextSize=14
    local detail=text(f,tostring(a.Detail or ""),UDim2.fromOffset(56,52),UDim2.new(1,-330,0,18),false); detail.TextSize=9; detail.TextColor3=Color3.fromRGB(155,165,188)
    local cost=text(f,"¥"..fmt(a.Cost,0),UDim2.new(1,-245,0,18),UDim2.fromOffset(105,24),true,Enum.TextXAlignment.Right); cost.TextSize=14
    local gain=text(f,"gain/¥ "..fmt(a.GainPerYen,4),UDim2.new(1,-245,0,46),UDim2.fromOffset(225,18),false,Enum.TextXAlignment.Right); gain.TextSize=9; gain.TextColor3=Color3.fromRGB(155,165,188)
end

-- -----------------------------------------------------------------------------
-- Rendering + tracker
-- -----------------------------------------------------------------------------
local function percentDelta(a,b)
    a=tonumber(a) or 0; b=tonumber(b) or 0
    if a==0 then return b>0 and "+∞" or "0%" end
    local p=(b-a)/math.abs(a)*100
    return (p>=0 and "+" or "")..fmt(p,0).."%"
end

local function renderTeam(state)
    for obj,b in pairs(objectiveButtons) do b.BackgroundColor3=(state.Strategy==obj) and Color3.fromRGB(67,83,132) or Color3.fromRGB(29,34,47) end
    local c=state.CurrentMetrics or {}; local r=state.Recommended or {}
    metricFrames[1].Value.Text=fmt(r.EarlyDPS,0); metricFrames[1].Sub.Text=fmt(c.EarlyDPS,0).." → "..percentDelta(c.EarlyDPS,r.EarlyDPS)
    metricFrames[2].Value.Text=fmt(r.MidDPS,0); metricFrames[2].Sub.Text=fmt(c.MidDPS,0).." → "..percentDelta(c.MidDPS,r.MidDPS)
    metricFrames[3].Value.Text=fmt(r.FullDPS,0); metricFrames[3].Sub.Text=fmt(c.FullDPS,0).." → "..percentDelta(c.FullDPS,r.FullDPS)
    metricFrames[4].Value.Text=tostring(setCount(r.CC)); metricFrames[4].Sub.Text="CC types • shield "..tostring(r.Shield or 0)
    clearScroll(CurScroll); clearScroll(RecScroll)
    for i,p in ipairs(currentTeam(state)) do unitCard(CurScroll,p,"S"..i) end
    for i,p in ipairs(recommendedTeam(state)) do unitCard(RecScroll,p,"#"..i) end
end

local function renderEconomy(state)
    local e=economy(state)
    summary[1].Value.Text=e.Starting and ("¥"..fmt(e.Starting,0)) or "—"; summary[1].Sub.Text=e.Starting and "DB/runtime" or "pending runtime"
    summary[2].Value.Text=e.StageTotal and ("¥"..fmt(e.StageTotal,0)) or "—"; summary[2].Sub.Text=e.StageTotal and "exact stage total" or "not exposed"
    summary[3].Value.Text=e.Learned and ("¥"..fmt(e.Learned,0)) or "LEARNING"; summary[3].Sub.Text=e.History and ("from "..tostring(e.History.WavesObserved or 0).." waves") or "positive Yen deltas"
    summary[4].Value.Text=e.FarmMax>0 and ("¥"..fmt(e.FarmMax,0)) or "—"; summary[4].Sub.Text=e.FarmMax>0 and "hotbar full-cap ceiling" or ((state.Facts and state.Facts.NoFarm) and "farm prohibited" or "no exact income")
    summary[5].Value.Text=e.FarmTotal and ("¥"..fmt(e.FarmTotal,0)) or "—"; summary[5].Sub.Text=e.FarmTotal and (tostring(e.WaveCount).." waves") or "needs wave count"
    local live=state.LastLive
    EconStatusText.Text="Yen "..tostring(live and live.Yen and ("¥"..fmt(live.Yen,0)) or "—").."   •   wave "..tostring(live and live.Wave or "—").."   •   observed +¥"..fmt(Dashboard.Tracker.RunPositive,0).."   •   last +¥"..fmt(Dashboard.Tracker.LastDelta,0)
    for _,c in ipairs(FarmScroll:GetChildren()) do if not c:IsA("UIListLayout") and not c:IsA("UIPadding") and not c:IsA("UICorner") then c:Destroy() end end
    local rows=farmRows(state)
    if #rows==0 then
        local none=text(FarmScroll,"No owned Farm unit with a validated Farm flag was found.",UDim2.new(),UDim2.new(1,-20,0,38),false,Enum.TextXAlignment.Center); none.TextSize=10
    else
        for _,row in ipairs(rows) do farmCard(FarmScroll,row) end
    end
end

local function renderLive(state)
    local live=state.LastLive or {}
    local e=economy(state)
    liveSummary[1].Value.Text=live.Yen and ("¥"..fmt(live.Yen,0)) or "—"; liveSummary[1].Sub.Text=live.Yen and "runtime" or "enter a match"
    liveSummary[2].Value.Text=tostring(live.Wave or "—"); liveSummary[2].Sub.Text=e.WaveCount and ("of "..tostring(e.WaveCount)) or "total unknown"
    liveSummary[3].Value.Text="+¥"..fmt(Dashboard.Tracker.RunPositive,0); liveSummary[3].Sub.Text="positive Yen inflow this run"
    liveSummary[4].Value.Text=e.FarmNow>0 and ("¥"..fmt(e.FarmNow,0)) or "—"; liveSummary[4].Sub.Text=e.FarmNow>0 and "placed farm income" or "no placed exact farm income"
    for _,c in ipairs(ActionList:GetChildren()) do c:Destroy() end
    for i=1,math.min(4,#(live.Actions or {})) do actionCard(ActionList,live.Actions[i],i) end
    if #(live.Actions or {})==0 then text(ActionList,"No live action yet. Enter the map, then REFRESH.",UDim2.fromOffset(0,10),UDim2.new(1,0,0,40),false,Enum.TextXAlignment.Center).TextColor3=Color3.fromRGB(150,160,182) end
end

function Dashboard.Refresh()
    if Dashboard.Destroyed then return end
    local state=Core.GetState()
    if not state or not state.Scan then return end
    local st=state.Stage
    StageLabel.Text=st and (tostring(st.Gamemode).."  •  "..tostring(st.MapName).."  •  "..tostring(st.ActName).."  •  "..tostring(st.Difficulty)) or "stage not detected"
    rebuildViewports(state)
    renderTeam(state)
    renderEconomy(state)
    renderLive(state)
end

function Dashboard.Sync(runCore)
    if Dashboard.Destroyed then return end
    SyncButton.Text="…"
    if runCore then pcall(Core.RefreshAnalysis) end
    local state=Core.GetState()
    if state and state.Scan then
        local e=economy(state)
        local box=findCoreBudgetBox()
        if box and e.AutoBudget and e.AutoBudget>0 then
            local new=tostring(math.floor(e.AutoBudget+.5))
            if box.Text~=new then
                box.Text=new
                if runCore then pcall(Core.RefreshAnalysis) end
            end
        end
    end
    pcall(Dashboard.Refresh)
    SyncButton.Text="SYNC"
end

local function resetTracker(state)
    local t=Dashboard.Tracker
    t.PrevYen=nil; t.PrevWave=nil; t.StageKey=stageKey(state); t.RunPositive=0; t.WavePositive={}; t.LastDelta=0
end

local function updateLearnedHistory(state)
    local t=Dashboard.Tracker
    local key=stageKey(state)
    local wave=tonumber(t.PrevWave)
    if key=="UNKNOWN" or not wave then return end
    local facts=state.Facts or {}
    local totalWaves=tonumber(facts.WaveCount)
    local wavesObserved=math.max(1,wave)
    local avg=t.RunPositive/wavesObserved
    local projected=(tonumber(facts.StartingYen) or 0)+(totalWaves and avg*totalWaves or t.RunPositive)
    local rec=History.Stages[key] or {}
    rec.LastPositiveInflow=t.RunPositive
    rec.WavesObserved=wavesObserved
    rec.AvgPositivePerWave=avg
    rec.ProjectedGross=projected
    rec.UpdatedAt=os.time()
    History.Stages[key]=rec
    saveHistory()
end

function Dashboard.TrackerTick()
    if Dashboard.Destroyed or not Dashboard.Tracker.Running then return end
    pcall(Core.RefreshLive)
    local state=Core.GetState()
    local live=state and state.LastLive
    if not live or tonumber(live.Yen)==nil then return end
    local t=Dashboard.Tracker
    local key=stageKey(state)
    if t.StageKey~=key then resetTracker(state) end
    local y=tonumber(live.Yen)
    local w=tonumber(live.Wave)
    if t.PrevYen==nil then t.PrevYen=y; t.PrevWave=w; return end
    if w and t.PrevWave and w<t.PrevWave then resetTracker(state); t.PrevYen=y; t.PrevWave=w; return end
    local delta=y-t.PrevYen
    t.LastDelta=0
    if delta>0 then
        t.RunPositive=t.RunPositive+delta
        t.LastDelta=delta
        local wk=tostring(w or t.PrevWave or "?")
        t.WavePositive[wk]=(t.WavePositive[wk] or 0)+delta
    end
    if w and t.PrevWave and w~=t.PrevWave then updateLearnedHistory(state) end
    t.PrevYen=y; t.PrevWave=w or t.PrevWave
    pcall(Dashboard.Refresh)
end

function Dashboard.StartTracker()
    local t=Dashboard.Tracker
    t.Token=t.Token+1
    local token=t.Token
    task.spawn(function()
        while t.Running and t.Token==token and not Dashboard.Destroyed do
            pcall(Dashboard.TrackerTick)
            task.wait(2.0)
        end
    end)
end

-- Drag
local dragging=false; local dragStart=nil; local startPos=nil
local c1=Top.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true; dragStart=i.Position; startPos=Main.Position end end)
local c2=UIS.InputChanged:Connect(function(i) if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then local d=i.Position-dragStart; Main.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y) end end)
local c3=UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)
local c4=UIS.InputBegan:Connect(function(i,p) if not p and i.KeyCode==Enum.KeyCode.V then Main.Visible=not Main.Visible end end)
Dashboard.Connections[#Dashboard.Connections+1]=c1; Dashboard.Connections[#Dashboard.Connections+1]=c2; Dashboard.Connections[#Dashboard.Connections+1]=c3; Dashboard.Connections[#Dashboard.Connections+1]=c4

function Dashboard.Destroy()
    if Dashboard.Destroyed then return end
    Dashboard.Destroyed=true
    Dashboard.Tracker.Running=false
    Dashboard.Tracker.Token=Dashboard.Tracker.Token+1
    for _,c in ipairs(Dashboard.Connections) do pcall(function() c:Disconnect() end) end
    if CoreMain then CoreMain.Visible=true end
    if Gui then Gui:Destroy() end
    if ENV.AE_STRATEGIST_DASHBOARD==Dashboard then ENV.AE_STRATEGIST_DASHBOARD=nil end
    if Core.Dashboard==Dashboard then Core.Dashboard=nil end
end

showPage("TEAM")
task.spawn(function()
    task.wait(.8)
    pcall(function() Dashboard.Sync(false) end)
    Dashboard.StartTracker()
end)
print("[AE Dashboard] READY",VERSION)
