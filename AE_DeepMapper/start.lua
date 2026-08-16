-- AE Deep Mapper stable entrypoint
local ROOT="https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_DeepMapper/"
local nonce=tostring(os.time()).."-"..tostring(math.random(100000,999999))
local StarterGui=game:GetService("StarterGui")
local function notify(title,text)
    pcall(function() StarterGui:SetCore("SendNotification",{Title=title,Text=text,Duration=7}) end)
end
notify("AE Deep Mapper","Loading V1 research console…")
local ok,src=pcall(function()return game:HttpGet(ROOT.."ae_deep_mapper_v1.lua?start="..nonce)end)
if not ok then warn("[AE-DM] fetch failed: "..tostring(src));notify("AE Deep Mapper","Fetch failed — check console");return end
local chunk,err=loadstring(src)
if not chunk then warn("[AE-DM] compile failed: "..tostring(err));notify("AE Deep Mapper","Compile failed — check console");return end
local okRun,res=pcall(chunk)
if not okRun then warn("[AE-DM] runtime failed: "..tostring(res));notify("AE Deep Mapper","Runtime failed — check console");return end
notify("AE Deep Mapper","V1 ready — use CAPABILITIES then SCAN CLIENT LOGIC")
return res
