-- AE Deep Mapper clean entrypoint
local ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_DeepMapper/"
local nonce = tostring(os.time()).."-"..tostring(math.random(100000,999999))
local StarterGui = game:GetService("StarterGui")

local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {Title=title, Text=text, Duration=8})
    end)
end

notify("AE Deep Mapper", "Loading Stats + Equipment discovery…")

local okFetch, src = pcall(function()
    return game:HttpGet(ROOT.."mapper.lua?fresh="..nonce)
end)
if not okFetch then
    warn("[AE-DM] mapper fetch failed: "..tostring(src))
    notify("AE Deep Mapper", "Fetch failed — check console")
    return
end

local chunk, compileErr = loadstring(src)
if not chunk then
    warn("[AE-DM] compile failed: "..tostring(compileErr))
    notify("AE Deep Mapper", "Compile failed — check console")
    return
end

local okRun, result = pcall(chunk)
if not okRun then
    warn("[AE-DM] runtime failed: "..tostring(result))
    notify("AE Deep Mapper", "Runtime failed — check console")
    return
end

return result
