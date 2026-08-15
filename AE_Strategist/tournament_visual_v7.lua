--[[
AE TOURNAMENT VISUAL V7
Visual-only layer over the working Tournament result.
- No background analysis.
- Reads ENV.AE_TOURNAMENT_OPTIMIZER.Result produced by the existing engine.
- Uses game UI images first, then game unit models as fallback.
- Shows Combat 6 + conditional Farm Variant.
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer
local ENV = getgenv and getgenv() or _G
local Engine = ENV.AE_TOURNAMENT_OPTIMIZER

if type(Engine) ~= "table" or type(Engine.Result) ~= "table" then
    error("Tournament result missing; run Analyze first")
end

if type(ENV.AE_TOURNAMENT_VISUAL_V7) == "table" and type(ENV.AE_TOURNAMENT_VISUAL_V7.Destroy) == "function" then
    pcall(ENV.AE_TOURNAMENT_VISUAL_V7.Destroy)
end

local Result = Engine.Result
local App = {Connections = {}, Destroyed = false, Result = Result, IconCache = {}, Selected = 1}
ENV.AE_TOURNAMENT_VISUAL_V7 = App

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

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function round(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = obj
    return c
end

local function makeText(parent, value, pos, size, fontSize, bold, align)
    local x = Instance.new("TextLabel")
    x.BackgroundTransparency = 1
    x.Position = pos
    x.Size = size
    x.Text = value or ""
    x.TextColor3 = Color3.fromRGB(236,238,244)
    x.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    x.TextSize = fontSize or 12
    x.TextXAlignment = align or Enum.TextXAlignment.Left
    x.TextYAlignment = Enum.TextYAlignment.Center
    x.TextWrapped = true
    x.Parent = parent
    return x
end

local function makeButton(parent, value, pos, size, callback)
    local b = Instance.new("TextButton")
    b.Position = pos
    b.Size = size
    b.BackgroundColor3 = Color3.fromRGB(62,78,127)
    b.BorderSizePixel = 0
    b.Text = value
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.Parent = parent
    round(b, 8)
    if callback then
        App.Connections[#App.Connections + 1] = b.MouseButton1Click:Connect(callback)
    end
    return b
end

local function panel(parent, pos, size)
    local f = Instance.new("Frame")
    f.Position = pos
    f.Size = size
    f.BackgroundColor3 = Color3.fromRGB(22,26,36)
    f.BorderSizePixel = 0
    f.Parent = parent
    round(f, 10)
    return f
end

-- Hide old Tournament UI; keep the engine/result alive.
local pg = LP:WaitForChild("PlayerGui")
for _, name in ipairs({"AE_Tournament_V4", "AE_Tournament_Only"}) do
    local old = pg:FindFirstChild(name)
    if old then old.Enabled = false end
end

local oldV7 = pg:FindFirstChild("AE_Tournament_VisualV7")
if oldV7 then oldV7:Destroy() end

local Gui = Instance.new("ScreenGui")
Gui.Name = "AE_Tournament_VisualV7"
Gui.ResetOnSpawn = false
Gui.DisplayOrder = 100020
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = pg
App.Gui = Gui

-- -----------------------------------------------------------------------------
-- GAME ICON RESOLVER
-- -----------------------------------------------------------------------------
local UnitModels = RS:FindFirstChild("Assets") and RS.Assets:FindFirstChild("Units")
local Info = RS:FindFirstChild("Shared") and RS.Shared:FindFirstChild("Information")
local UnitInfo = nil
if Info and Info:FindFirstChild("Units") then
    pcall(function() UnitInfo = require(Info.Units) end)
end
if type(UnitInfo) == "table" then UnitInfo = UnitInfo.Units or UnitInfo.Data or UnitInfo end

local function nearbyText(node)
    local cur = node
    local pieces = {}
    for _ = 1, 5 do
        cur = cur and cur.Parent
        if not cur then break end
        for _, d in ipairs(cur:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and #d.Text < 80 then
                pieces[#pieces + 1] = d.Text
                if #pieces >= 12 then break end
            end
        end
        if #pieces > 0 then break end
    end
    return norm(table.concat(pieces, " "))
end

local function findGameImageForText(searches)
    local targets = {}
    for _, s in ipairs(searches or {}) do
        local n = norm(s)
        if #n >= 2 then targets[#targets + 1] = n end
    end
    if #targets == 0 then return nil end

    local best, bestScore = nil, -1
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("ImageLabel") or d:IsA("ImageButton") then
            if type(d.Image) == "string" and d.Image ~= "" then
                local hay = norm(d.Name .. " " .. (d.Parent and d.Parent.Name or "")) .. nearbyText(d)
                local score = 0
                for _, t in ipairs(targets) do
                    if hay:find(t, 1, true) then score = score + #t end
                end
                if score > bestScore then best, bestScore = d, score end
            end
        end
    end
    if bestScore > 0 then return best end
end

local function copyImage(parent, source)
    if not source then return false end
    local img = Instance.new("ImageLabel")
    img.Size = UDim2.fromScale(1,1)
    img.BackgroundTransparency = 1
    img.Image = source.Image
    img.ImageColor3 = source.ImageColor3
    img.ImageTransparency = source.ImageTransparency
    img.ScaleType = Enum.ScaleType.Fit
    img.Parent = parent
    return true
end

local function findAssetModel(asset)
    if not UnitModels then return nil end
    local folder = UnitModels:FindFirstChild(asset)
    if not folder then return nil end
    if folder:IsA("Model") then return folder end
    for _, n in ipairs({"Model","Default","Shiny","Unit"}) do
        local x = folder:FindFirstChild(n)
        if x and x:IsA("Model") then return x end
    end
    return folder:FindFirstChildWhichIsA("Model", true)
end

local function gameViewport(parent, asset)
    local src = findAssetModel(asset)
    if not src then return false end
    local ok, model = pcall(function() return src:Clone() end)
    if not ok or not model then return false end

    local vf = Instance.new("ViewportFrame")
    vf.Size = UDim2.fromScale(1,1)
    vf.BackgroundTransparency = 1
    vf.BorderSizePixel = 0
    vf.Ambient = Color3.new(1,1,1)
    vf.LightColor = Color3.new(1,1,1)
    vf.Parent = parent

    local world = Instance.new("WorldModel")
    world.Parent = vf
    model.Parent = world
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = true
            d.CanCollide = false
        end
    end

    local cf, size = model:GetBoundingBox()
    local pivot = model:GetPivot()
    local centered = CFrame.new(-cf.Position) * pivot
    pcall(function() model:PivotTo(centered) end)
    local _, s = model:GetBoundingBox()
    local m = math.max(s.X, s.Y, s.Z, 1)

    local cam = Instance.new("Camera")
    cam.FieldOfView = 32
    cam.CFrame = CFrame.lookAt(Vector3.new(m * 1.35, m * 0.12, m * 2.5), Vector3.new(0, m * 0.06, 0))
    cam.Parent = vf
    vf.CurrentCamera = cam
    return true
end

local function renderUnitIcon(parent, copy)
    local asset = copy.Asset
    local display = copy.DisplayName or asset
    local cacheKey = norm(asset)
    local cached = App.IconCache[cacheKey]
    if cached and cached.Parent then
        return copyImage(parent, cached)
    end

    -- First choice: exact image already rendered by the game UI (hotbar / inventory / asset icon).
    local img = findGameImageForText({asset, display})
    if img then
        App.IconCache[cacheKey] = img
        if copyImage(parent, img) then return true end
    end

    -- Second choice: game-owned 3D unit model rendered into our viewport.
    return gameViewport(parent, asset)
end

local function renderModifierIcon(parent, names)
    local img = findGameImageForText(names)
    if img then return copyImage(parent, img) end
    return false
end

-- -----------------------------------------------------------------------------
-- FARM VARIANT
-- -----------------------------------------------------------------------------
local function farmStats(copy)
    if not copy or not copy.Farm then return nil end
    local bestIncome, bestUpgrade = nil, nil
    for _, u in ipairs(copy.Upgrades or {}) do
        local inc = tonumber(u.Income)
        if inc and inc > 0 and (not bestIncome or inc > bestIncome) then
            bestIncome = inc
            bestUpgrade = u
        end
    end
    if not bestIncome or not bestUpgrade then return nil end
    local cap = math.max(1, tonumber(copy.PlacementLimit) or 1)
    local perWave = bestIncome * cap
    local perCopyCost = tonumber(bestUpgrade.CumulativeCost) or tonumber(bestUpgrade.Cost)
    local totalCost = perCopyCost and perCopyCost * cap or nil
    local payback = totalCost and perWave > 0 and totalCost / perWave or nil
    return {Copy=copy, PerWave=perWave, TotalCost=totalCost, Payback=payback, Upgrade=bestUpgrade, Cap=cap}
end

local function bestFarm()
    local best = nil
    for _, copy in pairs(Result.Best or {}) do
        local row = farmStats(copy)
        if row and (not best or row.PerWave > best.PerWave) then best = row end
    end
    return best
end

local function farmVariant()
    local farm = bestFarm()
    if not farm then return nil end
    local team = {}
    for i, c in ipairs(Result.Team or {}) do team[i] = c end
    if #team == 0 then return nil end

    local weakestIndex, weakestDps = 1, math.huge
    for i, c in ipairs(team) do
        local d = tonumber(c.CapDPS) or 0
        if d < weakestDps then weakestDps, weakestIndex = d, i end
    end

    local removed = team[weakestIndex]
    team[weakestIndex] = farm.Copy
    local combatLoss = math.max(0, (tonumber(removed and removed.CapDPS) or 0) - (tonumber(farm.Copy.CapDPS) or 0))
    return {Farm=farm, Team=team, Removed=removed, CombatLoss=combatLoss, Slot=weakestIndex}
end

local FarmVariant = farmVariant()

-- -----------------------------------------------------------------------------
-- UI
-- -----------------------------------------------------------------------------
local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(1080,700)
Main.Position = UDim2.new(.5,-540,.5,-350)
Main.BackgroundColor3 = Color3.fromRGB(13,16,23)
Main.BorderSizePixel = 0
Main.Parent = Gui
round(Main, 12)

local Top = Instance.new("Frame")
Top.Size = UDim2.new(1,0,0,62)
Top.BackgroundColor3 = Color3.fromRGB(23,27,38)
Top.BorderSizePixel = 0
Top.Parent = Main
round(Top, 12)

local Title = makeText(Top,"TOURNAMENT OPTIMIZER V7",UDim2.fromOffset(18,0),UDim2.fromOffset(255,62),17,true)
local Stage = Result.State and Result.State.Stage or nil
local stageText = (Stage and (tostring(Stage.MapName or "Tournament") .. " • " .. tostring(Stage.Difficulty or ""))) or "Tournament"
local Subtitle = makeText(Top,stageText,UDim2.fromOffset(280,0),UDim2.fromOffset(430,62),11,false)
Subtitle.TextColor3 = Color3.fromRGB(157,168,193)
makeButton(Top,"×",UDim2.new(1,-52,0,14),UDim2.fromOffset(38,34),function() App.Destroy() end).TextSize = 18

local Mods = panel(Main,UDim2.fromOffset(18,76),UDim2.new(1,-36,0,82))
makeText(Mods,"CURRENT TOURNAMENT",UDim2.fromOffset(14,7),UDim2.fromOffset(190,18),9,true).TextColor3=Color3.fromRGB(151,162,187)

local threat = Result.Threat or {}
local modItems = {}
if threat.BossWaves then modItems[#modItems+1] = {Text="BOSS WAVES", Search={"Boss Waves","All enemies are bosses"}} end
if threat.Speedy then modItems[#modItems+1] = {Text="SPEEDY +"..tostring(threat.SpeedPercent or 50).."%", Search={"Speedy","Enemies are 50% faster"}} end
local labels = threat.Labels or {}
for _, x in ipairs(labels) do
    local nx = norm(x)
    if not nx:find("bosswaves",1,true) and not nx:find("speedy",1,true) then
        modItems[#modItems+1] = {Text=x,Search={x}}
    end
end
if #modItems == 0 then modItems[1] = {Text="NO MODIFIER ICON DETECTED", Search={}} end

for i,item in ipairs(modItems) do
    local chip = Instance.new("Frame")
    chip.Position = UDim2.fromOffset(14+(i-1)*205,30)
    chip.Size = UDim2.fromOffset(195,40)
    chip.BackgroundColor3 = Color3.fromRGB(31,37,51)
    chip.BorderSizePixel = 0
    chip.Parent = Mods
    round(chip,8)
    local ib = Instance.new("Frame")
    ib.Position=UDim2.fromOffset(5,5); ib.Size=UDim2.fromOffset(30,30); ib.BackgroundTransparency=1; ib.Parent=chip
    if not renderModifierIcon(ib,item.Search) then
        makeText(ib,"•",UDim2.fromScale(0,0),UDim2.fromScale(1,1),22,true,Enum.TextXAlignment.Center)
    end
    makeText(chip,item.Text,UDim2.fromOffset(42,0),UDim2.new(1,-48,1,0),11,true)
end

local Tabs = Instance.new("Frame")
Tabs.Position=UDim2.fromOffset(18,170); Tabs.Size=UDim2.new(1,-36,0,38); Tabs.BackgroundTransparency=1; Tabs.Parent=Main
local CombatButton, FarmButton
local mode = "COMBAT"
CombatButton = makeButton(Tabs,"BEST COMBAT 6",UDim2.fromOffset(0,0),UDim2.fromOffset(145,34))
FarmButton = makeButton(Tabs,"FARM VARIANT",UDim2.fromOffset(153,0),UDim2.fromOffset(145,34))

local TeamArea = panel(Main,UDim2.fromOffset(18,216),UDim2.new(1,-36,0,230))
local TeamTitle = makeText(TeamArea,"BEST COMBAT TEAM",UDim2.fromOffset(14,8),UDim2.new(1,-28,0,24),13,true)
local Cards = Instance.new("Frame")
Cards.Position=UDim2.fromOffset(10,38); Cards.Size=UDim2.new(1,-20,1,-46); Cards.BackgroundTransparency=1; Cards.Parent=TeamArea

local Detail = panel(Main,UDim2.fromOffset(18,458),UDim2.new(1,-36,1,-476))
local DetailTitle = makeText(Detail,"SELECT A UNIT",UDim2.fromOffset(16,10),UDim2.new(1,-32,0,27),15,true)
local DetailText = makeText(Detail,"",UDim2.fromOffset(16,42),UDim2.new(1,-32,1,-54),12,false)
DetailText.TextYAlignment=Enum.TextYAlignment.Top
DetailText.RichText=false

local function fidelity(copy)
    local n=0
    for _,v in pairs(copy.Fidelity or {}) do if v then n=n+1 end end
    if n>=3 then return "HIGH" elseif n>0 then return "PARTIAL" else return "BASE" end
end

local function roleBadges(copy)
    local out={}
    if copy.Farm then out[#out+1]="FARM" end
    if copy.ShieldCounter then out[#out+1]="SHIELD" end
    if count(copy.CC)>0 then out[#out+1]="CC" end
    if copy.Boss then out[#out+1]="BOSS" end
    local f=copy.Final
    if f and tonumber(f.Range) and tonumber(f.Range)>=28 then out[#out+1]="RANGE" end
    if #out==0 then out[1]="DPS" end
    return out
end

local function adviceFor(copy)
    local r=Engine.Result
    local advice=r and r.Advice and r.Advice[copy.Asset]
    -- Ask the working engine to calculate lazy advice by simulating its old card click is not exposed.
    -- Therefore only show advice already resolved by the engine; never fabricate missing advice.
    return advice
end

local function renderDetail(copy,index,variantMeta)
    if not copy then return end
    App.Selected=index
    DetailTitle.Text="#"..tostring(index).."  "..tostring(copy.DisplayName).."  •  Lv"..tostring(copy.Level or "?").."  •  "..tostring(copy.Trait or "No Trait")
    local bullets={}
    bullets[#bullets+1]="• Cap DPS: "..fmt(copy.CapDPS,0).."   | placement ×"..tostring(copy.PlacementLimit or 1).."   | final range "..fmt(copy.Final and copy.Final.Range,1)
    bullets[#bullets+1]="• Equipment: "..tostring(copy.EquipmentLabel or "None")
    bullets[#bullets+1]="• Potential: "..((copy.Potential and #copy.Potential>0) and table.concat(copy.Potential," • ") or "formula not resolved")
    bullets[#bullets+1]="• Stat confidence: "..fidelity(copy).."   | "..tostring(copy.SourceLabel or "BASE ONLY")
    bullets[#bullets+1]="• Roles: "..table.concat(roleBadges(copy)," / ")

    if threat.BossWaves then bullets[#bullets+1]="• Boss Waves: sustained DPS + range uptime matter; CC is not credited unless boss compatibility is proven." end
    if threat.Speedy then bullets[#bullets+1]="• Speedy +"..tostring(threat.SpeedPercent or 50).."%: range/uptime is weighted more heavily." end

    local advice=adviceFor(copy)
    if advice then
        if advice.TraitFit then bullets[#bullets+1]="• Recommended Trait for modifiers: "..tostring(advice.TraitFit.Name) end
        if advice.TraitHigh then bullets[#bullets+1]="• Highest cap-DPS Trait: "..tostring(advice.TraitHigh.Name) end
        if advice.TraitEarly then bullets[#bullets+1]="• Best opener Trait: "..tostring(advice.TraitEarly.Name) end
        if advice.Equipment then bullets[#bullets+1]="• Recommended Equipment: "..tostring(advice.Equipment.Name).." (theoretical unless owned)" end
    else
        bullets[#bullets+1]="• Trait/Equipment what-if: not calculated yet; current-copy recommendation remains evidence-based only."
    end

    local fs=farmStats(copy)
    if fs then
        bullets[#bullets+1]="• Farm income: ¥"..fmt(fs.PerWave,0).." / wave at cap"
        bullets[#bullets+1]="• Farm full cost: "..(fs.TotalCost and ("¥"..fmt(fs.TotalCost,0)) or "UNKNOWN").."   | payback "..(fs.Payback and (fmt(fs.Payback,1).." waves") or "UNKNOWN")
    end

    if variantMeta then
        bullets[#bullets+1]=""
        bullets[#bullets+1]="FARM VARIANT TRADE-OFF"
        bullets[#bullets+1]="• Replaces: "..tostring(variantMeta.Removed and variantMeta.Removed.DisplayName or "unknown")
        bullets[#bullets+1]="• Combat cap-DPS lost: "..fmt(variantMeta.CombatLoss,0)
        bullets[#bullets+1]="• Extra Farm income: ¥"..fmt(variantMeta.Farm.PerWave,0).." / wave"
        bullets[#bullets+1]="• Payback: "..(variantMeta.Farm.Payback and (fmt(variantMeta.Farm.Payback,1).." waves") or "UNKNOWN")
        bullets[#bullets+1]="• This is conditional because the Tournament score/economy formula is still unverified."
    end

    DetailText.Text=table.concat(bullets,"\n")
end

local function clearCards()
    for _,c in ipairs(Cards:GetChildren()) do c:Destroy() end
end

local function makeCard(copy,index,variantMeta)
    local w=158
    local f=Instance.new("TextButton")
    f.Position=UDim2.fromOffset((index-1)*(w+8),0)
    f.Size=UDim2.fromOffset(w,180)
    f.Text=""
    f.AutoButtonColor=true
    f.BackgroundColor3=Color3.fromRGB(29,34,46)
    f.BorderSizePixel=0
    f.Parent=Cards
    round(f,9)

    local vis=Instance.new("Frame")
    vis.Position=UDim2.fromOffset(6,6); vis.Size=UDim2.fromOffset(w-12,92); vis.BackgroundColor3=Color3.fromRGB(16,19,27); vis.BorderSizePixel=0; vis.ClipsDescendants=true; vis.Parent=f; round(vis,7)
    if not renderUnitIcon(vis,copy) then
        makeText(vis,(copy.DisplayName or "?"):sub(1,1),UDim2.fromScale(0,0),UDim2.fromScale(1,1),34,true,Enum.TextXAlignment.Center)
    end

    local badge=makeText(f,"#"..index,UDim2.fromOffset(8,8),UDim2.fromOffset(32,18),8,true,Enum.TextXAlignment.Center)
    badge.BackgroundTransparency=.08; badge.BackgroundColor3=Color3.fromRGB(70,88,142); round(badge,8)
    makeText(f,tostring(copy.DisplayName),UDim2.fromOffset(8,103),UDim2.new(1,-16,0,29),10,true)
    makeText(f,"Lv"..tostring(copy.Level or "?").." • "..tostring(copy.Trait or "No Trait"),UDim2.fromOffset(8,132),UDim2.new(1,-16,0,17),9,false).TextColor3=Color3.fromRGB(157,168,191)
    makeText(f,fmt(copy.CapDPS,0).." cap DPS",UDim2.fromOffset(8,151),UDim2.new(1,-16,0,19),10,true)

    App.Connections[#App.Connections+1]=f.MouseButton1Click:Connect(function() renderDetail(copy,index,variantMeta) end)
end

local function renderMode(newMode)
    mode=newMode
    clearCards()
    CombatButton.BackgroundColor3 = mode=="COMBAT" and Color3.fromRGB(69,87,143) or Color3.fromRGB(42,49,67)
    FarmButton.BackgroundColor3 = mode=="FARM" and Color3.fromRGB(69,87,143) or Color3.fromRGB(42,49,67)

    local team
    local meta=nil
    if mode=="FARM" then
        if not FarmVariant then
            TeamTitle.Text="FARM VARIANT • NOT AVAILABLE"
            DetailTitle.Text="NO VALIDATED FARM VARIANT"
            DetailText.Text="• No owned Farm unit with explicit Income data was resolved.\n• The optimizer will not invent farm income or payback.\n• Best Combat 6 remains the recommended evidence-based team."
            return
        end
        team=FarmVariant.Team
        meta=FarmVariant
        TeamTitle.Text="FARM VARIANT • ¥"..fmt(FarmVariant.Farm.PerWave,0).." / WAVE • PAYBACK "..(FarmVariant.Farm.Payback and fmt(FarmVariant.Farm.Payback,1) or "?").." WAVES"
    else
        team=Result.Team or {}
        TeamTitle.Text="BEST COMBAT 6 • "..((threat.Labels and #threat.Labels>0) and table.concat(threat.Labels," + ") or "CURRENT MODIFIERS")
    end

    for i,c in ipairs(team or {}) do makeCard(c,i,meta and i==meta.Slot and meta or nil) end
    if team and #team>0 then renderDetail(team[1],1,meta and meta.Slot==1 and meta or nil) end
end

CombatButton.MouseButton1Click:Connect(function() renderMode("COMBAT") end)
FarmButton.MouseButton1Click:Connect(function() renderMode("FARM") end)

-- Drag window.
local dragging=false; local dragStart=nil; local startPos=nil
App.Connections[#App.Connections+1]=Top.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true; dragStart=i.Position; startPos=Main.Position end
end)
App.Connections[#App.Connections+1]=UIS.InputChanged:Connect(function(i)
    if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then
        local d=i.Position-dragStart
        Main.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)
App.Connections[#App.Connections+1]=UIS.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
end)

function App.Destroy()
    if App.Destroyed then return end
    App.Destroyed=true
    for _,c in ipairs(App.Connections) do pcall(function() c:Disconnect() end) end
    if Gui then Gui:Destroy() end
    for _,name in ipairs({"AE_Tournament_V4","AE_Tournament_Only"}) do
        local old=pg:FindFirstChild(name)
        if old then old.Enabled=true end
    end
    if ENV.AE_TOURNAMENT_VISUAL_V7==App then ENV.AE_TOURNAMENT_VISUAL_V7=nil end
end

renderMode("COMBAT")
print("[AE Tournament Visual V7] READY | game-icon first | farm variant")
