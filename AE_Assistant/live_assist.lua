--[[
    Anime Expeditions Assistant | V3 Live Assist extension

    Loader:
      loadstring(game:HttpGet("https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Assistant/v3.lua"))()

    PURPOSE
    - Extends the V2 evidence advisor with live, read-only assistance.
    - Does NOT fire placement / upgrade / sell / ability remotes.
    - Uses exact DB stats when available and labels geometry/economy results as derived.
    - Never invents stage economy, placement legality, element multipliers, or cooldown state.

    LIVE FEATURES
    - workspace.Map.Path polyline discovery + route-length measurement.
    - Candidate placement search on real map ground using raycasts.
    - Range / attack-window evidence from the DB at each upgrade.
    - Runtime Yen, Wave, owned hotbar, placed-unit and enemy discovery.
    - "Place vs Upgrade" next-action ranking using marginal raw DPS and route exposure.
    - Explicit stage Farm-ban detection when a matching runtime stage table/module exposes it.
    - Current-enemy threat summary (progress, speed, shield/mechanic evidence where discoverable).
    - Range and recommended-placement visual overlays.

    IMPORTANT BOUNDARY
    The route score is a DERIVED spatial opportunity proxy. It is not exact clear time or exact
    total damage because target selection, AoE target count, animation timing, spawn spacing,
    server tick rules, passive state machines and placement legality can add constraints that are
    not always exposed to the client.
]]

local LIVE_VERSION = "3.0.0-live-readonly"
local MAIN_URL = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Assistant/main.lua"
local RAW_ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_DB/"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local ENV = getgenv and getgenv() or _G

if type(ENV.AE_LIVE_ASSIST) == "table" and type(ENV.AE_LIVE_ASSIST.Destroy) == "function" then
    pcall(ENV.AE_LIVE_ASSIST.Destroy)
end

local function notify(title, text, duration)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 6,
        })
    end)
end

local function normalize(value)
    return tostring(value or ""):lower():gsub("[^%w]", "")
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function getCI(tbl, names)
    if type(tbl) ~= "table" then return nil, nil end
    local wanted = {}
    for _, name in ipairs(names) do wanted[normalize(name)] = true end
    for key, value in pairs(tbl) do
        if wanted[normalize(key)] then return value, key end
    end
    return nil, nil
end

local function countKeys(tbl)
    local n = 0
    if type(tbl) == "table" then
        for _ in pairs(tbl) do n = n + 1 end
    end
    return n
end

local function formatNumber(value, digits)
    value = tonumber(value)
    if not value then return "?" end
    digits = digits or 2
    local abs = math.abs(value)
    if abs >= 1000000000 then return string.format("%.2fB", value / 1000000000) end
    if abs >= 1000000 then return string.format("%.2fM", value / 1000000) end
    if abs >= 1000 then return string.format("%.2fK", value / 1000) end
    local text = string.format("%." .. tostring(digits) .. "f", value)
    text = text:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
    return text
end

local function safeRequire(instance)
    if not instance or not instance:IsA("ModuleScript") then return nil end
    local ok, value = pcall(require, instance)
    if ok and type(value) == "table" then return value end
    return nil
end

local function safeJsonGet(url)
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if not ok then return nil end
    local decodedOk, decoded = pcall(function() return HttpService:JSONDecode(body) end)
    if decodedOk and type(decoded) == "table" then return decoded end
    return nil
end

local function walkTable(root, callback, maxDepth)
    if type(root) ~= "table" then return end
    local seen = {}
    maxDepth = maxDepth or 7
    local function visit(tbl, path, depth)
        if depth > maxDepth or seen[tbl] then return end
        seen[tbl] = true
        for key, value in pairs(tbl) do
            local p = path == "" and tostring(key) or (path .. "." .. tostring(key))
            callback(p, key, value, tbl, depth)
            if type(value) == "table" then visit(value, p, depth + 1) end
        end
    end
    visit(root, "", 0)
end

local function sanitize(value, seen, depth)
    seen = seen or {}
    depth = depth or 0
    if depth > 10 then return "<MAX_DEPTH>" end
    local kind = typeof(value)
    if kind == "nil" or kind == "string" or kind == "number" or kind == "boolean" then return value end
    if kind == "Vector3" then return {x = value.X, y = value.Y, z = value.Z, __type = "Vector3"} end
    if kind == "Vector2" then return {x = value.X, y = value.Y, __type = "Vector2"} end
    if kind == "Instance" then return {path = value:GetFullName(), class = value.ClassName, __type = "Instance"} end
    if kind ~= "table" then return tostring(value) end
    if seen[value] then return "<CYCLE>" end
    seen[value] = true
    local out = {}
    for k, v in pairs(value) do out[tostring(k)] = sanitize(v, seen, depth + 1) end
    seen[value] = nil
    return out
end

-- ============================================================
-- ENSURE V2 BASE UI EXISTS
-- ============================================================

local BaseApp = ENV.AE_ASSISTANT
if type(BaseApp) ~= "table" or not BaseApp.Rayfield or not BaseApp.Rayfield._Window then
    local ok, err = pcall(function()
        loadstring(game:HttpGet(MAIN_URL))()
    end)
    if not ok then
        notify("AE Live Assist", "Base V2 failed to load: " .. tostring(err), 10)
        warn("[AE Live Assist] base load failed", err)
        return
    end
    BaseApp = ENV.AE_ASSISTANT
end

if type(BaseApp) ~= "table" or not BaseApp.Rayfield or not BaseApp.Rayfield._Window then
    notify("AE Live Assist", "Base V2 window unavailable", 10)
    return
end

-- ============================================================
-- DATABASE
-- ============================================================

local Shared = ReplicatedStorage:FindFirstChild("Shared")
local InformationRoot = Shared and Shared:FindFirstChild("Information")

local function loadDB(moduleName, fileName)
    local runtime = InformationRoot and safeRequire(InformationRoot:FindFirstChild(moduleName))
    if runtime and countKeys(runtime) > 0 then return runtime, "runtime:" .. moduleName end
    local fallback = safeJsonGet(RAW_ROOT .. fileName)
    if fallback then return fallback, "github:" .. fileName end
    return {}, "unavailable"
end

local UnitsDB, UnitsSource = loadDB("Units", "units.json")
local EnemiesRoot, EnemiesSource = loadDB("Enemies", "enemies.json")
local ElementsRoot, ElementsSource = loadDB("Elements", "elements.json")
local PassivesRoot = loadDB("Passives", "passives.json")
local AbilitiesRoot = loadDB("Abilities", "abilities.json")
local MapsRoot = loadDB("Maps", "maps_full.json")
local GamemodesRoot = loadDB("Gamemodes", "gamemodes.json")

local EnemyList = EnemiesRoot.List or EnemiesRoot
local ElementData = ElementsRoot.ElementData or ElementsRoot
local PassivesDB = PassivesRoot.Passives or PassivesRoot
local AbilitiesDB = AbilitiesRoot.Abilities or AbilitiesRoot

if countKeys(UnitsDB) == 0 then
    notify("AE Live Assist", "Units database unavailable", 10)
    return
end

local UnitAlias = {}
for asset, info in pairs(UnitsDB) do
    UnitAlias[normalize(asset)] = asset
    if type(info) == "table" and info.DisplayName then UnitAlias[normalize(info.DisplayName)] = asset end
end

local EnemyAlias = {}
for key, info in pairs(EnemyList) do
    EnemyAlias[normalize(key)] = key
    if type(info) == "table" then
        local display = getCI(info, {"DisplayName", "Name"})
        if type(display) == "string" then EnemyAlias[normalize(display)] = key end
    end
end

