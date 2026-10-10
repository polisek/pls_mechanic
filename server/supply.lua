--[[
   _____                   _
  / ____|                 | |
 | (___  _   _ _ __  _ __ | |_   _
  \___ \| | | | '_ \| '_ \| | | | |
  ____) | |_| | |_) | |_) | | |_| |
 |_____/ \__,_| .__/| .__/|_|\__, |
              | |   | |       __/ |
              |_|   |_|      |___/
 Supplier orders (instant / delayed / run), supply runs with a van, orders log.
 Order status: pending (delayed) / awaiting_pickup (run) / in_transit (run started) / delivered / cancelled
]]--

SupplyServer = {}

local Cfg = Config.Supplier
local RunCfg = Config.Supplier.run
local ModeOrder = { "instant", "delayed", "run" }
local PAGE_SIZE = 20

local Catalog = {}        -- [key] = catalog entry
local DailyUsage = {}     -- [shopId][key] = pieces ordered today
local DailyKey = nil
local Cooldowns = {}      -- [src][action] = GetGameTimer()
local ItemLabels = nil
local Runs = {}           -- [runId] = run
local PlayerRuns = {}     -- [src] = runId
local RunCounter = 0
local ReleasedVans = {}   -- [entity] = true, vans of finished runs waiting for removal

for _, entry in ipairs(Cfg.catalog) do
    if Config.Items[entry.item] then
        Catalog[entry.item] = entry
    else
        print(("[pls_mechanic] Supplier catalog item '%s' is not in Config.Items"):format(tostring(entry.item)))
    end
end

--[[
  _    _      _
 | |  | |    | |
 | |__| | ___| |_ __   ___ _ __ ___
 |  __  |/ _ \ | '_ \ / _ \ '__/ __|
 | |  | |  __/ | |_) |  __/ |  \__ \
 |_|  |_|\___|_| .__/ \___|_|  |___/
               | |
               |_|
]]--

local function formatMoney(value)
    local formatted = tostring(math.floor(value or 0))
    local k
    repeat
        formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1 %2")
    until k == 0
    return Config.Currency..formatted
end

local function fail(message)
    return { ok = false, message = message }
end

-- true when action is allowed (and stores the time), false when player is too fast
local function checkRate(src, action, ms)
    Cooldowns[src] = Cooldowns[src] or {}
    local now = GetGameTimer()
    local last = Cooldowns[src][action]
    if last and now - last < ms then
        return false
    end
    Cooldowns[src][action] = now
    return true
end

local function getItemLabel(itemName)
    if not ItemLabels then
        local labels = {}
        local ok, items = pcall(BRIDGE.GetItems)
        if ok and type(items) == "table" then
            for name, data in pairs(items) do
                if type(data) == "table" and data.label then
                    labels[name] = data.label
                end
            end
        end
        if next(labels) then
            ItemLabels = labels
        end
        return labels[itemName] or itemName
    end
    return ItemLabels[itemName] or itemName
end

local function getPlayerName(src)
    local ok, name = pcall(BRIDGE.GetPlayerFullName, src)
    if ok and type(name) == "string" and name ~= "" then
        return name
    end
    return GetPlayerName(src) or ("ID "..tostring(src))
end

local function getCharId(src)
    local ok, charId = pcall(BRIDGE.GetPlayerCharId, src)
    if ok and charId then
        return tostring(charId)
    end
    return nil
end

local function log(src, action, message, data)
    local ok, err = pcall(OpenServer.Log, src, action, message, data)
    if not ok then
        print("[pls_mechanic] OpenServer.Log error: "..tostring(err))
    end
end

local function isNear(src, coords, maxDistance)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - coords) <= maxDistance
end

local function findPoint(shop, pointType)
    for _, point in pairs(shop and shop.points or {}) do
        if point.type == pointType then
            return point
        end
    end
    return nil
end

-- Player is at workshop point of given type (pointId from client)
local function isAtPoint(src, shop, pointId, pointType, extra)
    local point = Utils.GetShopPoint(shop, pointId)
    if not point or point.type ~= pointType then return false, nil end
    local radius = point.radius or (Config.PointTypes[pointType] and Config.PointTypes[pointType].radius) or 2.0
    return isNear(src, Utils.Vec3(point.coords), radius + (extra or 3.0)), point
end

local function countPieces(items)
    local pieces = 0
    for _, v in pairs(items or {}) do
        pieces = pieces + (tonumber(v.count) or 0)
    end
    return pieces
end

local function cratesFor(pieces)
    return math.ceil(pieces / math.max(1, RunCfg.itemsPerCrate))
end

local function decodeItems(value)
    local ok, items = pcall(json.decode, value or "[]")
    if ok and type(items) == "table" then
        return items
    end
    return {}
end

