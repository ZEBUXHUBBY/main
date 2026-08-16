        local world = Instance.new("WorldModel")
        world.Parent = viewportFrame
        model.Parent = world
        for _, descendant in ipairs(model:GetDescendants()) do
            if descendant:IsA("BasePart") then
                descendant.Anchored = true
                descendant.CanCollide = false
            end
        end

        local boundingCFrame = model:GetBoundingBox()
        local pivot = model:GetPivot()
        model:PivotTo(CFrame.new(-boundingCFrame.Position) * pivot)
        local _, size = model:GetBoundingBox()
        local maximum = math.max(size.X, size.Y, size.Z, 1)
        local cameraObject = Instance.new("Camera")
        cameraObject.FieldOfView = 32
        cameraObject.CFrame = CFrame.lookAt(Vector3.new(maximum * 1.25, maximum * 0.12, maximum * 2.45), Vector3.new(0, maximum * 0.05, 0))
        cameraObject.Parent = viewportFrame
        viewportFrame.CurrentCamera = cameraObject
        return true
    end

    local function addUnitVisual(parent, copy, slotIndex)
        local source = UI.Resolver.ByAsset[copy.Asset] or UI.Resolver.BySlot[slotIndex]
        if cloneVisual(source, parent) then return "GAME UI" end
        if modelVisual(copy.Asset, parent) then return "GAME MODEL" end
        local placeholder = label(parent, tostring(copy.DisplayName):sub(1, 1):upper(), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), {
            Bold = true, TextSize = 28, Align = Enum.TextXAlignment.Center,
        })
        return "TEXT"
    end

    local function modifierChip(parent, textValue, resolverKey, color)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.fromOffset(math.max(92, #textValue * 7 + 38), 34)
        frame.BackgroundColor3 = color or COLORS.Surface2
        frame.BackgroundTransparency = 0.05
        frame.BorderSizePixel = 0
        frame.Parent = parent
        rounded(frame, 13)

        local iconBox = Instance.new("Frame")
        iconBox.Position = UDim2.fromOffset(5, 5)
        iconBox.Size = UDim2.fromOffset(24, 24)
        iconBox.BackgroundTransparency = 1
        iconBox.Parent = frame
        if not cloneVisual(UI.Resolver.Modifier[resolverKey], iconBox) then
            local dot = Instance.new("Frame")
            dot.Size = UDim2.fromOffset(12, 12)
            dot.Position = UDim2.fromOffset(6, 6)
            dot.BackgroundColor3 = color or COLORS.Warn
            dot.BorderSizePixel = 0
            dot.Parent = iconBox
            rounded(dot, 6)
        end

        label(frame, textValue, UDim2.fromOffset(33, 0), UDim2.new(1, -38, 1, 0), {
            Bold = true, TextSize = 9,
        })
        return frame
    end

    -- Drawing -----------------------------------------------------------------

    -- Draw from the midpoint rather than rotating around the start point.
    -- A small overlap hides sub-pixel gaps at waypoint turns, so the route reads
    -- as one continuous road instead of disconnected bars.
    local function line(parent, a, b, thickness, color, transparency)
        local delta = b - a
        local length = delta.Magnitude
        local width = thickness or 5
        if length <= 0.01 then return nil end

        local midpoint = (a + b) * 0.5
        local overlap = math.max(2, width * 0.7)
        local object = Instance.new("Frame")
        object.AnchorPoint = Vector2.new(0.5, 0.5)
        object.Position = UDim2.fromOffset(midpoint.X, midpoint.Y)
        object.Size = UDim2.fromOffset(length + overlap * 2, width)
        object.Rotation = math.deg(math.atan2(delta.Y, delta.X))
        object.BackgroundColor3 = color or COLORS.Muted
        object.BackgroundTransparency = transparency or 0
        object.BorderSizePixel = 0
        object.Parent = parent
        rounded(object, math.max(2, width / 2))
        return object
    end

    local function worldBounds(path)
        local minimumX, maximumX, minimumZ, maximumZ = math.huge, -math.huge, math.huge, -math.huge
        for _, point in ipairs(path or {}) do
            local position = point.Position
            minimumX = math.min(minimumX, position.X)
            maximumX = math.max(maximumX, position.X)
            minimumZ = math.min(minimumZ, position.Z)
            maximumZ = math.max(maximumZ, position.Z)
        end
        if minimumX == math.huge then return nil end
        if maximumX - minimumX < 1 then maximumX = minimumX + 1 end
        if maximumZ - minimumZ < 1 then maximumZ = minimumZ + 1 end
        return {MinX = minimumX, MaxX = maximumX, MinZ = minimumZ, MaxZ = maximumZ}
    end

    local function toCanvas(position, bounds, size)
        local x = 24 + ((position.X - bounds.MinX) / (bounds.MaxX - bounds.MinX)) * math.max(1, size.X - 48)
        local y = 24 + ((position.Z - bounds.MinZ) / (bounds.MaxZ - bounds.MinZ)) * math.max(1, size.Y - 48)
        return Vector2.new(x, y)
    end

    local function selectedCopy(state)
        return state and state.RecommendedTeam and state.RecommendedTeam[state.SelectedUnit or 1] or nil
    end

    function UI:RenderHeader(state)
        clearChildren(ModifierRow, {UIListLayout = true})
        if not state then
            StageText.Text = "Ready for a one-shot scan"
            return
        end

        local context = state.Context or {}
        StageText.Text = tostring(context.Gamemode or "Tournament") .. "  •  " .. tostring(context.MapName or "UNKNOWN") .. "  •  " .. tostring(context.Difficulty or "UNKNOWN") .. "  •  score model " .. tostring(context.ScoreConfidence or "PROXY")

        if #(context.Labels or {}) == 0 then
            modifierChip(ModifierRow, "NO MODIFIER TEXT", nil, COLORS.Surface2)
        else
            for _, item in ipairs(context.Labels) do
                local normalized = norm(item)
                local key = normalized:find("boss", 1, true) and "BossWaves" or (normalized:find("speed", 1, true) and "Speedy" or (normalized:find("hard", 1, true) and "HardMode" or "Shielded"))
                local color = key == "BossWaves" and COLORS.Bad or (key == "Speedy" and COLORS.Cyan or (key == "HardMode" and COLORS.Warn or COLORS.Accent))
                modifierChip(ModifierRow, item, key, color)
            end
        end
    end

    function UI:RenderTeam(state)
        clearChildren(TeamList)
        if not state or #(state.RecommendedTeam or {}) == 0 then
            label(TeamList, "Press SCAN to build the six-slot Tournament plan.", UDim2.fromOffset(14, 24), UDim2.new(1, -28, 0, 80), {
                Color = COLORS.Muted, TextSize = 11, Wrap = true,
            })
            return
        end

        for index, copy in ipairs(state.RecommendedTeam) do
            local selected = index == (state.SelectedUnit or 1)
            local card = Instance.new("TextButton")
            card.Position = UDim2.fromOffset(0, (index - 1) * 71)
            card.Size = UDim2.new(1, 0, 0, 64)
            card.BackgroundColor3 = selected and COLORS.AccentSoft or COLORS.Surface2
            card.BackgroundTransparency = selected and 0.05 or 0.3
            card.BorderSizePixel = 0
            card.Text = ""
            card.Parent = TeamList
            rounded(card, 14)

            local visual = Instance.new("Frame")
            visual.Position = UDim2.fromOffset(5, 5)
            visual.Size = UDim2.fromOffset(54, 54)
            visual.BackgroundColor3 = Color3.fromRGB(15, 19, 29)
            visual.BackgroundTransparency = 0.05
            visual.BorderSizePixel = 0
            visual.ClipsDescendants = true
            visual.Parent = card
            rounded(visual, 13)
            addUnitVisual(visual, copy, index)

            label(card, copy.DisplayName, UDim2.fromOffset(68, 7), UDim2.new(1, -74, 0, 20), {
                Bold = true, TextSize = 10, Truncate = Enum.TextTruncate.AtEnd,
            })
            label(card, tostring(copy.Role or "DPS") .. "  •  " .. fmt(copy.CapDPS, 0), UDim2.fromOffset(68, 27), UDim2.new(1, -74, 0, 16), {
                Color = COLORS.Muted, TextSize = 8, Truncate = Enum.TextTruncate.AtEnd,
            })

            local targetText = tostring(copy.Targeting and copy.Targeting.Primary or "First")
            local target = label(card, targetText:upper(), UDim2.fromOffset(68, 45), UDim2.fromOffset(74, 14), {
                Bold = true, TextSize = 7, Align = Enum.TextXAlignment.Center,
            })
            target.BackgroundTransparency = 0
            target.BackgroundColor3 = COLORS.AccentSoft
            rounded(target, 7)

            local upgrade = label(card, "→ U" .. tostring(copy.UpgradePlan and copy.UpgradePlan.TargetLevel or "?"), UDim2.new(1, -78, 0, 43), UDim2.fromOffset(68, 17), {
                Bold = true, TextSize = 8, Align = Enum.TextXAlignment.Right,
            })
            upgrade.TextColor3 = COLORS.Warn

            if type(copy.TraitIcon) == "string" and copy.TraitIcon ~= "" then
                local traitIcon = Instance.new("ImageLabel")
                traitIcon.Position = UDim2.new(1, -119, 0, 42)
                traitIcon.Size = UDim2.fromOffset(18, 18)
                traitIcon.BackgroundTransparency = 1
                traitIcon.Image = copy.TraitIcon
                traitIcon.ScaleType = Enum.ScaleType.Fit
                traitIcon.Parent = card
            end
            local equipmentIconValue = copy.EquipmentIcons and copy.EquipmentIcons[1]
            if type(equipmentIconValue) == "string" and equipmentIconValue ~= "" then
                local equipmentIcon = Instance.new("ImageLabel")
                equipmentIcon.Position = UDim2.new(1, -98, 0, 42)
                equipmentIcon.Size = UDim2.fromOffset(18, 18)
                equipmentIcon.BackgroundTransparency = 1
                equipmentIcon.Image = equipmentIconValue
                equipmentIcon.ScaleType = Enum.ScaleType.Fit
                equipmentIcon.Parent = card
            end

            UI.Connections[#UI.Connections + 1] = card.MouseButton1Click:Connect(function()
                Brain:SelectUnit(index)
                UI:Render()
            end)
        end
    end

    function UI:RenderMap(state)
        clearChildren(MapSurface, {UICorner = true})
        local copy = selectedCopy(state)
        if not state or not copy then
            MapUnit.Text = "Select a unit"
            label(MapSurface, "Path + Sweet Spots will appear after SCAN inside a Tournament match.", UDim2.fromOffset(28, 34), UDim2.new(1, -56, 0, 70), {
                Color = COLORS.Muted, TextSize = 12, Wrap = true, Align = Enum.TextXAlignment.Center,
            })
            return
        end

        MapUnit.Text = copy.DisplayName .. "  •  target " .. tostring(copy.Targeting and copy.Targeting.Primary or "First") .. "  •  target upgrade U" .. tostring(copy.UpgradePlan and copy.UpgradePlan.TargetLevel or "?")

