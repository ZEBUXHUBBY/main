--[[
AE STRATEGIST | SAFE VISUAL ADDON L1
------------------------------------
This addon depends only on the already-loaded standalone AE_Strategist core.
It does NOT modify the core scanner/optimizer and does NOT fire gameplay remotes.

Purpose of Layer 1:
- Show current/recommended teams as visual cards.
- Reuse real in-game ViewportFrames when exact/slot evidence is available.
- Keep a visible status/debug line so failures are never silent.
- If this addon fails, the core remains usable.
]]

local VERSION = "visual-addon-l1.0"
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer
local ENV = getgenv and getgenv() or _G
local Core = ENV.AE_STRATEGIST

if type(Core) ~= "table" or type(Core.GetState) ~= "function" then
    warn("[AE Visual Addon] core missing; addon not loaded")
    return
end

if type(ENV.AE_STRATEGIST_VISUAL) == "table" and type(ENV.AE_STRATEGIST_VISUAL.Destroy) == "function" then
    pcall(ENV.AE_STRATEGIST_VISUAL.Destroy)
end

local Addon = {
    Version = VERSION,
    Connections = {},
    Destroyed = false,
    CardsByAsset = {},
    SlotViewports = {},
}
ENV.AE_STRATEGIST_VISUAL = Addon
Core.VisualAddon = Addon

local function norm(v)
    return tostring(v or ""):lower():gsub("[^%w]", "")
end

local function fmt(v, d)
    v = tonumber(v)
    if not v then return "?" end
    d = d or 0
    if math.abs(v) >= 1e9 then return string.format("%.2fB", v / 1e9) end
    if math.abs(v) >= 1e6 then return string.format("%.2fM", v / 1e6) end
    if math.abs(v) >= 1e3 then return string.format("%.2fK", v / 1e3) end
    local s = string.format("%." .. tostring(d) .. "f", v)
    return s:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
end

