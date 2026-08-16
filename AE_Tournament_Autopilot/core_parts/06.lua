        for tag in pairs(nextUpgrade.Tags or {}) do if not (previous.Tags or {})[tag] then unlocks = unlocks + 0.5 end end
        if norm(previous.HitboxType) ~= norm(nextUpgrade.HitboxType) then unlocks = unlocks + 1.5 end

        local value = dpsGain
        value = value + rangeGain * (context.Speedy and 30 or 16)
        value = value + hitboxGain * 8
        value = value + unlocks * (context.BossWaves and 220 or 160)
        if context.HardMode then value = value * 1.08 end
        if context.BossWaves then value = value + dpsGain * 0.22 end

        return {From=previous.Level,To=nextUpgrade.Level,Cost=cost,DPSGain=dpsGain,RangeGain=rangeGain,HitboxGain=hitboxGain,UnlockScore=unlocks,Value=value,ValuePerYen=value/cost,Spike=unlocks>=1 or rangeGain>=2 or hitboxGain>=3}
    end

    local function planUpgrade(copy, context)
        local steps,bestValuePerYen={},0
        for index=2,#(copy.Upgrades or {}) do local step=upgradeStepValue(copy,copy.Upgrades[index-1],copy.Upgrades[index],context);steps[#steps+1]=step;bestValuePerYen=math.max(bestValuePerYen,step.ValuePerYen) end
        local target=copy.Base and copy.Base.Level or 0;local stopReason="base only";local threshold=bestValuePerYen*(context.BossWaves and 0.24 or 0.32)
        for _,step in ipairs(steps) do if step.Spike or step.ValuePerYen>=threshold then target=step.To;stopReason=step.Spike and "includes the last major unlock/range spike" or "keeps efficient Tournament value per Yen" end end
        if context.BossWaves and copy.CapDPS>0 then local finalLevel=copy.Final and copy.Final.Level or target;if target<finalLevel and (copy.BossBonus or copy.CapDPS>0) then target=math.max(target,math.floor(finalLevel*0.75));stopReason="Boss Waves favor sustained high-upgrade damage" end end
        return {TargetLevel=target,NextStep=steps[1],Steps=steps,StopReason=stopReason}
    end

    local function weakestCombat(team)local weakest=nil;for _,copy in ipairs(team or {}) do if not weakest or (copy.TournamentScore or 0)<(weakest.TournamentScore or 0) then weakest=copy end end;return weakest end
    local function evaluateFarm(copies,combatTeam,context)
        local farmCopies={};for _,copy in pairs(copies or {}) do if copy.Farm and copy.FarmIncomeKnown then farmCopies[#farmCopies+1]=copy end end
        if #farmCopies==0 then return {Decision="UNKNOWN",Reason="No owned Farm copy with exact Income fields was resolved.",Exact=false} end
        local pressure=0;if context.HardMode then pressure+=1 end;if context.BossWaves then pressure+=2 end;if context.Speedy then pressure+=2 end
        local paybackLimit=pressure>=4 and 2.8 or (pressure>=2 and 4.0 or 5.5);local horizon=context.WaveCount or 20;local weakest=weakestCombat(combatTeam);local weakestDPS=weakest and weakest.CapDPS or 0;local best=nil
        for _,copy in ipairs(farmCopies) do for _,upgrade in ipairs(copy.Upgrades or {}) do if tonumber(upgrade.Income) and upgrade.Income>0 then local cap=math.max(1,copy.PlacementLimit or 1);local incomePerWave=upgrade.Income*cap;local cost=upgrade.CumulativeCost*cap;local payback=cost/math.max(1,incomePerWave);local gross=incomePerWave*math.max(0,horizon-payback);local pressurePenalty=weakestDPS*(pressure>=4 and 1.0 or 0.45);local score=gross-cost-pressurePenalty;local candidate={Copy=copy,Upgrade=upgrade,TargetLevel=upgrade.Level,IncomePerWave=incomePerWave,Cost=cost,PaybackWaves=payback,HorizonWaves=horizon,CombatDPSLost=weakestDPS,Replace=weakest,Score=score,Exact=true};if not best or candidate.Score>best.Score then best=candidate end end end end
        if not best then return {Decision="UNKNOWN",Reason="Farm unit exists, but no exact per-wave Income upgrade was found.",Exact=false} end
        if best.PaybackWaves<=paybackLimit and best.Score>0 then best.Decision="USE";best.Reason="Farm pays back before the current pressure limit. Stop at U"..tostring(best.TargetLevel).."." elseif best.PaybackWaves<=paybackLimit+1.5 and pressure<4 then best.Decision="OPTIONAL";best.Reason="Farm can work if the opener survives the early pressure window." else best.Decision="SKIP";best.Reason="Payback is too slow for the current Boss/Speed/Hard pressure." end;return best
    end

    -- Geometry: probe evidence confirms Workspace.Map.Paths is the canonical
    -- enemy route. It contains exactly 43 ordered Parts named 1..43, and live
    -- enemies report WaypointIndex=43 near the route end. Do not use PathModel.
    local function worldPosition(instance)
        if not instance then return nil end
        if instance:IsA("Attachment") then return instance.WorldPosition end
        if instance:IsA("BasePart") then return instance.Position end
        if instance:IsA("Vector3Value") then return instance.Value end
        if instance:IsA("CFrameValue") then return instance.Value.Position end
        return nil
    end

    local function discoverPath()
        local map=Workspace:FindFirstChild("Map");if not map then return {},"MAP_NOT_FOUND" end
        local container=map:FindFirstChild("Paths")
        if not container then return {},"MAP_PATHS_NOT_FOUND" end
        local indexed={};local maxOrder=0
        for _,child in ipairs(container:GetChildren()) do
            local order=tonumber(child.Name);local position=order and worldPosition(child) or nil
            if order and position then indexed[order]={Position=position,Order=order,Name=child.Name,Instance=child};maxOrder=math.max(maxOrder,order) end
        end
        if maxOrder<3 then return {},"MAP_PATHS_NO_ORDER" end
        local points={}
        for order=1,maxOrder do if not indexed[order] then return {},"MAP_PATHS_GAP_"..tostring(order) end;points[#points+1]=indexed[order] end
        return points,"VERIFIED_MAP_PATHS_"..tostring(#points)
    end

    local function pathDistance(points)local distance=0;for index=2,#points do distance+=(points[index].Position-points[index-1].Position).Magnitude end;return distance end
    local function coverageFor(position,range,points)
        local covered,total=0,0;local firstProgress,lastProgress=nil,nil;local progress=0
        for index=2,#points do local a=points[index-1].Position;local b=points[index].Position;local segmentLength=(b-a).Magnitude;local midpoint=(a+b)*0.5;total+=segmentLength;if (Vector3.new(midpoint.X,position.Y,midpoint.Z)-position).Magnitude<=range then covered+=segmentLength;if not firstProgress then firstProgress=progress end;lastProgress=progress+segmentLength end;progress+=segmentLength end
        return covered,total,firstProgress or 0,lastProgress or 0
    end
    local function groundAt(position)local origin=position+Vector3.new(0,120,0);local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={LocalPlayer.Character};local result=Workspace:Raycast(origin,Vector3.new(0,-300,0),params);return result and result.Position or position end
    local function sweetSpots(copy,points,context)
        if not copy or not copy.Final or #points<3 then return {} end
        local range=math.max(4,copy.Final.Range or 0);local candidates={};local totalLength=pathDistance(points);local progress=0
        for index=2,#points-1 do
            local previous,current,nextPoint=points[index-1].Position,points[index].Position,points[index+1].Position;local direction=nextPoint-previous;if direction.Magnitude>0.1 then direction=direction.Unit else direction=Vector3.new(1,0,0) end;local perpendicular=Vector3.new(-direction.Z,0,direction.X);local segmentLength=(current-previous).Magnitude;progress+=segmentLength;local offsetDistance=clamp(range*0.45,6,18)
            for _,side in ipairs({-1,1}) do local raw=current+perpendicular*offsetDistance*side;local position=groundAt(raw);local covered,total,first,last=coverageFor(position,range,points);local d1=current-previous;local d2=nextPoint-current;local turn=0;if d1.Magnitude>0.1 and d2.Magnitude>0.1 then turn=1-clamp(d1.Unit:Dot(d2.Unit),-1,1) end;local speedFactor=context.Speedy and (1+(context.SpeedPercent or 50)/100) or 1;local exposure=covered/speedFactor;local score=exposure+turn*range*0.7;if context.BossWaves then score+=exposure*0.25 end;candidates[#candidates+1]={WorldPosition=position,PathCoverage=covered,TotalPath=total,CoveragePercent=total>0 and covered/total or 0,FirstCoverage=first,LastCoverage=last,Progress=totalLength>0 and progress/totalLength or 0,Score=score,Range=range,Side=side} end
        end
        table.sort(candidates,function(a,b)return a.Score>b.Score end);local selected={};for _,candidate in ipairs(candidates) do local separated=true;for _,existing in ipairs(selected) do if (candidate.WorldPosition-existing.WorldPosition).Magnitude<math.max(8,range*0.45) then separated=false;break end end;if separated then selected[#selected+1]=candidate;if #selected>=3 then break end end end
        table.sort(selected,function(a,b)return a.Progress<b.Progress end);local labels={"A","B","C"};for index,spot in ipairs(selected) do spot.Label=labels[index] or tostring(index);spot.Purpose=index==1 and "OPENER" or (index==#selected and "CATCH / REPOSITION" or "SUSTAINED") end;return selected
    end

    local function scanCurrentYen()
        for _,name in ipairs({"Yen","CurrentYen","Money","Cash"}) do local value=LocalPlayer:GetAttribute(name);if tonumber(value) then return tonumber(value),"PlayerAttribute."..name end end
        local live=Brain.LiveReplicaCache;if live and live.PlayerGame and tonumber(live.PlayerGame.Yen) then return tonumber(live.PlayerGame.Yen),"Replica.Yen" end
        local playerGui=LocalPlayer:FindFirstChild("PlayerGui");if playerGui then for _,descendant in ipairs(playerGui:GetDescendants()) do if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then local contextName=norm(descendant.Name.." "..(descendant.Parent and descendant.Parent.Name or ""));if contextName:find("yen",1,true) or contextName:find("money",1,true) or contextName:find("cash",1,true) then local cleaned=tostring(descendant.Text):gsub("[,¥$%s]","");local value=tonumber(cleaned:match("%d+%.?%d*"));if value then return value,descendant:GetFullName() end end end end end
        return nil,"unresolved"
    end

    local function buildActionPlan(state)
        local team=state.RecommendedTeam or {};local selected=team[state.SelectedUnit or 1];local farm=state.FarmPlan;local yen,yenSource=scanCurrentYen();state.Live={Yen=yen,YenSource=yenSource}
        if not selected then return {Next={Type="SCAN",Title="No team available",Why={"Owned inventory could not be resolved."}},Queue={}} end
        local opener=team[1];for _,copy in ipairs(team) do if (copy.OpenerEfficiency or 0)>(opener.OpenerEfficiency or 0) then opener=copy end end
        local nextAction={Type="PLACE",Unit=opener,Title="Place "..tostring(opener.DisplayName),Subtitle=opener.SweetSpots and opener.SweetSpots[1] and ("Sweet Spot "..tostring(opener.SweetSpots[1].Label)) or "route unresolved — placement pending",Cost=opener.Base and opener.Base.CumulativeCost or nil,Target=opener.Targeting and opener.Targeting.Primary or "First",Why={"Highest opener value among the recommended six.","Start with target priority: "..tostring(opener.Targeting and opener.Targeting.Primary or "First").."."}}
        local queue={nextAction};if opener.UpgradePlan and opener.UpgradePlan.NextStep then queue[#queue+1]={Type="UPGRADE",Unit=opener,Title="Upgrade "..tostring(opener.DisplayName).." to U"..tostring(opener.UpgradePlan.NextStep.To),Cost=opener.UpgradePlan.NextStep.Cost} end
        for _,copy in ipairs(team) do if copy~=opener then queue[#queue+1]={Type="PLACE",Unit=copy,Title="Place "..tostring(copy.DisplayName),Target=copy.Targeting and copy.Targeting.Primary};if #queue>=4 then break end end end
        return {Next=nextAction,Queue=queue,Yen=yen}
    end
