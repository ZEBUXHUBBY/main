-- Beeconomy Automation Harness with Rayfield shell
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

-- Rayfield loader.
local Rayfield
local ok, err = pcall(function()
    local env = (typeof(getgenv) == "function") and getgenv() or _G
    if env.Rayfield then
        Rayfield = env.Rayfield
        return
    end

    local url = env.RayfieldUrl or "https://sirius.menu/rayfield"
    Rayfield = loadstring(game:HttpGet(url))()
end)

if not ok or not Rayfield then
    warn("[Beeconomy] Rayfield load failed:", err)
    return
end

local Window = Rayfield:CreateWindow({
    Name = "Beeconomy Automation",
    Icon = 0,
    LoadingTitle = "Beeconomy Automation",
    LoadingSubtitle = "by ZEBUXHUBBY",
    ShowText = "Beeconomy",
    Theme = "Default",
    ToggleUIKeybind = "K",
    DisableRayfieldPrompts = false,
    DisableBuildWarnings = false,
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "Beeconomy",
        FileName = "AutomationConfig"
    },
    Discord = {
        Enabled = false,
        Invite = "",
        RememberJoins = true
    },
    KeySystem = false,
})

local AutomationTab = Window:CreateTab("Automation", 4483362458)
local RewardsTab = Window:CreateTab("Rewards", 4483362458)
local DebugTab = Window:CreateTab("Debug", 4483362458)

AutomationTab:CreateSection("Main")

AutomationTab:CreateToggle({
    Name = "Dry Run",
    CurrentValue = Config.DryRun,
    Flag = "DryRun",
    Callback = function(v)
        Config.DryRun = v
    end,
})

AutomationTab:CreateToggle({
    Name = "Auto Farm",
    CurrentValue = Config.FarmEnabled,
    Flag = "AutoFarm",
    Callback = function(v)
        Config.FarmEnabled = v
    end,
})

AutomationTab:CreateToggle({
    Name = "Auto Mobs",
    CurrentValue = Config.MobEnabled,
    Flag = "AutoMobs",
    Callback = function(v)
        Config.MobEnabled = v
    end,
})

AutomationTab:CreateToggle({
    Name = "Auto Fishing",
    CurrentValue = Config.FishingEnabled,
    Flag = "AutoFishing",
    Callback = function(v)
        Config.FishingEnabled = v
    end,
})

AutomationTab:CreateToggle({
    Name = "Quest Assist",
    CurrentValue = Config.QuestAssist,
    Flag = "QuestAssist",
    Callback = function(v)
        Config.QuestAssist = v
    end,
})

AutomationTab:CreateInput({
    Name = "Preferred Field",
    CurrentValue = Config.PreferredField,
    PlaceholderText = "Dandelion",
    RemoveTextAfterFocusLost = false,
    Flag = "PreferredField",
    Callback = function(value)
        if type(value) == "string" and value ~= "" then
            Config.PreferredField = value
        end
    end,
})

AutomationTab:CreateSlider({
    Name = "Minimum Action Gap",
    Range = {0.1, 2.0},
    Increment = 0.05,
    Suffix = "s",
    CurrentValue = Config.MinActionGap,
    Flag = "ActionGap",
    Callback = function(value)
        Config.MinActionGap = value
    end,
})

RewardsTab:CreateSection("Normal UI Claims")

RewardsTab:CreateButton({
    Name = "Claim Daily Reward",
    Callback = claimDaily,
})

RewardsTab:CreateButton({
    Name = "Claim Playtime Rewards",
    Callback = claimPlaytime,
})

DebugTab:CreateSection("State")

DebugTab:CreateButton({
    Name = "Print Current State",
    Callback = function()
        local s = getState()
        for k, v in pairs(s) do
            print("[Beeconomy State]", k, v)
        end
    end,
})

DebugTab:CreateButton({
    Name = "Print Nearby Mobs",
    Callback = function()
        for index, entry in ipairs(findMobs()) do
            print(string.format("[Beeconomy Mob %d] %s | %.2f studs", index, entry.mob.Name, entry.distance))
        end
    end,
})

DebugTab:CreateParagraph({
    Title = "Potential bug testing",
    Content = "The mapper report marks the obfuscated remotes as hypotheses/unresolved surfaces. Live replay or fuzzing is not wired into this automation build."
})

task.spawn(function()
    while State.Running do
        questAssistStep()
        farmStep()
        mobStep()
        fishingStep()
        task.wait(0.5)
    end
end)

Rayfield:Notify({
    Title = "Beeconomy",
    Content = "Rayfield automation harness loaded",
    Duration = 5,
})

log("Loaded with Rayfield. DryRun =", Config.DryRun)
