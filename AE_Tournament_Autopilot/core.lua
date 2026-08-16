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

local joined = table.concat(source, "\n")

-- A separate read-only probe can validate the exact local-player profile when an
-- executor hides it inside function upvalues. The Brain accepts only an override
-- that still passes its own named UnitData/HotbarData shape check.
local marker = "    local function scanProfileData()\n"
local replacement = [[    local function scanProfileData()
        local env = getgenv and getgenv() or _G
        local override = env.AE_TOURNAMENT_PROFILE_OVERRIDE
        if type(override) == "table" then
            local shaped, data = tableHasProfileShape(override)
            if shaped and type(data) == "table" then
                appendDiagnostic("profile override accepted from exact profile probe")
                return data, nil
            end
            appendDiagnostic("profile override rejected: named UnitData/HotbarData shape missing")
        end
]]

local startAt, endAt = string.find(joined, marker, 1, true)
if startAt then
    joined = string.sub(joined, 1, startAt - 1) .. replacement .. string.sub(joined, endAt + 1)
else
    warn("[Tournament Brain] profile override patch marker not found")
end

local chunk, compileError = loadstring(joined)
if not chunk then error("Tournament Brain compile error: " .. tostring(compileError)) end
return chunk()
