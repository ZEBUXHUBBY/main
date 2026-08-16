local ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Tournament_Autopilot/ui_parts/"
local nonce = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
local parts = {"01.lua","02.lua","03.lua","04.lua","05.lua"}
local source = {}
for _, path in ipairs(parts) do
    local ok, body = pcall(function()
        return game:HttpGet(ROOT .. path .. "?ui=" .. nonce)
    end)
    if not ok then error("Tournament UI part fetch failed " .. path .. ": " .. tostring(body)) end
    source[#source + 1] = body
end
local joined = table.concat(source,"\n")

-- Readability -----------------------------------------------------------------
joined = joined:gsub('TextSize = 8, Truncate = Enum.TextTruncate.AtEnd', 'TextSize = 9, Truncate = Enum.TextTruncate.AtEnd')
joined = joined:gsub('Bold = true, TextSize = 10, Truncate = Enum.TextTruncate.AtEnd', 'Bold = true, TextSize = 11, Truncate = Enum.TextTruncate.AtEnd')
joined = joined:gsub('Bold = true, TextSize = 7, Align = Enum.TextXAlignment.Center', 'Bold = true, TextSize = 8, Align = Enum.TextXAlignment.Center')
joined = joined:gsub('Bold = true, TextSize = 8, Align = Enum.TextXAlignment.Right', 'Bold = true, TextSize = 9, Align = Enum.TextXAlignment.Right')
joined = joined:gsub('Color = COLORS.Muted, TextSize = 8, Align = Enum.TextXAlignment.Center', 'Color = COLORS.Muted, TextSize = 10, Align = Enum.TextXAlignment.Center')
joined = joined:gsub('Color = COLORS.Muted, TextSize = 10, Wrap = true, YAlign = Enum.TextYAlignment.Top', 'Color = COLORS.Muted, TextSize = 12, Wrap = true, YAlign = Enum.TextYAlignment.Top')
joined = joined:gsub('Bold = true, TextSize = 9, Truncate = Enum.TextTruncate.AtEnd', 'Bold = true, TextSize = 11, Truncate = Enum.TextTruncate.AtEnd')
joined = joined:gsub('Color = COLORS.Muted, TextSize = 8,', 'Color = COLORS.Muted, TextSize = 10,')
joined = joined:gsub('tostring%(copy%.Role or "DPS"%) %.%. "  •  " %.%. fmt%(copy%.CapDPS, 0%)', 'tostring(copy.Trait or "No Trait") .. "  •  " .. tostring(copy.Role or "DPS") .. "  •  " .. fmt(copy.CapDPS, 0)')
joined = joined:gsub('copy%.DisplayName %.%. "  •  target "', 'copy.DisplayName .. "  •  " .. tostring(copy.Trait or "No Trait") .. "  •  target "')
joined = joined:gsub('TeamSub%.Text = "Manual REFRESH only • no background scan"', 'TeamSub.Text = "Best owned copies • Trait shown may differ from current hotbar"')
joined = joined:gsub('TeamSub%.Text = "Tap a unit to inspect placement %+ target"', 'TeamSub.Text = "Best copy from whole inventory • tap to inspect"')

-- Portraits -------------------------------------------------------------------
-- SafeViewport listeners do not initialize clones created by our UI. Instead,
-- reuse viewport content the game has ALREADY rendered: WorldModel + fixed Camera.
-- This keeps the exact character setup/camera chosen by Anime Expeditions.
local oldAddStart = string.find(joined, "    local function findSafeViewportTemplate()\n", 1, true)
local oldAddEnd = oldAddStart and string.find(joined, "    -- Map drawing", oldAddStart, true) or nil
if oldAddStart and oldAddEnd then
local portraitReplacement = [[    local function viewportNearbyText(viewport)
        local words = {}
        local node = viewport
        for _ = 1, 5 do
            node = node and node.Parent
            if not node then break end
            for _, d in ipairs(node:GetDescendants()) do
                if (d:IsA("TextLabel") or d:IsA("TextButton")) then
                    local text = tostring(d.Text or "")
                    if text ~= "" and #text <= 80 then words[#words+1] = text end
                    if #words >= 18 then break end
                end
            end
            if #words >= 18 then break end
        end
        return norm(table.concat(words, " "))
    end

    local function renderedViewportScore(viewport, copy)
        local score = 0
        local wantedAsset = norm(copy.Asset)
        local wantedName = norm(copy.DisplayName)
        local nearby = viewportNearbyText(viewport)
        if #wantedAsset >= 3 and nearby:find(wantedAsset,1,true) then score += 220 end
        if #wantedName >= 3 and nearby:find(wantedName,1,true) then score += 260 end

        local ancestor = viewport.Parent
        for _ = 1, 4 do
            if not ancestor then break end
            local showed = ancestor:FindFirstChild("ShowedModel", true)
            if showed and showed:IsA("StringValue") then
                local showedNorm = norm(showed.Value)
                if showedNorm == wantedAsset then score += 420 end
                if showedNorm == wantedName then score += 420 end
                if showedNorm:find(wantedAsset,1,true) or wantedAsset:find(showedNorm,1,true) then score += 150 end
            end
            ancestor = ancestor.Parent
        end

        local world = viewport:FindFirstChildWhichIsA("WorldModel")
        if not world then return -math.huge end
        local models = 0
        for _, d in ipairs(world:GetDescendants()) do
            if d:IsA("Model") then
                models += 1
                local n = norm(d.Name)
                if n == wantedAsset then score += 500 end
                if n == wantedName then score += 500 end
                if #n >= 3 and (n:find(wantedAsset,1,true) or wantedAsset:find(n,1,true)) then score += 180 end
                if d:FindFirstChildWhichIsA("Humanoid", true) then score += 35 end
            end
        end
        if models > 0 then score += 15 end
        if viewport.CurrentCamera then score += 45 end
        if viewport.Visible then score += 5 end
        return score
    end

    local function findRenderedViewport(copy)
        local best, bestScore = nil, -math.huge
        for _, d in ipairs(PlayerGui:GetDescendants()) do
            if d:IsA("ViewportFrame") then
                local score = renderedViewportScore(d, copy)
                if score > bestScore then bestScore = score; best = d end
            end
        end
        if bestScore < 180 then return nil, bestScore end
        return best, bestScore
    end

    local function cloneRenderedViewport(copy, parent)
        local sourceViewport = findRenderedViewport(copy)
        if not sourceViewport then return false end
        local sourceWorld = sourceViewport:FindFirstChildWhichIsA("WorldModel")
        if not sourceWorld then return false end

        local viewport = Instance.new("ViewportFrame")
        viewport.Name = "GameRenderedPortrait"
        viewport.Size = UDim2.fromScale(1,1)
        viewport.Position = UDim2.fromScale(0,0)
        viewport.BackgroundTransparency = 1
        viewport.BorderSizePixel = 0
        viewport.Ambient = sourceViewport.Ambient
        viewport.LightColor = sourceViewport.LightColor
        viewport.LightDirection = sourceViewport.LightDirection
        viewport.ImageColor3 = sourceViewport.ImageColor3
        viewport.ImageTransparency = sourceViewport.ImageTransparency

        local okWorld, world = pcall(function() return sourceWorld:Clone() end)
        if not okWorld or not world then viewport:Destroy(); return false end
        world.Parent = viewport

        local sourceCamera = sourceViewport.CurrentCamera or sourceViewport:FindFirstChildWhichIsA("Camera", true)
        if sourceCamera then
            local okCamera, camera = pcall(function() return sourceCamera:Clone() end)
            if okCamera and camera then
                camera.Parent = viewport
                viewport.CurrentCamera = camera
            end
        end

        -- A rendered game viewport without a camera will remain blank; reject it.
        if not viewport.CurrentCamera then viewport:Destroy(); return false end
        viewport.Parent = parent
        return true
    end

    local function addUnitVisual(parent, copy, slotIndex)
        if cloneRenderedViewport(copy, parent) then return "CLONED GAME RENDER" end
        -- Keep our direct model renderer only as a second fallback.
        if modelVisual(copy.Asset, parent) then return "DIRECT GAME MODEL" end
        label(parent, tostring(copy.DisplayName):sub(1, 1):upper(), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), {
            Bold = true, TextSize = 28, Align = Enum.TextXAlignment.Center,
        })
        return "TEXT"
    end

]]
joined = string.sub(joined,1,oldAddStart-1) .. portraitReplacement .. string.sub(joined,oldAddEnd)
end