local function notifyShop(shopId, text, notifyType)
    for _, playerId in pairs(GetPlayers()) do
        local src = tonumber(playerId)
        if Player(src).state.pls_mechanic_duty == shopId then
            Shops.Notify(src, text, notifyType)
        end
    end
end

local REDELIVERY_SECONDS = 600

-- Adds items {{item = key, count}} to workshop storage.
-- Items that don't fit (storage full) wait at the supplier as a new delayed delivery.
local function deliverToStash(shopId, items)
    local stashId = Shops.GetStashId(shopId)
    local failed = {}
    for _, v in pairs(items or {}) do
        local count = math.floor(tonumber(v.count) or 0)
        if Config.Items[v.item] and count > 0 then
            if not BRIDGE.AddStashItem(stashId, Utils.Item(v.item), count) then
                table.insert(failed, { item = v.item, count = count })
            end
        end
    end
    if #failed > 0 then
        local now = os.time()
        MySQL.insert("INSERT INTO `pls_mechanic_orders` (`shop_id`, `charid`, `name`, `items`, `total`, `mode`, `status`, `deliver_at`, `created_at`) VALUES (?, NULL, ?, ?, 0, 'delayed', 'pending', ?, ?)", {
            shopId, locale("supply_redelivery_name"), json.encode(failed), now + REDELIVERY_SECONDS, now,
        })
        notifyShop(shopId, locale("supply_storage_full", math.floor(REDELIVERY_SECONDS / 60)), "error")
    end
end

--[[
  _____                                     _     _ _           _ _
 |  __ \                                   | |   | (_)         (_) |
 | |__) |_ _ _   _ _ __ ___   ___ _ __ | |_  | |_ _ __ ___  _| |_ ___
 |  ___/ _` | | | | '_ ` _ \ / _ \ '_ \| __| | | | '_ ` _ \| | __/ __|
 | |  | (_| | |_| | | | | | |  __/ | | | |_  | | | | | | | | | |_\__ \
 |_|   \__,_|\__, |_| |_| |_|\___|_| |_|\__| |_|_|_| |_| |_|_|\__|___/
              __/ |
             |___/
]]--

local function isModeEnabled(shop, mode)
    local modeCfg = Cfg.modes[mode]
    if not modeCfg or not modeCfg.enabled then return false end
    local modes = shop and shop.settings and shop.settings.supplyModes or {}
    return modes[mode] == true
end

local function getBalance(src, shopId)
    if Cfg.payFrom == "player" then
        if Cfg.playerAccount == "cash" then
            return BRIDGE.GetItemCount(src, "money") or 0
        end
        return BRIDGE.GetPlayerBankMoney(src) or 0
    end
    local job = Shops.GetSocietyJob(shopId)
    if not job then return 0 end
    return BRIDGE.GetSocietyMoney(job) or 0
end

local function takeMoney(src, shopId, amount)
    if amount <= 0 then return true end
    if getBalance(src, shopId) < amount then return false end
    if Cfg.payFrom == "player" then
        if Cfg.playerAccount == "cash" then
            return BRIDGE.RemoveItem(src, "money", amount) ~= false
        end
        return BRIDGE.RemovePlayerBankMoney(src, amount)
    end
    return BRIDGE.RemoveSocietyMoney(Shops.GetSocietyJob(shopId), amount) == true
end

local function refundMoney(src, shopId, amount)
    if amount <= 0 then return end
    if Cfg.payFrom == "player" then
        if Cfg.playerAccount == "cash" then
            BRIDGE.AddItem(src, "money", amount)
        else
            BRIDGE.AddPlayerBankMoney(src, amount)
        end
        return
    end
    local job = Shops.GetSocietyJob(shopId)
    if job then
        BRIDGE.AddSocietyMoney(job, amount)
    end
end

local function startOfDay()
    local t = os.date("*t")
    return os.time({ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 })
end

local function addUsage(shopId, items, sign)
    DailyUsage[shopId] = DailyUsage[shopId] or {}
    local usage = DailyUsage[shopId]
    for _, v in pairs(items) do
        usage[v.item] = math.max(0, (usage[v.item] or 0) + (tonumber(v.count) or 0) * (sign or 1))
    end
end

-- Daily limits are rebuilt from database on first use of the day (survive restart)
local function ensureDay()
    local key = os.date("%Y-%m-%d")
    if DailyKey == key then return end
    DailyKey = key
    DailyUsage = {}
    local rows = MySQL.query.await("SELECT `shop_id`, `items` FROM `pls_mechanic_orders` WHERE `created_at` >= ? AND `status` <> 'cancelled'", { startOfDay() }) or {}
    for _, row in pairs(rows) do
        addUsage(row.shop_id, decodeItems(row.items))
    end
end

--[[
   ____          _
  / __ \        | |
 | |  | |_ __ __| | ___ _ __ ___
 | |  | | '__/ _` |/ _ \ '__/ __|
 | |__| | | | (_| |  __/ |  \__ \
  \____/|_|  \__,_|\___|_|  |___/
]]--

