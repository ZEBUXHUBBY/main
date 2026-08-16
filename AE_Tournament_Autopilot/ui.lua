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

-- Readability patches.
joined = joined:gsub('TextSize = 8, Truncate = Enum.TextTruncate.AtEnd', 'TextSize = 9, Truncate = Enum.TextTruncate.AtEnd')
joined = joined:gsub('Bold = true, TextSize = 10, Truncate = Enum.TextTruncate.AtEnd', 'Bold = true, TextSize = 11, Truncate = Enum.TextTruncate.AtEnd')
joined = joined:gsub('Bold = true, TextSize = 7, Align = Enum.TextXAlignment.Center', 'Bold = true, TextSize = 8, Align = Enum.TextXAlignment.Center')
joined = joined:gsub('Bold = true, TextSize = 8, Align = Enum.TextXAlignment.Right', 'Bold = true, TextSize = 9, Align = Enum.TextXAlignment.Right')
joined = joined:gsub('Color = COLORS.Muted, TextSize = 8,', 'Color = COLORS.Muted, TextSize = 10,')
joined = joined:gsub('tostring%(copy%.Role or "DPS"%) %.%. "  •  " %.%. fmt%(copy%.CapDPS, 0%)', 'tostring(copy.Trait or "No Trait") .. "  •  " .. tostring(copy.Role or "DPS") .. "  •  " .. fmt(copy.CapDPS, 0)')
joined = joined:gsub('copy%.DisplayName %.%. "  •  target "', 'copy.DisplayName .. "  •  " .. tostring(copy.Trait or "No Trait") .. "  •  target "')
joined = joined:gsub('TeamSub%.Text = "Tap a unit to inspect placement %+ target"', 'TeamSub.Text = "Best copy from whole inventory • tap to inspect"')

