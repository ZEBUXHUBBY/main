local ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Tournament_Autopilot/ui_parts/"
local nonce = tostring(os.time()) .. "-" .. tostring(math.random(100000,999999))
local parts = {"01.lua","02.lua","03.lua","04.lua","05.lua"}
local source = {}
for _, path in ipairs(parts) do
    local ok, body = pcall(function() return game:HttpGet(ROOT .. path .. "?v23parts=" .. nonce) end)
    if not ok then error("Tournament UI V2.3 part fetch failed " .. path .. ": " .. tostring(body)) end
    source[#source + 1] = body
end
local joined = table.concat(source,"\n")

-- Visible version stamp: if this text is absent, this file was not loaded.
joined = joined:gsub('TOURNAMENT BRAIN', 'TOURNAMENT BRAIN · V2.3-WM', 1)

-- Readability
joined = joined:gsub('TextSize = 8, Truncate = Enum.TextTruncate.AtEnd', 'TextSize = 9, Truncate = Enum.TextTruncate.AtEnd')
joined = joined:gsub('Bold = true, TextSize = 10, Truncate = Enum.TextTruncate.AtEnd', 'Bold = true, TextSize = 11, Truncate = Enum.TextTruncate.AtEnd')
joined = joined:gsub('Bold = true, TextSize = 7, Align = Enum.TextXAlignment.Center', 'Bold = true, TextSize = 8, Align = Enum.TextXAlignment.Center')
joined = joined:gsub('Bold = true, TextSize = 8, Align = Enum.TextXAlignment.Right', 'Bold = true, TextSize = 9, Align = Enum.TextXAlignment.Right')
joined = joined:gsub('Color = COLORS.Muted, TextSize = 8,', 'Color = COLORS.Muted, TextSize = 10,')
joined = joined:gsub('tostring%(copy%.Role or "DPS"%) %.%. "  •  " %.%. fmt%(copy%.CapDPS, 0%)', 'tostring(copy.Trait or "No Trait") .. "  •  " .. tostring(copy.Role or "DPS") .. "  •  " .. fmt(copy.CapDPS, 0)')
joined = joined:gsub('copy%.DisplayName %.%. "  •  target "', 'copy.DisplayName .. "  •  " .. tostring(copy.Trait or "No Trait") .. "  •  target "')
joined = joined:gsub('TeamSub%.Text = "Tap a unit to inspect placement %+ target"', 'TeamSub.Text = "V2.3-WM • WorldModel portrait cache • tap to inspect"')

local addStart = string.find(joined, "    local function addUnitVisual(parent, copy, slotIndex)\n", 1, true)
local addEnd = addStart and string.find(joined, "    local function modifierChip", addStart, true) or nil
if addStart and addEnd then
local portrait = [[    UI.PortraitCache = UI.PortraitCache or {}

    local function portraitKey(name)
        return norm(tostring(name or ""))
    end

    local function exactTextExists(root, text)
        local wanted = portraitKey(text)
        for _, d in ipairs(root:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and portraitKey(d.Text) == wanted then return true end
        end
        return false
    end

    local function archivableClone(root)
        if not root then return nil end
        local backup = {}
        local function setOne(x)
            local ok, old = pcall(function() return x.Archivable end)
            if ok then backup[#backup+1] = {x,old}; pcall(function() x.Archivable=true end) end
        end
        setOne(root)
        for _, d in ipairs(root:GetDescendants()) do setOne(d) end
        local ok, cloned = pcall(function() return root:Clone() end)
        for _, item in ipairs(backup) do pcall(function() item[1].Archivable=item[2] end) end
        if ok and cloned and cloned:FindFirstChildWhichIsA("BasePart",true) then return cloned end
        if cloned then cloned:Destroy() end
        return nil
    end

    local function captureExactUnit(copy)
        local key = portraitKey(copy.DisplayName)
        if UI.PortraitCache[key] and UI.PortraitCache[key].World then return UI.PortraitCache[key] end
        local unitView = PlayerGui:FindFirstChild("UnitView")
        if not unitView or not exactTextExists(unitView,copy.DisplayName) then return nil end

        local bestViewport,bestWorld,bestParts=nil,nil,0
        for _, d in ipairs(unitView:GetDescendants()) do
            if d:IsA("ViewportFrame") then
                local world=d:FindFirstChildWhichIsA("WorldModel",true)
                if world then
                    local parts=0
                    for _,x in ipairs(world:GetDescendants()) do if x:IsA("BasePart") then parts+=1 end end
                    if parts>bestParts then bestViewport,bestWorld,bestParts=d,world,parts end
                end
            end
        end
        if not bestWorld or bestParts==0 then return nil end
        local cloned=archivableClone(bestWorld)
        if not cloned then return nil end
        local cam=bestViewport.CurrentCamera or bestViewport:FindFirstChildWhichIsA("Camera",true)
        UI.PortraitCache[key]={
            World=cloned,
            FOV=cam and cam.FieldOfView or 32,
            LookVector=cam and cam.CFrame.LookVector or Vector3.new(0,0,-1),
            UpVector=cam and cam.CFrame.UpVector or Vector3.new(0,1,0),
            Parts=bestParts,
        }
        return UI.PortraitCache[key]
    end

    local function bounds(world)
        local mn=Vector3.new(math.huge,math.huge,math.huge)
        local mx=Vector3.new(-math.huge,-math.huge,-math.huge)
        local n=0
        for _,p in ipairs(world:GetDescendants()) do
            if p:IsA("BasePart") and p.Transparency<0.99 then
                local cf,sz=p.CFrame,p.Size
                for x=-1,1,2 do for y=-1,1,2 do for z=-1,1,2 do
                    local q=cf:PointToWorldSpace(Vector3.new(sz.X*x/2,sz.Y*y/2,sz.Z*z/2))
                    mn=Vector3.new(math.min(mn.X,q.X),math.min(mn.Y,q.Y),math.min(mn.Z,q.Z))
                    mx=Vector3.new(math.max(mx.X,q.X),math.max(mx.Y,q.Y),math.max(mx.Z,q.Z))
                end end end
                n+=1
            end
        end
        if n==0 then return nil end
        return (mn+mx)/2,mx-mn
    end

    local function renderWorld(cache,parent)
        if not cache or not cache.World then return false end
        local world=archivableClone(cache.World)
        if not world then return false end
        local viewport=Instance.new("ViewportFrame")
        viewport.Name="AE_V23_WorldModelPortrait"
        viewport.Size=UDim2.fromScale(1,1)
        viewport.BackgroundTransparency=1
        viewport.BorderSizePixel=0
        viewport.Ambient=Color3.fromRGB(205,205,215)
        viewport.LightColor=Color3.fromRGB(255,246,236)
        viewport.LightDirection=Vector3.new(-1,-1,-1)
        viewport.Parent=parent
        world.Parent=viewport
        for _,d in ipairs(world:GetDescendants()) do
            if d:IsA("BasePart") then d.Anchored=true; d.CanCollide=false end
            if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then d.Enabled=false end
        end
        local center,size=bounds(world)
        if not center then viewport:Destroy();return false end
        local cam=Instance.new("Camera")
        cam.FieldOfView=tonumber(cache.FOV) or 32
        local look=cache.LookVector or Vector3.new(0,0,-1)
        local up=cache.UpVector or Vector3.new(0,1,0)
        if look.Magnitude<0.1 then look=Vector3.new(0,0,-1) end
        local halfFov=math.rad(math.clamp(cam.FieldOfView,15,70)*0.5)
        local framing=math.max(size.Y*0.58,size.X*0.50,size.Z*0.35,1)
        local distance=framing/math.max(0.12,math.tan(halfFov))*0.92
        local target=center+Vector3.new(0,size.Y*0.10,0)
        cam.CFrame=CFrame.lookAt(target-look.Unit*distance,target,up)
        cam.Parent=viewport
        viewport.CurrentCamera=cam
        return true
    end

    local function addUnitVisual(parent,copy,slotIndex)
        local cache=UI.PortraitCache[portraitKey(copy.DisplayName)] or captureExactUnit(copy)
        if cache and renderWorld(cache,parent) then return "V23 WORLDMODEL" end
        label(parent,tostring(copy.DisplayName):sub(1,1):upper(),UDim2.fromScale(0,0),UDim2.fromScale(1,1),{Bold=true,TextSize=28,Align=Enum.TextXAlignment.Center})
        return "TEXT"
    end

]]
joined=string.sub(joined,1,addStart-1)..portrait..string.sub(joined,addEnd)
else
    error("V2.3-WM portrait patch marker missing")
end

-- Preserve equal stud scale on tactical map.
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
local cs,ce=string.find(joined,oldCanvas,1,true)
if cs then joined=string.sub(joined,1,cs-1)..newCanvas..string.sub(joined,ce+1) end

local chunk,compileError=loadstring(joined)
if not chunk then error("Tournament UI V2.3 compile error: "..tostring(compileError)) end
return chunk()