local function buildOrder(row)
    local items = {}
    for _, v in pairs(decodeItems(row.items)) do
        local name = Utils.Item(v.item)
        table.insert(items, { item = name, label = getItemLabel(name), count = tonumber(v.count) or 0 })
    end
    return {
        id = row.id,
        date = row.created_at,
        name = row.name,
        items = items,
        total = row.total,
        mode = row.mode,
        status = row.status,
        deliverAt = row.deliver_at,
    }
end

-- Number of orders awaiting pickup per workshop -> GlobalState for client targets
local function refreshAwaiting()
    local rows = MySQL.query.await("SELECT `shop_id`, COUNT(*) AS `amount` FROM `pls_mechanic_orders` WHERE `status` = 'awaiting_pickup' GROUP BY `shop_id`") or {}
    local data = {}
    for _, row in pairs(rows) do
        data[tostring(row.shop_id)] = tonumber(row.amount) or 0
    end
    GlobalState:set("pls_mechanic_supply", data, true)
end

local function buildSupplierData(src, shop)
    ensureDay()
    local grade = tonumber(BRIDGE.GetPlayerGrade(src)) or 0
    local usage = DailyUsage[shop.id] or {}
    local catalog = {}
    for _, entry in ipairs(Cfg.catalog) do
        if Catalog[entry.item] == entry and (not entry.minGrade or grade >= entry.minGrade) then
            local name = Utils.Item(entry.item)
            table.insert(catalog, {
                item = name,
                label = getItemLabel(name),
                price = entry.price,
                category = entry.category,
                limit = entry.limit,
                remaining = entry.limit and math.max(0, entry.limit - (usage[entry.item] or 0)) or nil,
            })
        end
    end
    local modes = {}
    for _, key in ipairs(ModeOrder) do
        local modeCfg = Cfg.modes[key]
        if modeCfg then
            table.insert(modes, {
                key = key,
                label = locale("supply_mode_"..key),
                multiplier = modeCfg.multiplier,
                minutes = modeCfg.minutes,
                enabled = isModeEnabled(shop, key),
            })
        end
    end
    local orders = {}
    local rows = MySQL.query.await("SELECT * FROM `pls_mechanic_orders` WHERE `shop_id` = ? ORDER BY `id` DESC LIMIT ?", { shop.id, Cfg.historySize or 20 }) or {}
    for _, row in ipairs(rows) do
        table.insert(orders, buildOrder(row))
    end
    return {
        shopId = shop.id,
        shopName = shop.name,
        payFrom = Cfg.payFrom,
        balance = math.floor(getBalance(src, shop.id)),
        catalog = catalog,
        modes = modes,
        orders = orders,
    }
end

-- Validates NUI order items. Returns list {{item = key, count}}, pieces, sum or nil, error
local function parseOrderItems(src, shopId, items)
    if type(items) ~= "table" then return nil, locale("supply_invalid_order") end
    local grade = tonumber(BRIDGE.GetPlayerGrade(src)) or 0
    local merged, order = {}, {}
    local lines = 0
    for _, v in pairs(items) do
        lines = lines + 1
        if type(v) ~= "table" or lines > 100 then return nil, locale("supply_invalid_order") end
        local key = type(v.item) == "string" and (Catalog[v.item] and v.item or Utils.ItemKey(v.item)) or nil
        local entry = key and Catalog[key]
        if not entry or (entry.minGrade and grade < entry.minGrade) then
            return nil, locale("supply_unknown_item", tostring(v.item))
        end
        local count = tonumber(v.count)
        if not count or count ~= math.floor(count) or count < 1 or count > Cfg.maxCount then
            return nil, locale("supply_invalid_order")
        end
        if not merged[key] then
            merged[key] = 0
            table.insert(order, key)
        end
        merged[key] = merged[key] + math.floor(count)
    end
    if #order == 0 then return nil, locale("supply_invalid_order") end

    ensureDay()
    local usage = DailyUsage[shopId] or {}
    local list, pieces, sum = {}, 0, 0
    for _, key in ipairs(order) do
        local entry = Catalog[key]
        local count = merged[key]
        if count > Cfg.maxCount then return nil, locale("supply_invalid_order") end
        if entry.limit and (usage[key] or 0) + count > entry.limit then
            return nil, locale("supply_limit_reached", getItemLabel(Utils.Item(key)), math.max(0, entry.limit - (usage[key] or 0)))
        end
        pieces = pieces + count
        sum = sum + entry.price * count
        table.insert(list, { item = key, count = count })
    end
    return list, pieces, sum
end

