                        bestIndex = index
                    end
                end
                chain[#chain + 1] = table.remove(remaining, bestIndex)
            end
            points = chain
        end

        local deduped = {}
        for _, point in ipairs(points) do
            if #deduped == 0 or (point.Position - deduped[#deduped].Position).Magnitude > 0.25 then
                deduped[#deduped + 1] = point
            end
        end
        return deduped, orderedCount >= math.max(3, math.floor(#points * 0.6)) and "ORDERED" or "APPROXIMATE"
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
            Subtitle = opener.SweetSpots and opener.SweetSpots[1] and ("Sweet Spot " .. tostring(opener.SweetSpots[1].Label)) or "best route coverage",
            Cost = opener.Base and opener.Base.CumulativeCost or nil,
            Target = opener.Targeting and opener.Targeting.Primary or "First",
            Why = {
                "Highest opener value among the recommended six.",
                "Start with target priority: " .. tostring(opener.Targeting and opener.Targeting.Primary or "First") .. ".",
            },
        }

        local queue = {}
        queue[#queue + 1] = nextAction

        if opener.UpgradePlan and opener.UpgradePlan.NextStep then
            queue[#queue + 1] = {
                Type = "UPGRADE",
                Unit = opener,
                Title = "Upgrade " .. tostring(opener.DisplayName) .. " to U" .. tostring(opener.UpgradePlan.NextStep.To),
                Cost = opener.UpgradePlan.NextStep.Cost,
                Why = {"Best first marginal upgrade for the opener."},
            }
        end

        if farm and farm.Decision == "USE" then
            queue[#queue + 1] = {
                Type = "FARM",
                Unit = farm.Copy,
                Title = "Add Farm at U" .. tostring(farm.TargetLevel),
                Cost = farm.Cost,
                Why = {"Exact payback " .. string.format("%.1f", farm.PaybackWaves) .. " waves.", farm.Reason},
            }
        elseif farm and farm.Decision == "SKIP" then
            queue[#queue + 1] = {
                Type = "SAVE",
                Title = "Skip Farm; reserve for combat",
                Why = {farm.Reason},
            }
        end

        if #team >= 2 then
            local second = team[2]
            queue[#queue + 1] = {
                Type = "PLACE",
                Unit = second,
                Title = "Place " .. tostring(second.DisplayName),
                Subtitle = second.SweetSpots and second.SweetSpots[2] and ("Sweet Spot " .. tostring(second.SweetSpots[2].Label)) or "sustained position",
                Target = second.Targeting and second.Targeting.Primary or "Strongest",
                Why = {"Second-highest Tournament combat fit."},
            }
        end