-- Uniform world projection -----------------------------------------------------
local oldCanvas = [[    local function toCanvas(position, bounds, size)
        local x = 24 + ((position.X - bounds.MinX) / (bounds.MaxX - bounds.MinX)) * math.max(1, size.X - 48)
        local y = 24 + ((position.Z - bounds.MinZ) / (bounds.MaxZ - bounds.MinZ)) * math.max(1, size.Y - 48)
        return Vector2.new(x, y)
    end]]
local newCanvas = [[    local function worldCanvasScale(bounds, size)
        local spanX = math.max(1, bounds.MaxX - bounds.MinX)
        local spanZ = math.max(1, bounds.MaxZ - bounds.MinZ)
        return math.min(math.max(1,size.X-48)/spanX, math.max(1,size.Y-48)/spanZ)
    end

    local function toCanvas(position, bounds, size)
        local spanX = math.max(1, bounds.MaxX - bounds.MinX)
        local spanZ = math.max(1, bounds.MaxZ - bounds.MinZ)
        local scale = worldCanvasScale(bounds,size)
        local usedX, usedY = spanX*scale, spanZ*scale
        local originX = (size.X-usedX)*0.5
        local originY = (size.Y-usedY)*0.5
        return Vector2.new(originX + (position.X-bounds.MinX)*scale, originY + (position.Z-bounds.MinZ)*scale)
    end]]
