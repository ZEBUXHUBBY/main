-- AE Strategist safe layered entrypoint.
-- 1) Load the known-working standalone core.
-- 2) Load the optional visual addon in isolation.
-- If the addon fails, the core remains fully usable.
-- This never loads AE_Assistant.

local ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Strategist/"

local function fetch(path)
    local ok, source = pcall(function()
        return game:HttpGet(ROOT .. path)
    end)
    if not ok then
        return nil, source
    end
    return source, nil
end

local source, fetchError = fetch("main.lua")
if not source then
    warn("[AE Strategist] Failed to fetch standalone core:", fetchError)
    return
end

-- main.lua uses getCI(value) helpers that return (value, matchedKey).
-- Guard tonumber(getCI(...)) so the matched key cannot become tonumber's base arg.
source = source:gsub("tonumber(%b())", function(args)
    if args:sub(1, 7) == "(getCI(" then
        return "tonumber((" .. args:sub(2, -2) .. "))"
    end
    return "tonumber" .. args
end)

local chunk, compileError = loadstring(source)
if not chunk then
    warn("[AE Strategist] Core compile error:", compileError)
    return
end

local ran, runtimeError = pcall(chunk)
if not ran then
    warn("[AE Strategist] Core runtime error:", runtimeError)
    return
end

print("[AE Strategist] stable standalone core loaded")

-- Visuals are deliberately optional. Never allow them to take the core down.
task.spawn(function()
    local visualSource, visualFetchError = fetch("visual_addon.lua")
    if not visualSource then
        warn("[AE Strategist] Visual addon fetch failed; core remains active:", visualFetchError)
        return
    end

    -- Visual L1 hotfix: PlayerGui is a LayerCollector and has no AbsoluteSize.
    -- Use the active camera viewport instead. Keep this patch isolated from the core.
    visualSource = visualSource:gsub(
        'local viewport = pg%.AbsoluteSize or Vector2%.new%(1920,1080%)',
        'local viewport = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1920,1080)',
        1
    )

    local visualChunk, visualCompileError = loadstring(visualSource)
    if not visualChunk then
        warn("[AE Strategist] Visual addon compile failed; core remains active:", visualCompileError)
        return
    end

    local visualRan, visualRuntimeError = pcall(visualChunk)
    if not visualRan then
        warn("[AE Strategist] Visual addon runtime failed; core remains active:", visualRuntimeError)
        return
    end

    print("[AE Strategist] optional visual layer loaded")
end)