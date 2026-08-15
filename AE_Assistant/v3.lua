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
    local source = game:HttpGet(ROOT .. "live_assist.lua")

    -- Hotfix for the first V3 live-assist revision: getCI returns (value, key).
    -- Collapse it to one return before tonumber so the key cannot be interpreted
    -- as tonumber's optional numeric base argument. Remove this shim after the
    -- source file itself is replaced with the corrected revision.
    source = source:gsub(
        'Speed = tonumber%%(getCI%%(info, %%{"Speed", "MoveSpeed", "WalkSpeed", "BaseSpeed"%%}%%)%%),',
        'Speed = tonumber((getCI(info, {"Speed", "MoveSpeed", "WalkSpeed", "BaseSpeed"}))),'
    )

    loadstring(source)()
end)

if not okLive then
    warn("[AE V3] live assist failed:", errLive)
end
