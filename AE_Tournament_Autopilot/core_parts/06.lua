        for tag in pairs(nextUpgrade.Tags or {}) do if not (previous.Tags or {})[tag] then unlocks = unlocks + 0.5 end end
        if norm(previous.HitboxType) ~= norm(nextUpgrade.HitboxType) then unlocks = unlocks + 1.5 end

        local value = dpsGain
        value = value + rangeGain * (context.Speedy and 30 or 16)
        value = value + hitboxGain * 8
        value = value + unlocks * (context.BossWaves and 220 or 160)
        if context.HardMode then value = value * 1.08 end
        if context.BossWaves then value = value + dpsGain * 0.22 end

        return {
            From = previous.Level,
            To = nextUpgrade.Level,
            Cost = cost,
            DPSGain = dpsGain,
            RangeGain = rangeGain,
            HitboxGain = hitboxGain,
            UnlockScore = unlocks,
            Value = value,
            ValuePerYen = value / cost,
            Spike = unlocks >= 1 or rangeGain >= 2 or hitboxGain >= 3,
        }
    end

    local function planUpgrade(copy, context)
        local steps = {}
        local bestValuePerYen = 0
        for index = 2, #(copy.Upgrades or {}) do
            local step = upgradeStepValue(copy, copy.Upgrades[index - 1], copy.Upgrades[index], context)
            steps[#steps + 1] = step
            bestValuePerYen = math.max(bestValuePerYen, step.ValuePerYen)
        end

        local target = copy.Base and copy.Base.Level or 0
        local stopReason = "base only"
        local threshold = bestValuePerYen * (context.BossWaves and 0.24 or 0.32)
        for _, step in ipairs(steps) do
            if step.Spike or step.ValuePerYen >= threshold then
                target = step.To
                stopReason = step.Spike and "includes the last major unlock/range spike" or "keeps efficient Tournament value per Yen"
            end
        end

        if context.BossWaves and copy.CapDPS > 0 then
            local finalLevel = copy.Final and copy.Final.Level or target
            if target < finalLevel and (copy.BossBonus or copy.CapDPS > 0) then
                target = math.max(target, math.floor(finalLevel * 0.75))
                stopReason = "Boss Waves favor sustained high-upgrade damage"
            end
        end

        local nextStep = steps[1]
        return {
            TargetLevel = target,
            NextStep = nextStep,
            Steps = steps,
            StopReason = stopReason,
        }
    end

    -- -------------------------------------------------------------------------
    -- Farm decision
    -- -------------------------------------------------------------------------

    local function weakestCombat(team)
        local weakest = nil
        for _, copy in ipairs(team or {}) do
            if not weakest or (copy.TournamentScore or 0) < (weakest.TournamentScore or 0) then weakest = copy end
        end
        return weakest
    end

    local function evaluateFarm(copies, combatTeam, context)
        local farmCopies = {}
        for _, copy in pairs(copies or {}) do
            if copy.Farm and copy.FarmIncomeKnown then farmCopies[#farmCopies + 1] = copy end
        end

        if #farmCopies == 0 then
            return {
                Decision = "UNKNOWN",
                Reason = "No owned Farm copy with exact Income fields was resolved.",
                Exact = false,
            }
        end

        local pressure = 0
        if context.HardMode then pressure = pressure + 1 end
        if context.BossWaves then pressure = pressure + 2 end
        if context.Speedy then pressure = pressure + 2 end
        local paybackLimit = pressure >= 4 and 2.8 or (pressure >= 2 and 4.0 or 5.5)
        local horizon = context.WaveCount or 20
        local weakest = weakestCombat(combatTeam)
        local weakestDPS = weakest and weakest.CapDPS or 0

        local best = nil
        for _, copy in ipairs(farmCopies) do
            for _, upgrade in ipairs(copy.Upgrades or {}) do
                if tonumber(upgrade.Income) and upgrade.Income > 0 then
                    local cap = math.max(1, copy.PlacementLimit or 1)
                    local incomePerWave = upgrade.Income * cap
                    local cost = upgrade.CumulativeCost * cap
                    local payback = cost / math.max(1, incomePerWave)
                    local gross = incomePerWave * math.max(0, horizon - payback)
                    local pressurePenalty = weakestDPS * (pressure >= 4 and 1.0 or 0.45)
                    local score = gross - cost - pressurePenalty
                    local candidate = {
                        Copy = copy,
                        Upgrade = upgrade,
                        TargetLevel = upgrade.Level,
                        IncomePerWave = incomePerWave,
                        Cost = cost,
                        PaybackWaves = payback,
                        HorizonWaves = horizon,
                        CombatDPSLost = weakestDPS,
                        Replace = weakest,
                        Score = score,
                        Exact = true,
                    }
                    if not best or candidate.Score > best.Score then best = candidate end
                end
            end
        end

        if not best then
            return {
                Decision = "UNKNOWN",
                Reason = "Farm unit exists, but no exact per-wave Income upgrade was found.",
                Exact = false,
            }
        end

        if best.PaybackWaves <= paybackLimit and best.Score > 0 then
            best.Decision = "USE"
            best.Reason = "Farm pays back before the current pressure limit. Stop at U" .. tostring(best.TargetLevel) .. "."
        elseif best.PaybackWaves <= paybackLimit + 1.5 and pressure < 4 then
            best.Decision = "OPTIONAL"
            best.Reason = "Farm can work if the opener survives the early pressure window."
        else
            best.Decision = "SKIP"
            best.Reason = "Payback is too slow for the current Boss/Speed/Hard pressure."
        end
        return best
    end

    -- -------------------------------------------------------------------------
    -- Geometry / Sweet Spots
    -- -------------------------------------------------------------------------

    local function worldPosition(instance)
        if not instance then return nil end
        if instance:IsA("Attachment") then return instance.WorldPosition end
        if instance:IsA("BasePart") then return instance.Position end
        if instance:IsA("Vector3Value") then return instance.Value end
        if instance:IsA("CFrameValue") then return instance.Value.Position end
        return nil
    end

    local function numericOrder(instance)
        if not instance then return nil end
        local exact = tonumber(instance.Name)
        if exact then return exact end
        local lower = instance.Name:lower()
        if lower:find("waypoint",1,true) or lower:find("node",1,true) or lower:find("point",1,true) or lower:find("path",1,true) then
            return tonumber(instance.Name:match("%d+"))
        end
        return nil
    end

    local function discoverPath()
        -- Do not draw a guessed route. Only an explicitly ordered route is safe
        -- enough to drive placement/sell decisions.
        local map = Workspace:FindFirstChild("Map")
        if not map then return {}, "MAP_NOT_FOUND" end

        local containers = {}
        local direct = map:FindFirstChild("Path")
        if direct then containers[#containers + 1] = direct end
        for _, name in ipairs({"Waypoints","EnemyWaypoints","Route","Nodes"}) do
            local object = map:FindFirstChild(name, true)
            if object and object ~= direct then containers[#containers + 1] = object end
        end

        local best, bestOrdered = nil, 0
        for _, container in ipairs(containers) do
            local points = {}
            for _, descendant in ipairs(container:GetDescendants()) do
                local order = numericOrder(descendant)
                local position = order and worldPosition(descendant) or nil
                if order and position then
                    points[#points + 1] = {Position=position,Order=order,Name=descendant.Name,Instance=descendant}
                end
            end
            if #points >= 3 then
                table.sort(points,function(a,b) return a.Order < b.Order end)
                -- reject duplicate order values; they usually mean decorative
                -- children rather than one canonical route.
                local unique, clean = {}, {}
                for _, point in ipairs(points) do
                    if not unique[point.Order] then unique[point.Order]=true;clean[#clean+1]=point end
                end
                if #clean >= 3 and #clean > bestOrdered then best=clean;bestOrdered=#clean end
            end
        end

        if not best then return {}, "ROUTE_UNRESOLVED_NO_ORDERED_WAYPOINTS" end
        local deduped={}
        for _,point in ipairs(best) do
            if #deduped==0 or (point.Position-deduped[#deduped].Position).Magnitude>0.25 then deduped[#deduped+1]=point end
        end
        if #deduped<3 then return {}, "ROUTE_UNRESOLVED_TOO_FEW_POINTS" end
        return deduped,"ORDERED_STRICT"
    end

    local function pathDistance(points)
        local distance = 0
        for index = 2, #points do distance = distance + (points[index].Position - points[index - 1].Position).Magnitude end
        return distance
    end

    local function coverageFor(position, range, points)
        local covered, total = 0, 0
        local firstProgress, lastProgress = nil, nil
        local progress = 0
        for index = 2, #points do
            local a = points[index - 1].Position
            local b = points[index].Position
            local segmentLength = (b - a).Magnitude
            local midpoint = (a + b) * 0.5
            total = total + segmentLength
            if (Vector3.new(midpoint.X, position.Y, midpoint.Z) - position).Magnitude <= range then
                covered = covered + segmentLength
                if not firstProgress then firstProgress = progress end
                lastProgress = progress + segmentLength
            end
            progress = progress + segmentLength
        end
        return covered, total, firstProgress or 0, lastProgress or 0
    end

    local function groundAt(position)
        local origin = position + Vector3.new(0, 120, 0)
        local direction = Vector3.new(0, -300, 0)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {LocalPlayer.Character}
        local result = Workspace:Raycast(origin, direction, params)
        return result and result.Position or position
    end

    local function sweetSpots(copy, points, context)
        if not copy or not copy.Final or #points < 3 then return {} end
        local range = math.max(4, copy.Final.Range or 0)
        local candidates = {}
        local totalLength = pathDistance(points)
        local progress = 0

        for index = 2, #points - 1 do
            local previous = points[index - 1].Position
            local current = points[index].Position
            local nextPoint = points[index + 1].Position
            local direction = (nextPoint - previous)
            if direction.Magnitude > 0.1 then direction = direction.Unit else direction = Vector3.new(1, 0, 0) end
            local perpendicular = Vector3.new(-direction.Z, 0, direction.X)
            local segmentLength = (current - previous).Magnitude
            progress = progress + segmentLength

            local offsetDistance = clamp(range * 0.45, 6, 18)
            for _, side in ipairs({-1, 1}) do
                local raw = current + perpendicular * offsetDistance * side
                local position = groundAt(raw)
                local covered, total, first, last = coverageFor(position, range, points)
                local v1 = (current - previous).Unit
                local v2 = (nextPoint - current).Unit
                local turn = 1 - clamp(v1:Dot(v2), -1, 1)
                local speedFactor = context.Speedy and (1 + (context.SpeedPercent or 50) / 100) or 1
                local exposure = covered / speedFactor
                local score = exposure + turn * range * 0.7
                if context.BossWaves then score = score + exposure * 0.25 end
                candidates[#candidates + 1] = {
                    WorldPosition = position,
                    PathCoverage = covered,
                    TotalPath = total,
                    CoveragePercent = total > 0 and covered / total or 0,
                    FirstCoverage = first,
                    LastCoverage = last,
                    Progress = totalLength > 0 and progress / totalLength or 0,
                    Score = score,
                    Range = range,
                    Side = side,
                }
            end
        end

        table.sort(candidates, function(a, b) return a.Score > b.Score end)
        local selected = {}
        for _, candidate in ipairs(candidates) do
            local separated = true
            for _, existing in ipairs(selected) do
                if (candidate.WorldPosition - existing.WorldPosition).Magnitude < math.max(8, range * 0.45) then
                    separated = false
                    break
                end
            end
            if separated then
                selected[#selected + 1] = candidate
                if #selected >= 3 then break end
            end
        end

        table.sort(selected, function(a, b) return a.Progress < b.Progress end)
        local labels = {"A", "B", "C"}
        for index, spot in ipairs(selected) do
            spot.Label = labels[index] or tostring(index)
            spot.Purpose = index == 1 and "OPENER" or (index == #selected and "CATCH / REPOSITION" or "SUSTAINED")
        end
        return selected
    end

    -- -------------------------------------------------------------------------
    -- Live snapshot and action planner
    -- -------------------------------------------------------------------------

    local function scanCurrentYen()
        for _, name in ipairs({"Yen", "CurrentYen", "Money", "Cash"}) do
            local value = LocalPlayer:GetAttribute(name)
            if tonumber(value) then return tonumber(value), "PlayerAttribute." .. name end
        end

        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if playerGui then
            for _, descendant in ipairs(playerGui:GetDescendants()) do
                if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
                    local contextName = norm(descendant.Name .. " " .. (descendant.Parent and descendant.Parent.Name or ""))
                    if contextName:find("yen", 1, true) or contextName:find("money", 1, true) or contextName:find("cash", 1, true) then
                        local cleaned = tostring(descendant.Text):gsub("[,¥$%s]", "")
                        local value = tonumber(cleaned:match("%d+%.?%d*"))
                        if value then return value, descendant:GetFullName() end
                    end
                end
            end
        end
        return nil, "unresolved"
    end

    local function buildActionPlan(state)
        local team = state.RecommendedTeam or {}
        local selected = team[state.SelectedUnit or 1]
        local farm = state.FarmPlan
        local yen, yenSource = scanCurrentYen()
        state.Live = {Yen = yen, YenSource = yenSource}

        if not selected then
            return {
                Next = {Type = "SCAN", Title = "No team available", Why = {"Owned inventory could not be resolved."}},
                Queue = {},
            }
        end

        local opener = team[1]
        for _, copy in ipairs(team) do
            if (copy.OpenerEfficiency or 0) > (opener.OpenerEfficiency or 0) then opener = copy end
        end

        local nextAction = {
            Type = "PLACE",
            Unit = opener,
            Title = "Place " .. tostring(opener.DisplayName),
            Subtitle = opener.SweetSpots and opener.SweetSpots[1] and ("Sweet Spot " .. tostring(opener.SweetSpots[1].Label)) or "route unresolved — placement pending",
            Cost = opener.Base and opener.Base.CumulativeCost or nil,
            Target = opener.Targeting and opener.Targeting.Primary or "First",
            Why = {
                "Highest opener value among the recommended six.",
                "Start with target