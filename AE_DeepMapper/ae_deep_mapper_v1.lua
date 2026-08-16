-- AE Deep Mapper V1 - visible research console
-- Wraps V0 runtime/replica mapper with a simple standalone UI.

local Players=game:GetService("Players")
local HttpService=game:GetService("HttpService")
local UIS=game:GetService("UserInputService")
local LocalPlayer=Players.LocalPlayer
local PlayerGui=LocalPlayer:WaitForChild("PlayerGui")
local ENV=getgenv and getgenv() or _G

local ROOT="https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_DeepMapper/"
local nonce=tostring(os.time()).."-"..tostring(math.random(100000,999999))

-- Clean previous V1 UI only. V0 itself destroys its old mapper instance.
local old=PlayerGui:FindFirstChild("AE_DeepMapper_V1")
if old then old:Destroy() end

local function fetch(path)
    local ok,src=pcall(function()return game:HttpGet(ROOT..path.."?v1="..nonce)end)
    if not ok then return nil,tostring(src) end
    return src
end

local v0src,fetchErr=fetch("ae_deep_mapper_v0.lua")
if not v0src then warn("[AE-DM V1] V0 fetch failed: "..tostring(fetchErr));return end
local chunk,compileErr=loadstring(v0src)
if not chunk then warn("[AE-DM V1] V0 compile failed: "..tostring(compileErr));return end
local okMapper,Mapper=pcall(chunk)
if not okMapper or type(Mapper)~="table" then warn("[AE-DM V1] V0 runtime failed: "..tostring(Mapper));return end
Mapper.Version="AE-DM-V1"

local Gui=Instance.new("ScreenGui")
Gui.Name="AE_DeepMapper_V1"
Gui.ResetOnSpawn=false
Gui.IgnoreGuiInset=true
Gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
Gui.Parent=PlayerGui

local Main=Instance.new("Frame")
Main.Name="Main"
Main.Size=UDim2.fromOffset(620,430)
Main.Position=UDim2.new(0.5,-310,0.5,-215)
Main.BackgroundColor3=Color3.fromRGB(21,23,29)
Main.BorderSizePixel=0
Main.Parent=Gui
Instance.new("UICorner",Main).CornerRadius=UDim.new(0,14)

local Header=Instance.new("Frame")
Header.Size=UDim2.new(1,0,0,54)
Header.BackgroundColor3=Color3.fromRGB(30,33,42)
Header.BorderSizePixel=0
Header.Parent=Main
Instance.new("UICorner",Header).CornerRadius=UDim.new(0,14)

local Title=Instance.new("TextLabel")
Title.BackgroundTransparency=1
Title.Position=UDim2.fromOffset(18,8)
Title.Size=UDim2.new(1,-120,0,22)
Title.Font=Enum.Font.GothamBold
Title.TextSize=16
Title.TextXAlignment=Enum.TextXAlignment.Left
Title.TextColor3=Color3.fromRGB(240,242,250)
Title.Text="AE DEEP MAPPER · V1"
Title.Parent=Header

local Status=Instance.new("TextLabel")
Status.BackgroundTransparency=1
Status.Position=UDim2.fromOffset(18,30)
Status.Size=UDim2.new(1,-120,0,18)
Status.Font=Enum.Font.Gotham
Status.TextSize=11
Status.TextXAlignment=Enum.TextXAlignment.Left
Status.TextColor3=Color3.fromRGB(100,220,160)
Status.Text="LOADED · passive replica capture active"
Status.Parent=Header

local Close=Instance.new("TextButton")
Close.Size=UDim2.fromOffset(34,34)
Close.Position=UDim2.new(1,-44,0,10)
Close.BackgroundColor3=Color3.fromRGB(48,51,62)
Close.TextColor3=Color3.fromRGB(240,240,245)
Close.Font=Enum.Font.GothamBold
Close.TextSize=15
Close.Text="×"
Close.Parent=Header
Instance.new("UICorner",Close).CornerRadius=UDim.new(0,10)

local Left=Instance.new("Frame")
Left.Position=UDim2.fromOffset(14,68)
Left.Size=UDim2.fromOffset(182,348)
Left.BackgroundColor3=Color3.fromRGB(27,29,37)
Left.BorderSizePixel=0
Left.Parent=Main
Instance.new("UICorner",Left).CornerRadius=UDim.new(0,12)

local Right=Instance.new("Frame")
Right.Position=UDim2.fromOffset(208,68)
Right.Size=UDim2.new(1,-222,1,-82)
Right.BackgroundColor3=Color3.fromRGB(17,19,24)
Right.BorderSizePixel=0
Right.Parent=Main
Instance.new("UICorner",Right).CornerRadius=UDim.new(0,12)

local Log=Instance.new("TextLabel")
Log.BackgroundTransparency=1
Log.Position=UDim2.fromOffset(12,10)
Log.Size=UDim2.new(1,-24,1,-20)
Log.Font=Enum.Font.Code
Log.TextSize=12
Log.TextWrapped=false
Log.TextXAlignment=Enum.TextXAlignment.Left
Log.TextYAlignment=Enum.TextYAlignment.Top
Log.TextColor3=Color3.fromRGB(205,211,225)
Log.Text=""
Log.Parent=Right

