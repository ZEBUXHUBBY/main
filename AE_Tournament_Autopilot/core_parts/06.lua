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
        return tonumber(instance.Name:match("%d+"))
    end

    local function discoverPath()
        local roots = {}
        local map = Workspace:FindFirstChild("Map")
        if map then roots[#roots + 1] = map end
        roots[#roots + 1] = Workspace

        local namedContainers = {"Path", "Waypoints", "Nodes", "EnemyWaypoints", "Route", "Paths"}
        local bestCandidates = {}

        for _, root in ipairs(roots) do
            for _, containerName in ipairs(namedContainers) do
                local container = root:FindFirstChild(containerName, true)
                if container then
                    local points = {}
                    for _, descendant in ipairs(container:GetDescendants()) do
                        local position = worldPosition(descendant)
                        if position then
                            points[#points + 1] = {
                                Position = position,
                                Order = numericOrder(descendant),
                                Name = descendant.Name,
                                Instance = descendant,
                            }
                        end
                    end
                    if #points >= 3 then bestCandidates[#bestCandidates + 1] = points end
                end
            end
        end

        local points = nil
        for _, candidate in ipairs(bestCandidates) do
            if not points or #candidate > #points then points = candidate end
        end
        if not points then return {}, "ordered route not found" end

        local orderedCount = 0
        for _, point in ipairs(points) do if point.Order then orderedCount = orderedCount + 1 end end
        if orderedCount >= math.max(3, math.floor(#points * 0.6)) then
            table.sort(points, function(a, b)
                if a.Order and b.Order and a.Order ~= b.Order then return a.Order < b.Order end
                if a.Order and not b.Order then return true end
                if b.Order and not a.Order then return false end
                return tostring(a.Name) < tostring(b.Name)
            end)
        else
            -- Nearest-neighbour fallback. It is marked approximate in the UI.
            local remaining = arrayCopy(points)
            table.sort(remaining, function(a, b) return a.Position.X < b.Position.X end)
            local chain = {table.remove(remaining, 1)}
            while #remaining > 0 do
                local last = chain[#chain]
                local bestIndex, bestDistance = 1, math.huge
                for index, candidate in ipairs(remaining) do
                    local distance = (candidate.Position - last.Position).Magnitude
                    if distance < bestDistance then
                        bestDistance = distance
