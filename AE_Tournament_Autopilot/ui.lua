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

    local function findUnitViewViewport(copy)
        local unitView = PlayerGui:FindFirstChild("UnitView")
        if not unitView or not unitViewHasName(unitView, copy.DisplayName) then return nil end
        -- Do NOT require Visible=true. UnitView is commonly hidden again after the
        -- user returns to the game/Brain, while its rendered WorldModel stays alive.
        local best, bestParts = nil, 0
        for _, d in ipairs(unitView:GetDescendants()) do
            if d:IsA("ViewportFrame") then
                local world = d:FindFirstChildWhichIsA("WorldModel", true)
                if world then
                    local parts = 0
                    for _, x in ipairs(world:GetDescendants()) do if x:IsA("BasePart") then parts += 1 end end
                    if parts > bestParts then best, bestParts = d, parts end
                end
            end
        end
        return best
    end

    local function setArchivableTree(root, value, backup)
        backup = backup or {}
        local function apply(obj)
            local ok, old = pcall(function() return obj.Archivable end)
            if ok then backup[obj]=old;pcall(function()obj.Archivable=value end) end
        end
        apply(root);for _,d in ipairs(root:GetDescendants()) do apply(d) end;return backup
    end
    local function restoreArchivable(backup)
        for obj,value in pairs(backup or {}) do if obj then pcall(function()obj.Archivable=value end) end end
    end

    local function cloneWorldModel(sourceWorld)
        local backup=setArchivableTree(sourceWorld,true)
        local ok,cloned=pcall(function()return sourceWorld:Clone()end)
        restoreArchivable(backup)
        if ok and cloned and cloned:FindFirstChildWhichIsA("BasePart",true) then return cloned end
        if cloned then cloned:Destroy() end

        local world=Instance.new("WorldModel")
        -- Last-resort deep copy by top-level child. This handles rigs whose root
        -- WorldModel or Model is non-Archivable in the live game UI.
        for _,child in ipairs(sourceWorld:GetChildren()) do
            local childBackup=setArchivableTree(child,true)
            local childOk,childClone=pcall(function()return child:Clone()end)
            restoreArchivable(childBackup)
            if childOk and childClone then childClone.Parent=world end
        end
        if world:FindFirstChildWhichIsA("BasePart",true) then return world end
        world:Destroy();return nil
    end

    local function visibleBounds(world)
        local minX,minY,minZ=math.huge,math.huge,math.huge
        local maxX,maxY,maxZ=-math.huge,-math.huge,-math.huge;local count=0
        for _,part in ipairs(world:GetDescendants()) do
            if part:IsA("BasePart") and part.Transparency<0.98 then
                local cf,sz=part.CFrame,part.Size
                for sx=-1,1,2 do for sy=-1,1,2 do for zz=-1,1,2 do
                    local p=cf:PointToWorldSpace(Vector3.new(sz.X*sx/2,sz.Y*sy/2,sz.Z*zz/2))
                    minX=math.min(minX,p.X);maxX=math.max(maxX,p.X);minY=math.min(minY,p.Y);maxY=math.max(maxY,p.Y);minZ=math.min(minZ,p.Z);maxZ=math.max(maxZ,p.Z)
                end end end;count+=1
            end
        end
        if count==0 then return nil end
        return Vector3.new((minX+maxX)/2,(minY+maxY)/2,(minZ+maxZ)/2),Vector3.new(maxX-minX,maxY-minY,maxZ-minZ)
    end

    local function renderCopiedWorld(sourceViewport,parent)
        local sourceWorld=sourceViewport and sourceViewport:FindFirstChildWhichIsA("WorldModel",true)
        if not sourceWorld then return false end
        local world=cloneWorldModel(sourceWorld);if not world then return false end
        local viewport=Instance.new("ViewportFrame")
        viewport.Name="AECopiedGamePortrait";viewport.Size=UDim2.fromScale(1,1);viewport.Position=UDim2.fromScale(0,0);viewport.BackgroundTransparency=1;viewport.BorderSizePixel=0
        viewport.Ambient=sourceViewport.Ambient;viewport.LightColor=sourceViewport.LightColor;viewport.LightDirection=sourceViewport.LightDirection;viewport.Parent=parent;world.Parent=viewport
        for _,d in ipairs(world:GetDescendants()) do
            if d:IsA("BasePart") then d.Anchored=true;d.CanCollide=false end
            if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then d.Enabled=false end
        end
        local center,size=visibleBounds(world);if not center then viewport:Destroy();return false end
        local sourceCam=sourceViewport.CurrentCamera or sourceViewport:FindFirstChildWhichIsA("Camera",true)
        local cam=Instance.new("Camera");cam.FieldOfView=sourceCam and sourceCam.FieldOfView or 32
        local look=sourceCam and sourceCam.CFrame.LookVector or Vector3.new(0,0,-1);if look.Magnitude<0.1 then look=Vector3.new(0,0,-1) end
        local halfFov=math.rad(math.clamp(cam.FieldOfView,15,70)*0.5)
        local halfHeight=math.max(size.Y*0.58,size.X*0.58,size.Z*0.35)
        local distance=halfHeight/math.max(0.12,math.tan(halfFov))*1.22
        local target=center+Vector3.new(0,size.Y*0.02,0)
        cam.CFrame=CFrame.lookAt(target-look.Unit*distance,target);cam.Parent=viewport;viewport.CurrentCamera=cam
        return true
    end

    local function addUnitVisual(parent,copy,slotIndex)
        local source=findUnitViewViewport(copy)
        if source and renderCopiedWorld(source,parent) then return "COPIED HIDDEN UNITVIEW" end
        label(parent,tostring(copy.DisplayName):sub(1,1):upper(),UDim2.fromScale(0,0),UDim2.fromScale(1,1),{Bold=true,TextSize=28,Align=Enum.TextXAlignment.Center})
        return "TEXT"
    end

]]
joined=string.sub(joined,1,addStart-1)..portrait..string.sub(joined,addEnd)
else
    warn("[Tournament UI] addUnitVisual marker missing")
end

local oldCanvas=[[    local function toCanvas(position, bounds, size)
        local x = 24 + ((position.X - bounds.MinX) / (bounds.MaxX - bounds.MinX)) * math.max(1, size.X - 48)
        local y = 24 + ((position.Z - bounds.MinZ) / (bounds.MaxZ - bounds.MinZ)) * math.max(1, size.Y - 48)
        return Vector2.new(x, y)
    end]]
local newCanvas=[[    local function worldCanvasScale(bounds,size)
        local sx=math.max(1,bounds.MaxX-bounds.MinX);local sz=math.max(1,bounds.MaxZ-bounds.MinZ)
        return math.min(math.max(1,size.X-48)/sx,math.max(1,size.Y-48)/sz)
    end
    local function toCanvas(position,bounds,size)
        local sx=math.max(1,bounds.MaxX-bounds.MinX);local sz=math.max(1,bounds.MaxZ-bounds.MinZ);local scale=worldCanvasScale(bounds,size)
        local usedX,usedY=sx*scale,sz*scale
        return Vector2.new((size.X-usedX)*0.5+(position.X-bounds.MinX)*scale,(size.Y-usedY)*0.5+(position.Z-bounds.MinZ)*scale)
    end]]
local cs,ce=string.find(joined,oldCanvas,1,true);if cs then joined=string.sub(joined,1,cs-1)..newCanvas..string.sub(joined,ce+1) end

local chunk,compileError=loadstring(joined)
if not chunk then error("Tournament UI compile error: "..tostring(compileError)) end
return chunk()
