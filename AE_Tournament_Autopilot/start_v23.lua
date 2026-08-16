-- AE Tournament Autopilot V2.3-WM cache-safe entrypoint
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
    if type(old.ExtraConnections)=="table" then for _,c in ipairs(old.ExtraConnections) do pcall(function()c:Disconnect()end) end end
    ENV.AE_TOURNAMENT_AUTOPILOT=nil
end
local pg=LocalPlayer:WaitForChild("PlayerGui")
for _,name in ipairs({"AE_Tournament_Autopilot_M1","AE_Tournament_Autopilot_M2","AE_Tournament_Autopilot_M23"}) do local g=pg:FindFirstChild(name);if g then g:Destroy() end end

local nonce=tostring(os.time()).."-"..tostring(math.random(100000,999999))
local function fetch(path,tag)
    local ok,src=pcall(function()return game:HttpGet(ROOT..path.."?"..(tag or "v23").."="..nonce)end)
    if not ok then return nil,tostring(src) end
    return src
end
local function compile(label,src)
    local chunk,err=loadstring(src);if not chunk then return nil,label.." COMPILE ERROR: "..tostring(err) end
    local ok,res=pcall(chunk);if not ok then return nil,label.." RUNTIME ERROR: "..tostring(res) end
    return res,nil
end

local coreSource,err=fetch("core.lua","v23core")
if not coreSource then notify("Tournament Brain V2.3","Core fetch failed");warn(err);return end
local coreFactory,cerr=compile("CORE",coreSource)
if type(coreFactory)~="function" then notify("Tournament Brain V2.3","Core failed");warn(cerr);return end
local okBrain,Brain=pcall(coreFactory,{DatabaseRoot="https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_DB/"})
if not okBrain or type(Brain)~="table" then notify("Tournament Brain V2.3","Brain init failed");warn(Brain);return end

local uiSource,uerr=fetch("ui_v23.lua","v23ui")
if not uiSource then Brain:Destroy();notify("Tournament Brain V2.3","UI V2.3 fetch failed");warn(uerr);return end
local uiFactory,ucerr=compile("UI_V23",uiSource)
if type(uiFactory)~="function" then Brain:Destroy();notify("Tournament Brain V2.3","UI V2.3 failed");warn(ucerr);return end
local okUI,UI=pcall(uiFactory,Brain,{})
if not okUI or type(UI)~="table" then Brain:Destroy();notify("Tournament Brain V2.3","UI V2.3 init failed");warn(UI);return end

ENV.AE_TOURNAMENT_AUTOPILOT={Version="V2.3-WM-5955cc8",Brain=Brain,UI=UI,ExtraConnections={},Destroy=function()
    if UI and type(UI.Destroy)=="function" then pcall(function()UI:Destroy()end) end
    if Brain and type(Brain.Destroy)=="function" then pcall(function()Brain:Destroy()end) end
    ENV.AE_TOURNAMENT_AUTOPILOT=nil
end}
print("[AE Tournament Brain] V2.3-WM-5955cc8 READY")
notify("Tournament Brain","V2.3-WM loaded")
