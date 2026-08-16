--[[ AE Tournament Autopilot | Replica Identity Probe V4
Read-only. Captures only incoming Replica events. No server calls. ]]
local VERSION="replica-probe-v4.0"
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local HS=game:GetService("HttpService")
local LP=Players.LocalPlayer
local ENV=getgenv and getgenv() or _G
if type(ENV.AE_REPLICA_PROBE_V4)=="table" and type(ENV.AE_REPLICA_PROBE_V4.Destroy)=="function" then pcall(function() ENV.AE_REPLICA_PROBE_V4:Destroy() end) end
local P={Connections={},CaptureConnections={},Events={},ReplicaIds={},UnitPaths={},SetValues={},Creates={},Destroyed=false}
ENV.AE_REPLICA_PROBE_V4=P
local function norm(v)return tostring(v or ""):lower():gsub("[^%w]","")end
local function mask(v)local s=tostring(v or "");if #s>26 then return s:sub(1,10).."…"..s:sub(-6) end return s end
local function pathText(p) if type(p)~="table" then return tostring(p) end local a={} for i=1,math.min(14,#p) do a[#a+1]=tostring(p[i]) end return table.concat(a,".") end
local function preview(v,d) d=d or 0;if d>2 then return "<depth>" end;local t=typeof(v);if t=="nil" then return "nil" elseif t=="string" or t=="number" or t=="boolean" then return tostring(v) elseif t~="table" then return t end;local a,n={},0;for k,x in pairs(v) do n+=1;if n>12 then a[#a+1]="…" break end;a[#a+1]=tostring(k).."="..preview(x,d+1) end;return "{"..table.concat(a,",").."}" end
local function safe(v,d,seen) d=d or 0;seen=seen or {};if d>5 then return "<MAX>" end;local t=typeof(v);if t=="nil" or t=="string" or t=="number" or t=="boolean" then return v elseif t=="Vector3" then return {__type="Vector3",x=v.X,y=v.Y,z=v.Z} elseif t~="table" then return tostring(t) end;if seen[v] then return "<CYCLE>" end;seen[v]=true;local o,n={},0;for k,x in pairs(v) do n+=1;if n>100 then o["<TRUNCATED>"]=true break end;o[tostring(k)]=safe(x,d+1,seen) end;seen[v]=nil;return o end
local pg=LP:WaitForChild("PlayerGui");local old=pg:FindFirstChild("AE_ReplicaProbe_V4");if old then old:Destroy() end
local gui=Instance.new("ScreenGui");gui.Name="AE_ReplicaProbe_V4";gui.ResetOnSpawn=false;gui.DisplayOrder=100300;gui.Parent=pg
local main=Instance.new("Frame");main.Size=UDim2.fromOffset(680,410);main.Position=UDim2.new(.5,-340,.5,-205);main.BackgroundColor3=Color3.fromRGB(14,17,24);main.BorderSizePixel=0;main.Parent=gui;Instance.new("UICorner",main).CornerRadius=UDim.new(0,14)
local title=Instance.new("TextLabel");title.BackgroundTransparency=1;title.Position=UDim2.fromOffset(18,12);title.Size=UDim2.new(1,-70,0,28);title.Text="REPLICA IDENTITY PROBE V4";title.Font=Enum.Font.GothamBold;title.TextSize=17;title.TextColor3=Color3.new(1,1,1);title.TextXAlignment=Enum.TextXAlignment.Left;title.Parent=main
local close=Instance.new("TextButton");close.Position=UDim2.new(1,-49,0,11);close.Size=UDim2.fromOffset(35,32);close.Text="×";close.Font=Enum.Font.GothamBold;close.TextSize=18;close.TextColor3=Color3.new(1,1,1);close.BackgroundColor3=Color3.fromRGB(45,52,71);close.BorderSizePixel=0;close.Parent=main;Instance.new("UICorner",close).CornerRadius=UDim.new(0,9)
local status=Instance.new("TextLabel");status.Position=UDim2.fromOffset(18,55);status.Size=UDim2.new(1,-36,0,55);status.BackgroundColor3=Color3.fromRGB(23,28,39);status.BorderSizePixel=0;status.Text="READY — no GC scan. Capture incoming Replica traffic only.";status.Font=Enum.Font.Gotham;status.TextSize=11;status.TextColor3=Color3.fromRGB(205,214,232);status.TextWrapped=true;status.TextXAlignment=Enum.TextXAlignment.Left;status.Parent=main;Instance.new("UICorner",status).CornerRadius=UDim.new(0,10);local pad=Instance.new("UIPadding",status);pad.PaddingLeft=UDim.new(0,12);pad.PaddingRight=UDim.new(0,12)
local out=Instance.new("TextLabel");out.Position=UDim2.fromOffset(18,123);out.Size=UDim2.new(1,-36,1,-200);out.BackgroundColor3=Color3.fromRGB(18,22,31);out.BorderSizePixel=0;out.Text="We already know UnitData.<GUID> paths exist.\nV4 records the FIRST argument (replica id) beside those paths, plus ReplicaCreate/SetValues payload shapes.";out.Font=Enum.Font.Code;out.TextSize=11;out.TextColor3=Color3.fromRGB(224,228,238);out.TextXAlignment=Enum.TextXAlignment.Left;out.TextYAlignment=Enum.TextYAlignment.Top;out.TextWrapped=true;out.Parent=main;Instance.new("UICorner",out).CornerRadius=UDim.new(0,10);local op=Instance.new("UIPadding",out);op.PaddingLeft=UDim.new(0,12);op.PaddingTop=UDim.new(0,10)
local function setStatus(s)status.Text=tostring(s)end
local captureBtn,saveBtn
local function button(text,x,w,cb)local b=Instance.new("TextButton");b.Position=UDim2.new(x,8,1,-60);b.Size=UDim2.new(w,-12,0,42);b.Text=text;b.Font=Enum.Font.GothamBold;b.TextSize=11;b.TextColor3=Color3.new(1,1,1);b.BackgroundColor3=Color3.fromRGB(67,84,139);b.BorderSizePixel=0;b.Parent=main;Instance.new("UICorner",b).CornerRadius=UDim.new(0,10);P.Connections[#P.Connections+1]=b.MouseButton1Click:Connect(cb);return b end
local function refresh()
 local ids,unitEvents,setvals,creates=0,#P.UnitPaths,#P.SetValues,#P.Creates;for _ in pairs(P.ReplicaIds) do ids+=1 end
 local lines={"events: "..#P.Events,"distinct replica IDs: "..ids,"UnitData path events: "..unitEvents,"ReplicaSetValues samples: "..setvals,"ReplicaCreate samples: "..creates,""}
 local shown=0;for id,info in pairs(P.ReplicaIds) do if info.UnitPaths and #info.UnitPaths>0 then shown+=1;lines[#lines+1]="UNIT PROFILE REPLICA? "..mask(id).." | unit paths="..#info.UnitPaths.." | yen="..tostring(info.Yen).." | wave="..tostring(info.Wave);if shown>=5 then break end end end
 if shown==0 then lines[#lines+1]="No replica ID tied to UnitData yet. Keep capture running while Unit Manager is open." end
 out.Text=table.concat(lines,"\n")
end
local function record(remote,...)
 local args=table.pack(...);local name=norm(remote.Name);local id=tostring(args[1] or "");local p=pathText(args[2]);local e={Remote=remote:GetFullName(),ReplicaId=mask(id),Argc=args.n,Types={},Path=p}
 for i=1,math.min(args.n,5) do e.Types[i]=typeof(args[i]) end
 local info=P.ReplicaIds[id] or {Count=0,UnitPaths={}};P.ReplicaIds[id]=info;info.Count+=1
 if name=="replicaset" or name=="replicasetvalues" then
  e.Value=preview(args[3]);local np=norm(p)
  if np:find("unitdata",1,true) then info.UnitPaths[#info.UnitPaths+1]=p;P.UnitPaths[#P.UnitPaths+1]={ReplicaId=mask(id),Path=p,Value=preview(args[3])} end
  if np=="yen" then info.Yen=preview(args[3]) end;if np=="wave" then info.Wave=preview(args[3]) end
  if name=="replicasetvalues" and #P.SetValues<60 then P.SetValues[#P.SetValues+1]={ReplicaId=mask(id),Path=p,Value=preview(args[3])} end
 elseif name=="replicacreate" then if #P.Creates<40 then P.Creates[#P.Creates+1]={ReplicaId=mask(id),Arg1=preview(args[1]),Arg2=preview(args[2])} end end
 if #P.Events<600 then P.Events[#P.Events+1]=e end
 if #P.Events%60==0 then refresh() end
end
function P:Capture(seconds)
 seconds=tonumber(seconds) or 20;for _,c in ipairs(self.CaptureConnections) do pcall(function()c:Disconnect()end) end;self.CaptureConnections={};self.Events={};self.ReplicaIds={};self.UnitPaths={};self.SetValues={};self.Creates={}
 for _,root in ipairs({RS:FindFirstChild("RemoteEvents"),RS:FindFirstChild("Nodes")}) do if root then for _,r in ipairs(root:GetDescendants()) do if r:IsA("RemoteEvent") then local n=norm(r.Name);if n:find("replica",1,true) or n:find("updatenode",1,true) then self.CaptureConnections[#self.CaptureConnections+1]=r.OnClientEvent:Connect(function(...)local a=table.pack(...);task.defer(function()record(r,table.unpack(a,1,a.n))end)end) end end end end end
 captureBtn.Text="CAPTURING…";setStatus("Capture "..seconds.."s: keep Unit Manager open, scroll, swap one hotbar slot, and let one wave tick.")
 task.delay(seconds,function()if self.Destroyed then return end;for _,c in ipairs(self.CaptureConnections) do pcall(function()c:Disconnect()end) end;self.CaptureConnections={};captureBtn.Text="CAPTURE 20s";refresh();setStatus("Capture complete. SAVE REPORT and send it back.")end)
end
function P:Save()
 if type(writefile)~="function" then setStatus("writefile unavailable")return end;if type(makefolder)=="function" then pcall(makefolder,"AE_Tournament_Autopilot")end
 local report={Version=VERSION,PlaceId=game.PlaceId,Events=self.Events,UnitPaths=self.UnitPaths,SetValues=self.SetValues,Creates=self.Creates,ReplicaIds={}}
 for id,info in pairs(self.ReplicaIds) do report.ReplicaIds[mask(id)]={Count=info.Count,UnitPathCount=#info.UnitPaths,Yen=info.Yen,Wave=info.Wave} end
 local ok,j=pcall(function()return HS:JSONEncode(safe(report))end);if not ok then setStatus("encode failed: "..tostring(j))return end;local path="AE_Tournament_Autopilot/replica_probe_v4_latest.json";local w,err=pcall(writefile,path,j);setStatus(w and ("Saved "..path) or ("save failed: "..tostring(err)))
end
captureBtn=button("CAPTURE 20s",0,.5,function()P:Capture(20)end);saveBtn=button("SAVE REPORT",.5,.5,function()P:Save()end)
P.Connections[#P.Connections+1]=close.MouseButton1Click:Connect(function()P:Destroy()end)
function P:Destroy()if self.Destroyed then return end;self.Destroyed=true;for _,c in ipairs(self.Connections)do pcall(function()c:Disconnect()end)end;for _,c in ipairs(self.CaptureConnections)do pcall(function()c:Disconnect()end)end;if gui then gui:Destroy()end;if ENV.AE_REPLICA_PROBE_V4==self then ENV.AE_REPLICA_PROBE_V4=nil end end
print("[AE Replica Identity Probe V4] READY")