local function createOrder(src, shop, mode, items)
    local list, pieces, sum = parseOrderItems(src, shop.id, items)
    if not list then
        return fail(pieces) -- second value is the error message
    end

    local modeCfg = Cfg.modes[mode]
    local total = math.floor(sum * (modeCfg.multiplier or 1.0) + 0.5)
    if mode == "run" and cratesFor(pieces) > RunCfg.maxCrates then
        return fail(locale("supply_too_many_crates", cratesFor(pieces), RunCfg.maxCrates))
    end
    if getBalance(src, shop.id) < total then
        return fail(Cfg.payFrom == "society" and locale("supply_not_enough_society") or locale("not_enough_money"))
    end

    -- reserve daily limits before any await, rollback on failure
    addUsage(shop.id, list, 1)
    if not takeMoney(src, shop.id, total) then
        addUsage(shop.id, list, -1)
        return fail(Cfg.payFrom == "society" and locale("supply_not_enough_society") or locale("not_enough_money"))
    end

    local now = os.time()
    local status = mode == "instant" and "delivered" or (mode == "delayed" and "pending" or "awaiting_pickup")
    local deliverAt = mode == "delayed" and (now + math.floor((modeCfg.minutes or 15) * 60)) or 0
    local id = MySQL.insert.await("INSERT INTO `pls_mechanic_orders` (`shop_id`, `charid`, `name`, `items`, `total`, `mode`, `status`, `deliver_at`, `created_at`) VALUES (?, NULLIF(?, ''), ?, ?, ?, ?, ?, NULLIF(?, 0), ?)", {
        shop.id,
        getCharId(src) or "",
        getPlayerName(src),
        json.encode(list),
        total,
        mode,
        status,
        deliverAt,
        now,
    })
    if not id then
        addUsage(shop.id, list, -1)
        refundMoney(src, shop.id, total)
        return fail(locale("supply_order_failed"))
    end

    local message
    if mode == "instant" then
        deliverToStash(shop.id, list)
        message = locale("supply_order_instant", id, formatMoney(total))
    elseif mode == "delayed" then
        message = locale("supply_order_delayed", id, formatMoney(total), math.floor(modeCfg.minutes or 15))
    else
        refreshAwaiting()
        message = locale("supply_order_run", id, formatMoney(total), cratesFor(pieces))
    end
    log(src, "supply_order", ("Order #%s (%s) for %s, workshop %s"):format(id, mode, formatMoney(total), shop.name), { id = id, shopId = shop.id, mode = mode, items = list, total = total })
    return { ok = true, message = message, data = buildSupplierData(src, shop) }
end

-- Delivers delayed orders whose time has come (called every minute, catches up after restart)
local function deliverDueOrders()
    local rows = MySQL.query.await("SELECT * FROM `pls_mechanic_orders` WHERE `status` = 'pending' AND `deliver_at` IS NOT NULL AND `deliver_at` <= ?", { os.time() }) or {}
    for _, row in ipairs(rows) do
        local shop = Shops.Get(row.shop_id)
        local newStatus = shop and "delivered" or "cancelled"
        local affected = MySQL.update.await("UPDATE `pls_mechanic_orders` SET `status` = ? WHERE `id` = ? AND `status` = 'pending'", { newStatus, row.id })
        if shop and affected and affected > 0 then
            deliverToStash(shop.id, decodeItems(row.items))
            notifyShop(shop.id, locale("supply_delivered_notify", row.id), "success")
        end
    end
end

--[[
   _____                   _
  / ____|                 | |
 | (___  _   _ _ __  _ __ | |_   _   _ __ _   _ _ __
  \___ \| | | | '_ \| '_ \| | | | | | '__| | | | '_ \
  ____) | |_| | |_) | |_) | | |_| | | |  | |_| | | | |
 |_____/ \__,_| .__/| .__/|_|\__, | |_|   \__,_|_| |_|
              | |   | |       __/ |
              |_|   |_|      |___/
 run = { id, src, shopId, orders = {{id, items}}, crates, loaded, delivered, cargo, stage, location, van, netId, plate, expires }
 loaded    = crates taken from the supplier
 cargo     = crates currently in the van (van statebag "pls_supply")
 delivered = crates handed over at the workshop supply point
]]--

local function getPlayerRun(src)
    local runId = PlayerRuns[src]
    return runId and Runs[runId] or nil
end

local function setCargo(run, crates)
    run.cargo = math.max(0, crates)
    if run.van and DoesEntityExist(run.van) then
        Entity(run.van).state:set("pls_supply", { runId = run.id, shopId = run.shopId, crates = run.cargo }, true)
    end
end

local function runPayload(run)
    local location = RunCfg.locations[run.location]
    return {
        id = run.id,
        shopId = run.shopId,
        netId = run.netId,
        plate = run.plate,
        crates = run.crates,
        loaded = run.loaded,
        stage = run.stage,
        pickup = { x = location.coords.x, y = location.coords.y, z = location.coords.z, w = location.coords.w },
        pickupLabel = location.label,
        timeLimit = RunCfg.timeLimit,
    }
