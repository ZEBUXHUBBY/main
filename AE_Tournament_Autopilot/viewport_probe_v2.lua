-- AE Tournament Autopilot | Viewport Probe V2
-- Read-only UI introspection. Focused on UnitView/Unit Manager renderer inputs.
local Players=game:GetService("Players")
local HttpService=game:GetService("HttpService")
local LP=Players.LocalPlayer
local PG=LP:WaitForChild("PlayerGui")
local OUT={Version="viewport-probe-v2",PlaceId=game.PlaceId,Roots={},Cards={},Viewports={},Values={},Modules={}}

local function safeName(x)local ok,v=pcall(function()return x:GetFullName()end);return ok and v or tostring(x) end
local function attrs(x)local ok,a=pcall(function()return x:GetAttributes()end);return ok and a or {} end
local function textOf(x)
    if x:IsA("TextLabel") or x:IsA("TextButton") or x:IsA("TextBox") then return tostring(x.Text or "") end
    return nil
end
local function serializeValue(v)
    local t=typeof(v)
    if t=="Instance" then return safeName(v) end
    if t=="CFrame" then local p=v.Position;return {__type="CFrame",x=p.X,y=p.Y,z=p.Z} end
    if t=="Vector3" then return {__type="Vector3",x=v.X,y=v.Y,z=v.Z} end
    if t=="Color3" then return {__type="Color3",r=v.R,g=v.G,b=v.B} end
    if t=="string" or t=="number" or t=="boolean" or t=="nil" then return v end
    return tostring(v)
end

local interestingRoots={}
for _,d in ipairs(PG:GetDescendants()) do
    local n=d.Name:lower()
    if n:find("unitview",1,true) or n:find("unitmanager",1,true) or n:find("inventory",1,true) or n:find("units",1,true) then
        if d:IsA("GuiObject") or d:IsA("ScreenGui") or d:IsA("Folder") then interestingRoots[#interestingRoots+1]=d end
    end
end
local rootSeen={}
for _,r in ipairs(interestingRoots) do
    local top=r
    for _=1,4 do if top.Parent and top.Parent~=PG then top=top.Parent else break end end
    if not rootSeen[top] then rootSeen[top]=true;OUT.Roots[#OUT.Roots+1]={Path=safeName(top),Class=top.ClassName,Visible=(top:IsA("GuiObject") and top.Visible or nil),Attributes=attrs(top)} end
end

-- collect every value/object/module around UnitView, even if currently hidden
for _,d in ipairs(PG:GetDescendants()) do
    local path=safeName(d)
    local lower=path:lower()
    local inScope=lower:find("unitview",1,true) or lower:find("unitmanager",1,true) or lower:find("inventory",1,true)
    if inScope then
        if d:IsA("ObjectValue") or d:IsA("StringValue") or d:IsA("IntValue") or d:IsA("NumberValue") or d:IsA("BoolValue") then
            OUT.Values[#OUT.Values+1]={Path=path,Class=d.ClassName,Name=d.Name,Value=serializeValue(d.Value),Attributes=attrs(d)}
        elseif d:IsA("ModuleScript") then
            OUT.Modules[#OUT.Modules+1]={Path=path,Name=d.Name,Attributes=attrs(d)}
        elseif d:IsA("ViewportFrame") then
            local models={}
            local world=d:FindFirstChildWhichIsA("WorldModel")
            if world then for _,m in ipairs(world:GetDescendants()) do if m:IsA("Model") then models[#models+1]=m.Name end end end
            local cam=d.CurrentCamera or d:FindFirstChildWhichIsA("Camera",true)
            local texts={};local node=d
            for _=1,5 do node=node.Parent;if not node then break end;for _,x in ipairs(node:GetChildren()) do local tx=textOf(x);if tx and tx~="" then texts[#texts+1]=tx end end end
            OUT.Viewports[#OUT.Viewports+1]={Path=path,Visible=d.Visible,AbsSize={d.AbsoluteSize.X,d.AbsoluteSize.Y},Models=models,CurrentCamera=cam and cam.Name or nil,FOV=cam and cam.FieldOfView or nil,NearbyText=texts,Attributes=attrs(d)}
        end
    end
end

-- identify likely cards: GuiObjects that contain both meaningful text and viewport/value inputs.
for _,g in ipairs(PG:GetDescendants()) do
    if g:IsA("GuiObject") then
        local path=safeName(g);local lower=path:lower()
        if lower:find("unitview",1,true) or lower:find("unitmanager",1,true) or lower:find("inventory",1,true) then
            local texts,values,viewports={}, {}, 0
            for _,d in ipairs(g:GetDescendants()) do
                local tx=textOf(d);if tx and tx~="" and #tx<=100 then texts[#texts+1]=tx end
                if d:IsA("ObjectValue") or d:IsA("StringValue") then values[#values+1]={Name=d.Name,Class=d.ClassName,Value=serializeValue(d.Value)} end
                if d:IsA("ViewportFrame") then viewports+=1 end
                if #texts>12 or #values>10 then break end
            end
            if #texts>0 and (viewports>0 or #values>0) then
                OUT.Cards[#OUT.Cards+1]={Path=path,Name=g.Name,Class=g.ClassName,Visible=g.Visible,Texts=texts,Values=values,ViewportCount=viewports,Attributes=attrs(g)}
                if #OUT.Cards>=150 then break end
            end
        end
    end
end

local function save()
    if type(writefile)~="function" then warn("[Viewport Probe V2] writefile unavailable");return end
    if type(makefolder)=="function" then pcall(makefolder,"AE_Tournament_Autopilot") end
    local ok,json=pcall(function()return HttpService:JSONEncode(OUT)end)
    if not ok then warn("[Viewport Probe V2] encode failed",json);return end
    writefile("AE_Tournament_Autopilot/viewport_probe_v2_latest.json",json)
    print("[Viewport Probe V2] saved",#OUT.Cards,"cards",#OUT.Viewports,"viewports",#OUT.Values,"values")
end

save()
print("[Viewport Probe V2] Complete. Open Unit Manager FIRST, select one unit, then rerun for best evidence.")