local function rounded(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = obj
    return c
end

local function label(parent, text, pos, size, bold)
    local x = Instance.new("TextLabel")
    x.BackgroundTransparency = 1
    x.Position = pos or UDim2.new()
    x.Size = size or UDim2.new(1, 0, 0, 20)
    x.Text = text or ""
    x.TextColor3 = Color3.fromRGB(231, 234, 242)
    x.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    x.TextSize = 12
    x.TextXAlignment = Enum.TextXAlignment.Left
    x.TextYAlignment = Enum.TextYAlignment.Center
    x.TextTruncate = Enum.TextTruncate.AtEnd
    x.Parent = parent
    return x
end

local function button(parent, text, pos, size, callback)
    local b = Instance.new("TextButton")
    b.Position = pos
    b.Size = size
    b.BackgroundColor3 = Color3.fromRGB(56, 68, 105)
    b.BorderSizePixel = 0
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.Text = text
    b.AutoButtonColor = true
    b.Parent = parent
    rounded(b, 7)
    local con = b.MouseButton1Click:Connect(callback)
    Addon.Connections[#Addon.Connections + 1] = con
    return b
end

local parentGui
pcall(function()
    if gethui then parentGui = gethui() end
end)
parentGui = parentGui or game:GetService("CoreGui")
if not parentGui then parentGui = LP:WaitForChild("PlayerGui") end

local old = parentGui:FindFirstChild("AE_Strategist_VisualAddon")
if old then old:Destroy() end

local Gui = Instance.new("ScreenGui")
Gui.Name = "AE_Strategist_VisualAddon"
Gui.ResetOnSpawn = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = parentGui
Addon.Gui = Gui

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(820, 520)
Main.Position = UDim2.new(0.5, -410, 0.5, -260)
Main.BackgroundColor3 = Color3.fromRGB(15, 18, 25)
Main.BorderSizePixel = 0
Main.Parent = Gui
rounded(Main, 11)

local Top = Instance.new("Frame")
Top.Size = UDim2.new(1, 0, 0, 42)
Top.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
Top.BorderSizePixel = 0
Top.Parent = Main
rounded(Top, 11)

local Title = label(Top, "AE Strategist • Visual Layer 1", UDim2.fromOffset(14,0), UDim2.new(1,-250,1,0), true)
Title.TextSize = 14

local Status = label(Top, "Waiting for core state…", UDim2.new(0,250,0,0), UDim2.new(1,-420,1,0), false)
Status.TextSize = 10
Status.TextColor3 = Color3.fromRGB(157, 167, 192)

local SyncButton
SyncButton = button(Top, "SYNC CORE", UDim2.new(1,-160,0,7), UDim2.fromOffset(95,28), function()
    task.spawn(function()
        if Addon.Destroyed then return end
        SyncButton.Text = "SYNCING…"
        Status.Text = "Running core analysis…"
        local ok, err = pcall(Core.RefreshAnalysis)
        if not ok then
            Status.Text = "Core analysis error: " .. tostring(err)
            SyncButton.Text = "SYNC CORE"
            return
        end
        task.wait(0.15)
        local ok2, err2 = pcall(function() Addon.Refresh() end)
        if not ok2 then Status.Text = "Visual refresh error: " .. tostring(err2) end
        SyncButton.Text = "SYNC CORE"
    end)
end)

local Close = button(Top, "×", UDim2.new(1,-54,0,7), UDim2.fromOffset(40,28), function()
    Addon.Destroy()
end)
Close.TextSize = 17

local CurrentTitle = label(Main, "CURRENT HOTBAR", UDim2.fromOffset(16,54), UDim2.fromOffset(250,22), true)
local CurrentCount = label(Main, "", UDim2.new(1,-170,0,54), UDim2.fromOffset(150,22), false)
CurrentCount.TextXAlignment = Enum.TextXAlignment.Right
CurrentCount.TextColor3 = Color3.fromRGB(150,160,182)

local CurrentScroll = Instance.new("ScrollingFrame")
CurrentScroll.Position = UDim2.fromOffset(16,80)
CurrentScroll.Size = UDim2.new(1,-32,0,168)
CurrentScroll.BackgroundColor3 = Color3.fromRGB(20,23,32)
CurrentScroll.BorderSizePixel = 0
CurrentScroll.ScrollBarThickness = 4
CurrentScroll.ScrollingDirection = Enum.ScrollingDirection.X
CurrentScroll.CanvasSize = UDim2.new()
CurrentScroll.Parent = Main
rounded(CurrentScroll, 9)

local RecommendedTitle = label(Main, "RECOMMENDED", UDim2.fromOffset(16,260), UDim2.fromOffset(250,22), true)
local RecommendedCount = label(Main, "", UDim2.new(1,-170,0,260), UDim2.fromOffset(150,22), false)
RecommendedCount.TextXAlignment = Enum.TextXAlignment.Right
RecommendedCount.TextColor3 = Color3.fromRGB(150,160,182)

local RecScroll = CurrentScroll:Clone()
RecScroll.Position = UDim2.fromOffset(16,286)
RecScroll.Parent = Main

local Footer = Instance.new("Frame")
Footer.Position = UDim2.fromOffset(16,466)
Footer.Size = UDim2.new(1,-32,0,38)
Footer.BackgroundColor3 = Color3.fromRGB(22,26,35)
Footer.BorderSizePixel = 0
Footer.Parent = Main
rounded(Footer, 8)
local FooterText = label(Footer, "Visual source: scanning in-game ViewportFrames…", UDim2.fromOffset(10,0), UDim2.new(1,-20,1,0), false)
FooterText.TextSize = 10
FooterText.TextColor3 = Color3.fromRGB(164,175,198)

local function clearFrame(frame)
    for _, c in ipairs(frame:GetChildren()) do
        if not c:IsA("UICorner") and not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
            c:Destroy()
        end
    end
end

local function stripInteractive(root)
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("BaseScript") then
            d:Destroy()
        elseif d:IsA("TextButton") or d:IsA("ImageButton") then
            d.Active = false
            d.AutoButtonColor = false
            d.Selectable = false
        end
    end
end

local function safeViewportClone(vf)
    if not vf or not vf:IsA("ViewportFrame") then return nil end
    local ok, clone = pcall(function() return vf:Clone() end)
    if not ok or not clone then return nil end
    stripInteractive(clone)
    clone.AnchorPoint = Vector2.zero
    clone.Position = UDim2.fromOffset(0,0)
    clone.Size = UDim2.fromScale(1,1)
    clone.BackgroundTransparency = 1
    clone.BorderSizePixel = 0
    clone.Visible = true
    return clone
end

local function collectTextNear(vf)
    local node = vf
    for _ = 1, 5 do
        node = node and node.Parent
        if not node then break end
        local words = {}
        for _, d in ipairs(node:GetDescendants()) do
            if d:IsA("TextLabel") and d.Visible and d.Text ~= "" and #d.Text < 80 then
                words[#words + 1] = d.Text
                if #words >= 12 then break end
            end
        end
        if #words > 0 then return table.concat(words, " | ") end
    end
    return ""
end

local function viewportAssetEvidence(vf, profiles)
    if not vf or type(profiles) ~= "table" then return nil end
    local aliases = {}
    for asset, p in pairs(profiles) do
        aliases[norm(asset)] = asset
        if p and p.DisplayName then aliases[norm(p.DisplayName)] = asset end
    end

    for _, d in ipairs(vf:GetDescendants()) do
        if d:IsA("Model") or d:IsA("Folder") then
            local a = aliases[norm(d.Name)]
            if a then return a, "viewport descendant " .. d:GetFullName() end
        end
    end

    local node = vf
    for _ = 1, 6 do
        if not node then break end
        for _, key in ipairs({"Asset","Unit","UnitName","UnitAsset"}) do
            local v = node:GetAttribute(key)
            if v ~= nil then
                local a = aliases[norm(v)]
                if a then return a, "ancestor attribute " .. key end
            end
        end
        node = node.Parent
    end

    local nearby = norm(collectTextNear(vf))
    for alias, asset in pairs(aliases) do
        if #alias >= 4 and nearby:find(alias, 1, true) then
            return asset, "nearby text"
        end
    end
    return nil
end

local function findHotbarViewportCandidates()
    local out = {}
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return out end
    local viewport = pg.AbsoluteSize or Vector2.new(1920,1080)
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("ViewportFrame") and d.Visible then
            local size = d.AbsoluteSize
            local pos = d.AbsolutePosition
            if size.X >= 30 and size.Y >= 30 and size.X <= 180 and size.Y <= 180 and pos.Y >= viewport.Y * 0.52 then
                out[#out + 1] = d
            end
        end
    end
    table.sort(out, function(a,b)
        local ax, bx = a.AbsolutePosition.X, b.AbsolutePosition.X
        if math.abs(ax-bx) > 4 then return ax < bx end
        return a.AbsolutePosition.Y < b.AbsolutePosition.Y
    end)
    return out
end

local function rebuildViewportIndex(state)
    Addon.CardsByAsset = {}
    Addon.SlotViewports = {}
    local profiles = state and state.Profiles or {}
    local pg = LP:FindFirstChild("PlayerGui")
    local exact = 0
    local scanned = 0

    if pg then
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("ViewportFrame") then
                scanned = scanned + 1
                local asset, source = viewportAssetEvidence(d, profiles)
                if asset and not Addon.CardsByAsset[asset] then
                    Addon.CardsByAsset[asset] = {Viewport=d, Source=source}
                    exact = exact + 1
                end
            end
        end
    end

    local candidates = findHotbarViewportCandidates()
    local hot = state and state.Scan and state.Scan.Hotbar or {}
    for i, h in ipairs(hot) do
        local slot = tonumber(h.Slot) or i
        local vf = candidates[i]
        if vf then
            Addon.SlotViewports[slot] = vf
            if h.Asset and not Addon.CardsByAsset[h.Asset] then
                Addon.CardsByAsset[h.Asset] = {Viewport=vf, Source="hotbar slot heuristic #" .. tostring(i)}
            end
        end
    end

    return scanned, exact, #candidates
end

local function card(parent, p, x, tag, viewport)
    local f = Instance.new("Frame")
    f.Position = UDim2.fromOffset(x, 8)
    f.Size = UDim2.fromOffset(120, 146)
    f.BackgroundColor3 = Color3.fromRGB(29,33,45)
    f.BorderSizePixel = 0
    f.Parent = parent
    rounded(f, 9)

    local visual = Instance.new("Frame")
    visual.Position = UDim2.fromOffset(6,6)
    visual.Size = UDim2.fromOffset(108,88)
    visual.BackgroundColor3 = Color3.fromRGB(18,21,29)
    visual.BorderSizePixel = 0
    visual.ClipsDescendants = true
    visual.Parent = f
    rounded(visual, 7)

    local clone = safeViewportClone(viewport)
    if clone then
        clone.Parent = visual
    else
        local initials = tostring(p and p.DisplayName or "?"):gsub("%b()",""):match("^%s*(%S)") or "?"
        local ph = label(visual, initials:upper(), UDim2.fromScale(0,0), UDim2.fromScale(1,1), true)
        ph.TextSize = 34
        ph.TextXAlignment = Enum.TextXAlignment.Center
    end

    local name = label(f, tostring(p and p.DisplayName or "UNKNOWN"), UDim2.fromOffset(7,98), UDim2.new(1,-14,0,28), true)
    name.TextSize = 10
    name.TextWrapped = true
    name.TextTruncate = Enum.TextTruncate.None

    local final = p and p.Final
    local stat = label(f, string.format("%s  •  DPS %s", tostring(p and p.Element or "?"), fmt(final and final.RawDPS,0)), UDim2.fromOffset(7,126), UDim2.new(1,-14,0,15), false)
    stat.TextSize = 8
    stat.TextColor3 = Color3.fromRGB(163,171,191)

    if tag then
        local t = Instance.new("TextLabel")
        t.Size = UDim2.fromOffset(36,18)
        t.Position = UDim2.fromOffset(7,7)
        t.BackgroundColor3 = Color3.fromRGB(61,76,119)
        t.BackgroundTransparency = 0.08
        t.BorderSizePixel = 0
        t.Text = tag
        t.TextColor3 = Color3.new(1,1,1)
        t.Font = Enum.Font.GothamBold
        t.TextSize = 8
        t.Parent = f
        rounded(t, 9)
    end
    return f
end

local function currentProfiles(state)
    local out = {}
    if not state or type(state.Profiles) ~= "table" then return out end
    for i, h in ipairs(state.Scan and state.Scan.Hotbar or {}) do
        local p = state.Profiles[h.Asset]
        if p then out[#out + 1] = {Profile=p, Asset=h.Asset, Slot=tonumber(h.Slot) or i} end
    end
    table.sort(out, function(a,b) return a.Slot < b.Slot end)
    return out
end

function Addon.Refresh()
    if Addon.Destroyed then return end
    local ok, state = pcall(Core.GetState)
    if not ok or type(state) ~= "table" then
        Status.Text = "Core state unavailable"
        return
    end
    if not state.Scan or not state.Scan.Found then
        Status.Text = "Core has no validated owned scan yet — press SYNC CORE"
        return
    end

    Status.Text = "Indexing real game ViewportFrames…"
    local scanned, exact, hotCandidates = rebuildViewportIndex(state)

    clearFrame(CurrentScroll)
    clearFrame(RecScroll)

    local current = currentProfiles(state)
    local x = 8
    for i, item in ipairs(current) do
        local source = Addon.CardsByAsset[item.Asset]
        local vf = (source and source.Viewport) or Addon.SlotViewports[item.Slot]
        card(CurrentScroll, item.Profile, x, "S"..tostring(item.Slot), vf)
        x = x + 128
    end
    CurrentScroll.CanvasSize = UDim2.fromOffset(math.max(0,x),0)
    CurrentCount.Text = tostring(#current) .. " slots"

    local recommended = state.Recommended and state.Recommended.Team or {}
    x = 8
    local visualHits = 0
    for i, p in ipairs(recommended) do
        local source = p and Addon.CardsByAsset[p.Asset]
        local vf = source and source.Viewport or nil
        if vf then visualHits = visualHits + 1 end
        card(RecScroll, p, x, "#"..tostring(i), vf)
        x = x + 128
    end
    RecScroll.CanvasSize = UDim2.fromOffset(math.max(0,x),0)
    RecommendedCount.Text = tostring(#recommended) .. " units"

    local stage = state.Stage
    local st = stage and (tostring(stage.Gamemode).." / "..tostring(stage.MapName).." / "..tostring(stage.ActName)) or "stage unknown"
    Status.Text = "Synced • " .. st
    FooterText.Text = string.format(
        "Viewport scan: %d frames • exact asset matches: %d • hotbar candidates: %d • recommended icons resolved: %d/%d. Missing icons stay as initials; core data is untouched.",
        scanned, exact, hotCandidates, visualHits, #recommended
    )
end

-- Dragging is isolated to this addon window.
local dragging, dragStart, startPos = false, nil, nil
local c1 = Top.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true; dragStart = input.Position; startPos = Main.Position
    end
end)
Addon.Connections[#Addon.Connections + 1] = c1
local c2 = Top.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)
Addon.Connections[#Addon.Connections + 1] = c2
local c3 = UIS.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local d = input.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)
Addon.Connections[#Addon.Connections + 1] = c3

local visible = true
local c4 = UIS.InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.V then
        visible = not visible
        Main.Visible = visible
    end
end)
Addon.Connections[#Addon.Connections + 1] = c4

function Addon.Destroy()
    if Addon.Destroyed then return end
    Addon.Destroyed = true
    for _, c in ipairs(Addon.Connections) do pcall(function() c:Disconnect() end) end
    if Gui then pcall(function() Gui:Destroy() end) end
    if ENV.AE_STRATEGIST_VISUAL == Addon then ENV.AE_STRATEGIST_VISUAL = nil end
    if Core and Core.VisualAddon == Addon then Core.VisualAddon = nil end
end

-- Do not invoke a heavyweight analysis automatically here. Read the already-computed core state first.
task.spawn(function()
    task.wait(0.25)
    local ok, err = pcall(Addon.Refresh)
    if not ok then
        Status.Text = "Addon startup error: " .. tostring(err)
        warn("[AE Visual Addon] startup refresh", err)
    end
end)

print("[AE Visual Addon] READY", VERSION, "V = hide/show")