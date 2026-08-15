
        for key, row in pairs(type(Equipment) == "table" and Equipment or {}) do
            database.EquipmentIndex[norm(key)] = row
            if type(row) == "table" then
                for _, field in ipairs({"Asset", "DisplayName", "Name"}) do
                    local value = row[field]
                    if type(value) == "string" then database.EquipmentIndex[norm(value)] = row end
                end
            end
        end

        for asset, row in pairs(type(Units) == "table" and Units or {}) do
            database.UnitAlias[norm(asset)] = asset
            if type(row) == "table" then
                local displayName = ci(row, {"DisplayName", "Name"})
                if type(displayName) == "string" then database.UnitAlias[norm(displayName)] = asset end
            end
        end

        Brain.Cache.Database = database
        appendDiagnostic("DB units=" .. tostring(countKeys(Units)) .. " source=" .. tostring(unitsSource))
        appendDiagnostic("DB traits=" .. tostring(countKeys(Traits)) .. " source=" .. tostring(traitsSource))
        return database
    end

    -- -------------------------------------------------------------------------
    -- Profile / stage scanners
    -- -------------------------------------------------------------------------

    local function tableHasProfileShape(value)
        if type(value) ~= "table" then return false, nil end
        local data = rawget(value, "Data")
        if type(data) ~= "table" then data = value end
        local unitData = ci(data, {"UnitData", "Units"})
        local hotbarData = ci(data, {"HotbarData", "Hotbar"})
        return type(unitData) == "table" or type(hotbarData) == "table", data
    end

    local function profilePlayerAffinity(object)
        if type(object) ~= "table" then return 0 end
        local score = 0
        local inspected = 0

        local function inspectValue(value)
            if value == LocalPlayer then return 10000 end
            if typeof(value) == "Instance" then
                if value:IsA("Player") and value.UserId == LocalPlayer.UserId then return 10000 end
                return 0
            end
            if type(value) == "number" and value == LocalPlayer.UserId then return 1200 end
            if type(value) == "string" then
                if value == LocalPlayer.Name then return 1600 end
                if value == tostring(LocalPlayer.UserId) then return 1200 end
            end
            return 0
        end

        for key, value in pairs(object) do
            inspected = inspected + 1
            if inspected > 80 then break end
            score = score + inspectValue(value)
            local keyName = norm(key)
            if type(value) == "table" and (keyName:find("replication", 1, true) or keyName:find("player", 1, true) or keyName:find("owner", 1, true)) then
                local nested = 0
                for _, child in pairs(value) do
                    nested = nested + 1
                    if nested > 24 then break end
                    score = score + inspectValue(child)
                end
            end
        end
        return score
    end

    local function scanProfileData()
        if type(getgc) ~= "function" then
            appendDiagnostic("getgc unavailable")
            return nil, "getgc unavailable"
        end

        local ok, objects = pcall(getgc, true)
        if not ok or type(objects) ~= "table" then
            return nil, "getgc failed"
        end

        local bestData, bestScore = nil, -math.huge
        local inspected = 0
        for _, object in ipairs(objects) do
            if type(object) == "table" then
                inspected = inspected + 1
                local shaped, data = tableHasProfileShape(object)
                if shaped and type(data) == "table" then
                    local unitData = ci(data, {"UnitData", "Units"})
                    local hotbarData = ci(data, {"HotbarData", "Hotbar"})
                    local score = profilePlayerAffinity(object)
                    if type(unitData) == "table" then score = score + math.min(500, countKeys(unitData)) * 4 end
                    if type(hotbarData) == "table" then score = score + math.min(20, countKeys(hotbarData)) * 10 end
                    if ci(data, {"ProfileData"}) ~= nil then score = score + 25 end
                    if ci(data, {"ItemData"}) ~= nil then score = score + 10 end
                    if score > bestScore then
                        bestScore = score
                        bestData = data
                    end
                end
            end
        end

        appendDiagnostic("getgc tables inspected=" .. tostring(inspected) .. " profileScore=" .. tostring(bestScore))
        if not bestData then return nil, "profile replica not found" end
        return bestData, nil
    end

    local function isUnitRecord(value, database)
        if type(value) ~= "table" then return false end
        local asset = ci(value, {"Asset", "Unit", "UnitName"})
        if type(asset) ~= "string" or not database.UnitAlias[norm(asset)] then return false end
        return ci(value, {"Level", "EXP", "StatPotential", "Trait", "ObtainedAt", "Worthiness", "Equipped"}) ~= nil
    end

    local function unwrapUnitRecord(value, database)
        if type(value) ~= "table" then return nil end
        if isUnitRecord(value, database) then return value end
        local candidates = {
            value.UnitData,
            value.Data,
            value.Unit,
            value.ProfileUnit,
        }
        for _, candidate in ipairs(candidates) do
            if isUnitRecord(candidate, database) then return candidate end
        end
        return nil
    end

    local function parseOwned(profileData, database)
        local unitContainer = ci(profileData, {"UnitData", "Units"})
        local owned = {}
        local byId = {}

        local function addRecord(key, wrapper)
            local record = unwrapUnitRecord(wrapper, database)
            if not record then return end
            local rawAsset = ci(record, {"Asset", "Unit", "UnitName"})
            local asset = database.UnitAlias[norm(rawAsset)]
            if not asset then return end
            local id = tostring(ci(record, {"ID", "Id", "UUID", "Guid"}) or key or (asset .. "#" .. tostring(#owned + 1)))
            local entry = {
                Asset = asset,
                ID = id,
                Data = record,
                Wrapper = wrapper,
            }
            owned[#owned + 1] = entry
            byId[id] = entry
            byId[norm(id)] = entry
            byId[norm(asset .. "#" .. id)] = entry
        end

        if type(unitContainer) == "table" then
            for key, wrapper in pairs(unitContainer) do addRecord(key, wrapper) end
        end

        table.sort(owned, function(a, b)
            local assetA, assetB = tostring(a.Asset), tostring(b.Asset)
            if assetA ~= assetB then return assetA < assetB end
            return tostring(a.ID) < tostring(b.ID)
        end)

        return owned, byId
    end

    local function parseHotbar(profileData, owned, byId, database)
        local hotbarContainer = ci(profileData, {"HotbarData", "Hotbar"})
        local hotbar = {}

        local function resolveFromValue(value, key)
            if type(value) == "string" or type(value) == "number" then
                local text = tostring(value)
                return byId[text] or byId[norm(text)]
            end
            if type(value) == "table" then
                local record = unwrapUnitRecord(value, database)
                if record then
                    local rawAsset = ci(record, {"Asset", "Unit", "UnitName"})
                    local asset = database.UnitAlias[norm(rawAsset)]
                    local id = tostring(ci(record, {"ID", "Id", "UUID", "Guid"}) or key or "")
                    return byId[id] or byId[norm(id)] or {
                        Asset = asset,
                        ID = id,
                        Data = record,
                        Wrapper = value,
                    }
                end
                local id = ci(value, {"ID", "Id", "UnitID", "UnitId", "UUID", "Guid"})
                if id ~= nil then return byId[tostring(id)] or byId[norm(id)] end
                local asset = ci(value, {"Asset", "Unit", "UnitName"})
                if type(asset) == "string" then
                    local canonical = database.UnitAlias[norm(asset)]
                    for _, entry in ipairs(owned) do
                        if entry.Asset == canonical then return entry end
                    end
                end
            end
            return nil
        end

        if type(hotbarContainer) == "table" then
            for key, value in pairs(hotbarContainer) do
                local slot = tonumber(ci(type(value) == "table" and value or {}, {"HotbarSlot", "Slot"})) or tonumber(key)
                local record = resolveFromValue(value, key)
                if slot and record and record.Asset then
                    hotbar[#hotbar + 1] = {
                        Slot = slot,
                        Asset = record.Asset,
                        Record = record,
                    }
                end
            end
        end

        if #hotbar == 0 then
            local equipped = {}
            for _, entry in ipairs(owned) do
                if ci(entry.Data, {"Equipped"}) == true then equipped[#equipped + 1] = entry end
            end
            table.sort(equipped, function(a, b) return tostring(a.Asset) < tostring(b.Asset) end)
            for index = 1, math.min(6, #equipped) do
                hotbar[#hotbar + 1] = {
                    Slot = index,
                    Asset = equipped[index].Asset,
                    Record = equipped[index],
                }
            end
        end

        table.sort(hotbar, function(a, b) return (a.Slot or 999) < (b.Slot or 999) end)
        return hotbar
    end

    local function collectVisibleText()
        local pieces = {}
        local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then return "" end
        local count = 0
        for _, descendant in ipairs(playerGui:GetDescendants()) do
            if (descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox")) and descendant.Visible then
                local text = trim(descendant.Text)
                if text ~= "" then
                    pieces[#pieces + 1] = text
                    count = count + 1
                    if count >= 900 then break end
                end
            end
        end
        return table.concat(pieces, "\n")
    end
