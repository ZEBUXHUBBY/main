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

-- Portraits: use the exact image assets already loaded by the game's own unit card.
-- We first locate text that exactly matches DisplayName, then only inspect images
-- inside nearby card ancestors. This prevents grabbing unrelated hotbar icons.
local addStart = string.find(joined, "    local function addUnitVisual(parent, copy, slotIndex)\n", 1, true)
local addEnd = addStart and string.find(joined, "    local function modifierChip", addStart, true) or nil
if addStart and addEnd then
local portrait = [[    local BAD_IMAGE_WORDS = {
        "trait","element","rarity","star","lock","border","frame","stroke",
        "background","bg","icon","badge","equipment","equip","target","cost",
        "gradient","shine","glow","shadow","level","lvl","favorite","fav"
    }

    local function badImageName(name)
        local n = norm(name)
        for _, word in ipairs(BAD_IMAGE_WORDS) do
            if n:find(word,1,true) then return true end
        end
        return false
    end

    local function exactNameLabels(displayName)
        local wanted = norm(displayName)
        local out = {}
        if wanted == "" then return out end
        for _, d in ipairs(PlayerGui:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and norm(d.Text) == wanted then
                out[#out+1] = d
            end
        end
        return out
    end

    local function imageCandidateScore(image, textObject, depth)
        if not (image:IsA("ImageLabel") or image:IsA("ImageButton")) then return -math.huge end
        if type(image.Image) ~= "string" or image.Image == "" then return -math.huge end
        if badImageName(image.Name) then return -220 end

        local size = image.AbsoluteSize
        if size.X < 24 or size.Y < 24 then return -120 end
        local score = 0
        local ratio = size.X / math.max(1,size.Y)
        if ratio >= 0.55 and ratio <= 1.55 then score += 80 else score -= 30 end
        if size.X >= 48 and size.Y >= 48 then score += 55 end
        if size.X >= 70 and size.Y >= 70 then score += 35 end
        if size.X > 260 or size.Y > 260 then score -= 70 end
        if image.Visible then score += 20 end
        score -= (depth or 0) * 8

        local n = norm(image.Name)
        if n:find("portrait",1,true) or n:find("unit",1,true) or n:find("character",1,true) or n:find("model",1,true) then score += 95 end
        if n:find("image",1,true) or n:find("display",1,true) then score += 30 end

        if textObject and textObject:IsA("GuiObject") then
            local ip = image.AbsolutePosition + image.AbsoluteSize*0.5
            local tp = textObject.AbsolutePosition + textObject.AbsoluteSize*0.5
            local dist = (ip-tp).Magnitude
            if dist < 180 then score += 60 elseif dist < 320 then score += 20 end
        end
        return score
    end

    local function findNamedPortrait(copy)
        local best,bestScore=nil,-math.huge
        for _, textObject in ipairs(exactNameLabels(copy.DisplayName)) do
            local node = textObject.Parent
            for depth=1,7 do
                if not node or node == PlayerGui then break end
                for _, d in ipairs(node:GetDescendants()) do
                    if d:IsA("ImageLabel") or d:IsA("ImageButton") then
                        local score = imageCandidateScore(d,textObject,depth)
                        if score > bestScore then best,bestScore=d,score end
                    end
                end
                node = node.Parent
            end
        end
        if bestScore < 45 then return nil,bestScore end
        return best,bestScore
    end

    local function renderNamedPortrait(source,parent)
        if not source then return false end
        local image = Instance.new("ImageLabel")
        image.Name = "AEGamePortrait"
        image.Size = UDim2.fromScale(1,1)
        image.Position = UDim2.fromScale(0,0)
        image.BackgroundTransparency = 1
        image.BorderSizePixel = 0
        image.Image = source.Image
        image.ImageColor3 = source.ImageColor3
        image.ImageTransparency = 0
        image.ImageRectOffset = source.ImageRectOffset
        image.ImageRectSize = source.ImageRectSize
        image.ResampleMode = source.ResampleMode
        -- Fill the Brain portrait box while preserving the game's crop/atlas.
        image.ScaleType = Enum.ScaleType.Crop
        image.Parent = parent
        return true
    end

    local function addUnitVisual(parent,copy,slotIndex)
        local source = findNamedPortrait(copy)
        if source and renderNamedPortrait(source,parent) then return "NAMED GAME PORTRAIT" end
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

-- Preserve equal world scale on the tactical map.
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
