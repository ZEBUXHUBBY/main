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

-- Readability pass ------------------------------------------------------------
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

-- Portrait resolver: score actual character models instead of taking the first
-- nested model, which is frequently an Aura/VFX/Hitbox model.
local oldFind = [[    local function findUnitModel(asset)
        if not UnitModels then return nil end
        local folder = UnitModels:FindFirstChild(asset)
        if not folder then return nil end
        if folder:IsA("Model") then return folder end
        for _, name in ipairs({"Model", "Shiny", "Default", "Unit"}) do
            local model = folder:FindFirstChild(name)
            if model and model:IsA("Model") then return model end
        end
        return folder:FindFirstChildWhichIsA("Model", true)
    end]]
local newFind = [[    local function findUnitModel(asset)
        if not UnitModels then return nil end
        local folder = UnitModels:FindFirstChild(asset)
        if not folder then return nil end
        local candidates = {}
        if folder:IsA("Model") then candidates[#candidates+1] = folder end
        for _, object in ipairs(folder:GetDescendants()) do
            if object:IsA("Model") then candidates[#candidates+1] = object end
        end
        local best, bestScore = nil, -math.huge
        for _, model in ipairs(candidates) do
            local lower = model.Name:lower()
            local score = 0
            if lower == "model" or lower == "default" or lower == "unit" or lower == "character" then score = score + 45 end
            if lower:find("shiny",1,true) then score = score + 8 end
            if lower:find("vfx",1,true) or lower:find("effect",1,true) or lower:find("aura",1,true) or lower:find("hitbox",1,true) or lower:find("range",1,true) or lower:find("projectile",1,true) then score = score - 140 end
            if model:FindFirstChildWhichIsA("Humanoid", true) then score = score + 120 end
            if model:FindFirstChildWhichIsA("AnimationController", true) then score = score + 70 end
            if model:FindFirstChild("Head", true) then score = score + 50 end
            if model.PrimaryPart then score = score + 20 end
            local parts = 0
            for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then parts = parts + 1 end end
            score = score + math.min(parts, 30) * 3
            if parts < 2 then score = score - 80 end
            if score > bestScore then bestScore = score; best = model end
        end
        if bestScore < 20 then return nil end
        return best
    end]]
local fs,fe = string.find(joined,oldFind,1,true)
if fs then joined = string.sub(joined,1,fs-1)..newFind..string.sub(joined,fe+1) end

-- Strip visual effects from cloned character models before rendering portrait.
local cloneNeedle = [[        local ok, model = pcall(function() return source:Clone() end)
        if not ok or not model then return false end

        local viewportFrame = Instance.new("ViewportFrame")]]
local cloneReplacement = [[        local ok, model = pcall(function() return source:Clone() end)
        if not ok or not model then return false end
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("Smoke") or d:IsA("Fire") or d:IsA("Sparkles") or d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") or d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
                d:Destroy()
            elseif d:IsA("BasePart") then
                local n = d.Name:lower()
                if n:find("hitbox",1,true) or n:find("range",1,true) or n:find("aura",1,true) then d.Transparency = 1 end
            end
        end

        local viewportFrame = Instance.new("ViewportFrame")]]
local cs,ce=string.find(joined,cloneNeedle,1,true)
if cs then joined=string.sub(joined,1,cs-1)..cloneReplacement..string.sub(joined,ce+1) end

-- Never use the old hotbar/aura fallback as a unit portrait. A clean initial is
-- preferable to a false image until an exact external portrait is resolved.
local oldAdd = [[    local function addUnitVisual(parent, copy, slotIndex)
        -- Prefer the game's actual unit model. The old resolver often grabbed aura,
        -- element or card-decoration ImageLabels from the hotbar instead of the face.
        if modelVisual(copy.Asset, parent) then return "GAME MODEL" end
        local source = UI.Resolver.ByAsset[copy.Asset] or UI.Resolver.BySlot[slotIndex]
        if cloneVisual(source, parent) then return "GAME UI FALLBACK" end
        label(parent, tostring(copy.DisplayName):sub(1, 1):upper(), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), {
            Bold = true, TextSize = 28, Align = Enum.TextXAlignment.Center,
        })
        return "TEXT"
    end]]
local newAdd = [[    local function addUnitVisual(parent, copy, slotIndex)
        if modelVisual(copy.Asset, parent) then return "GAME MODEL" end
        label(parent, tostring(copy.DisplayName):sub(1, 1):upper(), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), {
            Bold = true, TextSize = 28, Align = Enum.TextXAlignment.Center,
        })
        return "TEXT"
    end]]
local as,ae=string.find(joined,oldAdd,1,true)
if as then joined=string.sub(joined,1,as-1)..newAdd..string.sub(joined,ae+1) end

-- True world-range rendering. toCanvas scales X and Z independently, therefore a
-- world-space circle must become an ellipse on screen when the map aspect differs.
local oldRange = [[            local point = toCanvas(spot.WorldPosition, bounds, size)
            local worldWidth = math.max(bounds.MaxX - bounds.MinX, bounds.MaxZ - bounds.MinZ)
            local diameter = clamp((spot.Range / math.max(1, worldWidth)) * math.min(size.X, size.Y) * 2, 48, 180)

            local rangeCircle = Instance.new("Frame")
            rangeCircle.AnchorPoint = Vector2.new(0.5, 0.5)
            rangeCircle.Position = UDim2.fromOffset(point.X, point.Y)
            rangeCircle.Size = UDim2.fromOffset(diameter, diameter)]]
local newRange = [[            local point = toCanvas(spot.WorldPosition, bounds, size)
            local worldSpanX = math.max(1, bounds.MaxX - bounds.MinX)
            local worldSpanZ = math.max(1, bounds.MaxZ - bounds.MinZ)
            local pixelsPerStudX = math.max(1, size.X - 48) / worldSpanX
            local pixelsPerStudZ = math.max(1, size.Y - 48) / worldSpanZ
            local diameterX = math.max(12, spot.Range * pixelsPerStudX * 2)
            local diameterY = math.max(12, spot.Range * pixelsPerStudZ * 2)

            local rangeCircle = Instance.new("Frame")
            rangeCircle.AnchorPoint = Vector2.new(0.5, 0.5)
            rangeCircle.Position = UDim2.fromOffset(point.X, point.Y)
            rangeCircle.Size = UDim2.fromOffset(diameterX, diameterY)]]
local rs,re=string.find(joined,oldRange,1,true)
if rs then joined=string.sub(joined,1,rs-1)..newRange..string.sub(joined,re+1) end
joined = joined:gsub('rounded%(rangeCircle, diameter / 2%)','rounded(rangeCircle, math.max(diameterX, diameterY) / 2)')

-- Make the range value explicit next to each sweet spot for validation.
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
