--[[
    Anime Stars - Aggressive Farm V3
    PlaceId: 122553263569744

    What this does
    - Detects live monsters from Workspace.Zones.<zone>.Characters by matching model UUID
      to Workspace.Zones.<zone>.Spawners.
    - Instantly hops to the nearest live monster and stays inside attack range.
    - Switches targets immediately when the current monster disappears/dies.
    - Pre-positions at the nearest spawner while waiting for respawn.
    - Optional noclip while farming.
    - Auto faces the target.
    - Auto M1 through executor mouse input / VirtualInputManager fallback.
    - Uses the game's existing server->client event bus only for fast retarget signals.

    Boundary
    - Does NOT call conch_networking/admin/role remotes.
    - Does NOT invoke BetterTween request remotes.
    - Does NOT spoof rewards, duplicate items, or bypass server authorization.
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local EXPECTED_PLACE_ID = 122553263569744

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    error("LocalPlayer unavailable")
end

local ENV = (type(getgenv) == "function" and getgenv()) or _G
if type(ENV.__ANIME_STARS_FARM_V3_CLEANUP) == "function" then
    pcall(ENV.__ANIME_STARS_FARM_V3_CLEANUP)
end

local WindUI = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"
))()

local Config = {
    Enabled = false,
    AutoM1 = true,
    Noclip = true,
    FaceTarget = true,
    PrePositionSpawner = true,
    FollowMovingTarget = true,

    TargetDistance = 4.0,
    HeightOffset = 0.0,
    AttackInterval = 0.12,
    RetargetInterval = 0.10,
    FollowInterval = 0.05,
    SpawnerOffset = 2.0,

    ZoneFilter = "", -- blank = all loaded zones
}

local State = {
    Version = 3,
    CurrentZone = nil,
    CurrentTarget = nil,
    CurrentSpawner = nil,
    TargetChangedAt = 0,
    LastAttack = 0,
    LastRetarget = 0,
    LastFollow = 0,
    KillsObserved = 0,
    RespawnsObserved = 0,
    Teleports = 0,
    Attacks = 0,
    Status = "IDLE",
}

local Connections = {}
local OriginalCanCollide = setmetatable({}, { __mode = "k" })
local Window
local HudGui
local HudLabel

local function notify(title, content, duration)
    pcall(function()
        WindUI:Notify({
            Title = title,
            Content = content,
            Duration = duration or 4,
        })
    end)
end

local function resolve(root, ...)
    local node = root
    for i = 1, select("#", ...) do
        node = node and node:FindFirstChild(select(i, ...))
        if not node then return nil end
    end
    return node
end

local function getCharacter()
    local character = LocalPlayer.Character
    if not character then return nil end
    local root = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then
        return nil
    end
    return character, root, humanoid
end

local function getZonesFolder()
    return workspace:FindFirstChild("Zones")
end

local function zoneAllowed(zone)
    if not zone or not zone:IsA("Folder") then
        return false
    end
    if Config.ZoneFilter == "" then
        return true
    end
    return string.lower(zone.Name) == string.lower(Config.ZoneFilter)
end

-- A model is treated as a live monster only when its UUID also exists in that zone's Spawners folder.
-- This avoids accidentally targeting players/NPCs that also live under a Characters folder.
local function getEnemyInfo(model, zone)
    if not model or not model:IsA("Model") or not zone then
        return nil
    end

    local spawners = zone:FindFirstChild("Spawners")
    if not spawners then return nil end

    local spawner = spawners:FindFirstChild(model.Name)
    if not spawner or not spawner:IsA("BasePart") then
        return nil
    end

    local root = model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")

    if not root or not root:IsA("BasePart") then
        return nil
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health <= 0 then
        return nil
    end

    return {
        Model = model,
        Root = root,
        Humanoid = humanoid,
        Spawner = spawner,
        Zone = zone,
    }
end

