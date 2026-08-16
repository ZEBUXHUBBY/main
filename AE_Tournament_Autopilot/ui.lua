local ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Tournament_Autopilot/ui_parts/"
local nonce = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
local parts = {"01.lua","02.lua","03.lua","04.lua","05.lua"}
local source = {}
for _, path in ipairs(parts) do
    local ok, body = pcall(function() return game:HttpGet(ROOT .. path .. "?ui=" .. nonce) end)
    if not ok then error("Tournament UI part fetch failed " .. path .. ": " .. tostring(body)) end
    source[#source + 1] = body
end
local joined = table.concat(source,"\n")

-- Readability
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

-- Portrait patch. IMPORTANT: patch the function that actually exists in ui_parts/03.lua.
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
local newAdd = [[    local function unitViewHasName(unitView, displayName)
        local wanted = norm(displayName)
        if wanted == "" then return false end
        for _, d in ipairs(unitView:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and norm(d.Text) == wanted then
                return true
            end
        end
        return false
    end

    local function cloneExactViewport(sourceViewport, parent)
        if not sourceViewport or not sourceViewport:IsA("ViewportFrame") then return false end
        local ok, clone = pcall(function()
            local previous = sourceViewport.Archivable
            sourceViewport.Archivable = true
            local result = sourceViewport:Clone()
            sourceViewport.Archivable = previous
            return result
        end)
        if not ok or not clone then return false end
        clone.Name = "AEExactUnitViewport"
        clone.AnchorPoint = Vector2.new(0,0)
        clone.Position = UDim2.fromScale(0,0)
        clone.Size = UDim2.fromScale(1,1)
        clone.BackgroundTransparency = 1
        clone.BorderSizePixel = 0
        clone.Visible = true
        local camera = clone:FindFirstChildWhichIsA("Camera", true)
        if camera then clone.CurrentCamera = camera end
        local world = clone:FindFirstChildWhichIsA("WorldModel", true)
        local hasPart = world and world:FindFirstChildWhichIsA("BasePart", true) ~= nil
        if not camera or not hasPart then clone:Destroy(); return false end
        clone.Parent = parent
        return true
    end

    local function cloneFromSelectedUnitView(copy, parent)
        local unitView = PlayerGui:FindFirstChild("UnitView")
        if not unitView or not unitViewHasName(unitView, copy.DisplayName) then return false end
        for _, d in ipairs(unitView:GetDescendants()) do
            if d:IsA("ViewportFrame") and d.Visible then
                local world = d:FindFirstChildWhichIsA("WorldModel", true)
                if world and world:FindFirstChildWhichIsA("BasePart", true) then
                    if cloneExactViewport(d, parent) then return true end
                end
            end
        end
        return false
    end

    local function cloneFromNamedCard(copy, parent)
        local wanted = norm(copy.DisplayName)
        for _, textObject in ipairs(PlayerGui:GetDescendants()) do
            if (textObject:IsA("TextLabel") or textObject:IsA("TextButton")) and norm(textObject.Text) == wanted then
                local node = textObject.Parent
                for _ = 1, 7 do
                    if not node then break end
                    for _, d in ipairs(node:GetDescendants()) do
                        if d:IsA("ViewportFrame") and d.Visible then
                            local world = d:FindFirstChildWhichIsA("WorldModel", true)
                            if world and world:FindFirstChildWhichIsA("BasePart", true) and cloneExactViewport(d,parent) then
                                return true
                            end
                        end
                    end
                    node = node.Parent
                end
            end
        end
        return false
    end

    local function addUnitVisual(parent, copy, slotIndex)
        -- V2 evidence: UnitView text identifies the selected unit and its viewport
        -- already contains the correct character rigs with the game's FOV 32 camera.
        if cloneFromSelectedUnitView(copy, parent) then return "EXACT UNITVIEW" end
        if cloneFromNamedCard(copy, parent) then return "EXACT CARD" end
        -- Do NOT reuse hotbar ImageLabels; those caused the colored-square portraits.
        label(parent, tostring(copy.DisplayName):sub(1,1):upper(), UDim2.fromScale(0,0), UDim2.fromScale(1,1), {
            Bold=true, TextSize=28, Align=Enum.TextXAlignment.Center,
        })
        return "TEXT"
    end]]
local ps,pe = string.find(joined, oldAdd, 1, true)
if ps then
    joined = string.sub(joined,1,ps-1) .. newAdd .. string.sub(joined,pe+1)
else
    warn("[Tournament UI] portrait patch marker missing")
end

-- Uniform world projection
local oldCanvas = [[    local function toCanvas(position, bounds, size)
        local x = 24 + ((position.X - bounds.MinX) / (bounds.MaxX - bounds.MinX)) * math.max(1, size.X - 48)
        local y = 24 + ((position.Z - bounds.MinZ) / (bounds.MaxZ - bounds.MinZ)) * math.max(1, size.Y - 48)
        return Vector2.new(x, y)
    end]]
local newCanvas = [[    local function worldCanvasScale(bounds,size)
        local spanX=math.max(1,bounds.MaxX-bounds.MinX);local spanZ=math.max(1,bounds.MaxZ-bounds.MinZ)
        return math.min(math.max(1,size.X-48)/spanX,math.max(1,size.Y-48)/spanZ)
    end
    local function toCanvas(position,bounds,size)
        local spanX=math.max(1,bounds.MaxX-bounds.MinX);local spanZ=math.max(1,bounds.MaxZ-bounds.MinZ);local scale=worldCanvasScale(bounds,size)
        local usedX,usedY=spanX*scale,spanZ*scale;local originX=(size.X-usedX)*0.5;local originY=(size.Y-usedY)*0.5
        return Vector2.new(originX+(position.X-bounds.MinX)*scale,originY+(position.Z-bounds.MinZ)*scale)
    end]]
local ts,te=string.find(joined,oldCanvas,1,true);if ts then joined=string.sub(joined,1,ts-1)..newCanvas..string.sub(joined,te+1) end

local oldRange = [[            local point = toCanvas(spot.WorldPosition, bounds, size)
            local worldWidth = math.max(bounds.MaxX - bounds.MinX, bounds.MaxZ - bounds.MinZ)
            local diameter = clamp((spot.Range / math.max(1, worldWidth)) * math.min(size.X, size.Y) * 2, 48, 180)

            local rangeCircle = Instance.new("Frame")
            rangeCircle.AnchorPoint = Vector2.new(0.5, 0.5)
            rangeCircle.Position = UDim2.fromOffset(point.X, point.Y)
            rangeCircle.Size = UDim2.fromOffset(diameter, diameter)]]
local newRange = [[            local point=toCanvas(spot.WorldPosition,bounds,size)
            local diameter=math.max(12,(tonumber(spot.Range) or 0)*worldCanvasScale(bounds,size)*2)
            local rangeCircle=Instance.new("Frame")
            rangeCircle.AnchorPoint=Vector2.new(0.5,0.5)
            rangeCircle.Position=UDim2.fromOffset(point.X,point.Y)
            rangeCircle.Size=UDim2.fromOffset(diameter,diameter)]]
local rs,re=string.find(joined,oldRange,1,true);if rs then joined=string.sub(joined,1,rs-1)..newRange..string.sub(joined,re+1) end

local marker=[[            marker.AutoButtonColor = false

            label(MapSurface, spot.Purpose,]]
local markerReplace=[[            marker.AutoButtonColor = false
            label(MapSurface,"R "..string.format("%.1f",tonumber(spot.Range) or 0),UDim2.fromOffset(point.X-38,point.Y-35),UDim2.fromOffset(76,16),{Bold=true,TextSize=8,Align=Enum.TextXAlignment.Center}).TextColor3=rangeCircle.BackgroundColor3

            label(MapSurface, spot.Purpose,]]
local ms,me=string.find(joined,marker,1,true);if ms then joined=string.sub(joined,1,ms-1)..markerReplace..string.sub(joined,me+1) end

local chunk,compileError=loadstring(joined)
if not chunk then error("Tournament UI compile error: "..tostring(compileError)) end
return chunk()
