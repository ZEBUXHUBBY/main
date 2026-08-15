-- AE Strategist recovery entrypoint.
-- Restores the known-working standalone strategist core while Visual V2 is rebuilt.
-- This still does NOT load AE_Assistant.

local URL = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Strategist/main.lua"

local ok, source = pcall(function()
    return game:HttpGet(URL)
end)

if not ok then
    warn("[AE Strategist] Failed to fetch standalone engine:", source)
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
    warn("[AE Strategist] Compile error:", compileError)
    return
end

local ran, runtimeError = pcall(chunk)
if not ran then
    warn("[AE Strategist] Runtime error:", runtimeError)
    return
end

print("[AE Strategist] recovered standalone core loaded")