local ts,te=string.find(joined,oldCanvas,1,true)
if ts then joined=string.sub(joined,1,ts-1)..newCanvas..string.sub(joined,te+1) end

local oldRange = [[            local point = toCanvas(spot.WorldPosition, bounds, size)
            local worldWidth = math.max(bounds.MaxX - bounds.MinX, bounds.MaxZ - bounds.MinZ)
            local diameter = clamp((spot.Range / math.max(1, worldWidth)) * math.min(size.X, size.Y) * 2, 48, 180)

            local rangeCircle = Instance.new("Frame")
            rangeCircle.AnchorPoint = Vector2.new(0.5, 0.5)
            rangeCircle.Position = UDim2.fromOffset(point.X, point.Y)
            rangeCircle.Size = UDim2.fromOffset(diameter, diameter)]]
local newRange = [[            local point = toCanvas(spot.WorldPosition, bounds, size)
            local pixelsPerStud = worldCanvasScale(bounds,size)
            local diameter = math.max(12, (tonumber(spot.Range) or 0) * pixelsPerStud * 2)

            local rangeCircle = Instance.new("Frame")
            rangeCircle.AnchorPoint = Vector2.new(0.5, 0.5)
            rangeCircle.Position = UDim2.fromOffset(point.X, point.Y)
            rangeCircle.Size = UDim2.fromOffset(diameter, diameter)]]
local rs,re=string.find(joined,oldRange,1,true)
if rs then joined=string.sub(joined,1,rs-1)..newRange..string.sub(joined,re+1) end

local marker = [[            marker.AutoButtonColor = false

            label(MapSurface, spot.Purpose,]]
local markerReplace = [[            marker.AutoButtonColor = false
            label(MapSurface, "R " .. string.format("%.1f", tonumber(spot.Range) or 0), UDim2.fromOffset(point.X - 38, point.Y - 35), UDim2.fromOffset(76, 16), {
                Bold = true, TextSize = 8, Align = Enum.TextXAlignment.Center,
            }).TextColor3 = rangeCircle.BackgroundColor3

            label(MapSurface, spot.Purpose,]]
local ms,me=string.find(joined,marker,1,true)
if ms then joined=string.sub(joined,1,ms-1)..markerReplace..string.sub(joined,me+1) end

-- M2 fallback -----------------------------------------------------------------
local oldFailure = [[            if not state then
                StageText.Text = "Scan failed: " .. tostring(analysisError)
                return
            end]]
local newFailure = [[            if not state then
                local live = type(Brain.GetLiveReplicaCache) == "function" and Brain:GetLiveReplicaCache() or nil
                if type(live) == "table" then
                    local unitCount=0;for _ in pairs(type(live.Units)=="table" and live.Units or {}) do unitCount=unitCount+1 end
                    local profileCount=0;for _ in pairs(type(live.ProfileFields)=="table" and live.ProfileFields or {}) do profileCount=profileCount+1 end
                    StageText.Text=string.format("LIVE M2 • Wave %s • Yen %s • placed %d • observed owned %d",tostring(live.Game and live.Game.Wave or "?"),tostring(live.PlayerGame and live.PlayerGame.Yen or "?"),unitCount,profileCount)
                else
                    StageText.Text="Scan failed: "..tostring(analysisError)
                end
                return
            end]]
local s,e=string.find(joined,oldFailure,1,true)
if s then joined=string.sub(joined,1,s-1)..newFailure..string.sub(joined,e+1) end

local chunk, compileError = loadstring(joined)
if not chunk then error("Tournament UI compile error: " .. tostring(compileError)) end
return chunk()
