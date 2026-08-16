-- Greedy Growers end-to-end demo loader
-- Uses demo_adapter.lua so every automation function can be verified safely.

local BASE = "https://raw.githubusercontent.com/ZEBUXHUBBY/main/main/GreedyGrowers/"

local function loadRemote(name)
    local src = game:HttpGet(BASE .. name)
    local fn, err = loadstring(src)
    assert(fn, err)
    return fn()
end

local Greedy = loadRemote("main.lua")
local Adapter = loadRemote("demo_adapter.lua")

Greedy.AttachAdapter(Adapter)
Greedy.SetConfig({
    Enabled = true,
    AutoBuySeed = true,
    AutoHarvest = true,
    AutoSell = true,
    CashReserve = 0,
    SellThreshold = 1,
})

Greedy.CreateUI()

getgenv().GreedyGrowers = Greedy
getgenv().GreedyGrowersAdapter = Adapter

print("[GreedyGrowers] DEMO automation active")
print("[GreedyGrowers] This demo performs buy -> plant -> grow -> lightning harvest -> sell automatically.")

return Greedy
