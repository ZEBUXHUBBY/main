-- Beeconomy Automation Harness with WindUI shell
-- Safe-by-default: normal state/UI/world interactions only.

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local Config = {
    DryRun = true,
    MinActionGap = 0.35,
    FarmEnabled = false,
    MobEnabled = false,
    FishingEnabled = false,
    QuestAssist = true,
    DailyRewards = true,
    PlaytimeRewards = true,
    PreferredField = "Dandelion",
    AuthorizedTestMode = false,
}

local State = {
    LastActionAt = 0,
    Running = true,
}

local function log(...)
    print("[Beeconomy]", ...)
end

local function canAct()
    return os.clock() - State.LastActionAt >= Config.MinActionGap
end

local function doAction(label, fn)
    if not canAct() then return false, "throttled" end
    State.LastActionAt = os.clock()

    if Config.DryRun then
        log("DRY RUN", label)
        return true, "dry-run"
    end

    local ok, result = pcall(fn)
    if not ok then
        warn("[Beeconomy]", label, result)
        return false, result
    end
    return result ~= false, result
end

local function getPlayerGui()
    return LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:FindFirstChild("PlayerGui")
end

local function resolve(root, parts)
    local node = root
    for _, name in ipairs(parts) do
        node = node and node:FindFirstChild(name)
        if not node then return nil end
    end
    return node
end

local GUI = {
    Playtime = {"MiddleGui","MenuMain","LeftSideBar","ButtonGrid","PlaytimeCell","Playtime"},
    Quests = {"MiddleGui","MenuMain","BottomDock","BottomBar","MenuShortcutStrip","RightShortcuts","Quests","IconButton"},
    Craft = {"MiddleGui","MenuMain","BottomDock","BottomBar","ButtonRow","Craft","IconButton"},
    Shovel = {"MiddleGui","MenuMain","ButtonStack","Hotbar","basic_shovel"},
    FishingRod = {"MiddleGui","MenuMain","ButtonStack","Hotbar","wooden_fishing_rod"},
    DailyClaim = {"MiddleGui","TabContainer","PlaytimePanel","Main","ContentArea","TabHost","DailyRewardsCanvas","DailyRewardsHost","Featured","Info","ClaimButton"},
    PlaytimeGifts = {"MiddleGui","TabContainer","PlaytimePanel","Main","ContentArea","TabHost","PlaytimeCanvas","PlaytimeRewardsHost","Inner","Slots","Gifts"},
}

local function activate(path, label)
    local gui = getPlayerGui()
    local button = gui and resolve(gui, path)
    if not button or not button:IsA("GuiButton") or not button.Visible then
        return false, "button unavailable"
    end
    return doAction(label, function()
        button:Activate()
        return true
    end)
end

local function getState()
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    local function stat(name)
        local v = leaderstats and leaderstats:FindFirstChild(name)
        return v and v.Value or nil
    end

    return {
        Level = stat("Level"),
        Honey = stat("Honey"),
        Hatches = stat("Hatches"),
        EquippedPickaxeId = LocalPlayer:GetAttribute("EquippedPickaxeId"),
        ShovelEquipped = LocalPlayer:GetAttribute("ShovelEquipped"),
        EquippedAxeId = LocalPlayer:GetAttribute("EquippedAxeId"),
        EquippedNetId = LocalPlayer:GetAttribute("EquippedNetId"),
        EquippedFishingRodId = LocalPlayer:GetAttribute("EquippedFishingRodId"),
        ActiveHoldRevision = LocalPlayer:GetAttribute("ActiveHoldRevision"),
        BeeCombatTargetMobId = LocalPlayer:GetAttribute("BeeCombatTargetMobId"),
        BeeCombatTargetFieldDb = LocalPlayer:GetAttribute("BeeCombatTargetFieldDb"),
        SelectedMobId = LocalPlayer:GetAttribute("SelectedMobId"),
        GripHoldKind = LocalPlayer:GetAttribute("GripHoldKind"),
    }
end

local function findMobs()
    local world = workspace:FindFirstChild("World1")
    local runtime = world and world:FindFirstChild("Runtime")
    local mobsFolder = runtime and runtime:FindFirstChild("Mobs")
    local out = {}
    if not mobsFolder then return out end

    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    for _, mob in ipairs(mobsFolder:GetChildren()) do
        local click = mob:FindFirstChild("BeeMobTargetClick", true)
        if click and click:IsA("ClickDetector") then
            local part = mob.PrimaryPart or mob:FindFirstChildWhichIsA("BasePart", true)
            local distance = (hrp and part) and (hrp.Position - part.Position).Magnitude or math.huge
            table.insert(out, {mob = mob, click = click, distance = distance})
        end
    end
    table.sort(out, function(a,b) return a.distance < b.distance end)
    return out
end

local function worldInteract(target, kind)
    return doAction("WorldInteract:" .. tostring(kind), function()
        -- Adapter point: use only normal/authorized interaction in your environment.
        -- Example for Studio-owned tests: fireclickdetector(target)
        if typeof(getgenv) == "function" then
            local env = getgenv()
            if type(env.BeeconomyWorldInteract) == "function" then
                return env.BeeconomyWorldInteract(target, kind)
            end
        end
        error("Define getgenv().BeeconomyWorldInteract(target, kind) for your authorized environment")
    end)
end

local function farmStep()
    if not Config.FarmEnabled then return end
    local s = getState()
    if not s.ShovelEquipped then
        activate(GUI.Shovel, "Equip shovel")
        return
    end

    if typeof(getgenv) == "function" then
        local env = getgenv()
        if type(env.BeeconomyFarmField) == "function" then
            doAction("Farm " .. tostring(s.BeeCombatTargetFieldDb or Config.PreferredField), function()
                return env.BeeconomyFarmField(s.BeeCombatTargetFieldDb or Config.PreferredField, s)
            end)
        end
    end
