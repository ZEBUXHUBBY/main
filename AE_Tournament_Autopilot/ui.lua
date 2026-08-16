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

-- Replace the actual addUnitVisual block from ui_parts/03.lua.
local addStart = string.find(joined, "    local function addUnitVisual(parent, copy, slotIndex)\n", 1, true)
local addEnd = addStart and string.find(joined, "    local function modifierChip", addStart, true) or nil
if addStart and addEnd then
local portrait = [[    local function unitViewHasName(unitView, displayName)
        local wanted = norm(displayName)
        if wanted == "" then return false end
        for _, d in ipairs(unitView:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and norm(d.Text) == wanted then return true end
        end
        return false
    end

    local function getWorldBounds(world)
        local minX,minY,minZ=math.huge,math.huge,math.huge
        local maxX,maxY,maxZ=-math.huge,-math.huge,-math.huge
        local count=0
        for _, part in ipairs(world:GetDescendants()) do
            if part:IsA("BasePart") and part.Transparency < 0.98 then
                local p=part.Position
                local h=part.Size*0.5
                minX=math.min(minX,p.X-h.X); maxX=math.max(maxX,p.X+h.X)
                minY=math.min(minY,p.Y-h.Y); maxY=math.max(maxY,p.Y+h.Y)
                minZ=math.min(minZ,p.Z-h.Z); maxZ=math.max(maxZ,p.Z+h.Z)
                count += 1
            end
        end
        if count == 0 then return nil end
        return Vector3.new((minX+maxX)*0.5,(minY+maxY)*0.5,(minZ+maxZ)*0.5), Vector3.new(maxX-minX,maxY-minY,maxZ-minZ)
    end

    local function fitViewportCamera(viewport, sourceCamera)
        local world=viewport:FindFirstChildWhichIsA("WorldModel",true)
        local camera=viewport.CurrentCamera or viewport:FindFirstChildWhichIsA("Camera",true)
        if not world or not camera then return false end
        local center,size=getWorldBounds(world)
        if not center then return false end

        local fov=(sourceCamera and sourceCamera.FieldOfView) or camera.FieldOfView or 32
        camera.FieldOfView=fov
        local halfFov=math.rad(math.clamp(fov,10,100)*0.5)
        local maxDim=math.max(size.X,size.Y,size.Z,1)
        -- The game's UnitView is ~16:9 but our card slot is close to square.
        -- Re-fit around the rig instead of copying the original camera distance.
        local distance=(maxDim*0.72)/math.max(0.12,math.tan(halfFov))*1.20
        local look=(sourceCamera and sourceCamera.CFrame.LookVector) or camera.CFrame.LookVector
        local up=(sourceCamera and sourceCamera.CFrame.UpVector) or camera.CFrame.UpVector
        if look.Magnitude < 0.5 then look=Vector3.new(0,0,-1) end
        local target=center+Vector3.new(0,size.Y*0.04,0)
        camera.CFrame=CFrame.lookAt(target-look.Unit*distance,target,up)
        viewport.CurrentCamera=camera
        return true
    end

    local function cloneExactViewport(sourceViewport,parent)
        if not sourceViewport or not sourceViewport:IsA("ViewportFrame") then return false end
        local oldArchivable=sourceViewport.Archivable
        sourceViewport.Archivable=true
        local ok,clone=pcall(function() return sourceViewport:Clone() end)
        sourceViewport.Archivable=oldArchivable
        if not ok or not clone then return false end

        clone.Name="AEFittedUnitViewport"
        clone.AnchorPoint=Vector2.new(0,0)
        clone.Position=UDim2.fromScale(0,0)
        clone.Size=UDim2.fromScale(1,1)
        clone.BackgroundTransparency=1
        clone.BorderSizePixel=0
        clone.Visible=true
        local camera=clone:FindFirstChildWhichIsA("Camera",true)
        if camera then clone.CurrentCamera=camera end
        clone.Parent=parent
        if not fitViewportCamera(clone,sourceViewport.CurrentCamera) then clone:Destroy(); return false end
        return true
    end

    local function viewportForSelectedUnit(copy)
        local unitView=PlayerGui:FindFirstChild("UnitView")
        if not unitView or not unitViewHasName(unitView,copy.DisplayName) then return nil end
        for _, d in ipairs(unitView:GetDescendants()) do
            if d:IsA("ViewportFrame") and d.Visible then
                local world=d:FindFirstChildWhichIsA("WorldModel",true)
                if world and world:FindFirstChildWhichIsA("BasePart",true) then return d end
            end
        end
        return nil
    end

    local function viewportForNamedCard(copy)
        local wanted=norm(copy.DisplayName)
        for _, textObject in ipairs(PlayerGui:GetDescendants()) do
            if (textObject:IsA("TextLabel") or textObject:IsA("TextButton")) and norm(textObject.Text)==wanted then
                local node=textObject.Parent
                for _=1,7 do
                    if not node then break end
                    for _, d in ipairs(node:GetDescendants()) do
                        if d:IsA("ViewportFrame") and d.Visible then
                            local world=d:FindFirstChildWhichIsA("WorldModel",true)
                            if world and world:FindFirstChildWhichIsA("BasePart",true) then return d end
                        end
                    end
                    node=node.Parent
                end
            end
        end
        return nil
    end

    local function addUnitVisual(parent,copy,slotIndex)
        local source=viewportForSelectedUnit(copy) or viewportForNamedCard(copy)
        if source and cloneExactViewport(source,parent) then return "FITTED UNITVIEW" end
        -- Do not use hotbar/card ImageLabels as fallback: they include stars/borders
        -- and were the source of the mis-positioned crop seen before.
        label(parent,tostring(copy.DisplayName):sub(1,1):upper(),UDim2.fromScale(0,0),UDim2.fromScale(1,1),{Bold=true,TextSize=28,Align=Enum.TextXAlignment.Center})
        return "TEXT"
    end

]]
joined=string.sub(joined,1,addStart-1)..portrait..string.sub(joined,addEnd)
else
    warn("[Tournament UI] addUnitVisual marker missing")
end

-- Uniform world projection for tactical map/range.
local oldCanvas=[[    local function toCanvas(position, bounds, size)
        local x = 24 + ((position.X - bounds.MinX) / (bounds.MaxX - bounds.MinX)) * math.max(1, size.X - 48)
        local y = 24 + ((position.Z - bounds.MinZ) / (bounds.MaxZ - bounds.MinZ)) * math.max(1, size.Y - 48)
        return Vector2.new(x, y)
    end]]
local newCanvas=[[    local function worldCanvasScale(bounds,size)
        local sx=math.max(1,bounds.MaxX-bounds.MinX); local sz=math.max(1,bounds.MaxZ-bounds.MinZ)
        return math.min(math.max(1,size.X-48)/sx,math.max(1,size.Y-48)/sz)
    end
    local function toCanvas(position,bounds,size)
        local sx=math.max(1,bounds.MaxX-bounds.MinX); local sz=math.max(1,bounds.MaxZ-bounds.MinZ); local scale=worldCanvasScale(bounds,size)
        local usedX,usedY=sx*scale,sz*scale
        return Vector2.new((size.X-usedX)*0.5+(position.X-bounds.MinX)*scale,(size.Y-usedY)*0.5+(position.Z-bounds.MinZ)*scale)
    end]]
local cs,ce=string.find(joined,oldCanvas,1,true);if cs then joined=string.sub(joined,1,cs-1)..newCanvas..string.sub(joined,ce+1) end

local chunk,compileError=loadstring(joined)
if not chunk then error("Tournament UI compile error: "..tostring(compileError)) end
return chunk()
