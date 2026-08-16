-- Beeconomy Automation Controller V1 (Rayfield)
-- Uses normal client interactions/state only. No forged tokens or unknown remote replay.
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local VIM=game:GetService("VirtualInputManager")
local LP=Players.LocalPlayer
local CFG={Farm=false,Tree=false,Rock=false,Fishing=false,Mob=false,Move=true,LoopDelay=.22,InteractDistance=11,Field="Dandelion",Verbose=true}
local STATE={busy=false,lastAction="idle",lastTarget=nil}

local function log(...) if CFG.Verbose then print("[Beeconomy Auto]",...) end end
local function char() return LP.Character end
local function root() local c=char();return c and c:FindFirstChild("HumanoidRootPart") end
local function hum() local c=char();return c and c:FindFirstChildOfClass("Humanoid") end
local function distTo(inst)
 local r=root();if not r or not inst then return math.huge end
 local p
 if inst:IsA("BasePart") then p=inst.Position elseif inst:IsA("Model") then local q=inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart",true);p=q and q.Position end
 return p and (r.Position-p).Magnitude or math.huge
end
local function modelPart(inst)
 if not inst then return nil end
 if inst:IsA("BasePart") then return inst end
 if inst:IsA("Model") then return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart",true) end
 return inst:FindFirstAncestorWhichIsA("Model") and (inst:FindFirstAncestorWhichIsA("Model").PrimaryPart or inst:FindFirstAncestorWhichIsA("Model"):FindFirstChildWhichIsA("BasePart",true)) or inst:FindFirstAncestorWhichIsA("BasePart")
end
local function moveNear(inst,stop)
 if not CFG.Move then return true end
 local h,r=hum(),root();local p=modelPart(inst);if not h or not r or not p then return false end
 stop=stop or CFG.InteractDistance
 if (r.Position-p.Position).Magnitude<=stop then return true end
 h:MoveTo(p.Position)
 local t=os.clock()+4
 repeat task.wait(.08) until not CFG.Move or not root() or distTo(p)<=stop or os.clock()>t
 return distTo(p)<=stop
end
local function pressKey(code)
 if keypress and keyrelease then keypress(code);task.wait(.05);keyrelease(code);return true end
 local kc=Enum.KeyCode[code]
 if kc then VIM:SendKeyEvent(true,kc,false,game);task.wait(.05);VIM:SendKeyEvent(false,kc,false,game);return true end
 return false
end
local function mouseClick()
 if mouse1click then mouse1click();return true end
 local pos=UIS:GetMouseLocation();VIM:SendMouseButtonEvent(pos.X,pos.Y,0,true,game,0);task.wait(.03);VIM:SendMouseButtonEvent(pos.X,pos.Y,0,false,game,0);return true
end
local TOOLKEY={shovel="One",axe="Two",pickaxe="Three",fishing_rod="Four",net="Five"}
local function currentHold() return LP:GetAttribute("GripHoldKind") end
local function equip(kind)
 if currentHold()==kind or (kind=="shovel" and LP:GetAttribute("ShovelEquipped")==true) then return true end
 local k=TOOLKEY[kind];if not k then return false end
 pressKey(k)
 local t=os.clock()+1.25
 repeat task.wait(.05) until currentHold()==kind or (kind=="shovel" and LP:GetAttribute("ShovelEquipped")==true) or os.clock()>t
 return currentHold()==kind or (kind=="shovel" and LP:GetAttribute("ShovelEquipped")==true)
end
local function lname(x)return string.lower(x.Name or "") end
local function containsAny(s,arr) s=string.lower(s);for _,v in ipairs(arr)do if string.find(s,string.lower(v),1,true) then return true end end;return false end
local function nearestByNames(names,classes)
 local best,bd=nil,math.huge
 for _,d in ipairs(workspace:GetDescendants()) do
  local okClass=not classes
  if classes then for _,c in ipairs(classes)do if d:IsA(c) then okClass=true break end end end
  if okClass and containsAny(d.Name,names) then
   local p=modelPart(d);local di=p and distTo(p) or math.huge
   if di<bd then best,bd=d,di end
  end
 end
 return best,bd
