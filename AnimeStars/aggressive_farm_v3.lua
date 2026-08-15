--[[
    Anime Stars - Aggressive Farm V3.1
    PlaceId: 122553263569744

    Fixes in 3.1
    - No hard dependency on VirtualInputManager.
    - WindUI failure no longer kills the script; a fallback UI is created.
    - M1 capability chain: mouse1click -> mouse1press/release -> VirtualInputManager -> VirtualUser.
    - Bootstrap/status errors are visible in console + HUD.
    - Targeting remains UUID<->Spawner based to avoid players/NPCs.

    Boundary
    - No conch/admin/role remotes.
    - No reward spoofing/duping.
    - No unknown BetterTween remote calls.
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local EXPECTED_PLACE_ID = 122553263569744

local function boot(msg)
    warn("[AnimeStars Farm V3.1] " .. tostring(msg))
end

local function safeService(name)
    local ok, service = pcall(function()
        return game:GetService(name)
    end)
    if ok then return service end
    boot("Service unavailable: " .. name .. " | " .. tostring(service))
    return nil
end

local Players = safeService("Players")
local ReplicatedStorage = safeService("ReplicatedStorage")
local RunService = safeService("RunService")
local VirtualInputManager = safeService("VirtualInputManager")
local VirtualUser = safeService("VirtualUser")

if not Players or not ReplicatedStorage or not RunService then
    error("[AnimeStars Farm V3.1] Required Roblox services unavailable")
end

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    error("[AnimeStars Farm V3.1] LocalPlayer unavailable")
end

local ENV = (type(getgenv) == "function" and getgenv()) or _G
if type(ENV.__ANIME_STARS_FARM_V3_CLEANUP) == "function" then
    pcall(ENV.__ANIME_STARS_FARM_V3_CLEANUP)
end

local WindUI
local windOk, windResult = pcall(function()
    local source = game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua")
    return loadstring(source)()
end)
if windOk then
    WindUI = windResult
    boot("WindUI loaded")
else
    boot("WindUI failed; fallback UI will be used | " .. tostring(windResult))
end

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
    NoclipInterval = 0.10,
    SpawnerOffset = 2.0,

    ZoneFilter = "",
}

local State = {
    Version = "3.1",
    CurrentZone = nil,
    CurrentTarget = nil,
    CurrentSpawner = nil,
    LastAttack = 0,
    LastRetarget = 0,
    LastFollow = 0,
    LastNoclip = 0,
    KillsObserved = 0,
    RespawnsObserved = 0,
    Teleports = 0,
    Attacks = 0,
    InputMode = "detecting",
    Status = "BOOTING",
    LastError = nil,
}

local Connections = {}
local OriginalCanCollide = setmetatable({}, { __mode = "k" })
local Window
local HudGui
local HudLabel
local FallbackGui

local function setError(where, err)
    State.LastError = tostring(where) .. ": " .. tostring(err)
    boot(State.LastError)
end

local function notify(title, content, duration)
    if WindUI then
        pcall(function()
            WindUI:Notify({
                Title = title,
                Content = content,
                Duration = duration or 4,
            })
        end)
    else
        boot(title .. " | " .. tostring(content))
    end
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
    if not root or not humanoid or humanoid.Health <= 0 then return nil end
    return character, root, humanoid
end

local function getZonesFolder()
    return workspace:FindFirstChild("Zones")
end

local function zoneAllowed(zone)
    if not zone then return false end
    if Config.ZoneFilter == "" then return true end
    return string.lower(zone.Name) == string.lower(Config.ZoneFilter)
end

local function getEnemyInfo(model, zone)
    if not model or not model:IsA("Model") or not zone then return nil end

    local spawners = zone:FindFirstChild("Spawners")
    if not spawners then return nil end

    local spawner = spawners:FindFirstChild(model.Name)
    if not spawner or not spawner:IsA("BasePart") then return nil end

    local root = model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")
    if not root or not root:IsA("BasePart") then return nil end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health <= 0 then return nil end

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
                    if info then result[#result + 1] = info end
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
                            best, bestDistance, bestZone = part, distance, zone
                        end
                    end
                end
            end
        end
    end
    return best, bestDistance, bestZone
end

local function setTarget(info)
    local nextModel = info and info.Model or nil
    if State.CurrentTarget == nextModel then return end

    State.CurrentTarget = nextModel
    State.CurrentSpawner = info and info.Spawner or nil
    State.CurrentZone = info and info.Zone or nil
    State.Status = info and ("TARGET " .. info.Model.Name) or "WAITING"
end

local function targetInfo()
    if not State.CurrentTarget or not State.CurrentZone then return nil end
    if not State.CurrentTarget.Parent then return nil end
    return getEnemyInfo(State.CurrentTarget, State.CurrentZone)
end

local function teleportNear(part, distance, height)
    local _, root = getCharacter()
    if not root or not part or not part.Parent then return false end

    distance = distance or Config.TargetDistance
    height = height or Config.HeightOffset

    local targetPos = part.Position
    local look = part.CFrame.LookVector
    if look.Magnitude < 0.1 then look = Vector3.new(0, 0, -1) end

    local position = targetPos - (look.Unit * distance) + Vector3.new(0, height, 0)
    local ok, err = pcall(function()
        root.CFrame = CFrame.lookAt(position, targetPos)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
    if not ok then
        setError("teleportNear", err)
        return false
    end

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
        pcall(function()
            root.CFrame = CFrame.lookAt(p, flat)
        end)
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
                local old = OriginalCanCollide[obj]
                if old ~= nil then
                    obj.CanCollide = old
                    OriginalCanCollide[obj] = nil
                end
            end
        end
    end
end

local function detectInputMode()
    if type(mouse1click) == "function" then
        State.InputMode = "mouse1click"
    elseif type(mouse1press) == "function" and type(mouse1release) == "function" then
        State.InputMode = "mouse1press/release"
    elseif VirtualInputManager then
        State.InputMode = "VirtualInputManager"
    elseif VirtualUser then
        State.InputMode = "VirtualUser"
    else
        State.InputMode = "UNAVAILABLE"
    end
    boot("M1 input mode: " .. State.InputMode)
end

detectInputMode()

local function clickM1()
    if not Config.AutoM1 then return end
    local now = os.clock()
    if now - State.LastAttack < Config.AttackInterval then return end
    State.LastAttack = now

    local ok = false

    if type(mouse1click) == "function" then
        ok = pcall(mouse1click)
        if ok then State.InputMode = "mouse1click" end
    end

    if not ok and type(mouse1press) == "function" and type(mouse1release) == "function" then
        ok = pcall(function()
            mouse1press()
            task.wait()
            mouse1release()
        end)
        if ok then State.InputMode = "mouse1press/release" end
    end

    if not ok and VirtualInputManager then
        ok = pcall(function()
            local camera = workspace.CurrentCamera
            local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
            local x, y = viewport.X / 2, viewport.Y / 2
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
        if ok then State.InputMode = "VirtualInputManager" end
    end

    if not ok and VirtualUser then
        ok = pcall(function()
            local camera = workspace.CurrentCamera
            VirtualUser:CaptureController()
            VirtualUser:Button1Down(Vector2.new(0, 0), camera and camera.CFrame or CFrame.new())
            task.wait()
            VirtualUser:Button1Up(Vector2.new(0, 0), camera and camera.CFrame or CFrame.new())
        end)
        if ok then State.InputMode = "VirtualUser" end
    end

    if ok then
        State.Attacks += 1
    else
        State.InputMode = "UNAVAILABLE"
    end
end

local function prePositionSpawner()
    if not Config.PrePositionSpawner then return false end
    local spawner, _, zone = nearestSpawner()
    if not spawner then return false end

    State.CurrentSpawner = spawner
    State.CurrentZone = zone
    State.Status = "PRE-SPAWN " .. spawner.Name
    return teleportNear(spawner, Config.SpawnerOffset, Config.HeightOffset)
end

local function retarget(force)
    local now = os.clock()
    if not force and now - State.LastRetarget < Config.RetargetInterval then return end
    State.LastRetarget = now

    if targetInfo() then return end

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

    local info = targetInfo()
    if not info then
        State.Status = "WAITING RESPAWN"
        return
    end

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

local function getEventsRemote()
    return resolve(ReplicatedStorage, "Shared", "Packages", "Events", "RemoteEvent")
end

local function onIncomingItem(item)
    if type(item) ~= "table" or type(item.Path) ~= "string" then return end

    if item.Path == "enemies/died" then
        State.KillsObserved += 1
        State.CurrentTarget = nil
        task.defer(function()
            if Config.Enabled then retarget(true) end
        end)
    elseif item.Path == "enemies/respawned" then
        State.RespawnsObserved += 1
        task.defer(function()
            if Config.Enabled then retarget(true) end
        end)
    elseif item.Path == "character/refresh" then
        State.CurrentTarget = nil
        task.delay(0.2, function()
            if Config.Enabled then retarget(true) end
        end)
    end
end

local function startEventObserver()
    local remote = getEventsRemote()
    if not remote or not remote:IsA("RemoteEvent") then
        boot("Events.RemoteEvent not found; polling retarget still works")
        return
    end

    Connections.Incoming = remote.OnClientEvent:Connect(function(payload)
        if type(payload) ~= "table" then return end
        local hadArrayItem = false
        for _, item in ipairs(payload) do
            hadArrayItem = true
            onIncomingItem(item)
        end
        if not hadArrayItem then onIncomingItem(payload) end
    end)
end

local function bindZoneSignals()
    local zones = getZonesFolder()
    if not zones then
        boot("workspace.Zones not found yet; heartbeat scanner will retry")
        return
    end

    local function bindZone(zone)
        local chars = zone:FindFirstChild("Characters")
        if not chars then return end

        local addKey = "Add_" .. zone.Name
        local removeKey = "Remove_" .. zone.Name
        if Connections[addKey] then pcall(function() Connections[addKey]:Disconnect() end) end
        if Connections[removeKey] then pcall(function() Connections[removeKey]:Disconnect() end) end

        Connections[addKey] = chars.ChildAdded:Connect(function(model)
            if Config.Enabled and zoneAllowed(zone) then
                task.defer(function()
                    if getEnemyInfo(model, zone) then retarget(true) end
                end)
            end
        end)

        Connections[removeKey] = chars.ChildRemoved:Connect(function(model)
            if model == State.CurrentTarget then
                State.CurrentTarget = nil
                if Config.Enabled then task.defer(function() retarget(true) end) end
            end
        end)
    end

    for _, zone in ipairs(zones:GetChildren()) do bindZone(zone) end
    Connections.ZoneAdded = zones.ChildAdded:Connect(function(zone)
        task.delay(0.1, function() bindZone(zone) end)
    end)
end

local function createHud()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local old = playerGui:FindFirstChild("AnimeStarsFarmV31HUD")
    if old then old:Destroy() end

    HudGui = Instance.new("ScreenGui")
    HudGui.Name = "AnimeStarsFarmV31HUD"
    HudGui.ResetOnSpawn = false
    HudGui.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(1, 0)
    frame.Position = UDim2.new(1, -16, 0, 76)
    frame.Size = UDim2.fromOffset(360, 150)
    frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    frame.BackgroundTransparency = 0.10
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
    HudLabel.TextWrapped = true
    HudLabel.Parent = frame
end

local function refreshHud()
    if not HudLabel then return end
    local target = State.CurrentTarget and State.CurrentTarget.Name or "none"
    local zone = State.CurrentZone and State.CurrentZone.Name or "auto"
    local enemyCount = #collectEnemies()
    HudLabel.Text = string.format(
        "AGGRESSIVE FARM V3.1\nStatus: %s\nZone: %s | Live: %d\nTarget: %s\nKills: %d | Hops: %d | M1: %d\nInput: %s%s",
        State.Status,
        zone,
        enemyCount,
        target,
        State.KillsObserved,
        State.Teleports,
        State.Attacks,
        State.InputMode,
        State.LastError and ("\nERR: " .. State.LastError) or ""
    )
end

local function toggleFarm(v)
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
end

local function buildFallbackUi()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local old = playerGui:FindFirstChild("AnimeStarsFarmFallback")
    if old then old:Destroy() end

    FallbackGui = Instance.new("ScreenGui")
    FallbackGui.Name = "AnimeStarsFarmFallback"
    FallbackGui.ResetOnSpawn = false
    FallbackGui.Parent = playerGui

    local button = Instance.new("TextButton")
    button.Position = UDim2.fromOffset(20, 100)
    button.Size = UDim2.fromOffset(220, 44)
    button.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Text = "Farm V3.1: OFF"
    button.Parent = FallbackGui
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)

    button.MouseButton1Click:Connect(function()
        toggleFarm(not Config.Enabled)
        button.Text = Config.Enabled and "Farm V3.1: ON" or "Farm V3.1: OFF"
    end)

    boot("Fallback UI created")
end

local function buildWindUi()
    if not WindUI then return false end

    local ok, err = pcall(function()
        Window = WindUI:CreateWindow({
            Title = "Anime Stars | Aggressive Farm V3.1",
            Folder = "AnimeStarsFarmV31",
            NewElements = true,
            HideSearchBar = false,
            OpenButton = {
                Title = "Farm V3.1",
                Enabled = true,
                Draggable = true,
                OnlyMobile = false,
            },
        })

        local Farm = Window:Tab({ Title = "Farm", Border = true })

        Farm:Toggle({
            Title = "Enable Aggressive Auto Farm",
            Desc = "Nearest live monster -> stick to range -> instant retarget",
            Value = false,
            Callback = toggleFarm,
        })

        Farm:Toggle({
            Title = "Auto M1",
            Value = Config.AutoM1,
            Callback = function(v) Config.AutoM1 = v == true end,
        })

        Farm:Toggle({
            Title = "Follow / Re-stick",
            Value = Config.FollowMovingTarget,
            Callback = function(v) Config.FollowMovingTarget = v == true end,
        })

        Farm:Toggle({
            Title = "Noclip",
            Value = Config.Noclip,
            Callback = function(v) Config.Noclip = v == true end,
        })

        Farm:Toggle({
            Title = "Pre-position at Spawner",
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
            Step = 0.01,
            Value = { Min = 0.05, Max = 0.50, Default = Config.AttackInterval },
            Callback = function(v) Config.AttackInterval = tonumber(v) or 0.12 end,
        })

        Farm:Input({
            Title = "Zone Filter",
            Placeholder = "blank = auto",
            Value = Config.ZoneFilter,
            Callback = function(v)
                Config.ZoneFilter = tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", "")
                State.CurrentTarget = nil
                if Config.Enabled then retarget(true) end
            end,
        })

        Farm:Button({
            Title = "Force Retarget",
            Callback = function()
                State.CurrentTarget = nil
                retarget(true)
            end,
        })

        Farm:Button({
            Title = "Teleport to Nearest Monster",
            Callback = function()
                local info = nearestEnemy()
                if info then
                    setTarget(info)
                    teleportNear(info.Root)
                else
                    notify("Farm", "No live monster found", 3)
                end
            end,
        })

        Farm:Button({
            Title = "Teleport to Nearest Spawner",
            Callback = function()
                if not prePositionSpawner() then notify("Farm", "No spawner found", 3) end
            end,
        })
    end)

    if not ok then
        setError("WindUI build", err)
        return false
    end

    boot("WindUI built")
    return true
end

createHud()

if not buildWindUi() then
    buildFallbackUi()
end

startEventObserver()
bindZoneSignals()

Connections.Heartbeat = RunService.Heartbeat:Connect(function()
    local now = os.clock()

    if Config.Enabled and Config.Noclip and now - State.LastNoclip >= Config.NoclipInterval then
        State.LastNoclip = now
        setNoclip(true)
    elseif not Config.Enabled and now - State.LastNoclip >= Config.NoclipInterval then
        State.LastNoclip = now
        setNoclip(false)
    end

    local ok, err = pcall(farmStep)
    if not ok then setError("farmStep", err) end
    refreshHud()
end)

Connections.CharacterAdded = LocalPlayer.CharacterAdded:Connect(function()
    State.CurrentTarget = nil
    task.delay(0.6, function()
        if Config.Enabled then retarget(true) end
    end)
end)

if game.PlaceId ~= EXPECTED_PLACE_ID then
    notify("Place mismatch", "Built for PlaceId " .. tostring(EXPECTED_PLACE_ID), 7)
end

ENV.__ANIME_STARS_FARM_V3_STATE = State
ENV.__ANIME_STARS_FARM_V3_CONFIG = Config
ENV.__ANIME_STARS_FARM_V3_CLEANUP = function()
    Config.Enabled = false
    setNoclip(false)

    for key, connection in pairs(Connections) do
        if connection then pcall(function() connection:Disconnect() end) end
        Connections[key] = nil
    end

    if HudGui then pcall(function() HudGui:Destroy() end) HudGui = nil end
    if FallbackGui then pcall(function() FallbackGui:Destroy() end) FallbackGui = nil end
    if Window then pcall(function() Window:Destroy() end) Window = nil end
end

State.Status = "READY"
boot("Loaded successfully")
notify("Aggressive Farm V3.1", "Loaded successfully. Enable Farm in WindUI/fallback button.", 5)