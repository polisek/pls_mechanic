--[[
  ______   _       _
 |  ____| | |     | |
 | |__ ___| |_ ___| |__
 |  __/ _ \ __/ __| '_ \
 | | |  __/ || (__| | | |
 |_|  \___|\__\___|_| |_|

 Parts fetching during repair / tuning (Config.Fetch). Parts don't have to be in the inventory at the start,
 a step without its parts / tools pauses (Fetch.Wait) until the mechanic brings them from the workshop storage
 and continues with the target on the vehicle. One wait at a time.

 Parts are counted by the rules of the workshop (client/inventory.lua: legal = clean only, illegal = stolen too).

 Fetch.Enabled() -> bool
 Fetch.Missing(items, tools, shopId?) -> { { item, need, have, missing, tool } }   only entries still missing, {} = ready
 Fetch.CheckStart(shopId, needed, tools) -> ok, problem, info                 needed = { [key] = count }, call in a thread
 Fetch.Wait(req) -> "ready" | "cancelled" | "timeout" | "too_far" | "no_vehicle"   blocks the calling thread
 Fetch.IsWaiting(owner?) -> bool
 Fetch.GetOverlay() -> WorkflowWaiting | nil                                  "waiting" field of the workflow overlay
 Fetch.Cancel()
]]--

Fetch = {}

local Current = nil             -- running wait (Fetch.Wait)
local StockCache = {}           -- [shopId] = { time, supported, stock = { [key] = count } }
local StockPending = {}         -- [shopId] = true while a stock request runs
local Weights = nil             -- [itemName] = kg per piece
local TakeUnsupported = false   -- inventory can't remove stash items, quick take is hidden
local ResumeTarget = nil

local TICK = 250
local RECOUNT_INTERVAL = 1000
local STOCK_CACHE = 2000                -- ms, stock numbers are reused this long
local STOCK_UNSUPPORTED_CACHE = 60000
local STOCK_REFRESH_NEAR = 2000         -- ms, stock refresh while waiting near the storage point
local STOCK_REFRESH_FAR = 6000
local STORAGE_NEAR = 25.0
local WARN_DISTANCE = 0.8               -- part of maxDistance, warning notify
local MAX_STOCK_KEYS = 40
local MAX_TAKE_ENTRIES = 20
local MAX_TAKE_COUNT = 50
local STORAGE_BLIP = { sprite = 478, colour = 5, scale = 0.9 }   -- radar_contraband (box)
local VEHICLE_BLIP = { sprite = 225, colour = 3, scale = 0.8 }   -- radar_gang_vehicle
local WEIGHT_IN_GRAMS = { ox_inventory = true, qb_inventory = true, quasar_inventory = true }

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

local function cfg()
    return Config.Fetch or {}
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if not ok then
        print("[pls_mechanic] Fetch callback error: "..tostring(result))
        return nil
    end
    return result
end

-- Parts by the rules of the workshop (shopId nil = current shop), tools with any metadata
local function countItem(key, tool, shopId)
    local ok, count
    if tool and Core.CountTool then
        ok, count = pcall(Core.CountTool, key)
    else
        ok, count = pcall(Core.CountItem, key, shopId)
    end
    return ok and math.floor(tonumber(count) or 0) or 0
end

local function itemLabel(key)
    return Core.GetItemLabel(Utils.Item(key))
end

