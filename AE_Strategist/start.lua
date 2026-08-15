-- AE Strategist standalone visual entrypoint.
-- Loads ONLY AE_Strategist/visual_v2.lua. It never loads AE_Assistant or Strategist v1.

local URL = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Strategist/visual_v2.lua"

local ok, source = pcall(function()
    return game:HttpGet(URL)
end)

if not ok then
    warn("[AE Strategist V2] Failed to fetch visual engine:", source)
    return
end

local chunk, compileError = loadstring(source)
if not chunk then
    warn("[AE Strategist V2] Compile error:", compileError)
    return
end

local ran, runtimeError = pcall(chunk)
if not ran then
    warn("[AE Strategist V2] Runtime error:", runtimeError)
    return
end

print("[AE Strategist V2] standalone visual entrypoint OK")
