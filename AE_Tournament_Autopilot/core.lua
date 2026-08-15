local ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Tournament_Autopilot/core_parts/"
local nonce = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
local parts = {"01.lua","02.lua","03.lua","04.lua","05.lua","06.lua","07.lua","08.lua"}
local source = {}
for _, path in ipairs(parts) do
    local ok, body = pcall(function()
        return game:HttpGet(ROOT .. path .. "?core=" .. nonce)
    end)
    if not ok then error("Tournament Brain part fetch failed " .. path .. ": " .. tostring(body)) end
    source[#source + 1] = body
end
local chunk, compileError = loadstring(table.concat(source, "\n"))
if not chunk then error("Tournament Brain compile error: " .. tostring(compileError)) end
return chunk()
