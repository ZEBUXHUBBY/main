-- Beeconomy Rayfield Automation
-- Built from observed Beeconomy mapper signatures. Unknown actions are not guessed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local LP = Players.LocalPlayer

if game.PlaceId ~= 101558830312092 then
    warn("[Beeconomy] Unexpected place:", game.PlaceId)
end

local CFG = {
    Farm = false,
    Mobs = false,
    Fishing = false,
    QuestAssist = false,
    AutoHourly = false,
    Field = "Dandelion",
    Gap = 0.45,
}

local lastAction = 0
local function log(...) print("[Beeconomy]", ...) end
local function ready()
    if os.clock() - lastAction < CFG.Gap then return false end
    lastAction = os.clock()
    return true
end

local Details = ReplicatedStorage:WaitForChild("Core"):WaitForChild("Details")
local EventRemote = Details:WaitForChild("e_7d9a2f31")
local FunctionRemote = Details:WaitForChild("f_4c81b6e2")

local SESSION_KEY = "7babad1b53c84bffb74659a0cb526b19"
local HARVEST_OPCODE = 3637647479 -- observed repeatedly for Dandelion harvest packets
local HOURLY_OPCODE = 4171703067 -- observed hourly reward claim

local function pg()
    return LP:FindFirstChildOfClass("PlayerGui") or LP:FindFirstChild("PlayerGui")
end

local function resolve(root, path)
    local n = root
    for _,name in ipairs(path) do
        n = n and n:FindFirstChild(name)
        if not n then return nil end
    end
    return n
end

local function clickGui(btn)
    if not btn or not btn:IsA("GuiButton") then return false end
    local ok = pcall(function() btn:Activate() end)
    if ok then return true end
    if firesignal then
        local ok2 = pcall(function() firesignal(btn.MouseButton1Click) end)
        if ok2 then return true end
    end
    local pos = btn.AbsolutePosition + btn.AbsoluteSize/2
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(pos.X,pos.Y,0,true,game,0)
        task.wait()
        VirtualInputManager:SendMouseButtonEvent(pos.X,pos.Y,0,false,game,0)
    end)
    return true
end

local GUI = {
    Shovel = {"MiddleGui","MenuMain","ButtonStack","Hotbar","basic_shovel"},
    Rod = {"MiddleGui","MenuMain","ButtonStack","Hotbar","wooden_fishing_rod"},
    Playtime = {"MiddleGui","MenuMain","LeftSideBar","ButtonGrid","PlaytimeCell","Playtime"},
    Craft = {"MiddleGui","MenuMain","BottomDock","BottomBar","ButtonRow","Craft","IconButton"},
}

local function clickPath(path)
    local root = pg()
    local b = root and resolve(root,path)
    return clickGui(b)
end

local function rootPart()
    local ch = LP.Character
    return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function currentField()
    return LP:GetAttribute("BeeCombatTargetFieldDb") or CFG.Field
end

local function equipShovel()
    if LP:GetAttribute("ShovelEquipped") then return true end
    clickPath(GUI.Shovel)
    task.wait(0.15)
    return LP:GetAttribute("ShovelEquipped") == true
end

