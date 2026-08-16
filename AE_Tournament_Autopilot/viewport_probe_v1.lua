-- AE Tournament Autopilot | Viewport Probe V1
-- Read-only UI inspection. No remotes fired.
local Players=game:GetService("Players")
local HttpService=game:GetService("HttpService")
local LP=Players.LocalPlayer
local PG=LP:WaitForChild("PlayerGui")
local function norm(s)return tostring(s or ""):lower():gsub("[^%w]","") end
local function collectText(node)
 local out={};local seen={}
 local cur=node
 for depth=1,4 do
  cur=cur and cur.Parent
  if not cur then break end
  for _,d in ipairs(cur:GetDescendants()) do
   if d:IsA("TextLabel") or d:IsA("TextButton") then
    local t=tostring(d.Text or "");if t~="" and #t<100 and not seen[t] then seen[t]=true;out[#out+1]=t end
    if #out>=24 then break end
   end
  end
  if #out>=24 then break end
 end
 return out
end
local rows={}
for _,v in ipairs(PG:GetDescendants()) do
 if v:IsA("ViewportFrame") then
  local world=v:FindFirstChildWhichIsA("WorldModel")
  local camera=v.CurrentCamera or v:FindFirstChildWhichIsA("Camera",true)
  local models={}
  if world then
   for _,d in ipairs(world:GetDescendants()) do
    if d:IsA("Model") then models[#models+1]=d.Name end
    if #models>=12 then break end
   end
  end
  local showed={}
  local cur=v.Parent
  for depth=1,5 do
   if not cur then break end
   for _,d in ipairs(cur:GetDescendants()) do if d:IsA("StringValue") and d.Name=="ShowedModel" then showed[#showed+1]=d.Value end end
   cur=cur.Parent
  end
  if world or camera or #showed>0 then
   rows[#rows+1]={Path=v:GetFullName(),Visible=v.Visible,AbsSize={v.AbsoluteSize.X,v.AbsoluteSize.Y},CurrentCamera=v.CurrentCamera and v.CurrentCamera:GetFullName() or nil,FOV=camera and camera.FieldOfView or nil,Models=models,ShowedModel=showed,NearbyText=collectText(v)}
  end
 end
end
local report={Version="viewport-probe-v1",PlaceId=game.PlaceId,Count=#rows,Viewports=rows}
if type(makefolder)=="function" then pcall(makefolder,"AE_Tournament_Autopilot") end
local json=HttpService:JSONEncode(report)
if type(writefile)=="function" then writefile("AE_Tournament_Autopilot/viewport_probe_v1_latest.json",json) end
print("[Viewport Probe V1]",#rows,"rendered viewport candidates saved")
for i=1,math.min(#rows,12) do local r=rows[i];print(i,table.concat(r.NearbyText," | "),"MODELS:",table.concat(r.Models,","),"SHOW:",table.concat(r.ShowedModel,","),"FOV:",r.FOV) end
