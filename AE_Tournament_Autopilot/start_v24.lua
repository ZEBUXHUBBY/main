-- AE Tournament Brain V2.4-RUNTIME cache-safe entrypoint
local ROOT="https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Tournament_Autopilot/"
local ENV=getgenv and getgenv() or _G
local Players=game:GetService("Players")
local StarterGui=game:GetService("StarterGui")
local LocalPlayer=Players.LocalPlayer
local function notify(title,text) pcall(function()StarterGui:SetCore("SendNotification",{Title=title,Text=text,Duration=7})end) end

if type(ENV.AE_TOURNAMENT_AUTOPILOT)=="table" then
    local old=ENV.AE_TOURNAMENT_AUTOPILOT
    if old.UI and type(old.UI.Destroy)=="function" then pcall(function()old.UI:Destroy()end) end
    if old.Brain and type(old.Brain.Destroy)=="function" then pcall(function()old.Brain:Destroy()end) end
    ENV.AE_TOURNAMENT_AUTOPILOT=nil
end
local pg=LocalPlayer:WaitForChild("PlayerGui")
for _,name in ipairs({"AE_Tournament_Autopilot_M1","AE_Tournament_Autopilot_M2","AE_Tournament_Autopilot_M23","AE_Tournament_Autopilot_M24"}) do local g=pg:FindFirstChild(name);if g then g:Destroy() end end

local nonce=tostring(os.time()).."-"..tostring(math.random(100000,999999))
local function fetch(path,tag)
    local ok,src=pcall(function()return game:HttpGet(ROOT..path.."?"..(tag or "v24").."="..nonce)end)
    if not ok then return nil,tostring(src) end
    return src
end
local function execute(label,src)
    local chunk,err=loadstring(src);if not chunk then return nil,label.." COMPILE ERROR: "..tostring(err) end
    local ok,res=pcall(chunk);if not ok then return nil,label.." RUNTIME ERROR: "..tostring(res) end
    return res,nil
end

local coreSource,err=fetch("core.lua","v24corebase")
if not coreSource then notify("Tournament Brain V2.4","Core fetch failed");warn(err);return end
local coreFactory,cerr=execute("CORE",coreSource)
if type(coreFactory)~="function" then notify("Tournament Brain V2.4","Core failed");warn(cerr);return end
local okBrain,Brain=pcall(coreFactory,{DatabaseRoot="https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_DB/"})
if not okBrain or type(Brain)~="table" then notify("Tournament Brain V2.4","Brain init failed");warn(Brain);return end

local runtimeSource,rerr=fetch("runtime_v24.lua","v24runtime")
if not runtimeSource then Brain:Destroy();notify("Tournament Brain V2.4","Runtime fetch failed");warn(rerr);return end
local runtimeFactory,rcerr=execute("RUNTIME_V24",runtimeSource)
if type(runtimeFactory)~="function" then Brain:Destroy();notify("Tournament Brain V2.4","Runtime compile failed");warn(rcerr);return end
local okRuntime,runtimeResult=pcall(runtimeFactory,Brain)
if not okRuntime then Brain:Destroy();notify("Tournament Brain V2.4","Runtime init failed");warn(runtimeResult);return end
Brain=runtimeResult or Brain

local uiSource,uerr=fetch("ui_v24.lua","v24ui")
if not uiSource then Brain:Destroy();notify("Tournament Brain V2.4","UI fetch failed");warn(uerr);return end
local uiFactory,ucerr=execute("UI_V24",uiSource)
if type(uiFactory)~="function" then Brain:Destroy();notify("Tournament Brain V2.4","UI failed");warn(ucerr);return end
local okUI,UI=pcall(uiFactory,Brain,{})
if not okUI or type(UI)~="table" then Brain:Destroy();notify("Tournament Brain V2.4","UI init failed");warn(UI);return end

ENV.AE_TOURNAMENT_AUTOPILOT={Version="V2.4-RUNTIME",Brain=Brain,UI=UI,Destroy=function()
    if UI and type(UI.Destroy)=="function" then pcall(function()UI:Destroy()end) end
    if Brain and type(Brain.Destroy)=="function" then pcall(function()Brain:Destroy()end) end
    ENV.AE_TOURNAMENT_AUTOPILOT=nil
end}
print("[AE Tournament Brain] V2.4-RUNTIME READY")
notify("Tournament Brain","V2.4-RUNTIME loaded")
