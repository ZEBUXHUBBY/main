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

-- Game-native portrait renderer ------------------------------------------------
-- Game UI evidence shows a shared renderer driven by:
--   Frame @SafeViewport=true
--     ViewportFrame
--     ShowedModel (StringValue)
-- We clone an existing game-owned template where possible and change ShowedModel,
-- allowing the game's own viewport system to build WorldModel + fixed Camera.
local oldAdd = [[    local function addUnitVisual(parent, copy, slotIndex)
        local source = UI.Resolver.ByAsset[copy.Asset] or UI.Resolver.BySlot[slotIndex]
        if cloneVisual(source, parent) then return "GAME UI" end
        if modelVisual(copy.Asset, parent) then return "GAME MODEL" end
        local placeholder = label(parent, tostring(copy.DisplayName):sub(1, 1):upper(), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), {
            Bold = true, TextSize = 28, Align = Enum.TextXAlignment.Center,
        })
        return "TEXT"
    end]]
local newAdd = [[    local function findSafeViewportTemplate()
        for _, object in ipairs(PlayerGui:GetDescendants()) do
            if object:IsA("GuiObject") and object:GetAttribute("SafeViewport") == true then
                local viewport = object:FindFirstChildWhichIsA("ViewportFrame", true)
                local showed = object:FindFirstChild("ShowedModel", true)
                if viewport and showed and showed:IsA("StringValue") then return object end
            end
        end
        return nil
    end

    local function gameNativeVisual(asset, parent)
        local template = findSafeViewportTemplate()
        local holder
        if template then
            local ok, clone = pcall(function() return template:Clone() end)
            if ok and clone then holder = clone end
        end
        if not holder then
            holder = Instance.new("Frame")
            holder.Name = "NativeUnitViewport"
            holder:SetAttribute("SafeViewport", true)
            holder.BackgroundTransparency = 1
            local viewport = Instance.new("ViewportFrame")
            viewport.Name = "ViewportFrame"
            viewport.BackgroundTransparency = 1
            viewport.Size = UDim2.fromScale(1, 1)
            viewport.Parent = holder
            local showed = Instance.new("StringValue")
            showed.Name = "ShowedModel"
            showed.Parent = holder
        end
        holder.Name = "NativeUnitViewport"
        holder.Position = UDim2.fromScale(0,0)
        holder.Size = UDim2.fromScale(1,1)
        holder.BackgroundTransparency = 1
        holder.Visible = true
        for _, child in ipairs(holder:GetChildren()) do
            if child:IsA("GuiObject") and not child:IsA("ViewportFrame") then
                child.Visible = false
            end
        end
        local showed = holder:FindFirstChild("ShowedModel", true)
        local viewport = holder:FindFirstChildWhichIsA("ViewportFrame", true)
        if not showed or not viewport then holder:Destroy(); return false end
        for _, child in ipairs(viewport:GetChildren()) do child:Destroy() end
        viewport.Size = UDim2.fromScale(1,1)
        viewport.Position = UDim2.fromScale(0,0)
        viewport.BackgroundTransparency = 1
        showed.Value = ""
        holder.Parent = parent
        task.defer(function()
            if holder.Parent and showed.Parent then showed.Value = tostring(asset or "") end
        end)
        return true
    end

    local function addUnitVisual(parent, copy, slotIndex)
        if gameNativeVisual(copy.Asset, parent) then return "GAME SAFE VIEWPORT" end
        local source = UI.Resolver.ByAsset[copy.Asset]
        if source and source:IsA("ViewportFrame") and cloneVisual(source, parent) then return "GAME VIEWPORT CLONE" end
        label(parent, tostring(copy.DisplayName):sub(1, 1):upper(), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), {
            Bold = true, TextSize = 28, Align = Enum.TextXAlignment.Center,
        })
        return "TEXT"
    end]]
local as,ae=string.find(joined,oldAdd,1,true)
if as then joined=string.sub(joined,1,as-1)..newAdd..string.sub(joined,ae+1) end

-- Uniform world projection -----------------------------------------------------
-- Use one pixels-per-stud scale for both X and Z. This preserves geometry:
-- a world-space circle remains a circle and the route gets letterboxing instead
-- of being stretched independently on each axis.
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