-- { { item, <field> } } -> "2x Brake pads, 1x Car jack"
local function listText(list, field)
    local parts = {}
    for _, v in ipairs(list or {}) do
        parts[#parts + 1] = math.floor(tonumber(v[field or "missing"]) or 0).."x "..itemLabel(v.item)
    end
    return table.concat(parts, ", ")
end

-- kg per piece from inventory item list (grams), nil = unknown
local function getWeight(itemName)
    if not WEIGHT_IN_GRAMS[BRIDGE.Inventory] then return nil end
    if not Weights then
        local ok, items = pcall(BRIDGE.GetItems)
        if not ok or type(items) ~= "table" or next(items) == nil then return nil end
        Weights = {}
        for name, data in pairs(items) do
            local grams = type(data) == "table" and tonumber(data.weight) or nil
            if grams and grams > 0 then
                Weights[name] = Utils.Round(grams / 1000, 2)
            end
        end
    end
    return Weights[itemName]
end

-- All parts / tools of a step with counts in the inventory, parts first: { { item, need, have, missing, tool } }
local function evaluate(items, tools, shopId)
    local list, index = {}, {}
    for _, v in ipairs(items or {}) do
        local key = type(v) == "table" and v.item or nil
        local count = type(v) == "table" and math.floor(tonumber(v.count) or 0) or 0
        if type(key) == "string" and count > 0 then
            if index[key] then
                index[key].need = index[key].need + count
            else
                index[key] = { item = key, need = count, tool = false }
                list[#list + 1] = index[key]
            end
        end
    end
    for _, key in ipairs(tools or {}) do
        if type(key) == "string" and not index[key] then
            index[key] = { item = key, need = 1, tool = true }
            list[#list + 1] = index[key]
        end
    end
    for _, entry in ipairs(list) do
        entry.have = countItem(entry.item, entry.tool, shopId)
        entry.missing = math.max(0, entry.need - entry.have)
    end
    return list
end

local function missingOf(list)
    local result = {}
    for _, entry in ipairs(list or {}) do
        if entry.missing > 0 then
            result[#result + 1] = { item = entry.item, need = entry.need, have = entry.have, missing = entry.missing, tool = entry.tool }
        end
    end
    return result
end

local function keysOf(list)
    local keys = {}
    for _, entry in ipairs(list or {}) do
        if #keys >= MAX_STOCK_KEYS then break end
        keys[#keys + 1] = entry.item
    end
    return keys
end

local function getStoragePoint(shopId)
    local shop = shopId and Core.GetShop(shopId)
    for _, point in pairs(shop and shop.points or {}) do
        if point.type == "storage" and point.coords then
            return point
        end
    end
    return nil
end

--[[
   _____ _             _
  / ____| |           | |
 | (___ | |_ ___   ___| | __
  \___ \| __/ _ \ / __| |/ /
  ____) | || (_) | (__|   <
 |_____/ \__\___/ \___|_|\_\

 Counts in the workshop storage from the server (cached, one request per shop at a time)
]]--

local function stockFresh(data, keys)
    if not data then return false end
    local age = GetGameTimer() - data.time
    if not data.supported then return age < STOCK_UNSUPPORTED_CACHE end
    if age >= STOCK_CACHE then return false end
    for _, key in ipairs(keys) do
        if data.stock[key] == nil then return false end
    end
    return true
end

-- Blocking (call in a thread). Returns cache entry or nil
local function requestStock(shopId, keys)
    if StockPending[shopId] then
        local timeout = GetGameTimer() + 5000
        while StockPending[shopId] and GetGameTimer() < timeout do
            Wait(50)
        end
        return StockCache[shopId]
    end
    StockPending[shopId] = true
    local ok, response = pcall(lib.callback.await, "pls_mechanic:server:fetch:stock", false, shopId, keys)
    StockPending[shopId] = nil
    -- nil response = server rate limit, the old numbers stay
    if ok and type(response) == "table" then
        local stock = {}
        for key, count in pairs(type(response.stock) == "table" and response.stock or {}) do
            stock[key] = tonumber(count)
        end
        StockCache[shopId] = { time = GetGameTimer(), supported = response.supported == true, stock = stock }
    end
    return StockCache[shopId]
end

local function getStock(shopId, keys)
    if not shopId or #keys == 0 then return nil end
    local data = StockCache[shopId]
    if stockFresh(data, keys) then return data end
    return requestStock(shopId, keys) or data
end

local function stockSignature(wait)
    local data = wait.shopId and StockCache[wait.shopId]
    if not data then return "" end
    local parts = { tostring(data.supported) }
    for _, key in ipairs(wait.keys) do
        parts[#parts + 1] = tostring(data.stock[key])
    end
    return table.concat(parts, ";")
end

--[[
  ____  _ _
 |  _ \| (_)
 | |_) | |_ _ __  ___
 |  _ <| | | '_ \/ __|
 | |_) | | | |_) \__ \
 |____/|_|_| .__/|___/
           | |
           |_|
]]--

local function setupBlip(blip, def, label)
    SetBlipSprite(blip, def.sprite)
    SetBlipColour(blip, def.colour)
    SetBlipScale(blip, def.scale)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(blip)
    return blip
end

local function removeBlip(blip)
    if blip and DoesBlipExist(blip) then
        RemoveBlip(blip)
    end
end

-- Route to the storage while parts are missing, back to the vehicle when everything is in the inventory
local function updateRoute(wait)
    if cfg().storageBlip == false then return end
    if wait.storageBlip and DoesBlipExist(wait.storageBlip) then
        SetBlipRoute(wait.storageBlip, not wait.ready)
        SetBlipRouteColour(wait.storageBlip, STORAGE_BLIP.colour)
    end
    if wait.vehicleBlip and DoesBlipExist(wait.vehicleBlip) then
        SetBlipRoute(wait.vehicleBlip, wait.ready == true)
        SetBlipRouteColour(wait.vehicleBlip, VEHICLE_BLIP.colour)
    end
end

local function createVehicleBlip(wait)
    removeBlip(wait.vehicleBlip)
    wait.vehicleBlip = nil
    if wait.vehicle and DoesEntityExist(wait.vehicle) then
        wait.vehicleBlip = setupBlip(AddBlipForEntity(wait.vehicle), VEHICLE_BLIP, locale("fetch_blip_vehicle"))
    end
end

local function createBlips(wait)
    if cfg().storageBlip ~= false then
        local point = getStoragePoint(wait.shopId)
        if point then
            local coords = Utils.Vec3(point.coords)
            wait.storageBlip = setupBlip(AddBlipForCoord(coords.x, coords.y, coords.z), STORAGE_BLIP, locale("fetch_blip_storage"))
        end
    end
    createVehicleBlip(wait)
    updateRoute(wait)
end

local function removeBlips(wait)
    removeBlip(wait.storageBlip)
    removeBlip(wait.vehicleBlip)
    wait.storageBlip, wait.vehicleBlip = nil, nil
end

--[[
 __          __   _ _   _
 \ \        / /  (_) | (_)
  \ \  /\  / /_ _ _| |_ _ _ __   __ _
   \ \/  \/ / _` | | __| | '_ \ / _` |
    \  /\  / (_| | | |_| | | | | (_| |
     \/  \/ \__,_|_|\__|_|_| |_|\__, |
                                 __/ |
                                |___/
]]--

-- Owner re-sends its overlay (includes Fetch.GetOverlay())
local function update(wait)
    if Current == wait and not wait.result then
        safeCall(wait.onUpdate)
    end
end

local function stopCarry(wait)
    if wait.carry then
        Anim.StopCarry(wait.carry)
        wait.carry = nil
    end
end

-- Vehicle of the wait, found again by net id when the handle changed (out of scope and back)
local function resolveVehicle(wait)
    if wait.vehicle and DoesEntityExist(wait.vehicle) then return wait.vehicle end
    if wait.netId and NetworkDoesEntityExistWithNetworkId(wait.netId) then
        local vehicle = NetToVeh(wait.netId)
        if vehicle ~= 0 and DoesEntityExist(vehicle) then
            wait.vehicle = vehicle
            if wait.started then
                createVehicleBlip(wait)
                updateRoute(wait)
            end
            return vehicle
        end
    end
    return nil
end

local function isWaitVehicle(wait, entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if entity == wait.vehicle then return true end
    return wait.netId ~= nil and NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity) == wait.netId
end

-- Counts the inventory again, overlay update when the missing list / ready flag changed
local function recount(wait, force)
    local list = evaluate(wait.items, wait.tools, wait.shopId)
    if Current ~= wait or wait.result then return end
    local ready, sig = true, {}
    for _, entry in ipairs(list) do
        if entry.missing > 0 then ready = false end
        sig[#sig + 1] = entry.item..":"..math.min(entry.have, entry.need)
    end
    sig = table.concat(sig, ";")
    local changed = force or sig ~= wait.sig or ready ~= wait.ready
    wait.list, wait.ready, wait.sig = list, ready, sig
    if ready and not wait.readyNotified then
        wait.readyNotified = true
        Core.Notify(locale("fetch_ready"), "success")
    end
    if changed then
        updateRoute(wait)
        update(wait)
    end
end

-- Stock numbers for the overlay (async, never two requests at once)
local function refreshStock(wait)
    if wait.stockBusy or not wait.shopId or #wait.keys == 0 then return end
    wait.stockBusy = true
    CreateThread(function()
        local before = stockSignature(wait)
        getStock(wait.shopId, wait.keys)
        wait.stockBusy = false
        if stockSignature(wait) ~= before then
            update(wait)
        end
    end)
end

local function nearStorage(wait, coords)
    local point = getStoragePoint(wait.shopId)
    return point ~= nil and #(coords - Utils.Vec3(point.coords)) <= STORAGE_NEAR
end

local function run(wait)
    Core.Notify(locale("fetch_waiting", listText(missingOf(wait.list))), "inform")
    createBlips(wait)
    recount(wait, true)
    refreshStock(wait)

    local maxDistance = tonumber(cfg().maxDistance) or 0
    local nextCount = GetGameTimer() + RECOUNT_INTERVAL
    local nextStock = GetGameTimer() + STOCK_REFRESH_NEAR
    while not wait.result do
        Wait(TICK)
        if wait.result then break end
        if safeCall(wait.isCancelled) == true then
            wait.result = "cancelled"
            break
        end
        local vehicle = resolveVehicle(wait)
        if not vehicle then
            wait.result = "no_vehicle"
            break
        end
        local coords = GetEntityCoords(cache.ped)
        if maxDistance > 0 then
            local distance = #(coords - GetEntityCoords(vehicle))
            if distance > maxDistance then
                wait.result = "too_far"
                break
            end
            if distance > maxDistance * WARN_DISTANCE then
                if not wait.warned then
                    wait.warned = true
                    Core.Notify(locale("fetch_too_far_warn"), "error")
                end
            elseif distance < maxDistance * (WARN_DISTANCE - 0.1) then
                wait.warned = false
            end
        end
        local now = GetGameTimer()
        if wait.deadline and now >= wait.deadline then
            wait.result = "timeout"
            break
        end
        if now >= nextCount then
            nextCount = now + RECOUNT_INTERVAL
            recount(wait)
        end
        if now >= nextStock then
            nextStock = now + (nearStorage(wait, coords) and STOCK_REFRESH_NEAR or STOCK_REFRESH_FAR)
            refreshStock(wait)
        end
    end
end

-- Blips, carry and state. Called on every end of a wait.
local function finish(wait)
    wait.result = wait.result or "cancelled"
    removeBlips(wait)
    stopCarry(wait)
    if Current == wait then
        Current = nil
    end
end

--[[
          _____ _____
    /\   |  __ \_   _|
   /  \  | |__) || |
  / /\ \ |  ___/ | |
 / ____ \| |    _| |_
/_/    \_\_|   |_____|
]]--

function Fetch.Enabled()
    return type(Config.Fetch) == "table" and Config.Fetch.enabled ~= false
end

-- Parts of one step still missing in the inventory. items = { {item = key, count = n} } (already multiplied), tools = { key }
-- Returns { { item = key, need, have, missing, tool } }, empty table = ready
function Fetch.Missing(items, tools, shopId)
    return missingOf(evaluate(items, tools, shopId))
end

-- Start check (repair / tuning preflight), call in a thread. needed = { [key] = count } summed over all steps, tools = { key }
-- Returns ok, problem, info:
--   ok = false + problem when Config.Fetch.requireStock and a part / tool is neither in the inventory nor in the storage
--   info = text for the caller ("inform") when some parts have to be fetched from the storage
function Fetch.CheckStart(shopId, needed, tools)
    shopId = tonumber(shopId) or Core.GetDutyShopId() or Core.GetMyShopId()
    local items = {}
    for key, value in pairs(needed or {}) do
        if type(value) == "table" then
            items[#items + 1] = { item = value.item, count = value.count }  -- list format { {item, count} }
        else
            items[#items + 1] = { item = key, count = value }
        end
    end
    table.sort(items, function(a, b) return tostring(a.item) < tostring(b.item) end)

    local missing = Fetch.Missing(items, tools, shopId)
    if #missing == 0 then return true, nil, nil end

    -- unknown stock (inventory without stash support, no shop) never blocks
    local data = getStock(shopId, keysOf(missing))
    local lacking = {}
    if data and data.supported then
        for _, entry in ipairs(missing) do
            local stock = data.stock[entry.item]
            if stock and stock < entry.missing then
                lacking[#lacking + 1] = { item = entry.item, missing = entry.missing - stock }
            end
        end
    end
    if cfg().requireStock and #lacking > 0 then
        return false, locale("fetch_no_stock", listText(lacking)), nil
    end
    return true, nil, locale("fetch_preflight_info", listText(missing))
end

-- Blocks the calling thread until the step parts are in the inventory AND the mechanic used "Continue" on the vehicle.
-- req = { owner, vehicle, netId, shopId?, label, items, tools, isCancelled?, onUpdate? } (see mechanic-fetch-spec.md)
function Fetch.Wait(req)
    if type(req) ~= "table" or Current then return "cancelled" end
    local shopId = tonumber(req.shopId) or Core.GetDutyShopId() or Core.GetMyShopId()
    local list = evaluate(req.items, req.tools, shopId)
    if #missingOf(list) == 0 then return "ready" end
    if Current then return "cancelled" end   -- other wait started while counting

    local timeout = (tonumber(cfg().timeout) or 0) * 60000
    local wait = {
        owner = req.owner,
        vehicle = req.vehicle,
        netId = req.netId,
        shopId = shopId,
        label = req.label or "",
        items = req.items or {},
        tools = req.tools or {},
        isCancelled = req.isCancelled,
        onUpdate = req.onUpdate,
        list = list,
        keys = keysOf(list),
        ready = false,
        deadline = timeout > 0 and GetGameTimer() + timeout or nil,
    }
    if not wait.netId and wait.vehicle and DoesEntityExist(wait.vehicle) and NetworkGetEntityIsNetworked(wait.vehicle) then
        wait.netId = NetworkGetNetworkIdFromEntity(wait.vehicle)
    end
    if not resolveVehicle(wait) then return "no_vehicle" end

    Current = wait
    wait.started = GetGameTimer()
    local ok, err = pcall(run, wait)
    if not ok then
        print("[pls_mechanic] Fetch.Wait error: "..tostring(err))
    end
    finish(wait)
    return wait.result
end

-- owner nil = any
function Fetch.IsWaiting(owner)
    local wait = Current
    return wait ~= nil and not wait.result and (owner == nil or wait.owner == owner)
end

-- NUI "waiting" payload of the workflow overlay, nil when not waiting.
-- items = all parts / tools of the step (have capped at need, stock nil = unknown, weight = kg per piece)
function Fetch.GetOverlay()
    local wait = Current
    if not wait or wait.result then return nil end
    local data = wait.shopId and StockCache[wait.shopId]
    local supported = data ~= nil and data.supported == true
    local items = {}
    for _, entry in ipairs(wait.list or {}) do
        local itemName = Utils.Item(entry.item)
        items[#items + 1] = {
            key = entry.item,
            label = Core.GetItemLabel(itemName),
            need = entry.need,
            have = math.min(entry.have, entry.need),
            stock = supported and data.stock[entry.item] or nil,
            tool = entry.tool,
            weight = getWeight(itemName),
        }
    end
    return {
        label = wait.label,
        items = items,
        ready = wait.ready == true,
        hint = locale(wait.ready and "fetch_hint_ready" or "fetch_hint_fetch"),
        remaining = wait.deadline and math.max(0, math.ceil((wait.deadline - GetGameTimer()) / 1000)) or nil,
    }
end

-- Ends a running Fetch.Wait as "cancelled" (within 250 ms)
function Fetch.Cancel()
    local wait = Current
    if wait and not wait.result then
        wait.result = "cancelled"
    end
end

--[[
  _______                   _
 |__   __|                 | |
    | | __ _ _ __ __ _  ___| |_ ___
    | |/ _` | '__/ _` |/ _ \ __/ __|
    | | (_| | | | (_| |  __/ |_\__ \
    |_|\__,_|_|  \__, |\___|\__|___/
                  __/ |
                 |___/
]]--

-- "Continue" on the vehicle: everything in the inventory -> the wait ends as "ready"
local function resume(owner)
    local wait = Current
    if not wait or wait.result or wait.owner ~= owner or wait.resuming then return end
    wait.resuming = true
    local missing = Fetch.Missing(wait.items, wait.tools, wait.shopId)
    wait.resuming = false
    if Current ~= wait or wait.result then return end
    if #missing > 0 then
        Core.Notify(locale("fetch_still_missing", listText(missing)), "error")
        recount(wait)
        return
    end
    stopCarry(wait)
    wait.result = "ready"
end

local function resumeOption(owner, label, icon)
    return {
        name = "pls_mechanic_fetch_resume_"..owner,
        label = locale(label),
        icon = icon,
        distance = tonumber(cfg().resumeDistance) or 4.0,
        canInteract = function(entity)
            local wait = Current
            if not wait or wait.result or wait.owner ~= owner then return false end
            return isWaitVehicle(wait, entity)
        end,
        onSelect = function()
            CreateThread(function()
                resume(owner)
            end)
        end,
    }
end

-- Storage point action: moves the missing parts of the step from the storage to the inventory
local function quickTake(shop, point)
    local wait = Current
    if not wait or wait.result or wait.taking or wait.shopId ~= shop.id then return end
    local missing = Fetch.Missing(wait.items, wait.tools, wait.shopId)
    if #missing == 0 then
        recount(wait)
        Core.Notify(locale("fetch_nothing_missing"), "inform")
        return
    end
    local list = {}
    for _, entry in ipairs(missing) do
        if #list >= MAX_TAKE_ENTRIES then break end
        list[#list + 1] = { item = entry.item, count = math.min(entry.missing, MAX_TAKE_COUNT) }
    end

    wait.taking = true
    local ok, response = pcall(lib.callback.await, "pls_mechanic:server:fetch:take", false, shop.id, list)
    wait.taking = false
    StockCache[shop.id] = nil
    if not ok or type(response) ~= "table" then
        Core.Notify(locale("fetch_take_failed"), "error")
        return
    end
    if not response.ok then
        if response.unsupported then TakeUnsupported = true end
        Core.Notify(response.message or locale("fetch_take_failed"), "error")
        return
    end

    local taken = type(response.taken) == "table" and response.taken or {}
    local notInStock = type(response.missing) == "table" and response.missing or {}
    local full = type(response.full) == "table" and response.full or {}
    if #taken > 0 then Core.Notify(locale("fetch_taken", listText(taken, "count")), "success") end
    if #notInStock > 0 then Core.Notify(locale("fetch_not_in_stock", listText(notInStock, "count")), "error") end
    if #full > 0 then Core.Notify(locale("fetch_cannot_carry", listText(full, "count")), "error") end

    if #taken > 0 and Current == wait and not wait.result then
        stopCarry(wait)
        if point and point.coords then
            Anim.Face(Utils.Vec3(point.coords))
        end
        Anim.Play("pickup")
        local carry = cfg().carry
        if carry and Current == wait and not wait.result then
            wait.carry = Anim.Carry(carry)
        end
    end
    if Current == wait and not wait.result then
        recount(wait, true)
        refreshStock(wait)
    end
end

CreateThread(function()
    if not Fetch.Enabled() then return end
    ResumeTarget = BRIDGE.AddGlobalVehicleTarget({
        resumeOption("repair", "fetch_resume_repair", "fa-solid fa-screwdriver-wrench"),
        resumeOption("tuning", "fetch_resume_tuning", "fa-solid fa-gauge-high"),
    })
    -- registered after client/shops.lua (next tick), "Open storage" stays the first option
    if cfg().quickTake ~= false then
        ShopPoints.RegisterAction("storage", {
            label = locale("fetch_take_target"),
            icon = "fa-solid fa-dolly",
            perm = "storage",
            canInteract = function(shop)
                local wait = Current
                if TakeUnsupported or not wait or wait.result or wait.taking or wait.ready then return false end
                if wait.shopId ~= shop.id then return false end
                local data = StockCache[wait.shopId]
                return not (data and data.supported == false)
            end,
            onSelect = quickTake,
        })
    end
end)

--[[
   _____ _
  / ____| |
 | (___ | |_ ___  _ __
  \___ \| __/ _ \| '_ \
  ____) | || (_) | |_) |
 |_____/ \__\___/| .__/
                 | |
                 |_|
]]--

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if Current then
        finish(Current)
    end
    if ResumeTarget then
        BRIDGE.RemoveGlobalVehicleTarget(ResumeTarget)
        ResumeTarget = nil
    end
end)
