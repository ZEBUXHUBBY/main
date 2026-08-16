-- Beeconomy Runtime Diagnostic Probe (Rayfield)
-- Read-only discovery helper. Dumps client hierarchy and interaction surfaces.
local Players=game:GetService("Players")
local HttpService=game:GetService("HttpService")
local LP=Players.LocalPlayer
local OUT={generatedAt=os.time(),placeId=game.PlaceId,game=game.Name,playerScripts={},moduleScripts={},guiButtons={},prompts={},clickDetectors={},attributes={},gcHints={}}

local function safe(v,d)
 d=d or 0
 if d>3 then return "<deep>" end
 local t=typeof(v)
 if t=="Vector3" then return {__type="Vector3",x=v.X,y=v.Y,z=v.Z} end
 if t=="CFrame" then return {__type="CFrame",components={v:GetComponents()}} end
 if t=="Instance" then return {__type="Instance",class=v.ClassName,path=v:GetFullName()} end
 if t=="table" then local o,n={},0;for k,x in pairs(v) do n+=1;if n>40 then o.__truncated=true;break end;o[tostring(k)]=safe(x,d+1) end;return o end
 if t=="string" or t=="number" or t=="boolean" or t=="nil" then return v end
 return tostring(v)
end

local function attrs(inst)
 local ok,a=pcall(inst.GetAttributes,inst)
 return ok and safe(a) or {}
end

local ps=LP:FindFirstChild("PlayerScripts")
if ps then
 for _,d in ipairs(ps:GetDescendants()) do
  if d:IsA("ModuleScript") or d:IsA("LocalScript") or d:IsA("Folder") then
   table.insert(OUT.playerScripts,{class=d.ClassName,name=d.Name,path=d:GetFullName(),attributes=attrs(d)})
  end
  if d:IsA("ModuleScript") then table.insert(OUT.moduleScripts,{name=d.Name,path=d:GetFullName(),attributes=attrs(d)}) end
 end
end

for _,d in ipairs(LP.PlayerGui:GetDescendants()) do
 if d:IsA("TextButton") or d:IsA("ImageButton") then
  table.insert(OUT.guiButtons,{class=d.ClassName,name=d.Name,path=d:GetFullName(),text=d:IsA("TextButton") and d.Text or nil,visible=d.Visible,active=d.Active,attributes=attrs(d)})
 end
end

for _,d in ipairs(workspace:GetDescendants()) do
 if d:IsA("ProximityPrompt") then
  table.insert(OUT.prompts,{name=d.Name,path=d:GetFullName(),actionText=d.ActionText,objectText=d.ObjectText,enabled=d.Enabled,holdDuration=d.HoldDuration,maxDistance=d.MaxActivationDistance,parent=d.Parent and d.Parent:GetFullName() or nil,attributes=attrs(d)})
 elseif d:IsA("ClickDetector") then
  table.insert(OUT.clickDetectors,{name=d.Name,path=d:GetFullName(),maxDistance=d.MaxActivationDistance,parent=d.Parent and d.Parent:GetFullName() or nil,attributes=attrs(d)})
 end
end

OUT.attributes.player=safe(LP:GetAttributes())

if getgc and debug and debug.getinfo then
 local ok,list=pcall(getgc,true)
 if ok then
  for _,obj in ipairs(list) do
   if type(obj)=="function" then
    local iok,info=pcall(debug.getinfo,obj)
    if iok and info then
     local src=tostring(info.source or "")
     local name=tostring(info.name or "")
     local hay=(src.." "..name):lower()
     if hay:find("network",1,true) or hay:find("fishing",1,true) or hay:find("shovel",1,true) or hay:find("pickaxe",1,true) or hay:find("axe",1,true) or hay:find("quest",1,true) or hay:find("hatch",1,true) then
      table.insert(OUT.gcHints,{name=name,source=src,linedefined=info.linedefined,lastlinedefined=info.lastlinedefined,what=info.what})
      if #OUT.gcHints>=120 then break end
     end
    end
   end
  end
 end
end

local function export()
 local json=HttpService:JSONEncode(OUT)
 local f="Beeconomy_RuntimeDiagnostic_"..os.time()..".json"
 if writefile then
  local ok,err=pcall(writefile,f,json)
  if ok then print("[BeeDiag] saved",f);return f end
  warn(err)
 end
 print(json)
end

local Rayfield=loadstring(game:HttpGet(((getgenv and getgenv().RayfieldUrl) or "https://sirius.menu/rayfield")))()
local W=Rayfield:CreateWindow({Name="Beeconomy Runtime Diagnostic",LoadingTitle="Beeconomy Diagnostic",LoadingSubtitle="ZEBUXHUBBY",ConfigurationSaving={Enabled=false},KeySystem=false})
local T=W:CreateTab("Diagnostic",4483362458)
T:CreateParagraph({Title="What this does",Content="Read-only scan of PlayerScripts/ClientModules, ModuleScripts, GUI buttons, ProximityPrompts, ClickDetectors, player attributes, and visible getgc function hints. It does not fire game remotes."})
T:CreateButton({Name="Export Diagnostic JSON",Callback=export})
T:CreateButton({Name="Print Counts",Callback=function() print("[BeeDiag] PlayerScripts",#OUT.playerScripts,"Modules",#OUT.moduleScripts,"GUI",#OUT.guiButtons,"Prompts",#OUT.prompts,"Clicks",#OUT.clickDetectors,"GC hints",#OUT.gcHints) end})
Rayfield:Notify({Title="Beeconomy Diagnostic ready",Content="Export the JSON and send it back.",Duration=6})
print("[BeeDiag] loaded",#OUT.playerScripts,#OUT.moduleScripts,#OUT.guiButtons,#OUT.prompts,#OUT.clickDetectors,#OUT.gcHints)