local function getHarvestPoints(center)
    -- Observed packets contain 3-6 nearby Vector3 flower/ground points.
    -- We only create local nearby points; the server remains authoritative.
    local points = {}
    local offsets = {
        Vector3.new(-2.0,-3.1, 1.0),
        Vector3.new( 2.4,-3.1, 2.6),
        Vector3.new(-2.5,-3.1,-2.2),
        Vector3.new( 2.6,-3.1,-3.0),
        Vector3.new(-0.4,-3.1,-1.2),
        Vector3.new( 0.8,-3.1, 0.4),
    }
    for _,off in ipairs(offsets) do
        points[#points+1] = center + off
    end
    return points
end

local function farmOnce()
    if not ready() then return end
    local hrp = rootPart()
    if not hrp then return end
    if not equipShovel() then
        log("Could not equip shovel")
        return
    end

    local field = currentField()
    local pos = hrp.Position
    local points = getHarvestPoints(pos)
    local ok,err = pcall(function()
        EventRemote:FireServer(SESSION_KEY, HARVEST_OPCODE, field, pos, points)
    end)
    if not ok then warn("[Beeconomy] harvest failed",err) end
end

local function mobList()
    local out = {}
    for _,d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ClickDetector") and d.Name == "BeeMobTargetClick" then
            local part = d.Parent
            local hrp = rootPart()
            local dist = math.huge
            if hrp and part and part:IsA("BasePart") then
                dist = (hrp.Position-part.Position).Magnitude
            end
            out[#out+1] = {cd=d,dist=dist}
        end
    end
    table.sort(out,function(a,b) return a.dist < b.dist end)
    return out
end

local function clickDetector(cd)
    if not cd then return false end
    if fireclickdetector then
        local ok = pcall(fireclickdetector,cd)
        return ok
    end
    return false
end

local function mobOnce()
    if not ready() then return end
    local list = mobList()
    if list[1] then
        if not clickDetector(list[1].cd) then
            log("Executor has no fireclickdetector")
        end
    end
end

local function fishingOnce()
    if not ready() then return end
    clickPath(GUI.Rod)
    task.wait(0.1)
    for _,d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ClickDetector") and d.Name == "FishingWaterClick" then
            if clickDetector(d) then return end
        end
    end
end

local function claimHourly()
    local ok,result = pcall(function()
        return FunctionRemote:InvokeServer(SESSION_KEY,HOURLY_OPCODE,"hourly",1)
    end)
    if ok then
        log("Hourly result", result and result.success)
        return result
    end
    warn("[Beeconomy] hourly failed",result)
end

local function questText()
    local root = pg()
    local box = root and resolve(root,{"MiddleGui","QuestBox"})
    if not box then return "" end
    local t = {}
    for _,d in ipairs(box:GetDescendants()) do
        if d:IsA("TextLabel") and d.Visible and d.Text ~= "" then
            t[#t+1] = string.lower(d.Text)
        end
    end
    return table.concat(t," ")
end

local function questOnce()
    local q = questText()
    if q == "" then return end
    if q:find("pollen",1,true) or q:find("honey",1,true) then
        farmOnce()
    elseif q:find("mob",1,true) or q:find("ladybug",1,true) or q:find("spider",1,true) or q:find("snail",1,true) or q:find("boss",1,true) then
        mobOnce()
    elseif q:find("fish",1,true) then
        fishingOnce()
    elseif q:find("craft",1,true) then
        clickPath(GUI.Craft)
    end
end

local Rayfield = loadstring(game:HttpGet(((getgenv and getgenv().RayfieldUrl) or "https://sirius.menu/rayfield")))()
local Window = Rayfield:CreateWindow({
    Name = "Beeconomy Automation",
    Icon = 0,
    LoadingTitle = "Beeconomy",
    LoadingSubtitle = "ZEBUXHUBBY",
    ConfigurationSaving = {Enabled=false},
    KeySystem = false,
})

local AutoTab = Window:CreateTab("Automation",4483362458)
local RewardTab = Window:CreateTab("Rewards",4483362458)
local DebugTab = Window:CreateTab("Debug",4483362458)

AutoTab:CreateToggle({Name="Auto Farm",CurrentValue=false,Flag="BeeFarm",Callback=function(v) CFG.Farm=v end})
AutoTab:CreateToggle({Name="Auto Mobs",CurrentValue=false,Flag="BeeMobs",Callback=function(v) CFG.Mobs=v end})
AutoTab:CreateToggle({Name="Auto Fishing",CurrentValue=false,Flag="BeeFish",Callback=function(v) CFG.Fishing=v end})
AutoTab:CreateToggle({Name="Quest Assist",CurrentValue=false,Flag="BeeQuest",Callback=function(v) CFG.QuestAssist=v end})
AutoTab:CreateInput({Name="Preferred Field",CurrentValue=CFG.Field,PlaceholderText="Dandelion",RemoveTextAfterFocusLost=false,Flag="BeeField",Callback=function(v) if v and v~="" then CFG.Field=v end end})
AutoTab:CreateSlider({Name="Action Gap",Range={0.25,2},Increment=0.05,Suffix="s",CurrentValue=CFG.Gap,Flag="BeeGap",Callback=function(v) CFG.Gap=v end})

RewardTab:CreateButton({Name="Claim Hourly Reward",Callback=claimHourly})
RewardTab:CreateToggle({Name="Auto Hourly Claim",CurrentValue=false,Flag="BeeHourly",Callback=function(v) CFG.AutoHourly=v end})

DebugTab:CreateButton({Name="Test Farm Once",Callback=farmOnce})
DebugTab:CreateButton({Name="Test Nearest Mob",Callback=mobOnce})
DebugTab:CreateButton({Name="Test Fishing Click",Callback=fishingOnce})
DebugTab:CreateButton({Name="Print State",Callback=function()
    print("Field",currentField())
    print("ShovelEquipped",LP:GetAttribute("ShovelEquipped"))
    print("GripHoldKind",LP:GetAttribute("GripHoldKind"))
    print("ActiveHoldRevision",LP:GetAttribute("ActiveHoldRevision"))
    print("SelectedMobId",LP:GetAttribute("SelectedMobId"))
    print("BeeCombatTargetMobId",LP:GetAttribute("BeeCombatTargetMobId"))
end})

local lastHourlyTry = 0
task.spawn(function()
    while task.wait(0.15) do
        if CFG.QuestAssist then
            questOnce()
        else
            if CFG.Farm then farmOnce() end
            if CFG.Mobs then mobOnce() end
            if CFG.Fishing then fishingOnce() end
        end
        if CFG.AutoHourly and os.clock()-lastHourlyTry > 60 then
            lastHourlyTry=os.clock()
            claimHourly()
        end
    end
end)

Rayfield:Notify({Title="Beeconomy",Content="Rayfield automation loaded",Duration=4})
log("Loaded. Direct actions enabled.")