local function collectEnemies()
    local zones = getZonesFolder()
    if not zones then return {} end

    local result = {}
    for _, zone in ipairs(zones:GetChildren()) do
        if zoneAllowed(zone) then
            local chars = zone:FindFirstChild("Characters")
            if chars then
                for _, model in ipairs(chars:GetChildren()) do
                    local info = getEnemyInfo(model, zone)
                    if info then
                        result[#result + 1] = info
                    end
                end
            end
        end
    end
    return result
end

local function nearestEnemy()
    local _, root = getCharacter()
    if not root then return nil end

    local best, bestDistance
    for _, info in ipairs(collectEnemies()) do
        local distance = (info.Root.Position - root.Position).Magnitude
        if not bestDistance or distance < bestDistance then
            best = info
            bestDistance = distance
        end
    end
    return best, bestDistance
end

local function nearestSpawner()
    local _, root = getCharacter()
    local zones = getZonesFolder()
    if not root or not zones then return nil end

    local best, bestDistance, bestZone
    for _, zone in ipairs(zones:GetChildren()) do
        if zoneAllowed(zone) then
            local spawners = zone:FindFirstChild("Spawners")
            if spawners then
                for _, part in ipairs(spawners:GetChildren()) do
                    if part:IsA("BasePart") then
                        local distance = (part.Position - root.Position).Magnitude
                        if not bestDistance or distance < bestDistance then
                            best = part
                            bestDistance = distance
                            bestZone = zone
                        end
                    end
                end
            end
        end
    end
    return best, bestDistance, bestZone
end

local function setTarget(info)
    if State.CurrentTarget == (info and info.Model or nil) then
        return
    end

    State.CurrentTarget = info and info.Model or nil
    State.CurrentSpawner = info and info.Spawner or nil
    State.CurrentZone = info and info.Zone or nil
    State.TargetChangedAt = os.clock()

    if info then
        State.Status = "TARGET: " .. info.Model.Name
    else
        State.Status = "WAITING"
    end
end

local function targetValid()
    local target = State.CurrentTarget
    local zone = State.CurrentZone
    if not target or not zone or not target.Parent then
        return false
    end
    return getEnemyInfo(target, zone) ~= nil
end

local function teleportNear(part, distance, height)
    local _, root = getCharacter()
    if not root or not part or not part.Parent then return false end

    distance = distance or Config.TargetDistance
    height = height or Config.HeightOffset

    local targetPos = part.Position
    local look = part.CFrame.LookVector
    if look.Magnitude < 0.1 then
        look = Vector3.new(0, 0, -1)
    end

    -- Place behind the target so the character is in melee range without occupying the same point.
    local position = targetPos - (look.Unit * distance) + Vector3.new(0, height, 0)
    root.CFrame = CFrame.lookAt(position, targetPos)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    State.Teleports += 1
    return true
end

local function faceTarget(info)
    if not Config.FaceTarget or not info then return end
    local _, root = getCharacter()
    if not root or not info.Root.Parent then return end

    local p = root.Position
    local t = info.Root.Position
    local flat = Vector3.new(t.X, p.Y, t.Z)
    if (flat - p).Magnitude > 0.1 then
        root.CFrame = CFrame.lookAt(p, flat)
    end
end

local function setNoclip(enabled)
    local character = LocalPlayer.Character
    if not character then return end

    for _, obj in ipairs(character:GetDescendants()) do
        if obj:IsA("BasePart") then
            if enabled then
                if OriginalCanCollide[obj] == nil then
                    OriginalCanCollide[obj] = obj.CanCollide
                end
                obj.CanCollide = false
            else
                local original = OriginalCanCollide[obj]
                if original ~= nil then
                    obj.CanCollide = original
                    OriginalCanCollide[obj] = nil
                end
            end
        end
    end
end

local function clickM1()
    if not Config.AutoM1 then return end
    local now = os.clock()
    if now - State.LastAttack < Config.AttackInterval then
        return
    end
    State.LastAttack = now

    local ok = false

    if type(mouse1click) == "function" then
        ok = pcall(mouse1click)
    elseif type(mouse1press) == "function" and type(mouse1release) == "function" then
        ok = pcall(function()
            mouse1press()
            task.wait()
            mouse1release()
        end)
    end

    if not ok then
        ok = pcall(function()
            local camera = workspace.CurrentCamera
            local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
            local x, y = viewport.X / 2, viewport.Y / 2
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
    end

    if ok then
        State.Attacks += 1
    end
end

local function prePositionSpawner()
    if not Config.PrePositionSpawner then return false end
    local spawner, _, zone = nearestSpawner()
    if not spawner then return false end

    State.CurrentSpawner = spawner
    State.CurrentZone = zone
    State.Status = "PRE-SPAWN: " .. spawner.Name
    return teleportNear(spawner, Config.SpawnerOffset, Config.HeightOffset)
end

local function retarget(force)
    local now = os.clock()
    if not force and now - State.LastRetarget < Config.RetargetInterval then
        return
    end
    State.LastRetarget = now

    if targetValid() then
        return
    end

    local info = nearestEnemy()
    setTarget(info)

    if info then
        teleportNear(info.Root)
    else
        prePositionSpawner()
    end
end

local function farmStep()
    if not Config.Enabled then
        State.Status = "IDLE"
        return
    end

    local now = os.clock()
    retarget(false)

    if targetValid() then
        local info = getEnemyInfo(State.CurrentTarget, State.CurrentZone)
        if info then
            State.Status = "FARMING " .. info.Model.Name

            if Config.FollowMovingTarget and now - State.LastFollow >= Config.FollowInterval then
                State.LastFollow = now
                local _, root = getCharacter()
                if root then
                    local distance = (info.Root.Position - root.Position).Magnitude
                    if distance > math.max(Config.TargetDistance + 2, 7) then
                        teleportNear(info.Root)
                    else
                        faceTarget(info)
                    end
                end
            end

            clickM1()
        end
    else
        State.Status = "WAITING RESPAWN"
    end
end

local function getEventsRemote()
    return resolve(ReplicatedStorage, "Shared", "Packages", "Events", "RemoteEvent")
end

local function onIncomingItem(item)
    if type(item) ~= "table" or type(item.Path) ~= "string" then return end
    local path = item.Path

    if path == "enemies/died" then
        State.KillsObserved += 1
        -- Do not wait for the next polling tick: invalidate and hop immediately.
        State.CurrentTarget = nil
        task.defer(function()
            if Config.Enabled then retarget(true) end
        end)
    elseif path == "enemies/respawned" then
        State.RespawnsObserved += 1
        task.defer(function()
            if Config.Enabled then retarget(true) end
        end)
    elseif path == "character/refresh" then
        State.CurrentTarget = nil
        task.delay(0.15, function()
            if Config.Enabled then retarget(true) end
        end)
    end
end

local function startEventObserver()
    local remote = getEventsRemote()
    if not remote or not remote:IsA("RemoteEvent") then return end

    Connections.Incoming = remote.OnClientEvent:Connect(function(payload)
        if type(payload) ~= "table" then return end
        local array = false
        for _, item in ipairs(payload) do
            array = true
            onIncomingItem(item)
        end
        if not array then
            onIncomingItem(payload)
        end
    end)
end

local function bindZoneSignals()
    local zones = getZonesFolder()
    if not zones then return end

    local function bindZone(zone)
        if not zone:IsA("Folder") then return end
        local chars = zone:FindFirstChild("Characters")
        if not chars then return end

        local keyAdd = "CharsAdd_" .. zone.Name
        local keyRemove = "CharsRemove_" .. zone.Name

        if Connections[keyAdd] then Connections[keyAdd]:Disconnect() end
        if Connections[keyRemove] then Connections[keyRemove]:Disconnect() end

        Connections[keyAdd] = chars.ChildAdded:Connect(function(model)
            if not Config.Enabled or not zoneAllowed(zone) then return end
            task.defer(function()
                if getEnemyInfo(model, zone) then
                    retarget(true)
                end
            end)
        end)

        Connections[keyRemove] = chars.ChildRemoved:Connect(function(model)
            if model == State.CurrentTarget then
                State.CurrentTarget = nil
                if Config.Enabled then
                    task.defer(function() retarget(true) end)
                end
            end
        end)
    end

    for _, zone in ipairs(zones:GetChildren()) do
        bindZone(zone)
    end

    Connections.ZoneAdded = zones.ChildAdded:Connect(function(zone)
        task.defer(function() bindZone(zone) end)
    end)
end

local function createHud()
    if HudGui then HudGui:Destroy() end

    HudGui = Instance.new("ScreenGui")
    HudGui.Name = "AnimeStarsFarmV3HUD"
    HudGui.ResetOnSpawn = false
    HudGui.IgnoreGuiInset = false
    HudGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.Name = "Panel"
    frame.AnchorPoint = Vector2.new(1, 0)
    frame.Position = UDim2.new(1, -16, 0, 76)
    frame.Size = UDim2.fromOffset(330, 122)
    frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    frame.BackgroundTransparency = 0.12
    frame.BorderSizePixel = 0
    frame.Parent = HudGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame

    HudLabel = Instance.new("TextLabel")
    HudLabel.BackgroundTransparency = 1
    HudLabel.Position = UDim2.fromOffset(12, 10)
    HudLabel.Size = UDim2.new(1, -24, 1, -20)
    HudLabel.Font = Enum.Font.Code
    HudLabel.TextSize = 14
    HudLabel.TextColor3 = Color3.new(1, 1, 1)
    HudLabel.TextXAlignment = Enum.TextXAlignment.Left
    HudLabel.TextYAlignment = Enum.TextYAlignment.Top
    HudLabel.TextWrapped = false
    HudLabel.Parent = frame
end

local function refreshHud()
    if not HudLabel then return end
    local target = State.CurrentTarget and State.CurrentTarget.Name or "none"
    local zone = State.CurrentZone and State.CurrentZone.Name or "auto"
    HudLabel.Text = string.format(
        "AGGRESSIVE FARM V3\nStatus: %s\nZone: %s | Target: %s\nKills: %d | Respawns: %d\nHops: %d | M1: %d",
        State.Status,
        zone,
        target,
        State.KillsObserved,
        State.RespawnsObserved,
        State.Teleports,
        State.Attacks
    )
end

local function buildUi()
    Window = WindUI:CreateWindow({
        Title = "Anime Stars | Aggressive Farm V3",
        Folder = "AnimeStarsFarmV3",
        Icon = "zap",
        NewElements = true,
        HideSearchBar = false,
        OpenButton = {
            Title = "Farm V3",
            Enabled = true,
            Draggable = true,
            OnlyMobile = false,
        },
    })

    local Farm = Window:Tab({
        Title = "Aggressive Farm",
        Icon = "swords",
        Border = true,
    })

    Farm:Toggle({
        Title = "Enable Aggressive Auto Farm",
        Desc = "Instant target-hop + stay in melee range + auto M1",
        Value = false,
        Callback = function(v)
            Config.Enabled = v == true
            if Config.Enabled then
                State.Status = "STARTING"
                retarget(true)
                notify("Aggressive Farm", "Enabled", 3)
            else
                State.CurrentTarget = nil
                State.Status = "IDLE"
                setNoclip(false)
                notify("Aggressive Farm", "Disabled", 3)
            end
        end,
    })

    Farm:Toggle({
        Title = "Auto M1",
        Desc = "Clicks M1 continuously while a monster is targeted",
        Value = Config.AutoM1,
        Callback = function(v) Config.AutoM1 = v == true end,
    })

    Farm:Toggle({
        Title = "Follow / Re-stick to Monster",
        Desc = "If the target moves away, instantly return to attack range",
        Value = Config.FollowMovingTarget,
        Callback = function(v) Config.FollowMovingTarget = v == true end,
    })

    Farm:Toggle({
        Title = "Noclip While Farming",
        Value = Config.Noclip,
        Callback = function(v) Config.Noclip = v == true end,
    })

    Farm:Toggle({
        Title = "Pre-position at Spawner",
        Desc = "When no live monster exists, wait directly at nearest spawner",
        Value = Config.PrePositionSpawner,
        Callback = function(v) Config.PrePositionSpawner = v == true end,
    })

    Farm:Slider({
        Title = "Target Distance",
        Step = 0.5,
        Value = { Min = 1, Max = 12, Default = Config.TargetDistance },
        Callback = function(v) Config.TargetDistance = tonumber(v) or 4 end,
    })

    Farm:Slider({
        Title = "M1 Interval",
        Desc = "Lower = more aggressive input; server still decides accepted attacks",
        Step = 0.01,
        Value = { Min = 0.05, Max = 0.50, Default = Config.AttackInterval },
        Callback = function(v) Config.AttackInterval = tonumber(v) or 0.12 end,
    })

    Farm:Input({
        Title = "Zone Filter",
        Desc = "Blank = any loaded zone. Example: skylands",
        Placeholder = "skylands",
        Value = Config.ZoneFilter,
        Callback = function(v)
            Config.ZoneFilter = tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", "")
            State.CurrentTarget = nil
            if Config.Enabled then retarget(true) end
        end,
    })

    Farm:Button({
        Title = "Force Retarget Now",
        Callback = function()
            State.CurrentTarget = nil
            retarget(true)
        end,
    })

    local Utility = Window:Tab({
        Title = "Utility",
        Icon = "settings",
        Border = true,
    })

    Utility:Button({
        Title = "Teleport to Nearest Live Monster",
        Callback = function()
            local info = nearestEnemy()
            if info then
                setTarget(info)
                teleportNear(info.Root)
            else
                notify("Farm V3", "No live monster found", 3)
            end
        end,
    })

    Utility:Button({
        Title = "Teleport to Nearest Spawner",
        Callback = function()
            if not prePositionSpawner() then
                notify("Farm V3", "No spawner found", 3)
            end
        end,
    })

    Utility:Button({
        Title = "Open Game Automation UI",
        Desc = "Use the game's native Auto Abilities together with V3",
        Callback = function()
            local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            local automation = playerGui and resolve(playerGui, "Main", "Container", "Automation")
            if automation and automation:IsA("GuiObject") then
                automation.Visible = true
                notify("Game Automation", "Opened native Automation UI", 3)
            else
                notify("Game Automation", "Automation frame was not found", 3)
            end
        end,
    })

    local About = Window:Tab({
        Title = "Info",
        Icon = "info",
        Border = true,
    })

    About:Paragraph({
        Title = "Target detection",
        Desc = "V3 only targets models in Workspace.Zones.<zone>.Characters whose UUID also exists in the same zone's Spawners folder. This is based on the observed Anime Stars world structure and avoids selecting players/NPC dialogue characters.",
    })

    About:Paragraph({
        Title = "What V3 deliberately does not do",
        Desc = "No conch admin/role calls, no reward spoofing/duping, and no BetterTween unknown-protocol calls. The aggressive part is movement/target switching/input automation, while the server remains authoritative for accepted combat and rewards.",
    })
end

Connections.Heartbeat = RunService.Heartbeat:Connect(function()
    if Config.Enabled and Config.Noclip then
        setNoclip(true)
    elseif not Config.Enabled then
        setNoclip(false)
    end

    farmStep()
    refreshHud()
end)

Connections.CharacterAdded = LocalPlayer.CharacterAdded:Connect(function()
    State.CurrentTarget = nil
    task.delay(0.5, function()
        if Config.Enabled then retarget(true) end
    end)
end)

startEventObserver()
bindZoneSignals()
createHud()
buildUi()

if game.PlaceId ~= EXPECTED_PLACE_ID then
    notify("Place mismatch", "This V3 was built for PlaceId " .. tostring(EXPECTED_PLACE_ID), 7)
end

ENV.__ANIME_STARS_FARM_V3_STATE = State
ENV.__ANIME_STARS_FARM_V3_CONFIG = Config
ENV.__ANIME_STARS_FARM_V3_CLEANUP = function()
    Config.Enabled = false
    setNoclip(false)

    for key, connection in pairs(Connections) do
        if connection then
            pcall(function() connection:Disconnect() end)
        end
        Connections[key] = nil
    end

    if HudGui then
        pcall(function() HudGui:Destroy() end)
        HudGui = nil
    end

    if Window then
        pcall(function() Window:Destroy() end)
        Window = nil
    end
end

notify("Aggressive Farm V3", "Loaded. Enable Aggressive Auto Farm in WindUI.", 5)
