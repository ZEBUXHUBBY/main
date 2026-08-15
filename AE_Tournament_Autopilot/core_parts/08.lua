
        return {
            Next = nextAction,
            Queue = queue,
            Yen = yen,
        }
    end

    -- -------------------------------------------------------------------------
    -- Public analysis
    -- -------------------------------------------------------------------------

    function Brain:Analyze()
        if self.Destroyed then return nil, "brain destroyed" end
        self.Diagnostics = {}

        local database = loadDatabases()
        local profileData, profileError = scanProfileData()
        if not profileData then
            return nil, profileError
        end

        local owned, byId = parseOwned(profileData, database)
        local hotbar = parseHotbar(profileData, owned, byId, database)
        local context = detectContext()

        local allCopies = {}
        local bestByAsset = {}
        for _, record in ipairs(owned) do
            local template = buildTemplate(record.Asset, database)
            if template then
                local copy = applyOwnedCopy(template, record, database)
                if copy then
                    allCopies[#allCopies + 1] = copy
                    local previous = bestByAsset[copy.Asset]
                    if not previous or copy.CapDPS > previous.CapDPS then bestByAsset[copy.Asset] = copy end
                end
            end
        end

        local maximum = rankContext(bestByAsset)
        local ranked = {}
        for _, copy in pairs(bestByAsset) do
            local reasons = {}
            copy.TournamentScore = rankUnit(copy, context, maximum, reasons)
            copy.ScoreReasons = reasons
            if copy.TournamentScore > -math.huge then ranked[#ranked + 1] = copy end
        end
        table.sort(ranked, function(a, b) return (a.TournamentScore or -math.huge) > (b.TournamentScore or -math.huge) end)

        local recommended = {}
        local deferredHybrids = {}
        for _, copy in ipairs(ranked) do
            if copy.Farm then
                deferredHybrids[#deferredHybrids + 1] = copy
            else
                recommended[#recommended + 1] = copy
                if #recommended >= 6 then break end
            end
        end
        -- Combat six stays Farm-free. A hybrid Farm is used only when fewer than six
        -- non-Farm combat copies exist, and the separate FarmPlan still explains the trade-off.
        if #recommended < 6 then
            for _, copy in ipairs(deferredHybrids) do
                if (copy.CapDPS or 0) > 0 then
                    recommended[#recommended + 1] = copy
                    if #recommended >= 6 then break end
                end
            end
        end

        local currentTeam = {}
        for _, slot in ipairs(hotbar) do
            local selected = nil
            if slot.Record then
                for _, copy in ipairs(allCopies) do
                    if copy.ID == slot.Record.ID then selected = copy break end
                end
            end
            selected = selected or bestByAsset[slot.Asset]
            if selected then currentTeam[#currentTeam + 1] = selected end
        end

        local path, pathQuality = discoverPath()
        for index, copy in ipairs(recommended) do
            copy.Role = roleFor(copy, context, index)
            copy.Targeting = targetPriority(copy, context, copy.Role)
            copy.UpgradePlan = planUpgrade(copy, context)
            copy.SweetSpots = sweetSpots(copy, path, context)
        end

        local farmPlan = evaluateFarm(bestByAsset, recommended, context)
        local state = {
            Version = self.Version,
            Context = context,
            ProfileFound = true,
            OwnedCount = #owned,
            Owned = owned,
            Hotbar = hotbar,
            CurrentTeam = currentTeam,
            RecommendedTeam = recommended,
            AllCopies = allCopies,
            BestByAsset = bestByAsset,
            FarmPlan = farmPlan,
            Path = path,
            PathQuality = pathQuality,
            SelectedUnit = 1,
            Database = database,
            Diagnostics = self.Diagnostics,
            Confidence = {
                Score = "PROXY",
                Geometry = #path >= 3 and pathQuality or "UNKNOWN",
                Economy = farmPlan.Exact and "EXACT FARM FIELDS" or "UNKNOWN",
            },
        }

        state.ActionPlan = buildActionPlan(state)
        self.State = state
        appendDiagnostic("owned=" .. tostring(#owned) .. " hotbar=" .. tostring(#hotbar) .. " recommended=" .. tostring(#recommended))
        appendDiagnostic("pathPoints=" .. tostring(#path) .. " pathQuality=" .. tostring(pathQuality))
        return state, nil
    end

    function Brain:SelectUnit(index)
        if not self.State then return nil end
        index = clamp(index, 1, math.max(1, #(self.State.RecommendedTeam or {})))
        self.State.SelectedUnit = index
        self.State.ActionPlan = buildActionPlan(self.State)
        return self.State.RecommendedTeam[index]
    end

    function Brain:GetState()
        return self.State
    end

    function Brain:RefreshTactical()
        if not self.State then return self:Analyze() end
        self.State.Context = detectContext()
        local path, quality = discoverPath()
        if #path >= 3 then
            self.State.Path = path
            self.State.PathQuality = quality
            for _, copy in ipairs(self.State.RecommendedTeam or {}) do
                copy.SweetSpots = sweetSpots(copy, path, self.State.Context)
            end
        end
        self.State.ActionPlan = buildActionPlan(self.State)
        return self.State, nil
    end

    function Brain:Destroy()
        self.Destroyed = true
        self.State = nil
        self.Cache = {}
    end

    return Brain
end
