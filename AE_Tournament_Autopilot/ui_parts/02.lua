        UI:Render()
    end

    for index, mode in ipairs({"PLAN", "PLAY", "REVIEW"}) do
        local object = button(ModeRow, mode, UDim2.fromOffset((index - 1) * 56, 0), UDim2.fromOffset(56, 38), function()
            setMode(mode)
        end, {
            Background = COLORS.AccentSoft,
            Transparency = mode == "PLAN" and 0 or 1,
            Radius = 10,
            TextSize = 9,
        })
        ModeButtons[mode] = object
    end

    ScanButton = button(Header, "SCAN", UDim2.new(1, -108, 0, 18), UDim2.fromOffset(66, 38), function()
        if onScanClick then onScanClick() end
    end, {
        Background = COLORS.Accent,
        Radius = 12,
    })

    CloseButton = button(Header, "×", UDim2.new(1, -38, 0, 18), UDim2.fromOffset(32, 38), function()
        UI:Destroy()
    end, {
        Background = COLORS.Surface2,
        TextSize = 18,
        Radius = 12,
    })

    -- Main regions ------------------------------------------------------------

    local TeamPanel = surface(Main, UDim2.fromOffset(18, 102), UDim2.fromOffset(284, 510), 0.18)
    TeamPanel.Name = "TeamPanel"
    local TeamTitle = label(TeamPanel, "YOUR BEST SIX", UDim2.fromOffset(16, 12), UDim2.fromOffset(200, 24), {
        Bold = true, TextSize = 12,
    })
    local TeamSub = label(TeamPanel, "Tap a unit to inspect placement + target", UDim2.fromOffset(16, 34), UDim2.fromOffset(250, 18), {
        Color = COLORS.Muted, TextSize = 9,
    })
    local TeamList = Instance.new("Frame")
    TeamList.Position = UDim2.fromOffset(10, 58)
    TeamList.Size = UDim2.new(1, -20, 1, -68)
    TeamList.BackgroundTransparency = 1
    TeamList.Parent = TeamPanel

    local MapPanel = surface(Main, UDim2.fromOffset(314, 102), UDim2.fromOffset(574, 510), 0.13)
    MapPanel.Name = "MapPanel"
    local MapTitle = label(MapPanel, "TACTICAL MAP", UDim2.fromOffset(18, 13), UDim2.fromOffset(180, 24), {
        Bold = true, TextSize = 12,
    })
    local MapUnit = label(MapPanel, "Select a unit", UDim2.fromOffset(18, 36), UDim2.fromOffset(380, 18), {
        Color = COLORS.Muted, TextSize = 10,
    })
    local MapSurface = Instance.new("Frame")
    MapSurface.Name = "MapSurface"
    MapSurface.Position = UDim2.fromOffset(16, 68)
    MapSurface.Size = UDim2.new(1, -32, 1, -84)
    MapSurface.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
    MapSurface.BackgroundTransparency = 0.12
    MapSurface.BorderSizePixel = 0
    MapSurface.ClipsDescendants = true
    MapSurface.Parent = MapPanel
    rounded(MapSurface, 16)

    local DecisionPanel = surface(Main, UDim2.fromOffset(900, 102), UDim2.fromOffset(342, 510), 0.16)
    DecisionPanel.Name = "DecisionPanel"
    local DecisionTitle = label(DecisionPanel, "NEXT", UDim2.fromOffset(18, 13), UDim2.fromOffset(120, 25), {
        Bold = true, TextSize = 12, Color = COLORS.Cyan,
    })
    local DecisionContent = Instance.new("Frame")
    DecisionContent.Position = UDim2.fromOffset(16, 44)
    DecisionContent.Size = UDim2.new(1, -32, 1, -58)
    DecisionContent.BackgroundTransparency = 1
    DecisionContent.Parent = DecisionPanel

    local QueuePanel = surface(Main, UDim2.fromOffset(18, 624), UDim2.new(1, -36, 0, 78), 0.16)
    QueuePanel.Name = "QueuePanel"
    local QueueTitle = label(QueuePanel, "ACTION QUEUE", UDim2.fromOffset(16, 8), UDim2.fromOffset(120, 18), {
        Bold = true, TextSize = 9, Color = COLORS.Muted,
    })
    local QueueContent = Instance.new("Frame")
    QueueContent.Position = UDim2.fromOffset(16, 28)
    QueueContent.Size = UDim2.new(1, -32, 0, 42)
    QueueContent.BackgroundTransparency = 1
    QueueContent.Parent = QueuePanel

    -- Game visual resolver ----------------------------------------------------

    local function nearbyText(instance)
        local node = instance
        local words = {}
        for _ = 1, 5 do
            node = node and node.Parent
            if not node then break end
            for _, descendant in ipairs(node:GetDescendants()) do
                if (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) and descendant.Visible then
                    local text = tostring(descendant.Text)
                    if text ~= "" and #text < 70 then
                        words[#words + 1] = text
                        if #words >= 12 then return norm(table.concat(words, " ")) end
                    end
                end
            end
        end
        return norm(table.concat(words, " "))
    end

    local function buildResolver(state)
        UI.Resolver = {ByAsset = {}, BySlot = {}, Modifier = {}, Built = true}
        local aliases = {}
        for _, copy in ipairs(state and state.AllCopies or {}) do
            aliases[norm(copy.Asset)] = copy.Asset
            aliases[norm(copy.DisplayName)] = copy.Asset
        end

        local candidates = {}
        for _, descendant in ipairs(PlayerGui:GetDescendants()) do
            if descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") or descendant:IsA("ViewportFrame") then
                if descendant.Visible then
                    local words = nearbyText(descendant)
                    for alias, asset in pairs(aliases) do
                        if #alias >= 4 and words:find(alias, 1, true) then
                            if not UI.Resolver.ByAsset[asset] then UI.Resolver.ByAsset[asset] = descendant end
                        end
                    end

                    local size = descendant.AbsoluteSize
                    local position = descendant.AbsolutePosition
                    if size.X >= 28 and size.Y >= 28 and size.X <= 210 and size.Y <= 210 and position.Y > viewport.Y * 0.55 then
                        candidates[#candidates + 1] = descendant
                    end
                end
            end
        end

        table.sort(candidates, function(a, b)
            if math.abs(a.AbsolutePosition.X - b.AbsolutePosition.X) > 4 then
                return a.AbsolutePosition.X < b.AbsolutePosition.X
            end
            return a.AbsolutePosition.Y < b.AbsolutePosition.Y
        end)

        local unique = {}
        for _, candidate in ipairs(candidates) do
            local key = tostring(math.floor(candidate.AbsolutePosition.X / 5))
            if not unique[key] then
                unique[key] = true
                UI.Resolver.BySlot[#UI.Resolver.BySlot + 1] = candidate
            end
        end

        local contextLabels = {
            bosswaves = "BossWaves",
            speedy = "Speedy",
            hardmode = "HardMode",
            shielded = "Shielded",
        }
        for _, descendant in ipairs(PlayerGui:GetDescendants()) do
            if descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
                local words = nearbyText(descendant)
                for textKey, resultKey in pairs(contextLabels) do
                    if words:find(textKey, 1, true) and not UI.Resolver.Modifier[resultKey] then
                        UI.Resolver.Modifier[resultKey] = descendant
                    end
                end
            end
        end
    end

    local function cloneVisual(source, parent)
        if not source then return false end
        local ok, clone = pcall(function() return source:Clone() end)
        if not ok or not clone then return false end
        clone.Position = UDim2.fromScale(0, 0)
        clone.Size = UDim2.fromScale(1, 1)
        clone.BackgroundTransparency = 1
        clone.BorderSizePixel = 0
        clone.Visible = true
        if clone:IsA("ImageLabel") or clone:IsA("ImageButton") then
            clone.ScaleType = Enum.ScaleType.Fit
            clone.ImageTransparency = 0
        end
        for _, descendant in ipairs(clone:GetDescendants()) do
            if descendant:IsA("BaseScript") then descendant:Destroy() end
            if descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then descendant.ScaleType = Enum.ScaleType.Fit end
        end
        clone.Parent = parent
        return true
    end

    local UnitModels = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Units")

    local function findUnitModel(asset)
        if not UnitModels then return nil end
        local folder = UnitModels:FindFirstChild(asset)
        if not folder then return nil end
        if folder:IsA("Model") then return folder end
        for _, name in ipairs({"Model", "Shiny", "Default", "Unit"}) do
            local model = folder:FindFirstChild(name)
            if model and model:IsA("Model") then return model end
        end
        return folder:FindFirstChildWhichIsA("Model", true)
    end

    local function modelVisual(asset, parent)
        local source = findUnitModel(asset)
        if not source then return false end
        local ok, model = pcall(function() return source:Clone() end)
        if not ok or not model then return false end

        local viewportFrame = Instance.new("ViewportFrame")
        viewportFrame.Size = UDim2.fromScale(1, 1)
        viewportFrame.BackgroundTransparency = 1
        viewportFrame.BorderSizePixel = 0
        viewportFrame.Ambient = Color3.fromRGB(210, 210, 220)
        viewportFrame.LightColor = Color3.fromRGB(255, 246, 234)
        viewportFrame.LightDirection = Vector3.new(-1, -1, -1)
        viewportFrame.Parent = parent