-- Portrait renderer. Portrait Render Tester V2 proved WorldModel:Clone() works
-- reliably in this executor while cloning a whole ViewportFrame does not.
local addStart = string.find(joined, "    local function addUnitVisual(parent, copy, slotIndex)\n", 1, true)
local addEnd = addStart and string.find(joined, "    local function modifierChip", addStart, true) or nil
if addStart and addEnd then
local portrait = [[    UI.PortraitCache = UI.PortraitCache or {}

    local function normalizeDisplayName(value)
        return norm(tostring(value or ""))
    end

    local function setTreeArchivable(root, value)
        local backup = {}
        local function setOne(object)
            local ok, old = pcall(function() return object.Archivable end)
            if ok then
                backup[#backup + 1] = {object, old}
                pcall(function() object.Archivable = value end)
            end
        end
        setOne(root)
        for _, descendant in ipairs(root:GetDescendants()) do setOne(descendant) end
        return backup
    end

    local function restoreTreeArchivable(backup)
        for _, item in ipairs(backup or {}) do
            pcall(function() item[1].Archivable = item[2] end)
        end
    end

    local function cloneWorld(sourceWorld)
        if not sourceWorld then return nil end
        local backup = setTreeArchivable(sourceWorld, true)
        local ok, cloned = pcall(function() return sourceWorld:Clone() end)
        restoreTreeArchivable(backup)
        if ok and cloned and cloned:FindFirstChildWhichIsA("BasePart", true) then return cloned end
        if cloned then cloned:Destroy() end
        return nil
    end

    local function worldBounds(world)
        local minX,minY,minZ = math.huge,math.huge,math.huge
        local maxX,maxY,maxZ = -math.huge,-math.huge,-math.huge
        local count = 0
        for _, part in ipairs(world:GetDescendants()) do
            if part:IsA("BasePart") and part.Transparency < 0.99 then
                local cf, size = part.CFrame, part.Size
                for sx=-1,1,2 do
                    for sy=-1,1,2 do
                        for sz=-1,1,2 do
                            local p = cf:PointToWorldSpace(Vector3.new(size.X*sx/2,size.Y*sy/2,size.Z*sz/2))
                            minX=math.min(minX,p.X); maxX=math.max(maxX,p.X)
                            minY=math.min(minY,p.Y); maxY=math.max(maxY,p.Y)
                            minZ=math.min(minZ,p.Z); maxZ=math.max(maxZ,p.Z)
                        end
                    end
                end
                count += 1
            end
        end
        if count == 0 then return nil end
        return Vector3.new((minX+maxX)/2,(minY+maxY)/2,(minZ+maxZ)/2), Vector3.new(maxX-minX,maxY-minY,maxZ-minZ), count
    end

    local function currentUnitViewSource()
        local unitView = PlayerGui:FindFirstChild("UnitView")
        if not unitView then return nil end

        local displayName = nil
        -- Prefer a meaningful visible title, but accept hidden UI because the
        -- game's WorldModel often survives after UnitView is closed.
        for _, descendant in ipairs(unitView:GetDescendants()) do
            if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
                local text = tostring(descendant.Text or "")
                if text ~= "" and text ~= "???" and #text >= 4 and #text <= 70 and text:find("(",1,true) then
                    displayName = text
                    if descendant.Visible then break end
                end
            end
        end
        if not displayName then return nil end

        local bestViewport,bestWorld,bestParts = nil,nil,0
        for _, descendant in ipairs(unitView:GetDescendants()) do
            if descendant:IsA("ViewportFrame") then
                local world = descendant:FindFirstChildWhichIsA("WorldModel", true)
                if world then
                    local parts = 0
                    for _, object in ipairs(world:GetDescendants()) do if object:IsA("BasePart") then parts += 1 end end
                    if parts > bestParts then
                        bestViewport,bestWorld,bestParts = descendant,world,parts
                    end
                end
            end
        end
        if not bestWorld or bestParts == 0 then return nil end
        local camera = bestViewport.CurrentCamera or bestViewport:FindFirstChildWhichIsA("Camera",true)
        return {
            DisplayName = displayName,
            Viewport = bestViewport,
            World = bestWorld,
            FOV = camera and camera.FieldOfView or 32,
            CameraCFrame = camera and camera.CFrame or CFrame.new(0,0,10),
            Parts = bestParts,
        }
    end

    local function captureCurrentPortrait()
        local source = currentUnitViewSource()
        if not source then return nil end
        local cloned = cloneWorld(source.World)
        if not cloned then return nil end
        local key = normalizeDisplayName(source.DisplayName)
        local old = UI.PortraitCache[key]
        if old and old.World then pcall(function() old.World:Destroy() end) end
        UI.PortraitCache[key] = {
            DisplayName = source.DisplayName,
            World = cloned,
            FOV = source.FOV,
            LookVector = source.CameraCFrame.LookVector,
            UpVector = source.CameraCFrame.UpVector,
            Parts = source.Parts,
        }
        return UI.PortraitCache[key]
    end

    local function cacheFor(copy)
        local key = normalizeDisplayName(copy.DisplayName)
        local cached = UI.PortraitCache[key]
        if cached and cached.World and cached.World.Parent == nil then return cached end

        -- Capture whatever the game's UnitView is currently showing. If it is
        -- this copy, it becomes available immediately; otherwise it is cached
        -- for the corresponding team card when that unit is rendered later.
        captureCurrentPortrait()
        return UI.PortraitCache[key]
    end

    local function renderCachedPortrait(cache, parent)
        if not cache or not cache.World then return false end
        local world = cloneWorld(cache.World)
        if not world then return false end

        local viewport = Instance.new("ViewportFrame")
        viewport.Name = "AEUnitPortrait"
        viewport.Size = UDim2.fromScale(1,1)
        viewport.Position = UDim2.fromScale(0,0)
        viewport.BackgroundTransparency = 1
        viewport.BorderSizePixel = 0
        viewport.Ambient = Color3.fromRGB(205,205,215)
        viewport.LightColor = Color3.fromRGB(255,246,236)
        viewport.LightDirection = Vector3.new(-1,-1,-1)
        viewport.Parent = parent
        world.Parent = viewport

        for _, descendant in ipairs(world:GetDescendants()) do
            if descendant:IsA("BasePart") then
                descendant.Anchored = true
                descendant.CanCollide = false
            elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
                descendant.Enabled = false
            end
        end

        local center,size = worldBounds(world)
        if not center then viewport:Destroy(); return false end

        local camera = Instance.new("Camera")
        camera.FieldOfView = tonumber(cache.FOV) or 32
        local look = cache.LookVector or Vector3.new(0,0,-1)
        local up = cache.UpVector or Vector3.new(0,1,0)
        if look.Magnitude < 0.1 then look = Vector3.new(0,0,-1) end

        -- Portrait crop: closer than the tester's full-body framing. Use body
        -- height as the main constraint so the face/torso fills a 54x54 card.
        local halfFov = math.rad(math.clamp(camera.FieldOfView,15,70)*0.5)
        local portraitHeight = math.max(size.Y * 0.72, size.X * 0.58, size.Z * 0.42, 1)
        local distance = portraitHeight / math.max(0.12,math.tan(halfFov)) * 0.82
        local target = center + Vector3.new(0,size.Y*0.12,0)
        camera.CFrame = CFrame.lookAt(target - look.Unit*distance, target, up)
        camera.Parent = viewport
        viewport.CurrentCamera = camera
        return true
    end

    local function addUnitVisual(parent, copy, slotIndex)
        local cache = cacheFor(copy)
        if cache and renderCachedPortrait(cache,parent) then return "WORLDMODEL CACHE" end
        label(parent,tostring(copy.DisplayName):sub(1,1):upper(),UDim2.fromScale(0,0),UDim2.fromScale(1,1),{
            Bold=true,TextSize=28,Align=Enum.TextXAlignment.Center
        })
        return "TEXT"
    end

]]
joined = string.sub(joined,1,addStart-1) .. portrait .. string.sub(joined,addEnd)
else
    warn("[Tournament UI] addUnitVisual marker missing")
end

-- Preserve one uniform stud-to-pixel scale on tactical map.
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
if not chunk then error("Tournament UI compile error: "..tostring(compileError)) end
return chunk()
