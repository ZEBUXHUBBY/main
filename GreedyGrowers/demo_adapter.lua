-- Greedy Growers working demo adapter
-- Simulates the full buy -> plant -> grow -> lightning -> harvest -> sell loop.
-- No third-party remotes are called.

local Adapter = {}
Adapter.Mode = "DEMO_AUTOMATION"

local function signal()
    local bindable = Instance.new("BindableEvent")
    return bindable, bindable.Event
end

local seedSpawnBindable
seedSpawnBindable, Adapter.SeedSpawned = signal()
local selectedBindable
selectedBindable, Adapter.SelectedItemChanged = signal()
local roundStartBindable
roundStartBindable, Adapter.RoundStarted = signal()
local plantStopBindable
plantStopBindable, Adapter.PlantStopped = signal()
local lightningBindable
lightningBindable, Adapter.LightningObserved = signal()
local crashBindable
crashBindable, Adapter.PlantCrashed = signal()
local resetBindable
resetBindable, Adapter.RoundReset = signal()
local dataBindable
dataBindable, Adapter.DataUpdated = signal()

local state = {
    cash = 530,
    offers = {},
    heldSeed = nil,
    heldSeedId = nil,
    activeTree = nil,
    inventory = 0,
    nextSpawnId = 1000,
    nextRoundId = 2000,
    lightningPeriod = 8,
}

local catalog = {
    {name="Oak", price=100, rarity="COMMON", growTime=3.5, value=150},
    {name="Pine", price=220, rarity="UNCOMMON", growTime=4.0, value=310},
    {name="Peach", price=350, rarity="RARE", growTime=4.5, value=520},
    {name="Avocado", price=500, rarity="EPIC", growTime=5.0, value=760},
}

local function shallowCopy(t)
    local o = {}
    for k,v in pairs(t) do o[k] = v end
    return o
end

function Adapter:GetCash()
    return state.cash
end

function Adapter:GetSeedOffers()
    local out = {}
    for _,offer in ipairs(state.offers) do
        out[#out+1] = shallowCopy(offer)
    end
    return out
end

function Adapter:GetHeldSeedName()
    return state.heldSeed and (state.heldSeed.name .. " Seed") or nil
end

function Adapter:GetTrees()
    if not state.activeTree then return {} end
    return {state.activeTree}
end

function Adapter:GetInventoryCount()
    return state.inventory
end

function Adapter:BuySeed(seed)
    if not seed or not seed.price then return false, "invalid seed" end
    if state.heldSeed then return false, "already holding seed" end
    if seed.price > state.cash then return false, "not enough cash" end

    state.cash -= seed.price
    state.heldSeed = shallowCopy(seed)
    state.heldSeedId = "demo-seed-" .. tostring(seed.spawnId or math.random(100000,999999))

    selectedBindable:Fire(state.heldSeedId)
    dataBindable:Fire({Currency={COINS=state.cash}})
    return true
end

function Adapter:PlantSeed(seedName)
    if not state.heldSeed then return false, "no held seed" end

    local seed = state.heldSeed
    state.heldSeed = nil
    state.heldSeedId = nil
    selectedBindable:Fire(nil)

    state.nextRoundId += 1
    local now = os.clock()
    state.activeTree = {
        roundId = state.nextRoundId,
        key = seed.name,
        name = seed.name,
        seedKey = seed.name,
        ready = false,
        plantedAt = now,
        readyAt = now + (seed.growTime or 4),
        observedValue = seed.value or math.floor(seed.price * 1.4),
        growTime = seed.growTime or 4,
    }

    roundStartBindable:Fire({
        roundId = state.activeTree.roundId,
        seedKey = seed.name,
        observedNumber = seed.growTime,
    })

    task.delay(seed.growTime or 4, function()
        if state.activeTree and state.activeTree.roundId == state.nextRoundId then
            state.activeTree.ready = true
            plantStopBindable:Fire(state.activeTree.roundId, seed.growTime or 4)
        end
    end)

    return true
end

function Adapter:HarvestTree(tree)
    if not state.activeTree then return false, "no active tree" end
    if tree and tree.roundId and tree.roundId ~= state.activeTree.roundId then
        return false, "wrong tree"
    end

    local value = tonumber(state.activeTree.observedValue) or 0
    state.inventory += 1
    state.activeTree = nil
    return true, value
end

function Adapter:SellAll()
    if state.inventory <= 0 then return false, 0 end
    local amount = 0
    -- Demo sale bonus simply proves the loop; it is not game data.
    amount = state.inventory * 100
    state.inventory = 0
    state.cash += amount
    dataBindable:Fire({Currency={COINS=state.cash}})
    return true, amount
end

local function spawnOffer()
    state.nextSpawnId += 1
    local base = catalog[((state.nextSpawnId - 1) % #catalog) + 1]
    local offer = shallowCopy(base)
    offer.spawnId = state.nextSpawnId
    offer.startTime = os.clock()
    offer.travelDuration = 15

    state.offers = {offer}
    seedSpawnBindable:Fire(shallowCopy(offer))
end

-- Simulated conveyor offers.
task.spawn(function()
    while task.wait(2.5) do
        spawnOffer()
    end
end)

-- Simulated global lightning. The controller should harvest immediately here.
task.spawn(function()
    while task.wait(state.lightningPeriod) do
        lightningBindable:Fire(os.clock())
        task.wait(0.18)
        if state.activeTree then
            local id = state.activeTree.roundId
            crashBindable:Fire(id, os.clock() - (state.activeTree.plantedAt or os.clock()))
            state.activeTree = nil
            resetBindable:Fire(id)
        end
    end
end)

return Adapter