end
local function nearestPrompt(names)
 local best,bd=nil,math.huge
 for _,d in ipairs(workspace:GetDescendants())do
  if d:IsA("ProximityPrompt") then
   local parent=d.Parent;local text=(d.ActionText or "").." "..(d.ObjectText or "").." "..(parent and parent.Name or "")
   if not names or containsAny(text,names) then local di=distTo(parent);if di<bd then best,bd=d,di end end
  end
 end
 return best,bd
end
local function nearestClick(names)
 local best,bd=nil,math.huge
 for _,d in ipairs(workspace:GetDescendants())do
  if d:IsA("ClickDetector") then local parent=d.Parent;local text=(parent and parent.Name or "").." "..(parent and parent.Parent and parent.Parent.Name or "");if not names or containsAny(text,names) then local di=distTo(parent);if di<bd then best,bd=d,di end end end
 end
 return best,bd
end
local function interact(inst)
 if not inst then return false end
 if inst:IsA("ProximityPrompt") then
  moveNear(inst.Parent,math.max(3,(inst.MaxActivationDistance or 10)-1))
  if fireproximityprompt then pcall(fireproximityprompt,inst);return true end
  local key=inst.KeyboardKeyCode;if key and key~=Enum.KeyCode.Unknown then VIM:SendKeyEvent(true,key,false,game);task.wait(math.max(.05,inst.HoldDuration or 0));VIM:SendKeyEvent(false,key,false,game);return true end
 elseif inst:IsA("ClickDetector") then
  moveNear(inst.Parent,math.max(3,(inst.MaxActivationDistance or 10)-1))
  if fireclickdetector then pcall(fireclickdetector,inst);return true end
 end
 moveNear(inst,CFG.InteractDistance);return mouseClick()
end
local function fieldTarget()
 local names={CFG.Field,"field","flower","pollen"};return nearestByNames(names,{"BasePart","Model"})
end
local function doFarm()
 if not equip("shovel") then return false,"equip shovel failed" end
 local t=fieldTarget();if t then moveNear(t,8) end
 mouseClick();return true,"farm swing"
end
local function doTree()
 if not equip("axe") then return false,"equip axe failed" end
 local cd=nearestClick({"tree","stump","wood"});if cd then interact(cd);return true,"tree clickdetector" end
 local pp=nearestPrompt({"tree","chop","wood"});if pp then interact(pp);return true,"tree prompt" end
 local t=nearestByNames({"tree","stump"},{"BasePart","Model"});if t then moveNear(t,8);mouseClick();return true,"tree click" end
 return false,"tree target not found"
end
local function doRock()
 if not equip("pickaxe") then return false,"equip pickaxe failed" end
 local cd=nearestClick({"rock","ore","stone"});if cd then interact(cd);return true,"rock clickdetector" end
 local pp=nearestPrompt({"rock","mine","ore","stone"});if pp then interact(pp);return true,"rock prompt" end
 local t=nearestByNames({"rock","ore","stone"},{"BasePart","Model"});if t then moveNear(t,8);mouseClick();return true,"rock click" end
 return false,"rock target not found"
end
local function doFishing()
 if not equip("fishing_rod") then return false,"equip fishing rod failed" end
 local pp=nearestPrompt({"fish","pond","water","cast"});if pp then interact(pp);return true,"fishing prompt" end
 local t=nearestByNames({"fishing","pond","water","lake"},{"BasePart","Model"});if t then moveNear(t,10) end
 mouseClick();return true,"fishing click"
end
local function doMob()
 local id=LP:GetAttribute("SelectedMobId") or LP:GetAttribute("BeeCombatTargetMobId")
 local cd=nearestClick({"ladybug","spider","mob","enemy","beetle","mantis"});if cd then interact(cd);return true,"mob clickdetector" end
 local pp=nearestPrompt({"ladybug","spider","mob","enemy","fight"});if pp then interact(pp);return true,"mob prompt" end
 local t=nearestByNames({"ladybug","spider","mob","enemy","beetle","mantis"},{"BasePart","Model"});if t then moveNear(t,10);mouseClick();return true,"mob click" end
 if id then return true,"mob already selected" end
 return false,"mob target not found"
