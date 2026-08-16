-- AE Tournament Autopilot | Portrait Candidate Tester V1
-- Standalone/read-only UI tester. Finds a unit card by exact visible text and
-- previews every nearby ImageLabel/ImageButton so we can identify the real portrait.

local Players=game:GetService("Players")
local LP=Players.LocalPlayer
local PG=LP:WaitForChild("PlayerGui")

local TARGET="8th Sword (Berserk)"
local ENV=getgenv and getgenv() or _G
if type(ENV.AE_PORTRAIT_TEST_TARGET)=="string" and ENV.AE_PORTRAIT_TEST_TARGET~="" then TARGET=ENV.AE_PORTRAIT_TEST_TARGET end

local old=PG:FindFirstChild("AE_Portrait_Candidate_Tester_V1")
if old then old:Destroy() end

local gui=Instance.new("ScreenGui")
gui.Name="AE_Portrait_Candidate_Tester_V1"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.Parent=PG

local main=Instance.new("Frame")
main.Size=UDim2.fromOffset(860,620)
main.Position=UDim2.fromScale(0.5,0.5)
main.AnchorPoint=Vector2.new(0.5,0.5)
main.BackgroundColor3=Color3.fromRGB(14,18,28)
main.BorderSizePixel=0
main.Parent=gui
Instance.new("UICorner",main).CornerRadius=UDim.new(0,14)

local function text(parent,txt,pos,size,ts,bold)
    local x=Instance.new("TextLabel")
    x.BackgroundTransparency=1;x.Position=pos;x.Size=size;x.Text=txt
    x.TextColor3=Color3.fromRGB(235,239,248);x.TextSize=ts or 14
    x.Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham
    x.TextXAlignment=Enum.TextXAlignment.Left;x.TextWrapped=true;x.Parent=parent
    return x
end
text(main,"PORTRAIT CANDIDATE TESTER",UDim2.fromOffset(18,12),UDim2.fromOffset(500,28),18,true)
local status=text(main,"Target: "..TARGET,UDim2.fromOffset(18,42),UDim2.fromOffset(760,24),12,false)

local close=Instance.new("TextButton")
close.Size=UDim2.fromOffset(40,34);close.Position=UDim2.new(1,-50,0,10);close.Text="×"
close.TextColor3=Color3.new(1,1,1);close.TextSize=20;close.Font=Enum.Font.GothamBold
close.BackgroundColor3=Color3.fromRGB(43,50,70);close.BorderSizePixel=0;close.Parent=main
Instance.new("UICorner",close).CornerRadius=UDim.new(0,9)
close.MouseButton1Click:Connect(function()gui:Destroy()end)

local scroll=Instance.new("ScrollingFrame")
scroll.Position=UDim2.fromOffset(16,78);scroll.Size=UDim2.new(1,-32,1,-94)
scroll.BackgroundTransparency=1;scroll.BorderSizePixel=0;scroll.ScrollBarThickness=7
scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y;scroll.CanvasSize=UDim2.fromOffset(0,0);scroll.Parent=main
local grid=Instance.new("UIGridLayout")
grid.CellSize=UDim2.fromOffset(194,238);grid.CellPadding=UDim2.fromOffset(10,10);grid.Parent=scroll

local function norm(s)return tostring(s or ""):lower():gsub("[%s%p_]","") end
local wanted=norm(TARGET)
local matches={}
for _,d in ipairs(PG:GetDescendants()) do
    if (d:IsA("TextLabel") or d:IsA("TextButton")) and norm(d.Text)==wanted then matches[#matches+1]=d end
end

local candidateMap={}
local candidates={}
local function addCandidate(img,depth,sourceText)
    if candidateMap[img] then return end
    candidateMap[img]=true
    local sx,sy=img.AbsoluteSize.X,img.AbsoluteSize.Y
    local area=sx*sy
    local name=img.Name:lower()
    local penalty=0
    for _,bad in ipairs({"star","lock","border","rarity","trait","element","icon","badge","level","gradient","frame"}) do if name:find(bad,1,true) then penalty+=50000 end end
    local score=area-depth*1500-penalty
    candidates[#candidates+1]={Image=img,Depth=depth,Score=score,SourceText=sourceText}
end

for _,match in ipairs(matches) do
    local node=match.Parent
    for depth=1,8 do
        if not node then break end
        for _,d in ipairs(node:GetDescendants()) do
            if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and d.Image~="" then addCandidate(d,depth,match:GetFullName()) end
        end
        node=node.Parent
    end
end

table.sort(candidates,function(a,b)return a.Score>b.Score end)
status.Text=string.format("Target: %s  •  exact text matches %d  •  image candidates %d",TARGET,#matches,#candidates)

local function shortPath(inst)
    local p=inst:GetFullName();if #p>86 then p="..."..p:sub(-83) end;return p
end

for i,c in ipairs(candidates) do
    local img=c.Image
    local card=Instance.new("Frame")
    card.BackgroundColor3=Color3.fromRGB(25,31,45);card.BorderSizePixel=0;card.Parent=scroll
    Instance.new("UICorner",card).CornerRadius=UDim.new(0,12)

    text(card,"#"..i.."  "..img.Name,UDim2.fromOffset(8,6),UDim2.new(1,-16,0,20),11,true)
    local preview=Instance.new("ImageLabel")
    preview.Position=UDim2.fromOffset(8,30);preview.Size=UDim2.new(1,-16,0,132)
    preview.BackgroundColor3=Color3.fromRGB(11,14,22);preview.BorderSizePixel=0
    preview.Image=img.Image;preview.ImageRectOffset=img.ImageRectOffset;preview.ImageRectSize=img.ImageRectSize
    preview.ScaleType=Enum.ScaleType.Fit;preview.ImageColor3=Color3.new(1,1,1);preview.ImageTransparency=0;preview.Parent=card
    Instance.new("UICorner",preview).CornerRadius=UDim.new(0,8)

    local meta=string.format("size %.0fx%.0f\nscore %.0f\n%s",img.AbsoluteSize.X,img.AbsoluteSize.Y,c.Score,shortPath(img))
    text(card,meta,UDim2.fromOffset(8,168),UDim2.new(1,-16,0,62),9,false)
end

if #candidates==0 then
    text(scroll,"No candidates found. Open Unit Manager/Unit Inventory so the card for '"..TARGET.."' is visible, then rerun this tester.",UDim2.fromOffset(20,20),UDim2.new(1,-40,0,90),14,true)
end

ENV.AE_PORTRAIT_TESTER={Target=TARGET,Matches=matches,Candidates=candidates,Gui=gui}
print("[Portrait Candidate Tester V1] target",TARGET,"matches",#matches,"candidates",#candidates)
