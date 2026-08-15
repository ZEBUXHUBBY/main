        local path = state.Path or {}
        if #path < 3 then
            label(MapSurface, "ROUTE NOT FOUND\nEnter the Tournament map or open the active stage, then press PLAY → REFRESH.", UDim2.fromOffset(40, 80), UDim2.new(1, -80, 0, 100), {
                Bold = true, Color = COLORS.Muted, TextSize = 12, Wrap = true, Align = Enum.TextXAlignment.Center,
            })
            return
        end

        RunService.RenderStepped:Wait()
        local size = MapSurface.AbsoluteSize
        local bounds = worldBounds(path)
        if not bounds then return end

        for index = 2, #path do
            local a = toCanvas(path[index - 1].Position, bounds, size)
            local b = toCanvas(path[index].Position, bounds, size)
            line(MapSurface, a, b, 8, Color3.fromRGB(75, 87, 118), 0.1)
            line(MapSurface, a, b, 2, Color3.fromRGB(157, 172, 213), 0.12)
        end

        local spawnPoint = toCanvas(path[1].Position, bounds, size)
        local basePoint = toCanvas(path[#path].Position, bounds, size)
        local spawn = label(MapSurface, "SPAWN", UDim2.fromOffset(spawnPoint.X - 28, spawnPoint.Y - 29), UDim2.fromOffset(56, 18), {
            Bold = true, TextSize = 7, Align = Enum.TextXAlignment.Center,
        })
        spawn.TextColor3 = COLORS.Cyan
        local base = label(MapSurface, "BASE", UDim2.fromOffset(basePoint.X - 28, basePoint.Y + 10), UDim2.fromOffset(56, 18), {
            Bold = true, TextSize = 7, Align = Enum.TextXAlignment.Center,
        })
        base.TextColor3 = COLORS.Bad

        for index, spot in ipairs(copy.SweetSpots or {}) do
            local point = toCanvas(spot.WorldPosition, bounds, size)
            local worldWidth = math.max(bounds.MaxX - bounds.MinX, bounds.MaxZ - bounds.MinZ)
            local diameter = clamp((spot.Range / math.max(1, worldWidth)) * math.min(size.X, size.Y) * 2, 48, 180)

            local rangeCircle = Instance.new("Frame")
            rangeCircle.AnchorPoint = Vector2.new(0.5, 0.5)
            rangeCircle.Position = UDim2.fromOffset(point.X, point.Y)
            rangeCircle.Size = UDim2.fromOffset(diameter, diameter)
            rangeCircle.BackgroundColor3 = index == 1 and COLORS.Good or (index == 2 and COLORS.Warn or COLORS.Accent)
            rangeCircle.BackgroundTransparency = 0.88
            rangeCircle.BorderSizePixel = 0
            rangeCircle.Parent = MapSurface
            rounded(rangeCircle, diameter / 2)
            local strokeObject = Instance.new("UIStroke")
            strokeObject.Thickness = 2
            strokeObject.Transparency = 0.15
            strokeObject.Color = rangeCircle.BackgroundColor3
            strokeObject.Parent = rangeCircle

            local marker = button(MapSurface, spot.Label, UDim2.fromOffset(point.X - 17, point.Y - 17), UDim2.fromOffset(34, 34), nil, {
                Background = rangeCircle.BackgroundColor3,
                Radius = 17,
                TextSize = 13,
            })
            marker.AutoButtonColor = false

            label(MapSurface, spot.Purpose, UDim2.fromOffset(point.X - 58, point.Y + 21), UDim2.fromOffset(116, 18), {
                Bold = true, TextSize = 7, Align = Enum.TextXAlignment.Center,
            }).TextColor3 = rangeCircle.BackgroundColor3
        end

        local legend = label(MapSurface, "A opener     B sustained     C catch / sell & reposition", UDim2.new(0, 18, 1, -27), UDim2.new(1, -36, 0, 18), {
            Color = COLORS.Muted, TextSize = 8, Align = Enum.TextXAlignment.Center,
        })
    end

    local function bullet(parent, textValue, y, color)
        local dot = Instance.new("Frame")
        dot.Position = UDim2.fromOffset(2, y + 6)
        dot.Size = UDim2.fromOffset(7, 7)
        dot.BackgroundColor3 = color or COLORS.Accent
        dot.BorderSizePixel = 0
        dot.Parent = parent
        rounded(dot, 4)
        return label(parent, textValue, UDim2.fromOffset(17, y), UDim2.new(1, -19, 0, 31), {
            Color = COLORS.Muted, TextSize = 10, Wrap = true, YAlign = Enum.TextYAlignment.Top,
        })
    end

    function UI:RenderDecision(state)
        clearChildren(DecisionContent)
        if UI.Mode == "REVIEW" then
            label(DecisionContent, "RUN REVIEW", UDim2.fromOffset(2, 5), UDim2.new(1, -4, 0, 26), {
                Bold = true, TextSize = 18,
            })
            bullet(DecisionContent, "M4 will record score, wave, leaks, money and every decision.", 44, COLORS.Cyan)
            bullet(DecisionContent, "The learner will compare Farm level, target schedule and placements between runs.", 91, COLORS.Warn)
            bullet(DecisionContent, "Current milestone builds the standard action model that Autopilot will execute later.", 148, COLORS.Good)
            return
        end

        if not state or not state.ActionPlan or not state.ActionPlan.Next then
            label(DecisionContent, "PRESS SCAN", UDim2.fromOffset(2, 7), UDim2.new(1, -4, 0, 34), {
                Bold = true, TextSize = 21,
            })
            bullet(DecisionContent, "One scan builds Team + Target + Upgrade + Farm + Sweet Spots.", 54, COLORS.Cyan)
            bullet(DecisionContent, "Nothing runs in the background.", 101, COLORS.Good)
            return
        end

        local action = state.ActionPlan.Next
        local copy = selectedCopy(state)
        label(DecisionContent, tostring(action.Type or "ACTION"), UDim2.fromOffset(2, 0), UDim2.new(1, -4, 0, 22), {
            Bold = true, TextSize = 10, Color = COLORS.Cyan,
        })
        label(DecisionContent, tostring(action.Title or "—"), UDim2.fromOffset(2, 23), UDim2.new(1, -4, 0, 53), {
            Bold = true, TextSize = 21, Wrap = true, YAlign = Enum.TextYAlignment.Top,
        })
        label(DecisionContent, tostring(action.Subtitle or ""), UDim2.fromOffset(2, 77), UDim2.new(1, -4, 0, 24), {
            Color = COLORS.Muted, TextSize = 10,
        })

        local costText = action.Cost and ("¥" .. fmt(action.Cost, 0)) or "NO COST DATA"
        local cost = label(DecisionContent, costText, UDim2.fromOffset(2, 104), UDim2.fromOffset(130, 35), {
            Bold = true, TextSize = 16, Align = Enum.TextXAlignment.Center,
        })
        cost.BackgroundTransparency = 0
        cost.BackgroundColor3 = COLORS.Surface2
        rounded(cost, 12)

        local targetText = "TARGET  " .. tostring(action.Target or (copy and copy.Targeting and copy.Targeting.Primary) or "First"):upper()
        local target = label(DecisionContent, targetText, UDim2.fromOffset(140, 104), UDim2.new(1, -142, 0, 35), {
            Bold = true, TextSize = 10, Align = Enum.TextXAlignment.Center,
        })
        target.BackgroundTransparency = 0
        target.BackgroundColor3 = COLORS.AccentSoft
        rounded(target, 12)

        local y = 151
        for _, reason in ipairs(action.Why or {}) do
            bullet(DecisionContent, reason, y, COLORS.Good)
            y = y + 40
        end

        if copy then
            bullet(DecisionContent, "Target rule: " .. tostring(copy.Targeting and copy.Targeting.Trigger or "default"), y, COLORS.Cyan)
            y = y + 47
            bullet(DecisionContent, "Stop upgrade: U" .. tostring(copy.UpgradePlan and copy.UpgradePlan.TargetLevel or "?") .. " — " .. tostring(copy.UpgradePlan and copy.UpgradePlan.StopReason or "unknown"), y, COLORS.Warn)
            y = y + 55
        end

        local farm = state.FarmPlan
        local farmColor = farm and farm.Decision == "USE" and COLORS.Good or (farm and farm.Decision == "SKIP" and COLORS.Bad or COLORS.Warn)
        local farmText = farm and ("FARM " .. tostring(farm.Decision)) or "FARM UNKNOWN"
        local farmChip = label(DecisionContent, farmText, UDim2.fromOffset(2, math.min(y, 390)), UDim2.new(1, -4, 0, 31), {
            Bold = true, TextSize = 10, Align = Enum.TextXAlignment.Center,
        })
        farmChip.BackgroundTransparency = 0
        farmChip.BackgroundColor3 = farmColor
        rounded(farmChip, 11)
        if farm and farm.PaybackWaves then
            label(DecisionContent, string.format("Payback %.1f waves • target U%s", farm.PaybackWaves, tostring(farm.TargetLevel)), UDim2.fromOffset(2, math.min(y + 32, 422)), UDim2.new(1, -4, 0, 20), {
                Color = COLORS.Muted, TextSize = 9, Align = Enum.TextXAlignment.Center,
            })
        end
    end

    function UI:RenderQueue(state)
        clearChildren(QueueContent)
        if not state or not state.ActionPlan then
            label(QueueContent, "SCAN → choose six → compute Sweet Spots → compare Place / Upgrade / Farm / Save / Target", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), {
                Color = COLORS.Muted, TextSize = 10, Align = Enum.TextXAlignment.Center,
            })
            return
        end

        local queue = state.ActionPlan.Queue or {}
        for index = 1, math.min(4, #queue) do
            local action = queue[index]
            local width = 286
            local frame = Instance.new("Frame")
            frame.Position = UDim2.fromOffset((index - 1) * (width + 10), 0)
            frame.Size = UDim2.fromOffset(width, 42)
            frame.BackgroundColor3 = index == 1 and COLORS.AccentSoft or COLORS.Surface2
            frame.BackgroundTransparency = index == 1 and 0.05 or 0.32
            frame.BorderSizePixel = 0
            frame.Parent = QueueContent
            rounded(frame, 12)

            local number = label(frame, tostring(index), UDim2.fromOffset(7, 7), UDim2.fromOffset(28, 28), {
                Bold = true, TextSize = 12, Align = Enum.TextXAlignment.Center,
            })
            number.BackgroundTransparency = 0
            number.BackgroundColor3 = index == 1 and COLORS.Good or COLORS.AccentSoft
            rounded(number, 9)

            label(frame, tostring(action.Title or action.Type or "ACTION"), UDim2.fromOffset(43, 3), UDim2.new(1, -49, 0, 22), {
                Bold = true, TextSize = 9, Truncate = Enum.TextTruncate.AtEnd,
            })
            label(frame, action.Cost and ("¥" .. fmt(action.Cost, 0)) or tostring(action.Type or ""), UDim2.fromOffset(43, 22), UDim2.new(1, -49, 0, 16), {
                Color = COLORS.Muted, TextSize = 8,
            })
        end
    end

    function UI:Render()
        if self.Destroyed then return end
        local state = Brain:GetState()
        if state and not self.Resolver.Built then buildResolver(state) end

        if self.Mode == "PLAY" and state then
            TeamTitle.Text = "LIVE DECISION TEAM"
            TeamSub.Text = "Manual REFRESH only • no background scan"
            ScanButton.Text = "REFRESH"
        elseif self.Mode == "REVIEW" then
            TeamTitle.Text = "LAST RUN SETUP"
            TeamSub.Text = "Learning layer arrives in M4"
            ScanButton.Text = "SCAN"
        else
            TeamTitle.Text = "YOUR BEST SIX"
            TeamSub.Text = "Tap a unit to inspect placement + target"
            ScanButton.Text = "SCAN"
        end

        self:RenderHeader(state)
        self:RenderTeam(state)
        self:RenderMap(state)
        self:RenderDecision(state)