end

-- Van of finished run disappears when nobody drives it
local function releaseVan(van)
    if not van or not DoesEntityExist(van) then return end
    ReleasedVans[van] = true
    CreateThread(function()
        Wait((RunCfg.vanDespawn or 20) * 1000)
        local deadline = os.time() + 300
        while DoesEntityExist(van) and GetPedInVehicleSeat(van, -1) ~= 0 and os.time() < deadline do
            Wait(5000)
        end
        if DoesEntityExist(van) then
            DeleteEntity(van)
        end
        ReleasedVans[van] = nil
    end)
end

-- Ends run. completed = goods go to storage, otherwise orders return to "awaiting_pickup"
local function endRun(run, reason, completed, notifyRunner)
    if run.closed then return end
    run.closed = true
    Runs[run.id] = nil
    if PlayerRuns[run.src] == run.id then
        PlayerRuns[run.src] = nil
    end
    if run.van and DoesEntityExist(run.van) then
        Entity(run.van).state:set("pls_supply", nil, true)
    end

    if completed then
        for _, order in ipairs(run.orders) do
            local affected = MySQL.update.await("UPDATE `pls_mechanic_orders` SET `status` = 'delivered' WHERE `id` = ? AND `status` = 'in_transit'", { order.id })
            if affected and affected > 0 then
                deliverToStash(run.shopId, order.items)
            end
        end
        releaseVan(run.van)
    else
        if run.van and DoesEntityExist(run.van) then
            DeleteEntity(run.van)
        end
        for _, order in ipairs(run.orders) do
            MySQL.update.await("UPDATE `pls_mechanic_orders` SET `status` = 'awaiting_pickup' WHERE `id` = ? AND `status` = 'in_transit'", { order.id })
        end
        refreshAwaiting()
    end

    if notifyRunner ~= false and GetPlayerName(run.src) then
        TriggerClientEvent("pls_mechanic:client:supply:runEnded", run.src, run.id, completed == true)
        Shops.Notify(run.src, locale(reason), completed and "success" or "error")
    end
    log(run.src, completed and "supply_run_done" or "supply_run_failed", ("Supply run #%s of workshop %s: %s"):format(run.id, run.shopId, reason), { orders = run.orders, crates = run.crates, delivered = run.delivered })
end

-- Completes the run when all crates were handed over. Returns true when completed.
local function checkCompleted(run, src)
    if run.delivered < run.crates then return false end
    if src ~= run.src then
        Shops.Notify(src, locale("supply_run_completed"), "success")
    end
    endRun(run, "supply_run_completed", true)
    return true
end

local function spawnVan(point)
    local coords = Utils.Vec3(point.coords)
    for _, vehicle in pairs(GetAllVehicles()) do
        if #(GetEntityCoords(vehicle) - coords) < 3.0 then
            return nil, locale("supply_garage_blocked")
        end
    end
    local van = CreateVehicleServerSetter(GetHashKey(RunCfg.vehicle), RunCfg.vehicleType or "automobile", coords.x, coords.y, coords.z + 1.0, (point.heading or 0.0) + 0.0)
    local deadline = GetGameTimer() + 5000
    while (not van or van == 0 or not DoesEntityExist(van)) and GetGameTimer() < deadline do
        Wait(50)
    end
    if not van or van == 0 or not DoesEntityExist(van) then
        return nil, locale("supply_van_failed")
    end
    -- keep it when the owner walks away, deleted by this module (native missing on old artifacts)
    if SetEntityOrphanMode then
        SetEntityOrphanMode(van, 2)
    end
    -- RPC setters need an owner client
    deadline = GetGameTimer() + 3000
    while NetworkGetEntityOwner(van) == -1 and GetGameTimer() < deadline do
        Wait(50)
    end
    local plate = ((RunCfg.platePrefix or "SUPP")..("%04d"):format(math.random(0, 9999))):sub(1, 8)
    SetVehicleNumberPlateText(van, plate)
    -- the owner client may apply the text later, the server plate is trusted right away
    if Vehicles and Vehicles.SetTrustedPlate then
        Vehicles.SetTrustedPlate(van, plate)
    end
    return van, plate
end

