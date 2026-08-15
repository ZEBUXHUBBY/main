-- AE Strategist standalone entrypoint.
-- Loads ONLY the new AE_Strategist engine. It never loads AE_Assistant.

local URL = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Strategist/main.lua"

local ok, source = pcall(function()
    return game:HttpGet(URL)
end)

if not ok then
    warn("[AE Strategist] Failed to fetch standalone engine:", source)
    return
end

-- Lua passes every return value from a function when it is the final argument.
-- getCI returns (value, matchedKey), while tonumber(value, base) has an optional
-- second argument. Protect every tonumber(getCI(...)) expression in the engine
-- so the matched key can never accidentally become tonumber's base argument.
local patched = 0
source = source:gsub("tonumber(%b())", function(args)
    if args:sub(1, 7) == "(getCI(" then
        patched = patched + 1
        return "tonumber((" .. args:sub(2, -2) .. "))"
    end
    return "tonumber" .. args
end)

local chunk, compileError = loadstring(source)
if not chunk then
    warn("[AE Strategist] Standalone engine compile error:", compileError)
    return
end

local ran, runtimeError = pcall(chunk)
if not ran then
    warn("[AE Strategist] Standalone engine runtime error:", runtimeError)
    return
end

print("[AE Strategist] standalone entrypoint OK | guarded tonumber/getCI calls:", patched)
