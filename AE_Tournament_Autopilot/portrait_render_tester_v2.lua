-- AE Tournament Autopilot | Portrait Render Tester V2
-- Standalone, read-only. Tests how this executor can reproduce the game's live UnitView model.
local Players=game:GetService("Players")
local LP=Players.LocalPlayer
local PG=LP:WaitForChild("PlayerGui")

local TARGET="8th Sword (Berserk)"
local old=PG:FindFirstChild("AEPortraitRenderTesterV2") if old then old:Destroy() end

local gui=Instance.new("ScreenGui")
gui.Name="AEPortraitRenderTesterV2";gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=999999;gui.Parent=PG
local main=Instance.new("Frame");main.Size=UDim2.fromOffset(930,520);main.Position=UDim2.new(.5,-465,.5,-260);main.BackgroundColor3=Color3.fromRGB(16,20,30);main.BorderSizePixel=0;main.Parent=gui
Instance.new("UICorner",main).CornerRadius=UDim.new(0,14)
local title=Instance.new("TextLabel");title.BackgroundTransparency=1;title.Position=UDim2.fromOffset(18,10);title.Size=UDim2.new(1,-60,0,28);title.Font=Enum.Font.GothamBold;title.TextSize=18;title.TextColor3=Color3.new(1,1,1);title.TextXAlignment=Enum.TextXAlignment.Left;title.Text="PORTRAIT RENDER TESTER V2";title.Parent=main
local status=Instance.new("TextLabel");status.BackgroundTransparency=1;status.Position=UDim2.fromOffset(18,38);status.Size=UDim2.new(1,-36,0,30);status.Font=Enum.Font.Gotham;status.TextSize=11;status.TextColor3=Color3.fromRGB(170,180,200);status.TextXAlignment=Enum.TextXAlignment.Left;status.Text="Open Unit Manager, select "..TARGET..", then rerun this script.";status.Parent=main
local close=Instance.new("TextButton");close.Size=UDim2.fromOffset(34,30);close.Position=UDim2.new(1,-44,0,10);close.Text="×";close.TextSize=18;close.Font=Enum.Font.GothamBold;close.TextColor3=Color3.new(1,1,1);close.BackgroundColor3=Color3.fromRGB(45,52,72);close.BorderSizePixel=0;close.Parent=main;Instance.new("UICorner",close).CornerRadius=UDim.new(0,8);close.MouseButton1Click:Connect(function()gui:Destroy()end)

local function norm(s)return tostring(s or ""):lower():gsub("[%s%p_]","") end
local function hasTarget(root)
    local w=norm(TARGET)
    for _,d in ipairs(root:GetDescendants()) do if (d:IsA("TextLabel") or d:IsA("TextButton")) and norm(d.Text)==w then return true end end
    return false
end
local unitView=PG:FindFirstChild("UnitView")
local sourceViewport=nil
if unitView and hasTarget(unitView) then
    local best,bestParts=nil,0
    for _,d in ipairs(unitView:GetDescendants()) do
        if d:IsA("ViewportFrame") then
            local world=d:FindFirstChildWhichIsA("WorldModel",true)
            local parts=0
            if world then for _,x in ipairs(world:GetDescendants()) do if x:IsA("BasePart") then parts+=1 end end end
            if parts>bestParts then best,bestParts=d,parts end
        end
    end
    sourceViewport=best
    status.Text="Source found • parts "..tostring(bestParts).." • visible "..tostring(best and best.Visible).." • FOV "..tostring(best and best.CurrentCamera and best.CurrentCamera.FieldOfView or "?")
else
    status.Text="SOURCE NOT FOUND — keep Unit Manager/UnitView on "..TARGET.." and rerun."
end

local methods={"A VIEWPORT CLONE","B WORLDMODEL CLONE","C CHILD CLONE","D MANUAL PART COPY"}
local boxes={}
for i,name in ipairs(methods) do
    local box=Instance.new("Frame");box.Size=UDim2.fromOffset(215,405);box.Position=UDim2.fromOffset(18+(i-1)*226,82);box.BackgroundColor3=Color3.fromRGB(23,29,42);box.BorderSizePixel=0;box.Parent=main;Instance.new("UICorner",box).CornerRadius=UDim.new(0,12)
    local h=Instance.new("TextLabel");h.BackgroundTransparency=1;h.Position=UDim2.fromOffset(10,8);h.Size=UDim2.new(1,-20,0,22);h.Font=Enum.Font.GothamBold;h.TextSize=12;h.TextColor3=Color3.new(1,1,1);h.TextXAlignment=Enum.TextXAlignment.Left;h.Text=name;h.Parent=box
    local viewHolder=Instance.new("Frame");viewHolder.Position=UDim2.fromOffset(10,38);viewHolder.Size=UDim2.new(1,-20,0,250);viewHolder.BackgroundColor3=Color3.fromRGB(12,16,24);viewHolder.BorderSizePixel=0;viewHolder.ClipsDescendants=true;viewHolder.Parent=box;Instance.new("UICorner",viewHolder).CornerRadius=UDim.new(0,10)
    local info=Instance.new("TextLabel");info.BackgroundTransparency=1;info.Position=UDim2.fromOffset(10,300);info.Size=UDim2.new(1,-20,0,95);info.Font=Enum.Font.Code;info.TextSize=10;info.TextColor3=Color3.fromRGB(180,190,210);info.TextWrapped=true;info.TextXAlignment=Enum.TextXAlignment.Left;info.TextYAlignment=Enum.TextYAlignment.Top;info.Text="waiting";info.Parent=box
    boxes[i]={holder=viewHolder,info=info}