end
local function step()
 if STATE.busy then return end;STATE.busy=true
 local ok,msg
 if CFG.Farm then ok,msg=doFarm()
 elseif CFG.Tree then ok,msg=doTree()
 elseif CFG.Rock then ok,msg=doRock()
 elseif CFG.Fishing then ok,msg=doFishing()
 elseif CFG.Mob then ok,msg=doMob()
 else STATE.busy=false;return end
 STATE.lastAction=msg or "unknown";log(STATE.lastAction,ok)
 STATE.busy=false
end
task.spawn(function()while task.wait(CFG.LoopDelay)do pcall(step)end end)

local Rayfield=loadstring(game:HttpGet(((getgenv and getgenv().RayfieldUrl)or"https://sirius.menu/rayfield")))()
local W=Rayfield:CreateWindow({Name="Beeconomy Automation V1",LoadingTitle="Beeconomy Automation Controller",LoadingSubtitle="ZEBUXHUBBY",ConfigurationSaving={Enabled=false},KeySystem=false})
local A=W:CreateTab("Automation",4483362458);local S=W:CreateTab("Settings",4483362458);local D=W:CreateTab("Debug",4483362458)
A:CreateToggle({Name="Auto Pollen Farm",CurrentValue=false,Flag="BeeAutoFarm",Callback=function(v)CFG.Farm=v end})
A:CreateToggle({Name="Auto Chop Tree",CurrentValue=false,Flag="BeeAutoTree",Callback=function(v)CFG.Tree=v end})
A:CreateToggle({Name="Auto Mine Rock",CurrentValue=false,Flag="BeeAutoRock",Callback=function(v)CFG.Rock=v end})
A:CreateToggle({Name="Auto Fishing",CurrentValue=false,Flag="BeeAutoFishing",Callback=function(v)CFG.Fishing=v end})
A:CreateToggle({Name="Auto Mob Interact",CurrentValue=false,Flag="BeeAutoMob",Callback=function(v)CFG.Mob=v end})
S:CreateInput({Name="Field Name",CurrentValue=CFG.Field,PlaceholderText="Dandelion",RemoveTextAfterFocusLost=false,Flag="BeeField",Callback=function(v)if v and v~="" then CFG.Field=v end end})
S:CreateSlider({Name="Loop Delay",Range={.12,1},Increment=.02,Suffix="s",CurrentValue=CFG.LoopDelay,Flag="BeeDelay",Callback=function(v)CFG.LoopDelay=v end})
S:CreateToggle({Name="Auto Move To Target",CurrentValue=true,Flag="BeeMove",Callback=function(v)CFG.Move=v end})
S:CreateToggle({Name="Verbose Console",CurrentValue=true,Flag="BeeVerbose",Callback=function(v)CFG.Verbose=v end})
D:CreateButton({Name="Test Farm Once",Callback=function()local ok,msg=doFarm();print("[Bee Test]",ok,msg)end})
D:CreateButton({Name="Test Tree Once",Callback=function()local ok,msg=doTree();print("[Bee Test]",ok,msg)end})
D:CreateButton({Name="Test Rock Once",Callback=function()local ok,msg=doRock();print("[Bee Test]",ok,msg)end})
D:CreateButton({Name="Test Fishing Once",Callback=function()local ok,msg=doFishing();print("[Bee Test]",ok,msg)end})
D:CreateButton({Name="Test Mob Once",Callback=function()local ok,msg=doMob();print("[Bee Test]",ok,msg)end})
D:CreateButton({Name="Print State",Callback=function()print("hold",currentHold(),"shovel",LP:GetAttribute("ShovelEquipped"),"mob",LP:GetAttribute("SelectedMobId"),LP:GetAttribute("BeeCombatTargetMobId"),"field",LP:GetAttribute("BeeCombatTargetFieldDb"),"last",STATE.lastAction)end})
D:CreateParagraph({Title="Controller behavior",Content="Uses tool hotkeys, Humanoid:MoveTo, ProximityPrompt/ClickDetector and normal mouse input. It does not forge fishing tokens or replay unknown remotes. If a target cannot be discovered, the Debug test prints exactly which target is missing."})
Rayfield:Notify({Title="Beeconomy Automation V1",Content="Adaptive normal-interaction controller loaded.",Duration=6})
log("loaded")