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

-- Readability pass ------------------------------------------------------------
joined = joined:gsub('TextSize = 8, Truncate = Enum.TextTruncate.AtEnd', 'TextSize = 9, Truncate = Enum.TextTruncate.AtEnd')
joined = joined:gsub('Bold = true, TextSize = 10, Truncate = Enum.TextTruncate.AtEnd', 'Bold = true, TextSize = 11, Truncate = Enum.TextTruncate.AtEnd')
joined = joined:gsub('Bold = true, TextSize = 7, Align = Enum.TextXAlignment.Center', 'Bold = true, TextSize = 8, Align = Enum.TextXAlignment.Center')
joined = joined:gsub('Bold = true, TextSize = 8, Align = Enum.TextXAlignment.Right', 'Bold = true, TextSize = 9, Align = Enum.TextXAlignment.Right')
joined = joined:gsub('Color = COLORS.Muted, TextSize = 8, Align = Enum.TextXAlignment.Center', 'Color = COLORS.Muted, TextSize = 10, Align = Enum.TextXAlignment.Center')
joined = joined:gsub('Color = COLORS.Muted, TextSize = 10, Wrap = true, YAlign = Enum.TextYAlignment.Top', 'Color = COLORS.Muted, TextSize = 12, Wrap = true, YAlign = Enum.TextYAlignment.Top')
joined = joined:gsub('Bold = true, TextSize = 9, Truncate = Enum.TextTruncate.AtEnd', 'Bold = true, TextSize = 11, Truncate = Enum.TextTruncate.AtEnd')
joined = joined:gsub('Color = COLORS.Muted, TextSize = 8,', 'Color = COLORS.Muted, TextSize = 10,')

-- Make it explicit that recommendations use the best owned copy, not necessarily
-- the current hotbar copy. Show the actual Trait chosen from that copy.
joined = joined:gsub('tostring%(copy%.Role or "DPS"%) %.%. "  •  " %.%. fmt%(copy%.CapDPS, 0%)', 'tostring(copy.Trait or "No Trait") .. "  •  " .. tostring(copy.Role or "DPS") .. "  •  " .. fmt(copy.CapDPS, 0)')
joined = joined:gsub('copy%.DisplayName %.%. "  •  target "', 'copy.DisplayName .. "  •  " .. tostring(copy.Trait or "No Trait") .. "  •  target "')
joined = joined:gsub('TeamSub%.Text = "Manual REFRESH only • no background scan"', 'TeamSub.Text = "Best owned copies • Trait shown may differ from current hotbar"')
joined = joined:gsub('TeamSub%.Text = "Tap a unit to inspect placement %+ target"', 'TeamSub.Text = "Best copy from whole inventory • tap to inspect"')

-- Reject tiny decorative ImageLabels as unit portraits. Prefer game ViewportFrame;
-- otherwise the existing addUnitVisual() naturally falls back to the game model.
local oldResolve = [[                    for alias, asset in pairs(aliases) do
                        if #alias >= 4 and words:find(alias, 1, true) then
                            if not UI.Resolver.ByAsset[asset] then UI.Resolver.ByAsset[asset] = descendant end
                        end
                    end]]
local newResolve = [[                    for alias, asset in pairs(aliases) do
                        if #alias >= 4 and words:find(alias, 1, true) then
                            local size = descendant.AbsoluteSize
                            local portraitLike = descendant:IsA("ViewportFrame") or (size.X >= 44 and size.Y >= 44 and size.X / math.max(1,size.Y) >= 0.65 and size.X / math.max(1,size.Y) <= 1.55)
                            local existing = UI.Resolver.ByAsset[asset]
                            if portraitLike and (not existing or (descendant:IsA("ViewportFrame") and not existing:IsA("ViewportFrame"))) then
                                UI.Resolver.ByAsset[asset] = descendant
                            end
                        end
                    end]]
local rs,re=string.find(joined,oldResolve,1,true)
if rs then joined=string.sub(joined,1,rs-1)..newResolve..string.sub(joined,re+1) end

-- M2 fallback: surface verified passive state if a manual scan fails.
local oldFailure = [[            if not state then
                StageText.Text = "Scan failed: " .. tostring(analysisError)
                return
            end]]
local newFailure = [[            if not state then
                local live = type(Brain.GetLiveReplicaCache) == "function" and Brain:GetLiveReplicaCache() or nil
                if type(live) == "table" then
                    local unitCount=0;for _ in pairs(type(live.Units)=="table" and live.Units or {}) do unitCount=unitCount+1 end
                    local profileCount=0;for _ in pairs(type(live.ProfileFields)=="table" and live.ProfileFields or {}) do profileCount=profileCount+1 end
                    StageText.Text=string.format("LIVE M2 • Wave %s • Yen %s • placed %d • observed owned %d",tostring(live.Game and live.Game.Wave or "?"),tostring(live.PlayerGame and live.PlayerGame.Yen or "?"),unitCount,profileCount)
                else
                    StageText.Text="Scan failed: "..tostring(analysisError)
                end
                return
            end]]
local s,e=string.find(joined,oldFailure,1,true)
if s then joined=string.sub(joined,1,s-1)..newFailure..string.sub(joined,e+1) end

local chunk, compileError = loadstring(joined)
if not chunk then error("Tournament UI compile error: " .. tostring(compileError)) end
return chunk()