local function startRun(src, shopId, pointId)
    if not Shops.HasPermission(src, "supply_run", shopId) then return fail(locale("no_permission")) end
    if getPlayerRun(src) then return fail(locale("supply_run_active")) end
    if not checkRate(src, "run", 5000) then return fail(locale("supply_cooldown")) end
    local shop = Shops.Get(shopId)
    if not isAtPoint(src, shop, pointId, "computer") then return fail(locale("too_far")) end
    if #RunCfg.locations == 0 then return fail(locale("supply_no_pickup")) end
    local garage = findPoint(shop, "garage")
    if not garage then return fail(locale("supply_no_garage")) end
    if not findPoint(shop, "supply") then return fail(locale("supply_no_supply_point")) end

    -- oldest awaiting orders that fit into the van
    local rows = MySQL.query.await("SELECT * FROM `pls_mechanic_orders` WHERE `shop_id` = ? AND `status` = 'awaiting_pickup' ORDER BY `id` ASC LIMIT 50", { shopId }) or {}
    local orders, pieces = {}, 0
    for _, row in ipairs(rows) do
        local items = decodeItems(row.items)
        local orderPieces = countPieces(items)
        if #orders > 0 and cratesFor(pieces + orderPieces) > RunCfg.maxCrates then
            break
        end
        local affected = MySQL.update.await("UPDATE `pls_mechanic_orders` SET `status` = 'in_transit' WHERE `id` = ? AND `status` = 'awaiting_pickup'", { row.id })
        if affected and affected > 0 then
            table.insert(orders, { id = row.id, items = items })
            pieces = pieces + orderPieces
        end
    end
    if #orders == 0 then
        refreshAwaiting()
        return fail(locale("supply_no_awaiting"))
    end

    local van, plateOrError = spawnVan(garage)
    if not van then
        for _, order in ipairs(orders) do
            MySQL.update.await("UPDATE `pls_mechanic_orders` SET `status` = 'awaiting_pickup' WHERE `id` = ? AND `status` = 'in_transit'", { order.id })
        end
        return fail(plateOrError)
    end

    RunCounter = RunCounter + 1
    local run = {
        id = RunCounter,
        src = src,
        shopId = shopId,
        orders = orders,
        crates = math.max(1, cratesFor(pieces)),
        loaded = 0,
        delivered = 0,
        cargo = 0,
        stage = "pickup",
        location = math.random(1, #RunCfg.locations),
        van = van,
        netId = NetworkGetNetworkIdFromEntity(van),
        plate = plateOrError,
        expires = os.time() + RunCfg.timeLimit * 60,
    }
    Runs[run.id] = run
    PlayerRuns[src] = run.id
    setCargo(run, 0)
    refreshAwaiting()
    log(src, "supply_run_start", ("Supply run #%s of workshop %s started (%d crates)"):format(run.id, shop.name, run.crates), { orders = orders })
    return { ok = true, message = locale("supply_run_started", run.crates, math.floor(RunCfg.timeLimit)), run = runPayload(run) }
end

-- Runs of workshop, own run first
local function getShopRuns(shopId, src)
    local list = {}
    for _, run in pairs(Runs) do
        if run.shopId == shopId then
            table.insert(list, run)
        end
    end
    table.sort(list, function(a, b)
        if (a.src == src) ~= (b.src == src) then
            return a.src == src
        end
        return a.id < b.id
    end)
    return list
end

--[[
  _____ _   _ ____  _      _____ _____
 |  __ \ | | |  _ \| |    |_   _/ ____|
 | |__) | | | | |_) | |      | || |
 |  ___/| | | |  _ <| |      | || |
 | |    | |_| | |_) | |____ _| || |____
 |_|     \___/|____/|______|_____\_____|
]]--

-- Supplier price of one piece (Config.Items key), 0 when not in catalog
function SupplyServer.GetPrice(key)
    local entry = Catalog[key]
    return entry and entry.price or 0
end

-- Active supply run of player (read only) or nil
function SupplyServer.GetPlayerRun(src)
    local run = getPlayerRun(src)
    return run and runPayload(run) or nil
end