local logRows={}
local function log(msg)
    local stamp=string.format("%6.2f",os.clock()-Mapper.StartedClock)
    logRows[#logRows+1]="["..stamp.."] "..tostring(msg)
    while #logRows>24 do table.remove(logRows,1) end
    Log.Text=table.concat(logRows,"\n")
    print("[AE-DM V1] "..tostring(msg))
end

local function button(text,y,callback)
    local b=Instance.new("TextButton")
    b.Position=UDim2.fromOffset(10,y)
    b.Size=UDim2.new(1,-20,0,38)
    b.BackgroundColor3=Color3.fromRGB(43,47,60)
    b.TextColor3=Color3.fromRGB(238,240,248)
    b.Font=Enum.Font.GothamBold
    b.TextSize=11
    b.Text=text
    b.AutoButtonColor=true
    b.Parent=Left
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,10)
    b.MouseButton1Click:Connect(callback)
    return b
end

local busy=false
local Scan=button("SCAN CLIENT LOGIC",10,function()
    if busy then return end
    busy=true;Status.Text="SCANNING CLIENT...";Status.TextColor3=Color3.fromRGB(255,196,100)
    task.spawn(function()
        local modules,merr=Mapper:BuildLoadedModuleIndex()
        log("modules: "..tostring(#modules)..(merr and (" · "..merr) or ""))
        local funcs,ferr=Mapper:BuildGCFunctionIndex(30000)
        log("relevant GC functions: "..tostring(#funcs)..(ferr and (" · "..ferr) or ""))
        local domains={}
        for _,row in ipairs(funcs) do for _,d in ipairs(row.domains or {}) do domains[d]=(domains[d] or 0)+1 end end
        local pairsList={};for k,v in pairs(domains) do pairsList[#pairsList+1]={k,v} end
        table.sort(pairsList,function(a,b)return a[2]>b[2] end)
        for i=1,math.min(10,#pairsList) do log("  "..pairsList[i][1].." = "..pairsList[i][2]) end
        busy=false;Status.Text="SCAN COMPLETE";Status.TextColor3=Color3.fromRGB(100,220,160)
    end)
end)

button("RUNTIME SNAPSHOT",56,function()
    local snap=Mapper:SnapshotRuntime()
    local function count(t)local n=0;for _ in pairs(t or {}) do n+=1 end;return n end
    log("runtime units="..count(snap.units).." enemies="..count(snap.enemies).." zones="..count(snap.zones).." buffs="..count(snap.buffs))
    log("events="..#Mapper.Events.." markers="..#Mapper.Markers.." economy="..#Mapper.Economy)
end)

button("MARK NOW",102,function()
    Mapper:Mark("MANUAL_MARK")
    log("manual marker added")
end)

button("EXPORT JSON",148,function()
    local ok,path=Mapper:Save("AE_DeepMapper")
    if ok then log("saved to executor workspace/"..tostring(path)) else log("EXPORT FAILED: "..tostring(path)) end
end)

button("CAPABILITIES",194,function()
    local names={"getgc","getconstants","getloadedmodules","getconnections","getupvalues","getprotos","writefile"}
    for _,n in ipairs(names) do log(n.." = "..tostring(Mapper.Capabilities[n])) end
end)

button("TOP REVERSE HITS",240,function()
    local rows=Mapper.ClientLogic or {}
    if #rows==0 then log("No client index yet. Press SCAN CLIENT LOGIC first.");return end
    local shown=0
    for _,row in ipairs(rows) do
        if shown>=10 then break end
        log(table.concat(row.domains or {},",").." | "..tostring(row.source or row.name or "function"))
        shown+=1
    end
end)

local info=Instance.new("TextLabel")
info.BackgroundTransparency=1
info.Position=UDim2.fromOffset(10,292)
info.Size=UDim2.new(1,-20,0,48)
info.TextWrapped=true
info.Font=Enum.Font.Gotham
info.TextSize=9
info.TextColor3=Color3.fromRGB(145,151,170)
info.Text="Capture is passive. Play normally, then Scan/Export. No remote fuzzing."
info.Parent=Left

-- drag
local dragging=false;local dragStart,startPos
Header.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true;dragStart=input.Position;startPos=Main.Position end
end)
UIS.InputChanged:Connect(function(input)
    if dragging and input.UserInputType==Enum.UserInputType.MouseMovement then
        local d=input.Position-dragStart
        Main.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)
UIS.InputEnded:Connect(function(input)if input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)

local oldDestroy=Mapper.Destroy
function Mapper:Destroy()
    if Gui and Gui.Parent then Gui:Destroy() end
    return oldDestroy(self)
end
Close.MouseButton1Click:Connect(function()Mapper:Destroy()end)

log("V1 UI loaded")
log("Replica listeners active: "..tostring(#Mapper.Connections))
local capCount=0;for _,v in pairs(Mapper.Capabilities) do if v then capCount+=1 end end
log("executor capabilities detected: "..capCount)
log("Press CAPABILITIES first, then SCAN CLIENT LOGIC")

ENV.AE_DEEP_MAPPER=Mapper
return Mapper
