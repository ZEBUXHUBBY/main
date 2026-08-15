--[[
AE TOURNAMENT AUTOPILOT M1
Clean standalone entrypoint. It does not load AE_Strategist or AE_Assistant.
The Brain is idle until SCAN / REFRESH is pressed.
]]

local ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Tournament_Autopilot/"
local ENV = getgenv and getgenv() or _G
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer

local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = 7,
        })
    end)
end

if type(ENV.AE_TOURNAMENT_AUTOPILOT) == "table" then
    local old = ENV.AE_TOURNAMENT_AUTOPILOT
    if old.UI and type(old.UI.Destroy) == "function" then pcall(function() old.UI:Destroy() end) end
    if old.Brain and type(old.Brain.Destroy) == "function" then pcall(function() old.Brain:Destroy() end) end
end

local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local oldGui = playerGui:FindFirstChild("AE_Tournament_Autopilot_M1")
if oldGui then oldGui:Destroy() end

local nonce = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
local function fetch(path)
    local ok, source = pcall(function()
        return game:HttpGet(ROOT .. path .. "?m1=" .. nonce)
    end)
    if not ok then return nil, tostring(source) end
    return source
end

local function compile(label, source)
    local chunk, compileError = loadstring(source)
    if not chunk then
        return nil, label .. " COMPILE ERROR: " .. tostring(compileError)
    end
    local ok, result = pcall(chunk)
    if not ok then
        return nil, label .. " RUNTIME ERROR: " .. tostring(result)
    end
    return result, nil
end

local coreSource, coreFetchError = fetch("core.lua")
if not coreSource then
    notify("Tournament Autopilot", "Core fetch failed")
    warn("[Tournament Autopilot] core fetch failed:", coreFetchError)
    return
end

local coreFactory, coreCompileError = compile("CORE", coreSource)
if type(coreFactory) ~= "function" then
    notify("Tournament Autopilot", "Core failed to load")
    warn("[Tournament Autopilot]", coreCompileError or "core factory missing")
    return
end

local brainOk, Brain = pcall(coreFactory, {
    DatabaseRoot = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_DB/",
})
if not brainOk or type(Brain) ~= "table" then
    notify("Tournament Autopilot", "Brain initialization failed")
    warn("[Tournament Autopilot] brain initialization failed:", Brain)
    return
end

local uiSource, uiFetchError = fetch("ui.lua")
if not uiSource then
    Brain:Destroy()
    notify("Tournament Autopilot", "UI fetch failed")
    warn("[Tournament Autopilot] ui fetch failed:", uiFetchError)
    return
end

local uiFactory, uiCompileError = compile("UI", uiSource)
if type(uiFactory) ~= "function" then
    Brain:Destroy()
    notify("Tournament Autopilot", "UI failed to load")
    warn("[Tournament Autopilot]", uiCompileError or "ui factory missing")
    return
end

local uiOk, UI = pcall(uiFactory, Brain, {})
if not uiOk or type(UI) ~= "table" then
    Brain:Destroy()
    notify("Tournament Autopilot", "UI initialization failed")
    warn("[Tournament Autopilot] ui initialization failed:", UI)
    return
end

ENV.AE_TOURNAMENT_AUTOPILOT = {
    Version = "m1.0.0",
    Brain = Brain,
    UI = UI,
    Destroy = function()
        if UI and type(UI.Destroy) == "function" then pcall(function() UI:Destroy() end) end
        if Brain and type(Brain.Destroy) == "function" then pcall(function() Brain:Destroy() end) end
        if ENV.AE_TOURNAMENT_AUTOPILOT then ENV.AE_TOURNAMENT_AUTOPILOT = nil end
    end,
}

print("[AE Tournament Autopilot] M1 READY | idle until SCAN")
