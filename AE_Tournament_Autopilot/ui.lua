local ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Tournament_Autopilot/ui_parts/"
local nonce = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
local parts = {"01.lua","02.lua","03.lua","04.lua","05.lua"}
local source = {}
for _, path in ipairs(parts) do
    local ok, body = pcall(function()
        return game:HttpGet(ROOT .. path .. "?ui=" .. nonce)
    end)
    if not ok then error("Tournament UI part fetch failed " .. path .. ": " .. tostring(body)) end
    source[#source + 1] = body
end
local joined = table.concat(source,"\n")

-- M2 fallback: if a manual PLAN scan cannot resolve the persistent inventory yet,
-- surface the passive live Replica cache instead of leaving the whole dashboard
-- looking dead. This does not create a fake team; it only reports verified live
-- state already received from the server.
local oldFailure = [[            if not state then
                StageText.Text = "Scan failed: " .. tostring(analysisError)
                return
            end]]
local newFailure = [[            if not state then
                local live = type(Brain.GetLiveReplicaCache) == "function" and Brain:GetLiveReplicaCache() or nil
                if type(live) == "table" then
                    local unitCount = 0
                    for _ in pairs(type(live.Units)=="table" and live.Units or {}) do unitCount = unitCount + 1 end
                    local profileCount = 0
                    for _ in pairs(type(live.ProfileFields)=="table" and live.ProfileFields or {}) do profileCount = profileCount + 1 end
                    StageText.Text = string.format("LIVE M2 • Wave %s • Yen %s • placed replicas %d • observed owned %d",
                        tostring(live.Game and live.Game.Wave or "?"),
                        tostring(live.PlayerGame and live.PlayerGame.Yen or "?"),
                        unitCount, profileCount)
                    NextType.Text = "LIVE STATE"
                    NextTitle.Text = "Inventory snapshot not resolved yet"
                    NextReason.Text = "Replica cache is active. Re-run this loader before the match starts to capture the initial Profile replica, then press SCAN."
                    CostChip.Text = "WAVE " .. tostring(live.Game and live.Game.Wave or "?")
                    TargetChip.Text = "¥ " .. tostring(live.PlayerGame and live.PlayerGame.Yen or "?")
                    FarmChip.Text = unitCount > 0 and (tostring(unitCount) .. " PLACED REPLICAS") or "WAITING FOR UNITS"
                    FarmChip.BackgroundColor3 = COLORS.Warn
                else
                    StageText.Text = "Scan failed: " .. tostring(analysisError)
                end
                return
            end]]
local s,e=string.find(joined,oldFailure,1,true)
if s then joined=string.sub(joined,1,s-1)..newFailure..string.sub(joined,e+1) else warn("[Tournament UI M2] failure patch marker missing") end

local chunk, compileError = loadstring(joined)
if not chunk then error("Tournament UI compile error: " .. tostring(compileError)) end
return chunk()
