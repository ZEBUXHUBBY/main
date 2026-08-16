-- Greedy Growers bootstrap loader
-- Loads the adaptive controller and always initializes the Rayfield UI.

local SOURCE = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/GreedyGrowers/main.lua"

local okSource, sourceOrError = pcall(function()
    return game:HttpGet(SOURCE)
end)

if not okSource then
    warn("[GreedyGrowers] Failed to download main.lua:", sourceOrError)
    return nil
end

local chunk, compileError = loadstring(sourceOrError)
if not chunk then
    warn("[GreedyGrowers] Failed to compile main.lua:", compileError)
    return nil
end

local okModule, Greedy = pcall(chunk)
if not okModule then
    warn("[GreedyGrowers] main.lua crashed while loading:", Greedy)
    return nil
end

if type(Greedy) ~= "table" then
    warn("[GreedyGrowers] main.lua did not return controller table")
    return Greedy
end

local okUI, uiError = pcall(function()
    Greedy.CreateUI()
end)

if not okUI then
    warn("[GreedyGrowers] UI initialization failed:", uiError)
else
    print("[GreedyGrowers] UI loaded. Controller ready for an authorized adapter.")
end

return Greedy