local function numericUpgradeEntries(info)
    local out = {}
    for key, value in pairs(type(info) == "table" and info.UpgradeInfo or {}) do
        local level = tonumber(key)
        if level ~= nil and type(value) == "table" then out[#out + 1] = {Level = level, Base = value} end
    end
    table.sort(out, function(a, b) return a.Level < b.Level end)
    return out
end

local ProfileCache = {}
local function buildProfile(asset)
    if ProfileCache[asset] then return ProfileCache[asset] end
    local info = UnitsDB[asset]
    if type(info) ~= "table" then return nil end
    local p = {
        Asset = asset,
        DisplayName = info.DisplayName or asset,
        Element = info.Element,
        Archetype = info.Archetype,
        PlacementType = info.PlacementType,
        PlacementLimit = tonumber(info.PlacementLimit) or 1,
        Farm = normalize(info.Element) == "farm" or info.IsFarm == true,
        Upgrades = {},
        Passives = {},
        Abilities = {},
    }
    local cumulative = 0
    local passSeen, abilitySeen = {}, {}
    for _, entry in ipairs(numericUpgradeEntries(info)) do
        local b = entry.Base
        local cost = tonumber(b.Cost) or 0
        cumulative = cumulative + cost
        local damage = tonumber(b.Damage) or 0
        local spa = tonumber(b.SPA)
        local range = tonumber(b.Range or b.RNG)
        local u = {
            Level = entry.Level,
            Cost = cost,
            CumulativeCost = cumulative,
            Damage = damage,
            SPA = spa,
            Range = range,
            RawDPS = spa and spa > 0 and damage / spa or 0,
            HitboxType = b.HitboxType,
            HitboxSize = tonumber(b.HitboxSize),
            SkillName = b.SkillName,
            IsFarm = b.IsFarm == true,
        }
        if u.IsFarm then p.Farm = true end
        p.Upgrades[#p.Upgrades + 1] = u
        for _, name in pairs(b.Passives or {}) do
            if type(name) == "string" and not passSeen[name] then
                passSeen[name] = true
                local e = PassivesDB[name] or {}
                p.Passives[#p.Passives + 1] = {
                    Name = name,
                    Description = tostring(e.Description or ""),
                    Cooldown = tonumber(e.Cooldown),
                    UnlockUpgrade = entry.Level,
                }
            end
        end
        for _, name in pairs(b.Abilities or {}) do
            if type(name) == "string" and not abilitySeen[name] then
                abilitySeen[name] = true
                local e = AbilitiesDB[name] or {}
                p.Abilities[#p.Abilities + 1] = {
                    Name = name,
                    DisplayName = e.DisplayName or name,
                    Description = tostring(e.Description or ""),
                    Cooldown = tonumber(e.Cooldown),
                    CooldownType = e.CooldownType,
                    UnlockUpgrade = entry.Level,
                }
            end
        end
    end
    p.Base = p.Upgrades[1]
    p.Final = p.Upgrades[#p.Upgrades]
    ProfileCache[asset] = p
    return p
end

local function upgradeAt(profile, level)
    if not profile then return nil, nil end
    for index, u in ipairs(profile.Upgrades) do
        if u.Level == tonumber(level) then return u, index end
    end
    return nil, nil
end

local function nextUpgrade(profile, level)
    local current, index = upgradeAt(profile, level)
    if not current then return nil, nil end
    return profile.Upgrades[index + 1], current
end

-- ============================================================
-- EXPLICIT ELEMENT MULTIPLIER ONLY
-- ============================================================

local function explicitElementMultiplier(unitElement, enemyElement)
    if not unitElement or not enemyElement then return nil, "missing element" end
    local info = ElementData[unitElement]
    if type(info) ~= "table" then
        for key, value in pairs(ElementData) do
            if normalize(key) == normalize(unitElement) then info = value break end
        end
    end
    if type(info) ~= "table" then return nil, "unit element not found" end

    local candidates = {}
    walkTable(info, function(path, key, value, parent)
        local np = normalize(path)
        local nk = normalize(key)
        if type(value) == "number" and value >= 0 and value <= 5 then
            if nk == normalize(enemyElement) and (np:find("multiplier", 1, true) or np:find("damage", 1, true)) then
                candidates[#candidates + 1] = value
            elseif (nk == "multiplier" or nk == "damagemultiplier" or nk == "damagedealtmultiplier") and type(parent) == "table" then
                local tag = getCI(parent, {"Element", "Against", "TargetElement", "EnemyElement"})
                if tag and normalize(tag) == normalize(enemyElement) then candidates[#candidates + 1] = value end
            end
        end
    end, 6)

    if #candidates == 0 then return nil, "no explicit numeric multiplier" end
    local first = candidates[1]
    for i = 2, #candidates do
        if math.abs(candidates[i] - first) > 1e-7 then return nil, "ambiguous numeric multipliers" end
    end
    return first, "explicit ElementData numeric multiplier"
end

-- ============================================================
-- PATH GEOMETRY
-- ============================================================

local function instancePosition(instance)
    if instance:IsA("BasePart") then return instance.Position end
    if instance:IsA("Attachment") then return instance.WorldPosition end
    if instance:IsA("Model") then
        local ok, pivot = pcall(function() return instance:GetPivot() end)
        if ok then return pivot.Position end
    end
    return nil
end

local function numericNodeOrder(instance)
    for _, attr in ipairs({"Order", "Index", "PathIndex", "NodeIndex", "Waypoint", "WaypointIndex"}) do
        local value = instance:GetAttribute(attr)
        if type(value) == "number" then return value, "attribute:" .. attr end
    end
    local number = tonumber(instance.Name:match("(%d+)$"))
    if number then return number, "name-suffix" end
    return nil, nil
end

local function findPathRoot()
    local map = Workspace:FindFirstChild("Map")
    if map then
        local direct = map:FindFirstChild("Path")
        if direct then return direct, "workspace.Map.Path" end
    end
    local best, bestCount = nil, 0
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d.Name == "Path" and (d:IsA("Folder") or d:IsA("Model")) then
            local count = 0
            for _, child in ipairs(d:GetDescendants()) do
                if child:IsA("BasePart") or child:IsA("Attachment") then count = count + 1 end
            end
            if count > bestCount then best, bestCount = d, count end
        end
    end
    return best, best and (best:GetFullName() .. " fallback") or "not found"
end

local function collectPathNodes(root)
    if not root then return nil, "Path root missing" end
    local raw = {}
    for _, child in ipairs(root:GetChildren()) do
        local pos = instancePosition(child)
        if pos then raw[#raw + 1] = {Instance = child, Position = pos} end
        if not pos and (child:IsA("Folder") or child:IsA("Model")) then
            for _, sub in ipairs(child:GetDescendants()) do
                local subPos = instancePosition(sub)
                if subPos then raw[#raw + 1] = {Instance = sub, Position = subPos} end
            end
        end
    end
    if #raw < 2 then return nil, "Fewer than 2 path nodes" end

    local orderSource = nil
    local used = {}
    for _, node in ipairs(raw) do
        local order, source = numericNodeOrder(node.Instance)
        if order == nil or used[order] then
            return nil, "Path node order is not explicit/unique"
        end
        node.Order = order
        orderSource = orderSource or source
        used[order] = true
    end
    table.sort(raw, function(a, b) return a.Order < b.Order end)

    local compact = {}
    for _, node in ipairs(raw) do
        if #compact == 0 or (compact[#compact].Position - node.Position).Magnitude > 0.05 then
            compact[#compact + 1] = node
        end
    end
    if #compact < 2 then return nil, "Path nodes collapse to one position" end
    return compact, "explicit order via " .. tostring(orderSource)
end

local function buildSegments(nodes)
    local segments = {}
    local total = 0
    for i = 1, #nodes - 1 do
        local a, b = nodes[i].Position, nodes[i + 1].Position
        local a2, b2 = Vector2.new(a.X, a.Z), Vector2.new(b.X, b.Z)
        local len = (b2 - a2).Magnitude
        if len > 0.01 then
            segments[#segments + 1] = {A = a, B = b, A2 = a2, B2 = b2, Length = len, StartDistance = total}
            total = total + len
        end
    end
    return segments, total
end

local function segmentLengthInsideCircle(a, b, center, radius)
    local d = b - a
    local f = a - center
    local A = d:Dot(d)
    if A <= 1e-12 then return (f.Magnitude <= radius) and 0 or 0 end
    local B = 2 * f:Dot(d)
    local C = f:Dot(f) - radius * radius
    local disc = B * B - 4 * A * C
    local insideA = f:Dot(f) <= radius * radius
    local fb = b - center
    local insideB = fb:Dot(fb) <= radius * radius
    if disc < 0 then return (insideA and insideB) and math.sqrt(A) or 0 end
    local sqrtDisc = math.sqrt(math.max(0, disc))
    local t1 = (-B - sqrtDisc) / (2 * A)
    local t2 = (-B + sqrtDisc) / (2 * A)
    if t1 > t2 then t1, t2 = t2, t1 end
    local lo = math.max(0, t1)
    local hi = math.min(1, t2)
    if hi <= lo then
        if insideA and insideB then return math.sqrt(A) end
        return 0
    end
    return (hi - lo) * math.sqrt(A)
end

local function coveredPathLength(segments, position, range)
    if not segments or not position or not range or range <= 0 then return 0 end
    local c = Vector2.new(position.X, position.Z)
    local total = 0
    for _, seg in ipairs(segments) do
        total = total + segmentLengthInsideCircle(seg.A2, seg.B2, c, range)
    end
    return total
end

local function samplePath(segments, totalLength, maxSamples)
    local out = {}
    if not segments or #segments == 0 or totalLength <= 0 then return out end
    maxSamples = maxSamples or 60
    local step = math.max(5, totalLength / maxSamples)
    local distance = 0
    local segIndex = 1
    while distance <= totalLength + 0.001 do
        while segIndex < #segments and distance > segments[segIndex].StartDistance + segments[segIndex].Length do
            segIndex = segIndex + 1
        end
        local seg = segments[segIndex]
        local localD = math.clamp(distance - seg.StartDistance, 0, seg.Length)
        local t = seg.Length > 0 and localD / seg.Length or 0
        local pos = seg.A:Lerp(seg.B, t)
        local tangent = seg.B2 - seg.A2
        if tangent.Magnitude > 0 then tangent = tangent.Unit else tangent = Vector2.new(1, 0) end
        out[#out + 1] = {Position = pos, Tangent = tangent, Distance = distance}
        distance = distance + step
    end
    return out
end

local function raycastGround(x, z, referenceY, pathRoot)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = {}
    if pathRoot then ignore[#ignore + 1] = pathRoot end
    local visuals = Workspace:FindFirstChild("AE_LiveAssist_Visuals")
    if visuals then ignore[#ignore + 1] = visuals end
    params.FilterDescendantsInstances = ignore
    params.IgnoreWater = false
    local origin = Vector3.new(x, referenceY + 80, z)
    local result = Workspace:Raycast(origin, Vector3.new(0, -180, 0), params)
    return result
end

-- ============================================================
-- RUNTIME DISCOVERY
-- ============================================================

local function parseNumericText(text)
    text = tostring(text or "")
    local number = text:match("([%d][%d,%.]*)")
    if not number then return nil end
    number = number:gsub(",", "")
    return tonumber(number)
end

local function scanYen()
    local candidates = {}
    local function add(value, score, source)
        value = tonumber(value)
        if value and value >= 0 then candidates[#candidates + 1] = {Value = value, Score = score, Source = source} end
    end

    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        for _, v in ipairs(leaderstats:GetChildren()) do
            if v:IsA("NumberValue") or v:IsA("IntValue") then
                local n = normalize(v.Name)
                if n == "yen" then add(v.Value, 100, v:GetFullName())
                elseif n == "money" or n == "cash" then add(v.Value, 70, v:GetFullName()) end
            end
        end
    end

    for _, d in ipairs(LocalPlayer:GetDescendants()) do
        if d:IsA("NumberValue") or d:IsA("IntValue") then
            local n = normalize(d.Name)
            if n == "yen" then add(d.Value, 95, d:GetFullName())
            elseif n == "money" or n == "cash" then add(d.Value, 65, d:GetFullName()) end
        end
    end

    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if gui then
        for _, d in ipairs(gui:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                local text = d.Text or ""
                local n = normalize(d.Name .. " " .. (d.Parent and d.Parent.Name or ""))
                local hasYenSymbol = text:find("¥", 1, true) or text:find("￥", 1, true)
                if hasYenSymbol or n:find("yen", 1, true) then
                    add(parseNumericText(text), hasYenSymbol and 90 or 75, d:GetFullName() .. " text")
                elseif n:find("money", 1, true) or n:find("cash", 1, true) then
                    add(parseNumericText(text), 55, d:GetFullName() .. " text")
                end
            end
        end
    end

    table.sort(candidates, function(a, b) return a.Score > b.Score end)
    if #candidates == 0 then return nil, "UNKNOWN: no validated Yen source" end
    if #candidates >= 2 and candidates[1].Score == candidates[2].Score and candidates[1].Value ~= candidates[2].Value then
        return nil, "UNKNOWN: equally strong Yen sources disagree"
    end
    return candidates[1].Value, candidates[1].Source
end

local function scanWave()
    local candidates = {}
    local function add(value, score, source)
        value = tonumber(value)
        if value and value >= 0 and value < 100000 then candidates[#candidates + 1] = {Value = value, Score = score, Source = source} end
    end
    for _, d in ipairs(LocalPlayer:GetDescendants()) do
        if d:IsA("IntValue") or d:IsA("NumberValue") then
            local n = normalize(d.Name)
            if n == "wave" or n == "currentwave" then add(d.Value, 95, d:GetFullName()) end
        end
    end
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if gui then
        for _, d in ipairs(gui:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") then
                local n = normalize(d.Name .. " " .. (d.Parent and d.Parent.Name or ""))
                if n:find("wave", 1, true) or tostring(d.Text):lower():find("wave", 1, true) then
                    add(parseNumericText(d.Text), 75, d:GetFullName() .. " text")
                end
            end
        end
    end
    table.sort(candidates, function(a, b) return a.Score > b.Score end)
    if #candidates == 0 then return nil, "UNKNOWN" end
    return candidates[1].Value, candidates[1].Source
end

local function resolveUnitAsset(value)
    if type(value) == "table" then
        local asset = getCI(value, {"Asset", "Unit", "UnitName"})
        if asset and UnitAlias[normalize(asset)] then return UnitAlias[normalize(asset)] end
        local id = getCI(value, {"ID", "Id", "UnitID", "UUID"})
        if id then value = id else return nil end
    end
    if type(value) == "string" or type(value) == "number" then
        local text = tostring(value)
        local prefix = text:match("^([^#]+)#") or text
        return UnitAlias[normalize(prefix)]
    end
    return nil
end

local function scanHotbarAssets()
    local out, seen = {}, {}
    if type(getgc) ~= "function" then return out, "getgc unavailable" end
    local ok, objects = pcall(getgc, true)
    if not ok or type(objects) ~= "table" then return out, "getgc failed" end
    for _, object in ipairs(objects) do
        if type(object) == "table" and rawget(object, "Token") == "HotbarData" then
            local data = rawget(object, "Data")
            local slots = type(data) == "table" and getCI(data, {"Slots"}) or nil
            if type(slots) == "table" then
                local ordered = {}
                for slot, value in pairs(slots) do ordered[#ordered + 1] = {Slot = tonumber(slot) or 999, Value = value} end
                table.sort(ordered, function(a, b) return a.Slot < b.Slot end)
                for _, item in ipairs(ordered) do
                    local asset = resolveUnitAsset(item.Value)
                    if asset and not seen[asset] then seen[asset] = true; out[#out + 1] = asset end
                end
                if #out > 0 then return out, "getgc HotbarData.Data.Slots" end
            end
        end
    end
    return out, "validated HotbarData not found"
end

local function exactOwnerEvidence(model)
    for _, key in ipairs({"OwnerUserId", "PlayerUserId", "UserId", "OwnerId"}) do
        local value = model:GetAttribute(key)
        if tonumber(value) == LocalPlayer.UserId then return true, "attribute:" .. key end
    end
    for _, key in ipairs({"Owner", "Player", "Username", "PlayerName"}) do
        local value = model:GetAttribute(key)
        if type(value) == "string" and value == LocalPlayer.Name then return true, "attribute:" .. key end
    end
    for _, childName in ipairs({"Owner", "Player"}) do
        local obj = model:FindFirstChild(childName)
        if obj and obj:IsA("ObjectValue") and obj.Value == LocalPlayer then return true, "ObjectValue:" .. childName end
    end
    local ancestor = model.Parent
    if ancestor and ancestor.Name == LocalPlayer.Name then return true, "parent named player" end
    return false, nil
end

local function modelAsset(model)
    for _, key in ipairs({"Asset", "Unit", "UnitName", "UnitAsset"}) do
        local value = model:GetAttribute(key)
        if value and UnitAlias[normalize(value)] then return UnitAlias[normalize(value)], "attribute:" .. key end
    end
    local byName = UnitAlias[normalize(model.Name)]
    if byName then return byName, "model name" end
    return nil, nil
end

local function modelUpgrade(model)
    for _, key in ipairs({"Upgrade", "UpgradeLevel", "CurrentUpgrade", "LevelUpgrade"}) do
        local value = model:GetAttribute(key)
        if tonumber(value) ~= nil then return tonumber(value), "attribute:" .. key end
    end
    for _, key in ipairs({"Upgrade", "UpgradeLevel", "CurrentUpgrade"}) do
        local child = model:FindFirstChild(key)
        if child and (child:IsA("IntValue") or child:IsA("NumberValue")) then return tonumber(child.Value), child:GetFullName() end
    end
    return nil, "UNKNOWN"
end

local function recordOwnerEvidence(record, model)
    if type(record) == "table" then
        for _, key in ipairs({"OwnerUserId", "PlayerUserId", "UserId", "OwnerId"}) do
            local value = getCI(record, {key})
            if tonumber(value) == LocalPlayer.UserId then return true, "record:" .. key end
        end
        for _, key in ipairs({"Owner", "Player", "Username", "PlayerName"}) do
            local value = getCI(record, {key})
            if value == LocalPlayer or (type(value) == "string" and value == LocalPlayer.Name) then return true, "record:" .. key end
        end
    end
    if model and model:IsA("Model") then return exactOwnerEvidence(model) end
    return false, nil
end

local function scanPlacedUnits()
    local out, seen = {}, {}

    -- First preference: replica-shaped GC records that directly bind exact unit data
    -- to a live workspace Model. This avoids confusing another player's tower with ours.
    if type(getgc) == "function" then
        local okGC, objects = pcall(getgc, true)
        if okGC and type(objects) == "table" then
            for _, record in ipairs(objects) do
                if type(record) == "table" then
                    local rawAsset = getCI(record, {"Asset", "Unit", "UnitName", "UnitAsset"})
                    local asset = rawAsset and UnitAlias[normalize(rawAsset)] or nil
                    local model = getCI(record, {"Model", "UnitModel", "Instance", "Character"})
                    if asset and typeof(model) == "Instance" and model:IsA("Model") and model:IsDescendantOf(Workspace) and not seen[model] then
                        local mine, ownerSource = recordOwnerEvidence(record, model)
                        if mine then
                            local okPivot, pivot = pcall(function() return model:GetPivot() end)
                            if okPivot then
                                local upgrade = getCI(record, {"Upgrade", "UpgradeLevel", "CurrentUpgrade"})
                                local upgradeSource = upgrade ~= nil and "replica record" or nil
                                if tonumber(upgrade) == nil then upgrade, upgradeSource = modelUpgrade(model) end
                                out[#out + 1] = {
                                    Model = model,
                                    Asset = asset,
                                    Position = pivot.Position,
                                    Upgrade = tonumber(upgrade),
                                    AssetSource = "replica record",
                                    OwnerSource = ownerSource,
                                    UpgradeSource = upgradeSource or "UNKNOWN",
                                }
                                seen[model] = true
                            end
                        end
                    end
                end
            end
        end
    end

    -- Second preference: exact owner evidence exposed on workspace Models.
    local roots = {}
    for _, name in ipairs({"Units", "UnitModels", "PlacedUnits", "Towers", "Troops", "UnitReplicas"}) do
        local root = Workspace:FindFirstChild(name)
        if root then roots[#roots + 1] = root end
        local map = Workspace:FindFirstChild("Map")
        if map and map:FindFirstChild(name) then roots[#roots + 1] = map:FindFirstChild(name) end
    end
    if #roots == 0 then roots[1] = Workspace end

    for _, root in ipairs(roots) do
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("Model") and not seen[d] then
                local asset, assetSource = modelAsset(d)
                if asset then
                    local mine, ownerSource = exactOwnerEvidence(d)
                    if mine then
                        local ok, pivot = pcall(function() return d:GetPivot() end)
                        if ok then
                            local upgrade, upgradeSource = modelUpgrade(d)
                            out[#out + 1] = {
                                Model = d,
                                Asset = asset,
                                Position = pivot.Position,
                                Upgrade = upgrade,
                                AssetSource = assetSource,
                                OwnerSource = ownerSource,
                                UpgradeSource = upgradeSource,
                            }
                            seen[d] = true
                        end
                    end
                end
            end
        end
        if root == Workspace and #out > 0 then break end
    end
    return out
end

local function enemyProfile(key)
    local info = EnemyList[key]
    if type(info) ~= "table" then return {Key = key, DisplayName = key, Shield = false, Mechanics = {}} end
    local p = {
        Key = key,
        DisplayName = getCI(info, {"DisplayName", "Name"}) or key,
        Speed = tonumber(getCI(info, {"Speed", "MoveSpeed", "WalkSpeed", "BaseSpeed"})),
        Element = getCI(info, {"Element", "DamageType"}),
        Type = getCI(info, {"Type", "EnemyType", "Class"}),
        Shield = false,
        Mechanics = {},
    }
    walkTable(info, function(path, _, value)
        local np = normalize(path)
        if (np:find("shield", 1, true) or np:find("barrier", 1, true)) and value ~= false and value ~= nil then p.Shield = true end
        if (np:find("mechanic", 1, true) or np:find("modifier", 1, true) or np:find("immune", 1, true) or np:find("resist", 1, true)) and type(value) ~= "table" then
            if #p.Mechanics < 8 then p.Mechanics[#p.Mechanics + 1] = path .. "=" .. tostring(value) end
        end
    end, 5)
    return p
end

local function enemyModelKey(model)
    for _, key in ipairs({"Asset", "Enemy", "EnemyName", "EnemyAsset"}) do
        local value = model:GetAttribute(key)
        if value and EnemyAlias[normalize(value)] then return EnemyAlias[normalize(value)] end
    end
    return EnemyAlias[normalize(model.Name)]
end

local function nearestPathProgress(segments, totalLength, position)
    if not segments or #segments == 0 or totalLength <= 0 then return nil, nil end
    local p = Vector2.new(position.X, position.Z)
    local bestDist, bestProgress = math.huge, nil
    for _, seg in ipairs(segments) do
        local d = seg.B2 - seg.A2
        local denom = d:Dot(d)
        local t = denom > 0 and math.clamp((p - seg.A2):Dot(d) / denom, 0, 1) or 0
        local q = seg.A2 + d * t
        local dist = (p - q).Magnitude
        if dist < bestDist then
            bestDist = dist
            bestProgress = (seg.StartDistance + seg.Length * t) / totalLength
        end
    end
    return bestProgress, bestDist
end

local function scanEnemies(segments, totalLength)
    local roots = {}
    for _, name in ipairs({"Enemies", "Enemy", "Mobs", "NPCs"}) do
        local r = Workspace:FindFirstChild(name)
        if r then roots[#roots + 1] = r end
        local map = Workspace:FindFirstChild("Map")
        if map and map:FindFirstChild(name) then roots[#roots + 1] = map:FindFirstChild(name) end
    end
    if #roots == 0 then roots[1] = Workspace end
    local out, seen = {}, {}
    for _, root in ipairs(roots) do
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("Model") and not seen[d] then
                local key = enemyModelKey(d)
                if key then
                    local ok, pivot = pcall(function() return d:GetPivot() end)
                    if ok then
                        local p = enemyProfile(key)
                        local runtimeSpeed = nil
                        for _, name in ipairs({"Speed", "MoveSpeed", "WalkSpeed"}) do
                            local v = d:GetAttribute(name)
                            if tonumber(v) then runtimeSpeed = tonumber(v) break end
                        end
                        local progress, pathDistance = nearestPathProgress(segments, totalLength, pivot.Position)
                        local hp, maxHp = nil, nil
                        local hum = d:FindFirstChildOfClass("Humanoid")
                        if hum then hp, maxHp = hum.Health, hum.MaxHealth end
                        out[#out + 1] = {
                            Model = d,
                            Key = key,
                            Profile = p,
                            Position = pivot.Position,
                            Speed = runtimeSpeed or p.Speed,
                            SpeedSource = runtimeSpeed and "runtime attribute" or (p.Speed and "enemy DB" or "UNKNOWN"),
                            Progress = progress,
                            PathDistance = pathDistance,
                            HP = hp,
                            MaxHP = maxHp,
                        }
                        seen[d] = true
                    end
                end
            end
        end
        if root == Workspace and #out > 0 then break end
    end
    return out
end

-- ============================================================
-- ACTIVE STAGE + EXPLICIT FARM RESTRICTION
-- ============================================================

local function detectRuntimeStageFields()
    if type(getgc) ~= "function" then return nil end
    local ok, objects = pcall(getgc, true)
    if not ok or type(objects) ~= "table" then return nil end
    local best, bestScore = nil, 0
    for _, object in ipairs(objects) do
        if type(object) == "table" then
            local mapName = getCI(object, {"MapName", "Map"})
            local actName = getCI(object, {"ActName", "Act"})
            if type(mapName) == "string" and type(actName) == "string" then
                local gm = getCI(object, {"Gamemode", "GameMode", "Mode"})
                local difficulty = getCI(object, {"Difficulty"})
                local score = 9 + (type(gm) == "string" and 3 or 0) + (type(difficulty) == "string" and 1 or 0)
                if score > bestScore then
                    bestScore = score
                    best = {MapName = mapName, ActName = actName, Gamemode = gm, Difficulty = difficulty, Raw = object, Source = "getgc exact fields"}
                end
            end
        end
    end
    return best
end

local function inspectFarmRestriction(root)
    local result = {NoFarm = nil, Evidence = {}, TotalYen = nil, WaveCount = nil, Duration = nil}
    if type(root) ~= "table" then return result end
    walkTable(root, function(path, key, value)
        local combined = normalize(path .. tostring(key))
        if combined:find("farm", 1, true) then
            if type(value) == "boolean" then
                if (combined:find("disable", 1, true) or combined:find("ban", 1, true) or combined:find("nofarm", 1, true) or combined:find("prohibit", 1, true)) and value == true then
                    result.NoFarm = true result.Evidence[#result.Evidence + 1] = path .. "=" .. tostring(value)
                elseif combined:find("allow", 1, true) and value == false then
                    result.NoFarm = true result.Evidence[#result.Evidence + 1] = path .. "=" .. tostring(value)
                elseif combined:find("allow", 1, true) and value == true and result.NoFarm == nil then
                    result.NoFarm = false result.Evidence[#result.Evidence + 1] = path .. "=" .. tostring(value)
                end
            elseif type(value) == "string" then
                local n = normalize(value)
                if n:find("nofarm", 1, true) or n:find("disablefarm", 1, true) or n:find("banfarm", 1, true) then
                    result.NoFarm = true result.Evidence[#result.Evidence + 1] = path .. "=" .. tostring(value)
                end
            end
        end
        if type(value) == "number" then
            local nk = normalize(key)
            if not result.TotalYen and (nk == "totalyen" or nk == "totalincome" or nk == "totalmoney" or nk == "availableyen") then result.TotalYen = value end
            if not result.WaveCount and (nk == "wavecount" or nk == "maxwave" or nk == "maxwaves" or nk == "totalwaves") then result.WaveCount = value end
            if not result.Duration and (nk == "duration" or nk == "stagetime" or nk == "timelimit" or nk == "totaltime") then result.Duration = value end
        end
    end, 9)
    return result
end

local function findStageModule(stage)
    if not stage or not InformationRoot then return nil end
    local maps = InformationRoot:FindFirstChild("Maps")
    if not maps then return nil end
    local best, bestScore = nil, 0
    for _, d in ipairs(maps:GetDescendants()) do
        if d:IsA("ModuleScript") and normalize(d.Name) == normalize(stage.ActName) then
            local score = 4
            local parent = d.Parent
            if parent and normalize(parent.Name) == normalize(stage.MapName) then score = score + 5 end
            local p = parent and parent.Parent
            if stage.Gamemode and p and normalize(p.Name) == normalize(stage.Gamemode) then score = score + 3 end
            if score > bestScore then best, bestScore = d, score end
        end
    end
    return bestScore >= 9 and best or nil
end

local function activeStageFacts()
    local stage = detectRuntimeStageFields()
    if not stage then return {Stage = nil, NoFarm = nil, Evidence = {}, Source = "runtime stage UNKNOWN"} end
    local combined = {NoFarm = nil, Evidence = {}, Source = stage.Source, Stage = stage}
    local direct = inspectFarmRestriction(stage.Raw)
    combined.NoFarm = direct.NoFarm
    for _, e in ipairs(direct.Evidence) do combined.Evidence[#combined.Evidence + 1] = "runtime:" .. e end
    combined.TotalYen, combined.WaveCount, combined.Duration = direct.TotalYen, direct.WaveCount, direct.Duration

    local module = findStageModule(stage)
    if module then
        local data = safeRequire(module)
        if data then
            local selected = data
            if stage.Difficulty then
                for key, value in pairs(data) do
                    if type(value) == "table" and normalize(key) == normalize(stage.Difficulty) then selected = value break end
                end
            end
            local facts = inspectFarmRestriction(selected)
            if facts.NoFarm ~= nil then combined.NoFarm = facts.NoFarm end
            combined.TotalYen = combined.TotalYen or facts.TotalYen
            combined.WaveCount = combined.WaveCount or facts.WaveCount
            combined.Duration = combined.Duration or facts.Duration
            for _, e in ipairs(facts.Evidence) do combined.Evidence[#combined.Evidence + 1] = module:GetFullName() .. ":" .. e end
            combined.Source = combined.Source .. " + " .. module:GetFullName()
        end
    end
    return combined
end

-- ============================================================
-- PLACEMENT CANDIDATES + ACTION ENGINE
-- ============================================================

local State = {
    Live = false,
    Strategy = "Fast Clear",
    RangeOverlay = false,
    PlacementMarker = true,
    PathRoot = nil,
    PathSource = nil,
    PathOrderSource = nil,
    Nodes = nil,
    Segments = nil,
    TotalPathLength = 0,
    PathSamples = nil,
    PlacementCache = {},
    LastSnapshot = nil,
    LoopToken = 0,
}

local function ensurePath(force)
    if State.Segments and not force then return true end
    local root, source = findPathRoot()
    local nodes, orderSource = collectPathNodes(root)
    if not nodes then
        State.PathRoot, State.Nodes, State.Segments, State.PathSamples = root, nil, nil, nil
        State.PathSource, State.PathOrderSource = source, orderSource
        State.TotalPathLength = 0
        return false
    end
    local segments, total = buildSegments(nodes)
    State.PathRoot = root
    State.PathSource = source
    State.PathOrderSource = orderSource
    State.Nodes = nodes
    State.Segments = segments
    State.TotalPathLength = total
    State.PathSamples = samplePath(segments, total, 64)
    State.PlacementCache = {}
    return #segments > 0
end

local function placementCandidates(profile, upgrade, maxReturn)
    if not profile or not upgrade or not upgrade.Range or not ensurePath(false) then return {} end
    local key = profile.Asset .. ":" .. tostring(upgrade.Level)
    if State.PlacementCache[key] then return State.PlacementCache[key] end
    local range = upgrade.Range
    local offsets = {}
    for _, base in ipairs({6, 10, 14, 18, 24, 30}) do
        if base <= math.max(6, range * 0.78) then offsets[#offsets + 1] = base end
    end
    if #offsets == 0 then offsets[1] = math.max(4, range * 0.45) end

    local candidates = {}
    for _, sample in ipairs(State.PathSamples or {}) do
        local normal = Vector2.new(-sample.Tangent.Y, sample.Tangent.X)
        for _, offset in ipairs(offsets) do
            for _, sign in ipairs({-1, 1}) do
                local xz = Vector2.new(sample.Position.X, sample.Position.Z) + normal * offset * sign
                local ground = raycastGround(xz.X, xz.Y, sample.Position.Y, State.PathRoot)
                if ground then
                    local pos = ground.Position + Vector3.new(0, 0.15, 0)
                    local covered = coveredPathLength(State.Segments, pos, range)
                    candidates[#candidates + 1] = {
                        Position = pos,
                        CoveredLength = covered,
                        CoverageRatio = State.TotalPathLength > 0 and covered / State.TotalPathLength or 0,
                        AnchorDistance = sample.Distance,
                        Ground = ground.Instance and ground.Instance:GetFullName() or "raycast hit",
                    }
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        if math.abs(a.CoveredLength - b.CoveredLength) > 1e-6 then return a.CoveredLength > b.CoveredLength end
        return a.AnchorDistance < b.AnchorDistance
    end)
    local out = {}
    local minSpacing = math.max(3, math.min(8, range * 0.2))
    for _, candidate in ipairs(candidates) do
        local distinct = true
        for _, kept in ipairs(out) do
            local d = Vector2.new(candidate.Position.X - kept.Position.X, candidate.Position.Z - kept.Position.Z).Magnitude
            if d < minSpacing then distinct = false break end
        end
        if distinct then
            out[#out + 1] = candidate
            if #out >= (maxReturn or 8) then break end
        end
    end
    State.PlacementCache[key] = out
    return out
end

local function weightedEnemyElementMultiplier(profile, enemies)
    local sum, count = 0, 0
    for _, enemy in ipairs(enemies or {}) do
        local element = enemy.Profile and enemy.Profile.Element
        if element then
            local multiplier = explicitElementMultiplier(profile.Element, element)
            if multiplier then sum = sum + multiplier; count = count + 1 end
        end
    end
    if count > 0 then return sum / count, "explicit numeric ElementData over visible enemies" end
    return nil, "no explicit numeric element multiplier for visible enemies"
end

local function averageEnemySpeed(enemies)
    local sum, count = 0, 0
    for _, e in ipairs(enemies or {}) do
        if tonumber(e.Speed) and e.Speed > 0 then sum = sum + e.Speed; count = count + 1 end
    end
    return count > 0 and sum / count or nil
end

local function actionOpportunity(rawDPS, coveredLength, elementMultiplier, averageSpeed)
    local value = (rawDPS or 0) * (coveredLength or 0) * (elementMultiplier or 1)
    if averageSpeed and averageSpeed > 0 then value = value / averageSpeed end
    return value
end

local function buildActions(hotbar, placed, enemies, stageFacts, yen)
    local actions = {}
    local placedCounts = {}
    for _, unit in ipairs(placed) do placedCounts[unit.Asset] = (placedCounts[unit.Asset] or 0) + 1 end
    local avgSpeed = averageEnemySpeed(enemies)

    for index, unit in ipairs(placed) do
        local profile = buildProfile(unit.Asset)
        if profile and unit.Upgrade ~= nil then
            local nextU, currentU = nextUpgrade(profile, unit.Upgrade)
            if currentU and nextU and nextU.Cost > 0 then
                local currentCovered = currentU.Range and coveredPathLength(State.Segments, unit.Position, currentU.Range) or 0
                local nextCovered = nextU.Range and coveredPathLength(State.Segments, unit.Position, nextU.Range) or currentCovered
                local elementMult, elementSource = weightedEnemyElementMultiplier(profile, enemies)
                local currentOpp = actionOpportunity(currentU.RawDPS, currentCovered, elementMult, avgSpeed)
                local nextOpp = actionOpportunity(nextU.RawDPS, nextCovered, elementMult, avgSpeed)
                local gain = math.max(0, nextOpp - currentOpp)
                actions[#actions + 1] = {
                    Kind = "UPGRADE",
                    Asset = unit.Asset,
                    DisplayName = profile.DisplayName,
                    UnitIndex = index,
                    FromUpgrade = currentU.Level,
                    ToUpgrade = nextU.Level,
                    Cost = nextU.Cost,
                    RawDPSGain = nextU.RawDPS - currentU.RawDPS,
                    OpportunityGain = gain,
                    Efficiency = nextU.Cost > 0 and gain / nextU.Cost or 0,
                    CurrentCovered = currentCovered,
                    NextCovered = nextCovered,
                    Affordable = yen and yen >= nextU.Cost or nil,
                    ElementMultiplier = elementMult,
                    ElementSource = elementSource,
                    Position = unit.Position,
                    HitboxType = nextU.HitboxType,
                    HitboxSize = nextU.HitboxSize,
                    SPA = nextU.SPA,
                    Range = nextU.Range,
                }
            end
        end
    end

    for _, asset in ipairs(hotbar) do
        local profile = buildProfile(asset)
        if profile and profile.Base and (placedCounts[asset] or 0) < profile.PlacementLimit then
            if not profile.Farm then
                local base = profile.Base
                if base.Cost > 0 and base.Range then
                    local candidates = placementCandidates(profile, base, 6)
                    local best = candidates[1]
                    if best then
                        local elementMult, elementSource = weightedEnemyElementMultiplier(profile, enemies)
                        local gain = actionOpportunity(base.RawDPS, best.CoveredLength, elementMult, avgSpeed)
                        actions[#actions + 1] = {
                            Kind = "PLACE",
                            Asset = asset,
                            DisplayName = profile.DisplayName,
                            Cost = base.Cost,
                            RawDPSGain = base.RawDPS,
                            OpportunityGain = gain,
                            Efficiency = base.Cost > 0 and gain / base.Cost or 0,
                            Affordable = yen and yen >= base.Cost or nil,
                            ElementMultiplier = elementMult,
                            ElementSource = elementSource,
                            Position = best.Position,
                            Covered = best.CoveredLength,
                            CoverageRatio = best.CoverageRatio,
                            HitboxType = base.HitboxType,
                            HitboxSize = base.HitboxSize,
                            SPA = base.SPA,
                            Range = base.Range,
                            Ground = best.Ground,
                        }
                    end
                end
            end
        end
    end

    local function better(a, b)
        if State.Strategy == "Max Damage" then
            if a.OpportunityGain ~= b.OpportunityGain then return a.OpportunityGain > b.OpportunityGain end
            if a.Efficiency ~= b.Efficiency then return a.Efficiency > b.Efficiency end
        else
            if a.Efficiency ~= b.Efficiency then return a.Efficiency > b.Efficiency end
            if a.OpportunityGain ~= b.OpportunityGain then return a.OpportunityGain > b.OpportunityGain end
        end
        if a.Cost ~= b.Cost then return a.Cost < b.Cost end
        return tostring(a.Asset) < tostring(b.Asset)
    end
    table.sort(actions, better)

    local bestNow = nil
    if yen then
        for _, action in ipairs(actions) do
            if action.Cost <= yen then bestNow = action break end
        end
    else
        bestNow = actions[1]
    end
    return actions, bestNow, actions[1], avgSpeed
end

-- ============================================================
-- VISUALS
-- ============================================================

local function visualsFolder()
    local f = Workspace:FindFirstChild("AE_LiveAssist_Visuals")
    if not f then
        f = Instance.new("Folder")
        f.Name = "AE_LiveAssist_Visuals"
        f.Parent = Workspace
    end
    return f
end

local function clearVisuals(kind)
    local f = Workspace:FindFirstChild("AE_LiveAssist_Visuals")
    if not f then return end
    for _, child in ipairs(f:GetChildren()) do
        if not kind or child:GetAttribute("AEKind") == kind then child:Destroy() end
    end
end

local function drawRangeOverlays(placed)
    clearVisuals("Range")
    if not State.RangeOverlay then return end
    local folder = visualsFolder()
    for _, unit in ipairs(placed) do
        local profile = buildProfile(unit.Asset)
        local upgrade = profile and unit.Upgrade ~= nil and upgradeAt(profile, unit.Upgrade) or nil
        if upgrade and upgrade.Range then
            local part = Instance.new("Part")
            part.Name = "Range_" .. unit.Asset
            part.Shape = Enum.PartType.Cylinder
            part.Anchored = true
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = false
            part.Material = Enum.Material.ForceField
            part.Transparency = 0.78
            part.Size = Vector3.new(0.18, upgrade.Range * 2, upgrade.Range * 2)
            part.CFrame = CFrame.new(unit.Position.X, unit.Position.Y + 0.08, unit.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
            part:SetAttribute("AEKind", "Range")
            part.Parent = folder
        end
    end
end

local function drawPlacementMarker(action)
    clearVisuals("Placement")
    if not State.PlacementMarker or not action or action.Kind ~= "PLACE" or not action.Position then return end
    local folder = visualsFolder()
    local part = Instance.new("Part")
    part.Name = "RecommendedPlacement"
    part.Shape = Enum.PartType.Ball
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.Material = Enum.Material.Neon
    part.Transparency = 0.2
    part.Size = Vector3.new(1.4, 1.4, 1.4)
    part.Position = action.Position + Vector3.new(0, 0.8, 0)
    part:SetAttribute("AEKind", "Placement")
    part.Parent = folder

    local gui = Instance.new("BillboardGui")
    gui.Size = UDim2.fromOffset(240, 60)
    gui.StudsOffset = Vector3.new(0, 2.2, 0)
    gui.AlwaysOnTop = true
    gui.Parent = part
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 0.3
    label.TextScaled = true
    label.TextWrapped = true
    label.Text = "PLACE " .. tostring(action.DisplayName) .. "\nDERIVED route coverage " .. formatNumber((action.CoverageRatio or 0) * 100, 1) .. "%"
    label.Parent = gui
end

-- ============================================================
-- UI
-- ============================================================

local rawWindow = BaseApp.Rayfield._Window
local Tab = rawWindow:Tab({Title = "Live Assist", Icon = "crosshair"})

local function paragraph(title, desc)
    return Tab:Paragraph({Title = title, Desc = desc or ""})
end

local RuntimeParagraph = paragraph("Runtime", "Press Refresh live snapshot.")
local NextParagraph = paragraph("Next best action", "Not calculated")
local PlacementParagraph = paragraph("Placement geometry", "Not calculated")
local EnemyParagraph = paragraph("Enemy threat", "Not calculated")
local EvidenceParagraph = paragraph("Evidence boundary", table.concat({
    "EXACT: DB Damage / SPA / Range / upgrade cost when present.",
    "EXACT: runtime Yen/Wave only when a validated source is found.",
    "DERIVED: path length inside range, route exposure, placement candidate and DPS-per-Yen ordering.",
    "UNKNOWN: actual server placement legality unless the server exposes it; this script does not probe placement remotes.",
    "UNKNOWN: exact clear time / total damage when spawn spacing, target cap, passive state, AoE target count or server tick behavior is missing.",
    "Farm is never recommended by the live DPS engine; if the stage explicitly bans Farm it is surfaced as a hard warning.",
}, "\n"))

local function setParagraph(element, title, desc)
    pcall(function() element:Set({Title = title, Desc = desc}) end)
end

Tab:Dropdown({
    Title = "Live objective",
    Desc = "Fast Clear prioritizes marginal route opportunity per Yen. Max Damage prioritizes absolute marginal route opportunity.",
    Values = {"Fast Clear", "Max Damage"},
    Value = State.Strategy,
    Multi = false,
    AllowNone = false,
    Callback = function(value)
        if type(value) == "table" then value = value.Title or value.Value or value[1] end
        if value == "Fast Clear" or value == "Max Damage" then State.Strategy = value end
    end,
})

local function actionText(action, yen)
    if not action then return "No validated Place/Upgrade action could be scored." end
    local lines = {
        string.format("%s %s | cost ¥%s", action.Kind, action.DisplayName or action.Asset, formatNumber(action.Cost, 0)),
    }
    if action.Kind == "UPGRADE" then lines[#lines + 1] = string.format("U%s -> U%s", tostring(action.FromUpgrade), tostring(action.ToUpgrade)) end
    lines[#lines + 1] = "Raw DPS gain: " .. formatNumber(action.RawDPSGain, 2)
    lines[#lines + 1] = "DERIVED route-opportunity gain: " .. formatNumber(action.OpportunityGain, 3)
    lines[#lines + 1] = "DERIVED gain / Yen: " .. formatNumber(action.Efficiency, 6)
    lines[#lines + 1] = "SPA after action: " .. formatNumber(action.SPA, 2) .. "s | Range: " .. formatNumber(action.Range, 2)
    lines[#lines + 1] = "Hitbox: " .. tostring(action.HitboxType or "UNKNOWN") .. " size=" .. tostring(action.HitboxSize or "UNKNOWN")
    lines[#lines + 1] = "Element multiplier: " .. (action.ElementMultiplier and (formatNumber(action.ElementMultiplier, 3) .. " EXACT numeric") or "UNKNOWN / not applied")
    if yen then
        lines[#lines + 1] = yen >= action.Cost and "Affordable NOW" or ("Save ¥" .. formatNumber(action.Cost - yen, 0) .. " more")
    else
        lines[#lines + 1] = "Affordability UNKNOWN because Yen source was not validated."
    end
    return table.concat(lines, "\n")
end

local function refreshSnapshot(forcePath)
    local pathOK = ensurePath(forcePath == true)
    local yen, yenSource = scanYen()
    local wave, waveSource = scanWave()
    local hotbar, hotbarSource = scanHotbarAssets()
    local placed = pathOK and scanPlacedUnits() or {}
    local enemies = pathOK and scanEnemies(State.Segments, State.TotalPathLength) or {}
    local stageFacts = activeStageFacts()
    local actions, bestNow, bestTarget, avgSpeed = {}, nil, nil, nil
    if pathOK then actions, bestNow, bestTarget, avgSpeed = buildActions(hotbar, placed, enemies, stageFacts, yen) end

    local stageName = stageFacts.Stage and string.format("%s / %s / %s / %s", tostring(stageFacts.Stage.Gamemode or "?"), tostring(stageFacts.Stage.MapName), tostring(stageFacts.Stage.ActName), tostring(stageFacts.Stage.Difficulty or "?")) or "UNKNOWN"
    local runtimeLines = {
        "Version: " .. LIVE_VERSION,
        "Stage: " .. stageName,
        "Path: " .. tostring(State.PathSource) .. " | " .. tostring(State.PathOrderSource),
        "Path length: " .. (pathOK and (formatNumber(State.TotalPathLength, 2) .. " studs") or "UNKNOWN"),
        "Yen: " .. (yen and ("¥" .. formatNumber(yen, 0)) or "UNKNOWN") .. " | " .. tostring(yenSource),
        "Wave: " .. tostring(wave or "UNKNOWN") .. " | " .. tostring(waveSource),
        "Hotbar: " .. (#hotbar > 0 and table.concat(hotbar, ", ") or "UNKNOWN") .. " | " .. tostring(hotbarSource),
        "Placed owned units validated: " .. tostring(#placed),
        "Visible matched enemies: " .. tostring(#enemies),
        "Visible avg speed: " .. tostring(avgSpeed and formatNumber(avgSpeed, 2) or "UNKNOWN"),
        "Farm restriction: " .. (stageFacts.NoFarm == true and "PROHIBITED (explicit)" or (stageFacts.NoFarm == false and "allowed (explicit)" or "UNKNOWN / not explicit")),
    }
    if #stageFacts.Evidence > 0 then runtimeLines[#runtimeLines + 1] = "Farm evidence: " .. table.concat(stageFacts.Evidence, " | ") end
    setParagraph(RuntimeParagraph, "Runtime evidence", table.concat(runtimeLines, "\n"))

    local nextLines = {"Objective: " .. State.Strategy}
    if yen then
        nextLines[#nextLines + 1] = "BEST AFFORDABLE NOW:\n" .. actionText(bestNow, yen)
        if bestTarget and bestTarget ~= bestNow then nextLines[#nextLines + 1] = "\nBEST SAVE TARGET:\n" .. actionText(bestTarget, yen) end
    else
        nextLines[#nextLines + 1] = actionText(bestTarget, nil)
    end
    if #actions > 1 then
        nextLines[#nextLines + 1] = "\nTop alternatives:"
        for i = 1, math.min(5, #actions) do
            local a = actions[i]
            nextLines[#nextLines + 1] = string.format("%d) %s %s | ¥%s | gain/¥=%s", i, a.Kind, a.DisplayName, formatNumber(a.Cost, 0), formatNumber(a.Efficiency, 6))
        end
    end
    setParagraph(NextParagraph, "Next best action", table.concat(nextLines, "\n"))

    local placementAction = nil
    for _, action in ipairs(actions) do if action.Kind == "PLACE" then placementAction = action break end end
    if placementAction then
        local p = placementAction.Position
        setParagraph(PlacementParagraph, "Best validated placement candidate", table.concat({
            placementAction.DisplayName .. " [" .. placementAction.Asset .. "]",
            string.format("World: X %.2f | Y %.2f | Z %.2f", p.X, p.Y, p.Z),
            "DB Range: " .. formatNumber(placementAction.Range, 2),
            "DERIVED path covered: " .. formatNumber(placementAction.Covered, 2) .. " / " .. formatNumber(State.TotalPathLength, 2) .. " studs (" .. formatNumber((placementAction.CoverageRatio or 0) * 100, 1) .. "%)",
            "Raycast ground: " .. tostring(placementAction.Ground),
            "This is a candidate on real map ground, NOT a server-confirmed legal placement.",
        }, "\n"))
    else
        setParagraph(PlacementParagraph, "Placement geometry", pathOK and "No legal-to-score hotbar placement candidate. Farm units are excluded from live DPS placement advice." or "Path geometry UNKNOWN; placement scoring disabled.")
    end

    table.sort(enemies, function(a, b) return (a.Progress or -1) > (b.Progress or -1) end)
    local enemyLines = {}
    local shieldCount, fastCount = 0, 0
    for _, e in ipairs(enemies) do
        if e.Profile.Shield then shieldCount = shieldCount + 1 end
        if e.Speed and avgSpeed and e.Speed > avgSpeed then fastCount = fastCount + 1 end
    end
    enemyLines[#enemyLines + 1] = "Visible: " .. tostring(#enemies) .. " | shield-evidence: " .. tostring(shieldCount) .. " | above-visible-average speed: " .. tostring(fastCount)
    for i = 1, math.min(6, #enemies) do
        local e = enemies[i]
        enemyLines[#enemyLines + 1] = string.format(
            "%s | progress=%s | speed=%s (%s) | element=%s | shield=%s%s",
            tostring(e.Profile.DisplayName),
            e.Progress and (formatNumber(e.Progress * 100, 1) .. "%") or "UNKNOWN",
            formatNumber(e.Speed, 2),
            tostring(e.SpeedSource),
            tostring(e.Profile.Element or "UNKNOWN"),
            tostring(e.Profile.Shield),
            e.HP and (" | HP=" .. formatNumber(e.HP, 0) .. "/" .. formatNumber(e.MaxHP, 0)) or ""
        )
    end
    if #enemies == 0 then enemyLines[#enemyLines + 1] = "No current enemy model matched the enemy DB." end
    setParagraph(EnemyParagraph, "Enemy threat", table.concat(enemyLines, "\n"))

    drawRangeOverlays(placed)
    drawPlacementMarker(bestNow and bestNow.Kind == "PLACE" and bestNow or placementAction)

    State.LastSnapshot = {
        Version = LIVE_VERSION,
        Timestamp = os.time(),
        Path = {Source = State.PathSource, OrderSource = State.PathOrderSource, Length = State.TotalPathLength, OK = pathOK},
        Yen = yen, YenSource = yenSource,
        Wave = wave, WaveSource = waveSource,
        Hotbar = hotbar, HotbarSource = hotbarSource,
        Placed = placed,
        Enemies = enemies,
        StageFacts = stageFacts,
        Actions = actions,
        BestNow = bestNow,
        BestTarget = bestTarget,
        Strategy = State.Strategy,
    }
    return State.LastSnapshot
end

Tab:Button({
    Title = "Refresh live snapshot",
    Desc = "Re-read runtime state and score Place vs Upgrade.",
    Callback = function()
        task.spawn(function()
            local ok, err = pcall(refreshSnapshot, false)
            if not ok then notify("AE Live Assist", "Refresh error: " .. tostring(err), 9) end
        end)
    end,
})

Tab:Button({
    Title = "Rescan map path",
    Desc = "Use after entering a new map or if workspace.Map.Path changed.",
    Callback = function()
        task.spawn(function()
            local ok, err = pcall(refreshSnapshot, true)
            notify("AE Live Assist", ok and "Path rescanned" or ("Path rescan error: " .. tostring(err)), 6)
        end)
    end,
})

Tab:Button({
    Title = "Start live refresh",
    Desc = "Refreshes the read-only advisor every ~1.5 seconds.",
    Callback = function()
        if State.Live then return end
        State.Live = true
        State.LoopToken = State.LoopToken + 1
        local token = State.LoopToken
        task.spawn(function()
            while State.Live and token == State.LoopToken do
                local ok, err = pcall(refreshSnapshot, false)
                if not ok then warn("[AE Live Assist] refresh", err) end
                task.wait(1.5)
            end
        end)
        notify("AE Live Assist", "Live refresh ON", 5)
    end,
})

Tab:Button({
    Title = "Stop live refresh",
    Callback = function()
        State.Live = false
        State.LoopToken = State.LoopToken + 1
        notify("AE Live Assist", "Live refresh OFF", 4)
    end,
})

Tab:Button({
    Title = "Toggle range overlays",
    Desc = "Shows DB range for placed units whose owner + upgrade were validated.",
    Callback = function()
        State.RangeOverlay = not State.RangeOverlay
        if not State.RangeOverlay then clearVisuals("Range") end
        pcall(refreshSnapshot, false)
        notify("AE Live Assist", "Range overlay " .. (State.RangeOverlay and "ON" or "OFF"), 4)
    end,
})

Tab:Button({
    Title = "Toggle placement marker",
    Desc = "Shows/hides the recommended candidate point; never places automatically.",
    Callback = function()
        State.PlacementMarker = not State.PlacementMarker
        if not State.PlacementMarker then clearVisuals("Placement") end
        pcall(refreshSnapshot, false)
        notify("AE Live Assist", "Placement marker " .. (State.PlacementMarker and "ON" or "OFF"), 4)
    end,
})

Tab:Button({
    Title = "Save live evidence JSON",
    Callback = function()
        if not writefile then notify("AE Live Assist", "writefile unavailable", 6) return end
        if not State.LastSnapshot then pcall(refreshSnapshot, false) end
        if makefolder then pcall(makefolder, "AE_Assistant") end
        local ok, encoded = pcall(function() return HttpService:JSONEncode(sanitize(State.LastSnapshot or {})) end)
        if not ok then notify("AE Live Assist", "JSON encode failed", 7) return end
        local wrote, err = pcall(writefile, "AE_Assistant/live_snapshot.json", encoded)
        notify("AE Live Assist", wrote and "Saved AE_Assistant/live_snapshot.json" or ("Save failed: " .. tostring(err)), 7)
    end,
})

local Live = {
    Version = LIVE_VERSION,
    State = State,
    Refresh = function(forcePath) return refreshSnapshot(forcePath == true) end,
    GetProfile = buildProfile,
    GetPlacementCandidates = function(asset, upgradeLevel)
        local profile = buildProfile(asset)
        local upgrade = profile and upgradeAt(profile, upgradeLevel)
        return profile and upgrade and placementCandidates(profile, upgrade, 12) or {}
    end,
}

function Live.Destroy()
    State.Live = false
    State.LoopToken = State.LoopToken + 1
    clearVisuals()
    if ENV.AE_LIVE_ASSIST == Live then ENV.AE_LIVE_ASSIST = nil end
    if BaseApp and BaseApp.LiveAssist == Live then BaseApp.LiveAssist = nil end
end

ENV.AE_LIVE_ASSIST = Live
BaseApp.LiveAssist = Live

pcall(function() refreshSnapshot(true) end)
notify("AE Live Assist V3", "Loaded read-only live advisor. Use Live Assist tab. K hides/shows UI.", 8)
print("[AE Live Assist] READY", LIVE_VERSION, "Units", UnitsSource, "Enemies", EnemiesSource, "Elements", ElementsSource)
