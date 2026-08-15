--[[
AE TOURNAMENT AUTOPILOT | CARTOONY MINIMAL UI M1
------------------------------------------------
Seamless PLAN / PLAY / REVIEW shell over Brain M1.
Game-owned visuals are used in this order:
1) live ImageLabel / ViewportFrame already rendered by the game
2) ReplicatedStorage.Assets.Units model rendered into a fresh ViewportFrame
3) text placeholder only when the game exposes neither
]]

return function(Brain, config)
    config = config or {}

    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace = game:GetService("Workspace")
    local LocalPlayer = Players.LocalPlayer
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    local UI = {
        Version = "ui-m1.0.0",
        Brain = Brain,
        Connections = {},
        Mode = "PLAN",
        Resolver = {ByAsset = {}, BySlot = {}, Modifier = {}, Built = false},
        Destroyed = false,
    }

    local old = PlayerGui:FindFirstChild("AE_Tournament_Autopilot_M1")
    if old then old:Destroy() end

    local COLORS = {
        Ink = Color3.fromRGB(248, 249, 252),
        Muted = Color3.fromRGB(167, 177, 199),
        Deep = Color3.fromRGB(12, 16, 24),
        Surface = Color3.fromRGB(24, 29, 42),
        Surface2 = Color3.fromRGB(31, 37, 53),
        Accent = Color3.fromRGB(91, 116, 211),
        AccentSoft = Color3.fromRGB(68, 83, 143),
        Good = Color3.fromRGB(81, 188, 135),
        Warn = Color3.fromRGB(240, 178, 77),
        Bad = Color3.fromRGB(230, 94, 99),
        Cyan = Color3.fromRGB(70, 195, 219),
    }

    local function norm(value)
        return tostring(value or ""):lower():gsub("[^%w]", "")
    end

    local function clamp(value, minimum, maximum)
        value = tonumber(value) or minimum
        if value < minimum then return minimum end
        if value > maximum then return maximum end
        return value
    end

    local function fmt(value, digits)
        value = tonumber(value)
        if not value then return "—" end
        digits = digits or 0
        local absolute = math.abs(value)
        if absolute >= 1e9 then return string.format("%.2fB", value / 1e9) end
        if absolute >= 1e6 then return string.format("%.2fM", value / 1e6) end
        if absolute >= 1e3 then return string.format("%.2fK", value / 1e3) end
        local text = string.format("%." .. tostring(digits) .. "f", value)
        return text:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
    end

    local function rounded(instance, radius)
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, radius or 12)
        corner.Parent = instance
        return corner
    end

    local function padding(instance, left, right, top, bottom)
        local object = Instance.new("UIPadding")
        object.PaddingLeft = UDim.new(0, left or 0)
        object.PaddingRight = UDim.new(0, right or left or 0)
        object.PaddingTop = UDim.new(0, top or 0)
        object.PaddingBottom = UDim.new(0, bottom or top or 0)
        object.Parent = instance
        return object
    end

    local function label(parent, value, position, size, options)
        options = options or {}
        local object = Instance.new("TextLabel")
        object.BackgroundTransparency = 1
        object.Position = position or UDim2.new()
        object.Size = size or UDim2.new(1, 0, 0, 24)
        object.Text = value or ""
        object.TextColor3 = options.Color or COLORS.Ink
        object.Font = options.Bold and Enum.Font.GothamBold or Enum.Font.Gotham
        object.TextSize = options.TextSize or 12
        object.TextXAlignment = options.Align or Enum.TextXAlignment.Left
        object.TextYAlignment = options.YAlign or Enum.TextYAlignment.Center
        object.TextWrapped = options.Wrap == true
        object.TextTruncate = options.Truncate or Enum.TextTruncate.None
        object.ZIndex = options.ZIndex or 1
        object.Parent = parent
        return object
    end

    local function button(parent, value, position, size, callback, options)
        options = options or {}
        local object = Instance.new("TextButton")
        object.Position = position
        object.Size = size
        object.BackgroundColor3 = options.Background or COLORS.AccentSoft
        object.BackgroundTransparency = options.Transparency or 0
        object.BorderSizePixel = 0
        object.Text = value or ""
        object.TextColor3 = options.Color or COLORS.Ink
        object.Font = options.Bold == false and Enum.Font.Gotham or Enum.Font.GothamBold
        object.TextSize = options.TextSize or 11
        object.AutoButtonColor = true
        object.ZIndex = options.ZIndex or 2
        object.Parent = parent
        rounded(object, options.Radius or 10)
        if callback then
            UI.Connections[#UI.Connections + 1] = object.MouseButton1Click:Connect(callback)
        end
        return object
    end

    local function surface(parent, position, size, transparency)
        local frame = Instance.new("Frame")
        frame.Position = position
        frame.Size = size
        frame.BackgroundColor3 = COLORS.Surface
        frame.BackgroundTransparency = transparency or 0.08
        frame.BorderSizePixel = 0
        frame.Parent = parent
        rounded(frame, 16)
        return frame
    end

    local function clearChildren(parent, keepClasses)
        keepClasses = keepClasses or {}
        for _, child in ipairs(parent:GetChildren()) do
            if not keepClasses[child.ClassName] then child:Destroy() end
        end
    end

    local Gui = Instance.new("ScreenGui")
    Gui.Name = "AE_Tournament_Autopilot_M1"
    Gui.ResetOnSpawn = false
    Gui.IgnoreGuiInset = false
    Gui.DisplayOrder = 100100
    Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    Gui.Parent = PlayerGui
    UI.Gui = Gui

    local Main = Instance.new("Frame")
    Main.Name = "Main"
    Main.Size = UDim2.fromOffset(1260, 720)
    Main.Position = UDim2.new(0.5, -630, 0.5, -360)
    Main.BackgroundColor3 = COLORS.Deep
    Main.BackgroundTransparency = 0.035
    Main.BorderSizePixel = 0
    Main.Parent = Gui
    rounded(Main, 22)
    UI.Main = Main

    local scale = Instance.new("UIScale")
    scale.Parent = Main
    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
    scale.Scale = math.min(1, viewport.X / 1320, viewport.Y / 770)

    local subtleStroke = Instance.new("UIStroke")
    subtleStroke.Thickness = 1
    subtleStroke.Transparency = 0.82
    subtleStroke.Color = Color3.fromRGB(120, 138, 185)
    subtleStroke.Parent = Main

    -- Header ------------------------------------------------------------------

    local Header = Instance.new("Frame")
    Header.Name = "Header"
    Header.Size = UDim2.new(1, 0, 0, 96)
    Header.BackgroundTransparency = 1
    Header.Parent = Main

    local Title = label(Header, "TOURNAMENT BRAIN", UDim2.fromOffset(24, 15), UDim2.fromOffset(240, 28), {
        Bold = true, TextSize = 18,
    })
    local StageText = label(Header, "Ready for a one-shot scan", UDim2.fromOffset(24, 45), UDim2.fromOffset(480, 23), {
        Color = COLORS.Muted, TextSize = 11,
    })

    local ModifierRow = Instance.new("Frame")
    ModifierRow.Name = "Modifiers"
    ModifierRow.Position = UDim2.fromOffset(520, 17)
    ModifierRow.Size = UDim2.fromOffset(430, 56)
    ModifierRow.BackgroundTransparency = 1
    ModifierRow.Parent = Header

    local ModifierLayout = Instance.new("UIListLayout")
    ModifierLayout.FillDirection = Enum.FillDirection.Horizontal
    ModifierLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    ModifierLayout.Padding = UDim.new(0, 8)
    ModifierLayout.Parent = ModifierRow

    local ModeRow = Instance.new("Frame")
    ModeRow.Position = UDim2.new(1, -286, 0, 18)
    ModeRow.Size = UDim2.fromOffset(168, 38)
    ModeRow.BackgroundColor3 = COLORS.Surface
    ModeRow.BackgroundTransparency = 0.15
    ModeRow.BorderSizePixel = 0
    ModeRow.Parent = Header
    rounded(ModeRow, 12)

    local ScanButton
    local CloseButton
    local onScanClick

    local ModeButtons = {}
    local function setMode(mode)
        UI.Mode = mode
        for name, object in pairs(ModeButtons) do
            object.BackgroundTransparency = name == mode and 0 or 1
            object.TextColor3 = name == mode and COLORS.Ink or COLORS.Muted
        end
