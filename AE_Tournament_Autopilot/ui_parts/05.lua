        self:RenderQueue(state)
    end

    -- One button, two explicit one-shot paths. Nothing runs in the background.
    onScanClick = function()
        if UI.Scanning then return end
        UI.Scanning = true
        ScanButton.Text = "…"

        if UI.Mode == "PLAY" and Brain:GetState() then
            StageText.Text = "Refreshing route, modifiers and current Yen once…"
            task.spawn(function()
                local ok, stateOrError = pcall(function()
                    local state = Brain:RefreshTactical()
                    return state
                end)
                UI.Scanning = false
                ScanButton.Text = "REFRESH"
                if not ok then
                    StageText.Text = "Refresh error: " .. tostring(stateOrError)
                    return
                end
                UI:Render()
            end)
            return
        end

        StageText.Text = "Reading inventory, modifiers, route and economy once…"
        task.spawn(function()
            local ok, state, analysisError = pcall(function()
                local result, err = Brain:Analyze()
                return result, err
            end)
            UI.Scanning = false
            ScanButton.Text = UI.Mode == "PLAY" and "REFRESH" or "SCAN"
            if not ok then
                StageText.Text = "Scan error: " .. tostring(state)
                return
            end
            if not state then
                StageText.Text = "Scan failed: " .. tostring(analysisError)
                return
            end
            UI.Resolver.Built = false
            UI:Render()
        end)
    end

    -- Drag --------------------------------------------------------------------

    local dragging = false
    local dragStart = nil
    local startPosition = nil

    UI.Connections[#UI.Connections + 1] = Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPosition = Main.Position
        end
    end)

    UI.Connections[#UI.Connections + 1] = UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            Main.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
        end
    end)

    UI.Connections[#UI.Connections + 1] = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)

    function UI:Destroy()
        if self.Destroyed then return end
        self.Destroyed = true
        for _, connection in ipairs(self.Connections) do pcall(function() connection:Disconnect() end) end
        self.Connections = {}
        if self.Gui then self.Gui:Destroy() end
    end

    UI:Render()
    return UI
end