end

local function mobStep()
    if not Config.MobEnabled then return end
    local mobs = findMobs()
    if mobs[1] then
        worldInteract(mobs[1].click, "BeeMobTargetClick")
    end
end

local function fishingStep()
    if not Config.FishingEnabled then return end
    local world = workspace:FindFirstChild("World1")
    local water = world and world:FindFirstChild("Water")
    local click = water and water:FindFirstChild("FishingWaterClick", true)
    if not click then return end
    activate(GUI.FishingRod, "Equip fishing rod")
    worldInteract(click, "FishingWaterClick")
end

local function claimDaily()
    activate(GUI.Playtime, "Open playtime")
    task.wait(0.2)
    activate(GUI.DailyClaim, "Claim daily reward")
end

local function claimPlaytime()
    activate(GUI.Playtime, "Open playtime")
    task.wait(0.2)
    local gui = getPlayerGui()
    local gifts = gui and resolve(gui, GUI.PlaytimeGifts)
    if not gifts then return end
    for _, gift in ipairs(gifts:GetChildren()) do
        local claim = gift:FindFirstChild("ClaimButton", true)
        if claim and claim:IsA("GuiButton") and claim.Visible then
            doAction("Claim playtime " .. gift.Name, function()
                claim:Activate()
                return true
            end)
            task.wait(Config.MinActionGap)
        end
    end
end

local function questAssistStep()
    if not Config.QuestAssist then return end
    local gui = getPlayerGui()
    local box = gui and resolve(gui, {"MiddleGui","QuestBox"})
    if not box then return end

    local text = {}
    for _, d in ipairs(box:GetDescendants()) do
        if d:IsA("TextLabel") and d.Visible and d.Text ~= "" then
            table.insert(text, string.lower(d.Text))
        end
    end
    local joined = table.concat(text, " ")

    if string.find(joined, "pollen", 1, true) or string.find(joined, "honey", 1, true) then
        Config.FarmEnabled = true
    elseif string.find(joined, "mob", 1, true) or string.find(joined, "ladybug", 1, true) or string.find(joined, "spider", 1, true) or string.find(joined, "snail", 1, true) or string.find(joined, "boss", 1, true) then
        Config.MobEnabled = true
    elseif string.find(joined, "fish", 1, true) then
        Config.FishingEnabled = true
    elseif string.find(joined, "craft", 1, true) then
        activate(GUI.Craft, "Open craft for quest")
    end
end

-- WindUI loader. Replace URL with the exact WindUI source you trust/use.
local WindUI
local ok, err = pcall(function()
    local env = (typeof(getgenv) == "function") and getgenv() or _G
    if env.WindUI then
        WindUI = env.WindUI
        return
    end

    local url = env.WindUIUrl
    assert(type(url) == "string" and #url > 0, "Set getgenv().WindUIUrl to your trusted WindUI raw source")
    WindUI = loadstring(game:HttpGet(url))()
end)

if not ok then
    warn("[Beeconomy] WindUI load failed:", err)
    return
end

local Window = WindUI:CreateWindow({
    Title = "Beeconomy Automation",
    Icon = "bee",
    Author = "ZEBUXHUBBY",
    Folder = "Beeconomy",
    Size = UDim2.fromOffset(580, 460),
    Transparent = true,
    Theme = "Dark",
    Resizable = true,
})

local FarmTab = Window:Tab({Title = "Automation", Icon = "sprout"})
local RewardTab = Window:Tab({Title = "Rewards", Icon = "gift"})
local DebugTab = Window:Tab({Title = "Debug", Icon = "bug"})

FarmTab:Toggle({
    Title = "Dry Run",
    Desc = "Log actions without performing them",
    Value = Config.DryRun,
    Callback = function(v) Config.DryRun = v end,
})

FarmTab:Toggle({
    Title = "Auto Farm",
    Value = Config.FarmEnabled,
    Callback = function(v) Config.FarmEnabled = v end,
})

FarmTab:Toggle({
    Title = "Auto Mobs",
    Value = Config.MobEnabled,
    Callback = function(v) Config.MobEnabled = v end,
})

FarmTab:Toggle({
    Title = "Auto Fishing",
    Value = Config.FishingEnabled,
    Callback = function(v) Config.FishingEnabled = v end,
})

FarmTab:Toggle({
    Title = "Quest Assist",
    Desc = "Reads visible quest text and enables the matching normal automation module",
    Value = Config.QuestAssist,
    Callback = function(v) Config.QuestAssist = v end,
})

RewardTab:Button({Title = "Claim Daily Reward", Callback = claimDaily})
RewardTab:Button({Title = "Claim Playtime Rewards", Callback = claimPlaytime})

DebugTab:Button({
    Title = "Print Current State",
    Callback = function()
        local s = getState()
        for k,v in pairs(s) do print(k, v) end
    end,
})

DebugTab:Paragraph({
    Title = "Potential bug testing",
    Desc = "The supplied report marks the obfuscated remotes as hypotheses and unresolved runtime-ID surfaces. Live replay/fuzzing is intentionally not wired here. Use a dev/test endpoint you control for state-machine, rate-policy, and spatial-validation checks.",
})

-- Main scheduler

task.spawn(function()
    while State.Running do
        questAssistStep()
        farmStep()
        mobStep()
        fishingStep()
        task.wait(0.5)
    end
end)

log("Loaded with WindUI. DryRun =", Config.DryRun)
