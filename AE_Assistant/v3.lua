-- Anime Expeditions Assistant V3 loader
-- One loadstring entrypoint: V2 pre-game advisor + V3 read-only live assist.

local ROOT = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/AE_Assistant/"

local okBase, errBase = pcall(function()
    loadstring(game:HttpGet(ROOT .. "main.lua"))()
end)

if not okBase then
    warn("[AE V3] base advisor failed:", errBase)
    return
end

local okLive, errLive = pcall(function()
    loadstring(game:HttpGet(ROOT .. "live_assist.lua"))()
end)

if not okLive then
    warn("[AE V3] live assist failed:", errLive)
end