end

local function arch(root,v,backup)
    backup=backup or {}
    local function one(x)local ok,o=pcall(function()return x.Archivable end);if ok then backup[x]=o;pcall(function()x.Archivable=v end)end end
    one(root);for _,d in ipairs(root:GetDescendants()) do one(d) end;return backup
end
local function restore(b)for x,v in pairs(b or {}) do pcall(function()x.Archivable=v end) end end
local function makeViewport(holder,sourceCam)
    local v=Instance.new("ViewportFrame");v.Size=UDim2.fromScale(1,1);v.BackgroundTransparency=1;v.BorderSizePixel=0;v.Ambient=Color3.fromRGB(200,200,210);v.LightColor=Color3.fromRGB(255,245,235);v.LightDirection=Vector3.new(-1,-1,-1);v.Parent=holder
    local c=Instance.new("Camera");c.FieldOfView=sourceCam and sourceCam.FieldOfView or 32;c.Parent=v;v.CurrentCamera=c
    return v,c
end
local function bounds(world)
    local mn=Vector3.new(math.huge,math.huge,math.huge);local mx=Vector3.new(-math.huge,-math.huge,-math.huge);local n=0
    for _,p in ipairs(world:GetDescendants()) do if p:IsA("BasePart") and p.Transparency<.99 then local cf,sz=p.CFrame,p.Size;for x=-1,1,2 do for y=-1,1,2 do for z=-1,1,2 do local q=cf:PointToWorldSpace(Vector3.new(sz.X*x/2,sz.Y*y/2,sz.Z*z/2));mn=Vector3.new(math.min(mn.X,q.X),math.min(mn.Y,q.Y),math.min(mn.Z,q.Z));mx=Vector3.new(math.max(mx.X,q.X),math.max(mx.Y,q.Y),math.max(mx.Z,q.Z)) end end end;n+=1 end end
    if n==0 then return nil end;return (mn+mx)/2,mx-mn,n
end
local function fit(v,c,sourceCam)
    local w=v:FindFirstChildWhichIsA("WorldModel",true);local center,size,n=w and bounds(w) or nil
    if not center then return false,0 end
    local look=sourceCam and sourceCam.CFrame.LookVector or Vector3.new(0,0,-1);local f=math.rad(c.FieldOfView*.5);local r=math.max(size.X,size.Y,size.Z,1);local dist=(r*.75)/math.max(.1,math.tan(f))*1.15;c.CFrame=CFrame.lookAt(center-look.Unit*dist,center+Vector3.new(0,size.Y*.04,0));return true,n
end

if sourceViewport then
    local sourceWorld=sourceViewport:FindFirstChildWhichIsA("WorldModel",true);local sourceCam=sourceViewport.CurrentCamera or sourceViewport:FindFirstChildWhichIsA("Camera",true)
    -- A
    do local ok,res=pcall(function()local b=arch(sourceViewport,true);local c=sourceViewport:Clone();restore(b);c.Size=UDim2.fromScale(1,1);c.Position=UDim2.fromScale(0,0);c.BackgroundTransparency=1;c.Visible=true;c.Parent=boxes[1].holder;local cam=c:FindFirstChildWhichIsA("Camera",true);if cam then c.CurrentCamera=cam end;return c end);local parts=0;if ok and res then local w=res:FindFirstChildWhichIsA("WorldModel",true);if w then for _,x in ipairs(w:GetDescendants()) do if x:IsA("BasePart") then parts+=1 end end end end;boxes[1].info.Text="ok="..tostring(ok).."\nparts="..parts.."\nCurrentCamera="..tostring(ok and res and res.CurrentCamera~=nil) end
    -- B
    do local v,c=makeViewport(boxes[2].holder,sourceCam);local ok,w=pcall(function()local b=arch(sourceWorld,true);local x=sourceWorld:Clone();restore(b);return x end);if ok and w then w.Parent=v;local fitted,n=fit(v,c,sourceCam);boxes[2].info.Text="world clone=true\nparts="..n.."\nfit="..tostring(fitted) else boxes[2].info.Text="world clone=false\n"..tostring(w) end end
    -- C
    do local v,c=makeViewport(boxes[3].holder,sourceCam);local w=Instance.new("WorldModel");w.Parent=v;local count=0;for _,child in ipairs(sourceWorld:GetChildren()) do local ok,x=pcall(function()local b=arch(child,true);local cc=child:Clone();restore(b);return cc end);if ok and x then x.Parent=w;count+=1 end end;local fitted,n=fit(v,c,sourceCam);boxes[3].info.Text="children cloned="..count.."\nparts="..n.."\nfit="..tostring(fitted) end
    -- D manual individual part snapshot
    do local v,c=makeViewport(boxes[4].holder,sourceCam);local w=Instance.new("WorldModel");w.Parent=v;local count=0;for _,p in ipairs(sourceWorld:GetDescendants()) do if p:IsA("MeshPart") or p:IsA("Part") or p:IsA("UnionOperation") then local ok,x=pcall(function()local b=arch(p,true);local cc=p:Clone();restore(b);return cc end);if ok and x then x.Anchored=true;x.CanCollide=false;x.Parent=w;count+=1 end end end;local fitted,n=fit(v,c,sourceCam);boxes[4].info.Text="parts copied="..count.."\nrender parts="..n.."\nfit="..tostring(fitted) end
end