--[[
   _____      _ _ _                _
  / ____|    | | | |              | |
 | |     __ _| | | |__   __ _  ___| | _____
 | |    / _` | | | '_ \ / _` |/ __| |/ / __|
 | |___| (_| | | | |_) | (_| | (__|   <\__ \
  \_____\__,_|_|_|_.__/ \__,_|\___|_|\_\___/
]]--

-- Returns { ok, data = SupplierData } or { ok = false, message }
lib.callback.register("pls_mechanic:server:supply:get", function(src, shopId)
    shopId = tonumber(shopId)
    if not shopId or not Shops.HasPermission(src, "order", shopId) then return fail(locale("no_permission")) end
    return { ok = true, data = buildSupplierData(src, Shops.Get(shopId)) }
end)

lib.callback.register("pls_mechanic:server:supply:order", function(src, shopId, mode, items)
    shopId = tonumber(shopId)
    if not shopId or not Shops.HasPermission(src, "order", shopId) then return fail(locale("no_permission")) end
    if not checkRate(src, "order", (Cfg.orderCooldown or 3) * 1000) then return fail(locale("supply_cooldown")) end
    local shop = Shops.Get(shopId)
    if type(mode) ~= "string" or not isModeEnabled(shop, mode) then return fail(locale("supply_mode_disabled")) end
    return createOrder(src, shop, mode, items)
end)

-- Orders log for workshop settings (manage_shop or admin), 20 per page
lib.callback.register("pls_mechanic:server:supply:orders", function(src, shopId, page)
    shopId = tonumber(shopId)
    local empty = { orders = {}, pages = 1 }
    if not shopId or not Shops.Get(shopId) then return empty end
    if not Shops.IsAdmin(src) and not Shops.HasPermission(src, "manage_shop", shopId) then return empty end
    local count = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM `pls_mechanic_orders` WHERE `shop_id` = ?", { shopId })) or 0
    local pages = math.max(1, math.ceil(count / PAGE_SIZE))
    page = Utils.Clamp(math.floor(tonumber(page) or 1), 1, pages)
    local rows = MySQL.query.await("SELECT * FROM `pls_mechanic_orders` WHERE `shop_id` = ? ORDER BY `id` DESC LIMIT ? OFFSET ?", { shopId, PAGE_SIZE, (page - 1) * PAGE_SIZE }) or {}
    local orders = {}
    for _, row in ipairs(rows) do
        table.insert(orders, buildOrder(row))
    end
    return { orders = orders, pages = pages }
end)

lib.callback.register("pls_mechanic:server:supply:startRun", function(src, shopId, pointId)
    shopId = tonumber(shopId)
    if not shopId or not Shops.Get(shopId) then return fail(locale("no_permission")) end
    return startRun(src, shopId, pointId)
end)

lib.callback.register("pls_mechanic:server:supply:cancelRun", function(src)
    local run = getPlayerRun(src)
    if not run then return fail(locale("supply_not_runner")) end
    endRun(run, "supply_run_cancelled", false, false)
    return { ok = true, message = locale("supply_run_cancelled") }
end)

-- Runner loads one crate at pickup into the van
lib.callback.register("pls_mechanic:server:supply:load", function(src)
    local run = getPlayerRun(src)
    if not run then return fail(locale("supply_not_runner")) end
    if run.loaded >= run.crates then return fail(locale("supply_loaded_all")) end
    if not checkRate(src, "load", math.floor(RunCfg.loadDuration * 0.75)) then return fail(locale("supply_too_fast")) end
    local pickup = RunCfg.locations[run.location].coords.xyz
    if not run.van or not DoesEntityExist(run.van) then return fail(locale("supply_run_failed_van")) end
    -- crates are carried from the pile to the rear of the van: the runner is at the pile or at the van (checked below at the pickup)
    if not isNear(src, pickup, 6.0) and not Shops.IsNearEntity(src, run.van, 6.0) then return fail(locale("too_far")) end
    if #(GetEntityCoords(run.van) - pickup) > RunCfg.vanDistance then
        return fail(locale("supply_van_too_far", run.plate or "?", math.floor(RunCfg.vanDistance)))
    end
    run.loaded = run.loaded + 1
    setCargo(run, run.cargo + 1)
    if run.loaded >= run.crates then
        run.stage = "deliver"
    end
    return { ok = true, loaded = run.loaded, crates = run.crates, done = run.stage == "deliver" }
end)

-- Crate from van to supply point (any worker of the workshop with supply_run)
lib.callback.register("pls_mechanic:server:supply:unload", function(src, shopId, pointId, netId)
    shopId = tonumber(shopId)
    if not shopId or not Shops.HasPermission(src, "supply_run", shopId) then return fail(locale("no_permission")) end
    if not checkRate(src, "unload", math.floor(RunCfg.unloadDuration * 0.75)) then return fail(locale("supply_too_fast")) end
    local near, point = isAtPoint(src, Shops.Get(shopId), pointId, "supply")
    if not near then return fail(locale("too_far")) end
    local van = Shops.GetEntity(tonumber(netId))
    local state = van and Entity(van).state.pls_supply
    local run = state and Runs[state.runId]
    if not run or run.van ~= van or run.shopId ~= shopId then return fail(locale("supply_no_shipment")) end
    if run.cargo < 1 then return fail(locale("supply_nothing_to_deliver")) end
    if #(GetEntityCoords(van) - Utils.Vec3(point.coords)) > RunCfg.vanDistance then
        return fail(locale("supply_van_too_far", run.plate or "?", math.floor(RunCfg.vanDistance)))
    end
    setCargo(run, run.cargo - 1)
    run.delivered = run.delivered + 1
    local delivered, crates = run.delivered, run.crates
    local completed = checkCompleted(run, src)
    return { ok = true, delivered = delivered, crates = crates, cargo = run.cargo, completed = completed }
end)

-- Crate items (carried by hand / recovered after theft) handed over at supply point
lib.callback.register("pls_mechanic:server:supply:deliverItems", function(src, shopId, pointId)
    shopId = tonumber(shopId)
    if not shopId or not Shops.HasPermission(src, "supply_run", shopId) then return fail(locale("no_permission")) end
    if not checkRate(src, "deliverItems", 1500) then return fail(locale("supply_too_fast")) end
    if not isAtPoint(src, Shops.Get(shopId), pointId, "supply") then return fail(locale("too_far")) end
    -- crates by the rules of the workshop (crates of a courier mission never count)
    local have = math.floor(Shops.CountItem(src, "supply_crate", shopId) or 0)
    if have < 1 then return fail(locale("supply_nothing_to_deliver")) end

    local left, total, completed = have, 0, false
    for _, run in ipairs(getShopRuns(shopId, src)) do
        -- only crates that were loaded and taken out of the van can be handed over
        local outstanding = run.loaded - run.delivered - run.cargo
        local count = math.min(left, outstanding)
        if count > 0 then
            -- checkCompleted can wait for the database, crates could leave the inventory meanwhile
            if (Shops.CountItem(src, "supply_crate", shopId) or 0) < count then break end
            local consumed, removed = Shops.RemoveItems(src, { { item = "supply_crate", count = count } }, 1, shopId)
            if not removed then
                Shops.AddItems(src, consumed, shopId)
                break
            end
            run.delivered = run.delivered + count
            left = left - count
            total = total + count
            if checkCompleted(run, src) then
                completed = true
            end
        end
        if left <= 0 then break end
    end
    if total == 0 then return fail(locale("supply_no_shipment")) end
    log(src, "supply_crates", ("Handed over %d crates at workshop %s"):format(total, shopId))
    return { ok = true, count = total, completed = completed, message = locale("supply_delivered_crates", total) }
end)

-- Anyone can take a crate out of a supply van (manual carry / theft)
lib.callback.register("pls_mechanic:server:supply:takeCrate", function(src, netId)
    if not checkRate(src, "take", math.floor(RunCfg.takeDuration * 0.75)) then return fail(locale("supply_too_fast")) end
    local van = Shops.GetEntity(tonumber(netId))
    local state = van and Entity(van).state.pls_supply
    local run = state and Runs[state.runId]
    if not run or run.van ~= van then return fail(locale("supply_no_crates")) end
    if run.cargo < 1 then return fail(locale("supply_no_crates")) end
    -- locked van can't be emptied (client checks the same for the target)
    if GetVehicleDoorLockStatus(van) > 1 then return fail(locale("supply_no_crates")) end
    if not Shops.IsNearEntity(src, van, 5.0) then return fail(locale("too_far")) end
    if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= 0 then return fail(locale("too_far")) end
    if not BRIDGE.AddItem(src, Utils.Item("supply_crate"), 1) then return fail(locale("supply_inventory_full")) end
    setCargo(run, run.cargo - 1)
    if src ~= run.src and GetPlayerName(run.src) then
        Shops.Notify(run.src, locale("supply_crate_taken"), "error")
    end
    log(src, "supply_take_crate", ("Took a crate from supply van of run #%s (workshop %s)"):format(run.id, run.shopId))
    return { ok = true, message = locale("supply_took_crate") }
end)

--[[
  _______ _                        _
 |__   __| |                      | |
    | |  | |__  _ __ ___  __ _  __| |___
    | |  | '_ \| '__/ _ \/ _` |/ _` / __|
    | |  | | | | | |  __/ (_| | (_| \__ \
    |_|  |_| |_|_|  \___|\__,_|\__,_|___/
]]--

CreateThread(function()
    while not Shops.IsLoaded() do
        Wait(500)
    end
    -- runs live in memory only, restart returns picked orders to the queue
    MySQL.update.await("UPDATE `pls_mechanic_orders` SET `status` = 'awaiting_pickup' WHERE `status` = 'in_transit'")
    refreshAwaiting()
    while true do
        local ok, err = pcall(deliverDueOrders)
        if not ok then
            print("[pls_mechanic] delayed orders error: "..tostring(err))
        end
        Wait(60000)
    end
end)

-- Time limit and lost van of active runs
CreateThread(function()
    while true do
        Wait(next(Runs) and 5000 or 15000)
        local now = os.time()
        local failed = {}
        for _, run in pairs(Runs) do
            if now >= run.expires then
                table.insert(failed, { run = run, reason = "supply_run_failed_timeout" })
            elseif not run.van or not DoesEntityExist(run.van) then
                table.insert(failed, { run = run, reason = "supply_run_failed_van" })
            end
        end
        for _, v in ipairs(failed) do
            endRun(v.run, v.reason, false)
        end
    end
end)

AddEventHandler("playerDropped", function()
    local src = source
    Cooldowns[src] = nil
    local run = getPlayerRun(src)
    if run then
        endRun(run, "supply_run_failed_timeout", false, false)
    end
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, run in pairs(Runs) do
        if run.van and DoesEntityExist(run.van) then
            DeleteEntity(run.van)
        end
    end
    for van in pairs(ReleasedVans) do
        if DoesEntityExist(van) then
            DeleteEntity(van)
        end
    end
end)
