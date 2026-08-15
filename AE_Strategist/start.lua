-- AE Strategist safe dashboard entrypoint.
-- 1) Load the known-working standalone core.
-- 2) Load Dashboard V2 in isolation.
-- If the dashboard fails, the core remains fully usable.
-- This never loads AE_Assistant.

local ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Strategist/"

local function fetch(path)
    local ok, source = pcall(function()
        return game:HttpGet(ROOT .. path)
    end)
    if not ok then return nil, source end
    return source, nil
end

local source, fetchError = fetch("main.lua")
if not source then
    warn("[AE Strategist] Failed to fetch standalone core:", fetchError)
    return
end

-- Core safety guard: getCI returns (value, matchedKey), while tonumber has an
-- optional second base argument. Collapse getCI to one return in tonumber calls.
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

-- Dashboard is optional and isolated. It can never take the core down.
task.spawn(function()
    local dashSource, dashFetchError = fetch("dashboard_v2.lua")
    if not dashSource then
        warn("[AE Strategist] Dashboard fetch failed; core remains active:", dashFetchError)
        return
    end

    -- Dashboard-only preflight patches. These never modify the core.
    dashSource = dashSource:gsub(
        "local LearnButton=button%(",
        "local LearnButton\nLearnButton=button(",
        1
    )

    -- Starting Yen is not a full-stage budget. Only replace the hidden core
    -- budget when the stage exposes TotalYen or the runtime learner has a projection.
    dashSource = dashSource:gsub(
        "local autoBudget=stageTotal or learned or starting",
        "local autoBudget=stageTotal or learned",
        1
    )

    local dashChunk, dashCompileError = loadstring(dashSource)
    if not dashChunk then
        warn("[AE Strategist] Dashboard compile failed; core remains active:", dashCompileError)
        return
    end

    local dashRan, dashRuntimeError = pcall(dashChunk)
    if not dashRan then
        warn("[AE Strategist] Dashboard runtime failed; core remains active:", dashRuntimeError)
        return
    end

    print("[AE Strategist] Dashboard V2 loaded")
end)