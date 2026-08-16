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

-- Portraits: V2 proved UnitView itself contains the selected unit model. Example:
-- visible UnitView text = "8th Sword (Berserk)" while its ViewportFrame contains
-- kenpachi rigs and a fixed FOV 32 camera. So display-name text is authoritative.
local oldAddStart = string.find(joined, "    local function findSafeViewportTemplate()\n", 1, true)
if not oldAddStart then oldAddStart = string.find(joined, "    local function viewportNearbyText(viewport)\n", 1, true) end
local oldAddEnd = oldAddStart and string.find(joined, "    -- Map drawing", oldAddStart, true) or nil
if oldAddStart and oldAddEnd then
local portraitReplacement = [[    local function guiContainsDisplayName(root, displayName)
        local wanted = norm(displayName)
        if wanted == "" then return false end
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") then
                if norm(d.Text) == wanted then return true end
            end
        end
        return false
    end

    local function cloneViewportExact(sourceViewport, parent)
        if not sourceViewport or not sourceViewport:IsA("ViewportFrame") then return false end
        local clone = sourceViewport:Clone()
        clone.Name = "ExactGameUnitPortrait"
        clone.Size = UDim2.fromScale(1,1)
        clone.Position = UDim2.fromScale(0,0)
        clone.AnchorPoint = Vector2.new(0,0)
        clone.BackgroundTransparency = 1
        clone.Visible = true
        clone.Parent = parent
        -- Cloning a ViewportFrame does not reliably preserve CurrentCamera binding.
        local camera = clone:FindFirstChildWhichIsA("Camera", true)
        if camera then clone.CurrentCamera = camera end
        return clone:FindFirstChildWhichIsA("WorldModel", true) ~= nil and clone.CurrentCamera ~= nil
    end

    local function cloneSelectedUnitView(copy, parent)
        local unitView = PlayerGui:FindFirstChild("UnitView")
        if not unitView or not guiContainsDisplayName(unitView, copy.DisplayName) then return false end
        local best = nil
        for _, d in ipairs(unitView:GetDescendants()) do
            if d:IsA("ViewportFrame") and d.Visible then
                local world = d:FindFirstChildWhichIsA("WorldModel", true)
                if world then
                    local hasParts = world:FindFirstChildWhichIsA("BasePart", true) ~= nil
                    if hasParts then best = d; break end
                end
            end
        end
        return best and cloneViewportExact(best,parent) or false
    end

    local function cloneNamedGameCard(copy, parent)
        local wanted = norm(copy.DisplayName)
        if wanted == "" then return false end
        for _, textObject in ipairs(PlayerGui:GetDescendants()) do
            if (textObject:IsA("TextLabel") or textObject:IsA("TextButton")) and norm(textObject.Text) == wanted then
                local node = textObject.Parent
                for _=1,7 do
                    if not node then break end
                    for _, d in ipairs(node:GetDescendants()) do
                        if d:IsA("ViewportFrame") and d.Visible and d:FindFirstChildWhichIsA("WorldModel",true) then
                            if cloneViewportExact(d,parent) then return true end
                        end
                    end
                    node=node.Parent
                end
            end
        end
        return false
    end

    local function addUnitVisual(parent, copy, slotIndex)
        -- Exact selected UnitView is strongest evidence and preserves the game's FOV 32.
        if cloneSelectedUnitView(copy,parent) then return "EXACT UNITVIEW" end
        if cloneNamedGameCard(copy,parent) then return "EXACT NAMED CARD" end
        if modelVisual(copy.Asset,parent) then return "DIRECT MODEL" end
        label(parent,tostring(copy.DisplayName):sub(1,1):upper(),UDim2.fromScale(0,0),UDim2.fromScale(1,1),{Bold=true,TextSize=28,Align=Enum.TextXAlignment.Center})
        return "TEXT"
    end

]]
joined=string.sub(joined,1,oldAddStart-1)..portraitReplacement..string.sub(joined,oldAddEnd)
end

-- Uniform world projection: preserve 1 stud equally on X/Z.
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
