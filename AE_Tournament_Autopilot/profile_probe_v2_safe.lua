-- AE Profile Probe V2 safe loader
local ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Tournament_Autopilot/"
local ENV = getgenv and getgenv() or _G
local nonce = tostring(os.time()) .. "-" .. tostring(math.random(100000,999999))
local source = game:HttpGet(ROOT .. "profile_probe_v2.lua?v2safe=" .. nonce)
local chunk, compileError = loadstring(source)
if not chunk then error("Profile Probe V2 compile error: " .. tostring(compileError)) end
local ok, runtimeError = pcall(chunk)
if not ok then error("Profile Probe V2 runtime error: " .. tostring(runtimeError)) end

-- Keep the saved report structural and small. The validated live profile remains
-- only in memory for USE + OPEN BRAIN and is never serialized in full.
local probe = ENV.AE_TOURNAMENT_PROFILE_PROBE_V2
if type(probe) == "table" and type(probe.Save) == "function" then
    local originalSave = probe.Save
    function probe:Save()
        if type(self.Report) == "table" and type(self.Report.ProfileCandidates) == "table" then
            for _, candidate in ipairs(self.Report.ProfileCandidates) do
                if type(candidate) == "table" then candidate.Profile = nil end
            end
        end
        return originalSave(self)
    end
end

print("[AE Profile Probe V2 Safe] READY")
