-- AE Deep Mapper clean-rebuild entrypoint
-- Old v0/v1 mapper implementations were intentionally removed.
-- KNOWLEDGE.md contains the verified discovery baseline from the first research run.

local StarterGui = game:GetService("StarterGui")
local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {Title=title, Text=text, Duration=8})
    end)
end

warn("[AE-DM] Clean rebuild initialized. Research baseline: AE_DeepMapper/KNOWLEDGE.md")
warn("[AE-DM] Next implementation target: targeted module dumper + replica bootstrap.")
notify("AE Deep Mapper", "Clean rebuild ready. Old mapper removed; knowledge baseline preserved.")

return {
    Version = "AE-DM-CLEAN-BASELINE",
    Status = "research-baseline",
    Knowledge = "AE_DeepMapper/KNOWLEDGE.md",
    Next = {
        "Tournament score/criteria dumper",
        "Stat formula dumper",
        "Trait/equipment/passive dumper",
        "Targeting/hitbox dumper",
        "Slow/Rewind status dumper",
        "Existing-replica bootstrap",
    }
}
